import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/api_exception.dart';
import '../cycles/data/cycles_api.dart';
import '../cycles/models/cycle.dart';
import '../events/data/events_api.dart';
import '../events/models/stress_event.dart';
import 'data/ai_insights_api.dart';
import 'data/range_report.dart';
import 'services/insight_analytics_service.dart';

class InsightProvider extends ChangeNotifier {
  final EventsApi eventsApi;
  final CyclesApi cyclesApi;
  final AiInsightsApi aiInsightsApi;
  final InsightAnalyticsService analyticsService;

  bool _loading = false;
  String? _errorMessage;
  List<StressEvent> _events = [];
  List<Cycle> _cycles = [];
  DateTime? _selectedStartMonth;
  DateTime? _selectedEndMonth;
  RangeReport? _rangeReport;
  bool _rangeReportLoading = false;
  final Map<String, RangeReport> _rangeCache = {};

  InsightProvider({
    required this.eventsApi,
    required this.cyclesApi,
    required this.aiInsightsApi,
    InsightAnalyticsService? analyticsService,
  }) : analyticsService = analyticsService ?? InsightAnalyticsService();

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  RangeReport? get rangeReport => _rangeReport;
  bool get rangeReportLoading => _rangeReportLoading;
  List<StressEvent> get events => List.unmodifiable(_events);
  List<Cycle> get cycles => List.unmodifiable(_cycles);
  List<DateTime> get availableMonths {
    if (_events.isEmpty) {
      final now = DateTime.now();
      return [DateTime(now.year, now.month)];
    }

    final months =
        _events
            .map(
              (event) =>
                  DateTime(event.detectedAt.year, event.detectedAt.month),
            )
            .toSet()
            .toList()
          ..sort();

    final first = months.first;
    final last = months.last;
    return List.generate(
      _monthDistance(first, last) + 1,
      (index) => DateTime(first.year, first.month + index),
    );
  }

  DateTime get selectedStartMonth =>
      _selectedStartMonth ?? availableMonths.first;

  DateTime get selectedEndMonth => _selectedEndMonth ?? availableMonths.last;

  InsightDateRange get selectedRange {
    final start = selectedStartMonth;
    final end = selectedEndMonth;
    return InsightDateRange(
      start: start,
      endExclusive: DateTime(end.year, end.month + 1),
      monthCount: _monthDistance(start, end) + 1,
    );
  }

  InsightReportViewModel get report => analyticsService.buildReport(
    events: _events,
    cycles: _cycles,
    range: selectedRange,
  );

  Future<void> refresh() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        eventsApi.listEvents(logged: true, limit: 200),
        cyclesApi.listCycles(),
      ]);
      _events =
          (results[0] as List<StressEvent>)
              .where((event) => event.isLoggedWithScore)
              .toList()
            ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
      _cycles = results[1] as List<Cycle>;
      _rangeCache.clear();
      _ensureSelectedRange();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    }

    _loading = false;
    notifyListeners();
  }

  void selectStartMonth(DateTime month) {
    final normalized = DateTime(month.year, month.month);
    if (!_containsMonth(normalized)) return;
    _selectedStartMonth = normalized;
    if (normalized.isAfter(selectedEndMonth)) {
      _selectedEndMonth = normalized;
    }
    notifyListeners();
    unawaited(loadRangeReport());
  }

  void selectEndMonth(DateTime month) {
    final normalized = DateTime(month.year, month.month);
    if (!_containsMonth(normalized)) return;
    _selectedEndMonth = normalized;
    if (normalized.isBefore(selectedStartMonth)) {
      _selectedStartMonth = normalized;
    }
    notifyListeners();
    unawaited(loadRangeReport());
  }

  String monthLabel(DateTime month) {
    return '${month.year}년 ${month.month}월';
  }

  TriggerPhaseDetailViewModel detailFor({
    required String trigger,
    required String phase,
  }) {
    return analyticsService.buildDetail(
      events: _events,
      cycles: _cycles,
      range: selectedRange,
      trigger: trigger,
      phase: phase,
    );
  }

  List<StressEvent> eventsForDay(DateTime day) {
    return analyticsService.eventsForDay(events: _events, day: day);
  }

  String phaseForEvent(StressEvent event) {
    return analyticsService.phaseForEvent(event, _cycles);
  }

  int? cycleDayForEvent(StressEvent event) {
    return analyticsService.cycleDayForEvent(event, _cycles);
  }

  Future<void> loadRangeReport() async {
    final frm = selectedRange.start;
    final to = selectedRange.endExclusive.subtract(const Duration(days: 1));
    final key = '${_fmtDate(frm)}|${_fmtDate(to)}';

    final cached = _rangeCache[key];
    if (cached != null) {
      _rangeReport = cached;
      notifyListeners();
      return;
    }

    _rangeReportLoading = true;
    notifyListeners();
    try {
      final fetched = await aiInsightsApi.getRangeReport(frm: frm, to: to);
      if (fetched != null) {
        _rangeCache[key] = fetched;
      }
      _rangeReport = fetched;
    } catch (_) {
      _rangeReport = null;
    } finally {
      _rangeReportLoading = false;
      notifyListeners();
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void clearSessionData() {
    _loading = false;
    _errorMessage = null;
    _events = [];
    _cycles = [];
    _selectedStartMonth = null;
    _selectedEndMonth = null;
    _rangeReport = null;
    _rangeReportLoading = false;
    _rangeCache.clear();
    notifyListeners();
  }

  void _ensureSelectedRange() {
    final months = availableMonths;
    if (months.isEmpty) return;

    if (_selectedStartMonth == null || !_containsMonth(_selectedStartMonth!)) {
      _selectedStartMonth = months.first;
    }
    if (_selectedEndMonth == null || !_containsMonth(_selectedEndMonth!)) {
      _selectedEndMonth = months.last;
    }
    if (_selectedStartMonth!.isAfter(_selectedEndMonth!)) {
      _selectedStartMonth = months.first;
      _selectedEndMonth = months.last;
    }
  }

  bool _containsMonth(DateTime month) {
    return availableMonths.any(
      (item) => item.year == month.year && item.month == month.month,
    );
  }

  int _monthDistance(DateTime start, DateTime end) {
    return (end.year - start.year) * 12 + end.month - start.month;
  }
}
