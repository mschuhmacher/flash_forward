// loading_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
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
    // Kick off initialization after first frame to avoid provider notifications
    // during the widget tree build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    // Run initialization and minimum duration in parallel
    await Future.wait([
      _loadData(),
      Future.delayed(const Duration(seconds: 2)), // Minimum 1 second
    ]);

    // Navigate to home screen after both complete
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  Future<void> _loadData() async {
    // Initialize providers
    await Provider.of<SessionLogProvider>(context, listen: false).init();
    await Provider.of<PresetProvider>(context, listen: false).init();

    // Add any other initialization tasks here
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TODO: ensure proper licensing for the logo
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
