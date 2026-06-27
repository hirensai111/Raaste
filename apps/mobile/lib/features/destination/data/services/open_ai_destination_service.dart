import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/osm_place.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class OpenAiGuideException implements Exception {
  final String message;
  const OpenAiGuideException(this.message);

  @override
  String toString() => message;
}

class OpenAiDestinationService {
  final Dio _dio;

  OpenAiDestinationService({Dio? dio})
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

  Future<DestinationGuide> generateGuide(
    TripIntake intake,
    OsmPlaceBundle places,
  ) async {
    final expectedDays = _expectedDayCount(intake.dates);
    final result = await _requestGuide(
      prompt: _generationPrompt(intake, places, expectedDays: expectedDays),
      fallbackIntake: intake,
      existingId: '',
    );
    final guide = result.copyWith(
      intake: intake,
      destinationName: intake.destination,
    );

    if (!_needsFullTripRetry(guide, expectedDays, intake.dates)) return guide;

    final retry = await _requestGuide(
      prompt: _generationPrompt(
        intake,
        places,
        expectedDays: expectedDays ?? 2,
        forceFullLength: true,
      ),
      fallbackIntake: intake,
      existingId: '',
    );
    return retry.copyWith(intake: intake, destinationName: intake.destination);
  }

  Future<DestinationGuide> generateGuideFromResearch(
    TripIntake intake,
    DestinationResearch research,
  ) async {
    final expectedDays = _expectedDayCount(intake.dates);
    final result = await _requestGuide(
      prompt: _researchPrompt(intake, research, expectedDays: expectedDays),
      fallbackIntake: intake,
      existingId: '',
    );
    final guide = result.copyWith(
      intake: intake,
      destinationName: intake.destination,
    );

    if (!_needsFullTripRetry(guide, expectedDays, intake.dates)) return guide;

    final retry = await _requestGuide(
      prompt: _researchPrompt(
        intake,
        research,
        expectedDays: expectedDays ?? 2,
        forceFullLength: true,
      ),
      fallbackIntake: intake,
      existingId: '',
    );
    return retry.copyWith(intake: intake, destinationName: intake.destination);
  }

  Future<DestinationGuide> reviseGuide({
    required DestinationGuide currentGuide,
    required String editRequest,
  }) async {
    var result = await _requestGuide(
      prompt: _revisionPrompt(currentGuide, editRequest),
      fallbackIntake: currentGuide.intake,
      existingId: currentGuide.id,
    );

    var revised = result.copyWith(
      id: currentGuide.id,
      destinationName:
          result.destinationName.trim().isEmpty
              ? currentGuide.destinationName
              : result.destinationName,
    );

    final expectedDays =
        _expectedDayCount(revised.intake.dates) ??
        _expectedDayCount(editRequest) ??
        _expectedDayCount(currentGuide.intake.dates);
    if (_needsFullTripRetry(revised, expectedDays, revised.intake.dates)) {
      result = await _requestGuide(
        prompt: _revisionPrompt(
          currentGuide,
          editRequest,
          forceFullLength: true,
          fallbackExpectedDays: expectedDays ?? 2,
        ),
        fallbackIntake: revised.intake,
        existingId: currentGuide.id,
      );
      revised = result.copyWith(
        id: currentGuide.id,
        destinationName:
            result.destinationName.trim().isEmpty
                ? currentGuide.destinationName
                : result.destinationName,
      );
    }

    return revised;
  }

