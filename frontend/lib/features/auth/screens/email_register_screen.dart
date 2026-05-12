import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_gradient_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/soft_primary_button.dart';
import '../auth_provider.dart';
import 'auth_form_widgets.dart';

class EmailRegisterScreen extends StatefulWidget {
  const EmailRegisterScreen({super.key});

  @override
  State<EmailRegisterScreen> createState() => _EmailRegisterScreenState();
}

class _EmailRegisterScreenState extends State<EmailRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();

  _EmailRegisterAction? _loadingAction;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isBusy = _loadingAction != null || auth.status == AuthStatus.checking;

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
                              icon: Icons.favorite_border_rounded,
                              title: '계정 만들기',
                              subtitle: '나의 작은 신호를 안전하게 이어갈 수 있어요',
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
                              validator: validateAuthEmail,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !isBusy,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
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
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _passwordConfirmController,
                              enabled: !isBusy,
                              obscureText: _obscurePasswordConfirm,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: authInputDecoration(
                                label: '비밀번호 확인',
                                icon: Icons.lock_reset_rounded,
                                suffix: IconButton(
                                  tooltip: _obscurePasswordConfirm
                                      ? '보기'
                                      : '숨기기',
                                  icon: Icon(
                                    _obscurePasswordConfirm
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () {
                                          setState(
                                            () => _obscurePasswordConfirm =
                                                !_obscurePasswordConfirm,
                                          );
                                        },
                                ),
                              ),
                              validator: _validatePasswordConfirm,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _nameController,
                              enabled: !isBusy,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.name],
                              decoration: authInputDecoration(
                                label: '이름 또는 닉네임',
                                hint: '선택',
                                icon: Icons.person_outline_rounded,
                              ),
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SoftPrimaryButton(
                              text: '이메일로 계정 만들기',
                              onTap: isBusy ? null : _submit,
                              isLoading:
                                  _loadingAction == _EmailRegisterAction.email,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            QuietAuthButton(
                              text: 'Google 계정으로 계속하기',
                              onTap: isBusy ? null : _continueWithGoogle,
                              isLoading:
                                  _loadingAction == _EmailRegisterAction.google,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton(
                              onPressed: isBusy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('돌아가기'),
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
    if (_loadingAction != null) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _showSnackBar('입력한 내용을 한 번 더 확인해 주세요.');
      return;
    }

    setState(() => _loadingAction = _EmailRegisterAction.email);
    final auth = context.read<AuthProvider>();
    var success = false;
    try {
      success = await auth.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _trimmedOrNull(_nameController.text),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingAction = null);
      }
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      return;
    }

    _showSnackBar(auth.errorMessage ?? '계정을 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  Future<void> _continueWithGoogle() async {
    if (_loadingAction != null) return;

    setState(() => _loadingAction = _EmailRegisterAction.google);
    final auth = context.read<AuthProvider>();
    var success = false;
    try {
      success = await auth.continueWithGoogle();
    } finally {
      if (mounted) {
        setState(() => _loadingAction = null);
      }
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      return;
    }

    _showSnackBar(auth.errorMessage ?? 'Google 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.');
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return '비밀번호를 입력해 주세요.';
    if (password.length < 6) return '비밀번호는 6자 이상 입력해 주세요.';
    return null;
  }

  String? _validatePasswordConfirm(String? value) {
    if ((value ?? '').isEmpty) return '비밀번호를 한 번 더 입력해 주세요.';
    if (value != _passwordController.text) return '비밀번호가 일치하지 않아요.';
    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _trimmedOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

enum _EmailRegisterAction { email, google }
