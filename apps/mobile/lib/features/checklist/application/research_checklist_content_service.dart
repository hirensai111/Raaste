import 'dart:convert';

import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';

class ResearchChecklistContentService {
  const ResearchChecklistContentService();

  Map<String, dynamic> buildContent({
    required SavedTrip trip,
    required DestinationResearch research,
    required String checklistType,
    required DateTime checklistDate,
    int? dayNumber,
    int? totalDays,
  }) {
    final profile = _ResearchProfile.fromResearch(research);
    switch (checklistType) {
      case 'pre_trip':
        return _preTrip(trip, profile);
      case 'post_trip':
        return _postTrip(trip, profile);
      default:
        return _dailyTrip(
          trip,
          profile,
          dayNumber: dayNumber ?? 1,
          totalDays: totalDays,
        );
    }
  }

  Map<String, dynamic> _preTrip(SavedTrip trip, _ResearchProfile profile) {
    final destination = _destinationName(trip);
    final intake = trip.guide.intake;
    return _content(
      title: '$destination prep checklist',
      intro:
          'Research-backed prep for ${trip.dates.isNotEmpty ? trip.dates : intake.dates}.',
      sections: [
        _section('Bookings and timing', '#', 'Verify before money is spent', [
          _item(
            'Confirm stay and first transfer',
            _joinDetails([
              intake.stayNameOrAddress,
              profile.transportReality,
              'Keep buffer time for arrival and the first planned stop.',
            ]),
            priority: 'high',
          ),
          _item(
            'Verify major attraction timings',
            _joinDetails([
              _sampleTiming(profile.places),
              'Check official pages or venue phones before final payment.',
            ]),
            priority: 'high',
          ),
        ]),
        _section(
          'Pack for local conditions',
          'P',
          'Clothes, comfort, medicines',
          [
            _item(
              'Pack for local dress norms',
              _joinDetails([profile.dressCode, profile.clothing]),
              priority: 'high',
            ),
            _item(
              'Carry comfort essentials',
              _joinDetails([
                profile.packing,
                'Comfortable shoes, medicines, ID, and weather-ready layers.',
              ]),
              priority: 'medium',
            ),
          ],
        ),
        _section('Money and offline backup', '\$', 'Cash, UPI, maps', [
          _item(
            'Carry payment backup',
            _joinDetails([profile.cashVsUpi, profile.whereCash]),
            priority: 'high',
          ),
          _item(
            'Save maps and contacts offline',
            _joinDetails([profile.offlineMap, profile.connectivity]),
            priority: 'medium',
          ),
        ]),
        _section('Local awareness', '!', 'Scams, etiquette, safety', [
          _item(
            'Know common tourist traps',
            _joinDetails(profile.scams.take(3).toList()),
            priority: 'high',
          ),
          _item(
            'Respect local etiquette',
            _joinDetails([profile.etiquette.take(2).join(' '), profile.safety]),
            priority: 'medium',
          ),
        ]),
        _section('Food planning', 'F', 'Meals and dietary preference', [
          _item(
            'Shortlist reliable meals',
            _joinDetails([
              _dietary(profile, intake.dietaryPreference),
              profile.restaurantReality,
            ]),
            priority: 'medium',
          ),
          _item(
            'Plan safe snacks and water',
            _joinDetails([
              profile.foodSafety,
              'Carry water for outdoor stops and keep meals flexible.',
            ]),
            priority: 'medium',
          ),
        ]),
      ],
    );
  }

