# Progress Chart Fixes — Design Spec

**Goal:** Fix three visual bugs in the Profile screen progress charts: duplicate data points on the same day causing looping lines, a cluttered x-axis with repeated date labels, and y-axis extremes showing non-round boundary values.

**Architecture:** Two files change. Data quality (deduplication) is fixed at the extractor layer so all consumers get clean data. Visual presentation (x-axis ticks, y-axis labels) is fixed in the chart widget layer. No model changes, no new dependencies, no new files.

**Files changed:**
- `lib/services/progress_extractor.dart` — deduplication in `extractLoads`, `extractGrades`, and `extractBodyWeight`
- `lib/presentation/widgets/progress_chart.dart` — x-axis scale logic + label rotation in `StrengthProgressChart`, `GradeProgressChart`, and `BodyWeightChart`; y-axis extremes suppression in all three

---

## Bug 1 — Deduplication by calendar day

### Problem
All three extractors use `session.completedAt` (millisecond precision) as the x-coordinate. Two sessions completed on the same calendar day produce two distinct x-values very close together. The line chart connects them in sorted order, creating a visible V-shaped loop. The x-axis renders two labels nearly on top of each other.

### Fix
After collecting raw points and sorting, group by calendar date. The key is a plain string `'yyyy-M-d'` (computed from a **UTC** DateTime — see UTC note below). Per group, keep the point with the highest value:

- **`extractLoads`**: keep the `StrengthPoint` with the highest `loadKg`. Take that point's `bodyWeightKg` (keep the body weight from the session that produced the best lift).
- **`extractGrades`**: keep the `GradePoint` with the highest `gradeIndex`.
- **`extractBodyWeight`**: keep the point with the highest `bodyWeightKg` per day (or the last — but highest is consistent with the other extractors).

Normalize the stored `date` of the surviving point to **UTC midnight** (`DateTime.utc(year, month, day)`) so all x-axis coordinates are exact midnight boundaries.

The public return types (`List<StrengthPoint>`, `List<GradePoint>`, `List<({DateTime date, double bodyWeightKg})>`) are unchanged.

### UTC requirement
All DateTime normalization must use `DateTime.utc(y, m, d)`, not `DateTime(y, m, d)` (local time). This is required because fl_chart receives x-values as `millisecondsSinceEpoch` doubles and converts them back with `DateTime.fromMillisecondsSinceEpoch(..., isUtc: true)`. Using local time would produce DST-shifted offsets that drift off midnight boundaries.

### Implementation detail — `extractLoads`

```dart
// After existing sort: group by UTC calendar day, keep max loadKg
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

### Implementation detail — `extractGrades`

```dart
// After existing sort: group by UTC calendar day, keep max gradeIndex
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

### Implementation detail — `extractBodyWeight`

```dart
// After existing sort: group by UTC calendar day, keep max bodyWeightKg
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

---

## Bug 2 — X-axis: four-scale calendar ticks with rotated labels

### Problem
`_xInterval` computes a fixed millisecond interval divided by 4, producing non-calendar-aligned ticks. The format `DateFormat('MMM yy')` renders March 2026 as "Mar 26" — `yy` is the two-digit year, easily misread as a day number. With multiple same-day points the labels all collapse onto the same x position.

### Scale selection

Based on label footprint analysis at 55° rotation on the minimum supported screen width (~280pt usable after 16pt horizontal padding × 2 and 44pt y-axis reservedSize):

At 55°, footprint = `W · cos(55°) + H · sin(55°)`:
- "d MMM" e.g. "24 Mar" (W≈42, H≈14): **35.6pt** → 41.6pt per slot with 6pt gap
- "MMM" e.g. "Mar" (W≈21, H≈14): **23.6pt** → 29.6pt per slot
- "yyyy" e.g. "2026" (W≈28, H≈14): **27.6pt** → 33.6pt per slot

| Scale | Trigger (rangeMs) | Tick dates | Label format | Max labels |
|-------|-------------------|-----------|--------------|------------|
| Weekly | ≤ 42 days | Monday of each week | `'d MMM'` e.g. "24 Mar" | 6 |
| Monthly | ≤ 274 days | 1st of each month | `'MMM'` e.g. "Mar" | 9 |
| Quarterly | ≤ 730 days | Jan 1, Apr 1, Jul 1, Oct 1 | `'MMM'` e.g. "Apr" | 9 |
| Yearly | > 730 days | Jan 1 of each year | `'yyyy'` e.g. "2026" | 8 |

Scale is computed from the **original** `rangeMs` (before any single-point padding is applied — see Single-point edge case below).

### Year-boundary label rule
For monthly and quarterly scales, when a tick lands on January, show the 4-digit year instead of "Jan". The sequence reads: `Dec` → `2026` → `Feb` → `Mar`. This prevents year ambiguity without requiring a secondary axis. The yearly scale always shows `yyyy`.

### Label rotation
All bottom-axis labels are rotated 55° counter-clockwise (text reads bottom-left to top-right, the "8 to 2 on a clockface" direction). In Flutter, `Transform.rotate` with a positive angle rotates clockwise, so counter-clockwise 55° = `angle: -pi * 55 / 180`.

### reservedSize
Bounding box height at 55° = `W · sin(55°) + H · cos(55°)`. For the widest label "24 Mar": 42 · 0.819 + 14 · 0.574 = **42.4pt**. Update `reservedSize` for all bottom axes from **28pt → 50pt** to accommodate rotated labels.

### fl_chart implementation

Set `interval` to **1 day = 86 400 000 ms** for all four scales. Since all data dates are normalized to UTC midnight (Bug 1), fl_chart generates tick x-values at exact UTC midnight boundaries. `getTitlesWidget` converts the float back to a UTC DateTime and checks whether it is a tick date for the active scale; it returns the label widget or `SizedBox.shrink()` for non-tick positions.

Performance: `getTitlesWidget` is called once per tick during `build()`, not per animation frame. At the maximum practical range for the yearly scale (~5 years = 1825 calls), each call is a trivial integer → DateTime conversion plus a few comparisons returning a `const SizedBox.shrink()`. This is imperceptible overhead.

### Private helpers (shared by all three chart classes)

Extract four private free functions at the top of `progress_chart.dart`:

```dart
enum _XScale { weekly, monthly, quarterly, yearly }

