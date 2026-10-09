# Blocks 选型目录（写 config 用）

> 生成/同步：`python3 scripts/update_blocks_catalog.py`  ·  日期：2026-10-08  ·  register_block 数：480

分工：`docs/block操作手册.md` = 怎么跑研究；本文件 = **选哪个 block / 改哪些 config 键**；`docs/block_catalog/` = 程序员 search_blocks 只读导出（另一套）。

<!-- MANUAL:HOW_TO_USE -->
## 0. 怎么用这份文档

1. 先看 **§1 研究类型 → 默认套路**，选定 template。
2. 再看 **§5 变体对照**，避免选错 `*_nhanes` / `*_incidence` / `*_prognosis`。
3. 打开对应 template，改【必改】键；**默认不要改** `pipeline$blocks`。
4. 需要核对键名/前置条件时，用 **§8 Block 卡片** 定位，再回读 `Blocks/...` 文件头。
5. 程序员隔离跑批流程见 `docs/block操作手册.md`；本文件只做 **block / config 选型字典**。

约定：
- pipeline 里的名字 = **`register_block` 名**，不是 `.R` 文件名。
- AUTO 段由 `python3 scripts/update_blocks_catalog.py` 重生成；`<!-- MANUAL:... -->` 段可手改并会被保留。
<!-- /MANUAL:HOW_TO_USE -->

<!-- MANUAL:ROUTINES -->
## 1. 研究类型 → 默认套路

| 场景 | 推荐 template | study_type / 备注 | 心智模型 |
|---|---|---|---|
| 交叉滞后（三库/多库发病） | `configs/templates/config_cross_lagged_frailty_batch.template.R` | `54_cross_lagged_full` | 出版清单固定：Fig1–4 / S1–S5 / S11；表 T1/T2/S1/S3–S8；**必跑**敏感性 S9–S17.1（`phases/PUBLICATION_SLOTS.md`） |
| 双库预后 / 生存 | `configs/templates/config_survival_dual_batch.template.R` | `prognosis` | Cox / KM / 亚组 |
| 单库 NHANES 发病 | `configs/templates/config_incidence_nhanes_batch.template.R` | `incidence` + 权重 | survey design |
| 竞争风险（卒中等） | `configs/templates/config_competing_risk_stroke_batch.template.R` | competing | `55_competing_risk_full` |
| IPW 糖尿病-卒中 | `configs/templates/config_ipw_diabetes_stroke_batch.template.R` | IPW | `69_ipw_*` |
| CRM NHANES + MR | `configs/templates/config_crm_nhanes_mr_batch.template.R` | NHANES pub | `70_crm_nhanes_pub` |
| 两阶段 Transformer | `configs/templates/config_two_stage_transformer_stroke.template.R` | TST | `71_two_stage_transformer_stroke` |
| ML 双库 | `configs/templates/config_ml_dual_batch.template.R` | ml | `22_ml_models` 等；发病双库可设 `split_mode=dev_internal_ext`（大库 7:3 + 小库整库外验，单库/预后仍 `per_db_internal`） |
| 环境暴露 / VOC | `configs/templates/config_environment_dkd_batch.template.R` | environment | `35–46` + environment full |
| 轨迹预后 | `configs/templates/config_trajectory_prognosis_batch.template.R` | trajectory | `53_trajectory_*` |

专题设计说明（非选型字典）：`docs/superpowers/specs/`。
<!-- /MANUAL:ROUTINES -->

<!-- MANUAL:GLOBAL_KEYS -->
## 2. 全局 config 地图（跨 block 共用）

| 节 | 常见键 | 谁在用（典型） |
|---|---|---|
| `project` | `study_type`, `classification_mode`, `disease*`, `analysis_group`, `reference_group`, `output_dir`, `use_step_prefixed_block_dirs` | 几乎所有 block |
| `data` | `rawdata_path`, `rawdata_obj`, `id_column`, `outcome_*` | 洗数 / 插补 / 基线 |
| `incidence` | `outcome_var`, `index_var`, `index_*` | 发病 logistic / 单多因素 |
| `survival` | `time_var`, `event_var`, `index_var` | Cox / KM / 预后亚组 |
| `nhanes` | `survey_weight`, `survey_cluster`, `survey_strata`, `exclude_cols` | `*_nhanes*` / weighted |
| `dual_db` | `primary` / `secondary` 路径与映射 | `00_dual_db/*` |
| `ml_batch` / `incidence_batch` | `split_mode`：双 regular 库默认 `dev_internal_ext`（人多库训练/内验、人少库整库外验、冻结主库模型）；含 NHANES 时默认 `per_db_internal` | `21_train_validation` / `24_ml_dual/ml_eval_external` |
| `index` | `enable`, `only`, `skip`, `digits` | `00_index` |
| `column_mapping` | `enable`, `database_type` | `01_column_mappings` |
| `imputation` | `method`, `m`, thresholds | `03_imputation` |
| `data_clean` | `missing_threshold`, `drop_columns` | `02_data_clean` |
| `plot` | `font_family` | 出图块 |
| `covariate_policy` | `force_age`（默认 TRUE）、`force_sex`（默认 FALSE）、`force_include` | VIF / Model1–2 / Gate B |

单块专有键见 §8 卡片的 `config$<block_id>`。
<!-- /MANUAL:GLOBAL_KEYS -->

<!-- MANUAL:PITFALLS -->
## 3. 常见坑（手维）

- `baseline_binary`：分层列必须恰好 2 水平，否则 pause/stop。
- 选 `*_nhanes_weighted` 前确认 `nhanes$survey_*` 列名与 `exclude_cols`。
- 双库：引擎内部槽位仍常称 nhanes(主)/mimic(副)；子目录名跟 `dual_db$*$name`。
- 竞争风险 / IPW / TST：优先整包 template，不要从零拼 `55/69/70/71`。
- 研究区勿手改母版 `pipeline$blocks` 绕过 `add_block`（见操作手册）。
- KM 与 Table 2 必须共用 `pipeline_quartile_factor`（左闭右开）；禁止 `cut(right=TRUE)` 或 28 天 landmark 当总事件。
- Cox/logistic 表 P 值用 `pub_format_p_cell`（p<0.001 写 `<0.001`）；禁止把 `9e-04` 标成 `P<0.0001`。分组列名是 `N (%)` 不是 `Case (%)`。
- 中介 LM Table S8 的 Model1/Model2 必须取 Cox 协变量（`pipeline_mediation_lm_adjustors`），禁止写死下标 `1,15:18`。
- `Ventilation`（ever）与 `Ventilation_Hour`（小时）不得映射成同一列；双库统一用 ever（No/Yes），小时不得进共有列 / Table 1 / Model2。
- `--no-skip` 必须重算 Gate A（删 `gate_a_columns.rds`）并重建共享层；旧缓存若把 `Ventilation_Hour` 当共有列，会把 eICU 的 `Ventilation` 整列滤掉。`--no-skip` 成功后应覆盖已有 `【success】<ix>`，不能因「目标已存在」留下裸名 `by_index/<ix>`。`--sensitivity-only --no-skip` 必须重跑已成功 SA。
- 轻量敏感性默认只有 Yes/No + 年龄（继承插补队列）。`SA_complete_case` 仅当 `sensitivity_suite$complete_case` 显式 TRUE：插补前 `mapped`/`cleaned` listwise（暴露 + 时间/结局 + 锁定 Model1/2）。默认 FALSE，勿默认打开。
- Figure 1 流程图必须走 `pipeline_pdf_device`（cairo_pdf 嵌 Times New Roman）；禁止对 `pdf()` 传 `"Times New Roman"`（Linux 报 unknown family）。
- 双库附表编号与正表相同：同一角色两库共用 S 号（`Table S1-eICU` + `Table S1-MIMIC` 都是插补）。禁止 `compact` 把根目录压成 S1…S22（一库一号）。森林图禁止整表 `clip=on`，轴端须留白，否则 0.2 的「0」会被裁掉。
- Table S1（插补前后）默认**不**放 `fustatus` / `event_var` / `outcome_column`：S1 在 `prognosis_outcome_landmark` 之前，与主文 28 天 Table 1 存活人数会对不上。勿为「表更全」再写回结局状态行。
- 发病 ML 双库 `split_mode=dev_internal_ext`：课题 config 后半段禁止再写回 `per_db_internal`。次库 `external_all` 时插补不得把 train/test rbind 翻倍。UV/VIF/LASSO 只在主库训练集；Table 2 logistic 仍两库全集。单库套路不走此口径。
- `simple_ROC` 默认 `mode=multivariable`；预后模板默认 `covariate_source=vif_final`（完整 VIF 临床集，不跟 Table 2 Gate C 剪枝短名单）；发病等可用 `locked`（与 Table2/Gate B 一致）。`locked` 在双库 `dual_db_cox_unified_locked` 后优先 `Model2Factors`。锁定/VIF 为空须硬停。ML 管线若把 ROC 放在 VIF 前，模板须显式 `mode=univariate`。预后结局用 `survival$event_var`。
- `plot_cutoff`（Figure S1）默认 `annotate_cutoff=maxstat`：图上标 surv_cutpoint 真实最优点；上游 RCS/配置切点另存，不钉虚线。
- 实验室关联 Table S8：`BAR ~ scale(lab)`，列名须为 `β per 1-SD`；禁止未标准化的原始量纲（PH 等会出现 |β|≈十几）。分位基线 Table S10 须剔除暴露公式组分（BAR→BUN/Albumin）。分段 Cox 表脚注须说明：段内 HR=段内 median high vs low，LLR 可与各段 P 值不一致。
- 双库汇总 `by_index/<ix>/Figures`（含 `【success】*`）**只保留拼图**（`Figure N. …` / `Figure SN. …`）；分库底稿只留在 `<db>/Figures`。`dual_db$combine_figures$remove_singles` 默认 TRUE，拼图后会硬清扫 `-eICU`/`-MIMIC` 单图。禁止把课题一次性 `tmp_*`/`rerun_*.R` 留在引擎根目录当“正式脚本”。
- 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。
- `image_information/*.md` 全项目统一：`## 图面说明`（详细；纳排图须逐步人数）+ `## 分析上下文`；**禁止**「标识」「技术」两段；入口 `R/pub_figure_export.R`，旧结果补刷 `run/pub/refresh_image_information.R`。
- 强制协变量默认**只 Age**（`covariate_policy$force_age=TRUE`，`force_sex=FALSE`）。Gender 须 UV/MV/VIF 自然入选，或课题显式 `force_sex=TRUE`。
- `exclude_from_models` 默认**不**含 BMI/Weight/Height；人体测量去留交给 VIF / anthropometric 共线性协调。若课题仍要硬踢，再在 `logistic_covariates$exclude_from_models` 显式写出。
- 敏感性勿手写固定场景名单。Yes/No 从两库 Table 1 动态生成（Yes n>50）+ 可配 `age_cutoff`；忽略旧 `scenarios`。轻量只重跑 Table 1/2，目录 `【success】`/`【failed】`，表 S12/S13。
<!-- /MANUAL:PITFALLS -->

<!-- BEGIN AUTO:dir_index -->
## 4. 目录速览（AUTO）

| 目录 | 块数 | register_block（节选） |
|---|---:|---|
| `00_attrition` | 1 | `attrition_flowchart` |
| `00_dual_db` | 5 | `dual_db_column_harmonize`, `dual_db_covariate_harmonize`, `dual_db_logistic_branch_harmonize`, `dual_db_logistic_main_table_realign`, `dual_db_logistic_scheme_harmonize` |
| `00_index` | 1 | `index` |
| `01_column_mappings` | 1 | `column_mapping` |
| `02_data_clean` | 1 | `data_clean` |
| `03_imputation` | 4 | `analysis_exclusion`, `imputation`, `prognosis_outcome_landmark`, `trim_index_extreme` |
| `04_baseline` | 3 | `baseline_binary`, `baseline_multiclass`, `baseline_nhanes` |
| `05_boxplot` | 1 | `boxplot` |
| `06_univariate` | 4 | `univariate_incidence_binary`, `univariate_incidence_multiclass`, `univariate_nhanes`, `univariate_prognosis` |
| `07_multivariate` | 8 | `multivariate_covariate_resolve`, `multivariate_incidence_binary`, `multivariate_incidence_harmonized`, `multivariate_incidence_multiclass`, `multivariate_nhanes`, `multivariate_nhanes_harmonized`, `multivariate_prognosis`, `multivariate_prognosis_harmonized` |
| `08_vif` | 5 | `multicollinearity`, `multicollinearity_final`, `multicollinearity_nhanes_final`, `multicollinearity_nhanes_screen`, `multicollinearity_screen` |
| `09_correlation` | 1 | `correlation` |
| `10_cox` | 8 | `cox_binary`, `cox_interaction`, `cox_ml_continuous_batch`, `cox_quartile`, `cox_quintile`, `cox_sextile`, `cox_subphenotype`, `cox_tertile` |
| `11_logistic` | 26 | `logistic_binary_clogit`, `logistic_binary_glm`, `logistic_binary_glm_rcs`, `logistic_binary_iptw_weighted`, `logistic_binary_nhanes_weighted`, `logistic_binary_nhanes_weighted_rcs`, `logistic_environment_glm`, `logistic_quartile_clogit`, …(+18) |
| `12_obj` | 1 | `obj` |
| `13_roc` | 2 | `ROC`, `simple_ROC` |
| `14_cutoff` | 1 | `cutoff` |
| `15_rcs` | 5 | `rcs_incidence`, `rcs_iptw_weighted`, `rcs_nhanes`, `rcs_prognosis`, `rcs_prognosis_by_group` |
| `16_weightcox` | 4 | `segmented_cox_binary`, `segmented_cox_quartile`, `segmented_cox_quintile`, `segmented_cox_tertile` |
| `17_shap` | 1 | `shap` |
| `18_subgroup` | 8 | `subgroup_environment_or`, `subgroup_incidence`, `subgroup_incidence_continuous`, `subgroup_iptw_weighted`, `subgroup_nhanes_weighted`, `subgroup_prognosis`, `subgroup_treatment_forest`, `unsupervised_clustering_table` |
| `19_feature_selection` | 10 | `feature_selection_bagged_trees`, `feature_selection_bayesian`, `feature_selection_boruta`, `feature_selection_consensus`, `feature_selection_lasso`, `feature_selection_lasso_cox`, `feature_selection_lvq`, `feature_selection_random_forest`, …(+2) |
| `20_mediation` | 12 | `mediation_ers_environment`, `mediation_incidence`, `mediation_longitudinal`, `mediation_nhanes_weighted`, `mediation_prognosis`, `mediation_subgroup_router`, `modmed_data_prep`, `modmed_mediation_batch`, …(+4) |
| `21_train_validation` | 1 | `train_validation` |
| `22_ml_models` | 26 | `cart_decision_path`, `ml_adaboost`, `ml_aggregate`, `ml_catboost`, `ml_coxboost`, `ml_dt`, `ml_enet`, `ml_enet_cox`, …(+18) |
| `23_ml_performance` | 1 | `performance_ml` |
| `24_ml_dual` | 10 | `ml_assoc_bundle`, `ml_assoc_covariate_resolve`, `ml_eval_external`, `ml_feature_selection_bundle`, `ml_id_deduplicate`, `ml_inherit_primary_features`, `ml_logistic_multi_index_bundle`, `ml_models_bundle`, …(+2) |
| `24_ml_supplementary` | 1 | `supplementary_ml` |
| `25_shiny` | 2 | `shiny_dynnom`, `shiny_ml_app` |
| `26_trajectory` | 6 | `trajectory_chisq`, `trajectory_dynpred`, `trajectory_gbmt`, `trajectory_jlcm`, `trajectory_plot_gbmt`, `trajectory_plot_jlcm` |
| `27_KM` | 3 | `km_binary`, `km_continuous_router`, `km_strata` |
| `28_plot` | 2 | `plot_cutoff`, `plot_histogram` |
| `29_chord_diagram` | 1 | `chord_diagram` |
| `30_lca` | 1 | `lca` |
| `31_subtype_viz` | 1 | `subtype_viz` |
| `32_stepp` | 1 | `stepp_prognosis` |
| `33_composite_risk_score` | 1 | `composite_risk_cox` |
| `34_IPTW` | 2 | `iptw_association`, `iptw_balance` |
| `35_environment_function` | 10 | `environment_lod_screen`, `environment_subgroup_search`, `environment_voc_clinical_gate`, `environment_voc_corrplot`, `environment_voc_extreme_trim`, `environment_voc_log_transform`, `prepare_environment_dkd_data`, `process_environment_data`, …(+2) |
| `36_capability` | 1 | `sensitivity_scenarios` |
| `36_environment_glm` | 1 | `glm_environment_quartile` |
| `37_environment_wqs` | 1 | `wqs_environment` |
| `38_environment_bkmr` | 2 | `bkmr_analysis`, `bkmr_fit` |
| `39_environment_qgcomp` | 1 | `qgcomp_environment` |
| `40_environment_descriptive` | 2 | `environment_characteristics`, `voc_correlation` |
| `41_environment_target` | 1 | `environment_target_enrichment` |
| `42_environment_single` | 1 | `environment_single_exposure_transform` |
| `43_dynamic_causal` | 2 | `dynamic_causal_cox_total`, `dynamic_causal_index_compute` |
| `44_multimorbidity` | 2 | `multimorbidity_baseline_category`, `multimorbidity_gee_cognition` |
| `45_multimodal` | 1 | `multimodal_early_fusion` |
| `46_environment_omics` | 5 | `env_gsea`, `env_ml_gene_screen`, `env_mr_docking`, `env_network_toxicology`, `env_scrna_summary` |
| `47_dynamic_causal_full` | 4 | `dynamic_causal_analysis_filter`, `dynamic_causal_cox_baseline`, `dynamic_causal_meta_merge`, `dynamic_causal_rcs_change` |
| `48_multimorbidity_full` | 4 | `multimorbidity_gee_interaction`, `multimorbidity_gee_stratified`, `multimorbidity_kml3d_trajectory`, `multimorbidity_sensitivity_suite` |
| `49_multimodal_full` | 2 | `multimodal_dl_shap`, `multimodal_omics_preprocess` |
| `50_complex_network` | 5 | `complex_network_bootnet`, `complex_network_covariate_residual`, `complex_network_descriptive`, `complex_network_ggm`, `complex_network_publication_tables` |
| `51_bayesian_comorbidity` | 7 | `bayesian_bodn`, `bayesian_body_clock`, `bayesian_bsc_aging`, `bayesian_bsc_clocks`, `bayesian_health_octo_suite`, `bayesian_outcome_validate`, `bayesian_roc_calibration` |
| `52_trajectory_incidence` | 8 | `trajectory_creatinine_pct`, `trajectory_lcmm_external_validate`, `trajectory_lcmm_fit`, `trajectory_lcmm_mpcmp_plot`, `trajectory_outcome_adjusted`, `trajectory_outcome_models`, `trajectory_prepare_wide_rdata`, `trajectory_wide_to_long` |
| `53_trajectory_prognosis_full` | 8 | `trajectory_baseline_by_class`, `trajectory_calc_28d_index`, `trajectory_dynpred_individual`, `trajectory_jlcm_discovery_validate`, `trajectory_km_class`, `trajectory_piecewise_cox`, `trajectory_subgroup_class`, `trajectory_weibull_compare` |
| `54_cross_lagged_full` | 21 | `cross_lagged_biomarker_cor`, `cross_lagged_change_logistic`, `cross_lagged_corr_table`, `cross_lagged_country_year_bar`, `cross_lagged_cox_frailty`, `cross_lagged_fi_compute`, `cross_lagged_fig1_group`, `cross_lagged_forest_or`, …(+13) |
| `55_competing_risk_full` | 18 | `competing_baseline_quartile`, `competing_baseline_trajectory`, `competing_cif_plot`, `competing_cox_sensitivity`, `competing_finegray`, `competing_flowchart`, `competing_index_exposure`, `competing_lmm_trajectory`, …(+10) |
| `56_ai_clinical_full` | 9 | `ai_cases_prepare`, `ai_guideline_audit`, `ai_lab_interpret`, `ai_llm_evaluate`, `ai_llm_multimodel`, `ai_multiround_sim`, `ai_order_robustness`, `ai_reader_comparison`, …(+1) |
| `57_dual_incidence_mr_full` | 10 | `crm_cox_mortality`, `crm_gout_strata`, `crm_nhanes_weighted`, `crm_ordinal_logistic`, `crm_rcs_sua`, `mr_egger_presso`, `mr_pleiotropy`, `mr_sensitivity`, …(+2) |
| `58_medication_regimen_full` | 7 | `medication_chemo_strata`, `medication_composite_risk`, `medication_descriptive`, `medication_km_treatment`, `medication_literature_targets`, `medication_stepp_strata`, `medication_trial_comparisons` |
| `59_markov_cognitive_full` | 8 | `markov_apoe_le_difference`, `markov_apoe_lifestyle`, `markov_life_expectancy`, `markov_life_table_figure`, `markov_msm_bootstrap`, `markov_msm_fit`, `markov_sensitivity_glmm`, `markov_state_prep` |
| `60_cdc_wonder_cits_full` | 8 | `cdc_wonder_fetch`, `cits_aggregate_monthly`, `cits_model_fit`, `cits_model_full`, `cits_plot`, `cits_publication_tables`, `cits_sensitivity`, `cits_sensitivity_extended` |
| `61_network_temperature_full` | 9 | `network_temp_centrality`, `network_temp_cohort_summary`, `network_temp_compute`, `network_temp_ggm_fit`, `network_temp_literature_validate`, `network_temp_mixed_model`, `network_temp_outcome_assoc`, `network_temp_prepare_long`, …(+1) |
| `62_sem_chain_mediation_full` | 9 | `sem_chain_mediation`, `sem_cox_baseline`, `sem_cox_chain_mediation`, `sem_data_prep`, `sem_descriptive`, `sem_literature_validate`, `sem_path_lavaan`, `sem_sensitivity`, …(+1) |
| `63_ai_medical_qa_full` | 8 | `ai_qa_cot_eval`, `ai_qa_dataset_summary`, `ai_qa_model_ranking`, `ai_qa_prepare`, `ai_qa_prompt_compare`, `ai_qa_prompt_templates`, `ai_qa_statistics`, `ai_qa_table4_validate` |
| `64_causal_forest_trajectory_full` | 9 | `cftraj_causal_forest`, `cftraj_circs_compute`, `cftraj_lcmm_episodic`, `cftraj_lcmm_fit`, `cftraj_multinomial`, `cftraj_sensitivity`, `cftraj_subgroup_viz`, `cftraj_trajectory_validate`, …(+1) |
| `65_incidence_prepost_full` | 8 | `prepost_data_prep`, `prepost_descriptive`, `prepost_domain_slopes`, `prepost_literature_validate`, `prepost_lmm_fit`, `prepost_sensitivity`, `prepost_subgroup_age`, `prepost_visualize` |
| `66_target_trial_full` | 9 | `tte_bootstrap_ci`, `tte_data_prep`, `tte_descriptive`, `tte_literature_validate`, `tte_pooled_logistic`, `tte_risk_difference`, `tte_sensitivity`, `tte_stratified`, …(+1) |
| `67_transformer_shortseq_full` | 10 | `trf_calibration`, `trf_causal_discovery`, `trf_data_prep`, `trf_early_detection`, `trf_external_val`, `trf_feature_reduce`, `trf_literature_validate`, `trf_multicenter_val`, …(+2) |
| `68_dual_change_score_full` | 8 | `dcs_bivariate_dcsm`, `dcs_data_prep`, `dcs_depression_to_memory`, `dcs_descriptive`, `dcs_literature_validate`, `dcs_memory_to_depression`, `dcs_sensitivity`, `dcs_verbal_fluency` |
| `69_ipw_diabetes_stroke_full` | 9 | `ipw_diabetes_exposure`, `ipw_diabetes_flowchart`, `ipw_jin_composite_risk`, `ipw_literature_targets`, `ipw_overlap_weights`, `ipw_pub_export`, `ipw_subgroup_km_pub`, `ipw_surv_calibration_roc`, …(+1) |
| `70_crm_nhanes_pub` | 13 | `crm_mr_figures`, `crm_mr_literature`, `crm_multivariate_prognosis`, `crm_nhanes_baseline_weighted`, `crm_nhanes_cox_pub`, `crm_nhanes_derive`, `crm_nhanes_flowchart`, `crm_nhanes_km_pub`, …(+5) |
| `71_two_stage_transformer_stroke` | 12 | `tst_calibration_dca`, `tst_cohort`, `tst_external`, `tst_landmark`, `tst_literature_validate`, `tst_pub_export`, `tst_repo_a1`, `tst_shap`, …(+4) |
| `72_incidence_prognosis_two_stage` | 3 | `ip_cohort_sle_aki`, `ip_stage2_cohort_28d`, `threshold_logistic` |
| `73_ml_nafld_cm` | 6 | `ml_nafld_external_bridge`, `ml_nafld_feature_spaces`, `ml_nafld_nested_cv`, `ml_nafld_omics_display`, `ml_nafld_pub_finalize`, `ml_nafld_score_compare` |
| `74_pa_mobility_cognitive_full` | 19 | `pamob_assemble_charls`, `pamob_assemble_nhanes`, `pamob_baseline_charls`, `pamob_baseline_nhanes`, `pamob_cognition_long`, `pamob_concept_fig1`, `pamob_contextual_inventory`, `pamob_contrast_preset`, …(+11) |
| `75_osteo_dxa_qct` | 3 | `diagnostic_vs_fracture`, `dxa_qct_agreement`, `modality_discordance_profile` |
| `76_cum_egdr_kmeans_ckm_full` | 11 | `ckm_attrition_flowchart`, `ckm_pub_finalize`, `ckm_stroke_data_ingest`, `cum_exposure_build`, `kmeans_elbow_bivar`, `kmeans_trajectory_panels`, `logistic_cum_index_bundle`, `rcs_ckm_strata_panels`, …(+3) |
| `77_gallstone_nomogram_full` | 13 | `gallstone_assoc_or_panels`, `gallstone_data_ingest`, `gallstone_dca_cic`, `gallstone_flowchart`, `gallstone_lasso_onese`, `gallstone_mv_nomogram`, `gallstone_pub_finalize`, `gallstone_rcs_panels`, …(+5) |

