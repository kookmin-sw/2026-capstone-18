import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import 'data/events_api.dart';
import 'models/stress_event.dart';

class EventsProvider extends ChangeNotifier {
  final EventsApi eventsApi;

  bool _loading = false;
  String? _errorMessage;
  List<StressEvent> _events = [];

  EventsProvider({required this.eventsApi});

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  List<StressEvent> get events => List.unmodifiable(_events);

  StressEvent? get latestEvent => _events.isEmpty ? null : _events.first;

  List<StressEvent> get todayEvents {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final list = _events
        .where((event) => !event.detectedAt.isBefore(startOfToday))
        .toList();

    list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return list;
  }

  List<StressEvent> get loggedEvents {
    final list = _events.where((event) => event.isLoggedWithScore).toList();
    list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return list;
  }

  List<StressEvent> get unloggedEvents {
    final list = _events.where((event) => !event.logged).toList();
    list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return list;
  }

  List<StressEvent> get todayUnloggedEvents {
    final list = todayEvents.where((event) => !event.logged).toList();
    list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return list;
  }

  int get todayUnloggedCount => todayUnloggedEvents.length;
  int get unloggedCount => unloggedEvents.length;
  bool get hasPendingLog => unloggedEvents.isNotEmpty;

  StressEvent? get pendingLogEvent {
    if (!hasPendingLog) return null;
    return unloggedEvents.first;
  }

  StressEvent? get latestLoggedEvent {
    final loggedToday = todayEvents
        .where((event) => event.isLoggedWithScore)
        .toList();
    loggedToday.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    if (loggedToday.isEmpty) return null;
    return loggedToday.first;
  }

  int? get latestLoggedScore => latestLoggedEvent?.stressScore;

  String get stressScoreDisplay {
    if (hasPendingLog) return '?';
    return latestLoggedScore?.toString() ?? '';
  }

  bool get hasStressScoreDisplay => stressScoreDisplay.isNotEmpty;

  bool get shouldShowUnknownStressScore {
    return hasPendingLog && latestLoggedScore == null;
  }

  Future<void> loadToday() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      final loaded = await eventsApi.listEvents(start: startOfToday, end: now);

