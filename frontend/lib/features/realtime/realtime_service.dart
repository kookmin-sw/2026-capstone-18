import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/secure_token_storage.dart';
import '../events/models/stress_event.dart';
import '../notifications/notification_copy.dart';

class RealtimeService {
  final SecureTokenStorage tokenStorage;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  RealtimeService({required this.tokenStorage});

  Future<void> connect({
    required void Function(StressEvent event) onStressEvent,
    required void Function(String message) onNotification,
  }) async {
    await disconnect();

    final token = await tokenStorage.readAccessToken();
    if (token == null || token.isEmpty) return;

    final uri = Uri.parse(
      ApiConfig.websocketUrl,
    ).replace(queryParameters: {'token': token});
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen((message) {
      final decoded = jsonDecode('$message') as Map<String, dynamic>;
      final type = decoded['type'];
      final data = decoded['payload'] ?? decoded['data'];

      if ((type == 'event.created' || type == 'stress_event') &&
          data is Map<String, dynamic>) {
        onStressEvent(StressEvent.fromJson(data));
      } else if (type == 'insight.ready' || type == 'notification') {
        final message = decoded['message'];
        onNotification(
          _displayMessage(message is String ? message : null) ??
              localizedNotificationText(
                NotificationCopyKey.realtimeFallbackBody,
              ),
        );
      }
    });
  }

  String? _displayMessage(String? message) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return RegExp(r'[가-힣]').hasMatch(trimmed) ? trimmed : null;
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }
}
