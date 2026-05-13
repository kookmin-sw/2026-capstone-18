import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/data/app_user.dart';
import '../../features/auth/user_display.dart';
import 'delete_account_screen.dart';

class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    final loginInfo = _loginInfoFor(user);

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
                    '계정 및 보안',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              const Text(
                '로그인 정보',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF201C28),
                ),
              ),

              const SizedBox(height: 12),

              _GlassCard(
                child: Column(
                  children: [
                    _InfoRow(
                      label: '계정',
                      value: loginInfo.accountLabel,
                      onTap: null,
                    ),
                    const Divider(color: Color(0x15000000), height: 1),
                    _InfoRow(
                      label: '비밀번호',
                      value: loginInfo.passwordLabel,
                      onTap: null,
                    ),
                  ],
                ),
              ),

              if (loginInfo.passwordHelper != null) ...[
                const SizedBox(height: 10),
                Text(
                  loginInfo.passwordHelper!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9888A0),
                    height: 1.5,
                  ),
                ),
              ],

              if (loginInfo.isAnonymous) ...[
                const SizedBox(height: 10),
                const Text(
                  '익명 계정은 이메일과 비밀번호가 연결되어 있지 않습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9888A0),
                    height: 1.5,
                  ),
                ),
              ],

              const SizedBox(height: 28),

              const Text(
                '주의가 필요한 설정',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF201C28),
                ),
              ),

              const SizedBox(height: 12),

              _GlassCard(
                child: _DangerRow(
                  title: '계정 삭제',
                  subtitle: '삭제된 계정은 다시 복구할 수 없어요',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DeleteAccountScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

_LoginInfo _loginInfoFor(AppUser? user) {
  final accountType = _normalizeAccountType(user?.accountType);
  final email = userEmail(user);

  if (accountType == 'anonymous') {
    return const _LoginInfo(
      accountLabel: '익명 계정',
      passwordLabel: '연결되지 않음',
      isAnonymous: true,
    );
  }

  if (accountType == 'google') {
    return _LoginInfo(
      accountLabel: email ?? 'Google 계정',
      passwordLabel: 'Google 계정으로 로그인',
      passwordHelper: 'Google 계정은 Google에서 비밀번호를 관리해요.',
    );
  }

  if (accountType == 'email') {
    return _LoginInfo(
      accountLabel: email ?? '계정 정보를 불러올 수 없어요',
      passwordLabel: '이메일 로그인',
    );
  }

  return _LoginInfo(
    accountLabel: email ?? '계정 정보를 불러올 수 없어요',
    passwordLabel: '계정 정보를 불러올 수 없어요',
  );
}

String? _normalizeAccountType(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized == 'anonymous' || normalized == 'anon') return 'anonymous';
  if (normalized == 'google') return 'google';
  if (normalized == 'email' || normalized == 'password') return 'email';
  return null;
}

class _LoginInfo {
  final String accountLabel;
  final String passwordLabel;
  final String? passwordHelper;
  final bool isAnonymous;

  const _LoginInfo({
    required this.accountLabel,
    required this.passwordLabel,
    this.passwordHelper,
    this.isAnonymous = false,
  });
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final clickable = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF201C28)),
              ),
            ),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  color: clickable
                      ? const Color(0xFFB87888)
                      : const Color(0xFF9888A0),
                  fontWeight: clickable ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            if (clickable) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFC0B0C0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DangerRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFFDAD5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Color(0xFFB87888),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '계정 삭제',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFB87888),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '삭제된 계정은 다시 복구할 수 없어요',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9888A0)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC0B0C0)),
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
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }
}
