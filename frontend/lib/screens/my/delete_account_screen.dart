import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/privacy/data/privacy_api.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool agreed = false;
  bool submitting = false;

  Future<void> _requestDeletion() async {
    if (!agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('계속하려면 내용을 확인하고 동의해 주세요.')));
      return;
    }
    if (submitting) return;

    setState(() => submitting = true);
    try {
      await context.read<PrivacyApi>().deleteAccount();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 삭제 요청을 보내지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    } finally {
      if (mounted) setState(() => submitting = false);
    }

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    await authProvider.logout();
    if (!navigator.mounted) return;

    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('계정 삭제 요청이 접수되었어요. 다시 로그인하면 30일 안에 요청을 취소할 수 있어요.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF201C28),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '계정 삭제',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDAD5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB87888),
                  size: 34,
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                '계정을 삭제하기 전에',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF201C28),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                '삭제를 요청하기 전에 아래 내용을 확인해 주세요. 건강 기록, 스트레스 이력, 생리 주기 인사이트에 영향을 줄 수 있어요.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: Color(0xFF9888A0),
                ),
              ),

              const SizedBox(height: 24),

              _WarningCard(
                title: '30일의 대기 기간이 있어요',
                body:
                    '삭제를 요청하면 계정이 삭제 예정 상태가 돼요. 30일 안에 다시 로그인하면 요청을 취소할 수 있어요.',
              ),

              _WarningCard(
                title: '개인 데이터가 삭제돼요',
                body:
                    '대기 기간이 끝나면 스트레스 기록, 스트레스 요인, 생리 주기 기록, 리포트, 연결된 기기 데이터가 삭제돼요.',
              ),

              _WarningCard(
                title: '이후에는 되돌릴 수 없어요',
                body: '30일이 지나 삭제가 완료되면 계정과 데이터는 복구할 수 없어요.',
              ),

              const SizedBox(height: 22),

              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: agreed,
                      activeColor: const Color(0xFFB87888),
                      onChanged: (value) {
                        setState(() => agreed = value ?? false);
                      },
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          '요청을 취소하지 않으면 30일 뒤 계정이 삭제된다는 것을 이해했어요.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: Color(0xFF201C28),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              GestureDetector(
                onTap: agreed ? _requestDeletion : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: agreed
                        ? const Color(0xFFB87888)
                        : const Color(0xFFC0B0C0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Text(
                      '계정 삭제 요청하기',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Center(
                  child: Text(
                    '취소',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9888A0),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String title;
  final String body;

  const _WarningCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF201C28),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF9888A0),
            ),
          ),
        ],
      ),
    );
  }
}
