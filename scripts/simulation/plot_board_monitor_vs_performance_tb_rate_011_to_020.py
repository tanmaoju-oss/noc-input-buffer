#!/usr/bin/env python3

"""Render the completed 0.11-to-0.20 board-monitor/performance-TB comparison."""

# Modify add dependency-light Graphviz comparison plot for board-monitor and performance-TB results, Michael Tan, 20260908

from __future__ import annotations

import pathlib
import subprocess
import tempfile


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_FILE = REPO_ROOT / "file" / "仿真分析" / "板级监测模块与性能TB_011至020注入率对比.png"
ZOOM_OUTPUT_FILE = REPO_ROOT / "file" / "仿真分析" / "板级监测模块与性能TB_010至017注入率对比放大图.png"
LOW_RATE_OUTPUT_FILE = REPO_ROOT / "file" / "仿真分析" / "板级监测模块与性能TB_000至016注入率对比图.png"

BOARD_POINTS = [(0.11, 28.149), (0.12, 37.650), (0.13, 57.399), (0.14, 85.318), (0.15, 125.131), (0.16, 168.746), (0.17, 215.469), (0.18, 265.748), (0.19, 322.862), (0.20, 371.774)]
TB_POINTS = [(0.11, 26.188), (0.12, 33.039), (0.13, 53.955), (0.14, 86.165), (0.15, 150.556), (0.16, 182.250), (0.17, 219.955), (0.18, 252.220), (0.19, 334.278), (0.20, 401.387)]

WIDTH, HEIGHT = 576.0, 576.0
LEFT, RIGHT, BOTTOM, TOP = 78.0, 548.0, 76.0, 514.0 #Modify use a near-square canvas and taller latency axis for comparison readability, Michael Tan, 20260908
X_MIN, X_MAX, Y_MAX = 0.10, 0.20, 450.0


def x_pos(rate: float) -> float:
    return LEFT + (rate - X_MIN) / (X_MAX - X_MIN) * (RIGHT - LEFT)


def y_pos(latency: float) -> float:
    return BOTTOM + latency / Y_MAX * (TOP - BOTTOM)


def build_dot(x_min: float, x_max: float, y_max: float, title: str) -> str:
    dot = [
        "graph comparison {",
        'graph [layout=neato, overlap=true, splines=line, outputorder=edgesfirst, bgcolor="white", margin=0, pad=0, size="8,8!", ratio=fill, dpi=100];',
        'node [fontname="DejaVu Sans", color="#333333"];',
        'anchor0 [pos="0,0!", shape=point, width=0.01, style=invis];',
        f'anchor1 [pos="{WIDTH},{HEIGHT}!", shape=point, width=0.01, style=invis];',
    ]
    y_divisions = 5
    for index in range(y_divisions + 1):
        value = index * y_max / y_divisions
        y = BOTTOM + value / y_max * (TOP - BOTTOM)
        label = f"{value:.0f}"
        dot += [f'yl{index} [pos="{LEFT},{y}!", shape=point, width=0.01, style=invis];', f'yr{index} [pos="{RIGHT},{y}!", shape=point, width=0.01, style=invis];', f'yl{index} -- yr{index} [color="{"#333333" if index in (0, y_divisions) else "#dddddd"}", penwidth={1.3 if index in (0, y_divisions) else 0.6}];', f'yt{index} [pos="{LEFT - 25},{y}!", shape=plaintext, label="{label}", fontsize=10];']
    for key in range(int(x_min * 100), int(x_max * 100) + 1):
        rate = key / 100.0
        x = LEFT + (rate - x_min) / (x_max - x_min) * (RIGHT - LEFT)
        dot += [f'xb{key} [pos="{x},{BOTTOM}!", shape=point, width=0.01, style=invis];', f'xt{key} [pos="{x},{TOP}!", shape=point, width=0.01, style=invis];', f'xb{key} -- xt{key} [color="{"#333333" if rate in (x_min, x_max) else "#dddddd"}", penwidth={1.3 if rate in (x_min, x_max) else 0.6}];', f'xl{key} [pos="{x},{BOTTOM - 22}!", shape=plaintext, label="{rate:.2f}", fontsize=10];']
    dot += [f'title [pos="{(LEFT + RIGHT) / 2},{HEIGHT - 18}!", shape=plaintext, label="{title}", fontname="DejaVu Sans Bold", fontsize=17];', f'xlabel [pos="{(LEFT + RIGHT) / 2},18!", shape=plaintext, label="Injection rate (packet/cycle/node)", fontsize=13];', f'ylabel [pos="20,{(BOTTOM + TOP) / 2}!", shape=plaintext, label="Average packet\\nlatency (cycles)", fontsize=11];', f'legend_b [pos="{LEFT + 110},{TOP - 20}!", shape=plaintext, label="● Board monitor (LFSR)", fontcolor="#2166c2", fontsize=11];', f'legend_t [pos="{LEFT + 300},{TOP - 20}!", shape=plaintext, label="■ Performance TB ($urandom)", fontcolor="#d6604d", fontsize=11];']
    for prefix, points, color, shape in [("board", BOARD_POINTS, "#2166c2", "circle"), ("tb", TB_POINTS, "#d6604d", "box")]:
        visible_points = [(rate, latency) for rate, latency in points if x_min <= rate <= x_max]
        for index, (rate, latency) in enumerate(visible_points):
            x = LEFT + (rate - x_min) / (x_max - x_min) * (RIGHT - LEFT)
            y = BOTTOM + latency / y_max * (TOP - BOTTOM)
            dot.append(f'{prefix}{index} [pos="{x},{y}!", shape={shape}, fixedsize=true, width=0.085, height=0.085, label="", color="{color}", fillcolor="{color}", style=filled, penwidth=0.8];')
            if index:
                dot.append(f'{prefix}{index - 1} -- {prefix}{index} [color="{color}", penwidth=2.2];')
    dot.append("}")
    return "\n".join(dot) + "\n"


