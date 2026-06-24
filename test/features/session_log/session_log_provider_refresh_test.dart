import 'dart:io';

import 'package:flash_forward/core/nullable.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flash_forward/features/session_log/session_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/catalog_test_kit.dart';
import '../../support/fake_supabase_sync_service.dart';

/// Routes SessionLogger's file path to a temp dir (the kit's fake is private).
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('session_refresh_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  test('claims local sessions to the cloud preserving completedAt', () async {
    final completed = DateTime(2026, 6, 1, 10);
    final local =
        testSession(id: 'guest-1').copyWith(completedAt: Nullable(completed));
    await SessionLogger.logSession(local);

    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService();
    await provider.refreshAfterSignIn(fake);

    expect(fake.claimedSessions.map((s) => s.id), ['guest-1']);
    expect(fake.claimedCompletedAts, [completed]);
  });

  test('reloads loggedSessions from the cloud after the claim', () async {
    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService()
      ..cloudLoggedSessions = [testSession(id: 'cloud-1')];

    await provider.refreshAfterSignIn(fake);

    expect(provider.loggedSessions.map((s) => s.id), ['cloud-1']);
  });

  test('a failing claim is swallowed and the reload still proceeds', () async {
    await SessionLogger.logSession(testSession(id: 'guest-1'));
    final provider = SessionLogProvider();
    final fake = FakeSupabaseSyncService()
      ..throwOnLogCompletedSession = true
      ..cloudLoggedSessions = [testSession(id: 'cloud-1')];

    // Must not throw despite the claim failing.
    await provider.refreshAfterSignIn(fake);

    expect(provider.loggedSessions.map((s) => s.id), ['cloud-1']);
  });
}
