# Propagation ID Stability and Session-Scoped Commit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Editing a session-embedded workout/exercise should (1) find all sibling sessions for the propagation prompt regardless of how many propagations have already happened, and (2) never silently create a duplicate catalog entry.

**Background — two bugs:**

1. **Lookup misses templateId siblings.** After a Yes-to-propagate, `propagateWorkoutToSessionTemplates` writes a `Workout.deepCopy()` (no `keepId`) into each affected session. Each embedded copy gets a fresh UUID; only `templateId` links back to the catalog. On a second edit of any embedded copy, `usagesOfWorkout(<fresh-uuid>)` finds no other sessions sharing that fresh id, so the prompt does not fire and propagation cannot run.

2. **Session-embedded workouts are silently promoted.** `commitChanges` calls `promoteAndUpdateWorkout`/`promoteAndUpdateExercise` for every item in the bag. For a session-screen save the bag contains the session's embedded workouts and exercises (which have fresh UUIDs from the deep-copy above). They are appended to `_userWorkouts`/`_userExercises` as new catalog entries — duplicates with the catalog originals.

**Resolution:** Treat `id` as the stable identity of a template. Embedded copies in sessions retain the catalog id; deep-copies for propagation/embedding default to `keepId: true`. Slidable Copy stays on `deepCopy()` with a fresh UUID (intentional fork). `commitChanges` becomes session-scope-aware: when the bag has a session, the bagged workouts/exercises are session-embedded and are NOT pushed to the catalog.

**Tech Stack:** Flutter (Dart), Provider, flutter_test

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Modify | `lib/models/workout.dart` | Doc-comment update on `deepCopy({keepId})` |
| Modify | `lib/models/exercise.dart` | Doc-comment update on `deepCopy({keepId})` |
| Modify | `lib/models/session.dart` | Doc-comment update on `deepCopy({keepId})` |
| Modify | `lib/providers/preset_provider.dart` | `propagate*` functions use `keepId: true`; `commitChanges` skips catalog promotion when `bag.session != null` |
| Modify | `lib/presentation/screens/training_program_flow/add_item_screen.dart` | On-add `deepCopy()` → `deepCopy(keepId: true)` |
| Modify | `lib/presentation/screens/training_program_flow/new_session_screen.dart` | Comment-only on `_copyWorkout` |
| Modify | `lib/presentation/screens/training_program_flow/new_workout_screen.dart` | Comment-only on `_copyExercise` |
| Test | `test/providers/preset_provider_propagate_test.dart` | New tests for id stability + second-pass edit |
| Test | `test/providers/preset_provider_commit_changes_test.dart` | New tests for session-scoped commit not promoting |

---

## Data invariants

1. **`id` is the stable logical identity of a template.** A catalog workout, every session-embedded copy of it, and every propagated-into-sibling copy all share the same `id`. The `id` answers "which template is this?".

2. **`templateId` is a soft breadcrumb.** Set by `deepCopy(keepId: false)` to point at the source's id. Used today only to support legacy data and a possible future "this used to be a fork of X" feature. Not used for propagation lookup once this plan ships, because the stable `id` covers that case.

3. **Object identity ≠ id identity.** Two sessions referencing the same template each hold their own Dart `Workout` instance (independent in memory, deep-copied) but share the catalog id. Mutating one cannot leak into the other (deep-copy guarantee), but propagation can find both (id-match guarantee).

4. **`_pending.workoutsById` "last edit wins per session" is unchanged.** Within a single session edit, if the same workout id appears twice (e.g. user added the same template as two cards for circuits) and the user edits one of them, the bag holds the latest edit under that id. The session's `setSession(...)` carries both occurrences inline; the propagation logic targets the catalog id and updates other sessions accordingly.

5. **Slidable Copy means divergence.** `_copyWorkout` and `_copyExercise` keep generating fresh UUIDs. Two cards in the same session that came from a Copy are independent and do not propagate to each other.

6. **Session-start (logging) is unchanged.** Starting a session run still calls `Session.deepCopy(keepId: false)` so the run record gets a fresh id distinct from the template.

---

## Task List Overview

