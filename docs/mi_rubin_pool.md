# 多重插补 Rubin 合并（全项目）

## 铁律（2026-10）

凡启用 MICE（`imputation$method` 非 `none`）：

1. **`m = 5`**（默认；可更大，禁止默默 `m = 1` 当 MI）
2. **`rubin_pool = TRUE`**：Cox / logistic / Fine–Gray 等**推断回归**跨 m 套拟合后按 Rubin 合并
3. **`complete_action = 1`** 仅服务操作层（Table1/S1、trim、FS、KM/RCS、轨迹输入）
4. **禁止**「m=5 只取 complete#1 出 HR/OR」还写多重插补

规则文件：`.cursor/rules/mi_m5_rubin_pool.mdc`

## 引擎入口

| 能力 | 函数 |
|------|------|
| 规范化 config | `mi_rubin_normalize_config`（`run_pipeline` / `imputation` 启动时） |
| 是否启用 | `mi_rubin_enabled(ctx)` |
| 取第 k 套并对齐 | `mi_complete_aligned` |
| Cox | `mi_coxph` |
| 二项 GLM | `mi_glm_binomial` |
| 合并 | `mi_rubin_pool_estimates` |

工具：`R/mi_rubin_pool.R`

## 已接线

- 竞争风险主回归：`Blocks/55_competing_risk_full/09block_competing_models_123.R`
- 预后 Cox 四分位：`Blocks/10_cox/03block_cox_quartile.R` → `mi_coxph`
- 发病 logistic 四分位：`Blocks/11_logistic/01block_logistic_quartile_glm.R` → `mi_glm_binomial`
- 预后 2.0 Table3：`run/prognosis_v2/pv2_mi_cox.R`

## 模板

所有含插补的 template 须含：

```r
imputation = list(
  method = "cart", m = 5L, max_iter = 5L, seed = 1234L,
  complete_action = 1L, rubin_pool = TRUE
)
```

`mi_rubin_normalize_config` 会在运行时把缺失的 `rubin_pool` 补成 TRUE、把 `m<5` 抬到 5。

## 例外

- `method = "none"`
- TST / 部分 ML **训练**可用操作层单套；同课题发表用 Cox/logistic 仍须 Rubin
- 用户书面单课题关闭（Methods 不得写 MI 推断）

## 测试

`tests/test_mi_rubin_pool.R`
