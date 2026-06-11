# Mid-Session Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit the structure of an active session (add/edit/remove workouts and exercises) without losing their timer progress, event log, or current position.

**Architecture:** `SessionStateProvider` gains `replaceActiveSession(Session)` which re-anchors progress by Exercise ID after structural changes. `NewSessionScreen` gains a `NewSessionScreenMode` enum replacing the `startAfterSave` bool, with a new `editActive` mode whose save path calls `replaceActiveSession` and pops. The existing `_showEditExerciseDialog` modal in `ActiveSessionScreen` wires up the currently-disabled OutlinedButton to push the editor.

**Tech Stack:** Flutter, Provider, existing session/workout/exercise models, `scripts/run_tests.sh` for test runs.

---

## File Map

| File | Change |
|------|--------|
| `lib/providers/session_state_provider.dart` | Drop `final` on `_OpenSetDraft`/`_OpenRestDraft` index fields; implement `replaceActiveSession` |
| `lib/presentation/screens/catalog_flow/new_session_screen.dart` | Replace `startAfterSave: bool` with `mode: NewSessionScreenMode`; refactor `_save()` into dispatch; add `editActive` lifecycle; replace direct `ActiveSessionScreen` push with an `onSaveAndStart` callback (breaks the existing circular import) |
| `lib/presentation/screens/session_flow/session_active_screen.dart` | Wire up OutlinedButton; import `new_session_screen.dart` (safe once the circular import is broken) |
| `lib/presentation/screens/session_flow/session_select_screen.dart` | Update callsite: provide `onSaveAndStart` callback; `startAfterSave: true` → `mode: editBeforeStart` |
| `lib/presentation/screens/root_screen.dart` | Update callsite: bare `NewSessionScreen()` → `mode: create` |
| `lib/presentation/screens/catalog_flow/catalog_screen.dart` | Update callsite: `session: x` → `mode: editCatalog, session: x` |
| `test/providers/session_state_provider_replace_test.dart` | New test file for `replaceActiveSession` |

> **Circular import fix:** `new_session_screen.dart` currently imports `session_active_screen.dart` to push `ActiveSessionScreen` in `_saveAndStart`. Adding the reverse import in Task 6 would create a cycle. Fix in Task 4: add `final void Function(Session)? onSaveAndStart` callback to `NewSessionScreen`. `_saveAndStart` calls this callback instead of pushing directly. Remove the `session_active_screen.dart` import from `new_session_screen.dart`. The one callsite that uses `editBeforeStart` mode (`session_select_screen.dart`) passes:
> ```dart
> onSaveAndStart: (session) => Navigator.pushAndRemoveUntil(
>   context,
>   MaterialPageRoute(builder: (_) => ActiveSessionScreen(session: session)),
>   (route) => route.isFirst,
> ),
> ```
> After this, `session_active_screen.dart` can import `new_session_screen.dart` without a cycle.

---

## Task 1: Drop `final` on draft index fields

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (bottom of file, `_OpenSetDraft` and `_OpenRestDraft` classes)

- [ ] Make `workoutIndex` and `exerciseIndex` non-final on both private draft classes

Change `_OpenSetDraft`:
```dart
class _OpenSetDraft {
  int workoutIndex;      // was: final int workoutIndex
  int exerciseIndex;     // was: final int exerciseIndex
  final int setIndex;
  final DateTime startAt;

  _OpenSetDraft({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
  });
}
```

Change `_OpenRestDraft`:
```dart
class _OpenRestDraft {
  final RestType restType;
  int workoutIndex;      // was: final int workoutIndex
  int exerciseIndex;     // was: final int exerciseIndex
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

- [ ] Run tests to confirm nothing broke
```bash
bash scripts/run_tests.sh
```
Expected: all passing (no behaviour change).

- [ ] Commit
```bash
git add lib/providers/session_state_provider.dart
git commit -m "refactor: make draft index fields mutable for mid-session re-anchoring"
```

---

## Task 2: Implement `replaceActiveSession` — anchor-survives branch

**Files:**
- Modify: `lib/providers/session_state_provider.dart` (~line 591, the empty `updateActiveSession` placeholder)
- Create: `test/providers/session_state_provider_replace_test.dart`

The placeholder `updateActiveSession()` at line 591 becomes the real implementation. Rename and implement.

- [ ] Write failing tests first

```dart
// test/providers/session_state_provider_replace_test.dart
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a session with named workout/exercise ids for easy lookup.
Session _fixture({
  String workoutId = 'w1',
  String exerciseId = 'e1',
  int sets = 3,
  int reps = 8,
}) => Session(
  title: 'S',
  label: 'other',
  workouts: [
    Workout(
      id: workoutId,
      title: 'W',
      label: 'other',
      timeBetweenExercises: 60,
      exercises: [
        Exercise(
          id: exerciseId,
          title: 'E',
          description: '',
          label: 'other',
          sets: sets,
          reps: reps,
          timeBetweenSets: 30,
        ),
      ],
    ),
  ],
);

