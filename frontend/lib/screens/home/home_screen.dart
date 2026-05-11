import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/user_display.dart';
import '../../features/events/events_provider.dart';
import '../../features/events/models/stress_event.dart';
import '../../features/home/greeting.dart';
import '../../features/home/home_provider.dart';
import '../../features/insight/data/morning_tip.dart';
import '../../features/insight/insight_provider.dart';
import '../../features/sleep/sleep_provider.dart';
import '../../features/triggers/triggers_provider.dart';
import '../my/my_cycle_screen.dart';
import '../my/sleep_data_screen.dart';
import 'events_log_screen.dart';
import 'stress_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openStressLog({StressEvent? sourceEvent}) async {
    final eventsProvider = context.read<EventsProvider>();
    final homeProvider = context.read<HomeProvider>();
    final insightProvider = context.read<InsightProvider>();
    final triggersProvider = context.read<TriggersProvider>();

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StressLogScreen(sourceEvent: sourceEvent),
      ),
    );

    if (!mounted) return;

    await homeProvider.refresh();
    await eventsProvider.loadToday();
    await insightProvider.refresh();
    await triggersProvider.load();
  }

  Future<void> _openStressLogFromPending() {
    return _openStressLog(
      sourceEvent: context.read<EventsProvider>().pendingLogEvent,
    );
  }

  Future<void> _openSleepData() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SleepDataScreen()),
    );

    if (!mounted) return;
    await context.read<SleepProvider>().loadLatest();
  }

  Future<void> _openMyCycle() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const MyCycleScreen()),
    );

    if (!mounted) return;

    await context.read<HomeProvider>().refresh();
  }

  Future<void> _refreshAll() async {
    final homeProvider = context.read<HomeProvider>();
    final eventsProvider = context.read<EventsProvider>();
    final insightProvider = context.read<InsightProvider>();
    final sleepProvider = context.read<SleepProvider>();

    await homeProvider.refresh();
    await eventsProvider.loadToday();
    await insightProvider.refresh();
    await sleepProvider.loadLatest();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final eventsProvider = context.watch<EventsProvider>();
    final sleepProvider = context.watch<SleepProvider>();
    final displayName = userDisplayName(context.watch<AuthProvider>().user);
    final date = DateTime.now();
    final greeting = getGreetingByTime(date, displayName);

    final latestSleep = sleepProvider.latestLog;

    final todayLoggedEvents = eventsProvider.todayEvents
        .where((event) => event.isLoggedWithScore)
        .toList();

    final todayLoggedCount = todayLoggedEvents.length;
    final unloggedCount = eventsProvider.unloggedCount;
    final hasPendingLog = eventsProvider.hasPendingLog;
    final stressScoreDisplay = eventsProvider.stressScoreDisplay;
    final hasStressScoreDisplay = eventsProvider.hasStressScoreDisplay;

    final weekAgo = date.subtract(const Duration(days: 7));
    final weekCount = eventsProvider.loggedEvents
        .where((event) => event.detectedAt.isAfter(weekAgo))
        .length;

    final hasCycle = home.currentCycle != null;
    final cycleDay = hasCycle ? '${home.currentCycle!.cycleDay}일차' : '--';
    final cyclePhase = home.currentCycle?.phase ?? '주기 정보 없음';
    final daysLeft = hasCycle
        ? '다음 생리 예정일까지 ${home.currentCycle!.cycleLength - home.currentCycle!.cycleDay + 1}일'
        : '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: RefreshIndicator(
          color: const Color(0xFFB87888),
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.screenTitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _formatDate(date),
                  style: AppTextStyles.caption.copyWith(color: AppColors.textL),
                ),

                if (home.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: home.errorMessage!),
                ],

                if (home.morningTip != null) ...[
                  const SizedBox(height: 20),
                  _MorningTipCard(tip: home.morningTip!),
                ],

                const SizedBox(height: 20),

                GlassCard(
                  blur: 4,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _CardLabel(label: '스트레스'),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  hasStressScoreDisplay
                                      ? stressScoreDisplay
                                      : '?',
                                  style: AppTextStyles.metricNumber.copyWith(
                                    fontSize: 46,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '/ 100',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textL,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!hasStressScoreDisplay) ...[
                              const SizedBox(height: AppSpacing.sm),
                              const Text(
                                '아직 감지된 스트레스가 없어요.\n워치를 착용하면 신호를 살펴볼게요.',
                                style: AppTextStyles.caption,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            SoftPrimaryButton(
                              text: '스트레스 기록해요',
                              onTap: () => _openStressLog(),
                              fullWidth: false,
                              height: 38,
                            ),
                          ],
                        ),
                      ),
                      if (hasStressScoreDisplay)
                        SizedBox(
                          width: 100,
                          height: 40,
                          child: CustomPaint(painter: _HeartbeatPainter()),
                        ),
                    ],
                  ),
                ),

                if (hasPendingLog) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _openStressLogFromPending,
                    child: GlassCard(
                      blur: 4,
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFE8EB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              color: Color(0xFFB87888),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '방금 감지된 스트레스를 기록할까요?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF201C28),
                                    height: 1.3,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '지금 기록해요',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB87888),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openSleepData,
                        child: GlassCard(
                          child: _MetricCardContent(
                            label: '수면',
                            value: latestSleep == null
                                ? '--'
                                : '${latestSleep.durationHours.toStringAsFixed(1)}시간',
                            caption: latestSleep == null
                                ? '아직 수면 데이터가 없어요'
                                : _formatDate(latestSleep.endedOn),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassCard(
                        child: _MetricCardContent(
                          label: '남은 기록',
                          value: '$unloggedCount',
                          caption: '기록을 기다려요',
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EventsLogScreen(),
                          ),
                        ),
                        child: GlassCard(
                          child: _MetricCardContent(
                            label: '기록',
                            value: '$todayLoggedCount',
                            caption: todayLoggedCount > 0
                                ? '이번 주 $weekCount건'
                                : '아직 기록이 없어요',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openMyCycle,
                        child: GlassCard(
                          child: _MetricCardContent(
                            label: '주기',
                            value: cycleDay,
                            caption: hasCycle
                                ? ''
                                : '최근 생리 시작일을 추가하거나 워치와 동기화해요',
                            captionColor: hasCycle
                                ? const Color(0xFFC0B0C0)
                                : const Color(0xFFB87888),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (hasCycle)
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('주기 흐름', style: AppTextStyles.cardTitle),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Container(
                                  height: 8,
                                  color: const Color(0xBFFFDAD5),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: 6,
                                child: Container(
                                  height: 8,
                                  color: const Color(0xBFF2DCF3),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  height: 8,
                                  color: const Color(0xBFDDEDF8),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: 10,
                                child: Container(
                                  height: 8,
                                  color: const Color(0xBF94D0BC),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '생리기',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFFC0B0C0),
                              ),
                            ),
                            Text(
                              '난포기',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFFC0B0C0),
                              ),
                            ),
                            Text(
                              '배란기',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFFC0B0C0),
                              ),
                            ),
                            Text(
                              '황체기',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFFC0B0C0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0x20000000), height: 1),
                        const SizedBox(height: 10),
                        Text(
                          koPhase(cyclePhase),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9888A0),
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _phaseDescription(cyclePhase),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFC0B0C0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            daysLeft,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9888A0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openMyCycle,
                    child: const GlassCard(
                      child: Column(
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            color: Color(0xFFC0B0C0),
                            size: 32,
                          ),
                          SizedBox(height: 10),
                          Text(
                            '최근 생리 시작일을 추가하거나 워치와 동기화하면 주기 흐름을 더 부드럽게 살펴볼 수 있어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9888A0),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
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

    return '${date.year}년 ${months[date.month - 1]} ${date.day}일';
  }

  String _phaseDescription(String phase) {
    final normalized = phase.toLowerCase();

    if (normalized.contains('period') || normalized.contains('menstrual')) {
      return '생리가 시작됐어요. 오늘은 몸을 조금 더 편하게 돌봐 주세요.';
    }
    if (normalized.contains('follicular')) {
      return '에너지가 서서히 올라오는 시기예요.';
    }
    if (normalized.contains('ovulation')) {
      return '몸과 마음이 비교적 선명하게 느껴질 수 있어요.';
    }
    if (normalized.contains('luteal')) {
      return '스트레스에 조금 더 민감해질 수 있는 시기예요.';
    }

    return '주기를 설정하면 내 흐름에 맞춰 보여드릴게요.';
  }
}

class _MetricCardContent extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color captionColor;

  const _MetricCardContent({
    required this.label,
    required this.value,
    required this.caption,
    this.captionColor = const Color(0xFFC0B0C0),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.label),
          const Spacer(),
          Text(value, style: AppTextStyles.metricNumber.copyWith(fontSize: 22)),
          if (caption.isNotEmpty)
            Text(caption, style: TextStyle(fontSize: 10, color: captionColor)),
        ],
      ),
    );
  }
}

class _MorningTipCard extends StatelessWidget {
  final MorningTip tip;

  const _MorningTipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      blur: 4,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF3C4CE), Color(0xFFB7A6D8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '오늘의 신호',
                style: AppTextStyles.label.copyWith(color: AppColors.textM),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            tip.headline,
            style: AppTextStyles.cardTitle.copyWith(fontSize: 17, height: 1.35),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tip.body,
            style: AppTextStyles.body.copyWith(color: AppColors.textB),
          ),
          if (tip.contextLine != null && tip.contextLine!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tip.contextLine!,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textM,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String label;

  const _CardLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFB87888),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.label),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB87888)),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB87888)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.3, size.height * 0.2)
      ..lineTo(size.width * 0.4, size.height * 0.8)
      ..lineTo(size.width * 0.5, size.height * 0.1)
      ..lineTo(size.width * 0.6, size.height * 0.7)
      ..lineTo(size.width * 0.7, size.height * 0.5)
      ..lineTo(size.width, size.height * 0.5);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
