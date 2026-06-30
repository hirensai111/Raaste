import 'dart:math' as math;

import 'package:raaste/features/destination/domain/models/destination_guide.dart';

class LocalItineraryEditService {
  const LocalItineraryEditService();

  List<LocalTripAlternative> suggestAlternatives({
    required DestinationGuide guide,
    required Map<String, dynamic> researchContext,
    required String request,
  }) {
    final categories = _requestedCategories(request);
    final dietaryPreference = _requestedDietaryPreference(request);
    final isMallRequest = categories.contains('mall');
    final sourceMatch =
        _matchStop(guide, request) ?? _fallbackStopForRequest(guide, request);
    if (sourceMatch == null) return const [];

    final sourceStop = sourceMatch.stop;
    final sourceCategory = _categoryForText(
      '${sourceStop.title} ${sourceStop.description} ${sourceStop.type}',
      fallback: sourceStop.type,
    );
    final dedicatedRestaurantRequest =
        _isDedicatedRestaurantRequest(request) ||
        (categories.isEmpty && sourceCategory == 'restaurant');
    final ranked = <_RankedPlace>[];

    for (final option in buildCatalog(researchContext)) {
      if (_samePlace(option.title, sourceStop.title)) continue;
      if (isMallRequest && option.category != 'mall') continue;
      if (dedicatedRestaurantRequest && option.category != 'restaurant') {
        continue;
      }
      if (dietaryPreference != null &&
          _categoryMatches('restaurant', option.category) &&
          !_dietaryCompatible(option, dietaryPreference)) {
        continue;
      }

      var score = 0.0;
      if (categories.isEmpty) {
        score += _categoryMatches(sourceCategory, option.category) ? 48 : 8;
      } else {
        for (final category in categories) {
          if (_categoryMatches(category, option.category)) {
            score += 90;
          } else if (_optionText(option).contains(category)) {
            score += 20;
          }
        }
      }

      if (option.isStructured) score += 20;
      if (dedicatedRestaurantRequest && option.category == 'restaurant') {
        score += 70;
      }
      if (dietaryPreference != null) {
        score += _dietaryRankBoost(option, dietaryPreference);
      }
      if (isMallRequest) {
        score += 120 + _mallRankBoost(option.title);
      } else if (option.warning != null) {
        score -= 16;
      }
      if (_isShoppingRequest(request) && !isMallRequest) {
        final title = _normalize(option.title);
        if (title == 'shilparamam') score += 32;
        if (title == 'laad bazaar') score += 24;
        if (option.category == 'mall') score += 12;
      }
      if (score > 0) ranked.add(_RankedPlace(option, score));
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(4).map((rankedOption) {
      final option = rankedOption.option;
      return LocalTripAlternative(
        title: option.title,
        reason: _alternativeReason(option),
        editRequest: 'Replace ${sourceStop.title} with ${option.title}.',
        option: option,
        applyLocally: true,
      );
    }).toList();
  }

  LocalGuideEditResult? applyDirectEdit({
    required DestinationGuide guide,
    required Map<String, dynamic> researchContext,
    required String request,
  }) {
    if (_requiresRouteOrTimingReasoning(request)) return null;

    final phrase = _replacementPhrase(request);
    if (phrase == null || _isGenericCategoryPhrase(phrase)) return null;

    final option = _matchOption(buildCatalog(researchContext), phrase);
    if (option == null) return null;

    return applySelectedAlternative(
      guide: guide,
      request: request,
      option: option,
    );
  }

  LocalGuideEditResult? applySelectedAlternative({
    required DestinationGuide guide,
    required String request,
    required ResearchPlaceOption option,
  }) {
    final sourceMatch =
        _matchStop(guide, request) ?? _fallbackStopForRequest(guide, request);
    if (sourceMatch == null) return null;

    final oldStop = sourceMatch.stop;
    final replacement = ItineraryStop(
      time: oldStop.time,
      title: option.title,
      description: _stopDescription(option),
      type: _stopType(option),
      sourceId: option.sourceId,
      lat: option.lat,
      lon: option.lon,
    );

    final days = <ItineraryDay>[];
    for (var dayIndex = 0; dayIndex < guide.itineraryDays.length; dayIndex++) {
      final day = guide.itineraryDays[dayIndex];
      if (dayIndex != sourceMatch.dayIndex) {
        days.add(day);
        continue;
      }

      final stops = <ItineraryStop>[];
      for (var stopIndex = 0; stopIndex < day.stops.length; stopIndex++) {
        stops.add(
          stopIndex == sourceMatch.stopIndex
              ? replacement
              : day.stops[stopIndex],
        );
      }
      days.add(
        ItineraryDay(
          dayNumber: day.dayNumber,
          title: day.title,
          subtitle: day.subtitle,
          stops: stops,
        ),
      );
    }

    return LocalGuideEditResult(
      guide: guide.copyWith(itineraryDays: days, updatedAt: DateTime.now()),
      message:
          'Done. I replaced ${oldStop.title} with ${option.title} using the saved trip research.',
    );
  }

  List<ResearchPlaceOption> buildCatalog(Map<String, dynamic> researchContext) {
    final options = <ResearchPlaceOption>[];
    _collectStructured(
      _asMap(researchContext['research']),
      'research',
      options,
    );
    _collectStructured(
      _asMap(researchContext['restaurantResearch']),
      'restaurantResearch',
      options,
    );
    _collectTextMentions(
      _asMap(researchContext['research']),
      'research',
      options,
    );
    _collectTextMentions(
      _asMap(researchContext['restaurantResearch']),
      'restaurantResearch',
      options,
    );
    return _dedupeOptions(options);
  }

  void _collectStructured(
    Object? value,
    String path,
    List<ResearchPlaceOption> options,
  ) {
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final item = value[i];
        if (_isMallPath(path) && item is String) {
          options.add(
            _optionFromTextMention(
              item,
              'Mall listed in saved research.',
              path,
            ),
          );
        }
        _collectStructured(item, '$path[$i]', options);
      }
      return;
    }

