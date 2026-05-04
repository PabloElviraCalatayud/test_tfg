#pragma once
#include <stdint.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

#define LSM9DS1_AG_ADDR  0x6B
#define LSM9DS1_MAG_ADDR 0x1E

#define LSM9DS1_WHO_AM_I_AG_VAL  0x68
#define LSM9DS1_WHO_AM_I_M_VAL   0x3D

#define LSM9DS1_ACCEL_SENS 0.000732f
#define LSM9DS1_GYRO_SENS  0.070f
#define LSM9DS1_MAG_SENS   0.000292f

typedef struct {
  i2c_master_bus_handle_t bus;
  uint32_t scl_hz;
} lsm9ds1_config_t;

typedef struct {
  float ax, ay, az;
  float gx, gy, gz;
  float mx, my, mz;
} lsm9ds1_data_t;

esp_err_t lsm9ds1_init(const lsm9ds1_config_t *cfg);
esp_err_t lsm9ds1_read(lsm9ds1_data_t *out);
void lsm9ds1_deinit(void);
