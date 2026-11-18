#!/usr/bin/env python3
"""Redraw ULN-triple main + sensitivity Figure 1/2 with Times-family fonts."""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

# Force Times before importing finalize (rcParams set at import)
os.environ.setdefault("MPLBACKEND", "Agg")

import finalize_easl_paper_pub as fin  # noqa: E402

print(f"[redraw] font family={fin._TIMES_FAMILY}", flush=True)

MAIN = Path("/mnt/sda/liver_uln_pub/summary_results_uln_triple")
STAGING = Path("/mnt/sda/liver_uln_pub/_staging_uln_sens")
ROOTS = {
    "all3": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996"),
    "bili": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996"),
    "alt": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996"),
    "ast": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996"),
}
META = {
    "all3": ("ULN-all3 lab-gate", "First AST≥38 and ALT≥41 and TBil≥1.3 mg/dL (all >ULN); drop AST+ALT+bilirubin"),
    "bili": ("ULN-bilirubin only", "First TBil≥1.3 mg/dL (22.23 µmol/L); drop bilirubin"),
    "alt": ("ULN-ALT only", "First ALT≥41 U/L; drop ALT"),
    "ast": ("ULN-AST only", "First AST≥38 U/L; drop AST"),
}
SENS_FILE = {
    "bili": "bilirubin ge1.3 only",
    "alt": "ALT ge41 only",
    "ast": "AST ge38 only",
}


def _set_cohort(key: str) -> None:
    title, rule = META[key]
    fin.COHORT_TITLE = title
    fin.COHORT_RULE_SHORT = rule
    fin.ROOT = ROOTS[key]
    fin.MAIN_OUT = fin.ROOT / "Output_physclip"
    fin.EXTRA = fin.ROOT / "Output_paper_extras_physclip"
    fin.PUB = MAIN if key == "all3" else STAGING / key


def _redraw_one(out: Path, key: str) -> None:
    _set_cohort(key)
    store = fin.collect_main()
    fin.make_fig1(out, store)
    tab = fin.fig2_training_size(fin.EXTRA, out)
    print(f"[redraw] {key} → {out} n_fig2={len(tab)}", flush=True)


def main() -> None:
    _redraw_one(MAIN, "all3")
    for key, file_lab in SENS_FILE.items():
        st = STAGING / key
        if not st.exists():
            raise SystemExit(f"missing staging {st}")
        _redraw_one(st, key)
        # copy fig2 into main as Figure S*
        src = "Figure 2. Training size"
        dst = f"Figure { {'bili':'S1','alt':'S2','ast':'S3'}[key] }. Training size ({file_lab})"
        for kind, ext in (("pdf", "pdf"), ("png", "png"), ("tiff", "tiff")):
            s = st / "Figures" / kind / f"{src}.{ext}"
            if not s.exists():
                continue
            d = MAIN / "Figures" / kind
            d.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, d / f"{dst}.{ext}")
        info_s = st / "Figures" / "image_information" / f"{src}.md"
        if info_s.exists():
            info_d = MAIN / "Figures" / "image_information"
            info_d.mkdir(parents=True, exist_ok=True)
            text = info_s.read_text(encoding="utf-8").replace(f"# {src}", f"# {dst}", 1)
            (info_d / f"{dst}.md").write_text(text, encoding="utf-8")
        print(f"[redraw] copied {dst}", flush=True)
    print("[redraw] DONE", MAIN, flush=True)


if __name__ == "__main__":
    main()
