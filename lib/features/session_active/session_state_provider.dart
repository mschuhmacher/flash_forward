import 'dart:async';

import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/features/session_active/session_progress.dart';
import 'package:flash_forward/features/session_active/session_state_machine.dart';
import 'package:flash_forward/features/session_active/session_telemetry_recorder.dart';
import 'package:flash_forward/core/settings_provider.dart';
import 'package:flash_forward/features/session_active/sound_dispatcher.dart';
import 'package:flash_forward/features/session_active/audio_beep_player.dart';
import 'package:flash_forward/features/session_active/beep_scheduler.dart';
import 'package:flash_forward/core/superset_utils.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

class SessionStateProvider extends ChangeNotifier {
  /// All below variables and functions pertain to global state management of the sessions.
  /// There is also functionality to keep track of the weeks in a training plan, but that is not utilized right now.
  ///

  int _weekIndex = 0;
  int _sessionIndex = 0;
  int _workoutIndex = 0;
  int _exerciseIndex = 0;

  /// Deep copy of the selected session — created on start() so the preset is never mutated.
  /// All mid-session edits apply to this copy only.
  Session? _activeSession;

  // Timer-related state. These fields are read by the UI and manipulated via
  // the start/pause/resume/reset methods below. The actual session/workout/
  // exercise lists remain the single source of truth in the models.
  SessionProgress _progress = const SessionProgress(
    workoutIndex: 0,
    exerciseIndex: 0,
    currentSet: 1,
    currentRep: 1,
    phase: TimerPhase.getReady,
  );
  // Countdown remaining for the current phase.
  Duration _remaining = Duration.zero;
  // Whether the ticker should decrement. Keeps the periodic timer lightweight.
  bool _isPaused = true;
  // Periodic timer that ticks once per second and advances phases.
  Timer? _ticker;
  // Wall-clock time of the last ticker callback. Used to measure real elapsed
  // time instead of assuming exactly 1 s per tick. Preserved across OS isolate
  // suspension so the next tick can catch up after the screen is locked.
  DateTime? _lastTickAt;
  // Beep timing + scheduling. Holds the injected BeepScheduler / AudioBeepPlayer
  // and decides what to beep and when. Wired via setBeepScheduler/
  // setAudioBeepPlayer.
  final SoundDispatcher _sound = SoundDispatcher();
  // Whether the app is currently in the foreground (screen on, app visible).
  bool _isForegrounded = true;
  // Current sound mode — synced from SettingsProvider at session start.
  SoundMode _soundMode = SoundMode.soundsOnly;
  // How early go/stop beeps fire relative to the actual phase boundary, to
  // compensate for audio latency and cognitive reaction time.
  static const Duration _audioLeadTime = Duration(milliseconds: 300);
  // How early the countdown beep fires. Larger than _audioLeadTime so the
  // 3-2-1 cadence ends before the go beep fires (gap = 3.1 s — i.e. 100 ms
  // between the end of the countdown audio and the go beep). The
  // AudioBeepPlayer bridges this gap with delayed session deactivation so
  // background audio doesn't pop to full volume in between.
  static const Duration _countdownLeadTime = Duration(milliseconds: 400);

  // ─── Timer display notifier ──────────────────────────────────────
  // Publishes the value the timer widget should currently display.
  // Updated on every tick (10 Hz) and on any state change that affects
  // _remaining or _overtimeElapsed. Listeners of this notifier rebuild
  // independently of the provider's notifyListeners() — the rest of the
  // screen does not rebuild when this fires.
  final ValueNotifier<Duration> timerDisplayNotifier = ValueNotifier(
    Duration.zero,
  );

  // ─── Anchor-deleted signal ───────────────────────────────────────
  // Bumped whenever a mid-session edit deletes the anchored exercise and
  // re-anchoring jumps elsewhere. The active screen listens to this to close
  // the open edit-exercise modal, whose target no longer exists. Only ever
  // fires while that modal is open (replaceActiveSession's sole caller).
  final ValueNotifier<int> anchorDeletedSignal = ValueNotifier(0);

  //
  Duration _overtimeElapsed = Duration.zero;
  bool _overtimeWasAutomatic = false;
  bool _restOvertimeOnBackground = false;
  TimerPhase _overtimeSourcePhase = TimerPhase.getReady;

  TimerPhase _rememberCurrentPhaseForPausing = TimerPhase.getReady;

  // Event log + slice/draft bookkeeping for the active session run.
  final SessionTelemetryRecorder _telemetry = SessionTelemetryRecorder();

  int get weekIndex => _weekIndex;
  int get sessionIndex => _sessionIndex;
  int get workoutIndex => _workoutIndex;
  int get exerciseIndex => _exerciseIndex;
  SessionProgress get progress => _progress;
  Duration get remaining => _remaining;
  TimerPhase get phase => _progress.phase;
  bool get isPaused => _isPaused;
  Duration get overtimeElapsed => _overtimeElapsed;

