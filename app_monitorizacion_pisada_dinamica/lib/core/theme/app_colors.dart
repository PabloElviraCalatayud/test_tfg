import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color bgPrimary = Color(0xFF0D0D0F);
  static const Color bgSurface = Color(0xFF1A1A1F);
  static const Color bgCard = Color(0xFF222228);
  static const Color bgCardAlt = Color(0xFF2A2A32);

  // Primary accent — Garmin cyan/blue
  static const Color accent = Color(0xFF00B4D8);
  static const Color accentDim = Color(0xFF0077A8);

  // Success / goal complete
  static const Color success = Color(0xFF2ECC71);
  static const Color successDim = Color(0xFF1A7A44);

  // Warning
  static const Color warning = Color(0xFFFF6B35);

  // Error / high pressure
  static const Color danger = Color(0xFFE63946);

  // Text
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF9090A0);
  static const Color textDisabled = Color(0xFF555565);

  // Divider
  static const Color divider = Color(0xFF2E2E38);

  // Pressure map gradient. Antes era un arcoíris tipo "jet" (azul-verde-
  // amarillo-rojo con tonos primarios muy saturados), un tipo de gradiente
  // que en visualización de datos se evita precisamente porque no es
  // perceptualmente uniforme (crea bandas/fronteras falsas) y resulta
  // visualmente chillón. Esta progresión es monótona en intensidad
  // percibida (frío/calma -> cálido/intenso) y usa los mismos tonos ya
  // presentes en el resto de la app (accent, success, warning, danger),
  // así que el mapa de presión se lee con el mismo lenguaje de color que
  // el resto de la interfaz en vez de uno ajeno.
  static const List<Color> pressureGradient = [
    Color(0xFF12263A), // sin apenas presión
    Color(0xFF1B4B91),
    Color(0xFF1C8C9C), // cerca de accent
    Color(0xFF4FAE64), // cerca de success
    Color(0xFFE0B23D),
    Color(0xFFE8783C), // cerca de warning
    Color(0xFFD64550), // max presión, cerca de danger
  ];

  // Heat map gradient (thermal)
  static const List<Color> thermalGradient = [
    Color(0xFF000080), // cold
    Color(0xFF0000FF),
    Color(0xFF00FFFF),
    Color(0xFF00FF00),
    Color(0xFFFFFF00),
    Color(0xFFFF8800),
    Color(0xFFDC143C), // hot
  ];

  // BLE states — color + shape icon for accessibility
  static const Color bleDisconnected = Color(0xFFE63946);
  static const Color bleConnecting = Color(0xFFFFB703);
  static const Color bleConnected = Color(0xFF2ECC71);
}