<!-- END AUTO:dir_index -->

<!-- BEGIN AUTO:variants -->
## 5. 变体对照（AUTO）

按家族对照选型（pipeline 写 **register_block 名**，不是文件名）。

### `baseline_*`（3）

| register_block |
|---|
| `baseline_binary` |
| `baseline_multiclass` |
| `baseline_nhanes` |

### `competing_*`（18）

| register_block |
|---|
| `competing_baseline_quartile` |
| `competing_baseline_trajectory` |
| `competing_cif_plot` |
| `competing_cox_sensitivity` |
| `competing_finegray` |
| `competing_flowchart` |
| `competing_index_exposure` |
| `competing_lmm_trajectory` |
| `competing_mixed_cox` |
| `competing_models_123` |
| `competing_models_123_death` |
| `competing_ph_calibration` |
| `competing_pub_export` |
| `competing_rcs` |
| `competing_stratified` |
| `competing_supp_tables` |
| `competing_trajectory_cluster` |
| `competing_tyg_compute` |

### `cox_*`（8）

| register_block |
|---|
| `cox_binary` |
| `cox_interaction` |
| `cox_ml_continuous_batch` |
| `cox_quartile` |
| `cox_quintile` |
| `cox_sextile` |
| `cox_subphenotype` |
| `cox_tertile` |

### `crm_*`（18）

| register_block |
|---|
| `crm_cox_mortality` |
| `crm_gout_strata` |
| `crm_mr_figures` |
| `crm_mr_literature` |
| `crm_multivariate_prognosis` |
| `crm_nhanes_baseline_weighted` |
| `crm_nhanes_cox_pub` |
| `crm_nhanes_derive` |
| `crm_nhanes_flowchart` |
| `crm_nhanes_km_pub` |
| `crm_nhanes_ordinal_pub` |
| `crm_nhanes_pub_align` |
| `crm_nhanes_pub_deliverables` |
| `crm_nhanes_rcs_pub` |
| `crm_nhanes_subgroup_supp` |
| `crm_nhanes_weighted` |
| `crm_ordinal_logistic` |
| `crm_rcs_sua` |

### `environment_*`（9）

| register_block |
|---|
| `environment_characteristics` |
| `environment_lod_screen` |
| `environment_single_exposure_transform` |
| `environment_subgroup_search` |
| `environment_target_enrichment` |
| `environment_voc_clinical_gate` |
| `environment_voc_corrplot` |
| `environment_voc_extreme_trim` |
| `environment_voc_log_transform` |

### `ipw_*`（9）

| register_block |
|---|
| `ipw_diabetes_exposure` |
| `ipw_diabetes_flowchart` |
| `ipw_jin_composite_risk` |
| `ipw_literature_targets` |
| `ipw_overlap_weights` |
| `ipw_pub_export` |
| `ipw_subgroup_km_pub` |
| `ipw_surv_calibration_roc` |
| `ipw_weighted_km_pub` |

### `logistic_*`（27）

| register_block |
|---|
| `logistic_binary_clogit` |
| `logistic_binary_glm` |
| `logistic_binary_glm_rcs` |
| `logistic_binary_iptw_weighted` |
| `logistic_binary_nhanes_weighted` |
| `logistic_binary_nhanes_weighted_rcs` |
| `logistic_cum_index_bundle` |
| `logistic_environment_glm` |
| `logistic_quartile_clogit` |
| `logistic_quartile_glm` |
| `logistic_quartile_glm_rcs` |
| `logistic_quartile_iptw_weighted` |
| `logistic_quartile_nhanes_weighted` |
| `logistic_quartile_nhanes_weighted_rcs` |
| `logistic_quintile_clogit` |
| `logistic_quintile_glm` |
| `logistic_quintile_glm_rcs` |
| `logistic_rcs_cutoff_nhanes_weighted` |
| `logistic_sextile_clogit` |
| `logistic_sextile_glm` |
| `logistic_subphenotype` |
| `logistic_tertile_clogit` |
| `logistic_tertile_glm` |
| `logistic_tertile_glm_rcs` |
| `logistic_tertile_iptw_weighted` |
| `logistic_tertile_nhanes_weighted` |
| `logistic_tertile_nhanes_weighted_rcs` |

### `mediation_*`（6）

| register_block |
|---|
| `mediation_ers_environment` |
| `mediation_incidence` |
| `mediation_longitudinal` |
| `mediation_nhanes_weighted` |
| `mediation_prognosis` |
| `mediation_subgroup_router` |

### `ml_*`（41）

| register_block |
|---|
| `ml_adaboost` |
| `ml_aggregate` |
| `ml_assoc_bundle` |
| `ml_assoc_covariate_resolve` |
| `ml_catboost` |
| `ml_coxboost` |
| `ml_dt` |
| `ml_enet` |
| `ml_enet_cox` |
| `ml_eval_external` |
| `ml_feature_selection_bundle` |
| `ml_gbmsurv` |
| `ml_id_deduplicate` |
| `ml_inherit_primary_features` |
| `ml_knn` |
| `ml_lightgbm` |
| `ml_logistic` |
| `ml_logistic_multi_index_bundle` |
| `ml_mboost_cox` |
| `ml_mlp` |
| `ml_models_bundle` |
| `ml_nafld_external_bridge` |
| `ml_nafld_feature_spaces` |
| `ml_nafld_nested_cv` |
| `ml_nafld_omics_display` |
| `ml_nafld_pub_finalize` |
| `ml_nafld_score_compare` |
| `ml_realmlp` |
| `ml_realtabpfn_2_5` |
| `ml_rf` |
| `ml_ridge_cox` |
| `ml_rsf` |
| `ml_rsvm` |
| `ml_stratified_reference_profile` |
| `ml_survivalsvm` |
| `ml_tablcl_v2` |
| `ml_tabpfn` |
| `ml_tabpfnv2` |
| `ml_vif_train_test` |
| `ml_xgboost` |
| `ml_xgbsurv` |

### `multivariate_*`（8）

| register_block |
|---|
| `multivariate_covariate_resolve` |
| `multivariate_incidence_binary` |
| `multivariate_incidence_harmonized` |
| `multivariate_incidence_multiclass` |
| `multivariate_nhanes` |
| `multivariate_nhanes_harmonized` |
| `multivariate_prognosis` |
| `multivariate_prognosis_harmonized` |

### `rcs_*`（6）

| register_block |
|---|
| `rcs_ckm_strata_panels` |
| `rcs_incidence` |
| `rcs_iptw_weighted` |
| `rcs_nhanes` |
| `rcs_prognosis` |
| `rcs_prognosis_by_group` |

### `subgroup_*`（7）

| register_block |
|---|
| `subgroup_environment_or` |
| `subgroup_incidence` |
| `subgroup_incidence_continuous` |
| `subgroup_iptw_weighted` |
| `subgroup_nhanes_weighted` |
| `subgroup_prognosis` |
| `subgroup_treatment_forest` |

### `trajectory_*`（22）

| register_block |
|---|
| `trajectory_baseline_by_class` |
| `trajectory_calc_28d_index` |
| `trajectory_chisq` |
| `trajectory_creatinine_pct` |
| `trajectory_dynpred` |
| `trajectory_dynpred_individual` |
| `trajectory_gbmt` |
| `trajectory_jlcm` |
| `trajectory_jlcm_discovery_validate` |
| `trajectory_km_class` |
| `trajectory_lcmm_external_validate` |
| `trajectory_lcmm_fit` |
| `trajectory_lcmm_mpcmp_plot` |
| `trajectory_outcome_adjusted` |
| `trajectory_outcome_models` |
| `trajectory_piecewise_cox` |
| `trajectory_plot_gbmt` |
| `trajectory_plot_jlcm` |
| `trajectory_prepare_wide_rdata` |
| `trajectory_subgroup_class` |
| `trajectory_weibull_compare` |
| `trajectory_wide_to_long` |

### `tst_*`（12）

| register_block |
|---|
| `tst_calibration_dca` |
| `tst_cohort` |
| `tst_external` |
| `tst_landmark` |
| `tst_literature_validate` |
| `tst_pub_export` |
| `tst_repo_a1` |
| `tst_shap` |
| `tst_split` |
| `tst_summary_results` |
| `tst_timeseries` |
| `tst_train_eval` |

### `univariate_*`（4）

| register_block |
|---|
| `univariate_incidence_binary` |
| `univariate_incidence_multiclass` |
| `univariate_nhanes` |
| `univariate_prognosis` |

<!-- END AUTO:variants -->

<!-- BEGIN AUTO:templates -->
## 6. Template 索引（AUTO）

写新 config：**先复制最近 template**，再改【必改】键。

| template | 说明 | 【必改】摘要 |
|---|---|---|
| `configs/templates/config_ai_clinical_cdm_batch.template.R` | config_ai_clinical_cdm_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_ai_medical_qa_cot_batch.template.R` | config_ai_medical_qa_cot_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_association_nhanes.template.R` | config_association_nhanes.template.R — NHANES 加权【横断面关联】通用模板 | 见文件头 |
| `configs/templates/config_bayesian_comorbidity_batch.template.R` | config_bayesian_comorbidity_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_burden_gbd.template.R` | config_burden_gbd.template.R — GBD 二次数据【全球负担描述】通用模板 | 见文件头 |
| `configs/templates/config_cdc_wonder_dobbs_batch.template.R` | config_cdc_wonder_dobbs_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_cftraj_charls_batch.template.R` | config_cftraj_charls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_competing_risk_chf_batch.template.R` | config_competing_risk_chf_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_competing_risk_stroke_batch.template.R` | config_competing_risk_stroke_batch.template | 见文件头 |
| `configs/templates/config_competing_risk_stroke_isolation.template.R` | config_competing_risk_stroke_batch.template.R — 竞争风险（MIMIC · by_unit） | 见文件头 |
| `configs/templates/config_complex_network_clhls_batch.template.R` | config_complex_network_clhls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_crm_nhanes_mr.template.R` | config_crm_nhanes_mr.template.R — NHANES 单库 CRM × 孟德尔随机化（Han 2025 JAHA） | 见文件头 |
| `configs/templates/config_crm_nhanes_mr_batch.template.R` | config_crm_nhanes_mr_batch.template.R — NHANES 单库 CRM × 孟德尔随机化（Batch） | 见文件头 |
| `configs/templates/config_cross_lagged_frailty_batch.template.R` | config_cross_lagged_frailty_batch.template.R — 交叉滞后 三库+Pooled | 见文件头 |
| `configs/templates/config_cum_egdr_kmeans_ckm_batch.template.R` | config_cum_egdr_kmeans_ckm_batch.template.R | 见文件头 |
| `configs/templates/config_dual_change_score_elsa_batch.template.R` | config_dual_change_score_elsa_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_dual_incidence_mr_crm_batch.template.R` | config_dual_incidence_mr_crm_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_dynamic_causal_dual_batch.template.R` | config_dynamic_causal_dual_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_environment_cd_osteo_nhanes.template.R` | config_environment_cd_osteo_nhanes.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_environment_dkd_batch.template.R` | config_environment_dkd_batch.template.R — DKD × 环境 VOC（NHANES 批量模板） | 见文件头 |
| `configs/templates/config_environment_dkd_nhanes.template.R` | config_environment_dkd_nhanes.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_gallstone_nomogram_batch.template.R` | config_gallstone_nomogram_batch.template.R | 见文件头 |
| `configs/templates/config_glide_sol_seoul.template.R` | Template — copy to configs/config_glide_sol_seoul.R and set gee$project | 见文件头 |
| `configs/templates/config_hf_dual_clustering.template.R` | config_hf_dual_clustering.template | 见文件头 |
| `configs/templates/config_incidence_dual.template.R` | config_incidence_dual.template | 见文件头 |
| `configs/templates/config_incidence_dual_batch.template.R` | config_incidence_dual_batch.template.R — 双库发病批量多指标配置模板 | # .batch_project_root ← 与本文件所在目录完全一致 # data$rawdata_path / rawdata_obj / id_column（两库各一组） # project$disease_code / disease / analysis_group / reference_group # dual_db$primary / secondary（路径、对象名、ID 列、列映射类型） # nhanes$survey_weight / survey_c |
| `configs/templates/config_incidence_iptw.template.R` | config_incidence_iptw.template | 见文件头 |
| `configs/templates/config_incidence_nhanes.template.R` | config_incidence_nhanes.template | 见文件头 |
| `configs/templates/config_incidence_nhanes_batch.template.R` | config_incidence_nhanes_batch.template.R — NHANES 单库发病批量模板 | 见文件头 |
| `configs/templates/config_incidence_prepost_charls_batch.template.R` | config_incidence_prepost_charls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_incidence_single.template.R` | config_incidence_single.template.R — 单库发病 Logistic 流水线配置模板 | 见文件头 |
| `configs/templates/config_ipw_diabetes_stroke_batch.template.R` | config_ipw_diabetes_stroke_batch.template.R — 用药IPW（Jin · MIMIC · unit=main） | 见文件头 |
| `configs/templates/config_markov_cognitive_clhls_batch.template.R` | config_markov_cognitive_clhls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_medication_regimen_text_soft_batch.template.R` | config_medication_regimen_text_soft_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_ml_dual_batch.template.R` | config_ml_dual_batch.template.R — ML 双库批量配置模板 | 见文件头 |
| `configs/templates/config_ml_small_sample.template.R` | config_ml_small_sample.template.R — 小样本 ML 配置模板（单库 / 单指标 or 全变量） | 见文件头 |
| `configs/templates/config_multimodal_tbi_batch.template.R` | config_multimodal_tbi_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_multimorbidity_additive_batch.template.R` | config_multimorbidity_additive_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_network_temperature_adolescent_batch.template.R` | config_network_temperature_adolescent_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_pa_mobility_cognitive.template.R` | config_pa_mobility_cognitive.template | 见文件头 |
| `configs/templates/config_pa_mobility_cognitive_batch.template.R` | config_pa_mobility_cognitive_batch.template | 见文件头 |
| `configs/templates/config_sem_chain_mediation_charls_batch.template.R` | config_sem_chain_mediation_charls_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_sle_aki_inc_prog_batch.template.R` | config_sle_aki_inc_prog_batch.template.R | 见文件头 |
| `configs/templates/config_survival_dual_batch.template.R` | config_survival_dual_batch.template.R — 双库预后批量多指标配置模板（引擎 defaults） | 见文件头 |
| `configs/templates/config_survival_iptw_pooled.template.R` | config_survival_iptw_pooled.template.R — 多队列 pooled IPTW-Cox 生存分析（通用模板） | 见文件头 |
| `configs/templates/config_survival_sae.template.R` | config_survival_sae.template | 见文件头 |
| `configs/templates/config_target_trial_rasi_aki_batch.template.R` | config_target_trial_rasi_aki_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_trajectory_incidence_aki_batch.template.R` | config_trajectory_incidence_aki_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_trajectory_prognosis_batch.template.R` | config_trajectory_prognosis_batch.template.R — 轨迹预后 JLCM 双库批量模板 | 见文件头 |
| `configs/templates/config_trajectory_prognosis_plt.template.R` | config_trajectory_prognosis_plt.template.R — 轨迹预后 PLT 单库模板 | 见文件头 |
| `configs/templates/config_trajectory_prognosis_plt_batch.template.R` | config_trajectory_prognosis_plt_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_transformer_aki_single_batch.template.R` | config_transformer_aki_single_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改） | 见文件头 |
| `configs/templates/config_two_stage_transformer_stroke.template.R` | config_two_stage_transformer_stroke.template.R — 缺血性脑卒中两阶段 Transformer（单跑） | 见文件头 |
| `configs/templates/config_two_stage_transformer_stroke_isolation.template.R` | config_two_stage_transformer_stroke_isolation.template.R | 见文件头 |
| `configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R` | config_two_stage_transformer_stroke_task_parallel.template.R | 见文件头 |

<!-- END AUTO:templates -->

<!-- BEGIN AUTO:pipelines -->
## 7. 已验证 pipeline 片段（AUTO）

以下从母版 template 抽取 `blocks = c(...)`（只读参考；研究区默认勿手改 pipeline，用 `add_block`）。

### `configs/templates/config_incidence_dual_batch.template.R`

- `pipeline_shared_nhanes$blocks`: `c("data_clean", "column_mapping", "dual_db_column_harmonize", "index")`
- `pipeline_shared_regular$blocks`: `c("data_clean", "column_mapping", "dual_db_column_harmonize", "index")`
- `pipeline_nhanes_batch$blocks`: `c( "data_clean", "column_mapping", "dual_db_column_harmonize", "index", "analysis_exclusion", # 发病套路不修剪指标极端值（不挂 trim_index_extreme） "imputation", "cutoff", "obj", "baseline_nhanes", "boxplot", "univariate_nhanes", "multicollinearity_nhanes_screen", "multivariate_nhanes", "multivariate_covariate_resolve", "multicollinearity_nhanes_final", "dual_db_covariate_harmonize", "multivariate_nhanes_harmonized", "simple_ROC", "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted", "logisti ...)`
- `pipeline_regular_batch$blocks`: `c( "data_clean", "column_mapping", "dual_db_column_harmonize", "index", "analysis_exclusion", # 发病套路不修剪指标极端值（不挂 trim_index_extreme） "imputation", "baseline_binary", "boxplot", "univariate_incidence_binary", "multicollinearity_screen", "multivariate_incidence_binary", "multivariate_covariate_resolve", "multicollinearity_final", "dual_db_covariate_harmonize", "multivariate_incidence_harmonized", "simple_ROC", "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm", "dual_db_logistic ...)`

### `configs/templates/config_survival_dual_batch.template.R`


### `configs/templates/config_competing_risk_stroke_batch.template.R`

- `pipeline_shared$blocks`: `c( "data_clean", "column_mapping", "dual_db_column_harmonize", "index", "trajectory_calc_28d_index" )`
- `pipeline_unit$blocks`: `c( "imputation", "competing_index_exposure", "analysis_exclusion", # 预后竞争风险：不修剪指标极端值（不挂 trim_index_extreme） "competing_trajectory_cluster", "competing_flowchart", "competing_baseline_quartile", "competing_lmm_trajectory", "competing_baseline_trajectory", "univariate_prognosis", "feature_selection_lasso", "feature_selection_random_forest", "competing_finegray", "competing_mixed_cox", "competing_models_123", "competing_models_123_death", "competing_stratified", "competing_rcs", "competing_cif_plot ...)`

### `configs/templates/config_ml_dual_batch.template.R`


### `configs/templates/config_ipw_diabetes_stroke_batch.template.R`

- `pipeline_shared$blocks`: `c("data_clean", "column_mapping")`
- `pipeline_unit$blocks`: `c( "imputation", "ipw_diabetes_exposure", "analysis_exclusion", "univariate_prognosis", "multicollinearity_screen", "ipw_jin_composite_risk", "iptw_balance", "iptw_association", "ipw_diabetes_flowchart", "ipw_weighted_km_pub", "subgroup_iptw_weighted", "subgroup_treatment_forest", "ipw_subgroup_km_pub", "stepp_prognosis", "cox_binary", "ipw_overlap_weights", "ipw_surv_calibration_roc", "ipw_literature_targets", "ipw_pub_export" )`

### `configs/templates/config_crm_nhanes_mr_batch.template.R`

- `pipeline_shared$blocks`: `c( "data_clean", "column_mapping", "dual_db_column_harmonize", "crm_nhanes_derive" )`

### `configs/templates/config_two_stage_transformer_stroke.template.R`

- `pipeline$blocks`: `c( "data_clean", "column_mapping", "tst_cohort", "tst_split", "imputation", "tst_timeseries", "baseline_binary", "tst_landmark", "tst_repo_a1", "tst_train_eval", "tst_calibration_dca", "tst_shap", "tst_external", "tst_literature_validate", "tst_pub_export", "tst_summary_results" )`

<!-- END AUTO:pipelines -->

<!-- BEGIN AUTO:block_cards -->
## 8. Block 卡片（AUTO）

共 **480** 个 `register_block`。 细节以各文件头部注释为准；本表只做选型索引。

### `00_attrition/`

#### `attrition_flowchart`
- 路径: `Blocks/00_attrition/01block_attrition_flowchart.R`
- 用途: ##############################################################################
- 典型位置: 任意 pipeline 最后一个 block（baseline_pipelines / 研究 batch 末尾）
- config 节: `config$attrition`
- 回读: `Blocks/00_attrition/01block_attrition_flowchart.R` 文件头注释


### `00_dual_db/`

#### `dual_db_column_harmonize`
- 路径: `Blocks/00_dual_db/01block_dual_db_column_harmonize.R`
- 用途: ##############################################################################
- 回读: `Blocks/00_dual_db/01block_dual_db_column_harmonize.R` 文件头注释

#### `dual_db_covariate_harmonize`
- 路径: `Blocks/00_dual_db/02block_dual_db_covariate_harmonize.R`
- 用途: ##############################################################################
- 回读: `Blocks/00_dual_db/02block_dual_db_covariate_harmonize.R` 文件头注释

#### `dual_db_logistic_branch_harmonize`
- 路径: `Blocks/00_dual_db/03block_dual_db_logistic_branch_harmonize.R`
- 用途: ##############################################################################
- 回读: `Blocks/00_dual_db/03block_dual_db_logistic_branch_harmonize.R` 文件头注释

#### `dual_db_logistic_main_table_realign`
- 路径: `Blocks/00_dual_db/05block_dual_db_logistic_main_table_realign.R`
- 用途: ##############################################################################
- 回读: `Blocks/00_dual_db/05block_dual_db_logistic_main_table_realign.R` 文件头注释

#### `dual_db_logistic_scheme_harmonize`
- 路径: `Blocks/00_dual_db/04block_dual_db_logistic_scheme_harmonize.R`
- 用途: ##############################################################################
- 回读: `Blocks/00_dual_db/04block_dual_db_logistic_scheme_harmonize.R` 文件头注释


### `00_index/`

