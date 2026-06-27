class RestaurantRecommendation {
  final String id;
  final String name;
  final String type;
  final String cuisine;
  final String speciality;
  final String description;
  final String knownForSince;
  final bool isVegOnly;
  final bool jainAvailable;
  final bool halalCertified;
  final bool veganOptions;
  final bool nonVegAvailable;
  final String priceRange;
  final String priceForTwo;
  final String area;
  final String landmark;
  final String address;
  final String distanceFromCenter;
  final String googleMapsQuery;
  final bool cashOnly;
  final bool upiAccepted;
  final bool reservationRequired;
  final String reservationNote;
  final String parking;
  final String seating;
  final bool acAvailable;
  final String bestTimeToVisit;
  final String avoidWhen;
  final String waitTimeReality;
  final String localTip;
  final String zomatoRating;
  final String googleRating;
  final bool isTouristTrap;
  final String touristTrapDetail;
  final List<String> bestFor;
  final List<SignatureDish> signatureDishes;

  const RestaurantRecommendation({
    required this.id,
    required this.name,
    required this.type,
    required this.cuisine,
    required this.speciality,
    required this.description,
    required this.knownForSince,
    required this.isVegOnly,
    required this.jainAvailable,
    required this.halalCertified,
    required this.veganOptions,
    required this.nonVegAvailable,
    required this.priceRange,
    required this.priceForTwo,
    required this.area,
    required this.landmark,
    required this.address,
    required this.distanceFromCenter,
    required this.googleMapsQuery,
    required this.cashOnly,
    required this.upiAccepted,
    required this.reservationRequired,
    required this.reservationNote,
    required this.parking,
    required this.seating,
    required this.acAvailable,
    required this.bestTimeToVisit,
    required this.avoidWhen,
    required this.waitTimeReality,
    required this.localTip,
    required this.zomatoRating,
    required this.googleRating,
    required this.isTouristTrap,
    required this.touristTrapDetail,
    required this.bestFor,
    required this.signatureDishes,
  });

  String get primaryDish =>
      signatureDishes.isEmpty ? speciality : signatureDishes.first.dish;

  List<String> get dietaryLabels {
    final labels = <String>[];
    if (isVegOnly) labels.add('Veg only');
    if (jainAvailable) labels.add('Jain');
    if (halalCertified) labels.add('Halal');
    if (veganOptions) labels.add('Vegan');
    if (nonVegAvailable) labels.add('Non-veg');
    return labels;
  }

  factory RestaurantRecommendation.fromJson(Map<String, dynamic> json) {
    final dietary = _map(json['dietary_tags']);
    final location = _map(json['location']);
    final practical = _map(json['practical']);
    final ratings = _map(json['rating_signals']);
    final name = json['name'] as String? ?? 'Restaurant';

    return RestaurantRecommendation(
      id: _slug(name),
      name: name,
      type: json['type'] as String? ?? 'restaurant',
      cuisine: json['cuisine'] as String? ?? '',
      speciality: json['speciality'] as String? ?? '',
      description:
          json['raaste_recommendation_reason'] as String? ??
          json['description'] as String? ??
          '',
      knownForSince: json['known_for_since'] as String? ?? '',
      isVegOnly: dietary['veg_only'] as bool? ?? false,
      jainAvailable: dietary['jain_available'] as bool? ?? false,
      halalCertified: dietary['halal'] as bool? ?? false,
      veganOptions: dietary['vegan_options'] as bool? ?? false,
      nonVegAvailable: dietary['non_veg_available'] as bool? ?? true,
      priceRange: json['price_range'] as String? ?? '',
      priceForTwo: json['price_for_two'] as String? ?? '',
      area: location['area'] as String? ?? '',
      landmark: location['landmark'] as String? ?? '',
      address: location['address'] as String? ?? '',
      distanceFromCenter: location['distance_from_center'] as String? ?? '',
      googleMapsQuery:
          location['google_maps_searchable'] as String? ??
          location['google_maps_query'] as String? ??
          name,
      cashOnly: practical['cash_only'] as bool? ?? false,
      upiAccepted: practical['upi_accepted'] as bool? ?? true,
      reservationRequired: practical['reservation_required'] as bool? ?? false,
      reservationNote: practical['reservation_note'] as String? ?? '',
      parking: practical['parking'] as String? ?? '',
      seating: practical['seating'] as String? ?? '',
      acAvailable: practical['ac_available'] as bool? ?? false,
      bestTimeToVisit: json['best_time_to_visit'] as String? ?? '',
      avoidWhen: json['avoid_when'] as String? ?? '',
      waitTimeReality: json['wait_time_reality'] as String? ?? '',
      localTip: json['local_tip'] as String? ?? '',
      zomatoRating: ratings['zomato_rating']?.toString() ?? '',
      googleRating: ratings['google_rating']?.toString() ?? '',
      isTouristTrap: json['tourist_trap_warning'] as bool? ?? false,
      touristTrapDetail: json['tourist_trap_detail'] as String? ?? '',
      bestFor:
          (json['best_for'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      signatureDishes:
          (json['signature_dishes'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(SignatureDish.fromJson)
              .toList(),
    );
  }
}

class SignatureDish {
  final String dish;
  final String description;
  final String price;

  const SignatureDish({
    required this.dish,
    required this.description,
    required this.price,
  });

  factory SignatureDish.fromJson(Map<String, dynamic> json) => SignatureDish(
    dish: json['dish'] as String? ?? '',
    description:
        json['description'] as String? ?? json['context'] as String? ?? '',
    price: json['price'] as String? ?? '',
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String _slug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'restaurant' : slug;
}
