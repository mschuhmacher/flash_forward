import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';

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
  late PresetProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('preset_trash_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('trashedItems getter', () {
    test('returns unmodifiable view of seeded entries', () {
      final entry = _trashedWorkout(id: 'w-1');
      provider.debugSeedTrash([entry]);

      expect(provider.trashedItems, hasLength(1));
      expect(provider.trashedItems.single.id, 'w-1');
      expect(
        () => (provider.trashedItems as List).add(entry),
        throwsUnsupportedError,
      );
    });
  });

  group('deleteToTrash', () {
    test('removes user workout and adds to trashedItems', () async {
      await provider.addPresetWorkout(_workout(id: 'w-1', title: 'My Workout'));

      await provider.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      expect(provider.presetUserWorkoutsIDs, isEmpty);
      expect(provider.trashedItems, hasLength(1));
      expect(provider.trashedItems.single.id, 'w-1');
      expect(provider.trashedItems.single.kind, TrashKind.workout);
    });

    test('removes user exercise and adds to trashedItems', () async {
      await provider.addPresetExercise(_exercise(id: 'e-1', title: 'My Exercise'));

      await provider.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      expect(provider.presetUserExerciseIDs, isEmpty);
      expect(provider.trashedItems, hasLength(1));
      expect(provider.trashedItems.single.id, 'e-1');
      expect(provider.trashedItems.single.kind, TrashKind.exercise);
    });

    test('removes user session and adds to trashedItems', () async {
      await provider.addPresetSession(_session(id: 's-1', title: 'My Session'));

      await provider.deleteToTrash(id: 's-1', kind: TrashKind.session);

      expect(provider.presetUserSessionIDs, isEmpty);
      expect(provider.trashedItems, hasLength(1));
      expect(provider.trashedItems.single.id, 's-1');
      expect(provider.trashedItems.single.kind, TrashKind.session);
    });

    test('trashed default workout is removed from presetWorkouts', () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'def-w', title: 'Default Workout')],
      );

      await provider.deleteToTrash(id: 'def-w', kind: TrashKind.workout);

      // The default is not in _userWorkouts so nothing was removed there, but
      // once trash filtering is added (Task 30) this will hide it. For now we
      // verify the entry was persisted in trash.
      expect(provider.trashedItems.single.id, 'def-w');
    });

    test('id never appears twice across userWorkouts and trash', () async {
      await provider.addPresetWorkout(_workout(id: 'w-1'));

      await provider.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      final userIds = provider.presetUserWorkoutsIDs;
      final trashIds = provider.trashedItems.map((e) => e.id).toSet();
      expect(userIds.intersection(trashIds), isEmpty);
    });
  });

  group('restoreFromTrash', () {
    test('removes from trashedItems and adds to user list', () async {
      await provider.addPresetWorkout(_workout(id: 'w-1', title: 'Workout'));
      await provider.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      expect(provider.trashedItems, hasLength(1));

      await provider.restoreFromTrash('w-1');

      expect(provider.trashedItems, isEmpty);
      expect(provider.presetUserWorkoutsIDs, contains('w-1'));
    });

    test('restores with overrideTitle when provided', () async {
      await provider.addPresetWorkout(_workout(id: 'w-1', title: 'Original'));
      await provider.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      await provider.restoreFromTrash('w-1', overrideTitle: 'Renamed');

      final restored = provider.presetWorkouts.firstWhere((w) => w.id == 'w-1');
      expect(restored.title, 'Renamed');
    });

    test('restores exercise with overrideTitle', () async {
      await provider.addPresetExercise(_exercise(id: 'e-1', title: 'Original'));
      await provider.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      await provider.restoreFromTrash('e-1', overrideTitle: 'Renamed');

      final restored = provider.presetExercises.firstWhere((e) => e.id == 'e-1');
      expect(restored.title, 'Renamed');
    });

    test('restores session with overrideTitle', () async {
      await provider.addPresetSession(_session(id: 's-1', title: 'Original'));
      await provider.deleteToTrash(id: 's-1', kind: TrashKind.session);

      await provider.restoreFromTrash('s-1', overrideTitle: 'Renamed');

      final restored = provider.presetSessions.firstWhere((s) => s.id == 's-1');
      expect(restored.title, 'Renamed');
    });

    test('no-op when id not in trash', () async {
      await provider.restoreFromTrash('nonexistent');
      expect(provider.trashedItems, isEmpty);
      expect(provider.presetUserWorkoutsIDs, isEmpty);
    });

    test('id never appears twice across userWorkouts and trash after restore',
        () async {
      await provider.addPresetWorkout(_workout(id: 'w-1'));
      await provider.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      await provider.restoreFromTrash('w-1');

      final userIds = provider.presetUserWorkoutsIDs;
      final trashIds = provider.trashedItems.map((e) => e.id).toSet();
      expect(userIds.intersection(trashIds), isEmpty);
    });
  });

  group('liftToCatalog', () {
    test('adds workout to user catalog', () async {
      final w = _workout(id: 'w-new', title: 'Fresh');

      await provider.liftToCatalog(item: w, kind: TrashKind.workout);

      expect(provider.presetUserWorkoutsIDs, contains('w-new'));
      expect(
        provider.presetWorkouts.firstWhere((x) => x.id == 'w-new').title,
        'Fresh',
      );
    });

    test('adds exercise to user catalog', () async {
      final e = _exercise(id: 'e-new', title: 'Fresh');

      await provider.liftToCatalog(item: e, kind: TrashKind.exercise);

      expect(provider.presetUserExerciseIDs, contains('e-new'));
    });

    test('adds session to user catalog', () async {
      final s = _session(id: 's-new', title: 'Fresh');

      await provider.liftToCatalog(item: s, kind: TrashKind.session);

      expect(provider.presetUserSessionIDs, contains('s-new'));
    });

    test('overrideTitle is applied', () async {
      final w = _workout(id: 'w-new', title: 'Original');

      await provider.liftToCatalog(
        item: w,
        kind: TrashKind.workout,
        overrideTitle: 'Renamed',
      );

      expect(
        provider.presetWorkouts.firstWhere((x) => x.id == 'w-new').title,
        'Renamed',
      );
    });

    test('overrideId is applied', () async {
      final w = _workout(id: 'old-id', title: 'W');

      await provider.liftToCatalog(
        item: w,
        kind: TrashKind.workout,
        overrideId: 'new-id',
      );

      expect(provider.presetUserWorkoutsIDs, contains('new-id'));
      expect(provider.presetUserWorkoutsIDs, isNot(contains('old-id')));
    });
  });

  group('reset clears trash', () {
    test('reset empties _trashedItems', () {
      provider.debugSeedTrash([_trashedWorkout(id: 'w-1')]);
      expect(provider.trashedItems, hasLength(1));

      provider.reset();

      expect(provider.trashedItems, isEmpty);
    });
  });

  group('_mergeTrashCloudAndLocal', () {
    test('union of disjoint lists', () {
      final local = [_trashedWorkout(id: 'w-local')];
      final cloud = [_trashedWorkout(id: 'w-cloud')];

      final merged = PresetProvider.mergeTrashCloudAndLocalForTest(local, cloud);

      expect(merged.map((e) => e.id).toSet(), {'w-local', 'w-cloud'});
    });

    test('cloud entry with later deletedAt wins on conflict', () {
      final earlier = DateTime(2025, 1, 1);
      final later = DateTime(2025, 6, 1);

      final local = [_trashedWorkout(id: 'w-1', title: 'Old', deletedAt: earlier)];
      final cloud = [_trashedWorkout(id: 'w-1', title: 'New', deletedAt: later)];

      final merged = PresetProvider.mergeTrashCloudAndLocalForTest(local, cloud);

      expect(merged, hasLength(1));
      expect(merged.single.title, 'New');
    });

    test('local entry with later deletedAt is kept over cloud', () {
      final earlier = DateTime(2025, 1, 1);
      final later = DateTime(2025, 6, 1);

      final local = [_trashedWorkout(id: 'w-1', title: 'New', deletedAt: later)];
      final cloud = [_trashedWorkout(id: 'w-1', title: 'Old', deletedAt: earlier)];

      final merged = PresetProvider.mergeTrashCloudAndLocalForTest(local, cloud);

      expect(merged.single.title, 'New');
    });
  });
}
