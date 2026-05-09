import '../../features/auth/data/app_user.dart';
import '../../features/consent/data/consent_api.dart';
import '../../features/cycles/models/cycle.dart';
import '../../features/events/models/stress_event.dart';
import '../../features/settings/data/settings_api.dart';
import '../../features/sleep/models/sleep_log.dart';

enum CyclePhase { menstrual, follicular, ovulation, luteal }

class CyclePhaseCalculator {
  static CyclePhase currentPhase({
    required DateTime lastPeriodStart,
    required int cycleLength,
    required int periodLength,
  }) {
    final daysSince =
        DateTime.now().difference(lastPeriodStart).inDays % cycleLength;
    final cycleDay = daysSince + 1;

    if (cycleDay <= periodLength) return CyclePhase.menstrual;

    final ovulationDay = cycleLength - 14;

    if (cycleDay <= ovulationDay - 3) return CyclePhase.follicular;
    if (cycleDay <= ovulationDay + 3) return CyclePhase.ovulation;

    return CyclePhase.luteal;
  }

  static int currentCycleDay({
    required DateTime lastPeriodStart,
    required int cycleLength,
  }) {
    return DateTime.now().difference(lastPeriodStart).inDays % cycleLength + 1;
  }

  static int daysUntilNextPeriod({
    required DateTime lastPeriodStart,
    required int cycleLength,
  }) {
    return cycleLength -
        currentCycleDay(
          lastPeriodStart: lastPeriodStart,
          cycleLength: cycleLength,
        ) +
        1;
  }

  static String phaseName(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return 'menstrual';
      case CyclePhase.follicular:
        return 'follicular';
      case CyclePhase.ovulation:
        return 'ovulation';
      case CyclePhase.luteal:
        return 'luteal';
    }
  }

  static String phaseDescription(CyclePhase phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return '생리가 시작됐어요. 오늘은 몸을 조금 더 편하게 돌봐 주세요.';
      case CyclePhase.follicular:
        return '에너지가 서서히 올라오는 시기예요. 가벼운 계획을 시작하기 좋아요.';
      case CyclePhase.ovulation:
        return '몸과 마음이 비교적 선명하게 느껴질 수 있는 시기예요.';
      case CyclePhase.luteal:
        return '스트레스에 조금 더 민감해질 수 있어요. 무리하지 않아도 괜찮아요.';
    }
  }
}

class MockBackend {
  static final AppUser user = AppUser(
    id: 'mock-user-1',
    email: 'minji@littlesignals.app',
    name: '민지',
    accountType: 'anonymous',
    consent: const {
      'raw_biosignal_consent': true,
      'notification_consent': true,
    },
    settings: const {'data_retention_days': 365, 'watch_status': 'Connected'},
  );

  static UserSettings settings = const UserSettings(
    notificationMaxPerDay: 5,
    stressThreshold: 0.75,
    quietHoursStart: '22:00:00',
    quietHoursEnd: '08:00:00',
    silenceDuringMeeting: true,
    silenceDuringExercise: true,
    consentAuditLogging: true,
    sleepNudgeEnabled: true,
    language: 'ko',
  );

  static ConsentState consent = const ConsentState(
    rawBiosignalConsent: true,
    auditLoggingConsent: true,
    privacyPolicyVersion: '2026.05',
  );

  static Cycle currentCycle = Cycle(
    id: 'mock-cycle-1',
    lastPeriodStart: DateTime(2026, 4, 16),
    periodEndDate: DateTime(2026, 4, 20),
    cycleLength: 28,
    periodLength: 5,
    notes: '',
  );

  static CyclePhase get currentPhase => CyclePhaseCalculator.currentPhase(
    lastPeriodStart: currentCycle.lastPeriodStart,
    cycleLength: currentCycle.cycleLength,
    periodLength: currentCycle.periodLength,
  );

  static int get currentCycleDay => CyclePhaseCalculator.currentCycleDay(
    lastPeriodStart: currentCycle.lastPeriodStart,
    cycleLength: currentCycle.cycleLength,
  );

