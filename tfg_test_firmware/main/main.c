#include <stdlib.h>
#include <stdbool.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

#include "system_state.h"
#include "ble_transport.h"
#include "ota_manager.h"
#include "packet_builder.h"

#define USE_REAL_SENSORS 0

#if USE_REAL_SENSORS
  #include "sensor_manager.h"
#else
  #include "ads1115_mock.h"
  #include "lsm9ds1_mock.h"
#endif

static const char *TAG = "MAIN";

static void sensor_task(void *arg)
{
  uint8_t pkt_buf[PKT_SENSOR_SIZE];
  size_t pkt_len;
  sensor_data_t data;

#if USE_REAL_SENSORS
  imu_frame_t imu;
#else
  ads1115_result_t adc;
  lsm9ds1_data_t imu;
#endif

  while (1) {

    if (system_state_get() == SYS_STATE_OTA) {
      ESP_LOGI(TAG, "[sensor_task] OTA activo → pausa");
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }

#if USE_REAL_SENSORS

    if (!sensor_manager_get_frame(&imu)) {
      vTaskDelay(pdMS_TO_TICKS(10));
      continue;
    }

    data.accel_x = imu.ax;
    data.accel_y = imu.ay;
    data.accel_z = imu.az;

    data.gyro_x  = imu.gx;
    data.gyro_y  = imu.gy;
    data.gyro_z  = imu.gz;

    data.mag_x   = imu.mx;
    data.mag_y   = imu.my;
    data.mag_z   = imu.mz;

#else

    ads1115_mock_read_all(&adc);
    lsm9ds1_mock_read(&imu);

    data.accel_x = imu.ax;
    data.accel_y = imu.ay;
    data.accel_z = imu.az;

    data.gyro_x  = imu.gx;
    data.gyro_y  = imu.gy;
    data.gyro_z  = imu.gz;

    data.mag_x   = imu.mx;
    data.mag_y   = imu.my;
    data.mag_z   = imu.mz;

    for (int i = 0; i < NUM_PRESSURE_SENSORS; i++) {
      data.pressure[i] = (uint32_t)(adc.voltage[i] / 3.3f * 100000.0f);
    }

#endif

    data.temperature[0] = 20.0f + ((float)(rand() % 100)) / 10.0f;
    data.temperature[1] = 20.0f + ((float)(rand() % 100)) / 10.0f;

    ESP_LOGI(TAG, "IMU A[%.2f %.2f %.2f] G[%.1f %.1f %.1f]",
             data.accel_x, data.accel_y, data.accel_z,
             data.gyro_x, data.gyro_y, data.gyro_z);

    if (packet_build_sensor(&data, pkt_buf, &pkt_len)) {

      das_ble_notify(pkt_buf, (uint16_t)pkt_len);

      ESP_LOGI(TAG, "PKT %d bytes → BLE %s",
               (int)pkt_len,
               das_ble_is_connected() ? "OK" : "no conn");
    }

    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

void app_main(void)
{
  ESP_LOGI(TAG, "=== ESP32-S3 DAS arrancando ===");

  system_state_init();

  if (das_ble_init() != ESP_OK) {
    ESP_LOGE(TAG, "BLE init failed");
    return;
  }

  if (ota_manager_init() != ESP_OK) {
    ESP_LOGE(TAG, "OTA init failed");
    return;
  }

  packet_builder_init();

#if USE_REAL_SENSORS

  sensor_manager_init();

#else

  ads1115_config_t ads_cfg = {
    .bus = NULL,
    .addr = 0x48,
    .fsr = ADS1115_FSR_4096MV,
    .data_rate = ADS1115_DR_128SPS
  };
  ads1115_mock_init(&ads_cfg);

  lsm9ds1_config_t imu_cfg = {
    .bus = NULL,
    .scl_hz = 400000
  };
  lsm9ds1_mock_init(&imu_cfg);

#endif

  system_state_set(SYS_STATE_RUNNING);

#if USE_REAL_SENSORS
  sensor_manager_start();
#endif

  xTaskCreate(sensor_task, "sensor_task", 4096, NULL, 5, NULL);

  ESP_LOGI(TAG, "Listo. Conéctate a BLE");
}