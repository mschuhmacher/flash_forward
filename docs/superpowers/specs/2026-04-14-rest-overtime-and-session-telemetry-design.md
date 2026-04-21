# Rest Overtime & Session Telemetry — Design

**Date:** 2026-04-14
**Status:** Draft for review
**Related files:**
- `lib/providers/session_state_provider.dart`
- `lib/providers/settings_provider.dart`
- `lib/services/beep_scheduler.dart`
- `lib/services/audio_beep_player.dart`
- `lib/presentation/screens/session_flow/session_active_screen.dart`
- `lib/models/session.dart`, `workout.dart`, `exercise.dart`

---

## Problem

Two interleaved problems:

1. **Unwanted auto-advance during rest.** When the user navigates away from the app (phone locked, app backgrounded) during `setRest` or `exerciseRest`, `reconcileAfterBackground()` fast-forwards the timer through every phase that elapsed. A user who glances at their phone 90 seconds after a set can return to find they've "missed" the next set — the app thinks they're already mid-rep of the following set. The user wants the app to *hold* at the rest phase and let it overtime (count up past zero) until they come back.

2. **No way to voluntarily extend a rest.** Even with the screen on, a user may decide mid-rest that they need more time — a longer break between sets, an unexpected interruption. Today the only tool is `pause`, which freezes time but gives no visual indication of how much overtime has accumulated.

Additionally, the feature creates an opportunity to address a separate long-standing gap: **no session-level timing telemetry**. The app tracks progress but doesn't record how long a logged session actually took, how much of it was active work versus rest, or how much time was "overtime." The instrumentation required for overtime tracking is the same instrumentation required for a full session-time breakdown, so we design both together.

## Goals

- Users can configure the app (via settings drawer) to automatically hold `setRest` and `exerciseRest` phases in an "overtime" state when the app is backgrounded, instead of auto-advancing.
- Users can manually trigger overtime at any point during `setRest`, `exerciseRest`, or `getReady` by long-pressing the pause button.
- Overtime is visually distinct: the timer counts up from zero (or from the overtime entry point) in `colorScheme.secondary`, and the pause button transforms into a forward-skip button in the same color.
- Exiting overtime always transitions to a fresh 10-second `getReady` phase — no exceptions, no remaining-time carry-over.
- Every logged session records a structured event log (SetEvents + RestEvents) that supports "total session time" and "time breakdown by phase" views.
- Session-level rollups are pre-computed at save time so the UI never has to aggregate raw events to show a summary.

## Non-goals

- Per-rep timing analytics (reps completed yes, individual rep durations no).
- Historical overtime analytics across sessions (one session at a time for v1).
- Configurable overtime exit duration — always 10s `getReady`.
- Overtime during `rep` or `repRest` phases — not supported.
- Automatic backfill of event logs for sessions logged before this feature ships.
- Cross-device sync of the "background overtime" setting (local `SharedPreferences` only).

---

## Architecture

### New `TimerPhase.overtime`

Extend the existing `TimerPhase` enum:

```dart
enum TimerPhase {
  rep,
  repRest,
  setRest,
  exerciseRest,
  overtime,          // NEW
  workoutComplete,
  paused,
  getReady,
}
```

`overtime` behaves differently from every other phase:
- It has no fixed duration. `_getDurationForPhase()` returns `Duration.zero` for it, but the ticker does not treat zero as "advance" — instead, the ticker accumulates elapsed time *upward* into a new field.
- `_calculateNextState()` returns `null` for `overtime` (never auto-advances).
- `_advanceByElapsed()` has an early branch: if `phase == overtime`, skip the subtract-and-transition logic entirely and just increment an overtime counter.

### New provider field: `_overtimeElapsed`

```dart
Duration _overtimeElapsed = Duration.zero;
```

- Reset to `Duration.zero` every time `overtime` is entered.
- Incremented by the ticker on each tick while in `overtime`.
- Read by the UI to display the count-up value.
- Included in the finalized RestEvent for overtime when the phase exits.