  Map<String, dynamic> _dailyTrip(
    SavedTrip trip,
    _ResearchProfile profile, {
    required int dayNumber,
    int? totalDays,
  }) {
    final destination = _destinationName(trip);
    final day = _dayFor(trip.guide, dayNumber);
    final contexts =
        (day?.stops ?? const <ItineraryStop>[])
            .map((stop) => _StopContext(stop, profile.match(stop)))
            .take(7)
            .toList();

    return _content(
      title:
          'Day $dayNumber${totalDays == null ? '' : ' of $totalDays'} checklist',
      intro:
          'Detailed local reminders for ${day?.title.trim().isNotEmpty == true ? day!.title : destination}.',
      sections: [
        _section('Before you leave', '>', 'Do these before stepping out', [
          _item(
            'Carry payment backup',
            _joinDetails([profile.cashVsUpi, profile.whereCash]),
            priority: 'high',
          ),
          _item(
            'Charge phone and save maps',
            _joinDetails([
              profile.offlineMap,
              profile.connectivity,
              'Keep a power bank ready for navigation and tickets.',
            ]),
            priority: 'high',
          ),
          _item(
            'Dress for today\'s route',
            _dressDetail(profile, contexts),
            priority: _hasDressStop(contexts) ? 'high' : 'medium',
          ),
          _item(
            'Verify tickets and lockers',
            _ticketDetail(contexts),
            priority: 'high',
          ),
        ]),
        _section(
          'Stop-by-stop prep',
          'S',
          day?.title ?? 'Your saved itinerary',
          _stopItems(contexts, profile),
        ),
        _section(
          'Money, safety, etiquette',
          '!',
          'Local realities to remember',
          [
            _item(
              'Avoid common tourist traps',
              _joinDetails(profile.scams.take(3).toList()),
              priority: 'high',
            ),
            _item(
              'Use transport with buffer time',
              _joinDetails([
                profile.transportReality,
                profile.transportScams.take(2).join(' '),
              ]),
              priority: 'medium',
            ),
            _item(
              'Follow local etiquette',
              _joinDetails([
                profile.etiquette.take(2).join(' '),
                profile.dressCode,
              ]),
              priority: 'medium',
            ),
          ],
        ),
        _section('Food and comfort', 'F', 'Meals, heat, and breaks', [
          ..._restaurantItems(contexts),
          _item(
            'Eat around your dietary preference',
            _joinDetails([
              _dietary(profile, trip.guide.intake.dietaryPreference),
              profile.restaurantReality,
            ]),
            priority: 'medium',
          ),
          _item(
            'Stay selective with street food',
            _joinDetails([
              profile.foodSafety,
              'Prefer busy stalls with high turnover and bottled water.',
            ]),
            priority: 'medium',
          ),
        ]),
        _section('Timing and comfort', 'T', 'Keep the day realistic', [
          _item(
            'Use crowd and heat buffers',
            _joinDetails([
              _crowdDetail(contexts),
              'Keep the next break flexible instead of rushing.',
            ]),
            priority: 'medium',
          ),
          _item(
            'Review tomorrow before sleeping',
            'Check the next route, cash needs, tickets, and weather while WiFi is available.',
            priority: 'low',
          ),
        ]),
      ],
    );
  }

  Map<String, dynamic> _postTrip(SavedTrip trip, _ResearchProfile profile) {
    final destination = _destinationName(trip);
    return _content(
      title: '$destination wrap-up checklist',
      intro: 'A practical wrap-up while trip details are still fresh.',
      sections: [
        _section('Today', '1', 'Close urgent loops', [
          _item(
            'Back up photos and tickets',
            'Save photos, entry tickets, hotel bills, and transport receipts before deleting anything.',
            priority: 'high',
          ),
          _item(
            'Check refunds and deposits',
            'Review hotel deposits, cab holds, bookings, and pending UPI/card transactions.',
            priority: 'medium',
          ),
        ]),
        _section('Remember what worked', '2', 'Keep useful local notes', [
          _item(
            'Save favorite local places',
            _joinDetails([
              profile.restaurantReality,
              'Mark restaurants, markets, and routes that were genuinely useful.',
            ]),
            priority: 'low',
          ),
          _item(
            'Note outdated research',
            'If a timing, fee, closure, or warning was different on-ground, flag it for your next plan.',
            priority: 'low',
          ),
        ]),
        _section('Share and review', '3', 'Help future travellers', [
          _item(
            'Review practical details',
            'Mention crowd timing, cash needs, accessibility, locker rules, and food quality.',
            priority: 'low',
          ),
          _item(
            'Organize trip expenses',
            _joinDetails([
              profile.cashVsUpi,
              'Split shared costs while memory is fresh.',
            ]),
            priority: 'medium',
          ),
        ]),
      ],
    );
  }
}

class _ResearchProfile {
  final List<_ResearchPlace> places;
  final String cashVsUpi;
  final String whereCash;
  final String offlineMap;
  final String connectivity;
  final String transportReality;
  final String dressCode;
  final String clothing;
  final String packing;
  final String foodSafety;
  final String restaurantReality;
  final String safety;
  final List<String> scams;
  final List<String> transportScams;
  final List<String> etiquette;
  final Map<String, dynamic> dietaryGuides;

