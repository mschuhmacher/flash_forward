# Unified edit model, deferred propagation & 90-day trash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the silent default-edit fork with a single edit model where every catalog item edits in place; defer all writes (save & propagation) until the outermost edit screen commits, so cancelling at any level discards everything below; route all deletes through a 90-day cloud-synced trash; let users lift session-embedded items into the catalog via a slidable action; and fix the underlying mutability bug that lets catalog edits leak into session templates before Save.

**Architecture:**
- One catalog list per kind. The first time a default item is saved (with edits), it is "promoted" into the user collection at the same id; defaults remain seeded from `kDefault*` constants but are shadowed by the user-list copy when ids match. There is no separate "is this a default?" check at save time.
- Edit screens own a deep copy of their input. All nested edits (an exercise inside a workout, a workout inside a session) accumulate as pending changes on the outer screen; nothing reaches the provider until the outermost screen's Save fires.
- On Save, a single combined propagation prompt covers everything that changed at any nested level. The prompt enumerates affected sessions/workouts by name. Yes propagates everywhere; No keeps other consumers on the previous content. Cancel at any level discards all pending changes.
- All deletions move the item to a cloud-synced trash with a `deletedAt` timestamp. After 90 days, items are purged on app start. A Settings screen lets users restore by checkboxes; the catalog screen shows an Undo SnackBar after each delete. Deletion confirms enumerate the item's references.
- A "Save to catalog" slidable action on session-embedded workouts (and workout-embedded exercises) lets users lift unique items into the catalog; title collisions force a rename via the same dialog used elsewhere.

**Tech Stack:** Flutter (Dart), Provider, Supabase (cloud sync), shared_preferences (local prefs), local JSON files via `PresetLogger`.

---

## File Structure

### New files
- `lib/services/trash_service.dart` — local read/write of `trash.json` plus 90-day purge logic.
- `lib/models/trash_entry.dart` — discriminated union of (Session | Workout | Exercise) + `deletedAt` + `kind`.
- `lib/presentation/screens/settings/restore_items_screen.dart` — sectioned picker UI (Sessions / Workouts / Exercises) with per-row "Expires in N days" and bulk Restore.
- `lib/presentation/widgets/rename_on_collision_dialog.dart` — shared dialog used in three flows: Save to catalog, restore from trash, propagate-replacing-existing.
- `lib/presentation/widgets/propagate_changes_dialog.dart` — already exists; extended to render a multi-section list when multiple kinds of changes propagate at once.
- `test/services/trash_service_test.dart`, `test/providers/preset_provider_promote_default_test.dart`, `test/providers/preset_provider_trash_test.dart`, `test/providers/preset_provider_save_to_catalog_test.dart`.

### Modified files
- `lib/data/default_workout_data.dart` — `_findInstance` returns the catalog Exercise directly (no `deepCopy`). Embedded exercise ids now match the catalog ids. (See Data invariants §1.)
- `lib/models/workout.dart`, `lib/models/exercise.dart`, `lib/models/session.dart` — `deepCopy()` gains a `keepId` flag (no other behavioral change). `templateId` field stays — single meaning: source breadcrumb. Drop comments referencing the old "modified default" meaning.
- `lib/providers/preset_provider.dart` — remove `isDefaultItem`, `isModifiedDefault`, `_hiddenDefaultIds`, `hideDefaultItem`, `restoreAllDefaults`, `_loadHiddenDefaultIds`, `_saveHiddenDefaultIds`, `userCreated*Count`, `allKnown*Titles`, `presetDefaultSessions`, `presetUserSessions` (after audit). Add `promoteAndUpdate*`, `deleteToTrash`, `restoreFromTrash`, `liftToCatalog`, `usagesOf*`, and shadow rules. Wire `TrashService` into init/CRUD.
- `lib/services/supabase_sync_service.dart` — add upload/delete for trash entries and a fetch for full trash list.
- `lib/services/sync_queue_service.dart` — add `uploadTrashEntry`, `deleteTrashEntry` operation types (matches existing pattern).
- `lib/presentation/screens/training_program_flow/new_workout_screen.dart` — deep-copy `_workout` from `widget.workout`; track pending nested exercise edits in local state; remove the default-fork branch and `_isEditingDefault`; remove `allKnownWorkoutTitles`. On Save (when entered standalone from catalog), commit + run combined propagation. On Save (when entered from a session edit), return the modified workout to the parent without committing.
- `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` — same pattern; track no nested edits (exercises are leaves) but otherwise mirror the workout screen for nested vs standalone.
- `lib/presentation/screens/training_program_flow/new_session_screen.dart` — deep-copy `_session`; track pending workout/exercise edits accumulated through drilldowns; remove default-fork branch. On Save: commit session + run combined propagation across all accumulated changes.
- `lib/presentation/screens/training_program_flow/catalog_screen.dart` — slidable Delete routes through trash for all items (defaults and user); single confirmation dialog enumerates references; show Undo SnackBar.
- `lib/presentation/screens/training_program_flow/add_item_screen.dart` — selecting items from the catalog returns a deep-copy (`keepId: false`) for sessions, so embedded copies are independent right from add. Keeps the existing per-screen mutability protection working uniformly.
- `lib/presentation/screens/root_screen.dart` — replace "Restore defaults" tile with "Restore items" → `RestoreItemsScreen`. Delete `_showRestoreDefaultsDialog`.
- `lib/utils/default_edit_tip.dart` — DELETE.
- `lib/data/default_workout_data.dart`, `lib/data/default_session_data.dart` — update id-stability comments to reference trash + sync, not `_hiddenDefaultIds`.

---

## Data invariants (read carefully — these shape every task below)

1. **Embedded exercise ids equal catalog ids.** `kDefaultWorkouts` builds its exercises by direct reference, not `deepCopy`. So `'climbing-warm-up'.exercises[0].id == 'repeaters'`. This makes promote-on-edit and propagation work for exercises embedded in default workouts, and gives a stable id for future progress tracking. Mutability is no longer enforced at the default-data layer — edit screens deep-copy on open, which is the right place for that.
2. **Single source of truth at consumption.** `presetWorkouts` (and friends) returns one row per id. If an id appears in `_userWorkouts`, the user copy wins; the default shadow is hidden. If an id appears in trash, it is hidden from `presetWorkouts` regardless of source list. This replaces `_hiddenDefaultIds`.
3. **Promotion on first save.** When the user saves a non-new edit to an item whose id is currently only in `_default*`, the new content is added to `_user*` (with the same id, `userId` populated) and persisted via `PresetLogger`. The default constant is untouched. The user-list copy shadows it on read.
4. **Edit screens own a deep copy.** `_workout` / `_session` are independent from `widget.workout` / `widget.session`. Mutations stay local until Save commits via the provider.
5. **Outer-shell save semantics.** Nested edits never write to the provider. A workout edited inside a session edit returns to the session screen as a pending change; the session screen accumulates those changes and commits them all when its Save fires. Cancellation at any level discards everything below.
6. **Combined propagation prompt.** A single dialog at the outermost Save lists every modified item that has consumers elsewhere. The prompt is one yes/no — Yes propagates everything, No keeps other consumers on previous content.
7. **Trash uses `deletedAt` and is cloud-synced.** Trash entries store the full item JSON plus `deletedAt`. Items past 90 days are purged on init. Trash is visible across devices via Supabase.
8. **`templateId` is a source-breadcrumb only.** It points to the item this was deep-copied from. Used by propagation lookup (match on id OR templateId) and by future progress-tracking features. The old "this user item is a fork of a default" meaning is removed.
9. **Save to catalog rule.** A session-embedded workout's slidable "Save to catalog" action is visible iff the workout's id isn't already in `presetWorkouts` (and not in trash). On tap, if the title collides with an existing catalog item, show the rename dialog. Same rule for exercises embedded in workouts.
10. **Id collision invariants.** Within a kind (workout / exercise / session), an id appears in at most one of `_userX` or `_trashedItems`. Defensive code in promote/delete/restore enforces this; tests verify it.

