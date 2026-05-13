import 'package:flutter/services.dart';
import '../../health/health_connect_exception.dart';
import '../models/watch_cycle_data.dart';

class WatchCycleService {
  const WatchCycleService();

  static const _channel = MethodChannel('littlesignals/health');

  Future<WatchCycleData?> getLatestCycleData() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getLatestCycleData',
      );
      if (result == null) return null;
      final periodEndMs = result['period_end_ms'] as int?;
      final cycleLengthDays = result['estimated_cycle_length_days'] as int?;
      return WatchCycleData(
        periodStart: DateTime.fromMillisecondsSinceEpoch(
          result['period_start_ms'] as int,
        ),
        periodEnd: periodEndMs != null
            ? DateTime.fromMillisecondsSinceEpoch(periodEndMs)
            : null,
        estimatedCycleLength: cycleLengthDays,
        source: result['source'] as String? ?? 'Galaxy Watch / Samsung Health',
      );
    } on PlatformException catch (error) {
      throw HealthConnectException.fromPlatformException(error);
    }
  }

  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestHealthPermissions',
        {'kind': 'cycle'},
      );
      return result?['granted'] == true;
    } on PlatformException catch (error) {
      throw HealthConnectException.fromPlatformException(error);
    }
  }
}
