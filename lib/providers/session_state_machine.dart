import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/utils/superset_utils.dart';

/// Pure transition logic for a running session: given where we are, what's
/// next, and how long does each phase last. No state, no side effects — every
/// method is static and depends only on its arguments.
///
/// Two models live here: the per-tick **phase cycle** (`calculateNextState` +
/// `getDurationForPhase`) and the **stop-navigation** model used by the
/// bottom bar (`calculateNextStop` / `calculatePreviousStop`). Both are
/// diagrammed and explained in
/// `docs/architecture/session-state-machine.md` — update that doc when you
/// change a transition here.
class SessionStateMachine {
  SessionStateMachine._();

  static const Duration getReadyLeadIn = Duration(seconds: 10);
  static bool isGetReadyMoment(TimerPhase phase, Duration remaining) {
    if (phase == TimerPhase.getReady) {
      return true;
    } else if ((phase == TimerPhase.setRest ||
            phase == TimerPhase.supersetRest ||
            phase == TimerPhase.exerciseRest) &&
        remaining > Duration.zero &&
        remaining <= getReadyLeadIn) {
      return true;
    } else {
      return false;
    }
  }

  static SessionProgress? calculateNextStop(
    SessionProgress p,
    Session activeSession,
  ) {
    final workout = activeSession.workouts[p.workoutIndex];
    final exercise = workout.exercises[p.exerciseIndex];
    final effectiveSets = setsForExerciseInWorkout(workout, exercise);
    final ss = supersetForExercise(workout, exercise.id);

    if (ss != null) {
      if (hasNextInSuperset(workout, p.exerciseIndex)) {
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: p.exerciseIndex + 1,
          currentSet: p.currentSet,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      // Last member of the group.
      if (p.currentSet < effectiveSets) {
        // More rounds: wrap to group start, bump set.
        final groupStart = supersetGroupStartIndex(workout, p.exerciseIndex);
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: groupStart,
          currentSet: p.currentSet + 1,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      // Group done — exit past the group's last index.
      final groupEnd = supersetGroupEndIndex(workout, p.exerciseIndex);
      return firstStopAtOrAfter(p.workoutIndex, groupEnd + 1, activeSession);
    }

    // Solo exercise: next exercise (sets aren't stops here — they're the
    // same exercise repeated, and the user wants to know what *exercise*
    // they're doing next).
    return firstStopAtOrAfter(
      p.workoutIndex,
      p.exerciseIndex + 1,
      activeSession,
    );
  }

  /// Returns a `rep` (or `getReady`) stop at exercise [index] within
  /// [workoutIndex], handling overflow into the next workout. Null when
  /// the session is exhausted.
  static SessionProgress? firstStopAtOrAfter(
    int workoutIndex,
    int index,
    Session activeSession,
  ) {
    final workout = activeSession.workouts[workoutIndex];
    if (index < workout.exercises.length) {
      return SessionProgress(
        workoutIndex: workoutIndex,
        exerciseIndex: index,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
    }
    final nextWorkout = workoutIndex + 1;
    if (nextWorkout < activeSession.workouts.length) {
      return SessionProgress(
        workoutIndex: nextWorkout,
        exerciseIndex: 0,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.getReady,
      );
    }
    return null;
  }

  static SessionProgress? calculatePreviousStop(
    SessionProgress p,
    Session activeSession,
  ) {
    // From workoutComplete the user is conceptually past the final exercise,
    // so "previous" re-enters the last real stop (the last exercise), not the
    // one before it. _lastStopBefore(w, len) resolves to that last exercise.
    if (p.phase == TimerPhase.workoutComplete) {
      final lastWorkoutIndex = activeSession.workouts.length - 1;
      final lastWorkout = activeSession.workouts[lastWorkoutIndex];
      return lastStopBefore(
        lastWorkoutIndex,
        lastWorkout.exercises.length,
        activeSession,
      );
    }

    final workout = activeSession.workouts[p.workoutIndex];
    final exercise = workout.exercises[p.exerciseIndex];
    final ss = supersetForExercise(workout, exercise.id);

    if (ss != null) {
      final groupStart = supersetGroupStartIndex(workout, p.exerciseIndex);
      if (p.exerciseIndex > groupStart) {
        // Earlier member of the same round.
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: p.exerciseIndex - 1,
          currentSet: p.currentSet,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      // First member of the group.
      if (p.currentSet > 1) {
        // Wrap back to the previous round's last member.
        final groupEnd = supersetGroupEndIndex(workout, p.exerciseIndex);
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: groupEnd,
          currentSet: p.currentSet - 1,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      // First round, first member — step out before the group.
      return lastStopBefore(p.workoutIndex, groupStart, activeSession);
    }

    // Solo exercise: previous exercise (sets aren't stops here).
    return lastStopBefore(p.workoutIndex, p.exerciseIndex, activeSession);
  }

  /// Returns a stop at exercise [index] - 1 within [workoutIndex], handling
  /// underflow into the previous workout's last exercise. Null at the very
  /// start of the session.
  ///
  /// When the previous exercise is a superset member, lands on the *last*
  /// member of the group at the *final* round, so a single back-press from
  /// outside the group enters at the group's natural "previous step."
  static SessionProgress? lastStopBefore(
    int workoutIndex,
    int index,
    Session activeSession,
  ) {
    if (index > 0) {
      final workout = activeSession.workouts[workoutIndex];
      final targetIndex = index - 1;
      final targetExercise = workout.exercises[targetIndex];
      final ss = supersetForExercise(workout, targetExercise.id);
      if (ss != null) {
        final groupEnd = supersetGroupEndIndex(workout, targetIndex);
        final groupExercise = workout.exercises[groupEnd];
        final effectiveSets = setsForExerciseInWorkout(workout, groupExercise);
        return SessionProgress(
          workoutIndex: workoutIndex,
          exerciseIndex: groupEnd,
          currentSet: effectiveSets,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      // Solo: sets aren't stops, so land at the start of the exercise.
      return SessionProgress(
        workoutIndex: workoutIndex,
        exerciseIndex: targetIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.rep,
      );
    }
    final prevWorkout = workoutIndex - 1;
    if (prevWorkout >= 0) {
      final workout = activeSession.workouts[prevWorkout];
      final lastIndex = workout.exercises.length - 1;
      // The cross-workout case mirrors jumpToExercise(-1): land at the
      // previous workout's last exercise, currentSet 1, getReady.
      return SessionProgress(
        workoutIndex: prevWorkout,
        exerciseIndex: lastIndex,
        currentSet: 1,
        currentRep: 1,
        phase: TimerPhase.getReady,
      );
    }
    return null;
  }

  // State machine transitions by exercise type:
  //
  // timedReps:     getReady → rep ↔ repRest → setRest → rep (next set) → exerciseRest
  // fixedDuration: getReady → rep → setRest → rep (next set) → exerciseRest
  // manual:        getReady → rep [waits for advanceManually()] → setRest → rep [waits] → exerciseRest
  //
  // setRest → exerciseRest when currentSet == sets (all types). For supersets,
  // setRest never fires — between rounds we go directly into exerciseRest with
  // exerciseIndex pre-advanced back to the first member of the block. The
  // duration of that exerciseRest is then the superset's supersetSetRest
  // (vs. workout.timeBetweenExercises for normal exerciseRest).
  // exerciseRest: progress already points to the next exercise on entry.
  //   → rep (same workout) or getReady (new workout, exerciseIndex == 0) or null (session done)
  static SessionProgress? calculateNextState(
    SessionProgress p,
    Session activeSession,
  ) {
    final Workout workout = activeSession.workouts[p.workoutIndex];
    final Exercise exercise = workout.exercises[p.exerciseIndex];
    final int effectiveSets = setsForExerciseInWorkout(workout, exercise);

    switch (p.phase) {
      case TimerPhase.rep:
        switch (exercise.type) {
          case ExerciseType.timedReps:
            final reps = exercise.reps ?? 1;
            if (exercise.timeBetweenReps > 0 && p.currentRep < reps) {
              return p.copyWith(phase: TimerPhase.repRest);
            }
            // No inter-rep rest — skip repRest and resolve via recursion.
            return calculateNextState(
              p.copyWith(phase: TimerPhase.repRest),
              activeSession,
            );
          case ExerciseType.fixedDuration:
            // A single timed effort per set — skip repRest entirely.
            // Also skip setRest on the last set.
            if (p.currentSet >= effectiveSets) {
              if (hasNextInSuperset(workout, p.exerciseIndex)) {
                return SessionProgress(
                  workoutIndex: p.workoutIndex,
                  exerciseIndex: p.exerciseIndex + 1,
                  currentSet: p.currentSet,
                  currentRep: 1,
                  phase: TimerPhase.supersetRest,
                );
              }
              return enterExerciseRest(p, activeSession);
            }
            if (hasNextInSuperset(workout, p.exerciseIndex)) {
              return SessionProgress(
                workoutIndex: p.workoutIndex,
                exerciseIndex: p.exerciseIndex + 1,
                currentSet: p.currentSet,
                currentRep: 1,
                phase: TimerPhase.supersetRest,
              );
            }
            return enterPostSetRest(p, workout, activeSession);
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
        if (p.currentSet >= effectiveSets) {
          if (hasNextInSuperset(workout, p.exerciseIndex)) {
            return SessionProgress(
              workoutIndex: p.workoutIndex,
              exerciseIndex: p.exerciseIndex + 1,
              currentSet: p.currentSet,
              currentRep: 1,
              phase: TimerPhase.supersetRest,
            );
          }
          return enterExerciseRest(p, activeSession);
        }
        if (hasNextInSuperset(workout, p.exerciseIndex)) {
          return SessionProgress(
            workoutIndex: p.workoutIndex,
            exerciseIndex: p.exerciseIndex + 1,
            currentSet: p.currentSet,
            currentRep: 1,
            phase: TimerPhase.supersetRest,
          );
        }
        return enterPostSetRest(p, workout, activeSession);

      case TimerPhase.setRest:
        // setRest is now solo-only. For superset between-rounds rest, the
        // state machine routes through exerciseRest in _enterPostSetRest.
        if (p.currentSet < effectiveSets) {
          return SessionProgress(
            workoutIndex: p.workoutIndex,
            exerciseIndex: p.exerciseIndex,
            currentSet: p.currentSet + 1,
            currentRep: 1,
            phase: TimerPhase.rep,
          );
        }
        return enterExerciseRest(p, activeSession);

      case TimerPhase.supersetRest:
        return p.copyWith(phase: TimerPhase.rep);

      case TimerPhase.exerciseRest:
        // Always → rep: exerciseIndex already points at the upcoming exercise
        // (set on entry), within-workout and cross-workout alike. The cycle no
        // longer produces getReady — the rest's final getReadyLeadIn seconds
        // are surfaced as "get ready" by isGetReadyMoment, not a separate phase.
        return p.copyWith(phase: TimerPhase.rep);
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
  /// After finishing the last rep/set of an exercise but with more sets to
  /// go, route into the appropriate post-set rest:
  /// - Solo exercise → setRest (uses exercise.timeBetweenSets).
  /// - Last member of a superset (more rounds remaining) → exerciseRest
  ///   with exerciseIndex pre-advanced back to the group's first member,
  ///   currentSet incremented. Duration is read from supersetSetRest by
  ///   _getDurationForPhase. The UI sees the upcoming exercise during the
  ///   rest, just like a normal exerciseRest.
  static SessionProgress enterPostSetRest(
    SessionProgress p,
    Workout workout,
    Session activeSession,
  ) {
    final exercise = workout.exercises[p.exerciseIndex];
    final superset = supersetForExercise(workout, exercise.id);
    if (superset == null) {
      // Solo: classic setRest stays at the current exercise; the
      // setRest case advances currentSet on exit.
      return p.copyWith(phase: TimerPhase.setRest);
    }
    // Superset: between-rounds rest. Pre-advance to the group's first
    // member and bump the set counter so the upcoming round starts there.
    final groupStart = supersetGroupStartIndex(workout, p.exerciseIndex);
    return SessionProgress(
      workoutIndex: p.workoutIndex,
      exerciseIndex: groupStart,
      currentSet: p.currentSet + 1,
      currentRep: 1,
      phase: TimerPhase.exerciseRest,
    );
  }

  /// Returns null if there are no more exercises (session ends).
  static SessionProgress? enterExerciseRest(
    SessionProgress progress,
    Session activeSession,
  ) {
    final workout = activeSession.workouts[progress.workoutIndex];
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
    if (nextWorkout < activeSession.workouts.length) {
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

  static bool isOvertimeEligible(TimerPhase p) {
    return (p == TimerPhase.setRest ||
        p == TimerPhase.exerciseRest ||
        p == TimerPhase.getReady);
  }

  static bool isRestPhase(TimerPhase p) =>
      p == TimerPhase.getReady ||
      p == TimerPhase.setRest ||
      p == TimerPhase.supersetRest ||
      p == TimerPhase.exerciseRest ||
      p == TimerPhase.overtime ||
      p == TimerPhase.paused;

  static RestType matchRestTypeToTimerPhase(TimerPhase p) {
    switch (p) {
      case TimerPhase.getReady:
        return RestType.getReady;
      case TimerPhase.setRest:
        return RestType.setRest;
      case TimerPhase.supersetRest:
        return RestType.supersetRest;
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

  /// Returns the duration for the current phase, derived from the active
  /// exercise/workout. Values are stored as seconds in the models.
  static Duration getDurationForPhase(
    SessionProgress p,
    Session? activeSession,
  ) {
    if (activeSession == null || p.phase == TimerPhase.workoutComplete) {
      return Duration.zero;
    }
    final workout = activeSession.workouts[p.workoutIndex];
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
      case TimerPhase.supersetRest:
        final superset = supersetForExercise(workout, exercise.id);
        return Duration(seconds: superset?.restSeconds ?? 15);
      case TimerPhase.exerciseRest:
        // Between-rounds rest of a superset (currentSet > 1 and the
        // upcoming exercise is a member of a superset whose first member
        // is also at p.exerciseIndex) uses supersetSetRest, falling back
        // to workout.timeBetweenExercises when not set.
        final superset = supersetForExercise(workout, exercise.id);
        if (superset != null && p.currentSet > 1) {
          return Duration(
            seconds: superset.supersetSetRest ?? workout.timeBetweenExercises,
          );
        }
        return Duration(seconds: workout.timeBetweenExercises);
      case TimerPhase.overtime:
        return Duration.zero;
      case TimerPhase.workoutComplete:
        return Duration.zero;
      case TimerPhase.paused:
        return Duration.zero;
      case TimerPhase.getReady:
        return getReadyLeadIn;
    }
  }
}
