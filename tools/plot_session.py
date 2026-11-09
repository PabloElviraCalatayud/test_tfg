#!/usr/bin/env python3
"""
plot_session.py
================

Genera gráficas de presión, temperatura y fases del ciclo de marcha a
partir de un CSV exportado desde la app (pestaña "Sesiones" -> icono de
compartir en una sesión grabada, ver ExportService en el código Dart).

Uso:
    pip install matplotlib
    python3 plot_session.py sesion.csv --outdir figuras

Sin dispositivo ni app a mano, para generar una sesión de ejemplo y sus
gráficas directamente (útil para probar el pipeline o tener una figura
de muestra mientras se recopila una sesión real):

    python3 plot_session.py --demo --outdir figuras

Columnas esperadas en el CSV (una fila por muestra, ver ExportService):
    t_ms, timestamp_iso,
    fsr_0..fsr_11, temp_0..temp_3,
    acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z, roll, pitch, yaw,
    gait_phase, step_edge

La única dependencia externa es matplotlib; todo lo demás (csv, lectura
de argumentos, generación del CSV de demostración) usa solo la librería
estándar de Python.
"""

from __future__ import annotations

import argparse
import csv
import math
import random
import sys
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")  # sin pantalla: solo generar ficheros PNG
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    from matplotlib.lines import Line2D
except ImportError:
    sys.exit("Falta matplotlib. Instálalo con: pip install matplotlib")


# ─────────────────────────────────────────────────────────────────────────
# Constantes compartidas con la app (deben coincidir con gait_phase.dart y
# sensor_data.dart -- si cambia el número/orden de los FSR o las fases de
# marcha en Dart, hay que actualizar esto también).
# ─────────────────────────────────────────────────────────────────────────

FSR_ZONES = {
    "Dedos (T1-T3)": [0, 1, 2],
    "Metatarsos (M1-M4)": [3, 4, 5, 6],
    "Arco (MF1-MF2)": [7, 8],
    "Talón (H1-H3)": [9, 10, 11],
}

PHASE_COLORS = {
    "initial_contact": "#E63946",
    "mid_stance": "#2ECC71",
    "terminal_stance": "#FF6B35",
    "swing": "#00B4D8",
}

PHASE_LABELS = {
    "initial_contact": "Contacto inicial",
    "mid_stance": "Apoyo medio",
    "terminal_stance": "Despegue",
    "swing": "Oscilación",
}


# ─────────────────────────────────────────────────────────────────────────
# Lectura del CSV
# ─────────────────────────────────────────────────────────────────────────

def read_csv(path: Path) -> list[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit(f"El CSV {path} no tiene filas de datos.")
    return rows


def to_seconds(rows: list[dict[str, str]]) -> list[float]:
    t0 = int(rows[0]["t_ms"])
    return [(int(r["t_ms"]) - t0) / 1000.0 for r in rows]


# ─────────────────────────────────────────────────────────────────────────
# Gráficas
# ─────────────────────────────────────────────────────────────────────────

def plot_pressure(rows, t, outpath: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 4.5))
    for zone, idxs in FSR_ZONES.items():
        vals = [max(float(r[f"fsr_{i}"]) for i in idxs) for r in rows]
        ax.plot(t, vals, label=zone, linewidth=1.6)

    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("Presión normalizada (0-1)")
    ax.set_title("Presión plantar por zona a lo largo del tiempo")
    ax.set_ylim(-0.02, 1.05)
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(outpath, dpi=160)
    plt.close(fig)


def plot_temperature(rows, t, outpath: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 4.5))
    labels = [
        "Termistor 1 (talón)",
        "Termistor 2 (arco)",
        "Termistor 3 (metatarso)",
        "Termistor 4 (dedos)",
    ]
    for i, label in enumerate(labels):
        vals = [float(r[f"temp_{i}"]) for r in rows]
        ax.plot(t, vals, label=label, linewidth=1.6)

    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("Temperatura (°C)")
    ax.set_title("Temperatura superficial por termistor a lo largo del tiempo")
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(outpath, dpi=160)
    plt.close(fig)


