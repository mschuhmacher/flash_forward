import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convertGrade', () {
    test('returns same entry when already in target system', () {
      const v = GradeEntry(system: GradeSystem.vscale, gradeIndex: 5);
      expect(convertGrade(v, GradeSystem.vscale), v);

      const f = GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 9);
      expect(convertGrade(f, GradeSystem.fontainebleau), f);
    });

    test('V0 converts to Font index 0', () {
      const v0 = GradeEntry(system: GradeSystem.vscale, gradeIndex: 0);
      final result = convertGrade(v0, GradeSystem.fontainebleau);
      expect(result, const GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 0));
    });

    test('V3 converts to Font index 3 (6A, first of [3,4])', () {
      const v3 = GradeEntry(system: GradeSystem.vscale, gradeIndex: 3);
      final result = convertGrade(v3, GradeSystem.fontainebleau);
      expect(result, const GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 3));
    });

    test('V17 converts to Font index 21 (9A)', () {
      const v17 = GradeEntry(system: GradeSystem.vscale, gradeIndex: 17);
      final result = convertGrade(v17, GradeSystem.fontainebleau);
      expect(result, const GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 21));
    });

    test('Font index 0 converts to V0', () {
      const f = GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 0);
      final result = convertGrade(f, GradeSystem.vscale);
      expect(result, const GradeEntry(system: GradeSystem.vscale, gradeIndex: 0));
    });

    test('Font index 4 (6A+) converts to V3', () {
      const f = GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 4);
      final result = convertGrade(f, GradeSystem.vscale);
      expect(result, const GradeEntry(system: GradeSystem.vscale, gradeIndex: 3));
    });

    test('Font index 21 (9A) converts to V17', () {
      const f = GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 21);
      final result = convertGrade(f, GradeSystem.vscale);
      expect(result, const GradeEntry(system: GradeSystem.vscale, gradeIndex: 17));
    });

    test('out-of-range V index returns null', () {
      const v = GradeEntry(system: GradeSystem.vscale, gradeIndex: 99);
      expect(convertGrade(v, GradeSystem.fontainebleau), isNull);
    });

    test('negative V index returns null', () {
      const v = GradeEntry(system: GradeSystem.vscale, gradeIndex: -1);
      expect(convertGrade(v, GradeSystem.fontainebleau), isNull);
    });

    test('out-of-range Font index returns null', () {
      const f = GradeEntry(system: GradeSystem.fontainebleau, gradeIndex: 99);
      expect(convertGrade(f, GradeSystem.vscale), isNull);
    });

    test('round-trip V → Font → V preserves original', () {
      for (int v = 0; v <= 17; v++) {
        final original = GradeEntry(system: GradeSystem.vscale, gradeIndex: v);
        final font = convertGrade(original, GradeSystem.fontainebleau);
        expect(font, isNotNull, reason: 'V$v should convert to Font');
        final back = convertGrade(font!, GradeSystem.vscale);
        expect(back, original, reason: 'V$v round-trip failed');
      }
    });
  });
}