---

## Task List Overview

### Phase 1 — Foundations: deep-copy on edit, default-data fix, models
- [ ] Task 1: `Workout.deepCopy({keepId})` and `Exercise.deepCopy({keepId})` + tests
- [ ] Task 2: `Session.deepCopy({keepId})` + tests
- [ ] Task 3: Remove `deepCopy()` from `_findInstance` in `default_workout_data.dart`; embedded exercise ids now equal catalog ids
- [ ] Task 4: `NewWorkoutScreen` initializes `_workout` from a `keepId: true` deep copy + manual repro
- [ ] Task 5: `NewSessionScreen` initializes `_session` from a `keepId: true` deep copy + manual repro
- [ ] Task 6: `AddItemScreen` returns `deepCopy()` (fresh ids) when adding to a session, so embedded copies are independent

### Phase 2 — Pending-changes tracking on edit screens (no provider writes mid-edit)
- [ ] Task 7: Define `PendingChange` (kind, item) and `PendingChangeBag` helper
- [ ] Task 8: `NewWorkoutScreen` accumulates pending exercise edits in local state; nested exercise saves return the new exercise without provider write; cancel discards
- [ ] Task 9: `NewSessionScreen` accumulates pending workout edits AND nested exercise edits
- [ ] Task 10: `NewExerciseScreen` operates the same way: returns the modified exercise to its parent without writing to the provider when invoked nested

### Phase 3 — `PresetProvider`: shadow rules, promotion, propagation
- [ ] Task 11: `presetWorkouts/Exercises/Sessions` shadow `_default*` by `_user*` ids + tests
- [ ] Task 12: `promoteAndUpdateWorkout/Exercise/Session(item)` — single entry that promotes if needed and updates if exists + tests
- [ ] Task 13: `usagesOfWorkout(id) → List<Session>`, `usagesOfExercise(id) → List<({Session, Workout})>` + tests (replaces existing `sessionTemplatesUsing*` / `sessionWorkoutPathsUsingExercise`)
- [ ] Task 14: `commitChanges(PendingChangeBag)` — one entry from edit screens; runs all promotes in order, returns the propagation surface (which ids changed and what they affect) + tests
- [ ] Task 15: Combined propagation prompt rendering: `propagate_changes_dialog` accepts grouped sections (workouts changed → sessions affected; exercises changed → workouts affected) + screenshot test or visual verification

### Phase 4 — Wire edit-screen Saves to the new commit path
- [ ] Task 16: `NewWorkoutScreen._save()` (standalone-from-catalog mode): build `PendingChangeBag` from `_workout` + accumulated exercise pending changes; call `commitChanges`; show combined propagation prompt
- [ ] Task 17: `NewWorkoutScreen` (nested-from-session mode): return `_workout` and pending bag to parent without committing
- [ ] Task 18: `NewExerciseScreen._save()` (standalone): same pattern — bag with one exercise change, commit, propagate
- [ ] Task 19: `NewExerciseScreen` (nested): return without committing
- [ ] Task 20: `NewSessionScreen._save()`: build full bag (session + workouts + exercises), commit, propagate
- [ ] Task 21: Manual repro of user's original bug: edit a default workout's exercise inside a session edit; on session Save, propagation prompt names other sessions using the workout

### Phase 5 — Strip default-fork machinery
- [ ] Task 22: Remove `_isEditingDefault`, `allKnown*Titles` branch, copy-on-edit-default save path, and tip-dialog calls from all three edit screens
- [ ] Task 23: Remove `isDefaultItem`, `isModifiedDefault`, `_hiddenDefaultIds`, `hideDefaultItem`, `restoreAllDefaults`, `_loadHiddenDefaultIds`, `_saveHiddenDefaultIds`, `userCreated*Count`, `allKnown*Titles`, `presetDefaultSessions/UserSessions` (after audit) from `PresetProvider`
- [ ] Task 24: Delete `lib/utils/default_edit_tip.dart` and confirm zero callsites
- [ ] Task 25: Update default-data file comments

### Phase 6 — Trash service + cloud sync
- [ ] Task 26: `TrashEntry` model + JSON round-trip test
- [ ] Task 27: `TrashService` (read/write/purge at 90 days) + tests
- [ ] Task 28: Supabase: `trash_entries` table, `uploadTrashEntry`/`deleteTrashEntry` in `SupabaseSyncService`, queue ops in `SyncQueueService`
- [ ] Task 29: `PresetProvider` wires `TrashService`: init purges + loads, `trashedItems` getter, `deleteToTrash`, `restoreFromTrash` (with title-collision rename dialog), `liftToCatalog` (with title-collision rename dialog) + tests
- [ ] Task 30: Update shadow rules: items currently in trash hide their default/user shadows in `presetWorkouts/Exercises/Sessions`

### Phase 7 — Catalog & settings UI
- [ ] Task 31: Catalog slidable Delete: routes through `deleteToTrash`; confirmation dialog enumerates references ("Used in: Session A, Session B"); after delete, show Undo SnackBar with 5s window
- [ ] Task 32: `RestoreItemsScreen` with sections, "Expires in N days" subtitle, bulk restore action; replace settings tile
- [ ] Task 33: Slidable "Save to catalog" action on workout cards inside session edit screen and exercise cards inside workout edit screen; visible iff id-not-in-catalog; on tap, rename-on-collision

### Phase 8 — Cleanup
- [ ] Task 34: `flutter analyze` clean (no new warnings)
- [ ] Task 35: `flutter test` green
- [ ] Task 36: End-to-end smoke verification

---

## Phase 1 — Foundations

### Task 1: `Workout.deepCopy({keepId})` and `Exercise.deepCopy({keepId})` + tests

**Files:**
- Modify: `lib/models/workout.dart:95-106`
- Modify: `lib/models/exercise.dart:152-172`
- Test: `test/models/workout_deep_copy_test.dart` (CREATE)

**Why:** Edit screens need a deep, independent copy that preserves the id (so save targets the right row) but owns its own `exercises` list. The existing `deepCopy()` is used by the "start a session" flow which needs a fresh id. One method, two modes via a flag.

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';