  Future<DestinationGuide> _requestGuide({
    required String prompt,
    required TripIntake fallbackIntake,
    required String existingId,
  }) async {
    final apiKey = dotenv.env['OPENAI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const OpenAiGuideException(
        'Add OPENAI_API_KEY in .env to generate AI destination guides.',
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
              'name': 'destination_itinerary',
              'strict': true,
              'schema': _guideSchema,
            },
          },
        },
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      final text = _extractOutputText(response.data ?? <String, dynamic>{});
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final intakeJson = <String, dynamic>{...fallbackIntake.toJson()};
      final decodedIntake = decoded['intake'];
      if (decodedIntake is Map) {
        intakeJson.addAll(Map<String, dynamic>.from(decodedIntake));
      }

      return DestinationGuide.fromJson({
        ...decoded,
        'id': existingId,
        'intake': intakeJson,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } on OpenAiGuideException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const OpenAiGuideException(
          'OpenAI rejected the API key. Check OPENAI_API_KEY in .env.',
        );
      }
      throw const OpenAiGuideException(
        'AI itinerary generation is unavailable right now. Please try again.',
      );
    } on FormatException {
      throw const OpenAiGuideException(
        'The AI response was not in the expected itinerary format. Please try again.',
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

    throw const OpenAiGuideException(
      'The AI response did not include itinerary text. Please try again.',
    );
  }

  String _generationPrompt(
    TripIntake intake,
    OsmPlaceBundle places, {
    int? expectedDays,
    bool forceFullLength = false,
  }) {
    return '''
You are Raaste, a careful local trip-planning assistant for India.
Create a coherent day-by-day itinerary from the user intake and raw OpenStreetMap data.

User intake:
${jsonEncode(intake.toJson())}

Raw nearby places from Overpass/OpenStreetMap:
${jsonEncode(places.toJson())}

Requirements:
- Build itinerary days, not separate attraction or restaurant lists.
${_dayCountInstruction(intake.dates, expectedDays, forceFullLength)}
- Return the intake object exactly as provided in User intake.
- Use OSM attractions for activity stops and OSM food places for meal stops whenever possible.
- Respect the arrival/landing time on Day 1 and departure time on the final day.
- Respect intake.travelMode when planning route pacing, transfers, parking/drop points, station/airport buffers, local transport, and warnings. If the user says car, include drive/parking realities; bus/train, include station and local transfer realities; aeroplane/flight, include airport transfer buffers; other, adapt sensibly.
- Pace days realistically for Indian domestic travellers.
- Follow intake.pacePreference closely. If it says leisure, leave breathing room; if packed, add fuller days; if it names specific days as leisure or packed, reflect that day-by-day.
- Match stops to the user's interests and dietary preference.
- Include morning, lunch, afternoon, and dinner where enough data exists.
- Every stop must have a time, title, type, sourceId if from OSM, optional lat/lon, and a concise useful description.
- Include a short overview with best time to visit and how to get there.
- Mention that prices, timings, availability, and travel conditions may vary and should be verified before travel.
- Do not invent exact live prices, ratings, schedules, or guarantees.
Return only JSON matching the schema.
''';
  }

  String _researchPrompt(
    TripIntake intake,
    DestinationResearch research, {
    int? expectedDays,
    bool forceFullLength = false,
  }) {
    return '''
You are Raaste, a careful local trip-planning assistant for India.
Create a neat, detailed day-by-day itinerary using curated Raaste research as the primary source of truth.

User intake:
${jsonEncode(intake.toJson())}

Curated Raaste research JSON:
${jsonEncode(research.toPromptJson())}

Requirements:
- Build itinerary days, not separate attraction or restaurant lists.
${_dayCountInstruction(intake.dates, expectedDays, forceFullLength)}
- Return the intake object exactly as provided in User intake.
- Use the curated research for ${research.destinationName} before any general knowledge. The fields destination, when_to_visit, how_to_reach, local_transport, attractions, food, accommodation, local_knowledge, safety, packing, and itinerary_framework are all relevant.
- Use itinerary_framework as the backbone, but adapt it to the user's dates, arrival time, departure time, travel mode, interests, people count, pace preference, and dietary preference.
- Respect intake.travelMode when choosing route order, transfer buffers, parking/drop points, station/airport advice, and local movement. Use local_transport and how_to_reach research heavily for this.
- Follow intake.pacePreference closely. If it says leisure, leave breathing room; if packed, add fuller days; if it names specific days as leisure or packed, reflect that day-by-day.
- Choose specific attractions and food experiences from the research whenever possible. Include local tips, crowd realities, closure warnings, transport advice, and verification notes inside stop descriptions when useful.
- For every stop sourced from the research, use sourceId values like research:${research.sourceId}:charminar or research:${research.sourceId}:food:local-specialty. Use coordinates from research when available, otherwise null.
- Make the itinerary feel practical and detailed: morning, lunch, afternoon, evening, and dinner where possible; avoid impossible cross-city hopping.
- Include an overview that reflects the destination tagline, best time to visit, and how to get there from the research.
- Mention that prices, timings, entry fees, availability, and travel conditions may vary and should be verified before travel.
- Do not invent exact live prices, ratings, schedules, closures, or guarantees beyond what the research says.
Return only JSON matching the schema.
''';
  }

  String _revisionPrompt(
    DestinationGuide guide,
    String editRequest, {
    bool forceFullLength = false,
    int? fallbackExpectedDays,
  }) {
    final isFollowUpDateEdit = editRequest.contains('Follow-up answers:');
    final requestedDays =
        isFollowUpDateEdit ? null : _expectedDayCount(editRequest);
    final expectedDays = fallbackExpectedDays ?? requestedDays;
    final dateBasis = requestedDays != null ? editRequest : guide.intake.dates;
    final lengthInstruction =
        forceFullLength || expectedDays != null
            ? _dayCountInstruction(dateBasis, expectedDays, forceFullLength)
            : '- If the edit request changes trip dates or trip length, update intake.dates and infer the full revised trip length. Otherwise keep the existing number of days.';

    return '''
You are Raaste, a careful local trip-planning assistant for India.
Revise this existing destination itinerary according to the user's edit request.

Edit request: $editRequest

Existing itinerary:
${jsonEncode(guide.toJson())}

Requirements:
- Keep the same destination unless the user explicitly asks to change it.
- The intake is editable. If the user asks to change dates, arrival/landing time, departure time, travel mode, traveller count, pace preference, interests, or dietary preference, update the matching intake field in the JSON response.
- Preserve useful stops unless the user asks to change them, but rebuild timing and day structure around any updated intake.
$lengthInstruction
- Respect the revised arrival/landing time on Day 1 and revised departure time on the final day.
- Respect intake.travelMode when revising route order, transfer buffers, parking/drop points, station/airport advice, and local movement.
- Return an intake object with all fields filled: destination, sourceId, displayAddress, lat, lon, dates, landingTime, departureTime, peopleCount, travelMode, pacePreference, interests, and dietaryPreference.
- Maintain the same disclaimer behavior: prices, timings, availability, and travel conditions may vary and should be verified before travel.
Return only JSON matching the schema.
''';
  }

  String _dayCountInstruction(
    String rawDates,
    int? expectedDays,
    bool forceFullLength,
  ) {
    final prefix =
        forceFullLength ? '- The previous itinerary was too short. ' : '- ';
    if (expectedDays != null) {
      return '${prefix}Create exactly $expectedDays itineraryDays, numbered 1 through $expectedDays, because the travel dates are "$rawDates".';
    }
    return '${prefix}Infer the full trip length from "$rawDates". If the dates are unclear, create a complete 2-day itinerary. Do not return only one day unless the user clearly described a one-day or same-day trip.';
  }

  bool _needsFullTripRetry(
    DestinationGuide guide,
    int? expectedDays,
    String rawDates,
  ) {
    final minimumDays = expectedDays ?? (_clearlyOneDay(rawDates) ? 1 : 2);
    return guide.itineraryDays.length < minimumDays;
  }

  int? _expectedDayCount(String rawDates) {
    final text = rawDates.toLowerCase().trim();
    if (text.isEmpty) return null;

    final explicitDays = RegExp(r'\b(\d{1,2})\s*days?\b').firstMatch(text);
    if (explicitDays != null) {
      final days = int.tryParse(explicitDays.group(1) ?? '');
      if (days != null && days >= 1 && days <= 30) return days;
    }

    final explicitNights = RegExp(r'\b(\d{1,2})\s*nights?\b').firstMatch(text);
    if (explicitNights != null) {
      final nights = int.tryParse(explicitNights.group(1) ?? '');
      if (nights != null && nights >= 1 && nights < 30) return nights + 1;
    }

    final range = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?(?:\s+[a-z]+)?\s*(?:-|to|until|till|through)\s*(?:[a-z]+\s+)?(\d{1,2})(?:st|nd|rd|th)?\b',
    ).firstMatch(text);
    if (range != null) {
      final start = int.tryParse(range.group(1) ?? '');
      final end = int.tryParse(range.group(2) ?? '');
      if (start != null && end != null && end >= start) {
        final days = end - start + 1;
        if (days >= 1 && days <= 30) return days;
      }
    }

    if (text.contains('weekend')) return 2;
    if (_clearlyOneDay(text)) return 1;
    return null;
  }

  bool _clearlyOneDay(String rawDates) {
    final text = rawDates.toLowerCase();
    return text.contains('one day') ||
        text.contains('1 day') ||
        text.contains('same day') ||
        text.contains('day trip');
  }

  static const Map<String, dynamic> _guideSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'destinationName',
      'intake',
      'overview',
      'itineraryDays',
      'disclaimers',
    ],
    'properties': {
      'destinationName': {'type': 'string'},
      'intake': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'destination',
          'sourceId',
          'displayAddress',
          'lat',
          'lon',
          'dates',
          'landingTime',
          'departureTime',
          'peopleCount',
          'travelMode',
          'pacePreference',
          'interests',
          'dietaryPreference',
        ],
        'properties': {
          'destination': {'type': 'string'},
          'sourceId': {'type': 'string'},
          'displayAddress': {'type': 'string'},
          'lat': {
            'type': ['number', 'null'],
          },
          'lon': {
            'type': ['number', 'null'],
          },
          'dates': {'type': 'string'},
          'landingTime': {'type': 'string'},
          'departureTime': {'type': 'string'},
          'peopleCount': {'type': 'integer'},
          'travelMode': {'type': 'string'},
          'pacePreference': {'type': 'string'},
          'interests': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'dietaryPreference': {'type': 'string'},
        },
      },
      'overview': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['summary', 'bestTimeToVisit', 'howToGetThere'],
        'properties': {
          'summary': {'type': 'string'},
          'bestTimeToVisit': {'type': 'string'},
          'howToGetThere': {'type': 'string'},
        },
      },
      'itineraryDays': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 14,
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['dayNumber', 'title', 'subtitle', 'stops'],
          'properties': {
            'dayNumber': {'type': 'integer'},
            'title': {'type': 'string'},
            'subtitle': {'type': 'string'},
            'stops': {
              'type': 'array',
              'minItems': 2,
              'maxItems': 7,
              'items': {
                'type': 'object',
                'additionalProperties': false,
                'required': [
                  'time',
                  'title',
                  'description',
                  'type',
                  'sourceId',
                  'lat',
                  'lon',
                ],
                'properties': {
                  'time': {'type': 'string'},
                  'title': {'type': 'string'},
                  'description': {'type': 'string'},
                  'type': {'type': 'string'},
                  'sourceId': {'type': 'string'},
                  'lat': {
                    'type': ['number', 'null'],
                  },
                  'lon': {
                    'type': ['number', 'null'],
                  },
                },
              },
            },
          },
        },
      },
      'disclaimers': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 4,
        'items': {'type': 'string'},
      },
    },
  };
}
