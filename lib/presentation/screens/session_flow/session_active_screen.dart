import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/presentation/widgets/label_badge.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/utils/timer_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_active_bottom_bar.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ActiveSessionScreen extends StatefulWidget {
  final Session session;

  const ActiveSessionScreen({super.key, required this.session});

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
        // Passes the session to start(), which deep-copies it internally.
        if (!_timerInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Guard again in case the widget unmounted before the callback.
            if (!mounted || _timerInitialized) return;
            sessionStateData.start(widget.session);
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
        Exercise activeExercise =
            activeWorkout.exercises[progress.exerciseIndex];

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
        switch (sessionStateData.phase) {
          case TimerPhase.setRest:
            phaseText = 'rest between sets';
          case TimerPhase.rep:
            if (activeExercise.type == ExerciseType.manual) {
              phaseText =
                  'set ${progress.currentSet} of ${activeExercise.sets}';
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
        }

        // Reps display text: show '-/-' when no rep target is set
        final repsText =
            activeExercise.reps != null
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
                              child: _SessionCard(
                                width: 44,
                                height: 44,
                                shadow: false,
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
                          ],
                        ),
                      SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // REPS
                            _SessionCard(
                              width: 150,
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
                            _SessionCard(
                              width: 180,
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
                              _SessionCard(
                                width: 50,
                                child: IconButton(
                                  onPressed: () {
                                    sessionStateData.jumpToSet(
                                      progress.currentSet - 1,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.remove_rounded,
                                    color: context.colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            SizedBox(width: 8),
                            // SETS
                            _SessionCard(
                              width: 150,
                              child: Text(
                                '${progress.currentSet} / ${activeExercise.sets}   sets',
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
                              _SessionCard(
                                width: 50,
                                child: IconButton(
                                  onPressed: () {
                                    sessionStateData.jumpToSet(
                                      progress.currentSet + 1,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.add_rounded,
                                    color: context.colorScheme.onPrimary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            Spacer(),
                            //EDIT
                            _SessionCard(
                              width: 50,
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
    // Only resume on close if the timer was running when we opened the sheet.
    // If the user had already paused manually, don't resume for them.
    final wasAlreadyPaused = sessionStateData.isPaused;
    sessionStateData.pause();

    // Local state — initialized once when sheet opens, applied to provider on save.
    int localSets = activeExercise.sets;
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
      builder: (BuildContext context) {
        // Resume is handled via .then() below — covers save, dismiss, and drag-close.
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyAndClose() {
              // Apply all local edits to the live session copy via the provider.
              // Uses copyWith (not deepCopy) — keeps the same IDs, only replaces fields.
              sessionStateData.updateActiveExercise(
                workoutIndex,
                exerciseIndex,
                activeExercise.copyWith(
                  sets: localSets,
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
                                        if (localRpe > 1)
                                          {setDialogState(() => localRpe--);}
                                      },
                                      increment: () {
                                        if (localRpe < 10)
                                          {setDialogState(() => localRpe++);}
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
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.width,
    required this.child,
    this.height = 50,
    this.shadow = true,
  });

  final double width;
  final double height;
  final bool shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colorScheme.primary,
        boxShadow: shadow ? context.shadowMedium : null,
        borderRadius: BorderRadius.circular(16),
        border: BoxBorder.all(color: context.colorScheme.onPrimary, width: 2),
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
