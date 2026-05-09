import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../features/sleep/models/sleep_log.dart';
import '../../features/sleep/services/sleep_insight_service.dart';
import '../../features/sleep/sleep_provider.dart';
import 'watch_connect_screen.dart';

class SleepDataScreen extends StatefulWidget {
  const SleepDataScreen({super.key});

  @override
  State<SleepDataScreen> createState() => _SleepDataScreenState();
}

class _SleepDataScreenState extends State<SleepDataScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SleepProvider>().load();
    });
  }

  Future<void> _openWatchConnect() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const WatchConnectScreen()),
    );

    if (!mounted) return;
    await context.read<SleepProvider>().loadLatest();
  }

  @override
  Widget build(BuildContext context) {
    final sleepProvider = context.watch<SleepProvider>();
    final latest = sleepProvider.latestLog;
    final history = sleepProvider.history;
    final sleepInsight = const SleepInsightService().buildInsight(
      latestLog: latest,
      history: history,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: RefreshIndicator(
          color: const Color(0xFFB87888),
          onRefresh: () => context.read<SleepProvider>().load(),
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
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Header(title: '수면 데이터'),
                          const SizedBox(height: 26),

                          if (sleepProvider.loading)
                            const Expanded(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(28),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFB87888),
                                  ),
                                ),
                              ),
                            )
                          else if (latest == null && history.isEmpty)
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (sleepProvider.errorMessage != null) ...[
                                    _GlassCard(
                                      child: Text(
                                        sleepProvider.errorMessage!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFB87888),
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _SleepEmptyState(
                                    onConnect: _openWatchConnect,
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            if (sleepProvider.errorMessage != null) ...[
                              _GlassCard(
                                child: Text(
                                  sleepProvider.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFB87888),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (latest != null)
                              _LatestSleepCard(sleepLog: latest),

                            if (latest != null) ...[
                              const SizedBox(height: 12),
                              _SleepInsightCard(insight: sleepInsight),
                            ],

                            if (history.isNotEmpty) ...[
                              if (latest != null) const SizedBox(height: 12),
                              _SleepHistoryCard(history: history),
                            ],
                          ],
                        ],
                      ),
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

class _LatestSleepCard extends StatelessWidget {
  final SleepLog sleepLog;

  const _LatestSleepCard({required this.sleepLog});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '최근 수면'),
          const SizedBox(height: 12),
          const Text(
            '총 수면 시간',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF9888A0),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(sleepLog.durationLabel, style: AppTextStyles.metricNumber),
          const SizedBox(height: 12),
          _SleepInfoRow(label: '날짜', value: _formatDate(sleepLog.endedOn)),
          _SleepInfoRow(
            label: '잠든 시간',
            value: _formatTime(sleepLog.fellAsleepAt),
          ),
          _SleepInfoRow(label: '일어난 시간', value: _formatTime(sleepLog.wokeUpAt)),
        ],
      ),
    );
  }
}

class _SleepInsightCard extends StatelessWidget {
  final String insight;

  const _SleepInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '수면 패턴'),
          const SizedBox(height: 8),
          Text(
            insight,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF9888A0),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _SleepInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9888A0),
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF201C28),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepHistoryCard extends StatelessWidget {
  final List<SleepLog> history;

  const _SleepHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final visibleHistory = history.take(14).toList();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '수면 기록'),
          const SizedBox(height: 12),

          ...visibleHistory.map((sleepLog) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatDate(sleepLog.endedOn)}\n${_formatTime(sleepLog.fellAsleepAt)} - ${_formatTime(sleepLog.wokeUpAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9888A0),
                        height: 1.45,
                      ),
                    ),
                  ),
                  Text(
                    sleepLog.durationLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF201C28),
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

class _SleepEmptyState extends StatelessWidget {
  final Future<void> Function() onConnect;

  const _SleepEmptyState({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          const Icon(
            Icons.bedtime_outlined,
            color: Color(0xFFC0B0C0),
            size: 32,
          ),
          const SizedBox(height: 10),
          const Text(
            '아직 수면 데이터가 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF201C28),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Galaxy Watch를 연결하면 수면 시간과 기록을 동기화해 볼 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9888A0),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SoftPrimaryButton(
            text: 'Galaxy Watch 연결하기',
            onTap: onConnect,
            height: 38,
            fullWidth: false,
          ),
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

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(padding: const EdgeInsets.all(16), child: child);
  }
}

String _formatDate(DateTime date) {
  return koFullDate(date);
}

String _formatTime(DateTime date) {
  return koTime(date);
}
