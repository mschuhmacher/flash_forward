# Get-ready as the tail of a rest — design

## Problem

Crossing from one workout into the next currently plays a **full**
between-exercises rest (`exerciseRest`, `workout.timeBetweenExercises`) and
*then* a **separate, fresh 10s `getReady`** phase. The countdown resets
between them: the rest counts down to `0:00`, then the timer jumps back to
`0:10` and counts down again before the first rep. This double countdown reads
as a bug.

Desired behaviour: the get-ready should be the **final 10 seconds of the rest
itself**, shown as one uninterrupted countdown. At `0:10` remaining the label
flips to "get ready"; the number keeps falling to `0:00`, then the rep starts.
Total rest time is unchanged (the extra 10s at the workout boundary
disappears). This should apply to **every set/exercise transition**, not just
the cross-workout boundary.

## Scope

In scope — the get-ready label tail applies to:

- `setRest` (between sets, solo)
- `supersetRest` (between superset members)
- `exerciseRest` (between exercises, between workouts, between superset rounds)

Out of scope / unchanged:

- `repRest` (between reps within a set) — **excluded**. It is a between-*reps*
  rest, not a set/exercise transition. Consistent with the beep system, which
  already skips the 3-2-1 countdown for `repRest`.
- Standalone `getReady` (session start, `jumpTo*`, overtime exit) — still a
  real 10s phase with no preceding rest. It already displays "get ready" and
  beeps; no change.

## Approach: derived get-ready window

"Get ready" stops being a phase tacked on *after* a rest. Instead a single
rule defines when the UI is in a get-ready moment:

```
isGetReadyMoment(phase, remaining) =
    phase == getReady
    OR (phase ∈ {setRest, supersetRest, exerciseRest}
        AND Duration.zero < remaining <= getReadyLeadIn)
```

where `getReadyLeadIn = Duration(seconds: 10)`.

Why this approach (vs. keeping `getReady` as a real phase entered early):

- The beep system **already** treats `setRest` / `supersetRest` /
  `exerciseRest` identically to `getReady` — 3-2-1 countdown in the final ~3s
  and a "go" beep at the rest→rep boundary
  (`SoundDispatcher._addBeepsForPhase`, `classifyTickEdge`). So audibly every
  rest already behaves like a get-ready. **No beep changes are needed.**
- The countdown is automatically continuous, because it is literally one
  phase running one countdown — nothing resets.
- No changes to the ticker, the background catch-up loop, or
  `_advanceByElapsed`'s `remaining <= 0` transition machinery.
- It *simplifies* the state machine by removing the cross-workout special case.

## Changes

1. **Constant.** Introduce `getReadyLeadIn = Duration(seconds: 10)` as the
   single source for both the get-ready window and `getReady`'s own duration
   (`getDurationForPhase` for `getReady` reuses it instead of a literal `10`).

2. **Single source of truth.** Add a pure helper
   `SessionStateMachine.isGetReadyMoment(TimerPhase phase, Duration remaining)`
   implementing the rule above. Unit-tested in isolation.

3. **State machine.** Remove the cross-workout branch in `calculateNextState`'s
   `exerciseRest` case (`isCrossWorkout` → `getReady`); `exerciseRest → rep`
   always. `getReady` is then produced only by the standalone entry points
   (start / jumps / overtime exit), which set it explicitly. Update
   `docs/architecture/session-state-machine.md` (the `exerciseRest --> getReady`
   edge and the surrounding notes) and the affected tests in
   `test/providers/session_state_machine_test.dart`.

4. **UI.** Wrap the `phaseText` label in `session_active_screen.dart` in a
   `ValueListenableBuilder<Duration>` on `timerDisplayNotifier`, so it
   re-derives "get ready" (with the existing secondary-colour style) when
   `isGetReadyMoment` is true for the current phase + remaining. This is the
   only way the label can flip mid-phase at `0:10`, because per-tick
   `_remaining` updates flow through `timerDisplayNotifier` and deliberately
   bypass `notifyListeners()`. Cost is negligible — it rebuilds a single
   `Text`, the way the timer number already does at 10 Hz.

## Edge cases

- **Rest shorter than 10s** (e.g. a 5s `setRest`): `remaining <= 10s` holds for
  the whole rest, so it shows "get ready" for its entire duration. Acceptable.
- **Overtime**: counts *up*, `remaining` is `Duration.zero`; not a get-ready
  moment. Unchanged.
- **Paused / workoutComplete**: not in the phase set; unchanged.

## Telemetry impact (accepted)

Removing the cross-workout `getReady` phase means workout boundaries no longer
log a distinct `getReady` `RestEvent` — they log the `exerciseRest` event only,
and the carved get-ready tail is part of that rest event rather than a separate
segment. Standalone get-readies still log a `getReady` event as before.
Telemetry tracks set grades / weights and per-rest durations, not get-ready
granularity, so this is acceptable.

## Testing

- `isGetReadyMoment`: true for `getReady` at any remaining; true for
  set/superset/exercise rest when `0 < remaining <= 10s`; false above 10s, at
  `0`, and for `repRest` / `rep` / `overtime` / `paused` / `workoutComplete`.
- `calculateNextState`: `exerciseRest → rep` on the former cross-workout case
  (set 1, exercise 0, new workout); the removed `exerciseRest → getReady` test
  is updated, not just deleted.
- `getDurationForPhase`: `getReady` still 10s (now via the constant).
- Widget: label shows the rest text above 10s and flips to "get ready" at/below
  10s for an `exerciseRest`/`setRest`; stays "get ready" throughout a standalone
  `getReady`.
