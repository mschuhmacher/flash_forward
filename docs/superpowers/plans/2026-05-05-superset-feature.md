# Superset Feature Implementation Plan (Revised)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to group exercises in a workout into supersets that chain together with a short configurable countdown between exercises, with per-superset color-coded UI indicators, asymmetric set-count support, whole-block reorder, and full propagation support.

**Architecture:** Add `SupersetConfig` (with `id`, `exerciseIds`, `restSeconds`, `supersetSets`) and a `supersets: List<SupersetConfig>` field to `Workout`. The timer references `workout.supersets` to determine membership and reads `superset.supersetSets ?? exercise.sets` everywhere set counts are consulted. A new `TimerPhase.supersetRest` handles the intra-superset countdown. A modal manages members (add/remove via trash icons + checkboxes for unsuperseted exercises), `supersetSets`, `restSeconds`, and dissolution. The workout list supports whole-block drag of superset members as a stack. `supersets` travels through `Workout.deepCopy` unchanged, so propagation works via the existing system.

**Tech Stack:** Flutter, Provider (ChangeNotifier), `package:uuid`, `flutter_slidable`, `flutter_test` (no external mocking)

---

## File Map

| Action | File |
|--------|------|
| Create | `lib/models/superset_config.dart` |
| Modify | `lib/models/workout.dart` |
| Modify | `lib/models/rest_event.dart` |
| Modify | `lib/models/session_summary.dart` |
| Modify | `lib/providers/session_state_provider.dart` |
| Modify | `lib/presentation/screens/training_program_flow/new_workout_screen.dart` |
| Modify | `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` |
| Modify | `lib/presentation/screens/session_flow/session_active_screen.dart` |
| Create | `lib/utils/superset_utils.dart` |
| Create | `lib/presentation/screens/training_program_flow/superset_modal.dart` |
| Create | `test/models/superset_config_test.dart` |
| Create | `test/utils/superset_utils_test.dart` |
| Create | `test/providers/session_state_provider_superset_test.dart` |
| Create | `test/providers/preset_provider_superset_propagate_test.dart` |

---

## Design Decisions (locked)

These were resolved during plan review. Implementations must match.

1. **`supersets: List<SupersetConfig>` lives on `Workout`, not on `Exercise`.** Group membership is a workout-level relationship; `deepCopy` carries the list through automatically and propagation lookups by exercise id continue to work.

2. **`SupersetConfig.supersetSets: int?` overrides member exercise's `sets` field.** When non-null, the timer reads `supersetSets` instead of `exercise.sets` for any exercise that is a member. The exercise's own `sets` field is preserved untouched and reappears when the exercise leaves the superset. Edits to the "sets" field on a superset member (catalog or mid-session) write to `supersetSets`, not `exercise.sets`. All members reflect the change immediately because they all read the same `supersetSets`.

3. **`supersetSets` defaults on creation:**
   - Members all have same `sets` → auto-set to that value (no prompt).
   - Members differ → prompt user, default to `max(member.sets)`.
   - Joining an existing superset → silently auto-keep the existing `supersetSets`.

4. **Members must remain contiguous in the workout list.** Order *within* the block is unconstrained; the block can move freely as a unit; solo exercises can move freely except into a block. The timer's `supersetGroupStartIndex` walk relies on this invariant.

5. **An exercise can be in at most one superset at a time.**

6. **Reorder model:**
   - Long-press any exercise → drag.
   - If the dragged exercise is a superset member, the entire block drags as a stack: topmost member full-size, with one stack-edge peeking below per additional member.
   - Drop runs `supersetsRemainContiguous` on the candidate list. Inter-block collision → reject + snap-back + snackbar.
   - Within-block reorder happens in the modal (drag handles in the member list there), not in the workout list.
   - Copying an exercise (`_copyExercise`) never adds the copy to a superset.
   - Deleting an exercise strips it from its superset; if the superset drops below 2 members, dissolve silently.

7. **Slidable on every exercise card** uses both panes:
   - **Start pane (left-to-right swipe): Save to catalog (conditional)** + **Copy.** Additive actions.
   - **End pane (right-to-left swipe): Superset** + **Delete.** Modifying/destructive actions.
   - The Superset action is contextual: "Add to superset" when the exercise is solo, "Edit superset" when it's a member.
   - Each `ActionPane` uses `extentRatio: 0.22 * visibleActionCount` so each individual action is fixed at ~22% of card width regardless of how many actions are visible. Single-action panes don't stretch.

8. **Add-to-superset chooser** (when there are existing supersets in the workout): popup menu listing each superset (color bar + member count + first-member title) plus "Create new superset." Picking an existing one opens the modal in "join" state (this exercise added, `supersetSets` auto-kept). No prompt on join, even if member sets differ.