### Phase 1 — Update propagation and embedding to keep ids
- [ ] Task 1: `propagateWorkoutToSessionTemplates` uses `keepId: true` + tests
- [ ] Task 2: `propagateExerciseToSessionTemplates` uses `keepId: true` + tests
- [ ] Task 3: `propagateExerciseToWorkouts` uses `keepId: true` + tests
- [ ] Task 4: `AddItemScreen` returns `deepCopy(keepId: true)` + manual repro

### Phase 2 — Session-scoped `commitChanges`
- [ ] Task 5: `commitChanges` skips catalog promotion when `bag.session != null` + tests
- [ ] Task 6: Adjust existing tests that assumed unconditional promotion

### Phase 3 — Documentation and intent comments
- [ ] Task 7: Update `Workout`/`Exercise`/`Session` `deepCopy` doc-comments
- [ ] Task 8: Annotate `_copyWorkout`/`_copyExercise` with intent

### Phase 4 — End-to-end verification and cleanup
- [ ] Task 9: Manual repro of the original bug scenarios
- [ ] Task 10: `flutter analyze` clean and `flutter test` green

---

## Phase 1 — Update propagation and embedding to keep ids

### Task 1: `propagateWorkoutToSessionTemplates` uses `keepId: true`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_propagate_test.dart`

**Why:** After propagation, sibling sessions must be discoverable by `usagesOfWorkout(catalogId)`. Today the propagation rewrites embedded copies with fresh UUIDs, so the lookup misses them on the next edit.

- [ ] **Step 1: Failing test**

In `propagateWorkoutToSessionTemplates` group:

```dart
test('embedded copies retain the catalog id after propagation', () async {
  final ex = _exercise(id: 'cat-e', sets: 3);
  final catalogW = _workout(id: 'cat-w', exercises: [ex]);
  final embeddedA = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
  final embeddedB = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
  final sA = _session(id: 's-a', workouts: [embeddedA]);
  final sB = _session(id: 's-b', workouts: [embeddedB]);
  provider.debugSeedDefaults(workouts: [catalogW], sessions: [sA, sB]);

  final updated = catalogW.copyWith(timeBetweenExercises: 999);
  await provider.propagateWorkoutToSessionTemplates(updated);

  for (final session in provider.presetSessions) {
    for (final w in session.workouts) {
      expect(w.id, 'cat-w', reason: 'id must remain catalog id after propagation');
    }
  }
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
Future<void> propagateWorkoutToSessionTemplates(Workout updated) async {
  final affected = usagesOfWorkout(updated.id);
  for (final session in affected) {
    final newWorkouts = session.workouts.map((w) {
      if (w.id == updated.id || w.templateId == updated.id) {
        return updated.deepCopy(keepId: true);
      }
      return w;
    }).toList();
    await promoteAndUpdateSession(session.copyWith(workouts: newWorkouts));
  }
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(propagate): keep catalog id when propagating workout edits"
```

---

### Task 2: `propagateExerciseToSessionTemplates` uses `keepId: true`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_propagate_test.dart`

- [ ] **Step 1: Failing test** — mirror Task 1 for exercise: after propagation, every embedded exercise has `id == updated.id`.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** — change the inner exercise replacement:

```dart
final newExercises = w.exercises.map((e) {
  if (e.id == updated.id || e.templateId == updated.id) {
    return updated.deepCopy(keepId: true);
  }
  return e;
}).toList();
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(propagate): keep catalog id when propagating exercise edits to sessions"
```

---

### Task 3: `propagateExerciseToWorkouts` uses `keepId: true`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_propagate_test.dart`

- [ ] **Step 1: Failing test** — propagate an exercise edit; assert each affected workout's matching exercise retains `id == updated.id`.

- [ ] **Step 2: Implement**

```dart
final newExercises = workout.exercises.map((e) {
  if (e.id == updated.id || e.templateId == updated.id) {
    return updated.deepCopy(keepId: true);
  }
  return e;
}).toList();
```

- [ ] **Step 3: Run; commit**

```bash
git commit -m "fix(propagate): keep catalog id when propagating exercise edits to workouts"
```

---

