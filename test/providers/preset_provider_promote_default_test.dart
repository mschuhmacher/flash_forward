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
}
