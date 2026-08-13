// lib/core/utils/packet_decoder.dart
//
// Espejo exacto del formato definido en packet_builder.h / packet_builder.c
// del firmware ESP32-NimBLE.
//
// Formato del paquete (59 bytes), RAW — el firmware NO convierte nada a
// unidades físicas, solo manda las cuentas crudas de los sensores. Toda la
// conversión física se hace aquí, con las fórmulas de sensor_calibration.dart
// (así se puede recalibrar sin reflashear el ESP32-S3):
//   [0]      type      (0x01 = sensor, 0x02 = ACK, 0x03 = status)
//   [1]      version   debe coincidir con kPktProtoVersion
//   [2-3]    seq       uint16 big-endian
//   [4-7]    ts_ms     uint32 big-endian
//   [8-57]   payload   50 bytes, 25 × int16 big-endian, RAW, orden fijo:
//              [0-2]   accel_x, accel_y, accel_z   (registros LSM9DS1)
//              [3-5]   gyro_x,  gyro_y,  gyro_z    (registros LSM9DS1)
//              [6-8]   mag_x,   mag_y,   mag_z     (registros LSM9DS1)
//              [9-20]  pressure_raw[0..11]         (cuentas ADC, 12 FSR)
//              [21-24] thermistor_raw[0..3]        (cuentas ADC, 4 NTC)
//   [58]     CRC-8     polinomio 0x07, init 0xFF

import 'dart:typed_data';
import 'dart:math';
import '../../shared/models/sensor_data.dart';
import 'sensor_calibration.dart';

// ─── Constantes del protocolo ─────────────────────────────────────────────────

const int kPktTypeSensor = 0x01;
const int kPktTypeAck    = 0x02;
const int kPktTypeStatus = 0x03;
const int kPktProtoVersion = 2;
const int kPktSensorSize = 59;
const int kPktHeaderBytes = 8;
const int kPktPayloadBytes = 50;
const int kNumPressureSensors = 12;
const int kNumThermistorSensors = 4;

// OTA commands (Flutter → ESP32 via CHR_CMD write)
const int kOtaCmdStart = 0x10; // [0x10][4B total_size LE]
const int kOtaCmdChunk = 0x11; // [0x11][2B chunk_idx LE][data...]
const int kOtaCmdEnd   = 0x12; // [0x12]
const int kOtaCmdAbort = 0x13; // [0x13]

// OTA ACK types (ESP32 → Flutter via CHR_SENSOR notification)
const int kOtaAckStart = 0x10;
const int kOtaAckChunk = 0x11;
const int kOtaAckEnd   = 0x12;

// ─── Resultado de decodificación ──────────────────────────────────────────────

sealed class DecodedPacket {}

class SensorPacket extends DecodedPacket {
  final int seq;
  final int tsMs;
  final SensorData data;
  SensorPacket({required this.seq, required this.tsMs, required this.data});
}

class AckPacket extends DecodedPacket {
  final int ackType;
  final int status; // 0 = OK
  AckPacket({required this.ackType, required this.status});
}

class UnknownPacket extends DecodedPacket {
  final int type;
  UnknownPacket(this.type);
}

// ─── Decoder ─────────────────────────────────────────────────────────────────

class PacketDecoder {

