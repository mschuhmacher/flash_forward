# Preset Session Persistence Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all sync-queue reliability gaps causing preset sessions (and workouts/exercises) to disappear or fail to sync: dequeue by type instead of id-only, add delete-retry for workouts/exercises, merge unsynced queue items with cloud data on load, and fix the Supabase `user_sessions` table so `uploadSession` succeeds.

**Architecture:** Four independent fixes building on a logical foundation: (1) fix `SyncQueueService.dequeue` to remove by `(id, type)` instead of just `id` so a successful upload no longer silently swallows a pending delete for the same item; (2) add `isRetry` + enqueue pattern to `deleteWorkout`/`deleteExercise` (already present for `deleteSession`); (3) after loading from cloud, append items that are in the local sync queue but not yet in cloud, skipping items with a pending delete; (4) fix the Supabase `user_sessions` table so `uploadSession` stops failing.

**Tech Stack:** Flutter/Dart, Provider, Supabase (PostgREST), `flutter_test`, `path_provider_platform_interface`

---

## Context: Why these bugs?

The `await` fix (already applied to `_save()` in both screen files) ensures `savePresetToFile` completes before navigation. But for logged-in users, `_loadUserPresetDataFromCloud` always loads from cloud on restart — the local file is only used as fallback when the cloud fetch **throws**. If `uploadSession` fails (queued for retry) but `fetchUserSessions` succeeds, cloud returns stale data and the locally-written session is silently ignored.

Additionally, `dequeue` currently removes all ops for a given id, meaning a successful upload silently removes any co-pending `deleteSession` for the same item. And `deleteWorkout`/`deleteExercise` have no retry logic at all.

Tasks 1 and 2 fix the sync queue's own correctness. Task 3 adds the defensive merge that makes the load path resilient to upload failures. Task 4 fixes the root cause of upload failures for sessions. All four ship together.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/services/sync_queue_service.dart` | Modify | Fix `dequeue` to remove by `(id, type)` |
| `lib/services/supabase_sync_service.dart` | Modify | Add retry to `deleteWorkout`/`deleteExercise`; update `processPendingSync` switch |
| `lib/providers/preset_provider.dart` | Modify | Add `mergeWithPendingOps`; update `init()` and `_loadUserPresetDataFromCloud` |
| `test/services/sync_queue_service_test.dart` | Create | Unit tests for `dequeue` by `(id, type)` |
| `test/providers/preset_provider_merge_test.dart` | Create | Unit tests for `mergeWithPendingOps` |

---

## Task 1: Fix `dequeue` to remove by `(id, type)`

Currently `dequeue(operationId)` removes **all** operations for a given id. If a queue contains both `uploadSession(s-1)` and `deleteSession(s-1)`, a successful upload dequeues both — the delete is silently lost. This is the foundation that Tasks 2 and 3 depend on.

`dequeue` has no external callers (confirmed by grep): it is only called inside `processQueue` within `sync_queue_service.dart` itself.

**Files:**
- Modify: `lib/services/sync_queue_service.dart`
- Create: `test/services/sync_queue_service_test.dart`

- [ ] **Step 1.1 — Write the failing tests**

Create `test/services/sync_queue_service_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

class _FakePathProvider with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

SyncOperation _op(String id, String type) =>
    SyncOperation(id: id, type: type, data: {}, createdAt: DateTime.now());

void main() {
  late Directory tmpDir;
  late SyncQueueService queue;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('sq_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    queue = SyncQueueService();
    await queue.loadQueue();
  });

  tearDown(() => tmpDir.delete(recursive: true));

  group('SyncQueueService.dequeue', () {
    test('removes only the matching (id, type) pair', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));
      await queue.enqueue(_op('s-1', 'deleteSession'));
      expect(queue.pendingOperations.length, 2);

      await queue.dequeue('s-1', 'uploadSession');

      expect(queue.pendingOperations.length, 1);
      expect(queue.pendingOperations.first.type, 'deleteSession');
    });

    test('does not remove an op when only the type matches but id differs', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));
      await queue.enqueue(_op('s-2', 'uploadSession'));

      await queue.dequeue('s-1', 'uploadSession');

      expect(queue.pendingOperations.length, 1);
      expect(queue.pendingOperations.first.id, 's-2');
    });

    test('does nothing when no matching (id, type) pair exists', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));

      await queue.dequeue('s-1', 'deleteSession'); // type mismatch

      expect(queue.pendingOperations.length, 1);
    });
  });
}
```

