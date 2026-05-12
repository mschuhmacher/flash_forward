# Default Data Edit, Delete & Reset — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to edit and delete default preset exercises/workouts/sessions, and restore them via Settings > Restore defaults.

**Architecture:** "Hide + Override" pattern — defaults remain immutable constants in code; a persisted `Set<String> _hiddenDefaultIds` tracks what the user has deleted or replaced. Editing a default silently creates a user-owned copy (`templateId → original ID`) and hides the original. Reset clears hidden IDs and removes user copies of defaults.

**Tech Stack:** Flutter, Provider, SharedPreferences, Supabase (existing stack — no new dependencies)

---

## Context

Users cannot currently delete or edit default exercises/workouts/sessions shipped with the app. Default items have `userId == null` and are loaded from Dart constants (`kDefaultExercises`, `kDefaultWorkouts`, `kDefaultSessions`) into `PresetProvider._defaultX` lists that are never persisted to disk. The catalog's swipe-delete is gated to user items only (`presetUserWorkoutsIDs.contains(id)`), and edit screens lock metadata fields (`_canEditMetadata = userId != null`). This plan unlocks full CRUD on defaults while keeping them restorable, and lays the foundation for freemium counting (edited defaults don't count toward free-user limits).

---

## Critical Pre-work Discovery

Only `kDefaultExercises` has stable string IDs (e.g., `'max-hangs'`). `kDefaultWorkouts` and `kDefaultSessions` have no `id:` parameters — they get random UUIDs at runtime, making hide-by-ID impossible across restarts. **Task 1 must add stable IDs before anything else.**

---

## UX Design (Confirmed)

- **Edit default:** Silent copy-on-edit. Opening a default item's edit screen works normally; on Save, a user-owned copy is created and the original is hidden. The user is **forced to pick a different title** for their copy — this is essential because after a Restore the original re-appears, and we can't have two items with the same name. A one-time info dialog explains the copy-on-edit behavior on first use (so the user understands where their edit went and why they had to rename it).
- **Delete default:** Swipe-delete enabled for all items. Defaults show a confirmation: *"Remove from catalog? Restore anytime in Settings > Restore defaults."*
- **DEFAULT badge:** Subtle chip on catalog cards for default items.
- **Settings reset:** "Restore defaults" — restores hidden/edited defaults to their original state. **Removes the user's customized copies of defaults** (because the original returns and they would otherwise duplicate). User-created-from-scratch items are untouched. The confirmation dialog must spell this out so the user is not surprised.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/data/default_workout_data.dart` | Add stable `id:` strings to all workout constructors |
| `lib/data/default_session_data.dart` | Add stable `id:` strings to all 8 session constructors |
| `lib/providers/preset_provider.dart` | Add `_hiddenDefaultIds` state, persistence, new methods, updated getters |
| `lib/presentation/screens/training_program_flow/catalog_screen.dart` | DEFAULT badge, unified hide/delete, confirmation dialog for defaults |
| `lib/presentation/screens/training_program_flow/new_exercise_screen.dart` | Remove metadata lock; copy-on-edit save path |
| `lib/presentation/screens/training_program_flow/new_workout_screen.dart` | Remove metadata lock; copy-on-edit save path |
| `lib/presentation/screens/training_program_flow/new_session_screen.dart` | Copy-on-edit save path (no metadata lock here already) |
| `lib/presentation/screens/root_screen.dart` | Add "Restore defaults" ListTile + dialog to SettingsDrawer |

---

## Task 1: Add Stable IDs to Default Workouts and Sessions

**Files:**
- Modify: `lib/data/default_workout_data.dart`
- Modify: `lib/data/default_session_data.dart`

Without stable IDs, hiding by ID is impossible across restarts since `kDefaultWorkouts` uses auto-generated UUIDs.

