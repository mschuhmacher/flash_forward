import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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

Exercise _exercise({
  required String id,
  String? templateId,
  String title = 'Ex',
  int sets = 3,
}) =>
    Exercise(
      id: id,
      templateId: templateId,
      title: title,
      description: 'd',
      label: 'push',
      sets: sets,
    );

Workout _workout({
  required String id,
  String? templateId,
  String title = 'W',
  required List<Exercise> exercises,
}) =>
    Workout(
      id: id,
      templateId: templateId,
      title: title,
      label: 'push',
      exercises: exercises,
      timeBetweenExercises: 60,
    );

Session _session({
  required String id,
  String title = 'S',
  required List<Workout> workouts,
}) =>
    Session(id: id, title: title, label: 'push', workouts: workouts);

void main() {
  late Directory tmpDir;
  late PresetProvider provider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('preset_propagate_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
    // Skip init() — we don't need defaults or sync. Seed via the public
    // addPresetSession() which routes through the same persistence path used
    // by the propagation methods.
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('sessionTemplatesUsingWorkout', () {
    test('matches by direct id (catalog workout dropped into a template)',
        () async {
      final w = _workout(id: 'cat-w', exercises: []);
      await provider.addPresetSession(_session(id: 's1', workouts: [w]));
      await provider.addPresetSession(_session(id: 's2', workouts: []));

      final result = provider.sessionTemplatesUsingWorkout('cat-w');

      expect(result.map((s) => s.id), ['s1']);
    });

    test('matches by templateId (deep-copied workout in a template)', () async {
      final embedded = _workout(
          id: 'instance-w', templateId: 'cat-w', exercises: []);
      await provider
          .addPresetSession(_session(id: 's1', workouts: [embedded]));

      final result = provider.sessionTemplatesUsingWorkout('cat-w');

      expect(result.map((s) => s.id), ['s1']);
    });

    test('returns empty when no template uses the workout', () async {
      await provider.addPresetSession(_session(id: 's1', workouts: []));

      expect(provider.sessionTemplatesUsingWorkout('nope'), isEmpty);
    });
  });

  group('sessionTemplatesUsingExercise & sessionWorkoutPathsUsingExercise', () {
    test('finds nested exercise occurrences across templates', () async {
      final ex1 = _exercise(id: 'cat-e');
      final ex1Copy =
          _exercise(id: 'instance-e', templateId: 'cat-e'); // deep-copied
      final ex2 = _exercise(id: 'other-e');

      final w1 = _workout(id: 'w1', title: 'Squats', exercises: [ex1, ex2]);
      final w2 = _workout(id: 'w2', title: 'Press', exercises: [ex1Copy]);
      final w3 = _workout(id: 'w3', title: 'Cardio', exercises: [ex2]);

      await provider.addPresetSession(
          _session(id: 's1', title: 'Leg day', workouts: [w1]));
      await provider.addPresetSession(
          _session(id: 's2', title: 'Push', workouts: [w2]));
      await provider.addPresetSession(
          _session(id: 's3', title: 'Other', workouts: [w3]));

      final sessions = provider.sessionTemplatesUsingExercise('cat-e');
      expect(sessions.map((s) => s.id).toSet(), {'s1', 's2'});

      final paths = provider.sessionWorkoutPathsUsingExercise('cat-e');
      expect(
        paths
            .map((p) => '${p.sessionTitle}|${p.workoutTitle}')
            .toSet(),
        {'Leg day|Squats', 'Push|Press'},
      );
    });
  });

  group('propagateWorkoutToSessionTemplates', () {
    test('updates only matching templates and uses independent deep copies',
        () async {
      final originalEx = _exercise(id: 'e-orig', sets: 3);
      final embeddedW = _workout(
          id: 'instance-w',
          templateId: 'cat-w',
          title: 'Old title',
          exercises: [originalEx]);
      final unrelatedW = _workout(id: 'other-w', exercises: []);

      await provider.addPresetSession(
          _session(id: 's1', workouts: [embeddedW]));
      await provider.addPresetSession(
          _session(id: 's2', workouts: [embeddedW.deepCopy()]));
      await provider
          .addPresetSession(_session(id: 's3', workouts: [unrelatedW]));

      final updatedCatalog = _workout(
          id: 'cat-w',
          title: 'New title',
          exercises: [_exercise(id: 'new-e', sets: 5)]);

      await provider.propagateWorkoutToSessionTemplates(updatedCatalog);

      final s1 = provider.presetSessions.firstWhere((s) => s.id == 's1');
      final s2 = provider.presetSessions.firstWhere((s) => s.id == 's2');
      final s3 = provider.presetSessions.firstWhere((s) => s.id == 's3');

      // Affected templates carry the new title and new sets.
      expect(s1.workouts.single.title, 'New title');
      expect(s1.workouts.single.exercises.single.sets, 5);
      expect(s2.workouts.single.title, 'New title');
      expect(s2.workouts.single.exercises.single.sets, 5);

      // Unrelated template untouched.
      expect(s3.workouts.single.id, 'other-w');

      // Independence: the embedded copies in s1 and s2 are different Exercise
      // instances (deep copies), so mutating one's exercises list does not
      // affect the other.
      expect(
        identical(
          s1.workouts.single.exercises,
          s2.workouts.single.exercises,
        ),
        isFalse,
      );
      expect(
        identical(
          s1.workouts.single.exercises.single,
          s2.workouts.single.exercises.single,
        ),
        isFalse,
      );

      // templateId chain preserved on propagated copies.
      expect(s1.workouts.single.templateId, 'cat-w');
      expect(s2.workouts.single.templateId, 'cat-w');
    });
  });

  group('propagateExerciseToSessionTemplates', () {
    test('updates only matching exercise slots, leaves others intact',
        () async {
      final targetEx = _exercise(id: 'cat-e', sets: 3, title: 'Squat');
      final otherEx = _exercise(id: 'other-e', sets: 4, title: 'Bench');
      final targetCopy =
          _exercise(id: 'instance-e', templateId: 'cat-e', sets: 3);

      final w1 =
          _workout(id: 'w1', exercises: [targetEx, otherEx]); // direct id
      final w2 =
          _workout(id: 'w2', exercises: [targetCopy]); // by templateId
      final w3 = _workout(id: 'w3', exercises: [otherEx]); // unrelated

      await provider.addPresetSession(_session(id: 's1', workouts: [w1]));
      await provider.addPresetSession(_session(id: 's2', workouts: [w2]));
      await provider.addPresetSession(_session(id: 's3', workouts: [w3]));

      final updated = _exercise(id: 'cat-e', sets: 7, title: 'Squat v2');

      await provider.propagateExerciseToSessionTemplates(updated);

      final s1 = provider.presetSessions.firstWhere((s) => s.id == 's1');
      final s2 = provider.presetSessions.firstWhere((s) => s.id == 's2');
      final s3 = provider.presetSessions.firstWhere((s) => s.id == 's3');

      // s1: target slot updated, sibling unchanged.
      final s1ws = s1.workouts.single;
      expect(s1ws.exercises.length, 2);
      expect(s1ws.exercises[0].sets, 7);
      expect(s1ws.exercises[0].title, 'Squat v2');
      expect(s1ws.exercises[0].templateId, 'cat-e');
      expect(s1ws.exercises[1].id, 'other-e');
      expect(s1ws.exercises[1].sets, 4);

      // s2: matched by templateId, replaced.
      expect(s2.workouts.single.exercises.single.sets, 7);
      expect(s2.workouts.single.exercises.single.templateId, 'cat-e');

      // s3: untouched.
      expect(s3.workouts.single.exercises.single.id, 'other-e');

      // Each propagated exercise is a fresh deep copy — no shared instances
      // between templates.
      expect(
        identical(
          s1ws.exercises[0],
          s2.workouts.single.exercises.single,
        ),
        isFalse,
      );
    });
  });
}
