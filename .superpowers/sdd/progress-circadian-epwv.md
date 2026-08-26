# SDD Progress — circadian-cross-lagged-epwv (2026-08-17)

Plan: `docs/superpowers/plans/2026-08-17-circadian-cross-lagged-epwv.md`
Note: **no git** — do not commit.

## Tasks
- Task 1: complete (prep dabiao; review clean)
- Task 2: complete (column review + disease_vars)
- Task 3: complete (三库 Table1 含 ePWV)
- Task 4: complete (VIF lock + Pooled N=87973 + 四路 logistic/RCS)
- Task 5: complete (node_stems/carry_vars/skip NHANES; CLPN 强制 condition1–7)
- Task 6: complete (CHARLS/ELSA 纵向中介 ePWV→FI→DN)
- Task 7: complete (spec 状态已更新)

## Longitudinal results
- CHARLS: N=2585, events=433; CLPN k=4 (drop condition2/3/4); mediation 18.1% complementary
- ELSA: N=2560, events=819; CLPN k=2 (drop 2/3/4/5/7); mediation 9.4% complementary
- Model2: Gender+Marital_Status+Alcohol_drinking+Weight+Hypertension+Diabetes（无 Age）
- 中介时序：两波，M 与 Y 同年

## Minor
- T1: NHANES circ_merge rounded; circ_keep_cols intersect
- T3: CHARLS Table1 无 BMI（其它复合指标排除）
- 中介/相关表文件名仍带 FI_Depression_Hip 后缀，表内标签已是 ePWV/FI/Circadian
