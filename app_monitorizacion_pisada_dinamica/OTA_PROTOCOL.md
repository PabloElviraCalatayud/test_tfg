# Protocolo OTA GaitSole — Especificación

## Visión general

La actualización OTA se realiza sobre BLE usando la característica de comando
(`CHR_CMD`, UUID `...ABE`, write con respuesta). El ESP32 confirma cada paso
mediante un paquete ACK enviado por la característica de sensor
(`CHR_SENSOR`, UUID `...ABD`, notify).

MTU negociado: **247 bytes** → payload útil por write: **244 bytes**.
Tamaño de chunk de datos OTA: **200 bytes** (conservador, cabe en cualquier MTU).

---

## Flujo de mensajes

```
Flutter                           ESP32
  │                                 │
  │──[0x10][size LE 4B]────────────>│  OTA_START
  │<─[ACK 0x10][0x00]───────────────│  ACK_START  OK
  │                                 │
  │──[0x11][idx LE 2B][data]───────>│  OTA_CHUNK (repetir por cada chunk)
  │<─[ACK 0x11][0x00]───────────────│  ACK_CHUNK  OK
  │  (si status != 0 → abort)       │
  │                                 │
  │──[0x12]────────────────────────>│  OTA_END
  │<─[ACK 0x12][0x00]───────────────│  ACK_END  OK → ESP32 reinicia
  │                                 │
  │──[0x13]────────────────────────>│  OTA_ABORT (en cualquier momento)
```

---

## Formato de comandos (Flutter → ESP32)

| Comando    | Byte[0] | Bytes siguientes            | Descripción              |
|------------|---------|------------------------------|--------------------------|
| OTA_START  | `0x10`  | [3][2][1][0] = total_size LE | Anuncia tamaño total     |
| OTA_CHUNK  | `0x11`  | [idx_lo][idx_hi] + data[]    | Chunk de firmware        |
| OTA_END    | `0x12`  | —                            | Finaliza, activa imagen  |
| OTA_ABORT  | `0x13`  | —                            | Cancela y descarta       |

---

## Formato de ACK (ESP32 → Flutter via notify)

```
[0x02][ack_type][status][crc8]   (4 bytes, formato PKT_TYPE_ACK)
```

- `ack_type`: `0x10` START | `0x11` CHUNK | `0x12` END
- `status`:   `0x00` OK  |  `0x01` CRC error | `0x02` write error | `0x03` size error

---

## Implementación en ESP32 (esquema)

```c
// En cmd_chr_access(), tras recibir escritura en CHR_CMD:

void ota_cmd_handler(const uint8_t *buf, uint16_t len) {
    switch (buf[0]) {
        case 0x10: // OTA_START
            uint32_t size = buf[1] | (buf[2]<<8) | (buf[3]<<16) | (buf[4]<<24);
            esp_ota_begin(update_partition, size, &ota_handle);
            send_ack(0x10, 0x00);
            break;

        case 0x11: // OTA_CHUNK
            uint16_t idx = buf[1] | (buf[2]<<8);
            esp_ota_write(ota_handle, &buf[3], len - 3);
            send_ack(0x11, 0x00);
            break;

        case 0x12: // OTA_END
            esp_ota_end(ota_handle);
            esp_ota_set_boot_partition(update_partition);
            send_ack(0x12, 0x00);
            esp_restart();
            break;

        case 0x13: // OTA_ABORT
            esp_ota_abort(ota_handle);
            break;
    }
}
```

---

## Notas de implementación

- **No se verifica CRC por chunk** en esta versión: BLE garantiza integridad
  a nivel de enlace (CRC de capa 2). Si se quiere verificación adicional,
  añadir SHA-256 del binario completo en OTA_END.
- El ESP32 debe tener configuradas **dos particiones OTA** en `partitions.csv`.
- Con MTU=247 y chunks de 200 bytes, un binario de 1 MB requiere
  ~5120 chunks y tarda aprox. **90 segundos** (200 ms entre chunks para
  que el ESP32 pueda escribir en flash sin saturar la cola BLE).
  La app espera ACK de cada chunk con timeout de 8 s.