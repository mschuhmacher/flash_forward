import 'dart:io';

import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Routes `getApplicationDocumentsPath()` to a temp dir so the file-backed
/// `TrashService` / `PresetLogger` read & write real files during tests.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

/// A wired-up catalog + trash environment backed by a temp directory.
///
/// `syncStatus` has no Supabase service attached, so all cloud calls are
/// skipped (local-only). The `TrashService` writes into [tmpDir], so
/// `deleteToTrash` / `restoreFromTrash` round-trip on disk exactly like
/// production — seed trash via `trash.deleteToTrash(...)`, NOT the
/// memory-only `debugSeedTrash`, when a test will later restore.
class CatalogTestEnv {
  CatalogTestEnv(this.tmpDir, this.catalog, this.syncStatus, this.trash);
  final Directory tmpDir;
  final CatalogProvider catalog;
  final SyncStatusProvider syncStatus;
  final TrashProvider trash;

  Future<void> dispose() async => tmpDir.delete(recursive: true);
}

/// Builds a [CatalogTestEnv] with the given default lists seeded.
/// Call `await env.dispose()` in tearDown.
Future<CatalogTestEnv> makeCatalogEnv({
  List<Session> sessions = const [],
  List<Workout> workouts = const [],
  List<Exercise> exercises = const [],
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final tmpDir = await Directory.systemTemp.createTemp('catalog_kit_');
  PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);

  final catalog = CatalogProvider()
    ..debugSeedDefaults(
      sessions: sessions,
      workouts: workouts,
      exercises: exercises,
    );
  final syncStatus = SyncStatusProvider();
  final trash = TrashProvider(catalog: catalog, syncStatus: syncStatus);
  catalog.attachTrashProvider(trash);
  return CatalogTestEnv(tmpDir, catalog, syncStatus, trash);
}

// ── Model factories ─────────────────────────────────────────────────────────
Session testSession({required String id, String title = 'S'}) =>
    Session(id: id, title: title, label: 'push', workouts: []);

Workout testWorkout({required String id, String title = 'W'}) => Workout(
  id: id,
  title: title,
  label: 'push',
  exercises: [],
  timeBetweenExercises: 60,
);

Exercise testExercise({required String id, String title = 'Ex'}) =>
    Exercise(id: id, title: title, description: 'd', label: 'push');
