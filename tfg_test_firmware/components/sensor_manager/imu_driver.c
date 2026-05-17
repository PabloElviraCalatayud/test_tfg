#include "imu_driver.h"
#include "esp_log.h"
#include "esp_check.h"

#define LSM9DS1_AG_ADDR   0x6B
#define LSM9DS1_MAG_ADDR  0x1E

#define WHO_AM_I_AG       0x0F
#define WHO_AM_I_MAG      0x0F

#define WHO_AM_I_AG_VAL   0x68
#define WHO_AM_I_MAG_VAL  0x3D

#define CTRL_REG1_G       0x10
#define CTRL_REG4         0x1E
#define CTRL_REG6_XL      0x20

#define CTRL_REG1_M       0x20
#define CTRL_REG2_M       0x21
#define CTRL_REG3_M       0x22

#define OUT_X_L_G         0x18
#define OUT_X_L_XL        0x28
#define OUT_X_L_M         0x28

#define AUTO_INC          0x80

static const char *TAG = "IMU_DRV";

static i2c_master_dev_handle_t ag_handle = NULL;
static i2c_master_dev_handle_t mag_handle = NULL;

static esp_err_t write_reg(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t value) {
  uint8_t data[2] = {reg, value};
  return i2c_master_transmit(dev, data, sizeof(data), -1);
}

static esp_err_t read_regs(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t *data, size_t len) {
  return i2c_master_transmit_receive(dev, &reg, 1, data, len, -1);
}

esp_err_t imu_driver_init(i2c_master_bus_handle_t bus) {
  if (!bus) {
    return ESP_ERR_INVALID_ARG;
  }

  i2c_device_config_t dev_config = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .scl_speed_hz = 400000,
  };

  dev_config.device_address = LSM9DS1_AG_ADDR;
  ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(bus, &dev_config, &ag_handle), TAG, "AG add fail");

  dev_config.device_address = LSM9DS1_MAG_ADDR;
  ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(bus, &dev_config, &mag_handle), TAG, "MAG add fail");

  uint8_t who;

  ESP_RETURN_ON_ERROR(read_regs(ag_handle, WHO_AM_I_AG, &who, 1), TAG, "AG WHO_AM_I fail");
  if (who != WHO_AM_I_AG_VAL) {
    return ESP_FAIL;
  }

  ESP_RETURN_ON_ERROR(read_regs(mag_handle, WHO_AM_I_MAG, &who, 1), TAG, "MAG WHO_AM_I fail");
  if (who != WHO_AM_I_MAG_VAL) {
    return ESP_FAIL;
  }

  ESP_RETURN_ON_ERROR(write_reg(ag_handle, CTRL_REG1_G,  0b11000000), TAG, "gyro fail");
  ESP_RETURN_ON_ERROR(write_reg(ag_handle, CTRL_REG4,    0b00111000), TAG, "gyro axis fail");
  ESP_RETURN_ON_ERROR(write_reg(ag_handle, CTRL_REG6_XL, 0b11000000), TAG, "acc fail");

  ESP_RETURN_ON_ERROR(write_reg(mag_handle, CTRL_REG1_M, 0b11110000), TAG, "mag1 fail");
  ESP_RETURN_ON_ERROR(write_reg(mag_handle, CTRL_REG2_M, 0b00000000), TAG, "mag2 fail");
  ESP_RETURN_ON_ERROR(write_reg(mag_handle, CTRL_REG3_M, 0b00000000), TAG, "mag3 fail");

  return ESP_OK;
}

esp_err_t imu_driver_read(imu_data_t *data) {
  if (!data) {
    return ESP_ERR_INVALID_ARG;
  }

  if (!ag_handle || !mag_handle) {
    return ESP_ERR_INVALID_STATE;
  }

  uint8_t raw[6];

  ESP_RETURN_ON_ERROR(read_regs(ag_handle, OUT_X_L_XL | AUTO_INC, raw, 6), TAG, "acc read fail");

  int16_t ax = (int16_t)((raw[1] << 8) | raw[0]);
  int16_t ay = (int16_t)((raw[3] << 8) | raw[2]);
  int16_t az = (int16_t)((raw[5] << 8) | raw[4]);

  ESP_RETURN_ON_ERROR(read_regs(ag_handle, OUT_X_L_G | AUTO_INC, raw, 6), TAG, "gyro read fail");

  int16_t gx = (int16_t)((raw[1] << 8) | raw[0]);
  int16_t gy = (int16_t)((raw[3] << 8) | raw[2]);
  int16_t gz = (int16_t)((raw[5] << 8) | raw[4]);

  ESP_RETURN_ON_ERROR(read_regs(mag_handle, OUT_X_L_M | AUTO_INC, raw, 6), TAG, "mag read fail");

  int16_t mx = (int16_t)((raw[1] << 8) | raw[0]);
  int16_t my = (int16_t)((raw[3] << 8) | raw[2]);
  int16_t mz = (int16_t)((raw[5] << 8) | raw[4]);

  data->ax = ax * 0.000061f;
  data->ay = ay * 0.000061f;
  data->az = az * 0.000061f;

  data->gx = gx * 0.00875f;
  data->gy = gy * 0.00875f;
  data->gz = gz * 0.00875f;

  data->mx = mx * 0.00014f;
  data->my = my * 0.00014f;
  data->mz = mz * 0.00014f;

  return ESP_OK;
}