def plot_gait_cycle(rows, t, outpath: Path) -> None:
    fig, ax = plt.subplots(figsize=(11, 4.5))

    # Franjas de fondo por fase de marcha detectada.
    phases = [r["gait_phase"] for r in rows]
    start_i = 0
    for i in range(1, len(phases) + 1):
        if i == len(phases) or phases[i] != phases[start_i]:
            color = PHASE_COLORS.get(phases[start_i], "#888888")
            x_end = t[i - 1] if i < len(t) else t[-1]
            ax.axvspan(t[start_i], x_end, color=color, alpha=0.12, linewidth=0)
            start_i = i

    peak = [max(float(r[f"fsr_{j}"]) for j in range(12)) for r in rows]
    ax.plot(t, peak, color="#1a2433", linewidth=1.8)

    for i, r in enumerate(rows):
        if r.get("step_edge") == "1":
            ax.axvline(t[i], color="#E63946", linestyle="--", linewidth=1, alpha=0.6)

    handles = [
        mpatches.Patch(color=c, alpha=0.3, label=PHASE_LABELS[k])
        for k, c in PHASE_COLORS.items()
    ]
    handles.append(Line2D([0], [0], color="#1a2433", lw=1.8, label="Presión máxima (12 FSR)"))
    handles.append(Line2D([0], [0], color="#E63946", lw=1, ls="--", label="Contacto inicial detectado"))
    ax.legend(handles=handles, loc="upper right", fontsize=7.5, ncol=2)

    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("Presión normalizada (0-1)")
    ax.set_title("Fases del ciclo de marcha detectadas durante la sesión")
    ax.set_ylim(-0.02, 1.05)
    ax.grid(alpha=0.2)
    fig.tight_layout()
    fig.savefig(outpath, dpi=160)
    plt.close(fig)


# ─────────────────────────────────────────────────────────────────────────
# Generador de sesión de ejemplo (sin hardware ni app)
# ─────────────────────────────────────────────────────────────────────────
# Mismas curvas de carga talón/mediopié/antepié que GaitWalkSimulator en
# fake_data.dart y que figuras/ciclo_marcha.svg -- la app, este script y la
# memoria cuentan la misma historia del ciclo de marcha.

_KEYFRAMES = [
    (0, 0.90, 0.15, 0.00),
    (6, 0.80, 0.50, 0.10),
    (20, 0.25, 0.90, 0.30),
    (40, 0.10, 0.55, 0.75),
    (55, 0.00, 0.15, 0.90),
    (80, 0.00, 0.00, 0.00),
    (100, 0.90, 0.15, 0.00),
]


def _loads_at(pct: float) -> tuple[float, float, float]:
    for (ap, ah, am, af), (bp, bh, bm, bf) in zip(_KEYFRAMES, _KEYFRAMES[1:]):
        if ap <= pct <= bp:
            span = bp - ap
            tt = 0.0 if span == 0 else (pct - ap) / span
            return (ah + (bh - ah) * tt, am + (bm - am) * tt, af + (bf - af) * tt)
    return (0.0, 0.0, 0.0)


def _jitter(v: float, amount: float, rng: random.Random) -> float:
    return min(1.0, max(0.0, v + (rng.random() * 2 - 1) * amount))


def _classify_phase(fsr: list[float], state: dict) -> str:
    heel = max(fsr[9:12])
    fore = max(fsr[0:7])
    total = max(fsr)
    state["recent_peak"] = total if total > state["recent_peak"] else state["recent_peak"] * 0.985
    state["recent_peak"] = max(state["recent_peak"], 0.05)
    ratio = total / state["recent_peak"]
    if ratio < 0.35:
        return "swing"
    if heel > fore * 1.3:
        return "initial_contact"
    if fore > heel * 1.3:
        return "terminal_stance"
    return "mid_stance"


