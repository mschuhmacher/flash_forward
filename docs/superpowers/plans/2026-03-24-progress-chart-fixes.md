# Progress Chart Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three visual bugs in the Profile screen progress charts: duplicate data points on same-day sessions causing looping lines, a cluttered x-axis with non-calendar-aligned labels, and non-round y-axis boundary values.

**Architecture:** Two files change. `progress_extractor.dart` gains per-day deduplication so all chart consumers get clean data. `progress_chart.dart` gains four private helpers for calendar-aware x-axis tick selection and label rotation, plus y-axis extreme suppression in all three chart classes. No new files, no new dependencies, no model changes.

**Tech Stack:** Flutter/Dart, `fl_chart`, `intl` (DateFormat), `dart:math` (pi)

**Spec:** `docs/superpowers/specs/2026-03-24-progress-chart-fixes-design.md`

---

## File Map

| File | Change |
|------|--------|
| `lib/services/progress_extractor.dart` | Add deduplication by UTC calendar day in `extractLoads`, `extractGrades`, `extractBodyWeight` |
| `lib/presentation/widgets/progress_chart.dart` | Add `import 'dart:math' show pi;`, add `_XScale` enum + 4 private helpers, replace bottomTitles in all three chart classes, update leftTitles in all three chart classes, remove `_xInterval` methods |
| `test/services/progress_extractor_test.dart` | New — unit tests for deduplication behavior |

---

## Task 1: Extractor deduplication

**Files:**
- Modify: `lib/services/progress_extractor.dart:56-117`
- Create: `test/services/progress_extractor_test.dart`

### Background

`extractLoads`, `extractGrades`, and `extractBodyWeight` currently return one point per session. When a user logs two sessions on the same calendar day, the chart receives two x-values milliseconds apart — creating a visible V-shaped loop. The fix groups by UTC calendar date and keeps the highest value per day. The surviving point's date is normalized to `DateTime.utc(y, m, d)` (exact midnight), matching fl_chart's tick boundaries.

UTC is required (not local time) because fl_chart stores x-values as `millisecondsSinceEpoch` doubles and converts back via `DateTime.fromMillisecondsSinceEpoch(..., isUtc: true)`. Local-time midnight has DST-shifted offsets that would drift off the tick grid.

---

- [ ] **Step 1: Create the test file**

Create `test/services/progress_extractor_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Minimal builders ─────────────────────────────────────────────────────────

Exercise _maxExercise({
  required double load,
  String templateId = 'ex-1',
  String loadUnit = 'kg',
}) => Exercise(
      templateId: templateId,
      title: 'Test Exercise',
      description: '',
      label: 'Max',
      load: load,
      loadUnit: loadUnit,
    );

Workout _workout(List<Exercise> exercises) => Workout(
      title: 'Test Workout',
      label: 'Max',
      exercises: exercises,
      timeBetweenExercises: 0,
    );

Session _session({
  required DateTime completedAt,
  List<Workout>? workouts,
  GradeEntry? maxGradeClimbed,
  double? bodyWeightKg,
}) => Session(
      title: 'Test Session',
      label: 'Other',
      completedAt: completedAt,
      workouts: workouts ?? [],
      maxGradeClimbed: maxGradeClimbed,
      bodyWeightKg: bodyWeightKg,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('extractLoads — deduplication', () {
    test('two sessions same UTC day → one point with higher load', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 9)),
          workouts: [_workout([_maxExercise(load: 50.0)])],
          bodyWeightKg: 70.0,
        ),
        _session(
          completedAt: day.add(const Duration(hours: 18)),
          workouts: [_workout([_maxExercise(load: 55.0)])],
          bodyWeightKg: 71.0,
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 1);
      expect(result.first.loadKg, 55.0);
      // Body weight comes from the session with the winning (higher) load
      expect(result.first.bodyWeightKg, 71.0);
    });

    test('single point: returns exactly one point with date normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14, 37),
          workouts: [_workout([_maxExercise(load: 60.0)])],
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 1);
      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });

    test('sessions on different UTC days → one point per day', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 10),
          workouts: [_workout([_maxExercise(load: 50.0)])],
        ),
        _session(
          completedAt: DateTime.utc(2026, 3, 21, 10),
          workouts: [_workout([_maxExercise(load: 55.0)])],
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 2);
    });
  });

  group('extractGrades — deduplication', () {
    test('two sessions same UTC day → one point with higher gradeIndex', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 9)),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 7),
        ),
        _session(
          completedAt: day.add(const Duration(hours: 18)),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 8),
        ),
      ];

      final result =
          ProgressExtractor.extractGrades(sessions, GradeMetric.climbed);

      expect(result.length, 1);
      expect(result.first.grade.gradeIndex, 8);
    });

    test('surviving point date is normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 6),
        ),
      ];

      final result =
          ProgressExtractor.extractGrades(sessions, GradeMetric.climbed);

      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });
  });

  group('extractBodyWeight — deduplication', () {
    test('two sessions same UTC day → one point with higher body weight', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 8)),
          bodyWeightKg: 70.5,
        ),
        _session(
          completedAt: day.add(const Duration(hours: 19)),
          bodyWeightKg: 71.0,
        ),
      ];

      final result = ProgressExtractor.extractBodyWeight(sessions);

      expect(result.length, 1);
      expect(result.first.bodyWeightKg, 71.0);
    });

    test('single point: returns exactly one point with date normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14, 37),
          bodyWeightKg: 70.0,
        ),
      ];

      final result = ProgressExtractor.extractBodyWeight(sessions);

      expect(result.length, 1);
      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });
  });
}
```

