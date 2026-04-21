# Rest Overtime & Session Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `TimerPhase.overtime` state that holds `setRest`/`exerciseRest` phases on user demand (long-press) or on background return (settings-gated), plus a structured session event log (SetEvents + RestEvents + SessionSummary) persisted with each logged session.

**Architecture:** Extend the existing `TimerPhase` enum with `overtime`; add a new `_overtimeElapsed` counter and `_overtimeWasAutomatic` flag on `SessionStateProvider`. Overtime is entered from two paths (manual long-press, reconcileAfterBackground auto-trigger) and always exits to a fresh 10-second `getReady`. Every phase transition routes through a single `_onPhaseTransition` dispatcher that both accumulates per-set active/rest slices and opens/closes RestEvent and SetEvent drafts. Rest events split on pause; set events span pauses. Summaries are precomputed at session save.

**Tech Stack:** Flutter, Dart, Provider (ChangeNotifier), SharedPreferences, Supabase (Postgres JSONB), flutter_test, `just_audio`, `flutter_local_notifications`.

**Spec:** [docs/superpowers/specs/2026-04-14-rest-overtime-and-session-telemetry-design.md](../specs/2026-04-14-rest-overtime-and-session-telemetry-design.md)

---

## Guiding principles

- **TDD where practical.** Models and provider logic get failing tests first. UI changes get manual verification plus one widget test for the pause-button transform.
- **One commit per task.** Small, reviewable steps. Commit messages use the existing repo style (see `git log`).
- **Do not touch files outside the listed scope.** If a task requires changes not listed, stop and surface the question.
- **No unrelated refactoring.** The spec calls out the exact changes.
- **Backwards compatibility.** New `Session` fields are nullable; `Session.fromJson` tolerates missing keys.

---

## File map

**New files:**
- `lib/models/set_event.dart` — `SetEvent` model + `toJson`/`fromJson`
- `lib/models/rest_event.dart` — `RestEvent` + `RestKind` enum + `toJson`/`fromJson`
- `lib/models/session_summary.dart` — `SessionSummary` + `toJson`/`fromJson`
- `test/models/set_event_test.dart`
- `test/models/rest_event_test.dart`
- `test/models/session_summary_test.dart`
- `test/providers/session_state_provider_overtime_test.dart`
- `test/providers/session_state_provider_event_log_test.dart`

