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
  FutureOr<void> Function(RealtimeEventMessage message)? _onEventMessage;
  void Function(String message)? _onNotification;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  bool _connecting = false;
  int _reconnectAttempts = 0;

  RealtimeService({required this.tokenStorage});

  Future<void> connect({
    required FutureOr<void> Function(RealtimeEventMessage message)
    onEventMessage,
    required void Function(String message) onNotification,
  }) async {
    _onEventMessage = onEventMessage;
    _onNotification = onNotification;
    _shouldReconnect = true;

    if (_channel != null || _connecting) return;

    await _openConnection();
  }

  Future<void> _openConnection() async {
    if (!_shouldReconnect || _channel != null || _connecting) return;

    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final token = await tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) {
      _connecting = false;
      return;
    }

    try {
      final uri = Uri.parse(ApiConfig.websocketUrl);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      if (!_shouldReconnect) {
        await channel.sink.close();
        return;
      }
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleConnectionClosed,
        onError: (_) => _handleConnectionClosed(),
      );
      _reconnectAttempts = 0;
    } catch (_) {
      _clearChannel();
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(dynamic message) {
    final decoded = _decodeEnvelope(message);
    if (decoded == null) return;

    final eventMessage = parseEventMessage(decoded);
    if (eventMessage != null) {
      final onEventMessage = _onEventMessage;
      if (onEventMessage != null) {
        unawaited(Future.sync(() => onEventMessage(eventMessage)));
      }
      return;
    }

    final type = decoded['type'];
    final data = decoded['payload'] ?? decoded['data'];

    if ((type == 'event.created' || type == 'stress_event') &&
        data is Map<String, dynamic>) {
      final onEventMessage = _onEventMessage;
      if (onEventMessage != null) {
        unawaited(
          Future.sync(
            () => onEventMessage(
              RealtimeEventMessage(
                type: RealtimeEventType.created,
                id: StressEvent.fromJson(data).id,
              ),
            ),
          ),
        );
      }
    } else if (type == 'insight.ready' || type == 'notification') {
      final message = decoded['message'];
      _onNotification?.call(
        _displayMessage(message is String ? message : null) ??
            localizedNotificationText(NotificationCopyKey.realtimeFallbackBody),
      );
    }
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
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _onEventMessage = null;
    _onNotification = null;
    final subscription = _subscription;
    final channel = _channel;
    _clearChannel();
    await subscription?.cancel();
    await channel?.sink.close();
  }

  void _clearChannel() {
    _subscription = null;
    _channel = null;
  }

  void _handleConnectionClosed() {
    _clearChannel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer != null || _channel != null) {
      return;
    }
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(_reconnectDelay(), () {
      _reconnectTimer = null;
      unawaited(_openConnection());
    });
  }

  Duration _reconnectDelay() {
    const seconds = [1, 2, 4, 8, 16, 30];
    final index = (_reconnectAttempts - 1).clamp(0, seconds.length - 1).toInt();
    return Duration(seconds: seconds[index]);
  }

  Map<String, dynamic>? _decodeEnvelope(dynamic message) {
    try {
      final decoded = jsonDecode('$message');
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }
}
