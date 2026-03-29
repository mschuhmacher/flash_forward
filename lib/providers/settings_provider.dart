import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
