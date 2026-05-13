import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/storage/secure_token_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_gradient_background.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/data/auth_api.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/consent/consent_provider.dart';
import 'features/consent/data/consent_api.dart';
import 'features/cycles/cycle_provider.dart';
import 'features/cycles/data/cycles_api.dart';
import 'features/cycles/services/cycle_ongoing_storage.dart';
import 'features/events/data/events_api.dart';
import 'features/events/events_provider.dart';
import 'features/home/home_provider.dart';
import 'features/insight/data/ai_insights_api.dart';
import 'features/insight/insight_provider.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/notifications_api.dart';
import 'features/privacy/data/privacy_api.dart';
import 'features/realtime/realtime_service.dart';
import 'features/settings/data/settings_api.dart';
import 'features/settings/settings_provider.dart';
import 'features/sleep/data/sleep_api.dart';
import 'features/sleep/sleep_provider.dart';
import 'features/triggers/data/categories_api.dart';
import 'features/triggers/triggers_provider.dart';
import 'screens/home/events_log_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/home/stress_log_screen.dart';
import 'screens/insight/insight_screen.dart';
import 'screens/my/my_screen.dart';

const SystemUiOverlayStyle _lumaSystemUiOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: AppColors.background,
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

final GlobalKey<NavigatorState> lumaNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    return;
  }

  await NotificationService.showRemoteMessageNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureSystemBars();
  await _initializeFirebase();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const LumaApp());
}

Future<void> _configureSystemBars() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_lumaSystemUiOverlayStyle);
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized');
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrint('$stackTrace');
  }
}

class LumaApp extends StatefulWidget {
  const LumaApp({super.key});

  @override
  State<LumaApp> createState() => _LumaAppState();
}

class _LumaAppState extends State<LumaApp> {
  late final SecureTokenStorage _tokenStorage;
  late final ApiClient _apiClient;
  late final AuthApi _authApi;
  late final EventsApi _eventsApi;
  late final CyclesApi _cyclesApi;
  late final SettingsApi _settingsApi;
  late final ConsentApi _consentApi;
  late final SleepApi _sleepApi;
  late final CategoriesApi _categoriesApi;
  late final PrivacyApi _privacyApi;
  late final NotificationsApi _notificationsApi;
  late final NotificationService _notificationService;
  late final AiInsightsApi _aiInsightsApi;
  late final RealtimeService _realtimeService;
  late final CycleOngoingStore _cycleOngoingStore;

  @override
  void initState() {
    super.initState();
    _tokenStorage = SecureTokenStorage();
    _apiClient = ApiClient(tokenStorage: _tokenStorage);
    _authApi = AuthApi(apiClient: _apiClient);
    _eventsApi = EventsApi(apiClient: _apiClient);
    _cyclesApi = CyclesApi(apiClient: _apiClient);
    _settingsApi = SettingsApi(apiClient: _apiClient);
    _consentApi = ConsentApi(apiClient: _apiClient);
    _sleepApi = SleepApi(apiClient: _apiClient);
    _categoriesApi = CategoriesApi(apiClient: _apiClient);
    _privacyApi = PrivacyApi(apiClient: _apiClient);
    _notificationsApi = NotificationsApi(apiClient: _apiClient);
    _notificationService = NotificationService(
      notificationsApi: _notificationsApi,
    );
    _aiInsightsApi = AiInsightsApi(apiClient: _apiClient);
    _realtimeService = RealtimeService(tokenStorage: _tokenStorage);
    _cycleOngoingStore = CycleOngoingStorage();
  }

