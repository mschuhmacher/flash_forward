import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timerDisplayNotifier', () {
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
              timeBetweenSets: 10,
            ),
          ],
          timeBetweenExercises: 100,
        ),
      ],
    );

    test('exists as a ValueNotifier<Duration> initialized to zero', () {
      final p = SessionStateProvider();
      expect(p.timerDisplayNotifier, isA<ValueNotifier<Duration>>());
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });

    test('start() syncs notifier to initial getReady duration', () {
      final p = SessionStateProvider()..start(fixture);
      // After start, phase is getReady with default 10s duration.
      expect(p.phase, TimerPhase.getReady);
      expect(p.remaining, p.timerDisplayNotifier.value);
      expect(p.timerDisplayNotifier.value, greaterThan(Duration.zero));
    });

    test('reset() syncs notifier to Duration.zero', () {
      final p = SessionStateProvider()..start(fixture);
      p.reset();
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });

    test('debugSetPhase() syncs notifier to new phase duration', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.setRest);
      // Phase changed → notifier should reflect the new _remaining for setRest.
      expect(p.timerDisplayNotifier.value, p.remaining);
      expect(p.timerDisplayNotifier.value, greaterThan(Duration.zero));
    });

    test('requestManualOvertime() syncs notifier to overtimeElapsed (zero)', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.getReady);
      p.requestManualOvertime();
      // In overtime, the notifier publishes _overtimeElapsed (starts at 0).
      expect(p.phase, TimerPhase.overtime);
      expect(p.timerDisplayNotifier.value, p.overtimeElapsed);
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });

    test('exitOvertime() syncs notifier back to _remaining', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.getReady);
      p.requestManualOvertime();
      expect(p.phase, TimerPhase.overtime);
      p.exitOvertime();
      // After exitOvertime, phase is back to getReady with fresh 10s.
      expect(p.phase, TimerPhase.getReady);
      expect(p.timerDisplayNotifier.value, p.remaining);
      expect(p.timerDisplayNotifier.value, const Duration(seconds: 10));
    });
  });
}
