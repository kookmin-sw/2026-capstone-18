import 'dart:async';

import 'package:flutter/foundation.dart';

import 'biosignal_capture_service.dart';
import 'stress_detection.dart';

class BiosignalCaptureController extends ChangeNotifier {
  final BiosignalCaptureService _service;
  StreamSubscription<CaptureStatus>? _statusSub;
  StreamSubscription<StressDetection>? _detectionSub;

  String _state = 'idle';
  int _elapsedSec = 0;
  int _windowsUploaded = 0;
  String? _error;
  bool _watchConnected = false;
  StressDetection? _latestDetection;

  bool get watchConnected => _watchConnected;
  StressDetection? get latestDetection => _latestDetection;

  BiosignalCaptureController({
    BiosignalCaptureService? service,
    Stream<StressDetection>? detectionStream,
  }) : _service = service ?? BiosignalCaptureService() {
    _statusSub = _service.statusStream().listen(_onStatus);
    _detectionSub = (detectionStream ?? stressDetectionStream()).listen(_onDetection);
  }

  String get state => _state;
  int get elapsedSec => _elapsedSec;
  int get windowsUploaded => _windowsUploaded;
  String? get error => _error;

  Future<void> start({required String accessToken, Duration? duration, String source = 'watch'}) async {
    _error = null;
    _latestDetection = null;
    notifyListeners();
    final secs = duration?.inSeconds;
    await _service.start(accessToken: accessToken, durationSec: secs, source: source);
  }

  Future<void> refreshWatchConnection() async {
    final connected = await _service.isWatchConnected();
    if (connected != _watchConnected) {
      _watchConnected = connected;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _service.stop();
  }

  void _onStatus(CaptureStatus s) {
    _state = s.state;
    _elapsedSec = s.elapsedSec;
    _windowsUploaded = s.windowsUploaded;
    _error = s.error;
    notifyListeners();
  }

  void _onDetection(StressDetection d) {
    _latestDetection = d;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _detectionSub?.cancel();
    super.dispose();
  }
}