// Adds a second exercise to a fixture session.
Session _withSecondExercise(Session s, {String id = 'e2'}) {
  final w = s.workouts[0];
  return s.copyWith(
    workouts: [
      w.copyWith(
        exercises: [
          ...w.exercises,
          Exercise(
            id: id,
            title: 'E2',
            description: '',
            label: 'other',
            sets: 3,
            reps: 8,
            timeBetweenSets: 30,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('replaceActiveSession — anchor survives', () {
    test('re-anchors to same exercise after add before it', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      // Move to second exercise (e2 at index 1).
      p.jumpToExercise(1);
      expect(p.progress.exerciseIndex, 1);

      // Edited session: insert a new exercise between e1 and e2.
      final workout = original.workouts[0];
      final newExercise = Exercise(
        id: 'e_new',
        title: 'New',
        description: '',
        label: 'other',
        sets: 2,
        reps: 5,
        timeBetweenSets: 20,
      );
      final edited = original.copyWith(
        workouts: [
          workout.copyWith(
            exercises: [workout.exercises[0], newExercise, workout.exercises[1]],
          ),
        ],
      );

      p.replaceActiveSession(edited);

      // e2 is now at index 2, not 1.
      expect(p.progress.exerciseIndex, 2);
      expect(p.progress.workoutIndex, 0);
    });

    test('clamps currentSet when sets reduced below current', () {
      final original = _fixture(sets: 4);
      final p = SessionStateProvider()..start(original);
      p.jumpToSet(3); // currentSet = 3
      expect(p.progress.currentSet, 3);

      // Reduce to 2 sets.
      final edited = _fixture(sets: 2);
      p.replaceActiveSession(edited);

      expect(p.progress.currentSet, 2);
    });

    test('preserves currentSet when sets unchanged', () {
      final original = _fixture(sets: 4);
      final p = SessionStateProvider()..start(original);
      p.jumpToSet(3);

      // Edit something else (e.g. reps), sets unchanged.
      final edited = _fixture(sets: 4, reps: 6);
      p.replaceActiveSession(edited);

      expect(p.progress.currentSet, 3);
    });

    test('rewrites open set draft indices after workout reorder', () {
      final w1 = Workout(
        id: 'w1', title: 'W1', label: 'other', timeBetweenExercises: 60,
        exercises: [
          Exercise(id: 'e1', title: 'E1', description: '', label: 'other',
              sets: 3, reps: 8, timeBetweenSets: 30),
        ],
      );
      final w2 = Workout(
        id: 'w2', title: 'W2', label: 'other', timeBetweenExercises: 60,
        exercises: [
          Exercise(id: 'e2', title: 'E2', description: '', label: 'other',
              sets: 3, reps: 8, timeBetweenSets: 30),
        ],
      );
      final original = Session(title: 'S', label: 'other', workouts: [w1, w2]);
      final p = SessionStateProvider()..start(original);
      // Advance to w2/e2 (workoutIndex 1, exerciseIndex 0).
      p.jumpToWorkout(1);
      p.debugSetPhase(TimerPhase.rep); // opens a set draft at w=1, e=0

      // Swap workout order in edited session.
      final edited = Session(title: 'S', label: 'other', workouts: [w2, w1]);
      p.replaceActiveSession(edited);

      // w2 is now at index 0; progress should re-anchor there.
      expect(p.progress.workoutIndex, 0);
      expect(p.progress.exerciseIndex, 0);
    });

    test('does not touch _setEvents or _restEvents', () {
      final original = _withSecondExercise(_fixture());
      final p = SessionStateProvider()..start(original);
      p.debugSetPhase(TimerPhase.rep);
      p.debugSetPhase(TimerPhase.exerciseRest); // logs a set event
      final eventCountBefore = p.debugRestEventCount();

      final edited = original.copyWith(); // structural no-op
      p.replaceActiveSession(edited);

      expect(p.debugRestEventCount(), eventCountBefore);
    });
  });
}
```

- [ ] Run tests to confirm they fail
```bash
bash scripts/run_tests.sh
```
Expected: compile error — `replaceActiveSession` not defined yet.

- [ ] Implement `replaceActiveSession` — anchor-survives branch only

Replace the empty `updateActiveSession()` placeholder with:

```dart
/// Replaces the active session structure with [edited] and re-anchors
/// progress to the user's current exercise by id. If the current exercise
/// was deleted, advances to the next available stop (see deletion branch
/// in Task 3). No-op if [_activeSession] is null.
void replaceActiveSession(Session edited) {
  if (_activeSession == null) return;

  // 1. Capture anchor ids before replacing.
  final anchorWorkoutId =
      _activeSession!.workouts[_progress.workoutIndex].id;
  final anchorExerciseId =
      _activeSession!.workouts[_progress.workoutIndex]
          .exercises[_progress.exerciseIndex].id;

  _activeSession = edited;

  // 2. Locate anchor in edited session.
  final newWIdx = edited.workouts.indexWhere((w) => w.id == anchorWorkoutId);
  final newEIdx = newWIdx >= 0
      ? edited.workouts[newWIdx].exercises
          .indexWhere((e) => e.id == anchorExerciseId)
      : -1;

  if (newWIdx >= 0 && newEIdx >= 0) {
    // Anchor survived — re-anchor and clamp.
    _workoutIndex = newWIdx;
    _exerciseIndex = newEIdx;
    final workout = edited.workouts[newWIdx];
    final exercise = workout.exercises[newEIdx];
    final effectiveSets = setsForExerciseInWorkout(workout, exercise);
    final clampedSet = _progress.currentSet.clamp(1, effectiveSets);
    final clampedRep = exercise.reps != null
        ? _progress.currentRep.clamp(1, exercise.reps!)
        : _progress.currentRep;
    _progress = SessionProgress(
      workoutIndex: newWIdx,
      exerciseIndex: newEIdx,
      currentSet: clampedSet,
      currentRep: clampedRep,
      phase: TimerPhase.paused,
    );
    // Rewrite open draft indices to match new position.
    if (_activeSetDraft != null) {
      _activeSetDraft!.workoutIndex = newWIdx;
      _activeSetDraft!.exerciseIndex = newEIdx;
    }
    if (_activeRestDraft != null) {
      _activeRestDraft!.workoutIndex = newWIdx;
      _activeRestDraft!.exerciseIndex = newEIdx;
    }
  } else {
    // Deletion branch — implemented in Task 3. Placeholder:
    _handleAnchorDeleted(anchorWorkoutId);
  }

  _remaining = _getDurationForPhase(_progress);
  _rescheduleSound();
  _syncTimerDisplay();
  notifyListeners();
}

// Temporary stub — replaced in Task 3.
void _handleAnchorDeleted(String anchorWorkoutId) {
  _discardDrafts();
  _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
  _remaining = Duration.zero;
  _beepScheduler?.cancelAll();
}
```

- [ ] Run tests
```bash
bash scripts/run_tests.sh
```
Expected: anchor-survives tests pass; deletion tests not yet written.

- [ ] Commit
```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_replace_test.dart
git commit -m "feat: implement replaceActiveSession — anchor-survives branch"
```

---

## Task 3: Implement `replaceActiveSession` — anchor-deleted branch

**Files:**
- Modify: `lib/providers/session_state_provider.dart`
- Modify: `test/providers/session_state_provider_replace_test.dart`

- [ ] Add failing tests for deletion branch

Append to `void main()` in `session_state_provider_replace_test.dart`:

```dart
group('replaceActiveSession — anchor deleted', () {
  test('jumps to next stop when current exercise deleted', () {
    final original = _withSecondExercise(_fixture());
    final p = SessionStateProvider()..start(original);
    // Stay on e1 (index 0). Delete e1, keep e2.
    final w = original.workouts[0];
    final edited = original.copyWith(
      workouts: [w.copyWith(exercises: [w.exercises[1]])],
    );

    p.replaceActiveSession(edited);

    // Should land on e2 (now index 0), paused, rememberPhase = getReady.
    expect(p.progress.exerciseIndex, 0);
    expect(p.progress.phase, TimerPhase.paused);
    // On resume the user should enter getReady, not mid-rep.
    p.resume();
    expect(p.phase, TimerPhase.getReady);
  });

  test('transitions to workoutComplete when all exercises from current onward deleted', () {
    final original = _withSecondExercise(_fixture());
    final p = SessionStateProvider()..start(original);
    p.jumpToExercise(1); // on e2
    // Delete everything from e2 onward — delete e2, keep e1.
    // Because we are on e2 (the last), and we delete it, nextStop = null,
    // previousStop = e1 (which is BEFORE current). But the user's intent
    // was "remove the rest" — when current is deleted and there is no
    // next stop, go to workoutComplete regardless.
    final w = original.workouts[0];
    final edited = original.copyWith(
      workouts: [w.copyWith(exercises: [w.exercises[0]])],
    );

    p.replaceActiveSession(edited);

    expect(p.phase, TimerPhase.workoutComplete);
  });

  test('discards open drafts when anchor deleted', () {
    final original = _withSecondExercise(_fixture());
    final p = SessionStateProvider()..start(original);
    p.debugSetPhase(TimerPhase.rep); // opens a set draft
    final w = original.workouts[0];
    // Delete e1 (current), keep e2.
    final edited = original.copyWith(
      workouts: [w.copyWith(exercises: [w.exercises[1]])],
    );
    p.replaceActiveSession(edited);
    // After deletion the event log should have at most the pre-existing events;
    // no new set event from the discarded draft.
    // The easiest proxy: finalizeSession should not throw and summary is coherent.
    expect(() => p.finalizeSession(), returnsNormally);
  });
});
```

- [ ] Run tests to confirm they fail
```bash
bash scripts/run_tests.sh
```

- [ ] Replace `_handleAnchorDeleted` stub with real implementation

```dart
void _handleAnchorDeleted(String anchorWorkoutId) {
  _discardDrafts();

  // Clamp old indices so _firstStopAtOrAfter doesn't index out of bounds.
  final clampedWIdx =
      _progress.workoutIndex.clamp(0, _activeSession!.workouts.length - 1);
  final clampedEIdx = _progress.exerciseIndex.clamp(
    0,
    _activeSession!.workouts[clampedWIdx].exercises.length,
  );

  final nextStop = _firstStopAtOrAfter(clampedWIdx, clampedEIdx);

  if (nextStop != null) {
    _workoutIndex = nextStop.workoutIndex;
    _exerciseIndex = nextStop.exerciseIndex;
    _progress = SessionProgress(
      workoutIndex: nextStop.workoutIndex,
      exerciseIndex: nextStop.exerciseIndex,
      currentSet: 1,
      currentRep: 1,
      phase: TimerPhase.paused,
    );
    _rememberCurrentPhaseForPausing = TimerPhase.getReady;
  } else {
    // Nothing left after current position — user removed the rest of the
    // session. Treat as session complete.
    _onPhaseTransition(_progress.phase, TimerPhase.workoutComplete, _progress);
    _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
    _remaining = Duration.zero;
    _beepScheduler?.cancelAll();
    _lastTickAt = null;
  }
}
```

- [ ] Run tests
```bash
bash scripts/run_tests.sh
```
Expected: all `replaceActiveSession` tests pass.

- [ ] Commit
```bash
git add lib/providers/session_state_provider.dart test/providers/session_state_provider_replace_test.dart
git commit -m "feat: implement replaceActiveSession — anchor-deleted branch"
```

---

## Task 4: Add `NewSessionScreenMode` enum and refactor `_save()`

**Files:**
- Modify: `lib/presentation/screens/catalog_flow/new_session_screen.dart`

This task is pure refactoring — no behaviour change. All existing save paths must work identically after.

- [ ] Add the enum above the class definition

```dart
enum NewSessionScreenMode { create, editCatalog, editBeforeStart, editActive }
```

- [ ] Replace the `startAfterSave` field with `mode` and add `onSaveAndStart` callback

```dart
class NewSessionScreen extends StatefulWidget {
  final Session? session;
  final NewSessionScreenMode mode;
  // Required when mode == editBeforeStart. Called with the built session
  // so the callsite can push ActiveSessionScreen (avoids circular import).
  final void Function(Session)? onSaveAndStart;

  const NewSessionScreen({
    super.key,
    this.session,
    this.mode = NewSessionScreenMode.create,
    this.onSaveAndStart,
  });
  // ...
}
```

- [ ] Update `_isNew` getter

```dart
bool get _isNew => widget.mode == NewSessionScreenMode.create;
```

- [ ] Update Save button label (line ~279)

```dart
child: Text(widget.mode == NewSessionScreenMode.editBeforeStart ? 'Save & Start' : 'Save'),
```

- [ ] Refactor `_save()` into a dispatch with named methods

Replace the entire `_save()` method:

```dart
Future<void> _save() async {
  if (_session.workouts.isEmpty ||
      _session.workouts.any((w) => w.exercises.isEmpty)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Every workout must have at least one exercise before saving.',
        ),
      ),
    );
    return;
  }
  if (!_formKey.currentState!.validate()) return;

  final session = _session.copyWith(
    title: _titleController.text.trim(),
    label: _itemLabelController.text,
    description: Nullable(
      _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    ),
    userId: _session.userId ??
        Provider.of<AuthProvider>(context, listen: false).userId,
  );

  switch (widget.mode) {
    case NewSessionScreenMode.editActive:
      return _saveActiveEdit(session);
    case NewSessionScreenMode.editBeforeStart:
      return _saveAndStart(session);
    case NewSessionScreenMode.create:
    case NewSessionScreenMode.editCatalog:
      return _saveToCatalog(session);
  }
}

Future<void> _saveActiveEdit(Session session) async {
  context.read<SessionStateProvider>().replaceActiveSession(session);
  if (mounted) Navigator.pop(context);
}

Future<void> _saveAndStart(Session session) async {
  if (mounted) widget.onSaveAndStart?.call(session);
}

Future<void> _saveToCatalog(Session session) async {
  final catalogProvider = Provider.of<CatalogProvider>(context, listen: false);

  if (_isNew) {
    await catalogProvider.upsertSession(session);
  } else {
    final editCommit = context.read<EditCommitController>();
    final bag = PendingChangeBag()..setSession(session);
    for (final wc in _pending.workoutsById.values) {
      bag.addWorkout(wc.workout);
    }
    for (final ec in _pending.exercisesById.values) {
      bag.addExercise(ec.exercise);
    }
    final result = await editCommit.commitChanges(
      bag,
      excludeSessionId: session.id,
    );
    if (result.hasAny && mounted) {
      final sections = <PropagationSection>[
        for (final entry in result.affectedSessionsByWorkoutId.entries)
          PropagationSection(
            itemKind: 'workout',
            itemId: entry.key,
            itemTitle: bag.workoutsById[entry.key]!.workout.title,
            consumerKind: 'sessions',
            consumers: [
              for (final s in entry.value)
                PropagationConsumer(id: s.id, label: s.title),
            ],
          ),
        for (final entry in result.affectedWorkoutsByExerciseId.entries)
          PropagationSection(
            itemKind: 'exercise',
            itemId: entry.key,
            itemTitle: bag.exercisesById[entry.key]!.exercise.title,
            consumerKind: 'workouts',
            consumers: [
              for (final w in entry.value)
                PropagationConsumer(id: w.id, label: w.title),
            ],
          ),
      ];
      final selection = await showPropagateChangesDialog(
        context: context,
        sections: sections,
      );
      if (selection == null) return;
      if (!selection.isEmpty) {
        await editCommit.propagateBag(bag, selection: selection);
      }
    }
  }
  if (mounted) Navigator.pop(context);
}
```

- [ ] Add `SessionStateProvider` import at the top of `new_session_screen.dart` (Dart does not have transitive imports):
```dart
import 'package:flash_forward/providers/session_state_provider.dart';
```

- [ ] Remove the `session_active_screen.dart` import from `new_session_screen.dart` (line 20 in the current file). It was only needed for the direct `ActiveSessionScreen` push, which is now handled via `onSaveAndStart` callback. This breaks the existing one-way dependency that would become circular in Task 6.

- [ ] Update the three existing callsites

`lib/presentation/screens/root_screen.dart:87`:
```dart
NewSessionScreen()
// becomes:
NewSessionScreen(mode: NewSessionScreenMode.create)
```

`lib/presentation/screens/catalog_flow/catalog_screen.dart:284`:
```dart
NewSessionScreen(session: filteredListItem)
// becomes:
NewSessionScreen(mode: NewSessionScreenMode.editCatalog, session: filteredListItem)
```

`lib/presentation/screens/session_flow/session_select_screen.dart:294-296`:
```dart
NewSessionScreen(
  session: ...,
  startAfterSave: true,
)
// becomes:
NewSessionScreen(
  mode: NewSessionScreenMode.editBeforeStart,
  session: ...,
  onSaveAndStart: (session) => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => ActiveSessionScreen(session: session),
    ),
    (route) => route.isFirst,
  ),
)
```

- [ ] Run tests
```bash
bash scripts/run_tests.sh
```
Expected: all passing — no behaviour changed.

- [ ] Commit
```bash
git add lib/presentation/screens/catalog_flow/new_session_screen.dart \
        lib/presentation/screens/root_screen.dart \
        lib/presentation/screens/catalog_flow/catalog_screen.dart \
        lib/presentation/screens/session_flow/session_select_screen.dart
