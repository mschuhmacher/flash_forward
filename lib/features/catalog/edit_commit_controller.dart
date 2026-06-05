import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';

/// Single entry point edit screens call to commit a [PendingChangeBag] and
/// optionally run propagation. Holds no state — orchestrates over the catalog
/// provider's existing primitives (upsertSession/Workout/Exercise,
/// usagesOfWorkout/Exercise, propagate*ToSessionTemplates,
/// propagateExerciseToWorkouts).
///
/// Why a separate class: the catalog provider is about catalog state. Save
/// orchestration is its own concern — façade over the catalog so screens have
/// one well-named entry point per flow (commit, then optionally propagate)
/// instead of reaching into individual catalog mutations.
class EditCommitController {
  EditCommitController(this._catalog);

  final CatalogProvider _catalog;

  /// Commits a [PendingChangeBag] to the catalog. Promotes happen in
  /// dependency order (exercises → workouts → session) and the returned
  /// [CommitResult] describes other consumers affected, so the caller can
  /// render the combined propagation prompt.
  ///
  /// Suppression rule: if a bagged exercise also lives inside a bagged
  /// workout's exercises list, its `affectedWorkoutsByExerciseId` entry is
  /// suppressed — the exercise change reaches its only relevant consumer (the
  /// parent workout) via the workout's own propagation, so prompting again at
  /// the exercise level would be misleading.
  ///
  /// Partial-failure semantics: if a promote mid-flight throws (e.g. disk or
  /// network failure), some items may already be persisted while others
  /// aren't. There is no automatic rollback; the caller must surface the error
  /// to the user.
  Future<CommitResult> commitChanges(
    PendingChangeBag bag, {
    String? excludeSessionId,
    String? excludeWorkoutId,
  }) async {
    // When the bag has a session, the bagged workouts and exercises are
    // session-embedded: they live inside the session JSON and are persisted
    // via the session's own promote below. Pushing them into the catalog
    // (_userWorkouts/_userExercises) would create silent duplicates.
    final isSessionScopedCommit = bag.session != null;

    if (!isSessionScopedCommit) {
      // Promote in dependency order: exercises first, workouts next.
      for (final ec in bag.exercisesById.values) {
        await _catalog.upsertExercise(ec.exercise);
      }
      for (final wc in bag.workoutsById.values) {
        await _catalog.upsertWorkout(wc.workout);
      }
    }
    if (bag.session != null) {
      await _catalog.upsertSession(bag.session!.session);
    }

    // Compute affected consumers AFTER promotion (so usagesOf reflects current state).
    final sessionsByWorkout = <String, List<Session>>{};
    final workoutsByExercise = <String, List<Workout>>{};
    for (final wc in bag.workoutsById.values) {
      final sessions =
          _catalog
              .usagesOfWorkout(
                wc.workout.id,
                alsoMatchTemplateId: wc.workout.templateId,
              )
              .where((s) => s.id != excludeSessionId)
              .toList();
      if (sessions.isNotEmpty) sessionsByWorkout[wc.workout.id] = sessions;
    }
    // Suppress exercise-level propagation for exercises that live inside a
    // workout that's also being committed. The user's edit was scoped to that
    // workout context; the exercise change reaches its only relevant consumer
    // (the parent workout) via the workout's own propagation.
    final exerciseIdsInsideBaggedWorkouts = <String>{
      for (final wc in bag.workoutsById.values)
        for (final e in wc.workout.exercises) e.id,
    };
    for (final ec in bag.exercisesById.values) {
      if (exerciseIdsInsideBaggedWorkouts.contains(ec.exercise.id)) continue;
      // Dedupe by workout.id, not object identity — sessions loaded from JSON
      // produce separate Workout instances for the same id, so .toSet() on the
      // raw objects fails to collapse them.
      final byId = <String, Workout>{};
      for (final u in _catalog.usagesOfExercise(
        ec.exercise.id,
        alsoMatchTemplateId: ec.exercise.templateId,
      )) {
        if (u.workout.id == excludeWorkoutId) continue;
        byId[u.workout.id] = u.workout;
      }
      if (byId.isNotEmpty) {
        workoutsByExercise[ec.exercise.id] = byId.values.toList();
      }
    }
    return CommitResult(
      affectedSessionsByWorkoutId: sessionsByWorkout,
      affectedWorkoutsByExerciseId: workoutsByExercise,
    );
  }

  /// Runs every propagation path implied by the bag. Called when the user
  /// confirms the combined propagation prompt. Exercises propagate into both
  /// session templates and user workouts; workouts propagate into session
  /// templates. Session changes don't propagate (sessions are leaf consumers).
  /// Pass [selection] to honour the per-consumer checkboxes; null means all.
  Future<void> propagateBag(
    PendingChangeBag bag, {
    PropagationSelection? selection,
  }) async {
    // Mirror the suppression in commitChanges: exercises that live inside a
    // bagged workout already reach session templates via the workout's own
    // propagation. Calling propagateExerciseToSessionTemplates separately
    // would ignore the selection filter (no 'exercise-in-sessions' key exists)
    // and overwrite correctly-excluded sessions.
    final exerciseIdsInsideBaggedWorkouts = <String>{
      for (final wc in bag.workoutsById.values)
        for (final e in wc.workout.exercises) e.id,
    };

    for (final ec in bag.exercisesById.values) {
      if (!exerciseIdsInsideBaggedWorkouts.contains(ec.exercise.id)) {
        await _catalog.propagateExerciseToSessionTemplates(
          ec.exercise,
          onlyToSessionIds: selection?.sessionIdsFor(
            'exercise',
            ec.exercise.id,
          ),
        );
      }
      await _catalog.propagateExerciseToWorkouts(
        ec.exercise,
        onlyToWorkoutIds: selection?.workoutIdsFor('exercise', ec.exercise.id),
      );
    }
    for (final wc in bag.workoutsById.values) {
      await _catalog.propagateWorkoutToSessionTemplates(
        wc.workout,
        onlyToSessionIds: selection?.sessionIdsFor('workout', wc.workout.id),
      );
    }
  }
}

/// Returned by [EditCommitController.commitChanges] so the edit screen can
/// render a single combined "this also affects …" prompt covering every
/// promoted item. Lists are already filtered by the optional excludes (the
/// workout/session being edited is suppressed from its own consumer list).
class CommitResult {
  CommitResult({
    required this.affectedSessionsByWorkoutId,
    required this.affectedWorkoutsByExerciseId,
  });

  /// Workout id → sessions (other than the one being edited, if any) that use it.
  final Map<String, List<Session>> affectedSessionsByWorkoutId;

  /// Exercise id → workouts (other than the one being edited, if any) that use it.
  final Map<String, List<Workout>> affectedWorkoutsByExerciseId;

  bool get hasAny =>
      affectedSessionsByWorkoutId.values.any((l) => l.isNotEmpty) ||
      affectedWorkoutsByExerciseId.values.any((l) => l.isNotEmpty);
}
