import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a session with named workout/exercise ids for easy lookup.
Session _fixture({
  String workoutId = 'w1',
  String exerciseId = 'e1',
  int sets = 3,
  int reps = 8,
}) =>
    Session(
      title: 'S',
      label: 'other',
      workouts: [
        Workout(
          id: workoutId,
          title: 'W',
          label: 'other',
          timeBetweenExercises: 60,
          exercises: [
            Exercise(
              id: exerciseId,
              title: 'E',
              description: '',
              label: 'other',
              sets: sets,
              reps: reps,
              timeBetweenSets: 30,
            ),
          ],
        ),
      ],
    );

// Adds a second exercise to a fixture session.
Session _withSecondExercise(Session s, {String id = 'e2'}) {
  final w = s.workouts[0];
  return s.copyWith(
    workouts: [
      w.copyWith(
        exercises: [
          ...w.exercises,
          Exercise(
            id: id,
            title: 'E2',
            description: '',
            label: 'other',
            sets: 3,
            reps: 8,
            timeBetweenSets: 30,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('replaceActiveSession — anchor survives', () {
    test('re-anchors to same exercise after add before it', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      // Move to second exercise (e2 at index 1).
      p.jumpToExercise(1);
      expect(p.progress.exerciseIndex, 1);

      // Build edited from the live activeSession so IDs match (start() deepCopies).
      final activeWorkout = p.activeSession!.workouts[0];
      final newExercise = Exercise(
        title: 'New',
        description: '',
        label: 'other',
        sets: 2,
        reps: 5,
        timeBetweenSets: 20,
      );
      final edited = p.activeSession!.copyWith(
        workouts: [
          activeWorkout.copyWith(
            exercises: [
              activeWorkout.exercises[0],
              newExercise,
              activeWorkout.exercises[1],
            ],
          ),
        ],
      );

      p.replaceActiveSession(edited);

      // e2 is now at index 2, not 1.
      expect(p.progress.exerciseIndex, 2);
      expect(p.progress.workoutIndex, 0);
    });

    test('clamps currentSet when sets reduced below current', () {
      final original = _fixture(sets: 4);
      final p = SessionStateProvider()..start(original);
      p.jumpToSet(3); // currentSet = 3
      expect(p.progress.currentSet, 3);

      // Reduce to 2 sets — build from live session to preserve IDs.
      final activeExercise = p.activeSession!.workouts[0].exercises[0];
      final activeWorkout = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [
          activeWorkout.copyWith(
            exercises: [activeExercise.copyWith(sets: 2)],
          ),
        ],
      );
      p.replaceActiveSession(edited);

      expect(p.progress.currentSet, 2);
    });

    test('preserves currentSet when sets unchanged', () {
      final original = _fixture(sets: 4);
      final p = SessionStateProvider()..start(original);
      p.jumpToSet(3);

      // Edit reps only — build from live session to preserve IDs.
      final activeExercise = p.activeSession!.workouts[0].exercises[0];
      final activeWorkout = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [
          activeWorkout.copyWith(
            exercises: [activeExercise.copyWith(reps: Nullable(6))],
          ),
        ],
      );
      p.replaceActiveSession(edited);

      expect(p.progress.currentSet, 3);
    });

    test('rewrites open set draft indices after workout reorder', () {
      final original = Session(
        title: 'S',
        label: 'other',
        workouts: [
          Workout(
            title: 'W1',
            label: 'other',
            timeBetweenExercises: 60,
            exercises: [
              Exercise(
                title: 'E1',
                description: '',
                label: 'other',
                sets: 3,
                reps: 8,
                timeBetweenSets: 30,
              ),
            ],
          ),
          Workout(
            title: 'W2',
            label: 'other',
            timeBetweenExercises: 60,
            exercises: [
              Exercise(
                title: 'E2',
                description: '',
                label: 'other',
                sets: 3,
                reps: 8,
                timeBetweenSets: 30,
              ),
            ],
          ),
        ],
      );
      final p = SessionStateProvider()..start(original);
      // Advance to W2/E2 (workoutIndex 1, exerciseIndex 0).
      p.jumpToWorkout(1);
      p.debugSetPhase(TimerPhase.rep); // opens a set draft at w=1, e=0

      // Swap workout order using the live activeSession ids.
      final activeW1 = p.activeSession!.workouts[0];
      final activeW2 = p.activeSession!.workouts[1];
      final edited = p.activeSession!.copyWith(workouts: [activeW2, activeW1]);
      p.replaceActiveSession(edited);

      // W2 is now at index 0; progress should re-anchor there.
      expect(p.progress.workoutIndex, 0);
      expect(p.progress.exerciseIndex, 0);
    });

    test('does not touch _setEvents or _restEvents', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.debugSetPhase(TimerPhase.rep);
      p.debugSetPhase(TimerPhase.exerciseRest); // logs a set event
      final eventCountBefore = p.debugRestEventCount();

      final edited = original.copyWith(); // structural no-op
      p.replaceActiveSession(edited);

      expect(p.debugRestEventCount(), eventCountBefore);
    });
  });

  group('replaceActiveSession — anchor deleted', () {
    test('jumps to next stop when current exercise deleted', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.pause(); // mirrors real usage: modal always pauses before editor opens

      // Stay on e1 (index 0). Delete e1, keep e2 — build from live session.
      final activeW = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [activeW.copyWith(exercises: [activeW.exercises[1]])],
      );

      p.replaceActiveSession(edited);

      // Should land on e2 (now index 0), paused, rememberPhase = getReady.
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.phase, TimerPhase.paused);
      // On resume the user should enter getReady, not mid-rep, with the
      // countdown primed to the full getReady duration (10s) rather than a
      // stale value left over from the deleted exercise's phase.
      p.resume();
      expect(p.phase, TimerPhase.getReady);
      expect(p.remaining, const Duration(seconds: 10));
    });

    test('transitions to workoutComplete when all exercises from current onward deleted', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.jumpToExercise(1); // on e2 (last exercise)
      // Delete e2 (current) — nothing after it. Build from live session.
      final activeW = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [activeW.copyWith(exercises: [activeW.exercises[0]])],
      );

      p.replaceActiveSession(edited);

      expect(p.phase, TimerPhase.workoutComplete);
      // Indices must be clamped to a still-valid slot: the active screen
      // indexes workouts[workoutIndex].exercises[exerciseIndex] on every
      // rebuild before checking for workoutComplete, so a stale (deleted)
      // index throws a RangeError during build.
      expect(p.progress.workoutIndex, lessThan(p.activeSession!.workouts.length));
      expect(
        p.progress.exerciseIndex,
        lessThan(
          p.activeSession!.workouts[p.progress.workoutIndex].exercises.length,
        ),
      );
    });

    test('stays workoutComplete after resume when last exercise deleted', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.jumpToExercise(1); // on e2 (last exercise)
      p.pause(); // modal opens → pause (not pre-paused by the user)
      final activeW = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [activeW.copyWith(exercises: [activeW.exercises[0]])],
      );

      p.replaceActiveSession(edited);
      expect(p.phase, TimerPhase.workoutComplete);

      // Closing the modal resumes (when not pre-paused). resume() must not flip
      // the phase off workoutComplete back onto the last surviving exercise.
      p.resume();
      expect(p.phase, TimerPhase.workoutComplete);
    });

    test('previousStop from workoutComplete lands on the last exercise', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.jumpToExercise(1); // on e2 (last exercise, index 1)
      final activeW = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [activeW.copyWith(exercises: [activeW.exercises[0]])],
      );
      p.replaceActiveSession(edited); // now workoutComplete; e1 is last (index 0)

      final prev = p.previousStop;
      expect(prev, isNotNull);
      // Should re-enter the last real exercise (index 0 here), not one before.
      expect(prev!.exerciseIndex, 0);
    });

    test('discards open drafts when anchor deleted', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.debugSetPhase(TimerPhase.rep); // opens a set draft on e1
      // Delete e1 (current), keep e2 — build from live session.
      final activeW = p.activeSession!.workouts[0];
      final edited = p.activeSession!.copyWith(
        workouts: [activeW.copyWith(exercises: [activeW.exercises[1]])],
      );
      p.replaceActiveSession(edited);
      // finalizeSession should not throw and summary is coherent.
      expect(() => p.finalizeSession(), returnsNormally);
    });
  });
}