### Task 4: `AddItemScreen` returns `deepCopy(keepId: true)`

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/add_item_screen.dart`

**Why:** When a catalog item is added to a session for the first time, the embedded copy's id should match the catalog id so the very first edit (or the first propagation) can find siblings.

- [ ] **Step 1: Replace the on-pop deep-copy**

```dart
final independent = selectedPresetItems.map((item) {
  if (item is Workout) return item.deepCopy(keepId: true);
  if (item is Exercise) return item.deepCopy(keepId: true);
  return item;
}).toList();
Navigator.pop(context, independent);
```

- [ ] **Step 2: Manual repro**: New session → add a default workout → save → catalog → edit that workout → save → propagation prompt fires listing the new session.

- [ ] **Step 3: Run tests; commit**

```bash
git commit -m "fix(add-item): preserve catalog id on add so first-edit propagation works"
```

---

## Phase 2 — Session-scoped `commitChanges`

### Task 5: `commitChanges` skips catalog promotion when `bag.session != null`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_commit_changes_test.dart`

**Why:** A session-screen save passes a bag containing the session and its session-embedded workouts/exercises. Those embedded items must NOT become standalone catalog rows. They live inside the session JSON and are persisted by the session's own promote.

- [ ] **Step 1: Failing tests**

```dart
test('session-scoped commit does not promote workouts to catalog', () async {
  final ex = _exercise(id: 'cat-e');
  final catalogW = _workout(id: 'cat-w', exercises: [ex]);
  final sa = _session(id: 'cat-s', workouts: [catalogW]);
  provider.debugSeedDefaults(workouts: [catalogW], sessions: [sa]);

  final embeddedW = catalogW.copyWith(timeBetweenExercises: 999);
  final bag = PendingChangeBag()
    ..setSession(sa.copyWith(workouts: [embeddedW]))
    ..addWorkout(embeddedW);

  final beforeUserWorkouts = provider.presetUserWorkoutsIDs.length;
  await provider.commitChanges(bag);

  expect(provider.presetUserWorkoutsIDs.length, beforeUserWorkouts);
});

test('session-scoped commit does not promote exercises to catalog', () async {
  // mirror the workout test for exercises
});

test('catalog-scoped commit still promotes (regression guard)', () async {
  final w = _workout(id: 'cat-w', exercises: []);
  provider.debugSeedDefaults(workouts: [w]);
  final bag = PendingChangeBag()..addWorkout(w.copyWith(timeBetweenExercises: 999));
  await provider.commitChanges(bag);
  expect(provider.presetUserWorkoutsIDs, contains('cat-w'));
});
```

- [ ] **Step 2: Run** — first two FAIL, third PASS (existing behaviour).

- [ ] **Step 3: Implement**

```dart
Future<CommitResult> commitChanges(
  PendingChangeBag bag, {
  String? excludeSessionId,
  String? excludeWorkoutId,
}) async {
  final isSessionScopedCommit = bag.session != null;

  if (!isSessionScopedCommit) {
    for (final ec in bag.exercisesById.values) {
      await promoteAndUpdateExercise(ec.exercise);
    }
    for (final wc in bag.workoutsById.values) {
      await promoteAndUpdateWorkout(wc.workout);
    }
  }
  if (bag.session != null) {
    await promoteAndUpdateSession(bag.session!.session);
  }

  // ── affected-consumer computation unchanged ──────────────────────────────
  // (existing sessionsByWorkout / workoutsByExercise logic stays as-is)
  // ...
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(preset): commitChanges skips catalog promotion for session-scoped bags"
```

---

### Task 6: Adjust existing commit-changes tests

**Files:**
- Modify: `test/providers/preset_provider_commit_changes_test.dart`

**Why:** The test "promotes in dependency order: exercises before workouts before session" asserts all three lists grow together. Under the new model, a session-scoped bag only grows `_userSessions`. Split or update.

- [ ] **Step 1:** Audit the existing tests in this file. For each test that builds a session-scoped bag (i.e. calls `bag.setSession(...)`):
  - If it asserts `_userWorkouts`/`_userExercises` membership after commit, update the assertion to confirm those lists are unchanged.
  - If it asserts dependency-ordering, split into two tests: one for catalog-scoped (workouts and exercises promoted), one for session-scoped (only session promoted; bagged workouts/exercises are not in `_user*`).

- [ ] **Step 2: Run; commit**

```bash
git commit -m "test(preset): adjust commit-changes tests for session-scope semantics"
```

---

## Phase 3 — Documentation and intent comments

### Task 7: Update `deepCopy` doc-comments

