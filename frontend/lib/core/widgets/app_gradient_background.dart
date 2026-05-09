import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppGradientBackground extends StatelessWidget {
  final Widget child;
  final bool includeSafeArea;

  const AppGradientBackground({
    super.key,
    required this.child,
    this.includeSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.background),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFBFD),
                      Color(0xFFFDF7FB),
                      Color(0xFFFFFAFB),
                    ],
                    stops: [0.0, 0.52, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -160,
              right: -130,
              child: Container(
                width: 420,
                height: 420,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.topGlow,
                ),
              ),
            ),
            Positioned(
              top: 190,
              left: -190,
              child: Container(
                width: 360,
                height: 360,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.sideGlow,
                ),
              ),
            ),
            Positioned(
              bottom: -210,
              left: -140,
              child: Container(
                width: 480,
                height: 480,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.bottomGlow,
                ),
              ),
            ),
            Positioned.fill(
              child: includeSafeArea ? SafeArea(child: child) : child,
            ),
          ],
        ),
      ),
    );
  }
}
