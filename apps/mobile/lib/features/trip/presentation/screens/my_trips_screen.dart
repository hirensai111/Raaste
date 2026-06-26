import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/data/services/place_image_service.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  final _repository = getIt<SavedTripRepository>();
  late Future<List<SavedTrip>> _tripsFuture;

  @override
  void initState() {
    super.initState();
    _tripsFuture = _repository.listTrips();
  }

  void _refresh() {
    setState(() => _tripsFuture = _repository.listTrips());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.trips,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TripsHeader(),
              const SizedBox(height: 18),
              Expanded(
                child:
                    user == null
                        ? const _SignedOutState()
                        : FutureBuilder<List<SavedTrip>>(
                          future: _tripsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: RaasteShellColors.clay,
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return _ErrorState(
                                message: snapshot.error.toString(),
                                onRetry: _refresh,
                              );
                            }

                            final trips = snapshot.data ?? const [];
                            if (trips.isEmpty) return const _EmptyTripsState();

                            return RefreshIndicator(
                              color: RaasteShellColors.clay,
                              onRefresh: () async => _refresh(),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                itemCount: trips.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 14),
                                itemBuilder:
                                    (context, index) =>
                                        _TripCard(trip: trips[index]),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripsHeader extends StatelessWidget {
  const _TripsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Trips',
                style: TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Saved AI itineraries for your journeys',
                style: TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: RaasteShellColors.ink,
            foregroundColor: Colors.white,
          ),
          onPressed: () => context.go(AppRoutes.home),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  final SavedTrip trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFCF7),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go('${AppRoutes.destination}?tripId=${trip.id}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(22),
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
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: SizedBox(
                  height: 168,
                  width: double.infinity,
                  child: _TripImage(trip: trip),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${trip.destinationName} Trip',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: RaasteShellColors.ink,
                              fontFamily: 'serif',
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: RaasteShellColors.clay,
                          size: 28,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trip.destinationAddress.isEmpty
                          ? trip.destinationName
                          : trip.destinationAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TripChip(
                          icon: Icons.calendar_month_outlined,
                          label:
                              trip.dates.isEmpty ? 'Dates saved' : trip.dates,
                        ),
                        _TripChip(
                          icon: Icons.group_outlined,
                          label:
                              '${trip.peopleCount} traveller${trip.peopleCount == 1 ? '' : 's'}',
                        ),
                        const _TripChip(
                          icon: Icons.edit_note_rounded,
                          label: 'Editable',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripImage extends StatelessWidget {
  final SavedTrip trip;

  const _TripImage({required this.trip});

  @override
  Widget build(BuildContext context) {
    final imageUrl = trip.imageUrl.trim();
    if (trip.hasRemoteImage) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: RaasteShellColors.surfaceAlt,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              color: RaasteShellColors.clay,
              strokeWidth: 2,
            ),
          );
        },
      );
    }
    return _fallbackImage();
  }

  Widget _fallbackImage() {
    return Image.asset(PlaceImageService.fallbackAsset, fit: BoxFit.cover);
  }
}

class _TripChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TripChip({required this.icon, required this.label});

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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  const _SignedOutState();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.lock_outline_rounded,
      title: 'Sign in to save trips',
      body: 'Your AI itineraries will appear here after you save them.',
      actionLabel: 'Sign In',
      onAction: () => context.go(AppRoutes.signIn),
    );
  }
}

class _EmptyTripsState extends StatelessWidget {
  const _EmptyTripsState();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.work_outline_rounded,
      title: 'No saved trips yet',
      body: 'Build an itinerary from Home, then save it to keep it here.',
      actionLabel: 'Plan a Trip',
      onAction: () => context.go(AppRoutes.home),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.error_outline_rounded,
      title: 'Trips could not load',
      body: message.replaceFirst('Exception: ', ''),
      actionLabel: 'Try Again',
      onAction: onRetry,
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
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RaasteShellColors.clay,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
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
