// lib/core/utils/sensor_calibration.dart
//
// ÚNICO sitio con las constantes físicas de calibración de los sensores.
// El firmware manda todo RAW (registros del LSM9DS1, cuentas ADC del
// ADS1115) sin convertir — la conversión a unidades físicas vive aquí a
// propósito, para poder recalibrar sensores sin reflashear el ESP32-S3.
//
// Cada constante está comentada con la constante de firmware que refleja;
// si en el futuro cambia algo en firmware (ej. la ganancia PGA del
// ADS1115, o el rango de escala completa del IMU), esta es la única
// contrapartida que hay que actualizar aquí.

import 'dart:math';

class SensorCalibration {
  SensorCalibration._();

  // ── IMU (LSM9DS1) — espeja las constantes eliminadas de imu_driver.c ──
  // Gyro ±245 dps (CTRL_REG1_G = 0x60), Accel ±2g (CTRL_REG6_XL = 0x60).
  static const double kGyroDpsPerLsb = 0.00875;
  static const double kAccelGPerLsb = 0.000061;
  static const double kMagGaussPerLsb = 0.00014;

  // ── ADS1115 — espeja FSR_UV_PER_LSB[ADS1115_FSR_4096MV] en ads1115.c ──
  // Válido mientras el firmware siga usando la ganancia ADS1115_FSR_4096MV
  // para los 4 chips (ver sensor_manager.c, adc_cfg.fsr).
  static const double kAdsUvPerLsb = 125.0;

  // ── FSR — espeja FSR_V_REF / FSR_PRESSURE_MAX_G en sensor_manager.c ──
  static const double kFsrVRef = 3.3;
  static const double kFsrPressureMaxG = 10000.0; // fondo de escala real: 10 kg

  // ── NTC — espeja NTC_V_REF/NTC_R_REF_OHM y la fórmula beta en ads1115.c ──
  static const double kNtcVRef = 3.3;
  static const double kNtcRRefOhm = 10000.0;
  static const double kNtcBeta = 3950.0;
  static const double kNtcT0Kelvin = 298.15;
  static const double kNtcR0Ohm = 10000.0;

  // ── IMU: raw -> unidades físicas ──────────────────────────────────────
  static double accelG(int raw) => raw * kAccelGPerLsb;
  static double gyroDps(int raw) => raw * kGyroDpsPerLsb;
  static double magGauss(int raw) => raw * kMagGaussPerLsb;

  // ── ADS1115: raw -> voltaje (mismo cálculo que ads1115_raw_to_voltage) ──
  static double rawToVoltage(int raw) => raw * kAdsUvPerLsb / 1e6;

  // ── FSR: voltaje -> gramos (mismo cálculo que ads1115_voltage_to_grams) ──
  static double voltageToGrams(double voltage) {
    if (voltage <= 0.0) return 0.0;
    if (voltage >= kFsrVRef) return kFsrPressureMaxG;
    return voltage / kFsrVRef * kFsrPressureMaxG;
  }

  // ── NTC: voltaje -> celsius (mismo cálculo que ads1115_ntc_to_celsius) ──
  static double voltageToCelsius(double voltage) {
    if (voltage <= 0.0 || voltage >= kNtcVRef) return -273.15;

    final rNtc = kNtcRRefOhm * voltage / (kNtcVRef - voltage);
    final tempK = 1.0 / (1.0 / kNtcT0Kelvin + (1.0 / kNtcBeta) * log(rNtc / kNtcR0Ohm));
    return tempK - 273.15;
  }

  // ── Atajos raw -> unidad final, para los sensores del ADS1115 ─────────
  static double rawToGrams(int raw) => voltageToGrams(rawToVoltage(raw));
  static double rawToCelsius(int raw) => voltageToCelsius(rawToVoltage(raw));
}
