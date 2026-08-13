#include "packet_builder.h"
#include <string.h>
#include "esp_timer.h"
#include "esp_log.h"

static const char *TAG = "PKT_BUILDER";
static uint16_t   s_seq = 0;

/* ── Escritura int16 big-endian ─────────────────────────────────────────── */
static void write_i16_be(uint8_t *buf, uint32_t *byte_pos, int16_t v)
{
  buf[*byte_pos]     = (uint8_t)(((uint16_t)v) >> 8);
  buf[*byte_pos + 1] = (uint8_t)(((uint16_t)v) & 0xFF);
  *byte_pos += 2;
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
  ESP_LOGI(TAG, "Initialized. Packet size: %d bytes (proto v%d, RAW)", PKT_SENSOR_SIZE, PKT_PROTO_VERSION);
}

/* ── Sensor packet (RAW, sin convertir) ─────────────────────────────────── */
bool packet_build_sensor(const sensor_data_t *d, uint8_t *buf, size_t *out_len)
{
  if (!d || !buf || !out_len) {
    return false;
  }

  memset(buf, 0, PKT_SENSOR_SIZE);

  uint32_t ts_ms = (uint32_t)(esp_timer_get_time() / 1000ULL);

  /* ── Header ─────────────────────────────────────────────────────────── */
  buf[0] = PKT_TYPE_SENSOR;
  buf[1] = PKT_PROTO_VERSION;
  buf[2] = (uint8_t)(s_seq >> 8);
  buf[3] = (uint8_t)(s_seq & 0xFF);
  buf[4] = (uint8_t)(ts_ms >> 24);
  buf[5] = (uint8_t)(ts_ms >> 16);
  buf[6] = (uint8_t)(ts_ms >>  8);
  buf[7] = (uint8_t)(ts_ms      );
  s_seq++;

  /* ── Payload: 25 x int16 BE, RAW, ancho fijo, sin convertir ───────────── */
  uint32_t pos = PKT_HEADER_BYTES;

  write_i16_be(buf, &pos, d->accel_x);
  write_i16_be(buf, &pos, d->accel_y);
  write_i16_be(buf, &pos, d->accel_z);

  write_i16_be(buf, &pos, d->gyro_x);
  write_i16_be(buf, &pos, d->gyro_y);
  write_i16_be(buf, &pos, d->gyro_z);

  write_i16_be(buf, &pos, d->mag_x);
  write_i16_be(buf, &pos, d->mag_y);
  write_i16_be(buf, &pos, d->mag_z);

  for (int i = 0; i < NUM_PRESSURE_SENSORS; i++) {
    write_i16_be(buf, &pos, d->pressure_raw[i]);
  }

  for (int i = 0; i < NUM_THERMISTOR_SENSORS; i++) {
    write_i16_be(buf, &pos, d->thermistor_raw[i]);
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
