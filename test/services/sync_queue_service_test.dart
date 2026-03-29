import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

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

  tearDown(() => tmpDir.delete(recursive: true));

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
}
