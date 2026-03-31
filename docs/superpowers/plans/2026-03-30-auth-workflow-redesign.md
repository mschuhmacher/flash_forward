# Auth Workflow Redesign — Implementation Plan

> **Execution model:** You (Michiel) implement each task. After completing a task, ask Claude to verify the output before moving to the next.

**Goal:** Progressively improve the auth workflow from bug fixes through guest mode and OAuth support.

**Spec:** `docs/superpowers/specs/2026-03-30-auth-workflow-redesign.md`

---

## Phase 1 — Immediate Fixes & Polish

### Task 1.1: Consolidate post-auth initialization

**Goal:** All post-auth provider initialization happens in `LoadingScreen` only. `LoginScreen` stops initializing providers and just navigates to `LoadingScreen`.

**Files:**
- Modify: `lib/presentation/screens/auth_flow/login_screen.dart`
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`

**What to do:**
- [ ] In `LoginScreen._signIn()` (lines 183-203): remove the `SessionLogProvider` and `PresetProvider` init calls. On success, navigate to `LoadingScreen` instead of `RootScreen`.
- [ ] Remove the `SessionLogProvider` and `PresetProvider` imports from `login_screen.dart` if no longer used.
- [ ] Verify `LoadingScreen._loadData()` already covers the same initialization (it does — lines 76-96).
- [ ] Test: sign in from `LoginScreen` → should go through `LoadingScreen` splash → land on `RootScreen` with all data loaded.
- [ ] Commit.

**Watch out for:**
- `LoginScreen` currently navigates with `pushReplacement`. `LoadingScreen` also uses `pushReplacement` to go to `RootScreen`. The stack should end up with just `RootScreen` — verify there's no double-push or back-button issue.

---

### Task 1.2: Deep-link email confirmation

**Goal:** When a user clicks the confirmation link in their email, the app detects it via `onAuthStateChange` and handles it — no more polling needed.

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/providers/auth_provider.dart`

**What to do:**
- [ ] In `main.dart` `_MyAppState.initState()` (lines 73-82): expand the `onAuthStateChange` listener to also handle email confirmation events. Supabase fires `signedIn` when a user clicks a confirmation magic link. When detected and the user has no `firstName` in their profile, call `applyMetadataToProfile()` via `AuthProvider`, then navigate to `LoadingScreen`.
- [ ] You need access to `AuthProvider` from the listener. Use `_navigatorKey.currentContext` to get the provider, or pass it in another way that works with your architecture.
- [ ] The tricky part: distinguishing a confirmation deep link from a normal sign-in. Check `data.session != null` and whether the user's profile still has a null `firstName` — the self-heal in `loadUserProfile` will handle it regardless, so this handler just needs to navigate to `LoadingScreen`.
- [ ] Test: sign up → on `EmailConfirmationScreen` → click the confirmation link from email → app should navigate to `LoadingScreen` → `RootScreen` with profile populated.
- [ ] Test: sign up → close the app entirely → click confirmation link → app opens to `LoadingScreen` → `RootScreen` with profile populated.
- [ ] Commit.

**Watch out for:**
- The `onAuthStateChange` listener fires for many events (initial session, token refresh, etc.). Be selective — don't re-navigate on every event. A good guard: only act when `data.event == AuthChangeEvent.signedIn` and the app is currently showing `EmailConfirmationScreen` or `LoginScreen`.
- The existing `passwordRecovery` handling must continue to work.

---

### Task 1.3: Simplify EmailConfirmationScreen

**Goal:** Remove the 120-second timeout and polling mechanism. The screen becomes a static "check your email" page with a resend button.

**Files:**
- Modify: `lib/presentation/screens/auth_flow/email_confirmation_screen.dart`

**What to do:**
- [ ] Remove `_countdownTimer`, `_pollingTimer`, `_remainingToResend`, and all polling logic.
- [ ] Remove `_startCountdownTimer()` and `_startPollingTimer()` methods.
- [ ] Remove `clearPendingSignupPassword()` from `dispose()` (deep link handles confirmation now).
- [ ] Build a simple screen with: mail icon, "Check your email" title, the email address, a "Resend email" button, a "Go to login" button.
- [ ] The "Resend email" button should call `authProvider.resendConfirmationEmail(email)` with a cooldown (disable button for 60 seconds after press, show countdown on the button text).
- [ ] Test: sign up → see the confirmation screen → button is available → tap resend → button disables for 60 seconds → tap "Go to login" → lands on `LoginScreen`.
- [ ] Commit.

