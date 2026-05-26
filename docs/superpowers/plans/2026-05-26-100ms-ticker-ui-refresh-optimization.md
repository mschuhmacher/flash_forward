# 100ms Ticker & UI Refresh Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `SessionStateProvider`'s ticker from 1Hz to 10Hz while limiting per-tick UI rebuilds to the timer text widget only, via a `ValueNotifier<Duration>` carve-out.

**Architecture:** Add a single `ValueNotifier<Duration> timerDisplayNotifier` to `SessionStateProvider`. A new private helper `_syncTimerDisplay()` publishes the current display value (either `_remaining` or `_overtimeElapsed` based on phase) to the notifier. The helper is called immediately before every `notifyListeners()` call in mutation methods, plus on every ticker tick after state mutation. The screen-wide `notifyListeners()` is moved inside the phase-transition guard in the ticker so it only fires on transitions, not every tick. The timer `Text` widget in `session_active_screen.dart` is wrapped in a `ValueListenableBuilder` that reads the notifier. The ticker frequency changes from `Duration(seconds: 1)` to `Duration(milliseconds: 100)`.

**Tech Stack:** Flutter, Dart, `provider` package, `ChangeNotifier`, `ValueNotifier`, `ValueListenableBuilder`.

**Spec:** [docs/superpowers/specs/2026-05-26-100ms-ticker-ui-refresh-optimization-design.md](../specs/2026-05-26-100ms-ticker-ui-refresh-optimization-design.md)

---

## Background for the implementer

### What `SessionStateProvider` does

It's a `ChangeNotifier`-based provider holding session state: which workout/exercise/set/rep the user is on (`_progress`), how much time remains in the current phase (`_remaining`), and how long the user has been in overtime (`_overtimeElapsed`). A 1-second periodic `Timer` (`_ticker`) advances `_remaining` and triggers phase transitions when it hits zero. The whole tree under `Consumer2<…, SessionStateProvider>` rebuilds on every tick because `notifyListeners()` is called from the tick callback.

### What we're changing

- The ticker becomes 100ms instead of 1s.
- A new `ValueNotifier<Duration>` exposes the displayable timer value (auto-switches between `_remaining` and `_overtimeElapsed`).
- Per-tick `notifyListeners()` is removed from the tick body and moved inside the existing phase-transition guard, so `Consumer`s rebuild only on transitions.
- The timer `Text` widget in `session_active_screen.dart` is wrapped in `ValueListenableBuilder<Duration>` so only it rebuilds at 10Hz.

### Why this works without changing the rest of the screen

Audit confirmed only **three reads** of `remaining`/`overtimeElapsed` exist in the entire `lib/` tree, all colocated in one `Text` widget in `session_active_screen.dart` (lines 380-418). The `Consumer2` wrappers in `session_active_screen.dart` and `session_active_bottom_bar.dart` stay — after this change, the provider only notifies on phase transitions, which is exactly when those wrappers should rebuild.

### Critical ordering rule

`_syncTimerDisplay()` reads `_progress.phase` to decide whether to publish `_overtimeElapsed` (during overtime) or `_remaining` (otherwise). **It must always be called AFTER `_progress` has been updated**, never before. In existing mutation methods this is naturally true because `_progress` is assigned before `notifyListeners()` is called; we just slot `_syncTimerDisplay()` in immediately before `notifyListeners()`.

### Tests

This repo uses `flutter_test`. Existing tests live in `test/providers/session_state_provider_*.dart` and exercise the public API (`start`, `pause`, `resume`, `requestManualOvertime`, `exitOvertime`, `debugSetPhase`, etc.). **Always run tests via `./scripts/run_tests.sh`** — never use raw `flutter test` (output is too large for the bash buffer). The script writes full output to `/tmp/flutter_test_result.txt` and prints a one-line summary.

---

## File Structure

| File | Action | Purpose |
|---|---|---|
| `lib/providers/session_state_provider.dart` | Modify | Add notifier, helper, ticker frequency change, move per-tick notify, sprinkle `_syncTimerDisplay()` calls |
| `lib/presentation/screens/session_flow/session_active_screen.dart` | Modify | Wrap timer `Text` in `ValueListenableBuilder<Duration>`, replace 3 reads of `remaining`/`overtimeElapsed` with `displayValue` |
| `test/providers/session_state_provider_timer_display_notifier_test.dart` | Create | New test file: covers the `timerDisplayNotifier` contract |

