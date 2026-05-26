# 100ms Ticker & UI Refresh Optimization — Design

**Date:** 2026-05-26
**Status:** Draft for review
**Related files:**
- `lib/providers/session_state_provider.dart`
- `lib/presentation/screens/session_flow/session_active_screen.dart`

---

## Problem

`SessionStateProvider` currently ticks at 1Hz. Two consequences:

1. **Audio beep timing is unreliable.** The early-fire logic for the go/stop beeps fires when `_remaining` crosses a 300ms threshold (e.g. `previousRemaining > 300ms && _remaining <= 300ms`). At 1Hz, `_remaining` jumps by ~1000ms per tick, so the threshold-crossing condition is fragile: if `previousRemaining` happens to land just under 1000ms due to drift, `_advanceByElapsed` runs, the phase transitions, and the early-fire condition is missed entirely. The result is sporadic missed beeps. The current code has no fallback because the originally planned migration to 100ms ticks was meant to make the early-fire window reliable.

2. **No path to sub-second UI precision.** Future enhancement: the user wants the option to show tenths of seconds on the timer display (e.g. `12.3` instead of `12`). At 1Hz this is impossible without re-architecting.

Both problems are solved by moving the ticker to 100ms. But the obvious naive change introduces a third problem:

3. **UI rebuild flood.** `SessionStateProvider` extends `ChangeNotifier` and calls `notifyListeners()` on every tick. The active session screen wraps its entire widget tree in `Consumer2<PresetProvider, SessionStateProvider>`, and the bottom bar wraps in `Consumer2<SessionLogProvider, SessionStateProvider>`. At 1Hz this is invisible; at 10Hz the whole tree rebuilds 10× per second, causing visible jank and significant wasted work, since the only field that actually changes per-tick is `_remaining` (or `_overtimeElapsed` during overtime).

## Goals

- Move the ticker frequency from 1Hz to 10Hz (100ms intervals) to make audio beep early-fire reliable and enable future sub-second UI precision.
- Limit per-tick UI rebuilds to the timer display widget only. All other widgets in the active session screen (exercise card, set/rep indicators, bottom bar, buttons) rebuild only on phase transitions and user actions, as they do today.
- Preserve all existing public APIs of `SessionStateProvider`. No widget restructuring beyond wrapping the timer text in one new builder widget.
- No new dependencies.

## Non-goals

- **Displaying tenths of seconds.** The infrastructure will support it (state ticks at 10Hz, the timer widget rebuilds at 10Hz), but the visible format stays as whole seconds. Adding tenths later becomes a pure UI change — modify `formatDuration()` or its consumers, no provider/architecture changes.
- **Splitting `SessionStateProvider` into multiple providers.** Considered and rejected (see Approaches Considered).
- **Per-frame animations or smooth ring fills.** Out of scope for this change. The current UI has no such elements.
- **Backwards-compatibility shims.** Internal state, internal callers — change in place.

---

## Architecture

The change has three parts, applied together:

1. **Provider:** Add a `ValueNotifier<Duration>` that publishes the timer's current display value. Update it on every tick. Move the per-tick `notifyListeners()` call inside the phase-transition guard so it only fires when the rest of the UI actually needs to re-derive.
2. **Widget:** Wrap the timer `Text` widget in a `ValueListenableBuilder` that reads the new notifier. Three existing reads of `remaining`/`overtimeElapsed` (all colocated in this one widget) become reads of the builder's `displayValue`.
3. **Ticker:** Change `Timer.periodic(Duration(seconds: 1), ...)` to `Timer.periodic(Duration(milliseconds: 100), ...)`.

### Why these three together

The ticker change alone causes the rebuild flood. The provider change alone doesn't help anything (the notifier is unused). The widget change alone is impossible without the notifier. They are a single coherent change with no useful intermediate state, and should land as one commit.

### Why `ValueNotifier` is the right primitive

