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

TrashEntry _trashedExercise({
  required String id,
  String title = 'Ex',
  DateTime? deletedAt,
}) =>
    TrashEntry.exercise(
      exercise: _exercise(id: id, title: title),
      deletedAt: deletedAt ?? DateTime(2025, 1, 1),
    );

TrashEntry _trashedSession({
  required String id,
  String title = 'S',
  DateTime? deletedAt,
}) =>
    TrashEntry.session(
      session: _session(id: id, title: title),
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
    tmpDir = await Directory.systemTemp.createTemp('catalog_trash_filter_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    catalog = PresetProvider();
    syncStatus = SyncStatusProvider();
    trash = TrashProvider(catalog: catalog, syncStatus: syncStatus);
    // Catalog's merged-list getters read trashed ids from the attached
    // trash provider — without this attach, they'd see no trash.
    catalog.attachTrashProvider(trash);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('presetWorkouts / presetExercises / presetSessions trash filtering',
      () {
    test('trashed user workout hidden from presetWorkouts', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      expect(catalog.presetWorkouts.any((w) => w.id == 'w-1'), isFalse);
    });

    test('trashed default workout hidden from presetWorkouts', () {
      catalog.debugSeedDefaults(
        workouts: [_workout(id: 'def-w')],
      );
      trash.debugSeedTrash([_trashedWorkout(id: 'def-w')]);

      expect(catalog.presetWorkouts.any((w) => w.id == 'def-w'), isFalse);
    });

    test('trashed user exercise hidden from presetExercises', () async {
      await catalog.addPresetExercise(_exercise(id: 'e-1'));
      await trash.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      expect(catalog.presetExercises.any((e) => e.id == 'e-1'), isFalse);
    });

    test('trashed default exercise hidden from presetExercises', () {
      catalog.debugSeedDefaults(
        exercises: [_exercise(id: 'def-e')],
      );
      trash.debugSeedTrash([_trashedExercise(id: 'def-e')]);

      expect(catalog.presetExercises.any((e) => e.id == 'def-e'), isFalse);
    });

    test('trashed user session hidden from presetSessions', () async {
      await catalog.addPresetSession(_session(id: 's-1'));
      await trash.deleteToTrash(id: 's-1', kind: TrashKind.session);

      expect(catalog.presetSessions.any((s) => s.id == 's-1'), isFalse);
    });

    test('trashed default session hidden from presetSessions', () {
      catalog.debugSeedDefaults(
        sessions: [_session(id: 'def-s')],
      );
      trash.debugSeedTrash([_trashedSession(id: 'def-s')]);

      expect(catalog.presetSessions.any((s) => s.id == 'def-s'), isFalse);
    });

    test('restoring a trashed item brings it back to presetWorkouts', () async {
      await catalog.addPresetWorkout(_workout(id: 'w-1', title: 'W'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      expect(catalog.presetWorkouts.any((w) => w.id == 'w-1'), isFalse);

      await trash.restoreFromTrash('w-1');

      expect(catalog.presetWorkouts.any((w) => w.id == 'w-1'), isTrue);
    });

    test('non-trashed items remain visible alongside trashed ones', () {
      catalog.debugSeedDefaults(
        workouts: [_workout(id: 'w-visible'), _workout(id: 'w-trashed')],
      );
      trash.debugSeedTrash([_trashedWorkout(id: 'w-trashed')]);

      final ids = catalog.presetWorkouts.map((w) => w.id).toSet();
      expect(ids, contains('w-visible'));
      expect(ids, isNot(contains('w-trashed')));
    });

    test('trash kind filtering: trashed workout does not hide exercises', () {
      catalog.debugSeedDefaults(
        exercises: [_exercise(id: 'e-1')],
      );
      // Seed a trash entry for a workout with the same id as the exercise —
      // the kind guard must prevent cross-kind suppression.
      trash.debugSeedTrash([_trashedWorkout(id: 'e-1')]);

      expect(catalog.presetExercises.any((e) => e.id == 'e-1'), isTrue);
    });

    test('trashed default workout is removed from presetWorkouts on delete',
        () async {
      catalog.debugSeedDefaults(
        workouts: [_workout(id: 'def-w', title: 'Default Workout')],
      );

      await trash.deleteToTrash(id: 'def-w', kind: TrashKind.workout);

      expect(trash.trashedItems.single.id, 'def-w');
      expect(catalog.presetWorkouts.any((w) => w.id == 'def-w'), isFalse);
    });
  });
}
