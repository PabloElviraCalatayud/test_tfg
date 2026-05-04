idf_component_register(
  SRCS "ota_manager.c"
  INCLUDE_DIRS "include"
  REQUIRES
    system_state
    ble_transport
    packet_builder
    app_update
    esp_partition
    esp_system
    freertos
    log
)
