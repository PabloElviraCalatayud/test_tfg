#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define SM_NUM_FSR_SENSORS         12  /**< sensores de presión FSR   */
#define SM_NUM_THERMISTOR_SENSORS  4   /**< termistores NTC           */

/*
 * Todo RAW: registros del LSM9DS1 y cuentas ADC del ADS1115 sin
 * convertir a unidades fisicas. La conversion (sensibilidad IMU,
 * voltaje->gramos, voltaje->celsius) vive en la app movil -- ver
 * lib/core/utils/sensor_calibration.dart -- para poder recalibrar sin
 * reflashear el firmware.
 */
typedef struct {
  int16_t ax, ay, az;
  int16_t gx, gy, gz;
  int16_t mx, my, mz;

  int16_t pressure_raw[SM_NUM_FSR_SENSORS];
  int16_t thermistor_raw[SM_NUM_THERMISTOR_SENSORS];
} sensor_frame_t;

void sensor_manager_init(void);

void sensor_manager_start(void);
void sensor_manager_stop(void);

bool sensor_manager_get_frame(sensor_frame_t *out_frame);

/**
 * Registra la task que debe despertarse (via xTaskNotifyGive) cada vez
 * que hay una lectura de IMU nueva. Permite que app_task mande paquetes
 * BLE dirigido por eventos (~50Hz, el ritmo real del IMU) en vez de
 * hacer polling a una tasa fija mas alta que la de los datos.
 */
void sensor_manager_set_notify_task(TaskHandle_t task);
