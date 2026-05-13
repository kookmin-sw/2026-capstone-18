import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../features/biosignals/biosignal_capture_controller.dart';
import '../../features/biosignals/stress_detection.dart';
import '../../features/consent/consent_provider.dart';
import 'capture_summary_screen.dart';

class WatchConnectScreen extends StatefulWidget {
  const WatchConnectScreen({super.key});

  @override
  State<WatchConnectScreen> createState() => _WatchConnectScreenState();
}

class _WatchConnectScreenState extends State<WatchConnectScreen> {
  late final BiosignalCaptureController _controller;
  final _tokenStorage = SecureTokenStorage();
  Duration? _selectedDuration = const Duration(minutes: 10);
  String _selectedSource = 'watch';
  String _lastSeenState = 'idle';

  @override
  void initState() {
    super.initState();
    _controller = BiosignalCaptureController();
    _controller.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.refreshWatchConnection();
    });
  }

  void _onUpdate() {
    if (!mounted) return;
    if (_lastSeenState != 'done' && _controller.state == 'done') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CaptureSummaryScreen(
            elapsedSec: _controller.elapsedSec,
            windowsUploaded: _controller.windowsUploaded,
          ),
        ),
      );
    }
    _lastSeenState = _controller.state;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onStart() async {
    final token = await _tokenStorage.readAccessToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요해요.')));
      return;
    }
    await _controller.start(
      accessToken: token,
      duration: _selectedDuration,
      source: _selectedSource,
    );
  }

  Future<void> _onStop() async {
    await _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    final isCapturing = _controller.state == 'capturing';
    context.watch<ConsentProvider>(); // rebuild when consent changes
    final mm = (_controller.elapsedSec ~/ 60).toString().padLeft(2, '0');
    final ss = (_controller.elapsedSec % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('생체신호 캡처'),
      ),
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatusChip(state: _controller.state),
                        const Spacer(),
                        Text(
                          '경과 $mm:$ss',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textB,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _InlineMetricRow(
                      items: [
                        _InlineMetricItem(
                          label: '업로드된 구간',
                          value: '${_controller.windowsUploaded}',
                        ),
                        _InlineMetricItem(
                          label: '상태',
                          value: _statusLabel(_controller.state),
                        ),
                      ],
                    ),
                    if (_shouldShowErrorNotice(
                      _controller.error,
                      _selectedSource,
                    )) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorNotice(rawError: _controller.error!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!isCapturing) ...[
                Consumer<ConsentProvider>(
                  builder: (context, provider, _) {
                    final granted =
                        provider.consent?.rawBiosignalConsent == true &&
                        provider.consent?.consentRevokedAt == null;
                    final usesWatchSource = _selectedSource == 'watch';
                    final isLoadingConsent = provider.isLoading;
                    return GlassCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '원시 생체신호 데이터 업로드 동의',
                                  style: AppTextStyles.cardTitle.copyWith(
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              if (usesWatchSource)
                                Switch(
                                  value: granted,
                                  activeThumbColor: AppColors.primary,
                                  activeTrackColor: AppColors.primaryLight,
                                  onChanged: isLoadingConsent
                                      ? null
                                      : (next) async {
                                          await provider.updateConsent({
                                            'raw_biosignal_consent': next,
                                          });
                                        },
                                )
                              else
                                const _DemoSourceBadge(),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            isLoadingConsent && usesWatchSource
                                ? '현재 계정의 동의 상태를 확인하고 있어요.'
                                : !usesWatchSource
                                ? '합성 데이터는 실제 사용자 생체신호가 아니며, 이 동의와 무관하게 데모 캡처를 실행할 수 있어요.'
                                : granted
                                ? '시계의 원시 생체신호 데이터가 안전하게 업로드됩니다. 언제든지 끌 수 있어요.'
                                : '동의가 필요해요. 동의를 켜야 캡처를 시작할 수 있어요.',
                            style: AppTextStyles.caption.copyWith(
                              color: granted || !usesWatchSource
                                  ? AppColors.textM
                                  : AppColors.textB,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel(title: '캡처 방식'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _sourceChip('watch', '시계'),
                    _sourceChip('synthetic', '합성'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _watchStatusLine(),
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel(title: '지속 시간'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _durationChip(const Duration(minutes: 10), '10분'),
                    _durationChip(const Duration(minutes: 30), '30분'),
                    _durationChip(null, '직접 멈출 때까지'),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SoftPrimaryButton(
                  text: '캡처 시작',
                  onTap: _canStart() ? _onStart : null,
                ),
              ] else ...[
                _LiveCaptureView(
                  elapsedSec: _controller.elapsedSec,
                  windowsUploaded: _controller.windowsUploaded,
                  selectedDuration: _selectedDuration,
                  onStop: _onStop,
                ),
                if (_controller.latestDetection != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _DetectionCard(
                      detection: _controller.latestDetection!,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationChip(Duration? duration, String label) {
    return _CaptureChoiceChip(
      label: label,
      selected: _selectedDuration == duration,
      onTap: () => setState(() => _selectedDuration = duration),
    );
  }

  Widget _sourceChip(String source, String label) {
    return _CaptureChoiceChip(
      label: label,
      selected: _selectedSource == source,
      onTap: () {
        setState(() => _selectedSource = source);
        if (source == 'watch') {
          _controller.refreshWatchConnection();
        }
      },
    );
  }

  Widget _watchStatusLine() {
    if (_selectedSource != 'watch') return const SizedBox.shrink();
    final connected = _controller.watchConnected;
    return Row(
      children: [
        Icon(
          connected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 15,
          color: connected ? AppColors.phaseLuteal : AppColors.textM,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            connected ? '시계 연결됨' : '시계가 연결되지 않았어요. 시계 앱을 페어링해 주세요.',
            style: AppTextStyles.caption.copyWith(
              color: connected ? AppColors.textB : AppColors.textM,
            ),
          ),
        ),
      ],
    );
  }

  bool _canStart() {
    if (_selectedSource == 'synthetic') {
      return true;
    }

    final consentProvider = context.read<ConsentProvider>();
    if (consentProvider.isLoading) return false;

    final consent = consentProvider.consent;
    final granted =
        consent?.rawBiosignalConsent == true &&
        consent?.consentRevokedAt == null;
    return granted && _controller.watchConnected;
  }
}

class _StatusChip extends StatelessWidget {
  final String state;

  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final isCapturing = state == 'capturing';
    final isError = state == 'error';
    final color = isCapturing
        ? AppColors.primary
        : isError
        ? AppColors.primaryPressed
        : AppColors.textM;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isCapturing ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _statusLabel(state),
            style: AppTextStyles.label.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMetricItem {
  final String label;
  final String value;

  const _InlineMetricItem({required this.label, required this.value});
}

class _InlineMetricRow extends StatelessWidget {
  final List<_InlineMetricItem> items;

  const _InlineMetricRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < items.length; index += 1) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(items[index].label, style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  items[index].value,
                  style: AppTextStyles.cardTitle.copyWith(
                    color: AppColors.textB,
                  ),
                ),
              ],
            ),
          ),
          if (index != items.length - 1) const SizedBox(width: AppSpacing.md),
        ],
      ],
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String rawError;

  const _ErrorNotice({required this.rawError});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _userErrorLabel(rawError),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textB,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTextStyles.cardTitle);
  }
}

class _DemoSourceBadge extends StatelessWidget {
  const _DemoSourceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        '데모 신호',
        style: AppTextStyles.label.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CaptureChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CaptureChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.38)
          : Colors.white.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.42)
                  : AppColors.textL.withValues(alpha: 0.34),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: selected ? AppColors.primary : AppColors.textB,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String state) {
  return switch (state) {
    'capturing' => '캡처 중',
    'error' => '오류',
    'done' => '완료',
    'idle' => '대기 중',
    _ => '대기 중',
  };
}

String _userErrorLabel(String rawError) {
  final error = rawError.trim();
  if (error == 'watch_not_connected') {
    return '시계가 연결되지 않았어요.';
  }
  if (error == 'watch_send_failed') {
    return '시계로 캡처 시작 신호를 보내지 못했어요.';
  }
  if (error == 'watch_disconnected') {
    return '캡처 중 시계 연결이 끊어졌어요.';
  }
  if (error == 'missing_token') {
    return '로그인이 필요해요.';
  }
  if (error.startsWith('upload_warn_')) {
    return '일부 데이터 업로드 상태를 확인하지 못했어요. 캡처는 계속 진행 중이에요.';
  }
  return '캡처 상태를 확인하지 못했어요.';
}

bool _shouldShowErrorNotice(String? rawError, String selectedSource) {
  final error = rawError?.trim();
  if (error == null || error.isEmpty) {
    return false;
  }
  if (selectedSource != 'watch' && error.startsWith('watch_')) {
    return false;
  }
  return true;
}

class _LiveCaptureView extends StatefulWidget {
  final int elapsedSec;
  final int windowsUploaded;
  final Duration? selectedDuration;
  final VoidCallback onStop;

  const _LiveCaptureView({
    required this.elapsedSec,
    required this.windowsUploaded,
    required this.selectedDuration,
    required this.onStop,
  });

  @override
  State<_LiveCaptureView> createState() => _LiveCaptureViewState();
}

class _LiveCaptureViewState extends State<_LiveCaptureView>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (widget.elapsedSec ~/ 60).toString().padLeft(2, '0');
    final ss = (widget.elapsedSec % 60).toString().padLeft(2, '0');
    final totalSec = widget.selectedDuration?.inSeconds;
    final progress = totalSec != null && totalSec > 0
        ? (widget.elapsedSec / totalSec).clamp(0.0, 1.0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xl,
            horizontal: 20,
          ),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                          AppColors.primaryLight,
                          AppColors.primary,
                          _pulseController.value,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '캡처 중',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: _ProgressArcPainter(progress: progress),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$mm:$ss',
                          style: AppTextStyles.metricNumber.copyWith(
                            fontSize: 44,
                            color: AppColors.textH,
                          ),
                        ),
                        if (totalSec != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '/ ${(totalSec ~/ 60).toString().padLeft(2, '0')}:${(totalSec % 60).toString().padLeft(2, '0')}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textM,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatChip(
                    label: '업로드',
                    value: '${widget.windowsUploaded}',
                    sub: '구간',
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  _StatChip(
                    label: '데이터',
                    value: (widget.windowsUploaded * 240 / 1024)
                        .toStringAsFixed(1),
                    sub: 'MB',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('실시간 신호', style: AppTextStyles.cardTitle),
              const SizedBox(height: AppSpacing.md),
              _ChannelRow(
                label: 'HR',
                color: AppColors.primary,
                controller: _pulseController,
                rate: 0.3,
              ),
              const SizedBox(height: 10),
              _ChannelRow(
                label: 'PPG',
                color: AppColors.phaseFollicular,
                controller: _pulseController,
                rate: 1.0,
              ),
              const SizedBox(height: 10),
              _ChannelRow(
                label: 'EDA',
                color: AppColors.phaseLuteal,
                controller: _pulseController,
                rate: 0.7,
              ),
              const SizedBox(height: 10),
              _ChannelRow(
                label: 'ACC',
                color: AppColors.triggerHealth,
                controller: _pulseController,
                rate: 1.4,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _StopCaptureButton(onTap: widget.onStop),
      ],
    );
  }
}

