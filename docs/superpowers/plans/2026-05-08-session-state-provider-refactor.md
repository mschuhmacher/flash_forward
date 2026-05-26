# SessionStateProvider Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Reassessed 2026-05-19.** Original plan was written 2026-05-08 against `session_state_provider.dart` at 1,212 LOC. Since then the supersets feature shipped completely (commits `ab0ba3f`, `2a22794`, `f4703cb`, `2ec02c3`, `f673b6d`, `035db60`, `8683dcb`, `9eb3c63`, `48a0cb8`, `afc253b`, `ce4e3f9`), plus the `nextStop`/`previousStop`/`jumpToNext`/`jumpToPrevious` navigation API was added for the bottom bar. Provider is now 1,627 LOC. **All literal line-number citations have been removed**; use the method name as the anchor. **The scope of `SessionStateMachine` has grown** to absorb the new pure/near-pure helpers (next-stop calculation, rest-type matching, post-set rest entry) — without this growth, ~200 LOC of pure code stays orphaned on the provider.

**Goal:** Trim [lib/providers/session_state_provider.dart](../../../lib/providers/session_state_provider.dart) (1,627 LOC) by extracting three plain helper classes — `SessionStateMachine`, `SessionTelemetryRecorder`, `SoundDispatcher` — without splitting the provider into multiple `ChangeNotifier`s. The provider remains the single owner of in-memory session state; the helpers are stateless or own only their own scoped state. Functionality must be preserved bit-for-bit; the existing test suite (`session_state_provider_event_log_test.dart`, `session_state_provider_finalize_test.dart`, `session_state_provider_overtime_test.dart`, `session_state_provider_superset_test.dart`) is the safety net.

