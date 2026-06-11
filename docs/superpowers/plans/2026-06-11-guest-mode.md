# Guest Mode (Demo Before Sign-In) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users demo the app without an account ("Continue as guest"), gating persisted catalog mutations and cloud session backup behind a dismissible auth wall, with guest sessions saved locally and auto-claimed on later auth.

**Architecture:** A persisted guest flag (`GuestModeStore`) routes cold start; a `SignInCoordinator` centralizes the provider wiring that is today duplicated in `LoadingScreen` and `LoginScreen` and adds the deferred-sign-in path (`onSignedIn`) using the existing `refreshAfterSignIn` seams; a `requireAuth` bottom-sheet helper gates the save sites; the auth screens gain a `popOnSuccess` detour mode so mid-task sign-in returns to the caller with drafts intact.

**Tech Stack:** Flutter, Provider, Supabase, SharedPreferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-11-guest-mode-design.md` — read it first.

**Test runner:** ALWAYS `./scripts/run_tests.sh <file>` — never raw `flutter test`.

---

## File Map

**Create:**
| File | Responsibility |
|---|---|
| `lib/features/auth/guest_mode_store.dart` | Persisted guest flag (SharedPreferences) |
| `lib/features/auth/sign_in_coordinator.dart` | `initForUser` / `initForGuest` / `onSignedIn` wiring |
| `lib/presentation/widgets/auth_wall.dart` | `requireAuth()` bottom sheet |
| `test/support/fake_supabase_sync_service.dart` | Shared fake for sync-service-touching tests |
| `test/support/fake_auth_service.dart` | Fake `AuthService` for widget tests |
| `test/features/auth/guest_mode_store_test.dart` | |
| `test/features/auth/sign_in_coordinator_test.dart` | |
| `test/features/session_log/session_log_provider_refresh_test.dart` | |
| `test/features/catalog/reset_clears_local_storage_test.dart` | |
| `test/presentation/screens/auth_wall_test.dart` | |
| `test/presentation/screens/profile_screen_guest_test.dart` | |

**Modify:** `auth_provider.dart` (injectable service, guest-flag clear), `session_log_provider.dart` (`refreshAfterSignIn`), `supabase_sync_service.dart` (`completedAt` param), `catalog_provider.dart` + `trash_provider.dart` (reset clears local files), `loading_screen.dart`, `login_screen.dart`, `signup_screen.dart`, `email_confirmation_screen.dart` (routing + detour), `new_session_screen.dart`, `new_workout_screen.dart`, `new_exercise_screen.dart`, `catalog_screen.dart` (gates), `session_active_bottom_bar.dart` (post-save prompt), `profile_screen.dart`, `settings_drawer.dart` (guest variants).

**Background you need:** `SyncStatusProvider` with no service attached IS the supported local-only state (see its doc comment). `CatalogProvider.init(trash:)` takes no userId. `CatalogProvider.refreshAfterSignIn()` (line ~165) and `TrashProvider.refreshAfterSignIn()` (line ~346) already exist. Test helpers live in `test/support/catalog_test_kit.dart`: `makeCatalogEnv()` (temp-dir-backed catalog+trash+syncStatus with a `_FakePathProvider` routing `path_provider` to a temp dir), and builders `testSession/testWorkout/testExercise`.

---

### Task 1: GuestModeStore

**Files:**
- Create: `lib/features/auth/guest_mode_store.dart`
- Test: `test/features/auth/guest_mode_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/features/auth/guest_mode_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to disabled', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await GuestModeStore.isEnabled(), false);
  });

  test('enable persists and disable clears', () async {
    SharedPreferences.setMockInitialValues({});
    await GuestModeStore.enable();
    expect(await GuestModeStore.isEnabled(), true);
    await GuestModeStore.disable();
    expect(await GuestModeStore.isEnabled(), false);
  });
}
```

- [ ] **Step 2: Run, verify it fails** — `./scripts/run_tests.sh test/features/auth/guest_mode_store_test.dart` — expected: compile error, `guest_mode_store.dart` not found.

- [ ] **Step 3: Implement**

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted "Continue as guest" flag. Set when the user taps the guest
/// button on the login screen; cleared on any successful sign-in
/// (SignInCoordinator.onSignedIn) and on sign-out (AuthProvider.signOut).
/// LoadingScreen reads it to route a returning guest straight to home.
class GuestModeStore {
  GuestModeStore._();

  static const _key = 'guest_mode';

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  static Future<void> enable() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);

  static Future<void> disable() async =>
      (await SharedPreferences.getInstance()).setBool(_key, false);
}
```

- [ ] **Step 4: Run, verify pass** — same command, expected `All tests passed!`
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(auth): GuestModeStore persisted guest flag"`

---

### Task 2: AuthProvider — injectable AuthService + guest-flag clear; FakeAuthService