  const _ResearchProfile({
    required this.places,
    required this.cashVsUpi,
    required this.whereCash,
    required this.offlineMap,
    required this.connectivity,
    required this.transportReality,
    required this.dressCode,
    required this.clothing,
    required this.packing,
    required this.foodSafety,
    required this.restaurantReality,
    required this.safety,
    required this.scams,
    required this.transportScams,
    required this.etiquette,
    required this.dietaryGuides,
  });

  factory _ResearchProfile.fromResearch(DestinationResearch research) {
    final data = research.data;
    final restaurantData = research.restaurantData ?? const <String, dynamic>{};
    final localTransport = _asMap(data['local_transport']);
    final money = _asMap(data['money']);
    final connectivity = _asMap(data['connectivity']);
    final localKnowledge = _asMap(data['local_knowledge']);
    final safety = _asMap(data['safety']);
    final packing = _asMap(data['packing']);
    final food = _asMap(data['food']);
    final scams = _dedupeStrings([
      ..._strings(localTransport['scam_warnings']),
      ..._trapTexts(localKnowledge['tourist_traps']),
      ..._trapTexts(localKnowledge['local_scams']),
      ..._strings(data['scam_warnings']),
    ]);

    return _ResearchProfile(
      places: _dedupePlaces([
        ..._collectPlaces(data, 'research', research.sourceId),
        ..._collectPlaces(
          restaurantData,
          'restaurantResearch',
          research.sourceId,
        ),
      ]),
      cashVsUpi: _firstText([money['cash_vs_upi'], data['cash_vs_upi']]),
      whereCash: _firstText([
        money['where_to_carry_cash'],
        data['where_to_carry_cash'],
      ]),
      offlineMap: _firstText([
        connectivity['offline_map_recommendation'],
        data['offline_map_recommendation'],
      ]),
      connectivity: _firstText([
        connectivity['mobile_network'],
        connectivity['wifi_availability'],
        _findFirstText(data, const ['mobile_network', 'wifi_availability']),
      ]),
      transportReality: _firstText([
        localTransport['transport_reality_check'],
        data['transport_reality_check'],
      ]),
      dressCode: _firstText([
        localKnowledge['dress_code'],
        _findFirstText(data, const ['dress_code']),
      ]),
      clothing: _firstText([packing['clothing']]),
      packing: _strings(
        packing['essentials_specific_to_destination'],
      ).take(5).join(' '),
      foodSafety: _firstText([
        food['street_food_safety'],
        restaurantData['street_food_guide'],
        _findFirstText(restaurantData, const ['street_food_safety']),
      ]),
      restaurantReality: _firstText([
        food['restaurant_price_reality'],
        food['tourist_trap_restaurants'],
        restaurantData['food_overview'],
      ]),
      safety: _firstText([
        safety['overall_safety_rating'],
        safety['safe_for_solo_women'],
      ]),
      scams: scams,
      transportScams: _strings(localTransport['scam_warnings']),
      etiquette: _strings(localKnowledge['cultural_etiquette']),
      dietaryGuides: _asMap(restaurantData['dietary_specific_guides']),
    );
  }

  _ResearchPlace? match(ItineraryStop stop) {
    _ResearchPlace? best;
    var bestScore = 0;
    for (final place in places) {
      final score = place.matchScore(stop);
      if (score > bestScore) {
        best = place;
        bestScore = score;
      }
    }
    return bestScore >= 34 ? best : null;
  }
}

class _StopContext {
  final ItineraryStop stop;
  final _ResearchPlace? place;

  const _StopContext(this.stop, this.place);
}

class _ResearchPlace {
  final String title;
  final String sourceId;
  final String category;
  final String description;
  final String localTip;
  final String bestTime;
  final String avoidWhen;
  final String entryFee;
  final String timeNeeded;
  final String crowdReality;
  final String warning;
  final String speciality;
  final String waitTime;
  final String practicalNote;
  final String searchText;

