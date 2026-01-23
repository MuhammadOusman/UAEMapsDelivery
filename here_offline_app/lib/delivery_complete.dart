import 'package:flutter/material.dart';

class DeliveryCompleteScreen extends StatelessWidget {
  final String customerName;
  final Duration duration;
  final int distanceMeters;

  const DeliveryCompleteScreen({Key? key, required this.customerName, required this.duration, required this.distanceMeters}) : super(key: key);

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }

  String _formatDistance(int meters) {
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000.0).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery complete')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: $customerName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Duration: ${_formatDuration(duration)}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('Distance: ${_formatDistance(distanceMeters)}', style: const TextStyle(fontSize: 16)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
