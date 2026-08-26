# create-pipeline-config 示例

## 标准预后套路 pipeline$blocks

```r
c(
  "data_clean", "column_mapping", "imputation",
  "baseline_binary", "boxplot",
  "univariate_prognosis", "multivariate_prognosis", "multicollinearity",
  "train_validation",
  "ml_lightgbm", "ml_rf", "ml_aggregate", "ROC",
  "cox_binary", "rcs_prognosis", "segmented_cox_binary",
  "subgroup_prognosis", "mediation_prognosis"
)
```

## 标准发病套路 pipeline$blocks

```r
c(
  "data_clean", "column_mapping", "imputation",
  "baseline_binary", "boxplot",
  "univariate_incidence_binary", "multivariate_incidence_binary", "multicollinearity",
  "logistic_quartile_glm",
  "rcs_incidence", "subgroup_incidence", "mediation_incidence"
)
```

## NHANES 加权套路 pipeline$blocks

```r
c(
  "data_clean", "column_mapping", "imputation",
  "obj",
  "baseline_nhanes",
  "univariate_nhanes", "multivariate_nhanes",
  "logistic_quartile_glm",
  "rcs_nhanes", "subgroup_nhanes_weighted"
)
```

## 最小试跑（D04 预后数据）

```r
# configs/config_survival.R 片段
config <- list(
  data = list(
    rawdata_path   = "Data/D04_rt_CleanData.RData",
    rawdata_obj    = "rt",
    outcome_column = "fustatus",
    id_column      = "subject_id"
  ),
  project = list(
    study_type      = "prognosis",
    disease         = "COPD",
    database        = "MIMIC",
    analysis_group  = "Non-survivor",
    reference_group = "Survivor",
    output_dir      = "Output/D04_rt",
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step"
  ),
  survival = list(
    time_var  = "futime",
    event_var = "fustatus",
    index_var = "RAR"
  ),
  data_clean = list(missing_threshold = 0.3),
  column_mapping = list(enable = TRUE, database_type = "MIMIC"),
  imputation = list(method = "cart", m = 5L, max_iter = 5L, seed = 1234L),
  baseline_binary = list(
    sig_cutoff = 0.05,
    exclude_vars = c("futime", "subject_id", "Micu_Code"),
    pause_on_min_sig_vars = FALSE
  )
)

pipeline <- list(
  name   = "survival_d04_minimal",
  blocks = c("data_clean", "column_mapping", "imputation", "baseline_binary"),
  render_tables_after = c("imputation", "baseline_binary"),
  dual_db = list(enable = FALSE),
  checkpoint = list(enable = FALSE)
)
```

## 薄入口 run_survival.R

```r
root <- normalizePath(getwd(), winslash = "/")
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/config_survival.R"))

options(cli.hyperlink = FALSE)
run_pipeline(root, config = config, pipeline = pipeline)
```

试跑：

```bash
cd /path/to/Block-new
Rscript run_survival.R
```

---

## register_block 名 ↔ config 键 ↔ 源文件（常用）

| register_block | config 键 | 源文件 |
|----------------|-----------|--------|
| data_clean | data_clean | Blocks/02_data_clean/01block_data_clean.R |
| column_mapping | column_mapping | Blocks/01_column_mappings/01block_column_mapping.R |
| imputation | imputation | Blocks/03_imputation/01block_imputation.R |
| baseline_binary | baseline_binary | Blocks/04_baseline/01block_baseline_binary.R |
| baseline_multiclass | baseline_multiclass | Blocks/04_baseline/02block_baseline_multiclass.R |
| baseline_nhanes | baseline_nhanes | Blocks/04_baseline/03block_baseline_nhanes.R |
| boxplot | boxplot | Blocks/05_boxplot/01block_boxplot.R |
| univariate_prognosis | univariate_prognosis | Blocks/06_univariate/01block_univariate_prognosis.R |
| univariate_incidence_binary | univariate_incidence_binary | Blocks/06_univariate/02block_univariate_incidence_binary.R |
| multivariate_prognosis | multivariate_prognosis | Blocks/07_multivariate/01block_multivariate_prognosis.R |
| multivariate_incidence_binary | multivariate_incidence_binary | Blocks/07_multivariate/02block_multivariate_incidence_binary.R |
| multicollinearity | multicollinearity | Blocks/08_vif/01block_multicollinearity.R |
| correlation | correlation | Blocks/09_correlation/01block_correlation.R |
| cox_binary | cox_binary | Blocks/10_cox/01block_cox_binary.R |
| cox_quartile | cox_quartile | Blocks/10_cox/03block_cox_quartile.R |
| logistic_quartile_glm | logistic_quartile_glm | Blocks/11_logistic/01block_logistic_quartile_glm.R |
| logistic_binary_glm | logistic_binary_glm | Blocks/11_logistic/04block_logistic_binary_glm.R |
| obj | nhanes（主 config）+ obj 块读 ctx | Blocks/12_obj/01block_obj.R |
| cutoff | cutoff | Blocks/14_cutoff/01block_cutoff.R |
| rcs_prognosis | rcs_prognosis | Blocks/15_rcs/01block_rcs_prognosis.R |
| rcs_incidence | rcs_incidence | Blocks/15_rcs/02block_rcs_incidence.R |
| segmented_cox_binary | segmented_cox_binary | Blocks/16_weightcox/01block_segmented_cox_binary.R |
| train_validation | splitting（主 config） | Blocks/21_train_validation/01block_train_validation.R |
| ml_dt | ml_dt | Blocks/22_ml_models/01block_ml_dt.R |
| ml_rf | ml_rf | Blocks/22_ml_models/02block_ml_rf.R |
| ml_lightgbm | ml_lightgbm | Blocks/22_ml_models/09block_ml_lightgbm.R |
| ml_aggregate | ml_aggregate | Blocks/22_ml_models/17block_ml_aggregate.R |
| ROC | roc | Blocks/13_roc/01block_ROC.R |
| shap | shap | Blocks/17_shap/01block_shap.R |
| subgroup_prognosis | subgroup_prognosis | Blocks/18_subgroup/01block_subgroup_prognosis.R |
| subgroup_incidence | subgroup_incidence | Blocks/18_subgroup/02block_subgroup_incidence.R |
| mediation_prognosis | mediation_prognosis | Blocks/20_mediation/01block_mediation_prognosis.R |
| mediation_incidence | mediation_incidence | Blocks/20_mediation/02block_mediation_incidence.R |

新增 block 时：`grep register_block Blocks/` 确认名，config 键与之一致。

---

## 发病 vs 预后 config 差异

| 字段 | prognosis | incidence |
|------|-----------|-----------|
| project$study_type | `"prognosis"` | `"incidence"` |
| 时间/事件 | survival$time_var / event_var | 通常无 |
| 结局 | outcome_column 或 event_var | incidence$outcome_var / Disease |
| baseline 分层 | event_var（生存）或 baseline_binary$strata | outcome_column |
| 下游回归 | cox_* / rcs_prognosis | logistic_* / rcs_incidence |

---

## 从旧 config.R 迁移步骤

1. 复制兄弟项目 `config.R` → `configs/config_<type>.R`
2. 删除与本套路无关的段（如预后 config 删 `logistic`、`incidence`）
3. 改名：`baseline` → `baseline_binary`；拆 `univariate_multivariate`
4. 追加 `pipeline` 对象（只列要跑的 block）
5. 用 R 探查数据，核对 `rawdata_obj`、列名、结局分布
6. 首次试跑最小 pipeline（4 步），通过后再扩展 `pipeline$blocks`
