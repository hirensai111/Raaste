import 'package:dio/dio.dart';

class PlaceImageService {
  static const fallbackAsset = 'assets/images/home_destination_jaipur.png';

  final Dio _dio;

  PlaceImageService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://en.wikipedia.org/api/rest_v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 12),
              headers: {
                'User-Agent':
                    'Raaste mobile prototype (travel planning image lookup)',
              },
            ),
          );

  Future<String> imageForDestination(String destinationName) async {
    final normalized = destinationName.trim();
    if (normalized.isEmpty) return fallbackAsset;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/page/summary/${Uri.encodeComponent(normalized)}',
        queryParameters: {'redirect': 'true'},
      );
      final page = response.data ?? <String, dynamic>{};
      final original = page['originalimage'] as Map<String, dynamic>?;
      final thumbnail = page['thumbnail'] as Map<String, dynamic>?;
      final url =
          (original?['source'] as String?) ??
          (thumbnail?['source'] as String?) ??
          '';
      return url.trim().isNotEmpty ? url : fallbackAsset;
    } catch (_) {
      return fallbackAsset;
    }
  }
}
