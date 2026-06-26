import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/services/destination_search_service.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';
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
                  padding: EdgeInsets.fromLTRB(padding, 20, padding, bottomInset),
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

// ─── Header ──────────────────────────────────────────────────────────────────

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
        _RoundIconButton(
          icon: Icons.person_rounded,
          onTap: () => showImplementingSoon(context),
        ),
      ],
    );
  }
}

// ─── Planner Hero ─────────────────────────────────────────────────────────────

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

    _debounce = Timer(const Duration(milliseconds: 900), () async {
      try {
        final results = await _searchService.autocomplete(query);
        if (!mounted || _controller.text.trim() != query) return;
        setState(() {
          _suggestions = results;
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
    final suggestion = _selectedSuggestion;
    final destination = suggestion?.name ?? _controller.text.trim();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Search a destination first')),
        );
      return;
    }

    if (suggestion == null || suggestion.lat == null || suggestion.lon == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Choose a destination from the search results')),
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
        final heroHeight = showSuggestions
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
          hintText: 'Search destinations in India',
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
                  'Search by OpenStreetMap',
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
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: RaasteShellColors.outline,
      ),
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

// ─── Preference Chips ─────────────────────────────────────────────────────────

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

// ─── Phase Cards ──────────────────────────────────────────────────────────────

class _PhaseCards extends StatelessWidget {
  const _PhaseCards();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cardWidth = ((w - 24) / 2.5).clamp(140.0, 210.0);

        return SizedBox(
          height: 220,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _PhaseCard(
                  title: 'Before Trip',
                  description: 'Briefing, itinerary, transport, packing',
                  icon: Icons.work_outline_rounded,
                  color: RaasteShellColors.sage,
                  width: cardWidth,
                ),
                const SizedBox(width: 12),
                _PhaseCard(
                  title: 'During Trip',
                  description: 'Ask anything, nearby food, local tips, offline guide',
                  icon: Icons.pin_drop_outlined,
                  color: RaasteShellColors.clay,
                  width: cardWidth,
                ),
                const SizedBox(width: 12),
                _PhaseCard(
                  title: 'After Trip',
                  description: 'Quick review and feedback',
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
    return Material(
      color: RaasteShellColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showImplementingSoon(context),
        child: Container(
          width: width,
          height: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
                radius: 20,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: color,
                  child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Current Trip Card ────────────────────────────────────────────────────────

class _CurrentTripCard extends StatelessWidget {
  const _CurrentTripCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RaasteShellColors.surfaceAlt,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => showImplementingSoon(context),
        child: Container(
          padding: const EdgeInsets.all(12),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 340;
              final imageWidget = ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/home_current_trip.png',
                  fit: BoxFit.cover,
                  height: compact ? 130 : 120,
                  width: compact ? double.infinity : 106,
                ),
              );
              final content = _CurrentTripContent(compact: compact);

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [imageWidget, const SizedBox(height: 12), content],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    imageWidget,
                    const SizedBox(width: 12),
                    Expanded(child: content),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CurrentTripContent extends StatelessWidget {
  final bool compact;
  const _CurrentTripContent({required this.compact});

  @override
  Widget build(BuildContext context) {
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
            Icon(Icons.more_horiz_rounded, color: RaasteShellColors.muted, size: 20),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Lonavala Weekend',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: RaasteShellColors.ink,
            fontFamily: 'serif',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Day 1 of 3',
          style: TextStyle(
            color: RaasteShellColors.clay,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: const LinearProgressIndicator(
            minHeight: 4,
            value: 0.32,
            backgroundColor: Color(0x14000000),
            color: RaasteShellColors.clay,
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallAction(icon: Icons.calendar_month_outlined, label: "Today's Plan"),
            _SmallAction(icon: Icons.download_rounded, label: 'Offline Guide'),
            _SmallAction(icon: Icons.chat_bubble_outline_rounded, label: 'Ask Guide'),
          ],
        ),
      ],
    );
  }
}

// ─── Popular Destinations ─────────────────────────────────────────────────────

class _PopularHeader extends StatelessWidget {
  const _PopularHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Popular right now',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: RaasteShellColors.ink,
              fontFamily: 'serif',
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: () => showImplementingSoon(context),
          style: TextButton.styleFrom(
            foregroundColor: RaasteShellColors.clay,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('View all'),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18),
            ],
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
        final w = constraints.maxWidth;
        final cardWidth = ((w - 14) / 1.85).clamp(190.0, 320.0);

        return SizedBox(
          height: 110,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _PopularCard(
                  image: 'assets/images/home_popular_jaipur_light.png',
                  title: 'Jaipur',
                  tag: 'Heritage',
                  meta: '4.6 · Rajasthan',
                  width: cardWidth,
                ),
                const SizedBox(width: 14),
                _PopularCard(
                  image: 'assets/images/home_popular_coorg_light.png',
                  title: 'Coorg',
                  tag: 'Nature',
                  meta: '4.7 · Karnataka',
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

class _PopularCard extends StatelessWidget {
  final String image;
  final String title;
  final String tag;
  final String meta;
  final double width;

  const _PopularCard({
    required this.image,
    required this.title,
    required this.tag,
    required this.meta,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RaasteShellColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showImplementingSoon(context),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: RaasteShellColors.shadow,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  image,
                  fit: BoxFit.cover,
                  height: 92,
                  width: 92,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.ink,
                        fontFamily: 'serif',
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x29C96F3D),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: RaasteShellColors.clay,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '★ $meta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 12,
                      ),
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

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RaasteShellColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: RaasteShellColors.ink, size: 24),
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
      child: Material(
        color: RaasteShellColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showImplementingSoon(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: RaasteShellColors.outline),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: RaasteShellColors.shadow, blurRadius: 8, offset: Offset(0, 4)),
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
      child: Material(
        color: RaasteShellColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showImplementingSoon(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: RaasteShellColors.outline),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: RaasteShellColors.shadow, blurRadius: 8, offset: Offset(0, 4)),
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
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showImplementingSoon(context),
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

