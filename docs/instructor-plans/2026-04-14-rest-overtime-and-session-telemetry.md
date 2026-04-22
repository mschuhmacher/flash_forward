# Instructor Plan: Rest Overtime & Session Telemetry

Source plan: `docs/superpowers/plans/2026-04-14-rest-overtime-and-session-telemetry.md`

**Goal:** Add a hold-at-rest overtime mode (manual long-press or auto on background) and a structured session event log (what happened in each set and rest, plus a rolled-up summary) that gets saved with every logged session.

---

## Task List Overview

### Phase 1 — Models
- [x] Task 1 of 26: Create `SetEvent` model
- [x] Task 2 of 26: Create `RestEvent` + `RestType` model
- [x] Task 3 of 26: Create `SessionSummary` model
- [x] Task 4 of 26: Extend `Session` with nullable event/summary fields + JSON round-trip tests

### Phase 2 — Settings
- [ ] Task 5 of 26: Add `restOvertimeOnBackground` to `SettingsProvider`

### Phase 3 — Overtime state machine
- [ ] Task 6 of 26: Add `TimerPhase.overtime` + overtime state fields + getter
- [ ] Task 7 of 26: Handle `TimerPhase.overtime` in all switch statements
- [ ] Task 8 of 26: Implement `_enterOvertime` private method
- [ ] Task 9 of 26: Implement `requestManualOvertime` public method + tests
- [ ] Task 10 of 26: Implement `exitOvertime` + session-end guard + tests
- [ ] Task 11 of 26: Ticker increments overtime elapsed while in overtime

### Phase 4 — Background auto-trigger
- [ ] Task 12 of 26: Update `reconcileAfterBackground` for auto-overtime + tests

### Phase 5 — Beep scheduler
- [ ] Task 13 of 26: Truncate future beep simulation when overtime setting is on

### Phase 6 — Event log instrumentation
- [ ] Task 14 of 26: Add event log state fields + helper predicates
- [ ] Task 15 of 26: Implement `_onPhaseTransition` dispatcher
- [ ] Task 16 of 26: Wire dispatcher into `_advanceByElapsed` and `start`
- [ ] Task 17 of 26: Wire dispatcher into `pause`/`resume` + tests
- [ ] Task 18 of 26: Wire dispatcher into `advanceManually`, jumps, `_enterOvertime`, `exitOvertime`, `reset`
- [ ] Task 19 of 26: Implement `_computeSummary` + `finalizeSession` + smoke test

### Phase 7 — Persistence
- [ ] Task 20 of 26: Finalize session before log + update Supabase sync payload

### Phase 8 — UI
- [ ] Task 21 of 26: Overtime branch in timer color/value + phase label
- [ ] Task 22 of 26: Pause button transforms during overtime + long-press to enter
- [ ] Task 23 of 26: Jump buttons disabled and greyed during overtime
- [ ] Task 24 of 26: Settings drawer toggle + sync to provider

### Phase 9 — Supabase migration
- [ ] Task 25 of 26: Add JSONB columns to Supabase schema

### Phase 10 — Validation
- [ ] Task 26 of 26: Manual end-to-end verification

---

## Task Details

---

### [ ] Task 1 of 26: Create `SetEvent` model

**Why:** The event log needs a structured record for each set a user completes. `SetEvent` is the fundamental unit — it captures what happened during one set: when it started and ended, how much of that time was active vs. inter-rep rest, and how many reps were completed.

**What (overview):** A new `SetEvent` class exists with all required fields. It can serialize itself to JSON and reconstruct from JSON correctly. Durations are stored as integer seconds. DateTimes are stored as ISO8601 strings. A test file verifies both the round-trip and the serialization format.

**Details:**
- The class has 8 fields, all required: `workoutIndex` (int), `exerciseIndex` (int), `setIndex` (int), `startAt` (DateTime), `endAt` (DateTime), `activeTime` (Duration), `interRepRestTime` (Duration), `repsCompleted` (int).
- JSON serialization: Duration fields serialize as integer seconds. Use key names that make the unit explicit: `activeTimeSeconds` and `interRepRestTimeSeconds`. DateTime fields serialize as ISO8601 strings, using the same key names as the Dart fields (`startAt`, `endAt`).
- `fromJson` is a factory constructor that reconstructs all fields. There are no optional fields — everything is required and non-nullable.
- The test file has a single fixed test instance constructed at the top of the group. It needs two tests: one that round-trips the instance through `toJson()` then `fromJson()` and asserts every field matches the original; one that calls `toJson()` and inspects the raw map, checking that `startAt` and `endAt` are Strings (not DateTimes), and that `activeTimeSeconds` and `interRepRestTimeSeconds` are ints (not Durations).
- Write the test file first. It won't compile until the model exists — that compile error is the failing test.

**Files:**
- Create: `lib/models/set_event.dart`
- Create: `test/models/set_event_test.dart`

⚡ **First of 3 similar model tasks — do this one yourself. Claude will handle Tasks 2 and 3 after your review passes.**

---

### [ ] Task 2 of 26: Create `RestEvent` + `RestKind` model

*(Claude handles this after Task 1 review passes)*

**Why:** The event log also needs to record what happened during each rest period. `RestEvent` captures the kind of rest (between sets, between exercises, overtime, etc.), how long it was planned to last, how long it actually lasted, and how much of that was overtime. The `RestKind` enum makes rest types explicit and serializable.