- [ ] **Step 1.2 — Run tests to confirm they fail**

```bash
cd /Users/michiel/projects/flash_forward
flutter test test/services/sync_queue_service_test.dart
```

Expected: compilation error or test failure — `dequeue` currently takes one argument.

- [ ] **Step 1.3 — Update `dequeue` signature and its caller in `sync_queue_service.dart`**

In `lib/services/sync_queue_service.dart`, change:

```dart
// Before
Future<void> dequeue(String operationId) async {
  _queue.removeWhere((op) => op.id == operationId);
  await _saveQueue();
}
```

To:

```dart
// After
Future<void> dequeue(String operationId, String operationType) async {
  _queue.removeWhere(
      (op) => op.id == operationId && op.type == operationType);
  await _saveQueue();
}
```

In the same file, update the one internal call inside `processQueue`:

```dart
// Before
await dequeue(operation.id);

// After
await dequeue(operation.id, operation.type);
```

- [ ] **Step 1.4 — Run tests to confirm they pass**

```bash
flutter test test/services/sync_queue_service_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 1.5 — Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 1.6 — Commit**

```bash
git add lib/services/sync_queue_service.dart test/services/sync_queue_service_test.dart
git commit -m "fix: dequeue by (id, type) to avoid silently removing co-pending ops"
```

---

## Task 2: Add retry logic for `deleteWorkout` and `deleteExercise`

`deleteSession` already uses the try/catch + enqueue pattern. `deleteWorkout` and `deleteExercise` fire-and-forget with no retry. A failed delete silently drops cloud data. This task mirrors the existing `deleteSession` pattern exactly.

**Files:**
- Modify: `lib/services/supabase_sync_service.dart`

No new tests: the retry path requires Supabase to be available. Covered by manual acceptance criteria.

- [ ] **Step 2.1 — Add retry to `deleteWorkout`**

In `lib/services/supabase_sync_service.dart`, replace `deleteWorkout`:

```dart
// Before
Future<void> deleteWorkout(String workoutId) async {
  await supabase
      .from('user_workouts')
      .delete()
      .eq('id', workoutId)
      .eq('user_id', userId);
}

// After
Future<void> deleteWorkout(String workoutId, {bool isRetry = false}) async {
  try {
    await supabase
        .from('user_workouts')
        .delete()
        .eq('id', workoutId)
        .eq('user_id', userId);
  } catch (e) {
    if (!isRetry) {
      await _syncQueue.enqueue(SyncOperation(
        id: workoutId,
        type: 'deleteWorkout',
        data: {'workoutId': workoutId},
        createdAt: DateTime.now(),
      ));
    }
    rethrow;
  }
}
```

- [ ] **Step 2.2 — Add retry to `deleteExercise`**

Replace `deleteExercise`:

```dart
// Before
Future<void> deleteExercise(String exerciseId) async {
  await supabase
      .from('user_exercises')
      .delete()
      .eq('id', exerciseId)
      .eq('user_id', userId);
}

// After
Future<void> deleteExercise(String exerciseId, {bool isRetry = false}) async {
  try {
    await supabase
        .from('user_exercises')
        .delete()
        .eq('id', exerciseId)
        .eq('user_id', userId);
  } catch (e) {
    if (!isRetry) {
      await _syncQueue.enqueue(SyncOperation(
        id: exerciseId,
        type: 'deleteExercise',
        data: {'exerciseId': exerciseId},
        createdAt: DateTime.now(),
      ));
    }
    rethrow;
  }
}
```

- [ ] **Step 2.3 — Add `deleteWorkout` and `deleteExercise` cases to `processPendingSync`**

In `processPendingSync`, add before the `default` case:

```dart
case 'deleteWorkout':
  await deleteWorkout(
      operation.data['workoutId'] as String, isRetry: true);
  break;
case 'deleteExercise':
  await deleteExercise(
      operation.data['exerciseId'] as String, isRetry: true);
  break;
