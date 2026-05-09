import 'package:flutter/foundation.dart';

import '../../core/config/api_config.dart';
import '../../core/errors/api_exception.dart';
import '../../core/mock/mock_backend.dart';
import '../consent/data/consent_api.dart';
import '../cycles/data/cycles_api.dart';
import '../cycles/models/cycle.dart';
import '../events/data/events_api.dart';
import '../events/models/stress_event.dart';

class HomeProvider extends ChangeNotifier {
  final EventsApi eventsApi;
  final CyclesApi cyclesApi;
  final ConsentApi consentApi;

  bool _loading = false;
  String? _errorMessage;
  List<StressEvent> _todayEvents = [];
  Cycle? _currentCycle;
  ConsentState? _consent;

  HomeProvider({
    required this.eventsApi,
    required this.cyclesApi,
    required this.consentApi,
  });

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  List<StressEvent> get todayEvents => List.unmodifiable(_todayEvents);
  StressEvent? get recentEvent =>
      _todayEvents.isEmpty ? null : _todayEvents.first;
  Cycle? get currentCycle => _currentCycle;
  ConsentState? get consent => _consent;

  int get todayStress {
    final scoredEvents = _todayEvents
        .where((event) => event.isLoggedWithScore)
        .toList();

    if (scoredEvents.isEmpty) return 0;

    final total = scoredEvents.fold<int>(
      0,
      (sum, event) => sum + event.stressScore!,
    );

    return (total / scoredEvents.length).round();
  }

  String get cyclePhase => _currentCycle?.phase ?? '주기 정보 없음';

  double get sleepHours => ApiConfig.useMock && MockBackend.sleepLogs.isNotEmpty
      ? MockBackend.sleepLogs.first.durationHours
      : 0;

  bool get hasSleepData =>
      ApiConfig.useMock && MockBackend.sleepLogs.isNotEmpty;

  int get thisWeekCount {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));

    if (ApiConfig.useMock) {
      return MockBackend.loggedEvents()
          .where((event) => event.detectedAt.isAfter(weekAgo))
          .length;
    }

    return _todayEvents
        .where(
          (event) =>
              event.isLoggedWithScore && event.detectedAt.isAfter(weekAgo),
        )
        .length;
  }

  Future<void> refresh() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    if (ApiConfig.useMock) {
      final events = MockBackend.todayEvents();
      events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

      _todayEvents = events;
      _currentCycle = MockBackend.currentCycle;
      _consent = MockBackend.consent;
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final results = await Future.wait<dynamic>([
        eventsApi.listEvents(start: startOfToday, end: now),
        cyclesApi.currentCycle(),
        consentApi.getConsent(),
      ]);

      final events = results[0] as List<StressEvent>;
      events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

      _todayEvents = events;
      _currentCycle = results[1] as Cycle?;
      _consent = results[2] as ConsentState;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    _loading = false;
    notifyListeners();
  }

  void applyRealtimeEvent(StressEvent event) {
    _todayEvents = [
      event,
      ..._todayEvents.where((item) => item.id != event.id),
    ];
    notifyListeners();
  }

  void clearSessionData() {
    _loading = false;
    _errorMessage = null;
    _todayEvents = [];
    _currentCycle = null;
    _consent = null;
    notifyListeners();
  }
}