  const _ResearchPlace({
    required this.title,
    required this.sourceId,
    required this.category,
    required this.description,
    required this.localTip,
    required this.bestTime,
    required this.avoidWhen,
    required this.entryFee,
    required this.timeNeeded,
    required this.crowdReality,
    required this.warning,
    required this.speciality,
    required this.waitTime,
    required this.practicalNote,
    required this.searchText,
  });

  bool get isFoodLike => category == 'restaurant' || category == 'cafe';
  bool get isShoppingLike => category == 'shopping' || category == 'mall';
  bool get isReligiousLike =>
      category == 'spiritual' ||
      _containsAny(searchText, const ['temple', 'mosque', 'masjid', 'dargah']);
  bool get isOldCityLike => _containsAny(searchText, const [
    'old city',
    'charminar',
    'laad bazaar',
    'mecca masjid',
    'ghat',
    'gali',
  ]);

  int matchScore(ItineraryStop stop) {
    final stopTitle = _normalize(stop.title);
    final stopDescription = _normalize(stop.description);
    final stopType = _normalize(stop.type);
    final stopSource = _normalize(stop.sourceId);
    final placeTitle = _normalize(title);
    final slug = _slug(title);
    var score = 0;
    if (stopSource.isNotEmpty && slug.isNotEmpty && stopSource.contains(slug)) {
      score += 90;
    }
    if (stopSource.isNotEmpty && stopSource == _normalize(sourceId)) {
      score += 90;
    }
    if (stopTitle == placeTitle) score += 80;
    if (stopTitle.contains(placeTitle) || placeTitle.contains(stopTitle)) {
      score += 60;
    }
    if (stopDescription.contains(placeTitle)) score += 40;
    if (stopType.isNotEmpty && category.contains(stopType)) score += 12;
    score +=
        _tokens(
          '$stopTitle $stopDescription',
        ).intersection(_tokens(placeTitle)).length *
        8;
    return score;
  }
}

List<Map<String, dynamic>> _stopItems(
  List<_StopContext> contexts,
  _ResearchProfile profile,
) {
  final items = <Map<String, dynamic>>[];
  for (final context in contexts) {
    items.add(
      _item(
        'Prep for ${_shortTitle(context.stop.title)}',
        _stopDetail(context, profile),
        priority: _stopPriority(context),
      ),
    );
  }
  if (items.isNotEmpty) return _dedupeItems(items).take(6).toList();
  return [
    _item(
      'Review today\'s itinerary',
      'Open the itinerary and verify timings, routes, and tickets before leaving.',
      priority: 'medium',
    ),
    _item(
      'Keep the plan flexible',
      'Use local crowd, weather, and travel-time reality to adjust breaks.',
      priority: 'low',
    ),
  ];
}

List<Map<String, dynamic>> _restaurantItems(List<_StopContext> contexts) {
  final items = <Map<String, dynamic>>[];
  for (final context in contexts) {
    final place = context.place;
    if (place == null || !place.isFoodLike) continue;
    items.add(
      _item(
        'Plan meal at ${_shortTitle(place.title)}',
        _joinDetails([
          place.speciality,
          place.localTip,
          place.waitTime,
          place.practicalNote,
          place.warning,
        ]),
        priority: place.warning.isEmpty ? 'medium' : 'high',
      ),
    );
  }
  return _dedupeItems(items).take(2).toList();
}

String _stopDetail(_StopContext context, _ResearchProfile profile) {
  final stop = context.stop;
  final place = context.place;
  return _joinDetails([
    stop.time.trim().isEmpty ? null : 'Planned time: ${stop.time}',
    place == null ? stop.description : place.description,
    place?.localTip.isEmpty == false ? 'Local tip: ${place!.localTip}' : null,
    place?.bestTime.isEmpty == false ? 'Best timing: ${place!.bestTime}' : null,
    place?.avoidWhen.isEmpty == false ? 'Avoid: ${place!.avoidWhen}' : null,
    place?.entryFee.isEmpty == false
        ? 'Entry/ticket: ${place!.entryFee}'
        : null,
    place?.timeNeeded.isEmpty == false
        ? 'Time needed: ${place!.timeNeeded}'
        : null,
    place?.crowdReality.isEmpty == false
        ? 'Crowd note: ${place!.crowdReality}'
        : null,
    place?.practicalNote,
    place?.warning.isEmpty == false ? 'Watch out: ${place!.warning}' : null,
    place?.isShoppingLike == true ? profile.whereCash : null,
    place?.isReligiousLike == true || place?.isOldCityLike == true
        ? profile.dressCode
        : null,
  ]);
}

