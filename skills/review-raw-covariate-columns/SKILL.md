---
name: review-raw-covariate-columns
description: >-
  Reviews every column in study raw data and builds disease_vars /
  analysis_exclusion lists so disease markers never enter covariates,
  Table1/S1, UV/MV/VIF, Model1–2, subgroups, or mediation. Use when writing
  or editing any Medical Blocks config, starting a new study, mapping dabiao
  columns, setting analysis_exclusion, or when the user mentions 审阅原始数据 /
  疾病相关协变量 / disease_vars / 写 config.
---

# 原始数据列审阅 → 疾病硬排除（全流水线必做）

写 / 改任何发病·预后·IPW·竞争风险·ML config **之前**，必须对本课题原始表
**逐列审阅**，把「与研究疾病相关、会造成结局泄漏或病理标志物污染」的列
写入 `analysis_exclusion$disease_vars`，并从协变量池/亚组/clinical 名单删除。
**禁止**只抄模板里的 `T2DM/HbA1c` 就交差。

配套铁律见 `.cursor/rules/disease_component_hard_exclusion.mdc`（指标组成排除仍
由 `analysis_exclusion` 块按当前 index 自动做；本 skill 专管**疾病相关列**）。

---

## 何时必须调用

- 新建 / 复制 / 迁移 config（含 `create-pipeline-config`）
- 换 dabiao / 结局 / 疾病编码
- 用户质疑某协变量不合理（如糖尿病课题里的尿白蛋白）
- 批量重跑前发现 Model2/Table1 仍含疾病标志物

---

## 工作流（不可跳步）

### 1. 读全列名

```r
env <- new.env(parent = emptyenv())
load("<rawdata_path>", envir = env)
obj <- env[[ "<rawdata_obj>" ]]
cols <- names(obj)
writeLines(cols, "<study>/Data/_column_review_raw.txt")
```

若已有 column_mapping，再列一遍 **mapping 后** 标准名（以分析实际列名为准）。

### 2. 按课题疾病做「保留 / 硬排除」二分

对 **每一列** 问：它是不是本课题疾病的诊断、分型、用药、核心病理/代谢标志物、
或结局定义泄漏？

| 归类 | 处置 |
|------|------|
| 人口学 / 通用血压血脂肝肾（非本疾病专属） | 可留协变量候选 |
| 本疾病诊断/分型/用药 | → `disease_vars` |
| 本疾病核心实验室标志物 | → `disease_vars` |
| 结局列 / ID / 权重/设计列 | 不进协变量（用既有 exclude，不塞进 disease_vars 亦可） |
| 复合指标本身 | 不进 disease_vars；由指标组成排除处理 |

**不确定时默认排除**（记入 `disease_vars` 并在审阅表标注【边界·已排除】），
不要为了「表更全」留下。

### 3. 疾病专项提示（示例，非写死引擎）

**糖尿病 / 糖尿病视网膜病变 / 糖尿病肾病相关课题** 至少审阅并通常排除：

- 诊断/分型：`T1DM`, `T2DM`, `Diabetes`
- 血糖轴：`Glucose`, `HbA1c`, `Insulin`, `OGTT*` 等
- 用药：`Antidiabetic_agents` 及同类
- 糖尿病微血管/肾病标志：`Albumin_Urine`, `AlbuminUrine`, `UACR`,
  `Microalbumin*` 等（尿白蛋白 ≠ 血清 `Albumin`；血清 Albumin 仅当它是
  **当前指标组成**时由成分排除删除，不因「尿白蛋白」误伤）

**其他疾病**：按病理自行列全（如 CKD→eGFR/肌酐分期诊断；心衰→BNP/NT-proBNP 等）。
**禁止**在 `Blocks/` 引擎里写死某病名单。

### 4. 写出审阅产物（必须落盘）

写到研究 `Data/`：

1. `_column_review.md` — 全列表：`列名 | 保留/排除 | 一句话理由`
2. 确认 `config` 中：

```r
.disease_exclusion_vars <- c( ...审阅排除名单... )

analysis_exclusion = list(
  disease_vars = .disease_exclusion_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
```

并同步从下列位置 **删掉** 同名变量：

- `incidence_batch$base_exclude_vars`（可并入 disease 名单）
- `incidence_batch$base_subgroup_vars`
- `subgroup$required_subgroup_vars` / `level_order`
- `logistic_*$clinical_factor_names` / `exclude_from_models`
- `imputation$table_s1_exclude_vars`
- `baseline_*$exclude_vars`

批量指标：用 `pipeline_indices_using_vars(.disease_exclusion_vars, .composite_index_vars)`
跳过疾病衍生暴露（整指标跳过）。

### 4b. 年龄亚组切点（与 disease_vars 同轮完成）

写 config 时同步落实 `.cursor/rules/age_subgroup_binary.mdc`：

1. **先查本疾病**常用年龄亚组界值（文献/指南），注释写入 config
2. **只配二分类**：`subgroup$age_cutoff`（及 `nhanes$age_cutoff` / 敏感性同值）
3. **禁止**无依据的 `age_group_cutoffs = c(30,45,60)` 四档
4. `level_order$Age_Group` 仅两级，与切点标签一致（如 `"< 65"` / `"≥ 65"`）

### 5. 流水线挂载检查

- `pipeline_*` 含 `analysis_exclusion`，且与 `baseline_pipelines.json` 一致（过 guard）
- 发病：`index` → `analysis_exclusion` → `imputation` → …
- 清掉旧 `by_index/`、`checkpoints/` 再重跑（旧结果可仍含泄漏列）

---

## 完成标准（自检）

- [ ] 原始表每一列都在 `_column_review.md` 有行
- [ ] 糖尿病类课题：`Albumin_Urine` / `HbA1c` / `Glucose` / `T2DM` / 降糖药等已在 `disease_vars`
- [ ] Model2 / 亚组 / clinical 名单无 `disease_vars` 交集
- [ ] `analysis_exclusion` 已配置且 pipeline 已挂块
- [ ] 年龄亚组为二分类：已查病种切点；无 `age_group_cutoffs`；`Age_Group` level_order 仅两级
- [ ] 用户可见：审阅文件路径 + 排除名单摘要

## 反例

- 只排除 `HbA1c`，却把 `Albumin_Urine` 留在 Model2（糖尿病课题）
- 不看 dabiao，直接复制上一病种 config 的 `disease_vars`
- 把血清 `Albumin` 因「名字像白蛋白」误加入 diabetes `disease_vars`，导致非成分场景误删
- 亚组森林照抄 NHANES 四档 `<30|30-44|45-59|≥60`，未按本疾病选定单一 `age_cutoff`
