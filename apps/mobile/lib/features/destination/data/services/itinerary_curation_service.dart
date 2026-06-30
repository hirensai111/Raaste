import 'dart:math' as math;

import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class ItineraryCurationService {
  const ItineraryCurationService();

  DestinationGuide curateGeneratedGuide({
    required DestinationGuide guide,
    required DestinationResearch research,
  }) {
    final profile = _InterestProfile.fromIntake(guide.intake);
    final catalog = _ResearchCatalog.fromResearch(research, guide.intake);
    if (catalog.places.isEmpty) return guide;

    final usedKeys = <String>{};
    var cityProfileHeritageCount = 0;
    final curatedDays = <ItineraryDay>[];

    for (final day in guide.itineraryDays) {
      final dayCategoryCounts = <String, int>{};
      final curatedStops = <ItineraryStop>[];

      for (final stop in day.stops) {
        final originalKeys = _stopKeys(stop);
        final currentCategory = _categoryForStop(stop);
        final duplicate = originalKeys.any(usedKeys.contains);
        final generic = _isGenericFiller(stop);
        final offBrief = _shouldReplaceForInterest(
          stop: stop,
          category: currentCategory,
          dayCategoryCounts: dayCategoryCounts,
          profile: profile,
          cityProfileHeritageCount: cityProfileHeritageCount,
        );

        var nextStop = stop;
        _ResearchPlace? selectedReplacement;
        if (duplicate || generic || offBrief) {
          final replacement = catalog.bestReplacement(
            replacing: stop,
            currentCategory: currentCategory,
            profile: profile,
            usedKeys: usedKeys,
          );
          if (replacement != null) {
            selectedReplacement = replacement;
            nextStop = replacement.toStopReplacing(stop);
          } else if (duplicate) {
            continue;
          }
        }

        if (selectedReplacement != null) {
          usedKeys.addAll(selectedReplacement.keys);
        }
        usedKeys.addAll(_stopKeys(nextStop));
        final nextCategory = _categoryForStop(nextStop);
        dayCategoryCounts[nextCategory] =
            (dayCategoryCounts[nextCategory] ?? 0) + 1;
        if (profile.prefersCityLife && _isHeritageLike(nextCategory)) {
          cityProfileHeritageCount++;
        }
        curatedStops.add(nextStop);
      }

      curatedDays.add(
        ItineraryDay(
          dayNumber: day.dayNumber,
          title: day.title,
          subtitle: day.subtitle,
          stops: curatedStops,
        ),
      );
    }

    return guide.copyWith(
      itineraryDays: curatedDays,
      updatedAt: DateTime.now(),
    );
  }

  bool _shouldReplaceForInterest({
    required ItineraryStop stop,
    required String category,
    required Map<String, int> dayCategoryCounts,
    required _InterestProfile profile,
    required int cityProfileHeritageCount,
  }) {
    if (!profile.hasSpecificInterests) return false;
    if (_isTransferOrRest(stop)) return false;
    if (_isMealStop(stop)) return false;

    if (profile.prefersCityLife && !profile.wantsHistoryOrSpiritual) {
      if (_isHeritageLike(category)) {
        final alreadyHasHeritageToday = (dayCategoryCounts[category] ?? 0) > 0;
        final title = _normalize(stop.title);
        final isUsefulCityAnchor =
            title.contains('charminar') ||
            title.contains('hussain sagar') ||
            title.contains('necklace road') ||
            title.contains('durgam cheruvu') ||
            title.contains('tank bund');
        if (alreadyHasHeritageToday || cityProfileHeritageCount >= 1) {
          return true;
        }
        if (!isUsefulCityAnchor && _looksLikeHeavySightseeing(stop)) {
          return true;
        }
      }
      if (category == 'museum' || category == 'spiritual') return true;
    }

    if (profile.wantsShopping &&
        !profile.wantsHistoryOrSpiritual &&
        _isHeritageLike(category) &&
        (dayCategoryCounts['shopping'] ?? 0) == 0 &&
        (dayCategoryCounts['mall'] ?? 0) == 0) {
      return true;
    }

    return false;
  }
}