- [ ] **Step 2: Run the tests — expect failures**

```bash
flutter test test/services/progress_extractor_test.dart --reporter expanded
```

Expected: all tests **FAIL** (dedup not yet implemented — current code returns one point per session, not per day).

- [ ] **Step 3: Implement deduplication in `extractLoads`**

In `lib/services/progress_extractor.dart`, replace the last two lines of `extractLoads` (the sort + return):

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
```

With:

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    // Group by UTC calendar day; keep the point with the highest loadKg.
    // Normalise the surviving date to UTC midnight so fl_chart tick positions align.
    final byDay = <String, StrengthPoint>{};
    for (final point in points) {
      final utc = point.date.toUtc();
      final key = '${utc.year}-${utc.month}-${utc.day}';
      final existing = byDay[key];
      if (existing == null || point.loadKg > existing.loadKg) {
        byDay[key] = (
          date: DateTime.utc(utc.year, utc.month, utc.day),
          loadKg: point.loadKg,
          bodyWeightKg: point.bodyWeightKg,
        );
      }
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
```

- [ ] **Step 4: Implement deduplication in `extractGrades`**

Replace the last two lines of `extractGrades`:

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
```

With:

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    // Group by UTC calendar day; keep the point with the highest gradeIndex.
    final byDay = <String, GradePoint>{};
    for (final point in points) {
      final utc = point.date.toUtc();
      final key = '${utc.year}-${utc.month}-${utc.day}';
      final existing = byDay[key];
      if (existing == null || point.grade.gradeIndex > existing.grade.gradeIndex) {
        byDay[key] = (
          date: DateTime.utc(utc.year, utc.month, utc.day),
          grade: point.grade,
        );
      }
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
```

- [ ] **Step 5: Implement deduplication in `extractBodyWeight`**

