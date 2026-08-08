idf_component_register(
  SRCS "main.c"
  INCLUDE_DIRS "."
  REQUIRES
    system_state
    ble_transport
    ota_manager
    packet_builder
    sensors_mock
    sensor_manager
    nvs_flash
    freertos
    log
    esp_pm
)