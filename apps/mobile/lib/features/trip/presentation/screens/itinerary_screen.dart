import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';

class ItineraryScreen extends StatelessWidget {
  final String tripId;

  const ItineraryScreen({
    super.key,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your itinerary')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trip #$tripId',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: 3,
                itemBuilder: (context, index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text('Day ${index + 1}'),
                      subtitle: const Text(
                        'Morning: Local breakfast\nAfternoon: Hidden waterfall\nEvening: Sunset point',
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () => context.go('${AppRoutes.companion}?tripId=$tripId'),
              child: const Text('Open trip companion'),
            ),
          ],
        ),
      ),
    );
  }
}
