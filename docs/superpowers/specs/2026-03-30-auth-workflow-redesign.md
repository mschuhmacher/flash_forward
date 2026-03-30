# Auth Workflow Redesign: Progressive Authentication

## Context

The current auth workflow has several issues:
- Profile metadata (name, country) is only applied via `applyMetadataToProfile()` inside `autoSignInAfterConfirmation()`, which fails if the user confirms email after the 120-second polling window or from a different device
- Email confirmation uses a fragile polling mechanism instead of Supabase deep links
- Post-auth initialization is duplicated between `LoginScreen` and `LoadingScreen`
- The app requires full authentication before any content is accessible, limiting user acquisition
- No OAuth support (Google/Apple)

This spec redesigns the auth workflow in 4 phases, moving toward a **progressive authentication** model: the app starts open, nudges toward signup at natural value moments, and makes signup as frictionless as possible.

## Phase 1 — Immediate Fixes & Polish

Low-effort fixes to the current architecture.

### 1a. Deep-link email confirmation (replace polling)

The app already registers `io.supabase.flashforward://` and handles `passwordRecovery` events in `main.dart:73-82`. Add handling for email confirmation events in the same `onAuthStateChange` listener.

When Supabase fires a `signedIn` or `tokenRefreshed` event after email confirmation:
1. Check if this is a fresh confirmation (user exists, was previously unconfirmed)
2. Call `applyMetadataToProfile()` to copy metadata to the profiles table
3. Navigate to `LoadingScreen` for standard initialization

This eliminates the 15-second polling mechanism and the password-in-memory dependency entirely.

**Files:** `lib/main.dart`, `lib/services/auth_service.dart`

### 1b. Remove the 120-second timeout

Replace the countdown timer in `EmailConfirmationScreen` with:
- A static "Check your email" message
- A "Resend email" button (with cooldown to prevent spam)
- A "Go to login" button

The screen stays open indefinitely. If the user leaves and comes back, `LoadingScreen` routes them to `LoginScreen` normally.

**Files:** `lib/presentation/screens/auth_flow/email_confirmation_screen.dart`

### 1c. Keep the self-heal in loadUserProfile

The self-heal block we added in `auth_provider.dart:loadUserProfile()` remains as a safety net. It catches edge cases where deep link handling doesn't fire (e.g., user confirms on laptop, then manually logs in on phone days later).

**Files:** Already implemented in `lib/providers/auth_provider.dart`

### 1d. Consolidate post-auth initialization

Currently `LoginScreen` (lines 186-196) and `LoadingScreen` (lines 76-96) both independently initialize `SessionLogProvider` and `PresetProvider`. This should happen in exactly one place.

Change: `LoginScreen.signIn()` navigates to `LoadingScreen` instead of `RootScreen`. `LoadingScreen` handles all provider initialization and routes to `RootScreen`.

**Files:** `lib/presentation/screens/auth_flow/login_screen.dart`, `lib/presentation/screens/auth_flow/loading_screen.dart`

---

## Phase 2 — Streamlined Signup Flow

Reduce signup friction while keeping email confirmation as a blocking gate.

### 2a. Slim the signup wizard to 2 steps

- **Step 1:** Email + password + confirm password + terms/privacy checkbox
- **Step 2:** First name + last name (required for personalization — avatar initial, profile display)

Country, phone number, and marketing consent move to the Profile settings screen as optional fields users can fill in anytime.

**Files:** `lib/presentation/screens/auth_flow/signup_screen.dart`, `lib/presentation/screens/profile_flow/profile_screen.dart`

### 2b. Apply metadata immediately at signup

Since we're simplifying to just name fields, and those are needed before confirmation anyway (for the self-heal fallback), apply them to user metadata during signup as currently done. The deep-link confirmation handler (Phase 1a) or self-heal (Phase 1c) will copy them to the profiles table.

No change needed — current metadata approach works fine with the streamlined wizard.

### 2c. Profile completion nudges

On the profile screen, if optional fields (country, phone) are empty, show a subtle "Complete your profile" card with the missing fields. Not a modal — a visible suggestion within the profile screen.

**Files:** `lib/presentation/screens/profile_flow/profile_screen.dart`

---

## Phase 3 — Open App Experience (Guest Mode)

Allow users to explore the app and use it meaningfully before signing up.

### 3a. Guest mode architecture

When no user is authenticated, the app loads into `RootScreen` with full navigation instead of redirecting to `LoginScreen`.

| Feature | Guest | Authenticated |
|---------|-------|---------------|
| Browse sessions/workouts/exercises catalog | Read-only | Full access |
| Follow sessions | Yes | Yes |
| Log session results (grades, notes) | Yes (local only) | Yes (synced to cloud) |
| Create/edit custom sessions/workouts/exercises | No — signup prompt | Yes |
| Progress/tracking | No — signup prompt | Yes |
| Profile screen | Shows signup/login CTA | Shows profile data |

