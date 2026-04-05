import 'package:flash_forward/models/grade_entry.dart';

/// Font scale ordered list (index 0 onward).
const List<String> kFontScale = [
  '4', '5', '5+',
  '6A', '6A+', '6B', '6B+', '6C', '6C+',
  '7A', '7A+', '7B', '7B+', '7C', '7C+',
  '8A', '8A+', '8B', '8B+', '8C', '8C+', '9A',
];

/// Cross-reference: V-scale index → list of equivalent Font scale indices.
/// Used only for the reference grid on grade charts.
/// V-scale index IS the grade number (V0=0 … V17=17).
const List<List<int>> kVToFontIndices = [
  [0],      // V0  → 4
  [1],      // V1  → 5
  [2],      // V2  → 5+
  [3, 4],   // V3  → 6A, 6A+
  [5, 6],   // V4  → 6B, 6B+
  [7, 8],   // V5  → 6C, 6C+
  [9],      // V6  → 7A
  [10],     // V7  → 7A+
  [11, 12], // V8  → 7B, 7B+
  [13],     // V9  → 7C
  [14],     // V10 → 7C+
  [15],     // V11 → 8A
  [16],     // V12 → 8A+
  [17],     // V13 → 8B
  [18],     // V14 → 8B+
  [19],     // V15 → 8C
  [20],     // V16 → 8C+
  [21],     // V17 → 9A
];

/// Returns the display string for a [GradeEntry].
String gradeLabel(GradeEntry entry) => switch (entry.system) {
  GradeSystem.vscale => 'V${entry.gradeIndex}',
  GradeSystem.fontainebleau =>
    (entry.gradeIndex >= 0 && entry.gradeIndex < kFontScale.length)
        ? kFontScale[entry.gradeIndex]
        : '?',
};

/// Converts [entry] to [targetSystem]. Returns it unchanged if already in
/// that system, or null if the grade index is out of the known mapping range.
GradeEntry? convertGrade(GradeEntry entry, GradeSystem targetSystem) {
  if (entry.system == targetSystem) return entry;
  switch (targetSystem) {
    case GradeSystem.fontainebleau:
      if (entry.gradeIndex < 0 ||
          entry.gradeIndex >= kVToFontIndices.length) {
        return null;
      }
      return GradeEntry(
        system: GradeSystem.fontainebleau,
        gradeIndex: kVToFontIndices[entry.gradeIndex].first,
      );
    case GradeSystem.vscale:
      for (int v = 0; v < kVToFontIndices.length; v++) {
        if (kVToFontIndices[v].contains(entry.gradeIndex)) {
          return GradeEntry(system: GradeSystem.vscale, gradeIndex: v);
        }
      }
      return null;
  }
}

/// Returns the Font scale grades that correspond to a given V-scale index.
/// Used to render the reference grid on grade charts.
List<String> fontEquivalentsForVGrade(int vIndex) {
  if (vIndex < 0 || vIndex >= kVToFontIndices.length) return [];
  return kVToFontIndices[vIndex]
      .map((i) => i < kFontScale.length ? kFontScale[i] : '?')
      .toList();
}