The existing `_remaining` field is set to `Duration.zero` on overtime entry and left alone. The UI's display branch keys off `phase == overtime` to render `_overtimeElapsed` instead of `_remaining`.

### Entry into overtime

Three entry points, all routing through a single private method:

```dart
void _enterOvertime(TimerPhase sourcePhase) {
  _overtimeElapsed = Duration.zero;
  _rememberCurrentPhaseForPausing = TimerPhase.overtime; // so pause→resume returns here
  _progress = _progress.copyWith(phase: TimerPhase.overtime);
  _remaining = Duration.zero;
  _closeOpenRestEvent(); // finalize the event for sourcePhase if one was open
  _openRestEvent(RestKind.overtime);
  _rescheduleSound(); // becomes a no-op: overtime schedules nothing
  notifyListeners();
}
```

**Entry point 1 — Manual long-press.** A new public method on the provider:

```dart
bool requestManualOvertime() {
  final p = _progress.phase;
  if (p != TimerPhase.setRest &&
      p != TimerPhase.exerciseRest &&
      p != TimerPhase.getReady) {
    return false;
  }
  _enterOvertime(p);
  return true;
}
```

Returns `false` if called from a disallowed phase (`rep`, `repRest`, `paused`, `workoutComplete`, already-`overtime`). The UI uses the return value to decide whether to animate the button color change.

**Entry point 2 — Backgrounded rest expiry (settings-driven).** When the user has `restOvertimeOnBackground == true` in settings and the app is backgrounded during `setRest` or `exerciseRest`, `reconcileAfterBackground()` detects on foreground return that the rest phase's expiry time passed during the gap. Instead of calling `_advanceByElapsed(fullGap)`, it:

1. Computes `elapsedToPhaseEnd = _remaining` (time from last tick to phase end).
2. Calls `_advanceByElapsed(elapsedToPhaseEnd)` — this brings `_remaining` to zero *at* the rest phase boundary, but does not transition because of a new guard (see below).
3. Computes `overshoot = fullGap - elapsedToPhaseEnd` and transitions into `overtime` with `_overtimeElapsed = overshoot`.
4. Finalizes the rest event for the expired phase (with `actualDuration == plannedDuration`, no overtime yet), and opens a fresh `overtime` RestEvent whose `startAt` is `phaseEndTime`.

The guard: `_advanceByElapsed` checks, when `_remaining` would cross zero during a rest-overtime-eligible phase in settings-mode, whether the setting is enabled. If so, it stops at zero instead of calling `_calculateNextState()`, and signals the reconcile path to enter overtime.

**Entry point 3 — Live ticker expiry of an "armed" rest.** This is the foreground-equivalent of entry point 2: the user is watching the screen, the setting is on, the rest timer naturally hits zero. The ticker's expiry check sees the setting is on and the current phase is `setRest`/`exerciseRest`, and calls `_enterOvertime()` instead of advancing.

An alternative (simpler) design: **the background setting *only* affects `reconcileAfterBackground`.** When the app is foregrounded and the rest expires, it auto-advances as it does today regardless of the setting. The setting is *specifically* about protecting against background auto-advance. This matches the stated user intent ("when they're away") and keeps the ticker path unchanged.

**Decision: go with the simpler design.** The setting only affects the background-return path. In foreground, if the user wants overtime, they use the manual long-press. This keeps two entry points (long-press + background-return) and leaves the ticker's expiry logic alone.

### Exit from overtime

Single exit path:

```dart
void exitOvertime() {
  if (_progress.phase != TimerPhase.overtime) return;
  _closeOpenRestEvent(); // finalize the overtime RestEvent
  _progress = _progress.copyWith(phase: TimerPhase.getReady);
  _remaining = const Duration(seconds: 10);
  _openRestEvent(RestKind.getReady);
  _startTicker(); // ensures _lastTickAt is fresh
  _rescheduleSound();
  notifyListeners();
}
```

