import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/utils/cycle_phase_ui.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/events/models/stress_event.dart';
import '../../features/insight/insight_provider.dart';

class DayEventsScreen extends StatelessWidget {
  final int day;
  final int month;
  final int year;

  const DayEventsScreen({
    super.key,
    required this.day,
    required this.month,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime(year, month, day);
    final insight = context.watch<InsightProvider>();
    final events = insight.eventsForDay(date);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF201C28),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$year년 $month월 $day일',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text(
                        '이날에는 아직 기록이 없어요.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9888A0),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final event = events[index];
                        return _EventItem(
                          event: event,
                          phase: insight.phaseForEvent(event),
                        );
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
  final String phase;

  const _EventItem({required this.event, required this.phase});

  @override
  Widget build(BuildContext context) {
    final phaseUi = CyclePhaseUi.of(phase);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const SizedBox(height: 18),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: phaseUi.color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            borderRadius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(event.detectedAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFC0B0C0),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        koTrigger(event.trigger),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF201C28),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: phaseUi.softBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        phaseUi.label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textB,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '스트레스 ${event.stressScore}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB87888),
                  ),
                ),
                if ((event.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    event.note!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9888A0),
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime date) {
    return koTime(date.toLocal());
  }
}
