import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncStatusProvider', () {
    test('reports zero pending sync when no service is attached', () {
      final provider = SyncStatusProvider();
      expect(provider.hasPendingSync, isFalse);
      expect(provider.pendingSyncCount, 0);
    });

    test('processPendingSync returns 0 when no service is attached', () async {
      final provider = SyncStatusProvider();
      expect(await provider.processPendingSync(), 0);
    });

    test('detach notifies listeners even from null state', () {
      final provider = SyncStatusProvider();
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.detach();

      expect(notifyCount, greaterThanOrEqualTo(1));
    });
  });
}
