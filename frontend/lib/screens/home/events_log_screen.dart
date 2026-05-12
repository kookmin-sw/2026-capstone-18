import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/events/events_provider.dart';
import '../../features/events/models/stress_event.dart';
import 'stress_log_screen.dart';

class EventsLogScreen extends StatefulWidget {
  const EventsLogScreen({super.key});

  @override
  State<EventsLogScreen> createState() => _EventsLogScreenState();
}

class _EventsLogScreenState extends State<EventsLogScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<EventsProvider>().loadToday();
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventsProvider = context.watch<EventsProvider>();

    final events =
        eventsProvider.todayEvents
            .where((event) => event.isLoggedWithScore)
            .toList()
          ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Color(0xFF201C28),
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '스트레스 기록',
                    style: TextStyle(
                      color: Color(0xFF201C28),
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: eventsProvider.loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFB87888),
                      ),
                    )
                  : events.isEmpty
                  ? const Center(
                      child: Text(
                        '오늘 남긴 스트레스 기록이 없어요',
                        style: TextStyle(
                          color: Color(0xFF9888A0),
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                      itemCount: events.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return _EventItem(event: event);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventItem extends StatelessWidget {
  final StressEvent event;

  const _EventItem({required this.event});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditor(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFB87888),
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.all(18),
              borderRadius: 24,
              blur: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeLabel(event.detectedAt),
                    style: const TextStyle(
                      color: Color(0xFFB8AEB3),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          koTrigger(event.trigger),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF181818),
                          ),
                        ),
                      ),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3DDEB),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              event.logged ? '기록 완료' : '기록 전',
                              style: const TextStyle(
                                color: Color(0xFF9B7B8B),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '기록 수정',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => _openEditor(context),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Color(0xFFC09AAB),
                            ),
                          ),
                          IconButton(
                            tooltip: '기록 삭제',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => _confirmDelete(context),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Color(0xFFC09AAB),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    '스트레스 ${event.stressScore} / 100',
                    style: const TextStyle(
                      color: Color(0xFFB87888),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  if ((event.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),

                    Text(
                      event.note!,
                      style: const TextStyle(
                        color: Color(0xFF7D7378),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StressLogScreen(sourceEvent: event)),
    );
    if (!context.mounted) return;
    await context.read<EventsProvider>().loadToday();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('기록을 삭제할까요?'),
        content: const Text('삭제한 스트레스 기록은 다시 복구할 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final deleted = await context.read<EventsProvider>().deleteEvent(event.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deleted ? '기록을 삭제했어요.' : '기록을 삭제하지 못했어요. 다시 시도해 주세요.'),
      ),
    );
  }

  String _timeLabel(DateTime dateTime) {
    final now = DateTime.now();

    final isToday =
        now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;

    final yesterday = now.subtract(const Duration(days: 1));

    final isYesterday =
        yesterday.year == dateTime.year &&
        yesterday.month == dateTime.month &&
        yesterday.day == dateTime.day;

    final time = koTime(dateTime);

    if (isToday) return time;

    if (isYesterday) {
      return '어제 · $time';
    }

    return '${dateTime.month}/${dateTime.day} · $time';
  }
}