`ChangeNotifier.notifyListeners()` is a coarse broadcast — every `Consumer<SessionStateProvider>` rebuilds regardless of which field changed. `ValueNotifier<T>` is a fine-grained, per-value broadcast — only widgets listening to the specific notifier rebuild. The two coexist on the same provider: high-frequency values get their own notifiers, low-frequency state changes use the existing `notifyListeners()` path.

This is Flutter's standard primitive for exactly this scenario (one high-frequency value on an otherwise low-frequency provider). No package required, no architectural rework, no new patterns to learn.

### Why one unified `timerDisplayNotifier` instead of two

The timer text widget displays either `_remaining` (normal phases) or `_overtimeElapsed` (overtime), depending on phase. Two implementation options:

- Two separate notifiers (`remainingNotifier`, `overtimeElapsedNotifier`), widget picks which to read based on phase.
- One unified notifier (`timerDisplayNotifier`) that always holds whichever value should currently be displayed; provider decides which based on phase.

Unified wins: simpler consumer (no phase-based ternary in the widget), provider already knows the phase, no semantic loss (the private `_remaining` and `_overtimeElapsed` fields still exist as the source of truth for game logic).

---

## Provider Changes (`SessionStateProvider`)

### New field

```dart
/// Publishes the value the timer widget should currently display.
/// Updated on every tick (10 Hz) and on any state change that affects
/// _remaining or _overtimeElapsed. Listeners of this notifier rebuild
/// independently of the provider's notifyListeners() — the rest of the
/// screen does not rebuild when this fires.
final ValueNotifier<Duration> timerDisplayNotifier =
    ValueNotifier(Duration.zero);
```

### New private helper

```dart
/// Updates timerDisplayNotifier to reflect the current displayable timer
/// value — _overtimeElapsed during overtime, _remaining otherwise.
/// Called wherever _remaining or _overtimeElapsed is mutated, or whenever
/// the phase transitions between overtime and normal.
///
/// IMPORTANT: must be called AFTER _progress is updated, since it reads
/// _progress.phase to decide which value to publish.
void _syncTimerDisplay() {
  timerDisplayNotifier.value = _progress.phase == TimerPhase.overtime
      ? _overtimeElapsed
      : _remaining;
}
```

### Ticker changes (`_startTicker`)

Two changes to the existing method:

1. **Frequency:** `Duration(seconds: 1)` → `Duration(milliseconds: 100)`.
2. **Notification scope:** the per-tick `notifyListeners()` call (currently at the end of the tick callback) is removed from the tick body and moved inside the existing `if (!identical(_progress, prevProgress))` block. The block, which previously only ran `_rescheduleSound()`, now also runs `notifyListeners()`.

After every state mutation in the tick (the `_overtimeElapsed += ...` path and the `_advanceByElapsed(...)` path), call `_syncTimerDisplay()` to publish the new display value. This replaces the implicit "everyone rebuilds and reads `remaining` directly" pattern with explicit per-tick publication to the notifier.

The existing beep-firing logic (countdown / go / stop early-fire checks based on `previousRemaining` vs. `_remaining` thresholds) is unchanged. It becomes more reliable at 100ms ticks because the early-fire window is hit on the first tick that crosses it, and the cross-detection condition naturally guarantees single-fire (the next tick has `previousRemaining ≤ threshold` so the condition fails).

### Other call sites that need `_syncTimerDisplay()`

The invariant: anywhere `_remaining` or `_overtimeElapsed` is assigned, or the phase transitions into/out of overtime, call `_syncTimerDisplay()`.

The implementation plan will enumerate the exact methods. From the existing code, the categories are:

