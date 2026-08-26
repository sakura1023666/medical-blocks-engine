# 竞争风险顺序特征筛选与模型分层设计

## 1. 目标

将缺血性脑卒中竞争风险批次的协变量筛选改为严格串联：

`univariate_prognosis → feature_selection_lasso → feature_selection_random_forest`

使用通用特征选择 block，删除不再使用的
`competing_lasso_screen` 和 `competing_rf_screen`。单库 MIMIC 从 95 个复合指标
定义中自动剔除含糖尿病结局定义变量的暴露后，使用 20 路并行。

## 2. 结局适配

特征筛选针对 28 天糖尿病主事件：

- `competing_primary_event = 1`：`competing_status_28d == 1`
- `competing_primary_event = 0`：删失、死亡或出院
- 时间：`competing_time_28d`

单因素 Cox 和 Cox-LASSO 将死亡、出院按竞争事件删失处理。正式效应模型仍使用：

- Model 1–3：Fine-Gray 亚分布风险模型
- Model 4–6：Standard Cox

## 3. 严格串联筛选

### 3.1 单因素层

运行通用 `univariate_prognosis`：

- 候选池排除 ID、时间、结局、全部复合指标、当前指标四分位和轨迹分组；
- 完整导出单因素 Cox 结果；
- `P < 0.10` 的变量写入 `ctx$results$univar_features`；
- 无变量通过则该指标失败，失败阶段记为 `univariate_prognosis`。

### 3.2 LASSO 层

运行通用 `feature_selection_lasso`：

- 新增向后兼容配置 `candidate_source = "univariate"`；
- 只接收 `ctx$results$univar_features`；
- prognosis 路径使用 Cox-LASSO；
- 输出写入 `ctx$results$feature_selection_by_model$lasso`；
- 无变量通过则该指标失败，失败阶段记为 `feature_selection_lasso`。

### 3.3 随机森林层

运行通用 `feature_selection_random_forest`：

- 新增向后兼容配置 `candidate_source = "lasso"`；
- 只接收 `ctx$results$feature_selection_by_model$lasso`；
- 使用 caret RFE + randomForest；
- 输出写入 `ctx$results$feature_selection_by_model$random_forest`；
- 该结果作为最终协变量集合；
- 无变量通过则该指标失败，失败阶段记为
  `feature_selection_random_forest`。

## 4. Model 1–6 协变量分层

所有协变量顺序必须可复现，不允许为获得显著结果而反复试选。RF 变量按 RFE
结果及变量重要性确定顺序，LASSO 变量按其入选顺序，单因素变量按 P 值升序。

- Model 1/4：不调整协变量。
- Model 2/5：人口学协变量集合（必须至少一个人口学变量）。
- Model 3/6：Model 2/5 的全部变量加非人口学协变量，恒为其真超集。

**Model 2/5 人口学来源（回退链 RF → LASSO → 单因素）：**

1. 依次检查 RF 最终集合、LASSO 集合、单因素 `P < 0.10` 集合中的人口学变量；
2. 取**首个含人口学变量的层的全部人口学变量**作为 Model 2/5；
3. 三层都没有人口学变量 → 该指标失败，原因 `MODEL_COVARIATE_INSUFFICIENT`。

**Model 3/6 非人口学来源（同一回退链）：**

1. 从 RF → LASSO → 单因素依次取「非人口学且不在 Model 2/5 中」的变量；
2. 取首个非空层的这些变量并入 Model 2/5，构成 Model 3/6；
3. 无任何非人口学协变量可加 → 失败 `MODEL_COVARIATE_INSUFFICIENT`。

人口学池由 `competing_risk$demographic_vars` 定义（默认 `Age/Gender/Race/BMI`）。
`covs$demo_source` 与 `covs$nondemo_source` 记录实际命中的来源层。

## 4b. P 值发表格式

所有 SCI 三线表（Table 1/3）与森林图（Figure 2/5/7/9）的 P 值统一经
`pub_format_p()` 规范：`P < 0.001` 显示为 `<0.001`，`P > 0.999` 显示为
`>0.999`，其余保留 3 位小数；禁止出现 `7.3e-24` 这类科学计数字符串。
机器可读 CSV（`Table_Models_*` 等）保留原始数值精度。

## 5. 清理范围

- 删除：
  - `Blocks/55_competing_risk_full/04block_competing_lasso_screen.R`
  - `Blocks/55_competing_risk_full/08block_competing_rf_screen.R`
- 删除 `pipeline_runner.R` 中对应映射。
- 将竞争风险配置、模板和决策树中的旧 block 名替换为通用 block。
- 不使用特征选择 consensus；最终结果直接取 RF 层。

