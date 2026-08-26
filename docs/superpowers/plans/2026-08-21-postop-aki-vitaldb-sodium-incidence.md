# Postop AKI VitalDB Sodium Incidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 VitalDB 单库跑通术前血钠 → 术后 48h AKI 发病分析，强制老师 Model 3 协变量，交付 Model 4（无 IOH）、Cr>4 敏感性、RCS 4 节点与老师三关键数。

**Architecture:** Prep 派生术中协变量并写出分析用 `dabiao`；`config_incidence_single.R` + `run_incidence_single.R` 跑主链（强制 `logistic$model1/2_factors`）；附加脚本从 checkpoint 重跑 Model 4 / Cr>4 / FDR 亚组与 `KEY_RESULTS`。不改 Blocks 核心，除非 FDR/RCS 配置缺口无法用脚本绕过。

**Tech Stack:** R, Medical Blocks (`run/incidence/run_incidence_single.R`), `rms`/`Hmisc` RCS, `jsonlite`

## Global Constraints

- 暴露：`Sodium`；结局：`judge` → 文案 **Postoperative AKI within 48 hours** / 组标签 **Postoperative AKI**
- Model 2（= 老师 Model 3）强制：`Age, Gender, BMI, Hypertension, T2DM, OpType, Approach, Hemoglobin, Albumin, Potassium, Creatinine`；**禁止** `icu_days`/`ICU_Days`/`UreaNitrogen`
- Model 4：Model 2 + `IntraopCrystalloid`, `IntraopColloid`, `OpDuration_min`, `Vasopressor_use`；**无 IOH**
- RCS：`nk_range = 4L`（Hmisc 默认结点 = 5/35/65/95 百分位）；报告拐点 1 位小数 + P-nonlinear
- 落盘根：`/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/`
- 引擎根：`/mnt/e/01block/01Block-new-Final`
- Git：**仅在用户明确要求时 commit**（本计划步骤中的 commit 默认跳过）
- 疾病列审阅：必须先有 `data/_column_review.md` 再定稿 config

## File Structure

| 路径 | 职责 |
|------|------|
| `.../incidence_38341157/data/_column_review.md` | 逐列保留/排除 |
| `.../data/vitaldb/prep_vitaldb_sodium.R` | 读原始 Rdata → 派生列 → 写 `D01_dabiao_VitalDB_sodium.RData` |
| `.../data/vitaldb/D01_dabiao_VitalDB_sodium.RData` | 分析用 `dabiao` |
| `.../config_incidence_single.R` | 单库发病主 config + pipeline |
| `.../run_model4_sensitivity_key.R` | Model 4、Cr>4、FDR 亚组、KEY_RESULTS |
| `.../Tables/Teacher_key_numbers.csv` + `KEY_RESULTS.md` | 老师三关键数 |
| （只读）`configs/templates/config_incidence_single.template.R` | 复制骨架 |
| （参考）`15_hearing_loss/.../config_incidence_liling.R` | 强制 `model1/2_factors` 写法 |

---

### Task 1: 列审阅 + Prep 派生 dabiao

**Files:**
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review.md`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/prep_vitaldb_sodium.R`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_dabiao_VitalDB_sodium.RData`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review_raw.txt`

**Interfaces:**
- Consumes: `D01_baseline_VitaIDB_CM(1).Rdata` 对象 `baseline`
- Produces: `dabiao` data.frame，含 `OpDuration_min`, `Vasopressor_use`, `Disease_Group`（因子：`No Postoperative AKI` / `Postoperative AKI`），保留 `judge`/`Sodium`/`ID` 与 Model 2/4 列

- [ ] **Step 1: 导出全列名**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript -e '
env <- new.env(parent = emptyenv())
load("/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_baseline_VitaIDB_CM(1).Rdata", envir = env)
writeLines(names(env$baseline),
  "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review_raw.txt")
