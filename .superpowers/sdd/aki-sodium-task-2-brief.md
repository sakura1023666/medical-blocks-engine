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

