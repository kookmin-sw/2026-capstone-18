import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/errors/api_exception.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/cycles/data/cycles_api.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/events/data/events_api.dart';
import 'package:little_signals/features/events/models/stress_event.dart';
import 'package:little_signals/features/insight/data/ai_insights_api.dart';
import 'package:little_signals/features/insight/data/morning_tip.dart';
import 'package:little_signals/features/insight/data/pattern_tip.dart';
import 'package:little_signals/features/insight/data/range_report.dart';
import 'package:little_signals/features/insight/insight_provider.dart';

void main() {
  // A fixed event so the provider has at least one month of data and can build
  // a valid selectedRange without crashing.
  final baseEvent = StressEvent(
    id: 'e1',
    detectedAt: DateTime(2026, 4, 1),
    logged: true,
    stressScore: 3,
    trigger: 'work',
    note: null,
  );

  final stubReport = RangeReport(
    periodStart: DateTime(2026, 4, 1),
    periodEnd: DateTime(2026, 4, 30),
    headline: 'Test headline',
    bodyMd: 'Test body',
    takeaways: const [],
    generatedAt: DateTime(2026, 5, 1),
  );

  /// Builds a provider whose range is April 2026 (single month).
  InsightProvider buildProvider({
    required _FakeAiInsightsApi aiApi,
    bool throwOnList = false,
  }) {
    return InsightProvider(
      eventsApi: _FakeEventsApi([baseEvent], throwOnList: throwOnList),
      cyclesApi: _FakeCyclesApi(),
      aiInsightsApi: aiApi,
    );
  }

  group('range report caching', () {
    test(
      'cache hit — getRangeReport called only once for same range',
      () async {
        final aiApi = _FakeAiInsightsApi(report: stubReport);
        final provider = buildProvider(aiApi: aiApi);

        // Populate events so selectedRange is valid.
        await provider.refresh();

        await provider.loadRangeReport();
        await provider.loadRangeReport();

        expect(aiApi.getRangeReportCallCount, equals(1));
        expect(provider.rangeReport, isNotNull);
        expect(provider.rangeReportLoading, isFalse);
        expect(provider.rangeReportStatus, RangeReportStatus.ready);
        expect(provider.rangeReportMessage, isNull);
      },
    );

    test(
      'refresh clears cache — second loadRangeReport hits API again',
      () async {
        final aiApi = _FakeAiInsightsApi(report: stubReport);
        final provider = buildProvider(aiApi: aiApi);

        await provider.refresh();
        await provider.loadRangeReport();
        expect(aiApi.getRangeReportCallCount, equals(1));

        // refresh() should clear the cache.
        await provider.refresh();
        await provider.loadRangeReport();

        expect(aiApi.getRangeReportCallCount, equals(2));
      },
    );

    test(
      'error handling — rangeReport is null and loading is false on throw',
      () async {
        final aiApi = _FakeAiInsightsApi(report: stubReport, throwOnGet: true);
        final provider = buildProvider(aiApi: aiApi);

        await provider.refresh();
        await provider.loadRangeReport();

        expect(provider.rangeReport, isNull);
        expect(provider.rangeReportLoading, isFalse);
        expect(provider.rangeReportStatus, RangeReportStatus.error);
        expect(provider.rangeReportMessage, contains('불러오지 못했어요'));
      },
    );

    test(
      'empty handling — null report keeps a visible empty message',
      () async {
        final aiApi = _FakeAiInsightsApi(report: null);
        final provider = buildProvider(aiApi: aiApi);

        await provider.refresh();
        await provider.loadRangeReport();

        expect(provider.rangeReport, isNull);
        expect(provider.rangeReportLoading, isFalse);
        expect(provider.rangeReportStatus, RangeReportStatus.empty);
        expect(provider.rangeReportMessage, contains('조금 더 쌓이면'));
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEventsApi extends EventsApi {
  final List<StressEvent> _events;
  final bool throwOnList;

  _FakeEventsApi(this._events, {this.throwOnList = false})
    : super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<List<StressEvent>> listEvents({
    DateTime? start,
    DateTime? end,
    bool? logged,
    String? cyclePhase,
    String? chip,
    String? cursor,
    int limit = 50,
  }) async {
    if (throwOnList) throw const ApiException(message: 'events error');
    return _events;
  }
}

class _FakeCyclesApi extends CyclesApi {
  _FakeCyclesApi()
    : super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<List<Cycle>> listCycles() async => const [];
}

class _FakeAiInsightsApi extends AiInsightsApi {
  final RangeReport? _report;
  final bool throwOnGet;
  int getRangeReportCallCount = 0;

  _FakeAiInsightsApi({required RangeReport? report, this.throwOnGet = false})
    : _report = report,
      super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<MorningTip?> getMorningTip() async => null;

  @override
  Future<PatternTip?> getPatternTip(String patternKey) async => null;

  @override
  Future<RangeReport?> getRangeReport({
    required DateTime frm,
    required DateTime to,
  }) async {
    getRangeReportCallCount++;
    if (throwOnGet) {
      throw const ApiException(message: 'range report error', statusCode: 500);
    }
    return _report;
  }
}
