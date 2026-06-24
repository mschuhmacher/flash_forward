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

  static const _keyOnboardingSessionSelectComplete =
      'pref_onboarding_session_select_complete';
  static const _keyOnboardingSessionActiveComplete =
      'pref_onboarding_session_active_complete';
  static const _keyOnboardingCatalogComplete =
      'pref_onboarding_catalog_complete';
  static const _keyOnboardingResetRequested =
      'pref_onboarding_reset_requested';

  String _weightUnit = 'kg';
  String _gradeSystem = 'fontainebleau';
  SoundMode _soundMode = SoundMode.soundsOnly;
  bool _restOvertimeOnBackground = false;
  bool _onboardingSessionSelectComplete = false;
  bool _onboardingSessionActiveComplete = false;
  bool _onboardingCatalogComplete = false;
  bool _onboardingResetRequested = false;

  String get weightUnit => _weightUnit;
  String get gradeSystem => _gradeSystem;
  SoundMode get soundMode => _soundMode;
  bool get restOvertimeOnBackground => _restOvertimeOnBackground;
  bool get onboardingSessionSelectComplete => _onboardingSessionSelectComplete;
  bool get onboardingSessionActiveComplete => _onboardingSessionActiveComplete;
  bool get onboardingCatalogComplete => _onboardingCatalogComplete;
  bool get onboardingResetRequested => _onboardingResetRequested;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _weightUnit = prefs.getString(_keyWeightUnit) ?? 'kg';
    _gradeSystem = prefs.getString(_keyGradeSystem) ?? 'fontainebleau';
    final storedSoundMode = prefs.getString(_keySoundMode);
    _soundMode =
        storedSoundMode != null
            ? SoundMode.values.byName(storedSoundMode)
            : SoundMode.soundsOnly;
    _restOvertimeOnBackground = prefs.getBool(_keyOvertime) ?? false;
    _onboardingSessionSelectComplete =
        prefs.getBool(_keyOnboardingSessionSelectComplete) ?? false;
    _onboardingSessionActiveComplete =
        prefs.getBool(_keyOnboardingSessionActiveComplete) ?? false;
    _onboardingCatalogComplete =
        prefs.getBool(_keyOnboardingCatalogComplete) ?? false;

    // The reset toggle is transient: always start as "not requested" on
    // app launch, regardless of what was persisted last session.
    _onboardingResetRequested = false;
    await prefs.setBool(_keyOnboardingResetRequested, false);

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

  Future<void> markOnboardingSessionSelectComplete() async {
    _onboardingSessionSelectComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingSessionSelectComplete, true);
  }

  Future<void> markOnboardingSessionActiveComplete() async {
    _onboardingSessionActiveComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingSessionActiveComplete, true);
  }

  Future<void> markOnboardingCatalogComplete() async {
    _onboardingCatalogComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingCatalogComplete, true);
  }

  Future<void> enableOnboarding() async {
    _onboardingSessionSelectComplete = false;
    _onboardingSessionActiveComplete = false;
    _onboardingCatalogComplete = false;
    _onboardingResetRequested = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingSessionSelectComplete, false);
    await prefs.setBool(_keyOnboardingSessionActiveComplete, false);
    await prefs.setBool(_keyOnboardingCatalogComplete, false);
    await prefs.setBool(_keyOnboardingResetRequested, true);
  }

  Future<void> disableOnboarding() async {
    _onboardingSessionSelectComplete = true;
    _onboardingSessionActiveComplete = true;
    _onboardingCatalogComplete = true;
    _onboardingResetRequested = false;

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingSessionSelectComplete, true);
    await prefs.setBool(_keyOnboardingSessionActiveComplete, true);
    await prefs.setBool(_keyOnboardingCatalogComplete, true);
    await prefs.setBool(_keyOnboardingResetRequested, false);
  }
}
