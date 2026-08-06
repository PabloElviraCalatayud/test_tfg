idf_component_register(
  SRCS
    "sensor_manager.c"
    "imu_driver.c"

  INCLUDE_DIRS
    "include"

  REQUIRES
    driver
    freertos
    esp_common
    system_state
    drivers
    log
)