_XScale _xScaleFor(double rangeMs) {
  const day = 86400000.0;
  if (rangeMs <= 42 * day)  return _XScale.weekly;
  if (rangeMs <= 274 * day) return _XScale.monthly;
  if (rangeMs <= 730 * day) return _XScale.quarterly;
  return _XScale.yearly;
}

bool _isTickDate(DateTime utcDate, _XScale scale) => switch (scale) {
  _XScale.weekly    => utcDate.weekday == DateTime.monday,
  _XScale.monthly   => utcDate.day == 1,
  _XScale.quarterly => utcDate.day == 1 && [1, 4, 7, 10].contains(utcDate.month),
  _XScale.yearly    => utcDate.day == 1 && utcDate.month == 1,
};

String _tickLabel(DateTime utcDate, _XScale scale) {
  // Year-boundary rule: replace Jan with the year number (monthly and quarterly scales)
  if (utcDate.month == 1 && scale != _XScale.yearly) return utcDate.year.toString();
  return switch (scale) {
    _XScale.weekly    => DateFormat('d MMM').format(utcDate),
    _XScale.monthly   => DateFormat('MMM').format(utcDate),
    _XScale.quarterly => DateFormat('MMM').format(utcDate),
    _XScale.yearly    => utcDate.year.toString(),
  };
}

/// Returns the bottom-axis label widget for a given x-value.
/// Returns SizedBox.shrink() for non-tick positions.
Widget _buildXLabel(double xMs, _XScale scale, BuildContext context) {
  final utcDate = DateTime.fromMillisecondsSinceEpoch(xMs.toInt(), isUtc: true);
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

`import 'dart:math' show pi;` must be added at the top of `progress_chart.dart`.

### Replacing `_xInterval` in each chart class

Apply to all three chart classes: `StrengthProgressChart`, `GradeProgressChart`, and `BodyWeightChart`.

Remove the existing `_xInterval` method from each chart class. Replace with:

```dart
// In build():
final rangeMs = maxX - minX;        // computed from deduped points
final scale = _xScaleFor(rangeMs);  // compute BEFORE any single-point padding
```

Then in `SideTitles`:
```dart
SideTitles(
  showTitles: true,
  reservedSize: 50,
  interval: 86400000,
  getTitlesWidget: (value, meta) => _buildXLabel(value, scale, context),
)
```

### Single-point edge case
When `rangeMs == 0` (all data on one day), compute `scale` first from the original `rangeMs`, then extend: `minX -= 3 * 86400000`, `maxX += 3 * 86400000`. The scale will be `weekly`. The extended range may contain a Monday tick which will render correctly.

---

## Bug 3 — Y-axis: suppress axis-extreme labels

### Problem
No `interval` is set on the y-axis. fl_chart auto-picks an interval based on `minY`/`maxY`, which are computed as `dataMin * 0.9` and `dataMax * 1.1`. These non-round boundaries produce non-round tick labels at the axis extremes (e.g. 13.5, 16.5) that sit between the clean auto-interval ticks.

### Fix
The auto-interval is acceptable. Suppress only the min and max labels using `TitleMeta`:

```dart
getTitlesWidget: (value, meta) {
  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
  return Text(value.toStringAsFixed(1), style: context.bodyMedium);
},
```

Apply to `leftTitles` in `StrengthProgressChart`, `BodyWeightChart`, and `GradeProgressChart`. For `GradeProgressChart` the y-axis already returns `SizedBox.shrink()` for values with no grade label — add the `meta.min`/`meta.max` guard before the existing null check for consistency.

---

## Edge cases

| Scenario | Handling |
|----------|----------|
| Single data point | `rangeMs == 0` → extend ±3 days; one dot renders, no line drawn |
| All points on same day | Dedup reduces to 1 point → same as above |
| Mixed grade systems on same day | Keep highest `gradeIndex`; cross-system comparison is imprecise but same-day mixed-system entries are rare in practice |
| Range exactly at a scale boundary | `<` comparisons mean the boundary always goes to the coarser scale |
| No data | `points.isEmpty` guard already returns `_EmptyState` before any of this logic runs |
| DST / timezone | All DateTime values normalized to UTC midnight; no local-time DST offsets affect tick positions |
