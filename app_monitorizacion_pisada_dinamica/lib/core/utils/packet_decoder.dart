// lib/core/utils/packet_decoder.dart
//
// Espejo exacto del bit-packing definido en packet_builder.h / packet_builder.c
// del firmware ESP32-NimBLE.
//
// Formato del paquete (54 bytes):
//   [0]      type     (0x01 = sensor, 0x02 = ACK, 0x03 = status)
//   [1-2]    seq      uint16 big-endian
//   [3-6]    ts_ms    uint32 big-endian
//   [7-52]   payload  46 bytes, 361 bits empaquetados
//   [53]     CRC-8    polinomio 0x07, init 0xFF
//
// Layout del payload (bits acumulados):
//   Accel X/Y/Z    : 3 × 12 bits, offset 1600, scale 100  → g
//   Gyro  X/Y/Z    : 3 × 13 bits, offset 4000, scale 2    → °/s
//   Mag   X/Y/Z    : 3 × 14 bits, offset 8000, scale 1000 → Gauss
//   Pressure[0-11] : 12 × 17 bits, 0–10000 g directo (fondo real del FSR: 10 kg)
//   Thermistor[0-3]: 4 × 10 bits, ×10 → °C
//   Total: 36+39+42+204+40 = 361 bits

import 'dart:math';
import 'dart:typed_data';
import '../../shared/models/sensor_data.dart';

// ─── Constantes del protocolo ─────────────────────────────────────────────────

const int kPktTypeSensor = 0x01;
const int kPktTypeAck    = 0x02;
const int kPktTypeStatus = 0x03;
const int kPktSensorSize = 54;
const int kPktHeaderBytes = 7;
const int kPktPayloadBytes = 46;
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

  // ── Leer N bits desde la posición bitPos del buffer ───────────────────────
  // Replica exactamente bitpack_write() en sentido inverso:
  //   bit_pos 0 → byte 0, bit 7 (MSB)
  //   bit_pos 1 → byte 0, bit 6
  //   ...
  static int _readBits(Uint8List buf, int bitPos, int numBits) {
    int result = 0;
    for (int i = numBits - 1; i >= 0; i--) {
      final byteIdx = bitPos ~/ 8;
      final bitIdx  = 7 - (bitPos % 8);
      if (byteIdx < buf.length && (buf[byteIdx] >> bitIdx) & 1 == 1) {
        result |= (1 << i);
      }
      bitPos++;
    }
    return result;
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

    // ── Verificar CRC ─────────────────────────────────────────────────────
    final expectedCrc = crc8(buf, kPktHeaderBytes + kPktPayloadBytes);
    if (buf[kPktHeaderBytes + kPktPayloadBytes] != expectedCrc) return null;

    // ── Header ────────────────────────────────────────────────────────────
    final seq  = (buf[1] << 8) | buf[2];
    final tsMs = (buf[3] << 24) | (buf[4] << 16) | (buf[5] << 8) | buf[6];

    // ── Payload ───────────────────────────────────────────────────────────
    final payload = buf.sublist(kPktHeaderBytes, kPktHeaderBytes + kPktPayloadBytes);
    int bitPos = 0;

    // Acelerómetro — 3 × 12 bits, offset 1600, scale 100 → g → ×9.81 = m/s²
    final axG = (_readBits(payload, bitPos,      12) - 1600) / 100.0; bitPos += 12;
    final ayG = (_readBits(payload, bitPos,      12) - 1600) / 100.0; bitPos += 12;
    final azG = (_readBits(payload, bitPos,      12) - 1600) / 100.0; bitPos += 12;

    // Giróscopo — 3 × 13 bits, offset 4000, scale 2 → °/s
    final gx = (_readBits(payload, bitPos, 13) - 4000) / 2.0; bitPos += 13;
    final gy = (_readBits(payload, bitPos, 13) - 4000) / 2.0; bitPos += 13;
    final gz = (_readBits(payload, bitPos, 13) - 4000) / 2.0; bitPos += 13;

    // Magnetómetro — 3 × 14 bits, offset 8000, scale 1000 → Gauss → ×100 = µT
    final mx = (_readBits(payload, bitPos, 14) - 8000) / 1000.0 * 100.0; bitPos += 14;
    final my = (_readBits(payload, bitPos, 14) - 8000) / 1000.0 * 100.0; bitPos += 14;
    final mz = (_readBits(payload, bitPos, 14) - 8000) / 1000.0 * 100.0; bitPos += 14;

    // Presión — 12 × 17 bits, valor directo en gramos (0–10000, fondo real del FSR)
    final List<double> pressure = [];
    for (int i = 0; i < kNumPressureSensors; i++) {
      pressure.add(_readBits(payload, bitPos, 17).toDouble()); bitPos += 17;
    }

    // Termistores — 4 × 10 bits, ×10 → °C
    final List<double> temperature = [];
    for (int i = 0; i < kNumThermistorSensors; i++) {
      temperature.add(_readBits(payload, bitPos, 10) / 10.0); bitPos += 10;
    }

    // ── Orientación derivada ──────────────────────────────────────────────
    // Acelerómetro en g, convertir a m/s² para el modelo
    final accX = axG * 9.81;
    final accY = ayG * 9.81;
    final accZ = azG * 9.81;

    // Roll y pitch desde acelerómetro (aproximación estática)
    final roll  = atan2(ayG, azG) * 180.0 / pi;
    final pitch = atan2(-axG, sqrt(ayG * ayG + azG * azG)) * 180.0 / pi;
    // Yaw simplificado desde magnetómetro (asumiendo dispositivo nivelado)
    final yaw   = atan2(-my, mx) * 180.0 / pi;

    // ── 12 sensores FSR y 4 termistores, uno a uno (sin agrupar por zonas) ──
    // Debe coincidir con FSR_PRESSURE_MAX_G en sensor_manager.c y PRESSURE_MAX
    // en packet_builder.h: fondo de escala real del sensor (10 kg).
    const double kMaxPressureG = 10000.0;
    final fsr = pressure.map((g) => (g / kMaxPressureG).clamp(0.0, 1.0)).toList();

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