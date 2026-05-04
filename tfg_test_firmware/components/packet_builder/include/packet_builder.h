#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* ═══════════════════════════════════════════════════════════════════════════
 * JUSTIFICACIÓN DEL FORMATO DE PAQUETE (bit-packing)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Como indica el tutor: primero entender el problema físico, luego codificar.
 *
 * ┌──────────────┬──────────────┬────────────────┬────────┬──────────────────┐
 * │ Sensor       │ Rango físico │ Resolución útil│  Bits  │ Razón            │
 * ├──────────────┼──────────────┼────────────────┼────────┼──────────────────┤
 * │ Accel X/Y/Z  │ ±16 g        │ 0.01 g → 3200v │ 12 bit │ 2^12=4096 > 3200 │
 * │ Gyro  X/Y/Z  │ ±2000 °/s    │ 0.5  → 8000 v  │ 13 bit │ 2^13=8192 > 8000 │
 * │ Mag   X/Y/Z  │ ±8 Gauss     │ 0.001→ 16000 v │ 14 bit │ 2^14=16384>16000 │
 * │ Presion ×4   │ 0–100 kg     │ 1 g → 100000 v │ 17 bit │ 2^17=131072>1e5  │
 * │ Termistor ×2 │ 0–100 °C     │ 0.1°→ 1000 v   │ 10 bit │ 2^10=1024 > 1000 │
 * └──────────────┴──────────────┴────────────────┴────────┴──────────────────┘
 *
 * Payload total:
 *   3×12 + 3×13 + 3×14 + 4×17 + 2×10 = 36+39+42+68+20 = 205 bits = 26 bytes
 *
 * Paquete completo (header 7B + payload 26B + CRC 1B) = 34 BYTES
 *
 * Comparación:
 *   - 15 floats (sin empaquetar)     → 60 bytes solo payload
 *   - JSON                           → ~300–500 bytes
 *   - Bit-packed (esta impl.)        → 34 bytes totales  ← 82% menos que JSON
 *
 * IMPACTO ENERGÉTICO:
 *   Con NimBLE y MTU=247B, todos los datos caben en 1 sola notificación BLE.
 *   Menos notificaciones = menos eventos radio = menos corriente.
 *   TX BLE activo ≈ 7.3 mA; reducir de 2 eventos a 1 supone ~47% menos
 *   tiempo en transmisión por muestra → ahorro directo en batería.
 *
 * DECODIFICACIÓN EN EL MÓVIL:
 *   Leer N bits consecutivos, restar offset, dividir por escala → float.
 *   Ejemplo: bits[0:11] → accel_x_raw; accel_x = (raw - 1600) / 100.0
 * ═══════════════════════════════════════════════════════════════════════════ */

/* ── Tipos de paquete ───────────────────────────────────────────────────── */
#define PKT_TYPE_SENSOR   0x01   /**< Datos de sensores (bit-packed)   */
#define PKT_TYPE_ACK      0x02   /**< ACK genérico                     */
#define PKT_TYPE_STATUS   0x03   /**< Estado del sistema               */

/* ── Escalas y offsets para bit-packing ────────────────────────────────── */
#define ACCEL_BITS       12
#define ACCEL_SCALE      100      /* ×100 → 0.01g resolución            */
#define ACCEL_OFFSET     1600     /* ±16g → [0, 3200]                   */

#define GYRO_BITS        13
#define GYRO_SCALE       2        /* ×2  → 0.5°/s resolución            */
#define GYRO_OFFSET      4000     /* ±2000°/s → [0, 8000]               */

#define MAG_BITS         14
#define MAG_SCALE        1000     /* ×1000 → 0.001G resolución          */
#define MAG_OFFSET       8000     /* ±8G → [0, 16000]                   */

#define PRESSURE_BITS    17       /* 0–100000 g directo                 */
#define PRESSURE_MAX     100000u

#define THERMISTOR_BITS  10       /* 0–100.0°C (×10) → [0, 1000]       */
#define THERMISTOR_SCALE 10

#define NUM_PRESSURE_SENSORS  4
#define NUM_THERMISTOR_SENSORS 2

/* ── Tamaños de paquete ─────────────────────────────────────────────────── */
#define PKT_HEADER_BYTES  7       /* type(1) + seq(2) + ts_ms(4)        */
#define PKT_PAYLOAD_BITS  205
#define PKT_PAYLOAD_BYTES ((PKT_PAYLOAD_BITS + 7) / 8)  /* 26 bytes    */
#define PKT_CRC_BYTES     1
#define PKT_SENSOR_SIZE   (PKT_HEADER_BYTES + PKT_PAYLOAD_BYTES + PKT_CRC_BYTES)  /* 34 */
#define PKT_ACK_SIZE      4       /* type(1) + ack_type(1) + status(1) + crc(1) */

/* ── Estructura de datos de sensores ───────────────────────────────────── */
typedef struct {
    float    accel_x, accel_y, accel_z;                    /* g          */
    float    gyro_x,  gyro_y,  gyro_z;                     /* °/s        */
    float    mag_x,   mag_y,   mag_z;                      /* Gauss      */
    uint32_t pressure[NUM_PRESSURE_SENSORS];               /* gramos     */
    float    temperature[NUM_THERMISTOR_SENSORS];          /* °C         */
} sensor_data_t;

/* ── API pública ────────────────────────────────────────────────────────── */
void    packet_builder_init(void);

/**
 * @brief Empaqueta sensor_data_t en formato bit-packed.
 * @param data    Datos de sensores.
 * @param buf     Buffer de salida (debe tener ≥ PKT_SENSOR_SIZE bytes).
 * @param out_len Bytes escritos en buf.
 * @return true si OK.
 */
bool    packet_build_sensor(const sensor_data_t *data,
                            uint8_t *buf, size_t *out_len);

/**
 * @brief Construye un paquete ACK.
 * @param ack_type Tipo de evento que se confirma (usa defines de ota_manager.h).
 * @param status   0 = OK, otro = error code.
 */
bool    packet_build_ack(uint8_t ack_type, uint8_t status,
                         uint8_t *buf, size_t *out_len);

uint8_t packet_crc8(const uint8_t *data, size_t len);