- [ ] **Step 1: Add `id:` to every `Workout(...)` constructor in `default_workout_data.dart`**

  Use kebab-case based on the title. Example:
  ```dart
  Workout(
    id: 'climbing-warm-up',   // ADD THIS
    title: 'Climbing Warm-up',
    ...
  )
  ```
  Full list of IDs to add (match to existing titles exactly):
  - `'climbing-warm-up'`, `'general-warm-up'`, `'strength-training-warm-up'`
  - `'flash-and-limit-bouldering'`, `'boulder-pyramid-endurance'`, `'route-laps-endurance'`
  - `'max-pick-ups-min-edge-hangs'`, `'combined-limit-strength'`, `'dynamic-climbing-power'`
  - `'full-body-strength-workout'`, `'general-upper-body-strength'`, `'upper-body-power'`
  - `'pull-ups-pick-ups-set'`, `'dips-and-front-lever'`, `'handstand-training'`
  - `'barbell-strength-training'`, `'daily-mobility-light-hangs'`
  - `'evening-stretch-recovery'`, `'quick-fingerboarding'`
  - (Add stable IDs to all remaining workouts in the file using the same pattern)

- [ ] **Step 2: Add `id:` to every `Session(...)` constructor in `default_session_data.dart`**

  ```dart
  Session(
    id: 'projecting-session',   // ADD THIS
    title: 'Projecting session',
    ...
  )
  ```
  Full list:
  - `'projecting-session'`, `'powerendurance-training'`, `'power-session'`
  - `'volume-session'`, `'full-body-strength-session'`
  - `'daily-fingerboard-stretching'`, `'daily-evening-stretch'`, `'quick-fingerboarding-session'`

- [ ] **Step 3: Verify no duplicate IDs**

  Run a debug assertion (can be in a test or `main()` during dev):
  ```dart
  assert(kDefaultWorkouts.map((w) => w.id).toSet().length == kDefaultWorkouts.length,
    'Duplicate IDs in kDefaultWorkouts');
  assert(kDefaultSessions.map((s) => s.id).toSet().length == kDefaultSessions.length,
    'Duplicate IDs in kDefaultSessions');
  ```
  Also verify exercises (already have IDs but double-check):
  ```dart
  assert(kDefaultExercises.map((e) => e.id).toSet().length == kDefaultExercises.length,
    'Duplicate IDs in kDefaultExercises');
  ```

- [ ] **Step 4: Hot-restart the app and verify catalog still loads correctly**

- [ ] **Step 5: Commit**
  ```bash
  git add lib/data/default_workout_data.dart lib/data/default_session_data.dart
  git commit -m "feat: add stable string IDs to default workouts and sessions"
  ```

---

## Task 2: Add `_hiddenDefaultIds` to PresetProvider

**Files:**
- Modify: `lib/providers/preset_provider.dart`

- [ ] **Step 1: Add state field and SharedPreferences key**

  At the top of `PresetProvider`, alongside the other state fields:
  ```dart
  static const _keyHiddenDefaultIds = 'pref_hidden_default_ids';
  Set<String> _hiddenDefaultIds = {};
  ```

- [ ] **Step 2: Add `_loadHiddenDefaultIds()` private method**

  ```dart
  Future<void> _loadHiddenDefaultIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyHiddenDefaultIds) ?? [];
    _hiddenDefaultIds = raw.toSet();
  }
  ```

- [ ] **Step 3: Add `_saveHiddenDefaultIds()` private method**

  ```dart
  Future<void> _saveHiddenDefaultIds() async {
    final prefs = await SharedPreferences.getInstance();
    // TODO(sync): sync hiddenDefaultIds to Supabase in a future multi-device release
    await prefs.setStringList(_keyHiddenDefaultIds, _hiddenDefaultIds.toList());
  }
  ```

- [ ] **Step 4: Call `_loadHiddenDefaultIds()` in `init()`**

  In the existing `init()` method, after loading defaults from constants but before loading user data:
  ```dart
  await _loadHiddenDefaultIds();
  ```

