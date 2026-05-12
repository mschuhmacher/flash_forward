import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session', () {
    final fixture = Session(title: 'test', label: 'other', workouts: []);

    test('New Session has null telemetry keys', () {
      expect(fixture.setEvents, null);
      expect(fixture.restEvents, null);
      expect(fixture.summary, null);
    });
    test('fromJson tolerates missing telemetry keys', () {
      final json = {
        'id': 'x',
        'title': 'test',
        'label': 'other',
        'workouts': [],
      };
      final s = Session.fromJson(json);
      expect(s.setEvents, null);
      expect(s.restEvents, null);
      expect(s.summary, null);
    });
    test('toJson / fromJson round-trips telemetry fields', () {
      final setEvents = [
        SetEvent(
          workoutIndex: 1,
          exerciseIndex: 2,
          setIndex: 3,
          startAt: DateTime.utc(2026, 1, 1),
          endAt: DateTime.utc(2027, 1, 1),
          activeTime: const Duration(seconds: 100),
          interRepRestTime: const Duration(seconds: 200),
          repsCompleted: 10,
        ),
      ];
      final restEvents = [
        RestEvent(
          restType: RestType.overtime,
          workoutIndex: 0,
          exerciseIndex: 1,
          setIndex: 2,
          startAt: DateTime.utc(2026, 1, 1),
          endAt: DateTime.utc(2027, 1, 1),
          plannedDuration: const Duration(seconds: 100),
          actualDuration: const Duration(seconds: 200),
          overtimeDuration: const Duration(seconds: 100),
        ),
      ];
      final sessionSummary = SessionSummary(
        totalTime: Duration(seconds: 100),
        activeTime: Duration(seconds: 100),
        interRepRestTime: Duration(seconds: 100),
        setRestTime: Duration(seconds: 100),
        exerciseRestTime: Duration(seconds: 100),
        getReadyTime: Duration(seconds: 100),
        overtime: Duration(seconds: 100),
        pausedTime: Duration(seconds: 100),
      );
      final session = Session(
        title: 'test',
        label: 'other',
        workouts: [],
        setEvents: setEvents,
        restEvents: restEvents,
        summary: sessionSummary,
      );
      final restored = Session.fromJson(session.toJson());
      expect(restored.setEvents?.length, setEvents.length);
      expect(restored.restEvents?.length, restEvents.length);
      expect(restored.summary?.totalTime, sessionSummary.totalTime);
    });
  });
}
