#pragma once
#include "lsm9ds1.h"

esp_err_t lsm9ds1_mock_init(const lsm9ds1_config_t *cfg);
esp_err_t lsm9ds1_mock_read(lsm9ds1_data_t *out);