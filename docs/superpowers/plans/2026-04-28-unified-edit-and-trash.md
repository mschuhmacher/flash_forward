# Unified edit model & 30-day trash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the "default vs user item" distinction into a single edit model where every catalog item edits in place, replace the silent hide-and-fork mechanism with a transparent 30-day trash, fix the underlying mutability bug that causes catalog edits to leak into session templates before Save, and make the existing propagation prompt fire reliably for every relevant edit.

**Architecture:**
- Catalog items (sessions, workouts, exercises) are no longer split between immutable `_default*` and mutable `_user*` lists at the consumption layer. The first time a default is edited, it is "promoted" into the user collection at the same id; defaults are still seeded from `kDefault*` constants but treated as initial content, not as a separate read-only tier.
- All deletions (defaults and user items alike) move the item into a single trash store (`trash.json` + Supabase `trash` if synced) with a `deletedAt` timestamp. Items older than 30 days are purged on app start. Settings exposes a "Restore items" picker grouped by Workouts / Exercises / Sessions.
- Edit screens deep-copy their input on open so mid-edit mutations don't escape into the catalog or any session that already references the item by reference.
- The existing propagation prompt (`showPropagateChangesDialog`) fires after every catalog save that mutated an item already used by ≥1 session template, regardless of whether the item was originally a default.

**Tech Stack:** Flutter (Dart), Provider, Supabase (cloud sync), shared_preferences (local prefs), local JSON files via `PresetLogger`.

---

## File Structure

### New files
- `lib/services/trash_service.dart` — local read/write of `trash.json` plus 30-day purge logic.
- `lib/models/trash_entry.dart` — discriminated union of (Session | Workout | Exercise) + `deletedAt` + `kind`.
- `lib/presentation/screens/settings/restore_items_screen.dart` — picker UI for restoring trashed items.
- `lib/presentation/widgets/default_edit_banner.dart` — REMOVED-from-plan; the new model has no special "editing a default" state. (kept here as a reminder that the previous plan had this; do NOT add it.)

### Modified files
- `lib/providers/preset_provider.dart` — remove default-fork machinery (`isDefaultItem`, `isModifiedDefault`, `_hiddenDefaultIds`, `hideDefaultItem`, `restoreAllDefaults`, `allKnown*Titles`, `userCreated*Count`); add promote-default-on-edit + trash routing; keep / extend propagation methods.
- `lib/models/session.dart`, `lib/models/workout.dart`, `lib/models/exercise.dart` — `templateId` field stays as a copy-breadcrumb (no functional change). Add a `keepId` flag to `deepCopy()` for the mutability fix.
- `lib/presentation/screens/training_program_flow/new_workout_screen.dart` — deep-copy `_workout` from `widget.workout`. Strip `_isEditingDefault`, the `allKnownWorkoutTitles` branch, the copy-on-edit-default save path, and the post-save tip dialog. Keep propagation prompt; it now fires on every in-place save that affects ≥1 template.
- `lib/presentation/screens/training_program_flow/new_session_screen.dart` — deep-copy `_session`. Strip default-fork machinery. (No propagation prompt: editing a session edits itself; no parent to propagate to.)
- `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` — strip default-fork machinery; keep propagation prompt.
- `lib/presentation/screens/training_program_flow/catalog_screen.dart` — slidable Delete now sends the item to the trash for both defaults and user items (single confirmation dialog with unified copy).
- `lib/presentation/screens/root_screen.dart` — replace "Restore defaults" tile and `_showRestoreDefaultsDialog` with a tile that opens `RestoreItemsScreen`.
- `lib/utils/default_edit_tip.dart` — DELETE; no longer needed.
- `lib/data/default_workout_data.dart`, `lib/data/default_session_data.dart` — comments referencing `_hiddenDefaultIds` need updating (the id stability rationale shifts to "trash entries reference items by id").
- `test/providers/preset_provider_propagate_test.dart` — keep existing tests; add coverage for the promote-on-edit and trash flows where they affect propagation.

### New tests
- `test/services/trash_service_test.dart` — round-trip, 30-day purge boundary, restore.
- `test/providers/preset_provider_promote_default_test.dart` — first edit of a default item promotes it into `_userWorkouts` (and persists), preserves id, and removes the in-memory default shadow.
- `test/providers/preset_provider_trash_test.dart` — delete routes to trash; restore brings item back; default-id collision after restore is handled.

---

## Data-model invariants (read carefully)

These shape every task below.