Called by:
- **The transformed pause button** when tapped while in `overtime`.
- **`reconcileAfterBackground()`** automatically on foreground return, *if* the overtime was triggered by background (not by manual long-press while foregrounded). See "Auto-exit on foreground" below.

### Auto-exit on foreground return

A subtle distinction: if the user *manually* long-presses into overtime while actively watching the screen, bringing the app to the foreground (trivially — it was already foregrounded) should NOT auto-exit. If the user *implicitly* entered overtime because the app backgrounded during a rest phase, foregrounding SHOULD auto-exit.

To distinguish, add a flag:

```dart
bool _overtimeWasAutomatic = false;
```

Set to `true` in entry point 2, `false` in entry point 1. Checked in `reconcileAfterBackground()`:

```dart
void reconcileAfterBackground() {
  if (_isPaused || _activeSession == null || _lastTickAt == null) return;
  final now = DateTime.now();
  _advanceByElapsed(now.difference(_lastTickAt!));
  _lastTickAt = now;

  // Auto-exit overtime only if it was triggered automatically.
  if (_progress.phase == TimerPhase.overtime && _overtimeWasAutomatic) {
    exitOvertime();
  }

  _rescheduleSound();
  notifyListeners();
}
```

This lets the user deliberately manual-overtime, put the phone down, walk away, come back, and *still* be in overtime when they pick it up — because they chose that mode. Only the settings-driven auto-overtime auto-exits.

### State machine diagram (changes highlighted)

```
getReady ──► rep ──► repRest ──► rep ... ──► setRest ──► rep (next set)
                                                │
                                                ├──► overtime (new)  [manual or auto]
                                                │       │
                                                │       ▼
                                                └──► getReady (fresh 10s)

exerciseRest ──► rep (or getReady if new workout)
      │
      ├──► overtime (new)  [manual or auto]
      │       │
      │       ▼
      └──► getReady (fresh 10s)

getReady ──► overtime (new)  [manual only]
                │
                ▼
             getReady (fresh 10s)  ← restarts the 10s
```

---

## Settings integration

Extend `SettingsProvider`:

```dart
class SettingsProvider extends ChangeNotifier {
  static const _keyRestOvertimeOnBackground = 'pref_rest_overtime_on_background';
  bool _restOvertimeOnBackground = false; // default off

  bool get restOvertimeOnBackground => _restOvertimeOnBackground;

  Future<void> setRestOvertimeOnBackground(bool value) async {
    _restOvertimeOnBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRestOvertimeOnBackground, value);
  }
}
```

Default `false` — opt-in feature. Users must discover and enable it in the settings drawer.

The `SessionStateProvider` reads this value via the setter pattern already used for `setSoundMode`:

```dart
void setRestOvertimeOnBackground(bool value) {
  _restOvertimeOnBackground = value;
}
```

Called from the same root-screen wiring that already syncs `SoundMode` to the session provider.

### Settings drawer UI

Add a new `SwitchListTile` to the settings drawer beneath the sound-mode section:

```
┌──────────────────────────────────────────┐
│  Extend rest when backgrounded           │
│  Keep rest periods running when you      │
│  leave the app.                    [off] │
└──────────────────────────────────────────┘
```

Plain SwitchListTile, no info button. The label and subtitle explain the behavior.

---

## Beep scheduling integration

The current `_rescheduleSound()` already only schedules notifications when backgrounded. The changes needed:

### `_calculateFutureBeeps()` simulation truncation

Add a phase check in the simulation loop: if the simulated next phase is `overtime`, OR if the current simulated phase is `setRest`/`exerciseRest` AND the setting is on AND the simulation would transition past it, stop adding beeps beyond the current phase.

Concretely: at the end of the loop body, after computing `next`, check whether the transition we're about to simulate is a "setRest/exerciseRest → something else" edge that would be blocked by overtime-on-background. If so, break.