class _ResearchCatalog {
  final List<_ResearchPlace> places;

  const _ResearchCatalog(this.places);

  factory _ResearchCatalog.fromResearch(
    DestinationResearch research,
    TripIntake intake,
  ) {
    final collector = _ResearchCollector(research);
    collector.collect(research.data, 'research');
    final restaurantData = research.restaurantData;
    if (restaurantData != null) {
      collector.collect(restaurantData, 'restaurantResearch');
    }
    return _ResearchCatalog(_dedupe(collector.places));
  }

  _ResearchPlace? bestReplacement({
    required ItineraryStop replacing,
    required String currentCategory,
    required _InterestProfile profile,
    required Set<String> usedKeys,
  }) {
    final replacingKeys = _stopKeys(replacing);
    final meal = _isMealStop(replacing);
    final time = replacing.time;
    _ResearchPlace? best;
    var bestScore = double.negativeInfinity;

    for (final place in places) {
      if (place.keys.any(usedKeys.contains)) continue;
      if (place.keys.any(replacingKeys.contains)) continue;
      if (_samePlace(place.title, replacing.title)) continue;
      if (meal && !place.isMealEligible(profile)) continue;
      if (!meal && place.category == 'restaurant' && !profile.wantsFood) {
        continue;
      }
      if (!meal && place.category == 'cafe' && !profile.wantsFood) {
        final usefulNightStop = profile.wantsNightlife && place.isEveningLike;
        final snackShop =
            place.searchText.contains('sweet') ||
            place.searchText.contains('bakery') ||
            place.searchText.contains('ice cream') ||
            place.searchText.contains('dessert');
        if (!usefulNightStop || snackShop) continue;
      }
      if (profile.prefersCityLife &&
          !profile.wantsHistoryOrSpiritual &&
          _isHeritageLike(place.category)) {
        continue;
      }

      var score = 0.0;
      if (place.structured) score += 12;
      if (_categoryMatches(currentCategory, place.category)) score += 12;
      for (final desired in profile.desiredCategories) {
        if (_categoryMatches(desired, place.category)) score += 85;
      }
      if (profile.prefersCityLife && place.isCityLife) score += 55;
      if (profile.wantsShopping && place.isShoppingLike) score += 45;
      if (profile.wantsNightlife && place.isEveningLike) score += 45;
      if (profile.wantsFood && place.isMealEligible(profile)) score += 40;
      if (profile.wantsPhotography && place.isPhotogenic) score += 30;
      if (_timeFits(time, place)) score += 24;
      if (place.warning != null && place.warning!.isNotEmpty) score -= 6;

      final title = _normalize(place.title);
      if (profile.prefersCityLife) {
        if (title.contains('shilparamam')) score += 36;
        if (title.contains('durgam cheruvu')) score += 70;
        if (title.contains('necklace road') || title.contains('tank bund')) {
          score += 58;
        }
        if (title.contains('jubilee') ||
            title.contains('banjara') ||
            title.contains('hitec')) {
          score += 22;
        }
      }
      if (profile.wantsShopping) {
        if (title.contains('laad bazaar')) score += 34;
        if (title.contains('mall')) score += 20;
      }

      if (score > bestScore) {
        bestScore = score;
        best = place;
      }
    }

    if (bestScore < 45) return null;
    return best;
  }

  static List<_ResearchPlace> _dedupe(List<_ResearchPlace> raw) {
    final byKey = <String, _ResearchPlace>{};
    for (final place in raw) {
      if (place.title.trim().length < 3) continue;
      if (_isGenericTitle(place.title)) continue;
      final existing = byKey[place.key];
      if (existing == null ||
          (!existing.structured && place.structured) ||
          place.description.length > existing.description.length) {
        byKey[place.key] = place;
      }
    }
    final items = byKey.values.toList();
    items.sort((a, b) {
      if (a.structured != b.structured) return a.structured ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return items;
  }
}

class _ResearchCollector {
  final DestinationResearch research;
  final List<_ResearchPlace> places = [];

  _ResearchCollector(this.research);

  void collect(Object? value, String path) {
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        collect(value[i], '$path[$i]');
      }
      return;
    }

    final map = _asMap(value);
    if (map.isEmpty) return;

    final title = _placeTitle(map);
    if (title != null && _looksLikePlaceMap(map, path)) {
      final place = _placeFromMap(title, map, path);
      if (place != null) places.add(place);
    }

    for (final entry in map.entries) {
      collect(entry.value, '$path.${entry.key}');
    }
  }

