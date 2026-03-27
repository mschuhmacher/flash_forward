import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/_OLD_add_item_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/session_select_row.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

class SessionSelectScreen extends StatefulWidget {
  final dynamic index;

  const SessionSelectScreen({super.key, this.index});

  @override
  State<SessionSelectScreen> createState() => _SessionSelectScreenState();
}

class _SessionSelectScreenState extends State<SessionSelectScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer2<PresetProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        final currentSessionList = presetData.presetSessions;

        // Guard clause: show loading indicator if sessions are loading
        if (presetData.isLoading) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Today\'s session', style: context.h4),
              centerTitle: true,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
// If done loading but sessionList remains empty due to error
        if (presetData.isLoading == false && currentSessionList.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Today\'s session', style: context.h4),
              centerTitle: true,
            ),
            body: Center(
              child: Text('No sessions found...', style: context.h2),
            ),
          );
        }

        final sessionLabel =
            kDefaultLabels[currentSessionList[sessionStateData.sessionIndex]
                .label];

        return Scaffold(
          appBar: AppBar(
            title: Text('Today\'s session', style: context.h4),
            centerTitle: true,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),
              SessionSelectRow(caseStatement: 'Session'),
              SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Row(
                  // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.75,
                      child: Text(
                        currentSessionList[sessionStateData.sessionIndex].title,
                        style: context.h3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    Spacer(),
                    Icon(sessionLabel?.icon, color: sessionLabel?.color),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Expanded(
                child: SessionSelectListView(
                  item: currentSessionList[sessionStateData.sessionIndex].workouts,
                ),
              ),
              SizedBox(height: 80),
            ],
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: StartSessionButton(routeName: 'workout_screen'),
                  ),
                ),
                FloatingActionButton(
                  backgroundColor: context.colorScheme.secondary,
                  foregroundColor: context.colorScheme.onSecondary,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => AddItemScreen(itemName: 'session'),
                      ),
                    );
                  },
                  child: Icon(Icons.add),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
