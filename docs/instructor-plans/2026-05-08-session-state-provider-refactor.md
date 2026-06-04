# Instructor Plan — SessionStateProvider Refactor

> Source plan: `docs/superpowers/plans/2026-05-08-session-state-provider-refactor.md`
> Mode: instructor (you code, Claude guides). One task at a time. Next task unlocks only after the current one passes review.

## Codebase drift noticed on 2026-06-03 (read before starting)

The source plan was last reassessed 2026-05-26. Since then:

1. **Provider is now 1,872 LOC** (plan says 1,681). The end-state target of "~600 LOC" is more realistically "~700". Don't treat the LOC numbers as hard gates — they're directional.
2. **`_syncTimerDisplay()` now appears 20 times** (19 call sites + 1 definition), not 16. The plan's acceptance criterion of "16" is stale — the real invariant is "the count does not change across the refactor." Measure the baseline yourself in Task 1 and hold it constant.
3. **There is a 6th provider test file the plan doesn't list: `test/providers/session_state_provider_replace_test.dart`.** It exercises `debugSetPhase` / `finalizeSession` / set-draft logging, so it is a **second canary for Task 3 (telemetry)** alongside `event_log_test.dart`. Keep it green and unchanged.
4. `_countdownLeadTime` is **400 ms**, not 500 ms (prose-only; the logic passes it as a parameter so it doesn't matter).
5. `SoundMode` has a 4th value, `none` (`both, soundsOnly, notificationsOnly, none`). Your Task 4 sound helper tests should assert `none` → no in-app sound and no notifications.
6. Confirmed accurate as written: ticker at 100 ms, `supersetRest` is a beep source for both countdown and go, the overtime ticker branch is "sync display only, never notifyListeners".

> **Task numbering note:** This instructor plan splits the source plan's "Task 1" into two instructor tasks (a measurement/baseline task, then the actual extraction) because the baseline measurement is a distinct skill worth doing deliberately. So instructor Task N ≠ source-plan Task N. The mapping is given in each task.

---

## Task summary

- [x] **Task 1 of 6** — Establish the green baseline and capture invariants (baseline: 18 `_syncTimerDisplay()` call sites / grep count 19)
- [x] **Task 2 of 6** — Extract `SessionStateMachine` (pure functions) *(source plan Task 1)* — flat layout (lib/providers/, test/providers/); + architecture doc with 2 mermaid diagrams
- [x] **Task 3 of 6** — Extract `SessionTelemetryRecorder` (scoped state) *(source plan Task 2)* — executed by Claude (full-answer); `_currentPhaseEnteredAt` moved into the recorder for full slice-attribution ownership
- [x] **Task 4 of 6** — Extract `SoundDispatcher` (beep timing) *(source plan Task 3)* — executed by Claude; `classifyTickEdge` returns `List<BeepType>`; thin `_rescheduleSound()` wrapper kept to adapt provider state
- [x] **Task 5 of 6** — Sweep: verify provider shape and invariants *(source plan Task 4)* — zero leftover refs, sync count 19 (18 sites+def) unchanged, analyze clean, full suite 327 green. Manual device smoke NOT run (no device in this session)
- [x] **Task 6 of 6** — Lift `SessionProgress`/`TimerPhase` into `session_progress.dart` *(source plan Task 5)* — done first to avoid double-editing helper imports; all helpers + provider + screens + 7 test files updated

The middle three tasks (2, 3, 4) all follow the **same TDD rhythm**: write a failing helper test → implement the helper as a near-verbatim port → migrate the provider to delegate → confirm the full suite stays green. You learn that rhythm by hand in Task 2; Tasks 3 and 4 reuse it with different subject matter. None of these are auto-handed-off — each helper is different enough in substance to be worth building yourself.

---

### [x] Task 1 of 6: Establish the green baseline and capture invariants

**Why:** This refactor is a behavior-preserving move — its entire safety net is "the existing tests stayed green and the invariants held." Before you change anything, you need a recorded starting point: which tests pass, and the current values of the two numbers that must not drift (the `_syncTimerDisplay()` count and the provider's notification structure). Without this baseline you can't prove later that nothing broke.

**What (overview):** You have a confirmed-green test run for the session provider suite, and you've written down the baseline values of the invariants the plan tracks, so any later drift is detectable.

**Details:**
- Run the provider test suite using the project's test runner (`scripts/run_tests.sh`, not raw `flutter test` — raw output floods the terminal). Target the `test/providers/` directory, or at minimum the six `session_state_provider_*_test.dart` files. Confirm all green. (We already fixed the one unrelated failure — `trash_provider_test.dart` — and committed it, so the suite should be clean.)
- Identify and list the **six** existing provider test files that form the safety net. The plan names five; the sixth is `session_state_provider_replace_test.dart`. You'll watch these for regressions throughout.
- Count the current `_syncTimerDisplay()` occurrences in `lib/providers/session_state_provider.dart`. Write the number down. This must be identical at the end of the refactor.
- Note the provider's **two notification channels**: the inherited `ChangeNotifier` (via `notifyListeners()`, fires only on phase transitions) and the public `ValueNotifier<Duration> timerDisplayNotifier` (fires at 10 Hz). Neither helper you extract will own either channel — both stay on the provider. Just confirm you can find both in the file and understand which is which.
- Confirm the helper directory `lib/providers/session/` does not exist yet (you'll create it in Task 2) and the test directory `test/providers/session/` does not exist yet either.
- No production code changes in this task. This is measurement only.

**Files:** None modified. You're reading `lib/providers/session_state_provider.dart` and running tests.

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [x] Task 2 of 6: Extract `SessionStateMachine` (pure functions)

*(Source plan Task 1.)*

**Why:** The provider currently mixes pure decision logic (given the current state, what's the next state? how long is this phase? is this phase eligible for overtime?) with stateful timer/notification machinery. The pure logic is the easiest to lift out cleanly because it has no state and no side effects — it's just functions of their inputs. Extracting it first gives you a trivially testable unit and shrinks the provider with the least risk. It's also the foundation the sound helper later reuses (the beep-scheduling walk simulates future states using this machine).

**What (overview):** A new `SessionStateMachine` class holds the pure transition/duration/classification functions, fully unit-tested in isolation. The provider keeps the same public API but delegates these computations to the new class. The full test suite stays green.

**Concept primer:**
- **Pure function** — a function whose output depends only on its inputs, with no side effects (no reading/writing fields, no notifications, no I/O). Same inputs always give the same output. This makes it trivially testable.
- **Static method** — a method that belongs to the class itself rather than to an instance, so you call it as `SessionStateMachine.calculateNextState(...)` without creating an object. Fits pure functions because there's no per-instance state to hold.
- **Verbatim port** — moving code to a new home with *zero* semantic change. The only edits allowed are mechanical: e.g. where the old code read the private field `_activeSession!`, the new function reads a parameter named `activeSession` instead. No logic rewrites, no "while I'm here" cleanups.
- **Private constructor (`ClassName._();`)** — a way to say "nobody should ever instantiate this class"; it only exists to namespace the static methods.

**Details:**
- Create `lib/providers/session/session_state_machine.dart` and `test/providers/session/session_state_machine_test.dart`.
- The functions to move (find them by name in the provider — they all currently exist as private methods): `_calculateNextState`, `_enterExerciseRest`, `_enterPostSetRest`, `_calculateNextStop`, `_calculatePreviousStop`, `_firstStopAtOrAfter`, `_lastStopBefore`, `_getDurationForPhase`, `_isOvertimeEligible`, `_isRestPhase`, `_matchRestTypeToTimerPhase`. On the helper they become public static methods (drop the leading underscore; `_calculateNextState` → `calculateNextState`, etc.).
- **TDD order matters here** — write the test first and watch it fail to compile (the class doesn't exist yet), *then* implement. This is the rhythm you'll reuse in Tasks 3 and 4.
- Test coverage to write (these mirror real behavior — derive the constructor argument shapes from how `session_state_provider_event_log_test.dart` and `session_state_provider_superset_test.dart` build their `Exercise`/`Workout`/`Session` fixtures):
  - `calculateNextState`: rep→repRest, repRest→rep, setRest→rep (with set bump), exerciseRest→rep, getReady→rep, supersetRest→rep, end-of-session returns null, the "fixedDuration skips repRest" case, manual returns null.
  - `getDurationForPhase`: rep for each ExerciseType, repRest, setRest, exerciseRest in the solo case, exerciseRest in the between-rounds superset case (returns `supersetSetRest`, falling back to `workout.timeBetweenExercises`), supersetRest (returns `superset.restSeconds`), getReady = 10s, and overtime/paused/workoutComplete = zero.
  - `isOvertimeEligible`: true for setRest/exerciseRest/getReady; false for everything else.
  - `isRestPhase`: true for getReady/setRest/exerciseRest/overtime/paused/supersetRest; false for rep/repRest/workoutComplete.
  - `enterExerciseRest`, `enterPostSetRest`, `calculateNextStop`, `calculatePreviousStop`, `firstStopAtOrAfter`, `lastStopBefore`, `matchRestTypeToTimerPhase` — at least the cases listed in the source plan's Task 1 Step 2 (solo vs superset, within-workout vs cross-workout, group-entry/exit boundaries, throws on non-rest phase for matchRestType).
- Inputs: the functions take `(SessionProgress, Session)` or just a `TimerPhase`. The helper will need to *import* `SessionProgress` and `TimerPhase` from the provider file for now — that's expected and fine (Task 6 optionally cleans up that dependency direction). `getDurationForPhase` takes a **nullable** `Session?` because the original returned `Duration.zero` when the active session was null — preserve that.
- After the helper and its tests are green, update the provider: import the helper, delete the eleven private methods, and replace every internal call site with the static-method form. The `nextStop` / `previousStop` getters keep their existing null-guard on `_activeSession` and just call through to the helper.
- **Do not move** the `debugSetPhase` `supersetRest` branch (the one that pre-advances `exerciseIndex` and asserts `hasNextInSuperset`). That's a test seam, not state-machine logic — it stays on the provider.
- Watch out: `_getDurationForPhase`'s exerciseRest branch has a load-bearing superset check (`superset != null && currentSet > 1`). Port it exactly; do not "simplify" it.
- End state: full suite green. The superset test is the canary for the nav-helper extraction (`calculateNextStop`/`calculatePreviousStop`); a failure there means a missed substitution.

**Files:**
- Create: `lib/providers/session/session_state_machine.dart`
- Create: `test/providers/session/session_state_machine_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [ ] Task 3 of 6: Extract `SessionTelemetryRecorder` (scoped state)

*(Source plan Task 2.)*

**Why:** The provider records what happened during a session — when each set started/ended, how much active vs. rest time accrued, what kind of rest occurred — and builds a summary at the end. This is a self-contained responsibility with one clear entry point (`_onPhaseTransition`). Pulling it into its own class means the provider stops juggling event lists and accumulators directly, and the recording logic becomes testable on its own.

**What (overview):** A `SessionTelemetryRecorder` class owns the set/rest event lists, the in-flight drafts, and the per-set time accumulators, exposing methods to open/close sets and rests and to compute the summary. The provider holds one instance, clears it on start/reset, and drives it from `_onPhaseTransition`. The summary produced at `finalizeSession` is byte-for-byte the same as before.

**Concept primer:**
- **Scoped state** — unlike the pure state machine, this class *does* hold mutable fields. But its lifetime is bounded to one session run: the provider clears it on `start()`/`reset()`, so nothing leaks between sessions.
- **Draft** — an in-progress record. A set/rest "opens" (a draft is created with a start time) and later "closes" (the draft becomes a finished event with an end time). The draft is the half-built event held between those two moments.
- **Accumulator** — a running total you add slices to over time (here: active time and inter-rep rest time within the current set).
- **Unmodifiable view** — exposing a list to callers in a way they can read but not mutate, so the recorder stays the single owner of its data.

**Details:**
- Create `lib/providers/session/session_telemetry_recorder.dart` and its test file. Write the failing test first (same rhythm as Task 2).
- State the recorder owns (currently fields on the provider): the `SetEvent` list, the `RestEvent` list, the active set draft, the active rest draft, and the two `Duration` accumulators (active time, inter-rep rest time).
- Public methods to provide (these mirror what the provider's `_onPhaseTransition` already does today): open a set, close a set (takes `repsCompleted`), open a rest (takes the `RestType`, the progress, and a planned duration), close a rest, add an active-time slice, add a rep-rest-time slice, discard in-flight drafts, clear everything, and compute the summary. Expose the two event lists as unmodifiable views.
- Behavioral specifics to preserve from the current provider code (read the existing `_startSetDraft`/`_closeSetDraft`/`_startRestDraft`/`_closeRestDraft`/`_discardDrafts`/`_computeSummary` to get these exactly):
  - Opening a set resets both accumulators to zero.
  - Closing a set with no open draft is a no-op (guard against null).
  - For a `setRest`, the rest event records the current set index; for other rest types the set index is null.
  - For an `overtime` rest, the overtime duration equals the actual elapsed; otherwise it's zero.
  - `clear()` empties both lists *and* discards drafts.
- Test coverage: initial empty state, open→close set records one event, open→close rest records the right `RestType` (include a `supersetRest` case), accumulators reset on new set, slices accumulate into the correct field, `discardDrafts` clears in-flight but not closed events, `clear` resets fully, and `computeSummary` aggregates across multiple events (mirror the assertions in `session_state_provider_event_log_test.dart`).
- Migrate the provider: add a `final` recorder field, delete the moved fields/methods and the two private draft classes at the bottom of the file, and route `_onPhaseTransition`, `start()`, `reset()`, `pause()`'s slice attribution, and `finalizeSession()` through the recorder. The `@visibleForTesting` debug methods `debugRestEventCount`/`debugRestEventTypes` now read from the recorder's event list (their external signature is unchanged so tests don't change).
- One subtlety the plan calls out: the *decision* of what planned duration a rest gets stays on the provider side (a small private helper that returns `getDurationForPhase` except for overtime/paused which are zero), because that's where it lived before. The recorder just stores whatever planned duration it's handed.
- Risk surface: `_onPhaseTransition` is the orchestration heart — it's called from many places. Both `event_log_test.dart` **and** `replace_test.dart` exercise it; both must stay green. The `interRepRestTime`/`activeTime` assertions in `event_log_test.dart` pinpoint a missed slice-attribution site.

**Files:**
- Create: `lib/providers/session/session_telemetry_recorder.dart`
- Create: `test/providers/session/session_telemetry_recorder_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [ ] Task 4 of 6: Extract `SoundDispatcher` (beep timing)

*(Source plan Task 3.)*

**Why:** The last non-core responsibility on the provider is sound: deciding when to schedule OS notification beeps for a backgrounded session, and which in-app beep (if any) to play on each timer tick. This logic is fiddly and timing-sensitive, so isolating it makes both the provider and the beep logic clearer and independently testable. After this task the provider is back to its core: timer ticker, public API, and orchestration of the three helpers.

**What (overview):** A `SoundDispatcher` class decides what to beep and when. It holds references to the beep scheduler and audio player (but doesn't own their lifecycles), exposes static predicates for "should we play in-app sound" and "should we use notifications", a `reschedule` method for the background path, and a `classifyTickEdge` method that returns the list of in-app beeps to play on a given tick boundary. The provider's ticker calls `classifyTickEdge` instead of its three inline beep checks. All sound behavior is preserved.

**Concept primer:**
- **Predicate** — a function that returns a bool answering a yes/no question (e.g. "should in-app sound play right now?").
- **Tick edge** — the boundary between two ticks: the timer state just before this tick and just after. A beep "fires on an edge" when a threshold (e.g. 300 ms remaining) was crossed between the previous remaining time and the new one.
- **Lead time** — how early a beep fires before the moment it marks, so the sound lands on time given audio latency. `_audioLeadTime` = 300 ms, `_countdownLeadTime` = 400 ms (note: source plan prose says 500 — the code says 400; pass it as a parameter and it doesn't matter).
- **Returning a list instead of a nullable** — `classifyTickEdge` returns a `List<BeepType>` (possibly empty), *not* a single nullable beep, because the countdown beep and the go beep can both fire on the same tick when the windows overlap (this was a real fix — commit `2ea37d8`). The provider plays each entry in order.

**Details:**
- Create `lib/providers/session/sound_dispatcher.dart` and its test file. Failing test first.
- Imports the helper needs: `SoundMode` from `settings_provider.dart`, `BeepType` and `ScheduledBeep` from `services/beep_scheduler.dart`, the audio player from `services/audio_beep_player.dart`, the state machine from Task 2 (the future-beep walk simulates upcoming phases using it), and `SessionProgress`/`TimerPhase`/`Session`.
- The class holds nullable scheduler and player references with setters and getters; it does **not** dispose them (the provider owns their lifecycle).
- Static predicates:
  - `shouldPlayInApp(isForegrounded, mode)` → true only when foregrounded and mode is `soundsOnly` or `both`. (When mode is `none`, false.)
  - `shouldUseNotifications(isForegrounded, isPaused, hasActiveSession, mode)` → true only when backgrounded, not paused, has an active session, and mode includes notifications (`both` or `notificationsOnly`). (When mode is `none`, false.)
- `reschedule(...)` (instance method): if no scheduler, do nothing; else compute whether notifications apply, and either schedule the future beeps or cancel all. The future-beep computation (`_calculateFutureBeeps` + `_addBeepsForPhase`) is a near-verbatim port from the provider, with internal calls to `_calculateNextState`/`_getDurationForPhase` swapped to the `SessionStateMachine` static methods.
- `classifyTickEdge(...)` (static): returns `List<BeepType>`. Three independent checks, each may add to the list:
  - **Countdown** fires when the previous remaining was above the countdown threshold (`3s + countdownLeadTime`) and the new remaining dropped to ≤ threshold but still > 0, and the source phase is `getReady`, `setRest`, **or `supersetRest`** (all three — the source plan originally listed only the first two; `supersetRest` was added when supersets shipped, and the live code includes it).
  - **Go** fires when leaving any of `getReady`/`setRest`/`repRest`/`supersetRest` with previous remaining > `audioLeadTime` and new remaining ≤ `audioLeadTime`.
  - **Stop** fires when still in `rep` (prev and new both `rep`) with the same lead-time crossing. Stop is mutually exclusive with the other two by phase predicate, but the function still returns a list.
  - Returns empty when `playInApp` is false or no edge matched.
- Test coverage: each predicate (include the `none` mode → false for both), each beep type from each of its valid source phases (explicitly test `supersetRest` as a countdown and a go source), the empty-list cases, and **the same-tick countdown+go pair** (synthesize a prev remaining just above the countdown threshold and a new remaining just below `audioLeadTime`, expect `[countdown, go]` in that order). **Use ≤ 100 ms granularity between prev and new remaining** in fixtures — the ticker runs at 100 ms, so a 500 ms gap is unrealistic and could mask a regression.
- Migrate the provider: replace the scheduler/player fields with a single `SoundDispatcher` instance; the public `setBeepScheduler`/`setAudioBeepPlayer` setters delegate to it; replace `_rescheduleSound()` calls with `_sound.reschedule(...)`; delete `_rescheduleSound`/`_calculateFutureBeeps`/`_addBeepsForPhase`; and in the ticker, replace the three inline `if (playInApp && ...)` blocks with one `classifyTickEdge` call whose returned list you play in order.
- **Preserve the ticker's two-channel structure exactly** (this is the highest-risk part):
  - The overtime branch stays "sync display only, never `notifyListeners()`". Do not add a notify there.
  - `notifyListeners()` and the reschedule call stay inside the `if (!identical(_progress, prevProgress))` phase-transition guard.
  - `_syncTimerDisplay()` still runs at the end of every tick.
  - Do not touch any existing `_syncTimerDisplay()` call site — the count must stay at your Task 1 baseline.
- Also route `setForegrounded`, `pause`, `reset`, `_advanceByElapsed`'s cancel site, `_enterOvertime`, `exitOvertime`, and the two exact-alarm permission methods through the dispatcher.
- After tests are green, do the **manual sound smoke test** (source plan Task 3 Step 7): run the app, verify in-app countdown/go/stop in a solo session, countdown+go across a superset boundary, a backgrounded countdown notification, and live mode toggling. Tests can't fully cover audio timing — this is the real safety net for this task.

**Files:**
- Create: `lib/providers/session/sound_dispatcher.dart`
- Create: `test/providers/session/sound_dispatcher_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [ ] Task 5 of 6: Sweep — verify provider shape and invariants

*(Source plan Task 4.)*

**Why:** After three extractions it's easy to leave a dangling reference, an unused import, or a dropped `_syncTimerDisplay()` site. This task is the verification pass that proves the refactor is clean and behavior is fully preserved, end to end.

**What (overview):** The provider contains no leftover references to any moved method or field, the `_syncTimerDisplay()` count matches the Task 1 baseline, static analysis is clean, the full suite is green, and a manual end-to-end walk shows no behavioral regression.

**Details:**
- Grep the provider for every moved method/field name (all eleven state-machine methods, the telemetry methods/fields/draft classes, the three sound methods, the old scheduler/player fields). Expect **zero** matches — any survivor is a missed reference.
- Confirm `_syncTimerDisplay()` still appears exactly your Task 1 baseline count (you measured it then; it should be unchanged — 20 unless the baseline differed). Also confirm `timerDisplayNotifier` and the `ValueNotifier` field/dispose still exist.
- Run static analysis (`flutter analyze`) — zero errors. Clean up any unused imports the extractions left behind.
- Run the full test suite — all green, all six existing provider tests plus the three new helper tests.
- Measure the file sizes (provider + three helpers). Don't treat the source plan's LOC targets as hard gates (the provider was already 1,872 LOC, larger than the plan assumed) — the goal is "meaningfully smaller provider, no logic lost," not a specific number.
- Do the manual end-to-end smoke walk from the source plan's Task 4 Step 5 (all ten scenarios: full session, pause/resume, manual overtime, background reconciliation, mid-session edit, mid-session superset edit, superset round walk, next/previous stop, smooth timer text at 10 Hz with no non-timer flicker, hot-restart teardown with no disposed-notifier errors).

**Files:**
- Modify (only if cleanup needed): `lib/providers/session_state_provider.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [ ] Task 6 of 6: *(Optional)* Lift `SessionProgress` and `TimerPhase` into a shared file

*(Source plan Task 5. Purely cosmetic — skip unless you want a cleaner dependency graph.)*

**Why:** The three helper files import `SessionProgress` and `TimerPhase` from the provider — meaning the helpers depend on the very file that uses them (a slightly awkward back-dependency). Moving those two types into their own sibling file makes the dependency flow one-directional: provider and helpers both depend on the shared types, neither depends on the other for them.

**What (overview):** `SessionProgress` and `TimerPhase` live in `lib/providers/session/session_progress.dart`. Every file that used to import them from the provider now imports them from the new file. The suite stays green.

**Details:**
- Move the `TimerPhase` enum and the `SessionProgress` class (including its `copyWith`) out of `session_state_provider.dart` into a new `lib/providers/session/session_progress.dart`.
- Update imports everywhere they were referenced: the provider itself, all three helper files, and every test file that imports those types (the six provider tests + the three new helper tests).
- This is a wide but mechanical diff. Only worth doing if the back-dependency bothers you; the code works fine without it.

**Files:**
- Create: `lib/providers/session/session_progress.dart`
- Modify: `lib/providers/session_state_provider.dart`, the three helper files, and the nine test files that reference the types.

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*
