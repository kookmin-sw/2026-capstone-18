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
import 'range_report_screen.dart';
import 'report_detail_screen.dart';

class MyReportScreen extends StatefulWidget {
  const MyReportScreen({super.key});

  @override
  State<MyReportScreen> createState() => _MyReportScreenState();
}

class _MyReportScreenState extends State<MyReportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<InsightProvider>().events.isEmpty) {
        context.read<InsightProvider>().refresh();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InsightProvider>().loadRangeReport();
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
                        const _Header(title: '나의 리포트'),
                        const SizedBox(height: 20),
                        _RangeSelector(provider: provider),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final p = context.watch<InsightProvider>();
                            final rangeReport = p.rangeReport;
                            if (p.rangeReportLoading && rangeReport == null) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: _AiReportSkeleton(),
                              );
                            }
                            if (rangeReport == null) {
                              if (p.rangeReportStatus ==
                                      RangeReportStatus.empty ||
                                  p.rangeReportStatus ==
                                      RangeReportStatus.error) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _AiReportStateCard(
                                    message:
                                        p.rangeReportMessage ??
                                        'AI 리포트는 기록이 조금 더 쌓이면 보여드릴게요.',
                                    isError:
                                        p.rangeReportStatus ==
                                        RangeReportStatus.error,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        RangeReportScreen(report: rangeReport),
                                  ),
                                ),
                                child: _GlassCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rangeReport.headline,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF201C28),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (rangeReport.takeaways.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '· ${rangeReport.takeaways.first.title}: ${rangeReport.takeaways.first.body}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF615A6A),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (provider.errorMessage != null)
                          _InfoCard(
                            text: provider.errorMessage!,
                            color: const Color(0xFFB87888),
                          )
                        else if (!report.hasData)
                          const _InfoCard(text: '이 기간에는 아직 살펴볼 데이터가 충분하지 않아요.')
                        else ...[
                          Row(
                            children: [
                              _MetricCard(
                                label: '전체 기록',
                                value: '${report.totalEvents}',
                              ),
                              const SizedBox(width: 10),
                              _MetricCard(
                                label: '평균 스트레스',
                                value: report.averageStress.round().toString(),
                              ),
                              const SizedBox(width: 10),
                              _MetricCard(
                                label: '자주 나타난 일차',
                                value: report.mostCommonCycleDay == null
                                    ? '--'
                                    : '${report.mostCommonCycleDay}일차',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _PhaseDistribution(report: report),
                          const SizedBox(height: 12),
                          _TriggerRanking(report: report),
                          const SizedBox(height: 12),
                          _TriggerMatrix(report: report),
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

class _PhaseDistribution extends StatelessWidget {
  final InsightReportViewModel report;

  const _PhaseDistribution({required this.report});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '기간별 주기 단계 흐름'),
          const SizedBox(height: 12),
          ...report.phaseAverages.map((phase) {
            final share = report.totalEvents == 0
                ? 0.0
                : phase.count / report.totalEvents;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      koPhase(phase.phase),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF483848),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF5F1F6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _phaseColor(phase.phase),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${phase.count}건 · 평균 ${phase.averageStress.round()}',
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
    );
  }
}

class _TriggerRanking extends StatelessWidget {
  final InsightReportViewModel report;

  const _TriggerRanking({required this.report});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '자주 나타난 요인'),
          const SizedBox(height: 12),
          ...report.triggerRanking.take(5).map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      koTrigger(item.trigger),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF201C28),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${item.count}건 · 평균 ${item.averageStress.round()}',
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
    );
  }
}

class _TriggerMatrix extends StatelessWidget {
  final InsightReportViewModel report;

  const _TriggerMatrix({required this.report});

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
          const SectionTitle(title: '스트레스 요인 × 주기 단계'),
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
                    return Expanded(
                      child: GestureDetector(
                        onTap: cell.count == 0
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReportDetailScreen(
                                    trigger: trigger,
                                    phase: phase,
                                  ),
                                ),
                              ),
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _cellColor(cell.count, maxCount),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              cell.count == 0 ? '' : '${cell.count}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cell.count > maxCount / 2
                                    ? Colors.white
                                    : const Color(0xFF7A3848),
                              ),
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

  Color _cellColor(int count, int maxCount) {
    if (count == 0 || maxCount == 0) {
      return const Color(0xFFE8E0EC).withValues(alpha: 0.3);
    }
    final alpha = 0.18 + (count / maxCount) * 0.6;
    return const Color(0xFFB87888).withValues(alpha: alpha);
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

class _InfoCard extends StatelessWidget {
  final String text;
  final Color color;

  const _InfoCard({required this.text, this.color = const Color(0xFF9888A0)});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Text(text, style: TextStyle(fontSize: 13, color: color)),
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

class _AiReportSkeleton extends StatefulWidget {
  const _AiReportSkeleton();

  @override
  State<_AiReportSkeleton> createState() => _AiReportSkeletonState();
}

class _AiReportSkeletonState extends State<_AiReportSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final shimmer = LinearGradient(
            begin: Alignment(-1.5 + _anim.value * 3, 0),
            end: Alignment(-0.5 + _anim.value * 3, 0),
            colors: const [
              Color(0xFFE8DFF0),
              Color(0xFFF5EFF9),
              Color(0xFFE8DFF0),
            ],
            stops: const [0.0, 0.5, 1.0],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // headline placeholder
              Container(
                height: 16,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: shimmer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 10),
              // takeaway placeholder — shorter
              Container(
                height: 12,
                width: 220,
                decoration: BoxDecoration(
                  gradient: shimmer,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB87888).withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'AI 리포트 생성 중…',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB09AB8),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AiReportStateCard extends StatelessWidget {
  final String message;
  final bool isError;

  const _AiReportStateCard({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: (isError ? AppColors.primary : AppColors.triggerSocial)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.auto_awesome_outlined,
              size: 15,
              color: isError ? AppColors.primary : AppColors.triggerSocial,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(
                color: isError ? AppColors.primary : AppColors.textM,
              ),
            ),
          ),
        ],
      ),
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