  static int get daysUntilNextPeriod =>
      CyclePhaseCalculator.daysUntilNextPeriod(
        lastPeriodStart: currentCycle.lastPeriodStart,
        cycleLength: currentCycle.cycleLength,
      );

  static String get currentPhaseName =>
      CyclePhaseCalculator.phaseName(currentPhase);

  static String get currentPhaseDescription =>
      CyclePhaseCalculator.phaseDescription(currentPhase);

  static final List<Cycle> cycleHistory = [
    Cycle(
      id: 'cycle-3',
      lastPeriodStart: DateTime(2026, 4, 16),
      periodEndDate: DateTime(2026, 4, 20),
      cycleLength: 28,
      periodLength: 5,
      notes: '',
    ),
    Cycle(
      id: 'cycle-2',
      lastPeriodStart: DateTime(2026, 3, 19),
      periodEndDate: DateTime(2026, 3, 23),
      cycleLength: 28,
      periodLength: 5,
      notes: '',
    ),
    Cycle(
      id: 'cycle-1',
      lastPeriodStart: DateTime(2026, 2, 19),
      periodEndDate: DateTime(2026, 2, 23),
      cycleLength: 28,
      periodLength: 5,
      notes: '',
    ),
    Cycle(
      id: 'cycle-0',
      lastPeriodStart: DateTime(2026, 1, 22),
      periodEndDate: DateTime(2026, 1, 26),
      cycleLength: 28,
      periodLength: 5,
      notes: '',
    ),
    Cycle(
      id: 'cycle-dec',
      lastPeriodStart: DateTime(2025, 12, 25),
      periodEndDate: DateTime(2025, 12, 29),
      cycleLength: 28,
      periodLength: 5,
      notes: '',
    ),
  ];

  static final List<Map<String, dynamic>> userTriggers = [
    {'name': 'Work', 'color': 0xFFB87888, 'events': 19},
    {'name': 'Social', 'color': 0xFFB7A6D8, 'events': 10},
    {'name': 'Family', 'color': 0xFF94D0BC, 'events': 9},
    {'name': 'School', 'color': 0xFFAED3E8, 'events': 6},
    {'name': 'Health', 'color': 0xFFE7C9A9, 'events': 8},
    {'name': 'Other', 'color': 0xFFD6C6D9, 'events': 0},
  ];

  static final Set<String> deletedDefaultTriggerKeys = {};

  static const List<String> stressTriggerOptions = [
    'Work',
    'Social',
    'Family',
    'School',
    'Health',
    'Other',
  ];

  static void addTrigger(String name, int colorHex) {
    userTriggers.add({'name': name, 'color': colorHex, 'events': 0});
  }

  static void removeTrigger(String name) {
    userTriggers.removeWhere((trigger) => trigger['name'] == name);
  }

  static final List<SleepLog> sleepLogs = [
    SleepLog(
      id: 'sleep-2026-05-07',
      fellAsleepAt: DateTime(2026, 5, 6, 23, 40),
      wokeUpAt: DateTime(2026, 5, 7, 6, 28),
      endedOn: DateTime(2026, 5, 7),
    ),
    SleepLog(
      id: 'sleep-2026-05-06',
      fellAsleepAt: DateTime(2026, 5, 5, 23, 20),
      wokeUpAt: DateTime(2026, 5, 6, 6, 26),
      endedOn: DateTime(2026, 5, 6),
    ),
    SleepLog(
      id: 'sleep-2026-05-05',
      fellAsleepAt: DateTime(2026, 5, 4, 23, 55),
      wokeUpAt: DateTime(2026, 5, 5, 6, 19),
      endedOn: DateTime(2026, 5, 5),
    ),
    SleepLog(
      id: 'sleep-2026-05-04',
      fellAsleepAt: DateTime(2026, 5, 3, 22, 58),
      wokeUpAt: DateTime(2026, 5, 4, 6, 28),
      endedOn: DateTime(2026, 5, 4),
    ),
  ];

