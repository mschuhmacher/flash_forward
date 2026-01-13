import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flash_forward/data/labels.dart';

import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/_UI_design_helper_screens/cheat_sheet_screen.dart';
import 'package:flash_forward/_UI_design_helper_screens/colorscheme_demo_screen.dart';
import 'package:flash_forward/presentation/widgets/my_calendar.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/presentation/screens/login_screen.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<int, GlobalKey> _iconButtonKeys = {};

  Future<void> _signOut() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Sign Out?', style: context.h3),
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
              child: Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await authProvider.signOut();

      // Navigate to login screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionLogProvider, AuthProvider>(
      builder: (
        BuildContext context,
        sessionLogData,
        authProvider,
        Widget? child,
      ) {
        // DEBUG: Add these lines temporarily
        print('Auth is authenticated: ${authProvider.isAuthenticated}');
        print('User profile: ${authProvider.userProfile}');
        print('First name: ${authProvider.userProfile?.firstName}');

        // Reverse the list to show the latest sessions first
        List<Session> selectedSessions =
            sessionLogData.selectedSessions.reversed.toList();

        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hey ${authProvider.userProfile?.firstName ?? "Climber"}!',
                              style: context.h1,
                            ),
                            Text('Ready to climb?', style: context.bodyMedium),
                          ],
                        ),
                      ),
                      // Profile/Sign Out button
                      PopupMenuButton<String>(
                        icon: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Text(
                            authProvider.userProfile?.firstName
                                    ?.substring(0, 1)
                                    .toUpperCase() ??
                                'U',
                            style: context.titleMedium.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'signout') {
                            _signOut();
                          }
                          // Add more menu options here later (profile, settings, etc.)
                        },
                        itemBuilder:
                            (BuildContext context) => [
                              PopupMenuItem<String>(
                                enabled: false,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      authProvider.userProfile?.fullName ?? '',
                                      style: context.titleMedium,
                                    ),
                                    Text(
                                      authProvider.userProfile?.email ?? '',
                                      style: context.bodyMedium.copyWith(
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem<String>(
                                value: 'signout',
                                child: Row(
                                  children: [
                                    Icon(Icons.logout),
                                    SizedBox(width: 8),
                                    Text('Sign Out'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 40),
                StartSessionButton(routeName: 'session_select_screen'),
                SizedBox(height: 40),
                MyCalendar(),
                SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        'Logged sessions',
                        style: context.h3,
                        textAlign: TextAlign.start,
                      ),
                      Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onSecondary,
                        ),
                        onPressed: () {
                          sessionLogData.clearAllLoggedSessions();
                        },
                        child: Text('Clear logs', style: context.bodyMedium),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      selectedSessions.isEmpty
                          ? Center(
                            child: Text(
                              'No climbing sessions logged yet.',
                              style: context.bodyLarge,
                            ),
                          )
                          : _buildListView(selectedSessions),
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  ListView _buildListView(List<Session> selectedSessions) {
    return ListView.separated(
      itemCount: selectedSessions.length,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      separatorBuilder: (context, index) => SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = selectedSessions[index];
        final date = session.date;

        // Ensure we have a GlobalKey for this index
        if (!_iconButtonKeys.containsKey(index)) {
          _iconButtonKeys[index] = GlobalKey();
        }
        final iconButtonKey = _iconButtonKeys[index]!;

        final formattedDate =
            date != null ? DateFormat('dd MMM yyyy').format(date) : '';
        final formattedTime =
            date != null ? DateFormat('HH:mm').format(date) : '';

        return Material(
          //ListTile is wwrapped in a material widget so prevent the list from overflowing into the other widgets in the column. Known issue.
          child: ListTile(
            title: Text(session.title, style: context.titleMedium),
            subtitle: Text(
              '$formattedDate at $formattedTime',
              style: context.bodyMedium,
            ),
            trailing:
                (session.label != null &&
                        kDefaultLabels.containsKey(session.label))
                    ? IconButton(
                      key: iconButtonKey,
                      icon: Icon(
                        kDefaultLabels[session.label]!.icon,
                        color: kDefaultLabels[session.label]!.color,
                        size: 20,
                      ),
                      onPressed: () {
                        _showLabelPopup(context, session.label!, iconButtonKey);
                      },
                      tooltip: session.label,
                    )
                    : null,
            tileColor: Theme.of(context).colorScheme.surfaceBright,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurface,
                width: 0.5,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLabelPopup(
    BuildContext context,
    String label,
    GlobalKey iconButtonKey,
  ) {
    final labelOption = kDefaultLabels[label]!;
    final RenderBox? renderBox =
        iconButtonKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final overlayState = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder:
          (overlayContext) => Stack(
            children: [
              // Transparent barrier to detect taps outside
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => overlayEntry?.remove(),
                  child: Container(color: Colors.transparent),
                ),
              ),
              // The popup card
              Positioned(
                top: position.dy + size.height + 8, // Position below the icon
                right:
                    MediaQuery.of(overlayContext).size.width -
                    position.dx -
                    size.width,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(overlayContext).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: context.shadowMedium,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          labelOption.icon,
                          color: labelOption.color,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(label, style: context.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
    );

    overlayState.insert(overlayEntry);

    // Auto-dismiss after 2 seconds
    Future.delayed(Duration(seconds: 2), () {
      overlayEntry?.remove();
    });
  }
}
