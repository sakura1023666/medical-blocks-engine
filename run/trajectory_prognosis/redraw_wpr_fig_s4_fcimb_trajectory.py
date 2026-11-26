#!/usr/bin/env python3
"""Figure S4: literature-style sensitivity JLCM trajectories.

Default: 28-day complete follow-up mortality (all-cause via dead_time) vs
primary in-hospital 28-day death — matches fcimb Supp Fig4.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path("/mnt/e/01block/01Block-new-Final")


def main(argv: list[str] | None = None) -> None:
    argv = list(argv or sys.argv[1:])
    if "--mode" not in argv:
        argv = ["--mode", "allcause28", *argv]
    cmd = [
        "Rscript",
        str(ROOT / "run/trajectory_prognosis/redraw_wpr_fig_s4_sensitivity_landmark.R"),
        *argv,
    ]
    subprocess.run(cmd, check=True, cwd=str(ROOT))


if __name__ == "__main__":
    main()