```dart
final next = _calculateNextState(simProgress);
if (next == null) break;

// If the user has rest-overtime-on-background enabled, notifications
// past an expiring rest phase will never fire — the real state machine
// will hold at overtime. Truncate the simulation.
if (_restOvertimeOnBackground &&
    (simProgress.phase == TimerPhase.setRest ||
     simProgress.phase == TimerPhase.exerciseRest)) {
  break;
}

// Manual rep phase: duration unknown (existing logic)
// ...
```

This means a user with overtime-on-background enabled gets notifications up to and including the "rest is over" beep at the end of their first rest phase, then nothing. When they foreground the app, normal beep scheduling resumes for the next segment.

### In-app audio during overtime

The ticker's in-app audio logic (countdown/go/stop) fires on phase transitions. Since overtime is never entered via a natural ticker decrement (only via `_enterOvertime()` or `reconcileAfterBackground`), and `overtime` itself produces no phase transitions, the existing audio code naturally goes silent while in overtime. No change needed.

One edge: when entering overtime from the reconcile path, we should NOT fire a stop/go beep for the implied `setRest → overtime` transition. The reconcile path already suppresses this because it doesn't call the ticker's audio branch.

When *exiting* overtime into `getReady`, the existing ticker logic will naturally fire the countdown beep at T-3s of the fresh 10s getReady. No change needed.

---

## UI changes

### Timer display

In `session_active_screen.dart`, the timer text widget (lines 301–333) currently selects color based on phase. Add an `overtime` branch:

```dart
Color timerColor;
Duration displayValue;
switch (phase) {
  case TimerPhase.overtime:
    timerColor = colorScheme.secondary;
    displayValue = sessionState.overtimeElapsed;
    break;
  case TimerPhase.paused:
    timerColor = colorScheme.tertiary;
    displayValue = sessionState.remaining;
    break;
  // ... existing cases
}
```

Add a `get overtimeElapsed` getter to `SessionStateProvider`.

The phase label above the timer (line 292) adds a new case:
```dart
TimerPhase.overtime => 'overtime',
```

Styled in `colorScheme.secondary` to match.

### Pause button transform

The pause/resume button (lines 341–357) becomes a small state machine:

| Phase | Icon | Color | On tap | On long-press |
|---|---|---|---|---|
| `rep`, `repRest` | pause | normal | `pause()` | (nothing) |
| `setRest`, `exerciseRest`, `getReady` | pause | normal | `pause()` | `requestManualOvertime()` → icon/color flip |
| `paused` | play_arrow | normal | `resume()` | (nothing) |
| `overtime` | skip_next | `secondary` | `exitOvertime()` | (nothing) |

Long-press detection uses `GestureDetector.onLongPress`. The color change must fire immediately on long-press detection (not after overtime entry completes) — since `requestManualOvertime()` updates state synchronously and calls `notifyListeners()`, a `Consumer<SessionStateProvider>` around the button already gets the repaint in one frame. Good enough.

### Long-press affordance

No visual affordance (no tooltip, no hint text). The feature is discovered through documentation or the settings-drawer copy. Adding a "long-press for overtime" hint would clutter the screen for the common case.

---

## Event log model

### Models

Add three new model files:

**`lib/models/set_event.dart`:**
```dart
class SetEvent {
  final int workoutIndex;
  final int exerciseIndex;
  final int setIndex;                 // 1-based
  final DateTime startAt;
  final DateTime endAt;
  final Duration activeTime;          // sum of real rep wall-clock (paused excluded)
  final Duration interRepRestTime;    // sum of real repRest wall-clock (paused excluded)
  final int repsCompleted;
  // endAt - startAt = activeTime + interRepRestTime + pausedTimeInThisSet
  // pausedTimeInThisSet is derivable by intersecting `paused` RestEvents with [startAt, endAt]
}
```

