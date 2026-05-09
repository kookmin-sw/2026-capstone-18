import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                    '개인정보 처리방침',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF201C28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              _PolicyCard(
                title: '1. 수집하는 정보',
                body:
                    'LittleSignals는 스트레스 기록, 생리 주기 정보, 선택한 스트레스 요인, 워치 연결 상태, 이메일 같은 기본 계정 정보를 수집할 수 있어요.',
              ),

              _PolicyCard(
                title: '2. 데이터를 사용하는 방법',
                body:
                    '데이터는 스트레스 흐름을 시각화하고, 주기 단계와의 연결을 살펴보며, 월간 리포트와 개인화된 경험을 제공하는 데 사용돼요.',
              ),

              _PolicyCard(
                title: '3. 건강 데이터',
                body:
                    '스트레스와 생리 주기 정보는 민감할 수 있어요. LittleSignals는 이 정보를 신중히 다루고, 나의 패턴을 이해하는 기능에만 사용해요.',
              ),

              _PolicyCard(
                title: '4. 워치 연결',
                body:
                    'Galaxy Watch를 연결하면 실시간 감지와 기록을 돕기 위해 워치의 스트레스 관련 신호를 사용할 수 있어요.',
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final String title;
  final String body;

  const _PolicyCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF201C28),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: Color(0xFF9888A0),
            ),
          ),
        ],
      ),
    );
  }
}
