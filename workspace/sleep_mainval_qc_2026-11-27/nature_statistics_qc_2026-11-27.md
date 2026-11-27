# Nature statistics QC — sleep dyslipidemia mainval（2026-11-27 re-audit）

- Project: `G:\02block_result\49_Dyslipidemia\prognosis_v2_mainval_41904528（00）\summary_results`
- Profile: `PV2_PROFILE=sleep_dyslipidemia`
- Scope: delivery Tables / Methods / midterm vs former Nature P0 list
- Verdict: **PASS** (former P0-1…P0-9 all FIXED; no residual P0 accepted)

## Former P0 disposition

| ID | Issue | Status | Evidence |
|----|-------|--------|----------|
| P0-1 | Fig5 NHANES AUC labelled 0.765 vs Table S4 0.764 | **FIXED** | `pdftotext` Fig5 legend: `NHANES (AUC=0.764)`; image_information locked to S4 |
| P0-2 | Table S1 listed RCS cutoff / S10–S14 package | **FIXED** | S1 Items = Population…SBP only; no S10/S12–S14 data row (footnote notes packages not in delivery) |
| P0-3 | Methods missing bootstrap B=200 / seed | **FIXED** | Methods: `B = 200, seed = 41904528`; Table S8 footnotes same |
| P0-4 | Methods missing RCS knots 5/35/65/95 & ref 7.5 h | **FIXED** | Methods dose–response sentence: interior knots 5th/35th/65th/95th; reference 7.5 h |
| P0-5 | Methods missing MICE outcome-exclusion limitation | **FIXED** | Methods: residual selection bias vs outcome-inclusive imputation; Table S6 referenced |
| P0-6 | WTMEC cycle-pooling ambiguity | **FIXED** | Methods: WTMEC2YR + nested PSU/strata; **no additional cycle-pooling multipliers** |
| P0-7 | Table S9 vs Table 3 contrast denominator unclear | **FIXED** | S9 footnotes (3 cohorts): subset vs five-level Table 3; small numeric differences expected |
| P0-8 | Table4 ragcod on primary cohorts; CHARLS “Supplementary only” sole role | **FIXED** | NHANES/SHHS: no ragcod; CHARLS: ragcod definition + **Sparse-event note** (17 CV deaths; descriptive); no “Supplementary only” |
| P0-9 | Fig7 missing P-int; no Subgroup_Pint.csv | **FIXED** | Fig7 annotates P-int per stratum; `Subgroup_Pint.csv` in delivery_workspace checkpoints |

## Cross-checks

- Midterm PDF: no Table S10 / S12–S14 / RCS cutoff-package narrative (no rebuild required).
- Competing-risk Table 4 primary cohorts free of CHARLS-only cause coding notes.
- Mediation bootstrap seed aligned Methods ↔ S8.
- Delivery whitelist after prune: Figures / Tables / Methods md / software txt / 中期 PDF only.
- Layer A3 underscore: PASS after Fig7 subtitle used “Sleep Group”.

## Residual notes (not P0)

- P1: dense Fig7 text may still trip collision scanners; delivery PDF remains vector.
- CHARLS Fine–Gray remains sparse-event descriptive by design.

## Conclusion

**PASS** — all nine former Nature P0 items FIXED; ready for delivery hand-off.