def generate_demo_csv(path: Path, duration_s: float = 12.0, hz: float = 20.0, seed: int = 7) -> None:
    rng = random.Random(seed)
    dt = 1.0 / hz
    n = int(duration_s * hz)

    cycle_pos = 0.0
    stride_s = 1.05
    temp = [30.5, 30.0, 32.5, 32.0]
    classifier_state = {"recent_peak": 0.25}
    last_phase = "swing"

    fieldnames = (
        ["t_ms", "timestamp_iso"]
        + [f"fsr_{i}" for i in range(12)]
        + [f"temp_{i}" for i in range(4)]
        + ["acc_x", "acc_y", "acc_z", "gyro_x", "gyro_y", "gyro_z",
           "roll", "pitch", "yaw", "gait_phase", "step_edge"]
    )

    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for i in range(n):
            t_ms = int(i * dt * 1000)
            cycle_pos += dt / stride_s
            if cycle_pos >= 1.0:
                cycle_pos -= 1.0
                stride_s = 0.95 + rng.random() * 0.2

            heel, mid, fore = _loads_at(cycle_pos * 100)

            fsr = [
                _jitter(fore * 0.85, 0.05, rng), _jitter(fore, 0.05, rng), _jitter(fore * 0.70, 0.05, rng),
                _jitter(fore, 0.06, rng), _jitter(fore * 0.95, 0.06, rng),
                _jitter(fore * 0.80, 0.06, rng), _jitter(fore * 0.60, 0.06, rng),
                _jitter(mid, 0.03, rng), _jitter(mid * 0.80, 0.03, rng),
                _jitter(heel * 0.90, 0.05, rng), _jitter(heel, 0.05, rng), _jitter(heel * 0.85, 0.05, rng),
            ]
            temp = [min(36.0, max(28.0, x + (rng.random() * 2 - 1) * 0.03)) for x in temp]

            impact = max(0.0, (heel - 0.6) * 5.0)
            sway = math.sin(cycle_pos * 2 * math.pi) * 6.0

            phase = _classify_phase(fsr, classifier_state)
            step_edge = 1 if (last_phase == "swing" and phase != "swing") else 0
            last_phase = phase

            row = {
                "t_ms": t_ms,
                "timestamp_iso": "",
                **{f"fsr_{j}": f"{fsr[j]:.4f}" for j in range(12)},
                **{f"temp_{j}": f"{temp[j]:.2f}" for j in range(4)},
                "acc_x": f"{sway * 0.2 + (rng.random() * 2 - 1) * 0.3:.4f}",
                "acc_y": f"{9.81 + impact + (rng.random() * 2 - 1) * 0.2:.4f}",
                "acc_z": f"{(rng.random() * 2 - 1) * 0.4:.4f}",
                "gyro_x": f"{sway + (rng.random() * 2 - 1) * 1.5:.4f}",
                "gyro_y": f"{(rng.random() * 2 - 1) * 2.0:.4f}",
                "gyro_z": f"{(rng.random() * 2 - 1) * 1.5:.4f}",
                "roll": f"{sway:.3f}",
                "pitch": f"{(fore - heel) * 6.0:.3f}",
                "yaw": f"{(rng.random() * 2 - 1) * 3.0:.3f}",
                "gait_phase": phase,
                "step_edge": step_edge,
            }
            writer.writerow(row)


# ─────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("csv_path", nargs="?", help="CSV exportado desde la app")
    parser.add_argument(
        "--demo", action="store_true",
        help="generar una sesión sintética de ejemplo en vez de leer un CSV",
    )
    parser.add_argument(
        "--outdir", default="figuras_sesion",
        help="carpeta de salida para las imágenes (y el CSV de demo)",
    )
    parser.add_argument("--prefix", default="", help="prefijo para los nombres de archivo generados")
    args = parser.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if args.demo:
        csv_path = outdir / "sesion_demo.csv"
        generate_demo_csv(csv_path)
        print(f"CSV de ejemplo generado en {csv_path}")
    elif args.csv_path:
        csv_path = Path(args.csv_path)
    else:
        parser.error("indica la ruta de un CSV, o usa --demo para generar uno de ejemplo")
        return

    rows = read_csv(csv_path)
    t = to_seconds(rows)

    prefix = f"{args.prefix}_" if args.prefix else ""
    plot_pressure(rows, t, outdir / f"{prefix}presion.png")
    plot_temperature(rows, t, outdir / f"{prefix}temperatura.png")
    plot_gait_cycle(rows, t, outdir / f"{prefix}ciclo_marcha.png")

    print(f"Gráficas generadas en {outdir}/")


if __name__ == "__main__":
    main()
