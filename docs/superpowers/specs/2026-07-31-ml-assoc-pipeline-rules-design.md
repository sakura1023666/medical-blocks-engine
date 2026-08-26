# ML 双库流水线规则：关联分析 + AdaBoost + 出图去重

> 状态：已实现；RAR 验收通过（2026-07-31）  
> 依赖：`2026-07-31-ml-cross-db-train-test-design.md`（跨库 train/test 已落地）  
> 动机：胰腺癌 RAR 中期 PDF 要求的 RCS / 逻辑回归 / Cox / KM / 亚组 HR 在当前 ML 精简上游中缺失；AdaBoost 被默认剔除；单张 PDF 出现两页相同图。

## 1. 目标

把下列规则写进 **引擎可复用配置与块序列**（方案 A），使下次复现时：

1. 出齐与中期 PDF 对应的关联分析图/表（命名无库前缀）。
2. AdaBoost 在小样本自动启用、大样本自动跳过。
3. 单张 PDF **不得**出现两页相同内容。

不以「改一篇 PDF 文案编号」为目标；以流水线产物完整、可复现为目标。

## 2. 已确认决策

| 项 | 决策 |
|----|------|
| 落地范围 | **A**：改 `ml_dual_*` 默认主链 + 块数据槽；研究 config 只开开关/阈值 |
| 单因素 | **仅训练集**；预后与预测均用 **逻辑回归** |
| VIF | **训练集与测试集各做一份** |
| LASSO / 特征选择 | **仅训练集**（与现网一致，规则写死） |
| 关联数据槽 | 单库：`data_imp`；双库/`cross_db`：`data_train` + `data_test` 各跑一遍 |
| 无时间变量 | **跳过** Cox、KM、亚组 HR |
| AdaBoost | 加入默认 methods；仅当 **`n_train < 350`**（`max_train_n = 349`）才训练，否则跳过不失败 |
| 命名 | 发表级文件名用 `Train` / `Validation`（或无前缀），**禁止**注入 MIMIC/eICU 等库名 |
| 图「重复」含义 | **同一 PDF 内两页内容相同**（非 step vs 根目录镜像） |

## 3. 主链顺序（规则）

在 `imputation` → `train_validation`（及既有 baseline / ROC / boxplot 等）之后：

```
1. univariate_*          # 仅 train；逻辑回归（incidence 与 prognosis 均走 logistic 单因素语义）
2. multicollinearity_screen  # train + test 各一份 VIF（及必要相关图）
3. 关联块：
     logistic_*_glm（及按需 rcs 后 logistic）
     rcs_*
     若 has_time_var：cox_binary + km_binary
     （无时间变量则整段 Cox/KM 不入链）
4. ml_feature_selection_bundle   # LASSO 等仅 train
5. ml_models_bundle              # 含条件 AdaBoost
6. performance_ml / supplementary_ml / shap / shiny_ml_app
7. subgroup：OR（incidence）+ 若 has_time_var 再挂 HR（prognosis 亚组或等价 HR 块）
```

`has_time_var`：`nzchar(config$survival$time_var)`（本例 `futime`）。

### 3.1 替换现网行为

当前 `ml_dual_primary_ml_stat_upstream_blocks()` 仅挂：

- `univariate_*` + `multicollinearity_screen`

并 **故意跳过** logistic / RCS / Cox / KM。本规格要求改为挂上 §3 关联段；精简上游不再作为 dual ML 默认。

可选保留开关：`config$ml_batch$assoc_blocks = "full" | "ml_thin"`（默认 `"full"`），避免极少数只要 ML 的旧实验被硬打断；但胰腺癌研究强制 `"full"`。

## 4. 数据槽约定

| 场景 | 单因素 | VIF | 关联（logistic/RCS/Cox/KM） | LASSO/ML |
|------|--------|-----|------------------------------|----------|
| 单库 | train（若尚未 split，则等价于 `imputed` 全队列；实现上优先 `ctx$data$train`，缺失则回退 `imputed`） | train+test；若无 test 则仅 imputed 一份 | `imputed`（`data_imp`） | train/test |
| 双库 / cross_db | **仅** `ctx$data$train` | `train` 与 `test` 各一份 | **各**在 `train`、`test` 上跑 | train 拟合 / test 外推 |

实现注意：

- 现网槽位名保持 `ctx$data$train` / `test` / `imputed`（不改名为 `data_train`；文档可写别名）。
- 双库关联块需支持 `data_slots = c("train","test")` 循环，或等价「跑两次、产出两套图/表」。
- 发表文件名后缀：`… (Train).pdf` / `… (Validation).pdf`，或合并多面板一张且图注写 Train/Validation；**不得**写库名。