**Files:**
- Modify: `lib/features/auth/auth_provider.dart:8` and `:180`
- Create: `test/support/fake_auth_service.dart`

`AuthService` has no constructor-time Supabase access (the `supabase` global in `supabase_config.dart:26` is only touched inside methods), so a fake subclass is safe to construct in tests.

- [ ] **Step 1: Make the service injectable.** Replace `final AuthService _authService = AuthService();` with:

```dart
final AuthService _authService;

AuthProvider({AuthService? authService})
    : _authService = authService ?? AuthService();
```

- [ ] **Step 2: Clear the guest flag on sign-out.** In `signOut()` add `await GuestModeStore.disable();` as the first line (import `guest_mode_store.dart`). No unit test — the line is glue over a tested store; covered by manual verification (Task 13).

- [ ] **Step 3: Create `test/support/fake_auth_service.dart`**

```dart
import 'package:flash_forward/features/auth/auth_service.dart';

/// Constructible without Supabase.initialize() — the real AuthService only
/// touches the supabase global inside methods, all overridden here as needed.
class FakeAuthService extends AuthService {
  FakeAuthService({this.signedIn = false, this.emailConfirmed = true});

  bool signedIn;
  bool emailConfirmed;

  @override
  bool isSignedIn() => signedIn;

  @override
  bool isEmailConfirmed() => emailConfirmed;
}
```

Check `AuthService.isSignedIn` / `isEmailConfirmed` signatures in `auth_service.dart` and match them exactly (they may return `bool` from a nullable session check).

- [ ] **Step 4: Compile check** — `./scripts/run_tests.sh test/features/auth/guest_mode_store_test.dart` (fast file that imports nothing broken; also run `flutter analyze lib/features/auth test/support` if in doubt). Expected: pass / no analyzer errors.
- [ ] **Step 5: Commit** — `git commit -am "feat(auth): injectable AuthService seam + clear guest flag on sign-out"`

---

### Task 3: SupabaseSyncService.logCompletedSession completedAt param + FakeSupabaseSyncService

**Files:**
- Modify: `lib/core/sync/supabase_sync_service.dart:106-129`
- Create: `test/support/fake_supabase_sync_service.dart`

- [ ] **Step 1: Add the param.** The claim (Task 4) must preserve when a guest session actually happened; today the method stamps `DateTime.now()`. Change the signature and both usages of the timestamp:

```dart
Future<void> logCompletedSession(
  Session session, {
  bool isRetry = false,
  DateTime? completedAt,
}) async {
  final completedAtIso = (completedAt ?? DateTime.now()).toIso8601String();
  try {
    await supabase.from('session_logs').insert({
      'user_id': userId,
      'session_id': session.id,
      'completed_at': completedAtIso,
      'session_data': session.toJson(),
    });
  } catch (e) {
    if (!isRetry) {
      await _syncQueue.enqueue(SyncOperation(
        id: '${session.id}_$completedAtIso',
        type: 'logSession',
        data: {
          'session': session.toJson(),
          'completedAt': completedAtIso,
        },
        createdAt: DateTime.now(),
      ));
    }
    rethrow;
  }
}
```

