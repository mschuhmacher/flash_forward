# Settings Provider & Preferences Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the weight unit and grade system preference controls from `profile_screen.dart` into `SettingsDrawer`, with shared state managed by a new `SettingsProvider`.

**Architecture:** Create a `SettingsProvider` (ChangeNotifier + SharedPreferences) as the single source of truth for user preferences. Register it globally in `main.dart`. `SettingsDrawer` owns the UI controls; `profile_screen.dart` reads values for the charts via `context.watch`.

**Tech Stack:** Flutter, provider, shared_preferences

---

## File Structure

- **Create:** `lib/providers/settings_provider.dart` — ChangeNotifier holding weightUnit + gradeSystem, reads/writes SharedPreferences
- **Modify:** `lib/main.dart` — register `SettingsProvider` in `MultiProvider`
- **Modify:** `lib/presentation/screens/root_screen.dart` — add preference controls to `SettingsDrawer` via `Consumer<SettingsProvider>`
- **Modify:** `lib/presentation/screens/profile_flow/profile_screen.dart` — remove local pref state/methods/UI, read from provider

---

### Task 1: Create `SettingsProvider`

**Files:**
- Create: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyWeightUnit  = 'pref_weight_unit';
  static const _keyGradeSystem = 'pref_grade_system';

  String _weightUnit  = 'kg';
  String _gradeSystem = 'fontainebleau';

  String get weightUnit  => _weightUnit;
  String get gradeSystem => _gradeSystem;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _weightUnit  = prefs.getString(_keyWeightUnit)  ?? 'kg';
    _gradeSystem = prefs.getString(_keyGradeSystem) ?? 'fontainebleau';
    notifyListeners();
  }

  Future<void> setWeightUnit(String unit) async {
    _weightUnit = unit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeightUnit, unit);
  }

  Future<void> setGradeSystem(String system) async {
    _gradeSystem = system;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGradeSystem, system);
  }
}
```

Note: `notifyListeners()` fires before the `await prefs.setString` so the UI updates instantly (same feel as the original `setState`).

- [ ] **Step 2: Commit**

```bash
git add lib/providers/settings_provider.dart
git commit -m "feat: add SettingsProvider for weight unit and grade system prefs"
```

---

### Task 2: Register `SettingsProvider` in `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import**

Add alongside the other provider imports:
```dart
import 'package:flash_forward/providers/settings_provider.dart';
```

- [ ] **Step 2: Add to `MultiProvider` list**

```dart
ChangeNotifierProvider(create: (context) => SettingsProvider()..init()),
```

The `..init()` cascade fires immediately on construction so prefs are loaded before any widget consumes them.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register SettingsProvider in MultiProvider"
```

---

### Task 3: Add preference controls to `SettingsDrawer`

**Files:**
- Modify: `lib/presentation/screens/root_screen.dart`

- [ ] **Step 1: Add import**

```dart
import 'package:flash_forward/providers/settings_provider.dart';
```

- [ ] **Step 2: Replace the `build` method of `SettingsDrawer`**

Replace the entire `build` method body with:

```dart
@override
Widget build(BuildContext context) {
  return Drawer(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text('Preferences', style: context.titleMedium),
          ),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weight unit', style: context.bodyMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'kg',  label: Text('kg')),
                      ButtonSegment(value: 'lbs', label: Text('lbs')),
                    ],
                    selected: {settings.weightUnit},
                    onSelectionChanged: (s) => settings.setWeightUnit(s.first),
                  ),
                  const SizedBox(height: 20),
                  Text('Grade system', style: context.bodyMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'fontainebleau', label: Text('Fontainebleau')),
                      ButtonSegment(value: 'vscale',        label: Text('V-scale')),
                    ],
                    selected: {settings.gradeSystem},
                    onSelectionChanged: (s) => settings.setGradeSystem(s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Past entries use their stored system and will still display correctly.',
                    style: context.bodyMedium.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Data', style: context.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded),
            title: Text('Clear logs', style: context.bodyMedium),
            onTap: () => _showClearLogsPopUp(context),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Account', style: context.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text('Sign out', style: context.bodyMedium),
            onTap: () => _signOut(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_rounded),
            title: Text('Delete account', style: context.bodyMedium),
            onTap: () => _deleteAccount(context),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/root_screen.dart
git commit -m "feat: add preference controls to SettingsDrawer"
```

---

### Task 4: Simplify `profile_screen.dart`

**Files:**
- Modify: `lib/presentation/screens/profile_flow/profile_screen.dart`

- [ ] **Step 1: Swap imports**

Remove:
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Add:
```dart
import 'package:flash_forward/providers/settings_provider.dart';
```

- [ ] **Step 2: Remove local state fields**

Delete these two fields from `_ProfileScreenState`:
```dart
String _weightUnit = 'kg';
String _gradeSystem = 'fontainebleau';
```

- [ ] **Step 3: Remove `initState`, `_loadPrefs`, `_setWeightUnit`, `_setGradeSystem`**

Delete all four of these methods entirely. `initState` no longer needs an override.

- [ ] **Step 4: Read settings from provider at top of `build`**

Inside `build`, after `Consumer<AuthProvider>` opens, add:
```dart
final settings = context.watch<SettingsProvider>();
```

- [ ] **Step 5: Update chart usages**

Replace `_gradeSystem` with `settings.gradeSystem`:
```dart
gradeSystem: settings.gradeSystem == 'fontainebleau'
    ? GradeSystem.fontainebleau
    : GradeSystem.vscale,
```

Replace `unit: _weightUnit` with `unit: settings.weightUnit`.

- [ ] **Step 6: Remove the Preferences UI section from `build`**

Delete this entire block:
```dart
// ── Preferences ───────────────────────────────────────────────────
const SizedBox(height: 32),
Text('Preferences', style: context.h3),
const SizedBox(height: 16),
Text('Weight unit', style: context.titleMedium),
const SizedBox(height: 8),
SegmentedButton<String>( ... weight unit ... ),
const SizedBox(height: 20),
Text('Grade system', style: context.titleMedium),
const SizedBox(height: 8),
SegmentedButton<String>( ... grade system ... ),
const SizedBox(height: 6),
Text('Past entries use their stored system...'),
const SizedBox(height: 32),
```

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/profile_flow/profile_screen.dart
git commit -m "refactor: remove local pref state from ProfileScreen, read from SettingsProvider"
```
