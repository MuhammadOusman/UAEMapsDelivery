// ignore_for_file: unused_field, unused_element, avoid_print, use_build_context_synchronously

import 'dart:typed_data';

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/search.dart';
import 'package:here_sdk/routing.dart' as here;
import 'package:geolocator/geolocator.dart';
import 'package:here_offline_app/app_theme.dart';

// Trip lifecycle states (simplified)
enum TripStatus { idle, onboard, completed }

class DeliveryPlannerScreen extends StatefulWidget {
  const DeliveryPlannerScreen({Key? key}) : super(key: key);

  @override
  State<DeliveryPlannerScreen> createState() => _DeliveryPlannerScreenState();
}

class _DeliveryPlannerScreenState extends State<DeliveryPlannerScreen> {
  HereMapController? _hereMapController;
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  GeoCoordinates? _pickupCoords;
  GeoCoordinates? _dropCoords;
  GeoCoordinates? _userCoords; // current device location (shown on map)

  late SearchEngine _searchEngine;
  late here.RoutingEngine _routingEngine;

  final List<MapMarker> _mapMarkers = [];
  final List<MapPolyline> _mapPolylines = [];

  String _routeInfo = '';
  bool _calculatingRoute = false;

  // Navigation / trip state
  bool _navigating = false;
  StreamSubscription<Position>? _positionSubscription;
  MapMarker? _userMarker;
  double _totalDistanceTravelled = 0.0; // meters
  DateTime? _tripStartTime;
  DateTime? _tripEndTime;
  GeoCoordinates? _lastPositionCoords;
  here.Route? _currentRoute;
  int _currentManeuverIndex = 0;
  String _currentManeuverInstruction = '';

  // Trip lifecycle
  TripStatus _tripStatus = TripStatus.idle;

  // UI/UX state
  bool _showCenterPicker = false; // show center-pin for pickup/drop confirm
  bool _selectingPickup = false;

  // Inline suggest state
  List<Suggestion> _suggestions = [];
  bool _suggestLoading = false;
  String _focusedField = ''; // 'pickup' or 'drop'
  Timer? _suggestDebounce;

