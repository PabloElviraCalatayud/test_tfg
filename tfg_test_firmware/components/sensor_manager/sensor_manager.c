#include "sensor_manager.h"
#include "imu_driver.h"
#include "ads1115.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "driver/i2c_master.h"
#include "esp_log.h"

#include <stdio.h>
#include <string.h>

#define I2C_PORT0 I2C_NUM_0
#define I2C_SDA0  GPIO_NUM_8
#define I2C_SCL0  GPIO_NUM_9

#define I2C_PORT1 I2C_NUM_1
#define I2C_SDA1  GPIO_NUM_4
#define I2C_SCL1  GPIO_NUM_5

/* Igual que en el hardware de referencia que sí funciona con los 4 ADS1115:
 * 100 kHz es mas robusto en breadboard/cableado largo que 400 kHz. */
#define I2C_FREQ_HZ 100000

static const char *TAG = "SENSOR_MGR";

/*
 * El ADS1115 solo tiene 4 entradas single-ended. En vez de poner los 4
 * chips en un unico bus con 4 direcciones distintas (lo que exige atar
 * ADDR a SDA/SCL en dos de ellos -- un cableado delicado que si falla
 * puede tumbar el bus entero), se usan 2 buses I2C fisicos, con 2 chips
 * por bus en las direcciones simples GND/VCC (0x48/0x49). Los primeros
 * 3 chips (12 canales) alimentan los FSR y el 4º chip (4 canales) los
 * termistores.
 */
#define ADS1115_NUM_DEVICES        4
#define ADS1115_FSR_DEVICE_COUNT   3
#define ADS1115_TEMP_DEVICE_INDEX  3

#define FSR_V_REF           3.3f      /* tensión de alimentación del divisor FSR */
#define FSR_PRESSURE_MAX_G  100000u   /* debe coincidir con PRESSURE_MAX del packet_builder */

#define NTC_V_REF           3.3f
#define NTC_R_REF_OHM       10000.0f

static const uint8_t ADC_I2C_ADDR[ADS1115_NUM_DEVICES] = {
  ADS1115_ADDR_GND, ADS1115_ADDR_VCC,
  ADS1115_ADDR_GND, ADS1115_ADDR_VCC,
};

/* A que bus fisico (0 = GPIO8/9, 1 = GPIO4/5) pertenece cada chip */
static const uint8_t ADC_I2C_BUS[ADS1115_NUM_DEVICES] = {
  0, 0,
  1, 1,
};

static ads1115_handle_t s_adc[ADS1115_NUM_DEVICES];

static sensor_frame_t frame;

static SemaphoreHandle_t mutex;

