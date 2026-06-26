import 'package:raaste/features/checklist/domain/models/trip_checklist.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripChecklistException implements Exception {
  final String message;

  const TripChecklistException(this.message);

  @override
  String toString() => message;
}

class TripChecklistRepository {
  final SupabaseClient _client;

  TripChecklistRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<TripChecklist>> listChecklists() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    try {
      await ensureDueChecklists();
      final rows = await _client
          .from('trip_checklists')
          .select()
          .eq('user_id', user.id)
          .order('checklist_date', ascending: false)
          .order('generated_at', ascending: false);
      return rows
          .whereType<Map<String, dynamic>>()
          .map(TripChecklist.fromSupabase)
          .toList();
    } on PostgrestException catch (e) {
      throw TripChecklistException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const TripChecklistException(
        'Could not load your checklists right now.',
      );
    }
  }

  Future<void> ensureDueChecklists() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final tripRows = await _client
        .from('saved_trips')
        .select()
        .eq('user_id', user.id);
    final trips =
        tripRows
            .whereType<Map<String, dynamic>>()
            .map(SavedTrip.fromSupabase)
            .toList();
    final today = _dateOnly(DateTime.now());

    for (final trip in trips) {
      final range = _parseTripDateRange(_tripDateText(trip), today);
      if (range == null) continue;

      final dueItems = _dueChecklists(range, today);
      for (final due in dueItems) {
        await _client.from('trip_checklists').upsert({
          'trip_id': trip.id,
          'user_id': user.id,
          'checklist_type': due.type,
          'checklist_date': _isoDate(due.date),
          'day_number': due.dayNumber,
          'destination_name': trip.destinationName,
          'trip_dates': _tripDateText(trip),
          'content': _fallbackContent(trip, range, due, today),
          'generated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'trip_id,checklist_type,checklist_date');
      }
    }
  }

  String _friendlyDatabaseMessage(PostgrestException e) {
    if (e.code == '42P01' || e.code == 'PGRST205') {
      return 'The trip_checklists table has not been created yet. Run the checklist SQL migration in Supabase first.';
    }
    return e.message.isNotEmpty
        ? e.message
        : 'Checklist database request failed.';
  }
}

class _TripDateRange {
  final DateTime start;
  final DateTime end;

  const _TripDateRange({required this.start, required this.end});

  int get totalDays => end.difference(start).inDays + 1;

  int dayNumber(DateTime value) {
    final rawDay = _dateOnly(value).difference(start).inDays + 1;
    return rawDay.clamp(1, totalDays).toInt();
  }
}

class _DueChecklist {
  final String type;
  final DateTime date;
  final int? dayNumber;

  const _DueChecklist({required this.type, required this.date, this.dayNumber});
}

List<_DueChecklist> _dueChecklists(_TripDateRange range, DateTime today) {
  final due = <_DueChecklist>[];
  final preTripDate = range.start.subtract(const Duration(days: 14));
  final postTripDate = range.end.add(const Duration(days: 1));

  if (!today.isBefore(preTripDate) && today.isBefore(range.start)) {
    due.add(_DueChecklist(type: 'pre_trip', date: preTripDate));
  }

  if (!today.isBefore(range.start) && !today.isAfter(range.end)) {
    due.add(
      _DueChecklist(
        type: 'in_trip_daily',
        date: today,
        dayNumber: range.dayNumber(today),
      ),
    );
  }

  if (!today.isBefore(postTripDate)) {
    due.add(_DueChecklist(type: 'post_trip', date: postTripDate));
  }

  return due;
}

String _tripDateText(SavedTrip trip) {
  final savedDates = trip.dates.trim();
  if (savedDates.isNotEmpty) return savedDates;
  return trip.guide.intake.dates.trim();
}

