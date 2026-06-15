import 'package:flash_forward/constants/urls.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/presentation/screens/profile_flow/restore_items_screen.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/core/settings_provider.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AuthProvider>().isAuthenticated;
    return Drawer(
      backgroundColor: context.colorScheme.surfaceBright,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text('Preferences', style: context.titleLargePrimary),
              ),
              Consumer<SettingsProvider>(
                builder:
                    (context, settings, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weight unit', style: context.titleMedium),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            // height: 40,
                            child: SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: [
                                ButtonSegment(
                                  value: 'kg',
                                  label: Text('kg', style: context.bodyMedium),
                                ),
                                ButtonSegment(
                                  value: 'lbs',
                                  label: Text('lbs', style: context.bodyMedium),
                                ),
                              ],
                              showSelectedIcon: false,
                              selected: {settings.weightUnit},
                              onSelectionChanged:
                                  (s) => settings.setWeightUnit(s.first),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text('Grade system', style: context.titleMedium),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: [
                                ButtonSegment(
                                  value: 'fontainebleau',
                                  label: Text(
                                    'Fontainebleau',
                                    style: context.bodyMedium,
                                  ),
                                ),
                                ButtonSegment(
                                  value: 'vscale',
                                  label: Text(
                                    'V-scale',
                                    style: context.bodyMedium,
                                  ),
                                ),
                              ],
                              showSelectedIcon: false,
                              selected: {settings.gradeSystem},
                              onSelectionChanged:
                                  (s) => settings.setGradeSystem(s.first),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Past entries are automatically converted to the selected system.',
                            style: context.bodyMedium.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text('Sound', style: context.titleMedium),
                              const SizedBox(width: 2),
                              IconButton(
                                icon: const Icon(Icons.info_outline_rounded),
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showSoundInfoDialog(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownMenu<SoundMode>(
                            initialSelection: settings.soundMode,
                            onSelected: (mode) {
                              if (mode != null) settings.setSoundMode(mode);
                            },
                            expandedInsets: EdgeInsets.symmetric(horizontal: 8),
                            textStyle: context.bodyMedium,
                            menuStyle: MenuStyle(
                              backgroundColor: WidgetStatePropertyAll(
                                context.colorScheme.surfaceBright,
                              ),
                              // optional, to match:
                              surfaceTintColor: const WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            dropdownMenuEntries: [
                              DropdownMenuEntry(
                                value: SoundMode.both,
                                label: 'Both',
                                labelWidget: Text(
                                  'Both',
                                  style: context.bodyMedium,
                                ),
                              ),
                              DropdownMenuEntry(
                                value: SoundMode.soundsOnly,
                                label: 'Sounds only',
                                labelWidget: Text(
                                  'Sounds only',
                                  style: context.bodyMedium,
                                ),
                              ),
                              DropdownMenuEntry(
                                value: SoundMode.notificationsOnly,
                                label: 'Notifications only',
                                labelWidget: Text(
                                  'Notifications only',
                                  style: context.bodyMedium,
                                ),
                              ),
                              DropdownMenuEntry(
                                value: SoundMode.none,
                                label: 'None',
                                labelWidget: Text(
                                  'None',
                                  style: context.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text('Overtime', style: context.titleMedium),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Automatically extend rests into overtime when the app is backgrounded.',
                              style: context.bodyMedium,
                            ),
                            value: settings.restOvertimeOnBackground,
                            onChanged:
                                (value) =>
                                    settings.setRestOvertimeOnBackground(value),
                          ),
                        ],
                      ),
                    ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Data', style: context.titleLargePrimary),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_rounded),
                title: Text('Clear logs', style: context.bodyLarge),
                onTap: () => _showClearLogsPopUp(context),
              ),
              if (isAuthenticated)
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: Text('Restore trash', style: context.bodyLarge),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RestoreItemsScreen(),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Account', style: context.titleLargePrimary),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: Text('Terms of service', style: context.bodyLarge),
                onTap: () async {
                  await launchUrl(URL.termsOfService);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: Text('Privacy statement', style: context.bodyLarge),
                onTap: () async {
                  await launchUrl(URL.privacyPolicy);
                },
              ),
              if (isAuthenticated) ...[
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text('Sign out', style: context.bodyLarge),
                  onTap: () => _signOut(context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_rounded),
                  title: Text('Delete account', style: context.bodyLarge),
                  onTap: () => _deleteAccount(context),
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(
                    'Sign in / Create account',
                    style: context.bodyLarge,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(popOnSuccess: true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sign out?', style: context.h3),
          content: Text(
            'Are you sure you want to sign out?',
            style: context.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (confirm == true && context.mounted) {
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

      await sessionLogProvider.reset();
      await catalogProvider.reset();
      await trashProvider.reset();
      syncStatus.detach();
      await authProvider.signOut();

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final deleteController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete account?', style: context.h3),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete your account? This is irreversible.',
                style: context.bodyMedium,
              ),
              SizedBox(height: 16),
              Text('Type \'delete\' to confirm.', style: context.bodyMedium),
              SizedBox(height: 8),
              TextField(controller: deleteController),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: deleteController,
              builder: (context, value, child) {
                return ElevatedButton(
                  onPressed:
                      value.text == 'delete'
                          ? () => Navigator.of(context).pop(true)
                          : null,
                  child: Text('Delete account'),
                );
              },
            ),
          ],
        );
      },
    );

    if (confirm == true && context.mounted) {
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

      await sessionLogProvider.reset();
      await catalogProvider.reset();
      await trashProvider.reset();
      syncStatus.detach();
      await authProvider.deleteUser();

      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: context.colorScheme.primary,
                  ),
                  SizedBox(height: 16),
                  Text('Account deleted', style: context.h3),
                  SizedBox(height: 8),
                  Text(
                    'Your account has been permanently deleted.',
                    style: context.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
      );

      await Future.delayed(const Duration(seconds: 3));

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showSoundInfoDialog(BuildContext context) {
    final isIOS = Platform.isIOS;
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Sound modes', style: dialogContext.h3),
            content: Text(
              isIOS
                  ? 'Both: Plays beeps in the app while your screen is on. Schedules notification sounds when the screen locks — note that iOS plays these with your device\'s notification settings, which may include vibration.\n\n'
                      'Sounds only: Beeps play in the app while the screen is on. No notifications when backgrounded.\n\n'
                      'Notifications only: No in-app sounds. Schedules notification sounds when the screen locks (with your device\'s notification settings, which may include vibration).\n\n'
                      'None: All sounds disabled. The timer runs silently.'
                  : 'Both: Plays beeps in the app while the screen is on. Schedules notification sounds when backgrounded — only the app\'s own sounds, no extra vibration.\n\n'
                      'Sounds only: Beeps play in the app while the screen is on. No notifications when backgrounded.\n\n'
                      'Notifications only: No in-app sounds. Schedules notification sounds when backgrounded — only the app\'s own sounds, no extra vibration.\n\n'
                      'None: All sounds disabled. The timer runs silently.',
              style: dialogContext.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  void _showClearLogsPopUp(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Clear logs', style: dialogContext.h3),
          content: Text(
            'Are you sure you want to clear your logs?',
            style: dialogContext.bodyMedium,
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Provider.of<SessionLogProvider>(
                      context,
                      listen: false,
                    ).clearAllLoggedSessions();
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text('Clear logs'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