cat("n_cols=", length(names(env$baseline)), "\n")
'
```

Expected: 打印 `n_cols= 84`

- [ ] **Step 2: 写 `_column_review.md`（逐列）**

按 `skills/review-raw-covariate-columns/SKILL.md`：每列 `保留|排除` + 一句话理由。  
**必须排除出自动协变量池（写入后续 `disease_vars` / `exclude_*`）的示例：**  
`judge`（结局）、`icu_days`/`ICU_Days`、`death_inhosp`/`Death_Inhosp`、`IntraopUO`、`UreaNitrogen`、重复时间戳/文本诊断列（`Diagnosis`/`OpName`/`PreopECG` 等不进模型）、`GFR`/`CreatinineClearance`（与 Cr 共线，Model 2 只留 `Creatinine`）。  
**Creatinine：** Table1/Model2 **保留**（老师强制混杂）；不进亚组分层名单。

- [ ] **Step 3: 写并运行 prep 脚本**

`prep_vitaldb_sodium.R` 核心逻辑：

```r
.in <- "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb"
env <- new.env(parent = emptyenv())
load(file.path(.in, "D01_baseline_VitaIDB_CM(1).Rdata"), envir = env)
d <- env$baseline
stopifnot(is.data.frame(d), all(c("ID", "Sodium", "judge") %in% names(d)))

d$OpDuration_min <- as.numeric(d$opend - d$opstart) / 60
vaso_cols <- c("IntraopEPH", "IntraopPHE", "IntraopEPI", "IntraopCA")
d$Vasopressor_use <- factor(
  as.integer(rowSums(sapply(vaso_cols, function(v) as.numeric(d[[v]]) > 0), na.rm = TRUE) > 0),
  levels = c(0L, 1L), labels = c("No", "Yes")
)
# 结局因子（分析组 = Postoperative AKI）
d$Disease_Group <- factor(
  ifelse(as.integer(d$judge) == 1L, "Postoperative AKI", "No Postoperative AKI"),
  levels = c("No Postoperative AKI", "Postoperative AKI")
)
# 二值 0/1 兼容列（部分块读 Disease）
d$Disease <- as.integer(d$Disease_Group == "Postoperative AKI")

dabiao <- d
save(dabiao, file = file.path(.in, "D01_dabiao_VitalDB_sodium.RData"))
cat("nrow=", nrow(dabiao), " AKI=", sum(dabiao$Disease == 1L), "\n")
```

Run:

```bash
Rscript "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/prep_vitaldb_sodium.R"
```

Expected: `nrow= 6388 AKI= 268`

- [ ] **Step 4: 冒烟检查派生列**

```bash
Rscript -e '
e <- new.env(); load("/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/vitaldb/D01_dabiao_VitalDB_sodium.RData", envir=e)
print(summary(e$dabiao$OpDuration_min))
print(table(e$dabiao$Vasopressor_use, useNA="ifany"))
print(table(e$dabiao$Disease_Group, useNA="ifany"))
'
```

Expected: 手术时长有限值；Vasopressor_use 为 No/Yes；Disease_Group 两水平。

---

### Task 2: 写 `config_incidence_single.R` + pipeline

**Files:**
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/config_incidence_single.R`
- Read: `configs/templates/config_incidence_single.template.R`
- Read: `/mnt/g/02block_result/15_hearing_loss/incidence_38341157/config_incidence_liling.R`（强制 factors 参考）

**Interfaces:**
- Consumes: `D01_dabiao_VitalDB_sodium.RData` / `dabiao`
- Produces: `config`, `pipeline` 供 `run_incidence_single.R`

- [ ] **Step 1: 从模板复制并改必改键**

根路径变量：

```r
.study <- "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157"
.m1 <- c("Age", "Gender")
.m2 <- c(
  "Age", "Gender", "BMI", "Hypertension", "T2DM",
  "OpType", "Approach", "Hemoglobin", "Albumin", "Potassium", "Creatinine"
)
.disease_exclusion_vars <- c(
  # 从 Task1 _column_review.md 抄最终名单；至少含：
  "icu_days", "ICU_Days", "death_inhosp", "Death_Inhosp",
  "UreaNitrogen", "IntraopUO", "GFR", "CreatinineClearance",
  "judge"  # 结局原列；分析用 Disease_Group/Disease
)
```

关键 config 片段（须写入完整 config，勿省略其它模板段）：

