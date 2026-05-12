import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/pending_change.dart';
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
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('preset_commit_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    provider = PresetProvider();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('commitChanges', () {
    test(
      'lists sessions affected by changed workouts; suppresses exercise-level '
      'entry when the exercise lives inside a bagged workout',
      () async {
        // Catalog: one exercise, one workout containing it, one session containing
        // that workout. Plus another (sibling) workout that also references the
        // exercise.
        final ex = _exercise(id: 'cat-e', title: 'Squat');
        final parentWorkout = _workout(
          id: 'cat-w',
          title: 'Leg day',
          exercises: [ex],
        );
        final siblingWorkout = _workout(
          id: 'sibling-w',
          title: 'Other day',
          exercises: [_exercise(id: 'instance-e', templateId: 'cat-e')],
        );
        final sessionUsingParent = _session(
          id: 'cat-s',
          workouts: [parentWorkout],
        );
        final otherSession = _session(
          id: 'other-s',
          workouts: [siblingWorkout],
        );

        await provider.addPresetExercise(ex);
        await provider.addPresetWorkout(parentWorkout);
        await provider.addPresetWorkout(siblingWorkout);
        await provider.addPresetSession(sessionUsingParent);
        await provider.addPresetSession(otherSession);

        // User edits both the exercise and its parent workout in the same flow.
        final bag = PendingChangeBag()
          ..addExercise(_exercise(id: 'cat-e', title: 'Squat v2', sets: 5))
          ..addWorkout(_workout(
            id: 'cat-w',
            title: 'Leg day v2',
            exercises: [_exercise(id: 'cat-e', title: 'Squat v2', sets: 5)],
          ));

        final result = await provider.commitChanges(
          bag,
          excludeWorkoutId: 'cat-w',
        );

        expect(result.hasAny, isTrue);

        // Workout cat-w is used by sessionUsingParent → reported.
        expect(
          result.affectedSessionsByWorkoutId['cat-w']!.map((s) => s.id),
          ['cat-s'],
        );

        // Suppression rule: cat-e is inside cat-w (which is bagged), so the
        // exercise-level entry is suppressed even though sibling-w also
        // consumes cat-e. The user's edit was scoped to the parent workout.
        expect(
          result.affectedWorkoutsByExerciseId.containsKey('cat-e'),
          isFalse,
        );
      },
    );

    test(
      'suppresses exercise-level entry when exercise lives inside a bagged '
      'workout, but unrelated bagged exercises still get their entries',
      () async {
        // Bag will contain workout w1 (with exercise e1) and a separate
        // exercise e2 that is NOT in w1's exercises. e1 should be suppressed,
        // e2 should still surface its other consumers.
        final e1 = _exercise(id: 'e1', title: 'E1');
        final e2 = _exercise(id: 'e2', title: 'E2');
        final w1 = _workout(id: 'w1', title: 'W1', exercises: [e1]);
        final otherWorkoutUsingE2 = _workout(
          id: 'w-other',
          title: 'W-other',
          exercises: [e2],
        );

        await provider.addPresetExercise(e1);
        await provider.addPresetExercise(e2);
        await provider.addPresetWorkout(w1);
        await provider.addPresetWorkout(otherWorkoutUsingE2);
        // Sessions wrap the workouts so usagesOfExercise can locate them.
        await provider.addPresetSession(_session(id: 's1', workouts: [w1]));
        await provider.addPresetSession(
          _session(id: 's2', workouts: [otherWorkoutUsingE2]),
        );

        final bag = PendingChangeBag()
          ..addWorkout(_workout(
            id: 'w1',
            title: 'W1 v2',
            exercises: [_exercise(id: 'e1', title: 'E1 v2')],
          ))
          ..addExercise(_exercise(id: 'e2', title: 'E2 v2'));

        final result = await provider.commitChanges(bag);

        // e1 is inside the bagged workout w1 → suppressed.
        expect(result.affectedWorkoutsByExerciseId.containsKey('e1'), isFalse);
        // e2 is NOT inside any bagged workout → its entry is computed.
        expect(
          result.affectedWorkoutsByExerciseId['e2']!.map((w) => w.id),
          ['w-other'],
        );
      },
    );

    test('without excludeWorkoutId, all consuming workouts are listed',
        () async {
      final ex = _exercise(id: 'cat-e');
      final parentWorkout = _workout(id: 'cat-w', exercises: [ex]);
      final siblingWorkout = _workout(
        id: 'sibling-w',
        exercises: [_exercise(id: 'instance-e', templateId: 'cat-e')],
      );

      await provider.addPresetExercise(ex);
      await provider.addPresetWorkout(parentWorkout);
      await provider.addPresetWorkout(siblingWorkout);
      // Each workout sits inside a session so usagesOfExercise can find them.
      await provider.addPresetSession(
        _session(id: 's1', workouts: [parentWorkout]),
      );
      await provider.addPresetSession(
        _session(id: 's2', workouts: [siblingWorkout]),
      );

      final bag = PendingChangeBag()
        ..addExercise(_exercise(id: 'cat-e', sets: 9));

      final result = await provider.commitChanges(bag);

      expect(
        result.affectedWorkoutsByExerciseId['cat-e']!
            .map((w) => w.id)
            .toSet(),
        {'cat-w', 'sibling-w'},
      );
    });

    test('excludeSessionId suppresses the session being edited', () async {
      final w = _workout(id: 'cat-w', exercises: []);
      await provider.addPresetWorkout(w);
      await provider.addPresetSession(_session(id: 's1', workouts: [w]));
      await provider.addPresetSession(_session(id: 's2', workouts: [w]));

      final bag = PendingChangeBag()
        ..addWorkout(_workout(id: 'cat-w', title: 'Renamed', exercises: []));

      final result =
          await provider.commitChanges(bag, excludeSessionId: 's1');

      expect(
        result.affectedSessionsByWorkoutId['cat-w']!.map((s) => s.id),
        ['s2'],
      );
    });

    test('hasAny is false when there are no other consumers', () async {
      // Edit a brand-new exercise/workout that nothing else references.
      await provider.addPresetExercise(_exercise(id: 'lonely-e'));
      await provider.addPresetWorkout(_workout(id: 'lonely-w', exercises: []));

      final bag = PendingChangeBag()
        ..addExercise(_exercise(id: 'lonely-e', sets: 4))
        ..addWorkout(_workout(id: 'lonely-w', title: 'New', exercises: []));

      final result = await provider.commitChanges(bag);

      expect(result.hasAny, isFalse);
      expect(result.affectedSessionsByWorkoutId, isEmpty);
      expect(result.affectedWorkoutsByExerciseId, isEmpty);
    });

    test(
      'catalog-scoped commit promotes exercises and workouts in dependency order',
      () async {
        provider.debugSeedDefaults(
          exercises: [_exercise(id: 'cat-e', title: 'Default ex')],
          workouts: [_workout(id: 'cat-w', title: 'Default w', exercises: [])],
        );

        final bag = PendingChangeBag()
          ..addExercise(_exercise(id: 'cat-e', title: 'My ex'))
          ..addWorkout(_workout(id: 'cat-w', title: 'My w', exercises: []));

        await provider.commitChanges(bag);

        // Both were promoted (defaults shadowed).
        expect(provider.presetUserExerciseIDs, contains('cat-e'));
        expect(provider.presetUserWorkoutsIDs, contains('cat-w'));

        // And the user-list values reflect the bag's edits.
        expect(
          provider.presetExercises.firstWhere((e) => e.id == 'cat-e').title,
          'My ex',
        );
        expect(
          provider.presetWorkouts.firstWhere((w) => w.id == 'cat-w').title,
          'My w',
        );
      },
    );

    test(
      'session-scoped commit promotes only the session; '
      'bagged workouts and exercises are not pushed to the catalog',
      () async {
        provider.debugSeedDefaults(
          exercises: [_exercise(id: 'cat-e', title: 'Default ex')],
          workouts: [_workout(id: 'cat-w', title: 'Default w', exercises: [])],
          sessions: [_session(id: 'cat-s', title: 'Default s', workouts: [])],
        );

        final bag = PendingChangeBag()
          ..addExercise(_exercise(id: 'cat-e', title: 'My ex'))
          ..addWorkout(_workout(id: 'cat-w', title: 'My w', exercises: []))
          ..setSession(_session(id: 'cat-s', title: 'My s', workouts: []));

        await provider.commitChanges(bag);

        // Session was promoted; defaults for exercises and workouts are NOT
        // shadowed — they remain in the default list only.
        expect(provider.presetUserExerciseIDs, isNot(contains('cat-e')));
        expect(provider.presetUserWorkoutsIDs, isNot(contains('cat-w')));
        expect(provider.presetUserSessionIDs, contains('cat-s'));

        // The session in the catalog reflects the bag's edit.
        expect(
          provider.presetSessions.firstWhere((s) => s.id == 'cat-s').title,
          'My s',
        );
      },
    );

    test('session-scoped commit does not promote workouts to catalog', () async {
      final ex = _exercise(id: 'cat-e');
      final catalogW = _workout(id: 'cat-w', exercises: [ex]);
      final sa = _session(id: 'cat-s', workouts: [catalogW]);
      provider.debugSeedDefaults(workouts: [catalogW], sessions: [sa]);

      final embeddedW = catalogW.copyWith(timeBetweenExercises: 999);
      final bag = PendingChangeBag()
        ..setSession(sa.copyWith(workouts: [embeddedW]))
        ..addWorkout(embeddedW);

      final beforeUserWorkouts = provider.presetUserWorkoutsIDs.length;
      await provider.commitChanges(bag);

      expect(provider.presetUserWorkoutsIDs.length, beforeUserWorkouts);
    });

    test('session-scoped commit does not promote exercises to catalog', () async {
      final ex = _exercise(id: 'cat-e');
      final catalogW = _workout(id: 'cat-w', exercises: [ex]);
      final sa = _session(id: 'cat-s', workouts: [catalogW]);
      provider.debugSeedDefaults(exercises: [ex], workouts: [catalogW], sessions: [sa]);

      final embeddedEx = ex.copyWith(sets: 7);
      final bag = PendingChangeBag()
        ..setSession(sa)
        ..addExercise(embeddedEx);

      final beforeUserExercises = provider.presetUserExerciseIDs.length;
      await provider.commitChanges(bag);

      expect(provider.presetUserExerciseIDs.length, beforeUserExercises);
    });

    test('catalog-scoped commit still promotes workouts (regression guard)', () async {
      final w = _workout(id: 'cat-w', exercises: []);
      provider.debugSeedDefaults(workouts: [w]);
      final bag = PendingChangeBag()..addWorkout(w.copyWith(timeBetweenExercises: 999));
      await provider.commitChanges(bag);
      expect(provider.presetUserWorkoutsIDs, contains('cat-w'));
    });

    test(
      'dedupes affected workouts by id when two sessions reference the same '
      'workout via separate Workout instances',
      () async {
        // Two sessions each contain a Workout with the same id but distinct
        // Dart instances (e.g. each session was loaded from JSON separately).
        // The propagation prompt must list the shared workout once, not twice.
        final ex = _exercise(id: 'cat-e', title: 'Pull-ups');
        final wA = _workout(
          id: 'shared-w',
          title: 'Full-Body',
          exercises: [ex],
        );
        final wB = _workout(
          id: 'shared-w',
          title: 'Full-Body',
          exercises: [_exercise(id: 'cat-e', title: 'Pull-ups')],
        );
        final sA = _session(id: 's-a', title: 'A', workouts: [wA]);
        final sB = _session(id: 's-b', title: 'B', workouts: [wB]);

        provider.debugSeedDefaults(
          exercises: [ex],
          workouts: [wA],
          sessions: [sA, sB],
        );

        final bag = PendingChangeBag()
          ..addExercise(_exercise(id: 'cat-e', title: 'Pull-ups', sets: 5));
        final result = await provider.commitChanges(bag);

        expect(result.affectedWorkoutsByExerciseId['cat-e'], hasLength(1));
        expect(
          result.affectedWorkoutsByExerciseId['cat-e']!.single.id,
          'shared-w',
        );
      },
    );

    test(
      'session-edit of an embedded workout (fresh UUID, templateId pointing '
      'to catalog) finds sibling sessions via the templateId chain',
      () async {
        // Realistic legacy data: three sessions each carry a session-embedded
        // copy of Climbing Warm-up with a unique fresh UUID and templateId
        // pointing back to the catalog id. This shape predates id-stable
        // propagation and survives on disk.
        final ex = _exercise(id: 'cat-e', sets: 3);
        final catalogW = _workout(id: 'cat-w', exercises: [ex]);

        Workout legacyEmbed(String id) => _workout(
              id: id,
              templateId: 'cat-w',
              exercises: [_exercise(id: 'cat-e', sets: 3)],
            );
        final sA = _session(
          id: 's-a',
          workouts: [legacyEmbed('uuid-a')],
        );
        final sB = _session(
          id: 's-b',
          workouts: [legacyEmbed('uuid-b')],
        );
        final sC = _session(
          id: 's-c',
          workouts: [legacyEmbed('uuid-c')],
        );

        provider.debugSeedDefaults(
          workouts: [catalogW],
          sessions: [sA, sB, sC],
        );

        // User opens session A and edits its embedded workout (id=uuid-a).
        // The session save bags the modified workout with that fresh id and
        // templateId=cat-w.
        final editedWorkout = legacyEmbed('uuid-a').copyWith(
          timeBetweenExercises: 999,
        );
        final bag = PendingChangeBag()
          ..setSession(sA.copyWith(workouts: [editedWorkout]))
          ..addWorkout(editedWorkout);

        final result = await provider.commitChanges(
          bag,
          excludeSessionId: 's-a',
        );

        // Sibling sessions sB and sC must be reachable via the templateId
        // chain even though no other session shares 'uuid-a' as id.
        expect(
          result.affectedSessionsByWorkoutId['uuid-a']!
              .map((s) => s.id)
              .toSet(),
          {'s-b', 's-c'},
        );
      },
    );
  });

  group('propagateBag', () {
    test(
      'runs exercise→sessions, exercise→workouts, and workout→sessions; '
      'mutating one propagated copy does not bleed into another',
      () async {
        // An exercise lives in two user workouts AND in a session-template
        // workout (referenced via templateId). Both consumers must be updated,
        // each with an independent deep copy.
        final originalEx = _exercise(id: 'cat-e', sets: 3, title: 'Squat');
        final wA = _workout(
          id: 'wA',
          exercises: [originalEx],
        );
        final wB = _workout(
          id: 'wB',
          exercises: [_exercise(id: 'instance-e', templateId: 'cat-e', sets: 3)],
        );

        await provider.addPresetExercise(originalEx);
        await provider.addPresetWorkout(wA);
        await provider.addPresetWorkout(wB);
        // Session template embeds wA so workout propagation has something to do.
        await provider.addPresetSession(
          _session(id: 's1', workouts: [wA.deepCopy()]),
        );

        final updatedEx = _exercise(id: 'cat-e', sets: 7, title: 'Squat v2');
        final updatedW = _workout(
          id: 'wA',
          title: 'wA renamed',
          exercises: [updatedEx],
        );

        final bag = PendingChangeBag()
          ..addExercise(updatedEx)
          ..addWorkout(updatedW);

        // Commit first (so the catalog reflects the edit) then propagate.
        await provider.commitChanges(bag);
        await provider.propagateBag(bag);

        // Both user workouts now carry the new exercise sets.
        final wAAfter =
            provider.presetWorkouts.firstWhere((w) => w.id == 'wA');
        final wBAfter =
            provider.presetWorkouts.firstWhere((w) => w.id == 'wB');
        expect(wAAfter.exercises.single.sets, 7);
        expect(wBAfter.exercises.single.sets, 7);

        // Independent instances — mutating one's exercises list won't bleed.
        expect(
          identical(wAAfter.exercises.single, wBAfter.exercises.single),
          isFalse,
        );

        // Session template was also updated by workout propagation: title
        // matches the renamed catalog workout, and exercises are deep copies
        // distinct from the user-workout copies.
        final s1After = provider.presetSessions.firstWhere((s) => s.id == 's1');
        expect(s1After.workouts.single.title, 'wA renamed');
        expect(s1After.workouts.single.exercises.single.sets, 7);
        expect(
          identical(
            s1After.workouts.single.exercises.single,
            wAAfter.exercises.single,
          ),
          isFalse,
        );
      },
    );

    test('session changes do not trigger any propagation', () async {
      // A session with embedded workout/exercise. We change the session via
      // the bag — propagateBag should not touch anything else.
      final ex = _exercise(id: 'cat-e');
      final w = _workout(id: 'cat-w', exercises: [ex]);
      await provider.addPresetExercise(ex);
      await provider.addPresetWorkout(w);
      await provider.addPresetSession(_session(id: 'cat-s', workouts: [w]));

      final bag = PendingChangeBag()
        ..setSession(_session(id: 'cat-s', title: 'Renamed', workouts: [w]));

      // Snapshot user lists pre-propagate.
      final wBefore =
          provider.presetWorkouts.firstWhere((x) => x.id == 'cat-w');
      final eBefore =
          provider.presetExercises.firstWhere((x) => x.id == 'cat-e');

      await provider.propagateBag(bag);

      // Identity preserved: nothing was rewritten.
      expect(
        identical(
          provider.presetWorkouts.firstWhere((x) => x.id == 'cat-w'),
          wBefore,
        ),
        isTrue,
      );
      expect(
        identical(
          provider.presetExercises.firstWhere((x) => x.id == 'cat-e'),
          eBefore,
        ),
        isTrue,
      );
    });
  });

  group('propagateExerciseToWorkouts', () {
    test(
      'replaces matching exercises in user workouts (by id and templateId) '
      'and gives each workout an independent deep copy',
      () async {
        final original = _exercise(id: 'cat-e', sets: 3);
        final w1 = _workout(id: 'w1', exercises: [original]);
        final w2 = _workout(
          id: 'w2',
          exercises: [_exercise(id: 'instance-e', templateId: 'cat-e', sets: 3)],
        );
        final w3 = _workout(
          id: 'w3',
          exercises: [_exercise(id: 'unrelated-e')],
        );

        await provider.addPresetWorkout(w1);
        await provider.addPresetWorkout(w2);
        await provider.addPresetWorkout(w3);

        final updated = _exercise(id: 'cat-e', sets: 9, title: 'New');

        await provider.propagateExerciseToWorkouts(updated);

        final w1After = provider.presetWorkouts.firstWhere((w) => w.id == 'w1');
        final w2After = provider.presetWorkouts.firstWhere((w) => w.id == 'w2');
        final w3After = provider.presetWorkouts.firstWhere((w) => w.id == 'w3');

        // Affected workouts updated; matched-by-templateId exercise gets a
        // fresh copy carrying the catalog id (keepId: true).
        expect(w1After.exercises.single.sets, 9);
        expect(w2After.exercises.single.sets, 9);
        expect(w2After.exercises.single.id, 'cat-e');

        // Unrelated workout untouched.
        expect(w3After.exercises.single.id, 'unrelated-e');

        // Independent instances.
        expect(
          identical(w1After.exercises.single, w2After.exercises.single),
          isFalse,
        );
      },
    );

    test('embedded exercise copies in workouts retain the catalog id after propagation', () async {
      final catalogEx = _exercise(id: 'cat-e', sets: 3);
      final w = _workout(
          id: 'w-1',
          exercises: [_exercise(id: 'cat-e', sets: 3)]);
      provider.debugSeedDefaults(exercises: [catalogEx], workouts: [w]);

      final updated = catalogEx.copyWith(sets: 5);
      await provider.propagateExerciseToWorkouts(updated);

      for (final workout in provider.presetWorkouts) {
        for (final e in workout.exercises) {
          expect(e.id, 'cat-e', reason: 'id must remain catalog id after propagation');
        }
      }
    });
  });
}
