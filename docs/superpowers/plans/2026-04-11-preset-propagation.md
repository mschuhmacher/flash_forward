# Preset Propagation Preference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users control whether edits to sessions, workouts, and exercises are saved back to the preset catalog via a three-way preference (Always / Ask / Never).

**Architecture:** A `PropagationPreference` enum is added to `SettingsProvider` and persisted via `SharedPreferences`. A shared utility function `maybePropagateToPreset` reads the pref and either persists silently, shows an "Update preset?" dialog, or skips — then each form screen calls it for edits (new items always persist unconditionally). The `persistToProvider` flag introduced earlier in `NewWorkoutScreen` and `NewExerciseScreen` is removed; `_isNew` already carries that meaning.

**Tech Stack:** Flutter, Provider, SharedPreferences, flutter_test

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Modify | `lib/providers/settings_provider.dart` | Add `PropagationPreference` enum + field, getter, setter, persistence |
| Create | `lib/utils/propagation_utils.dart` | `maybePropagateToPreset()` + `PropagationDialog` widget |
| Modify | `lib/presentation/screens/root_screen.dart` | Add propagation pref UI to `SettingsDrawer` |
| Modify | `lib/presentation/screens/training_program_flow/new_session_screen.dart` | Replace hardcoded persist with `maybePropagateToPreset`; fix `startAfterSave` case |
| Modify | `lib/presentation/screens/training_program_flow/new_workout_screen.dart` | Remove `persistToProvider` flag; replace with `maybePropagateToPreset` for edits. Inner-navigation call site (within-session workout tap, line 251 of `new_session_screen.dart`) is implicitly covered — removing the flag means `_isNew`+pref logic applies to all callers. |
| Modify | `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` | Same as workout screen. Inner-navigation call site (within-workout exercise tap, line 261 of `new_workout_screen.dart`) is implicitly covered by the same mechanism. |
| Modify | `lib/presentation/screens/training_program_flow/catalog_screen.dart` | Remove `persistToProvider: true` from workout/exercise card taps |
| Modify | `lib/presentation/screens/root_screen.dart` (FAB) | Remove `persistToProvider: true` from workout/exercise FAB cases |
| Test | `test/utils/propagation_utils_test.dart` | Unit tests for `maybePropagateToPreset` logic |

---

### Task 1: Add `PropagationPreference` to `SettingsProvider`

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Test: `test/providers/settings_provider_test.dart` (create)

- [ ] **Step 1: Write failing tests**

```dart
// test/providers/settings_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsProvider.propagationPreference', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to ask', () async {
      final p = SettingsProvider();
      await p.init();
      expect(p.propagationPreference, PropagationPreference.ask);
    });

    test('persists and restores always', () async {
      SharedPreferences.setMockInitialValues({'pref_propagation': 'always'});
      final p = SettingsProvider();
      await p.init();
      expect(p.propagationPreference, PropagationPreference.always);
    });

    test('persists and restores never', () async {
      SharedPreferences.setMockInitialValues({'pref_propagation': 'never'});
      final p = SettingsProvider();
      await p.init();
      expect(p.propagationPreference, PropagationPreference.never);
    });

    test('setPropagationPreference notifies and persists', () async {
      final p = SettingsProvider();
      await p.init();
      bool notified = false;
      p.addListener(() => notified = true);
      await p.setPropagationPreference(PropagationPreference.never);
      expect(notified, isTrue);
      expect(p.propagationPreference, PropagationPreference.never);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_propagation'), 'never');
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```
flutter test test/providers/settings_provider_test.dart
```
Expected: FAIL — `PropagationPreference` not defined.

- [ ] **Step 3: Add enum + field to `SettingsProvider`**

In `lib/providers/settings_provider.dart`, add after the imports:

```dart
enum PropagationPreference { always, ask, never }
```

Inside `SettingsProvider`:

```dart
static const _keyPropagation = 'pref_propagation';

PropagationPreference _propagationPreference = PropagationPreference.ask;

PropagationPreference get propagationPreference => _propagationPreference;
```

In `init()`, add:

```dart
_propagationPreference = _parsePropagation(prefs.getString(_keyPropagation));
```

Add these methods:

```dart
Future<void> setPropagationPreference(PropagationPreference pref) async {
  _propagationPreference = pref;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyPropagation, pref.name);
}

