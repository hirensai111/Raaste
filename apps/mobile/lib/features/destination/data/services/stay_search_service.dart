import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';

class StaySearchException implements Exception {
  final String message;
  const StaySearchException(this.message);

  @override
  String toString() => message;
}

class StaySearchService {
  final Dio _osmDio;
  final Dio _googleDio;

  StaySearchService({Dio? osmDio, Dio? googleDio})
    : _osmDio =
          osmDio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://nominatim.openstreetmap.org',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'RaasteMobile/1.0 stay search',
              },
            ),
          ),
      _googleDio =
          googleDio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://maps.googleapis.com',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  Future<List<PlaceSuggestion>> search({
    required String query,
    required String destinationName,
    double? destinationLat,
    double? destinationLon,
  }) async {
    final cleanQuery = query.trim();
    final cleanDestination = destinationName.trim();
    if (cleanQuery.length < 2 || cleanDestination.isEmpty) return const [];

    final osmResults = await _searchOpenStreetMap(
      query: cleanQuery,
      destinationName: cleanDestination,
      destinationLat: destinationLat,
      destinationLon: destinationLon,
    );
    if (osmResults.isNotEmpty) return osmResults;

    return _searchGoogle(query: cleanQuery, destinationName: cleanDestination);
  }

  Future<List<PlaceSuggestion>> _searchOpenStreetMap({
    required String query,
    required String destinationName,
    double? destinationLat,
    double? destinationLon,
  }) async {
    try {
      final response = await _osmDio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'q': '$query, $destinationName, India',
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 8,
          'countrycodes': 'in',
          'dedupe': 1,
          if (destinationLat != null && destinationLon != null)
            'viewbox': _viewbox(destinationLat, destinationLon),
          if (destinationLat != null && destinationLon != null) 'bounded': 0,
        },
      );

      final rows = response.data ?? const [];
      return _dedupe(
        rows
            .whereType<Map>()
            .map((row) => _fromOpenStreetMap(Map<String, dynamic>.from(row)))
            .whereType<PlaceSuggestion>()
            .toList(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw const StaySearchException(
          'OpenStreetMap search is busy right now. Try again in a moment.',
        );
      }
      return const [];
    }
  }

  Future<List<PlaceSuggestion>> _searchGoogle({
    required String query,
    required String destinationName,
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) return const [];

    try {
      final response = await _googleDio.get<Map<String, dynamic>>(
        '/maps/api/geocode/json',
        queryParameters: {
          'address': '$query, $destinationName, India',
          'components': 'country:IN',
          'key': apiKey,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      final status = data['status'] as String? ?? '';
      if (status != 'OK') return const [];

      final rows = data['results'] as List<dynamic>? ?? const [];
      return _dedupe(
        rows
            .whereType<Map>()
            .map((row) => _fromGoogle(Map<String, dynamic>.from(row)))
            .whereType<PlaceSuggestion>()
            .take(6)
            .toList(),
      );
    } on DioException {
      return const [];
    }
  }

  PlaceSuggestion? _fromOpenStreetMap(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '');
    final lon = double.tryParse(json['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;

    final displayName = json['display_name']?.toString().trim() ?? '';
    final name = _nameFromAddress(json) ?? displayName.split(',').first.trim();
    if (name.isEmpty) return null;

    final category = json['category']?.toString() ?? '';
    final type = json['type']?.toString() ?? '';
    final description = _description(category, type, displayName);

    return PlaceSuggestion(
      sourceId:
          'osm:${json['osm_type'] ?? 'place'}:${json['osm_id'] ?? '$lat,$lon'}',
      name: name,
      description: description,
      displayAddress: displayName.isEmpty ? name : displayName,
      lat: lat,
      lon: lon,
    );
  }

  PlaceSuggestion? _fromGoogle(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    if (geometry is! Map) return null;
    final location = geometry['location'];
    if (location is! Map) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lon = (location['lng'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final address = json['formatted_address']?.toString().trim() ?? '';
    final components = json['address_components'] as List<dynamic>? ?? const [];
    final name =
        components
            .whereType<Map>()
            .map((item) => item['long_name']?.toString().trim())
            .firstWhere(
              (item) => item != null && item.isNotEmpty,
              orElse: () => null,
            ) ??
        address.split(',').first.trim();
    if (name.isEmpty) return null;

    return PlaceSuggestion(
      sourceId: 'google:${json['place_id'] ?? '$lat,$lon'}',
      name: name,
      description: 'Google Maps result',
      displayAddress: address.isEmpty ? name : address,
      lat: lat,
      lon: lon,
    );
  }

  String? _nameFromAddress(Map<String, dynamic> json) {
    final address = json['address'];
    if (address is! Map) return null;
    const keys = [
      'hotel',
      'hostel',
      'guest_house',
      'resort',
      'motel',
      'apartment',
      'neighbourhood',
      'suburb',
      'quarter',
      'road',
    ];
    for (final key in keys) {
      final value = address[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String _description(String category, String type, String displayName) {
    final label = [
      category,
      type,
    ].where((item) => item.trim().isNotEmpty).join(' / ').replaceAll('_', ' ');
    if (label.isNotEmpty) return label;
    final parts = displayName.split(',').map((item) => item.trim()).toList();
    if (parts.length >= 3) return parts.take(3).join(', ');
    return 'Map result';
  }

  List<PlaceSuggestion> _dedupe(List<PlaceSuggestion> places) {
    final seen = <String>{};
    final results = <PlaceSuggestion>[];
    for (final place in places) {
      final key =
          '${place.name.toLowerCase()}|${place.lat?.toStringAsFixed(5)}|${place.lon?.toStringAsFixed(5)}';
      if (seen.add(key)) results.add(place);
    }
    return results;
  }

  String _viewbox(double lat, double lon) {
    const delta = 0.35;
    final left = lon - delta;
    final right = lon + delta;
    final top = lat + delta;
    final bottom = lat - delta;
    return '$left,$top,$right,$bottom';
  }
}
