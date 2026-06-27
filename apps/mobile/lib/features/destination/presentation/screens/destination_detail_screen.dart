import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class DestinationDetailScreen extends StatefulWidget {
  final String destinationId;
  final String? tripId;

  const DestinationDetailScreen({
    super.key,
    required this.destinationId,
    this.tripId,
  });

  @override
  State<DestinationDetailScreen> createState() =>
      _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen> {
  final _guideStore = getIt<DestinationGuideStore>();
  final _savedTrips = getIt<SavedTripRepository>();
  late Future<_DetailData> _detailFuture;
  SavedTrip? _savedTrip;
  bool _isSaving = false;

  bool get _openedFromSavedTrip => widget.tripId?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<_DetailData> _loadDetail() async {
    final tripId = widget.tripId?.trim();
    if (tripId != null && tripId.isNotEmpty) {
      final trip = await _savedTrips.getTrip(tripId);
      if (trip == null) return const _DetailData();
      await _guideStore.saveGuide(trip.guide);
      _savedTrip = trip;
      return _DetailData(guide: trip.guide, savedTrip: trip);
    }

    final guide = await _guideStore.getGuide(widget.destinationId);
    if (guide == null) return const _DetailData();
    return _DetailData(guide: guide);
  }

  Future<void> _saveToTrips(DestinationGuide guide) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final trip = await _savedTrips.saveGuide(guide);
      if (!mounted) return;
      setState(() {
        _savedTrip = trip;
        _detailFuture = Future.value(
          _DetailData(guide: guide, savedTrip: trip),
        );
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved to My Trips')));
    } on SavedTripException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_DetailData>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: RaasteShellColors.clay),
              );
            }

            if (snapshot.hasError) {
              return _GuideError(message: snapshot.error.toString());
            }

            final data = snapshot.data ?? const _DetailData();
            final guide = data.guide;
            if (guide == null) return const _GuideNotFound();

            final savedTrip = _savedTrip ?? data.savedTrip;
            final bottomInset = MediaQuery.of(context).padding.bottom + 24;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _GuideHeader(
                        guide: guide,
                        backToTrips: _openedFromSavedTrip,
                      ),
                      const SizedBox(height: 16),
                      _DisclaimerBanner(disclaimers: guide.disclaimers),
                      const SizedBox(height: 18),
                      _OverviewSection(overview: guide.overview),
                      const SizedBox(height: 18),
                      ...guide.itineraryDays.map(
                        (day) => Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _ItineraryDayCard(day: day),
                        ),
                      ),
                      _GuideActions(
                        guide: guide,
                        savedTrip: savedTrip,
                        isSaving: _isSaving,
                        onSave: () => _saveToTrips(guide),
                      ),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailData {
  final DestinationGuide? guide;
  final SavedTrip? savedTrip;

  const _DetailData({this.guide, this.savedTrip});
}

class _GuideHeader extends StatelessWidget {
  final DestinationGuide guide;
  final bool backToTrips;

  const _GuideHeader({required this.guide, required this.backToTrips});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed:
              () => context.go(backToTrips ? AppRoutes.trips : AppRoutes.home),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: RaasteShellColors.ink,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                guide.destinationName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${guide.intake.dates} | ${guide.intake.peopleCount} traveller${guide.intake.peopleCount == 1 ? '' : 's'} | ${guide.intake.dietaryPreference}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  final List<String> disclaimers;

  const _DisclaimerBanner({required this.disclaimers});

  @override
  Widget build(BuildContext context) {
    final text =
        disclaimers.isEmpty
            ? 'Prices, timings, availability, and travel conditions may vary. Verify before travel.'
            : disclaimers.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8D2A6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: RaasteShellColors.clay,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontSize: 12,
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

class _OverviewSection extends StatelessWidget {
  final GuideOverview overview;

  const _OverviewSection({required this.overview});

  @override
  Widget build(BuildContext context) {
    return _GuideSection(
      title: 'Overview',
      icon: Icons.explore_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BodyText(overview.summary),
          const SizedBox(height: 12),
          _InlineFact(title: 'Best time', value: overview.bestTimeToVisit),
          const SizedBox(height: 10),
          _InlineFact(title: 'How to get there', value: overview.howToGetThere),
        ],
      ),
    );
  }
}