**What (overview):** A `RestKind` enum and a `RestEvent` class exist. `RestEvent` serializes `RestKind` as its name string, handles a nullable `setIndex`, and round-trips correctly. A test verifies the round-trip, kind serialization, and null `setIndex` tolerance.

**Details:**
- `RestKind` is an enum with five values: `getReady`, `setRest`, `exerciseRest`, `overtime`, `paused`.
- `RestEvent` has 9 fields: `kind` (RestKind), `workoutIndex` (int), `exerciseIndex` (int), `setIndex` (int? — nullable), `startAt` (DateTime), `endAt` (DateTime), `plannedDuration` (Duration), `actualDuration` (Duration), `overtimeDuration` (Duration). All fields are required in the constructor, but `setIndex` accepts null.
- JSON serialization: `kind` serializes as its enum name string (e.g. `"setRest"`). Durations serialize as integer seconds using the `Seconds` suffix pattern (e.g. `plannedDurationSeconds`). DateTimes serialize as ISO8601 strings.
- `fromJson` reconstructs `RestKind` from the string name using the enum's `byName` lookup. `setIndex` is cast as `int?` so a null value in the map is tolerated.
- Three tests: round-trip all fields, verify `kind` serializes as a plain string (not the full enum path), verify that a JSON map with `setIndex: null` deserializes without error.

**Files:**
- Create: `lib/models/rest_event.dart`
- Create: `test/models/rest_event_test.dart`

---

### [ ] Task 3 of 26: Create `SessionSummary` model

*(Claude handles this after Task 1 review passes)*

**Why:** Instead of re-computing time breakdowns every time a session is displayed, we pre-compute and store a rolled-up summary at the moment the session is saved. `SessionSummary` holds the total time broken down into eight categories.

**What (overview):** A `SessionSummary` class exists with all eight duration fields. It serializes durations as integer seconds and round-trips correctly. A test verifies the round-trip.

**Details:**
- Eight fields, all Duration, all required: `totalTime`, `activeTime`, `interRepRestTime`, `setRestTime`, `exerciseRestTime`, `getReadyTime`, `overtime`, `pausedTime`.
- JSON serialization: all fields serialize as integer seconds using the `Seconds` suffix (e.g. `totalTimeSeconds`, `activeTimeSeconds`).
- One test: construct a fixture with known values, round-trip through `toJson`/`fromJson`, assert all eight fields match.

**Files:**
- Create: `lib/models/session_summary.dart`
- Create: `test/models/session_summary_test.dart`

---

### [ ] Task 4 of 26: Extend `Session` with nullable event/summary fields

**Why:** The `Session` model is what gets stored and synced. Adding the event lists and summary to it means the telemetry travels with the session automatically. Making the fields nullable ensures old sessions without telemetry continue to load without errors.

**What (overview):** `Session` has three new optional fields. `fromJson` tolerates their absence. `toJson` omits them when null. `copyWith` passes them through. `deepCopy` sets all three to null explicitly.

**Details:**
- Three new fields: `setEvents` (List<SetEvent>?), `restEvents` (List<RestEvent>?), `summary` (SessionSummary?). All default to null.
- Add imports for the three new model files at the top of `session.dart`.
- `fromJson`: cast `json['setEvents']` as `List<dynamic>?` and map each element through `SetEvent.fromJson`. Same for `restEvents`. For `summary`, check for null before calling `SessionSummary.fromJson`. Missing keys silently produce null — no error.
- `toJson`: use collection-if to conditionally include each field only when non-null.
- `copyWith`: add three new optional parameters. Their default should pass through the existing value (not default to null), so that callers who don't specify them don't accidentally clear them.
- `deepCopy`: this method creates a live session from a preset — it should explicitly pass null for all three new fields so no historical telemetry leaks into a fresh session.
- Test file has three test cases: (1) a `Session` constructed without the new fields has them all null; (2) `Session.fromJson` with a map missing those keys produces null fields; (3) a session with all three populated round-trips correctly through `toJson`/`fromJson`.

**Files:**
- Modify: `lib/models/session.dart`
- Create: `test/models/session_telemetry_fields_test.dart`

---

### [ ] Task 5 of 26: Add `restOvertimeOnBackground` to `SettingsProvider`

**Why:** The background overtime behavior needs to be user-controlled. Storing it in `SettingsProvider` means it persists across app launches and is accessible anywhere in the widget tree.

**What (overview):** `SettingsProvider` has a new boolean preference, off by default, with a getter and async setter. It's loaded in `init()` and persisted when changed. No UI yet.

**Details:**
- Add a private string constant for the SharedPreferences key. Follow the naming pattern of existing keys in the file (look at how `_keySoundMode` or similar are named).
- Add a private bool field `_restOvertimeOnBackground`, initialized to false.
- Add a public getter `restOvertimeOnBackground` that returns the field.
- Add an async setter `setRestOvertimeOnBackground(bool value)` that: updates the field, calls `notifyListeners()`, then persists via `SharedPreferences`.
- In `init()`, load the value using `prefs.getBool(key) ?? false` alongside the other preference loads.
- No tests required for this task — the pattern is identical to existing preferences in the file.

**Files:**
- Modify: `lib/providers/settings_provider.dart`

---

### [ ] Task 6 of 26: Add `TimerPhase.overtime` + overtime state fields + getter

**Why:** The state machine needs a new phase to represent "the rest timer has been held." The accompanying fields track how long overtime has been running and whether it was triggered automatically or manually — this distinction matters for how it exits.