  static SleepLog saveSleepLog(SleepLog sleepLog) {
    final saved = sleepLog.id.isEmpty
        ? sleepLog.copyWith(
            id: 'sleep-${sleepLog.endedOn.year}-${sleepLog.endedOn.month}-${sleepLog.endedOn.day}',
          )
        : sleepLog;
    sleepLogs.removeWhere((item) => item.id == saved.id);
    sleepLogs.insert(0, saved);
    sleepLogs.sort((a, b) => b.endedOn.compareTo(a.endedOn));
    return saved;
  }

  static void deleteSleepLog(String id) {
    sleepLogs.removeWhere((item) => item.id == id);
  }

  static final List<StressEvent> events = [
    StressEvent(
      id: 'unlogged-today-1',
      detectedAt: DateTime.now().subtract(const Duration(hours: 2)),
      cyclePhase: currentPhaseName.toLowerCase(),
      cycleDay: currentCycleDay,
      stressScore: null,
      stressDetected: true,
      trigger: '',
      note: null,
      logged: false,

      logChips: const [],
      logText: null,
      notified: true,
    ),
    StressEvent(
      id: 'event-24',
      detectedAt: DateTime(2026, 5, 7, 14, 20),
      cyclePhase: 'luteal',
      cycleDay: 22,
      stressScore: 72,
      trigger: 'Work',
      note: '회의 준비가 예상보다 길어졌어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '회의 준비가 예상보다 길어졌어요.',
    ),
    StressEvent(
      id: 'event-23',
      detectedAt: DateTime(2026, 5, 7, 9, 45),
      cyclePhase: 'luteal',
      cycleDay: 22,
      stressScore: 65,
      trigger: 'Family',
      note: '아침 일정 조율에 시간이 조금 더 걸렸어요.',
      logged: true,
      logChips: const ['Family'],
      logText: '아침 일정 조율에 시간이 조금 더 걸렸어요.',
    ),
    StressEvent(
      id: 'event-22',
      detectedAt: DateTime(2026, 5, 5, 18, 15),
      cyclePhase: 'luteal',
      cycleDay: 20,
      stressScore: 58,
      trigger: 'Social',
      note: '사람이 많은 카페에서 집중하기 어려웠어요.',
      logged: true,
      logChips: const ['Social'],
      logText: '사람이 많은 카페에서 집중하기 어려웠어요.',
    ),
    StressEvent(
      id: 'event-21',
      detectedAt: DateTime(2026, 5, 3, 16, 5),
      cyclePhase: 'luteal',
      cycleDay: 18,
      stressScore: 74,
      trigger: 'Work',
      note: '마감 일정이 갑자기 앞당겨졌어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '마감 일정이 갑자기 앞당겨졌어요.',
    ),
    StressEvent(
      id: 'event-20',
      detectedAt: DateTime(2026, 4, 30, 13, 10),
      cyclePhase: 'ovulation',
      cycleDay: 15,
      stressScore: 46,
      trigger: 'School',
      note: '',
      logged: true,
      logChips: const ['School'],
      logText: '',
    ),
    StressEvent(
      id: 'event-19',
      detectedAt: DateTime(2026, 4, 28, 11, 30),
      cyclePhase: 'follicular',
      cycleDay: 13,
      stressScore: 42,
      trigger: 'Social',
      note: '',
      logged: true,
      logChips: const ['Social'],
      logText: '',
    ),
    StressEvent(
      id: 'event-18',
      detectedAt: DateTime(2026, 4, 24, 17, 45),
      cyclePhase: 'follicular',
      cycleDay: 9,
      stressScore: 52,
      trigger: 'Work',
      note: '리뷰 회의가 길게 이어졌어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '리뷰 회의가 길게 이어졌어요.',
    ),
    StressEvent(
      id: 'event-17',
      detectedAt: DateTime(2026, 4, 20, 20, 10),
      cyclePhase: 'menstrual',
      cycleDay: 5,
      stressScore: 69,
      trigger: 'Health',
      note: '복통과 피로감이 함께 느껴졌어요.',
      logged: true,
      logChips: const ['Health'],
      logText: '복통과 피로감이 함께 느껴졌어요.',
    ),
    StressEvent(
      id: 'event-16',
      detectedAt: DateTime(2026, 4, 18, 10, 0),
      cyclePhase: 'menstrual',
      cycleDay: 3,
      stressScore: 81,
      trigger: 'Health',
      note: '잠을 깊게 자지 못했고 두통이 있었어요.',
      logged: true,
      logChips: const ['Health'],
      logText: '잠을 깊게 자지 못했고 두통이 있었어요.',
    ),
    StressEvent(
      id: 'event-15',
      detectedAt: DateTime(2026, 4, 12, 15, 0),
      cyclePhase: 'luteal',
      cycleDay: 25,
      stressScore: 77,
      trigger: 'Work',
      note: '해야 할 일이 한 번에 많이 몰렸어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '해야 할 일이 한 번에 많이 몰렸어요.',
    ),
    StressEvent(
      id: 'event-14',
      detectedAt: DateTime(2026, 4, 9, 12, 20),
      cyclePhase: 'luteal',
      cycleDay: 22,
      stressScore: 63,
      trigger: 'Family',
      note: '',
      logged: true,
      logChips: const ['Family'],
      logText: '',
    ),
    StressEvent(
      id: 'event-13',
      detectedAt: DateTime(2026, 4, 4, 19, 30),
      cyclePhase: 'luteal',
      cycleDay: 17,
      stressScore: 71,
      trigger: 'Work',
      note: '월요일 일정에 대한 늦은 메시지를 받았어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '월요일 일정에 대한 늦은 메시지를 받았어요.',
    ),
    StressEvent(
      id: 'event-12',
      detectedAt: DateTime(2026, 3, 31, 14, 5),
      cyclePhase: 'ovulation',
      cycleDay: 13,
      stressScore: 49,
      trigger: 'Social',
      note: '',
      logged: true,
      logChips: const ['Social'],
      logText: '',
    ),
    StressEvent(
      id: 'event-11',
      detectedAt: DateTime(2026, 3, 27, 9, 55),
      cyclePhase: 'follicular',
      cycleDay: 9,
      stressScore: 38,
      trigger: 'School',
      note: '',
      logged: true,
      logChips: const ['School'],
      logText: '',
    ),
    StressEvent(
      id: 'event-10',
      detectedAt: DateTime(2026, 3, 23, 16, 35),
      cyclePhase: 'menstrual',
      cycleDay: 5,
      stressScore: 61,
      trigger: 'Health',
      note: '',
      logged: true,
      logChips: const ['Health'],
      logText: '',
    ),
    StressEvent(
      id: 'event-9',
      detectedAt: DateTime(2026, 3, 21, 11, 25),
      cyclePhase: 'menstrual',
      cycleDay: 3,
      stressScore: 67,
      trigger: 'Family',
      note: '',
      logged: true,
      logChips: const ['Family'],
      logText: '',
    ),
    StressEvent(
      id: 'event-8',
      detectedAt: DateTime(2026, 3, 16, 18, 50),
      cyclePhase: 'luteal',
      cycleDay: 26,
      stressScore: 79,
      trigger: 'Work',
      note: '주말 전 마감이 부담스럽게 느껴졌어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '주말 전 마감이 부담스럽게 느껴졌어요.',
    ),
    StressEvent(
      id: 'event-7',
      detectedAt: DateTime(2026, 3, 12, 13, 5),
      cyclePhase: 'luteal',
      cycleDay: 22,
      stressScore: 73,
      trigger: 'Work',
      note: '',
      logged: true,
      logChips: const ['Work'],
      logText: '',
    ),
    StressEvent(
      id: 'event-6',
      detectedAt: DateTime(2026, 3, 8, 20, 15),
      cyclePhase: 'luteal',
      cycleDay: 18,
      stressScore: 64,
      trigger: 'Social',
      note: '',
      logged: true,
      logChips: const ['Social'],
      logText: '',
    ),
    StressEvent(
      id: 'event-5',
      detectedAt: DateTime(2026, 3, 3, 10, 45),
      cyclePhase: 'ovulation',
      cycleDay: 13,
      stressScore: 44,
      trigger: 'School',
      note: '',
      logged: true,
      logChips: const ['School'],
      logText: '',
    ),
    StressEvent(
      id: 'event-4',
      detectedAt: DateTime(2026, 2, 28, 16, 0),
      cyclePhase: 'follicular',
      cycleDay: 10,
      stressScore: 48,
      trigger: 'Work',
      note: '',
      logged: true,
      logChips: const ['Work'],
      logText: '',
    ),
    StressEvent(
      id: 'event-3',
      detectedAt: DateTime(2026, 2, 23, 12, 10),
      cyclePhase: 'menstrual',
      cycleDay: 5,
      stressScore: 59,
      trigger: 'Health',
      note: '',
      logged: true,
      logChips: const ['Health'],
      logText: '',
    ),
    StressEvent(
      id: 'event-2',
      detectedAt: DateTime(2026, 2, 20, 15, 20),
      cyclePhase: 'menstrual',
      cycleDay: 2,
      stressScore: 55,
      trigger: 'Family',
      note: '',
      logged: true,
      logChips: const ['Family'],
      logText: '',
    ),
    StressEvent(
      id: 'event-1',
      detectedAt: DateTime(2026, 2, 16, 9, 15),
      cyclePhase: 'luteal',
      cycleDay: 26,
      stressScore: 76,
      trigger: 'Work',
      note: '',
      logged: true,
      logChips: const ['Work'],
      logText: '',
    ),
    StressEvent(
      id: 'event-jan-4',
      detectedAt: DateTime(2026, 1, 28, 16, 10),
      cyclePhase: 'menstrual',
      cycleDay: 7,
      stressScore: 62,
      trigger: 'Health',
      note: '잠을 잘 못 자서 피로감이 남아 있었어요.',
      logged: true,
      logChips: const ['Health'],
      logText: '잠을 잘 못 자서 피로감이 남아 있었어요.',
    ),
    StressEvent(
      id: 'event-jan-3',
      detectedAt: DateTime(2026, 1, 24, 11, 5),
      cyclePhase: 'menstrual',
      cycleDay: 3,
      stressScore: 68,
      trigger: 'Family',
      note: '',
      logged: true,
      logChips: const ['Family'],
      logText: '',
    ),
    StressEvent(
      id: 'event-jan-2',
      detectedAt: DateTime(2026, 1, 16, 13, 40),
      cyclePhase: 'luteal',
      cycleDay: 23,
      stressScore: 78,
      trigger: 'Work',
      note: '예상하지 못한 기획 회의가 생겼어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '예상하지 못한 기획 회의가 생겼어요.',
    ),
    StressEvent(
      id: 'event-jan-1',
      detectedAt: DateTime(2026, 1, 8, 18, 25),
      cyclePhase: 'ovulation',
      cycleDay: 15,
      stressScore: 47,
      trigger: 'Social',
      note: '',
      logged: true,
      logChips: const ['Social'],
      logText: '',
    ),
    StressEvent(
      id: 'event-dec-4',
      detectedAt: DateTime(2025, 12, 30, 10, 15),
      cyclePhase: 'menstrual',
      cycleDay: 6,
      stressScore: 57,
      trigger: 'Health',
      note: '',
      logged: true,
      logChips: const ['Health'],
      logText: '',
    ),
    StressEvent(
      id: 'event-dec-3',
      detectedAt: DateTime(2025, 12, 27, 15, 0),
      cyclePhase: 'menstrual',
      cycleDay: 3,
      stressScore: 64,
      trigger: 'Family',
      note: '',
      logged: true,
      logChips: const ['Family'],
      logText: '',
    ),
    StressEvent(
      id: 'event-dec-2',
      detectedAt: DateTime(2025, 12, 18, 17, 45),
      cyclePhase: 'luteal',
      cycleDay: 22,
      stressScore: 75,
      trigger: 'Work',
      note: '연휴 전 인수인계가 부담스럽게 느껴졌어요.',
      logged: true,
      logChips: const ['Work'],
      logText: '연휴 전 인수인계가 부담스럽게 느껴졌어요.',
    ),
    StressEvent(
      id: 'event-dec-1',
      detectedAt: DateTime(2025, 12, 10, 12, 35),
      cyclePhase: 'ovulation',
      cycleDay: 14,
      stressScore: 43,
      trigger: 'School',
      note: '',
      logged: true,
      logChips: const ['School'],
      logText: '',
    ),
  ];

