import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/notifications/notification_service.dart';
import 'package:little_signals/features/realtime/realtime_service.dart';

void main() {
  group('Realtime event contract', () {
    test('parses backend events.created websocket envelope', () {
      final message = RealtimeService.parseEventMessage({
        'type': 'events.created',
        'data': {'id': 'event-1'},
      });

      expect(message?.type, RealtimeEventType.created);
      expect(message?.id, 'event-1');
    });

    test('parses backend events.updated websocket envelope', () {
      final message = RealtimeService.parseEventMessage({
        'type': 'events.updated',
        'data': {'id': 'event-2'},
      });

      expect(message?.type, RealtimeEventType.updated);
      expect(message?.id, 'event-2');
    });

    test('parses backend events.deleted websocket envelope', () {
      final message = RealtimeService.parseEventMessage({
        'type': 'events.deleted',
        'data': {'id': 'event-3'},
      });

      expect(message?.type, RealtimeEventType.deleted);
      expect(message?.id, 'event-3');
    });

    test('parses backend FCM nested data envelope', () {
      final message = NotificationService.eventMessageFromRemoteData({
        'type': 'events.created',
        'data': jsonEncode({
          'type': 'events.created',
          'data': {'id': 'event-4'},
        }),
      });

      expect(message?.type, RealtimeEventType.created);
      expect(message?.id, 'event-4');
    });
  });
}