- [ ] **Step 5: Update the three `presetX` getters to filter hidden items**

  ```dart
  List<Session> get presetSessions => [
    ..._defaultSessions.where((s) => !_hiddenDefaultIds.contains(s.id)),
    ..._userSessions,
  ];
  List<Workout> get presetWorkouts => [
    ..._defaultWorkouts.where((w) => !_hiddenDefaultIds.contains(w.id)),
    ..._userWorkouts,
  ];
  List<Exercise> get presetExercises => [
    ..._defaultExercises.where((e) => !_hiddenDefaultIds.contains(e.id)),
    ..._userExercises,
  ];
  ```

- [ ] **Step 6: Add query helper methods**

  ```dart
  /// Returns true if [id] belongs to any of the immutable default lists.
  bool isDefaultItem(String id) =>
      _defaultSessions.any((s) => s.id == id) ||
      _defaultWorkouts.any((w) => w.id == id) ||
      _defaultExercises.any((e) => e.id == id);

  /// Returns true if [templateId] points to a default item.
  /// Use to identify user items that are edits of defaults.
  bool isModifiedDefault(String? templateId) {
    if (templateId == null) return false;
    return isDefaultItem(templateId);
  }
  ```

- [ ] **Step 7: Add `hideDefaultItem()` method**

  ```dart
  Future<void> hideDefaultItem(String id) async {
    _hiddenDefaultIds.add(id);
    await _saveHiddenDefaultIds();
    notifyListeners();
  }
  ```

- [ ] **Step 8: Add `restoreAllDefaults()` method**

  This method has two responsibilities that must happen together:
  1. Un-hide the original defaults (clear `_hiddenDefaultIds`).
  2. Remove the user copies that were created when the user edited those defaults (`templateId` points to a default). These copies must go — otherwise, after restore, the user would see both the restored original AND their custom version side-by-side, which defeats the purpose of "restore" and would be visually confusing.

  User items that the user created from scratch (with `templateId == null` or pointing to another user item) are **not** touched.

  ```dart
  /// Clears all hidden defaults AND removes any user items that were created by
  /// editing a default (identified by templateId pointing to a default item).
  ///
  /// Why delete the user copies: if we only un-hid the originals, the user would
  /// see both the restored original and their customized copy in the catalog —
  /// two items with similar names, competing for attention. The UX intent of
  /// "Restore defaults" is "bring me back to a clean slate for default content",
  /// so the customized copies are removed.
  ///
  /// User-created-from-scratch items are NOT affected (templateId is null or points
  /// to another user item, not a default).
  Future<void> restoreAllDefaults() async {
    // Step 1: un-hide originals. This alone makes the catalog show the defaults again.
    _hiddenDefaultIds.clear();
    await _saveHiddenDefaultIds();

    // Step 2: find user items that are "modified defaults" (templateId points to a
    // default item). These were created by the copy-on-edit flow in Task 4.
    final removedSessionIds = _userSessions
        .where((s) => isModifiedDefault(s.templateId))
        .map((s) => s.id)
        .toList();
    final removedWorkoutIds = _userWorkouts
        .where((w) => isModifiedDefault(w.templateId))
        .map((w) => w.id)
        .toList();
    final removedExerciseIds = _userExercises
        .where((e) => isModifiedDefault(e.templateId))
        .map((e) => e.id)
        .toList();

    // Drop them from in-memory state.
    _userSessions.removeWhere((s) => removedSessionIds.contains(s.id));
    _userWorkouts.removeWhere((w) => removedWorkoutIds.contains(w.id));
    _userExercises.removeWhere((e) => removedExerciseIds.contains(e.id));

    // Persist pruned lists to local JSON (overwrite-in-place).
    await PresetLogger.savePresetToFile('user_preset_sessions.json', _userSessions);
    await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
    await PresetLogger.savePresetToFile('user_preset_exercises.json', _userExercises);

    // Best-effort cloud deletion. We don't block on failures — the sync queue
    // pattern used elsewhere in this file will retry on next connectivity.
    if (_syncService != null) {
      for (final id in removedSessionIds) {
        await _syncService!.deleteSession(id).catchError((_) {});
      }
      for (final id in removedWorkoutIds) {
        await _syncService!.deleteWorkout(id).catchError((_) {});
      }
      for (final id in removedExerciseIds) {
        await _syncService!.deleteExercise(id).catchError((_) {});
      }
    }

    notifyListeners();
  }
  ```

