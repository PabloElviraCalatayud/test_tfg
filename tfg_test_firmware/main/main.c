#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

#include "system_state.h"
#include "ble_transport.h"
#include "ota_manager.h"
#include "packet_builder.h"
#include "ads1115_mock.h"
#include "lsm9ds1_mock.h"

static const char *TAG = "MAIN";

/* ── Tarea de sensores mock ─────────────────────────────────────────────────
 * Lee mock, empaqueta y manda por BLE a 1 Hz.
 * Se detiene automáticamente cuando el estado pasa a OTA
 * (la cola BLE descarta si no hay conexión, no bloquea).
 * ────────────────────────────────────────────────────────────────────────── */
static void sensor_task(void *arg)
{
    uint8_t         pkt_buf[PKT_SENSOR_SIZE];
    size_t          pkt_len;
    sensor_data_t   data;
    ads1115_result_t adc;
    lsm9ds1_data_t   imu;

    while (1) {
        /* Parar si estamos en OTA */
        if (system_state_get() == SYS_STATE_OTA) {
            ESP_LOGI(TAG, "[sensor_task] OTA activo → sensores pausados");
            vTaskDelay(pdMS_TO_TICKS(500));
            continue;
        }

        /* Leer mocks */
        ads1115_mock_read_all(&adc);
        lsm9ds1_mock_read(&imu);

        /* Copiar a sensor_data_t */
        data.accel_x = imu.ax;  data.accel_y = imu.ay;  data.accel_z = imu.az;
        data.gyro_x  = imu.gx;  data.gyro_y  = imu.gy;  data.gyro_z  = imu.gz;
        data.mag_x   = imu.mx;  data.mag_y   = imu.my;  data.mag_z   = imu.mz;

        for (int i = 0; i < NUM_PRESSURE_SENSORS; i++) {
            data.pressure[i] = (uint32_t)(adc.voltage[i] / 3.3f * 100000.0f);
        }
        data.temperature[0] = 20.0f + ((float)(rand() % 100)) / 10.0f;
        data.temperature[1] = 20.0f + ((float)(rand() % 100)) / 10.0f;

        /* Log en terminal */
        ESP_LOGI(TAG, "IMU  A[%.2f %.2f %.2f] G[%.1f %.1f %.1f]",
                 imu.ax, imu.ay, imu.az, imu.gx, imu.gy, imu.gz);
        ESP_LOGI(TAG, "ADC  P[%lu %lu %lu %lu] T[%.1f %.1f]",
                 data.pressure[0], data.pressure[1],
                 data.pressure[2], data.pressure[3],
                 data.temperature[0], data.temperature[1]);

        /* Empaquetar y enviar */
        /* Empaquetar y enviar */
        if (packet_build_sensor(&data, pkt_buf, &pkt_len)) {

            das_ble_notify(pkt_buf, (uint16_t)pkt_len);

            ESP_LOGI(TAG, "PKT  %d bytes → BLE %s",
                    (int)pkt_len,
                    das_ble_is_connected() ? "OK" : "no conn");
        }

        ESP_LOGI(TAG, "─────────────────────────────");
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "=== ESP32-S3 DAS (mock) arrancando ===");

    /* 1. Estado global */
    system_state_init();

    /* 2. BLE (también inicializa NVS internamente) */
    if (das_ble_init() != ESP_OK) {
        ESP_LOGE(TAG, "BLE init failed");
        return;
    }

    /* 3. OTA manager (escucha comandos BLE) */
    if (ota_manager_init() != ESP_OK) {
        ESP_LOGE(TAG, "OTA init failed");
        return;
    }

    /* 4. Packet builder */
    packet_builder_init();

    /* 5. Sensores mock */
    ads1115_config_t ads_cfg = {
        .bus = NULL, .addr = 0x48,
        .fsr = ADS1115_FSR_4096MV, .data_rate = ADS1115_DR_128SPS
    };
    ads1115_mock_init(&ads_cfg);

    lsm9ds1_config_t imu_cfg = { .bus = NULL, .scl_hz = 400000 };
    lsm9ds1_mock_init(&imu_cfg);

    /* 6. Sistema listo */
    system_state_set(SYS_STATE_RUNNING);

    /* 7. Tarea de sensores */
    xTaskCreate(sensor_task, "sensor_task", 4096, NULL, 5, NULL);

    ESP_LOGI(TAG, "Listo. Conéctate con nRF Connect a 'ESP32S3-DAS'");
}