```r
config <- list(
  data = list(
    rawdata_path = file.path(.study, "data/vitaldb/D01_dabiao_VitalDB_sodium.RData"),
    rawdata_obj  = "dabiao",
    outcome_column = "Disease_Group",
    id_column = "ID",
    strip_id_columns_after_imputation = c("ID")
  ),
  project = list(
    name = "Postop_AKI_VitalDB_Sodium",
    disease_code = "26",
    disease = "Postoperative_AKI",
    disease_cn = "术后急性肾损伤",
    literature_pmid = "38341157",
    database = "VitalDB",
    database_type = "regular",
    study_type = "incidence",
    classification_mode = "binary",
    analysis_group = "Postoperative AKI",
    reference_group = "No Postoperative AKI",
    output_dir = .study,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  incidence = list(outcome_var = "Disease_Group", index_var = "Sodium"),
  logistic = list(
    index_var = "Sodium",
    model1_factors = .m1,
    model2_factors = .m2,
    model2_max_covariates = 20L
  ),
  index = list(enable = FALSE),
  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),
  # 年龄切点依据：无病种特异文献，用默认 65
  subgroup = list(
    age_cutoff = 65L,
    min_n = 20,
    required_subgroup_vars = c("Age_Group", "Gender", "BMI", "Hypertension"),
    level_order = list(Age_Group = c("< 65", "\u2265 65")),
    forest_xlim = c(0, 8)
  ),
  rcs_incidence = list(
    index_var = "Sodium",
    model1_factors = .m1,
    model2_factors = .m2,
    nk_range = 4L,          # 固定 4 节点 → Hmisc 默认 5/35/65/95
    cutoff_label_digits = 1L,
    histbin = 1
  ),
  logistic_quartile_glm = list(
    index_var = "Sodium",
    include_continuous_row = TRUE,
    model1_factors = .m1,
    # model2 由 logistic$model2_factors / ctx；禁止 random_search 改写主结论
    gate_enable = TRUE,
    phase = "screen",
    random_search = list(max_outer_attempts = 0L),  # 关闭搜索；若引擎不允许 0 则用 pause_enable=FALSE 且 factors 已强制
    pause_enable = FALSE
  ),
  multivariate_incidence_binary = list(
    write_model_factors = FALSE,  # 禁止覆盖强制名单
    required_predictors = .m2,
    pause_enable = FALSE
  ),
  baseline_binary = list(
    strata = "Disease_Group",
    include_vars = c(
      "Age", "Gender", "BMI", "Hypertension", "T2DM", "OpType", "Approach",
      "Hemoglobin", "Albumin", "Potassium", "Creatinine", "Sodium",
      "IntraopCrystalloid", "IntraopColloid", "OpDuration_min", "Vasopressor_use"
    ),
    exclude_vars = c("ID", "Age_Group", "judge", "Disease"),
    pause_enable = FALSE
  ),
  attrition = list(
    enable = TRUE,
    db_label = "VitalDB",
    title = "Postoperative AKI within 48 hours — VitalDB",
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE
  )
  # … 其余段从模板拷贝并改 index_var/MCMI→Sodium，pause_enable=FALSE
)
```

- [ ] **Step 2: pipeline 插入 `analysis_exclusion`，关闭中介（本轮非重点）**

```r
pipeline <- list(
  name = "incidence_postop_aki_vitaldb_sodium",
  blocks = c(
    "data_clean",
    "column_mapping",
    "analysis_exclusion",
    "imputation",
    "attrition",
    "baseline_binary",
    "univariate_incidence_binary",
    "multicollinearity_screen",
    "multivariate_incidence_binary",
    "multicollinearity_final",
    "simple_ROC",
    "logistic_quartile_glm",
    "logistic_tertile_glm",
    "logistic_binary_glm",
    "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs",
    "logistic_tertile_glm_rcs",
    "logistic_binary_glm_rcs",
    "logistic_quintile_glm_rcs",
    "subgroup_incidence"
  ),
  logistic_gate = list(enable = TRUE),
  render_tables_after = c(
    "imputation", "attrition", "baseline_binary",
    "univariate_incidence_binary", "multicollinearity_screen",
    "multivariate_incidence_binary", "multicollinearity_final",
    "simple_ROC",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quintile_glm",
    "rcs_incidence",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs",
    "logistic_binary_glm_rcs", "logistic_quintile_glm_rcs",
    "subgroup_incidence"
  ),
  render_figures_after = character(0),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = TRUE, dir = file.path(.study, "checkpoints"))
)
```

