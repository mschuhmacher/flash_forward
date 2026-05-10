# PresetProvider Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split [lib/providers/preset_provider.dart](../../../lib/providers/preset_provider.dart) (1,148 LOC) into focused units — a `CatalogProvider`, a `TrashProvider`, an `EditCommitController`, a `SyncStatusProvider` — with two pure helpers (`PresetSyncMerger`, `PresetLoader`) lifted out, and a generic `PersistedListWriter` collapsing the duplicated 4-step write recipe. Functionality must be preserved bit-for-bit; the existing test suite is the safety net.

**Architecture:** Extract pure helpers first (zero-risk, test-only changes). Then introduce the `PersistedListWriter` and migrate the 12 near-identical CRUD methods inside `PresetProvider` so internal cleanup happens before the structural split. Then extract `TrashProvider`, exposing trash state via `Listenable.merge` so catalog merged-list getters remain reactive. Then extract `EditCommitController` (orchestration) and `SyncStatusProvider` (sync-status passthroughs that were duplicated in `SessionLogProvider` too). Finally rename `PresetProvider` to `CatalogProvider`, register the new providers in `MultiProvider`, and migrate ~16 call sites. Each step is gated by `flutter test` returning green.

**Tech Stack:** Flutter, Provider (ChangeNotifier + ProxyProvider), Dart, `flutter_test`, Sentry, Supabase. No new external dependencies.

---

## File Map

| Action | File |
|--------|------|
| Create | `lib/providers/preset_loader.dart` |
| Create | `lib/providers/preset_sync_merger.dart` |
| Create | `lib/providers/persisted_list_writer.dart` |
| Create | `lib/providers/sync_status_provider.dart` |
| Create | `lib/providers/trash_provider.dart` |
| Create | `lib/providers/edit_commit_controller.dart` |
| Create | `lib/providers/catalog_provider.dart` |
| Delete | `lib/providers/preset_provider.dart` (after migration) |
| Modify | `lib/main.dart` (MultiProvider registration) |
| Modify | ~16 call sites — see Task 11 |
| Create | `test/providers/preset_loader_test.dart` |
| Create | `test/providers/preset_sync_merger_test.dart` |
| Create | `test/providers/persisted_list_writer_test.dart` |
| Create | `test/providers/sync_status_provider_test.dart` |
| Create | `test/providers/trash_provider_test.dart` |
| Create | `test/providers/edit_commit_controller_test.dart` |
| Create | `test/providers/catalog_provider_test.dart` (umbrella) |
| Migrate | `test/providers/preset_provider_merge_test.dart` → `preset_sync_merger_test.dart` |
| Migrate | `test/providers/preset_provider_trash_test.dart` → split: trash-state assertions go to `trash_provider_test.dart`, catalog-side assertions stay against `CatalogProvider` |
| Migrate | `test/providers/preset_provider_promote_default_test.dart` → `catalog_provider_test.dart` (rename references) |
| Migrate | `test/providers/preset_provider_propagate_test.dart` → `catalog_provider_test.dart` (rename references) |
| Migrate | `test/providers/preset_provider_commit_changes_test.dart` → `edit_commit_controller_test.dart` (rename references) |

---

## Locked design decisions

These have been agreed and must not be revisited mid-execution.

1. **Public API style breaks.** Call sites are migrated to read the narrower provider (`CatalogProvider`, `TrashProvider`, etc.). No facade is kept.
2. **Single shared `SupabaseSyncService` instance.** Currently each of `PresetProvider` and `SessionLogProvider` owns its own `_syncService`. After this refactor, `SyncStatusProvider` owns the singleton; `CatalogProvider` and `TrashProvider` receive it via constructor injection. `SessionLogProvider` is updated in this plan only at the registration level so it can also accept the shared instance — its internals are not refactored here (out of scope; tracked in Plan B).
3. **`TrashProvider` depends on `CatalogProvider`** and is wired with `ChangeNotifierProxyProvider` — `TrashProvider` mutates user lists on `restoreFromTrash`/`liftToCatalog`, and `CatalogProvider` filters trashed ids in its merged-list getters by listening to `TrashProvider`. The reactive seam is `Listenable.merge([catalog, trash])` for any UI that wants both.
4. **Behavior preservation is the gate.** Each task ends with `flutter test` returning fully green. If a migrated test fails, the migration is wrong, not the test.
5. **`mergeWithPendingOps` and `mergeTrashCloudAndLocal` keep their static signatures** when moved to helpers, so migrated tests can call them with minimal change.
6. **`@visibleForTesting` debug seeders (`debugSeedDefaults`, `debugSeedTrash`)** stay on the new providers — they're load-bearing in 4 of the 5 existing test files.
7. **No behavior changes to error handling.** Every cloud upload/delete is wrapped in `try/catch` with `Sentry.captureException` exactly as today, including the existing best-effort semantics (failures in cloud writes do not throw to callers; failures in local writes propagate).
8. **No backwards-compatibility shims.** When `preset_provider.dart` is deleted, all call sites and imports are migrated in the same task.

---

## Task 1: Extract `PresetSyncMerger`

**Why first:** It's a pure static method with zero dependencies on `PresetProvider` state. Moving it is a rename + import update. There is already a dedicated test file ([preset_provider_merge_test.dart](../../../test/providers/preset_provider_merge_test.dart)) that exercises it directly, so the safety net is at full strength.

**Files:**
- Create: `lib/providers/preset_sync_merger.dart`
- Modify: `lib/providers/preset_provider.dart` (remove `mergeWithPendingOps`, replace internal callers)
- Migrate: `test/providers/preset_provider_merge_test.dart` → `test/providers/preset_sync_merger_test.dart`

- [ ] **Step 1: Run baseline tests**

```bash
flutter test
```
Expected: all PASS. Confirms the starting state is green.

- [ ] **Step 2: Create the helper**

Create `lib/providers/preset_sync_merger.dart`:

```dart
import 'package:flash_forward/services/sync_queue_service.dart';

/// Pure helpers for merging cloud results with locally-queued sync operations
/// and for deduplicating trash-entry lists. Extracted from PresetProvider so
/// they can be reused and tested in isolation.
class PresetSyncMerger {
  PresetSyncMerger._();

  /// Merges [cloudItems] with items from [pendingOps] that have not yet been
  /// uploaded (i.e. their id is absent from cloud results).
  ///
  /// Only operations matching [operationType] are considered.
  /// Items with a pending [deleteOperationType] op are excluded — they were
  /// deleted locally and must not be re-surfaced.
  /// Cloud always wins when the same id appears in both cloud and upload queue.
  ///
  /// Note: [fromJson] receives data serialised by the model's own toJson()
  /// (camelCase keys from the local queue), not the Supabase column mapping
  /// used in fetchUser*. Do not swap these callsites.
  static List<T> mergeWithPendingOps<T>({
    required List<T> cloudItems,
    required String Function(T) getId,
    required String operationType,
    required String deleteOperationType,
    required T Function(Map<String, dynamic>) fromJson,
    required List<SyncOperation> pendingOps,
  }) {
    final cloudIds = cloudItems.map(getId).toSet();
    final deletedIds = pendingOps
        .where((op) => op.type == deleteOperationType)
        .map((op) => op.id)
        .toSet();
    final unsynced = pendingOps
        .where((op) =>
            op.type == operationType &&
            !cloudIds.contains(op.id) &&
            !deletedIds.contains(op.id))
        .map((op) => fromJson(op.data));
    final filteredCloud =
        cloudItems.where((item) => !deletedIds.contains(getId(item))).toList();
    return [...filteredCloud, ...unsynced];
  }
}
```

Note: this is a verbatim move. Do not change semantics.

- [ ] **Step 3: Migrate the test file**

