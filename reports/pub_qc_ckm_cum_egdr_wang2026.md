# Pub QC — CKM cum-eGDR Wang 2026 (post-fix)

**Scope:** `by_index/【success】eGDR/summary_results/` only  
**N:** 4,983 (project; paper 5,248)  
**Verdict:** PASS (structure aligned to paper visual + MOESM; denominators project-true)

## MOESM table inventory

| ID | MOESM title | Our file |
|----|-------------|----------|
| S1 | Cox associations eGDR patterns + cum eGDR | `Table S1. Cox associations…xlsx` |
| S2 | Subgroup eGDR patterns (long: Subgroup\|Variable\|N\|Events\|HR\|P\|Pint) | `Table S2…xlsx` (rebuilt long) |
| S3 | Cox after multiple imputation | `Table S3. Cox after MICE.xlsx` |
| S4 | Logistic after multiple imputation | `Table S4. Logistic after MICE.xlsx` |
| Fig S1–S3 | RCS HR; subgroup HR; subgroup OR | present under Figures/ |

## What was wrong → fixed

| Issue | Fix |
|-------|-----|
| Fig2 B/C swapped; B no hull | A elbow \| **B scatter+chull** \| **C mean±SE** (PDF page7 visual; caption text was swapped) |
| Table1 sections not bold; levels flush; eGDR mid-labs; BMI exclusion | Bold Demographics/Labs/Comorbidities/**Exposure**; indent levels; Exposure at bottom; no BMI exclusion |
| Table3 last strata NE | Diabetes Yes Class4 & BMI≥30 Class3 = **NE** (0 events); footnote; Female→Male order |
| S2 ≠ MOESM | Rebuilt MOESM long format |
| S3/S4 titles weak | MOESM wording; near-zero missing → mirror complete-case + footnote |

## Fig2B confirm

Read `Figures/png/Figure 2. eGDR change patterns.png`: **Panel B = eGDR2012 vs eGDR2015 scatter with 4 colored convex hulls**, Class1 red circle / Class2 green triangle / Class3 blue square / Class4 purple asterisk — matches user screenshot & PDF.

## Paths

- Outputs: `/mnt/g/02block_result/46_CKM/累计暴露聚类_41654871/by_index/【success】eGDR/summary_results/`
- Rebuild: `run/cum_egdr_kmeans_ckm/rebuild_pub_tables_fig2.R`
- Gap note: `reports/pub_qc_ckm_cum_egdr_wang2026_gap.md`
