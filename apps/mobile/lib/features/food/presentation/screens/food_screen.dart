import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/food/data/repositories/food_repository.dart';
import 'package:raaste/features/food/domain/models/restaurant_recommendation.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  final _repository = getIt<FoodRepository>();
  late Future<FoodDiscoveryData> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadDiscovery();
  }

  void _refresh() {
    setState(() => _future = _repository.loadDiscovery());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final bottomInset = MediaQuery.of(context).padding.bottom + 100;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.food,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset),
          child:
              user == null
                  ? const _SignedOutState()
                  : FutureBuilder<FoodDiscoveryData>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const _LoadingState();
                      }

                      if (snapshot.hasError) {
                        return _StatePanel(
                          icon: Icons.restaurant_menu_rounded,
                          title: 'Food picks could not load',
                          body: snapshot.error.toString().replaceFirst(
                            'Exception: ',
                            '',
                          ),
                          actionLabel: 'Try Again',
                          onAction: _refresh,
                        );
                      }

                      final data = snapshot.data;
                      if (data == null || data.trip == null) {
                        return _NoTripState(
                          onAction: () => context.go(AppRoutes.trips),
                        );
                      }

                      if (data.restaurants.isEmpty) {
                        return _NoRestaurantsState(
                          data: data,
                          onAction: _refresh,
                        );
                      }

                      return RefreshIndicator(
                        color: RaasteShellColors.clay,
                        onRefresh: () async => _refresh(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          itemCount: data.restaurants.length + 2,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            if (index == 0) return _FoodHeader(data: data);
                            if (index == 1) return const _DiscoveryNotice();
                            final restaurant = data.restaurants[index - 2];
                            return _RestaurantCard(
                              trip: data.trip!,
                              restaurant: restaurant,
                              repository: _repository,
                              onChanged: _refresh,
                            );
                          },
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }
}

class _FoodHeader extends StatelessWidget {
  final FoodDiscoveryData data;

