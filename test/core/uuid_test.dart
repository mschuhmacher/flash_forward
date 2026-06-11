import 'package:flash_forward/core/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isUuid accepts canonical UUIDs and rejects slugs', () {
    expect(isUuid('11111111-1111-4111-8111-111111111111'), isTrue);
    expect(isUuid('projecting-session'), isFalse);
    expect(isUuid(''), isFalse);
    expect(isUuid('11111111-1111-4111-8111'), isFalse);
  });
}