Rename `test/providers/preset_provider_merge_test.dart` to `test/providers/preset_sync_merger_test.dart`. Update its imports and replace `PresetProvider.mergeWithPendingOps` with `PresetSyncMerger.mergeWithPendingOps`:

```bash
git mv test/providers/preset_provider_merge_test.dart \
       test/providers/preset_sync_merger_test.dart
```

Then in the renamed file:
- Replace `import 'package:flash_forward/providers/preset_provider.dart';` with `import 'package:flash_forward/providers/preset_sync_merger.dart';`
- Replace `group('PresetProvider.mergeWithPendingOps', () {` with `group('PresetSyncMerger.mergeWithPendingOps', () {`
- Replace each `PresetProvider.mergeWithPendingOps<` with `PresetSyncMerger.mergeWithPendingOps<` (7 occurrences expected).

- [ ] **Step 4: Run the migrated test**

```bash
flutter test test/providers/preset_sync_merger_test.dart
```
Expected: all 7 tests PASS. If any fail, the rename was incomplete.

- [ ] **Step 5: Update `PresetProvider` to delegate to the helper**

In `lib/providers/preset_provider.dart`:
- Add `import 'package:flash_forward/providers/preset_sync_merger.dart';`
- Delete the entire `static List<T> mergeWithPendingOps<T>(...)` method body (lines 205-226).
- Update the three call sites in `_loadUserPresetDataFromCloud` (around lines 157, 165, 173) to call `PresetSyncMerger.mergeWithPendingOps(...)` with identical arguments.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The 4 other preset_provider tests must still pass — they exercise paths that go through the cloud-load merge.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/preset_provider.dart \
        lib/providers/preset_sync_merger.dart \
        test/providers/preset_sync_merger_test.dart
git commit -m "refactor(presets): extract mergeWithPendingOps to PresetSyncMerger"
```

---

## Task 2: Extract trash-list merge into `PresetSyncMerger`

**Why next:** Same pattern as Task 1 — another pure static method, also already tested directly via `mergeTrashCloudAndLocalForTest`. Moving it now means the helper is "complete" before we touch any stateful code.

**Files:**
- Modify: `lib/providers/preset_sync_merger.dart`
- Modify: `lib/providers/preset_provider.dart`
- Modify: `test/providers/preset_provider_trash_test.dart` (only the lines that call `mergeTrashCloudAndLocalForTest`)

- [ ] **Step 1: Add the helper method**

Append to `lib/providers/preset_sync_merger.dart` (inside the class):

```dart
/// Merges [local] and [cloud] trash lists, deduplicating by id.
/// When both lists contain the same id, the entry with the later [deletedAt]
/// wins (last-write-wins conflict resolution).
static List<TrashEntry> mergeTrashCloudAndLocal(
  List<TrashEntry> local,
  List<TrashEntry> cloud,
) {
  final byId = <String, TrashEntry>{};
  for (final e in local) {
    byId[e.id] = e;
  }
  for (final e in cloud) {
    final existing = byId[e.id];
    if (existing == null || e.deletedAt.isAfter(existing.deletedAt)) {
      byId[e.id] = e;
    }
  }
  return byId.values.toList();
}
```

Add at the top: `import 'package:flash_forward/models/trash_entry.dart';`

- [ ] **Step 2: Update PresetProvider to delegate**

In `lib/providers/preset_provider.dart`:
- Delete the `_mergeTrashCloudAndLocal` static method (around line 885-900).
- Delete the `mergeTrashCloudAndLocalForTest` method (around line 879-883).
- Replace the single internal call site in `_loadAndPurgeTrash` (around line 784) with `PresetSyncMerger.mergeTrashCloudAndLocal(...)`.

- [ ] **Step 3: Update the test file**

In `test/providers/preset_provider_trash_test.dart`:
- Add `import 'package:flash_forward/providers/preset_sync_merger.dart';`
- Replace the three `PresetProvider.mergeTrashCloudAndLocalForTest(...)` call sites (lines ~368, ~380, ~393) with `PresetSyncMerger.mergeTrashCloudAndLocal(...)`.

- [ ] **Step 4: Run the full suite**

```bash
flutter test
```
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/preset_provider.dart \
        lib/providers/preset_sync_merger.dart \
        test/providers/preset_provider_trash_test.dart
git commit -m "refactor(presets): move mergeTrashCloudAndLocal to PresetSyncMerger"
```

---

## Task 3: Extract `PresetLoader`

**Why next:** It's the second pure helper. It currently lives as two private methods (`_loadUserPresetDataFromCloud`, `_loadUserPresetDataFromLocal`) that are only called from `init()`. Extracting them removes the implicit coupling between `PresetProvider.init` and `SupabaseSyncService` internals, and gives us a unit-testable load step.

**Files:**
- Create: `lib/providers/preset_loader.dart`
- Create: `test/providers/preset_loader_test.dart`
- Modify: `lib/providers/preset_provider.dart`

- [ ] **Step 1: Write the failing test**

Create `test/providers/preset_loader_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PresetLoaderResult', () {
    test('exposes the three lists provided in the constructor', () {
      final result = PresetLoaderResult(
        sessions: const <Session>[],
        workouts: const <Workout>[],
        exercises: const <Exercise>[],
      );
      expect(result.sessions, isEmpty);
      expect(result.workouts, isEmpty);
      expect(result.exercises, isEmpty);
    });
  });
}
```

The full behavior of `PresetLoader.loadFromCloud` and `PresetLoader.loadFromLocal` is covered indirectly by the existing `preset_provider_promote_default_test.dart` and friends, which exercise `init()`. We only unit-test the result type here. The deeper behavior remains protected by the umbrella tests.

- [ ] **Step 2: Run — verify it fails**

```bash
flutter test test/providers/preset_loader_test.dart
```
Expected: compile error — `PresetLoader` does not exist.

- [ ] **Step 3: Create `lib/providers/preset_loader.dart`**

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';

/// The three user-preset lists, returned by [PresetLoader] as a single tuple.
class PresetLoaderResult {
  PresetLoaderResult({
    required this.sessions,
    required this.workouts,
    required this.exercises,
  });

  final List<Session> sessions;
  final List<Workout> workouts;
  final List<Exercise> exercises;
}

/// Loads user-preset lists from cloud (Supabase) or from local JSON.
/// Pure with respect to the in-memory state of [CatalogProvider] — does not
/// hold any state itself; the caller assigns the returned lists.
class PresetLoader {
  PresetLoader._();

  /// Load from Supabase, merging in queued (un-uploaded) operations.
  /// The caller is responsible for ensuring [syncService.syncQueue] is loaded
  /// before this is called.
  static Future<PresetLoaderResult> loadFromCloud(
    SupabaseSyncService syncService,
  ) async {
    final cloudSessions = await syncService.fetchUserSessions();
    final cloudWorkouts = await syncService.fetchUserWorkouts();
    final cloudExercises = await syncService.fetchUserExercises();
    final pending = syncService.syncQueue.pendingOperations;

    final sessions = PresetSyncMerger.mergeWithPendingOps(
      cloudItems: cloudSessions,
      getId: (s) => s.id,
      operationType: 'uploadSession',
      deleteOperationType: 'deleteSession',
      fromJson: Session.fromJson,
      pendingOps: pending,
    );
    final workouts = PresetSyncMerger.mergeWithPendingOps(
      cloudItems: cloudWorkouts,
      getId: (w) => w.id,
      operationType: 'uploadWorkout',
      deleteOperationType: 'deleteWorkout',
      fromJson: Workout.fromJson,
      pendingOps: pending,
    );
    final exercises = PresetSyncMerger.mergeWithPendingOps(
      cloudItems: cloudExercises,
      getId: (e) => e.id,
      operationType: 'uploadExercise',
      deleteOperationType: 'deleteExercise',
      fromJson: Exercise.fromJson,
      pendingOps: pending,
    );
    return PresetLoaderResult(
      sessions: sessions,
      workouts: workouts,
      exercises: exercises,
    );
  }

