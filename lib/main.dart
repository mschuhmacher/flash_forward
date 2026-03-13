import 'dart:async';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flash_forward/presentation/screens/auth_flow/loading_screen.dart';
import 'package:flash_forward/presentation/screens/auth_flow/reset_password_screen.dart';
import 'package:flash_forward/services/supabase_config.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_theme.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Lock app to portrait mode
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final packageInfo = await PackageInfo.fromPlatform();

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = kDebugMode ? 'debug' : 'production';
      options.release =
          'flash_forward@${packageInfo.version}+${packageInfo.buildNumber}';
      options.sendDefaultPii = false;
      options.enableLogs = true;
      options.tracesSampleRate = 0.2;
      options.profilesSampleRate = 0.1;
      options.replay.sessionSampleRate = 0.1;
      options.replay.onErrorSampleRate = 1.0;
    },
    appRunner: () => runApp(SentryWidget(child:
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => SessionLogProvider()),
        ChangeNotifierProvider(create: (context) => PresetProvider()),
        ChangeNotifierProvider(create: (context) => SessionStateProvider()),
      ],
      child: const MyApp(),
    ),
  )),
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
            (route) => false,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Flash Forward',
      debugShowCheckedModeBanner: false,
      theme: lightAppTheme,
      darkTheme: darkAppTheme,
      themeMode: ThemeMode.light, // switch to system when better dark mode colors set
      home: const LoadingScreen(),
    );
  }
}
