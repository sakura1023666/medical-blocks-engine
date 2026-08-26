# 多重插补 Rubin 合并（全项目）

## 约定

- `config$imputation$m > 1` 且存在 `ctx$results$mice_model`（mids）时，**推断回归**默认按 Rubin 规则合并。
- `complete_action` 仍用于操作层单套数据框（trim / 特征选择 / 轨迹 / Table S1）。
- 开关：`config$imputation$rubin_pool`（默认 `TRUE`；显式 `FALSE` 可关闭）。

## 已接线

- 竞争风险主回归：`Blocks/55_competing_risk_full/09block_competing_models_123.R`（含死亡 Models）
- 工具：`R/mi_rubin_pool.R`

## 新课题模板

- `configs/templates/config_incidence_dual_batch.template.R`：`m=5`, `rubin_pool=TRUE`
- `configs/templates/config_competing_risk_stroke_batch.template.R`：同上

## 尚未接线（后续）

发病/预后 dual-batch 的 `cox_*` / `logistic_*` 仍吃单套 `imputed`。新课题请优先把关联表拟合改走 `mi_complete_aligned` + `mi_rubin_pool_estimates`；在接好前勿在方法学写「已按 Rubin 合并」除非该管线已接线。
