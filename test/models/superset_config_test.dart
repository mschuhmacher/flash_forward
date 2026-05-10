import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SupersetConfig base() => SupersetConfig(
        id: 'ss-1',
        exerciseIds: ['e1', 'e2'],
        restSeconds: 15,
        supersetSets: 4,
        supersetSetRest: 90,
      );

  test('SupersetConfig survives toJson/fromJson round-trip', () {
    final s = base();
    final restored = SupersetConfig.fromJson(s.toJson());
    expect(restored.id, 'ss-1');
    expect(restored.exerciseIds, ['e1', 'e2']);
    expect(restored.restSeconds, 15);
    expect(restored.supersetSets, 4);
    expect(restored.supersetSetRest, 90);
  });

  test('SupersetConfig fromJson handles missing supersetSets (null)', () {
    final json = base().toJson()..remove('supersetSets');
    final restored = SupersetConfig.fromJson(json);
    expect(restored.supersetSets, isNull);
  });

  test('SupersetConfig fromJson handles missing supersetSetRest (null)', () {
    final json = base().toJson()..remove('supersetSetRest');
    final restored = SupersetConfig.fromJson(json);
    expect(restored.supersetSetRest, isNull);
  });

  test('copyWith preserves unspecified fields', () {
    final s = base().copyWith(restSeconds: 20);
    expect(s.id, 'ss-1');
    expect(s.exerciseIds, ['e1', 'e2']);
    expect(s.restSeconds, 20);
    expect(s.supersetSets, 4);
    expect(s.supersetSetRest, 90);
  });

  test('copyWith can set supersetSets to a new value', () {
    final s = base().copyWith(supersetSets: 5);
    expect(s.supersetSets, 5);
  });

  test('copyWith can set supersetSetRest to a new value', () {
    final s = base().copyWith(supersetSetRest: 120);
    expect(s.supersetSetRest, 120);
  });

  group('Workout.supersets', () {
    Workout workoutWith(List<SupersetConfig> supersets) => Workout(
          title: 'W',
          label: 'l',
          exercises: [],
          timeBetweenExercises: 120,
          supersets: supersets,
        );

    test('Workout.supersets survives toJson/fromJson round-trip', () {
      final w = workoutWith([base()]);
      final restored = Workout.fromJson(w.toJson());
      expect(restored.supersets.length, 1);
      expect(restored.supersets.first.id, 'ss-1');
      expect(restored.supersets.first.supersetSets, 4);
    });

    test('Workout.fromJson with missing supersets key defaults to empty list', () {
      final json = workoutWith([]).toJson()..remove('supersets');
      final restored = Workout.fromJson(json);
      expect(restored.supersets, isEmpty);
    });

    test('Workout.deepCopy carries supersets through', () {
      final w = workoutWith([base()]);
      final copy = w.deepCopy(keepId: true);
      expect(copy.supersets.first.id, 'ss-1');
      expect(copy.supersets.first.exerciseIds, ['e1', 'e2']);
      expect(copy.supersets.first.supersetSets, 4);
    });

    test('Workout.deepCopy supersets are independent instances', () {
      final w = workoutWith([base()]);
      final copy = w.deepCopy(keepId: true);
      expect(identical(w.supersets.first, copy.supersets.first), isFalse);
    });

    test('Workout.copyWith replaces supersets', () {
      final w = workoutWith([base()]);
      final updated = w.copyWith(supersets: []);
      expect(updated.supersets, isEmpty);
    });

    test('Workout.copyWith without supersets argument preserves them', () {
      final w = workoutWith([base()]);
      final updated = w.copyWith(title: 'New title');
      expect(updated.supersets, hasLength(1));
      expect(updated.supersets.first.id, 'ss-1');
    });
  });
}
