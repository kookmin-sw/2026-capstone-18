import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/soft_outline_button.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../core/widgets/trigger_chip.dart';
import '../../features/cycles/cycle_provider.dart';
import '../../features/events/events_provider.dart';
import '../../features/events/models/stress_event.dart';
import '../../features/home/home_provider.dart';
import '../../features/insight/insight_provider.dart';
import '../../features/triggers/triggers_provider.dart';

class StressLogScreen extends StatefulWidget {
  final StressEvent? sourceEvent;

  const StressLogScreen({super.key, this.sourceEvent});

  @override
  State<StressLogScreen> createState() => _StressLogScreenState();
}

class _StressLogScreenState extends State<StressLogScreen> {
  final TextEditingController _noteController = TextEditingController();

  String? _selectedTrigger;
  int? _selectedStressScore;
  bool _saving = false;

  String get _stressScoreLabel {
    return _selectedStressScore?.toString() ?? '?';
  }

  bool get _isEditingLoggedEvent =>
      widget.sourceEvent?.isLoggedWithScore == true;

  bool get _isFromDetectedStress =>
      widget.sourceEvent != null && !_isEditingLoggedEvent;

  @override
  void initState() {
    super.initState();
    final trigger = widget.sourceEvent?.trigger;
    if (trigger != null && !_isUnknownTrigger(trigger)) {
      _selectedTrigger = trigger.trim();
    }
    final note = widget.sourceEvent?.note ?? widget.sourceEvent?.logText;
    if (note != null && note.trim().isNotEmpty) {
      _noteController.text = note.trim();
    }
    _selectedStressScore = widget.sourceEvent?.stressScore ?? 50;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stressScore = _selectedStressScore;
    if (stressScore == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스트레스 점수를 선택해 주세요.')));
      return;
    }

    setState(() => _saving = true);

    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final eventsProvider = context.read<EventsProvider>();
    final currentCycle = context.read<CycleProvider>().currentCycle;
    final homeProvider = context.read<HomeProvider>();
    final insightProvider = context.read<InsightProvider>();
    final sourceEvent = widget.sourceEvent;
    final result = _isEditingLoggedEvent && sourceEvent != null
        ? await eventsProvider.updateEvent(
            event: sourceEvent,
            stressScore: stressScore,
            trigger: _selectedTrigger ?? '',
            note: note,
          )
        : await eventsProvider.createEvent(
            stressScore: stressScore,
            trigger: _selectedTrigger ?? '',
            note: note,
            cyclePhase: currentCycle?.phase,
            cycleDay: currentCycle?.cycleDay,
            sourceUnloggedEvent: _isFromDetectedStress ? sourceEvent : null,
          );

    if (!mounted) return;

    if (result == null) {
      setState(() => _saving = false);
      final errorMessage = context.read<EventsProvider>().errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? '기록을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }

    await Future.wait([homeProvider.refresh(), insightProvider.refresh()]);

    if (!mounted) return;

    setState(() => _saving = false);
    Navigator.pop(context);
  }

  void _skip() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditingLoggedEvent = _isEditingLoggedEvent;
    final isFromDetectedStress = _isFromDetectedStress;
    final triggerOptions = _triggerOptions(context.watch<TriggersProvider>());

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Row(
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
                const Expanded(
                  child: Text(
                    '스트레스 기록',
                    style: TextStyle(
                      color: Color(0xFF201C28),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (!isFromDetectedStress) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Text(
                  '오늘 느낀 스트레스를 조용히 기록해요.',
                  style: AppTextStyles.caption.copyWith(
                    color: const Color(0xFF9888A0),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              blur: 4,
              padding: const EdgeInsets.all(22),
              borderRadius: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditingLoggedEvent
                        ? '스트레스 기록 수정'
                        : isFromDetectedStress
                        ? '감지된 스트레스'
                        : '오늘의 스트레스',
                    style: AppTextStyles.label,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _stressScoreLabel,
                        style: AppTextStyles.metricNumber.copyWith(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '/ 100',
                          style: TextStyle(
                            fontSize: 18,
                            color: Color(0xFFB8AEB3),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isEditingLoggedEvent) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '기록한 점수와 요인을 다시 조정할 수 있어요.',
                      style: AppTextStyles.body,
                    ),
                  ] else if (isFromDetectedStress) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '조금 전 감지된 스트레스예요. 준비되면 점수와 상황을 가볍게 남겨 주세요.',
                      style: AppTextStyles.body,
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Text(
                      '워치 감지 없이도 지금의 느낌을 편하게 남길 수 있어요.',
                      style: AppTextStyles.body,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('스트레스 점수', style: AppTextStyles.sectionTitle),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: const Color(0xFFF2DCF3),
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.12),
                      trackHeight: 5,
                    ),
                    child: Slider(
                      value: (_selectedStressScore ?? 50).toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (value) {
                        setState(() {
                          _selectedStressScore = value.round();
                        });
                      },
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC0B0B8),
                        ),
                      ),
                      Text(
                        '100',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFC0B0B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle(title: '어떤 일이 있었나요?'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: triggerOptions.map((trigger) {
                final selected = _sameTrigger(_selectedTrigger, trigger.key);

                return TriggerChip(
                  label: trigger.label,
                  color: trigger.color,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      _selectedTrigger = selected ? null : trigger.key;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle(title: '메모'),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: '짧은 메모를 남겨 보세요',
                hintStyle: const TextStyle(color: Color(0xFFC0B0B8)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: SoftOutlineButton(
                    text: isEditingLoggedEvent ? '취소' : '건너뛰기',
                    onTap: _saving ? null : _skip,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SoftPrimaryButton(
                    text: '저장하기',
                    onTap: _saving ? null : _save,
                    isLoading: _saving,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_TriggerOption> _triggerOptions(TriggersProvider provider) {
    if (provider.triggers.isEmpty) {
      return TriggersProvider.defaultTriggers
          .map((trigger) => _TriggerOption.fromTrigger(trigger))
          .toList();
    }

    return provider.triggers
        .map((trigger) => _TriggerOption.fromTrigger(trigger))
        .toList();
  }

  bool _sameTrigger(String? left, String right) {
    if (left == null) return false;
    final leftValues = _triggerValues(left);
    final rightValues = _triggerValues(right);
    return leftValues.any(rightValues.contains);
  }

  bool _isUnknownTrigger(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized == 'uncategorized';
  }

  Set<String> _triggerValues(String value) {
    return {value.trim().toLowerCase(), koTrigger(value).trim().toLowerCase()};
  }
}

class _TriggerOption {
  final String key;
  final String label;
  final Color color;

  _TriggerOption.fromTrigger(StressTrigger trigger)
    : key = trigger.name,
      label = koTrigger(trigger.name),
      color = trigger.color;
}