  /// The active session copy. Non-null while a session is running.
  Session? get activeSession => _activeSession;

  void setBeepScheduler(BeepScheduler scheduler) =>
      _sound.setScheduler(scheduler);

  void setAudioBeepPlayer(AudioBeepPlayer player) => _sound.setPlayer(player);

  void setSoundMode(SoundMode mode) {
    _soundMode = mode;
    _rescheduleSound();
  }

  void setRestOvertimeOnBackground(bool value) =>
      _restOvertimeOnBackground = value;

  /// Called by [ActiveSessionScreen] on app lifecycle changes. On going to
  /// background, schedules notifications if the sound mode requires them. On
  /// returning to foreground, cancels pending notifications and reconciles
  /// elapsed time.
  void setForegrounded(bool foregrounded) {
    if (_isForegrounded == foregrounded) return;
    _isForegrounded = foregrounded;
    if (foregrounded) {
      _sound.cancelAll();
      reconcileAfterBackground();
    } else {
      _rescheduleSound();
    }
  }

  Future<bool> canScheduleExactAlarms() => _sound.canScheduleExactAlarms();

  Future<void> requestExactAlarmPermission() =>
      _sound.requestExactAlarmPermission();

  void incrementWeekIndex() {
    _weekIndex++;
    notifyListeners();
  }

  void decrementWeekIndex() {
    _weekIndex--;
    notifyListeners();
  }

  void incrementSessionIndex() {
    _sessionIndex++;
    notifyListeners();
  }

  void decrementSessionIndex() {
    _sessionIndex--;
    notifyListeners();
  }

  void setSessionIndex(int index) {
    _sessionIndex = index;
    notifyListeners();
  }

  void incrementWorkoutIndex() {
    _workoutIndex++;
    notifyListeners();
  }

  void decrementWorkoutIndex() {
    _workoutIndex--;
    notifyListeners();
  }

  void setWorkoutIndex(int index) {
    _workoutIndex = index;
    notifyListeners();
  }