static TaskHandle_t imu_task_handle;
static TaskHandle_t adc_task_handle;
static TaskHandle_t console_task_handle;

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

          ESP_LOGD(
            TAG,
            "FSR[%2d] bus=%d addr=0x%02X ch=%d  V=%.3fV  P=%u g",
            fsr_idx, ADC_I2C_BUS[dev], ADC_I2C_ADDR[dev], ch,
            res.voltage[ch], (unsigned int)pressure[fsr_idx]
          );

          fsr_idx++;
        }

      } else {

        ESP_LOGW(
          TAG, "Fallo lectura ADS1115 FSR bus=%d addr=0x%02X",
          ADC_I2C_BUS[dev], ADC_I2C_ADDR[dev]
        );

        for (int ch = 0; ch < ADS1115_NUM_CHANNELS; ch++) {
          pressure[fsr_idx++] = 0;
        }
      }
    }

    if (ads1115_read_all(s_adc[ADS1115_TEMP_DEVICE_INDEX], &res) == ESP_OK) {

      for (int ch = 0; ch < SM_NUM_THERMISTOR_SENSORS; ch++) {
        temperature[ch] = ads1115_ntc_to_celsius(res.voltage[ch], NTC_V_REF, NTC_R_REF_OHM);

        ESP_LOGD(
          TAG,
          "NTC[%d] bus=%d addr=0x%02X ch=%d  V=%.3fV  T=%.1f C",
          ch, ADC_I2C_BUS[ADS1115_TEMP_DEVICE_INDEX],
          ADC_I2C_ADDR[ADS1115_TEMP_DEVICE_INDEX], ch,
          res.voltage[ch], temperature[ch]
        );
      }

    } else {

      ESP_LOGW(
        TAG, "Fallo lectura ADS1115 NTC bus=%d addr=0x%02X",
        ADC_I2C_BUS[ADS1115_TEMP_DEVICE_INDEX],
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

/*
 * Volcado por consola en tiempo real. IMU, FSR y termistores se leen a
 * ritmos distintos (20/200 ms) en tasks separadas; en vez de que cada
 * una imprima por su cuenta (ilegible, se intercalan sin orden), esta
 * task toma una unica foto de `frame` y la imprime en UNA linea, a un
 * ritmo fijo y lento (2 Hz) para poder seguirla a simple vista.
 */
static void console_task(void *arg) {
  sensor_frame_t snap;

  while (1) {
    xSemaphoreTake(mutex, portMAX_DELAY);
    snap = frame;
    xSemaphoreGive(mutex);

    char fsr_str[SM_NUM_FSR_SENSORS * 7 + 1];
    int  pos = 0;
    for (int i = 0; i < SM_NUM_FSR_SENSORS; i++) {
      pos += snprintf(
        fsr_str + pos, sizeof(fsr_str) - pos,
        "%s%u", (i == 0) ? "" : " ", (unsigned int)snap.pressure[i]
      );
    }

    char ntc_str[SM_NUM_THERMISTOR_SENSORS * 7 + 1];
    pos = 0;
    for (int i = 0; i < SM_NUM_THERMISTOR_SENSORS; i++) {
      pos += snprintf(
        ntc_str + pos, sizeof(ntc_str) - pos,
        "%s%.1f", (i == 0) ? "" : " ", snap.temperature[i]
      );
    }

    ESP_LOGI(
      TAG,
      "IMU A[%5.2f %5.2f %5.2f] G[%6.1f %6.1f %6.1f] | FSR(g)[%s] | NTC(C)[%s]",
      snap.ax, snap.ay, snap.az,
      snap.gx, snap.gy, snap.gz,
      fsr_str, ntc_str
    );

    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

static i2c_master_bus_handle_t create_bus(
  i2c_port_t port,
  gpio_num_t sda,
  gpio_num_t scl
) {
  i2c_master_bus_handle_t bus;

  i2c_master_bus_config_t cfg = {
    .i2c_port = port,
    .sda_io_num = sda,
    .scl_io_num = scl,
    .clk_source = I2C_CLK_SRC_DEFAULT,
    .glitch_ignore_cnt = 7,
    .flags.enable_internal_pullup = true
  };

  ESP_ERROR_CHECK(
    i2c_new_master_bus(&cfg, &bus)
  );

  return bus;
}

/* Escanea el bus y vuelca por consola que direcciones responden de
 * verdad, para poder diagnosticar cableado sin herramientas externas. */
static void scan_bus(i2c_master_bus_handle_t bus, int bus_index) {
  ESP_LOGI(TAG, "Escaneando bus I2C %d...", bus_index);

  for (uint8_t addr = 0x03; addr < 0x78; addr++) {
    if (i2c_master_probe(bus, addr, 50) == ESP_OK) {
      ESP_LOGI(TAG, "  bus %d: dispositivo encontrado en 0x%02X", bus_index, addr);
    }
  }
}

void sensor_manager_init(void) {
  i2c_master_bus_handle_t bus0 = create_bus(I2C_PORT0, I2C_SDA0, I2C_SCL0);
  i2c_master_bus_handle_t bus1 = create_bus(I2C_PORT1, I2C_SDA1, I2C_SCL1);
  i2c_master_bus_handle_t buses[2] = { bus0, bus1 };

  scan_bus(bus0, 0);
  scan_bus(bus1, 1);

  ESP_ERROR_CHECK(
    imu_driver_init(bus0)
  );

  for (int i = 0; i < ADS1115_NUM_DEVICES; i++) {
    ads1115_config_t adc_cfg = {
      .bus = buses[ADC_I2C_BUS[i]],
      .addr = ADC_I2C_ADDR[i],
      .fsr = ADS1115_FSR_4096MV,
      .data_rate = ADS1115_DR_128SPS,
    };

    /*
     * No se aborta si un ADS1115 no responde: puede que ese chip todavia
     * no este cableado (ej. bring-up parcial de los 16 canales). Se deja
     * su handle a NULL y adc_task lo detecta y lo omite en cada lectura.
     */
    esp_err_t err = ads1115_init(&adc_cfg, &s_adc[i]);
    if (err != ESP_OK) {
      ESP_LOGW(
        TAG,
        "ADS1115 bus=%d addr=0x%02X no disponible (err=0x%x), se omite",
        ADC_I2C_BUS[i], ADC_I2C_ADDR[i], err
      );
      s_adc[i] = NULL;
    }
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

  xTaskCreate(
    console_task,
    "console_task",
    4096,
    NULL,
    3,
    &console_task_handle
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
