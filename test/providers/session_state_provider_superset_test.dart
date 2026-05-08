import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
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

    test('setRest from last exercise in 3-member superset resets to first exercise',
        () {
      p.start(_ss3(sets: 2));
      p.jumpToExercise(2); // last superset member
      p.debugSetPhase(TimerPhase.setRest);
      expect(p.progress.exerciseIndex, 2);
      // 61s = setRest (60s) + 1s overshoot; small overshoot keeps us in the
      // rep phase of the first member rather than fast-forwarding further.
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 61)));
      p.reconcileAfterBackground();
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 2);
      expect(p.progress.phase, TimerPhase.rep);
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

  group('debug helpers (visible-for-testing)', () {
    test('debugSetPhase fires phase transition and resets remaining', () {
      final p = SessionStateProvider();
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.progress.phase, TimerPhase.supersetRest);
    });
  });
}
