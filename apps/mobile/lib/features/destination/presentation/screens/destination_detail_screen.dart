import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class DestinationDetailScreen extends StatefulWidget {
  final String destinationId;

  const DestinationDetailScreen({
    super.key,
    required this.destinationId,
  });

  @override
  State<DestinationDetailScreen> createState() =>
      _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen> {
  late final Future<DestinationGuide?> _guideFuture;
  final _store = getIt<DestinationGuideStore>();

  @override
  void initState() {
    super.initState();
    _guideFuture = _store.getGuide(widget.destinationId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<DestinationGuide?>(
          future: _guideFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  color: RaasteShellColors.clay,
                ),
              );
            }

            final guide = snapshot.data;
            if (guide == null) return const _GuideNotFound();

            final bottomInset = MediaQuery.of(context).padding.bottom + 24;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _GuideHeader(guide: guide),
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
                      _EditButton(guideId: guide.id),
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

class _GuideHeader extends StatelessWidget {
  final DestinationGuide guide;

  const _GuideHeader({required this.guide});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: () => context.go(AppRoutes.home),
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
    final text = disclaimers.isEmpty
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

class _ItineraryDayCard extends StatelessWidget {
  final ItineraryDay day;

  const _ItineraryDayCard({required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: const BoxDecoration(
                  color: RaasteShellColors.ink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  day.dayNumber.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      day.subtitle.isEmpty ? 'Day ${day.dayNumber}' : day.subtitle,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...day.stops.map((stop) => _ItineraryStopRow(stop: stop)),
        ],
      ),
    );
  }
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

class _EditButton extends StatelessWidget {
  final String guideId;

  const _EditButton({required this.guideId});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RaasteShellColors.clay,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('${AppRoutes.destinationChat}?guideId=$guideId'),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Edit with AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideNotFound extends StatelessWidget {
  const _GuideNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.travel_explore_rounded,
              color: RaasteShellColors.sage,
              size: 52,
            ),
            const SizedBox(height: 16),
            const Text(
              'Guide not found',
              style: TextStyle(
                color: RaasteShellColors.ink,
                fontFamily: 'serif',
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search a destination on Home and Raaste will build a fresh guide.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}
