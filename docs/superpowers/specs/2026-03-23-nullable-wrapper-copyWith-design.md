# Design: `Nullable<T>` wrapper for `copyWith` nullable field clearing

**Date:** 2026-03-23
**Status:** Approved

## Problem

Dart `copyWith` methods cannot distinguish `null` ("clear this field") from an omitted argument ("keep the current value"). The workaround in use — a private `_keep` sentinel (`Object? field = _keep`) — works but is type-unsafe (requires `as T?` casts) and non-obvious to new contributors.

## Chosen approach: `Nullable<T>` wrapper

A single utility class resolves the ambiguity type-safely:

```dart
class Nullable<T> {
  final T? value;
  const Nullable(this.value);
}
```

| Intent | Call site |
|---|---|
| Keep existing value | omit the parameter |
| Set to a non-null value | `copyWith(rpe: Nullable(5))` |
| Clear to null | `copyWith(rpe: Nullable(null))` |

## Scope

### New file
- `lib/utils/nullable.dart` — defines `Nullable<T>`

### Models updated

**`Workout`** — add `Nullable` to: `description`, `notes`, `difficulty`, `equipment`
**`Session`** — replace existing sentinels + add: `description`, `notes`, `rpe`, `completedAt`, `maxGradeClimbed`, `maxGradeFlashed`, `bodyWeightKg`
**`Exercise`** — replace existing sentinels + add: `reps`, `rpe`, `notes`, `loadUnit`, `equipment`, `muscleGroups`, `difficulty`

Remove the private `const Object _keep = Object()` from each model file once migrated.

### Call sites updated
- `session_active_bottom_bar.dart` — wrap `maxGradeClimbed`, `maxGradeFlashed`, `bodyWeightKg` in `Nullable(...)`
- `session_active_screen.dart` — any sentinel fields passed explicitly
- `new_workout_screen.dart` — replace constructor call in `_save()` with `_workout.copyWith(...)`
- Any other callers that pass explicit null to sentinel fields

## Non-goals
- No changes to `toJson` / `fromJson` / `deepCopy`
- No changes to non-nullable fields
- No code generation added