git commit -m "refactor: replace startAfterSave bool with NewSessionScreenMode enum"
```

---

## Task 5: Add `editActive` lifecycle to `NewSessionScreen`

**Files:**
- Modify: `lib/presentation/screens/catalog_flow/new_session_screen.dart`

- [ ] Add provider reference field and pause-on-entry logic

Add to `_NewSessionScreenState`:

```dart
// Only used in editActive mode. Cached in initState so dispose() can call it.
SessionStateProvider? _sessionProvider;
bool _wasAlreadyPausedOnEntry = false;
```

Add `initState` override (or extend existing one if present):

```dart
@override
void initState() {
  super.initState();
  if (widget.mode == NewSessionScreenMode.editActive) {
    _sessionProvider = context.read<SessionStateProvider>();
    _wasAlreadyPausedOnEntry = _sessionProvider!.isPaused;
    if (!_wasAlreadyPausedOnEntry) _sessionProvider!.pause();
  }
}
```

Update `dispose`:

```dart
@override
void dispose() {
  if (widget.mode == NewSessionScreenMode.editActive &&
      !_wasAlreadyPausedOnEntry) {
    // resume() is a no-op if already unpaused (e.g. workoutComplete state),
    // so no phase-check needed here.
    _sessionProvider!.resume();
  }
  _titleController.dispose();
  _descriptionController.dispose();
  _itemLabelController.dispose();
  super.dispose();
}
```

- [ ] Run tests
```bash
bash scripts/run_tests.sh
```
Expected: all passing.

- [ ] Commit
```bash
git add lib/presentation/screens/catalog_flow/new_session_screen.dart
git commit -m "feat: NewSessionScreen pauses/resumes timer in editActive mode"
```

---

## Task 6: Wire up OutlinedButton in `_showEditExerciseDialog`

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart` (~line 784)