#### `index`
- 路径: `Blocks/00_index/01block_index.R`
- 用途: ##############################################################################
- 典型位置: column_mapping → imputation → index（插补后计算指标，缺失列自动跳过）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned`
- 写出: ctx$data$cleaned、ctx$data$imputed 中新增指标列； ctx$results$computed_indices（已计算指标名 + 统计摘要） 文件: Tables/Table Index Summary.csv 依赖: dplyr（case_when 条件公式）
- config 节: `config$index`
- 回读: `Blocks/00_index/01block_index.R` 文件头注释


### `01_column_mappings/`

#### `column_mapping`
- 路径: `Blocks/01_column_mappings/01block_column_mapping.R`
- 用途: ##############################################################################
- 典型位置: data_clean 之前或之后（常紧接 data_clean 前，enable=TRUE 时）
- 前置: `require_data = ctx$data$raw（来自 data_clean 加载）或已有 cleaned / imputed`
- config 节: `config$column_mapping`
- 回读: `Blocks/01_column_mappings/01block_column_mapping.R` 文件头注释


### `02_data_clean/`

#### `data_clean`
- 路径: `Blocks/02_data_clean/01block_data_clean.R`
- 用途: ##############################################################################
- 典型位置: 第一步或 column_mapping 之后；产出 cleaned 供 imputation
- 前置: `require_config = config$data$rawdata_path（.RData/.rds/.csv 等）或上游 ctx$data$mapped`
- config 节: `config$computed_indices`, `config$data`, `config$data_clean`, `config$project`
- 回读: `Blocks/02_data_clean/01block_data_clean.R` 文件头注释


### `03_imputation/`

#### `analysis_exclusion`
- 路径: `Blocks/03_imputation/03block_analysis_exclusion.R`
- 用途: ##############################################################################
- 典型位置: competing_index_exposure 之后、trim_index_extreme / 表导出之前
- config 节: `config$analysis_exclusion`
- 回读: `Blocks/03_imputation/03block_analysis_exclusion.R` 文件头注释

#### `imputation`
- 路径: `Blocks/03_imputation/01block_imputation.R`
- 用途: ##############################################################################
- 典型位置: data_clean（± column_mapping）之后；下游均读 ctx$data$imputed
- 前置: `require_data = ctx$data$mapped %||% ctx$data$cleaned`
- config 节: `config$analysis_var_policy`, `config$imputation`
- 回读: `Blocks/03_imputation/01block_imputation.R` 文件头注释

#### `prognosis_outcome_landmark`
- 路径: `Blocks/03_imputation/04block_prognosis_outcome_landmark.R`
- 用途: ##############################################################################
- 典型位置: imputation 之后、baseline_binary 之前
- config 节: `config$prognosis_outcome`, `config$survival`
- 回读: `Blocks/03_imputation/04block_prognosis_outcome_landmark.R` 文件头注释

#### `trim_index_extreme`
- 路径: `Blocks/03_imputation/02block_trim_index_extreme.R`
- 用途: ##############################################################################
- config 节: `config$incidence`, `config$incidence_batch`
- 回读: `Blocks/03_imputation/02block_trim_index_extreme.R` 文件头注释


### `04_baseline/`

#### `baseline_binary`
- 路径: `Blocks/04_baseline/01block_baseline_binary.R`
- 用途: ##############################################################################
- 典型位置: imputation 后；strata 列须恰好 2 水平（low/high 或 Case/Control）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_levels = 2L, # 分层列水平数必须恰好为 2，否则 pause / stop`
- config 节: `config$analysis_var_policy`, `config$baseline_binary`
- 回读: `Blocks/04_baseline/01block_baseline_binary.R` 文件头注释

#### `baseline_multiclass`
- 路径: `Blocks/04_baseline/02block_baseline_multiclass.R`
- 用途: ##############################################################################
- 典型位置: imputation 后；strata 水平数 >= 3（ANOVA / Kruskal-Wallis）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_levels_min = 3L, # 分层列水平数 >= 3，否则 pause / stop`
- config 节: `config$analysis_var_policy`, `config$baseline_multiclass`
- 回读: `Blocks/04_baseline/02block_baseline_multiclass.R` 文件头注释

#### `baseline_nhanes`
- 路径: `Blocks/04_baseline/03block_baseline_nhanes.R`
- 用途: ##############################################################################
- 典型位置: obj 之后；读 ctx$results$nhanes_design（加权 Table 1 + 正态性 Table S）
- 前置: `require_data = ctx$results$nhanes_design # 须先 run_block(obj)`
- config 节: `config$analysis_var_policy`, `config$baseline_nhanes`, `config$nhanes`
- 回读: `Blocks/04_baseline/03block_baseline_nhanes.R` 文件头注释


### `05_boxplot/`

#### `boxplot`
- 路径: `Blocks/05_boxplot/01block_boxplot.R`
- 用途: ##############################################################################
- 典型位置: baseline 之后（可用 sig_vars 或 survival/logistic 指定指标）
- config 节: `config$boxplot`
- 回读: `Blocks/05_boxplot/01block_boxplot.R` 文件头注释


### `06_univariate/`

#### `univariate_incidence_binary`
- 路径: `Blocks/06_univariate/02block_univariate_incidence_binary.R`
- 用途: ##############################################################################
- 典型位置: incidence + 非 NHANES；二分类结局；下游 multivariate_incidence_binary
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = incidence；classification_mode 为 binary`
- config 节: `config$univariate_incidence_binary`
- 回读: `Blocks/06_univariate/02block_univariate_incidence_binary.R` 文件头注释

#### `univariate_incidence_multiclass`
- 路径: `Blocks/06_univariate/03block_univariate_incidence_multiclass.R`
- 用途: ##############################################################################
- 典型位置: imputation 后；study_type=incidence；classification_mode=multiclass
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = incidence；结局水平数 >= 3；非 NHANES`
- config 节: `config$univariate_incidence_multiclass`
- 回读: `Blocks/06_univariate/03block_univariate_incidence_multiclass.R` 文件头注释

#### `univariate_nhanes`
- 路径: `Blocks/06_univariate/04block_univariate_nhanes.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$results$nhanes_design # 须先 run_block(obj)`
- config 节: `config$nhanes`, `config$univariate_nhanes`
- 回读: `Blocks/06_univariate/04block_univariate_nhanes.R` 文件头注释

#### `univariate_prognosis`
- 路径: `Blocks/06_univariate/01block_univariate_prognosis.R`
- 用途: ##############################################################################
- 典型位置: imputation 后；study_type=prognosis；供 multivariate_prognosis 读 univar_coef
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = project$study_type == "prognosis"`
- config 节: `config$univariate_prognosis`
- 回读: `Blocks/06_univariate/01block_univariate_prognosis.R` 文件头注释


### `07_multivariate/`

#### `multivariate_covariate_resolve`
- 路径: `Blocks/07_multivariate/05block_multivariate_covariate_resolve.R`
- 用途: ##############################################################################
- 典型位置: multivariate_* 之后、multicollinearity_*_final 之前
- 回读: `Blocks/07_multivariate/05block_multivariate_covariate_resolve.R` 文件头注释

#### `multivariate_incidence_binary`
- 路径: `Blocks/07_multivariate/02block_multivariate_incidence_binary.R`
- 用途: ##############################################################################
- 典型位置: ... multicollinearity_final → [dual_db_covariate_harmonize] →
- config 节: `config$multivariate_incidence_binary`
- 回读: `Blocks/07_multivariate/02block_multivariate_incidence_binary.R` 文件头注释

#### `multivariate_incidence_harmonized`
- 路径: `Blocks/07_multivariate/02block_multivariate_incidence_binary.R`
- 用途: ##############################################################################
- 典型位置: ... multicollinearity_final → [dual_db_covariate_harmonize] →
- config 节: `config$multivariate_incidence_binary`
- 回读: `Blocks/07_multivariate/02block_multivariate_incidence_binary.R` 文件头注释

#### `multivariate_incidence_multiclass`
- 路径: `Blocks/07_multivariate/03block_multivariate_incidence_multiclass.R`
- 用途: ##############################################################################
- config 节: `config$multivariate_incidence_multiclass`
- 回读: `Blocks/07_multivariate/03block_multivariate_incidence_multiclass.R` 文件头注释

#### `multivariate_nhanes`
- 路径: `Blocks/07_multivariate/04block_multivariate_nhanes.R`
- 用途: ##############################################################################
- 典型位置: ... multicollinearity_nhanes_final → dual_db_covariate_harmonize →
- 前置: `require_data = ctx$results$nhanes_design`; `require_study = incidence + classification_mode binary`
- config 节: `config$multivariate_nhanes`, `config$nhanes`
- 回读: `Blocks/07_multivariate/04block_multivariate_nhanes.R` 文件头注释

#### `multivariate_nhanes_harmonized`
- 路径: `Blocks/07_multivariate/04block_multivariate_nhanes.R`
- 用途: ##############################################################################
- 典型位置: ... multicollinearity_nhanes_final → dual_db_covariate_harmonize →
- 前置: `require_data = ctx$results$nhanes_design`; `require_study = incidence + classification_mode binary`
- config 节: `config$multivariate_nhanes`, `config$nhanes`
- 回读: `Blocks/07_multivariate/04block_multivariate_nhanes.R` 文件头注释

#### `multivariate_prognosis`
- 路径: `Blocks/07_multivariate/01block_multivariate_prognosis.R`
- 用途: ##############################################################################
- config 节: `config$multivariate_prognosis`
- 回读: `Blocks/07_multivariate/01block_multivariate_prognosis.R` 文件头注释

#### `multivariate_prognosis_harmonized`
- 路径: `Blocks/07_multivariate/01block_multivariate_prognosis.R`
- 用途: ##############################################################################
- config 节: `config$multivariate_prognosis`
- 回读: `Blocks/07_multivariate/01block_multivariate_prognosis.R` 文件头注释


### `08_vif/`

#### `multicollinearity`
- 路径: `Blocks/08_vif/01block_multicollinearity.R`
- 用途: ##############################################################################
- 典型位置: baseline 后、单因素/多因素/RCS 前；下游读 ctx$results$Model2Factors
- 回读: `Blocks/08_vif/01block_multicollinearity.R` 文件头注释

#### `multicollinearity_final`
- 路径: `Blocks/08_vif/01block_multicollinearity.R`
- 用途: ##############################################################################
- 典型位置: baseline 后、单因素/多因素/RCS 前；下游读 ctx$results$Model2Factors
- 回读: `Blocks/08_vif/01block_multicollinearity.R` 文件头注释

#### `multicollinearity_nhanes_final`
- 路径: `Blocks/08_vif/02block_multicollinearity_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$multicollinearity`
- 回读: `Blocks/08_vif/02block_multicollinearity_nhanes_weighted.R` 文件头注释

#### `multicollinearity_nhanes_screen`
- 路径: `Blocks/08_vif/02block_multicollinearity_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$multicollinearity`
- 回读: `Blocks/08_vif/02block_multicollinearity_nhanes_weighted.R` 文件头注释

#### `multicollinearity_screen`
- 路径: `Blocks/08_vif/01block_multicollinearity.R`
- 用途: ##############################################################################
- 典型位置: baseline 后、单因素/多因素/RCS 前；下游读 ctx$results$Model2Factors
- 回读: `Blocks/08_vif/01block_multicollinearity.R` 文件头注释


### `09_correlation/`

#### `correlation`
- 路径: `Blocks/09_correlation/01block_correlation.R`
- 用途: ##############################################################################
- 典型位置: baseline / multicollinearity 附近；可选读 continuous_vars
- config 节: `config$correlation`
- 回读: `Blocks/09_correlation/01block_correlation.R` 文件头注释


### `10_cox/`

#### `cox_binary`
- 路径: `Blocks/10_cox/01block_cox_binary.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity 后；study_type=prognosis；可选协变量组合搜索
- config 节: `config$cox`, `config$cox_binary`
- 回读: `Blocks/10_cox/01block_cox_binary.R` 文件头注释

#### `cox_interaction`
- 路径: `Blocks/10_cox/06block_cox_interaction.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = config$project$study_type == "prognosis"`; `require_config = config$survival（time_var / event_var / event_value 必填）`
- config 节: `config$cox_interaction`, `config$project`, `config$survival`
- 回读: `Blocks/10_cox/06block_cox_interaction.R` 文件头注释

#### `cox_ml_continuous_batch`
- 路径: `Blocks/10_cox/08block_cox_ml_continuous_batch.R`
- 用途: ##############################################################################
- config 节: `config$cox_ml_continuous_batch`
- 回读: `Blocks/10_cox/08block_cox_ml_continuous_batch.R` 文件头注释

#### `cox_quartile`
- 路径: `Blocks/10_cox/03block_cox_quartile.R`
- 用途: ##############################################################################
- 回读: `Blocks/10_cox/03block_cox_quartile.R` 文件头注释

#### `cox_quintile`
- 路径: `Blocks/10_cox/04block_cox_quintile.R`
- 用途: ##############################################################################
- config 节: `config$cox_quintile`
- 回读: `Blocks/10_cox/04block_cox_quintile.R` 文件头注释

#### `cox_sextile`
- 路径: `Blocks/10_cox/05block_cox_sextile.R`
- 用途: ##############################################################################
- config 节: `config$cox_sextile`
- 回读: `Blocks/10_cox/05block_cox_sextile.R` 文件头注释

#### `cox_subphenotype`
- 路径: `Blocks/10_cox/07block_cox_subphenotype_multimodel.R`
- 用途: ##############################################################################
- 典型位置: lca → … → cox_subphenotype
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = ctx$results$df_final（含 Subphenotype 列）`
- config 节: `config$cox_subphenotype`, `config$survival`
- 回读: `Blocks/10_cox/07block_cox_subphenotype_multimodel.R` 文件头注释

#### `cox_tertile`
- 路径: `Blocks/10_cox/02block_cox_tertile.R`
- 用途: ##############################################################################
- 回读: `Blocks/10_cox/02block_cox_tertile.R` 文件头注释


### `11_logistic/`

#### `logistic_binary_clogit`
- 路径: `Blocks/11_logistic/07block_logistic_binary_clogit.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_col = bl_cfg$strata_var # 默认 "match_id"`; `require_ctx_results = "Model1Factors"`; `require_package = "survival"`
- 回读: `Blocks/11_logistic/07block_logistic_binary_clogit.R` 文件头注释

#### `logistic_binary_glm`
- 路径: `Blocks/11_logistic/04block_logistic_binary_glm.R`
- 用途: ##############################################################################
- 典型位置: 发病二分类；中位数二分暴露；随机搜索 Model2 协变量
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "Model1Factors"`
- 回读: `Blocks/11_logistic/04block_logistic_binary_glm.R` 文件头注释

#### `logistic_binary_glm_rcs`
- 路径: `Blocks/11_logistic/04block_logistic_binary_glm.R`
- 用途: ##############################################################################
- 典型位置: 发病二分类；中位数二分暴露；随机搜索 Model2 协变量
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "Model1Factors"`
- 回读: `Blocks/11_logistic/04block_logistic_binary_glm.R` 文件头注释

#### `logistic_binary_iptw_weighted`
- 路径: `Blocks/11_logistic/17block_logistic_binary_iptw_weighted.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → logistic_binary_iptw_weighted
- config 节: `config$logistic_binary_iptw_weighted`
- 回读: `Blocks/11_logistic/17block_logistic_binary_iptw_weighted.R` 文件头注释

#### `logistic_binary_nhanes_weighted`
- 路径: `Blocks/11_logistic/15block_logistic_binary_nhanes_weighted.R`
- 用途: ##############################################################################
- 回读: `Blocks/11_logistic/15block_logistic_binary_nhanes_weighted.R` 文件头注释

#### `logistic_binary_nhanes_weighted_rcs`
- 路径: `Blocks/11_logistic/15block_logistic_binary_nhanes_weighted.R`
- 用途: ##############################################################################
- 回读: `Blocks/11_logistic/15block_logistic_binary_nhanes_weighted.R` 文件头注释

#### `logistic_environment_glm`
- 路径: `Blocks/11_logistic/11block_logistic_environment_glm.R`
- 用途: ##############################################################################
- 典型位置: 上游写入 select_vocs；对每个 VOC 四分位 GLM 筛选；写 select_vocs_glm/final
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "select_vocs" # 上游写入候选环境暴露列名向量`
- config 节: `config$environment`
- 回读: `Blocks/11_logistic/11block_logistic_environment_glm.R` 文件头注释

#### `logistic_quartile_clogit`
- 路径: `Blocks/11_logistic/03block_logistic_quartile_clogit.R`
- 用途: ##############################################################################
- 典型位置: 匹配病例对照；clogit + strata_var；需 survival 包
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 必须存在且含 outcome/index/strata_var 列`; `require_strata_col = bl_cfg$strata_var # 默认 "match_id"；缺失则 stop`; `require_ctx_results = "Model1Factors" # 优先读取；为 NULL 时 fallback 到 bl_cfg$model1_factors`; `require_package = "survival" # clogit()`
- 回读: `Blocks/11_logistic/03block_logistic_quartile_clogit.R` 文件头注释

#### `logistic_quartile_glm`
- 路径: `Blocks/11_logistic/01block_logistic_quartile_glm.R`
- 用途: ##############################################################################
- 典型位置: incidence + imputed；multicollinearity 后；可写 Model1Factors 供下游
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 必须存在且含 outcome/index 列`; `require_ctx_results = "Model1Factors" # 优先读取；为 NULL 时 fallback 到 bl_cfg$model1_factors`
- 回读: `Blocks/11_logistic/01block_logistic_quartile_glm.R` 文件头注释

#### `logistic_quartile_glm_rcs`
- 路径: `Blocks/11_logistic/01block_logistic_quartile_glm.R`
- 用途: ##############################################################################
- 典型位置: incidence + imputed；multicollinearity 后；可写 Model1Factors 供下游
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 必须存在且含 outcome/index 列`; `require_ctx_results = "Model1Factors" # 优先读取；为 NULL 时 fallback 到 bl_cfg$model1_factors`
- 回读: `Blocks/11_logistic/01block_logistic_quartile_glm.R` 文件头注释

#### `logistic_quartile_iptw_weighted`
- 路径: `Blocks/11_logistic/18block_logistic_quartile_iptw_weighted.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → logistic_quartile_iptw_weighted
- config 节: `config$logistic_quartile_iptw_weighted`
- 回读: `Blocks/11_logistic/18block_logistic_quartile_iptw_weighted.R` 文件头注释

#### `logistic_quartile_nhanes_weighted`
- 路径: `Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$logistic_nhanes_weighted`, `config$logistic_quartile_nhanes_weighted`
- 回读: `Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R` 文件头注释

#### `logistic_quartile_nhanes_weighted_rcs`
- 路径: `Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$logistic_nhanes_weighted`, `config$logistic_quartile_nhanes_weighted`
- 回读: `Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R` 文件头注释

#### `logistic_quintile_clogit`
- 路径: `Blocks/11_logistic/09block_logistic_quintile_clogit.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_col = bl_cfg$strata_var # 默认 "match_id"`; `require_ctx_results = "Model1Factors"`; `require_package = "survival"`
- 回读: `Blocks/11_logistic/09block_logistic_quintile_clogit.R` 文件头注释

#### `logistic_quintile_glm`
- 路径: `Blocks/11_logistic/02block_logistic_quintile_glm.R`
- 用途: ##############################################################################
- 典型位置: incidence；五分位暴露；随机搜索 Model2；源 C01_LogisticCode_quintiles.R
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 必须存在且含 outcome/index 列`; `require_ctx_results = "Model1Factors" # 优先读取；为 NULL 时 fallback 到 pos.factors[model1_pos_idx]`
- 回读: `Blocks/11_logistic/02block_logistic_quintile_glm.R` 文件头注释

#### `logistic_quintile_glm_rcs`
- 路径: `Blocks/11_logistic/02block_logistic_quintile_glm.R`
- 用途: ##############################################################################
- 典型位置: incidence；五分位暴露；随机搜索 Model2；源 C01_LogisticCode_quintiles.R
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 必须存在且含 outcome/index 列`; `require_ctx_results = "Model1Factors" # 优先读取；为 NULL 时 fallback 到 pos.factors[model1_pos_idx]`
- 回读: `Blocks/11_logistic/02block_logistic_quintile_glm.R` 文件头注释

#### `logistic_rcs_cutoff_nhanes_weighted`
- 路径: `Blocks/11_logistic/16block_logistic_rcs_cutoff_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$logistic_rcs_cutoff_nhanes_weighted`
- 回读: `Blocks/11_logistic/16block_logistic_rcs_cutoff_nhanes_weighted.R` 文件头注释

#### `logistic_sextile_clogit`
- 路径: `Blocks/11_logistic/10block_logistic_sextile_clogit.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_col = bl_cfg$strata_var # 默认 "match_id"`; `require_ctx_results = "Model1Factors"`; `require_package = "survival"`
- 回读: `Blocks/11_logistic/10block_logistic_sextile_clogit.R` 文件头注释

#### `logistic_sextile_glm`
- 路径: `Blocks/11_logistic/06block_logistic_sextile_glm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "Model1Factors"`
- 回读: `Blocks/11_logistic/06block_logistic_sextile_glm.R` 文件头注释

#### `logistic_subphenotype`
- 路径: `Blocks/11_logistic/12block_logistic_subphenotype_multimodel.R`
- 用途: ##############################################################################
- 典型位置: lca → … → logistic_subphenotype
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = ctx$results$df_final（含 Subphenotype 列）`
- config 节: `config$analysis_group`, `config$data`, `config$logistic_subphenotype`
- 回读: `Blocks/11_logistic/12block_logistic_subphenotype_multimodel.R` 文件头注释

#### `logistic_tertile_clogit`
- 路径: `Blocks/11_logistic/08block_logistic_tertile_clogit.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_strata_col = bl_cfg$strata_var # 默认 "match_id"`; `require_ctx_results = "Model1Factors"`; `require_package = "survival"`
- 回读: `Blocks/11_logistic/08block_logistic_tertile_clogit.R` 文件头注释

#### `logistic_tertile_glm`
- 路径: `Blocks/11_logistic/05block_logistic_tertile_glm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "Model1Factors"`
- 回读: `Blocks/11_logistic/05block_logistic_tertile_glm.R` 文件头注释

#### `logistic_tertile_glm_rcs`
- 路径: `Blocks/11_logistic/05block_logistic_tertile_glm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = "Model1Factors"`
- 回读: `Blocks/11_logistic/05block_logistic_tertile_glm.R` 文件头注释

#### `logistic_tertile_iptw_weighted`
- 路径: `Blocks/11_logistic/19block_logistic_tertile_iptw_weighted.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → logistic_tertile_iptw_weighted
- config 节: `config$logistic_tertile_iptw_weighted`
- 回读: `Blocks/11_logistic/19block_logistic_tertile_iptw_weighted.R` 文件头注释

#### `logistic_tertile_nhanes_weighted`
- 路径: `Blocks/11_logistic/14block_logistic_tertile_nhanes_weighted.R`
- 用途: ##############################################################################
- 回读: `Blocks/11_logistic/14block_logistic_tertile_nhanes_weighted.R` 文件头注释

#### `logistic_tertile_nhanes_weighted_rcs`
- 路径: `Blocks/11_logistic/14block_logistic_tertile_nhanes_weighted.R`
- 用途: ##############################################################################
- 回读: `Blocks/11_logistic/14block_logistic_tertile_nhanes_weighted.R` 文件头注释


### `12_obj/`

#### `obj`
- 路径: `Blocks/12_obj/01block_obj.R`
- 用途: ##############################################################################
- 典型位置: imputation → cutoff → obj → baseline_nhanes / rcs_nhanes / 加权分析
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_results = cutoff 写入的 nhanes_data_binary / _tert / _quart`
- config 节: `config$nhanes`
- 回读: `Blocks/12_obj/01block_obj.R` 文件头注释


### `13_roc/`

#### `ROC`
- 路径: `Blocks/13_roc/01block_ROC.R`
- 用途: ##############################################################################
- 典型位置: train_validation → ml_models → ROC（勿与父块 block_ROC.R 重复 source）
- 前置: `require_results = ctx$results$ml_models（含 tidymodels workflow + recipe）`
- config 节: `config$plot`, `config$roc`
- 回读: `Blocks/13_roc/01block_ROC.R` 文件头注释

#### `simple_ROC`
- 路径: `Blocks/13_roc/02block_simple_ROC.R`
- 用途: ##############################################################################
- 典型位置: … → multivariate_*_harmonized → simple_ROC → …
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_config = config$roc_simple (optional; falls back to incidence/logistic)`
- config 节: `config$roc_simple`
- 回读: `Blocks/13_roc/02block_simple_ROC.R` 文件头注释


### `14_cutoff/`

#### `cutoff`
- 路径: `Blocks/14_cutoff/01block_cutoff.R`
- 用途: ##############################################################################
- 典型位置: imputation → cutoff → obj（NHANES 专用）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- config 节: `config$cutoff`, `config$data`, `config$incidence`, `config$nhanes`
- 回读: `Blocks/14_cutoff/01block_cutoff.R` 文件头注释


### `15_rcs/`

#### `rcs_incidence`
- 路径: `Blocks/15_rcs/02block_rcs_incidence.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned（pipeline 决定数据源，块内不切换）`; `require_study = project$study_type == "incidence"（非 incidence 则跳过）`
- config 节: `config$rcs_incidence`
- 回读: `Blocks/15_rcs/02block_rcs_incidence.R` 文件头注释

#### `rcs_iptw_weighted`
- 路径: `Blocks/15_rcs/04block_rcs_iptw_weighted.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → logistic_*_iptw_weighted（可选）→ rcs_iptw_weighted
- 写出: ctx$results$rcs_iptw_*、iptw_design_rcs、cutoff_value、<Index>_RCS_Group
- config 节: `config$rcs_iptw_weighted`
- 回读: `Blocks/15_rcs/04block_rcs_iptw_weighted.R` 文件头注释

