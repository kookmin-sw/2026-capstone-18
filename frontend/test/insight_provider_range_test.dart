import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/errors/api_exception.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/cycles/data/cycles_api.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/cycles/services/cycle_ongoing_storage.dart';
import 'package:little_signals/features/events/data/events_api.dart';
import 'package:little_signals/features/events/models/stress_event.dart';
import 'package:little_signals/features/insight/data/ai_insights_api.dart';
import 'package:little_signals/features/insight/data/morning_tip.dart';
import 'package:little_signals/features/insight/data/pattern_tip.dart';
import 'package:little_signals/features/insight/data/range_report.dart';
import 'package:little_signals/features/insight/insight_provider.dart';

void main() {
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

  test('refresh keeps backend is_period_ongoing as server truth', () async {
    final now = DateTime.now();
    final cycle = Cycle(
      id: 'cycle-ongoing',
      lastPeriodStart: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 13)),
      periodEndDate: null,
      cycleLength: 28,
      periodLength: 5,
      notes: null,
      periodOngoing: true,
    );
    final event = StressEvent(
      id: 'event-ongoing',
      detectedAt: now,
      logged: true,
      stressScore: 64,
      trigger: 'work',
      note: null,
    );
    final ongoingStore = _FakeCycleOngoingStore();
    final provider = InsightProvider(
      eventsApi: _FakeEventsApi([event]),
      cyclesApi: _FakeCyclesApi(current: cycle, history: [cycle]),
      aiInsightsApi: _FakeAiInsightsApi(report: null),
      cycleOngoingStore: ongoingStore,
    );

    await provider.refresh();

    expect(provider.cycles.single.periodOngoing, isTrue);
    expect(await ongoingStore.isOngoing('cycle-ongoing'), isTrue);
    expect(
      provider.report.phaseDistribution.highestDistributionPhase,
      'menstrual',
    );
  });
}

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
  final Cycle? current;
  final List<Cycle> history;

  _FakeCyclesApi({this.current, this.history = const []})
    : super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<Cycle?> currentCycle() async => current;

  @override
  Future<List<Cycle>> listCycles() async => history;
}

class _FakeCycleOngoingStore extends CycleOngoingStore {
  final Set<String> _ongoingCycleIds = <String>{};

  @override
  Future<bool> isOngoing(String cycleId) async {
    return _ongoingCycleIds.contains(cycleId);
  }

  @override
  Future<void> setOngoing(String cycleId, bool ongoing) async {
    if (ongoing) {
      _ongoingCycleIds.add(cycleId);
    } else {
      _ongoingCycleIds.remove(cycleId);
    }
  }
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
