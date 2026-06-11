# Instructor plan: Get-ready as the tail of a rest

Source spec: [docs/superpowers/specs/2026-06-04-get-ready-as-rest-tail-design.md](../superpowers/specs/2026-06-04-get-ready-as-rest-tail-design.md)

Goal: make "get ready" the **final 10 seconds of each set/exercise rest**, shown
as one uninterrupted countdown, instead of a separate 10s phase tacked on after
the cross-workout rest. Approach A (derived get-ready window) from the spec.

Help levels per task: **default** (Socratic) unless you invoke `/hint`,
`/answer`, or `/fullanswer`. Escalation is scoped to the current task only.

Run tests with `scripts/run_tests.sh` (not raw `flutter test`).

---

## Summary

1. [x] Add `getReadyLeadIn` constant + `isGetReadyMoment` pure helper (test-first)
2. [x] Remove the cross-workout `exerciseRest → getReady` transition (state machine + doc + tests)
3. [x] Flip the UI label to "get ready" in the final 10s of a rest (UI; widget test skipped — no widget-test scaffolding in repo, logic covered by isGetReadyMoment unit tests)

---

### [x] Task 1 of 3: Add `getReadyLeadIn` constant + `isGetReadyMoment` helper

**Why:** Approach A needs one rule that answers "is this moment a get-ready
moment?" so both the UI label and any future caller agree. Putting it in the
pure state-machine layer (no state, no side effects — output depends only on
its arguments) keeps it unit-testable in isolation and reuses the existing
test file. This task introduces no visible behaviour change on its own; it's
the foundation the next two tasks build on.

**What (overview):** `SessionStateMachine` exposes a single constant for the
10-second lead-in and a pure boolean helper that decides whether a given
`(phase, remaining)` pair should read as "get ready". The existing get-ready
duration is sourced from the new constant.

**Concept primer:**
- *Pure helper* — a static function whose result depends only on its inputs,
  with no reads/writes of object state. The other methods in
  `SessionStateMachine` are already written this way.

**Details:**
- Add a public static `const Duration getReadyLeadIn = Duration(seconds: 10)`
  on `SessionStateMachine`.
- In `getDurationForPhase`, the `getReady` case should return `getReadyLeadIn`
  instead of the literal `Duration(seconds: 10)`. The existing "getReady is
  10s" test must still pass unchanged.
- Add a static `bool isGetReadyMoment(TimerPhase phase, Duration remaining)`.
  The rule:
  - `phase == getReady` → **true**, unconditionally (a standalone get-ready
    shows "get ready" for its whole duration).
  - `phase` is one of `setRest`, `supersetRest`, `exerciseRest` → **true** only
    when `remaining > Duration.zero` **and** `remaining <= getReadyLeadIn`.
  - everything else (`repRest`, `rep`, `overtime`, `paused`,
    `workoutComplete`) → **false**. Note `repRest` is deliberately excluded.
- **Write the tests first** (TDD), in a new group inside
  `test/providers/session_state_machine_test.dart`. Cover, at minimum:
  - `getReady` → true at a representative remaining (e.g. 10s and 5s).
  - `exerciseRest` / `setRest` / `supersetRest`: 11s → false; exactly 10s →
    true; 1s → true; 0s → false.
  - `repRest` at 5s → false.
  - `rep`, `overtime`, `paused`, `workoutComplete` → false.
- Boundary matters: `remaining == getReadyLeadIn` (exactly 10s) is **true**,
  `remaining == Duration.zero` is **false**. Make sure your tests pin both.

