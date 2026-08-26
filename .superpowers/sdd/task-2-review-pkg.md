# Task 2 Review Package

## Report
# Task 2 Report — 指标库审计与补缺

**日期**：2026-08-26  
**状态**：完成

## 交付物

| 产物 | 路径 |
|------|------|
| 指标公式追加 | `Blocks/00_index/01block_index.R`（+5：`LMR`, `MLR`, `PIV`, `SIIR`, `SIS`） |
| 覆盖审计 | `G:/02block_result/29_SLE/.../data/_index_coverage.md` |
| 本报告 | `.superpowers/sdd/task-2-report.md` |

## Step 1 — 已有 vs 文献目标

审计 15 个文献目标：10 已有，5 缺失（SIS, LMR, MLR, PIV, SIIR）。未重复追加 CONUT/PNI/GNRI/NLR/SII/SIRI/BMI/PLR/CAR/AGR。

## Step 2 — 追加公式（文献依据）

| 指标 | 定义 |
|------|------|
| LMR | Lymphocytes / Monocyte |
| MLR | Monocyte / Lymphocytes |
| PIV | Platelet × Neutrophil × Monocyte / Lymphocyte（Pan-Immune-Inflammation Value） |
| SIIR | Neutrophil × Monocyte × Platelet / Lymphocyte（SIIRI，与 PIV/AISI 同型） |
| SIS | Shibutani 2018 *Oncol Lett*：LMR>4.44 且 Albumin>4.0 g/dL → 0；双低 → 2；其余 → 1 |

未改 index 块 skip 逻辑；缺 Monocyte 时上述 6 项（含 SIRI）自动 skip。

## Step 3 — 冒烟

dabiao n=271，最小列映射 + `scale_hematology_dataframe`：

- **8/15 目标可算**：BMI, NLR, PLR, SII, AGR, CAR, PNI, GNRI
- **6 项 skip**：Monocyte 列不存在（SIRI, LMR, MLR, PIV, SIIR, SIS）
- **CONUT_score**：需中间评分列，全 pipeline 顺序下可算
- **5 条新公式 PARSE_OK**

## 自检

- [x] 仅追加缺失项，风格与现有 `list(name=..., expr=..., digits=...)` 一致
- [x] `_index_coverage.md` 含 have/missing/推荐 `index$only`
- [x] 未 git commit
- [x] 未改旧课题 config / Tables/Figures

## 遗留 / 下游

1. **Monocyte**：MIMIC baseline 无该列；若 Task 3 column_mapping 能从 WBC−Neutrophil−Lymphocytes 派生，则 LMR/MLR/SIS/SIRI/PIV/SIIR 可激活。
2. **PIV vs AISI vs SIIR**：公式等价，保留三名称供文献对照；analysis_exclusion 会分别解析组成。
3. **composite_index_vars.R**：未同步（Task brief 仅要求 `01block_index.R`）；后续 bulk 名单可补 5 名。

## _index_coverage.md
# 指标库覆盖审计 — SLE→AKI（Task 2）

**审计日期**：2026-08-26  
**公式源**：`Blocks/00_index/01block_index.R`  
**文献目标**（design spec §8）：CONUT、PNI、GNRI、NLR、SII、SIRI、SIS、LMR、BMI、PLR、MLR、CAR、PIV、AGR、SIIR

## 文献目标 vs 引擎

### 已有（审计前）

CONUT_score, PNI, GNRI, NLR, SII, SIRI, BMI, PLR, CAR, AGR

### 缺失（已追加）

| 指标 | 公式 / 文献依据 | 依赖列 |
|------|-----------------|--------|
| LMR | Lymphocytes / Monocyte | Lymphocytes, Monocyte |
| MLR | Monocyte / Lymphocytes | Monocyte, Lymphocytes |
| PIV | Platelet × Neutrophil × Monocyte / Lymphocyte（Fuca et al.） | Platelet_Count, Neutrophil_Count, Monocyte, Lymphocytes |
| SIIR | Neutrophil × Monocyte × Platelet / Lymphocyte（SIIRI，心血管文献） | 同上 |
| SIS | Shibutani 2018：LMR>4.44 且 Albumin>4.0→0；双低→2；其余→1 | Lymphocytes, Monocyte, Albumin |

### 引擎全量指标名（审计时 n=93→98）

见 `01block_index.R` `.idx_definitions()`；新增 5 条位于 SIRI 之后。

## 本队列 dabiao 可算性（冒烟 2026-08-26）

映射 `NeutrophilCount→Neutrophil_Count`、`PlateletCount→Platelet_Count`、`TC→Total_Cholesterol` 后，n=271：

| 状态 | 指标 |
|------|------|
| **可算**（n_valid>0） | BMI, NLR, PLR, SII, AGR, CAR, PNI, GNRI |
| **skip**（缺 Monocyte） | SIRI, LMR, MLR, PIV, SIIR, SIS |
| **需中间列**（全 pipeline 可算） | CONUT_score（alb_score/lymp_score/chol_score） |

baseline/dabiao **无 Monocyte 列**；Monocyte 依赖项在 index 块自动 skip，符合 design「缺成分不中断」。

## 推荐 `index$only`（本课题）

```r
c("CONUT_score", "PNI", "GNRI", "NLR", "SII", "SIRI", "SIS", "LMR",
  "BMI", "PLR", "MLR", "CAR", "PIV", "AGR", "SIIR")
```

缺 Monocyte 时实际 `computed_indices` 为上述子集；不中断流水线。

## Diff hunks for new indices in 01block_index.R
295:    list(name = "LMR",
296-         expr = "Lymphocytes / Monocyte",
297-         digits = 4),
298:    list(name = "MLR",
299-         expr = "Monocyte / Lymphocytes",
300-         digits = 4),
301:    list(name = "PIV",
302-         expr = paste0(
303-           "Platelet_Count * Neutrophil_Count * ",
304-           "Monocyte / Lymphocytes"
305-         ),
306-         digits = 4),
307:    list(name = "SIIR",
308-         expr = paste0(
309-           "Neutrophil_Count * Monocyte * ",
310-           "Platelet_Count / Lymphocytes"
311-         ),
312-         digits = 4),
313:    list(name = "SIS",
314-         expr = paste0(
315-           "dplyr::case_when(",
316-           "Lymphocytes / Monocyte > 4.44 & Albumin > 4.0 ~ 0, ",
317-           "Lymphocytes / Monocyte <= 4.44 & Albumin <= 4.0 ~ 2, ",
318-           "TRUE ~ 1)"
319-         ),
320-         digits = 0L),
321-    list(name = "MHR",