    final map = _asMap(value);
    if (map.isEmpty) return;

    final title = _placeTitle(map);
    if (title != null && _looksLikePlaceMap(map, path)) {
      options.add(_optionFromMap(title, map, path));
    }

    for (final entry in map.entries) {
      _collectStructured(entry.value, '$path.${entry.key}', options);
    }
  }

  ResearchPlaceOption _optionFromMap(
    String title,
    Map<String, dynamic> map,
    String path,
  ) {
    final text = _mapText(map);
    final category = _categoryForPlace(
      title: title,
      path: path,
      text: text,
      fallback: _asText(map['type']),
    );
    final coordinates = _asMap(map['coordinates']);
    final location = _asMap(map['location']);
    final dietaryTags = _asMap(map['dietary_tags']);
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
      'why',
      'speciality',
      'reason',
    ]);
    return ResearchPlaceOption(
      title: title,
      category: category,
      sourceId: 'research:$path:${_slug(title)}',
      description: description,
      bestTime: _asText(map['best_time_to_visit']),
      timeNeeded: _asText(map['time_needed']),
      localTip: _asText(map['local_tip']),
      warning: warning.isEmpty ? null : warning,
      vegOnly: _asBool(dietaryTags['veg_only']),
      jainAvailable: _asBool(dietaryTags['jain_available']),
      veganOptions: _asBool(dietaryTags['vegan_options']),
      halal: _asBool(dietaryTags['halal']),
      nonVegAvailable: _asBool(dietaryTags['non_veg_available']),
      lat: _asDouble(coordinates['lat']) ?? _asDouble(location['lat']),
      lon:
          _asDouble(coordinates['lon']) ??
          _asDouble(coordinates['lng']) ??
          _asDouble(location['lon']) ??
          _asDouble(location['lng']),
      isStructured: true,
    );
  }

  void _collectTextMentions(
    Object? value,
    String path,
    List<ResearchPlaceOption> options,
  ) {
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _collectTextMentions(value[i], '$path[$i]', options);
      }
      return;
    }

    final map = _asMap(value);
    if (map.isNotEmpty) {
      for (final entry in map.entries) {
        _collectTextMentions(entry.value, '$path.${entry.key}', options);
      }
      return;
    }

    final text = _asText(value);
    if (text.isEmpty) return;

    for (final entry in _knownMallMentions.entries) {
      if (!text.toLowerCase().contains(entry.key.toLowerCase())) continue;
      options.add(_optionFromTextMention(entry.value, text, path));
    }

    final matches = RegExp(
      r"\b([A-Z][A-Za-z&.'-]+(?:\s+[A-Z][A-Za-z&.'-]+){0,4}\s+(?:Mall|Market|Bazaar|Galleria))\b",
    ).allMatches(text);
    for (final match in matches) {
      final title = match.group(1)?.trim();
      if (title == null || title.isEmpty) continue;
      options.add(_optionFromTextMention(title, text, path));
    }
  }

  ResearchPlaceOption _optionFromTextMention(
    String title,
    String text,
    String path,
  ) {
    final cleanTitle = title.replaceFirst(
      RegExp(r'\s+malls?$', caseSensitive: false),
      ' Mall',
    );
    final hasWarning = RegExp(
      r'\b(trap|overpriced|avoid|charge|inflated|mediocre)\b',
      caseSensitive: false,
    ).hasMatch(text);
    return ResearchPlaceOption(
      title: cleanTitle,
      category: _isMallTitle(cleanTitle) ? 'mall' : 'shopping',
      sourceId: 'research:$path:${_slug(cleanTitle)}',
      description: _compactText(text),
      bestTime: '',
      timeNeeded: '',
      localTip: '',
      warning: hasWarning ? _compactText(text) : null,
      vegOnly: false,
      jainAvailable: false,
      veganOptions: false,
      halal: false,
      nonVegAvailable: false,
      lat: null,
      lon: null,
      isStructured: false,
    );
  }

  List<ResearchPlaceOption> _dedupeOptions(List<ResearchPlaceOption> options) {
    final byTitle = <String, ResearchPlaceOption>{};
    for (final option in options) {
      final key = _normalize(option.title);
      if (key.length < 3 || _isGenericTitle(option.title)) continue;
      final existing = byTitle[key];
      if (existing == null ||
          (!existing.isStructured && option.isStructured) ||
          (existing.category != 'mall' && option.category == 'mall') ||
          option.description.length > existing.description.length) {
        byTitle[key] = option;
      }
    }
    final deduped = byTitle.values.toList();
    deduped.sort((a, b) {
      if (a.category != b.category) {
        if (a.category == 'mall') return -1;
        if (b.category == 'mall') return 1;
      }
      if (a.isStructured != b.isStructured) return a.isStructured ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return deduped;
  }

  _StopMatch? _matchStop(DestinationGuide guide, String request) {
    final phrase = _sourcePhrase(request) ?? request;
    final ranked = <_RankedStop>[];
    for (var dayIndex = 0; dayIndex < guide.itineraryDays.length; dayIndex++) {
      final day = guide.itineraryDays[dayIndex];
      for (var stopIndex = 0; stopIndex < day.stops.length; stopIndex++) {
        final stop = day.stops[stopIndex];
        final score = _stopScore(phrase, request, stop);
        if (score > 0) {
          ranked.add(
            _RankedStop(
              _StopMatch(dayIndex: dayIndex, stopIndex: stopIndex, stop: stop),
              score,
            ),
          );
        }
      }
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty || ranked.first.score < 42) return null;
    if (ranked.length > 1 && ranked.first.score - ranked[1].score < 7) {
      return null;
    }
    return ranked.first.match;
  }

  _StopMatch? _fallbackStopForRequest(DestinationGuide guide, String request) {
    final categories = _requestedCategories(request);
    if (categories.isEmpty) return null;

    final ranked = <_RankedStop>[];
    for (var dayIndex = 0; dayIndex < guide.itineraryDays.length; dayIndex++) {
      final day = guide.itineraryDays[dayIndex];
      for (var stopIndex = 0; stopIndex < day.stops.length; stopIndex++) {
        final stop = day.stops[stopIndex];
        final text = _normalize(
          '${stop.title} ${stop.description} ${stop.type}',
        );
        final category = _categoryForText(text, fallback: stop.type);
        var score = 0.0;
        for (final requested in categories) {
          if (_categoryMatches(requested, category)) score += 42;
          if (text.contains(requested)) score += 30;
        }
        if (_isGenericEditStop(stop)) score += 35;
        if (text.contains('mall time')) score += 50;
        if (score > 0) {
          ranked.add(
            _RankedStop(
              _StopMatch(dayIndex: dayIndex, stopIndex: stopIndex, stop: stop),
              score,
            ),
          );
        }
      }
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty || ranked.first.score < 35) return null;
    if (ranked.length > 1 && ranked.first.score - ranked[1].score < 10) {
      return null;
    }
    return ranked.first.match;
  }

  double _stopScore(String phrase, String request, ItineraryStop stop) {
    final normalizedPhrase = _normalize(phrase);
    final normalizedRequest = _normalize(request);
    final title = _normalize(stop.title);
    final source = _normalize(stop.sourceId);
    final text = _normalize('${stop.title} ${stop.description} ${stop.type}');

    var score = _textScore(normalizedPhrase, title) * 100;
    if (normalizedRequest.contains(title) && title.length >= 4) score += 55;
    if (source.isNotEmpty && normalizedRequest.contains(source)) score += 35;
    if (_hasUsefulTimeOverlap(normalizedPhrase, stop.time)) score += 70;
    if (normalizedPhrase.contains('mall') && text.contains('mall')) score += 85;
    if (normalizedPhrase.contains('shopping') && text.contains('shopping')) {
      score += 55;
    }
    score += _tokenOverlapScore(normalizedPhrase, text) * 30;
    return score;
  }

  ResearchPlaceOption? _matchOption(
    List<ResearchPlaceOption> catalog,
    String phrase,
  ) {
    final normalizedPhrase = _normalize(phrase);
    final ranked = <_RankedPlace>[];
    for (final option in catalog) {
      final title = _normalize(option.title);
      var score = _textScore(normalizedPhrase, title) * 100;
      score += _tokenOverlapScore(normalizedPhrase, _optionText(option)) * 22;
      if (normalizedPhrase.contains(title) && title.length >= 4) score += 45;
      if (option.isStructured) score += 6;
      if (score > 0) ranked.add(_RankedPlace(option, score));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty || ranked.first.score < 62) return null;
    if (ranked.length > 1 && ranked.first.score - ranked[1].score < 5) {
      return null;
    }
    return ranked.first.option;
  }

  String? _sourcePhrase(String request) {
    final editVerb =
        r'(?:replace|swap|change|edit|update|modify|switch|substitute|turn)';
    final patterns = [
      RegExp(
        r'\b' + editVerb + r'\s+(?:the\s+)?(.+?)\s+(?:with|to|for|into)\s+',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:instead of|in place of)\s+(.+?)(?:$|[,.])',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:alternatives?|options?)\s+(?:to|for)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:show|suggest|find|give me)\s+.+\s+(?:to|for)\s+(.+)$',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(request);
      final value = match?.group(1);
      if (value != null && value.trim().isNotEmpty) return _cleanPhrase(value);
    }
    return null;
  }

  String? _replacementPhrase(String request) {
    final editVerb =
        r'(?:replace|swap|change|edit|update|modify|switch|substitute|turn)';
    final patterns = [
      RegExp(
        r'\b' + editVerb + r'\s+.+?\s+(?:with|to|for|into)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:use|put|add|try|choose)\s+(.+?)\s+(?:instead of|in place of)\s+',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:can we|please|pls)?\s*(?:use|put|add|try|choose)\s+(.+)$',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(request);
      final value = match?.group(1);
      if (value != null && value.trim().isNotEmpty) return _cleanPhrase(value);
    }
    return null;
  }

  Set<String> _requestedCategories(String request) {
    final lower = request.toLowerCase();
    final categories = <String>{};
    if (RegExp(r'\b(mall|malls)\b').hasMatch(lower)) categories.add('mall');
    if (RegExp(
      r'\b(shopping|shop|shops|market|markets|bazaar|craft|souvenir)\b',
    ).hasMatch(lower)) {
      categories.add('shopping');
    }
    if (RegExp(
      r'\b(restaurant|restaurants|restraunt|restraunts|resturant|resturants|lunch|dinner|breakfast|food|biryani|meal|eatery|eateries|dining)\b',
    ).hasMatch(lower)) {
      categories.add('restaurant');
    }
    if (RegExp(r'\b(cafe|cafes|coffee|chai|bakery)\b').hasMatch(lower)) {
      categories.add('cafe');
    }
    if (RegExp(r'\b(fort|tomb|palace|heritage|museum)\b').hasMatch(lower)) {
      categories.add('heritage');
    }
    if (RegExp(
      r'\b(temple|mosque|masjid|spiritual|religious)\b',
    ).hasMatch(lower)) {
      categories.add('spiritual');
    }
    if (RegExp(r'\b(park|lake|garden|nature|viewpoint)\b').hasMatch(lower)) {
      categories.add('nature');
    }
    return categories;
  }

  bool _isGenericCategoryPhrase(String phrase) {
    var text = _normalize(phrase);
    text =
        text
            .replaceAll(
              RegExp(r'\b(a|an|some|any|one|good|nice|nearby|best|the)\b'),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (text.isEmpty) return true;
    const generic = {
      'mall',
      'malls',
      'cafe',
      'cafes',
      'restaurant',
      'restaurants',
      'restraunt',
      'restraunts',
      'resturant',
      'resturants',
      'market',
      'markets',
      'shopping',
      'shop',
      'shops',
      'place',
      'activity',
      'attraction',
      'park',
      'museum',
      'temple',
      'option',
      'options',
    };
    return generic.contains(text) || text.endsWith(' option');
  }

  String? _requestedDietaryPreference(String request) {
    final lower = request.toLowerCase();
    if (RegExp(
      r'\b(jain|satvik|satvic|no onion|no garlic)\b',
    ).hasMatch(lower)) {
      return 'jain';
    }
    if (RegExp(r'\b(vegan|plant based|plant-based)\b').hasMatch(lower)) {
      return 'vegan';
    }
    if (RegExp(
      r'\b(veg|vegetarian|pure veg|pure vegetarian)\b',
    ).hasMatch(lower)) {
      return 'veg';
    }
    if (RegExp(r'\b(halal)\b').hasMatch(lower)) return 'halal';
    return null;
  }

  bool _isDedicatedRestaurantRequest(String request) {
    final lower = request.toLowerCase();
    final asksForDining = RegExp(
      r'\b(restaurant|restaurants|restraunt|restraunts|resturant|resturants|dining|eatery|eateries|lunch|dinner|meal)\b',
    ).hasMatch(lower);
    final asksForSnackOrCafe = RegExp(
      r'\b(cafe|cafes|coffee|chai|tea|bakery|bakeries|sweet|sweets|dessert|ice cream|snack)\b',
    ).hasMatch(lower);
    return asksForDining && !asksForSnackOrCafe;
  }

  bool _dietaryCompatible(ResearchPlaceOption option, String preference) {
    switch (preference) {
      case 'veg':
        return option.vegOnly || !option.nonVegAvailable;
      case 'jain':
        return option.jainAvailable || option.vegOnly;
      case 'vegan':
        return option.veganOptions;
      case 'halal':
        return option.halal || option.vegOnly;
      default:
        return true;
    }
  }

  double _dietaryRankBoost(ResearchPlaceOption option, String preference) {
    if (!_categoryMatches('restaurant', option.category)) return 0;
    switch (preference) {
      case 'veg':
        if (option.vegOnly) return 130;
        if (!option.nonVegAvailable) return 100;
        return 0;
      case 'jain':
        if (option.jainAvailable) return 140;
        if (option.vegOnly) return 55;
        return 0;
      case 'vegan':
        return option.veganOptions ? 130 : 0;
      case 'halal':
        return option.halal ? 100 : 0;
      default:
        return 0;
    }
  }

  String _dietaryLabel(ResearchPlaceOption option) {
    if (option.jainAvailable && option.veganOptions && option.vegOnly) {
      return 'Pure veg with Jain and vegan options.';
    }
    if (option.jainAvailable && option.vegOnly) {
      return 'Pure veg with Jain options.';
    }
    if (option.veganOptions && option.vegOnly) {
      return 'Pure veg with vegan options.';
    }
    if (option.vegOnly) return 'Pure vegetarian.';
    if (option.veganOptions) return 'Vegan options available.';
    if (option.jainAvailable) return 'Jain options available.';
    if (option.halal) return 'Halal-friendly.';
    return '';
  }

  bool _requiresRouteOrTimingReasoning(String request) {
    return RegExp(
      r'\b(retime|move|optimi[sz]e|route|less tiring|easier|slower|faster|rearrange|rebuild|whole day|entire day)\b',
      caseSensitive: false,
    ).hasMatch(request);
  }

  String _stopDescription(ResearchPlaceOption option) {
    final parts = <String>[];
    if (option.description.isNotEmpty) {
      parts.add(option.description);
    }
    if (option.bestTime.isNotEmpty) {
      parts.add('Best timing: ${option.bestTime}.');
    }
    if (option.timeNeeded.isNotEmpty) {
      parts.add('Plan for ${option.timeNeeded}.');
    }
    if (option.localTip.isNotEmpty) {
      parts.add('Local note: ${option.localTip}');
    }
    final dietary = _dietaryLabel(option);
    if (dietary.isNotEmpty) {
      parts.add('Dietary note: $dietary');
    }
    if (option.warning != null && option.warning!.isNotEmpty) {
      parts.add('Research note: ${option.warning}');
    }
    parts.add(
      'Kept in the original itinerary slot; verify current prices and timings before travel.',
    );
    return _compactText(parts.join(' '), maxLength: 520);
  }

  String _alternativeReason(ResearchPlaceOption option) {
    final pieces = <String>[];
    if (option.description.isNotEmpty) {
      pieces.add(option.description);
    }
    if (option.bestTime.isNotEmpty) {
      pieces.add('Best timing: ${option.bestTime}.');
    }
    final dietary = _dietaryLabel(option);
    if (dietary.isNotEmpty) {
      pieces.add(dietary);
    }
    if (option.warning != null && option.warning!.isNotEmpty) {
      pieces.add('Research note: ${option.warning}');
    }
    return _compactText(pieces.join(' '), maxLength: 240);
  }

  String _stopType(ResearchPlaceOption option) {
    switch (option.category) {
      case 'restaurant':
      case 'cafe':
        return option.category;
      case 'shopping':
      case 'mall':
        return 'shopping';
      case 'heritage':
        return 'sightseeing';
      case 'spiritual':
        return 'temple';
      case 'nature':
        return 'outdoor';
      default:
        return 'activity';
    }
  }

  String _categoryForPlace({
    required String title,
    required String path,
    required String text,
    required String fallback,
  }) {
    final lowerPath = path.toLowerCase();
    if (_isMallPath(lowerPath) || _isMallTitle(title)) return 'mall';
    final typedCategory = _categoryForKnownType(fallback);
    if (typedCategory != null) return typedCategory;
    return _categoryForText('$title $text', fallback: fallback);
  }

  String? _categoryForKnownType(String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return null;
    if (normalized.contains('street') ||
        normalized.contains('stall') ||
        normalized.contains('bandi') ||
        normalized.contains('cart') ||
        normalized.contains('fast food') ||
        normalized.contains('snack')) {
      return 'cafe';
    }
    if (normalized == 'restaurant' ||
        normalized.contains('restaurant') ||
        normalized.contains('dining') ||
        normalized.contains('dhaba')) {
      return 'restaurant';
    }
    if (normalized.contains('cafe') ||
        normalized.contains('coffee') ||
        normalized.contains('bakery') ||
        normalized.contains('baker') ||
        normalized.contains('sweet') ||
        normalized.contains('mithai') ||
        normalized.contains('dessert') ||
        normalized.contains('ice cream')) {
      return 'cafe';
    }
    if (normalized.contains('mall')) return 'mall';
    if (normalized.contains('market') || normalized.contains('shopping')) {
      return 'shopping';
    }
    return null;
  }

  String _categoryForText(String text, {String fallback = ''}) {
    final lower = '$text $fallback'.toLowerCase();
    if (RegExp(r'\b(cafe|coffee|chai|bakery)\b').hasMatch(lower)) return 'cafe';
    if (RegExp(
      r'\b(restaurant|biryani|meal|food|cuisine|dish|thali)\b',
    ).hasMatch(lower)) {
      return 'restaurant';
    }
    if (RegExp(r'\b(mall|malls|galleria)\b').hasMatch(lower)) return 'mall';
    if (RegExp(
      r'\b(shopping|shop|market|bazaar|craft|handicraft|souvenir|saree|bangle|pearl)\b',
    ).hasMatch(lower)) {
      return 'shopping';
    }
    if (RegExp(
      r'\b(fort|tomb|palace|museum|heritage|archaeological)\b',
    ).hasMatch(lower)) {
      return 'heritage';
    }
    if (RegExp(
      r'\b(temple|mosque|masjid|dargah|spiritual|religious)\b',
    ).hasMatch(lower)) {
      return 'spiritual';
    }
    if (RegExp(
      r'\b(park|lake|garden|viewpoint|waterfall|trek|hill|nature)\b',
    ).hasMatch(lower)) {
      return 'nature';
    }
    return fallback.trim().isEmpty ? 'activity' : _normalize(fallback);
  }

  bool _categoryMatches(String requested, String actual) {
    if (requested == actual) return true;
    if (requested == 'shopping' && (actual == 'market' || actual == 'mall')) {
      return true;
    }
    if (requested == 'restaurant' && actual == 'cafe') return true;
    if (requested == 'heritage' && actual == 'sightseeing') return true;
    return false;
  }

  bool _isShoppingRequest(String request) {
    final categories = _requestedCategories(request);
    return categories.contains('shopping') || categories.contains('mall');
  }

  bool _looksLikePlaceMap(Map<String, dynamic> map, String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.destination') ||
        lowerPath.contains('data_quality')) {
      return false;
    }
    if (_isGenericTitle(_placeTitle(map) ?? '')) return false;
    if (_isMallPath(lowerPath)) return true;
    const placeFields = [
      'description',
      'why_worth_it',
      'why_hidden',
      'best_time_to_visit',
      'local_tip',
      'coordinates',
      'how_to_get_there',
      'cuisine',
      'speciality',
      'location',
      'raaste_recommendation_reason',
      'reason',
    ];
    return placeFields.any(map.containsKey);
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
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _mapText(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    for (final value in map.values) {
      if (value is String) buffer.write(' $value');
    }
    return buffer.toString();
  }

  String _optionText(ResearchPlaceOption option) {
    return _normalize(
      '${option.title} ${option.category} ${option.description} ${option.localTip} ${option.warning ?? ''}',
    );
  }

  bool _samePlace(String a, String b) {
    final left = _normalize(a);
    final right = _normalize(b);
    return left == right ||
        (left.length >= 4 && right.contains(left)) ||
        (right.length >= 4 && left.contains(right));
  }

  bool _isGenericTitle(String title) {
    final normalized = _normalize(title);
    if (normalized.length < 3) return true;
    const blocked = {
      'destination',
      'restaurant',
      'restaurants',
      'restraunt',
      'restraunts',
      'resturant',
      'resturants',
      'mall',
      'malls',
      'market',
      'shopping',
      'option',
      'activity',
      'place',
    };
    return blocked.contains(normalized);
  }

  bool _isGenericEditStop(ItineraryStop stop) {
    final text = _normalize('${stop.title} ${stop.description} ${stop.type}');
    return text.contains('generic') ||
        text.contains('mall time') ||
        text.contains('shopping option') ||
        text.contains('choose a mall') ||
        text.contains('nearby mall') ||
        text.contains('good mall');
  }

  bool _isMallPath(String path) {
    final lower = path.toLowerCase();
    return lower.split(RegExp(r'[.\[\]]+')).contains('malls') ||
        lower.contains('shopping_malls') ||
        lower.contains('mall_options');
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

  double _mallRankBoost(String title) {
    switch (_normalize(title)) {
      case 'inorbit mall':
        return 30;
      case 'gvk one mall':
        return 24;
      case 'forum mall':
      case 'forum sujana mall':
        return 18;
      default:
        return 0;
    }
  }

  bool _hasUsefulTimeOverlap(String phrase, String stopTime) {
    final phraseTokens = _tokens(phrase);
    if (!phraseTokens.contains('am') && !phraseTokens.contains('pm')) {
      return false;
    }
    final stopTokens = _tokens(stopTime);
    return phraseTokens.intersection(stopTokens).length >= 2;
  }

  double _textScore(String query, String candidate) {
    if (query.isEmpty || candidate.isEmpty) return 0;
    if (query == candidate) return 1;
    if (query.contains(candidate) || candidate.contains(query)) return 0.86;
    final overlap = _tokenOverlapScore(query, candidate);
    final distanceRatio =
        1 -
        (_levenshtein(query, candidate) /
            math.max(query.length, candidate.length));
    return math.max(overlap, distanceRatio * 0.78);
  }

  double _tokenOverlapScore(String a, String b) {
    final left = _tokens(a);
    final right = _tokens(b);
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    return (2 * intersection) / (left.length + right.length);
  }

  Set<String> _tokens(String value) {
    return _normalize(
      value,
    ).split(RegExp(r'\s+')).where((token) => token.length > 1).toSet();
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        );
      }
      previous = current;
    }
    return previous[b.length];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
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

  String _cleanPhrase(String value) {
    return value
        .replaceAll(RegExp(r'\b(the|a|an)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.?!,]+$'), '')
        .trim();
  }

  String _compactText(String value, {int maxLength = 280}) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength).trim()}...';
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

  String _slug(String value) => _normalize(value).replaceAll(' ', '_');

  static const _knownMallMentions = {
    'Inorbit': 'Inorbit Mall',
    'GVK One': 'GVK One Mall',
    'Forum': 'Forum Mall',
  };
}

