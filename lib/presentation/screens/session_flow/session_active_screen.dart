import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/utils/timer_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/session_active_bottom_bar.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  bool _timerInitialized = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<PresetProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        // Initialize the timer & keep screen awake once when the screen first builds.
        // Passes the preset session to start(), which deep-copies it internally.
        if (!_timerInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Guard again in case the widget unmounted before the callback.
            if (!mounted || _timerInitialized) return;
            final presetSession = presetData.presetSessions[sessionStateData.sessionIndex];
            sessionStateData.start(presetSession);
            _timerInitialized = true;

            // Start keeping screen awake
            WakelockPlus.enable();
          });
        }

        // Use the provider's active session copy — never the preset directly
        final activeSession = sessionStateData.activeSession;
        if (activeSession == null) return const Scaffold();

        final progress = sessionStateData.progress;

        Workout activeWorkout = activeSession.workouts[progress.workoutIndex];
        Exercise activeExercise = activeWorkout.exercises[progress.exerciseIndex];

        List<Widget> workoutNames =
            activeSession.workouts
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
        workoutNames[progress.workoutIndex] = Text(
          activeSession.workouts[progress.workoutIndex].title,
          style: context.bodyLarge.copyWith(
            color: context.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
          softWrap: true,
          maxLines: 2,
          textAlign: TextAlign.end,
        );

        // Limit displayed workout names to max 4 with sliding window
        final totalWorkouts = workoutNames.length;
        final currentIndex = progress.workoutIndex;
        List<Widget> displayedWorkoutNames;

        if (totalWorkouts <= 4) {
          // Show all items
          displayedWorkoutNames = workoutNames;
        } else if (currentIndex >= totalWorkouts - 3) {
          // Near the end: show last 4 without ellipsis
          displayedWorkoutNames = workoutNames.sublist(totalWorkouts - 4);
        } else {
          // In the middle: show 3 items + ellipsis
          final startIndex = (currentIndex - 1).clamp(0, totalWorkouts - 4);
          displayedWorkoutNames = [
            ...workoutNames.sublist(startIndex, startIndex + 3),
            Text('...', style: context.bodyMedium, textAlign: TextAlign.end),
          ];
        }

        final isManualRep = activeExercise.type == ExerciseType.manual &&
            sessionStateData.phase == TimerPhase.rep;

        String phaseText;
        TextStyle phaseTextStyle = context.h2.copyWith(
          color: context.colorScheme.onPrimary,
        );
        switch (sessionStateData.phase) {
          case TimerPhase.setRest:
            phaseText = 'rest between sets';
          case TimerPhase.rep:
            if (activeExercise.type == ExerciseType.manual) {
              phaseText = 'set ${progress.currentSet} of ${activeExercise.sets}';
            } else {
              phaseText = 'rep';
            }
          case TimerPhase.repRest:
            phaseText = 'rest';
          case TimerPhase.exerciseRest:
            phaseText = 'rest between exercises';
          case TimerPhase.workoutComplete:
            phaseText = 'workout complete';
          case TimerPhase.paused:
            phaseText = 'paused';
            phaseTextStyle = context.h2.copyWith(
              color: context.colorScheme.tertiary,
            );
          case TimerPhase.getReady:
            phaseText = 'get ready';
            phaseTextStyle = context.h2.copyWith(
              color: context.colorScheme.secondary,
            );
        }

        // Reps display text: show '-/-' when no rep target is set
        final repsText = activeExercise.reps != null
            ? '${progress.currentRep} / ${activeExercise.reps}   reps'
            : '-/-   reps';

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
                        children: [
                          ...displayedWorkoutNames,
                          SizedBox(height: 8),
                        ],
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
                          boxShadow: context.shadowLarge,
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
                      Center(child: Text(phaseText, style: phaseTextStyle)),
                      // ── Timer or manual-advance button ──────────
                      if (isManualRep)
                        _ManualAdvanceButton(
                          isLastSet: progress.currentSet >= activeExercise.sets,
                          onPressed: () => sessionStateData.advanceManually(),
                          color: context.colorScheme.onPrimary,
                        )
                      else
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: Text(
                                formatDuration(sessionStateData.remaining),
                                style: context.h1.copyWith(
                                  color: () {
                                    if (sessionStateData.isPaused) {
                                      return context.colorScheme.tertiary;
                                    } else if (sessionStateData.phase ==
                                        TimerPhase.getReady) {
                                      return context.colorScheme.secondary;
                                    } else if (sessionStateData.phase ==
                                        TimerPhase.rep) {
                                      return context.colorScheme.onPrimary;
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
                                            onPressed: () {
                                              sessionStateData.resume();
                                              WakelockPlus.enable();
                                            },
                                            icon: Icon(Icons.play_arrow_rounded),
                                            color: context.colorScheme.onPrimary,
                                          )
                                          : IconButton(
                                            onPressed: () {
                                              sessionStateData.pause();
                                              WakelockPlus.disable();
                                            },
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
                                boxShadow: context.shadowMedium,
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
                                boxShadow: context.shadowMedium,
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
                                  repsText,
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
                                boxShadow: context.shadowMedium,
                                border: BoxBorder.all(
                                  color: context.colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              width: 220,
                              height: 50,
                              child: Center(
                                child: Text(
                                  'Load: ${activeExercise.load.toString()} kg',
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
                                boxShadow: context.shadowMedium,
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
                                      progress.workoutIndex,
                                      progress.exerciseIndex,
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
    Exercise activeExercise,
    SessionStateProvider sessionStateData,
    int workoutIndex,
    int exerciseIndex,
  ) {
    // Track local edits in dialog state; apply to provider on close
    int localSets = activeExercise.sets;
    int? localReps = activeExercise.reps;
    bool localRepsEnabled = activeExercise.reps != null;

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
                  // Only show timing details for timedReps exercises
                  if (activeExercise.type == ExerciseType.timedReps) ...[
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
                  ],
                  if (activeExercise.type == ExerciseType.fixedDuration) ...[
                    SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Active time:', style: context.titleMedium),
                        Text(
                          '${activeExercise.activeTime} seconds',
                          style: context.bodyMedium,
                        ),
                      ],
                    ),
                  ],
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
                      Text(
                        activeExercise.load.toString(),
                        style: context.bodyMedium,
                      ),
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
                        value: localSets,
                        minimum: sessionStateData.progress.currentSet,
                        decrement: () {
                          setDialogState(() => localSets--);
                        },
                        increment: () {
                          setDialogState(() => localSets++);
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // Rep target: editable for timedReps (required), optional for others
                  if (activeExercise.type == ExerciseType.timedReps)
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
                          value: localReps ?? 1,
                          minimum: sessionStateData.progress.currentRep,
                          decrement: () {
                            setDialogState(() => localReps = ((localReps ?? 1) - 1).clamp(1, 9999));
                          },
                          increment: () {
                            setDialogState(() => localReps = (localReps ?? 1) + 1);
                          },
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rep target', style: context.titleMedium),
                        Switch(
                          value: localRepsEnabled,
                          onChanged: (enabled) {
                            setDialogState(() {
                              localRepsEnabled = enabled;
                              if (enabled) localReps ??= 5;
                            });
                          },
                        ),
                      ],
                    ),
                    if (localRepsEnabled)
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
                            value: localReps ?? 5,
                            minimum: 1,
                            decrement: () {
                              setDialogState(() => localReps = ((localReps ?? 5) - 1).clamp(1, 9999));
                            },
                            increment: () {
                              setDialogState(() => localReps = (localReps ?? 5) + 1);
                            },
                          ),
                        ],
                      ),
                  ],
                ],
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // Apply local edits to the active session copy via the provider
                        sessionStateData.updateActiveExercise(
                          workoutIndex,
                          exerciseIndex,
                          activeExercise.copyWith(
                            sets: localSets,
                            reps: localRepsEnabled ? localReps : null,
                          ),
                        );
                        // TODO: autopause and unpause when dialog is opened
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

/// Button shown instead of the countdown timer for manual-type exercises.
class _ManualAdvanceButton extends StatelessWidget {
  final bool isLastSet;
  final VoidCallback onPressed;
  final Color color;

  const _ManualAdvanceButton({
    required this.isLastSet,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colorScheme.onPrimary,
          foregroundColor: context.colorScheme.primary,
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          isLastSet ? 'Done' : 'Next set',
          style: context.titleLarge.copyWith(
            color: context.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
