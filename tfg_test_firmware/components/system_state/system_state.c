#include "system_state.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_log.h"

static const char *TAG = "SYS_STATE";

#define MAX_CALLBACKS 8

static system_state_t   s_state    = SYS_STATE_INIT;
static SemaphoreHandle_t s_mutex   = NULL;
static sys_state_cb_t   s_cbs[MAX_CALLBACKS];
static int              s_cb_count = 0;

static const char *state_name(system_state_t s) {
    switch (s) {
        case SYS_STATE_INIT:    return "INIT";
        case SYS_STATE_RUNNING: return "RUNNING";
        case SYS_STATE_OTA:     return "OTA";
        case SYS_STATE_ERROR:   return "ERROR";
        default:                return "UNKNOWN";
    }
}

void system_state_init(void) {
    s_mutex = xSemaphoreCreateMutex();
    configASSERT(s_mutex);
    s_state    = SYS_STATE_INIT;
    s_cb_count = 0;
    ESP_LOGI(TAG, "Initialized");
}

system_state_t system_state_get(void) {
    xSemaphoreTake(s_mutex, portMAX_DELAY);
    system_state_t st = s_state;
    xSemaphoreGive(s_mutex);
    return st;
}

void system_state_set(system_state_t state) {
    xSemaphoreTake(s_mutex, portMAX_DELAY);

    /* ─── IDEMPOTENTE: no notificar si no hay cambio real ─────────────────
     * Lección del proyecto anterior (#2): system_state_set() llamado
     * múltiples veces con el mismo estado disparaba los callbacks N veces,
     * causando intentos de detener sensores ya detenidos.
     */
    if (s_state == state) {
        xSemaphoreGive(s_mutex);
        return;
    }

    ESP_LOGI(TAG, "Transition: %s → %s", state_name(s_state), state_name(state));
    s_state = state;
    xSemaphoreGive(s_mutex);

    /* Notificar fuera del mutex para evitar deadlocks en callbacks */
    for (int i = 0; i < s_cb_count; i++) {
        s_cbs[i](state);
    }
}

bool system_state_register_cb(sys_state_cb_t cb) {
    if (!cb || s_cb_count >= MAX_CALLBACKS) {
        return false;
    }
    s_cbs[s_cb_count++] = cb;
    return true;
}