**Modified files:**
- `lib/models/session.dart` — add nullable `setEvents`, `restEvents`, `summary` fields + `toJson`/`fromJson`/`copyWith`/`deepCopy` updates
- `lib/providers/settings_provider.dart` — add `restOvertimeOnBackground` bool + setter
- `lib/providers/session_state_provider.dart` — add `TimerPhase.overtime`, `_overtimeElapsed`, `_overtimeWasAutomatic`, `_restOvertimeOnBackground`, event log state, transition dispatcher, overtime methods, reconcile updates, beep simulation truncation, session finalization helper
- `lib/services/beep_scheduler.dart` — none (all changes are in the provider's simulation loop)
- `lib/services/supabase_sync_service.dart` — include new fields in `uploadSession` payload
- `lib/providers/session_log_provider.dart` — ensure `refreshSelectedSessions` receives the finalized session (no behavioral change if caller already finalizes)
- `lib/presentation/screens/session_flow/session_active_screen.dart` — overtime branch in timer display, phase label, pause button transform, jump-button grey-out
- `lib/presentation/screens/root_screen.dart` — add `SwitchListTile` for `restOvertimeOnBackground` in `SettingsDrawer`, wire setting sync to `SessionStateProvider`

**Supabase migration:**
- Add `set_events JSONB`, `rest_events JSONB`, `summary JSONB` columns to `user_sessions` table. Tooling TBD in Task 23.

---

## Task overview

| # | Task | Phase |
|---|---|---|
| 1 | Create `SetEvent` model + tests | Models |
| 2 | Create `RestEvent` + `RestKind` model + tests | Models |
| 3 | Create `SessionSummary` model + tests | Models |
| 4 | Extend `Session` model with nullable event/summary fields + JSON round-trip tests | Models |
| 5 | Add `restOvertimeOnBackground` to `SettingsProvider` | Settings |
| 6 | Add `TimerPhase.overtime` + `_overtimeElapsed` + getter | Overtime state |
| 7 | Add `_getDurationForPhase` / `_calculateNextState` cases for overtime | Overtime state |
| 8 | Implement `_enterOvertime` private method (no event log yet) | Overtime state |
| 9 | Implement `requestManualOvertime` public method + guard tests | Overtime state |
| 10 | Implement `exitOvertime` + session-end guard + tests | Overtime state |
| 11 | Ticker increments `_overtimeElapsed` when in overtime | Overtime state |
| 12 | Update `reconcileAfterBackground` for auto-overtime + auto-exit + tests | Background auto |
| 13 | Update `_calculateFutureBeeps` to truncate at rest phase when setting is on | Beep scheduler |
| 14 | Add event log state fields + helper predicates | Event log |
| 15 | Implement `_onPhaseTransition` dispatcher (slice + rest draft + set draft) | Event log |
| 16 | Wire dispatcher into `_advanceByElapsed` transition loop | Event log |
| 17 | Wire dispatcher into `pause`/`resume` (split-on-pause for rests) + tests | Event log |
| 18 | Wire dispatcher into `advanceManually`, jumps (discard), `_enterOvertime`/`exitOvertime` | Event log |
| 19 | Implement `_computeSummary` + `finalizeSession` + hand-calculated fixture test | Event log |
| 20 | Session persistence: finalize before log call + update `SupabaseSyncService.uploadSession` | Persistence |
| 21 | UI: overtime branch in timer color/value + phase label | UI |
| 22 | UI: pause button transform (icon + color + long-press) + widget test | UI |
| 23 | UI: jump buttons disabled + greyed out during overtime | UI |
| 24 | Settings drawer: new `SwitchListTile` + wire to provider in root_screen | UI |
| 25 | Supabase JSONB migration authoring + manual verification | Persistence |
| 26 | Manual end-to-end verification + final commit | Validation |

---

## Phase 1 — Models

### Task 1: Create `SetEvent` model

**Files:**
- Create: `lib/models/set_event.dart`
- Create: `test/models/set_event_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/set_event_test.dart`:

```dart
import 'package:flash_forward/models/set_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SetEvent', () {
    final fixture = SetEvent(
      workoutIndex: 0,
      exerciseIndex: 1,
      setIndex: 2,
      startAt: DateTime.utc(2026, 4, 14, 10, 0, 0),
      endAt: DateTime.utc(2026, 4, 14, 10, 1, 30),
      activeTime: const Duration(seconds: 40),
      interRepRestTime: const Duration(seconds: 30),
      repsCompleted: 8,
    );

    test('toJson round-trips via fromJson', () {
      final restored = SetEvent.fromJson(fixture.toJson());
      expect(restored.workoutIndex, fixture.workoutIndex);
      expect(restored.exerciseIndex, fixture.exerciseIndex);
      expect(restored.setIndex, fixture.setIndex);
      expect(restored.startAt, fixture.startAt);
      expect(restored.endAt, fixture.endAt);
      expect(restored.activeTime, fixture.activeTime);
      expect(restored.interRepRestTime, fixture.interRepRestTime);
      expect(restored.repsCompleted, fixture.repsCompleted);
    });

    test('toJson encodes DateTimes as ISO8601 strings and Durations as seconds', () {
      final json = fixture.toJson();
      expect(json['startAt'], '2026-04-14T10:00:00.000Z');
      expect(json['endAt'], '2026-04-14T10:01:30.000Z');
      expect(json['activeTimeSeconds'], 40);
      expect(json['interRepRestTimeSeconds'], 30);
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/models/set_event_test.dart`
Expected: compile error (`set_event.dart` does not exist).

- [ ] **Step 3: Implement `SetEvent`**

Create `lib/models/set_event.dart`:

```dart
class SetEvent {
  final int workoutIndex;
  final int exerciseIndex;
  final int setIndex;
  final DateTime startAt;
  final DateTime endAt;
  final Duration activeTime;
  final Duration interRepRestTime;
  final int repsCompleted;

  const SetEvent({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.endAt,
    required this.activeTime,
    required this.interRepRestTime,
    required this.repsCompleted,
  });

  Map<String, dynamic> toJson() => {
        'workoutIndex': workoutIndex,
        'exerciseIndex': exerciseIndex,
        'setIndex': setIndex,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'activeTimeSeconds': activeTime.inSeconds,
        'interRepRestTimeSeconds': interRepRestTime.inSeconds,
        'repsCompleted': repsCompleted,
      };

  factory SetEvent.fromJson(Map<String, dynamic> json) => SetEvent(
        workoutIndex: json['workoutIndex'] as int,
        exerciseIndex: json['exerciseIndex'] as int,
        setIndex: json['setIndex'] as int,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: DateTime.parse(json['endAt'] as String),
        activeTime: Duration(seconds: json['activeTimeSeconds'] as int),
        interRepRestTime:
            Duration(seconds: json['interRepRestTimeSeconds'] as int),
        repsCompleted: json['repsCompleted'] as int,
      );
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `flutter test test/models/set_event_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/models/set_event.dart test/models/set_event_test.dart
git commit -m "feat: add SetEvent model for session telemetry"
```

---

### Task 2: Create `RestEvent` + `RestKind` model

**Files:**
- Create: `lib/models/rest_event.dart`
- Create: `test/models/rest_event_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/rest_event_test.dart`:

```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RestEvent', () {
    final fixture = RestEvent(
      kind: RestKind.overtime,
      workoutIndex: 0,
      exerciseIndex: 1,
      setIndex: 2,
      startAt: DateTime.utc(2026, 4, 14, 10, 0, 0),
      endAt: DateTime.utc(2026, 4, 14, 10, 0, 45),
      plannedDuration: Duration.zero,
      actualDuration: const Duration(seconds: 45),
      overtimeDuration: const Duration(seconds: 45),
    );

    test('toJson round-trips via fromJson', () {
      final restored = RestEvent.fromJson(fixture.toJson());
      expect(restored.kind, fixture.kind);
      expect(restored.workoutIndex, fixture.workoutIndex);
      expect(restored.exerciseIndex, fixture.exerciseIndex);
      expect(restored.setIndex, fixture.setIndex);
      expect(restored.startAt, fixture.startAt);
      expect(restored.endAt, fixture.endAt);
      expect(restored.plannedDuration, fixture.plannedDuration);
      expect(restored.actualDuration, fixture.actualDuration);
      expect(restored.overtimeDuration, fixture.overtimeDuration);
    });

    test('fromJson tolerates null setIndex', () {
      final json = fixture.toJson()..['setIndex'] = null;
      final restored = RestEvent.fromJson(json);
      expect(restored.setIndex, isNull);
    });

    test('kind serializes as its enum name', () {
      expect(fixture.toJson()['kind'], 'overtime');
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/models/rest_event_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement `RestEvent`**

Create `lib/models/rest_event.dart`:

```dart
enum RestKind { getReady, setRest, exerciseRest, overtime, paused }

class RestEvent {
  final RestKind kind;
  final int workoutIndex;
  final int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final DateTime endAt;
  final Duration plannedDuration;
  final Duration actualDuration;
  final Duration overtimeDuration;

  const RestEvent({
    required this.kind,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.endAt,
    required this.plannedDuration,
    required this.actualDuration,
    required this.overtimeDuration,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'workoutIndex': workoutIndex,
        'exerciseIndex': exerciseIndex,
        'setIndex': setIndex,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'plannedDurationSeconds': plannedDuration.inSeconds,
        'actualDurationSeconds': actualDuration.inSeconds,
        'overtimeDurationSeconds': overtimeDuration.inSeconds,
      };

  factory RestEvent.fromJson(Map<String, dynamic> json) => RestEvent(
        kind: RestKind.values.byName(json['kind'] as String),
        workoutIndex: json['workoutIndex'] as int,
        exerciseIndex: json['exerciseIndex'] as int,
        setIndex: json['setIndex'] as int?,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: DateTime.parse(json['endAt'] as String),
        plannedDuration:
            Duration(seconds: json['plannedDurationSeconds'] as int),
        actualDuration:
            Duration(seconds: json['actualDurationSeconds'] as int),
        overtimeDuration:
            Duration(seconds: json['overtimeDurationSeconds'] as int),
      );
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `flutter test test/models/rest_event_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/models/rest_event.dart test/models/rest_event_test.dart
git commit -m "feat: add RestEvent model with RestKind enum"
```

---

### Task 3: Create `SessionSummary` model

**Files:**
- Create: `lib/models/session_summary.dart`
- Create: `test/models/session_summary_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/session_summary_test.dart`:

```dart
import 'package:flash_forward/models/session_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummary', () {
    final fixture = const SessionSummary(
      totalTime: Duration(minutes: 30),
      activeTime: Duration(minutes: 8),
      interRepRestTime: Duration(minutes: 4),
      setRestTime: Duration(minutes: 10),
      exerciseRestTime: Duration(minutes: 5),
      getReadyTime: Duration(seconds: 30),
      overtime: Duration(minutes: 2),
      pausedTime: Duration(seconds: 30),
    );

    test('toJson round-trips via fromJson', () {
      final restored = SessionSummary.fromJson(fixture.toJson());
      expect(restored.totalTime, fixture.totalTime);
      expect(restored.activeTime, fixture.activeTime);
      expect(restored.interRepRestTime, fixture.interRepRestTime);
      expect(restored.setRestTime, fixture.setRestTime);
      expect(restored.exerciseRestTime, fixture.exerciseRestTime);
      expect(restored.getReadyTime, fixture.getReadyTime);
      expect(restored.overtime, fixture.overtime);
      expect(restored.pausedTime, fixture.pausedTime);
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/models/session_summary_test.dart`

- [ ] **Step 3: Implement `SessionSummary`**

Create `lib/models/session_summary.dart`:

```dart
class SessionSummary {
  final Duration totalTime;
  final Duration activeTime;
  final Duration interRepRestTime;
  final Duration setRestTime;
  final Duration exerciseRestTime;
  final Duration getReadyTime;
  final Duration overtime;
  final Duration pausedTime;

  const SessionSummary({
    required this.totalTime,
    required this.activeTime,
    required this.interRepRestTime,
    required this.setRestTime,
    required this.exerciseRestTime,
    required this.getReadyTime,
    required this.overtime,
    required this.pausedTime,
  });

  Map<String, dynamic> toJson() => {
        'totalTimeSeconds': totalTime.inSeconds,
        'activeTimeSeconds': activeTime.inSeconds,
        'interRepRestTimeSeconds': interRepRestTime.inSeconds,
        'setRestTimeSeconds': setRestTime.inSeconds,
        'exerciseRestTimeSeconds': exerciseRestTime.inSeconds,
        'getReadyTimeSeconds': getReadyTime.inSeconds,
        'overtimeSeconds': overtime.inSeconds,
        'pausedTimeSeconds': pausedTime.inSeconds,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        totalTime: Duration(seconds: json['totalTimeSeconds'] as int),
        activeTime: Duration(seconds: json['activeTimeSeconds'] as int),
        interRepRestTime:
            Duration(seconds: json['interRepRestTimeSeconds'] as int),
        setRestTime: Duration(seconds: json['setRestTimeSeconds'] as int),
        exerciseRestTime:
            Duration(seconds: json['exerciseRestTimeSeconds'] as int),
        getReadyTime: Duration(seconds: json['getReadyTimeSeconds'] as int),
        overtime: Duration(seconds: json['overtimeSeconds'] as int),
        pausedTime: Duration(seconds: json['pausedTimeSeconds'] as int),
      );
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `flutter test test/models/session_summary_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/models/session_summary.dart test/models/session_summary_test.dart
git commit -m "feat: add SessionSummary model for telemetry rollups"
```

---

### Task 4: Extend `Session` with event log and summary fields

**Files:**
- Modify: `lib/models/session.dart`
- Create: `test/models/session_telemetry_fields_test.dart`

- [ ] **Step 1: Read `lib/models/session.dart` fully**

Needed to see current `toJson`, `fromJson`, `copyWith`, `deepCopy` shapes.

- [ ] **Step 2: Write failing test**

Create `test/models/session_telemetry_fields_test.dart`:

```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session telemetry fields', () {
    test('Session constructs with null telemetry fields by default', () {
      final s = Session(
        id: 'x',
        title: 't',
        label: 'l',
        workouts: const [],
      );
      expect(s.setEvents, isNull);
      expect(s.restEvents, isNull);
      expect(s.summary, isNull);
    });

    test('Session.fromJson tolerates missing telemetry keys', () {
      final json = {
        'id': 'x',
        'title': 't',
        'label': 'l',
        'workouts': [],
      };
      final s = Session.fromJson(json);
      expect(s.setEvents, isNull);
      expect(s.restEvents, isNull);
      expect(s.summary, isNull);
    });

    test('Session.toJson → fromJson round-trips populated telemetry', () {
      final setEvent = SetEvent(
        workoutIndex: 0,
        exerciseIndex: 0,
        setIndex: 1,
        startAt: DateTime.utc(2026, 4, 14, 10),
        endAt: DateTime.utc(2026, 4, 14, 10, 1),
        activeTime: const Duration(seconds: 30),
        interRepRestTime: const Duration(seconds: 20),
        repsCompleted: 5,
      );
      final restEvent = RestEvent(
        kind: RestKind.setRest,
        workoutIndex: 0,
        exerciseIndex: 0,
        setIndex: 1,
        startAt: DateTime.utc(2026, 4, 14, 10, 1),
        endAt: DateTime.utc(2026, 4, 14, 10, 2),
        plannedDuration: const Duration(seconds: 60),
        actualDuration: const Duration(seconds: 60),
        overtimeDuration: Duration.zero,
      );
      final summary = const SessionSummary(
        totalTime: Duration(minutes: 2),
        activeTime: Duration(seconds: 30),
        interRepRestTime: Duration(seconds: 20),
        setRestTime: Duration(seconds: 60),
        exerciseRestTime: Duration.zero,
        getReadyTime: Duration.zero,
        overtime: Duration.zero,
        pausedTime: Duration.zero,
      );
      final s = Session(
        id: 'x',
        title: 't',
        label: 'l',
        workouts: const [],
        setEvents: [setEvent],
        restEvents: [restEvent],
        summary: summary,
      );
      final restored = Session.fromJson(s.toJson());
      expect(restored.setEvents, hasLength(1));
      expect(restored.restEvents, hasLength(1));
      expect(restored.summary, isNotNull);
      expect(restored.summary!.activeTime, const Duration(seconds: 30));
    });
  });
}
```

- [ ] **Step 3: Run test — verify it fails**

Run: `flutter test test/models/session_telemetry_fields_test.dart`

- [ ] **Step 4: Add fields to `Session`**

In `lib/models/session.dart`:

1. Add imports at top:
```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
```

2. Add three nullable fields to the class:
```dart
final List<SetEvent>? setEvents;
final List<RestEvent>? restEvents;
final SessionSummary? summary;
```

3. Add to the constructor parameter list as `this.setEvents`, `this.restEvents`, `this.summary` (all optional, no `required`).

4. Extend `toJson`:
```dart
Map<String, dynamic> toJson() => {
  // ... existing fields ...
  if (setEvents != null)
    'setEvents': setEvents!.map((e) => e.toJson()).toList(),
  if (restEvents != null)
    'restEvents': restEvents!.map((e) => e.toJson()).toList(),
  if (summary != null) 'summary': summary!.toJson(),
};
```

5. Extend `fromJson`:
```dart
factory Session.fromJson(Map<String, dynamic> json) => Session(
  // ... existing fields ...
  setEvents: (json['setEvents'] as List<dynamic>?)
      ?.map((e) => SetEvent.fromJson(e as Map<String, dynamic>))
      .toList(),
  restEvents: (json['restEvents'] as List<dynamic>?)
      ?.map((e) => RestEvent.fromJson(e as Map<String, dynamic>))
      .toList(),
  summary: json['summary'] == null
      ? null
      : SessionSummary.fromJson(json['summary'] as Map<String, dynamic>),
);
```

6. Extend `copyWith` with three new nullable parameters that pass through by default.

7. In `deepCopy`: pass `setEvents: null, restEvents: null, summary: null` explicitly — a deep-copy starts a fresh session for live tracking and must not carry telemetry from the preset.

- [ ] **Step 5: Run test — verify pass**

Run: `flutter test test/models/session_telemetry_fields_test.dart`

- [ ] **Step 6: Run full model test suite to catch regressions**

Run: `flutter test test/models/`

- [ ] **Step 7: Commit**

```bash
git add lib/models/session.dart test/models/session_telemetry_fields_test.dart
git commit -m "feat: add optional setEvents/restEvents/summary fields to Session"
```

---

## Phase 2 — Settings

### Task 5: Add `restOvertimeOnBackground` to `SettingsProvider`

**Files:**
- Modify: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Add the key, field, getter, and setter**

Add next to `_keySoundMode` / `_soundMode`:

```dart
static const _keyRestOvertimeOnBackground = 'pref_rest_overtime_on_background';
bool _restOvertimeOnBackground = false;
bool get restOvertimeOnBackground => _restOvertimeOnBackground;

Future<void> setRestOvertimeOnBackground(bool value) async {
  _restOvertimeOnBackground = value;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyRestOvertimeOnBackground, value);
}
```

Extend `init()`:

```dart
_restOvertimeOnBackground =
    prefs.getBool(_keyRestOvertimeOnBackground) ?? false;
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/providers/settings_provider.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/providers/settings_provider.dart
git commit -m "feat: add restOvertimeOnBackground setting, default off"
```

---

## Phase 3 — Overtime state machine

### Task 6: Add `TimerPhase.overtime` + state fields + getter

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add enum value**

In the `TimerPhase` enum, add `overtime` immediately before `workoutComplete`:

```dart
enum TimerPhase {
  rep,
  repRest,
  setRest,
  exerciseRest,
  overtime, // new
  workoutComplete,
  paused,
  getReady,
}
```

- [ ] **Step 2: Add state fields to `SessionStateProvider`**

Near `_lastTickAt` and the sound-mode field, add:

```dart
// Count-up timer for the overtime phase. Reset on entry.
Duration _overtimeElapsed = Duration.zero;
// Distinguishes background-auto overtime (auto-exits on foreground return)
// from manual long-press overtime (stays until user taps skip).
bool _overtimeWasAutomatic = false;
// Synced from SettingsProvider at session start and on setting change.
bool _restOvertimeOnBackground = false;
```

- [ ] **Step 3: Add getter + setter**

```dart
Duration get overtimeElapsed => _overtimeElapsed;

void setRestOvertimeOnBackground(bool value) {
  _restOvertimeOnBackground = value;
}
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/providers/session_state_provider.dart`
Expected: many "switch exhaustiveness" warnings because new `overtime` value is not handled. Those get fixed in Task 7.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: scaffold TimerPhase.overtime and overtime state fields"
```

---

### Task 7: Handle `TimerPhase.overtime` in switch statements

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add `overtime` branch to `_getDurationForPhase`**

```dart
case TimerPhase.overtime:
  return Duration.zero;
```

- [ ] **Step 2: Add `overtime` branch to `_calculateNextState`**

```dart
case TimerPhase.overtime:
  return null; // overtime never auto-advances; exit is explicit
```

- [ ] **Step 3: Add `overtime` branch to `_addBeepsForPhase`**

```dart
case TimerPhase.overtime:
  break; // no beeps while in overtime
```

(Put alongside the other no-op cases.)

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/providers/session_state_provider.dart`
Expected: no switch-exhaustiveness warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: handle TimerPhase.overtime in state machine switches"
```

---

### Task 8: Implement `_enterOvertime` private method

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add helper `_isOvertimeEligible`**

Put near the top of the class's private section:

```dart
bool _isOvertimeEligible(TimerPhase p) =>
    p == TimerPhase.setRest ||
    p == TimerPhase.exerciseRest ||
    p == TimerPhase.getReady;
```

- [ ] **Step 2: Add `_enterOvertime`**

```dart
void _enterOvertime({required bool automatic}) {
  _overtimeElapsed = Duration.zero;
  _overtimeWasAutomatic = automatic;
  _progress = _progress.copyWith(phase: TimerPhase.overtime);
  _remaining = Duration.zero;
  _rememberCurrentPhaseForPausing = TimerPhase.overtime;
  _rescheduleSound(); // overtime schedules nothing
  notifyListeners();
}
```

(No event-log hooks yet — wired in Task 18.)

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/providers/session_state_provider.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: add _enterOvertime helper"
```

---

### Task 9: `requestManualOvertime` public method + tests

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Create: `test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/providers/session_state_provider_overtime_test.dart` with setup to instantiate a provider and force it into various phases. Use a small fixture session with one exercise, 2 sets, 10s timeBetweenSets.

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Session _fixture() => Session(
      id: 's',
      title: 't',
      label: 'l',
      workouts: [
        Workout(
          id: 'w',
          title: 'w',
          label: 'w',
          exercises: [
            Exercise(
              id: 'e',
              title: 'e',
              type: ExerciseType.fixedDuration,
              sets: 2,
              timeBetweenSets: 10,
              activeTime: 5,
              timePerRep: 0,
              timeBetweenReps: 0,
              load: 0,
            ),
          ],
          timeBetweenExercises: 10,
        ),
      ],
    );

void main() {
  group('requestManualOvertime', () {
    test('succeeds from setRest', () {
      final p = SessionStateProvider()..start(_fixture());
      // Force into setRest.
      p.jumpToSet(1); // set=1, phase=rep
      // Advance phase manually by direct state manipulation is not available;
      // instead call private machinery via a ticker: skip this path and set
      // phase via a dedicated test hook if needed. For now test via long
      // elapsed advance: pause then resume with tick.
      // Simpler: assert from-rep rejects, then maneuver.
      // (This test will be fleshed out once we have a helper.)
      expect(p.phase, isNotNull);
    });
  });
}
```

> **Note for implementer:** the test above is a scaffold. Because `SessionStateProvider` doesn't yet expose a way to force a phase, add a `@visibleForTesting` helper:
>
> ```dart
> @visibleForTesting
> void debugSetPhase(TimerPhase phase) {
>   _progress = _progress.copyWith(phase: phase);
>   _remaining = _getDurationForPhase(_progress);
> }
> ```
>
> Import `package:meta/meta.dart`. Then the test can call `p.debugSetPhase(TimerPhase.setRest)` before asserting.

Flesh out the test group to cover:
- `requestManualOvertime()` returns `true` from `setRest`, `exerciseRest`, `getReady`
- Returns `false` from `rep`, `repRest`, `paused`, `workoutComplete`, `overtime`
- On success, `phase` becomes `TimerPhase.overtime`, `overtimeElapsed` is zero, `remaining` is zero

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 3: Implement `requestManualOvertime` + `debugSetPhase`**

Add `import 'package:meta/meta.dart';` at the top.

```dart
@visibleForTesting
void debugSetPhase(TimerPhase phase) {
  _progress = _progress.copyWith(phase: phase);
  _remaining = _getDurationForPhase(_progress);
  notifyListeners();
}

bool requestManualOvertime() {
  if (!_isOvertimeEligible(_progress.phase)) return false;
  _enterOvertime(automatic: false);
  return true;
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_overtime_test.dart
git commit -m "feat: requestManualOvertime public entry point"
```

---

### Task 10: `exitOvertime` + session-end guard + tests

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 1: Add tests**

Append to the existing test file:

```dart
group('exitOvertime', () {
  test('from setRest → fresh 10s getReady', () {
    final p = SessionStateProvider()..start(_fixture());
    p.debugSetPhase(TimerPhase.setRest);
    p.requestManualOvertime();
    p.exitOvertime();
    expect(p.phase, TimerPhase.getReady);
    expect(p.remaining, const Duration(seconds: 10));
  });

  test('from exerciseRest → fresh 10s getReady', () {
    final p = SessionStateProvider()..start(_fixture());
    p.debugSetPhase(TimerPhase.exerciseRest);
    p.requestManualOvertime();
    p.exitOvertime();
    expect(p.phase, TimerPhase.getReady);
    expect(p.remaining, const Duration(seconds: 10));
  });

  test('from getReady → restart 10s getReady', () {
    final p = SessionStateProvider()..start(_fixture());
    // start() enters getReady
    expect(p.phase, TimerPhase.getReady);
    p.requestManualOvertime();
    p.exitOvertime();
    expect(p.phase, TimerPhase.getReady);
    expect(p.remaining, const Duration(seconds: 10));
  });

  test('no-op when not in overtime', () {
    final p = SessionStateProvider()..start(_fixture());
    p.debugSetPhase(TimerPhase.setRest);
    final before = p.phase;
    p.exitOvertime();
    expect(p.phase, before);
  });
});
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 3: Implement `exitOvertime`**

```dart
void exitOvertime() {
  if (_progress.phase != TimerPhase.overtime) return;
  _overtimeWasAutomatic = false;
  _overtimeElapsed = Duration.zero;
  _progress = _progress.copyWith(phase: TimerPhase.getReady);
  _remaining = const Duration(seconds: 10);
  _startTicker(); // fresh _lastTickAt
  _rescheduleSound();
  notifyListeners();
}
```

> **Session-end edge case:** if the user manually enters overtime during the *very last* rest of the session and then exits, `getReady` would be followed by a `rep` for a non-existent next exercise. Handle by checking whether the session has more reps to do:
>
> ```dart
> // Peek at what the next phase would be if we transitioned from "the phase
> // we came from to get here." Simulate from the remembered source phase.
> final sourcePhase = _rememberCurrentPhaseForPausing;
> final from = _progress.copyWith(phase: sourcePhase);
> final next = _calculateNextState(from);
> if (next == null) {
>   // Session is done — skip getReady entirely.
>   _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
>   _remaining = Duration.zero;
>   _beepScheduler?.cancelAll();
>   notifyListeners();
>   return;
> }
> ```
>
> But the remembered source is set inside `_enterOvertime` to `TimerPhase.overtime`, which defeats this. Fix by capturing the source phase on entry:
>
> Add `TimerPhase _overtimeSourcePhase = TimerPhase.getReady;` to the provider. Set it in `_enterOvertime` before overwriting `_rememberCurrentPhaseForPausing`:
>
> ```dart
> void _enterOvertime({required bool automatic}) {
>   _overtimeSourcePhase = _progress.phase;
>   // ... rest unchanged
> }
> ```
>
> Then use `_overtimeSourcePhase` for the peek in `exitOvertime`.

- [ ] **Step 4: Add session-end guard test**

```dart
test('from final exerciseRest → workoutComplete, not getReady', () {
  final p = SessionStateProvider()..start(_fixture());
  // Put progress on the session's final exerciseRest manually.
  p.debugSetPhase(TimerPhase.exerciseRest);
  // For a fixture with a single workout/exercise with sets=2, finishing the
  // last set yields an exerciseRest that ends the session. Force
  // `currentSet` to the last set via jumpToSet.
  p.jumpToSet(2);
  p.debugSetPhase(TimerPhase.exerciseRest);
  p.requestManualOvertime();
  p.exitOvertime();
  expect(p.phase, TimerPhase.workoutComplete);
});
```

> If this test reveals that the fixture can't reach that state via public API, adjust the fixture or the test to use direct progress manipulation. The key assertion is: on exit, if `_calculateNextState(from-source-phase)` is null, land on `workoutComplete`.

- [ ] **Step 5: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_overtime_test.dart
git commit -m "feat: exitOvertime with session-end guard"
```

---

### Task 11: Ticker increments `_overtimeElapsed`

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add overtime branch at top of ticker body**

In `_startTicker()`'s `Timer.periodic` callback, immediately after the pause/complete early-return, insert:

```dart
if (_progress.phase == TimerPhase.overtime) {
  final now = DateTime.now();
  _overtimeElapsed += now.difference(_lastTickAt!);
  _lastTickAt = now;
  notifyListeners();
  return;
}
```

This bypasses `_advanceByElapsed` entirely while in overtime.

- [ ] **Step 2: Write test**

Append to overtime test file:

```dart
test('ticker increments overtimeElapsed', () async {
  final p = SessionStateProvider()..start(_fixture());
  p.debugSetPhase(TimerPhase.setRest);
  p.requestManualOvertime();
  expect(p.overtimeElapsed, Duration.zero);
  await Future.delayed(const Duration(milliseconds: 1200));
  expect(p.overtimeElapsed.inMilliseconds, greaterThan(800));
});
```

- [ ] **Step 3: Run test — verify pass**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_overtime_test.dart
git commit -m "feat: ticker accumulates overtime elapsed time"
```

---

## Phase 4 — Background auto-trigger

### Task 12: `reconcileAfterBackground` overtime branches

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 1: Write failing tests**

Append to overtime test file:

```dart
group('reconcileAfterBackground with overtime setting', () {
  test('auto-enters overtime when rest expires in background', () {
    final p = SessionStateProvider()
      ..setRestOvertimeOnBackground(true)
      ..start(_fixture());
    p.debugSetPhase(TimerPhase.setRest);
    // Simulate a 30s background gap (rest is 10s, overshoot is 20s).
    // Rewind _lastTickAt by 30s via reflection isn't available, so use
    // a test-only setter:
    p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 30)));
    p.reconcileAfterBackground();
    expect(p.phase, TimerPhase.getReady); // auto-exited on foreground
  });

  test('stays in overtime if manually entered before backgrounding', () {
    final p = SessionStateProvider()..start(_fixture());
    p.debugSetPhase(TimerPhase.setRest);
    p.requestManualOvertime();
    p.debugSetLastTickAt(DateTime.now().subtract(const Duration(seconds: 30)));
    p.reconcileAfterBackground();
    expect(p.phase, TimerPhase.overtime);
    expect(p.overtimeElapsed.inSeconds, greaterThanOrEqualTo(29));
  });
});
```

Add `@visibleForTesting void debugSetLastTickAt(DateTime t) => _lastTickAt = t;` to the provider.

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 3: Update `reconcileAfterBackground`**

```dart
void reconcileAfterBackground() {
  if (_isPaused || _activeSession == null || _lastTickAt == null) return;
  final now = DateTime.now();
  final gap = now.difference(_lastTickAt!);

  // Case 1: already in overtime → accumulate the gap into _overtimeElapsed.
  if (_progress.phase == TimerPhase.overtime) {
    _overtimeElapsed += gap;
    _lastTickAt = now;
    if (_overtimeWasAutomatic) {
      exitOvertime();
    } else {
      notifyListeners();
    }
    return;
  }

  // Case 2: setting on + currently in a setRest/exerciseRest that expired
  //         during the gap → enter overtime, accumulate overshoot.
  final inEligibleRest = _progress.phase == TimerPhase.setRest ||
      _progress.phase == TimerPhase.exerciseRest;
  if (_restOvertimeOnBackground && inEligibleRest && gap >= _remaining) {
    final untilExpiry = _remaining;
    _advanceByElapsed(untilExpiry); // brings _remaining to 0 at phase boundary
    // Do NOT let _advanceByElapsed transition; guard with a check below.
    // If _advanceByElapsed already transitioned past the rest, roll back.
    // (Simpler: handle before calling _advanceByElapsed.)
    _lastTickAt = now;
    final overshoot = gap - untilExpiry;
    _enterOvertime(automatic: true);
    _overtimeElapsed = overshoot;
    exitOvertime(); // we're on foreground, auto-exit immediately
    return;
  }

  // Case 3: standard fast-forward.
  _advanceByElapsed(gap);
  _lastTickAt = now;
  _rescheduleSound();
  notifyListeners();
}
```

> **Design note:** the "guard to stop `_advanceByElapsed` at the rest boundary" is tricky. The simpler approach: detect the condition *before* calling `_advanceByElapsed`, set `_remaining = Duration.zero` directly for the expired rest, and skip straight to `_enterOvertime`. No partial advance is needed because we're not crossing more than one phase boundary — we stop at the first rest expiry.
>
> Revised body for Case 2:
>
> ```dart
> if (_restOvertimeOnBackground && inEligibleRest && gap >= _remaining) {
>   final overshoot = gap - _remaining;
>   _remaining = Duration.zero;
>   _lastTickAt = now;
>   _enterOvertime(automatic: true);
>   _overtimeElapsed = overshoot;
>   exitOvertime(); // auto-exit because we're foregrounded now
>   return;
> }
> ```
>
> Use this simpler form.

- [ ] **Step 4: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_overtime_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_overtime_test.dart
git commit -m "feat: reconcileAfterBackground enters overtime when rest expires in background"
```

---

## Phase 5 — Beep scheduler truncation

### Task 13: Truncate `_calculateFutureBeeps` simulation

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add truncation in the simulation loop**

Inside `_calculateFutureBeeps()`'s `while (true)` loop, after computing `next`, add:

```dart
// If rest-overtime-on-background is enabled and we're about to simulate past
// a setRest/exerciseRest expiry, the real state machine will hold at overtime
// instead. Stop scheduling beeps beyond this point — they would fire after
// the user expected a hold.
if (_restOvertimeOnBackground &&
    (simProgress.phase == TimerPhase.setRest ||
     simProgress.phase == TimerPhase.exerciseRest)) {
  break;
}
```

Place this *before* the existing manual-rep break.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/providers/session_state_provider.dart`

- [ ] **Step 3: Manually verify by reading code path**

Trace through the loop on paper: with setting on and current phase `setRest`, the loop adds beeps for the current setRest (countdown + go), computes `next`, hits the truncation check, breaks. Good.

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: truncate beep simulation at rest boundary when overtime setting is on"
```

---

## Phase 6 — Event log instrumentation

### Task 14: Add event log state + predicates

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add imports**

```dart
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
```

- [ ] **Step 2: Add state fields**

```dart
// Event log — accumulated during an active session, attached to the
// logged Session when the user saves it.
final List<SetEvent> _setEvents = [];
final List<RestEvent> _restEvents = [];

// In-progress drafts. Null when no set/rest is currently open.
_OpenSetDraft? _openSetDraft;
_OpenRestDraft? _openRestDraft;

// Slice tracking: _currentPhaseEnteredAt is updated on every phase
// transition so slices can be attributed to the correct accumulator.
DateTime? _currentPhaseEnteredAt;

// Per-set accumulators (reset when a new set opens).
Duration _currentSetActiveAccum = Duration.zero;
Duration _currentSetRepRestAccum = Duration.zero;
```

Add private draft classes at the bottom of the file:

```dart
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
  final RestKind kind;
  final int workoutIndex;
  final int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final Duration plannedDuration;
  _OpenRestDraft({
    required this.kind,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.plannedDuration,
  });
}
```

- [ ] **Step 3: Add helper predicates**

```dart
bool _isRestPhase(TimerPhase p) =>
    p == TimerPhase.getReady ||
    p == TimerPhase.setRest ||
    p == TimerPhase.exerciseRest ||
    p == TimerPhase.overtime ||
    p == TimerPhase.paused;

RestKind _kindForPhase(TimerPhase p) {
  switch (p) {
    case TimerPhase.getReady:
      return RestKind.getReady;
    case TimerPhase.setRest:
      return RestKind.setRest;
    case TimerPhase.exerciseRest:
      return RestKind.exerciseRest;
    case TimerPhase.overtime:
      return RestKind.overtime;
    case TimerPhase.paused:
      return RestKind.paused;
    default:
      throw StateError('Not a rest phase: $p');
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: scaffold event log state and helpers"
```

---

### Task 15: `_onPhaseTransition` dispatcher

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Add draft open/close helpers**

```dart
void _openSetDraft(SessionProgress p) {
  _openSetDraft = _OpenSetDraft(
    workoutIndex: p.workoutIndex,
    exerciseIndex: p.exerciseIndex,
    setIndex: p.currentSet,
    startAt: DateTime.now(),
  );
  _currentSetActiveAccum = Duration.zero;
  _currentSetRepRestAccum = Duration.zero;
}

void _closeSetDraft({required int repsCompleted}) {
  final d = _openSetDraft;
  if (d == null) return;
  _setEvents.add(SetEvent(
    workoutIndex: d.workoutIndex,
    exerciseIndex: d.exerciseIndex,
    setIndex: d.setIndex,
    startAt: d.startAt,
    endAt: DateTime.now(),
    activeTime: _currentSetActiveAccum,
    interRepRestTime: _currentSetRepRestAccum,
    repsCompleted: repsCompleted,
  ));
  _openSetDraft = null;
  _currentSetActiveAccum = Duration.zero;
  _currentSetRepRestAccum = Duration.zero;
}

void _openRestDraft(RestKind kind, SessionProgress p) {
  final planned = (kind == RestKind.overtime || kind == RestKind.paused)
      ? Duration.zero
      : _getDurationForPhase(p);
  _openRestDraft = _OpenRestDraft(
    kind: kind,
    workoutIndex: p.workoutIndex,
    exerciseIndex: p.exerciseIndex,
    setIndex: (kind == RestKind.setRest) ? p.currentSet : null,
    startAt: DateTime.now(),
    plannedDuration: planned,
  );
}

void _closeRestDraft() {
  final d = _openRestDraft;
  if (d == null) return;
  final now = DateTime.now();
  final actual = now.difference(d.startAt);
  _restEvents.add(RestEvent(
    kind: d.kind,
    workoutIndex: d.workoutIndex,
    exerciseIndex: d.exerciseIndex,
    setIndex: d.setIndex,
    startAt: d.startAt,
    endAt: now,
    plannedDuration: d.plannedDuration,
    actualDuration: actual,
    overtimeDuration: d.kind == RestKind.overtime ? actual : Duration.zero,
  ));
  _openRestDraft = null;
}

void _discardDrafts() {
  _openSetDraft = null;
  _openRestDraft = null;
  _currentSetActiveAccum = Duration.zero;
  _currentSetRepRestAccum = Duration.zero;
  _currentPhaseEnteredAt = null;
}
```

- [ ] **Step 2: Add the dispatcher**

```dart
/// Central hook for all phase transitions. Updates slice accumulators,
/// closes drafts for the phase being exited, and opens drafts for the
/// phase being entered. Must be called with the NEW progress already
/// committed to `_progress`? No — call it BEFORE committing so we can
/// read the old phase from `_progress` and use the `to` argument for new.
/// Keep signature: (from, to, newProgress).
void _onPhaseTransition(TimerPhase from, TimerPhase to, SessionProgress newProgress) {
  final now = DateTime.now();

  // 1. Slice accumulation: attribute the elapsed time since _currentPhaseEnteredAt
  //    to the correct set-level accumulator based on the phase being exited.
  if (_currentPhaseEnteredAt != null) {
    final slice = now.difference(_currentPhaseEnteredAt!);
    if (from == TimerPhase.rep) {
      _currentSetActiveAccum += slice;
    } else if (from == TimerPhase.repRest) {
      _currentSetRepRestAccum += slice;
    }
  }
  _currentPhaseEnteredAt = now;

  // 2. Close rest draft if we're leaving a rest-like phase.
  if (_isRestPhase(from)) _closeRestDraft();

  // 3. Close set draft if we're leaving `rep` for a non-inter-rep destination.
  if (from == TimerPhase.rep &&
      (to == TimerPhase.setRest ||
       to == TimerPhase.exerciseRest ||
       to == TimerPhase.workoutComplete ||
       to == TimerPhase.overtime || // possible via manual from rep? no, guard prevents. keep for safety.
       to == TimerPhase.paused)) {
    // For paused-from-rep: we want the set to span the pause, not close.
    // Handle that by NOT closing on paused.
    if (to != TimerPhase.paused) {
      _closeSetDraft(repsCompleted: _progress.currentRep);
    }
  }

  // 4. Open set draft if we're entering `rep` to start a new set.
  //    (rep coming from getReady, setRest, exerciseRest — NOT repRest or paused.)
  if (to == TimerPhase.rep &&
      from != TimerPhase.repRest &&
      from != TimerPhase.paused) {
    _openSetDraft(newProgress);
  }

  // 5. Open rest draft if we're entering a rest phase.
  if (_isRestPhase(to)) _openRestDraft(_kindForPhase(to), newProgress);
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: add _onPhaseTransition event log dispatcher"
```

---

### Task 16: Wire dispatcher into `_advanceByElapsed` and `start`

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: Update `start()`**

After setting `_progress = ...getReady`, call the dispatcher with `from = workoutComplete` (the "prior" phase on a fresh start):

```dart
_onPhaseTransition(TimerPhase.workoutComplete, TimerPhase.getReady, _progress);
```

Also clear prior event state:

```dart
_setEvents.clear();
_restEvents.clear();
_discardDrafts();
```

Place at the top of `start()` before the deep-copy assignment.

- [ ] **Step 2: Update `_advanceByElapsed` transition loop**

Replace the body of the `while (_remaining <= Duration.zero)` loop so each `_progress = next` is preceded by a dispatcher call:

```dart
while (_remaining <= Duration.zero) {
  if (_activeSession != null) {
    final exercise = _activeSession!
        .workouts[_progress.workoutIndex].exercises[_progress.exerciseIndex];
    if (exercise.type == ExerciseType.manual &&
        _progress.phase == TimerPhase.rep) {
      _remaining = Duration.zero;
      return;
    }
  }
  final next = _calculateNextState(_progress);
  if (next == null) {
    _onPhaseTransition(_progress.phase, TimerPhase.workoutComplete, _progress);
    _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
    _remaining = Duration.zero;
    return;
  }
  _onPhaseTransition(_progress.phase, next.phase, next);
  _remaining = _getDurationForPhase(next) + _remaining;
  _progress = next;
}
```

- [ ] **Step 3: Run existing tests to catch regressions**

Run: `flutter test test/providers/`

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: dispatch phase transitions from _advanceByElapsed and start"
```

---

### Task 17: Wire dispatcher into `pause`/`resume` with tests

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Create: `test/providers/session_state_provider_event_log_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/providers/session_state_provider_event_log_test.dart`:

```dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Session _fixture() => Session(
      id: 's',
      title: 't',
      label: 'l',
      workouts: [
        Workout(
          id: 'w',
          title: 'w',
          label: 'w',
          exercises: [
            Exercise(
              id: 'e',
              title: 'e',
              type: ExerciseType.fixedDuration,
              sets: 1,
              timeBetweenSets: 0,
              activeTime: 5,
              timePerRep: 0,
              timeBetweenReps: 0,
              load: 0,
            ),
          ],
          timeBetweenExercises: 0,
        ),
      ],
    );

void main() {
  test('pause during setRest splits the rest event', () {
    final p = SessionStateProvider()..start(_fixture());
    p.debugSetPhase(TimerPhase.setRest);
    // Let 100ms elapse in setRest, then pause for 100ms, then resume.
    // Since actual wall-clock elapsed matters, we use Future.delayed.
    // NOTE: this test is time-sensitive.
    expect(p.debugRestEventCount(), 1); // setRest just opened
    p.pause();
    expect(p.debugRestEventCount(), 2); // first setRest closed + paused open? No — paused is a draft.
    // Revisit: assert on finalized events after full flow.
  });
}
```

> **Implementer note:** testing event counts precisely requires test hooks. Add:
>
> ```dart
> @visibleForTesting
> int debugRestEventCount() => _restEvents.length;
> @visibleForTesting
> List<RestKind> debugRestEventKinds() => _restEvents.map((e) => e.kind).toList();
> ```
>
> Refine the test to cover: pause during setRest, then resume, then directly force transition out of setRest. Verify that `debugRestEventKinds()` contains `[setRest, paused, setRest]` (the split pattern).

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/providers/session_state_provider_event_log_test.dart`

- [ ] **Step 3: Update `pause()`**

```dart
void pause() {
  if (_isPaused) return;
  _isPaused = true;
  _lastTickAt = null;

  // Flush any partial rep/repRest slice into the set accumulators BEFORE
  // the dispatcher runs, so the "from" phase's slice is attributed before
  // we switch phase to paused.
  if (_currentPhaseEnteredAt != null) {
    final slice = DateTime.now().difference(_currentPhaseEnteredAt!);
    if (_progress.phase == TimerPhase.rep) {
      _currentSetActiveAccum += slice;
    } else if (_progress.phase == TimerPhase.repRest) {
      _currentSetRepRestAccum += slice;
    }
    _currentPhaseEnteredAt = DateTime.now();
  }

  _rememberCurrentPhaseForPausing = _progress.phase;
  _onPhaseTransition(_progress.phase, TimerPhase.paused, _progress);
  _progress = _progress.copyWith(phase: TimerPhase.paused);
  _rescheduleSound();
  notifyListeners();
}
```

- [ ] **Step 4: Update `resume()`**

```dart
void resume() {
  if (!_isPaused) return;
  _isPaused = false;
  final target = _progress.copyWith(phase: _rememberCurrentPhaseForPausing);
  _onPhaseTransition(TimerPhase.paused, target.phase, target);
  _progress = target;
  _startTicker();
  _rescheduleSound();
  notifyListeners();
}
```

- [ ] **Step 5: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_event_log_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_event_log_test.dart
git commit -m "feat: pause/resume split rest events into multiple segments"
```

---

### Task 18: Wire dispatcher into `advanceManually`, jumps, `_enterOvertime`, `exitOvertime`, `reset`

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

- [ ] **Step 1: `advanceManually`**

Wrap phase assignments with dispatcher calls. Before:

```dart
_progress = _progress.copyWith(phase: TimerPhase.setRest);
```

After:

```dart
final next = _progress.copyWith(phase: TimerPhase.setRest);
_onPhaseTransition(_progress.phase, next.phase, next);
_progress = next;
```

Same for the `exerciseRest` branch.

- [ ] **Step 2: `jumpToWorkout` / `jumpToExercise` / `jumpToSet`**

Before modifying `_progress`, call `_discardDrafts()`. These are navigational actions that should not produce events.

```dart
_discardDrafts();
// ... existing jump logic ...
// After setting _progress, open fresh drafts for the landing phase:
_onPhaseTransition(TimerPhase.workoutComplete, _progress.phase, _progress);
```

The "from = workoutComplete" convention signals "no prior phase slice to attribute."

- [ ] **Step 3: `_enterOvertime`**

Add a dispatcher call before committing the new phase:

```dart
void _enterOvertime({required bool automatic}) {
  _overtimeSourcePhase = _progress.phase;
  _overtimeElapsed = Duration.zero;
  _overtimeWasAutomatic = automatic;
  final next = _progress.copyWith(phase: TimerPhase.overtime);
  _onPhaseTransition(_progress.phase, next.phase, next);
  _progress = next;
  _remaining = Duration.zero;
  _rememberCurrentPhaseForPausing = TimerPhase.overtime;
  _rescheduleSound();
  notifyListeners();
}
```

- [ ] **Step 4: `exitOvertime`**

Add the dispatcher call before the phase change:

```dart
// Session-end branch:
if (next == null) {
  _onPhaseTransition(TimerPhase.overtime, TimerPhase.workoutComplete, _progress);
  _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
  // ...
}
// Normal exit branch:
final target = _progress.copyWith(phase: TimerPhase.getReady);
_onPhaseTransition(TimerPhase.overtime, target.phase, target);
_progress = target;
_remaining = const Duration(seconds: 10);
// ...
```

- [ ] **Step 5: `reset()`**

Clear everything:

```dart
void reset() {
  _ticker?.cancel();
  _lastTickAt = null;
  _beepScheduler?.cancelAll();
  _activeSession = null;
  _setEvents.clear();
  _restEvents.clear();
  _discardDrafts();
  // ... rest unchanged
}
```

- [ ] **Step 6: Run full test suite**

Run: `flutter test test/providers/`

- [ ] **Step 7: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: dispatch phase transitions from all provider entry points"
```

---

### Task 19: `_computeSummary` + `finalizeSession` + fixture test

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_event_log_test.dart`

- [ ] **Step 1: Implement `_computeSummary` and `finalizeSession`**

```dart
SessionSummary _computeSummary() {
  Duration sum(Iterable<Duration> ds) =>
      ds.fold(Duration.zero, (a, b) => a + b);

  final firstStart = _setEvents.isNotEmpty
      ? _setEvents.first.startAt
      : (_restEvents.isNotEmpty ? _restEvents.first.startAt : DateTime.now());
  final lastEnd = _setEvents.isNotEmpty
      ? _setEvents.last.endAt
      : (_restEvents.isNotEmpty ? _restEvents.last.endAt : DateTime.now());

  return SessionSummary(
    totalTime: lastEnd.difference(firstStart),
    activeTime: sum(_setEvents.map((e) => e.activeTime)),
    interRepRestTime: sum(_setEvents.map((e) => e.interRepRestTime)),
    setRestTime: sum(_restEvents
        .where((e) => e.kind == RestKind.setRest)
        .map((e) => e.actualDuration)),
    exerciseRestTime: sum(_restEvents
        .where((e) => e.kind == RestKind.exerciseRest)
        .map((e) => e.actualDuration)),
    getReadyTime: sum(_restEvents
        .where((e) => e.kind == RestKind.getReady)
        .map((e) => e.actualDuration)),
    overtime: sum(_restEvents
        .where((e) => e.kind == RestKind.overtime)
        .map((e) => e.overtimeDuration)),
    pausedTime: sum(_restEvents
        .where((e) => e.kind == RestKind.paused)
        .map((e) => e.actualDuration)),
  );
}

/// Closes any still-open drafts, computes the summary, and returns a Session
/// copy with event lists and summary attached. Called before persistence.
Session? finalizeSession() {
  if (_activeSession == null) return null;

  // Flush any open drafts (e.g. user ended session mid-rest).
  if (_openRestDraft != null) _closeRestDraft();
  if (_openSetDraft != null) {
    _closeSetDraft(repsCompleted: _progress.currentRep);
  }

  final summary = _computeSummary();
  return _activeSession!.copyWith(
    setEvents: List.unmodifiable(_setEvents),
    restEvents: List.unmodifiable(_restEvents),
    summary: summary,
  );
}
```

- [ ] **Step 2: Write fixture test**

Append to `session_state_provider_event_log_test.dart`:

```dart
test('finalizeSession with fixed-duration fixture produces expected summary', () async {
  final p = SessionStateProvider()..start(_fixture());
  // fixture: 1 exercise, 1 set, activeTime=5, no rests
  // Manually drive the state machine via debug hook + short waits.
  // Short version: assert finalized session has non-null summary and
  // activeTime matches the set event.
  await Future.delayed(const Duration(milliseconds: 50));
  final finalized = p.finalizeSession();
  expect(finalized, isNotNull);
  expect(finalized!.summary, isNotNull);
  expect(finalized.setEvents, isNotNull);
});
```

> This test is a smoke test for the wiring. A more exhaustive hand-calculated test is difficult without richer debug hooks; defer to manual verification (Task 26).

- [ ] **Step 3: Run tests — verify pass**

Run: `flutter test test/providers/session_state_provider_event_log_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_event_log_test.dart
git commit -m "feat: computeSummary and finalizeSession for event log persistence"
```

---

## Phase 7 — Persistence

### Task 20: Finalize session before log + update Supabase sync

**Files:**
- Modify: `lib/providers/session_log_provider.dart`
- Modify: `lib/services/supabase_sync_service.dart`
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart` (if it's the caller)

- [ ] **Step 1: Locate the caller of `refreshSelectedSessions`**

Run: `rg "refreshSelectedSessions" lib/ --glob "*.dart"`

Identify the widget/provider that calls it at session end (likely in `session_active_screen.dart` or a completion dialog). The caller currently passes the raw active session — change it to call `sessionStateProvider.finalizeSession()` and pass the returned value instead.

- [ ] **Step 2: Update the caller**

At the call site:

```dart
final finalized = context.read<SessionStateProvider>().finalizeSession();
if (finalized == null) return;
await context.read<SessionLogProvider>().refreshSelectedSessions(finalized);
```

- [ ] **Step 3: Update `SupabaseSyncService.uploadSession`**

Extend the upsert payload in `uploadSession` to include the new fields:

```dart
await supabase.from('user_sessions').upsert({
  'id': session.id,
  'user_id': userId,
  'title': session.title,
  'label': session.label,
  'description': session.description,
  'completed_at': session.completedAt?.toIso8601String(),
  'workouts': session.workouts.map((w) => w.toJson()).toList(),
  'set_events': session.setEvents?.map((e) => e.toJson()).toList(),
  'rest_events': session.restEvents?.map((e) => e.toJson()).toList(),
  'summary': session.summary?.toJson(),
  'updated_at': DateTime.now().toIso8601String(),
});
```

Also update `fetchUserSessions`: `Session.fromJson` handles the new keys automatically if the response includes them, but the `json` keys coming from Supabase use snake_case (`set_events`, `rest_events`). Add a translation layer:

```dart
return Session.fromJson({
  ...json as Map<String, dynamic>,
  'userId': json['user_id'],
  'setEvents': json['set_events'],
  'restEvents': json['rest_events'],
  'summary': json['summary'],
});
```

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/services/supabase_sync_service.dart lib/providers/session_log_provider.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/providers/session_log_provider.dart lib/services/supabase_sync_service.dart lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat: persist event log and summary with logged sessions"
```

---

## Phase 8 — UI

### Task 21: Overtime in timer display + phase label

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`

- [ ] **Step 1: Read the current timer display code** (lines ~290-335)

- [ ] **Step 2: Add an `overtime` branch**

In the switch/if ladder that picks the timer color and text, add:

```dart
// inside whatever function computes `timerColor`, `timerValue`:
if (phase == TimerPhase.overtime) {
  timerColor = colorScheme.secondary;
  timerValue = formatDuration(sessionState.overtimeElapsed);
}
```

In the phase label builder:

```dart
TimerPhase.overtime => Text(
    'overtime',
    style: TextStyle(color: colorScheme.secondary),
  ),
```

- [ ] **Step 3: Manual verification plan**

Cannot easily widget-test this without a full SessionStateProvider fixture. Verified in Task 26 manual pass.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat: display overtime count-up timer in secondary color"
```

---

### Task 22: Pause button transform + long-press + widget test

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`
- Create: `test/widget/pause_button_overtime_test.dart` *(directory may need creating)*

- [ ] **Step 1: Add long-press gesture and overtime branch**

Locate the pause button (around line 341). Wrap or replace its existing `IconButton`/`GestureDetector` with:

```dart
Consumer<SessionStateProvider>(
  builder: (context, state, _) {
    final phase = state.phase;
    final isOvertime = phase == TimerPhase.overtime;
    final canLongPress = phase == TimerPhase.setRest ||
        phase == TimerPhase.exerciseRest ||
        phase == TimerPhase.getReady;

    IconData icon;
    Color color = Theme.of(context).iconTheme.color ?? Colors.white;
    VoidCallback onTap;

    if (isOvertime) {
      icon = Icons.skip_next;
      color = Theme.of(context).colorScheme.secondary;
      onTap = state.exitOvertime;
    } else if (state.isPaused) {
      icon = Icons.play_arrow;
      onTap = state.resume;
    } else {
      icon = Icons.pause;
      onTap = state.pause;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: canLongPress
          ? () => state.requestManualOvertime()
          : null,
      child: Icon(icon, color: color, size: 48),
    );
  },
);
```

- [ ] **Step 2: Write widget test**

Create `test/widget/pause_button_overtime_test.dart`:

```dart
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Import the session_active_screen or just extract the pause button to a
// small widget testable in isolation. Depending on structure, you may need
// to factor the button out into `PauseOvertimeButton` to make this testable.

void main() {
  testWidgets('long-press from setRest triggers overtime', (tester) async {
    // If the button isn't extractable, this test is skipped and verified
    // manually in Task 26.
  }, skip: 'Extract pause button into its own widget first if needed');
}
```

> **Pragmatic note:** widget testing the pause button in situ inside `session_active_screen.dart` is hard (lots of provider wiring). Two options:
>
> **A.** Extract the button into a new `lib/presentation/screens/session_flow/pause_overtime_button.dart` widget that takes a `SessionStateProvider` via provider lookup. Then widget-test it against a mock provider.
>
> **B.** Skip widget testing, rely on manual verification.
>
> Prefer A if it's a small extraction. If the button is deeply coupled to surrounding layout (Row/Column with shared paddings), prefer B to avoid scope creep.

- [ ] **Step 3: Run tests or manual verification**

Run: `flutter test test/widget/` (if extracted) or run the app and tap/long-press manually.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart test/widget/
git commit -m "feat: pause button transforms to overtime skip on long-press"
```

---

### Task 23: Grey out jump buttons during overtime

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`
- Possibly: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart`

- [ ] **Step 1: Locate jump button widgets**

Run: `rg "jumpToSet|jumpToExercise|jumpToWorkout" lib/presentation --glob "*.dart"`

- [ ] **Step 2: Wrap each with an overtime-aware disabled state**

For each jump button (prev/next exercise, set +/−):

```dart
final isOvertime = context.select<SessionStateProvider, bool>(
  (s) => s.phase == TimerPhase.overtime,
);
return IconButton(
  onPressed: isOvertime ? null : () => state.jumpToSet(newIndex),
  icon: Icon(
    Icons.skip_previous,
    color: isOvertime
        ? Theme.of(context).disabledColor
        : Theme.of(context).iconTheme.color,
  ),
);
```

Adjust per actual widget types in the file.

- [ ] **Step 3: Manual verification**

Run the app, enter overtime via long-press, confirm buttons visibly grey and non-responsive.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/session_flow/
git commit -m "feat: grey out and disable jump buttons during overtime"
```

---

### Task 24: Settings drawer toggle + provider sync wiring

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart`

- [ ] **Step 1: Add `SwitchListTile` in `SettingsDrawer`**

Near the existing sound-mode dropdown in the `SettingsDrawer` class:

```dart
Consumer<SettingsProvider>(
  builder: (context, settings, _) => SwitchListTile(
    title: const Text('Extend rest when backgrounded'),
    subtitle: const Text(
      'Keep rest timers running when you leave the app. '
      'Tap the skip button to continue when you return.',
    ),
    value: settings.restOvertimeOnBackground,
    onChanged: (v) {
      settings.setRestOvertimeOnBackground(v);
      context.read<SessionStateProvider>().setRestOvertimeOnBackground(v);
    },
  ),
),
```

- [ ] **Step 2: Sync setting on app startup**

In `root_screen.dart`'s `initState` or wherever `SoundMode` is currently synced from `SettingsProvider` to `SessionStateProvider`, add the parallel sync for `restOvertimeOnBackground`:

```dart
context.read<SessionStateProvider>()
  .setRestOvertimeOnBackground(
    context.read<SettingsProvider>().restOvertimeOnBackground,
  );
```

- [ ] **Step 3: Run app manually**

Run: `flutter run` on simulator. Toggle the setting. Verify it persists across app restart.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/root_screen.dart
git commit -m "feat: settings drawer toggle for rest overtime on background"
```

---

## Phase 9 — Supabase migration

### Task 25: Add JSONB columns to Supabase schema

**Files:**
- Create: `supabase/migrations/<timestamp>_session_telemetry.sql` (path depends on how existing migrations are stored — investigate first)

- [ ] **Step 1: Find existing Supabase migration location**

Run: `ls supabase/ 2>/dev/null ; rg "user_sessions" --glob "*.sql"`

If the project uses the Supabase CLI, add a new migration via `supabase migration new session_telemetry`. If migrations are applied manually via the dashboard, draft the SQL here for the user to run.

- [ ] **Step 2: Draft migration SQL**

```sql
ALTER TABLE user_sessions
  ADD COLUMN IF NOT EXISTS set_events JSONB,
  ADD COLUMN IF NOT EXISTS rest_events JSONB,
  ADD COLUMN IF NOT EXISTS summary JSONB;
```

- [ ] **Step 3: Apply (or hand to user for application)**

If CLI: `supabase db push` on a dev project first.
If manual: deliver the SQL to the user with instructions.

- [ ] **Step 4: Verify round-trip**

Upload a test session from the app, query the row in Supabase SQL editor, confirm the three columns populate with JSON.

- [ ] **Step 5: Commit migration file if applicable**

```bash
git add supabase/migrations/
git commit -m "chore: add session telemetry JSONB columns to user_sessions"
```

---

## Phase 10 — Validation

### Task 26: Manual end-to-end verification

**Files:** none

- [ ] **Step 1: Manual test plan**

Run `flutter run` on device/simulator. Walk through:

1. **Happy path — no overtime.** Start a session, complete a set normally, verify logged session shows in profile with a summary (once a summary view exists; otherwise verify via database).
2. **Manual overtime during setRest.** Start a session, reach a setRest, long-press the pause button. Verify: icon flips to skip-next, color becomes secondary, timer counts up. Tap skip. Verify: transitions to getReady with 10s remaining. Verify getReady beeps and then proceeds normally.
3. **Manual overtime during getReady.** Long-press during getReady. Verify: enters overtime. Tap skip. Verify: getReady restarts from 10s.
4. **Long-press is no-op during rep.** Long-press pause button during a rep. Verify: nothing happens.
5. **Long-press is no-op during repRest.** Set up a timedReps exercise with timeBetweenReps>0. Long-press during repRest. Verify: nothing happens.
6. **Auto overtime on background (setting on).** Toggle "Extend rest when backgrounded" on. Start a session, reach setRest, lock the phone. Wait > plannedDuration. Unlock. Verify: session transitioned to getReady automatically (or skip to workoutComplete if it was the last rest), not fast-forwarded past the next set.
7. **Manual overtime survives backgrounding.** Long-press into overtime. Lock phone. Wait. Unlock. Verify: still in overtime with `overtimeElapsed` reflecting the gap.
8. **Jump buttons disabled in overtime.** Long-press into overtime, verify set +/- and prev/next exercise icons are greyed and unresponsive.
9. **Session log persistence.** Complete a session containing at least one manual overtime. Verify the logged session JSON file (via `SessionLogger` path, see `session_log.json` in app documents dir) contains non-null `setEvents`, `restEvents`, and `summary`. Optional: verify Supabase row after a sync.
10. **Beep truncation.** With setting on, start a session with multiple exercises, reach setRest, background. Listen for beeps: should hear the countdown at setRest end, then silence. No beeps for what would have been the next set's getReady.

- [ ] **Step 2: If any step fails, file the bug in a new task and fix before merging**

- [ ] **Step 3: Final commit (if any small fixes)**

```bash
git add <fixes>
git commit -m "fix: address manual verification issues"
```

---

## Completion checklist

- [ ] All unit tests pass: `flutter test`
- [ ] Analyzer clean: `flutter analyze`
- [ ] Manual test plan (Task 26) fully passed
- [ ] Supabase migration applied and verified (Task 25)
- [ ] Spec's open questions all resolved (session save hook ✓, settings drawer location ✓, Supabase tooling ✓)
- [ ] Commits squashed or merged per project convention

## Post-merge follow-ups (out of scope for this plan)

- Session summary UI (dashboard widget showing total time / breakdown)
- Historical overtime analytics across sessions
- Per-exercise overtime preference overrides
- Widget test for pause button (requires extracting the button into its own file)
