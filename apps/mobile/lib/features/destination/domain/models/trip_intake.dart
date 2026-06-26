class TripIntake {
  final String destination;
  final String sourceId;
  final String displayAddress;
  final double? lat;
  final double? lon;
  final String dates;
  final String landingTime;
  final String departureTime;
  final int peopleCount;
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
    required this.peopleCount,
    required this.interests,
    required this.dietaryPreference,
  });

  Map<String, dynamic> toJson() => {
        'destination': destination,
        'sourceId': sourceId,
        'displayAddress': displayAddress,
        'lat': lat,
        'lon': lon,
        'dates': dates,
        'landingTime': landingTime,
        'departureTime': departureTime,
        'peopleCount': peopleCount,
        'interests': interests,
        'dietaryPreference': dietaryPreference,
      };

  factory TripIntake.fromJson(Map<String, dynamic> json) => TripIntake(
        destination: json['destination'] as String? ?? '',
        sourceId: (json['sourceId'] as String?) ??
            (json['placeId'] as String?) ??
            '',
        displayAddress: json['displayAddress'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
        dates: json['dates'] as String? ?? '',
        landingTime: json['landingTime'] as String? ?? '',
        departureTime: json['departureTime'] as String? ?? '',
        peopleCount: (json['peopleCount'] as num?)?.toInt() ?? 1,
        interests: (json['interests'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        dietaryPreference: json['dietaryPreference'] as String? ?? '',
      );
}


