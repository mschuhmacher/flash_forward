import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/presentation/widgets/label_badge.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/utils/timer_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/catalog_provider.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_active_bottom_bar.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_session_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:io' show Platform;

class ActiveSessionScreen extends StatefulWidget {
  final Session session;

  const ActiveSessionScreen({super.key, required this.session});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

// WidgetsBindingObserver lets this widget react to app lifecycle changes.
// When the app returns to the foreground (e.g. after the screen was locked),
// didChangeAppLifecycleState fires with AppLifecycleState.resumed. We use
// that to call reconcileAfterBackground(), which measures how much real time
// passed while the Dart isolate was suspended and fast-forwards the timer
// accordingly. It also reschedules any remaining beep notifications from the
// new position.
class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with WidgetsBindingObserver {
  bool _timerInitialized = false;

  // Context of the open edit-exercise modal, captured when it opens and
  // cleared when it closes. Lets us pop it from outside (e.g. when the
  // anchored exercise is deleted mid-session).
  BuildContext? _editModalContext;

  // Provider reference + listener for the anchor-deleted signal. Attached
  // once in didChangeDependencies, detached in dispose.
  SessionStateProvider? _sessionProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<SessionStateProvider>();
    if (provider != _sessionProvider) {
      _sessionProvider?.anchorDeletedSignal.removeListener(_onAnchorDeleted);
      _sessionProvider = provider;
      _sessionProvider!.anchorDeletedSignal.addListener(_onAnchorDeleted);
    }
  }

