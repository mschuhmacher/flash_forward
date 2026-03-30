import 'package:flash_forward/presentation/screens/training_program_flow/_OLD_add_item_screen.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/presentation/screens/session_flow/home_screen.dart';
import 'package:flash_forward/presentation/screens/profile_flow/profile_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_session_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/program_screen.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:provider/provider.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with SingleTickerProviderStateMixin {
  late final List<Widget> destinationScreens;
  int _selectedScreenIndex = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    destinationScreens = [
      HomeScreen(),
      ProgramScreen(tabController: _tabController),
      ProfileScreen(),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _selectedScreenIndex == 1
              ? AppBar(
                title: TabBar(
                  controller: _tabController,
                  labelStyle: context.titleLarge.copyWith(
                    color: context.colorScheme.primary,
                  ),
                  tabs: [
                    Tab(text: 'Sessions'),
                    Tab(text: 'Workouts'),
                    Tab(text: 'Exercises'),
                  ],
                ),
                surfaceTintColor:
                    Colors
                        .transparent, //disables Material3 overlay. I.e. doesn't change the color of the appBar when the ListView scrolls
              )
              : null,
      body: SafeArea(child: destinationScreens[_selectedScreenIndex]),
      floatingActionButton:
          _selectedScreenIndex == 1
              ? FloatingActionButton(
                onPressed: () {
                  switch (_tabController.index) {
                    case 0:
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NewSessionScreen()),
                      );
                    case 1:
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NewWorkoutScreen()),
                      );
                    case 2:
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NewExerciseScreen()),
                      );
                  }
                },
                child: Icon(Icons.add),
              )
              : null,
      endDrawer: _selectedScreenIndex == 2 ? SettingsDrawer() : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          boxShadow: context.shadowLarge,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Consumer<AuthProvider>(
              builder:
                  (context, authProvider, child) => GNav(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    // rippleColor: context.colorScheme.primary.withAlpha(50),
                    gap: 8,
                    iconSize: 24,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    duration: Duration(milliseconds: 400),
                    activeColor: context.colorScheme.primary,
                    color: context.colorScheme.primary,
                    // tabBackgroundColor: context.colorScheme.surfaceDim,
                    textStyle: context.bodyLarge.copyWith(
                      color: context.colorScheme.primary,
                    ),
                    tabActiveBorder: Border.all(
                      color: context.colorScheme.primary,
                      width: 1,
                    ),
                    tabs: [
                      GButton(icon: Icons.home_rounded, text: 'Home'),
                      GButton(icon: Icons.event_note_rounded, text: 'Program'),
                      GButton(
                        icon: Icons.person_rounded,
                        text:
                            authProvider.userProfile?.firstName.isNotEmpty ==
                                    true
                                ? authProvider.userProfile!.firstName
                                : "Climber",
                      ),
                    ],
                    selectedIndex: _selectedScreenIndex,
                    onTabChange: (index) {
                      setState(() {
                        _selectedScreenIndex = index;
                      });
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: context.colorScheme.surfaceBright,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text('Preferences', style: context.titleMedium),
            ),
            Consumer<SettingsProvider>(
              builder:
                  (context, settings, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Weight unit', style: context.bodyMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'kg', label: Text('kg')),
                            ButtonSegment(value: 'lbs', label: Text('lbs')),
                          ],
                          selected: {settings.weightUnit},
                          onSelectionChanged:
                              (s) => settings.setWeightUnit(s.first),
                        ),
                        const SizedBox(height: 20),
                        Text('Grade system', style: context.bodyMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'fontainebleau',
                              label: Text('Fontainebleau'),
                            ),
                            ButtonSegment(
                              value: 'vscale',
                              label: Text('V-scale'),
                            ),
                          ],
                          selected: {settings.gradeSystem},
                          onSelectionChanged:
                              (s) => settings.setGradeSystem(s.first),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Past entries use their stored system and will still display correctly.',
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Data', style: context.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded),
              title: Text('Clear logs', style: context.bodyMedium),
              onTap: () => _showClearLogsPopUp(context),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Account', style: context.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text('Privacy statement', style: context.bodyMedium),
              onTap: () => _signOut(context),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text('Sign out', style: context.bodyMedium),
              onTap: () => _signOut(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded),
              title: Text('Delete account', style: context.bodyMedium),
              onTap: () => _deleteAccount(context),
            ),
          ],
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
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      await sessionLogProvider.reset();
      presetProvider.reset();
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
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      await sessionLogProvider.reset();
      presetProvider.reset();
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
