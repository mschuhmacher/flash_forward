import 'dart:async';

import 'package:flash_forward/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

/// Describes which part of the timer is active. Kept minimal so UI can branch
/// on a single enum instead of separate booleans.
enum TimerPhase {
  rep,
  repRest,
  setRest,
  exerciseRest,
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

  TimerPhase _rememberCurrentPhaseForPausing = TimerPhase.getReady;

  int get weekIndex => _weekIndex;
  int get sessionIndex => _sessionIndex;
  int get workoutIndex => _workoutIndex;
  int get exerciseIndex => _exerciseIndex;
  SessionProgress get progress => _progress;
  Duration get remaining => _remaining;
  TimerPhase get phase => _progress.phase;
  bool get isPaused => _isPaused;

  /// The active session copy. Non-null while a session is running.
  Session? get activeSession => _activeSession;

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
    _workoutIndex = index;
    _progress = SessionProgress(
      workoutIndex: index,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.rep,
    );
    _remaining = _getDurationForPhase(_progress);
    notifyListeners();
  }

  /// Jump to a specific exercise and reset set/rep to the first items.
  /// Keeps the timer in sync with navigation actions in the UI.
  void jumpToExercise(int index) {
    if (_activeSession == null) return;
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
      _remaining = _getDurationForPhase(_progress);
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
      _remaining = _getDurationForPhase(_progress);
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
      _remaining = _getDurationForPhase(_progress);
      notifyListeners();
    }
  }

  void jumpToSet(int index) {
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
      _remaining = _getDurationForPhase(_progress);
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
      _remaining = _getDurationForPhase(_progress);
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
    final clampedRep = updated.reps != null
        ? _progress.currentRep.clamp(1, updated.reps!)
        : _progress.currentRep;
    if (clampedSet != _progress.currentSet || clampedRep != _progress.currentRep) {
      _progress = _progress.copyWith(currentSet: clampedSet, currentRep: clampedRep);
    }

    notifyListeners();
  }

  // -------- Timer controls (first pass) --------
  // These methods expose a minimal API for the UI to drive the timer. They
  // rely on the session/workout/exercise models for timing data instead of
  // duplicating durations inside the provider.

  void start(Session session) {
    // Deep copy the preset so mid-session edits never affect it
    _activeSession = session.deepCopy();
    _progress = const SessionProgress(
      workoutIndex: 0,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.getReady,
    );
    _remaining = _getDurationForPhase(_progress);
    _isPaused = false;
    _startTicker();
    notifyListeners();
  }

  void pause() {
    if (_isPaused)
      {return;} // idempotent — second call would corrupt _rememberCurrentPhaseForPausing
    _isPaused = true;
    _rememberCurrentPhaseForPausing = _progress.phase;
    _progress = _progress.copyWith(phase: TimerPhase.paused);
    notifyListeners();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _progress = _progress.copyWith(phase: _rememberCurrentPhaseForPausing);
    _startTicker();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _activeSession = null;
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
      _progress = _progress.copyWith(phase: TimerPhase.setRest);
    } else {
      _progress = _progress.copyWith(phase: TimerPhase.exerciseRest);
    }
    _remaining = _getDurationForPhase(_progress);
    notifyListeners();
    // The existing ticker picks up the timed setRest/exerciseRest countdown normally.
  }

  void _startTicker() {
    // Ensure only one ticker runs at a time.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_remaining > Duration.zero) {
        _remaining -= const Duration(seconds: 1);
        notifyListeners();
        return;
      }

      // Do not auto-advance manual exercises in the rep phase — wait for advanceManually().
      if (_activeSession != null) {
        final exercise =
            _activeSession!.workouts[_progress.workoutIndex].exercises[_progress
                .exerciseIndex];
        if (exercise.type == ExerciseType.manual &&
            _progress.phase == TimerPhase.rep) {
          return;
        }
      }

      final next = _calculateNextState(_progress);
      if (next == null) {
        _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
        _remaining = Duration.zero;
        notifyListeners();
        return;
      }

      _progress = next;
      _remaining = _getDurationForPhase(_progress);
      notifyListeners();
    });
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
      case TimerPhase.workoutComplete:
        return Duration.zero;
      case TimerPhase.paused:
        return Duration.zero;
      case TimerPhase.getReady:
        return const Duration(seconds: 10);
    }
  }
}
