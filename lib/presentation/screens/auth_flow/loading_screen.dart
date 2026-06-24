import 'package:flash_forward/presentation/screens/root_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/auth/guest_mode_store.dart';
import 'package:flash_forward/features/auth/sign_in_coordinator.dart';
import 'package:flash_forward/core/settings_provider.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

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

    // Run initialization with display time
    await Future.wait([
      _loadData(),
      Future.delayed(const Duration(seconds: 1)),
    ]);

    if (!mounted) return;

    // Authenticated but email not confirmed: sign out, back to login. Checked
    // here (and in _loadData) before any provider wiring, so we never half-init
    // for a user we're about to sign out.
    if (authProvider.isAuthenticated && !authProvider.isEmailConfirmed) {
      await authProvider.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(showEmailConfirmationMessage: true),
        ),
      );
      return;
    }

    // Authenticated, or a remembered guest → home. Otherwise → login.
    if (authProvider.isAuthenticated || await GuestModeStore.isEnabled()) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootScreen()),
      );
    } else {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Initialize auth first
    await authProvider.init();

    if (!mounted) return;
    // Settings init runs once regardless of which route is taken; it stays
    // here rather than in the coordinator.
    await Provider.of<SettingsProvider>(context, listen: false).init();
    if (!mounted) return;

    final coordinator = SignInCoordinator.of(context);
    if (authProvider.isAuthenticated && authProvider.isEmailConfirmed) {
      final userId = authProvider.userId;
      if (userId != null) await coordinator.initForUser(userId);
    } else if (await GuestModeStore.isEnabled()) {
      await coordinator.initForGuest();
    }
    // Unconfirmed-email or not-yet-guest: no provider wiring; _initializeApp
    // routes to login.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/bouldering_logo.png',
              width: 120,
              height: 120,
              color: context.colorScheme.onSurface,
            ),
            const SizedBox(height: 24),
            Text('Flash Forward', style: context.h1),
            const SizedBox(height: 40),
            CircularProgressIndicator(color: context.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
