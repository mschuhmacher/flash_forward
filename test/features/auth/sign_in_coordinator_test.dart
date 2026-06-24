import 'package:flash_forward/features/auth/guest_mode_store.dart';
import 'package:flash_forward/features/auth/sign_in_coordinator.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/catalog_test_kit.dart';
import '../../support/fake_supabase_sync_service.dart';

const _uuid = '11111111-1111-4111-8111-111111111111';

void main() {
  test('initForGuest wires catalog locally and never builds a service',
      () async {
    SharedPreferences.setMockInitialValues({});
    final env = await makeCatalogEnv();
    final sessionLog = SessionLogProvider();
    final coordinator = SignInCoordinator(
      catalogProvider: env.catalog,
      trashProvider: env.trash,
      sessionLogProvider: sessionLog,
      syncStatusProvider: env.syncStatus,
      serviceFactory: (_) => fail('guest init must not build a service'),
    );

    await coordinator.initForGuest();

    expect(env.syncStatus.service, isNull);
    expect(env.catalog.isInitialized, true);
    expect(sessionLog.isInitialized, true);
    await env.dispose();
  });

  test('onSignedIn attaches the service, surfaces cloud data, clears the flag',
      () async {
    SharedPreferences.setMockInitialValues({'pref_guest_mode': true});
    final env = await makeCatalogEnv();
    final sessionLog = SessionLogProvider();
    final fake = FakeSupabaseSyncService()
      ..cloudUserSessions = [testSession(id: _uuid)];
    final coordinator = SignInCoordinator(
      catalogProvider: env.catalog,
      trashProvider: env.trash,
      sessionLogProvider: sessionLog,
      syncStatusProvider: env.syncStatus,
      serviceFactory: (_) => fake,
    );
    await coordinator.initForGuest();

    await coordinator.onSignedIn('user-1');

    expect(env.syncStatus.service, same(fake));
    expect(env.catalog.presetSessions.map((s) => s.id), contains(_uuid));
    expect(await GuestModeStore.isEnabled(), false);
    await env.dispose();
  });
}
