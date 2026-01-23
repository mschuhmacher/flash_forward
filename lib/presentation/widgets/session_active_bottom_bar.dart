import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/my_icon_button.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/services/session_logger.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

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

        String nextExerciseString;
        if (progress.exerciseIndex + 1 < activeWorkout.list.length) {
          nextExerciseString =
              'Next exercise: \n${activeWorkout.list[progress.exerciseIndex + 1].title}';
        } else if (progress.exerciseIndex + 1 == activeWorkout.list.length &&
            progress.workoutIndex + 1 < activeSession.list.length) {
          nextExerciseString =
              'Next exercise: \n${activeSession.list[progress.workoutIndex + 1].list[0].title}';
        } else if (progress.exerciseIndex + 1 == activeWorkout.list.length &&
            progress.workoutIndex + 1 == activeSession.list.length) {
          nextExerciseString = 'Next exercise: \nDone';
        } else {
          nextExerciseString = '';
        }

        return SizedBox(
          height: 100,
          child: BottomAppBar(
            color: context.colorScheme.primary,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    (sessionStateData.progress.exerciseIndex == 0 &&
                            sessionStateData.progress.workoutIndex == 0)
                        ? SizedBox.shrink()
                        : GestureDetector(
                          onTap: () {
                            //TODO: this cannot regress past the first exercise of a workout. change to go further or add a button for workout skipping
                            sessionStateData.jumpToExercise(
                              sessionStateData.exerciseIndex - 1,
                              activeSession,
                            );
                          },
                          child: MyIconButton(
                            icon: Icons.arrow_back,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
                          ),
                        ),
                    Expanded(
                      child: Center(
                        child: Text(
                          nextExerciseString,
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.onPrimary,
                          ),
                          overflow: TextOverflow.fade,
                        ),
                      ),
                    ),

                    (sessionStateData.workoutIndex >= 0 &&
                            sessionStateData.workoutIndex <
                                activeSession.list.length - 1)
                        ? GestureDetector(
                          onTap: () {
                            sessionStateData.jumpToExercise(
                              sessionStateData.exerciseIndex + 1,
                              activeSession,
                            );
                          },
                          child: MyIconButton(
                            icon: Icons.arrow_forward,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
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
                          child: MyIconButton(
                            icon: Icons.check,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
                          ),
                        ),
                  ],
                ),
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

                      // Reset the session state data
                      SessionStateProvider().reset();

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
