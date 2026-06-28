import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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
                      _TripMapSection(guide: guide),
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

class _TripMapSection extends StatefulWidget {
  final DestinationGuide guide;

  const _TripMapSection({required this.guide});

  @override
  State<_TripMapSection> createState() => _TripMapSectionState();
}

class _TripMapSectionState extends State<_TripMapSection> {
  int? _selectedDayNumber;

  List<ItineraryDay> get _daysWithPins =>
      widget.guide.itineraryDays
          .where((day) => _mapPinsForDay(day).isNotEmpty)
          .toList();

  @override
  void initState() {
    super.initState();
    final days = _daysWithPins;
    if (days.isNotEmpty) _selectedDayNumber = days.first.dayNumber;
  }

  @override
  void didUpdateWidget(covariant _TripMapSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final days = _daysWithPins;
    if (days.isEmpty) {
      _selectedDayNumber = null;
      return;
    }
    final selectedExists = days.any(
      (day) => day.dayNumber == _selectedDayNumber,
    );
    if (!selectedExists) _selectedDayNumber = days.first.dayNumber;
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysWithPins;
    if (days.isEmpty) {
      return const _GuideSection(
        title: 'Trip map',
        icon: Icons.map_outlined,
        child: _BodyText(
          'Map pins will appear here once the itinerary includes mapped stops.',
        ),
      );
    }

    final selectedDay = days.firstWhere(
      (day) => day.dayNumber == _selectedDayNumber,
      orElse: () => days.first,
    );
    final pins = _mapPinsForDay(selectedDay);
    final summary = _travelSummaryForGuide(widget.guide);

    return _GuideSection(
      title: 'Trip map',
      icon: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DayMapDropdown(
            days: days,
            selectedDay: selectedDay,
            onChanged: (dayNumber) {
              setState(() => _selectedDayNumber = dayNumber);
            },
          ),
          const SizedBox(height: 12),
          _InteractiveTripMap(day: selectedDay, pins: pins),
          const SizedBox(height: 14),
          _TravelTimeSummary(summary: summary),
        ],
      ),
    );
  }
}

class _DayMapDropdown extends StatelessWidget {
  final List<ItineraryDay> days;
  final ItineraryDay selectedDay;
  final ValueChanged<int> onChanged;

  const _DayMapDropdown({
    required this.days,
    required this.selectedDay,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EBDD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: const BoxDecoration(
              color: RaasteShellColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedDay.dayNumber,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    dropdownColor: const Color(0xFFFFFCF7),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: RaasteShellColors.ink,
                    ),
                    selectedItemBuilder:
                        (context) =>
                            days
                                .map(
                                  (day) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Day ${day.dayNumber}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: RaasteShellColors.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                    items:
                        days
                            .map(
                              (day) => DropdownMenuItem<int>(
                                value: day.dayNumber,
                                child: Text(
                                  'Day ${day.dayNumber} - ${day.title}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: RaasteShellColors.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value != null) onChanged(value);
                    },
                  ),
                ),
                Text(
                  selectedDay.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: RaasteShellColors.outline),
            ),
            child: Text(
              '${_mapPinsForDay(selectedDay).length} stops',
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveTripMap extends StatefulWidget {
  final ItineraryDay day;
  final List<_MapPin> pins;

  const _InteractiveTripMap({required this.day, required this.pins});

  @override
  State<_InteractiveTripMap> createState() => _InteractiveTripMapState();
}

class _InteractiveTripMapState extends State<_InteractiveTripMap> {
  late final MapController _controller;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
  }

  @override
  void didUpdateWidget(covariant _InteractiveTripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.dayNumber != widget.day.dayNumber ||
        oldWidget.pins.length != widget.pins.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToDay());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.pins.map((pin) => pin.point).toList();
    final center = _centerForPins(widget.pins);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 330,
        color: const Color(0xFFE9EFE2),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: center,
                initialZoom: widget.pins.length == 1 ? 15 : 13,
                initialCameraFit:
                    points.length > 1
                        ? CameraFit.coordinates(
                          coordinates: points,
                          padding: const EdgeInsets.fromLTRB(42, 72, 42, 72),
                          maxZoom: 15.5,
                        )
                        : null,
                minZoom: 4,
                maxZoom: 18,
                backgroundColor: const Color(0xFFE9EFE2),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _mapReady = true;
                  _fitToDay();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.raaste.raaste',
                  maxNativeZoom: 19,
                ),
                if (points.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: 4,
                        color: RaasteShellColors.clay.withValues(alpha: .78),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white.withValues(alpha: .9),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers:
                      widget.pins
                          .map(
                            (pin) => Marker(
                              point: pin.point,
                              width: 210,
                              height: 86,
                              alignment: Alignment.bottomCenter,
                              child: _MapMarkerLabel(pin: pin),
                            ),
                          )
                          .toList(),
                ),
                const SimpleAttributionWidget(
                  source: Text(
                    'OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10),
                  ),
                  backgroundColor: Color(0xDDFFFCF7),
                ),
              ],
            ),
            Positioned(
              right: 10,
              top: 10,
              child: _MapZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
                onFit: _fitToDay,
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _MapDayBadge(dayNumber: widget.day.dayNumber),
            ),
          ],
        ),
      ),
    );
  }

  void _fitToDay() {
    if (!_mapReady || widget.pins.isEmpty) return;
    final points = widget.pins.map((pin) => pin.point).toList();
    if (points.length == 1) {
      _controller.move(points.first, 15);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(42, 72, 42, 72),
        maxZoom: 15.5,
      ),
    );
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _controller.camera;
    final nextZoom = (camera.zoom + delta).clamp(4.0, 18.0).toDouble();
    _controller.move(camera.center, nextZoom);
  }
}

