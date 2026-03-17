import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ble_gateway/models/notification_item.dart';

void main() {
  group('NotificationItem', () {
    final now = DateTime(2024, 1, 1, 12, 0, 0);

    test('markSent returns a copy with sent=true', () {
      final item = NotificationItem(
        packageName: 'com.example.app',
        title: 'Test',
        body: 'Hello',
        receivedAt: now,
      );

      final sent = item.markSent();
      expect(sent.sent, isTrue);
      expect(sent.title, item.title);
      expect(sent.body, item.body);
      expect(sent.packageName, item.packageName);
      expect(sent.receivedAt, item.receivedAt);
    });

    test('default sent value is false', () {
      final item = NotificationItem(
        packageName: 'com.test',
        title: 'T',
        body: 'B',
        receivedAt: now,
      );
      expect(item.sent, isFalse);
    });

    test('toString includes package and title', () {
      final item = NotificationItem(
        packageName: 'com.test.pkg',
        title: 'My Title',
        body: 'Body text',
        receivedAt: now,
      );
      final str = item.toString();
      expect(str, contains('com.test.pkg'));
      expect(str, contains('My Title'));
    });
  });
}