`column_mapping$enable = FALSE`（VitalDB 列已是分析名）；`database_type = "regular"`。

- [ ] **Step 3: dry source 配置**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript -e '
source("R/utils.R")
source("/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/config_incidence_single.R")
stopifnot(identical(config$logistic$model2_factors[length(config$logistic$model2_factors)], "Creatinine"))
stopifnot(!"UreaNitrogen" %in% config$logistic$model2_factors)
stopifnot(!"icu_days" %in% config$logistic$model2_factors)
stopifnot(isTRUE(config$rcs_incidence$nk_range == 4L) || identical(as.integer(config$rcs_incidence$nk_range), 4L))
stopifnot("analysis_exclusion" %in% pipeline$blocks)
cat("OK config\n")
'
```

Expected: `OK config`

---

### Task 3: 跑主分析流水线

**Files:**
- Use: `run/incidence/run_incidence_single.R`
- Use: `config_incidence_single.R`
- Writes under `.study`：`Tables/`, `Figures/`, `checkpoints/`, `step*/`

**Interfaces:**
- Consumes: Task 2 config
- Produces: Table 1/2、RCS 图、亚组图、checkpoint imputed

- [ ] **Step 1: 启动主跑**

```bash
cd /mnt/e/01block/01Block-new-Final
mkdir -p "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/logs"
MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
  Rscript run/incidence/run_incidence_single.R \
    --config "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/config_incidence_single.R" \
  2>&1 | tee "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/logs/main_$(date +%Y%m%d_%H%M%S).log"
```

Expected: 正常结束（exit 0）；若 `PAUSE_FOR_USER_DECISION` → 按 pause 原因修 config 后从 checkpoint `--from` 续跑。

- [ ] **Step 2: 验收强制协变量与术语**

```bash
# Table 2 / logistic 表应含 Creatinine，不应含 UreaNitrogen 或 ICU
rg -n "UreaNitrogen|ICU|icu_days|Creatinine|Postoperative AKI" \
  "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/Tables" | head -40
ls "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/Figures" | head
```

Expected: 组名含 Postoperative AKI；模型协变量含 Creatinine、无 BUN/ICU stay。

- [ ] **Step 3: 确认 RCS nk=4**

在日志中搜索 `Selected nk = 4`；或读 `ctx`/cutoff csv。若不存在，检查 `rcs_incidence$nk_range`。

---

### Task 4: Model 4 + Cr>4 敏感性 + FDR 亚组 + KEY_RESULTS

**Files:**
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/run_model4_sensitivity_key.R`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/Tables/Teacher_key_numbers.csv`
- Create: `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/KEY_RESULTS.md`

**Interfaces:**
- Consumes: checkpoint imputed（或 `Tables` 中主文 logistic 结果 + 重新 `glm`）
- Produces: Model4 表、敏感性表、FDR 森林图（若重绘）、三关键数文件

- [ ] **Step 1: 实现脚本骨架（从 imputed 读入）**

定位最新 imputed checkpoint（路径随 runner 而定，常见 `checkpoints/**/imputed*.rds` 或 step 目录）。脚本内：

```r
.study <- "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157"
.m2 <- c("Age","Gender","BMI","Hypertension","T2DM","OpType","Approach",
         "Hemoglobin","Albumin","Potassium","Creatinine")