  /// Closes the open edit-exercise modal when the anchored exercise was
  /// deleted mid-session and re-anchoring jumped elsewhere. The modal's
  /// target no longer exists, so editing it makes no sense.
  ///
  /// Deferred to the next frame: the signal fires from replaceActiveSession
  /// while NewSessionScreen (the editor) is still on top of the modal and
  /// about to pop itself. Popping now would target the wrong route, so we
  /// wait until the editor has been removed.
  void _onAnchorDeleted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final modalContext = _editModalContext;
      if (modalContext != null && modalContext.mounted) {
        Navigator.of(modalContext).pop();
      }
    });
  }

  @override
  void dispose() {
    _sessionProvider?.anchorDeletedSignal.removeListener(_onAnchorDeleted);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<SessionStateProvider>();
    if (state == AppLifecycleState.resumed) {
      provider.setForegrounded(true);
    } else if (state == AppLifecycleState.paused) {
      provider.setForegrounded(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CatalogProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        // Initialize the timer & keep screen awake once when the screen first builds.
        // Passes the session to start(), which deep-copies it internally.
        if (!_timerInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // Guard again in case the widget unmounted before the callback.
            if (!mounted || _timerInitialized) return;
            final settings = context.read<SettingsProvider>();
            sessionStateData.start(widget.session);
            sessionStateData.setSoundMode(settings.soundMode);
            sessionStateData.setRestOvertimeOnBackground(
              settings.restOvertimeOnBackground,
            );
            _timerInitialized = true;

            // Start keeping screen awake
            WakelockPlus.enable();

            // Android 12+: SCHEDULE_EXACT_ALARM lets us fire beep sounds
            // exactly on time even when the screen is locked. Show a rationale
            // dialog before sending the user to the system settings page.
            // No-op on iOS and on Android where permission is already granted.
            if (Platform.isAndroid) {
              final canSchedule =
                  await sessionStateData.canScheduleExactAlarms();
              if (!canSchedule && context.mounted) {
                await showDialog<void>(
                  context: context,
                  builder:
                      (dialogContext) => AlertDialog(
                        title: const Text('Allow exact alarms'),
                        content: const Text(
                          'Flash Forward schedules audio beeps during your session '
                          'so they fire on time even with the screen locked.\n\n'
                          'Tap Allow to enable this in Settings.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Not now'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await sessionStateData
                                  .requestExactAlarmPermission();
                            },
                            child: const Text('Allow'),
                          ),
                        ],
                      ),
                );
              }
            }
          });
        }

        // Use the provider's active session copy — never the preset directly
        final activeSession = sessionStateData.activeSession;
        if (activeSession == null) {
          return Scaffold(
            body: Center(
              child: Text('Session is empty', style: context.bodyLarge),
            ),
          );
        }

        if (activeSession.workouts.any((w) => w.exercises.isEmpty)) {
          return Scaffold(
            body: Center(
              child: Text(
                'This session has workouts without exercises. Add exercises to your workouts before starting a session.',
                style: context.bodyLarge,
              ),
            ),
          );
        }

        final progress = sessionStateData.progress;

        // workoutComplete is a live, navigable phase: the exercise-level UI is
        // replaced by a "Workout complete" state, but the user can still jump
        // back into the workout (bottom bar) or add exercises (edit button).
        final bool isComplete =
            sessionStateData.phase == TimerPhase.workoutComplete;

        Workout activeWorkout = activeSession.workouts[progress.workoutIndex];
        // Clamp so this read never throws. In complete state the value is
        // arbitrary-but-valid and isn't displayed; in every other phase
        // exerciseIndex is already in range.
        Exercise activeExercise = activeWorkout.exercises[progress.exerciseIndex
            .clamp(0, activeWorkout.exercises.length - 1)];

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

        final isManualRep =
            activeExercise.type == ExerciseType.manual &&
            sessionStateData.phase == TimerPhase.rep;

        String phaseText;
        TextStyle phaseTextStyle = context.h2.copyWith(
          color: context.colorScheme.onPrimary,
        );
        final effectiveSets = setsForExerciseInWorkout(
          activeWorkout,
          activeExercise,
        );
        switch (sessionStateData.phase) {
          case TimerPhase.setRest:
            phaseText = 'rest between sets';
          case TimerPhase.supersetRest:
            phaseText = 'superset rest';
          case TimerPhase.rep:
            if (activeExercise.type == ExerciseType.manual) {
              phaseText = 'set ${progress.currentSet} of $effectiveSets';
            } else {
              phaseText = 'active';
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
          case TimerPhase.overtime:
            phaseText = 'overtime';
            phaseTextStyle = context.h2.copyWith(
              color: context.colorScheme.secondary,
            );
        }

        // Reps display text. Fixed-duration exercises show only the target
        // (reps is informational — the user does as many as they can in the
        // active time, there's no per-rep counter). Other types show
        // current/target. '-/-' when no target is set.
        final String repsText;
        if (activeExercise.reps == null) {
          repsText = '-/-   reps';
        } else if (activeExercise.type == ExerciseType.fixedDuration) {
          repsText = '${activeExercise.reps}   reps';
        } else {
          repsText = '${progress.currentRep} / ${activeExercise.reps}   reps';
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
                      if (isComplete)
                        Center(
                          child: Text(
                            'Workout complete',
                            style: context.h1.copyWith(
                              color: context.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      else
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
                              if (() {
                                final ss = supersetForExercise(
                                  activeWorkout,
                                  activeExercise.id,
                                );
                                return ss != null;
                              }())
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: () {
                                        final ss =
                                            supersetForExercise(
                                              activeWorkout,
                                              activeExercise.id,
                                            )!;
                                        final idx = activeWorkout.supersets
                                            .indexWhere((s) => s.id == ss.id);
                                        return idx >= 0
                                            ? supersetColorForIndex(idx)
                                            : supersetColor(ss.id);
                                      }(),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
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
                  child: isComplete
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 12.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Edit stays available so the user can add
                              // exercises. There is no current exercise, so go
                              // straight to the session editor (no per-exercise
                              // modal).
                              _RoundedBox(
                                width: 50,
                                borderColor: context.colorScheme.onPrimary,
                                child: IconButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => NewSessionScreen(
                                          mode: NewSessionScreenMode.editActive,
                                          session:
                                              sessionStateData.activeSession!,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: Icon(
                                    Icons.edit,
                                    color: context.colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                              SizedBox(width: 24),
                            ],
                          ),
                        )
                      : Column(
                    children: [
                      Center(child: Text(phaseText, style: phaseTextStyle)),
                      // ── Timer or manual-advance button ──────────
                      if (isManualRep)
                        _ManualAdvanceButton(
                          isLastSet: progress.currentSet >= effectiveSets,
                          onPressed: () => sessionStateData.advanceManually(),
                          color: context.colorScheme.onPrimary,
                        )
                      else
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable:
                                    sessionStateData.timerDisplayNotifier,
                                builder: (context, displayValue, _) {
                                  return Text(
                                    sessionStateData.phase ==
                                            TimerPhase.overtime
                                        ? formatDuration(displayValue)
                                        : formatCountdown(displayValue),
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
                                        } else if (sessionStateData.phase ==
                                            TimerPhase.overtime) {
                                          return context.colorScheme.secondary;
                                        } else if ((sessionStateData.phase ==
                                                    TimerPhase.repRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.setRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.supersetRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.exerciseRest) &&
                                            displayValue <
                                                Duration(seconds: 10)) {
                                          return context.colorScheme.secondary;
                                        } else {
                                          return context.colorScheme.onPrimary;
                                        }
                                      }(),
                                    ),
                                    textScaler: TextScaler.linear(2.5),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              right: 20,
                              child: _PauseResumeOvertimeButton(
                                sessionStateData: sessionStateData,
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
                            // REPS
                            _RoundedBox(
                              width: 150,
                              borderColor: context.colorScheme.onPrimary,
                              child: Text(
                                repsText,
                                style: context.titleLarge.copyWith(
                                  color: context.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            // LOAD
                            _RoundedBox(
                              width: 180,
                              borderColor: context.colorScheme.onPrimary,
                              child: Text(
                                'Load: ${activeExercise.load.toString()} kg',
                                style: context.titleLarge.copyWith(
                                  color: context.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
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
                            // MINUS
                            if (sessionStateData.phase !=
                                TimerPhase.exerciseRest)
                              _RoundedBox(
                                width: 50,
                                borderColor:
                                    sessionStateData.phase ==
                                            TimerPhase.overtime
                                        ? context.colorScheme.onSurface
                                            .withValues(alpha: 0.38)
                                        : context.colorScheme.onPrimary,
                                child: IconButton(
                                  onPressed:
                                      sessionStateData.phase ==
                                              TimerPhase.overtime
                                          ? null
                                          : () {
                                            sessionStateData.jumpToSet(
                                              progress.currentSet - 1,
                                            );
                                          },
                                  icon: Icon(
                                    Icons.remove_rounded,
                                    color:
                                        sessionStateData.phase ==
                                                TimerPhase.overtime
                                            ? context.colorScheme.onSurface
                                                .withValues(alpha: 0.38)
                                            : context.colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            SizedBox(width: 8),
                            // SETS
                            _RoundedBox(
                              width: 150,
                              borderColor: context.colorScheme.onPrimary,
                              child: Text(
                                '${progress.currentSet} / $effectiveSets   sets',
                                style: context.titleLarge.copyWith(
                                  color: context.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            // PLUS
                            if (sessionStateData.phase !=
                                TimerPhase.exerciseRest)
                              _RoundedBox(
                                width: 50,
                                borderColor:
                                    sessionStateData.phase ==
                                            TimerPhase.overtime
                                        ? context.colorScheme.onSurface
                                            .withValues(alpha: 0.38)
                                        : context.colorScheme.onPrimary,
                                child: IconButton(
                                  onPressed:
                                      sessionStateData.phase ==
                                              TimerPhase.overtime
                                          ? null
                                          : () {
                                            sessionStateData.jumpToSet(
                                              progress.currentSet + 1,
                                            );
                                          },
                                  icon: Icon(
                                    Icons.add_rounded,
                                    color:
                                        sessionStateData.phase ==
                                                TimerPhase.overtime
                                            ? context.colorScheme.onSurface
                                                .withValues(alpha: 0.38)
                                            : context.colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            Spacer(),
                            //EDIT
                            _RoundedBox(
                              width: 50,
                              borderColor:
                                  sessionStateData.phase == TimerPhase.overtime
                                      ? context.colorScheme.onSurface
                                          .withValues(alpha: 0.38)
                                      : context.colorScheme.onPrimary,
                              child: IconButton(
                                onPressed:
                                    sessionStateData.phase ==
                                            TimerPhase.overtime
                                        ? null
                                        : () {
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
                                  color:
                                      sessionStateData.phase ==
                                              TimerPhase.overtime
                                          ? context.colorScheme.onSurface
                                              .withValues(alpha: 0.38)
                                          : context.colorScheme.onPrimary,
                                  size: 24,
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
                    context.read<SessionStateProvider>().reset();
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
    // Only resume on close if the timer was running when we opened the sheet.
    // If the user had already paused manually, don't resume for them.
    final wasAlreadyPaused = sessionStateData.isPaused;
    sessionStateData.pause();

    // For superset members, the sets value displayed/edited in the dialog
    // is the parent superset's supersetSets, not exercise.sets. The save
    // path below routes back via updateActiveSupersetSets.
    final activeWorkout =
        sessionStateData.activeSession?.workouts[workoutIndex];
    final supersetMembership =
        activeWorkout != null
            ? supersetForExercise(activeWorkout, activeExercise.id)
            : null;
    final initialSets =
        activeWorkout != null
            ? setsForExerciseInWorkout(activeWorkout, activeExercise)
            : activeExercise.sets;

    // Local state — initialized once when sheet opens, applied to provider on save.
    int localSets = initialSets;
    int? localReps = activeExercise.reps;
    bool localRepsEnabled = activeExercise.reps != null;
    int localTimeBetweenSets = activeExercise.timeBetweenSets;
    int localTimePerRep = activeExercise.timePerRep;
    int localTimeBetweenReps = activeExercise.timeBetweenReps;
    int localActiveTime = activeExercise.activeTime;
    String localLoadUnit = activeExercise.loadUnit ?? 'kg';
    bool localRpeEnabled = activeExercise.rpe != null;
    int localRpe = activeExercise.rpe ?? 5;
    final loadController = TextEditingController(
      text: activeExercise.load > 0 ? activeExercise.load.toString() : '',
    );
    final notesController = TextEditingController(
      text: activeExercise.notes ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext modalContext) {
        // Captured so the anchor-deleted listener can pop this modal from
        // outside when its target exercise is removed mid-session.
        _editModalContext = modalContext;
        // Resume is handled via .then() below — covers save, dismiss, and drag-close.
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyAndClose() {
              // For superset members, the sets edit goes to supersetSets so
              // every member of the group reflects the change. Other fields
              // (reps, load, etc.) stay on the exercise. exercise.sets is
              // preserved unchanged so removing the exercise from the
              // superset later restores its original set count.
              final exerciseEditedSets =
                  supersetMembership != null ? activeExercise.sets : localSets;
              if (supersetMembership != null && localSets != initialSets) {
                sessionStateData.updateActiveSupersetSets(
                  workoutId: activeWorkout!.id,
                  exerciseId: activeExercise.id,
                  newSupersetSets: localSets,
                );
              }
              // Apply all local edits to the live session copy via the provider.
              // Uses copyWith (not deepCopy) — keeps the same IDs, only replaces fields.
              // Target by ID, not index: a mid-session structural edit may have
              // shifted positions while the modal was open. No-op if deleted.
              sessionStateData.updateActiveExercise(
                activeWorkout!.id,
                activeExercise.id,
                activeExercise.copyWith(
                  sets: exerciseEditedSets,
                  reps: Nullable(localRepsEnabled ? localReps : null),
                  timeBetweenSets: localTimeBetweenSets,
                  timePerRep: localTimePerRep,
                  timeBetweenReps: localTimeBetweenReps,
                  activeTime: localActiveTime,
                  load: (double.tryParse(loadController.text.trim()) ??
                          activeExercise.load)
                      .clamp(0, FieldLimits.loadLimit.toDouble()),
                  loadUnit: Nullable(localLoadUnit),
                  rpe: Nullable(localRpeEnabled ? localRpe.clamp(1, 10) : null),
                  notes: Nullable(
                    notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                  ),
                ),
              );
              Navigator.pop(context);
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Edit Exercise', style: context.h3),
                          ElevatedButton(
                            onPressed: applyAndClose,
                            child: Text('Save'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    // Scrollable content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),

                        children: [
                          OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NewSessionScreen(
                                    mode: NewSessionScreenMode.editActive,
                                    session: sessionStateData.activeSession!,
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor:
                                  context.colorScheme.surfaceBright,
                              side: BorderSide(
                                color: context.colorScheme.primary,
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                "Edit this session's workouts and exercises.",
                                style: context.titleMedium.copyWith(
                                  color: context.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ── Exercise info (read-only) ──────────────
                          _SessionEditSectionHeader(title: 'Exercise'),
                          const SizedBox(height: 8),
                          _SessionEditSectionCard(
                            children: [
                              LabelBadge(labelKey: activeExercise.label),
                              const SizedBox(height: 4),
                              Text(activeExercise.title, style: context.h3),
                              if (activeExercise.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  activeExercise.description,
                                  style: context.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Training ───────────────────────────────
                          _SessionEditSectionHeader(title: 'Training'),
                          const SizedBox(height: 8),
                          _SessionEditSectionCard(
                            children: [
                              // Sets
                              _SessionEditCounterRow(
                                label: 'Sets',
                                value: localSets,
                                minimum: 1,
                                maximum: FieldLimits.setLimit,
                                onDecrement:
                                    () => setDialogState(() => localSets--),
                                onIncrement:
                                    () => setDialogState(() => localSets++),
                              ),
                              const _SessionEditDivider(),

                              // Type-specific timing + reps
                              if (activeExercise.type ==
                                  ExerciseType.timedReps) ...[
                                _SessionEditCounterRow(
                                  label: 'Reps',
                                  value: localReps ?? 10,
                                  minimum: 1,
                                  maximum: FieldLimits.repLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () => localReps = (localReps ?? 10) - 1,
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () => localReps = (localReps ?? 10) + 1,
                                      ),
                                ),
                                const _SessionEditDivider(),
                                _SessionEditCounterRow(
                                  label: 'Rest between sets',
                                  value: localTimeBetweenSets,
                                  minimum: 0,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets - 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets + 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                _SessionEditCounterRow(
                                  label: 'Time per rep',
                                  value: localTimePerRep,
                                  minimum: 0,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () => localTimePerRep--,
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localTimePerRep =
                                                (localTimePerRep + 1).clamp(
                                                  0,
                                                  FieldLimits.timeLimit,
                                                ),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                _SessionEditCounterRow(
                                  label: 'Rest between reps',
                                  value: localTimeBetweenReps,
                                  minimum: 0,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () => localTimeBetweenReps--,
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenReps =
                                                (localTimeBetweenReps + 1)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                ),
                              ] else if (activeExercise.type ==
                                  ExerciseType.fixedDuration) ...[
                                _SessionEditCounterRow(
                                  label: 'Active time (s)',
                                  value: localActiveTime,
                                  minimum: 5,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localActiveTime =
                                                (localActiveTime - 5).clamp(
                                                  5,
                                                  FieldLimits.timeLimit,
                                                ),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localActiveTime =
                                                (localActiveTime + 5).clamp(
                                                  5,
                                                  FieldLimits.timeLimit,
                                                ),
                                      ),
                                ),
                                const _SessionEditDivider(),
                                _SessionEditCounterRow(
                                  label: 'Rest between sets',
                                  value: localTimeBetweenSets,
                                  minimum: 0,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets - 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets + 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                ),
                                const _SessionEditDivider(),
                                _SessionEditOptionalRepsRow(
                                  enabled: localRepsEnabled,
                                  reps: localReps ?? 5,
                                  maximum: FieldLimits.repLimit,
                                  onToggle:
                                      (enabled) => setDialogState(() {
                                        localRepsEnabled = enabled;
                                        if (enabled) localReps ??= 5;
                                      }),
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localReps = ((localReps ?? 5) - 1)
                                                .clamp(1, FieldLimits.repLimit),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localReps = ((localReps ?? 5) + 1)
                                                .clamp(1, FieldLimits.repLimit),
                                      ),
                                ),
                              ] else ...[
                                // manual
                                _SessionEditCounterRow(
                                  label: 'Rest between sets',
                                  value: localTimeBetweenSets,
                                  minimum: 0,
                                  maximum: FieldLimits.timeLimit,
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets - 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localTimeBetweenSets =
                                                (localTimeBetweenSets + 5)
                                                    .clamp(
                                                      0,
                                                      FieldLimits.timeLimit,
                                                    ),
                                      ),
                                ),
                                const _SessionEditDivider(),
                                _SessionEditOptionalRepsRow(
                                  enabled: localRepsEnabled,
                                  reps: localReps ?? 5,
                                  maximum: FieldLimits.repLimit,
                                  onToggle:
                                      (enabled) => setDialogState(() {
                                        localRepsEnabled = enabled;
                                        if (enabled) localReps ??= 5;
                                      }),
                                  onDecrement:
                                      () => setDialogState(
                                        () =>
                                            localReps = ((localReps ?? 5) - 1)
                                                .clamp(1, FieldLimits.repLimit),
                                      ),
                                  onIncrement:
                                      () => setDialogState(
                                        () =>
                                            localReps = ((localReps ?? 5) + 1)
                                                .clamp(1, FieldLimits.repLimit),
                                      ),
                                ),
                              ],
                              const _SessionEditDivider(),

                              // Load
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: loadController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        TextInputFormatter.withFunction(
                                          (oldValue, newValue) =>
                                              newValue.copyWith(
                                                text: newValue.text.replaceAll(
                                                  ',',
                                                  '.',
                                                ),
                                              ),
                                        ),
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'),
                                        ),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Load',
                                        labelStyle: context.bodyMedium,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Wrap(
                                    spacing: 6,
                                    children:
                                        ['kg', 'lbs'].map((unit) {
                                          return ChoiceChip(
                                            label: Text(unit),
                                            selected: localLoadUnit == unit,
                                            onSelected:
                                                (selected) => setDialogState(
                                                  () =>
                                                      localLoadUnit =
                                                          selected
                                                              ? unit
                                                              : localLoadUnit,
                                                ),
                                          );
                                        }).toList(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Details ────────────────────────────────
                          _SessionEditSectionHeader(title: 'Details'),
                          const SizedBox(height: 8),
                          _SessionEditSectionCard(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('RPE', style: context.titleMedium),
                                      Text(
                                        'Rate of Perceived Exertion',
                                        style: context.bodyMedium.copyWith(
                                          color:
                                              context
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    value: localRpeEnabled,
                                    onChanged:
                                        (value) => setDialogState(
                                          () => localRpeEnabled = value,
                                        ),
                                  ),
                                ],
                              ),
                              if (localRpeEnabled) ...[
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _rpeLabel(localRpe),
                                      style: context.bodyMedium.copyWith(
                                        color:
                                            context
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                    ),
                                    IncrementDecrementNumberWidget(
                                      value: localRpe.clamp(1, 10),
                                      minimum: 1,
                                      decrement: () {
                                        if (localRpe > 1) {
                                          setDialogState(() => localRpe--);
                                        }
                                      },
                                      increment: () {
                                        if (localRpe < 10) {
                                          setDialogState(() => localRpe++);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Notes ──────────────────────────────────
                          _SessionEditSectionHeader(title: 'Notes'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: notesController,
                            minLines: 3,
                            maxLines: null,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Notes',
                              labelStyle: context.bodyMedium,
                              hintText: 'Any additional notes...',
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((_) {
      _editModalContext = null;
      if (!wasAlreadyPaused) sessionStateData.resume();
    });
  }

  String _rpeLabel(int rpe) {
    return switch (rpe) {
      1 || 2 => 'Very light',
      3 || 4 => 'Light',
      5 || 6 => 'Moderate',
      7 || 8 => 'Hard',
      9 => 'Very hard',
      _ => 'Maximum',
    };
  }
}

class _PauseResumeOvertimeButton extends StatelessWidget {
  final SessionStateProvider sessionStateData;

  const _PauseResumeOvertimeButton({required this.sessionStateData});

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.pause_rounded;
    Color widgetColor = context.colorScheme.onPrimary;
    VoidCallback onTap = () {
      sessionStateData.pause();
      WakelockPlus.disable();
    };
    VoidCallback onLongPress = () {};

    if (sessionStateData.phase == TimerPhase.setRest ||
        sessionStateData.phase == TimerPhase.exerciseRest ||
        sessionStateData.phase == TimerPhase.getReady) {
      onLongPress = sessionStateData.requestManualOvertime;
    }

    if (sessionStateData.phase == TimerPhase.overtime) {
      icon = Icons.skip_next_rounded;
      widgetColor = context.colorScheme.secondary;
      onTap = sessionStateData.exitOvertime;
    } else if (sessionStateData.isPaused) {
      icon = Icons.play_arrow_rounded;
      onTap = () {
        sessionStateData.resume();
        WakelockPlus.enable();
      };
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _RoundedBox(
        width: 44,
        height: 44,
        shadow: false,
        borderColor: widgetColor,
        child: Icon(icon, color: widgetColor),
      ),
    );
  }
}

// ── Private helper widgets for the edit bottom sheet ────────────────────────

class _SessionEditSectionHeader extends StatelessWidget {
  final String title;
  const _SessionEditSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: context.titleMedium),
    );
  }
}

class _SessionEditSectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SessionEditSectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SessionEditCounterRow extends StatelessWidget {
  final String label;
  final int value;
  final int minimum;
  final int? maximum;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _SessionEditCounterRow({
    required this.label,
    required this.value,
    required this.minimum,
    this.maximum,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.titleMedium),
        IncrementDecrementNumberWidget(
          value: value,
          minimum: minimum,
          maximum: maximum,
          decrement: onDecrement,
          increment: onIncrement,
        ),
      ],
    );
  }
}

class _SessionEditOptionalRepsRow extends StatelessWidget {
  final bool enabled;
  final int reps;
  final int? maximum;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _SessionEditOptionalRepsRow({
    required this.enabled,
    required this.reps,
    this.maximum,
    required this.onToggle,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rep target', style: context.titleMedium),
                Text(
                  'Optional — shown during exercise',
                  style: context.bodyMedium.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Switch(value: enabled, onChanged: onToggle),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 8),
          _SessionEditCounterRow(
            label: 'Reps',
            value: reps,
            minimum: 1,
            maximum: maximum,
            onDecrement: onDecrement,
            onIncrement: onIncrement,
          ),
        ],
      ],
    );
  }
}

class _SessionEditDivider extends StatelessWidget {
  const _SessionEditDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1),
    );
  }
}

/// A styled card used throughout the active session screen.
/// Renders a fixed-size box with the primary color, rounded corners, a border,
/// and an optional medium shadow. The child is automatically centered.
class _RoundedBox extends StatelessWidget {
  const _RoundedBox({
    required this.width,
    required this.child,
    this.height = 50,
    this.shadow = true,
    required this.borderColor,
  });

  final double width;
  final double height;
  final bool shadow;
  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colorScheme.primary,
        boxShadow: shadow ? context.shadowMedium : null,
        borderRadius: BorderRadius.circular(16),
        border: BoxBorder.all(color: borderColor, width: 2),
      ),
      child: Center(child: child),
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
