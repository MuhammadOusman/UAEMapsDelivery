import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/mapview.dart';

class HereOfflineMapScreen extends StatefulWidget {
  final bool prefetchOnStart;
  const HereOfflineMapScreen({Key? key, this.prefetchOnStart = false}) : super(key: key);

  @override
  State<HereOfflineMapScreen> createState() => _HereOfflineMapScreenState();
}

class _HereOfflineMapScreenState extends State<HereOfflineMapScreen> {
  HereMapController? _hereMapController;

  // Prefetch state (camera sweep) - kept for backward compatibility
  bool _prefetching = false;
  double _progress = 0.0;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    // No offline MapDownloader in Explore edition; official persistent offline
    // downloads require the Navigate edition and will be added later.
  }

  void _showStatus(String s) {
    if (!mounted) return;
    setState(() { _status = s; });
  }

  void _onMapCreated(HereMapController controller) async {
    _hereMapController = controller;

    // Set initial camera
    const double distanceToEarthInMeters = 8000;
    MapMeasure mapMeasureZoom = MapMeasure(MapMeasureKind.distanceInMeters, distanceToEarthInMeters);
    _hereMapController!.camera.lookAtPointWithMeasure(GeoCoordinates(25.2048, 55.2708), mapMeasureZoom);

    // Load scene
    _hereMapController!.mapScene.loadSceneForMapScheme(MapScheme.normalDay, (MapError? error) {
      if (error != null) {
        _showStatus('Map scene not loaded: ${error.toString()}');
        return;
      }
      _showStatus('Map ready');

      // If requested, perform the simple camera prefetch (legacy behavior)
      if (widget.prefetchOnStart) {
        _prefetchUAE();
      }
    });
  }

  Future<void> _prefetchUAE() async {
    if (_prefetching) return;
    _prefetching = true;
    _showStatus('Prefetching map cache...');
    setState(() { _progress = 0.0; });

    final prefs = await SharedPreferences.getInstance();

    // Rough UAE bounding box
    final double south = 22.5;
    final double north = 26.5;
    final double west = 51.2;
    final double east = 56.6;

    const int rows = 6;
    const int cols = 6;
    int total = rows * cols;
    int done = 0;

    // Use a camera distance that corresponds to a reasonably detailed zoom level
    const double distanceToEarthInMeters = 3000;
    MapMeasure mapMeasureZoom = MapMeasure(MapMeasureKind.distanceInMeters, distanceToEarthInMeters);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final lat = south + (north - south) * (r + 0.5) / rows;
        final lon = west + (east - west) * (c + 0.5) / cols;
        _hereMapController?.camera.lookAtPointWithMeasure(GeoCoordinates(lat, lon), mapMeasureZoom);
        // Wait a bit to let map engine fetch tiles (tweak if necessary)
        await Future.delayed(const Duration(milliseconds: 600));
        done++;
        if (!mounted) return;
        setState(() { _progress = done / total; _status = 'Prefetching map cache... (${done}/$total)'; });
      }
    }

    await prefs.setBool('map_prefetched', true);

    if (!mounted) return;
    setState(() { _status = 'Prefetch complete'; _progress = 1.0; _prefetching = false; });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // --- MapDownloader helpers ---
  // Persistent offline downloads (MapDownloader) are not part of the Explore edition used here.
  // These functions will be implemented when migrating to the Navigate SDK.


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HERE Offline - UAE (Map)')),
      body: Column(
        children: [
          Expanded(
            child: HereMap(onMapCreated: _onMapCreated),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(_status),
                const SizedBox(height: 8),

                // Prefetch (legacy)
                Row(children: [
                  ElevatedButton.icon(
                    onPressed: _prefetching ? null : _prefetchUAE,
                    icon: const Icon(Icons.download),
                    label: const Text('Prefetch UAE (cache)'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Center on Dubai
                      const double distanceToEarthInMeters = 8000;
                      MapMeasure mapMeasureZoom = MapMeasure(MapMeasureKind.distanceInMeters, distanceToEarthInMeters);
                      _hereMapController?.camera.lookAtPointWithMeasure(GeoCoordinates(25.2048, 55.2708), mapMeasureZoom);
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Center Dubai'),
                  ),
                ]),

                const SizedBox(height: 12),

                // Map controls
                Row(children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      // Center on Dubai
                      const double distanceToEarthInMeters = 8000;
                      MapMeasure mapMeasureZoom = MapMeasure(MapMeasureKind.distanceInMeters, distanceToEarthInMeters);
                      _hereMapController?.camera.lookAtPointWithMeasure(GeoCoordinates(25.2048, 55.2708), mapMeasureZoom);
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Center Dubai'),
                  ),
                ])
              ],
            ),
          )
        ],
      ),
    );
  }
}
