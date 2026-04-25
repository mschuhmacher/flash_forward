import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundMode { both, soundsOnly, notificationsOnly, none }

/// Responsibilities:
/// - Holds in-memory state for user preferences (weight unit, grade system).
/// - Provides getters for UI to read current preferences.
/// - Persists changes to SharedPreferences.
/// - Notifies listeners when preferences change.
///
/// Why:
/// Preferences are read in ProfileScreen (for chart display) and written in
/// SettingsDrawer (which lives outside ProfileScreen's widget tree). A shared
/// provider avoids duplicating state and keeps both widgets in sync.

class SettingsProvider extends ChangeNotifier {
  static const _keyWeightUnit = 'pref_weight_unit';
  static const _keyGradeSystem = 'pref_grade_system';
  static const _keySoundMode = 'pref_sound_mode';
  static const _keyOvertime = 'pref_overtime';

  String _weightUnit = 'kg';
  String _gradeSystem = 'fontainebleau';
  SoundMode _soundMode = SoundMode.soundsOnly;
  bool _restOvertimeOnBackground = false;

  String get weightUnit => _weightUnit;
  String get gradeSystem => _gradeSystem;
  SoundMode get soundMode => _soundMode;
  bool get restOvertimeOnBackground => _restOvertimeOnBackground;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _weightUnit = prefs.getString(_keyWeightUnit) ?? 'kg';
    _gradeSystem = prefs.getString(_keyGradeSystem) ?? 'fontainebleau';
    final storedSoundMode = prefs.getString(_keySoundMode);
    _soundMode =
        storedSoundMode != null ? SoundMode.values.byName(storedSoundMode) : SoundMode.soundsOnly;
    _restOvertimeOnBackground = prefs.getBool(_keyOvertime) ?? false;
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

  Future<void> setSoundMode(SoundMode mode) async {
    _soundMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySoundMode, mode.name);
  }

  Future<void> setRestOvertimeOnBackground(bool value) async {
    _restOvertimeOnBackground = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOvertime, value);
  }
}