String _dressDetail(_ResearchProfile profile, List<_StopContext> contexts) {
  final sensitiveStops = contexts
      .where((context) {
        final place = context.place;
        final text = _normalize(
          '${context.stop.title} ${context.stop.description}',
        );
        return place?.isReligiousLike == true ||
            place?.isOldCityLike == true ||
            _containsAny(text, const [
              'temple',
              'mosque',
              'masjid',
              'old city',
            ]);
      })
      .map((context) => context.stop.title)
      .take(3)
      .join(', ');
  return _joinDetails([
    sensitiveStops.isEmpty ? null : 'Relevant today for: $sensitiveStops',
    profile.dressCode,
    profile.clothing,
    'Prefer comfortable shoes for walking and standing in queues.',
  ]);
}

String _ticketDetail(List<_StopContext> contexts) {
  final notes = <String>[];
  for (final context in contexts) {
    final place = context.place;
    if (place == null) continue;
    final detail = _joinDetails([
      place.entryFee.isEmpty ? null : '${place.title}: ${place.entryFee}',
      place.avoidWhen.isEmpty
          ? null
          : '${place.title}: avoid ${place.avoidWhen}',
      place.bestTime.isEmpty ? null : '${place.title}: best ${place.bestTime}',
    ]);
    if (detail.isNotEmpty) notes.add(detail);
  }
  return notes.isEmpty
      ? 'Check opening hours, ticket counters, locker rules, and closure days before leaving.'
      : _joinDetails(notes.take(4).toList());
}

String _crowdDetail(List<_StopContext> contexts) {
  final notes = <String>[];
  for (final context in contexts) {
    final place = context.place;
    if (place == null) continue;
    final detail = _joinDetails([
      place.crowdReality.isEmpty
          ? null
          : '${place.title}: ${place.crowdReality}',
      place.avoidWhen.isEmpty
          ? null
          : '${place.title}: avoid ${place.avoidWhen}',
    ]);
    if (detail.isNotEmpty) notes.add(detail);
  }
  return notes.isEmpty
      ? 'Add buffers for traffic, queues, heat, and meal delays.'
      : _joinDetails(notes.take(3).toList());
}

List<_ResearchPlace> _collectPlaces(
  Object? value,
  String path,
  String sourceId,
) {
  final places = <_ResearchPlace>[];
  void collect(Object? current, String currentPath) {
    if (current is List) {
      for (var i = 0; i < current.length; i++) {
        final item = current[i];
        if (item is String && _isPlaceListPath(currentPath)) {
          final place = _placeFromText(item, currentPath, sourceId);
          if (place != null) places.add(place);
        }
        collect(item, '$currentPath[$i]');
      }
      return;
    }
    final map = _asMap(current);
    if (map.isEmpty) return;
    final title = _placeTitle(map);
    if (title != null && _looksLikePlaceMap(map, currentPath)) {
      final place = _placeFromMap(title, map, currentPath, sourceId);
      if (place != null) places.add(place);
    }
    for (final entry in map.entries) {
      collect(entry.value, '$currentPath.${entry.key}');
    }
  }

  collect(value, path);
  return places;
}

