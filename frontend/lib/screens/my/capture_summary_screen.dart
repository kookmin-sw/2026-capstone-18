import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/soft_primary_button.dart';

class CaptureSummaryScreen extends StatelessWidget {
  final int elapsedSec;
  final int windowsUploaded;

  const CaptureSummaryScreen({
    super.key,
    required this.elapsedSec,
    required this.windowsUploaded,
  });

  @override
  Widget build(BuildContext context) {
    final mm = (elapsedSec ~/ 60).toString().padLeft(2, '0');
    final ss = (elapsedSec % 60).toString().padLeft(2, '0');
    final estBytes = windowsUploaded * 240 * 1024;
    final estMb = (estBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('캡처 완료'),
      ),
      body: AppGradientBackground(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('캡처 요약', style: AppTextStyles.cardTitle),
                    const SizedBox(height: AppSpacing.lg),
                    _SummaryMetric(label: '지속 시간', value: '$mm:$ss'),
                    const SizedBox(height: AppSpacing.lg),
                    _SummaryMetric(
                      label: '업로드된 윈도우',
                      value: '$windowsUploaded',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SummaryMetric(label: '대략 데이터 크기', value: '약 $estMb MB'),
                  ],
                ),
              ),
              const Spacer(),
              SoftPrimaryButton(
                text: '완료',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.caption)),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: AppTextStyles.metricNumber.copyWith(
            fontSize: 26,
            color: AppColors.textH,
          ),
        ),
      ],
    );
  }
}
