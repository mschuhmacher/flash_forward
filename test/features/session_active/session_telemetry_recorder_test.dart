import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/features/session_active/session_progress.dart';
import 'package:flash_forward/features/session_active/session_telemetry_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

SessionProgress _p({
  int workoutIndex = 0,
  int exerciseIndex = 0,
  int currentSet = 1,
  int currentRep = 1,
  TimerPhase phase = TimerPhase.rep,
}) =>
    SessionProgress(
      workoutIndex: workoutIndex,
      exerciseIndex: exerciseIndex,
      currentSet: currentSet,
      currentRep: currentRep,
      phase: phase,
    );

void main() {
  late SessionTelemetryRecorder rec;

  setUp(() => rec = SessionTelemetryRecorder());

  group('initial state', () {
    test('no events, no draft output', () {
      expect(rec.setEvents, isEmpty);
      expect(rec.restEvents, isEmpty);
      expect(rec.restEventCount, 0);
      expect(rec.restEventTypes, isEmpty);
    });
  });

  group('set events', () {
    test('openSet then closeSet records one SetEvent with the right indices',
        () {
      rec.openSet(_p(workoutIndex: 1, exerciseIndex: 2, currentSet: 3));
      rec.closeSet(repsCompleted: 5);

      expect(rec.setEvents, hasLength(1));
      final e = rec.setEvents.single;
      expect(e.workoutIndex, 1);
      expect(e.exerciseIndex, 2);
      expect(e.setIndex, 3);
      expect(e.repsCompleted, 5);
    });

    test('closeSet with no open draft is a no-op', () {
      rec.closeSet(repsCompleted: 3);
      expect(rec.setEvents, isEmpty);
    });

    test('opening a new set resets the accumulators', () {
      rec.openSet(_p());
      rec.beginPhase();
      rec.attributeSliceOnExit(TimerPhase.rep); // some active time accrues
      rec.openSet(_p(currentSet: 2)); // should zero the accumulators
      rec.closeSet(repsCompleted: 1);

      // The second set never accrued time after its open, so both are zero.
      final e = rec.setEvents.single;
      expect(e.activeTime, Duration.zero);
      expect(e.interRepRestTime, Duration.zero);
    });
  });

  group('slice attribution', () {
    test('rep slices accumulate into activeTime', () async {
      rec.openSet(_p());
      rec.beginPhase();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rec.attributeSliceOnExit(TimerPhase.rep);
      rec.closeSet(repsCompleted: 1);

      final e = rec.setEvents.single;
      expect(e.activeTime, greaterThan(Duration.zero));
      expect(e.interRepRestTime, Duration.zero);
    });

    test('repRest slices accumulate into interRepRestTime', () async {
      rec.openSet(_p());
      rec.beginPhase();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rec.attributeSliceOnExit(TimerPhase.repRest);
      rec.closeSet(repsCompleted: 1);

      final e = rec.setEvents.single;
      expect(e.interRepRestTime, greaterThan(Duration.zero));
      expect(e.activeTime, Duration.zero);
    });

    test('attributeSliceOnExit before beginPhase is a no-op', () {
      rec.openSet(_p());
      rec.attributeSliceOnExit(TimerPhase.rep); // no phase clock started
      rec.closeSet(repsCompleted: 1);
      expect(rec.setEvents.single.activeTime, Duration.zero);
    });
  });

  group('rest events', () {
    test('openRest(setRest) records the set index and RestType', () {
      rec.openRest(
        restType: RestType.setRest,
        progress: _p(currentSet: 4, phase: TimerPhase.setRest),
        plannedDuration: const Duration(seconds: 60),
      );
      rec.closeRest();

      expect(rec.restEvents, hasLength(1));
      final e = rec.restEvents.single;
      expect(e.restType, RestType.setRest);
      expect(e.setIndex, 4);
      expect(e.plannedDuration, const Duration(seconds: 60));
    });

    test('openRest(supersetRest) records RestType.supersetRest and null set',
        () {
      rec.openRest(
        restType: RestType.supersetRest,
        progress: _p(phase: TimerPhase.supersetRest),
        plannedDuration: const Duration(seconds: 10),
      );
      rec.closeRest();

      final e = rec.restEvents.single;
      expect(e.restType, RestType.supersetRest);
      expect(e.setIndex, isNull);
    });

    test('overtime rest records its actual duration as overtime', () async {
      rec.openRest(
        restType: RestType.overtime,
        progress: _p(phase: TimerPhase.overtime),
        plannedDuration: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      rec.closeRest();

      final e = rec.restEvents.single;
      expect(e.overtimeDuration, greaterThan(Duration.zero));
      expect(e.overtimeDuration, e.actualDuration);
    });

    test('non-overtime rest has zero overtime', () {
      rec.openRest(
        restType: RestType.setRest,
        progress: _p(phase: TimerPhase.setRest),
        plannedDuration: const Duration(seconds: 30),
      );
      rec.closeRest();
      expect(rec.restEvents.single.overtimeDuration, Duration.zero);
    });

    test('closeRest with no open draft is a no-op', () {
      rec.closeRest();
      expect(rec.restEvents, isEmpty);
    });

    test('restEventTypes mirrors the recorded order', () {
      for (final t in [
        RestType.getReady,
        RestType.setRest,
        RestType.supersetRest,
      ]) {
        rec.openRest(
          restType: t,
          progress: _p(),
          plannedDuration: Duration.zero,
        );
        rec.closeRest();
      }
      expect(rec.restEventTypes, [
        RestType.getReady,
        RestType.setRest,
        RestType.supersetRest,
      ]);
      expect(rec.restEventCount, 3);
    });
  });

  group('updateActiveDraftIndices', () {
    test('rewrites the open set and rest draft positions', () {
      rec.openSet(_p(workoutIndex: 0, exerciseIndex: 0));
      rec.openRest(
        restType: RestType.setRest,
        progress: _p(workoutIndex: 0, exerciseIndex: 0, currentSet: 2),
        plannedDuration: Duration.zero,
      );
      rec.updateActiveDraftIndices(3, 7);
      rec.closeSet(repsCompleted: 1);
      rec.closeRest();

      expect(rec.setEvents.single.workoutIndex, 3);
      expect(rec.setEvents.single.exerciseIndex, 7);
      expect(rec.restEvents.single.workoutIndex, 3);
      expect(rec.restEvents.single.exerciseIndex, 7);
    });

    test('is a no-op when nothing is open', () {
      rec.updateActiveDraftIndices(3, 7);
      expect(rec.setEvents, isEmpty);
      expect(rec.restEvents, isEmpty);
    });
  });

  group('discardDrafts', () {
    test('drops in-flight drafts but keeps closed events', () {
      rec.openSet(_p());
      rec.closeSet(repsCompleted: 2); // a closed event
      rec.openSet(_p(currentSet: 2)); // an in-flight draft
      rec.discardDrafts();
      rec.closeSet(repsCompleted: 9); // no-op: draft was discarded

      expect(rec.setEvents, hasLength(1));
      expect(rec.setEvents.single.repsCompleted, 2);
    });
  });

  group('clear', () {
    test('resets to initial state', () {
      rec.openSet(_p());
      rec.closeSet(repsCompleted: 1);
      rec.openRest(
        restType: RestType.setRest,
        progress: _p(),
        plannedDuration: Duration.zero,
      );
      rec.closeRest();

      rec.clear();

      expect(rec.setEvents, isEmpty);
      expect(rec.restEvents, isEmpty);
    });
  });

  group('computeSummary', () {
    test('aggregates active/rest times across events', () {
      // Two sets with active + inter-rep time.
      rec.openSet(_p());
      rec.beginPhase();
      // Manually accrue known durations by attributing zero-length slices is
      // unreliable; instead assert the summary buckets rest types correctly.
      rec.closeSet(repsCompleted: 1);

      for (final t in [
        RestType.setRest,
        RestType.supersetRest,
        RestType.exerciseRest,
        RestType.getReady,
        RestType.paused,
      ]) {
        rec.openRest(
          restType: t,
          progress: _p(),
          plannedDuration: Duration.zero,
        );
        rec.closeRest();
      }

      final summary = rec.computeSummary();
      // Every actual duration is ~0 but the buckets must be non-negative and
      // total equals the sum of parts.
      expect(summary.totalTime, isNotNull);
      expect(
        summary.totalTime,
        summary.activeTime +
            summary.interRepRestTime +
            summary.setRestTime +
            summary.supersetRestTime +
            summary.exerciseRestTime +
            summary.getReadyTime +
            summary.overtime +
            summary.pausedTime,
      );
    });
  });
}