```

- [ ] **Step 2.4 — Run full test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 2.5 — Commit**

```bash
git add lib/services/supabase_sync_service.dart
git commit -m "fix: add retry-on-failure for deleteWorkout and deleteExercise"
```

---

## Task 3: Merge pending sync-queue items with cloud data on load

After loading from cloud, items that are in the local sync queue (pending upload) but absent from cloud results are appended. Items with a co-pending delete operation are excluded. Also awaits the sync queue's disk load before merging to close a startup race.

This task depends on Task 1 being shipped: Task 1 ensures that a successful upload no longer silently removes a co-pending delete, making the delete-exclusion logic in this task actually reachable.

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Create: `test/providers/preset_provider_merge_test.dart`

- [ ] **Step 3.1 — Write the failing tests**

Create `test/providers/preset_provider_merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

Session _session(String id) =>
    Session(id: id, title: 'T', label: 'push', workouts: []);

SyncOperation _uploadOp(Session s) => SyncOperation(
    id: s.id,
    type: 'uploadSession',
    data: s.toJson(),
    createdAt: DateTime.now());

SyncOperation _deleteOp(String id) => SyncOperation(
    id: id,
    type: 'deleteSession',
    data: {},
    createdAt: DateTime.now());

void main() {
  group('PresetProvider.mergeWithPendingOps', () {
    test('returns cloud items unchanged when queue is empty', () {
      final s = _session('cloud-1');
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [s],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [],
      );
      expect(result.map((s) => s.id).toList(), ['cloud-1']);
    });

    test('appends queued item not present in cloud', () {
      final local = _session('local-1');
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(local)],
      );
      expect(result.map((s) => s.id).toList(), ['local-1']);
    });

    test('does not duplicate item already in cloud', () {
      final s = _session('shared-1');
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [s],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(s)],
      );
      expect(result.length, 1);
    });

    test('ignores queued operations of a different type', () {
      final s = _session('del-1');
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });

    test('cloud item is preferred when same id is in both cloud and queue', () {
      final cloudVersion = _session('s-1');
      final queueVersion =
          Session(id: 's-1', title: 'Stale', label: 'push', workouts: []);
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [cloudVersion],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(queueVersion)],
      );
      expect(result.length, 1);
      expect(result.first.title, 'T'); // cloud version kept
    });

    test('does not re-add item when uploadSession and deleteSession are both pending', () {
      final s = _session('s-2');
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(s), _deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });
  });
}
```

- [ ] **Step 3.2 — Run tests to confirm they fail**

```bash
flutter test test/providers/preset_provider_merge_test.dart
```

Expected: compilation error — `mergeWithPendingOps` does not exist yet.

- [ ] **Step 3.3 — Add `mergeWithPendingOps` static method to `PresetProvider`**

Add inside the `PresetProvider` class body in `lib/providers/preset_provider.dart` (after `_loadUserPresetDataFromLocal`, before `deleteAllUserPresets`):

```dart
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
  return [...cloudItems, ...unsynced];
}
```

Ensure `SyncOperation` is imported (from `lib/services/sync_queue_service.dart`).

- [ ] **Step 3.4 — Await queue load before cloud load in `init()`**

`SupabaseSyncService` calls `_syncQueue.loadQueue()` fire-and-forget in its constructor (constructors cannot be async). Without an explicit await, `pendingOperations` may return `[]` at merge time.

In `lib/providers/preset_provider.dart` `init()`, replace:

```dart
_syncService = SupabaseSyncService(userId: userId);
await _loadUserPresetDataFromCloud();
```

With:

```dart
_syncService = SupabaseSyncService(userId: userId);
await _syncService!.syncQueue.loadQueue(); // ensure queue loaded before merge
await _loadUserPresetDataFromCloud();
```

`loadQueue()` is idempotent, so calling it twice is safe.

- [ ] **Step 3.5 — Update `_loadUserPresetDataFromCloud`**

Replace the current implementation with:

```dart
Future<void> _loadUserPresetDataFromCloud() async {
  if (_syncService == null) return;

  try {
    final cloudSessions = await _syncService!.fetchUserSessions();
    final cloudWorkouts = await _syncService!.fetchUserWorkouts();
    final cloudExercises = await _syncService!.fetchUserExercises();
    final pending = _syncService!.syncQueue.pendingOperations;

    _userSessions = mergeWithPendingOps(
      cloudItems: cloudSessions,
      getId: (s) => s.id,
      operationType: 'uploadSession',
      deleteOperationType: 'deleteSession',
      fromJson: Session.fromJson,
      pendingOps: pending,
    );
    _userWorkouts = mergeWithPendingOps(
      cloudItems: cloudWorkouts,
      getId: (w) => w.id,
      operationType: 'uploadWorkout',
      deleteOperationType: 'deleteWorkout',
      fromJson: Workout.fromJson,
      pendingOps: pending,
    );
    _userExercises = mergeWithPendingOps(
      cloudItems: cloudExercises,
      getId: (e) => e.id,
      operationType: 'uploadExercise',
      deleteOperationType: 'deleteExercise',
      fromJson: Exercise.fromJson,
      pendingOps: pending,
    );
  } catch (e, stackTrace) {
    Sentry.captureException(e, stackTrace: stackTrace);
    await _loadUserPresetDataFromLocal();
  }
}
```

- [ ] **Step 3.6 — Run tests to confirm they pass**

```bash
flutter test test/providers/preset_provider_merge_test.dart
```

Expected: all 6 tests pass.

- [ ] **Step 3.7 — Run full test suite**

```bash
flutter test
```

Expected: all tests pass, no regressions.

- [ ] **Step 3.8 — Commit**

```bash
git add lib/providers/preset_provider.dart test/providers/preset_provider_merge_test.dart
git commit -m "fix: merge pending sync-queue items with cloud data on load"
```

---

## Task 4: Diagnose and fix Supabase `user_sessions` upload failure

> ⚠️ **PREREQUISITE — Supabase schema info needed before implementing this task.**
> Run the diagnostics in Step 4.0, share the results, then apply the matching fix.

### Step 4.0 — Gather Supabase schema information

Run in the **Supabase SQL Editor** (Dashboard → SQL Editor → New Query):

```sql
-- Column definitions for both tables
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name IN ('user_sessions', 'user_workouts')
ORDER BY table_name, ordinal_position;