  static List<StressEvent> todayEvents() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    return events.where((event) => !event.detectedAt.isBefore(start)).toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  static List<StressEvent> allEvents() {
    return List<StressEvent>.from(events)
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  static List<StressEvent> loggedEvents() {
    return events.where((event) => event.isLoggedWithScore).toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  static List<StressEvent> unloggedEvents() {
    return events.where((event) => !event.logged).toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  static int get todayLogCount {
    return todayEvents().where((event) => event.isLoggedWithScore).length;
  }

  static int get todayUnloggedCount {
    return todayEvents().where((event) => !event.logged).length;
  }

  static int get thisWeekCount {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));

    return events
        .where(
          (event) =>
              event.isLoggedWithScore && event.detectedAt.isAfter(weekAgo),
        )
        .length;
  }

  static StressEvent createEvent({
    required int stressScore,
    required String trigger,
    String? note,
  }) {
    final normalizedTrigger = trigger.trim();
    final logChips = normalizedTrigger.isEmpty
        ? const <String>[]
        : <String>[normalizedTrigger];
    final event = StressEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      detectedAt: DateTime.now(),
      stressScore: stressScore,
      trigger: normalizedTrigger,
      note: note,
      logged: true,
      cyclePhase: currentPhaseName.toLowerCase(),
      cycleDay: currentCycleDay,
      logChips: logChips,
      logText: note,
      notified: false,
    );

    events.insert(0, event);

    final index = userTriggers.indexWhere(
      (item) => item['name'] == normalizedTrigger,
    );
    if (index != -1 && normalizedTrigger.isNotEmpty) {
      userTriggers[index]['events'] =
          (userTriggers[index]['events'] as int) + 1;
    }

    return event;
  }