void main() {
  Workout sample() => Workout(
        id: 'w-1',
        templateId: null,
        title: 't',
        label: 'l',
        exercises: [
          Exercise(id: 'e-1', title: 'a', description: 'd', label: 'l'),
        ],
        timeBetweenExercises: 60,
      );

  test('deepCopy(): new id, fresh exercises with new ids, templateId chain set', () {
    final src = sample();
    final dst = src.deepCopy();
    expect(dst.id, isNot('w-1'));
    expect(dst.templateId, 'w-1');
    expect(dst.exercises.single.id, isNot('e-1'));
    expect(dst.exercises.single.templateId, 'e-1');
    expect(identical(dst.exercises, src.exercises), isFalse);
  });

  test('deepCopy(keepId: true): same id, fresh exercises with same ids, templateId untouched', () {
    final src = sample();
    final dst = src.deepCopy(keepId: true);
    expect(dst.id, 'w-1');
    expect(dst.templateId, isNull);
    expect(dst.exercises.single.id, 'e-1');
    expect(dst.exercises.single.templateId, isNull);
    expect(identical(dst.exercises, src.exercises), isFalse);
    expect(identical(dst.exercises.single, src.exercises.single), isFalse);
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
// workout.dart
Workout deepCopy({bool keepId = false}) => Workout(
      id: keepId ? id : null,
      templateId: keepId ? templateId : (templateId ?? id),
      title: title,
      label: label,
      description: description,
      exercises: exercises.map((e) => e.deepCopy(keepId: keepId)).toList(),
      difficulty: difficulty,
      equipment: equipment,
      timeBetweenExercises: timeBetweenExercises,
      userId: userId,
      notes: notes,
    );

// exercise.dart
Exercise deepCopy({bool keepId = false}) => Exercise(
      id: keepId ? id : null,
      templateId: keepId ? templateId : (templateId ?? id),
      // all other fields unchanged
    );
```

- [ ] **Step 4: Run** — PASS. Existing propagation tests must still pass (they call `deepCopy()` with no args).

- [ ] **Step 5: Commit**

```bash
git add lib/models/workout.dart lib/models/exercise.dart test/models/workout_deep_copy_test.dart
git commit -m "feat(models): add keepId flag to Workout/Exercise deepCopy"
```

---

### Task 2: `Session.deepCopy({keepId})` + tests

**Files:**
- Modify: `lib/models/session.dart:152-162`
- Test: `test/models/session_deep_copy_test.dart` (CREATE)

- [ ] **Step 1: Write failing test** (mirror Task 1 for Session).

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
Session deepCopy({bool keepId = false}) => Session(
      id: keepId ? id : null,
      templateId: keepId ? templateId : (templateId ?? id),
      title: title,
      label: label,
      description: description,
      workouts: workouts.map((w) => w.deepCopy(keepId: keepId)).toList(),
      userId: userId,
    );
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(models): add keepId flag to Session.deepCopy"
```

---

### Task 3: Default workouts use catalog exercises directly (no deepCopy)

**Files:**
- Modify: `lib/data/default_workout_data.dart:6-14`

**Why:** Currently `_findInstance` calls `template.deepCopy()`, giving each embedded exercise a runtime-generated id. That breaks promote-on-edit and propagation for any exercise edited via a default workout drilldown. With edit screens now owning a deep copy on open (Tasks 4-5), there's no need for `kDefaultWorkouts` to defensively copy — embedded references can equal catalog references.

- [ ] **Step 1: Replace `_findInstance`**

Before:
```dart
Exercise _findInstance(String id) {
  final template = kDefaultExercises.firstWhere((t) => t.id == id);
  return template.deepCopy();
}
```

After:
```dart
// Returns the catalog Exercise directly. Edit screens deep-copy on open, so
// mid-edit mutations cannot leak through this reference.
Exercise _exerciseRef(String id) =>
    kDefaultExercises.firstWhere((t) => t.id == id);
```

Update all callers in the file (`_findInstance(...)` → `_exerciseRef(...)`).

- [ ] **Step 2: Update the comment block** at the top of the file to reflect the new semantics: "Embedded exercise ids equal catalog ids; mutations are protected by edit-screen deep-copy on open."

- [ ] **Step 3: Run** — `flutter test`. Existing tests should still pass; if any test asserted that embedded exercise ids differed from catalog ids, update it.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(defaults): default workouts reference catalog exercises directly"
```

---

### Task 4: `NewWorkoutScreen` deep-copies its input

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart:46-53`

**Why:** Today `_workout = widget.workout` makes the screen mutate the catalog object directly while editing. A user editing an exercise inside that workout sees the change reflected in any session template that already references the workout — even before Save.

- [ ] **Step 1: Replace the field initializer**

```dart
late Workout _workout =
    widget.workout?.deepCopy(keepId: true) ??
    Workout(
      title: 'title',
      label: 'label',
      exercises: [],
      timeBetweenExercises: 120,
    );
```

- [ ] **Step 2: Manual repro**

1. Run the app.
2. New session → add a workout with at least 1 exercise → save the session.
3. Open the catalog → open that workout → change an exercise's sets → press the back button without saving.
4. Open the saved session — original sets are shown.

- [ ] **Step 3: Run tests** — `flutter test` green.

- [ ] **Step 4: Commit**

```bash
git commit -m "fix(workout-edit): deep-copy widget.workout to prevent leak into catalog"
```

---

### Task 5: `NewSessionScreen` deep-copies its input

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart:50-51`

- [ ] **Step 1: Replace the field initializer**

```dart
late Session _session =
    widget.session?.deepCopy(keepId: true) ??
    Session(title: 'title', label: 'label', workouts: []);
```

- [ ] **Step 2: Manual repro**: open a session → add or remove a workout → press back without saving → re-open and verify unchanged.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(session-edit): deep-copy widget.session to prevent leak into catalog"
```

---

### Task 6: `AddItemScreen` returns deep copies when adding to a session

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/add_item_screen.dart` (the `Navigator.pop(context, selectedPresetItems)` line)

**Why:** Today `AddItemScreen` returns catalog objects by reference. Once added to a session and saved, the session's embedded workout IS the same object as `_userWorkouts[i]`. Subsequent catalog edits silently mutate the session. Returning `deepCopy()` of each selected item makes session-embedded items independent from the start.

- [ ] **Step 1: Map selection through deep-copy**

Find the line that returns selected items. Replace:
```dart
Navigator.pop(context, selectedPresetItems);
```
with:
```dart
final independent = selectedPresetItems
    .map((item) {
      if (item is Workout) return item.deepCopy();
      if (item is Exercise) return item.deepCopy();
      return item; // sessions added at higher levels, not via this screen
    })
    .toList();
Navigator.pop(context, independent);
```

(Confirm via grep that `AddItemScreen` is only used for workouts and exercises within a session/workout edit, never for sessions themselves.)

- [ ] **Step 2: Manual repro**: new session → add a default workout → save → catalog → edit that workout → save → re-open the session → embedded workout reflects ONLY what the user explicitly chose to propagate (governed by the propagation prompt later in this plan), not the silent in-place mutation we have today.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(add-item): return deep copies so embedded items are independent"
```

---

## Phase 2 — Pending-changes tracking on edit screens

### Task 7: `PendingChange` and `PendingChangeBag`

**Files:**
- Create: `lib/models/pending_change.dart`
- Test: `test/models/pending_change_test.dart`

**Why:** Need a uniform way to accumulate "this exercise/workout/session was modified during the edit, but hasn't been committed yet." On Save, the bag is handed to `PresetProvider.commitChanges` which orchestrates writes and propagation.

- [ ] **Step 1: Define types**

```dart
sealed class PendingChange {
  const PendingChange();
}

class WorkoutChanged extends PendingChange {
  const WorkoutChanged(this.workout);
  final Workout workout;
}

class ExerciseChanged extends PendingChange {
  const ExerciseChanged(this.exercise);
  final Exercise exercise;
}

class SessionChanged extends PendingChange {
  const SessionChanged(this.session);
  final Session session;
}

class PendingChangeBag {
  PendingChangeBag();
  final Map<String, ExerciseChanged> exercisesById = {};
  final Map<String, WorkoutChanged> workoutsById = {};
  SessionChanged? session;

  void addExercise(Exercise e) => exercisesById[e.id] = ExerciseChanged(e);
  void addWorkout(Workout w) => workoutsById[w.id] = WorkoutChanged(w);
  void setSession(Session s) => session = SessionChanged(s);

  bool get isEmpty =>
      exercisesById.isEmpty && workoutsById.isEmpty && session == null;
}
```

Same-id replays overwrite (last edit wins per session).

- [ ] **Step 2: Tests** — overwrite-on-replay, isEmpty correctness.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(models): add PendingChange and PendingChangeBag"
```

---

### Task 8: `NewWorkoutScreen` accumulates pending exercise edits

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart`

**Why:** When the user opens an exercise from inside a workout edit, the inner edit screen now returns the modified exercise without writing to the provider. The outer workout screen must remember the modification so Save can flush it.

- [ ] **Step 1: Add a `PendingChangeBag _pending = PendingChangeBag()` field.**

- [ ] **Step 2: When the inner exercise edit returns**, replace the workout's exercise list entry AND add the exercise to `_pending.exercisesById`. Today the code does `_workout.exercises[index] = newExercise`; keep that for in-screen rendering, but ALSO track the change in `_pending`.

- [ ] **Step 3: When `_copyExercise` produces a new copy** (slidable copy), no pending entry — copies are wholly new objects with fresh ids and no consumers to propagate to.

- [ ] **Step 4: When `_deleteExercise`** removes an exercise from the workout, that's a structural change to the workout, not a change to the exercise itself. No pending exercise change. The workout-level change is captured when the outer Save fires.

- [ ] **Step 5: Tests** — pending bag accumulates correctly across multiple inner exercise edits.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(workout-edit): accumulate pending exercise changes locally"
```

---

### Task 9: `NewSessionScreen` accumulates pending workout AND exercise edits

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`

**Why:** A session edit can drill two levels deep (session → workout → exercise). Pending changes from both levels surface on the session's Save.

- [ ] **Step 1: Add a `PendingChangeBag _pending = PendingChangeBag()` field.**

- [ ] **Step 2: When opening a workout edit from the session**, pass `_pending` (or a fresh sub-bag) into the workout edit screen. On return, merge: any `WorkoutChanged` for the returned workout, plus all `ExerciseChanged` accumulated inside.

- [ ] **Step 3: When the user re-orders/copies/deletes workouts** at the session level, capture as a `SessionChanged(_session)` on Save. No per-workout pending entry for those structural moves.

- [ ] **Step 4: Tests** — drilling in/out accumulates exercises across multiple workout edits.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(session-edit): accumulate pending workout & exercise changes locally"
```

---

### Task 10: `NewExerciseScreen` returns without writing when nested

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`

**Why:** When opened nested (from a workout edit), the screen must return the modified exercise as a value and let the parent flush. When opened standalone (from the catalog exercises tab, `persistToProvider: true`), the screen commits via the new `commitChanges` path (Task 18).

- [ ] **Step 1: Distinguish modes** — same as today, on `widget.persistToProvider`. Standalone path: build a single-item bag and commit (deferred to Task 18). Nested path: just `Navigator.pop(context, exercise)` — the parent already deep-copied its own state; mutation is contained.

- [ ] **Step 2: Confirm** that when nested, no `presetProvider.updatePresetExercise` or similar is called. Remove any leftover write paths.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "refactor(exercise-edit): nested mode returns without provider write"
```

---

## Phase 3 — `PresetProvider`: shadow rules, promotion, commit

### Task 11: Shadow rules for the three list getters

**Files:**
- Modify: `lib/providers/preset_provider.dart:39-50`
- Test: `test/providers/preset_provider_promote_default_test.dart` (CREATE)

**Why:** The user list shadows the default list by id. Trash hides items from both lists (Task 30). This getter is the single source of truth for the catalog UI.

- [ ] **Step 1: Tests**

```dart
test('presetWorkouts: user copy with default id shadows the default', () { /* ... */ });
test('presetExercises: same shadow rule', () { /* ... */ });
test('presetSessions: same shadow rule', () { /* ... */ });
```

- [ ] **Step 2: Implement**

```dart
List<Workout> get presetWorkouts {
  final userIds = _userWorkouts.map((w) => w.id).toSet();
  return [
    ..._defaultWorkouts.where((w) => !userIds.contains(w.id)),
    ..._userWorkouts,
  ];
}
```

(Mirror for `presetExercises` and `presetSessions`. Trash filtering added in Task 30.)

- [ ] **Step 3: Run; commit**

```bash
git commit -m "feat(preset): user-list shadows default-list by id"
```

---

### Task 12: `promoteAndUpdate*`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_promote_default_test.dart`

**Why:** Single entry point: insert into user list if not yet there; otherwise update existing.

- [ ] **Step 1: Tests** — promote default → adds to user list, persists; subsequent edit → updates in place; idempotent on retry; defends id-collision invariants.

- [ ] **Step 2: Implement** for workout, exercise, session (mirror pattern):

```dart
Future<void> promoteAndUpdateWorkout(Workout updated) async {
  final i = _userWorkouts.indexWhere((w) => w.id == updated.id);
  if (i == -1) {
    _userWorkouts.add(updated);
  } else {
    _userWorkouts[i] = updated;
  }
  await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
  if (_syncService != null) {
    try { await _syncService!.uploadWorkout(updated); }
    catch (e, st) { Sentry.captureException(e, stackTrace: st); }
  }
  notifyListeners();
}
```

- [ ] **Step 3: Run; commit**

```bash
git commit -m "feat(preset): add promoteAndUpdateWorkout/Exercise/Session"
```

---

### Task 13: `usagesOf*` consolidation

**Files:**
- Modify: `lib/providers/preset_provider.dart` — replace `sessionTemplatesUsingWorkout`, `sessionTemplatesUsingExercise`, `sessionWorkoutPathsUsingExercise` with the names below
- Update: `test/providers/preset_provider_propagate_test.dart`

**Why:** Cleaner naming and a single shape for the propagation prompt's display.

- [ ] **Step 1: Rename**

```dart
List<Session> usagesOfWorkout(String workoutId) { /* same logic as before */ }

/// Each usage of an exercise is described by which session and which workout
/// inside that session contain the matching exercise. (Same exercise can
/// appear in multiple workouts; same workout can appear in multiple sessions.)
List<({Session session, Workout workout})> usagesOfExercise(String exerciseId) { /* same logic */ }
```

(Old names can stay as deprecated aliases for one commit if other code refers to them; remove on the same commit if not.)

- [ ] **Step 2: Update tests; run; commit**

```bash
git commit -m "refactor(preset): rename propagation lookup methods to usagesOf*"
```

---

### Task 14: `commitChanges(PendingChangeBag)`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_commit_changes_test.dart` (CREATE)

**Why:** One entry from edit screens. The provider runs all promotes (exercise → workout → session order), then returns a description of which other consumers are affected, which the edit screen renders as the combined propagation prompt.

- [ ] **Step 1: Define a result struct**

```dart
class CommitResult {
  CommitResult({required this.affectedSessionsByWorkoutId,
                required this.affectedWorkoutsByExerciseId});
  // Workout id → sessions (other than the one being edited, if any) that use it
  final Map<String, List<Session>> affectedSessionsByWorkoutId;
  // Exercise id → workouts (other than the one being edited, if any) that use it
  final Map<String, List<Workout>> affectedWorkoutsByExerciseId;
  bool get hasAny =>
      affectedSessionsByWorkoutId.values.any((l) => l.isNotEmpty) ||
      affectedWorkoutsByExerciseId.values.any((l) => l.isNotEmpty);
}
```

- [ ] **Step 2: Implement**

```dart
Future<CommitResult> commitChanges(PendingChangeBag bag, {String? excludeSessionId, String? excludeWorkoutId}) async {
  // Promote in dependency order: exercises first, workouts next, session last.
  for (final ec in bag.exercisesById.values) {
    await promoteAndUpdateExercise(ec.exercise);
  }
  for (final wc in bag.workoutsById.values) {
    await promoteAndUpdateWorkout(wc.workout);
  }
  if (bag.session != null) {
    await promoteAndUpdateSession(bag.session!.session);
  }

  // Compute affected consumers AFTER promotion (so usagesOf reflects current state).
  final sessionsByWorkout = <String, List<Session>>{};
  final workoutsByExercise = <String, List<Workout>>{};
  for (final wc in bag.workoutsById.values) {
    final sessions = usagesOfWorkout(wc.workout.id)
        .where((s) => s.id != excludeSessionId)
        .toList();
    if (sessions.isNotEmpty) sessionsByWorkout[wc.workout.id] = sessions;
  }
  for (final ec in bag.exercisesById.values) {
    final workouts = usagesOfExercise(ec.exercise.id)
        .map((u) => u.workout)
        .where((w) => w.id != excludeWorkoutId)
        .toSet() // dedupe
        .toList();
    if (workouts.isNotEmpty) workoutsByExercise[ec.exercise.id] = workouts;
  }
  return CommitResult(
    affectedSessionsByWorkoutId: sessionsByWorkout,
    affectedWorkoutsByExerciseId: workoutsByExercise,
  );
}

Future<void> propagateBag(PendingChangeBag bag) async {
  for (final ec in bag.exercisesById.values) {
    await propagateExerciseToSessionTemplates(ec.exercise);
    await propagateExerciseToWorkouts(ec.exercise); // NEW — see Step 3
  }
  for (final wc in bag.workoutsById.values) {
    await propagateWorkoutToSessionTemplates(wc.workout);
  }
  // session changes don't propagate.
}
```

- [ ] **Step 3: Add `propagateExerciseToWorkouts`** — propagates an updated exercise into all `_userWorkouts` (and into trash-restorable user sessions via the existing path) by replacing matching exercises in their `exercises` lists. Use `deepCopy()` per occurrence so each workout owns an independent exercise instance.

- [ ] **Step 4: Tests**
  - Bag with one exercise change inside one workout change: `CommitResult` lists sessions affected by the workout AND workouts affected by the exercise; `excludeWorkoutId` correctly suppresses the parent workout from the exercise's affected list.
  - `propagateBag` runs everything; mutating one propagated copy doesn't bleed into another.

- [ ] **Step 5: Run; commit**

```bash
git commit -m "feat(preset): add commitChanges/propagateBag entry points"
```

---

### Task 15: Combined propagation prompt rendering

**Files:**
- Modify: `lib/presentation/widgets/propagate_changes_dialog.dart`

**Why:** A single dialog must describe potentially several kinds of changes at once. Group by what changed, list each group's consumers.

- [ ] **Step 1: Extend the dialog signature**

```dart
class PropagationSection {
  PropagationSection({required this.itemKind, required this.itemTitle, required this.consumerLabels});
  final String itemKind;       // "workout" | "exercise"
  final String itemTitle;      // the changed item's title
  final List<String> consumerLabels;
}

Future<bool?> showPropagateChangesDialog({
  required BuildContext context,
  required List<PropagationSection> sections,
}) {
  // Title: "Apply changes elsewhere?"
  // Body: for each section, render a heading "<itemTitle> (<itemKind>) is also used in:" then the bulleted list of consumerLabels.
  // Actions: "Keep local" / "Update all".
}
```

- [ ] **Step 2: Update existing single-section callsites** to wrap their data in a one-element `sections` list.

- [ ] **Step 3: Visual sanity check** — open in-app with two sections to confirm layout fits within a typical dialog max-height; wrap content in `SingleChildScrollView` if needed.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(propagate-dialog): render multi-section combined prompt"
```

---

## Phase 4 — Wire edit-screen Saves to the new commit path

### Task 16: `NewWorkoutScreen._save()` (standalone-from-catalog mode)

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart:73-130`

**Why:** Replace the three-branch save with: build a `PendingChangeBag` (the workout itself + accumulated nested exercise changes) and call `commitChanges`. Show the combined prompt.

- [ ] **Step 1: Replace `_save()` body**

```dart
final workout = _buildWorkoutFromForm(); // unchanged
if (widget.persistToProvider) {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  if (_isNew) {
    await pp.addPresetWorkout(workout);
  } else {
    final bag = PendingChangeBag()
      ..addWorkout(workout);
    for (final ec in _pending.exercisesById.values) {
      bag.addExercise(ec.exercise);
    }
    final result = await pp.commitChanges(bag, excludeWorkoutId: workout.id);

    if (result.hasAny && mounted) {
      final sections = <PropagationSection>[
        for (final entry in result.affectedSessionsByWorkoutId.entries)
          PropagationSection(
            itemKind: 'workout',
            itemTitle: workout.title,
            consumerLabels: entry.value.map((s) => s.title).toList(),
          ),
        for (final entry in result.affectedWorkoutsByExerciseId.entries)
          PropagationSection(
            itemKind: 'exercise',
            itemTitle: bag.exercisesById[entry.key]!.exercise.title,
            consumerLabels: entry.value.map((w) => w.title).toList(),
          ),
      ];
      final yes = await showPropagateChangesDialog(context: context, sections: sections);
      if (yes == true) await pp.propagateBag(bag);
    }
  }
}
if (mounted) Navigator.pop(context, workout);
```

(`_isNew` path stays simple. Default-fork branch is gone.)

- [ ] **Step 2: Manual repro of the user's original bug**
  - New session → add a default workout → save the session.
  - Catalog → open that workout → change an exercise's sets → save.
  - Combined prompt fires listing both: "<workout>" used in <session>, AND "<exercise>" used in workouts including the same workout (filtered out via `excludeWorkoutId`).
  - Tap **Update all** → session reflects new sets via the workout-level propagation; other workouts containing that exercise also pick it up.
  - Tap **Keep local** → only the current workout (and its row in the catalog) reflects the change.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(workout-edit): unified save with combined propagation prompt"
```

---

### Task 17: `NewWorkoutScreen` (nested-from-session mode)

**Files:**
- Modify: same file

**Why:** When `persistToProvider: false` (always when entered from a session edit), Save returns the workout AND the pending bag to the parent without committing.

- [ ] **Step 1:** When `widget.persistToProvider == false`, on Save:

```dart
Navigator.pop(context, (workout: workout, pending: _pending));
```

- [ ] **Step 2:** The session screen merges the returned bag into its own `_pending` (Task 9 already wires this).

- [ ] **Step 3:** Cancel discards everything; nothing extra to do — `_pending` lives only in the screen state.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(workout-edit): nested mode returns pending bag without commit"
```

---

### Task 18: `NewExerciseScreen._save()` (standalone)

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart:101-180`

- [ ] **Step 1:** Build a single-item bag, call `commitChanges` with `excludeWorkoutId: null`, render any returned exercise→workouts sections.

- [ ] **Step 2: Manual repro**: edit a default exercise from the catalog exercise tab; on save, prompt names every workout containing that exercise. Tap Update all → workouts pick up the new exercise; tap Keep local → only the catalog exercise changes.

- [ ] **Step 3: Commit**

```bash
git commit -m "fix(exercise-edit): unified save with combined propagation prompt"
```

---

### Task 19: `NewExerciseScreen` (nested)

**Files:**
- Modify: same file

- [ ] **Step 1:** When nested (`persistToProvider: false`), `Navigator.pop(context, exercise)` — no provider write. The parent (workout edit) tracks it via Task 8.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(exercise-edit): nested mode returns without commit"
```

---

### Task 20: `NewSessionScreen._save()`

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart:71-125`

- [ ] **Step 1:** Build the full bag from `_pending` plus the session itself; call `commitChanges` with `excludeSessionId: session.id`. Render combined prompt sections for any workout-level and/or exercise-level consumers outside this session.

```dart
if (_isNew) {
  await pp.addPresetSession(session);
} else {
  final bag = PendingChangeBag()
    ..setSession(session);
  for (final wc in _pending.workoutsById.values) bag.addWorkout(wc.workout);
  for (final ec in _pending.exercisesById.values) bag.addExercise(ec.exercise);
  final result = await pp.commitChanges(bag, excludeSessionId: session.id);
  if (result.hasAny && mounted) {
    /* render combined sections, prompt, propagate on Yes */
  }
}
```

- [ ] **Step 2: Manual repro of the warm-up scenario**
  - Two sessions both contain the same Warm-up workout (same id).
  - Open session A → drill into Warm-up → change pullup reps from 8 to 10 → return → Save session A.
  - Combined prompt fires: "<Warm-up> (workout) is also used in: <Session B>". (Note: pullup-exercise consumers in OTHER workouts are not surfaced — the user changed pullups in the context of Warm-up, not at the catalog exercise level.)
  - Tap **Update all** → Session B's embedded Warm-up shows the new reps.

  Wait — a subtle point: the user *also* edited an exercise. The bag has both an exercise change AND a workout change. The exercise propagation section would suggest pushing pullups into all workouts that contain it, even though the user's intent was scoped to Warm-up. This is the contradiction the user flagged.

  Resolution: when an exercise change is part of a bag that ALSO contains the workout it lives in, suppress the exercise-level propagation section. The exercise change reaches its only consumer (its parent workout) via the workout's propagation, not via a standalone exercise propagation. Implement this filter in `commitChanges`: if an exercise's id appears in a workout in the bag, skip `affectedWorkoutsByExerciseId` for that exercise.

  Update Task 14's implementation accordingly:

  ```dart
  // In commitChanges, before computing workoutsByExercise:
  final exerciseIdsInsideBaggedWorkouts = <String>{
    for (final wc in bag.workoutsById.values)
      for (final e in wc.workout.exercises) e.id,
  };
  for (final ec in bag.exercisesById.values) {
    if (exerciseIdsInsideBaggedWorkouts.contains(ec.exercise.id)) continue;
    /* compute affected workouts as before */
  }
  ```

  Re-test Task 14 with this filter.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(session-edit): unified save with combined propagation prompt"
```

---

### Task 21: End-to-end manual verification

- [ ] **Step 1:** Reproduce the user's exact original bug (workout edit via catalog after creating a session that uses the workout). Combined prompt fires listing the session by name. Yes/No both work.

- [ ] **Step 2:** Reproduce the warm-up/pullup nested scenario. Single combined prompt; exercise-level section suppressed because it's nested inside a bagged workout.

- [ ] **Step 3:** Verify cancellation. Open a session edit, drill in three levels deep, change everything, press the back button at the session level. No provider writes; catalog and other sessions unchanged.

---

## Phase 5 — Strip default-fork machinery

### Task 22: Remove `_isEditingDefault` & friends from edit screens

**Files:**
- Modify: all three edit screens

- [ ] **Step 1: Remove `_isEditingDefault` getters and `allKnown*Titles` branches.** Title validator becomes:

```dart
validator: (v) {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  return FieldValidators.workoutTitle(
    v,
    existingTitles: pp.presetWorkouts.map((w) => w.title).toList(),
    ownTitle: widget.workout?.title,
  );
}
```

- [ ] **Step 2: Remove the copy-on-edit-default branch** in each `_save()` (already absorbed in Tasks 16/18/20).

- [ ] **Step 3: Remove `showDefaultEditTipIfNeeded` calls.**

- [ ] **Step 4: Run; commit**

```bash
git commit -m "refactor(edit-screens): drop default-fork machinery"
```

---

### Task 23: Remove default-fork machinery from `PresetProvider`

**Files:**
- Modify: `lib/providers/preset_provider.dart`

**Symbols to remove:**
- `_keyHiddenDefaultIds`, `_hiddenDefaultIds`, `_loadHiddenDefaultIds`, `_saveHiddenDefaultIds`
- `isDefaultItem`, `isModifiedDefault`, `hideDefaultItem`, `restoreAllDefaults`
- `allKnownExerciseTitles`, `allKnownWorkoutTitles`, `allKnownSessionTitles`
- `userCreatedExerciseCount`, `userCreatedWorkoutCount`, `userCreatedSessionCount`
- `presetDefaultSessions`, `presetUserSessions` (audit; remove if unused)
- The `_hiddenDefaultIds.clear()` line in `reset()`

- [ ] **Step 1: Audit consumers** — `grep -rn "isDefaultItem\|isModifiedDefault\|hideDefaultItem\|restoreAllDefaults\|allKnown.*Titles\|userCreated.*Count" lib/ test/`. Update or remove.

- [ ] **Step 2: Delete the symbols and helpers.**

- [ ] **Step 3: Run** — `flutter analyze` clean; `flutter test` green.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(preset): remove default-fork machinery"
```

---

### Task 24: Delete `default_edit_tip.dart`

**Files:**
- Delete: `lib/utils/default_edit_tip.dart`

- [ ] **Step 1:** `grep -rn showDefaultEditTipIfNeeded lib/ test/` — empty.
- [ ] **Step 2:** Delete file. Leave the orphaned `pref_seen_default_edit_tip` SharedPreferences key.
- [ ] **Step 3: Commit**

```bash
git rm lib/utils/default_edit_tip.dart
git commit -m "refactor: remove default-edit tip dialog"
```

---

### Task 25: Update default-data file comments

**Files:**
- Modify: `lib/data/default_workout_data.dart:11-14`, `lib/data/default_session_data.dart:8-12`

- [ ] **Step 1:** Replace the "_hiddenDefaultIds" rationale with: "IDs are stable keys referenced by trash entries (`trash.json` and Supabase), session templates (via `templateId`), and Supabase row keys. Do not change an existing id once shipped — doing so will orphan trash entries and template references."

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(defaults): update id-stability rationale"
```

---

## Phase 6 — Trash service + cloud sync

### Task 26: `TrashEntry` model + JSON round-trip test

**Files:**
- Create: `lib/models/trash_entry.dart`, `test/models/trash_entry_test.dart`

- [ ] **Step 1: Tests** — round-trips workouts, exercises, sessions; preserves `deletedAt`.

- [ ] **Step 2: Implement**

```dart
enum TrashKind { session, workout, exercise }

class TrashEntry {
  TrashEntry._({required this.kind, required this.payload, required this.deletedAt});
  factory TrashEntry.session({required Session session, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.session, payload: session, deletedAt: deletedAt);
  factory TrashEntry.workout({required Workout workout, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.workout, payload: workout, deletedAt: deletedAt);
  factory TrashEntry.exercise({required Exercise exercise, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.exercise, payload: exercise, deletedAt: deletedAt);

  final TrashKind kind;
  final Object payload;
  final DateTime deletedAt;

  String get id => switch (kind) {
        TrashKind.session => (payload as Session).id,
        TrashKind.workout => (payload as Workout).id,
        TrashKind.exercise => (payload as Exercise).id,
      };
  String get title => switch (kind) {
        TrashKind.session => (payload as Session).title,
        TrashKind.workout => (payload as Workout).title,
        TrashKind.exercise => (payload as Exercise).title,
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'deletedAt': deletedAt.toIso8601String(),
        'payload': switch (kind) {
          TrashKind.session => (payload as Session).toJson(),
          TrashKind.workout => (payload as Workout).toJson(),
          TrashKind.exercise => (payload as Exercise).toJson(),
        },
      };
  factory TrashEntry.fromJson(Map<String, dynamic> json) {
    final kind = TrashKind.values.byName(json['kind'] as String);
    final deletedAt = DateTime.parse(json['deletedAt'] as String);
    final p = json['payload'] as Map<String, dynamic>;
    return switch (kind) {
      TrashKind.session => TrashEntry.session(session: Session.fromJson(p), deletedAt: deletedAt),
      TrashKind.workout => TrashEntry.workout(workout: Workout.fromJson(p), deletedAt: deletedAt),
      TrashKind.exercise => TrashEntry.exercise(exercise: Exercise.fromJson(p), deletedAt: deletedAt),
    };
  }
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(models): add TrashEntry"
```

---

### Task 27: `TrashService` (read/write/purge)

**Files:**
- Create: `lib/services/trash_service.dart`, `test/services/trash_service_test.dart`

- [ ] **Step 1: Tests** (use `_FakePathProvider` pattern from `sync_queue_service_test.dart`)
  - `add` then `readAll` round-trips.
  - `purgeOlderThan(Duration(days: 90), now: ...)` removes entries with `deletedAt < cutoff`.
  - `restore(id)` removes the entry and returns it.
  - Empty file → `readAll` returns `[]`.

- [ ] **Step 2: Implement**

```dart
class TrashService {
  Future<List<TrashEntry>> readAll();
  Future<void> add(TrashEntry entry);
  Future<TrashEntry?> restore(String id);
  Future<int> purgeOlderThan(Duration ttl, {DateTime? now});
  // Internally writes to '<docs>/trash.json'.
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(trash): add TrashService with 90-day purge"
```

---

### Task 28: Cloud sync for trash

**Files:**
- Modify: `lib/services/supabase_sync_service.dart`, `lib/services/sync_queue_service.dart`
- Tests: extend the existing service tests

**Why:** Trash state must be visible across devices. Without this, deleting an item on phone A leaves it visible on phone B; a subsequent edit on B silently un-shadows the trashed-state on next sync.

- [ ] **Step 1: Supabase schema** (note for the human implementer to apply migrations):

```sql
create table public.trash_entries (
  id text not null,
  user_id uuid not null,
  kind text not null check (kind in ('session','workout','exercise')),
  payload jsonb not null,
  deleted_at timestamptz not null,
  primary key (id, user_id)
);
alter table public.trash_entries enable row level security;
create policy "users see own trash" on public.trash_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: `SupabaseSyncService` additions**

```dart
Future<void> uploadTrashEntry(TrashEntry entry, {bool isRetry = false});
Future<void> deleteTrashEntry(String id, {bool isRetry = false});
Future<List<TrashEntry>> fetchUserTrashEntries();
```

Mirror the existing pattern (`uploadWorkout`, etc.). Enqueue to `SyncQueueService` on failure.

- [ ] **Step 3: `SyncQueueService` additions**

Add operation types `'uploadTrashEntry'` and `'deleteTrashEntry'`. Update the dispatcher.

- [ ] **Step 4: Tests** — round-trip via cloud (mock); pending op survives offline; idempotent retry.

- [ ] **Step 5: Conflict resolution** — when phone A trashes an item that phone B is concurrently editing, the last write wins by Supabase timestamp. Document in the file: edit-after-trash on the loser device shows up in the cloud as a `_userWorkouts` upload that conflicts with the trash entry. The provider's load order resolves it: **trash wins over user list when both contain the same id**, so the trashed state takes precedence on next sync.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(trash): cloud sync via Supabase"
```

---

### Task 29: Provider wires `TrashService`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_trash_test.dart` (CREATE)

- [ ] **Step 1: Tests**
  - `init` purges expired and loads trash from local + cloud.
  - `deleteToTrash(id, kind)` removes from `_userX` if present, adds to trash, persists local + cloud.
  - `restoreFromTrash(id)` removes from trash, adds to `_userX`, persists; if title collides, surfaces a precondition that the caller must rename first (the call accepts an `overrideTitle` parameter, used after the rename dialog).
  - `liftToCatalog(item, kind)` adds to `_userX` (with id collision → fresh id), persists; `overrideTitle` parameter for title collisions.
  - Id collision invariants: an id never appears twice across `_userX` and trash.

- [ ] **Step 2: Implement**

```dart
final TrashService _trashService = TrashService();
List<TrashEntry> _trashedItems = [];
List<TrashEntry> get trashedItems => List.unmodifiable(_trashedItems);

Future<void> _loadAndPurgeTrash() async {
  await _trashService.purgeOlderThan(const Duration(days: 90));
  _trashedItems = await _trashService.readAll();
  // Cloud merge: union with any cloud entries; conflicts resolved by latest deletedAt.
  if (_syncService != null) {
    try {
      final cloud = await _syncService!.fetchUserTrashEntries();
      _trashedItems = _mergeTrashCloudAndLocal(_trashedItems, cloud);
    } catch (e, st) { Sentry.captureException(e, stackTrace: st); }
  }
}

Future<void> deleteToTrash({required String id, required TrashKind kind}) async {
  final now = DateTime.now();
  TrashEntry entry;
  switch (kind) {
    case TrashKind.workout:
      final src = presetWorkouts.firstWhere((w) => w.id == id);
      _userWorkouts.removeWhere((w) => w.id == id);
      entry = TrashEntry.workout(workout: src, deletedAt: now);
      await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
    case TrashKind.exercise: /* mirror */
    case TrashKind.session:  /* mirror */
  }
  _trashedItems.add(entry);
  await _trashService.add(entry);
  if (_syncService != null) { try { await _syncService!.uploadTrashEntry(entry); } catch (_) {} }
  notifyListeners();
}

Future<void> restoreFromTrash(String id, {String? overrideTitle}) async {
  final entry = await _trashService.restore(id);
  if (entry == null) return;
  // Caller is responsible for rename dialog if title collides.
  switch (entry.kind) {
    case TrashKind.workout:
      var w = entry.payload as Workout;
      if (overrideTitle != null) w = w.copyWith(title: overrideTitle);
      _userWorkouts.add(w);
      await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
    case /* ... */:
  }
  _trashedItems.removeWhere((e) => e.id == id);
  if (_syncService != null) { try { await _syncService!.deleteTrashEntry(id); } catch (_) {} }
  notifyListeners();
}

Future<void> liftToCatalog({required Object item, required TrashKind kind, String? overrideTitle, String? overrideId}) async {
  // Add to _userX; if id collides, caller passes overrideId. If title collides, caller passes overrideTitle.
  // No propagation; this is purely additive.
}
```

- [ ] **Step 3: Run; commit**

```bash
git commit -m "feat(preset): wire TrashService + restoreFromTrash + liftToCatalog"
```

---

### Task 30: Trash filtering in shadow rules

**Files:**
- Modify: `lib/providers/preset_provider.dart`

- [ ] **Step 1:** Update shadow rules:

```dart
List<Workout> get presetWorkouts {
  final userIds = _userWorkouts.map((w) => w.id).toSet();
  final trashedIds = _trashedItems
      .where((e) => e.kind == TrashKind.workout)
      .map((e) => e.id)
      .toSet();
  return [
    ..._defaultWorkouts.where((w) => !userIds.contains(w.id) && !trashedIds.contains(w.id)),
    ..._userWorkouts.where((w) => !trashedIds.contains(w.id)),
  ];
}
```

- [ ] **Step 2: Tests** — trashed default disappears; trashed user item disappears; restoring brings it back to its proper list.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(preset): trash filters shadow rules for all kinds"
```

---

## Phase 7 — Catalog & settings UI

### Task 31: Catalog Delete + reference enumeration + Undo SnackBar

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/catalog_screen.dart:87-155`

- [ ] **Step 1: Helpers in `PresetProvider`** (if not already present)

```dart
List<Session> sessionsContainingWorkout(String id) => /* ... */;
List<Workout> workoutsContainingExercise(String id) => /* ... */;
```

- [ ] **Step 2: Replace `_hideOrDeleteItem` with `_moveToTrash`**

```dart
Future<void> _moveToTrash(dynamic item) async {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  final kind = switch (widget.itemType) {
    ItemType.sessions => TrashKind.session,
    ItemType.workouts => TrashKind.workout,
    ItemType.exercises => TrashKind.exercise,
  };
  // Enumerate references.
  final references = switch (kind) {
    TrashKind.workout => pp.sessionsContainingWorkout(item.id).map((s) => s.title).toList(),
    TrashKind.exercise => pp.workoutsContainingExercise(item.id).map((w) => w.title).toList(),
    TrashKind.session => const <String>[],
  };
  final confirm = await _showTrashConfirmationDialog(item.title, references);
  if (confirm != true) return;
  await pp.deleteToTrash(id: item.id, kind: kind);
  // Undo SnackBar
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 5),
    content: Text('Moved "${item.title}" to trash'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () async {
        await pp.restoreFromTrash(item.id);
      },
    ),
  ));
}
```

- [ ] **Step 3: Single confirmation dialog**

```
Title: "Move to trash?"
Body (no references): '"<title>" will be moved to the trash. You can restore it within 90 days from Settings.'
Body (with references): '"<title>" is currently used in: <bulleted list>. Moving it to the trash won\'t affect those — they keep their own copy. Move to trash?'
Actions: Cancel | Move to trash
```

- [ ] **Step 4: Manual repro**
  - Slidable Delete on a default exercise → reference list shows workouts; confirm; SnackBar with Undo; tap Undo within 5s — exercise reappears.
  - Repeat for a workout used in 2 sessions.
  - Repeat for a session — no references listed.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(catalog): trash routing with reference enumeration + Undo SnackBar"
```

---

### Task 32: `RestoreItemsScreen`

**Files:**
- Create: `lib/presentation/screens/settings/restore_items_screen.dart`
- Modify: `lib/presentation/screens/root_screen.dart` (replace tile)

- [ ] **Step 1: Build the UI** — `Scaffold` + `Consumer<PresetProvider>`:
  - Three sections (Sessions / Workouts / Exercises). Hide empty sections.
  - Each row: `CheckboxListTile`, title = item title, subtitle = "Expires in N days" (calculated from `deletedAt + 90 days - now()`); when N ≤ 7, subtitle styled in error color.
  - Bottom: `FilledButton('Restore selected')` enabled when `_selected.isNotEmpty`.
  - Empty state: centered "Trash is empty".

- [ ] **Step 2: Action wiring**

```dart
Future<void> _restoreSelected() async {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  for (final id in _selected) {
    final entry = pp.trashedItems.firstWhere((e) => e.id == id);
    final clashes = _titleClashes(pp, entry);
    String? overrideTitle;
    if (clashes) {
      overrideTitle = await showRenameOnCollisionDialog(
        context: context,
        currentTitle: entry.title,
        existingTitles: _existingTitlesForKind(pp, entry.kind),
      );
      if (overrideTitle == null) continue; // user cancelled this one; skip
    }
    await pp.restoreFromTrash(id, overrideTitle: overrideTitle);
  }
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Restored ${_selected.length} item(s)')),
  );
  setState(() => _selected.clear());
}
```

- [ ] **Step 3: Replace settings tile** in `root_screen.dart`. Delete `_showRestoreDefaultsDialog`.

```dart
ListTile(
  leading: const Icon(Icons.restore_rounded),
  title: Text('Restore items', style: context.bodyLarge),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const RestoreItemsScreen()),
  ),
),
```

- [ ] **Step 4: Manual repro**
  - Trash a default and a user item; visit Restore items; check both; verify "Expires in N days" labels; tap Restore selected; both reappear.
  - Force a title collision (rename a user workout to match a trashed default's title; trash the default; restore from trash) → rename dialog fires; user picks a new title; restore succeeds.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(settings): RestoreItemsScreen with expiration & rename-on-collision"
```

