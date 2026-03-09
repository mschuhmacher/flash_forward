import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/presentation/widgets/my_calendar.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/presentation/screens/login_screen.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<int, GlobalKey> _iconButtonKeys = {};

  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionLogProvider, AuthProvider>(
      builder: (
        BuildContext context,
        sessionLogData,
        authProvider,
        Widget? child,
      ) {
        // Reverse the list to show the latest sessions first
        List<Session> selectedSessions =
            sessionLogData.selectedSessions.reversed.toList();

        return Column(
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
                          'Hey ${authProvider.userProfile?.firstName.isNotEmpty == true ? authProvider.userProfile!.firstName : "Climber"}!',
                          style: context.h1,
                        ),
                        Text('Ready to climb?', style: context.bodyMedium),
                      ],
                    ),
                  ),
                  // Profile/Sign Out button
                  PopupMenuButton<String>(
                    icon: CircleAvatar(
                      backgroundColor: context.colorScheme.primary,
                      child: Text(
                        authProvider.userProfile?.firstName.isNotEmpty == true
                            ? authProvider.userProfile!.firstName[0]
                                .toUpperCase()
                            : 'U',
                        style: context.titleMedium.copyWith(
                          color: context.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'signout':
                          _signOut();
                        case 'delete':
                          _deleteAccount();
                          break;
                        default:
                      }
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
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_rounded),
                                SizedBox(width: 8),
                                Text('Delete account'),
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

            SizedBox(height: 32),
            StartSessionButton(routeName: 'session_select_screen'),
            SizedBox(height: 32),
            MyCalendar(),
            SizedBox(height: 16),
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
                      backgroundColor: context.colorScheme.secondary,
                      foregroundColor: context.colorScheme.onSecondary,
                    ),
                    onPressed: _showClearLogsPopUp,
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
          ],
        );
      },
    );
  }

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
      final sessionLogProvider = Provider.of<SessionLogProvider>(
        context,
        listen: false,
      );
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      // Reset providers to allow re-initialization with different user
      await sessionLogProvider.reset();
      presetProvider.reset();

      await authProvider.signOut();

      // Navigate to login screen
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final _deleteController = TextEditingController();

    // Show confirmation dialog
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
              TextField(controller: _deleteController),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _deleteController,
              builder: (context, value, child) {
                return ElevatedButton(
                  onPressed:
                      value.text == 'delete'
                          ? () {
                            Navigator.of(context).pop(true);
                          }
                          : null,
                  child: Text('Delete account'),
                );
              },
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      final sessionLogProvider = Provider.of<SessionLogProvider>(
        context,
        listen: false,
      );
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      // Reset providers to allow re-initialization with different user
      await sessionLogProvider.reset();
      presetProvider.reset();

      // Delete user
      await authProvider.deleteUser();

      if (!mounted) return;

      // Show brief confirmation dialog
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

      // Wait 3 seconds, then navigate (pushAndRemoveUntil also removes the dialog route)
      await Future.delayed(const Duration(seconds: 3));

      // Navigate to login screen
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
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

        return Slidable(
          key: ValueKey(session.id),
          endActionPane: ActionPane(
            motion: ScrollMotion(),
            children: [
              SizedBox(width: 8),
              SlidableAction(
                // An action can be bigger than the others.
                flex: 3,
                onPressed: (context) {},
                backgroundColor: context.colorScheme.secondary,
                foregroundColor: context.colorScheme.onError,
                icon: Icons.edit_rounded,
                label: 'Edit',
              ),
              SlidableAction(
                flex: 2,
                onPressed: (context) {},
                backgroundColor: context.colorScheme.error,
                foregroundColor: context.colorScheme.onError,
                icon: Icons.delete_rounded,
                label: 'Delete',
              ),
            ],
          ),
          child: Material(
            //ListTile is wwrapped in a material widget so prevent the list from overflowing into the other widgets in the column. Known issue.
            child: ListTile(
              title: Text(session.title, style: context.titleMedium),
              subtitle: Text(
                '$formattedDate at $formattedTime',
                style: context.bodyMedium,
              ),
              trailing:
                  (kDefaultLabels.containsKey(session.label))
                      ? IconButton(
                        key: iconButtonKey,
                        icon: Icon(
                          kDefaultLabels[session.label]!.icon,
                          color: kDefaultLabels[session.label]!.color,
                          size: 20,
                        ),
                        onPressed: () {
                          _showLabelPopup(
                            context,
                            session.label,
                            iconButtonKey,
                          );
                        },
                        tooltip: session.label,
                      )
                      : null,
              tileColor: context.colorScheme.surfaceBright,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
                side: BorderSide(
                  color: context.colorScheme.onSurface,
                  width: 0.5,
                ),
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

  void _showClearLogsPopUp() {
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
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
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
