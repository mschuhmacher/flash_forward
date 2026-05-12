import 'package:flash_forward/models/rest_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RestEvent', () {
    final fixture = RestEvent(
      restType: RestType.overtime,
      workoutIndex: 0,
      exerciseIndex: 1,
      setIndex: 2,
      startAt: DateTime.utc(2026, 4, 14, 10, 0, 0),
      endAt: DateTime.utc(2026, 4, 14, 10, 0, 45),
      plannedDuration: Duration.zero,
      actualDuration: const Duration(seconds: 45),
      overtimeDuration: const Duration(seconds: 45),
    );

    test('toJson round-trips via fromJson', () {
      final restored = RestEvent.fromJson(fixture.toJson());
      expect(restored.restType, fixture.restType);
      expect(restored.workoutIndex, fixture.workoutIndex);
      expect(restored.exerciseIndex, fixture.exerciseIndex);
      expect(restored.setIndex, fixture.setIndex);
      expect(restored.startAt, fixture.startAt);
      expect(restored.endAt, fixture.endAt);
      expect(restored.plannedDuration, fixture.plannedDuration);
      expect(restored.actualDuration, fixture.actualDuration);
      expect(restored.overtimeDuration, fixture.overtimeDuration);
    });

    test('fromJson tolerates null setIndex', () {
      final json = fixture.toJson()..['setIndex'] = null;
      final restored = RestEvent.fromJson(json);
      expect(restored.setIndex, isNull);
    });

    test('restType serializes as its enum name', () {
      expect(fixture.toJson()['restType'], 'overtime');
    });
  });
}
