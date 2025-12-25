import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:training_schedule_app/models/exercise.dart';
import 'package:training_schedule_app/models/workout.dart';
import 'package:training_schedule_app/providers/preset_provider.dart';
import 'package:training_schedule_app/presentation/widgets/session_active_bottom_bar.dart';
import 'package:training_schedule_app/providers/session_state_provider.dart';
import 'package:training_schedule_app/themes/app_text_styles.dart';

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  bool _timerInitialized = false;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PresetProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        // Retrieving the needed data for the workout screen
        final activeSession =
            presetData.presetSessions[sessionStateData.sessionIndex];

        // Initialize the timer once when the screen first builds.
        if (!_timerInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Guard again in case the widget unmounted before the callback.
            if (!mounted || _timerInitialized) return;
            sessionStateData.start(activeSession);
            _timerInitialized = true;
          });
        }

        final progress = sessionStateData.progress;

        Workout activeWorkout = activeSession.list[progress.workoutIndex];
        Exercise activeExercise = activeWorkout.list[progress.exerciseIndex];

        List<Widget> exerciseWidgets =
            activeWorkout.list
                .map(
                  (name) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.title,
                        style: context.titleMedium.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        softWrap: true,
                        maxLines: 2,
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${name.description} \n',
                        style: context.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                )
                .toList();
        List<Widget> workoutNames =
            activeSession.list
                .map(
                  (name) => Text(
                    name.title,
                    style: context.bodyMedium,
                    softWrap: true,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                  ),
                )
                .toList();
        // Highlight the title of the current block in a list of block titles
        for (int i = 0; i < workoutNames.length; i++) {
          if (i == progress.workoutIndex) {
            workoutNames[i] = Text(
              activeSession.list[i].title,
              style: context.h3,
              softWrap: true,
              maxLines: 2,
              textAlign: TextAlign.end,
            );
          }
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () {
                _showCloseConfirmationDialog(context);
              },
              icon: Icon(Icons.close),
            ),
            title: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(activeSession.title, style: context.h4),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 12.0, 36.0, 12.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.95,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [...workoutNames, SizedBox(height: 8)],
                        // List.from(workoutNames)..addAll([
                        //   Text(
                        //     '\n ${activeWorkout.description}',
                        //     style: context.bodyMedium,
                        //     textAlign: TextAlign.end,
                        //   ),

                        //   SizedBox(height: 8),
                        // ]),
                        // Create new list from block names and add the block description to it with a whiteline in between
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // flex: 12,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(150), // large curve
                          ),
                        ),
                        child: null,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          60.0,
                          72.0,
                          24.0,
                          12.0,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...exerciseWidgets,
                              SizedBox(height: 16),
                              Text(
                                '${activeExercise.title}: Set ${progress.currentSet}/${activeExercise.sets} • '
                                'Rep ${progress.currentRep}/${activeExercise.reps}',
                                style: context.bodyMedium.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                                textAlign: TextAlign.end,
                              ),
                              Text(
                                'Phase: ${sessionStateData.phase.name} • Remaining: ${_formatDuration(sessionStateData.remaining)}',
                                style: context.bodyLarge.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.end,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: ActiveSessionBottomBar(),
        );
      },
    );
  }

  void _showCloseConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Close session?', style: context.h3),
          content: Text(
            'Are you sure you want to close this session? Your progress will not be saved.',
            style: context.bodyMedium,
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                  },
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                    Navigator.of(context).pop(); // Close the session screen
                  },
                  child: Text('Close'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
