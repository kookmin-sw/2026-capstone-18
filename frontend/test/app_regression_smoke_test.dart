import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/errors/api_exception.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/core/theme/app_colors.dart';
import 'package:little_signals/core/theme/app_theme.dart';
import 'package:little_signals/core/utils/korean_ui_text.dart';
import 'package:little_signals/features/auth/auth_provider.dart';
import 'package:little_signals/features/auth/data/app_user.dart';
import 'package:little_signals/features/auth/data/auth_api.dart';
import 'package:little_signals/features/auth/screens/login_screen.dart';
import 'package:little_signals/features/consent/consent_provider.dart';
import 'package:little_signals/features/consent/data/consent_api.dart';
import 'package:little_signals/features/cycles/cycle_provider.dart';
import 'package:little_signals/features/cycles/data/cycles_api.dart';
import 'package:little_signals/features/cycles/models/cycle.dart';
import 'package:little_signals/features/cycles/models/watch_cycle_data.dart';
import 'package:little_signals/features/cycles/services/watch_cycle_service.dart';
import 'package:little_signals/features/events/data/events_api.dart';
import 'package:little_signals/features/events/events_provider.dart';
import 'package:little_signals/features/events/models/stress_event.dart';
import 'package:little_signals/features/home/home_provider.dart';
import 'package:little_signals/features/insight/data/ai_insights_api.dart';
import 'package:little_signals/features/insight/data/morning_tip.dart';
import 'package:little_signals/features/insight/data/weekly_report.dart';
import 'package:little_signals/features/insight/insight_provider.dart';
import 'package:little_signals/features/privacy/data/privacy_api.dart';
import 'package:little_signals/features/settings/data/settings_api.dart';
import 'package:little_signals/features/settings/settings_provider.dart';
import 'package:little_signals/features/sleep/data/sleep_api.dart';
import 'package:little_signals/features/sleep/models/sleep_log.dart';
import 'package:little_signals/features/sleep/sleep_provider.dart';
import 'package:little_signals/features/triggers/data/categories_api.dart';
import 'package:little_signals/features/triggers/triggers_provider.dart';
import 'package:little_signals/main.dart';
import 'package:little_signals/screens/home/events_log_screen.dart';
import 'package:little_signals/screens/home/stress_log_screen.dart';
import 'package:little_signals/screens/insight/insight_screen.dart';
import 'package:little_signals/screens/my/change_password_screen.dart';
import 'package:little_signals/screens/my/my_cycle_screen.dart';
import 'package:little_signals/screens/my/my_triggers_screen.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'auth landing supports login/signup navigation and anonymous start',
    (tester) async {
      final data = _SmokeData(authStatus: AuthStatus.unauthenticated);

      await tester.pumpWidget(
        _SmokeApp(data: data, child: const LoginScreen()),
      );
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      expect(find.text('Luma'), findsOneWidget);

      expect(find.text('시작하기'), findsOneWidget);
      expect(find.text('이미 계정이 있으신가요?'), findsOneWidget);
      expect(find.text('익명으로 시작하기'), findsOneWidget);
      expect(find.text('이메일'), findsNothing);
      expect(find.text('비밀번호'), findsNothing);
      expect(find.text('Google 계정으로 계속하기'), findsNothing);

      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('나의 작은 신호를 안전하게 이어갈 수 있어요'), findsOneWidget);
      expect(find.text('이메일로 계정 만들기'), findsOneWidget);
      expect(find.text('Google 계정으로 계속하기'), findsOneWidget);

      await _systemBack(tester);
      _expectNoFlutterException(tester);
      expect(find.text('Luma'), findsOneWidget);

      await tester.tap(find.text('이미 계정이 있으신가요?'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('이메일로 로그인해요'), findsOneWidget);
      expect(find.text('이메일로 로그인하기'), findsOneWidget);
      expect(find.text('Google 계정으로 계속하기'), findsOneWidget);

      await tester.tap(find.text('비밀번호를 잊으셨나요?'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('비밀번호를 다시 설정해요'), findsOneWidget);
      await _systemBack(tester);
      _expectNoFlutterException(tester);
      expect(find.text('이메일로 로그인해요'), findsOneWidget);

      await tester.tap(find.text('계정 만들기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('나의 작은 신호를 안전하게 이어갈 수 있어요'), findsOneWidget);

      await _systemBack(tester);
      _expectNoFlutterException(tester);
      expect(find.text('Luma'), findsOneWidget);

      await tester.tap(find.text('익명으로 시작하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(data.auth.status, AuthStatus.authenticated);
    },
  );

  testWidgets(
    'main tabs, push/pop, stress log, cycle, sleep, watch, insight, and my pages smoke test',
    (tester) async {
      final data = _SmokeData(authStatus: AuthStatus.authenticated);
      await data.load();

      await tester.pumpWidget(_SmokeApp(data: data, child: const MainScreen()));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      await tester.tap(find.text('스트레스 기록해요'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('스트레스 기록'), findsOneWidget);
      expect(find.text('업무'), findsWidgets);
      expect(find.text('대인관계'), findsWidgets);
      expect(find.text('가족'), findsWidgets);
      expect(find.text('학업'), findsWidgets);
      expect(find.text('건강'), findsWidgets);
      expect(find.text('Work'), findsNothing);

      await tester.ensureVisible(find.text('저장하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('스트레스 기록해요'), findsOneWidget);

      await tester.tap(find.text('인사이트'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('인사이트'), findsWidgets);

      await tester.tap(find.text('사이클 × 스트레스'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('요인 분포'), findsOneWidget);
      await _systemBack(tester);

      await tester.tap(find.text('나의 리포트'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('전체 기록'), findsOneWidget);
      await _systemBack(tester);

      await tester.tap(find.text('프로필'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('민지'), findsOneWidget);

      await tester.tap(find.byTooltip('닉네임 수정'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('닉네임을 바꿔요'), findsOneWidget);
      expect(find.text('예: 수빈'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '민지',
      );
      await tester.enterText(find.byType(TextField), '수빈님');
      await tester.tap(find.widgetWithText(TextButton, '저장하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('수빈'), findsOneWidget);

      await tester.tap(find.text('홈'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.textContaining('수빈님'), findsOneWidget);

      await tester.tap(find.text('프로필'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      final cycleMenu = find.byKey(const ValueKey('my-cycle-menu'));
      final cycleMenuIcon = find.descendant(
        of: cycleMenu,
        matching: find.byIcon(Icons.calendar_month_outlined),
      );
      await tester.ensureVisible(cycleMenuIcon.first);
      await tester.tap(cycleMenuIcon.first);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('최근 생리 시작일'), findsWidgets);
      expect(find.text('사이클 스트레스 패턴'), findsOneWidget);

      await tester.tap(find.text('동기화하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.textContaining('동기화'), findsWidgets);
      expect(find.text('생리 주기 기록'), findsOneWidget);
      await _systemBack(tester);

      await tester.ensureVisible(find.text('수면 데이터'));
      await tester.tap(find.text('수면 데이터'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('최근 수면'), findsOneWidget);
      expect(find.text('총 수면 시간'), findsOneWidget);
      expect(find.text('수면 패턴'), findsOneWidget);
      expect(find.text('잠든 시간'), findsOneWidget);
      expect(find.text('일어난 시간'), findsOneWidget);
      expect(find.text('수면 기록'), findsOneWidget);
      await _systemBack(tester);

      await tester.ensureVisible(find.text('Galaxy Watch'));
      await tester.tap(find.text('Galaxy Watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      _expectNoFlutterException(tester);
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('원시 생체신호 데이터 업로드 동의'), findsOneWidget);
      expect(find.text('소스'), findsOneWidget);
      expect(find.text('지속 시간'), findsOneWidget);
      expect(find.text('캡처 시작'), findsOneWidget);
      await _systemBack(tester);

      expect(find.text('개인정보 처리방침'), findsNothing);

      await tester.ensureVisible(find.text('계정 및 보안'));
      await tester.tap(find.text('계정 및 보안'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('로그인 정보'), findsOneWidget);

      await tester.tap(find.text('계정 삭제'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('계정을 삭제하기 전에'), findsOneWidget);
      await _systemBack(tester);
      await _systemBack(tester);
    },
  );

  testWidgets('password screen smoke test', (tester) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const ChangePasswordScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);
  });

  testWidgets('my cycle watch sync fills dates and auto-saves', (tester) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const MyCycleScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    final now = DateTime.now();
    final watchStart = DateTime(now.year, now.month, now.day - 10);
    final watchEnd = DateTime(now.year, now.month, now.day - 6);

    await tester.tap(find.text('동기화하기'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    expect(find.text('Galaxy Watch에서 주기 데이터를 불러와 저장했어요.'), findsOneWidget);
    expect(find.text(koFullDate(watchStart)), findsOneWidget);
    expect(find.text(koFullDate(watchEnd)), findsOneWidget);
    expect(data.cycleProvider.currentCycle!.lastPeriodStart, watchStart);
    expect(data.homeProvider.currentCycle!.lastPeriodStart, watchStart);
  });

  testWidgets('my cycle watch sync failure keeps form values', (tester) async {
    final data = _SmokeData(
      authStatus: AuthStatus.authenticated,
      failWatchSync: true,
    );
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const MyCycleScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    final initialStart = data.cycleProvider.currentCycle!.lastPeriodStart;
    final initialEnd = data.cycleProvider.currentCycle!.periodEndDate!;

    await tester.tap(find.text('동기화하기'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    expect(find.text('주기 데이터를 동기화하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text(koFullDate(initialStart)), findsOneWidget);
    expect(find.text(koFullDate(initialEnd)), findsOneWidget);
  });

  testWidgets('my cycle start date selection auto-saves and refreshes data', (
    tester,
  ) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await tester.pumpWidget(_SmokeApp(data: data, child: const MainScreen()));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    await tester.tap(find.text('프로필'));
    await tester.pumpAndSettle();

    final cycleMenu = find.byKey(const ValueKey('my-cycle-menu'));
    final cycleMenuIcon = find.descendant(
      of: cycleMenu,
      matching: find.byIcon(Icons.calendar_month_outlined),
    );
    await tester.ensureVisible(cycleMenuIcon.first);
    await tester.tap(cycleMenuIcon.first);
    await tester.pumpAndSettle();
    expect(find.text('Galaxy Watch와 동기화'), findsOneWidget);

    final initialStart = data.cycleProvider.currentCycle!.lastPeriodStart;
    final updatedStart = initialStart.add(const Duration(days: 1));

    await tester.tap(find.text(koFullDate(initialStart)).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'cycle-calendar-day-${updatedStart.year}-${updatedStart.month}-${updatedStart.day}',
        ),
      ),
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text(koFullDate(updatedStart)), findsOneWidget);

    _expectNoFlutterException(tester);

    expect(find.text('주기 기록이 저장되었어요.'), findsOneWidget);
    expect(find.text('Galaxy Watch와 동기화'), findsOneWidget);
    expect(find.text('저장하기'), findsNothing);
    expect(data.cycleProvider.currentCycle!.lastPeriodStart, updatedStart);
    expect(data.homeProvider.currentCycle!.lastPeriodStart, updatedStart);

    await _systemBack(tester);
    expect(find.text('스트레스 요인'), findsWidgets);
    expect(
      find.textContaining(
        '최근 생리 시작일 ${updatedStart.month}월 ${updatedStart.day}일',
      ),
      findsOneWidget,
    );
  });

  testWidgets('my cycle end date selection auto-saves and refreshes data', (
    tester,
  ) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const MyCycleScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    final initialEnd = data.cycleProvider.currentCycle!.periodEndDate!;
    final updatedEnd = initialEnd.add(const Duration(days: 1));

    await tester.tap(find.text(koFullDate(initialEnd)).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'cycle-calendar-day-${updatedEnd.year}-${updatedEnd.month}-${updatedEnd.day}',
        ),
      ),
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    expect(find.text('주기 기록이 저장되었어요.'), findsOneWidget);
    expect(find.text(koFullDate(updatedEnd)), findsOneWidget);
    expect(data.cycleProvider.currentCycle!.periodEndDate, updatedEnd);
    expect(data.homeProvider.currentCycle!.periodEndDate, updatedEnd);
    expect(find.text('저장하기'), findsNothing);
  });

  testWidgets('my cycle auto-save failure stays on screen with error', (
    tester,
  ) async {
    final data = _SmokeData(
      authStatus: AuthStatus.authenticated,
      failCycleSave: true,
    );
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const MyCycleScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    final initialStart = data.cycleProvider.currentCycle!.lastPeriodStart;
    final updatedStart = initialStart.add(const Duration(days: 1));

    await tester.tap(find.text(koFullDate(initialStart)).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          'cycle-calendar-day-${updatedStart.year}-${updatedStart.month}-${updatedStart.day}',
        ),
      ),
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    expect(find.text('Galaxy Watch와 동기화'), findsOneWidget);
    expect(find.text('생리 주기 정보를 저장하지 못했어요.'), findsOneWidget);
    expect(find.text('저장하기'), findsNothing);
    expect(data.cycleProvider.currentCycle!.lastPeriodStart, initialStart);
  });

  testWidgets('trigger add sheet shows duplicate error inline', (tester) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const MyTriggersScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    await tester.tap(find.text('+ 새 요인 추가하기'));
    await tester.pumpAndSettle();
    expect(find.text('새 요인 추가하기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' 업무 ');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);
    expect(find.text('이미 있는 요인이에요.'), findsOneWidget);
    expect(find.text('새 요인 추가하기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '운동');
    await tester.pumpAndSettle();
    expect(find.text('이미 있는 요인이에요.'), findsNothing);

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);
    expect(find.text('새 요인 추가하기'), findsNothing);
    expect(find.text('운동'), findsOneWidget);
    expect(find.text('업무'), findsOneWidget);
    expect(find.text('대인관계'), findsOneWidget);
    expect(find.text('가족'), findsOneWidget);
    expect(find.text('학업'), findsOneWidget);
    expect(find.text('건강'), findsOneWidget);
  });

  testWidgets('stress log reflects edited and deleted default triggers', (
    tester,
  ) async {
    final data = _SmokeData(authStatus: AuthStatus.authenticated);
    await data.load();

    await data.triggersProvider.updateTrigger(
      0,
      name: '회사',
      color: const Color(0xFFB87888),
    );
    await data.triggersProvider.removeTrigger(1);
    await data.triggersProvider.addTrigger(
      name: '운동',
      color: const Color(0xFF94D0BC),
    );

    await tester.pumpWidget(
      _SmokeApp(data: data, child: const StressLogScreen()),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    expect(find.text('회사'), findsOneWidget);
    expect(find.text('운동'), findsOneWidget);
    expect(find.text('업무'), findsNothing);
    expect(find.text('대인관계'), findsNothing);
    expect(find.text('가족'), findsOneWidget);
    expect(find.text('학업'), findsOneWidget);
    expect(find.text('건강'), findsOneWidget);
  });

  testWidgets(
    'stress log shows unknown trigger fallback and edits saved logs',
    (tester) async {
      final data = _SmokeData(authStatus: AuthStatus.authenticated);
      await data.load();

      final created = await data.eventsProvider.createEvent(
        stressScore: 80,
        trigger: '',
        note: null,
      );
      expect(created, isNotNull);

      await tester.pumpWidget(
        _SmokeApp(data: data, child: const EventsLogScreen()),
      );
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      expect(find.text('요인 불명'), findsOneWidget);
      expect(find.text('기록 전'), findsNothing);

      await tester.tap(find.text('요인 불명'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      expect(find.text('스트레스 기록 수정'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      final sliderCenter = tester.getCenter(find.byType(Slider));
      await tester.tapAt(Offset(sliderCenter.dx + 60, sliderCenter.dy));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가족'));
      await tester.enterText(find.byType(TextField), '수정된 메모');
      await tester.ensureVisible(find.text('저장하기'));
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);

      final edited = data.eventsProvider.todayEvents.firstWhere(
        (event) => event.id == created!.id,
      );
      expect(edited.trigger, 'Family');
      expect(edited.note, '수정된 메모');
      expect(edited.stressScore, lessThan(80));
      expect(edited.stressScore, greaterThan(62));
      expect(find.text('가족'), findsWidgets);
      expect(find.text('수정된 메모'), findsOneWidget);

      await tester.pumpWidget(
        _SmokeApp(data: data, child: const InsightScreen()),
      );
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
      expect(find.text('가족 관련 기록이 1건으로 가장 많아요.'), findsOneWidget);
      expect(find.textContaining('가족과'), findsNothing);
      expect(find.textContaining('가족가'), findsNothing);
    },
  );

  test(
    'visible Korean copy scan has no known English fallback strings',
    () async {
      final sourceFiles = <String>[
        'README.md',
        'lib/core/network/api_client.dart',
        'lib/features/auth/auth_provider.dart',
        'lib/features/auth/data/auth_api.dart',
        'lib/features/cycles/cycle_provider.dart',
        'lib/features/events/data/events_api.dart',
        'lib/features/events/events_provider.dart',
        'lib/features/realtime/realtime_service.dart',
        'lib/features/sleep/sleep_provider.dart',
      ];

      final oldGoogleSetupCopy = 'Google 로그인 설정을 ${'준비'}';
      final oldServerClientIdName = '${'LU'}MA_GOOGLE_SERVER_CLIENT_ID';
      final oldAppName = '${'lu'}ma_app';
      final oldTokenDebugMethod = '_debugGoogle${'Id'}Token';
      final oldAccountEmailLog = 'GOOGLE selected account ${'email'}';

      for (final path in sourceFiles) {
        final text = await File(path).readAsString();
        expect(text, isNot(contains('New update')));
        expect(
          text,
          isNot(contains('will be available in the next integration step')),
        );
        expect(text, isNot(contains('Unsupported HTTP method')));
        expect(text, isNot(contains('Missing auth tokens')));
        expect(text, isNot(contains('이벤트 응답')));
        expect(text, isNot(contains(oldGoogleSetupCopy)));
        expect(text, isNot(contains(oldServerClientIdName)));
        expect(text, isNot(contains(oldAppName)));
        expect(text, isNot(contains(oldTokenDebugMethod)));
        expect(text, isNot(contains(oldAccountEmailLog)));
      }
    },
  );
}

class _SmokeApp extends StatelessWidget {
  final _SmokeData data;
  final Widget child;

  const _SmokeApp({required this.data, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: data.auth),
        ChangeNotifierProvider<EventsProvider>.value(
          value: data.eventsProvider,
        ),
        ChangeNotifierProvider<CycleProvider>.value(value: data.cycleProvider),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: data.settingsProvider,
        ),
        ChangeNotifierProvider<ConsentProvider>.value(
          value: data.consentProvider,
        ),
        ChangeNotifierProvider<HomeProvider>.value(value: data.homeProvider),
        ChangeNotifierProvider<InsightProvider>.value(
          value: data.insightProvider,
        ),
        ChangeNotifierProvider<TriggersProvider>.value(
          value: data.triggersProvider,
        ),
        ChangeNotifierProvider<SleepProvider>.value(value: data.sleepProvider),
        Provider<PrivacyApi>.value(value: data.privacyApi),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        color: AppColors.background,
        theme: AppTheme.light,
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: AppColors.background,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: ColoredBox(color: AppColors.background, child: child),
        ),
      ),
    );
  }
}

class _SmokeData {
  late final _FakeAuthProvider auth;
  late final _FakeEventsApi eventsApi;
  late final _FakeCyclesApi cyclesApi;
  late final _FakeSettingsApi settingsApi;
  late final _FakeConsentApi consentApi;
  late final _FakeSleepApi sleepApi;
  late final _FakeCategoriesApi categoriesApi;
  late final _FakePrivacyApi privacyApi;

  late final EventsProvider eventsProvider;
  late final CycleProvider cycleProvider;
  late final SettingsProvider settingsProvider;
  late final ConsentProvider consentProvider;
  late final HomeProvider homeProvider;
  late final InsightProvider insightProvider;
  late final TriggersProvider triggersProvider;
  late final SleepProvider sleepProvider;

  final _events = <StressEvent>[];
  late Cycle _cycle;
  late List<Cycle> _cycles;
  late List<SleepLog> _sleepLogs;

  _SmokeData({
    required AuthStatus authStatus,
    bool failCycleSave = false,
    bool failWatchSync = false,
  }) {
    final now = DateTime.now();
    _cycle = Cycle(
      id: 'cycle-1',
      lastPeriodStart: DateTime(now.year, now.month, now.day - 12),
      periodEndDate: DateTime(now.year, now.month, now.day - 8),
      cycleLength: 28,
      periodLength: 5,
      notes: null,
    );
    _cycles = [_cycle];
    _events.add(
      StressEvent(
        id: 'event-1',
        detectedAt: now.subtract(const Duration(hours: 2)),
        stressScore: 62,
        trigger: 'Work',
        cyclePhase: 'luteal',
        cycleDay: 22,
        logged: true,
        logChips: const ['Work'],
        note: '회의 준비가 예상보다 길어졌어요.',
      ),
    );
    _sleepLogs = [
      SleepLog(
        id: 'sleep-1',
        fellAsleepAt: now.subtract(const Duration(hours: 8, minutes: 10)),
        wokeUpAt: now.subtract(const Duration(minutes: 30)),
        endedOn: now,
      ),
    ];

    auth = _FakeAuthProvider(status: authStatus);
    eventsApi = _FakeEventsApi(_events);
    cyclesApi = _FakeCyclesApi(
      currentCycle: () => _cycle,
      cycles: () => _cycles,
      failSave: failCycleSave,
      onSave: (cycle) {
        _cycle = cycle;
        _cycles = [cycle, ..._cycles.where((item) => item.id != cycle.id)];
      },
    );
    settingsApi = _FakeSettingsApi();
    consentApi = _FakeConsentApi();
    sleepApi = _FakeSleepApi(_sleepLogs);
    categoriesApi = _FakeCategoriesApi();
    privacyApi = _FakePrivacyApi();

    eventsProvider = EventsProvider(eventsApi: eventsApi);
    cycleProvider = CycleProvider(
      cyclesApi: cyclesApi,
      watchCycleService: _FakeWatchCycleService(hasData: !failWatchSync),
    );
    settingsProvider = SettingsProvider(settingsApi: settingsApi);
    consentProvider = ConsentProvider(consentApi: consentApi);
    final fakeAiInsightsApi = _FakeAiInsightsApi();
    homeProvider = HomeProvider(
      eventsApi: eventsApi,
      cyclesApi: cyclesApi,
      consentApi: consentApi,
      aiInsightsApi: fakeAiInsightsApi,
    );
    insightProvider = InsightProvider(
      eventsApi: eventsApi,
      cyclesApi: cyclesApi,
      aiInsightsApi: fakeAiInsightsApi,
    );
    triggersProvider = TriggersProvider(categoriesApi: categoriesApi);
    sleepProvider = SleepProvider(sleepApi: sleepApi);
  }

  Future<void> load() async {
    await Future.wait([
      eventsProvider.loadToday(),
      cycleProvider.loadCurrentCycle(),
      consentProvider.loadConsent(),
      homeProvider.refresh(),
      insightProvider.refresh(),
      triggersProvider.load(),
      sleepProvider.load(),
    ]);
  }
}

class _FakeAuthProvider extends AuthProvider {
  AuthStatus _status;
  String? _message;
  AppUser? _fakeUser;

  _FakeAuthProvider({required AuthStatus status})
    : _status = status,
      _fakeUser = status == AuthStatus.authenticated ? _user : null,
      super(
        authApi: AuthApi(apiClient: _dummyApiClient()),
        tokenStorage: SecureTokenStorage(),
        apiClient: _dummyApiClient(),
      );

  static const _user = AppUser(
    id: 'user-1',
    email: null,
    name: '민지',
    accountType: 'anonymous',
    consent: <String, dynamic>{},
    settings: <String, dynamic>{},
  );

  @override
  AuthStatus get status => _status;

  @override
  AppUser? get user => _fakeUser;

  @override
  String? get errorMessage => _message;

  @override
  Future<void> signInAnonymously() async {
    _status = AuthStatus.authenticated;
    _fakeUser = _user;
    _message = null;
    notifyListeners();
  }

  @override
  Future<bool> continueWithGoogle() async {
    _message = 'Google 로그인 정보를 확인하지 못했어요.';
    notifyListeners();
    return false;
  }

  @override
  Future<bool> signInWithEmail(String email, String password) async {
    _message = '현재 이메일 로그인은 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.';
    notifyListeners();
    return false;
  }

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    _message = '현재 이메일 계정 만들기는 지원되지 않아요. 익명 또는 Google 로그인을 이용해 주세요.';
    notifyListeners();
    return false;
  }

  @override
  Future<bool> updateNickname(String nickname) async {
    final normalized = rawNickname(nickname);
    if (normalized.isEmpty) {
      _message = '닉네임을 입력해 주세요.';
      notifyListeners();
      return false;
    }

    _fakeUser = (_fakeUser ?? _user).copyWith(name: normalized);
    _message = null;
    notifyListeners();
    return true;
  }

  @override
  Future<void> logout() async {
    _status = AuthStatus.unauthenticated;
    _fakeUser = null;
    notifyListeners();
  }
}

class _FakeEventsApi extends EventsApi {
  final List<StressEvent> events;

  _FakeEventsApi(this.events) : super(apiClient: _dummyApiClient());

  @override
  Future<List<StressEvent>> listEvents({
    DateTime? start,
    DateTime? end,
    bool? logged,
    String? cyclePhase,
    String? chip,
    String? cursor,
    int limit = 50,
  }) async {
    return events
        .where((event) {
          if (start != null && event.detectedAt.isBefore(start)) return false;
          if (end != null && event.detectedAt.isAfter(end)) return false;
          if (logged != null && event.logged != logged) return false;
          return true;
        })
        .take(limit)
        .toList();
  }

  @override
  Future<StressEvent> createEvent(StressEvent event) async {
    final normalizedTrigger = event.trigger.trim();
    final normalizedNote = event.note ?? event.logText;
    final saved = StressEvent(
      id: 'event-${events.length + 1}',
      detectedAt: event.detectedAt,
      stressDetected: event.stressDetected,
      cyclePhase: event.cyclePhase,
      cycleDay: event.cycleDay,
      logged: true,
      logChips: normalizedTrigger.isEmpty
          ? const <String>[]
          : <String>[normalizedTrigger],
      logText: normalizedNote,
      notified: event.notified,
      stressScore: event.stressScore,
      trigger: normalizedTrigger,
      note: normalizedNote,
    );
    events.insert(0, saved);
    return saved;
  }

  @override
  Future<StressEvent> updateEvent(
    String id,
    Map<String, dynamic> changes,
  ) async {
    final index = events.indexWhere((event) => event.id == id);
    final existing = index >= 0
        ? events[index]
        : StressEvent(
            id: id,
            detectedAt: DateTime.now(),
            trigger: '',
            note: null,
          );
    final logChips = changes['log_chips'] as List?;
    final normalizedTrigger = logChips == null || logChips.isEmpty
        ? ''
        : '${logChips.first}'.trim();
    final updated = StressEvent(
      id: existing.id,
      detectedAt: existing.detectedAt,
      stressDetected: existing.stressDetected,
      cyclePhase: existing.cyclePhase,
      cycleDay: existing.cycleDay,
      logged: changes['logged'] == true || existing.logged,
      logChips: normalizedTrigger.isEmpty
          ? const <String>[]
          : <String>[normalizedTrigger],
      logText: changes.containsKey('log_text')
          ? changes['log_text'] as String?
          : existing.logText,
      notified: existing.notified,
      stressScore: (changes['user_stress_level'] as num?)?.round(),
      trigger: normalizedTrigger,
      note: changes.containsKey('log_text')
          ? changes['log_text'] as String?
          : existing.note,
    );
    if (index >= 0) {
      events[index] = updated;
    } else {
      events.insert(0, updated);
    }
    return updated;
  }
}

class _FakeCyclesApi extends CyclesApi {
  final Cycle Function() _currentCycleGetter;
  final List<Cycle> Function() cycles;
  final ValueChanged<Cycle> onSave;
  final bool failSave;

  _FakeCyclesApi({
    required Cycle Function() currentCycle,
    required this.cycles,
    required this.onSave,
    this.failSave = false,
  }) : _currentCycleGetter = currentCycle,
       super(apiClient: _dummyApiClient());

  @override
  Future<Cycle?> currentCycle() async => _currentCycleGetter.call();

  @override
  Future<List<Cycle>> listCycles() async => cycles.call();

  @override
  Future<Cycle> createPeriod(Cycle cycle) async {
    if (failSave) {
      throw const ApiException(message: '생리 주기 정보를 저장하지 못했어요.');
    }

    final saved = Cycle(
      id: cycle.id.isEmpty ? 'cycle-saved' : cycle.id,
      lastPeriodStart: cycle.lastPeriodStart,
      periodEndDate: cycle.periodEndDate,
      cycleLength: cycle.cycleLength,
      periodLength: cycle.periodLength,
      notes: cycle.notes,
    );
    onSave(saved);
    return saved;
  }

  @override
  Future<Cycle> updateCycle(String id, Map<String, dynamic> changes) async {
    if (failSave) {
      throw const ApiException(message: '생리 주기 정보를 저장하지 못했어요.');
    }

    final current = _currentCycleGetter.call();
    final periodStart = DateTime.tryParse(
      '${changes['period_start_date'] ?? ''}',
    );
    final periodEndRaw = changes['period_end_date'];
    final periodEnd = periodEndRaw == null
        ? null
        : DateTime.tryParse('$periodEndRaw');
    final updated = Cycle(
      id: id,
      lastPeriodStart: periodStart ?? current.lastPeriodStart,
      periodEndDate: changes.containsKey('period_end_date')
          ? periodEnd
          : current.periodEndDate,
      cycleLength:
          (changes['cycle_length_days'] as num?)?.round() ??
          current.cycleLength,
      periodLength: periodEnd == null
          ? current.periodLength
          : periodEnd
                    .difference(periodStart ?? current.lastPeriodStart)
                    .inDays +
                1,
      notes: current.notes,
    );
    onSave(updated);
    return updated;
  }
}

class _FakeWatchCycleService extends WatchCycleService {
  final bool hasData;

  const _FakeWatchCycleService({required this.hasData});

  @override
  Future<WatchCycleData?> getLatestCycleData() async {
    if (!hasData) return null;

    final now = DateTime.now();
    return WatchCycleData(
      periodStart: DateTime(now.year, now.month, now.day - 10),
      periodEnd: DateTime(now.year, now.month, now.day - 6),
      estimatedCycleLength: 28,
    );
  }
}

class _FakeSettingsApi extends SettingsApi {
  UserSettings settings = const UserSettings(
    notificationMaxPerDay: 5,
    stressThreshold: 0.75,
    quietHoursStart: '22:00:00',
    quietHoursEnd: '08:00:00',
    silenceDuringMeeting: true,
    silenceDuringExercise: true,
    consentAuditLogging: true,
    sleepNudgeEnabled: true,
    language: 'ko',
  );

  _FakeSettingsApi() : super(apiClient: _dummyApiClient());

  @override
  Future<UserSettings> getSettings() async => settings;

  @override
  Future<UserSettings> updateSettings(Map<String, dynamic> changes) async {
    settings = UserSettings(
      notificationMaxPerDay: settings.notificationMaxPerDay,
      stressThreshold: settings.stressThreshold,
      quietHoursStart: settings.quietHoursStart,
      quietHoursEnd: settings.quietHoursEnd,
      silenceDuringMeeting: settings.silenceDuringMeeting,
      silenceDuringExercise: settings.silenceDuringExercise,
      consentAuditLogging: settings.consentAuditLogging,
      sleepNudgeEnabled:
          changes['notification_consent'] as bool? ??
          settings.sleepNudgeEnabled,
      language: settings.language,
    );
    return settings;
  }
}

class _FakeConsentApi extends ConsentApi {
  ConsentState consent = const ConsentState(
    rawBiosignalConsent: true,
    auditLoggingConsent: true,
    privacyPolicyVersion: '2026.05',
  );

  _FakeConsentApi() : super(apiClient: _dummyApiClient());

  @override
  Future<ConsentState> getConsent() async => consent;

  @override
  Future<ConsentState> updateConsent(Map<String, dynamic> changes) async {
    consent = ConsentState(
      rawBiosignalConsent:
          changes['consent_raw_biosignals'] as bool? ??
          consent.rawBiosignalConsent,
      auditLoggingConsent:
          changes['consent_audit_logging'] as bool? ??
          consent.auditLoggingConsent,
      privacyPolicyVersion: consent.privacyPolicyVersion,
    );
    return consent;
  }
}

class _FakeSleepApi extends SleepApi {
  final List<SleepLog> sleepLogs;

  _FakeSleepApi(this.sleepLogs) : super(apiClient: _dummyApiClient());

  @override
  Future<SleepLog?> getLatestSleepLog() async =>
      sleepLogs.isEmpty ? null : sleepLogs.first;

  @override
  Future<List<SleepLog>> listSleepLogs() async => sleepLogs;
}

class _FakeCategoriesApi extends CategoriesApi {
  final categories = <TriggerCategoryDto>[
    const TriggerCategoryDto(
      id: 'work',
      name: 'Work',
      color: Color(0xFFB87888),
      eventCount: 2,
    ),
    const TriggerCategoryDto(
      id: 'health',
      name: 'Health',
      color: Color(0xFFE7C9A9),
      eventCount: 1,
    ),
  ];

  _FakeCategoriesApi() : super(apiClient: _dummyApiClient());

  @override
  Future<List<TriggerCategoryDto>> listCategories() async => categories;

  @override
  Future<TriggerCategoryDto> createCategory({
    required String name,
    required Color color,
    int? sortOrder,
  }) async {
    final category = TriggerCategoryDto(
      id: 'category-${categories.length + 1}',
      name: name,
      color: color,
      eventCount: 0,
    );
    categories.add(category);
    return category;
  }

  @override
  Future<TriggerCategoryDto> updateCategory(
    String id, {
    String? name,
    Color? color,
    int? sortOrder,
  }) async {
    final index = categories.indexWhere((category) => category.id == id);
    if (index == -1) {
      throw const ApiException(message: '스트레스 요인을 수정하지 못했어요.');
    }

    final current = categories[index];
    final updated = TriggerCategoryDto(
      id: current.id,
      name: name ?? current.name,
      color: color ?? current.color,
      eventCount: current.eventCount,
    );
    categories[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteCategory(String id) async {
    categories.removeWhere((category) => category.id == id);
  }
}

class _FakeAiInsightsApi extends AiInsightsApi {
  _FakeAiInsightsApi() : super(apiClient: _dummyApiClient());

  @override
  Future<WeeklyReport?> getLatestWeeklyReport() async => null;

  @override
  Future<MorningTip?> getMorningTip() async => null;
}

class _FakePrivacyApi extends PrivacyApi {
  _FakePrivacyApi() : super(apiClient: _dummyApiClient());

  @override
  Future<void> deleteAccount() async {}
}

ApiClient _dummyApiClient() => ApiClient(tokenStorage: SecureTokenStorage());

void _expectNoFlutterException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