**What (overview):** `TimerPhase` gets a new `overtime` value. `SessionStateProvider` gets three new private fields and a getter and setter. The analyzer will show switch-exhaustiveness warnings after this — expected, fixed in Task 7.

**Details:**
- Add `overtime` to the `TimerPhase` enum. Position it immediately before `workoutComplete` (look at the existing enum order and slot it there — order matters for readability).
- Add three private fields to `SessionStateProvider`: `_overtimeElapsed` (Duration, initialized to `Duration.zero`), `_overtimeWasAutomatic` (bool, initialized to false), `_restOvertimeOnBackground` (bool, initialized to false). Place them near the other timer state fields like `_lastTickAt`.
- Add a public getter `Duration get overtimeElapsed => _overtimeElapsed`.
- Add a public setter `void setRestOvertimeOnBackground(bool value)` that simply assigns the field (no persistence — that's handled by `SettingsProvider`).
- Run `flutter analyze` after this task. You should see exhaustiveness warnings for the new enum value in switch statements — that's the signal that the next task is needed.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 7 of 26: Handle `TimerPhase.overtime` in all switch statements

**Why:** Every switch on `TimerPhase` needs a case for `overtime` or the analyzer warns. Each switch has a clear and specific behavior for this new phase.

**What (overview):** Three switch statements get an `overtime` case each. The analyzer reports no exhaustiveness warnings after this change.

**Details:**
- `_getDurationForPhase`: the `overtime` case returns `Duration.zero`. Overtime is a count-up, so there is no planned duration.
- `_calculateNextState`: the `overtime` case returns `null`. Overtime never auto-advances — the user must explicitly exit it.
- `_addBeepsForPhase`: the `overtime` case is a no-op (empty case or `break`). No sounds are scheduled while in overtime.
- Run `flutter analyze lib/providers/session_state_provider.dart` after — the exhaustiveness warnings should be gone.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 8 of 26: Implement `_enterOvertime` private method

**Why:** Every path that enters overtime goes through one shared method. This keeps entry logic — resetting elapsed, recording the automatic flag, updating the phase, clearing remaining — in one place.

**What (overview):** A private `_enterOvertime({required bool automatic})` exists. It resets elapsed to zero, sets the flag, transitions phase to overtime, clears remaining, reschedules sound, and notifies. No event log hooks yet.

**Details:**
- Method signature: `void _enterOvertime({required bool automatic})`.
- Steps in order: set `_overtimeElapsed = Duration.zero`, set `_overtimeWasAutomatic = automatic`, update `_progress` by copying it with `phase: TimerPhase.overtime`, set `_remaining = Duration.zero`, update `_rememberCurrentPhaseForPausing = TimerPhase.overtime`, call `_rescheduleSound()` (it will schedule nothing for overtime since `_addBeepsForPhase` is a no-op), call `notifyListeners()`.
- Do not add event log dispatcher calls here yet — that wiring comes in Task 18.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 9 of 26: Implement `requestManualOvertime` + tests

**Why:** Long-pressing the pause button calls this method. It needs a guard so overtime can only be entered from phases where it makes sense. The return value tells the UI whether overtime was actually entered.

**What (overview):** A public `requestManualOvertime()` returns true if entered, false if the current phase wasn't eligible. Tests cover all eligible and ineligible phases.

**Details:**
- Add a private helper predicate `_isOvertimeEligible(TimerPhase p)` that returns true for `setRest`, `exerciseRest`, and `getReady` only.
- `requestManualOvertime()`: if `_isOvertimeEligible(_progress.phase)` is false, return false. Otherwise call `_enterOvertime(automatic: false)` and return true.
- Tests require forcing the provider into specific phases without relying on real-time ticker behavior. Add a `@visibleForTesting` method `debugSetPhase(TimerPhase phase)` that directly updates `_progress` and `_remaining` (via `_getDurationForPhase`) and calls `notifyListeners`. Import `package:meta/meta.dart` for the annotation.
- The test file needs a small fixture session (one workout, one exercise, two sets, some `timeBetweenSets` value). Use it to instantiate the provider in each test.
- Tests: `requestManualOvertime()` returns true from `setRest`, `exerciseRest`, `getReady`; returns false from `rep`, `repRest`, `paused`, `workoutComplete`, `overtime`; on a successful call, `phase == TimerPhase.overtime`, `overtimeElapsed == Duration.zero`, `remaining == Duration.zero`.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Create: `test/providers/session_state_provider_overtime_test.dart`

---

### [ ] Task 10 of 26: Implement `exitOvertime` + session-end guard + tests

**Why:** Exiting overtime always lands on a fresh 10-second get-ready — a clear "you're about to go" signal. The exception is when the session is already over: transitioning to get-ready would lead to a rep that doesn't exist, so we go directly to `workoutComplete`.

**What (overview):** A public `exitOvertime()` exists. No-op when not in overtime. Normal exit lands on 10-second get-ready. Session-end exit lands on `workoutComplete`. Tests cover all cases.

**Details:**
- To implement the session-end guard, you need to know which phase was being held when overtime was entered. Add a new private field `_overtimeSourcePhase` (TimerPhase, initialized to `TimerPhase.getReady`). Set it inside `_enterOvertime` before overwriting `_progress`: `_overtimeSourcePhase = _progress.phase`.
- `exitOvertime()` steps: return early if `_progress.phase != TimerPhase.overtime`. Peek at whether the session has more to do by calling `_calculateNextState` on a copy of `_progress` with phase set to `_overtimeSourcePhase`. If it returns null, the session is over — set phase to `workoutComplete`, remaining to zero, cancel beeps, notify, return. Otherwise, set phase to `getReady`, remaining to 10 seconds, start a fresh ticker, reschedule sound, reset `_overtimeWasAutomatic` and `_overtimeElapsed` to their zero states, notify.
- Tests: exit from `setRest` source → `getReady` with 10s remaining; exit from `exerciseRest` source → `getReady` with 10s; exit from `getReady` source → `getReady` restarted at 10s; `exitOvertime()` when not in overtime is a no-op (phase unchanged); exit from the final rest of the session → `workoutComplete`.
- For the final-rest test: use the fixture session and put the provider in a state where the source phase has no next state. The simplest way is to use `debugSetPhase` to set an `exerciseRest` on a session that has already completed its last set.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_overtime_test.dart`

---

### [ ] Task 11 of 26: Ticker increments overtime elapsed

**Why:** While in overtime, `_advanceByElapsed` would try to count remaining time down — but overtime has no remaining time and never auto-advances. The ticker needs a special branch that counts up instead.

**What (overview):** In the ticker callback, when phase is overtime, the tick accumulates elapsed time into `_overtimeElapsed` and returns early without running the normal advance logic. A test verifies the counter grows.

**Details:**
- In `_startTicker()`'s `Timer.periodic` callback, find the early-return checks at the top (e.g. for paused or workoutComplete). Add a new early-return branch immediately after those checks, before `_advanceByElapsed` is called.
- The branch: if `_progress.phase == TimerPhase.overtime`, compute elapsed as `DateTime.now().difference(_lastTickAt!)`, add it to `_overtimeElapsed`, update `_lastTickAt = DateTime.now()`, call `notifyListeners()`, return.
- Test: start a provider with the fixture, use `debugSetPhase` to enter `setRest`, call `requestManualOvertime()`, wait ~1200ms via `Future.delayed`, assert `overtimeElapsed.inMilliseconds > 800`. The threshold gives slack for test timing variability.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_overtime_test.dart`

---

### [ ] Task 12 of 26: Update `reconcileAfterBackground` for auto-overtime

**Why:** `reconcileAfterBackground` fast-forwards the state machine by the time spent in the background. With overtime, two new scenarios arise: (1) a rest expired while backgrounded and the setting is on — enter overtime and immediately auto-exit; (2) overtime was already active before backgrounding — accumulate the gap and auto-exit only if it was an automatic entry.

**What (overview):** `reconcileAfterBackground` handles two new cases before falling through to the existing fast-forward logic. A `@visibleForTesting` helper for `_lastTickAt` enables deterministic tests.

**Details:**
- Add `@visibleForTesting void debugSetLastTickAt(DateTime t) => _lastTickAt = t;` to the provider.
- The method already reads `gap = now.difference(_lastTickAt!)`. Add two new cases at the top of the method body, before the existing fast-forward:
  - **Case 1 — already in overtime:** if `_progress.phase == TimerPhase.overtime`, add gap to `_overtimeElapsed`, update `_lastTickAt = now`. If `_overtimeWasAutomatic`, call `exitOvertime()`. Otherwise call `notifyListeners()`. Return.
  - **Case 2 — rest expired during background with setting on:** if `_restOvertimeOnBackground` is true AND current phase is `setRest` or `exerciseRest` AND `gap >= _remaining`, then: compute `overshoot = gap - _remaining`, set `_remaining = Duration.zero`, update `_lastTickAt = now`, call `_enterOvertime(automatic: true)`, set `_overtimeElapsed = overshoot`, call `exitOvertime()`. Return.
- Tests: for Case 1 with `_overtimeWasAutomatic = true` — set phase to `setRest`, call `requestManualOvertime()`, use `debugSetLastTickAt` to backdate by 30s, call `reconcileAfterBackground()`, assert phase is now `getReady`. For Case 2 — enable `restOvertimeOnBackground`, set phase to `setRest`, backdate by 30s (more than rest duration), call `reconcileAfterBackground()`, assert phase is `getReady`.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_overtime_test.dart`

---

### [ ] Task 13 of 26: Truncate future beep simulation at rest boundary

**Why:** The beep scheduler pre-schedules all upcoming sounds by simulating future phase transitions. With the background overtime setting on, this simulation is wrong — it would schedule beeps for sets that won't start until the user manually skips overtime.

**What (overview):** The simulation loop breaks early when the setting is on and it reaches a set or exercise rest, preventing beeps from being scheduled beyond the hold point.

**Details:**
- Find `_calculateFutureBeeps()` in the provider. It contains a `while (true)` loop that advances a simulated `SessionProgress` and schedules beeps.
- Inside the loop, after computing the next simulated state and before adding beeps for it, add a check: if `_restOvertimeOnBackground` is true AND the current simulated phase (not the next one — the one just completed) is `setRest` or `exerciseRest`, break out of the loop.
- The placement is important: you want to schedule the beeps for the rest itself (the countdown and "go" sound at rest-end), but not for anything after it. Check the existing loop structure carefully to find the right insertion point.
- No automated tests — verify by reading the code path on paper: with the setting on and current phase `setRest`, trace through and confirm the loop stops after the current rest's beeps.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 14 of 26: Add event log state fields + helper predicates

**Why:** Before the transition dispatcher can record events, the data structures to hold them need to exist. Drafts represent an event that has started but not yet been closed. Helper predicates keep the dispatcher logic readable.

**What (overview):** The provider gets two finalized event lists, two optional draft holders, a phase-entry timestamp, two per-set accumulators, two private draft classes, and two predicate methods.

**Details:**
- Two `List` fields initialized as empty: `final List<SetEvent> _setEvents = []` and `final List<RestEvent> _restEvents = []`. Import the model files at the top of the provider.
- Two optional draft fields, initialized to null: one of a private type `_OpenSetDraft` and one of `_OpenRestDraft`.
- `DateTime? _currentPhaseEnteredAt` — used to compute how long the current phase has been active when a transition happens.
- `Duration _currentSetActiveAccum = Duration.zero` and `Duration _currentSetRepRestAccum = Duration.zero` — accumulate the active and inter-rep-rest time for the currently open set.
- Two private classes at the bottom of the file (outside the provider class):
  - `_OpenSetDraft`: fields `workoutIndex` (int), `exerciseIndex` (int), `setIndex` (int), `startAt` (DateTime). Constructor takes all four as required named params.
  - `_OpenRestDraft`: fields `kind` (RestKind), `workoutIndex` (int), `exerciseIndex` (int), `setIndex` (int?), `startAt` (DateTime), `plannedDuration` (Duration). Constructor takes all as required named params.
- Two private methods on the provider:
  - `_isRestPhase(TimerPhase p)`: returns true for `getReady`, `setRest`, `exerciseRest`, `overtime`, `paused`.
  - `_kindForPhase(TimerPhase p)`: returns the corresponding `RestKind` for each rest phase. Throws a `StateError` for non-rest phases (this is a programming error, not a user error).

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 15 of 26: Implement `_onPhaseTransition` dispatcher

**Why:** Every phase change needs the same bookkeeping: attribute elapsed time to the right accumulator, close what was open, open what should start. One method handles all of it so individual call sites don't repeat this logic.

**What (overview):** A private `_onPhaseTransition(from, to, newProgress)` method and four draft helper methods exist. The dispatcher attributes time slices, closes drafts for the exiting phase, and opens drafts for the entering phase.

**Details:**
- Add four private helper methods before the dispatcher:
  - `_openNewSetDraft(SessionProgress p)`: assigns a new `_OpenSetDraft` using workout/exercise/set indices from `p` and `startAt: DateTime.now()`. Resets both accumulators to `Duration.zero`.
  - `_closeOpenSetDraft({required int repsCompleted})`: if `_openSetDraft` is null, return. Otherwise create and append a `SetEvent` to `_setEvents`, then null out the draft and reset accumulators.
  - `_openNewRestDraft(RestKind kind, SessionProgress p)`: assigns a new `_OpenRestDraft`. `plannedDuration` is `_getDurationForPhase(p)` for normal rest phases; for `overtime` and `paused`, use `Duration.zero` (they have no planned duration). `setIndex` is only meaningful for `setRest` — pass `p.currentSet` for setRest, null for everything else.
  - `_closeOpenRestDraft()`: if `_openRestDraft` is null, return. Compute `actualDuration = DateTime.now().difference(draft.startAt)`. `overtimeDuration` is `actualDuration` only if `kind == RestKind.overtime`, otherwise `Duration.zero`. Create and append a `RestEvent`, then null out the draft.
  - `_discardDrafts()`: null both drafts, reset both accumulators, set `_currentPhaseEnteredAt = null`.
- The dispatcher `_onPhaseTransition(TimerPhase from, TimerPhase to, SessionProgress newProgress)`:
  1. If `_currentPhaseEnteredAt != null`, compute `slice = DateTime.now().difference(_currentPhaseEnteredAt!)`. Add to `_currentSetActiveAccum` if `from == TimerPhase.rep`, or to `_currentSetRepRestAccum` if `from == TimerPhase.repRest`.
  2. Set `_currentPhaseEnteredAt = DateTime.now()`.
  3. If `_isRestPhase(from)`, call `_closeOpenRestDraft()`.
  4. If `from == TimerPhase.rep` AND `to` is not `repRest` AND `to` is not `paused`, call `_closeOpenSetDraft(repsCompleted: newProgress.currentRep)`. (Pauses span the set; inter-rep rests are within a set.)
  5. If `to == TimerPhase.rep` AND `from` is not `repRest` AND `from` is not `paused`, call `_openNewSetDraft(newProgress)`.
  6. If `_isRestPhase(to)`, call `_openNewRestDraft(_kindForPhase(to), newProgress)`.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 16 of 26: Wire dispatcher into `_advanceByElapsed` and `start`

**Why:** `start()` and `_advanceByElapsed` are the two entry points for phase changes during normal automatic flow. Both must call the dispatcher so every transition is recorded.

**What (overview):** `start()` clears prior event state and calls the dispatcher for the initial get-ready. `_advanceByElapsed`'s loop calls the dispatcher before committing each new phase. Existing tests pass after.

**Details:**
- In `start()`: at the very top, before the deep-copy or any state assignment, call `_setEvents.clear()`, `_restEvents.clear()`, `_discardDrafts()`. After the initial `_progress` is set to the get-ready state, call `_onPhaseTransition(TimerPhase.workoutComplete, TimerPhase.getReady, _progress)`. Using `workoutComplete` as the "from" phase is the convention for "no prior phase to attribute time to."
- In `_advanceByElapsed`'s `while (_remaining <= Duration.zero)` loop: before each `_progress = next` assignment, call `_onPhaseTransition(_progress.phase, next.phase, next)`. For the branch that transitions to `workoutComplete` (when `_calculateNextState` returns null), call `_onPhaseTransition(_progress.phase, TimerPhase.workoutComplete, _progress)` before updating `_progress`.
- Run `flutter test test/providers/` after. All existing tests should still pass — this is a pure addition, no behavior changes for normal flow.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 17 of 26: Wire dispatcher into `pause`/`resume` + tests

**Why:** Pause and resume are user-initiated phase changes. A pause during a rest splits it into two rest events (before-pause and after-resume). The dispatcher must be called correctly so partial elapsed time is attributed before the phase changes.

**What (overview):** `pause()` flushes a partial slice, then calls the dispatcher. `resume()` calls the dispatcher to close the paused draft and open a new one for the resumed phase. Tests verify the split-rest behavior.

**Details:**
- In `pause()`: before calling the dispatcher, flush any partial elapsed time manually. If `_currentPhaseEnteredAt != null`, compute `slice = DateTime.now().difference(_currentPhaseEnteredAt!)`. If `_progress.phase == rep`, add to `_currentSetActiveAccum`. If `repRest`, add to `_currentSetRepRestAccum`. Then update `_currentPhaseEnteredAt = DateTime.now()`. After flushing, call `_onPhaseTransition(_progress.phase, TimerPhase.paused, _progress)` before updating `_progress`.
- In `resume()`: build the target progress (with phase = `_rememberCurrentPhaseForPausing`), then call `_onPhaseTransition(TimerPhase.paused, target.phase, target)` before assigning `_progress = target`.
- Add two `@visibleForTesting` helpers: `int debugRestEventCount() => _restEvents.length` and `List<RestKind> debugRestEventKinds() => _restEvents.map((e) => e.kind).toList()`.
- Test: set phase to `setRest`, call `pause()`, then call `resume()`, then use `debugSetPhase` to force a transition out of `setRest`. Assert that `debugRestEventKinds()` contains `[RestKind.setRest, RestKind.paused, RestKind.setRest]` — the first `setRest` is the segment before pause, `paused` is the pause itself, the second `setRest` is the resumed segment.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Create: `test/providers/session_state_provider_event_log_test.dart`

---

### [ ] Task 18 of 26: Wire dispatcher into `advanceManually`, jumps, `_enterOvertime`, `exitOvertime`, `reset`

**Why:** The remaining public entry points that change phase need to be wired up so no transition is missed. Jump actions are special — they discard all in-progress drafts because navigating mid-set produces data that cannot be meaningfully attributed.

**What (overview):** Five methods get dispatcher calls or draft discards. After this task, every phase transition in the provider goes through `_onPhaseTransition`.

**Details:**
- `advanceManually()`: wherever it assigns a new phase to `_progress`, compute a `next` progress value first, call `_onPhaseTransition(_progress.phase, next.phase, next)`, then assign `_progress = next`. Do this for each branch (the `setRest` branch and the `exerciseRest` branch if they exist separately).
- Jump methods (`jumpToWorkout`, `jumpToExercise`, `jumpToSet`): call `_discardDrafts()` before any state changes. After the jump is committed to `_progress`, call `_onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress)` — using `workoutComplete` as the "from" signals "no prior slice to attribute."
- `_enterOvertime()`: before committing the new phase, add `_overtimeSourcePhase = _progress.phase` (this field was introduced in Task 10), then call `_onPhaseTransition(_progress.phase, TimerPhase.overtime, next)` where `next` is the progress with the overtime phase. Then assign `_progress = next`.
- `exitOvertime()`: add dispatcher calls before each phase assignment. For the `workoutComplete` branch: `_onPhaseTransition(TimerPhase.overtime, TimerPhase.workoutComplete, _progress)`. For the normal get-ready branch: call the dispatcher before assigning `_progress`.
- `reset()`: after cancelling the ticker and clearing `_activeSession`, call `_setEvents.clear()`, `_restEvents.clear()`, `_discardDrafts()`.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

---

### [ ] Task 19 of 26: Implement `_computeSummary` + `finalizeSession` + smoke test

**Why:** When a session is saved, the still-open drafts need to be closed, the summary needs to be computed from all finalized events, and the result needs to be returned as a `Session` copy ready for persistence.

**What (overview):** A private `_computeSummary()` sums durations from the finalized event lists. A public `finalizeSession()` closes open drafts, computes the summary, and returns a populated `Session` copy. A smoke test verifies the wiring.

**Details:**
- `_computeSummary()` private method: it receives no arguments — it reads `_setEvents` and `_restEvents` directly. Compute:
  - `totalTime`: difference between the `startAt` of the first event (check both lists, use whichever starts earlier) and the `endAt` of the last event (same approach).
  - `activeTime`: sum of `activeTime` across all `_setEvents`.
  - `interRepRestTime`: sum of `interRepRestTime` across all `_setEvents`.
  - `setRestTime`: sum of `actualDuration` from `_restEvents` where `kind == RestKind.setRest`.
  - `exerciseRestTime`: same filter for `exerciseRest`.
  - `getReadyTime`: same filter for `getReady`.
  - `overtime`: sum of `overtimeDuration` from `_restEvents` where `kind == RestKind.overtime`.
  - `pausedTime`: sum of `actualDuration` from `_restEvents` where `kind == RestKind.paused`.
- `finalizeSession()` public method: return null if `_activeSession == null`. Close any open rest draft via `_closeOpenRestDraft()`. Close any open set draft via `_closeOpenSetDraft(repsCompleted: _progress.currentRep)`. Call `_computeSummary()`. Return `_activeSession!.copyWith(setEvents: List.unmodifiable(_setEvents), restEvents: List.unmodifiable(_restEvents), summary: summary)`.
- Smoke test: instantiate provider with fixture session, call `start()`, immediately call `finalizeSession()`. Assert result is not null, `result!.summary != null`, and `result.setEvents != null`.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_event_log_test.dart`

