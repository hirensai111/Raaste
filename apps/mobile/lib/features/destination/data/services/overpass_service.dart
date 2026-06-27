import 'package:dio/dio.dart';

import 'package:raaste/features/destination/domain/models/osm_place.dart';

class OverpassException implements Exception {
  final String message;
  const OverpassException(this.message);

  @override
  String toString() => message;
}

class OverpassService {
  final Dio _dio;

  OverpassService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://overpass-api.de/api',
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 45),
                headers: {
                  'Accept': 'application/json',
                  'User-Agent': 'RaasteMobile/1.0 prototype itinerary planner',
                },
              ),
            );

  Future<OsmPlaceBundle> fetchNearbyPlaces({
    required double lat,
    required double lon,
  }) async {
    final first = await _fetchRadius(lat: lat, lon: lon, radiusMeters: 10000);
    if (!first.isSparse) return first;

    final expanded = await _fetchRadius(lat: lat, lon: lon, radiusMeters: 25000);
    if (expanded.attractions.length + expanded.food.length >=
        first.attractions.length + first.food.length) {
      return expanded;
    }
    return first;
  }

  Future<OsmPlaceBundle> _fetchRadius({
    required double lat,
    required double lon,
    required int radiusMeters,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/interpreter',
        data: {'data': _query(lat: lat, lon: lon, radiusMeters: radiusMeters)},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final elements = response.data?['elements'] as List<dynamic>? ?? const [];
      final places = elements
          .whereType<Map<String, dynamic>>()
          .map(OsmPlace.fromOverpass)
          .where((place) =>
              place.name != 'Unnamed place' && place.lat != 0 && place.lon != 0)
          .toList();

      final attractions = <String, OsmPlace>{};
      final food = <String, OsmPlace>{};
      for (final place in places) {
        if (place.category == 'food') {
          food.putIfAbsent(place.name.toLowerCase(), () => place);
        } else {
          attractions.putIfAbsent(place.name.toLowerCase(), () => place);
        }
      }

      return OsmPlaceBundle(
        attractions: attractions.values.take(30).toList(),
        food: food.values.take(30).toList(),
        radiusMeters: radiusMeters,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw const OverpassException(
          'OpenStreetMap place data is busy right now. Please try again shortly.',
        );
      }
      throw const OverpassException(
        'Could not fetch nearby attractions and restaurants right now.',
      );
    }
  }

  String _query({
    required double lat,
    required double lon,
    required int radiusMeters,
  }) {
    return '''
[out:json][timeout:25];
(
  node["tourism"~"attraction|museum|viewpoint|zoo"](around:,,);
  way["tourism"~"attraction|museum|viewpoint|zoo"](around:,,);
  relation["tourism"~"attraction|museum|viewpoint|zoo"](around:,,);
  node["historic"](around:,,);
  way["historic"](around:,,);
  relation["historic"](around:,,);
  node["leisure"="park"](around:,,);
  way["leisure"="park"](around:,,);
  relation["leisure"="park"](around:,,);
  node["amenity"~"restaurant|cafe|fast_food|food_court"](around:,,);
  way["amenity"~"restaurant|cafe|fast_food|food_court"](around:,,);
  relation["amenity"~"restaurant|cafe|fast_food|food_court"](around:,,);
);
out center tags;
''';
  }
}
