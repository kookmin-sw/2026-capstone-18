import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/api_config.dart';
import 'notification_copy.dart';
import 'notifications_api.dart';

class NotificationService {
  final NotificationsApi notificationsApi;
  final FirebaseMessaging? _messagingOverride;

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
    if (ApiConfig.useMock) {
      debugPrint('FCM registration skipped: mock mode');
      return;
    }

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
}