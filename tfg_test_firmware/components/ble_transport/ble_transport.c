#include "ble_transport.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "nvs_flash.h"

#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "esp_log.h"
#include <string.h>

static const char *TAG = "BLE";

/* UUIDs */
static const ble_uuid128_t SERVICE_UUID =
    BLE_UUID128_INIT(0xBC,0x9A,0x78,0x56,0x34,0x12,0x34,0x12,
                     0x34,0x12,0x34,0x12,0x78,0x56,0x34,0x12);

static const ble_uuid128_t CHR_SENSOR_UUID =
    BLE_UUID128_INIT(0xBD,0x9A,0x78,0x56,0x34,0x12,0x34,0x12,
                     0x34,0x12,0x34,0x12,0x78,0x56,0x34,0x12);

static const ble_uuid128_t CHR_CMD_UUID =
    BLE_UUID128_INIT(0xBE,0x9A,0x78,0x56,0x34,0x12,0x34,0x12,
                     0x34,0x12,0x34,0x12,0x78,0x56,0x34,0x12);

/* Estado */
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_sensor_val_hdl = 0;
static ble_cmd_handler_t s_cmd_handler = NULL;
static bool s_notify_enabled = false;

#define TX_QUEUE_DEPTH 8

typedef struct {
  uint8_t data[BLE_PKT_MAX_SIZE];
  uint16_t len;
} ble_pkt_t;

static QueueHandle_t s_tx_queue = NULL;

/* Forward */
static void das_ble_advertise(void);
static int gap_event_cb(struct ble_gap_event *event, void *arg);

/* GATT */
static int sensor_chr_access(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg) {
  return 0;
}

static int cmd_chr_access(uint16_t conn_handle, uint16_t attr_handle,
                          struct ble_gatt_access_ctxt *ctxt, void *arg) {

  if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len > BLE_PKT_MAX_SIZE) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

    uint8_t buf[BLE_PKT_MAX_SIZE];
    uint16_t out_len;

    if (ble_hs_mbuf_to_flat(ctxt->om, buf, sizeof(buf), &out_len) != 0)
      return BLE_ATT_ERR_UNLIKELY;

    if (s_cmd_handler) s_cmd_handler(buf, out_len);
  }

  return 0;
}

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
  {
    .type = BLE_GATT_SVC_TYPE_PRIMARY,
    .uuid = &SERVICE_UUID.u,
    .characteristics = (struct ble_gatt_chr_def[]) {
      {
        .uuid       = &CHR_SENSOR_UUID.u,
        .flags      = BLE_GATT_CHR_F_NOTIFY,
        .val_handle = &s_sensor_val_hdl,
        .access_cb  = sensor_chr_access,
      },
      {
        .uuid      = &CHR_CMD_UUID.u,
        .flags     = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
        .access_cb = cmd_chr_access,
      },
      { 0 },
    },
  },
  { 0 },
};

/* Advertising */
static void das_ble_advertise(void) {
  struct ble_gap_adv_params adv_params = {0};
  adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
  adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

  struct ble_hs_adv_fields fields = {0};
  fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
  fields.name = (uint8_t *)"ESP32S3-DAS";
  fields.name_len = 11;
  fields.name_is_complete = 1;

  ble_gap_adv_set_fields(&fields);

  int rc = ble_gap_adv_start(BLE_OWN_ADDR_PUBLIC, NULL, BLE_HS_FOREVER,
                             &adv_params, gap_event_cb, NULL);

  if (rc != 0) ESP_LOGE(TAG, "Adv error: %d", rc);
}

/* GAP events */
static int gap_event_cb(struct ble_gap_event *event, void *arg) {
  switch (event->type) {

    case BLE_GAP_EVENT_CONNECT:
      if (event->connect.status == 0) {
        s_conn_handle = event->connect.conn_handle;
        ble_att_set_preferred_mtu(247);
        ble_gattc_exchange_mtu(s_conn_handle, NULL, NULL);
      } else {
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        das_ble_advertise();
      }
      break;

    case BLE_GAP_EVENT_DISCONNECT:
      s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
      s_notify_enabled = false;
      das_ble_advertise();
      break;

    case BLE_GAP_EVENT_SUBSCRIBE:
      if (event->subscribe.attr_handle == s_sensor_val_hdl) {
        s_notify_enabled = event->subscribe.cur_notify;
      }
      break;

    default:
      break;
  }
  return 0;
}

/* NimBLE */
static void on_reset(int reason) {
  s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
}

static void on_sync(void) {
  ble_hs_util_ensure_addr(0);
  das_ble_advertise();
}

static void nimble_host_task(void *arg) {
  nimble_port_run();
  nimble_port_freertos_deinit();
}

/* TX task */
static void ble_tx_task(void *arg) {
  ble_pkt_t pkt;

  while (1) {
    if (xQueueReceive(s_tx_queue, &pkt, portMAX_DELAY) != pdTRUE) continue;
    if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE) continue;
    if (!s_notify_enabled) continue;

    struct os_mbuf *om = ble_hs_mbuf_from_flat(pkt.data, pkt.len);
    if (!om) continue;

    ble_gatts_notify_custom(s_conn_handle, s_sensor_val_hdl, om);

    vTaskDelay(pdMS_TO_TICKS(15));
  }
}

/* API */
esp_err_t das_ble_init(void) {

  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    nvs_flash_erase();
    err = nvs_flash_init();
  }
  if (err != ESP_OK) return err;

  s_tx_queue = xQueueCreate(TX_QUEUE_DEPTH, sizeof(ble_pkt_t));
  if (!s_tx_queue) return ESP_ERR_NO_MEM;

  nimble_port_init();

  ble_hs_cfg.reset_cb = on_reset;
  ble_hs_cfg.sync_cb  = on_sync;
  ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

  ble_svc_gap_init();
  ble_svc_gatt_init();
  ble_svc_gap_device_name_set("ESP32S3-DAS");

  ble_gatts_count_cfg(s_gatt_svcs);
  ble_gatts_add_svcs(s_gatt_svcs);

  nimble_port_freertos_init(nimble_host_task);

  xTaskCreate(ble_tx_task, "ble_tx", 4096, NULL, 5, NULL);

  return ESP_OK;
}

bool das_ble_notify(const uint8_t *data, uint16_t len) {
  if (!data || len == 0 || len > BLE_PKT_MAX_SIZE) return false;

  ble_pkt_t pkt;
  pkt.len = len;
  memcpy(pkt.data, data, len);

  if (xQueueSend(s_tx_queue, &pkt, pdMS_TO_TICKS(50)) != pdTRUE) {
    ESP_LOGW(TAG, "queue full");
    return false;
  }
  return true;
}

void das_ble_set_cmd_handler(ble_cmd_handler_t handler) {
  s_cmd_handler = handler;
}

bool das_ble_is_connected(void) {
  return s_conn_handle != BLE_HS_CONN_HANDLE_NONE;
}