      _events = loaded;
      _sortEvents();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = '스트레스 기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loaded = await eventsApi.listEvents(limit: 200);
      _events = loaded;
      _sortEvents();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = '스트레스 기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<StressEvent?> createEvent({
    required int stressScore,
    required String trigger,
    String? note,
    String? cyclePhase,
    int? cycleDay,
    StressEvent? sourceUnloggedEvent,
  }) async {
    final normalizedTrigger = _normalizeTrigger(trigger);
    final logChips = _logChips(normalizedTrigger);
    final normalizedNote = _normalizeNote(note);

    try {
      final savedEvent = sourceUnloggedEvent == null
          ? await eventsApi.createEvent(
              StressEvent(
                id: '',
                detectedAt: DateTime.now(),
                stressScore: stressScore,
                trigger: normalizedTrigger,
                note: normalizedNote,
                logged: true,
                logChips: logChips,
                logText: normalizedNote,
                cyclePhase: cyclePhase ?? 'unknown',
                cycleDay: cycleDay ?? 0,
                notified: false,
              ),
            )
          : await eventsApi.updateEvent(sourceUnloggedEvent.id, {
              'logged': true,
              'mood_chips': const <String>[],
              'log_chips': logChips,
              'user_stress_level': stressScore,
              if (normalizedNote?.isNotEmpty == true)
                'log_text': normalizedNote,
            });
      final event = _loggedEventFrom(
        savedEvent,
        stressScore: stressScore,
        trigger: normalizedTrigger,
        note: normalizedNote,
      );

      _events = [
        event,
        ..._events.where((existing) => existing.id != event.id),
      ];
      _sortEvents();

      _errorMessage = null;
      notifyListeners();
      return event;
    } on ApiException catch (error) {
      _errorMessage = _createEventErrorMessage(error);
      notifyListeners();
      return null;
    } catch (_) {
      _errorMessage = '기록을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      notifyListeners();
      return null;
    }
  }

  Future<StressEvent?> updateEvent({
    required StressEvent event,
    required int stressScore,
    required String trigger,
    String? note,
  }) async {
    final normalizedTrigger = _normalizeTrigger(trigger);
    final normalizedNote = _normalizeNote(note);
    final logChips = _logChips(normalizedTrigger);

    try {
      final savedEvent = await eventsApi.updateEvent(event.id, {
        'logged': true,
        'mood_chips': const <String>[],
        'log_chips': logChips,
        'user_stress_level': stressScore,
        'log_text': normalizedNote,
      });
      final updatedEvent = _loggedEventFrom(
        savedEvent.id.isEmpty ? event : savedEvent,
        stressScore: stressScore,
        trigger: normalizedTrigger,
        note: normalizedNote,
      );

      _events = [
        updatedEvent,
        ..._events.where((existing) => existing.id != updatedEvent.id),
      ];
      _sortEvents();
      _errorMessage = null;
      notifyListeners();
      return updatedEvent;
    } on ApiException catch (error) {
      _errorMessage = _createEventErrorMessage(error);
      notifyListeners();
      return null;
    } catch (_) {
      _errorMessage = '기록을 수정하지 못했어요. 잠시 후 다시 시도해 주세요.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteEvent(String id) async {
    if (id.trim().isEmpty) {
      _errorMessage = '기록을 삭제하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }

    try {
      await eventsApi.deleteEvent(id);
      _events = _events.where((event) => event.id != id).toList();
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = '기록을 삭제하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }
  }

  void addUnloggedDetection({required DateTime detectedAt}) {
    final event = StressEvent(
      id: 'detected-${detectedAt.millisecondsSinceEpoch}',
      detectedAt: detectedAt,
      stressDetected: true,
      trigger: '',
      note: null,
      logged: false,
      logChips: const [],
      logText: null,
      cyclePhase: 'unknown',
      cycleDay: 0,
      notified: false,
    );

    _events = [event, ..._events];
    _sortEvents();
    notifyListeners();
  }

  void upsertRealtimeEvent(StressEvent event) {
    _events = [event, ..._events.where((existing) => existing.id != event.id)];

    _sortEvents();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _sortEvents() {
    _events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  void clearSessionData() {
    _loading = false;
    _errorMessage = null;
    _events = [];
    notifyListeners();
  }

  StressEvent _loggedEventFrom(
    StressEvent event, {
    required int stressScore,
    required String trigger,
    String? note,
  }) {
    final normalizedTrigger = _normalizeTrigger(trigger);
    final normalizedNote = _normalizeNote(note);

    return StressEvent(
      id: event.id,
      detectedAt: event.detectedAt,
      stressDetected: event.stressDetected,
      cyclePhase: event.cyclePhase,
      cycleDay: event.cycleDay,
      logged: true,
      logChips: _logChips(normalizedTrigger),
      logText: normalizedNote,
      notified: event.notified,
      stressScore: stressScore,
      trigger: normalizedTrigger,
      note: normalizedNote,
    );
  }

  String _normalizeTrigger(String trigger) => trigger.trim();

  String? _normalizeNote(String? note) {
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  List<String> _logChips(String trigger) {
    return trigger.isEmpty ? const <String>[] : <String>[trigger];
  }

  String _createEventErrorMessage(ApiException error) {
    if (error.statusCode == 422) {
      final validationMessage = _firstValidationMessage(error.details);
      return _displayMessage(validationMessage) ?? error.message;
    }

    return error.message;
  }

  String? _displayMessage(String? message) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return RegExp(r'[가-힣]').hasMatch(trimmed) ? trimmed : null;
  }

  String? _firstValidationMessage(Object? details) {
    if (details is! Map<String, dynamic>) return null;

    final validationItems = details['detail'] is List
        ? details['detail'] as List
        : details['errors'] is List
        ? details['errors'] as List
        : null;
    if (validationItems == null || validationItems.isEmpty) return null;

    for (final item in validationItems) {
      if (item is Map<String, dynamic>) {
        final message = item['msg'];
        if (message is String && message.isNotEmpty) return message;
      }
    }

    return null;
  }
}
