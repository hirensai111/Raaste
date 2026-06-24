class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({this.message = 'Server error occurred', this.statusCode});
}

class CacheException implements Exception {
  final String message;

  const CacheException({this.message = 'Cache error occurred'});
}

class NetworkException implements Exception {
  final String message;

  const NetworkException({this.message = 'Network error occurred'});
}

class LocationException implements Exception {
  final String message;

  const LocationException({this.message = 'Location error occurred'});
}

class UnauthorizedException implements Exception {
  final String message;

  const UnauthorizedException({this.message = 'User is not authorized'});
}
