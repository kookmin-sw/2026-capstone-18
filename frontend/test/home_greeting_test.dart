import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/features/home/greeting.dart';

void main() {
  test('returns morning greeting from 05:00 to 11:59', () {
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 5), 'Dana'),
      '좋은 아침이에요, Dana님',
    );
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 11, 59), 'Dana'),
      '좋은 아침이에요, Dana님',
    );
  });

  test('returns afternoon greeting from 12:00 to 17:59', () {
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 12), 'Dana'),
      '좋은 오후예요, Dana님',
    );
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 17, 59), 'Dana'),
      '좋은 오후예요, Dana님',
    );
  });

  test('returns evening greeting from 18:00 to 23:59', () {
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 18), 'Dana'),
      '오늘 하루도 수고했어요, Dana님',
    );
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 23, 59), 'Dana'),
      '오늘 하루도 수고했어요, Dana님',
    );
  });

  test('returns late-night greeting from 00:00 to 04:59', () {
    expect(getGreetingByTime(DateTime(2026, 5, 9), 'Dana'), '늦은 시간이네요, Dana님');
    expect(
      getGreetingByTime(DateTime(2026, 5, 9, 4, 59), 'Dana'),
      '늦은 시간이네요, Dana님',
    );
  });

  test('falls back to anonymous nickname when nickname is blank', () {
    expect(getGreetingByTime(DateTime(2026, 5, 9, 8), '   '), '좋은 아침이에요, 사용자님');
  });

  test('does not duplicate honorific suffix', () {
    expect(getGreetingByTime(DateTime(2026, 5, 9, 8), '지원님'), '좋은 아침이에요, 지원님');
  });
}
