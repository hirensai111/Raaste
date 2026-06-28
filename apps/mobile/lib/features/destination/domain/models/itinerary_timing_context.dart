class ItineraryTimingContext {
  final String destinationName;
  final String travelMode;
  final RoutePlace stay;
  final RoutePlace? arrivalHub;
  final RoutePlace? departureHub;
  final List<RouteTimingEntry> routes;
  final List<String> notes;
  final DateTime generatedAt;

  const ItineraryTimingContext({
    required this.destinationName,
    required this.travelMode,
    required this.stay,
    required this.arrivalHub,
    required this.departureHub,
    required this.routes,
    required this.notes,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'destinationName': destinationName,
    'travelMode': travelMode,
    'stay': stay.toJson(),
    if (arrivalHub != null) 'arrivalHub': arrivalHub!.toJson(),
    if (departureHub != null) 'departureHub': departureHub!.toJson(),
    'routes': routes.map((route) => route.toJson()).toList(),
    'notes': notes,
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory ItineraryTimingContext.fromJson(Map<String, dynamic> json) {
    return ItineraryTimingContext(
      destinationName: json['destinationName'] as String? ?? '',
      travelMode: json['travelMode'] as String? ?? '',
      stay: RoutePlace.fromJson(
        json['stay'] as Map<String, dynamic>? ?? const {},
        fallbackName: 'Stay',
        fallbackType: 'stay',
      ),
      arrivalHub:
          json['arrivalHub'] is Map<String, dynamic>
              ? RoutePlace.fromJson(
                json['arrivalHub'] as Map<String, dynamic>,
                fallbackName: 'Arrival hub',
                fallbackType: 'arrival_hub',
              )
              : null,
      departureHub:
          json['departureHub'] is Map<String, dynamic>
              ? RoutePlace.fromJson(
                json['departureHub'] as Map<String, dynamic>,
                fallbackName: 'Departure hub',
                fallbackType: 'departure_hub',
              )
              : null,
      routes:
          (json['routes'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(RouteTimingEntry.fromJson)
              .toList(),
      notes:
          (json['notes'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class RoutePlace {
  final String name;
  final String? address;
  final double lat;
  final double lon;
  final String type;

  const RoutePlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (address != null && address!.trim().isNotEmpty) 'address': address,
    'lat': lat,
    'lon': lon,
    'type': type,
  };

  factory RoutePlace.fromJson(
    Map<String, dynamic> json, {
    required String fallbackName,
    required String fallbackType,
  }) {
    return RoutePlace(
      name: json['name'] as String? ?? fallbackName,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon:
          (json['lon'] as num?)?.toDouble() ??
          (json['lng'] as num?)?.toDouble() ??
          0,
      type: json['type'] as String? ?? fallbackType,
    );
  }
}

class RouteTimingEntry {
  final String label;
  final RoutePlace origin;
  final RoutePlace destination;
  final String mode;
  final int durationMinutes;
  final String durationText;
  final int distanceMeters;
  final String distanceText;

  const RouteTimingEntry({
    required this.label,
    required this.origin,
    required this.destination,
    required this.mode,
    required this.durationMinutes,
    required this.durationText,
    required this.distanceMeters,
    required this.distanceText,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'origin': origin.toJson(),
    'destination': destination.toJson(),
    'mode': mode,
    'durationMinutes': durationMinutes,
    'durationText': durationText,
    'distanceMeters': distanceMeters,
    'distanceText': distanceText,
  };

  factory RouteTimingEntry.fromJson(Map<String, dynamic> json) {
    return RouteTimingEntry(
      label: json['label'] as String? ?? '',
      origin: _placeFromRouteSide(
        json['origin'],
        fallbackName: 'Origin',
        fallbackType: 'origin',
      ),
      destination: _placeFromRouteSide(
        json['destination'],
        fallbackName: 'Destination',
        fallbackType: 'destination',
      ),
      mode: json['mode'] as String? ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      durationText: json['durationText'] as String? ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      distanceText: json['distanceText'] as String? ?? '',
    );
  }
}

RoutePlace _placeFromRouteSide(
  Object? value, {
  required String fallbackName,
  required String fallbackType,
}) {
  if (value is Map<String, dynamic>) {
    return RoutePlace.fromJson(
      value,
      fallbackName: fallbackName,
      fallbackType: fallbackType,
    );
  }
  if (value is String && value.trim().isNotEmpty) {
    return RoutePlace(
      name: value.trim(),
      address: null,
      lat: 0,
      lon: 0,
      type: fallbackType,
    );
  }
  return RoutePlace(
    name: fallbackName,
    address: null,
    lat: 0,
    lon: 0,
    type: fallbackType,
  );
}
