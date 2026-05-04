#pragma once

#include <stdbool.h>

typedef enum {
  SYS_STATE_INIT,
  SYS_STATE_IDLE,
  SYS_STATE_RUNNING,
  SYS_STATE_OTA,
  SYS_STATE_ERROR
} system_state_t;

typedef void (*sys_state_cb_t)(system_state_t);

void system_state_init(void);
system_state_t system_state_get(void);
void system_state_set(system_state_t state);
bool system_state_register_cb(sys_state_cb_t cb);