import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';

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
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('지속 시간', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text('$mm:$ss',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Text('업로드된 윈도우',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text('$windowsUploaded',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Text('대략 데이터 크기',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text('약 $estMb MB',
                          style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