  static StressEvent addUnloggedEvent({required DateTime detectedAt}) {
    final event = StressEvent(
      id: 'unlogged-${DateTime.now().microsecondsSinceEpoch}',
      detectedAt: detectedAt,
      stressDetected: true,
      trigger: '',
      note: null,
      logged: false,
      stressScore: null,
      cyclePhase: currentPhaseName.toLowerCase(),
      cycleDay: currentCycleDay,
      logChips: const [],
      logText: null,
      notified: true,
    );

    events.insert(0, event);
    return event;
  }

  static StressEvent logDetectedEvent({
    required String id,
    required int stressScore,
    required String trigger,
    String? note,
  }) {
    final index = events.indexWhere((event) => event.id == id);
    if (index == -1) {
      throw StateError('Unlogged event not found.');
    }

    final normalizedTrigger = trigger.trim();
    final logChips = normalizedTrigger.isEmpty
        ? const <String>[]
        : <String>[normalizedTrigger];
    final sourceEvent = events[index];
    final loggedEvent = StressEvent(
      id: sourceEvent.id,
      detectedAt: sourceEvent.detectedAt,
      stressDetected: sourceEvent.stressDetected,
      cyclePhase: sourceEvent.cyclePhase,
      cycleDay: sourceEvent.cycleDay,
      logged: true,
      stressScore: stressScore,
      trigger: normalizedTrigger,
      note: note,
      logChips: logChips,
      logText: note,
      notified: sourceEvent.notified,
    );

    events[index] = loggedEvent;

    final triggerIndex = userTriggers.indexWhere(
      (item) => item['name'] == normalizedTrigger,
    );
    if (triggerIndex != -1 && normalizedTrigger.isNotEmpty) {
      userTriggers[triggerIndex]['events'] =
          (userTriggers[triggerIndex]['events'] as int) + 1;
    }

    return loggedEvent;
  }

