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

  BleConnectionState _state = BleConnectionState.disconnected;

  final _ackCtrl = StreamController<AckPacket>.broadcast();

  bool _isDisconnecting = false;
  bool _isConnecting    = false;

  void _log(String msg) {
    print('[BLE] $msg');
  }

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
    await _scanSub?.cancel();
    _scanSub = null;

    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  Future<void> connectToDevice(String deviceId) async {
    await stopScan();

    if (_state == BleConnectionState.connecting) {
      _log('Ya conectando, ignorando...');
      return;
    }

    _setState(BleConnectionState.connecting);
    _isDisconnecting = false;
    _isConnecting = true;

    try {
      final device = BluetoothDevice.fromId(deviceId);
      _device = device;

      await _connStateSub?.cancel();
      _connStateSub = device.connectionState.listen((state) {
        _log('Device state update: $state');

        if (state == BluetoothConnectionState.disconnected) {
          if (_isConnecting) {
            _log('⚠️ Ignorando disconnect durante conexión');
            return;
          }
          _onDisconnected();
        }
      });

      _log('Conectando...');
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      if (_device == null) {
        _log('⚠️ Conexión abortada (device null)');
        return;
      }

      _log('Solicitando MTU...');
      await device.requestMtu(247);

      _log('Descubriendo servicios...');
      final services = await device.discoverServices();

      if (_device == null) {
        _log('⚠️ Conexión abortada tras discoverServices');
        return;
      }

      final service = services.firstWhere(
            (s) => s.serviceUuid == Guid(kServiceUuid),
      );

      _sensorChr = service.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(kSensorUuid),
      );

      _cmdChr = service.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(kCmdUuid),
      );

      _log('Activando notificaciones...');
      await _sensorChr!.setNotifyValue(true);

      await _notifySub?.cancel();
      _notifySub = _sensorChr!.lastValueStream.listen(_onNotification);

      _isConnecting = false;

      _setState(BleConnectionState.connected);
      _log('✅ Conectado correctamente');

    } catch (e) {
      _isConnecting = false;
      _log('❌ Error conectando: $e');
      await _forceCleanup();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_device == null) return;

    if (_isDisconnecting) {
      _log('Ya en proceso de desconexión...');
      return;
    }

    _isDisconnecting = true;
    _log('🔌 Desconectando manualmente...');

    try {
      await _device!.disconnect();
    } catch (e) {
      _log('Error en disconnect(): $e');
    }
  }

  void _onDisconnected() {
    if (_isDisconnecting) {
      _log('✅ Desconectado correctamente');
    } else {
      _log('⚠️ Desconexión inesperada');
    }

    _forceCleanup();
  }

  Future<void> _forceCleanup() async {
    _log('🧹 Limpiando recursos BLE...');

    try { await _notifySub?.cancel(); } catch (_) {}
    _notifySub = null;

    try { await _connStateSub?.cancel(); } catch (_) {}
    _connStateSub = null;

    try { await _scanSub?.cancel(); } catch (_) {}
    _scanSub = null;

    _sensorChr = null;
    _cmdChr = null;
    _device = null;

    _isDisconnecting = false;
    _isConnecting = false;

    if (_state != BleConnectionState.disconnected) {
      _setState(BleConnectionState.disconnected);
    }

    _log('🧹 Cleanup completo');
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
    if (_state == s) return;
    _log('Estado: $_state -> $s');
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

      await writeCmd(Uint8List.fromList([0x01]));

      while (offset < totalSize) {
        final end = (offset + kOtaChunkSize > totalSize)
            ? totalSize
            : offset + kOtaChunkSize;

        final chunk = firmware.sublist(offset, end);

        await writeCmd(chunk);

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

      await writeCmd(Uint8List.fromList([0x02]));

    } catch (e) {
      onError(e.toString());
      rethrow;
    }
  }
}