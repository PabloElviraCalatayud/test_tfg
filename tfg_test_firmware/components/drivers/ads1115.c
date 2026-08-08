#include "ads1115.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <math.h>
#include <stdlib.h>

static const char *TAG = "ADS1115";

#define ADS1115_REG_CONVERSION  0x00
#define ADS1115_REG_CONFIG      0x01

struct ads1115_dev_s {
  i2c_master_dev_handle_t dev;
  ads1115_fsr_t fsr;
  ads1115_dr_t  dr;
};

static const float FSR_UV_PER_LSB[] = {
  187.5f, 125.0f, 62.5f, 31.25f, 15.625f, 7.8125f,
};

static const uint16_t DR_WAIT_MS[] = {
  130, 70, 35, 20, 10, 5, 3, 2
};

static esp_err_t write_reg16(ads1115_handle_t h, uint8_t reg, uint16_t val)
{
  uint8_t buf[3] = { reg, (uint8_t)(val >> 8), (uint8_t)(val & 0xFF) };
  /* xfer_timeout_ms es en milisegundos directos (no ticks de FreeRTOS);
   * -1 = esperar indefinidamente, igual que el resto de drivers I2C
   * de este proyecto (imu_driver.c) y que el hardware de referencia. */
  return i2c_master_transmit(h->dev, buf, 3, -1);
}

static esp_err_t read_reg16(ads1115_handle_t h, uint8_t reg, uint16_t *out)
{
  uint8_t reg_buf = reg;
  uint8_t raw[2];
  esp_err_t err = i2c_master_transmit_receive(h->dev, &reg_buf, 1, raw, 2, -1);
  if (err == ESP_OK) {
    *out = (uint16_t)((raw[0] << 8) | raw[1]);
  }
  return err;
}

esp_err_t ads1115_init(const ads1115_config_t *cfg, ads1115_handle_t *out_handle)
{
  if (!cfg || !cfg->bus || !out_handle) return ESP_ERR_INVALID_ARG;

  ads1115_handle_t h = calloc(1, sizeof(struct ads1115_dev_s));
  if (!h) return ESP_ERR_NO_MEM;

  h->fsr = cfg->fsr;
  h->dr  = cfg->data_rate;

  i2c_device_config_t dev_cfg = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .device_address  = cfg->addr,
    .scl_speed_hz    = 100000,
  };

  esp_err_t err = i2c_master_bus_add_device(cfg->bus, &dev_cfg, &h->dev);
  if (err != ESP_OK) {
    free(h);
    return err;
  }

  uint16_t cfg_val;
  err = read_reg16(h, ADS1115_REG_CONFIG, &cfg_val);
  if (err != ESP_OK) {
    i2c_master_bus_rm_device(h->dev);
    free(h);
    return err;
  }

  ESP_LOGI(TAG, "ADS1115 iniciado en addr 0x%02X", cfg->addr);

  *out_handle = h;
  return ESP_OK;
}

esp_err_t ads1115_read_channel(ads1115_handle_t h, ads1115_mux_t mux, int16_t *raw_out)
{
  if (!h || !raw_out) return ESP_ERR_INVALID_STATE;

  uint16_t config =
    (1u << 15) |
    ((uint16_t)mux  << 12) |
    ((uint16_t)h->fsr << 9) |
    (1u << 8) |
    ((uint16_t)h->dr << 5) |
    (3u << 0);

  esp_err_t err = write_reg16(h, ADS1115_REG_CONFIG, config);
  if (err != ESP_OK) return err;

  vTaskDelay(pdMS_TO_TICKS(DR_WAIT_MS[h->dr & 0x07]));

  uint16_t status;
  for (int i = 0; i < 10; i++) {
    err = read_reg16(h, ADS1115_REG_CONFIG, &status);
    if (err == ESP_OK && (status & 0x8000)) break;
    vTaskDelay(pdMS_TO_TICKS(2));
  }

  uint16_t raw_u;
  err = read_reg16(h, ADS1115_REG_CONVERSION, &raw_u);
  if (err != ESP_OK) return err;

  *raw_out = (int16_t)raw_u;
  return ESP_OK;
}

esp_err_t ads1115_read_all(ads1115_handle_t h, ads1115_result_t *out)
{
  if (!out) return ESP_ERR_INVALID_ARG;
  if (!h) return ESP_ERR_INVALID_STATE;

  static const ads1115_mux_t channels[ADS1115_NUM_CHANNELS] = {
    ADS1115_MUX_AIN0_GND,
    ADS1115_MUX_AIN1_GND,
    ADS1115_MUX_AIN2_GND,
    ADS1115_MUX_AIN3_GND,
  };

  for (int i = 0; i < ADS1115_NUM_CHANNELS; i++) {
    if (ads1115_read_channel(h, channels[i], &out->raw[i]) != ESP_OK) {
      out->raw[i] = 0;
      out->voltage[i] = 0;
    } else {
      out->voltage[i] = ads1115_raw_to_voltage(out->raw[i], h->fsr);
    }
  }
  return ESP_OK;
}

void ads1115_deinit(ads1115_handle_t h)
{
  if (h) {
    if (h->dev) {
      i2c_master_bus_rm_device(h->dev);
    }
    free(h);
  }
}

float ads1115_ntc_to_celsius(float v_adc, float v_ref, float r_ref_ohm)
{
  if (v_adc <= 0.0f || v_adc >= v_ref) return -273.15f;

  const float B = 3950.0f;
  const float T0 = 298.15f;
  const float R0 = 10000.0f;

  float r_ntc = r_ref_ohm * v_adc / (v_ref - v_adc);
  float temp_k = 1.0f / (1.0f / T0 + (1.0f / B) * logf(r_ntc / R0));
  return temp_k - 273.15f;
}

uint32_t ads1115_voltage_to_grams(float voltage, float v_max, uint32_t pressure_max_g)
{
  if (voltage <= 0.0f) return 0;
  if (voltage >= v_max) return pressure_max_g;
  return (uint32_t)(voltage / v_max * pressure_max_g);
}

float ads1115_raw_to_voltage(int16_t raw, ads1115_fsr_t fsr)
{
  float uv_per_lsb = FSR_UV_PER_LSB[fsr & 0x07];
  return (float)raw * uv_per_lsb / 1e6f;
}
