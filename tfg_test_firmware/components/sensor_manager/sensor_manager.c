#include "sensor_manager.h"
#include "imu_driver.h"
#include "ads1115.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "driver/i2c_master.h"
#include "esp_log.h"

#include <string.h>

#define I2C_PORT 0
#define I2C_SDA  GPIO_NUM_8
#define I2C_SCL  GPIO_NUM_9

static const char *TAG = "SENSOR_MGR";

/*
 * El ADS1115 solo tiene 4 entradas single-ended, así que para llegar a los
 * 12 FSR + 4 termistores (16 canales) se usan 4 chips en el mismo bus I2C,
 * uno por cada dirección posible (GND/VCC/SDA/SCL). Los primeros 3 chips
 * (12 canales) alimentan los FSR y el 4º chip (4 canales) los termistores.
 */
#define ADS1115_NUM_DEVICES        4
#define ADS1115_FSR_DEVICE_COUNT   3
#define ADS1115_TEMP_DEVICE_INDEX  3

#define FSR_V_REF           3.3f      /* tensión de alimentación del divisor FSR */
#define FSR_PRESSURE_MAX_G  100000u   /* debe coincidir con PRESSURE_MAX del packet_builder */

#define NTC_V_REF           3.3f
#define NTC_R_REF_OHM       10000.0f

static const uint8_t ADC_I2C_ADDR[ADS1115_NUM_DEVICES] = {
  ADS1115_ADDR_GND,
  ADS1115_ADDR_VCC,
  ADS1115_ADDR_SDA,
  ADS1115_ADDR_SCL,
};

static ads1115_handle_t s_adc[ADS1115_NUM_DEVICES];

static sensor_frame_t frame;

static SemaphoreHandle_t mutex;

static TaskHandle_t imu_task_handle;
static TaskHandle_t adc_task_handle;

static void imu_task(void *arg) {
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

static void adc_task(void *arg) {
  ads1115_result_t res;
  uint32_t pressure[SM_NUM_FSR_SENSORS];
  float    temperature[SM_NUM_THERMISTOR_SENSORS];

  while (1) {

    int fsr_idx = 0;
    for (int dev = 0; dev < ADS1115_FSR_DEVICE_COUNT; dev++) {

      if (ads1115_read_all(s_adc[dev], &res) == ESP_OK) {

        for (int ch = 0; ch < ADS1115_NUM_CHANNELS; ch++) {
          pressure[fsr_idx] = ads1115_voltage_to_grams(
            res.voltage[ch], FSR_V_REF, FSR_PRESSURE_MAX_G
          );

          ESP_LOGI(
            TAG,
            "FSR[%2d] addr=0x%02X ch=%d  V=%.3fV  P=%u g",
            fsr_idx, ADC_I2C_ADDR[dev], ch,
            res.voltage[ch], (unsigned int)pressure[fsr_idx]
          );

          fsr_idx++;
        }

      } else {

        ESP_LOGW(TAG, "Fallo lectura ADS1115 FSR addr=0x%02X", ADC_I2C_ADDR[dev]);

        for (int ch = 0; ch < ADS1115_NUM_CHANNELS; ch++) {
          pressure[fsr_idx++] = 0;
        }
      }
    }

    if (ads1115_read_all(s_adc[ADS1115_TEMP_DEVICE_INDEX], &res) == ESP_OK) {

      for (int ch = 0; ch < SM_NUM_THERMISTOR_SENSORS; ch++) {
        temperature[ch] = ads1115_ntc_to_celsius(res.voltage[ch], NTC_V_REF, NTC_R_REF_OHM);

        ESP_LOGI(
          TAG,
          "NTC[%d] addr=0x%02X ch=%d  V=%.3fV  T=%.1f C",
          ch, ADC_I2C_ADDR[ADS1115_TEMP_DEVICE_INDEX], ch,
          res.voltage[ch], temperature[ch]
        );
      }

    } else {

      ESP_LOGW(
        TAG, "Fallo lectura ADS1115 NTC addr=0x%02X",
        ADC_I2C_ADDR[ADS1115_TEMP_DEVICE_INDEX]
      );

      for (int ch = 0; ch < SM_NUM_THERMISTOR_SENSORS; ch++) {
        temperature[ch] = 0.0f;
      }
    }

    xSemaphoreTake(mutex, portMAX_DELAY);

    memcpy(frame.pressure, pressure, sizeof(pressure));
    memcpy(frame.temperature, temperature, sizeof(temperature));

    xSemaphoreGive(mutex);

    vTaskDelay(pdMS_TO_TICKS(200));
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

  for (int i = 0; i < ADS1115_NUM_DEVICES; i++) {
    ads1115_config_t adc_cfg = {
      .bus = bus,
      .addr = ADC_I2C_ADDR[i],
      .fsr = ADS1115_FSR_4096MV,
      .data_rate = ADS1115_DR_128SPS,
    };

    ESP_ERROR_CHECK(
      ads1115_init(&adc_cfg, &s_adc[i])
    );
  }

  mutex = xSemaphoreCreateMutex();

  xTaskCreate(
    imu_task,
    "imu_task",
    4096,
    NULL,
    5,
    &imu_task_handle
  );

  xTaskCreate(
    adc_task,
    "adc_task",
    4096,
    NULL,
    4,
    &adc_task_handle
  );
}

bool sensor_manager_get_frame(
  sensor_frame_t *out
) {
  if (!out) {
    return false;
  }

  xSemaphoreTake(mutex, portMAX_DELAY);

  *out = frame;

  xSemaphoreGive(mutex);

  return true;
}
