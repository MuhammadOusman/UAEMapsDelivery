import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/routing.dart' as here;
import 'package:geolocator/geolocator.dart';

class DeliveryNextScreen extends StatefulWidget {
  final GeoCoordinates userCoords;
  final GeoCoordinates pickupCoords;
  final GeoCoordinates dropCoords;

  const DeliveryNextScreen({Key? key, required this.userCoords, required this.pickupCoords, required this.dropCoords}) : super(key: key);

  @override
  State<DeliveryNextScreen> createState() => _DeliveryNextScreenState();
}

class _DeliveryNextScreenState extends State<DeliveryNextScreen> {
  HereMapController? _hereMapController;
  late here.RoutingEngine _routingEngine;
  here.Route? _route;

  MapMarker? _userMarker;
  StreamSubscription<Position>? _posSub;

  final List<MapPolyline> _polylines = [];

  List<String> _maneuverTexts = [];
  int _nextManeuverIndex = 0;
  String _currentManeuver = '';

  // trip summary
  int? _totalMeters;
  Duration? _totalDuration;

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
    _posSub?.cancel();
    super.dispose();
  }

  void _onMapCreated(HereMapController controller) {
    _hereMapController = controller;
    // Use the light map scheme (user requested light theme)
    controller.mapScene.loadSceneForMapScheme(MapScheme.normalDay, (MapError? e) {
      if (e != null) { debugPrint('Scene load failed: $e'); return; }
      // draw route and center camera
      _calculateAndShowRoute();
      // add user marker
      _addOrMoveUserMarker(widget.userCoords);
      _startLocationUpdates();
      // set an initial close third-person camera view (tighter for street detail)
      try {
        debugPrint('Initial camera: centering at user ${widget.userCoords.latitude},${widget.userCoords.longitude}');
        _hereMapController?.camera.lookAtPointWithMeasure(widget.userCoords, MapMeasure(MapMeasureKind.distanceInMeters, 20));
        _hereMapController?.camera.setOrientationAtTarget(GeoOrientationUpdate(0.0, 65.0));
      } catch (_) {}
    });
  }

  Future<void> _calculateAndShowRoute() async {
    final start = here.Waypoint.withDefaults(widget.userCoords);
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
      // draw each section separately with white border + colored core (orange for first leg, blue for second)
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

      // extract maneuvers (text + short distance)
      _maneuverTexts = [];
      for (final s in _route!.sections) {
        for (final m in s.maneuvers) {
          _maneuverTexts.add('${m.text} · ${m.lengthInMeters} m');
        }
      }
      if (_maneuverTexts.isNotEmpty) {
        _currentManeuver = _maneuverTexts.first;
        _nextManeuverIndex = 0;
      }

      // zoom closer and tilt for third-person view and center on the initial leg (tighter for street detail)
      try {
        final firstVertex = _route!.sections.first.geometry.vertices.first;
        debugPrint('Centering on route start ${firstVertex.latitude},${firstVertex.longitude}');
        _hereMapController!.camera.lookAtPointWithMeasure(firstVertex, MapMeasure(MapMeasureKind.distanceInMeters, 30));
        _hereMapController!.camera.setOrientationAtTarget(GeoOrientationUpdate(0.0, 65.0));
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

  void _addOrMoveUserMarker(GeoCoordinates coords) {
    if (_hereMapController == null) return;
    if (_userMarker != null) {
      try { _hereMapController!.mapScene.removeMapMarker(_userMarker!); } catch (_) {}
      _userMarker = null;
    }
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><circle cx="18" cy="18" r="9" fill="#0077FF" stroke="#fff" stroke-width="2"/></svg>''';
    final data = Uint8List.fromList(svg.codeUnits);
    final img = MapImage.withImageDataImageFormatWidthAndHeight(data, ImageFormat.svg, 36, 36);
    _userMarker = MapMarker(coords, img);
    _hereMapController!.mapScene.addMapMarker(_userMarker!);
  }

  // End trip: stop location updates, clear overlays and return to the main planner
  void _endTrip() {
    _posSub?.cancel();
    _posSub = null;
    try {
      if (_userMarker != null) _hereMapController?.mapScene.removeMapMarker(_userMarker!);
    } catch (_) {}
    for (final p in _polylines) {
      try { _hereMapController?.mapScene.removeMapPolyline(p); } catch (_) {}
    }
    _polylines.clear();
    // navigate back to the first screen
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _startLocationUpdates() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2)).listen((pos) {
      final coords = GeoCoordinates(pos.latitude, pos.longitude);
      _addOrMoveUserMarker(coords);

      // follow with camera (third-person effect) — zoom in and tilt
      try {
        // If heading available, use it for orientation
        final heading = (pos.heading.isFinite && pos.heading >= 0) ? pos.heading : 0.0;
          // center on user and set orientation (bearing + tilt) for a tight third-person view
          try {
            _hereMapController?.camera.lookAtPointWithMeasure(coords, MapMeasure(MapMeasureKind.distanceInMeters, 20));
            _hereMapController?.camera.setOrientationAtTarget(GeoOrientationUpdate(heading, 65.0));
          } catch (_) {}
        } catch (_) {}

      // update maneuver index simple heuristic: advance if near next maneuver coordinate
      if (_route != null) {
        final maneuvers = _route!.sections.expand((s) => s.maneuvers).toList();
        if (_nextManeuverIndex < maneuvers.length) {
          final nextM = maneuvers[_nextManeuverIndex];
          final d = nextM.coordinates.distanceTo(coords);
          if (d < 25) {
            _nextManeuverIndex++;
            if (_nextManeuverIndex < maneuvers.length) _currentManeuver = '${maneuvers[_nextManeuverIndex].text} • ${maneuvers[_nextManeuverIndex].lengthInMeters} m';
            setState(() {});
          }
        }
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen map
          Positioned.fill(child: HereMap(onMapCreated: _onMapCreated)),

          // Turn-by-turn overlay at top (light card) - compact pill style
          Positioned(
            top: 20,
            left: 12,
            right: 12,
            child: SizedBox(
              height: 88,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(24)), child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 260), child: Text(_currentManeuver.isNotEmpty ? _currentManeuver : 'Calculating route...', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _maneuverTexts.length,
                              itemBuilder: (context, i) {
                                if (i == _nextManeuverIndex) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)), child: Text(_maneuverTexts[i], style: const TextStyle(color: Colors.black87), overflow: TextOverflow.ellipsis)),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)), child: Text(_totalDuration != null ? _formatDuration(_totalDuration!) : 'ETA', style: TextStyle(color: Colors.black87))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom status bar / trip card (light)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_totalDuration != null && _totalMeters != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                    child: Row(
                      children: [
                        Icon(Icons.directions_car, color: Colors.grey[800]),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_formatLength(_totalMeters!), style: TextStyle(color: Colors.grey[700])), Text(_formatDuration(_totalDuration!), style: const TextStyle(fontWeight: FontWeight.bold))]),
                        const Spacer(),
                        // small control icons
                        CircleAvatar(radius: 18, backgroundColor: Colors.grey[200], child: IconButton(icon: Icon(Icons.pause, color: Colors.grey[800]), onPressed: () {})),
                        const SizedBox(width: 8),
                        // End Trip Button
                        ElevatedButton(
                          onPressed: _endTrip,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          child: const Text('End Trip', style: TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(radius: 18, backgroundColor: Colors.grey[200], child: IconButton(icon: Icon(Icons.menu, color: Colors.grey[800]), onPressed: () {})),

                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
