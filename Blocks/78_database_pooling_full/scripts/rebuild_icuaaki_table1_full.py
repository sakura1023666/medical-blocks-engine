#!/usr/bin/env python3
"""Full Table 1 (vitals/labs/drugs) for ICUAKI via finalize_easl helpers."""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("ICUAKI_ROOT", "/mnt/sda/BlendedICU/data/icuaaki_4db_20261106"))
os.environ.setdefault("LIVER_ROOT", str(ROOT))
os.environ.setdefault("LIVER_BLENDED_SUBDIR", "blendedlos_icuaaki")
os.environ.setdefault("EASL_MAIN_OUT", str(ROOT / "Output_database_pooling"))
os.environ.setdefault("EASL_EXTRA_OUT", str(ROOT / "Output_paper_extras"))
os.environ.setdefault("LIVER_PUB_OUT", str(ROOT / "summary_results"))
os.environ.setdefault("LIVER_COHORT_TITLE", "ICU-AKI (KDIGO DN=1)")
os.environ.setdefault(
    "LIVER_COHORT_RULE_SHORT",
    "KDIGO ICU-AKI DN=1; drop Cr/UO from features",
)
os.environ.setdefault(
    "LIVER_TABLE1_FOOTNOTE",
    "KDIGO ICU-AKI cohort (DN=1). Continuous: mean [SD] "
    "(vitals/labs = stay-level hourly mean after physiological-range clip). "
    "Drug exposure: any hourly dose >0 during the stay. "
    "Creatinine and urine output excluded from model features.",
)
os.environ.setdefault("LIVER_FEATURE_DROP_EN", "Creatinine and urine_output excluded from model features.")
os.environ.setdefault("LIVER_TABLE1_WORKERS", "24")
os.environ.setdefault("LIVER_SKIP_DELIVERY", "1")

# Import after env so module-level paths resolve to ICUAKI.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import finalize_easl_paper_pub as f  # noqa: E402

def main() -> None:
    print("BLENDED", f.BLENDED_ROOT, "exists", f.BLENDED_ROOT.exists(), flush=True)
    tables = f.PUB / "Tables"
    tables.mkdir(parents=True, exist_ok=True)
    df = f.table1_wide()
    f._save_table(
        df,
        tables / "Table 1. Cohort characteristics",
        title="Table 1. Characteristics of ICU-AKI patient stays included in the study, according to the original database",
        footnote=f.TABLE1_FOOTNOTE,
    )
    print("WROTE", tables / "Table 1. Cohort characteristics.xlsx", "rows", len(df), flush=True)


if __name__ == "__main__":
    main()
