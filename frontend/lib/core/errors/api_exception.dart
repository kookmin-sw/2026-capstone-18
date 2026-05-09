class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? details;

  const ApiException({required this.message, this.statusCode, this.details});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => message;
}
