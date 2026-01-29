import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
import 'package:flash_forward/presentation/screens/login_screen.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Run initialization with minimum 2 second display time
    await Future.wait([
      _loadData(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    if (!mounted) return;

    // Navigate based on auth state
    if (authProvider.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Initialize auth first
    await authProvider.init();

    // If user is authenticated, load their data
    if (authProvider.isAuthenticated) {
      final userId = authProvider.userId;

      // Pass userId to both providers
      final sessionLogProvider = Provider.of<SessionLogProvider>(
        context,
        listen: false,
      );
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      await sessionLogProvider.init(userId: userId);
      await presetProvider.init(userId: userId);

      // Process any pending sync operations from previous offline sessions
      await sessionLogProvider.processPendingSync();
      await presetProvider.processPendingSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/bouldering_logo.png',
              width: 120,
              height: 120,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 24),
            Text('Flash Forward', style: context.h1),
            const SizedBox(height: 40),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
