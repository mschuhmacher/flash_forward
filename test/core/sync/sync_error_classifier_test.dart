import 'package:flash_forward/core/sync/sync_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('22P02 and 4xx client errors are permanent', () {
    expect(
      classifySyncFailure(
          const PostgrestException(message: 'bad uuid', code: '22P02')),
      SyncFailureKind.permanent,
    );
    expect(
      classifySyncFailure(const PostgrestException(message: 'bad', code: '400')),
      SyncFailureKind.permanent,
    );
    expect(
      classifySyncFailure(
          const PostgrestException(message: 'unproc', code: '422')),
      SyncFailureKind.permanent,
    );
  });

  test('5xx, network, and unknown errors are transient', () {
    expect(
      classifySyncFailure(const PostgrestException(message: 'boom', code: '500')),
      SyncFailureKind.transient,
    );
    expect(
      classifySyncFailure(Exception('SocketException: failed host lookup')),
      SyncFailureKind.transient,
    );
  });
}
