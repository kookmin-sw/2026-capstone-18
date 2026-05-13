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
import '../../features/triggers/triggers_provider.dart';
import '../my/my_cycle_screen.dart';
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
    final hasCycleData = provider.cycles.isNotEmpty;

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
                                value: '${report.averageStress.round()}점',
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
                          if (report.hasPhaseData)
                            _PhaseDistribution(report: report)
                          else
                            _CycleInfoGuideCard(hasCycleData: hasCycleData),
                          const SizedBox(height: 12),
                          _TriggerRanking(report: report),
                          if (report.hasPhaseData) ...[
                            const SizedBox(height: 12),
                            _TriggerMatrix(report: report),
                          ],
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

class _CycleInfoGuideCard extends StatelessWidget {
  final bool hasCycleData;

  const _CycleInfoGuideCard({required this.hasCycleData});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '주기 기반 리포트'),
          const SizedBox(height: 8),
          Text(
            hasCycleData
                ? '선택한 기간에 주기와 연결된 스트레스 기록이 아직 없어요.'
                : '주기 데이터가 아직 없어요.\n주기 정보를 입력하면 스트레스와 주기의 관계를 볼 수 있어요.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textM,
            ),
          ),
          if (!hasCycleData) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MyCycleScreen(),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text(
                  '주기 기록하기',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhaseDistribution extends StatelessWidget {
  final InsightReportViewModel report;

  const _PhaseDistribution({required this.report});

  @override
  Widget build(BuildContext context) {
    final maxPhaseCount = report.phaseAverages.fold<int>(
      0,
      (max, phase) => phase.count > max ? phase.count : max,
    );

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '기간별 주기 단계 흐름'),
          const SizedBox(height: 12),
          ...report.phaseAverages.map((phase) {
            final phaseCount = phase.count;
            final barWidthRatio = maxPhaseCount == 0
                ? 0.0
                : phaseCount / maxPhaseCount;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      CyclePhaseUi.of(phase.phase).label,
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
                        value: barWidthRatio,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF5F1F6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          CyclePhaseUi.of(phase.phase).color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$phaseCount건 · 평균 ${phase.averageStress.round()}점',
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
    final triggerColors = context.watch<TriggersProvider>().triggers;
    final factors = [...report.triggerRanking]
      ..sort((a, b) {
        final countOrder = b.count.compareTo(a.count);
        if (countOrder != 0) return countOrder;
        return koTrigger(a.trigger).compareTo(koTrigger(b.trigger));
      });
    final topFactors = factors.take(5).toList();
    final totalFactorCount = factors.fold<int>(
      0,
      (sum, item) => sum + item.count,
    );
    final maxCount = topFactors.fold<int>(
      0,
      (max, item) => item.count > max ? item.count : max,
    );

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '자주 나타난 요인'),
          const SizedBox(height: 6),
          const Text(
            '선택한 기간의 전체 요인 기록 중 각 요인이 차지하는 비율입니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.textM,
            ),
          ),
          const SizedBox(height: 16),
          if (topFactors.isEmpty || totalFactorCount == 0)
            const _ChartEmptyState(message: '선택한 기간의 스트레스 요인 기록이 아직 없어요.')
          else
            SizedBox(
              height: 198,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: topFactors.map((item) {
                  final factorRatio = item.count / totalFactorCount;
                  final barHeightRatio = maxCount == 0
                      ? 0.0
                      : item.count / maxCount;
                  return Expanded(
                    child: _TriggerRankingBar(
                      label: koTrigger(item.trigger),
                      count: item.count,
                      ratio: factorRatio,
                      barHeightRatio: barHeightRatio,
                      color: _triggerColorFor(item.trigger, triggerColors),
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

class _TriggerRankingBar extends StatelessWidget {
  final String label;
  final int count;
  final double ratio;
  final double barHeightRatio;
  final Color color;

  const _TriggerRankingBar({
    required this.label,
    required this.count,
    required this.ratio,
    required this.barHeightRatio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const maxBarHeight = 104.0;
    final barHeight = (maxBarHeight * barHeightRatio).clamp(8.0, maxBarHeight);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$count건',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A5867),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 26,
              height: barHeight,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 30,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                color: Color(0xFF483848),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(ratio * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF9888A0),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F0F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: Color(0xFF9888A0),
          ),
        ),
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
    final maxCellCount = report.triggerByCyclePhaseMatrix.fold<int>(
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
                      CyclePhaseUi.of(phase).label,
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
                    final cellCount = cell.count;
                    return Expanded(
                      child: GestureDetector(
                        onTap: cellCount == 0
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
                            color: _cellColor(
                              cellCount: cellCount,
                              maxCellCount: maxCellCount,
                              phase: phase,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              cellCount == 0 ? '' : '$cellCount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cellCount > 0
                                    ? AppColors.textB
                                    : Colors.transparent,
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

  Color _cellColor({
    required int cellCount,
    required int maxCellCount,
    required String phase,
  }) {
    final phaseBaseColor = CyclePhaseUi.of(phase).color;
    if (cellCount == 0 || maxCellCount == 0) {
      return phaseBaseColor.withValues(alpha: 0.12);
    }

    final intensityRatio = (cellCount / maxCellCount).clamp(0.0, 1.0);
    final cellOpacity = intensityRatio >= 0.5 ? 0.85 : 0.42;
    return phaseBaseColor.withValues(alpha: cellOpacity);
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
              Container(
                height: 16,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: shimmer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 10),

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

Color _triggerColorFor(String trigger, List<StressTrigger> triggers) {
  final targetValues = _triggerValues(trigger);
  final sources = triggers.isEmpty
      ? TriggersProvider.defaultTriggers
      : triggers;

  for (final source in sources) {
    if (_triggerValues(source.name).any(targetValues.contains)) {
      return source.color;
    }
  }

  final normalized = trigger.trim().toLowerCase();
  final translated = koTrigger(trigger).trim().toLowerCase();
  return switch (normalized) {
    '' || 'unknown' || 'uncategorized' => AppColors.triggerOther,
    'work' => AppColors.triggerWork,
    'social' => AppColors.triggerSocial,
    'family' => AppColors.triggerFamily,
    'school' => AppColors.triggerSchool,
    'health' => AppColors.triggerHealth,
    _ => switch (translated) {
      '업무' => AppColors.triggerWork,
      '대인관계' => AppColors.triggerSocial,
      '가족' => AppColors.triggerFamily,
      '학업' => AppColors.triggerSchool,
      '건강' => AppColors.triggerHealth,
      '요인 불명' => AppColors.triggerOther,
      _ => AppColors.triggerOther,
    },
  };
}

Set<String> _triggerValues(String trigger) {
  return {
    trigger.trim().toLowerCase(),
    koTrigger(trigger).trim().toLowerCase(),
  };
}