**Files:**
- Modify: `lib/models/workout.dart`, `lib/models/exercise.dart`, `lib/models/session.dart`

- [ ] **Step 1: Replace the `deepCopy` doc-comment** with:

```dart
/// Creates an independent Dart copy with deep-copied children.
///
/// With [keepId] = true (default for propagation, AddItemScreen, and any
/// "this is the same logical template, just a separate instance" use case):
/// the copy keeps the source's id and templateId. Mutating one instance
/// cannot leak into another (deep-copy guarantee), but propagation lookups
/// (`usagesOfWorkout`/`usagesOfExercise`) match by id and so naturally
/// find every sibling instance.
///
/// With [keepId] = false: generates a fresh UUID and sets templateId as a
/// breadcrumb pointing at the source's id. Use only for genuine forks:
/// slidable Copy (intentional divergence — the user wants to evolve the
/// copy independently of the original) and starting a session run (the
/// run record is its own entity, not a template).
```

(Adjust per model — the `Workout` version mentions exercises, the `Session` version mentions workouts.)

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(models): clarify keepId semantics on deepCopy"
```

---

### Task 8: Annotate `_copyWorkout`/`_copyExercise` with intent

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart`

**Why:** A future reader looking at `workout.deepCopy()` (no `keepId`) might think it's stale. Make the intent explicit so they don't "fix" it.

- [ ] **Step 1: Add a one-liner above each Copy method**:

```dart
// Slidable Copy means divergence. Fresh UUID so this card evolves
// independently of the original (e.g. a circuits use case where the same
// template appears twice with different reps/loads).
_copyWorkout(Workout workout) {
  final newWorkout = workout.deepCopy();
  ...
}
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs(edit-screens): explain why slidable Copy uses fresh UUIDs"
```

---

## Phase 4 — End-to-end verification and cleanup

### Task 9: Manual repro

Run through these scenarios on a real device or simulator:

- [ ] **Step 1: First-pass propagation (regression guard).**
  1. Two default sessions both contain Climbing Warm-up.
  2. Open Session A → drill into Climbing Warm-up → change an exercise's reps → save the session.
  3. Combined prompt fires listing Session B as affected. Tap **Update all**.
  4. Open Session B — embedded Climbing Warm-up shows the new reps.

- [ ] **Step 2: Second-pass propagation (the bug this plan fixes).**
  1. Open Session B (just updated above) → drill into Climbing Warm-up → change a different exercise's reps → save the session.
  2. **Combined prompt fires** listing the other sessions (A, plus any others).
  3. Tap **Update all** → all of them update.

- [ ] **Step 3: No catalog duplicates.**
  1. After running steps 1–2, open the Workouts tab in the catalog.
  2. **Climbing Warm-up appears exactly once.** No duplicate user-list entry.

- [ ] **Step 4: Slidable Copy still creates a fork.**
  1. Inside a session edit, slidable-Copy a workout.
  2. The copy gets a fresh UUID (verifiable via debug print or by editing one and confirming the other doesn't change).
  3. After save, the copy is part of the session but does not appear in the catalog.

- [ ] **Step 5: Standalone catalog edit still works (regression guard).**
  1. Open the Workouts catalog tab → tap a workout → edit → save.
  2. If used in any session, the prompt fires. Update all → sessions get the new content.

---

### Task 10: `flutter analyze` clean and `flutter test` green

- [ ] **Step 1:** `flutter analyze` — no new warnings.
- [ ] **Step 2:** `flutter test` — all tests pass.

---

## Out of scope (call out for future plans)

- **Removing `templateId` from the model.** It can stay as an unused-for-now breadcrumb. If it becomes truly orphaned later we can drop it in a separate plan.
- **Per-consumer checkbox propagation.** Tracked in a separate plan ("Per-consumer checkbox propagation prompt"). Depends on the id-stability shipped here.
- **Deduplicating already-leaked catalog entries.** If the user has stale duplicates from before this plan ships, they'll see them in the catalog. Trash them manually via slidable Delete; the trash auto-purges after 90 days.
- **Conflict semantics when a session contains the same template twice (circuits).** Today: `_pending.workoutsById` keys by id, so the second edit wins; the session retains both cards. This plan does not change that. If a future feature needs per-occurrence editing it would extend the bag to key by `(sessionWorkoutIndex, id)`.
