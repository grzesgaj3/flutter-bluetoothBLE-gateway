import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/notification_item.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';

/// Main screen of the BLE Gateway application.
///
/// Displays:
///   • BLE connection status + connect/disconnect button
///   • Smartwatch battery level (large percentage indicator)
///   • List of recently forwarded notifications
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Gateway'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _BleStatusCard(),
          _BatteryCard(),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Notifications',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const Expanded(child: _NotificationList()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BLE status card
// ---------------------------------------------------------------------------

class _BleStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    final isConnected = ble.isConnected;
    final statusColor = isConnected ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: statusColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BLE Status',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    ble.connectionStatus,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: statusColor),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: isConnected
                  ? () => ble.disconnect()
                  : () => ble.startScan(),
              icon: Icon(isConnected ? Icons.link_off : Icons.search),
              label: Text(isConnected ? 'Disconnect' : 'Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isConnected ? Colors.red.shade400 : Colors.blue.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Battery level card
// ---------------------------------------------------------------------------

class _BatteryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final level = ble.batteryLevel;

    Color batteryColor;
    if (level == null) {
      batteryColor = Colors.grey;
    } else if (level <= 20) {
      batteryColor = Colors.red;
    } else if (level <= 50) {
      batteryColor = Colors.orange;
    } else {
      batteryColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _batteryIcon(level),
              color: batteryColor,
              size: 40,
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                Text(
                  'Smartwatch Battery',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  level != null ? '$level%' : '—',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: batteryColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            if (level != null) ...[
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: level / 100,
                  color: batteryColor,
                  backgroundColor: Colors.grey.shade200,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown;
    if (level <= 10) return Icons.battery_0_bar;
    if (level <= 30) return Icons.battery_2_bar;
    if (level <= 50) return Icons.battery_3_bar;
    if (level <= 70) return Icons.battery_5_bar;
    return Icons.battery_full;
  }
}

// ---------------------------------------------------------------------------
// Notification list
// ---------------------------------------------------------------------------

class _NotificationList extends StatelessWidget {
  const _NotificationList();

  @override
  Widget build(BuildContext context) {
    final notifications =
        context.watch<NotificationService>().recentNotifications;

    if (notifications.isEmpty) {
      return const Center(
        child: Text(
          'No notifications yet',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) =>
          _NotificationTile(item: notifications[index]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            item.sent ? Colors.green.shade100 : Colors.orange.shade100,
        child: Icon(
          item.sent ? Icons.check : Icons.pending,
          color: item.sent ? Colors.green : Colors.orange,
          size: 18,
        ),
      ),
      title: Text(
        item.title.isNotEmpty ? item.title : '(no title)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        item.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTime(item.receivedAt),
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
