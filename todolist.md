# Flash Forward — Roadmap

> Current version: **1.1** · Next major: **2.0.0**
>
> Types: `feature` · `bug` · `idea` · `chore`
> Complexity: `low` · `medium` · `high` · `very high`

---

## Full Table

| Name | Type | Description | Version | Complexity |
|------|------|-------------|---------|------------|
| **BUGS & USER-REPORTED ISSUES** | | | | |
| Sign-up: continue button hidden by keyboard | bug | Continue button is obscured by the keyboard during sign-up; no way to dismiss keyboard | 2.0.0 | low |
| Sign-up: name not populated after email confirmation on different device | bug | User's display name fails to populate when the confirmation email is opened on a different device than the one with the app installed; likely a deep-link / session issue | 2.0.0 | medium |
| Home screen: no clear path to create a session | bug | First-time or empty-state users have no obvious call-to-action to create a session; empty state should guide them there | 2.0.0 | low |
| RAM overusage — WatchdogTermination (Sentry) | bug | Sentry reports WatchdogTermination errors indicating excessive RAM usage; needs profiling and fix | 2.0.0 | medium |
| Conflict resolution: local vs. cloud data | bug | No strategy in place for resolving conflicts between locally stored data and Supabase cloud data | backlog | high |
| Offline mode tests | bug | No test coverage for offline behaviour; create integration/unit tests to validate offline flows | backlog | medium |
| Review default exercise time fields (activeTime) | bug | Go through all default/catalog exercises and verify their time values are correct | backlog | low |
| **FEATURES** | | | | |
| App Store Connect: add business name | chore | Add the business name to the App Store Connect account | 2.0.0 | low |
| Supabase health-check cron job | chore | Set up an external cron job that pings the Supabase URL periodically to prevent the project from pausing due to inactivity | backlog | low |
| Add logger package (dev tooling) | chore | Integrate a Flutter logger package for structured local debug logging during development | backlog | low |
| Ask Claude: add `const` for runtime optimisation | chore | Have Claude audit the codebase and add `const` constructors wherever applicable to improve widget rebuild performance | backlog | low |
| Ask Claude: evaluate widget extraction | chore | Have Claude identify UI functions/widgets that should be moved to separate widget files to improve readability | backlog | low |
| Ask Claude: Flutter framework code review | chore | Have Claude cross-reference the codebase against Flutter best practices and flag design issues | backlog | low |
| Edit load in active session screen | feature | Add an edit button on the active session screen that allows the user to adjust the load for the current exercise mid-session | 2.0.0 | medium |
| Separate reps and load per set | feature | Allow each set of an exercise to have its own rep count and load value. Requires a data model change (Set/Map per set). UI: editable rep & load fields per set, add/remove set buttons in ExerciseCard on NewWorkoutScreen | 2.1.0 | high |
| Active session: next / previous set & rep navigation | feature | Add forward and back navigation buttons on the active session screen to move between sets and reps manually | 2.0.0 | medium |
| Edit catalog sessions | feature | Allow users to edit the default/catalog sessions (title, exercises, structure) | 2.0.0 | medium |
| Hide / restore catalog sessions | feature | Allow users to hide catalog sessions from their session list, with the option to restore them from a settings menu (settings menu to be created) | 2.1.0 | medium |
| Onboarding screens | feature | Design and implement onboarding flow for new users covering key app concepts | backlog | high |
| Supersets functionality | feature | Allow exercises to be grouped into supersets within a workout | 2.1.0 | high |
| Remove logged sessions by swiping | feature | User can swipe-to-delete individual logged sessions from their history | 2.1.0 | low |
| Catalog field edit — UI feedback | feature | When a user taps a disabled field (title, label, description) on a catalog exercise/workout, show a clear explanation that it cannot be edited because it is a catalog field. Consider a more intuitive overall UI for displaying vs. editing exercise fields | 2.0.0 | low |
| Catalog propagation | feature | When a change is made to a catalog exercise or workout, prompt the user to propagate that change to existing sessions/workouts that use it; let them select which ones to update | 2.0.0 | high |
| Option: exercise with no fixed time | feature | Allow an exercise to be configured with no set duration; the timer keeps running until the user manually advances to the next exercise | 2.0.0 | medium |
| Supabase deep linking (email confirmation) | feature | Configure deep linking so that tapping the email confirmation link opens the app directly instead of a web page | backlog | medium |
| lbs vs. kg setting | feature | Add a user preference to display and input weight in either kilograms or pounds | 2.0.0 | low |
| Band resistance support | feature | Allow exercises to specify resistance bands as a load type, in addition to numeric weight | 2.0.0 | medium |
| Today button in calendar | feature | Add a "Today" shortcut button on the calendar/log screen to jump back to the current date | backlog | low |
| Clear all logs button | feature | Add a "Clear all logs" button to the profile / settings screen | 2.0.0 | low |
| Apple / Google sign-in | feature | Add OAuth sign-in via Apple and Google as alternatives to email/password | backlog | high |
| Split add_item_screen | feature | Split the combined add_item_screen into separate add_session_screen and add_workout_screen to reduce coupling and improve maintainability | 2.0.0 | medium |
| Convert addExerciseModalSheet to a screen | feature | Replace the modal sheet for adding exercises with a full navigation screen for better UX and code structure | 2.0.0 | low |
| Privacy statement screen | feature | Add a privacy statement / policy screen, accessible from the profile page | 2.0.0 | low |
| Profile settings menu | feature | Settings menu accessible from the profile page with the following options: edit user fields (name, email, etc.), delete all logs, revert catalog items to defaults (without removing user-defined items), remove all user-defined exercises/workouts, export logs, delete account | 2.0.0 | high |
| **IDEAS** | | | | |
| Start a standalone workout or exercise | idea | Toggle to let users start a single workout or exercise directly, without selecting or creating a full session first | backlog | medium |
| Bottom navigation bar | idea | Replace current navigation with a persistent bottom nav bar as the primary navigation structure | 2.0.0 | high |
| Home screen: logged workouts tab | idea | Dedicated tab in the bottom nav for viewing logged workout history | 2.0.0 | medium |
| Edit sessions / workouts / exercises screen | idea | Dedicated tab / screen in the bottom nav for managing the catalog (sessions, workouts, exercises) | 2.0.0 | medium |
| Profile page | idea | Dedicated profile page accessible from the bottom nav, containing user settings and preferences | 2.0.0 | medium |
| Profile: app theme toggle | idea | Toggle between light and dark mode from the profile page | 2.0.0 | low |
| Grid view of exercise labels / phases | idea | A screen showing exercises grouped by label (Warm-up, Climbing, Gym, Stretching, Skills, Daily, etc.) in a grid; tapping a cell navigates to all workouts of that type. New workouts can only be added from this screen. Optionally a horizontal-scroll list per label section | backlog | high |
| Long-press pause to extend timer | idea | Long-pressing the pause button during an exercise keeps the timer running beyond the normal duration; displayed with a loop icon | 2.1.0 | low |
| Animations | idea | Add transitions: between timer phase text labels, between exercises/workouts, and between the workout name list items | backlog | medium |
| Longitudinal progress tracking | idea | Track and visualise long-term progress for key exercises (e.g. max hangs progressions) | 2.1.0 | high |
| Testing sessions | idea | Mark certain exercises or sessions as "test sessions" (e.g. max hangs, pickups, big-3 strength) to separate testing data from training data | 2.1.0 | medium |
| Timers without sessions | idea | Allow users to run timers without having to set up a session or exercise first | backlog | medium |
| Import training schedule | idea | Allow users to import a training schedule (format TBD) to auto-populate sessions, workouts, and exercises | backlog | high |
| **POST-2.0.0** | | | | |
| Friend profiles & social graph | idea | Users can search for other users and add them as friends | 3.0+ | very high |
| Public and private sessions | idea | Users can mark sessions as public or private and share them | 3.0+ | high |
| Add sessions from other users (teams / coaches) | idea | Users can browse and add sessions created by others, enabling team and coach workflows | 3.0+ | very high |