def render(output_file: pathlib.Path, x_min: float, x_max: float, y_max: float, title: str, board_points: list[tuple[float, float]] = BOARD_POINTS, tb_points: list[tuple[float, float]] = TB_POINTS) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".dot", encoding="utf-8", dir=OUTPUT_FILE.parent, delete=False) as handle:
        global BOARD_POINTS, TB_POINTS
        original_board_points, original_tb_points = BOARD_POINTS, TB_POINTS
        BOARD_POINTS, TB_POINTS = board_points, tb_points
        handle.write(build_dot(x_min, x_max, y_max, title))
        BOARD_POINTS, TB_POINTS = original_board_points, original_tb_points
        dot_path = pathlib.Path(handle.name)
    try:
        subprocess.run(["neato", "-n2", "-Tpng", "-Gdpi=100", f"-o{output_file}", str(dot_path)], check=True)
    finally:
        dot_path.unlink(missing_ok=True)
    print(f"points={len(BOARD_POINTS)} output={output_file}")


def main() -> None:
    render(OUTPUT_FILE, 0.10, 0.20, 450.0, "5x5 / 4 VC / 4-flit: Board Monitor vs Performance TB")
    render(ZOOM_OUTPUT_FILE, 0.10, 0.17, 250.0, "Board Monitor vs Performance TB Zoom (0.10–0.17)") #Modify add a knee-focused 0.10-to-0.17 comparison view, Michael Tan, 20260908
    low_rate_board = [(0.00, 23.987), (0.10, 23.987)] + BOARD_POINTS #Modify extend the pre-0.10 board curve horizontally using its measured 0.10 value, Michael Tan, 20260908
    low_rate_tb = [(0.00, 22.565), (0.10, 22.565)] + TB_POINTS #Modify extend the pre-0.10 TB curve horizontally using its measured 0.10 value, Michael Tan, 20260908
    render(LOW_RATE_OUTPUT_FILE, 0.00, 0.16, 250.0, "Board Monitor vs Performance TB (0.00–0.16)", low_rate_board, low_rate_tb) #Modify add the requested 0-to-0.16 comparison view, Michael Tan, 20260908


if __name__ == "__main__":
    main()