  const _FoodHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    final trip = data.trip!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Food',
          style: TextStyle(
            color: RaasteShellColors.ink,
            fontFamily: 'serif',
            fontSize: 40,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Curated places to eat for your trip',
          style: TextStyle(
            color: RaasteShellColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: RaasteShellColors.outline),
            boxShadow: const [
              BoxShadow(
                color: RaasteShellColors.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: RaasteShellColors.ink,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.destinationName.isEmpty
                              ? 'Your trip'
                              : trip.destinationName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: RaasteShellColors.ink,
                            fontFamily: 'serif',
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data.message,
                          style: const TextStyle(
                            color: RaasteShellColors.muted,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(
                    icon: Icons.no_food_outlined,
                    label: _dietLabel(data.dietaryPreference),
                  ),
                  _MiniChip(
                    icon: Icons.route_outlined,
                    label:
                        trip.dates.isEmpty
                            ? trip.guide.intake.dates
                            : trip.dates,
                  ),
                  _MiniChip(
                    icon: Icons.verified_outlined,
                    label: '${data.restaurants.length} matched',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscoveryNotice extends StatelessWidget {
  const _DiscoveryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E7D6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: RaasteShellColors.clay),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Discovery only. No ordering or delivery. Directions copy a Google Maps search, and adding a place updates your saved itinerary.',
              style: TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  final SavedTrip trip;
  final RestaurantRecommendation restaurant;
  final FoodRepository repository;
  final VoidCallback onChanged;

  const _RestaurantCard({
    required this.trip,
    required this.restaurant,
    required this.repository,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.ink,
                        fontFamily: 'serif',
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        restaurant.area,
                        restaurant.cuisine,
                      ].where((item) => item.trim().isNotEmpty).join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RatingPill(label: restaurant.googleRating),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            restaurant.speciality,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            restaurant.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RaasteShellColors.muted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (restaurant.priceForTwo.isNotEmpty)
                _Tag(label: restaurant.priceForTwo),
              if (restaurant.bestTimeToVisit.isNotEmpty)
                _Tag(label: restaurant.bestTimeToVisit),
              ...restaurant.dietaryLabels
                  .take(4)
                  .map((label) => _Tag(label: label)),
            ],
          ),
          const SizedBox(height: 14),
          if (restaurant.localTip.isNotEmpty)
            _InfoLine(
              icon: Icons.lightbulb_outline_rounded,
              text: restaurant.localTip,
            ),
          if (restaurant.waitTimeReality.isNotEmpty)
            _InfoLine(
              icon: Icons.schedule_rounded,
              text: restaurant.waitTimeReality,
            ),
          if (restaurant.parking.isNotEmpty)
            _InfoLine(
              icon: Icons.local_parking_rounded,
              text: restaurant.parking,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: RaasteShellColors.ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => _showAddSheet(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Add'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RaasteShellColors.ink,
                    side: const BorderSide(color: RaasteShellColors.outline),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => _copyDirections(context),
                  icon: const Icon(Icons.directions_rounded, size: 20),
                  label: const Text('Directions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyDirections(BuildContext context) {
    Clipboard.setData(ClipboardData(text: restaurant.googleMapsQuery));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Google Maps search copied: ${restaurant.googleMapsQuery}',
          ),
        ),
      );
  }

  void _showAddSheet(BuildContext context) {
    var selectedDay = 1;
    var selectedMeal = 'lunch';
    final totalDays =
        trip.guide.itineraryDays.isEmpty ? 1 : trip.guide.itineraryDays.length;
    var selectedTime = _defaultMealTimeFor(trip, selectedDay, selectedMeal);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RaasteShellColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              final timeSuggestions = _timeSuggestionsFor(
                trip,
                selectedDay,
                selectedMeal,
              );

              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          height: 4,
                          width: 44,
                          decoration: BoxDecoration(
                            color: RaasteShellColors.outline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Add ${restaurant.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RaasteShellColors.ink,
                          fontFamily: 'serif',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Choose day',
                        style: TextStyle(
                          color: RaasteShellColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(totalDays, (index) {
                          final day = index + 1;
                          return ChoiceChip(
                            selected: selectedDay == day,
                            label: Text('Day $day'),
                            onSelected:
                                (_) => setSheetState(() {
                                  selectedDay = day;
                                  selectedTime = _defaultMealTimeFor(
                                    trip,
                                    selectedDay,
                                    selectedMeal,
                                  );
                                }),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Meal slot',
                        style: TextStyle(
                          color: RaasteShellColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            ['breakfast', 'lunch', 'snack', 'dinner']
                                .map(
                                  (slot) => ChoiceChip(
                                    selected: selectedMeal == slot,
                                    label: Text(_prettySlot(slot)),
                                    onSelected:
                                        (_) => setSheetState(() {
                                          selectedMeal = slot;
                                          selectedTime = _defaultMealTimeFor(
                                            trip,
                                            selectedDay,
                                            selectedMeal,
                                          );
                                        }),
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Time',
                        style: TextStyle(
                          color: RaasteShellColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            timeSuggestions
                                .map(
                                  (time) => ChoiceChip(
                                    selected: selectedTime == time,
                                    label: Text(time),
                                    onSelected:
                                        (_) => setSheetState(
                                          () => selectedTime = time,
                                        ),
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: RaasteShellColors.ink,
                            side: const BorderSide(
                              color: RaasteShellColors.outline,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _timeOfDayFromText(selectedTime),
                            );
                            if (picked == null) return;
                            setSheetState(
                              () => selectedTime = _formatTimeOfDay(picked),
                            );
                          },
                          icon: const Icon(Icons.schedule_rounded, size: 20),
                          label: Text('Set time: $selectedTime'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: RaasteShellColors.clay,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            await repository.addRestaurantToItinerary(
                              trip: trip,
                              restaurant: restaurant,
                              dayNumber: selectedDay,
                              mealSlot: selectedMeal,
                              mealTime: selectedTime,
                            );
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${restaurant.name} added to itinerary',
                                  ),
                                ),
                              );
                            onChanged();
                          },
                          icon: const Icon(Icons.playlist_add_check_rounded),
                          label: const Text('Add to Itinerary'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final String label;

  const _RatingPill({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8D8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            color: RaasteShellColors.clay,
            size: 16,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: RaasteShellColors.sage, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8D8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: RaasteShellColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8D8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: RaasteShellColors.ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: RaasteShellColors.clay),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  const _SignedOutState();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.lock_outline_rounded,
      title: 'Sign in for food picks',
      body: 'Raaste filters food recommendations from your saved trip diet.',
      actionLabel: 'Sign In',
      onAction: () => context.go(AppRoutes.signIn),
    );
  }
}

class _NoTripState extends StatelessWidget {
  final VoidCallback onAction;

  const _NoTripState({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.restaurant_menu_rounded,
      title: 'No trip selected',
      body:
          'Save a trip first. Food picks are matched to that trip and its dietary preference.',
      actionLabel: 'View Trips',
      onAction: onAction,
    );
  }
}

class _NoRestaurantsState extends StatelessWidget {
  final FoodDiscoveryData data;
  final VoidCallback onAction;

  const _NoRestaurantsState({required this.data, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FoodHeader(data: data),
        const SizedBox(height: 18),
        Expanded(
          child: _StatePanel(
            icon: Icons.restaurant_menu_rounded,
            title: 'No food picks yet',
            body: data.message,
            actionLabel: 'Refresh',
            onAction: onAction,
          ),
        ),
      ],
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: RaasteShellColors.outline),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RaasteShellColors.sage, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontFamily: 'serif',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RaasteShellColors.ink,
                foregroundColor: Colors.white,
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

String _dietLabel(String value) {
  final label = value.trim().isEmpty ? 'Diet matched' : value.trim();
  return 'Filtered: $label';
}

List<String> _timeSuggestionsFor(
  SavedTrip trip,
  int dayNumber,
  String mealSlot,
) {
  final values = <String>{
    _defaultMealTimeFor(trip, dayNumber, mealSlot),
    _fallbackMealTime(mealSlot),
  };
  return values.where((value) => value.trim().isNotEmpty).toList();
}

String _defaultMealTimeFor(SavedTrip trip, int dayNumber, String mealSlot) {
  final days = trip.guide.itineraryDays;
  if (days.isEmpty) return _fallbackMealTime(mealSlot);
  final safeIndex = (dayNumber - 1).clamp(0, days.length - 1).toInt();
  final day = days.firstWhere(
    (item) => item.dayNumber == dayNumber,
    orElse: () => days[safeIndex],
  );

  for (final stop in day.stops) {
    if (_mealSlotForStop(stop) == mealSlot) {
      return _firstTimeLabel(stop.time);
    }
  }
  return _fallbackMealTime(mealSlot);
}

String? _mealSlotForStop(ItineraryStop stop) {
  final header = '${stop.type} ${stop.title}'.toLowerCase();
  final isMeal =
      header.contains('restaurant') ||
      header.contains('food') ||
      header.contains('meal') ||
      header.contains('breakfast') ||
      header.contains('lunch') ||
      header.contains('snack') ||
      header.contains('dinner');
  if (!isMeal) return null;

  if (header.contains('breakfast')) return 'breakfast';
  if (header.contains('lunch')) return 'lunch';
  if (header.contains('snack')) return 'snack';
  if (header.contains('dinner')) return 'dinner';
  final minutes = _minutesFromText(stop.time);
  if (minutes >= 6 * 60 && minutes <= 11 * 60) return 'breakfast';
  if (minutes >= 11 * 60 && minutes < 16 * 60) return 'lunch';
  if (minutes >= 16 * 60 && minutes < 18 * 60) return 'snack';
  if (minutes >= 18 * 60 && minutes <= 23 * 60) return 'dinner';
  return null;
}

String _firstTimeLabel(String value) =>
    _formatClockMinutes(_minutesFromText(value));

TimeOfDay _timeOfDayFromText(String value) {
  final minutes = _minutesFromText(value) % (24 * 60);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

String _formatTimeOfDay(TimeOfDay value) {
  return _formatClockMinutes(value.hour * 60 + value.minute);
}

String _fallbackMealTime(String mealSlot) {
  switch (mealSlot) {
    case 'breakfast':
      return '9:00 AM';
    case 'lunch':
      return '1:00 PM';
    case 'snack':
      return '5:00 PM';
    case 'dinner':
    default:
      return '8:00 PM';
  }
}

int _minutesFromText(String value) {
  final match = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return 13 * 60;
  var hour = int.tryParse(match.group(1) ?? '') ?? 13;
  final minute = int.tryParse(match.group(2) ?? '') ?? 0;
  final suffix = (match.group(3) ?? '').toUpperCase();
  if (suffix == 'PM' && hour < 12) hour += 12;
  if (suffix == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

String _formatClockMinutes(int value) {
  final normalized = value % (24 * 60);
  final hour24 = normalized ~/ 60;
  final minute = normalized % 60;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
}

String _prettySlot(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
