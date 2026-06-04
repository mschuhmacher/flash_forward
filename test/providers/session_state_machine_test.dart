import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/providers/session_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fixture builders ─────────────────────────────────────────────────
//
// These mirror the constructors used in session_state_provider_superset_test
// and event_log_test, but expose the knobs the state machine branches read:
// exercise type, reps, the inter-rep/inter-set/active durations, and the
// superset config fields (restSeconds, supersetSets, supersetSetRest).

Exercise _fixed(String id, {int sets = 2, int activeTime = 30}) => Exercise(
      id: id,
      title: id,
      description: 'd',
      label: 'l',
      type: ExerciseType.fixedDuration,
      sets: sets,
      activeTime: activeTime,
      timeBetweenSets: 60,
    );

Exercise _timed(
  String id, {
  int sets = 2,
  int reps = 3,
  int timeBetweenReps = 5,
  int timePerRep = 4,
  int timeBetweenSets = 60,
}) =>
    Exercise(
      id: id,
      title: id,
      description: 'd',
      label: 'l',
      type: ExerciseType.timedReps,
      sets: sets,
      reps: reps,
      timePerRep: timePerRep,
      timeBetweenReps: timeBetweenReps,
      timeBetweenSets: timeBetweenSets,
    );

Exercise _manual(String id, {int sets = 2}) => Exercise(
      id: id,
      title: id,
      description: 'd',
      label: 'l',
      type: ExerciseType.manual,
      sets: sets,
    );

/// Single workout of solo exercises (no supersets).
Session _solo(List<Exercise> exercises, {int timeBetweenExercises = 120}) =>
    Session(title: 't', label: 'l', workouts: [
      Workout(
        title: 'W',
        label: 'l',
        timeBetweenExercises: timeBetweenExercises,
        exercises: exercises,
        supersets: const [],
      ),
    ]);

/// Single workout where [e1, e2] form a superset block.
Session _superset({
  int sets = 2,
  int restSeconds = 10,
  int? supersetSets,
  int? supersetSetRest,
  int timeBetweenExercises = 120,
}) =>
    Session(title: 't', label: 'l', workouts: [
      Workout(
        title: 'W',
        label: 'l',
        timeBetweenExercises: timeBetweenExercises,
        exercises: [_fixed('e1', sets: sets), _fixed('e2', sets: sets)],
        supersets: [
          SupersetConfig(
            id: 'ss1',
            exerciseIds: const ['e1', 'e2'],
            restSeconds: restSeconds,
            supersetSets: supersetSets,
            supersetSetRest: supersetSetRest,
          ),
        ],
      ),
    ]);

/// Two workouts: W1 = [a1] solo, W2 = [b1] solo. For cross-workout cases.
Session _twoWorkouts() => Session(title: 't', label: 'l', workouts: [
      Workout(
        title: 'W1',
        label: 'l',
        timeBetweenExercises: 120,
        exercises: [_fixed('a1', sets: 2)],
        supersets: const [],
      ),
      Workout(
        title: 'W2',
        label: 'l',
        timeBetweenExercises: 120,
        exercises: [_fixed('b1', sets: 2)],
        supersets: const [],
      ),
    ]);

SessionProgress _p({
  int workoutIndex = 0,
  int exerciseIndex = 0,
  int currentSet = 1,
  int currentRep = 1,
  required TimerPhase phase,
}) =>
    SessionProgress(
      workoutIndex: workoutIndex,
      exerciseIndex: exerciseIndex,
      currentSet: currentSet,
      currentRep: currentRep,
      phase: phase,
    );