---

## Task 1: Add `timerDisplayNotifier` field and `_syncTimerDisplay()` helper (TDD)

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (add field near line 108-122, add helper method)
- Create: `test/providers/session_state_provider_timer_display_notifier_test.dart`

This task introduces the new public field and private helper, plus a test file that asserts the contract. No call-site wiring yet — that comes in later tasks. After this task, the notifier exists but is only updated by direct test calls or by future task changes.

- [ ] **Step 1: Write the failing test**

Create `test/providers/session_state_provider_timer_display_notifier_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timerDisplayNotifier', () {
    final fixture = Session(
      title: 'test',
      label: 'other',
      workouts: [
        Workout(
          title: 'WorkoutTitle',
          label: 'Other',
          exercises: [
            Exercise(
              title: 'ExerciseTitle',
              description: 'TestDescription',
              label: 'Other',
              sets: 2,
              reps: 10,
              timeBetweenSets: 10,
            ),
          ],
          timeBetweenExercises: 100,
        ),
      ],
    );

    test('exists as a ValueNotifier<Duration> initialized to zero', () {
      final p = SessionStateProvider();
      expect(p.timerDisplayNotifier, isA<ValueNotifier<Duration>>());
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: FAIL with compile error "The getter 'timerDisplayNotifier' isn't defined for the type 'SessionStateProvider'."

- [ ] **Step 3: Add the field and helper to `SessionStateProvider`**

Open `lib/providers/session_state_provider.dart`. Find the field block ending around line 117 (just after the `static const Duration _countdownLeadTime = Duration(milliseconds: 400);` line). Add the new field immediately after `_countdownLeadTime`:

```dart
  // ─── Timer display notifier ──────────────────────────────────────
  // Publishes the value the timer widget should currently display.
  // Updated on every tick (10 Hz) and on any state change that affects
  // _remaining or _overtimeElapsed. Listeners of this notifier rebuild
  // independently of the provider's notifyListeners() — the rest of the
  // screen does not rebuild when this fires.
  final ValueNotifier<Duration> timerDisplayNotifier =
      ValueNotifier(Duration.zero);
