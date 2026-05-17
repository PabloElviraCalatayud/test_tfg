#include "sensor_manager.h"
#include "imu_driver.h"
#include "system_state.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "driver/i2c_master.h"

#define I2C_PORT 0
#define I2C_SDA GPIO_NUM_14
#define I2C_SCL GPIO_NUM_13

static TaskHandle_t sensor_task = NULL;
static SemaphoreHandle_t data_mutex;
static imu_frame_t current_frame;

static i2c_master_bus_handle_t bus_handle;

static volatile bool task_running = false;

static void sensor_task_fn(void *arg) {
  imu_data_t data;
  TickType_t last = xTaskGetTickCount();

  task_running = true;

  while (1) {

    if (system_state_get() == SYS_STATE_OTA) {
      vTaskDelay(pdMS_TO_TICKS(200));
      continue;
    }

    if (imu_driver_read(&data) == ESP_OK) {

      xSemaphoreTake(data_mutex, portMAX_DELAY);

      current_frame.ax = data.ax;
      current_frame.ay = data.ay;
      current_frame.az = data.az;

      current_frame.gx = data.gx;
      current_frame.gy = data.gy;
      current_frame.gz = data.gz;

      current_frame.mx = data.mx;
      current_frame.my = data.my;
      current_frame.mz = data.mz;

      xSemaphoreGive(data_mutex);
    }

    vTaskDelayUntil(&last, pdMS_TO_TICKS(10));
  }
}

void sensor_manager_start(void) {
  if (sensor_task != NULL) {
    return;
  }

  xTaskCreate(sensor_task_fn, "sensor_task", 4096, NULL, 5, &sensor_task);
}

void sensor_manager_stop(void) {
  if (sensor_task == NULL) {
    return;
  }

  vTaskDelete(sensor_task);
  sensor_task = NULL;
  task_running = false;
}

void sensor_manager_init(void) {
  i2c_master_bus_config_t bus_config = {
    .i2c_port = I2C_PORT,
    .sda_io_num = I2C_SDA,
    .scl_io_num = I2C_SCL,
    .clk_source = I2C_CLK_SRC_DEFAULT,
    .glitch_ignore_cnt = 7,
    .intr_priority = 0,
    .trans_queue_depth = 4,
  };

  i2c_new_master_bus(&bus_config, &bus_handle);
  imu_driver_init(bus_handle);

  data_mutex = xSemaphoreCreateMutex();
}

bool sensor_manager_get_frame(imu_frame_t *out_frame) {
  if (!out_frame || !task_running) {
    return false;
  }

  xSemaphoreTake(data_mutex, portMAX_DELAY);
  *out_frame = current_frame;
  xSemaphoreGive(data_mutex);

  return true;
}