#### `rcs_nhanes`
- 路径: `Blocks/15_rcs/03block_rcs_nhanes.R`
- 用途: ##############################################################################
- 典型位置: imputation → cutoff → obj → rcs_nhanes（.is_nhanes_db 为真）
- 前置: `require_results = ctx$results$nhanes_design（须先 run_block("obj")）`
- 写出: ctx$results$nhanes_rcs（crude/model1/model2 预测与 P 值）； nhanes_rcs_cutoffs_all / nhanes_rcs_primary_cutoff（Model2 曲线切点，对齐 rcs_incidence）； rcs_nhanes_figure；rcs_nhanes_model1|2_factors
- config 节: `config$rcs_nhanes`
- 回读: `Blocks/15_rcs/03block_rcs_nhanes.R` 文件头注释

#### `rcs_prognosis`
- 路径: `Blocks/15_rcs/01block_rcs_prognosis.R`
- 用途: ##############################################################################
- 典型位置: imputation → … → rcs_prognosis（study_type = prognosis）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = config$project$study_type == "prognosis"（否则跳过）`
- 写出: rcs_cutoff / cutoff_value = Model2 曲线切点（见 utils.R rcs_refined_cutoffs）； rcs_prognosis_nk, res_crude|model1|model2, rcs_prognosis_figure cutoff 规则: 仅 1 个 HR=1 → 该 x；≥2 个 HR=1 时斜率=0 峰值仅当其落在两 HR=1 之间才保留 图: 无背景密度；Model 2（C）H
- config 节: `config$cox`, `config$project`, `config$rcs_prognosis`, `config$survival`
- 回读: `Blocks/15_rcs/01block_rcs_prognosis.R` 文件头注释

#### `rcs_prognosis_by_group`
- 路径: `Blocks/15_rcs/04block_rcs_prognosis_by_group.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = config$project$study_type == "prognosis"（非 prognosis 时 warning 跳过）`; `require_config = config$survival（time_var / event_var / event_value 必填，块内无兜底）`
- 写出: ctx$results$rcs_prognosis_by_group_curve, rcs_prognosis_by_group_nk_global, rcs_prognosis_by_group_ref, rcs_prognosis_by_group_overlap_range, rcs_prognosis_by_group_strata_ok, rcs_prognosis_by_group_fail_log（内存，不落盘）
- config 节: `config$project`, `config$rcs_prognosis_by_group`, `config$survival`
- 回读: `Blocks/15_rcs/04block_rcs_prognosis_by_group.R` 文件头注释


### `16_weightcox/`

#### `segmented_cox_binary`
- 路径: `Blocks/16_weightcox/01block_segmented_cox_binary.R`
- 用途: ##############################################################################
- 典型位置: … → multicollinearity → 10_cox → 15_rcs → segmented_cox_binary → [weightcox 图/KM]
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_hr_direction="auto" 下不卡方向`; `require_hr_direction = "auto", # auto|none；auto=有 10_cox anchor 才卡 HR 方向`
- 写出: ctx$results$segmented_cox_binary, ctx$results$segmented_cox（兼容别名） Tables/Table S#. Segmented Cox of <index> and <disease>.xlsx（pub 自动编号） 表注：段内 median split 口径 + LLR 口径 + 切点来源（RCS primary cutoff） Segmented_Cox_binary_samp
- config 节: `config$cutoff`, `config$segmented_cox_binary`, `config$survival`, `config$weightcox`
- 回读: `Blocks/16_weightcox/01block_segmented_cox_binary.R` 文件头注释

#### `segmented_cox_quartile`
- 路径: `Blocks/16_weightcox/03block_segmented_cox_quartile.R`
- 用途: ##############################################################################
- 典型位置: … → multicollinearity → cox_quartile → segmented_cox_quartile
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_cox = 须先 run_block(ctx, "cox_quartile")`; `require_hr_direction = "auto"）`; `require_hr_direction = "auto",`
- 写出: ctx$results$segmented_cox_quartile Tables/Table S4. Segmented Cox (quartile) of <index> and <disease>.xlsx Table 共 4 行 HR + 1 行 Log-likelihood ratio 不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
- config 节: `config$segmented_cox_quartile`, `config$survival`
- 回读: `Blocks/16_weightcox/03block_segmented_cox_quartile.R` 文件头注释

#### `segmented_cox_quintile`
- 路径: `Blocks/16_weightcox/04block_segmented_cox_quintile.R`
- 用途: ##############################################################################
- 典型位置: … → multicollinearity → cox_quintile → segmented_cox_quintile
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_cox = 须先 run_block(ctx, "cox_quintile")`; `require_hr_direction = "auto",`
- 写出: ctx$results$segmented_cox_quintile Tables/Table S4. Segmented Cox (quintile) of <index> and <disease>.xlsx Table 共 5 行 HR + 1 行 Log-likelihood ratio 不写: cutoff PDF, KM PDF, imputed_for_index_cut_baseline.RData
- config 节: `config$segmented_cox_quintile`, `config$survival`
- 回读: `Blocks/16_weightcox/04block_segmented_cox_quintile.R` 文件头注释

#### `segmented_cox_tertile`
- 路径: `Blocks/16_weightcox/02block_segmented_cox_tertile.R`
- 用途: ##############################################################################
- 典型位置: … → multicollinearity → cox_tertile → segmented_cox_tertile
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_cox = 须先 run_block(ctx, "cox_tertile")`; `require_hr_direction="auto" 下不卡方向`; `require_cox_method = "tertile", # 与 ctx$results$cox_grouping$method 校验`; `require_hr_direction = "auto", # auto|none`
- 写出: ctx$results$segmented_cox_tertile（breaks, segment_results, loglik_p, table, …） Tables/Table S4. Segmented Cox (tertile) of <index> and <disease>.xlsx Table 共 3 行 HR（Q1/Q2/Q3 各段层内 high vs low）+ 1 行 Log-likelihood ratio 不写
- config 节: `config$segmented_cox_tertile`, `config$survival`
- 回读: `Blocks/16_weightcox/02block_segmented_cox_tertile.R` 文件头注释


### `17_shap/`

#### `shap`
- 路径: `Blocks/17_shap/01block_shap.R`
- 用途: ##############################################################################
- 典型位置: ml_models 之后；建议包 shapviz、cowplot
- 前置: `require_results = ctx$results$ml_models[[tag]]（parsnip fit + recipe）`
- config 节: `config$shap`
- 回读: `Blocks/17_shap/01block_shap.R` 文件头注释


### `18_subgroup/`

#### `subgroup_environment_or`
- 路径: `Blocks/18_subgroup/09block_subgroup_environment_or.R`
- 用途: ##############################################################################
- 典型位置: glm_environment_quartile → subgroup_environment_or
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$data`, `config$subgroup_environment_or`
- 回读: `Blocks/18_subgroup/09block_subgroup_environment_or.R` 文件头注释

#### `subgroup_incidence`
- 路径: `Blocks/18_subgroup/02block_subgroup_incidence.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_config = config$subgroup, incidence$outcome_var/index_var, logistic$index_var`
- config 节: `config$subgroup`
- 回读: `Blocks/18_subgroup/02block_subgroup_incidence.R` 文件头注释

#### `subgroup_incidence_continuous`
- 路径: `Blocks/18_subgroup/05block_subgroup_incidence_continuous.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_config = config$subgroup, incidence$outcome_var/index_var, logistic$index_var`
- config 节: `config$subgroup`
- 回读: `Blocks/18_subgroup/05block_subgroup_incidence_continuous.R` 文件头注释

#### `subgroup_iptw_weighted`
- 路径: `Blocks/18_subgroup/08block_subgroup_iptw_weighted.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → logistic_*_iptw_weighted（可选）→ subgroup_iptw_weighted
- config 节: `config$subgroup`, `config$subgroup_iptw_weighted`
- 回读: `Blocks/18_subgroup/08block_subgroup_iptw_weighted.R` 文件头注释

#### `subgroup_nhanes_weighted`
- 路径: `Blocks/18_subgroup/03block_subgroup_nhanes_weighted.R`
- 用途: ##############################################################################
- 前置: `require_ctx_results = nhanes_logistic_selected_scheme 或 nhanes_design_*`
- config 节: `config$logistic`, `config$nhanes`, `config$subgroup`
- 回读: `Blocks/18_subgroup/03block_subgroup_nhanes_weighted.R` 文件头注释

#### `subgroup_prognosis`
- 路径: `Blocks/18_subgroup/01block_subgroup_prognosis.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_config = config$subgroup, survival$time_var/event_var, logistic$index_var`
- config 节: `config$subgroup`
- 回读: `Blocks/18_subgroup/01block_subgroup_prognosis.R` 文件头注释

#### `subgroup_treatment_forest`
- 路径: `Blocks/18_subgroup/07block_subgroup_treatment_forest.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_config = config$subgroup_treatment_forest, config$survival`
- 写出: ctx$results$subgroup_treatment_forest, subgroup_treatment_ref, subgroup_treatment_vars
- config 节: `config$subgroup_treatment_forest`, `config$survival`
- 回读: `Blocks/18_subgroup/07block_subgroup_treatment_forest.R` 文件头注释

#### `unsupervised_clustering_table`
- 路径: `Blocks/18_subgroup/06block_subgroup_unsupervised_clustering.R`
- 用途: ##############################################################################
- 写出: ctx$results$unsupervised_clustering_table (final data frame)
- config 节: `config$unsupervised_clustering_table`
- 回读: `Blocks/18_subgroup/06block_subgroup_unsupervised_clustering.R` 文件头注释


### `19_feature_selection/`

#### `feature_selection_bagged_trees`
- 路径: `Blocks/19_feature_selection/05block_feature_selection_bagged_trees.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = caret, ipred`
- 回读: `Blocks/19_feature_selection/05block_feature_selection_bagged_trees.R` 文件头注释

#### `feature_selection_bayesian`
- 路径: `Blocks/19_feature_selection/03block_feature_selection_bayesian.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = caret, klaR`
- 回读: `Blocks/19_feature_selection/03block_feature_selection_bayesian.R` 文件头注释

#### `feature_selection_boruta`
- 路径: `Blocks/19_feature_selection/02block_feature_selection_boruta.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = Boruta`
- 回读: `Blocks/19_feature_selection/02block_feature_selection_boruta.R` 文件头注释

#### `feature_selection_consensus`
- 路径: `Blocks/19_feature_selection/07block_feature_selection_consensus.R`
- 用途: ##############################################################################
- 典型位置: 01–06 方法块 → 本块 → 08 韦恩图（可选）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = ctx$results$feature_selection_by_model # 须先跑 01–06 各方法块`; `require_min_composites_in_auto = FALSE,`
- 回读: `Blocks/19_feature_selection/07block_feature_selection_consensus.R` 文件头注释

#### `feature_selection_lasso`
- 路径: `Blocks/19_feature_selection/01block_feature_selection_lasso.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = glmnet（Cox 路径另需 survival）`
- 回读: `Blocks/19_feature_selection/01block_feature_selection_lasso.R` 文件头注释

#### `feature_selection_lasso_cox`
- 路径: `Blocks/19_feature_selection/10block_feature_selection_lasso_cox.R`
- 用途: ##############################################################################
- 典型位置: univariate_prognosis → ml_vif_train_test → 本块
- 前置: `require_data = ctx$data$train（优先）/ imputed；须含 survival$time_var / event_var`; `require_ctx_results = Model2Factors 或 vif_screen_pass（UV→VIF 后）`; `require_packages = glmnet, survival；拼图建议 cowplot；热图建议 corrplot`
- 回读: `Blocks/19_feature_selection/10block_feature_selection_lasso_cox.R` 文件头注释

#### `feature_selection_lvq`
- 路径: `Blocks/19_feature_selection/06block_feature_selection_lvq.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = caret`
- 回读: `Blocks/19_feature_selection/06block_feature_selection_lvq.R` 文件头注释

#### `feature_selection_random_forest`
- 路径: `Blocks/19_feature_selection/04block_feature_selection_random_forest.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity → 本块 → feature_selection_consensus
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned # 由 pipeline 决定，块内不选源`; `require_ctx_results = Model2Factors（标准路径，须先跑 multicollinearity）`; `require_packages = caret, randomForest`
- 回读: `Blocks/19_feature_selection/04block_feature_selection_random_forest.R` 文件头注释

#### `feature_selection_venn`
- 路径: `Blocks/19_feature_selection/08block_feature_selection_venn.R`
- 用途: ##############################################################################
- 前置: `require_ctx_results = feature_selection_final`; `require_ctx_results = feature_selection_venn_input # 由 feature_selection_consensus (07) 写入`; `require_block = feature_selection_consensus（须先跑 07；或 RDS 含 venn_input）`
- 回读: `Blocks/19_feature_selection/08block_feature_selection_venn.R` 文件头注释

#### `lasso_environment_voc`
- 路径: `Blocks/19_feature_selection/09block_lasso_environment_voc.R`
- 用途: ##############################################################################
- 典型位置: process_environment_data → lasso_environment_voc → logistic_environment_glm
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs（可选；若为 NULL 则使用 ctx$data 中所有数值列）`
- config 节: `config$data`, `config$lasso_environment`, `config$project`
- 回读: `Blocks/19_feature_selection/09block_lasso_environment_voc.R` 文件头注释


### `20_mediation/`

#### `mediation_ers_environment`
- 路径: `Blocks/20_mediation/04block_mediation_ers_environment.R`
- 用途: ##############################################################################
- 典型位置: glm_environment_quartile → mediation_ers_environment
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$data`, `config$mediation_ers_environment`
- 回读: `Blocks/20_mediation/04block_mediation_ers_environment.R` 文件头注释

#### `mediation_incidence`
- 路径: `Blocks/20_mediation/02block_mediation_incidence.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = ctx$results$Model2Factors`
- 回读: `Blocks/20_mediation/02block_mediation_incidence.R` 文件头注释

#### `mediation_longitudinal`
- 路径: `Blocks/20_mediation/06block_mediation_longitudinal.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/06block_mediation_longitudinal.R` 文件头注释

#### `mediation_nhanes_weighted`
- 路径: `Blocks/20_mediation/03block_mediation_nhanes_weighted.R`
- 用途: ##############################################################################
- config 节: `config$mediation_nhanes_weighted`
- 回读: `Blocks/20_mediation/03block_mediation_nhanes_weighted.R` 文件头注释

#### `mediation_prognosis`
- 路径: `Blocks/20_mediation/01block_mediation_prognosis.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = ctx$results$Model2Factors`
- config 节: `config$mediation_prognosis`
- 回读: `Blocks/20_mediation/01block_mediation_prognosis.R` 文件头注释

#### `mediation_subgroup_router`
- 路径: `Blocks/20_mediation/05block_mediation_subgroup_router.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/05block_mediation_subgroup_router.R` 文件头注释

#### `modmed_data_prep`
- 路径: `Blocks/20_mediation/07block_modmed_data_prep.R`
- 用途: ##############################################################################
- config 节: `config$modmed`, `config$modmed_data_prep`
- 回读: `Blocks/20_mediation/07block_modmed_data_prep.R` 文件头注释

#### `modmed_mediation_batch`
- 路径: `Blocks/20_mediation/09block_modmed_mediation_batch.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/09block_modmed_mediation_batch.R` 文件头注释

#### `modmed_moderated_mediation`
- 路径: `Blocks/20_mediation/11block_modmed_moderated_mediation.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/11block_modmed_moderated_mediation.R` 文件头注释

#### `modmed_moderation`
- 路径: `Blocks/20_mediation/10block_modmed_moderation.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/10block_modmed_moderation.R` 文件头注释

#### `modmed_simple_slopes`
- 路径: `Blocks/20_mediation/12block_modmed_simple_slopes.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/12block_modmed_simple_slopes.R` 文件头注释

#### `modmed_spearman`
- 路径: `Blocks/20_mediation/08block_modmed_spearman.R`
- 用途: ##############################################################################
- 回读: `Blocks/20_mediation/08block_modmed_spearman.R` 文件头注释


### `21_train_validation/`

#### `train_validation`
- 路径: `Blocks/21_train_validation/01block_train_validation.R`
- 用途: ##############################################################################
- 典型位置: imputation 之后、ml_models 之前；enable=FALSE 时需自行赋值 ctx$data$train/test
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- config 节: `config$train_validation`
- 回读: `Blocks/21_train_validation/01block_train_validation.R` 文件头注释


### `22_ml_models/`

#### `cart_decision_path`
- 路径: `Blocks/22_ml_models/21block_cart_decision_path.R`
- 用途: ##############################################################################
- 典型位置: train_validation → ml_feature_selection_bundle → 本块 → ml_models_bundle
- 前置: `require_data = ctx$data$train（data_scope=train）或 imputed/cleaned（analysis）`; `require_ctx_results = feature_selection_final（可选）或 Model2Factors / config$features`
- config 节: `config$features`
- 回读: `Blocks/22_ml_models/21block_cart_decision_path.R` 文件头注释

#### `ml_adaboost`
- 路径: `Blocks/22_ml_models/11block_ml_adaboost.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/11block_ml_adaboost.R` 文件头注释

#### `ml_aggregate`
- 路径: `Blocks/22_ml_models/17block_ml_aggregate.R`
- 用途: ##############################################################################
- 回读: `Blocks/22_ml_models/17block_ml_aggregate.R` 文件头注释

#### `ml_catboost`
- 路径: `Blocks/22_ml_models/12block_ml_catboost.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/12block_ml_catboost.R` 文件头注释

#### `ml_coxboost`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_dt`
- 路径: `Blocks/22_ml_models/01block_ml_dt.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/01block_ml_dt.R` 文件头注释

#### `ml_enet`
- 路径: `Blocks/22_ml_models/04block_ml_enet.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/04block_ml_enet.R` 文件头注释

#### `ml_enet_cox`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_gbmsurv`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_knn`
- 路径: `Blocks/22_ml_models/10block_ml_knn.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/10block_ml_knn.R` 文件头注释

#### `ml_lightgbm`
- 路径: `Blocks/22_ml_models/09block_ml_lightgbm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/09block_ml_lightgbm.R` 文件头注释

#### `ml_logistic`
- 路径: `Blocks/22_ml_models/08block_ml_logistic.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/08block_ml_logistic.R` 文件头注释

#### `ml_mboost_cox`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_mlp`
- 路径: `Blocks/22_ml_models/06block_ml_mlp.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/06block_ml_mlp.R` 文件头注释

#### `ml_realmlp`
- 路径: `Blocks/22_ml_models/07block_ml_realmlp.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/07block_ml_realmlp.R` 文件头注释

#### `ml_realtabpfn_2_5`
- 路径: `Blocks/22_ml_models/15block_ml_realtabpfn_2_5.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/15block_ml_realtabpfn_2_5.R` 文件头注释

#### `ml_rf`
- 路径: `Blocks/22_ml_models/02block_ml_rf.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/02block_ml_rf.R` 文件头注释

#### `ml_ridge_cox`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_rsf`
- 路径: `Blocks/22_ml_models/18block_ml_rsf.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate（prognosis）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）`
- config 节: `config$survival`
- 回读: `Blocks/22_ml_models/18block_ml_rsf.R` 文件头注释

#### `ml_rsvm`
- 路径: `Blocks/22_ml_models/05block_ml_rsvm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/05block_ml_rsvm.R` 文件头注释

#### `ml_survivalsvm`
- 路径: `Blocks/22_ml_models/20block_ml_surv_extra_models.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本系列 → ml_aggregate → performance_ml
- 回读: `Blocks/22_ml_models/20block_ml_surv_extra_models.R` 文件头注释

#### `ml_tablcl_v2`
- 路径: `Blocks/22_ml_models/16block_ml_tablcl_v2.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/16block_ml_tablcl_v2.R` 文件头注释

#### `ml_tabpfn`
- 路径: `Blocks/22_ml_models/13block_ml_tabpfn.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/13block_ml_tabpfn.R` 文件头注释

#### `ml_tabpfnv2`
- 路径: `Blocks/22_ml_models/14block_ml_tabpfnv2.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/14block_ml_tabpfnv2.R` 文件头注释

#### `ml_xgboost`
- 路径: `Blocks/22_ml_models/03block_ml_xgboost.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）或 Model2Factors`
- 回读: `Blocks/22_ml_models/03block_ml_xgboost.R` 文件头注释

#### `ml_xgbsurv`
- 路径: `Blocks/22_ml_models/19block_ml_xgbsurv.R`
- 用途: ##############################################################################
- 典型位置: train_validation → 本块 → ml_aggregate（prognosis）
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = feature_selection_final（feature_selection 启用时）`
- config 节: `config$survival`
- 回读: `Blocks/22_ml_models/19block_ml_xgbsurv.R` 文件头注释


### `23_ml_performance/`

#### `performance_ml`
- 路径: `Blocks/23_ml_performance/01block_performance_ml.R`
- 用途: ##############################################################################
- 典型位置: train_validation → ml_models → performance_ml（勿与父块重复 source）
- 前置: `require_results = ctx$results$ml_eval_all, ctx$results$ml_models`; `require_data = ctx$data$train / test（ROC/校准/DCA）；Models/evalresult_<tag>.RData`
- config 节: `config$performance_ml`
- 回读: `Blocks/23_ml_performance/01block_performance_ml.R` 文件头注释


### `24_ml_dual/`

#### `ml_assoc_bundle`
- 路径: `Blocks/24_ml_dual/05block_ml_assoc_bundle.R`
- 用途: ##############################################################################
- 回读: `Blocks/24_ml_dual/05block_ml_assoc_bundle.R` 文件头注释

#### `ml_assoc_covariate_resolve`
- 路径: `Blocks/24_ml_dual/07block_ml_assoc_covariate_resolve.R`
- 用途: ##############################################################################
- 典型位置: ml_feature_selection_bundle 之后、ml_assoc_bundle 之前
- config 节: `config$assoc_covariate`
- 回读: `Blocks/24_ml_dual/07block_ml_assoc_covariate_resolve.R` 文件头注释

#### `ml_eval_external`
- 路径: `Blocks/24_ml_dual/08block_ml_eval_external.R`
- 用途: ##############################################################################
- 典型位置: ml_inherit_primary_features → 本块（次库 split_mode=dev_internal_ext）
- config 节: `config$ml_eval_external`
- 回读: `Blocks/24_ml_dual/08block_ml_eval_external.R` 文件头注释

#### `ml_feature_selection_bundle`
- 路径: `Blocks/24_ml_dual/02block_ml_feature_selection_bundle.R`
- 用途: ##############################################################################
- 回读: `Blocks/24_ml_dual/02block_ml_feature_selection_bundle.R` 文件头注释

#### `ml_id_deduplicate`
- 路径: `Blocks/24_ml_dual/00block_ml_id_deduplicate.R`
- 用途: ##############################################################################
- 典型位置: 本块 → data_clean → column_mapping → …（仅 ML 双库 / ML 预测）
- config 节: `config$data`
- 回读: `Blocks/24_ml_dual/00block_ml_id_deduplicate.R` 文件头注释

#### `ml_inherit_primary_features`
- 路径: `Blocks/24_ml_dual/01block_ml_inherit_primary_features.R`
- 用途: ##############################################################################
- 典型位置: imputation → 本块 → train_validation → ml_models_bundle …
- config 节: `config$dual_db`
- 回读: `Blocks/24_ml_dual/01block_ml_inherit_primary_features.R` 文件头注释

#### `ml_logistic_multi_index_bundle`
- 路径: `Blocks/24_ml_dual/04block_ml_logistic_multi_index_bundle.R`
- 用途: ##############################################################################
- 回读: `Blocks/24_ml_dual/04block_ml_logistic_multi_index_bundle.R` 文件头注释

#### `ml_models_bundle`
- 路径: `Blocks/24_ml_dual/03block_ml_models_bundle.R`
- 用途: ##############################################################################
- config 节: `config$ml_models`
- 回读: `Blocks/24_ml_dual/03block_ml_models_bundle.R` 文件头注释

#### `ml_stratified_reference_profile`
- 路径: `Blocks/24_ml_dual/09block_ml_stratified_reference_profile.R`
- 用途: ##############################################################################
- 典型位置: publication_literature_final 组装阶段（Task 8 CLI 调用；本任务
- config 节: `config$ml_stratified_reference_profile`
- 回读: `Blocks/24_ml_dual/09block_ml_stratified_reference_profile.R` 文件头注释

#### `ml_vif_train_test`
- 路径: `Blocks/24_ml_dual/06block_ml_vif_train_test.R`
- 用途: ##############################################################################
- 回读: `Blocks/24_ml_dual/06block_ml_vif_train_test.R` 文件头注释


### `24_ml_supplementary/`

#### `supplementary_ml`
- 路径: `Blocks/24_ml_supplementary/01block_supplementary_ml.R`
- 用途: ##############################################################################
- 典型位置: ml_models → supplementary_ml（勿与父块重复 source）
- 前置: `require_results = ctx$results$ml_models；Data/Hpbest.RData、Models/evalresult_<tag>.RData`; `require_data = ctx$data$train / test（logloss / delong / nri_idi）；超参数表仅需 Hpbest`
- config 节: `config$supplementary_ml`
- 回读: `Blocks/24_ml_supplementary/01block_supplementary_ml.R` 文件头注释


