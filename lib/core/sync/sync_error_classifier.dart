import 'package:supabase_flutter/supabase_flutter.dart'; // re-exports PostgrestException

/// How a failed sync operation should be treated on retry.
enum SyncFailureKind {
  /// The server rejected the *content* and will reject it forever (malformed
  /// input, bad request, unprocessable entity). Retrying is pointless — discard.
  permanent,

  /// A transient condition (network, timeout, 5xx, unknown). Worth retrying
  /// across launches, up to a cap.
  transient,
}

/// Classifies a sync failure so [SyncQueueService.processQueue] can decide
/// whether to discard immediately or retry.
///
/// Permanent = Postgres data/integrity error (SQLSTATE class 22/23, e.g. the
/// `22P02` "invalid input syntax for type uuid" that poisoned the queue), or an
/// HTTP `400`/`422`. Everything else is transient.
SyncFailureKind classifySyncFailure(Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    if (code == '400' || code == '422') return SyncFailureKind.permanent;
    if (code != null && (code.startsWith('22') || code.startsWith('23'))) {
      return SyncFailureKind.permanent;
    }
  }
  return SyncFailureKind.transient;
}
