import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import '../health/health_connect_exception.dart';
import 'data/cycles_api.dart';
import 'models/cycle.dart';
import 'models/watch_cycle_data.dart';
import 'services/watch_cycle_service.dart';

class CycleProvider extends ChangeNotifier {
  final CyclesApi cyclesApi;
  final WatchCycleService watchCycleService;

  bool _loading = false;
  String? _errorMessage;
  HealthConnectFailureReason? _healthSyncFailureReason;
  Cycle? _currentCycle;
  List<Cycle> _cycleHistory = [];

  CycleProvider({required this.cyclesApi, WatchCycleService? watchCycleService})
    : watchCycleService = watchCycleService ?? const WatchCycleService();

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  HealthConnectFailureReason? get healthSyncFailureReason =>
      _healthSyncFailureReason;
  Cycle? get currentCycle => _currentCycle;
  List<Cycle> get cycleHistory => List.unmodifiable(_cycleHistory);
  bool get hasCycleLengthHistory => _cycleIntervals().isNotEmpty;

  int get calculatedCycleLength {
    final intervals = _cycleIntervals();
    if (intervals.isEmpty) return 28;
    final total = intervals.reduce((a, b) => a + b);
    return (total / intervals.length).round();
  }

  List<int> _cycleIntervals() {
    final sorted = [..._cycleHistory]
      ..sort((a, b) => b.lastPeriodStart.compareTo(a.lastPeriodStart));
    if (sorted.length < 2) return const [];

    final intervals = <int>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final diff = sorted[i].lastPeriodStart
          .difference(sorted[i + 1].lastPeriodStart)
          .inDays
          .abs();
      if (diff >= 14 && diff <= 45) intervals.add(diff);
    }

    return intervals;
  }

  Future<void> loadCurrentCycle() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        cyclesApi.currentCycle(),
        cyclesApi.listCycles(),
      ]);
      _currentCycle = results[0] as Cycle?;
      _cycleHistory = results[1] as List<Cycle>;
      _healthSyncFailureReason = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    _loading = false;
    notifyListeners();
  }

  Future<bool> savePeriod({
    required DateTime lastPeriodStart,
    DateTime? periodEndDate,
    int? cycleLength,
    int? periodLength,
  }) async {
    final resolvedCycleLength = cycleLength ?? calculatedCycleLength;
    final resolvedPeriodLength =
        periodLength ?? _periodLength(lastPeriodStart, periodEndDate);

    try {
      final cycle = Cycle(
        id: _currentCycle?.id ?? '',
        lastPeriodStart: lastPeriodStart,
        periodEndDate: periodEndDate,
        cycleLength: resolvedCycleLength,
        periodLength: resolvedPeriodLength,
        notes: _currentCycle?.notes,
      );

      if (_currentCycle != null && _currentCycle!.id.isNotEmpty) {
        _currentCycle = await cyclesApi.updateCycle(_currentCycle!.id, {
          'period_start_date': _date(lastPeriodStart),
          'period_end_date': periodEndDate == null
              ? null
              : _date(periodEndDate),
          'cycle_length_days': resolvedCycleLength,
        });
      } else {
        _currentCycle = await cyclesApi.createPeriod(cycle);
      }
      _cycleHistory = await cyclesApi.listCycles();
      _errorMessage = null;
      _healthSyncFailureReason = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<WatchCycleData?> latestGalaxyWatchCycleData() async {
    try {
      final data = await watchCycleService.getLatestCycleData();
      if (data == null || data.periodEnd == null) {
        _setHealthSyncError(HealthConnectFailureReason.noData);
        return null;
      }

      _errorMessage = null;
      _healthSyncFailureReason = null;
      return data;
    } on HealthConnectException catch (error) {
      _setHealthSyncError(error.reason);
      return null;
    } catch (_) {
      _setHealthSyncError(HealthConnectFailureReason.nativeError);
      return null;
    }
  }

  Future<bool> requestHealthConnectPermission() async {
    try {
      final granted = await watchCycleService.requestPermission();
      if (granted) {
        _errorMessage = null;
        _healthSyncFailureReason = null;
      } else {
        _setHealthSyncError(HealthConnectFailureReason.permissionDenied);
      }
      notifyListeners();
      return granted;
    } on HealthConnectException catch (error) {
      _setHealthSyncError(error.reason);
      notifyListeners();
      return false;
    } catch (_) {
      _setHealthSyncError(HealthConnectFailureReason.nativeError);
      notifyListeners();
      return false;
    }
  }

  Future<bool> syncCycleFromGalaxyWatch() async {
    final data = await latestGalaxyWatchCycleData();
    if (data == null) {
      notifyListeners();
      return false;
    }

    return savePeriod(
      lastPeriodStart: data.periodStart,
      periodEndDate: data.periodEnd,
      cycleLength: data.estimatedCycleLength,
    );
  }

  int _periodLength(DateTime lastPeriodStart, DateTime? periodEndDate) {
    if (periodEndDate == null) return 7;

    final start = DateTime(
      lastPeriodStart.year,
      lastPeriodStart.month,
      lastPeriodStart.day,
    );
    final end = DateTime(
      periodEndDate.year,
      periodEndDate.month,
      periodEndDate.day,
    );
    final length = end.difference(start).inDays + 1;

    return length < 1 ? 1 : length;
  }

  String _date(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.toIso8601String().split('T').first;
  }

  void _setHealthSyncError(HealthConnectFailureReason reason) {
    _healthSyncFailureReason = reason;
    _errorMessage = switch (reason) {
      HealthConnectFailureReason.permissionDenied => '건강 데이터 접근 권한이 필요해요.',
      HealthConnectFailureReason.noData => '불러올 주기 기록이 아직 없어요. 수동으로 입력해 주세요.',
      HealthConnectFailureReason.unavailable => '이 기기에서는 건강 데이터 연동을 사용할 수 없어요.',
      HealthConnectFailureReason.nativeError =>
        '주기 데이터를 동기화하지 못했어요. 다시 시도해 주세요.',
    };
  }

  void clearSessionData() {
    _loading = false;
    _errorMessage = null;
    _healthSyncFailureReason = null;
    _currentCycle = null;
    _cycleHistory = [];
    notifyListeners();
  }
}
