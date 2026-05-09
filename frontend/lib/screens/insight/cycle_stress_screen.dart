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

class CycleStressScreen extends StatefulWidget {
  const CycleStressScreen({super.key});

  @override
  State<CycleStressScreen> createState() => _CycleStressScreenState();
}

class _CycleStressScreenState extends State<CycleStressScreen> {
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
    final provider = context.watch<InsightProvider>();
    final report = provider.report;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: RefreshIndicator(
          color: const Color(0xFFB87888),
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
                        _RangeSelector(provider: provider),
                        const SizedBox(height: 12),
                        if (provider.errorMessage != null)
                          _ErrorCard(message: provider.errorMessage!)
                        else if (!report.hasData)
                          const _EmptyCard()
                        else ...[
                          Row(
                            children: [
                              _MetricCard(
                                label: '기록',
                                value: '${report.totalEvents}',
                              ),
                              const SizedBox(width: 10),
                              _MetricCard(
                                label: '평균 스트레스',
                                value: report.averageStress.round().toString(),
                              ),
                              const SizedBox(width: 10),
                              _MetricCard(
                                label: '높았던 주기 단계',
                                value: report.peakStressPhase == null
                                    ? '--'
                                    : koPhase(report.peakStressPhase!),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _PhaseComparisonCard(report: report),
                          const SizedBox(height: 12),
                          _GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionTitle(title: '요인 분포'),
                                const SizedBox(height: 12),
                                ...report.triggerRanking.take(5).map((item) {
                                  final share = report.totalEvents == 0
                                      ? 0.0
                                      : item.count / report.totalEvents;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 74,
                                          child: Text(
                                            koTrigger(item.trigger),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF483848),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: share,
                                              minHeight: 8,
                                              backgroundColor: const Color(
                                                0xFFF2DCF3,
                                              ),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(Color(0xFFB87888)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${item.count}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF9888A0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _TriggerPhaseMatrix(report: report),
                        ],
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
}

class _RangeSelector extends StatelessWidget {
  final InsightProvider provider;

  const _RangeSelector({required this.provider});

  @override
  Widget build(BuildContext context) {
    final months = provider.availableMonths;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            koMonthRange(
              start: provider.selectedRange.start,
              endExclusive: provider.selectedRange.endExclusive,
              monthCount: provider.selectedRange.monthCount,
            ),
            style: AppTextStyles.cardTitle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MonthDropdown(
                  label: '시작',
                  value: provider.selectedStartMonth,
                  months: months,
                  onChanged: provider.selectStartMonth,
                  provider: provider,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MonthDropdown(
                  label: '종료',
                  value: provider.selectedEndMonth,
                  months: months,
                  onChanged: provider.selectEndMonth,
                  provider: provider,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthDropdown extends StatelessWidget {
  final String label;
  final DateTime value;
  final List<DateTime> months;
  final ValueChanged<DateTime> onChanged;
  final InsightProvider provider;

  const _MonthDropdown({
    required this.label,
    required this.value,
    required this.months,
    required this.onChanged,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F0F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: value,
          isExpanded: true,
          itemHeight: 52,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFB87888)),
          items: months.map((month) {
            return DropdownMenuItem<DateTime>(
              value: month,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFC0B0C0),
                    ),
                  ),
                  Text(
                    koMonthLabel(month),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF201C28),
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

class _PhaseComparisonCard extends StatelessWidget {
  final InsightReportViewModel report;

  const _PhaseComparisonCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '주기 단계별 흐름'),
          const SizedBox(height: 12),
          ...report.phaseAverages.map((phase) {
            final isPeak = phase.phase == report.peakStressPhase;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(
                          koPhase(phase.phase),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isPeak
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isPeak
                                ? const Color(0xFFB87888)
                                : const Color(0xFF483848),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: phase.value,
                            minHeight: 9,
                            backgroundColor: const Color(0xFFF2DCF3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _phaseColor(phase.phase),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '평균 ${phase.averageStress.round()} · ${phase.count}건',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9888A0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          const _PhaseLegendWrap(),
        ],
      ),
    );
  }
}

class _TriggerPhaseMatrix extends StatelessWidget {
  final InsightReportViewModel report;

  const _TriggerPhaseMatrix({required this.report});

  @override
  Widget build(BuildContext context) {
    final phases = InsightAnalyticsService.phases;
    final maxCount = report.triggerByCyclePhaseMatrix.fold<int>(
      0,
      (max, cell) => cell.count > max ? cell.count : max,
    );

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '주기 단계별 스트레스 요인'),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 72),
              ...phases.map(
                (phase) => Expanded(
                  child: Center(
                    child: Text(
                      koPhaseShort(phase),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF9888A0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...report.triggers.map((trigger) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      koTrigger(trigger),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF483848),
                      ),
                    ),
                  ),
                  ...phases.map((phase) {
                    final cell = report.triggerByCyclePhaseMatrix.firstWhere(
                      (item) => item.trigger == trigger && item.phase == phase,
                    );
                    final alpha = maxCount == 0 || cell.count == 0
                        ? 0.08
                        : 0.18 + (cell.count / maxCount) * 0.58;
                    return Expanded(
                      child: Container(
                        height: 36,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFB87888,
                          ).withValues(alpha: alpha),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            cell.count == 0 ? '' : '${cell.count}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cell.count > maxCount / 2
                                  ? Colors.white
                                  : const Color(0xFF7A3848),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
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
          child: const Icon(Icons.arrow_back, color: Color(0xFF201C28)),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Color(0xFF201C28),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9888A0)),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF201C28),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseLegendWrap extends StatelessWidget {
  const _PhaseLegendWrap();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: InsightAnalyticsService.phases.map((phase) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _phaseColor(phase),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              koPhase(phase),
              style: const TextStyle(fontSize: 9, color: Color(0xFF9888A0)),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return const _GlassCard(
      child: Text(
        '이 기간에는 아직 스트레스 기록이 충분하지 않아요.',
        style: TextStyle(fontSize: 13, color: Color(0xFF9888A0)),
      ),
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
        style: const TextStyle(fontSize: 13, color: Color(0xFFB87888)),
      ),
    );
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

Color _phaseColor(String phase) {
  return switch (InsightAnalyticsService.normalizePhase(phase)) {
    'menstrual' => const Color(0xFFFFDAD5),
    'follicular' => const Color(0xFFF2DCF3),
    'ovulation' => const Color(0xFFDDEDF8),
    'luteal' => const Color(0xFF94D0BC),
    _ => const Color(0xFFE8E0EC),
  };
}
