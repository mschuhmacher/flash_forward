import 'package:flash_forward/models/set_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SetEvent', () {
    final fixture = SetEvent(
      workoutIndex: 0,
      exerciseIndex: 1,
      setIndex: 2,
      startAt: DateTime.utc(2026, 4, 14, 10, 0, 0),
      endAt: DateTime.utc(2026, 4, 14, 10, 1, 30),
      activeTime: const Duration(seconds: 40),
      interRepRestTime: const Duration(seconds: 30),
      repsCompleted: 8,
    );

    test('SetEvent round-trip json', () {
      final restored = SetEvent.fromJson(fixture.toJson());
      expect(restored.workoutIndex, fixture.workoutIndex);
      expect(restored.exerciseIndex, fixture.exerciseIndex);
      expect(restored.setIndex, fixture.setIndex);
      expect(restored.startAt, fixture.startAt);
      expect(restored.endAt, fixture.endAt);
      expect(restored.activeTime, fixture.activeTime);
      expect(restored.interRepRestTime, fixture.interRepRestTime);
      expect(restored.repsCompleted, fixture.repsCompleted);
    });
    test('SetEvent formatting', () {
      final json = fixture.toJson();
      expect(json['startAt'], '2026-04-14T10:00:00.000Z');
      expect(json['endAt'], '2026-04-14T10:01:30.000Z');
      expect(json['activeTimeSeconds'], 40);
      expect(json['interRepRestTimeSeconds'], 30);
    });
  });
}