**Files:**
- `lib/providers/session_state_machine.dart`
- `test/providers/session_state_machine_test.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [x] Task 2 of 3: Remove the cross-workout `exerciseRest → getReady` transition

**Why:** Today the per-tick phase cycle inserts a fresh 10s `getReady` after the
full between-workouts rest — that's the extra countdown we're removing. With
Approach A the get-ready is just the last 10s of the rest itself, so the cycle
should flow `exerciseRest → rep` everywhere. After this, `getReady` is produced
*only* by the explicit entry points (session start, the `jumpTo*` methods,
overtime exit) — never by the automatic cycle.

**What (overview):** `calculateNextState`'s `exerciseRest` case always advances
to `rep`. The architecture doc and the affected unit tests reflect the removed
edge. The bottom-bar next/previous navigation helpers are **left untouched**.

**Details:**
- In `calculateNextState`, the `exerciseRest` case currently branches on a
  cross-workout signal (`currentSet == 1 && exerciseIndex == 0`) to choose
  `getReady` vs `rep`. Make it unconditionally advance to `rep`. Remove the
  now-dead local and the explanatory comment block for that branch.
- **Do not touch** `calculateNextStop` / `firstStopAtOrAfter` /
  `lastStopBefore`. Those belong to the *stop-navigation* model (the
  next/previous buttons), which still lands on a real standalone `getReady`
  when you jump across a workout boundary. Only the *phase cycle*
  (`calculateNextState`) changes here. The architecture doc explains the
  two-model split if you want to re-read it.
- Update `docs/architecture/session-state-machine.md`: in the phase-cycle
  mermaid diagram, the `exerciseRest --> getReady: cross-workout ...` edge goes
  away and `exerciseRest --> rep` becomes unconditional. Add a short note that
  `getReady` is now only an entry-point phase (start / jumps / overtime exit),
  not produced by the cycle. Leave the `exerciseRest` duration note (its two
  duties around superset rounds) intact — that's still accurate.
- Update the tests in `test/providers/session_state_machine_test.dart`. The
  existing test 'exerciseRest → getReady on a cross-workout boundary'
  (around line 222) should be **rewritten** to assert the new
  `exerciseRest → rep` behaviour for that same input — don't just delete it.
  Scan the rest of the file for any other case that asserts the cycle producing
  `getReady` cross-workout and update those too. (Stop-navigation tests that
  expect `getReady` — e.g. "off the end of a workout crosses to the next at
  getReady" — are the navigation model and should stay green unchanged.)
- Run the full suite; nothing outside the intended edges should go red.

**Files:**
- `lib/providers/session_state_machine.dart`
- `docs/architecture/session-state-machine.md`
- `test/providers/session_state_machine_test.dart`

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*

---

### [x] Task 3 of 3: Flip the UI label to "get ready" in the final 10s of a rest

**Why:** This is the visible payoff. The phase label (`phaseText`) is computed
in the main provider-`Consumer` build, which only rebuilds on `notifyListeners()`
— i.e. on phase changes, not on the per-tick `_remaining` updates that flow
through `timerDisplayNotifier` at 10 Hz. So as-is the label can't flip mid-phase
at the 0:10 mark. We need the label to react to `remaining`, using the
`isGetReadyMoment` rule from Task 1.

**What (overview):** During a `setRest` / `supersetRest` / `exerciseRest`, the
phase label shows its normal rest text until 10s remain, then switches to "get
ready" (with the same secondary-colour style the standalone get-ready already
uses) and stays there as the number counts continuously to zero. Standalone
`getReady` still reads "get ready" throughout. Total time is unchanged.

**Details:**
- The label `Text(phaseText, style: phaseTextStyle)` lives around
  `session_active_screen.dart:478`; `phaseText` / `phaseTextStyle` are set in
  the `switch` around lines 262–294. The countdown number just below it already
  rebuilds per tick via a `ValueListenableBuilder` on
  `provider.timerDisplayNotifier`.
- Make the label react to `remaining` the same way the number does: it should
  re-evaluate whenever `timerDisplayNotifier` ticks. Keep computing the base
  `phaseText` / style in the existing `switch`, then, when the current phase is
  one of the three carved rests **and** `isGetReadyMoment(phase, remaining)` is
  true, override the text to `'get ready'` and the style to the same
  secondary-colour style the `getReady` case uses (lines 285–288). Don't
  duplicate that style literal more than necessary — reuse it.
- `phase == getReady` already renders "get ready" through the `switch`, so the
  override only needs to handle the rest phases. Make sure the two paths don't
  fight (e.g. don't override during `rep`, `repRest`, `overtime`, `paused`).
- Watch the data source: the per-tick value you compare against is the same
  `Duration` the number widget reads from `timerDisplayNotifier`. During
  overtime that notifier carries elapsed-up time — `isGetReadyMoment` already
  returns false for `overtime`, so the label stays correct, but keep it in mind.
- **Widget test:** find the existing active-screen widget tests to model setup
  (how they build the screen with a `SessionStateProvider` and drive it into a
  phase). Add cases: an `exerciseRest` at 11s remaining shows
  'rest between exercises'; at 10s shows 'get ready'; a standalone `getReady`
  shows 'get ready'. Pump/settle as those existing tests do.

**Files:**
- `lib/presentation/screens/session_flow/session_active_screen.dart`
- the active-screen widget test file (locate it under `test/`)

> *Current help level: **default** (Why/What/Details only — Socratic guidance in chat). Use `/hint`, `/answer`, or `/fullanswer` to escalate.*
