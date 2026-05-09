import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_text_styles.dart';
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
    return _phaseColor(_getPhase(day)).withValues(alpha: 0.45);
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


                      _GlassCard(
                        child: Column(
                          children: [

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _focusedMonth = DateTime(
                                      _focusedMonth.year,
                                      _focusedMonth.month - 1,
                                    );
                                  }),
                                  child: const Icon(
                                    Icons.chevron_left,
                                    color: Color(0xFF9888A0),
                                  ),
                                ),
                                Text(
                                  koMonthLabel(_focusedMonth),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF201C28),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _focusedMonth = DateTime(
                                      _focusedMonth.year,
                                      _focusedMonth.month + 1,
                                    );
                                  }),
                                  child: const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF9888A0),
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


                            _buildCalendarGrid(insight),
                            const SizedBox(height: 12),


                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _LegendItem(
                                  color: const Color(0xFFFFDAD5),
                                  label: '생리기',
                                ),
                                _LegendItem(
                                  color: const Color(0xFFF2DCF3),
                                  label: '난포기',
                                ),
                                _LegendItem(
                                  color: const Color(0xFFDDEDF8),
                                  label: '배란기',
                                ),
                                _LegendItem(
                                  color: const Color(
                                    0xFF94D0BC,
                                  ).withValues(alpha: 0.5),
                                  label: '황체기',
                                ),
                              ],
                            ),
                          ],
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
                                  color: const Color(0xFFFFDAD5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.sync,
                                  color: Color(0xFFB87888),
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
                                          : '${koPhase(report.peakStressPhase!)}에 스트레스가 가장 높았어요.',
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
                                  color: const Color(0xFFF2DCF3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.bar_chart,
                                  color: Color(0xFF9888A0),
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

  Widget _buildCalendarGrid(InsightProvider insight) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;

    final startOffset = firstDay.weekday - 1;

    List<Widget> cells = [];


    for (int i = 0; i < startOffset; i++) {
      cells.add(const SizedBox());
    }


    for (int day = 1; day <= daysInMonth; day++) {
      final isSelected = _selectedDay == day;
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
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
                  month: _focusedMonth.month,
                  year: _focusedMonth.year,
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
}

Color _phaseColor(String phase) {
  return switch (InsightAnalyticsService.normalizePhase(phase)) {
    'menstrual' => const Color(0xFFFFDAD5),
    'follicular' => const Color(0xFFF2DCF3),
    'ovulation' => const Color(0xFFDDEDF8),
    'luteal' => const Color(0xFF94D0BC),
    _ => const Color(0xFFE8E0EC),
  };
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(padding: const EdgeInsets.all(16), child: child);
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