  /// Load from local JSON files only. Used when no user is authenticated, and
  /// as the cloud-failure fallback inside the caller.
  static Future<PresetLoaderResult> loadFromLocal() async {
    final sessions = (await PresetLogger.readUserPresetSessions()).toList();
    final workouts = (await PresetLogger.readUserPresetWorkouts()).toList();
    final exercises = (await PresetLogger.readUserPresetExercises()).toList();
    return PresetLoaderResult(
      sessions: sessions,
      workouts: workouts,
      exercises: exercises,
    );
  }
}
```

- [ ] **Step 4: Run the helper test**

```bash
flutter test test/providers/preset_loader_test.dart
```
Expected: PASS.

- [ ] **Step 5: Update `PresetProvider.init` to use the helper**

In `lib/providers/preset_provider.dart`:
- Add `import 'package:flash_forward/providers/preset_loader.dart';`
- Delete `_loadUserPresetDataFromCloud` (lines ~148-185).
- Delete `_loadUserPresetDataFromLocal` (lines ~188-192).
- In `init()`, replace the cloud branch with:

```dart
if (userId != null) {
  _syncService = SupabaseSyncService(userId: userId);
  await _syncService!.syncQueue.loadQueue();
  try {
    final loaded = await PresetLoader.loadFromCloud(_syncService!);
    _userSessions = loaded.sessions;
    _userWorkouts = loaded.workouts;
    _userExercises = loaded.exercises;
  } catch (e, stackTrace) {
    Sentry.captureException(e, stackTrace: stackTrace);
    final fallback = await PresetLoader.loadFromLocal();
    _userSessions = fallback.sessions;
    _userWorkouts = fallback.workouts;
    _userExercises = fallback.exercises;
  }
} else {
  final loaded = await PresetLoader.loadFromLocal();
  _userSessions = loaded.sessions;
  _userWorkouts = loaded.workouts;
  _userExercises = loaded.exercises;
}
```

This preserves the existing semantics: cloud-first when authenticated, with a Sentry-logged fallback to local on any cloud exception.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. Pay special attention to `preset_provider_promote_default_test.dart` and `preset_provider_propagate_test.dart` — they call `init()` indirectly via debug seeders, but any failure here means the `init` rewrite changed semantics.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/preset_loader.dart \
        lib/providers/preset_provider.dart \
        test/providers/preset_loader_test.dart
git commit -m "refactor(presets): extract user-preset loading into PresetLoader"
```

---

## Task 4: Introduce `PersistedListWriter` helper

**Why next:** The 12 add/update/delete methods inside `PresetProvider` follow an identical 4-step recipe (mutate in-memory list → save JSON → cloud op + Sentry → notify). Collapsing them into a generic helper is internal cleanup that doesn't change the public API of `PresetProvider` — call sites stay green. This must happen *before* the structural split, so the new providers inherit the cleaner shape.

**Files:**
- Create: `lib/providers/persisted_list_writer.dart`
- Create: `test/providers/persisted_list_writer_test.dart`
- Modify: `lib/providers/preset_provider.dart`

- [ ] **Step 1: Write the failing test**

Create `test/providers/persisted_list_writer_test.dart`:

```dart
import 'package:flash_forward/providers/persisted_list_writer.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  _Item(this.id, this.value);
  final String id;
  final int value;
}

void main() {
  group('PersistedListWriter', () {
    test('upsert adds when id is absent', () async {
      final list = <_Item>[];
      String? saved;
      _Item? uploaded;
      await PersistedListWriter.upsert<_Item>(
        list: list,
        item: _Item('a', 1),
        getId: (i) => i.id,
        saveLocal: () async => saved = 'saved',
        cloudOp: (i) async => uploaded = i,
      );
      expect(list.single.id, 'a');
      expect(saved, 'saved');
      expect(uploaded?.id, 'a');
    });

    test('upsert replaces in place when id exists', () async {
      final list = <_Item>[_Item('a', 1)];
      await PersistedListWriter.upsert<_Item>(
        list: list,
        item: _Item('a', 2),
        getId: (i) => i.id,
        saveLocal: () async {},
        cloudOp: (i) async {},
      );
      expect(list.single.value, 2);
    });

    test('removeById removes matching entries', () async {
      final list = <_Item>[_Item('a', 1), _Item('b', 2)];
      await PersistedListWriter.removeById<_Item>(
        list: list,
        id: 'a',
        getId: (i) => i.id,
        saveLocal: () async {},
        cloudOp: () async {},
      );
      expect(list.map((i) => i.id), ['b']);
    });

    test('upsert swallows cloudOp errors and logs to Sentry-equivalent', () async {
      final list = <_Item>[];
      Object? captured;
      await PersistedListWriter.upsert<_Item>(
        list: list,
        item: _Item('a', 1),
        getId: (i) => i.id,
        saveLocal: () async {},
        cloudOp: (i) async => throw StateError('cloud down'),
        onCloudError: (e, st) => captured = e,
      );
      expect(list.single.id, 'a', reason: 'local mutation must persist');
      expect(captured, isA<StateError>());
    });

    test('removeById propagates saveLocal errors', () async {
      final list = <_Item>[_Item('a', 1)];
      expect(
        () => PersistedListWriter.removeById<_Item>(
          list: list,
          id: 'a',
          getId: (i) => i.id,
          saveLocal: () async => throw StateError('disk full'),
          cloudOp: () async {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run — verify it fails**

```bash
flutter test test/providers/persisted_list_writer_test.dart
```
Expected: compile error — `PersistedListWriter` does not exist.

- [ ] **Step 3: Implement the helper**

Create `lib/providers/persisted_list_writer.dart`:

```dart
/// Encapsulates the local-list + local-file + cloud-op + Sentry recipe used
/// by every persisted-list mutation in CatalogProvider, TrashProvider, and
/// SessionLogProvider.
///
/// The helper does not call notifyListeners — the caller does that after the
/// returned future completes. This keeps the helper free of any Flutter
/// dependency.
class PersistedListWriter {
  PersistedListWriter._();

  /// Inserts [item] into [list] (replacing any entry with the same id),
  /// awaits [saveLocal], then awaits [cloudOp]. Errors from [cloudOp] are
  /// passed to [onCloudError] (typically Sentry) and swallowed; errors from
  /// [saveLocal] propagate to the caller.
  static Future<void> upsert<T>({
    required List<T> list,
    required T item,
    required String Function(T) getId,
    required Future<void> Function() saveLocal,
    Future<void> Function(T)? cloudOp,
    void Function(Object, StackTrace)? onCloudError,
  }) async {
    final id = getId(item);
    final i = list.indexWhere((e) => getId(e) == id);
    if (i == -1) {
      list.add(item);
    } else {
      list[i] = item;
    }
    await saveLocal();
    if (cloudOp != null) {
      try {
        await cloudOp(item);
      } catch (e, st) {
        onCloudError?.call(e, st);
      }
    }
  }

