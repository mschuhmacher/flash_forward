import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class SessionSelectListView extends StatelessWidget {
  const SessionSelectListView({
    super.key,
    required this.item,
    this.setIndex,
    this.route,
    this.editMode = false,
    this.scrollMode = true,
  });
  final List<dynamic> item;
  final dynamic route;
  final void Function(int index)?
  setIndex; // was used for session_overview_screen. all session in a list, and tapping a session would set the index of the row_selection to the correct sessions. Remove?
  final bool editMode;
  final bool scrollMode;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics:
          scrollMode
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
      // depending on scrollMode it lets the user scrolls or not. The bottomModalSheet for editing sessions is in a singleChildScrollView
      shrinkWrap: true,
      itemBuilder: (context, index) {
        return Consumer<SessionLogProvider>(
          builder: (context, trainingData, child) {
            return GestureDetector(
              onTap: () {
                if (setIndex != null) {
                  // setIndex in not a required parameter
                  setIndex!(index);
                }
                if (route != null) {
                  // route is not a required parameter.
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => route),
                  );
                }
              },
              child: MyListViewCard(
                item: item,
                index: index,
                editMode: editMode,
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => SizedBox(height: 8),
      itemCount: item.length,
    );
  }
}

class MyListViewCard extends StatelessWidget {
  const MyListViewCard({
    super.key,
    required this.item,
    required this.index,
    required this.editMode,
  });

  final List item;
  final int index;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20),
      child: Consumer2<PresetProvider, SessionStateProvider>(
        builder: (context, presetData, sessionStateData, child) {
          return Container(
            padding: EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                width: 0.25,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              color: Theme.of(context).colorScheme.surfaceBright,
              boxShadow: context.shadowSmall,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item[index].title,
                        style: context.titleMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (editMode == true) ...[
                      Spacer(),
                      IconButton.outlined(
                        color: Theme.of(context).colorScheme.onSurface,
                        onPressed: null,
                        icon: Icon(Icons.edit),
                      ),
                      IconButton.outlined(
                        onPressed: () {
                          if (sessionStateData.sessionIndex ==
                              presetData.presetSessions.length - 1) {
                            sessionStateData.decrementSessionIndex();
                          }
                          presetData.deleteUserPresetSession(index);
                        },
                        icon: Icon(Icons.delete),
                      ),
                    ],
                  ],
                ),
                Divider(
                  thickness: 0.75,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                // loops through the exerciseList and creates Text widget for each one. ListView iterates through the blockList.
                for (var item in item[index].list)
                  Text(item.title, style: context.bodyMedium),
              ],
            ),
          );
        },
      ),
    );
  }
}
