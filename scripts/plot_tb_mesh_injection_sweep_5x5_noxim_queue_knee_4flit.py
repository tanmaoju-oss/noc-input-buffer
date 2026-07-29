#!/usr/bin/env python3

"""Plot the WSL 4-flit 5x5 queue-knee injection/latency result."""

# Modify add dependency-light Graphviz latency plot generator for WSL results, Michael Tan, 20260714

from __future__ import annotations

import pathlib
import subprocess
import tempfile


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TOP = "tb_mesh_injection_sweep_5x5_noxim_queue_knee_4flit"
RESULT_DIR = REPO_ROOT / "vivado_sim_wsl" / f"{TOP}_sim"
RESULT_FILE = RESULT_DIR / "injection_latency_results.txt"
FULL_OUTPUT_FILE = RESULT_DIR / "injection_latency_curve_full.png"
ZOOM_OUTPUT_FILE = RESULT_DIR / "injection_latency_curve_knee_zoom.png"

CANVAS_WIDTH_PT = 792.0
CANVAS_HEIGHT_PT = 518.4
PLOT_LEFT = 82.0
PLOT_RIGHT = 766.0
PLOT_BOTTOM = 66.0
PLOT_TOP = 476.0


def load_points() -> list[tuple[float, float]]:
    lines = RESULT_FILE.read_text(encoding="utf-8").splitlines()
    points: list[tuple[float, float]] = []
    for line in lines[1:]:
        fields = line.split()
        if not fields:
            continue
        injection_rate = float(fields[1])
        latency_cycles = int(fields[12]) / 1000.0
        points.append((injection_rate, latency_cycles))

    if len(points) != 20:
        raise RuntimeError(f"expected 20 data points, found {len(points)}")
    return points


def x_position(rate: float, x_max: float) -> float:
    return PLOT_LEFT + (rate / x_max) * (PLOT_RIGHT - PLOT_LEFT)


def y_position(latency: float, y_max: float) -> float:
    return PLOT_BOTTOM + (latency / y_max) * (PLOT_TOP - PLOT_BOTTOM)


def build_dot(
    points: list[tuple[float, float]], title: str, x_max: float, y_max: float
) -> str:
    dot: list[str] = [
        "graph latency_curve {",
        '  graph [layout=neato, overlap=true, splines=line, outputorder=edgesfirst, '
        'bgcolor="white", margin=0, pad=0, size="11,7.2!", ratio=fill, dpi=100];',
        '  node [fontname="DejaVu Sans", color="#333333"];',
        '  edge [fontname="DejaVu Sans"];',
        f'  anchor_min [pos="0,0!", shape=point, width=0.01, style=invis];',
        f'  anchor_max [pos="{CANVAS_WIDTH_PT},{CANVAS_HEIGHT_PT}!", shape=point, width=0.01, style=invis];',
    ]

    for index in range(9):
        tick_value = index * y_max / 8.0
        tick_label = int(tick_value + 0.5)
        y = y_position(tick_value, y_max)
        dot.append(
            f'  ygrid_l_{index} [pos="{PLOT_LEFT},{y}!", shape=point, width=0.01, style=invis];'
        )
        dot.append(
            f'  ygrid_r_{index} [pos="{PLOT_RIGHT},{y}!", shape=point, width=0.01, style=invis];'
        )
        color = "#333333" if index in (0, 8) else "#dddddd"
        width = 1.3 if index in (0, 8) else 0.6
        dot.append(
            f'  ygrid_l_{index} -- ygrid_r_{index} [color="{color}", penwidth={width}];'
        )
        dot.append(
            f'  ylabel_{index} [pos="{PLOT_LEFT - 22},{y}!", shape=plaintext, '
            f'label="{tick_label}", fontsize=10];'
        )

    for index in range(11):
        rate = index * x_max / 10.0
        x = x_position(rate, x_max)
        dot.append(
            f'  xgrid_b_{index} [pos="{x},{PLOT_BOTTOM}!", shape=point, width=0.01, style=invis];'
        )
        dot.append(
            f'  xgrid_t_{index} [pos="{x},{PLOT_TOP}!", shape=point, width=0.01, style=invis];'
        )
        color = "#333333" if index in (0, 10) else "#dddddd"
        width = 1.3 if index in (0, 10) else 0.6
        dot.append(
            f'  xgrid_b_{index} -- xgrid_t_{index} [color="{color}", penwidth={width}];'
        )
        dot.append(
            f'  xlabel_{index} [pos="{x},{PLOT_BOTTOM - 22}!", shape=plaintext, '
            f'label="{rate:.2f}", fontsize=10];'
        )

    dot.extend(
        [
            f'  title [pos="{(PLOT_LEFT + PLOT_RIGHT) / 2},{CANVAS_HEIGHT_PT - 17}!", '
            f'shape=plaintext, label="{title}", '
            'fontname="DejaVu Sans Bold", fontsize=17];',
            f'  x_axis_label [pos="{(PLOT_LEFT + PLOT_RIGHT) / 2},18!", shape=plaintext, '
            'label="Injection rate (packet/cycle/node)", fontsize=13];',
            f'  y_axis_label [pos="19,{(PLOT_BOTTOM + PLOT_TOP) / 2}!", shape=plaintext, '
            'label="Average packet\\nlatency (cycles)", fontsize=11];',
        ]
    )

    for index, (rate, latency) in enumerate(points):
        dot.append(
            f'  point_{index} [pos="{x_position(rate, x_max)},{y_position(latency, y_max)}!", '
            'shape=circle, fixedsize=true, width=0.075, height=0.075, label="", '
            'color="#2166c2", fillcolor="#2166c2", style=filled, penwidth=0.8];'
        )
        if index:
            dot.append(
                f'  point_{index - 1} -- point_{index} [color="#2166c2", penwidth=2.2];'
            )

    dot.append("}")
    return "\n".join(dot) + "\n"


def render_plot(
    points: list[tuple[float, float]],
    output_file: pathlib.Path,
    title: str,
    x_max: float,
    y_max: float,
) -> None:
    dot_text = build_dot(points, title, x_max, y_max)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".dot", encoding="utf-8", dir=RESULT_DIR, delete=False
    ) as dot_file:
        dot_file.write(dot_text)
        dot_path = pathlib.Path(dot_file.name)

    try:
        subprocess.run(
            ["neato", "-n2", "-Tpng", "-Gdpi=100", f"-o{output_file}", str(dot_path)],
            check=True,
        )
    finally:
        dot_path.unlink(missing_ok=True)

    print(f"points={len(points)} output={output_file}")


def main() -> None:
    points = load_points()
    zoom_points = [point for point in points if point[0] <= 0.16]
    if len(zoom_points) != 9:
        raise RuntimeError(f"expected 9 zoom data points, found {len(zoom_points)}")

    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    render_plot(
        points,
        FULL_OUTPUT_FILE,
        "5x5 Queue Knee, Packet = 4 Flits (WSL Vivado 2025.2)",
        0.5,
        3000.0,
    )
    render_plot(
        zoom_points,
        ZOOM_OUTPUT_FILE,
        "5x5 Queue Knee Zoom, Packet = 4 Flits (WSL Vivado 2025.2)",
        0.16,
        500.0,
    )


if __name__ == "__main__":
    main()