  /// Removes any entry in [list] with matching [id], awaits [saveLocal], then
  /// awaits [cloudOp]. Same error semantics as [upsert].
  static Future<void> removeById<T>({
    required List<T> list,
    required String id,
    required String Function(T) getId,
    required Future<void> Function() saveLocal,
    Future<void> Function()? cloudOp,
    void Function(Object, StackTrace)? onCloudError,
  }) async {
    list.removeWhere((e) => getId(e) == id);
    await saveLocal();
    if (cloudOp != null) {
      try {
        await cloudOp();
      } catch (e, st) {
        onCloudError?.call(e, st);
      }
    }
  }
}
```

- [ ] **Step 4: Run the helper tests**

```bash
flutter test test/providers/persisted_list_writer_test.dart
```
Expected: all 5 tests PASS.

- [ ] **Step 5: Migrate `PresetProvider` add/update methods**

In `lib/providers/preset_provider.dart`:
- Add `import 'package:flash_forward/providers/persisted_list_writer.dart';`
- Replace `addPresetSession`, `updatePresetSession`, `addPresetWorkout`, `updatePresetWorkout`, `addPresetExercise`, `updatePresetExercise`, `promoteAndUpdateSession`, `promoteAndUpdateWorkout`, `promoteAndUpdateExercise` to call `PersistedListWriter.upsert(...)`.

Example for `addPresetSession` (the existing add and update methods both collapse to upsert; promote* is also an upsert — see locked decision 1: external call sites can change, but in this task we keep public method names so internal-only churn is contained, and migrate names in Task 8):

```dart
Future<void> addPresetSession(Session session) async {
  await PersistedListWriter.upsert<Session>(
    list: _userSessions,
    item: session,
    getId: (s) => s.id,
    saveLocal: () => PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    ),
    cloudOp: _syncService == null
        ? null
        : (s) => _syncService!.uploadSession(s),
    onCloudError: Sentry.captureException,
  );
  notifyListeners();
}
```

Apply the same shape to all 9 add/update/promote methods. Each becomes ~10 lines.

- [ ] **Step 6: Migrate `PresetProvider` delete methods**

Replace `deleteUserPresetSession`, `deleteUserPresetWorkout`, `deleteUserPresetExercise` to call `PersistedListWriter.removeById(...)`. Example:

```dart
Future<void> deleteUserPresetSession(String id) async {
  await PersistedListWriter.removeById<Session>(
    list: _userSessions,
    id: id,
    getId: (s) => s.id,
    saveLocal: () => PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    ),
    cloudOp: _syncService == null
        ? null
        : () => _syncService!.deleteSession(id),
    onCloudError: Sentry.captureException,
  );
  notifyListeners();
}
```

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The 4 PresetProvider test files exercise add/update/delete across many paths — any failure here means the migration changed semantics.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/persisted_list_writer.dart \
        lib/providers/preset_provider.dart \
        test/providers/persisted_list_writer_test.dart
git commit -m "refactor(presets): collapse CRUD recipe into PersistedListWriter"
```

---

## Task 5: Introduce `SyncStatusProvider`

**Why next:** Three near-identical sync-status passthroughs (`hasPendingSync`, `pendingSyncCount`, `processPendingSync`) currently live on both `PresetProvider` and `SessionLogProvider`. Extracting them now means the structural split for `PresetProvider` (Tasks 7-9) inherits the cleaner shape, and `SessionLogProvider` is left untouched in this plan — it just keeps its own copies until Plan B addresses it.

The shared `SupabaseSyncService` instance is the key change here. Currently each provider creates its own. We introduce `SyncStatusProvider` as the owner; `CatalogProvider` and `TrashProvider` will receive it via constructor injection in later tasks.

**Files:**
- Create: `lib/providers/sync_status_provider.dart`
- Create: `test/providers/sync_status_provider_test.dart`
- (`PresetProvider` is *not* modified in this task — wiring happens in Task 7.)

- [ ] **Step 1: Write the failing test**

Create `test/providers/sync_status_provider_test.dart`:

```dart
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncStatusProvider', () {
    test('reports zero pending sync when no service is attached', () {
      final provider = SyncStatusProvider();
      expect(provider.hasPendingSync, isFalse);
      expect(provider.pendingSyncCount, 0);
    });

    test('processPendingSync returns 0 when no service is attached', () async {
      final provider = SyncStatusProvider();
      expect(await provider.processPendingSync(), 0);
    });

    test('attach() sets the service and notifies listeners', () {
      final provider = SyncStatusProvider();
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);
      // Use null detach + null attach to keep this test free of supabase mocks;
      // the field-update behavior is what we exercise here.
      provider.detach();
      expect(notifyCount, greaterThanOrEqualTo(1));
    });
  });
}
```

This is a deliberately thin unit test. Behavior against a real `SupabaseSyncService` is exercised end-to-end via the `CatalogProvider` umbrella tests (Task 9).

- [ ] **Step 2: Run — verify it fails**

```bash
flutter test test/providers/sync_status_provider_test.dart
```
Expected: compile error — `SyncStatusProvider` does not exist.

- [ ] **Step 3: Implement `SyncStatusProvider`**

Create `lib/providers/sync_status_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';

/// Owns the [SupabaseSyncService] instance and exposes pending-sync status to
/// any UI that wants to surface it without watching a domain provider.
///
/// Lifecycle:
/// - Construct once in MultiProvider, with no service attached.
/// - On login (LoadingScreen / LoginScreen), call [attach] with the userId-bound
///   service.
/// - On logout (RootScreen), call [detach] to clear the reference.
class SyncStatusProvider extends ChangeNotifier {
  SupabaseSyncService? _service;

  SupabaseSyncService? get service => _service;

  bool get hasPendingSync => _service?.hasPendingSync ?? false;
  int get pendingSyncCount => _service?.pendingSyncCount ?? 0;

  void attach(SupabaseSyncService service) {
    _service = service;
    notifyListeners();
  }

  void detach() {
    _service = null;
    notifyListeners();
  }

  Future<int> processPendingSync() async {
    if (_service == null) return 0;
    return await _service!.processPendingSync();
  }
}
```

- [ ] **Step 4: Run the helper test**

```bash
flutter test test/providers/sync_status_provider_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/sync_status_provider.dart \
        test/providers/sync_status_provider_test.dart
git commit -m "refactor(presets): introduce SyncStatusProvider"
```

---

## Task 6: Extract `TrashProvider`

**Why next:** Trash is the most isolated of the remaining domains. Its state (`_trashedItems`) is only touched in 6 methods (`_loadAndPurgeTrash`, `_selfHealCatalogTrashDrift`, `deleteToTrash`, `restoreFromTrash`, `liftToCatalog`, the `trashedItems` getter), and the existing `preset_provider_trash_test.dart` covers all of them. Extracting it before the rename keeps the diff focused.

**The dependency seam:** `TrashProvider` writes to user lists on restore/lift/heal; `CatalogProvider` reads `_trashedItems` to filter merged lists. We resolve this with a back-reference: `TrashProvider` holds a reference to `CatalogProvider`, given via constructor (`ChangeNotifierProxyProvider`). For now, while `PresetProvider` still exists, `TrashProvider` holds a reference to `PresetProvider` so it can mutate user lists. After Task 8 renames the class, the reference becomes `CatalogProvider`.

**Files:**
- Create: `lib/providers/trash_provider.dart`
- Create: `test/providers/trash_provider_test.dart`
- Modify: `lib/providers/preset_provider.dart` (delete the trash bits, add a small public surface for `TrashProvider` to call)
- Modify: `lib/main.dart` (add `ChangeNotifierProxyProvider` for `TrashProvider`)
- Modify: `test/providers/preset_provider_trash_test.dart` (split — see Step 7)

- [ ] **Step 1: Add the public mutation surface to `PresetProvider`**

`TrashProvider.deleteToTrash`/`restoreFromTrash`/`liftToCatalog` need to mutate `_userSessions`/`_userWorkouts`/`_userExercises`. Currently those are private. Expose minimal mutation methods that `TrashProvider` will call.

In `lib/providers/preset_provider.dart`, add (just below the existing public CRUD methods):

