import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/features/catalog/trash_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

Exercise _ex(String id) =>
    Exercise(id: id, title: id, description: '', label: 'l');

Workout _wo(String id) => Workout(
      id: id,
      title: id,
      label: 'l',
      exercises: [],
      timeBetweenExercises: 60,
    );

Session _se(String id) =>
    Session(id: id, title: id, label: 'l', workouts: []);

void main() {
  late Directory tmpDir;
  late TrashService svc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('trash_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    svc = TrashService();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('TrashService', () {
    test('readAll returns [] when file does not exist', () async {
      final entries = await svc.readAll();
      expect(entries, isEmpty);
    });

    test('add then readAll round-trips three entries in insertion order',
        () async {
      final now = DateTime(2026, 4, 30);
      final e1 = TrashEntry.exercise(exercise: _ex('ex-1'), deletedAt: now);
      final e2 = TrashEntry.workout(workout: _wo('wo-1'), deletedAt: now);
      final e3 = TrashEntry.session(session: _se('se-1'), deletedAt: now);

      await svc.add(e1);
      await svc.add(e2);
      await svc.add(e3);

      final all = await svc.readAll();
      expect(all.length, 3);
      expect(all[0].id, 'ex-1');
      expect(all[0].kind, TrashKind.exercise);
      expect(all[1].id, 'wo-1');
      expect(all[1].kind, TrashKind.workout);
      expect(all[2].id, 'se-1');
      expect(all[2].kind, TrashKind.session);
    });

    test('add dedupes by id: re-adding an entry replaces the old one',
        () async {
      final now = DateTime(2026, 4, 30);
      final e1 = TrashEntry.exercise(exercise: _ex('ex-1'), deletedAt: now);
      final e1again =
          TrashEntry.exercise(exercise: _ex('ex-1'), deletedAt: now.add(const Duration(hours: 1)));

      await svc.add(e1);
      await svc.add(e1again);

      final all = await svc.readAll();
      expect(all.length, 1);
      expect(all[0].deletedAt, e1again.deletedAt);
    });

    test('purgeOlderThan removes entries strictly older than cutoff', () async {
      final now = DateTime(2026, 4, 30);
      final recent = TrashEntry.exercise(
        exercise: _ex('recent'),
        deletedAt: now.subtract(const Duration(days: 10)),
      );
      final old1 = TrashEntry.workout(
        workout: _wo('old1'),
        deletedAt: now.subtract(const Duration(days: 91)),
      );
      final old2 = TrashEntry.session(
        session: _se('old2'),
        deletedAt: now.subtract(const Duration(days: 100)),
      );

      await svc.add(recent);
      await svc.add(old1);
      await svc.add(old2);

      final purged =
          await svc.purgeOlderThan(const Duration(days: 90), now: now);
      expect(purged.toSet(), {'old1', 'old2'});

      final remaining = await svc.readAll();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'recent');
    });

    test('purgeOlderThan keeps default-derived entries regardless of age',
        () async {
      final now = DateTime(2026, 4, 30);
      final oldUser = TrashEntry.session(
        session: _se('u-old'),
        deletedAt: now.subtract(const Duration(days: 200)),
      );
      // A forked default: templateId set, so shadowId != id.
      final oldDefault = TrashEntry.session(
        session: _se('x').copyWith(id: 'fork-uuid', templateId: 'projecting-session'),
        deletedAt: now.subtract(const Duration(days: 200)),
      );

      await svc.add(oldUser);
      await svc.add(oldDefault);

      final purged = await svc.purgeOlderThan(const Duration(days: 90), now: now);
      expect(purged, contains('u-old')); // user item purged
      expect(purged, isNot(contains('fork-uuid'))); // default kept

      final remaining = await svc.readAll();
      expect(remaining.map((e) => e.id), ['fork-uuid']);
    });

    test('restore returns the entry and removes it; unknown id returns null',
        () async {
      final now = DateTime(2026, 4, 30);
      final e1 = TrashEntry.exercise(exercise: _ex('ex-1'), deletedAt: now);
      final e2 = TrashEntry.workout(workout: _wo('wo-1'), deletedAt: now);

      await svc.add(e1);
      await svc.add(e2);

      final restored = await svc.restore('ex-1');
      expect(restored, isNotNull);
      expect(restored!.id, 'ex-1');
      expect(restored.kind, TrashKind.exercise);

      final remaining = await svc.readAll();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'wo-1');

      final notFound = await svc.restore('no-such-id');
      expect(notFound, isNull);
    });

    test('round-trip preserves deletedAt timestamp', () async {
      final ts = DateTime(2025, 12, 31, 23, 59, 59);
      final entry =
          TrashEntry.exercise(exercise: _ex('ex-ts'), deletedAt: ts);
      await svc.add(entry);

      final all = await svc.readAll();
      expect(all.first.deletedAt, ts);
    });
  });
}
