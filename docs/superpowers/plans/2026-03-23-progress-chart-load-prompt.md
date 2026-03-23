# Progress Chart Load Prompt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-Max-exercise load prompt to the session finish dialog so that strength PR data is captured and the progress chart on the Profile screen actually populates.

**Architecture:** The bug is a data-capture gap. `ProgressExtractor.extractLoads` filters `exercise.load <= 0`, but all Max exercises default to `load: 0.0` and the only existing way to set a load was a small edit icon inside the active session — invisible to users doing their first test session. The fix adds an explicit load-entry section to the existing `_showFinishSessionDialog`, following the same pattern already used for body weight. The extracted loads are applied back to the session's workouts before saving so `extractLoads` finds non-zero values on the next Profile visit.

**Tech Stack:** Flutter/Dart, Provider, existing `Exercise.copyWith`, `Workout.copyWith`, `Session.copyWith`, `ProgressExtractor.isMaxExercise`, `FilteringTextInputFormatter`

---

## File Map

| File | Change |
|------|--------|
| `lib/presentation/screens/session_flow/session_active_bottom_bar.dart` | Only file changed. Add load collection before `showDialog`, add UI section in dialog, apply loads to workouts in save handler. |

No new files. No model changes. No new dependencies.

---

### Task 1: Collect Max exercises and create controllers before `showDialog`

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart:138-159`

The current code computes `hasMaxExercise` via `sessionHasMaxExercise` and then separately creates body-weight controllers. Replace the `hasMaxExercise` line with a loop that also builds a list of per-exercise controllers.

- [ ] **Step 1: Remove the standalone `hasMaxExercise` declaration**

In `_showFinishSessionDialog`, delete these two lines (currently around line 138):
```dart
final hasMaxExercise =
    ProgressExtractor.sessionHasMaxExercise(activeSession);
```

- [ ] **Step 2: Add the controller-building loop after `bodyWeightController`**

Insert the following block immediately after the `bodyWeightController` declaration (and before `showDialog`):

```dart
// Collect unique Max exercises so the user can enter the load achieved.
// Deduplication by templateId ?? title mirrors the key used in ProgressExtractor.
final seenKeys = <String>{};
final maxExercisesForLoad = <({
  String key,
  String title,
  TextEditingController controller,
})>[];
for (final workout in activeSession.workouts) {
  for (final exercise in workout.exercises) {
    if (!ProgressExtractor.isMaxExercise(exercise)) continue;
    final key = exercise.templateId ?? exercise.title;
    if (seenKeys.contains(key)) continue;
    seenKeys.add(key);
    // Pre-fill if the user already set a load via the in-session edit dialog.
    // Normalize stored value (exercise.loadUnit) to the display unit.
    String prefill = '';
    if (exercise.load > 0) {
      final loadKg = (exercise.loadUnit?.toLowerCase() == 'lbs')
          ? exercise.load / 2.20462
          : exercise.load;
      final displayLoad = weightUnit == 'lbs' ? loadKg * 2.20462 : loadKg;
      prefill = displayLoad.toStringAsFixed(1);
    }
    maxExercisesForLoad.add((
      key: key,
      title: exercise.title,
      controller: TextEditingController(text: prefill),
    ));
  }
}
final hasMaxExercise = maxExercisesForLoad.isNotEmpty;
```

This replaces the old `hasMaxExercise` bool and the separate `sessionHasMaxExercise` call. Body-weight and load sections both use `hasMaxExercise`.

- [ ] **Step 3: Hot reload and confirm the dialog still opens without errors**

No behaviour change yet — just structural refactor of how `hasMaxExercise` is derived.

---

### Task 2: Add the load-entry UI section inside the dialog

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart` — inside the `SingleChildScrollView > Column` of the `AlertDialog`

The dialog already has a body-weight section gated on `hasMaxExercise`. Add a **Max exercise loads** section directly above it.

- [ ] **Step 1: Insert the section between the grade pickers and the body-weight section**

Find the comment `// ── Body weight (only shown when session has Max exercises) ──` and insert the following block immediately before it:

```dart
// ── Max exercise loads (shown when session has Max exercises) ──
if (hasMaxExercise) ...[
  const SizedBox(height: 20),
  Text(
    'Max exercise loads',
    style: dialogContext.titleMedium,
  ),
  const SizedBox(height: 4),
  Text(
    'Enter the load you achieved for each test ($weightUnit)',
    style: dialogContext.bodyMedium.copyWith(
      color: dialogContext.colorScheme.onSurfaceVariant,
    ),
  ),
  const SizedBox(height: 8),
  ...maxExercisesForLoad.map(
    (info) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: info.controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(r'^\d*\.?\d*'),
          ),
        ],
        decoration: InputDecoration(
          labelText: info.title,
          hintText: weightUnit == 'lbs' ? 'e.g. 154.3' : 'e.g. 70.0',
          border: const OutlineInputBorder(),
          suffixText: weightUnit,
        ),
        style: dialogContext.bodyMedium,
      ),
    ),
  ),
],
```

