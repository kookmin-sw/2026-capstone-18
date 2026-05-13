import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import '../health/health_connect_exception.dart';
import 'data/sleep_api.dart';
import 'models/sleep_log.dart';
import 'services/watch_sleep_service.dart';

class SleepProvider extends ChangeNotifier {
  final SleepApi sleepApi;
  final WatchSleepService watchSleepService;

  bool _loading = false;
  String? _errorMessage;
  HealthConnectFailureReason? _healthSyncFailureReason;
  SleepLog? _latestLog;
  List<SleepLog> _history = [];

  SleepProvider({required this.sleepApi, WatchSleepService? watchSleepService})
    : watchSleepService = watchSleepService ?? const WatchSleepService();

  bool get loading => _loading;

  String? get errorMessage => _errorMessage;

  String? get message => _errorMessage;

  HealthConnectFailureReason? get healthSyncFailureReason =>
      _healthSyncFailureReason;

  SleepLog? get latestLog => _latestLog;

  List<SleepLog> get history => List.unmodifiable(_history);

  bool get hasData => _latestLog != null || _history.isNotEmpty;

  double get averageHours {
    if (_history.isEmpty) {
      return _latestLog?.durationHours ?? 0;
    }

    final total = _history.fold<double>(
      0,
      (sum, record) => sum + record.durationHours,
    );

    return total / _history.length;
  }

  Future<void> load({DateTime? start, DateTime? end}) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _history = _sortedByLatest(
        await sleepApi.listSleepLogs(start: start, end: end),
      );
      _latestLog = _firstOrNull(_history);
      _healthSyncFailureReason = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadLatest() async {
    try {
      _latestLog = await sleepApi.getLatestSleepLog();
      _errorMessage = null;
      _healthSyncFailureReason = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    notifyListeners();
  }

  Future<void> loadHistory({DateTime? start, DateTime? end}) async {
    try {
      _history = _sortedByLatest(
        await sleepApi.listSleepLogs(start: start, end: end),
      );

      _latestLog = _firstOrNull(_history);

      _errorMessage = null;
      _healthSyncFailureReason = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    notifyListeners();
  }

  Future<bool> saveSleepLog({
    required DateTime fellAsleepAt,
    required DateTime wokeUpAt,
    required DateTime endedOn,
  }) async {
    final sleepLog = SleepLog(
      id: '',
      fellAsleepAt: fellAsleepAt,
      wokeUpAt: wokeUpAt,
      endedOn: endedOn,
    );

    try {
      final saved = await sleepApi.createSleepLog(sleepLog);

      _upsert(saved);
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

  Future<bool> updateSleepLog(SleepLog sleepLog) async {
    try {
      final saved = await sleepApi.updateSleepLog(sleepLog);

      _upsert(saved);
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

  Future<bool> deleteSleepLog(String id) async {
    try {
      await sleepApi.deleteSleepLog(id);

      _history = _history.where((item) => item.id != id).toList();

      _latestLog = _firstOrNull(_sortedByLatest(_history));

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

  Future<bool> syncSleepFromGalaxyWatch() async {
    try {
      final data = await watchSleepService.getLatestSleepData();

      if (data == null) {
        _setHealthSyncError(HealthConnectFailureReason.noData);
        notifyListeners();
        return false;
      }

      return saveSleepLog(
        fellAsleepAt: data.fellAsleepAt,
        wokeUpAt: data.wokeUpAt,
        endedOn: data.endedOn,
      );
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

  Future<bool> requestHealthConnectPermission() async {
    try {
      final granted = await watchSleepService.requestPermission();
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

  void _setHealthSyncError(HealthConnectFailureReason reason) {
    _healthSyncFailureReason = reason;
    _errorMessage = switch (reason) {
      HealthConnectFailureReason.permissionDenied => '건강 데이터 접근 권한이 필요해요.',
      HealthConnectFailureReason.noData => '불러올 수면 기록이 아직 없어요.',
      HealthConnectFailureReason.unavailable => '이 기기에서는 건강 데이터 연동을 사용할 수 없어요.',
      HealthConnectFailureReason.nativeError =>
        '수면 데이터를 동기화하지 못했어요. 다시 시도해 주세요.',
    };
  }

  void _upsert(SleepLog sleepLog) {
    _history = [sleepLog, ..._history.where((item) => item.id != sleepLog.id)];

    _history = _sortedByLatest(_history);

    _latestLog = _firstOrNull(_history);
  }

  List<SleepLog> _sortedByLatest(List<SleepLog> records) {
    return [...records]..sort((a, b) => b.endedOn.compareTo(a.endedOn));
  }

  SleepLog? _firstOrNull(List<SleepLog> records) {
    if (records.isEmpty) return null;

    return records.first;
  }

  void clearSessionData() {
    _loading = false;
    _errorMessage = null;
    _healthSyncFailureReason = null;
    _latestLog = null;
    _history = [];
    notifyListeners();
  }
}
