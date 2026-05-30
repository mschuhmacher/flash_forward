import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

Session _session(String id) =>
    Session(id: id, title: 'T', label: 'push', workouts: []);

SyncOperation _uploadOp(Session s) => SyncOperation(
    id: s.id,
    type: 'uploadSession',
    data: s.toJson(),
    createdAt: DateTime.now());

SyncOperation _deleteOp(String id) => SyncOperation(
    id: id,
    type: 'deleteSession',
    data: {},
    createdAt: DateTime.now());

Workout _workout({required String id, String title = 'W'}) => Workout(
      id: id,
      title: title,
      label: 'push',
      exercises: [],
      timeBetweenExercises: 60,
    );

TrashEntry _trashedWorkout({
  required String id,
  String title = 'W',
  DateTime? deletedAt,
}) =>
    TrashEntry.workout(
      workout: _workout(id: id, title: title),
      deletedAt: deletedAt ?? DateTime(2025, 1, 1),
    );

void main() {
  group('PresetSyncMerger.mergeWithPendingOps', () {
    test('returns cloud items unchanged when queue is empty', () {
      final s = _session('cloud-1');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [s],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [],
      );
      expect(result.map((s) => s.id).toList(), ['cloud-1']);
    });

    test('appends queued item not present in cloud', () {
      final local = _session('local-1');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(local)],
      );
      expect(result.map((s) => s.id).toList(), ['local-1']);
    });

    test('does not duplicate item already in cloud', () {
      final s = _session('shared-1');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [s],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(s)],
      );
      expect(result.length, 1);
    });

    test('ignores queued operations of a different type', () {
      final s = _session('del-1');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });

    test('cloud item is preferred when same id is in both cloud and queue', () {
      final cloudVersion = _session('s-1');
      final queueVersion =
          Session(id: 's-1', title: 'Stale', label: 'push', workouts: []);
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [cloudVersion],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(queueVersion)],
      );
      expect(result.length, 1);
      expect(result.first.title, 'T'); // cloud version kept
    });

    test('does not re-add item when uploadSession and deleteSession are both pending', () {
      final s = _session('s-2');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(s), _deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });

    test('filters out cloud item when a pending delete op exists for its id', () {
      final s = _session('cloud-del-1');
      final result = PresetSyncMerger.mergeWithPendingOps<Session>(
        cloudItems: [s],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });
  });

  group('PresetSyncMerger.mergeTrashCloudAndLocal', () {
    test('union of disjoint lists', () {
      final local = [_trashedWorkout(id: 'w-local')];
      final cloud = [_trashedWorkout(id: 'w-cloud')];

      final merged = PresetSyncMerger.mergeTrashCloudAndLocal(local, cloud);

      expect(merged.map((e) => e.id).toSet(), {'w-local', 'w-cloud'});
    });

    test('cloud entry with later deletedAt wins on conflict', () {
      final earlier = DateTime(2025, 1, 1);
      final later = DateTime(2025, 6, 1);

      final local = [
        _trashedWorkout(id: 'w-1', title: 'Old', deletedAt: earlier)
      ];
      final cloud = [
        _trashedWorkout(id: 'w-1', title: 'New', deletedAt: later)
      ];

      final merged = PresetSyncMerger.mergeTrashCloudAndLocal(local, cloud);

      expect(merged, hasLength(1));
      expect(merged.single.title, 'New');
    });

    test('local entry with later deletedAt is kept over cloud', () {
      final earlier = DateTime(2025, 1, 1);
      final later = DateTime(2025, 6, 1);

      final local = [
        _trashedWorkout(id: 'w-1', title: 'New', deletedAt: later)
      ];
      final cloud = [
        _trashedWorkout(id: 'w-1', title: 'Old', deletedAt: earlier)
      ];

      final merged = PresetSyncMerger.mergeTrashCloudAndLocal(local, cloud);

      expect(merged.single.title, 'New');
    });
  });
}
