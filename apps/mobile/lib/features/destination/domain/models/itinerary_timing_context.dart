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
    'origin': origin.name,
    'destination': destination.name,
    'mode': mode,
    'durationMinutes': durationMinutes,
    'durationText': durationText,
    'distanceMeters': distanceMeters,
    'distanceText': distanceText,
  };
}