### `25_shiny/`

#### `shiny_dynnom`
- 路径: `Blocks/25_shiny/01block_shiny_dynnom.R`
- 用途: ##############################################################################
- 典型位置: feature_selection → train_validation → shiny_dynnom
- 前置: `require_data = train_validation/Data/df_train_RData.RData`; `require_results = Model2Factors（ctx 或 feature_selection/Model2Factors.RData）`
- config 节: `config$shiny`
- 回读: `Blocks/25_shiny/01block_shiny_dynnom.R` 文件头注释

#### `shiny_ml_app`
- 路径: `Blocks/25_shiny/02block_shiny_ml_app.R`
- 用途: ##############################################################################
- 典型位置: train_validation → ml_models → shiny_ml_app
- 前置: `require_data = train_validation/Data；ml_models/Models/evalresult_<tag>.RData`; `require_results = Model2Factors、ml_best_model_tag（或 shiny_ml_app$ml_model_tag）`
- config 节: `config$shiny`
- 回读: `Blocks/25_shiny/02block_shiny_ml_app.R` 文件头注释


### `26_trajectory/`

#### `trajectory_chisq`
- 路径: `Blocks/26_trajectory/05block_trajectory_chisq.R`
- 用途: ##############################################################################
- config 节: `config$trajectory`
- 回读: `Blocks/26_trajectory/05block_trajectory_chisq.R` 文件头注释

#### `trajectory_dynpred`
- 路径: `Blocks/26_trajectory/06block_trajectory_dynpred.R`
- 用途: ##############################################################################
- config 节: `config$plot`, `config$trajectory`
- 回读: `Blocks/26_trajectory/06block_trajectory_dynpred.R` 文件头注释

#### `trajectory_gbmt`
- 路径: `Blocks/26_trajectory/01block_trajectory_gbmt.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed_with_id %||% ctx$data$imputed # pipeline 决定，块内不选源`; `require_pkg = gbmt, dplyr, tidyr, stringr, cli`
- config 节: `config$data`
- 回读: `Blocks/26_trajectory/01block_trajectory_gbmt.R` 文件头注释

#### `trajectory_jlcm`
- 路径: `Blocks/26_trajectory/02block_trajectory_jlcm.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed_with_id %||% ctx$data$imputed # pipeline 决定，块内不选源`; `require_pkg = lcmm, survival, splines, dplyr, tidyr, stringr, cli`
- 写出: ctx$data$trajectory_long, ctx$data$imputed/cleaned 新增 trajectory_class 列， ctx$results$trajectory_jlcm_models, ctx$results$trajectory_ic_table 落盘: Data/D01_long_{Index}_D_{D}.RData, Data/D01_jlcm_{Index}_models.RData, Tab
- config 节: `config$survival`
- 回读: `Blocks/26_trajectory/02block_trajectory_jlcm.R` 文件头注释

#### `trajectory_plot_gbmt`
- 路径: `Blocks/26_trajectory/03block_trajectory_plot_gbmt.R`
- 用途: ##############################################################################
- 前置: `require_ctx_data = ctx$data$trajectory_long（或 long_data_dir 磁盘兜底）`; `require_upstream = trajectory_gbmt（或已有 D01_long_*.RData）`
- 回读: `Blocks/26_trajectory/03block_trajectory_plot_gbmt.R` 文件头注释

#### `trajectory_plot_jlcm`
- 路径: `Blocks/26_trajectory/04block_trajectory_plot_jlcm.R`
- 用途: ##############################################################################
- 前置: `require_ctx_data = ctx$data$trajectory_long（或 long_data_dir 磁盘兜底）`; `require_ctx_results = ctx$results$trajectory_jlcm_models（或 jlcm_model_dir 兜底）`; `require_upstream = trajectory_jlcm`
- 回读: `Blocks/26_trajectory/04block_trajectory_plot_jlcm.R` 文件头注释


### `27_KM/`

#### `km_binary`
- 路径: `Blocks/27_KM/01block_km_binary.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- config 节: `config$km`
- 回读: `Blocks/27_KM/01block_km_binary.R` 文件头注释

#### `km_continuous_router`
- 路径: `Blocks/27_KM/03block_km_continuous_router.R`
- 用途: ##############################################################################
- 回读: `Blocks/27_KM/03block_km_continuous_router.R` 文件头注释

#### `km_strata`
- 路径: `Blocks/27_KM/02block_km_strata.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- 写出: ctx$data$km_strata_derived（仅 ID + 派生/分层列 + time/event，不污染 imputed）
- 回读: `Blocks/27_KM/02block_km_strata.R` 文件头注释


### `28_plot/`

#### `plot_cutoff`
- 路径: `Blocks/28_plot/01block_plot_cutoff.R`
- 用途: ##############################################################################
- 回读: `Blocks/28_plot/01block_plot_cutoff.R` 文件头注释

#### `plot_histogram`
- 路径: `Blocks/28_plot/02block_histogram.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_lca = ctx$results$df_final (Subphenotype column from block_lca)`
- config 节: `config$data`
- 回读: `Blocks/28_plot/02block_histogram.R` 文件头注释


### `29_chord_diagram/`

#### `chord_diagram`
- 路径: `Blocks/29_chord_diagram/01block_chord_diagram.R`
- 用途: ##############################################################################
- 前置: `require_ctx_results = lca_results, lca_selected_vars, df_final, lca_optimal_k`; `require_block = block_lca（须在 lca 之后）；自动 source 同目录 block_system_map_library.R`
- 回读: `Blocks/29_chord_diagram/01block_chord_diagram.R` 文件头注释


### `30_lca/`

#### `lca`
- 路径: `Blocks/30_lca/01block_lca.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- 回读: `Blocks/30_lca/01block_lca.R` 文件头注释


### `31_subtype_viz/`

#### `subtype_viz`
- 路径: `Blocks/31_subtype_viz/01block_subtype_viz.R`
- 用途: ##############################################################################
- 前置: `require_ctx_results = lca_results, lca_selected_vars, df_final, lca_optimal_k`; `require_block = lca（须在 lca 之后）`
- 回读: `Blocks/31_subtype_viz/01block_subtype_viz.R` 文件头注释


### `32_stepp/`

#### `stepp_prognosis`
- 路径: `Blocks/32_stepp/01block_stepp_prognosis.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = config$project$study_type == "prognosis"`; `require_config = config$survival（time_var / event_var / event_value 必填，块内无兜底）`
- 写出: ctx$results$stepp_prognosis_overall_results, stepp_prognosis_by_group_results, stepp_prognosis_overall_rate, stepp_prognosis_index_median, stepp_prognosis_by_group_fail_log, stepp_prognosis_figure
- config 节: `config$project`, `config$stepp_prognosis`, `config$survival`
- 回读: `Blocks/32_stepp/01block_stepp_prognosis.R` 文件头注释


### `33_composite_risk_score/`

#### `composite_risk_cox`
- 路径: `Blocks/33_composite_risk_score/01block_composite_risk_cox.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = config$project$study_type == "prognosis"`; `require_config = config$survival（time_var / event_var / event_value 必填）`
- 写出: ctx$data$imputed（追加 score_var） ctx$results$composite_risk_cox_model, composite_risk_cox_coef_table, composite_risk_score_var, composite_risk_predictors（实际使用的变量名）
- config 节: `config$composite_risk_cox`, `config$project`, `config$survival`
- 回读: `Blocks/33_composite_risk_score/01block_composite_risk_cox.R` 文件头注释


### `34_IPTW/`

#### `iptw_association`
- 路径: `Blocks/34_IPTW/02block_iptw_association.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → iptw_association
- 写出: ctx$results$iptw_association_table
- config 节: `config$iptw_association`
- 回读: `Blocks/34_IPTW/02block_iptw_association.R` 文件头注释

#### `iptw_balance`
- 路径: `Blocks/34_IPTW/01block_iptw_balance.R`
- 用途: ##############################################################################
- 写出: ctx$data$iptw_weighted, ctx$results$iptw_design, iptw_high_smd_vars, iptw_balance_table
- config 节: `config$iptw_balance`
- 回读: `Blocks/34_IPTW/01block_iptw_balance.R` 文件头注释


### `35_environment_function/`

#### `environment_lod_screen`
- 路径: `Blocks/35_environment_function/07block_environment_lod_screen.R`
- 用途: ##############################################################################
- 典型位置: column_mapping → environment_lod_screen → imputation
- 回读: `Blocks/35_environment_function/07block_environment_lod_screen.R` 文件头注释

#### `environment_subgroup_search`
- 路径: `Blocks/35_environment_function/05block_environment_subgroup_search.R`
- 用途: ##############################################################################
- 回读: `Blocks/35_environment_function/05block_environment_subgroup_search.R` 文件头注释

#### `environment_voc_clinical_gate`
- 路径: `Blocks/35_environment_function/02block_environment_voc_clinical_gate.R`
- 用途: ##############################################################################
- 回读: `Blocks/35_environment_function/02block_environment_voc_clinical_gate.R` 文件头注释

#### `environment_voc_corrplot`
- 路径: `Blocks/35_environment_function/08block_environment_voc_corrplot.R`
- 用途: ##############################################################################
- 典型位置: multicollinearity_nhanes_final → environment_voc_corrplot → environment_voc_clinical_gate
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx = voc_columns（来自 environment_lod_screen）`
- config 节: `config$environment_corrplot`
- 回读: `Blocks/35_environment_function/08block_environment_voc_corrplot.R` 文件头注释

#### `environment_voc_extreme_trim`
- 路径: `Blocks/35_environment_function/06block_environment_voc_extreme_trim.R`
- 用途: ##############################################################################
- 回读: `Blocks/35_environment_function/06block_environment_voc_extreme_trim.R` 文件头注释

#### `environment_voc_log_transform`
- 路径: `Blocks/35_environment_function/00block_environment_voc_log_transform.R`
- 用途: ##############################################################################
- config 节: `config$environment_voc_log_transform`
- 回读: `Blocks/35_environment_function/00block_environment_voc_log_transform.R` 文件头注释

#### `prepare_environment_dkd_data`
- 路径: `Blocks/35_environment_function/00block_prepare_environment_dkd_data.R`
- 用途: ##############################################################################
- 典型位置: 第一步（在 data_clean 之前）
- 回读: `Blocks/35_environment_function/00block_prepare_environment_dkd_data.R` 文件头注释

#### `process_environment_data`
- 路径: `Blocks/35_environment_function/01block_process_environment_data.R`
- 用途: ##############################################################################
- 典型位置: column_mapping → process_environment_data → logistic_environment_glm
- 前置: `require_data = ctx$data$mapped %||% ctx$data$cleaned`
- config 节: `config$environment_process`
- 回读: `Blocks/35_environment_function/01block_process_environment_data.R` 文件头注释

#### `remove_outliers`
- 路径: `Blocks/35_environment_function/02block_remove_outliers.R`
- 用途: ##############################################################################
- 典型位置: imputation / process_environment_data → remove_outliers → 分析 block
- 前置: `require_data = ctx$data[[data_slot]]（优先 imputed，回退 cleaned）`
- config 节: `config$remove_outliers`
- 回读: `Blocks/35_environment_function/02block_remove_outliers.R` 文件头注释

#### `table1_summary`
- 路径: `Blocks/35_environment_function/03block_table1_summary.R`
- 用途: ##############################################################################
- config 节: `config$table1_summary`
- 回读: `Blocks/35_environment_function/03block_table1_summary.R` 文件头注释


### `36_capability/`

#### `sensitivity_scenarios`
- 路径: `Blocks/36_capability/01block_sensitivity_scenarios.R`
- 用途: ##############################################################################
- 回读: `Blocks/36_capability/01block_sensitivity_scenarios.R` 文件头注释


### `36_environment_glm/`

#### `glm_environment_quartile`
- 路径: `Blocks/36_environment_glm/01block_glm_environment_quartile.R`
- 用途: ##############################################################################
- 典型位置: lasso_environment_voc → glm_environment_quartile
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs # 上游 lasso_environment_voc 写入`
- config 节: `config$data`, `config$glm_environment_quartile`
- 回读: `Blocks/36_environment_glm/01block_glm_environment_quartile.R` 文件头注释


### `37_environment_wqs/`

#### `wqs_environment`
- 路径: `Blocks/37_environment_wqs/01block_wqs_environment.R`
- 用途: ##############################################################################
- 典型位置: glm_environment_quartile → wqs_environment
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$data`, `config$wqs_environment`
- 回读: `Blocks/37_environment_wqs/01block_wqs_environment.R` 文件头注释


### `38_environment_bkmr/`

#### `bkmr_analysis`
- 路径: `Blocks/38_environment_bkmr/02block_bkmr_analysis.R`
- 用途: ##############################################################################
- 典型位置: bkmr_fit → bkmr_analysis
- 前置: `require_ctx_results = fit_bkmr, bkmr_Z, bkmr_y, bkmr_X`
- config 节: `config$bkmr_analysis`
- 回读: `Blocks/38_environment_bkmr/02block_bkmr_analysis.R` 文件头注释

#### `bkmr_fit`
- 路径: `Blocks/38_environment_bkmr/01block_bkmr_fit.R`
- 用途: ##############################################################################
- 典型位置: wqs_environment → bkmr_fit → bkmr_analysis
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$bkmr_fit`, `config$data`
- 回读: `Blocks/38_environment_bkmr/01block_bkmr_fit.R` 文件头注释


### `39_environment_qgcomp/`

#### `qgcomp_environment`
- 路径: `Blocks/39_environment_qgcomp/01block_qgcomp_environment.R`
- 用途: ##############################################################################
- 典型位置: glm_environment_quartile → qgcomp_environment
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$data`, `config$qgcomp_environment`
- 回读: `Blocks/39_environment_qgcomp/01block_qgcomp_environment.R` 文件头注释


### `40_environment_descriptive/`

#### `environment_characteristics`
- 路径: `Blocks/40_environment_descriptive/02block_environment_characteristics.R`
- 用途: ##############################################################################
- 典型位置: process_environment_data → environment_characteristics
- 前置: `require_ctx_results = environment_process_stats（由 process_environment_data 写入）`
- config 节: `config$environment_characteristics`
- 回读: `Blocks/40_environment_descriptive/02block_environment_characteristics.R` 文件头注释

#### `voc_correlation`
- 路径: `Blocks/40_environment_descriptive/01block_voc_correlation.R`
- 用途: ##############################################################################
- 典型位置: process_environment_data → voc_correlation
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_ctx_results = select_vocs_final（或 select_vocs）`
- config 节: `config$voc_correlation`
- 回读: `Blocks/40_environment_descriptive/01block_voc_correlation.R` 文件头注释


### `41_environment_target/`

#### `environment_target_enrichment`
- 路径: `Blocks/41_environment_target/01block_environment_target_enrichment.R`
- 用途: ##############################################################################
- 回读: `Blocks/41_environment_target/01block_environment_target_enrichment.R` 文件头注释


### `42_environment_single/`

#### `environment_single_exposure_transform`
- 路径: `Blocks/42_environment_single/01block_environment_single_exposure_transform.R`
- 用途: ##############################################################################
- 回读: `Blocks/42_environment_single/01block_environment_single_exposure_transform.R` 文件头注释


### `43_dynamic_causal/`

#### `dynamic_causal_cox_total`
- 路径: `Blocks/43_dynamic_causal/02block_dynamic_causal_cox_total.R`
- 用途: ##############################################################################
- 回读: `Blocks/43_dynamic_causal/02block_dynamic_causal_cox_total.R` 文件头注释

#### `dynamic_causal_index_compute`
- 路径: `Blocks/43_dynamic_causal/01block_dynamic_causal_index_compute.R`
- 用途: ##############################################################################
- 回读: `Blocks/43_dynamic_causal/01block_dynamic_causal_index_compute.R` 文件头注释


### `44_multimorbidity/`

#### `multimorbidity_baseline_category`
- 路径: `Blocks/44_multimorbidity/01block_multimorbidity_baseline_category.R`
- 用途: ##############################################################################
- 回读: `Blocks/44_multimorbidity/01block_multimorbidity_baseline_category.R` 文件头注释

#### `multimorbidity_gee_cognition`
- 路径: `Blocks/44_multimorbidity/02block_multimorbidity_gee_cognition.R`
- 用途: ##############################################################################
- 回读: `Blocks/44_multimorbidity/02block_multimorbidity_gee_cognition.R` 文件头注释


### `45_multimodal/`

#### `multimodal_early_fusion`
- 路径: `Blocks/45_multimodal/01block_multimodal_early_fusion.R`
- 用途: ##############################################################################
- 回读: `Blocks/45_multimodal/01block_multimodal_early_fusion.R` 文件头注释


### `46_environment_omics/`

#### `env_gsea`
- 路径: `Blocks/46_environment_omics/01block_env_omics_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/46_environment_omics/01block_env_omics_suite.R` 文件头注释

#### `env_ml_gene_screen`
- 路径: `Blocks/46_environment_omics/01block_env_omics_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/46_environment_omics/01block_env_omics_suite.R` 文件头注释

#### `env_mr_docking`
- 路径: `Blocks/46_environment_omics/01block_env_omics_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/46_environment_omics/01block_env_omics_suite.R` 文件头注释

#### `env_network_toxicology`
- 路径: `Blocks/46_environment_omics/01block_env_omics_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/46_environment_omics/01block_env_omics_suite.R` 文件头注释

#### `env_scrna_summary`
- 路径: `Blocks/46_environment_omics/01block_env_omics_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/46_environment_omics/01block_env_omics_suite.R` 文件头注释


### `47_dynamic_causal_full/`

#### `dynamic_causal_analysis_filter`
- 路径: `Blocks/47_dynamic_causal_full/01block_dynamic_causal_analysis_filter.R`
- 用途: ##############################################################################
- 回读: `Blocks/47_dynamic_causal_full/01block_dynamic_causal_analysis_filter.R` 文件头注释

#### `dynamic_causal_cox_baseline`
- 路径: `Blocks/47_dynamic_causal_full/02block_dynamic_causal_cox_baseline.R`
- 用途: ##############################################################################
- 回读: `Blocks/47_dynamic_causal_full/02block_dynamic_causal_cox_baseline.R` 文件头注释

#### `dynamic_causal_meta_merge`
- 路径: `Blocks/47_dynamic_causal_full/03block_dynamic_causal_meta_merge.R`
- 用途: ##############################################################################
- 回读: `Blocks/47_dynamic_causal_full/03block_dynamic_causal_meta_merge.R` 文件头注释

#### `dynamic_causal_rcs_change`
- 路径: `Blocks/47_dynamic_causal_full/04block_dynamic_causal_rcs_change.R`
- 用途: ##############################################################################
- 回读: `Blocks/47_dynamic_causal_full/04block_dynamic_causal_rcs_change.R` 文件头注释


### `48_multimorbidity_full/`

#### `multimorbidity_gee_interaction`
- 路径: `Blocks/48_multimorbidity_full/03block_multimorbidity_gee_interaction.R`
- 用途: ##############################################################################
- 回读: `Blocks/48_multimorbidity_full/03block_multimorbidity_gee_interaction.R` 文件头注释

#### `multimorbidity_gee_stratified`
- 路径: `Blocks/48_multimorbidity_full/02block_multimorbidity_gee_stratified.R`
- 用途: ##############################################################################
- 回读: `Blocks/48_multimorbidity_full/02block_multimorbidity_gee_stratified.R` 文件头注释

#### `multimorbidity_kml3d_trajectory`
- 路径: `Blocks/48_multimorbidity_full/01block_multimorbidity_kml3d_trajectory.R`
- 用途: ##############################################################################
- 回读: `Blocks/48_multimorbidity_full/01block_multimorbidity_kml3d_trajectory.R` 文件头注释

#### `multimorbidity_sensitivity_suite`
- 路径: `Blocks/48_multimorbidity_full/04block_multimorbidity_sensitivity_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/48_multimorbidity_full/04block_multimorbidity_sensitivity_suite.R` 文件头注释


### `49_multimodal_full/`

#### `multimodal_dl_shap`
- 路径: `Blocks/49_multimodal_full/02block_multimodal_dl_shap.R`
- 用途: ##############################################################################
- 回读: `Blocks/49_multimodal_full/02block_multimodal_dl_shap.R` 文件头注释

#### `multimodal_omics_preprocess`
- 路径: `Blocks/49_multimodal_full/01block_multimodal_omics_preprocess.R`
- 用途: ##############################################################################
- 回读: `Blocks/49_multimodal_full/01block_multimodal_omics_preprocess.R` 文件头注释


### `50_complex_network/`

#### `complex_network_bootnet`
- 路径: `Blocks/50_complex_network/03block_complex_network_bootnet.R`
- 用途: ##############################################################################
- 回读: `Blocks/50_complex_network/03block_complex_network_bootnet.R` 文件头注释

#### `complex_network_covariate_residual`
- 路径: `Blocks/50_complex_network/04block_complex_network_covariate_residual.R`
- 用途: ##############################################################################
- 回读: `Blocks/50_complex_network/04block_complex_network_covariate_residual.R` 文件头注释

#### `complex_network_descriptive`
- 路径: `Blocks/50_complex_network/02block_complex_network_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/50_complex_network/02block_complex_network_descriptive.R` 文件头注释

#### `complex_network_ggm`
- 路径: `Blocks/50_complex_network/01block_complex_network_ggm.R`
- 用途: ##############################################################################
- 回读: `Blocks/50_complex_network/01block_complex_network_ggm.R` 文件头注释

#### `complex_network_publication_tables`
- 路径: `Blocks/50_complex_network/05block_complex_network_publication_tables.R`
- 用途: ##############################################################################
- 回读: `Blocks/50_complex_network/05block_complex_network_publication_tables.R` 文件头注释


### `51_bayesian_comorbidity/`

#### `bayesian_bodn`
- 路径: `Blocks/51_bayesian_comorbidity/01block_bayesian_bodn.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/01block_bayesian_bodn.R` 文件头注释

#### `bayesian_body_clock`
- 路径: `Blocks/51_bayesian_comorbidity/02block_bayesian_body_clock.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/02block_bayesian_body_clock.R` 文件头注释

#### `bayesian_bsc_aging`
- 路径: `Blocks/51_bayesian_comorbidity/03block_bayesian_bsc_aging.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/03block_bayesian_bsc_aging.R` 文件头注释

#### `bayesian_bsc_clocks`
- 路径: `Blocks/51_bayesian_comorbidity/05block_bayesian_bsc_clocks.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/05block_bayesian_bsc_clocks.R` 文件头注释

#### `bayesian_health_octo_suite`
- 路径: `Blocks/51_bayesian_comorbidity/06block_bayesian_health_octo_suite.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/06block_bayesian_health_octo_suite.R` 文件头注释

#### `bayesian_outcome_validate`
- 路径: `Blocks/51_bayesian_comorbidity/04block_bayesian_outcome_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/04block_bayesian_outcome_validate.R` 文件头注释

#### `bayesian_roc_calibration`
- 路径: `Blocks/51_bayesian_comorbidity/07block_bayesian_roc_calibration.R`
- 用途: ##############################################################################
- 回读: `Blocks/51_bayesian_comorbidity/07block_bayesian_roc_calibration.R` 文件头注释


### `52_trajectory_incidence/`

#### `trajectory_creatinine_pct`
- 路径: `Blocks/52_trajectory_incidence/00block_trajectory_creatinine_pct.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/00block_trajectory_creatinine_pct.R` 文件头注释

#### `trajectory_lcmm_external_validate`
- 路径: `Blocks/52_trajectory_incidence/06block_trajectory_lcmm_external_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/06block_trajectory_lcmm_external_validate.R` 文件头注释

#### `trajectory_lcmm_fit`
- 路径: `Blocks/52_trajectory_incidence/02block_trajectory_lcmm_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/02block_trajectory_lcmm_fit.R` 文件头注释

#### `trajectory_lcmm_mpcmp_plot`
- 路径: `Blocks/52_trajectory_incidence/05block_trajectory_lcmm_mpcmp_plot.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/05block_trajectory_lcmm_mpcmp_plot.R` 文件头注释

#### `trajectory_outcome_adjusted`
- 路径: `Blocks/52_trajectory_incidence/07block_trajectory_outcome_adjusted.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/07block_trajectory_outcome_adjusted.R` 文件头注释

#### `trajectory_outcome_models`
- 路径: `Blocks/52_trajectory_incidence/03block_trajectory_outcome_models.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/03block_trajectory_outcome_models.R` 文件头注释

#### `trajectory_prepare_wide_rdata`
- 路径: `Blocks/52_trajectory_incidence/04block_trajectory_prepare_wide_rdata.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/04block_trajectory_prepare_wide_rdata.R` 文件头注释