9. **Modal layout (used for create/edit/join):**
   - Members list: name + trash icon per row (trash removes from superset, not from workout).
   - "Add" section: checkboxes for workout exercises that are not in *any* superset (solo exercises only). On confirm, checked exercises join.
   - `supersetSets` number input.
   - `restSeconds` number input.
   - Destructive "Remove superset" button at the bottom: dissolves the superset, exercises stay in workout.
   - On confirm with member count 0 or 1: silently dissolve (the modal can't reach that state via UI affordances since each trash icon adds an exercise back into solo state, but defensive handling on confirm).

10. **`supersetRest` is not overtime-eligible.** It is a mandatory short pause to switch equipment.

11. **Per-card color bar** identifies supersets visually. Per-superset palette color rendered as a leading vertical bar on the exercise card. No badge widget. No continuous strip across adjacent cards in v1. Same color on the session player active card during a superset's exercises and during `supersetRest`.

12. **Mid-session edits routing:** the exercise edit screen's "sets" field writes to `superset.supersetSets` on the active session's workout for superset members; reps/loads/RPE/notes write to the exercise as before.

---

## File Map Notes

The original plan included `superset_badge.dart`. **This file is intentionally NOT created.** Per design decision 11, the per-card color bar lives inside `_ExerciseCard` styling (no separate widget). The original `superset_dialog.dart` becomes `superset_modal.dart` — same file slot, different scope (modal manages add/edit/dissolve in one place).

---

## Task 1: `SupersetConfig` model + `Workout` changes

**Files:** `lib/models/superset_config.dart`, `lib/models/workout.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/superset_config_test.dart`:
```dart
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SupersetConfig base() => SupersetConfig(
        id: 'ss-1',
        exerciseIds: ['e1', 'e2'],
        restSeconds: 15,
        supersetSets: 4,
      );

  test('SupersetConfig survives toJson/fromJson round-trip', () {
    final s = base();
    final restored = SupersetConfig.fromJson(s.toJson());
    expect(restored.id, 'ss-1');
    expect(restored.exerciseIds, ['e1', 'e2']);
    expect(restored.restSeconds, 15);
    expect(restored.supersetSets, 4);
  });

  test('SupersetConfig fromJson handles missing supersetSets (null)', () {
    final json = base().toJson()..remove('supersetSets');
    final restored = SupersetConfig.fromJson(json);
    expect(restored.supersetSets, isNull);
  });

  test('copyWith preserves unspecified fields', () {
    final s = base().copyWith(restSeconds: 20);
    expect(s.id, 'ss-1');
    expect(s.exerciseIds, ['e1', 'e2']);
    expect(s.restSeconds, 20);
    expect(s.supersetSets, 4);
  });

  test('copyWith can set supersetSets to a new value', () {
    final s = base().copyWith(supersetSets: 5);
    expect(s.supersetSets, 5);
  });

  group('Workout.supersets', () {
    Workout workoutWith(List<SupersetConfig> supersets) => Workout(
          title: 'W',
          label: 'l',
          exercises: [],
          timeBetweenExercises: 120,
          supersets: supersets,
        );

    test('Workout.supersets survives toJson/fromJson round-trip', () {
      final w = workoutWith([base()]);
      final restored = Workout.fromJson(w.toJson());
      expect(restored.supersets.length, 1);
      expect(restored.supersets.first.id, 'ss-1');
      expect(restored.supersets.first.supersetSets, 4);
    });

    test('Workout.fromJson with missing supersets key defaults to empty list', () {
      final json = workoutWith([]).toJson()..remove('supersets');
      final restored = Workout.fromJson(json);
      expect(restored.supersets, isEmpty);
    });

    test('Workout.deepCopy carries supersets through', () {
      final w = workoutWith([base()]);
      final copy = w.deepCopy(keepId: true);
      expect(copy.supersets.first.id, 'ss-1');
      expect(copy.supersets.first.exerciseIds, ['e1', 'e2']);
      expect(copy.supersets.first.supersetSets, 4);
    });

    test('Workout.deepCopy supersets are independent instances', () {
      final w = workoutWith([base()]);
      final copy = w.deepCopy(keepId: true);
      expect(identical(w.supersets.first, copy.supersets.first), isFalse);
    });

    test('Workout.copyWith replaces supersets', () {
      final w = workoutWith([base()]);
      final updated = w.copyWith(supersets: []);
      expect(updated.supersets, isEmpty);
    });

    test('Workout.copyWith without supersets argument preserves them', () {
      final w = workoutWith([base()]);
      final updated = w.copyWith(title: 'New title');
      expect(updated.supersets, hasLength(1));
      expect(updated.supersets.first.id, 'ss-1');
    });
  });
}
```

- [ ] **Step 2: Run — verify it fails**

Run: `flutter test test/models/superset_config_test.dart`
Expected: compile error — `SupersetConfig` does not exist

- [ ] **Step 3: Create `lib/models/superset_config.dart`**

```dart
import 'package:uuid/uuid.dart';

class SupersetConfig {
  final String id;
  final List<String> exerciseIds; // ordered list of exercise IDs in this superset
  final int restSeconds;          // rest between exercises within the superset
  final int? supersetSets;        // overrides each member's `sets` when non-null

  SupersetConfig({
    String? id,
    required this.exerciseIds,
    this.restSeconds = 15,
    this.supersetSets,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseIds': exerciseIds,
    'restSeconds': restSeconds,
    'supersetSets': supersetSets,
  };

  factory SupersetConfig.fromJson(Map<String, dynamic> json) => SupersetConfig(
    id: json['id'] as String?,
    exerciseIds: List<String>.from(json['exerciseIds'] as List),
    restSeconds: json['restSeconds'] as int? ?? 15,
    supersetSets: json['supersetSets'] as int?,
  );

  SupersetConfig copyWith({
    String? id,
    List<String>? exerciseIds,
    int? restSeconds,
    int? supersetSets,
  }) => SupersetConfig(
    id: id ?? this.id,
    exerciseIds: exerciseIds ?? this.exerciseIds,
    restSeconds: restSeconds ?? this.restSeconds,
    supersetSets: supersetSets ?? this.supersetSets,
  );
}
```

Note: the `int? supersetSets` parameter on `copyWith` cannot distinguish "not provided" from "set to null". This is intentional — `supersetSets` is set on creation/edit and never explicitly cleared while the superset exists. Removing the superset removes the entire `SupersetConfig`. If a future use case needs to clear it, switch to `Nullable<int>?` consistent with `Workout.copyWith`.

- [ ] **Step 4: Update `lib/models/workout.dart`**

Add import at top:
```dart
import 'package:flash_forward/models/superset_config.dart';
```

Add field after `timeBetweenExercises`:
```dart
final List<SupersetConfig> supersets;
```

Add to constructor with default:
```dart
this.supersets = const [],
```

Add to `toJson()`:
```dart
'supersets': supersets.map((s) => s.toJson()).toList(),
```

Add to `fromJson()` (backward-compatible — missing key → empty list):
```dart
supersets: ((json['supersets']) as List<dynamic>? ?? [])
    .map((s) => SupersetConfig.fromJson(s as Map<String, dynamic>))
    .toList(),
```

Add to `copyWith()` signature and body:
```dart
List<SupersetConfig>? supersets,
```
```dart
supersets: supersets ?? this.supersets,
```

Add to `deepCopy()`:
```dart
supersets: supersets.map((s) => s.copyWith()).toList(),
```

- [ ] **Step 5: Run — verify passes**

Run: `flutter test test/models/superset_config_test.dart`
Expected: all PASS

Run: `flutter test` (full suite)
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add lib/models/superset_config.dart lib/models/workout.dart \
        test/models/superset_config_test.dart
git commit -m "feat(superset): add SupersetConfig model and Workout.supersets field"
```

---

## Task 2: Superset utilities

**Files:** `lib/utils/superset_utils.dart`, `test/utils/superset_utils_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/utils/superset_utils_test.dart`:
```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _ex(String id, {int sets = 3}) => Exercise(
      id: id, title: id, description: 'd', label: 'l', sets: sets);

SupersetConfig _ss(String id, List<String> exIds,
        {int rest = 10, int? supersetSets}) =>
    SupersetConfig(
        id: id, exerciseIds: exIds, restSeconds: rest, supersetSets: supersetSets);

Workout _workout(List<Exercise> exs, List<SupersetConfig> ss) => Workout(
      title: 'W', label: 'l', exercises: exs,
      timeBetweenExercises: 120, supersets: ss);

void main() {
  group('supersetForExercise', () {
    test('returns null when exercise is not in any superset', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(supersetForExercise(w, 'a'), isNull);
    });

    test('returns config when exercise is in a superset', () {
      final w = _workout([_ex('a'), _ex('b')],
          [_ss('ss1', ['a', 'b'])]);
      expect(supersetForExercise(w, 'a')?.id, 'ss1');
    });
  });

  group('hasNextInSuperset', () {
    test('returns false for solo exercise', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(hasNextInSuperset(w, 0), isFalse);
    });

    test('returns true for first superset member with next-in-block', () {
      final w = _workout([_ex('a'), _ex('b')],
          [_ss('ss1', ['a', 'b'])]);
      expect(hasNextInSuperset(w, 0), isTrue);
    });

    test('returns false for last superset member', () {
      final w = _workout([_ex('a'), _ex('b')],
          [_ss('ss1', ['a', 'b'])]);
      expect(hasNextInSuperset(w, 1), isFalse);
    });
  });

  group('supersetGroupStartIndex', () {
    test('returns same index for solo exercise', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(supersetGroupStartIndex(w, 1), 1);
    });

    test('returns index of first member for last exercise in group', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c')],
          [_ss('ss1', ['a', 'b', 'c'])]);
      expect(supersetGroupStartIndex(w, 2), 0);
    });
  });

  group('setsForExerciseInWorkout', () {
    test('returns exercise.sets for solo exercise', () {
      final w = _workout([_ex('a', sets: 4)], []);
      expect(setsForExerciseInWorkout(w, w.exercises.first), 4);
    });

    test('returns supersetSets when member is in superset with override', () {
      final w = _workout(
          [_ex('a', sets: 3), _ex('b', sets: 4)],
          [_ss('ss1', ['a', 'b'], supersetSets: 5)]);
      expect(setsForExerciseInWorkout(w, w.exercises[0]), 5);
      expect(setsForExerciseInWorkout(w, w.exercises[1]), 5);
    });

    test('falls back to exercise.sets when supersetSets is null', () {
      final w = _workout(
          [_ex('a', sets: 3), _ex('b', sets: 3)],
          [_ss('ss1', ['a', 'b'])]); // supersetSets unset
      expect(setsForExerciseInWorkout(w, w.exercises[0]), 3);
    });
  });

  group('supersetsRemainContiguous', () {
    test('returns true when no supersets', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c')], []);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns true when all supersets are contiguous', () {
      final w = _workout(
          [_ex('a'), _ex('b'), _ex('c'), _ex('d')],
          [_ss('ss1', ['a', 'b']), _ss('ss2', ['c', 'd'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns false when a superset has a gap', () {
      // A and C are in a superset, but B is between them.
      final w = _workout(
          [_ex('a'), _ex('b'), _ex('c')],
          [_ss('ss1', ['a', 'c'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isFalse);
    });

    test('handles within-block reorder (members not in canonical order)', () {
      // exerciseIds: [a, b, c], list order: [c, b, a] — still contiguous.
      final w = _workout(
          [_ex('c'), _ex('b'), _ex('a')],
          [_ss('ss1', ['a', 'b', 'c'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns true when a superset references absent exercise ids', () {
      // Defensive: if an exerciseId got out of sync (shouldn't happen but
      // shouldn't crash), treat absent ids as no constraint.
      final w = _workout(
          [_ex('a'), _ex('b')],
          [_ss('ss1', ['a', 'ghost'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });
  });

  group('supersetColor', () {
    test('same id returns same color', () {
      expect(supersetColor('abc'), equals(supersetColor('abc')));
    });
  });

  group('supersetColorForIndex', () {
    test('cycles through palette on overflow', () {
      expect(supersetColorForIndex(0), equals(supersetColorForIndex(5)));
    });
  });
}
```

- [ ] **Step 2: Run — verify it fails**

Run: `flutter test test/utils/superset_utils_test.dart`
Expected: import error — `superset_utils.dart` does not exist

- [ ] **Step 3: Create `lib/utils/superset_utils.dart`**

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter/material.dart';

const _kSupersetPalette = [
  Color(0xFF4CAF50), // green
  Color(0xFF2196F3), // blue
  Color(0xFFF44336), // red
  Color(0xFFFF9800), // orange
  Color(0xFF9C27B0), // purple
];

/// Stable color for a superset by its index in `workout.supersets`.
Color supersetColorForIndex(int index) =>
    _kSupersetPalette[index % _kSupersetPalette.length];

/// Stable fallback: derives palette index from the superset id.
/// Used when callers don't have a workout-level index available
/// (e.g. session player, where the superset is reached via lookup).
Color supersetColor(String supersetId) {
  final hash = supersetId.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7FFFFFFF);
  return _kSupersetPalette[hash % _kSupersetPalette.length];
}

/// Returns the [SupersetConfig] that contains [exerciseId], or null.
SupersetConfig? supersetForExercise(Workout workout, String exerciseId) {
  for (final ss in workout.supersets) {
    if (ss.exerciseIds.contains(exerciseId)) return ss;
  }
  return null;
}

/// True if the exercise at [exerciseIndex] is in a superset AND the next
/// exercise in the workout list is also in the same superset.
/// Relies on the contiguous-block invariant (see [supersetsRemainContiguous]).
bool hasNextInSuperset(Workout workout, int exerciseIndex) {
  if (exerciseIndex + 1 >= workout.exercises.length) return false;
  final currentId = workout.exercises[exerciseIndex].id;
  final nextId = workout.exercises[exerciseIndex + 1].id;
  final ss = supersetForExercise(workout, currentId);
  if (ss == null) return false;
  return ss.exerciseIds.contains(nextId);
}

/// Returns the workout list index of the first exercise that belongs to the
/// same superset as the exercise at [exerciseIndex]. Returns [exerciseIndex]
/// itself if that exercise is not in any superset. Walks backward through
/// the workout list — relies on the contiguous-block invariant.
int supersetGroupStartIndex(Workout workout, int exerciseIndex) {
  final exercise = workout.exercises[exerciseIndex];
  final ss = supersetForExercise(workout, exercise.id);
  if (ss == null) return exerciseIndex;
  for (var i = exerciseIndex - 1; i >= 0; i--) {
    if (!ss.exerciseIds.contains(workout.exercises[i].id)) return i + 1;
  }
  return 0;
}

/// Returns the effective set count for [exercise] inside [workout]:
/// - `superset.supersetSets` if the exercise is a member of a superset
///   that has set an override.
/// - `exercise.sets` otherwise (solo exercise, or member of a superset
///   whose `supersetSets` is null).
int setsForExerciseInWorkout(Workout workout, Exercise exercise) {
  final ss = supersetForExercise(workout, exercise.id);
  return ss?.supersetSets ?? exercise.sets;
}

/// True if every superset's members are a contiguous block in [exercises].
/// Order *within* the block is not constrained — only that there are no
/// non-member exercises interleaved with members.
bool supersetsRemainContiguous(
  List<Exercise> exercises,
  List<SupersetConfig> supersets,
) {
  for (final ss in supersets) {
    final indices = <int>[];
    for (var i = 0; i < exercises.length; i++) {
      if (ss.exerciseIds.contains(exercises[i].id)) indices.add(i);
    }
    if (indices.isEmpty) continue; // defensive: ignore stale ids
    if (indices.last - indices.first + 1 != indices.length) return false;
  }
  return true;
}

/// Strips [exerciseId] from every superset in [supersets]. Returns a new
/// list with supersets that drop below 2 members removed entirely.
/// Used after exercise deletion / removal-from-superset.
List<SupersetConfig> removeExerciseFromSupersets(
  String exerciseId,
  List<SupersetConfig> supersets,
) {
  final result = <SupersetConfig>[];
  for (final ss in supersets) {
    if (!ss.exerciseIds.contains(exerciseId)) {
      result.add(ss);
      continue;
    }
    final newIds = ss.exerciseIds.where((id) => id != exerciseId).toList();
    if (newIds.length >= 2) {
      result.add(ss.copyWith(exerciseIds: newIds));
    }
    // else: dissolve silently.
  }
  return result;
}
```

- [ ] **Step 4: Run — verify passes**

Run: `flutter test test/utils/superset_utils_test.dart`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/utils/superset_utils.dart test/utils/superset_utils_test.dart
git commit -m "feat(superset): add superset utility functions"
```

---

## Task 3: Timer — `supersetRest` phase + `supersetSets` reads + debug helpers

**Files:** `lib/models/rest_event.dart`, `lib/models/session_summary.dart`, `lib/providers/session_state_provider.dart`

This is the largest single task. The state machine reads `setsForExerciseInWorkout(workout, exercise)` everywhere it currently reads `exercise.sets`, so asymmetric supersets work transparently.

- [ ] **Step 1: Write failing timer tests**

Create `test/providers/session_state_provider_superset_test.dart`:
```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _e(String id, {int sets = 2}) => Exercise(
    id: id, title: id, description: 'd', label: 'l',
    sets: sets, reps: 1, timeBetweenReps: 0, timeBetweenSets: 60);

Session _ss2({int sets = 2, int ssRestSeconds = 10, int? supersetSets}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W', label: 'l', timeBetweenExercises: 120,
      exercises: [_e('e1', sets: sets), _e('e2', sets: sets)],
      supersets: [SupersetConfig(
          id: 'ss1', exerciseIds: ['e1', 'e2'],
          restSeconds: ssRestSeconds, supersetSets: supersetSets)],
    ),
  ]);
}

Session _ss3({int sets = 2}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W', label: 'l', timeBetweenExercises: 120,
      exercises: [_e('e1', sets: sets), _e('e2', sets: sets), _e('e3', sets: sets)],
      supersets: [SupersetConfig(
          id: 'ss1', exerciseIds: ['e1', 'e2', 'e3'], restSeconds: 15)],
    ),
  ]);
}

/// 2 exercises with different `sets` values, supersetSets overrides both.
Session _ssAsymmetric({required int e1Sets, required int e2Sets, required int supersetSets}) {
  return Session(title: 't', label: 'l', workouts: [
    Workout(
      title: 'W', label: 'l', timeBetweenExercises: 120,
      exercises: [_e('e1', sets: e1Sets), _e('e2', sets: e2Sets)],
      supersets: [SupersetConfig(
          id: 'ss1', exerciseIds: ['e1', 'e2'],
          restSeconds: 10, supersetSets: supersetSets)],
    ),
  ]);
}

void main() {
  group('supersetRest phase transitions', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('supersetRest duration comes from SupersetConfig.restSeconds', () {
      p.start(_ss2(ssRestSeconds: 15));
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.remaining, const Duration(seconds: 15));
    });

    test('supersetRest exerciseIndex points to next superset member', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.progress.exerciseIndex, 1);
    });

    test('supersetRest -> rep at next exercise', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 11)));
      expect(p.progress.phase, TimerPhase.rep);
      expect(p.progress.exerciseIndex, 1);
    });

    test('setRest from last exercise in 3-member superset resets to first exercise', () {
      p.start(_ss3(sets: 2));
      p.jumpToExercise(2); // last superset member
      p.debugSetPhase(TimerPhase.setRest);
      expect(p.progress.exerciseIndex, 2);
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 65)));
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 2);
      expect(p.progress.phase, TimerPhase.rep);
    });

    test('exerciseRest fires after final set of last superset exercise', () {
      p.start(_ss2(sets: 1));
      p.jumpToExercise(1); // last member
      p.debugSetPhase(TimerPhase.exerciseRest);
      expect(p.progress.phase, TimerPhase.exerciseRest);
    });

    test('supersetRest is logged in restEvents', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.debugRestEventTypes(), contains(RestType.supersetRest));
    });

    test('supersetRest is NOT overtime-eligible', () {
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.requestManualOvertime(), isFalse);
    });

    test('non-superset exercise unaffected: setRest goes to same exercise next set', () {
      final solo = Session(title: 't', label: 'l', workouts: [
        Workout(title: 'W', label: 'l', timeBetweenExercises: 120,
          exercises: [_e('solo', sets: 2)],
          supersets: [],
        ),
      ]);
      p.start(solo);
      p.debugSetPhase(TimerPhase.setRest);
      p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 65)));
      expect(p.progress.exerciseIndex, 0);
      expect(p.progress.currentSet, 2);
    });
  });

  group('supersetSets overrides exercise.sets in state machine', () {
    late SessionStateProvider p;
    setUp(() => p = SessionStateProvider());

    test('asymmetric superset: 3-set + 4-set with supersetSets=4 runs 4 rounds for both', () {
      p.start(_ssAsymmetric(e1Sets: 3, e2Sets: 4, supersetSets: 4));
      // Verify final set count perceived by state machine.
      // jumpToSet(4) on e1 should be valid (because supersetSets=4, not 3).
      p.jumpToSet(4);
      expect(p.progress.currentSet, 4);
      expect(p.progress.phase, TimerPhase.rep);
    });

    test('supersetSets=null falls back to first member exercise.sets', () {
      // Both members have sets=3; supersetSets is null → falls back to 3.
      p.start(_ss2(sets: 3));
      p.jumpToSet(3);
      expect(p.progress.currentSet, 3);
      // 4th set should not be reachable.
      p.jumpToSet(4);
      expect(p.progress.currentSet, 3);
    });
  });

  group('debug helpers (visible-for-testing)', () {
    test('debugSetPhase fires phase transition and resets remaining', () {
      final p = SessionStateProvider();
      p.start(_ss2());
      p.debugSetPhase(TimerPhase.supersetRest);
      expect(p.progress.phase, TimerPhase.supersetRest);
    });
  });
}
```

- [ ] **Step 2: Run — verify it fails**

Run: `flutter test test/providers/session_state_provider_superset_test.dart`
Expected: compile errors — `TimerPhase.supersetRest`, debug helpers, `RestType.supersetRest` do not exist

- [ ] **Step 3: Add `supersetRest` to `RestType` in `lib/models/rest_event.dart`**

```dart
enum RestType { getReady, setRest, supersetRest, exerciseRest, overtime, paused }
```

- [ ] **Step 4: Add `supersetRestTime` to `lib/models/session_summary.dart`**

The current `SessionSummary` class is final-fields-only with no `copyWith`. Add only what's needed:

```dart
final Duration supersetRestTime;
```

In the constructor, default to `Duration.zero`:
```dart
this.supersetRestTime = Duration.zero,
```

In `toJson()`:
```dart
'supersetRestTimeSeconds': supersetRestTime.inSeconds,
```

In `fromJson()`:
```dart
supersetRestTime: Duration(seconds: json['supersetRestTimeSeconds'] as int? ?? 0),
```

(Backward-compatible — old JSON without `supersetRestTimeSeconds` falls back to zero.)

**Do not add a `copyWith` to `SessionSummary`** — none exists today and adding one is out of scope.

- [ ] **Step 5: Update `session_state_provider.dart` — `TimerPhase` enum**

Add `supersetRest` after `setRest`:
```dart
enum TimerPhase {
  rep, repRest, setRest, supersetRest, exerciseRest,
  overtime, workoutComplete, paused, getReady,
}
```

Add import:
```dart
import 'package:flash_forward/utils/superset_utils.dart';
```

- [ ] **Step 6: Add `@visibleForTesting` debug helpers**

Inside `SessionStateProvider`, add:

```dart
@visibleForTesting
void debugSetPhase(TimerPhase phase) {
  if (_activeSession == null) return;
  final workout = _activeSession!.workouts[_progress.workoutIndex];
  final next = phase == TimerPhase.supersetRest
      ? SessionProgress(
          workoutIndex: _progress.workoutIndex,
          exerciseIndex: _progress.exerciseIndex + 1,
          currentSet: _progress.currentSet,
          currentRep: 1,
          phase: TimerPhase.supersetRest,
        )
      : _progress.copyWith(phase: phase);
  _onPhaseTransition(_progress.phase, next.phase, next);
  _progress = next;
  _remaining = _getDurationForPhase(_progress);
  notifyListeners();
}

