#!/usr/bin/env python3

"""Plot the WSL four-VC 4-flit 5x5 queue-knee injection/throughput result."""

# Modify add dependency-light Graphviz four-VC fixed-window throughput curve, Michael Tan, 20260715

from __future__ import annotations

import pathlib
import subprocess
import tempfile


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
TOP = "tb_mesh_throughput_sweep_5x5_noxim_queue_knee_4flit_4vc"
RESULT_DIR = REPO_ROOT / "vivado_sim_wsl" / f"{TOP}_sim"
RESULT_FILE = RESULT_DIR / "throughput_results.txt"
OUTPUT_FILE = RESULT_DIR / "throughput_curve.png"  # Modify use the independent throughput output name, Michael Tan, 20260715
PACKET_OUTPUT_FILE = RESULT_DIR / "throughput_curve_packet.png"  # Modify add packet-unit throughput output without replacing the flit-unit curve, Michael Tan, 20260724

CANVAS_WIDTH_PT = 792.0
CANVAS_HEIGHT_PT = 518.4
PLOT_LEFT = 82.0
PLOT_RIGHT = 766.0
PLOT_BOTTOM = 66.0
PLOT_TOP = 476.0


def load_points(throughput_column: int) -> list[tuple[float, float]]:  # Modify select the recorded flit or packet throughput column, Michael Tan, 20260724
    lines = RESULT_FILE.read_text(encoding="utf-8").splitlines()
    points: list[tuple[float, float]] = []
    for line in lines[1:]:
        fields = line.split()
        if not fields:
            continue
        injection_rate = float(fields[1])
        delivered_throughput = int(fields[throughput_column]) / 1_000_000.0
        points.append((injection_rate, delivered_throughput))  # Modify reuse the fixed-window normalized throughput selected by unit, Michael Tan, 20260724

    if len(points) != 20:
        raise RuntimeError(f"expected 20 data points, found {len(points)}")
    return points


def x_position(rate: float, x_max: float) -> float:
    return PLOT_LEFT + (rate / x_max) * (PLOT_RIGHT - PLOT_LEFT)


def y_position(throughput: float, y_max: float) -> float:
    return PLOT_BOTTOM + (throughput / y_max) * (PLOT_TOP - PLOT_BOTTOM)


def build_dot(
    points: list[tuple[float, float]],
    title: str,
    x_max: float,
    y_max: float,
    x_divisions: int,
    y_divisions: int,
    y_axis_label: str,  # Modify support explicit flit-unit and packet-unit y-axis labels, Michael Tan, 20260724
    y_tick_decimals: int,  # Modify keep 0.02 packet-throughput ticks distinct, Michael Tan, 20260724
    y_axis_label_x: float,
    y_axis_label_y: float,  # Modify allow the packet-unit label to avoid the denser tick labels, Michael Tan, 20260724
) -> str:
    dot: list[str] = [
        "graph throughput_curve {",
        '  graph [layout=neato, overlap=true, splines=line, outputorder=edgesfirst, '
        'bgcolor="white", margin=0, pad=0, size="11,7.2!", ratio=fill, dpi=100];',
        '  node [fontname="DejaVu Sans", color="#333333"];',
        '  edge [fontname="DejaVu Sans"];',
        f'  anchor_min [pos="0,0!", shape=point, width=0.01, style=invis];',
        f'  anchor_max [pos="{CANVAS_WIDTH_PT},{CANVAS_HEIGHT_PT}!", shape=point, width=0.01, style=invis];',
    ]

    for index in range(y_divisions + 1):
        tick_value = index * y_max / y_divisions
        tick_label = f"{tick_value:.{y_tick_decimals}f}"  # Modify format ticks according to the selected throughput scale, Michael Tan, 20260724
        y = y_position(tick_value, y_max)
        dot.append(
            f'  ygrid_l_{index} [pos="{PLOT_LEFT},{y}!", shape=point, width=0.01, style=invis];'
        )
        dot.append(
            f'  ygrid_r_{index} [pos="{PLOT_RIGHT},{y}!", shape=point, width=0.01, style=invis];'
        )
        color = "#333333" if index in (0, y_divisions) else "#dddddd"
        width = 1.3 if index in (0, y_divisions) else 0.6
        dot.append(
            f'  ygrid_l_{index} -- ygrid_r_{index} [color="{color}", penwidth={width}];'
        )
        dot.append(
            f'  ylabel_{index} [pos="{PLOT_LEFT - 22},{y}!", shape=plaintext, '
            f'label="{tick_label}", fontsize=10];'
        )

    for index in range(x_divisions + 1):
        rate = index * x_max / x_divisions
        x = x_position(rate, x_max)
        dot.append(
            f'  xgrid_b_{index} [pos="{x},{PLOT_BOTTOM}!", shape=point, width=0.01, style=invis];'
        )
        dot.append(
            f'  xgrid_t_{index} [pos="{x},{PLOT_TOP}!", shape=point, width=0.01, style=invis];'
        )
        color = "#333333" if index in (0, x_divisions) else "#dddddd"
        width = 1.3 if index in (0, x_divisions) else 0.6
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
            f'  y_axis_label [pos="{y_axis_label_x},{y_axis_label_y}!", shape=plaintext, '
            f'label="{y_axis_label}", fontsize=11];',  # Modify label each curve with its actual throughput unit, Michael Tan, 20260724
        ]
    )

    for index, (rate, throughput) in enumerate(points):
        dot.append(
            f'  point_{index} [pos="{x_position(rate, x_max)},{y_position(throughput, y_max)}!", '
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
    x_divisions: int,
    y_divisions: int,
    y_axis_label: str,  # Modify pass the selected throughput unit into the plot, Michael Tan, 20260724
    y_tick_decimals: int,  # Modify pass unit-appropriate y-axis precision, Michael Tan, 20260724
    y_axis_label_x: float,
    y_axis_label_y: float,  # Modify pass the selected y-axis label position, Michael Tan, 20260724
) -> None:
    dot_text = build_dot(
        points,
        title,
        x_max,
        y_max,
        x_divisions,
        y_divisions,
        y_axis_label,
        y_tick_decimals,
        y_axis_label_x,
        y_axis_label_y,
    )  # Modify render either flit-unit or packet-unit throughput, Michael Tan, 20260724
    # Modify render normalized throughput with fixed decimal tick spacing, Michael Tan, 20260715
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
    flit_points = load_points(14)  # Modify read normalized flit throughput from the verified result table, Michael Tan, 20260724
    packet_points = load_points(15)  # Modify read normalized packet throughput from the verified result table, Michael Tan, 20260724

    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    render_plot(
        flit_points,
        OUTPUT_FILE,
        "5x5 Delivered Throughput, Packet = 4 Flits, 4 VCs (WSL Vivado 2025.2)",
        0.5,
        0.6,
        10,
        6,
        "Delivered throughput\\n(flit/cycle/node)",
        1,
        19,
        (PLOT_BOTTOM + PLOT_TOP) / 2,
        # Modify show linear growth followed by the delivered-throughput plateau, Michael Tan, 20260715
    )
    render_plot(
        packet_points,
        PACKET_OUTPUT_FILE,
        "5x5 Packet Throughput, Packet = 4 Flits, 4 VCs (WSL Vivado 2025.2)",
        0.5,
        0.16,
        10,
        8,
        "Delivered packet throughput (packet/cycle/node)",
        2,
        PLOT_LEFT + 125,
        PLOT_TOP - 18,
        # Modify align both axes to packet/cycle/node and place the unit label clear of dense y ticks, Michael Tan, 20260724
    )


if __name__ == "__main__":
    main()
