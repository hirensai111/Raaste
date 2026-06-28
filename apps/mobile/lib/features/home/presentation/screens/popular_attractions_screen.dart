import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';
import 'package:raaste/features/home/domain/models/popular_attraction.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class PopularAttractionsScreen extends StatelessWidget {
  const PopularAttractionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom + 76 + 24;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.home,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  Row(
                    children: [
                      _CircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => context.go(AppRoutes.home),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Top 10 Destinations',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: RaasteShellColors.ink,
                                fontFamily: 'serif',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Pick a destination and start an AI itinerary',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: RaasteShellColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 560;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: popularAttractions.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: twoColumns ? 2 : 1,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: twoColumns ? 286 : 304,
                        ),
                        itemBuilder:
                            (context, index) => _TopAttractionCard(
                              rank: index + 1,
                              attraction: popularAttractions[index],
                            ),
                      );
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopAttractionCard extends StatelessWidget {
  final int rank;
  final PopularAttraction attraction;

  const _TopAttractionCard({required this.rank, required this.attraction});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFCF7),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openAttraction(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: RaasteShellColors.shadow,
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Image.asset(
                    attraction.image,
                    height: 142,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.38),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      height: 34,
                      width: 34,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: RaasteShellColors.ink,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Text(
                      attraction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'serif',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: RaasteShellColors.clay,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              attraction.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RaasteShellColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            attraction.tags
                                .take(3)
                                .map((tag) => _AttractionTag(label: tag))
                                .toList(),
                      ),
                      const Spacer(),
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Create itinerary',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: RaasteShellColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: RaasteShellColors.clay,
                            size: 21,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAttraction(BuildContext context) {
    final uri = Uri(
      path: AppRoutes.destinationChat,
      queryParameters: {
        'destination': attraction.planningDestination,
        'sourceId': attraction.sourceId,
        'displayAddress': attraction.address,
        'lat': attraction.lat.toString(),
        'lon': attraction.lon.toString(),
      },
    );
    context.go(uri.toString());
  }
}

class _AttractionTag extends StatelessWidget {
  final String label;

  const _AttractionTag({required this.label});

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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: RaasteShellColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6EFE3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          width: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: RaasteShellColors.outline),
          ),
          child: Icon(icon, color: RaasteShellColors.ink, size: 22),
        ),
      ),
    );
  }
}
