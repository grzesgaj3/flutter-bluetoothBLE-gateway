import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/notification_item.dart';

// ---------------------------------------------------------------------------
// UUID constants
// ---------------------------------------------------------------------------

/// Custom BLE service hosted by the smartwatch prototype.
const String _kServiceUuid = '0000FFE0-0000-1000-8000-00805F9B34FB';

/// Time-sync characteristic (Write-only): sends current date/time as bytes.
const String _kTimeSyncUuid = '0000FFE1-0000-1000-8000-00805F9B34FB';

/// Push-notification characteristic (Write-only): sends notification payload.
const String _kPushNotifyUuid = '0000FFE2-0000-1000-8000-00805F9B34FB';

/// Battery-level characteristic (Read + Notify): 1-byte value 0–100.
const String _kBatteryUuid = '0000FFE4-0000-1000-8000-00805F9B34FB';

/// Target device name to connect to.
const String _kTargetDeviceName = 'SmartWatch_Proto';

/// Scan timeout.
const Duration _kScanTimeout = Duration(seconds: 15);

/// Conservative default MTU payload size used when the negotiated MTU is
/// unknown (3-byte ATT header is already excluded here).
const int _kDefaultMtuPayload = 20;

// ---------------------------------------------------------------------------
// BleService
// ---------------------------------------------------------------------------

/// Manages BLE scanning, connection, characteristic I/O and exposes state
/// via [ChangeNotifier] so the UI can rebuild reactively.
class BleService extends ChangeNotifier {
  // ── Public state ──────────────────────────────────────────────────────────

  /// Latest known connection status to display in the UI.
  String connectionStatus = 'Disconnected';

  /// Battery level reported by the smartwatch (0–100, null = unknown).
  int? batteryLevel;

  /// Whether an active connection to the device exists right now.
  bool get isConnected => _device != null && _connected;

  // ── Private fields ────────────────────────────────────────────────────────

  BluetoothDevice? _device;
  bool _connected = false;
  int _mtuPayload = _kDefaultMtuPayload;

  BluetoothCharacteristic? _timeSyncChar;
  BluetoothCharacteristic? _pushNotifyChar;
  BluetoothCharacteristic? _batteryChar;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _batterySub;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Begin scanning for [_kTargetDeviceName] and connect when found.
  Future<void> startScan() async {
    if (FlutterBluePlus.isScanningNow) return;

    _setStatus('Scanning…');

    await FlutterBluePlus.startScan(timeout: _kScanTimeout);

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (result.device.platformName == _kTargetDeviceName) {
          _scanSub?.cancel();
          FlutterBluePlus.stopScan();
          _connectToDevice(result.device);
          return;
        }
      }
    });
  }

  /// Disconnect cleanly and reset internal state.
  Future<void> disconnect() async {
    await _device?.disconnect();
    _resetState();
  }

  /// Write [notification] to the Push-Notify (FFE2) characteristic.
  ///
  /// Payload structure (per spec):
  ///   [0x02][titleLen][title bytes][body bytes]
  ///
  /// Long payloads are split into MTU-sized chunks so that the watch
  /// receives a complete, ordered byte stream.
  Future<void> sendNotification(NotificationItem notification) async {
    if (_pushNotifyChar == null || !_connected) return;

    final titleBytes = utf8.encode(notification.title);
    final bodyBytes = utf8.encode(notification.body);

    // Build the full payload
    final payload = <int>[
      0x02, // type = notification
      titleBytes.length & 0xFF, // title length (1 byte, max 255)
      ...titleBytes,
      ...bodyBytes,
    ];

    // Write in MTU-sized chunks (write without response is faster for bulk)
    for (int offset = 0; offset < payload.length; offset += _mtuPayload) {
      final end =
          (offset + _mtuPayload > payload.length) ? payload.length : offset + _mtuPayload;
      final chunk = payload.sublist(offset, end);
      await _pushNotifyChar!.write(chunk, withoutResponse: true);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _setStatus('Connecting…');
    _device = device;

    _connSub = device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        _connected = true;
        _setStatus('Connected');
        await _onConnected(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        _connected = false;
        _setStatus('Disconnected');
        _resetCharacteristics();
        // Auto-reconnect after a short delay
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!_connected) await startScan();
      }
    });

    await device.connect(autoConnect: false);
  }

  Future<void> _onConnected(BluetoothDevice device) async {
    // Request a larger MTU to reduce the number of write chunks
    try {
      final mtu = await device.requestMtu(512);
      // ATT protocol reserves 3 bytes for header
      _mtuPayload = (mtu - 3).clamp(20, 512);
    } catch (_) {
      _mtuPayload = _kDefaultMtuPayload;
    }

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() ==
          _kServiceUuid.toUpperCase()) {
        await _bindCharacteristics(service);
        break;
      }
    }

    // Immediately sync current time after connection is established
    await _sendTimeSync();
  }

  Future<void> _bindCharacteristics(BluetoothService service) async {
    for (final char in service.characteristics) {
      final uuid = char.uuid.toString().toUpperCase();
      if (_uuidMatches(uuid, _kTimeSyncUuid)) {
        _timeSyncChar = char;
      } else if (_uuidMatches(uuid, _kPushNotifyUuid)) {
        _pushNotifyChar = char;
      } else if (_uuidMatches(uuid, _kBatteryUuid)) {
        _batteryChar = char;
        await _subscribeToBattery(char);
      }
    }
  }

  /// Returns true if [uuid] matches [target], supporting both full 128-bit
  /// and short 16-bit representations (e.g. "FFE1" or the full UUID string).
  bool _uuidMatches(String uuid, String target) {
    final normalised = uuid.toUpperCase();
    final normalTarget = target.toUpperCase();
    return normalised == normalTarget || normalised.contains(normalTarget);
  }

  /// Writes the current local time to the Time-Sync (FFE1) characteristic.
  ///
  /// Byte layout: [year_hi][year_lo][month][day][hour][minute][second]
  /// (year is split into two bytes, big-endian)
  Future<void> _sendTimeSync() async {
    if (_timeSyncChar == null) return;

    final now = DateTime.now();
    final payload = <int>[
      (now.year >> 8) & 0xFF, // year high byte
      now.year & 0xFF, // year low byte
      now.month, // 1–12
      now.day, // 1–31
      now.hour, // 0–23
      now.minute, // 0–59
      now.second, // 0–59
    ];

    await _timeSyncChar!.write(payload, withoutResponse: false);
  }

  Future<void> _subscribeToBattery(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    _batterySub = char.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        batteryLevel = value[0].clamp(0, 100);
        notifyListeners();
      }
    });

    // Trigger an initial read so we have a value right away
    try {
      final initial = await char.read();
      if (initial.isNotEmpty) {
        batteryLevel = initial[0].clamp(0, 100);
        notifyListeners();
      }
    } catch (_) {
      // Not critical – notification will update the value soon
    }
  }

  void _resetCharacteristics() {
    _batterySub?.cancel();
    _batterySub = null;
    _timeSyncChar = null;
    _pushNotifyChar = null;
    _batteryChar = null;
    batteryLevel = null;
    notifyListeners();
  }

  void _resetState() {
    _connSub?.cancel();
    _scanSub?.cancel();
    _connected = false;
    _device = null;
    _resetCharacteristics();
    _setStatus('Disconnected');
  }

  void _setStatus(String status) {
    connectionStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _scanSub?.cancel();
    _batterySub?.cancel();
    super.dispose();
  }
}