@visibleForTesting
void debugSetLastTickAt(DateTime t) {
  _lastTickAt = t;
  // Trigger state machine catch-up using the gap as elapsed time.
  final gap = DateTime.now().difference(t);
  _advanceByElapsed(gap);
  _lastTickAt = DateTime.now();
  notifyListeners();
}

@visibleForTesting
List<RestType> debugRestEventTypes() =>
    _restEvents.map((e) => e.restType).toList();
```

`flutter/foundation.dart` is already imported (for `ChangeNotifier`); `@visibleForTesting` comes from there. If not, add `import 'package:flutter/foundation.dart';`.

- [ ] **Step 7: Update `_isRestPhase` and `_matchRestTypeToTimerPhase`**

`_isRestPhase` — add `p == TimerPhase.supersetRest ||` to the existing chain.

`_matchRestTypeToTimerPhase` — add case:
```dart
case TimerPhase.supersetRest:
  return RestType.supersetRest;
```

**Do NOT add `supersetRest` to `_isOvertimeEligible`.** Per design decision 10.

**Do NOT add `supersetRest` to the `reconcileAfterBackground` overtime gap check** ([line 553-557](lib/providers/session_state_provider.dart#L553-L557)). That specific branch triggers `_enterOvertime(automatic: true)` when the gap exceeds the rest duration; since supersetRest is not overtime-eligible, including it there is contradictory.

**This does NOT mean reconcileAfterBackground skips supersetRest entirely.** When the app returns to foreground during supersetRest, the function falls through to the existing `_advanceByElapsed(gap)` call, which rolls the state machine forward through whatever phases the gap covered (supersetRest → next member's rep → possibly into setRest → etc.) — same as it does for `repRest`. Backgrounded supersetRest reconciles correctly without auto-overtime.

**Audible beeps during background.** Beeps are scheduled via `_calculateFutureBeeps` + `BeepScheduler.scheduleAll`, which runs whenever a phase transitions and the app is backgrounded. Step 12 below adds the supersetRest go-beep to that simulation, so beeps continue while backgrounded.

**Overtime DOES still apply to setRest within a superset.** The "between rounds" rest of a superset (e.g. `set 1/A → supersetRest → set 1/B → setRest → set 2/A …`) uses `TimerPhase.setRest`, which remains overtime-eligible. Only the short intra-round transitions are not.

- [ ] **Step 8: Update `_getDurationForPhase` — add `supersetRest` case**

```dart
case TimerPhase.supersetRest:
  final ss = supersetForExercise(workout, exercise.id);
  return Duration(seconds: ss?.restSeconds ?? 15);
