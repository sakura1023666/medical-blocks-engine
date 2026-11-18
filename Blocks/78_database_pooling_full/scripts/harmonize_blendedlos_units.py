#!/usr/bin/env python3
"""Engine-level BlendedLoS / BlendedICU timeseries unit harmonization + gate.

Target units match Allyn MOESM1 physio clip bounds used by `_run_one_template.py`:
  - blood_glucose → mmol/L  (clip ~2.8–12.4)
  - hemoglobin    → g/dL    (clip ~6.0–14.0)

Self-built `blendedlos_ready` / disease extracts sometimes skip official
`timeseriesprocessor._harmonize_*` conversions. This module is the single
engine fix so every prepare / train path cannot silently train on mixed units.

Idempotent: median-based detection; already-harmonized files are skipped.
Marker: <root>/preprocessed_timeseries/_units_harmonized.json

Usage:
  python harmonize_blendedlos_units.py --root /mnt/sda/BlendedICU/data/blendedlos_ready
  python harmonize_blendedlos_units.py --root .../blendedlos_icuaaki --assert-only
  python harmonize_blendedlos_units.py --root ... --dry-run --limit 20
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

# BlendedICU official mimic*/eicu glucose factor
MGDL_TO_MMOL = 0.0555

# Detection thresholds (file-level non-null median)
GLU_MGDL_MEDIAN = 30.0  # >30 → treat as mg/dL
HB_GDL_LO, HB_GDL_HI = 4.0, 20.0  # already g/dL
HB_GL_LO, HB_GL_HI = 40.0, 250.0  # g/L → /10
HB_X100_LO, HB_X100_HI = 400.0, 2500.0  # 100× g/dL (seen on HiRID ready copies) → /100

# Gate: per-DB sampled medians must land here after harmonize
GATE_GLU = (3.0, 15.0)
GATE_HB = (6.0, 16.0)
GATE_MIN_FILES = 20
GATE_SAMPLE = 80

DBS_DEFAULT = ("amsterdam", "mimic4", "eicu", "hirid", "mimic3")


def _atomic_write_parquet(df: pd.DataFrame, path: Path) -> None:
    fd, tmp = tempfile.mkstemp(suffix=".parquet", dir=str(path.parent))
    os.close(fd)
    tmp_path = Path(tmp)
    try:
        df.to_parquet(tmp_path, index=False)
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)


def _median(series: pd.Series) -> float | None:
    nn = pd.to_numeric(series, errors="coerce").dropna()
    if nn.empty:
        return None
    return float(nn.median())


def _fix_glucose(raw: pd.Series) -> tuple[pd.Series, dict[str, Any]]:
    med = _median(raw)
    if med is None:
        return raw, {"status": "empty"}
    if med < GLU_MGDL_MEDIAN:
        return raw, {"status": "already_mmol", "median": med}
    out = pd.to_numeric(raw, errors="coerce").astype(float)
    mask = out.notna() & (out > GLU_MGDL_MEDIAN)
    out.loc[mask] = out.loc[mask] * MGDL_TO_MMOL
    # second pass for residual mg/dL pockets
    mask2 = out.notna() & (out > GLU_MGDL_MEDIAN)
    out.loc[mask2] = out.loc[mask2] * MGDL_TO_MMOL
    new_med = _median(out)
    return out, {
        "status": "converted_mgdl_to_mmol",
        "median_before": med,
        "median_after": new_med,
        "n_converted": int(mask.sum()),
        "factor": MGDL_TO_MMOL,
    }


def _hb_factor(med: float) -> tuple[float, str] | tuple[None, str]:
    if HB_GDL_LO <= med <= HB_GDL_HI:
        return None, "already_gdl"
    if HB_GL_LO <= med <= HB_GL_HI:
        return 10.0, "gL_to_gdl_div10"
    if HB_X100_LO <= med <= HB_X100_HI:
        # Prefer /100 when that lands in g/dL; else /10 (official HiRID)
        if HB_GDL_LO <= (med / 100.0) <= HB_GDL_HI:
            return 100.0, "x100_to_gdl_div100"
        if HB_GDL_LO <= (med / 10.0) <= HB_GDL_HI:
            return 10.0, "gL_to_gdl_div10"
        return 100.0, "x100_to_gdl_div100"
    # Ambiguous high values: try /100 then /10
    if med > HB_X100_HI:
        if HB_GDL_LO <= (med / 100.0) <= HB_GDL_HI:
            return 100.0, "x100_to_gdl_div100"
        if HB_GDL_LO <= (med / 10.0) <= HB_GDL_HI:
            return 10.0, "gL_to_gdl_div10"
    return None, f"unhandled_median_{med:.3f}"


def _fix_hemoglobin(raw: pd.Series) -> tuple[pd.Series, dict[str, Any]]:
    med = _median(raw)
    if med is None:
        return raw, {"status": "empty"}
    factor, reason = _hb_factor(med)
    if factor is None:
        return raw, {"status": reason, "median": med}
    out = pd.to_numeric(raw, errors="coerce").astype(float)
    mask = out.notna() & (out > 0)
    out.loc[mask] = out.loc[mask] / factor
    new_med = _median(out)
    return out, {
        "status": f"converted_{reason}",
        "median_before": med,
        "median_after": new_med,
        "n_converted": int(mask.sum()),
        "divisor": factor,
    }


def _convert_file(path: Path, *, dry_run: bool) -> dict[str, Any]:
    df = pd.read_parquet(path)
    touched = False
    report: dict[str, Any] = {"file": path.name, "vars": {}}
    for col, fixer in (
        ("blood_glucose", _fix_glucose),
        ("hemoglobin", _fix_hemoglobin),
    ):
        if col not in df.columns:
            report["vars"][col] = {"status": "no_col"}
            continue
        new_s, meta = fixer(df[col])
        report["vars"][col] = meta
        if meta.get("status", "").startswith("converted"):
            if not dry_run:
                if not touched:
                    df = df.copy()
                    touched = True
                df[col] = new_s
            else:
                touched = True
    if touched and not dry_run:
        _atomic_write_parquet(df, path)
        report["status"] = "written"
    elif touched:
        report["status"] = "would_write"
    else:
        report["status"] = "unchanged"
    return report


def _iter_db_parquets(root: Path, dbs: tuple[str, ...]) -> list[tuple[str, Path]]:
    ts = root / "preprocessed_timeseries"
    out: list[tuple[str, Path]] = []
    for db in dbs:
        folder = ts / db
        if not folder.is_dir():
            continue
        for p in sorted(folder.glob("*.parquet")):
            if p.name.startswith("_"):
                continue
            out.append((db, p))
    return out


def sample_db_medians(
    root: Path,
    *,
    dbs: tuple[str, ...] = DBS_DEFAULT,
    n_files: int = GATE_SAMPLE,
    seed: int = 0,
) -> dict[str, dict[str, float | None]]:
    """Return {db: {blood_glucose: med, hemoglobin: med}} from sampled files."""
    rng = np.random.default_rng(seed)
    result: dict[str, dict[str, float | None]] = {}
    ts = root / "preprocessed_timeseries"
    for db in dbs:
        folder = ts / db
        if not folder.is_dir():
            continue
        files = [p for p in folder.glob("*.parquet") if not p.name.startswith("_")]
        if not files:
            continue
        take = min(n_files, len(files))
        chosen = list(rng.choice(files, size=take, replace=False))
        acc: dict[str, list[float]] = {"blood_glucose": [], "hemoglobin": []}
        for p in chosen:
            try:
                cols = [c for c in ("blood_glucose", "hemoglobin")]
                df = pd.read_parquet(p, columns=cols)
            except Exception:
                df = pd.read_parquet(p)
            for c in acc:
                if c in df.columns:
                    v = pd.to_numeric(df[c], errors="coerce").dropna()
                    if len(v):
                        acc[c].append(float(v.median()))
        result[db] = {
            c: (float(np.median(vals)) if vals else None) for c, vals in acc.items()
        }
    return result


def assert_units_harmonized(
    root: Path,
    *,
    dbs: tuple[str, ...] | None = None,
    require_dbs: tuple[str, ...] | None = None,
) -> dict[str, Any]:
    """Hard gate: raise SystemExit if any present DB fails glucose/Hb unit checks.

    require_dbs: DBs that must exist under preprocessed_timeseries (optional).
    """
    root = Path(root)
    ts = root / "preprocessed_timeseries"
    if not ts.is_dir():
        raise SystemExit(f"[units-gate] missing {ts}")
    present = tuple(
        d
        for d in (dbs or DBS_DEFAULT)
        if (ts / d).is_dir() and any((ts / d).glob("*.parquet"))
    )
    if require_dbs:
        missing = [d for d in require_dbs if d not in present]
        if missing:
            raise SystemExit(f"[units-gate] required DBs missing: {missing}")
    meds = sample_db_medians(root, dbs=present or DBS_DEFAULT)
    failures: list[str] = []
    for db, m in meds.items():
        g = m.get("blood_glucose")
        h = m.get("hemoglobin")
        if g is not None and not (GATE_GLU[0] <= g <= GATE_GLU[1]):
            failures.append(
                f"{db} blood_glucose median={g:.3f} not in mmol/L gate {GATE_GLU}"
            )
        if h is not None and not (GATE_HB[0] <= h <= GATE_HB[1]):
            failures.append(
                f"{db} hemoglobin median={h:.3f} not in g/dL gate {GATE_HB}"
            )
    report = {
        "root": str(root),
        "medians": meds,
        "gate_glucose_mmol": GATE_GLU,
        "gate_hemoglobin_gdl": GATE_HB,
        "ok": not failures,
        "failures": failures,
    }
    if failures:
        raise SystemExit(
            "[units-gate] FAIL — mixed or unconverted units detected:\n  - "
            + "\n  - ".join(failures)
            + "\nFix: python Blocks/78_database_pooling_full/scripts/harmonize_blendedlos_units.py "
            f"--root {root}"
        )
    print(f"[units-gate] PASS root={root} medians={json.dumps(meds)}", flush=True)
    return report


def harmonize_root(
    root: Path,
    *,
    dry_run: bool = False,
    limit: int = 0,
    dbs: tuple[str, ...] = DBS_DEFAULT,
    run_assert: bool = True,
) -> dict[str, Any]:
    root = Path(root)
    files = _iter_db_parquets(root, dbs)
    if limit > 0:
        files = files[:limit]
    print(
        f"[units] root={root} files={len(files)} dry_run={dry_run}",
        flush=True,
    )
    counts: dict[str, int] = {}
    by_db_var: dict[str, dict[str, dict[str, int]]] = {}
    for i, (db, path) in enumerate(files, 1):
        r = _convert_file(path, dry_run=dry_run)
        counts[r["status"]] = counts.get(r["status"], 0) + 1
        by_db_var.setdefault(db, {})
        for var, meta in r.get("vars", {}).items():
            st = str(meta.get("status", "?"))
            by_db_var[db].setdefault(var, {})
            by_db_var[db][var][st] = by_db_var[db][var].get(st, 0) + 1
        if i % 2000 == 0 or i == len(files):
            print(f"[units] {i}/{len(files)} {counts}", flush=True)

    meds_before = None  # filled only in dry path via sampling after
    meds = sample_db_medians(root, dbs=dbs) if not dry_run else sample_db_medians(root, dbs=dbs)
    marker = {
        "harmonized_at": datetime.now(timezone.utc).isoformat(),
        "root": str(root.resolve()),
        "n_files": len(files),
        "counts": counts,
        "by_db_var": by_db_var,
        "sample_medians": meds,
        "dry_run": bool(dry_run),
        "glucose_factor_mgdl_to_mmol": MGDL_TO_MMOL,
        "note": (
            "blood_glucose→mmol/L; hemoglobin→g/dL "
            "(HiRID g/L÷10 or 100×g/dL÷100 by median)"
        ),
    }
    marker_path = root / "preprocessed_timeseries" / "_units_harmonized.json"
    if not dry_run:
        marker_path.parent.mkdir(parents=True, exist_ok=True)
        marker_path.write_text(json.dumps(marker, indent=2), encoding="utf-8")
        print(f"[units] marker → {marker_path}", flush=True)
        # keep legacy glucose marker for old ULN scripts
        mimic = root / "preprocessed_timeseries" / "mimic4"
        if mimic.is_dir():
            legacy = {
                "converted_at": marker["harmonized_at"],
                "via": "harmonize_blendedlos_units.py",
                "factor": MGDL_TO_MMOL,
                "sample_medians": meds.get("mimic4"),
            }
            (mimic / "_glucose_mmol_L.json").write_text(
                json.dumps(legacy, indent=2), encoding="utf-8"
            )
    else:
        print(json.dumps(marker, indent=2))

    if run_assert and not dry_run:
        assert_units_harmonized(root, dbs=dbs)
    print("[units] DONE", counts, flush=True)
    return marker


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--root",
        type=Path,
        required=True,
        help="blendedlos_ready or disease blendedlos_* tree",
    )
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--assert-only", action="store_true")
    ap.add_argument(
        "--dbs",
        default=",".join(DBS_DEFAULT),
        help="comma-separated DB folder names under preprocessed_timeseries",
    )
    ap.add_argument("--no-assert", action="store_true")
    args = ap.parse_args()
    dbs = tuple(x.strip() for x in args.dbs.split(",") if x.strip())
    if args.assert_only:
        assert_units_harmonized(args.root, dbs=dbs)
        return
    harmonize_root(
        args.root,
        dry_run=args.dry_run,
        limit=args.limit,
        dbs=dbs,
        run_assert=not args.no_assert,
    )


if __name__ == "__main__":
    main()
