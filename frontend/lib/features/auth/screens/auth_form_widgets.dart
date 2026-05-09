import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

class AuthFormHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AuthFormHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.32),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.screenTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, textAlign: TextAlign.center, style: AppTextStyles.body),
      ],
    );
  }
}

class QuietAuthButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;

  const QuietAuthButton({
    super.key,
    required this.text,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  )
                : Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.textB,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

InputDecoration authInputDecoration({
  required String label,
  required IconData icon,
  String? hint,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.primary),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.50),
    labelStyle: AppTextStyles.caption.copyWith(color: AppColors.textM),
    hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textL),
    errorStyle: AppTextStyles.caption.copyWith(color: AppColors.primary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    enabledBorder: authInputBorder(Colors.white.withValues(alpha: 0.68)),
    focusedBorder: authInputBorder(AppColors.primary.withValues(alpha: 0.72)),
    errorBorder: authInputBorder(AppColors.primary.withValues(alpha: 0.72)),
    focusedErrorBorder: authInputBorder(AppColors.primary),
    disabledBorder: authInputBorder(Colors.white.withValues(alpha: 0.42)),
  );
}

OutlineInputBorder authInputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: color),
  );
}

String? validateAuthEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return '이메일을 입력해 주세요.';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  if (!valid) return '이메일 형식을 한 번 더 확인해 주세요.';
  return null;
}