class _ItineraryDayCard extends StatefulWidget {
  final ItineraryDay day;

  const _ItineraryDayCard({required this.day});

  @override
  State<_ItineraryDayCard> createState() => _ItineraryDayCardState();
}

class _ItineraryDayCardState extends State<_ItineraryDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 58,
                      width: 58,
                      decoration: const BoxDecoration(
                        color: RaasteShellColors.ink,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        day.dayNumber.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day.title,
                            maxLines: _expanded ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: RaasteShellColors.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            day.subtitle.isEmpty
                                ? 'Day ${day.dayNumber}'
                                : day.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: RaasteShellColors.muted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: RaasteShellColors.ink,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
              child: Column(
                children:
                    _visibleStops(
                      day.stops,
                    ).map((stop) => _ItineraryStopRow(stop: stop)).toList(),
              ),
            ),
            crossFadeState:
                _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

List<ItineraryStop> _visibleStops(List<ItineraryStop> stops) {
  final regularStops = <ItineraryStop>[];
  final mealChoices = <String, _MealChoice>{};

  for (final stop in stops) {
    final slot = _mealSlotForStop(stop);
    if (slot == null) {
      regularStops.add(stop);
      continue;
    }

    final current = mealChoices[slot];
    final isUserAdded = _isUserAddedRestaurant(stop);
    if (current == null) {
      mealChoices[slot] = _MealChoice(
        stop: stop,
        plannedTime: isUserAdded ? null : stop.time,
        isUserAdded: isUserAdded,
      );
      continue;
    }

    mealChoices[slot] = _MealChoice(
      stop: isUserAdded ? stop : current.stop,
      plannedTime: current.plannedTime ?? (isUserAdded ? null : stop.time),
      isUserAdded: current.isUserAdded || isUserAdded,
    );
  }

  final visibleStops = <ItineraryStop>[
    ...regularStops,
    ...mealChoices.values.map((choice) => choice.visibleStop),
  ]..sort((a, b) => _stopMinutes(a.time).compareTo(_stopMinutes(b.time)));

  return visibleStops;
}

class _MealChoice {
  final ItineraryStop stop;
  final String? plannedTime;
  final bool isUserAdded;

  const _MealChoice({
    required this.stop,
    required this.plannedTime,
    required this.isUserAdded,
  });

  ItineraryStop get visibleStop {
    final time = plannedTime;
    if (time == null || time == stop.time) return stop;
    return ItineraryStop(
      time: time,
      title: stop.title,
      description: stop.description,
      type: stop.type,
      sourceId: stop.sourceId,
      lat: stop.lat,
      lon: stop.lon,
    );
  }
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
  final minutes = _stopMinutes(stop.time);
  if (minutes >= 6 * 60 && minutes <= 11 * 60) return 'breakfast';
  if (minutes >= 11 * 60 && minutes < 16 * 60) return 'lunch';
  if (minutes >= 16 * 60 && minutes < 18 * 60) return 'snack';
  if (minutes >= 18 * 60 && minutes <= 23 * 60) return 'dinner';
  return null;
}

bool _isUserAddedRestaurant(ItineraryStop stop) {
  final type = stop.type.toLowerCase();
  final sourceId = stop.sourceId.toLowerCase();
  return sourceId.startsWith('restaurant:') && type.startsWith('restaurant:');
}

