import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cycle_phase_ui.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/insight/insight_provider.dart';
import '../../features/insight/services/insight_analytics_service.dart';

class CycleStressScreen extends StatefulWidget {
  const CycleStressScreen({super.key});

  @override
  State<CycleStressScreen> createState() => _CycleStressScreenState();
}

class _CycleStressScreenState extends State<CycleStressScreen> {
  late DateTime _selectedStartMonth;
  late DateTime _selectedEndMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedStartMonth = DateTime(now.year, now.month);
    _selectedEndMonth = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<InsightProvider>().events.isEmpty) {
        context.read<InsightProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InsightProvider>();
    final range = _selectedRange;
    final report = provider.analyticsService.buildReport(
      events: provider.events,
      cycles: provider.cycles,
      range: range,
    );
    final activePhase = provider.analyticsService.phaseForDate(
      DateTime.now(),
      provider.cycles,
    );
    final distribution = report.phaseDistribution;
    final phaseIntensities = _phaseIntensities(report.phaseAverages);
    final insightText = _cycleStressInsightMessage(
      distribution: distribution,
      intensities: phaseIntensities,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: context.read<InsightProvider>().refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                        const _Header(title: '사이클 × 스트레스'),
                        const SizedBox(height: 20),
                        _CycleRangeSelector(
                          startMonth: _selectedStartMonth,
                          endMonth: _selectedEndMonth,
                          months: _availableMonths(provider),
                          onStartChanged: _selectStartMonth,
                          onEndChanged: _selectEndMonth,
                        ),
                        const SizedBox(height: 16),
                        if (provider.errorMessage != null) ...[
                          _ErrorCard(message: provider.errorMessage!),
                          const SizedBox(height: 14),
                        ],
                        _PhaseDistributionCard(distribution: distribution),
                        const SizedBox(height: 16),
                        _PhaseAveragesCard(
                          intensities: phaseIntensities,
                          activePhase: activePhase,
                        ),
                        const SizedBox(height: 16),
                        _InsightCard(message: insightText),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InsightDateRange get _selectedRange {
    return InsightDateRange(
      start: _selectedStartMonth,
      endExclusive: DateTime(
        _selectedEndMonth.year,
        _selectedEndMonth.month + 1,
      ),
      monthCount: _monthDistance(_selectedStartMonth, _selectedEndMonth) + 1,
    );
  }

  List<DateTime> _availableMonths(InsightProvider provider) {
    final months = <DateTime>{
      ...provider.availableMonths.map(_normalizeMonth),
      _normalizeMonth(DateTime.now()),
      _selectedStartMonth,
      _selectedEndMonth,
    }.toList()..sort();

    final first = months.first;
    final last = months.last;
    return List.generate(
      _monthDistance(first, last) + 1,
      (index) => DateTime(first.year, first.month + index),
    );
  }

  void _selectStartMonth(DateTime month) {
    final normalized = _normalizeMonth(month);
    setState(() {
      _selectedStartMonth = normalized;
      if (_selectedStartMonth.isAfter(_selectedEndMonth)) {
        _selectedEndMonth = normalized;
      }
    });
  }

  void _selectEndMonth(DateTime month) {
    final normalized = _normalizeMonth(month);
    setState(() {
      _selectedEndMonth = normalized;
      if (_selectedEndMonth.isBefore(_selectedStartMonth)) {
        _selectedStartMonth = normalized;
      }
    });
  }

  DateTime _normalizeMonth(DateTime date) => DateTime(date.year, date.month);

  int _monthDistance(DateTime start, DateTime end) {
    return (end.year - start.year) * 12 + end.month - start.month;
  }
}

class _PhaseDistributionCard extends StatelessWidget {
  final PhaseDistribution distribution;

  const _PhaseDistributionCard({required this.distribution});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주기 단계별 스트레스 분포', style: AppTextStyles.cardTitle),
          const SizedBox(height: 6),
          const Text(
            '선택한 기간 동안 기록된 스트레스가 각 주기 단계에 어떤 비율로 분포하는지 보여줍니다.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textM),
          ),
          const SizedBox(height: 18),
          if (distribution.totalLogs == 0)
            const _ChartEmptyState(message: '선택한 기간의 스트레스 기록이 아직 없어요.')
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 166,
                    child: CustomPaint(
                      painter: _PhaseDonutPainter(distribution.items),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              CyclePhaseUi.of(
                                distribution.highestDistributionPhase,
                              ).label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textH,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${distribution.highestDistributionRatio.round()}%',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(child: _PhaseDistributionLegend(distribution)),
              ],
            ),
        ],
      ),
    );
  }
}