**`lib/models/rest_event.dart`:**
```dart
enum RestKind { getReady, setRest, exerciseRest, overtime, paused }

class RestEvent {
  final RestKind kind;
  final int workoutIndex;
  final int exerciseIndex;
  final int? setIndex;                 // null for exerciseRest and top-level getReady
  final DateTime startAt;
  final DateTime endAt;
  final Duration plannedDuration;      // zero for overtime and paused
  final Duration actualDuration;       // == endAt - startAt (split-on-pause invariant)
  final Duration overtimeDuration;      // > 0 only for RestKind.overtime
}
```

**`lib/models/session_summary.dart`:**
```dart
class SessionSummary {
  final Duration totalTime;           // endAt of last event - startAt of first event
  final Duration activeTime;          // sum over SetEvents
  final Duration interRepRestTime;    // sum over SetEvents
  final Duration setRestTime;         // sum over RestEvents where kind == setRest
  final Duration exerciseRestTime;    // sum over RestEvents where kind == exerciseRest
  final Duration getReadyTime;        // sum over RestEvents where kind == getReady
  final Duration overtime;             // sum over RestEvents where kind == overtime
  final Duration pausedTime;          // sum over RestEvents where kind == paused
}
```

### Session model extensions

Extend `Session` with three new fields (all nullable for backward compatibility with existing logged sessions):

```dart
class Session {
  // ... existing fields
  final List<SetEvent>? setEvents;
  final List<RestEvent>? restEvents;
  final SessionSummary? summary;
}
```

`copyWith()`, `deepCopy()`, `toJson()` and `fromJson()` extended accordingly. The three new model classes (`SetEvent`, `RestEvent`, `SessionSummary`) need their own `toJson`/`fromJson` implementations following the hand-written pattern already used by `Session`/`Workout`/`Exercise`. Supabase schema needs a migration adding JSONB columns for the two event lists and the summary on the `sessions` table.

### Accumulation rules (provider-side)

The `SessionStateProvider` gains internal in-progress event state:

```dart
// Event log accumulators
final List<SetEvent> _setEvents = [];
final List<RestEvent> _restEvents = [];

// In-progress set accumulator (one at a time)
SetEvent? _openSetEventDraft;        // holds startAt, workoutIndex, etc.
Duration _currentSetActiveAccum = Duration.zero;
Duration _currentSetRepRestAccum = Duration.zero;

// In-progress rest event (one at a time)
RestEvent? _openRestEventDraft;
DateTime? _currentPhaseEnteredAt;    // wall-clock start of current phase
```

### Transition handlers

Every phase transition must route through two bookkeeping functions. Add them as private methods:

```dart
void _closeOpenRestEvent() {
  if (_openRestEventDraft == null) return;
  final now = DateTime.now();
  final draft = _openRestEventDraft!;
  _restEvents.add(RestEvent(
    kind: draft.kind,
    workoutIndex: draft.workoutIndex,
    exerciseIndex: draft.exerciseIndex,
    setIndex: draft.setIndex,
    startAt: draft.startAt,
    endAt: now,
    plannedDuration: draft.plannedDuration,
    actualDuration: now.difference(draft.startAt),
    overtimeDuration: draft.kind == RestKind.overtime
        ? now.difference(draft.startAt)
        : Duration.zero,
  ));
  _openRestEventDraft = null;
}

void _openRestEvent(RestKind kind) {
  final now = DateTime.now();
  final planned = kind == RestKind.overtime || kind == RestKind.paused
      ? Duration.zero
      : _getDurationForPhase(_progress);
  _openRestEventDraft = RestEvent(
    kind: kind,
    workoutIndex: _progress.workoutIndex,
    exerciseIndex: _progress.exerciseIndex,
    setIndex: _includesSetIndex(kind) ? _progress.currentSet : null,
    startAt: now,
    endAt: now, // placeholder; overwritten at close
    plannedDuration: planned,
    actualDuration: Duration.zero,
    overtimeDuration: Duration.zero,
  );
}

void _openSetEvent() {
  _openSetEventDraft = SetEventDraft(
    workoutIndex: _progress.workoutIndex,
    exerciseIndex: _progress.exerciseIndex,
    setIndex: _progress.currentSet,
    startAt: DateTime.now(),
  );
  _currentSetActiveAccum = Duration.zero;
  _currentSetRepRestAccum = Duration.zero;
}

void _closeOpenSetEvent() {
  if (_openSetEventDraft == null) return;
  final draft = _openSetEventDraft!;
  _setEvents.add(SetEvent(
    workoutIndex: draft.workoutIndex,
    exerciseIndex: draft.exerciseIndex,
    setIndex: draft.setIndex,
    startAt: draft.startAt,
    endAt: DateTime.now(),
    activeTime: _currentSetActiveAccum,
    interRepRestTime: _currentSetRepRestAccum,
    repsCompleted: _progress.currentRep,
  ));
  _openSetEventDraft = null;
  _currentSetActiveAccum = Duration.zero;
  _currentSetRepRestAccum = Duration.zero;
}
```