_ResearchPlace? _placeFromMap(
  String title,
  Map<String, dynamic> map,
  String path,
  String sourceId,
) {
  final location = _asMap(map['location']);
  final practical = _asMap(map['practical']);
  final text = _mapText(map);
  final category = _categoryFor(title, _text(map['type']), path, text);
  if (category == 'ignore') return null;
  final touristTrapWarning = map['tourist_trap_warning'] == true;
  final warning = _firstText([
    touristTrapWarning ? map['tourist_trap_detail'] : null,
    map['tourist_trap_detail'],
    map['warning'],
    map['avoid_when'],
  ]);
  final practicalBits = <String>[
    _boolNote(practical['cash_only'], 'Cash only'),
    practical['upi_accepted'] == false ? 'UPI may not be accepted' : '',
    _boolNote(practical['reservation_required'], 'Reservation recommended'),
    _text(practical['reservation_note']),
    _text(practical['parking']),
    practical['ac_available'] == true ? 'AC available' : '',
  ];
  final sourcePrefix =
      path.startsWith('restaurantResearch')
          ? 'research:$sourceId:food'
          : 'research:$sourceId';
  return _ResearchPlace(
    title: title,
    sourceId: '$sourcePrefix:${_slug(title)}',
    category: category,
    description: _firstText([
      map['why_worth_it'],
      map['why_hidden'],
      map['raaste_recommendation_reason'],
      map['description'],
      map['speciality'],
      map['reason'],
    ]),
    localTip: _text(map['local_tip']),
    bestTime: _firstText([map['best_time_to_visit'], map['best_time']]),
    avoidWhen: _text(map['avoid_when']),
    entryFee: _text(map['entry_fee']),
    timeNeeded: _text(map['time_needed']),
    crowdReality: _firstText([map['crowd_reality'], map['wait_time_reality']]),
    warning: warning,
    speciality: _firstText([
      map['speciality'],
      _signatureDishText(map['signature_dishes']),
    ]),
    waitTime: _text(map['wait_time_reality']),
    practicalNote: _joinDetails(practicalBits),
    searchText: _normalize('$title $path $text ${_mapText(location)}'),
  );
}

_ResearchPlace? _placeFromText(String raw, String path, String sourceId) {
  final title =
      raw.split(RegExp(r'[:\-]')).first.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.length < 3 || title.length > 80) return null;
  final category = _categoryFor(title, '', path, raw);
  if (category == 'ignore') return null;
  return _ResearchPlace(
    title: title,
    sourceId: 'research:$sourceId:${_slug(title)}',
    category: category,
    description: raw,
    localTip: '',
    bestTime: '',
    avoidWhen: '',
    entryFee: '',
    timeNeeded: '',
    crowdReality: '',
    warning: '',
    speciality: '',
    waitTime: '',
    practicalNote: '',
    searchText: _normalize('$title $path $raw'),
  );
}

bool _looksLikePlaceMap(Map<String, dynamic> map, String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.destination') ||
      lowerPath.contains('.location') ||
      lowerPath.contains('.coordinates') ||
      lowerPath.contains('.practical') ||
      lowerPath.contains('.rating_signals') ||
      lowerPath.contains('.dietary_tags') ||
      lowerPath.contains('.signature_dishes') ||
      lowerPath.contains('data_quality')) {
    return false;
  }
  if (_isGenericTitle(_placeTitle(map) ?? '')) return false;
  if (_isPlaceListPath(lowerPath)) return true;
  const fields = [
    'description',
    'why_worth_it',
    'why_hidden',
    'best_time_to_visit',
    'local_tip',
    'entry_fee',
    'avoid_when',
    'cuisine',
    'speciality',
    'raaste_recommendation_reason',
  ];
  return fields.any(map.containsKey);
}

bool _isPlaceListPath(String path) {
  final lower = path.toLowerCase();
  return lower.contains('attractions') ||
      lower.contains('hidden_gems') ||
      lower.contains('restaurants') ||
      lower.contains('malls') ||
      lower.contains('markets') ||
      lower.contains('shopping') ||
      lower.contains('photography_spots') ||
      lower.contains('nearby_destinations');
}

