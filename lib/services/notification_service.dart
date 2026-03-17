import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/notification_item.dart';
import 'ble_service.dart';

// ---------------------------------------------------------------------------
// Channel constants (must match the Kotlin side)
// ---------------------------------------------------------------------------

/// EventChannel through which the native NotificationListenerService pushes
/// new notifications to the Flutter layer.
const EventChannel _kNotificationChannel =
    EventChannel('com.example.flutter_ble_gateway/notifications');

/// MethodChannel used to request the user to enable the notification access
/// permission for this app in Android Settings.
const MethodChannel _kPermissionChannel =
    MethodChannel('com.example.flutter_ble_gateway/notification_permission');

// ---------------------------------------------------------------------------
// NotificationService
// ---------------------------------------------------------------------------

/// Bridges Android's [NotificationListenerService] to the Flutter layer and
/// forwards captured notifications to [BleService] for BLE transmission.
///
/// Maintains a capped list of recent [NotificationItem]s for the UI.
class NotificationService extends ChangeNotifier {
  NotificationService({required BleService bleService})
      : _bleService = bleService;

  final BleService _bleService;

  /// Maximum number of notifications kept in [recentNotifications].
  static const int _kMaxHistory = 50;

  /// Ordered list of recently received notifications (newest first).
  final List<NotificationItem> recentNotifications = [];

  StreamSubscription<dynamic>? _eventSub;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start listening for notifications from the native layer.
  ///
  /// Call [requestPermission] first if the user has not yet granted
  /// notification access to this app.
  void startListening() {
    _eventSub?.cancel();
    _eventSub = _kNotificationChannel.receiveBroadcastStream().listen(
          _onNativeNotification,
          onError: (Object err) =>
              debugPrint('[NotificationService] stream error: $err'),
        );
  }

  /// Ask the OS to open the Notification Access settings screen so the user
  /// can grant permission to this app.
  Future<void> requestPermission() async {
    try {
      await _kPermissionChannel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException catch (e) {
      debugPrint('[NotificationService] requestPermission error: $e');
    }
  }

  /// Checks whether notification listener permission is currently granted.
  Future<bool> isPermissionGranted() async {
    try {
      final result = await _kPermissionChannel
          .invokeMethod<bool>('isNotificationPermissionGranted');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Stop listening and release resources.
  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _onNativeNotification(dynamic event) {
    if (event is! Map) return;

    final item = NotificationItem(
      packageName: (event['package'] as String?) ?? '',
      title: (event['title'] as String?) ?? '',
      body: (event['text'] as String?) ?? '',
      receivedAt: DateTime.now(),
    );

    // Forward to BLE immediately; mark as sent after success
    _bleService.sendNotification(item).then((_) {
      final idx = recentNotifications.indexOf(item);
      if (idx != -1) {
        recentNotifications[idx] = item.markSent();
        notifyListeners();
      }
    }).catchError((Object _) {
      // Keep item in list as not-sent; BLE might reconnect later
    });

    // Prepend to history and trim to max size
    recentNotifications.insert(0, item);
    if (recentNotifications.length > _kMaxHistory) {
      recentNotifications.removeRange(_kMaxHistory, recentNotifications.length);
    }
    notifyListeners();
  }
}
