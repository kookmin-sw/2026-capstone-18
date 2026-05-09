import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class TriggerChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const TriggerChip({
    super.key,
    required this.label,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? _stronger(color) : AppColors.textM;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.58),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: selected ? 0.16 : 0.07),
              blurRadius: selected ? 18 : 12,
              spreadRadius: -9,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: textColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Color _stronger(Color input) {
    final hsl = HSLColor.fromColor(input);
    return hsl
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
  }
}
