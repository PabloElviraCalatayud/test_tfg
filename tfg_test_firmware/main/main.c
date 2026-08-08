#include <stdlib.h>
#include <stdbool.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_log.h"
#include "esp_pm.h"

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
      data->pressure_raw[fsr_idx] = res.raw[ch];

      ESP_LOGI(
        TAG,
        "FSR[%2d] addr=0x%02X ch=%d  raw=%d",
        fsr_idx, MOCK_ADC_I2C_ADDR[dev], ch, res.raw[ch]
      );

      fsr_idx++;
    }
  }

  ads1115_mock_read_all(s_mock_adc[MOCK_ADS1115_TEMP_DEVICE_INDEX], &res);

  for (int ch = 0; ch < NUM_THERMISTOR_SENSORS; ch++) {
    data->thermistor_raw[ch] = res.raw[ch];

    ESP_LOGI(
      TAG,
      "NTC[%d] addr=0x%02X ch=%d  raw=%d",
      ch, MOCK_ADC_I2C_ADDR[MOCK_ADS1115_TEMP_DEVICE_INDEX], ch, res.raw[ch]
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

#if USE_REAL_SENSORS
    /*
     * Dirigido por eventos: espera a que sensor_manager avise de que hay
     * una lectura de IMU nueva (~50Hz, el ritmo real del sensor) en vez
     * de hacer polling a una tasa fija mas alta que la de los datos --
     * la mayoria de esos ciclos extra solo reenviaban el mismo paquete.
     */
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
#endif

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
      data.pressure_raw[i] = frame.pressure_raw[i];
    }

    for (int i = 0; i < NUM_THERMISTOR_SENSORS; i++) {
      data.thermistor_raw[i] = frame.thermistor_raw[i];
    }

#else

    lsm9ds1_mock_read(&imu);

    /* lsm9ds1_mock sigue devolviendo unidades fisicas (driver legacy,
     * no forma parte del path real); se castea a int16 solo para que
     * esta rama de mock compile con el formato RAW del paquete. */
    data.accel_x = (int16_t)imu.ax;
    data.accel_y = (int16_t)imu.ay;
    data.accel_z = (int16_t)imu.az;

    data.gyro_x = (int16_t)imu.gx;
    data.gyro_y = (int16_t)imu.gy;
    data.gyro_z = (int16_t)imu.gz;

    data.mag_x = (int16_t)imu.mx;
    data.mag_y = (int16_t)imu.my;
    data.mag_z = (int16_t)imu.mz;

    mock_read_adc(&data);

#endif

    /*
     * El detalle de IMU/FSR/NTC ya se ve en la linea consolidada que
     * imprime sensor_manager (2 Hz). Aqui solo dejamos un heartbeat de
     * estado BLE, throttled a ~1 Hz, para no inundar la consola con un
     * log por paquete (el bucle corre a ~50 Hz, dirigido por eventos).
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

    if (pkt_count >= 50) {

      ESP_LOGI(
        TAG,
        "BLE %s | %d paquetes/s",
        das_ble_is_connected() ? "OK" : "no conn",
        pkt_count
      );

      pkt_count = 0;
    }

#if !USE_REAL_SENSORS
    /* Rama mock: no hay sensor_manager que avise por notificacion, asi
     * que se mantiene el ritmo por polling. */
    vTaskDelay(
      pdMS_TO_TICKS(10)
    );
#endif
  }
}

void app_main(void) {
  ESP_LOGI(
    TAG,
    "=== ESP32-S3 DAS arrancando ==="
  );

  /*
   * DFS + light-sleep automatico: baja la frecuencia de CPU (y entra en
   * light-sleep) en los huecos de inactividad entre tasks, sin tocar la
   * frecuencia maxima disponible cuando hay trabajo real. min_freq_mhz=80
   * deja margen de sobra para el timing de I2C/BLE; se puede bajar mas
   * (ej. 40) tras validar en campo que no afecta a la estabilidad BLE.
   */
  ESP_ERROR_CHECK(
    esp_pm_configure(&(esp_pm_config_t){
      .max_freq_mhz = 160,
      .min_freq_mhz = 80,
      .light_sleep_enable = true,
    })
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

  TaskHandle_t app_task_handle;

  xTaskCreate(
    app_task,
    "app_task",
    6144,
    NULL,
    5,
    &app_task_handle
  );

#if USE_REAL_SENSORS
  /* app_task espera en ulTaskNotifyTake() a que sensor_manager avise de
   * una lectura de IMU nueva -- ver comentario en app_task(). */
  sensor_manager_set_notify_task(app_task_handle);
#endif

  ESP_LOGI(
    TAG,
    "Listo. Conectate a BLE"
  );
}
