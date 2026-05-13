import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/cycles/cycle_provider.dart';
import 'package:little_signals/features/cycles/data/cycles_api.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';

void main() {
  test('invalid period end before start is not saved', () async {
    var saveCount = 0;
    final provider = CycleProvider(
      cyclesApi: _ValidationCyclesApi(
        onSave: (_) {
          saveCount++;
        },
      ),
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
    final provider = CycleProvider(cyclesApi: cyclesApi);
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
      final provider = CycleProvider(cyclesApi: cyclesApi);
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
