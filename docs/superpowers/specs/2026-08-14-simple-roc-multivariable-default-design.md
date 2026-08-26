# Design: simple_ROC 默认多变量（锁定协变量）

**Date:** 2026-08-14  
**Status:** approved — implemented 2026-08-14  
**Approved choices:** 方案 A；锁定为空硬失败；引擎级默认；预测器 = `glm(指标 + 锁定协变量)` 概率

## 1. Goal

让所有挂 `simple_ROC` 的常规发病/预后课题，默认用**协变量选择最终锁定名单**做多变量预测 ROC，与 Table 2 Model2 / Gate B 一致；避免再默认只画单变量指标 ROC。

## 2. Non-goals

- 不改 ML 专用 `ROC` 块（基于 `ml_models` workflow 的那条）。
- 不做时间依赖 ROC / Cox 线性预测子 ROC（预后仍用事件二分类 + logistic 预测概率，与现有 `simple_ROC` 一致）。
- 不强制同时输出单变量+多变量双曲线。

## 3. Behavior

### 3.1 Defaults (`config$roc_simple`)

| 键 | 新默认 | 说明 |
|---|---|---|
| `mode` | `"multivariable"` | 原块内默认 `"univariate"` |
| `covariate_source` | `"locked"` | `locked_multivariable_covariates` / `vif_final_pass` / `Model2Factors` |
| 覆盖 | 仍允许 | `mode = "univariate"` 或 `enable = FALSE` |

### 3.2 Model

1. 解析 `index_var`（incidence / survival / roc_simple）。
2. 解析锁定协变量：`locked_multivariable_covariates(ctx, cfg)$covariates`（**不含**指标本身）。
3. 若名单为空且 `mode = "multivariable"` → **`stop()`**，提示须放在 VIF final / Gate B / `multivariate_*_harmonized` 之后，或改 `mode`/`covariate_source`。
4. `glm(.y ~ index + covariates, family = binomial)` → `predict(..., type = "response")` → `pROC::roc`。
5. 图题标明 multivariable；汇总表（若导出）写 `Covariates` 列。

### 3.3 Outcome resolution

| 研究类型 | 结局列 |
|---|---|
| 发病 | `roc_simple$outcome_var` → `data$outcome_column` → `"Disease"`（现状） |
| 预后 | `roc_simple$outcome_var` → **`survival$event_var`** → 再回退 data outcome；二分类事件（0/1） |

预后不再误用发病 `Disease` 列（若列不存在本就会失败；有同名脏列时更危险）。

### 3.4 Pipeline placement

- **发病 / 预后常规批**：`simple_ROC` 必须在 `multivariate_*_harmonized`（或单库等价锁定点）之后。基线 JSON 发病段已满足；预后尾部扩展保持在 core 之后。
- **ML 基线**（`pipeline_regular_primary_ml_batch` 等把 `simple_ROC` 放在 VIF 前）：**模板显式 `mode = "univariate"`**（或 `enable = FALSE`），避免硬失败；不与 ML 特征选择混用同一锁定语义。不挪 ML 块顺序（本版）。

## 4. Code / config touch list

1. `Blocks/13_roc/02block_simple_ROC.R`  
   - 默认 `mode` → multivariable  
   - 锁定为空：warning+return → **stop**  
   - 预后 `event_var` 解析  
   - 文件头注释与 PITFALL 对齐  
2. Templates：`config_survival_dual_batch.template.R`、`config_incidence_iptw.template.R` 等缺 `mode` 的补上；发病已写 multivariable 的保持。  
3. ML 相关 template / study build：显式 `roc_simple$mode = "univariate"`（若启用 simple_ROC）。  
4. `docs/Blocks_catalog.md` MANUAL:PITFALLS 一条。  
5. Tests：  
   - 块默认 mode 为 multivariable（或 resolve 路径测默认）  
   - 锁定为空 + multivariable → `stop`  
   - 预后 outcome 解析优先 `event_var`  
   - 现有 locked vs config 协变量测试保留  
   - 发病基线顺序测试保留；可加「生存尾部 simple_ROC 在 harmonized 之后」的轻量断言（若易测）

## 5. SAE / 已有结果

- 课题 `config_survival.R` 的 `roc_simple` 可不改（吃引擎默认）；重跑 `simple_ROC` 后 Figure S4 变为多变量。  
- 旧单变量 ROC 图不会自动更新，需对该指标 `--no-skip` 或只重跑含 ROC 的段落。

## 6. Success criteria

- [ ] 无显式 `mode` 时，发病/预后常规跑出多变量 ROC，协变量与锁定 Model2 一致。  
- [ ] 锁定为空时流水线硬停并给出可操作提示。  
- [ ] 预后用 `event_var`。  
- [ ] ML 管线不因新默认而莫名失败。  
- [ ] 相关 guard 测试通过。

## 7. Open decisions (resolved)

- ML：本版 **显式 univariate**，不挪 `baseline_pipelines.json` 中 ML 的 `simple_ROC` 位置。
