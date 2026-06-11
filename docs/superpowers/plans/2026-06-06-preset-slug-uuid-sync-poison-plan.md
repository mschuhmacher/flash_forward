# Preset slug ↔ uuid sync poison — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop preset *slug* ids from being written into `uuid` columns (which throws `22P02` and poisons the sync queue), make the queue resistant to permanently-failing ops, and unify deleted-defaults into one trash with a recency-based restore screen.

**Architecture:** Three independent phases that ship together. **Phase B** hardens the sync queue (discard + classify, no schema). **Phase A** forks stock defaults to UUIDs on first promotion/deletion, keying default-suppression on `templateId` so cloud writes are uuid-clean and a deleted default stays hidden durably (its non-purging trash entry is the record). **Phase C** is a one-time load heal (folded into A's load path). **Phase UX** reworks the Restore screen.

**Tech Stack:** Flutter / Dart, Provider, Supabase (`postgrest`), `sentry_flutter`, `uuid`. Tests: `flutter_test` run via `./scripts/run_tests.sh`.

**Spec:** `docs/superpowers/plans/2026-06-06-preset-slug-uuid-sync-poison.md`

**Conventions:**
- Run tests with `./scripts/run_tests.sh <path>` (NOT raw `flutter test` — keeps output small). Success prints `+N: All tests passed!`.
- Commit after each task. Branch is `refactor/preset-provider` (or a fresh `fix/preset-slug-uuid-poison`).
- The three models (`Session`, `Workout`, `Exercise`) already expose `deepCopy({bool keepId = false})` → `keepId:false` gives a fresh UUID and sets `templateId = templateId ?? id`. Reuse it; do not reinvent forking.

---

## File map

| File | Responsibility | Phase |
|------|----------------|-------|
| `lib/core/uuid.dart` *(new)* | `bool isUuid(String)` — shared by impl + tests | A0 |
| `test/support/catalog_test_kit.dart` *(new)* | `makeCatalog()` / `makeTrashProvider()` shared test setup | A0 |
| `lib/core/sync/sync_queue_service.dart` | `SyncOperation.attempts`; `processQueue` disposition (classify/discard/retry, Sentry-once); `dropNonUuidOps` | B/C |
| `lib/core/sync/sync_error_classifier.dart` *(new)* | Pure `SyncFailureKind classify(Object error)` → permanent vs transient | B |
| `lib/core/sync/supabase_sync_service.dart` | Retry handler **rethrows** instead of swallowing (lets `processQueue` classify) | B |
| `lib/models/trash_entry.dart` | `shadowId` getter (`templateId ?? id`) | A |
| `lib/features/catalog/catalog_provider.dart` | default-id helpers; fork-on-promote in `upsert*`; shadow getters key on `templateId`; heal-on-load | A/C |
| `lib/features/catalog/trash_provider.dart` | fork-on-delete-of-default in `deleteToTrash`; `shadowedDefaultIdsOf`; retention keeps default-derived entries | A |
| `lib/features/catalog/trash_service.dart` | `purgeOlderThan` skips default-derived entries | A |
| `lib/presentation/screens/profile_flow/restore_items_screen.dart` | recency list + "default" tag + collapsed Older + reset-to-factory | UX |

---

## Phase B — Sync queue poison-resistance

Independent of everything else. Lands the fix that actually silences Sentry.

### Task B1: Add a persisted `attempts` counter to `SyncOperation`

**Files:**
- Modify: `lib/core/sync/sync_queue_service.dart:27-53` (model), `:132-140` (enqueue carry-over)
- Test: `test/core/sync/sync_queue_service_test.dart`

- [ ] **Step 1: Write the failing test** — append to the existing file:

```dart
test('enqueue replacing an op carries the attempts counter over', () async {
  final svc = SyncQueueService();
  final op = SyncOperation(
    id: 'a', type: 'uploadSession', data: {'x': 1},
    createdAt: DateTime(2026), attempts: 3,
  );
  await svc.enqueue(op);
  // Re-enqueue same (id,type) with attempts 0 — must NOT reset to 0.
  await svc.enqueue(SyncOperation(
    id: 'a', type: 'uploadSession', data: {'x': 2},
    createdAt: DateTime(2026), attempts: 0,
  ));
  expect(svc.pendingOperations.single.attempts, 3);
  expect(svc.pendingOperations.single.data['x'], 2); // payload still refreshed
});

test('SyncOperation.fromJson defaults attempts to 0 when absent', () {
  final op = SyncOperation.fromJson({
    'id': 'a', 'type': 't', 'data': {}, 'createdAt': DateTime(2026).toIso8601String(),
  });
  expect(op.attempts, 0);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/run_tests.sh test/core/sync/sync_queue_service_test.dart`
Expected: FAIL — `attempts` is not a named parameter / getter.

- [ ] **Step 3: Implement** — add the field, serialize it, and carry it over on enqueue:

```dart
// SyncOperation: add field + constructor param
final int attempts;

SyncOperation({
  required this.id,
  required this.type,
  required this.data,
  required this.createdAt,
  this.attempts = 0,
});

// toJson: add 'attempts': attempts,
// fromJson: attempts: json['attempts'] as int? ?? 0,

SyncOperation copyWith({int? attempts, Map<String, dynamic>? data}) => SyncOperation(
  id: id, type: type, data: data ?? this.data,
  createdAt: createdAt, attempts: attempts ?? this.attempts,
);
```

In `enqueue`, preserve the prior attempts when replacing the same `(id, type)`:

```dart
Future<void> enqueue(SyncOperation operation) async {
  final existingIndex = _queue.indexWhere(
      (op) => op.id == operation.id && op.type == operation.type);
  final carried = existingIndex == -1
      ? operation
      : operation.copyWith(attempts: _queue[existingIndex].attempts);
  _queue.removeWhere(
      (op) => op.id == operation.id && op.type == operation.type);
  _queue.add(carried);
  await _saveQueue();
}
```

- [ ] **Step 4: Run to verify it passes** — `./scripts/run_tests.sh test/core/sync/sync_queue_service_test.dart` → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(sync): persist attempts counter on SyncOperation"`

### Task B2: Pure error classifier (permanent vs transient)

**Files:**
- Create: `lib/core/sync/sync_error_classifier.dart`
- Test: `test/core/sync/sync_error_classifier_test.dart` *(new)*

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flash_forward/core/sync/sync_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // re-exports PostgrestException

void main() {
  test('22P02 and 4xx are permanent', () {
    expect(classifySyncFailure(
      const PostgrestException(message: 'bad uuid', code: '22P02')),
      SyncFailureKind.permanent);
    expect(classifySyncFailure(
      const PostgrestException(message: 'bad', code: '400')),
      SyncFailureKind.permanent);
    expect(classifySyncFailure(
      const PostgrestException(message: 'unproc', code: '422')),
      SyncFailureKind.permanent);
  });

  test('network/timeout/5xx and unknown are transient', () {
    expect(classifySyncFailure(
      const PostgrestException(message: 'boom', code: '500')),
      SyncFailureKind.transient);
    expect(classifySyncFailure(Exception('SocketException: failed host lookup')),
      SyncFailureKind.transient);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `./scripts/run_tests.sh test/core/sync/sync_error_classifier_test.dart` → FAIL (file missing).

- [ ] **Step 3: Implement**

```dart
import 'package:supabase_flutter/supabase_flutter.dart'; // re-exports PostgrestException

enum SyncFailureKind { permanent, transient }

/// Permanent = the server rejected the *content* and will reject it forever
/// (malformed/invalid input, bad request, unprocessable). Retrying is pointless.
/// Everything else (network, timeout, 5xx, unknown) is transient → retry.
SyncFailureKind classifySyncFailure(Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    // Postgres SQLSTATE class 22/23 = data/integrity errors; HTTP 400/422.
    if (code == '22P02' || code == '400' || code == '422') {
      return SyncFailureKind.permanent;
    }
    if (code != null && code.startsWith('22')) return SyncFailureKind.permanent;
  }
  return SyncFailureKind.transient;
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(sync): add permanent/transient error classifier"`

### Task B3: `processQueue` disposition — discard, classify, Sentry-once

**Files:**
- Modify: `lib/core/sync/sync_queue_service.dart:198-235` (`processQueue`)
- Modify: `lib/core/sync/supabase_sync_service.dart:455-463` (retry handler must **rethrow**, not swallow)
- Test: `test/core/sync/sync_queue_service_test.dart`

**Behavior:** `processQueue`'s handler is expected to **throw** on failure (so the error reaches the classifier). On throw:
- **permanent** → dequeue (discard) + capture to Sentry once.
- **transient** → increment `attempts`; if `attempts + 1 >= maxAttempts` (default 5) → dequeue + capture once; else re-enqueue with incremented attempts (kept for next launch), **no** Sentry.

- [ ] **Step 1: Write failing tests** (use a fake handler that throws):

```dart
test('permanent failure is discarded on first attempt and reported once', () async {
  final svc = SyncQueueService();
  await svc.enqueue(SyncOperation(id: 'a', type: 'uploadSession', data: {},
      createdAt: DateTime(2026)));
  var calls = 0;
  await svc.processQueue((_) async {
    calls++;
    throw const PostgrestException(message: 'bad uuid', code: '22P02');
  });
  expect(svc.pendingCount, 0);      // discarded
  expect(calls, 1);
});

test('transient failure retries up to maxAttempts then discards', () async {
  final svc = SyncQueueService(maxAttempts: 3);
  await svc.enqueue(SyncOperation(id: 'a', type: 'uploadSession', data: {},
      createdAt: DateTime(2026)));
  Future<bool> fail(_) async => throw Exception('SocketException');
  await svc.processQueue(fail); // attempt 1 -> attempts=1, kept
  expect(svc.pendingCount, 1);
  expect(svc.pendingOperations.single.attempts, 1);
  await svc.processQueue(fail); // attempt 2 -> attempts=2, kept
  await svc.processQueue(fail); // attempt 3 -> hits cap, discarded
  expect(svc.pendingCount, 0);
});
```

> Note: `processQueue` short-circuits when `hasConnectivity()` is false. These tests run on the host where `Connectivity()` typically returns none. Add a constructor seam `SyncQueueService({this.maxAttempts = 5, Future<bool> Function()? connectivityOverride})` and use it in `hasConnectivity`; pass `connectivityOverride: () async => true` in the tests (wire it in Step 3).

- [ ] **Step 2: Run to verify it fails** → FAIL (`maxAttempts`/`connectivityOverride` unknown; ops not discarded).

- [ ] **Step 3: Implement** — add the seam and rewrite the catch:

```dart
final int maxAttempts;
final Future<bool> Function()? _connectivityOverride;

SyncQueueService({this.maxAttempts = 5, Future<bool> Function()? connectivityOverride})
    : _connectivityOverride = connectivityOverride;

Future<bool> hasConnectivity() async {
  if (_connectivityOverride != null) return _connectivityOverride!();
  // ...existing connectivity_plus check...
}
```

Rewrite the loop body. The handler contract becomes: **returns `true`** = success (dequeue); **returns `false`** = permanently un-handleable (discard + report once — this is what the `default:` unknown-op-type branch returns); **throws** = failure to classify.

```dart
for (final operation in queueCopy) {
  try {
    final success = await handler(operation);
    if (success) {
      await dequeue(operation.id, operation.type);
      successCount++;
    } else {
      // Handler explicitly can't process this op (e.g. unknown type) — never
      // retriable. Discard so it can't become an immortal poison op.
      await dequeue(operation.id, operation.type);
      Sentry.captureMessage('Discarded un-handleable sync op: ${operation.type}');
    }
  } catch (e, stackTrace) {
    final kind = classifySyncFailure(e);
    final willExhaust = kind == SyncFailureKind.permanent
        || operation.attempts + 1 >= maxAttempts;
    if (willExhaust) {
      await dequeue(operation.id, operation.type); // silent discard
      Sentry.captureException(e, stackTrace: stackTrace, withScope: (scope) {
        scope.setContexts('sync_op', {
          'type': operation.type, 'id': operation.id,
          'attempts': operation.attempts + 1, 'disposition': kind.name,
        });
      });
    } else {
      // transient, under cap: keep with incremented attempts, no Sentry.
      await enqueue(operation.copyWith(attempts: operation.attempts + 1));
    }
  }
}
```

Then make the retry handler **rethrow**. In `supabase_sync_service.dart` `processPendingSync`, remove the inner `try/catch` that does `Sentry.captureException(...) ; return false` (`:460-462`) so failures propagate to `processQueue`'s classifier. The handler should `return true` on success, **keep the `default:` branch returning `false`** (now discarded by the loop above, not retried forever), and let exceptions bubble.

Add a third test for the unknown-op discard:

```dart
test('unknown op type is discarded, not kept forever', () async {
  final svc = SyncQueueService(connectivityOverride: () async => true);
  await svc.enqueue(SyncOperation(id: 'a', type: 'bogusOp', data: {}, createdAt: DateTime(2026)));
  await svc.processQueue((_) async => false); // handler can't handle it
  expect(svc.pendingCount, 0);
});
```

- [ ] **Step 4: Run to verify it passes** — `./scripts/run_tests.sh test/core/sync/sync_queue_service_test.dart` → PASS. Then full suite: `./scripts/run_tests.sh` (watch for tests asserting old keep-on-failure behaviour; update them to the new disposition).
- [ ] **Step 5: Commit** — `git commit -am "feat(sync): discard poison ops with classify + Sentry-once; handler rethrows"`

---

## Phase A — Fork stock defaults to UUIDs; suppress by templateId

### Task A0: Test seams + shared test kit (do this first)

Phases A/C/UX tests need to inject user-list items and a temp-dir-backed trash. These seams don't exist yet — add them once here so later tasks just call them.

**Files:**
- Create: `lib/core/uuid.dart` (`bool isUuid(String s)` — single source of truth, reused by impl *and* test predicates)
- Modify: `lib/features/catalog/catalog_provider.dart` — add `@visibleForTesting debugSeedUserSessions/Workouts/Exercises` mirroring the existing `debugSeedDefaults({...})` at `:172`
- Modify: `lib/features/catalog/trash_provider.dart` — add an optional `TrashService` injection to the ctor (currently `final TrashService _trashService = TrashService();` is hardcoded):
  ```dart
  TrashProvider({required CatalogProvider catalog, required SyncStatusProvider syncStatus, TrashService? trashService})
      : _catalog = catalog, _syncStatus = syncStatus, _trashService = trashService ?? TrashService();
  final TrashService _trashService;
  ```
- Create: `test/support/catalog_test_kit.dart` — shared helpers used by every later task:
  ```dart
  // Registers a temp-dir _FakePathProvider (copy the one already in
  // test/features/catalog/catalog_provider_trash_filtering_test.dart:13-21),
  // builds a CatalogProvider seeded with the real kDefault* lists, and a
  // TrashProvider backed by a real TrashService writing into the temp dir
  // (so add()/readAll()/restore() round-trip on disk — restoreFromTrash works).
  Future<CatalogProvider> makeCatalog();              // CatalogProvider()..debugSeedDefaults(sessions: kDefaultSessions, ...)
  Future<TrashProvider> makeTrashProvider(CatalogProvider c); // TrashProvider(catalog: c, syncStatus: _FakeSync(), trashService: <temp-dir>) ; c.attachTrashProvider(...)
  ```
  Seed trash in tests via `await trash.deleteToTrash(...)` or `await trashService.add(entry); await trash.loadAndPurge();` so the on-disk file and in-memory `_trashedItems` agree — do **not** use `debugSeedTrash` (memory-only) for tests that then call `restoreFromTrash`, which reads the file.

- [ ] **Step 1:** Write `isUuid` + a trivial test (`isUuid('11111111-1111-4111-8111-111111111111')` true; `isUuid('projecting-session')` false). Run, fail, implement, pass.
- [ ] **Step 2:** Add the `debugSeedUserSessions/Workouts/Exercises` seams and the `TrashProvider` `trashService` param. No behavior change → covered by later tasks compiling.
- [ ] **Step 3:** Write `catalog_test_kit.dart`. Sanity test: `final c = await makeCatalog(); expect(c.presetSessions, isNotEmpty);`
- [ ] **Step 4:** Commit — `git commit -am "test: catalog/trash test kit + isUuid + user-list seams"`

### Task A1: Default-id helpers on `CatalogProvider`

**Files:**
- Modify: `lib/features/catalog/catalog_provider.dart` (near `:110-112`)
- Test: `test/features/catalog/catalog_provider_promote_default_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('isDefaultSessionId is true only for stock default slugs', () {
  final c = CatalogProvider()..debugSeedDefaults(sessions: kDefaultSessions);
  expect(c.isDefaultSessionId('projecting-session'), isTrue);
  expect(c.isDefaultSessionId('11111111-1111-4111-8111-111111111111'), isFalse);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL.
- [ ] **Step 3: Implement** — expose membership over the seeded default lists:

```dart
Set<String> get _defaultSessionIds => _defaultSessions.map((s) => s.id).toSet();
Set<String> get _defaultWorkoutIds => _defaultWorkouts.map((w) => w.id).toSet();
Set<String> get _defaultExerciseIds => _defaultExercises.map((e) => e.id).toSet();

bool isDefaultSessionId(String id) => _defaultSessionIds.contains(id);
bool isDefaultWorkoutId(String id) => _defaultWorkoutIds.contains(id);
bool isDefaultExerciseId(String id) => _defaultExerciseIds.contains(id);
```

- [ ] **Step 4: Run to verify it passes** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(catalog): default-id membership helpers"`

### Task A2: Fork-on-promote in `upsertSession/Workout/Exercise`

**Files:**
- Modify: `lib/features/catalog/catalog_provider.dart:216-234` (and the workout/exercise twins)
- Test: `test/features/catalog/catalog_provider_promote_default_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('upserting a stock default forks it to a UUID with templateId=slug', () async {
  final c = makeCatalog(); // existing test helper
  final stock = kDefaultSessions.firstWhere((s) => s.id == 'projecting-session');
  await c.upsertSession(stock.copyWith(title: 'My Projecting'));

  final saved = c.presetSessions.firstWhere((s) => s.title == 'My Projecting');
  expect(saved.id, isNot('projecting-session'));     // forked
  expect(_isUuid(saved.id), isTrue);
  expect(saved.templateId, 'projecting-session');    // breadcrumb
});

test('upserting an already-forked item is idempotent (no re-fork)', () async {
  final c = makeCatalog();
  final forked = kDefaultSessions.first.deepCopy(keepId: false); // uuid + templateId
  await c.upsertSession(forked);
  await c.upsertSession(forked.copyWith(title: 'x'));
  expect(c.presetSessions.where((s) => s.templateId == forked.templateId).length, 1);
  expect(c.presetSessions.firstWhere((s) => s.id == forked.id).id, forked.id);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL (slug kept).
- [ ] **Step 3: Implement** — fork only when the incoming id is a stock default slug:

```dart
Future<void> upsertSession(Session session) async {
  final toSave = isDefaultSessionId(session.id)
      ? session.deepCopy(keepId: false) // fresh UUID, templateId = slug
      : session;
  await SyncedItemOps.upsert<Session>(
    list: _userSessions, item: toSave, getId: (s) => s.id,
    saveLocal: () => PresetLogger.savePresetToFile('user_preset_sessions.json', _userSessions),
    cloudOp: _syncStatus?.service == null ? null : (s) => _syncStatus!.service!.uploadSession(s),
    onCloudError: (e, st) => Sentry.captureException(e, stackTrace: st),
  );
  notifyListeners();
}
```

Mirror in `upsertWorkout` (use `isDefaultWorkoutId`) and `upsertExercise` (`isDefaultExerciseId`). **Check the propagation caller at `:482`** (`upsertSession(session.copyWith(workouts: …))`) — it now forks too, which is correct; confirm its test still asserts shadowing by templateId (updated in A4), not by slug id.

- [ ] **Step 4: Run to verify it passes** → PASS. Run `./scripts/run_tests.sh test/features/catalog/` and fix any propagate-test that assumed same-id promotion.
- [ ] **Step 5: Commit** — `git commit -am "feat(catalog): fork stock defaults to UUID on promote"`

### Task A3: Fork-on-delete-of-a-default in `deleteToTrash`

**Files:**
- Modify: `lib/features/catalog/trash_provider.dart:149-203`
- Test: `test/features/catalog/trash_provider_test.dart`

A never-customized default deleted today is trashed at its slug id. Fork it so the trash entry is uuid-clean and carries `templateId = slug`.

- [ ] **Step 1: Write the failing test**

```dart
test('deleting a never-customized default trashes a UUID-bearing fork', () async {
  final tp = makeTrashProvider(); // with catalog seeded with defaults
  await tp.deleteToTrash(id: 'projecting-session', kind: TrashKind.session);
  final entry = tp.trashedItems.single;
  expect(_isUuid(entry.id), isTrue);
  expect((entry.payload as Session).templateId, 'projecting-session');
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL (entry.id == slug).
- [ ] **Step 3: Implement** — in each `case` of `deleteToTrash`, fork `src` when it is a stock default before building the entry. E.g. for sessions:

```dart
var src = _catalog.presetSessions.firstWhere((s) => s.id == id, orElse: ...);
if (_catalog.isDefaultSessionId(src.id)) {
  src = src.deepCopy(keepId: false); // uuid + templateId = slug
}
await _catalog.removeSessionLocal(id);
entry = TrashEntry.session(session: src, deletedAt: now);
```

Mirror for workout/exercise. (The subsequent `service.deleteSession(id)` still uses the original slug `id` — harmless: deleting a non-existent uuid row is a no-op; and there was never a slug row in the cloud.)

- [ ] **Step 4: Update the pre-existing test this breaks.** `test/features/catalog/catalog_provider_trash_filtering_test.dart` (`'trashed default workout is removed from presetWorkouts on delete'`, ~line 162-174) asserts `trash.trashedItems.single.id == 'def-w'`. After fork-on-delete the id is a fresh UUID, so change that line to:
  ```dart
  expect(isUuid(trash.trashedItems.single.id), isTrue);
  expect((trash.trashedItems.single.payload as Workout).templateId, 'def-w');
  ```
- [ ] **Step 5: Run to verify** — `./scripts/run_tests.sh test/features/catalog/` → PASS.
- [ ] **Step 6: Commit** — `git commit -am "feat(trash): fork stock defaults to UUID when deleting to trash"`

### Task A4: Suppress defaults by `templateId` (shadow getters + trash helper)

**Files:**
- Modify: `lib/models/trash_entry.dart` (add `shadowId`)
- Modify: `lib/features/catalog/trash_provider.dart` (add `shadowedDefaultIdsOf`)
- Modify: `lib/features/catalog/catalog_provider.dart:53-85` (three shadow getters)
- Test: `test/features/catalog/catalog_provider_trash_filtering_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('a forked default override shadows the stock default', () {
  final c = makeCatalog();
  final forked = kDefaultSessions
      .firstWhere((s) => s.id == 'projecting-session')
      .deepCopy(keepId: false); // templateId = projecting-session
  c.debugSeedUserSessions([forked]);
  final ids = c.presetSessions.map((s) => s.id).toList();
  expect(ids, contains(forked.id));
  expect(ids, isNot(contains('projecting-session'))); // stock hidden
});

test('a trashed forked default keeps the stock default hidden', () {
  final c = makeCatalog();
  final forked = kDefaultSessions.first.deepCopy(keepId: false);
  trash.debugSeedTrash([TrashEntry.session(session: forked, deletedAt: DateTime(2026))]);
  expect(c.presetSessions.any((s) => s.id == forked.templateId), isFalse);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL.
- [ ] **Step 3: Implement.**

`TrashEntry`:
```dart
String get shadowId => switch (kind) {
  TrashKind.session  => (payload as Session).templateId  ?? (payload as Session).id,
  TrashKind.workout  => (payload as Workout).templateId  ?? (payload as Workout).id,
  TrashKind.exercise => (payload as Exercise).templateId ?? (payload as Exercise).id,
};
```

`TrashProvider`:
```dart
Set<String> shadowedDefaultIdsOf(TrashKind kind) =>
    _trashedItems.where((e) => e.kind == kind).map((e) => e.shadowId).toSet();
```

`CatalogProvider.presetSessions` (mirror for workouts/exercises):
```dart
List<Session> get presetSessions {
  final trashedIds = _trash?.trashedIdsOf(TrashKind.session) ?? const <String>{};
  final shadowedDefaultIds = <String>{
    ..._userSessions.map((s) => s.templateId ?? s.id),
    ...?_trash?.shadowedDefaultIdsOf(TrashKind.session),
  };
  return [
    ..._defaultSessions.where((s) => !shadowedDefaultIds.contains(s.id)),
    ..._userSessions.where((s) => !trashedIds.contains(s.id)),
  ];
}
```

- [ ] **Step 4: Run to verify it passes** → PASS. Run `./scripts/run_tests.sh test/features/catalog/` — update any pre-existing shadow tests that asserted same-id suppression.
- [ ] **Step 5: Commit** — `git commit -am "feat(catalog): suppress defaults by templateId incl. trashed forks"`

### Task A5: Retention by origin — default-derived trash entries never purge

**Files:**
- Modify: `lib/features/catalog/trash_service.dart:42-50` (`purgeOlderThan`)
- Test: `test/features/catalog/trash_service_test.dart`

A default-derived entry (one whose payload has a non-null `templateId`, i.e. it forked a default) must survive past 90 days.

- [ ] **Step 1: Write the failing test**

```dart
test('purgeOlderThan keeps default-derived entries regardless of age', () async {
  final svc = TrashService();
  final old = DateTime(2020); // way past 90d
  final userItem = TrashEntry.session(session: Session(title:'u',label:'l',workouts:[]), deletedAt: old);
  final forkedDefault = TrashEntry.session(
    session: kDefaultSessions.first.deepCopy(keepId:false), deletedAt: old);
  await svc.debugSeed([userItem, forkedDefault]); // add a test seam or write file
  final purged = await svc.purgeOlderThan(const Duration(days: 90));
  expect(purged, contains(userItem.id));        // user item gone
  expect(purged, isNot(contains(forkedDefault.id))); // default kept
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL (both purged).
- [ ] **Step 3: Implement** — exempt entries whose payload carries a `templateId` (use `shadowId != id` as the "is a fork of a default" test, since fork-on-* always sets templateId):

```dart
bool _isDefaultDerived(TrashEntry e) => e.shadowId != e.id; // templateId set
// in purgeOlderThan:
final purged = entries
    .where((e) => e.deletedAt.isBefore(cutoff) && !_isDefaultDerived(e))
    .toList();
entries.removeWhere((e) => e.deletedAt.isBefore(cutoff) && !_isDefaultDerived(e));
```

- [ ] **Step 4: Run to verify it passes** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(trash): never auto-purge default-derived entries"`

---

## Phase C — One-time heal on load (folded into A's load path)

### Task C1: Re-id slug-id user items and drop non-uuid poison ops

**Files:**
- Modify: `lib/features/catalog/catalog_provider.dart` (`init`/`refreshAfterSignIn` after lists load, `:120-135` / `:159-161`)
- Add: a `dropNonUuidOps()` to `SyncQueueService`
- Test: `test/features/catalog/catalog_provider_promote_default_test.dart`, `test/core/sync/sync_queue_service_test.dart`

Existing devices carry customized defaults in local JSON at slug ids (their uploads always failed) plus the matching poison op. On load: re-id those user items to UUID + `templateId = oldId`, and drop queue ops whose payload id isn't a UUID.

- [ ] **Step 1: Write failing tests**

```dart
// catalog
test('heal re-ids slug-id user items to uuid + templateId', () async {
  final c = makeCatalog();
  c.debugSeedUserSessions([
    Session(id: 'projecting-session', title: 'Customized', label: 'l', workouts: []),
  ]);
  await c.healSlugIdUserItems();
  final s = c.presetSessions.firstWhere((s) => s.title == 'Customized');
  expect(_isUuid(s.id), isTrue);
  expect(s.templateId, 'projecting-session');
});

// queue
test('dropNonUuidOps removes ops whose entity id is not a uuid', () async {
  final svc = SyncQueueService();
  await svc.enqueue(SyncOperation(id: 'projecting-session', type: 'uploadSession', data: {}, createdAt: DateTime(2026)));
  await svc.enqueue(SyncOperation(id: '11111111-1111-4111-8111-111111111111', type: 'uploadSession', data: {}, createdAt: DateTime(2026)));
  await svc.dropNonUuidOps();
  expect(svc.pendingOperations.map((o) => o.id), ['11111111-1111-4111-8111-111111111111']);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL.
- [ ] **Step 3: Implement.**

`SyncQueueService` (reuse `isUuid` from `lib/core/uuid.dart`, created in A0):
```dart
Future<void> dropNonUuidOps() async {
  _queue.removeWhere((op) => !isUuid(op.id));
  await _saveQueue();
}
```

`CatalogProvider.healSlugIdUserItems()` — for each user list, replace any item whose id isn't a UUID (`!isUuid(item.id)`) with `item.deepCopy(keepId: false)` (fresh uuid, templateId = old id), then `saveLocal`. Call it in `init`/`refreshAfterSignIn` right after the user lists are populated and before `trash.selfHeal…`, and call `service.syncQueue.dropNonUuidOps()` when a service exists.

- [ ] **Step 4: Run to verify it passes** → PASS. Full suite green: `./scripts/run_tests.sh`.
- [ ] **Step 5: Commit** — `git commit -am "feat(catalog): heal slug-id user items and drop poison ops on load"`

---

## Phase UX — Restore screen rework

### Task U1: Catalog/trash data for the restore screen

**Files:**
- Modify: `lib/features/catalog/trash_provider.dart` (recency-sorted view + default flag)
- Test: `test/features/catalog/trash_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('entriesByRecency sorts newest-first and flags defaults', () {
  final tp = makeTrashProvider();
  final userE = TrashEntry.session(session: Session(title:'u',label:'l',workouts:[]), deletedAt: DateTime(2026,6,1));
  final defE  = TrashEntry.session(session: kDefaultSessions.first.deepCopy(keepId:false), deletedAt: DateTime(2026,6,5));
  tp.debugSeedTrash([userE, defE]);
  final view = tp.entriesByRecency;
  expect(view.first.entry.id, defE.id);     // newest first
  expect(view.first.isDefault, isTrue);
  expect(view.last.isDefault, isFalse);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL.
- [ ] **Step 3: Implement** — a small view-model + getters:

```dart
class RestorableEntry {
  RestorableEntry(this.entry, this.isDefault);
  final TrashEntry entry;
  final bool isDefault;
}

List<RestorableEntry> get entriesByRecency {
  final list = _trashedItems
      .map((e) => RestorableEntry(e, e.shadowId != e.id))
      .toList()
    ..sort((a, b) => b.entry.deletedAt.compareTo(a.entry.deletedAt));
  return list;
}

/// All deleted defaults (any age) — for "Restore all defaults".
List<TrashEntry> get deletedDefaults =>
    _trashedItems.where((e) => e.shadowId != e.id).toList();
```

- [ ] **Step 4: Run to verify it passes** → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(trash): recency view + default flag for restore screen"`

### Task U2: RestoreItemsScreen — recency list, Older section, reset-to-factory

**Files:**
- Modify: `lib/presentation/screens/profile_flow/restore_items_screen.dart`
- Test: `test/features/catalog/trash_provider_test.dart` (a "restore all defaults" provider test); widget test optional.

UI behaviour (build on the existing multi-select list):
- Render `trash.entriesByRecency`. Items with `isDefault` get a small **"default"** chip.
- Split at 90 days: entries with `deletedAt` older than `DateTime.now() - 90d` go under a **collapsed** "Older" `ExpansionTile` (they are necessarily defaults). Recent entries render in the main list.
- At the foot of the expanded "Older" tile, a low-emphasis **"Restore all defaults"** `TextButton` → confirm dialog → `trash.restoreAllDefaults()`.
- Individual restore stays `restoreFromTrash(id)` (unchanged; idempotent because the fork already has a UUID).

- [ ] **Step 1: Write the failing provider test**

```dart
test('restoreAllDefaults restores every deleted default, recent and old', () async {
  final tp = makeTrashProvider();
  final recent = TrashEntry.session(session: kDefaultSessions[0].deepCopy(keepId:false), deletedAt: DateTime.now());
  final old    = TrashEntry.session(session: kDefaultSessions[1].deepCopy(keepId:false), deletedAt: DateTime(2020));
  tp.debugSeedTrash([recent, old]);
  await tp.restoreAllDefaults();
  expect(tp.trashedItems, isEmpty);
});
```

- [ ] **Step 2: Run to verify it fails** → FAIL (`restoreAllDefaults` missing).
- [ ] **Step 3: Implement** `restoreAllDefaults` on `TrashProvider` (loop `deletedDefaults`, call existing `restoreFromTrash`), then wire the screen widgets (chips, `ExpansionTile`, button + `AlertDialog`). Keep the existing collision-handling path for individual restores.

- [ ] **Step 4: Run to verify it passes** → PASS. Manually verify with `/run` or the verify skill: delete a default, confirm it leaves the catalog and appears (tagged) in Restore items; restore it; confirm it returns.
- [ ] **Step 5: Commit** — `git commit -am "feat(restore): recency list, Older defaults section, reset-to-factory"`

---

## Final verification

- [ ] `./scripts/run_tests.sh` — whole suite green.
- [ ] Manual smoke (verify skill): (a) customize a default → it syncs (no `22P02` in logs); (b) delete a default → gone from catalog, tagged in Restore items, no pop-back; (c) restore it → returns; (d) with a seeded poison op, launch once → op gone, no repeating Sentry event.
- [ ] Confirm no Supabase schema migration was needed (reuses `trash_entries`; `dismissed_defaults` table is NOT created — the unified-trash model replaced it).