## 5. AdaBoost

1. `ml_dual_default_ml_methods()` **纳入** `"adaboost"`。
2. 默认 / 覆盖：`config$ml_adaboost$limits$max_train_n <- 349L`（`n_train > 349` → 跳过）。
3. 诊断并修复历史挂起/失败（依赖、CV、超时、环境），保证在 `n_train < 350` 时可写出 `evalresult_adaboost.RData`。
4. 跳过时：日志说明原因，**不**导致整指标 failed。

胰腺癌当前 `n_train≈308` → 应跑通 AdaBoost。

## 6. 单 PDF 双页相同图（根因与修复）

### 6.1 根因（已核实）

`render_queued_figures()`（`R/utils.R`）约定：`plot_fn` **只 return 图形对象**，由渲染器 `print` 一次。若 `plot_fn` 内已 `print(x)` 且返回值仍是 ggplot/grob/cowplot，会再 `print` 一次 → **同一 PDF 两页相同**。

实测：`Figure 2. ML performance combined 2x4.pdf` 为 **Pages: 2**，两页预览一致。  
触发代码形如：`save_figure(..., function() print(comb), ...)`（`Blocks/23_ml_performance/01block_performance_ml.R` 多处）。

### 6.2 修复规则

1. 所有 `save_figure` 的 `plot_fn`：**禁止**内部 `print`；改为 `function() comb` / `function() p`。
2. 优先清扫 `performance_ml` 中全部 `function() print(...)`；并扫其他 ML 相关块同类写法。
3. 验收：关键 PDF `pdfinfo` → `Pages: 1`（或设计上的多页且页间内容不同）。

## 7. 无库前缀

1. 保持 `mirror_aggregate_prefix_db = FALSE`。
2. 特征选择等标签中的 `Train MIMIC IV -Test eICU` 改为不含库名（如空前缀或 `Train-Test`）。
3. 双库关联产物用 Train/Validation，不用库名。

## 8. 亚组

- 始终出 **OR** 亚组（incidence 路径）。
- 若 `has_time_var`：再出 **HR** 亚组（挂 `subgroup_prognosis` 或现有 HR 等价块；数据槽与关联一致：双库则 train/test 策略与主分析一致，默认至少在 train 上出 HR 森林图——若实现成本高，规格最低要求：**有时间变量则必须产出至少一份 HR 亚组表/图**）。
- 无时间变量：不挂 HR。

## 9. 与中期 PDF 的映射（验收清单，非强制同编号）

| PDF 内容 | 流水线产物期望 |
|----------|----------------|
| Table S1 插补前后 | 已有 imputation Table S1 |
| Table 1 基线 | baseline |
| 单因素 | univariate（仅 train） |
| VIF / 相关 | multicollinearity_screen（train+test） |
| RCS | rcs_*（train+test 或单库 imp） |
| 逻辑回归表 | logistic_*_glm |
| Cox 表 + KM | cox_binary + km_binary（有 futime） |
| LASSO 等 | feature selection（仅 train） |
| ML 总览 / 宽表 / SHAP | performance_ml / shap（含 AdaBoost 当 n_train<350） |
| 亚组 | OR +（有时间）HR |

## 10. 非目标

- 不自动改选指标循环名单。
- 不强制 PDF 图号与流水线 `Figure N` 编号一一改名（可由后期 curate）。
- 不删除 step 目录存档；只修「单文件双页重复」。

## 11. 实现落点（供计划拆任务）

1. `configs/ml_dual_shared_overrides.R`：块序列、`assoc_blocks`、AdaBoost methods + `max_train_n`。
2. 单因素 / VIF / 关联块：`data_slot` / 双槽循环 / 无时间跳过。
3. `11block_ml_adaboost.R` + 默认 methods：限流 + 修挂。
4. `01block_performance_ml.R`（及同类）：`save_figure` 去掉内层 `print`。
5. 发表标签：去库名前缀。
6. 胰腺癌 `config.R`：对齐 full assoc + adaboost；RAR 验收重跑。

## 12. 风险

- 默认挂全关联会拉长每个指标 runtime。
- 双槽关联若块不支持循环，需最小侵入包装，避免改爆所有 logistic/cox 块。
- 预后「单因素也用逻辑回归」可能与旧 `univariate_prognosis`（Cox）语义冲突：dual ML 路径显式改走 logistic 单因素或配置 `univariate_method = "logistic"`。
