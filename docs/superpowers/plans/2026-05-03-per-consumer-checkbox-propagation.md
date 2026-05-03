# Per-Consumer Checkbox Propagation Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the binary "Keep local / Update all" propagation prompt with a per-consumer checkbox UI so users can opt in selectively (e.g. push the new pull-up reps to Session A and Session C, but not Session B).

**Depends on:** [`2026-05-03-propagation-id-stability.md`](2026-05-03-propagation-id-stability.md) — that plan stabilises ids across propagation, which is required for checkbox identity to remain meaningful between visits.

**Architecture:**
- `PropagateChangesDialog` returns a structured `PropagationSelection` instead of a `bool`. Each consumer (session or workout) is a checkbox; default state is all checked (preserves today's behaviour on a no-op confirm).
- `PropagationSection.consumerLabels: List<String>` becomes `consumers: List<PropagationConsumer>` with stable ids.
- `propagateBag(bag, selection: ...)` plumbs the selection to each `propagate*` function, which accepts an optional `Set<String>` filter on consumer ids.
- Selection-map keys are kind-prefixed (`workout-in-sessions:<id>`, `exercise-in-sessions:<id>`, `exercise-in-workouts:<id>`) so an exercise that has both session-template consumers and workout consumers can be tracked separately.

**Tech Stack:** Flutter (Dart), Provider, flutter_test

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Modify | `lib/presentation/widgets/propagate_changes_dialog.dart` | Add `PropagationConsumer`, `PropagationSelection`; render checkboxes; return selection |
| Modify | `lib/providers/preset_provider.dart` | `propagate*` functions accept `Set<String>?` filter; `propagateBag` accepts `PropagationSelection?` |
| Modify | `lib/presentation/screens/training_program_flow/new_workout_screen.dart` | Build `PropagationConsumer` lists with stable ids; pass selection to `propagateBag` |
| Modify | `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` | Same |
| Modify | `lib/presentation/screens/training_program_flow/new_session_screen.dart` | Same |
| Test | `test/widgets/propagate_changes_dialog_test.dart` | New — widget tests for checkbox UI |
| Test | `test/providers/preset_provider_propagate_test.dart` | New tests for partial selection |

---

## Selection-key convention

Sections in the dialog can describe three categories of consumer:

| Section's `itemKind` | Consumer kind | Selection key |
|----------------------|---------------|---------------|
| `'workout'` | sessions | `'workout-in-sessions:<workoutId>'` |
| `'exercise'` (when listed under sessions in the prompt) | sessions | `'exercise-in-sessions:<exerciseId>'` |
| `'exercise'` (when listed under workouts in the prompt) | workouts | `'exercise-in-workouts:<exerciseId>'` |

Two `PropagationSection`s can share the same `itemId` (same exercise, two consumer categories). The kind-prefixed key disambiguates them.

---

## Task List Overview

### Phase 1 — Dialog and selection model
- [ ] Task 1: Define `PropagationConsumer` + `PropagationSelection` and update `PropagationSection`
- [ ] Task 2: Render checkboxes; return selection on confirm + widget tests

### Phase 2 — Provider plumbing
- [ ] Task 3: `propagate*` functions accept `Set<String>?` filter + tests
- [ ] Task 4: `propagateBag` accepts `PropagationSelection?` + tests

### Phase 3 — Edit screens
- [ ] Task 5: `NewWorkoutScreen` builds consumers with ids; passes selection
- [ ] Task 6: `NewExerciseScreen` same
- [ ] Task 7: `NewSessionScreen` same

### Phase 4 — Verification
- [ ] Task 8: Manual end-to-end repro
- [ ] Task 9: `flutter analyze` clean and `flutter test` green

---

## Phase 1 — Dialog and selection model

### Task 1: Define `PropagationConsumer` + `PropagationSelection` and update `PropagationSection`

**Files:**
- Modify: `lib/presentation/widgets/propagate_changes_dialog.dart`

**Why:** The current dialog API takes opaque consumer label strings, so it has no way to identify which consumers the user kept vs. dropped. Promote labels to objects with stable ids.

- [ ] **Step 1: Add types**

```dart
class PropagationConsumer {
  /// Stable id of the consumer (session id or workout id, depending on
  /// the section's itemKind / consumer kind).
  final String id;
  /// Display title shown next to the checkbox.
  final String label;

  const PropagationConsumer({required this.id, required this.label});
}

class PropagationSection {
  PropagationSection({
    required this.itemKind,
    required this.itemId,
    required this.itemTitle,
    required this.consumers,
    required this.consumerKind, // 'sessions' | 'workouts'
  });

  /// 'workout' or 'exercise' — what is being changed.
  final String itemKind;
  /// Stable id of the changed item.
  final String itemId;
  /// Display title of the changed item.
  final String itemTitle;
  /// What kind of consumer this section lists.
  final String consumerKind;
  final List<PropagationConsumer> consumers;

  /// Selection-map key. See plan documentation for convention.
  String get selectionKey => '$itemKind-in-$consumerKind:$itemId';
}

class PropagationSelection {
  /// Keyed by `PropagationSection.selectionKey` → set of consumer ids the
  /// user chose to update. Sections not present default to "none selected".
  PropagationSelection(this._byKey);
  final Map<String, Set<String>> _byKey;

  Set<String> consumerIdsFor(PropagationSection section) =>
      _byKey[section.selectionKey] ?? const {};

  bool get isEmpty => _byKey.values.every((s) => s.isEmpty);

  /// Convenience for callers building a "by item id" lookup. Filters to
  /// only the requested consumer kind so a single id with both consumer
  /// categories doesn't clash.
  Set<String>? sessionIdsFor(String itemKind, String itemId) =>
      _byKey['$itemKind-in-sessions:$itemId'];
  Set<String>? workoutIdsFor(String itemKind, String itemId) =>
      _byKey['$itemKind-in-workouts:$itemId'];
}
```

- [ ] **Step 2: Update existing dialog signature** to take the new section shape (UI rendering happens in Task 2). Old callers will break — that's fine; Tasks 5–7 update them.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(propagate-dialog): introduce PropagationConsumer and PropagationSelection"
```

---

### Task 2: Render checkboxes; return selection + widget tests

**Files:**
- Modify: `lib/presentation/widgets/propagate_changes_dialog.dart`
- Test: `test/widgets/propagate_changes_dialog_test.dart` (CREATE)

- [ ] **Step 1: Failing widget test**

```dart
testWidgets('all consumers checked by default; Update returns full selection',
    (tester) async {
  final sections = [
    PropagationSection(
      itemKind: 'workout',
      itemId: 'cat-w',
      itemTitle: 'Climbing Warm-up',
      consumerKind: 'sessions',
      consumers: [
        PropagationConsumer(id: 's-a', label: 'Session A'),
        PropagationConsumer(id: 's-b', label: 'Session B'),
      ],
    ),
  ];
  PropagationSelection? result;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
    return ElevatedButton(
      onPressed: () async {
        result = await showPropagateChangesDialog(
            context: ctx, sections: sections);
      },
      child: const Text('open'),
    );
  })));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Update selected'));
  await tester.pumpAndSettle();

  expect(result, isNotNull);
  expect(result!.consumerIdsFor(sections.first), {'s-a', 's-b'});
});

