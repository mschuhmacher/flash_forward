import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/features/auth/guest_mode_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to disabled when nothing was ever written', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await GuestModeStore.isEnabled(), false);
  });

  test('enable() persists true, disable() persists false', () async {
    SharedPreferences.setMockInitialValues({});

    await GuestModeStore.enable();
    expect(await GuestModeStore.isEnabled(), true);

    await GuestModeStore.disable();
    expect(await GuestModeStore.isEnabled(), false);
  });
}
