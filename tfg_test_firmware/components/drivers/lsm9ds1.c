#include "lsm9ds1.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define REG_WHO_AM_I_AG 0x0F
#define REG_CTRL_REG1_G 0x10
#define REG_CTRL_REG4   0x1E
#define REG_CTRL_REG5_XL 0x1F
#define REG_CTRL_REG6_XL 0x20
#define REG_CTRL_REG8   0x22
#define REG_OUT_X_L_G   0x18
#define REG_OUT_X_L_XL  0x28

#define REG_WHO_AM_I_M 0x0F
#define REG_CTRL_REG1_M 0x20
#define REG_CTRL_REG2_M 0x21
#define REG_CTRL_REG3_M 0x22
#define REG_CTRL_REG4_M 0x23
#define REG_OUT_X_L_M   0x28

static i2c_master_dev_handle_t s_ag_dev  = NULL;
static i2c_master_dev_handle_t s_mag_dev = NULL;

static esp_err_t reg_write(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t val)
{
  uint8_t buf[2] = { reg, val };
  return i2c_master_transmit(dev, buf, 2, pdMS_TO_TICKS(10));
}

static esp_err_t reg_read(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t *data, size_t len)
{
  return i2c_master_transmit_receive(dev, &reg, 1, data, len, pdMS_TO_TICKS(10));
}

esp_err_t lsm9ds1_init(const lsm9ds1_config_t *cfg)
{
  if (!cfg || !cfg->bus) return ESP_ERR_INVALID_ARG;
  if (s_ag_dev || s_mag_dev) return ESP_ERR_INVALID_STATE;

  i2c_device_config_t ag_cfg = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .device_address = LSM9DS1_AG_ADDR,
    .scl_speed_hz = cfg->scl_hz ? cfg->scl_hz : 400000,
  };

  if (i2c_master_bus_add_device(cfg->bus, &ag_cfg, &s_ag_dev) != ESP_OK) return ESP_FAIL;

  i2c_device_config_t mag_cfg = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .device_address = LSM9DS1_MAG_ADDR,
    .scl_speed_hz = cfg->scl_hz ? cfg->scl_hz : 400000,
  };

  if (i2c_master_bus_add_device(cfg->bus, &mag_cfg, &s_mag_dev) != ESP_OK) {
    i2c_master_bus_rm_device(s_ag_dev);
    s_ag_dev = NULL;
    return ESP_FAIL;
  }

  uint8_t who;

  if (reg_read(s_ag_dev, REG_WHO_AM_I_AG, &who, 1) != ESP_OK || who != LSM9DS1_WHO_AM_I_AG_VAL) return ESP_FAIL;
  if (reg_read(s_mag_dev, REG_WHO_AM_I_M, &who, 1) != ESP_OK || who != LSM9DS1_WHO_AM_I_M_VAL) return ESP_FAIL;

  reg_write(s_ag_dev, REG_CTRL_REG1_G, 0x9C);
  reg_write(s_ag_dev, REG_CTRL_REG4, 0x38);
  reg_write(s_ag_dev, REG_CTRL_REG5_XL, 0x38);
  reg_write(s_ag_dev, REG_CTRL_REG6_XL, 0xA8);
  reg_write(s_ag_dev, REG_CTRL_REG8, 0x44);

  reg_write(s_mag_dev, REG_CTRL_REG1_M, 0x5C);
  reg_write(s_mag_dev, REG_CTRL_REG2_M, 0x60);
  reg_write(s_mag_dev, REG_CTRL_REG3_M, 0x00);
  reg_write(s_mag_dev, REG_CTRL_REG4_M, 0x0C);

  return ESP_OK;
}

esp_err_t lsm9ds1_read(lsm9ds1_data_t *out)
{
  if (!out || !s_ag_dev || !s_mag_dev) return ESP_ERR_INVALID_STATE;

  uint8_t raw[6];

  if (reg_read(s_ag_dev, REG_OUT_X_L_G | 0x80, raw, 6) != ESP_OK) return ESP_FAIL;
  out->gx = (int16_t)((raw[1] << 8) | raw[0]) * LSM9DS1_GYRO_SENS;
  out->gy = (int16_t)((raw[3] << 8) | raw[2]) * LSM9DS1_GYRO_SENS;
  out->gz = (int16_t)((raw[5] << 8) | raw[4]) * LSM9DS1_GYRO_SENS;

  if (reg_read(s_ag_dev, REG_OUT_X_L_XL | 0x80, raw, 6) != ESP_OK) return ESP_FAIL;
  out->ax = (int16_t)((raw[1] << 8) | raw[0]) * LSM9DS1_ACCEL_SENS;
  out->ay = (int16_t)((raw[3] << 8) | raw[2]) * LSM9DS1_ACCEL_SENS;
  out->az = (int16_t)((raw[5] << 8) | raw[4]) * LSM9DS1_ACCEL_SENS;

  if (reg_read(s_mag_dev, REG_OUT_X_L_M | 0x80, raw, 6) != ESP_OK) return ESP_FAIL;
  out->mx = (int16_t)((raw[1] << 8) | raw[0]) * LSM9DS1_MAG_SENS;
  out->my = (int16_t)((raw[3] << 8) | raw[2]) * LSM9DS1_MAG_SENS;
  out->mz = (int16_t)((raw[5] << 8) | raw[4]) * LSM9DS1_MAG_SENS;

  return ESP_OK;
}

void lsm9ds1_deinit(void)
{
  if (s_ag_dev) {
    i2c_master_bus_rm_device(s_ag_dev);
    s_ag_dev = NULL;
  }
  if (s_mag_dev) {
    i2c_master_bus_rm_device(s_mag_dev);
    s_mag_dev = NULL;
  }
}
