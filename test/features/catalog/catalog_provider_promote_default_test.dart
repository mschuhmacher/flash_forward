import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/core/uuid.dart';

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

void main() {
  late Directory tmpDir;
  late CatalogProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('preset_shadow_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = CatalogProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('default-id helpers', () {
    test('isDefault*Id is true only for seeded default ids', () {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s')],
        workouts: [_workout(id: 'cat-w')],
        exercises: [_exercise(id: 'cat-e')],
      );
      expect(provider.isDefaultSessionId('cat-s'), isTrue);
      expect(provider.isDefaultWorkoutId('cat-w'), isTrue);
      expect(provider.isDefaultExerciseId('cat-e'), isTrue);
      expect(provider.isDefaultSessionId('11111111-1111-4111-8111-111111111111'),
          isFalse);
      expect(provider.isDefaultWorkoutId('cat-s'), isFalse);
    });
  });

  group('heal on load', () {
    test('healSlugIdUserItems re-ids slug-id user items to uuid + templateId',
        () async {
      provider.debugSeedUserSessions([
        _session(id: 'projecting-session', title: 'Customized'),
      ]);
      provider.debugSeedUserWorkouts([_workout(id: 'cat-w', title: 'W')]);

      await provider.healSlugIdUserItems();

      final s = provider.presetSessions.firstWhere((s) => s.title == 'Customized');
      expect(isUuid(s.id), isTrue);
      expect(s.templateId, 'projecting-session');
      final w = provider.presetWorkouts.firstWhere((w) => w.title == 'W');
      expect(isUuid(w.id), isTrue);
      expect(w.templateId, 'cat-w');
    });

    test('healSlugIdUserItems leaves already-uuid items untouched', () async {
      final uuid = '11111111-1111-4111-8111-111111111111';
      provider.debugSeedUserSessions([_session(id: uuid, title: 'Keep')]);

      await provider.healSlugIdUserItems();

      final s = provider.presetSessions.firstWhere((s) => s.title == 'Keep');
      expect(s.id, uuid);
      expect(s.templateId, isNull);
    });
  });

  group('fork on promote', () {
    test('promoting a stock default forks to a UUID with templateId = slug', () async {
      provider.debugSeedDefaults(sessions: [_session(id: 'cat-s', title: 'Default')]);
      await provider.upsertSession(_session(id: 'cat-s', title: 'Mine'));

      final saved = provider.presetSessions.firstWhere((s) => s.title == 'Mine');
      expect(saved.id, isNot('cat-s')); // forked
      expect(isUuid(saved.id), isTrue);
      expect(saved.templateId, 'cat-s'); // breadcrumb
      // stock default is hidden (shadowed by templateId)
      expect(provider.presetSessions.any((s) => s.id == 'cat-s'), isFalse);
    });

    test('upserting an already-forked item does not re-fork', () async {
      provider.debugSeedDefaults(sessions: [_session(id: 'cat-s', title: 'Default')]);
      await provider.upsertSession(_session(id: 'cat-s', title: 'First'));
      final fork = provider.presetSessions.firstWhere((s) => s.templateId == 'cat-s');
      // Re-upsert the forked (uuid) item.
      await provider.upsertSession(fork.copyWith(title: 'Edited'));

      expect(
        provider.presetSessions.where((s) => s.templateId == 'cat-s').length, 1);
      final after = provider.presetSessions.firstWhere((s) => s.templateId == 'cat-s');
      expect(after.id, fork.id); // same uuid, updated in place
      expect(after.title, 'Edited');
    });
  });

  group('shadow rules', () {
    test(
      'presetWorkouts: user copy with default id shadows the default',
      () async {
        provider.debugSeedDefaults(
          workouts: [_workout(id: 'cat-w', title: 'Default')],
        );
        await provider.upsertWorkout(_workout(id: 'cat-w', title: 'Mine'));

        final titles = provider.presetWorkouts.map((w) => w.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test(
      'presetExercises: user copy with default id shadows the default',
      () async {
        provider.debugSeedDefaults(
          exercises: [_exercise(id: 'cat-e', title: 'Default')],
        );
        await provider.upsertExercise(_exercise(id: 'cat-e', title: 'Mine'));

        final titles = provider.presetExercises.map((e) => e.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test(
      'presetSessions: user copy with default id shadows the default',
      () async {
        provider.debugSeedDefaults(
          sessions: [_session(id: 'cat-s', title: 'Default')],
        );
        await provider.upsertSession(_session(id: 'cat-s', title: 'Mine'));

        final titles = provider.presetSessions.map((s) => s.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test('non-shadowed defaults remain visible alongside user items', () async {
      provider.debugSeedDefaults(
        workouts: [
          _workout(id: 'cat-w1', title: 'Default 1'),
          _workout(id: 'cat-w2', title: 'Default 2'),
        ],
      );
      await provider.upsertWorkout(_workout(id: 'cat-w1', title: 'Mine'));
      await provider.upsertWorkout(_workout(id: 'user-only', title: 'Solo'));

      final titles = provider.presetWorkouts.map((w) => w.title).toSet();
      expect(titles, {'Default 2', 'Mine', 'Solo'});
    });
  });

  group('upsert*', () {
    test(
      'upsertWorkout: promotes default into user list and shadows it',
      () async {
        provider.debugSeedDefaults(
          workouts: [_workout(id: 'cat-w', title: 'Default')],
        );

        await provider.upsertWorkout(
          _workout(id: 'cat-w', title: 'Mine'),
        );

        final promoted =
            provider.presetWorkouts.where((w) => w.templateId == 'cat-w').single;
        expect(isUuid(promoted.id), isTrue); // forked to a UUID
        expect(provider.presetUserWorkoutsIDs.length, 1);
        final titles = provider.presetWorkouts.map((w) => w.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test('upsertWorkout: subsequent edit updates in place', () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );

      await provider.upsertWorkout(
        _workout(id: 'cat-w', title: 'First'),
      );
      await provider.upsertWorkout(
        _workout(id: 'cat-w', title: 'Second'),
      );

      final userTitles =
          provider.presetWorkouts
              .where((w) => w.templateId == 'cat-w')
              .map((w) => w.title)
              .toList();
      expect(userTitles, ['Second']);
      expect(provider.presetUserWorkoutsIDs.length, 1);
    });

    test('upsertWorkout: idempotent on retry', () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );

      final updated = _workout(id: 'cat-w', title: 'Mine');
      await provider.upsertWorkout(updated);
      await provider.upsertWorkout(updated);

      expect(provider.presetUserWorkoutsIDs.length, 1);
      expect(
        provider.presetWorkouts.where((w) => w.templateId == 'cat-w').single.title,
        'Mine',
      );
    });

    test(
      'upsertExercise: promotes default into user list and shadows it',
      () async {
        provider.debugSeedDefaults(
          exercises: [_exercise(id: 'cat-e', title: 'Default')],
        );

        await provider.upsertExercise(
          _exercise(id: 'cat-e', title: 'Mine'),
        );

        final promoted =
            provider.presetExercises.where((e) => e.templateId == 'cat-e').single;
        expect(isUuid(promoted.id), isTrue); // forked to a UUID
        expect(provider.presetUserExerciseIDs.length, 1);
        final titles = provider.presetExercises.map((e) => e.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test(
      'upsertExercise: subsequent edit updates in place',
      () async {
        provider.debugSeedDefaults(
          exercises: [_exercise(id: 'cat-e', title: 'Default')],
        );

        await provider.upsertExercise(
          _exercise(id: 'cat-e', title: 'First'),
        );
        await provider.upsertExercise(
          _exercise(id: 'cat-e', title: 'Second'),
        );

        final userTitles =
            provider.presetExercises
                .where((e) => e.templateId == 'cat-e')
                .map((e) => e.title)
                .toList();
        expect(userTitles, ['Second']);
        expect(provider.presetUserExerciseIDs.length, 1);
      },
    );

    test('upsertExercise: idempotent on retry', () async {
      provider.debugSeedDefaults(
        exercises: [_exercise(id: 'cat-e', title: 'Default')],
      );

      final updated = _exercise(id: 'cat-e', title: 'Mine');
      await provider.upsertExercise(updated);
      await provider.upsertExercise(updated);

      expect(provider.presetUserExerciseIDs.length, 1);
      expect(
        provider.presetExercises.where((e) => e.templateId == 'cat-e').single.title,
        'Mine',
      );
    });

    test(
      'upsertSession: promotes default into user list and shadows it',
      () async {
        provider.debugSeedDefaults(
          sessions: [_session(id: 'cat-s', title: 'Default')],
        );

        await provider.upsertSession(
          _session(id: 'cat-s', title: 'Mine'),
        );

        final promoted =
            provider.presetSessions.where((s) => s.templateId == 'cat-s').single;
        expect(isUuid(promoted.id), isTrue); // forked to a UUID
        expect(provider.presetUserSessionIDs.length, 1);
        final titles = provider.presetSessions.map((s) => s.title).toList();
        expect(titles, ['Mine']);
      },
    );

    test('upsertSession: subsequent edit updates in place', () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );

      await provider.upsertSession(
        _session(id: 'cat-s', title: 'First'),
      );
      await provider.upsertSession(
        _session(id: 'cat-s', title: 'Second'),
      );

      final userTitles =
          provider.presetSessions
              .where((s) => s.templateId == 'cat-s')
              .map((s) => s.title)
              .toList();
      expect(userTitles, ['Second']);
      expect(provider.presetUserSessionIDs.length, 1);
    });

    test('upsertSession: idempotent on retry', () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );

      final updated = _session(id: 'cat-s', title: 'Mine');
      await provider.upsertSession(updated);
      await provider.upsertSession(updated);

      expect(provider.presetUserSessionIDs.length, 1);
      expect(
        provider.presetSessions.where((s) => s.templateId == 'cat-s').single.title,
        'Mine',
      );
    });
  });
}
