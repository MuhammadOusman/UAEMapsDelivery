import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/search.dart';
import 'package:here_sdk/routing.dart' as here;
import 'delivery_next.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class DeliveryStrictScreen extends StatefulWidget {
  const DeliveryStrictScreen({Key? key}) : super(key: key);

  @override
  State<DeliveryStrictScreen> createState() => _DeliveryStrictScreenState();
}

class _DeliveryStrictScreenState extends State<DeliveryStrictScreen> {
  HereMapController? _hereMapController;
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  GeoCoordinates? _userCoords;
  GeoCoordinates? _pickupCoords;
  GeoCoordinates? _dropCoords;

  // Karachi center to bias search when user location is elsewhere.
  final GeoCoordinates _karachiCenter = GeoCoordinates(24.8607, 67.0011);
  // Temporary fixed user position in Dubai (kept for tests) - not used when GPS enabled.
  final GeoCoordinates _dubaiTestCoords = GeoCoordinates(25.2048, 55.2708);

  // Live location subscription
  StreamSubscription<Position>? _posSub;
  Position? _lastPos;

  late SearchEngine _searchEngine;
  late here.RoutingEngine _routingEngine;

  final List<MapMarker> _markers = [];
  final List<MapPolyline> _polylines = [];

  List<Suggestion> _suggestions = [];
  bool _suggestLoading = false;
  String _focusedField = '';
  Timer? _debounce;

  here.Route? _userToPickupRoute;
  here.Route? _pickupToDropRoute;

  // Trip summary to show as a card under fields
  int? _totalMeters;
  Duration? _totalDuration;

