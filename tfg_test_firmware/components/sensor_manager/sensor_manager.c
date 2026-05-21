#include "sensor_manager.h"
#include "imu_driver.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "driver/i2c_master.h"

#define I2C_PORT 0
#define I2C_SDA  GPIO_NUM_8
#define I2C_SCL  GPIO_NUM_9

static imu_frame_t frame;

static SemaphoreHandle_t mutex;

static TaskHandle_t task_handle;

static void sensor_task(void *arg) {
  imu_data_t data;

  while (1) {

    if (imu_driver_read(&data) == ESP_OK) {

      xSemaphoreTake(mutex, portMAX_DELAY);

      frame.ax = data.ax;
      frame.ay = data.ay;
      frame.az = data.az;

      frame.gx = data.gx;
      frame.gy = data.gy;
      frame.gz = data.gz;

      frame.mx = data.mx;
      frame.my = data.my;
      frame.mz = data.mz;

      xSemaphoreGive(mutex);
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

void sensor_manager_init(void) {
  i2c_master_bus_handle_t bus;

  i2c_master_bus_config_t cfg = {
    .i2c_port = I2C_PORT,
    .sda_io_num = I2C_SDA,
    .scl_io_num = I2C_SCL,
    .clk_source = I2C_CLK_SRC_DEFAULT,
    .glitch_ignore_cnt = 7,
    .flags.enable_internal_pullup = false
  };

  ESP_ERROR_CHECK(
    i2c_new_master_bus(
      &cfg,
      &bus
    )
  );

  ESP_ERROR_CHECK(
    imu_driver_init(bus)
  );

  mutex = xSemaphoreCreateMutex();

  xTaskCreate(
    sensor_task,
    "imu_task",
    4096,
    NULL,
    5,
    &task_handle
  );
}

bool sensor_manager_get_frame(
  imu_frame_t *out
) {
  if (!out) {
    return false;
  }

  xSemaphoreTake(mutex, portMAX_DELAY);

  *out = frame;

  xSemaphoreGive(mutex);

  return true;
}