1. **Single source of truth at consumption.** `presetWorkouts` (and friends) returns one row per id. If an id exists in both `_defaultWorkouts` and `_userWorkouts`, the user copy wins; the default shadow is hidden. (This replaces `_hiddenDefaultIds`.)
2. **Promotion on first edit.** When the user saves an edit to an item whose id is currently only in `_default*`, the new content is added to `_user*` (with the same id, `userId` populated) and persisted via `PresetLogger`. The default constant is untouched in memory; the user-list copy shadows it on read.
3. **Trash uses `deletedAt`.** Trash entries store the full item JSON plus `deletedAt`. Restoring re-routes the item back into `_user*` (because once deleted, the item is no longer "default-shaped"; it's user-owned content). Purge runs on init when `deletedAt` is older than 30 days.
4. **Trash is the only post-delete state.** No more `_hiddenDefaultIds`. Slidable delete on a default does the same thing as slidable delete on a user item: trash entry, restorable for 30 days, then purged.
5. **`templateId` is informational only.** It points to the source of a copy. The propagation lookup matches on `id` OR `templateId` because that's still the chain we care about.
6. **Edit screens own a deep copy.** `_workout` / `_session` are independent from `widget.workout` / `widget.session`. Mutations in the screen never escape until Save commits via the provider.

---

## Task List Overview

### Phase 1 — Foundations: deep-copy on edit & `keepId`
- [ ] Task 1: `Workout.deepCopy({keepId})` + tests
- [ ] Task 2: `Session.deepCopy({keepId})` + tests
- [ ] Task 3: `NewWorkoutScreen` initializes `_workout` from a `keepId: true` deep copy + manual repro
- [ ] Task 4: `NewSessionScreen` initializes `_session` from a `keepId: true` deep copy + manual repro

### Phase 2 — Trash service
- [ ] Task 5: `TrashEntry` model + JSON round-trip test
- [ ] Task 6: `TrashService` (read/write/purge) + tests
- [ ] Task 7: `PresetProvider` wires `TrashService`: `init()` purges expired, `trashedItems` getter, `restoreFromTrash(id)` + tests

### Phase 3 — Promote-default-on-edit
- [ ] Task 8: `PresetProvider.presetWorkouts` shadow rule + test
- [ ] Task 9: Same for `presetExercises` and `presetSessions` + tests
- [ ] Task 10: `PresetProvider.promoteAndUpdateWorkout/Exercise/Session` + tests
- [ ] Task 11: Wire `NewWorkoutScreen._save()` to use `promoteAndUpdate*` for the in-place edit path + manual repro
- [ ] Task 12: Same for `NewExerciseScreen._save()` + manual repro
- [ ] Task 13: Same for `NewSessionScreen._save()` + manual repro

### Phase 4 — Strip default-fork machinery
- [ ] Task 14: Remove `_isEditingDefault`, `_isDefault` checks, `allKnown*Titles`, and the copy-on-edit-default branch from all three edit screens
- [ ] Task 15: Remove `isDefaultItem`, `isModifiedDefault`, `_hiddenDefaultIds`, `hideDefaultItem`, `restoreAllDefaults`, `_loadHiddenDefaultIds`, `_saveHiddenDefaultIds`, `userCreated*Count`, `allKnown*Titles` from `PresetProvider`
- [ ] Task 16: Delete `lib/utils/default_edit_tip.dart` and its callsites
- [ ] Task 17: Update default-data file comments (`default_workout_data.dart`, `default_session_data.dart`) to match the new id-stability rationale (trash references by id)

### Phase 5 — Trash-routed deletion in catalog
- [ ] Task 18: `PresetProvider.deleteToTrash(id, kind)` + tests
- [ ] Task 19: `catalog_screen._hideOrDeleteItem` routes through `deleteToTrash` for ALL items (default or user) + manual repro
- [ ] Task 20: Single delete-confirmation dialog with unified copy ("Move to trash? Restore within 30 days from Settings.")

### Phase 6 — Restore Items screen
- [ ] Task 21: `RestoreItemsScreen` UI scaffolding (sectioned: Sessions / Workouts / Exercises) + checkbox state
- [ ] Task 22: Wire bulk restore action; navigate from settings drawer; remove old "Restore defaults" tile

### Phase 7 — Propagation prompt fires for every relevant edit
- [ ] Task 23: Verify the propagation prompt fires on every `promoteAndUpdate*` path that has affected templates (manual repro of the user's exact bug report)
- [ ] Task 24: Update `propagateExerciseToSessionTemplates` and `propagateWorkoutToSessionTemplates` callsites: ensure they run AFTER the promote-and-update completes so lookups see the new content

### Phase 8 — Cleanup
- [ ] Task 25: Run `flutter analyze`; ensure 0 new warnings
- [ ] Task 26: Run full `flutter test`; all green

---

## Phase 1 — Foundations

### Task 1: `Workout.deepCopy({keepId})` + tests

**Files:**
- Modify: `lib/models/workout.dart:95-106`
- Test: `test/models/workout_deep_copy_test.dart` (CREATE)

**Why:** Edit screens need a deep copy that preserves the id (so save targets the right row) but owns its own `exercises` list. The existing `deepCopy()` is used by the "start a session" flow which needs a fresh id. One method, two modes via a flag.

- [ ] **Step 1: Write failing test** (`test/models/workout_deep_copy_test.dart`)

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

  test('deepCopy() default: new id, fresh exercises', () {
    final src = sample();
    final dst = src.deepCopy();
    expect(dst.id, isNot('w-1'));
    expect(dst.templateId, 'w-1');
    expect(identical(dst.exercises, src.exercises), isFalse);
    expect(identical(dst.exercises.single, src.exercises.single), isFalse);
  });

  test('deepCopy(keepId: true): same id, fresh exercises, templateId untouched',
      () {
    final src = sample();
    final dst = src.deepCopy(keepId: true);
    expect(dst.id, 'w-1');
    expect(dst.templateId, isNull);
    expect(identical(dst.exercises, src.exercises), isFalse);
    expect(identical(dst.exercises.single, src.exercises.single), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/workout_deep_copy_test.dart`
Expected: FAIL — `keepId` not a parameter.

- [ ] **Step 3: Modify `Workout.deepCopy`**

Change [lib/models/workout.dart:95-106](lib/models/workout.dart#L95-L106) to:

```dart
/// Independent copy with deep-copied exercises.
///
/// - Default (`keepId: false`): assigns a fresh id and sets `templateId`
///   to the source's id (or its existing templateId). Use when adding to a
///   session, copying within a session, or starting a session.
/// - `keepId: true`: preserves the source's id AND its templateId. Use in
///   edit screens so the working copy can be saved back into the catalog
///   under the same id without breaking the templateId chain.
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
```

Then add the `keepId` flag to `Exercise.deepCopy()` symmetrically (signature change only; behavior identical when `keepId: false`):

```dart
Exercise deepCopy({bool keepId = false}) => Exercise(
      id: keepId ? id : null,
      templateId: keepId ? templateId : (templateId ?? id),
      // ... all other fields unchanged
    );
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/models/workout_deep_copy_test.dart test/providers/preset_provider_propagate_test.dart`
Expected: PASS (existing propagation tests should still pass since they call `deepCopy()` with no args).

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

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

void main() {
  Session sample() => Session(
        id: 's-1',
        title: 't',
        label: 'l',
        workouts: [
          Workout(
              id: 'w-1',
              title: 'wt',
              label: 'wl',
              exercises: [],
              timeBetweenExercises: 60),
        ],
      );

  test('deepCopy(keepId: true): same id and workouts deep-copied with keepId',
      () {
    final dst = sample().deepCopy(keepId: true);
    expect(dst.id, 's-1');
    expect(dst.workouts.single.id, 'w-1');
    expect(identical(dst.workouts, sample().workouts), isFalse);
  });

  test('deepCopy(): new id, workouts deep-copied with new ids', () {
    final dst = sample().deepCopy();
    expect(dst.id, isNot('s-1'));
    expect(dst.workouts.single.id, isNot('w-1'));
    expect(dst.workouts.single.templateId, 'w-1');
  });
}
```

- [ ] **Step 2: Run** — expect FAIL (keepId not a parameter).

- [ ] **Step 3: Modify `Session.deepCopy`** at [lib/models/session.dart:152-162](lib/models/session.dart#L152-L162):

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

- [ ] **Step 4: Run tests** — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/session.dart test/models/session_deep_copy_test.dart
git commit -m "feat(models): add keepId flag to Session.deepCopy"
```

---

### Task 3: `NewWorkoutScreen` deep-copies its input

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart:46-53`

**Why:** Today `_workout = widget.workout` makes the screen mutate the catalog object directly while editing. A user editing an exercise inside that workout sees the change reflected in any session template that already references the workout — even before Save. The user's bug report ("the session showed the updated sets" without a propagation prompt) is exactly this leak.

- [ ] **Step 1: Replace the field initializer**

Before:
```dart
late Workout _workout =
    widget.workout ??
    Workout(
      title: 'title',
      label: 'label',
      exercises: [],
      timeBetweenExercises: 120,
    );
```

After:
```dart
// Deep-copy the input so mid-edit mutations (insert/remove/replace exercises)
// stay local to this screen until _save() commits via the provider.
late Workout _workout =
    widget.workout?.deepCopy(keepId: true) ??
    Workout(
      title: 'title',
      label: 'label',
      exercises: [],
      timeBetweenExercises: 120,
    );
```

- [ ] **Step 2: Manual repro of the leak (negative — should fail today, pass after)**

1. Run the app.
2. New session → add a workout with at least 1 exercise → save the session.
3. Open the catalog → open that workout → in-screen, change an exercise's sets, then **press the back button (do not save)**.
4. Open the saved session.
5. **Before this task:** the session shows the changed sets (bug).
6. **After this task:** the session shows the original sets.

- [ ] **Step 3: Run existing tests**

Run: `flutter test`
Expected: PASS (no test depends on the in-place mutation behavior).

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_workout_screen.dart
git commit -m "fix(workout-edit): deep-copy widget.workout to prevent leak into catalog"
```

---

### Task 4: `NewSessionScreen` deep-copies its input

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart:50-51`

- [ ] **Step 1: Replace the field initializer**

Before:
```dart
late Session _session =
    widget.session ?? Session(title: 'title', label: 'label', workouts: []);
```

After:
```dart
late Session _session =
    widget.session?.deepCopy(keepId: true) ??
    Session(title: 'title', label: 'label', workouts: []);
```

- [ ] **Step 2: Manual repro**

1. Open the catalog → open a session → add or remove a workout → press back without saving.
2. Re-open the session — workouts list is unchanged.

- [ ] **Step 3: Run tests** — `flutter test` should be green.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_session_screen.dart
git commit -m "fix(session-edit): deep-copy widget.session to prevent leak into catalog"
```

---

## Phase 2 — Trash service

### Task 5: `TrashEntry` model + JSON round-trip test

**Files:**
- Create: `lib/models/trash_entry.dart`
- Test: `test/models/trash_entry_test.dart`

**Why:** Single home for trashed items regardless of kind. Storing the full payload (not just an id) means restore works even if the source list has drifted.

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';

void main() {
  test('TrashEntry round-trips a Workout payload', () {
    final w = Workout(
        id: 'w-1', title: 't', label: 'l', exercises: [], timeBetweenExercises: 60);
    final entry = TrashEntry.workout(
        workout: w, deletedAt: DateTime.utc(2026, 4, 28, 12));
    final json = entry.toJson();
    final restored = TrashEntry.fromJson(json);
    expect(restored.kind, TrashKind.workout);
    expect(restored.deletedAt, DateTime.utc(2026, 4, 28, 12));
    expect((restored.payload as Workout).id, 'w-1');
  });

  test('TrashEntry round-trips an Exercise payload', () {
    final e = Exercise(id: 'e-1', title: 't', description: 'd', label: 'l');
    final entry = TrashEntry.exercise(
        exercise: e, deletedAt: DateTime.utc(2026, 4, 28, 12));
    final restored = TrashEntry.fromJson(entry.toJson());
    expect(restored.kind, TrashKind.exercise);
    expect((restored.payload as Exercise).id, 'e-1');
  });
}
```

- [ ] **Step 2: Run** — FAIL (model not defined).

- [ ] **Step 3: Implement `lib/models/trash_entry.dart`**

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

enum TrashKind { session, workout, exercise }

class TrashEntry {
  TrashEntry._({
    required this.kind,
    required this.payload,
    required this.deletedAt,
  });

  factory TrashEntry.session({required Session session, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.session, payload: session, deletedAt: deletedAt);
  factory TrashEntry.workout({required Workout workout, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.workout, payload: workout, deletedAt: deletedAt);
  factory TrashEntry.exercise({required Exercise exercise, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.exercise, payload: exercise, deletedAt: deletedAt);

  final TrashKind kind;
  final Object payload; // Session | Workout | Exercise
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

- [ ] **Step 4: Run tests** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/trash_entry.dart test/models/trash_entry_test.dart
git commit -m "feat(models): add TrashEntry"
```

---

### Task 6: `TrashService` (read/write/purge) + tests

**Files:**
- Create: `lib/services/trash_service.dart`
- Test: `test/services/trash_service_test.dart`

- [ ] **Step 1: Write failing tests**

Use the same `_FakePathProvider` pattern from `test/services/sync_queue_service_test.dart` to point `path_provider` at a temp dir. Three tests:
- `add then read` round-trips entries.
- `purgeOlderThan(30 days)` removes entries with `deletedAt < cutoff` and keeps the rest.
- `restore(id)` removes the entry and returns it.

- [ ] **Step 2: Implement `TrashService`**

API (all async):
```dart
class TrashService {
  Future<List<TrashEntry>> readAll();
  Future<void> add(TrashEntry entry);
  Future<TrashEntry?> restore(String id);
  Future<int> purgeOlderThan(Duration ttl, {DateTime? now});
  // Internally writes to '<docs>/trash.json'.
}
```

Use `PresetLogger.savePresetToFile` pattern as a reference (separate file). Keep it stateless aside from disk I/O — `PresetProvider` will own the in-memory cache.

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/trash_service.dart test/services/trash_service_test.dart
git commit -m "feat(trash): add TrashService with 30-day purge"
```

---

### Task 7: `PresetProvider` adopts `TrashService`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_trash_test.dart` (CREATE)

**Why:** Provider becomes the single entry point for trash operations and exposes `trashedItems` to the UI.

- [ ] **Step 1: Write failing tests** (in the new test file)

- `init()` (or a new `loadTrash()` if preferred to avoid cloud paths) populates `trashedItems`.
- `deleteToTrash(id, kind)` moves the item out of the corresponding user list AND adds a TrashEntry.
- `restoreFromTrash(id)` brings it back into the user list and removes it from trash.
- Items with `deletedAt` older than 30 days are not loaded into `trashedItems` (purged on init).

- [ ] **Step 2: Add `trashedItems` getter, `_trashService`, `_trashedItems` cache**

In `PresetProvider`:

```dart
final TrashService _trashService = TrashService();
List<TrashEntry> _trashedItems = [];
List<TrashEntry> get trashedItems => List.unmodifiable(_trashedItems);

Future<void> _loadAndPurgeTrash() async {
  await _trashService.purgeOlderThan(const Duration(days: 30));
  _trashedItems = await _trashService.readAll();
}
```

Call `_loadAndPurgeTrash()` from `init()` after the existing user-list load. (Cloud-trash sync is OUT OF SCOPE for this plan — local-only trash is sufficient for v1; add a TODO comment.)

- [ ] **Step 3: Add CRUD**

```dart
Future<void> deleteToTrash({required String id, required TrashKind kind}) async {
  // Pull from the corresponding user list (or default list — see Task 19 for routing).
  // Wrap in a TrashEntry, persist via _trashService.add, update _userX list,
  // call notifyListeners, and persist via PresetLogger.
}

Future<void> restoreFromTrash(String id) async {
  final entry = await _trashService.restore(id);
  if (entry == null) return;
  switch (entry.kind) {
    case TrashKind.workout:
      _userWorkouts.add(entry.payload as Workout);
      await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
    // ...session, exercise
  }
  _trashedItems.removeWhere((e) => e.id == id);
  notifyListeners();
}
```

(Detailed routing for default-vs-user is handled in Task 19.)

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

```bash
git add lib/providers/preset_provider.dart test/providers/preset_provider_trash_test.dart
git commit -m "feat(preset): wire TrashService into PresetProvider"
```

---

## Phase 3 — Promote-default-on-edit

### Task 8: `presetWorkouts` shadow rule

**Files:**
- Modify: `lib/providers/preset_provider.dart:43-46`
- Test: `test/providers/preset_provider_promote_default_test.dart` (CREATE)

**Why:** When a default's id appears in `_userWorkouts`, the user copy must shadow the default so consumers see exactly one row. This replaces `_hiddenDefaultIds`.

- [ ] **Step 1: Write failing test**

```dart
test('presetWorkouts: user copy with default id shadows the default', () {
  final p = PresetProvider();
  // Inject directly via a test helper or seed via addPresetWorkout if init() not called.
  // (See test/providers/preset_provider_propagate_test.dart for the pattern.)
  // ... seed _defaultWorkouts with a default 'd1' ...
  // ... add a user workout with id == 'd1', different title ...
  expect(p.presetWorkouts.where((w) => w.id == 'd1').length, 1);
  expect(p.presetWorkouts.firstWhere((w) => w.id == 'd1').title, 'user-edit');
});
```

- [ ] **Step 2: Implement the shadow rule**

```dart
List<Workout> get presetWorkouts {
  final userIds = _userWorkouts.map((w) => w.id).toSet();
  return [
    ..._defaultWorkouts.where((w) => !userIds.contains(w.id)),
    ..._userWorkouts,
  ];
}
```

- [ ] **Step 3: Run tests** — PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/providers/preset_provider.dart test/providers/preset_provider_promote_default_test.dart
git commit -m "feat(preset): user-list shadows default-list by id"
```

---

### Task 9: Same shadow rule for `presetExercises` and `presetSessions`

**Files:**
- Modify: `lib/providers/preset_provider.dart:39-50`

- [ ] **Step 1: Add tests for both** (parallel to Task 8).
- [ ] **Step 2: Apply the same pattern** to the two other getters.
- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "feat(preset): user-list shadows default-list for exercises & sessions"
```

---

### Task 10: `PresetProvider.promoteAndUpdate*` methods

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_promote_default_test.dart`

**Why:** Single entry point that handles both first-edit-of-a-default (insert into user list) and subsequent edits (update existing user row). Called by all three edit screens.

- [ ] **Step 1: Write tests**

- `promoteAndUpdateWorkout` on a default-id: inserts into `_userWorkouts`, persists.
- Same on a user-id that already exists: updates in place, persists.
- Idempotent on retry.

- [ ] **Step 2: Implement**

```dart
Future<void> promoteAndUpdateWorkout(Workout updated) async {
  final userIndex = _userWorkouts.indexWhere((w) => w.id == updated.id);
  if (userIndex == -1) {
    _userWorkouts.add(updated);
  } else {
    _userWorkouts[userIndex] = updated;
  }
  await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
  if (_syncService != null) {
    try { await _syncService!.uploadWorkout(updated); }
    catch (e, st) { Sentry.captureException(e, stackTrace: st); }
  }
  notifyListeners();
}

// Same for promoteAndUpdateExercise and promoteAndUpdateSession.
```

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "feat(preset): add promoteAndUpdateWorkout/Exercise/Session"
```

---

### Task 11: `NewWorkoutScreen._save()` uses `promoteAndUpdateWorkout`

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart:73-130`

**Why:** Replace the three-branch (`_isNew` / `isDefault` / else) with two: `_isNew` calls `addPresetWorkout`; existing items call `promoteAndUpdateWorkout`. This is what makes the user's bug report fix manifest end-to-end.

- [ ] **Step 1: Reduce `_save()` to**

```dart
if (widget.persistToProvider) {
  final presetProvider = Provider.of<PresetProvider>(context, listen: false);
  if (_isNew) {
    await presetProvider.addPresetWorkout(workout);
  } else {
    await presetProvider.promoteAndUpdateWorkout(workout);
    final affected = presetProvider.sessionTemplatesUsingWorkout(workout.id);
    if (affected.isNotEmpty && mounted) {
      final yes = await showPropagateChangesDialog(
        context: context,
        itemKind: 'workout',
        affectedItemLabels: affected.map((s) => s.title).toList(),
      );
      if (yes == true) {
        await presetProvider.propagateWorkoutToSessionTemplates(workout);
      }
    }
  }
}
```

Remove the `isDefault` branch entirely.

- [ ] **Step 2: Manual repro of user's exact bug**

1. New session → add a default workout → save.
2. Open the catalog → open that default workout → change exercise sets → save.
3. **Expected:** propagation prompt appears listing the session by name.
4. Tap **Update all** → the session reflects the new sets.
5. Tap **Keep local** → only the catalog reflects the change; the session keeps the original sets.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(workout-edit): unify save path; promote-on-first-edit & always offer propagation"
```

---

### Task 12: `NewExerciseScreen._save()` mirrors Task 11

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart:101-180`

- [ ] **Steps:** Replace the `_isNew` / `isDefault` / else with `_isNew` → `addPresetExercise`; else → `promoteAndUpdateExercise` + propagation prompt against `sessionWorkoutPathsUsingExercise`.
- [ ] **Manual repro:** edit a default exercise that's used in 1+ session-template workouts → prompt appears with `Session → Workout` paths.
- [ ] **Commit**

```bash
git commit -m "fix(exercise-edit): unify save path; promote-on-first-edit & always offer propagation"
```

---

### Task 13: `NewSessionScreen._save()` mirrors Task 11

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart:71-125`

- [ ] **Steps:** `_isNew` → `addPresetSession`; else → `promoteAndUpdateSession`. (No propagation needed for sessions — they're top-level.)
- [ ] **Commit**

```bash
git commit -m "fix(session-edit): unify save path; promote-on-first-edit"
```

---

## Phase 4 — Strip default-fork machinery

### Task 14: Remove `_isEditingDefault` & friends from edit screens

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart` (remove `_isEditingDefault`, `allKnownWorkoutTitles` branch in title validator, simplify validator)
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` (same)
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart` (same)

**Why:** With promotion-on-edit, there's no special "editing a default" state. Title validator becomes the simple "must be unique among current items, but you may keep your own existing title" rule.

- [ ] **Step 1: For each screen, simplify the title validator** to:

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

(No more "editing default" branch.)

- [ ] **Step 2: Delete `_isEditingDefault` getters.**

- [ ] **Step 3: Run tests** — `flutter test` should be green.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(edit-screens): drop _isEditingDefault; uniform title validation"
```

---

### Task 15: Remove default-fork machinery from `PresetProvider`

**Files:**
- Modify: `lib/providers/preset_provider.dart`

**Symbols to remove:**
- `_keyHiddenDefaultIds`, `_hiddenDefaultIds`, `_loadHiddenDefaultIds`, `_saveHiddenDefaultIds`
- `isDefaultItem`, `isModifiedDefault`, `hideDefaultItem`, `restoreAllDefaults`
- `allKnownExerciseTitles`, `allKnownWorkoutTitles`, `allKnownSessionTitles`
- `userCreatedExerciseCount`, `userCreatedWorkoutCount`, `userCreatedSessionCount`
- `presetDefaultSessions`, `presetUserSessions` (if unused after refactor — check)
- The `_hiddenDefaultIds.clear()` line in `reset()`

- [ ] **Step 1: Find consumers** — `grep -rn "isDefaultItem\|isModifiedDefault\|hideDefaultItem\|restoreAllDefaults\|allKnown.*Titles\|userCreated.*Count" lib/ test/`. Update or remove each consumer.

- [ ] **Step 2: Delete the symbols and their helpers.**

- [ ] **Step 3: Run `flutter analyze`** — expect 0 new warnings (only pre-existing ones from elsewhere).

- [ ] **Step 4: Run tests** — `flutter test` green.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(preset): remove default-fork machinery"
```

---

### Task 16: Delete `default_edit_tip.dart`

**Files:**
- Delete: `lib/utils/default_edit_tip.dart`
- Modify: any callsite of `showDefaultEditTipIfNeeded` (already removed in Tasks 11-13; double-check)

- [ ] **Step 1: Confirm no callsites remain** — `grep -rn showDefaultEditTipIfNeeded lib/ test/` should be empty.
- [ ] **Step 2: Delete the file.** Also delete the `pref_seen_default_edit_tip` SharedPreferences key (it'll just become orphaned; no migration needed).
- [ ] **Step 3: Commit**

```bash
git rm lib/utils/default_edit_tip.dart
git commit -m "refactor: remove default-edit tip dialog"
```

---

### Task 17: Update default-data file comments

**Files:**
- Modify: `lib/data/default_workout_data.dart:11-14`
- Modify: `lib/data/default_session_data.dart:8-12`

- [ ] **Step 1: Replace the "_hiddenDefaultIds" rationale** with: "IDs are stable keys referenced by trash entries (`trash.json`), session templates (via `templateId`), and Supabase row keys. Do not change an existing id once shipped — doing so will orphan trash entries and template references for existing users."
- [ ] **Step 2: Commit**

```bash
git commit -m "docs(defaults): update id-stability rationale"
```

---

## Phase 5 — Trash-routed deletion in catalog

### Task 18: `PresetProvider.deleteToTrash` (full implementation)

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: extend `test/providers/preset_provider_trash_test.dart`

**Note:** Task 7 stubbed this; finalize it now that the default/user model is unified.

- [ ] **Step 1: Tests**
  - Deleting a user workout: removes from `_userWorkouts`, adds to trash, persists both.
  - Deleting a default workout that hasn't been edited: read default from `_defaultWorkouts`, add a TrashEntry; on subsequent reads, `presetWorkouts` no longer includes it.
- [ ] **Step 2: Implementation** — for defaults, "deleting" means there's no row to remove from `_userWorkouts`; instead, the trashed-id is added to a `_trashedDefaultIds` set (derived from `_trashedItems`) that the `presetWorkouts` getter consults.

  Update the shadow rule from Task 8 to:

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

(Same for exercises and sessions.)

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "feat(preset): unify deletion through trash for defaults & user items"
```

---

### Task 19: `catalog_screen._hideOrDeleteItem` routes through trash

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/catalog_screen.dart:87-155`

- [ ] **Step 1: Replace `_hideOrDeleteItem`** with:

```dart
Future<void> _moveToTrash(dynamic item) async {
  final confirm = await _showTrashConfirmationDialog(item.title);
  if (confirm != true) return;
  final pp = Provider.of<PresetProvider>(context, listen: false);
  final kind = switch (widget.itemType) {
    ItemType.sessions => TrashKind.session,
    ItemType.workouts => TrashKind.workout,
    ItemType.exercises => TrashKind.exercise,
  };
  await pp.deleteToTrash(id: item.id, kind: kind);
}
```

- [ ] **Step 2: Replace both old dialogs with one** (`_showTrashConfirmationDialog`):

```
Title: "Move to trash?"
Body: "\"$title\" will be moved to the trash. You can restore it within 30 days from Settings."
Actions: Cancel | Move to trash
```

- [ ] **Step 3: Manual repro**
  - Slidable Delete on a default exercise → confirmation appears → confirm → exercise disappears from catalog.
  - Slidable Delete on a user workout → same dialog, same flow.
  - Both items are visible in the Restore Items screen (Task 21).

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(catalog): route all deletes through trash"
```

---

### Task 20: Unified delete dialog wording

Folded into Task 19. Skip if already complete.

---

## Phase 6 — Restore Items screen

### Task 21: `RestoreItemsScreen` UI scaffolding

**Files:**
- Create: `lib/presentation/screens/settings/restore_items_screen.dart`

- [ ] **Step 1: Build the UI** — `Scaffold` with an `AppBar('Restore items')`. Body is a `Consumer<PresetProvider>` rendering three sections (Sessions / Workouts / Exercises) with `Checkbox` per item and a single "Restore selected" `FilledButton` at the bottom.

  - Each section is a `Card` with a `Text` header and a `Column` of `CheckboxListTile`.
  - If a section is empty, hide it.
  - If trash is empty entirely, show a centered `Empty trash` message.
  - State: a `Set<String> _selected` of trash entry ids.

- [ ] **Step 2: Visual sanity check** — run the app, populate the trash with one item per kind, navigate to the screen, verify layout.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(settings): add RestoreItemsScreen scaffolding"
```

---

### Task 22: Wire bulk restore + replace settings tile

**Files:**
- Modify: `lib/presentation/screens/settings/restore_items_screen.dart` (action wiring)
- Modify: `lib/presentation/screens/root_screen.dart:325-329`, `lib/presentation/screens/root_screen.dart:373-408`

- [ ] **Step 1: Implement action**

```dart
Future<void> _restoreSelected(BuildContext context, Set<String> selected) async {
  final pp = Provider.of<PresetProvider>(context, listen: false);
  for (final id in selected) {
    await pp.restoreFromTrash(id);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored ${selected.length} items')),
    );
  }
}
```

- [ ] **Step 2: Replace settings tile**

In `root_screen.dart`, replace the "Restore defaults" `ListTile` and `_showRestoreDefaultsDialog` with:

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

Delete `_showRestoreDefaultsDialog`.

- [ ] **Step 3: Manual repro**
  1. Trash a default exercise + a user workout.
  2. Settings → Restore items → check both → tap Restore selected.
  3. Both reappear in the catalog.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(settings): replace Restore defaults with Restore items picker"
```

---

## Phase 7 — Propagation prompt fires for every relevant edit

### Task 23: End-to-end manual verification of the user's bug report

**Files:** none (verification only)

- [ ] Use the exact steps from the user's report:
  1. New session → add a workout → save.
  2. Catalog → open same workout → change exercise sets → save.
  3. **Expected:** propagation prompt appears listing the affected session.
  4. Tap **Update all** → session reflects new sets.
  5. Re-do the test, tapping **Keep local** → session retains old sets.

If the prompt does not fire, investigate before proceeding to Task 24.

---

### Task 24: Verify propagation runs after promotion completes

**Files:**
- Re-read: `lib/presentation/screens/training_program_flow/new_workout_screen.dart` (after Task 11)
- Re-read: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` (after Task 12)

- [ ] Confirm that in each `_save()` the order is: `await promoteAndUpdate*(workout)` → `sessionTemplatesUsing*` → dialog → `propagate*ToSessionTemplates`. The lookup must run AFTER the promote so the user list is current; the propagation must use the value the user just saved (not a stale `widget.workout`).
- [ ] No code change expected if Task 11/12 were done correctly. If the order is wrong, fix it and re-commit.

---

## Phase 8 — Cleanup

### Task 25: `flutter analyze` clean

- [ ] Run `flutter analyze`. The pre-existing 6 info-level findings are acceptable; no new warnings introduced by this plan.

### Task 26: `flutter test` green

- [ ] Run `flutter test`. All tests pass, including the new model/service/provider tests added in this plan.

---

## Verification (end-to-end smoke)

After all tasks land, the following must hold without code changes:

1. **Mutability:** open the catalog, edit an exercise inside a workout, press the back button without saving → catalog and any sessions referencing the workout still show the original content.
2. **Promotion:** edit a default workout for the first time → catalog shows your edit; the same id; no second copy; no banner; no tip dialog.
3. **Propagation:** edit a workout used in ≥1 session template → prompt appears listing the templates by name; Yes propagates, No keeps templates on the previous content.
4. **Trash:** slidable Delete on any catalog item (default or user) → confirmation dialog → item disappears from catalog and appears in `Settings → Restore items`. Within 30 days, it can be restored. After 30 days (verifiable in tests via `purgeOlderThan`), it's purged.
5. **Restore:** check items in `Restore items`, tap Restore selected → items reappear in the catalog. The original default's id is preserved on restore.
6. **No regressions:** start a session, run it, complete it. Logged sessions are unaffected. `flutter test` green; `flutter analyze` only shows pre-existing warnings.

## Out of scope

- Cloud sync of trash entries (local-only for v1; add a TODO).
- Changing how completed session logs are stored or displayed.
- Touching the active running session model.
- Migrating the `pref_seen_default_edit_tip` SharedPreferences key (we leave it orphaned).
- Per-item conflict UI when restoring an id that already exists in user list (shouldn't happen with current flows, but add a defensive `if (existingUserIndex != -1) overwrite` rather than a UI dialog).