#### `trajectory_wide_to_long`
- 路径: `Blocks/52_trajectory_incidence/01block_trajectory_wide_to_long.R`
- 用途: ##############################################################################
- 回读: `Blocks/52_trajectory_incidence/01block_trajectory_wide_to_long.R` 文件头注释


### `53_trajectory_prognosis_full/`

#### `trajectory_baseline_by_class`
- 路径: `Blocks/53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R`
- 用途: ##############################################################################
- 前置: `require_upstream = trajectory_jlcm（assign_class_ng 需已回写 trajectory_class）`; `require_pkg = gtsummary, openxlsx, dplyr`
- config 节: `config$survival`
- 回读: `Blocks/53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R` 文件头注释

#### `trajectory_calc_28d_index`
- 路径: `Blocks/53_trajectory_prognosis_full/08block_trajectory_calc_28d_index.R`
- 用途: ##############################################################################
- config 节: `config$dual_db`, `config$trajectory_jlcm`
- 回读: `Blocks/53_trajectory_prognosis_full/08block_trajectory_calc_28d_index.R` 文件头注释

#### `trajectory_dynpred_individual`
- 路径: `Blocks/53_trajectory_prognosis_full/05block_trajectory_dynpred_individual.R`
- 用途: ##############################################################################
- 前置: `require_upstream = trajectory_jlcm（需要 ctx$results$trajectory_jlcm_models[[Index]]）`; `require_pkg = lcmm, survival, flexsurv, dplyr, tidyr, ggplot2, MASS`; `require_survivor_dyn_better = TRUE, # 存活代表：动态模型生存概率需优于静态 Weibull`
- config 节: `config$trajectory_jlcm`
- 回读: `Blocks/53_trajectory_prognosis_full/05block_trajectory_dynpred_individual.R` 文件头注释

#### `trajectory_jlcm_discovery_validate`
- 路径: `Blocks/53_trajectory_prognosis_full/03block_trajectory_jlcm_discovery_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/53_trajectory_prognosis_full/03block_trajectory_jlcm_discovery_validate.R` 文件头注释

#### `trajectory_km_class`
- 路径: `Blocks/53_trajectory_prognosis_full/04block_trajectory_km_class.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_pkg = survival, survminer, dplyr, ggplot2`
- config 节: `config$survival`
- 回读: `Blocks/53_trajectory_prognosis_full/04block_trajectory_km_class.R` 文件头注释

#### `trajectory_piecewise_cox`
- 路径: `Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- config 节: `config$survival`, `config$trajectory_pub`
- 回读: `Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R` 文件头注释

#### `trajectory_subgroup_class`
- 路径: `Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- config 节: `config$survival`
- 回读: `Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R` 文件头注释

#### `trajectory_weibull_compare`
- 路径: `Blocks/53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R`
- 用途: ##############################################################################
- 前置: `require_upstream = trajectory_jlcm（需要 ctx$results$trajectory_jlcm_models[[Index]]）`; `require_pkg = lcmm, survival, flexsurv, dplyr, tidyr, ggplot2, Hmisc`
- config 节: `config$trajectory_jlcm`
- 回读: `Blocks/53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R` 文件头注释


### `54_cross_lagged_full/`

#### `cross_lagged_biomarker_cor`
- 路径: `Blocks/54_cross_lagged_full/11block_cross_lagged_biomarker_cor.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/11block_cross_lagged_biomarker_cor.R` 文件头注释

#### `cross_lagged_change_logistic`
- 路径: `Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R` 文件头注释

#### `cross_lagged_corr_table`
- 路径: `Blocks/54_cross_lagged_full/15block_cross_lagged_corr_table.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/15block_cross_lagged_corr_table.R` 文件头注释

#### `cross_lagged_country_year_bar`
- 路径: `Blocks/54_cross_lagged_full/18block_cross_lagged_country_year_bar.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$longitudinal %||% ctx$data$imputed`
- 回读: `Blocks/54_cross_lagged_full/18block_cross_lagged_country_year_bar.R` 文件头注释

#### `cross_lagged_cox_frailty`
- 路径: `Blocks/54_cross_lagged_full/02block_cross_lagged_cox_frailty.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/02block_cross_lagged_cox_frailty.R` 文件头注释

#### `cross_lagged_fi_compute`
- 路径: `Blocks/54_cross_lagged_full/01block_cross_lagged_fi_compute.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/01block_cross_lagged_fi_compute.R` 文件头注释

#### `cross_lagged_fig1_group`
- 路径: `Blocks/54_cross_lagged_full/19block_cross_lagged_fig1_group.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$longitudinal`
- 回读: `Blocks/54_cross_lagged_full/19block_cross_lagged_fig1_group.R` 文件头注释

#### `cross_lagged_forest_or`
- 路径: `Blocks/54_cross_lagged_full/16block_cross_lagged_forest_or.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- 回读: `Blocks/54_cross_lagged_full/16block_cross_lagged_forest_or.R` 文件头注释

#### `cross_lagged_frailty_transition`
- 路径: `Blocks/54_cross_lagged_full/08block_cross_lagged_frailty_transition.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/08block_cross_lagged_frailty_transition.R` 文件头注释

#### `cross_lagged_km`
- 路径: `Blocks/54_cross_lagged_full/06block_cross_lagged_km.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/06block_cross_lagged_km.R` 文件头注释

#### `cross_lagged_long_prepare`
- 路径: `Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R`
- 用途: ##############################################################################
- config 节: `config$cross_lagged_long_prepare`
- 回读: `Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R` 文件头注释

#### `cross_lagged_mediation`
- 路径: `Blocks/54_cross_lagged_full/03block_cross_lagged_mediation.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/03block_cross_lagged_mediation.R` 文件头注释

#### `cross_lagged_mediation_bootstrap`
- 路径: `Blocks/54_cross_lagged_full/07block_cross_lagged_mediation_bootstrap.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/07block_cross_lagged_mediation_bootstrap.R` 文件头注释

#### `cross_lagged_meta_merge`
- 路径: `Blocks/54_cross_lagged_full/12block_cross_lagged_meta_merge.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/12block_cross_lagged_meta_merge.R` 文件头注释

#### `cross_lagged_network`
- 路径: `Blocks/54_cross_lagged_full/17block_cross_lagged_network.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$longitudinal_wide_clpn %||% longitudinal_wide`
- 回读: `Blocks/54_cross_lagged_full/17block_cross_lagged_network.R` 文件头注释

#### `cross_lagged_network_bootstrap`
- 路径: `Blocks/54_cross_lagged_full/22block_cross_lagged_network_bootstrap.R`
- 用途: ##############################################################################
- config 节: `config$cross_lagged_network_bootstrap`
- 回读: `Blocks/54_cross_lagged_full/22block_cross_lagged_network_bootstrap.R` 文件头注释

#### `cross_lagged_panel_network`
- 路径: `Blocks/54_cross_lagged_full/04block_cross_lagged_panel_network.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/04block_cross_lagged_panel_network.R` 文件头注释

#### `cross_lagged_pooled_bind`
- 路径: `Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R`
- 用途: ##############################################################################
- 前置: `require_ctx_results = ctx$results$cohort_imputed_list`; `require_ctx_results = Model2Factors（可选；缺则用 config 锁定名单）`
- config 节: `config$cross_lagged_pooled_bind`
- 回读: `Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R` 文件头注释

#### `cross_lagged_sensitivity`
- 路径: `Blocks/54_cross_lagged_full/10block_cross_lagged_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/10block_cross_lagged_sensitivity.R` 文件头注释

#### `cross_lagged_subgroup`
- 路径: `Blocks/54_cross_lagged_full/05block_cross_lagged_subgroup.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/05block_cross_lagged_subgroup.R` 文件头注释

#### `cross_lagged_subgroup_extended`
- 路径: `Blocks/54_cross_lagged_full/09block_cross_lagged_subgroup_extended.R`
- 用途: ##############################################################################
- 回读: `Blocks/54_cross_lagged_full/09block_cross_lagged_subgroup_extended.R` 文件头注释


### `55_competing_risk_full/`

#### `competing_baseline_quartile`
- 路径: `Blocks/55_competing_risk_full/14block_competing_baseline_quartile.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/14block_competing_baseline_quartile.R` 文件头注释

#### `competing_baseline_trajectory`
- 路径: `Blocks/55_competing_risk_full/15block_competing_baseline_trajectory.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/15block_competing_baseline_trajectory.R` 文件头注释

#### `competing_cif_plot`
- 路径: `Blocks/55_competing_risk_full/06block_competing_cif_plot.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/06block_competing_cif_plot.R` 文件头注释

#### `competing_cox_sensitivity`
- 路径: `Blocks/55_competing_risk_full/11block_competing_cox_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/11block_competing_cox_sensitivity.R` 文件头注释

#### `competing_finegray`
- 路径: `Blocks/55_competing_risk_full/03block_competing_finegray.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/03block_competing_finegray.R` 文件头注释

#### `competing_flowchart`
- 路径: `Blocks/55_competing_risk_full/17block_competing_flowchart.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/17block_competing_flowchart.R` 文件头注释

#### `competing_index_exposure`
- 路径: `Blocks/55_competing_risk_full/13block_competing_index_exposure.R`
- 用途: ##############################################################################
- config 节: `config$competing_risk`
- 回读: `Blocks/55_competing_risk_full/13block_competing_index_exposure.R` 文件头注释

#### `competing_lmm_trajectory`
- 路径: `Blocks/55_competing_risk_full/02block_competing_lmm_trajectory.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/02block_competing_lmm_trajectory.R` 文件头注释

#### `competing_mixed_cox`
- 路径: `Blocks/55_competing_risk_full/07block_competing_mixed_cox.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/07block_competing_mixed_cox.R` 文件头注释

#### `competing_models_123`
- 路径: `Blocks/55_competing_risk_full/09block_competing_models_123.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/09block_competing_models_123.R` 文件头注释

#### `competing_models_123_death`
- 路径: `Blocks/55_competing_risk_full/16block_competing_models_123_death.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/16block_competing_models_123_death.R` 文件头注释

#### `competing_ph_calibration`
- 路径: `Blocks/55_competing_risk_full/12block_competing_ph_calibration.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/12block_competing_ph_calibration.R` 文件头注释

#### `competing_pub_export`
- 路径: `Blocks/55_competing_risk_full/18block_competing_pub_export.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/18block_competing_pub_export.R` 文件头注释

#### `competing_rcs`
- 路径: `Blocks/55_competing_risk_full/05block_competing_rcs.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/05block_competing_rcs.R` 文件头注释

#### `competing_stratified`
- 路径: `Blocks/55_competing_risk_full/10block_competing_stratified.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/10block_competing_stratified.R` 文件头注释

#### `competing_supp_tables`
- 路径: `Blocks/55_competing_risk_full/19block_competing_supp_tables.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/19block_competing_supp_tables.R` 文件头注释

#### `competing_trajectory_cluster`
- 路径: `Blocks/55_competing_risk_full/20block_competing_trajectory_cluster.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/20block_competing_trajectory_cluster.R` 文件头注释

#### `competing_tyg_compute`
- 路径: `Blocks/55_competing_risk_full/01block_competing_tyg_compute.R`
- 用途: ##############################################################################
- 回读: `Blocks/55_competing_risk_full/01block_competing_tyg_compute.R` 文件头注释


### `56_ai_clinical_full/`

#### `ai_cases_prepare`
- 路径: `Blocks/56_ai_clinical_full/01block_ai_cases_prepare.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/01block_ai_cases_prepare.R` 文件头注释

#### `ai_guideline_audit`
- 路径: `Blocks/56_ai_clinical_full/03block_ai_guideline_audit.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/03block_ai_guideline_audit.R` 文件头注释

#### `ai_lab_interpret`
- 路径: `Blocks/56_ai_clinical_full/08block_ai_lab_interpret.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/08block_ai_lab_interpret.R` 文件头注释

#### `ai_llm_evaluate`
- 路径: `Blocks/56_ai_clinical_full/02block_ai_llm_evaluate.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/02block_ai_llm_evaluate.R` 文件头注释

#### `ai_llm_multimodel`
- 路径: `Blocks/56_ai_clinical_full/06block_ai_llm_multimodel.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/06block_ai_llm_multimodel.R` 文件头注释

#### `ai_multiround_sim`
- 路径: `Blocks/56_ai_clinical_full/05block_ai_multiround_sim.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/05block_ai_multiround_sim.R` 文件头注释

#### `ai_order_robustness`
- 路径: `Blocks/56_ai_clinical_full/09block_ai_order_robustness.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/09block_ai_order_robustness.R` 文件头注释

#### `ai_reader_comparison`
- 路径: `Blocks/56_ai_clinical_full/04block_ai_reader_comparison.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/04block_ai_reader_comparison.R` 文件头注释

#### `ai_reader_study`
- 路径: `Blocks/56_ai_clinical_full/07block_ai_reader_study.R`
- 用途: ##############################################################################
- 回读: `Blocks/56_ai_clinical_full/07block_ai_reader_study.R` 文件头注释


### `57_dual_incidence_mr_full/`

#### `crm_cox_mortality`
- 路径: `Blocks/57_dual_incidence_mr_full/02block_crm_cox_mortality.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/02block_crm_cox_mortality.R` 文件头注释

#### `crm_gout_strata`
- 路径: `Blocks/57_dual_incidence_mr_full/10block_crm_gout_strata.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/10block_crm_gout_strata.R` 文件头注释

#### `crm_nhanes_weighted`
- 路径: `Blocks/57_dual_incidence_mr_full/09block_crm_nhanes_weighted.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/09block_crm_nhanes_weighted.R` 文件头注释

#### `crm_ordinal_logistic`
- 路径: `Blocks/57_dual_incidence_mr_full/01block_crm_ordinal_logistic.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/01block_crm_ordinal_logistic.R` 文件头注释

#### `crm_rcs_sua`
- 路径: `Blocks/57_dual_incidence_mr_full/03block_crm_rcs_sua.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/03block_crm_rcs_sua.R` 文件头注释

#### `mr_egger_presso`
- 路径: `Blocks/57_dual_incidence_mr_full/07block_mr_egger_presso.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/07block_mr_egger_presso.R` 文件头注释

#### `mr_pleiotropy`
- 路径: `Blocks/57_dual_incidence_mr_full/08block_mr_pleiotropy.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/08block_mr_pleiotropy.R` 文件头注释

#### `mr_sensitivity`
- 路径: `Blocks/57_dual_incidence_mr_full/05block_mr_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/05block_mr_sensitivity.R` 文件头注释

#### `mr_snp_screen`
- 路径: `Blocks/57_dual_incidence_mr_full/06block_mr_snp_screen.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/06block_mr_snp_screen.R` 文件头注释

#### `mr_twosample`
- 路径: `Blocks/57_dual_incidence_mr_full/04block_mr_twosample.R`
- 用途: ##############################################################################
- 回读: `Blocks/57_dual_incidence_mr_full/04block_mr_twosample.R` 文件头注释


### `58_medication_regimen_full/`

#### `medication_chemo_strata`
- 路径: `Blocks/58_medication_regimen_full/04block_medication_chemo_strata.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/04block_medication_chemo_strata.R` 文件头注释

#### `medication_composite_risk`
- 路径: `Blocks/58_medication_regimen_full/01block_medication_composite_risk.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/01block_medication_composite_risk.R` 文件头注释

#### `medication_descriptive`
- 路径: `Blocks/58_medication_regimen_full/02block_medication_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/02block_medication_descriptive.R` 文件头注释

#### `medication_km_treatment`
- 路径: `Blocks/58_medication_regimen_full/03block_medication_km_treatment.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/03block_medication_km_treatment.R` 文件头注释

#### `medication_literature_targets`
- 路径: `Blocks/58_medication_regimen_full/07block_medication_literature_targets.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/07block_medication_literature_targets.R` 文件头注释

#### `medication_stepp_strata`
- 路径: `Blocks/58_medication_regimen_full/06block_medication_stepp_strata.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/06block_medication_stepp_strata.R` 文件头注释

#### `medication_trial_comparisons`
- 路径: `Blocks/58_medication_regimen_full/05block_medication_trial_comparisons.R`
- 用途: ##############################################################################
- 回读: `Blocks/58_medication_regimen_full/05block_medication_trial_comparisons.R` 文件头注释


### `59_markov_cognitive_full/`

#### `markov_apoe_le_difference`
- 路径: `Blocks/59_markov_cognitive_full/07block_markov_apoe_le_difference.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/07block_markov_apoe_le_difference.R` 文件头注释

#### `markov_apoe_lifestyle`
- 路径: `Blocks/59_markov_cognitive_full/04block_markov_apoe_lifestyle.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/04block_markov_apoe_lifestyle.R` 文件头注释

#### `markov_life_expectancy`
- 路径: `Blocks/59_markov_cognitive_full/03block_markov_life_expectancy.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/03block_markov_life_expectancy.R` 文件头注释

#### `markov_life_table_figure`
- 路径: `Blocks/59_markov_cognitive_full/06block_markov_life_table_figure.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/06block_markov_life_table_figure.R` 文件头注释

#### `markov_msm_bootstrap`
- 路径: `Blocks/59_markov_cognitive_full/05block_markov_msm_bootstrap.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/05block_markov_msm_bootstrap.R` 文件头注释

#### `markov_msm_fit`
- 路径: `Blocks/59_markov_cognitive_full/02block_markov_msm_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/02block_markov_msm_fit.R` 文件头注释

#### `markov_sensitivity_glmm`
- 路径: `Blocks/59_markov_cognitive_full/08block_markov_sensitivity_glmm.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/08block_markov_sensitivity_glmm.R` 文件头注释

#### `markov_state_prep`
- 路径: `Blocks/59_markov_cognitive_full/01block_markov_state_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/59_markov_cognitive_full/01block_markov_state_prep.R` 文件头注释


### `60_cdc_wonder_cits_full/`

#### `cdc_wonder_fetch`
- 路径: `Blocks/60_cdc_wonder_cits_full/05block_cdc_wonder_fetch.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/05block_cdc_wonder_fetch.R` 文件头注释

#### `cits_aggregate_monthly`
- 路径: `Blocks/60_cdc_wonder_cits_full/01block_cits_aggregate_monthly.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/01block_cits_aggregate_monthly.R` 文件头注释

#### `cits_model_fit`
- 路径: `Blocks/60_cdc_wonder_cits_full/02block_cits_model_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/02block_cits_model_fit.R` 文件头注释

#### `cits_model_full`
- 路径: `Blocks/60_cdc_wonder_cits_full/06block_cits_model_full.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/06block_cits_model_full.R` 文件头注释

#### `cits_plot`
- 路径: `Blocks/60_cdc_wonder_cits_full/04block_cits_plot.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/04block_cits_plot.R` 文件头注释

#### `cits_publication_tables`
- 路径: `Blocks/60_cdc_wonder_cits_full/08block_cits_publication_tables.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/08block_cits_publication_tables.R` 文件头注释

#### `cits_sensitivity`
- 路径: `Blocks/60_cdc_wonder_cits_full/03block_cits_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/03block_cits_sensitivity.R` 文件头注释

#### `cits_sensitivity_extended`
- 路径: `Blocks/60_cdc_wonder_cits_full/07block_cits_sensitivity_extended.R`
- 用途: ##############################################################################
- 回读: `Blocks/60_cdc_wonder_cits_full/07block_cits_sensitivity_extended.R` 文件头注释


### `61_network_temperature_full/`

#### `network_temp_centrality`
- 路径: `Blocks/61_network_temperature_full/07block_network_temp_centrality.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/07block_network_temp_centrality.R` 文件头注释

#### `network_temp_cohort_summary`
- 路径: `Blocks/61_network_temperature_full/08block_network_temp_cohort_summary.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/08block_network_temp_cohort_summary.R` 文件头注释

#### `network_temp_compute`
- 路径: `Blocks/61_network_temperature_full/02block_network_temp_compute.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/02block_network_temp_compute.R` 文件头注释

#### `network_temp_ggm_fit`
- 路径: `Blocks/61_network_temperature_full/05block_network_temp_ggm_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/05block_network_temp_ggm_fit.R` 文件头注释

#### `network_temp_literature_validate`
- 路径: `Blocks/61_network_temperature_full/09block_network_temp_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/09block_network_temp_literature_validate.R` 文件头注释

#### `network_temp_mixed_model`
- 路径: `Blocks/61_network_temperature_full/06block_network_temp_mixed_model.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/06block_network_temp_mixed_model.R` 文件头注释

#### `network_temp_outcome_assoc`
- 路径: `Blocks/61_network_temperature_full/04block_network_temp_outcome_assoc.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/04block_network_temp_outcome_assoc.R` 文件头注释

#### `network_temp_prepare_long`
- 路径: `Blocks/61_network_temperature_full/01block_network_temp_prepare_long.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/01block_network_temp_prepare_long.R` 文件头注释

#### `network_temp_trajectory`
- 路径: `Blocks/61_network_temperature_full/03block_network_temp_trajectory.R`
- 用途: ##############################################################################
- 回读: `Blocks/61_network_temperature_full/03block_network_temp_trajectory.R` 文件头注释


### `62_sem_chain_mediation_full/`

#### `sem_chain_mediation`
- 路径: `Blocks/62_sem_chain_mediation_full/05block_sem_chain_mediation.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/05block_sem_chain_mediation.R` 文件头注释

#### `sem_cox_baseline`
- 路径: `Blocks/62_sem_chain_mediation_full/03block_sem_cox_baseline.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/03block_sem_cox_baseline.R` 文件头注释

#### `sem_cox_chain_mediation`
- 路径: `Blocks/62_sem_chain_mediation_full/08block_sem_cox_chain_mediation.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/08block_sem_cox_chain_mediation.R` 文件头注释

#### `sem_data_prep`
- 路径: `Blocks/62_sem_chain_mediation_full/01block_sem_data_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/01block_sem_data_prep.R` 文件头注释

#### `sem_descriptive`
- 路径: `Blocks/62_sem_chain_mediation_full/02block_sem_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/02block_sem_descriptive.R` 文件头注释

#### `sem_literature_validate`
- 路径: `Blocks/62_sem_chain_mediation_full/09block_sem_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/09block_sem_literature_validate.R` 文件头注释

#### `sem_path_lavaan`
- 路径: `Blocks/62_sem_chain_mediation_full/04block_sem_path_lavaan.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/04block_sem_path_lavaan.R` 文件头注释

#### `sem_sensitivity`
- 路径: `Blocks/62_sem_chain_mediation_full/07block_sem_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/07block_sem_sensitivity.R` 文件头注释

#### `sem_stratified`
- 路径: `Blocks/62_sem_chain_mediation_full/06block_sem_stratified.R`
- 用途: ##############################################################################
- 回读: `Blocks/62_sem_chain_mediation_full/06block_sem_stratified.R` 文件头注释


### `63_ai_medical_qa_full/`

#### `ai_qa_cot_eval`
- 路径: `Blocks/63_ai_medical_qa_full/02block_ai_qa_cot_eval.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/02block_ai_qa_cot_eval.R` 文件头注释

#### `ai_qa_dataset_summary`
- 路径: `Blocks/63_ai_medical_qa_full/05block_ai_qa_dataset_summary.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/05block_ai_qa_dataset_summary.R` 文件头注释

#### `ai_qa_model_ranking`
- 路径: `Blocks/63_ai_medical_qa_full/06block_ai_qa_model_ranking.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/06block_ai_qa_model_ranking.R` 文件头注释

#### `ai_qa_prepare`
- 路径: `Blocks/63_ai_medical_qa_full/01block_ai_qa_prepare.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/01block_ai_qa_prepare.R` 文件头注释

#### `ai_qa_prompt_compare`
- 路径: `Blocks/63_ai_medical_qa_full/03block_ai_qa_prompt_compare.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/03block_ai_qa_prompt_compare.R` 文件头注释

#### `ai_qa_prompt_templates`
- 路径: `Blocks/63_ai_medical_qa_full/07block_ai_qa_prompt_templates.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/07block_ai_qa_prompt_templates.R` 文件头注释

#### `ai_qa_statistics`
- 路径: `Blocks/63_ai_medical_qa_full/04block_ai_qa_statistics.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/04block_ai_qa_statistics.R` 文件头注释

#### `ai_qa_table4_validate`
- 路径: `Blocks/63_ai_medical_qa_full/08block_ai_qa_table4_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/63_ai_medical_qa_full/08block_ai_qa_table4_validate.R` 文件头注释


### `64_causal_forest_trajectory_full/`

#### `cftraj_causal_forest`
- 路径: `Blocks/64_causal_forest_trajectory_full/05block_cftraj_causal_forest.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/05block_cftraj_causal_forest.R` 文件头注释

#### `cftraj_circs_compute`
- 路径: `Blocks/64_causal_forest_trajectory_full/01block_cftraj_circs_compute.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/01block_cftraj_circs_compute.R` 文件头注释

#### `cftraj_lcmm_episodic`
- 路径: `Blocks/64_causal_forest_trajectory_full/08block_cftraj_lcmm_episodic.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/08block_cftraj_lcmm_episodic.R` 文件头注释

#### `cftraj_lcmm_fit`
- 路径: `Blocks/64_causal_forest_trajectory_full/03block_cftraj_lcmm_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/03block_cftraj_lcmm_fit.R` 文件头注释

#### `cftraj_multinomial`
- 路径: `Blocks/64_causal_forest_trajectory_full/04block_cftraj_multinomial.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/04block_cftraj_multinomial.R` 文件头注释

#### `cftraj_sensitivity`
- 路径: `Blocks/64_causal_forest_trajectory_full/07block_cftraj_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/07block_cftraj_sensitivity.R` 文件头注释

#### `cftraj_subgroup_viz`
- 路径: `Blocks/64_causal_forest_trajectory_full/06block_cftraj_subgroup_viz.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/06block_cftraj_subgroup_viz.R` 文件头注释

#### `cftraj_trajectory_validate`
- 路径: `Blocks/64_causal_forest_trajectory_full/09block_cftraj_trajectory_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/09block_cftraj_trajectory_validate.R` 文件头注释

#### `cftraj_wide_to_long`
- 路径: `Blocks/64_causal_forest_trajectory_full/02block_cftraj_wide_to_long.R`
- 用途: ##############################################################################
- 回读: `Blocks/64_causal_forest_trajectory_full/02block_cftraj_wide_to_long.R` 文件头注释


### `65_incidence_prepost_full/`

#### `prepost_data_prep`
- 路径: `Blocks/65_incidence_prepost_full/01block_prepost_data_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/01block_prepost_data_prep.R` 文件头注释

#### `prepost_descriptive`
- 路径: `Blocks/65_incidence_prepost_full/02block_prepost_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/02block_prepost_descriptive.R` 文件头注释

#### `prepost_domain_slopes`
- 路径: `Blocks/65_incidence_prepost_full/04block_prepost_domain_slopes.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/04block_prepost_domain_slopes.R` 文件头注释

#### `prepost_literature_validate`
- 路径: `Blocks/65_incidence_prepost_full/08block_prepost_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/08block_prepost_literature_validate.R` 文件头注释

#### `prepost_lmm_fit`
- 路径: `Blocks/65_incidence_prepost_full/03block_prepost_lmm_fit.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/03block_prepost_lmm_fit.R` 文件头注释

#### `prepost_sensitivity`
- 路径: `Blocks/65_incidence_prepost_full/06block_prepost_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/06block_prepost_sensitivity.R` 文件头注释

#### `prepost_subgroup_age`
- 路径: `Blocks/65_incidence_prepost_full/05block_prepost_subgroup_age.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/05block_prepost_subgroup_age.R` 文件头注释

#### `prepost_visualize`
- 路径: `Blocks/65_incidence_prepost_full/07block_prepost_visualize.R`
- 用途: ##############################################################################
- 回读: `Blocks/65_incidence_prepost_full/07block_prepost_visualize.R` 文件头注释


### `66_target_trial_full/`

#### `tte_bootstrap_ci`
- 路径: `Blocks/66_target_trial_full/09block_tte_bootstrap_ci.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/09block_tte_bootstrap_ci.R` 文件头注释

#### `tte_data_prep`
- 路径: `Blocks/66_target_trial_full/01block_tte_data_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/01block_tte_data_prep.R` 文件头注释

#### `tte_descriptive`
- 路径: `Blocks/66_target_trial_full/02block_tte_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/02block_tte_descriptive.R` 文件头注释

#### `tte_literature_validate`
- 路径: `Blocks/66_target_trial_full/08block_tte_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/08block_tte_literature_validate.R` 文件头注释

#### `tte_pooled_logistic`
- 路径: `Blocks/66_target_trial_full/04block_tte_pooled_logistic.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/04block_tte_pooled_logistic.R` 文件头注释

#### `tte_risk_difference`
- 路径: `Blocks/66_target_trial_full/05block_tte_risk_difference.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/05block_tte_risk_difference.R` 文件头注释

#### `tte_sensitivity`
- 路径: `Blocks/66_target_trial_full/07block_tte_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/07block_tte_sensitivity.R` 文件头注释

#### `tte_stratified`
- 路径: `Blocks/66_target_trial_full/06block_tte_stratified.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/06block_tte_stratified.R` 文件头注释

#### `tte_weighting`
- 路径: `Blocks/66_target_trial_full/03block_tte_weighting.R`
- 用途: ##############################################################################
- 回读: `Blocks/66_target_trial_full/03block_tte_weighting.R` 文件头注释


### `67_transformer_shortseq_full/`

#### `trf_calibration`
- 路径: `Blocks/67_transformer_shortseq_full/04block_trf_calibration.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/04block_trf_calibration.R` 文件头注释

#### `trf_causal_discovery`
- 路径: `Blocks/67_transformer_shortseq_full/09block_trf_causal_discovery.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/09block_trf_causal_discovery.R` 文件头注释

#### `trf_data_prep`
- 路径: `Blocks/67_transformer_shortseq_full/01block_trf_data_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/01block_trf_data_prep.R` 文件头注释

#### `trf_early_detection`
- 路径: `Blocks/67_transformer_shortseq_full/05block_trf_early_detection.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/05block_trf_early_detection.R` 文件头注释

#### `trf_external_val`
- 路径: `Blocks/67_transformer_shortseq_full/06block_trf_external_val.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/06block_trf_external_val.R` 文件头注释

#### `trf_feature_reduce`
- 路径: `Blocks/67_transformer_shortseq_full/02block_trf_feature_reduce.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/02block_trf_feature_reduce.R` 文件头注释

#### `trf_literature_validate`
- 路径: `Blocks/67_transformer_shortseq_full/08block_trf_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/08block_trf_literature_validate.R` 文件头注释

#### `trf_multicenter_val`
- 路径: `Blocks/67_transformer_shortseq_full/10block_trf_multicenter_val.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/10block_trf_multicenter_val.R` 文件头注释

#### `trf_sensitivity`
- 路径: `Blocks/67_transformer_shortseq_full/07block_trf_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/07block_trf_sensitivity.R` 文件头注释

#### `trf_train_eval`
- 路径: `Blocks/67_transformer_shortseq_full/03block_trf_train_eval.R`
- 用途: ##############################################################################
- 回读: `Blocks/67_transformer_shortseq_full/03block_trf_train_eval.R` 文件头注释


### `68_dual_change_score_full/`

#### `dcs_bivariate_dcsm`
- 路径: `Blocks/68_dual_change_score_full/03block_dcs_bivariate_dcsm.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/03block_dcs_bivariate_dcsm.R` 文件头注释

#### `dcs_data_prep`
- 路径: `Blocks/68_dual_change_score_full/01block_dcs_data_prep.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/01block_dcs_data_prep.R` 文件头注释

#### `dcs_depression_to_memory`
- 路径: `Blocks/68_dual_change_score_full/04block_dcs_depression_to_memory.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/04block_dcs_depression_to_memory.R` 文件头注释

#### `dcs_descriptive`
- 路径: `Blocks/68_dual_change_score_full/02block_dcs_descriptive.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/02block_dcs_descriptive.R` 文件头注释

#### `dcs_literature_validate`
- 路径: `Blocks/68_dual_change_score_full/08block_dcs_literature_validate.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/08block_dcs_literature_validate.R` 文件头注释

#### `dcs_memory_to_depression`
- 路径: `Blocks/68_dual_change_score_full/05block_dcs_memory_to_depression.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/05block_dcs_memory_to_depression.R` 文件头注释

#### `dcs_sensitivity`
- 路径: `Blocks/68_dual_change_score_full/07block_dcs_sensitivity.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/07block_dcs_sensitivity.R` 文件头注释

#### `dcs_verbal_fluency`
- 路径: `Blocks/68_dual_change_score_full/06block_dcs_verbal_fluency.R`
- 用途: ##############################################################################
- 回读: `Blocks/68_dual_change_score_full/06block_dcs_verbal_fluency.R` 文件头注释


### `69_ipw_diabetes_stroke_full/`

#### `ipw_diabetes_exposure`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R` 文件头注释

