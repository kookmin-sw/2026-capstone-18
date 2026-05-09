import 'package:flutter/material.dart';

import '../../core/storage/secure_token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../features/biosignals/biosignal_capture_controller.dart';
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
                ElevatedButton(
                  onPressed: _onStop,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                  child: const Text('캡처 중지'),
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
      onSelected: (_) => setState(() => _selectedSource = source),
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
    if (_selectedSource == 'watch' && !_controller.watchConnected) return false;
    return true;
  }
}
