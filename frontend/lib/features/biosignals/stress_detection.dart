import 'dart:async';

import 'package:flutter/services.dart';

const _detectionChannel = EventChannel('littlesignals/capture/detections');

class StressDetection {
  final int sessionElapsedSec;
  final DateTime detectedAt;
  final double probStress;
  final String state;
  final bool inStressEvent;
  final bool shouldNotify;

  const StressDetection({
    required this.sessionElapsedSec,
    required this.detectedAt,
    required this.probStress,
    required this.state,
    required this.inStressEvent,
    required this.shouldNotify,
  });

  factory StressDetection.fromMap(Map<dynamic, dynamic> m) => StressDetection(
        sessionElapsedSec: (m['session_elapsed_sec'] as int?) ?? 0,
        detectedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['detected_at_ms'] as int?) ?? 0,
          isUtc: true,
        ),
        probStress: (m['prob_stress'] as num?)?.toDouble() ?? 0.0,
        state: (m['state'] as String?) ?? 'Baseline',
        inStressEvent: m['in_stress_event'] == true,
        shouldNotify: m['should_notify'] == true,
      );
}

/// One Stream per process (the underlying EventChannel only supports a single listener).
Stream<StressDetection>? _detectionStream;

Stream<StressDetection> stressDetectionStream() {
  _detectionStream ??= _detectionChannel
      .receiveBroadcastStream()
      .map((e) => StressDetection.fromMap(e as Map<dynamic, dynamic>));
  return _detectionStream!;
}
