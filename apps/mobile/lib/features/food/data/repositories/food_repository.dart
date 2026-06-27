import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/food/domain/models/restaurant_recommendation.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';

class FoodDiscoveryData {
  final SavedTrip? trip;
  final String dietaryPreference;
  final List<RestaurantRecommendation> restaurants;
  final String message;

  const FoodDiscoveryData({
    required this.trip,
    required this.dietaryPreference,
    required this.restaurants,
    required this.message,
  });
}

class FoodRepository {
  static const _hyderabadRestaurantsAsset =
      'assets/research/hyderabad_raaste_restaurants.json';

  final SavedTripRepository _savedTrips;
  final AssetBundle _bundle;

  FoodRepository({SavedTripRepository? savedTrips, AssetBundle? bundle})
    : _savedTrips = savedTrips ?? SavedTripRepository(),
      _bundle = bundle ?? rootBundle;

  Future<FoodDiscoveryData> loadDiscovery() async {
    final trips = await _savedTrips.listTrips();
    final trip = _pickTrip(trips);
    if (trip == null) {
      return const FoodDiscoveryData(
        trip: null,
        dietaryPreference: '',
        restaurants: [],
        message: 'Save a trip first to see food picks matched to your diet.',
      );
    }

    final destination = _destinationText(trip);
    if (!destination.contains('hyderabad') &&
        !destination.contains('secunderabad')) {
      return FoodDiscoveryData(
        trip: trip,
        dietaryPreference: _dietaryPreference(trip),
        restaurants: const [],
        message:
            'Curated food picks are available for Hyderabad right now. More cities are next.',
      );
    }

    final restaurants = await _loadHyderabadRestaurants();
    final dietary = _dietaryPreference(trip);
    final filtered = _filterByDiet(restaurants, dietary);

    return FoodDiscoveryData(
      trip: trip,
      dietaryPreference: dietary,
      restaurants: filtered,
      message:
          filtered.isEmpty
              ? 'No restaurants matched this dietary preference yet.'
              : 'Pre-filtered for ${_friendlyDiet(dietary)} from your trip.',
    );
  }

  Future<void> addRestaurantToItinerary({
    required SavedTrip trip,
    required RestaurantRecommendation restaurant,
    required int dayNumber,
    required String mealSlot,
    required String mealTime,
  }) async {
    final latestTrip = await _savedTrips.getTrip(trip.id);
    final guide = (latestTrip ?? trip).guide;
    final days = guide.itineraryDays;
    if (days.isEmpty) return;

    final safeDay = dayNumber.clamp(1, days.length).toInt();
    final normalizedSlot = mealSlot.trim().toLowerCase();
    final selectedDay = days.firstWhere(
      (day) => day.dayNumber == safeDay,
      orElse: () => days[(safeDay - 1).clamp(0, days.length - 1).toInt()],
    );
    final requestedMealTime =
        mealTime.trim().isEmpty
            ? _replacementMealTime(selectedDay.stops, normalizedSlot)
            : mealTime.trim();
    final stop = ItineraryStop(
      time: requestedMealTime,
      title: '${_titleForMeal(normalizedSlot)} at ${restaurant.name}',
      description:
          '${restaurant.speciality}. ${restaurant.description} Local tip: ${restaurant.localTip} Prices and timings may vary; verify before travel.',
      type: 'restaurant:$normalizedSlot',
      sourceId: 'restaurant:${restaurant.id}',
      lat: null,
      lon: null,
    );

    final updatedDays = <ItineraryDay>[];
    for (final day in days) {
      if (day.dayNumber != safeDay) {
        updatedDays.add(day);
        continue;
      }
      final cleanedStops =
          day.stops
              .where(
                (existing) =>
                    !_isSameMealSlot(
                      existing,
                      mealSlot: normalizedSlot,
                      mealTime: requestedMealTime,
                    ),
              )
              .toList();
      final stops = _resolvedDayStops([...cleanedStops, stop]);
      updatedDays.add(
        ItineraryDay(
          dayNumber: day.dayNumber,
          title: day.title,
          subtitle: day.subtitle,
          stops: stops,
        ),
      );
    }

    final updatedGuide = guide.copyWith(
      itineraryDays: updatedDays,
      updatedAt: DateTime.now(),
    );
    await _savedTrips.updateTripGuide(tripId: trip.id, guide: updatedGuide);
  }

