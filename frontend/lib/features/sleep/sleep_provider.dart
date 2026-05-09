import 'package:flutter/foundation.dart';

import '../../core/config/api_config.dart';
import '../../core/errors/api_exception.dart';
import '../../core/mock/mock_backend.dart';
import 'data/sleep_api.dart';
import 'models/sleep_log.dart';
import 'services/watch_sleep_service.dart';

class SleepProvider extends ChangeNotifier {
  final SleepApi sleepApi;
  final WatchSleepService watchSleepService;

  bool _loading = false;
  String? _errorMessage;
  SleepLog? _latestLog;
  List<SleepLog> _history = [];

  SleepProvider({required this.sleepApi, WatchSleepService? watchSleepService})
    : watchSleepService = watchSleepService ?? const WatchSleepService();

  bool get loading => _loading;

  String? get errorMessage => _errorMessage;

  String? get message => _errorMessage;

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

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    if (ApiConfig.useMock) {
      _history = MockBackend.sleepLogs;
      _latestLog = _firstOrNull(_sortedByLatest(_history));

      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        sleepApi.getLatestSleepLog(),
        sleepApi.listSleepLogs(),
      ]);

      _latestLog = results[0] as SleepLog?;
      _history = _sortedByLatest(results[1] as List<SleepLog>);

      _latestLog ??= _firstOrNull(_history);
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadLatest() async {
    if (ApiConfig.useMock) {
      _latestLog = _firstOrNull(_sortedByLatest(MockBackend.sleepLogs));

      _errorMessage = null;
      notifyListeners();
      return;
    }

    try {
      _latestLog = await sleepApi.getLatestSleepLog();
      _errorMessage = null;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    notifyListeners();
  }

  Future<void> loadHistory() async {
    if (ApiConfig.useMock) {
      _history = _sortedByLatest(MockBackend.sleepLogs);

      _latestLog ??= _firstOrNull(_history);

      _errorMessage = null;
      notifyListeners();
      return;
    }

    try {
      _history = _sortedByLatest(await sleepApi.listSleepLogs());

      _latestLog ??= _firstOrNull(_history);

      _errorMessage = null;
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

    if (ApiConfig.useMock) {
      final saved = MockBackend.saveSleepLog(sleepLog);

      _upsert(saved);
      _errorMessage = null;

      notifyListeners();
      return true;
    }

    try {
      final saved = await sleepApi.createSleepLog(sleepLog);

      _upsert(saved);
      _errorMessage = null;

      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;

      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSleepLog(SleepLog sleepLog) async {
    if (ApiConfig.useMock) {
      final saved = MockBackend.saveSleepLog(sleepLog);

      _upsert(saved);
      _errorMessage = null;

      notifyListeners();
      return true;
    }

    try {
      final saved = await sleepApi.updateSleepLog(sleepLog);

      _upsert(saved);
      _errorMessage = null;

      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;

      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSleepLog(String id) async {
    if (ApiConfig.useMock) {
      MockBackend.deleteSleepLog(id);

      _history = _history.where((item) => item.id != id).toList();

      _latestLog = _firstOrNull(_sortedByLatest(_history));

      _errorMessage = null;

      notifyListeners();
      return true;
    }

    try {
      await sleepApi.deleteSleepLog(id);

      _history = _history.where((item) => item.id != id).toList();

      _latestLog = _firstOrNull(_sortedByLatest(_history));

      _errorMessage = null;

      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;

      notifyListeners();
      return false;
    }
  }

  Future<bool> syncSleepFromGalaxyWatch() async {
    final data = await watchSleepService.getLatestSleepData();

    if (data == null) {
      _errorMessage = 'Galaxy Watch 수면 동기화는 곧 사용할 수 있어요.';

      notifyListeners();
      return false;
    }

    return saveSleepLog(
      fellAsleepAt: data.fellAsleepAt,
      wokeUpAt: data.wokeUpAt,
      endedOn: data.endedOn,
    );
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
    _latestLog = null;
    _history = [];
    notifyListeners();
  }
}