---

## 2.0.0 Scope

| Name | Type | Complexity | Status |
|------|------|------------|--------|
| Sign-up: continue button hidden by keyboard | bug | low | To Do |
| Sign-up: name not populated after email confirmation on different device | bug | medium | To Do |
| Home screen: no clear path to create a session | bug | low | Done |
| RAM overusage — WatchdogTermination (Sentry) | bug | medium | To Do |
| App Store Connect: add business name | chore | low | To Do |
| Edit load in active session screen | feature | medium | To Do |
| Active session: next / previous set & rep navigation | feature | medium | To Do |
| Edit catalog sessions | feature | medium | Done |
| Catalog field edit — UI feedback | feature | low | To Do |
| Catalog propagation | feature | high | To Do |
| Option: exercise with no fixed time | feature | medium | Done |
| lbs vs. kg setting | feature | low | To Do |
| Band resistance support | feature | medium | To Do |
| Clear all logs button | feature | low | To Do |
| Split add_item_screen | feature | medium | Done |
| Convert addExerciseModalSheet to a screen | feature | low | Done |
| Privacy statement screen | feature | low | To Do |
| Profile settings menu | feature | high | To Do |
| Bottom navigation bar | idea | high | Done |
| Home screen: logged workouts tab | idea | medium | Done |
| Edit sessions / workouts / exercises screen | idea | medium | Done |
| Profile page | idea | medium | Done |
| Profile: app theme toggle | idea | low | To Do |

---

## 2.1.0 Scope

| Name | Type | Complexity |
|------|------|------------|
| Separate reps and load per set | feature | high |
| Hide / restore catalog sessions | feature | medium |
| Supersets functionality | feature | high |
| Remove logged sessions by swiping | feature | low |
| Long-press pause to extend timer | idea | low |
| Longitudinal progress tracking | idea | high |
| Testing sessions | idea | medium |

---

## Backlog

| Name | Type | Complexity |
|------|------|------------|
| Conflict resolution: local vs. cloud data | bug | high |
| Offline mode tests | bug | medium |
| Review default exercise time fields (activeTime) | bug | low |
| Supabase health-check cron job | chore | low |
| Add logger package (dev tooling) | chore | low |
| Ask Claude: add `const` for runtime optimisation | chore | low |
| Ask Claude: evaluate widget extraction | chore | low |
| Ask Claude: Flutter framework code review | chore | low |
| Onboarding screens | feature | high |
| Supabase deep linking (email confirmation) | feature | medium |
| Today button in calendar | feature | low |
| Apple / Google sign-in | feature | high |
| Start a standalone workout or exercise | idea | medium |
| Grid view of exercise labels / phases | idea | high |
| Animations | idea | medium |
| Timers without sessions | idea | medium |
| Import training schedule | idea | high |
| Friend profiles & social graph | idea | very high |
| Public and private sessions | idea | high |
| Add sessions from other users (teams / coaches) | idea | very high |
