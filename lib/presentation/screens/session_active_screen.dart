import 'package:flash_forward/models/exercise_instance.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/session_active_bottom_bar.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

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
        ExerciseInstance activeExercise =
            activeWorkout.list[progress.exerciseIndex];

        //TODO: remove exerciseWidgets if not used
        List<Widget> exerciseWidgets =
            activeWorkout.list
                .map(
                  (name) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.title,
                        style: context.titleMedium.copyWith(
                          color: context.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        softWrap: true,
                        maxLines: 2,
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${name.description} \n',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onPrimary,
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
              style: context.bodyLarge.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              softWrap: true,
              maxLines: 2,
              textAlign: TextAlign.end,
            );
          }
        }

        String phaseText;
        switch (sessionStateData.phase) {
          case TimerPhase.setRest:
            phaseText = 'Rest between sets';
          case TimerPhase.rep:
            phaseText = 'Rep';
          case TimerPhase.repRest:
            phaseText = 'Rest between reps';
          case TimerPhase.exerciseRest:
            phaseText = 'Rest between exercises';
          case TimerPhase.workoutComplete:
            phaseText = 'Workout complete';
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 12.0, 20.0, 12.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.97,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [...workoutNames, SizedBox(height: 8)],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: context.colorScheme.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(150), // large curve
                          ),
                        ),
                        child: null,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          60.0,
                          60.0,
                          20.0,
                          12.0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeExercise.title,
                              style: context.h1.copyWith(
                                color: context.colorScheme.onPrimary,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              activeExercise.description,
                              style: context.bodyLarge.copyWith(
                                color: context.colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: context.colorScheme.primary,
                  child: Column(
                    children: [
                      Center(
                        child: Text(
                          phaseText,
                          style: context.h2.copyWith(
                            color: context.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: Text(
                              _formatDuration(sessionStateData.remaining),
                              style: context.h1.copyWith(
                                color: () {
                                  if (sessionStateData.isPaused) {
                                    return context.colorScheme.error;
                                  } else if (sessionStateData.phase ==
                                      TimerPhase.rep) {
                                    return Color(0xFF10b981);
                                  } else if ((sessionStateData.phase ==
                                              TimerPhase.repRest ||
                                          sessionStateData.phase ==
                                              TimerPhase.setRest ||
                                          sessionStateData.phase ==
                                              TimerPhase.exerciseRest) &&
                                      sessionStateData.remaining <
                                          Duration(seconds: 10)) {
                                    return context.colorScheme.secondary;
                                  } else {
                                    return context.colorScheme.onPrimary;
                                  }
                                }(),
                              ),
                              textScaler: TextScaler.linear(2.5),
                            ),
                          ),
                          Positioned(
                            right: 20,
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 44,
                              height: 44,
                              child: Center(
                                child:
                                    sessionStateData.isPaused
                                        ? IconButton(
                                          onPressed:
                                              () => sessionStateData.resume(
                                                activeSession,
                                              ),
                                          icon: Icon(Icons.play_arrow_rounded),
                                          color: context.colorScheme.onPrimary,
                                        )
                                        : IconButton(
                                          onPressed: sessionStateData.pause,
                                          icon: Icon(Icons.pause_rounded),
                                          color: context.colorScheme.onPrimary,
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 160,
                              height: 50,
                              child: Center(
                                child: Text(
                                  '${progress.currentSet} / ${activeExercise.sets}   sets',
                                  style: context.titleLarge.copyWith(
                                    color: context.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),

                            Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 160,
                              height: 50,
                              child: Center(
                                child: Text(
                                  '${progress.currentRep} / ${activeExercise.reps}   reps',
                                  style: context.titleLarge.copyWith(
                                    color: context.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 220,
                              height: 50,
                              child: Center(
                                child: Text(
                                  'Load: ${activeExercise.load}',
                                  style: context.titleLarge.copyWith(
                                    color: context.colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: context.colorScheme.primary,
                                borderRadius: BorderRadius.circular(16),
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 50,
                              height: 50,
                              child: Center(
                                child: IconButton(
                                  onPressed: () {
                                    _showEditExerciseDialog(
                                      context,
                                      activeExercise,
                                      sessionStateData,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.edit,
                                    color: context.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
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
                    SessionStateProvider().reset();
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

  void _showEditExerciseDialog(
    BuildContext context,
    ExerciseInstance activeExercise,
    SessionStateProvider sessionStateData,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: 20),
              title: Text(activeExercise.title, style: context.h2),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Description:', style: context.titleMedium),
                      Text(
                        activeExercise.description,
                        style: context.bodyMedium,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time between sets:', style: context.titleMedium),
                      Text(
                        '${activeExercise.timeBetweenSets} seconds',
                        style: context.bodyMedium,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time per rep:', style: context.titleMedium),
                      Text(
                        '${activeExercise.timePerRep} seconds',
                        style: context.bodyMedium,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Time between reps:', style: context.titleMedium),
                      Text(
                        '${activeExercise.timeBetweenReps} seconds',
                        style: context.bodyMedium,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RPE:', style: context.titleMedium),
                      Text('${activeExercise.rpe}', style: context.bodyMedium),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Load:', style: context.titleMedium),
                      SizedBox(width: 8),
                      // TODO: change to edit field
                      Text(activeExercise.load, style: context.bodyMedium),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Number of sets',
                          style: context.titleMedium,
                        ),
                      ),
                      SizedBox(width: 8),
                      IncrementDecrementNumberWidget(
                        value: activeExercise.sets,
                        minimum: sessionStateData.progress.currentSet,
                        decrement: () {
                          setDialogState(() {
                            activeExercise.sets--;
                          });
                        },
                        increment: () {
                          setDialogState(() {
                            activeExercise.sets++;
                          });
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Number of reps',
                          style: context.titleMedium,
                        ),
                      ),
                      SizedBox(width: 8),
                      IncrementDecrementNumberWidget(
                        value: activeExercise.reps,
                        minimum: sessionStateData.progress.currentRep,
                        decrement: () {
                          setDialogState(() {
                            activeExercise.reps--;
                          });
                        },
                        increment: () {
                          setDialogState(() {
                            activeExercise.reps++;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // TODO: autopause and unpause when dialog is opened
                        // SessionStateProvider().resume(activeSession);
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Close',
                        style: context.titleMedium.copyWith(
                          color: context.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
