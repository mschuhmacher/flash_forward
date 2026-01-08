import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/exercise.dart';

/// Describes which part of the timer is active. Kept minimal so UI can branch
/// on a single enum instead of separate booleans.
enum TimerPhase { rep, repRest, setRest, exerciseRest, workoutComplete }

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

  // Timer-related state. These fields are read by the UI and manipulated via
  // the start/pause/resume/reset methods below. The actual session/workout/
  // exercise lists remain the single source of truth in the models.
  SessionProgress _progress = const SessionProgress(
    workoutIndex: 0,
    exerciseIndex: 0,
    currentSet: 1,
    currentRep: 1,
    phase: TimerPhase.workoutComplete,
  );
  // Countdown remaining for the current phase.
  Duration _remaining = Duration.zero;
  // Whether the ticker should decrement. Keeps the periodic timer lightweight.
  bool _isPaused = true;
  // Periodic timer that ticks once per second and advances phases.
  Timer? _ticker;

  int get weekIndex => _weekIndex;
  int get sessionIndex => _sessionIndex;
  int get workoutIndex => _workoutIndex;
  SessionProgress get progress => _progress;
  Duration get remaining => _remaining;
  TimerPhase get phase => _progress.phase;
  bool get isPaused => _isPaused;

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
  void jumpToWorkout(int index, Session session) {
    if (index < 0 || index >= session.list.length) return;
    _workoutIndex = index;
    _progress = SessionProgress(
      workoutIndex: index,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.rep,
    );
    _remaining = _getDurationForPhase(session, _progress);
    notifyListeners();
  }

  // -------- Timer controls (first pass) --------
  // These methods expose a minimal API for the UI to drive the timer. They
  // rely on the session/workout/exercise models for timing data instead of
  // duplicating durations inside the provider.

  void start(Session session) {
    _progress = const SessionProgress(
      workoutIndex: 0,
      exerciseIndex: 0,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.rep,
    );
    _remaining = _getDurationForPhase(session, _progress);
    _isPaused = false;
    _startTicker(session);
    notifyListeners();
  }

  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  void resume(Session session) {
    if (!_isPaused) return;
    _isPaused = false;
    _startTicker(session);
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
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

  void _startTicker(Session session) {
    // Ensure only one ticker runs at a time.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_remaining > Duration.zero) {
        _remaining -= const Duration(seconds: 1);
        notifyListeners();
        return;
      }

      final next = _calculateNextState(session, _progress);
      if (next == null) {
        _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
        _remaining = Duration.zero;
        notifyListeners();
        return;
      }

      _progress = next;
      _remaining = _getDurationForPhase(session, _progress);
      notifyListeners();
    });
  }

  /// Pure transition logic: given current position + phase, determine what the
  /// next position/phase should be. This re-reads the latest session/workout/
  /// exercise data, so mid-session edits are respected automatically.
  SessionProgress? _calculateNextState(Session session, SessionProgress p) {
    final Workout workout = session.list[p.workoutIndex];
    final Exercise exercise = workout.list[p.exerciseIndex];

    switch (p.phase) {
      case TimerPhase.rep:
        // After a rep, either go to repRest or straight into the next rep flow
        if (exercise.timeBetweenReps > 0) {
          return p.copyWith(phase: TimerPhase.repRest);
        }
        // fallthrough handled by repRest case
        return _calculateNextState(
          session,
          p.copyWith(phase: TimerPhase.repRest),
        );

      case TimerPhase.repRest:
        if (p.currentRep < exercise.reps) {
          return p.copyWith(
            currentRep: p.currentRep + 1,
            phase: TimerPhase.rep,
          );
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
        return p.copyWith(phase: TimerPhase.exerciseRest);

      case TimerPhase.exerciseRest:
        final nextExerciseIndex = p.exerciseIndex + 1;
        if (nextExerciseIndex < workout.list.length) {
          return SessionProgress(
            workoutIndex: p.workoutIndex,
            exerciseIndex: nextExerciseIndex,
            currentSet: 1,
            currentRep: 1,
            phase: TimerPhase.rep,
          );
        }
        final nextWorkoutIndex = p.workoutIndex + 1;
        if (nextWorkoutIndex < session.list.length) {
          return SessionProgress(
            workoutIndex: nextWorkoutIndex,
            exerciseIndex: 0,
            currentSet: 1,
            currentRep: 1,
            phase: TimerPhase.rep,
          );
        }
        return null;

      case TimerPhase.workoutComplete:
        return null;
    }
  }

  /// Returns the duration for the current phase, derived from the active
  /// exercise/workout. Values are stored as seconds in the models.
  Duration _getDurationForPhase(Session session, SessionProgress p) {
    if (p.phase == TimerPhase.workoutComplete) return Duration.zero;
    final workout = session.list[p.workoutIndex];
    final exercise = workout.list[p.exerciseIndex];

    switch (p.phase) {
      case TimerPhase.rep:
        return Duration(seconds: exercise.timePerRep);
      case TimerPhase.repRest:
        return Duration(seconds: exercise.timeBetweenReps);
      case TimerPhase.setRest:
        return Duration(seconds: exercise.timeBetweenSets);
      case TimerPhase.exerciseRest:
        return Duration(seconds: workout.timeBetweenExercises);
      case TimerPhase.workoutComplete:
        return Duration.zero;
    }
  }
}
