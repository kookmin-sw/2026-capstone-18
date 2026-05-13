import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/soft_primary_button.dart';

Future<bool> showHealthConnectPermissionSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_border_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '건강 데이터 접근 권한이 필요해요',
                        style: AppTextStyles.cardTitle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '수면과 주기 기록을 불러오려면 Health Connect 접근 권한이 필요해요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6F6077),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                SoftPrimaryButton(
                  text: '권한 허용하기',
                  onTap: () => Navigator.pop(context, true),
                  height: 44,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      '나중에 할게요',
                      style: TextStyle(
                        color: Color(0xFF9888A0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  return result == true;
}