- **Session lifecycle:** `start()`, `reset()` — set initial / cleared display value.
- **Phase entry:** methods that set `_remaining = _getDurationForPhase(...)` (e.g. `_advanceByElapsed`'s phase-transition loop, `_enterPostSetRest`, jump methods).
- **Overtime entry/exit:** the method that enters `TimerPhase.overtime` (resets `_overtimeElapsed` to zero, switches the displayed source) and the method that exits it (switches back to `_remaining`).
- **Manual user actions:** `advanceManually`, `jumpToNext`, `jumpToPrevious` — any method that resets `_remaining`.

Methods that do **not** need to call `_syncTimerDisplay()`:
- `pause()` / `resume()` — neither `_remaining` nor `_overtimeElapsed` changes; only `_isPaused`.
- Any method that only mutates phase-independent state (set logs, rest events, etc.).

### Disposal

```dart
@override
void dispose() {
  timerDisplayNotifier.dispose();
  _ticker?.cancel();
  super.dispose();
}
```

Verify whether `SessionStateProvider` currently overrides `dispose()`. If yes, add the notifier disposal to the existing override. If no, add the override.

---

## Widget Changes (`session_active_screen.dart`)

### Audit results

A grep of all `.dart` files for `.remaining\b` and `.overtimeElapsed\b` returned exactly three reads outside the provider itself, all in `session_active_screen.dart` and all within the same `Text` widget (lines 380-418):

| Line | Read | Purpose |
|---|---|---|
| 383 | `sessionStateData.overtimeElapsed` | Displayed value during overtime |
| 386 | `sessionStateData.remaining` | Displayed value during normal phases |
| 409 | `sessionStateData.remaining < Duration(seconds: 10)` | Color threshold (switch to `secondary` color when <10s during rest phases) |

No other widgets in the codebase read these fields. The bottom bar (`session_active_bottom_bar.dart`) reads `phase`, `nextStop`, `previousStop`, `activeSession` — none of which change per-tick — so it requires no changes.

### The change

Wrap the existing `Text` widget in a `ValueListenableBuilder<Duration>`:

```dart
Center(
  child: ValueListenableBuilder<Duration>(
    valueListenable: sessionStateData.timerDisplayNotifier,
    builder: (context, displayValue, _) {
      return Text(
        formatDuration(displayValue),
        style: context.h1.copyWith(
          color: () {
            if (sessionStateData.isPaused) {
              return context.colorScheme.tertiary;
            } else if (sessionStateData.phase == TimerPhase.getReady) {
              return context.colorScheme.secondary;
            } else if (sessionStateData.phase == TimerPhase.rep) {
              return context.colorScheme.onPrimary;
            } else if (sessionStateData.phase == TimerPhase.overtime) {
              return context.colorScheme.secondary;
            } else if ((sessionStateData.phase == TimerPhase.repRest ||
                        sessionStateData.phase == TimerPhase.setRest ||
                        sessionStateData.phase == TimerPhase.supersetRest ||
                        sessionStateData.phase == TimerPhase.exerciseRest) &&
                    displayValue < Duration(seconds: 10)) {
              return context.colorScheme.secondary;
            } else {
              return context.colorScheme.onPrimary;
            }
          }(),
        ),
        textScaler: TextScaler.linear(2.5),
      );
    },
  ),
),
```

Three substantive differences from the current code:

1. The phase-based ternary that picked between `overtimeElapsed` and `remaining` for the display value is gone — `displayValue` already holds whichever should be shown.
2. The color check at line 409 reads `displayValue` instead of `sessionStateData.remaining` — same value, but now sourced from the notifier (rebuilds 10×/sec instead of once per phase transition).
3. The reads of `sessionStateData.phase` and `sessionStateData.isPaused` inside the builder are unchanged. These only change on phase transitions / user actions and trigger their own rebuilds via the existing `Consumer2`. The `ValueListenableBuilder` re-evaluates them by closure on each notifier-driven rebuild, which is correct.

### Why `Consumer2` wrappers can stay

The outer `Consumer2<PresetProvider, SessionStateProvider>` (active screen) and `Consumer2<SessionLogProvider, SessionStateProvider>` (bottom bar) remain. After this change, `SessionStateProvider.notifyListeners()` only fires on phase transitions and user actions — which is exactly when these wrappers should rebuild. Removing them would force extracting per-field providers, which is unnecessary churn.

---

## Approaches Considered

### Approach 1: `ValueNotifier` carve-out (chosen)
Add `timerDisplayNotifier` to `SessionStateProvider`. Stop per-tick `notifyListeners()`. Wrap timer text in `ValueListenableBuilder`.

- **Pros:** Minimal API change, no new dependencies, surgical scope (1 provider field + 1 helper method + 1 widget wrapper). Audit confirmed only 3 colocated reads exist.
- **Cons:** None significant.

### Approach 2: Split `SessionStateProvider` into two providers
Extract a `TimerTickProvider` holding `_remaining` and `_overtimeElapsed`. Wire it up separately in `main.dart`. Active screen consumes both providers.

- **Pros:** Cleaner conceptual separation.
- **Cons:** `_remaining` is tightly coupled to phase transition logic, beep firing, and `_advanceByElapsed`. Extracting requires shared state plumbing between the two providers (`SessionStateProvider` still needs to read it for beep timing). More files, more wiring, no real benefit.

### Approach 3: `Selector<SessionStateProvider>` everywhere
Keep per-tick `notifyListeners()`. Replace `Consumer2` wrappers with `Selector`s that limit rebuilds to widgets whose selected value changed.

- **Pros:** No provider API change.
- **Cons:** `Selector` still evaluates its selector function on every notification — 10Hz CPU work across many widgets. The screen-wide `Consumer2` would need restructuring (`Selector` only watches one provider). More work, worse outcome than Approach 1.

---

## Testing

No automated test changes required. The grep for ticker references in `test/` returned zero matches — there are no tests today that assert on tick frequency or per-tick behavior. Existing tests that exercise `start()`, `pause()`, phase transitions, and beep scheduling continue to work since the public API is unchanged.

Manual verification on device after implementation:

- Start a session with a `getReady` phase ≥ 5 seconds. Confirm the timer text counts down smoothly. Confirm no visible jank in the surrounding UI during the countdown.
- Trigger the countdown beep, go beep, and stop beep across multiple phases. Confirm all fire reliably (not sporadic as before).
- Enter overtime. Confirm the timer text switches to counting up from zero and continues rendering smoothly.
- Pause and resume. Confirm the timer stops/restarts correctly and the displayed value matches the actual `_remaining`.
- Background the app for 30+ seconds during a phase shorter than 30 seconds. Resume. Confirm the timer jumps to the correct post-catchup phase and value.
- Cross the `<10s` color threshold during a rest phase. Confirm the color changes within ~100ms of crossing (previously was tied to the phase transition).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A future widget added by another developer reads `sessionStateData.remaining` directly and silently breaks (only updates on phase transitions instead of every tick). | Add a brief comment on the `remaining` and `overtimeElapsed` getters in `SessionStateProvider` pointing readers to `timerDisplayNotifier` for high-frequency UI updates. |
| A method that mutates `_remaining` or `_overtimeElapsed` forgets to call `_syncTimerDisplay()`, causing the timer to display stale data until the next tick. | The 100ms tick rate means stale data lives at most 100ms — visible only as a one-frame flicker, not a sustained bug. Acceptable. The implementation plan will enumerate all call sites to minimize the chance. |
| `ValueListenableBuilder` captures stale `sessionStateData` by closure (phase, isPaused) between phase transitions. | Not a real risk: the outer `Consumer2` rebuilds on phase transitions, which rebuilds the `ValueListenableBuilder` itself with a fresh closure. The notifier-driven rebuilds in between phase transitions are correct because phase doesn't change during them. |

---

## Implementation Scope

| File | Change |
|---|---|
| `lib/providers/session_state_provider.dart` | Add `timerDisplayNotifier` field. Add `_syncTimerDisplay()` private helper. Change ticker interval to 100ms. Move per-tick `notifyListeners()` inside the phase-transition guard. Call `_syncTimerDisplay()` at every `_remaining` / `_overtimeElapsed` mutation and at overtime entry/exit. Add/update `dispose()` to dispose the notifier. |
| `lib/presentation/screens/session_flow/session_active_screen.dart` | Wrap the timer `Text` widget (lines 380-418) in `ValueListenableBuilder<Duration>` reading `timerDisplayNotifier`. Replace 3 reads of `remaining`/`overtimeElapsed` with `displayValue`. |

Total: 2 files, no new dependencies, no public API changes.