---

### [ ] Task 20 of 26: Finalize session before log + update Supabase sync payload

**Why:** The session passed to the log provider and uploaded to Supabase is currently the raw active session. It needs to be the finalized version so the telemetry is persisted. The sync service also needs to include the new fields and handle the snake_case ↔ camelCase translation.

**What (overview):** The call site that logs a completed session uses `finalizeSession()` first. The sync service includes the three new fields in the upsert and maps their snake_case column names back on fetch.

**Details:**
- First, find the call site: search for `refreshSelectedSessions` in the `lib/` directory. The file that calls it is where you'll make changes.
- At that call site: obtain the finalized session by calling `context.read<SessionStateProvider>().finalizeSession()`. Guard against null (if null, return early or log a warning). Pass the finalized session to `refreshSelectedSessions` instead of the raw active session.
- In `SupabaseSyncService.uploadSession`: add three new entries to the upsert map. The Supabase column names use snake_case: `'set_events'`, `'rest_events'`, `'summary'`. Their values are `session.setEvents?.map((e) => e.toJson()).toList()`, same for `restEvents`, and `session.summary?.toJson()`. Null values are acceptable — Supabase will store NULL for missing telemetry.
- In `SupabaseSyncService.fetchUserSessions` (or wherever rows are deserialized): the JSON from Supabase uses snake_case keys, but `Session.fromJson` expects camelCase. Add a mapping step before passing the row to `Session.fromJson`: copy the map and add `'setEvents': row['set_events']`, `'restEvents': row['rest_events']`, `'summary': row['summary']`.

