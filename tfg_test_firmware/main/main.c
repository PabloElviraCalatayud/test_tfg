#include <stdlib.h>
#include <stdbool.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_log.h"

#include "system_state.h"
#include "ble_transport.h"
#include "ota_manager.h"
#include "packet_builder.h"

#define USE_REAL_SENSORS 1

#if USE_REAL_SENSORS
  #include "sensor_manager.h"
#else
  #include "ads1115_mock.h"
  #include "lsm9ds1_mock.h"
#endif

static const char *TAG = "MAIN";

#if !USE_REAL_SENSORS
/*
 * Réplica del esquema de 4 ADS1115 (12 canales FSR + 4 canales termistor)
 * usado por sensor_manager, pero con lecturas simuladas para poder probar
 * sin hardware conectado.
 */
#define MOCK_ADS1115_NUM_DEVICES       4
#define MOCK_ADS1115_FSR_DEVICE_COUNT  3
#define MOCK_ADS1115_TEMP_DEVICE_INDEX 3

static const uint8_t MOCK_ADC_I2C_ADDR[MOCK_ADS1115_NUM_DEVICES] = {
  ADS1115_ADDR_GND,
  ADS1115_ADDR_VCC,
  ADS1115_ADDR_SDA,
  ADS1115_ADDR_SCL,
};

static ads1115_handle_t s_mock_adc[MOCK_ADS1115_NUM_DEVICES];

static void mock_read_adc(sensor_data_t *data) {
  ads1115_result_t res;
  int fsr_idx = 0;

  for (int dev = 0; dev < MOCK_ADS1115_FSR_DEVICE_COUNT; dev++) {
    ads1115_mock_read_all(s_mock_adc[dev], &res);

    for (int ch = 0; ch < ADS1115_NUM_CHANNELS; ch++) {
      data->pressure[fsr_idx] = (uint32_t)(
        res.voltage[ch] / 3.3f * 10000.0f
      );

      ESP_LOGI(
        TAG,
        "FSR[%2d] addr=0x%02X ch=%d  V=%.3fV  P=%u g",
        fsr_idx, MOCK_ADC_I2C_ADDR[dev], ch,
        res.voltage[ch], (unsigned int)data->pressure[fsr_idx]
      );

      fsr_idx++;
    }
  }

  ads1115_mock_read_all(s_mock_adc[MOCK_ADS1115_TEMP_DEVICE_INDEX], &res);

  for (int ch = 0; ch < NUM_THERMISTOR_SENSORS; ch++) {
    data->temperature[ch] =
      20.0f + (res.voltage[ch] / 3.3f) * 30.0f;

    ESP_LOGI(
      TAG,
      "NTC[%d] addr=0x%02X ch=%d  V=%.3fV  T=%.1f C",
      ch, MOCK_ADC_I2C_ADDR[MOCK_ADS1115_TEMP_DEVICE_INDEX], ch,
      res.voltage[ch], data->temperature[ch]
    );
  }
}
#endif

