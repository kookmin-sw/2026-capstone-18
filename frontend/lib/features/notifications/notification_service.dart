import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_copy.dart';
import 'notifications_api.dart';
import '../realtime/realtime_service.dart';

class NotificationService {
  static const _stressSignalChannelId = 'stress_signal_events';
  static const _stressSignalChannelName = 'Stress signals';
  static const _stressSignalChannelDescription =
      'Notifications for detected stress signals.';
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsInitialized = false;

  final NotificationsApi notificationsApi;
  final FirebaseMessaging? _messagingOverride;
  StreamSubscription<RemoteMessage>? _foregroundMessagesSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  Future<void> Function(String eventId)? _onStressEventTap;
  bool _messageHandlingInitialized = false;

  NotificationService({
    required this.notificationsApi,
    FirebaseMessaging? messaging,
  }) : _messagingOverride = messaging;

  LocalizedNotificationCopy get permissionRationale {
    return localizedPermissionRationale();
  }

  String get permissionDeniedMessage {
    return localizedNotificationText(NotificationCopyKey.permissionDenied);
  }

  String get permissionEnabledMessage {
    return localizedNotificationText(NotificationCopyKey.permissionEnabled);
  }

  Future<void> requestPermissionAndRegister() async {
    if (Firebase.apps.isEmpty) {
      debugPrint('FCM registration skipped: Firebase is not initialized.');
      return;
    }

    try {
      final messaging = _messagingOverride ?? FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();

      debugPrint('FCM permission status: ${settings.authorizationStatus.name}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM registration skipped: permission denied');
        return;
      }

      final token = await messaging.getToken();

      if (kDebugMode && token != null && token.isNotEmpty) {
        debugPrint('FCM token received');
      }

      if (token == null || token.isEmpty) {
        debugPrint('FCM registration skipped: token is null');
        return;
      }

      await notificationsApi.registerDeviceToken(token);
      debugPrint('FCM token registered with backend');
    } catch (error, stackTrace) {
      debugPrint('FCM registration failed');

      if (kDebugMode) {
        debugPrint('$error');
        debugPrint('$stackTrace');
      }
    }
  }

  Future<void> initializeMessageHandling({
    required Future<void> Function(String eventId) onStressEventTap,
  }) async {
    _onStressEventTap = onStressEventTap;

    if (Firebase.apps.isEmpty) {
      debugPrint('FCM message handling skipped: Firebase is not initialized.');
      return;
    }

    await _ensureLocalNotificationsInitialized(
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    if (_messageHandlingInitialized) return;
    _messageHandlingInitialized = true;

    _foregroundMessagesSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) {
      unawaited(showRemoteMessageNotification(message));
    });

    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      unawaited(_handleRemoteMessageTap(message));
    });

    final messaging = _messagingOverride ?? FirebaseMessaging.instance;
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      unawaited(_handleRemoteMessageTap(initialMessage));
    }

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        response?.payload != null) {
      _handleNotificationPayload(response!.payload!);
    }
  }

  Stream<RemoteMessage> get foregroundMessages {
    return FirebaseMessaging.onMessage;
  }

  Future<void> unregisterCurrentDevice() async {
    if (Firebase.apps.isEmpty) return;

    final messaging = _messagingOverride ?? FirebaseMessaging.instance;
    final token = await messaging.getToken();

    if (token != null) {
      await notificationsApi.unregisterDeviceToken(token);
    }
  }

  Future<void> dispose() async {
    await _foregroundMessagesSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _foregroundMessagesSubscription = null;
    _messageOpenedSubscription = null;
    _messageHandlingInitialized = false;
    _onStressEventTap = null;
  }

  static Future<void> showRemoteMessageNotification(
    RemoteMessage message,
  ) async {
    final eventMessage = eventMessageFromRemoteData(message.data);
    if (eventMessage == null ||
        eventMessage.type != RealtimeEventType.created) {
      return;
    }

    await _ensureLocalNotificationsInitialized();

    final copy = localizedStressDetectedNotification();
    await _localNotifications.show(
      id: eventMessage.id.hashCode & 0x7fffffff,
      title: copy.title,
      body: copy.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _stressSignalChannelId,
          _stressSignalChannelName,
          channelDescription: _stressSignalChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _payloadForEventMessage(eventMessage),
    );
  }

  static RealtimeEventMessage? eventMessageFromRemoteData(
    Map<String, dynamic> data,
  ) {
    final nestedEnvelope = _decodeEnvelope(data['data']);
    final envelope = nestedEnvelope ?? data;

    return RealtimeService.parseEventMessage(envelope);
  }

  static Future<void> _ensureLocalNotificationsInitialized({
    void Function(NotificationResponse response)?
    onDidReceiveNotificationResponse,
  }) async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _stressSignalChannelId,
        _stressSignalChannelName,
        description: _stressSignalChannelDescription,
        importance: Importance.high,
      ),
    );

    _localNotificationsInitialized = true;
  }

  static Map<String, dynamic>? _decodeEnvelope(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String _payloadForEventMessage(RealtimeEventMessage message) {
    return jsonEncode({
      'type': switch (message.type) {
        RealtimeEventType.created => 'events.created',
        RealtimeEventType.updated => 'events.updated',
        RealtimeEventType.deleted => 'events.deleted',
      },
      'data': {'id': message.id},
    });
  }

  Future<void> _handleRemoteMessageTap(RemoteMessage message) async {
    final eventMessage = eventMessageFromRemoteData(message.data);
    if (eventMessage == null ||
        eventMessage.type == RealtimeEventType.deleted) {
      return;
    }

    await _onStressEventTap?.call(eventMessage.id);
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) return;
    _handleNotificationPayload(payload);
  }

  void _handleNotificationPayload(String payload) {
    final envelope = _decodeEnvelope(payload);
    if (envelope == null) return;

    final eventMessage = RealtimeService.parseEventMessage(envelope);
    if (eventMessage == null ||
        eventMessage.type == RealtimeEventType.deleted) {
      return;
    }

    unawaited(_onStressEventTap?.call(eventMessage.id));
  }
}
