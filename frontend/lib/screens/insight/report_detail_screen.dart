import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../features/insight/insight_provider.dart';
import '../../features/insight/services/insight_analytics_service.dart';

class ReportDetailScreen extends StatelessWidget {
  final String trigger;
  final String phase;

  const ReportDetailScreen({
    super.key,
    required this.trigger,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final detail = context.watch<InsightProvider>().detailFor(
      trigger: trigger,
      phase: phase,
    );
    final phaseLabel = koPhase(detail.phase);

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
                      _Header(title: '${koTrigger(trigger)} × $phaseLabel'),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _phaseColor(
                            detail.phase,
                          ).withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _phaseColor(
                              detail.phase,
                            ).withValues(alpha: 0.7),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    koMonthRange(
                                      start: detail.range.start,
                                      endExclusive: detail.range.endExclusive,
                                      monthCount: detail.range.monthCount,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9888A0),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    koTrigger(trigger),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF201C28),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    phaseLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF483848),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${detail.totalEvents}건',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFFB87888),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _MetricCard(
                            label: '기록',
                            value: '${detail.totalEvents}',
                          ),
                          const SizedBox(width: 8),
                          _MetricCard(
                            label: '평균 스트레스',
                            value: '${detail.averageStress.round()}점',
                          ),
                          const SizedBox(width: 8),
                          _MetricCard(
                            label: '자주 나타난 일차',
                            value: detail.mostCommonCycleDay == null
                                ? '기록 없음'
                                : '${detail.mostCommonCycleDay}일차',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(
                              title: '${koTrigger(trigger)}의 주기 단계별 분포',
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: detail.crossPhaseComparison.map((cell) {
                                final active = cell.phase == detail.phase;
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? _phaseColor(
                                              cell.phase,
                                            ).withValues(alpha: 0.64)
                                          : Colors.white.withValues(
                                              alpha: 0.44,
                                            ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: active
                                          ? Border.all(
                                              color: const Color(
                                                0xFFB87888,
                                              ).withValues(alpha: 0.45),
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          koPhase(cell.phase),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: active
                                                ? const Color(0xFF201C28)
                                                : const Color(0xFF9888A0),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${cell.count}건',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF201C28),
                                          ),
                                        ),
                                        Text(
                                          '평균 ${cell.averageStress.round()}점',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFF9888A0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (detail.events.isEmpty)
                        const _GlassCard(
                          child: Text(
                            '이 기간에는 일치하는 기록이 없어요.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9888A0),
                            ),
                          ),
                        )
                      else
                        _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionTitle(title: '일치하는 기록'),
                              const SizedBox(height: 12),
                              ...detail.events.map((event) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 9,
                                        height: 9,
                                        margin: const EdgeInsets.only(top: 5),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFB87888),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${_formatDate(event.detectedAt)} · ${event.cycleDay}일차',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFFC0B0C0),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '스트레스 ${event.stressScore} · $phaseLabel',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF201C28),
                                              ),
                                            ),
                                            if ((event.note ?? '').isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 3,
                                                ),
                                                child: Text(
                                                  event.note!,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF9888A0),
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
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

  String _formatDate(DateTime date) {
    const months = [
      '1월',
      '2월',
      '3월',
      '4월',
      '5월',
      '6월',
      '7월',
      '8월',
      '9월',
      '10월',
      '11월',
      '12월',
    ];
    return '${months[date.month - 1]} ${date.day}일';
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
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF201C28),
            ),
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
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF201C28),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9888A0)),
            ),
          ],
        ),
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
    'menstrual' => AppColors.phaseMenstrual,
    'follicular' => AppColors.phaseFollicular,
    'ovulation' => AppColors.phaseOvulation,
    'luteal' => AppColors.phaseLuteal,
    _ => AppColors.triggerOther,
  };
}