```dart
/// Used by TrashProvider when restoring or lifting items into the catalog.
/// Replaces or appends — same semantics as promoteAndUpdate*.
@protected
Future<void> upsertUserSession(Session s) => promoteAndUpdateSession(s);
@protected
Future<void> upsertUserWorkout(Workout w) => promoteAndUpdateWorkout(w);
@protected
Future<void> upsertUserExercise(Exercise e) => promoteAndUpdateExercise(e);

/// Used by TrashProvider for self-heal and deleteToTrash to remove without
/// uploading a delete (the trash entry itself is the source of truth).
@protected
Future<void> removeUserSessionLocal(String id) async {
  _userSessions.removeWhere((s) => s.id == id);
  await PresetLogger.savePresetToFile(
    'user_preset_sessions.json', _userSessions);
}
@protected
Future<void> removeUserWorkoutLocal(String id) async {
  _userWorkouts.removeWhere((w) => w.id == id);
  await PresetLogger.savePresetToFile(
    'user_preset_workouts.json', _userWorkouts);
}
@protected
Future<void> removeUserExerciseLocal(String id) async {
  _userExercises.removeWhere((e) => e.id == id);
  await PresetLogger.savePresetToFile(
    'user_preset_exercises.json', _userExercises);
}
```

These mirror the helpers `deleteToTrash` and `_selfHealCatalogTrashDrift` already perform inline; we're factoring them out so `TrashProvider` can call them. They are temporary — Task 8 promotes them to first-class catalog methods.

- [ ] **Step 2: Run baseline tests**

```bash
flutter test
```
Expected: all PASS. Adding methods that delegate to existing ones must not change behavior.

- [ ] **Step 3: Write the `TrashProvider` test stub**

Create `test/providers/trash_provider_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flash_forward/providers/trash_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

// One smoke test that proves wiring works end-to-end. Full behavior coverage
// is migrated from preset_provider_trash_test.dart in step 7.
void main() {
  late PresetProvider catalog;
  late TrashProvider trash;

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('trash_provider_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    catalog = PresetProvider();
    trash = TrashProvider(catalog: catalog, syncStatus: SyncStatusProvider());
  });

  test('trashedItems is empty on a fresh provider', () {
    expect(trash.trashedItems, isEmpty);
  });

  test('debugSeedTrash exposes seeded entries via trashedItems', () {
    trash.debugSeedTrash([
      TrashEntry.exercise(
        exercise: Exercise(id: 'e1', title: 'Ex', /* fill required fields */),
        deletedAt: DateTime(2026, 5, 1),
      ),
    ]);
    expect(trash.trashedItems, hasLength(1));
    expect(trash.trashedItems.single.id, 'e1');
  });
}
```

(The exact `Exercise` constructor arguments depend on the model. Mirror an existing test like `preset_provider_trash_test.dart` for the right shape.)

- [ ] **Step 4: Run — verify it fails**

```bash
flutter test test/providers/trash_provider_test.dart
```
Expected: compile error — `TrashProvider` does not exist.

- [ ] **Step 5: Implement `TrashProvider`**

Create `lib/providers/trash_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flash_forward/services/trash_service.dart';

/// Owns trash state. Depends on PresetProvider for catalog mutation
/// (restoreFromTrash, liftToCatalog, deleteToTrash) and on SyncStatusProvider
/// for cloud access (when authenticated).
class TrashProvider extends ChangeNotifier {
  TrashProvider({
    required PresetProvider catalog,
    required SyncStatusProvider syncStatus,
  })  : _catalog = catalog,
        _syncStatus = syncStatus;

  final PresetProvider _catalog;
  final SyncStatusProvider _syncStatus;
  final TrashService _trashService = TrashService();

  List<TrashEntry> _trashedItems = [];
  List<TrashEntry> get trashedItems => List.unmodifiable(_trashedItems);

  /// Returns the trashed ids partitioned by kind. CatalogProvider's merged-list
  /// getters read this to filter.
  Set<String> trashedIdsOf(TrashKind kind) => _trashedItems
      .where((e) => e.kind == kind)
      .map((e) => e.id)
      .toSet();

  @visibleForTesting
  void debugSeedTrash(List<TrashEntry> entries) {
    _trashedItems = List.from(entries);
    notifyListeners();
  }

  /// Called by CatalogProvider.init after the catalog lists are loaded.
  Future<void> loadAndPurge() async {
    final purgedIds =
        await _trashService.purgeOlderThan(const Duration(days: 90));
    _trashedItems = await _trashService.readAll();
    final svc = _syncStatus.service;
    if (svc != null) {
      for (final id in purgedIds) {
        try {
          await svc.deleteTrashEntry(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      try {
        final cloud = await svc.fetchUserTrashEntries();
        _trashedItems =
            PresetSyncMerger.mergeTrashCloudAndLocal(_trashedItems, cloud);
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }
    notifyListeners();
  }

  /// Called after init: ensures user-list rows for trashed ids are removed
  /// from disk and cloud, fixing drift from older builds.
  Future<void> selfHealCatalogTrashDrift() async {
    // Same body as PresetProvider._selfHealCatalogTrashDrift, but uses
    // _catalog.removeUserWorkoutLocal etc. (added in Step 1) and reads
    // user-id sets via the catalog's existing presetUserWorkoutsIDs/etc.
    // [Verbatim port — preserve every Sentry call and order of operations.]
    // ...
  }

  Future<void> deleteToTrash({
    required String id,
    required TrashKind kind,
  }) async {
    // Same body as PresetProvider.deleteToTrash, but list mutations route
    // through _catalog.removeUserWorkoutLocal etc., and the cloud sync goes
    // through _syncStatus.service. [Verbatim port — preserve every branch.]
    // ...
    notifyListeners();
  }

  Future<void> restoreFromTrash(String id, {String? overrideTitle}) async {
    // Verbatim port. Calls _catalog.upsertUserWorkout etc. for the restored
    // item, removes the entry from _trashedItems, calls
    // _syncStatus.service?.deleteTrashEntry on success.
    // ...
    notifyListeners();
  }

  Future<void> liftToCatalog({
    required Object item,
    required TrashKind kind,
    String? overrideTitle,
    String? overrideId,
  }) async {
    // Verbatim port. Calls _catalog.upsertUserWorkout/etc.
    // ...
    notifyListeners();
  }
}
```

The bodies marked `// ...` must be ported verbatim from `preset_provider.dart` lines 770-1097, with these substitutions:
- `_userSessions.removeWhere(...)` → `await _catalog.removeUserSessionLocal(...)` (and same for workout/exercise).
- `_userSessions.add(x)` followed by save+upload → `await _catalog.upsertUserSession(x)`.
- `_syncService` → `_syncStatus.service`.
- `_trashedItems.add` / `removeWhere` stays as-is (this state lives in TrashProvider now).
- All `Sentry.captureException` calls preserved verbatim.

- [ ] **Step 6: Wire into `main.dart`**

In `lib/main.dart`, replace the existing `MultiProvider` providers list with:

```dart
providers: [
  ChangeNotifierProvider(create: (context) => AuthProvider()),
  ChangeNotifierProvider(create: (context) => SessionLogProvider()),
  ChangeNotifierProvider(create: (context) => SyncStatusProvider()),
  ChangeNotifierProvider(create: (context) => PresetProvider()),
  ChangeNotifierProxyProvider2<PresetProvider, SyncStatusProvider, TrashProvider>(
    create: (context) => TrashProvider(
      catalog: context.read<PresetProvider>(),
      syncStatus: context.read<SyncStatusProvider>(),
    ),
    update: (_, catalog, syncStatus, previous) =>
        previous ?? TrashProvider(catalog: catalog, syncStatus: syncStatus),
  ),
  ChangeNotifierProvider(create: (_) => sessionStateProvider),
  ChangeNotifierProvider(create: (context) => SettingsProvider()),
],
```

