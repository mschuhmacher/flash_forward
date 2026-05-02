import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

sealed class PendingChange {
  const PendingChange();
}

class WorkoutChanged extends PendingChange {
  const WorkoutChanged(this.workout);
  final Workout workout;
}

class ExerciseChanged extends PendingChange {
  const ExerciseChanged(this.exercise);
  final Exercise exercise;
}

class SessionChanged extends PendingChange {
  const SessionChanged(this.session);
  final Session session;
}

/// Accumulates edits made during a single edit-screen session.
/// Nothing is written to the provider until the outermost Save fires and
/// hands this bag to [PresetProvider.commitChanges]. Cancelling at any level
/// discards the bag and leaves the provider untouched.
/// Same-id replays overwrite (last edit wins per item).
class PendingChangeBag {
  PendingChangeBag();

  final Map<String, ExerciseChanged> exercisesById = {};
  final Map<String, WorkoutChanged> workoutsById = {};
  SessionChanged? session;

  void addExercise(Exercise e) => exercisesById[e.id] = ExerciseChanged(e);
  void addWorkout(Workout w) => workoutsById[w.id] = WorkoutChanged(w);
  void setSession(Session s) => session = SessionChanged(s);

  /// Merges [other] into this bag, with [other]'s entries taking precedence
  /// on id collision. Used when a nested edit screen returns its sub-bag.
  void merge(PendingChangeBag other) {
    exercisesById.addAll(other.exercisesById);
    workoutsById.addAll(other.workoutsById);
    if (other.session != null) session = other.session;
  }

  bool get isEmpty =>
      exercisesById.isEmpty && workoutsById.isEmpty && session == null;
}