Replace the last two lines of `extractBodyWeight`:

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
```

With:

```dart
    points.sort((a, b) => a.date.compareTo(b.date));
    // Group by UTC calendar day; keep the highest bodyWeightKg per day.
    final byDay = <String, ({DateTime date, double bodyWeightKg})>{};
    for (final point in points) {
      final utc = point.date.toUtc();
      final key = '${utc.year}-${utc.month}-${utc.day}';
      final existing = byDay[key];
      if (existing == null || point.bodyWeightKg > existing.bodyWeightKg) {
        byDay[key] = (
          date: DateTime.utc(utc.year, utc.month, utc.day),
          bodyWeightKg: point.bodyWeightKg,
        );
      }
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
```

- [ ] **Step 6: Run the tests — expect all pass**

```bash
flutter test test/services/progress_extractor_test.dart --reporter expanded
```

Expected: all 6 tests **PASS**.

- [ ] **Step 7: Commit**

```bash
git add lib/services/progress_extractor.dart test/services/progress_extractor_test.dart
git commit -m "fix: deduplicate progress data by UTC calendar day in all three extractors

Multiple sessions on the same day produced duplicate x-values in
fl_chart, causing visible V-shaped loops. Now each extractor groups
by UTC calendar date and keeps the highest value per day (max load,
max gradeIndex, max body weight). Surviving point dates are normalized
to DateTime.utc(y, m, d) to align with fl_chart tick boundaries."
```

---

## Task 2: Chart fixes — x-axis scale + y-axis extremes

**Files:**
- Modify: `lib/presentation/widgets/progress_chart.dart`

### Background

**X-axis (Bug 2):** Each chart class has a `_xInterval` method that divides the total range by 4, producing non-calendar-aligned ticks. The label format `DateFormat('MMM yy')` renders "Mar 26" where "26" is the two-digit year (not the day), which is easily misread. The fix replaces this with a 4-scale calendar tick system:

| Scale | Trigger | Tick dates | Format |
|-------|---------|-----------|--------|
| Weekly | ≤ 42 days | Monday of each week | `'d MMM'` e.g. "24 Mar" |
| Monthly | ≤ 274 days | 1st of each month | `'MMM'` e.g. "Mar" |
| Quarterly | ≤ 730 days | Jan 1, Apr 1, Jul 1, Oct 1 | `'MMM'` e.g. "Apr" |
| Yearly | > 730 days | Jan 1 of each year | `'yyyy'` e.g. "2026" |

On monthly/quarterly scales, January ticks show the 4-digit year number instead of "Jan" to prevent year ambiguity.

`interval` is set to 86 400 000 ms (1 day) for all scales. Since all dates from Task 1 are normalized to UTC midnight, fl_chart generates ticks at exact midnight boundaries. `getTitlesWidget` returns a label only for tick dates; all others return `SizedBox.shrink()`. This runs at build time only — not per animation frame.

Labels are rotated 55° counter-clockwise (`angle: -pi * 55 / 180`) so they read bottom-left to top-right. `reservedSize` increases from 28 pt → 50 pt to accommodate the rotated bounding box.

**Y-axis (Bug 3):** `minY = dataMin * 0.9` and `maxY = dataMax * 1.1` produce non-round boundaries, causing fl_chart to emit non-round tick labels at the axis extremes. The auto-interval is fine; only the min and max labels need suppressing via `meta.min`/`meta.max`.

**Single-point edge case:** When all data falls on one day, `rangeMs == 0`. Compute scale first (it will be `weekly`), then pad `minX -= 3 days` and `maxX += 3 days` so the chart has room to draw.

---

- [ ] **Step 1: Add `import 'dart:math' show pi;`**

In `lib/presentation/widgets/progress_chart.dart`, add after the existing imports (after line 7):

```dart
import 'dart:math' show pi;
```

- [ ] **Step 2: Add private helpers before `StrengthProgressChart`**

Insert the following block between the import block and the `StrengthProgressChart` class declaration (before line 10):

```dart
// ── X-axis scale helpers ──────────────────────────────────────────────────────

enum _XScale { weekly, monthly, quarterly, yearly }

/// Selects the tick scale from the chart's total time range in milliseconds.
/// Scale is computed from the ORIGINAL rangeMs before any single-point padding.
_XScale _xScaleFor(double rangeMs) {
  const day = 86400000.0;
  if (rangeMs <= 42 * day) return _XScale.weekly;
  if (rangeMs <= 274 * day) return _XScale.monthly;
  if (rangeMs <= 730 * day) return _XScale.quarterly;
  return _XScale.yearly;
}

/// Returns true when [utcDate] is a tick position for [scale].
bool _isTickDate(DateTime utcDate, _XScale scale) => switch (scale) {
      _XScale.weekly => utcDate.weekday == DateTime.monday,
      _XScale.monthly => utcDate.day == 1,
      _XScale.quarterly =>
        utcDate.day == 1 && [1, 4, 7, 10].contains(utcDate.month),
      _XScale.yearly => utcDate.day == 1 && utcDate.month == 1,
    };

/// Returns the label string for a tick date.
/// On monthly and quarterly scales, January shows the 4-digit year number
/// instead of "Jan" so the year boundary is unambiguous.
String _tickLabel(DateTime utcDate, _XScale scale) {
  if (utcDate.month == 1 && scale != _XScale.yearly) {
    return utcDate.year.toString();
  }
  return switch (scale) {
    _XScale.weekly => DateFormat('d MMM').format(utcDate),
    _XScale.monthly => DateFormat('MMM').format(utcDate),
    _XScale.quarterly => DateFormat('MMM').format(utcDate),
    _XScale.yearly => utcDate.year.toString(),
  };
}

/// Bottom-axis label widget for a given x-value (milliseconds since epoch).
/// Returns [SizedBox.shrink] for non-tick positions.
/// Labels are rotated 55° counter-clockwise ("8 to 2 on a clock face").
Widget _buildXLabel(double xMs, _XScale scale, BuildContext context) {
  final utcDate =
      DateTime.fromMillisecondsSinceEpoch(xMs.toInt(), isUtc: true);
  if (!_isTickDate(utcDate, scale)) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Transform.rotate(
      angle: -pi * 55 / 180,
      child: Text(_tickLabel(utcDate, scale), style: context.bodyMedium),
    ),
  );
}
```

- [ ] **Step 3: Update `StrengthProgressChart.build()` — x-axis**

In `StrengthProgressChart.build()`, find these two lines (around line 44):

```dart
    final minX = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.date.millisecondsSinceEpoch.toDouble();