  @override
  void dispose() {
    unawaited(_notificationService.dispose());
    unawaited(_realtimeService.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authApi: _authApi,
            tokenStorage: _tokenStorage,
            apiClient: _apiClient,
          )..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => EventsProvider(eventsApi: _eventsApi),
        ),
        ChangeNotifierProvider(
          create: (_) => CycleProvider(
            cyclesApi: _cyclesApi,
            cycleOngoingStore: _cycleOngoingStore,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(settingsApi: _settingsApi),
        ),
        ChangeNotifierProvider(
          create: (_) => ConsentProvider(consentApi: _consentApi),
        ),
        ChangeNotifierProvider(
          create: (_) => HomeProvider(
            eventsApi: _eventsApi,
            cyclesApi: _cyclesApi,
            consentApi: _consentApi,
            aiInsightsApi: _aiInsightsApi,
            cycleOngoingStore: _cycleOngoingStore,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => InsightProvider(
            eventsApi: _eventsApi,
            cyclesApi: _cyclesApi,
            aiInsightsApi: _aiInsightsApi,
            cycleOngoingStore: _cycleOngoingStore,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => TriggersProvider(categoriesApi: _categoriesApi),
        ),
        ChangeNotifierProvider(
          create: (_) => SleepProvider(sleepApi: _sleepApi),
        ),
        Provider<PrivacyApi>.value(value: _privacyApi),
        Provider<NotificationService>.value(value: _notificationService),
        Provider<RealtimeService>.value(value: _realtimeService),
      ],
      child: MaterialApp(
        navigatorKey: lumaNavigatorKey,
        title: 'Luma',
        debugShowCheckedModeBanner: false,
        color: AppColors.background,
        theme: AppTheme.light,
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _lumaSystemUiOverlayStyle,
            child: ColoredBox(
              color: AppColors.background,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  AuthStatus? _lastStatus;
  String? _lastAuthenticatedUserId;
  String? _fcmRegisteredUserId;
  String? _realtimeConnectedUserId;
  String? _notificationHandlingUserId;
  String? _pendingNotificationEventId;

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthProvider, AuthStatus>(
      (auth) => auth.status,
    );
    final userId = context.select<AuthProvider, String?>(
      (auth) => auth.user?.id,
    );

    final authenticatedUserChanged =
        status == AuthStatus.authenticated &&
        userId != _lastAuthenticatedUserId;
    if (status != _lastStatus || authenticatedUserChanged) {
      _lastStatus = status;
      if (status == AuthStatus.authenticated) {
        _lastAuthenticatedUserId = userId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _clearAuthenticatedSessionData();
          unawaited(_loadAuthenticatedSession(userId));
        });
      } else if (status == AuthStatus.unauthenticated) {
        _lastAuthenticatedUserId = null;
        _fcmRegisteredUserId = null;
        _realtimeConnectedUserId = null;
        _notificationHandlingUserId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_disconnectSessionServices());
          _clearAuthenticatedSessionData();
        });
      }
    }

    return switch (status) {
      AuthStatus.checking => const _BootScreen(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.authenticated => const MainScreen(),
    };
  }

  Future<void> _loadAuthenticatedSession(String? sessionUserId) async {
    debugPrint('AUTH authenticated: loading initial staging data');

    final futures = <Future<void>>[
      context.read<HomeProvider>().refresh(),
      context.read<EventsProvider>().loadToday(),
      context.read<CycleProvider>().loadCurrentCycle(),
      context.read<ConsentProvider>().loadConsent(),
      context.read<InsightProvider>().refresh(),
      context.read<TriggersProvider>().load(),
      context.read<SleepProvider>().loadLatest(),
    ];

    final userId = sessionUserId ?? 'authenticated';
    if (_fcmRegisteredUserId != userId) {
      _fcmRegisteredUserId = userId;
      futures.add(
        context.read<NotificationService>().requestPermissionAndRegister(),
      );
    }

    await Future.wait(futures);

    if (!mounted) return;

    await _connectRealtimeSession(userId);
    await _initializeNotificationHandling(userId);
    await _openPendingNotificationEvent();
  }

  Future<void> _connectRealtimeSession(String userId) async {
    if (_realtimeConnectedUserId == userId) return;

    final realtimeService = context.read<RealtimeService>();
    await realtimeService.disconnect();
    await realtimeService.connect(
      onEventMessage: _handleRealtimeEventMessage,
      onNotification: _showRealtimeNotification,
    );

    _realtimeConnectedUserId = userId;
  }

  Future<void> _initializeNotificationHandling(String userId) async {
    if (_notificationHandlingUserId == userId) return;

    final notificationService = context.read<NotificationService>();
    await notificationService.initializeMessageHandling(
      onStressEventTap: _handleStressEventNotificationTap,
    );
    _notificationHandlingUserId = userId;
  }

  Future<void> _disconnectSessionServices() async {
    final realtimeService = context.read<RealtimeService>();
    final notificationService = context.read<NotificationService>();
    await realtimeService.disconnect();
    await notificationService.dispose();
  }

  Future<void> _handleRealtimeEventMessage(RealtimeEventMessage message) async {
    if (!mounted) return;

    final eventsProvider = context.read<EventsProvider>();
    final homeProvider = context.read<HomeProvider>();

    if (message.type == RealtimeEventType.deleted) {
      eventsProvider.removeRealtimeEvent(message.id);
      homeProvider.removeRealtimeEvent(message.id);
      return;
    }

    final event = await eventsProvider.fetchAndUpsertEvent(message.id);
    if (!mounted || event == null) return;

    homeProvider.applyRealtimeEvent(event);
  }

  void _showRealtimeNotification(String message) {
    final context = lumaNavigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleStressEventNotificationTap(String eventId) async {
    if (_lastStatus != AuthStatus.authenticated) {
      _pendingNotificationEventId = eventId;
      return;
    }

    await _openStressEventFromNotification(eventId);
  }

  Future<void> _openPendingNotificationEvent() async {
    final eventId = _pendingNotificationEventId;
    if (eventId == null) return;

    _pendingNotificationEventId = null;
    await _openStressEventFromNotification(eventId);
  }

  Future<void> _openStressEventFromNotification(String eventId) async {
    final navigator = lumaNavigatorKey.currentState;
    final navigatorContext = lumaNavigatorKey.currentContext;
    if (navigator == null || navigatorContext == null) {
      _pendingNotificationEventId = eventId;
      return;
    }

    final eventsProvider = navigatorContext.read<EventsProvider>();
    final homeProvider = navigatorContext.read<HomeProvider>();
    final event = await eventsProvider.fetchAndUpsertEvent(eventId);
    if (!mounted) return;

    if (event == null) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    homeProvider.applyRealtimeEvent(event);
    navigator.popUntil((route) => route.isFirst);

    if (!event.logged) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => StressLogScreen(sourceEvent: event)),
      );
    } else {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const EventsLogScreen()),
      );
    }
  }

  void _clearAuthenticatedSessionData() {
    context.read<HomeProvider>().clearSessionData();
    context.read<EventsProvider>().clearSessionData();
    context.read<CycleProvider>().clearSessionData();
    context.read<SettingsProvider>().clearSessionData();
    context.read<ConsentProvider>().clearSessionData();
    context.read<InsightProvider>().clearSessionData();
    context.read<TriggersProvider>().clearSessionData();
    context.read<SleepProvider>().clearSessionData();
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    InsightScreen(),
    MyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white.withValues(alpha: 0.76),
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: '인사이트',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '프로필',
          ),
        ],
      ),
    );
  }
}