int _stopMinutes(String value) {
  final match = RegExp(
    r'(\d{1,2}):(\d{2})\s*(AM|PM)?',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return 24 * 60;
  var hour = int.tryParse(match.group(1) ?? '') ?? 0;
  final minute = int.tryParse(match.group(2) ?? '') ?? 0;
  final suffix = (match.group(3) ?? '').toUpperCase();
  if (suffix == 'PM' && hour < 12) hour += 12;
  if (suffix == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

class _ItineraryStopRow extends StatelessWidget {
  final ItineraryStop stop;

  const _ItineraryStopRow({required this.stop});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Icon(
              _iconFor(stop.type),
              color: _colorFor(stop.type),
              size: 27,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${stop.time} | ${stop.description}',
                  style: const TextStyle(
                    color: Color(0xFF6E7A91),
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('food') ||
        normalized.contains('restaurant') ||
        normalized.contains('lunch') ||
        normalized.contains('dinner')) {
      return Icons.restaurant_rounded;
    }
    if (normalized.contains('museum') || normalized.contains('historic')) {
      return Icons.palette_outlined;
    }
    if (normalized.contains('view') || normalized.contains('nature')) {
      return Icons.center_focus_strong_rounded;
    }
    return Icons.place_rounded;
  }

  Color _colorFor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('food') ||
        normalized.contains('restaurant') ||
        normalized.contains('lunch') ||
        normalized.contains('dinner')) {
      return const Color(0xFFB9A7D8);
    }
    if (normalized.contains('museum') || normalized.contains('historic')) {
      return const Color(0xFFEA8B8B);
    }
    return RaasteShellColors.clay;
  }
}

class _GuideSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _GuideSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: RaasteShellColors.clay, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontFamily: 'serif',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  final String title;
  final String value;

  const _InlineFact({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            title,
            style: const TextStyle(
              color: RaasteShellColors.sage,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(child: _BodyText(value)),
      ],
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;

  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.isEmpty ? 'Details will appear here.' : text,
      style: const TextStyle(
        color: RaasteShellColors.muted,
        fontSize: 13,
        height: 1.4,
      ),
    );
  }
}

class _GuideActions extends StatelessWidget {
  final DestinationGuide guide;
  final SavedTrip? savedTrip;
  final bool isSaving;
  final VoidCallback onSave;

  const _GuideActions({
    required this.guide,
    required this.savedTrip,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final trip = savedTrip;
    return Column(
      children: [
        if (trip == null)
          _ActionButton(
            label: isSaving ? 'Saving...' : 'Save to My Trips',
            icon:
                isSaving
                    ? Icons.hourglass_top_rounded
                    : Icons.bookmark_add_outlined,
            color: RaasteShellColors.ink,
            onTap: isSaving ? null : onSave,
          )
        else
          _ActionButton(
            label: 'Saved in My Trips',
            icon: Icons.check_circle_rounded,
            color: RaasteShellColors.ink,
            onTap: () => context.go(AppRoutes.trips),
          ),
        const SizedBox(height: 12),
        _ActionButton(
          label: 'Edit with AI',
          icon: Icons.auto_awesome_rounded,
          color: RaasteShellColors.clay,
          onTap: () {
            final tripParam = trip == null ? '' : '&tripId=${trip.id}';
            context.go(
              '${AppRoutes.destinationChat}?guideId=${guide.id}$tripParam',
            );
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? color.withValues(alpha: 0.7) : color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideError extends StatelessWidget {
  final String message;

  const _GuideError({required this.message});

  @override
  Widget build(BuildContext context) {
    return _StateMessage(
      icon: Icons.error_outline_rounded,
      title: 'Trip could not load',
      body: message.replaceFirst('Exception: ', ''),
      actionLabel: 'Back to Trips',
      onAction: () => context.go(AppRoutes.trips),
    );
  }
}

class _GuideNotFound extends StatelessWidget {
  const _GuideNotFound();

  @override
  Widget build(BuildContext context) {
    return _StateMessage(
      icon: Icons.travel_explore_rounded,
      title: 'Guide not found',
      body: 'Search a destination on Home and Raaste will build a fresh guide.',
      actionLabel: 'Go Home',
      onAction: () => context.go(AppRoutes.home),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RaasteShellColors.sage, size: 52),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontFamily: 'serif',
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
