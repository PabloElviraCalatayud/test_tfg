idf_component_register(
  SRCS
    "lsm9ds1.c"
    "ads1115.c"

  INCLUDE_DIRS
    "include"

  REQUIRES
    driver
    esp_driver_i2c
    esp_timer
)
