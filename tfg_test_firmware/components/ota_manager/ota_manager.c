#include "ota_manager.h"
#include "ble_transport.h"
#include "packet_builder.h"
#include "system_state.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_log.h"
#include "esp_system.h"

#include <string.h>

static const char *TAG = "OTA_MGR";

typedef struct {
  uint8_t  cmd;
  uint8_t  data[BLE_PKT_MAX_SIZE];
  uint16_t data_len;
} ota_msg_t;

static QueueHandle_t s_queue = NULL;

/* ACK */
static void send_ack(uint8_t cmd, uint8_t status) {
  uint8_t buf[PKT_ACK_SIZE];
  size_t len;

  if (packet_build_ack(cmd, status, buf, &len)) {
    das_ble_notify(buf, (uint16_t)len);
  }
}

/* BLE handler */
static void ota_ble_cmd_handler(const uint8_t *data, uint16_t len) {

  if (!data || len == 0 || !s_queue) return;

  ota_msg_t msg = {0};

  msg.cmd = data[0];
  msg.data_len = (len > 1) ? (len - 1) : 0;

  if (msg.data_len > BLE_PKT_MAX_SIZE) {
    msg.data_len = BLE_PKT_MAX_SIZE;
  }

  if (msg.data_len > 0) {
    memcpy(msg.data, &data[1], msg.data_len);
  }

  xQueueSend(s_queue, &msg, 0);
}

/* OTA TASK */
static void ota_task(void *arg) {

  ota_msg_t msg;

  esp_ota_handle_t ota_handle = 0;
  const esp_partition_t *ota_part = NULL;

  bool ota_active = false;

  while (1) {

    if (xQueueReceive(s_queue, &msg, portMAX_DELAY) != pdTRUE) continue;

    switch (msg.cmd) {

    case OTA_CMD_START: {

      if (ota_active) {
        send_ack(OTA_CMD_START, OTA_STATUS_ERR);
        break;
      }

      ESP_LOGI(TAG, "OTA START");

      system_state_set(SYS_STATE_OTA);
      vTaskDelay(pdMS_TO_TICKS(300));

      ota_part = esp_ota_get_next_update_partition(NULL);

      if (!ota_part) {
        send_ack(OTA_CMD_START, OTA_STATUS_ERR);
        system_state_set(SYS_STATE_RUNNING);
        break;
      }

      if (esp_ota_begin(ota_part, OTA_WITH_SEQUENTIAL_WRITES, &ota_handle) != ESP_OK) {
        send_ack(OTA_CMD_START, OTA_STATUS_ERR);
        system_state_set(SYS_STATE_RUNNING);
        break;
      }

      ota_active = true;
      send_ack(OTA_CMD_START, OTA_STATUS_OK);
      break;
    }

    case OTA_CMD_DATA: {

      if (!ota_active || !ota_handle) {
        send_ack(OTA_CMD_DATA, OTA_STATUS_ERR);
        break;
      }

      if (esp_ota_write(ota_handle, msg.data, msg.data_len) != ESP_OK) {
        send_ack(OTA_CMD_DATA, OTA_STATUS_ERR);
      } else {
        send_ack(OTA_CMD_DATA, OTA_STATUS_OK);
      }

      break;
    }

    case OTA_CMD_END: {

      if (!ota_active) {
        send_ack(OTA_CMD_END, OTA_STATUS_ERR);
        break;
      }

      if (esp_ota_end(ota_handle) != ESP_OK) {
        send_ack(OTA_CMD_END, OTA_STATUS_ERR);
        ota_active = false;
        system_state_set(SYS_STATE_RUNNING);
        break;
      }

      if (esp_ota_set_boot_partition(ota_part) != ESP_OK) {
        send_ack(OTA_CMD_END, OTA_STATUS_ERR);
        ota_active = false;
        system_state_set(SYS_STATE_RUNNING);
        break;
      }

      send_ack(OTA_CMD_END, OTA_STATUS_OK);

      ESP_LOGI(TAG, "Rebooting...");
      vTaskDelay(pdMS_TO_TICKS(1000));
      esp_restart();
      break;
    }

    case OTA_CMD_ABORT: {

      if (ota_active && ota_handle) {
        esp_ota_abort(ota_handle);
      }

      ota_active = false;
      send_ack(OTA_CMD_ABORT, OTA_STATUS_OK);
      system_state_set(SYS_STATE_RUNNING);
      break;
    }

    default:
      ESP_LOGW(TAG, "Unknown cmd: 0x%02X", msg.cmd);
      break;
    }
  }
}

/* INIT */
esp_err_t ota_manager_init(void) {

  s_queue = xQueueCreate(4, sizeof(ota_msg_t));
  if (!s_queue) return ESP_ERR_NO_MEM;

  das_ble_set_cmd_handler(ota_ble_cmd_handler);

  xTaskCreate(ota_task, "ota_task", 8192, NULL, 8, NULL);

  return ESP_OK;
}
