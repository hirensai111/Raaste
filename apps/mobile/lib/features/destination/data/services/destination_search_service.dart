import 'package:dio/dio.dart';

import 'package:raaste/features/destination/domain/models/place_suggestion.dart';

class DestinationSearchException implements Exception {
  final String message;
  const DestinationSearchException(this.message);

  @override
  String toString() => message;
}

class DestinationSearchService {
  final Dio _dio;
  DateTime? _lastRequestAt;

  DestinationSearchService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://nominatim.openstreetmap.org',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'Accept': 'application/json',
                  'User-Agent':
                      'RaasteMobile/1.0 (prototype travel planner; contact: support@raaste.app)',
                },
              ),
            );

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 2) return const [];

    try {
      await _respectPublicRateLimit();
      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'q': query,
          'countrycodes': 'in',
          'format': 'jsonv2',
          'addressdetails': 1,
          'namedetails': 1,
          'limit': 5,
          'dedupe': 1,
        },
      );

      final suggestions = response.data ?? const [];
      return suggestions
          .whereType<Map<String, dynamic>>()
          .map(PlaceSuggestion.fromNominatim)
          .where((item) => item.sourceId.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 403 || status == 429) {
        throw const DestinationSearchException(
          'OpenStreetMap search is rate-limited right now. Please wait a moment and try again.',
        );
      }
      throw const DestinationSearchException(
        'Destination search is unavailable right now. Please try again.',
      );
    }
  }

  Future<void> _respectPublicRateLimit() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      const minimumGap = Duration(milliseconds: 1100);
      if (elapsed < minimumGap) {
        await Future<void>.delayed(minimumGap - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}
