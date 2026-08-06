#pragma once

#include <stdbool.h>
#include <stdint.h>

#define SM_NUM_FSR_SENSORS         12  /**< sensores de presión FSR   */
#define SM_NUM_THERMISTOR_SENSORS  4   /**< termistores NTC           */

typedef struct {
  float ax, ay, az;
  float gx, gy, gz;
  float mx, my, mz;

  uint32_t pressure[SM_NUM_FSR_SENSORS];            /**< gramos */
  float    temperature[SM_NUM_THERMISTOR_SENSORS];  /**< °C     */
} sensor_frame_t;

void sensor_manager_init(void);

void sensor_manager_start(void);
void sensor_manager_stop(void);

bool sensor_manager_get_frame(sensor_frame_t *out_frame);
