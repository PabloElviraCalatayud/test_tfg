// lib/features/dashboard/presentation/widgets/heat_map_widget.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/svg_path_utils.dart';
import '../../../../shared/providers/sensor_provider.dart';

// ─── Posiciones normalizadas de los 4 termistores ─────────────────────────────
// x: 0=medial, 1=lateral  |  y: 0=talón, 1=dedos
const List<(double, double)> _thermistorPositions = [
  (0.46, 0.20), // Talón
  (0.44, 0.50), // Arco
  (0.46, 0.74), // Metatarso
  (0.46, 0.92), // Dedos
];

const List<String> _thermistorLabels = [
  'Talón', 'Arco', 'Metatarso', 'Dedos',
];

// Cada termistor cae en la misma zona anatomica que un grupo de sensores
// FSR del mapa de presion (ver _fsrPositions en pressure_map_widget.dart:
// dedos=0-2, metatarsos=3-6, arco=7-8, talon=9-11). Se usa para poder
// mostrar, al tocar un termistor, que % del peso total se lleva esa
// misma zona -- no solo la temperatura.
const List<List<int>> _thermistorZoneFsrIndices = [
  [9, 10, 11], // Talón
  [7, 8], // Arco
  [3, 4, 5, 6], // Metatarso
  [0, 1, 2], // Dedos
];

