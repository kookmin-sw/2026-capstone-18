import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/soft_primary_button.dart';
import '../auth_provider.dart';
import 'auth_form_widgets.dart';
import 'email_login_screen.dart';
import 'email_register_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isChecking = auth.status == AuthStatus.checking;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 44,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 3),
                      const _BrandIntro(),
                      const SizedBox(height: 42),
                      if (auth.errorMessage != null) ...[
                        _AuthErrorMessage(message: auth.errorMessage!),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      SoftPrimaryButton(
                        text: '시작하기',
                        onTap: isChecking
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const EmailRegisterScreen(),
                                  ),
                                );
                              },
                      ),
                      const SizedBox(height: 12),
                      QuietAuthButton(
                        text: '이미 계정이 있으신가요?',
                        onTap: isChecking
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const EmailLoginScreen(),
                                  ),
                                );
                              },
                      ),
                      const Spacer(flex: 2),
                      _AnonymousAction(
                        enabled: !isChecking,
                        onAnonymousStart: auth.signInAnonymously,
                      ),
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
}

class _BrandIntro extends StatelessWidget {
  const _BrandIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 42,
                spreadRadius: -10,
                offset: const Offset(0, 22),
              ),
              BoxShadow(
                color: const Color(0xFFB7A6D8).withValues(alpha: 0.18),
                blurRadius: 36,
                spreadRadius: -12,
                offset: const Offset(-8, 14),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Luma',
          textAlign: TextAlign.center,
          style: AppTextStyles.display.copyWith(
            fontSize: 35,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF211D27),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '스트레스와 생리 주기의 흐름을 함께 기록해 보세요',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textM,
            height: 1.62,
          ),
        ),
      ],
    );
  }
}

class _AuthErrorMessage extends StatelessWidget {
  final String message;

  const _AuthErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.54)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _AnonymousAction extends StatelessWidget {
  final bool enabled;
  final VoidCallback onAnonymousStart;

  const _AnonymousAction({
    required this.enabled,
    required this.onAnonymousStart,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTextStyles.caption.copyWith(
      color: AppColors.textM,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onAnonymousStart : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text('익명으로 시작하기', style: textStyle),
          ),
        ),
      ),
    );
  }
}
