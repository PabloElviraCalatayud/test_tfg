#include "packet_builder.h"
#include <string.h>
#include "esp_timer.h"
#include "esp_log.h"

static const char *TAG = "PKT_BUILDER";
static uint16_t   s_seq = 0;

/* ───────────────────────────────────────────────────────────────────────────
 * BIT-PACKING CORE
 * ─────────────────────────────────────────────────────────────────────────── */
static void bitpack_write(uint8_t *buf, uint32_t *bit_pos,
                          uint32_t value, uint8_t bits)
{
  for (int i = bits - 1; i >= 0; i--) {
    uint32_t byte_idx = *bit_pos / 8;
    uint8_t  bit_idx  = 7u - (uint8_t)(*bit_pos % 8);

    if (value & (1u << i)) {
      buf[byte_idx] |=  (uint8_t)(1u << bit_idx);
    } else {
      buf[byte_idx] &= ~(uint8_t)(1u << bit_idx);
    }

    (*bit_pos)++;
  }
}

/* ── CRC-8 (polinomio 0x07, init 0xFF) ──────────────────────────────────── */
uint8_t packet_crc8(const uint8_t *data, size_t len)
{
  uint8_t crc = 0xFF;

  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];

    for (int j = 0; j < 8; j++) {
      if (crc & 0x80) {
        crc = (uint8_t)((crc << 1) ^ 0x07);
      } else {
        crc <<= 1;
      }
    }
  }

  return crc;
}

/* ── Init ────────────────────────────────────────────────────────────────── */
void packet_builder_init(void)
{
  s_seq = 0;
  ESP_LOGI(TAG, "Initialized. Packet size: %d bytes", PKT_SENSOR_SIZE);
}

/* ── Sensor packet ───────────────────────────────────────────────────────── */
bool packet_build_sensor(const sensor_data_t *d, uint8_t *buf, size_t *out_len)
{
  if (!d || !buf || !out_len) {
    return false;
  }

  memset(buf, 0, PKT_SENSOR_SIZE);

  uint32_t ts_ms = (uint32_t)(esp_timer_get_time() / 1000ULL);

  /* ── Header ─────────────────────────────────────────────────────────── */
  buf[0] = PKT_TYPE_SENSOR;
  buf[1] = (uint8_t)(s_seq >> 8);
  buf[2] = (uint8_t)(s_seq & 0xFF);
  buf[3] = (uint8_t)(ts_ms >> 24);
  buf[4] = (uint8_t)(ts_ms >> 16);
  buf[5] = (uint8_t)(ts_ms >>  8);
  buf[6] = (uint8_t)(ts_ms      );
  s_seq++;

  /* ── Payload ────────────────────────────────────────────────────────── */
  uint8_t  *payload = &buf[PKT_HEADER_BYTES];
  uint32_t  bit_pos = 0;

  #define PACK_ACCEL(v) bitpack_write(payload, &bit_pos, \
    (uint32_t)((int32_t)((v) * ACCEL_SCALE) + ACCEL_OFFSET), ACCEL_BITS)

  PACK_ACCEL(d->accel_x);
  PACK_ACCEL(d->accel_y);
  PACK_ACCEL(d->accel_z);

  #define PACK_GYRO(v) bitpack_write(payload, &bit_pos, \
    (uint32_t)((int32_t)((v) * GYRO_SCALE) + GYRO_OFFSET), GYRO_BITS)

  PACK_GYRO(d->gyro_x);
  PACK_GYRO(d->gyro_y);
  PACK_GYRO(d->gyro_z);

  #define PACK_MAG(v) bitpack_write(payload, &bit_pos, \
    (uint32_t)((int32_t)((v) * MAG_SCALE) + MAG_OFFSET), MAG_BITS)

  PACK_MAG(d->mag_x);
  PACK_MAG(d->mag_y);
  PACK_MAG(d->mag_z);

  for (int i = 0; i < NUM_PRESSURE_SENSORS; i++) {
    uint32_t p = (d->pressure[i] > PRESSURE_MAX) ? PRESSURE_MAX : d->pressure[i];
    bitpack_write(payload, &bit_pos, p, PRESSURE_BITS);
  }

  for (int i = 0; i < NUM_THERMISTOR_SENSORS; i++) {
    uint32_t t = (uint32_t)(d->temperature[i] * THERMISTOR_SCALE);
    if (t > 1000) {
      t = 1000;
    }
    bitpack_write(payload, &bit_pos, t, THERMISTOR_BITS);
  }

  buf[PKT_HEADER_BYTES + PKT_PAYLOAD_BYTES] =
      packet_crc8(buf, PKT_HEADER_BYTES + PKT_PAYLOAD_BYTES);

  *out_len = PKT_SENSOR_SIZE;
  return true;
}

/* ── ACK packet ─────────────────────────────────────────────────────────── */
bool packet_build_ack(uint8_t ack_type, uint8_t status,
                      uint8_t *buf, size_t *out_len)
{
  if (!buf || !out_len) {
    return false;
  }

  buf[0] = PKT_TYPE_ACK;
  buf[1] = ack_type;
  buf[2] = status;
  buf[3] = packet_crc8(buf, 3);

  *out_len = PKT_ACK_SIZE;
  return true;
}