Color _thermalColor(double norm) {
  // norm: 0.0 (frío) → 1.0 (caliente)
  const colors = AppColors.thermalGradient;
  final t      = norm.clamp(0.0, 1.0);
  final scaled = t * (colors.length - 1);
  final idx    = scaled.floor().clamp(0, colors.length - 2);
  return Color.lerp(colors[idx], colors[idx + 1], scaled - idx)!;
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class HeatMapWidget extends ConsumerStatefulWidget {
  const HeatMapWidget({super.key});
  @override
  ConsumerState<HeatMapWidget> createState() => _HeatMapWidgetState();
}

class _HeatMapWidgetState extends ConsumerState<HeatMapWidget> {
  // Igual que en PressureMapWidget: antes esto era un OverlayEntry
  // posicionado a mano con context.findRenderObject()+localToGlobal sobre
  // el RenderBox de TODA la tarjeta (no el del mapa), asi que el aviso
  // podia salir desplazado fuera de sitio y desaparecer a los 2s sin que
  // se llegase a ver. Un panel fijo en el layout no puede des-posicionarse.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data  = ref.watch(sensorDataProvider);
    final temps = data.temperature;
    final avg   = data.avgTemperature;
    final tMin  = data.minTemperature;
    final tMax  = data.maxTemperature;

    // Normalized average for color
    final avgNorm = (tMax - tMin) < 0.01
        ? 0.5
        : ((avg - tMin) / (tMax - tMin)).clamp(0.0, 1.0);
    final avgColor = _thermalColor(avgNorm);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MAPA TÉRMICO',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: avgColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border:
                  Border.all(color: avgColor.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.thermostat, size: 12, color: avgColor),
                    const SizedBox(width: 4),
                    Text(
                      'Media: ${avg.toStringAsFixed(1)} °C',
                      style: TextStyle(
                          color: avgColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Mapa de calor ────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 0.52,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return Stack(
                children: [
                  // IDW heat map con blur suavizador
                  CustomPaint(
                    size: Size(w, h),
                    painter: _ThermalPainter(
                      temps: temps,
                      tMin: tMin,
                      tMax: tMax,
                    ),
                  ),

                  // Zonas táctiles por sensor (encima del mapa)
                  for (int i = 0;
                  i < _thermistorPositions.length &&
                      i < temps.length;
                  i++)
                    Positioned(
                      left:
                      _thermistorPositions[i].$1 * w - 22,
                      top: (1 - _thermistorPositions[i].$2) *
                          h -
                          22,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = i),
                        child: const SizedBox(
                            width: 44, height: 44),
                      ),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: 8),

          // ── Leyenda de temperatura ────────────────────────────────────
          Row(
            children: [
              Text('${tMin.toStringAsFixed(1)}°',
                  style: const TextStyle(
                      color: AppColors.textDisabled, fontSize: 9)),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: AppColors.thermalGradient),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text('${tMax.toStringAsFixed(1)}°',
                  style: const TextStyle(
                      color: AppColors.textDisabled, fontSize: 9)),
            ],
          ),
          const SizedBox(height: 10),
          _SelectedReadout(
            label: _selected == null
                ? null
                : '${_selected! + 1} · ${_thermistorLabels[_selected!]}',
            temp: _selected == null || _selected! >= temps.length
                ? null
                : temps[_selected!],
            zonePercent: _selected == null
                ? null
                : _thermistorZoneFsrIndices[_selected!].fold<double>(
                    0,
                    (s, idx) => idx < data.relativePercent.length
                        ? s + data.relativePercent[idx]
                        : s,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Panel fijo (siempre en el mismo sitio del layout) con el ultimo
/// termistor tocado: temperatura y % de peso que soporta esa misma zona.
class _SelectedReadout extends StatelessWidget {
  final String? label;
  final double? temp;
  final double? zonePercent;
  const _SelectedReadout({
    required this.label,
    required this.temp,
    required this.zonePercent,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = label != null && temp != null && zonePercent != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasSelection ? AppColors.accent.withOpacity(0.3) : AppColors.divider,
        ),
      ),
      child: hasSelection
          ? Row(
              children: [
                Text(label!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const Spacer(),
                Text('${temp!.toStringAsFixed(1)} °C',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Text('${zonePercent!.toStringAsFixed(0)}% del peso',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            )
          : const Text(
              'Ningún termistor seleccionado',
              style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
            ),
    );
  }
}

// ─── Painter — IDW + blur ────────────────────────────────────────────────────

class _ThermalPainter extends CustomPainter {
  final List<double> temps;
  final double tMin, tMax;

  const _ThermalPainter({
    required this.temps,
    required this.tMin,
    required this.tMax,
  });

  // ── IDW (Inverse Distance Weighting) ───────────────────────────────────────
  // Interpola el valor normalizado (0-1) en el punto (nx, ny) del espacio
  // sensor ponderando la influencia de cada termistor por 1/dist².
  double _idw(double nx, double ny) {
    if (temps.isEmpty) return 0.5;
    final range = tMax - tMin;
    if (range < 0.01) return 0.5; // todos iguales → punto medio

    double totalW = 0;
    double sum    = 0;

    for (int i = 0;
    i < _thermistorPositions.length && i < temps.length;
    i++) {
      final (sx, sy) = _thermistorPositions[i];
      final dx   = nx - sx;
      final dy   = ny - sy;
      final dist2 = dx * dx + dy * dy;

      // Si el punto coincide con un sensor, devuelve su valor directamente
      if (dist2 < 1e-8) {
        return ((temps[i] - tMin) / range).clamp(0.0, 1.0);
      }

      // Ponderación: inverse square (p=2) — equilibrio entre suavidad
      // y localización de cada sensor. Valores más altos (p=3) crearían
      // zonas más nítidas pero con artefactos entre sensores escasos.
      final w = 1.0 / dist2;
      totalW += w;
      sum    += w * (temps[i] - tMin) / range;
    }

    return totalW > 0 ? (sum / totalW).clamp(0.0, 1.0) : 0.5;
  }

  // ── Grid de celdas coloreadas ─────────────────────────────────────────────
  // Resolución: 28 × 56 = 1568 celdas.
  // Suficiente para suavidad visual al aplicar blur posterior.
  void _drawIDWGrid(Canvas canvas, Size size) {
    const cols = 28;
    const rows = 56;
    final cellW = size.width  / cols;
    final cellH = size.height / rows;

    for (int col = 0; col < cols; col++) {
      for (int row = 0; row < rows; row++) {
        // Centro de la celda en espacio sensor (y=0 talón, y=1 dedos)
        final nx = (col + 0.5) / cols;
        final ny = 1.0 - (row + 0.5) / rows; // flip canvas→sensor

        final norm  = _idw(nx, ny);
        final color = _thermalColor(norm);

        // +0.5 en ancho/alto para evitar líneas blancas entre celdas
        canvas.drawRect(
          Rect.fromLTWH(
              col * cellW, row * cellH, cellW + 0.5, cellH + 0.5),
          Paint()..color = color.withOpacity(0.92),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final foot = SvgPathUtils.buildFootPath(size);

    // 1. Fondo oscuro del pie
    canvas.drawPath(
      foot,
      Paint()..color = const Color(0xFF080810),
    );

    // 2. Mapa IDW con blur gaussiano
    //    Secuencia: clipPath → saveLayer(blur) → grid → restore(aplica blur) → restore(clip)
    canvas.save();
    canvas.clipPath(foot);

    // El blur (σ=12) suaviza la transición entre celdas del grid,
    // eliminando el efecto "píxelado" y creando gradientes continuos.
    // Se aplica DESPUÉS de dibujar el grid (al hacer restore del saveLayer).
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..imageFilter =
        ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    );

    _drawIDWGrid(canvas, size);

    canvas.restore(); // ← aquí se aplica el blur al grid

    // 3. Dots de los sensores (nítidos, encima del blur, aún clipeados)
    for (int i = 0;
    i < _thermistorPositions.length && i < temps.length;
    i++) {
      final (nx, ny) = _thermistorPositions[i];
      final px   = nx * size.width;
      final py   = (1 - ny) * size.height;
      final norm = (tMax - tMin) < 0.01
          ? 0.5
          : ((temps[i] - tMin) / (tMax - tMin)).clamp(0.0, 1.0);
      final color = _thermalColor(norm);

      // Halo blanco para visibilidad sobre cualquier color de fondo
      canvas.drawCircle(
        Offset(px, py),
        6.5,
        Paint()..color = Colors.white.withOpacity(0.55),
      );
      // Punto coloreado
      canvas.drawCircle(
        Offset(px, py),
        5,
        Paint()..color = color,
      );

      // Numero de nodo (1-4), para poder identificar cada termistor
      // fisico -- mismo criterio que los 12 nodos FSR del mapa de presion.
      _drawNodeNumber(canvas, Offset(px, py), i + 1);
    }

    canvas.restore(); // ← quita el clip

    // 4. Contorno del pie encima de todo
    canvas.drawPath(
      foot,
      Paint()
        ..color      = const Color(0xFF8B7355).withOpacity(0.55)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawNodeNumber(Canvas canvas, Offset pos, int number) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Numero desplazado justo encima del punto para no taparlo -- los
    // puntos termicos son mas pequenos que los blobs de presion y no hay
    // sitio para centrar el texto encima sin que quede ilegible.
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height + 6));
  }

  @override
  bool shouldRepaint(_ThermalPainter old) =>
      old.temps != temps ||
          old.tMin  != tMin  ||
          old.tMax  != tMax;
}