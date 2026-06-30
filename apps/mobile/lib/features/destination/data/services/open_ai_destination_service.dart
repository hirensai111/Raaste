import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:raaste/features/destination/data/services/itinerary_curation_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/itinerary_timing_context.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class OpenAiGuideException implements Exception {
  final String message;
  const OpenAiGuideException(this.message);

  @override
  String toString() => message;
}

class TripAlternativeSuggestion {
  final String title;
  final String reason;
  final String editRequest;

  const TripAlternativeSuggestion({
    required this.title,
    required this.reason,
    required this.editRequest,
  });

  bool get isValid => title.trim().isNotEmpty && editRequest.trim().isNotEmpty;

  factory TripAlternativeSuggestion.fromJson(Map<String, dynamic> json) {
    return TripAlternativeSuggestion(
      title: json['title'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      editRequest: json['editRequest'] as String? ?? '',
    );
  }
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
    DestinationResearch research, {
    required ItineraryTimingContext timingContext,
  }) async {
    final expectedDays = _expectedDayCount(intake.dates);
    final result = await _requestGuide(
      prompt: _researchPrompt(
        intake,
        research,
        timingContext: timingContext,
        expectedDays: expectedDays,
      ),
      fallbackIntake: intake,
      existingId: '',
    );
    final guide = _curateGeneratedGuide(
      result.copyWith(
        intake: intake,
        destinationName: intake.destination,
        timingContext: timingContext,
      ),
      research,
    );

    if (!_needsFullTripRetry(guide, expectedDays, intake.dates)) return guide;

    final retry = await _requestGuide(
      prompt: _researchPrompt(
        intake,
        research,
        timingContext: timingContext,
        expectedDays: expectedDays ?? 2,
        forceFullLength: true,
      ),
      fallbackIntake: intake,
      existingId: '',
    );
    return _curateGeneratedGuide(
      retry.copyWith(
        intake: intake,
        destinationName: intake.destination,
        timingContext: timingContext,
      ),
      research,
    );
  }

  DestinationGuide _curateGeneratedGuide(
    DestinationGuide guide,
    DestinationResearch research,
  ) {
    return const ItineraryCurationService().curateGeneratedGuide(
      guide: guide,
      research: research,
    );
  }