Then check `processPendingSync()` in the same file: confirm the `logSession` retry path replays `data['completedAt']` (it should already, since the op carried `completedAt` before this change — verify, don't assume).

- [ ] **Step 2: Create the shared fake** in `test/support/fake_supabase_sync_service.dart`:

```dart
import 'package:flash_forward/core/sync/supabase_sync_service.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';

/// Overrides every network method used by the guest-mode flows. Safe to
/// construct without Supabase.initialize() — the supabase global is only
/// touched inside the real methods. The inherited SyncQueueService is real
/// and file-backed; tests that exercise it must fake path_provider
/// (see catalog_test_kit.dart).
class FakeSupabaseSyncService extends SupabaseSyncService {
  FakeSupabaseSyncService() : super(userId: 'fake-user-id');

  final claimedSessions = <Session>[];
  final claimedCompletedAts = <DateTime?>[];
  List<Session> cloudLoggedSessions = [];
  List<Session> cloudUserSessions = [];
  List<Workout> cloudUserWorkouts = [];
  List<Exercise> cloudUserExercises = [];
  List<TrashEntry> cloudTrashEntries = [];
  bool throwOnLogCompletedSession = false;

  @override
  Future<void> logCompletedSession(
    Session session, {
    bool isRetry = false,
    DateTime? completedAt,
  }) async {
    if (throwOnLogCompletedSession) throw Exception('simulated offline');
    claimedSessions.add(session);
    claimedCompletedAts.add(completedAt);
  }

  @override
  Future<List<Session>> fetchLoggedSessions({
    DateTime? startDate,
    DateTime? endDate,
  }) async => cloudLoggedSessions;

  @override
  Future<List<Session>> fetchUserSessions() async => cloudUserSessions;

  @override
  Future<List<Workout>> fetchUserWorkouts() async => cloudUserWorkouts;

  @override
  Future<List<Exercise>> fetchUserExercises() async => cloudUserExercises;

  @override
  Future<List<TrashEntry>> fetchUserTrashEntries() async => cloudTrashEntries;
}
```

Verify the `TrashEntry` import path (`grep -rn "class TrashEntry" lib/`).

- [ ] **Step 3: Run whole suite to catch regressions from the signature change** — `./scripts/run_tests.sh`. Expected: all pass.
- [ ] **Step 4: Commit** — `git commit -am "feat(sync): completedAt param on logCompletedSession + shared fake sync service"`

---

### Task 4: SessionLogProvider.refreshAfterSignIn — seam + claim

**Files:**
- Modify: `lib/features/session_log/session_log_provider.dart` (add method after `reset()`, ~line 196)
- Test: `test/features/session_log/session_log_provider_refresh_test.dart`

- [ ] **Step 1: Write the failing test.** `SessionLogger` is file-backed via path_provider, so route it to a temp dir (the kit's `_FakePathProvider` is private — duplicate the 8-line fake):

```dart
import 'dart:io';

import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flash_forward/features/session_log/session_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/catalog_test_kit.dart';
import '../../support/fake_supabase_sync_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('session_refresh_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  test('claims local sessions to the cloud preserving completedAt', () async {
    final completed = DateTime(2026, 6, 1, 10);
    final local = testSession(id: 'guest-1').copyWith(
      completedAt: Nullable(completed), // match copyWith's Nullable wrapper
    );
    await SessionLogger.logSession(local);

    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService();
    await provider.refreshAfterSignIn(fake);

    expect(fake.claimedSessions.map((s) => s.id), ['guest-1']);
    expect(fake.claimedCompletedAts, [completed]);
  });

  test('reloads loggedSessions from the cloud after the claim', () async {
    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService()
      ..cloudLoggedSessions = [testSession(id: 'cloud-1')];
    await provider.refreshAfterSignIn(fake);

    expect(provider.loggedSessions.map((s) => s.id), ['cloud-1']);
  });

  test('a failing claim is swallowed and the rest still proceeds', () async {
    await SessionLogger.logSession(testSession(id: 'guest-1'));
    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService()..throwOnLogCompletedSession = true;

    await provider.refreshAfterSignIn(fake); // must not throw

    expect(provider.loggedSessions.map((s) => s.id), ['cloud... see note']);
  });
}
```

Notes for the executor: import `Nullable` from wherever `Session.copyWith` defines it (`grep -n "class Nullable" lib/`). In the failure test, `fetchLoggedSessions` still succeeds (only `logCompletedSession` throws), so assert `provider.loggedSessions` equals `fake.cloudLoggedSessions` (set it to one session to make the assertion meaningful). `Sentry.captureException` is a safe no-op when Sentry is uninitialized.

- [ ] **Step 2: Run, verify failure** — `./scripts/run_tests.sh test/features/session_log/session_log_provider_refresh_test.dart` — expected: `refreshAfterSignIn` undefined.

- [ ] **Step 3: Implement** (after `reset()`):

```dart
/// Deferred sign-in seam (mirrors CatalogProvider/TrashProvider).
/// Attaches the shared sync service, then *claims* guest-era sessions:
/// every locally-stored session is pushed to the cloud with its original
/// completion date. Failures are queued for retry by the service and must
/// not block the rest of sign-in. Finally reloads from the cloud so an
/// existing account's history appears.
Future<void> refreshAfterSignIn(SupabaseSyncService service) async {
  _syncService = service;

  final localSessions = await SessionLogger.readLoggedSessions();
  for (final session in localSessions) {
    try {
      await service.logCompletedSession(
        session,
        completedAt: session.completedAt,
      );
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  await loadLoggedSessions();
  updateSelectedSessionsCalendarFormat();
}
```

Double-claim safety: sign-out clears local session storage (`reset()` → `clearLoggedSessions()`), so at any deferred sign-in the local file contains only guest-era sessions — see spec §3/§6.

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `git commit -am "feat(session-log): refreshAfterSignIn seam + guest session claim"`

---

### Task 5: reset() clears local catalog/trash storage (spec §6)

**Files:**
- Modify: `lib/features/catalog/catalog_provider.dart:687` (`reset`), `lib/features/catalog/trash_provider.dart:361` (`reset`)
- Modify: `lib/presentation/screens/profile_flow/settings_drawer.dart` (`_signOut` ~line 289, `_deleteAccount` ~line 358: await the resets)
- Test: `test/features/catalog/reset_clears_local_storage_test.dart`

- [ ] **Step 1: Write the failing test** (uses `makeCatalogEnv` — temp-dir-backed files):

```dart
import 'package:flash_forward/features/catalog/preset_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_test_kit.dart';

void main() {
  test('CatalogProvider.reset deletes local user preset files', () async {
    final env = await makeCatalogEnv();
    await env.catalog.init(trash: env.trash);
    await env.catalog.upsertSession(testSession(id: 'u1'));
    expect((await PresetLoader.loadFromLocal()).sessions, isNotEmpty);

    await env.catalog.reset();

    expect((await PresetLoader.loadFromLocal()).sessions, isEmpty);
    await env.dispose();
  });

  test('TrashProvider.reset clears the local trash file', () async {
    final env = await makeCatalogEnv(sessions: [testSession(id: 's1')]);
    await env.catalog.init(trash: env.trash);
    await env.trash.deleteToTrash(id: 's1', kind: TrashKind.session);
    expect(env.trash.trashedItems, isNotEmpty);

    await env.trash.reset();

    await env.trash.loadAndPurge(); // re-read from disk
    expect(env.trash.trashedItems, isEmpty);
    await env.dispose();
  });
}
```

Import `TrashKind` from its model file (`grep -rn "enum TrashKind" lib/`). If `upsertSession` requires a UUID id, use the kit's pattern from existing tests (see `catalog_provider_promote_default_test.dart`).

- [ ] **Step 2: Run, verify failure** (`reset` returns `void` → `await` analyzer error, and/or local files survive).

- [ ] **Step 3: Implement.** `CatalogProvider.reset()` becomes:

```dart
/// Reset provider state on logout. Also deletes the local preset files —
/// they are a signed-in user's offline mirror, and a guest (or the next
/// account, offline) would otherwise load them via PresetLoader.loadFromLocal.
Future<void> reset() async {
  _isInitialized = false;
  _isLoading = false;
  _defaultSessions = [];
  _defaultWorkouts = [];
  _defaultExercises = [];
  _userSessions = [];
  _userWorkouts = [];
  _userExercises = [];
  await PresetLogger.deleteAllUserPresetFiles();
  notifyListeners();
}
```

`TrashProvider.reset()` becomes:

```dart
Future<void> reset() async {
  _trashedItems = [];
  await _trashService.clear(); // local only — cloud trash belongs to the account
  notifyListeners();
}
```

- [ ] **Step 4: Fix call sites.** `grep -rn "catalogProvider.reset()\|trashProvider.reset()\|\.reset()" lib test` — in `settings_drawer.dart` `_signOut` and `_deleteAccount`, change to `await catalogProvider.reset(); await trashProvider.reset();`. Update any test call sites the grep finds.

- [ ] **Step 5: Run the new test file, then the whole suite** — `./scripts/run_tests.sh`. Expected: all pass.
- [ ] **Step 6: Commit** — `git commit -am "feat(catalog,trash): reset() clears local storage so guests never see a previous user's items"`

---

### Task 6: SignInCoordinator

**Files:**
- Create: `lib/features/auth/sign_in_coordinator.dart`
- Test: `test/features/auth/sign_in_coordinator_test.dart`

- [ ] **Step 1: Write the failing test:**

```dart
import 'package:flash_forward/features/auth/guest_mode_store.dart';
import 'package:flash_forward/features/auth/sign_in_coordinator.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/catalog_test_kit.dart';
import '../../support/fake_supabase_sync_service.dart';

void main() {
  test('initForGuest wires catalog locally, attaches no service', () async {
    final env = await makeCatalogEnv();
    final sessionLog = SessionLogProvider();
    final coordinator = SignInCoordinator(
      catalog: env.catalog,
      trash: env.trash,
      sessionLog: sessionLog,
      syncStatus: env.syncStatus,
      serviceFactory: (_) => fail('guest init must not create a service'),
    );

    await coordinator.initForGuest();

    expect(env.syncStatus.service, isNull);
    expect(env.catalog.isInitialized, true);
    expect(sessionLog.isInitialized, true);
    await env.dispose();
  });

  test('onSignedIn attaches service, refreshes all providers, clears guest flag',
      () async {
    SharedPreferences.setMockInitialValues({'guest_mode': true});
    final env = await makeCatalogEnv();
    final sessionLog = SessionLogProvider();
    final fake = FakeSupabaseSyncService()
      ..cloudUserSessions = [testSession(id: 'c0ffee00-0000-4000-8000-000000000001')];
    final coordinator = SignInCoordinator(
      catalog: env.catalog,
      trash: env.trash,
      sessionLog: sessionLog,
      syncStatus: env.syncStatus,
      serviceFactory: (_) => fake,
    );
    await coordinator.initForGuest();

    await coordinator.onSignedIn('user-1');

    expect(env.syncStatus.service, same(fake));
    expect(env.catalog.userSessions.map((s) => s.id),
        contains('c0ffee00-0000-4000-8000-000000000001'));
    expect(await GuestModeStore.isEnabled(), false);
    await env.dispose();
  });
}
```

Note: check the public getter name for user sessions on `CatalogProvider` (`userSessions` vs similar — grep). Use a UUID-shaped id so `healSlugIdUserItems`/`dropNonUuidOps` don't re-id it.

- [ ] **Step 2: Run, verify failure** — file not found.

- [ ] **Step 3: Implement:**

```dart
import 'package:flash_forward/core/sync/supabase_sync_service.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/features/auth/guest_mode_store.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Central owner of the provider wiring around sign-in. The order is
/// load-bearing: attach the service BEFORE init/refresh, so providers see
/// the cloud path. Three entry points:
///  - [initForUser]: cold start, already authenticated.
///  - [initForGuest]: cold start or guest button — no service; the
///    unattached SyncStatusProvider is the supported local-only state.
///  - [onSignedIn]: deferred sign-in from the auth wall — attach, then
///    refresh via the refreshAfterSignIn seams (claims guest sessions).
class SignInCoordinator {
  SignInCoordinator({
    required this.catalog,
    required this.trash,
    required this.sessionLog,
    required this.syncStatus,
    SupabaseSyncService Function(String userId)? serviceFactory,
  }) : _serviceFactory =
           serviceFactory ?? ((userId) => SupabaseSyncService(userId: userId));

  factory SignInCoordinator.of(BuildContext context) => SignInCoordinator(
        catalog: context.read<CatalogProvider>(),
        trash: context.read<TrashProvider>(),
        sessionLog: context.read<SessionLogProvider>(),
        syncStatus: context.read<SyncStatusProvider>(),
      );

  final CatalogProvider catalog;
  final TrashProvider trash;
  final SessionLogProvider sessionLog;
  final SyncStatusProvider syncStatus;
  final SupabaseSyncService Function(String userId) _serviceFactory;

  Future<void> initForUser(String userId) async {
    syncStatus.attach(_serviceFactory(userId));
    catalog.attachSyncStatus(syncStatus);
    catalog.attachTrashProvider(trash);
    await sessionLog.init(userId: userId);
    await catalog.init(trash: trash);
    await sessionLog.processPendingSync();
    await syncStatus.processPendingSync();
  }

  Future<void> initForGuest() async {
    catalog.attachSyncStatus(syncStatus);
    catalog.attachTrashProvider(trash);
    await sessionLog.init();
    await catalog.init(trash: trash);
  }

  Future<void> onSignedIn(String userId) async {
    final service = _serviceFactory(userId);
    syncStatus.attach(service);
    await catalog.refreshAfterSignIn();
    await trash.refreshAfterSignIn();
    await sessionLog.refreshAfterSignIn(service);
    await sessionLog.processPendingSync();
    await syncStatus.processPendingSync();
    await GuestModeStore.disable();
  }
}
```

(Known asymmetry, fine for now: `initForUser` lets `sessionLog.init` build its own service instance — existing behavior; `onSignedIn` shares one.)

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `git commit -am "feat(auth): SignInCoordinator — initForUser/initForGuest/onSignedIn"`

---

### Task 7: requireAuth bottom sheet

**Files:**
- Create: `lib/presentation/widgets/auth_wall.dart`
- Test: `test/presentation/screens/auth_wall_test.dart`

- [ ] **Step 1: Write the failing widget test:**

```dart
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/presentation/widgets/auth_wall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_auth_service.dart';

Widget _host(AuthProvider auth, void Function(Future<bool>) onResult) {
  return ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              onResult(requireAuth(context, message: 'Create an account to save.')),
          child: const Text('go'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('resolves true immediately when authenticated', (tester) async {
    final auth = AuthProvider(authService: FakeAuthService(signedIn: true));
    late Future<bool> result;
    await tester.pumpWidget(_host(auth, (r) => result = r));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Create an account to save.'), findsNothing);
    expect(await result, true);
  });

  testWidgets('guest sees the sheet; Not now resolves false', (tester) async {
    final auth = AuthProvider(authService: FakeAuthService(signedIn: false));
    late Future<bool> result;
    await tester.pumpWidget(_host(auth, (r) => result = r));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Create an account to save.'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(await result, false);
  });
}
```

- [ ] **Step 2: Run, verify failure.**

- [ ] **Step 3: Implement:**

```dart
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/presentation/screens/auth_flow/signup_screen.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _WallAction { createAccount, logIn }

/// The auth wall. Resolves true if the user is (or becomes) authenticated.
/// Guests get a dismissible bottom sheet; the auth buttons run the existing
/// auth screens in detour mode (popOnSuccess) and return here afterwards,
/// leaving the caller's navigation stack and form state intact.
/// Premium note: keep gate sites a single guard call — future plan-limit
/// checks stack at the same choke points.
Future<bool> requireAuth(BuildContext context, {required String message}) async {
  if (context.read<AuthProvider>().isAuthenticated) return true;

  final action = await showModalBottomSheet<_WallAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message,
                style: sheetContext.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(sheetContext, _WallAction.createAccount),
              child: const Text('Create account'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(sheetContext, _WallAction.logIn),
              child: const Text('Log in'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return false;

  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => action == _WallAction.createAccount
          ? const SignUpScreen(popOnSuccess: true)
          : const LoginScreen(popOnSuccess: true),
    ),
  );
  return result == true;
}
```

This won't compile until `popOnSuccess` exists — for THIS task, add the bare field to both screens (`final bool popOnSuccess;` + ctor param `this.popOnSuccess = false`) without behavior; Task 8 wires the behavior. Style the sheet to match the app (look at existing bottom sheets / dialogs for colors).

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `git commit -am "feat(ui): requireAuth bottom-sheet gate"`

---

### Task 8: Detour mode through Login → Signup → EmailConfirmation

**Files:**
- Modify: `lib/presentation/screens/auth_flow/login_screen.dart`, `signup_screen.dart`, `email_confirmation_screen.dart`

No automated test (navigation chains through Supabase-coupled screens); verified manually in Task 13. Keep changes mechanical:

- [ ] **Step 1: LoginScreen.** Already has `popOnSuccess` field (Task 7). In `_signIn()` success branch, replace the whole wiring block (lines ~196-224) with:

```dart
if (success) {
  final userId = authProvider.userId;
  if (userId == null) return;
  final coordinator = SignInCoordinator.of(context);
  if (widget.popOnSuccess) {
    await coordinator.onSignedIn(userId);
    if (mounted) Navigator.of(context).pop(true);
  } else {
    await coordinator.initForUser(userId);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const RootScreen()));
  }
}
```

Drop the now-unused imports (`SupabaseSyncService`, `SyncStatusProvider`, `TrashProvider`, `CatalogProvider`, `SessionLogProvider`) and add `sign_in_coordinator.dart`.

- [ ] **Step 2: LoginScreen sign-up link** (~line 405): in detour mode the result must bubble up:

```dart
onPressed: () async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        builder: (_) => SignUpScreen(popOnSuccess: widget.popOnSuccess)),
  );
  if (widget.popOnSuccess && ok == true && context.mounted) {
    Navigator.of(context).pop(true);
  }
},
```

- [ ] **Step 3: SignUpScreen `_signUp()` success** (~line 120): replace `pushAndRemoveUntil` with mode-dependent navigation:

```dart
if (widget.popOnSuccess) {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => EmailConfirmationScreen(
        email: _emailController.text.trim(),
        popOnSuccess: true,
      ),
    ),
  );
  if (ok == true && mounted) Navigator.of(context).pop(true);
} else {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) =>
          EmailConfirmationScreen(email: _emailController.text.trim()),
    ),
    (route) => false,
  );
}
```

- [ ] **Step 4: EmailConfirmationScreen.** Add `final bool popOnSuccess;` (default false). Three exits change when `popOnSuccess`:
  - Polling success (~line 66-83): after `autoSignInAfterConfirmation`, in detour mode run the coordinator then pop:

```dart
if (widget.popOnSuccess) {
  if (success) {
    final userId = _authProvider.userId;
    if (userId != null && mounted) {
      await SignInCoordinator.of(context).onSignedIn(userId);
    }
    if (mounted) Navigator.of(context).pop(true);
  } else if (mounted) {
    Navigator.of(context).pop(false);
  }
} else {
  // existing pushAndRemoveUntil(LoadingScreen / LoginScreen) unchanged
}
```

  - Countdown timeout (~line 48-55): `if (widget.popOnSuccess) { Navigator.of(context).pop(false); } else { existing pushReplacement }`.
  - 'Go back to login' button (~line 118): same split — detour pops `false`.

- [ ] **Step 5: Run full suite + analyzer** — `./scripts/run_tests.sh` and `flutter analyze lib/presentation/screens/auth_flow`. Expected: pass, no errors.
- [ ] **Step 6: Commit** — `git commit -am "feat(auth): detour mode (popOnSuccess) through login/signup/email-confirmation"`

---

### Task 9: LoadingScreen routing + LoginScreen guest button

**Files:**
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`, `login_screen.dart`

- [ ] **Step 1: LoadingScreen.** Replace `_initializeApp`/`_loadData` with three-way routing through the coordinator (settings init stays here — spec §2):

```dart
Future<void> _initializeApp() async {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);

  await Future.wait([
    _loadData(),
    Future.delayed(const Duration(seconds: 1)),
  ]);
  if (!mounted) return;

  if (authProvider.isAuthenticated && !authProvider.isEmailConfirmed) {
    await authProvider.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => const LoginScreen(showEmailConfirmationMessage: true),
    ));
    return;
  }

  if (authProvider.isAuthenticated || await GuestModeStore.isEnabled()) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootScreen()));
  } else {
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }
}

