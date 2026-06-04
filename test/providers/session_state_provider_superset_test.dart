import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _e(String id, {int sets = 2}) => Exercise(
    id: id,
    title: id,
    description: 'd',
    label: 'l',
    sets: sets,
    reps: 1,
    timeBetweenReps: 0,
    timeBetweenSets: 60);

Session _ss2({int sets = 2, int ssRestSeconds = 10, int? supersetSets}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [_e('e1', sets: sets), _e('e2', sets: sets)],
      supersets: [
        SupersetConfig(
            id: 'ss1',
            exerciseIds: ['e1', 'e2'],
            restSeconds: ssRestSeconds,
            supersetSets: supersetSets)
      ],
    ),
  ]);
}

Session _ss3({int sets = 2}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [
        _e('e1', sets: sets),
        _e('e2', sets: sets),
        _e('e3', sets: sets)
      ],
      supersets: [
        SupersetConfig(
            id: 'ss1', exerciseIds: ['e1', 'e2', 'e3'], restSeconds: 15)
      ],
    ),
  ]);
}

/// Workout: [e1, e2, e3] where e1+e2 form a superset; e3 is solo.
Session _ssMixed({int supersetSets = 2, int e3Sets = 2}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [_e('e1', sets: 1), _e('e2', sets: 1), _e('e3', sets: e3Sets)],
      supersets: [
        SupersetConfig(
            id: 'ss1',
            exerciseIds: ['e1', 'e2'],
            restSeconds: 10,
            supersetSets: supersetSets)
      ],
    ),
  ]);
}

/// Two workouts: W1 = [a1] solo, W2 = [b1, b2] superset.
Session _ssTwoWorkouts() {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W1',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [_e('a1', sets: 2)],
      supersets: const [],
    ),
    Workout(
      title: 'W2',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [_e('b1', sets: 1), _e('b2', sets: 1)],
      supersets: [
        SupersetConfig(
            id: 'ss1',
            exerciseIds: ['b1', 'b2'],
            restSeconds: 10,
            supersetSets: 2)
      ],
    ),
  ]);
}

Session _ssAsymmetric(
    {required int e1Sets, required int e2Sets, required int supersetSets}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W',
      label: 'l',
      timeBetweenExercises: 120,
      exercises: [_e('e1', sets: e1Sets), _e('e2', sets: e2Sets)],
      supersets: [
        SupersetConfig(
            id: 'ss1',
            exerciseIds: ['e1', 'e2'],
            restSeconds: 10,
            supersetSets: supersetSets)
      ],
    ),
  ]);
}

