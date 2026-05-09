import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;
  final double? height;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 24,
    this.blur = 0,
    this.height,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.60),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.30),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: 140,
            height: 110,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(topLeft: radius.topLeft),
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.05,
                  colors: [
                    Colors.white.withValues(alpha: 0.46),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 1,
            right: 1,
            top: 1,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14),
            blurRadius: 44,
            spreadRadius: -14,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: const Color(0xFFB7A6D8).withValues(alpha: 0.12),
            blurRadius: 34,
            spreadRadius: -18,
            offset: const Offset(-8, 12),
          ),
          BoxShadow(
            color: const Color(0xFF3B2332).withValues(alpha: 0.05),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: blur <= 0
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: card,
              ),
      ),
    );
  }
}
