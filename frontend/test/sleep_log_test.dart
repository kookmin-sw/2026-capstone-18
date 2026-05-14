import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/sleep/data/sleep_api.dart';
import 'package:little_signals/features/sleep/models/sleep_log.dart';

void main() {
  test('SleepLog ignores legacy rating and note fields from backend', () {
    final sleepLog = SleepLog.fromJson({
      'id': 'sleep-1',
      'fell_asleep_at': '2026-05-08T23:30:00.000',
      'woke_up_at': '2026-05-09T06:45:00.000',
      'ended_on': '2026-05-09',
      'sleep_quality': 'very_good',
      'note': 'legacy diary text',
    });

    expect(sleepLog.id, 'sleep-1');
    expect(sleepLog.durationLabel, '7시간 15분');
  });

  test('SleepLog create payload includes backend-required default rating', () {
    final sleepLog = SleepLog(
      id: 'sleep-1',
      fellAsleepAt: DateTime(2026, 5, 8, 23, 30),
      wokeUpAt: DateTime(2026, 5, 9, 6, 45),
      endedOn: DateTime(2026, 5, 9),
    );

    expect(
      sleepLog.toCreateJson().keys,
      containsAll(['fell_asleep_at', 'woke_up_at', 'ended_on', 'rating']),
    );
    expect(sleepLog.toCreateJson()['rating'], SleepLog.defaultImportedRating);
    expect(sleepLog.toCreateJson(), isNot(contains('sleep_quality')));
    expect(sleepLog.toCreateJson(), isNot(contains('note')));

    expect(
      sleepLog.toUpdateJson().keys,
      containsAll(['fell_asleep_at', 'woke_up_at']),
    );
    expect(sleepLog.toUpdateJson(), isNot(contains('sleep_quality')));
    expect(sleepLog.toUpdateJson(), isNot(contains('note')));
  });

  test('SleepApi list sends explicit day boundary datetimes', () async {
    Uri? capturedUri;
    final api = SleepApi(
      apiClient: ApiClient(
        tokenStorage: _MemoryTokenStorage(),
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          return http.Response('{"items":[]}', 200);
        }),
      ),
    );
    final start = DateTime(2026, 5, 1);
    final end = DateTime(2026, 5, 31);

    await api.listSleepLogs(start: start, end: end);

    expect(capturedUri, isNotNull);
    expect(
      capturedUri!.queryParameters['start'],
      DateTime(2026, 5, 1).toUtc().toIso8601String(),
    );
    expect(
      capturedUri!.queryParameters['end'],
      DateTime(2026, 5, 31, 23, 59, 59, 999).toUtc().toIso8601String(),
    );
    expect(capturedUri!.queryParameters['limit'], '200');
  });
}

class _MemoryTokenStorage extends SecureTokenStorage {
  @override
  Future<String?> readAccessToken() async => null;
}
