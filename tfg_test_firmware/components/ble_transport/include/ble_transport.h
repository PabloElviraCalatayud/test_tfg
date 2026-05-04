#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "esp_err.h"

#define BLE_PKT_MAX_SIZE   244

typedef void (*ble_cmd_handler_t)(const uint8_t *data, uint16_t len);

esp_err_t das_ble_init(void);
bool das_ble_notify(const uint8_t *data, uint16_t len);
void das_ble_set_cmd_handler(ble_cmd_handler_t handler);
bool das_ble_is_connected(void);
