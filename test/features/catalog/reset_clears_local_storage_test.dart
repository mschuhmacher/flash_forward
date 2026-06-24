import 'package:flash_forward/features/catalog/preset_loader.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_test_kit.dart';

const _uuid = '11111111-1111-4111-8111-111111111111';

void main() {
  test('CatalogProvider.reset deletes local user preset files', () async {
    final env = await makeCatalogEnv();
    await env.catalog.init(trash: env.trash);
    await env.catalog.upsertSession(testSession(id: _uuid));
    expect((await PresetLoader.loadFromLocal()).sessions, isNotEmpty);

    await env.catalog.reset();

    expect((await PresetLoader.loadFromLocal()).sessions, isEmpty);
    await env.dispose();
  });

  test('TrashProvider.reset clears the local trash store', () async {
    // init() reloads defaults from kDefaultSessions, so seed via upsert
    // (a persisted user item) rather than makeCatalogEnv(sessions:).
    final env = await makeCatalogEnv();
    await env.catalog.init(trash: env.trash);
    await env.catalog.upsertSession(testSession(id: _uuid));
    await env.trash.deleteToTrash(id: _uuid, kind: TrashKind.session);
    expect(env.trash.trashedItems, isNotEmpty);

    await env.trash.reset();
    await env.trash.loadAndPurge(); // re-read from disk

    expect(env.trash.trashedItems, isEmpty);
    await env.dispose();
  });
}
