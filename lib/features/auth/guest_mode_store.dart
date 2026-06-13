import 'package:shared_preferences/shared_preferences.dart';

class GuestModeStore {
  static const _keyGuestMode = 'pref_guest_mode';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGuestMode) ?? false;
  }

  static Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, true);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestMode, false);
  }
}