  _ResearchPlace? _placeFromMap(
    String title,
    Map<String, dynamic> map,
    String path,
  ) {
    final text = _mapText(map);
    final type = _asText(map['type']);
    final category = _categoryForPlace(
      title: title,
      type: type,
      path: path,
      text: text,
    );
    if (category == 'ignore') return null;

    final coordinates = _asMap(map['coordinates']);
    final location = _asMap(map['location']);
    final dietary = _asMap(map['dietary_tags']);
    final warning = _firstText(map, const [
      'tourist_trap_warning',
      'tourist_trap_detail',
      'avoid_when',
      'warning',
    ]);
    final description = _firstText(map, const [
      'why_worth_it',
      'why_hidden',
      'raaste_recommendation_reason',
      'description',
      'speciality',
      'reason',
      'tip',
    ]);
    final sourcePrefix =
        path.startsWith('restaurantResearch')
            ? 'research:${research.sourceId}:food'
            : 'research:${research.sourceId}';

    return _ResearchPlace(
      title: title,
      category: category,
      sourceId: '$sourcePrefix:${_slug(title)}',
      description: description,
      bestTime:
          _asText(map['best_time_to_visit']) +
          (_asText(map['best_time']).isEmpty
              ? ''
              : ' ${_asText(map['best_time'])}'),
      timeNeeded: _asText(map['time_needed']),
      localTip: _asText(map['local_tip']),
      warning: warning.isEmpty ? null : warning,
      searchText: _normalize('$title $type $path $text'),
      vegOnly: _asBool(dietary['veg_only']),
      jainAvailable: _asBool(dietary['jain_available']),
      veganOptions: _asBool(dietary['vegan_options']),
      halal: _asBool(dietary['halal']),
      nonVegAvailable: _asBool(dietary['non_veg_available']),
      lat: _asDouble(coordinates['lat']) ?? _asDouble(location['lat']),
      lon:
          _asDouble(coordinates['lng']) ??
          _asDouble(coordinates['lon']) ??
          _asDouble(location['lng']) ??
          _asDouble(location['lon']),
      structured: true,
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
    if (lowerPath.contains('attractions') ||
        lowerPath.contains('hidden_gems') ||
        lowerPath.contains('restaurants') ||
        lowerPath.contains('malls') ||
        lowerPath.contains('markets')) {
      return true;
    }
    const fields = [
      'description',
      'why_worth_it',
      'why_hidden',
      'best_time_to_visit',
      'local_tip',
      'coordinates',
      'how_to_get_there',
      'cuisine',
      'speciality',
      'raaste_recommendation_reason',
      'tip',
    ];
    return fields.any(map.containsKey);
  }

  String _categoryForPlace({
    required String title,
    required String type,
    required String path,
    required String text,
  }) {
    final lower = _normalize('$title $type $path $text');
    final normalizedType = _normalize(type);
    if (normalizedType.contains('restaurant') ||
        normalizedType.contains('dhaba')) {
      return 'restaurant';
    }
    if (normalizedType.contains('cafe') ||
        normalizedType.contains('bakery') ||
        normalizedType.contains('sweet') ||
        normalizedType.contains('street') ||
        normalizedType.contains('stall')) {
      return 'cafe';
    }
    if (_isMallTitle(title) || lower.contains(' malls ')) return 'mall';
    if (RegExp(
      r'\b(market|bazaar|shopping|craft|handicraft|souvenir|pearl|bangle|saree|mall)\b',
    ).hasMatch(lower)) {
      return lower.contains('mall') ? 'mall' : 'shopping';
    }
    if (RegExp(
      r'\b(pub|bar|club|nightlife|late night|brewery|jubilee hills|banjara hills|hitec|necklace road|tank bund|durgam cheruvu|cable bridge|city lights)\b',
    ).hasMatch(lower)) {
      return 'urban';
    }
    if (RegExp(
      r'\b(lake|park|garden|forest|trail|viewpoint|sunset|sunrise|promenade)\b',
    ).hasMatch(lower)) {
      return 'nature';
    }
    if (RegExp(r'\b(museum)\b').hasMatch(lower)) return 'museum';
    if (RegExp(
      r'\b(temple|mosque|masjid|dargah|spiritual|religious)\b',
    ).hasMatch(lower)) {
      return 'spiritual';
    }
    if (RegExp(
      r'\b(fort|tomb|palace|monument|heritage|archaeological)\b',
    ).hasMatch(lower)) {
      return 'heritage';
    }
    return 'activity';
  }
}

class _ResearchPlace {
  final String title;
  final String category;
  final String sourceId;
  final String description;
  final String bestTime;
  final String timeNeeded;
  final String localTip;
  final String? warning;
  final String searchText;
  final bool vegOnly;
  final bool jainAvailable;
  final bool veganOptions;
  final bool halal;
  final bool nonVegAvailable;
  final double? lat;
  final double? lon;
  final bool structured;

