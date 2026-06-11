# Guest Mode (Demo Before Sign-In) — Design

**Date:** 2026-06-11
**Status:** Approved by user (pending spec review)
**Depends on:** caller-wires init refactor (`refactor/preset-provider` branch) — `CatalogProvider.init()` without userId, `refreshAfterSignIn()` seams on `CatalogProvider` and `TrashProvider`.

## Goal

Let users demo the app without an account. Flow: loading screen → login screen (if not authenticated) → "Continue as guest" → home screen. Guests can browse the catalog, run default sessions, and experiment in editors. Persisted mutations (catalog save/delete) and cloud backup of completed sessions require an account.

## Decisions (locked with user)

| Topic | Decision |
|---|---|
| Completed guest session | Saved locally immediately; claimed (pushed to cloud) on any later auth. Never lost, no time pressure. |
| Guest persistence | "Continue as guest" is remembered; subsequent launches go straight to home. Login screen only on first launch or after sign-out. |
| Gate timing | Gate on **save**, not on entry. Guests can open editors and experiment freely. |
| Gate UX | Dismissible bottom sheet: message + [Create account] [Log in] [Not now]. |
| Data claim | Auto-claim guest sessions on **both** signup and login to an existing account. Silent merge; session UUIDs make it collision-free. |
| Auth detour | Auth screens push on top of the nav stack; on success they pop back to the caller with drafts intact. OS-kill during email confirmation loses in-memory drafts — accepted (completed sessions are already safe locally). |
| Profile tab (guest) | "Create an account" CTA card replacing profile details, plus device-local settings that still apply. Settings drawer hides account actions, shows sign-in/create CTA. |
| Premium gating (future) | Out of scope. Constraint: gates are single guard calls at save sites so premium limit checks can stack at the same choke points later. |

## 1. Guest state & cold-start routing

`AuthProvider` gains a persisted guest flag (SharedPreferences key `guest_mode`):

- `bool get isGuest` — flag set and not authenticated.
- `Future<void> enterGuestMode()` — sets flag, notifies.
- Flag cleared on any successful auth (sign-in, auto-sign-in after confirmation) and on sign-out.

`LoadingScreen` routing becomes three-way:

1. Authenticated + email confirmed → `coordinator.initForUser(userId)` → `RootScreen`.
2. Guest flag set → `coordinator.initForGuest()` → `RootScreen`.
3. Neither → `LoginScreen`.

The unconfirmed-email path (sign out, back to login with message) is unchanged.

`LoginScreen` gets a "Continue as guest" button below the existing actions: `enterGuestMode()`, `initForGuest()`, `pushReplacement(RootScreen)`.

## 2. `SignInCoordinator` (new, `lib/features/auth/sign_in_coordinator.dart`)

Plain class (not a ChangeNotifier), constructed with `AuthProvider`, `CatalogProvider`, `TrashProvider`, `SessionLogProvider`, `SyncStatusProvider`, `SettingsProvider`. Three entry points:

- **`initForUser(String userId)`** — the existing four-step wiring (attach `SupabaseSyncService`, `catalog.attachSyncStatus`, `catalog.attachTrashProvider`, init) plus `sessionLog.init(userId:)` and both `processPendingSync()` calls. Replaces the duplicated wiring blocks in `LoadingScreen._loadData` and `LoginScreen._signIn`.
- **`initForGuest()`** — same wiring **minus** `syncStatus.attach(...)`: `sessionLog.init(userId: null)`, `catalog.init(trash:)`. Local-only fallback, the behavior the caller-wires refactor made expected.
- **`onSignedIn(String userId)`** — deferred auth: `syncStatus.attach(SupabaseSyncService(userId:))`, `catalog.refreshAfterSignIn()`, `trash.refreshAfterSignIn()`, `sessionLog.refreshAfterSignIn(userId)` (new, §3), `processPendingSync()`, clear guest flag.

Wiring order is load-bearing (attach before init / before refresh); centralizing it is the point.

## 3. `SessionLogProvider.refreshAfterSignIn(userId)` — seam + claim

New method, completing the seam treatment the other providers already got:

1. Attach `SupabaseSyncService(userId:)`.
2. **Claim**: upsert all locally-stored sessions to the cloud.

Failure semantics match today's offline behavior: a failed claim leaves sessions local; the pending-sync queue retries later; Sentry captures exceptions. Whether the claim reuses the pending-ops queue or enumerates local storage directly is decided at planning stage.

Edge: guest sessions claimed into a different person's account (shared device) — accepted per the auto-claim decision. Planning verifies whether sign-out clears local session storage, which would make this moot.

## 4. The auth wall — `requireAuth`

`Future<bool> requireAuth(BuildContext context, {required String message})` (new widget/helper, `lib/presentation/widgets/auth_wall.dart`):

- Authenticated → resolves `true` immediately.
- Otherwise: dismissible modal bottom sheet with `message` + **Create account** / **Log in** / **Not now**.
- Auth buttons push the existing screens in **detour mode** — a `popOnSuccess: true` flag threaded `LoginScreen` → `SignupScreen` → `EmailConfirmationScreen`. On success the screen calls `coordinator.onSignedIn(userId)` then pops the auth stack back to the caller with `true`. Every other exit (back button, confirmation timeout, "go back to login") pops `false`. Cold-start mode keeps today's `pushReplacement` / `pushAndRemoveUntil(LoadingScreen)` behavior.

### Gate points

The gate follows the existing save-propagation rules: nested editors (`persistToProvider: false`) pop their result up the stack without persisting and are **never** gated; the wall fires once, at the top of the chain, where the mutation actually persists.

| Site | Rule |
|---|---|
| `NewExerciseScreen` / `NewWorkoutScreen` save | Gate inside the `persistToProvider == true` branch only. |
| `NewSessionScreen` save (create + edit) | Always gates (always persists). |
| Catalog delete actions | Gated (deleting a default forks it to a user item — a persisted mutation). |
| Restore screen | Unreachable for guests (settings drawer hides it). |
| Finish-session dialog | **No blocking gate.** Save proceeds locally first; afterwards a guest sees a post-save variant of the sheet: "Session saved on this device. Create a free account to back up your progress." [Create account] [Log in] [Not now]. "Not now" is safe — the session is claimed at whatever later auth happens. |

If `requireAuth` resolves `true` (user authed during the detour), the pending save continues with form state intact. If `false`, the user stays in the editor with the draft.

## 5. Guest profile tab & settings drawer

- `ProfileScreen` (guest): "Create an account" CTA card replacing profile details; buttons reuse the detour flow. Device-local settings that still apply (grade system, weight unit, sound) remain visible.
- `SettingsDrawer` (guest): hide sign-out, delete-account, restore-items; show sign-in / create-account CTA.
- Nav bar label already falls back to "Climber" — no change.

## 6. Out of scope

- Premium/subscription gating (max user sessions/workouts, >1-month graphs). Separate feature; only constraint honored here is the single-guard-call shape at gate sites.
- Draft persistence for catalog editors across OS kill.
- Unifying `initForUser` with `initForGuest + onSignedIn`. Possible later simplification; not now.

## 7. Testing

- **Unit:** coordinator wiring order per entry point (mocked providers); `SessionLogProvider.refreshAfterSignIn` claim incl. failure path; `AuthProvider` guest-flag persistence and clearing.
- **Widget:** `requireAuth` resolves true/false correctly; gated saves show the sheet for guests and not for authed users; nested (`persistToProvider: false`) saves never gate; guest ProfileScreen shows CTA.
- Run via `scripts/run_tests.sh`.