testWidgets('unchecking removes the consumer from the selection',
    (tester) async {
  // ...similar setup, untap the checkbox for Session B before Update...
  expect(result!.consumerIdsFor(sections.first), {'s-a'});
});

testWidgets('Cancel returns null', (tester) async {
  // ...tap Cancel...
  expect(result, isNull);
});
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

```dart
Future<PropagationSelection?> showPropagateChangesDialog({
  required BuildContext context,
  required List<PropagationSection> sections,
}) {
  // Initialise selection with all consumers checked (preserves
  // back-compat behaviour for users who just confirm without changing
  // anything).
  final selected = <String, Set<String>>{
    for (final s in sections)
      s.selectionKey: {for (final c in s.consumers) c.id},
  };
  return showDialog<PropagationSelection>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      return AlertDialog(
        title: const Text('Apply changes elsewhere?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) ...const [
                  SizedBox(height: 12),
                  Divider(height: 1),
                  SizedBox(height: 12),
                ],
                Text(
                  '${sections[i].itemTitle} (${sections[i].itemKind}) '
                  'is also used in:',
                ),
                ...sections[i].consumers.map((c) {
                  final key = sections[i].selectionKey;
                  final isChecked = selected[key]!.contains(c.id);
                  return CheckboxListTile(
                    value: isChecked,
                    title: Text(c.label),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected[key]!.add(c.id);
                      } else {
                        selected[key]!.remove(c.id);
                      }
                    }),
                  );
                }),
                Row(children: [
                  TextButton(
                    onPressed: () => setState(() {
                      selected[sections[i].selectionKey] = {
                        for (final c in sections[i].consumers) c.id,
                      };
                    }),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selected[sections[i].selectionKey]!.clear();
                    }),
                    child: const Text('Select none'),
                  ),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(PropagationSelection(Map.of(selected))),
            child: const Text('Update selected'),
          ),
        ],
      );
    }),
  );
}
```