### When accumulators are updated

The SetEvent accumulators need slice-by-slice updates. Two approaches:

1. **Per-tick increment.** The ticker adds the elapsed wall-clock of each tick to the accumulator corresponding to the current phase. Simple but coarse-grained.
2. **Per-transition slice.** At every phase transition (or pause/resume), compute `now - _currentPhaseEnteredAt` and add it to the accumulator for the just-exited phase, then set `_currentPhaseEnteredAt = now`.

**Decision: per-transition slice.** It's more precise (handles large reconcile gaps correctly), and it's cheaper (no per-tick bookkeeping). The transition points are already the right hooks.

Integration: `_advanceByElapsed()`'s phase-transition loop (currently just sets `_progress = next`) gains a call:

```dart
while (_remaining <= Duration.zero) {
  // ... existing manual-exercise guard
  final next = _calculateNextState(_progress);
  if (next == null) {
    _onPhaseExit(_progress.phase);
    _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
    _closeOpenSetEvent();
    _closeOpenRestEvent();
    _remaining = Duration.zero;
    return;
  }
  _onPhaseExit(_progress.phase);
  _onPhaseEnter(next.phase, next);
  _remaining = _getDurationForPhase(next) + _remaining;
  _progress = next;
}
```

Where `_onPhaseExit` and `_onPhaseEnter` are the bookkeeping dispatchers that update accumulators and open/close draft events per the rules above.

### Pause/resume

Pause transitions:

```dart
void pause() {
  if (_isPaused) return;
  _isPaused = true;
  _lastTickAt = null;
  _rememberCurrentPhaseForPausing = _progress.phase;

  // Event log: close any open rest event (split-on-pause rule).
  // Flush any partial slice on the in-progress set's accumulators.
  _flushCurrentPhaseSliceIntoAccumulators();
  _closeOpenRestEvent();

  _progress = _progress.copyWith(phase: TimerPhase.paused);
  _openRestEvent(RestKind.paused);
  _rescheduleSound();
  notifyListeners();
}

void resume() {
  if (!_isPaused) return;
  _isPaused = false;

  _closeOpenRestEvent(); // close the paused event
  _progress = _progress.copyWith(phase: _rememberCurrentPhaseForPausing);

  // If resuming into a rest phase, open a NEW rest event of the same kind
  // (split-on-pause). If resuming into rep/repRest, open no rest event but
  // mark the current phase enter time so the set accumulators can slice from now.
  if (_isRestPhase(_progress.phase)) {
    _openRestEvent(_kindForPhase(_progress.phase));
  }
  _currentPhaseEnteredAt = DateTime.now();

  _startTicker();
  _rescheduleSound();
  notifyListeners();
}
```

`_flushCurrentPhaseSliceIntoAccumulators()` handles the case where the set was open and the pause happened mid-rep or mid-repRest: add the slice from `_currentPhaseEnteredAt` to `now` to the correct accumulator, so the partial rep time is not lost.

