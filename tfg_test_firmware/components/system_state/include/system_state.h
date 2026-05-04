#pragma once
#include <stdbool.h>

/**
 * @brief Estados globales del sistema.
 *
 * La transición única válida en condiciones normales es:
 *   INIT → RUNNING → OTA → RUNNING (tras reboot)
 * ERROR es un estado terminal (requiere reset).
 */
typedef enum {
    SYS_STATE_INIT    = 0,
    SYS_STATE_RUNNING,
    SYS_STATE_OTA,
    SYS_STATE_ERROR,
} system_state_t;

/** Callback notificado cuando el estado cambia (solo en cambios reales). */
typedef void (*sys_state_cb_t)(system_state_t new_state);

void             system_state_init(void);
system_state_t   system_state_get(void);

/**
 * @brief Cambia el estado global.
 * Idempotente: si el estado ya es el mismo, no notifica callbacks.
 * LECCIÓN del proyecto anterior: sin esta protección los callbacks
 * se ejecutan múltiples veces (problema #2 del README).
 */
void system_state_set(system_state_t state);

/** Registra un callback. Máx 8 callbacks. */
bool system_state_register_cb(sys_state_cb_t cb);

