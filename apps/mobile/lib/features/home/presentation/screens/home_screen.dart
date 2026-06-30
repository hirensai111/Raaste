import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/services/destination_search_service.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';
import 'package:raaste/features/home/domain/models/popular_attraction.dart';
import 'package:raaste/features/home/presentation/widgets/popular_destination_image.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _firstName = 'Hiren';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  void _loadUserName() {
    final user = Supabase.instance.client.auth.currentUser;
    final firstName = user?.userMetadata?['first_name'] as String?;
    if (firstName != null && firstName.isNotEmpty) {
      setState(() => _firstName = firstName);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: RaasteShellColors.background,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: RaasteShellColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    final bottomInset = MediaQuery.of(context).padding.bottom + 76 + 12 + 16;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.home,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final padding = w < 380 ? 18.0 : 22.0;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    20,
                    padding,
                    bottomInset,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _Header(firstName: _firstName),
                      const SizedBox(height: 18),
                      const _PlannerHero(),
                      const SizedBox(height: 16),
                      const _PreferenceChips(),
                      const SizedBox(height: 18),
                      const _PhaseCards(),
                      const SizedBox(height: 16),
                      const _CurrentTripCard(),
                      const SizedBox(height: 20),
                      const _PopularHeader(),
                      const SizedBox(height: 12),
                      const _PopularDestinations(),
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

// Header

class _Header extends StatelessWidget {
  final String firstName;
  const _Header({required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, c) {
                  final compact = c.maxWidth < 300;
                  final logoSize = compact ? 44.0 : 52.0;
                  final wordmarkSize = compact ? 38.0 : 46.0;

                  return Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/raaste_logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Raaste',
                            style: TextStyle(
                              color: RaasteShellColors.ink,
                              fontFamily: 'serif',
                              fontSize: wordmarkSize,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'Smart guide. Local insights. Better journeys.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 13,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _ProfileInitialAvatar(firstName: firstName),
      ],
    );
  }
}

// Planner Hero

class _PlannerHero extends StatefulWidget {
  const _PlannerHero();

  @override
  State<_PlannerHero> createState() => _PlannerHeroState();
}

class _PlannerHeroState extends State<_PlannerHero> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _searchService = getIt<DestinationSearchService>();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  PlaceSuggestion? _selectedSuggestion;
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _selectedSuggestion = null;
    _debounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    _debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await _searchService.autocomplete(query);
        if (!mounted || _controller.text.trim() != query) return;
        setState(() {
          _suggestions = results;
          _searchError =
              results.isEmpty
                  ? 'Raaste currently supports Hyderabad, Lonavala, and Varanasi.'
                  : null;
          _isSearching = false;
        });
      } on DestinationSearchException catch (e) {
        if (!mounted) return;
        setState(() {
          _suggestions = const [];
          _searchError = e.message;
          _isSearching = false;
        });
      }
    });
  }

  void _selectSuggestion(PlaceSuggestion suggestion) {
    setState(() {
      _selectedSuggestion = suggestion;
      _controller.text = suggestion.name;
      _suggestions = const [];
      _searchError = null;
    });
    _focusNode.unfocus();
  }

  void _startPlanning() {
    final typedDestination = _controller.text.trim();
    final suggestion =
        _selectedSuggestion ??
        _searchService.findCuratedDestination(typedDestination);
    final destination = suggestion?.name ?? typedDestination;
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Search a destination first')),
        );
      return;
    }

    if (suggestion == null ||
        suggestion.lat == null ||
        suggestion.lon == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Choose Hyderabad, Lonavala, or Varanasi from Raaste destinations',
            ),
          ),
        );
      return;
    }

    final uri = Uri(
      path: AppRoutes.destinationChat,
      queryParameters: {
        'destination': destination,
        'sourceId': suggestion.sourceId,
        'displayAddress': suggestion.displayAddress,
        'lat': suggestion.lat.toString(),
        'lon': suggestion.lon.toString(),
      },
    );
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final showSuggestions =
            _isSearching || _searchError != null || _suggestions.isNotEmpty;
        final heroHeight =
            showSuggestions
                ? (w * 1.02).clamp(350.0, 420.0).toDouble()
                : (w * 0.62).clamp(224.0, 260.0).toDouble();
        final compact = w < 390;
        final innerPadding = compact ? 16.0 : 20.0;

        return SizedBox(
          height: heroHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/home_hero_art.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.topRight,
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.transparent,
                          Color(0xB8647A55),
                          RaasteShellColors.sage,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(innerPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.travel_explore_rounded,
                              color: RaasteShellColors.background,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Where are you going?',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'serif',
                                  fontSize: compact ? 20 : 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _SearchBox(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _onQueryChanged,
                          onSubmitted: _startPlanning,
                        ),
                        if (showSuggestions) ...[
                          const SizedBox(height: 10),
                          _SuggestionPanel(
                            suggestions: _suggestions,
                            isLoading: _isSearching,
                            error: _searchError,
                            onSelect: _selectSuggestion,
                          ),
                        ],
                        const Spacer(),
                        _PrimaryButton(
                          label: 'Plan My Trip',
                          icon: Icons.navigation_rounded,
                          onTap: _startPlanning,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEAFFFFFF),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted(),
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: RaasteShellColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          hintText: 'Search Raaste destinations',
          hintStyle: TextStyle(color: Colors.grey, fontWeight: FontWeight.w400),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: RaasteShellColors.ink,
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        ),
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  final List<PlaceSuggestion> suggestions;
  final bool isLoading;
  final String? error;
  final ValueChanged<PlaceSuggestion> onSelect;

  const _SuggestionPanel({
    required this.suggestions,
    required this.isLoading,
    required this.error,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 136),
      decoration: BoxDecoration(
        color: const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: RaasteShellColors.clay,
                backgroundColor: Colors.transparent,
              ),
            Flexible(child: _buildBody()),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Raaste curated destinations',
                  style: TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            error!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ),
      );
    }

    if (suggestions.isEmpty) {
      return const SizedBox(height: 34);
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: suggestions.length,
      separatorBuilder:
          (_, __) => const Divider(height: 1, color: RaasteShellColors.outline),
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return InkWell(
          onTap: () => onSelect(suggestion),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  color: RaasteShellColors.sage,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RaasteShellColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        suggestion.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RaasteShellColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RaasteShellColors.clay,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// Preference Chips

class _PreferenceChips extends StatelessWidget {
  const _PreferenceChips();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: BouncingScrollPhysics(),
      child: Row(
        children: [
          _Chip(icon: Icons.eco_rounded, label: 'Veg'),
          _Chip(icon: Icons.back_hand_outlined, label: 'Jain'),
          _ChipTextIcon(text: 'H', label: 'Halal'),
          _Chip(icon: Icons.landscape_rounded, label: 'Nature'),
          _Chip(icon: Icons.room_service_rounded, label: 'Food'),
          _Chip(icon: Icons.account_balance_outlined, label: 'History'),
        ],
      ),
    );
  }
}

