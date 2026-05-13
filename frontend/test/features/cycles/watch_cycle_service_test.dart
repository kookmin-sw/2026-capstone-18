import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/cycles/services/watch_cycle_service.dart';
import 'package:little_signals/features/health/health_connect_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('littlesignals/health');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns WatchCycleData mapped from channel response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getLatestCycleData');
          return {
            'period_start_ms': 1700000000000,
            'period_end_ms': 1700432000000,
            'estimated_cycle_length_days': null,
            'source': 'Galaxy Watch / Samsung Health',
          };
        });

    final result = await const WatchCycleService().getLatestCycleData();
    expect(result, isNotNull);
    expect(result!.periodStart.millisecondsSinceEpoch, equals(1700000000000));
    expect(result.periodEnd?.millisecondsSinceEpoch, equals(1700432000000));
    expect(result.source, equals('Galaxy Watch / Samsung Health'));
  });

  test('returns null when channel returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await const WatchCycleService().getLatestCycleData();
    expect(result, isNull);
  });

  test('maps native failure reasons from platform errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'no_data');
        });

    await expectLater(
      const WatchCycleService().getLatestCycleData(),
      throwsA(
        isA<HealthConnectException>().having(
          (error) => error.reason,
          'reason',
          HealthConnectFailureReason.noData,
        ),
      ),
    );
  });

  test('requests cycle permission through health channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requestHealthPermissions');
          expect(call.arguments, {'kind': 'cycle'});
          return {'granted': true};
        });

    final result = await const WatchCycleService().requestPermission();
    expect(result, isTrue);
  });
}