**Watch out for:**
- With the deep link handler from Task 1.2, the user may be on this screen when the deep link fires. The `main.dart` listener will navigate away, so this screen doesn't need to detect confirmation itself.

---

### Task 1.4: Clean up polling remnants in AuthProvider

**Goal:** Remove `_pendingSignupPassword` and related methods now that polling is gone.

**Files:**
- Modify: `lib/providers/auth_provider.dart`
- Modify: `lib/services/auth_service.dart`

**What to do:**
- [ ] Remove `_pendingSignupPassword` field from `AuthProvider`.
- [ ] Remove `pollForEmailConfirmation()`, `clearPendingSignupPassword()`, and `autoSignInAfterConfirmation()` methods.
- [ ] In `signUp()`: remove the line that stores the password (`_pendingSignupPassword = password`).
- [ ] In `AuthService`: remove `checkEmailStatus()` method and the `EmailStatus` enum (if nothing else uses them). Keep `trySignIn()` if it's used elsewhere.
- [ ] Verify the self-heal block in `loadUserProfile()` still works — it uses `_authService.getUserMetadata()`, not the password, so it should be unaffected.
- [ ] Run the app through the full flow: sign up → confirm → log in → profile populated (via self-heal).
- [ ] Commit.

---

### Task 1.5: Phase 1 integration test

**Goal:** Verify the entire Phase 1 flow end-to-end.

- [ ] Sign up with a new account → lands on `EmailConfirmationScreen` (no countdown, just static screen with resend).
- [ ] Click confirmation link in email → app navigates to `LoadingScreen` → `RootScreen` with name populated.
- [ ] Sign out → sign in from `LoginScreen` → goes through `LoadingScreen` → `RootScreen` (not directly to `RootScreen`).
- [ ] Sign up → do NOT confirm → close app → open app → lands on `LoginScreen` with "please confirm" message (existing behavior).
- [ ] Sign up → confirm from laptop browser → open app on phone → log in → profile has name (self-heal path).
- [ ] Commit a version bump or tag if desired.

---

## Phase 2 — Streamlined Signup Flow

### Task 2.1: Slim signup wizard to 2 steps

**Goal:** Signup collects only email/password and first/last name. Country, phone, marketing consent are removed from signup.

**Files:**
- Modify: `lib/presentation/screens/auth_flow/signup_screen.dart`
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/providers/auth_provider.dart`

**What to do:**
- [ ] Redesign the signup wizard from 3 steps to 2:
  - **Step 1:** Email, password, confirm password, terms/privacy agreement (as a checkbox or tappable text, not a separate step)
  - **Step 2:** First name, last name
- [ ] Remove the country picker, phone number field, and marketing consent checkbox from the signup screen.
- [ ] Update `AuthProvider.signUp()` and `AuthService.signUp()` signatures: remove `phoneNumber`, `country`, `marketingConsent` parameters. Still store `firstName` and `lastName` in Supabase user metadata.
- [ ] Update `applyMetadataToProfile()` in `AuthService`: only apply `first_name`, `last_name`, and `app_version_at_signup` (no longer phone/country/marketing since they won't be in metadata).
- [ ] Test: full signup flow works with 2 steps, email confirmation, profile shows name.
- [ ] Commit.

**Watch out for:**
- Don't delete the `profiles` table columns for country/phone/marketing — they'll be populated from the profile settings screen in Task 2.2.
- The `UserProfile` model should keep all fields.

---

### Task 2.2: Add optional profile fields to profile settings

**Goal:** Users can set their country, phone number, and marketing consent from the profile screen.

**Files:**
- Modify: `lib/presentation/screens/profile_flow/profile_screen.dart`
- Possibly create: a profile edit screen or inline editing section

**What to do:**
- [ ] Add editable fields for country, phone number, and marketing consent to the profile screen (or a "Edit profile" sub-screen).
- [ ] Use the existing `AuthProvider.updateProfile()` method to save changes.
- [ ] Reuse the country picker widget from the old signup step 2 (move it to a shared widget if it isn't already).
- [ ] Test: edit country/phone from profile → saves to Supabase → persists on reload.
- [ ] Commit.

---

### Task 2.3: Profile completion nudge

**Goal:** Show a subtle card on the profile screen when optional fields are empty, nudging the user to complete their profile.

**Files:**
- Modify: `lib/presentation/screens/profile_flow/profile_screen.dart`

**What to do:**
- [ ] If `userProfile.country` or `userProfile.phoneNumber` is null/empty, show a card at the top of the profile screen: "Complete your profile" with a list of missing fields and a button to edit.
- [ ] The card should be dismissable (or just naturally disappear once fields are filled).
- [ ] Keep it subtle — not a modal, not an alert. Just a visible suggestion within the normal profile layout.
- [ ] Test: new user sees the card → fills in country → card updates to show only remaining fields → all filled → card disappears.
- [ ] Commit.

---

### Task 2.4: Phase 2 integration test

- [ ] Sign up with 2-step wizard → confirm email → log in → profile shows name.
- [ ] Go to profile screen → see "complete your profile" nudge → add country and phone → nudge disappears.
- [ ] Existing users who already have country/phone should NOT see the nudge.
- [ ] Commit.

---

## Phase 3 — Open App Experience (Guest Mode)

### Task 3.1: Guest-mode routing in LoadingScreen

**Goal:** Unauthenticated users go to `RootScreen` (guest mode) instead of `LoginScreen`.

**Files:**
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`