- [ ] **Step 4: Run** — PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(propagate-dialog): per-consumer checkboxes with selection result"
```

---

## Phase 2 — Provider plumbing

### Task 3: `propagate*` functions accept `Set<String>?` filter

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_propagate_test.dart`

**Why:** Each propagation function currently iterates every match. To honour user selection, accept an optional filter on consumer ids; `null` means "all" (preserves callers that don't filter).

- [ ] **Step 1: Failing test**

```dart
test('propagateWorkoutToSessionTemplates with onlyToSessionIds filters', () async {
  // Three sessions A, B, C all reference catalog workout 'cat-w'.
  // Filter to {A.id, C.id}. After: A and C updated, B unchanged.
});
```

- [ ] **Step 2: Implement**

```dart
Future<void> propagateWorkoutToSessionTemplates(
  Workout updated, {
  Set<String>? onlyToSessionIds,
}) async {
  final affected = usagesOfWorkout(updated.id)
      .where((s) => onlyToSessionIds == null || onlyToSessionIds.contains(s.id))
      .toList();
  for (final session in affected) {
    final newWorkouts = session.workouts.map((w) {
      if (w.id == updated.id || w.templateId == updated.id) {
        return updated.deepCopy(keepId: true);
      }
      return w;
    }).toList();
    await promoteAndUpdateSession(session.copyWith(workouts: newWorkouts));
  }
}

Future<void> propagateExerciseToSessionTemplates(
  Exercise updated, {
  Set<String>? onlyToSessionIds,
}) async {
  // mirror — filter sessions before walking
}

Future<void> propagateExerciseToWorkouts(
  Exercise updated, {
  Set<String>? onlyToWorkoutIds,
}) async {
  // mirror — filter workouts before replacing
}
```

- [ ] **Step 3: Run; commit**

```bash
git commit -m "feat(preset): propagate functions accept consumer-id filters"
```

---

### Task 4: `propagateBag` accepts `PropagationSelection?`

**Files:**
- Modify: `lib/providers/preset_provider.dart`
- Test: `test/providers/preset_provider_propagate_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('propagateBag with empty selection writes nothing', () async {
  // Bag with one bagged exercise + selection that has no consumers checked.
  // Affected sessions/workouts unchanged after call.
});

test('propagateBag with partial selection only updates chosen consumers',
    () async {
  // Three sibling sessions; selection contains only two of them.
  // Two updated; third unchanged.
});

test('propagateBag with null selection updates all (back-compat guard)',
    () async {
  // Bag without selection arg. All consumers updated. (Same behaviour as
  // before this plan landed.)
});
```

- [ ] **Step 2: Implement**

```dart
Future<void> propagateBag(
  PendingChangeBag bag, {
  PropagationSelection? selection,
}) async {
  for (final ec in bag.exercisesById.values) {
    await propagateExerciseToSessionTemplates(
      ec.exercise,
      onlyToSessionIds:
          selection?.sessionIdsFor('exercise', ec.exercise.id),
    );
    await propagateExerciseToWorkouts(
      ec.exercise,
      onlyToWorkoutIds:
          selection?.workoutIdsFor('exercise', ec.exercise.id),
    );
  }
  for (final wc in bag.workoutsById.values) {
    await propagateWorkoutToSessionTemplates(
      wc.workout,
      onlyToSessionIds:
          selection?.sessionIdsFor('workout', wc.workout.id),
    );
  }
}
```

- [ ] **Step 3: Run; commit**

```bash
git commit -m "feat(preset): propagateBag accepts PropagationSelection"
```

---

## Phase 3 — Edit screens

### Task 5: `NewWorkoutScreen` builds consumers with ids; passes selection

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart`

- [ ] **Step 1: Build sections with `PropagationConsumer`**

Replace the existing section-build with:

```dart
final sections = <PropagationSection>[
  for (final entry in result.affectedSessionsByWorkoutId.entries)
    PropagationSection(
      itemKind: 'workout',
      itemId: entry.key,
      itemTitle: workout.title,
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
if (selection != null && !selection.isEmpty) {
  await presetProvider.propagateBag(bag, selection: selection);
}
```

- [ ] **Step 2: Commit**

```bash
git commit -m "feat(workout-edit): pass per-consumer selection to propagateBag"
```

---

### Task 6: `NewExerciseScreen` same shape

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`

Mirror Task 5: build sections with `PropagationConsumer`, pass selection.

- [ ] **Step 1: Update; commit**

```bash
git commit -m "feat(exercise-edit): pass per-consumer selection to propagateBag"
```

---

### Task 7: `NewSessionScreen` same shape

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`

Mirror Task 5.

- [ ] **Step 1: Update; commit**

```bash
git commit -m "feat(session-edit): pass per-consumer selection to propagateBag"
```

---

## Phase 4 — Verification

### Task 8: Manual end-to-end repro

- [ ] **Step 1: Partial selection.**
  1. Open the catalog Workouts tab → tap a workout used in three sessions → edit something → save.
  2. Prompt fires with three checkboxes, all checked.
  3. Uncheck one → tap Update selected.
  4. Verify the unchecked session retains the previous content; the others updated.

- [ ] **Step 2: Repeat-prompt for the unchecked one.**
  1. Edit the same workout again from inside the previously-unchecked session.
  2. The prompt fires again listing the other two sessions (since they share the catalog id; lookup still finds them).

- [ ] **Step 3: Cancel keeps everything local.**
  1. Edit a workout → on the prompt, tap Cancel.
  2. Other consumers untouched. Catalog item updated.

- [ ] **Step 4: Empty selection acts like cancel.**
  1. Edit a workout → uncheck everything → tap Update selected.
  2. Other consumers untouched. Catalog item still updated.

- [ ] **Step 5: Mixed sections (workout + exercise).**
  1. Set up: a session with a workout containing pull-ups, and another workout in the catalog also containing pull-ups.
  2. Edit pull-ups via the session's drilldown so the bag has both a session-embedded workout change and a session-embedded exercise change… *(if the suppression rule from the unified-edit plan kicks in, exercise-level section may not appear; that's expected)*. Adjust the scenario to one that does generate two sections.
  3. Confirm both sections each have their own checkboxes; selection on one does not affect the other.

---

### Task 9: `flutter analyze` clean and `flutter test` green

- [ ] `flutter analyze` — no new warnings.
- [ ] `flutter test` — all tests pass.

---

## Out of scope (call out for future plans)

- **Persisting selection state across edits** ("don't ask me about Session B again"). Could be a per-session preference or a per-template-per-consumer ignore list.
- **Per-consumer change preview.** Today the prompt only shows titles; a future feature could show a diff or a summary of what's about to change for each consumer.
- **Bulk-selection helpers across sections.** Right now each section has its own Select all / Select none. A "Select none across all sections" might be useful with many sections.
