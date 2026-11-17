#!/usr/bin/env python3
"""After cross_eval_ams_mimic, rebuild Table 3 + sensitivity S4/S6/S8 into the ULN triple pack."""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.styles import Alignment, Font

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import finalize_easl_paper_pub as fin  # noqa: E402
import pandas as pd

PUB = Path(
    os.environ.get(
        "ULN_TRIPLE_PUB_OUT",
        "/mnt/sda/liver_uln_pub/summary_results_uln_triple",
    )
)

COHORTS = [
    {
        "key": "all3",
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_all3_42151996"),
        "dst_name": "Table 3. Four training strategies.xlsx",
        "title": "Table 3. Model performance on specialization and generalization in four separate training methods",
        "sens_prefix": "",
    },
    {
        "key": "bili",
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_bili_42151996"),
        "dst_name": "Table S4. Four training strategies (bilirubin ge1.3 only).xlsx",
        "title": "Table S4. Sensitivity: bilirubin ≥1.3 mg/dL only — Model performance on specialization and generalization in four separate training methods",
        "sens_prefix": "Sensitivity analysis (bilirubin ≥1.3 mg/dL only). ",
    },
    {
        "key": "alt",
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_alt_42151996"),
        "dst_name": "Table S6. Four training strategies (ALT ge41 only).xlsx",
        "title": "Table S6. Sensitivity: ALT ≥41 U/L only — Model performance on specialization and generalization in four separate training methods",
        "sens_prefix": "Sensitivity analysis (ALT ≥41 U/L only). ",
    },
    {
        "key": "ast",
        "root": Path("/mnt/sda/BlendedICU/data/liver_dysfunction_uln_ast_42151996"),
        "dst_name": "Table S8. Four training strategies (AST ge38 only).xlsx",
        "title": "Table S8. Sensitivity: AST ≥38 U/L only — Model performance on specialization and generalization in four separate training methods",
        "sens_prefix": "Sensitivity analysis (AST ≥38 U/L only). ",
    },
]

FOOT = (
    "AUROC 95% CI: DeLong (stay-level). MAPE 95% CI: patient-level bootstrap 10,000. "
    "Mcomposite = 0.5×[(MAPE/MAPE₀)+( (1−AUROC)/(1−AUROC₀) )] with Amsterdam-alone on Amsterdam as baseline; point estimate. "
    "¹Transfer learning: pretrain on MIMIC-IV then fine-tune on AmsterdamUMC; only Amsterdam specialization is reported. "
    "²Data pooling: AmsterdamUMC + MIMIC-IV. "
    "Specialization off-diagonal cells (Amsterdam model on MIMIC-IV test; MIMIC-IV model on Amsterdam test) use peer-database cross-evaluation. "
    "Generalization = mean of eICU and HiRID (held out from training). "
    "Dashes: strategy not applicable."
)


def _rebuild_one(spec: dict) -> None:
    root = spec["root"]
    fin.ROOT = root
    _tag = os.environ.get("OUT_TAG", "physclip").strip() or "physclip"
    fin.MAIN_OUT = Path(os.environ.get("EASL_MAIN_OUT", "").strip() or str(root / f"Output_{_tag}"))
    fin.EXTRA = Path(
        os.environ.get("EASL_EXTRA_OUT", "").strip()
        or str(root / f"Output_paper_extras_{_tag}")
    )
    store = fin.collect_main()
    ci_path = fin.EXTRA / "ci_main_four_arms" / "Table_CI_DeLong_bootstrap10k.csv"
    ci = pd.read_csv(ci_path)
    # sanity: cross cells present for solo arms
    for unit, db in (
        ("liver_expA_amsterdam_solo", "mimic4"),
        ("liver_expB_mimic_solo", "amsterdam"),
    ):
        hit = ci[(ci["unit"] == unit) & (ci["eval_on"] == db)]
        if hit.empty:
            raise SystemExit(f"missing cross CI {unit}×{db} under {ci_path}")
    t3 = fin.table3_wide_matrix(store, ci)
    tmp = PUB / "_tmp_t3_rebuild"
    tmp.mkdir(parents=True, exist_ok=True)
    stem = spec["dst_name"].replace(".xlsx", "")
    fin._save_table(
        t3,
        tmp / stem,
        title=spec["title"],
        footnote=spec["sens_prefix"] + FOOT,
    )
    src = tmp / (stem + ".xlsx")
    dst = PUB / "Tables" / spec["dst_name"]
    shutil.copy2(src, dst)
    # enforce Times title
    wb = load_workbook(dst)
    ws = wb.active
    ws.cell(1, 1).font = Font(name="Times New Roman", bold=True, size=12)
    ws.cell(1, 1).alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    wb.save(dst)
    print(f"[ok] {spec['key']} → {dst.name}", flush=True)
    # show off-diagonal cells
    print(t3.iloc[[1, 4]].to_string(index=False), flush=True)


def main() -> None:
    (PUB / "Tables").mkdir(parents=True, exist_ok=True)
    for spec in COHORTS:
        _rebuild_one(spec)
    print("[done] Table 3 / S4 / S6 / S8 refreshed", flush=True)


if __name__ == "__main__":
    main()
