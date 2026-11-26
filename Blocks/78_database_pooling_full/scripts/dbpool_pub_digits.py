#!/usr/bin/env python3
"""Publication digit policy for dbpool / BlendedLoS packs.

Single source for rounding used by finalize_easl_paper_pub.py /
finalize_icuaaki_paper_pub.py. Keep in sync with
`.cursor/rules/dbpool_pub_digits.mdc` and Methods text in R/pub_dbpool_methods.R.

Policy (reference multi-database ICU mortality/RLoS TPC tables)
---------------------------------------------------------------------
| Quantity                         | Digits | Where                         |
|----------------------------------|--------|-------------------------------|
| Mortality AUROC (+ CI)           | 3      | Table 2, Table S2, Table S3/S4|
| Mortality AUROC (+ CI)           | 2      | Table 3 four-strategy matrix  |
| AUPRC (+ CI)                     | 3      | Table 2 / S3 when reported    |
| RLoS MAPE (+ CI)                 | 1      | Table 2, Table S2             |
| RLoS MAPE (+ CI)                 | 2      | Table 3, Table S3             |
| Mcomposite                       | 2      | Table 3                       |
| Internal–external Δ%             | 1      | Table 2 variation column      |
| Mortality / risk %               | 1      | Table 1, Table S5             |
| Predicted risk / Sens/Spec/PPV   | 3      | Table S5, calibration labels  |
| Fixed threshold labels           | 2      | Table S5 (≥0.10 / ≥0.20)      |
| Youden threshold                 | 3      | Table S5                      |
| Brier score                      | 3      | Figure 3 legends               |
| DeLong / bootstrap P             | NEJM   | <0.001 / >0.999 / else 3 dec  |
| Counts (N, deaths)               | int    | thousands comma               |

Do not mix Table 2 (3-dec AUROC) cells with Table 3 (2-dec AUROC) in the same
sentence without stating the table source.
"""
from __future__ import annotations

import math
from typing import Any

DIGITS = {
    "auroc_table2": 3,
    "auroc_table3": 2,
    "auroc_supp": 3,
    "auprc": 3,
    "mape_table2": 1,
    "mape_table3": 2,
    "mape_supp": 2,
    "mcomposite": 2,
    "var_pct": 1,
    "mort_pct": 1,
    "risk": 3,
    "sens_spec": 3,
    "threshold_fixed": 2,
    "threshold_youden": 3,
    "brier": 3,
}


def fmt_est(x: Any, digits: int = 3) -> str:
    if x is None:
        return "–"
    try:
        v = float(x)
    except (TypeError, ValueError):
        return "–"
    if not math.isfinite(v):
        return "–"
    return f"{v:.{int(digits)}f}"


def fmt_ci(est: Any, lo: Any, hi: Any, digits: int = 3, sep: str = "–") -> str:
    """Point [lo–hi] with en-dash unless sep overridden."""
    core = fmt_est(est, digits)
    if core == "–":
        return "–"
    try:
        lo_f, hi_f = float(lo), float(hi)
    except (TypeError, ValueError):
        return core
    if not (math.isfinite(lo_f) and math.isfinite(hi_f)):
        return core
    return f"{core} [{lo_f:.{int(digits)}f}{sep}{hi_f:.{int(digits)}f}]"


def fmt_p(p: Any) -> str:
    if p is None:
        return "–"
    try:
        v = float(p)
    except (TypeError, ValueError):
        return "–"
    if not math.isfinite(v):
        return "–"
    if v < 0.001:
        return "<0.001"
    if v > 0.999:
        return ">0.999"
    return f"{v:.3f}"


def fmt_n(n: Any) -> str:
    try:
        return f"{int(n):,}"
    except (TypeError, ValueError):
        return "–"


def scrub_display_underscore(text: str) -> str:
    """Replace programming underscores in display footnotes/labels (keep none)."""
    if not text:
        return text
    # known clinical tokens first
    repl = {
        "blood_glucose": "blood glucose",
        "urine_output": "urine output",
        "source_dataset": "source dataset",
        "pred_mort": "predicted mortality",
        "y_mort": "mortality label",
        "time_before_pred": "time-before-pred",
        "max_los": "max LoS",
    }
    out = str(text)
    for a, b in repl.items():
        out = out.replace(a, b)
    # residual snake_case → spaces (conservative: only [a-z0-9]_[a-z])
    import re

    out = re.sub(r"(?<=[A-Za-z0-9])_(?=[A-Za-z])", " ", out)
    return out