// Phase Cards

class _PhaseCards extends StatelessWidget {
  const _PhaseCards();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cardWidth = ((w - 24) / 2.2).clamp(164.0, 230.0);

        return SizedBox(
          height: 226,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _PhaseCard(
                  title: 'Before Trip',
                  description:
                      'Trip briefing, AI itinerary, transport choices, packing checklist',
                  icon: Icons.work_outline_rounded,
                  color: RaasteShellColors.sage,
                  width: cardWidth,
                ),
                const SizedBox(width: 12),
                _PhaseCard(
                  title: 'During Trip',
                  description:
                      'Ask anything, nearby food, local tips, safety help, offline guide',
                  icon: Icons.pin_drop_outlined,
                  color: RaasteShellColors.clay,
                  width: cardWidth,
                ),
                const SizedBox(width: 12),
                _PhaseCard(
                  title: 'After Trip',
                  description:
                      'Quick reviews, trip notes, feedback, saved memories',
                  icon: Icons.camera_alt_outlined,
                  color: const Color(0xFF6B6885),
                  width: cardWidth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhaseCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final double width;

  const _PhaseCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 226,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RaasteShellColors.surface,
        border: Border.all(color: RaasteShellColors.outline),
        borderRadius: BorderRadius.circular(20),
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
          CircleAvatar(
            radius: 22,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontFamily: 'serif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              description,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.34,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentTripCard extends StatefulWidget {
  const _CurrentTripCard();

  @override
  State<_CurrentTripCard> createState() => _CurrentTripCardState();
}

class _CurrentTripCardState extends State<_CurrentTripCard> {
  late final Future<_CurrentTripLookup> _lookupFuture = _loadCurrentTrip();

  Future<_CurrentTripLookup> _loadCurrentTrip() async {
    try {
      final trips = await getIt<SavedTripRepository>().listTrips();
      final now = DateTime.now();

      for (final trip in trips) {
        final range = _parseTripDateRange(_tripDateText(trip), now);
        if (range != null && range.contains(now)) {
          return _CurrentTripLookup(trip: trip, range: range);
        }
      }

      return const _CurrentTripLookup();
    } on SavedTripException catch (error) {
      return _CurrentTripLookup(error: error.message);
    } catch (_) {
      return const _CurrentTripLookup(
        error: 'Could not check your current trips right now.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CurrentTripLookup>(
      future: _lookupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _CurrentTripLoadingCard();
        }

        final lookup = snapshot.data ?? const _CurrentTripLookup();
        if (lookup.trip != null && lookup.range != null) {
          return _CurrentTripTile(trip: lookup.trip!, range: lookup.range!);
        }

        if (lookup.error != null) {
          return _NoCurrentTripCard(
            title: 'Current trip unavailable',
            subtitle: lookup.error!,
            icon: Icons.cloud_off_rounded,
          );
        }

        return const _NoCurrentTripCard(
          title: 'No ongoing trips',
          subtitle:
              'Saved trips will appear here automatically when their travel dates are active.',
          icon: Icons.luggage_rounded,
        );
      },
    );
  }
}

class _CurrentTripLookup {
  final SavedTrip? trip;
  final _TripDateRange? range;
  final String? error;

  const _CurrentTripLookup({this.trip, this.range, this.error});
}

class _CurrentTripTile extends StatelessWidget {
  final SavedTrip trip;
  final _TripDateRange range;

  const _CurrentTripTile({required this.trip, required this.range});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RaasteShellColors.surfaceAlt,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          final imageWidget = _CurrentTripImage(trip: trip, compact: compact);
          final content = _CurrentTripContent(
            trip: trip,
            range: range,
            compact: compact,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [imageWidget, const SizedBox(height: 12), content],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              imageWidget,
              const SizedBox(width: 12),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

void _openCurrentTripItinerary(BuildContext context, SavedTrip trip) {
  final uri = Uri(
    path: AppRoutes.destination,
    queryParameters: {'tripId': trip.id},
  );
  context.go(uri.toString());
}

void _openCurrentTripCompanion(BuildContext context, SavedTrip trip) {
  final uri = Uri(
    path: AppRoutes.companion,
    queryParameters: {'tripId': trip.id},
  );
  context.go(uri.toString());
}

class _CurrentTripImage extends StatelessWidget {
  final SavedTrip trip;
  final bool compact;

  const _CurrentTripImage({required this.trip, required this.compact});

  @override
  Widget build(BuildContext context) {
    final imagePath =
        trip.imageUrl.trim().isNotEmpty
            ? trip.imageUrl.trim()
            : 'assets/images/home_current_trip.png';

    Widget image;
    if (trip.hasRemoteImage) {
      image = Image.network(
        imagePath,
        fit: BoxFit.cover,
        height: compact ? 130 : 120,
        width: compact ? double.infinity : 106,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    } else {
      image = Image.asset(
        imagePath,
        fit: BoxFit.cover,
        height: compact ? 130 : 120,
        width: compact ? double.infinity : 106,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    }

    return ClipRRect(borderRadius: BorderRadius.circular(14), child: image);
  }

  Widget _fallbackImage() {
    return Image.asset(
      'assets/images/home_current_trip.png',
      fit: BoxFit.cover,
      height: compact ? 130 : 120,
      width: compact ? double.infinity : 106,
    );
  }
}

class _CurrentTripContent extends StatelessWidget {
  final SavedTrip trip;
  final _TripDateRange range;
  final bool compact;

  const _CurrentTripContent({
    required this.trip,
    required this.range,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final destination =
        trip.destinationName.trim().isNotEmpty
            ? trip.destinationName.trim()
            : trip.guide.destinationName.trim();
    final title =
        destination.toLowerCase().contains('trip')
            ? destination
            : '$destination Trip';
    final dayNumber = range.dayNumber(DateTime.now());
    final totalDays = range.totalDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.circle, color: Color(0xFF9EB37B), size: 10),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'CURRENT TRIP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Icon(
              Icons.more_horiz_rounded,
              color: RaasteShellColors.muted,
              size: 20,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: RaasteShellColors.ink,
            fontFamily: 'serif',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Day $dayNumber of $totalDays',
          style: const TextStyle(
            color: RaasteShellColors.clay,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: dayNumber / totalDays,
            backgroundColor: const Color(0x14000000),
            color: RaasteShellColors.clay,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallAction(
              icon: Icons.calendar_month_outlined,
              label: 'Itinerary',
              onTap: () => _openCurrentTripItinerary(context, trip),
            ),
            _SmallAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Ask Guide',
              onTap: () => _openCurrentTripCompanion(context, trip),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurrentTripLoadingCard extends StatelessWidget {
  const _CurrentTripLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RaasteShellColors.surfaceAlt,
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
      child: const Row(
        children: [
          SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: RaasteShellColors.ink,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Checking your saved trips...',
              style: TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoCurrentTripCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _NoCurrentTripCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RaasteShellColors.surfaceAlt,
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
      child: Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFE5D8C7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: RaasteShellColors.ink, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontFamily: 'serif',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
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

class _TripDateRange {
  final DateTime start;
  final DateTime end;

  const _TripDateRange({required this.start, required this.end});

  int get totalDays => end.difference(start).inDays + 1;

  bool contains(DateTime value) {
    final day = _dateOnly(value);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  int dayNumber(DateTime value) {
    final rawDay = _dateOnly(value).difference(start).inDays + 1;
    return rawDay.clamp(1, totalDays).toInt();
  }
}

String _tripDateText(SavedTrip trip) {
  final savedDates = trip.dates.trim();
  if (savedDates.isNotEmpty) return savedDates;
  return trip.guide.intake.dates.trim();
}

_TripDateRange? _parseTripDateRange(String raw, DateTime now) {
  var text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  text = text
      .replaceAll(',', ' ')
      .replaceAll('.', ' ')
      .replaceAll('until', 'to')
      .replaceAll('till', 'to')
      .replaceAll('through', 'to')
      .replaceAll('â€“', '-')
      .replaceAll('â€”', '-')
      // Separate a glued ordinal+word, e.g. "4thjuly" -> "4th july".
      // NOTE: replaceAll does NOT expand $1/$2 backreferences for String
      // replacements, so we must use replaceAllMapped with a callback.
      .replaceAllMapped(
        RegExp(r'(\d)(st|nd|rd|th)([a-z])'),
        (m) => '${m[1]}${m[2]} ${m[3]}',
      )
      // Separate a digit glued to a non-ordinal word, e.g. "12august" ->
      // "12 august". Do NOT split ordinal suffixes ("1st", "4th") because the
      // date regexes below rely on them staying attached to the number.
      .replaceAllMapped(
        RegExp(r'(\d)(?!st\b|nd\b|rd\b|th\b)([a-z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAll(RegExp(r'\s+'), ' ');

  final fallbackYear = _extractYear(text) ?? now.year;

  final isoMatches =
      RegExp(
        r'\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b',
      ).allMatches(text).toList();
  if (isoMatches.length >= 2) {
    return _buildDateRange(
      _intValue(isoMatches.first.group(1)),
      _intValue(isoMatches.first.group(2)),
      _intValue(isoMatches.first.group(3)),
      _intValue(isoMatches[1].group(1)),
      _intValue(isoMatches[1].group(2)),
      _intValue(isoMatches[1].group(3)),
    );
  }

  final numericRange = RegExp(
    r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\s*(?:-|to)\s*(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b',
  ).firstMatch(text);
  if (numericRange != null) {
    final startYear = _normalizeYear(numericRange.group(3), fallbackYear);
    final endYear = _normalizeYear(numericRange.group(6), startYear);
    return _buildDateRange(
      startYear,
      _intValue(numericRange.group(2)),
      _intValue(numericRange.group(1)),
      endYear,
      _intValue(numericRange.group(5)),
      _intValue(numericRange.group(4)),
    );
  }

  final dayMonthRange = RegExp(
    '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+($_monthPattern)\\s*(?:-|to)\\s*(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+($_monthPattern))?\\b',
  ).firstMatch(text);
  if (dayMonthRange != null) {
    final startMonth = _monthNumber(dayMonthRange.group(2));
    final endMonth = _monthNumber(dayMonthRange.group(4)) ?? startMonth;
    if (startMonth != null && endMonth != null) {
      return _buildDateRange(
        fallbackYear,
        startMonth,
        _intValue(dayMonthRange.group(1)),
        fallbackYear,
        endMonth,
        _intValue(dayMonthRange.group(3)),
      );
    }
  }

  final dayRangeMonth = RegExp(
    '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s*(?:-|to)\\s*(\\d{1,2})(?:st|nd|rd|th)?\\s+($_monthPattern)\\b',
  ).firstMatch(text);
  if (dayRangeMonth != null) {
    final month = _monthNumber(dayRangeMonth.group(3));
    if (month != null) {
      return _buildDateRange(
        fallbackYear,
        month,
        _intValue(dayRangeMonth.group(1)),
        fallbackYear,
        month,
        _intValue(dayRangeMonth.group(2)),
      );
    }
  }

  final monthDayRange = RegExp(
    '\\b($_monthPattern)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\s*(?:-|to)\\s*(?:(\\w+)\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\b',
  ).firstMatch(text);
  if (monthDayRange != null) {
    final startMonth = _monthNumber(monthDayRange.group(1));
    final endMonth = _monthNumber(monthDayRange.group(3)) ?? startMonth;
    if (startMonth != null && endMonth != null) {
      return _buildDateRange(
        fallbackYear,
        startMonth,
        _intValue(monthDayRange.group(2)),
        fallbackYear,
        endMonth,
        _intValue(monthDayRange.group(4)),
      );
    }
  }

  final singleDay = RegExp(
    '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+($_monthPattern)\\b',
  ).firstMatch(text);
  if (singleDay != null) {
    final month = _monthNumber(singleDay.group(2));
    if (month != null) {
      return _buildDateRange(
        fallbackYear,
        month,
        _intValue(singleDay.group(1)),
        fallbackYear,
        month,
        _intValue(singleDay.group(1)),
      );
    }
  }

  return null;
}

const _monthPattern =
    'jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december';

const _monthNumbers = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

int? _monthNumber(String? value) => _monthNumbers[value?.trim().toLowerCase()];

int? _extractYear(String text) {
  final match = RegExp(r'\b(20\d{2}|19\d{2})\b').firstMatch(text);
  return int.tryParse(match?.group(1) ?? '');
}

int _normalizeYear(String? rawYear, int fallbackYear) {
  final parsed = int.tryParse(rawYear ?? '');
  if (parsed == null) return fallbackYear;
  return parsed < 100 ? 2000 + parsed : parsed;
}

int _intValue(String? value) => int.tryParse(value ?? '') ?? 1;

_TripDateRange? _buildDateRange(
  int startYear,
  int startMonth,
  int startDay,
  int endYear,
  int endMonth,
  int endDay,
) {
  final start = _safeDate(startYear, startMonth, startDay);
  var end = _safeDate(endYear, endMonth, endDay);
  if (start == null || end == null) return null;
  if (end.isBefore(start)) {
    end = _safeDate(end.year + 1, end.month, end.day);
  }
  if (end == null) return null;
  return _TripDateRange(start: start, end: end);
}

DateTime? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final value = DateTime(year, month, day);
  if (value.year != year || value.month != month || value.day != day) {
    return null;
  }
  return _dateOnly(value);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
// Popular Destinations

class _PopularHeader extends StatelessWidget {
  const _PopularHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Popular destinations',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Top places people are planning across India',
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
        const SizedBox(width: 10),
        Material(
          color: RaasteShellColors.ink,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => context.go(AppRoutes.popularAttractions),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View more',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 5),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopularDestinations extends StatelessWidget {
  const _PopularDestinations();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewCount = constraints.maxWidth < 350 ? 1 : 2;
        final attractions = popularAttractions.take(previewCount).toList();

        if (previewCount == 1) {
          return _PopularCard(attraction: attractions.first);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < attractions.length; index++) ...[
              if (index > 0) const SizedBox(width: 12),
              Expanded(
                child: _PopularCard(
                  attraction: attractions[index],
                  compact: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PopularCard extends StatelessWidget {
  final PopularAttraction attraction;
  final bool compact;

  const _PopularCard({required this.attraction, this.compact = false});

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
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PopularDestinationImage(
                attraction: attraction,
                height: compact ? 104 : 150,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            attraction.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: RaasteShellColors.ink,
                              fontFamily: 'serif',
                              fontSize: compact ? 18 : 25,
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
                    const SizedBox(height: 7),
                    Text(
                      attraction.location,
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
                      children:
                          attraction.tags
                              .take(compact ? 2 : 3)
                              .map((tag) => _PopularTag(label: tag))
                              .toList(),
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

class _PopularTag extends StatelessWidget {
  final String label;

  const _PopularTag({required this.label});

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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileInitialAvatar extends StatelessWidget {
  final String firstName;

  const _ProfileInitialAvatar({required this.firstName});

  @override
  Widget build(BuildContext context) {
    final trimmedName = firstName.trim();
    final initial =
        trimmedName.isEmpty ? '?' : trimmedName.substring(0, 1).toUpperCase();

    return Semantics(
      label: trimmedName.isEmpty ? 'Profile' : 'Profile for $trimmedName',
      child: Container(
        height: 52,
        width: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RaasteShellColors.surface,
          border: Border.all(color: RaasteShellColors.outline),
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: const TextStyle(
            color: RaasteShellColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: RaasteShellColors.surface,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RaasteShellColors.sage, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipTextIcon extends StatelessWidget {
  final String text;
  final String label;

  const _ChipTextIcon({required this.text, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: RaasteShellColors.surface,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: const TextStyle(
                color: RaasteShellColors.sage,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: RaasteShellColors.ink, size: 15),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
