import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/cycles/cycle_provider.dart';
import 'package:little_signals/features/cycles/data/cycles_api.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/cycles/services/cycle_ongoing_storage.dart';

void main() {
  test('invalid period end before start is not saved', () async {
    var saveCount = 0;
    final provider = CycleProvider(
      cyclesApi: _ValidationCyclesApi(
        onSave: (_) {
          saveCount++;
        },
      ),
      cycleOngoingStore: _FakeCycleOngoingStore(),
    );

    final saved = await provider.savePeriod(
      lastPeriodStart: DateTime(2026, 5, 11),
      periodEndDate: DateTime(2026, 5, 9),
    );

    expect(saved, isFalse);
    expect(saveCount, 0);
    expect(provider.errorMessage, '생리 종료일은 시작일보다 빠를 수 없어요.');
  });

  test('explicit null period end is passed through for clearing', () async {
    Cycle? savedCycle;
    final cyclesApi = _ValidationCyclesApi(
      current: Cycle(
        id: 'cycle-1',
        lastPeriodStart: DateTime(2026, 5, 1),
        periodEndDate: DateTime(2026, 5, 6),
        cycleLength: 28,
        periodLength: 6,
        notes: null,
      ),
      onSave: (cycle) {
        savedCycle = cycle;
      },
    );
    final provider = CycleProvider(
      cyclesApi: cyclesApi,
      cycleOngoingStore: _FakeCycleOngoingStore(),
    );
    await provider.loadCurrentCycle();

    final saved = await provider.savePeriod(
      lastPeriodStart: DateTime(2026, 5, 1),
      periodEndDate: null,
    );

    expect(saved, isTrue);
    expect(cyclesApi.lastChanges, containsPair('period_end_date', null));
    expect(savedCycle?.periodEndDate, isNull);
    expect(provider.currentCycle?.periodEndDate, isNull);
  });

  test(
    'stale backend response fails clear end date instead of reporting success',
    () async {
      final cyclesApi = _ValidationCyclesApi(
        current: Cycle(
          id: 'cycle-1',
          lastPeriodStart: DateTime(2026, 5, 1),
          periodEndDate: DateTime(2026, 5, 6),
          cycleLength: 28,
          periodLength: 6,
          notes: null,
        ),
        ignoreNullPeriodEnd: true,
        onSave: (_) {},
      );
      final provider = CycleProvider(
        cyclesApi: cyclesApi,
        cycleOngoingStore: _FakeCycleOngoingStore(),
      );
      await provider.loadCurrentCycle();

      final saved = await provider.savePeriod(
        lastPeriodStart: DateTime(2026, 5, 1),
        periodEndDate: null,
      );

      expect(saved, isFalse);
      expect(cyclesApi.lastChanges, containsPair('period_end_date', null));
      expect(provider.currentCycle?.periodEndDate, DateTime(2026, 5, 6));
      expect(provider.errorMessage, '생리 종료일을 지우지 못했어요. 다시 시도해 주세요.');
    },
  );

  test('ongoing period flag is applied to current cycle phase', () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 12);
    final ongoingStore = _FakeCycleOngoingStore();
    final cyclesApi = _ValidationCyclesApi(
      current: Cycle(
        id: 'cycle-1',
        lastPeriodStart: start,
        periodEndDate: null,
        cycleLength: 28,
        periodLength: 7,
        notes: null,
      ),
      onSave: (_) {},
    );
    final provider = CycleProvider(
      cyclesApi: cyclesApi,
      cycleOngoingStore: ongoingStore,
    );

    await provider.loadCurrentCycle();
    expect(provider.currentCycle?.periodOngoing, isFalse);
    expect(provider.currentCycle?.phase, isNot('menstrual'));

    final saved = await provider.savePeriod(
      lastPeriodStart: start,
      periodEndDate: null,
      periodOngoing: true,
    );

    expect(saved, isTrue);
    expect(await ongoingStore.isOngoing('cycle-1'), isTrue);
    expect(provider.currentCycle?.periodOngoing, isTrue);
    expect(provider.currentCycle?.phase, 'menstrual');
  });

  test('setting period end clears ongoing period flag', () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 12);
    final ongoingStore = _FakeCycleOngoingStore();
    await ongoingStore.setOngoing('cycle-1', true);
    final cyclesApi = _ValidationCyclesApi(
      current: Cycle(
        id: 'cycle-1',
        lastPeriodStart: start,
        periodEndDate: null,
        cycleLength: 28,
        periodLength: 7,
        notes: null,
      ),
      onSave: (_) {},
    );
    final provider = CycleProvider(
      cyclesApi: cyclesApi,
      cycleOngoingStore: ongoingStore,
    );

    // Server-wins: server returns periodOngoing=false (default), so the
    // provider resets the local cache and reflects the server value.
    await provider.loadCurrentCycle();
    expect(provider.currentCycle?.periodOngoing, isFalse);

    final saved = await provider.savePeriod(
      lastPeriodStart: start,
      periodEndDate: DateTime(now.year, now.month, now.day - 8),
      periodOngoing: true,
    );

    expect(saved, isTrue);
    expect(await ongoingStore.isOngoing('cycle-1'), isFalse);
    expect(provider.currentCycle?.periodOngoing, isFalse);
  });

  test('savePeriod sends is_period_ongoing in PATCH payload', () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 5);
    final cyclesApi = _ValidationCyclesApi(
      current: Cycle(
        id: 'cycle-1',
        lastPeriodStart: start,
        periodEndDate: null,
        cycleLength: 28,
        periodLength: 7,
        notes: null,
      ),
      onSave: (_) {},
    );
    final provider = CycleProvider(
      cyclesApi: cyclesApi,
      cycleOngoingStore: _FakeCycleOngoingStore(),
    );
    await provider.loadCurrentCycle();

    final saved = await provider.savePeriod(
      lastPeriodStart: start,
      periodEndDate: null,
      periodOngoing: true,
    );

    expect(saved, isTrue);
    expect(cyclesApi.lastChanges, containsPair('is_period_ongoing', true));
  });

  test('loadCurrentCycle trusts server is_period_ongoing over local cache',
      () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 5);
    // Local cache says ongoing=true, but server returns periodOngoing=false.
    final ongoingStore = _FakeCycleOngoingStore();
    await ongoingStore.setOngoing('cycle-1', true);
    final cyclesApi = _ValidationCyclesApi(
      current: Cycle(
        id: 'cycle-1',
        lastPeriodStart: start,
        periodEndDate: null,
        cycleLength: 28,
        periodLength: 7,
        notes: null,
        // periodOngoing defaults to false — server says not ongoing
      ),
      onSave: (_) {},
    );
    final provider = CycleProvider(
      cyclesApi: cyclesApi,
      cycleOngoingStore: ongoingStore,
    );

    await provider.loadCurrentCycle();

    // Server wins: provider should reflect server's false, not cache's true.
    expect(provider.currentCycle?.periodOngoing, isFalse);
    // Local store should have been reset to false.
    expect(await ongoingStore.isOngoing('cycle-1'), isFalse);
  });
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

