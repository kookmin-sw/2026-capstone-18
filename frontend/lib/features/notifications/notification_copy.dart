import 'dart:ui';

enum NotificationCopyKey {
  permissionTitle,
  permissionBody,
  permissionDenied,
  permissionEnabled,
  settingsTitle,
  settingsEnabledSubtitle,
  settingsDisabledSubtitle,
  realtimeFallbackTitle,
  realtimeFallbackBody,
  stressDetectedTitle,
  stressDetectedBody,
  dailyReminderTitle,
  dailyReminderBody,
}

class LocalizedNotificationCopy {
  final String title;
  final String body;

  const LocalizedNotificationCopy({required this.title, required this.body});
}

String localizedNotificationText(NotificationCopyKey key, {Locale? locale}) {
  final isKorean = _isKorean(locale);

  return switch (key) {
    NotificationCopyKey.permissionTitle =>
      isKorean ? '알림을 받아볼까요?' : 'Turn on notifications?',
    NotificationCopyKey.permissionBody =>
      isKorean
          ? '스트레스 신호와 리마인더를 필요한 순간에 알려드릴게요.'
          : "We'll let you know about stress signals and gentle reminders when they matter.",
    NotificationCopyKey.permissionDenied =>
      isKorean
          ? '알림이 꺼져 있어요. 설정에서 언제든 다시 켤 수 있어요.'
          : 'Notifications are off. You can turn them back on in Settings anytime.',
    NotificationCopyKey.permissionEnabled =>
      isKorean
          ? '알림을 켰어요. 필요한 순간에 조용히 알려드릴게요.'
          : "Notifications are on. We'll keep reminders gentle.",
    NotificationCopyKey.settingsTitle => isKorean ? '알림' : 'Notifications',
    NotificationCopyKey.settingsEnabledSubtitle =>
      isKorean
          ? '스트레스 알림과 매일 리마인더가 켜져 있어요'
          : 'Stress alerts and daily reminders are on.',
    NotificationCopyKey.settingsDisabledSubtitle =>
      isKorean ? '알림이 꺼져 있어요' : 'Notifications are off.',
    NotificationCopyKey.realtimeFallbackTitle =>
      isKorean ? '새로운 소식이 도착했어요' : 'You have a new update',
    NotificationCopyKey.realtimeFallbackBody =>
      isKorean
          ? '확인할 준비가 되면 앱에서 살펴봐요.'
          : "Open the app when you're ready to take a look.",
    NotificationCopyKey.stressDetectedTitle =>
      isKorean ? '스트레스 신호가 감지됐어요' : 'A stress signal was detected',
    NotificationCopyKey.stressDetectedBody =>
      isKorean
          ? '잠시 멈추고 지금의 느낌을 기록해 볼까요?'
          : "Take a moment to note how you're feeling.",
    NotificationCopyKey.dailyReminderTitle =>
      isKorean ? '오늘의 신호를 기록해요' : "Log today's signal",
    NotificationCopyKey.dailyReminderBody =>
      isKorean
          ? '몸과 마음의 흐름을 짧게 남겨 보세요.'
          : 'Take a moment to record your body and mood.',
  };
}

LocalizedNotificationCopy localizedNotificationPayload({
  required NotificationCopyKey titleKey,
  required NotificationCopyKey bodyKey,
  Locale? locale,
}) {
  return LocalizedNotificationCopy(
    title: localizedNotificationText(titleKey, locale: locale),
    body: localizedNotificationText(bodyKey, locale: locale),
  );
}

LocalizedNotificationCopy localizedPermissionRationale({Locale? locale}) {
  return localizedNotificationPayload(
    titleKey: NotificationCopyKey.permissionTitle,
    bodyKey: NotificationCopyKey.permissionBody,
    locale: locale,
  );
}

LocalizedNotificationCopy localizedStressDetectedNotification({
  Locale? locale,
}) {
  return localizedNotificationPayload(
    titleKey: NotificationCopyKey.stressDetectedTitle,
    bodyKey: NotificationCopyKey.stressDetectedBody,
    locale: locale,
  );
}

LocalizedNotificationCopy localizedDailyReminderNotification({Locale? locale}) {
  return localizedNotificationPayload(
    titleKey: NotificationCopyKey.dailyReminderTitle,
    bodyKey: NotificationCopyKey.dailyReminderBody,
    locale: locale,
  );
}

bool _isKorean(Locale? locale) {
  final languageCode =
      (locale ?? PlatformDispatcher.instance.locale).languageCode;
  return languageCode.toLowerCase() == 'ko';
}
