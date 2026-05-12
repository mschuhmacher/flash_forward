import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_provider.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

Exercise _e({required String id, String? templateId, int sets = 3}) =>
    Exercise(
      id: id,
      templateId: templateId,
      title: id,
      description: 'd',
      label: 'push',
      sets: sets,
    );

SupersetConfig _ss({
  required String id,
  required List<String> exerciseIds,
  int restSeconds = 10,
  int? supersetSets,
}) =>
    SupersetConfig(
      id: id,
      exerciseIds: exerciseIds,
      restSeconds: restSeconds,
      supersetSets: supersetSets,
    );

Workout _w({
  required String id,
  String? templateId,
  String title = 'W',
  required List<Exercise> exercises,
  List<SupersetConfig> supersets = const [],
}) =>
    Workout(
      id: id,
      templateId: templateId,
      title: title,
      label: 'push',
      exercises: exercises,
      timeBetweenExercises: 60,
      supersets: supersets,
    );

Session _s(
        {required String id,
        String title = 'S',
        required List<Workout> workouts}) =>
    Session(id: id, title: title, label: 'push', workouts: workouts);

void main() {
  late Directory tmpDir;
  late PresetProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('superset_propagate_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  test('1. workout edit propagates with supersets intact + independence',
      () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 4);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);

    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));
    await provider.addPresetSession(
        _s(id: 's2', workouts: [embedded.deepCopy(keepId: true)]));

    final updated = embedded.copyWith(timeBetweenExercises: 999);
    await provider.propagateWorkoutToSessionTemplates(updated);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    final s2 = provider.presetSessions.firstWhere((x) => x.id == 's2');

    expect(s1.workouts.single.supersets, hasLength(1));
    expect(s1.workouts.single.supersets.single.id, 'ss1');
    expect(s2.workouts.single.supersets, hasLength(1));
    expect(s2.workouts.single.supersets.single.id, 'ss1');

    // Independence: each session's superset is a separate Dart instance.
    expect(
      identical(s1.workouts.single.supersets.first,
          s2.workouts.single.supersets.first),
      isFalse,
    );

    expect(s1.workouts.single.timeBetweenExercises, 999);
    expect(s2.workouts.single.timeBetweenExercises, 999);
  });

  test('2. exercise edit does not drop the parent workout supersets',
      () async {
    final exA = _e(id: 'ex-a', sets: 3);
    final exB = _e(id: 'ex-b', sets: 3);
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 3);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));

    final updatedExA = exA.copyWith(title: 'Squat v2');
    await provider.propagateExerciseToSessionTemplates(updatedExA);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    final w = s1.workouts.single;
    expect(w.supersets, hasLength(1));
    expect(w.supersets.single.id, 'ss1');
    expect(w.supersets.single.exerciseIds, ['ex-a', 'ex-b']);
    expect(w.supersets.single.supersetSets, 3);
    // The exercise itself updated.
    expect(w.exercises.firstWhere((e) => e.id == 'ex-a').title, 'Squat v2');
  });

  test('3. editing the supersets list propagates the new list', () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final exC = _e(id: 'ex-c');
    final exD = _e(id: 'ex-d');
    final ss1 = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b']);
    final embedded = _w(
        id: 'cat-w', exercises: [exA, exB, exC, exD], supersets: [ss1]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));
    await provider.addPresetSession(
        _s(id: 's2', workouts: [embedded.deepCopy(keepId: true)]));

    final ss2 = _ss(id: 'ss2', exerciseIds: ['ex-c', 'ex-d']);
    final updated = embedded.copyWith(supersets: [ss1, ss2]);
    await provider.propagateWorkoutToSessionTemplates(updated);

    for (final id in ['s1', 's2']) {
      final s = provider.presetSessions.firstWhere((x) => x.id == id);
      expect(
        s.workouts.single.supersets.map((x) => x.id).toSet(),
        {'ss1', 'ss2'},
        reason: 'session $id missing supersets after propagation',
      );
    }
  });

  test('4. second-pass propagation preserves supersets', () async {
    final exA = _e(id: 'ex-a');
    final exB = _e(id: 'ex-b');
    final ss = _ss(id: 'ss1', exerciseIds: ['ex-a', 'ex-b']);
    final catalogW = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    final embeddedA = _w(
      id: 'cat-w',
      exercises: [
        exA.deepCopy(keepId: true),
        exB.deepCopy(keepId: true),
      ],
      supersets: [ss.copyWith()],
    );
    final embeddedB = _w(
      id: 'cat-w',
      exercises: [
        exA.deepCopy(keepId: true),
        exB.deepCopy(keepId: true),
      ],
      supersets: [ss.copyWith()],
    );
    final sA = _s(id: 's-a', workouts: [embeddedA]);
    final sB = _s(id: 's-b', workouts: [embeddedB]);
    provider.debugSeedDefaults(workouts: [catalogW], sessions: [sA, sB]);

    await provider.propagateWorkoutToSessionTemplates(
      catalogW.copyWith(timeBetweenExercises: 999),
    );
    await provider.propagateWorkoutToSessionTemplates(
      catalogW.copyWith(timeBetweenExercises: 999, title: 'New Title'),
    );

    for (final session in provider.presetSessions) {
      final w = session.workouts.single;
      expect(w.supersets, hasLength(1));
      expect(w.supersets.single.id, 'ss1');
      expect(w.title, 'New Title');
    }
  });

  test('5. supersetSets survives propagation', () async {
    final exA = _e(id: 'ex-a', sets: 3);
    final exB = _e(id: 'ex-b', sets: 4);
    final ss = _ss(
        id: 'ss1', exerciseIds: ['ex-a', 'ex-b'], supersetSets: 5);
    final embedded = _w(id: 'cat-w', exercises: [exA, exB], supersets: [ss]);
    await provider.addPresetSession(_s(id: 's1', workouts: [embedded]));

    final updated = embedded.copyWith(timeBetweenExercises: 90);
    await provider.propagateWorkoutToSessionTemplates(updated);

    final s1 = provider.presetSessions.firstWhere((x) => x.id == 's1');
    expect(s1.workouts.single.supersets.single.supersetSets, 5);
    expect(s1.workouts.single.timeBetweenExercises, 90);
  });
}
