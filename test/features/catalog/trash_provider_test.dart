import 'dart:io';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/core/uuid.dart';
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

Exercise _exercise({required String id, String title = 'Ex'}) =>
    Exercise(id: id, title: title, description: 'd', label: 'push');

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
}) => TrashEntry.workout(
  workout: _workout(id: id, title: title),
  deletedAt: deletedAt ?? DateTime(2025, 1, 1),
);

void main() {
  late Directory tmpDir;
  late CatalogProvider catalog;
  late SyncStatusProvider syncStatus;
  late TrashProvider trash;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('trash_provider_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    catalog = CatalogProvider();
    syncStatus = SyncStatusProvider();
    trash = TrashProvider(catalog: catalog, syncStatus: syncStatus);
    // Attach so the catalog's merged-list getters see trash changes —
    // tests that assert via catalog.presetWorkouts etc. need this.
    catalog.attachTrashProvider(trash);
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('fork on delete-of-a-default', () {
    test('deleting a never-customized default trashes a UUID-bearing fork', () async {
      catalog.debugSeedDefaults(sessions: [_session(id: 'projecting-session')]);
      await trash.deleteToTrash(id: 'projecting-session', kind: TrashKind.session);

      final entry = trash.trashedItems.single;
      expect(isUuid(entry.id), isTrue);
      expect((entry.payload as Session).templateId, 'projecting-session');
      expect(catalog.presetSessions.any((s) => s.id == 'projecting-session'),
          isFalse);
    });

    test('deleting an already-forked item keeps its UUID id', () async {
      catalog.debugSeedDefaults(workouts: [_workout(id: 'cat-w')]);
      await catalog.upsertWorkout(_workout(id: 'cat-w', title: 'Mine'));
      final fork =
          catalog.presetWorkouts.firstWhere((w) => w.templateId == 'cat-w');
      await trash.deleteToTrash(id: fork.id, kind: TrashKind.workout);

      expect(trash.trashedItems.single.id, fork.id);
      expect((trash.trashedItems.single.payload as Workout).templateId, 'cat-w');
    });
  });

  group('restore screen data', () {
    test('entriesByRecency sorts newest-first and flags defaults', () {
      final userE =
          TrashEntry.session(session: _session(id: 'u-1'), deletedAt: DateTime(2026, 6, 1));
      final defE = TrashEntry.session(
        session: _session(id: 'x').copyWith(id: 'fork', templateId: 'cat-s'),
        deletedAt: DateTime(2026, 6, 5),
      );
      trash.debugSeedTrash([userE, defE]);

      final view = trash.entriesByRecency;
      expect(view.first.entry.id, 'fork'); // newest first
      expect(view.first.isDefault, isTrue);
      expect(view.last.entry.id, 'u-1');
      expect(view.last.isDefault, isFalse);
    });

    test('restoreAllDefaults restores every deleted default', () async {
      catalog.debugSeedDefaults(
        sessions: [_session(id: 'cat-s1'), _session(id: 'cat-s2')],
      );
      await trash.deleteToTrash(id: 'cat-s1', kind: TrashKind.session);
      await trash.deleteToTrash(id: 'cat-s2', kind: TrashKind.session);
      expect(trash.deletedDefaults.length, 2);

      await trash.restoreAllDefaults();

      expect(trash.trashedItems, isEmpty);
      // Both defaults are restored (as forks shadowing the stock defaults).
      expect(catalog.presetSessions.where((s) => s.templateId == 'cat-s1'), hasLength(1));
      expect(catalog.presetSessions.where((s) => s.templateId == 'cat-s2'), hasLength(1));
    });
  });

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
      await catalog.upsertWorkout(_workout(id: 'w-1', title: 'My Workout'));

      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      expect(catalog.presetUserWorkoutsIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 'w-1');
      expect(trash.trashedItems.single.kind, TrashKind.workout);
    });

    test('removes user exercise and adds to trashedItems', () async {
      await catalog.upsertExercise(
        _exercise(id: 'e-1', title: 'My Exercise'),
      );

      await trash.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      expect(catalog.presetUserExerciseIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 'e-1');
      expect(trash.trashedItems.single.kind, TrashKind.exercise);
    });

    test('removes user session and adds to trashedItems', () async {
      await catalog.upsertSession(_session(id: 's-1', title: 'My Session'));

      await trash.deleteToTrash(id: 's-1', kind: TrashKind.session);

      expect(catalog.presetUserSessionIDs, isEmpty);
      expect(trash.trashedItems, hasLength(1));
      expect(trash.trashedItems.single.id, 's-1');
      expect(trash.trashedItems.single.kind, TrashKind.session);
    });

    test('id never appears twice across userWorkouts and trash', () async {
      await catalog.upsertWorkout(_workout(id: 'w-1'));

      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      final userIds = catalog.presetUserWorkoutsIDs;
      final trashIds = trash.trashedItems.map((e) => e.id).toSet();
      expect(userIds.intersection(trashIds), isEmpty);
    });
  });

  group('restoreFromTrash', () {
    test('removes from trashedItems and adds to user list', () async {
      await catalog.upsertWorkout(_workout(id: 'w-1', title: 'Workout'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
      expect(trash.trashedItems, hasLength(1));

      await trash.restoreFromTrash('w-1');

      expect(trash.trashedItems, isEmpty);
      expect(catalog.presetUserWorkoutsIDs, contains('w-1'));
    });

    test('restores with overrideTitle when provided', () async {
      await catalog.upsertWorkout(_workout(id: 'w-1', title: 'Original'));
      await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);

      await trash.restoreFromTrash('w-1', overrideTitle: 'Renamed');

      final restored = catalog.presetWorkouts.firstWhere((w) => w.id == 'w-1');
      expect(restored.title, 'Renamed');
    });

    test('restores exercise with overrideTitle', () async {
      await catalog.upsertExercise(_exercise(id: 'e-1', title: 'Original'));
      await trash.deleteToTrash(id: 'e-1', kind: TrashKind.exercise);

      await trash.restoreFromTrash('e-1', overrideTitle: 'Renamed');

      final restored = catalog.presetExercises.firstWhere((e) => e.id == 'e-1');
      expect(restored.title, 'Renamed');
    });

    test('restores session with overrideTitle', () async {
      await catalog.upsertSession(_session(id: 's-1', title: 'Original'));
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

    test(
      'id never appears twice across userWorkouts and trash after restore',
      () async {
        await catalog.upsertWorkout(_workout(id: 'w-1'));
        await trash.deleteToTrash(id: 'w-1', kind: TrashKind.workout);
        await trash.restoreFromTrash('w-1');

        final userIds = catalog.presetUserWorkoutsIDs;
        final trashIds = trash.trashedItems.map((e) => e.id).toSet();
        expect(userIds.intersection(trashIds), isEmpty);
      },
    );
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
