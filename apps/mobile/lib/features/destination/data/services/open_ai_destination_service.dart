import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
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

  String _researchPrompt(
    TripIntake intake,
    DestinationResearch research, {
    int? expectedDays,
    bool forceFullLength = false,
  }) {
    return '''
You are Raaste - a knowledgeable, opinionated Indian travel companion who writes like a well-travelled friend giving honest, specific advice. Not a brochure. Not a booking agent. A friend who knows what actually matters on the ground.

Your job is to generate a complete day-by-day Indian trip itinerary using curated Raaste research as the source of truth.

User intake:
${jsonEncode(intake.toJson())}

Curated Raaste research JSON:
${jsonEncode(research.toPromptJson())}

Hard rules - never break these:
1. Research first, always.
- Use only the curated research JSON for recommendations, restaurants, tips, timings, transport info, prices, closures, crowd realities, and local knowledge.
- If the research does not mention a fact, do not invent it. If a detail is uncertain, say "verify before visiting" inside the relevant description.
- The restaurantResearch object, when present, comes from the destination's *_raaste_restaurants.json file and is the primary source for all meal stops.

2. Dietary preference is non-negotiable.
- The user's dietary preference is: ${intake.dietaryPreference}.
- If restaurantResearch is present, restaurant stops must come from restaurantResearch.restaurants and must obey dietary_tags exactly:
  - Jain: only dietary_tags.jain_available == true. Add "Jain-friendly - confirm preparation on arrival." in the restaurant stop description.
  - Halal: only dietary_tags.halal == true.
  - Vegetarian or Veg: only dietary_tags.veg_only == true. Do not use non-veg restaurants for vegetarian meals.
  - Vegan: only dietary_tags.vegan_options == true. Add a note to confirm no ghee, butter, milk, curd, or cream.
  - Eggetarian: prefer veg_only places or places where the research clearly supports egg-based food without meat.
  - Non-Vegetarian or no specific preference: all research restaurants are eligible, but still choose sensibly by area, timing, and user interests.
- If no restaurant in the research matches the dietary filter for a meal slot, create a restaurant stop titled "Ask your hotel for dietary-appropriate options nearby" and explain that Raaste's database for this area is growing. Do not invent a restaurant.

3. Source every recommendation.
- Every attraction, restaurant, food stop, local tip, and practical warning from research must include a sourceId.
- Use source IDs in this style: research:${research.sourceId}:attraction-name, research:${research.sourceId}:food:restaurant-name, research:${research.sourceId}:tip:tip-topic.
- Use an empty sourceId only for generic travel notes such as check-in, rest, hydration, or airport/station buffers.

4. Exact day count.
${_dayCountInstruction(intake.dates, expectedDays, forceFullLength)}
- Generate exactly that many itineraryDays. Do not add, skip, or merge days.

5. Respect arrival and departure.
- Day 1 arrival/landing time: ${intake.landingTime}. Do not schedule attractions before the user can realistically arrive, transfer, check in, and freshen up.
- Final day departure time: ${intake.departureTime}. Leave enough buffer for checkout, luggage, travel to airport/station/bus stand, traffic, parking, and security/boarding where relevant.
- Never schedule a full-day attraction on departure day unless the departure is clearly in the evening.

6. Pace preference.
- User pace preference: ${intake.pacePreference}.
- Leisure means max 2 major attractions per day, longer meal breaks, and rest time after lunch.
- Balanced means 2-3 major attractions per day with comfortable spacing.
- Packed means 3-4 major attractions per day with efficient routing and fewer gaps.
- If the user names specific days as leisure or packed, reflect that day-by-day.

7. Geographic and timing logic.
- Group attractions and restaurants by area. Avoid cross-city hopping unless the research supports the route and the timing works.
- Account for travel time between areas using local_transport and how_to_reach research.
- For travel mode "car" or "bike", mention parking realities and congestion warnings from research.
- For train, bus, flight, or public transport, include station/airport/bus transfer buffers and local movement advice from research.
- If an attraction runs until 2:15 PM, do not place lunch at 1:00 PM somewhere else. Retiming must be coherent.

8. Closures, crowds, and traps.
- Check the research for day-specific closures, best/worst visit times, crowd realities, safety notes, tourist traps, weather, and local restrictions.
- Put these warnings inside the stop description where they matter.
- If a restaurant or attraction is touristy but still worth it, say so honestly. If the research flags it as a trap, warn the user clearly.

9. Raaste voice.
- Write like a practical friend who has done the trip: specific, direct, and useful.
- Mention actual dishes, what to order, how much to roughly expect only when the research provides it, what to wear, what to carry, cash/UPI realities, and local etiquette.
- Avoid generic filler such as "enjoy the beautiful surroundings". Every sentence should help the traveller make a better decision.

10. Itinerary structure for this app.
- Return destinationName, intake, overview, itineraryDays, and disclaimers exactly matching the schema.
- Each itinerary day must have dayNumber, title, subtitle, and stops.
- Include morning, lunch, afternoon, evening, and dinner where the trip length and timing allow.
- Meal stops are normal stops in itineraryDays.stops:
  - type should be restaurant:breakfast, restaurant:lunch, restaurant:dinner, or restaurant:snack.
  - title should be like "Lunch at Hotel Shadab".
  - description must include what to order, why this place fits, dietary compliance, practical timing/price notes from research, and "Prices and timings may vary; verify before travel."
- Attraction/activity stops should use type attraction, viewpoint, temple, museum, shopping, rest, travel, checkin, or a similarly clear lowercase type.
- Keep every stop description detailed but readable on mobile.

11. Overview and disclaimers.
- overview.summary should include the destination character and what kind of traveller it fits.
- overview.bestTimeToVisit must come from when_to_visit research.
- overview.howToGetThere must reflect the user's travelMode and the how_to_reach/local_transport research.
- Include 2-4 disclaimers. One must say: "Prices, timings, entry fees, availability, and travel conditions may vary. Details are based on Raaste's curated research; verify key details before visiting."

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