  Future<List<RestaurantRecommendation>> _loadHyderabadRestaurants() async {
    final raw = await _bundle.loadString(_hyderabadRestaurantsAsset);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['restaurants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RestaurantRecommendation.fromJson)
        .toList();
  }

  List<RestaurantRecommendation> _filterByDiet(
    List<RestaurantRecommendation> restaurants,
    String preference,
  ) {
    final diet = preference.toLowerCase();
    final filtered =
        restaurants.where((restaurant) {
          if (diet.contains('jain')) return restaurant.jainAvailable;
          if (diet.contains('halal')) return restaurant.halalCertified;
          if (diet.contains('vegan')) return restaurant.veganOptions;
          if (diet.contains('veg') && !diet.contains('non')) {
            return restaurant.isVegOnly ||
                restaurant.jainAvailable ||
                restaurant.veganOptions;
          }
          if (diet.contains('non')) return restaurant.nonVegAvailable;
          return true;
        }).toList();

    filtered.sort((a, b) {
      if (a.isTouristTrap != b.isTouristTrap) return a.isTouristTrap ? 1 : -1;
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  SavedTrip? _pickTrip(List<SavedTrip> trips) {
    if (trips.isEmpty) return null;
    final today = _dateOnly(DateTime.now());
    final withRange = <_TripWithRange>[];

    for (final trip in trips) {
      final range = _parseTripDateRange(_tripDateText(trip), today);
      if (range != null) {
        withRange.add(_TripWithRange(trip: trip, range: range));
      }
    }

    final active =
        withRange
            .where(
              (item) =>
                  !today.isBefore(item.range.start) &&
                  !today.isAfter(item.range.end),
            )
            .toList()
          ..sort((a, b) => a.range.start.compareTo(b.range.start));
    if (active.isNotEmpty) return active.first.trip;

    final upcoming =
        withRange.where((item) => item.range.start.isAfter(today)).toList()
          ..sort((a, b) => a.range.start.compareTo(b.range.start));
    if (upcoming.isNotEmpty) return upcoming.first.trip;

    final planned =
        trips
            .where((trip) => trip.status.toLowerCase() != 'completed')
            .toList();
    return planned.isNotEmpty ? planned.first : trips.first;
  }

  String _dietaryPreference(SavedTrip trip) {
    final value = trip.guide.intake.dietaryPreference.trim();
    return value.isEmpty ? 'No specific preference' : value;
  }

  String _destinationText(SavedTrip trip) {
    return [
      trip.destinationName,
      trip.destinationAddress,
      trip.guide.destinationName,
      trip.guide.intake.destination,
      trip.guide.intake.displayAddress,
    ].join(' ').toLowerCase();
  }
}

class _TripWithRange {
  final SavedTrip trip;
  final _TripDateRange range;

  const _TripWithRange({required this.trip, required this.range});
}

class _TripDateRange {
  final DateTime start;
  final DateTime end;

  const _TripDateRange({required this.start, required this.end});
}

String _tripDateText(SavedTrip trip) {
  final savedDates = trip.dates.trim();
  if (savedDates.isNotEmpty) return savedDates;
  return trip.guide.intake.dates.trim();
}

_TripDateRange? _parseTripDateRange(String raw, DateTime now) {
  var text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  text =
      text
          .replaceAll(',', ' ')
          .replaceAll('.', ' ')
          .replaceAll('until', 'to')
          .replaceAll('till', 'to')
          .replaceAll('through', 'to')
          .replaceAll(RegExp(r'(\d)(st|nd|rd|th)([a-z])'), r'$1$2 $3')
          .replaceAll(RegExp(r'(\d)(?!(?:st|nd|rd|th)\b)([a-z])'), r'$1 $2')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

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

String _friendlyDiet(String value) {
  final diet = value.trim();
  return diet.isEmpty ? 'your dietary preference' : diet;
}

bool _isSameMealSlot(
  ItineraryStop stop, {
  required String mealSlot,
  required String mealTime,
}) {
  final slot = _slotForExistingStop(stop);
  if (slot == mealSlot) return true;
  if (slot != null) return false;

  final stopMinutes = _minutes(stop.time);
  final mealMinutes = _minutes(mealTime);
  return (stopMinutes - mealMinutes).abs() <= 45 &&
      stop.type.toLowerCase().contains('meal');
}

String _replacementMealTime(List<ItineraryStop> stops, String mealSlot) {
  String? userAddedTime;
  String? plannedMealTime;
  String? anyMealTime;

  for (final stop in stops) {
    if (_slotForExistingStop(stop) != mealSlot) continue;
    anyMealTime ??= stop.time;
    if (_isUserAddedRestaurant(stop)) {
      userAddedTime = stop.time;
    } else {
      plannedMealTime ??= stop.time;
    }
  }

  return plannedMealTime ??
      userAddedTime ??
      anyMealTime ??
      _timeForMeal(mealSlot);
}

String? _slotForExistingStop(ItineraryStop stop) {
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
  final minutes = _minutes(stop.time);
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

String _timeForMeal(String mealSlot) {
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

String _titleForMeal(String mealSlot) {
  switch (mealSlot) {
    case 'breakfast':
      return 'Breakfast';
    case 'lunch':
      return 'Lunch';
    case 'snack':
      return 'Snack';
    case 'dinner':
    default:
      return 'Dinner';
  }
}

List<ItineraryStop> _resolvedDayStops(List<ItineraryStop> stops) {
  final sorted = [...stops]..sort(_compareStopsByTime);
  final resolved = <ItineraryStop>[];
  var nextAvailable = 0;

  for (final stop in sorted) {
    final range = _rangeForStop(stop);
    var start = range.start;
    if (start < nextAvailable) start = nextAvailable + 15;

    final shifted =
        start == range.start ? stop : _shiftStop(stop, start, range);
    resolved.add(shifted);
    nextAvailable = start + range.duration;
  }

  return resolved;
}

ItineraryStop _shiftStop(
  ItineraryStop stop,
  int startMinutes,
  _StopTimeRange originalRange,
) {
  final time =
      originalRange.hasEnd
          ? '${_formatMinutes(startMinutes)} - ${_formatMinutes(startMinutes + originalRange.duration)}'
          : _formatMinutes(startMinutes);
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

_StopTimeRange _rangeForStop(ItineraryStop stop) {
  final matches = _clockMatches(stop.time);
  final start =
      matches.isEmpty ? _minutes(stop.time) : _clockMinutes(matches[0]);
  if (matches.length >= 2) {
    var end = _clockMinutes(matches[1], fallbackSuffix: matches[0].suffix);
    if (end <= start) end += 12 * 60;
    return _StopTimeRange(
      start: start,
      duration: (end - start).clamp(20, 6 * 60).toInt(),
      hasEnd: true,
    );
  }

  return _StopTimeRange(
    start: start,
    duration: _durationForStop(stop),
    hasEnd: false,
  );
}

int _durationForStop(ItineraryStop stop) {
  switch (_slotForExistingStop(stop)) {
    case 'breakfast':
      return 45;
    case 'lunch':
      return 75;
    case 'snack':
      return 35;
    case 'dinner':
      return 75;
  }

  final type = stop.type.toLowerCase();
  if (type.contains('travel')) return 45;
  if (type.contains('rest')) return 45;
  return 60;
}

String _formatMinutes(int value) {
  final normalized = value % (24 * 60);
  final hour24 = normalized ~/ 60;
  final minute = normalized % 60;
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
}

List<_ClockMatch> _clockMatches(String value) {
  return RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?', caseSensitive: false)
      .allMatches(value)
      .map(
        (match) => _ClockMatch(
          hour: int.tryParse(match.group(1) ?? '') ?? 0,
          minute: int.tryParse(match.group(2) ?? '') ?? 0,
          suffix: (match.group(3) ?? '').toUpperCase(),
        ),
      )
      .toList();
}

int _clockMinutes(_ClockMatch match, {String? fallbackSuffix}) {
  var hour = match.hour;
  final suffix = match.suffix.isEmpty ? fallbackSuffix ?? '' : match.suffix;
  if (suffix == 'PM' && hour < 12) hour += 12;
  if (suffix == 'AM' && hour == 12) hour = 0;
  return hour * 60 + match.minute;
}

class _StopTimeRange {
  final int start;
  final int duration;
  final bool hasEnd;

  const _StopTimeRange({
    required this.start,
    required this.duration,
    required this.hasEnd,
  });
}

class _ClockMatch {
  final int hour;
  final int minute;
  final String suffix;

  const _ClockMatch({
    required this.hour,
    required this.minute,
    required this.suffix,
  });
}

int _compareStopsByTime(ItineraryStop a, ItineraryStop b) {
  return _minutes(a.time).compareTo(_minutes(b.time));
}

int _minutes(String value) {
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