```

No new import is needed: `ValueNotifier` is in `package:flutter/foundation.dart`, which is re-exported by `package:flutter/material.dart` — already imported at the top of the file.

Now add the private helper. Find a logical spot — immediately before `_startTicker()` at line 878 is a good place. Insert:

```dart
  /// Updates [timerDisplayNotifier] to reflect the current displayable
  /// timer value — `_overtimeElapsed` during overtime, `_remaining`
  /// otherwise. Call wherever `_remaining` or `_overtimeElapsed` is
  /// mutated, or whenever the phase transitions between overtime and
  /// normal.
  ///
  /// IMPORTANT: must be called AFTER `_progress` is updated, since it
  /// reads `_progress.phase` to decide which value to publish.
  void _syncTimerDisplay() {
    timerDisplayNotifier.value = _progress.phase == TimerPhase.overtime
        ? _overtimeElapsed
        : _remaining;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: PASS — `timerDisplayNotifier` exists, is a `ValueNotifier<Duration>`, initialized to `Duration.zero`.

- [ ] **Step 5: Verify no broader regressions**

Run: `./scripts/run_tests.sh`
Expected: All tests pass. (The helper is unused so it'll trigger an "unused element" hint — that's expected and resolves in later tasks. The field is final, no warning.)

- [ ] **Step 6: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_timer_display_notifier_test.dart
git commit -m "add timerDisplayNotifier and _syncTimerDisplay() to SessionStateProvider.

scaffolds the ValueNotifier carve-out for the 100ms ticker refactor.
the notifier and helper are unused so far — call sites are wired in
subsequent tasks. test asserts the notifier exists, is a
ValueNotifier<Duration>, and is initialized to Duration.zero.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Wire `_syncTimerDisplay()` into all mutation methods (no behavior change yet)

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (15 call sites — one new line before each `notifyListeners()` in mutation methods)
- Modify: `test/providers/session_state_provider_timer_display_notifier_test.dart` (add tests asserting notifier value tracks state)

This task adds `_syncTimerDisplay()` calls without changing any user-visible behavior. The ticker is still 1Hz and still calls `notifyListeners()` on every tick — those changes come in Task 3. After this task, `timerDisplayNotifier.value` is always in sync with the actual displayable value whenever a mutation method runs.

The rule is mechanical: **immediately before every `notifyListeners()` call in a method that mutates `_remaining`, `_overtimeElapsed`, or `_progress.phase`, add `_syncTimerDisplay();`**. The ticker itself is handled in Task 3.

### Call sites (precise list)

| Method | Notify line(s) | Action |
|---|---|---|
| `jumpToWorkout` (~L246) | One | Add `_syncTimerDisplay();` above |
| `jumpToExercise` (~L273, L289, L307) | **Three branches** (cross-workout-back, normal, cross-workout-forward) | Add `_syncTimerDisplay();` above each |
| `_applyJumpTarget` (~L356) | One | Add `_syncTimerDisplay();` above |
| `jumpToSet` (~L537, L549) | Two branches | Add `_syncTimerDisplay();` above each |
| `start` (~L666) | One | Add `_syncTimerDisplay();` above |
| `reset` (~L793) | One | Add `_syncTimerDisplay();` above |
| `reconcileAfterBackground` (~L811, L833) | Two branches with `notifyListeners()` | Add `_syncTimerDisplay();` above each. (The `exitOvertime()` early-return branch handles itself in `exitOvertime`.) |
| `advanceManually` (~L875) | One | Add `_syncTimerDisplay();` above |
| `_enterOvertime` (~L1480) | One | Add `_syncTimerDisplay();` above |
| `exitOvertime` (~L1505) | One | Add `_syncTimerDisplay();` above |
| `debugSetPhase` (~L1540) | One | Add `_syncTimerDisplay();` above |

Total: **15 distinct insertion points** across 11 methods. The pattern is purely mechanical — find each `notifyListeners();` in the methods above and insert `_syncTimerDisplay();` immediately before it.

### Methods that do NOT need a call

- `pause()`, `resume()` — neither `_remaining` nor `_overtimeElapsed` is changed. The display value should freeze; existing notifier value is already correct.
- `setBeepScheduler`, `setAudioBeepPlayer`, `setSoundMode`, `setRestOvertimeOnBackground`, `setForegrounded` — no timer state change.
- `incrementWeekIndex`, `decrementWeekIndex`, etc. — pre-session navigation, no active timer.
- `_startTicker` — handled in Task 3.

- [ ] **Step 1: Write the failing test**

Append to `test/providers/session_state_provider_timer_display_notifier_test.dart` inside the `group('timerDisplayNotifier', ...)`:

```dart
    test('start() syncs notifier to initial getReady duration', () {
      final p = SessionStateProvider()..start(fixture);
      // After start, phase is getReady with default 10s duration.
      expect(p.phase, TimerPhase.getReady);
      expect(p.remaining, p.timerDisplayNotifier.value);
      expect(p.timerDisplayNotifier.value, greaterThan(Duration.zero));
    });

    test('reset() syncs notifier to Duration.zero', () {
      final p = SessionStateProvider()..start(fixture);
      p.reset();
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });

    test('debugSetPhase() syncs notifier to new phase duration', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.setRest);
      // Phase changed → notifier should reflect the new _remaining for setRest.
      expect(p.timerDisplayNotifier.value, p.remaining);
      expect(p.timerDisplayNotifier.value, greaterThan(Duration.zero));
    });

    test('requestManualOvertime() syncs notifier to overtimeElapsed (zero)', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.getReady);
      p.requestManualOvertime();
      // In overtime, the notifier publishes _overtimeElapsed (starts at 0).
      expect(p.phase, TimerPhase.overtime);
      expect(p.timerDisplayNotifier.value, p.overtimeElapsed);
      expect(p.timerDisplayNotifier.value, Duration.zero);
    });

    test('exitOvertime() syncs notifier back to _remaining', () {
      final p = SessionStateProvider()..start(fixture);
      p.debugSetPhase(TimerPhase.getReady);
      p.requestManualOvertime();
      expect(p.phase, TimerPhase.overtime);
      p.exitOvertime();
      // After exitOvertime, phase is back to getReady with fresh 10s.
      expect(p.phase, TimerPhase.getReady);
      expect(p.timerDisplayNotifier.value, p.remaining);
      expect(p.timerDisplayNotifier.value, const Duration(seconds: 10));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: FAIL — `timerDisplayNotifier.value` is still `Duration.zero` (never updated), so all assertions comparing it to `_remaining` or expecting non-zero values fail.

- [ ] **Step 3: Add `_syncTimerDisplay()` calls before every `notifyListeners()` in mutation methods**

Work through the table above. For each method/branch, find the `notifyListeners();` line and insert `_syncTimerDisplay();` immediately above it (same indentation).

Example for `start()` (around line 666):

```dart
    _remaining = _getDurationForPhase(_progress);
    _isPaused = false;
    _startTicker();
    _rescheduleSound();
    _syncTimerDisplay();      // ← NEW
    notifyListeners();
  }