```

- [ ] **Step 9: Replace `exercise.sets` reads with `setsForExerciseInWorkout(workout, exercise)` in `_calculateNextState`**

Inside `_calculateNextState`, the four places that read `exercise.sets` must become `setsForExerciseInWorkout(workout, exercise)`. Concretely, replace the body:

```dart
SessionProgress? _calculateNextState(SessionProgress p) {
  if (_activeSession == null) return null;
  final Workout workout = _activeSession!.workouts[p.workoutIndex];
  final Exercise exercise = workout.exercises[p.exerciseIndex];
  final int effectiveSets = setsForExerciseInWorkout(workout, exercise);

  switch (p.phase) {
    case TimerPhase.rep:
      switch (exercise.type) {
        case ExerciseType.timedReps:
          final reps = exercise.reps ?? 1;
          if (exercise.timeBetweenReps > 0 && p.currentRep < reps) {
            return p.copyWith(phase: TimerPhase.repRest);
          }
          return _calculateNextState(p.copyWith(phase: TimerPhase.repRest));
        case ExerciseType.fixedDuration:
          if (p.currentSet >= effectiveSets) {
            if (hasNextInSuperset(workout, p.exerciseIndex)) {
              return SessionProgress(
                workoutIndex: p.workoutIndex,
                exerciseIndex: p.exerciseIndex + 1,
                currentSet: p.currentSet,
                currentRep: 1,
                phase: TimerPhase.supersetRest,
              );
            }
            return _enterExerciseRest(p);
          }
          if (hasNextInSuperset(workout, p.exerciseIndex)) {
            return SessionProgress(
              workoutIndex: p.workoutIndex,
              exerciseIndex: p.exerciseIndex + 1,
              currentSet: p.currentSet,
              currentRep: 1,
              phase: TimerPhase.supersetRest,
            );
          }
          return p.copyWith(phase: TimerPhase.setRest);
        case ExerciseType.manual:
          return null;
      }

    case TimerPhase.repRest:
      final reps = exercise.reps ?? 1;
      if (p.currentRep < reps) {
        return p.copyWith(currentRep: p.currentRep + 1, phase: TimerPhase.rep);
      }
      if (p.currentSet >= effectiveSets) {
        if (hasNextInSuperset(workout, p.exerciseIndex)) {
          return SessionProgress(
            workoutIndex: p.workoutIndex,
            exerciseIndex: p.exerciseIndex + 1,
            currentSet: p.currentSet,
            currentRep: 1,
            phase: TimerPhase.supersetRest,
          );
        }
        return _enterExerciseRest(p);
      }
      if (hasNextInSuperset(workout, p.exerciseIndex)) {
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: p.exerciseIndex + 1,
          currentSet: p.currentSet,
          currentRep: 1,
          phase: TimerPhase.supersetRest,
        );
      }
      return p.copyWith(phase: TimerPhase.setRest);

    case TimerPhase.setRest:
      if (p.currentSet < effectiveSets) {
        final groupStart = supersetGroupStartIndex(workout, p.exerciseIndex);
        return SessionProgress(
          workoutIndex: p.workoutIndex,
          exerciseIndex: groupStart,
          currentSet: p.currentSet + 1,
          currentRep: 1,
          phase: TimerPhase.rep,
        );
      }
      return _enterExerciseRest(p);

    case TimerPhase.supersetRest:
      return p.copyWith(phase: TimerPhase.rep);

    case TimerPhase.exerciseRest:
      return p.copyWith(
        phase: p.exerciseIndex == 0 ? TimerPhase.getReady : TimerPhase.rep,
      );
    case TimerPhase.getReady:
      return p.copyWith(phase: TimerPhase.rep);
    case TimerPhase.overtime:
      return null;
    case TimerPhase.workoutComplete:
      return null;
    case TimerPhase.paused:
      return null;
  }
}
```

Note: `setRest` for solo exercises is unaffected because `supersetGroupStartIndex` returns `p.exerciseIndex` for non-members.

- [ ] **Step 10: Update `advanceManually` for manual exercises in supersets**

```dart
void advanceManually() {
  if (_activeSession == null) return;
  final workout = _activeSession!.workouts[_progress.workoutIndex];
  final exercise = workout.exercises[_progress.exerciseIndex];
  if (exercise.type != ExerciseType.manual) return;
  if (_progress.phase != TimerPhase.rep) return;

  final effectiveSets = setsForExerciseInWorkout(workout, exercise);

  if (hasNextInSuperset(workout, _progress.exerciseIndex)) {
    final ss = supersetForExercise(workout, exercise.id);
    final next = SessionProgress(
      workoutIndex: _progress.workoutIndex,
      exerciseIndex: _progress.exerciseIndex + 1,
      currentSet: _progress.currentSet,
      currentRep: 1,
      phase: TimerPhase.supersetRest,
    );
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _remaining = Duration(seconds: ss?.restSeconds ?? 15);
  } else if (_progress.currentSet < effectiveSets) {
    final next = _progress.copyWith(phase: TimerPhase.setRest);
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _remaining = _getDurationForPhase(_progress);
  } else {
    final next = _progress.copyWith(phase: TimerPhase.exerciseRest);
    _onPhaseTransition(_progress.phase, next.phase, next);
    _progress = next;
    _remaining = _getDurationForPhase(_progress);
  }
  _rescheduleSound();
  notifyListeners();
}
```

- [ ] **Step 11: Update `updateActiveExercise` for clamping under `supersetSets`**

In `updateActiveExercise` ([session_state_provider.dart:343](lib/providers/session_state_provider.dart#L343)), the clamp uses `updated.sets` for max. Replace with `setsForExerciseInWorkout`:

```dart
final workout = _activeSession!.workouts[workoutIndex];
final updatedExercises = List<Exercise>.from(workout.exercises);
updatedExercises[exerciseIndex] = updated;
final updatedWorkout = workout.copyWith(exercises: updatedExercises);
final updatedWorkouts = List<Workout>.from(_activeSession!.workouts);
updatedWorkouts[workoutIndex] = updatedWorkout;
_activeSession = _activeSession!.copyWith(workouts: updatedWorkouts);

final effectiveSets = setsForExerciseInWorkout(updatedWorkout, updated);
final clampedSet = _progress.currentSet.clamp(1, effectiveSets);
final clampedRep = updated.reps != null
    ? _progress.currentRep.clamp(1, updated.reps!)
    : _progress.currentRep;
if (clampedSet != _progress.currentSet || clampedRep != _progress.currentRep) {
  _progress = _progress.copyWith(currentSet: clampedSet, currentRep: clampedRep);
}
notifyListeners();
```

This handles the case where the user updates `supersetSets` (Task 8 routes that update through here).

- [ ] **Step 12: Add `supersetRest` to `_addBeepsForPhase`**

`supersetRest` is short and has no countdown — only a go-beep at end. Match the existing `repRest` case pattern:

```dart
case TimerPhase.supersetRest:
  if (phaseEndAt.isAfter(now)) {
    beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.go));
  }
```

The simulation loop in `_calculateFutureBeeps` does not need any new break condition. The existing `BeepScheduler.maxBeeps` cap protects against unbounded simulation if a workout has many supersets.

- [ ] **Step 13: Update `_computeSummary` — track `supersetRestTime`**

```dart
var supersetRestTime = Duration.zero;
// inside the existing switch:
case RestType.supersetRest:
  supersetRestTime += e.actualDuration;
// in totalTime:
final totalTime = activeTime + interRepRestTime + setRestTime +
    supersetRestTime + exerciseRestTime + getReadyTime + overtime + pausedTime;
// in SessionSummary constructor call:
supersetRestTime: supersetRestTime,
```

- [ ] **Step 14: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_superset_test.dart`
Expected: all PASS

Run: `flutter test`
Expected: all PASS

- [ ] **Step 15: Commit**

```bash
git add lib/models/rest_event.dart lib/models/session_summary.dart \
        lib/providers/session_state_provider.dart \
        test/providers/session_state_provider_superset_test.dart
git commit -m "feat(superset): add supersetRest phase, supersetSets reads, debug helpers"
```

---

## Task 4: Superset modal

**Files:** `lib/presentation/screens/training_program_flow/superset_modal.dart`

This modal handles create, edit, and join in a single screen.

- [ ] **Step 1: Create `lib/presentation/screens/training_program_flow/superset_modal.dart`**

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flutter/material.dart';

class SupersetModalResult {
  /// Final ordered member ids. Empty/single-member means dissolve the superset.
  final List<String> memberIds;
  final int restSeconds;
  final int supersetSets;
  /// True if the user tapped the destructive Remove button.
  final bool dissolveRequested;

  const SupersetModalResult({
    required this.memberIds,
    required this.restSeconds,
    required this.supersetSets,
    this.dissolveRequested = false,
  });
}