Add the necessary imports.

- [ ] **Step 7: Wire `TrashProvider` into `PresetProvider.init`**

`PresetProvider.init` currently calls `_loadAndPurgeTrash()` and `_selfHealCatalogTrashDrift()`. Now those live on `TrashProvider`. The cleanest seam is for `init` to take an optional `TrashProvider` and call its methods after the catalog is loaded. Update the signature:

```dart
Future<void> init({String? userId, TrashProvider? trash}) async {
  // ... existing body up to "_isLoading = false" ...

  if (trash != null) {
    await trash.loadAndPurge();
    await trash.selfHealCatalogTrashDrift();
  }

  _isLoading = false;
  notifyListeners();
}
```

Then update the merged-list getters (`presetSessions`, `presetWorkouts`, `presetExercises`) to take their `trashedIds` from the optional `TrashProvider` if provided. To avoid plumbing the trash provider through every getter call, add a setter:

```dart
TrashProvider? _trash;
void attachTrashProvider(TrashProvider trash) {
  _trash = trash;
  trash.addListener(notifyListeners); // refilter when trash changes
}
```

Inside the getters, replace the local `trashedIds` computation with:

```dart
final trashedIds = _trash?.trashedIdsOf(TrashKind.workout) ?? const <String>{};
```

(and same for the other two kinds).

In `LoadingScreen` and `LoginScreen`, after constructing both providers, call `presetProvider.attachTrashProvider(trashProvider)` and pass `trash: trashProvider` into `init`.

- [ ] **Step 8: Delete the now-orphaned bits from `PresetProvider`**

Remove from `preset_provider.dart`:
- The `_trashService` field, `_trashedItems` field, `trashedItems` getter.
- `debugSeedTrash`.
- `_loadAndPurgeTrash`.
- `_selfHealCatalogTrashDrift`.
- `deleteToTrash`.
- `restoreFromTrash`.
- `liftToCatalog`.

The merged-list getters' trash-filtering logic now reads from `_trash`.

- [ ] **Step 9: Migrate `preset_provider_trash_test.dart`**

Split into two files:

**`test/providers/trash_provider_test.dart`**: tests that exercise `deleteToTrash`, `restoreFromTrash`, `liftToCatalog`, `loadAndPurge`, `selfHealCatalogTrashDrift`, `trashedItems` — those move and have their imports/types updated. The test setup constructs both a `PresetProvider` and a wired-up `TrashProvider`.

**Keep in `preset_provider_trash_test.dart` (or move to `catalog_provider_test.dart`)**: tests that assert merged-list filtering (e.g., "trashed workout disappears from `presetWorkouts`"). These need both providers but read primarily from the catalog.

Update the surviving file's `setUp` to construct both providers and call `attachTrashProvider`.

- [ ] **Step 10: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The `preset_provider_trash_test.dart` migrations are the highest-risk part of this plan — every failure means a behavior was lost in translation.

- [ ] **Step 11: Commit**

```bash
git add lib/providers/trash_provider.dart \
        lib/providers/preset_provider.dart \
        lib/main.dart \
        lib/presentation/screens/auth_flow/loading_screen.dart \
        lib/presentation/screens/auth_flow/login_screen.dart \
        test/providers/trash_provider_test.dart \
        test/providers/preset_provider_trash_test.dart
git commit -m "refactor(presets): extract TrashProvider with proxy provider wiring"
```

---

## Task 7: Wire `SyncStatusProvider` into `PresetProvider`

**Why next:** Now that `TrashProvider` already reads from `SyncStatusProvider`, take the same step for `PresetProvider`. Replace the internal `_syncService` field with a reference to the shared service. This is purely internal — no public API changes.

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Modify: `lib/main.dart`
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`, `lib/presentation/screens/auth_flow/login_screen.dart`, `lib/presentation/screens/root_screen.dart`

- [ ] **Step 1: Replace `_syncService` field**

In `preset_provider.dart`:
- Remove the `_syncService` field and `init`'s `_syncService = SupabaseSyncService(userId: userId);` line.
- Add `SyncStatusProvider? _syncStatus;` and a setter `void attachSyncStatus(SyncStatusProvider s) { _syncStatus = s; }`.
- Replace every `_syncService` reference with `_syncStatus?.service`. The `null` semantics are identical (no service = no cloud op).

- [ ] **Step 2: Update `init` to use the attached service**

```dart
Future<void> init({
  String? userId,
  TrashProvider? trash,
}) async {
  if (_isInitialized) return;
  _isInitialized = true;
  _isLoading = true;
  notifyListeners();

  _defaultSessions = List.from(kDefaultSessions);
  _defaultWorkouts = List.from(kDefaultWorkouts);
  _defaultExercises = List.from(kDefaultExercises);

  final svc = _syncStatus?.service;
  if (svc != null) {
    await svc.syncQueue.loadQueue();
    try {
      final loaded = await PresetLoader.loadFromCloud(svc);
      _userSessions = loaded.sessions;
      _userWorkouts = loaded.workouts;
      _userExercises = loaded.exercises;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      final fallback = await PresetLoader.loadFromLocal();
      _userSessions = fallback.sessions;
      _userWorkouts = fallback.workouts;
      _userExercises = fallback.exercises;
    }
  } else {
    final loaded = await PresetLoader.loadFromLocal();
    _userSessions = loaded.sessions;
    _userWorkouts = loaded.workouts;
    _userExercises = loaded.exercises;
  }

  if (trash != null) {
    await trash.loadAndPurge();
    await trash.selfHealCatalogTrashDrift();
  }

  _isLoading = false;
  notifyListeners();
}
```

Note `init` no longer takes `userId`. The caller is responsible for: creating the `SupabaseSyncService(userId: userId)`, calling `syncStatus.attach(svc)`, then calling `presetProvider.init()`.

- [ ] **Step 3: Remove the sync-passthrough getters from `PresetProvider`**

Delete `hasPendingSync`, `pendingSyncCount`, `processPendingSync` from `preset_provider.dart`. Anyone who needed them now reads `SyncStatusProvider` directly.

- [ ] **Step 4: Update `LoadingScreen` and `LoginScreen` to wire the chain**

In each, replace the existing init flow with:

```dart
final syncStatus = context.read<SyncStatusProvider>();
final presetProvider = context.read<PresetProvider>();
final trashProvider = context.read<TrashProvider>();

if (userId != null) {
  syncStatus.attach(SupabaseSyncService(userId: userId));
}
presetProvider.attachSyncStatus(syncStatus);
presetProvider.attachTrashProvider(trashProvider);
await presetProvider.init(trash: trashProvider);
```

- [ ] **Step 5: Update `RootScreen.reset` flow**

Currently calls `presetProvider.reset()`. Update so it also calls `syncStatus.detach()`. Keep `presetProvider.reset()` — it still resets in-memory lists and the trash list reset moves to `trashProvider.reset()` (add a no-arg `reset()` to `TrashProvider` that clears `_trashedItems` and notifies).

- [ ] **Step 6: Find and update any UI that reads `hasPendingSync`/`pendingSyncCount`/`processPendingSync` off `PresetProvider`**

```bash
grep -rn "presetProvider\.\(hasPendingSync\|pendingSyncCount\|processPendingSync\)\|<PresetProvider>().*\(hasPendingSync\|pendingSyncCount\|processPendingSync\)" lib/
```
Each match becomes a `SyncStatusProvider` lookup.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/preset_provider.dart \
        lib/presentation/screens/auth_flow/loading_screen.dart \
        lib/presentation/screens/auth_flow/login_screen.dart \
        lib/presentation/screens/root_screen.dart
git commit -m "refactor(presets): wire PresetProvider through SyncStatusProvider"
```

---

