// lib/shared/models/gait_phase.dart
//
// Fase aproximada del ciclo de la marcha (ver memoria, Capítulo 4,
// "El ciclo de la marcha y su relevancia para los datos recogidos").
// Es una señal DERIVADA, calculada en vivo a partir de los 12 FSR, pensada
// para visualización (badge en el dashboard, franjas de color en el
// gráfico de grabación) y para enriquecer los datos exportados con algo
// más que presión/temperatura en crudo.
//
// No sustituye al detector de pasos ya validado (_detectSteps en
// sensor_provider.dart), que sigue siendo la única fuente que escribe en
// el historial persistente de pasos.

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum GaitPhase { swing, initialContact, midStance, terminalStance }

extension GaitPhaseX on GaitPhase {
  String get label => switch (this) {
        GaitPhase.swing => 'Oscilación',
        GaitPhase.initialContact => 'Contacto inicial',
        GaitPhase.midStance => 'Apoyo medio',
        GaitPhase.terminalStance => 'Despegue',
      };

  /// Identificador estable para guardar en la base de datos / CSV
  /// exportado -- no traducir, no depende del idioma de la interfaz.
  String get csvCode => switch (this) {
        GaitPhase.swing => 'swing',
        GaitPhase.initialContact => 'initial_contact',
        GaitPhase.midStance => 'mid_stance',
        GaitPhase.terminalStance => 'terminal_stance',
      };

  Color get color => switch (this) {
        GaitPhase.swing => AppColors.accent,
        GaitPhase.initialContact => AppColors.danger,
        GaitPhase.midStance => AppColors.success,
        GaitPhase.terminalStance => AppColors.warning,
      };

  static GaitPhase fromCsvCode(String code) {
    return switch (code) {
      'initial_contact' => GaitPhase.initialContact,
      'mid_stance' => GaitPhase.midStance,
      'terminal_stance' => GaitPhase.terminalStance,
      _ => GaitPhase.swing,
    };
  }
}

/// Clasifica cada lectura de los 12 FSR en una fase aproximada del ciclo
/// de la marcha. Mismo principio de diseño que el detector de pasos: en
/// vez de un umbral absoluto (los FSR de bajo coste no parten de un
/// reposo en 0, ver sensor_provider.dart), se compara la carga actual
/// contra un pico reciente con decaimiento -- así se adapta sola al nivel
/// de reposo/precarga de cada sesión concreta, en vez de asumir uno fijo.
class GaitPhaseClassifier {
  // Índices de FSR por zona -- deben coincidir con `centerOfPressure` en
  // sensor_data.dart (mismo orden de los 12 sensores reales).
  static const List<int> _heelIdx = [9, 10, 11];
  static const List<int> _foreIdx = [0, 1, 2, 3, 4, 5, 6];

  static const double _peakDecayPerSample = 0.985;
  static const double _swingRatio = 0.35;
  static const double _dominanceRatio = 1.3;
  static const double _minPeak = 0.05;

  double _recentPeak = 0.25;

  double _maxAt(List<double> fsr, List<int> idx) {
    double m = 0;
    for (final i in idx) {
      if (i < fsr.length && fsr[i] > m) m = fsr[i];
    }
    return m;
  }

  GaitPhase classify(List<double> fsr) {
    if (fsr.isEmpty) return GaitPhase.swing;

    final heel = _maxAt(fsr, _heelIdx);
    final fore = _maxAt(fsr, _foreIdx);
    final total = fsr.reduce((a, b) => a > b ? a : b);

    _recentPeak =
        total > _recentPeak ? total : _recentPeak * _peakDecayPerSample;
    if (_recentPeak < _minPeak) _recentPeak = _minPeak;

    final loadRatio = total / _recentPeak;
    if (loadRatio < _swingRatio) return GaitPhase.swing;

    if (heel > fore * _dominanceRatio) return GaitPhase.initialContact;
    if (fore > heel * _dominanceRatio) return GaitPhase.terminalStance;
    return GaitPhase.midStance;
  }

  /// Reinicia el pico de referencia -- llamar en cada (re)conexión BLE
  /// genuina o al arrancar una grabación en modo simulado, igual que
  /// `_lastPeak` en el detector de pasos.
  void reset() {
    _recentPeak = 0.25;
  }
}
