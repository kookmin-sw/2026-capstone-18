import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cycle_phase_ui.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../features/insight/insight_provider.dart';
import '../../features/insight/services/insight_analytics_service.dart';
import 'day_events_screen.dart';
import 'cycle_stress_screen.dart';
import 'my_report_screen.dart';

class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});

  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int? _selectedDay;

  String _getPhase(int day) {
    if (day <= 5) return 'menstrual';
    if (day <= 13) return 'follicular';
    if (day <= 16) return 'ovulation';
    return 'luteal';
  }

  Color _getPhaseColor(int day) {
    return CyclePhaseUi.of(_getPhase(day)).color.withValues(alpha: 0.45);
  }

  String _topTriggerSummary(TriggerRankingItem? topTrigger) {
    if (topTrigger == null) {
      return '새 기록이 쌓이면 리포트가 업데이트돼요.';
    }

    final triggerName = koTrigger(topTrigger.trigger);
    if (triggerName == '요인 불명') {
      return '요인 불명 기록이 ${topTrigger.count}건으로 가장 많아요.';
    }

    return '$triggerName 관련 기록이 ${topTrigger.count}건으로 가장 많아요.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<InsightProvider>().events.isEmpty) {
        context.read<InsightProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final insight = context.watch<InsightProvider>();
    final report = insight.report;
    final topTrigger = report.triggerRanking.isEmpty
        ? null
        : report.triggerRanking.first;
    final earliestMonth = _earliestCalendarMonth(insight);
    final latestMonth = _latestCalendarMonth();
    final focusedMonth = _clampMonth(
      _focusedMonth,
      min: earliestMonth,
      max: latestMonth,
    );
    if (!_isSameMonth(focusedMonth, _focusedMonth)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _focusedMonth = focusedMonth;
          _selectedDay = null;
        });
      });
    }
    final canGoPrevious = _isAfterMonth(focusedMonth, earliestMonth);
    final canGoNext = _isBeforeMonth(focusedMonth, latestMonth);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('인사이트', style: AppTextStyles.screenTitle),
                      const SizedBox(height: 20),

                      GestureDetector(
                        onHorizontalDragEnd: (details) => _handleCalendarSwipe(
                          details,
                          minMonth: earliestMonth,
                          maxMonth: latestMonth,
                        ),
                        child: _GlassCard(
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _CalendarArrow(
                                    icon: Icons.chevron_left,
                                    enabled: canGoPrevious,
                                    onTap: () => _moveFocusedMonth(
                                      -1,
                                      minMonth: earliestMonth,
                                      maxMonth: latestMonth,
                                    ),
                                  ),
                                  Text(
                                    koMonthLabel(focusedMonth),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF201C28),
                                    ),
                                  ),
                                  _CalendarArrow(
                                    icon: Icons.chevron_right,
                                    enabled: canGoNext,
                                    onTap: () => _moveFocusedMonth(
                                      1,
                                      minMonth: earliestMonth,
                                      maxMonth: latestMonth,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              Row(
                                children: ['월', '화', '수', '목', '금', '토', '일']
                                    .map(
                                      (d) => Expanded(
                                        child: Center(
                                          child: Text(
                                            d,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFFC0B0C0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 8),

                              _buildCalendarGrid(insight, focusedMonth),
                              const SizedBox(height: 12),

                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                children: [
                                  _LegendItem(
                                    color: CyclePhaseUi.of('menstrual').color,
                                    label: CyclePhaseUi.of('menstrual').label,
                                  ),
                                  _LegendItem(
                                    color: CyclePhaseUi.of('follicular').color,
                                    label: CyclePhaseUi.of('follicular').label,
                                  ),
                                  _LegendItem(
                                    color: CyclePhaseUi.of('ovulation').color,
                                    label: CyclePhaseUi.of('ovulation').label,
                                  ),
                                  _LegendItem(
                                    color: CyclePhaseUi.of('luteal').color,
                                    label: CyclePhaseUi.of('luteal').label,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CycleStressScreen(),
                          ),
                        ),
                        child: _GlassCard(
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: CyclePhaseUi.of('menstrual').color,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.sync,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SectionTitle(title: '사이클 × 스트레스'),
                                    const SizedBox(height: 2),
                                    Text(
                                      report.peakStressPhase == null
                                          ? '스트레스 기록이 쌓이면 주기 흐름과 함께 살펴볼 수 있어요.'
                                          : '${CyclePhaseUi.of(report.peakStressPhase!).label}에 스트레스가 가장 높았어요.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9888A0),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFC0B0C0),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyReportScreen(),
                          ),
                        ),
                        child: _GlassCard(
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: CyclePhaseUi.of('follicular').color,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.bar_chart,
                                  color: AppColors.textM,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SectionTitle(title: '나의 리포트'),
                                    const SizedBox(height: 2),
                                    Text(
                                      _topTriggerSummary(topTrigger),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9888A0),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFC0B0C0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(InsightProvider insight, DateTime focusedMonth) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;

    final startOffset = firstDay.weekday - 1;

    List<Widget> cells = [];

    for (int i = 0; i < startOffset; i++) {
      cells.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final isSelected = _selectedDay == day;
      final date = DateTime(focusedMonth.year, focusedMonth.month, day);
      final dayEvents = insight.eventsForDay(date);
      final hasLoggedEvents = dayEvents.isNotEmpty;
      final phaseColor = _getPhaseColor(day);

      cells.add(
        GestureDetector(
          onTap: () {
            setState(() => _selectedDay = day);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DayEventsScreen(
                  day: day,
                  month: focusedMonth.month,
                  year: focusedMonth.year,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFB87888) : phaseColor,
              shape: BoxShape.circle,
              border: isSelected ? null : Border.all(color: Colors.transparent),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : const Color(0xFF483848),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                if (hasLoggedEvents && !isSelected)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB87888),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      children: cells,
    );
  }

  DateTime _earliestCalendarMonth(InsightProvider insight) {
    final currentMonth = _currentMonth();
    final recordMonths = <DateTime>[
      for (final event in insight.events)
        DateTime(event.detectedAt.year, event.detectedAt.month),
      for (final cycle in insight.cycles)
        DateTime(cycle.lastPeriodStart.year, cycle.lastPeriodStart.month),
      for (final cycle in insight.cycles)
        if (cycle.periodEndDate != null)
          DateTime(cycle.periodEndDate!.year, cycle.periodEndDate!.month),
    ];

    if (recordMonths.isEmpty) return currentMonth;
    recordMonths.sort();
    final earliest = recordMonths.first;
    return earliest.isAfter(currentMonth) ? currentMonth : earliest;
  }

  DateTime _latestCalendarMonth() {
    final currentMonth = _currentMonth();
    return DateTime(currentMonth.year, currentMonth.month + 2);
  }

  DateTime _currentMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime _clampMonth(
    DateTime month, {
    required DateTime min,
    required DateTime max,
  }) {
    final normalized = DateTime(month.year, month.month);
    if (_isBeforeMonth(normalized, min)) return min;
    if (_isAfterMonth(normalized, max)) return max;
    return normalized;
  }

  void _moveFocusedMonth(
    int delta, {
    required DateTime minMonth,
    required DateTime maxMonth,
  }) {
    final next = _clampMonth(
      DateTime(_focusedMonth.year, _focusedMonth.month + delta),
      min: minMonth,
      max: maxMonth,
    );
    if (_isSameMonth(next, _focusedMonth)) return;

    setState(() {
      _focusedMonth = next;
      _selectedDay = null;
    });
  }

  void _handleCalendarSwipe(
    DragEndDetails details, {
    required DateTime minMonth,
    required DateTime maxMonth,
  }) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 120) return;
    _moveFocusedMonth(
      velocity < 0 ? 1 : -1,
      minMonth: minMonth,
      maxMonth: maxMonth,
    );
  }

  bool _isBeforeMonth(DateTime first, DateTime second) {
    return first.year < second.year ||
        (first.year == second.year && first.month < second.month);
  }

  bool _isAfterMonth(DateTime first, DateTime second) {
    return first.year > second.year ||
        (first.year == second.year && first.month > second.month);
  }

  bool _isSameMonth(DateTime first, DateTime second) {
    return first.year == second.year && first.month == second.month;
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(padding: const EdgeInsets.all(16), child: child);
  }
}

class _CalendarArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CalendarArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.28,
        child: Icon(icon, color: const Color(0xFF9888A0)),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF9888A0)),
        ),
      ],
    );
  }
}
