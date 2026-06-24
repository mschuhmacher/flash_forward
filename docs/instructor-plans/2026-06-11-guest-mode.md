# Instructor Plan: Guest Mode (Demo Before Sign-In)

Source plan: `docs/superpowers/plans/2026-06-11-guest-mode.md`
Spec: `docs/superpowers/specs/2026-06-11-guest-mode-design.md`
Branch: `develop`

**Test runner:** always `./scripts/run_tests.sh <file>` — never raw `flutter test`.

**Help levels:** every task starts in **default** mode (Socratic — no code from me). You escalate per-task with `/hint` (concept + where, no code), `/answer` (approach + tiny fragment), `/fullanswer` (I take over). Escalation never carries to the next task.

---

## Task Summary

- [x] Task 1 of 13: GuestModeStore — the persisted guest flag
- [x] Task 2 of 13: Make AuthProvider's service injectable + a fake for tests
- [x] Task 3 of 13: Preserve session date on claim + a fake sync service
- [x] Task 4 of 13: SessionLogProvider.refreshAfterSignIn — seam + claim
- [x] Task 5 of 13: reset() clears local catalog/trash storage
- [x] Task 6 of 13: SignInCoordinator — the wiring brain
- [x] Task 7 of 13: requireAuth — the auth-wall bottom sheet
- [x] Task 8 of 13: Detour mode through login → signup → confirmation
- [x] Task 9 of 13: Cold-start routing + "Continue as guest" button
- [x] Task 10 of 13: Gate the catalog mutation sites (repetitive)
- [x] Task 11 of 13: Finish-session post-save nudge
- [x] Task 12 of 13: Guest ProfileScreen + SettingsDrawer
- [~] Task 13 of 13: Full verification (automated done; manual walkthrough pending)

---

### [x] Task 1 of 13: GuestModeStore — the persisted guest flag

**Why:** Everything downstream keys off one piece of durable state: "has this person chosen to use the app as a guest?" It has to survive app restarts so a returning guest skips the login screen. Building this first gives every later task something concrete to read and write.

**What (overview):** A small storage helper that can report whether guest mode is on, turn it on, and turn it off — backed by on-device persistence so the answer survives a kill/relaunch. Covered by a unit test.

**Details:**
- New class in `lib/features/auth/guest_mode_store.dart`. It holds no instance state of its own — it's a thin wrapper over the device's key/value store (`SharedPreferences`, the same persistence other parts of the app use for prefs).
- Three behaviours: read the current flag (defaulting to *off* when nothing was ever written), set it on, set it off. All three are asynchronous because the underlying store is.
- Use a single string key, e.g. `guest_mode`. Keep the key private to the class.
- Since there's no instance state, the members can be static (callable without constructing the class). Look at how an existing static helper in the codebase is shaped if you want a reference.
- Test in `test/features/auth/guest_mode_store_test.dart`. In tests, `SharedPreferences` needs a mock backing store seeded before each case — find the one-liner the existing tests use to set initial mock values (grep the test folder for `setMockInitialValues`). Two cases: (1) with an empty store the flag reads as off; (2) after turning it on it reads on, and after turning it off it reads off again.

**Files:** `lib/features/auth/guest_mode_store.dart`, `test/features/auth/guest_mode_store_test.dart`

⚙️ TDD: write the failing test first, watch it fail (compile error is a valid failure), implement, watch it pass, commit.

---

### [x] Task 2 of 13: Make AuthProvider's service injectable + a fake for tests

**Why:** Later tasks (the auth wall, the profile CTA) need to test UI in both signed-in and guest states. Right now `AuthProvider` hard-creates its `AuthService`, which talks to Supabase — untestable without a live backend. Making the service swappable lets tests inject a stand-in. We also clear the guest flag on sign-out here, so a returning real user isn't mistaken for a guest.

