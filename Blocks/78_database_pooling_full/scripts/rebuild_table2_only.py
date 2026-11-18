#!/usr/bin/env python3
"""Rebuild only Table 2 (with DeLong/bootstrap CIs) into an existing summary_results pack."""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Allow `python /tmp/rebuild_table2_only.py` with finalize helpers on PYTHONPATH or same dir.
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, "/tmp")

import finalize_easl_paper_pub as fin  # noqa: E402


def main():
    root = Path(
        os.environ.get(
            "LIVER_ROOT",
            "/mnt/sda/BlendedICU/data/liver_dysfunction_acg_42151996",
        )
    )
    if (root / "Output_paper_extras_physclip").is_dir():
        extra = root / "Output_paper_extras_physclip"
    else:
        extra = root / "Output_paper_extras"
    pub = Path(
        os.environ.get(
            "LIVER_PUB_OUT",
            str(root / "summary_results_acg_physclip"),
        )
    )
    tables = pub / "Tables"
    tables.mkdir(parents=True, exist_ok=True)
    # Ensure helpers see same EXTRA/ROOT as env-driven finalize
    fin.EXTRA = extra
    fin.ROOT = root
    print("EXTRA", extra, flush=True)
    print("PUB", pub, flush=True)
    t2 = fin.table2_manuscript(extra)
    if t2.empty:
        raise SystemExit("Table 2 empty — check liver_dataset_benchmark predictions")
    fin._save_table(
        t2,
        tables / "Table 2. Internal and external",
        title="Table 2. Comparison of the TPC model's internal and external validation when training on subsets of the BlendedICU dataset",
        footnote="TPC trained on one database (100% trainval). "
        "Internal = same-database test stays; External = pooled stays from the other three databases (single CI). "
        "AUROC 95% CI: DeLong (stay-level). MAPE/AUPRC 95% CI: patient-level bootstrap 10,000 (percentile). "
        "AUPRC cells include class-prevalence Baseline. "
        "Variation = (external − internal) / internal × 100%.",
    )
    print("wrote", tables / "Table 2. Internal and external.xlsx")
    print(t2.to_string(index=False))


if __name__ == "__main__":
    main()
