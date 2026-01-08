import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/presentation/screens/add_item_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/session_select_row.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

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
        final sessionLabel =
            kDefaultLabels[currentSessionList[sessionStateData.sessionIndex]
                .label];

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: Text('Today\'s session', style: context.h4),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _editSessionModalSheet(context);
                  },
                  icon: Icon(Icons.edit),
                ),
              ],
            ),
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
                  item: currentSessionList[sessionStateData.sessionIndex].list,
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
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
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

  Future<dynamic> _editSessionModalSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext builder) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.95, // open at 80% of the screen height
          minChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Consumer2<PresetProvider, SessionStateProvider>(
                builder: (context, presetData, sessionStateData, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text('Default sessions', style: context.h4),
                      ),
                      SizedBox(height: 8),
                      SessionSelectListView(
                        item: presetData.presetDefaultSessions,
                        scrollMode: false,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child:
                            presetData.presetUserSessions.isNotEmpty
                                ? Row(
                                  children: [
                                    Text('Your sessions', style: context.h4),
                                    Spacer(),
                                    ElevatedButton(
                                      style: ButtonStyle().copyWith(
                                        backgroundColor:
                                            WidgetStateProperty.all<Color>(
                                              Theme.of(
                                                context,
                                              ).colorScheme.errorContainer,
                                            ),
                                        foregroundColor:
                                            WidgetStateProperty.all(
                                              Theme.of(
                                                context,
                                              ).colorScheme.onErrorContainer,
                                            ),
                                      ),
                                      onPressed: () {
                                        presetData
                                            .deleteAllUserPresetSessions();
                                        sessionStateData.setSessionIndex(0);
                                        Navigator.pop(context);
                                      },
                                      child: Text('Remove all'),
                                    ),
                                  ],
                                )
                                : SizedBox.shrink(),
                      ),
                      SizedBox(height: 8),
                      SessionSelectListView(
                        item: presetData.presetUserSessions,
                        editMode: true,
                        scrollMode: false,
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
