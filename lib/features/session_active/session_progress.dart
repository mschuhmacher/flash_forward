// Shared session-progress value types.
//
// Lifted out of `session_state_provider.dart` so the helper classes
// (`SessionStateMachine`, `SessionTelemetryRecorder`, `SoundDispatcher`) can
// depend on these types without importing the provider that composes them —
// the dependency now flows one way: provider + helpers → these types.

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