void main() {
  group('calculateNextState', () {
    test('timedReps rep → repRest when more reps remain', () {
      final s = _solo([_timed('e1', reps: 3, timeBetweenReps: 5)]);
      final next = SessionStateMachine.calculateNextState(
        _p(currentRep: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next!.phase, TimerPhase.repRest);
      expect(next.currentRep, 1); // bump happens on repRest→rep, not here
    });

    test('repRest → rep increments the rep counter', () {
      final s = _solo([_timed('e1', reps: 3, timeBetweenReps: 5)]);
      final next = SessionStateMachine.calculateNextState(
        _p(currentRep: 1, phase: TimerPhase.repRest),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
      expect(next.currentRep, 2);
    });

    test('timedReps with timeBetweenReps == 0 skips repRest', () {
      // reps remain, but no inter-rep rest → recursion resolves straight to
      // the next rep rather than parking in repRest.
      final s = _solo([_timed('e1', reps: 3, timeBetweenReps: 0)]);
      final next = SessionStateMachine.calculateNextState(
        _p(currentRep: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
      expect(next.currentRep, 2);
    });

    test('fixedDuration rep → setRest when more sets remain (solo)', () {
      final s = _solo([_fixed('e1', sets: 3)]);
      final next = SessionStateMachine.calculateNextState(
        _p(currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next!.phase, TimerPhase.setRest);
      expect(next.exerciseIndex, 0); // setRest stays on the same exercise
    });

    test('setRest → rep bumps the set (solo)', () {
      final s = _solo([_fixed('e1', sets: 3)]);
      final next = SessionStateMachine.calculateNextState(
        _p(currentSet: 1, phase: TimerPhase.setRest),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
      expect(next.currentSet, 2);
    });

    test('setRest on last set → exerciseRest at next exercise', () {
      final s = _solo([_fixed('e1', sets: 2), _fixed('e2', sets: 2)]);
      final next = SessionStateMachine.calculateNextState(
        _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.setRest),
        s,
      );
      expect(next!.phase, TimerPhase.exerciseRest);
      expect(next.exerciseIndex, 1); // pre-advanced to e2
    });

    test('supersetRest → rep (same progress, new phase)', () {
      final s = _superset();
      final next = SessionStateMachine.calculateNextState(
        _p(exerciseIndex: 1, phase: TimerPhase.supersetRest),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
      expect(next.exerciseIndex, 1);
    });

    test('getReady → rep', () {
      final s = _solo([_fixed('e1')]);
      final next = SessionStateMachine.calculateNextState(
        _p(phase: TimerPhase.getReady),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
    });

    test('exerciseRest → rep within the same workout', () {
      // exerciseIndex already points at the upcoming exercise (set on entry).
      final s = _solo([_fixed('e1'), _fixed('e2')]);
      final next = SessionStateMachine.calculateNextState(
        _p(exerciseIndex: 1, currentSet: 1, phase: TimerPhase.exerciseRest),
        s,
      );
      expect(next!.phase, TimerPhase.rep);
    });

    test('exerciseRest → getReady on a cross-workout boundary', () {
      // currentSet == 1 && exerciseIndex == 0 is the cross-workout signal.
      final s = _twoWorkouts();
      final next = SessionStateMachine.calculateNextState(
        _p(
          workoutIndex: 1,
          exerciseIndex: 0,
          currentSet: 1,
          phase: TimerPhase.exerciseRest,
        ),
        s,
      );
      expect(next!.phase, TimerPhase.getReady);
    });

    test('end of session returns null', () {
      // Last set of the only exercise → no next exercise → null.
      final s = _solo([_fixed('e1', sets: 2)]);
      final next = SessionStateMachine.calculateNextState(
        _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.setRest),
        s,
      );
      expect(next, isNull);
    });

    test('manual rep returns null (driven only by advanceManually)', () {
      final s = _solo([_manual('e1')]);
      final next = SessionStateMachine.calculateNextState(
        _p(phase: TimerPhase.rep),
        s,
      );
      expect(next, isNull);
    });
  });

  group('getDurationForPhase', () {
    test('rep duration per exercise type', () {
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.rep),
          _solo([_timed('e1', timePerRep: 4)]),
        ),
        const Duration(seconds: 4),
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.rep),
          _solo([_fixed('e1', activeTime: 30)]),
        ),
        const Duration(seconds: 30),
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.rep),
          _solo([_manual('e1')]),
        ),
        Duration.zero,
      );
    });

    test('repRest and setRest read the exercise durations', () {
      final s = _solo([_timed('e1', timeBetweenReps: 5, timeBetweenSets: 60)]);
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.repRest),
          s,
        ),
        const Duration(seconds: 5),
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.setRest),
          s,
        ),
        const Duration(seconds: 60),
      );
    });

    test('supersetRest reads the config restSeconds', () {
      final s = _superset(restSeconds: 25);
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(exerciseIndex: 1, phase: TimerPhase.supersetRest),
          s,
        ),
        const Duration(seconds: 25),
      );
    });

    // The load-bearing branch: exerciseRest duration depends on whether this
    // is a normal between-exercise rest or a superset between-rounds rest.
    // The condition is `superset != null && currentSet > 1`. The two cases
    // below differ ONLY in currentSet, proving the conditional matters.
    test('exerciseRest at currentSet 1 uses workout.timeBetweenExercises', () {
      final s = _superset(
        supersetSetRest: 45,
        timeBetweenExercises: 120,
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(exerciseIndex: 0, currentSet: 1, phase: TimerPhase.exerciseRest),
          s,
        ),
        const Duration(seconds: 120),
      );
    });

    test('exerciseRest between superset rounds uses supersetSetRest', () {
      final s = _superset(
        supersetSetRest: 45,
        timeBetweenExercises: 120,
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.exerciseRest),
          s,
        ),
        const Duration(seconds: 45),
      );
    });

    test('between-rounds rest falls back to timeBetweenExercises when '
        'supersetSetRest is null', () {
      final s = _superset(
        supersetSetRest: null,
        timeBetweenExercises: 120,
      );
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.exerciseRest),
          s,
        ),
        const Duration(seconds: 120),
      );
    });

    test('getReady is 10s; overtime/paused/complete are zero', () {
      final s = _solo([_fixed('e1')]);
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.getReady),
          s,
        ),
        const Duration(seconds: 10),
      );
      for (final phase in [
        TimerPhase.overtime,
        TimerPhase.paused,
        TimerPhase.workoutComplete,
      ]) {
        expect(
          SessionStateMachine.getDurationForPhase(_p(phase: phase), s),
          Duration.zero,
          reason: '$phase should be zero',
        );
      }
    });

    test('null session returns zero', () {
      expect(
        SessionStateMachine.getDurationForPhase(
          _p(phase: TimerPhase.rep),
          null,
        ),
        Duration.zero,
      );
    });
  });

  group('isOvertimeEligible', () {
    test('true only for setRest/exerciseRest/getReady', () {
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.setRest), isTrue);
      expect(
        SessionStateMachine.isOvertimeEligible(TimerPhase.exerciseRest),
        isTrue,
      );
      expect(
        SessionStateMachine.isOvertimeEligible(TimerPhase.getReady),
        isTrue,
      );
      for (final phase in [
        TimerPhase.rep,
        TimerPhase.repRest,
        TimerPhase.supersetRest,
        TimerPhase.overtime,
        TimerPhase.paused,
        TimerPhase.workoutComplete,
      ]) {
        expect(
          SessionStateMachine.isOvertimeEligible(phase),
          isFalse,
          reason: '$phase should be ineligible',
        );
      }
    });
  });

  group('isRestPhase', () {
    test('true for rest-like phases, false for rep/repRest/complete', () {
      for (final phase in [
        TimerPhase.getReady,
        TimerPhase.setRest,
        TimerPhase.supersetRest,
        TimerPhase.exerciseRest,
        TimerPhase.overtime,
        TimerPhase.paused,
      ]) {
        expect(
          SessionStateMachine.isRestPhase(phase),
          isTrue,
          reason: '$phase should be a rest phase',
        );
      }
      for (final phase in [
        TimerPhase.rep,
        TimerPhase.repRest,
        TimerPhase.workoutComplete,
      ]) {
        expect(
          SessionStateMachine.isRestPhase(phase),
          isFalse,
          reason: '$phase should not be a rest phase',
        );
      }
    });
  });

  group('matchRestTypeToTimerPhase', () {
    test('maps each rest phase to its RestType', () {
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.getReady),
        RestType.getReady,
      );
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.setRest),
        RestType.setRest,
      );
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.supersetRest),
        RestType.supersetRest,
      );
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.exerciseRest),
        RestType.exerciseRest,
      );
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.overtime),
        RestType.overtime,
      );
      expect(
        SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.paused),
        RestType.paused,
      );
    });

    test('throws on a non-rest phase', () {
      expect(
        () => SessionStateMachine.matchRestTypeToTimerPhase(TimerPhase.rep),
        throwsStateError,
      );
    });
  });

  group('enterPostSetRest', () {
    test('solo exercise → setRest at the same exercise', () {
      final s = _solo([_fixed('e1', sets: 3)]);
      final workout = s.workouts[0];
      final next = SessionStateMachine.enterPostSetRest(
        _p(exerciseIndex: 0, currentSet: 1, phase: TimerPhase.rep),
        workout,
        s,
      );
      expect(next.phase, TimerPhase.setRest);
      expect(next.exerciseIndex, 0);
      expect(next.currentSet, 1); // set bump happens later, in the setRest case
    });

    test('superset last member with more rounds → exerciseRest at group '
        'start with the set bumped', () {
      final s = _superset(supersetSets: 3);
      final workout = s.workouts[0];
      // Sitting on the last member (e2, index 1) of round 1.
      final next = SessionStateMachine.enterPostSetRest(
        _p(exerciseIndex: 1, currentSet: 1, phase: TimerPhase.rep),
        workout,
        s,
      );
      expect(next.phase, TimerPhase.exerciseRest);
      expect(next.exerciseIndex, 0); // pulled back to the group's first member
      expect(next.currentSet, 2); // next round
    });
  });

  group('enterExerciseRest', () {
    test('advances to the next exercise within the workout', () {
      final s = _solo([_fixed('e1'), _fixed('e2')]);
      final next = SessionStateMachine.enterExerciseRest(
        _p(exerciseIndex: 0, phase: TimerPhase.rep),
        s,
      );
      expect(next!.exerciseIndex, 1);
      expect(next.phase, TimerPhase.exerciseRest);
    });

    test('crosses into the next workout at exerciseIndex 0', () {
      final s = _twoWorkouts();
      final next = SessionStateMachine.enterExerciseRest(
        _p(workoutIndex: 0, exerciseIndex: 0, phase: TimerPhase.rep),
        s,
      );
      expect(next!.workoutIndex, 1);
      expect(next.exerciseIndex, 0);
      expect(next.phase, TimerPhase.exerciseRest);
    });

    test('returns null at the end of the session', () {
      final s = _solo([_fixed('e1')]);
      final next = SessionStateMachine.enterExerciseRest(
        _p(exerciseIndex: 0, phase: TimerPhase.rep),
        s,
      );
      expect(next, isNull);
    });
  });

  group('calculateNextStop', () {
    test('solo: skips to the next exercise (sets are not stops)', () {
      final s = _solo([_fixed('e1', sets: 3), _fixed('e2', sets: 3)]);
      final next = SessionStateMachine.calculateNextStop(
        _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.rep),
        s,
      );
      expect(next!.exerciseIndex, 1);
      expect(next.currentSet, 1); // lands at set 1 of the next exercise
    });

    test('superset: next member in the same round', () {
      final s = _superset();
      final next = SessionStateMachine.calculateNextStop(
        _p(exerciseIndex: 0, currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next!.exerciseIndex, 1); // e1 → e2
      expect(next.currentSet, 1);
    });

    test('superset: last member with more rounds wraps to group start, set+1',
        () {
      final s = _superset(supersetSets: 2);
      final next = SessionStateMachine.calculateNextStop(
        _p(exerciseIndex: 1, currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next!.exerciseIndex, 0); // wrap back to e1
      expect(next.currentSet, 2); // next round
    });

    test('superset: last member on the last round exits past the group', () {
      // e1+e2 superset (2 rounds), then a solo e3 after the block.
      final s = Session(title: 't', label: 'l', workouts: [
        Workout(
          title: 'W',
          label: 'l',
          timeBetweenExercises: 120,
          exercises: [_fixed('e1'), _fixed('e2'), _fixed('e3')],
          supersets: [
            SupersetConfig(
              id: 'ss1',
              exerciseIds: const ['e1', 'e2'],
              restSeconds: 10,
              supersetSets: 2,
            ),
          ],
        ),
      ]);
      final next = SessionStateMachine.calculateNextStop(
        _p(exerciseIndex: 1, currentSet: 2, phase: TimerPhase.rep),
        s,
      );
      expect(next!.exerciseIndex, 2); // exits to the solo e3
    });

    test('returns null at the end of the session', () {
      final s = _solo([_fixed('e1', sets: 2)]);
      final next = SessionStateMachine.calculateNextStop(
        _p(exerciseIndex: 0, currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(next, isNull);
    });
  });

  group('calculatePreviousStop', () {
    test('solo: steps back to the previous exercise', () {
      final s = _solo([_fixed('e1'), _fixed('e2')]);
      final prev = SessionStateMachine.calculatePreviousStop(
        _p(exerciseIndex: 1, currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(prev!.exerciseIndex, 0);
    });

    test('superset: earlier member of the same round', () {
      final s = _superset();
      final prev = SessionStateMachine.calculatePreviousStop(
        _p(exerciseIndex: 1, currentSet: 1, phase: TimerPhase.rep),
        s,
      );
      expect(prev!.exerciseIndex, 0); // e2 → e1
      expect(prev.currentSet, 1);
    });

    test('superset: first member on a later round wraps back to group end, '
        'set-1', () {
      final s = _superset(supersetSets: 2);
      final prev = SessionStateMachine.calculatePreviousStop(
        _p(exerciseIndex: 0, currentSet: 2, phase: TimerPhase.rep),
        s,
      );
      expect(prev!.exerciseIndex, 1); // back to e2 (group end)
      expect(prev.currentSet, 1); // previous round
    });

    test('stepping back into a superset block lands on group end at last round',
        () {
      // solo e0, then e1+e2 superset (2 rounds). From workoutComplete, the
      // previous stop re-enters the last real stop: the group's last member
      // at its final round.
      final s = Session(title: 't', label: 'l', workouts: [
        Workout(
          title: 'W',
          label: 'l',
          timeBetweenExercises: 120,
          exercises: [_fixed('e0'), _fixed('e1'), _fixed('e2')],
          supersets: [
            SupersetConfig(
              id: 'ss1',
              exerciseIds: const ['e1', 'e2'],
              restSeconds: 10,
              supersetSets: 2,
            ),
          ],
        ),
      ]);
      final prev = SessionStateMachine.calculatePreviousStop(
        _p(exerciseIndex: 0, phase: TimerPhase.workoutComplete),
        s,
      );
      expect(prev!.exerciseIndex, 2); // group end (e2)
      expect(prev.currentSet, 2); // last round
    });
  });

  group('firstStopAtOrAfter', () {
    test('within the workout returns a rep stop', () {
      final s = _solo([_fixed('e1'), _fixed('e2')]);
      final stop = SessionStateMachine.firstStopAtOrAfter(0, 1, s);
      expect(stop!.exerciseIndex, 1);
      expect(stop.phase, TimerPhase.rep);
    });

    test('off the end of a workout crosses to the next at getReady', () {
      final s = _twoWorkouts();
      final stop = SessionStateMachine.firstStopAtOrAfter(0, 1, s);
      expect(stop!.workoutIndex, 1);
      expect(stop.exerciseIndex, 0);
      expect(stop.phase, TimerPhase.getReady);
    });

    test('off the end of the last workout returns null', () {
      final s = _solo([_fixed('e1')]);
      expect(SessionStateMachine.firstStopAtOrAfter(0, 1, s), isNull);
    });
  });

  group('lastStopBefore', () {
    test('within the workout returns the previous exercise at rep', () {
      final s = _solo([_fixed('e1'), _fixed('e2')]);
      final stop = SessionStateMachine.lastStopBefore(0, 1, s);
      expect(stop!.exerciseIndex, 0);
      expect(stop.phase, TimerPhase.rep);
    });

    test('crosses back to the previous workout last exercise at getReady', () {
      final s = _twoWorkouts();
      final stop = SessionStateMachine.lastStopBefore(1, 0, s);
      expect(stop!.workoutIndex, 0);
      expect(stop.exerciseIndex, 0);
      expect(stop.phase, TimerPhase.getReady);
    });

    test('at the very start of the session returns null', () {
      final s = _solo([_fixed('e1')]);
      expect(SessionStateMachine.lastStopBefore(0, 0, s), isNull);
    });
  });
}
