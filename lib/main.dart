import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flash_forward/presentation/screens/loading_screen.dart';
import 'package:flash_forward/services/supabase_config.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_theme.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (this also loads dotenv)
  await SupabaseConfig.initialize();

  // Lock app to portrait mode
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await SentryFlutter.init(
    (options) {
      options.dsn = kDebugMode ? '' : dotenv.env['SENTRY_DSN'];

      // Adds request headers and IP for users, for more info visit:
      // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
      options.sendDefaultPii = false;
      options.enableLogs = true;
      options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
      options.profilesSampleRate = kDebugMode ? 1.0 : 0.5;
      // Configure Session Replay
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash Forward',
      debugShowCheckedModeBanner: false,
      theme: lightAppTheme,
      darkTheme: darkAppTheme,
      themeMode: ThemeMode.system,
      home: const LoadingScreen(),
    );
  }
}
