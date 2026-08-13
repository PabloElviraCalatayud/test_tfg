#pragma once

#include "driver/i2c_master.h"
#include "esp_err.h"

/*
 * Valores RAW directos de los registros del LSM9DS1 (sin convertir a
 * unidades fisicas). La conversion (sensibilidad g/LSB, dps/LSB,
 * gauss/LSB) se hace en la app movil -- ver sensor_calibration.dart.
 */
typedef struct {
  int16_t ax;
  int16_t ay;
  int16_t az;

  int16_t gx;
  int16_t gy;
  int16_t gz;

  int16_t mx;
  int16_t my;
  int16_t mz;
} imu_data_t;

esp_err_t imu_driver_init(i2c_master_bus_handle_t bus);

esp_err_t imu_driver_read(
  imu_data_t *data
);
