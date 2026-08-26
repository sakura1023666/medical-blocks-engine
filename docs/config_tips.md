# config_tips — 通用 Config 修改流程

> 适用所有 `configs/config_*.R` 套路。配合 [CONFIG_WORKFLOW.md](../.cursor/prompts/CONFIG_WORKFLOW.md) 在对话中 `@` 引用。

---

## AI 行为总则

1. **先读数据、后提问**：用户提供 RData 路径或 `colnames` 后，AI 自行推断人口学列名、Model1/Model2 候选、亚组变量、列映射类型；**不向用户重复确认**。
2. **最小提问集**：仅问下文「必问」项；其余一律走**默认规则**。
3. **改 config 前**：列出将修改的键名清单，用户确认后再改文件。
4. **改 config 后**：自动给出对应 `Rscript` 命令（Windows 路径含空格须加引号）。
5. **遵守** [BLOCKS_USAGE_GUIDE.md](../BLOCKS_USAGE_GUIDE.md)：配置驱动、不在 block config 加 `data_source`、不改 block 实现。

---

## 默认规则（无需向用户提问）

| 项 | 默认 |
|----|------|
| 跑哪些库 | **全部跑**（双库 → `--db both`；单库 → 对应 `run_*.R`） |
| 双库额外排除 | 暴露相关块中 **额外排除 `Hemoglobin`**（`index_exclude_vars` / `excluded_predictors` 等） |
| `column_mapping` | **始终 `enable = TRUE`**，按各库 `database_type` 设置 |
| 单因素 / 多因素阈值 | p<0.1 / p<0.05，**不改** |
| VIF 阈值与 exclude | 沿用模板 config，**不改** |
| Logistic 随机搜索 | 沿用模板（含 `require_triple_model_sig` 等），**不改** |
| pipeline blocks 列表 | **不增删、不调序** |
| ROC / RCS / 中介 / 亚组 | 模板里有什么保留什么，**不因用户未提及而删除** |
| checkpoint 路径 | 随 `output_dir` / 项目编号自动推导，**不单独问** |
| `data_clean$drop_columns` | **不主动问、不主动改** |
| Model1 / Model2 因子 | 沿用模板 + 闸门 B 自动对齐，**不单独问** |
| 亚组 / 别名 | 沿用模板 `subgroup` / `subgroup_var_aliases`，**不单独问** |

---

## 第 1 层：研究骨架（先定再动 config）

### 必问

1. **疾病编码**是什么？（如 `01`，写入 `project$disease_code`；用于产出路径第一层文件夹）
2. **暴露变量**叫什么？（NHANES 与 MIMIC/单库列名不同则分别记录，改 `index_var` 及所有 `*_index_var` / `response_vars` 引用）
3. **结局列名**是什么？**二分类取值**是什么（**参考组** / **病例组**）？

### 不问 · 自动处理

- **文献 ID**（PubMed ID / DOI / `literature_pmid`）— **不向用户提问**；沿用 config 模板或项目既定值
- 双库 → 自动在暴露相关排除列表中加入 `Hemoglobin`
- 库数量 → 默认全跑
- **输出目录** — 按套路自动命名，并同步 `project$disease` / checkpoint 前缀：

```
output_dir 命名规则：
  单库发病/预后：Output/{暴露}_{analysis_group}
  NHANES 单库：  Output/{暴露}_{analysis_group}_NHANES
  双库发病：     Output/{暴露}_{analysis_group}_dual
  双库 HF 聚类： Output/{主题}_dual_clustering（沿用模板风格时可保留 HF 前缀）
  双库 batch：   G:/02block_result/{疾病编码}_{disease}/{study_type}_{literature_pmid}/
                 （WSL：/mnt/g/02block_result/...；literature_pmid 取自 config，不问用户）

示例：
  暴露 Hematocrit，病例组 OA  → Output/Hematocrit_OA_dual
  暴露 BMI，病例组 OA，NHANES  → Output/BMI_OA_NHANES
  疾病编码 01，UI，PMID 38341157（config 内定）
    → G:/02block_result/01_Urinary_Incontinence/incidence_38341157/
```

### 按套路改哪些键

