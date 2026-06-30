class TripIntake {
  final String destination;
  final String sourceId;
  final String displayAddress;
  final double? lat;
  final double? lon;
  final String dates;
  final String landingTime;
  final String departureTime;
  final String stayNameOrAddress;
  final double? stayLat;
  final double? stayLon;
  final int peopleCount;
  final String travelMode;
  final String pacePreference;
  final List<String> interests;
  final String dietaryPreference;

  const TripIntake({
    required this.destination,
    required this.sourceId,
    required this.displayAddress,
    required this.lat,
    required this.lon,
    required this.dates,
    required this.landingTime,
    required this.departureTime,
    required this.stayNameOrAddress,
    required this.stayLat,
    required this.stayLon,
    required this.peopleCount,
    required this.travelMode,
    required this.pacePreference,
    required this.interests,
    required this.dietaryPreference,
  });

  TripIntake copyWith({
    String? destination,
    String? sourceId,
    String? displayAddress,
    double? lat,
    double? lon,
    String? dates,
    String? landingTime,
    String? departureTime,
    String? stayNameOrAddress,
    double? stayLat,
    double? stayLon,
    int? peopleCount,
    String? travelMode,
    String? pacePreference,
    List<String>? interests,
    String? dietaryPreference,
  }) {
    return TripIntake(
      destination: destination ?? this.destination,
      sourceId: sourceId ?? this.sourceId,
      displayAddress: displayAddress ?? this.displayAddress,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      dates: dates ?? this.dates,
      landingTime: landingTime ?? this.landingTime,
      departureTime: departureTime ?? this.departureTime,
      stayNameOrAddress: stayNameOrAddress ?? this.stayNameOrAddress,
      stayLat: stayLat ?? this.stayLat,
      stayLon: stayLon ?? this.stayLon,
      peopleCount: peopleCount ?? this.peopleCount,
      travelMode: travelMode ?? this.travelMode,
      pacePreference: pacePreference ?? this.pacePreference,
      interests: interests ?? this.interests,
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
    );
  }

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'sourceId': sourceId,
    'displayAddress': displayAddress,
    'lat': lat,
    'lon': lon,
    'dates': dates,
    'landingTime': landingTime,
    'departureTime': departureTime,
    'stayNameOrAddress': stayNameOrAddress,
    'stayLat': stayLat,
    'stayLon': stayLon,
    'peopleCount': peopleCount,
    'travelMode': travelMode,
    'pacePreference': pacePreference,
    'interests': interests,
    'dietaryPreference': dietaryPreference,
  };

  factory TripIntake.fromJson(Map<String, dynamic> json) => TripIntake(
    destination: json['destination'] as String? ?? '',
    sourceId:
        (json['sourceId'] as String?) ?? (json['placeId'] as String?) ?? '',
    displayAddress: json['displayAddress'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble(),
    lon: (json['lon'] as num?)?.toDouble(),
    dates: json['dates'] as String? ?? '',
    landingTime: json['landingTime'] as String? ?? '',
    departureTime: json['departureTime'] as String? ?? '',
    stayNameOrAddress:
        json['stayNameOrAddress'] as String? ??
        json['hotelNameOrAddress'] as String? ??
        json['stay'] as String? ??
        '',
    stayLat:
        (json['stayLat'] as num?)?.toDouble() ??
        (json['hotelLat'] as num?)?.toDouble(),
    stayLon:
        (json['stayLon'] as num?)?.toDouble() ??
        (json['stayLng'] as num?)?.toDouble() ??
        (json['hotelLon'] as num?)?.toDouble(),
    peopleCount: (json['peopleCount'] as num?)?.toInt() ?? 1,
    travelMode: json['travelMode'] as String? ?? 'Not specified',
    pacePreference: json['pacePreference'] as String? ?? 'Balanced',
    interests:
        (json['interests'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
    dietaryPreference: json['dietaryPreference'] as String? ?? '',
  );
}
