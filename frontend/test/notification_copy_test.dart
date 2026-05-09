import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/notifications/notification_copy.dart';

void main() {
  test('returns Korean notification copy for Korean locale', () {
    final permission = localizedPermissionRationale(locale: const Locale('ko'));
    final stress = localizedStressDetectedNotification(
      locale: const Locale('ko'),
    );

    expect(permission.title, '알림을 받아볼까요?');
    expect(permission.body, contains('알려드릴게요'));
    expect(stress.title, '스트레스 신호가 감지됐어요');
    expect(stress.body, contains('기록해 볼까요'));
  });

  test('returns English notification copy for non-Korean locale', () {
    final permission = localizedPermissionRationale(locale: const Locale('en'));
    final daily = localizedDailyReminderNotification(
      locale: const Locale('en'),
    );

    expect(permission.title, 'Turn on notifications?');
    expect(permission.body, contains('gentle reminders'));
    expect(daily.title, "Log today's signal");
    expect(daily.body, contains('body and mood'));
  });

  test('localizes app-internal notification status messages', () {
    expect(
      localizedNotificationText(
        NotificationCopyKey.permissionDenied,
        locale: const Locale('ko'),
      ),
      '알림이 꺼져 있어요. 설정에서 언제든 다시 켤 수 있어요.',
    );
    expect(
      localizedNotificationText(
        NotificationCopyKey.permissionDenied,
        locale: const Locale('en'),
      ),
      'Notifications are off. You can turn them back on in Settings anytime.',
    );
    expect(
      localizedNotificationText(
        NotificationCopyKey.settingsEnabledSubtitle,
        locale: const Locale('en'),
      ),
      'Stress alerts and daily reminders are on.',
    );
  });
}
