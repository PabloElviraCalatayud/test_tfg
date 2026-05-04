idf_component_register(
  SRCS
    "ads1115_mock.c"
    "lsm9ds1_mock.c"

  INCLUDE_DIRS
    "include"

  REQUIRES
    drivers
)