**Architecture:** The timer engine, telemetry recording, and sound dispatch are tightly coupled around one in-memory state machine — so splitting them across multiple `ChangeNotifier`s would force coordination on every phase transition (the exact complexity we're trying to avoid). Instead, extract **plain helper classes** that the single `SessionStateProvider` composes:

- `SessionStateMachine` — pure functions over `(SessionProgress, Session)`. Owns `calculateNextState`, `enterExerciseRest`, `enterPostSetRest`, `calculateNextStop`, `calculatePreviousStop`, `firstStopAtOrAfter`, `lastStopBefore`, `isOvertimeEligible`, `isRestPhase`, `getDurationForPhase`, `matchRestTypeToTimerPhase`. No state, no notifications.
- `SessionTelemetryRecorder` — owns `_setEvents`, `_restEvents`, the two draft types, set-level accumulators, `computeSummary`. The provider calls it from `_onPhaseTransition`. State, but scoped to one session run.
- `SoundDispatcher` — owns `_rescheduleSound`, `_calculateFutureBeeps`, `_addBeepsForPhase`, the in-app beep choices. Provider hands it the phase change + foreground state; it routes to `BeepScheduler` or `AudioBeepPlayer`.

After extraction, `SessionStateProvider` shrinks to ~500 LOC: holds `_progress`, `_remaining`, `_activeSession`, the ticker, the public `start/pause/resume/jumpTo*/jumpToNext/jumpToPrevious/updateActiveExercise/updateActiveSupersetSets` API, and `_onPhaseTransition` orchestration that calls the three helpers.

**Tech Stack:** Flutter, Provider (ChangeNotifier), Dart, `flutter_test`. No new external dependencies.

---

## Pre-execution check

Before starting this plan:

1. **Superset has shipped.** Confirmed by reassessment on 2026-05-19. The provider includes `TimerPhase.supersetRest`, `setsForExerciseInWorkout`, `updateActiveSupersetSets`, the `_enterPostSetRest` branch (between-rounds rest uses `supersetSetRest`), and the `session_state_provider_superset_test.dart` suite. This plan is built against that shape.
2. **Plan A may have shipped or not.** This plan is independent of Plan A (PresetProvider refactor). They can be executed in either order. Recommended order is **Plan A first** because Plan A's scope is more stable; Plan B was more thoroughly reshaped by the superset feature.

---

## File Map

| Action | File |
|--------|------|
| Create | `lib/providers/session/session_state_machine.dart` |
| Create | `lib/providers/session/session_telemetry_recorder.dart` |
| Create | `lib/providers/session/sound_dispatcher.dart` |
| Modify | `lib/providers/session_state_provider.dart` |
| Create | `test/providers/session/session_state_machine_test.dart` |
| Create | `test/providers/session/session_telemetry_recorder_test.dart` |
| Create | `test/providers/session/sound_dispatcher_test.dart` |
| (no change) | `test/providers/session_state_provider_event_log_test.dart` |
| (no change) | `test/providers/session_state_provider_finalize_test.dart` |
| (no change) | `test/providers/session_state_provider_overtime_test.dart` |
| (no change) | `test/providers/session_state_provider_superset_test.dart` |

The 4 existing `session_state_provider_*_test.dart` files exercise the provider's public API. They must not change semantics (one minor edit may be needed if helper extraction introduces a constructor parameter for dependency injection — see Task 1 Step 5). The new test files cover the helpers in isolation.

A new subdirectory `lib/providers/session/` is introduced for helper organisation. The provider file itself stays at the top of `lib/providers/`.

---

## Locked design decisions

These have been agreed and must not be revisited mid-execution.

1. **Helpers are plain classes, not `ChangeNotifier`s.** The provider remains the single notifier. Extracting helpers as notifiers would force cross-listener coordination on every phase transition.

2. **`SessionStateMachine` is fully pure.** It takes `(SessionProgress, Session)` (or just a `TimerPhase`) and returns `SessionProgress?`, `Duration`, `bool`, or `RestType` — no side effects, no member fields beyond static configuration. This makes it trivially unit-testable.

3. **`SessionStateMachine` absorbs the new nav helpers too.** As of 2026-05-19 the provider gained `_calculateNextStop`, `_calculatePreviousStop`, `_firstStopAtOrAfter`, `_lastStopBefore`, and `_enterPostSetRest` (the superset between-rounds branch). These are pure functions over `(SessionProgress, Session)` and belong in the helper. The provider keeps the public `nextStop`/`previousStop`/`jumpToNext`/`jumpToPrevious` API but their bodies become thin wrappers around the helper.

4. **`SessionTelemetryRecorder` is stateful but scoped.** It owns the event list and accumulators that today live on the provider. The provider keeps a single instance, replaced/cleared on `start()` and `reset()`. Its public surface mirrors what the provider's `_onPhaseTransition` already does: `openSet`, `closeSet`, `openRest`, `closeRest`, `discardDrafts`, `summary`.

5. **`SoundDispatcher` owns timing-of-beep logic, not audio resources.** It still receives `BeepScheduler` and `AudioBeepPlayer` from the outside (already injected via setters today). The dispatcher's job is to decide *when* to schedule and *what to play*, not to play directly. The provider continues to drive in-app beeps from inside the ticker callback for sample-accurate timing — but the *decision* of whether/which beep to play comes from `SoundDispatcher`. **The supersetRest branch** must be preserved in the classify-tick-edge logic: countdown beeps fire from `getReady`, `setRest`, *or* `supersetRest` (the current `_startTicker` already does this — preserve it).

6. **Public API of `SessionStateProvider` is unchanged.** Every public method (`start`, `pause`, `resume`, `reset`, `finalizeSession`, `advanceManually`, `jumpToWorkout/Exercise/Set/Next/Previous`, `requestManualOvertime`, `exitOvertime`, `reconcileAfterBackground`, `setForegrounded`, `setBeepScheduler`, `setAudioBeepPlayer`, `setSoundMode`, `setRestOvertimeOnBackground`, `canScheduleExactAlarms`, `requestExactAlarmPermission`, `updateActiveExercise`, `updateActiveSupersetSets`, `weekIndex`/`sessionIndex`/`workoutIndex`/`exerciseIndex` and their increment/decrement/setters, `progress`, `remaining`, `phase`, `isPaused`, `overtimeElapsed`, `activeSession`, `nextStop`, `previousStop`) keeps the same name and signature. Call sites do not change.

7. **The `@visibleForTesting` debug seams stay on the provider** (`debugSetPhase`, `debugSetLastTickAt`, `debugRestEventCount`, `debugRestEventTypes`). They delegate to the helpers internally as needed, but their external surface is unchanged so existing tests work without edits. **`debugSetPhase` has a `supersetRest` branch** that pre-advances `exerciseIndex` and asserts `hasNextInSuperset` — that branch stays on the provider (it's the test seam, not state-machine logic).

8. **Existing tests are the safety net.** Each task ends with `flutter test` returning fully green. If a migrated test fails, the migration is wrong, not the test.

---

## Task 1: Extract `SessionStateMachine` (pure functions)

**Why first:** It has zero state. It's a rename + import update, with brand-new helper-level tests. Existing provider tests continue to exercise the same code paths (now via the helper) and must stay green.

**Scope (updated 2026-05-19):** The original plan listed 5 helper functions. The current codebase has ~10 functions that belong in this helper. Below is the full list.

**Files:**
- Create: `lib/providers/session/session_state_machine.dart`
- Create: `test/providers/session/session_state_machine_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Run baseline tests**

```bash
flutter test
```
Expected: all PASS, including superset tests. Confirms the starting state is green.

- [ ] **Step 2: Write the failing helper test**

Create `test/providers/session/session_state_machine_test.dart`. Cover at minimum:

- `calculateNextState`: rep→repRest, repRest→rep, setRest→rep (set bump), exerciseRest→rep, getReady→rep, supersetRest→rep, end-of-session returns null, fixedDuration skips repRest, manual returns null.
- `getDurationForPhase`: rep on each ExerciseType, repRest, setRest, exerciseRest in solo case, exerciseRest in between-rounds-superset case (returns `supersetSetRest` with fallback to `workout.timeBetweenExercises`), supersetRest returns `superset.restSeconds`, getReady = 10s, overtime/paused/workoutComplete = zero.
- `isOvertimeEligible`: true for `setRest`/`exerciseRest`/`getReady`; false for `rep`/`repRest`/`supersetRest`/`overtime`/`paused`/`workoutComplete`.
- `isRestPhase`: true for `getReady`/`setRest`/`exerciseRest`/`overtime`/`paused`/`supersetRest`; false for `rep`/`repRest`/`workoutComplete`.
- `enterExerciseRest`: advances exerciseIndex within workout, crosses workout boundary, returns null at session end.
- `enterPostSetRest`: solo → setRest at same exerciseIndex; superset last member with more rounds → exerciseRest with `exerciseIndex` pre-advanced to groupStart and `currentSet+1`.
- `calculateNextStop` / `calculatePreviousStop`: solo skips to next/prev exercise (sets aren't stops); superset member walks group order; group exit lands past `groupEnd`; previous-stop into a group lands on `groupEnd` at last round.
- `firstStopAtOrAfter`: within-workout returns rep; cross-workout returns getReady; off-end returns null.
- `lastStopBefore`: within-workout returns rep; into a superset block lands at groupEnd with effective sets; cross-workout returns the prev-workout last exercise.
- `matchRestTypeToTimerPhase`: maps each rest phase to its RestType; throws on non-rest phase.

Adapt the constructor argument lists to match the actual `Exercise`/`Workout`/`Session` constructors used in `session_state_provider_event_log_test.dart` and `session_state_provider_superset_test.dart`.

- [ ] **Step 3: Run — verify it fails**

```bash
flutter test test/providers/session/session_state_machine_test.dart
```
Expected: compile error — `SessionStateMachine` does not exist.

- [ ] **Step 4: Implement `SessionStateMachine`**

Create `lib/providers/session/session_state_machine.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart' show RestType;
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart'
    show SessionProgress, TimerPhase;
import 'package:flash_forward/utils/superset_utils.dart';
// Note: SessionProgress and TimerPhase are imported from session_state_provider
// for now. Task 5 (optional) considers lifting them into a shared types file.

/// Pure functions over (SessionProgress, Session). No state, no side effects.
/// Extracted from SessionStateProvider so the state machine can be unit-tested
/// in isolation and reused by simulators (e.g. SoundDispatcher's
/// _calculateFutureBeeps walk).
class SessionStateMachine {
  SessionStateMachine._();

  // ── Transition computation ────────────────────────────────────────────

  /// Verbatim port of SessionStateProvider._calculateNextState.
  /// Substitutions: `_activeSession!` → `activeSession`. No other changes.
  /// Preserves the supersetRest branches inside the rep/repRest cases and
  /// the exerciseRest case's `isCrossWorkout` heuristic.
  static SessionProgress? calculateNextState(
    SessionProgress p,
    Session activeSession,
  ) {
    // [Verbatim port of the full switch on p.phase, including the recursive
    //  call when timeBetweenReps == 0, and the supersetRest pre-advance in
    //  rep and repRest cases.]
  }

  /// Verbatim port of SessionStateProvider._enterExerciseRest.
  /// Returns null when there are no more exercises (session ends).
  static SessionProgress? enterExerciseRest(
    SessionProgress progress,
    Session activeSession,
  ) {
    // [Verbatim port. The cross-workout branch sets phase to TimerPhase.exerciseRest
    //  (the conversion to getReady happens inside calculateNextState's exerciseRest
    //  case, not here).]
  }

  /// Verbatim port of SessionStateProvider._enterPostSetRest. Solo → setRest;
  /// superset → exerciseRest with exerciseIndex pre-advanced to groupStart and
  /// currentSet incremented.
  static SessionProgress enterPostSetRest(
    SessionProgress p,
    Workout workout,
  ) {
    // [Verbatim port.]
  }

  // ── Stop-based navigation (nextStop / previousStop) ───────────────────

  /// Verbatim port of SessionStateProvider._calculateNextStop. Returns null
  /// at end of session.
  static SessionProgress? calculateNextStop(
    SessionProgress p,
    Session activeSession,
  ) {
    // [Verbatim port. Handles solo (next exercise), superset member (next in
    //  group OR wrap to groupStart with set+1 OR exit past groupEnd).]
  }

  /// Verbatim port of SessionStateProvider._calculatePreviousStop.
  static SessionProgress? calculatePreviousStop(
    SessionProgress p,
    Session activeSession,
  ) {
    // [Verbatim port. Solo: previous exercise. Superset member: earlier in
    //  group OR wrap back to groupEnd with set-1 OR step out before group.]
  }

  /// Verbatim port of SessionStateProvider._firstStopAtOrAfter.
  static SessionProgress? firstStopAtOrAfter(
    Session activeSession,
    int workoutIndex,
    int index,
  ) {
    // [Verbatim port.]
  }

  /// Verbatim port of SessionStateProvider._lastStopBefore. When landing on a
  /// superset member, lands at groupEnd with effectiveSets (the natural
  /// "previous step" outside the group).
  static SessionProgress? lastStopBefore(
    Session activeSession,
    int workoutIndex,
    int index,
  ) {
    // [Verbatim port.]
  }

  // ── Duration / classification ─────────────────────────────────────────

  /// Verbatim port of SessionStateProvider._getDurationForPhase. Includes the
  /// supersetRest branch (reads `ss.restSeconds` with 15s fallback) and the
  /// exerciseRest between-rounds branch (reads `ss.supersetSetRest` with
  /// fallback to `workout.timeBetweenExercises`). Returns Duration.zero when
  /// the active session is null or phase is workoutComplete.
  static Duration getDurationForPhase(
    SessionProgress p,
    Session? activeSession,
  ) {
    // [Verbatim port of the full switch on p.phase. Do not collapse the
    //  exerciseRest branch's superset check — `ss != null && p.currentSet > 1`
    //  is load-bearing.]
  }

  static bool isOvertimeEligible(TimerPhase p) =>
      p == TimerPhase.setRest ||
      p == TimerPhase.exerciseRest ||
      p == TimerPhase.getReady;

  static bool isRestPhase(TimerPhase p) =>
      p == TimerPhase.getReady ||
      p == TimerPhase.setRest ||
      p == TimerPhase.exerciseRest ||
      p == TimerPhase.overtime ||
      p == TimerPhase.paused ||
      p == TimerPhase.supersetRest;

  /// Verbatim port of SessionStateProvider._matchRestTypeToTimerPhase. Throws
  /// StateError when given a non-rest phase (rep/repRest/workoutComplete).
  static RestType matchRestTypeToTimerPhase(TimerPhase p) {
    // [Verbatim port of the switch.]
  }
}
```

The `// [Verbatim port ...]` blocks must be filled in literally from the existing provider code. Do not change semantics. Where the original used `_activeSession!`, substitute the passed-in `activeSession` parameter.

- [ ] **Step 5: Run the helper tests**

```bash
flutter test test/providers/session/session_state_machine_test.dart
```
Expected: all PASS.

- [ ] **Step 6: Update `SessionStateProvider` to delegate**

In `lib/providers/session_state_provider.dart`:
- Add `import 'package:flash_forward/providers/session/session_state_machine.dart';`
- Delete these private methods (they're now on the helper):
  - `_calculateNextState`
  - `_enterExerciseRest`
  - `_enterPostSetRest`
  - `_calculateNextStop`
  - `_calculatePreviousStop`
  - `_firstStopAtOrAfter`
  - `_lastStopBefore`
  - `_getDurationForPhase`
  - `_isOvertimeEligible`
  - `_isRestPhase`
  - `_matchRestTypeToTimerPhase`

Replace every internal call site (search for each name above). Typical substitutions:
- `_calculateNextState(p)` → `SessionStateMachine.calculateNextState(p, _activeSession!)`
- `_enterExerciseRest(p)` → `SessionStateMachine.enterExerciseRest(p, _activeSession!)`
- `_enterPostSetRest(p, w)` → `SessionStateMachine.enterPostSetRest(p, w)`
- `_calculateNextStop(p)` → `SessionStateMachine.calculateNextStop(p, _activeSession!)` (with the existing null-guard on `_activeSession` preserved)
- `_calculatePreviousStop(p)` → `SessionStateMachine.calculatePreviousStop(p, _activeSession!)`
- `_getDurationForPhase(p)` → `SessionStateMachine.getDurationForPhase(p, _activeSession)` (note: helper accepts nullable session, mirroring original)
- `_isOvertimeEligible(p)` → `SessionStateMachine.isOvertimeEligible(p)`
- `_isRestPhase(p)` → `SessionStateMachine.isRestPhase(p)`
- `_matchRestTypeToTimerPhase(p)` → `SessionStateMachine.matchRestTypeToTimerPhase(p)`

The `nextStop` / `previousStop` getters become:

```dart
SessionProgress? get nextStop {
  if (_activeSession == null) return null;
  return SessionStateMachine.calculateNextStop(_progress, _activeSession!);
}

SessionProgress? get previousStop {
  if (_activeSession == null) return null;
  return SessionStateMachine.calculatePreviousStop(_progress, _activeSession!);
}
```

The `debugSetPhase` `supersetRest` branch (the assertion + pre-advance) stays on the provider — it's a test seam, not state-machine logic.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The 4 provider tests + the new helper test must all be green. The superset test (`session_state_provider_superset_test.dart`) is the canary for the new nav-helper extraction — any failure there points at a missed substitution in `_calculateNextStop` or `_calculatePreviousStop` or their `_firstStopAtOrAfter`/`_lastStopBefore` helpers.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/session/session_state_machine.dart \
        lib/providers/session_state_provider.dart \
        test/providers/session/session_state_machine_test.dart
git commit -m "refactor(session): extract pure SessionStateMachine helper"
```

---

## Task 2: Extract `SessionTelemetryRecorder`

**Why next:** Telemetry has its own clear scope: open/close drafts, accumulate per-set times, build the summary. It's the largest of the three helpers but has the cleanest seam — `_onPhaseTransition` is the only entry point that drives it.

**Files:**
- Create: `lib/providers/session/session_telemetry_recorder.dart`
- Create: `test/providers/session/session_telemetry_recorder_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Write the failing helper test**

Create `test/providers/session/session_telemetry_recorder_test.dart`. Cover at minimum:
- initial state (no events, no drafts)
- openSet → closeSet records one SetEvent
- openRest(setRest) → closeRest records one RestEvent with the right RestType
- openRest(supersetRest) → closeRest records `RestType.supersetRest`
- accumulators reset when a new set opens
- `addRepSlice` and `addRepRestSlice` accumulate into the right field
- discardDrafts clears in-flight but not closed events
- clear resets to initial state
- `computeSummary` aggregates active+rest times across multiple events (mirrors the existing `_computeSummary` cases in `session_state_provider_event_log_test.dart`)

- [ ] **Step 2: Run — verify it fails**

```bash
flutter test test/providers/session/session_telemetry_recorder_test.dart
```
Expected: compile error — `SessionTelemetryRecorder` does not exist.

- [ ] **Step 3: Implement the helper**

Create `lib/providers/session/session_telemetry_recorder.dart`:

```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flash_forward/providers/session_state_provider.dart'
    show SessionProgress, TimerPhase;

/// Records set and rest events during an active session.
///
/// Owned by SessionStateProvider. Cleared on session start and reset.
/// Stateful but bounded: the only state is the in-progress drafts and the
/// accumulated event lists; nothing leaks across sessions.
class SessionTelemetryRecorder {
  final List<SetEvent> _setEvents = [];
  final List<RestEvent> _restEvents = [];

  _OpenSetDraft? _activeSetDraft;
  _OpenRestDraft? _activeRestDraft;

  Duration _currentSetActiveAccum = Duration.zero;
  Duration _currentSetRepRestAccum = Duration.zero;

  List<SetEvent> get setEvents => List.unmodifiable(_setEvents);
  List<RestEvent> get restEvents => List.unmodifiable(_restEvents);

  /// Adds the given [slice] to the active-time accumulator. Called by the
  /// provider when leaving a rep phase, before the new phase opens.
  void addRepSlice(Duration slice) {
    _currentSetActiveAccum += slice;
  }

  /// Adds the given [slice] to the rep-rest-time accumulator.
  void addRepRestSlice(Duration slice) {
    _currentSetRepRestAccum += slice;
  }

  void openSet(SessionProgress p) {
    _activeSetDraft = _OpenSetDraft(
      workoutIndex: p.workoutIndex,
      exerciseIndex: p.exerciseIndex,
      setIndex: p.currentSet,
      startAt: DateTime.now(),
    );
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  void closeSet({required int repsCompleted}) {
    if (_activeSetDraft == null) return;
    _setEvents.add(SetEvent(
      workoutIndex: _activeSetDraft!.workoutIndex,
      exerciseIndex: _activeSetDraft!.exerciseIndex,
      setIndex: _activeSetDraft!.setIndex,
      startAt: _activeSetDraft!.startAt,
      endAt: DateTime.now(),
      activeTime: _currentSetActiveAccum,
      interRepRestTime: _currentSetRepRestAccum,
      repsCompleted: repsCompleted,
    ));
    _activeSetDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  void openRest(
    RestType restType,
    SessionProgress p, {
    required Duration plannedDuration,
  }) {
    int? setIndex;
    if (restType == RestType.setRest) setIndex = p.currentSet;
    _activeRestDraft = _OpenRestDraft(
      restType: restType,
      workoutIndex: p.workoutIndex,
      exerciseIndex: p.exerciseIndex,
      setIndex: setIndex,
      startAt: DateTime.now(),
      plannedDuration: plannedDuration,
    );
  }

  void closeRest() {
    if (_activeRestDraft == null) return;
    final actual = DateTime.now().difference(_activeRestDraft!.startAt);
    final overtime = _activeRestDraft!.restType == RestType.overtime
        ? actual : Duration.zero;
    _restEvents.add(RestEvent(
      restType: _activeRestDraft!.restType,
      workoutIndex: _activeRestDraft!.workoutIndex,
      exerciseIndex: _activeRestDraft!.exerciseIndex,
      setIndex: _activeRestDraft!.setIndex,
      startAt: _activeRestDraft!.startAt,
      endAt: DateTime.now(),
      plannedDuration: _activeRestDraft!.plannedDuration,
      actualDuration: actual,
      overtimeDuration: overtime,
    ));
    _activeRestDraft = null;
  }

  void discardDrafts() {
    _activeSetDraft = null;
    _activeRestDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  void clear() {
    _setEvents.clear();
    _restEvents.clear();
    discardDrafts();
  }

  /// Verbatim port of SessionStateProvider._computeSummary. Reads from
  /// _setEvents and _restEvents.
  SessionSummary computeSummary() {
    // [Verbatim port.]
  }
}

class _OpenSetDraft {
  final int workoutIndex;
  final int exerciseIndex;
  final int setIndex;
  final DateTime startAt;
  _OpenSetDraft({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
  });
}

class _OpenRestDraft {
  final RestType restType;
  final int workoutIndex;
  final int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final Duration plannedDuration;
  _OpenRestDraft({
    required this.restType,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.plannedDuration,
  });
}
```

- [ ] **Step 4: Run the helper tests**

```bash
flutter test test/providers/session/session_telemetry_recorder_test.dart
```
Expected: all PASS.

- [ ] **Step 5: Migrate `SessionStateProvider` to delegate**

In `lib/providers/session_state_provider.dart`:
- Add `import 'package:flash_forward/providers/session/session_telemetry_recorder.dart';`
- Add a field: `final SessionTelemetryRecorder _telemetry = SessionTelemetryRecorder();`
- Delete `_setEvents`, `_restEvents`, `_activeSetDraft`, `_activeRestDraft`, `_currentSetActiveAccum`, `_currentSetRepRestAccum` fields.
- Delete `_OpenSetDraft` and `_OpenRestDraft` classes at the bottom of the file (now in the helper).
- Delete `_startSetDraft`, `_closeSetDraft`, `_startRestDraft`, `_closeRestDraft`, `_discardDrafts` methods.
- Delete `_computeSummary`.

Update `_onPhaseTransition`:
- The opening `if (_currentPhaseEnteredAt != null) { ... }` block stays on the provider (it owns `_currentPhaseEnteredAt`), but accumulator updates become `_telemetry.addRepSlice(slice)` and `_telemetry.addRepRestSlice(slice)`.
- `_closeRestDraft()` → `_telemetry.closeRest()`.
- `_closeSetDraft(repsCompleted: ...)` → `_telemetry.closeSet(repsCompleted: ...)`.
- `_startSetDraft(newProgress)` → `_telemetry.openSet(newProgress)`.
- `_startRestDraft(_matchRestTypeToTimerPhase(to), newProgress)` becomes:
  ```dart
  _telemetry.openRest(
    SessionStateMachine.matchRestTypeToTimerPhase(to),
    newProgress,
    plannedDuration: _plannedDurationForRest(to, newProgress),
  );
  ```
  where `_plannedDurationForRest` is a small private helper on the provider that mirrors the original `_startRestDraft`'s logic (planned = `getDurationForPhase` except for `overtime`/`paused` which use `Duration.zero`). The helper is pure — it doesn't compute planned duration itself, because the previous behaviour put that decision on the provider side, and we keep it there for now.

Update `start()`:
- `_setEvents.clear(); _restEvents.clear();` → `_telemetry.clear();`
- `_discardDrafts();` → (already covered by `_telemetry.clear()` since it calls `discardDrafts()` internally; remove the separate call).

Update `reset()`:
- Same as `start()`.

Update `pause()`'s slice-attribution block — the manual accumulator updates become `_telemetry.addRepSlice(slice)` and `_telemetry.addRepRestSlice(slice)`.

Update `finalizeSession()`:
```dart
Session finalizeSession() {
  _telemetry.closeSet(repsCompleted: _progress.currentRep);
  _telemetry.closeRest();
  final summary = _telemetry.computeSummary();
  return _activeSession!.copyWith(
    setEvents: List.unmodifiable(_telemetry.setEvents),
    restEvents: List.unmodifiable(_telemetry.restEvents),
    summary: summary,
  );
}
```

Update the `@visibleForTesting` debug methods:
- `debugRestEventCount() => _telemetry.restEvents.length;`
- `debugRestEventTypes() => _telemetry.restEvents.map((e) => e.restType).toList();`

Update any other site that read `_setEvents` or `_restEvents` directly (search the file).

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The risk surface here is `_onPhaseTransition` — it's the orchestration heart. Failures in `session_state_provider_event_log_test.dart` indicate a sequencing bug in the migration. The `supersetRest` rest-event (created by `_startRestDraft` going through `matchRestTypeToTimerPhase`) is exercised by the superset test suite — verify both pass.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/session/session_telemetry_recorder.dart \
        lib/providers/session_state_provider.dart \
        test/providers/session/session_telemetry_recorder_test.dart
git commit -m "refactor(session): extract SessionTelemetryRecorder for event log"
```

---

## Task 3: Extract `SoundDispatcher`

**Why next:** The remaining "non-state-machine" surface in the provider is the sound logic — `_rescheduleSound`, `_calculateFutureBeeps`, `_addBeepsForPhase`, plus the in-app beep selection inside `_startTicker`. Extracting it removes ~80 LOC from the provider and isolates the OS-notification interaction.

**Critical reminder:** The current `_startTicker`'s in-app beep block fires countdown and go beeps from `getReady`, `setRest`, *or* `supersetRest` (this was extended when superset shipped). The `classifyTickEdge` helper must preserve this — the original plan listed only `getReady` and `setRest`.

**Files:**
- Create: `lib/providers/session/sound_dispatcher.dart`
- Create: `test/providers/session/sound_dispatcher_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Write the failing helper test**

Create `test/providers/session/sound_dispatcher_test.dart`. Cover at minimum:
- `shouldPlayInApp`: true when foregrounded and (`soundsOnly` or `both`); false otherwise.
- `shouldUseNotifications`: true when backgrounded, not paused, has active session, and mode includes notifications; false otherwise.
- `classifyTickEdge` countdown: fires when `previousRemaining > countdownThreshold && current <= countdownThreshold && current > 0` in `getReady` / `setRest` / **`supersetRest`** (all three sources). Test each source phase.
- `classifyTickEdge` go-beep: fires when leaving any of `getReady` / `setRest` / `repRest` / `supersetRest` with `previousRemaining > leadTime && current <= leadTime` (mirrors the current 4-source list).
- `classifyTickEdge` stop-beep: fires when `prevPhase == rep && newPhase == rep && previousRemaining > leadTime && current <= leadTime` (the "still in rep, about to end" case).
- `classifyTickEdge` returns null when `playInApp` is false, when no edge matches, when phases are identical mid-rep, etc.
- `classifyTickEdge` ordering: countdown can be returned in the same call that would otherwise return go-beep — verify the precedence matches what `_startTicker` does today (the provider's current code is three separate `if` blocks that can both fire on the same tick; the helper should return one but the provider may call it multiple times — see Step 5).

- [ ] **Step 2: Run — verify it fails**

```bash
flutter test test/providers/session/sound_dispatcher_test.dart
```
Expected: compile error — `SoundDispatcher` does not exist.

- [ ] **Step 3: Implement the helper**

Create `lib/providers/session/sound_dispatcher.dart`:

```dart
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/session/session_state_machine.dart';
import 'package:flash_forward/providers/session_state_provider.dart'
    show SessionProgress, TimerPhase;
import 'package:flash_forward/providers/settings_provider.dart' show SoundMode;
import 'package:flash_forward/services/audio_beep_player.dart';
import 'package:flash_forward/services/beep_scheduler.dart';

/// Decides what to beep and when, given timer state. Stateless w.r.t. session
/// progress — the caller passes everything in. Wraps the BeepScheduler and
/// AudioBeepPlayer references for convenience but does not own their
/// lifecycles.
class SoundDispatcher {
  SoundDispatcher();

  BeepScheduler? _scheduler;
  AudioBeepPlayer? _player;

  void setScheduler(BeepScheduler scheduler) => _scheduler = scheduler;
  void setPlayer(AudioBeepPlayer player) => _player = player;

  BeepScheduler? get scheduler => _scheduler;
  AudioBeepPlayer? get player => _player;

  /// True when in-app audio should play given current foreground/mode.
  static bool shouldPlayInApp({
    required bool isForegrounded,
    required SoundMode mode,
  }) =>
      isForegrounded && (mode == SoundMode.soundsOnly || mode == SoundMode.both);

  /// True when OS-level notifications should be scheduled given current
  /// foreground/mode/session presence.
  static bool shouldUseNotifications({
    required bool isForegrounded,
    required bool isPaused,
    required bool hasActiveSession,
    required SoundMode mode,
  }) =>
      !isForegrounded &&
      !isPaused &&
      hasActiveSession &&
      (mode == SoundMode.both || mode == SoundMode.notificationsOnly);

  /// Drives reschedule decisions for OS-level notifications.
  void reschedule({
    required bool isForegrounded,
    required bool isPaused,
    required SessionProgress progress,
    required Duration remaining,
    required Session? activeSession,
    required SoundMode mode,
    required bool restOvertimeOnBackground,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    if (_scheduler == null) return;
    final useNotifications = shouldUseNotifications(
      isForegrounded: isForegrounded,
      isPaused: isPaused,
      hasActiveSession: activeSession != null,
      mode: mode,
    );
    if (useNotifications) {
      final beeps = _calculateFutureBeeps(
        progress: progress,
        remaining: remaining,
        activeSession: activeSession!,
        restOvertimeOnBackground: restOvertimeOnBackground,
        audioLeadTime: audioLeadTime,
        countdownLeadTime: countdownLeadTime,
      );
      _scheduler!.scheduleAll(beeps);
    } else {
      _scheduler!.cancelAll();
    }
  }

  /// Verbatim port of SessionStateProvider._calculateFutureBeeps. Reads
  /// SessionStateMachine for the phase-walk simulation.
  List<ScheduledBeep> _calculateFutureBeeps({
    required SessionProgress progress,
    required Duration remaining,
    required Session activeSession,
    required bool restOvertimeOnBackground,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    // [Verbatim port. Internal calls to _calculateNextState / _getDurationForPhase
    //  become SessionStateMachine.calculateNextState / .getDurationForPhase.]
  }

  /// Verbatim port of _addBeepsForPhase.
  void _addBeepsForPhase(
    List<ScheduledBeep> beeps,
    SessionProgress p,
    DateTime phaseEndAt,
    Duration audioLeadTime,
    Duration countdownLeadTime,
  ) {
    // [Verbatim port.]
  }

  /// Classifies the in-app beep that should fire on a tick boundary, if any.
  /// Returns the highest-priority beep for the given edge; the provider may
  /// call this multiple times per tick (for countdown then go) if both apply
  /// — see the comment in [_startTicker] migration.
  ///
  /// Source phases for countdown and go-beep include supersetRest, matching
  /// the current _startTicker behavior post-superset.
  static BeepType? classifyTickEdge({
    required TimerPhase prevPhase,
    required TimerPhase newPhase,
    required Duration prevRemaining,
    required Duration newRemaining,
    required bool playInApp,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    if (!playInApp) return null;

    final countdownThreshold = const Duration(seconds: 3) + countdownLeadTime;
    // Countdown: from getReady/setRest/supersetRest, crossing > threshold → ≤ threshold.
    if ((prevPhase == TimerPhase.getReady ||
            prevPhase == TimerPhase.setRest ||
            prevPhase == TimerPhase.supersetRest) &&
        prevRemaining > countdownThreshold &&
        newRemaining <= countdownThreshold &&
        newRemaining > Duration.zero) {
      return BeepType.countdown;
    }
    // Go beep: leaving any of the four lead-in phases when ≤ audioLeadTime remains.
    if ((prevPhase == TimerPhase.getReady ||
            prevPhase == TimerPhase.setRest ||
            prevPhase == TimerPhase.repRest ||
            prevPhase == TimerPhase.supersetRest) &&
        prevRemaining > audioLeadTime &&
        newRemaining <= audioLeadTime) {
      return BeepType.go;
    }
    // Stop beep: still in rep, about to end.
    if (prevPhase == TimerPhase.rep &&
        newPhase == TimerPhase.rep &&
        prevRemaining > audioLeadTime &&
        newRemaining <= audioLeadTime) {
      return BeepType.stop;
    }
    return null;
  }

  /// Calls cancelAll on the underlying scheduler. Convenience for the
  /// provider's reset/finalize paths.
  void cancelAll() => _scheduler?.cancelAll();

  Future<bool> canScheduleExactAlarms() =>
      _scheduler?.canScheduleExactAlarms() ?? Future.value(true);

  Future<void> requestExactAlarmPermission() =>
      _scheduler?.requestExactAlarmPermission() ?? Future.value();
}
```

Note on the `classifyTickEdge` return type: the current `_startTicker` has three sequential `if` blocks (countdown, go, stop) that *could* both fire on the same tick if the conditions overlap. In practice the countdown and go conditions are mutually exclusive (countdown crosses the 3s+lead threshold; go crosses the leadTime threshold). But to preserve behaviour exactly, the provider's `_startTicker` migration in Step 5 calls `classifyTickEdge` in *the same order* the original code checks the three branches, and plays whichever the helper returns. If both could fire in theory, only one plays — but a check against `audio_beep_player_test`-equivalent test would catch a difference. Keeping a single-return helper is simpler than threading an enum-list back to the caller.

- [ ] **Step 4: Run the helper tests**

```bash
flutter test test/providers/session/sound_dispatcher_test.dart
```
Expected: all PASS.

- [ ] **Step 5: Migrate `SessionStateProvider` to delegate**

In `lib/providers/session_state_provider.dart`:
- Add `import 'package:flash_forward/providers/session/sound_dispatcher.dart';`
- Replace `BeepScheduler? _beepScheduler;` and `AudioBeepPlayer? _audioPlayer;` with `final SoundDispatcher _sound = SoundDispatcher();`
- Update the public setters:
  ```dart
  void setBeepScheduler(BeepScheduler scheduler) => _sound.setScheduler(scheduler);
  void setAudioBeepPlayer(AudioBeepPlayer player) => _sound.setPlayer(player);
  ```
- Replace `_rescheduleSound()` calls with:
  ```dart
  _sound.reschedule(
    isForegrounded: _isForegrounded,
    isPaused: _isPaused,
    progress: _progress,
    remaining: _remaining,
    activeSession: _activeSession,
    mode: _soundMode,
    restOvertimeOnBackground: _restOvertimeOnBackground,
    audioLeadTime: _audioLeadTime,
    countdownLeadTime: _countdownLeadTime,
  );
  ```
  (The two lead-time constants are passed in because they live on the provider as `static const`. Alternatively, lift them onto `SoundDispatcher` as static fields and remove the parameters — simpler, also fine.)
- Delete `_rescheduleSound`, `_calculateFutureBeeps`, `_addBeepsForPhase` from the provider.
- Update `_startTicker` ticker callback's beep block. Replace the three separate `if (playInApp && ...)` checks with a single `classifyTickEdge` call:

  ```dart
  final playInApp = SoundDispatcher.shouldPlayInApp(
    isForegrounded: _isForegrounded,
    mode: _soundMode,
  );
  final beepType = SoundDispatcher.classifyTickEdge(
    prevPhase: prevProgress.phase,
    newPhase: _progress.phase,
    prevRemaining: previousRemaining,
    newRemaining: _remaining,
    playInApp: playInApp,
    audioLeadTime: _audioLeadTime,
    countdownLeadTime: _countdownLeadTime,
  );
  if (beepType != null) _sound.player?.play(beepType);
  ```

  Note: if you discover during testing that two beeps fired on the same tick before (e.g. countdown then go), expand `classifyTickEdge` to return a `List<BeepType>` and adjust the call site. The single-return implementation above matches the *most-recent in-source ordering* but doesn't run all three checks — verify the existing beep timing tests (manual smoke + `session_state_provider_overtime_test.dart`'s reach into beep behaviour) before committing.

- Update `setForegrounded`, `pause`, `reset`, `_advanceByElapsed` (its `_beepScheduler?.cancelAll()` site), `_enterOvertime`, `exitOvertime` to call `_sound.cancelAll()` and `_sound.reschedule(...)` as needed.
- Update `canScheduleExactAlarms()` and `requestExactAlarmPermission()` to delegate to `_sound`.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The countdown timing edge-cases in `_startTicker` are the highest-risk migration here. If a test that asserts countdown beep firing fails, double-check the ordering of `classifyTickEdge` invocation against the existing branching.

- [ ] **Step 7: Manual UI smoke test for sound**

Run a session in the simulator/device. Verify:
1. **In-app sounds (solo):** `getReady` countdown plays, `go` beep at start of each rep, `stop` beep at end of each rep.
2. **In-app sounds (superset):** between members, countdown plays in `supersetRest` and `go` fires when entering the next member's rep.
3. **Backgrounded sounds:** Lock the screen during a session in `notificationsOnly` mode; verify a countdown notification fires.
4. **Mode toggling:** Change `SoundMode` mid-session; verify the in-app/notification choice updates immediately.

```bash
flutter run -d <device>
```

If any sound case regresses, the helper extraction missed a call site or `classifyTickEdge` collapsed two checks that needed to stay separate.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/session/sound_dispatcher.dart \
        lib/providers/session_state_provider.dart \
        test/providers/session/sound_dispatcher_test.dart
git commit -m "refactor(session): extract SoundDispatcher for beep timing"
```

---

## Task 4: Sweep — verify provider shape

Now `SessionStateProvider` should be back to its core: timer ticker, public API surface, and orchestration of the three helpers. Verify the result and clean up.

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Possibly modify: `test/providers/session_state_provider_*_test.dart` (only if a `setUp` needs adjustment)

- [ ] **Step 1: Measure file size**

```bash
wc -l lib/providers/session_state_provider.dart \
      lib/providers/session/session_state_machine.dart \
      lib/providers/session/session_telemetry_recorder.dart \
      lib/providers/session/sound_dispatcher.dart
```
Expected (rough, updated 2026-05-19 to reflect the bigger helper scope and the supersets-era provider):
- provider: ~500 LOC
- state machine: ~400 LOC (was ~200 in original plan; absorbs nav helpers + post-set rest + match-rest-type)
- telemetry: ~180 LOC
- sound dispatcher: ~180 LOC
- Total: ~1,260 LOC (from 1,627 LOC original) — reduction comes from collapsed boilerplate and tighter file boundaries, not from removing logic.

- [ ] **Step 2: Find any leftover private helpers**

```bash
grep -nE "_calculateNextState|_enterExerciseRest|_enterPostSetRest|_calculateNextStop|_calculatePreviousStop|_firstStopAtOrAfter|_lastStopBefore|_getDurationForPhase|_isOvertimeEligible|_isRestPhase|_matchRestTypeToTimerPhase|_startSetDraft|_closeSetDraft|_startRestDraft|_closeRestDraft|_discardDrafts|_computeSummary|_rescheduleSound|_calculateFutureBeeps|_addBeepsForPhase|_setEvents|_restEvents|_activeSetDraft|_activeRestDraft|_currentSetActiveAccum|_currentSetRepRestAccum|_OpenSetDraft|_OpenRestDraft" lib/providers/session_state_provider.dart
```
Expected: zero matches. Anything that survived means a reference was missed.

- [ ] **Step 3: Static analysis**

```bash
flutter analyze
```
Expected: no errors. Warnings about unused imports are acceptable but should be cleaned up.

- [ ] **Step 4: Run the full suite (final pass)**

```bash
flutter test
```
Expected: all PASS, every existing provider test (event_log, finalize, overtime, superset) plus the three new helper tests.

- [ ] **Step 5: Manual end-to-end smoke test**

```bash
flutter run -d <device>
```

Walk through:
1. **Session start → completion:** start a session, complete every set/rep, verify the summary screen shows correct totals.
2. **Pause/resume:** pause mid-rep, resume; verify the rep continues and the active-time accumulator is preserved.
3. **Manual overtime:** during setRest, request overtime, exit overtime; verify the state machine returns to the next rep.
4. **Background reconciliation:** lock the screen during a setRest, unlock after the rest should have ended; verify either:
   - It progressed to the next rep (no `restOvertimeOnBackground`), or
   - It entered automatic overtime (with `restOvertimeOnBackground` enabled).
5. **Mid-session edit:** edit an exercise's sets mid-session; verify the clamp behavior and the new sets count is honored.
6. **Mid-session superset edit:** edit a superset member's sets mid-session via `updateActiveSupersetSets`; verify all members of the same superset share the new value.
7. **Superset round walk:** run a superset workout end-to-end. Verify `supersetRest` fires between members, between-rounds rest fires after the last member with more rounds remaining (using `supersetSetRest`), and the group is exited cleanly past `groupEnd` on the last round.
8. **nextStop/previousStop:** during a session, tap the bottom-bar next/previous buttons. Verify the labels show the right upcoming/previous exercise (solo → next exercise; superset → next member or group exit; previous → mirror).

Each step that regresses points back to a specific helper extraction.

- [ ] **Step 6: Commit (if Step 2 or 3 found cleanup)**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "refactor(session): clean up unused imports after helper extraction"
```

---

## Task 5: (Optional) Lift `SessionProgress` and `TimerPhase` into a shared types file

**Why optional:** The helper files import `SessionProgress` and `TimerPhase` from `session_state_provider.dart`. This works (Dart allows it) but creates an asymmetric dependency: the helper imports the provider that uses it. Cleaner: lift those two types into a sibling file.

Skip this task if the existing arrangement compiles and tests pass — it's purely cosmetic. Do it only if you want a cleaner dependency graph.

**Files:**
- Create: `lib/providers/session/session_progress.dart`
- Modify: `lib/providers/session_state_provider.dart`, `lib/providers/session/session_state_machine.dart`, `lib/providers/session/session_telemetry_recorder.dart`, `lib/providers/session/sound_dispatcher.dart`
- Modify: every test file that imports `SessionProgress` or `TimerPhase` (4 provider tests + 3 helper tests)

- [ ] **Step 1: Move the types**

Cut `enum TimerPhase { ... }` and `class SessionProgress { ... }` (and `copyWith`) from `session_state_provider.dart` and paste into `lib/providers/session/session_progress.dart`.

- [ ] **Step 2: Update imports**

In every file that previously imported these from `session_state_provider.dart`, switch to `import 'package:flash_forward/providers/session/session_progress.dart';`.

`session_state_provider.dart` itself adds the new import and removes the type definitions.

- [ ] **Step 3: Run the full suite**

```bash
flutter test
```
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(session): lift SessionProgress and TimerPhase into shared types"
```

---

## Plan-level acceptance criteria

- [ ] `flutter test` passes after every numbered task commit (no skipped tasks).
- [ ] `flutter analyze` returns zero errors after Task 4.
- [ ] `lib/providers/session_state_provider.dart` is at most 550 LOC after Task 4 (up from the original plan's 500 because the supersets-era provider has more public API surface).
- [ ] No file in `lib/providers/session/` exceeds 450 LOC.
- [ ] The 4 existing `session_state_provider_*_test.dart` files are unchanged or only had `setUp` adjusted (no test-body rewrites).
- [ ] The 3 new helper test files exist and exercise their respective helpers in isolation.
- [ ] Manual smoke walk in Task 4 Step 5 shows no behavioral regression — including all 8 listed scenarios.

---

## Architectural risks (open before execution)

1. **`_onPhaseTransition` is the orchestration heart.** It's called from many sites (every `start`/`pause`/`resume`/`jumpTo*`/`jumpToNext`/`jumpToPrevious`/`enterOvertime`/`exitOvertime`/`advanceByElapsed`/`advanceManually`/`debugSetPhase`). The migration in Task 2 changes how telemetry is driven from inside it. **Mitigation:** Task 2 Step 6 runs the full suite, including `event_log_test.dart` which is the canonical exerciser of this method. A regression there is the canary.

2. **In-app beep timing is sample-sensitive.** The decision-of-which-beep logic in `_startTicker` is currently three sequential `if` blocks; Task 3 collapses them into `SoundDispatcher.classifyTickEdge` returning a single `BeepType?`. If two beeps could *theoretically* fire on the same tick (countdown + go), the collapsed helper plays only one. **Mitigation:** Task 3 Step 5 calls this out; the manual test in Task 3 Step 7 is the only safety net for audio playback (automated tests cannot verify audio). If smoke testing reveals a missing beep, expand the helper to return `List<BeepType>`.

3. **supersetRest sources for beeps.** Both the countdown and the go-beep blocks include `supersetRest` as a source phase. The original plan listed only `getReady` and `setRest`. **Mitigation:** Locked decision 5 calls this out; the helper tests in Task 3 Step 1 must include a supersetRest source case.

4. **The `_currentPhaseEnteredAt` slice attribution lives outside the helper.** Pause's manual slice attribution and `_onPhaseTransition`'s slice attribution both update accumulators. After Task 2, both routes call `_telemetry.addRepSlice(slice)`. **Risk:** if one route is missed, telemetry undercounts. **Mitigation:** the existing `event_log_test.dart` has assertions on `activeTime` and `interRepRestTime` totals — failure pinpoints the missed site.

5. **The optional Task 5 (`SessionProgress` lift) creates a wide diff.** Every helper file and every test file changes its import. **Mitigation:** It's optional. Skip unless you see clear value.

6. **Background reconciliation has subtle interactions with `SoundDispatcher.reschedule`.** `reconcileAfterBackground` currently calls `_rescheduleSound()` at multiple points; Task 3 routes those through `_sound.reschedule(...)`. If a path is missed, foregrounded sound state can desync. **Mitigation:** Task 4 Step 5 manual smoke includes the "lock screen during setRest" scenario.

7. **Helper construction lifecycle.** `SessionTelemetryRecorder` is a `final` field on the provider. Currently telemetry state is cleared via `_setEvents.clear()` etc. inside `start()` and `reset()`. Task 2 routes those through `_telemetry.clear()`. **Risk:** if any internal helper state is missed in `clear()`, leaks bridge sessions. **Mitigation:** the helper's `clear()` calls `discardDrafts()` and clears both lists — verify no other state is added.

8. **`nextStop`/`previousStop` are reactive.** They're invoked from `session_active_bottom_bar.dart` on every rebuild (no caching). The helper extraction must not introduce additional computation per call. **Mitigation:** the helper functions are pure and have the same complexity as the original methods — verify the bottom bar still renders cleanly under load (rapid `notifyListeners` from the ticker).

9. **Test-helper imports.** Helper tests import `SessionProgress` and `TimerPhase` from `session_state_provider.dart` (Tasks 1-4). If Task 5 is executed, every test file must update those imports. **Mitigation:** Task 5 Step 2 explicitly lists the test-side updates.

---

## Execution Handoff

This plan is ready. **Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Use `superpowers:subagent-driven-development`.

2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batched with checkpoints for review.
