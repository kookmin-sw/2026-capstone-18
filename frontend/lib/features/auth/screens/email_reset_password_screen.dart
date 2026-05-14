import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/soft_primary_button.dart';
import '../auth_provider.dart';
import 'auth_form_widgets.dart';

class EmailResetPasswordScreen extends StatefulWidget {
  const EmailResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailResetPasswordScreen> createState() =>
      _EmailResetPasswordScreenState();
}

class _EmailResetPasswordScreenState extends State<EmailResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateOtp(String? value) {
    final v = (value ?? '').trim();
    if (v.length < 6) return '6자리 코드를 입력해 주세요.';
    if (!RegExp(r'^[0-9]+$').hasMatch(v)) return '숫자만 입력해 주세요.';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.length < 8) return '비밀번호는 8자 이상이어야 해요.';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) {
      return '비밀번호가 일치하지 않아요.';
    }
    return null;
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    if (_submitting) return;

    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().resetPasswordWithOtp(
      email: widget.email,
      otp: _otpController.text.trim(),
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) {
      final message = context.read<AuthProvider>().errorMessage ??
          '비밀번호를 변경하지 못했어요. 잠시 후 다시 시도해 주세요.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    // Success — pop back to whichever screen launched the forgot flow.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('비밀번호를 변경했어요. 새 비밀번호로 로그인했어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로가기',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => Navigator.of(context).pop(),
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
                            AuthFormHeader(
                              icon: Icons.password_rounded,
                              title: '인증 코드를 입력해 주세요',
                              subtitle:
                                  '${widget.email}로 보낸 6자리 코드를 입력하고\n새 비밀번호를 설정해 주세요',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: authInputDecoration(
                                label: '인증 코드 (6자리)',
                                icon: Icons.pin_rounded,
                              ),
                              validator: _validateOtp,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: authInputDecoration(
                                label: '새 비밀번호 (8자 이상)',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _confirmController,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: authInputDecoration(
                                label: '새 비밀번호 확인',
                                icon: Icons.lock_outline_rounded,
                              ),
                              validator: _validateConfirm,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SoftPrimaryButton(
                              text: _submitting ? '변경 중...' : '비밀번호 변경',
                              onTap: _submitting ? null : _submit,
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
}