  Future<DestinationGuide> reviseGuide({
    required DestinationGuide currentGuide,
    required String editRequest,
    required ItineraryTimingContext timingContext,
    DestinationResearch? research,
  }) async {
    var result = await _requestGuide(
      prompt: _revisionPrompt(
        currentGuide,
        editRequest,
        timingContext: timingContext,
        research: research,
      ),
      fallbackIntake: currentGuide.intake,
      existingId: currentGuide.id,
    );

    var revised = result.copyWith(
      id: currentGuide.id,
      timingContext: timingContext,
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
          timingContext: timingContext,
          research: research,
          forceFullLength: true,
          fallbackExpectedDays: expectedDays ?? 2,
        ),
        fallbackIntake: revised.intake,
        existingId: currentGuide.id,
      );
      revised = result.copyWith(
        id: currentGuide.id,
        timingContext: timingContext,
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
    required ItineraryTimingContext timingContext,
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

Computed Google route timing context:
${jsonEncode(timingContext.toJson())}

Research usage guide:
${_researchUsageGuide(research, intake)}

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
- Prefer a real dietary-compliant restaurant from restaurantResearch even if it requires retiming or moving the meal to a nearby/next area.
- Do not create restaurant stops titled "Ask your hotel..." or similar placeholders.
- Only if there is no dietary-compliant restaurant anywhere in restaurantResearch, create a generic non-restaurant stop titled "Meal break near your stay" with type "rest" and explain that the user should choose a verified dietary-safe option nearby. Do not pretend it is a restaurant.

3. Source every recommendation, but never show source IDs to users.
- Every attraction, restaurant, food stop, local tip, and practical warning from research must include a sourceId field.
- Use source IDs in this style: research:${research.sourceId}:attraction-name, research:${research.sourceId}:food:restaurant-name, research:${research.sourceId}:tip:tip-topic.
- Use an empty sourceId only for generic travel notes such as check-in, rest, hydration, meal breaks, or airport/station buffers.
- Do not write "sourceId", "Source IDs", "research:...", JSON keys, or raw source references inside destinationName, overview, day title, subtitle, stop title, stop description, or disclaimers. The sourceId property is the only place source IDs belong.

4. Exact day count.
${_dayCountInstruction(intake.dates, expectedDays, forceFullLength)}
- Generate exactly that many itineraryDays. Do not add, skip, or merge days.

5. Respect arrival, stay, and departure.
- Day 1 arrival/landing time: ${intake.landingTime}. Stay/hotel/base: ${intake.stayNameOrAddress}. Do not schedule attractions before the user can realistically arrive, transfer to the stay, check in, freshen up, and then travel to the first stop.
- Final day departure time: ${intake.departureTime}. Leave enough buffer for checkout, luggage, travel from stay to airport/station/bus stand, traffic, parking, and security/boarding where relevant.
- Never schedule a full-day attraction on departure day unless the departure is clearly in the evening.

6. Pace preference.
- User pace preference: ${intake.pacePreference}.
- Leisure means max 2 major attractions per day, longer meal breaks, and rest time after lunch.
- Balanced means 2-3 major attractions per day with comfortable spacing.
- Packed means 3-4 major attractions per day with efficient routing and fewer gaps.
- If the user names specific days as leisure or packed, reflect that day-by-day.

Interest fit is a hard constraint.
- User selected interests: ${intake.interests.join(', ')}.
- Do not use the destination's default famous-monument circuit unless it matches these interests.
- Pick attractions, areas, restaurants, shopping stops, evening zones, and rest breaks that directly serve the selected interests.
- If the user selected Shopping, Nightlife, Food, City, Urban, Cafes, or Local Life, prioritize bazaars, markets, cafes, restaurants, promenades, modern districts, evening streets, and nightlife-safe areas. Use monuments only as anchors or backdrops when they support those interests.
- If History or Spiritual is not selected, keep museum/temple/fort-heavy planning optional and limited.

7. Google route timing is a hard constraint.
- Use the computed Google route timing context above as minimum movement time between stay, arrival/departure hubs, attractions, and restaurants.
- You may add extra buffer for crowds, luggage, check-in, weather, traffic uncertainty, parking, walking, tickets, and security, but you must not schedule less movement time than Google returned.
- For flight/aeroplane travel, explicitly account for airport-to-stay and stay-to-airport road transfers plus airport security/boarding buffer.
- If the user arrives by train or bus, explicitly account for station/bus-stand to stay and final stay-to-station/bus-stand transfer.
- If a route entry says stay to a place takes 45 minutes, the first stop cannot begin 10 minutes after hotel departure.

8. Geographic and timing logic.
- Group attractions and restaurants by area. Avoid cross-city hopping unless the research supports the route and the timing works.
- Account for travel time between areas using local_transport, how_to_reach research, and the Google route timing context.
- For travel mode "car" or "bike", mention parking realities and congestion warnings from research.
- For train, bus, flight, or public transport, include station/airport/bus transfer buffers and local movement advice from research.
- If an attraction runs until 2:15 PM, do not place lunch at 1:00 PM somewhere else. Retiming must be coherent.

9. Closures, crowds, and traps.
- Check the research for day-specific closures, best/worst visit times, crowd realities, safety notes, tourist traps, weather, and local restrictions.
- Put these warnings inside the stop description where they matter.
- If a restaurant or attraction is touristy but still worth it, say so honestly. If the research flags it as a trap, warn the user clearly.

10. Raaste voice.
- Write like a practical friend who has done the trip: specific, direct, and useful.
- Mention actual dishes, what to order, how much to roughly expect only when the research provides it, what to wear, what to carry, cash/UPI realities, and local etiquette.
- Avoid generic filler such as "enjoy the beautiful surroundings". Every sentence should help the traveller make a better decision.

11. Itinerary structure for this app.
- Return destinationName, intake, overview, itineraryDays, and disclaimers exactly matching the schema.
- Each itinerary day must have dayNumber, title, subtitle, and stops.
- Include morning, lunch, afternoon, evening, and dinner where the trip length and timing allow.
- Meal stops are normal stops in itineraryDays.stops:
  - type should be restaurant:breakfast, restaurant:lunch, restaurant:dinner, or restaurant:snack.
  - title should be like "Lunch at Hotel Shadab".
  - description must include what to order, why this place fits, dietary compliance, practical timing/price notes from research, and "Prices and timings may vary; verify before travel."
- Attraction/activity stops should use type attraction, viewpoint, temple, museum, shopping, rest, travel, checkin, or a similarly clear lowercase type.
- Do not repeat the same specific attraction, restaurant, or food stop across multiple days unless it is the stay/base, arrival hub, departure hub, or a required transfer.
- If a place was already used earlier, choose a different curated place or make the later stop a rest/transfer note instead.
- Keep every stop description detailed but readable on mobile.

12. Overview and disclaimers.
- overview.summary should include the destination character and what kind of traveller it fits.
- overview.bestTimeToVisit must come from when_to_visit research.
- overview.howToGetThere must reflect the user's travelMode and the how_to_reach/local_transport research.
- Include 2-4 disclaimers. One must say: "Prices, timings, entry fees, availability, and travel conditions may vary. Details are based on Raaste's curated research; verify key details before visiting."

Return only JSON matching the schema.
''';
  }

  String _interestUsageGuide(TripIntake intake) {
    final interests =
        intake.interests
            .map((interest) => interest.trim())
            .where((interest) => interest.isNotEmpty)
            .toList();
    if (interests.isEmpty) {
      return '- No interests were selected, so create a balanced first-timer plan without overloading famous monuments.';
    }

    final normalized = interests.join(' ').toLowerCase();
    final lines = <String>[
      '- User selected interests: ${interests.join(', ')}. Treat these as the primary trip brief, not decoration.',
      '- At least two thirds of non-transfer stops should clearly match one or more selected interests.',
      '- If a famous attraction does not match the selected interests, skip it or make it optional instead of forcing it into the main day.',
    ];

    final wantsShopping =
        normalized.contains('shopping') ||
        normalized.contains('market') ||
        normalized.contains('bazaar');
    final wantsNightlife =
        normalized.contains('nightlife') ||
        normalized.contains('night') ||
        normalized.contains('bar') ||
        normalized.contains('club');
    final wantsCity =
        normalized.contains('city') ||
        normalized.contains('urban') ||
        normalized.contains('local life') ||
        normalized.contains('local');
    final wantsHistory =
        normalized.contains('history') ||
        normalized.contains('heritage') ||
        normalized.contains('museum') ||
        normalized.contains('monument');
    final wantsSpiritual =
        normalized.contains('spiritual') ||
        normalized.contains('temple') ||
        normalized.contains('mosque');

    if (wantsShopping) {
      lines.add(
        '- Shopping interest: prioritize markets, bazaars, crafts, malls, local shopping streets, bargaining tips, best shopping hours, and what to buy. Do not replace shopping time with museum time.',
      );
    }
    if (wantsNightlife) {
      lines.add(
        '- Nightlife interest: include safe evening districts, late cafes/food streets, lake promenade or city-light stops, and realistic return-to-stay advice. Avoid isolated late-night monuments.',
      );
    }
    if (wantsCity) {
      lines.add(
        '- City/urban interest: prioritize neighbourhood energy, cafes, promenades, markets, modern districts, metro/cab practicality, and local-life observations over passive sightseeing.',
      );
    }
    if ((wantsShopping || wantsNightlife || wantsCity) &&
        !wantsHistory &&
        !wantsSpiritual) {
      lines.add(
        '- Because History/Spiritual were not selected, do not build a monument-heavy route. Use monuments only as short anchors/backdrops for markets, food lanes, views, or city atmosphere.',
      );
    }

    return lines.join('\n');
  }

  String _researchUsageGuide(DestinationResearch research, TripIntake intake) {
    final sourceId = research.sourceId.trim().toLowerCase();
    final interestGuide = _interestUsageGuide(intake);
    final base = '''
Read the research like a planner, not like a search result list:
- Start with research.itinerary_framework as the destination's recommended skeleton, then adapt it to the user's dates, arrival/departure times, stay area, pace, travel mode, interests, dietary preference, and Google route timing.
$interestGuide
- Build every day around area clusters. Do not mix far-apart clusters just because both places are famous.
- Use research.attractions as the canonical attraction list. For each selected attraction, use its why_worth_it, best_time_to_visit, avoid_when, time_needed, crowd_reality, local_tip, accessibility, entry_fee, and coordinates where present.
- Use research.when_to_visit.monthly_breakdown and festival_calendar to add seasonal warnings when relevant. If exact travel month is unclear, keep seasonal advice general.
- Use research.local_transport, money, safety, packing, accommodation, and local_knowledge for practical details inside the stops, not as separate generic essays.
- Use restaurantResearch.food_overview, street_food_guide, dietary_specific_guides, meal_planning_guide, budget_meal_planning, and restaurants together. RestaurantResearch.restaurants chooses the actual place; the guides explain when/why/how to eat there.
- For every mapped stop, preserve lat/lon from attraction coordinates when available so the app can show map pins. If a restaurant has no coordinates, leave lat/lon null rather than inventing them.
- If research.data_quality.fields_needing_verification names a fee, timing, fare, contact number, or operational detail, include a verify-before-travel note exactly where that detail appears.
''';

    if (sourceId != 'hyderabad') return base;

    return '''
$base
Hyderabad-specific planning rules from the new Raaste research:
- Treat Hyderabad as multiple cities in one: Old City heritage/food, Golconda-Qutb Shahi heritage, Tank Bund/Birla/Hussain Sagar evening zone, HITEC City/Jubilee/Banjara modern food and nightlife, and Ramoji/outer day trips. Keep days clustered around one or two nearby zones.
- Old City cluster: Charminar, Laad Bazaar, Mecca Masjid, Chowmahalla Palace, Salar Jung Museum, Nimrah Cafe, Hotel Shadab, Madina/Moazzam Jahi/nearby food lanes. Schedule it early morning or evening; warn about crowds, modest dress, cash, bargaining, Friday/prayer/festival pressure, and very limited parking.
- Golconda cluster: Golconda Fort plus Qutb Shahi Tombs. Respect steep steps, heat, water/shoes, light-show Monday closure, and the tombs' possible Friday verification note. Do not combine this with a rushed Old City lunch unless route timing makes it realistic.
- Tank Bund/Birla cluster: Birla Mandir, Hussain Sagar, Necklace Road, Lumbini Park/NTR Gardens. This works best as sunset/evening pacing after a lighter afternoon.
- Modern-west cluster: Shilparamam, Durgam Cheruvu, KBR National Park, Jubilee Hills/Banjara Hills/HITEC food. Use this for shopping, cafes, nightlife, city walks, and lower-chaos days.
- Ramoji Film City is a full-day or near-full-day choice. Do not squeeze it between central-city attractions.
- Use Hyderabad food research with strong opinions: choose by area and meal slot, prefer Old City food while already in Old City, use HITEC/Jubilee options when the day is west-side, and avoid sending users across town only for a meal unless it is the whole point of that day.
- For Shopping + Nightlife + City interests, build around Laad Bazaar/Moazzam Jahi/Abids or Shilparamam during shopping hours, then Jubilee Hills/Banjara Hills/HITEC/Durgam Cheruvu/Necklace Road style evening zones. Do not make the day a Salar Jung/Golconda/temple/museum plan unless the user also selected History/Spiritual.
- When Charminar appears for a shopping/nightlife/city plan, frame it as the gateway to Laad Bazaar, Old City street energy, lights, chai, and food lanes, not as a monument-climb history stop.
- For biryani and iconic food, include what to order, best time for freshest batch, wait-time reality, quality/tourist-trap warnings, parking/seating/cash-UPI notes, and dietary compliance from restaurantResearch. Never suggest a generic lunch if a compliant curated restaurant exists.
- Hyderabad heat and monsoon matter. In April-May, push outdoor walking to early morning/evening and use museums/restaurants/indoor breaks in the afternoon. In monsoon, add rain, traffic, and footwear cautions.
- The voice should feel local and current: mention practical realities like Old City chaos, airport distance from the hotel, HITEC-to-Old-City distance, metro usefulness/limits, autos/cab negotiation, and the difference between legendary original outlets and weaker branches when research says so.
''';
  }

  String _revisionPrompt(
    DestinationGuide guide,
    String editRequest, {
    required ItineraryTimingContext timingContext,
    DestinationResearch? research,
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
    final researchBlock =
        research == null
            ? ''
            : '''

Curated Raaste research JSON:
${jsonEncode(research.toPromptJson())}

Research usage guide:
${_researchUsageGuide(research, guide.intake)}

Research-grounded edit rules:
- For every replacement, alternative, restaurant, mall, shopping stop, cafe, activity, or area, choose a concrete named option from the curated research JSON or the existing itinerary. Search all research fields, not only attractions.
- If the user asks for a broad category such as "some mall", "a cafe", "shopping", "market", or "something modern", pick the best matching named place from research. Never write generic placeholders like "choose a good mall", "visit a nearby mall", "ask locally", or "find a cafe".
- For Hyderabad shopping/mall-style requests, prefer named researched options that fit the route and context, such as Shilparamam, Laad Bazaar, GVK One mall, Inorbit, Forum, Durgam Cheruvu, HITEC/Jubilee/Banjara zones, or other named options present in the research. Include any research warnings, such as mall restaurants being overpriced, when relevant.
- If there is no exact named match in research, choose the closest named researched place and explain the compromise inside the stop description. Do not invent a new place name.
''';

    return '''
You are Raaste, a careful local trip-planning assistant for India.
Revise this existing destination itinerary according to the user's edit request.

Edit request: $editRequest

Existing itinerary:
${jsonEncode(guide.toJson())}

Computed Google route timing context for the revised/current stay and travel mode:
${jsonEncode(timingContext.toJson())}
$researchBlock
Requirements:
- Keep the same destination unless the user explicitly asks to change it.
- The intake is editable. If the user asks to change dates, arrival/landing time, departure time, stay/hotel/base, travel mode, traveller count, pace preference, interests, or dietary preference, update the matching intake field in the JSON response.
- Preserve useful stops unless the user asks to change them, but rebuild timing and day structure around any updated intake.
$lengthInstruction
- Respect the revised arrival/landing time on Day 1 and revised departure time on the final day.
- Respect intake.travelMode and intake.stayNameOrAddress when revising route order, transfer buffers, parking/drop points, station/airport advice, and local movement.
- Use the computed Google route timing context as hard minimum travel time. Add buffer when needed, but do not create overlapping or impossible stop times.
- Do not write "sourceId", "Source IDs", "research:...", JSON keys, or raw source references inside visible text fields. The sourceId property is the only place source IDs belong.
- Do not repeat the same specific attraction, restaurant, or food stop across multiple days unless it is the stay/base, arrival hub, departure hub, or a required transfer.
- Return an intake object with all fields filled: destination, sourceId, displayAddress, lat, lon, dates, landingTime, departureTime, stayNameOrAddress, stayLat, stayLon, peopleCount, travelMode, pacePreference, interests, and dietaryPreference.
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

  Future<List<TripAlternativeSuggestion>> suggestTripAlternatives({
    required DestinationGuide guide,
    required Map<String, dynamic> researchContext,
    required String request,
  }) async {
    final apiKey = dotenv.env['OPENAI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const OpenAiGuideException(
        'Add OPENAI_API_KEY in .env to suggest trip alternatives.',
      );
    }

    final model = dotenv.env['OPENAI_MODEL']?.trim();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/responses',
        data: {
          'model': model?.isNotEmpty == true ? model : 'gpt-4.1-mini',
          'input': _alternativePrompt(
            guide: guide,
            researchContext: researchContext,
            request: request,
          ),
          'text': {
            'format': {
              'type': 'json_schema',
              'name': 'trip_alternatives',
              'strict': true,
              'schema': _alternativesSchema,
            },
          },
        },
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      final text = _extractOutputText(response.data ?? <String, dynamic>{});
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final alternatives =
          (decoded['alternatives'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(TripAlternativeSuggestion.fromJson)
              .where((item) => item.isValid)
              .take(4)
              .toList();
      if (alternatives.isEmpty) {
        throw const OpenAiGuideException(
          'I could not find useful alternatives for that stop. Try naming the place you want to replace.',
        );
      }
      return alternatives;
    } on OpenAiGuideException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const OpenAiGuideException(
          'OpenAI rejected the API key. Check OPENAI_API_KEY in .env.',
        );
      }
      final detail = _openAiErrorMessage(e.response?.data);
      if (detail != null) {
        throw OpenAiGuideException('Could not suggest alternatives: $detail');
      }
      throw const OpenAiGuideException(
        'Could not suggest alternatives right now. Please try again.',
      );
    } on FormatException {
      throw const OpenAiGuideException(
        'The alternatives response was not in the expected format. Please try again.',
      );
    }
  }

  String _alternativePrompt({
    required DestinationGuide guide,
    required Map<String, dynamic> researchContext,
    required String request,
  }) {
    return '''
You are Raaste, an itinerary editing assistant for India.

The traveller asked for alternatives before changing the saved itinerary.
User request:
$request

Current saved itinerary JSON:
${jsonEncode(guide.toJson())}

Curated local research JSON:
${jsonEncode(researchContext)}

Return 2 to 4 practical alternatives that can replace the place, meal, or activity the traveller is asking about.
Rules:
- Use only the curated research or places already present in the saved itinerary. Search all research fields, including attractions, itinerary frameworks, local knowledge, accommodation areas, money/trap notes, shopping notes, and restaurants.
- If the user asks for a broad category such as "some mall", "a cafe", "shopping", "market", or "something modern", return concrete named options from research that match the category. Do not tell the user to choose a mall or find one nearby.
- For Hyderabad shopping/mall-style requests, valid researched options may include Shilparamam, Laad Bazaar, GVK One mall, Inorbit, Forum, Durgam Cheruvu, HITEC/Jubilee/Banjara zones, or other named places present in the research. Prefer options that fit the current route and timing.
- Respect the traveller's dietary preference: ${guide.intake.dietaryPreference}.
- Do not change trip dates, arrival time, departure time, hotel/stay, people count, pace, interests, or travel mode.
- Each title must be a concrete place, restaurant, area, or activity name from research. Never use generic titles such as "Nearby mall", "Good cafe", "Shopping option", or "Choose a mall".
- Each editRequest must be ready to pass into an itinerary revision call. It should explicitly say what to replace, which day/time if known, the selected named alternative, and that nearby timings should be adjusted without changing dates or trip length.
- If research warns about the option, include that warning in the reason, for example overpriced mall restaurants.
Return only JSON matching the schema.
''';
  }

  Future<String> askCompanion({
    required Map<String, dynamic> tripContext,
    required Map<String, dynamic> researchContext,
    required List<Map<String, String>> history,
    required String question,
  }) async {
    final apiKey = dotenv.env['OPENAI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const OpenAiGuideException(
        'Add OPENAI_API_KEY in .env to use the companion.',
      );
    }

    final model = dotenv.env['OPENAI_MODEL']?.trim();
    final systemPrompt = _companionSystemPrompt(tripContext, researchContext);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/responses',
        data: {
          'model': model?.isNotEmpty == true ? model : 'gpt-4.1-mini',
          'instructions': systemPrompt,
          'input': _companionConversationInput(history, question),
          'max_output_tokens': 600,
        },
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      final content = _extractOutputText(response.data ?? <String, dynamic>{});
      if (content.trim().isEmpty) {
        throw const OpenAiGuideException(
          'Empty response from companion. Please try again.',
        );
      }
      return content.trim();
    } on OpenAiGuideException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const OpenAiGuideException(
          'OpenAI rejected the API key. Check OPENAI_API_KEY in .env.',
        );
      }
      final detail = _openAiErrorMessage(e.response?.data);
      if (detail != null) {
        throw OpenAiGuideException('Companion could not answer: $detail');
      }
      throw const OpenAiGuideException(
        'Companion could not reach AI right now. Check your connection and try again.',
      );
    }
  }

  String _companionConversationInput(
    List<Map<String, String>> history,
    String question,
  ) {
    final buffer = StringBuffer();
    if (history.isNotEmpty) {
      buffer.writeln('Recent conversation:');
      for (final message in history) {
        final rawRole = message['role'] ?? 'user';
        final role = rawRole == 'assistant' ? 'Raaste companion' : 'Traveller';
        final content = message['content']?.trim();
        if (content == null || content.isEmpty) continue;
        buffer.writeln('$role: $content');
      }
      buffer.writeln();
    }

    buffer.writeln('Traveller question:');
    buffer.write(question.trim());
    return buffer.toString();
  }

  String? _openAiErrorMessage(Object? data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }

  String _companionSystemPrompt(
    Map<String, dynamic> trip,
    Map<String, dynamic> research,
  ) {
    return '''
You are Raaste — a well-travelled local friend who has already been to this destination and is travelling with this person right now. You know their trip inside out: where they are staying, what they eat, what they want to do, and what today's plan is.

Your job is to answer their questions exactly like a knowledgeable local friend would — specific, direct, honest, and useful. Not a customer service bot. Not a brochure. A friend who says "skip that one, it's a tourist trap, go here instead."

This person's trip context:
${jsonEncode(trip)}

Curated local knowledge for this destination (research, restaurants, transport, tips, prices, crowd realities):
${jsonEncode(research)}

How to answer:
- Use the research as your source of truth. If a fact isn't in the research, say "I don't have verified info on that — best to check locally" rather than guessing.
- Dietary preference is non-negotiable: ${trip['dietary_preference'] ?? 'not specified'}. Never recommend a place that doesn't meet it.
- For restaurant questions, use the restaurant research. Mention what to order, cash/UPI reality, wait times, and any tourist-trap warnings from the research.
- For transport questions, use local_transport and how_to_reach from the research. Mention negotiation, apps that work, apps that don't, and real fares where available.
- For cost questions, give the research figure with "this may have changed — confirm before paying."
- For "what should I do now / this evening / today" questions, use today's itinerary day from the trip context and the user's interests: ${(trip['interests'] as List?)?.join(', ') ?? 'not specified'}.
- Keep answers concise — 3 to 6 sentences unless the question genuinely needs more. The person is on their phone, probably standing somewhere.
- Don't repeat what you just said in the previous message. Don't start every reply with "Great question!" or similar filler.
- If you don't know, say so briefly and suggest how to find out locally.
''';
  }

  bool _clearlyOneDay(String rawDates) {
    final text = rawDates.toLowerCase();
    return text.contains('one day') ||
        text.contains('1 day') ||
        text.contains('same day') ||
        text.contains('day trip');
  }

  static const Map<String, dynamic> _alternativesSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['alternatives'],
    'properties': {
      'alternatives': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 4,
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['title', 'reason', 'editRequest'],
          'properties': {
            'title': {'type': 'string'},
            'reason': {'type': 'string'},
            'editRequest': {'type': 'string'},
          },
        },
      },
    },
  };
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
          'stayNameOrAddress',
          'stayLat',
          'stayLon',
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
          'stayNameOrAddress': {'type': 'string'},
          'stayLat': {
            'type': ['number', 'null'],
          },
          'stayLon': {
            'type': ['number', 'null'],
          },
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
