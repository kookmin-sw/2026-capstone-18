import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/auth/data/app_user.dart';
import 'package:little_signals/features/auth/user_display.dart';

void main() {
  const emptyMaps = <String, dynamic>{};

  test('uses name when it is present', () {
    const user = AppUser(
      id: '1',
      email: 'dana@example.com',
      name: 'Dana',
      accountType: 'user',
      consent: emptyMaps,
      settings: emptyMaps,
    );

    expect(userDisplayName(user), 'Dana');
    expect(userProfileSubtitle(user), 'dana@example.com');
  });

  test('uses email prefix when name is missing', () {
    const user = AppUser(
      id: '2',
      email: 'jina@example.com',
      name: null,
      accountType: 'user',
      consent: emptyMaps,
      settings: emptyMaps,
    );

    expect(userDisplayName(user), 'jina');
    expect(userProfileSubtitle(user), 'jina@example.com');
  });

  test('uses anonymous labels without name or email', () {
    const user = AppUser(
      id: '3',
      email: null,
      name: null,
      accountType: 'anonymous',
      consent: emptyMaps,
      settings: emptyMaps,
    );

    expect(userDisplayName(user), '사용자');
    expect(userProfileSubtitle(user), '익명 계정');
  });

  test('returns raw nickname for identity display', () {
    const user = AppUser(
      id: '4',
      email: null,
      name: '지원님',
      accountType: 'anonymous',
      consent: emptyMaps,
      settings: emptyMaps,
    );

    expect(userDisplayName(user), '지원');
  });
}
