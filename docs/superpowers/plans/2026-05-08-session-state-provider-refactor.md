# SessionStateProvider Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim [lib/providers/session_state_provider.dart](../../../lib/providers/session_state_provider.dart) (1,212 LOC and growing once superset lands) by extracting three plain helper classes — `SessionStateMachine`, `SessionTelemetryRecorder`, `SoundDispatcher` — without splitting the provider into multiple `ChangeNotifier`s. The provider remains the single owner of in-memory session state; the helpers are stateless or own only their own scoped state. Functionality must be preserved bit-for-bit; the existing test suite (`session_state_provider_event_log_test.dart`, `session_state_provider_finalize_test.dart`, `session_state_provider_overtime_test.dart`, plus the superset tests) is the safety net.

**Architecture:** The timer engine, telemetry recording, and sound dispatch are tightly coupled around one in-memory state machine — so splitting them across multiple `ChangeNotifier`s would force coordination on every phase transition (the exact complexity we're trying to avoid). Instead, extract **plain helper classes** that the single `SessionStateProvider` composes:

- `SessionStateMachine` — pure functions over `(SessionProgress, Session)`. Owns `_calculateNextState`, `_enterExerciseRest`, `_isOvertimeEligible`, `_isRestPhase`, `_getDurationForPhase`. No state, no notifications.
- `SessionTelemetryRecorder` — owns `_setEvents`, `_restEvents`, the two draft types, set-level accumulators, `_computeSummary`. The provider calls it from `_onPhaseTransition`. State, but scoped to one session run.
- `SoundDispatcher` — owns `_rescheduleSound`, `_calculateFutureBeeps`, `_addBeepsForPhase`, the in-app beep choices. Provider hands it the phase change + foreground state; it routes to `BeepScheduler` or `AudioBeepPlayer`.

After extraction, `SessionStateProvider` shrinks from ~1,212 LOC to ~400 LOC: holds `_progress`, `_remaining`, `_activeSession`, the ticker, the public `start/pause/resume/jumpTo*` API, and `_onPhaseTransition` orchestration that calls the three helpers.

**Tech Stack:** Flutter, Provider (ChangeNotifier), Dart, `flutter_test`. No new external dependencies.

---

## Pre-execution check

Before starting this plan:

1. **Superset must have shipped.** This plan is built against the post-superset shape of `session_state_provider.dart` — including `TimerPhase.supersetRest`, `setsForExerciseInWorkout`, `updateActiveSupersetSets`, and the superset test suite. If superset has not landed, file:line references in this plan will be stale; either ship superset first or update the references throughout.
2. **Plan A may have shipped or not.** This plan is independent of Plan A (PresetProvider refactor). They can be executed in either order. If Plan A has shipped, the only knock-on effect here is that `SessionStateProvider` no longer reads `PresetProvider` — but it never did, so this is moot.

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

2. **`SessionStateMachine` is fully pure.** It takes `(SessionProgress, Session)` and returns `SessionProgress?` or `Duration` — no side effects, no member fields beyond static configuration. This makes it trivially unit-testable.

3. **`SessionTelemetryRecorder` is stateful but scoped.** It owns the event list and accumulators that today live on the provider. The provider keeps a single instance, replaced/cleared on `start()` and `reset()`. Its public surface mirrors what the provider's `_onPhaseTransition` already does: `openSet`, `closeSet`, `openRest`, `closeRest`, `discardDrafts`, `summary`.

4. **`SoundDispatcher` owns timing-of-beep logic, not audio resources.** It still receives `BeepScheduler` and `AudioBeepPlayer` from the outside (already injected via setters today). The dispatcher's job is to decide *when* to schedule and *what to play*, not to play directly. The provider continues to drive in-app beeps from inside the ticker callback for sample-accurate timing — but the *decision* of whether/which beep to play comes from `SoundDispatcher`.

5. **Public API of `SessionStateProvider` is unchanged.** Every public method (`start`, `pause`, `resume`, `reset`, `finalizeSession`, `advanceManually`, `jumpToWorkout/Exercise/Set`, `requestManualOvertime`, `exitOvertime`, `reconcileAfterBackground`, `setForegrounded`, `setBeepScheduler`, `setAudioBeepPlayer`, `setSoundMode`, `setRestOvertimeOnBackground`, `canScheduleExactAlarms`, `requestExactAlarmPermission`, `updateActiveExercise`, `updateActiveSupersetSets`, `weekIndex`/`sessionIndex`/`workoutIndex`/`exerciseIndex` and their increment/decrement/setters, `progress`, `remaining`, `phase`, `isPaused`, `overtimeElapsed`, `activeSession`) keeps the same name and signature. Call sites do not change.

6. **The `@visibleForTesting` debug seams stay on the provider** (`debugSetPhase`, `debugSetLastTickAt`, `debugRestEventCount`, `debugRestEventTypes`). They delegate to the helpers internally as needed, but their external surface is unchanged so existing tests work without edits.

7. **Existing tests are the safety net.** Each task ends with `flutter test` returning fully green. If a migrated test fails, the migration is wrong, not the test.

---

## Task 1: Extract `SessionStateMachine` (pure functions)

**Why first:** It has zero state. It's a rename + import update, with brand-new helper-level tests. Existing provider tests continue to exercise the same code paths (now via the helper) and must stay green.

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

Create `test/providers/session/session_state_machine_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session/session_state_machine.dart';
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Helper to build a single-workout single-exercise session for tests.
  Session minimalSession({
    int sets = 3,
    int reps = 5,
    int timeBetweenReps = 2,
    int timeBetweenSets = 30,
    int timeBetweenExercises = 60,
    ExerciseType type = ExerciseType.timedReps,
  }) {
    final exercise = Exercise(
      // Fill required fields per the actual Exercise constructor; mirror
      // the test helpers in session_state_provider_event_log_test.dart.
    );
    final workout = Workout(
      // ...
      exercises: [exercise],
      timeBetweenExercises: timeBetweenExercises,
    );
    return Session(/* ..., */ workouts: [workout]);
  }

  group('SessionStateMachine.calculateNextState', () {
    test('rep → repRest when reps remaining and timeBetweenReps > 0', () {
      final s = minimalSession();
      const p = SessionProgress(
        workoutIndex: 0, exerciseIndex: 0,
        currentSet: 1, currentRep: 1, phase: TimerPhase.rep,
      );
      final next = SessionStateMachine.calculateNextState(p, s);
      expect(next?.phase, TimerPhase.repRest);
    });

    test('repRest → rep with currentRep+1 when reps remaining', () {
      final s = minimalSession();
      const p = SessionProgress(
        workoutIndex: 0, exerciseIndex: 0,
        currentSet: 1, currentRep: 2, phase: TimerPhase.repRest,
      );
      final next = SessionStateMachine.calculateNextState(p, s);
      expect(next?.phase, TimerPhase.rep);
      expect(next?.currentRep, 3);
    });

    test('setRest → rep with currentSet+1 and currentRep reset', () {
      final s = minimalSession();
      const p = SessionProgress(
        workoutIndex: 0, exerciseIndex: 0,
        currentSet: 1, currentRep: 5, phase: TimerPhase.setRest,
      );
      final next = SessionStateMachine.calculateNextState(p, s);
      expect(next?.phase, TimerPhase.rep);
      expect(next?.currentSet, 2);
      expect(next?.currentRep, 1);
    });

    test('returns null on the final exercise of the final workout', () {
      // Build a session where currentSet == sets, currentRep == reps,
      // exerciseIndex is the last, workoutIndex is the last.
      // Verify exerciseRest → null after exhausting workouts.
    });
  });

  group('SessionStateMachine.getDurationForPhase', () {
    test('rep on timedReps returns Duration(seconds: timePerRep)', () {
      // ...
    });
    test('rep on fixedDuration returns Duration(seconds: activeTime)', () {
      // ...
    });
    test('rep on manual returns Duration.zero', () {
      // ...
    });
    test('repRest returns timeBetweenReps', () {
      // ...
    });
    test('setRest returns timeBetweenSets', () {
      // ...
    });
    test('exerciseRest returns workout.timeBetweenExercises', () {
      // ...
    });
    test('overtime/workoutComplete/paused all return Duration.zero', () {
      // ...
    });
    test('getReady returns Duration(seconds: 10)', () {
      // ...
    });
    test('supersetRest returns the active superset.restSeconds', () {
      // (post-superset only — verify the superset path)
    });
  });

  group('SessionStateMachine.isOvertimeEligible', () {
    test('true for setRest, exerciseRest, getReady', () {
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.setRest), isTrue);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.exerciseRest), isTrue);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.getReady), isTrue);
    });
    test('false for rep, repRest, supersetRest, overtime, paused, workoutComplete', () {
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.rep), isFalse);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.repRest), isFalse);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.supersetRest), isFalse);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.overtime), isFalse);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.paused), isFalse);
      expect(SessionStateMachine.isOvertimeEligible(TimerPhase.workoutComplete), isFalse);
    });
  });

  group('SessionStateMachine.isRestPhase', () {
    test('true for getReady, setRest, exerciseRest, overtime, paused, supersetRest', () {
      // ...
    });
    test('false for rep, repRest, workoutComplete', () {
      // ...
    });
  });
}
```

Adapt the constructor argument lists to match the actual `Exercise`/`Workout`/`Session` constructors used in the existing provider tests.

- [ ] **Step 3: Run — verify it fails**

```bash
flutter test test/providers/session/session_state_machine_test.dart
```
Expected: compile error — `SessionStateMachine` does not exist.

- [ ] **Step 4: Implement `SessionStateMachine`**

Create `lib/providers/session/session_state_machine.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;
// (Note: SessionProgress and TimerPhase are imported from session_state_provider
// for now. Task 5 considers whether to lift them into a shared types file.)

/// Pure functions over (SessionProgress, Session). No state, no side effects.
/// Extracted from SessionStateProvider so the state machine can be unit-tested
/// in isolation and reused by simulators (e.g. SoundDispatcher's
/// _calculateFutureBeeps walk).
class SessionStateMachine {
  SessionStateMachine._();

  /// Verbatim port of SessionStateProvider._calculateNextState. Takes the
  /// active session because it reads workouts/exercises/supersets to decide
  /// the transition.
  static SessionProgress? calculateNextState(
    SessionProgress p,
    Session activeSession,
  ) {
    // [Verbatim port from session_state_provider.dart:809-878 with these
    // substitutions: `_activeSession!` → `activeSession`. No other changes.]
    final Workout workout = activeSession.workouts[p.workoutIndex];
    final Exercise exercise = workout.exercises[p.exerciseIndex];

    switch (p.phase) {
      case TimerPhase.rep:
        // ... full body unchanged ...
      // ... etc. ...
    }
  }

  /// Verbatim port of SessionStateProvider._enterExerciseRest.
  static SessionProgress? enterExerciseRest(
    SessionProgress progress,
    Session activeSession,
  ) {
    // [Verbatim port from lines 883-909 with `_activeSession!` →
    // `activeSession`. No other changes.]
  }

  /// Verbatim port of SessionStateProvider._getDurationForPhase. Returns
  /// Duration.zero when the active session is null, mirroring the original
  /// guard.
  static Duration getDurationForPhase(
    SessionProgress p,
    Session? activeSession,
  ) {
    // [Verbatim port from lines 1149-1178. Add the supersetRest case post-
    // superset: when phase == TimerPhase.supersetRest, look up the superset
    // by exerciseId and return Duration(seconds: superset.restSeconds).]
  }

  static bool isOvertimeEligible(TimerPhase p) {
    return p == TimerPhase.setRest ||
        p == TimerPhase.exerciseRest ||
        p == TimerPhase.getReady;
  }

  static bool isRestPhase(TimerPhase p) =>
      p == TimerPhase.getReady ||
      p == TimerPhase.setRest ||
      p == TimerPhase.exerciseRest ||
      p == TimerPhase.overtime ||
      p == TimerPhase.paused ||
      p == TimerPhase.supersetRest;
}
```

The `// [Verbatim port ...]` blocks must be filled in literally from the existing provider code. Do not change semantics.

- [ ] **Step 5: Run the helper tests**

```bash
flutter test test/providers/session/session_state_machine_test.dart
```
Expected: all PASS.

- [ ] **Step 6: Update `SessionStateProvider` to delegate**

In `lib/providers/session_state_provider.dart`:
- Add `import 'package:flash_forward/providers/session/session_state_machine.dart';`
- Delete `_calculateNextState` (lines 809-878).
- Delete `_enterExerciseRest` (lines 883-909).
- Delete `_getDurationForPhase` (lines 1149-1178).
- Delete `_isOvertimeEligible` (lines 920-924).
- Delete `_isRestPhase` (lines 926-931).

Replace every internal call site:
- `_calculateNextState(p)` → `SessionStateMachine.calculateNextState(p, _activeSession!)` (the caller has already null-checked `_activeSession`).
- `_enterExerciseRest(p)` → `SessionStateMachine.enterExerciseRest(p, _activeSession!)`.
- `_getDurationForPhase(p)` → `SessionStateMachine.getDurationForPhase(p, _activeSession)`.
- `_isOvertimeEligible(p)` → `SessionStateMachine.isOvertimeEligible(p)`.
- `_isRestPhase(p)` → `SessionStateMachine.isRestPhase(p)`.

The internal callers are:
- `_advanceByElapsed` (line ~664)
- `_calculateFutureBeeps` (line ~729)
- `start` (calls `_getDurationForPhase`)
- `pause`/`resume`/`jumpTo*`/`updateActiveExercise`/`advanceManually` (all call `_getDurationForPhase`)
- `requestManualOvertime` (calls `_isOvertimeEligible`)
- `exitOvertime` (calls `_calculateNextState`)
- `reconcileAfterBackground` (multiple)
- `_onPhaseTransition` (calls `_isRestPhase`)

Update each.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The 4 provider tests + the new helper test must all be green. If a provider test fails, the most likely cause is a missed call site — search for any remaining `_calculateNextState`, `_enterExerciseRest`, `_getDurationForPhase`, `_isOvertimeEligible`, `_isRestPhase` in `session_state_provider.dart`.

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

Create `test/providers/session/session_telemetry_recorder_test.dart`:

```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/providers/session/session_telemetry_recorder.dart';
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionTelemetryRecorder', () {
    late SessionTelemetryRecorder rec;
    setUp(() => rec = SessionTelemetryRecorder());

    test('initial state has no events and no open drafts', () {
      expect(rec.setEvents, isEmpty);
      expect(rec.restEvents, isEmpty);
    });

    test('openSet then closeSet records one SetEvent', () {
      const p = SessionProgress(
        workoutIndex: 0, exerciseIndex: 0,
        currentSet: 1, currentRep: 1, phase: TimerPhase.rep,
      );
      rec.openSet(p);
      rec.closeSet(repsCompleted: 5);
      expect(rec.setEvents, hasLength(1));
      expect(rec.setEvents.single.repsCompleted, 5);
    });

    test('openRest then closeRest records one RestEvent', () {
      const p = SessionProgress(
        workoutIndex: 0, exerciseIndex: 0,
        currentSet: 2, currentRep: 1, phase: TimerPhase.setRest,
      );
      rec.openRest(RestType.setRest, p, plannedDuration: const Duration(seconds: 30));
      rec.closeRest();
      expect(rec.restEvents, hasLength(1));
      expect(rec.restEvents.single.restType, RestType.setRest);
    });

    test('summary aggregates active+rest times across events', () {
      // ...
    });

    test('discardDrafts clears open drafts but not closed events', () {
      // ...
    });

    test('clear resets to initial state', () {
      // ...
    });

    test('accumulator resets when a new set opens', () {
      // (covers the _currentSetActiveAccum / _currentSetRepRestAccum reset)
    });

    test('addRepSlice attributes time to the active-time accumulator', () {
      // Drives the per-set accumulators directly.
    });
  });
}
```

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
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;

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

  SessionSummary computeSummary() {
    // Verbatim port of SessionStateProvider._computeSummary (lines 452-498).
    // Reads from _setEvents and _restEvents.
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
- Update `_onPhaseTransition`:
  - The opening `if (_currentPhaseEnteredAt != null) { ... }` block stays, but the accumulator updates become `_telemetry.addRepSlice(slice)` and `_telemetry.addRepRestSlice(slice)`.
  - `_closeRestDraft()` → `_telemetry.closeRest()`.
  - `_closeSetDraft(repsCompleted: ...)` → `_telemetry.closeSet(repsCompleted: ...)`.
  - `_startSetDraft(newProgress)` → `_telemetry.openSet(newProgress)`.
  - `_startRestDraft(_matchRestTypeToTimerPhase(to), newProgress)` → `_telemetry.openRest(_matchRestTypeToTimerPhase(to), newProgress, plannedDuration: SessionStateMachine.getDurationForPhase(newProgress, _activeSession))`. (Note: previously the planned duration came from `_getDurationForPhase` — preserve that. The provider must compute it before calling the helper because the helper is pure.)
- Update `start()`:
  - `_setEvents.clear(); _restEvents.clear();` → `_telemetry.clear();`
  - `_discardDrafts();` → `_telemetry.discardDrafts();`
- Update `reset()`:
  - `_setEvents.clear(); _restEvents.clear();` → `_telemetry.clear();`
  - `_discardDrafts();` → `_telemetry.discardDrafts();`
- Update `pause()`'s slice-attribution block — the manual accumulator updates become `_telemetry.addRepSlice(slice)` and `_telemetry.addRepRestSlice(slice)`.
- Update `finalizeSession()`:
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
- Update the `@visibleForTesting` debug methods:
  - `debugRestEventCount() => _telemetry.restEvents.length;`
  - `debugRestEventTypes() => _telemetry.restEvents.map((e) => e.restType).toList();`
- Update any other site that read `_setEvents` or `_restEvents` directly.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The risk surface here is `_onPhaseTransition` — it's the orchestration heart. Failures in `session_state_provider_event_log_test.dart` indicate a sequencing bug in the migration.

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

**Files:**
- Create: `lib/providers/session/sound_dispatcher.dart`
- Create: `test/providers/session/sound_dispatcher_test.dart`
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Write the failing helper test**

Create `test/providers/session/sound_dispatcher_test.dart`:

```dart
import 'package:flash_forward/providers/session/sound_dispatcher.dart';
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;
import 'package:flash_forward/providers/settings_provider.dart' show SoundMode;
import 'package:flutter_test/flutter_test.dart';

class _FakeBeepScheduler {
  bool cancelAllCalled = false;
  List<dynamic> scheduled = [];
  void cancelAll() => cancelAllCalled = true;
  void scheduleAll(List<dynamic> beeps) => scheduled = beeps;
}

class _FakeAudioPlayer {
  String? lastPlayed;
  void play(dynamic beep) => lastPlayed = beep.toString();
}

void main() {
  group('SoundDispatcher.shouldPlayInApp', () {
    test('true when foreground and mode is soundsOnly', () {
      expect(SoundDispatcher.shouldPlayInApp(
        isForegrounded: true, mode: SoundMode.soundsOnly,
      ), isTrue);
    });
    test('false when backgrounded', () {
      expect(SoundDispatcher.shouldPlayInApp(
        isForegrounded: false, mode: SoundMode.soundsOnly,
      ), isFalse);
    });
    test('false when mode is notificationsOnly', () {
      expect(SoundDispatcher.shouldPlayInApp(
        isForegrounded: true, mode: SoundMode.notificationsOnly,
      ), isFalse);
    });
  });

  group('SoundDispatcher.shouldUseNotifications', () {
    test('true when backgrounded and notificationsOnly', () {
      // ...
    });
    test('false when foregrounded', () {
      // ...
    });
    test('false when no active session', () {
      // ...
    });
  });

  group('SoundDispatcher.classifyTickEdge', () {
    // Covers the in-app beep-decision logic from _startTicker.
    test('countdown when previousRemaining > 3s and current <= 3s in getReady', () {
      // ...
    });
    test('go beep when entering rep from non-rep', () {
      // ...
    });
    test('stop beep when leaving rep into non-rep', () {
      // ...
    });
    test('no beep on rep→rep (same phase tick)', () {
      // ...
    });
  });
}
```

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
import 'package:flash_forward/providers/session_state_provider.dart' show SessionProgress, TimerPhase;
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
      );
      _scheduler!.scheduleAll(beeps);
    } else {
      _scheduler!.cancelAll();
    }
  }

  /// Verbatim port of SessionStateProvider._calculateFutureBeeps with
  /// `_progress`/`_remaining`/`_activeSession`/`_restOvertimeOnBackground`
  /// passed in as parameters.
  List<ScheduledBeep> _calculateFutureBeeps({
    required SessionProgress progress,
    required Duration remaining,
    required Session activeSession,
    required bool restOvertimeOnBackground,
  }) {
    // [Verbatim port from session_state_provider.dart:729-763.]
  }

  /// Verbatim port of _addBeepsForPhase.
  void _addBeepsForPhase(
    List<ScheduledBeep> beeps,
    SessionProgress p,
    DateTime phaseEndAt,
  ) {
    // [Verbatim port from session_state_provider.dart:765-798.]
  }

  /// Classifies the in-app beep that should fire on a tick boundary, if any.
  /// Encapsulates the decision logic from inside _startTicker so tests can
  /// drive it directly.
  static BeepType? classifyTickEdge({
    required TimerPhase prevPhase,
    required TimerPhase newPhase,
    required Duration prevRemaining,
    required Duration newRemaining,
    required bool playInApp,
  }) {
    if (!playInApp) return null;
    // Countdown: from getReady or setRest, crossing >3s → ≤3s.
    if ((prevPhase == TimerPhase.getReady ||
            prevPhase == TimerPhase.setRest) &&
        prevRemaining > const Duration(seconds: 3) &&
        newRemaining <= const Duration(seconds: 3) &&
        newRemaining > Duration.zero) {
      return BeepType.countdown;
    }
    // Go beep: entering rep from non-rep.
    if (newPhase == TimerPhase.rep && prevPhase != TimerPhase.rep) {
      return BeepType.go;
    }
    // Stop beep: leaving rep to non-rep.
    if (prevPhase == TimerPhase.rep && newPhase != TimerPhase.rep) {
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
  );
  ```
- Delete `_rescheduleSound`, `_calculateFutureBeeps`, `_addBeepsForPhase` from the provider.
- Update `_startTicker` ticker callback's beep block:
  ```dart
  if (!identical(_progress, prevProgress)) {
    _sound.reschedule(/* ...same args as above... */);
    final beepType = SoundDispatcher.classifyTickEdge(
      prevPhase: prevProgress.phase,
      newPhase: _progress.phase,
      prevRemaining: previousRemaining,
      newRemaining: _remaining,
      playInApp: SoundDispatcher.shouldPlayInApp(
        isForegrounded: _isForegrounded,
        mode: _soundMode,
      ),
    );
    if (beepType != null) _sound.player?.play(beepType);
  }
  // Same for the countdown branch above the transition check — call
  // SoundDispatcher.classifyTickEdge in the per-tick path too. (Verify
  // ordering preserves "countdown fires before go-beep" semantics.)
  ```
- Update `setForegrounded`, `pause`, `reset`, `_advanceByElapsed` (its `_beepScheduler?.cancelAll()` site), `_enterOvertime`, `exitOvertime` to call `_sound.cancelAll()` and `_sound.reschedule(...)` as needed.
- Update `canScheduleExactAlarms()` and `requestExactAlarmPermission()` to delegate to `_sound`.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```
Expected: all PASS. The countdown timing edge-cases in `_startTicker` are the highest-risk migration here. If a test that asserts countdown beep firing fails, double-check the ordering of `classifyTickEdge` invocation against the existing branching.

- [ ] **Step 7: Manual UI smoke test for sound**

Run a session in the simulator/device. Verify:
1. **In-app sounds:** `getReady` countdown plays, `go` beep at start of each rep, `stop` beep at end of each rep.
2. **Backgrounded sounds:** Lock the screen during a session in `notificationsOnly` mode; verify a countdown notification fires.
3. **Mode toggling:** Change `SoundMode` mid-session; verify the in-app/notification choice updates immediately.

```bash
flutter run -d <device>
```

If any sound case regresses, the helper extraction missed a call site.

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
Expected (rough): provider ~400 LOC, state machine ~200 LOC, telemetry ~180 LOC, sound dispatcher ~150 LOC. Total ~930 — reduction comes from collapsed boilerplate, not from removing logic.

- [ ] **Step 2: Find any leftover private helpers**

```bash
grep -nE "_calculateNextState|_enterExerciseRest|_getDurationForPhase|_isOvertimeEligible|_isRestPhase|_startSetDraft|_closeSetDraft|_startRestDraft|_closeRestDraft|_discardDrafts|_computeSummary|_rescheduleSound|_calculateFutureBeeps|_addBeepsForPhase|_setEvents|_restEvents|_activeSetDraft|_activeRestDraft|_currentSetActiveAccum|_currentSetRepRestAccum|_OpenSetDraft|_OpenRestDraft" lib/providers/session_state_provider.dart
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
Expected: all PASS, every existing provider test plus the three new helper tests, plus the superset tests if they're in.

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
6. **Superset (post-superset):** run a superset workout, verify `supersetRest` fires between members and that the superset's `supersetSets` is honored.

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
- Modify: every test file that imports `SessionProgress` or `TimerPhase`

- [ ] **Step 1: Move the types**

Cut `enum TimerPhase { ... }` and `class SessionProgress { ... }` (and `copyWith`) from `session_state_provider.dart` and paste into `lib/providers/session/session_progress.dart`. Add an exporting `library;` declaration.

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
- [ ] `lib/providers/session_state_provider.dart` is at most 500 LOC after Task 4.
- [ ] No file in `lib/providers/session/` exceeds 250 LOC.
- [ ] The 4 existing `session_state_provider_*_test.dart` files are unchanged or only had `setUp` adjusted (no test-body rewrites).
- [ ] The 3 new helper test files exist and exercise their respective helpers in isolation.
- [ ] Manual smoke walk in Task 4 Step 5 shows no behavioral regression — including all six listed scenarios.

---

## Architectural risks (open before execution)

1. **`_onPhaseTransition` is the orchestration heart.** It's called from many sites (every `start`/`pause`/`resume`/`jumpTo*`/`enterOvertime`/`exitOvertime`/`advanceByElapsed`/`advanceManually`/`debugSetPhase`). The migration in Task 2 changes how telemetry is driven from inside it. **Mitigation:** Task 2 Step 6 runs the full suite, including `event_log_test.dart` which is the canonical exerciser of this method. A regression there is the canary.

2. **In-app beep timing is sample-sensitive.** The decision-of-which-beep logic in `_startTicker` is currently inline; Task 3 extracts it into `SoundDispatcher.classifyTickEdge`. If the extraction reorders the countdown branch vs. the transition branch, beep timing can shift by a tick. **Mitigation:** Task 3 Step 5 specifies the exact ordering ("countdown fires before go-beep"), and Task 3 Step 7 is a manual UI test for sound — automated tests cannot verify audio playback, so the manual check is load-bearing here.

3. **The `_currentPhaseEnteredAt` slice attribution lives outside the helper.** Pause's manual slice attribution and `_onPhaseTransition`'s slice attribution both update accumulators. After Task 2, both routes call `_telemetry.addRepSlice(slice)`. **Risk:** if one route is missed, telemetry undercounts. **Mitigation:** the existing `event_log_test.dart` has assertions on `activeTime` and `interRepRestTime` totals — failure pinpoints the missed site.

4. **The optional Task 5 (`SessionProgress` lift) creates a wide diff.** Every helper file and every test file changes its import. **Mitigation:** It's optional. Skip unless you see clear value.

5. **Background reconciliation has subtle interactions with `SoundDispatcher.reschedule`.** `reconcileAfterBackground` currently calls `_rescheduleSound()` at multiple points; Task 3 routes those through `_sound.reschedule(...)`. If a path is missed, foregrounded sound state can desync. **Mitigation:** Task 4 Step 5 manual smoke includes the "lock screen during setRest" scenario.

6. **Helper construction lifecycle.** `SessionTelemetryRecorder` is a `final` field on the provider. Currently telemetry state is cleared via `_setEvents.clear()` etc. inside `start()` and `reset()`. Task 2 routes those through `_telemetry.clear()`. **Risk:** if `start()` is called twice without an intervening `reset()`, the helper instance is shared and `clear()` resets it correctly, but if any internal helper state is missed in `clear()`, leaks bridge sessions. **Mitigation:** the helper's `clear()` calls `discardDrafts()` and clears both lists — verify no other state is added.

7. **Test-helper imports.** Helper tests import `SessionProgress` and `TimerPhase` from `session_state_provider.dart` (Tasks 1-4). If Task 5 is executed, every test file must update those imports. **Mitigation:** Task 5 Step 2 explicitly lists the test-side updates.

---

## Execution Handoff

This plan is ready. **Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Use `superpowers:subagent-driven-development`.

2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batched with checkpoints for review.

**Note from the user:** this plan is queued behind both the superset feature (`2026-05-05-superset-feature.md`) and the PresetProvider refactor (`2026-05-08-preset-provider-refactor.md`). After both ship, the user will update this plan if any line numbers or method names have shifted, then pick an execution mode.
