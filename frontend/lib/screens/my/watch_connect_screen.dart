import 'dart:math' as _math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요해요.')),
      );
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
        title: const Text('Watch'),
      ),
      body: AppGradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text('상태: ${_controller.state}',
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text('경과 $mm:$ss · 업로드된 윈도우 ${_controller.windowsUploaded}'),
                      if (_controller.error != null) ...[
                        const SizedBox(height: 8),
                        Text('오류: ${_controller.error}',
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!isCapturing) ...[
                Consumer<ConsentProvider>(
                  builder: (context, provider, _) {
                    final granted = provider.consent?.rawBiosignalConsent == true
                        && provider.consent?.consentRevokedAt == null;
                    return GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '원시 생체신호 데이터 업로드 동의',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Switch(
                                  value: granted,
                                  onChanged: (next) async {
                                    await provider.updateConsent({
                                      'raw_biosignal_consent': next,
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              granted
                                  ? '시계의 원시 생체신호 데이터가 안전하게 백엔드에 업로드됩니다. 언제든지 끌 수 있어요.'
                                  : '동의가 필요해요. 동의를 켜야 캡처를 시작할 수 있어요.',
                              style: TextStyle(
                                fontSize: 12,
                                color: granted
                                    ? Colors.grey.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text('소스', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _sourceChip('watch', '시계'),
                    _sourceChip('synthetic', '합성'),
                  ],
                ),
                const SizedBox(height: 6),
                _watchStatusLine(),
                const SizedBox(height: 16),
                Text('지속 시간', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _durationChip(const Duration(minutes: 10), '10분'),
                    _durationChip(const Duration(minutes: 30), '30분'),
                    _durationChip(null, '직접 멈출 때까지'),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _canStart() ? _onStart : null, child: const Text('캡처 시작')),
              ] else ...[
                _LiveCaptureView(
                  elapsedSec: _controller.elapsedSec,
                  windowsUploaded: _controller.windowsUploaded,
                  selectedDuration: _selectedDuration,
                  onStop: _onStop,
                ),
                if (_controller.latestDetection != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _DetectionCard(detection: _controller.latestDetection!),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationChip(Duration? duration, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedDuration == duration,
      onSelected: (_) => setState(() => _selectedDuration = duration),
    );
  }

  Widget _sourceChip(String source, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedSource == source,
      onSelected: (_) {
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
    return Text(
      connected ? '시계 연결됨 ✓' : '시계 연결 안 됨 — 시계 앱을 페어링해 주세요',
      style: TextStyle(
        fontSize: 12,
        color: connected ? Colors.green.shade700 : Colors.orange.shade700,
      ),
    );
  }

  bool _canStart() {
    final consent = context.read<ConsentProvider>().consent;
    final granted = consent?.rawBiosignalConsent == true && consent?.consentRevokedAt == null;
    if (!granted) return false;
    // Don't gate on watchConnected — connectedNodes is unreliable.
    return true;
  }
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
        // Live timer + progress ring
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                            const Color(0xFFF8C4D7),
                            const Color(0xFFB89DDB),
                            _pulseController.value,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '캡처 중',
                        style: TextStyle(
                          color: Colors.pink.shade400,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
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
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D2433),
                            ),
                          ),
                          if (totalSec != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '/ ${(totalSec ~/ 60).toString().padLeft(2, '0')}:${(totalSec % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatChip(
                      label: '업로드',
                      value: '${widget.windowsUploaded}',
                      sub: '윈도우',
                    ),
                    const SizedBox(width: 24),
                    _StatChip(
                      label: '데이터',
                      value: '${(widget.windowsUploaded * 240 / 1024).toStringAsFixed(1)}',
                      sub: 'MB',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Animated channel waveforms
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '실시간 신호',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _ChannelRow(
                  label: 'HR',
                  color: Colors.pink.shade300,
                  controller: _pulseController,
                  rate: 0.3,
                ),
                const SizedBox(height: 10),
                _ChannelRow(
                  label: 'PPG',
                  color: Colors.purple.shade300,
                  controller: _pulseController,
                  rate: 1.0,
                ),
                const SizedBox(height: 10),
                _ChannelRow(
                  label: 'EDA',
                  color: Colors.teal.shade300,
                  controller: _pulseController,
                  rate: 0.7,
                ),
                const SizedBox(height: 10),
                _ChannelRow(
                  label: 'ACC',
                  color: Colors.amber.shade400,
                  controller: _pulseController,
                  rate: 1.4,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: widget.onStop,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('캡처 중지'),
        ),
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
      ..color = const Color(0x22B89DDB);
    canvas.drawArc(rect, -1.5708, 6.2832, false, track);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0xFFB89DDB), Color(0xFFF8C4D7), Color(0xFFB89DDB)],
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
  const _StatChip({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D2433),
          ),
        ),
        Text(
          sub,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
        ),
      ],
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
              color: Colors.grey.shade700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, __) => CustomPaint(
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
      final y = mid + (mid * 0.7) * (
        0.5 * (1 - 1) * 0 + // placeholder so formula is readable
        0.6 * math_sin(t) +
        0.3 * math_sin(t * 2.3)
      );
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

double math_sin(double x) => _math.sin(x);

class _DetectionCard extends StatelessWidget {
  final StressDetection detection;
  const _DetectionCard({required this.detection});

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().toUtc().difference(detection.detectedAt);
    final agoMin = ago.inMinutes;
    final agoSec = ago.inSeconds % 60;
    final agoLabel = agoMin > 0 ? '$agoMin분 $agoSec초 전' : '$agoSec초 전';
    final probLabel = (detection.probStress * 100).toStringAsFixed(1);
    final stateLabel = detection.inStressEvent ? '스트레스 감지' : '정상';
    final color = detection.inStressEvent ? Colors.orange.shade700 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('최신 감지', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '$stateLabel · 신뢰도 $probLabel%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(agoLabel, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
