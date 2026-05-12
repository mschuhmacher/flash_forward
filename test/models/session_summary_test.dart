import 'package:flash_forward/models/session_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummary', () {
    const fixture = SessionSummary(
      totalTime: Duration(minutes: 30),
      activeTime: Duration(minutes: 8),
      interRepRestTime: Duration(minutes: 4),
      setRestTime: Duration(minutes: 10),
      exerciseRestTime: Duration(minutes: 5),
      getReadyTime: Duration(seconds: 30),
      overtime: Duration(minutes: 2),
      pausedTime: Duration(seconds: 30),
    );

    test('toJson round-trips via fromJson', () {
      final restored = SessionSummary.fromJson(fixture.toJson());
      expect(restored.totalTime, fixture.totalTime);
      expect(restored.activeTime, fixture.activeTime);
      expect(restored.interRepRestTime, fixture.interRepRestTime);
      expect(restored.setRestTime, fixture.setRestTime);
      expect(restored.exerciseRestTime, fixture.exerciseRestTime);
      expect(restored.getReadyTime, fixture.getReadyTime);
      expect(restored.overtime, fixture.overtime);
      expect(restored.pausedTime, fixture.pausedTime);
    });
  });
}