**Files:**
- Modify: whichever file calls `refreshSelectedSessions` (search to find it)
- Modify: `lib/services/supabase_sync_service.dart`

---

### [ ] Task 21 of 26: Overtime branch in timer display + phase label

**Why:** The UI has no concept of overtime yet. During overtime the timer must count up, not down, and use a distinct color so the user understands the state has changed.

**What (overview):** When phase is overtime, the displayed timer value shows `overtimeElapsed` (counting up) in the secondary color. The phase label shows "overtime" in the same color. No other phases change.

**Details:**
- Find the code that computes the displayed timer value and color. It likely lives in a builder or a helper function that switches on `phase`. Search for where `remaining` or `_remaining` is read for display, or where timer colors are assigned.
- Add an `overtime` branch: display value is `sessionState.overtimeElapsed` (read via the public getter from Task 6). Color is `Theme.of(context).colorScheme.secondary`.
- Find the phase label widget — it likely maps `TimerPhase` values to strings. Add `TimerPhase.overtime` → `'overtime'` with `colorScheme.secondary` color.
- This task has no automated tests. Verification is manual (Task 26).

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`

---

### [ ] Task 22 of 26: Pause button transforms during overtime + long-press to enter

**Why:** The pause button is the primary interaction point for overtime. Long-pressing during an eligible rest enters overtime. While in overtime, the button's icon and color change to communicate that tapping it will skip overtime, not pause.

**What (overview):** The button handles three states: normal (pause icon), paused (play icon), overtime (skip-forward icon in secondary color). Long-press on eligible phases enters overtime. Long-press elsewhere is a no-op.

**Details:**
- Find the pause button widget in the file. It currently responds to taps for pause/resume. You need to add long-press support and an overtime-specific visual state.
- The button needs to read two things from the provider: `phase` and `isPaused`. Based on these, determine: if `phase == overtime`, show a skip-forward icon in `colorScheme.secondary`, tap calls `exitOvertime`. If paused (but not overtime), show a play icon, tap calls `resume`. Otherwise show a pause icon, tap calls `pause`.
- Long-press is only wired up on `setRest`, `exerciseRest`, and `getReady`. On all other phases (including overtime itself), long-press does nothing. Long-press calls `requestManualOvertime()`.
- The button likely uses `IconButton`. You may need to replace it with a `GestureDetector` wrapping an `Icon` to get both `onTap` and `onLongPress`. Look at how the button is currently built and choose the least-invasive approach.
- Consider whether this button is small enough to extract into its own widget (`PauseOvertimeButton` or similar). If it's tightly coupled to the surrounding layout, leave it in place. If it can be extracted cleanly in under ~30 lines, do it — it will make the optional widget test in the next step feasible.

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`
- Possibly create: `test/widget/pause_button_overtime_test.dart` (only if button is extracted)