---

### Task 33: Slidable "Save to catalog" action

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart` (workout cards)
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart` (exercise cards)
- Create: `lib/presentation/widgets/rename_on_collision_dialog.dart`

**Why:** Lets users lift session-embedded items into the catalog. Visible whenever the item's id isn't currently in the catalog. On tap, if the title collides, a rename dialog fires.

- [ ] **Step 1: Implement `rename_on_collision_dialog.dart`**

```dart
Future<String?> showRenameOnCollisionDialog({
  required BuildContext context,
  required String currentTitle,
  required List<String> existingTitles,
}) {
  // TextFormField pre-filled with currentTitle. Validator: must differ from existingTitles.
  // Buttons: Cancel (returns null) / Save (returns the new title).
}
```

- [ ] **Step 2: Add the slidable action on workout cards in `NewSessionScreen`**

Inside the existing `Slidable` for each workout card, add an action:

```dart
SlidableAction(
  onPressed: (_) => _saveWorkoutToCatalog(workout),
  icon: Icons.save_alt_rounded,
  label: 'Save to catalog',
  // visible only when:
  //   pp.presetWorkouts.every((w) => w.id != workout.id) &&
  //   pp.trashedItems.every((e) => e.id != workout.id)
),
```

(Use the slidable's `extentRatio`/conditional rendering pattern already in use; if conditional `SlidableAction` isn't supported directly, wrap the action in a function that no-ops + shows a SnackBar when conditions don't hold — but prefer to omit the action visually when ineligible.)

- [ ] **Step 3: Implement `_saveWorkoutToCatalog`**

```dart
Future<void> _saveWorkoutToCatalog(Workout workout) async {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  final titles = pp.presetWorkouts.map((w) => w.title).toList();
  String? finalTitle = workout.title;
  if (titles.contains(workout.title)) {
    finalTitle = await showRenameOnCollisionDialog(
      context: context,
      currentTitle: workout.title,
      existingTitles: titles,
    );
    if (finalTitle == null) return;
  }
  await pp.liftToCatalog(
    item: finalTitle == workout.title ? workout : workout.copyWith(title: finalTitle),
    kind: TrashKind.workout,
  );
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Saved to catalog')),
  );
}
```

- [ ] **Step 4: Same for exercise cards in `NewWorkoutScreen`** — slidable action visible iff exercise id not in `presetExercises` and not in trash.

- [ ] **Step 5: Tests** (`test/providers/preset_provider_save_to_catalog_test.dart`)
  - `liftToCatalog` adds to user list; persists; sync.
  - Title collision in caller → rename dialog supplies override; lift succeeds with new title.
  - Id collision → caller supplies fresh `overrideId`; lift succeeds with new id.

- [ ] **Step 6: Manual repro**
  - In a session edit, copy a workout via the existing copy slidable (id is fresh, not in catalog) → "Save to catalog" appears → tap → if title clashes, rename dialog → catalog gains the new workout.
  - Copy an exercise inside a workout edit → same flow.
  - On a session-embedded workout whose id is already in the catalog → "Save to catalog" not visible.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(edit-screens): Save to catalog slidable action with rename-on-collision"
```

---

## Phase 8 — Cleanup

### Task 34: `flutter analyze` clean

- [ ] Run `flutter analyze`. The pre-existing 6 info-level findings are acceptable; no new warnings introduced.

### Task 35: `flutter test` green

- [ ] Run `flutter test`. All new + existing tests pass.

### Task 36: End-to-end smoke verification

- [ ] **Mutability:** edit an exercise inside a workout → back without saving → catalog and any sessions referencing the workout still show the original.

- [ ] **Promotion:** edit a default workout for the first time → no banner, no tip dialog; catalog shows the edit; the same id; no second copy.

- [ ] **Combined propagation prompt (warm-up scenario):**
  - Two sessions both contain Warm-up (same id).
  - Edit Warm-up via session A's drilldown, change pullup reps inside it, save the session.
  - Single dialog: "Warm-up (workout) is also used in: <Session B>". Pullup-as-an-exercise propagation NOT shown (suppressed because nested inside the bagged workout).
  - Yes → session B shows new reps. No → only session A.

- [ ] **Standalone exercise edit:** edit pullup from the exercise tab → prompt lists every workout containing pullup. Yes → all those workouts pick up the new exercise. No → only the catalog row changes.

- [ ] **Cancel discards:** drill three levels deep into a session, change everything, press back at the session level → no provider writes.

- [ ] **Trash + restore + undo:**
  - Slidable Delete a default exercise → reference list shows workouts → confirm → Undo SnackBar — tap Undo within 5s → exercise reappears.
  - Re-trash → wait → Settings → Restore items → "Expires in 90 days" subtitle → check → Restore selected → exercise back.
  - Force a title collision on restore → rename dialog → restore succeeds.

- [ ] **Save to catalog:**
  - Copy a workout in a session → Save to catalog (rename if needed) → catalog has the new workout.
  - The same workout has the action hidden if it was added from the catalog (id matches).

- [ ] **Multi-device:** trash on phone A → log in on phone B → item is hidden in catalog and appears in Restore items.

- [ ] **No regressions:** start a session, run it, complete it. Logged sessions unaffected. `flutter test` green; `flutter analyze` clean.

---

## Out of scope (call out for future plans)

- **Sync from catalog**: a per-template "pull latest from catalog" action that re-applies the current catalog version of an embedded workout/exercise. The `templateId` field is the breadcrumb that enables this. Not built in this plan.
- **Progress tracking via templateId**: aggregating across logged sessions by exercise `templateId` (e.g. "max grade climbed for pull-ups over time"). Not built in this plan.
- **Bulk delete from catalog**: trashing multiple items in one gesture. Not requested for v1.
- **Search in trash**: filtering the Restore items list. Not requested for v1.
- **Trash payload schema versioning**: rely on graceful `fromJson` defaults; if a future model change is breaking, write a migration at that point.
- **Migration of legacy `_hiddenDefaultIds`**: develop branch only — no live users with that state.
- **Migration of legacy templateId-forked user copies**: same — develop branch only.