#### `ipw_diabetes_flowchart`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/02block_ipw_flowchart.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → iptw_association → ipw_diabetes_flowchart
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_results = ctx$results$ipw_diabetes_exposure（可选，来自 01block_ipw_diabetes_exposure）`
- 写出: ctx$results$ipw_diabetes_flowchart
- config 节: `config$ipw_diabetes_flowchart`, `config$survival`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/02block_ipw_flowchart.R` 文件头注释

#### `ipw_jin_composite_risk`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/09block_ipw_jin_composite_risk.R`
- 用途: ##############################################################################
- 回读: `Blocks/69_ipw_diabetes_stroke_full/09block_ipw_jin_composite_risk.R` 文件头注释

#### `ipw_literature_targets`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/06block_ipw_literature_targets.R`
- 用途: ##############################################################################
- 典型位置: ... → cox_binary → ipw_overlap_weights → ipw_literature_targets → ipw_pub_export
- 前置: `require_results = ctx$results（尽力探测；缺失项不阻断，仅计入 failed 清单）`
- 写出: ctx$results$ipw_literature_targets（含 all_found 布尔标记、逐项明细）
- config 节: `config$ipw_literature_targets`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/06block_ipw_literature_targets.R` 文件头注释

#### `ipw_overlap_weights`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/04block_ipw_overlap_weights.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → ... → cox_binary → ipw_overlap_weights
- 前置: `require_data = ctx$data$iptw_weighted %||% ctx$data$imputed %||% ctx$data$cleaned`; `require_results = ctx$results$iptw_ps_covariates（可选；来自 34_IPTW/01block_iptw_balance）`
- 写出: ctx$results$ipw_overlap_weights（PS、重叠权重、Cox HR/CI/P）
- config 节: `config$ipw_overlap_weights`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/04block_ipw_overlap_weights.R` 文件头注释

#### `ipw_pub_export`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/07block_ipw_pub_export.R`
- 用途: ##############################################################################
- 典型位置: ... → ipw_literature_targets → ipw_pub_export（pipeline 末尾）
- 前置: `require_config = config$project$mirror_pub_outputs_to_root（TRUE 才执行镜像）`
- 写出: 无新增分析结果；仅镜像文件 + 写出根目录清单
- config 节: `config$ipw_pub_export`, `config$project`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/07block_ipw_pub_export.R` 文件头注释

#### `ipw_subgroup_km_pub`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/05block_ipw_subgroup_km_pub.R`
- 用途: ##############################################################################
- 前置: `require_data = ctx$data$iptw_weighted（须先 iptw_balance）`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/05block_ipw_subgroup_km_pub.R` 文件头注释

#### `ipw_surv_calibration_roc`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/08block_ipw_surv_calibration_roc.R`
- 用途: ##############################################################################
- 回读: `Blocks/69_ipw_diabetes_stroke_full/08block_ipw_surv_calibration_roc.R` 文件头注释

#### `ipw_weighted_km_pub`
- 路径: `Blocks/69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R`
- 用途: ##############################################################################
- 典型位置: iptw_balance → iptw_association → ipw_diabetes_flowchart → ipw_weighted_km_pub
- 前置: `require_data = ctx$data$iptw_weighted（须先运行 34_IPTW/01block_iptw_balance）`; `require_results = ctx$results$iptw_weight_col（可选；缺省回退 "weight"）`
- 写出: ctx$results$ipw_weighted_km_pub（加权/未加权 Cox HR、95% CI、P，pub_format_p 格式化）
- config 节: `config$ipw_weighted_km_pub`, `config$survival`
- 回读: `Blocks/69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R` 文件头注释


### `70_crm_nhanes_pub/`

#### `crm_mr_figures`
- 路径: `Blocks/70_crm_nhanes_pub/09block_crm_mr_figures.R`
- 用途: ##############################################################################
- 典型位置: mr worker 末尾（mr_snp_screen → mr_twosample → mr_egger_presso →
- 写出: ctx$results$crm_mr_figures（各结局 n_snps_harmonised、IVW/LOO 估计、图路径、 skipped_outcomes 及原因、mendelian helper 是否命中）
- config 节: `config$dual_incidence_mr`, `config$project`
- 回读: `Blocks/70_crm_nhanes_pub/09block_crm_mr_figures.R` 文件头注释

#### `crm_mr_literature`
- 路径: `Blocks/70_crm_nhanes_pub/11block_crm_mr_literature.R`
- 用途: ##############################################################################
- 前置: `require_packages = TwoSampleMR, MendelianRandomization, MRPRESSO, data.table,`; `require_files = dual_incidence_mr$gwas_exposure_path（尿酸 GWAS .tsv.gz）`; `require_plink = dual_incidence_mr$plink_bin + ld_bfile（1000G EUR）`
- 回读: `Blocks/70_crm_nhanes_pub/11block_crm_mr_literature.R` 文件头注释

#### `crm_multivariate_prognosis`
- 路径: `Blocks/70_crm_nhanes_pub/13block_crm_multivariate_prognosis.R`
- 用途: ##############################################################################
- 回读: `Blocks/70_crm_nhanes_pub/13block_crm_multivariate_prognosis.R` 文件头注释

#### `crm_nhanes_baseline_weighted`
- 路径: `Blocks/70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R`
- 用途: ##############################################################################
- 典型位置: crm_nhanes_derive → crm_nhanes_flowchart → crm_nhanes_baseline_weighted → ...
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`
- 写出: ctx$results$crm_nhanes_baseline_weighted
- config 节: `config$crm_nhanes_baseline_weighted`, `config$nhanes`
- 回读: `Blocks/70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R` 文件头注释

#### `crm_nhanes_cox_pub`
- 路径: `Blocks/70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R`
- 用途: ##############################################################################
- 回读: `Blocks/70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R` 文件头注释

#### `crm_nhanes_derive`
- 路径: `Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R`
- 用途: ##############################################################################
- config 节: `config$crm_nhanes_pub`
- 回读: `Blocks/70_crm_nhanes_pub/01block_crm_nhanes_derive.R` 文件头注释

#### `crm_nhanes_flowchart`
- 路径: `Blocks/70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R`
- 用途: ##############################################################################
- 典型位置: crm_nhanes_derive → crm_nhanes_flowchart → crm_nhanes_baseline_weighted → ...
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`; `require_results = ctx$results$crm_nhanes_derive（可选，用于起始队列 n / min_age 快照）`
- 写出: ctx$results$crm_nhanes_flowchart
- config 节: `config$crm_nhanes_flowchart`
- 回读: `Blocks/70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R` 文件头注释

#### `crm_nhanes_km_pub`
- 路径: `Blocks/70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R`
- 用途: ##############################################################################
- 典型位置: crm_nhanes_derive → ... → crm_nhanes_km_pub
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`
- 写出: ctx$results$crm_nhanes_km_pub
- config 节: `config$crm_nhanes_km_pub`
- 回读: `Blocks/70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R` 文件头注释

#### `crm_nhanes_ordinal_pub`
- 路径: `Blocks/70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R`
- 用途: ##############################################################################
- 典型位置: crm_nhanes_derive → ... → crm_nhanes_ordinal_pub（Table 2）→ crm_nhanes_cox_pub → ...
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`
- 写出: ctx$results$crm_nhanes_ordinal_pub（每个暴露×模型的 tidy 系数、gout_available、 analytic_n、可选 thin57_comparison）
- config 节: `config$crm_nhanes_ordinal_pub`, `config$nhanes`
- 回读: `Blocks/70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R` 文件头注释

#### `crm_nhanes_pub_align`
- 路径: `Blocks/70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R`
- 用途: ##############################################################################
- 典型位置: pipeline 末尾（... → crm_nhanes_rcs_pub → crm_nhanes_pub_align）
- 写出: 无新增分析结果；仅镜像已存在但未同步到根目录的文件 + 写出核对清单
- config 节: `config$crm_nhanes_pub_align`, `config$project`
- 回读: `Blocks/70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R` 文件头注释

#### `crm_nhanes_pub_deliverables`
- 路径: `Blocks/70_crm_nhanes_pub/12block_crm_nhanes_pub_deliverables.R`
- 用途: ##############################################################################
- config 节: `config$crm_nhanes_pub_deliverables`, `config$study_batch`
- 回读: `Blocks/70_crm_nhanes_pub/12block_crm_nhanes_pub_deliverables.R` 文件头注释

#### `crm_nhanes_rcs_pub`
- 路径: `Blocks/70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R`
- 用途: ##############################################################################
- 典型位置: ... → crm_nhanes_cox_pub → crm_nhanes_rcs_pub（Figure 3）→ crm_nhanes_pub_align
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`
- 写出: ctx$results$crm_nhanes_rcs_pub（各分层曲线数据、P_overall/P_nonlinear、 skipped_strata、可选 thin57_comparison）
- config 节: `config$crm_nhanes_rcs_pub`, `config$nhanes`
- 回读: `Blocks/70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R` 文件头注释

#### `crm_nhanes_subgroup_supp`
- 路径: `Blocks/70_crm_nhanes_pub/10block_crm_nhanes_subgroup_supp.R`
- 用途: ##############################################################################
- 典型位置: obs_strata worker：crm_gout_strata → crm_nhanes_subgroup_supp
- 前置: `require_data = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）`
- 写出: ctx$results$crm_nhanes_subgroup_supp（tidy 长表、各亚组 analytic_n、跳过记录）
- config 节: `config$crm_nhanes_subgroup_supp`, `config$nhanes`
- 回读: `Blocks/70_crm_nhanes_pub/10block_crm_nhanes_subgroup_supp.R` 文件头注释


### `71_two_stage_transformer_stroke/`

#### `tst_calibration_dca`
- 路径: `Blocks/71_two_stage_transformer_stroke/07block_tst_calibration_dca.R`
- 用途: ##############################################################################
- 回读: `Blocks/71_two_stage_transformer_stroke/07block_tst_calibration_dca.R` 文件头注释

#### `tst_cohort`
- 路径: `Blocks/71_two_stage_transformer_stroke/01block_tst_cohort.R`
- 用途: ##############################################################################
- config 节: `config$data`, `config$tst_cohort`
- 回读: `Blocks/71_two_stage_transformer_stroke/01block_tst_cohort.R` 文件头注释

#### `tst_external`
- 路径: `Blocks/71_two_stage_transformer_stroke/09block_tst_external.R`
- 用途: ##############################################################################
- config 节: `config$tst_stroke`
- 回读: `Blocks/71_two_stage_transformer_stroke/09block_tst_external.R` 文件头注释

#### `tst_landmark`
- 路径: `Blocks/71_two_stage_transformer_stroke/03block_tst_landmark.R`
- 用途: ##############################################################################
- config 节: `config$tst_landmark`, `config$tst_stroke`
- 回读: `Blocks/71_two_stage_transformer_stroke/03block_tst_landmark.R` 文件头注释

#### `tst_literature_validate`
- 路径: `Blocks/71_two_stage_transformer_stroke/10block_tst_literature_validate.R`
- 用途: ##############################################################################
- config 节: `config$literature_targets`
- 回读: `Blocks/71_two_stage_transformer_stroke/10block_tst_literature_validate.R` 文件头注释

#### `tst_pub_export`
- 路径: `Blocks/71_two_stage_transformer_stroke/11block_tst_pub_export.R`
- 用途: ##############################################################################
- config 节: `config$project`, `config$tst_pub_export`
- 回读: `Blocks/71_two_stage_transformer_stroke/11block_tst_pub_export.R` 文件头注释

#### `tst_repo_a1`
- 路径: `Blocks/71_two_stage_transformer_stroke/05block_tst_repo_a1.R`
- 用途: ##############################################################################
- config 节: `config$tst_stroke`
- 回读: `Blocks/71_two_stage_transformer_stroke/05block_tst_repo_a1.R` 文件头注释

#### `tst_shap`
- 路径: `Blocks/71_two_stage_transformer_stroke/08block_tst_shap.R`
- 用途: ##############################################################################
- 回读: `Blocks/71_two_stage_transformer_stroke/08block_tst_shap.R` 文件头注释

#### `tst_split`
- 路径: `Blocks/71_two_stage_transformer_stroke/04block_tst_split.R`
- 用途: ##############################################################################
- config 节: `config$tst_stroke`
- 回读: `Blocks/71_two_stage_transformer_stroke/04block_tst_split.R` 文件头注释

#### `tst_summary_results`
- 路径: `Blocks/71_two_stage_transformer_stroke/12block_tst_summary_results.R`
- 用途: ##############################################################################
- config 节: `config$tst_stroke`
- 回读: `Blocks/71_two_stage_transformer_stroke/12block_tst_summary_results.R` 文件头注释

#### `tst_timeseries`
- 路径: `Blocks/71_two_stage_transformer_stroke/02block_tst_timeseries.R`
- 用途: ##############################################################################
- config 节: `config$data`, `config$tst_stroke`, `config$tst_timeseries`
- 回读: `Blocks/71_two_stage_transformer_stroke/02block_tst_timeseries.R` 文件头注释

#### `tst_train_eval`
- 路径: `Blocks/71_two_stage_transformer_stroke/06block_tst_train_eval.R`
- 用途: ##############################################################################
- 回读: `Blocks/71_two_stage_transformer_stroke/06block_tst_train_eval.R` 文件头注释


### `72_incidence_prognosis_two_stage/`

#### `ip_cohort_sle_aki`
- 路径: `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R`
- 用途: ip_cohort_sle_aki — SLE 背景 ∩ MIMIC ICU baseline 纳排分析集
- 典型位置: ip_cohort_sle_aki → attrition_flowchart → data_clean → column_mapping → index → analysis_exclusion → imputation
- 前置: `require_config = config$ip_two_stage$baseline_path / sle_path / arf_path`
- config 节: `config$ip_two_stage`
- 回读: `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R` 文件头注释

#### `ip_stage2_cohort_28d`
- 路径: `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R`
- 用途: ip_stage2_cohort_28d — AKI 阳性亚队列 + 预后 CSV + 规则 C 时间零点 + 28 天行政截尾
- 典型位置: Stage1 发病链 → ip_stage2_cohort_28d → Stage2 预后链（cox/KM/rcs…）
- 前置: `require_config = config$ip_two_stage$prognosis_path`; `require_data = ctx$data$imputed %||% ctx$data$locked %||% ctx$data$cleaned`
- config 节: `config$data`, `config$ip_two_stage`, `config$project`
- 回读: `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R` 文件头注释

#### `threshold_logistic`
- 路径: `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R`
- 用途: threshold_logistic — 发病侧连续 index 的 threshold / piecewise logistic 表+图
- 典型位置: … → rcs_incidence → threshold_logistic → subgroup_incidence
- 前置: `require_data = ctx$data$imputed %||% ctx$data$cleaned`; `require_study = project$study_type == "incidence"（非 incidence 则跳过）`
- config 节: `config$threshold_logistic`
- 回读: `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R` 文件头注释


### `73_ml_nafld_cm/`

#### `ml_nafld_external_bridge`
- 路径: `Blocks/73_ml_nafld_cm/06block_ml_nafld_external_bridge.R`
- 用途: ##############################################################################
- 典型位置: ml_nafld_pub_finalize 之后（院内主文已定稿，外部为 Figure 7 + 补充）
- config 节: `config$external_bridge`
- 回读: `Blocks/73_ml_nafld_cm/06block_ml_nafld_external_bridge.R` 文件头注释

#### `ml_nafld_feature_spaces`
- 路径: `Blocks/73_ml_nafld_cm/01block_ml_nafld_feature_spaces.R`
- 用途: ##############################################################################
- 典型位置: univariate + ml_vif_train_test 之后
- config 节: `config$feature_engineering`
- 回读: `Blocks/73_ml_nafld_cm/01block_ml_nafld_feature_spaces.R` 文件头注释

#### `ml_nafld_nested_cv`
- 路径: `Blocks/73_ml_nafld_cm/02block_ml_nafld_nested_cv.R`
- 用途: ##############################################################################
- 典型位置: ml_nafld_feature_spaces 之后（折内仍重做特征选择）
- config 节: `config$ml_small_sample`
- 回读: `Blocks/73_ml_nafld_cm/02block_ml_nafld_nested_cv.R` 文件头注释

#### `ml_nafld_omics_display`
- 路径: `Blocks/73_ml_nafld_cm/08block_ml_nafld_omics_display.R`
- 用途: ##############################################################################
- 典型位置: ml_nafld_external_bridge 之后（模块六/七补齐）
- config 节: `config$omics_display`
- 回读: `Blocks/73_ml_nafld_cm/08block_ml_nafld_omics_display.R` 文件头注释

#### `ml_nafld_pub_finalize`
- 路径: `Blocks/73_ml_nafld_cm/04block_ml_nafld_pub_finalize.R`
- 用途: ##############################################################################
- 回读: `Blocks/73_ml_nafld_cm/04block_ml_nafld_pub_finalize.R` 文件头注释

#### `ml_nafld_score_compare`
- 路径: `Blocks/73_ml_nafld_cm/03block_ml_nafld_score_compare.R`
- 用途: ##############################################################################
- 回读: `Blocks/73_ml_nafld_cm/03block_ml_nafld_score_compare.R` 文件头注释


### `74_pa_mobility_cognitive_full/`

#### `pamob_assemble_charls`
- 路径: `Blocks/74_pa_mobility_cognitive_full/02block_pamob_assemble_charls.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/02block_pamob_assemble_charls.R` 文件头注释

#### `pamob_assemble_nhanes`
- 路径: `Blocks/74_pa_mobility_cognitive_full/12block_pamob_assemble_nhanes.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/12block_pamob_assemble_nhanes.R` 文件头注释

#### `pamob_baseline_charls`
- 路径: `Blocks/74_pa_mobility_cognitive_full/04block_pamob_baseline_charls.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/04block_pamob_baseline_charls.R` 文件头注释

#### `pamob_baseline_nhanes`
- 路径: `Blocks/74_pa_mobility_cognitive_full/13block_pamob_baseline_nhanes.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/13block_pamob_baseline_nhanes.R` 文件头注释

#### `pamob_cognition_long`
- 路径: `Blocks/74_pa_mobility_cognitive_full/03block_pamob_cognition_long.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/03block_pamob_cognition_long.R` 文件头注释

#### `pamob_concept_fig1`
- 路径: `Blocks/74_pa_mobility_cognitive_full/11block_pamob_concept_fig1.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/11block_pamob_concept_fig1.R` 文件头注释

#### `pamob_contextual_inventory`
- 路径: `Blocks/74_pa_mobility_cognitive_full/19block_pamob_contextual_inventory.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/19block_pamob_contextual_inventory.R` 文件头注释

#### `pamob_contrast_preset`
- 路径: `Blocks/74_pa_mobility_cognitive_full/07block_pamob_contrast_preset.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/07block_pamob_contrast_preset.R` 文件头注释

#### `pamob_feasibility`
- 路径: `Blocks/74_pa_mobility_cognitive_full/01block_pamob_feasibility.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/01block_pamob_feasibility.R` 文件头注释

#### `pamob_flowchart`
- 路径: `Blocks/74_pa_mobility_cognitive_full/10block_pamob_flowchart.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/10block_pamob_flowchart.R` 文件头注释

#### `pamob_lmm_episodic`
- 路径: `Blocks/74_pa_mobility_cognitive_full/06block_pamob_lmm_episodic.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/06block_pamob_lmm_episodic.R` 文件头注释

#### `pamob_lmm_global`
- 路径: `Blocks/74_pa_mobility_cognitive_full/05block_pamob_lmm_global.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/05block_pamob_lmm_global.R` 文件头注释

#### `pamob_panel_fig4`
- 路径: `Blocks/74_pa_mobility_cognitive_full/16block_pamob_panel_fig4.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/16block_pamob_panel_fig4.R` 文件头注释

#### `pamob_pub_export`
- 路径: `Blocks/74_pa_mobility_cognitive_full/18block_pamob_pub_export.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/18block_pamob_pub_export.R` 文件头注释

#### `pamob_sensitivity_charls`
- 路径: `Blocks/74_pa_mobility_cognitive_full/09block_pamob_sensitivity_charls.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/09block_pamob_sensitivity_charls.R` 文件头注释

#### `pamob_sensitivity_nhanes`
- 路径: `Blocks/74_pa_mobility_cognitive_full/17block_pamob_sensitivity_nhanes.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/17block_pamob_sensitivity_nhanes.R` 文件头注释

#### `pamob_svy_dsst`
- 路径: `Blocks/74_pa_mobility_cognitive_full/14block_pamob_svy_dsst.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/14block_pamob_svy_dsst.R` 文件头注释

#### `pamob_svy_nfl`
- 路径: `Blocks/74_pa_mobility_cognitive_full/15block_pamob_svy_nfl.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/15block_pamob_svy_nfl.R` 文件头注释

#### `pamob_traj_plot`
- 路径: `Blocks/74_pa_mobility_cognitive_full/08block_pamob_traj_plot.R`
- 用途: ##############################################################################
- 回读: `Blocks/74_pa_mobility_cognitive_full/08block_pamob_traj_plot.R` 文件头注释


### `75_osteo_dxa_qct/`

#### `diagnostic_vs_fracture`
- 路径: `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R`
- 用途: ##############################################################################
- 典型位置: dxa_qct_agreement 之后；modality_discordance_profile 之前
- config 节: `config$diagnostic_vs_fracture`
- 回读: `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R` 文件头注释

#### `dxa_qct_agreement`
- 路径: `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R`
- 用途: ##############################################################################
- 典型位置: imputation / baseline_binary 之后；diagnostic_vs_fracture 之前
- config 节: `config$dxa_qct_agreement`
- 回读: `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R` 文件头注释

#### `modality_discordance_profile`
- 路径: `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R`
- 用途: ##############################################################################
- 典型位置: diagnostic_vs_fracture 之后
- config 节: `config$modality_discordance_profile`
- 回读: `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R` 文件头注释


### `76_cum_egdr_kmeans_ckm_full/`

#### `ckm_attrition_flowchart`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/00block_ckm_attrition_flowchart.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/00block_ckm_attrition_flowchart.R` 文件头注释

