import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/biosignals/biosignal_capture_controller.dart';
import 'package:little_signals/features/biosignals/biosignal_capture_service.dart';

class _FakeService extends BiosignalCaptureService {
  final StreamController<CaptureStatus> ctrl = StreamController.broadcast();
  bool startCalled = false;
  bool stopCalled = false;
  String? lastToken;
  int? lastDurationSec;

  @override
  Stream<CaptureStatus> statusStream() => ctrl.stream;

  @override
  Future<void> start({
    required String accessToken,
    int? durationSec,
    String backendBase = 'https://api-staging.friendlykr.com',
  }) async {
    startCalled = true;
    lastToken = accessToken;
    lastDurationSec = durationSec;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }
}

void main() {
  test('controller forwards events from service stream', () async {
    final fake = _FakeService();
    final controller = BiosignalCaptureController(service: fake);
    final updates = <String>[];
    controller.addListener(() => updates.add(controller.state));

    fake.ctrl.add(const CaptureStatus(state: 'capturing', elapsedSec: 5, windowsUploaded: 0));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, 'capturing');
    expect(controller.elapsedSec, 5);
    expect(updates.contains('capturing'), isTrue);

    fake.ctrl.add(const CaptureStatus(state: 'done', elapsedSec: 600, windowsUploaded: 10));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, 'done');
    expect(controller.windowsUploaded, 10);
  });

  test('start invokes service.start with token + duration', () async {
    final fake = _FakeService();
    final controller = BiosignalCaptureController(service: fake);
    await controller.start(accessToken: 'tok', duration: const Duration(minutes: 10));
    expect(fake.startCalled, isTrue);
    expect(fake.lastToken, 'tok');
    expect(fake.lastDurationSec, 600);
  });

  test('stop invokes service.stop', () async {
    final fake = _FakeService();
    final controller = BiosignalCaptureController(service: fake);
    await controller.stop();
    expect(fake.stopCalled, isTrue);
  });
}
