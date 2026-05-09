import '../../core/utils/korean_ui_text.dart';
import 'data/app_user.dart';

const defaultUserDisplayName = '사용자';

String userDisplayName(AppUser? user) {
  final name = _trimmedOrNull(user?.name);
  if (name != null) return rawNickname(name);

  final email = _trimmedOrNull(user?.email);
  if (email != null) {
    final prefix = email.split('@').first.trim();
    return rawNickname(prefix);
  }

  return defaultUserDisplayName;
}

String userProfileSubtitle(AppUser? user) {
  return userEmail(user) ?? '익명 계정';
}

String? userEmail(AppUser? user) {
  return _trimmedOrNull(user?.email);
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