  const _ResearchPlace({
    required this.title,
    required this.category,
    required this.sourceId,
    required this.description,
    required this.bestTime,
    required this.timeNeeded,
    required this.localTip,
    required this.warning,
    required this.searchText,
    required this.vegOnly,
    required this.jainAvailable,
    required this.veganOptions,
    required this.halal,
    required this.nonVegAvailable,
    required this.lat,
    required this.lon,
    required this.structured,
  });

  String get key => 'title:${_normalize(title)}';

  Set<String> get keys => {key, 'source:${sourceId.toLowerCase()}'};

  bool get isShoppingLike => category == 'shopping' || category == 'mall';

  bool get isCityLife =>
      isShoppingLike ||
      category == 'urban' ||
      category == 'cafe' ||
      searchText.contains('hitec') ||
      searchText.contains('jubilee') ||
      searchText.contains('banjara') ||
      searchText.contains('old city') ||
      searchText.contains('city lights') ||
      searchText.contains('promenade') ||
      searchText.contains('cable bridge');

  bool get isEveningLike =>
      searchText.contains('evening') ||
      searchText.contains('sunset') ||
      searchText.contains('night') ||
      searchText.contains('lights') ||
      searchText.contains('pub') ||
      searchText.contains('late');

  bool get isPhotogenic =>
      searchText.contains('view') ||
      searchText.contains('sunset') ||
      searchText.contains('sunrise') ||
      searchText.contains('photography') ||
      searchText.contains('lights') ||
      category == 'viewpoint' ||
      category == 'nature' ||
      category == 'urban';

  bool isMealEligible(_InterestProfile profile) {
    if (category != 'restaurant' && category != 'cafe') return false;
    switch (profile.dietaryPreference) {
      case 'jain':
        return jainAvailable || vegOnly;
      case 'halal':
        return halal || vegOnly;
      case 'vegan':
        return veganOptions;
      case 'veg':
        return vegOnly || !nonVegAvailable;
      default:
        return true;
    }
  }

  ItineraryStop toStopReplacing(ItineraryStop original) {
    final prefix = _isMealStop(original) ? _mealPrefix(original) : null;
    final visibleTitle = prefix == null ? title : '$prefix at $title';
    return ItineraryStop(
      time: original.time,
      title: visibleTitle,
      description: _descriptionForStop(),
      type: _typeForCategory(category, original.type),
      sourceId: sourceId,
      lat: lat,
      lon: lon,
    );
  }

