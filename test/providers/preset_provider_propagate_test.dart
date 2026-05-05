import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
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

  group('usagesOfWorkout', () {
    test('matches by direct id (catalog workout dropped into a template)',
        () async {
      final w = _workout(id: 'cat-w', exercises: []);
      await provider.addPresetSession(_session(id: 's1', workouts: [w]));
      await provider.addPresetSession(_session(id: 's2', workouts: []));

      final result = provider.usagesOfWorkout('cat-w');

      expect(result.map((s) => s.id), ['s1']);
    });

    test('matches by templateId (deep-copied workout in a template)', () async {
      final embedded = _workout(
          id: 'instance-w', templateId: 'cat-w', exercises: []);
      await provider
          .addPresetSession(_session(id: 's1', workouts: [embedded]));

      final result = provider.usagesOfWorkout('cat-w');

      expect(result.map((s) => s.id), ['s1']);
    });

    test('returns empty when no template uses the workout', () async {
      await provider.addPresetSession(_session(id: 's1', workouts: []));

      expect(provider.usagesOfWorkout('nope'), isEmpty);
    });
  });

  group('usagesOfExercise', () {
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

      final usages = provider.usagesOfExercise('cat-e');

      // Distinct sessions reachable via the usages list.
      expect(
        usages.map((u) => u.session?.id).whereType<String>().toSet(),
        {'s1', 's2'},
      );

      // (sessionTitle, workoutTitle) pairs for every occurrence — what the
      // propagation dialog renders.
      expect(
        usages
            .where((u) => u.session != null)
            .map((u) => '${u.session!.title}|${u.workout.title}')
            .toSet(),
        {'Leg day|Squats', 'Push|Press'},
      );
    });

    test(
        'workoutsContainingExercise dedupes by workout.id when sessions hold '
        'separate Workout instances with the same id',
        () async {
      // Multiple sessions each carry a Workout with the same id but distinct
      // Dart instances (each loaded from JSON separately). The deduped result
      // must list the shared workout exactly once.
      final ex = _exercise(id: 'shared-e', title: 'Hangs');
      final wA = _workout(
        id: 'shared-w',
        title: 'Combined Limit Strength',
        exercises: [ex],
      );
      final wB = _workout(
        id: 'shared-w',
        title: 'Combined Limit Strength',
        exercises: [_exercise(id: 'shared-e', title: 'Hangs')],
      );
      final wC = _workout(
        id: 'shared-w',
        title: 'Combined Limit Strength',
        exercises: [_exercise(id: 'shared-e', title: 'Hangs')],
      );
      final sA = _session(id: 's-a', title: 'A', workouts: [wA]);
      final sB = _session(id: 's-b', title: 'B', workouts: [wB]);
      final sC = _session(id: 's-c', title: 'C', workouts: [wC]);

      provider.debugSeedDefaults(
        exercises: [ex],
        workouts: [wA],
        sessions: [sA, sB, sC],
      );

      final result = provider.workoutsContainingExercise('shared-e');

      expect(result, hasLength(1));
      expect(result.single.id, 'shared-w');
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

      // Catalog id preserved on propagated copies (keepId: true) so future
      // edits in any session can find siblings via usagesOfWorkout.
      expect(s1.workouts.single.id, 'cat-w');
      expect(s2.workouts.single.id, 'cat-w');
    });

    test('embedded copies retain the catalog id after propagation', () async {
      final ex = _exercise(id: 'cat-e', sets: 3);
      final catalogW = _workout(id: 'cat-w', exercises: [ex]);
      final embeddedA = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
      final embeddedB = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
      final sA = _session(id: 's-a', workouts: [embeddedA]);
      final sB = _session(id: 's-b', workouts: [embeddedB]);
      provider.debugSeedDefaults(workouts: [catalogW], sessions: [sA, sB]);

      final updated = catalogW.copyWith(timeBetweenExercises: 999);
      await provider.propagateWorkoutToSessionTemplates(updated);

      for (final session in provider.presetSessions) {
        for (final w in session.workouts) {
          expect(w.id, 'cat-w', reason: 'id must remain catalog id after propagation');
        }
      }
    });

    test('second-pass: usagesOfWorkout still finds siblings after propagation',
        () async {
      // The original regression: after a first propagation, fresh-UUID copies
      // broke the sibling lookup so a second edit from any session no longer
      // saw the others. With keepId: true the post-propagation embedded copies
      // share the catalog id, so usagesOfWorkout finds every session.
      final ex = _exercise(id: 'cat-e', sets: 3);
      final catalogW = _workout(id: 'cat-w', exercises: [ex]);
      final embeddedA = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
      final embeddedB = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
      final embeddedC = _workout(id: 'cat-w', exercises: [ex.deepCopy(keepId: true)]);
      final sA = _session(id: 's-a', workouts: [embeddedA]);
      final sB = _session(id: 's-b', workouts: [embeddedB]);
      final sC = _session(id: 's-c', workouts: [embeddedC]);
      provider.debugSeedDefaults(
        workouts: [catalogW],
        sessions: [sA, sB, sC],
      );

      // First-pass propagation from a catalog edit.
      await provider.propagateWorkoutToSessionTemplates(
        catalogW.copyWith(timeBetweenExercises: 999),
      );

      // Pick any post-propagated embedded copy and re-look up siblings as if
      // the user opened a different session and edited the workout there.
      final postPropagated = provider.presetSessions
          .firstWhere((s) => s.id == 's-b')
          .workouts
          .single;
      final siblings = provider.usagesOfWorkout(
        postPropagated.id,
        alsoMatchTemplateId: postPropagated.templateId,
      );

      expect(siblings.map((s) => s.id).toSet(), {'s-a', 's-b', 's-c'});
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
      expect(s1ws.exercises[0].id, 'cat-e');
      expect(s1ws.exercises[1].id, 'other-e');
      expect(s1ws.exercises[1].sets, 4);

      // s2: matched by templateId, replaced; new copy carries the catalog id.
      expect(s2.workouts.single.exercises.single.sets, 7);
      expect(s2.workouts.single.exercises.single.id, 'cat-e');

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

    test('embedded exercise copies retain the catalog id after propagation', () async {
      final catalogEx = _exercise(id: 'cat-e', sets: 3);
      final embeddedW = _workout(
          id: 'w-1',
          exercises: [_exercise(id: 'cat-e', sets: 3)]);
      final s = _session(id: 's-a', workouts: [embeddedW]);
      provider.debugSeedDefaults(exercises: [catalogEx], sessions: [s]);

      final updated = catalogEx.copyWith(sets: 5);
      await provider.propagateExerciseToSessionTemplates(updated);

      for (final session in provider.presetSessions) {
        for (final w in session.workouts) {
          for (final e in w.exercises) {
            expect(e.id, 'cat-e', reason: 'id must remain catalog id after propagation');
          }
        }
      }
    });
  });

  group('propagateWorkoutToSessionTemplates with onlyToSessionIds filter', () {
    test('filters to specified sessions, leaves others unchanged', () async {
      final w = _workout(id: 'cat-w', title: 'Old', exercises: []);
      await provider.addPresetSession(_session(id: 's-a', workouts: [w]));
      await provider.addPresetSession(_session(id: 's-b', workouts: [w.deepCopy()]));
      await provider.addPresetSession(_session(id: 's-c', workouts: [w.deepCopy()]));

      final updated = _workout(id: 'cat-w', title: 'New', exercises: []);
      await provider.propagateWorkoutToSessionTemplates(
        updated,
        onlyToSessionIds: {'s-a', 's-c'},
      );

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a').workouts.single.title,
        'New',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-b').workouts.single.title,
        'Old',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-c').workouts.single.title,
        'New',
      );
    });

    test('null filter updates all (back-compat)', () async {
      final w = _workout(id: 'cat-w', title: 'Old', exercises: []);
      await provider.addPresetSession(_session(id: 's-a', workouts: [w]));
      await provider.addPresetSession(_session(id: 's-b', workouts: [w.deepCopy()]));

      await provider.propagateWorkoutToSessionTemplates(
        _workout(id: 'cat-w', title: 'New', exercises: []),
      );

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a').workouts.single.title,
        'New',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-b').workouts.single.title,
        'New',
      );
    });
  });

  group('propagateBag with PropagationSelection', () {
    test('empty selection writes nothing', () async {
      final ex = _exercise(id: 'cat-e', sets: 3);
      final w = _workout(id: 'w-1', exercises: [ex]);
      await provider.addPresetSession(_session(id: 's-a', workouts: [w]));

      final bag = PendingChangeBag()..addExercise(ex.copyWith(sets: 9));
      final selection = PropagationSelection({
        'exercise-in-sessions:cat-e': {},
        'exercise-in-workouts:cat-e': {},
      });
      await provider.propagateBag(bag, selection: selection);

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a')
            .workouts.single.exercises.single.sets,
        3,
      );
    });

    test('partial selection only updates chosen consumers', () async {
      final w = _workout(id: 'cat-w', title: 'Old', exercises: []);
      await provider.addPresetSession(_session(id: 's-a', workouts: [w]));
      await provider.addPresetSession(_session(id: 's-b', workouts: [w.deepCopy()]));
      await provider.addPresetSession(_session(id: 's-c', workouts: [w.deepCopy()]));

      final updated = _workout(id: 'cat-w', title: 'New', exercises: []);
      final bag = PendingChangeBag()..addWorkout(updated);
      final selection = PropagationSelection({
        'workout-in-sessions:cat-w': {'s-a', 's-c'},
      });
      await provider.propagateBag(bag, selection: selection);

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a').workouts.single.title,
        'New',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-b').workouts.single.title,
        'Old',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-c').workouts.single.title,
        'New',
      );
    });

    test('null selection updates all (back-compat guard)', () async {
      final w = _workout(id: 'cat-w', title: 'Old', exercises: []);
      await provider.addPresetSession(_session(id: 's-a', workouts: [w]));
      await provider.addPresetSession(_session(id: 's-b', workouts: [w.deepCopy()]));

      final updated = _workout(id: 'cat-w', title: 'New', exercises: []);
      final bag = PendingChangeBag()..addWorkout(updated);
      await provider.propagateBag(bag);

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a').workouts.single.title,
        'New',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-b').workouts.single.title,
        'New',
      );
    });

    test(
        'exercise-in-workouts selection (session-scoped edit path) only updates '
        'sessions that contain the chosen workout', () async {
      // Three sessions each embed the same workout, which contains the exercise.
      // The dialog shows consumers as workouts (all share id 'shared-w').
      // User unchecks s-b's workout — only s-a and s-c should be updated.
      final ex = _exercise(id: 'cat-e', sets: 3);
      final wA = _workout(id: 'shared-w', exercises: [ex]);
      final wB = _workout(id: 'shared-w', exercises: [_exercise(id: 'cat-e', sets: 3)]);
      final wC = _workout(id: 'shared-w', exercises: [_exercise(id: 'cat-e', sets: 3)]);
      provider.debugSeedDefaults(
        exercises: [ex],
        sessions: [
          _session(id: 's-a', workouts: [wA]),
          _session(id: 's-b', workouts: [wB]),
          _session(id: 's-c', workouts: [wC]),
        ],
      );

      final updated = ex.copyWith(sets: 9);
      final bag = PendingChangeBag()..addExercise(updated);
      // Dialog shows workout consumers; user deselects s-b by deselecting
      // 'shared-w' for that session — but since all three share the same
      // workout id the selection must be expressed as session ids via the
      // resolved path. Simulate by using exercise-in-sessions directly.
      final selection = PropagationSelection({
        'exercise-in-sessions:cat-e': {'s-a', 's-c'},
      });
      await provider.propagateBag(bag, selection: selection);

      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-a')
            .workouts.single.exercises.single.sets,
        9,
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-b')
            .workouts.single.exercises.single.sets,
        3,
        reason: 's-b was excluded from the selection',
      );
      expect(
        provider.presetSessions.firstWhere((s) => s.id == 's-c')
            .workouts.single.exercises.single.sets,
        9,
      );
    });
  });
}
