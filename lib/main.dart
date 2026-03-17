import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/ble_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request runtime permissions required for BLE on Android 12+
  await _requestBlePermissions();

  runApp(const GatewayApp());
}

/// Requests Bluetooth and Location permissions required for BLE scanning on
/// Android.  On Android 12+ BLUETOOTH_SCAN / BLUETOOTH_CONNECT are required;
/// on older versions ACCESS_FINE_LOCATION is needed instead.
Future<void> _requestBlePermissions() async {
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}

class GatewayApp extends StatelessWidget {
  const GatewayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // BLE service – manages device scanning, connection, GATT I/O
        ChangeNotifierProvider<BleService>(create: (_) => BleService()),

        // Notification service – listens to Android notifications and uses
        // BleService to forward them to the smartwatch
        ChangeNotifierProxyProvider<BleService, NotificationService>(
          create: (ctx) => NotificationService(
            bleService: ctx.read<BleService>(),
          ),
          update: (_, ble, previous) =>
              previous ?? NotificationService(bleService: ble),
        ),
      ],
      child: MaterialApp(
        title: 'BLE Gateway',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
          useMaterial3: true,
        ),
        home: const _AppRoot(),
      ),
    );
  }
}

/// Root widget that initialises services and starts BLE scanning once the
/// widget tree is ready.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final notifService = context.read<NotificationService>();
    final bleService = context.read<BleService>();

    // Ensure Bluetooth adapter is on; handle the case where it is off
    if (await FlutterBluePlus.adapterState.first ==
        BluetoothAdapterState.on) {
      unawaited(bleService.startScan());
    }

    // Check notification access; prompt user if not yet granted
    final hasPermission = await notifService.isPermissionGranted();
    if (!hasPermission && mounted) {
      _showNotificationPermissionDialog();
    } else {
      notifService.startListening();
    }
  }

  void _showNotificationPermissionDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Notification Access Required'),
        content: const Text(
          'This app needs permission to read notifications so it can forward '
          'them to your smartwatch.\n\n'
          'Tap "Open Settings", enable "BLE Gateway" in the list, then return '
          'to the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<NotificationService>().requestPermission();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

/// Explicitly marks a [Future] as intentionally not awaited (fire-and-forget).
/// Using this helper suppresses Dart's `unawaited_futures` lint warning.
// ignore: prefer_void_to_null
void unawaited(Future<void> future) {}
