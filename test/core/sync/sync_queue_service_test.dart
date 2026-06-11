import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/core/sync/sync_queue_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

SyncOperation _op(String id, String type) =>
    SyncOperation(id: id, type: type, data: {}, createdAt: DateTime.now());

void main() {
  late Directory tmpDir;
  late SyncQueueService queue;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('sq_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    queue = SyncQueueService();
    await queue.loadQueue();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('SyncQueueService.dequeue', () {
    test('removes only the matching (id, type) pair', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));
      await queue.enqueue(_op('s-1', 'deleteSession'));
      expect(queue.pendingOperations.length, 2);

      await queue.dequeue('s-1', 'uploadSession');

      expect(queue.pendingOperations.length, 1);
      expect(queue.pendingOperations.first.type, 'deleteSession');
    });

    test('does not remove an op when only the type matches but id differs', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));
      await queue.enqueue(_op('s-2', 'uploadSession'));

      await queue.dequeue('s-1', 'uploadSession');

      expect(queue.pendingOperations.length, 1);
      expect(queue.pendingOperations.first.id, 's-2');
    });

    test('does nothing when no matching (id, type) pair exists', () async {
      await queue.enqueue(_op('s-1', 'uploadSession'));

      await queue.dequeue('s-1', 'deleteSession'); // type mismatch

      expect(queue.pendingOperations.length, 1);
    });
  });

  group('SyncOperation.attempts', () {
    test('enqueue replacing an op carries the attempts counter over', () async {
      await queue.enqueue(SyncOperation(
        id: 'a', type: 'uploadSession', data: {'x': 1},
        createdAt: DateTime(2026), attempts: 3,
      ));
      // Re-enqueue same (id,type) with attempts 0 — must NOT reset to 0.
      await queue.enqueue(SyncOperation(
        id: 'a', type: 'uploadSession', data: {'x': 2},
        createdAt: DateTime(2026), attempts: 0,
      ));
      expect(queue.pendingOperations.single.attempts, 3);
      expect(queue.pendingOperations.single.data['x'], 2); // payload refreshed
    });

    test('fromJson defaults attempts to 0 when absent', () {
      final op = SyncOperation.fromJson(<String, dynamic>{
        'id': 'a', 'type': 't', 'data': <String, dynamic>{},
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(op.attempts, 0);
    });
  });

  group('processQueue disposition', () {
    test('permanent failure is discarded on first attempt', () async {
      final svc = SyncQueueService(connectivityOverride: () async => true);
      await svc.enqueue(_op('a', 'uploadSession'));
      var calls = 0;
      await svc.processQueue((_) async {
        calls++;
        throw const PostgrestException(message: 'bad uuid', code: '22P02');
      });
      expect(svc.pendingCount, 0); // discarded
      expect(calls, 1);
    });

    test('transient failure retries up to maxAttempts then discards', () async {
      final svc = SyncQueueService(
          maxAttempts: 3, connectivityOverride: () async => true);
      await svc.enqueue(_op('a', 'uploadSession'));
      Future<bool> fail(SyncOperation _) async =>
          throw Exception('SocketException');

      await svc.processQueue(fail); // attempt 1 -> attempts=1, kept
      expect(svc.pendingCount, 1);
      expect(svc.pendingOperations.single.attempts, 1);
      await svc.processQueue(fail); // attempt 2 -> attempts=2, kept
      expect(svc.pendingOperations.single.attempts, 2);
      await svc.processQueue(fail); // attempt 3 -> hits cap, discarded
      expect(svc.pendingCount, 0);
    });

    test('unknown op type (handler returns false) is discarded', () async {
      final svc = SyncQueueService(connectivityOverride: () async => true);
      await svc.enqueue(_op('a', 'bogusOp'));
      await svc.processQueue((_) async => false);
      expect(svc.pendingCount, 0);
    });

    test('success dequeues the op', () async {
      final svc = SyncQueueService(connectivityOverride: () async => true);
      await svc.enqueue(_op('a', 'uploadSession'));
      final n = await svc.processQueue((_) async => true);
      expect(n, 1);
      expect(svc.pendingCount, 0);
    });
  });

  group('dropNonUuidOps', () {
    test('removes ops whose entity id is not a UUID', () async {
      await queue.enqueue(_op('projecting-session', 'uploadSession'));
      await queue.enqueue(
          _op('11111111-1111-4111-8111-111111111111', 'uploadSession'));

      await queue.dropNonUuidOps();

      expect(queue.pendingOperations.map((o) => o.id),
          ['11111111-1111-4111-8111-111111111111']);
    });
  });
}
