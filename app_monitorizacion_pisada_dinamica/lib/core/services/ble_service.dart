import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/packet_decoder.dart';

const String kServiceUuid  = '12345678-1234-1234-1234-123456789abc';
const String kSensorUuid   = '12345678-1234-1234-1234-123456789abd';
const String kCmdUuid      = '12345678-1234-1234-1234-123456789abe';
const String kDeviceName   = 'ESP32S3-DAS';
const int    kOtaChunkSize = 200;

enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleDeviceInfo {
  final String id;
  final String name;
  final int rssi;
  BleDeviceInfo({required this.id, required this.name, required this.rssi});
}

class BleService {
  final _connectionStateCtrl = StreamController<BleConnectionState>.broadcast();
  final _packetCtrl          = StreamController<DecodedPacket>.broadcast();
  final _scanResultsCtrl     = StreamController<List<BleDeviceInfo>>.broadcast();
  final _otaProgressCtrl     = StreamController<double>.broadcast();

  Stream<BleConnectionState>  get connectionStateStream => _connectionStateCtrl.stream;
  Stream<DecodedPacket>       get packetStream          => _packetCtrl.stream;
  Stream<List<BleDeviceInfo>> get scanResultsStream     => _scanResultsCtrl.stream;
  Stream<double>              get otaProgressStream     => _otaProgressCtrl.stream;

  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _sensorChr;
  BluetoothCharacteristic?  _cmdChr;
  StreamSubscription?       _notifySub;
  StreamSubscription?       _connStateSub;
  StreamSubscription?       _scanSub;
  BleConnectionState        _state = BleConnectionState.disconnected;

  final _ackCtrl = StreamController<AckPacket>.broadcast();

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every(
          (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_state == BleConnectionState.connected) return;

    final hasPerms = await requestPermissions();
    if (!hasPerms) throw Exception('Permisos BLE denegados');

    if (await FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth no disponible');
    }

    _setState(BleConnectionState.scanning);

    final seen = <String, BleDeviceInfo>{};

    await FlutterBluePlus.startScan(timeout: timeout);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName.isEmpty) continue;
        seen[r.device.remoteId.str] = BleDeviceInfo(
          id: r.device.remoteId.str,
          name: r.device.platformName,
          rssi: r.rssi,
        );
      }
      _scanResultsCtrl.add(seen.values.toList());
    });

    Future.delayed(timeout + const Duration(milliseconds: 500), () {
      if (_state == BleConnectionState.scanning) {
        _setState(BleConnectionState.disconnected);
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  Future<void> connectToDevice(String deviceId) async {
    await stopScan();
    _setState(BleConnectionState.connecting);

    try {
      final device = BluetoothDevice.fromId(deviceId);
      _device = device;

      _connStateSub?.cancel();
      _connStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));
      await device.requestMtu(247);

      final services = await device.discoverServices();

      final service = services.firstWhere(
            (s) => s.serviceUuid == Guid(kServiceUuid),
      );

      _sensorChr = service.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(kSensorUuid),
      );

      _cmdChr = service.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(kCmdUuid),
      );

      await _sensorChr!.setNotifyValue(true);

      _notifySub?.cancel();
      _notifySub = _sensorChr!.lastValueStream.listen(_onNotification);

      _setState(BleConnectionState.connected);

    } catch (e) {
      _onDisconnected();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final deviceToDisconnect = _device;
    if (deviceToDisconnect == null) return;

    try {
      await deviceToDisconnect.disconnect();
    } catch (_) {}
  }

  void _onDisconnected() {
    _notifySub?.cancel();
    _notifySub = null;

    _connStateSub?.cancel();
    _connStateSub = null;

    _scanSub?.cancel();
    _scanSub = null;

    _sensorChr = null;
    _cmdChr    = null;
    _device    = null;

    _setState(BleConnectionState.disconnected);
  }

  void _onNotification(List<int> raw) {
    final packet = PacketDecoder.decode(raw);
    if (packet == null) return;

    if (packet is AckPacket) {
      _ackCtrl.add(packet);
    }

    _packetCtrl.add(packet);
  }

  Future<void> writeCmd(Uint8List data) async {
    if (_cmdChr == null) throw Exception('No conectado');
    await _cmdChr!.write(data, withoutResponse: false);
  }

  void _setState(BleConnectionState s) {
    _state = s;
    _connectionStateCtrl.add(s);
  }

  BleConnectionState get currentState => _state;
  bool get isConnected => _state == BleConnectionState.connected;

  void dispose() {
    _notifySub?.cancel();
    _connStateSub?.cancel();
    _scanSub?.cancel();
    _connectionStateCtrl.close();
    _packetCtrl.close();
    _scanResultsCtrl.close();
    _otaProgressCtrl.close();
    _ackCtrl.close();
  }
  Future<void> flashFirmware(
      Uint8List firmware, {
        required Function(double) onProgress,
        required Function(String) onError,
      }) async {
    if (!isConnected || _cmdChr == null) {
      throw Exception('Dispositivo no conectado');
    }

    try {
      final totalSize = firmware.length;
      int offset = 0;

      // ─── 1. Comando inicio OTA (opcional según tu firmware ESP32) ───
      await writeCmd(Uint8List.fromList([0x01]));

      while (offset < totalSize) {
        final end = (offset + kOtaChunkSize > totalSize)
            ? totalSize
            : offset + kOtaChunkSize;

        final chunk = firmware.sublist(offset, end);

        // ─── 2. Enviar chunk ───
        await writeCmd(chunk);

        // ─── 3. Esperar ACK del ESP32 ───
        await _ackCtrl.stream.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            throw Exception('Timeout esperando ACK');
          },
        );

        offset = end;

        final progress = offset / totalSize;
        onProgress(progress);
        _otaProgressCtrl.add(progress);
      }

      // ─── 4. Finalizar OTA ───
      await writeCmd(Uint8List.fromList([0x02]));

    } catch (e) {
      onError(e.toString());
      rethrow;
    }
  }
}