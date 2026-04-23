import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Overtime tests', () {
    final fixture = Session(
      title: 'test',
      label: 'other',
      workouts: [
        Workout(
          title: 'WorkoutTitle',
          label: 'Other',
          exercises: [
            Exercise(
              title: 'ExerciseTitle',
              description: 'TestDescription',
              label: 'Other',
              sets: 2,
              reps: 10,
            ),
          ],
          timeBetweenExercises: 100,
        ),
      ],
    );

    group('RequestManualOvertime return true for eligible phases', () {
      test('setRest', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.setRest);
        expect(p.requestManualOvertime(), true);
      });
      test('exerciseRest', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.exerciseRest);
        expect(p.requestManualOvertime(), true);
      });
      test('getReady', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.getReady);
        expect(p.requestManualOvertime(), true);
      });
      test('check values on success', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.getReady); // Eligible phase
        p.requestManualOvertime();
        expect(p.phase, TimerPhase.overtime);
        expect(p.overtimeElapsed, Duration.zero);
        expect(p.remaining, Duration.zero);
      });
    });
    group('RequestManualOvertime return false for ineligible phases', () {
      test('rep', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.rep);
        expect(p.requestManualOvertime(), false);
      });
      test('repRest', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.repRest);
        expect(p.requestManualOvertime(), false);
      });
      test('paused', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.paused);
        expect(p.requestManualOvertime(), false);
      });
      test('workoutComplete', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.workoutComplete);
        expect(p.requestManualOvertime(), false);
      });
      test('overtime', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.overtime);
        expect(p.requestManualOvertime(), false);
      });
    });

    group('ExitOvertime tests', () {
      test('setRest', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.setRest);
        p.requestManualOvertime();
        p.exitOvertime();
        expect(p.phase, TimerPhase.getReady);
        expect(p.remaining, Duration(seconds: 10));
      });
      test('exerciseRest', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.exerciseRest);
        p.requestManualOvertime();
        p.exitOvertime();
        expect(p.phase, TimerPhase.getReady);
        expect(p.remaining, Duration(seconds: 10));
      });
      test('getReady', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.getReady);
        p.requestManualOvertime();
        p.exitOvertime();
        expect(p.phase, TimerPhase.getReady);
        expect(p.remaining, const Duration(seconds: 10));
      });
      test('not in overtime', () {
        final p = SessionStateProvider()..start(fixture);
        p.debugSetPhase(TimerPhase.setRest);
        p.exitOvertime();
        expect(p.phase, TimerPhase.setRest);
      });
    });
  });
}