class _ValidationCyclesApi extends CyclesApi {
  Cycle _current;
  final ValueChanged<Cycle> onSave;
  final bool ignoreNullPeriodEnd;
  Map<String, dynamic>? lastChanges;

  _ValidationCyclesApi({
    Cycle? current,
    required this.onSave,
    this.ignoreNullPeriodEnd = false,
  }) : _current =
           current ??
           Cycle(
             id: '',
             lastPeriodStart: DateTime(2026, 5, 1),
             periodEndDate: null,
             cycleLength: 28,
             periodLength: 7,
             notes: null,
           ),
       super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<Cycle?> currentCycle() async => _current.id.isEmpty ? null : _current;

  @override
  Future<List<Cycle>> listCycles() async =>
      _current.id.isEmpty ? const [] : [_current];

  @override
  Future<Cycle> createPeriod(Cycle cycle) async {
    _current = Cycle(
      id: 'cycle-created',
      lastPeriodStart: cycle.lastPeriodStart,
      periodEndDate: cycle.periodEndDate,
      cycleLength: cycle.cycleLength,
      periodLength: cycle.periodLength,
      notes: cycle.notes,
    );
    onSave(_current);
    return _current;
  }

  @override
  Future<Cycle> updateCycle(String id, Map<String, dynamic> changes) async {
    lastChanges = Map<String, dynamic>.from(changes);
    final periodStart = DateTime.tryParse('${changes['period_start_date']}');
    final hasPeriodEnd = changes.containsKey('period_end_date');
    final periodEndRaw = changes['period_end_date'];
    final periodEnd = periodEndRaw == null
        ? null
        : DateTime.tryParse('$periodEndRaw');
    final resolvedPeriodEnd =
        ignoreNullPeriodEnd && hasPeriodEnd && periodEndRaw == null
        ? _current.periodEndDate
        : hasPeriodEnd
        ? periodEnd
        : _current.periodEndDate;
    _current = Cycle(
      id: id,
      lastPeriodStart: periodStart ?? _current.lastPeriodStart,
      periodEndDate: resolvedPeriodEnd,
      cycleLength:
          (changes['cycle_length_days'] as num?)?.round() ??
          _current.cycleLength,
      periodLength: resolvedPeriodEnd == null
          ? 7
          : resolvedPeriodEnd
                    .difference(periodStart ?? _current.lastPeriodStart)
                    .inDays +
                1,
      notes: _current.notes,
    );
    onSave(_current);
    return _current;
  }
}