Future<void> _loadData() async {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  await authProvider.init();

  if (!mounted) return;
  await Provider.of<SettingsProvider>(context, listen: false).init();
  if (!mounted) return;

  final coordinator = SignInCoordinator.of(context);
  if (authProvider.isAuthenticated && authProvider.isEmailConfirmed) {
    final userId = authProvider.userId;
    if (userId != null) await coordinator.initForUser(userId);
  } else if (await GuestModeStore.isEnabled()) {
    await coordinator.initForGuest();
  }
}
```

Mind the unconfirmed-email case: no provider init happens for it (matches today, where init ran but the user was immediately signed out — initializing first then signing out left half-initialized providers; routing on `isEmailConfirmed` before init is the cleaner equivalent). Drop now-unused imports.

- [ ] **Step 2: LoginScreen guest button.** Below the sign-up `Row` (~line 422), add (hidden in detour mode):

```dart
if (!widget.popOnSuccess) ...[
  const SizedBox(height: 8),
  TextButton(
    onPressed: () async {
      await GuestModeStore.enable();
      if (!mounted) return;
      await SignInCoordinator.of(context).initForGuest();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootScreen()));
    },
    child: Text('Continue as guest', style: context.bodyLarge),
  ),
],
```

- [ ] **Step 3: Run suite + analyze; manually boot the app** (`flutter run` or the /verify flow): cold start unauthenticated → login screen → Continue as guest → home with default catalog. Restart → straight to home.
- [ ] **Step 4: Commit** — `git commit -am "feat(auth): guest routing on cold start + continue-as-guest button"`

---

### Task 10: Gate the catalog mutation sites

**Files:**
- Modify: `new_session_screen.dart:95` (`_save`) and `:201` (`_saveWorkoutToCatalog`), `new_workout_screen.dart:~130` (save method), `new_exercise_screen.dart:~225` (save method), `catalog_screen.dart:~100` (`_moveToTrash`)

**The rule (spec §4):** gate only where the mutation persists — inside/ahead of the `persistToProvider == true` branch, and for `NewSessionScreen` only modes `create`/`editCatalog`. Nested editors (`persistToProvider: false`) and active-session edits (`editActive`/`editBeforeStart`) never gate. Place the gate BEFORE the `copyWith` that stamps `userId`, so a mid-save sign-in is picked up.

- [ ] **Step 1: NewSessionScreen `_save()`** — after validation, before building `session`:

```dart
if (widget.mode == NewSessionScreenMode.create ||
    widget.mode == NewSessionScreenMode.editCatalog) {
  final ok = await requireAuth(context,
      message: 'Create a free account to save sessions to your catalog.');
  if (!ok || !mounted) return;
}
```

- [ ] **Step 2: NewSessionScreen `_saveWorkoutToCatalog()`** — after its empty-exercises guard:

```dart
final ok = await requireAuth(context,
    message: 'Create a free account to save workouts to your catalog.');
