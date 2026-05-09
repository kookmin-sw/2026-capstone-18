import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/soft_primary_button.dart';
import '../auth_provider.dart';
import 'auth_form_widgets.dart';
import 'email_forgot_password_screen.dart';
import 'email_register_screen.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isBusy = _submitting || auth.status == AuthStatus.checking;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로가기',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: isBusy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: AppGradientBackground(
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: Center(
                    child: GlassCard(
                      blur: 4,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthFormHeader(
                              icon: Icons.mail_outline_rounded,
                              title: '이메일로 로그인해요',
                              subtitle: '기록을 안전하게 이어서 확인해요',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _emailController,
                              enabled: !isBusy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: authInputDecoration(
                                label: '이메일',
                                icon: Icons.mail_outline_rounded,
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !isBusy,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: authInputDecoration(
                                label: '비밀번호',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  tooltip: _obscurePassword ? '보기' : '숨기기',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () {
                                          setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          );
                                        },
                                ),
                              ),
                              validator: _validatePassword,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SoftPrimaryButton(
                              text: '이메일로 로그인하기',
                              onTap: isBusy ? null : _submit,
                              isLoading: isBusy,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            QuietAuthButton(
                              text: 'Google 계정으로 계속하기',
                              onTap: isBusy ? null : _continueWithGoogle,
                              isLoading: isBusy,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _LoginTextActions(
                              enabled: !isBusy,
                              onCreateAccount: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const EmailRegisterScreen(),
                                  ),
                                );
                              },
                              onForgotPassword: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const EmailForgotPasswordScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
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

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _showSnackBar('입력한 내용을 한 번 더 확인해 주세요.');
      return;
    }

    setState(() => _submitting = true);

    final auth = context.read<AuthProvider>();
    final success = await auth.signInWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _submitting = false);
    _showSnackBar(auth.errorMessage ?? '로그인하지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _submitting = true);

    final auth = context.read<AuthProvider>();
    final success = await auth.continueWithGoogle();

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _submitting = false);
    _showSnackBar(auth.errorMessage ?? 'Google 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.');
  }

  String? _validateEmail(String? value) => validateAuthEmail(value);

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return '비밀번호를 입력해 주세요.';
    if (password.length < 6) return '비밀번호는 6자 이상 입력해 주세요.';
    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoginTextActions extends StatelessWidget {
  final bool enabled;
  final VoidCallback onCreateAccount;
  final VoidCallback onForgotPassword;

  const _LoginTextActions({
    required this.enabled,
    required this.onCreateAccount,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: buttonStyle,
          onPressed: enabled ? onCreateAccount : null,
          child: const Text('계정 만들기'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Text('·', style: TextStyle(color: AppColors.textL)),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: enabled ? onForgotPassword : null,
          child: const Text('비밀번호를 잊으셨나요?'),
        ),
      ],
    );
  }
}
