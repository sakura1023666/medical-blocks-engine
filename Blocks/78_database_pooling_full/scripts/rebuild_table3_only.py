#!/usr/bin/env python3
"""Rebuild only Table 3 (Allyn layout + stay-level CIs) into an existing summary_results pack."""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, "/tmp")

import pandas as pd

import finalize_easl_paper_pub as fin  # noqa: E402


def main():
    root = Path(
        os.environ.get(
            "LIVER_ROOT",
            "/mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996",
        )
    )
    if (root / "Output_physclip").is_dir():
        fin.MAIN_OUT = root / "Output_physclip"
    else:
        fin.MAIN_OUT = root / "Output_noenzyme"
    if (root / "Output_paper_extras_physclip").is_dir():
        fin.EXTRA = root / "Output_paper_extras_physclip"
    else:
        fin.EXTRA = root / "Output_paper_extras"
    fin.ROOT = root
    pub = Path(
        os.environ.get(
            "LIVER_PUB_OUT",
            str(root / "summary_results_acg_physclip"),
        )
    )
    tables = pub / "Tables"
    tables.mkdir(parents=True, exist_ok=True)

    store = fin.collect_main()
    ci_path = fin.EXTRA / "ci_main_four_arms" / "Table_CI_DeLong_bootstrap10k.csv"
    ci = pd.read_csv(ci_path) if ci_path.exists() else None
    print("MAIN_OUT", fin.MAIN_OUT, flush=True)
    print("CI rows", 0 if ci is None else len(ci), flush=True)
    t3 = fin.table3_wide_matrix(store, ci)
    fin._save_table(
        t3,
        tables / "Table 3. Four training strategies",
        title="Table 3. Model performance on specialization and generalization in four separate training methods",
        footnote="AUROC 95% CI: DeLong (stay-level). MAPE 95% CI: patient-level bootstrap 10,000. "
        "Mcomposite = 0.5×[(MAPE/MAPE₀)+( (1−AUROC)/(1−AUROC₀) )] with Amsterdam-alone on Amsterdam as baseline; point estimate. "
        "¹Transfer learning: pretrain on MIMIC-IV then fine-tune on AmsterdamUMC; only Amsterdam specialization is reported. "
        "²Data pooling: AmsterdamUMC + MIMIC-IV. "
        "Generalization = mean of eICU and HiRID (held out from training). "
        "Dashes: strategy not applicable or evaluation database absent from that run's test predictions.",
    )
    print("wrote", tables / "Table 3. Four training strategies.xlsx")
    print(t3.to_string(index=False))


if __name__ == "__main__":
    main()
