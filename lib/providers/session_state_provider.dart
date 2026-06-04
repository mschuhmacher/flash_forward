import 'dart:async';

import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/providers/session_state_machine.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/services/audio_beep_player.dart';
import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

/// Describes which part of the timer is active. Kept minimal so UI can branch
/// on a single enum instead of separate booleans.
enum TimerPhase {
  rep,
  repRest,
  setRest,
  supersetRest,
  exerciseRest,
  overtime,
  workoutComplete,
  paused,
  getReady,
}

/// Immutable snapshot of where the user currently is inside the session tree
/// (workout -> exercise -> set -> rep) plus the phase of the timer.
/// This lives in the provider so UI can read it directly without deriving.
class SessionProgress {
  final int workoutIndex;
  final int exerciseIndex;
  final int currentSet; // 1-based
  final int currentRep; // 1-based
  final TimerPhase phase;

  const SessionProgress({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.currentSet,
    required this.currentRep,
    required this.phase,
  });

  SessionProgress copyWith({
    int? workoutIndex,
    int? exerciseIndex,
    int? currentSet,
    int? currentRep,
    TimerPhase? phase,
  }) {
    return SessionProgress(
      workoutIndex: workoutIndex ?? this.workoutIndex,
      exerciseIndex: exerciseIndex ?? this.exerciseIndex,
      currentSet: currentSet ?? this.currentSet,
      currentRep: currentRep ?? this.currentRep,
      phase: phase ?? this.phase,
    );
  }
}

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
  // Injected scheduler — null until setBeepScheduler() is called.
  BeepScheduler? _beepScheduler;
  // Injected in-app audio player — null until setAudioBeepPlayer() is called.
  AudioBeepPlayer? _audioPlayer;
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

  // Event log — accumulated during an active session.
  final List<SetEvent> _setEvents = [];
  final List<RestEvent> _restEvents = [];

  // In-progress drafts. Null when no set/rest is currently open.
  _OpenSetDraft? _activeSetDraft;
  _OpenRestDraft? _activeRestDraft;

  // Updated on every phase transition for slice attribution.
  DateTime? _currentPhaseEnteredAt;

  // Per-set accumulators — reset when a new set opens.
  Duration _currentSetActiveAccum = Duration.zero;
  Duration _currentSetRepRestAccum = Duration.zero;

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

  void setBeepScheduler(BeepScheduler scheduler) => _beepScheduler = scheduler;

  void setAudioBeepPlayer(AudioBeepPlayer player) => _audioPlayer = player;

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
      _beepScheduler?.cancelAll();
      reconcileAfterBackground();
    } else {
      _rescheduleSound();
    }
  }

  Future<bool> canScheduleExactAlarms() =>
      _beepScheduler?.canScheduleExactAlarms() ?? Future.value(true);

  Future<void> requestExactAlarmPermission() =>
      _beepScheduler?.requestExactAlarmPermission() ?? Future.value();

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
    _discardDrafts();
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
    _discardDrafts();
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
    _discardDrafts();
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
    _discardDrafts();
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
      if (_activeSetDraft != null) {
        _activeSetDraft!.workoutIndex = newWorkoutIndex;
        _activeSetDraft!.exerciseIndex = newExerciseIndex;
      }
      if (_activeRestDraft != null) {
        _activeRestDraft!.workoutIndex = newWorkoutIndex;
        _activeRestDraft!.exerciseIndex = newExerciseIndex;
      }
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
    _discardDrafts();

    // Clamp old indices so _firstStopAtOrAfter doesn't go out of bounds.
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
      _beepScheduler?.cancelAll();
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
    _setEvents.clear();
    _restEvents.clear();
    _discardDrafts();

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
    _currentPhaseEnteredAt = DateTime.now(); // Start time for the first slice

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

    if (_currentPhaseEnteredAt != null) {
      Duration slice = DateTime.now().difference(_currentPhaseEnteredAt!);
      if (_progress.phase == TimerPhase.rep) {
        _currentSetActiveAccum += slice;
      }
      if (_progress.phase == TimerPhase.repRest) {
        _currentSetRepRestAccum += slice;
      }
      _currentPhaseEnteredAt = DateTime.now();
    }

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

  SessionSummary _computeSummary() {
    var activeTime = Duration.zero;
    var interRepRestTime = Duration.zero;
    for (final e in _setEvents) {
      activeTime += e.activeTime;
      interRepRestTime += e.interRepRestTime;
    }

    var setRestTime = Duration.zero;
    var supersetRestTime = Duration.zero;
    var exerciseRestTime = Duration.zero;
    var getReadyTime = Duration.zero;
    var overtime = Duration.zero;
    var pausedTime = Duration.zero;
    for (final e in _restEvents) {
      switch (e.restType) {
        case RestType.setRest:
          setRestTime += e.actualDuration;
        case RestType.supersetRest:
          supersetRestTime += e.actualDuration;
        case RestType.exerciseRest:
          exerciseRestTime += e.actualDuration;
        case RestType.getReady:
          getReadyTime += e.actualDuration;
        case RestType.overtime:
          overtime += e.actualDuration;
        case RestType.paused:
          pausedTime += e.actualDuration;
      }
    }

    final totalTime =
        activeTime +
        interRepRestTime +
        setRestTime +
        supersetRestTime +
        exerciseRestTime +
        getReadyTime +
        overtime +
        pausedTime;

    return SessionSummary(
      totalTime: totalTime,
      activeTime: activeTime,
      interRepRestTime: interRepRestTime,
      setRestTime: setRestTime,
      supersetRestTime: supersetRestTime,
      exerciseRestTime: exerciseRestTime,
      getReadyTime: getReadyTime,
      overtime: overtime,
      pausedTime: pausedTime,
    );
  }

  /// Closes any open drafts, computes telemetry, and returns the active session
  /// populated with event logs and a summary. Does not reset state — call
  /// [reset] separately after persisting.
  Session finalizeSession() {
    _closeSetDraft(repsCompleted: _progress.currentRep);
    _closeRestDraft();
    final summary = _computeSummary();
    return _activeSession!.copyWith(
      setEvents: List.unmodifiable(_setEvents),
      restEvents: List.unmodifiable(_restEvents),
      summary: summary,
    );
  }

  void reset() {
    _ticker?.cancel();
    _lastTickAt = null;
    _beepScheduler?.cancelAll();
    _activeSession = null;
    _setEvents.clear();
    _restEvents.clear();
    _discardDrafts();
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
      // go: route through _enterPostSetRest so superset members enter
      // exerciseRest pre-advanced to the group's first member.
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

      final playInApp =
          _isForegrounded &&
          (_soundMode == SoundMode.soundsOnly || _soundMode == SoundMode.both);

      if (playInApp) {
        final countdownThreshold =
            const Duration(seconds: 3) + _countdownLeadTime;
        // Countdown: fire when remaining crosses the threshold during getReady,
        // setRest, or supersetRest. Shifted earlier by _countdownLeadTime so the
        // "3" beep in the cadence lands at exactly 3 s remaining, with a 3.2 s
        // gap before the go beep (gap = 3 s + _countdownLeadTime - _audioLeadTime).
        if ((prevProgress.phase == TimerPhase.getReady ||
                prevProgress.phase == TimerPhase.setRest ||
                prevProgress.phase == TimerPhase.supersetRest) &&
            previousRemaining > countdownThreshold &&
            _remaining <= countdownThreshold &&
            _remaining > Duration.zero) {
          _audioPlayer?.play(BeepType.countdown);
        }

        // Go beep: fires _audioLeadTime before the rep starts, i.e. while still
        // in the preceding rest/getReady phase with ≤ _audioLeadTime remaining.
        if ((prevProgress.phase == TimerPhase.getReady ||
                prevProgress.phase == TimerPhase.setRest ||
                prevProgress.phase == TimerPhase.repRest ||
                prevProgress.phase == TimerPhase.supersetRest) &&
            previousRemaining > _audioLeadTime &&
            _remaining <= _audioLeadTime) {
          _audioPlayer?.play(BeepType.go);
        }

        // Stop beep: fires _audioLeadTime before the rep ends, i.e. while still
        // in the rep phase with ≤ _audioLeadTime remaining.
        if (prevProgress.phase == TimerPhase.rep &&
            _progress.phase == TimerPhase.rep &&
            previousRemaining > _audioLeadTime &&
            _remaining <= _audioLeadTime) {
          _audioPlayer?.play(BeepType.stop);
        }
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
        _beepScheduler?.cancelAll();
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

  /// Cancels or reschedules notifications based on the current sound mode and
  /// foreground state. In-app audio is driven directly by the ticker and does
  /// not need scheduling here.
  void _rescheduleSound() {
    final useNotifications =
        !_isForegrounded &&
        !_isPaused &&
        _activeSession != null &&
        (_soundMode == SoundMode.both ||
            _soundMode == SoundMode.notificationsOnly);
    if (useNotifications && _beepScheduler != null) {
      _beepScheduler!.scheduleAll(_calculateFutureBeeps());
    } else {
      _beepScheduler?.cancelAll();
    }
  }

  /// Simulates the remaining state machine from the current position and
  /// returns a chronological list of beeps to schedule. Stops at
  /// [BeepScheduler.maxBeeps] entries (iOS limit) or when a manual rep phase
  /// is reached (unknown duration).
  List<ScheduledBeep> _calculateFutureBeeps() {
    final beeps = <ScheduledBeep>[];
    var simProgress = _progress;
    var phaseEndAt = DateTime.now().add(_remaining);

    while (true) {
      _addBeepsForPhase(beeps, simProgress, phaseEndAt);
      if (beeps.length >= BeepScheduler.maxBeeps) break;

      final next = SessionStateMachine.calculateNextState(simProgress, _activeSession!);
      if (next == null) break;

      if (_restOvertimeOnBackground &&
          (simProgress.phase == TimerPhase.setRest ||
              simProgress.phase == TimerPhase.exerciseRest)) {
        break;
      }

      // Manual rep phase: duration unknown — cannot predict further.
      if (_activeSession != null) {
        final exercise =
            _activeSession!.workouts[next.workoutIndex].exercises[next
                .exerciseIndex];
        if (exercise.type == ExerciseType.manual &&
            next.phase == TimerPhase.rep) {
          break;
        }
      }

      phaseEndAt = phaseEndAt.add(SessionStateMachine.getDurationForPhase(next, _activeSession));
      simProgress = next;
    }

    return beeps;
  }

  void _addBeepsForPhase(
    List<ScheduledBeep> beeps,
    SessionProgress p,
    DateTime phaseEndAt,
  ) {
    final now = DateTime.now();
    switch (p.phase) {
      case TimerPhase.rep:
        // Stop beep fires _audioLeadTime before the rep ends.
        final stopAt = phaseEndAt.subtract(_audioLeadTime);
        if (stopAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: stopAt, type: BeepType.stop));
        }
      case TimerPhase.getReady:
      case TimerPhase.setRest:
      case TimerPhase.supersetRest:
        // Countdown at 3 s + _countdownLeadTime before phase end so the "3"
        // beep aligns with 3 s remaining. Go beep _audioLeadTime before end.
        // repRest intentionally excluded — no countdown for inter-rep rests.
        final countdownAt = phaseEndAt.subtract(
          const Duration(seconds: 3) + _countdownLeadTime,
        );
        if (countdownAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: countdownAt, type: BeepType.countdown));
        }
        final goAt = phaseEndAt.subtract(_audioLeadTime);
        if (goAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: goAt, type: BeepType.go));
        }
      case TimerPhase.repRest:
        // No countdown for inter-rep rests; go beep _audioLeadTime before end.
        final goAt = phaseEndAt.subtract(_audioLeadTime);
        if (goAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: goAt, type: BeepType.go));
        }
      default:
        break; // exerciseRest, workoutComplete, paused, overtime: no beeps
    }
  }

  bool requestManualOvertime() {
    if (SessionStateMachine.isOvertimeEligible(_progress.phase)) {
      _enterOvertime(automatic: false);
      return true;
    } else {
      return false;
    }
  }

  void _startSetDraft(SessionProgress progress) {
    _activeSetDraft = _OpenSetDraft(
      workoutIndex: progress.workoutIndex,
      exerciseIndex: progress.exerciseIndex,
      setIndex: progress.currentSet,
      startAt: DateTime.now(),
    );
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  void _closeSetDraft({required int repsCompleted}) {
    if (_activeSetDraft == null) return;

    _setEvents.add(
      SetEvent(
        workoutIndex: _activeSetDraft!.workoutIndex,
        exerciseIndex: _activeSetDraft!.exerciseIndex,
        setIndex: _activeSetDraft!.setIndex,
        startAt: _activeSetDraft!.startAt,
        endAt: DateTime.now(),
        activeTime: _currentSetActiveAccum,
        interRepRestTime: _currentSetRepRestAccum,
        repsCompleted: repsCompleted,
      ),
    );
    _activeSetDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  void _startRestDraft(RestType restType, SessionProgress progress) {
    Duration plannedDuration = Duration.zero;
    int? setIndex;

    if (restType != RestType.overtime && restType != RestType.paused) {
      plannedDuration = SessionStateMachine.getDurationForPhase(progress, _activeSession);
    }
    if (restType == RestType.setRest) {
      setIndex = progress.currentSet;
    }

    _activeRestDraft = _OpenRestDraft(
      restType: restType,
      workoutIndex: progress.workoutIndex,
      exerciseIndex: progress.exerciseIndex,
      setIndex: setIndex,
      startAt: DateTime.now(),
      plannedDuration: plannedDuration,
    );
  }

  void _closeRestDraft() {
    if (_activeRestDraft == null) return;

    Duration actual = DateTime.now().difference(_activeRestDraft!.startAt);
    Duration overtimeDuration = Duration.zero;

    if (_activeRestDraft!.restType == RestType.overtime) {
      overtimeDuration = actual;
    }

    _restEvents.add(
      RestEvent(
        restType: _activeRestDraft!.restType,
        workoutIndex: _activeRestDraft!.workoutIndex,
        exerciseIndex: _activeRestDraft!.exerciseIndex,
        setIndex: _activeRestDraft!.setIndex,
        startAt: _activeRestDraft!.startAt,
        endAt: DateTime.now(),
        plannedDuration: _activeRestDraft!.plannedDuration,
        actualDuration: actual,
        overtimeDuration: overtimeDuration,
      ),
    );

    _activeRestDraft = null;
  }

  void _discardDrafts() {
    _activeRestDraft = null;
    _activeSetDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
    _currentPhaseEnteredAt = null;
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
    //    Skip if this is the very first transition (no prior timestamp yet).
    if (_currentPhaseEnteredAt != null) {
      Duration slice = DateTime.now().difference(_currentPhaseEnteredAt!);
      if (from == TimerPhase.rep) _currentSetActiveAccum += slice;
      if (from == TimerPhase.repRest) _currentSetRepRestAccum += slice;
      _currentPhaseEnteredAt = DateTime.now();
    }

    // 2. Close the open rest event when leaving any rest-like phase.
    //    Each rest phase (getReady, setRest, exerciseRest, overtime, paused)
    //    has its own RestEvent — closing it stamps the end time.
    if (SessionStateMachine.isRestPhase(from)) _closeRestDraft();

    // 3. Close the open set event when leaving a rep for anything that ends
    //    the set. We keep it open across repRest (inter-rep rest is part of
    //    the same set) and across paused (the set spans the pause).
    if (from == TimerPhase.rep &&
        to != TimerPhase.repRest &&
        to != TimerPhase.paused) {
      _closeSetDraft(repsCompleted: newProgress.currentRep);
    }

    // 4. Open a new set event when entering a rep from a phase that starts a
    //    new set. We do NOT open one when coming from repRest (already open)
    //    or paused (resuming an existing set).
    if (to == TimerPhase.rep &&
        from != TimerPhase.repRest &&
        from != TimerPhase.paused) {
      _startSetDraft(newProgress);
    }

    // 5. Open a new rest event whenever entering any rest-like phase.
    //    This includes overtime and paused — each gets its own RestEvent so
    //    the log shows exactly how long each segment lasted.
    if (SessionStateMachine.isRestPhase(to)) {
      _startRestDraft(SessionStateMachine.matchRestTypeToTimerPhase(to), newProgress);
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
      _beepScheduler?.cancelAll();
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
  int debugRestEventCount() => _restEvents.length;

  @visibleForTesting
  List<RestType> debugRestEventTypes() =>
      _restEvents.map((e) => e.restType).toList();

  @override
  void dispose() {
    _ticker?.cancel();
    timerDisplayNotifier.dispose();
    anchorDeletedSignal.dispose();
    super.dispose();
  }
}

class _OpenSetDraft {
  int workoutIndex;
  int exerciseIndex;
  final int setIndex;
  final DateTime startAt;

  _OpenSetDraft({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
  });
}

class _OpenRestDraft {
  final RestType restType;
  int workoutIndex;
  int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final Duration plannedDuration;

  _OpenRestDraft({
    required this.restType,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.plannedDuration,
  });
}