```

Replace with:

```dart
    var minX = points.first.date.millisecondsSinceEpoch.toDouble();
    var maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    }
```

Then find the `bottomTitles` SideTitles block inside `StrengthProgressChart` (lines 114–132):

```dart
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _xInterval(minX, maxX),
                getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(
                    value.toInt(),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM yy').format(date),
                      style: context.bodyMedium,
                    ),
                  );
                },
              ),
            ),
```

Replace with:

```dart
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: 86400000,
                getTitlesWidget: (value, meta) =>
                    _buildXLabel(value, scale, context),
              ),
            ),
```

- [ ] **Step 4: Update `StrengthProgressChart.build()` — y-axis**

Find the `leftTitles` `getTitlesWidget` inside `StrengthProgressChart` (around line 108):

```dart
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: context.bodyMedium,
                ),
```

Replace with:

```dart
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toStringAsFixed(1),
                    style: context.bodyMedium,
                  );
                },
```

- [ ] **Step 5: Remove `_xInterval` from `StrengthProgressChart`**

Delete the entire method (lines 171–176):

```dart
  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    // Show ~4 labels
    return (rangeMs / 4).ceilToDouble();
  }
```

- [ ] **Step 6: Update `GradeProgressChart.build()` — x-axis**

In `GradeProgressChart.build()`, find these two lines (around line 209):

```dart
    final minX = allDates.reduce((a, b) => a < b ? a : b);
    final maxX = allDates.reduce((a, b) => a > b ? a : b);
```

Replace with:

```dart
    var minX = allDates.reduce((a, b) => a < b ? a : b);
    var maxX = allDates.reduce((a, b) => a > b ? a : b);
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    }
```

Then find the `bottomTitles` SideTitles block inside `GradeProgressChart` (around lines 284–299):

```dart
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _xInterval(minX, maxX),
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          DateFormat('MMM yy').format(date),
                          style: context.bodyMedium,
                        ),
                      );
                    },
                  ),
                ),
```

Replace with:

```dart
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    interval: 86400000,
                    getTitlesWidget: (value, meta) =>
                        _buildXLabel(value, scale, context),
                  ),
                ),