## Task 8: Extract `EditCommitController`

**Why next:** `commitChanges`, `propagateBag`, and `CommitResult` form a coherent orchestration surface that doesn't hold its own state. Extracting it now means `PresetProvider` (about to become `CatalogProvider`) is left with its core domain — defaults + user lists + propagation primitives.

**Files:**
- Create: `lib/providers/edit_commit_controller.dart`
- Modify: `lib/providers/preset_provider.dart` (remove `commitChanges`, `propagateBag`, `CommitResult`; keep `propagateWorkoutToSessionTemplates`, `propagateExerciseToSessionTemplates`, `propagateExerciseToWorkouts`, `usagesOfWorkout`, `usagesOfExercise`)
- Migrate: `test/providers/preset_provider_commit_changes_test.dart` → `test/providers/edit_commit_controller_test.dart`
- Modify: `lib/main.dart` (register `EditCommitController` as a `Provider` — no ChangeNotifier needed)
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`, `new_workout_screen.dart`, `new_exercise_screen.dart` — call sites that invoke `commitChanges`/`propagateBag`

- [ ] **Step 1: Create `EditCommitController`**

```dart
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';

/// Single entry point that edit screens call to commit a [PendingChangeBag]
/// and to run propagation. Holds no state; orchestrates over PresetProvider.
class EditCommitController {
  EditCommitController(this._catalog);
  final PresetProvider _catalog;

  /// See full doc on the original PresetProvider.commitChanges.
  Future<CommitResult> commitChanges(
    PendingChangeBag bag, {
    String? excludeSessionId,
    String? excludeWorkoutId,
  }) async {
    // Verbatim port of PresetProvider.commitChanges body. _catalog
    // replaces `this` for promoteAndUpdate*, usagesOfWorkout, usagesOfExercise.
    // ...
  }

  Future<void> propagateBag(PendingChangeBag bag) async {
    // Verbatim port of PresetProvider.propagateBag body.
    // ...
  }
}

class CommitResult {
  CommitResult({
    required this.affectedSessionsByWorkoutId,
    required this.affectedWorkoutsByExerciseId,
  });
  final Map<String, List<Session>> affectedSessionsByWorkoutId;
  final Map<String, List<Workout>> affectedWorkoutsByExerciseId;
  bool get hasAny =>
      affectedSessionsByWorkoutId.values.any((l) => l.isNotEmpty) ||
      affectedWorkoutsByExerciseId.values.any((l) => l.isNotEmpty);
}
```

- [ ] **Step 2: Remove `commitChanges`, `propagateBag`, `CommitResult` from `PresetProvider`**

Delete those exact methods/class from `preset_provider.dart`. Leave the propagation primitives (`propagateWorkoutToSessionTemplates`, `propagateExerciseToSessionTemplates`, `propagateExerciseToWorkouts`, `usagesOfWorkout`, `usagesOfExercise`) in place — they're still public-API surface of the catalog.

- [ ] **Step 3: Register the controller in `main.dart`**

```dart
ProxyProvider<PresetProvider, EditCommitController>(
  update: (_, catalog, __) => EditCommitController(catalog),
),
```

- [ ] **Step 4: Migrate the test file**

```bash
git mv test/providers/preset_provider_commit_changes_test.dart \
       test/providers/edit_commit_controller_test.dart
```

In the renamed file:
- Replace each call site that invokes `provider.commitChanges` with `controller.commitChanges`, where `controller = EditCommitController(provider)`.
- Update imports.

- [ ] **Step 5: Update edit screens**

`new_session_screen.dart`, `new_workout_screen.dart`, `new_exercise_screen.dart`: each currently calls `pp.commitChanges(...)` and `pp.propagateBag(...)`. Replace with `context.read<EditCommitController>().commitChanges(...)` etc.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/edit_commit_controller.dart \
        lib/providers/preset_provider.dart \
        lib/main.dart \
        lib/presentation/screens/training_program_flow/new_session_screen.dart \
        lib/presentation/screens/training_program_flow/new_workout_screen.dart \
        lib/presentation/screens/training_program_flow/new_exercise_screen.dart \
        test/providers/edit_commit_controller_test.dart
git commit -m "refactor(presets): extract EditCommitController for save orchestration"
```

---

## Task 9: Rename `PresetProvider` → `CatalogProvider`

**Why next:** All trash, sync-status, edit-commit responsibilities have been removed. What remains is the catalog domain: defaults, user lists, merged-list getters, CRUD, propagation primitives. Rename the file and class to reflect that. This is mechanical but touches every call site.

**Files:**
- Rename: `lib/providers/preset_provider.dart` → `lib/providers/catalog_provider.dart`
- Rename class: `PresetProvider` → `CatalogProvider` (everywhere)
- Rename method aliases added in Task 6 from `upsertUserSession` etc. to be the canonical names (delete the legacy `addPresetSession`, `updatePresetSession`, `promoteAndUpdateSession` aliases — keep one, e.g. `upsertSession`/`upsertWorkout`/`upsertExercise`).
- Modify: `lib/main.dart`, `lib/presentation/...` (16 call sites)
- Migrate test files (rename references)

- [ ] **Step 1: Rename the file**

```bash
git mv lib/providers/preset_provider.dart lib/providers/catalog_provider.dart
```

- [ ] **Step 2: Rename the class**

In the new file, rename `PresetProvider` → `CatalogProvider` everywhere (class declaration, debug seeders, etc.).

- [ ] **Step 3: Settle the public API method names**

Decide once for the whole catalog — recommend canonical:

| Old | New |
|---|---|
| `addPresetSession` / `updatePresetSession` / `promoteAndUpdateSession` | `upsertSession` |
| `addPresetWorkout` / `updatePresetWorkout` / `promoteAndUpdateWorkout` | `upsertWorkout` |
| `addPresetExercise` / `updatePresetExercise` / `promoteAndUpdateExercise` | `upsertExercise` |
| `deleteUserPresetSession` | `deleteSession` |
| `deleteUserPresetWorkout` | `deleteWorkout` |
| `deleteUserPresetExercise` | `deleteExercise` |
| `presetSessions` / `presetWorkouts` / `presetExercises` | unchanged (semantically still the catalog) |

Apply the renames inside `catalog_provider.dart`. The semantic difference between `add` and `update` was already collapsed by `PersistedListWriter.upsert` in Task 4 — there's only one method per kind needed.

- [ ] **Step 4: Update all call sites**

