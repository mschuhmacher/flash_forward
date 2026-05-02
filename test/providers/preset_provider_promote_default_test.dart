import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
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

void main() {
  late Directory tmpDir;
  late PresetProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('preset_shadow_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('shadow rules', () {
    test('presetWorkouts: user copy with default id shadows the default',
        () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );
      await provider.addPresetWorkout(_workout(id: 'cat-w', title: 'Mine'));

      final titles = provider.presetWorkouts.map((w) => w.title).toList();
      expect(titles, ['Mine']);
    });

    test('presetExercises: user copy with default id shadows the default',
        () async {
      provider.debugSeedDefaults(
        exercises: [_exercise(id: 'cat-e', title: 'Default')],
      );
      await provider.addPresetExercise(_exercise(id: 'cat-e', title: 'Mine'));

      final titles = provider.presetExercises.map((e) => e.title).toList();
      expect(titles, ['Mine']);
    });

    test('presetSessions: user copy with default id shadows the default',
        () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );
      await provider.addPresetSession(_session(id: 'cat-s', title: 'Mine'));

      final titles = provider.presetSessions.map((s) => s.title).toList();
      expect(titles, ['Mine']);
    });

    test('non-shadowed defaults remain visible alongside user items',
        () async {
      provider.debugSeedDefaults(
        workouts: [
          _workout(id: 'cat-w1', title: 'Default 1'),
          _workout(id: 'cat-w2', title: 'Default 2'),
        ],
      );
      await provider.addPresetWorkout(_workout(id: 'cat-w1', title: 'Mine'));
      await provider.addPresetWorkout(_workout(id: 'user-only', title: 'Solo'));

      final titles = provider.presetWorkouts.map((w) => w.title).toSet();
      expect(titles, {'Default 2', 'Mine', 'Solo'});
    });
  });

  group('promoteAndUpdate*', () {
    test('promoteAndUpdateWorkout: promotes default into user list and shadows it',
        () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );

      await provider.promoteAndUpdateWorkout(
        _workout(id: 'cat-w', title: 'Mine'),
      );

      expect(provider.presetUserWorkoutsIDs, {'cat-w'});
      final titles = provider.presetWorkouts.map((w) => w.title).toList();
      expect(titles, ['Mine']);
    });

    test('promoteAndUpdateWorkout: subsequent edit updates in place', () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );

      await provider.promoteAndUpdateWorkout(
        _workout(id: 'cat-w', title: 'First'),
      );
      await provider.promoteAndUpdateWorkout(
        _workout(id: 'cat-w', title: 'Second'),
      );

      final userTitles = provider.presetWorkouts
          .where((w) => w.id == 'cat-w')
          .map((w) => w.title)
          .toList();
      expect(userTitles, ['Second']);
      expect(provider.presetUserWorkoutsIDs.length, 1);
    });

    test('promoteAndUpdateWorkout: idempotent on retry', () async {
      provider.debugSeedDefaults(
        workouts: [_workout(id: 'cat-w', title: 'Default')],
      );

      final updated = _workout(id: 'cat-w', title: 'Mine');
      await provider.promoteAndUpdateWorkout(updated);
      await provider.promoteAndUpdateWorkout(updated);

      expect(provider.presetUserWorkoutsIDs.length, 1);
      expect(
        provider.presetWorkouts.where((w) => w.id == 'cat-w').single.title,
        'Mine',
      );
    });

    test('promoteAndUpdateExercise: promotes default into user list and shadows it',
        () async {
      provider.debugSeedDefaults(
        exercises: [_exercise(id: 'cat-e', title: 'Default')],
      );

      await provider.promoteAndUpdateExercise(
        _exercise(id: 'cat-e', title: 'Mine'),
      );

      expect(provider.presetUserExerciseIDs, {'cat-e'});
      final titles = provider.presetExercises.map((e) => e.title).toList();
      expect(titles, ['Mine']);
    });

    test('promoteAndUpdateExercise: subsequent edit updates in place',
        () async {
      provider.debugSeedDefaults(
        exercises: [_exercise(id: 'cat-e', title: 'Default')],
      );

      await provider.promoteAndUpdateExercise(
        _exercise(id: 'cat-e', title: 'First'),
      );
      await provider.promoteAndUpdateExercise(
        _exercise(id: 'cat-e', title: 'Second'),
      );

      final userTitles = provider.presetExercises
          .where((e) => e.id == 'cat-e')
          .map((e) => e.title)
          .toList();
      expect(userTitles, ['Second']);
      expect(provider.presetUserExerciseIDs.length, 1);
    });

    test('promoteAndUpdateExercise: idempotent on retry', () async {
      provider.debugSeedDefaults(
        exercises: [_exercise(id: 'cat-e', title: 'Default')],
      );

      final updated = _exercise(id: 'cat-e', title: 'Mine');
      await provider.promoteAndUpdateExercise(updated);
      await provider.promoteAndUpdateExercise(updated);

      expect(provider.presetUserExerciseIDs.length, 1);
      expect(
        provider.presetExercises.where((e) => e.id == 'cat-e').single.title,
        'Mine',
      );
    });

    test('promoteAndUpdateSession: promotes default into user list and shadows it',
        () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );

      await provider.promoteAndUpdateSession(
        _session(id: 'cat-s', title: 'Mine'),
      );

      expect(provider.presetUserSessionIDs, {'cat-s'});
      final titles = provider.presetSessions.map((s) => s.title).toList();
      expect(titles, ['Mine']);
    });

    test('promoteAndUpdateSession: subsequent edit updates in place', () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );

      await provider.promoteAndUpdateSession(
        _session(id: 'cat-s', title: 'First'),
      );
      await provider.promoteAndUpdateSession(
        _session(id: 'cat-s', title: 'Second'),
      );

      final userTitles = provider.presetSessions
          .where((s) => s.id == 'cat-s')
          .map((s) => s.title)
          .toList();
      expect(userTitles, ['Second']);
      expect(provider.presetUserSessionIDs.length, 1);
    });

    test('promoteAndUpdateSession: idempotent on retry', () async {
      provider.debugSeedDefaults(
        sessions: [_session(id: 'cat-s', title: 'Default')],
      );

      final updated = _session(id: 'cat-s', title: 'Mine');
      await provider.promoteAndUpdateSession(updated);
      await provider.promoteAndUpdateSession(updated);

      expect(provider.presetUserSessionIDs.length, 1);
      expect(
        provider.presetSessions.where((s) => s.id == 'cat-s').single.title,
        'Mine',
      );
    });
  });
}
