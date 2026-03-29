import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/preset_provider.dart';
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

void main() {
  group('PresetProvider.mergeWithPendingOps', () {
    test('returns cloud items unchanged when queue is empty', () {
      final s = _session('cloud-1');
      final result = PresetProvider.mergeWithPendingOps<Session>(
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
      final result = PresetProvider.mergeWithPendingOps<Session>(
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
      final result = PresetProvider.mergeWithPendingOps<Session>(
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
      final result = PresetProvider.mergeWithPendingOps<Session>(
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
      final result = PresetProvider.mergeWithPendingOps<Session>(
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
      final result = PresetProvider.mergeWithPendingOps<Session>(
        cloudItems: [],
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: [_uploadOp(s), _deleteOp(s.id)],
      );
      expect(result, isEmpty);
    });
  });
}
