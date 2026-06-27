import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:raaste/features/trip/domain/models/saved_trip.dart';

class OpenAiChecklistException implements Exception {
  final String message;
  const OpenAiChecklistException(this.message);

  @override
  String toString() => message;
}

/// Generates rich, trip-specific checklist content via the OpenAI Responses
/// API. The output is a normalized JSON map (see [_checklistSchema]) that the
/// checklist UI renders directly as a checkable list.
///
/// The repository falls back to its built-in static content if this throws,
/// so callers should treat a thrown exception as "use the fallback".
class OpenAiChecklistService {
  final Dio _dio;

  OpenAiChecklistService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.openai.com/v1',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  /// Generates checklist content for [trip] for the given [checklistType]
  /// (`pre_trip`, `in_trip_daily`, or `post_trip`).
  ///
  /// For `in_trip_daily`, [dayNumber] and [dayTitle] describe the current day
  /// so the AI can anchor the list to today's itinerary.
  Future<Map<String, dynamic>> generateChecklist({
    required SavedTrip trip,
    required String checklistType,
    int? dayNumber,
    String? dayTitle,
    int? totalDays,
  }) async {
    final prompt = _buildPrompt(
      trip: trip,
      checklistType: checklistType,
      dayNumber: dayNumber,
      dayTitle: dayTitle,
      totalDays: totalDays,
    );
    return _request(prompt);
  }

  Future<Map<String, dynamic>> _request(String prompt) async {
    final apiKey = dotenv.env['OPENAI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const OpenAiChecklistException(
        'Add OPENAI_API_KEY in .env to generate AI checklists.',
      );
    }

