#include "imu_driver.h"

#include <math.h>

#include "esp_check.h"
#include "esp_log.h"

#define I2C_FREQ_HZ       400000

#define LSM9DS1_AG_ADDR   0x6B
#define LSM9DS1_MAG_ADDR  0x1E

#define WHO_AM_I          0x0F

#define CTRL_REG1_G       0x10
#define CTRL_REG6_XL      0x20

#define CTRL_REG1_M       0x20
#define CTRL_REG2_M       0x21
#define CTRL_REG3_M       0x22

#define OUT_X_L_G         0x18
#define OUT_X_L_XL        0x28
#define OUT_X_L_M         0x28

static const char *TAG = "IMU_DRIVER";

static i2c_master_dev_handle_t ag_dev;
static i2c_master_dev_handle_t mag_dev;

static esp_err_t write_reg(
  i2c_master_dev_handle_t dev,
  uint8_t reg,
  uint8_t value
) {
  uint8_t data[2] = {
    reg,
    value
  };

  return i2c_master_transmit(
    dev,
    data,
    sizeof(data),
    -1
  );
}

static esp_err_t read_reg(
  i2c_master_dev_handle_t dev,
  uint8_t reg,
  uint8_t *data,
  size_t len
) {
  reg |= 0x80;

  return i2c_master_transmit_receive(
    dev,
    &reg,
    1,
    data,
    len,
    -1
  );
}

static int16_t make_int16(
  uint8_t lsb,
  uint8_t msb
) {
  return (int16_t)((msb << 8) | lsb);
}

esp_err_t imu_driver_init(
  i2c_master_bus_handle_t bus
) {
  i2c_device_config_t dev_cfg = {
    .dev_addr_length = I2C_ADDR_BIT_LEN_7,
    .scl_speed_hz = I2C_FREQ_HZ
  };

  dev_cfg.device_address = LSM9DS1_AG_ADDR;

  ESP_RETURN_ON_ERROR(
    i2c_master_bus_add_device(
      bus,
      &dev_cfg,
      &ag_dev
    ),
    TAG,
    "AG add failed"
  );

  dev_cfg.device_address = LSM9DS1_MAG_ADDR;

  ESP_RETURN_ON_ERROR(
    i2c_master_bus_add_device(
      bus,
      &dev_cfg,
      &mag_dev
    ),
    TAG,
    "MAG add failed"
  );

  uint8_t who = 0;

  ESP_RETURN_ON_ERROR(
    read_reg(
      ag_dev,
      WHO_AM_I,
      &who,
      1
    ),
    TAG,
    "WHO_AM_I failed"
  );

  ESP_LOGI(TAG, "AG WHO_AM_I = 0x%02X", who);

  /*
    Gyroscope:
    119 Hz
    ±245 dps
  */
  ESP_RETURN_ON_ERROR(
    write_reg(
      ag_dev,
      CTRL_REG1_G,
      0x60
    ),
    TAG,
    "gyro cfg failed"
  );

  /*
    Accelerometer:
    119 Hz
    ±2g
  */
  ESP_RETURN_ON_ERROR(
    write_reg(
      ag_dev,
      CTRL_REG6_XL,
      0x60
    ),
    TAG,
    "accel cfg failed"
  );

  /*
    Magnetometer
  */
  ESP_RETURN_ON_ERROR(
    write_reg(
      mag_dev,
      CTRL_REG1_M,
      0x70
    ),
    TAG,
    "mag cfg1 failed"
  );

  ESP_RETURN_ON_ERROR(
    write_reg(
      mag_dev,
      CTRL_REG2_M,
      0x00
    ),
    TAG,
    "mag cfg2 failed"
  );

  ESP_RETURN_ON_ERROR(
    write_reg(
      mag_dev,
      CTRL_REG3_M,
      0x00
    ),
    TAG,
    "mag cfg3 failed"
  );

  return ESP_OK;
}

esp_err_t imu_driver_read(
  imu_data_t *data
) {
  uint8_t gyro_raw[6];
  uint8_t accel_raw[6];
  uint8_t mag_raw[6];

  ESP_RETURN_ON_ERROR(
    read_reg(
      ag_dev,
      OUT_X_L_G,
      gyro_raw,
      6
    ),
    TAG,
    "gyro read failed"
  );

  ESP_RETURN_ON_ERROR(
    read_reg(
      ag_dev,
      OUT_X_L_XL,
      accel_raw,
      6
    ),
    TAG,
    "accel read failed"
  );

  ESP_RETURN_ON_ERROR(
    read_reg(
      mag_dev,
      OUT_X_L_M,
      mag_raw,
      6
    ),
    TAG,
    "mag read failed"
  );

  int16_t gx_raw = make_int16(gyro_raw[0], gyro_raw[1]);
  int16_t gy_raw = make_int16(gyro_raw[2], gyro_raw[3]);
  int16_t gz_raw = make_int16(gyro_raw[4], gyro_raw[5]);

  int16_t ax_raw = make_int16(accel_raw[0], accel_raw[1]);
  int16_t ay_raw = make_int16(accel_raw[2], accel_raw[3]);
  int16_t az_raw = make_int16(accel_raw[4], accel_raw[5]);

  int16_t mx_raw = make_int16(mag_raw[0], mag_raw[1]);
  int16_t my_raw = make_int16(mag_raw[2], mag_raw[3]);
  int16_t mz_raw = make_int16(mag_raw[4], mag_raw[5]);

  data->gx = gx_raw * 0.00875f;
  data->gy = gy_raw * 0.00875f;
  data->gz = gz_raw * 0.00875f;

  data->ax = ax_raw * 0.000061f;
  data->ay = ay_raw * 0.000061f;
  data->az = az_raw * 0.000061f;

  data->mx = mx_raw * 0.00014f;
  data->my = my_raw * 0.00014f;
  data->mz = mz_raw * 0.00014f;

  return ESP_OK;
}
