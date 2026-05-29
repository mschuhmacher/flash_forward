import 'dart:io';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
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

Exercise _exercise({required String id, String title = 'Ex'}) => Exercise(
      id: id,
      title: title,
      description: 'd',
      label: 'push',
    );

Workout _workout({required String id, String title = 'W'}) => Workout(
      id: id,
      title: title,
      label: 'push',
      exercises: [],
      timeBetweenExercises: 60,
    );

Session _session({required String id, String title = 'S'}) =>
    Session(id: id, title: title, label: 'push', workouts: []);

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
    // Attach so the catalog's merged-list getters see trash changes —
    // tests that assert via catalog.presetWorkouts etc. need this.
    catalog.attachTrashProvider(trash);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('trashedItems getter', () {
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

    test('returns unmodifiable view of seeded entries', () {
      final entry = _trashedWorkout(id: 'w-1');
      trash.debugSeedTrash([entry]);

      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 'w-1');
      expect(
        () => (trash.trashedItems as List).add(entry),
        throwsUnsupportedError,
      );
    });
  });

  group('deleteToTrash', () {
    test('removes user workout and adds to trashedItems', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1', title: 'My Workout'));

      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      expect(catalog.presetUserWorkoutsIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 'w-1');
      expect(trash.trashedItems.single.kind, TrashKind.workout);
    });

    test('removes user exercise and adds to trashedItems', () async {
      await catalog
          .addPresetExercise(_exercise(id: 'e-1', title: 'My Exercise'));

      await trash.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      expect(catalog.presetUserExerciseIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 'e-1');
      expect(trash.trashedItems.single.kind, TrashKind.exercise);
    });

    test('removes user session and adds to trashedItems', () async {
      await catalog.addPresetSession(_session(id: 's-1', title: 'My Session'));

      await trash.deleteToTrash(id: 's-1', kind: TrashKind.session);

      expect(catalog.presetUserSessionIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 's-1');
      expect(trash.trashedItems.single.kind, TrashKind.session);
    });

    test('id never appears twice across userWorkouts and trash', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1'));

      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      final userIds = catalog.presetUserWorkoutsIDs;
      final trashIds = trash.trashedItems.map((e) => e.id).toSet();
      expect(userIds.intersection(trashIds), isEmpty);
    });
  });

  group('restoreFromTrash', () {
    test('removes from trashedItems and adds to user list', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1', title: 'Workout'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      expect(trash.trashedItems, hasLength(1));

      await trash.restoreFromTrash('w-1');

      expect(trash.trashedItems, isEmpty);
      expect(catalog.presetUserWorkoutsIDs, contains('w-1'));
    });

    test('restores with overrideTitle when provided', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1', title: 'Original'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      await trash.restoreFromTrash('w-1', overrideTitle: 'Renamed');

      final restored = catalog.presetWorkouts.firstWhere((w) => w.id == 'w-1');
      expect(restored.title, 'Renamed');
    });

    test('restores exercise with overrideTitle', () async {
      await catalog.addPresetExercise(_exercise(id: 'e-1', title: 'Original'));
      await trash.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      await trash.restoreFromTrash('e-1', overrideTitle: 'Renamed');

      final restored = catalog.presetExercises.firstWhere((e) => e.id == 'e-1');
      expect(restored.title, 'Renamed');
    });

    test('restores session with overrideTitle', () async {
      await catalog.addPresetSession(_session(id: 's-1', title: 'Original'));
      await trash.deleteToTrash(id: 's-1', kind: TrashKind.session);

      await trash.restoreFromTrash('s-1', overrideTitle: 'Renamed');

      final restored = catalog.presetSessions.firstWhere((s) => s.id == 's-1');
      expect(restored.title, 'Renamed');
    });

    test('no-op when id not in trash', () async {
      await trash.restoreFromTrash('nonexistent');
      expect(trash.trashedItems, isEmpty);
      expect(catalog.presetUserWorkoutsIDs, isEmpty);
    });

    test('id never appears twice across userWorkouts and trash after restore',
        () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      await trash.restoreFromTrash('w-1');

      final userIds = catalog.presetUserWorkoutsIDs;
      final trashIds = trash.trashedItems.map((e) => e.id).toSet();
      expect(userIds.intersection(trashIds), isEmpty);
    });
  });

  group('liftToCatalog', () {
    test('adds workout to user catalog', () async {
      final w = _workout(id: 'w-new', title: 'Fresh');

      await trash.liftToCatalog(item: w, kind: TrashKind.workout);

      expect(catalog.presetUserWorkoutsIDs, contains('w-new'));
      expect(
        catalog.presetWorkouts.firstWhere((x) => x.id == 'w-new').title,
        'Fresh',
      );
    });

    test('adds exercise to user catalog', () async {
      final e = _exercise(id: 'e-new', title: 'Fresh');

      await trash.liftToCatalog(item: e, kind: TrashKind.exercise);

      expect(catalog.presetUserExerciseIDs, contains('e-new'));
    });

    test('adds session to user catalog', () async {
      final s = _session(id: 's-new', title: 'Fresh');

      await trash.liftToCatalog(item: s, kind: TrashKind.session);

      expect(catalog.presetUserSessionIDs, contains('s-new'));
    });

    test('overrideTitle is applied', () async {
      final w = _workout(id: 'w-new', title: 'Original');

      await trash.liftToCatalog(
        item: w,
        kind: TrashKind.workout,
        overrideTitle: 'Renamed',
      );

      expect(
        catalog.presetWorkouts.firstWhere((x) => x.id == 'w-new').title,
        'Renamed',
      );
    });

    test('overrideId is applied', () async {
      final w = _workout(id: 'old-id', title: 'W');

      await trash.liftToCatalog(
        item: w,
        kind: TrashKind.workout,
        overrideId: 'new-id',
      );

      expect(catalog.presetUserWorkoutsIDs, contains('new-id'));
      expect(catalog.presetUserWorkoutsIDs, isNot(contains('old-id')));
    });
  });

  group('reset clears trash', () {
    test('reset empties trashedItems', () {
      trash.debugSeedTrash([_trashedWorkout(id: 'w-1')]);
      expect(trash.trashedItems, hasLength(1));

      trash.reset();

      expect(trash.trashedItems, isEmpty);
    });
  });
}