.m4_extra <- c("IntraopCrystalloid","IntraopColloid","OpDuration_min","Vasopressor_use")
# load imputed df as `dat`；结局 0/1 为 Disease；暴露 Sodium
# 分类协变量 as.factor
fit_or <- function(dat, rhs) {
  f <- as.formula(paste("Disease ~ Sodium +", paste(rhs, collapse = "+")))
  fit <- glm(f, data = dat, family = binomial())
  co <- summary(fit)$coefficients
  list(fit = fit, row = co["Sodium", , drop = FALSE])
}
```

- [ ] **Step 2: Model 4 与 Cr>4**

```r
# Model2 复核
r2 <- fit_or(dat, .m2)
# Model4
r4 <- fit_or(dat, c(.m2, .m4_extra))
# 敏感性
dat_s <- dat[is.finite(dat$Creatinine) & dat$Creatinine <= 4, , drop = FALSE]
r2s <- fit_or(dat_s, .m2)
# 写出 CSV：OR = exp(Estimate), CI, P
```

表注固定句：「Model 4 未纳入 IOH（VitalDB MAP 波形待补）；解释为 secondary/sensitivity。」

- [ ] **Step 3: 四分位 Q2 P（与主文闸门一致）**

从主文 `Tables/` 中 logistic 闸门选定的 grouping 表读取 Q2 行 P；若需复算：

```r
# 使用与主表相同的 Group 列（若 checkpoint 有），否则 quantile 四分位
# 报告 Q2 vs Q1 的 Model2 P
```

若文稿切点为 138–140 且与等频四分位不一致：额外出一张 **固定切点** 敏感性表（切点写入表注），主 KEY_RESULTS 优先填 **主文闸门表** 的 Q2 P，并注明切点。

- [ ] **Step 4: RCS 拐点与 P-nonlinear**

从主跑 `rcs_incidence` 产物读取 primary cutoff；P-nonlinear 取 Model2 anova/lrtest（脚本内对 `rms::lrm(Disease ~ rcs(Sodium,4) + …)` 做非线性检验）。拐点格式：`round(x, 1)`。

- [ ] **Step 5: 亚组 FDR**

读取亚组结果 CSV 中各层 P / P-interaction；`p.adjust(..., method = "BH")`；写出 `Tables/Subgroup_FDR.csv`；若可调用现有 `subgroup_prepare_forest_plot_df`，重绘 Figure 3 且图注含「Benjamini–Hochberg FDR」。**不要**为做 FDR 大改 Blocks（本课题脚本级即可）。

- [ ] **Step 6: 写 KEY_RESULTS**

`Teacher_key_numbers.csv` 列：`metric,value,note`，至少三行：

1. `model2_sodium_continuous_OR_P`  
2. `model2_Q2_P`  
3. `rcs_inflection_and_p_nonlinear`  

`KEY_RESULTS.md` 用中文各写一句可读结论。

- [ ] **Step 7: 运行脚本**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/run_model4_sensitivity_key.R" \
  2>&1 | tee "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/logs/key_$(date +%Y%m%d_%H%M%S).log"
```

Expected: 三文件写出；无 error。

---

### Task 5: 终验对照 spec 成功标准

**Files:**
- Read: `docs/superpowers/specs/2026-08-21-postop-aki-vitaldb-sodium-incidence-design.md` §7

- [ ] **Step 1: 核对清单**

```bash
test -f "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/data/_column_review.md"
test -f "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/KEY_RESULTS.md"
test -f "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/Tables/Teacher_key_numbers.csv"
rg -n "Selected nk = 4|nk = 4" "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/logs" | head
rg -n "IOH|待补" "/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157" --glob '*.md' --glob '*.csv' | head
```

- [ ] **Step 2: 向用户汇报三关键数**

打开 `KEY_RESULTS.md`，把 OR/P、Q2 P、拐点与 P-nonlinear 贴进回复。

---

## Spec coverage (self-review)

| Spec 要求 | Task |
|-----------|------|
| 列审阅 + disease_vars | Task 1–2 |
| Prep：时长/升压药；无 IOH | Task 1 |
| incidence_single + 强制 Model 3 | Task 2–3 |
| Model 4 液体 mL + 时长 + 升压药 | Task 4 |
| RCS nk=4（5/35/65/95） | Task 2 `nk_range=4L` + Task 3/4 |
| Cr>4 敏感性 | Task 4 |
| FDR 亚组 | Task 4 |
| 术语 Postoperative AKI | Task 1–2 |
| KEY 三数 | Task 4–5 |
| 不做 PSM / IOH | 全局约束；无对应任务 |

**Placeholder scan：** 无 TBD；checkpoint 具体文件名在 Task 4 Step 1 用 `find` 解析（实现时写死找到的路径）。

**分位切点：** Task 4 Step 3 显式处理文稿 138–140 vs 引擎等频四分位。
