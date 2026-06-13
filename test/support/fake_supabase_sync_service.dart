import 'package:flash_forward/core/sync/supabase_sync_service.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';

/// In-memory stand-in for [SupabaseSyncService]. Safe to construct without
/// Supabase.initialize() — every network method the guest flows touch is
/// overridden here, so the real supabase global is never reached.
///
/// Assumes `logCompletedSession` takes `completedAt` as a NAMED optional
/// parameter (see Task 3): `logCompletedSession(session, {bool isRetry,
/// DateTime? completedAt})`. Match the real signature to this.
///
/// Note: the inherited SyncQueueService is real and file-backed. None of the
/// overrides below touch it, but a test that drives an un-overridden queue
/// path would need the temp-dir path_provider fake (see catalog_test_kit.dart).
class FakeSupabaseSyncService extends SupabaseSyncService {
  FakeSupabaseSyncService() : super(userId: 'fake-user-id');

  /// Recorded claims, in call order.
  final List<Session> claimedSessions = [];
  final List<DateTime?> claimedCompletedAts = [];

  /// Canned cloud data each fetch returns (default empty).
  List<Session> cloudLoggedSessions = [];
  List<Session> cloudUserSessions = [];
  List<Workout> cloudUserWorkouts = [];
  List<Exercise> cloudUserExercises = [];
  List<TrashEntry> cloudTrashEntries = [];

  /// When true, [logCompletedSession] throws — simulates an offline claim.
  bool throwOnLogCompletedSession = false;

  @override
  Future<void> logCompletedSession(
    Session session, {
    bool isRetry = false,
    DateTime? completedAt,
  }) async {
    if (throwOnLogCompletedSession) {
      throw Exception('FakeSupabaseSyncService: simulated offline');
    }
    claimedSessions.add(session);
    claimedCompletedAts.add(completedAt);
  }

  @override
  Future<List<Session>> fetchLoggedSessions({
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      cloudLoggedSessions;

  @override
  Future<List<Session>> fetchUserSessions() async => cloudUserSessions;

  @override
  Future<List<Workout>> fetchUserWorkouts() async => cloudUserWorkouts;

  @override
  Future<List<Exercise>> fetchUserExercises() async => cloudUserExercises;

  @override
  Future<List<TrashEntry>> fetchUserTrashEntries() async => cloudTrashEntries;
}
