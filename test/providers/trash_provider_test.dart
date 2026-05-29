import 'dart:io';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flash_forward/providers/trash_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

Workout _workout({required String id, String title = 'W'}) => Workout(
      id: id,
      title: title,
      label: 'push',
      exercises: [],
      timeBetweenExercises: 60,
    );

TrashEntry _trashedWorkout({
  required String id,
  String title = 'W',
  DateTime? deletedAt,
}) =>
    TrashEntry.workout(
      workout: _workout(id: id, title: title),
      deletedAt: deletedAt ?? DateTime(2025, 1, 1),
    );

void main() {
  late Directory tmpDir;
  late PresetProvider catalog;
  late SyncStatusProvider syncStatus;
  late TrashProvider trash;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('trash_provider_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    catalog = PresetProvider();
    syncStatus = SyncStatusProvider();
    trash = TrashProvider(catalog: catalog, syncStatus: syncStatus);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('TrashProvider', () {
    test('trashedItems is empty on a fresh provider', () {
      expect(trash.trashedItems, isEmpty);
    });

    test('debugSeedTrash exposes seeded entries via trashedItems', () {
      trash.debugSeedTrash([
        _trashedWorkout(id: 'w-1', title: 'My Workout'),
        _trashedWorkout(id: 'w-2', title: 'Another'),
      ]);

      expect(trash.trashedItems, hasLength(2));
      expect(trash.trashedItems.first.id, 'w-1');
    });
  });
}