PropagationPreference _parsePropagation(String? value) => switch (value) {
  'always' => PropagationPreference.always,
  'never'  => PropagationPreference.never,
  _        => PropagationPreference.ask,
};
```

- [ ] **Step 4: Run tests to confirm they pass**

```
flutter test test/providers/settings_provider_test.dart
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/settings_provider.dart test/providers/settings_provider_test.dart
git commit -m "feat: add PropagationPreference setting to SettingsProvider"
```

---

### Task 2: Create `propagation_utils.dart`

**Files:**
- Create: `lib/utils/propagation_utils.dart`
- Test: `test/utils/propagation_utils_test.dart` (create)

The utility handles the three-way decision: persist silently, show dialog then conditionally persist, or skip. It is decoupled from provider types — it takes a callback.

- [ ] **Step 1: Write failing tests**

```dart
// test/utils/propagation_utils_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/utils/propagation_utils.dart';

void main() {
  group('maybePropagateToPreset', () {
    testWidgets('always — calls persist without dialog', (tester) async {
      bool persisted = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return TextButton(
            onPressed: () async {
              await maybePropagateToPreset(
                ctx,
                PropagationPreference.always,
                () async { persisted = true; },
              );
            },
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(persisted, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('never — skips persist', (tester) async {
      bool persisted = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return TextButton(
            onPressed: () async {
              await maybePropagateToPreset(
                ctx,
                PropagationPreference.never,
                () async { persisted = true; },
              );
            },
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(persisted, isFalse);
    });

    testWidgets('ask — shows dialog, Yes triggers persist', (tester) async {
      bool persisted = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return TextButton(
            onPressed: () async {
              await maybePropagateToPreset(
                ctx,
                PropagationPreference.ask,
                () async { persisted = true; },
              );
            },
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Update preset'));
      await tester.pumpAndSettle();
      expect(persisted, isTrue);
    });

    testWidgets('ask — No skips persist', (tester) async {
      bool persisted = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return TextButton(
            onPressed: () async {
              await maybePropagateToPreset(
                ctx,
                PropagationPreference.ask,
                () async { persisted = true; },
              );
            },
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep local'));
      await tester.pumpAndSettle();
      expect(persisted, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```
flutter test test/utils/propagation_utils_test.dart
```
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create `lib/utils/propagation_utils.dart`**

```dart
import 'package:flash_forward/providers/settings_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

/// Conditionally persists [persist] based on [pref].
/// - always → calls [persist] immediately
/// - never  → no-op
/// - ask    → shows [PropagationDialog]; calls [persist] only if confirmed
///
/// Safety: [persist] must NOT capture or use [context] — the utility does not
/// guard for unmounted state after the dialog resolves. All provider calls in
/// [persist] should use references obtained before calling this function.
Future<void> maybePropagateToPreset(
  BuildContext context,
  PropagationPreference pref,
  Future<void> Function() persist,
) async {
  switch (pref) {
    case PropagationPreference.always:
      await persist();
    case PropagationPreference.never:
      return;
    case PropagationPreference.ask:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const PropagationDialog(),
      );
      if (confirmed == true) await persist();
  }
}

class PropagationDialog extends StatelessWidget {
  const PropagationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update preset?', style: context.h3),
      content: Text(
        'Do you want to save these changes back to the preset catalog?',
        style: context.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep local'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Update preset'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```
flutter test test/utils/propagation_utils_test.dart
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/utils/propagation_utils.dart test/utils/propagation_utils_test.dart
git commit -m "feat: add maybePropagateToPreset utility and PropagationDialog"
```

---

### Task 3: Add propagation preference UI to `SettingsDrawer`

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart` (lines ~170–240 — the `SettingsDrawer` widget)

The drawer already uses `Consumer<SettingsProvider>`. Add a third preference block following the same pattern as weight unit and grade system.

- [ ] **Step 1: Update `SettingsDrawer` in `root_screen.dart`**

Add `import 'package:flash_forward/providers/settings_provider.dart';` if not already imported (it is, via the `Consumer`).

Inside the `Consumer<SettingsProvider>` `Column`, after the grade system block (`const SizedBox(height: 6)` + the description text), add:

```dart
const SizedBox(height: 20),
Text('Preset sync', style: context.titleMedium),
const SizedBox(height: 8),
SizedBox(
  width: double.infinity,
  child: SegmentedButton<PropagationPreference>(
    style: SegmentedButton.styleFrom(
      visualDensity: VisualDensity.compact,
    ),
    segments: [
      ButtonSegment(
        value: PropagationPreference.always,
        label: Text('Always', style: context.bodyMedium),
      ),
      ButtonSegment(
        value: PropagationPreference.ask,
        label: Text('Ask', style: context.bodyMedium),
      ),
      ButtonSegment(
        value: PropagationPreference.never,
        label: Text('Never', style: context.bodyMedium),
      ),
    ],
    showSelectedIcon: false,
    selected: {settings.propagationPreference},
    onSelectionChanged: (s) =>
        settings.setPropagationPreference(s.first),
  ),
),
const SizedBox(height: 6),
Text(
  'When editing an existing preset, controls whether changes are saved back to the catalog.',
  style: context.bodyMedium.copyWith(
    color: context.colorScheme.onSurfaceVariant,
  ),
),
```

- [ ] **Step 2: Hot-reload and verify UI in the Preferences drawer**

Open the app → Profile tab → open settings drawer → confirm the "Preset sync" segmented button appears and selecting each option persists across app restarts.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/root_screen.dart
git commit -m "feat: add preset sync preference UI to settings drawer"
```

---

### Task 4: Update `NewSessionScreen`

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`

Two cases to handle:
1. **Normal save** (catalog edit, FAB creates new) — currently always calls `addPresetSession` / `updatePresetSession`. Change: new sessions always persist; edits go through `maybePropagateToPreset`.
2. **`startAfterSave: true`** (session_select → edit before start) — currently never persists. Change: call `maybePropagateToPreset` **before** navigating to `ActiveSessionScreen`.

- [ ] **Step 1: Add import for propagation utils**

At the top of `new_session_screen.dart`, add:
```dart
import 'package:flash_forward/utils/propagation_utils.dart';
import 'package:flash_forward/providers/settings_provider.dart';
```

- [ ] **Step 2: Update `_save()`**

Replace the current `_save()` body (lines 60–98) with:

```dart
Future<void> _save() async {
  if (_formKey.currentState!.validate()) {
    final session = _session.copyWith(
      title: _titleController.text.trim(),
      label: _itemLabelController.text,
      description: Nullable(
        _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      ),
      userId:
          _session.userId ??
          Provider.of<AuthProvider>(context, listen: false).userId,
    );

    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    if (widget.startAfterSave) {
      // Editing before starting — ask about preset propagation first.
      // Guard with !_isNew: startAfterSave is only reachable from
      // session_select_screen which always passes an existing session,
      // but the guard is explicit for safety.
      if (!_isNew) {
        await maybePropagateToPreset(
          context,
          settings.propagationPreference,
          () => presetProvider.updatePresetSession(session),
        );
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveSessionScreen(session: session),
          ),
          (route) => route.isFirst,
        );
      }
      return;
    }

    if (_isNew) {
      await presetProvider.addPresetSession(session);
    } else {
      await maybePropagateToPreset(
        context,
        settings.propagationPreference,
        () => presetProvider.updatePresetSession(session),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}
```

- [ ] **Step 3: Hot-reload and manual test**

Test these three paths:
- Open a session from catalog → edit → save → with pref = Always: session updated in catalog
- Open a session from catalog → edit → save → with pref = Ask: dialog appears; Yes updates, No doesn't
- Open a session from catalog → edit → save → with pref = Never: session not updated in catalog
- Open a session from session_select → Edit → save → with pref = Ask: dialog appears, then session starts regardless of answer

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_session_screen.dart
git commit -m "feat: apply propagation preference when saving existing sessions"
```

---

### Task 5: Update `NewWorkoutScreen` — remove flag, add propagation

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart`
- Modify: `lib/presentation/screens/training_program_flow/catalog_screen.dart`
- Modify: `lib/presentation/screens/root_screen.dart`

The `persistToProvider` flag was added earlier this session and is now superseded. Remove it; use `_isNew` + `maybePropagateToPreset` instead.

- [ ] **Step 1: Remove `persistToProvider` and update `_save()` in `NewWorkoutScreen`**

Replace the class declaration:

```dart
class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  const NewWorkoutScreen({super.key, this.workout});
```

Remove the `persistToProvider` field and doc comment. Then update `_save()`:

Add imports at the top:
```dart
import 'package:flash_forward/utils/propagation_utils.dart';
import 'package:flash_forward/providers/settings_provider.dart';
```

Replace the `_save()` persist block:

```dart
final presetProvider = Provider.of<PresetProvider>(context, listen: false);
final settings = Provider.of<SettingsProvider>(context, listen: false);

if (_isNew) {
  await presetProvider.addPresetWorkout(workout);
} else {
  await maybePropagateToPreset(
    context,
    settings.propagationPreference,
    () => presetProvider.updatePresetWorkout(workout),
  );
}
if (mounted) Navigator.pop(context, workout);
```

- [ ] **Step 2: Remove `persistToProvider: true` from `catalog_screen.dart`**

In the `ItemType.workouts` case of `ProgramListviewCard.build()`:

```dart
case ItemType.workouts:
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => NewWorkoutScreen(workout: filteredListItem),
    ),
  );
```

- [ ] **Step 3: Remove `persistToProvider: true` from root_screen.dart FAB**

```dart
case 1:
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => NewWorkoutScreen()),
  );
```

- [ ] **Step 4: Hot-reload and verify**

- New workout from FAB → always saved to catalog ✓
- Edit workout from catalog → propagation pref respected ✓
- Edit workout from within session → propagation pref respected ✓

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_workout_screen.dart \
        lib/presentation/screens/training_program_flow/catalog_screen.dart \
        lib/presentation/screens/root_screen.dart
git commit -m "feat: apply propagation preference when saving existing workouts"
```

---

### Task 6: Update `NewExerciseScreen` — remove flag, add propagation

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`
- Modify: `lib/presentation/screens/training_program_flow/catalog_screen.dart`
- Modify: `lib/presentation/screens/root_screen.dart`

Same pattern as Task 5.

- [ ] **Step 1: Remove `persistToProvider` and update `_save()` in `NewExerciseScreen`**

Replace the class declaration:

```dart
class NewExerciseScreen extends StatefulWidget {
  final Exercise? exercise;

  const NewExerciseScreen({super.key, this.exercise});
```

Add imports:
```dart
import 'package:flash_forward/utils/propagation_utils.dart';
import 'package:flash_forward/providers/settings_provider.dart';
```

Replace `_save()` with:

```dart
Future<void> _save() async {
  if (_formKey.currentState!.validate()) {
    final exercise = Exercise(
      id: widget.exercise?.id,
      templateId: widget.exercise?.templateId,
      userId:
          widget.exercise?.userId ??
          Provider.of<AuthProvider>(context, listen: false).userId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      label: _label ?? '',
      equipment:
          _equipmentController.text.trim().isEmpty
              ? null
              : _equipmentController.text.trim(),
      muscleGroups:
          _muscleGroupsController.text.trim().isEmpty
              ? null
              : _muscleGroupsController.text.trim(),
      difficulty: _difficulty,
      type: _exerciseType,
      sets: _sets,
      reps:
          _exerciseType == ExerciseType.timedReps
              ? (_reps ?? 10)
              : (_repsEnabled ? _reps : null),
      timeBetweenSets: _timeBetweenSets,
      timePerRep: _timePerRep,
      timeBetweenReps: _timeBetweenReps,
      activeTime: _activeTime,
      load: double.tryParse(_loadController.text.trim()) ?? 0.0,
      loadUnit: _loadUnit,
      rpe: _rpeEnabled ? _rpe.clamp(1, 10) : null,
      notes:
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
    );
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (_isNew) {
      await presetProvider.addPresetExercise(exercise);
    } else {
      await maybePropagateToPreset(
        context,
        settings.propagationPreference,
        () => presetProvider.updatePresetExercise(exercise),
      );
    }
    if (mounted) Navigator.pop(context, exercise);
  }
}
```

- [ ] **Step 2: Remove `persistToProvider: true` from `catalog_screen.dart`**

```dart
case ItemType.exercises:
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) =>
          NewExerciseScreen(exercise: filteredListItem),
    ),
  );
```

- [ ] **Step 3: Remove `persistToProvider: true` from root_screen.dart FAB**

```dart
case 2:
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => NewExerciseScreen()),
  );
```

- [ ] **Step 4: Hot-reload and verify**

- New exercise from FAB → always saved to catalog ✓
- Edit exercise from catalog → propagation pref respected ✓
- Edit exercise within workout → propagation pref respected; workout local state also updated ✓

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/training_program_flow/new_exercise_screen.dart \
        lib/presentation/screens/training_program_flow/catalog_screen.dart \
        lib/presentation/screens/root_screen.dart
git commit -m "feat: apply propagation preference when saving existing exercises"
```

---

### Task 7: Full regression check

- [ ] **Step 1: Run all tests**

```
flutter test
```
Expected: all pass.

- [ ] **Step 2: Manual smoke test — all three preference modes**

With pref = **Always**:
- Create session/workout/exercise from FAB → appears in catalog ✓
- Edit session from catalog → saved ✓
- Edit session from session_select → saved, then session starts ✓
- Edit workout within session → workout preset updated ✓
- Edit exercise within workout → exercise preset updated ✓

With pref = **Ask**:
- All edit paths show the "Update preset?" dialog ✓
- "Update preset" → saves; "Keep local" → doesn't ✓
- New item creation → no dialog, always saves ✓

With pref = **Never**:
- All edit paths skip the dialog, do not update catalog ✓
- New item creation → always saves ✓

- [ ] **Step 3: Final commit if any loose ends**

```bash
git add -p
git commit -m "chore: preset propagation feature complete"
```
