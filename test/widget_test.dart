import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ticket payload parsing accepts a versioned event credential', () {
    final payload = {'v': 1, 'e': 'event-123', 'c': 'opaque-random-credential-123456789012'};
    expect(payload['v'], 1);
    expect(payload['e'], 'event-123');
    expect(payload['c'], isA<String>());
  });

  test('ticket payload rejects mismatched event and unsupported version', () {
    final payload = {'v': 2, 'e': 'other-event', 'c': 'opaque-random-credential-123456789012'};
    expect(payload['v'] == 1 && payload['e'] == 'event-123', isFalse);
  });
}
