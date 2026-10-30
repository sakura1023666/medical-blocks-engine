# cute_ran HHR midterm alignment audit (2026-10-30)

**Ground truth:** `/mnt/e/01block/01Block-new-Final/cute_ran老师中期分析结果.pdf`  
**Archive (Oct23):** `/mnt/g/02block_result/22_depression/incidence_cute_ran/summary_results_MOVED_to_by_index_20261023_171023/`  
**Delivery:** `/mnt/g/02block_result/22_depression/incidence_cute_ran/by_index/【success】HHR/summary_results/`

## FAIL checklist (pre-fix → action)

| # | Item | Midterm / Archive | Pre-fix current | Action |
|---|---|---|---|---|
| 1 | **Fig1** | Dual A NHANES / B CHARLS; first box `Participants in NHANES 2005-2023` (n=41,714); first exclude `Age < 18 or missing age` (NHANES 0 / CHARLS 21); included 30,069 / 9,934 | Single-panel CHARLS `(mimic)`; `Starting cohort (2005-2023) n=16,216`; wrong exclude wording | **RESTORED** archive Fig1 (pdf/png/tiff) |
| 2 | **Fig S3 NHANES** | Direct **2.990** (1.500, 5.958) p=0.003; Prop **4.760%** | Direct 3.369; Prop 4.630% | **RESTORED** |
| 3 | **Table S9-NHANES mediation** | Total **3.217**; Direct 2.99; Path a **8.783**; Prop 4.760% | Total 3.65; Direct 3.369; Path a 8.591; Prop 4.630% | **RESTORED** archive S8 → retitled S9 |
| 4 | **Table 1-CHARLS Education** | Below HS **2,060 (20.74%)** / Above **7,874 (79.26%)**; p=0.016 | 8,911 (89.70%) / 1,023 (10.30%) | **RESTORED** |
| 5 | **CHARLS S1–S7** | Education coding 20.74%/79.26% | Flipped + VIF/MV drift | **RESTORED** archive |
| 6 | **Table 2-CHARLS Model2** | cont OR **1.388**; Q4 **1.263** | 1.39; 1.264 | **RESTORED** |
| 7 | **Fig2 / Fig3 / S1 / S2** | Oct23 hashes | MD5 differed | **RESTORED** all 6 figure PDFs + rasters |
| 8 | Path a **0.056** | Must not appear; CHARLS Path a=**0.113** | Not in delivery | **OK** |

## Already matched (kept)

- Table 1-NHANES: N=30,069 / 27,268 / 2,801 (Age/CRP etc. match midterm 表1)
- Table 2-NHANES: Q4 Model2 OR=1.306 (tiny P rounding vs archive only)
- Table S9-CHARLS: Path a=0.113; Direct=1.394; Prop=2.020% (= midterm 表6)
- Table S11 alcohol NHANES: matches midterm 表7 ORs
- Fig2 caption numbers: P-overall <0.001; NHANES nonlinear=0.560; CHARLS <0.001

## Numbering note

Midterm body labeled mediation as 表5/6 (archive files were `Table S8`). Delivery keeps dual-db roles: **S8=lab Associations**, **S9=Mediation**. S8 Associations retained; CHARLS CRP Model2 β=0.113 aligns with Path a.

## What was restored / fixed

- All 6 Figures → index `Figures/` + `summary_results/Figures/` (from Oct23 archive; formats ok, dpi≥600)
- CHARLS T1/T2/S1–S7, both S9 mediation, alcohol S10/S11, T2-NHANES → Tables in index + summary_results
- Midterm PDF replaced with **reference GT** (md5 `b8442d2c…`)
- No full dual-batch. NHANES `step27` mediation xlsx was permission-locked (delivery S9 is correct)

## Final paths

- Delivery root: `/mnt/g/02block_result/22_depression/incidence_cute_ran/by_index/【success】HHR/summary_results/`
- Midterm PDF: `.../summary_results/cute_ran老师中期分析结果.pdf`
- This audit: `/mnt/g/02block_result/22_depression/incidence_cute_ran/reports/midterm_align_audit_2026-10-30.md`