**What to do:**
- [ ] Change the unauthenticated branch (line 58-62) to navigate to `RootScreen` instead of `LoginScreen`.
- [ ] In the `_loadData()` method: when not authenticated, skip provider initialization that requires a userId. Settings can still init.
- [ ] Test: launch app without being logged in → lands on `RootScreen` with bottom navigation visible.
- [ ] Commit.

**Watch out for:**
- `RootScreen` and its child screens may assume `authProvider.userProfile` is not null. You'll need to handle the null case throughout (Tasks 3.2-3.4 address this).

---

### Task 3.2: Guest-safe providers

**Goal:** `SessionLogProvider` works in local-only mode for guests. `PresetProvider` loads default data without a userId.

**Files:**
- Modify: `lib/providers/session_log_provider.dart`
- Modify: `lib/providers/preset_provider.dart`

**What to do:**
- [ ] `SessionLogProvider`: allow `init()` to be called with `userId: null`. In this mode:
  - Load/save session logs from a separate local file (e.g., `guest_session_log.json`) to avoid mixing with authenticated user data
  - Skip all Supabase calls and sync queue operations
  - The logging interface (add session, get sessions) should work the same
- [ ] `PresetProvider`: allow `init()` to be called with `userId: null`. In this mode:
  - Load default/standard presets only (no user-specific presets from Supabase)
  - Reject create/edit/delete operations (or gate them behind a check)
- [ ] Update `LoadingScreen._loadData()` to call these providers with `userId: null` in the unauthenticated branch.
- [ ] Test: app in guest mode → can browse sessions/presets → can log a session result → data persists in local file → close and reopen app → guest data still there.
- [ ] Commit.

---

### Task 3.3: Guest-safe UI — RootScreen, HomeScreen, ProgramScreen

**Goal:** The main screens work for guests: catalog browsing and session following work, but gated actions show a signup prompt.

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart`
- Modify: screens that assume authentication
- Create: a reusable signup prompt bottom sheet widget

**What to do:**
- [ ] Create a reusable `SignupPromptSheet` widget (bottom sheet) with: a short benefit message, "Sign up" button (→ `SignUpScreen`), "Maybe later" button (dismiss).
- [ ] Audit `RootScreen` and its child screens for places that assume `authProvider.userProfile != null` or `authProvider.userId != null`. Add null guards.
- [ ] For gated actions (create/edit sessions/workouts/exercises, access progress/tracking), show the `SignupPromptSheet` instead of performing the action.
- [ ] The profile tab should show a signup/login CTA for guests instead of profile data.
- [ ] Test: guest can navigate all tabs → browse catalog → follow a session → log results → attempt to create a session → sees signup prompt → tap "Sign up" → goes to signup screen.
- [ ] Commit.

**Watch out for:**
- Don't gate too aggressively. The goal is to let guests use the app meaningfully. Only gate actions that genuinely require an account (creating content, cloud sync, progress tracking).

---

### Task 3.4: Guest profile tab

**Goal:** The profile tab shows a signup/login CTA for guests instead of the normal profile view.

**Files:**
- Modify: `lib/presentation/screens/profile_flow/profile_screen.dart`

**What to do:**
- [ ] When `authProvider.userProfile == null` (guest), show an alternative layout: app logo, tagline, "Sign up" button, "Already have an account? Log in" link.
- [ ] "Sign up" → navigates to `SignUpScreen`.
- [ ] "Log in" → navigates to `LoginScreen`.
- [ ] Keep the existing profile view for authenticated users unchanged.
- [ ] Test: guest taps profile tab → sees signup CTA → taps "Sign up" → completes signup → returns to profile → sees their profile data.
- [ ] Commit.

---

### Task 3.5: Guest data migration on signup

**Goal:** When a guest signs up and confirms email, their local session logs are migrated to their cloud account.

**Files:**
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`
- Modify: `lib/providers/session_log_provider.dart`