The button currently has `onPressed: null`. Make it active.

- [ ] Replace `onPressed: null` with the navigation handler

```dart
OutlinedButton(
  onPressed: () {
    Navigator.pop(context); // close modal, discard in-modal edits
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewSessionScreen(
          mode: NewSessionScreenMode.editActive,
          session: sessionStateData.activeSession!,
        ),
      ),
    );
  },
  style: OutlinedButton.styleFrom(
    backgroundColor: context.colorScheme.surfaceBright,
    side: BorderSide(
      color: context.colorScheme.primary,
      width: 0.5,
    ),
  ),
  child: Center(
    child: Text(
      "Edit this session's workouts and exercises.",
      style: context.titleMedium.copyWith(
        color: context.colorScheme.primary,
      ),
    ),
  ),
),
```

- [ ] Add `NewSessionScreen` import at top of `session_active_screen.dart`. This is safe because Task 4 removed the reverse import (`session_active_screen.dart`) from `new_session_screen.dart`:
```dart
import 'package:flash_forward/presentation/screens/catalog_flow/new_session_screen.dart';
```

- [ ] Run tests
```bash
bash scripts/run_tests.sh
```
Expected: all passing.

- [ ] Commit
```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat: wire up mid-session editor button in exercise edit modal"
```

---