```bash
grep -rln "PresetProvider\|presetProvider" lib/ test/
```
For each file:
- Replace `import 'package:flash_forward/providers/preset_provider.dart';` with `import 'package:flash_forward/providers/catalog_provider.dart';`.
- Replace `PresetProvider` with `CatalogProvider`.
- Replace `presetProvider` local-variable name with `catalogProvider` (or keep — local name doesn't matter, but consistency helps).
- Replace renamed methods per the table in Step 3.

The 16 call sites listed in the original analysis are:
- `lib/main.dart` (registration)
- `lib/models/pending_change.dart` (doc comment only)
- `lib/presentation/screens/session_flow/session_select_screen.dart`
- `lib/presentation/screens/session_flow/session_active_screen.dart`
- `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`
- `lib/presentation/screens/training_program_flow/add_item_screen.dart`
- `lib/presentation/screens/training_program_flow/catalog_screen.dart`
- `lib/presentation/screens/training_program_flow/new_session_screen.dart`
- `lib/presentation/screens/training_program_flow/new_workout_screen.dart`
- `lib/presentation/screens/auth_flow/loading_screen.dart`
- `lib/presentation/screens/auth_flow/login_screen.dart`
- `lib/presentation/screens/profile_flow/restore_items_screen.dart`
- `lib/presentation/screens/root_screen.dart`
- `lib/presentation/widgets/session_select_row.dart`
- `lib/presentation/widgets/session_select_listview.dart`

- [ ] **Step 5: Update the remaining test files**

```bash
git mv test/providers/preset_provider_promote_default_test.dart \
       test/providers/catalog_provider_promote_default_test.dart
git mv test/providers/preset_provider_propagate_test.dart \
       test/providers/catalog_provider_propagate_test.dart
```

Inside both, rename `PresetProvider` → `CatalogProvider` and update method names per Step 3.

The third surviving file (`preset_provider_trash_test.dart`, post-Task-6 split) handles catalog-side filtering — also rename it to `catalog_provider_trash_filtering_test.dart` for consistency, and update its references.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. This is the make-or-break point — if anything fails, an import or rename was missed.

- [ ] **Step 7: Static analysis**

```bash
flutter analyze
```
Expected: no errors. Warnings about unused imports are acceptable but should be cleaned up.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(presets): rename PresetProvider to CatalogProvider with canonical method names"
```

---

## Task 10: Restore-screen call site (special case)

`restore_items_screen.dart` has a long file rename in this branch already (`settings/restore_items_screen.dart` → `profile_flow/restore_items_screen.dart`). It depends heavily on `PresetProvider` for *both* trash (`pp.trashedItems`, `pp.restoreFromTrash`, `pp.liftToCatalog`) and catalog reads (`pp.presetWorkouts`, `pp.presetExercises`, `pp.presetSessions`). After the split, the screen needs both `CatalogProvider` (for reads) and `TrashProvider` (for restore/lift).

**Files:**
- Modify: `lib/presentation/screens/profile_flow/restore_items_screen.dart`

- [ ] **Step 1: Update the `Consumer`**

Replace the existing `Consumer<PresetProvider>(...)` with `Consumer2<CatalogProvider, TrashProvider>(builder: (context, catalog, trash, _) { ... })`.

Inside the builder:
- `pp.trashedItems` → `trash.trashedItems`.
- `pp.restoreFromTrash(id, overrideTitle: t)` → `trash.restoreFromTrash(id, overrideTitle: t)`.
- `pp.liftToCatalog(...)` → `trash.liftToCatalog(...)`.
- `pp.presetWorkouts` / `pp.presetExercises` / `pp.presetSessions` → `catalog.presetWorkouts` / etc.

The helper methods on the screen (`_titleClashes`, `_existingTitlesForKind`, `_restoreSelected`) currently take `PresetProvider pp` — change their signatures to take both `(CatalogProvider catalog, TrashProvider trash)` and route accordingly.

- [ ] **Step 2: Run the full suite**

```bash
flutter test
```
Expected: all PASS.

- [ ] **Step 3: Manual smoke test (UI)**

Restore-flow has trash → list → restore-with-rename and trash → list → lift-to-catalog. Both must still render correctly and update their lists after action. The skill instruction is: start the dev server, restore an item, verify it appears in the catalog after restore.

```bash
flutter run -d <device>
```

Walk through:
1. Trash a catalog workout from `catalog_screen.dart`.
2. Open the restore screen.
3. Verify the workout appears with its title.
4. Trigger a title clash by renaming a different workout to the trashed title.
5. Restore — verify the rename dialog appears and the renamed item lands in the catalog.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/profile_flow/restore_items_screen.dart
git commit -m "refactor(presets): split restore-screen consumer across Catalog and Trash providers"
```

---

## Task 11: Sweep — find and fix forgotten imports

After the structural changes, run a final sweep for orphans and duplicate logic.

- [ ] **Step 1: Find unused imports**

```bash
flutter analyze 2>&1 | grep -i "unused"
```

Clean each one.

- [ ] **Step 2: Confirm no `PresetProvider` references remain**

```bash
grep -rn "PresetProvider" lib/ test/
```
Expected: zero matches.

- [ ] **Step 3: Confirm no duplicate sync-passthroughs survived on `CatalogProvider`**

```bash
grep -nE "hasPendingSync|pendingSyncCount|processPendingSync" lib/providers/catalog_provider.dart
```
Expected: zero matches.

- [ ] **Step 4: Run the full suite + analyzer one more time**

```bash
flutter test && flutter analyze
```
Expected: green + zero analyzer errors.

- [ ] **Step 5: Manual UI smoke test**

Walk through the major flows (each is a known consumer of one of the new providers):

1. **Catalog flow:** add workout, edit workout (with propagation prompt), trash, restore.
2. **Session flow:** start session, complete session, view in calendar.
3. **Auth flow:** sign out, sign back in, verify catalog and trash both reload.
4. **Offline flow:** kill network, mutate a workout, restore network, see sync indicator clear.

If any of these regress, the diff in this task surfaces what was missed.

- [ ] **Step 6: Commit (if Step 1 found anything)**

```bash
git add lib/ test/
git commit -m "refactor(presets): clean up unused imports after split"
```

---

## Plan-level acceptance criteria

- [ ] `flutter test` passes after every numbered task commit (no skipped tasks).
- [ ] `flutter analyze` returns zero errors after Task 11.
- [ ] Total LOC across `catalog_provider.dart` + `trash_provider.dart` + `edit_commit_controller.dart` + `sync_status_provider.dart` + `preset_loader.dart` + `preset_sync_merger.dart` + `persisted_list_writer.dart` is roughly half of the original 1,148 (target: 600-700 LOC for production code).
- [ ] No file in this set exceeds 600 LOC.
- [ ] All 16 known call sites have been updated to read the narrower provider.
- [ ] Manual smoke walk in Task 11 Step 5 shows no behavioral regression.

---

## Architectural risks (open before execution)

1. **`ChangeNotifierProxyProvider` ordering.** `TrashProvider` depends on `CatalogProvider` and `SyncStatusProvider`; the order in the `MultiProvider` list matters. If the proxy fires before its deps are constructed, we get a runtime null. **Mitigation:** the create lambda guards against missing deps, and Tasks 6/7 have a `flutter test` gate that catches construction failures.
2. **`Listenable.merge` for combined catalog+trash UI.** Some widgets (e.g., `session_select_row.dart`, `session_select_listview.dart`) use `Consumer2<PresetProvider, SessionStateProvider>`. After the split, anything that needs both catalog + trash data needs `Consumer3` or merged listenables. **Mitigation:** Task 10 calls this out explicitly; Task 9 Step 4 enumerates all sites.
3. **`TrashProvider.attachTrashProvider` setter on CatalogProvider creates a circular reference.** `CatalogProvider._trash` holds a reference to `TrashProvider`, and `TrashProvider._catalog` holds a reference back. Each listens to the other; in Flutter `ChangeNotifier` this is fine (no leak as long as both are owned by `MultiProvider`), but on `dispose` the listeners must be removed. **Mitigation:** add a `@override dispose()` on `CatalogProvider` that removes its trash listener.
4. **`init({String? userId})` signature change.** Currently call sites pass `userId`. After Task 7 they don't — the `SyncStatusProvider.attach` is the new seam. **Mitigation:** Task 7 Step 4 updates `LoadingScreen` and `LoginScreen` (the only two `init`-callers) explicitly.
5. **Test setup churn.** Each migrated test file's `setUp` constructs different combinations of providers. Risk of subtle test-only bugs (e.g., forgetting `attachSyncStatus` in a test that exercises cloud paths). **Mitigation:** prefer `setUp` helpers like `_makeCatalogWithDeps()` shared across the new test files.

---

## Execution Handoff

This plan is ready. **Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Use `superpowers:subagent-driven-development`.

2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batched with checkpoints for review.

**Note from the user:** this plan is queued behind `2026-05-05-superset-feature.md`. After superset ships, the user will update this plan if any line numbers or method names have shifted, then pick an execution mode.
