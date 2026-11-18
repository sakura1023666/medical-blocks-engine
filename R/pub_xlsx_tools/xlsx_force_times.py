#!/usr/bin/env python3
"""Thin CLI alias → python/pub_xlsx_scrub_display.py --times-only.

Do not add a second Times implementation here. Canonical logic is in
python/pub_xlsx_scrub_display.py (also used by pub_delivery_scrub_display).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRUB = ROOT / "python" / "pub_xlsx_scrub_display.py"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: xlsx_force_times.py <xlsx> [xlsx...]", file=sys.stderr)
        return 2
    if not SCRUB.exists():
        print(f"missing scrub script: {SCRUB}", file=sys.stderr)
        return 1
    cmd = [sys.executable, str(SCRUB), "--times-only", *sys.argv[1:]]
    return int(subprocess.call(cmd))


if __name__ == "__main__":
    raise SystemExit(main())
