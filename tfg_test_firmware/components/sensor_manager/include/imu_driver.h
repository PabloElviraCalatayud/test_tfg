#pragma once

#include "driver/i2c_master.h"
#include "esp_err.h"

typedef struct {
  float ax;
  float ay;
  float az;
  float gx;
  float gy;
  float gz;
  float mx;
  float my;
  float mz;
} imu_data_t;

esp_err_t imu_driver_init(i2c_master_bus_handle_t bus);
esp_err_t imu_driver_read(imu_data_t *data);