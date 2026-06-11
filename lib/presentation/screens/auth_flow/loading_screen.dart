import 'package:flash_forward/presentation/screens/root_screen.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/core/sync/supabase_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
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

    // Navigate based on auth state
    if (authProvider.isAuthenticated) {
      if (!authProvider.isEmailConfirmed) {
        // User exists but email not confirmed - sign out and redirect to login
        await authProvider.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) =>
                    const LoginScreen(showEmailConfirmationMessage: true),
          ),
        );
        return;
      }
      // Email confirmed - proceed to home
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RootScreen()),
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

    if (!mounted) return;
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    await settingsProvider.init();

    // If user is authenticated, load their data
    if (authProvider.isAuthenticated) {
      if (!mounted) return;

      final userId = authProvider.userId;

      final sessionLogProvider = Provider.of<SessionLogProvider>(
        context,
        listen: false,
      );
      final catalogProvider = Provider.of<CatalogProvider>(
        context,
        listen: false,
      );
      final syncStatus = context.read<SyncStatusProvider>();
      final trashProvider = context.read<TrashProvider>();

      // Four-step wiring: attach the cloud service, then plug the catalog
      // into both sync-status and trash, then init.
      if (userId != null) {
        syncStatus.attach(SupabaseSyncService(userId: userId));
      }
      catalogProvider.attachSyncStatus(syncStatus);
      catalogProvider.attachTrashProvider(trashProvider);
      await sessionLogProvider.init(userId: userId);
      await catalogProvider.init(trash: trashProvider);

      // Process any pending sync operations from previous offline sessions
      await sessionLogProvider.processPendingSync();
      await syncStatus.processPendingSync();
    }
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
