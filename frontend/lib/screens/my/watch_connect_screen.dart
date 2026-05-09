import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';

class WatchConnectScreen extends StatefulWidget {
  const WatchConnectScreen({super.key});

  @override
  State<WatchConnectScreen> createState() => _WatchConnectScreenState();
}

class _WatchConnectScreenState extends State<WatchConnectScreen> {
  bool isConnected = false;
  bool isSearching = true;

  void _toggleConnection() {
    setState(() {
      if (isConnected) {
        isConnected = false;
        isSearching = false;
      } else {
        isSearching = true;

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              isConnected = true;
              isSearching = false;
            });
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  child: Column(
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
                            '워치',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF201C28),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 42),

                      Container(
                        width: 138,
                        height: 138,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEDE7FF), Color(0xFFFFDAD5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFB87888).withValues(alpha: 0.18),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.watch_outlined,
                          size: 62,
                          color: Color(0xFF9888A0),
                        ),
                      ),

                      const SizedBox(height: 34),

                      const Text(
                        '워치를 연결해요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF201C28),
                          height: 1.15,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Galaxy Watch로 몸의 신호를 더 부드럽게 살펴봐요.\n블루투스를 켜고 워치를 가까이 두세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: Color(0xFF9888A0),
                        ),
                      ),

                      const SizedBox(height: 34),

                      _WatchStatusCard(
                        isSearching: isSearching,
                        isConnected: isConnected,
                      ),

                      const SizedBox(height: 28),

                      Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: GestureDetector(
                            onTap: _toggleConnection,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? const Color(0xFF565B66)
                                    : const Color(0xFFB87888),
                                borderRadius: BorderRadius.circular(26),
                              ),
                              child: Center(
                                child: Text(
                                  isConnected ? '연결 해제하기' : '연결하기',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (!isConnected) ...[
                        const SizedBox(height: 18),

                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            '지금은 건너뛰기',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF9888A0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WatchStatusCard extends StatelessWidget {
  final bool isSearching;
  final bool isConnected;

  const _WatchStatusCard({
    required this.isSearching,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        borderRadius: 28,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 142),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(
                  child: isSearching
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            color: Color(0xFF8E9DFF),
                            backgroundColor: Color(0xFFFFDAD5),
                          ),
                        )
                      : Icon(
                          isConnected
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 52,
                          color: isConnected
                              ? const Color(0xFF94D0BC)
                              : const Color(0xFFB87888),
                        ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    _body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9888A0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title {
    if (isSearching) return '워치를 찾고 있어요';
    if (isConnected) return 'Galaxy Watch가 연결됐어요';
    return '워치가 아직 연결되지 않았어요';
  }

  String get _body {
    if (isSearching) return '잠시만 기다려 주세요';
    if (isConnected) return '신호를 동기화할 준비가 되었어요.';
    return '워치를 다시 연결해 보세요.';
  }
}