#### `ckm_pub_finalize`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/09block_ckm_pub_finalize.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/09block_ckm_pub_finalize.R` 文件头注释

#### `ckm_stroke_data_ingest`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/01block_ckm_stroke_data_ingest.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/01block_ckm_stroke_data_ingest.R` 文件头注释

#### `cum_exposure_build`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/02block_cum_exposure_build.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/02block_cum_exposure_build.R` 文件头注释

#### `kmeans_elbow_bivar`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/03block_kmeans_elbow_bivar.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/03block_kmeans_elbow_bivar.R` 文件头注释

#### `kmeans_trajectory_panels`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/04block_kmeans_trajectory_panels.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/04block_kmeans_trajectory_panels.R` 文件头注释

#### `logistic_cum_index_bundle`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/05block_logistic_cum_index_bundle.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/05block_logistic_cum_index_bundle.R` 文件头注释

#### `rcs_ckm_strata_panels`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/06block_rcs_ckm_strata_panels.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/06block_rcs_ckm_strata_panels.R` 文件头注释

#### `sensitivity_cox_mice_bundle`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/07block_sensitivity_cox_mice_bundle.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/07block_sensitivity_cox_mice_bundle.R` 文件头注释

#### `table1_by_class_ckm`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/04b_block_table1_by_class_ckm.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/04b_block_table1_by_class_ckm.R` 文件头注释

#### `table3_class_subgroup_forests`
- 路径: `Blocks/76_cum_egdr_kmeans_ckm_full/08block_table3_class_subgroup_forests.R`
- 用途: ##############################################################################
- 回读: `Blocks/76_cum_egdr_kmeans_ckm_full/08block_table3_class_subgroup_forests.R` 文件头注释


### `77_gallstone_nomogram_full/`

#### `gallstone_assoc_or_panels`
- 路径: `Blocks/77_gallstone_nomogram_full/02block_gallstone_assoc_or_panels.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/02block_gallstone_assoc_or_panels.R` 文件头注释

#### `gallstone_data_ingest`
- 路径: `Blocks/77_gallstone_nomogram_full/01block_gallstone_data_ingest.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/01block_gallstone_data_ingest.R` 文件头注释

#### `gallstone_dca_cic`
- 路径: `Blocks/77_gallstone_nomogram_full/09block_gallstone_dca_cic.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/09block_gallstone_dca_cic.R` 文件头注释

#### `gallstone_flowchart`
- 路径: `Blocks/77_gallstone_nomogram_full/00block_gallstone_flowchart.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/00block_gallstone_flowchart.R` 文件头注释

#### `gallstone_lasso_onese`
- 路径: `Blocks/77_gallstone_nomogram_full/06block_gallstone_lasso_onese.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/06block_gallstone_lasso_onese.R` 文件头注释

#### `gallstone_mv_nomogram`
- 路径: `Blocks/77_gallstone_nomogram_full/07block_gallstone_mv_nomogram.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/07block_gallstone_mv_nomogram.R` 文件头注释

#### `gallstone_pub_finalize`
- 路径: `Blocks/77_gallstone_nomogram_full/11block_gallstone_pub_finalize.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/11block_gallstone_pub_finalize.R` 文件头注释

#### `gallstone_rcs_panels`
- 路径: `Blocks/77_gallstone_nomogram_full/03block_gallstone_rcs_panels.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/03block_gallstone_rcs_panels.R` 文件头注释

#### `gallstone_roc_cal_boot`
- 路径: `Blocks/77_gallstone_nomogram_full/08block_gallstone_roc_cal_boot.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/08block_gallstone_roc_cal_boot.R` 文件头注释

#### `gallstone_subgroup_sex`
- 路径: `Blocks/77_gallstone_nomogram_full/10block_gallstone_subgroup_sex.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/10block_gallstone_subgroup_sex.R` 文件头注释

#### `gallstone_table1`
- 路径: `Blocks/77_gallstone_nomogram_full/04block_gallstone_table1.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/04block_gallstone_table1.R` 文件头注释

#### `gallstone_train_split`
- 路径: `Blocks/77_gallstone_nomogram_full/05block_gallstone_train_split.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/05block_gallstone_train_split.R` 文件头注释

#### `gallstone_uv_covariate_screen`
- 路径: `Blocks/77_gallstone_nomogram_full/01a_block_gallstone_uv_covariate_screen.R`
- 用途: ##############################################################################
- 回读: `Blocks/77_gallstone_nomogram_full/01a_block_gallstone_uv_covariate_screen.R` 文件头注释

<!-- END AUTO:block_cards -->

<!-- BEGIN AUTO:id_list -->
## 9. 全量 register_block 列表（AUTO）

`ROC`, `ai_cases_prepare`, `ai_guideline_audit`, `ai_lab_interpret`, `ai_llm_evaluate`, `ai_llm_multimodel`, `ai_multiround_sim`, `ai_order_robustness`, `ai_qa_cot_eval`, `ai_qa_dataset_summary`, `ai_qa_model_ranking`, `ai_qa_prepare`, `ai_qa_prompt_compare`, `ai_qa_prompt_templates`, `ai_qa_statistics`, `ai_qa_table4_validate`, `ai_reader_comparison`, `ai_reader_study`, `analysis_exclusion`, `attrition_flowchart`, `baseline_binary`, `baseline_multiclass`, `baseline_nhanes`, `bayesian_bodn`, `bayesian_body_clock`, `bayesian_bsc_aging`, `bayesian_bsc_clocks`, `bayesian_health_octo_suite`, `bayesian_outcome_validate`, `bayesian_roc_calibration`, `bkmr_analysis`, `bkmr_fit`, `boxplot`, `cart_decision_path`, `cdc_wonder_fetch`, `cftraj_causal_forest`, `cftraj_circs_compute`, `cftraj_lcmm_episodic`, `cftraj_lcmm_fit`, `cftraj_multinomial`, `cftraj_sensitivity`, `cftraj_subgroup_viz`, `cftraj_trajectory_validate`, `cftraj_wide_to_long`, `chord_diagram`, `cits_aggregate_monthly`, `cits_model_fit`, `cits_model_full`, `cits_plot`, `cits_publication_tables`, `cits_sensitivity`, `cits_sensitivity_extended`, `ckm_attrition_flowchart`, `ckm_pub_finalize`, `ckm_stroke_data_ingest`, `column_mapping`, `competing_baseline_quartile`, `competing_baseline_trajectory`, `competing_cif_plot`, `competing_cox_sensitivity`, `competing_finegray`, `competing_flowchart`, `competing_index_exposure`, `competing_lmm_trajectory`, `competing_mixed_cox`, `competing_models_123`, `competing_models_123_death`, `competing_ph_calibration`, `competing_pub_export`, `competing_rcs`, `competing_stratified`, `competing_supp_tables`, `competing_trajectory_cluster`, `competing_tyg_compute`, `complex_network_bootnet`, `complex_network_covariate_residual`, `complex_network_descriptive`, `complex_network_ggm`, `complex_network_publication_tables`, `composite_risk_cox`, `correlation`, `cox_binary`, `cox_interaction`, `cox_ml_continuous_batch`, `cox_quartile`, `cox_quintile`, `cox_sextile`, `cox_subphenotype`, `cox_tertile`, `crm_cox_mortality`, `crm_gout_strata`, `crm_mr_figures`, `crm_mr_literature`, `crm_multivariate_prognosis`, `crm_nhanes_baseline_weighted`, `crm_nhanes_cox_pub`, `crm_nhanes_derive`, `crm_nhanes_flowchart`, `crm_nhanes_km_pub`, `crm_nhanes_ordinal_pub`, `crm_nhanes_pub_align`, `crm_nhanes_pub_deliverables`, `crm_nhanes_rcs_pub`, `crm_nhanes_subgroup_supp`, `crm_nhanes_weighted`, `crm_ordinal_logistic`, `crm_rcs_sua`, `cross_lagged_biomarker_cor`, `cross_lagged_change_logistic`, `cross_lagged_corr_table`, `cross_lagged_country_year_bar`, `cross_lagged_cox_frailty`, `cross_lagged_fi_compute`, `cross_lagged_fig1_group`, `cross_lagged_forest_or`, `cross_lagged_frailty_transition`, `cross_lagged_km`, `cross_lagged_long_prepare`, `cross_lagged_mediation`, `cross_lagged_mediation_bootstrap`, `cross_lagged_meta_merge`, `cross_lagged_network`, `cross_lagged_network_bootstrap`, `cross_lagged_panel_network`, `cross_lagged_pooled_bind`, `cross_lagged_sensitivity`, `cross_lagged_subgroup`, `cross_lagged_subgroup_extended`, `cum_exposure_build`, `cutoff`, `data_clean`, `dcs_bivariate_dcsm`, `dcs_data_prep`, `dcs_depression_to_memory`, `dcs_descriptive`, `dcs_literature_validate`, `dcs_memory_to_depression`, `dcs_sensitivity`, `dcs_verbal_fluency`, `diagnostic_vs_fracture`, `dual_db_column_harmonize`, `dual_db_covariate_harmonize`, `dual_db_logistic_branch_harmonize`, `dual_db_logistic_main_table_realign`, `dual_db_logistic_scheme_harmonize`, `dxa_qct_agreement`, `dynamic_causal_analysis_filter`, `dynamic_causal_cox_baseline`, `dynamic_causal_cox_total`, `dynamic_causal_index_compute`, `dynamic_causal_meta_merge`, `dynamic_causal_rcs_change`, `env_gsea`, `env_ml_gene_screen`, `env_mr_docking`, `env_network_toxicology`, `env_scrna_summary`, `environment_characteristics`, `environment_lod_screen`, `environment_single_exposure_transform`, `environment_subgroup_search`, `environment_target_enrichment`, `environment_voc_clinical_gate`, `environment_voc_corrplot`, `environment_voc_extreme_trim`, `environment_voc_log_transform`, `feature_selection_bagged_trees`, `feature_selection_bayesian`, `feature_selection_boruta`, `feature_selection_consensus`, `feature_selection_lasso`, `feature_selection_lasso_cox`, `feature_selection_lvq`, `feature_selection_random_forest`, `feature_selection_venn`, `gallstone_assoc_or_panels`, `gallstone_data_ingest`, `gallstone_dca_cic`, `gallstone_flowchart`, `gallstone_lasso_onese`, `gallstone_mv_nomogram`, `gallstone_pub_finalize`, `gallstone_rcs_panels`, `gallstone_roc_cal_boot`, `gallstone_subgroup_sex`, `gallstone_table1`, `gallstone_train_split`, `gallstone_uv_covariate_screen`, `glm_environment_quartile`, `imputation`, `index`, `ip_cohort_sle_aki`, `ip_stage2_cohort_28d`, `iptw_association`, `iptw_balance`, `ipw_diabetes_exposure`, `ipw_diabetes_flowchart`, `ipw_jin_composite_risk`, `ipw_literature_targets`, `ipw_overlap_weights`, `ipw_pub_export`, `ipw_subgroup_km_pub`, `ipw_surv_calibration_roc`, `ipw_weighted_km_pub`, `km_binary`, `km_continuous_router`, `km_strata`, `kmeans_elbow_bivar`, `kmeans_trajectory_panels`, `lasso_environment_voc`, `lca`, `logistic_binary_clogit`, `logistic_binary_glm`, `logistic_binary_glm_rcs`, `logistic_binary_iptw_weighted`, `logistic_binary_nhanes_weighted`, `logistic_binary_nhanes_weighted_rcs`, `logistic_cum_index_bundle`, `logistic_environment_glm`, `logistic_quartile_clogit`, `logistic_quartile_glm`, `logistic_quartile_glm_rcs`, `logistic_quartile_iptw_weighted`, `logistic_quartile_nhanes_weighted`, `logistic_quartile_nhanes_weighted_rcs`, `logistic_quintile_clogit`, `logistic_quintile_glm`, `logistic_quintile_glm_rcs`, `logistic_rcs_cutoff_nhanes_weighted`, `logistic_sextile_clogit`, `logistic_sextile_glm`, `logistic_subphenotype`, `logistic_tertile_clogit`, `logistic_tertile_glm`, `logistic_tertile_glm_rcs`, `logistic_tertile_iptw_weighted`, `logistic_tertile_nhanes_weighted`, `logistic_tertile_nhanes_weighted_rcs`, `markov_apoe_le_difference`, `markov_apoe_lifestyle`, `markov_life_expectancy`, `markov_life_table_figure`, `markov_msm_bootstrap`, `markov_msm_fit`, `markov_sensitivity_glmm`, `markov_state_prep`, `mediation_ers_environment`, `mediation_incidence`, `mediation_longitudinal`, `mediation_nhanes_weighted`, `mediation_prognosis`, `mediation_subgroup_router`, `medication_chemo_strata`, `medication_composite_risk`, `medication_descriptive`, `medication_km_treatment`, `medication_literature_targets`, `medication_stepp_strata`, `medication_trial_comparisons`, `ml_adaboost`, `ml_aggregate`, `ml_assoc_bundle`, `ml_assoc_covariate_resolve`, `ml_catboost`, `ml_coxboost`, `ml_dt`, `ml_enet`, `ml_enet_cox`, `ml_eval_external`, `ml_feature_selection_bundle`, `ml_gbmsurv`, `ml_id_deduplicate`, `ml_inherit_primary_features`, `ml_knn`, `ml_lightgbm`, `ml_logistic`, `ml_logistic_multi_index_bundle`, `ml_mboost_cox`, `ml_mlp`, `ml_models_bundle`, `ml_nafld_external_bridge`, `ml_nafld_feature_spaces`, `ml_nafld_nested_cv`, `ml_nafld_omics_display`, `ml_nafld_pub_finalize`, `ml_nafld_score_compare`, `ml_realmlp`, `ml_realtabpfn_2_5`, `ml_rf`, `ml_ridge_cox`, `ml_rsf`, `ml_rsvm`, `ml_stratified_reference_profile`, `ml_survivalsvm`, `ml_tablcl_v2`, `ml_tabpfn`, `ml_tabpfnv2`, `ml_vif_train_test`, `ml_xgboost`, `ml_xgbsurv`, `modality_discordance_profile`, `modmed_data_prep`, `modmed_mediation_batch`, `modmed_moderated_mediation`, `modmed_moderation`, `modmed_simple_slopes`, `modmed_spearman`, `mr_egger_presso`, `mr_pleiotropy`, `mr_sensitivity`, `mr_snp_screen`, `mr_twosample`, `multicollinearity`, `multicollinearity_final`, `multicollinearity_nhanes_final`, `multicollinearity_nhanes_screen`, `multicollinearity_screen`, `multimodal_dl_shap`, `multimodal_early_fusion`, `multimodal_omics_preprocess`, `multimorbidity_baseline_category`, `multimorbidity_gee_cognition`, `multimorbidity_gee_interaction`, `multimorbidity_gee_stratified`, `multimorbidity_kml3d_trajectory`, `multimorbidity_sensitivity_suite`, `multivariate_covariate_resolve`, `multivariate_incidence_binary`, `multivariate_incidence_harmonized`, `multivariate_incidence_multiclass`, `multivariate_nhanes`, `multivariate_nhanes_harmonized`, `multivariate_prognosis`, `multivariate_prognosis_harmonized`, `network_temp_centrality`, `network_temp_cohort_summary`, `network_temp_compute`, `network_temp_ggm_fit`, `network_temp_literature_validate`, `network_temp_mixed_model`, `network_temp_outcome_assoc`, `network_temp_prepare_long`, `network_temp_trajectory`, `obj`, `pamob_assemble_charls`, `pamob_assemble_nhanes`, `pamob_baseline_charls`, `pamob_baseline_nhanes`, `pamob_cognition_long`, `pamob_concept_fig1`, `pamob_contextual_inventory`, `pamob_contrast_preset`, `pamob_feasibility`, `pamob_flowchart`, `pamob_lmm_episodic`, `pamob_lmm_global`, `pamob_panel_fig4`, `pamob_pub_export`, `pamob_sensitivity_charls`, `pamob_sensitivity_nhanes`, `pamob_svy_dsst`, `pamob_svy_nfl`, `pamob_traj_plot`, `performance_ml`, `plot_cutoff`, `plot_histogram`, `prepare_environment_dkd_data`, `prepost_data_prep`, `prepost_descriptive`, `prepost_domain_slopes`, `prepost_literature_validate`, `prepost_lmm_fit`, `prepost_sensitivity`, `prepost_subgroup_age`, `prepost_visualize`, `process_environment_data`, `prognosis_outcome_landmark`, `qgcomp_environment`, `rcs_ckm_strata_panels`, `rcs_incidence`, `rcs_iptw_weighted`, `rcs_nhanes`, `rcs_prognosis`, `rcs_prognosis_by_group`, `remove_outliers`, `segmented_cox_binary`, `segmented_cox_quartile`, `segmented_cox_quintile`, `segmented_cox_tertile`, `sem_chain_mediation`, `sem_cox_baseline`, `sem_cox_chain_mediation`, `sem_data_prep`, `sem_descriptive`, `sem_literature_validate`, `sem_path_lavaan`, `sem_sensitivity`, `sem_stratified`, `sensitivity_cox_mice_bundle`, `sensitivity_scenarios`, `shap`, `shiny_dynnom`, `shiny_ml_app`, `simple_ROC`, `stepp_prognosis`, `subgroup_environment_or`, `subgroup_incidence`, `subgroup_incidence_continuous`, `subgroup_iptw_weighted`, `subgroup_nhanes_weighted`, `subgroup_prognosis`, `subgroup_treatment_forest`, `subtype_viz`, `supplementary_ml`, `table1_by_class_ckm`, `table1_summary`, `table3_class_subgroup_forests`, `threshold_logistic`, `train_validation`, `trajectory_baseline_by_class`, `trajectory_calc_28d_index`, `trajectory_chisq`, `trajectory_creatinine_pct`, `trajectory_dynpred`, `trajectory_dynpred_individual`, `trajectory_gbmt`, `trajectory_jlcm`, `trajectory_jlcm_discovery_validate`, `trajectory_km_class`, `trajectory_lcmm_external_validate`, `trajectory_lcmm_fit`, `trajectory_lcmm_mpcmp_plot`, `trajectory_outcome_adjusted`, `trajectory_outcome_models`, `trajectory_piecewise_cox`, `trajectory_plot_gbmt`, `trajectory_plot_jlcm`, `trajectory_prepare_wide_rdata`, `trajectory_subgroup_class`, `trajectory_weibull_compare`, `trajectory_wide_to_long`, `trf_calibration`, `trf_causal_discovery`, `trf_data_prep`, `trf_early_detection`, `trf_external_val`, `trf_feature_reduce`, `trf_literature_validate`, `trf_multicenter_val`, `trf_sensitivity`, `trf_train_eval`, `trim_index_extreme`, `tst_calibration_dca`, `tst_cohort`, `tst_external`, `tst_landmark`, `tst_literature_validate`, `tst_pub_export`, `tst_repo_a1`, `tst_shap`, `tst_split`, `tst_summary_results`, `tst_timeseries`, `tst_train_eval`, `tte_bootstrap_ci`, `tte_data_prep`, `tte_descriptive`, `tte_literature_validate`, `tte_pooled_logistic`, `tte_risk_difference`, `tte_sensitivity`, `tte_stratified`, `tte_weighting`, `univariate_incidence_binary`, `univariate_incidence_multiclass`, `univariate_nhanes`, `univariate_prognosis`, `unsupervised_clustering_table`, `voc_correlation`, `wqs_environment`

<!-- END AUTO:id_list -->