## 6. 疾病变量与复合指标组成变量硬排除

### 6.1 配置接口

每项研究通过通用配置声明疾病相关变量，不在 block 内写死具体疾病：

```r
analysis_exclusion = list(
  disease_vars = c("T1DM", "T2DM", "Diabetes", "HbA1c"),
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
```

变量名按大小写和常见分隔符归一匹配，但不使用可能误伤其他变量的模糊子串匹配。

### 6.2 当前指标组成变量解析

从 `Blocks/00_index/01block_index.R` 的 `.idx_definitions()` 读取当前指标公式，
使用 R 表达式解析变量名；如果公式依赖另一复合指标，则递归展开，直至得到原始列。
例如：

- `NLR → Neutrophil_Count + Lymphocytes`
- `ALI → Weight + Height + Albumin + Neutrophil_Count + Lymphocytes`

无法完成解析时停止该单元并记录
`EXCLUSION_COMPONENT_RESOLVE_FAIL`，不得静默放行。

### 6.3 两阶段排除

组成变量在当前复合指标计算完成前仍可用于计算，但从最早的插补 Table S1 开始加入
表级排除名单。指标层顺序为：
`competing_index_exposure`（基线值/四分位/长表）→ `analysis_exclusion` →
`trim_index_extreme` → `competing_trajectory_cluster`（仅对 trim 后保留 ID 做
LMM BLUP + mclust 最优 K）。`analysis_exclusion` 从 unit 的
`raw/cleaned/imputed` 分析副本硬删除：

1. 疾病相关变量；
2. 当前指标全部直接和链式原始组成变量；
3. 除当前指标外的其他复合指标；
4. 对应的派生泄漏列。

必须保留当前复合指标、四分位、轨迹、ID、时间、主事件和竞争事件列。审计日志可记录
删除名单，但 Table S1、Table 1/3、单因素、LASSO、RF、Model 1–6 和补充表均不得
出现被排除变量。

### 6.4 含疾病变量的暴露单元

若某复合指标公式直接或递归使用疾病变量，该指标从本研究的暴露单元中整体排除，
不进入 shared 轨迹计算或 worker 队列。当前定义至少覆盖
`SHR`、`HGI`、`HbA1c_HDL_C`、`eGDR`、`HSI`、`NFS`、`FSI`；
最终名单由公式解析生成，不依赖手写列表。

## 7. 成功与失败标签

沿用参考项目
`Prognosis_Trajectory_38882552/by_index` 的目录标签方式。每个指标结束后直接重命名
指标目录：

- `【success】{Index}`：全流程完成，可用于结果汇总；
- `【failed】{Index}`：流程失败或早停，不可用于主结果。

例如：`【success】NLR`、`【failed】APRI`。目录内部继续保留机器可读的
`_batch_status.json`，记录 `failed_stage`、`error_message`、耗时和最终协变量，
但不再新增 `_STATUS_SUCCESS.json` / `_STATUS_FAILED.json`。

根目录输出：

- `Tables/Indicator_availability.csv`
- `Tables/Indicator_availability.xlsx`
- `Tables/Batch_summary_all_units.csv`

汇总至少包含：指标、中文状态（可用/失败）、英文状态
（success/failed）、失败阶段、失败原因、轨迹 K、最终协变量、耗时。

## 8. 清库和重跑

保留 `data/` 原始输入，删除旧的：

- `by_unit/`
- `checkpoints/`
- `_shared/`
- `Tables/`
- `Figures/`
- `logs/`
- `data/mimic/12_*.RData`

然后依次运行：

1. `--shared-only --no-skip`
2. `--workers 20 --no-skip`

候选单位来自 `.composite_index_vars`，再自动剔除公式含糖尿病相关变量的指标；
配置、shared 层和 worker 层必须使用同一份过滤后名单。

## 9. 验证

1. 静态检查过滤后单位数、剔除原因及 workers=20。
2. NLR 单指标验证严格数据流：
   `univar_features → lasso → random_forest → model covariates`。
3. 检查 Model 2/5 是 Model 3/6 的真子集。
4. 检查 Fine-Gray 与 Standard Cox 均使用新的分层协变量。
5. 检查每个指标目录均带 `【success】` 或 `【failed】` 前缀，并有根目录汇总。
6. 对 NLR、ALI 做直接/链式组成变量解析测试。
7. 检查所有分析表、候选集和模型协变量不存在疾病变量、当前指标组成变量或其他复合指标。
8. 检查所有含 HbA1c/Diabetes 的复合指标均未进入任务队列。
9. 单指标验证通过后再启动 20 路全量批次。
