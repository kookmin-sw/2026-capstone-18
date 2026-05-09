import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final oldPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hideOld = true;
  bool hideNew = true;
  bool hideConfirm = true;

  @override
  void dispose() {
    oldPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _savePassword() {
    if (newPasswordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('새 비밀번호가 서로 일치하지 않습니다.')));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('비밀번호 변경됐습니다.')));

    Navigator.pop(context);
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
                    '비밀번호 변경',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              const Text(
                '비밀번호를 변경해요',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF201C28),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                '현재 비밀번호를 입력한 뒤 새 비밀번호를 설정해 주세요.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF9888A0),
                ),
              ),

              const SizedBox(height: 26),

              _PasswordField(
                label: '현재 비밀번호',
                controller: oldPasswordController,
                obscureText: hideOld,
                onToggle: () => setState(() => hideOld = !hideOld),
              ),

              const SizedBox(height: 14),

              _PasswordField(
                label: '새 비밀번호',
                controller: newPasswordController,
                obscureText: hideNew,
                onToggle: () => setState(() => hideNew = !hideNew),
              ),

              const SizedBox(height: 14),

              _PasswordField(
                label: '새 비밀번호 확인',
                controller: confirmPasswordController,
                obscureText: hideConfirm,
                onToggle: () => setState(() => hideConfirm = !hideConfirm),
              ),

              const SizedBox(height: 28),

              GestureDetector(
                onTap: _savePassword,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB87888),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Text(
                      '저장하기',
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
}

class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscureText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(fontSize: 14, color: Color(0xFF201C28)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF9888A0), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Icon(
              obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: const Color(0xFFC0B0C0),
            ),
          ),
        ),
      ),
    );
  }
}
