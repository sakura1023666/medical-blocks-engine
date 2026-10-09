# Pub QC gap — CKM cum-eGDR Wang 2026 (N=4983 project)

Date: 2026-09-30  
Outputs: `/mnt/g/02block_result/46_CKM/累计暴露聚类_41654871/by_index/【success】eGDR/summary_results/`

## MOESM inventory (12933_2026_3096_MOESM1_ESM.docx)

| ID | Title (verbatim) | Structure |
|----|------------------|-----------|
| Table S1 | Cox regression for associations between eGDR change patterns, cumulative eGDR, and stroke in subjects with CKM syndrome stages 0–4 | Variable · Total · Events · Model1–3 HR/P (Class2 ref; cum eGDR; tertiles; P for trend) |
| Table S2 | Subgroup analysis of eGDR change patterns and stroke incidence in subjects with CKM syndrome (stages 0–4) | **Long**: Subgroup · Variable · N · Events, n (%) · HR (95%CI) · P · P for interaction |
| Table S3 | Association … cox regression analysis after multiple imputation | Same skeleton as S1 (Model1–3 HR) |
| Table S4 | Association … logistic regression analysis after multiple imputation | Same skeleton as Table 2 (Model1–3 OR) |
| Fig. S1 | RCS cumulative eGDR vs stroke (HR), panels A/B/C by CKM | |
| Fig. S2 | Subgroup forest cumulative eGDR (per 0.1) HR | |
| Fig. S3 | Subgroup forest cumulative eGDR (per 0.1) OR | |

## Paper Fig2 (PDF page 7 visual vs caption)

| Panel | PDF visual (authoritative) | Caption text (swapped) |
|-------|---------------------------|-------------------------|
| A | Elbow WCSS vs k | Elbow |
| B | Scatter eGDR2012×eGDR2015 + colored convex hulls | Caption wrongly says “mean trajectories” |
| C | Mean eGDR trajectories 2012→2015 | Caption wrongly says “distribution” |

## What was wrong → fixed

1. **Fig2 B/C swapped**; B lacked hulls → A elbow \| **B scatter+hull** \| **C mean±SE**
2. **Table1**: section titles not bold; levels unindented; eGDR mixed mid-table; BMI extreme exclusion footnote → bold sections; indent levels; **Exposure** section at bottom; no BMI exclusion
3. **Table3** Diabetes Yes Class4 / BMI≥30 Class3 **NE** (0 events) — kept NE + footnote (paper used 0(0–Inf)); Gender ordered Female→Male
4. **Table S2** was wide Class columns ≠ MOESM long format → rebuilt MOESM long
5. **Table S3/S4** titles/layout refreshed to MOESM wording (near-zero missing → mirror complete-case + footnote)

## Paths

- Rebuild: `run/cum_egdr_kmeans_ckm/rebuild_pub_tables_fig2.R`, `rebuild_figures_match_paper.R`
- Helper: `R/literature_ckm_cum_egdr.R`