String? _placeTitle(Map<String, dynamic> map) {
  for (final key in const ['name', 'title', 'place', 'restaurant']) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String _categoryFor(String title, String type, String path, String text) {
  final lower = _normalize('$title $type $path $text');
  final normalizedType = _normalize(type);
  if (_containsAny(normalizedType, const ['restaurant', 'dhaba'])) {
    return 'restaurant';
  }
  if (_containsAny(normalizedType, const [
        'cafe',
        'bakery',
        'sweet',
        'street',
        'stall',
      ]) ||
      _containsAny(lower, const ['cafe', 'ice cream', 'sweets', 'chaat'])) {
    return 'cafe';
  }
  if (_isMallTitle(title) || lower.contains('malls')) return 'mall';
  if (_containsAny(lower, const [
    'market',
    'bazaar',
    'shopping',
    'craft',
    'handicraft',
    'souvenir',
    'pearl',
    'bangle',
    'saree',
  ])) {
    return 'shopping';
  }
  if (_containsAny(lower, const [
    'pub',
    'bar',
    'club',
    'nightlife',
    'hitec',
    'jubilee',
    'banjara',
    'city lights',
    'promenade',
  ])) {
    return 'urban';
  }
  if (_containsAny(lower, const [
    'lake',
    'park',
    'garden',
    'trail',
    'viewpoint',
  ])) {
    return 'nature';
  }
  if (lower.contains('museum')) return 'museum';
  if (_containsAny(lower, const ['temple', 'mosque', 'masjid', 'dargah'])) {
    return 'spiritual';
  }
  if (_containsAny(lower, const [
    'fort',
    'tomb',
    'palace',
    'monument',
    'heritage',
    'archaeological',
  ])) {
    return 'heritage';
  }
  return 'activity';
}

bool _isMallTitle(String title) {
  return _containsAny(_normalize(title), const [
    'mall',
    'inorbit',
    'gvk one',
    'forum',
    'nexus',
    'phoenix',
  ]);
}

List<_ResearchPlace> _dedupePlaces(List<_ResearchPlace> places) {
  final byKey = <String, _ResearchPlace>{};
  for (final place in places) {
    final key = _normalize(place.title);
    final existing = byKey[key];
    if (existing == null || place.localTip.length > existing.localTip.length) {
      byKey[key] = place;
    }
  }
  return byKey.values.toList();
}

Map<String, dynamic> _content({
  required String title,
  required String intro,
  required List<Map<String, dynamic>> sections,
}) {
  final cleanSections =
      sections
          .map((section) {
            final items = _dedupeItems(
              (section['items'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .where((item) => _text(item['text']).isNotEmpty)
                  .toList(),
            );
            return {...section, 'items': items};
          })
          .where((section) => (section['items'] as List).isNotEmpty)
          .take(6)
          .toList();
  return {
    'source': 'research_local',
    'title': title,
    'intro': intro,
    'sections': cleanSections,
  };
}

Map<String, dynamic> _section(
  String name,
  String icon,
  String context,
  List<Map<String, dynamic>> items,
) => {'name': name, 'emoji': icon, 'context': context, 'items': items};

Map<String, dynamic> _item(
  String text,
  String detail, {
  String priority = 'medium',
  String actionLabel = '',
}) => {
  'text': _compactText(text, maxLength: 90),
  'detail': _compactText(detail, maxLength: 620),
  'priority': priority,
  'action_label': actionLabel,
  'done': false,
};

List<Map<String, dynamic>> _dedupeItems(List<Map<String, dynamic>> items) {
  final seen = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final item in items) {
    final key = _normalize(_text(item['text']));
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(item);
  }
  return result;
}

String _sampleTiming(List<_ResearchPlace> places) {
  final notes = <String>[];
  for (final place in places) {
    if (place.bestTime.isEmpty && place.avoidWhen.isEmpty) continue;
    notes.add(
      _joinDetails([
        '${place.title}:',
        place.bestTime.isEmpty ? null : 'best ${place.bestTime};',
        place.avoidWhen.isEmpty ? null : 'avoid ${place.avoidWhen}',
      ]),
    );
    if (notes.length == 3) break;
  }
  return notes.join(' ');
}

String _dietary(_ResearchProfile profile, String preference) {
  final key = _normalize(preference);
  for (final entry in profile.dietaryGuides.entries) {
    if (key.isNotEmpty && _normalize(entry.key).contains(key)) {
      return _text(entry.value);
    }
  }
  if (profile.dietaryGuides.isNotEmpty) {
    return _text(profile.dietaryGuides.values.first);
  }
  return preference.trim().isEmpty
      ? 'Pick meals from researched reliable restaurants and busy stalls.'
      : 'Use researched restaurants that fit $preference and confirm ingredients before ordering.';
}

String _stopPriority(_StopContext context) {
  final place = context.place;
  if (place == null) return 'medium';
  if (place.warning.isNotEmpty ||
      place.avoidWhen.isNotEmpty ||
      place.isReligiousLike ||
      place.isOldCityLike) {
    return 'high';
  }
  return 'medium';
}

bool _hasDressStop(List<_StopContext> contexts) {
  return contexts.any((context) {
    final place = context.place;
    final text = _normalize(
      '${context.stop.title} ${context.stop.description}',
    );
    return place?.isReligiousLike == true ||
        place?.isOldCityLike == true ||
        _containsAny(text, const ['temple', 'mosque', 'masjid', 'old city']);
  });
}

ItineraryDay? _dayFor(DestinationGuide guide, int dayNumber) {
  final matches = guide.itineraryDays.where(
    (day) => day.dayNumber == dayNumber,
  );
  if (matches.isNotEmpty) return matches.first;
  return guide.itineraryDays.isEmpty ? null : guide.itineraryDays.first;
}

String _destinationName(SavedTrip trip) {
  final saved = trip.destinationName.trim();
  if (saved.isNotEmpty) return saved;
  final guide = trip.guide.destinationName.trim();
  return guide.isEmpty ? 'your trip' : guide;
}

List<String> _trapTexts(Object? value) {
  if (value is List) {
    return value
        .map((item) {
          final map = _asMap(item);
          if (map.isEmpty) return _text(item);
          return _joinDetails([
            _text(map['trap']),
            _text(map['name']),
            _text(map['reality']),
            _text(map['how_to_avoid']),
          ]);
        })
        .where((text) => text.isNotEmpty)
        .toList();
  }
  return _strings(value);
}

String _findFirstText(Object? value, List<String> keys) {
  if (value is List) {
    for (final item in value) {
      final found = _findFirstText(item, keys);
      if (found.isNotEmpty) return found;
    }
    return '';
  }
  final map = _asMap(value);
  if (map.isEmpty) return '';
  for (final key in keys) {
    final direct = _text(map[key]);
    if (direct.isNotEmpty) return direct;
  }
  for (final item in map.values) {
    final found = _findFirstText(item, keys);
    if (found.isNotEmpty) return found;
  }
  return '';
}

String _firstText(List<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> _strings(Object? value) {
  if (value is List) {
    return value.map(_text).where((text) => text.isNotEmpty).toList();
  }
  final text = _text(value);
  return text.isEmpty ? const [] : [text];
}

List<String> _dedupeStrings(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final clean = _compactText(value, maxLength: 260);
    final key = _normalize(clean);
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(clean);
  }
  return result;
}

String _joinDetails(List<Object?> values) {
  final parts =
      values
          .map(_text)
          .where((text) => text.isNotEmpty)
          .map((text) => text.endsWith('.') ? text : '$text.')
          .toList();
  if (parts.isEmpty) {
    return 'Verify timings, prices, and local conditions before leaving.';
  }
  return _compactText(parts.join(' '), maxLength: 780);
}

String _text(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map(_text).where((text) => text.isNotEmpty).join(' ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_text(entry.value)}')
        .where((text) => !text.endsWith(': '))
        .join(' ');
  }
  return value.toString().trim();
}

String _boolNote(Object? value, String note) => value == true ? note : '';

String _signatureDishText(Object? value) {
  final items = value is List ? value : const [];
  return items
      .whereType<Map>()
      .map(
        (dish) =>
            _joinDetails([dish['dish'], dish['description'], dish['price']]),
      )
      .where((text) => text.isNotEmpty)
      .take(3)
      .join(' ');
}

String _mapText(Map<String, dynamic> map) => jsonEncode(map);

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

bool _isGenericTitle(String value) {
  final text = _normalize(value);
  return text.isEmpty ||
      const {
        'destination',
        'location',
        'coordinates',
        'practical',
        'rating signals',
        'data quality',
      }.contains(text);
}

String _shortTitle(String value) {
  final clean = value.split('|').first.trim();
  return _compactText(clean.isEmpty ? 'this stop' : clean, maxLength: 42);
}

String _compactText(String value, {required int maxLength}) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  final clipped = normalized.substring(0, maxLength).trimRight();
  final lastSpace = clipped.lastIndexOf(' ');
  if (lastSpace > maxLength * 0.65) {
    return '${clipped.substring(0, lastSpace)}...';
  }
  return '$clipped...';
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _slug(String value) => _normalize(value).replaceAll(' ', '-');

Set<String> _tokens(String value) {
  return _normalize(
    value,
  ).split(' ').where((token) => token.length > 2).toSet();
}

bool _containsAny(String value, List<String> terms) {
  final lower = value.toLowerCase();
  return terms.any(lower.contains);
}
