import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/routing.dart' as here;
import 'package:geolocator/geolocator.dart';
import 'dart:async' as async;
import 'package:here_offline_app/app_theme.dart';

// Live location disabled temporarily; using fixed Dubai test coordinate.
class DeliveryNextScreen extends StatefulWidget {
  final GeoCoordinates userCoords;
  final GeoCoordinates pickupCoords;
  final GeoCoordinates dropCoords;
  final String customerName;
  final String pickupAddress;
  final String dropAddress;

  const DeliveryNextScreen({Key? key, required this.userCoords, required this.pickupCoords, required this.dropCoords, required this.customerName, required this.pickupAddress, required this.dropAddress}) : super(key: key);

  @override
  State<DeliveryNextScreen> createState() => _DeliveryNextScreenState();
}

class _DeliveryNextScreenState extends State<DeliveryNextScreen> {
  HereMapController? _hereMapController;
  late here.RoutingEngine _routingEngine;
  here.Route? _route;

  MapMarker? _userMarker;
  MapMarker? _pickupMarker;
  MapMarker? _dropMarker;

  double? _currentSpeedKph; // Speed will show when live GPS is restored.
  bool _pickedUp = false;
  GeoCoordinates? _currentCoords; // track current arrow position

  // Live GPS
  async.StreamSubscription<Position>? _posSub;
  Position? _lastPosition;
  DateTime? _tripStartTime;
  DateTime? _tripEndTime;
  double _distanceTravelled = 0.0;

  final List<MapPolyline> _polylines = [];

  List<String> _maneuverTexts = [];
  String _currentManeuver = '';

  int? _totalMeters;
  Duration? _totalDuration;

  // TEMP spoofed user location (Dubai) until live location is restored.
  final GeoCoordinates _dubaiTestCoords = GeoCoordinates(25.2048, 55.2708);

  VoidCallback? _themeListener;

  @override
  void initState() {
    super.initState();
    try {
      _routingEngine = here.RoutingEngine();
    } catch (e) {
      debugPrint('Routing init failed: $e');
    }
  }

  @override
  void dispose() {
    try { if (_themeListener != null) AppTheme.mode.removeListener(_themeListener!); } catch (_) {}
    super.dispose();
  }

  void _onMapCreated(HereMapController controller) {
    _hereMapController = controller;
    final scheme = Theme.of(context).brightness == Brightness.dark ? MapScheme.normalNight : MapScheme.normalDay;
    controller.mapScene.loadSceneForMapScheme(scheme, (MapError? e) {
      if (e != null) { debugPrint('Scene load failed: $e'); return; }
      _calculateAndShowRoute();
      // start location updates (live GPS)
      _startLocationUpdates();
      _addPickupDropMarkers();
      try {
        // Orient the initial view toward the pickup location (until GPS updates move it)
        final initial = widget.userCoords;
        final headingToPickup = _bearingBetween(initial, widget.pickupCoords);
        _hereMapController?.camera.lookAtPointWithMeasure(initial, MapMeasure(MapMeasureKind.distanceInMeters, 40));
        _hereMapController?.camera.setOrientationAtTarget(GeoOrientationUpdate(headingToPickup, 65.0));
      } catch (_) {}
    });

    // reload scene when theme changes
    _themeListener = () {
      final useDark = AppTheme.mode.value == ThemeMode.dark || (AppTheme.mode.value == ThemeMode.system && Theme.of(context).brightness == Brightness.dark);
      final newScheme = useDark ? MapScheme.normalNight : MapScheme.normalDay;
      try { controller.mapScene.loadSceneForMapScheme(newScheme, (MapError? err) {}); } catch (_) {}
    };
    AppTheme.mode.addListener(_themeListener!);

  }

