import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/soft_primary_button.dart';
import '../auth_provider.dart';
import 'auth_form_widgets.dart';
import 'email_reset_password_screen.dart';

class EmailForgotPasswordScreen extends StatefulWidget {
  const EmailForgotPasswordScreen({super.key});

  @override
  State<EmailForgotPasswordScreen> createState() =>
      _EmailForgotPasswordScreenState();
}

class _EmailForgotPasswordScreenState extends State<EmailForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
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
                            const AuthFormHeader(
                              icon: Icons.lock_reset_rounded,
                              title: '비밀번호를 다시 설정해요',
                              subtitle: '가입한 이메일로 안내를 보내드릴게요',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              decoration: authInputDecoration(
                                label: '이메일',
                                icon: Icons.mail_outline_rounded,
                              ),
                              validator: validateAuthEmail,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SoftPrimaryButton(
                              text: '재설정 메일 받기',
                              onTap: _submit,
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
      _showSnackBar('이메일을 한 번 더 확인해 주세요.');
      return;
    }
    if (_submitting) return;

    final email = _emailController.text.trim();
    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().forgotPassword(email);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) {
      _showSnackBar(
        context.read<AuthProvider>().errorMessage ?? '잠시 후 다시 시도해 주세요.',
      );
      return;
    }
    // Backend always returns 200 (no enumeration). Navigate regardless.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailResetPasswordScreen(email: email),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