---

### [ ] Task 23 of 26: Jump buttons disabled and greyed during overtime

**Why:** Jumping to another set or exercise during overtime would leave an unclosed event log draft and produce corrupt telemetry. The buttons must be fully non-interactive and visually signal their unavailability.

**What (overview):** All jump buttons are disabled (non-tappable) and use the disabled color when `phase == overtime`. All other phase behavior is unchanged.

**Details:**
- Search for `jumpToSet`, `jumpToExercise`, and `jumpToWorkout` in the presentation layer to find all button call sites.
- For each button: read `phase` from the provider (or use a `context.select` that returns just the bool `phase == TimerPhase.overtime`). When `isOvertime` is true: set `onPressed: null` (Flutter's standard way to disable any button widget) and use `Theme.of(context).disabledColor` for the icon color. When not in overtime: keep existing behavior and color.
- Each button needs its own `isOvertime` read — or you can hoist a single `isOvertime` bool if all the buttons are built in the same widget subtree.
- Check both `session_active_screen.dart` and `session_active_bottom_bar.dart` (if it exists) — the jump buttons may be split between files.

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`
- Possibly: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart`

---

### [ ] Task 24 of 26: Settings drawer toggle + sync to provider

**Why:** The `restOvertimeOnBackground` preference exists in `SettingsProvider` (Task 5) but has no UI. Users need to toggle it, and the live session state needs to reflect changes immediately without requiring an app restart.

**What (overview):** A new `SwitchListTile` in the settings drawer reads and writes the preference. Toggling it updates both the provider (for persistence) and the session state provider (for live effect). The setting is also synced on startup.

**Details:**
- Find the settings drawer in `root_screen.dart`. It likely already has other preference controls (e.g. a sound mode toggle). Add the new tile near them.
- The tile's `value` reads `SettingsProvider.restOvertimeOnBackground`. Its `onChanged` callback does two things: calls `settings.setRestOvertimeOnBackground(v)` (persists) and calls `context.read<SessionStateProvider>().setRestOvertimeOnBackground(v)` (live effect).
- Title: something like "Extend rest when backgrounded". Subtitle: a one-sentence explanation (e.g. "Keeps the rest timer on hold when you leave the app — tap skip to continue when you return").
- Startup sync: find where `SettingsProvider` values are synced to `SessionStateProvider` on app init (search for where sound mode is synced — it's likely in `initState` or a `PostFrameCallback` in `root_screen.dart`). Add a parallel call to sync `restOvertimeOnBackground` in the same place.

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart`

---

### [ ] Task 25 of 26: Add JSONB columns to Supabase schema

**Why:** The app now sends `set_events`, `rest_events`, and `summary` in the session upsert, but the `user_sessions` table doesn't have those columns. Without the migration, the data is silently dropped.

**What (overview):** A migration adds three nullable JSONB columns to `user_sessions`. After applying it, a test upload confirms the columns populate correctly.

**Details:**
- First, find where existing migrations live: check the `supabase/` directory at the repo root. If it has a `migrations/` subfolder with `.sql` files, create a new file there. If migrations are applied manually via the Supabase dashboard, you'll write the SQL here and apply it by hand.
- SQL to add: `ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS set_events JSONB, ADD COLUMN IF NOT EXISTS rest_events JSONB, ADD COLUMN IF NOT EXISTS summary JSONB;` — the `IF NOT EXISTS` guard makes the migration safe to re-run.
- Apply method: if using Supabase CLI, run the migration against your development project first. If applying manually, paste the SQL into the Supabase SQL editor on the dashboard.
- Verification: after applying, do a complete session in the app and log it. Query the `user_sessions` row in the Supabase SQL editor and confirm `set_events`, `rest_events`, and `summary` are not null (they should contain JSON).

**Files:**
- Create: migration file in `supabase/migrations/` (or apply manually if no CLI setup exists)

---

### [ ] Task 26 of 26: Manual end-to-end verification

**Why:** Unit tests verify individual pieces in isolation. A full manual pass is the only way to confirm all pieces work together correctly in the real app, including behaviors that are hard to unit test: sound timing, background lifecycle, visual states, and data persistence.

**What (overview):** A structured manual test session walks through all new behaviors and confirms each one works correctly on a real device or simulator.

**Details:**
The following scenarios need to be tested, in order:

1. **Normal session, no overtime.** Complete a session without ever triggering overtime. Verify the session logs successfully and the summary is non-null (check via the Supabase SQL editor or a debug print if no summary UI exists yet).
2. **Manual overtime from set rest.** Reach a set rest. Long-press the pause button. Verify: icon changes to skip-forward, color becomes secondary, timer counts up. Tap the skip button. Verify: transitions to a 10-second get-ready, which then proceeds normally.
3. **Manual overtime from get-ready.** Long-press during get-ready. Verify: enters overtime. Tap skip. Verify: get-ready restarts from 10 seconds.
4. **Long-press during rep — no-op.** Long-press during an active rep. Verify: nothing happens, session continues normally.
5. **Long-press during repRest — no-op.** (Requires an exercise with `timeBetweenReps > 0`.) Long-press during an inter-rep rest. Verify: nothing happens.
6. **Auto-overtime on background (setting on).** Enable "Extend rest when backgrounded" in settings. Start a session, reach a set rest. Lock the device (or switch apps) and wait longer than the rest duration. Return to the app. Verify: session is in get-ready (or workoutComplete if it was the final rest), not fast-forwarded into the next rep.
7. **Manual overtime survives backgrounding.** Long-press into overtime. Lock device and wait 20+ seconds. Return. Verify: still in overtime, `overtimeElapsed` reflects the elapsed time (including the background gap).
8. **Jump buttons disabled in overtime.** Enter overtime via long-press. Verify: set +/- and prev/next exercise buttons are visually greyed and unresponsive to taps.
9. **Session log contains telemetry.** Complete a session that includes at least one overtime. Check the logged session row in Supabase (or the local JSON file if local persistence is used). Verify `set_events`, `rest_events`, and `summary` are all non-null and contain plausible data.
10. **Beep truncation (setting on).** With "Extend rest when backgrounded" on, start a session with multiple exercises and reach a set rest. Background the app. Confirm that no beeps fire for what would have been the next set's get-ready countdown.

Any scenario that fails becomes a new task before merging.

**Files:** No code changes expected.

---
