#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

#define ADS1115_ADDR_GND  0x48
#define ADS1115_ADDR_VCC  0x49
#define ADS1115_ADDR_SDA  0x4A
#define ADS1115_ADDR_SCL  0x4B

#define ADS1115_NUM_CHANNELS 4  /**< canales single-ended por chip ADS1115 */

typedef enum {
  ADS1115_MUX_AIN0_GND = 0x04,
  ADS1115_MUX_AIN1_GND = 0x05,
  ADS1115_MUX_AIN2_GND = 0x06,
  ADS1115_MUX_AIN3_GND = 0x07,
  ADS1115_MUX_AIN0_AIN1 = 0x00,
  ADS1115_MUX_AIN2_AIN3 = 0x03,
} ads1115_mux_t;

typedef enum {
  ADS1115_FSR_6144MV = 0x00,
  ADS1115_FSR_4096MV = 0x01,
  ADS1115_FSR_2048MV = 0x02,
  ADS1115_FSR_1024MV = 0x03,
  ADS1115_FSR_512MV  = 0x04,
  ADS1115_FSR_256MV  = 0x05,
} ads1115_fsr_t;

typedef enum {
  ADS1115_DR_8SPS   = 0x00,
  ADS1115_DR_16SPS  = 0x01,
  ADS1115_DR_32SPS  = 0x02,
  ADS1115_DR_64SPS  = 0x03,
  ADS1115_DR_128SPS = 0x04,
  ADS1115_DR_250SPS = 0x05,
  ADS1115_DR_475SPS = 0x06,
  ADS1115_DR_860SPS = 0x07,
} ads1115_dr_t;

typedef struct {
  i2c_master_bus_handle_t bus;
  uint8_t addr;
  ads1115_fsr_t fsr;
  ads1115_dr_t data_rate;
} ads1115_config_t;

typedef struct {
  int16_t raw[ADS1115_NUM_CHANNELS];
  float voltage[ADS1115_NUM_CHANNELS];
} ads1115_result_t;

/**
 * Handle opaco a una instancia de ADS1115. Cada chip físico (hasta 4 en el
 * mismo bus I2C, uno por dirección ADS1115_ADDR_*) tiene su propio handle,
 * lo que permite escalar de 4 a 16 canales analógicos usando 4 chips.
 */
typedef struct ads1115_dev_s *ads1115_handle_t;

esp_err_t ads1115_init(const ads1115_config_t *cfg, ads1115_handle_t *out_handle);
esp_err_t ads1115_read_all(ads1115_handle_t handle, ads1115_result_t *out);
esp_err_t ads1115_read_channel(ads1115_handle_t handle, ads1115_mux_t mux, int16_t *raw_out);
void ads1115_deinit(ads1115_handle_t handle);

float ads1115_ntc_to_celsius(float v_adc, float v_ref, float r_ref_ohm);
uint32_t ads1115_voltage_to_grams(float voltage, float v_max, uint32_t pressure_max_g);