  @override
  void initState() {
    super.initState();
    try {
      _searchEngine = SearchEngine();
    } catch (e) {
      debugPrint('Search init failed: $e');
    }
    try {
      _routingEngine = here.RoutingEngine();
    } catch (e) {
      debugPrint('Routing init failed: $e');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _customerController.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    try { _posSub?.cancel(); } catch (_) {}
    super.dispose();
  }

  void _onMapCreated(HereMapController controller) {
    _hereMapController = controller;
    controller.mapScene.loadSceneForMapScheme(MapScheme.normalDay, (MapError? error) {
      if (error != null) {
        debugPrint('Scene load failed: $error');
        return;
      }

      if (_userCoords != null) {
        _addUserMarker(_userCoords!);
        _hereMapController?.camera.lookAtPoint(_userCoords!);
      }
    });
  }

  Future<void> _initLocation() async {
    // Try to start live GPS tracking; fall back to temporary test coordinate if not available.
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // fallback to test coords
        _userCoords = _dubaiTestCoords;
        if (_hereMapController != null) {
          _addUserMarker(_userCoords!);
          _centerToCoords(_userCoords!, 200);
        }
        setState(() {});
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _userCoords = _dubaiTestCoords;
          if (_hereMapController != null) {
            _addUserMarker(_userCoords!);
            _centerToCoords(_userCoords!, 200);
          }
          setState(() {});
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _userCoords = _dubaiTestCoords;
        if (_hereMapController != null) {
          _addUserMarker(_userCoords!);
          _centerToCoords(_userCoords!, 200);
        }
        setState(() {});
        return;
      }

      // get current position and set user marker
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _lastPos = pos;
      _userCoords = GeoCoordinates(pos.latitude, pos.longitude);
      if (_hereMapController != null) {
        _addUserMarker(_userCoords!);
        _centerToCoords(_userCoords!, 200);
      }

      // subscribe to position updates
      final locationSettings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
      _posSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((p) {
        _lastPos = p;
        _userCoords = GeoCoordinates(p.latitude, p.longitude);
        if (_hereMapController != null) {
          // move marker
          _addUserMarker(_userCoords!);
        }
        setState(() {});
      });
    } catch (e) {
      debugPrint('Location init error: $e');
      // fallback
      _userCoords = _dubaiTestCoords;
      if (_hereMapController != null) {
        _addUserMarker(_userCoords!);
        _centerToCoords(_userCoords!, 200);
      }
      setState(() {});
    }
  }

  void _addUserMarker(GeoCoordinates coords) {
    if (_hereMapController == null) return;
    // remove existing user marker if any
    if (_markers.isNotEmpty) {
      try { _hereMapController!.mapScene.removeMapMarker(_markers.first); } catch (_) {}
      _markers.clear();
    }
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><circle cx="18" cy="18" r="9" fill="#0077FF" stroke="#fff" stroke-width="2"/></svg>''';
    final data = Uint8List.fromList(svg.codeUnits);
    final img = MapImage.withImageDataImageFormatWidthAndHeight(data, ImageFormat.svg, 36, 36);
    final m = MapMarker(coords, img);
    _hereMapController!.mapScene.addMapMarker(m);
    _markers.add(m);
  }


  void _clearPolylines() {
    for (final p in _polylines) {
      try { _hereMapController?.mapScene.removeMapPolyline(p); } catch (_) {}
    }
    _polylines.clear();
  }

  Future<here.Route?> _calcRoute(GeoCoordinates from, GeoCoordinates to) async {
    final start = here.Waypoint.withDefaults(from);
    final dest = here.Waypoint.withDefaults(to);
    final comp = Completer<here.Route?>();
    final opts = here.CarOptions();
    opts.routeOptions.enableTolls = false;
    _routingEngine.calculateCarRoute([start, dest], opts, (here.RoutingError? err, List<here.Route>? routes) {
      if (err != null || routes == null || routes.isEmpty) { comp.complete(null); return; }
      comp.complete(routes.first);
    });
    return comp.future;
  }

  void _showLeg(here.Route route, Color color) {
    final geo = route.geometry;
    final bg = MapPolyline.withRepresentation(geo, MapPolylineSolidRepresentation(MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, 14), Colors.white, LineCap.round));
    final main = MapPolyline.withRepresentation(geo, MapPolylineSolidRepresentation(MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, 8), color, LineCap.round));
    _hereMapController?.mapScene.addMapPolyline(bg);
    _hereMapController?.mapScene.addMapPolyline(main);
    _polylines.add(bg);
    _polylines.add(main);
  }

  // Suggest handling
  void _onQueryChanged(String field, String query) {
    _debounce?.cancel();
    if (query.isEmpty) { setState(() { _suggestions = []; _suggestLoading = false; }); return; }
    setState(() { _suggestLoading = true; _focusedField = field; });
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final biasCenter = _userCoords ?? _karachiCenter;
      final tq = TextQuery.withArea(query, TextQueryArea.withCenter(biasCenter));
      _searchEngine.suggestExtended(tq, SearchOptions(), (SearchError? err, List<Suggestion>? s, ResponseDetails? r) {
        setState(() { _suggestLoading = false; _suggestions = s ?? []; });
      });
    });
  }

  Future<Place?> _fetchPlaceById(String id) async {
    Place? found;
    final q = PlaceIdQuery(id);
    final c = Completer<void>();
    _searchEngine.searchByPlaceIdWithLanguageCodeExtended(q, null, (SearchError? err, Place? p, ResponseDetails? r) {
      if (err == null && p != null) found = p;
      c.complete();
    });
    await c.future;
    return found;
  }

  Future<void> _onPickupSelected() async {
    if (_userCoords == null) await _initLocation();
    if (_userCoords == null || _pickupCoords == null) return;
    // clear polylines and draw user->pickup
    _clearPolylines();
    _userToPickupRoute = await _calcRoute(_userCoords!, _pickupCoords!);
    if (_userToPickupRoute != null) {
      _showLeg(_userToPickupRoute!, Colors.orange);
      // center to show the leg region and prefer a detail-friendly zoom
      _centerToInclude(_userCoords!, _pickupCoords!);
    }
  }

  Future<void> _onDropSelected() async {
    if (_pickupCoords == null || _dropCoords == null) return;
    _pickupToDropRoute = await _calcRoute(_pickupCoords!, _dropCoords!);
    if (_pickupToDropRoute != null) {
      // keep user->pickup if present, add pickup->drop polyline
      _showLeg(_pickupToDropRoute!, Colors.blue);

      // center to show the full route (user + pickup + drop) automatically
      final pins = <GeoCoordinates>[_pickupCoords!, _dropCoords!];
      if (_userCoords != null) pins.add(_userCoords!);
      _centerToAllPins(pins);

      // store summary to display below fields (no popup)
      final totalMeters = (_userToPickupRoute?.lengthInMeters ?? 0) + (_pickupToDropRoute?.lengthInMeters ?? 0);
      final totalSeconds = (_userToPickupRoute?.duration.inSeconds ?? 0) + (_pickupToDropRoute?.duration.inSeconds ?? 0);
      final totalDuration = Duration(seconds: totalSeconds);
      setState(() { _totalMeters = totalMeters; _totalDuration = totalDuration; });
    }
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

  // Center camera to given coordinates at specified distance (meters) and tilt for better detail visibility
  void _centerToCoords(GeoCoordinates coords, double meters) {
    if (_hereMapController == null) return;
    // Allow much closer minimum so local streets become visible (down to ~8m)
    // Reduce the maximum clamp and use a top-down (0° tilt) orientation for a normal map view.
    final m = meters.clamp(8.0, 2000.0);
    try {
      debugPrint('Centering to ${coords.latitude},${coords.longitude} at ${m}m');
      _hereMapController!.camera.lookAtPointWithMeasure(coords, MapMeasure(MapMeasureKind.distanceInMeters, m));
      // use flat top-down view for clearer local street rendering
      _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(0.0, 0.0));
    } catch (_) {}
  }

  // Center camera to include two coordinates while aiming to show local details when they are close
  void _centerToInclude(GeoCoordinates a, GeoCoordinates b) {
    if (_hereMapController == null) return;
    final dist = a.distanceTo(b);
    double meters;
    if (dist < 50) {
      // extremely close - zoom right to neighborhood level
      meters = (dist * 1.0).clamp(8.0, 120.0);
    } else if (dist < 500) {
      // local span
      meters = (dist * 0.7).clamp(20.0, 600.0);
    } else {
      // longer spans - overview but not too far
      meters = (dist * 0.6).clamp(200.0, 4000.0);
    }
    final mid = GeoCoordinates((a.latitude + b.latitude) / 2.0, (a.longitude + b.longitude) / 2.0);
    debugPrint('Centering to include points dist=${dist} -> meters=${meters}');
    _centerToCoords(mid, meters);
  }

  // Center to fit all provided points with padding so the full route is visible
  void _centerToAllPins(List<GeoCoordinates> points) {
    if (_hereMapController == null || points.isEmpty) return;
    if (points.length == 1) {
      _centerToCoords(points.first, 120);
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final center = GeoCoordinates((minLat + maxLat) / 2.0, (minLon + maxLon) / 2.0);

    final corners = [
      GeoCoordinates(minLat, minLon),
      GeoCoordinates(minLat, maxLon),
      GeoCoordinates(maxLat, minLon),
      GeoCoordinates(maxLat, maxLon),
    ];

    double maxRadius = 0;
    for (final c in corners) {
      final d = c.distanceTo(center);
      if (d > maxRadius) maxRadius = d;
    }

    final meters = (maxRadius * 2.4).clamp(80.0, 8000.0);
    _centerToCoords(center, meters);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Fields at the top (strict request)
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextField(controller: _customerController, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline), hintText: 'Customer name (optional)')),
                          const SizedBox(height: 8),
                          TextField(controller: _pickupController, decoration: const InputDecoration(prefixIcon: Icon(Icons.circle), hintText: 'Pickup'), onTap: () => setState(() { _focusedField = 'pickup'; _suggestions = []; }), onChanged: (v) => _onQueryChanged('pickup', v)),
                          const SizedBox(height: 8),
                          TextField(controller: _dropController, decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on), hintText: 'Drop-off'), onTap: () => setState(() { _focusedField = 'drop'; _suggestions = []; }), onChanged: (v) => _onQueryChanged('drop', v)),

                          if (_suggestLoading) const Padding(padding: EdgeInsets.only(top: 8.0), child: LinearProgressIndicator()),

                          if (_suggestions.isNotEmpty)
                            SizedBox(height: 160, child: ListView.builder(itemCount: _suggestions.length, itemBuilder: (context, i) {
                              final s = _suggestions[i];
                              return ListTile(
                                title: Text(s.title),
                                subtitle: s.place?.address.addressText != null ? Text(s.place!.address.addressText) : null,
                                onTap: () async {
                                  GeoCoordinates? coords = s.place?.geoCoordinates;
                                  if (coords == null && s.id != null) {
                                    final p = await _fetchPlaceById(s.id!);
                                    coords = p?.geoCoordinates;
                                  }
                                  if (coords == null) return;
                                  setState(() {
                                    if (_focusedField == 'pickup') {
                                      _pickupCoords = coords;
                                      _pickupController.text = s.title;
                                    } else {
                                      _dropCoords = coords;
                                      _dropController.text = s.title;
                                    }
                                    _suggestions = [];
                                  });

                                  if (_focusedField == 'pickup') {
                                    await _onPickupSelected();
                                  } else {
                                    await _onDropSelected();
                                  }
                                },
                              );
                            })),
                        ],
                      ),
                    ),
                  ),
                ),

                // Map fills the rest; it should show only the user's marker and polylines
                Expanded(child: HereMap(onMapCreated: _onMapCreated)),



                // add spacing so map content isn't obscured by floating card
                const SizedBox(height: 96),
              ],
            ),

            // Bottom card combining trip info and Start button
            if (_totalMeters != null && _totalDuration != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 20,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                    child: Row(
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_formatLength(_totalMeters!), style: TextStyle(color: Colors.grey[700])), const SizedBox(height: 4), Text(_formatDuration(_totalDuration!), style: const TextStyle(fontWeight: FontWeight.bold))]),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: (_pickupCoords != null && _dropCoords != null)
                              ? () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryNextScreen(
                                    userCoords: _userCoords!,
                                    pickupCoords: _pickupCoords!,
                                    dropCoords: _dropCoords!,
                                    customerName: _customerController.text.isEmpty ? '<unknown>' : _customerController.text,
                                  )));
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