### Set boundaries

`_openSetEvent()` is called when the provider first enters `TimerPhase.rep` for a given set (detected by transition `getReady→rep`, `setRest→rep`, `exerciseRest→rep`, or `repRest→rep` where `currentRep == 1`).

`_closeOpenSetEvent()` is called when leaving the last rep of a set (transition `rep→setRest` or `rep→exerciseRest`).

For manual exercises: `_openSetEvent()` on `getReady→rep` or `setRest→rep`, `_closeOpenSetEvent()` on `advanceManually()`.

### Jumps

`jumpToSet`, `jumpToExercise`, `jumpToWorkout` discard any open set/rest event drafts without writing them (jumps are exploratory/navigational, not training records). A new helper `_discardOpenDrafts()` handles this.

---

## Session finalization

When the session is logged (via whatever "save session" call exists — needs verification in implementation), the provider computes the summary:

```dart
SessionSummary _computeSummary() {
  // Close any lingering drafts first
  _closeOpenSetEvent();
  _closeOpenRestEvent();

  Duration sum(Iterable<Duration> ds) =>
      ds.fold(Duration.zero, (a, b) => a + b);

  return SessionSummary(
    totalTime: _setEvents.isEmpty
        ? Duration.zero
        : _setEvents.last.endAt.difference(_setEvents.first.startAt),
    activeTime: sum(_setEvents.map((e) => e.activeTime)),
    interRepRestTime: sum(_setEvents.map((e) => e.interRepRestTime)),
    setRestTime: sum(_restEvents.where((e) => e.kind == RestKind.setRest).map((e) => e.actualDuration)),
    exerciseRestTime: sum(_restEvents.where((e) => e.kind == RestKind.exerciseRest).map((e) => e.actualDuration)),
    getReadyTime: sum(_restEvents.where((e) => e.kind == RestKind.getReady).map((e) => e.actualDuration)),
    overtime: sum(_restEvents.where((e) => e.kind == RestKind.overtime).map((e) => e.overtimeDuration)),
    pausedTime: sum(_restEvents.where((e) => e.kind == RestKind.paused).map((e) => e.actualDuration)),
  );
}
```

The summary, full event lists, and session tree are written together. Future UI reads the summary for dashboards and the raw events for drill-downs.

---

## Edge cases

### Overtime during `getReady`

Allowed (long-press only). Exit transitions back to `getReady` with a fresh 10s — effectively a "restart the countdown" with a recorded overtime interval in between. Event-wise: the original `getReady` event closes, an `overtime` event runs for the duration the user was in overtime, a new `getReady` event opens.

### Long-press while already in overtime

`requestManualOvertime()` returns false (overtime is not a valid source phase). The button's onLongPress does nothing. Tap still exits overtime.

### Background entry during overtime (manual)

User manually entered overtime, then put the phone down. Reconcile sees `phase == overtime` and `_overtimeWasAutomatic == false`, increments `_overtimeElapsed` by the gap, does NOT auto-exit. User returns, taps skip button, exits into getReady.

### Background entry during overtime (auto)

User's rest naturally overran due to the setting. Phone backgrounded throughout. On foreground return, reconcile increments `_overtimeElapsed` by the gap, then auto-exits into getReady because `_overtimeWasAutomatic == true`.

### Manual overtime on the very last phase of the session

User long-presses during the final `exerciseRest` of the session. Enter overtime normally. On exit, `getReady` would be the "next rep" of a non-existent next exercise. Guard: in `exitOvertime()`, check whether `_calculateNextState(overtime-source-phase)` is `null` (session would have ended). If so, transition directly to `workoutComplete` instead of `getReady`.

### Pause inside overtime

Not reachable. In manual overtime the pause button has become the forward-skip exit button, so there is no pause gesture available. In auto-overtime triggered by backgrounding, the foreground return immediately transitions to `getReady`, so the user never has an opportunity to interact with overtime at all. Pause-during-overtime therefore does not need to be handled.

