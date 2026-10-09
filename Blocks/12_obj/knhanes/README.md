# KNHANES 复杂抽样权重（block_obj / weight_builder = "knhanes"）

本目录说明 **韩国国民健康营养调查（KNHANES）** 的加权方法，与美国 NHANES
（`R/nhanes_survey_weight.R`，权重 ÷K）**严格分开**。

## 实现入口

| 文件 | 作用 |
|------|------|
| `R/knhanes_survey_weight.R` | `compute_knhanes_pooled_weight()` / `knhanes_survey_weight_source_cols()` |
| `Blocks/12_obj/01block_obj.R` | `config$nhanes$weight_builder = "knhanes"` 时分派韩国权重，再 `svydesign` |
| `WEIGHTING.md` | KDCA 合并权重公式、层/PSU 唯一化、验收与 Methods 句 |

## 配置要点

```r
project = list(database = "KNHANES", database_type = "knhanes", ...)
nhanes = list(   # 槽位名沿用 nhanes（加权主库角色）；builder 决定算法
  weight_builder   = "knhanes",
  survey_weight    = "W_pooled",
  survey_cluster   = "PSU",
  survey_strata    = "STRATA",
  auto_new_weight  = TRUE,
  nest             = FALSE,   # KNHANES 指南：nest=FALSE（NHANES 默认 TRUE）
  recompute_new_weight = TRUE # 分析集定型后须按当前 Σn 重算
)
knhanes = list(
  raw_weight  = "wt_itvex",  # 问卷+体检；营养模型敏感性可用 wt_tot
  raw_cluster = "psu",
  raw_strata  = "kstrata",
  cycle_col   = "cycle"
)
```

## 下游纪律

- 主文 Table1 / UV / MV / VIF / Logistic / RCS / 亚组 / 加权中介：一律吃 `nhanes_design*`（由本 builder 建成）。
- **禁止**把 `W_pooled` 塞进普通 `glm(..., weights=)` 当主结果。
- 亚组用 `subset(design, …)`，不要重算权重常数。
- 纳排流程图用未加权样本计数。