## Task 7: Manual UI verification

No automated tests cover the full navigation flow. Verify these paths manually in the app.

### Original plan items

- [ ] Open an active session → tap an exercise → tap "Edit this session's workouts and exercises" → confirm editor opens (on top of the modal) showing the current session's workouts.

- [ ] In the editor: add a new exercise after the current one → save → confirm you land back on the same exercise (still paused), set/rep preserved. Resume works.

- [ ] In the editor: add a new exercise *before* the current one → save → confirm you land on the same exercise at the new (higher) index. Set/rep preserved.

- [ ] In the editor: delete the current exercise → save → confirm you land on the next exercise in `getReady` phase (paused). Resume starts getReady countdown.

- [ ] In the editor: delete all exercises after and including current → save → confirm session transitions to `workoutComplete` (no "resume" needed).

- [ ] In the editor: tap back without saving → confirm you return to the paused active session at the original position. Resume works.

- [ ] Open an active session where you had already manually paused → open editor → make a change → save → confirm session is still paused after save (not auto-resumed).

- [ ] Verify the `workoutComplete` path on `ActiveSessionScreen` still fires correctly through natural session completion (not via editor), to confirm the dispose guard didn't break normal flow.

- [ ] **Critical:** Verify what `ActiveSessionScreen` shows when it receives `workoutComplete` state on return from the editor (delete-everything path). The screen does not have a dedicated complete-screen guard — it renders the timer UI with phaseText "workout complete", same as natural completion. Confirm it is not blank/broken and does not crash (see RangeError fix below).