  Future<void> _calculateAndShowRoute() async {
    final startCoord = _getCurrentStartCoords();
    final start = here.Waypoint.withDefaults(startCoord);
    final mid = here.Waypoint.withDefaults(widget.pickupCoords);
    final end = here.Waypoint.withDefaults(widget.dropCoords);

    final comp = Completer<here.Route?>();
    final opts = here.CarOptions();
    opts.routeOptions.enableTolls = false;

    _routingEngine.calculateCarRoute([start, mid, end], opts, (here.RoutingError? err, List<here.Route>? routes) {
      if (err != null || routes == null || routes.isEmpty) { comp.complete(null); return; }
      comp.complete(routes.first);
    });

    _route = await comp.future;
    if (_route != null && _hereMapController != null) {
      _clearPolylines();
      int idx = 0;
      int totalMeters = 0;
      int totalSeconds = 0;
      for (final s in _route!.sections) {
        final color = (idx == 0) ? Colors.orange : (idx == 1) ? Colors.blue : Colors.green;
        _showSectionGeo(s.geometry, color);
        totalMeters += s.lengthInMeters;
        totalSeconds += s.duration.inSeconds;
        idx++;
      }
      _totalMeters = totalMeters;
      _totalDuration = Duration(seconds: totalSeconds);

      _maneuverTexts = [];
      for (final s in _route!.sections) {
        for (final m in s.maneuvers) {
          _maneuverTexts.add('${m.text} · ${m.lengthInMeters} m');
        }
      }
      if (_maneuverTexts.isNotEmpty) {
        _currentManeuver = _maneuverTexts.first;
      }

      try {
        final verts = _route!.sections.first.geometry.vertices;
        final firstVertex = verts.first;
        final nextVertex = verts.length > 1 ? verts[1] : firstVertex;
        final heading = _bearingBetween(firstVertex, nextVertex);
        final startMarkerCoords = _getCurrentStartCoords();
        _addOrMoveUserMarker(startMarkerCoords, heading: heading);
        _hereMapController!.camera.lookAtPointWithMeasure(firstVertex, MapMeasure(MapMeasureKind.distanceInMeters, 80));
        _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(heading, 70.0));
      } catch (_) {}
      setState(() {});
    }
  }

  void _clearPolylines() {
    for (final p in _polylines) {
      try { _hereMapController?.mapScene.removeMapPolyline(p); } catch (_) {}
    }
    _polylines.clear();
  }

  void _showSectionGeo(GeoPolyline geo, Color color) {
    final bg = MapPolyline.withRepresentation(
      geo,
      MapPolylineSolidRepresentation(
        MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, 18),
        Colors.white,
        LineCap.round,
      ),
    );
    final main = MapPolyline.withRepresentation(
      geo,
      MapPolylineSolidRepresentation(
        MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, 10),
        color,
        LineCap.round,
      ),
    );
    _hereMapController?.mapScene.addMapPolyline(bg);
    _hereMapController?.mapScene.addMapPolyline(main);
    _polylines.add(bg);
    _polylines.add(main);
  }

  void _addPickupDropMarkers() {
    if (_hereMapController == null) return;
    for (final m in [_pickupMarker, _dropMarker]) {
      if (m != null) {
        try { _hereMapController!.mapScene.removeMapMarker(m); } catch (_) {}
      }
    }
    _pickupMarker = null;
    _dropMarker = null;

    const pickupSvg = '''<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44">
      <path d="M22 3 C14 3 8 9 8 17 c0 9 14 24 14 24s14-15 14-24C36 9 30 3 22 3z" fill="#1FB141" stroke="#ffffff" stroke-width="2"/>
      <circle cx="22" cy="17" r="6" fill="#ffffff"/>
    </svg>''';
    const dropSvg = '''<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44">
      <path d="M22 3 C14 3 8 9 8 17 c0 9 14 24 14 24s14-15 14-24C36 9 30 3 22 3z" fill="#FF5722" stroke="#ffffff" stroke-width="2"/>
      <circle cx="22" cy="17" r="6" fill="#ffffff"/>
    </svg>''';

    final pickupImg = MapImage.withImageDataImageFormatWidthAndHeight(Uint8List.fromList(pickupSvg.codeUnits), ImageFormat.svg, 44, 44);
    final dropImg = MapImage.withImageDataImageFormatWidthAndHeight(Uint8List.fromList(dropSvg.codeUnits), ImageFormat.svg, 44, 44);

    _pickupMarker = MapMarker(widget.pickupCoords, pickupImg);
    _dropMarker = MapMarker(widget.dropCoords, dropImg);
    _hereMapController!.mapScene.addMapMarker(_pickupMarker!);
    _hereMapController!.mapScene.addMapMarker(_dropMarker!);
  }

  void _recenterCamera() {
    if (_hereMapController == null) return;
    try {
      if (_route != null) {
        final verts = _route!.sections.first.geometry.vertices;
        final firstVertex = verts.first;
        final nextVertex = verts.length > 1 ? verts[1] : firstVertex;
        final heading = _bearingBetween(firstVertex, nextVertex);
        _hereMapController!.camera.lookAtPointWithMeasure(firstVertex, MapMeasure(MapMeasureKind.distanceInMeters, 80));
        _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(heading, 70.0));
        _addOrMoveUserMarker(_pickedUp ? widget.pickupCoords : _getCurrentStartCoords(), heading: heading);
        return;
      }
      final startFallback = _getCurrentStartCoords();
      _hereMapController!.camera.lookAtPointWithMeasure(startFallback, MapMeasure(MapMeasureKind.distanceInMeters, 80));
      _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(0.0, 70.0));
      _addOrMoveUserMarker(startFallback, heading: 0);
    } catch (_) {}
  }

  void _addOrMoveUserMarker(GeoCoordinates coords, {double heading = 0}) {
    if (_hereMapController == null) return;
    if (_userMarker != null) {
      try { _hereMapController!.mapScene.removeMapMarker(_userMarker!); } catch (_) {}
      _userMarker = null;
    }
    const svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 64 64">
      <defs>
        <linearGradient id="grad" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#1A73E8"/>
          <stop offset="100%" stop-color="#0B58C6"/>
        </linearGradient>
        <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
          <feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity="0.35"/>
        </filter>
      </defs>
      <g filter="url(#shadow)">
        <path d="M32 4 L48 44 L32 36 L16 44 Z" fill="url(#grad)" stroke="#ffffff" stroke-width="3" stroke-linejoin="round"/>
        <circle cx="32" cy="36" r="5" fill="#ffffff" fill-opacity="0.9"/>
      </g>
    </svg>''';
    final data = Uint8List.fromList(svg.codeUnits);
    final img = MapImage.withImageDataImageFormatWidthAndHeight(data, ImageFormat.svg, 192, 192);
    _userMarker = MapMarker.withAnchor(coords, img, Anchor2D.withHorizontalAndVertical(0.5, 1.0));
    _hereMapController!.mapScene.addMapMarker(_userMarker!);
    // remember where we placed the arrow so pickup can reroute from this point if pressed early
    _currentCoords = coords;
  }

  void _endTrip({bool popToRoot = true}) {
    try {
      if (_userMarker != null) _hereMapController?.mapScene.removeMapMarker(_userMarker!);
      if (_pickupMarker != null) _hereMapController?.mapScene.removeMapMarker(_pickupMarker!);
      if (_dropMarker != null) _hereMapController?.mapScene.removeMapMarker(_dropMarker!);
    } catch (_) {}
    for (final p in _polylines) {
      try { _hereMapController?.mapScene.removeMapPolyline(p); } catch (_) {}
    }
    _polylines.clear();
    // stop GPS tracking
    _stopLocationUpdates();
    if (popToRoot && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _routeFromPickupToDrop([GeoCoordinates? startOverride]) async {
    // Recalculate route starting at pickup -> drop, allowing optional starting point.
    final startCoord = startOverride ?? widget.pickupCoords;
    final start = here.Waypoint.withDefaults(startCoord);
    final end = here.Waypoint.withDefaults(widget.dropCoords);
    final comp = Completer<here.Route?>();
    final opts = here.CarOptions();
    opts.routeOptions.enableTolls = false;
    _routingEngine.calculateCarRoute([start, end], opts, (here.RoutingError? err, List<here.Route>? routes) {
      if (err != null || routes == null || routes.isEmpty) { comp.complete(null); return; }
      comp.complete(routes.first);
    });
    final route = await comp.future;
    if (route != null && _hereMapController != null) {
      _route = route;
      _clearPolylines();
      int totalMeters = 0;
      int totalSeconds = 0;
      for (final s in route.sections) {
        _showSectionGeo(s.geometry, Colors.blue);
        totalMeters += s.lengthInMeters;
        totalSeconds += s.duration.inSeconds;
      }
      _totalMeters = totalMeters;
      _totalDuration = Duration(seconds: totalSeconds);
      _maneuverTexts = [];
      for (final s in route.sections) for (final m in s.maneuvers) _maneuverTexts.add('${m.text} · ${m.lengthInMeters} m');
      if (_maneuverTexts.isNotEmpty) _currentManeuver = _maneuverTexts.first;
      try {
        final verts = route.sections.first.geometry.vertices;
        final firstVertex = verts.first;
        final nextVertex = verts.length > 1 ? verts[1] : firstVertex;
        final heading = _bearingBetween(firstVertex, nextVertex);
        _hereMapController!.camera.lookAtPointWithMeasure(firstVertex, MapMeasure(MapMeasureKind.distanceInMeters, 80));
        _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(heading, 70.0));
        // place user arrow at the actual start point used for this reroute (may be current location)
        _addOrMoveUserMarker(startCoord, heading: heading);
      } catch (_) {}
      setState(() {});
    }
  }
  void _onPickupPressed() async {
    setState(() { _pickedUp = true; });
    // If user pressed early, reroute from the arrow's current position; otherwise use pickup coord
    final startCoord = _currentCoords ?? widget.pickupCoords;
    // place arrow where we consider 'now' (the point from which we'll route)
    _addOrMoveUserMarker(startCoord, heading: 0);
    // remove pickup marker since item is picked
    try { if (_pickupMarker != null) { _hereMapController?.mapScene.removeMapMarker(_pickupMarker!); _pickupMarker = null; } } catch (_) {}
    // start trip timer if not started
    _tripStartTime ??= DateTime.now();
    await _routeFromPickupToDrop(startCoord);
  }


  String _formatLength(int meters) {
    if (meters < 1000) return '$meters m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }

  double _bearingBetween(GeoCoordinates a, GeoCoordinates b) {
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    final deg = brng * 180.0 / math.pi;
    return (deg + 360.0) % 360.0;
  }

  double _toRadians(double deg) => deg * (math.pi / 180.0);

  GeoCoordinates _getCurrentStartCoords() {
    // prefer last known GPS arrow coords, then initial supplied userCoords, else fallback test coords
    return _currentCoords ?? widget.userCoords ?? _dubaiTestCoords;
  }

  // --- Delivery completion ---
  void _onDeliverPressed() async {
    // stop tracking
    _stopLocationUpdates();
    _tripEndTime ??= DateTime.now();
    final duration = _tripEndTime!.difference(_tripStartTime ?? _tripEndTime!);
    final distance = _distanceTravelled.round();
    // cleanup map
    _endTrip(popToRoot: false);
    // show summary screen
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryCompleteScreen(customerName: widget.customerName, duration: duration, distanceMeters: distance))).then((_) {
      // after summary, go back to root
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  String _nextInstructionText() {
    if (_maneuverTexts.length > 1) return _maneuverTexts[1];
    return 'Awaiting next maneuver';
  }

  // --- Live GPS tracking helpers ---
  Future<void> _startLocationUpdates() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
        return;
      }
      var permission = await Geolocator.checkPermission();
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

      // get an immediate current position so speed/arrow show up quickly
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
        _lastPosition = pos;
        _currentSpeedKph = (pos.speed.isNaN ? 0.0 : pos.speed) * 3.6;
        _currentCoords = GeoCoordinates(pos.latitude, pos.longitude);
        if (_hereMapController != null) {
          _addOrMoveUserMarker(_currentCoords!, heading: pos.heading);
          _hereMapController!.camera.lookAtPointWithMeasure(_currentCoords!, MapMeasure(MapMeasureKind.distanceInMeters, 40));
        }
      } catch (e) { debugPrint('Initial getCurrentPosition failed: $e'); }

      final locationSettings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
      _posSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((pos) {
        _onPosition(pos);
      });
    } catch (e) {
      debugPrint('Location start failed: $e');
    }
  }

  void _stopLocationUpdates() {
    try {
      _posSub?.cancel();
      _posSub = null;
      _lastPosition = null;
      _tripEndTime = DateTime.now();
    } catch (_) {}
  }

  void _onPosition(Position pos) {
    // update speed
    setState(() {
      _currentSpeedKph = (pos.speed.isNaN ? 0.0 : pos.speed) * 3.6;
    });

    // compute distance from last
    if (_lastPosition != null) {
      final delta = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, pos.latitude, pos.longitude);
      _distanceTravelled += delta;
    }
    _lastPosition = pos;

    // update arrow position and heading
    final coords = GeoCoordinates(pos.latitude, pos.longitude);
    double heading = pos.heading;
    if (heading.isNaN || heading == 0.0) {
      if (_currentCoords != null) heading = _bearingBetween(_currentCoords!, coords);
    }
    _addOrMoveUserMarker(coords, heading: heading);

    // if trip not started yet, set start
    _tripStartTime ??= DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: HereMap(onMapCreated: _onMapCreated)),

          Positioned(
            top: 20,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentManeuver.isNotEmpty ? _currentManeuver : 'Calculating route...',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Next: ${_nextInstructionText()}',
                          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              _totalDuration != null ? _formatDuration(_totalDuration!) : 'ETA',
                              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8), fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 10),
                            if (_totalMeters != null)
                              Text(
                                _formatLength(_totalMeters!),
                                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8), fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ),

          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.customerName.isNotEmpty ? 'Picking up (${widget.customerName})' : 'Picking up (unknown)', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text(_pickedUp ? 'En route to ${widget.dropAddress}' : widget.pickupAddress, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  ),
                  if (!_pickedUp)
                    ElevatedButton(
                      onPressed: _onPickupPressed,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                      child: const Text('Pickup'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _onDeliverPressed,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), backgroundColor: Colors.green),
                      child: const Text('Deliver'),
                    ),
                ],
              ),
            ),
          ),

          Positioned(
            right: 16,
            top: 140,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(12)),
              child: Text(
                _currentSpeedKph != null ? '${_currentSpeedKph!.toStringAsFixed(0)} km/h' : '0 km/h',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton(
              mini: true,
              onPressed: _recenterCamera,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}

class DeliveryCompleteScreen extends StatelessWidget {
  final String customerName;
  final int distanceMeters;
  final Duration duration;

  const DeliveryCompleteScreen({Key? key, required this.customerName, required this.distanceMeters, required this.duration}) : super(key: key);

  String _formatLength(int meters) {
    if (meters < 1000) return '$meters m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery complete')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Customer: $customerName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Distance: ${_formatLength(distanceMeters)}'),
              const SizedBox(height: 6),
              Text('Duration: ${_formatDuration(duration)}'),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
