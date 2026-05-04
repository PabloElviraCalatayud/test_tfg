#pragma once
#include "ads1115.h"

esp_err_t ads1115_mock_init(const ads1115_config_t *cfg);
esp_err_t ads1115_mock_read_all(ads1115_result_t *out);