import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';

class TripPlanningScreen extends StatefulWidget {
  final String destinationId;

  const TripPlanningScreen({super.key, required this.destinationId});

  @override
  State<TripPlanningScreen> createState() => _TripPlanningScreenState();
}

class _TripPlanningScreenState extends State<TripPlanningScreen> {
  int _days = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(AppRoutes.home);
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Plan your trip'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.destinationId,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Text(
              'How many days?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _days.toDouble(),
              min: 1,
              max: 14,
              divisions: 13,
              label: '$_days days',
              onChanged: (value) => setState(() => _days = value.toInt()),
            ),
            Text('$_days days', style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            ElevatedButton(
              onPressed:
                  () => context.go(
                    '${AppRoutes.itinerary}?tripId=demo-${widget.destinationId}-$_days',
                  ),
              child: const Text('Build my itinerary'),
            ),
          ],
        ),
      ),
    );
  }
}
