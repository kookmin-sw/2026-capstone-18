import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/trigger_chip.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/user_display.dart';
import '../../features/cycles/cycle_provider.dart';
import '../../features/triggers/triggers_provider.dart';
import 'my_cycle_screen.dart';
import 'my_triggers_screen.dart';
import 'watch_connect_screen.dart';
import 'privacy_policy_screen.dart';
import 'account_security_screen.dart';
import 'sleep_data_screen.dart';

class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final cycleProvider = context.watch<CycleProvider>();
    final triggers = context.watch<TriggersProvider>().triggers;
    final displayName = userDisplayName(user);
    final editableNickname = rawNickname(user?.name ?? '');
    final accountType = user?.accountType ?? 'anonymous';
    final cycle = cycleProvider.currentCycle;

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
                      GlassCard(
                        blur: 4,
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFFDAD5),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Color(0xFFB87888),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 42,
                                      ),
                                      child: Text(
                                        displayName,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.screenTitle
                                            .copyWith(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w600,
                                              height: 1.2,
                                            ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: IconButton(
                                        tooltip: '닉네임 수정',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 19,
                                          color: Color(0xFFB87888),
                                        ),
                                        onPressed: () => _showNicknameDialog(
                                          context,
                                          editableNickname,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      _SectionLabel(label: '주기'),
                      const SizedBox(height: 8),
                      _MenuCard(
                        key: const ValueKey('my-cycle-menu'),
                        icon: Icons.calendar_month_outlined,
                        iconColor: const Color(0xFFB87888),
                        iconBg: const Color(0xFFFFDAD5),
                        title: '생리 주기 기록',
                        subtitle: cycle == null
                            ? '최근 생리 시작일을 추가하거나 워치와 동기화해요'
                            : '최근 생리 시작일 ${_formatShortDate(cycle.lastPeriodStart)} · 평균 주기 ${cycleProvider.calculatedCycleLength}일',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyCycleScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      _SectionLabel(label: '스트레스 요인'),
                      const SizedBox(height: 8),
                      _GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '스트레스 요인',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF201C28),
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MyTriggersScreen(),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFFC0B0C0),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ...triggers.map(
                                  (trigger) => TriggerChip(
                                    label: koTrigger(trigger.name),
                                    color: trigger.color,
                                    selected: true,
                                  ),
                                ),
                                const TriggerChip(
                                  label: '+ 추가',
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      _SectionLabel(label: '수면'),
                      const SizedBox(height: 8),
                      _MenuCard(
                        icon: Icons.bedtime_outlined,
                        iconColor: const Color(0xFFB87888),
                        iconBg: const Color(0xFFFFDAD5),
                        title: '수면 데이터',
                        subtitle: '수면 흐름을 차분히 살펴봐요',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SleepDataScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      _SectionLabel(label: '기기'),
                      const SizedBox(height: 8),
                      _MenuCard(
                        icon: Icons.watch_outlined,
                        iconColor: const Color(0xFF9888A0),
                        iconBg: const Color(0xFFF2DCF3),
                        title: 'Galaxy Watch',
                        subtitle: '연결되어 있어요',
                        subtitleColor: const Color(0xFF94D0BC),
                        showDot: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WatchConnectScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      _SectionLabel(label: '데이터 및 개인정보'),
                      const SizedBox(height: 8),
                      _MenuCard(
                        icon: Icons.privacy_tip_outlined,
                        iconColor: const Color(0xFF9888A0),
                        iconBg: const Color(0xFFF2DCF3),
                        title: '개인정보 처리방침',
                        subtitle: '데이터가 어떻게 쓰이는지 확인해요',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PrivacyPolicyScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      _SectionLabel(label: '계정'),
                      const SizedBox(height: 8),
                      _MenuCard(
                        icon: Icons.shield_outlined,
                        iconColor: const Color(0xFFB87888),
                        iconBg: const Color(0xFFFFE4E4),
                        title: '계정 및 보안',
                        subtitle: koAccountType(accountType),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountSecurityScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFFF8F2F5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: const Text(
                                '로그아웃',
                                style: AppTextStyles.sectionTitle,
                              ),
                              content: const Text(
                                '정말 로그아웃할까요?',
                                style: AppTextStyles.body,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    '취소',
                                    style: TextStyle(color: Color(0xFF9888A0)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await auth.logout();
                                  },
                                  child: const Text(
                                    '로그아웃',
                                    style: TextStyle(color: Color(0xFFB87888)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              '로그아웃',
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 100),
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

  Future<void> _showNicknameDialog(
    BuildContext context,
    String currentName,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _NicknameDialog(currentName: currentName),
    );
  }

  String _formatShortDate(DateTime date) {
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

class _NicknameDialog extends StatefulWidget {
  final String currentName;

  const _NicknameDialog({required this.currentName});

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF8F2F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('닉네임을 바꿔요', style: AppTextStyles.sectionTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.62),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Color(0xFF9888A0))),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('저장하기', style: TextStyle(color: Color(0xFFB87888))),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final nickname = _controller.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (nickname.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('닉네임을 입력해 주세요.')));
      return;
    }

    final auth = context.read<AuthProvider>();
    final saved = await auth.updateNickname(nickname);
    if (!mounted) return;

    if (saved) {
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('닉네임을 저장했어요.')));
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(auth.errorMessage ?? '닉네임을 저장하지 못했어요.')),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.sectionLabel.copyWith(color: AppColors.textL),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final bool showDot;
  final VoidCallback onTap;

  const _MenuCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.subtitleColor = const Color(0xFFC0B0C0),
    this.showDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.cardTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (showDot)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: subtitleColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          subtitle,
                          style: AppTextStyles.caption.copyWith(
                            color: subtitleColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFC0B0C0)),
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
