#pragma once
#include <stdint.h>
#include "esp_err.h"

#define OTA_CMD_START   0x10
#define OTA_CMD_DATA    0x11
#define OTA_CMD_END     0x12
#define OTA_CMD_ABORT   0x13

#define OTA_STATUS_OK   0x00
#define OTA_STATUS_ERR  0x01

esp_err_t ota_manager_init(void);
