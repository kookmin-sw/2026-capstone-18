import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
import 'features/events/data/events_api.dart';
import 'features/events/events_provider.dart';
import 'features/home/home_provider.dart';
import 'features/insight/insight_provider.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/notifications_api.dart';
import 'features/privacy/data/privacy_api.dart';
import 'features/settings/data/settings_api.dart';
import 'features/settings/settings_provider.dart';
import 'features/sleep/data/sleep_api.dart';
import 'features/sleep/sleep_provider.dart';
import 'features/triggers/data/categories_api.dart';
import 'features/triggers/triggers_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/insight/insight_screen.dart';
import 'screens/my/my_screen.dart';

const SystemUiOverlayStyle _littleSignalsSystemUiOverlayStyle =
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureSystemBars();
  await _initializeFirebase();
  runApp(const LittleSignalsApp());
}

Future<void> _configureSystemBars() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_littleSignalsSystemUiOverlayStyle);
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

class LittleSignalsApp extends StatefulWidget {
  const LittleSignalsApp({super.key});

  @override
  State<LittleSignalsApp> createState() => _LittleSignalsAppState();
}

class _LittleSignalsAppState extends State<LittleSignalsApp> {
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
          create: (_) => CycleProvider(cyclesApi: _cyclesApi),
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
          ),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              InsightProvider(eventsApi: _eventsApi, cyclesApi: _cyclesApi),
        ),
        ChangeNotifierProvider(
          create: (_) => TriggersProvider(categoriesApi: _categoriesApi),
        ),
        ChangeNotifierProvider(
          create: (_) => SleepProvider(sleepApi: _sleepApi),
        ),
        Provider<PrivacyApi>.value(value: _privacyApi),
        Provider<NotificationService>.value(value: _notificationService),
      ],
      child: MaterialApp(
        title: 'LittleSignals',
        debugShowCheckedModeBanner: false,
        color: AppColors.background,
        theme: AppTheme.light,
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _littleSignalsSystemUiOverlayStyle,
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
  String? _fcmRegisteredUserId;

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthProvider, AuthStatus>(
      (auth) => auth.status,
    );

    if (status != _lastStatus) {
      _lastStatus = status;
      if (status == AuthStatus.authenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _clearAuthenticatedSessionData();
          unawaited(_loadAuthenticatedSession());
        });
      } else if (status == AuthStatus.unauthenticated) {
        _fcmRegisteredUserId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
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

  Future<void> _loadAuthenticatedSession() async {
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

    final user = context.read<AuthProvider>().user;
    final userId = user?.id ?? 'authenticated';
    if (_fcmRegisteredUserId != userId) {
      _fcmRegisteredUserId = userId;
      futures.add(
        context.read<NotificationService>().requestPermissionAndRegister(),
      );
    }

    await Future.wait(futures);
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