-- RLS enabled?
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('user_sessions', 'user_workouts');

-- RLS policies
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename IN ('user_sessions', 'user_workouts');
```

---

### Likely root cause A: Missing or wrong-type column on `user_sessions`

**Symptom:** `uploadSession` payload includes a `workouts` column (jsonb array), but the table may not have this column, or it may be typed differently from `user_workouts.exercises`.

**Fix:**

```sql
ALTER TABLE user_sessions
  ADD COLUMN IF NOT EXISTS workouts jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE user_sessions
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

ALTER TABLE user_sessions
  ALTER COLUMN created_at SET DEFAULT now();
```

---

### Likely root cause B: Missing RLS policy for `user_sessions`

**Symptom:** `user_workouts` has an INSERT/UPDATE policy for authenticated users but `user_sessions` does not.

**Fix — mirror the `user_workouts` policies exactly:**

```sql
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own sessions"
  ON user_sessions
  FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);
```

---

### Likely root cause C: `completed_at` NOT NULL constraint

**Symptom:** Preset sessions always have `completedAt: null`, but the table has a NOT NULL constraint on `completed_at`.

**Fix:**

```sql
ALTER TABLE user_sessions
  ALTER COLUMN completed_at DROP NOT NULL;
```

---

> **Note on migrations:** This project has no `supabase/migrations/` directory. Apply fixes directly via the Supabase SQL Editor or Dashboard.

- [ ] **Step 4.1 — Apply the relevant fix** (determined from Step 4.0 results)

- [ ] **Step 4.2 — Manually verify upload reaches cloud**

In the app (debug build), create a new preset session while connected. Hot restart. Verify the session is present. Then check the Supabase Table Editor for a matching row in `user_sessions` to confirm the session reached cloud (not just merged from the local queue).

- [ ] **Step 4.3 — Commit** (if a migration file was added)

```bash
git add supabase/  # only if you created a migrations folder
git commit -m "fix: correct user_sessions Supabase schema/RLS so uploadSession succeeds"
```

---

## Acceptance criteria

- [ ] Creating a preset session and hot-restarting shows the session in the list
- [ ] A session created while offline appears immediately and persists after reconnecting and syncing
- [ ] Deleting a session and hot-restarting does NOT show the deleted session
- [ ] A session created then immediately deleted (before any sync) does not reappear after restart
- [ ] Deleting a workout while offline queues the delete and retries on reconnect
- [ ] Creating a preset workout and hot-restarting continues to work
- [ ] All unit tests pass (`flutter test`)
