import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/my_arrow_button.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/services/session_logger.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class ActiveSessionBottomBar extends StatefulWidget {
  const ActiveSessionBottomBar({super.key});

  @override
  State<ActiveSessionBottomBar> createState() => _ActiveSessionBottomBarState();
}

class _ActiveSessionBottomBarState extends State<ActiveSessionBottomBar> {
  @override
  Widget build(BuildContext context) {
    return Consumer3<PresetProvider, SessionLogProvider, SessionStateProvider>(
      builder: (context, presetData, sessionLogData, sessionStateData, child) {
        final Session activeSession =
            presetData.presetSessions[sessionStateData.sessionIndex];

        final progress = sessionStateData.progress;
        Workout activeWorkout = activeSession.list[progress.workoutIndex];

        return SizedBox(
          height: 110,
          child: BottomAppBar(
            color: Theme.of(context).colorScheme.primary,
            child: Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  sessionStateData.workoutIndex > 0
                      ? GestureDetector(
                        onTap: () {
                          sessionStateData.jumpToWorkout(
                            sessionStateData.workoutIndex - 1,
                            activeSession,
                          );
                        },
                        child: MyArrowButton(icon: Icons.arrow_back, size: 40),
                      )
                      : SizedBox.shrink(),

                  if (progress.exerciseIndex + 1 < activeWorkout.list.length)
                    Text(
                      'Next exercise: \n${activeWorkout.list[progress.exerciseIndex + 1].title}',
                      style: context.bodyLarge.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),

                  (sessionStateData.workoutIndex >= 0 &&
                          sessionStateData.workoutIndex <
                              activeSession.list.length - 1)
                      ? GestureDetector(
                        onTap: () {
                          sessionStateData.jumpToWorkout(
                            sessionStateData.workoutIndex + 1,
                            activeSession,
                          );
                        },
                        child: MyArrowButton(
                          icon: Icons.arrow_forward,
                          size: 40,
                        ),
                      )
                      : GestureDetector(
                        onTap: () {
                          _showFinishSessionDialog(
                            context,
                            activeSession,
                            sessionLogData,
                          );
                        },
                        child: MyArrowButton(icon: Icons.check, size: 40),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFinishSessionDialog(
    BuildContext context,
    Session activeSession,
    SessionLogProvider sessionLogData,
  ) {
    final labelController = TextEditingController(text: activeSession.label);
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Session summary', style: dialogContext.h3),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workouts completed:', style: dialogContext.bodyLarge),
                SizedBox(height: 8),
                ...activeSession.list.map(
                  (workout) => Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                    child: Text(
                      '• ${workout.title}',
                      style: dialogContext.bodyMedium,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                MyLabelDropdownButton(
                  value: activeSession.label,
                  // labelController.text.isNotEmpty
                  //     ? labelController.text
                  //     : null,
                  onChanged: (value) {
                    setState(() {
                      labelController.text = value ?? '';
                    });
                  },
                  validator:
                      (value) =>
                          value == null || value.isEmpty
                              ? 'Please select a label'
                              : null,
                ),
                SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Add notes about your session...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  style: dialogContext.bodyMedium,
                ),
              ],
            ),
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
                  onPressed: () async {
                    // Create a new session with the label and description
                    final finishedSession = Session(
                      id: activeSession.id,
                      title: activeSession.title,
                      label: labelController.text,
                      description:
                          descriptionController.text.isEmpty
                              ? null
                              : descriptionController.text,
                      date: DateTime.now(),
                      list: activeSession.list,
                    );

                    Navigator.of(dialogContext).pop();

                    await SessionLogger.logSession(finishedSession);
                    sessionLogData.refreshSelectedSessions(finishedSession);

                    // Only use the buildContext is it still mounted. Meaning, the widget is still in the Widgettree.
                    // If user leaves screen before await is done, mounted would be false
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Session saved to log!')),
                      );

                      // Keeps popping routes until the current route is the first route. Not named,so no errors.
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                  child: Text('Finish'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
