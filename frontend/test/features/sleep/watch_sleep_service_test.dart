import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/sleep/services/watch_sleep_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('littlesignals/health');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns WatchSleepData mapped from channel response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getLatestSleepData');
      return {
        'fell_asleep_at_ms': 1700000000000,
        'woke_up_at_ms': 1700028800000,
        'ended_on_ms': 1700028800000,
        'source': 'Galaxy Watch',
      };
    });

    final result = await const WatchSleepService().getLatestSleepData();
    expect(result, isNotNull);
    expect(result!.fellAsleepAt.millisecondsSinceEpoch, equals(1700000000000));
    expect(result.wokeUpAt.millisecondsSinceEpoch, equals(1700028800000));
    expect(result.source, equals('Galaxy Watch'));
  });

  test('returns null when channel returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await const WatchSleepService().getLatestSleepData();
    expect(result, isNull);
  });
}
