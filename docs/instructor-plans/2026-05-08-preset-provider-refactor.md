# Instructor Plan — PresetProvider Refactor

> **Source plan:** [docs/superpowers/plans/2026-05-08-preset-provider-refactor.md](../superpowers/plans/2026-05-08-preset-provider-refactor.md)
>
> **Goal:** Split [lib/providers/preset_provider.dart](../../lib/providers/preset_provider.dart) (1,187 LOC) into focused units — `CatalogProvider`, `TrashProvider`, `EditCommitController`, `SyncStatusProvider` — with three helpers (`PresetSyncMerger`, `PresetLoader`, `SyncedItemOps`). Add `refreshAfterSignIn` seam on Catalog and Trash for the upcoming demo-before-signin feature.
>
> **Help levels:** Each task starts in **default mode** (Why/What/Details, Socratic chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate for the current task only. Reset to default on the next task.
>
> **Test discipline:** Every task ends with `scripts/run_tests.sh` returning green before you say "done." If a migrated test fails, the migration is wrong — not the test.

---

## Task Summary

| # | Status | Title |
|---|--------|-------|
| 1 | `[ ]` | Extract `PresetSyncMerger.mergeWithPendingOps` |
| 2 | `[ ]` | Add `mergeTrashCloudAndLocal` to `PresetSyncMerger` |
| 3 | `[ ]` | Extract `PresetLoader` |
| 4 | `[ ]` | Introduce `SyncedItemOps` and migrate `PresetProvider`'s CRUD (⚡ first-of-12) |
| 5 | `[ ]` | Introduce `SyncStatusProvider` |
| 6 | `[ ]` | Add catalog mutation surface for trash (prep for `TrashProvider`) |
| 7 | `[ ]` | Implement `TrashProvider` (file + stub test) |
| 8 | `[ ]` | Wire `TrashProvider` into `MultiProvider` and `init` |
| 9 | `[ ]` | Remove trash logic from `PresetProvider`, split trash test |
| 10 | `[ ]` | Caller-wires `init`: drop `userId`, add `refreshAfterSignIn` |
| 11 | `[ ]` | Extract `EditCommitController` (⚡ first-of-3 edit screens) |
| 12 | `[ ]` | Rename `PresetProvider` → `CatalogProvider` (⚡ first-of-15 call sites) |
| 13 | `[ ]` | Update `restore_items_screen.dart` to use both providers |
| 14 | `[ ]` | Final sweep — analyzer, grep, smoke walk |

---

## Forward-looking context

Two features are queued behind this refactor:

1. **Demo-before-signin** — the app will boot into the catalog without auth context; sign-in happens later via a new seam.
2. **Paywalling/subscription** — a new gating provider will sit alongside `SyncStatusProvider`.

This shapes two decisions baked into Tasks 7 and 10:
- **Caller-wires `init`.** The auth-screen caller does the `SyncStatusProvider.attach` step explicitly. Demo mode is "no attach" — `init` falls through to local naturally.
- **`refreshAfterSignIn()` seam.** Both `CatalogProvider` and `TrashProvider` get a method that reloads cloud state into an already-initialised provider. Not exercised by existing UI; the demo-before-signin feature plan will hook into it.

---

## Locked design decisions (don't revisit mid-execution)

1. **Public API style breaks.** Call sites are migrated to read the narrower provider. No facade kept.
2. **Single shared `SupabaseSyncService`** instance, owned by `SyncStatusProvider`. `CatalogProvider` and `TrashProvider` read it via attachment.
3. **`TrashProvider` depends on `CatalogProvider`** via `ChangeNotifierProxyProvider2`. The reactive seam for UI that wants both is `Listenable.merge([catalog, trash])`.
4. **Behavior preservation is the gate.** `scripts/run_tests.sh` must pass after every task commit.
5. **Static helper signatures unchanged.** `mergeWithPendingOps` and `mergeTrashCloudAndLocal` keep their signatures when moved so migrated tests change minimally.
6. **`@visibleForTesting` debug seeders** (`debugSeedDefaults`, `debugSeedTrash`) stay on the new providers — 5 of the 6 existing test files depend on them.
7. **No behavior changes to error handling.** Every cloud upload/delete stays wrapped in `try/catch` with `Sentry.captureException`.
8. **No backwards-compatibility shims.** When `preset_provider.dart` is deleted, all imports migrate in the same task.
9. **Caller-wires `init`.** `CatalogProvider.init()` will not take `userId` (Task 10).
10. **`refreshAfterSignIn` is the post-init reload seam** (Task 10).

---

## [ ] Task 1 of 14: Extract `PresetSyncMerger.mergeWithPendingOps`

**Why:** The static merge logic is pure and already has its own test file. Moving it out first sets up the helper for Task 2 and reduces `preset_provider.dart`'s surface area with zero risk to behavior.

**What (overview):** A new `PresetSyncMerger` class exists with the static `mergeWithPendingOps<T>` method. `PresetProvider` no longer defines this method — it imports the helper and delegates. The migrated test file passes against the new class.

**Details:**
- New file: `lib/providers/preset_sync_merger.dart`. Class is named `PresetSyncMerger` with a private constructor (`PresetSyncMerger._()`). Method `mergeWithPendingOps` is a `static` with the same signature it has on `PresetProvider` now.
- The merge logic is a verbatim move. Do not change semantics. The doc comment about `fromJson` receiving the local-queue's camelCase JSON (not the Supabase column mapping) must be preserved — it's load-bearing.
- Test migration: `git mv test/providers/preset_provider_merge_test.dart test/providers/preset_sync_merger_test.dart`. Update the import, the `group()` description, and each `PresetProvider.mergeWithPendingOps<` call. ~7 call-site updates expected in the test.
- After migration, the three internal call sites in `_loadUserPresetDataFromCloud` (one each for sessions/workouts/exercises) should call `PresetSyncMerger.mergeWithPendingOps(...)`.
- `scripts/run_tests.sh` is green before you say done.

**Files:**
- Create: `lib/providers/preset_sync_merger.dart`
- Rename + modify: `test/providers/preset_provider_merge_test.dart` → `test/providers/preset_sync_merger_test.dart`
- Modify: `lib/providers/preset_provider.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 2 of 14: Add `mergeTrashCloudAndLocal` to `PresetSyncMerger`

**Why:** The second pure static helper. Moving it now keeps all the "merge by id with conflict resolution" logic in one place before any stateful code moves.

**What (overview):** `PresetSyncMerger` exposes `mergeTrashCloudAndLocal` as a public static method. `PresetProvider` no longer has `_mergeTrashCloudAndLocal` or the `mergeTrashCloudAndLocalForTest` `@visibleForTesting` shim. The internal call site in `_loadAndPurgeTrash` and the three test call sites are updated to use the helper directly.

**Details:**
- Add `mergeTrashCloudAndLocal(List<TrashEntry> local, List<TrashEntry> cloud)` as a static method on `PresetSyncMerger`. Verbatim move of `_mergeTrashCloudAndLocal`. Conflict resolution is last-write-wins by `deletedAt`.
- Add the `package:flash_forward/models/trash_entry.dart` import to the helper file.
- The `mergeTrashCloudAndLocalForTest` shim is deleted, not migrated — call sites in `preset_provider_trash_test.dart` move directly to `PresetSyncMerger.mergeTrashCloudAndLocal(...)`. There are three such call sites in the test.
- The test file is *not* renamed in this task — it still covers trash *and* will be split in Task 9. For now just update the three lines that call `mergeTrashCloudAndLocalForTest`.
- `scripts/run_tests.sh` is green before you say done.

**Files:**
- Modify: `lib/providers/preset_sync_merger.dart`
- Modify: `lib/providers/preset_provider.dart`
- Modify: `test/providers/preset_provider_trash_test.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 3 of 14: Extract `PresetLoader`

**Why:** Loading is the second pure helper. Today `_loadUserPresetDataFromCloud` and `_loadUserPresetDataFromLocal` are private methods on `PresetProvider`, only called from `init`. Lifting them out (1) decouples `init` from `SupabaseSyncService` internals, (2) creates a reusable load step that `refreshAfterSignIn` will call in Task 10, and (3) makes the loader unit-testable.

**What (overview):** A new `PresetLoader` class with two static methods (`loadFromCloud`, `loadFromLocal`) returns a `PresetLoaderResult` containing the three lists (sessions, workouts, exercises). `PresetProvider.init` calls the loader and assigns the result; the two private load methods are gone.

**Details:**
- New file: `lib/providers/preset_loader.dart`. Class `PresetLoader` with private constructor.
- New value class: `PresetLoaderResult` with three required fields (`sessions: List<Session>`, `workouts: List<Workout>`, `exercises: List<Exercise>`). Constructor takes them as named parameters.
- `loadFromCloud(SupabaseSyncService syncService)` is `async`, returns `Future<PresetLoaderResult>`. It fetches the three cloud lists, reads `syncService.syncQueue.pendingOperations`, and merges each list via `PresetSyncMerger.mergeWithPendingOps`. The caller is responsible for calling `loadQueue()` first.
- `loadFromLocal()` is `async`, returns `Future<PresetLoaderResult>`. Reads each user JSON file via `PresetLogger`.
- The three pendingOps operation/delete type strings (e.g. `'uploadSession'`/`'deleteSession'`) stay verbatim — they're load-bearing for queue matching.
- New test file: `test/providers/preset_loader_test.dart`. A single test asserts `PresetLoaderResult` exposes the three lists from its constructor. Deeper behavior is covered indirectly by the existing `preset_provider_promote_default_test.dart` and friends which call `init()`. Don't try to unit-test `loadFromCloud` — mocking Supabase is out of scope.
- In `PresetProvider.init`, the cloud branch becomes: `await _syncService!.syncQueue.loadQueue();` then `try { final loaded = await PresetLoader.loadFromCloud(_syncService!); _userSessions = loaded.sessions; ... } catch (...) { Sentry...; final fallback = await PresetLoader.loadFromLocal(); _userSessions = fallback.sessions; ... }`. The local branch becomes a single `PresetLoader.loadFromLocal()` call with assignment.
- For this task only, `init` still takes `userId` — Task 10 is where the API changes.
- `scripts/run_tests.sh` is green before you say done. Pay special attention to `preset_provider_promote_default_test.dart` and `preset_provider_propagate_test.dart` — they're the indirect exercisers of `init`.

**Files:**
- Create: `lib/providers/preset_loader.dart`
- Create: `test/providers/preset_loader_test.dart`
- Modify: `lib/providers/preset_provider.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 4 of 14: Introduce `SyncedItemOps` and migrate `PresetProvider`'s CRUD

**Why:** The 12 add/update/delete methods in `PresetProvider` follow an identical 4-step recipe (mutate list → save JSON → cloud op + Sentry → notify). Collapsing them into one generic helper removes ~200 LOC of boilerplate and gives the new providers (Tasks 5–9) a cleaner shape to inherit.

**What (overview):** A new `SyncedItemOps` helper has two static methods (`upsert<T>`, `removeById<T>`). The first add/update/delete method in `PresetProvider` is migrated to use them. After review, the remaining 11 methods are migrated by the instructor.

⚡ **First of 12 — do this one yourself. Claude handles the remaining 11 after your first migration passes review.**

**Details:**
- New file: `lib/providers/synced_item_ops.dart`. Class `SyncedItemOps` with a private constructor. No Flutter import — keep it framework-free.
- `upsert<T>` signature (named parameters): `list: List<T>`, `item: T`, `getId: String Function(T)`, `saveLocal: Future<void> Function()`, `cloudOp: Future<void> Function(T)?`, `onCloudError: void Function(Object, StackTrace)?`. Returns `Future<void>`.
  - Behaviour: if `getId(item)` matches an existing list entry, replace it in place; otherwise append. Then await `saveLocal()`. If `cloudOp` non-null, await it inside `try/catch`; on catch, call `onCloudError` if provided. **`saveLocal` errors propagate; `cloudOp` errors are swallowed after `onCloudError`.** This mirrors today's "best-effort cloud, strict local" semantics.
- `removeById<T>` signature: `list`, `id: String`, `getId`, `saveLocal`, `cloudOp: Future<void> Function()?` (note: no item argument — delete is by id), `onCloudError`. Behaviour: remove all matching entries from `list`, then `saveLocal` + optional `cloudOp` with the same error semantics.
- The helper does NOT call `notifyListeners` — the caller does that after the future completes. Keeps the helper free of Flutter.
- New test file: `test/providers/synced_item_ops_test.dart`. Five tests covering: upsert adds new, upsert replaces in place, removeById removes, upsert swallows cloud errors and forwards to `onCloudError`, removeById propagates saveLocal errors. Use a simple in-test `_Item` class with `id` and `value` to avoid pulling in app models.
- Choose **one** method in `PresetProvider` to migrate first — pick `addPresetSession` (the simplest add). The migrated method passes `_userSessions` as `list`, `session` as `item`, `(s) => s.id` as `getId`, the existing `PresetLogger.savePresetToFile('user_preset_sessions.json', _userSessions)` invocation as `saveLocal`, `_syncService == null ? null : (s) => _syncService!.uploadSession(s)` as `cloudOp`, and `Sentry.captureException` as `onCloudError`. After the helper call, `notifyListeners()`.
- External method name stays the same (`addPresetSession`) — name changes happen in Task 12.
- `scripts/run_tests.sh` is green before you say done. The 5 existing PresetProvider test files exercise add/update/delete paths heavily — any failure means the helper's semantics drift from the inlined original.

**Files:**
- Create: `lib/providers/synced_item_ops.dart`
- Create: `test/providers/synced_item_ops_test.dart`
- Modify: `lib/providers/preset_provider.dart` (one method only — the rest happens after review)

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 5 of 14: Introduce `SyncStatusProvider`

**Why:** Three sync-status passthroughs (`hasPendingSync`, `pendingSyncCount`, `processPendingSync`) currently live on both `PresetProvider` and `SessionLogProvider`. Extracting them into a shared provider sets up the chain where one `SupabaseSyncService` is owned centrally — the shape the demo-before-signin feature needs.

**What (overview):** A new `SyncStatusProvider extends ChangeNotifier` exists with `attach(SupabaseSyncService)`, `detach()`, `service` getter, `hasPendingSync`/`pendingSyncCount` passthroughs, and `processPendingSync()`. `PresetProvider` is NOT modified in this task — the wiring happens in Task 10.

**Details:**
- New file: `lib/providers/sync_status_provider.dart`.
- Single nullable field `_service: SupabaseSyncService?`. Public `service` getter returns it.
- `attach(service)` sets the field and notifies. `detach()` clears it and notifies.
- `hasPendingSync` returns `_service?.hasPendingSync ?? false`. `pendingSyncCount` returns `_service?.pendingSyncCount ?? 0`.
- `processPendingSync()` returns `Future<int>`. When `_service` is null, returns `0`. Otherwise delegates.
- New test file: `test/providers/sync_status_provider_test.dart`. Three tests: zero-pending when no service attached, `processPendingSync()` returns 0 when no service, `detach()` notifies listeners even from null state. Keep the test free of Supabase mocks — exercise only the null-service path. Deeper behavior is covered end-to-end in Task 9's umbrella tests.
- Lifecycle documentation in the class doc comment: constructed once in `MultiProvider` with no service; attached on login (eager auth screens today, lazy sign-in from demo mode in the future); detached on logout. Demo mode = constructed, never attached.
- `scripts/run_tests.sh` is green before you say done.

**Files:**
- Create: `lib/providers/sync_status_provider.dart`
- Create: `test/providers/sync_status_provider_test.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 6 of 14: Add catalog mutation surface for trash (prep for `TrashProvider`)

**Why:** `TrashProvider` will need to mutate `_userSessions`/`_userWorkouts`/`_userExercises` to support restore/lift/heal flows. Those lists are private today. This task exposes a minimal `@protected` surface so the next task can build `TrashProvider` without reaching into `PresetProvider`'s internals.

**What (overview):** `PresetProvider` exposes six `@protected` methods that `TrashProvider` will call — three `upsertUser*` (delegating to existing `promoteAndUpdate*`) and three `removeUser*Local` (which mutate the list and save JSON, but *don't* upload a delete to cloud).

**Details:**
- Add to `PresetProvider`, immediately below the existing public CRUD methods:
  - `upsertUserSession(Session s)` returns `Future<void>` and delegates to `promoteAndUpdateSession(s)`. Same for `upsertUserWorkout` and `upsertUserExercise`.
  - `removeUserSessionLocal(String id)` is `Future<void>`. Removes from `_userSessions` and calls `PresetLogger.savePresetToFile` for the sessions JSON file. **No cloud delete here** — when trash is the source of truth, the catalog row is removed locally only, and the trash entry's upload is what the cloud sees. Same for workouts and exercises.
  - All six methods are annotated `@protected` (the annotation is `package:meta` — already imported in this file via `flutter/foundation.dart`).
- Don't migrate any existing call sites in this task. The methods are introduced; existing inline mutations in `deleteToTrash` etc. stay as they are until Task 9.
- The six methods are temporary — Task 12 promotes them to first-class catalog methods with cleaner names. For now, the naming reflects their intent: "this is what `TrashProvider` calls."
- `scripts/run_tests.sh` is green before you say done. Adding methods that delegate to existing ones must not change behavior.

**Files:**
- Modify: `lib/providers/preset_provider.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 7 of 14: Implement `TrashProvider` (file + stub test)

**Why:** Trash is the most isolated of the remaining domains. Extracting it as its own `ChangeNotifier` clears the path for the rename in Task 12 and exposes a clean `trashedIdsOf(kind)` surface that the catalog's merged-list getters will read in Task 9.

**What (overview):** A new `TrashProvider extends ChangeNotifier` exists with the trash domain methods (`loadAndPurge`, `selfHealCatalogTrashDrift`, `deleteToTrash`, `restoreFromTrash`, `liftToCatalog`, `refreshAfterSignIn`, `reset`), holds its own `_trashedItems` and `TrashService`, and depends on `PresetProvider` (for catalog mutation) and `SyncStatusProvider` (for cloud) via constructor. A stub test exists. `PresetProvider` is NOT modified in this task — the deletion + wiring happens in Tasks 8 and 9.

**Details:**
- New file: `lib/providers/trash_provider.dart`.
- Constructor: `TrashProvider({required PresetProvider catalog, required SyncStatusProvider syncStatus})` — both required, no nullable.
- Three private fields: `_catalog` (PresetProvider), `_syncStatus` (SyncStatusProvider), `_trashService = TrashService()`. One private list field `_trashedItems`.
- Public `trashedItems` getter returns an unmodifiable view.
- Public `trashedIdsOf(TrashKind kind) -> Set<String>`. Filters by kind, maps to id, into a set. The catalog will call this in Task 9 to filter its merged lists.
- `@visibleForTesting void debugSeedTrash(List<TrashEntry> entries)` — sets `_trashedItems` and notifies. Mirror the existing one on `PresetProvider`.
- `loadAndPurge()` — verbatim port of `PresetProvider._loadAndPurgeTrash` body, with substitutions: `_syncService` → `_syncStatus.service`. Notifies at the end.
- `selfHealCatalogTrashDrift()` — verbatim port of `PresetProvider._selfHealCatalogTrashDrift`. Substitutions:
  - `_userSessions`/`_userWorkouts`/`_userExercises` reads → use the catalog's existing `presetUserSessionIDs`/`presetUserWorkoutsIDs`/`presetUserExerciseIDs` getters to determine staleness.
  - `_userSessions.removeWhere(...) + save` → `await _catalog.removeUserSessionLocal(id)` (same for workout/exercise).
  - `_syncService` → `_syncStatus.service`.
  - **All three cloud-delete loops must be ported** (deleteWorkout, deleteExercise, deleteSession). These were added in commit `5f18430` and weren't in the original-original method — they fix cloud drift.
- `deleteToTrash({required String id, required TrashKind kind})` — verbatim port from `PresetProvider`. Substitutions:
  - `_userSessions.removeWhere(...) + save` → `await _catalog.removeUserSessionLocal(id)` (and same for the others).
  - `_syncService` → `_syncStatus.service`.
  - `_trashedItems.add(...)` and `_trashService.add(...)` stay — this state lives in `TrashProvider` now.
  - Every `Sentry.captureException` preserved verbatim.
  - Notifies at the end.
- `restoreFromTrash(String id, {String? overrideTitle})` — verbatim port. Substitutions:
  - `_userWorkouts.removeWhere + .add + save` → `await _catalog.upsertUserWorkout(w)` (and same for the others).
  - `_trashedItems.removeWhere(...)` stays.
  - `_syncService` → `_syncStatus.service`.
- `liftToCatalog({required Object item, required TrashKind kind, String? overrideTitle, String? overrideId})` — verbatim port. Each kind branch's `_userX.add + save + upload` becomes `await _catalog.upsertUserX(...)` (the upsertUser methods route through `promoteAndUpdate*` which already handles the upload).
- `refreshAfterSignIn()` — new method (Task 10's seam, but defined here). If `_syncStatus.service` is null, return. Otherwise fetch cloud trash entries and merge with current `_trashedItems` via `PresetSyncMerger.mergeTrashCloudAndLocal`. Sentry on error. Notify on success.
- `reset()` — clears `_trashedItems` and notifies. Called on logout in Task 10.
- New test file: `test/providers/trash_provider_test.dart`. Two tests are enough at this stage:
  - "trashedItems is empty on a fresh provider"
  - "debugSeedTrash exposes seeded entries"
  Use `Directory.systemTemp.createTemp` + a `_FakePathProvider` in `setUp` (mirror what `preset_provider_trash_test.dart` does for path setup). Construct a real `PresetProvider` and a real `SyncStatusProvider` (no mocks needed since service is null by default). Deeper behavior coverage migrates from `preset_provider_trash_test.dart` in Task 9.
- `scripts/run_tests.sh` is green before you say done. The new test file is the only new exerciser; the existing tests still pass through `PresetProvider`'s methods because we haven't deleted them yet.

**Files:**
- Create: `lib/providers/trash_provider.dart`
- Create: `test/providers/trash_provider_test.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 8 of 14: Wire `TrashProvider` into `MultiProvider` and `init`

**Why:** `TrashProvider` exists but isn't reachable yet. This task registers it in the provider tree, makes `PresetProvider.init` accept and drive it, and makes the catalog's merged-list getters read trash filtering from it.

**What (overview):** `lib/main.dart`'s `MultiProvider` includes `SyncStatusProvider` and a `ChangeNotifierProxyProvider2<PresetProvider, SyncStatusProvider, TrashProvider>`. `PresetProvider.init` takes an optional `TrashProvider` parameter and calls `loadAndPurge` + `selfHealCatalogTrashDrift` on it. The three merged-list getters read trashed ids from an attached `TrashProvider` instead of from local `_trashedItems`. **Both `PresetProvider`'s own trash logic and `TrashProvider`'s logic still exist** — the deletion happens in Task 9.

**Details:**
- In `main.dart`'s `MultiProvider`, add the providers in this order to satisfy dependency direction: `AuthProvider`, `SessionLogProvider`, **`SyncStatusProvider`** (new), `PresetProvider`, **`ChangeNotifierProxyProvider2<PresetProvider, SyncStatusProvider, TrashProvider>`** (new), `sessionStateProvider`, `SettingsProvider`. The proxy provider's `create` constructs `TrashProvider(catalog: context.read<PresetProvider>(), syncStatus: context.read<SyncStatusProvider>())`. The `update` lambda returns `previous ?? TrashProvider(catalog: catalog, syncStatus: syncStatus)` — we don't recreate on dep change.
- Add the imports `sync_status_provider.dart` and `trash_provider.dart` to `main.dart`.
- In `PresetProvider`, add a private field `TrashProvider? _trash` and a setter `void attachTrashProvider(TrashProvider trash) { _trash = trash; trash.addListener(notifyListeners); }`. The listener registration is what keeps merged-list getters reactive when trash mutates.
- Modify `init`'s signature to `Future<void> init({String? userId, TrashProvider? trash}) async`. After the existing local/cloud branch and before `_isLoading = false`, if `trash != null`: `await trash.loadAndPurge(); await trash.selfHealCatalogTrashDrift();`. Keep `_isInitialized` and `_isLoading` exactly as they are now.
- In the three merged-list getters (`presetSessions`, `presetWorkouts`, `presetExercises`), replace the local `trashedIds` computation with `_trash?.trashedIdsOf(TrashKind.session)` (and similar) `?? const <String>{}`. The rest of the filtering stays.
- In both `LoadingScreen` and `LoginScreen` (in `lib/presentation/screens/auth_flow/`), find the existing `await presetProvider.init(userId: ...)` call. Before it, read `trashProvider` from context and call `presetProvider.attachTrashProvider(trashProvider)`. Pass `trash: trashProvider` into the `init` call.
- **Do not delete `_loadAndPurgeTrash`, `_selfHealCatalogTrashDrift`, or `_trashService` from `PresetProvider` yet.** They still run — the wiring is parallel right now. Task 9 deletes the duplicates.
- Add a `@override void dispose()` to `PresetProvider` that calls `_trash?.removeListener(notifyListeners)` before `super.dispose()`. Prevents listener leaks on teardown.
- `scripts/run_tests.sh` is green before you say done. The `preset_provider_trash_test.dart` still exercises `PresetProvider`'s trash methods directly — it should still pass because those methods haven't moved yet.

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/providers/preset_provider.dart`
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`
- Modify: `lib/presentation/screens/auth_flow/login_screen.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 9 of 14: Remove trash logic from `PresetProvider`, split trash test

**Why:** Now that `TrashProvider` is wired in and the catalog filters via it, the duplicate logic in `PresetProvider` can come out. This is the structural split's commit point — after this, the catalog provider truly doesn't own trash state.

**What (overview):** `PresetProvider` loses its trash fields, methods, and seeder. The existing `preset_provider_trash_test.dart` is split: tests that exercise trash *mutations* move to `trash_provider_test.dart`; tests that assert merged-list *filtering* stay in a new `catalog_provider_trash_filtering_test.dart` (still pointing at `PresetProvider` for this task — Task 12 does the class rename).

**Details:**
- Remove from `PresetProvider`:
  - Field: `final TrashService _trashService = TrashService();`
  - Field: `List<TrashEntry> _trashedItems = [];`
  - Getter: `trashedItems`
  - `@visibleForTesting void debugSeedTrash(List<TrashEntry> entries)`
  - `_loadAndPurgeTrash()`
  - `_selfHealCatalogTrashDrift()`
  - `deleteToTrash(...)`
  - `restoreFromTrash(...)`
  - `liftToCatalog(...)`
- Also remove the corresponding init calls inside `PresetProvider.init` (the two `await _loadAndPurgeTrash()` / `await _selfHealCatalogTrashDrift()` lines). The `if (trash != null) { await trash.loadAndPurge(); await trash.selfHealCatalogTrashDrift(); }` block from Task 8 is now the only path.
- Remove the `import 'package:flash_forward/services/trash_service.dart';` and `package:flash_forward/models/trash_entry.dart` imports from `preset_provider.dart` only if no other code in the file still references them. The `TrashKind` enum is used in the merged-list getters — keep that import.
- Test file split:
  - Categorise each test in `preset_provider_trash_test.dart`:
    - Tests that call `presetProvider.deleteToTrash`, `restoreFromTrash`, `liftToCatalog`, or seed via `debugSeedTrash` to exercise *those methods* → move to `trash_provider_test.dart`. Update them to construct `TrashProvider(catalog: presetProvider, syncStatus: SyncStatusProvider())` in `setUp`, and call methods on `trashProvider` instead of `presetProvider`. The `attachTrashProvider` call is also needed in `setUp` so the catalog's merged-list filtering stays reactive.
    - Tests that seed trash via `debugSeedTrash` but assert the result via `presetProvider.presetWorkouts` / `.presetExercises` / `.presetSessions` → these are filtering tests. Move them to a new file `test/providers/catalog_provider_trash_filtering_test.dart`. Same `setUp` (both providers + `attachTrashProvider`), but tests assert against the catalog's merged-list getters and seed trash via `trashProvider.debugSeedTrash(...)`.
  - The original `preset_provider_trash_test.dart` is deleted at the end of the split.
- `scripts/run_tests.sh` is green before you say done. This is the highest-risk task — every failure means a behavior was lost in translation. If anything regresses, the cloud-delete loops in `selfHealCatalogTrashDrift` are a specific suspect (the post-`5f18430` extension was easy to miss in the verbatim port).

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Modify: `test/providers/trash_provider_test.dart` (gains migrated tests)
- Create: `test/providers/catalog_provider_trash_filtering_test.dart`
- Delete: `test/providers/preset_provider_trash_test.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 10 of 14: Caller-wires `init` — drop `userId`, add `refreshAfterSignIn`

**Why:** This is where the API change lands. Removing `userId` from `init` makes demo-before-signin natural ("no attach call before init" = local-only). Adding `refreshAfterSignIn` gives the future sign-in-from-demo flow a clean hook. Also routes `PresetProvider`'s cloud access through `SyncStatusProvider`, removing the last duplicate-`SupabaseSyncService` instance.

**What (overview):** `PresetProvider.init` no longer takes `userId`. It reads cloud access from an attached `SyncStatusProvider`. A new `attachSyncStatus` setter exists. A new `refreshAfterSignIn` method reloads cloud data into an already-initialised provider. The two auth screens are updated to wire the chain. `RootScreen` is updated so logout detaches the service.

**Details:**
- In `PresetProvider`:
  - Remove the field `SupabaseSyncService? _syncService;`.
  - Add field `SyncStatusProvider? _syncStatus;` and setter `void attachSyncStatus(SyncStatusProvider s) { _syncStatus = s; }`.
  - Find every `_syncService` reference in the file. Each becomes `_syncStatus?.service`. The null-semantics are identical (no service = no cloud op = local-only).
  - Modify `init`'s signature to `Future<void> init({TrashProvider? trash}) async`. Remove the `_syncService = SupabaseSyncService(userId: userId);` line entirely. The cloud branch becomes: `final svc = _syncStatus?.service; if (svc != null) { await svc.syncQueue.loadQueue(); try { ... PresetLoader.loadFromCloud(svc) ... } catch (...) { Sentry...; fallback to local; } } else { ... local ... }`.
  - Add new public method `Future<void> refreshAfterSignIn() async`. If `_syncStatus?.service` is null, return. Otherwise call `svc.syncQueue.loadQueue()` and then `PresetLoader.loadFromCloud(svc)`, assigning the three lists. Notify on success. Catch + Sentry on failure — **no local fallback here** (local state was already loaded at init).
  - Remove the three sync-passthrough methods: `hasPendingSync`, `pendingSyncCount`, `processPendingSync`. Anything that needed them now reads `SyncStatusProvider` directly.
  - Update `reset()` so it no longer touches `_syncService` (the field doesn't exist anymore).
- In both `LoadingScreen` and `LoginScreen`, replace the existing init flow with the four-step wiring:
  1. `final syncStatus = context.read<SyncStatusProvider>();`
  2. `if (userId != null) syncStatus.attach(SupabaseSyncService(userId: userId));`
  3. `presetProvider.attachSyncStatus(syncStatus); presetProvider.attachTrashProvider(trashProvider);`
  4. `await presetProvider.init(trash: trashProvider);`
  The `userId` no longer goes to `init` — it goes to the `SupabaseSyncService` constructor on the caller side.
- In `loading_screen.dart`, find the call to `presetProvider.processPendingSync()` and change it to `syncStatus.processPendingSync()` (after reading `syncStatus` from context).
- In `RootScreen`, both call sites of `presetProvider.reset()` need additional cleanup: also call `syncStatus.detach()` and `trashProvider.reset()` (in any order — they're independent). Read both from context.
- Grep `grep -rn "presetProvider\.\(hasPendingSync\|pendingSyncCount\|processPendingSync\)" lib/` afterwards — there should be zero matches.
- `scripts/run_tests.sh` is green before you say done. The auth flow is the riskiest area — if the existing tests don't cover a path you changed, run the app manually and confirm sign-in still loads cloud data.

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`
- Modify: `lib/presentation/screens/auth_flow/login_screen.dart`
- Modify: `lib/presentation/screens/root_screen.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 11 of 14: Extract `EditCommitController` (⚡ first of 3 edit screens)

**Why:** `commitChanges`, `propagateBag`, and `CommitResult` form a coherent orchestration surface that doesn't hold state — it's a stateless façade over `PresetProvider`'s catalog mutations. Extracting it gives the catalog provider a tighter domain and gives edit screens a single, named entry point.

**What (overview):** A new `EditCommitController` class exists. Its constructor takes a `PresetProvider`. It exposes `commitChanges` and `propagateBag` (verbatim ports of the existing methods). The `CommitResult` class moves with it. `PresetProvider` no longer defines these — they're gone. The first of three edit screens (`new_exercise_screen.dart`, the simplest) is migrated to use `EditCommitController` via `context.read`. The remaining two screens are migrated by the instructor after review.

⚡ **First of 3 edit screens — migrate `new_exercise_screen.dart` only. Claude handles `new_session_screen.dart` and `new_workout_screen.dart` after your first migration passes review.**

**Details:**
- New file: `lib/providers/edit_commit_controller.dart`.
- Class `EditCommitController` (no ChangeNotifier — it holds no state and doesn't notify). Constructor: `EditCommitController(this._catalog)` where `_catalog: PresetProvider` is private final.
- `Future<CommitResult> commitChanges(PendingChangeBag bag, {String? excludeSessionId, String? excludeWorkoutId})` — verbatim port from `PresetProvider.commitChanges`. The body's `this.promoteAndUpdate*` / `this.usagesOfWorkout` / `this.usagesOfExercise` become `_catalog.promoteAndUpdate*` / `_catalog.usagesOfWorkout` / `_catalog.usagesOfExercise`. Preserve every branch — `isSessionScopedCommit`, the exercise-inside-bagged-workout suppression, the after-promotion `usagesOf` recompute.
- `Future<void> propagateBag(PendingChangeBag bag, {PropagationSelection? selection})` — verbatim port. Same suppression-mirror logic.
- `CommitResult` class moves to this file too. Same fields and `hasAny` getter.
- Remove `commitChanges`, `propagateBag`, and `CommitResult` from `preset_provider.dart`. Keep the propagation primitives — `propagateWorkoutToSessionTemplates`, `propagateExerciseToSessionTemplates`, `propagateExerciseToWorkouts`, `usagesOfWorkout`, `usagesOfExercise`, `sessionsContainingWorkout`, `workoutsContainingExercise` — they're still part of the catalog's public API.
- Register `EditCommitController` in `main.dart`'s `MultiProvider`. Use `ProxyProvider<PresetProvider, EditCommitController>(update: (_, catalog, __) => EditCommitController(catalog))`. It's a regular `Provider` (no listening to `EditCommitController` because it has no notifier).
- Migrate `lib/presentation/screens/catalog_flow/new_exercise_screen.dart` only. Find every `presetProvider.commitChanges(...)` and `presetProvider.propagateBag(...)` call. Replace with `context.read<EditCommitController>().commitChanges(...)` and `.propagateBag(...)`. Read the controller once and reuse if there are multiple calls in the same callback.
- Test file migration: `git mv test/providers/preset_provider_commit_changes_test.dart test/providers/edit_commit_controller_test.dart`. Update imports. Every call site that did `provider.commitChanges(...)` becomes `controller.commitChanges(...)` where `controller = EditCommitController(provider)` in `setUp`. Same for `propagateBag`.
- `scripts/run_tests.sh` is green before you say done.

**Files:**
- Create: `lib/providers/edit_commit_controller.dart`
- Modify: `lib/providers/preset_provider.dart`
- Modify: `lib/main.dart`
- Modify: `lib/presentation/screens/catalog_flow/new_exercise_screen.dart`
- Rename + modify: `test/providers/preset_provider_commit_changes_test.dart` → `test/providers/edit_commit_controller_test.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 12 of 14: Rename `PresetProvider` → `CatalogProvider` (⚡ first of 15 call sites)

**Why:** The class is now misnamed. After Tasks 1–11, what remains is the catalog domain — defaults, user lists, merged-list getters, CRUD, propagation primitives. Naming it `CatalogProvider` makes the rest of the codebase legible. The rename also collapses three legacy method names per kind (`addPreset*`, `updatePreset*`, `promoteAndUpdate*`) into one canonical `upsert*`.

**What (overview):** The file `lib/providers/preset_provider.dart` is renamed to `lib/providers/catalog_provider.dart`. The class `PresetProvider` is renamed to `CatalogProvider`. The legacy method names per kind collapse to canonical `upsertSession`/`upsertWorkout`/`upsertExercise` and `deleteSession`/`deleteWorkout`/`deleteExercise`. The first call site (`lib/main.dart`) is migrated. The remaining 14 call sites are migrated by the instructor after review.

⚡ **First of 15 — migrate `lib/main.dart` only. Claude handles the remaining 14 call sites + the 4 test files after your first migration passes review.**

**Details:**
- File rename: `git mv lib/providers/preset_provider.dart lib/providers/catalog_provider.dart`.
- Inside the renamed file, rename `class PresetProvider` to `class CatalogProvider` everywhere it appears.
- Method renames inside the catalog file (apply the table fully):
  | Old | New |
  |---|---|
  | `addPresetSession` / `updatePresetSession` / `promoteAndUpdateSession` | `upsertSession` |
  | `addPresetWorkout` / `updatePresetWorkout` / `promoteAndUpdateWorkout` | `upsertWorkout` |
  | `addPresetExercise` / `updatePresetExercise` / `promoteAndUpdateExercise` | `upsertExercise` |
  | `deleteUserPresetSession` | `deleteSession` |
  | `deleteUserPresetWorkout` | `deleteWorkout` |
  | `deleteUserPresetExercise` | `deleteExercise` |
  Also rename the six `upsertUser*` / `removeUser*Local` `@protected` methods added in Task 6 — drop the `User` infix (`upsertSession` already replaces `upsertUserSession`; for the remove-local variants, name them `removeSessionLocal`/`removeWorkoutLocal`/`removeExerciseLocal`). `TrashProvider`'s calls into them are updated as part of the call-site sweep.
  `presetSessions`/`presetWorkouts`/`presetExercises` stay — semantically they're still "the catalog" and renaming is more churn than benefit.
- Migrate `lib/main.dart` only. Update the import path, the class reference in the `ChangeNotifierProvider`, and any local variable name (`presetProvider` → `catalogProvider` is consistent but optional — the local name doesn't change behavior).
- The 14 remaining call sites (deferred to instructor): `lib/models/pending_change.dart` (doc comment), `lib/providers/trash_provider.dart`, `lib/providers/edit_commit_controller.dart`, the auth/profile/root/session/catalog/widget screens (12 files). Plus 4 test file renames: `preset_provider_promote_default_test.dart` → `catalog_provider_promote_default_test.dart`, `preset_provider_propagate_test.dart` → `catalog_provider_propagate_test.dart`, `preset_provider_superset_propagate_test.dart` → `catalog_provider_superset_propagate_test.dart`, `catalog_provider_trash_filtering_test.dart` already named correctly (created in Task 9).
- `scripts/run_tests.sh` is green before you say done. With only `main.dart` migrated, tests will fail with "PresetProvider not found" everywhere else — that's expected. The handoff completes the rest before re-running.

**Files (first instance):**
- Rename: `lib/providers/preset_provider.dart` → `lib/providers/catalog_provider.dart`
- Modify: the renamed file (class + method renames)
- Modify: `lib/main.dart`

**Files (instructor handles):** the other 14 call sites + 4 test file renames listed above.

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 13 of 14: Update `restore_items_screen.dart` to use both providers

**Why:** The restore screen is the only consumer that reads both *trash state* and *catalog state* in the same widget tree (to detect title collisions on restore and to show what's in the catalog vs trash). Now that the providers are split, the screen needs both — and the helper methods on the screen need their signatures updated.

**What (overview):** The screen's `Consumer<PresetProvider>` becomes `Consumer2<CatalogProvider, TrashProvider>`. Trash reads (`trashedItems`, `restoreFromTrash`, `liftToCatalog`) go through the trash provider; catalog reads (`presetWorkouts`/`presetExercises`/`presetSessions`) go through the catalog provider. The screen's helper methods (`_titleClashes`, `_existingTitlesForKind`, `_restoreSelected`) take both providers as parameters.

**Details:**
- File: `lib/presentation/screens/profile_flow/restore_items_screen.dart`.
- Replace the existing `Consumer<PresetProvider>(...)` with `Consumer2<CatalogProvider, TrashProvider>(builder: (context, catalog, trash, _) { ... })`.
- Inside the builder, every `pp.trashedItems` → `trash.trashedItems`. Every `pp.restoreFromTrash(id, overrideTitle: t)` → `trash.restoreFromTrash(id, overrideTitle: t)`. Every `pp.liftToCatalog(...)` → `trash.liftToCatalog(...)`. Every `pp.presetWorkouts`/`pp.presetExercises`/`pp.presetSessions` → `catalog.presetWorkouts`/etc.
- The three helper methods currently take `PresetProvider pp` as a parameter. Update each signature to take both `CatalogProvider catalog` and `TrashProvider trash` (in that order — by convention reads-first, writes-second). Update internal references inside each method to use the right provider.
- After the change, run the test suite. There may not be a dedicated test for this screen, so:
- Manual smoke test:
  1. Trash a catalog workout from `catalog_flow/catalog_screen.dart`.
  2. Open the restore screen.
  3. Verify the workout appears with its title.
  4. Trigger a title clash by renaming a different workout to the trashed title.
  5. Restore — verify the rename dialog appears and the renamed item lands in the catalog.
- `scripts/run_tests.sh` is green before you say done, plus the manual walkthrough passes.

**Files:**
- Modify: `lib/presentation/screens/profile_flow/restore_items_screen.dart`

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## [ ] Task 14 of 14: Final sweep — analyzer, grep, smoke walk

**Why:** Tighten up. After 13 structural tasks there'll be stray unused imports, possibly missed references, and the upcoming demo-before-signin feature depends on the `refreshAfterSignIn` seams being present and named correctly.

**What (overview):** Analyzer is clean. Grep confirms no `PresetProvider` references remain anywhere. The two `refreshAfterSignIn` methods exist on `CatalogProvider` and `TrashProvider`. The catalog file no longer has any sync-passthrough methods. The manual smoke walk passes.

**Details:**
- Run `flutter analyze`. Address every error (warnings about unused imports are common after a split this size — clean them up).
- Run `grep -rn "PresetProvider" lib/ test/`. Expected: zero matches. Any hits are missed renames from Task 12.
- Run `grep -nE "hasPendingSync|pendingSyncCount|processPendingSync" lib/providers/catalog_provider.dart`. Expected: zero matches. These should all live on `SyncStatusProvider` now.
- Run `grep -nE "refreshAfterSignIn" lib/providers/catalog_provider.dart lib/providers/trash_provider.dart`. Expected: one match in each file. This is the seam the upcoming demo-before-signin feature will hook into — confirm it's there.
- Run `scripts/run_tests.sh` one more time. All green.
- Manual UI smoke walk:
  1. **Catalog flow:** add workout, edit workout (trigger the propagation prompt), trash, restore.
  2. **Session flow:** start session, complete session, view in calendar.
  3. **Auth flow:** sign out, sign back in. Verify catalog and trash both reload (check counts vs what was there before sign-out).
  4. **Offline flow:** kill network, mutate a workout, restore network, see the sync indicator clear.
  5. **Superset flow:** edit a superset workout (member sets, supersetSetRest), confirm the propagation prompt fires and accepts.
- If any of those regress, the diff in this final task surfaces what was missed in earlier tasks.
- Commit the analyzer/grep cleanup (if anything came up).

**Files:**
- Any file with unused imports surfaced by analyzer (likely a handful in `lib/` and `test/`).

> *Current help level: **default**. Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

## Plan-level acceptance criteria

- [ ] `scripts/run_tests.sh` passes after every task commit (no skipped tasks).
- [ ] `flutter analyze` returns zero errors after Task 14.
- [ ] Total LOC across `catalog_provider.dart` + `trash_provider.dart` + `edit_commit_controller.dart` + `sync_status_provider.dart` + `preset_loader.dart` + `preset_sync_merger.dart` + `synced_item_ops.dart` is 600–750 LOC.
- [ ] No file in that set exceeds 600 LOC.
- [ ] All 15 known call sites (production + test files) updated.
- [ ] Both `refreshAfterSignIn` methods exist (Task 14 grep confirms).
- [ ] Manual smoke walk (Task 14) passes — including superset flow.