```

Example for `reset()` (around line 793):

```dart
    _remaining = Duration.zero;
    _isPaused = true;
    _syncTimerDisplay();      // ← NEW
    notifyListeners();
  }
```

Example for `exitOvertime()` (around line 1505):

```dart
    _overtimeElapsed = Duration.zero;
    _overtimeWasAutomatic = false;
    _syncTimerDisplay();      // ← NEW
    notifyListeners();
  }
```

Repeat for every entry in the table. **Verify the insertion is immediately above `notifyListeners()`, not earlier in the method** — this guarantees `_progress` is fully updated before `_syncTimerDisplay()` reads `_progress.phase`.

- [ ] **Step 4: Run new tests to verify they pass**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: PASS — all 5 new tests assert the notifier value matches `_remaining` or `_overtimeElapsed` after mutation, and they do.

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `./scripts/run_tests.sh`
Expected: All tests pass. The added `_syncTimerDisplay()` calls are no-ops from the perspective of the existing public API.

- [ ] **Step 6: Manual sanity grep**

Run: `grep -n "notifyListeners();" lib/providers/session_state_provider.dart | wc -l`
Expected: ~28 (matches pre-change count). The number should be unchanged — we added `_syncTimerDisplay()` calls, not new notifications.

Run: `grep -n "_syncTimerDisplay();" lib/providers/session_state_provider.dart | wc -l`
Expected: **15**. Should match the call-site count from the table above (Task 2 wires up all 15 sites; Task 3 will add 2 more in the ticker, bringing the total to 17 after the next task).

- [ ] **Step 7: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_timer_display_notifier_test.dart
git commit -m "wire _syncTimerDisplay() into all mutation methods.

inserts _syncTimerDisplay() immediately before every notifyListeners()
call in methods that mutate _remaining, _overtimeElapsed, or
_progress.phase. no user-visible behavior change yet (ticker still
1Hz, still notifies per-tick) — just keeps timerDisplayNotifier in
sync with the underlying state ahead of the ticker refactor.

covers: start, reset, jumpToWorkout, jumpToExercise (all three
branches: cross-workout-back, normal, cross-workout-forward),
_applyJumpTarget, jumpToSet (both branches), advanceManually,
_enterOvertime, exitOvertime, reconcileAfterBackground (both
notifying branches), debugSetPhase. 15 insertion sites total.

adds 5 tests asserting the notifier tracks state after mutation.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Change ticker to 100ms, move per-tick notify into phase-transition guard, sync notifier each tick

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (`_startTicker` method only)
- Modify: `test/providers/session_state_provider_timer_display_notifier_test.dart` (add ticker behavior tests)

This task is where the actual frequency change lands. After this, the ticker runs at 100ms, `notifyListeners()` fires only on phase transitions, and `timerDisplayNotifier` is updated on every tick.

### The current `_startTicker` body (for reference, lines 878-952)

```dart
  void _startTicker() {
    _ticker?.cancel();
    _lastTickAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_progress.phase == TimerPhase.overtime) {
        final now = DateTime.now();
        _overtimeElapsed += now.difference(_lastTickAt!);
        _lastTickAt = now;
        notifyListeners();
        return;
      }

      final now = DateTime.now();
      final prevProgress = _progress;
      final previousRemaining = _remaining;

      _advanceByElapsed(now.difference(_lastTickAt!));
      _lastTickAt = now;

      final playInApp = _isForegrounded && (...);

      if (playInApp) {
        // ... beep logic (unchanged) ...
      }

      if (!identical(_progress, prevProgress)) {
        _rescheduleSound();
      }
      notifyListeners();
    });
  }