```

- [ ] **Step 7: Update `GradeProgressChart.build()` — y-axis**

Find the `leftTitles` `getTitlesWidget` inside `GradeProgressChart` (around line 277):

```dart
                    getTitlesWidget: (value, meta) {
                      final label = indexToLabel[value.round()];
                      if (label == null) return const SizedBox.shrink();
                      return Text(label, style: context.bodyMedium);
                    },
```

Replace with:

```dart
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) {
                        return const SizedBox.shrink();
                      }
                      final label = indexToLabel[value.round()];
                      if (label == null) return const SizedBox.shrink();
                      return Text(label, style: context.bodyMedium);
                    },
```

- [ ] **Step 8: Remove `_xInterval` from `GradeProgressChart`**

Delete the method (around lines 336–340):

```dart
  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    return (rangeMs / 4).ceilToDouble();
  }
```

- [ ] **Step 9: Update `BodyWeightChart.build()` — x-axis**

In `BodyWeightChart.build()`, find these two lines (around line 379):

```dart
    final minX = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.date.millisecondsSinceEpoch.toDouble();
```

Replace with:

```dart
    var minX = points.first.date.millisecondsSinceEpoch.toDouble();
    var maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final rangeMs = maxX - minX;
    final scale = _xScaleFor(rangeMs); // compute BEFORE padding
    if (rangeMs == 0) {
      minX -= 3 * 86400000;
      maxX += 3 * 86400000;
    }
```

Then find the `bottomTitles` SideTitles block inside `BodyWeightChart` (around lines 424–438):

```dart
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _xInterval(minX, maxX),
                getTitlesWidget: (value, meta) {
                  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM yy').format(date),
                      style: context.bodyMedium,
                    ),
                  );
                },
              ),
            ),
```

Replace with:

```dart
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: 86400000,
                getTitlesWidget: (value, meta) =>
                    _buildXLabel(value, scale, context),
              ),
            ),
```

- [ ] **Step 10: Update `BodyWeightChart.build()` — y-axis**

Find the `leftTitles` `getTitlesWidget` inside `BodyWeightChart` (around line 418):

```dart
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: context.bodyMedium,
                ),
```

Replace with:

```dart
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toStringAsFixed(1),
                    style: context.bodyMedium,
                  );
                },
```

- [ ] **Step 11: Remove `_xInterval` from `BodyWeightChart`**

Delete the method (around lines 469–473):

```dart
  double _xInterval(double minX, double maxX) {
    final rangeMs = maxX - minX;
    if (rangeMs <= 0) return 1;
    return (rangeMs / 4).ceilToDouble();
  }
```

- [ ] **Step 12: Verify the app compiles**

```bash
flutter analyze lib/presentation/widgets/progress_chart.dart lib/services/progress_extractor.dart
```

Expected: no errors or warnings related to the changed files.

- [ ] **Step 13: Manual verification — hot reload**

Run the app. Navigate to the Profile screen.

Verify:
1. **Deduplication** — If you have multiple sessions logged on the same day for the same exercise, the chart shows one dot (not two) and no V-shaped loop. The dot appears at the highest load.
2. **X-axis labels** — Labels show calendar-aligned dates (e.g. "24 Mar" for the Monday of a week on the weekly scale). No repeated labels. Labels are rotated ~55° from horizontal.
3. **Y-axis labels** — The extreme top and bottom y-axis values are suppressed. Only the auto-interval ticks show labels.

- [ ] **Step 14: Commit**

```bash
git add lib/presentation/widgets/progress_chart.dart
git commit -m "fix: calendar-aware x-axis ticks and y-axis extreme suppression in progress charts

Replaces the static divide-by-4 interval with a 4-scale calendar tick
system (weekly/monthly/quarterly/yearly) selected by data range. Tick
dates are calendar boundaries (Mondays, 1sts, quarter starts, Jan 1s).
January ticks on monthly/quarterly scales show the year number to
prevent ambiguity (Dec → 2026 → Feb). Labels rotated 55° counter-
clockwise; reservedSize increased from 28 to 50 pt.

Also suppresses the non-round min/max y-axis boundary labels that
appeared between clean auto-interval ticks."
```
