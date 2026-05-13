import 'package:flutter/services.dart';

enum HealthConnectFailureReason {
  permissionDenied,
  noData,
  unavailable,
  nativeError,
}

class HealthConnectException implements Exception {
  final HealthConnectFailureReason reason;

  const HealthConnectException(this.reason);

  factory HealthConnectException.fromPlatformException(
    PlatformException error,
  ) {
    return HealthConnectException(_reasonFromCode(error.code));
  }

  static HealthConnectFailureReason _reasonFromCode(String code) {
    return switch (code) {
      'permission_denied' => HealthConnectFailureReason.permissionDenied,
      'no_data' => HealthConnectFailureReason.noData,
      'health_connect_unavailable' => HealthConnectFailureReason.unavailable,
      _ => HealthConnectFailureReason.nativeError,
    };
  }

  @override
  String toString() => 'HealthConnectException($reason)';
}