if (!ok || !mounted) return;
```

- [ ] **Step 3: NewWorkoutScreen save** — at the top of the save method, before the `copyWith`:

```dart
if (widget.persistToProvider) {
  final ok = await requireAuth(context,
      message: 'Create a free account to save workouts to your catalog.');
  if (!ok || !mounted) return;
}
```

- [ ] **Step 4: NewExerciseScreen save** — same pattern, message '…save exercises to your catalog.'

- [ ] **Step 5: CatalogScreen `_moveToTrash`** — first line:

```dart
final ok = await requireAuth(context,
    message: 'Create a free account to customize your catalog.');
if (!ok || !mounted) return;
```

- [ ] **Step 6: Widget test (representative).** Extend `test/presentation/screens/auth_wall_test.dart` OR a new file: pump `NewExerciseScreen(persistToProvider: true)` with `makeCatalogEnv` providers + guest `AuthProvider`, fill the title field, tap save, expect the sheet text; flip to `FakeAuthService(signedIn: true)`, expect no sheet. Also pump with `persistToProvider: false` as guest and expect no sheet on save. If NewExerciseScreen requires more providers than practical, gate-check NewWorkoutScreen instead — one representative test is enough; the other sites follow the identical pattern.

- [ ] **Step 7: Run suite. Commit** — `git commit -am "feat(catalog): auth wall on persisting saves and deletes"`

---

### Task 11: Finish-session post-save prompt

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart:~458-480`