- [ ] **Step 9: Clear hidden IDs in `reset()` (logout)**

  Find the existing `reset()` method and add:
  ```dart
  _hiddenDefaultIds = {};
  ```
  Also call `_saveHiddenDefaultIds()` so the cleared state is persisted on logout.

- [ ] **Step 10: Add unfiltered title getters for strict uniqueness validation**

  Why: the standard `presetExercises` getter filters out hidden defaults, so a hidden default's title looks "free" to the regular title validator. But when editing a default via copy-on-edit, we need to force the user to pick a new name — because after `restoreAllDefaults()` runs, the original will come back and both titles must remain unique. The edit screens use these unfiltered getters only in the "editing a default" code path.

  ```dart
  /// Titles of ALL known exercises (defaults + user items), including hidden defaults.
  /// Use only when validating titles during copy-on-edit of a default, so the user
  /// is forced to pick a new title that won't collide with the restored original later.
  List<String> get allKnownExerciseTitles => [
    ..._defaultExercises.map((e) => e.title),
    ..._userExercises.map((e) => e.title),
  ];
  List<String> get allKnownWorkoutTitles => [
    ..._defaultWorkouts.map((w) => w.title),
    ..._userWorkouts.map((w) => w.title),
  ];
  List<String> get allKnownSessionTitles => [
    ..._defaultSessions.map((s) => s.title),
    ..._userSessions.map((s) => s.title),
  ];
  ```

- [ ] **Step 11: Add freemium-ready item counters (future-proof)**

  ```dart
  int get userCreatedExerciseCount =>
      _userExercises.where((e) => !isModifiedDefault(e.templateId)).length;
  int get userCreatedWorkoutCount =>
      _userWorkouts.where((w) => !isModifiedDefault(w.templateId)).length;
  int get userCreatedSessionCount =>
      _userSessions.where((s) => !isModifiedDefault(s.templateId)).length;
  ```

- [ ] **Step 12: Verify logic manually in debug**

  - Call `hideDefaultItem('max-hangs')` → verify it disappears from `presetExercises`
  - Verify `allKnownExerciseTitles` still contains the hidden default's title
  - Call `restoreAllDefaults()` → verify it re-appears
  - Verify `isDefaultItem('max-hangs')` returns `true`, `isDefaultItem('fake-id')` returns `false`

- [ ] **Step 13: Commit**
  ```bash
  git add lib/providers/preset_provider.dart
  git commit -m "feat: add hidden defaults tracking and restore logic to PresetProvider"
  ```

---

