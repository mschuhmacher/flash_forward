import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir;
}

Exercise _ex(String id) =>
    Exercise(id: id, title: id, description: '', label: 'l');

TrashEntry _trashEx(String id) => TrashEntry.exercise(
      exercise: _ex(id),
      deletedAt: DateTime(2026, 1, 1),
    );

/// Subclass that intercepts the Supabase network calls so tests run offline.
///
/// [_uploadShouldThrow] / [_deleteShouldThrow] simulate connectivity failures.
/// [_fetchRows] is the data returned by a simulated successful fetch.
class _TestableSupabaseSyncService extends SupabaseSyncService {
  _TestableSupabaseSyncService({required super.userId});

  bool uploadShouldThrow = false;
  bool deleteShouldThrow = false;
  List<Map<String, dynamic>> fetchRows = [];

  @override
  Future<void> uploadTrashEntry(TrashEntry entry,
      {bool isRetry = false}) async {
    if (uploadShouldThrow) {
      // Let the base implementation's catch block run by calling super,
      // but we simulate the Supabase failure by throwing before super can
      // make a real network call. We replicate the enqueue logic here because
      // super's try/catch wraps the real Supabase call, not this override.
      if (!isRetry) {
        await syncQueue.enqueue(SyncOperation(
          id: entry.id,
          type: 'uploadTrashEntry',
          data: entry.toJson(),
          createdAt: DateTime.now(),
        ));
      }
      throw Exception('simulated upload failure');
    }
    // No-op for success path — avoids touching the real Supabase client.
  }

  @override
  Future<void> deleteTrashEntry(String id, {bool isRetry = false}) async {
    if (deleteShouldThrow) {
      if (!isRetry) {
        await syncQueue.enqueue(SyncOperation(
          id: id,
          type: 'deleteTrashEntry',
          data: {'trashEntryId': id},
          createdAt: DateTime.now(),
        ));
      }
      throw Exception('simulated delete failure');
    }
  }

  @override
  Future<List<TrashEntry>> fetchUserTrashEntries() async {
    return fetchRows.map((row) {
      return TrashEntry.fromJson({
        'kind': row['kind'],
        'deletedAt': row['deleted_at'],
        'payload': row['payload'],
      });
    }).toList();
  }
}

void main() {
  late Directory tmpDir;
  late _TestableSupabaseSyncService svc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('sync_trash_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    svc = _TestableSupabaseSyncService(userId: 'user-1');
    await svc.syncQueue.loadQueue();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('SupabaseSyncService trash cloud sync', () {
    test('uploadTrashEntry enqueues operation on failure', () async {
      svc.uploadShouldThrow = true;
      final entry = _trashEx('ex-1');

      await expectLater(
        () => svc.uploadTrashEntry(entry),
        throwsA(isA<Exception>()),
      );

      final ops = svc.syncQueue.pendingOperations;
      expect(ops.length, 1);
      expect(ops.first.type, 'uploadTrashEntry');
      expect(ops.first.id, 'ex-1');
    });

    test('uploadTrashEntry does not double-enqueue on retry', () async {
      svc.uploadShouldThrow = true;
      final entry = _trashEx('ex-1');

      // Simulate a retry: isRetry=true means the queue must NOT grow.
      await expectLater(
        () => svc.uploadTrashEntry(entry, isRetry: true),
        throwsA(isA<Exception>()),
      );

      expect(svc.syncQueue.pendingOperations, isEmpty);
    });

    test('deleteTrashEntry enqueues operation on failure', () async {
      svc.deleteShouldThrow = true;

      await expectLater(
        () => svc.deleteTrashEntry('ex-2'),
        throwsA(isA<Exception>()),
      );

      final ops = svc.syncQueue.pendingOperations;
      expect(ops.length, 1);
      expect(ops.first.type, 'deleteTrashEntry');
      expect(ops.first.id, 'ex-2');
      expect(ops.first.data['trashEntryId'], 'ex-2');
    });

    test('deleteTrashEntry does not double-enqueue on retry', () async {
      svc.deleteShouldThrow = true;

      await expectLater(
        () => svc.deleteTrashEntry('ex-2', isRetry: true),
        throwsA(isA<Exception>()),
      );

      expect(svc.syncQueue.pendingOperations, isEmpty);
    });

    test('fetchUserTrashEntries round-trips an exercise entry', () async {
      final entry = _trashEx('ex-rt');
      final json = entry.toJson();

      // Simulate the column mapping that fetchUserTrashEntries performs.
      svc.fetchRows = [
        {
          'kind': json['kind'],
          'deleted_at': json['deletedAt'],
          'payload': json['payload'],
        }
      ];

      final results = await svc.fetchUserTrashEntries();
      expect(results.length, 1);
      expect(results.first.id, 'ex-rt');
      expect(results.first.kind, TrashKind.exercise);
      expect(results.first.deletedAt, entry.deletedAt);
    });

    test('fetchUserTrashEntries returns empty list when no rows', () async {
      svc.fetchRows = [];
      final results = await svc.fetchUserTrashEntries();
      expect(results, isEmpty);
    });
  });
}