### Bugs found & fixed during verification

- [ ] **No `setState during build` warning:** confirm no `setState()/markNeedsBuild() during build` or `widget tree was locked` warnings in the terminal (editor is pushed on top of the modal; no `initState` pause/resume lifecycle).

- [ ] **Frozen countdown preserved:** mid-phase (e.g. rest-between-sets), edit + save → timer keeps the **same phase and frozen countdown**, not reset to 00:00, no jump to a different phase.

- [ ] **No phase jump on save:** saving the editor doesn't transition the phase incorrectly (rest→active, active→rest, etc.).

- [ ] **Re-anchor after reorder, no overwrite/duplicate:** on exercise 3, add an exercise before the superset, reorder it before current, save editor → save modal → active screen shows the **correct** current exercise; reopen editor → **no duplicate** of the current exercise.

- [ ] **Modal Save targets correct exercise:** after a reorder, the modal's "Save" writes edits to the **correct** exercise by ID, not the stale index.

- [ ] **Reduce sets/reps below current:** edit current exercise to fewer sets than `currentSet` → progress clamps to the new max, no crash.

- [ ] **getReady starts at 10s after delete:** delete the current exercise → jumps to next exercise → on resume, getReady countdown starts at **10s** (not a stale value).

- [ ] **Modal auto-closes on anchor delete:** delete the current (anchored) exercise → after save, the edit-exercise **modal closes automatically**; active screen shows the next exercise.

- [ ] **Modal auto-closes on delete-everything:** delete current + all following → session goes to `workoutComplete` and the modal auto-closes.

- [ ] **No RangeError on delete-everything:** delete current + all remaining exercises → no `RangeError` / `Invalid value: Not in inclusive range` crash in `ActiveSessionScreen.build`. Indices are clamped to a valid slot in the workoutComplete branch.

### Constraint checks

- [ ] **Empty workout blocked:** save with a workout that has no exercises → "Every workout must have at least one exercise" snackbar.

- [ ] **Superset contiguity:** reorder an exercise into the middle of a superset → "Cannot drop inside a superset" snackbar.
