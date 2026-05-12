import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/insight/data/range_report.dart';

class RangeReportScreen extends StatelessWidget {
  final RangeReport report;
  const RangeReportScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final n = report.periodEnd.month - report.periodStart.month +
        (report.periodEnd.year - report.periodStart.year) * 12 + 1;
    final dateLabel = koMonthRange(
      start: report.periodStart,
      endExclusive: DateTime(report.periodEnd.year, report.periodEnd.month + 1),
      monthCount: n,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back,
                          color: AppColors.textH,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _DateChip(label: dateLabel),
                      const SizedBox(height: 14),
                      Text(report.headline, style: AppTextStyles.title),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: MarkdownBody(
                    data: report.bodyMd,
                    styleSheet: MarkdownStyleSheet(
                      p: AppTextStyles.body,
                      h3: AppTextStyles.sectionTitle,
                      h4: AppTextStyles.cardTitle,
                      strong: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textH,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (report.takeaways.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 28, 20, 14),
                  child: Text('주요 인사이트', style: AppTextStyles.sectionTitle),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TakeawayCard(
                        index: i,
                        takeaway: report.takeaways[i],
                      ),
                    ),
                    childCount: report.takeaways.length,
                  ),
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          height: 1.3,
        ),
      ),
    );
  }
}

class _TakeawayCard extends StatelessWidget {
  final int index;
  final RangeTakeaway takeaway;

  const _TakeawayCard({required this.index, required this.takeaway});

  static const List<Color> _accents = [
    AppColors.primary,
    Color(0xFFB7A6D8),
    AppColors.triggerFamily,
    AppColors.triggerSchool,
    AppColors.triggerHealth,
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _accents[index % _accents.length];
    return GlassCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(takeaway.title, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 6),
                    Text(takeaway.body, style: AppTextStyles.body),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
