import 'dart:convert';

import 'package:raaste/features/checklist/application/open_ai_checklist_service.dart';
import 'package:raaste/features/checklist/application/research_checklist_content_service.dart';
import 'package:raaste/features/checklist/domain/models/trip_checklist.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
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
  final OpenAiChecklistService? _checklistService;
  final DestinationResearchService? _researchService;
  final ResearchChecklistContentService _researchContentService;

  TripChecklistRepository({
    SupabaseClient? client,
    OpenAiChecklistService? checklistService,
    DestinationResearchService? researchService,
    ResearchChecklistContentService? researchContentService,
  }) : _client = client ?? Supabase.instance.client,
       _checklistService = checklistService,
       _researchService = researchService,
       _researchContentService =
           researchContentService ?? const ResearchChecklistContentService();

  Future<List<TripChecklist>> listChecklists() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    // Generate due checklists first. AI failures fall back to static content,
    // but database/schema failures should be visible instead of looking like
    // there are simply no checklists.
    try {
      await ensureDueChecklists();
    } on TripChecklistException {
      rethrow;
    } on PostgrestException catch (e) {
      throw TripChecklistException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const TripChecklistException(
        'Could not generate your checklist right now.',
      );
    }

    try {
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

  /// Persists the done/undone state of a single checklist item, identified by
  /// its section and item index within the checklist [content].
  ///
  /// Returns the updated content map so the caller can keep local state in sync.
  Future<Map<String, dynamic>> setItemDone({
    required String checklistId,
    required Map<String, dynamic> content,
    required int sectionIndex,
    required int itemIndex,
    required bool done,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const TripChecklistException('Sign in to update your checklist.');
    }

    // Deep-copy and mutate the targeted item's done flag.
    final updated = jsonDecode(jsonEncode(content)) as Map<String, dynamic>;
    final sections = updated['sections'];
    if (sections is List &&
        sectionIndex >= 0 &&
        sectionIndex < sections.length) {
      final section = sections[sectionIndex];
      if (section is Map) {
        final items = section['items'];
        if (items is List && itemIndex >= 0 && itemIndex < items.length) {
          final item = items[itemIndex];
          if (item is Map) {
            item['done'] = done;
          }
        }
      }
    }

    try {
      await _client
          .from('trip_checklists')
          .update({'content': updated})
          .eq('id', checklistId)
          .eq('user_id', user.id);
      return updated;
    } on PostgrestException catch (e) {
      throw TripChecklistException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const TripChecklistException('Could not save your change.');
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
      final raw = _tripDateText(trip);
      final range = _parseTripDateRange(raw, today);
      if (range == null) continue;

      final dueItems = _dueChecklists(range, today);

      // Look up which (type, date) checklists already exist for this trip so we
      // only generate the genuinely-missing ones. This preserves the user's
      // checked-off items and avoids re-spending OpenAI tokens on every refresh.
      final existingKeys = await _existingChecklistKeys(trip.id, user.id);

      for (final due in dueItems) {
        final key = '${due.type}|${_isoDate(due.date)}';
        if (existingKeys.contains(key)) continue;

        // Try AI generation first; fall back to built-in static content.
        final content = await _generateContent(trip, range, due, today);

        await _insertChecklist(
          trip: trip,
          userId: user.id,
          rawDates: raw,
          due: due,
          content: content,
        );
      }

      // Remove checklists that no longer belong to the trip's current phase,
      // e.g. a pre-trip prep list once the trip has started, or an in-trip
      // daily list from a previous day. This also clears rows written with an
      // incorrect date by an earlier version of the date parser.
      try {
        await _pruneStaleChecklists(
          tripId: trip.id,
          userId: user.id,
          dueItems: dueItems,
        );
      } catch (_) {
        // Pruning is best-effort; never block on it.
      }
    }
  }

  /// Refreshes checklist rows for a trip after its itinerary changes.
  ///
  /// This regenerates content through the same OpenAI path used for the very
  /// first checklist (via [_generateContent]) so an edited trip produces a
  /// checklist of the same quality as the original. The user's checked-off
  /// items are preserved by re-applying their done state onto the freshly
  /// generated content. OpenAI failures fall back to research-local content.
  Future<void> refreshTripChecklists(SavedTrip trip) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final raw = _tripDateText(trip);
    final today = _dateOnly(DateTime.now());
    final range = _parseTripDateRange(raw, today);
    if (range == null) return;

    final dueItems = _dueChecklists(range, today);
    if (dueItems.isEmpty) {
      await _pruneStaleChecklists(
        tripId: trip.id,
        userId: user.id,
        dueItems: dueItems,
      );
      return;
    }

    final existing = await _existingChecklistsByKey(trip.id, user.id);

    for (final due in dueItems) {
      final key = _checklistKey(due.type, due.date);
      final existingChecklist = existing[key];

      // Regenerate with the full AI pipeline (same as initial generation),
      // then carry over any items the user already checked off.
      final generated = await _generateContent(trip, range, due, today);
      final content = _applyDoneState(generated, existingChecklist?.content);

      if (existingChecklist == null) {
        await _insertChecklist(
          trip: trip,
          userId: user.id,
          rawDates: raw,
          due: due,
          content: content,
        );
        continue;
      }

      await _updateChecklist(
        checklist: existingChecklist,
        trip: trip,
        userId: user.id,
        rawDates: raw,
        due: due,
        content: content,
      );
    }

    await _pruneStaleChecklists(
      tripId: trip.id,
      userId: user.id,
      dueItems: dueItems,
    );
  }

  Future<void> _insertChecklist({
    required SavedTrip trip,
    required String userId,
    required String rawDates,
    required _DueChecklist due,
    required Map<String, dynamic> content,
  }) async {
    final payload = {
      'trip_id': trip.id,
      'user_id': userId,
      'checklist_type': due.type,
      'checklist_date': _isoDate(due.date),
      'day_number': due.dayNumber,
      'destination_name':
          trip.destinationName.trim().isEmpty
              ? trip.guide.destinationName
              : trip.destinationName,
      'trip_dates': rawDates,
      'content': content,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _client.from('trip_checklists').insert(payload);
    } on PostgrestException catch (e) {
      // If another refresh/device created the row between the existence check
      // and insert, keep going. Any other database issue should be visible.
      if (_isDuplicateChecklistError(e)) return;
      throw TripChecklistException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const TripChecklistException(
        'Could not save the generated checklist. Please try again.',
      );
    }
  }

  Future<void> _updateChecklist({
    required TripChecklist checklist,
    required SavedTrip trip,
    required String userId,
    required String rawDates,
    required _DueChecklist due,
    required Map<String, dynamic> content,
  }) async {
    final payload = {
      'destination_name':
          trip.destinationName.trim().isEmpty
              ? trip.guide.destinationName
              : trip.destinationName,
      'trip_dates': rawDates,
      'day_number': due.dayNumber,
      'content': content,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _client
          .from('trip_checklists')
          .update(payload)
          .eq('id', checklist.id)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw TripChecklistException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const TripChecklistException(
        'Could not refresh your checklist right now.',
      );
    }
  }

  /// Returns the set of 'type|date' keys already stored for this trip.
  Future<Set<String>> _existingChecklistKeys(
    String tripId,
    String userId,
  ) async {
    try {
      final rows = await _client
          .from('trip_checklists')
          .select('checklist_type, checklist_date')
          .eq('trip_id', tripId)
          .eq('user_id', userId);
      return rows.whereType<Map<String, dynamic>>().map((row) {
        final type = row['checklist_type'] as String? ?? '';
        final date = row['checklist_date'] as String? ?? '';
        final normalized =
            DateTime.tryParse(date) == null
                ? date
                : _isoDate(DateTime.parse(date));
        return '$type|$normalized';
      }).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<Map<String, TripChecklist>> _existingChecklistsByKey(
    String tripId,
    String userId,
  ) async {
    try {
      final rows = await _client
          .from('trip_checklists')
          .select()
          .eq('trip_id', tripId)
          .eq('user_id', userId);
      final result = <String, TripChecklist>{};
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final checklist = TripChecklist.fromSupabase(row);
        result[_checklistKey(
              checklist.checklistType,
              checklist.checklistDate,
            )] =
            checklist;
      }
      return result;
    } catch (_) {
      return const <String, TripChecklist>{};
    }
  }

  /// AI-generated checklist content with a static fallback on any failure.
  Future<Map<String, dynamic>> _generateContent(
    SavedTrip trip,
    _TripDateRange range,
    _DueChecklist due,
    DateTime today,
  ) async {
    final research = await _researchService?.loadForIntake(trip.guide.intake);
    final service = _checklistService;
    if (service != null) {
      try {
        final dayNumber = due.dayNumber ?? range.dayNumber(today);
        final matchingDays = trip.guide.itineraryDays.where(
          (item) => item.dayNumber == dayNumber,
        );
        final dayTitle = matchingDays.isEmpty ? null : matchingDays.first.title;
        return await service.generateChecklist(
          trip: trip,
          checklistType: due.type,
          dayNumber: due.type == 'in_trip_daily' ? dayNumber : null,
          dayTitle: due.type == 'in_trip_daily' ? dayTitle : null,
          totalDays: range.totalDays,
          researchContext: research?.toPromptJson(),
        );
      } catch (_) {
        // Fall through to research-local content below.
      }
    }

    if (research != null) {
      return _researchContentService.buildContent(
        trip: trip,
        research: research,
        checklistType: due.type,
        checklistDate: due.date,
        dayNumber: due.dayNumber ?? range.dayNumber(today),
        totalDays: range.totalDays,
      );
    }

    return _fallbackContent(trip, range, due, today);
  }

  /// Deletes any stored checklists for [tripId] that are not part of the
  /// current [dueItems] set. A checklist is identified by its
  /// (checklist_type, checklist_date) pair, matching the table's unique key.
  Future<void> _pruneStaleChecklists({
    required String tripId,
    required String userId,
    required List<_DueChecklist> dueItems,
  }) async {
    final keepKeys =
        dueItems.map((due) => '${due.type}|${_isoDate(due.date)}').toSet();

    final rows = await _client
        .from('trip_checklists')
        .select('id, checklist_type, checklist_date')
        .eq('trip_id', tripId)
        .eq('user_id', userId);

    final staleIds = <String>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final type = row['checklist_type'] as String? ?? '';
      final date = row['checklist_date'] as String? ?? '';
      // Normalise the stored date (Postgres may return 'YYYY-MM-DD' or a full
      // timestamp) before comparing against the due-set keys.
      final normalizedDate =
          DateTime.tryParse(date) == null
              ? date
              : _isoDate(DateTime.parse(date));
      final key = '$type|$normalizedDate';
      if (!keepKeys.contains(key)) {
        final id = row['id'] as String?;
        if (id != null) staleIds.add(id);
      }
    }

    if (staleIds.isEmpty) return;
    await _client.from('trip_checklists').delete().inFilter('id', staleIds);
  }

  bool _isDuplicateChecklistError(PostgrestException e) {
    final message = e.message.toLowerCase();
    return e.code == '23505' ||
        message.contains('duplicate key') ||
        message.contains('already exists');
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

String _checklistKey(String type, DateTime date) => '$type|${_isoDate(date)}';

Map<String, dynamic> _applyDoneState(
  Map<String, dynamic> content,
  Map<String, dynamic>? existingContent,
) {
  if (existingContent == null) return content;

  final doneByText = _doneItemsByText(existingContent);
  if (doneByText.isEmpty) return content;

  final updated = jsonDecode(jsonEncode(content)) as Map<String, dynamic>;
  for (final sectionKey in const ['sections', 'categories']) {
    final sections = updated[sectionKey];
    if (sections is! List) continue;

    for (final section in sections.whereType<Map>()) {
      final items = section['items'];
      if (items is! List) continue;

      for (final item in items.whereType<Map>()) {
        final key = _normalizedChecklistText(item['text']);
        if (key.isEmpty) continue;
        final done = doneByText[key];
        if (done != null) item['done'] = done;
      }
    }
  }
  return updated;
}

Map<String, bool> _doneItemsByText(Map<String, dynamic> content) {
  final result = <String, bool>{};
  for (final sectionKey in const ['sections', 'categories']) {
    final sections = content[sectionKey];
    if (sections is! List) continue;

    for (final section in sections.whereType<Map>()) {
      final items = section['items'];
      if (items is! List) continue;

      for (final item in items.whereType<Map>()) {
        final key = _normalizedChecklistText(item['text']);
        if (key.isNotEmpty && item['done'] == true) result[key] = true;
      }
    }
  }
  return result;
}

String _normalizedChecklistText(Object? value) {
  if (value is! String) return '';
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
          'emoji': '🎟️',
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
          'emoji': '🎒',
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
          'emoji': '📱',
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
          'emoji': 'ℹ️',
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
          'emoji': '🍽️',
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
          'emoji': '💳',
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
    final stops = day?.stops.take(6).toList() ?? const [];
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
          'emoji': '🌅',
          'time_context': 'Do before stepping out',
          'items': [
            {'text': 'Charge phone and power bank', 'type': 'prep'},
            {'text': 'Carry water and small cash', 'type': 'prep'},
          ],
        },
        {
          'name': 'Today\'s Plan',
          'emoji': '📍',
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
          'emoji': '🍽️',
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
          'emoji': '💡',
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
        'emoji': '⚡',
        'items': [
          {'text': 'Back up trip photos', 'priority': 'high'},
          {'text': 'Check refunds and deposits', 'priority': 'medium'},
        ],
      },
      {
        'name': 'This Week',
        'emoji': '📅',
        'items': [
          {'text': 'Review trip expenses', 'priority': 'medium'},
          {'text': 'Save favorite places', 'priority': 'low'},
        ],
      },
      {
        'name': 'Share & Remember',
        'emoji': '📸',
        'items': [
          {'text': 'Organize best memories', 'priority': 'low'},
        ],
      },
      {
        'name': 'Help Future Travellers',
        'emoji': '🙌',
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

String _isoDate(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