| 套路 | 必改键 |
|------|--------|
| **发病**（single / nhanes / dual） | `incidence$outcome_var`, `incidence$index_var`, `incidence$index_component_vars`, `incidence$index_exclude_vars`（双库加 Hemoglobin）, `logistic$index_var`, `prediction$index_vars`, `project$disease_code`, `project$analysis_group`, `project$reference_group`, `project$disease`, `project$output_dir`, `nhanes$cutoff_index_var`（NHANES）, 各块内 `index_var` / `response_vars` / `excluded_predictors` 中的暴露名 |
| **发病 batch**（dual_batch） | 上表发病键 + `.batch_project_root` / `incidence_batch$output_base` / `shared_ck_base` / `index_ck_base`；`literature_pmid` **仅改 config、不向用户问** |
| **预后**（survival_sae） | `survival$index_var`, `survival$time_var`, `survival$event_var`, `logistic$index_var`, `project$*`, `km_strata` 中与暴露相关的 strata 名（若模板写死指标名则同步替换） |
| **预后 batch** | `computed_indices` 清单 + `survival$index_var` 占位；详见 [SURVIVAL_BATCH_GUIDE.md](../SURVIVAL_BATCH_GUIDE.md)，**不改 worker 内 block 列表** |
| **HF 双库聚类** | `project$*`, `data$*` / `dual_db$*`, `hf_nonclinical_vars`（按库列名）, 聚类相关 `output_dir` |

---

## 第 2 层：数据入口

### 必问

1. 每个库的 **文件路径、RData 对象名、ID 列**（单库 1 组；双库 NHANES + MIMIC/eICU 各 1 组）
2. 若含 **NHANES**：调查权重三件套（`survey_weight` / `survey_cluster` / `survey_strata`）列名是否与模板不同？（相同则不改）

### 不问 · 自动处理

- `data_clean$drop_columns` — 不改
- `strip_id_columns_after_imputation` — 按 ID 列名自动补全常见项（`SEQN`, `subject_id`, `ID`）

### 主要改

- `data$rawdata_path`, `data$rawdata_obj`, `data$id_column`, `data$outcome_column`
- 双库：`dual_db$primary`, `dual_db$secondary`（及 `checkpoint_base` / `harmonization_dir` 与 output 一致）
- NHANES：`nhanes$survey_*`, `nhanes$exclude_cols`

---

## 第 3 层：列映射与双库对齐

### 不问 · 自动处理

- **`column_mapping$enable = TRUE`**（所有库）
- 从数据 **直接识别** Age / Sex / Gender / Race / Smoking 等人口学列，写入或校验 `demo_keywords`、`dual_db$harmonization` 相关项
- Model1 / Model2、亚组变量、别名 — **沿用模板**，闸门 B 运行时自动对齐

### 主要改（仅当数据与模板冲突时）

- `column_mapping$database_type`
- `dual_db$harmonization$index_component_vars`（与暴露一致）
- 暴露名替换触发的 `excluded_predictors` / `exclude_vars` 全局替换

---

## 第 4 层：分析细节

**全部默认，不向用户提问，不修改**，除非用户**显式**要求改阈值、删 block 或改 pipeline。

沿用模板中的：`univariate_*`, `multivariate_*`, `multicollinearity`, `logistic_*`, `pipeline_*`, `render_*`, pause 开关等。

---

## 第 5 层：确认与交付

### 不问 · 自动交付

1. **修改摘要**：表格式列出「键 → 旧值 → 新值」
2. **运行命令**（项目根目录执行，R 路径按用户环境）：

```powershell
cd "项目根目录"

# 双库发病
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_incidence_dual.R --db both

# NHANES 单库发病
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_incidence_nhanes.R

# 单库发病
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_incidence_single.R

# 单库预后
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_survival_sae.R

# HF 双库聚类
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_hf_dual_clustering.R

# 预后 batch（若已实现）
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_survival_batch.R --workers 8
```

3. 若仅换数据、结构不变：可建议 `--from <block>` 从检查点续跑（根据报错或用户说明，**不主动问**）

---

## AI 收到数据后的执行顺序

```
1. 识别 config 套路（对照 CONFIG_WORKFLOW 第一节表格）
2. load 用户数据 → colnames、结局 table、ID、NHANES 权重列（如有）
3. 仅提「第 1 层必问 + 第 2 层必问」；缺疾病编码/暴露/结局/路径时才问；**不问文献 ID**
4. 输出「拟修改键清单」→ 等用户确认
5. 改 config（全局替换暴露名；双库同步 primary/secondary；output_dir 按规则）
6. 给出 Rscript 命令
```

---

## 最小数据包（用户可提供任一）

```r
load("路径.RData")
names(对象名)                          # 或 colnames(对象名)
table(对象名$结局列, useNA = "ifany")   # 确认参考组/病例组水平
```

双库则 NHANES、MIMIC 各一份。