class LocalGuideEditResult {
  final DestinationGuide guide;
  final String message;

  const LocalGuideEditResult({required this.guide, required this.message});
}

class LocalTripAlternative {
  final String title;
  final String reason;
  final String editRequest;
  final ResearchPlaceOption? option;
  final bool applyLocally;

  const LocalTripAlternative({
    required this.title,
    required this.reason,
    required this.editRequest,
    required this.option,
    required this.applyLocally,
  });
}

class ResearchPlaceOption {
  final String title;
  final String category;
  final String sourceId;
  final String description;
  final String bestTime;
  final String timeNeeded;
  final String localTip;
  final String? warning;
  final bool vegOnly;
  final bool jainAvailable;
  final bool veganOptions;
  final bool halal;
  final bool nonVegAvailable;
  final double? lat;
  final double? lon;
  final bool isStructured;

  const ResearchPlaceOption({
    required this.title,
    required this.category,
    required this.sourceId,
    required this.description,
    required this.bestTime,
    required this.timeNeeded,
    required this.localTip,
    required this.warning,
    required this.vegOnly,
    required this.jainAvailable,
    required this.veganOptions,
    required this.halal,
    required this.nonVegAvailable,
    required this.lat,
    required this.lon,
    required this.isStructured,
  });
}

class _StopMatch {
  final int dayIndex;
  final int stopIndex;
  final ItineraryStop stop;

  const _StopMatch({
    required this.dayIndex,
    required this.stopIndex,
    required this.stop,
  });
}

class _RankedStop {
  final _StopMatch match;
  final double score;

  const _RankedStop(this.match, this.score);
}

class _RankedPlace {
  final ResearchPlaceOption option;
  final double score;

  const _RankedPlace(this.option, this.score);
}
