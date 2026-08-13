#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* ═══════════════════════════════════════════════════════════════════════════
 * FORMATO DE PAQUETE: RAW, sin convertir
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * El firmware manda las cuentas RAW de los sensores (registros del LSM9DS1,
 * cuentas ADC del ADS1115) tal cual, sin ningun escalado a unidades fisicas.
 * Toda la conversion (sensibilidad IMU, voltaje->gramos, voltaje->celsius)
 * se hace en la app movil (lib/core/utils/sensor_calibration.dart). Motivo:
 * es mucho mas rapido iterar/recalibrar cambiando codigo Dart que reflashear
 * el ESP32-S3 -- de hecho, un fondo de escala mal calibrado en firmware costo
 * varias rondas de depuracion antes de este cambio.
 *
 * Como cada campo es ya un entero nativo del sensor, no hace falta bit-packing
 * (ese ahorro de bytes solo tenia sentido cuando se mandaban floats de 4B por
 * cada eje). Con MTU=247B (BLE_PKT_MAX_SIZE=244B) el tamano no es un problema:
 * 25 campos int16 caben de sobra en una sola notificacion BLE.
 *
 * Payload: 25 x int16 big-endian, orden fijo:
 *   [0-2]   accel_x, accel_y, accel_z   (registros LSM9DS1, raw)
 *   [3-5]   gyro_x,  gyro_y,  gyro_z    (registros LSM9DS1, raw)
 *   [6-8]   mag_x,   mag_y,   mag_z     (registros LSM9DS1, raw)
 *   [9-20]  pressure_raw[0..11]         (cuentas ADC de los 12 FSR)
 *   [21-24] thermistor_raw[0..3]        (cuentas ADC de los 4 NTC)
 *
 * Paquete completo: header 8B (type+version+seq+ts_ms) + payload 50B + CRC 1B
 *                  = 59 BYTES
 * ═══════════════════════════════════════════════════════════════════════════ */

/* ── Tipos de paquete ───────────────────────────────────────────────────── */
#define PKT_TYPE_SENSOR   0x01   /**< Datos de sensores (RAW)          */
#define PKT_TYPE_ACK      0x02   /**< ACK genérico                     */
#define PKT_TYPE_STATUS   0x03   /**< Estado del sistema               */

/* Version del formato del payload de sensores. Distinta version = campos
 * incompatibles; permite detectar un mismatch firmware/app en vez de que
 * los paquetes se descarten en silencio por longitud/CRC. */
#define PKT_PROTO_VERSION 2

#define NUM_PRESSURE_SENSORS   12
#define NUM_THERMISTOR_SENSORS 4
#define PKT_NUM_FIELDS   (9 + NUM_PRESSURE_SENSORS + NUM_THERMISTOR_SENSORS) /* 25 */

/* ── Tamaños de paquete ─────────────────────────────────────────────────── */
#define PKT_HEADER_BYTES  8       /* type(1) + version(1) + seq(2) + ts_ms(4) */
#define PKT_PAYLOAD_BYTES (PKT_NUM_FIELDS * 2)  /* 50 bytes, 25 x int16 */
#define PKT_CRC_BYTES     1
#define PKT_SENSOR_SIZE   (PKT_HEADER_BYTES + PKT_PAYLOAD_BYTES + PKT_CRC_BYTES)  /* 59 */
#define PKT_ACK_SIZE      4       /* type(1) + ack_type(1) + status(1) + crc(1) */

/* ── Estructura de datos de sensores (RAW) ─────────────────────────────── */
typedef struct {
    int16_t accel_x, accel_y, accel_z;                       /* registros LSM9DS1 */
    int16_t gyro_x,  gyro_y,  gyro_z;                         /* registros LSM9DS1 */
    int16_t mag_x,   mag_y,   mag_z;                          /* registros LSM9DS1 */
    int16_t pressure_raw[NUM_PRESSURE_SENSORS];               /* cuentas ADC FSR   */
    int16_t thermistor_raw[NUM_THERMISTOR_SENSORS];           /* cuentas ADC NTC   */
} sensor_data_t;

/* ── API pública ────────────────────────────────────────────────────────── */
void    packet_builder_init(void);

/**
 * @brief Empaqueta sensor_data_t en formato RAW (int16 de ancho fijo).
 * @param data    Datos de sensores (valores RAW, sin convertir).
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