  @override
  void initState() {
    super.initState();
    try {
      _searchEngine = SearchEngine();
    } on Exception catch (e) {
      print('SearchEngine init failed: $e');
    }
    try {
      _routingEngine = here.RoutingEngine();
    } on Exception catch (e) {
      print('RoutingEngine init failed: $e');
    }

    // Initialize location and show user's current position on the map
    _initLocation();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  void _onMapCreated(HereMapController controller) {
    _hereMapController = controller;

    // Center on UAE
    const double distanceToEarthInMeters = 8000;
    MapMeasure mapMeasureZoom = MapMeasure(MapMeasureKind.distanceInMeters, distanceToEarthInMeters);
    controller.camera.lookAtPointWithMeasure(GeoCoordinates(25.2048, 55.2708), mapMeasureZoom);

    final scheme = Theme.of(context).brightness == Brightness.dark ? MapScheme.normalNight : MapScheme.normalDay;
    controller.mapScene.loadSceneForMapScheme(scheme, (MapError? error) {
      if (error != null) {
        print('MapScene load failed: $error');
      }
    });

    // reload scene when theme changes
    final themeListener = () {
      final useDark = AppTheme.mode.value == ThemeMode.dark || (AppTheme.mode.value == ThemeMode.system && Theme.of(context).brightness == Brightness.dark);
      final newScheme = useDark ? MapScheme.normalNight : MapScheme.normalDay;
      try { controller.mapScene.loadSceneForMapScheme(newScheme, (MapError? err) {}); } catch (_) {}
    };
    AppTheme.mode.addListener(themeListener);
    // remove listener when disposing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        () async {
          // ensure removal when leaving
          await Future<void>.delayed(Duration.zero);
          try { AppTheme.mode.removeListener(themeListener); } catch (_) {}
        }();
      }
    });
  }



  Future<Place?> _fetchPlaceById(String id) async {
    Place? found;
    final query = PlaceIdQuery(id);
    final completer = Completer<void>();
    _searchEngine.searchByPlaceIdWithLanguageCodeExtended(query, null, (SearchError? error, Place? place, ResponseDetails? r) {
      if (error == null && place != null) {
        found = place;
      }
      completer.complete();
    });
    await completer.future;
    return found;
  }

  void _onQueryChanged(String field, String query) {
    _suggestDebounce?.cancel();
    if (query.isEmpty) {
      setState(() { _suggestions = []; });
      return;
    }
    _suggestLoading = true;
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () {
      final textQuery = TextQuery.withArea(query, TextQueryArea.withCountries([CountryCode.are], GeoCoordinates(25.2048, 55.2708)));
      final options = SearchOptions();
      _searchEngine.suggestExtended(textQuery, options, (SearchError? error, List<Suggestion>? suggestions, ResponseDetails? r) {
        setState(() {
          _suggestLoading = false;
          _suggestions = suggestions ?? [];
          _focusedField = field;
        });
      });
    });
  }

  void _confirmCenterAsSelection() {
    // use camera center
    final box = _hereMapController?.camera.boundingBox;
    if (box == null) return;
    final northEast = box.northEastCorner;
    final southWest = box.southWestCorner;
    final lat = (northEast.latitude + southWest.latitude) / 2.0;
    final lon = (northEast.longitude + southWest.longitude) / 2.0;
    final coords = GeoCoordinates(lat, lon);
    setState(() {
      if (_focusedField == 'pickup') {
        _pickupCoords = coords;
        _pickupController.text = 'Selected location';
      } else {
        _dropCoords = coords;
        _dropController.text = 'Selected location';
      }
      _showCenterPicker = false;
      _suggestions = [];
    });
    _updateMarkersAndCamera();
  }

  void _updateMarkersAndCamera() {
    if (_hereMapController == null) return;

    // Clear existing markers
    for (final m in _mapMarkers) {
      _hereMapController!.mapScene.removeMapMarker(m);
    }
    _mapMarkers.clear();

    if (_pickupCoords != null) {
      _addMarker(_pickupCoords!, '#2E86AB');
    }
    if (_dropCoords != null) {
      _addMarker(_dropCoords!, '#E63946');
    }

    // Zoom to show both
    if (_pickupCoords != null && _dropCoords != null) {
      final north = max(_pickupCoords!.latitude, _dropCoords!.latitude);
      final south = min(_pickupCoords!.latitude, _dropCoords!.latitude);
      final east = max(_pickupCoords!.longitude, _dropCoords!.longitude);
      final west = min(_pickupCoords!.longitude, _dropCoords!.longitude);
      final box = GeoBox(GeoCoordinates(north, east), GeoCoordinates(south, west));
      _hereMapController!.camera.lookAtAreaWithGeoOrientationAndViewRectangle(box, GeoOrientationUpdate(0, 0), Rectangle2D(Point2D(0,0), Size2D(300, 300)));
    } else if (_pickupCoords != null) {
      _hereMapController!.camera.lookAtPoint(_pickupCoords!);
    } else if (_dropCoords != null) {
      _hereMapController!.camera.lookAtPoint(_dropCoords!);
    }
  }

  void _addMarker(GeoCoordinates coords, String colorHex) {
    // Simple SVG circle as marker
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">
      <circle cx="24" cy="24" r="14" fill="$colorHex" stroke="#ffffff" stroke-width="3" />
    </svg>''';
    final data = Uint8List.fromList(svg.codeUnits);
    final img = MapImage.withImageDataImageFormatWidthAndHeight(data, ImageFormat.svg, 48, 48);
    final marker = MapMarker(coords, img);
    _hereMapController!.mapScene.addMapMarker(marker);
    _mapMarkers.add(marker);
  }

  void _clearRoute() {
    _routeInfo = '';
    for (final poly in _mapPolylines) {
      _hereMapController?.mapScene.removeMapPolyline(poly);
    }
    _mapPolylines.clear();
    setState(() {});
  }

  void _clearAll() {
    _clearRoute();
    for (final m in _mapMarkers) {
      _hereMapController?.mapScene.removeMapMarker(m);
    }
    _mapMarkers.clear();
    _pickupCoords = null;
    _dropCoords = null;
    _pickupController.clear();
    _dropController.clear();
    setState(() {});
  }

  Future<here.Route?> _calculateRoute() async {
    if (_pickupCoords == null || _dropCoords == null) return null;
    if (_hereMapController == null) return null;
    _clearRoute();

    final start = here.Waypoint.withDefaults(_pickupCoords!);
    final dest = here.Waypoint.withDefaults(_dropCoords!);
    final waypoints = [start, dest];

    setState(() { _calculatingRoute = true; });

    here.CarOptions carOptions = here.CarOptions();
    carOptions.routeOptions.enableTolls = false;

    final completer = Completer<here.Route?>();
    _routingEngine.calculateCarRoute(waypoints, carOptions, (here.RoutingError? error, List<here.Route>? routes) {
      setState(() { _calculatingRoute = false; });
      if (error != null || routes == null || routes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route calculation failed')));
        completer.complete(null);
        return;
      }
      final route = routes.first;
      _currentRoute = route;
      _showRouteOnMap(route);
      setState(() {
        _routeInfo = '${_formatLength(route.lengthInMeters)}, Duration: ${route.duration.inMinutes} min';
      });
      completer.complete(route);
    });

    return completer.future;
  }

  void _showRouteOnMap(here.Route route) {
    final GeoPolyline geoPolyline = route.geometry;
    const double bgWidthInPixels = 18;
    const double widthInPixels = 12;
    final Color bgColor = const Color.fromARGB(200, 255, 255, 255);
    final Color polylineColor = const Color.fromARGB(230, 66, 133, 244); // Google blue
    try {
      // background stroke for contrast
      final bgPolyline = MapPolyline.withRepresentation(
        geoPolyline,
        MapPolylineSolidRepresentation(
          MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, bgWidthInPixels),
          bgColor,
          LineCap.round,
        ),
      );
      _hereMapController!.mapScene.addMapPolyline(bgPolyline);
      _mapPolylines.add(bgPolyline);

      final mapPolyline = MapPolyline.withRepresentation(
        geoPolyline,
        MapPolylineSolidRepresentation(
          MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, widthInPixels),
          polylineColor,
          LineCap.round,
        ),
      );
      _hereMapController!.mapScene.addMapPolyline(mapPolyline);
      _mapPolylines.add(mapPolyline);

      // Track current route and maneuvers
      _currentRoute = route;
      _currentManeuverIndex = 0;
      if (route.sections.isNotEmpty && route.sections.first.maneuvers.isNotEmpty) {
        _currentManeuverInstruction = route.sections.first.maneuvers.first.text;
      } else {
        _currentManeuverInstruction = '';
      }
      setState(() {});

      // Animate camera to route
      _animateToRoute(route);
    } on Exception catch (e) {
      print('Failed to show route: $e');
    }
  }

  void _animateToRoute(here.Route route) {
    final bearing = 0.0;
    final tilt = 0.0;
    final origin = Point2D(50, 50);
    final sizeInPixels = Size2D(
      _hereMapController!.viewportSize.width - 100,
      _hereMapController!.viewportSize.height - 100,
    );
    final mapViewport = Rectangle2D(origin, sizeInPixels);

    _hereMapController!.camera.lookAtAreaWithGeoOrientationAndViewRectangle(route.boundingBox, GeoOrientationUpdate(bearing, tilt), mapViewport);
  }

  // --- Navigation helpers ---
  String _formatLength(int meters) {
    if (meters < 1000) return '$meters m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000.0).toStringAsFixed(2)} km';
  }

  String _estimateFare(int meters, Duration duration) {
    // Simple fare heuristic: base + per_km + per_min
    final km = meters / 1000.0;
    final minutes = duration.inMinutes.toDouble();
    final base = 3.0; // base fare
    final perKm = 1.2; // AED per km
    final perMin = 0.2; // AED per minute
    final fare = base + perKm * km + perMin * minutes;
    return 'AED ${fare.toStringAsFixed(1)}';
  }

  Future<void> _startTrip() async {
    if (_navigating) return;

    // If we don't have a route yet, calculate it now
    if (_currentRoute == null) {
      final r = await _calculateRoute();
      if (r == null) return; // failed to compute
    }

    // Request permissions
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied.')));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
      return;
    }

    _tripStartTime = DateTime.now();
    _totalDistanceTravelled = 0.0;
    _lastPositionCoords = null;
    _navigating = true;
    _tripStatus = TripStatus.onboard;

    // Subscribe to position updates
    final locationSettings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
    _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
      _onPosition(pos);
    });

    // Log trip start for diagnostics
    print('Trip started at $_tripStartTime; pickup=$_pickupCoords drop=$_dropCoords');

    setState(() {});
  }

  Future<void> _stopTrip({bool arrived = false}) async {
    if (!_navigating) return;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _tripEndTime = DateTime.now();
    _navigating = false;
    _tripStatus = TripStatus.completed; 

    final duration = _tripEndTime!.difference(_tripStartTime!);
    final distance = _totalDistanceTravelled;

    // diagnostic log
    print('Trip ended at $_tripEndTime; duration=${duration.inSeconds}s distance=${distance}m customer=${_customerController.text} arrived=$arrived');
    final customer = _customerController.text.isEmpty ? '<unknown>' : _customerController.text;

    // Show summary
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: Text(arrived ? 'Trip Completed' : 'Trip Ended'),
        content: Text('Customer: $customer\nDuration: ${duration.inMinutes} min ${duration.inSeconds % 60}s\nDistance: ${_formatDistance(distance)}'),
        actions: [
          TextButton(onPressed: () { Navigator.of(context).pop(); }, child: const Text('OK')),
        ],
      );
    });

    setState(() {});
  }

  void _addOrMoveUserMarker(GeoCoordinates coords) {
    if (_hereMapController == null) return;
    // remove old
    if (_userMarker != null) {
      try { _hereMapController!.mapScene.removeMapMarker(_userMarker!); } catch (_) {}
      _userMarker = null;
    }
    // simple blue marker
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
      <circle cx="16" cy="16" r="8" fill="#0077FF" stroke="#ffffff" stroke-width="2" />
    </svg>''';
    final data = Uint8List.fromList(svg.codeUnits);
    final img = MapImage.withImageDataImageFormatWidthAndHeight(data, ImageFormat.svg, 32, 32);
    _userMarker = MapMarker(coords, img);
    _hereMapController!.mapScene.addMapMarker(_userMarker!);
  }

  // Initialize geolocation (gets current position and places marker)
  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied')));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final coords = GeoCoordinates(pos.latitude, pos.longitude);
      _userCoords = coords;
      // Add user marker when map is ready
      if (_hereMapController != null) {
        _addOrMoveUserMarker(coords);
        _hereMapController!.camera.lookAtPoint(coords);
      }
    } on Exception catch (e) {
      print('Location init failed: $e');
    }
  }

  // Calculate route between two coordinates and return the route (async)
  Future<here.Route?> _calculateRouteBetween(GeoCoordinates start, GeoCoordinates end) async {
    final startWp = here.Waypoint.withDefaults(start);
    final endWp = here.Waypoint.withDefaults(end);
    final waypoints = [startWp, endWp];

    final completer = Completer<here.Route?>();
    here.CarOptions carOptions = here.CarOptions();
    carOptions.routeOptions.enableTolls = false;

    _routingEngine.calculateCarRoute(waypoints, carOptions, (here.RoutingError? error, List<here.Route>? routes) {
      if (error != null || routes == null || routes.isEmpty) {
        completer.complete(null);
        return;
      }
      completer.complete(routes.first);
    });

    return completer.future;
  }

  // Show route geometry on map as a single leg with specified color (with background stroke)
  void _showRouteLegOnMap(here.Route? route, Color color) {
    if (route == null || _hereMapController == null) return;
    final GeoPolyline geoPolyline = route.geometry;
    const double bgWidthInPixels = 14;
    const double widthInPixels = 8;
    final Color bgColor = const Color.fromARGB(200, 255, 255, 255);
    try {
      final bgPolyline = MapPolyline.withRepresentation(
        geoPolyline,
        MapPolylineSolidRepresentation(
          MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, bgWidthInPixels),
          bgColor,
          LineCap.round,
        ),
      );
      _hereMapController!.mapScene.addMapPolyline(bgPolyline);
      _mapPolylines.add(bgPolyline);

      final mapPolyline = MapPolyline.withRepresentation(
        geoPolyline,
        MapPolylineSolidRepresentation(
          MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, widthInPixels),
          color,
          LineCap.round,
        ),
      );
      _hereMapController!.mapScene.addMapPolyline(mapPolyline);
      _mapPolylines.add(mapPolyline);
    } on Exception catch (e) {
      print('Failed to show leg on map: $e');
    }
  }

  void _onPosition(Position pos) {
    final coords = GeoCoordinates(pos.latitude, pos.longitude);

    // update distance travelled
    if (_lastPositionCoords != null) {
      _totalDistanceTravelled += _lastPositionCoords!.distanceTo(coords);
    }
    _lastPositionCoords = coords;

    _addOrMoveUserMarker(coords);

    // update next maneuver instruction and advance if close
    if (_currentRoute != null) {
      // find next maneuver from current index
      final maneuvers = _currentRoute!.sections.expand((s) => s.maneuvers).toList();
      if (_currentManeuverIndex < maneuvers.length) {
        final nextM = maneuvers[_currentManeuverIndex];
        final distToM = nextM.coordinates.distanceTo(coords);
        _currentManeuverInstruction = nextM.text;
        if (distToM < 20) {
          _currentManeuverIndex++;
        }
      }

      // check arrival
      final arrivalPlace = _currentRoute!.sections.last.arrivalPlace;
      final destinationCoords = _dropCoords ?? arrivalPlace.originalCoordinates ?? arrivalPlace.mapMatchedCoordinates;
      final distToDest = destinationCoords.distanceTo(coords);
      if (distToDest < 25) {
        // auto complete
        _stopTrip(arrived: true);
        return;
      }

      // check deviation (simple nearest vertex distance)
      double minDist = double.infinity;
      for (final v in _currentRoute!.geometry.vertices) {
        final d = v.distanceTo(coords);
        if (d < minDist) minDist = d;
      }
      if (minDist > 60) {
        // reroute
        _recalculateRouteFromPosition(coords);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rerouting...')));
      }
    }



    setState(() {});
  }

  void _recalculateRouteFromPosition(GeoCoordinates from) {
    if (_dropCoords == null) return;
    final start = here.Waypoint.withDefaults(from);
    final dest = here.Waypoint.withDefaults(_dropCoords!);
    final waypoints = [start, dest];
    here.CarOptions carOptions = here.CarOptions();
    carOptions.routeOptions.enableTolls = false;

    _routingEngine.calculateCarRoute(waypoints, carOptions, (here.RoutingError? error, List<here.Route>? routes) {
      if (error != null || routes == null || routes.isEmpty) {
        print('Reroute failed: $error');
        return;
      }
      final route = routes.first;
      _currentRoute = route;
      print('Reroute successful; new length=${route.lengthInMeters}m duration=${route.duration}');
      _clearRoute();
      _showRouteOnMap(route);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route updated')));
    });
  }

  // Recently-calculated legs for user->pickup and pickup->drop
  here.Route? _lastUserToPickupRoute;
  here.Route? _lastPickupToDropRoute;

  // Called after a pickup location is selected: show user->pickup leg
  Future<void> _onPickupSelected() async {
    if (_userCoords == null) {
      await _initLocation();
    }
    if (_userCoords == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to obtain current location')));
      return;
    }
    if (_pickupCoords == null) return;

    // Clear any existing route legs and calculate user->pickup
    _clearRoute();
    _lastUserToPickupRoute = await _calculateRouteBetween(_userCoords!, _pickupCoords!);
    if (_lastUserToPickupRoute != null) {
      _showRouteLegOnMap(_lastUserToPickupRoute, Colors.orangeAccent);
      // zoom to show both points roughly
      final box = GeoBox(_userCoords!, _pickupCoords!);
      try { _hereMapController?.camera.lookAtAreaWithGeoOrientationAndViewRectangle(box, GeoOrientationUpdate(0,0), Rectangle2D(Point2D(0,0), Size2D(300,300))); } catch (_) {}
    }
  }

  // Called after a drop location is selected: show pickup->drop leg and summary
  Future<void> _onDropSelected() async {
    if (_pickupCoords == null || _dropCoords == null) return;

    // Ensure user->pickup leg exists (calculate if missing)
    if (_lastUserToPickupRoute == null) {
      await _onPickupSelected();
    }

    // Calculate pickup->drop
    _lastPickupToDropRoute = await _calculateRouteBetween(_pickupCoords!, _dropCoords!);
    if (_lastPickupToDropRoute != null) {
      _showRouteLegOnMap(_lastPickupToDropRoute, const Color(0xFF4285F4));

      // After both legs present, show summary
      final int totalMeters = (_lastUserToPickupRoute?.lengthInMeters ?? 0) + (_lastPickupToDropRoute?.lengthInMeters ?? 0);
      final Duration totalDuration = Duration(seconds: (_lastUserToPickupRoute?.duration.inSeconds ?? 0) + (_lastPickupToDropRoute?.duration.inSeconds ?? 0));

      // Show popup with distance and ETA
      showDialog(context: context, builder: (_) {
        return AlertDialog(
          title: const Text('Trip Summary'),
          content: Text('Total distance: ${_formatLength(totalMeters)}\nEstimated time: ${totalDuration.inMinutes} min'),
          actions: [TextButton(onPressed: () { Navigator.of(context).pop(); }, child: const Text('OK'))],
        );
      });

      // Zoom to show full trip
      try {
        final north = max(_userCoords!.latitude, _dropCoords!.latitude);
        final south = min(_userCoords!.latitude, _dropCoords!.latitude);
        final east = max(_userCoords!.longitude, _dropCoords!.longitude);
        final west = min(_userCoords!.longitude, _dropCoords!.longitude);
        final box = GeoBox(GeoCoordinates(north, east), GeoCoordinates(south, west));
        _hereMapController?.camera.lookAtAreaWithGeoOrientationAndViewRectangle(box, GeoOrientationUpdate(0,0), Rectangle2D(Point2D(0,0), Size2D(300,300)));
      } catch (_) {}
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // full-screen map
          Positioned.fill(child: HereMap(onMapCreated: _onMapCreated)),









        ],
      ),
    );
  }}

