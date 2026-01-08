import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flash_forward/data/labels.dart';

import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/_UI_design_helper_screens/cheat_sheet_screen.dart';
import 'package:flash_forward/_UI_design_helper_screens/colorscheme_demo_screen.dart';
import 'package:flash_forward/presentation/widgets/my_calendar.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<int, GlobalKey> _iconButtonKeys = {};

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionLogProvider>(
      builder: (BuildContext context, sessionLogData, Widget? child) {
        // Reverse the list to show the latest sessions first
        List<Session> selectedSessions =
            sessionLogData.selectedSessions.reversed.toList();

        return Scaffold(
          // appBar: AppBar(
          //   backgroundColor: Theme.of(context).colorScheme.surface,
          //   title: SizedBox.shrink(),
          // title: Row(
          //   children: [
          //     ElevatedButton(
          //       onPressed: () {
          //         Navigator.push(
          //           context,
          //           MaterialPageRoute(
          //             builder: (context) => ColorSchemeDemoScreen(),
          //           ),
          //         );
          //       },
          //       child: Text(' test screen'),
          //     ),
          //     ElevatedButton(
          //       onPressed: () {
          //         Navigator.push(
          //           context,
          //           MaterialPageRoute(
          //             builder: (context) => Material3ColorCheatSheet(),
          //           ),
          //         );
          //       },
          //       child: Text(' cheat sheet'),
          //     ),
          //   ],
          // ),
          //   centerTitle: true,
          // ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 24),
                  child: Text('Hey, ready to climb?', style: context.h1),
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
