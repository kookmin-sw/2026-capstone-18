import '../../core/utils/korean_ui_text.dart';

String getGreetingByTime(DateTime now, String nickname) {
  final name = koNickname(nickname);
  final hour = now.hour;

  if (hour >= 5 && hour < 12) {
    return '좋은 아침이에요, $name';
  }

  if (hour >= 12 && hour < 18) {
    return '좋은 오후예요, $name';
  }

  if (hour >= 18) {
    return '오늘 하루도 수고했어요, $name';
  }

  return '늦은 시간이네요, $name';
}
