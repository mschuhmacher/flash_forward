import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/features/session_active/session_progress.dart';
import 'package:flash_forward/features/session_active/session_state_provider.dart';
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

    test('ticker is 100ms interval', () async {
      // Use a debug entry point if available, or assert indirectly by
      // measuring tick rate. We assert indirectly: after starting a
      // session and waiting ~250ms, the notifier should have been
      // updated multiple times. With a 1s tick interval, only 0-1
      // updates would happen in 250ms.
      final p = SessionStateProvider()..start(fixture);
      // start() puts us in getReady with ~10s remaining; ticker is running.
      var updateCount = 0;
      p.timerDisplayNotifier.addListener(() => updateCount++);
      await Future.delayed(const Duration(milliseconds: 350));
      // At 100ms interval we expect ~3 updates in 350ms. Be generous to
      // accommodate scheduling jitter — assert >= 2.
      expect(updateCount, greaterThanOrEqualTo(2));
      p.dispose();
    });

    test('per-tick changes to _remaining do not fire notifyListeners', () async {
      // The whole point of the refactor: ChangeNotifier listeners (i.e.
      // Consumer widgets) should NOT rebuild on every tick — only on
      // phase transitions and user actions. The notifier listener (the
      // timer widget) should rebuild every tick.
      final p = SessionStateProvider()..start(fixture);
      // Allow the ticker to warm up; attach listeners after the first few
      // ticks so we measure steady-state behavior.
      await Future.delayed(const Duration(milliseconds: 50));

      var changeNotifierFires = 0;
      var notifierFires = 0;
      p.addListener(() => changeNotifierFires++);
      p.timerDisplayNotifier.addListener(() => notifierFires++);

      // Wait less than the getReady duration (10s) so no phase transition.
      await Future.delayed(const Duration(milliseconds: 350));

      // ValueNotifier should have fired multiple times (one per tick).
      expect(notifierFires, greaterThanOrEqualTo(2));
      // ChangeNotifier should NOT have fired — no phase transition occurred.
      expect(changeNotifierFires, 0);

      p.dispose();
    });
  });
}