- [ ] **Step 1:** In the finish dialog's save handler, the current code calls `sessionLogData.refreshSelectedSessions(finishedSession);` un-awaited, then snackbar/reset/popUntil. Change to: await the save (guarantees the local write — spec: "logged in background, backgrounding can't lose it"), then prompt guests AFTER the save, then pop home:

```dart
Navigator.of(dialogContext).pop();

await sessionLogData.refreshSelectedSessions(finishedSession);

if (context.mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Session saved to log!')),
  );
  SessionStateProvider().reset();
  WakelockPlus.disable();

  if (!context.read<AuthProvider>().isAuthenticated) {
    // Post-save nudge: the session is already safe locally; any later
    // sign-in claims it. Result deliberately ignored.
    await requireAuth(context,
        message:
            'Session saved on this device. Create a free account to back up your progress.');
  }
  if (context.mounted) {
    Navigator.popUntil(context, (route) => route.isFirst);
  }
}
```

Imports: `auth_provider.dart`, `auth_wall.dart`. (Leave the pre-existing `SessionStateProvider().reset()` oddity alone — out of scope.)

- [ ] **Step 2:** Run suite; manual check in Task 13. Commit — `git commit -am "feat(session): post-save signup nudge for guests"`

---

### Task 12: Guest ProfileScreen + SettingsDrawer

