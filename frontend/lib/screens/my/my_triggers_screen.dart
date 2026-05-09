import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../core/widgets/trigger_chip.dart';
import '../../features/triggers/triggers_provider.dart';

class MyTriggersScreen extends StatefulWidget {
  const MyTriggersScreen({super.key});

  @override
  State<MyTriggersScreen> createState() => _MyTriggersScreenState();
}

class _MyTriggersScreenState extends State<MyTriggersScreen> {
  final TextEditingController _controller = TextEditingController();

  final List<Color> _colorOptions = const [
    Color(0xFFB87888),
    Color(0xFFB7A6D8),
    Color(0xFF94D0BC),
    Color(0xFFAED3E8),
    Color(0xFFF2DCF3),
    Color(0xFFE7C9A9),
    Color(0xFFD8D2D8),
  ];

  Color _selectedColor = const Color(0xFFB87888);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<TriggersProvider>().triggers.isEmpty) {
        context.read<TriggersProvider>().load();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  void _showAddSheet() {
    _controller.clear();
    _selectedColor = const Color(0xFFB87888);
    String? inlineError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8F2F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(title: '새 요인 추가하기'),
              const SizedBox(height: AppSpacing.md),
              _InputBox(
                controller: _controller,
                hint: '요인 이름을 입력해 주세요',
                onChanged: (_) {
                  if (inlineError == null) return;
                  setModal(() => inlineError = null);
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: inlineError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: const ValueKey('add-trigger-inline-error'),
                        padding: const EdgeInsets.only(top: 10),
                        child: _InlineErrorMessage(message: inlineError!),
                      ),
              ),
              const SizedBox(height: 18),
              const SectionTitle(title: '색을 선택해요'),
              const SizedBox(height: 12),
              _ColorPicker(
                options: _colorOptions,
                selected: _selectedColor,
                onSelect: (c) => setModal(() => _selectedColor = c),
              ),
              const SizedBox(height: 24),
              SoftPrimaryButton(
                text: '추가하기',
                onTap: () {
                  final name = _controller.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('요인 이름을 입력해 주세요.')),
                    );
                    return;
                  }
                  final provider = context.read<TriggersProvider>();
                  if (provider.triggers.any(
                    (trigger) => _isSameTriggerLabel(trigger.name, name),
                  )) {
                    setModal(() => inlineError = '이미 있는 요인이에요.');
                    return;
                  }
                  provider.addTrigger(name: name, color: _selectedColor);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSheet(int index) {
    final trigger = context.read<TriggersProvider>().triggers[index];
    _controller.text = koTrigger(trigger.name);
    _selectedColor = trigger.color;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8F2F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionTitle(title: '요인 편집하기'),
                  TriggerChip(
                    label: _controller.text.isNotEmpty
                        ? koTrigger(_controller.text)
                        : '미리보기',
                    color: _selectedColor,
                    selected: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InputBox(controller: _controller, hint: '요인 이름을 입력해 주세요'),
              const SizedBox(height: 18),
              const SectionTitle(title: '색을 선택해요'),
              const SizedBox(height: 12),
              _ColorPicker(
                options: _colorOptions,
                selected: _selectedColor,
                onSelect: (c) => setModal(() => _selectedColor = c),
              ),
              const SizedBox(height: 24),
              SoftPrimaryButton(
                text: '저장하기',
                onTap: () {
                  final name = _controller.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('요인 이름을 입력해 주세요.')),
                    );
                    return;
                  }
                  context.read<TriggersProvider>().updateTrigger(
                    index,
                    name: name,
                    color: _selectedColor,
                  );
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Center(
                  child: Text(
                    '취소',
                    style: TextStyle(fontSize: 14, color: Color(0xFF9888A0)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFF8F2F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('이 요인을 삭제할까요?'),
        content: const Text(
          '요인을 삭제해도 지난 기록은 삭제되지 않아요. 해당 기록은 미분류로 표시돼요.',
          style: TextStyle(fontSize: 13, color: Color(0xFF9888A0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Color(0xFF9888A0))),
          ),
          TextButton(
            onPressed: () {
              context.read<TriggersProvider>().removeTrigger(index);
              Navigator.pop(context);
            },
            child: const Text('삭제', style: TextStyle(color: Color(0xFFB87888))),
          ),
        ],
      ),
    );
  }

  bool _isSameTriggerLabel(String existing, String input) {
    final existingLabels = _triggerLabelKeys(existing);
    final inputLabels = _triggerLabelKeys(input);
    return existingLabels.any(inputLabels.contains);
  }

  Set<String> _triggerLabelKeys(String value) {
    return {value.trim().toLowerCase(), koTrigger(value).trim().toLowerCase()};
  }

  @override
  Widget build(BuildContext context) {
    final triggers = context.watch<TriggersProvider>().triggers;

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
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF201C28),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: SectionTitle(title: '스트레스 요인')),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                '일상 속 스트레스 요인을 차분히 살펴보고 관리해요',
                style: TextStyle(fontSize: 13, color: Color(0xFF9888A0)),
              ),
            ),
            const SizedBox(height: 18),


            Expanded(
              child: triggers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.label_outline,
                              color: Color(0xFFC0B0C0),
                              size: 40,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '아직 등록된 요인이 없어요.\n첫 스트레스 요인을 추가해 보세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9888A0),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      itemCount: triggers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final trigger = triggers[index];
                        final color = trigger.color;
                        return GestureDetector(
                          onTap: () => _showEditSheet(index),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
                            ),
                            borderRadius: 18,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TriggerChip(
                                      label: koTrigger(trigger.name),
                                      color: color,
                                      selected: true,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${trigger.eventCount}건',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFC0B0C0),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _confirmDelete(index),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                    color: Color(0xFFB87888),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),


            Padding(
              padding: const EdgeInsets.all(22),
              child: SoftPrimaryButton(
                text: '+ 새 요인 추가하기',
                onTap: _showAddSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _ColorPicker extends StatelessWidget {
  final List<Color> options;
  final Color selected;
  final ValueChanged<Color> onSelect;
  const _ColorPicker({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((color) {
        final isSelected = selected == color;
        return GestureDetector(
          onTap: () => onSelect(color),
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: const Color(0xFF201C28), width: 2)
                  : Border.all(color: Colors.white, width: 1),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InputBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _InputBox({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: Color(0xFF201C28)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFC0B0C0)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

class _InlineErrorMessage extends StatelessWidget {
  final String message;

  const _InlineErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4E4).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFB87888).withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFFB87888)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB87888),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
