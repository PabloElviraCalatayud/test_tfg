#include "lsm9ds1_mock.h"
#include "esp_log.h"
#include <stdlib.h>

static const char *TAG = "LSM9DS1_MOCK";

esp_err_t lsm9ds1_mock_init(const lsm9ds1_config_t *cfg)
{
  ESP_LOGI(TAG, "Mock LSM9DS1 initialized");
  return ESP_OK;
}

esp_err_t lsm9ds1_mock_read(lsm9ds1_data_t *out)
{
  if (!out) return ESP_ERR_INVALID_ARG;

  out->ax = ((float)(rand() % 2000) - 1000) / 1000.0f;
  out->ay = ((float)(rand() % 2000) - 1000) / 1000.0f;
  out->az = 1.0f;

  out->gx = ((float)(rand() % 500) - 250);
  out->gy = ((float)(rand() % 500) - 250);
  out->gz = ((float)(rand() % 500) - 250);

  out->mx = ((float)(rand() % 200) - 100) / 10.0f;
  out->my = ((float)(rand() % 200) - 100) / 10.0f;
  out->mz = ((float)(rand() % 200) - 100) / 10.0f;

  return ESP_OK;
}