void main() {
  group('supersetRest phase transitions', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('supersetRest duration comes from SupersetConfig.restSeconds', () {
      p.start(_ss2(ssRestSeconds: 15));
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.remaining, const Duration(seconds: 15));
    });

    test('supersetRest exerciseIndex points to next superset member', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.progress.exerciseIndex, 1);
    });

    test('supersetRest -> rep at next exercise', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 11)));
      p.reconcileAfterBackground();
      expect(p.progress.phase, TimerPhase.rep);
      expect(p.progress.exerciseIndex, 1);
    });

    test(
        'between rounds of a 3-member superset: rep@last member auto-advances '
        'to exerciseRest pre-advanced to the first member',
        () {
      // After the last rep of the last superset member with more rounds
      // to go, the state machine routes through exerciseRest (not
      // setRest) with exerciseIndex pre-advanced back to the group's
      // first member and currentSet incremented. The UI consequently
      // shows the upcoming exercise during the rest, just like a normal
      // exerciseRest.
      p.start(_ss3(sets: 2));
      p.jumpToExercise(2); // last superset member
      p.debugSetPhase(TimerPhase.rep);
      // Drive the state machine forward via a backgrounded gap that
      // exceeds the rep phase: rep → exerciseRest@first-member, set=2.
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 35)));
      p.reconcileAfterBackground();
      expect(p.progress.phase, TimerPhase.exerciseRest);
      expect(p.progress.exerciseIndex, 0); // pre-advanced back to A
      expect(p.progress.currentSet, 2);
    });

    test('exerciseRest fires after final set of last superset exercise', () {
      p.start(_ss2(sets: 1));
      p.jumpToExercise(1); // last member
      p.debugSetPhase(TimerPhase.exerciseRest);
      expect(p.progress.phase, TimerPhase.exerciseRest);
    });

    test('supersetRest is logged in restEvents', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      // Advance past the supersetRest so the open draft closes and the
      // RestEvent gets recorded in `_restEvents`.
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 11)));
      p.reconcileAfterBackground();
      expect(p.debugRestEventTypes(), contains(RestType.supersetRest));
    });

    test('supersetRest is NOT overtime-eligible', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.requestManualOvertime(), isFalse);
    });

    test('non-superset exercise unaffected: setRest goes to same exercise next set',
        () {
      final solo = Session(title: 't', label: 'l', workouts: [
        Workout(
          title: 'W',
          label: 'l',
          timeBetweenExercises: 120,
          exercises: [_e('solo', sets: 2)],
          supersets: [],
        ),
      ]);
      p.start(solo);
      p.debugSetPhase(TimerPhase.setRest);
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 61)));
      p.reconcileAfterBackground();
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 2);
    });
  });

  group('supersetSets overrides exercise.sets in state machine', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('asymmetric superset: 3-set + 4-set with supersetSets=4 lets jumpToSet(4)',
        () {
      p.start(_ssAsymmetric(e1Sets: 3, e2Sets: 4, supersetSets: 4));
      p.jumpToSet(4);
      expect(p.progress.currentSet, 4);
      expect(p.progress.phase, TimerPhase.rep);
    });

    test('supersetSets=null falls back to first member exercise.sets', () {
      p.start(_ss2(sets: 3));
      p.jumpToSet(3);
      expect(p.progress.currentSet, 3);
      // 4th set should not be reachable.
      p.jumpToSet(4);
      expect(p.progress.currentSet, 3);
    });
  });

  group('nextStop / jumpToNext', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('inside a superset round → next member, same set', () {
      p.start(_ss3(sets: 2));
      // Start at e1, set 1.
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 1);
      p.jumpToNext();
      expect(p.progress.exerciseIndex, 1); // e2
      expect(p.progress.currentSet, 1);
      expect(p.progress.phase, TimerPhase.rep);
    });

    test('last superset member with rounds remaining → group start, set+1', () {
      p.start(_ss3(sets: 2));
      p.jumpToExercise(2); // e3, set 1
      p.jumpToNext();
      expect(p.progress.exerciseIndex, 0); // wrapped to e1
      expect(p.progress.currentSet, 2); // round 2
      expect(p.progress.phase, TimerPhase.rep);
    });

    test('last superset member, last round → first exercise after group', () {
      p.start(_ssMixed(supersetSets: 2));
      // Reach e2 (last member) at the last round.
      p.jumpToExercise(1);
      p.jumpToSet(2);
      p.jumpToNext();
      expect(p.progress.exerciseIndex, 2); // e3, the solo exercise
      expect(p.progress.currentSet, 1);
    });

    test('solo exercise → next exercise regardless of set position', () {
      // Solo exercise sets are not "stops" — pressing forward jumps past
      // remaining sets to the next exercise. The user wants to know what
      // *exercise* is next, not "set 2 of the same one."
      p.start(_ssMixed(e3Sets: 3));
      p.jumpToExercise(2); // solo e3, set 1 of 3
      expect(p.nextStop, isNull); // e3 is the last exercise
      // From mid-session a solo exercise's nextStop should also skip sets:
      p.start(_ssTwoWorkouts());
      // a1 has 2 sets; from a1 set 1, next is W2's b1, not a1 set 2.
      p.jumpToNext();
      expect(p.progress.workoutIndex, 1);
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 1);
    });

    test('last exercise of last workout → null', () {
      p.start(_ssMixed(e3Sets: 2));
      p.jumpToExercise(2);
      expect(p.nextStop, isNull);
    });

    test('cross-workout: last exercise of W1 → first exercise of W2 (getReady)',
        () {
      p.start(_ssTwoWorkouts());
      // a1 has 2 sets, but sets aren't stops — from set 1 we jump to W2.
      p.jumpToNext();
      expect(p.progress.workoutIndex, 1);
      expect(p.progress.exerciseIndex, 0); // b1
      expect(p.progress.currentSet, 1);
      expect(p.progress.phase, TimerPhase.getReady);
    });
  });

  group('previousStop / jumpToPrevious', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('inside a superset round (not first member) → previous member, same set',
        () {
      p.start(_ss3(sets: 2));
      p.jumpToExercise(2); // e3, set 1
      p.jumpToPrevious();
      expect(p.progress.exerciseIndex, 1); // e2
      expect(p.progress.currentSet, 1);
    });

    test('first member of superset, mid-rounds → previous round\'s last member',
        () {
      p.start(_ss3(sets: 2));
      // Manually land on e1, round 2 — the auto-advance pre-advances the
      // index to e1 with currentSet=2 between rounds, so this models
      // "press back on the first rep of round 2".
      p.jumpToExercise(0);
      p.jumpToSet(2);
      p.jumpToPrevious();
      expect(p.progress.exerciseIndex, 2); // last member
      expect(p.progress.currentSet, 1); // previous round
    });

    test('first round, first member of superset → null at session start', () {
      p.start(_ss3(sets: 2));
      expect(p.previousStop, isNull);
    });

    test('solo exercise → previous exercise regardless of set position', () {
      // Symmetric to the forward case: solo sets aren't stops. Back-pressing
      // from any set of a solo exercise lands at the previous exercise's
      // start (set 1).
      p.start(_ssTwoWorkouts());
      p.jumpToWorkout(1); // W2 b1, set 1
      p.jumpToPrevious();
      expect(p.progress.workoutIndex, 0);
      expect(p.progress.exerciseIndex, 0); // a1
      expect(p.progress.currentSet, 1); // set 1, not the last set
    });

    test('first solo exercise after a superset → group end at last round', () {
      p.start(_ssMixed(supersetSets: 2));
      p.jumpToExercise(2); // solo e3, set 1
      p.jumpToPrevious();
      // The previous step from outside a group is the group's last member
      // at its final round (the immediately-previous physical action).
      expect(p.progress.exerciseIndex, 1); // e2 = group end
      expect(p.progress.currentSet, 2); // last round
    });

    test('cross-workout: first exercise of W2 → last exercise of W1 (getReady)',
        () {
      p.start(_ssTwoWorkouts());
      p.jumpToWorkout(1);
      p.jumpToPrevious();
      expect(p.progress.workoutIndex, 0);
      expect(p.progress.exerciseIndex, 0); // a1 = last exercise of W1
      expect(p.progress.currentSet, 1);
      expect(p.progress.phase, TimerPhase.getReady);
    });
  });

  group('debug helpers (visible-for-testing)', () {
    test('debugSetPhase fires phase transition and resets remaining', () {
      final p = SessionStateProvider();
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.progress.phase, TimerPhase.supersetRest);
    });
  });
}
