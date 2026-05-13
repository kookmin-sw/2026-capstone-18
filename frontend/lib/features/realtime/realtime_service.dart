import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/secure_token_storage.dart';
import '../events/models/stress_event.dart';
import '../notifications/notification_copy.dart';

enum RealtimeEventType { created, updated, deleted }

class RealtimeEventMessage {
  final RealtimeEventType type;
  final String id;

  const RealtimeEventMessage({required this.type, required this.id});
}

class RealtimeService {
  final SecureTokenStorage tokenStorage;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  RealtimeService({required this.tokenStorage});

  Future<void> connect({
    required FutureOr<void> Function(RealtimeEventMessage message)
    onEventMessage,
    required void Function(String message) onNotification,
  }) async {
    if (_channel != null) return;

    await disconnect();

    final token = await tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) return;

    final uri = Uri.parse(
      ApiConfig.websocketUrl,
    ).replace(queryParameters: {'token': token});
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen(
      (message) {
        final decoded = jsonDecode('$message') as Map<String, dynamic>;
        final eventMessage = parseEventMessage(decoded);
        if (eventMessage != null) {
          onEventMessage(eventMessage);
          return;
        }

        final type = decoded['type'];
        final data = decoded['payload'] ?? decoded['data'];

        if ((type == 'event.created' || type == 'stress_event') &&
            data is Map<String, dynamic>) {
          onEventMessage(
            RealtimeEventMessage(
              type: RealtimeEventType.created,
              id: StressEvent.fromJson(data).id,
            ),
          );
        } else if (type == 'insight.ready' || type == 'notification') {
          final message = decoded['message'];
          onNotification(
            _displayMessage(message is String ? message : null) ??
                localizedNotificationText(
                  NotificationCopyKey.realtimeFallbackBody,
                ),
          );
        }
      },
      onDone: _clearChannel,
      onError: (_) => _clearChannel(),
    );
  }

  static RealtimeEventMessage? parseEventMessage(
    Map<String, dynamic> envelope,
  ) {
    final type = envelope['type'] as String?;
    final eventType = switch (type) {
      'events.created' || 'event.created' => RealtimeEventType.created,
      'events.updated' || 'event.updated' => RealtimeEventType.updated,
      'events.deleted' || 'event.deleted' => RealtimeEventType.deleted,
      _ => null,
    };

    if (eventType == null) return null;

    final data = _normalizeData(envelope['data'] ?? envelope['payload']);
    final id =
        _stringValue(data?['id']) ??
        _stringValue(data?['event_id']) ??
        _stringValue(envelope['id']) ??
        _stringValue(envelope['event_id']);

    if (id == null || id.isEmpty) return null;

    return RealtimeEventMessage(type: eventType, id: id);
  }

  static Map<String, dynamic>? _normalizeData(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return _normalizeData(decoded['data'] ?? decoded['payload']) ??
              decoded;
        }
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          return _normalizeData(map['data'] ?? map['payload']) ?? map;
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  String? _displayMessage(String? message) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return RegExp(r'[가-힣]').hasMatch(trimmed) ? trimmed : null;
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _clearChannel();
  }

  void _clearChannel() {
    _subscription = null;
    _channel = null;
  }
}
