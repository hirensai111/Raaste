import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class DestinationResearchService {
  static const _assets = <_ResearchAsset>[
    _ResearchAsset(
      sourceId: 'hyderabad',
      name: 'Hyderabad',
      state: 'Telangana',
      tagline: 'Nizami heritage, biryani, bazaars, and modern city energy.',
      assetPath: 'assets/research/hyderabad_raaste_research.json',
      restaurantAssetPath: 'assets/research/hyderabad_raaste_restaurants.json',
      matchTerms: ['hyderabad', 'secunderabad'],
      lat: 17.3850,
      lon: 78.4867,
    ),
    _ResearchAsset(
      sourceId: 'lonavala',
      name: 'Lonavala',
      state: 'Maharashtra',
      tagline: 'Misty ghats, monsoon viewpoints, forts, and chikki stops.',
      assetPath: 'assets/research/lonavala_raaste_research.json',
      restaurantAssetPath: 'assets/research/lonavala_raaste_restaurants.json',
      matchTerms: ['lonavala', 'khandala', 'pawna', 'karla'],
      lat: 18.7546,
      lon: 73.4062,
    ),
    _ResearchAsset(
      sourceId: 'varanasi',
      name: 'Varanasi',
      state: 'Uttar Pradesh',
      tagline: 'Ghats, temples, old-city lanes, rituals, and timeless food.',
      assetPath: 'assets/research/varanasi_raaste_research.json',
      restaurantAssetPath: 'assets/research/varanasi_raaste_restaurants.json',
      matchTerms: ['varanasi', 'banaras', 'benares', 'kashi'],
      lat: 25.3176,
      lon: 82.9739,
    ),
  ];

  final AssetBundle _bundle;

  DestinationResearchService({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  List<PlaceSuggestion> availableDestinations() {
    return _assets.map((asset) => asset.toSuggestion()).toList();
  }

  List<String> matchTermsFor(String sourceId) {
    final normalized = sourceId.trim().toLowerCase();
    for (final asset in _assets) {
      if (asset.sourceId == normalized) return asset.matchTerms;
    }
    return const [];
  }

  Future<DestinationResearch?> loadForIntake(TripIntake intake) async {
    final sourceId = intake.sourceId.trim().toLowerCase();
    for (final asset in _assets) {
      if (asset.sourceId == sourceId) return _load(asset);
    }

    final destinationText =
        [intake.destination, intake.displayAddress].join(' ').toLowerCase();

    for (final asset in _assets) {
      if (!_matches(asset, destinationText)) continue;

      final research = await _load(asset);
      if (research != null) return research;
    }

    return null;
  }

  bool _matches(_ResearchAsset asset, String text) {
    return asset.matchTerms.any(text.contains);
  }

  Future<DestinationResearch?> _load(_ResearchAsset asset) async {
    try {
      final raw = await _bundle.loadString(asset.assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final restaurantData = await _loadRestaurantResearch(asset);
      final destination = decoded['destination'];
      final destinationName =
          destination is Map<String, dynamic>
              ? destination['name'] as String? ?? asset.name
              : asset.name;

      return DestinationResearch(
        destinationName: destinationName,
        sourceId: asset.sourceId,
        assetPath: asset.assetPath,
        data: decoded,
        restaurantAssetPath: asset.restaurantAssetPath,
        restaurantData: restaurantData,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadRestaurantResearch(
    _ResearchAsset asset,
  ) async {
    final path = asset.restaurantAssetPath;
    if (path == null) return null;

    try {
      final raw = await _bundle.loadString(path);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _compactRestaurantResearch(decoded);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _compactRestaurantResearch(
    Map<String, dynamic> decoded,
  ) {
    return {
      'destination': decoded['destination'],
      'food_overview': decoded['food_overview'],
      'street_food_guide': decoded['street_food_guide'],
      'dietary_specific_guides': decoded['dietary_specific_guides'],
      'meal_planning_guide': decoded['meal_planning_guide'],
      'budget_meal_planning': decoded['budget_meal_planning'],
      'what_to_bring_home': decoded['what_to_bring_home'],
      'data_quality': decoded['data_quality'],
      'restaurants': _compactRestaurants(decoded['restaurants']),
    };
  }

  List<Map<String, dynamic>> _compactRestaurants(Object? value) {
    final items = value is List ? value : const [];
    return items.whereType<Map>().map((raw) {
      final json = Map<String, dynamic>.from(raw);
      final location = _map(json['location']);
      final practical = _map(json['practical']);
      return {
        'name': json['name'],
        'type': json['type'],
        'cuisine': json['cuisine'],
        'speciality': json['speciality'],
        'dietary_tags': _map(json['dietary_tags']),
        'price_range': json['price_range'],
        'price_for_two': json['price_for_two'],
        'signature_dishes': _compactSignatureDishes(json['signature_dishes']),
        'best_time_to_visit': json['best_time_to_visit'],
        'avoid_when': json['avoid_when'],
        'wait_time_reality': json['wait_time_reality'],
        'local_tip': json['local_tip'],
        'tourist_trap_warning': json['tourist_trap_warning'],
        'tourist_trap_detail': json['tourist_trap_detail'],
        'known_for_since': json['known_for_since'],
        'location': {
          'area': location['area'],
          'landmark': location['landmark'],
          'address': location['address'],
          'distance_from_center': location['distance_from_center'],
          'google_maps_searchable':
              location['google_maps_searchable'] ??
              location['google_maps_query'],
        },
        'practical': {
          'cash_only': practical['cash_only'],
          'upi_accepted': practical['upi_accepted'],
          'reservation_required': practical['reservation_required'],
          'reservation_note': practical['reservation_note'],
          'parking': practical['parking'],
          'seating': practical['seating'],
          'ac_available': practical['ac_available'],
        },
        'rating_signals': _compactRatingSignals(json['rating_signals']),
        'raaste_recommendation_reason': json['raaste_recommendation_reason'],
        'best_for': json['best_for'],
      };
    }).toList();
  }

  Map<String, dynamic> _compactRatingSignals(Object? value) {
    final rating = _map(value);
    return {
      'zomato_rating': rating['zomato_rating'],
      'google_rating': rating['google_rating'],
      'review_count_approximate': rating['review_count_approximate'],
      'mentioned_in_sources': rating['mentioned_in_sources'],
    };
  }

  List<Map<String, dynamic>> _compactSignatureDishes(Object? value) {
    final items = value is List ? value : const [];
    return items.whereType<Map>().take(4).map((raw) {
      final dish = Map<String, dynamic>.from(raw);
      return {
        'dish': dish['dish'],
        'description': dish['description'] ?? dish['context'],
        'price': dish['price'],
      };
    }).toList();
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}

class _ResearchAsset {
  final String sourceId;
  final String name;
  final String state;
  final String tagline;
  final String assetPath;
  final String? restaurantAssetPath;
  final List<String> matchTerms;
  final double lat;
  final double lon;

  const _ResearchAsset({
    required this.sourceId,
    required this.name,
    required this.state,
    required this.tagline,
    required this.assetPath,
    this.restaurantAssetPath,
    required this.matchTerms,
    required this.lat,
    required this.lon,
  });

  PlaceSuggestion toSuggestion() {
    return PlaceSuggestion.curated(
      sourceId: sourceId,
      name: name,
      state: state,
      tagline: tagline,
      lat: lat,
      lon: lon,
    );
  }
}