  static StressEvent updateEvent({
    required String id,
    required int stressScore,
    required String trigger,
    String? note,
  }) {
    final index = events.indexWhere((event) => event.id == id);
    if (index == -1) {
      throw StateError('Event not found.');
    }

    final normalizedTrigger = trigger.trim();
    final logChips = normalizedTrigger.isEmpty
        ? const <String>[]
        : <String>[normalizedTrigger];
    final sourceEvent = events[index];
    final updatedEvent = StressEvent(
      id: sourceEvent.id,
      detectedAt: sourceEvent.detectedAt,
      stressDetected: sourceEvent.stressDetected,
      cyclePhase: sourceEvent.cyclePhase,
      cycleDay: sourceEvent.cycleDay,
      logged: true,
      logChips: logChips,
      logText: note,
      notified: sourceEvent.notified,
      stressScore: stressScore,
      trigger: normalizedTrigger,
      note: note,
    );

    events[index] = updatedEvent;
    return updatedEvent;
  }

  static Cycle saveCycle({
    required DateTime lastPeriodStart,
    DateTime? periodEndDate,
    required int cycleLength,
    required int periodLength,
    String? notes,
  }) {
    currentCycle = Cycle(
      id: currentCycle.id,
      lastPeriodStart: lastPeriodStart,
      periodEndDate: periodEndDate,
      cycleLength: cycleLength,
      periodLength: periodLength,
      notes: notes,
    );

    cycleHistory.removeWhere(
      (cycle) =>
          cycle.lastPeriodStart.year == lastPeriodStart.year &&
          cycle.lastPeriodStart.month == lastPeriodStart.month &&
          cycle.lastPeriodStart.day == lastPeriodStart.day,
    );

    cycleHistory.insert(0, currentCycle);
    cycleHistory.sort((a, b) => b.lastPeriodStart.compareTo(a.lastPeriodStart));

    return currentCycle;
  }