static void app_task(void *arg) {
  uint8_t pkt_buf[PKT_SENSOR_SIZE];
  size_t pkt_len;

  sensor_data_t data;

#if USE_REAL_SENSORS
  sensor_frame_t frame;
#else
  lsm9ds1_data_t imu;
#endif

  while (1) {

    if (system_state_get() == SYS_STATE_OTA) {

      ESP_LOGI(
        TAG,
        "[app_task] OTA activo -> pausa"
      );

      vTaskDelay(
        pdMS_TO_TICKS(500)
      );

      continue;
    }

#if USE_REAL_SENSORS

    if (!sensor_manager_get_frame(&frame)) {

      vTaskDelay(
        pdMS_TO_TICKS(10)
      );

      continue;
    }

    data.accel_x = frame.ax;
    data.accel_y = frame.ay;
    data.accel_z = frame.az;

    data.gyro_x = frame.gx;
    data.gyro_y = frame.gy;
    data.gyro_z = frame.gz;

    data.mag_x = frame.mx;
    data.mag_y = frame.my;
    data.mag_z = frame.mz;

    for (int i = 0; i < NUM_PRESSURE_SENSORS; i++) {
      data.pressure[i] = frame.pressure[i];
    }

    for (int i = 0; i < NUM_THERMISTOR_SENSORS; i++) {
      data.temperature[i] = frame.temperature[i];
    }

#else

    lsm9ds1_mock_read(&imu);

    data.accel_x = imu.ax;
    data.accel_y = imu.ay;
    data.accel_z = imu.az;

    data.gyro_x = imu.gx;
    data.gyro_y = imu.gy;
    data.gyro_z = imu.gz;

    data.mag_x = imu.mx;
    data.mag_y = imu.my;
    data.mag_z = imu.mz;

    mock_read_adc(&data);

#endif

    /*
     * El detalle de IMU/FSR/NTC ya se ve en la linea consolidada que
     * imprime sensor_manager (2 Hz). Aqui solo dejamos un heartbeat de
     * estado BLE, throttled a ~1 Hz, para no inundar la consola con un
     * log por paquete (este bucle corre a 100 Hz).
     */
    static int pkt_count = 0;

    if (packet_build_sensor(
          &data,
          pkt_buf,
          &pkt_len
        )) {

      das_ble_notify(
        pkt_buf,
        (uint16_t)pkt_len
      );

      pkt_count++;
    }

    if (pkt_count >= 100) {

      ESP_LOGI(
        TAG,
        "BLE %s | %d paquetes/s",
        das_ble_is_connected() ? "OK" : "no conn",
        pkt_count
      );

      pkt_count = 0;
    }

    vTaskDelay(
      pdMS_TO_TICKS(10)
    );
  }
}

void app_main(void) {
  ESP_LOGI(
    TAG,
    "=== ESP32-S3 DAS arrancando ==="
  );

  /*
   * NimBLE imprime una linea por cada "GATT procedure initiated" (osea,
   * por cada notificacion BLE que mandamos). A la tasa de envio actual
   * eso inunda la consola sin aportar nada que no sepamos ya; se deja
   * en WARN para seguir viendo errores reales del stack BLE.
   */
  esp_log_level_set("NimBLE", ESP_LOG_WARN);

  system_state_init();

  if (das_ble_init() != ESP_OK) {

    ESP_LOGE(
      TAG,
      "BLE init failed"
    );

    return;
  }

  if (ota_manager_init() != ESP_OK) {

    ESP_LOGE(
      TAG,
      "OTA init failed"
    );

    return;
  }

  packet_builder_init();

#if USE_REAL_SENSORS

  /*
    Sensor manager:
    - crea I2C
    - inicializa IMU
    - inicializa los 4 ADS1115 (12 canales FSR + 4 canales termistor)
    - crea tasks de adquisición (IMU y ADC) que muestran las lecturas
      por consola
  */
  sensor_manager_init();

#else

  for (int i = 0; i < MOCK_ADS1115_NUM_DEVICES; i++) {
    ads1115_config_t ads_cfg = {
      .bus = NULL,
      .addr = MOCK_ADC_I2C_ADDR[i],
      .fsr = ADS1115_FSR_4096MV,
      .data_rate = ADS1115_DR_128SPS
    };

    ads1115_mock_init(
      &ads_cfg,
      &s_mock_adc[i]
    );
  }

  lsm9ds1_config_t imu_cfg = {
    .bus = NULL,
    .scl_hz = 400000
  };

  lsm9ds1_mock_init(
    &imu_cfg
  );

#endif

  system_state_set(
    SYS_STATE_RUNNING
  );

  xTaskCreate(
    app_task,
    "app_task",
    6144,
    NULL,
    5,
    NULL
  );

  ESP_LOGI(
    TAG,
    "Listo. Conectate a BLE"
  );
}
