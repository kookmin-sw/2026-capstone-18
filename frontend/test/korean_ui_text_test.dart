import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/utils/korean_ui_text.dart';

void main() {
  group('koNickname', () {
    test('adds Korean honorific only for display', () {
      expect(koNickname('Amy'), 'Amy님');
      expect(koNickname('지원'), '지원님');
    });

    test('falls back and avoids duplicate honorifics', () {
      expect(koNickname('   '), '사용자님');
      expect(koNickname('Mina님'), 'Mina님');
    });
  });

  group('rawNickname', () {
    test('removes display honorific before storage', () {
      expect(rawNickname('Amy님'), 'Amy');
      expect(rawNickname('지원님님'), '지원');
    });
  });
}
