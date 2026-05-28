import 'package:flash_forward/providers/synced_item_ops.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  _Item(this.id, this.value);
  final String id;
  final int value;
}

void main() {
  group('SyncedItemOps', () {
    test('upsert adds when id is absent', () async {
      final list = <_Item>[];
      String? saved;
      _Item? uploaded;

      await SyncedItemOps.upsert<_Item>(
        list: list,
        item: _Item('a', 1),
        getId: (i) => i.id,
        saveLocal: () async => saved = 'saved',
        cloudOp: (i) async => uploaded = i,
      );

      expect(list.single.id, 'a');
      expect(saved, 'saved');
      expect(uploaded?.id, 'a');
    });

    test('upsert replaces in place when id exists', () async {
      final list = <_Item>[_Item('a', 1)];

      await SyncedItemOps.upsert<_Item>(
        list: list,
        item: _Item('a', 2),
        getId: (i) => i.id,
        saveLocal: () async {},
      );

      expect(list, hasLength(1));
      expect(list.single.value, 2);
    });

    test('removeById removes matching entries', () async {
      final list = <_Item>[_Item('a', 1), _Item('b', 2)];

      await SyncedItemOps.removeById<_Item>(
        list: list,
        id: 'a',
        getId: (i) => i.id,
        saveLocal: () async {},
      );

      expect(list.map((i) => i.id), ['b']);
    });

    test('upsert swallows cloudOp errors and forwards to onCloudError', () async {
      final list = <_Item>[];
      Object? captured;

      await SyncedItemOps.upsert<_Item>(
        list: list,
        item: _Item('a', 1),
        getId: (i) => i.id,
        saveLocal: () async {},
        cloudOp: (i) async => throw StateError('cloud down'),
        onCloudError: (e, st) => captured = e,
      );

      expect(list.single.id, 'a',
          reason: 'local mutation must persist even when cloud fails');
      expect(captured, isA<StateError>());
    });

    test('removeById propagates saveLocal errors', () async {
      final list = <_Item>[_Item('a', 1)];

      expect(
        () => SyncedItemOps.removeById<_Item>(
          list: list,
          id: 'a',
          getId: (i) => i.id,
          saveLocal: () async => throw StateError('disk full'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