### 3b. Local-only session logging for guests

`SessionLogProvider` operates in a "local-only" mode when no user is authenticated:
- Same logging interface as authenticated mode
- Writes go to local JSON file only (no sync queue, no Supabase calls)
- Uses a `guest` prefix or separate file to distinguish from authenticated user data

### 3c. Guest data migration on signup

When a guest signs up and completes email confirmation:
1. `LoadingScreen` detects existing local guest session logs
2. Migrates them to the user's cloud account (uploads to Supabase with the new user ID)
3. Clears local guest data after successful migration

This ensures users don't lose the data they accumulated while exploring.

### 3d. Signup prompts at value boundaries

When a guest hits a gated action, show a bottom sheet:
- Brief explanation of the benefit ("Sign up to create custom workouts and track your progress")
- "Sign up" button → signup screen
- "Maybe later" → dismiss

Gated actions: creating/editing catalog items, accessing progress/tracking, any write that would require cloud sync.

### 3e. LoadingScreen changes

Current flow: unauthenticated → `LoginScreen`
New flow: unauthenticated → `RootScreen` (guest mode)

Login/signup screens become accessible from:
- Profile tab (which shows a signup/login CTA for guests)
- Signup prompt bottom sheets at gated actions

### 3f. Navigation after guest signup

After a guest signs up and confirms email:
1. Store the current route/context locally before navigating to signup
2. After successful auth + initialization, navigate back to the stored route
3. The user picks up where they left off, now with full access

**Key files:** `lib/presentation/screens/auth_flow/loading_screen.dart`, `lib/providers/session_log_provider.dart`, `lib/presentation/screens/root_screen.dart`, `lib/presentation/screens/profile_flow/profile_screen.dart`

---

## Phase 4 — OAuth Support (Google & Apple) [Sketch]

This phase is intentionally lighter — exact UX decisions will be made closer to implementation.

### 4a. General approach

- Add "Continue with Google" and "Continue with Apple" buttons on login/signup screens
- Use Supabase's native OAuth support with the existing PKCE flow
- OAuth users skip email confirmation (provider has already verified the email)
- Both redirect via the existing `io.supabase.flashforward://` deep link scheme

### 4b. Required setup

- **Google:** OAuth consent screen + credentials in Google Cloud Console, configured in Supabase dashboard
- **Apple:** Sign in with Apple capability + Service ID, configured in Supabase dashboard
- **Flutter:** `google_sign_in` and `sign_in_with_apple` packages (or Supabase's built-in OAuth flow via browser)

### 4c. Profile handling for OAuth users

OAuth may or may not provide a name. Approach TBD — options include:
- Auto-apply name from OAuth metadata if available
- Prompt for name if missing (one-time screen or profile completion nudge)
- Make first name optional app-wide (use email initial as fallback)

Decision deferred until implementation.

### 4d. Shared post-auth flow

All auth methods (email, Google, Apple) converge on the same post-auth path:
1. Auth completed → session established
2. Navigate to `LoadingScreen`
3. `LoadingScreen` handles initialization (providers, sync, guest data migration)
4. Route to `RootScreen`

### 4e. Guest → OAuth

A guest using "Continue with Google/Apple" follows the same migration path as email signup (Phase 3c). Local guest data is migrated to the new account.

---

## Implementation Order

1. **Phase 1** — Immediate fixes (can be done now, independent of other phases)
2. **Phase 2** — Streamlined signup (depends on Phase 1d for clean initialization)
3. **Phase 3** — Open app / guest mode (largest scope, independent of Phase 2 but benefits from it)
4. **Phase 4** — OAuth (depends on Phase 1d for shared post-auth flow, benefits from Phase 3 for guest→auth transition)

Each phase can be implemented and shipped independently.

## Verification

### Phase 1
- Sign up, wait > 2 minutes, confirm email from a different device, log in on phone → profile should be populated
- Sign up, confirm immediately via deep link → auto-navigates to app with profile populated
- LoginScreen sign-in → goes through LoadingScreen → RootScreen (not directly to RootScreen)

### Phase 2
- Signup wizard has 2 steps only
- Country/phone are accessible from profile settings
- Profile completion card appears when optional fields are empty

### Phase 3
- App launches to RootScreen without authentication
- Guest can browse catalog, follow sessions, log results
- Guest data persists across app restarts (local storage)
- Signup from guest mode migrates local data to cloud account
- Gated actions show signup prompt bottom sheet

### Phase 4
- Google/Apple buttons appear on login/signup screens
- OAuth sign-in creates account and navigates to app
- OAuth user profile is populated with available name data
- Guest → OAuth migration works correctly
