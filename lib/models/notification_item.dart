/// Represents a single notification captured from the Android system
/// and forwarded (or pending forwarding) to the BLE smartwatch.
class NotificationItem {
  /// Application package that posted the notification.
  final String packageName;

  /// Short title of the notification (e.g. sender name, app name).
  final String title;

  /// Body / content text of the notification.
  final String body;

  /// Timestamp when the notification was received on the phone.
  final DateTime receivedAt;

  /// Whether the notification has already been successfully written to the
  /// BLE characteristic (FFE2).
  final bool sent;

  const NotificationItem({
    required this.packageName,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.sent = false,
  });

  /// Returns a copy of this item with [sent] set to [true].
  NotificationItem markSent() => NotificationItem(
        packageName: packageName,
        title: title,
        body: body,
        receivedAt: receivedAt,
        sent: true,
      );

  @override
  String toString() =>
      'NotificationItem(pkg=$packageName, title=$title, sent=$sent)';
}
