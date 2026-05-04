#include "ads1115_mock.h"
#include "esp_log.h"
#include <stdlib.h>

static const char *TAG = "ADS1115_MOCK";

esp_err_t ads1115_mock_init(const ads1115_config_t *cfg)
{
  ESP_LOGI(TAG, "Mock ADS1115 initialized");
  return ESP_OK;
}

esp_err_t ads1115_mock_read_all(ads1115_result_t *out)
{
  if (!out) return ESP_ERR_INVALID_ARG;

  for (int i = 0; i < 4; i++) {
    out->raw[i] = rand() % 32768;
    out->voltage[i] = ((float)(rand() % 3300)) / 1000.0f;
  }

  return ESP_OK;
}