### Reset during overtime

`reset()` discards drafts and clears state as before. No special handling — the draft events are not persisted, so the partial data is lost by design (reset means "throw everything away").

### Jump during overtime

Disallow. While `phase == overtime`, all jump/navigation icons in the bottom bar (previous/next exercise, set +/-) are both disabled *and visually greyed out* — a clear signal that the session is held until the user exits overtime deliberately. Re-enabling on overtime exit happens automatically via the `Consumer<SessionStateProvider>` repaint when `phase` changes to `getReady`.

---

## Testing strategy

### Unit tests (provider)

New test file `test/providers/session_state_provider_overtime_test.dart`:

- `requestManualOvertime` succeeds from setRest / exerciseRest / getReady
- `requestManualOvertime` fails from rep / repRest / paused / workoutComplete / overtime
- `exitOvertime` transitions to fresh 10s getReady from all three valid entry sources
- `_overtimeElapsed` increments correctly under ticker advancement
- Auto-overtime on background (setting on): reconcile sees expired setRest, enters overtime with correct `_overtimeElapsed`, auto-exits on subsequent foreground return
- Manual overtime on background: entered manually, backgrounded, foregrounded — stays in overtime
- Exit on last phase of session → workoutComplete, not getReady
- Pause-inside-overtime split semantics (event count = 3: overtime, paused, overtime)
- Jumps are no-ops while in overtime

New test file `test/providers/session_state_provider_event_log_test.dart`:

- A full 3-set timedReps exercise produces 3 SetEvents and 2 setRest RestEvents + 1 exerciseRest + 1 initial getReady
- Pause mid-rep: SetEvent `activeTime` accounts for partial rep; `paused` RestEvent captures the pause interval
- Pause mid-setRest: splits into two setRest RestEvents + one paused RestEvent
- SessionSummary computation matches hand-calculated values for a known fixture session
- Event timestamps are monotonic within each list
- Jump discards in-progress drafts (no stray SetEvent in output)

### Widget tests

- Pause button renders as forward-skip icon with secondary color during overtime
- Long-press from rep phase does nothing
- Long-press from setRest enters overtime; icon and color update within one frame
- Timer displays count-up value in secondary color during overtime
- Settings drawer toggle persists to SharedPreferences

### Integration / manual tests

- Real-device background/foreground scenarios (auto-overtime on/off)
- Sound mode interaction: notifications during auto-overtime truncate correctly
- Hive round-trip: save a session with events, reload, verify summary matches

---

## Migration and rollout

- **Model compatibility:** add the three fields as nullable. `Session.fromJson` tolerates missing keys (existing stored sessions have `setEvents == null`, `restEvents == null`, `summary == null`). UI that consumes them falls back to "no telemetry available" when null.
- **Supabase schema:** add `set_events`, `rest_events`, `summary` JSONB columns to the `sessions` table via a migration. Existing rows load as null — no backfill needed, and existing sessions won't have events anyway.
- **No local database:** the project persists sessions as JSON via `session_logger.dart` → Supabase. There is no Hive or SQLite layer to migrate.
- **Default settings:** `restOvertimeOnBackground` defaults to `false`. Users opt in via the settings drawer.
- **No flag gating:** the overtime feature ships on for all users; only the background-auto-overtime behavior is opt-in.

---

## Open questions

1. **Session save hook location.** Confirmed that `session_logger.dart` and `session_log_provider.dart` exist, but the exact handler that transitions to `workoutComplete` and triggers persistence needs verification during implementation — that's where `_computeSummary()` must be called and the event lists attached to the `Session` before saving.
2. **Supabase migration tooling.** Confirm how existing Supabase migrations are authored in this project (SQL files? dashboard?) and add the JSONB column migration through the same path.
3. **Settings drawer location.** Locate the settings drawer widget file and add the new `SwitchListTile` next to the existing sound-mode toggle.