**What to do:**
- [ ] In `SessionLogProvider`, add a method like `migrateGuestData(String userId)` that:
  1. Reads the guest session log file (`guest_session_log.json`)
  2. Uploads each session to Supabase with the new userId
  3. Deletes the guest file after successful migration
- [ ] In `LoadingScreen._loadData()`, after initializing `SessionLogProvider` with the authenticated userId, check if a guest session log file exists and call `migrateGuestData()`.
- [ ] Test: use app as guest → log 2-3 sessions → sign up → confirm email → log in → sessions appear in your account → guest file is gone.
- [ ] Test: sign up as a new user with no guest data → no errors, no migration attempted.
- [ ] Commit.

**Watch out for:**
- Migration should be idempotent: if it partially fails and runs again, it shouldn't create duplicates. Consider checking for existing sessions by some identifier before uploading.

---

### Task 3.6: Navigation context preservation

**Goal:** When a guest signs up from a signup prompt, they return to where they were after completing auth.

**Files:**
- Modify: `SignupPromptSheet` widget (or wherever you navigate to signup)
- Modify: `lib/presentation/screens/auth_flow/loading_screen.dart`

**What to do:**
- [ ] Before navigating to the signup screen from a guest context, save a simple route identifier (e.g., which tab index, or which session they were viewing) to a local variable or shared preferences.
- [ ] After successful auth, `LoadingScreen` checks for a saved route and navigates to `RootScreen` with that context (e.g., the right tab selected, or pushing the session detail screen).
- [ ] If no saved route, default to `RootScreen` as usual.
- [ ] Keep this simple — tab index is enough for v1. Deep-linking back to a specific session detail can come later.
- [ ] Test: guest is on Program tab → taps a gated action → signs up → after auth, lands back on Program tab (not Home).
- [ ] Commit.

---

### Task 3.7: Phase 3 integration test

- [ ] Fresh install → app opens to `RootScreen` in guest mode → can browse all tabs.
- [ ] Guest follows a session, logs results → data persists on app restart.
- [ ] Guest tries to create a custom session → signup prompt bottom sheet.
- [ ] Guest taps profile tab → sees signup CTA → signs up → confirms email → logs in → profile shows, guest session data migrated.
- [ ] Returning authenticated user → normal flow, no guest data interference.
- [ ] Commit.

---

## Phase 4 — OAuth Support [Sketch]

> This phase is intentionally lighter. Flesh out during implementation.

### Task 4.1: Supabase OAuth configuration

- [ ] Set up Google OAuth in Google Cloud Console and Supabase dashboard.
- [ ] Set up Apple Sign In in Apple Developer portal and Supabase dashboard.
- [ ] Verify the redirect URL scheme (`io.supabase.flashforward://`) works for OAuth callbacks.

### Task 4.2: OAuth buttons on login/signup screens

- [ ] Add "Continue with Google" and "Continue with Apple" buttons above the email form on both `LoginScreen` and `SignUpScreen`.
- [ ] Use Supabase's `signInWithOAuth()` or native sign-in packages.
- [ ] On success, navigate to `LoadingScreen` (same as email auth — Phase 1 consolidation).

### Task 4.3: OAuth profile handling

- [ ] After OAuth sign-in, check if the profile has a `firstName`.
- [ ] If the OAuth provider returned a name in metadata, apply it automatically.
- [ ] If no name available, decide approach (prompt screen vs. profile nudge vs. email initial fallback). Design decision deferred.

### Task 4.4: Guest → OAuth flow

- [ ] Guest tapping an OAuth button follows the same migration path as email signup (Task 3.5).
- [ ] OAuth users skip email confirmation, so migration happens immediately in `LoadingScreen`.

### Task 4.5: Phase 4 integration test

- [ ] Google sign-in → lands in app with profile populated.
- [ ] Apple sign-in → lands in app with profile populated (or nudge if name hidden).
- [ ] Guest → Google sign-in → guest data migrated.
- [ ] Existing email user → still works as before.
