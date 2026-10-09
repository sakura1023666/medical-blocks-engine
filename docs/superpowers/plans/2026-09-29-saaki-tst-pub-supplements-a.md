# SA-AKI TST midterm pub supplements (Plan A)

> **For agentic workers:** additive only — do not rewrite Table1–3 / Fig1–3 / S6 / S7.

**Goal:** Add S8+ calibration, multi-model DCA, NRI/IDI, eICU strata + domain-shift note without changing locked main results.

**Architecture:** One-shot script `Blocks/71_two_stage_transformer_stroke/scripts/add_pub_supplements_midterm.py` reads existing `model_b.pth` + npz + APSIII map; writes only new files under `summary_results/`.

**Tech Stack:** Python (Windows Miniconda `torch` env), sklearn, matplotlib, numpy.

## Global Constraints

- Never overwrite existing Table 1–3 / S1–S2 / Figure 1–3 / S1–S7 bytes
- New IDs start at Table S8 / Figure S8
- Day5 / L120 / test n=849 (MIMIC); eICU Day5 evaluable cohort
- Comparator = APSIII; strong baseline = XGBoost (retrain day≤5 features, seed=42)
