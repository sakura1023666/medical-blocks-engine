#!/usr/bin/env python3
"""DEPRECATED thin wrapper → harmonize_blendedlos_units.py

Kept so older ULN retrain shells (`schedule_uln_glu_retrain_34.sh`) keep working.
New code must call `harmonize_blendedlos_units.py` (glucose + hemoglobin + gate).
"""
from __future__ import annotations

import argparse
from pathlib import Path

from harmonize_blendedlos_units import harmonize_root


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Wrapper: full unit harmonize (glucose+Hb). Prefer harmonize_blendedlos_units.py"
    )
    ap.add_argument(
        "--ready",
        type=Path,
        default=Path("/mnt/sda/BlendedICU/data/blendedlos_ready"),
    )
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    print(
        "[deprecated] fix_mimic_blood_glucose_mmol.py → harmonize_blendedlos_units "
        f"root={args.ready}",
        flush=True,
    )
    harmonize_root(
        args.ready,
        dry_run=args.dry_run,
        limit=args.limit,
        dbs=("mimic4", "mimic3", "eicu", "amsterdam", "hirid"),
        run_assert=not args.dry_run,
    )


if __name__ == "__main__":
    main()