class _PhaseDistributionLegend extends StatelessWidget {
  final PhaseDistribution distribution;

  const _PhaseDistributionLegend(this.distribution);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: distribution.items.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: CyclePhaseUi.of(item.phase).color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  CyclePhaseUi.of(item.phase).label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textB,
                  ),
                ),
              ),
              Text(
                '${item.phaseDistributionRatio.round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textM,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PhaseAveragesCard extends StatelessWidget {
  final List<_PhaseIntensityItem> intensities;
  final String? activePhase;

  const _PhaseAveragesCard({
    required this.intensities,
    required this.activePhase,
  });

  @override
  Widget build(BuildContext context) {
    final maxPhaseIntensityScore = intensities.fold<double>(
      0,
      (max, phase) => phase.phaseAverageStressScore > max
          ? phase.phaseAverageStressScore
          : max,
    );

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주기 단계별 평균 강도', style: AppTextStyles.cardTitle),
          const SizedBox(height: 6),
          const Text(
            '각 주기 단계에서 기록된 스트레스 점수의 평균값을 비교합니다.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textM),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 184,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: intensities.map((phase) {
                final isActive = phase.phase == activePhase;
                final phaseIntensityScore = phase.phaseAverageStressScore;
                final barHeightRatio = maxPhaseIntensityScore <= 0
                    ? 0.0
                    : (phaseIntensityScore / maxPhaseIntensityScore).clamp(
                        0.0,
                        1.0,
                      );
                return Expanded(
                  child: _PhaseAverageBar(
                    phase: phase.phase,
                    phaseAverageStressScore: phase.phaseAverageStressScore,
                    phaseLogCount: phase.phaseLogCount,
                    barHeightRatio: barHeightRatio,
                    isActive: isActive,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseAverageBar extends StatelessWidget {
  final String phase;
  final double phaseAverageStressScore;
  final int phaseLogCount;
  final double barHeightRatio;
  final bool isActive;

  const _PhaseAverageBar({
    required this.phase,
    required this.phaseAverageStressScore,
    required this.phaseLogCount,
    required this.barHeightRatio,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    const maxBarHeight = 112.0;
    final hasData = phaseLogCount > 0;
    final barHeight = !hasData || barHeightRatio <= 0
        ? 4.0
        : maxBarHeight * barHeightRatio;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            hasData ? '$phaseLogCount건' : '기록 없음',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: hasData ? 12 : 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textM,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: barHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: CyclePhaseUi.of(phase).color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasData ? '평균 ${phaseAverageStressScore.round()}점' : '-',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textB,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CyclePhaseUi.of(phase).label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textM,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String message;

  const _InsightCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lightbulb,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: AppColors.textB,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleRangeSelector extends StatelessWidget {
  final DateTime startMonth;
  final DateTime endMonth;
  final List<DateTime> months;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  const _CycleRangeSelector({
    required this.startMonth,
    required this.endMonth,
    required this.months,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    final range = InsightDateRange(
      start: startMonth,
      endExclusive: DateTime(endMonth.year, endMonth.month + 1),
      monthCount: _monthDistance(startMonth, endMonth) + 1,
    );

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            koMonthRange(
              start: range.start,
              endExclusive: range.endExclusive,
              monthCount: range.monthCount,
            ),
            style: AppTextStyles.cardTitle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MonthDropdown(
                  label: '시작',
                  value: startMonth,
                  months: months,
                  onChanged: onStartChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MonthDropdown(
                  label: '종료',
                  value: endMonth,
                  months: months,
                  onChanged: onEndChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _monthDistance(DateTime start, DateTime end) {
    return (end.year - start.year) * 12 + end.month - start.month;
  }
}

class _MonthDropdown extends StatelessWidget {
  final String label;
  final DateTime value;
  final List<DateTime> months;
  final ValueChanged<DateTime> onChanged;

  const _MonthDropdown({
    required this.label,
    required this.value,
    required this.months,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: value,
          isExpanded: true,
          itemHeight: 52,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
          items: months.map((month) {
            return DropdownMenuItem<DateTime>(
              value: month,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 9, color: AppColors.textL),
                  ),
                  Text(
                    koMonthLabel(month),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textH,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (month) {
            if (month != null) onChanged(month);
          },
        ),
      ),
    );
  }
}

class _ChartEmptyState extends StatelessWidget {
  final String message;

  const _ChartEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 166,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textM,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back, color: AppColors.textH),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textH,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: AppColors.primary),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(padding: padding, child: child);
  }
}

class _PhaseIntensityItem {
  final String phase;
  final int phaseLogCount;
  final double phaseAverageStressScore;

  const _PhaseIntensityItem({
    required this.phase,
    required this.phaseLogCount,
    required this.phaseAverageStressScore,
  });
}

class _PhaseDonutPainter extends CustomPainter {
  final List<PhaseDistributionItem> items;

  const _PhaseDonutPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<int>(0, (sum, item) => sum + item.phaseLogCount);
    if (total == 0) return;

    final strokeWidth = size.shortestSide * 0.16;
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    var startAngle = -math.pi / 2;

    for (final item in items) {
      if (item.phaseLogCount == 0) continue;
      final sweep = (item.phaseLogCount / total) * math.pi * 2;
      paint.color = CyclePhaseUi.of(item.phase).color;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PhaseDonutPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}

List<_PhaseIntensityItem> _phaseIntensities(List<PhaseAverage> averages) {
  final byPhase = {
    for (final item in averages)
      InsightAnalyticsService.normalizePhase(item.phase): item,
  };

  return [
    for (final phase in CyclePhaseUi.orderedPhases)
      _PhaseIntensityItem(
        phase: phase,
        phaseLogCount: byPhase[phase]?.count ?? 0,
        phaseAverageStressScore: byPhase[phase]?.averageStress ?? 0,
      ),
  ];
}

String _cycleStressInsightMessage({
  required PhaseDistribution distribution,
  required List<_PhaseIntensityItem> intensities,
}) {
  if (distribution.totalLogs < 3) {
    return '기록이 더 쌓이면 주기 단계별 분포와 평균 강도를 함께 분석해드릴게요.';
  }

  final intensityCandidates = intensities
      .where((item) => item.phaseLogCount > 0)
      .toList();
  if (intensityCandidates.isEmpty) {
    return '기록이 더 쌓이면 주기 단계별 분포와 평균 강도를 함께 분석해드릴게요.';
  }

  final highestIntensityPhase = intensityCandidates.reduce((best, current) {
    if (current.phaseAverageStressScore > best.phaseAverageStressScore) {
      return current;
    }
    return best;
  }).phase;
  final highestDistributionPhase = distribution.highestDistributionPhase;
  final highestDistributionRatio = distribution.highestDistributionRatio;

  if (highestDistributionRatio < 40) {
    return '스트레스 기록은 주기 전반에 비교적 고르게 분포했고, 평균 강도는 ${CyclePhaseUi.of(highestIntensityPhase).label}에서 가장 높게 나타났어요.';
  }

  if (highestDistributionPhase == highestIntensityPhase) {
    return '스트레스 기록의 분포와 평균 강도 모두 ${CyclePhaseUi.of(highestDistributionPhase).label}에서 가장 높게 나타났어요.';
  }

  if (highestDistributionRatio >= 50) {
    return '스트레스 기록은 ${CyclePhaseUi.of(highestDistributionPhase).label}에 가장 많이 분포했고, 평균 강도는 ${CyclePhaseUi.of(highestIntensityPhase).label}에서 가장 높게 나타났어요.';
  }

  return '스트레스 기록은 ${CyclePhaseUi.of(highestDistributionPhase).label}에 다소 많이 분포했고, 평균 강도는 ${CyclePhaseUi.of(highestIntensityPhase).label}에서 가장 높게 나타났어요.';
}