  static UserSettings updateSettings(Map<String, dynamic> changes) {
    settings = UserSettings(
      notificationMaxPerDay:
          (changes['notification_max_per_day'] as num?)?.round() ??
          settings.notificationMaxPerDay,
      stressThreshold:
          (changes['stress_threshold'] as num?)?.toDouble() ??
          settings.stressThreshold,
      quietHoursStart:
          changes['quiet_hours_start'] as String? ?? settings.quietHoursStart,
      quietHoursEnd:
          changes['quiet_hours_end'] as String? ?? settings.quietHoursEnd,
      silenceDuringMeeting:
          changes['silence_during_meeting'] as bool? ??
          settings.silenceDuringMeeting,
      silenceDuringExercise:
          changes['silence_during_exercise'] as bool? ??
          settings.silenceDuringExercise,
      consentAuditLogging:
          changes['consent_audit_logging'] as bool? ??
          settings.consentAuditLogging,
      sleepNudgeEnabled:
          changes['sleep_nudge_enabled'] as bool? ??
          changes['notification_consent'] as bool? ??
          settings.sleepNudgeEnabled,
      language: changes['language'] as String? ?? settings.language,
    );

    return settings;
  }

  static ConsentState updateConsent(Map<String, dynamic> changes) {
    consent = ConsentState(
      rawBiosignalConsent:
          changes['consent_raw_biosignals'] as bool? ??
          changes['raw_biosignal_consent'] as bool? ??
          consent.rawBiosignalConsent,
      auditLoggingConsent:
          changes['consent_audit_logging'] as bool? ??
          changes['audit_logging_consent'] as bool? ??
          consent.auditLoggingConsent,
      privacyPolicyVersion:
          changes['privacy_policy_version'] as String? ??
          consent.privacyPolicyVersion,
    );

    return consent;
  }
}