  String _descriptionForStop() {
    final parts = <String>[];
    if (description.isNotEmpty) parts.add(description);
    if (bestTime.trim().isNotEmpty) parts.add('Best timing: $bestTime.');
    if (timeNeeded.trim().isNotEmpty) parts.add('Plan for $timeNeeded.');
    if (localTip.trim().isNotEmpty) parts.add('Local note: $localTip');
    if (warning != null && warning!.trim().isNotEmpty) {
      parts.add('Research note: $warning');
    }
    parts.add('Prices and timings may vary; verify before travel.');
    return _compactText(parts.join(' '), maxLength: 520);
  }
}

class _InterestProfile {
  final String normalizedInterests;
  final String dietaryPreference;
  final bool wantsShopping;
  final bool wantsNightlife;
  final bool wantsFood;
  final bool wantsHistory;
  final bool wantsSpiritual;
  final bool wantsNature;
  final bool wantsAdventure;
  final bool wantsPhotography;
  final bool wantsCity;

  const _InterestProfile({
    required this.normalizedInterests,
    required this.dietaryPreference,
    required this.wantsShopping,
    required this.wantsNightlife,
    required this.wantsFood,
    required this.wantsHistory,
    required this.wantsSpiritual,
    required this.wantsNature,
    required this.wantsAdventure,
    required this.wantsPhotography,
    required this.wantsCity,
  });

  factory _InterestProfile.fromIntake(TripIntake intake) {
    final interests = intake.interests.join(' ').toLowerCase();
    final diet = intake.dietaryPreference.toLowerCase();
    return _InterestProfile(
      normalizedInterests: interests,
      dietaryPreference: _dietaryKey(diet),
      wantsShopping: _containsAny(interests, const [
        'shopping',
        'market',
        'bazaar',
        'mall',
        'souvenir',
      ]),
      wantsNightlife: _containsAny(interests, const [
        'nightlife',
        'night',
        'pub',
        'bar',
        'club',
      ]),
      wantsFood: _containsAny(interests, const [
        'food',
        'restaurant',
        'cafe',
        'local food',
        'street food',
      ]),
      wantsHistory: _containsAny(interests, const [
        'history',
        'heritage',
        'museum',
        'monument',
      ]),
      wantsSpiritual: _containsAny(interests, const [
        'spiritual',
        'temple',
        'mosque',
        'religious',
      ]),
      wantsNature: _containsAny(interests, const [
        'nature',
        'wildlife',
        'park',
        'lake',
        'mountains',
      ]),
      wantsAdventure: _containsAny(interests, const [
        'adventure',
        'trek',
        'road trip',
      ]),
      wantsPhotography: _containsAny(interests, const [
        'photography',
        'photo',
        'views',
        'viewpoint',
      ]),
      wantsCity: _containsAny(interests, const [
        'city',
        'urban',
        'local life',
        'city life',
        'modern',
      ]),
    );
  }

  bool get hasSpecificInterests => normalizedInterests.trim().isNotEmpty;

  bool get wantsHistoryOrSpiritual => wantsHistory || wantsSpiritual;

  bool get prefersCityLife =>
      wantsShopping || wantsNightlife || wantsFood || wantsCity;