class _ProgressArcPainter extends CustomPainter {
  final double? progress;
  _ProgressArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 6.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.phaseFollicular.withValues(alpha: 0.28);
    canvas.drawArc(rect, -1.5708, 6.2832, false, track);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          AppColors.phaseFollicular,
          AppColors.phaseMenstrual,
          AppColors.phaseFollicular,
        ],
        startAngle: -1.5708,
        endAngle: 4.7124,
      ).createShader(rect);
    final sweep = progress != null ? 6.2832 * progress! : 6.2832;
    canvas.drawArc(rect, -1.5708, sweep, false, fg);
  }

  @override
  bool shouldRepaint(_ProgressArcPainter old) => old.progress != progress;
}

class _StatChip extends StatelessWidget {
  final String label, value, sub;
  const _StatChip({
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: AppColors.textM,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textH,
          ),
        ),
        Text(
          sub,
          style: AppTextStyles.label.copyWith(
            color: AppColors.textM,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _StopCaptureButton extends StatelessWidget {
  final VoidCallback onTap;

  const _StopCaptureButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryPressed,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPressed.withValues(alpha: 0.24),
                blurRadius: 24,
                spreadRadius: -10,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Text(
            '캡처 중지',
            style: AppTextStyles.button.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final String label;
  final Color color;
  final AnimationController controller;
  final double rate;

  const _ChannelRow({
    required this.label,
    required this.color,
    required this.controller,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textM,
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) => CustomPaint(
                size: Size.infinite,
                painter: _WaveformPainter(
                  color: color,
                  phase: controller.value * rate * 6.2832,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Color color;
  final double phase;
  _WaveformPainter({required this.color, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final path = Path();
    final mid = size.height / 2;
    final n = 60;
    for (int i = 0; i <= n; i++) {
      final x = (i / n) * size.width;
      final t = (i / n) * 6.2832 * 2 + phase;
      final y =
          mid +
          (mid * 0.7) *
              (0.5 * (1 - 1) * 0 +
                  0.6 * mathSin(t) +
                  0.3 * mathSin(t * 2.3));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.phase != phase;
}

double mathSin(double x) => math.sin(x);

class _DetectionCard extends StatelessWidget {
  final StressDetection detection;
  const _DetectionCard({required this.detection});

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().difference(detection.detectedAt.toLocal());
    final agoMin = ago.inMinutes;
    final agoSec = ago.inSeconds % 60;
    final agoLabel = agoMin > 0 ? '$agoMin분 $agoSec초 전' : '$agoSec초 전';
    final probLabel = (detection.probStress * 100).toStringAsFixed(1);
    final stateLabel = detection.inStressEvent ? '스트레스 감지' : '정상';
    final color = detection.inStressEvent
        ? AppColors.primaryPressed
        : AppColors.phaseLuteal;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('최신 감지', style: AppTextStyles.label),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$stateLabel · 신뢰도 $probLabel%',
            style: AppTextStyles.cardTitle.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(agoLabel, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
