import 'dart:async';

import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/services/audio_beep_player.dart';
import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

import 'package:meta/meta.dart';

/// Describes which part of the timer is active. Kept minimal so UI can branch
/// on a single enum instead of separate booleans.
enum TimerPhase {
  rep,
  repRest,
  setRest,
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
    _remaining = _getDurationForPhase(_progress);
    _rescheduleSound();
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
      _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
      _remaining = _getDurationForPhase(_progress);
      _rescheduleSound();
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
      _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
      _remaining = _getDurationForPhase(_progress);
      _rescheduleSound();
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
      _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
      _remaining = _getDurationForPhase(_progress);
      _rescheduleSound();
      notifyListeners();
    }
  }

  void jumpToSet(int index) {
    _discardDrafts();
    if (index < 0) {
      return;
    } else if (index == 0) {
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
      _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
      _remaining = _getDurationForPhase(_progress);
      _rescheduleSound();
      notifyListeners();
    } else if (index > 0 &&
        index <=
            _activeSession!
                .workouts[_workoutIndex]
                .exercises[_exerciseIndex]
                .sets) {
      _progress = SessionProgress(
        workoutIndex: _workoutIndex,
        exerciseIndex: _exerciseIndex,
        currentSet: index,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
      _onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
      _remaining = _getDurationForPhase(_progress);
      _rescheduleSound();
      notifyListeners();
    } else if (index >
        _activeSession!
            .workouts[_workoutIndex]
            .exercises[_exerciseIndex]
            .sets) {
      return;
    }
  }

  /// Update a single exercise in the active session copy (e.g. mid-session load/sets edit).
  /// Uses copyWith so all fields remain immutable — the preset is never touched.
  void updateActiveExercise(
    int workoutIndex,
    int exerciseIndex,
    Exercise updated,
  ) {
    if (_activeSession == null) return;
    final workout = _activeSession!.workouts[workoutIndex];
    final updatedExercises = List<Exercise>.from(workout.exercises);
    updatedExercises[exerciseIndex] = updated;
    final updatedWorkouts = List<Workout>.from(_activeSession!.workouts);
    updatedWorkouts[workoutIndex] = workout.copyWith(
      exercises: updatedExercises,
    );
    _activeSession = _activeSession!.copyWith(workouts: updatedWorkouts);

    // Clamp progress if the user reduced sets/reps below current position.
    final clampedSet = _progress.currentSet.clamp(1, updated.sets);
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

    _remaining = _getDurationForPhase(_progress);
    _isPaused = false;
    _startTicker();
    _rescheduleSound();
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
    var exerciseRestTime = Duration.zero;
    var getReadyTime = Duration.zero;
    var overtime = Duration.zero;
    var pausedTime = Duration.zero;
    for (final e in _restEvents) {
      switch (e.restType) {
        case RestType.setRest:
          setRestTime += e.actualDuration;
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

    final totalTime = activeTime +
        interRepRestTime +
        setRestTime +
        exerciseRestTime +
        getReadyTime +
        overtime +
        pausedTime;

    return SessionSummary(
      totalTime: totalTime,
      activeTime: activeTime,
      interRepRestTime: interRepRestTime,
      setRestTime: setRestTime,
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
    notifyListeners();
  }

  /// For manual-type exercises: advance to the next set (with rest) or to
  /// exerciseRest when all sets are done. No-op for other exercise types.
  void advanceManually() {
    if (_activeSession == null) return;
    final exercise =
        _activeSession!.workouts[_progress.workoutIndex].exercises[_progress
            .exerciseIndex];
    if (exercise.type != ExerciseType.manual) return;
    if (_progress.phase != TimerPhase.rep) return;

    if (_progress.currentSet < exercise.sets) {
      final next = _progress.copyWith(phase: TimerPhase.setRest);
      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
    } else {
      final next = _progress.copyWith(phase: TimerPhase.exerciseRest);
      _onPhaseTransition(_progress.phase, next.phase, next);
      _progress = next;
    }
    _remaining = _getDurationForPhase(_progress);
    _rescheduleSound();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    // Stamp the current wall-clock time so the first tick can measure a real
    // elapsed delta.
    _lastTickAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_progress.phase == TimerPhase.overtime) {
        final now = DateTime.now();
        _overtimeElapsed += now.difference(_lastTickAt!);
        _lastTickAt = now;
        notifyListeners();
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
        // Countdown: fire when remaining crosses from >3 s to ≤3 s during
        // getReady or setRest. The sound file contains the full 3-2-1 cadence.
        if ((prevProgress.phase == TimerPhase.getReady ||
                prevProgress.phase == TimerPhase.setRest) &&
            previousRemaining > const Duration(seconds: 3) &&
            _remaining <= const Duration(seconds: 3) &&
            _remaining > Duration.zero) {
          _audioPlayer?.play(BeepType.countdown);
        }
      }

      // Only reschedule when a phase transition occurred. Rescheduling every
      // tick would cancel and recreate all 64 notifications at 1 Hz, flooding
      // the OS notification API and causing beeps to miss their fire window.
      if (!identical(_progress, prevProgress)) {
        _rescheduleSound();
        if (playInApp) {
          // Go beep: entering a rep (from getReady, setRest, or repRest).
          if (_progress.phase == TimerPhase.rep &&
              prevProgress.phase != TimerPhase.rep) {
            _audioPlayer?.play(BeepType.go);
          }
          // Stop beep: leaving a rep phase into any rest or completion.
          else if (prevProgress.phase == TimerPhase.rep &&
              _progress.phase != TimerPhase.rep) {
            _audioPlayer?.play(BeepType.stop);
          }
        }
      }
      notifyListeners();
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
      final next = _calculateNextState(_progress);
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
      _remaining = _getDurationForPhase(next) + _remaining;

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

      final next = _calculateNextState(simProgress);
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

      phaseEndAt = phaseEndAt.add(_getDurationForPhase(next));
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
        // Stop beep (microwave-style ding) when the rep duration ends.
        if (phaseEndAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.stop));
        }
      case TimerPhase.getReady:
      case TimerPhase.setRest:
        // Single countdown notification at 3 s before phase end — the sound
        // file itself contains three beeps (3, 2, 1). Go beep at phase end.
        // repRest intentionally excluded — no countdown for inter-rep rests.
        final t = phaseEndAt.subtract(const Duration(seconds: 3));
        if (t.isAfter(now)) {
          beeps.add(ScheduledBeep(at: t, type: BeepType.countdown));
        }
        if (phaseEndAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.go));
        }
      case TimerPhase.repRest:
        // No countdown for inter-rep rests, but go beep fires at the start of
        // each rep.
        if (phaseEndAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.go));
        }
      default:
        break; // exerciseRest, workoutComplete, paused, overtime: no beeps
    }
  }

  // State machine transitions by exercise type:
  //
  // timedReps:     getReady → rep ↔ repRest → setRest → rep (next set) → exerciseRest
  // fixedDuration: getReady → rep → setRest → rep (next set) → exerciseRest
  // manual:        getReady → rep [waits for advanceManually()] → setRest → rep [waits] → exerciseRest
  //
  // setRest → exerciseRest when currentSet == sets (all types)
  // exerciseRest: progress already points to the next exercise on entry.
  //   → rep (same workout) or getReady (new workout, exerciseIndex == 0) or null (session done)
  SessionProgress? _calculateNextState(SessionProgress p) {
    if (_activeSession == null) return null;
    final Workout workout = _activeSession!.workouts[p.workoutIndex];
    final Exercise exercise = workout.exercises[p.exerciseIndex];

    switch (p.phase) {
      case TimerPhase.rep:
        switch (exercise.type) {
          case ExerciseType.timedReps:
            final reps = exercise.reps ?? 1;
            if (exercise.timeBetweenReps > 0 && p.currentRep < reps) {
              return p.copyWith(phase: TimerPhase.repRest);
            }
            // No inter-rep rest — skip repRest and resolve via recursion.
            return _calculateNextState(p.copyWith(phase: TimerPhase.repRest));
          case ExerciseType.fixedDuration:
            // A single timed effort per set — skip repRest entirely.
            // Also skip setRest on the last set.
            if (p.currentSet >= exercise.sets) {
              return _enterExerciseRest(p);
            }
            return p.copyWith(phase: TimerPhase.setRest);
          case ExerciseType.manual:
            // Should never be reached via the ticker (guarded in _startTicker).
            // Only advanceManually() drives transitions from here.
            return null;
        }

      case TimerPhase.repRest:
        final reps = exercise.reps ?? 1;
        if (p.currentRep < reps) {
          return p.copyWith(
            currentRep: p.currentRep + 1,
            phase: TimerPhase.rep,
          );
        }
        // Last rep done — skip setRest if this was also the last set.
        if (p.currentSet >= exercise.sets) {
          return _enterExerciseRest(p);
        }
        return p.copyWith(phase: TimerPhase.setRest);

      case TimerPhase.setRest:
        if (p.currentSet < exercise.sets) {
          return p.copyWith(
            currentSet: p.currentSet + 1,
            currentRep: 1,
            phase: TimerPhase.rep,
          );
        }
        return _enterExerciseRest(p);

      case TimerPhase.exerciseRest:
        // exerciseIndex already points to the next exercise (set on entry).
        // If exerciseIndex == 0 it was a cross-workout transition → getReady,
        // otherwise continue directly to rep within the same workout.
        return p.copyWith(
          phase: p.exerciseIndex == 0 ? TimerPhase.getReady : TimerPhase.rep,
        );
      case TimerPhase.getReady:
        // Transition from GET READY to first rep of current exercise
        return p.copyWith(phase: TimerPhase.rep);
      case TimerPhase.overtime:
        return null;
      case TimerPhase.workoutComplete:
        return null;
      case TimerPhase.paused:
        return null;
    }
  }

  /// Advances to the next exercise and enters exerciseRest, so the UI
  /// immediately shows the upcoming exercise during the rest period.
  /// Returns null if there are no more exercises (session ends).
  SessionProgress? _enterExerciseRest(SessionProgress progress) {
    final workout = _activeSession!.workouts[progress.workoutIndex];
    final nextExercise = progress.exerciseIndex + 1;

    if (nextExercise < workout.exercises.length) {
      return SessionProgress(
        workoutIndex: progress.workoutIndex,
        exerciseIndex: nextExercise,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.exerciseRest,
      );
    }

    final nextWorkout = progress.workoutIndex + 1;
    if (nextWorkout < _activeSession!.workouts.length) {
      return SessionProgress(
        workoutIndex: nextWorkout,
        exerciseIndex: 0,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.exerciseRest,
      );
    }

    return null;
  }

  bool requestManualOvertime() {
    if (_isOvertimeEligible(_progress.phase)) {
      _enterOvertime(automatic: false);
      return true;
    } else {
      return false;
    }
  }

  bool _isOvertimeEligible(TimerPhase p) {
    return (p == TimerPhase.setRest ||
        p == TimerPhase.exerciseRest ||
        p == TimerPhase.getReady);
  }

  bool _isRestPhase(TimerPhase p) =>
      p == TimerPhase.getReady ||
      p == TimerPhase.setRest ||
      p == TimerPhase.exerciseRest ||
      p == TimerPhase.overtime ||
      p == TimerPhase.paused;

  RestType _matchRestTypeToTimerPhase(TimerPhase p) {
    switch (p) {
      case TimerPhase.getReady:
        return RestType.getReady;
      case TimerPhase.setRest:
        return RestType.setRest;
      case TimerPhase.exerciseRest:
        return RestType.exerciseRest;
      case TimerPhase.overtime:
        return RestType.overtime;
      case TimerPhase.paused:
        return RestType.paused;
      default:
        throw StateError('Not a rest phase: $p');
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
      plannedDuration = _getDurationForPhase(progress);
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
    if (_isRestPhase(from)) _closeRestDraft();

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
    if (_isRestPhase(to)) {
      _startRestDraft(_matchRestTypeToTimerPhase(to), newProgress);
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
    notifyListeners();
  }

  void exitOvertime() {
    if (_progress.phase != TimerPhase.overtime) return;

    SessionProgress? _nextState = _calculateNextState(
      _progress.copyWith(phase: _overtimeSourcePhase),
    );
    if (_nextState == null) {
      _onPhaseTransition(TimerPhase.overtime, TimerPhase.workoutComplete, _progress);
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
    notifyListeners();
  }

  // Force the provider into a specific phase for testing
  @visibleForTesting
  void debugSetPhase(TimerPhase phase) {
    final next = _progress.copyWith(phase: phase);
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _remaining = _getDurationForPhase(_progress);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetLastTickAt(DateTime t) => _lastTickAt = t;

  @visibleForTesting
  int debugRestEventCount() => _restEvents.length;

  @visibleForTesting
  List<RestType> debugRestEventTypes() =>
      _restEvents.map((e) => e.restType).toList();

  /// Returns the duration for the current phase, derived from the active
  /// exercise/workout. Values are stored as seconds in the models.
  Duration _getDurationForPhase(SessionProgress p) {
    if (_activeSession == null || p.phase == TimerPhase.workoutComplete) {
      return Duration.zero;
    }
    final workout = _activeSession!.workouts[p.workoutIndex];
    final exercise = workout.exercises[p.exerciseIndex];

    switch (p.phase) {
      case TimerPhase.rep:
        return switch (exercise.type) {
          ExerciseType.timedReps => Duration(seconds: exercise.timePerRep),
          ExerciseType.fixedDuration => Duration(seconds: exercise.activeTime),
          ExerciseType.manual => Duration.zero,
        };
      case TimerPhase.repRest:
        return Duration(seconds: exercise.timeBetweenReps);
      case TimerPhase.setRest:
        return Duration(seconds: exercise.timeBetweenSets);
      case TimerPhase.exerciseRest:
        return Duration(seconds: workout.timeBetweenExercises);
      case TimerPhase.overtime:
        return Duration.zero;
      case TimerPhase.workoutComplete:
        return Duration.zero;
      case TimerPhase.paused:
        return Duration.zero;
      case TimerPhase.getReady:
        return const Duration(seconds: 10);
    }
  }
}

class _OpenSetDraft {
  final int workoutIndex;
  final int exerciseIndex;
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
  final int workoutIndex;
  final int exerciseIndex;
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