  List<String> get desiredCategories {
    final categories = <String>[];
    if (wantsShopping) categories.addAll(['shopping', 'mall']);
    if (wantsNightlife) categories.addAll(['urban', 'cafe', 'restaurant']);
    if (wantsFood) categories.addAll(['restaurant', 'cafe']);
    if (wantsCity) categories.addAll(['urban', 'shopping', 'mall', 'cafe']);
    if (wantsNature) categories.addAll(['nature', 'viewpoint']);
    if (wantsAdventure) categories.addAll(['nature', 'activity']);
    if (wantsPhotography) categories.addAll(['viewpoint', 'urban', 'nature']);
    if (wantsHistory) categories.addAll(['heritage', 'museum']);
    if (wantsSpiritual) categories.add('spiritual');
    if (categories.isEmpty) categories.add('activity');
    return categories.toSet().toList();
  }
}

Set<String> _stopKeys(ItineraryStop stop) {
  if (_isTransferOrRest(stop)) return const {};
  final keys = <String>{};
  final source = stop.sourceId.trim().toLowerCase();
  if (source.startsWith('research:')) keys.add('source:$source');
  final normalized =
      _normalize(
        stop.title,
      ).replaceFirst(RegExp(r'^(breakfast|lunch|dinner|snack) at '), '').trim();
  if (normalized.length >= 4) keys.add('title:$normalized');
  return keys;
}

String _categoryForStop(ItineraryStop stop) {
  final text = _normalize('${stop.type} ${stop.title} ${stop.description}');
  if (RegExp(
    r'\b(restaurant|lunch|dinner|breakfast|food|meal|biryani)\b',
  ).hasMatch(text)) {
    return 'restaurant';
  }
  if (RegExp(r'\b(cafe|coffee|chai|bakery|sweet|ice cream)\b').hasMatch(text)) {
    return 'cafe';
  }
  if (RegExp(r'\b(mall)\b').hasMatch(text)) return 'mall';
  if (RegExp(
    r'\b(shopping|market|bazaar|craft|pearl|bangle|souvenir)\b',
  ).hasMatch(text)) {
    return 'shopping';
  }
  if (RegExp(
    r'\b(pub|bar|club|nightlife|hitec|jubilee|banjara|durgam|necklace|tank bund|promenade|city lights|cable bridge)\b',
  ).hasMatch(text)) {
    return 'urban';
  }
  if (RegExp(r'\b(museum)\b').hasMatch(text)) return 'museum';
  if (RegExp(
    r'\b(temple|mosque|masjid|dargah|spiritual|religious)\b',
  ).hasMatch(text)) {
    return 'spiritual';
  }
  if (RegExp(
    r'\b(fort|tomb|palace|monument|heritage|archaeological)\b',
  ).hasMatch(text)) {
    return 'heritage';
  }
  if (RegExp(
    r'\b(lake|park|garden|forest|trail|sunset|sunrise|viewpoint|view)\b',
  ).hasMatch(text)) {
    return 'nature';
  }
  return 'activity';
}

bool _isMealStop(ItineraryStop stop) {
  final text = _normalize('${stop.type} ${stop.title}');
  return RegExp(
    r'\b(restaurant|breakfast|lunch|dinner|snack|meal)\b',
  ).hasMatch(text);
}

String? _mealPrefix(ItineraryStop stop) {
  final text = _normalize('${stop.type} ${stop.title} ${stop.time}');
  if (text.contains('breakfast')) return 'Breakfast';
  if (text.contains('lunch')) return 'Lunch';
  if (text.contains('dinner')) return 'Dinner';
  if (text.contains('snack')) return 'Snack';
  final minutes = _startMinutes(stop.time);
  if (minutes == null) return null;
  if (minutes >= 6 * 60 && minutes < 11 * 60) return 'Breakfast';
  if (minutes >= 11 * 60 && minutes < 16 * 60) return 'Lunch';
  if (minutes >= 16 * 60 && minutes < 18 * 60) return 'Snack';
  if (minutes >= 18 * 60 && minutes < 23 * 60) return 'Dinner';
  return null;
}

bool _isTransferOrRest(ItineraryStop stop) {
  final text = _normalize('${stop.type} ${stop.title} ${stop.description}');
  return RegExp(
    r'\b(travel|transfer|checkin|check in|checkout|check out|rest|buffer|luggage|airport|station|arrival|departure)\b',
  ).hasMatch(text);
}

bool _isGenericFiller(ItineraryStop stop) {
  final text = _normalize('${stop.title} ${stop.description}');
  return text.contains('generic') ||
      text.contains('nearby mall') ||
      text.contains('good mall') ||
      text.contains('choose a mall') ||
      text.contains('nearby cafe') ||
      text.contains('good cafe') ||
      text.contains('shopping option') ||
      text.contains('ask locally');
}

bool _looksLikeHeavySightseeing(ItineraryStop stop) {
  final text = _normalize('${stop.title} ${stop.description} ${stop.type}');
  return RegExp(
    r'\b(golconda|qutb|salar jung|chowmahalla|paigah|tomb|fort|palace|museum|temple|mandir|masjid)\b',
  ).hasMatch(text);
}

bool _isHeritageLike(String category) =>
    category == 'heritage' || category == 'museum' || category == 'spiritual';

bool _categoryMatches(String requested, String actual) {
  if (requested == actual) return true;
  if (requested == 'shopping' && actual == 'mall') return true;
  if (requested == 'urban' &&
      (actual == 'shopping' || actual == 'mall' || actual == 'cafe')) {
    return true;
  }
  if (requested == 'viewpoint' && (actual == 'nature' || actual == 'urban')) {
    return true;
  }
  return false;
}

String _typeForCategory(String category, String fallback) {
  switch (category) {
    case 'restaurant':
      return 'restaurant';
    case 'cafe':
      return 'cafe';
    case 'mall':
    case 'shopping':
      return 'shopping';
    case 'urban':
      return 'city-life';
    case 'nature':
      return 'outdoor';
    case 'museum':
      return 'museum';
    case 'spiritual':
      return 'spiritual';
    case 'heritage':
      return 'heritage';
    default:
      return fallback.trim().isEmpty ? 'activity' : fallback;
  }
}

bool _timeFits(String time, _ResearchPlace place) {
  final text = _normalize('${place.bestTime} ${place.description}');
  final minutes = _startMinutes(time);
  if (minutes == null) return false;
  if (minutes < 11 * 60) {
    return text.contains('morning') || text.contains('breakfast');
  }
  if (minutes >= 16 * 60) {
    return text.contains('evening') ||
        text.contains('sunset') ||
        text.contains('night') ||
        text.contains('dinner') ||
        text.contains('lights');
  }
  return text.contains('afternoon') || text.contains('lunch');
}

int? _startMinutes(String value) {
  final match = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  if (hour == null || hour < 1 || hour > 12) return null;
  var normalized = hour % 12;
  final suffix = (match.group(3) ?? '').toUpperCase();
  if (suffix == 'PM') normalized += 12;
  return normalized * 60 + minute;
}

bool _samePlace(String a, String b) {
  final left = _normalize(a);
  final right =
      _normalize(
        b,
      ).replaceFirst(RegExp(r'^(breakfast|lunch|dinner|snack) at '), '').trim();
  return left == right ||
      (left.length >= 4 && right.contains(left)) ||
      (right.length >= 4 && left.contains(right));
}

bool _isMallTitle(String title) {
  final normalized = _normalize(title);
  return normalized.contains(' mall') ||
      normalized.endsWith('mall') ||
      normalized.contains('galleria') ||
      normalized == 'inorbit' ||
      normalized == 'gvk one' ||
      normalized == 'forum';
}

bool _isGenericTitle(String title) {
  final normalized = _normalize(title);
  const blocked = {
    'destination',
    'restaurant',
    'restaurants',
    'mall',
    'malls',
    'market',
    'shopping',
    'option',
    'activity',
    'place',
    'location',
  };
  return normalized.length < 3 || blocked.contains(normalized);
}

String? _placeTitle(Map<String, dynamic> map) {
  for (final key in const ['name', 'mall_name', 'title', 'spot', 'area']) {
    final value = _asText(map[key]);
    if (value.isNotEmpty) return value;
  }
  return null;
}

String _firstText(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _asText(map[key]);
    if (value.isNotEmpty && value.toLowerCase() != 'false') return value;
  }
  return '';
}

String _mapText(Map<String, dynamic> map) {
  final buffer = StringBuffer();
  for (final entry in map.entries) {
    final value = entry.value;
    if (value is String) buffer.write(' ${entry.key}: $value');
    if (value is List) buffer.write(' ${value.whereType<String>().join(' ')}');
  }
  return buffer.toString();
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String _asText(Object? value) => value is String ? value.trim() : '';

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  if (value is num) return value != 0;
  return false;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _containsAny(String text, List<String> needles) {
  return needles.any(text.contains);
}

String _dietaryKey(String text) {
  if (text.contains('jain') || text.contains('satvik')) return 'jain';
  if (text.contains('halal')) return 'halal';
  if (text.contains('vegan')) return 'vegan';
  if (text.contains('veg') || text.contains('vegetarian')) return 'veg';
  return 'any';
}

String _compactText(String value, {int maxLength = 480}) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= maxLength) return text;
  return '${text.substring(0, math.min(maxLength, text.length)).trim()}...';
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('golkonda', 'golconda')
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _slug(String value) => _normalize(value).replaceAll(' ', '-');