- [ ] **Step 2: Hot reload, open a session with Max exercises, tap the finish button**

Verify:
- Each unique Max exercise in the session gets its own labelled text field
- Fields are blank (no load set) or pre-filled (if the user already set load via in-session edit icon)
- Body weight field still appears below
- Sessions without Max exercises show no load fields

---

### Task 3: Apply entered loads to the session's workouts before saving

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_bottom_bar.dart` — inside the `ElevatedButton.onPressed` handler

Currently `finishedSession` is built directly from `activeSession.copyWith(...)`. We need to first patch the workouts with the entered loads, then pass those updated workouts into `copyWith`.

- [ ] **Step 1: Build the `loadKgMap` from the controllers**

Insert before the `final finishedSession = activeSession.copyWith(...)` line:

```dart
// Build a map from exercise key → load in kg from the user's inputs.
// Only non-zero, parseable values are included; blank/zero fields are ignored
// so exercises that weren't tested today are left with their existing load.
final loadKgMap = <String, double>{};
for (final info in maxExercisesForLoad) {
  final text = info.controller.text.trim();
  final parsed = double.tryParse(text);
  if (parsed != null && parsed > 0) {
    loadKgMap[info.key] =
        weightUnit == 'lbs' ? parsed / 2.20462 : parsed;
  }
}
```

- [ ] **Step 2: Rebuild the workouts list with updated loads**

Insert immediately after the `loadKgMap` block:

```dart
// Apply entered loads to the session copy. Exercises not in loadKgMap
// are returned unchanged. Loads are stored in kg with loadUnit 'kg' for
// consistent normalization in ProgressExtractor._normalizeToKg.
final updatedWorkouts = loadKgMap.isEmpty
    ? activeSession.workouts
    : activeSession.workouts.map((workout) {
        final updatedExercises = workout.exercises.map((exercise) {
          if (!ProgressExtractor.isMaxExercise(exercise)) return exercise;
          final key = exercise.templateId ?? exercise.title;
          final loadKg = loadKgMap[key];
          if (loadKg == null) return exercise;
          return exercise.copyWith(
            load: loadKg,
            loadUnit: Nullable('kg'),
          );
        }).toList();
        return workout.copyWith(exercises: updatedExercises);
      }).toList();
```

- [ ] **Step 3: Pass `updatedWorkouts` into `finishedSession`**

Modify the existing `activeSession.copyWith(...)` call to add `workouts: updatedWorkouts`:

```dart
final finishedSession = activeSession.copyWith(
  workouts: updatedWorkouts,      // ← add this line
  label: labelController.text,
  description: Nullable(
    descriptionController.text.isEmpty
        ? null
        : descriptionController.text,
  ),
  completedAt: Nullable(DateTime.now()),
  maxGradeClimbed: Nullable(selectedGradeClimbed),
  maxGradeFlashed: Nullable(selectedGradeFlashed),
  bodyWeightKg: Nullable(bodyWeightKg),
);
```

- [ ] **Step 4: Hot reload, complete a full test session with loads entered**

Verify end-to-end:
1. Start a session that includes at least one Max exercise (e.g., "Max Weighted Pull-up")
2. Complete the session without editing exercise loads mid-session
3. In the finish dialog, enter a load (e.g., `10` kg) for the Max exercise
4. Tap Finish
5. Navigate to Profile tab
6. The strength chart dropdown shows the exercise
7. The chart renders a single data point (dot) for today's date at the entered load
8. The "No data logged yet" empty state is gone

- [ ] **Step 5: Verify existing sessions without Max exercises are unaffected**

Complete a non-Max session — confirm the finish dialog shows no load fields and the existing grade/body-weight UX is unchanged.

---

### Task 4: Commit

- [ ] **Step 1: Stage and commit**

```bash
git add lib/presentation/screens/session_flow/session_active_bottom_bar.dart
git commit -m "fix: prompt for Max exercise loads in finish dialog so progress chart populates

Previously, all Max exercises defaulted to load 0.0. The only way to set
a load was via an edit icon during the session, which users wouldn't know
to use on their first test. ProgressExtractor.extractLoads filters out
load <= 0, so the chart always showed 'No data logged yet'.

Now the finish dialog shows one text field per unique Max exercise in the
session, following the same pattern as the body weight prompt. Entered
values are written back to the session's workout exercises (stored as kg)
before saving, so the extractor finds non-zero loads on the next visit."
```