**Files:**
- Modify: `lib/presentation/screens/profile_flow/profile_screen.dart:~30-40`, `settings_drawer.dart` (Data + Account sections, ~lines 195-245)
- Test: `test/presentation/screens/profile_screen_guest_test.dart`

- [ ] **Step 1: Failing widget test:** pump `ProfileScreen` inside `MaterialApp` with providers (`ChangeNotifierProvider<AuthProvider>` with `FakeAuthService(signedIn: false)`, plus `SessionLogProvider` and `SettingsProvider` — check the build for what it watches). Expect `find.text('Create account')` (CTA) and no `CircleAvatar`. Run, verify fails.

- [ ] **Step 2: Implement guest branch.** The chart sections don't read `profile` fields (only the header does), so keep them shared:

```dart
final profile = authProvider.userProfile;
final isGuest = !authProvider.isAuthenticated;
if (!isGuest && profile == null) return const SizedBox.shrink();
```

Header: `isGuest ? const _GuestCtaCard() : Row(/* existing user header */)`. New private widget at the bottom of the file:

```dart
class _GuestCtaCard extends StatelessWidget {
  const _GuestCtaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("You're exploring as a guest", style: context.h3),
          const SizedBox(height: 8),
          Text(
            'Create a free account to back up your sessions and build your own training.',
            style: context.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SignUpScreen(popOnSuccess: true))),
            child: const Text('Create account'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LoginScreen(popOnSuccess: true))),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: SettingsDrawer guest variant.** Read `final isAuthenticated = context.watch<AuthProvider>().isAuthenticated;` in `build`. Then:
  - 'Restore trash' tile: wrap in `if (isAuthenticated)`.
  - 'Sign out' + 'Delete account' tiles: wrap in `if (isAuthenticated) ...[ ... ] else ListTile(leading: const Icon(Icons.login), title: Text('Sign in / Create account', style: context.bodyLarge), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(popOnSuccess: true))))`.
  - 'Clear logs', preferences, ToS/privacy: unchanged (work for guests).

- [ ] **Step 4: Run tests + suite. Commit** — `git commit -am "feat(profile): guest CTA card + guest settings drawer"`

---

### Task 13: Full verification

- [ ] **Step 1:** `./scripts/run_tests.sh` — whole suite green.
- [ ] **Step 2:** `flutter analyze` — no new warnings.
- [ ] **Step 3: Manual end-to-end (emulator/device), in this order:**
  1. Fresh install (or wipe app data) → loading → login screen shows 'Continue as guest'.
  2. Guest → home; catalog shows ONLY stock defaults; profile tab shows CTA card; settings drawer shows no sign-out/restore-trash, has sign-in tile.
  3. Open new-workout editor as guest, add a nested exercise, save the nested exercise (no wall), tap top-level save → wall appears; 'Not now' → still in editor, draft intact.
  4. From the wall: 'Log in' with an existing account → returns to the editor, save succeeds, item lands in catalog (and cloud).
  5. Sign out → local catalog/trash/session files cleared (re-enter guest: stock defaults only, empty log).
  6. Guest again → run a short default session → finish → 'Session saved to log!' + post-save sheet; 'Not now' → home shows the session locally. Kill + relaunch → session still there (guest flag remembered).
  7. Sign in (detour from profile CTA) → session appears in the cloud account with its original date (check Supabase `session_logs.completed_at`).
  8. Full signup detour: wall → Create account → confirm email → auto-sign-in → returns to where the wall was opened, guest flag cleared.
  9. Catalog delete as guest → wall; authed → trash confirmation dialog as before.
- [ ] **Step 4:** Update the spec status line to 'Implemented' and commit any doc touch-ups.

---

## Out of scope (do NOT build)
Premium gating, catalog draft persistence across OS kill, unifying `initForUser` with `initForGuest + onSignedIn`, fixing the pre-existing `SessionStateProvider().reset()` oddity.