## Task 3: Update CatalogScreen — DEFAULT Badge and Delete for All Items

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/catalog_screen.dart`

- [ ] **Step 1: Replace `_deleteItem` with `_hideOrDeleteItem`**

  Replace the existing `_deleteItem` method with:
  ```dart
  Future<void> _hideOrDeleteItem(dynamic item) async {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    final isDefault = presetProvider.isDefaultItem(item.id);

    if (isDefault) {
      final confirm = await _showHideDefaultDialog(item.title);
      if (confirm != true) return;
      await presetProvider.hideDefaultItem(item.id);
    } else {
      switch (widget.itemType) {
        case ItemType.sessions:
          await presetProvider.deleteUserPresetSession(item.id);
        case ItemType.workouts:
          await presetProvider.deleteUserPresetWorkout(item.id);
        case ItemType.exercises:
          await presetProvider.deleteUserPresetExercise(item.id);
      }
    }
  }

  Future<bool?> _showHideDefaultDialog(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from catalog?'),
        content: Text(
          '"$title" is a default item. You can restore it anytime via Settings > Restore defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
  ```

- [ ] **Step 2: Update the `onDelete` call in `itemBuilder` to always pass the callback**

  Find the `ProgramListviewCard(...)` constructor call. Change:
  ```dart
  // OLD (conditional)
  onDelete: isUserDefined ? () => _deleteItem(item) : null,

  // NEW (always available)
  onDelete: () => _hideOrDeleteItem(item),
  ```

- [ ] **Step 3: Pass `isDefault` to `ProgramListviewCard`**

  In `itemBuilder`, compute:
  ```dart
  final bool isDefault = presetProvider.isDefaultItem(item.id);
  ```
  Pass it to the card:
  ```dart
  ProgramListviewCard(
    // ... existing params
    isDefault: isDefault,
  )
  ```

- [ ] **Step 4: Add `isDefault` field to `ProgramListviewCard`**

  In the `ProgramListviewCard` class:
  ```dart
  final bool isDefault;

  const ProgramListviewCard({
    // ... existing
    required this.isDefault,
  });
  ```

- [ ] **Step 5: Add DEFAULT chip to the card's title row**

  In the `ListTile.title` widget, wrap the existing title text in a `Row` (or update the existing row) to include the chip:
  ```dart
  title: Row(
    children: [
      Expanded(
        child: Text(
          filteredListItem.title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (isDefault)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            'DEFAULT',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
    ],
  ),
  ```

- [ ] **Step 6: Run app and verify**
  - DEFAULT badge appears on default exercises/workouts/sessions
  - Swipe a default exercise → "Remove from catalog?" dialog appears → confirm → item disappears
  - Swipe a user-created item → deletes directly (no dialog)

- [ ] **Step 7: Commit**
  ```bash
  git add lib/presentation/screens/training_program_flow/catalog_screen.dart
  git commit -m "feat: enable delete for default catalog items with DEFAULT badge"
  ```

---

## Task 4: Copy-on-Edit for Default Items in Edit Screens

**Files:**
- Modify: `lib/presentation/screens/training_program_flow/new_exercise_screen.dart`
- Modify: `lib/presentation/screens/training_program_flow/new_workout_screen.dart`
- Modify: `lib/presentation/screens/training_program_flow/new_session_screen.dart`

### 4a: NewExerciseScreen

- [ ] **Step 1: Remove the `_canEditMetadata` getter and all its usages**

  Delete the `_canEditMetadata` getter. For every form field that uses `enabled: _canEditMetadata` or `validator: _canEditMetadata ? fn : null`, remove the condition and leave the field fully enabled/validated. Rationale: we now allow editing defaults, so metadata (title, label, description) must be editable in all cases.

- [ ] **Step 2: Detect "editing a default" once and reuse it**

  Near the top of `_NewExerciseScreenState.build` (or as a getter), add:
  ```dart
  // When editing a default, we force a "copy-on-edit" flow: the user's edit
  // becomes a new user-owned item, and the original default is hidden. Because
  // the user can later restore the original via Settings, the copy must have a
  // UNIQUE title — otherwise the restored original and the copy would collide.
  bool get _isEditingDefault {
    if (widget.exercise == null) return false;
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    return presetProvider.isDefaultItem(widget.exercise!.id);
  }
  ```

- [ ] **Step 3: Strict title validation when editing a default**

  Find the title `TextFormField` and its `validator`. The validator currently calls `FieldValidators.exerciseTitle(value, existingTitles: ..., ownTitle: widget.exercise?.title)`.

  Change the `existingTitles` source and the `ownTitle` argument based on `_isEditingDefault`:
  ```dart
  validator: (value) {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);

    // When editing a default we use the UNFILTERED list (defaults + user,
    // including the hidden original). And we intentionally omit ownTitle so
    // the validator DOES see the original's title as "taken" — this forces
    // the user to pick a new name. Why: after Restore defaults, the original
    // re-appears, and two items with the same title would be ambiguous.
    final existingTitles = _isEditingDefault
        ? presetProvider.allKnownExerciseTitles
        : presetProvider.presetExercises.map((e) => e.title).toList();

    final ownTitle = _isEditingDefault ? null : widget.exercise?.title;

    return FieldValidators.exerciseTitle(
      value,
      existingTitles: existingTitles,
      ownTitle: ownTitle,
    );
  },
  ```

  (If the current validator assigns `existingTitles` somewhere else, apply the same logic there — the key is that `_isEditingDefault` selects the strict path.)

- [ ] **Step 4: Update `_save()` to perform the copy-on-edit**

  Find the `if (widget.persistToProvider)` block. Replace it with:
  ```dart
  if (widget.persistToProvider) {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    // Recompute here instead of using _isEditingDefault so we don't hit the
    // provider during widget build vs. save paths inconsistently.
    final isDefault = widget.exercise != null &&
        presetProvider.isDefaultItem(widget.exercise!.id);

    if (_isNew) {
      // Brand new user exercise — straight add.
      await presetProvider.addPresetExercise(exercise);
    } else if (isDefault) {
      // Copy-on-edit: the user cannot mutate a default in place. Instead we
      // create a brand-new user-owned copy that carries a templateId pointing
      // back to the original default. This templateId is the marker used by
      // isModifiedDefault() and restoreAllDefaults() to identify and clean up
      // these copies later. After adding the copy, we hide the original so the
      // user doesn't see both side by side.
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userCopy = exercise.copyWith(
        id: const Uuid().v4(),
        userId: authProvider.userId,
        templateId: Nullable(widget.exercise!.id),
      );
      await presetProvider.addPresetExercise(userCopy);
      await presetProvider.hideDefaultItem(widget.exercise!.id);
      await _showDefaultEditTipIfNeeded();
    } else {
      // Regular edit of a user item — mutate in place.
      await presetProvider.updatePresetExercise(exercise);
    }
  }
  ```

- [ ] **Step 5: Add `_showDefaultEditTipIfNeeded()` — one-time educational dialog**

  **What this method does:** The first time the user ever edits a default item, it shows a one-time explanation dialog telling them what just happened ("your edit became a personal copy, the original can be restored from Settings"). It uses a SharedPreferences boolean flag (`pref_seen_default_edit_tip`) to ensure the dialog only shows once per device install — after that, edits of defaults are silent.

  **Why this exists:** The copy-on-edit flow is silent by design (chosen over an explicit "Customize" workflow for lower friction). But "silent" means the user has no idea that (a) their edit created a NEW item and (b) the original was hidden but can be restored. Without this dialog, a user who edits a default and later wonders "where did the original go?" has no clue where to look. Showing it once anchors the mental model: edits of defaults are reversible and live in Settings.

  ```dart
  /// Shows a one-time educational dialog the first time the user edits a default
  /// item. After it has been shown once, it never appears again (tracked via
  /// SharedPreferences key `pref_seen_default_edit_tip`).
  ///
  /// Rationale: the copy-on-edit flow is silent by design, but that silence
  /// hides two important facts from the user — (1) their edit became a new
  /// personal copy, not an in-place modification of the default, and (2) the
  /// original can be brought back via Settings > Restore defaults. Showing
  /// this once builds the user's mental model for the whole feature.
  Future<void> _showDefaultEditTipIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('pref_seen_default_edit_tip') == true) return;
    // Persist before showing so even if the user force-quits mid-dialog we
    // don't annoy them with it again on next launch.
    await prefs.setBool('pref_seen_default_edit_tip', true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default item customized'),
        content: const Text(
          "You just edited a default item. Your changes were saved as a personal "
          "copy — the original default has been hidden from your catalog. "
          "You can bring all default content back anytime via "
          "Settings > Restore defaults.",
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
  ```

  Add `import 'package:shared_preferences/shared_preferences.dart';` if not already present.
  Add `import 'package:uuid/uuid.dart';` if not already present.

- [ ] **Step 6: Verify in app**
  - Open a default exercise from catalog → all fields are editable
  - Try to save without changing the title → validator rejects it ("An exercise with this title already exists") — this proves the uniqueness enforcement works
  - Change the title to something unique and tap Save
  - On first-ever default edit: the info dialog appears
  - Verify: catalog shows renamed version (user copy), original default is gone
  - Open another default and edit it → info dialog does NOT appear again

### 4b: NewWorkoutScreen

Apply the exact same pattern as NewExerciseScreen (Steps 1–5). Specifically:

- [ ] **Step 7: Remove `_canEditMetadata` getter and all usages**

- [ ] **Step 8: Add `_isEditingDefault` getter** (identical pattern, using `widget.workout`)

- [ ] **Step 9: Strict title validation when editing a default**

  Use `presetProvider.allKnownWorkoutTitles` and omit `ownTitle` when `_isEditingDefault` is true. Same rationale as exercise: forces the user to pick a unique name so the restored original and the copy don't collide later.

- [ ] **Step 10: Update `_save()` to perform copy-on-edit**

  ```dart
  if (widget.persistToProvider) {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    final isDefault = widget.workout != null &&
        presetProvider.isDefaultItem(widget.workout!.id);

    if (_isNew) {
      await presetProvider.addPresetWorkout(workout);
    } else if (isDefault) {
      // Copy-on-edit: new user-owned workout, templateId points to the default
      // so restoreAllDefaults() can find and remove this copy later.
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userCopy = workout.copyWith(
        id: const Uuid().v4(),
        userId: authProvider.userId,
        templateId: Nullable(widget.workout!.id),
      );
      await presetProvider.addPresetWorkout(userCopy);
      await presetProvider.hideDefaultItem(widget.workout!.id);
      await _showDefaultEditTipIfNeeded(); // same logic as exercise screen
    } else {
      await presetProvider.updatePresetWorkout(workout);
    }
  }
  ```

- [ ] **Step 11: Add `_showDefaultEditTipIfNeeded()`** (identical to exercise screen, or extract to a shared helper)

### 4c: NewSessionScreen

`NewSessionScreen` has no `persistToProvider` flag and no metadata lock, so only title validation and the save path need updating.

- [ ] **Step 12: Add `_isEditingDefault` getter** (using `widget.session`)

- [ ] **Step 13: Strict title validation when editing a default**

  Use `presetProvider.allKnownSessionTitles` and omit `ownTitle` when `_isEditingDefault`.

- [ ] **Step 14: Update `_save()` with copy-on-edit**

  ```dart
  final presetProvider = Provider.of<PresetProvider>(context, listen: false);
  final isDefault = widget.session != null &&
      presetProvider.isDefaultItem(widget.session!.id);

  if (_isNew) {
    await presetProvider.addPresetSession(session);
  } else if (isDefault) {
    // Copy-on-edit for sessions — same contract as exercises/workouts.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userCopy = session.copyWith(
      id: const Uuid().v4(),
      userId: authProvider.userId,
      templateId: Nullable(widget.session!.id),
    );
    await presetProvider.addPresetSession(userCopy);
    await presetProvider.hideDefaultItem(widget.session!.id);
    await _showDefaultEditTipIfNeeded();
  } else {
    await presetProvider.updatePresetSession(session);
  }
  ```

- [ ] **Step 15: Add `_showDefaultEditTipIfNeeded()`** (identical to exercise screen)

- [ ] **Step 16: Commit**
  ```bash
  git add lib/presentation/screens/training_program_flow/new_exercise_screen.dart \
          lib/presentation/screens/training_program_flow/new_workout_screen.dart \
          lib/presentation/screens/training_program_flow/new_session_screen.dart
  git commit -m "feat: copy-on-edit for default items, remove metadata lock"
  ```

---

## Task 5: Add "Restore Defaults" to Settings Drawer

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart`

- [ ] **Step 1: Add the `_showRestoreDefaultsDialog` method to `SettingsDrawer`**

  The confirmation dialog must be explicit that the user's **customized copies of defaults** will be deleted. This is critical — without clear wording, a user who spent time tweaking a default workout could lose their changes unexpectedly. User items built from scratch are NOT affected and we say so in the same breath to reassure them.

  ```dart
  /// Shows a confirmation dialog for restoring default content and, if confirmed,
  /// calls PresetProvider.restoreAllDefaults().
  ///
  /// Dialog wording is deliberately explicit: it tells the user that their
  /// customized copies of defaults WILL be deleted, while also reassuring them
  /// that items they created from scratch are safe. This is the only "destructive
  /// for customizations, safe for creations" operation in the app, so surprise
  /// here would be costly.
  Future<void> _showRestoreDefaultsDialog(BuildContext context) async {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore defaults?'),
        content: const Text(
          "All default exercises, workouts, and sessions will be restored to "
          "their original state.\n\n"
          "Any edits you made to default items will be lost — your customized "
          "copies of defaults will be deleted.\n\n"
          "Items you created from scratch will NOT be affected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await presetProvider.restoreAllDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default items restored')),
        );
      }
    }
  }
  ```

- [ ] **Step 2: Add the ListTile to the SettingsDrawer body**

  In the SettingsDrawer widget, add after the "Clear logs" tile (before the next `Divider`):
  ```dart
  ListTile(
    leading: const Icon(Icons.restore_rounded),
    title: const Text('Restore defaults'),
    onTap: () => _showRestoreDefaultsDialog(context),
  ),
  ```

- [ ] **Step 3: Verify end-to-end**

  1. Delete a default exercise from catalog
  2. Go to Profile → Settings (end drawer)
  3. Tap "Restore defaults" → confirm
  4. Return to catalog → exercise is visible again

- [ ] **Step 4: Commit**
  ```bash
  git add lib/presentation/screens/root_screen.dart
  git commit -m "feat: add Restore defaults option to Settings drawer"
  ```

---

## End-to-End Verification Checklist

- [ ] Default exercises, workouts, and sessions all show the DEFAULT badge in catalog
- [ ] Swipe a default exercise → confirmation dialog appears → confirm → item hidden
- [ ] Swipe a user exercise → no dialog → deletes immediately
- [ ] Open a default exercise → all fields editable (no locked title/description/label)
- [ ] Try to save a default exercise without changing the title → validator blocks with "already exists" error (proves strict uniqueness works)
- [ ] Change title to something unique and save → user copy appears in catalog, original default is gone
- [ ] First-ever default edit shows the one-time info dialog; subsequent default edits do NOT re-show it
- [ ] Open a user exercise (not a default) → edit → saves in place (no duplication, no tip dialog)
- [ ] Settings > Restore defaults → dialog clearly states that customized copies of defaults will be deleted
- [ ] Confirm restore → all hidden defaults reappear AND all user copies of defaults (templateId pointing to a default) are gone
- [ ] User-created-from-scratch items (templateId null) survive the restore untouched
- [ ] After restore, editing the same default again works fresh (no ghost copies left behind)
- [ ] `userCreatedExerciseCount` does NOT include edited-default copies — verify by creating one user item from scratch and one edit-of-default, then reading the count
- [ ] After logout and login, hidden IDs are cleared (fresh slate per user)
- [ ] Hot-restart the app during dev → default IDs are stable (no phantom hidden items)

---

## Freemium Notes (Future Reference)

When freemium is introduced, use `presetProvider.userCreatedExerciseCount` (not `_userExercises.length`) for limit checks. Items where `isModifiedDefault(templateId) == true` are exempt from counting — they're personalized defaults, not new content. The gating logic goes in `PresetProvider.addPreset*` methods:

```dart
Future<void> addPresetExercise(Exercise exercise) async {
  if (!isModifiedDefault(exercise.templateId)) {
    // check free-user limit here
  }
  // ... existing add logic
}
```

No model changes are needed for freemium — `templateId` already carries all the information needed.