  /// Jump to a specific workout and reset exercise/set/rep to the first items.
  /// Keeps the timer in sync with navigation actions in the UI.
  void jumpToWorkout(int index) {
    if (_activeSession == null) return;
    if (index < 0 || index >= _activeSession!.workouts.length) return;
    _telemetry.discardDrafts();
    _workoutIndex = index;
    _progress = SessionProgress(
      workoutIndex: index,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.rep,
    );
    // workoutComplete is a sentinel meaning "no prior phase" — drafts were
    // already discarded above, so the dispatcher has nothing to close.
    _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
    _remaining = SessionStateMachine.getDurationForPhase(
      _progress,
      _activeSession,
    );
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  /// Jump to a specific exercise and reset set/rep to the first items.
  /// Keeps the timer in sync with navigation actions in the UI.
  void jumpToExercise(int index) {
    if (_activeSession == null) return;
    _telemetry.discardDrafts();
    // Return statement (is this needed?)
    if (index < -1) {
      return;
    }
    // When at first exercise of second+ workout, go back to last exercise of previous workout
    else if (index == -1 && _workoutIndex > 0) {
      _workoutIndex--;
      _exerciseIndex =
          _activeSession!.workouts[_workoutIndex].exercises.length - 1;
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.getReady,
      );
      _onPhaseTransition(
        TimerPhase.workoutComplete,
        _progress.phase,
        _progress,
      );
      _remaining = SessionStateMachine.getDurationForPhase(
        _progress,
        _activeSession,
      );
      _rescheduleSound();
      _syncTimerDisplay();
      notifyListeners();
    }
    // When within range of list of exercises of workout, go to previous or next
    else if (index >= 0 &&
        index < _activeSession!.workouts[_workoutIndex].exercises.length) {
      _exerciseIndex = index;
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.getReady,
      );
      _onPhaseTransition(
        TimerPhase.workoutComplete,
        _progress.phase,
        _progress,
      );
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
      _rescheduleSound();
      _syncTimerDisplay();
      notifyListeners();
    }
    // When at the last exercise of a workout and not the final exercise of session, go to first exercise of next workout
    else if (index ==
            _activeSession!.workouts[_workoutIndex].exercises.length &&
        _workoutIndex + 1 < _activeSession!.workouts.length) {
      _workoutIndex++;
      _exerciseIndex = 0;
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.getReady,
      );
      _onPhaseTransition(
        TimerPhase.workoutComplete,
        _progress.phase,
        _progress,
      );
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
      _rescheduleSound();
      _syncTimerDisplay();
      notifyListeners();
    }
  }

  /// The next *exercise the user will physically perform* from [_progress],
  /// or null on the final exercise of the session.
  ///
  /// "Next" means the next move the user makes, which differs by context:
  /// - Solo exercise → the next exercise in the workout (sets are not stops;
  ///   they're the same exercise repeated). Always lands at currentSet 1.
  /// - Superset member → the next member they actually do, which mirrors
  ///   physical performance order: next member in the same round, or wrap
  ///   to group start with set+1 on the last member of a round, or exit the
  ///   group on the last round. The set counter is preserved/bumped to
  ///   reflect the round, not reset.
  ///
  /// Always lands at `TimerPhase.rep` (or `TimerPhase.getReady` for the very
  /// first exercise of a later workout, matching `jumpToExercise`).
  SessionProgress? get nextStop => SessionStateMachine.calculateNextStop(_progress, _activeSession!);

  /// Symmetric counterpart to [nextStop]. Null at the very first rep of the
  /// session.
  SessionProgress? get previousStop => SessionStateMachine.calculatePreviousStop(_progress, _activeSession!);

  /// Jumps to [nextStop] if non-null. No-op otherwise (final rep of session).
  /// Discards any in-flight set draft. Sets the timer to the new phase's
  /// duration so the UI is consistent after the jump.
  void jumpToNext() {
    final target = nextStop;
    if (target == null) return;
    _applyJumpTarget(target);
  }

  /// Symmetric counterpart to [jumpToNext].
  void jumpToPrevious() {
    final target = previousStop;
    if (target == null) return;
    _applyJumpTarget(target);
  }

  void _applyJumpTarget(SessionProgress target) {
    if (_activeSession == null) return;
    _telemetry.discardDrafts();
    _workoutIndex = target.workoutIndex;
    _exerciseIndex = target.exerciseIndex;
    _progress = target;
    _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
    _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  void jumpToSet(int index) {
    _telemetry.discardDrafts();
    if (index < 0) {
      return;
    }
    if (_activeSession == null) return;
    final workout = _activeSession!.workouts[_workoutIndex];
    final exercise = workout.exercises[_exerciseIndex];
    final effectiveSets = setsForExerciseInWorkout(workout, exercise);
    if (index == 0) {
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
      _onPhaseTransition(
        TimerPhase.workoutComplete,
        _progress.phase,
        _progress,
      );
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
      _rescheduleSound();
      _syncTimerDisplay();
      notifyListeners();
    } else if (index > 0 && index <= effectiveSets) {
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: index,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
      _onPhaseTransition(
        TimerPhase.workoutComplete,
        _progress.phase,
        _progress,
      );
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
      _rescheduleSound();
      _syncTimerDisplay();
      notifyListeners();
    } else if (index > effectiveSets) {
      return;
    }
  }

  /// Replaces the active session structure with [edited] and re-anchors
  /// progress to the user's current exercise by id. If the current exercise
  /// was deleted, advances to the next available stop. No-op if no session
  /// is active.
  void replaceActiveSession(Session edited) {
    if (_activeSession == null) return;

    // Capture anchor ids before replacing.
    final anchorWorkoutId = _activeSession!.workouts[_progress.workoutIndex].id;
    final anchorExerciseId =
        _activeSession!
            .workouts[_progress.workoutIndex]
            .exercises[_progress.exerciseIndex]
            .id;

    _activeSession = edited;

    // Locate anchor in edited session.
    final newWorkoutIndex = edited.workouts.indexWhere(
      (w) => w.id == anchorWorkoutId,
    );
    final newExerciseIndex =
        newWorkoutIndex >= 0
            ? edited.workouts[newWorkoutIndex].exercises.indexWhere(
              (e) => e.id == anchorExerciseId,
            )
            : -1;

    if (newWorkoutIndex >= 0 && newExerciseIndex >= 0) {
      // Anchor survived — re-anchor and clamp.
      _workoutIndex = newWorkoutIndex;
      _exerciseIndex = newExerciseIndex;
      final workout = edited.workouts[newWorkoutIndex];
      final exercise = workout.exercises[newExerciseIndex];
      final effectiveSets = setsForExerciseInWorkout(workout, exercise);
      final clampedSet = _progress.currentSet.clamp(1, effectiveSets);
      final clampedRep =
          exercise.reps != null
              ? _progress.currentRep.clamp(1, exercise.reps!)
              : _progress.currentRep;
      _progress = SessionProgress(
        workoutIndex: newWorkoutIndex,
        exerciseIndex: newExerciseIndex,
        currentSet: clampedSet,
        currentRep: clampedRep,
        phase: TimerPhase.paused,
      );
      // Rewrite open draft indices to match new position.
      _telemetry.updateActiveDraftIndices(newWorkoutIndex, newExerciseIndex);
    } else {
      _handleAnchorDeleted();
    }

    if (!_isPaused) {
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    }
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  void _handleAnchorDeleted() {
    _telemetry.discardDrafts();

    // Clamp old indices so firstStopAtOrAfter doesn't go out of bounds.
    final clampedWorkoutIndex = _progress.workoutIndex.clamp(
      0,
      _activeSession!.workouts.length - 1,
    );
    final clampedExerciseIndex = _progress.exerciseIndex.clamp(
      0,
      _activeSession!.workouts[clampedWorkoutIndex].exercises.length,
    );

    final nextStop = SessionStateMachine.firstStopAtOrAfter(
      clampedWorkoutIndex,
      clampedExerciseIndex,
      _activeSession!,
    );

    if (nextStop != null) {
      _workoutIndex = nextStop.workoutIndex;
      _exerciseIndex = nextStop.exerciseIndex;
      _progress = SessionProgress(
        workoutIndex: nextStop.workoutIndex,
        exerciseIndex: nextStop.exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.paused,
      );
      _rememberCurrentPhaseForPausing = TimerPhase.getReady;
      // Prime the countdown for the phase we'll resume into. The paused-guard
      // on the _remaining recompute in replaceActiveSession would otherwise
      // leave a stale duration, so set it explicitly here.
      _remaining = SessionStateMachine.getDurationForPhase(
        _progress.copyWith(phase: TimerPhase.getReady),
        _activeSession,
      );
    } else {
      // Nothing left after current position — user removed the rest of the
      // session. Treat as session complete.
      //
      // Clamp the indices to a still-valid slot: the old position points at a
      // now-deleted exercise (or workout). The active screen renders a
      // "Workout complete" state instead of the exercise card, but it still
      // reads workouts[workoutIndex] for the workout-name strip, so the
      // workout index in particular must stay in range.
      final safeWorkoutIndex = clampedWorkoutIndex.clamp(
        0,
        _activeSession!.workouts.length - 1,
      );
      final safeExerciseIndex = _progress.exerciseIndex.clamp(
        0,
        _activeSession!.workouts[safeWorkoutIndex].exercises.length - 1,
      );
      _workoutIndex = safeWorkoutIndex;
      _exerciseIndex = safeExerciseIndex;
      _onPhaseTransition(
        _progress.phase,
        TimerPhase.workoutComplete,
        _progress,
      );
      _progress = _progress.copyWith(
        workoutIndex: safeWorkoutIndex,
        exerciseIndex: safeExerciseIndex,
        phase: TimerPhase.workoutComplete,
      );
      // The modal closing triggers resume() (when not pre-paused), which
      // restores _rememberCurrentPhaseForPausing onto _progress. Without this
      // it would hold the deleted exercise's old phase (e.g. rep) and flip us
      // off workoutComplete back onto the last surviving exercise.
      _rememberCurrentPhaseForPausing = TimerPhase.workoutComplete;
      _remaining = Duration.zero;
      _sound.cancelAll();
      _lastTickAt = null;
    }

    // The modal was editing the now-deleted anchor exercise; tell the active
    // screen to close it. Fires in both branches — the target is gone either way.
    anchorDeletedSignal.value++;
  }

  /// Update a single exercise in the active session copy (e.g. mid-session load/sets edit).
  /// Uses copyWith so all fields remain immutable — the preset is never touched.
  ///
  /// Targets the workout and exercise by ID rather than index: a mid-session
  /// structural edit (add/reorder) may have shifted positions between the
  /// modal opening and Save. No-op if either ID is no longer present (e.g. the
  /// exercise was deleted in the editor) — the in-modal edits are discarded.
  void updateActiveExercise(
    String workoutId,
    String exerciseId,
    Exercise updated,
  ) {
    if (_activeSession == null) return;
    final workoutIndex = _activeSession!.workouts.indexWhere(
      (w) => w.id == workoutId,
    );
    if (workoutIndex == -1) return;
    final workout = _activeSession!.workouts[workoutIndex];
    final exerciseIndex = workout.exercises.indexWhere(
      (e) => e.id == exerciseId,
    );
    if (exerciseIndex == -1) return;
    final updatedExercises = List<Exercise>.from(workout.exercises);
    updatedExercises[exerciseIndex] = updated;
    final updatedWorkout = workout.copyWith(exercises: updatedExercises);
    final updatedWorkouts = List<Workout>.from(_activeSession!.workouts);
    updatedWorkouts[workoutIndex] = updatedWorkout;
    _activeSession = _activeSession!.copyWith(workouts: updatedWorkouts);

    // Clamp progress if the user reduced sets/reps below current position.
    // For superset members, sets clamp uses the superset's effective sets.
    final effectiveSets = setsForExerciseInWorkout(updatedWorkout, updated);
    final clampedSet = _progress.currentSet.clamp(1, effectiveSets);
    final clampedRep =
        updated.reps != null
            ? _progress.currentRep.clamp(1, updated.reps!)
            : _progress.currentRep;
    if (clampedSet != _progress.currentSet ||
        clampedRep != _progress.currentRep) {
      _progress = _progress.copyWith(
        currentSet: clampedSet,
        currentRep: clampedRep,
      );
    }

    notifyListeners();
  }

  /// Updates `supersetSets` on the superset that contains [exerciseId] in
  /// the active session's workout identified by [workoutId]. No-op if the
  /// workout is gone or the exercise is not a superset member. Clamps
  /// `currentSet` to the new value when applicable.
  ///
  /// Targets the workout by ID (not index) so a mid-session structural edit
  /// that shifted positions doesn't write to the wrong workout.
  ///
  /// Mid-session sets edits on a superset member route here instead of
  /// `updateActiveExercise` for the sets field — all members of the same
  /// superset share `supersetSets`, so a single edit propagates to all of
  /// them via the existing read path (`setsForExerciseInWorkout`).
  void updateActiveSupersetSets({
    required String workoutId,
    required String exerciseId,
    required int newSupersetSets,
  }) {
    if (_activeSession == null) return;
    final workoutIndex = _activeSession!.workouts.indexWhere(
      (w) => w.id == workoutId,
    );
    if (workoutIndex == -1) return;
    final workout = _activeSession!.workouts[workoutIndex];
    final supersetIndex = workout.supersets.indexWhere(
      (superset) => superset.exerciseIds.contains(exerciseId),
    );
    if (supersetIndex == -1) return;
    final updated = workout.supersets[supersetIndex].copyWith(
      supersetSets: newSupersetSets,
    );
    final newSupersets = List<SupersetConfig>.from(workout.supersets);
    newSupersets[supersetIndex] = updated;
    final updatedWorkout = workout.copyWith(supersets: newSupersets);
    final updatedWorkouts = List<Workout>.from(_activeSession!.workouts);
    updatedWorkouts[workoutIndex] = updatedWorkout;
    _activeSession = _activeSession!.copyWith(workouts: updatedWorkouts);

    if (_progress.workoutIndex == workoutIndex) {
      final activeExercise = updatedWorkout.exercises[_progress.exerciseIndex];
      final effectiveSets = setsForExerciseInWorkout(
        updatedWorkout,
        activeExercise,
      );
      final clamped = _progress.currentSet.clamp(1, effectiveSets);
      if (clamped != _progress.currentSet) {
        _progress = _progress.copyWith(currentSet: clamped);
      }
    }
    notifyListeners();
  }

  // -------- Timer controls (first pass) --------
  // These methods expose a minimal API for the UI to drive the timer. They
  // rely on the session/workout/exercise models for timing data instead of
  // duplicating durations inside the provider.

  void start(Session session) {
    // Clear
    _telemetry.clear();

    // Deep copy the preset so mid-session edits never affect it
    _activeSession = session.deepCopy();
    _workoutIndex = 0;
    _exerciseIndex = 0;
    _progress = const SessionProgress(
      workoutIndex: 0,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.getReady,
    );

    _onPhaseTransition(
      TimerPhase.workoutComplete,
      _progress.phase, //getReady
      _progress,
    );
    _telemetry.beginPhase(); // Start time for the first slice

    _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    _isPaused = false;
    _startTicker();
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  void pause() {
    if (_isPaused) {
      return; // idempotent — second call would corrupt _rememberCurrentPhaseForPausing
    }

    _telemetry.attributeSliceOnExit(_progress.phase);

    _onPhaseTransition(_progress.phase, TimerPhase.paused, _progress);

    _isPaused = true;
    _lastTickAt = null;
    _rememberCurrentPhaseForPausing = _progress.phase;
    _progress = _progress.copyWith(phase: TimerPhase.paused);
    _rescheduleSound(); // cancels because _isPaused is true
    notifyListeners();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;

    SessionProgress targetProgress = _progress.copyWith(
      phase: _rememberCurrentPhaseForPausing,
    );
    _onPhaseTransition(TimerPhase.paused, targetProgress.phase, targetProgress);
    _progress = targetProgress;
    _startTicker();
    _rescheduleSound();
    notifyListeners();
  }

  /// Closes any open drafts, computes telemetry, and returns the active session
  /// populated with event logs and a summary. Does not reset state — call
  /// [reset] separately after persisting.
  Session finalizeSession() {
    _telemetry.closeSet(repsCompleted: _progress.currentRep);
    _telemetry.closeRest();
    final summary = _telemetry.computeSummary();
    return _activeSession!.copyWith(
      setEvents: _telemetry.setEvents,
      restEvents: _telemetry.restEvents,
      summary: summary,
    );
  }

  void reset() {
    _ticker?.cancel();
    _lastTickAt = null;
    _sound.cancelAll();
    _activeSession = null;
    _telemetry.clear();
    _progress = const SessionProgress(
      workoutIndex: 0,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.workoutComplete,
    );
    _remaining = Duration.zero;
    _isPaused = true;
    _syncTimerDisplay();
    notifyListeners();
  }

  /// Called when the app returns to foreground. Catches any time gap the
  /// ticker missed while the isolate was suspended, then reschedules beeps
  /// for the session's remaining phases.
  void reconcileAfterBackground() {
    if (_isPaused || _activeSession == null || _lastTickAt == null) return;
    final now = DateTime.now();

    if (_progress.phase == TimerPhase.overtime) {
      _overtimeElapsed += now.difference(_lastTickAt!);
      _lastTickAt = now;
      if (_overtimeWasAutomatic) {
        exitOvertime();
        return;
      } else {
        _syncTimerDisplay();
        notifyListeners();
        return;
      }
    }
    final Duration gap = now.difference(_lastTickAt!);
    if (_restOvertimeOnBackground &&
        (_progress.phase == TimerPhase.setRest ||
            _progress.phase == TimerPhase.exerciseRest ||
            _progress.phase == TimerPhase.getReady) &&
        (gap >= _remaining)) {
      Duration overshoot = gap - _remaining;
      _remaining = Duration.zero;
      _lastTickAt = now;
      _enterOvertime(automatic: true);
      _overtimeElapsed = overshoot;
      exitOvertime();
      return;
    }

    _lastTickAt = now;
    _advanceByElapsed(gap);
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  /// For manual-type exercises: advance to the next set (with rest) or to
  /// exerciseRest when all sets are done. For superset members, the next
  /// member's rep starts after a `supersetRest`. No-op for other exercise types.
  void advanceManually() {
    if (_activeSession == null) return;
    final workout = _activeSession!.workouts[_progress.workoutIndex];
    final exercise = workout.exercises[_progress.exerciseIndex];
    if (exercise.type != ExerciseType.manual) return;
    if (_progress.phase != TimerPhase.rep) return;

    final effectiveSets = setsForExerciseInWorkout(workout, exercise);

    if (hasNextInSuperset(workout, _progress.exerciseIndex)) {
      final ss = supersetForExercise(workout, exercise.id);
      final next = SessionProgress(
        workoutIndex: _progress.workoutIndex,
        exerciseIndex: _progress.exerciseIndex + 1,
        currentSet: _progress.currentSet,
        currentRep: 1,
        phase: TimerPhase.supersetRest,
      );
      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
      _remaining = Duration(seconds: ss?.restSeconds ?? 15);
    } else if (_progress.currentSet < effectiveSets) {
      // Last member of a superset (or solo exercise) with more sets to
      // go: route through SessionStateMachine.enterPostSetRest so superset
      // members enter exerciseRest pre-advanced to the group's first member.
      final next = SessionStateMachine.enterPostSetRest(_progress, workout, _activeSession!);
      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    } else {
      final next = _progress.copyWith(phase: TimerPhase.exerciseRest);
      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
      _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    }
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  /// Updates [timerDisplayNotifier] to reflect the current displayable
  /// timer value — `_overtimeElapsed` during overtime, `_remaining`
  /// otherwise. Call wherever `_remaining` or `_overtimeElapsed` is
  /// mutated, or whenever the phase transitions between overtime and
  /// normal.
  ///
  /// IMPORTANT: must be called AFTER `_progress` is updated, since it
  /// reads `_progress.phase` to decide which value to publish.
  void _syncTimerDisplay() {
    timerDisplayNotifier.value =
        _progress.phase == TimerPhase.overtime ? _overtimeElapsed : _remaining;
  }

  void _startTicker() {
    _ticker?.cancel();
    // Stamp the current wall-clock time so the first tick can measure a real
    // elapsed delta.
    _lastTickAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_progress.phase == TimerPhase.overtime) {
        final now = DateTime.now();
        _overtimeElapsed += now.difference(_lastTickAt!);
        _lastTickAt = now;
        // High-frequency display update only — do NOT notifyListeners() here.
        // The screen-wide Consumer would otherwise rebuild 10x per second.
        _syncTimerDisplay();
        return;
      }

      final now = DateTime.now();
      // Use actual wall-clock elapsed instead of a fixed 1 s decrement.
      // When the OS suspends the isolate (screen locked), the ticker stops
      // firing but _lastTickAt is preserved. The next tick after the isolate
      // resumes will have a large elapsed value (e.g. 45 s), which
      // _advanceByElapsed handles by fast-forwarding through however many
      // phases elapsed during that gap.
      final prevProgress = _progress;
      final previousRemaining = _remaining;

      _advanceByElapsed(now.difference(_lastTickAt!));
      _lastTickAt = now;

      // In-app beeps for this tick boundary. classifyTickEdge can return both
      // a countdown and a go beep on the same tick (overlapping windows after
      // an isolate suspension); the provider plays each in order.
      final playInApp = SoundDispatcher.shouldPlayInApp(
        isForegrounded: _isForegrounded,
        mode: _soundMode,
      );
      final beeps = SoundDispatcher.classifyTickEdge(
        prevPhase: prevProgress.phase,
        newPhase: _progress.phase,
        prevRemaining: previousRemaining,
        newRemaining: _remaining,
        playInApp: playInApp,
        audioLeadTime: _audioLeadTime,
        countdownLeadTime: _countdownLeadTime,
      );
      for (final b in beeps) {
        _sound.player?.play(b);
      }

      // Only reschedule (and notify Consumer widgets) when a phase
      // transition occurred. Per-tick display updates flow through the
      // ValueNotifier below, bypassing the screen-wide rebuild.
      if (!identical(_progress, prevProgress)) {
        _rescheduleSound();
        notifyListeners();
      }
      // Always publish the new display value (10 Hz). Only the timer
      // widget's ValueListenableBuilder rebuilds in response.
      _syncTimerDisplay();
    });
  }

  void _advanceByElapsed(Duration elapsed) {
    // Subtract the real elapsed time. If the isolate was suspended (screen
    // locked), elapsed can be many seconds in a single call, making _remaining
    // go deeply negative.
    _remaining -= elapsed;

    // Loop because a single large elapsed value can skip through multiple
    // phases. e.g. locked for 45 s during a 10 s getReady → blows past
    // getReady, setRest, into rep.
    while (_remaining <= Duration.zero) {
      // Manual exercises wait for the user to tap advanceManually() — never
      // auto-advance.
      if (_activeSession != null) {
        final exercise =
            _activeSession!.workouts[_progress.workoutIndex].exercises[_progress
                .exerciseIndex];
        if (exercise.type == ExerciseType.manual &&
            _progress.phase == TimerPhase.rep) {
          _remaining = Duration.zero;
          return;
        }
      }
      final next = SessionStateMachine.calculateNextState(_progress, _activeSession!);
      if (next == null) {
        _onPhaseTransition(
          _progress.phase,
          TimerPhase.workoutComplete,
          _progress,
        );
        _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
        _remaining = Duration.zero;
        _sound.cancelAll();
        return;
      }
      // _remaining is negative here (the overshoot past phase end).
      // Adding the next phase's full duration keeps the overshoot as a debt,
      // so rapid successive phases consume the correct total elapsed time.
      _remaining = SessionStateMachine.getDurationForPhase(next, _activeSession) + _remaining;

      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
    }
  }

  /// Cancels or reschedules OS notifications via [SoundDispatcher], adapting
  /// the provider's current state to its parameter list. In-app audio is
  /// driven directly by the ticker (see [SoundDispatcher.classifyTickEdge]).
  void _rescheduleSound() {
    _sound.reschedule(
      isForegrounded: _isForegrounded,
      isPaused: _isPaused,
      progress: _progress,
      remaining: _remaining,
      activeSession: _activeSession,
      mode: _soundMode,
      restOvertimeOnBackground: _restOvertimeOnBackground,
      audioLeadTime: _audioLeadTime,
      countdownLeadTime: _countdownLeadTime,
    );
  }

  bool requestManualOvertime() {
    if (SessionStateMachine.isOvertimeEligible(_progress.phase)) {
      _enterOvertime(automatic: false);
      return true;
    } else {
      return false;
    }
  }

  /// The duration a rest of [restType] entering at [progress] was planned to
  /// run. Stored on the rest event for later comparison against actual time.
  /// Overtime and paused have no planned duration. Lives on the provider
  /// because it needs the active session.
  Duration _plannedRestDuration(RestType restType, SessionProgress progress) {
    if (restType == RestType.overtime || restType == RestType.paused) {
      return Duration.zero;
    }
    return SessionStateMachine.getDurationForPhase(progress, _activeSession);
  }

  /// Central hook called on every phase change. Keeps the event log consistent
  /// without each call site having to reason about it.
  ///
  /// Must be called BEFORE committing the new phase to [_progress], so [from]
  /// still reflects the phase being exited and [newProgress] carries the
  /// incoming phase.
  void _onPhaseTransition(
    TimerPhase from,
    TimerPhase to,
    SessionProgress newProgress,
  ) {
    // 1. Attribute the time spent in the exiting phase to the correct
    //    set-level accumulator. Only rep and repRest contribute to set
    //    telemetry — other phases are tracked as their own rest events.
    //    No-op if this is the very first transition (no prior timestamp yet).
    _telemetry.attributeSliceOnExit(from);

    // 2. Close the open rest event when leaving any rest-like phase.
    //    Each rest phase (getReady, setRest, exerciseRest, overtime, paused)
    //    has its own RestEvent — closing it stamps the end time.
    if (SessionStateMachine.isRestPhase(from)) _telemetry.closeRest();

    // 3. Close the open set event when leaving a rep for anything that ends
    //    the set. We keep it open across repRest (inter-rep rest is part of
    //    the same set) and across paused (the set spans the pause).
    if (from == TimerPhase.rep &&
        to != TimerPhase.repRest &&
        to != TimerPhase.paused) {
      _telemetry.closeSet(repsCompleted: newProgress.currentRep);
    }

    // 4. Open a new set event when entering a rep from a phase that starts a
    //    new set. We do NOT open one when coming from repRest (already open)
    //    or paused (resuming an existing set).
    if (to == TimerPhase.rep &&
        from != TimerPhase.repRest &&
        from != TimerPhase.paused) {
      _telemetry.openSet(newProgress);
    }

    // 5. Open a new rest event whenever entering any rest-like phase.
    //    This includes overtime and paused — each gets its own RestEvent so
    //    the log shows exactly how long each segment lasted.
    if (SessionStateMachine.isRestPhase(to)) {
      final restType = SessionStateMachine.matchRestTypeToTimerPhase(to);
      _telemetry.openRest(
        restType: restType,
        progress: newProgress,
        plannedDuration: _plannedRestDuration(restType, newProgress),
      );
    }
  }

  void _enterOvertime({required bool automatic}) {
    _overtimeSourcePhase = _progress.phase;
    _overtimeElapsed = Duration.zero;
    _overtimeWasAutomatic = automatic;
    _remaining = Duration.zero;
    final next = _progress.copyWith(phase: TimerPhase.overtime);
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _rescheduleSound();
    _syncTimerDisplay();
    notifyListeners();
  }

  void exitOvertime() {
    if (_progress.phase != TimerPhase.overtime) return;

    SessionProgress? _nextState = SessionStateMachine.calculateNextState(
      _progress.copyWith(phase: _overtimeSourcePhase),
      _activeSession!,
    );
    if (_nextState == null) {
      _onPhaseTransition(
        TimerPhase.overtime,
        TimerPhase.workoutComplete,
        _progress,
      );
      _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
      _remaining = Duration.zero;
      _sound.cancelAll();
    } else {
      final target = _nextState.copyWith(phase: TimerPhase.getReady);
      _onPhaseTransition(TimerPhase.overtime, target.phase, target);
      _progress = target;
      _remaining = const Duration(seconds: 10);
      _startTicker();
      _rescheduleSound();
    }

    _overtimeElapsed = Duration.zero;
    _overtimeWasAutomatic = false;
    _syncTimerDisplay();
    notifyListeners();
  }

  // Force the provider into a specific phase for testing.
  // For `supersetRest`, advance the exercise index to the next member as the
  // real state machine would do on entry. Asserts the current exercise has a
  // next-in-superset so out-of-bounds indexing can't happen.
  @visibleForTesting
  void debugSetPhase(TimerPhase phase) {
    final SessionProgress next;
    if (phase == TimerPhase.supersetRest) {
      assert(
        _activeSession != null &&
            hasNextInSuperset(
              _activeSession!.workouts[_progress.workoutIndex],
              _progress.exerciseIndex,
            ),
        'debugSetPhase(supersetRest): the current exercise must have a '
        'next-in-superset member. Call jumpToExercise() to a member that '
        'is not the last in its block, or build the fixture so the active '
        'exercise has a sibling.',
      );
      next = SessionProgress(
        workoutIndex: _progress.workoutIndex,
        exerciseIndex: _progress.exerciseIndex + 1,
        currentSet: _progress.currentSet,
        currentRep: 1,
        phase: TimerPhase.supersetRest,
      );
    } else {
      next = _progress.copyWith(phase: phase);
    }
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _remaining = SessionStateMachine.getDurationForPhase(_progress, _activeSession);
    _syncTimerDisplay();
    notifyListeners();
  }

  @visibleForTesting
  void debugSetLastTickAt(DateTime t) => _lastTickAt = t;

  @visibleForTesting
  int debugRestEventCount() => _telemetry.restEventCount;

  @visibleForTesting
  List<RestType> debugRestEventTypes() => _telemetry.restEventTypes;

  @override
  void dispose() {
    _ticker?.cancel();
    timerDisplayNotifier.dispose();
    anchorDeletedSignal.dispose();
    super.dispose();
  }
}
