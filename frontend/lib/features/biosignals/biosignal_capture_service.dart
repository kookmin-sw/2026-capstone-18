import 'dart:async';

import 'package:flutter/services.dart';

const _methodChannel = MethodChannel('littlesignals/capture');
const _eventChannel = EventChannel('littlesignals/capture/status');

class CaptureStatus {
  final String state;
  final int elapsedSec;
  final int windowsUploaded;
  final String? error;

  const CaptureStatus({
    required this.state,
    required this.elapsedSec,
    required this.windowsUploaded,
    this.error,
  });

  factory CaptureStatus.fromMap(Map<dynamic, dynamic> m) => CaptureStatus(
        state: (m['state'] as String?) ?? 'idle',
        elapsedSec: (m['elapsed_sec'] as int?) ?? 0,
        windowsUploaded: (m['windows_uploaded'] as int?) ?? 0,
        error: m['error'] as String?,
      );

  static const idle = CaptureStatus(state: 'idle', elapsedSec: 0, windowsUploaded: 0);
}

class BiosignalCaptureService {
  Stream<CaptureStatus>? _stream;

  Stream<CaptureStatus> statusStream() {
    _stream ??= _eventChannel
        .receiveBroadcastStream()
        .map((e) => CaptureStatus.fromMap(e as Map<dynamic, dynamic>));
    return _stream!;
  }

  Future<void> start({
    required String accessToken,
    int? durationSec,
    String backendBase = 'https://api-staging.friendlykr.com',
    String source = 'watch',
  }) async {
    await _methodChannel.invokeMethod<void>('start', <String, dynamic>{
      'accessToken': accessToken,
      'durationSec': durationSec ?? -1,
      'backendBase': backendBase,
      'source': source,
    });
  }

  Future<bool> isWatchConnected() async {
    final result = await _methodChannel.invokeMethod<bool>('isWatchConnected');
    return result ?? false;
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod<void>('stop');
  }
}