**Concept primer:**
- *Dependency injection* — instead of a class building its own collaborator internally, you let the caller pass one in (with a sensible default when they don't). This is what makes the collaborator swappable in tests.
- *Test double / fake* — a stand-in object that mimics a real one's interface but with canned behaviour, so a test doesn't hit the network.

**What (overview):** `AuthProvider` accepts an optional `AuthService` and falls back to building a real one when none is given. Its sign-out path also clears the guest flag from Task 1. A reusable fake `AuthService` exists for tests to control "is this user signed in / email-confirmed?".

**Details:**
- In `auth_provider.dart`: the field currently initialised inline as a fresh `AuthService` becomes a constructor-injected dependency with a default. The public constructor gains an optional named parameter; when the caller omits it, build the real one. Nothing else about the class changes.
- In `signOut()`: clear the guest flag (call into Task 1's store) so signing out of a real account doesn't leave the device in guest mode. Make sure the clear happens regardless of how the rest of sign-out goes.
- New fake in `test/support/fake_auth_service.dart`: a subclass of the real `AuthService` that overrides just the two read methods the UI cares about — whether a user is signed in, and whether their email is confirmed — returning values you set via its constructor. Before writing it, open `auth_service.dart` and confirm the exact names and return types of those two methods so your overrides match. The real `AuthService` only touches the Supabase global *inside* its methods, so constructing a subclass in a test is safe even though Supabase isn't initialised.
- No new unit test file for the AuthProvider change itself — the sign-out flag-clearing is glue over an already-tested store and gets covered in the manual run-through (Task 13). The fake is exercised by later tasks. Just make sure the project still compiles/analyses cleanly.

**Files:** `lib/features/auth/auth_provider.dart`, `test/support/fake_auth_service.dart`

---

### [~] Task 3 of 13: Preserve session date on claim + a fake sync service

**Why:** When a guest later signs in, their locally-saved sessions get pushed to the cloud ("claimed"). Each claimed session must keep the date it actually happened, not the date of the sign-in. The cloud-logging method currently stamps "now", so we give it an optional explicit timestamp. We also build a fake sync service here — the shared test double that stands in for all Supabase calls in later tasks.

**Concept primer:**
- *Optional parameter with a fallback* — add a parameter that, when omitted, preserves today's behaviour (stamp "now"); when provided, uses the caller's value.

**What (overview):** The cloud session-logging method accepts an optional completion timestamp and uses it (falling back to "now"). A reusable fake `SupabaseSyncService` exists that records what it was asked to claim and can return canned cloud data, without any network.

**Details:**
- In `supabase_sync_service.dart`, the method that logs a completed session to the cloud (`logCompletedSession`) gains an optional `completedAt` (a `DateTime?`). Where it currently computes the timestamp from "now", prefer the passed value when present. This timestamp is used in two places in that method — the inserted row and the offline-retry queue entry — make sure both use the same resolved value so a retried claim still carries the right date.
- While you're there, confirm (don't assume) that the offline-retry path for a logged session already replays its stored `completedAt` — it should, since the queued operation carried that field before this change.
- New fake in `test/support/fake_supabase_sync_service.dart`: a subclass of `SupabaseSyncService` that overrides every network method the guest flows touch — logging a completed session, and the fetch methods for logged sessions, user sessions/workouts/exercises, and trash entries. It should record the sessions (and the completedAt values) it was asked to log into public lists a test can inspect, expose settable lists for the canned cloud data each fetch returns, and have a switch to simulate the log call throwing (so the "claim fails offline" test can use it). Construct it with a dummy userId. Check the import path for the trash-entry model before writing it.
- TDD note: this task has no dedicated test of its own; its correctness is proven by Task 4's tests, which lean on this fake. After the changes, run the **whole** suite — the signature change could ripple into existing sync tests.

**Files:** `lib/core/sync/supabase_sync_service.dart`, `test/support/fake_supabase_sync_service.dart`

---

### [x] Task 4 of 13: SessionLogProvider.refreshAfterSignIn — seam + claim

**Why:** This is the heart of "nothing you did as a guest is lost." When a guest signs in, this method attaches the real cloud service, pushes every locally-stored session up to that account (the *claim*), then reloads so an existing account's history shows. Other providers already have a `refreshAfterSignIn` seam; the session log is the one that's missing it.

**Concept primer:**
- *Seam* — a deliberately-placed hook where deferred wiring happens. The catalog and trash providers already expose one; you're adding the matching one here so a single coordinator (Task 6) can drive them all the same way.

**What (overview):** A new method on `SessionLogProvider` that takes a cloud service, claims all local sessions to it (preserving each one's real completion date, and not letting a failed push abort the rest), then reloads the in-memory list from the cloud. Covered by unit tests.

**Details:**
- New method `refreshAfterSignIn` on `SessionLogProvider`, placed near `reset()`. It receives a `SupabaseSyncService` (the shared one the coordinator will own) and stores it as the provider's service.
- The claim: read all locally-stored sessions (there's already a reader on `SessionLogger`), and for each one call the cloud-log method from Task 3, passing that session's own `completedAt` so the date is preserved. Wrap each push so a failure on one session is captured (Sentry) and swallowed — the service's own retry queue will catch up later, and one bad push must not abort the others or throw out of this method.
- After claiming, reload the in-memory lists from the cloud and refresh the selected-day window — reuse the provider's existing load + calendar-refresh methods rather than re-implementing them.
- Why double-claiming isn't a worry: sign-out wipes local session storage (Task 5 / existing `reset`), so at any sign-in the local file holds only genuine guest-era sessions. (Spec §3/§6.)
- Tests in `test/features/session_log/session_log_provider_refresh_test.dart`. `SessionLogger` is file-backed via `path_provider`, so you must route it to a temp directory — the catalog test kit has a private path-provider fake you can copy the ~8-line shape of. Three cases: (1) a local session gets claimed with its original `completedAt` preserved (assert against the fake's recorded lists); (2) after refresh the in-memory list reflects the fake's canned cloud sessions; (3) when the claim is set to throw, the method still completes and the reload still happens. `Nullable` (the wrapper `copyWith` uses for the date) lives in `lib/core/nullable.dart`.

**Files:** `lib/features/session_log/session_log_provider.dart`, `test/features/session_log/session_log_provider_refresh_test.dart`

---

### [x] Task 5 of 13: reset() clears local catalog/trash storage

**Why:** This closes a real bug the spec found (§6). Sign-out clears the in-memory catalog and trash but leaves their *local files* on disk. Today that's invisible, because the only post-sign-out path reloads from the cloud. But a guest loads from those local files — so a guest on a device where someone signed out would see the previous user's custom items. Clearing the files on reset prevents that leak.

**What (overview):** `CatalogProvider.reset()` and `TrashProvider.reset()` additionally delete their on-disk local stores, and the sign-out / delete-account flows await these now-async resets. Covered by a unit test.

**Details:**
- `CatalogProvider.reset()` currently clears in-memory lists and is synchronous. It becomes asynchronous and also deletes the local preset files — there's already a `PresetLogger` method that deletes all user preset files; reuse it.
- `TrashProvider.reset()` similarly becomes asynchronous and clears its local trash store — the `TrashService` already has a clear method. Only clear *local*; cloud trash belongs to the account and isn't ours to wipe here.
- Both resets switch from returning nothing-synchronously to returning a future. Find every caller (`grep` for `.reset()` across `lib` and `test`) and make sure the ones that should wait now await — specifically the sign-out and delete-account handlers in `settings_drawer.dart`. Update any test call sites the grep turns up.
- Test in `test/features/catalog/reset_clears_local_storage_test.dart`, using `makeCatalogEnv()` from the test kit (it backs the catalog and trash with a real temp directory). Two cases: (1) after saving a user session then calling catalog reset, loading from local returns empty; (2) after moving an item to trash then calling trash reset, re-reading the trash from disk returns empty. Import `TrashKind` from its model file; if `upsertSession` needs a UUID-shaped id, mirror what existing catalog tests do.

**Files:** `lib/features/catalog/catalog_provider.dart`, `lib/features/catalog/trash_provider.dart`, `lib/presentation/screens/profile_flow/settings_drawer.dart`, `test/features/catalog/reset_clears_local_storage_test.dart`

---

### [x] Task 6 of 13: SignInCoordinator — the wiring brain

**Why:** The four-step provider wiring (attach cloud service → plug catalog into sync + trash → init) is currently copy-pasted in two screens, and the new deferred-sign-in path needs a third variant. Centralising all three in one class removes the duplication and gives every entry point (cold start, guest start, mid-task sign-in) one well-ordered place to call. The wiring order is load-bearing: attach must happen before init/refresh.

**Concept primer:**
- *Coordinator* — a plain (non-widget, non-provider) class that orchestrates several providers in the right order. It holds references to them but owns no UI.
- *Factory constructor* — an alternate constructor that builds the object from something else; here, a `.of(context)` that pulls the providers out of the widget tree so call sites stay one-liners.
- *Function-typed parameter* — passing a function as a constructor argument (here, "given a userId, make a sync service") so tests can substitute a fake instead of a real Supabase-backed one.

**What (overview):** A new `SignInCoordinator` class with three entry points — one for an already-authenticated cold start, one for a guest cold start (no cloud service; local-only), and one for deferred sign-in (attach, then drive the three `refreshAfterSignIn` seams, then clear the guest flag). Covered by unit tests for the guest-init and deferred-sign-in paths.

**Details:**
- New class in `lib/features/auth/sign_in_coordinator.dart`. Constructor takes the four providers it wires — catalog, trash, session-log, sync-status — plus an optional function that turns a userId into a `SupabaseSyncService` (default: build the real one; tests pass one that returns the fake). Also give it a `.of(context)` factory that reads the four providers from the widget tree.
- `initForUser(userId)` — the existing four-step wiring: build+attach the service onto sync-status, plug the catalog into sync-status and trash, init the session log with the userId, init the catalog with trash, then process any pending sync on both. This replaces the duplicated blocks in the loading and login screens (you'll swap those over in Tasks 8–9).
- `initForGuest()` — the same shape **minus** the service attach and the pending-sync calls: still plug the catalog into sync-status and trash (an unattached sync-status *is* the local-only state — see its doc comment), init the session log with no userId, init the catalog with trash.
- `onSignedIn(userId)` — the deferred path: build+attach the service, then call `refreshAfterSignIn` on catalog, trash, and session-log (the last one takes the service you just built — that's the seam from Task 4), then process pending sync, then clear the guest flag (Task 1).
- Known, acceptable asymmetry: `initForUser` lets the session-log build its own service internally (today's behaviour), while `onSignedIn` shares one explicitly. Don't try to unify them — out of scope.
- Tests in `test/features/auth/sign_in_coordinator_test.dart`, using `makeCatalogEnv()` for catalog+trash+sync-status and a fresh `SessionLogProvider`, plus the fake sync service via the factory parameter. Two cases: (1) `initForGuest` leaves sync-status with no service attached yet still initialises catalog and session-log — and the factory must NOT be called (have the test's factory fail if invoked); (2) `onSignedIn` attaches the fake, surfaces the fake's canned cloud user-session in the catalog, and clears the guest flag. Note the catalog's public list getter is `presetSessions` (merged defaults+user items) — there is no `userSessions` getter. Use a UUID-shaped id for the canned session so the catalog's slug-healing doesn't re-id it. (`makeCatalogEnv` already attaches the trash provider; the coordinator attaches again — harmless, idempotent.)

**Files:** `lib/features/auth/sign_in_coordinator.dart`, `test/features/auth/sign_in_coordinator_test.dart`

---

### [x] Task 7 of 13: requireAuth — the auth-wall bottom sheet

**Why:** This is the gate guests hit when they try to do something that needs an account. One reusable function keeps every gate site a single call, and shapes the choke point so the future premium-limit checks can stack at the same spot.

**Concept primer:**
- *Modal bottom sheet that returns a value* — a sheet that slides up, and when dismissed hands back which button the user tapped (or nothing if they tapped away).
- *Async navigation result* — pushing a screen and `await`-ing what it eventually pops back, so this function can resolve true/false based on whether the user actually signed in.

**What (overview):** An async `requireAuth(context, message:)` that returns true immediately if already authenticated; otherwise shows a dismissible sheet (message + Create account / Log in / Not now). Choosing an auth action runs the existing auth screens in "detour mode" and resolves true only if the user actually signs in; any dismissal resolves false. Covered by widget tests.

**Details:**
- New helper in `lib/presentation/widgets/auth_wall.dart`, a top-level async function returning `Future<bool>`.
- Fast path: if the auth provider reports authenticated, return true without showing anything.
- Otherwise show a modal bottom sheet with the passed message and three choices: Create account, Log in, Not now (and tapping the scrim to dismiss behaves like Not now). Model the three outcomes however you like — a small private enum for the two real actions, with null meaning dismissed, is one clean way.
- If the user picked an auth action, push the corresponding existing screen (signup or login) in **detour mode** and await its boolean result; return that (treating null/false as "didn't sign in"). Detour mode is a flag those screens will gain in Task 8 — for *this* task, just add the bare flag to both screens' constructors (default off) so this file compiles; you wire the actual behaviour next task. Guard against using a `context` after an await when the widget's gone.
- Style the sheet to match the app — look at an existing sheet/dialog for colours and text styles rather than raw defaults.
- Tests in `test/presentation/screens/auth_wall_test.dart`. Build a tiny host widget with a button that calls `requireAuth` and captures the returned future, wrapping it in a provider that supplies an `AuthProvider` built with the Task 2 fake. Two cases: (1) fake signed-in → tapping the button shows no sheet and the future resolves true; (2) fake guest → the sheet appears with the message and the three button labels, and tapping Not now resolves the future false.

**Files:** `lib/presentation/widgets/auth_wall.dart`, `test/presentation/screens/auth_wall_test.dart`

---

### [x] Task 8 of 13: Detour mode through login → signup → confirmation

**Why:** When a guest signs in *mid-task* (from the wall), they must land back exactly where they were, with their draft intact — not get bounced to a fresh home screen as the cold-start flow does. "Detour mode" is a flag threaded through the three auth screens that swaps "replace the whole stack" for "pop back to whoever opened me, reporting success."

**Concept primer:**
- *Returning a value through `Navigator.pop`* — a pushed screen can hand a result back to its pusher when it pops; that's how the wall learns whether sign-in succeeded.
- *Threading a flag* — each screen passes the detour flag to the next one it pushes, so the whole login→signup→confirmation chain agrees on which mode it's in.

**What (overview):** Login, signup, and email-confirmation screens each accept a `popOnSuccess` flag. In cold-start mode they behave exactly as today (replace the navigation stack, route through loading/home). In detour mode, on successful sign-in they run the coordinator's deferred-sign-in path and pop back to the caller reporting success; every non-success exit pops reporting failure.

**Details:**
- All three screens (`login_screen.dart`, `signup_screen.dart`, `email_confirmation_screen.dart`) gain a `popOnSuccess` boolean constructor flag, default off. (Login and signup already got the bare flag in Task 7; now give it meaning.)
- **Login** success handler: today it does the four-step wiring inline and pushes home. Replace the inline wiring with a call to the coordinator (Task 6). In cold-start mode keep "init for user, then replace into home." In detour mode call the coordinator's deferred-sign-in path and pop back `true`. Also: the screen's "Sign up" link should carry the same flag onward, and when a detour-mode signup eventually succeeds, the login screen should bubble that success up by popping `true` too. Remove the now-unused imports the inline wiring needed; add the coordinator import.
- **Signup** success handler: today it replaces the stack with the confirmation screen. In detour mode, push the confirmation screen (also in detour mode) and await its result, popping `true` upward when it succeeds; in cold-start mode keep today's stack-replace.
- **Confirmation** screen has three exits — polling detects confirmation (auto sign-in), the resend countdown runs out, and the "go back to login" button. In cold-start mode all three keep today's behaviour (route through loading/login). In detour mode: on confirmed+signed-in, run the coordinator's deferred path then pop `true`; on the timeout and the back button, pop `false`.
- No automated test — these chains run through Supabase-coupled screens. Verified by hand in Task 13. Keep the edits mechanical and lean on `flutter analyze` plus the full suite to catch breakage.

**Files:** `lib/presentation/screens/auth_flow/login_screen.dart`, `signup_screen.dart`, `email_confirmation_screen.dart`

---

### [ ] Task 9 of 13: Cold-start routing + "Continue as guest" button

**Why:** This is where guest mode becomes reachable and sticky. The loading screen learns a third route (guest → home), and the login screen gets the button that enters guest mode. Together with the persisted flag, a returning guest now boots straight to home.

**What (overview):** The loading screen routes three ways at cold start — authenticated→home, remembered-guest→home, otherwise→login — driving provider init through the coordinator. The login screen gains a "Continue as guest" button that enables the flag, runs guest init, and goes home. (Settings init stays on the loading screen.)

**Details:**
- **Loading screen:** rework its init so that after auth-state is known it picks one of three routes. Keep the existing unconfirmed-email handling (sign out → login with the "please confirm" banner). Then: if authenticated *or* the guest flag is set, go to the root/home screen; otherwise go to login. The data-loading half should call the coordinator's `initForUser` when authenticated-and-confirmed, or `initForGuest` when the guest flag is set, and do neither otherwise. Settings init stays here (it runs once regardless of route — spec §2), not in the coordinator. Note a subtlety vs. today: route on email-confirmed *before* initialising providers for that case, so you don't half-init providers for a user you're about to sign out. Drop imports the old inline wiring needed.
- **Login screen:** add a "Continue as guest" button (below the existing sign-up row). It enables the guest flag (Task 1), runs the coordinator's `initForGuest`, then replaces into the root/home screen. Hide this button when the login screen is in detour mode (a guest opening the wall is already a guest — backing out is their "not now"). Mind the across-await `mounted`/`context` checks.
- No new automated test; exercise it in the Task 13 manual run-through (and you can smoke it now with `flutter run`). Run the suite + analyzer to confirm nothing broke.

**Files:** `lib/presentation/screens/auth_flow/loading_screen.dart`, `lib/presentation/screens/auth_flow/login_screen.dart`

---

### [ ] Task 10 of 13: Gate the catalog mutation sites (repetitive)

**Why:** This is the actual gating — the points where a guest's action would persist a change get wrapped in the auth wall. The rule (spec §4) is precise: gate only where the mutation *persists*, never on nested editors that just pop their result up, and never on active-session edits. Placement matters more than the call itself.

**What (overview):** Each persisting save/delete site calls `requireAuth` before committing, bailing out (staying on screen, draft intact) if the user declines. Nested-editor saves and active-session edits are left untouched. One representative widget test proves a guest sees the wall and a signed-in user doesn't.

**Details — the five sites:**
1. **NewExerciseScreen** save — gate only inside the branch that actually persists to the provider (the `persistToProvider == true` path); a nested exercise editor (flag off) must not gate. Put the guard before the code that stamps the user id, so a mid-save sign-in is reflected.
2. **NewWorkoutScreen** save — same pattern, same `persistToProvider` condition.
3. **NewSessionScreen** main save — gate only for the catalog-bound modes (create / edit-catalog), not for the active-session edit modes.
4. **NewSessionScreen** save-workout-to-catalog — gate after its existing empty-exercises guard.
5. **CatalogScreen** move-to-trash — gate as the first thing in the handler (deleting a stock default forks it into a user item, which is a persisted mutation).

In every case: if the wall resolves false, return early without persisting or popping; if it's been awaited, re-check `mounted` before using context. Each guard is the same one-line `requireAuth(...)` call with a site-appropriate message — keep them a single call so future premium checks can stack there.

**Test:** one representative widget test (extend the auth-wall test file or add a new one): pump the exercise editor (persist flag on) with the `makeCatalogEnv` providers and a *guest* auth provider, fill the title, tap save, expect the wall's text; then with a signed-in fake, expect no wall; then pump with the persist flag *off* as a guest and confirm save does **not** gate. If the exercise editor needs an awkward number of providers, do the representative test on the workout editor instead — one is enough; the others follow the identical pattern.

⚡ **First of 5 — do site #1 (NewExerciseScreen) yourself, plus the representative test.** After your review passes, I'll apply the same guard to the other four sites (adapting placement per the notes above) and report back. That's the repetitive-handoff part — the guard is identical, only the placement differs.

**Files:** `new_exercise_screen.dart`, `new_workout_screen.dart`, `new_session_screen.dart`, `catalog_screen.dart`, and the chosen test file.

---

### [ ] Task 11 of 13: Finish-session post-save nudge

**Why:** Finishing a session is special: the session is *always* saved locally first (so backgrounding/kill can't lose it), and only then is a guest nudged to make an account to back it up. The save must not be gated — only followed by an optional prompt. This is the "save locally, claim later" decision made concrete.

**What (overview):** The finish-session handler awaits the local save first, then — only for a guest — shows the auth wall with a "saved on this device, create an account to back it up" message, then returns home. Declining is always safe; the session is claimed at whatever later sign-in happens.

**Details:**
- In `session_active_bottom_bar.dart`, the finish-dialog save handler currently fires the save without awaiting, then snackbars/resets/pops home. Change it to **await** the save (guaranteeing the local write completes), then keep the snackbar/reset, then — if the user is *not* authenticated — show the auth wall with the back-up-your-progress message. Ignore the wall's result deliberately (the session is already safe either way), then pop home.
- The prompt is *after* the save, not a gate on it — order matters. Guard the context across the awaits as usual.
- Leave the pre-existing oddity where a throwaway `SessionStateProvider` gets reset — that's out of scope, don't touch it.
- No automated test; covered in the Task 13 manual run.

**Files:** `lib/presentation/screens/session_flow/session_active_bottom_bar.dart`

---

### [ ] Task 12 of 13: Guest ProfileScreen + SettingsDrawer

**Why:** The profile tab is a natural conversion surface and the settings drawer exposes account actions that make no sense for a guest. Guests get a "create an account" call-to-action instead of an empty profile, and the drawer hides sign-out / delete / restore-trash while offering a sign-in entry.

**What (overview):** For a guest, the profile screen shows a CTA card in place of the user header (charts stay shared); the settings drawer hides account-only actions and shows a sign-in/create entry instead. A widget test confirms the guest profile shows the CTA and not the user header.

**Details:**
- **ProfileScreen:** today it bails out entirely when there's no profile. Instead, detect the guest case (not authenticated) and render a CTA card where the signed-in user header would go — the chart sections below don't read profile fields, so keep them shared between guest and user. The CTA card: a short headline + blurb + a "Create account" button (pushes signup in detour mode) and a "Sign in" link (pushes login in detour mode). A small private widget for the card keeps the build readable.
- **SettingsDrawer:** read the authenticated flag in build. Hide "Restore trash", "Sign out", and "Delete account" for guests; in their place show a single "Sign in / Create account" entry that pushes login in detour mode. Leave preferences, "Clear logs", and the ToS/privacy links visible — they work for guests too.
- Test in `test/presentation/screens/profile_screen_guest_test.dart`: pump the profile screen with a guest auth provider (and whatever providers its build watches — check the build), expect the "Create account" CTA present and the user header (e.g. the avatar) absent. Write it failing first.

**Files:** `lib/presentation/screens/profile_flow/profile_screen.dart`, `lib/presentation/screens/profile_flow/settings_drawer.dart`, `test/presentation/screens/profile_screen_guest_test.dart`

---

### [ ] Task 13 of 13: Full verification

**Why:** Tie it together and prove the whole flow end-to-end — automated suite, analyzer, and a scripted manual run that walks every branch a real guest would hit.

**What (overview):** Green suite, clean analyzer, and a hands-on device/emulator walkthrough covering guest entry, gating, the detour, sign-out clearing, local session survival across kill, and the claim landing in the cloud with the right date.

**Details:**
- Run the whole suite via the script; run `flutter analyze` and confirm no new warnings.
- Manual walkthrough on device/emulator, in order:
  1. Fresh install (or wipe data) → loading → login shows "Continue as guest".
  2. Guest → home; catalog shows only stock defaults; profile tab shows the CTA; drawer has no sign-out/restore-trash, has a sign-in entry.
  3. Open the new-workout editor as a guest, add a nested exercise, save the nested exercise (no wall), then top-level save → wall appears; Not now → still in the editor, draft intact.
  4. From the wall: Log in with an existing account → returns to the editor, save succeeds, item appears in catalog (and cloud).
  5. Sign out → local catalog/trash/session files cleared (re-enter guest: stock defaults only, empty log).
  6. Guest again → run a short default session → finish → "saved to log" + the post-save sheet; Not now → home shows the session locally. Kill + relaunch → session still there (guest remembered).
  7. Sign in via the profile CTA → the session appears in the cloud account with its original date (check `session_logs.completed_at` in Supabase).
  8. Full signup detour: wall → Create account → confirm email → auto sign-in → returns to where the wall was opened, guest flag cleared.
  9. Catalog delete as a guest → wall; as a signed-in user → the normal trash-confirmation dialog.
- Finally, flip the spec's status line to "Implemented" and commit any doc touch-ups.

**Files:** verification only (plus a spec status touch-up).