class SupersetModal extends StatefulWidget {
  /// All exercises in the parent workout (for the "Add" section).
  final List<Exercise> workoutExercises;
  /// Other supersets in the workout — used to filter the "Add" section so
  /// exercises already in another superset are not offered.
  final List<SupersetConfig> otherSupersets;
  /// When non-null, editing an existing superset.
  final SupersetConfig? existing;
  /// When non-null, the user invoked "Add to superset" on this exercise:
  /// it is added to the member list pre-checked, regardless of [existing].
  final Exercise? joiningExercise;
  /// Members of the superset on entry (for rendering order).
  /// Required for both create and edit: the create-modal pre-fills with the
  /// invoking exercise + any auto-included members.
  final List<Exercise> initialMembers;

  const SupersetModal({
    super.key,
    required this.workoutExercises,
    required this.otherSupersets,
    required this.initialMembers,
    this.existing,
    this.joiningExercise,
  });

  @override
  State<SupersetModal> createState() => _SupersetModalState();
}

class _SupersetModalState extends State<SupersetModal> {
  late List<Exercise> _members;
  late final Set<String> _addCandidates;
  late final TextEditingController _restCtrl;
  late final TextEditingController _setsCtrl;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.initialMembers);
    _addCandidates = {};
    _restCtrl = TextEditingController(
      text: '${widget.existing?.restSeconds ?? 15}',
    );
    _setsCtrl = TextEditingController(
      text: '${_initialSupersetSets()}',
    );
  }

  /// Initial value for the supersetSets field:
  /// - Editing existing superset → use existing.supersetSets.
  /// - Creating: if all members have same sets, that value; else max().
  int _initialSupersetSets() {
    if (widget.existing?.supersetSets != null) {
      return widget.existing!.supersetSets!;
    }
    if (_members.isEmpty) return 3;
    final setCounts = _members.map((e) => e.sets).toSet();
    if (setCounts.length == 1) return setCounts.single;
    return _members.map((e) => e.sets).reduce((a, b) => a > b ? a : b);
  }

  @override
  void dispose() {
    _restCtrl.dispose();
    _setsCtrl.dispose();
    super.dispose();
  }

  void _removeMember(Exercise e) {
    setState(() => _members.remove(e));
  }

  void _toggleAdd(String id, bool? value) {
    setState(() {
      if (value == true) {
        _addCandidates.add(id);
      } else {
        _addCandidates.remove(id);
      }
    });
  }

  void _confirm() {
    // Pull in newly added exercises (preserving workout-list order).
    final ordered = <Exercise>[];
    for (final e in widget.workoutExercises) {
      if (_members.any((m) => m.id == e.id)) {
        ordered.add(_members.firstWhere((m) => m.id == e.id));
      } else if (_addCandidates.contains(e.id)) {
        ordered.add(e);
      }
    }
    // Members that were reordered within the modal keep their modal order
    // for the same-id slots, but newly-added exercises are inserted at their
    // workout-list position. Editor logic re-pulls the consecutive block
    // post-confirm, so workout-list order is fine.
    final rest = int.tryParse(_restCtrl.text) ?? 15;
    final sets = int.tryParse(_setsCtrl.text) ??
        _initialSupersetSets();
    Navigator.pop(
      context,
      SupersetModalResult(
        memberIds: ordered.map((e) => e.id).toList(),
        restSeconds: rest,
        supersetSets: sets,
      ),
    );
  }

  void _confirmDissolve() {
    Navigator.pop(
      context,
      SupersetModalResult(
        memberIds: const [],
        restSeconds: 0,
        supersetSets: 0,
        dissolveRequested: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addable = widget.workoutExercises.where((e) {
      if (_members.any((m) => m.id == e.id)) return false;
      // Hide exercises already in a different superset.
      for (final ss in widget.otherSupersets) {
        if (ss.exerciseIds.contains(e.id)) return false;
      }
      return true;
    }).toList();

    return AlertDialog(
      title: Text(widget.existing == null ? 'Create superset' : 'Edit superset'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Members', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No members yet — add exercises below.'),
                ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                itemCount: _members.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) newIndex -= 1;
                    final m = _members.removeAt(oldIndex);
                    _members.insert(newIndex, m);
                  });
                },
                itemBuilder: (ctx, i) {
                  final e = _members[i];
                  return ListTile(
                    key: ValueKey(e.id),
                    title: Text(e.title),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _removeMember(e),
                      tooltip: 'Remove from superset',
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (addable.isNotEmpty) ...[
                const Text('Add exercises', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...addable.map((e) => CheckboxListTile(
                      dense: true,
                      title: Text(e.title),
                      value: _addCandidates.contains(e.id),
                      onChanged: (v) => _toggleAdd(e.id, v),
                    )),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  const Expanded(child: Text('Sets')),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: _setsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Rest between exercises (s)')),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: _restCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: _confirmDissolve,
                    icon: Icon(Icons.link_off_rounded,
                        color: context.colorScheme.error),
                    label: Text(
                      'Remove superset',
                      style: context.bodyMedium
                          .copyWith(color: context.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _confirm,
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

Future<SupersetModalResult?> showSupersetModal({
  required BuildContext context,
  required List<Exercise> workoutExercises,
  required List<SupersetConfig> otherSupersets,
  required List<Exercise> initialMembers,
  SupersetConfig? existing,
  Exercise? joiningExercise,
}) =>
    showDialog<SupersetModalResult>(
      context: context,
      builder: (_) => SupersetModal(
        workoutExercises: workoutExercises,
        otherSupersets: otherSupersets,
        initialMembers: initialMembers,
        existing: existing,
        joiningExercise: joiningExercise,
      ),
    );
```

Note on the mismatch prompt: per design decision 3, when creating with mismatched member sets the modal shows the prompt as a **pre-filled `_setsCtrl`** with `max()` of member sets, accompanied by an **inline notice** rendered above the sets field when `_members.map((e) => e.sets).toSet().length > 1`. Add this inline notice in the build method, immediately above the Sets row:

```dart
if (widget.existing == null &&
    _members.map((e) => e.sets).toSet().length > 1) ...[
  Container(
    padding: const EdgeInsets.all(8),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: context.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'Members have different set counts (${_members.map((e) => e.sets).join(', ')}). Pick the number of sets the whole superset will run.',
      style: context.bodySmall,
    ),
  ),
],
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/screens/training_program_flow/superset_modal.dart
git commit -m "feat(superset): add superset create/edit/dissolve modal"
```

---

## Task 5: Workout editor — slidable wiring, color bar, mutation safety

**Files:** `lib/presentation/screens/training_program_flow/new_workout_screen.dart`

This task only handles slidable wiring, color rendering, and mutation safety (delete/copy/dissolve normalization). Whole-block drag is in Task 6.

- [ ] **Step 1: Add superset state and helpers to `_NewWorkoutScreenState`**

Add imports:
```dart
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/superset_modal.dart';
import 'package:uuid/uuid.dart';
```

Add helper methods inside `_NewWorkoutScreenState`:

```dart
SupersetConfig? _supersetForExercise(Exercise exercise) =>
    supersetForExercise(_workout, exercise.id);

int? _supersetIndexForExercise(Exercise exercise) {
  for (var i = 0; i < _workout.supersets.length; i++) {
    if (_workout.supersets[i].exerciseIds.contains(exercise.id)) return i;
  }
  return null;
}

Future<void> _onSupersetSlidableTap(Exercise exercise) async {
  final ss = _supersetForExercise(exercise);
  if (ss != null) {
    await _editSuperset(ss);
  } else {
    await _addToSuperset(exercise);
  }
}

Future<void> _addToSuperset(Exercise exercise) async {
  final supersets = _workout.supersets;
  if (supersets.isEmpty) {
    await _openCreateModal(initialExercise: exercise);
    return;
  }
  // Show popup menu: pick existing or create new.
  final picked = await showMenu<String>(
    context: context,
    position: const RelativeRect.fromLTRB(100, 200, 100, 200),
    items: [
      for (var i = 0; i < supersets.length; i++)
        PopupMenuItem<String>(
          value: supersets[i].id,
          child: Row(children: [
            Container(width: 4, height: 24,
                color: supersetColorForIndex(i)),
            const SizedBox(width: 8),
            Text('${supersets[i].exerciseIds.length} exercises: '
                '${_workout.exercises.firstWhere(
                  (e) => e.id == supersets[i].exerciseIds.first,
                  orElse: () => exercise,
                ).title}'),
          ]),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: '__new__',
        child: Text('Create new superset'),
      ),
    ],
  );
  if (picked == null) return;
  if (picked == '__new__') {
    await _openCreateModal(initialExercise: exercise);
  } else {
    final existing = supersets.firstWhere((s) => s.id == picked);
    await _editSuperset(existing, joining: exercise);
  }
}

Future<void> _openCreateModal({required Exercise initialExercise}) async {
  final result = await showSupersetModal(
    context: context,
    workoutExercises: _workout.exercises,
    otherSupersets: _workout.supersets,
    initialMembers: [initialExercise],
    existing: null,
  );
  if (result == null || result.dissolveRequested) return;
  if (result.memberIds.length < 2) return; // can't create with <2

  final newSs = SupersetConfig(
    exerciseIds: result.memberIds,
    restSeconds: result.restSeconds,
    supersetSets: result.supersetSets,
  );
  setState(() {
    _workout = _workout.copyWith(
      exercises: _reorderToContiguous(_workout.exercises, result.memberIds),
      supersets: [..._workout.supersets, newSs],
    );
  });
}

Future<void> _editSuperset(SupersetConfig ss, {Exercise? joining}) async {
  final initialMembers = _workout.exercises
      .where((e) => ss.exerciseIds.contains(e.id))
      .toList();
  if (joining != null && !initialMembers.any((m) => m.id == joining.id)) {
    initialMembers.add(joining);
  }
  final otherSupersets = _workout.supersets.where((s) => s.id != ss.id).toList();
  final result = await showSupersetModal(
    context: context,
    workoutExercises: _workout.exercises,
    otherSupersets: otherSupersets,
    initialMembers: initialMembers,
    existing: ss,
    joiningExercise: joining,
  );
  if (result == null) return;

  if (result.dissolveRequested || result.memberIds.length < 2) {
    setState(() {
      _workout = _workout.copyWith(
        supersets: _workout.supersets.where((s) => s.id != ss.id).toList(),
      );
    });
    return;
  }

  // Apply edits: update the SupersetConfig, ensure members are contiguous.
  final updated = ss.copyWith(
    exerciseIds: result.memberIds,
    restSeconds: result.restSeconds,
    supersetSets: result.supersetSets,
  );
  setState(() {
    _workout = _workout.copyWith(
      exercises: _reorderToContiguous(_workout.exercises, result.memberIds),
      supersets: _workout.supersets
          .map((s) => s.id == ss.id ? updated : s)
          .toList(),
    );
  });
}

/// Pulls all members listed in [memberIds] to be contiguous in the exercise
/// list, anchored at the position of the first member already in the list.
List<Exercise> _reorderToContiguous(
    List<Exercise> exercises, List<String> memberIds) {
  if (memberIds.length < 2) return exercises;
  final memberSet = memberIds.toSet();
  final firstAnchor = exercises.indexWhere((e) => memberSet.contains(e.id));
  if (firstAnchor == -1) return exercises;
  final members = <Exercise>[];
  final others = <Exercise>[];
  for (final e in exercises) {
    if (memberSet.contains(e.id)) {
      members.add(e);
    } else {
      others.add(e);
    }
  }
  // Sort members in the order specified by memberIds (modal-defined order).
  members.sort((a, b) =>
      memberIds.indexOf(a.id).compareTo(memberIds.indexOf(b.id)));
  // Insert the consecutive block at the position the anchor exercise occupied
  // among the non-members.
  final insertAt = exercises
      .sublist(0, firstAnchor)
      .where((e) => !memberSet.contains(e.id))
      .length;
  return [...others]..insertAll(insertAt, members);
}

void _normalizeSupersetsAfterDelete(String exerciseId) {
  final updated = removeExerciseFromSupersets(exerciseId, _workout.supersets);
  if (updated.length != _workout.supersets.length ||
      updated.any((s) => !_workout.supersets.any((o) =>
          o.id == s.id && o.exerciseIds.length == s.exerciseIds.length))) {
    _workout = _workout.copyWith(supersets: updated);
  }
}
```

- [ ] **Step 2: Update `_deleteExercise` to normalize supersets**

```dart
_deleteExercise(Exercise exercise) {
  setState(() {
    _workout = _workout.copyWith(
      exercises: _workout.exercises.where((e) => e.id != exercise.id).toList(),
      supersets: removeExerciseFromSupersets(exercise.id, _workout.supersets),
    );
  });
}
```

(`removeExerciseFromSupersets` from Task 2 silently dissolves supersets that drop below 2.)

- [ ] **Step 3: `_copyExercise` does not add the copy to a superset**

The existing `_copyExercise` already creates a new exercise with a fresh UUID. Per design decision 6, the copy is not added to the original's superset (its UUID isn't in any `exerciseIds` list). No change needed beyond ensuring the contiguity invariant: insert the copy at `index + 1` of the original. If the original is the *last* member of a superset, the copy lands right after the block — fine. If the original is in the *middle* of a superset, inserting at `index+1` puts the copy *inside* the block, breaking contiguity. Detection:

```dart
_copyExercise(Exercise exercise) {
  final newExercise = exercise.deepCopy();
  setState(() {
    final ss = _supersetForExercise(exercise);
    int insertAt;
    if (ss != null) {
      // Insert after the last member of the superset block.
      var lastMemberIndex = -1;
      for (var i = 0; i < _workout.exercises.length; i++) {
        if (ss.exerciseIds.contains(_workout.exercises[i].id)) {
          lastMemberIndex = i;
        }
      }
      insertAt = lastMemberIndex + 1;
    } else {
      insertAt = _workout.exercises.indexOf(exercise) + 1;
    }
    final newList = List<Exercise>.from(_workout.exercises)
      ..insert(insertAt, newExercise);
    _workout = _workout.copyWith(exercises: newList);
  });
}
```

- [ ] **Step 4: Update `_ExerciseCard` to render two slidable panes + leading color bar**

Replace the `_ExerciseCard` constructor to take an optional `paletteIndex`:

```dart
class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onSuperset;
  final VoidCallback? onSaveToCatalog;
  final int? paletteIndex; // non-null when exercise is a superset member

  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
    required this.onSuperset,
    this.onSaveToCatalog,
    this.paletteIndex,
  });
  // ...
}
```

In `build`, replace the `Slidable` with two-pane layout:

```dart
Slidable(
  key: ValueKey(exercise.id),
  startActionPane: ActionPane(
    motion: const ScrollMotion(),
    extentRatio: 0.22 * (onSaveToCatalog != null ? 2 : 1),
    children: [
      if (onSaveToCatalog != null) ...[
        SlidableAction(
          borderRadius: BorderRadius.circular(12),
          onPressed: (_) => onSaveToCatalog!(),
          backgroundColor: context.colorScheme.tertiary,
          foregroundColor: context.colorScheme.onTertiary,
          icon: Icons.save_alt_rounded,
          label: 'Save to\ncatalog',
        ),
        const SizedBox(width: 4),
      ],
      SlidableAction(
        borderRadius: BorderRadius.circular(12),
        onPressed: (_) => onCopy(),
        backgroundColor: context.colorScheme.secondary,
        foregroundColor: context.colorScheme.onSecondary,
        icon: Icons.copy_rounded,
        label: 'Copy',
      ),
    ],
  ),
  endActionPane: ActionPane(
    motion: const ScrollMotion(),
    extentRatio: 0.22 * 2,
    children: [
      SlidableAction(
        borderRadius: BorderRadius.circular(12),
        onPressed: (_) => onSuperset(),
        backgroundColor: context.colorScheme.tertiary,
        foregroundColor: context.colorScheme.onTertiary,
        icon: paletteIndex != null
            ? Icons.edit_rounded
            : Icons.link_rounded,
        label: paletteIndex != null ? 'Edit\nsuperset' : 'Add to\nsuperset',
      ),
      const SizedBox(width: 4),
      SlidableAction(
        borderRadius: BorderRadius.circular(12),
        onPressed: (_) => onDelete(),
        backgroundColor: context.colorScheme.error,
        foregroundColor: context.colorScheme.onError,
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
    ],
  ),
  child: GestureDetector(
    onTap: onTap,
    child: _cardBody(context),
  ),
)
```

Where `_cardBody(context)` is the existing card decoration wrapped to add a leading color bar when `paletteIndex != null`:

```dart
Widget _cardBody(BuildContext context) {
  final body = Container(
    /* existing decoration... */
  );
  if (paletteIndex == null) return body;
  return Stack(
    children: [
      body,
      Positioned(
        left: 0, top: 0, bottom: 0,
        child: Container(
          width: 4,
          decoration: BoxDecoration(
            color: supersetColorForIndex(paletteIndex!),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
          ),
        ),
      ),
    ],
  );
}
```

(Adapt the existing card-body extraction; the original code may have inline decoration. Move whatever's currently rendered inside the existing `Slidable.child` into `_cardBody` and apply the Stack+bar wrapper.)

- [ ] **Step 5: Wire callbacks in `itemBuilder`**

In the `ReorderableListView.builder.itemBuilder`, pass:

```dart
final paletteIndex = _supersetIndexForExercise(exercise);
return _ExerciseCard(
  // existing params
  onSuperset: () => _onSupersetSlidableTap(exercise),
  paletteIndex: paletteIndex,
);
```

- [ ] **Step 6: Run full test suite — should still pass**

Run: `flutter test`
Expected: all PASS (whole-block drag and `supersetSets` mid-session edits are not yet implemented; existing tests should still pass)

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_workout_screen.dart
git commit -m "feat(superset): workout editor slidable + modal wiring + color bar"
```

---

## Task 6: Whole-block drag in the workout list

**Files:** `lib/presentation/screens/training_program_flow/new_workout_screen.dart`

This is the trickiest task. We override `onReorder` to detect when the dragged exercise is a superset member and move all members as a unit, then validate contiguity post-move.

- [ ] **Step 1: Replace the existing `onReorder` callback**

In the `ReorderableListView.builder` ([new_workout_screen.dart:335](lib/presentation/screens/training_program_flow/new_workout_screen.dart#L335)):

```dart
onReorder: (int oldIndex, int newIndex) {
  setState(() {
    if (oldIndex < newIndex) newIndex -= 1;

    final exercises = List<Exercise>.from(_workout.exercises);
    final dragged = exercises[oldIndex];
    final draggedSuperset = supersetForExercise(_workout, dragged.id);

    if (draggedSuperset == null) {
      // Solo exercise — single-item move.
      final candidate = List<Exercise>.from(exercises)
        ..removeAt(oldIndex)
        ..insert(newIndex, dragged);
      if (!supersetsRemainContiguous(candidate, _workout.supersets)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot drop inside a superset')),
        );
        return;
      }
      _workout = _workout.copyWith(exercises: candidate);
      return;
    }

    // Superset member — move the whole block.
    final memberIds = draggedSuperset.exerciseIds.toSet();
    final blockIndices = <int>[];
    for (var i = 0; i < exercises.length; i++) {
      if (memberIds.contains(exercises[i].id)) blockIndices.add(i);
    }
    // (blockIndices is contiguous by invariant.)
    final blockStart = blockIndices.first;
    final blockEnd = blockIndices.last;
    final blockExercises = exercises.sublist(blockStart, blockEnd + 1);
    final remainder = [
      ...exercises.sublist(0, blockStart),
      ...exercises.sublist(blockEnd + 1),
    ];
    // The user dragged the exercise at oldIndex to newIndex *in the original
    // list*. Translate that into a target index in the remainder list.
    int targetInRemainder;
    if (newIndex <= blockStart) {
      targetInRemainder = newIndex;
    } else if (newIndex > blockEnd) {
      targetInRemainder = newIndex - blockExercises.length;
    } else {
      // newIndex is inside the block — no-op (the block can't move into itself).
      return;
    }
    targetInRemainder = targetInRemainder.clamp(0, remainder.length);

    final candidate = List<Exercise>.from(remainder)
      ..insertAll(targetInRemainder, blockExercises);

    if (!supersetsRemainContiguous(candidate, _workout.supersets)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot drop inside another superset')),
      );
      return;
    }
    _workout = _workout.copyWith(exercises: candidate);
  });
},
```

- [ ] **Step 2: Add a `proxyDecorator` to render the dragged stack visual**

Pass to `ReorderableListView.builder`:

```dart
proxyDecorator: (child, index, animation) {
  final exercise = _workout.exercises[index];
  final ss = _supersetForExercise(exercise);
  if (ss == null) return child;
  // Count siblings to compute stack-edge count.
  final siblingCount = ss.exerciseIds.length - 1;
  return Material(
    color: Colors.transparent,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = siblingCount; i > 0; i--)
          Positioned(
            top: i * 4.0,
            left: 0,
            right: 0,
            child: Container(
              height: 12,
              margin: EdgeInsets.symmetric(horizontal: i * 2.0),
              decoration: BoxDecoration(
                color: context.colorScheme.surface,
                border: Border.all(
                    color: context.colorScheme.outline.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        child,
      ],
    ),
  );
},
```

This renders peeking stack-edges *behind* the dragged card, with each successive edge slightly narrower and lower, so the drag visual reads as "this card represents a stack of N."

- [ ] **Step 3: Add a save-time invariant check**

In `_save()`, before the existing `validate()` call:

```dart
if (!supersetsRemainContiguous(_workout.exercises, _workout.supersets)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('A superset is broken — please re-create it')),
  );
  return;
}
```

This is a defense-in-depth guard. It should not normally fire because every editing path validates, but if a future code change accidentally produces a non-contiguous state, the bad state can't be persisted.

- [ ] **Step 4: Add unit tests for `_reorderToContiguous` and the contiguity logic**

Skipped — this is exercised through the existing `supersetsRemainContiguous` tests in Task 2 plus manual verification (next task). The reorder logic in `onReorder` is too tied to UI to unit-test cleanly without a widget test, which is out of scope for v1.

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_workout_screen.dart
git commit -m "feat(superset): whole-block drag with stack proxy + contiguity validation"
```

---

## Task 7: Session player UI

**Files:** `lib/presentation/screens/session_flow/session_active_screen.dart`

- [ ] **Step 1: Add `supersetRest` to the phase label string switch**

Find the phase-label switch (search for `TimerPhase.setRest:` patterns) and add:
```dart
case TimerPhase.supersetRest:
  phaseText = 'superset rest';
```

- [ ] **Step 2: Render leading color bar on the active exercise card during a superset**

In the active exercise card's build method, find the existing card decoration and wrap it the same way `_ExerciseCard` does in Task 5 step 4:

```dart
final activeWorkout = sessionStateData.activeWorkout;
final activeExercise = sessionStateData.activeExercise;
final ss = supersetForExercise(activeWorkout, activeExercise.id);
final paletteIndex = ss != null
    ? activeWorkout.supersets.indexWhere((s) => s.id == ss.id)
    : null;

// Wrap existing card body with the color-bar Stack when paletteIndex != null
// (use the same pattern as _ExerciseCard._cardBody from Task 5).
```

- [ ] **Step 3: Include `supersetRest` in the timer low-time color logic**

```dart
} else if ((phase == TimerPhase.setRest ||
    phase == TimerPhase.supersetRest ||
    phase == TimerPhase.exerciseRest) &&
    remaining < const Duration(seconds: 10)) {
  timerColor = context.colorScheme.secondary;
```

- [ ] **Step 4: Display sets-remaining UI uses `setsForExerciseInWorkout`**

Wherever the session player renders "Set N of M," replace `exercise.sets` reads with `setsForExerciseInWorkout(activeWorkout, activeExercise)`. Search for `.sets` references in the session-active screen and update each.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat(superset): session player – supersetRest UI, color bar, coming-up subtitle"
```

---

## Task 8: Mid-session edit routing for `supersetSets`

**Files:** `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`, `lib/providers/session_state_provider.dart`

When the user edits an exercise that is a superset member mid-session, the "sets" field reads from and writes to `superset.supersetSets` on the active session's workout. This requires the edit screen to know whether the exercise is a member.

- [ ] **Step 1: Add a method to `SessionStateProvider`**

Add to `session_state_provider.dart`:

```dart
/// Updates `supersetSets` on the superset that contains [exerciseId] in the
/// active session's workout at [workoutIndex]. No-op if the exercise is not
/// in any superset. Clamps `currentSet` to the new value.
void updateActiveSupersetSets({
  required int workoutIndex,
  required String exerciseId,
  required int newSupersetSets,
}) {
  if (_activeSession == null) return;
  final workout = _activeSession!.workouts[workoutIndex];
  final ssIndex = workout.supersets.indexWhere(
    (ss) => ss.exerciseIds.contains(exerciseId),
  );
  if (ssIndex == -1) return;
  final updated = workout.supersets[ssIndex]
      .copyWith(supersetSets: newSupersetSets);
  final newSupersets = List<SupersetConfig>.from(workout.supersets);
  newSupersets[ssIndex] = updated;
  final updatedWorkout = workout.copyWith(supersets: newSupersets);
  final updatedWorkouts = List<Workout>.from(_activeSession!.workouts);
  updatedWorkouts[workoutIndex] = updatedWorkout;
  _activeSession = _activeSession!.copyWith(workouts: updatedWorkouts);

  // Clamp progress to the new set count.
  if (_progress.workoutIndex == workoutIndex) {
    final activeExercise = updatedWorkout.exercises[_progress.exerciseIndex];
    final effectiveSets = setsForExerciseInWorkout(updatedWorkout, activeExercise);
    final clamped = _progress.currentSet.clamp(1, effectiveSets);
    if (clamped != _progress.currentSet) {
      _progress = _progress.copyWith(currentSet: clamped);
    }
  }
  notifyListeners();
}
```

Add the import for `SupersetConfig` if not already present.

- [ ] **Step 2: Update `new_exercise_screen.dart` to route sets edits**

The exercise edit screen currently has a `sets` field that writes to `Exercise.sets` via `copyWith`. Add a parameter `Workout? parentWorkout` so the screen knows the context:

- For catalog edits (no superset context), `parentWorkout` is null — write to `Exercise.sets` as today.
- For workout-editor edits and mid-session edits, `parentWorkout` is the parent workout. If the exercise is a superset member, the sets field reads from and writes to `superset.supersetSets`; if not, falls back to `exercise.sets`.

Concretely, in `new_exercise_screen.dart`:

```dart
class NewExerciseScreen extends StatefulWidget {
  final Exercise? exercise;
  final Workout? parentWorkout;
  // ...
  const NewExerciseScreen({super.key, this.exercise, this.parentWorkout, /* ... */});
}
```

Inside the state class, when initializing the sets controller:
```dart
final initialSets = widget.parentWorkout != null && widget.exercise != null
    ? setsForExerciseInWorkout(widget.parentWorkout!, widget.exercise!)
    : widget.exercise?.sets ?? 3;
_setsController = TextEditingController(text: '$initialSets');
```

In the save flow, detect superset membership and route accordingly:
```dart
final newSets = int.tryParse(_setsController.text) ?? exercise.sets;
final ss = widget.parentWorkout != null
    ? supersetForExercise(widget.parentWorkout!, exercise.id)
    : null;
if (ss != null && newSets != ss.supersetSets) {
  // Superset member — emit a separate "supersetSets change" signal alongside
  // the exercise update. The caller (workout editor or session screen) is
  // responsible for routing this to the appropriate provider.
  _supersetSetsChange = newSets;
}
final updated = exercise.copyWith(
  sets: ss != null ? exercise.sets : newSets, // keep original sets when in superset
  /* other fields */
);
```

Return both via the result tuple:
```dart
Navigator.pop(context, (
  exercise: updated,
  supersetSetsChange: _supersetSetsChange, // null when not changed or not in superset
));
```

The exact return type depends on the existing screen's signature; adapt to match. The two callers that need to handle this:

1. **`new_workout_screen.dart`** — when receiving the result, if `supersetSetsChange != null`, update the local `_workout.supersets` to reflect the new value (in addition to the exercise update).

2. **The session-active mid-edit flow** — when receiving the result, call `provider.updateActiveSupersetSets(workoutIndex: w, exerciseId: ex.id, newSupersetSets: change)` if `supersetSetsChange != null`, in addition to the existing `provider.updateActiveExercise(...)`.

Search for callers of `NewExerciseScreen` (e.g. mid-session edit dispatcher in the session player) and update each to consume the new tuple.

- [ ] **Step 3: Indicate in the UI that sets are superset-controlled**

When the exercise being edited is a superset member, render an inline notice next to the sets field:

```dart
if (widget.parentWorkout != null &&
    widget.exercise != null &&
    supersetForExercise(widget.parentWorkout!, widget.exercise!.id) != null) ...[
  const SizedBox(height: 4),
  Text(
    'Sets are controlled by the superset — changes apply to all members.',
    style: context.bodySmall.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    ),
  ),
],
```

- [ ] **Step 4: Run full test suite**

Run: `flutter test`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_exercise_screen.dart \
        lib/providers/session_state_provider.dart \
        lib/presentation/screens/training_program_flow/new_workout_screen.dart \
        lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat(superset): route sets edits to supersetSets for superset members"
```

---

## Task 9: Propagation regression tests

**Files:** `test/providers/preset_provider_superset_propagate_test.dart`

Five explicit tests, mirroring the helpers and assertion style of [test/providers/preset_provider_propagate_test.dart](test/providers/preset_provider_propagate_test.dart).

- [ ] **Step 1: Create the test file**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

Exercise _e({required String id, String? templateId, int sets = 3}) =>
    Exercise(
      id: id, templateId: templateId, title: id,
      description: 'd', label: 'push', sets: sets,
    );

SupersetConfig _ss({
  required String id,
  required List<String> exerciseIds,
  int restSeconds = 10,
  int? supersetSets,
}) => SupersetConfig(
  id: id, exerciseIds: exerciseIds,
  restSeconds: restSeconds, supersetSets: supersetSets,
);

Workout _w({
  required String id,
  String? templateId,
  String title = 'W',
  required List<Exercise> exercises,
  List<SupersetConfig> supersets = const [],
}) => Workout(
  id: id, templateId: templateId, title: title, label: 'push',
  exercises: exercises, timeBetweenExercises: 60, supersets: supersets,
);

Session _s({required String id, String title = 'S', required List<Workout> workouts}) =>
    Session(id: id, title: title, label: 'push', workouts: workouts);

void main() {
  late Directory tmpDir;
  late PresetProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('superset_propagate_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  test('1. workout edit propagates with supersets intact + independence', () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 4);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);

    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));
    await provider.addPresetSession(_s(id: 's2', workouts: [embedded.deepCopy(keepId: true)]));

    final updated = embedded.copyWith(timeBetweenExercises: 999);
    await provider.propagateWorkoutToSessionTemplates(updated);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    final s2 = provider.presetSessions.firstWhere((x) => x.id == 's2');

    // Both copies still carry the superset.
    expect(s1.workouts.single.supersets, hasLength(1));
    expect(s1.workouts.single.supersets.single.id, 'ss1');
    expect(s2.workouts.single.supersets, hasLength(1));
    expect(s2.workouts.single.supersets.single.id, 'ss1');

    // Independence: each session's superset is a separate Dart instance.
    expect(
      identical(s1.workouts.single.supersets.first,
                s2.workouts.single.supersets.first),
      isFalse,
    );

    // The new timeBetweenExercises propagated.
    expect(s1.workouts.single.timeBetweenExercises, 999);
    expect(s2.workouts.single.timeBetweenExercises, 999);
  });

  test('2. exercise edit does not drop the parent workout supersets', () async {
    final exA = _e(id: 'ex-a', sets: 3);
    final exB = _e(id: 'ex-b', sets: 3);
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 3);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));

    final updatedExA = exA.copyWith(title: 'Squat v2');
    await provider.propagateExerciseToSessionTemplates(updatedExA);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    final w = s1.workouts.single;
    expect(w.supersets, hasLength(1));
    expect(w.supersets.single.id, 'ss1');
    expect(w.supersets.single.exerciseIds, ['ex-a', 'ex-b']);
    expect(w.supersets.single.supersetSets, 3);
    // The exercise itself updated.
    expect(w.exercises.firstWhere((e) => e.id == 'ex-a').title, 'Squat v2');
  });

  test('3. editing the supersets list propagates the new list', () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final exC = _e(id: 'ex-c');
    final exD = _e(id: 'ex-d');
    final ss1 = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b']);
    final embedded = _w(
        id: 'cat-w', exercises: [exA, exB, exC, exD], supersets: [ss1]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));
    await provider.addPresetSession(_s(id: 's2', workouts: [embedded.deepCopy(keepId: true)]));

    final ss2 = _ss(id: 'ss2', exerciseIds: ['ex-c', 'ex-d']);
    final updated = embedded.copyWith(supersets: [ss1, ss2]);
    await provider.propagateWorkoutToSessionTemplates(updated);

    for (final id in ['s1', 's2']) {
      final s = provider.presetSessions.firstWhere((x) => x.id == id);
      expect(s.workouts.single.supersets.map((x) => x.id).toSet(),
          {'ss1', 'ss2'},
          reason: 'session $id missing supersets after propagation');
    }
  });

  test('4. second-pass propagation preserves supersets', () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b']);
    final catalogW = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    final embeddedA = _w(id: 'cat-w', exercises: [exA.deepCopy(keepId: true), exB.deepCopy(keepId: true)], supersets: [ss.copyWith()]);
    final embeddedB = _w(id: 'cat-w', exercises: [exA.deepCopy(keepId: true), exB.deepCopy(keepId: true)], supersets: [ss.copyWith()]);
    final sA = _s(id: 's-a', workouts: [embeddedA]);
    final sB = _s(id: 's-b', workouts: [embeddedB]);
    provider.debugSeedDefaults(workouts: [catalogW], sessions: [sA, sB]);

    // First-pass propagation.
    await provider.propagateWorkoutToSessionTemplates(
      catalogW.copyWith(timeBetweenExercises: 999),
    );
    // Second-pass propagation — different field, supersets must still survive.
    await provider.propagateWorkoutToSessionTemplates(
      catalogW.copyWith(timeBetweenExercises: 999, title: 'New Title'),
    );

    for (final session in provider.presetSessions) {
      final w = session.workouts.single;
      expect(w.supersets, hasLength(1));
      expect(w.supersets.single.id, 'ss1');
      expect(w.title, 'New Title');
    }
  });

  test('5. supersetSets survives propagation', () async {
    final exA = _e(id: 'ex-a', sets: 3);
    final exB = _e(id: 'ex-b', sets: 4);
    final ss = _ss(
        id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 5);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));

    final updated = embedded.copyWith(timeBetweenExercises: 90);
    await provider.propagateWorkoutToSessionTemplates(updated);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    expect(s1.workouts.single.supersets.single.supersetSets, 5);
    expect(s1.workouts.single.timeBetweenExercises, 90);
  });
}
```

- [ ] **Step 2: Run**

Run: `flutter test test/providers/preset_provider_superset_propagate_test.dart`
Expected: all PASS — propagation already works because `Workout.deepCopy` and `Workout.copyWith` carry `supersets` through.

- [ ] **Step 3: Commit**

```bash
git add test/providers/preset_provider_superset_propagate_test.dart
git commit -m "test(superset): verify supersets survive every propagation path"
```

---

## Verification Checklist (manual smoke test)

- [ ] **Create with uniform sets:** Workout with 3 exercises, all sets=3. Slidable right-to-left on exercise 1 → "Add to superset." No existing supersets → modal opens directly with exercise 1 pre-listed. Add exercise 3 via checkbox. Sets field auto-fills with 3 (no prompt). Confirm → exercises reorder to [1, 3, 2], 1 and 3 show colored leading bars, both run 3 supersetSets.

- [ ] **Create with mismatched sets:** Workout with exercises A(sets=3), B(sets=5). Add to superset → modal opens, inline notice "Members have different set counts (3, 5)" appears, sets field pre-fills with 5. User can change to any value. Confirm → both members run 5 sets in the timer.

- [ ] **Add to existing superset (popup chooser):** Workout has superset SS1 = [A, B]. Slidable on solo exercise C → "Add to superset" → popup menu with SS1 (color bar + "2 exercises: A") + "Create new superset." Pick SS1 → modal opens with A, B, C as members. supersetSets pre-fills with SS1's existing value (no prompt even if C.sets differs). Confirm → C joins SS1.

- [ ] **Edit superset (open modal):** Slidable on a superset member shows "Edit superset" not "Add to superset." Modal lists members with trash icons, addable solo exercises with checkboxes, sets, rest, "Remove superset" button.

- [ ] **Trash removes member, doesn't remove from workout:** Tap trash icon next to member B in modal. B disappears from member list. Confirm → B is solo in the workout, A and C are still in the superset.

- [ ] **Auto-dissolve when count drops below 2:** Edit a 2-member superset, trash one member, confirm → superset dissolves silently, both exercises become solo.

- [ ] **Remove superset button:** Edit a superset, tap "Remove superset" → all members become solo, exercises stay in the workout.

- [ ] **Within-block reorder via modal:** Edit a superset with 3 members. Drag member B above A in the modal's member list. Confirm → workout order updates to [B, A, C]. Block stays contiguous.

- [ ] **Whole-block drag (long-press):** Workout `[A, {B,C}, D, E]` (B,C in superset). Long-press B → drag visual shows B card + 1 stack-edge. Drop after E → workout reorders to `[A, D, E, B, C]`. Per-card color bars persist on B and C.

- [ ] **Reject solo into block:** Workout `[A, {B,C}, D]`. Drag A and try to drop between B and C. Snap-back + snackbar.

- [ ] **Reject block into block:** Workout `[{A,B}, {C,D}]`. Drag A's block toward C-D and try to drop between C and D. Snap-back + snackbar.

- [ ] **Copy doesn't join superset:** Workout `{A,B}` superset. Slidable Copy on A → new exercise A2 appears immediately after the block (after B), not inside. Block stays `{A,B}`.

- [ ] **Delete strips superset:** Workout `{A,B,C}`. Slidable Delete on B → workout becomes `{A,C}`, superset still has 2 members.

- [ ] **Delete dissolves on count<2:** Workout `{A,B}`. Slidable Delete on B → A becomes solo, superset gone.

- [ ] **Run a session — symmetric:** Workout `{A,B}` with supersetSets=2, restSeconds=8.
  Sequence: getReady → set1/A rep → 8s supersetRest → set1/B rep → setRest → set2/A → supersetRest → set2/B → exerciseRest.

- [ ] **Run a session — asymmetric:** A has sets=3, B has sets=5, supersetSets=4. Both run 4 rounds.

- [ ] **`supersetRest` UI:** During supersetRest, "Coming up" subtitle appears, exercise card shows the next member with leading color bar, timer turns yellow at <10s.

- [ ] **`supersetRest` not overtime:** Tap "+" overtime button during supersetRest → no effect.

- [ ] **Mid-session sets edit:** Open a superset member's edit screen during a session, change sets from 4 to 3, save. Both members of the superset reflect 3 going forward. Inline notice "Sets are controlled by the superset" was visible during edit.

- [ ] **Catalog sets edit on superset member:** Same as above but in the workout editor. Saving propagates the new supersetSets to all sibling embedded workouts in sessions (propagation prompt fires).

- [ ] **Save broken state guard:** (Hard to trigger from UI; skip unless implementing developer override.)

---

## Key Design Decisions (recap)

- **Workout-level supersets** is reorder-safe and propagation-free: `deepCopy` carries the list, lookups by exercise id continue to work.
- **`supersetSets` overrides per-exercise sets** without destroying them. Members keep their original `sets` for restoration on leave.
- **Contiguous-block invariant** is enforced at every mutation point (delete, copy, modal edit, list reorder). The save-time check is defense-in-depth.
- **`supersetRest` is not overtime-eligible**: a mandatory short pause to switch equipment.
- **`setRest` from a superset member** uses `supersetGroupStartIndex` to walk back to the first list-position of the contiguous block. For solo exercises this is a no-op.
- **Slidable two-pane layout** keeps the additive (Save/Copy) gestures distinct from modifying (Superset/Delete). Fixed per-action width via `extentRatio: 0.22 * actionCount`.
- **Per-superset color bar on the leading edge** is the only visual indicator. No badge widget; no continuous strip. Same color appears on the session player active card during the superset.