Map<String, dynamic> _fallbackContent(
  SavedTrip trip,
  _TripDateRange range,
  _DueChecklist due,
  DateTime today,
) {
  final destination =
      trip.destinationName.trim().isEmpty
          ? trip.guide.destinationName
          : trip.destinationName;
  final intake = trip.guide.intake;
  final travelMode =
      intake.travelMode.trim().isEmpty
          ? 'your chosen transport'
          : intake.travelMode;
  final interests =
      intake.interests.isEmpty
          ? 'your saved interests'
          : intake.interests.take(3).join(', ');

  if (due.type == 'pre_trip') {
    return {
      'categories': [
        {
          'name': 'Book & Reserve',
          'emoji': 'ticket',
          'items': [
            {
              'text': 'Confirm stay booking',
              'priority': 'high',
              'days_before': 14,
            },
            {
              'text': 'Verify ${travelMode.toLowerCase()} arrival details',
              'priority': 'high',
              'days_before': 7,
            },
            {
              'text': 'Check attraction timings',
              'priority': 'medium',
              'days_before': 3,
            },
          ],
        },
        {
          'name': 'Pack',
          'emoji': 'bag',
          'items': [
            {
              'text': 'Pack comfortable walking shoes',
              'priority': 'high',
              'days_before': 3,
            },
            {
              'text': 'Carry weather-ready layers',
              'priority': 'medium',
              'days_before': 3,
            },
            {
              'text': 'Keep medicines and ID ready',
              'priority': 'high',
              'days_before': 2,
            },
          ],
        },
        {
          'name': 'Download & Save',
          'emoji': 'phone',
          'items': [
            {'text': 'Save offline map', 'priority': 'high', 'days_before': 7},
            {
              'text': 'Save hotel and transport contacts',
              'priority': 'high',
              'days_before': 2,
            },
          ],
        },
        {
          'name': 'Know Before You Go',
          'emoji': 'info',
          'items': [
            {
              'text': 'Verify prices before travel',
              'priority': 'medium',
              'days_before': null,
            },
            {
              'text': 'Plan around $interests',
              'priority': 'medium',
              'days_before': null,
            },
          ],
        },
        {
          'name': 'Food & Dietary',
          'emoji': 'food',
          'items': [
            {
              'text': 'Shortlist ${intake.dietaryPreference} food options',
              'priority': 'medium',
              'days_before': 7,
            },
          ],
        },
        {
          'name': 'Money & Documents',
          'emoji': 'card',
          'items': [
            {
              'text': 'Carry ID and small cash',
              'priority': 'high',
              'days_before': 2,
            },
            {
              'text': 'Keep booking screenshots offline',
              'priority': 'high',
              'days_before': 2,
            },
          ],
        },
      ],
      'generated_for': destination,
      'season_note':
          'Prices, timings, and travel conditions may vary; verify before travel.',
    };
  }

  if (due.type == 'in_trip_daily') {
    final dayNumber = due.dayNumber ?? range.dayNumber(today);
    final matchingDays = trip.guide.itineraryDays.where(
      (item) => item.dayNumber == dayNumber,
    );
    final day = matchingDays.isEmpty ? null : matchingDays.first;
    final stops = day?.stops.take(5).toList() ?? const [];
    return {
      'day_number': dayNumber,
      'date': _isoDate(today),
      'morning_greeting':
          'Good morning, Day $dayNumber in $destination is ready.',
      'weather_heads_up':
          'Verify today\'s weather and local timings before leaving.',
      'sections': [
        {
          'name': 'Before You Leave',
          'emoji': 'sunrise',
          'time_context': 'Do before stepping out',
          'items': [
            {'text': 'Charge phone and power bank', 'type': 'prep'},
            {'text': 'Carry water and small cash', 'type': 'prep'},
          ],
        },
        {
          'name': 'Today\'s Plan',
          'emoji': 'pin',
          'time_context': day?.title ?? 'Your saved itinerary',
          'items':
              stops
                  .map(
                    (stop) => {
                      'text': stop.title,
                      'type': stop.type,
                      'time': stop.time,
                      'tip': stop.description,
                    },
                  )
                  .toList(),
        },
        {
          'name': 'Eat & Drink',
          'emoji': 'food',
          'time_context': 'Keep meals flexible',
          'items': [
            {
              'text': 'Choose meals matching ${intake.dietaryPreference}',
              'type': 'meal',
              'time': 'Lunch',
            },
          ],
        },
        {
          'name': 'Good to Know Today',
          'emoji': 'idea',
          'time_context': 'Practical reminders',
          'items': [
            {'text': 'Verify entry timings locally', 'type': 'tip'},
            {
              'text': 'Keep ${travelMode.toLowerCase()} buffer time',
              'type': 'tip',
            },
          ],
        },
      ],
      'end_of_day_note': 'Check tomorrow\'s route and keep the plan flexible.',
    };
  }

  return {
    'wrap_up_message': 'Hope $destination was amazing; here is your wrap-up.',
    'sections': [
      {
        'name': 'Do Today',
        'emoji': 'bolt',
        'items': [
          {'text': 'Back up trip photos', 'priority': 'high'},
          {'text': 'Check refunds and deposits', 'priority': 'medium'},
        ],
      },
      {
        'name': 'This Week',
        'emoji': 'calendar',
        'items': [
          {'text': 'Review trip expenses', 'priority': 'medium'},
          {'text': 'Save favorite places', 'priority': 'low'},
        ],
      },
      {
        'name': 'Share & Remember',
        'emoji': 'camera',
        'items': [
          {'text': 'Organize best memories', 'priority': 'low'},
        ],
      },
      {
        'name': 'Help Future Travellers',
        'emoji': 'help',
        'items': [
          {'text': 'Flag outdated Raaste tips', 'priority': 'low'},
        ],
      },
    ],
  };
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
      .replaceAll(RegExp(r'(\d)(st|nd|rd|th)([a-z])'), r'$1$2 $3')
      .replaceAll(RegExp(r'(\d)([a-z])'), r'$1 $2')
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

String _isoDate(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