    final model = dotenv.env['OPENAI_MODEL']?.trim();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/responses',
        data: {
          'model': model?.isNotEmpty == true ? model : 'gpt-4.1-mini',
          'input': prompt,
          'text': {
            'format': {
              'type': 'json_schema',
              'name': 'trip_checklist',
              'strict': true,
              'schema': _checklistSchema,
            },
          },
        },
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      final text = _extractOutputText(response.data ?? <String, dynamic>{});
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      return _normalize(decoded);
    } on OpenAiChecklistException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const OpenAiChecklistException(
          'OpenAI rejected the API key. Check OPENAI_API_KEY in .env.',
        );
      }
      throw const OpenAiChecklistException(
        'AI checklist generation is unavailable right now.',
      );
    } on FormatException {
      throw const OpenAiChecklistException(
        'The AI checklist response was not in the expected format.',
      );
    }
  }

  String _extractOutputText(Map<String, dynamic> response) {
    final direct = response['output_text'];
    if (direct is String && direct.trim().isNotEmpty) return direct;

    final output = response['output'] as List<dynamic>? ?? const [];
    for (final item in output) {
      if (item is! Map<String, dynamic>) continue;
      final content = item['content'] as List<dynamic>? ?? const [];
      for (final part in content) {
        if (part is! Map<String, dynamic>) continue;
        final text = part['text'];
        if (text is String && text.trim().isNotEmpty) return text;
      }
    }

    throw const OpenAiChecklistException(
      'The AI checklist response did not include any text.',
    );
  }

  /// Ensures every item carries a `done: false` flag so the UI has a
  /// consistent shape to toggle, and stamps the AI source.
  Map<String, dynamic> _normalize(Map<String, dynamic> decoded) {
    final sections = (decoded['sections'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((section) {
          final items = (section['items'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => {
                  'text': item['text'] ?? '',
                  'detail': item['detail'] ?? '',
                  'priority': item['priority'] ?? '',
                  'action_label': item['action_label'] ?? '',
                  'done': false,
                },
              )
              .toList();
          return {
            'name': section['name'] ?? 'Checklist',
            'emoji': section['emoji'] ?? '📋',
            'context': section['context'] ?? '',
            'items': items,
          };
        })
        .toList();

    return {
      'source': 'ai',
      'title': decoded['title'] ?? '',
      'intro': decoded['intro'] ?? '',
      'sections': sections,
    };
  }

  String _buildPrompt({
    required SavedTrip trip,
    required String checklistType,
    int? dayNumber,
    String? dayTitle,
    int? totalDays,
  }) {
    final intake = trip.guide.intake;
    final destination =
        trip.destinationName.trim().isEmpty
            ? trip.guide.destinationName
            : trip.destinationName;

    final phaseInstruction = switch (checklistType) {
      'pre_trip' =>
        'This is a PRE-TRIP preparation checklist, shown in the days before departure. '
            'Focus on bookings, packing, documents, money, health/medical prep, '
            'offline downloads, dietary research, and destination-specific prep. '
            'Tailor packing and prep to the destination, season implied by the dates, '
            'the travel mode, the traveller count, the stated interests, and the '
            'dietary preference.',
      'in_trip_daily' =>
        'This is a DURING-TRIP daily checklist for Day ${dayNumber ?? 1}'
            '${totalDays != null ? ' of $totalDays' : ''}'
            '${dayTitle != null && dayTitle.trim().isNotEmpty ? ' ("$dayTitle")' : ''}. '
            'Focus on what to do this morning before heading out, the key stops for '
            'today drawn from the saved itinerary, meals matching the dietary '
            'preference, local practical tips, safety, and money/connectivity '
            'reminders. Keep it actionable for the day.',
      _ =>
        'This is a POST-TRIP wrap-up checklist, shown after the trip ends. '
            'Focus on immediate tasks (back up photos, returns/refunds, deposits), '
            'this-week tasks (expense review, sharing memories), and helping future '
            'travellers (reviews, flagging outdated tips).',
    };

    return '''
You are Raaste, a careful, detail-oriented travel assistant for Indian domestic travel.
Generate a highly practical, trip-specific checklist.

$phaseInstruction

Trip details:
${jsonEncode({
          'destination': destination,
          'destination_address': trip.destinationAddress,
          'dates': trip.dates.isNotEmpty ? trip.dates : intake.dates,
          'people_count': trip.peopleCount,
          'travel_mode': intake.travelMode,
          'pace_preference': intake.pacePreference,
          'interests': intake.interests,
          'dietary_preference': intake.dietaryPreference,
          'landing_time': intake.landingTime,
          'departure_time': intake.departureTime,
        })}

${checklistType == 'in_trip_daily' ? 'Today\'s saved itinerary for Day ${dayNumber ?? 1}:\n${jsonEncode(_dayJson(trip, dayNumber))}\n' : ''}
Requirements:
- Produce 4 to 6 sections, each with a short emoji, a clear name, an optional one-line context, and 2 to 6 concrete items.
- Each item has: "text" (the actionable task), "detail" (a short helpful note or how-to, may be empty), "priority" (one of "critical", "high", "medium", "low"), and "action_label" (a short call-to-action like "Download Now" or "Request with Airline" when relevant, otherwise empty).
- Be specific to THIS trip: reference the destination, dietary preference, travel mode, interests, and traveller count where it adds value. Avoid generic filler.
- Do not invent exact live prices, schedules, or guarantees. Remind the user to verify timings and prices.
- Keep item text concise (under ~90 characters). Put extra context in "detail".
- "title" should be a short heading for the whole checklist. "intro" should be one friendly sentence of context.
Return only JSON matching the schema.
''';
  }

  Map<String, dynamic> _dayJson(SavedTrip trip, int? dayNumber) {
    final number = dayNumber ?? 1;
    final matching = trip.guide.itineraryDays.where(
      (day) => day.dayNumber == number,
    );
    if (matching.isEmpty) return const {};
    final day = matching.first;
    return {
      'dayNumber': day.dayNumber,
      'title': day.title,
      'subtitle': day.subtitle,
      'stops': day.stops
          .map(
            (stop) => {
              'time': stop.time,
              'title': stop.title,
              'description': stop.description,
              'type': stop.type,
            },
          )
          .toList(),
    };
  }

  static const Map<String, dynamic> _checklistSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['title', 'intro', 'sections'],
    'properties': {
      'title': {'type': 'string'},
      'intro': {'type': 'string'},
      'sections': {
        'type': 'array',
        'minItems': 4,
        'maxItems': 6,
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['name', 'emoji', 'context', 'items'],
          'properties': {
            'name': {'type': 'string'},
            'emoji': {'type': 'string'},
            'context': {'type': 'string'},
            'items': {
              'type': 'array',
              'minItems': 2,
              'maxItems': 6,
              'items': {
                'type': 'object',
                'additionalProperties': false,
                'required': ['text', 'detail', 'priority', 'action_label'],
                'properties': {
                  'text': {'type': 'string'},
                  'detail': {'type': 'string'},
                  'priority': {
                    'type': 'string',
                    'enum': ['critical', 'high', 'medium', 'low'],
                  },
                  'action_label': {'type': 'string'},
                },
              },
            },
          },
        },
      },
    },
  };
}
