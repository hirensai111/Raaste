import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/itinerary_timing_context.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class RouteTimingException implements Exception {
  final String message;
  const RouteTimingException(this.message);

  @override
  String toString() => message;
}

class GoogleRouteMatrixService {
  final Dio _dio;

  GoogleRouteMatrixService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://maps.googleapis.com',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 45),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  Future<ItineraryTimingContext> buildTimingContext(
    TripIntake intake,
    DestinationResearch research,
  ) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const RouteTimingException(
        'Add GOOGLE_MAPS_API_KEY in .env so Raaste can calculate hotel-aware travel times.',
      );
    }

    final stayText = intake.stayNameOrAddress.trim();
    if (stayText.isEmpty) {
      throw const RouteTimingException(
        'Tell me where you are staying so I can calculate realistic route times.',
      );
    }

    final stay = await _stayPlace(intake, research, apiKey);

    final travelMode = _normalizedTravelMode(intake.travelMode);
    final hub = await _arrivalDepartureHub(research, travelMode, apiKey);
    final attractions = _attractionPlaces(research).take(8).toList();
    final restaurants = await _restaurantPlaces(research, apiKey, limit: 4);
    final keyPlaces = [...attractions, ...restaurants].take(10).toList();

    if (keyPlaces.isEmpty) {
      throw const RouteTimingException(
        'I could not find mapped places in Raaste research for route timing.',
      );
    }

    final pairs = <_RoutePair>[];
    if (hub != null) {
      pairs.add(_RoutePair('Arrival transfer to stay', hub, stay));
      pairs.add(_RoutePair('Final-day transfer from stay', stay, hub));
    }

    for (final place in keyPlaces.take(8)) {
      pairs.add(_RoutePair('Stay to ${place.name}', stay, place));
    }

    final orderedAttractions = attractions.take(6).toList();
    for (var i = 0; i < orderedAttractions.length - 1; i++) {
      pairs.add(
        _RoutePair(
          '${orderedAttractions[i].name} to ${orderedAttractions[i + 1].name}',
          orderedAttractions[i],
          orderedAttractions[i + 1],
        ),
      );
    }

    if (pairs.isEmpty) {
      throw const RouteTimingException(
        'I could not build route pairs for this itinerary.',
      );
    }

    final routeResults = await Future.wait(
      pairs.map((pair) => _routePairResult(pair, apiKey, travelMode)),
    );
    final routes = routeResults.map((result) => result.entry).toList();
    final routeNotes =
        routeResults.map((result) => result.note).whereType<String>().toList();
    if (routes.isEmpty) {
      throw const RouteTimingException(
        'I could not calculate any usable route timings for this itinerary.',
      );
    }

    return ItineraryTimingContext(
      destinationName: research.destinationName,
      travelMode: travelMode,
      stay: stay,
      arrivalHub: hub,
      departureHub: hub,
      routes: routes,
      notes: [
        'Google route durations are planning estimates, not live traffic guarantees.',
        'Use these durations as minimum movement buffers; add extra time for check-in, luggage, queues, parking, crowds, and weather.',
        'For flights, keep airport security and boarding buffers separate from the road transfer duration.',
        ...routeNotes,
      ],
      generatedAt: DateTime.now(),
    );
  }

  Future<RoutePlace> _stayPlace(
    TripIntake intake,
    DestinationResearch research,
    String apiKey,
  ) async {
    final stayText = intake.stayNameOrAddress.trim();
    final stayLat = intake.stayLat;
    final stayLon = intake.stayLon;
    if (stayLat != null && stayLon != null && stayLat != 0 && stayLon != 0) {
      return RoutePlace(
        name: stayText,
        address: stayText,
        lat: stayLat,
        lon: stayLon,
        type: 'stay',
      );
    }

    return _geocodePlace(
      '$stayText, ${research.destinationName}, India',
      apiKey,
      fallbackName: stayText,
      type: 'stay',
    );
  }

  Future<RoutePlace?> _arrivalDepartureHub(
    DestinationResearch research,
    String travelMode,
    String apiKey,
  ) async {
    String? query;
    String type = 'arrival_hub';
    final howToReach = _map(research.data['how_to_reach']);

    if (_isFlightMode(travelMode)) {
      query = _string(_map(howToReach['nearest_airport'])['name']);
      query =
          query?.isNotEmpty == true
              ? query
              : '${research.destinationName} airport';
      type = 'airport';
    } else if (_isTrainMode(travelMode)) {
      query = _string(_map(howToReach['nearest_railway_station'])['name']);
      query =
          query?.isNotEmpty == true
              ? query
              : '${research.destinationName} railway station';
      type = 'railway_station';
    } else if (_isBusMode(travelMode)) {
      query = '${research.destinationName} bus stand';
      type = 'bus_stand';
    }

    if (query == null || query.trim().isEmpty) return null;
    final cleanQuery = _cleanHubQuery(query, research.destinationName);
    return _geocodePlace(
      '$cleanQuery, ${research.destinationName}, India',
      apiKey,
      fallbackName: cleanQuery,
      type: type,
    );
  }

  Future<RoutePlace> _geocodePlace(
    String query,
    String apiKey, {
    required String fallbackName,
    required String type,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/maps/api/geocode/json',
        queryParameters: {
          'address': query,
          'components': 'country:IN',
          'key': apiKey,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      final status = data['status'] as String? ?? '';
      final results = data['results'] as List<dynamic>? ?? const [];
      if (status != 'OK' || results.isEmpty) {
        throw RouteTimingException(
          'Google Maps could not locate "$fallbackName". Try a more specific hotel, area, or address.',
        );
      }

      final first = results.first as Map<String, dynamic>;
      final geometry = _map(first['geometry']);
      final location = _map(geometry['location']);
      final lat = (location['lat'] as num?)?.toDouble();
      final lon = (location['lng'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        throw RouteTimingException(
          'Google Maps found "$fallbackName" but did not return coordinates.',
        );
      }

      return RoutePlace(
        name: fallbackName,
        address: first['formatted_address'] as String?,
        lat: lat,
        lon: lon,
        type: type,
      );
    } on RouteTimingException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
        throw const RouteTimingException(
          'Google Maps rejected GOOGLE_MAPS_API_KEY. Check the key and enabled APIs.',
        );
      }
      throw const RouteTimingException(
        'Could not reach Google Maps geocoding right now. Please try again.',
      );
    }
  }

  Future<RouteTimingEntry> _routePair(
    _RoutePair pair,
    String apiKey,
    String travelMode,
  ) async {
    try {
      final response = await _dio.post<List<dynamic>>(
        'https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix',
        data: {
          'origins': [_routeWaypoint(pair.origin)],
          'destinations': [_routeWaypoint(pair.destination)],
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_UNAWARE',
        },
        options: Options(
          headers: {
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask':
                'originIndex,destinationIndex,duration,distanceMeters,condition,status',
          },
        ),
      );
      final items = response.data ?? const [];
      if (items.isEmpty || items.first is! Map<String, dynamic>) {
        throw const RouteTimingException(
          'Google Maps did not return a route for one of the itinerary transfers.',
        );
      }
      final item = items.first as Map<String, dynamic>;
      final condition = item['condition'] as String? ?? 'ROUTE_EXISTS';
      if (condition != 'ROUTE_EXISTS') {
        throw RouteTimingException(
          'Google Maps could not route ${pair.origin.name} to ${pair.destination.name}.',
        );
      }
      if (item['distanceMeters'] == null || item['duration'] == null) {
        throw RouteTimingException(
          'Google Maps returned an incomplete route for ${pair.origin.name} to ${pair.destination.name}.',
        );
      }
      final distanceMeters = (item['distanceMeters'] as num).toInt();
      final durationSeconds = _durationSeconds(item['duration']);
      final minutes = math.max(1, (durationSeconds / 60).ceil());
      return RouteTimingEntry(
        label: pair.label,
        origin: pair.origin,
        destination: pair.destination,
        mode: travelMode,
        durationMinutes: minutes,
        durationText: _formatDuration(minutes),
        distanceMeters: distanceMeters,
        distanceText: _formatDistance(distanceMeters),
      );
    } on RouteTimingException {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
        throw const RouteTimingException(
          'Google Maps rejected GOOGLE_MAPS_API_KEY. Check Routes API access for this key.',
        );
      }
      throw const RouteTimingException(
        'Could not calculate Google route times right now. Please try again.',
      );
    }
  }

  Future<_RouteResult> _routePairResult(
    _RoutePair pair,
    String apiKey,
    String travelMode,
  ) async {
    try {
      return _RouteResult(await _routePair(pair, apiKey, travelMode));
    } on RouteTimingException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('api_key') || lower.contains('rejected')) rethrow;
      return _RouteResult(
        _estimatedRoutePair(pair, travelMode),
        'Estimated ${pair.label} because Google Maps could not return an exact route. Confirm this transfer locally.',
      );
    }
  }

  RouteTimingEntry _estimatedRoutePair(_RoutePair pair, String travelMode) {
    final straightLineMeters = _straightLineMeters(
      pair.origin,
      pair.destination,
    );
    final adjustedMeters = math.max(1000, (straightLineMeters * 1.45).round());
    final minutes = math.max(8, ((adjustedMeters / 1000) / 18 * 60).ceil());
    return RouteTimingEntry(
      label: pair.label,
      origin: pair.origin,
      destination: pair.destination,
      mode: '$travelMode estimate',
      durationMinutes: minutes,
      durationText: _formatDuration(minutes),
      distanceMeters: adjustedMeters,
      distanceText: _formatDistance(adjustedMeters),
    );
  }

  int _straightLineMeters(RoutePlace origin, RoutePlace destination) {
    const earthRadiusMeters = 6371000.0;
    final originLat = _toRadians(origin.lat);
    final destinationLat = _toRadians(destination.lat);
    final deltaLat = _toRadians(destination.lat - origin.lat);
    final deltaLon = _toRadians(destination.lon - origin.lon);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(originLat) *
            math.cos(destinationLat) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (earthRadiusMeters * c).round();
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
  Map<String, dynamic> _routeWaypoint(RoutePlace place) => {
    'waypoint': {
      'location': {
        'latLng': {'latitude': place.lat, 'longitude': place.lon},
      },
    },
  };

  List<RoutePlace> _attractionPlaces(DestinationResearch research) {
    final attractions = research.data['attractions'];
    if (attractions is! List) return const [];

    final places = <RoutePlace>[];
    for (final item in attractions) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final coordinates = _map(json['coordinates']);
      final lat = (coordinates['lat'] as num?)?.toDouble();
      final lon =
          (coordinates['lng'] as num?)?.toDouble() ??
          (coordinates['lon'] as num?)?.toDouble();
      final name = _string(json['name']);
      if (lat == null || lon == null || name == null || name.isEmpty) continue;
      places.add(
        RoutePlace(
          name: name,
          address: research.destinationName,
          lat: lat,
          lon: lon,
          type: _string(json['type']) ?? 'attraction',
        ),
      );
    }
    return places;
  }

  Future<List<RoutePlace>> _restaurantPlaces(
    DestinationResearch research,
    String apiKey, {
    required int limit,
  }) async {
    final restaurants = research.restaurantData?['restaurants'];
    if (restaurants is! List) return const [];

    final places = <RoutePlace>[];
    for (final item in restaurants) {
      if (places.length >= limit) break;
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final name = _string(json['name']);
      if (name == null || name.isEmpty) continue;
      final location = _map(json['location']);
      final lat = (location['lat'] as num?)?.toDouble();
      final lon =
          (location['lng'] as num?)?.toDouble() ??
          (location['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        places.add(
          RoutePlace(
            name: name,
            address: _string(location['address']),
            lat: lat,
            lon: lon,
            type: 'restaurant',
          ),
        );
        continue;
      }

      final searchable =
          _string(location['google_maps_searchable']) ??
          _string(location['google_maps_query']) ??
          _string(location['address']) ??
          '$name ${research.destinationName}';
      try {
        final place = await _geocodePlace(
          '$searchable, ${research.destinationName}, India',
          apiKey,
          fallbackName: name,
          type: 'restaurant',
        );
        places.add(place);
      } on RouteTimingException {
        // Restaurant geocoding enriches the timing context but should not block
        // the whole itinerary if a single food listing is hard to locate.
      }
    }
    return places;
  }

  String _normalizedTravelMode(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.contains('flight') ||
        lower.contains('aeroplane') ||
        lower.contains('airplane') ||
        lower.contains('plane') ||
        lower.contains('air')) {
      return 'flight';
    }
    if (lower.contains('train') || lower.contains('rail')) return 'train';
    if (lower.contains('bus') || lower.contains('coach')) return 'bus';
    if (lower.contains('car') ||
        lower.contains('drive') ||
        lower.contains('cab')) {
      return 'car';
    }
    return value.trim().isEmpty ? 'other' : value.trim();
  }

  bool _isFlightMode(String value) => value == 'flight';
  bool _isTrainMode(String value) => value == 'train';
  bool _isBusMode(String value) => value == 'bus';

  String _cleanHubQuery(String query, String destinationName) {
    var cleaned =
        query
            .split('—')
            .first
            .split(';')
            .first
            .split(',')
            .first
            .replaceAll(RegExp(r'\([^)]*\)'), '')
            .trim();
    if (cleaned.isEmpty) cleaned = query.trim();
    if (!cleaned.toLowerCase().contains(destinationName.toLowerCase())) {
      cleaned = '$cleaned $destinationName';
    }
    return cleaned;
  }

  int _durationSeconds(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(value.trim());
      if (match != null) {
        return double.parse(match.group(1)!).round();
      }
    }
    return 0;
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String _formatDistance(int meters) {
    if (meters < 1000) return '$meters m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

class _RouteResult {
  final RouteTimingEntry entry;
  final String? note;

  const _RouteResult(this.entry, [this.note]);
}

class _RoutePair {
  final String label;
  final RoutePlace origin;
  final RoutePlace destination;

  const _RoutePair(this.label, this.origin, this.destination);
}
