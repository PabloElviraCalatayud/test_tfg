#pragma once

#include <stdbool.h>

typedef struct {
  float ax, ay, az;
  float gx, gy, gz;
  float mx, my, mz;
} imu_frame_t;

void sensor_manager_init(void);

void sensor_manager_start(void);
void sensor_manager_stop(void);

bool sensor_manager_get_frame(imu_frame_t *out_frame);