class _MapMarkerLabel extends StatelessWidget {
  final _MapPin pin;

  const _MapMarkerLabel({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RaasteShellColors.outline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 24,
                width: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: RaasteShellColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  pin.stopNumber.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  pin.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontSize: 11,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.location_pin,
          color: RaasteShellColors.clay,
          size: 34,
          shadows: [
            Shadow(
              color: Color(0x55000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEEFFFCF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapIconButton(icon: Icons.add_rounded, onTap: onZoomIn),
          const Divider(height: 1, color: RaasteShellColors.outline),
          _MapIconButton(icon: Icons.remove_rounded, onTap: onZoomOut),
          const Divider(height: 1, color: RaasteShellColors.outline),
          _MapIconButton(icon: Icons.center_focus_strong_rounded, onTap: onFit),
        ],
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 38,
          width: 38,
          child: Icon(icon, color: RaasteShellColors.ink, size: 20),
        ),
      ),
    );
  }
}

class _MapDayBadge extends StatelessWidget {
  final int dayNumber;

  const _MapDayBadge({required this.dayNumber});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEEFFFCF7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_rounded,
            color: RaasteShellColors.clay,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            'Day $dayNumber',
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelTimeSummary extends StatelessWidget {
  final _TravelSummary summary;

  const _TravelTimeSummary({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5EBDD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: const BoxDecoration(
              color: RaasteShellColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.primaryText,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.secondaryText,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _MapPin {
  final int dayNumber;
  final int stopNumber;
  final String title;
  final LatLng point;

  const _MapPin({
    required this.dayNumber,
    required this.stopNumber,
    required this.title,
    required this.point,
  });
}

class _TravelSummary {
  final String primaryText;
  final String secondaryText;

  const _TravelSummary({
    required this.primaryText,
    required this.secondaryText,
  });
}

List<_MapPin> _mapPinsForDay(ItineraryDay day) {
  final pins = <_MapPin>[];
  final seen = <String>{};

  for (final stop in _visibleStops(day.stops)) {
    final lat = stop.lat;
    final lon = stop.lon;
    if (lat == null || lon == null) continue;
    if (lat.abs() < 0.0001 && lon.abs() < 0.0001) continue;

    final key =
        '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}:${stop.title.toLowerCase()}';
    if (seen.contains(key)) continue;
    seen.add(key);

    pins.add(
      _MapPin(
        dayNumber: day.dayNumber,
        stopNumber: pins.length + 1,
        title:
            stop.title.trim().isEmpty ? 'Stop ${pins.length + 1}' : stop.title,
        point: LatLng(lat, lon),
      ),
    );
  }

  return pins;
}

LatLng _centerForPins(List<_MapPin> pins) {
  if (pins.isEmpty) return const LatLng(20.5937, 78.9629);
  final totalLat = pins.fold<double>(0, (sum, pin) => sum + pin.point.latitude);
  final totalLon = pins.fold<double>(
    0,
    (sum, pin) => sum + pin.point.longitude,
  );
  return LatLng(totalLat / pins.length, totalLon / pins.length);
}

_TravelSummary _travelSummaryForGuide(DestinationGuide guide) {
  final timingRoutes = guide.timingContext?.routes ?? const [];
  final dayCount = math.max(guide.itineraryDays.length, 1);
  final totalRouteMinutes = timingRoutes.fold<int>(
    0,
    (sum, route) => sum + math.max(route.durationMinutes, 0),
  );

  if (totalRouteMinutes > 0) {
    final avg = (totalRouteMinutes / dayCount).round();
    return _TravelSummary(
      primaryText: 'Average travel time: ${_durationLabel(avg)} per day',
      secondaryText:
          'Based on ${timingRoutes.length} Google route estimate${timingRoutes.length == 1 ? '' : 's'} for this itinerary. Actual traffic may vary.',
    );
  }

  final fallbackAverage = _fallbackDailyTravelAverage(guide.itineraryDays);
  if (fallbackAverage <= 0) {
    return const _TravelSummary(
      primaryText: 'Average travel time: not enough mapped data',
      secondaryText:
          'Mapped stops are available, but there is not enough route data yet to estimate daily travel time.',
    );
  }

  return _TravelSummary(
    primaryText:
        'Average travel time: ${_durationLabel(fallbackAverage)} per day',
    secondaryText:
        'Estimated from the spacing between mapped itinerary stops. Generate or edit the trip with Google route timing for sharper estimates.',
  );
}

int _fallbackDailyTravelAverage(List<ItineraryDay> days) {
  if (days.isEmpty) return 0;
  final estimates = <int>[];
  for (final day in days) {
    final mappedStops =
        _visibleStops(
          day.stops,
        ).where((stop) => stop.lat != null && stop.lon != null).toList();
    if (mappedStops.length < 2) {
      estimates.add(0);
      continue;
    }

    var dayMinutes = 0;
    for (var i = 0; i < mappedStops.length - 1; i++) {
      dayMinutes += _roughTravelMinutes(
        mappedStops[i].lat!,
        mappedStops[i].lon!,
        mappedStops[i + 1].lat!,
        mappedStops[i + 1].lon!,
      );
    }
    estimates.add(dayMinutes);
  }

  final total = estimates.fold<int>(0, (sum, item) => sum + item);
  return (total / math.max(estimates.length, 1)).round();
}

int _roughTravelMinutes(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degreesToRadians(lat2 - lat1);
  final dLon = _degreesToRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(lat1)) *
          math.cos(_degreesToRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  final km = earthRadiusKm * c;
  return math.max(8, (km / 18 * 60).round());
}

double _degreesToRadians(double value) => value * math.pi / 180;

String _durationLabel(int minutes) {
  if (minutes <= 0) return 'Not enough mapped data';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) return '${hours}h';
  return '${hours}h ${mins}m';
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
