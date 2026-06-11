import 'package:flash_forward/data/default_session_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_kit.dart';

void main() {
  test('makeCatalogEnv seeds defaults and wires trash', () async {
    final env = await makeCatalogEnv(sessions: kDefaultSessions);
    addTearDown(env.dispose);
    expect(env.catalog.presetSessions, isNotEmpty);
    expect(
      env.catalog.presetSessions.any((s) => s.id == 'projecting-session'),
      isTrue,
    );
  });
}