  // ── CRC-8, polinomio 0x07, init 0xFF — igual que packet_builder.c ─────────
  static int crc8(Uint8List data, int len) {
    int crc = 0xFF;
    for (int i = 0; i < len; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ 0x07) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
    }
    return crc;
  }

  // ── Leer un int16 big-endian con signo desde el offset dado ───────────────
  static int _readInt16BE(Uint8List buf, int offset) {
    final v = (buf[offset] << 8) | buf[offset + 1];
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  // ── Punto de entrada principal ────────────────────────────────────────────
  static DecodedPacket? decode(List<int> raw) {
    if (raw.isEmpty) return null;
    final buf = Uint8List.fromList(raw);

    final type = buf[0];

    if (type == kPktTypeAck && buf.length >= 4) {
      // ACK packet: [type][ack_type][status][crc]
      final expectedCrc = crc8(buf, 3);
      if (buf[3] != expectedCrc) return null; // CRC error
      return AckPacket(ackType: buf[1], status: buf[2]);
    }

    if (type == kPktTypeSensor) {
      return _decodeSensorPacket(buf);
    }

    return UnknownPacket(type);
  }

  static SensorPacket? _decodeSensorPacket(Uint8List buf) {
    if (buf.length < kPktSensorSize) return null;

    // ── Version del protocolo ───────────────────────────────────────────────
    // Firmware y app deben ir sincronizados. Sin esto, un mismatch de formato
    // se descartaria en silencio por CRC/longitud, indistinguible de "no
    // llega nada" al depurar.
    final version = buf[1];
    if (version != kPktProtoVersion) return null;

    // ── Verificar CRC ─────────────────────────────────────────────────────
    final expectedCrc = crc8(buf, kPktHeaderBytes + kPktPayloadBytes);
    if (buf[kPktHeaderBytes + kPktPayloadBytes] != expectedCrc) return null;

    // ── Header ────────────────────────────────────────────────────────────
    final seq  = (buf[2] << 8) | buf[3];
    final tsMs = (buf[4] << 24) | (buf[5] << 16) | (buf[6] << 8) | buf[7];

    // ── Payload: 25 × int16 BE, RAW ──────────────────────────────────────
    int off = kPktHeaderBytes;
    int nextI16() {
      final v = _readInt16BE(buf, off);
      off += 2;
      return v;
    }

    final accelXRaw = nextI16(), accelYRaw = nextI16(), accelZRaw = nextI16();
    final gyroXRaw  = nextI16(), gyroYRaw  = nextI16(), gyroZRaw  = nextI16();
    final magXRaw   = nextI16(), magYRaw   = nextI16(), magZRaw   = nextI16();

    final pressureRaw = List<int>.generate(kNumPressureSensors, (_) => nextI16());
    final thermistorRaw = List<int>.generate(kNumThermistorSensors, (_) => nextI16());

    // ── IMU: raw -> unidades físicas ───────────────────────────────────────
    final axG = SensorCalibration.accelG(accelXRaw);
    final ayG = SensorCalibration.accelG(accelYRaw);
    final azG = SensorCalibration.accelG(accelZRaw);

    final gx = SensorCalibration.gyroDps(gyroXRaw);
    final gy = SensorCalibration.gyroDps(gyroYRaw);
    final gz = SensorCalibration.gyroDps(gyroZRaw);

    // Gauss -> µT (×100), igual convención que usaban los widgets antes
    final mx = SensorCalibration.magGauss(magXRaw) * 100.0;
    final my = SensorCalibration.magGauss(magYRaw) * 100.0;
    final mz = SensorCalibration.magGauss(magZRaw) * 100.0;

    // Acelerómetro en g -> m/s² para el modelo
    final accX = axG * 9.81;
    final accY = ayG * 9.81;
    final accZ = azG * 9.81;

    // Roll y pitch desde acelerómetro (aproximación estática)
    final roll  = atan2(ayG, azG) * 180.0 / pi;
    final pitch = atan2(-axG, sqrt(ayG * ayG + azG * azG)) * 180.0 / pi;
    // Yaw simplificado desde magnetómetro (asumiendo dispositivo nivelado)
    final yaw   = atan2(-my, mx) * 180.0 / pi;

    // ── FSR: raw -> gramos -> normalizado 0..1 ─────────────────────────────
    final fsr = pressureRaw
        .map((raw) => (SensorCalibration.rawToGrams(raw) / SensorCalibration.kFsrPressureMaxG)
            .clamp(0.0, 1.0))
        .toList();

    // ── Termistores: raw -> celsius ─────────────────────────────────────────
    final temperature = thermistorRaw.map((raw) => SensorCalibration.rawToCelsius(raw)).toList();

    return SensorPacket(
      seq: seq,
      tsMs: tsMs,
      data: SensorData(
        fsr: fsr,
        temperature: temperature,
        accX: accX, accY: accY, accZ: accZ,
        gyroX: gx,  gyroY: gy,  gyroZ: gz,
        magX: mx,   magY: my,   magZ: mz,
        roll: roll, pitch: pitch, yaw: yaw,
        stepCount: 0, // detección de pasos: ver SensorDataNotifier._detectSteps
        stepGoal: 10000,
      ),
    );
  }

  // ── Constructores de comandos OTA ─────────────────────────────────────────

  static Uint8List buildOtaStart(int totalSize) {
    final buf = Uint8List(5);
    buf[0] = kOtaCmdStart;
    buf[1] = (totalSize      ) & 0xFF;
    buf[2] = (totalSize >>  8) & 0xFF;
    buf[3] = (totalSize >> 16) & 0xFF;
    buf[4] = (totalSize >> 24) & 0xFF;
    return buf;
  }

  static Uint8List buildOtaChunk(int chunkIdx, Uint8List data) {
    final buf = Uint8List(3 + data.length);
    buf[0] = kOtaCmdChunk;
    buf[1] = chunkIdx & 0xFF;
    buf[2] = (chunkIdx >> 8) & 0xFF;
    buf.setRange(3, buf.length, data);
    return buf;
  }

  static Uint8List buildOtaEnd()   => Uint8List.fromList([kOtaCmdEnd]);
  static Uint8List buildOtaAbort() => Uint8List.fromList([kOtaCmdAbort]);
}