```

### Three precise changes

1. **`Duration(seconds: 1)` → `Duration(milliseconds: 100)`** in the `Timer.periodic` call.
2. **Overtime branch:** replace `notifyListeners();` with `_syncTimerDisplay();` (do NOT call `notifyListeners()` per-tick in overtime either — overtime updates are also high-frequency display-only changes).
3. **Main branch:** remove the final `notifyListeners();` from the bottom of the callback. Move it inside the existing `if (!identical(_progress, prevProgress))` block, right after `_rescheduleSound()`. Add `_syncTimerDisplay();` at the bottom of the main branch (after the phase-transition guard, before the closing brace) so every tick publishes the new display value.

- [ ] **Step 1: Write the failing test**

Append to `test/providers/session_state_provider_timer_display_notifier_test.dart`:

```dart
    test('ticker is 100ms interval', () async {
      // Use a debug entry point if available, or assert indirectly by
      // measuring tick rate. We assert indirectly: after starting a
      // session and waiting ~250ms, the notifier should have been
      // updated multiple times. With a 1s tick interval, only 0-1
      // updates would happen in 250ms.
      final p = SessionStateProvider()..start(fixture);
      // start() puts us in getReady with ~10s remaining; ticker is running.
      var updateCount = 0;
      p.timerDisplayNotifier.addListener(() => updateCount++);
      await Future.delayed(const Duration(milliseconds: 350));
      // At 100ms interval we expect ~3 updates in 350ms. Be generous to
      // accommodate scheduling jitter — assert >= 2.
      expect(updateCount, greaterThanOrEqualTo(2));
      p.pause();
    });

    test('per-tick changes to _remaining do not fire notifyListeners', () async {
      // The whole point of the refactor: ChangeNotifier listeners (i.e.
      // Consumer widgets) should NOT rebuild on every tick — only on
      // phase transitions and user actions. The notifier listener (the
      // timer widget) should rebuild every tick.
      final p = SessionStateProvider()..start(fixture);
      // Consume the start() notification.
      await Future.delayed(const Duration(milliseconds: 50));

      var changeNotifierFires = 0;
      var notifierFires = 0;
      p.addListener(() => changeNotifierFires++);
      p.timerDisplayNotifier.addListener(() => notifierFires++);

      // Wait less than the getReady duration (10s) so no phase transition.
      await Future.delayed(const Duration(milliseconds: 350));

      // ValueNotifier should have fired multiple times (one per tick).
      expect(notifierFires, greaterThanOrEqualTo(2));
      // ChangeNotifier should NOT have fired — no phase transition occurred.
      expect(changeNotifierFires, 0);

      p.pause();
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: FAIL — `'ticker is 100ms interval'` fails because at 1s interval `updateCount` will be 0 or 1. `'per-tick changes...'` fails because the current ticker calls `notifyListeners()` every second so `changeNotifierFires` will be >= 0 if a tick happens, but more importantly the notifier-fires assertion fails because the notifier isn't updated per-tick yet.

- [ ] **Step 3: Modify `_startTicker` in `lib/providers/session_state_provider.dart`**

Locate `_startTicker` (around line 878). Apply the three changes precisely. The new body should look like:

```dart
  void _startTicker() {
    _ticker?.cancel();
    // Stamp the current wall-clock time so the first tick can measure a real
    // elapsed delta.
    _lastTickAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;

      if (_progress.phase == TimerPhase.overtime) {
        final now = DateTime.now();
        _overtimeElapsed += now.difference(_lastTickAt!);
        _lastTickAt = now;
        // High-frequency display update only — do NOT notifyListeners() here.
        // The screen-wide Consumer would otherwise rebuild 10x per second.
        _syncTimerDisplay();
        return;
      }

      final now = DateTime.now();
      // Use actual wall-clock elapsed instead of a fixed 1 s decrement.
      // When the OS suspends the isolate (screen locked), the ticker stops
      // firing but _lastTickAt is preserved. The next tick after the isolate
      // resumes will have a large elapsed value (e.g. 45 s), which
      // _advanceByElapsed handles by fast-forwarding through however many
      // phases elapsed during that gap.
      final prevProgress = _progress;
      final previousRemaining = _remaining;

      _advanceByElapsed(now.difference(_lastTickAt!));
      _lastTickAt = now;

      final playInApp =
          _isForegrounded &&
          (_soundMode == SoundMode.soundsOnly || _soundMode == SoundMode.both);

      if (playInApp) {
        // ... existing beep-firing block (lines ~909-941) UNCHANGED ...
      }

      // Only reschedule (and notify Consumer widgets) when a phase
      // transition occurred. Per-tick display updates flow through the
      // ValueNotifier below, bypassing the screen-wide rebuild.
      if (!identical(_progress, prevProgress)) {
        _rescheduleSound();
        notifyListeners();
      }
      // Always publish the new display value (10 Hz). Only the timer
      // widget's ValueListenableBuilder rebuilds in response.
      _syncTimerDisplay();
    });
  }
```

**Critical:** the beep-firing block (`if (playInApp) { ... countdown / go / stop ... }`) must remain exactly as it is. Do not edit it. Only the three changes listed above (line 883 frequency, overtime branch, end-of-callback). The local variables `prevProgress` and `previousRemaining` must stay — `previousRemaining` is used inside the beep-firing block to detect threshold crossings.

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `./scripts/run_tests.sh test/providers/session_state_provider_timer_display_notifier_test.dart`
Expected: PASS — the 100ms interval test sees multiple notifier updates in 350ms, and the per-tick test confirms `ChangeNotifier` doesn't fire while only `ValueNotifier` does.

- [ ] **Step 5: Run the full test suite**

Run: `./scripts/run_tests.sh`
Expected: All tests pass. If existing tests break, the most likely cause is they implicitly relied on `notifyListeners()` firing per-tick. Check the failure: if a test was reading provider state after a `Future.delayed(...)` and expecting `notifyListeners` to have been called, that's a fragile test that should now poll state directly. Fix by reading the public getter rather than counting listener calls. **Do not undo the refactor to make a test pass.**

- [ ] **Step 6: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_timer_display_notifier_test.dart
git commit -m "move SessionStateProvider ticker to 100ms, isolate per-tick rebuilds.

three precise changes to _startTicker:
1. Timer.periodic interval: 1s -> 100ms.
2. overtime branch: replace notifyListeners() with _syncTimerDisplay()
   so 10Hz overtime updates flow only to the timer widget, not the
   whole screen.
3. main branch: remove per-tick notifyListeners(); move it inside the
   existing phase-transition guard (alongside _rescheduleSound).
   add _syncTimerDisplay() at the end of the callback so every tick
   publishes the new display value.

net effect: Consumer<SessionStateProvider> widgets rebuild only on
phase transitions and user actions (as they always should have). the
new ValueListenableBuilder around the timer Text widget (next task)
rebuilds at 10Hz, isolated from the rest of the tree.

beep-firing logic is unchanged — at 100ms ticks it becomes more
reliable because the early-fire window is hit on the first tick that
crosses the threshold.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Wrap timer `Text` widget in `ValueListenableBuilder`

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart` (lines 379-419 — the `Center > Text` block)

This is the consumer side. The widget needs to read `timerDisplayNotifier` instead of `sessionStateData.remaining` / `sessionStateData.overtimeElapsed` directly. Phase reads (`sessionStateData.phase`, `sessionStateData.isPaused`) stay as direct reads since they don't change per-tick.

Note: this task has no automated test (UI test). Verification is by reading the diff carefully and manual testing on device after Task 5.

- [ ] **Step 1: Read the current code**

Open `lib/presentation/screens/session_flow/session_active_screen.dart`. Locate the `Center` widget at line ~379, which wraps a `Text` widget that displays the timer. The full block is lines 379-419.

- [ ] **Step 2: Replace the `Center > Text` block with a `Center > ValueListenableBuilder > Text` block**

**Before** (lines 379-419):

```dart
                            Center(
                              child: Text(
                                sessionStateData.phase == TimerPhase.overtime
                                    ? formatDuration(
                                      sessionStateData.overtimeElapsed,
                                    )
                                    : formatDuration(
                                      sessionStateData.remaining,
                                    ),
                                style: context.h1.copyWith(
                                  color: () {
                                    if (sessionStateData.isPaused) {
                                      return context.colorScheme.tertiary;
                                    } else if (sessionStateData.phase ==
                                        TimerPhase.getReady) {
                                      return context.colorScheme.secondary;
                                    } else if (sessionStateData.phase ==
                                        TimerPhase.rep) {
                                      return context.colorScheme.onPrimary;
                                    } else if (sessionStateData.phase ==
                                        TimerPhase.overtime) {
                                      return context.colorScheme.secondary;
                                    } else if ((sessionStateData.phase ==
                                                TimerPhase.repRest ||
                                            sessionStateData.phase ==
                                                TimerPhase.setRest ||
                                            sessionStateData.phase ==
                                                TimerPhase.supersetRest ||
                                            sessionStateData.phase ==
                                                TimerPhase.exerciseRest) &&
                                        sessionStateData.remaining <
                                            Duration(seconds: 10)) {
                                      return context.colorScheme.secondary;
                                    } else {
                                      return context.colorScheme.onPrimary;
                                    }
                                  }(),
                                ),
                                textScaler: TextScaler.linear(2.5),
                              ),
                            ),
```

**After:**

```dart
                            Center(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable:
                                    sessionStateData.timerDisplayNotifier,
                                builder: (context, displayValue, _) {
                                  return Text(
                                    formatDuration(displayValue),
                                    style: context.h1.copyWith(
                                      color: () {
                                        if (sessionStateData.isPaused) {
                                          return context.colorScheme.tertiary;
                                        } else if (sessionStateData.phase ==
                                            TimerPhase.getReady) {
                                          return context.colorScheme.secondary;
                                        } else if (sessionStateData.phase ==
                                            TimerPhase.rep) {
                                          return context.colorScheme.onPrimary;
                                        } else if (sessionStateData.phase ==
                                            TimerPhase.overtime) {
                                          return context.colorScheme.secondary;
                                        } else if ((sessionStateData.phase ==
                                                    TimerPhase.repRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.setRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.supersetRest ||
                                                sessionStateData.phase ==
                                                    TimerPhase.exerciseRest) &&
                                            displayValue <
                                                Duration(seconds: 10)) {
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

**Three substantive changes** (verify the diff):

1. **Outer wrapping:** `Text(...)` becomes `ValueListenableBuilder<Duration>(valueListenable: ..., builder: ... return Text(...))`.
2. **Display value source:** the `sessionStateData.phase == TimerPhase.overtime ? overtimeElapsed : remaining` ternary is gone. `formatDuration(displayValue)` reads directly from the builder argument.
3. **Color threshold check:** `sessionStateData.remaining < Duration(seconds: 10)` becomes `displayValue < Duration(seconds: 10)`. Same semantic, but now responsive to per-tick updates.

**No other changes.** Phase reads (`sessionStateData.phase`, `sessionStateData.isPaused`) inside the color callback stay as direct reads from the captured `sessionStateData` closure — they update on phase transitions via the outer `Consumer2`.

- [ ] **Step 3: Run analyzer to catch any typos / import issues**

Run: `flutter analyze lib/presentation/screens/session_flow/session_active_screen.dart`
Expected: No errors. (`ValueListenableBuilder` is part of `package:flutter/widgets.dart` which is transitively imported via `material.dart` already at the top of the file — no import change needed.)

- [ ] **Step 4: Run full test suite**

Run: `./scripts/run_tests.sh`
Expected: All tests pass. No tests directly target this widget, but if any widget tests render the active session screen they need to keep working.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "wrap active session timer text in ValueListenableBuilder.

reads timerDisplayNotifier instead of sessionStateData.remaining /
overtimeElapsed directly. only this widget rebuilds at 10Hz; the
surrounding tree rebuilds only on phase transitions via the existing
Consumer2.

the phase-based overtime vs remaining ternary is gone — the notifier
already publishes whichever value should be shown. the <10s color
check now reads the notifier value so the color transition happens
within ~100ms of crossing the threshold instead of within ~1s.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Add notifier disposal to `SessionStateProvider`

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (add or extend `dispose()` override)

`ValueNotifier` extends `ChangeNotifier`, which leaks listeners if not disposed. Since `SessionStateProvider` is itself a `ChangeNotifier` registered as a `ChangeNotifierProvider` in `main.dart`, its `dispose()` is called when the provider tree tears down. We need to dispose the notifier from there.

- [ ] **Step 1: Check whether `dispose()` is already overridden**

Run: `grep -n "void dispose(" lib/providers/session_state_provider.dart`
Expected output: either a line showing `void dispose() {` (override already exists), OR no match (no override yet).

- [ ] **Step 2: Add or extend the `dispose()` method**

**If `dispose()` does NOT exist:** Add this method at the end of the class (just before the closing `}` of `SessionStateProvider`):

```dart
  @override
  void dispose() {
    _ticker?.cancel();
    timerDisplayNotifier.dispose();
    super.dispose();
  }
```

**If `dispose()` already exists:** Add `timerDisplayNotifier.dispose();` to it, immediately before `super.dispose();`. Keep the existing `_ticker?.cancel()` if present, or add it if not.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/providers/session_state_provider.dart`
Expected: No errors.

- [ ] **Step 4: Run full test suite**

Run: `./scripts/run_tests.sh`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "dispose timerDisplayNotifier in SessionStateProvider.dispose().

prevents listener leaks when the provider tree tears down. also
ensures the ticker is cancelled on disposal.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Manual verification on device

**No file changes.** This task is a checklist for hand-testing on a real device (iPhone or Android), since the optimization's value is most visible at the UI rebuild layer which automated tests don't cover.

- [ ] **Step 1: Build and install the app on a physical device**

Run: `flutter run -d <device-id>` (or use the IDE run button).

- [ ] **Step 2: Verify smooth timer behavior**

Start a session with a `getReady` phase ≥ 5 seconds. Confirm:
- The timer text counts down smoothly (visually identical to before — still whole seconds).
- No visible jank or stutter in the surrounding UI (exercise card, set/rep, bottom bar) during the countdown.
- After the phase transition (getReady → rep), the rest of the UI updates correctly.

- [ ] **Step 3: Verify beep reliability**

Trigger the countdown beep, go beep, and stop beep across multiple phases. Confirm:
- All beeps fire reliably (no sporadic misses, which was the symptom of the bug this work also fixes).
- Countdown beep starts ~3.5s before phase end, ends ~0.5s before go beep, go beep fires ~300ms before rep starts.

- [ ] **Step 4: Verify overtime behavior**

Trigger overtime (long-press the pause button during `setRest` or `getReady`). Confirm:
- The timer text switches to counting up from zero.
- The number ticks up smoothly (whole seconds).
- The surrounding UI stays visually still — no flicker per tick.

Exit overtime (tap the forward-skip button). Confirm:
- The timer switches back to counting down for the new `getReady` phase.
- The screen rebuilds for the phase transition (color of phase text changes, bottom bar updates).

- [ ] **Step 5: Verify pause/resume**

Pause during a phase. Confirm the timer freezes at the current value and color shifts to the paused (tertiary) color. Resume. Confirm the timer continues counting down from the frozen value.

- [ ] **Step 6: Verify background catch-up**

Background the app for 30+ seconds during a phase shorter than 30s. Bring the app back to foreground. Confirm:
- The timer jumps to the correct post-catchup phase/value.
- The screen rebuilds correctly for any phase transitions that happened during the gap.
- No stuck or stale display values.

- [ ] **Step 7: Verify <10s color threshold**

During a rest phase, wait until the timer crosses 10 seconds remaining. Confirm:
- The timer color changes to `secondary` within ~100ms of crossing (much faster than before, which only updated on phase transitions).

- [ ] **Step 8: Mark this task complete**

No commit needed — manual verification only. If any of the above checks fail, file a follow-up and do not consider the feature shipped.

---

## Done criteria

- [ ] All 5 implementation tasks committed.
- [ ] `./scripts/run_tests.sh` is fully green.
- [ ] Manual verification on a physical device completed (all checks in Task 6 pass).
- [ ] No `notifyListeners()` is called per-tick in `_startTicker()` (only on phase transitions).
- [ ] `timerDisplayNotifier.value` always equals the displayable timer value (= `_overtimeElapsed` during overtime, `_remaining` otherwise) immediately after any mutation method or tick.

---

## Out of scope for this plan

- Displaying tenths of seconds in the timer text. The infrastructure now supports it (state ticks at 10Hz, the widget rebuilds at 10Hz). When you want it, edit `formatDuration()` or the `Text(formatDuration(displayValue))` line — no provider changes needed.
- Splitting `SessionStateProvider` into multiple providers. See the spec's "Approaches Considered" for why this was rejected.
- Per-frame animations or smooth ring fills. None exist in the current UI; if added later, they should also use `ValueListenableBuilder` reading the notifier (or a new dedicated notifier for animation progress).
