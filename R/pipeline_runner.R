###############################################################################
#  pipeline_runner.R — 通用 Block 流水线引擎
#  block 名 → 源文件映射在此维护；config 只放参数，不放 run_block 代码
#
#  run_pipeline(..., run_opts):
#    from  — 从某步之后续跑（block 名或 step03_imputation）
#    to    — 只跑到某步（含该步）
#    only  — 只跑列出的 block（保持 pipeline$blocks 顺序）
###############################################################################

pipeline_block_sources <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  b <- function(...) file.path(root, "Blocks", ...)
  list(
    data_clean                    = b("02_data_clean/01block_data_clean.R"),
    attrition_flowchart           = b("00_attrition/01block_attrition_flowchart.R"),
    column_mapping                = b("01_column_mappings/01block_column_mapping.R"),
    dual_db_column_harmonize      = b("00_dual_db/01block_dual_db_column_harmonize.R"),
    dual_db_covariate_harmonize   = b("00_dual_db/02block_dual_db_covariate_harmonize.R"),
    dual_db_logistic_branch_harmonize = b("00_dual_db/03block_dual_db_logistic_branch_harmonize.R"),
    dual_db_logistic_scheme_harmonize = b("00_dual_db/04block_dual_db_logistic_scheme_harmonize.R"),
    dual_db_logistic_main_table_realign = b("00_dual_db/05block_dual_db_logistic_main_table_realign.R"),
    imputation                    = b("03_imputation/01block_imputation.R"),
    environment_voc_log_transform = b("35_environment_function/00block_environment_voc_log_transform.R"),
    trim_index_extreme            = b("03_imputation/02block_trim_index_extreme.R"),
    analysis_exclusion            = b("03_imputation/03block_analysis_exclusion.R"),
    index                         = b("00_index/01block_index.R"),
    baseline_binary               = b("04_baseline/01block_baseline_binary.R"),
    baseline_multiclass           = b("04_baseline/02block_baseline_multiclass.R"),
    baseline_nhanes               = b("04_baseline/03block_baseline_nhanes.R"),
    boxplot                       = b("05_boxplot/01block_boxplot.R"),
    univariate_prognosis          = b("06_univariate/01block_univariate_prognosis.R"),
    univariate_incidence_binary   = b("06_univariate/02block_univariate_incidence_binary.R"),
    univariate_nhanes             = b("06_univariate/04block_univariate_nhanes.R"),
    multivariate_prognosis        = b("07_multivariate/01block_multivariate_prognosis.R"),
    multivariate_prognosis_harmonized = b("07_multivariate/01block_multivariate_prognosis.R"),
    multivariate_incidence_binary = b("07_multivariate/02block_multivariate_incidence_binary.R"),
    multivariate_incidence_harmonized = b("07_multivariate/02block_multivariate_incidence_binary.R"),
    multivariate_nhanes           = b("07_multivariate/04block_multivariate_nhanes.R"),
    multivariate_nhanes_harmonized = b("07_multivariate/04block_multivariate_nhanes.R"),
    multivariate_covariate_resolve = b("07_multivariate/05block_multivariate_covariate_resolve.R"),
    multicollinearity             = b("08_vif/01block_multicollinearity.R"),
    multicollinearity_screen      = b("08_vif/01block_multicollinearity.R"),
    multicollinearity_final       = b("08_vif/01block_multicollinearity.R"),
    multicollinearity_nhanes_screen = b("08_vif/02block_multicollinearity_nhanes_weighted.R"),
    multicollinearity_nhanes_final  = b("08_vif/02block_multicollinearity_nhanes_weighted.R"),
    correlation                   = b("09_correlation/01block_correlation.R"),
    lca                           = b("30_lca/01block_lca.R"),
    subtype_viz                   = b("31_subtype_viz/01block_subtype_viz.R"),
    chord_diagram                 = b("29_chord_diagram/01block_chord_diagram.R"),
    cox_binary                    = b("10_cox/01block_cox_binary.R"),
    cox_subphenotype              = b("10_cox/07block_cox_subphenotype_multimodel.R"),
    cox_tertile                   = b("10_cox/02block_cox_tertile.R"),
    cox_quartile                  = b("10_cox/03block_cox_quartile.R"),
    cox_quintile                  = b("10_cox/04block_cox_quintile.R"),
    cox_sextile                   = b("10_cox/05block_cox_sextile.R"),
    cox_interaction               = b("10_cox/06block_cox_interaction.R"),
    cox_ml_continuous_batch       = b("10_cox/08block_cox_ml_continuous_batch.R"),
    logistic_binary_glm           = b("11_logistic/04block_logistic_binary_glm.R"),
    logistic_subphenotype         = b("11_logistic/12block_logistic_subphenotype_multimodel.R"),
    logistic_binary_clogit        = b("11_logistic/07block_logistic_binary_clogit.R"),
    logistic_quartile_glm         = b("11_logistic/01block_logistic_quartile_glm.R"),
    logistic_quartile_glm_rcs     = b("11_logistic/01block_logistic_quartile_glm.R"),
    logistic_quintile_glm         = b("11_logistic/02block_logistic_quintile_glm.R"),
    logistic_tertile_glm          = b("11_logistic/05block_logistic_tertile_glm.R"),
    logistic_tertile_glm_rcs      = b("11_logistic/05block_logistic_tertile_glm.R"),
    logistic_binary_glm_rcs       = b("11_logistic/04block_logistic_binary_glm.R"),
    logistic_quartile_nhanes_weighted     = b("11_logistic/13block_logistic_quartile_nhanes_weighted.R"),
    logistic_quartile_nhanes_weighted_rcs = b("11_logistic/13block_logistic_quartile_nhanes_weighted.R"),
    logistic_tertile_nhanes_weighted      = b("11_logistic/14block_logistic_tertile_nhanes_weighted.R"),
    logistic_tertile_nhanes_weighted_rcs  = b("11_logistic/14block_logistic_tertile_nhanes_weighted.R"),
    logistic_binary_nhanes_weighted       = b("11_logistic/15block_logistic_binary_nhanes_weighted.R"),
    logistic_binary_nhanes_weighted_rcs = b("11_logistic/15block_logistic_binary_nhanes_weighted.R"),
    logistic_rcs_cutoff_nhanes_weighted = b("11_logistic/16block_logistic_rcs_cutoff_nhanes_weighted.R"),
    logistic_nhanes_weighted_common     = b("11_logistic/00logistic_nhanes_weighted_common.R"),
    logistic_iptw_weighted_common       = b("11_logistic/00logistic_iptw_weighted_common.R"),
    km_binary                     = b("27_KM/01block_km_binary.R"),
    km_strata                     = b("27_KM/02block_km_strata.R"),
    km_continuous_router          = b("27_KM/03block_km_continuous_router.R"),
    plot_cutoff                   = b("28_plot/01block_plot_cutoff.R"),
    plot_histogram                = b("28_plot/02block_histogram.R"),
    unsupervised_clustering_table = b("18_subgroup/06block_subgroup_unsupervised_clustering.R"),
    obj                           = b("12_obj/01block_obj.R"),
    cutoff                        = b("14_cutoff/01block_cutoff.R"),
    rcs_prognosis                 = b("15_rcs/01block_rcs_prognosis.R"),
    rcs_incidence                 = b("15_rcs/02block_rcs_incidence.R"),
    rcs_nhanes                    = b("15_rcs/03block_rcs_nhanes.R"),
    rcs_prognosis_by_group        = b("15_rcs/04block_rcs_prognosis_by_group.R"),
    stepp_prognosis               = b("32_stepp/01block_stepp_prognosis.R"),
    segmented_cox_binary          = b("16_weightcox/01block_segmented_cox_binary.R"),
    segmented_cox_tertile         = b("16_weightcox/02block_segmented_cox_tertile.R"),
    segmented_cox_quartile        = b("16_weightcox/03block_segmented_cox_quartile.R"),
    train_validation              = b("21_train_validation/01block_train_validation.R"),
    ml_dt                         = b("22_ml_models/01block_ml_dt.R"),
    ml_rf                         = b("22_ml_models/02block_ml_rf.R"),
    ml_xgboost                    = b("22_ml_models/03block_ml_xgboost.R"),
    ml_enet                       = b("22_ml_models/04block_ml_enet.R"),
    ml_rsvm                       = b("22_ml_models/05block_ml_rsvm.R"),
    ml_mlp                        = b("22_ml_models/06block_ml_mlp.R"),
    ml_realmlp                    = b("22_ml_models/07block_ml_realmlp.R"),
    ml_logistic                   = b("22_ml_models/08block_ml_logistic.R"),
    ml_lightgbm                   = b("22_ml_models/09block_ml_lightgbm.R"),
    ml_knn                        = b("22_ml_models/10block_ml_knn.R"),
    ml_adaboost                   = b("22_ml_models/11block_ml_adaboost.R"),
    ml_catboost                   = b("22_ml_models/12block_ml_catboost.R"),
    ml_tabpfn                     = b("22_ml_models/13block_ml_tabpfn.R"),
    ml_tabpfnv2                   = b("22_ml_models/14block_ml_tabpfnv2.R"),
    ml_realtabpfn_2_5             = b("22_ml_models/15block_ml_realtabpfn_2_5.R"),
    ml_tablcl_v2                  = b("22_ml_models/16block_ml_tablcl_v2.R"),
    ml_rsf                        = b("22_ml_models/18block_ml_rsf.R"),
    ml_xgbsurv                    = b("22_ml_models/19block_ml_xgbsurv.R"),
    ml_aggregate                  = b("22_ml_models/17block_ml_aggregate.R"),
    performance_ml                = b("23_ml_performance/01block_performance_ml.R"),
    supplementary_ml              = b("24_ml_supplementary/01block_supplementary_ml.R"),
    shiny_dynnom                  = b("25_shiny/01block_shiny_dynnom.R"),
    shiny_ml_app                  = b("25_shiny/02block_shiny_ml_app.R"),
    feature_selection_lasso       = b("19_feature_selection/01block_feature_selection_lasso.R"),
    feature_selection_boruta      = b("19_feature_selection/02block_feature_selection_boruta.R"),
    feature_selection_bayesian    = b("19_feature_selection/03block_feature_selection_bayesian.R"),
    feature_selection_random_forest = b("19_feature_selection/04block_feature_selection_random_forest.R"),
    feature_selection_bagged_trees  = b("19_feature_selection/05block_feature_selection_bagged_trees.R"),
    feature_selection_lvq         = b("19_feature_selection/06block_feature_selection_lvq.R"),
    feature_selection_consensus   = b("19_feature_selection/07block_feature_selection_consensus.R"),
    feature_selection_venn        = b("19_feature_selection/08block_feature_selection_venn.R"),
    ml_feature_selection_bundle   = b("24_ml_dual/02block_ml_feature_selection_bundle.R"),
    ml_models_bundle              = b("24_ml_dual/03block_ml_models_bundle.R"),
    ml_inherit_primary_features   = b("24_ml_dual/01block_ml_inherit_primary_features.R"),
    ml_logistic_multi_index_bundle = b("24_ml_dual/04block_ml_logistic_multi_index_bundle.R"),
    ml_assoc_bundle               = b("24_ml_dual/05block_ml_assoc_bundle.R"),
    ml_vif_train_test             = b("24_ml_dual/06block_ml_vif_train_test.R"),
    ml_assoc_covariate_resolve    = b("24_ml_dual/07block_ml_assoc_covariate_resolve.R"),
    ROC                           = b("13_roc/01block_ROC.R"),
    simple_ROC                    = b("13_roc/02block_simple_ROC.R"),
    shap                          = b("17_shap/01block_shap.R"),
    subgroup_prognosis            = b("18_subgroup/01block_subgroup_prognosis.R"),
    subgroup_incidence            = b("18_subgroup/02block_subgroup_incidence.R"),
    subgroup_nhanes_weighted      = b("18_subgroup/03block_subgroup_nhanes_weighted.R"),
    subgroup_prognosis_continuous = b("18_subgroup/04block_subgroup_prognosis_continuous.R"),
    subgroup_incidence_continuous = b("18_subgroup/05block_subgroup_incidence_continuous.R"),
    mediation_prognosis           = b("20_mediation/01block_mediation_prognosis.R"),
    mediation_incidence           = b("20_mediation/02block_mediation_incidence.R"),
    mediation_nhanes_weighted     = b("20_mediation/03block_mediation_nhanes_weighted.R"),
    mediation_ers_environment     = b("20_mediation/04block_mediation_ers_environment.R"),
    mediation_subgroup_router     = b("20_mediation/05block_mediation_subgroup_router.R"),
    modmed_data_prep              = b("20_mediation/07block_modmed_data_prep.R"),
    modmed_spearman               = b("20_mediation/08block_modmed_spearman.R"),
    modmed_mediation_batch        = b("20_mediation/09block_modmed_mediation_batch.R"),
    modmed_moderation             = b("20_mediation/10block_modmed_moderation.R"),
    modmed_moderated_mediation    = b("20_mediation/11block_modmed_moderated_mediation.R"),
    modmed_simple_slopes          = b("20_mediation/12block_modmed_simple_slopes.R"),
    sensitivity_scenarios         = b("36_capability/01block_sensitivity_scenarios.R"),
    process_environment_data      = b("35_environment_function/01block_process_environment_data.R"),
    prepare_environment_dkd_data  = b("35_environment_function/00block_prepare_environment_dkd_data.R"),
    environment_lod_screen          = b("35_environment_function/07block_environment_lod_screen.R"),
    environment_voc_clinical_gate   = b("35_environment_function/02block_environment_voc_clinical_gate.R"),
    environment_voc_corrplot        = b("35_environment_function/08block_environment_voc_corrplot.R"),
    environment_subgroup_search     = b("35_environment_function/05block_environment_subgroup_search.R"),
    environment_voc_extreme_trim    = b("35_environment_function/06block_environment_voc_extreme_trim.R"),
    remove_outliers               = b("35_environment_function/02block_remove_outliers.R"),
    table1_summary                = b("35_environment_function/03block_table1_summary.R"),
    glm_environment_quartile      = b("36_environment_glm/01block_glm_environment_quartile.R"),
    wqs_environment               = b("37_environment_wqs/01block_wqs_environment.R"),
    bkmr_fit                      = b("38_environment_bkmr/01block_bkmr_fit.R"),
    bkmr_analysis                 = b("38_environment_bkmr/02block_bkmr_analysis.R"),
    qgcomp_environment            = b("39_environment_qgcomp/01block_qgcomp_environment.R"),
    environment_target_enrichment = b("41_environment_target/01block_environment_target_enrichment.R"),
    voc_correlation               = b("40_environment_descriptive/01block_voc_correlation.R"),
    environment_characteristics   = b("40_environment_descriptive/02block_environment_characteristics.R"),
    lasso_environment_voc         = b("19_feature_selection/09block_lasso_environment_voc.R"),
    subgroup_environment_or       = b("18_subgroup/09block_subgroup_environment_or.R"),
    environment_single_exposure_transform = b("42_environment_single/01block_environment_single_exposure_transform.R"),
    dynamic_causal_index_compute  = b("43_dynamic_causal/01block_dynamic_causal_index_compute.R"),
    dynamic_causal_cox_total      = b("43_dynamic_causal/02block_dynamic_causal_cox_total.R"),
    multimorbidity_baseline_category = b("44_multimorbidity/01block_multimorbidity_baseline_category.R"),
    multimorbidity_gee_cognition  = b("44_multimorbidity/02block_multimorbidity_gee_cognition.R"),
    multimodal_early_fusion       = b("45_multimodal/01block_multimodal_early_fusion.R"),
    env_network_toxicology        = b("46_environment_omics/01block_env_omics_suite.R"),
    env_ml_gene_screen            = b("46_environment_omics/01block_env_omics_suite.R"),
    env_scrna_summary             = b("46_environment_omics/01block_env_omics_suite.R"),
    env_gsea                      = b("46_environment_omics/01block_env_omics_suite.R"),
    env_mr_docking                = b("46_environment_omics/01block_env_omics_suite.R"),
    dynamic_causal_analysis_filter = b("47_dynamic_causal_full/01block_dynamic_causal_analysis_filter.R"),
    dynamic_causal_cox_baseline   = b("47_dynamic_causal_full/02block_dynamic_causal_cox_baseline.R"),
    dynamic_causal_meta_merge     = b("47_dynamic_causal_full/03block_dynamic_causal_meta_merge.R"),
    dynamic_causal_rcs_change       = b("47_dynamic_causal_full/04block_dynamic_causal_rcs_change.R"),
    multimorbidity_kml3d_trajectory = b("48_multimorbidity_full/01block_multimorbidity_kml3d_trajectory.R"),
    multimorbidity_gee_stratified = b("48_multimorbidity_full/02block_multimorbidity_gee_stratified.R"),
    multimorbidity_gee_interaction = b("48_multimorbidity_full/03block_multimorbidity_gee_interaction.R"),
    multimorbidity_sensitivity_suite = b("48_multimorbidity_full/04block_multimorbidity_sensitivity_suite.R"),
    multimodal_omics_preprocess   = b("49_multimodal_full/01block_multimodal_omics_preprocess.R"),
    multimodal_dl_shap            = b("49_multimodal_full/02block_multimodal_dl_shap.R"),
    complex_network_ggm             = b("50_complex_network/01block_complex_network_ggm.R"),
    complex_network_descriptive     = b("50_complex_network/02block_complex_network_descriptive.R"),
    complex_network_bootnet         = b("50_complex_network/03block_complex_network_bootnet.R"),
    complex_network_covariate_residual = b("50_complex_network/04block_complex_network_covariate_residual.R"),
    complex_network_publication_tables = b("50_complex_network/05block_complex_network_publication_tables.R"),
    bayesian_bodn                   = b("51_bayesian_comorbidity/01block_bayesian_bodn.R"),
    bayesian_body_clock             = b("51_bayesian_comorbidity/02block_bayesian_body_clock.R"),
    bayesian_bsc_aging              = b("51_bayesian_comorbidity/03block_bayesian_bsc_aging.R"),
    bayesian_outcome_validate       = b("51_bayesian_comorbidity/04block_bayesian_outcome_validate.R"),
    bayesian_bsc_clocks             = b("51_bayesian_comorbidity/05block_bayesian_bsc_clocks.R"),
    bayesian_health_octo_suite      = b("51_bayesian_comorbidity/06block_bayesian_health_octo_suite.R"),
    bayesian_roc_calibration        = b("51_bayesian_comorbidity/07block_bayesian_roc_calibration.R"),
    trajectory_creatinine_pct       = b("52_trajectory_incidence/00block_trajectory_creatinine_pct.R"),
    trajectory_wide_to_long         = b("52_trajectory_incidence/01block_trajectory_wide_to_long.R"),
    trajectory_lcmm_fit             = b("52_trajectory_incidence/02block_trajectory_lcmm_fit.R"),
    trajectory_outcome_models       = b("52_trajectory_incidence/03block_trajectory_outcome_models.R"),
    trajectory_prepare_wide_rdata   = b("52_trajectory_incidence/04block_trajectory_prepare_wide_rdata.R"),
    trajectory_lcmm_mpcmp_plot      = b("52_trajectory_incidence/05block_trajectory_lcmm_mpcmp_plot.R"),
    trajectory_lcmm_external_validate = b("52_trajectory_incidence/06block_trajectory_lcmm_external_validate.R"),
    trajectory_outcome_adjusted     = b("52_trajectory_incidence/07block_trajectory_outcome_adjusted.R"),
    trajectory_piecewise_cox        = b("53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R"),
    trajectory_weibull_compare      = b("53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R"),
    trajectory_jlcm_discovery_validate = b("53_trajectory_prognosis_full/03block_trajectory_jlcm_discovery_validate.R"),
    trajectory_km_class             = b("53_trajectory_prognosis_full/04block_trajectory_km_class.R"),
    trajectory_dynpred_individual   = b("53_trajectory_prognosis_full/05block_trajectory_dynpred_individual.R"),
    trajectory_subgroup_class       = b("53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R"),
    trajectory_baseline_by_class    = b("53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R"),
    trajectory_calc_28d_index       = b("53_trajectory_prognosis_full/08block_trajectory_calc_28d_index.R"),
    trajectory_gbmt                 = b("26_trajectory/01block_trajectory_gbmt.R"),
    trajectory_jlcm                 = b("26_trajectory/02block_trajectory_jlcm.R"),
    trajectory_plot_gbmt            = b("26_trajectory/03block_trajectory_plot_gbmt.R"),
    trajectory_plot_jlcm            = b("26_trajectory/04block_trajectory_plot_jlcm.R"),
    trajectory_chisq                = b("26_trajectory/05block_trajectory_chisq.R"),
    trajectory_dynpred               = b("26_trajectory/06block_trajectory_dynpred.R"),
    cross_lagged_fi_compute         = b("54_cross_lagged_full/01block_cross_lagged_fi_compute.R"),
    cross_lagged_cox_frailty        = b("54_cross_lagged_full/02block_cross_lagged_cox_frailty.R"),
    cross_lagged_mediation          = b("54_cross_lagged_full/03block_cross_lagged_mediation.R"),
    cross_lagged_panel_network      = b("54_cross_lagged_full/04block_cross_lagged_panel_network.R"),
    cross_lagged_subgroup           = b("54_cross_lagged_full/05block_cross_lagged_subgroup.R"),
    cross_lagged_km                 = b("54_cross_lagged_full/06block_cross_lagged_km.R"),
    cross_lagged_mediation_bootstrap = b("54_cross_lagged_full/07block_cross_lagged_mediation_bootstrap.R"),
    cross_lagged_frailty_transition = b("54_cross_lagged_full/08block_cross_lagged_frailty_transition.R"),
    cross_lagged_subgroup_extended  = b("54_cross_lagged_full/09block_cross_lagged_subgroup_extended.R"),
    cross_lagged_sensitivity        = b("54_cross_lagged_full/10block_cross_lagged_sensitivity.R"),
    cross_lagged_biomarker_cor      = b("54_cross_lagged_full/11block_cross_lagged_biomarker_cor.R"),
    cross_lagged_meta_merge         = b("54_cross_lagged_full/12block_cross_lagged_meta_merge.R"),
    cross_lagged_pooled_bind        = b("54_cross_lagged_full/13block_cross_lagged_pooled_bind.R"),
    cross_lagged_long_prepare       = b("54_cross_lagged_full/14block_cross_lagged_long_prepare.R"),
    cross_lagged_corr_table         = b("54_cross_lagged_full/15block_cross_lagged_corr_table.R"),
    cross_lagged_forest_or          = b("54_cross_lagged_full/16block_cross_lagged_forest_or.R"),
    cross_lagged_network            = b("54_cross_lagged_full/17block_cross_lagged_network.R"),
    cross_lagged_country_year_bar   = b("54_cross_lagged_full/18block_cross_lagged_country_year_bar.R"),
    cross_lagged_fig1_group         = b("54_cross_lagged_full/19block_cross_lagged_fig1_group.R"),
    cross_lagged_change_logistic    = b("54_cross_lagged_full/20block_cross_lagged_change_logistic.R"),
    cross_lagged_network_bootstrap  = b("54_cross_lagged_full/22block_cross_lagged_network_bootstrap.R"),
    mediation_longitudinal          = b("20_mediation/06block_mediation_longitudinal.R"),
    competing_tyg_compute           = b("55_competing_risk_full/01block_competing_tyg_compute.R"),
    competing_lmm_trajectory        = b("55_competing_risk_full/02block_competing_lmm_trajectory.R"),
    competing_finegray              = b("55_competing_risk_full/03block_competing_finegray.R"),
    competing_rcs                   = b("55_competing_risk_full/05block_competing_rcs.R"),
    competing_cif_plot              = b("55_competing_risk_full/06block_competing_cif_plot.R"),
    competing_mixed_cox             = b("55_competing_risk_full/07block_competing_mixed_cox.R"),
    competing_models_123            = b("55_competing_risk_full/09block_competing_models_123.R"),
    competing_stratified            = b("55_competing_risk_full/10block_competing_stratified.R"),
    competing_cox_sensitivity       = b("55_competing_risk_full/11block_competing_cox_sensitivity.R"),
    competing_ph_calibration        = b("55_competing_risk_full/12block_competing_ph_calibration.R"),
    competing_index_exposure        = b("55_competing_risk_full/13block_competing_index_exposure.R"),
    competing_baseline_quartile     = b("55_competing_risk_full/14block_competing_baseline_quartile.R"),
    competing_baseline_trajectory   = b("55_competing_risk_full/15block_competing_baseline_trajectory.R"),
    competing_models_123_death      = b("55_competing_risk_full/16block_competing_models_123_death.R"),
    competing_flowchart             = b("55_competing_risk_full/17block_competing_flowchart.R"),
    competing_pub_export            = b("55_competing_risk_full/18block_competing_pub_export.R"),
    competing_supp_tables           = b("55_competing_risk_full/19block_competing_supp_tables.R"),
    competing_trajectory_cluster    = b("55_competing_risk_full/20block_competing_trajectory_cluster.R"),
    ai_cases_prepare                = b("56_ai_clinical_full/01block_ai_cases_prepare.R"),
    ai_llm_evaluate                 = b("56_ai_clinical_full/02block_ai_llm_evaluate.R"),
    ai_guideline_audit              = b("56_ai_clinical_full/03block_ai_guideline_audit.R"),
    ai_reader_comparison            = b("56_ai_clinical_full/04block_ai_reader_comparison.R"),
    ai_multiround_sim               = b("56_ai_clinical_full/05block_ai_multiround_sim.R"),
    ai_llm_multimodel               = b("56_ai_clinical_full/06block_ai_llm_multimodel.R"),
    ai_reader_study                 = b("56_ai_clinical_full/07block_ai_reader_study.R"),
    ai_lab_interpret                = b("56_ai_clinical_full/08block_ai_lab_interpret.R"),
    ai_order_robustness             = b("56_ai_clinical_full/09block_ai_order_robustness.R"),
    crm_ordinal_logistic            = b("57_dual_incidence_mr_full/01block_crm_ordinal_logistic.R"),
    crm_cox_mortality               = b("57_dual_incidence_mr_full/02block_crm_cox_mortality.R"),
    crm_rcs_sua                     = b("57_dual_incidence_mr_full/03block_crm_rcs_sua.R"),
    mr_twosample                    = b("57_dual_incidence_mr_full/04block_mr_twosample.R"),
    mr_sensitivity                  = b("57_dual_incidence_mr_full/05block_mr_sensitivity.R"),
    mr_snp_screen                   = b("57_dual_incidence_mr_full/06block_mr_snp_screen.R"),
    mr_egger_presso                 = b("57_dual_incidence_mr_full/07block_mr_egger_presso.R"),
    mr_pleiotropy                   = b("57_dual_incidence_mr_full/08block_mr_pleiotropy.R"),
    crm_nhanes_weighted             = b("57_dual_incidence_mr_full/09block_crm_nhanes_weighted.R"),
    crm_gout_strata                 = b("57_dual_incidence_mr_full/10block_crm_gout_strata.R"),
    crm_nhanes_derive             = b("70_crm_nhanes_pub/01block_crm_nhanes_derive.R"),
    crm_nhanes_flowchart          = b("70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R"),
    crm_nhanes_baseline_weighted  = b("70_crm_nhanes_pub/03block_crm_nhanes_baseline_weighted.R"),
    crm_nhanes_km_pub             = b("70_crm_nhanes_pub/04block_crm_nhanes_km_pub.R"),
    crm_nhanes_ordinal_pub        = b("70_crm_nhanes_pub/05block_crm_nhanes_ordinal_pub.R"),
    crm_nhanes_cox_pub            = b("70_crm_nhanes_pub/06block_crm_nhanes_cox_pub.R"),
    crm_nhanes_rcs_pub            = b("70_crm_nhanes_pub/07block_crm_nhanes_rcs_pub.R"),
    crm_nhanes_pub_align          = b("70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R"),
    crm_mr_figures                = b("70_crm_nhanes_pub/09block_crm_mr_figures.R"),
    crm_nhanes_subgroup_supp      = b("70_crm_nhanes_pub/10block_crm_nhanes_subgroup_supp.R"),
    crm_mr_literature             = b("70_crm_nhanes_pub/11block_crm_mr_literature.R"),
    crm_nhanes_pub_deliverables   = b("70_crm_nhanes_pub/12block_crm_nhanes_pub_deliverables.R"),
    crm_multivariate_prognosis    = b("70_crm_nhanes_pub/13block_crm_multivariate_prognosis.R"),
    medication_composite_risk       = b("58_medication_regimen_full/01block_medication_composite_risk.R"),
    medication_descriptive          = b("58_medication_regimen_full/02block_medication_descriptive.R"),
    medication_km_treatment         = b("58_medication_regimen_full/03block_medication_km_treatment.R"),
    medication_chemo_strata         = b("58_medication_regimen_full/04block_medication_chemo_strata.R"),
    medication_trial_comparisons    = b("58_medication_regimen_full/05block_medication_trial_comparisons.R"),
    medication_stepp_strata         = b("58_medication_regimen_full/06block_medication_stepp_strata.R"),
    medication_literature_targets   = b("58_medication_regimen_full/07block_medication_literature_targets.R"),
    markov_state_prep               = b("59_markov_cognitive_full/01block_markov_state_prep.R"),
    markov_msm_fit                  = b("59_markov_cognitive_full/02block_markov_msm_fit.R"),
    markov_life_expectancy          = b("59_markov_cognitive_full/03block_markov_life_expectancy.R"),
    markov_apoe_lifestyle           = b("59_markov_cognitive_full/04block_markov_apoe_lifestyle.R"),
    markov_msm_bootstrap            = b("59_markov_cognitive_full/05block_markov_msm_bootstrap.R"),
    markov_life_table_figure        = b("59_markov_cognitive_full/06block_markov_life_table_figure.R"),
    markov_apoe_le_difference       = b("59_markov_cognitive_full/07block_markov_apoe_le_difference.R"),
    markov_sensitivity_glmm         = b("59_markov_cognitive_full/08block_markov_sensitivity_glmm.R"),
    cdc_wonder_fetch                = b("60_cdc_wonder_cits_full/05block_cdc_wonder_fetch.R"),
    cits_aggregate_monthly          = b("60_cdc_wonder_cits_full/01block_cits_aggregate_monthly.R"),
    cits_model_fit                  = b("60_cdc_wonder_cits_full/02block_cits_model_fit.R"),
    cits_sensitivity                = b("60_cdc_wonder_cits_full/03block_cits_sensitivity.R"),
    cits_plot                       = b("60_cdc_wonder_cits_full/04block_cits_plot.R"),
    cits_model_full                 = b("60_cdc_wonder_cits_full/06block_cits_model_full.R"),
    cits_sensitivity_extended       = b("60_cdc_wonder_cits_full/07block_cits_sensitivity_extended.R"),
    cits_publication_tables         = b("60_cdc_wonder_cits_full/08block_cits_publication_tables.R"),
    network_temp_prepare_long       = b("61_network_temperature_full/01block_network_temp_prepare_long.R"),
    network_temp_compute            = b("61_network_temperature_full/02block_network_temp_compute.R"),
    network_temp_trajectory         = b("61_network_temperature_full/03block_network_temp_trajectory.R"),
    network_temp_outcome_assoc      = b("61_network_temperature_full/04block_network_temp_outcome_assoc.R"),
    network_temp_ggm_fit            = b("61_network_temperature_full/05block_network_temp_ggm_fit.R"),
    network_temp_mixed_model        = b("61_network_temperature_full/06block_network_temp_mixed_model.R"),
    network_temp_centrality         = b("61_network_temperature_full/07block_network_temp_centrality.R"),
    network_temp_cohort_summary     = b("61_network_temperature_full/08block_network_temp_cohort_summary.R"),
    network_temp_literature_validate = b("61_network_temperature_full/09block_network_temp_literature_validate.R"),
    sem_data_prep                   = b("62_sem_chain_mediation_full/01block_sem_data_prep.R"),
    sem_descriptive                 = b("62_sem_chain_mediation_full/02block_sem_descriptive.R"),
    sem_cox_baseline                = b("62_sem_chain_mediation_full/03block_sem_cox_baseline.R"),
    sem_path_lavaan                 = b("62_sem_chain_mediation_full/04block_sem_path_lavaan.R"),
    sem_chain_mediation             = b("62_sem_chain_mediation_full/05block_sem_chain_mediation.R"),
    sem_stratified                  = b("62_sem_chain_mediation_full/06block_sem_stratified.R"),
    sem_sensitivity                 = b("62_sem_chain_mediation_full/07block_sem_sensitivity.R"),
    sem_cox_chain_mediation         = b("62_sem_chain_mediation_full/08block_sem_cox_chain_mediation.R"),
    sem_literature_validate         = b("62_sem_chain_mediation_full/09block_sem_literature_validate.R"),
    ai_qa_prepare                   = b("63_ai_medical_qa_full/01block_ai_qa_prepare.R"),
    ai_qa_cot_eval                  = b("63_ai_medical_qa_full/02block_ai_qa_cot_eval.R"),
    ai_qa_prompt_compare            = b("63_ai_medical_qa_full/03block_ai_qa_prompt_compare.R"),
    ai_qa_statistics                = b("63_ai_medical_qa_full/04block_ai_qa_statistics.R"),
    ai_qa_dataset_summary           = b("63_ai_medical_qa_full/05block_ai_qa_dataset_summary.R"),
    ai_qa_model_ranking             = b("63_ai_medical_qa_full/06block_ai_qa_model_ranking.R"),
    ai_qa_prompt_templates          = b("63_ai_medical_qa_full/07block_ai_qa_prompt_templates.R"),
    ai_qa_table4_validate           = b("63_ai_medical_qa_full/08block_ai_qa_table4_validate.R"),
    cftraj_circs_compute            = b("64_causal_forest_trajectory_full/01block_cftraj_circs_compute.R"),
    cftraj_wide_to_long             = b("64_causal_forest_trajectory_full/02block_cftraj_wide_to_long.R"),
    cftraj_lcmm_fit                 = b("64_causal_forest_trajectory_full/03block_cftraj_lcmm_fit.R"),
    cftraj_multinomial              = b("64_causal_forest_trajectory_full/04block_cftraj_multinomial.R"),
    cftraj_causal_forest            = b("64_causal_forest_trajectory_full/05block_cftraj_causal_forest.R"),
    cftraj_subgroup_viz             = b("64_causal_forest_trajectory_full/06block_cftraj_subgroup_viz.R"),
    cftraj_sensitivity              = b("64_causal_forest_trajectory_full/07block_cftraj_sensitivity.R"),
    cftraj_lcmm_episodic            = b("64_causal_forest_trajectory_full/08block_cftraj_lcmm_episodic.R"),
    cftraj_trajectory_validate      = b("64_causal_forest_trajectory_full/09block_cftraj_trajectory_validate.R"),
    prepost_data_prep               = b("65_incidence_prepost_full/01block_prepost_data_prep.R"),
    prepost_descriptive             = b("65_incidence_prepost_full/02block_prepost_descriptive.R"),
    prepost_lmm_fit                 = b("65_incidence_prepost_full/03block_prepost_lmm_fit.R"),
    prepost_domain_slopes           = b("65_incidence_prepost_full/04block_prepost_domain_slopes.R"),
    prepost_subgroup_age            = b("65_incidence_prepost_full/05block_prepost_subgroup_age.R"),
    prepost_sensitivity             = b("65_incidence_prepost_full/06block_prepost_sensitivity.R"),
    prepost_visualize               = b("65_incidence_prepost_full/07block_prepost_visualize.R"),
    prepost_literature_validate     = b("65_incidence_prepost_full/08block_prepost_literature_validate.R"),
    tte_data_prep                   = b("66_target_trial_full/01block_tte_data_prep.R"),
    tte_descriptive                 = b("66_target_trial_full/02block_tte_descriptive.R"),
    tte_weighting                   = b("66_target_trial_full/03block_tte_weighting.R"),
    tte_pooled_logistic             = b("66_target_trial_full/04block_tte_pooled_logistic.R"),
    tte_risk_difference             = b("66_target_trial_full/05block_tte_risk_difference.R"),
    tte_bootstrap_ci                = b("66_target_trial_full/09block_tte_bootstrap_ci.R"),
    tte_stratified                  = b("66_target_trial_full/06block_tte_stratified.R"),
    tte_sensitivity                 = b("66_target_trial_full/07block_tte_sensitivity.R"),
    tte_literature_validate         = b("66_target_trial_full/08block_tte_literature_validate.R"),
    trf_data_prep                   = b("67_transformer_shortseq_full/01block_trf_data_prep.R"),
    trf_feature_reduce              = b("67_transformer_shortseq_full/02block_trf_feature_reduce.R"),
    trf_causal_discovery            = b("67_transformer_shortseq_full/09block_trf_causal_discovery.R"),
    trf_train_eval                  = b("67_transformer_shortseq_full/03block_trf_train_eval.R"),
    trf_calibration                 = b("67_transformer_shortseq_full/04block_trf_calibration.R"),
    trf_early_detection             = b("67_transformer_shortseq_full/05block_trf_early_detection.R"),
    trf_multicenter_val             = b("67_transformer_shortseq_full/10block_trf_multicenter_val.R"),
    trf_external_val                = b("67_transformer_shortseq_full/06block_trf_external_val.R"),
    trf_sensitivity                 = b("67_transformer_shortseq_full/07block_trf_sensitivity.R"),
    trf_literature_validate         = b("67_transformer_shortseq_full/08block_trf_literature_validate.R"),
    dcs_data_prep                   = b("68_dual_change_score_full/01block_dcs_data_prep.R"),
    dcs_descriptive                 = b("68_dual_change_score_full/02block_dcs_descriptive.R"),
    dcs_bivariate_dcsm              = b("68_dual_change_score_full/03block_dcs_bivariate_dcsm.R"),
    dcs_depression_to_memory        = b("68_dual_change_score_full/04block_dcs_depression_to_memory.R"),
    dcs_memory_to_depression        = b("68_dual_change_score_full/05block_dcs_memory_to_depression.R"),
    dcs_verbal_fluency              = b("68_dual_change_score_full/06block_dcs_verbal_fluency.R"),
    dcs_sensitivity                 = b("68_dual_change_score_full/07block_dcs_sensitivity.R"),
    dcs_literature_validate         = b("68_dual_change_score_full/08block_dcs_literature_validate.R"),
    iptw_balance                  = b("34_IPTW/01block_iptw_balance.R"),
    iptw_association              = b("34_IPTW/02block_iptw_association.R"),
    subgroup_iptw_weighted        = b("18_subgroup/08block_subgroup_iptw_weighted.R"),
    subgroup_treatment_forest     = b("18_subgroup/07block_subgroup_treatment_forest.R"),
    ipw_diabetes_exposure         = b("69_ipw_diabetes_stroke_full/01block_ipw_diabetes_exposure.R"),
    ipw_diabetes_flowchart        = b("69_ipw_diabetes_stroke_full/02block_ipw_flowchart.R"),
    ipw_weighted_km_pub           = b("69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R"),
    ipw_overlap_weights           = b("69_ipw_diabetes_stroke_full/04block_ipw_overlap_weights.R"),
    ipw_subgroup_km_pub           = b("69_ipw_diabetes_stroke_full/05block_ipw_subgroup_km_pub.R"),
    ipw_literature_targets        = b("69_ipw_diabetes_stroke_full/06block_ipw_literature_targets.R"),
    ipw_pub_export                = b("69_ipw_diabetes_stroke_full/07block_ipw_pub_export.R"),
    ipw_surv_calibration_roc      = b("69_ipw_diabetes_stroke_full/08block_ipw_surv_calibration_roc.R"),
    ipw_jin_composite_risk        = b("69_ipw_diabetes_stroke_full/09block_ipw_jin_composite_risk.R"),
    tst_cohort                    = b("71_two_stage_transformer_stroke/01block_tst_cohort.R"),
    tst_timeseries                = b("71_two_stage_transformer_stroke/02block_tst_timeseries.R"),
    tst_landmark                  = b("71_two_stage_transformer_stroke/03block_tst_landmark.R"),
    tst_split                     = b("71_two_stage_transformer_stroke/04block_tst_split.R"),
    tst_repo_a1                   = b("71_two_stage_transformer_stroke/05block_tst_repo_a1.R"),
    tst_train_eval                = b("71_two_stage_transformer_stroke/06block_tst_train_eval.R"),
    tst_calibration_dca           = b("71_two_stage_transformer_stroke/07block_tst_calibration_dca.R"),
    tst_shap                      = b("71_two_stage_transformer_stroke/08block_tst_shap.R"),
    tst_external                  = b("71_two_stage_transformer_stroke/09block_tst_external.R"),
    tst_literature_validate       = b("71_two_stage_transformer_stroke/10block_tst_literature_validate.R"),
    tst_pub_export                = b("71_two_stage_transformer_stroke/11block_tst_pub_export.R"),
    tst_summary_results           = b("71_two_stage_transformer_stroke/12block_tst_summary_results.R"),
    ip_cohort_sle_aki             = b("72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R"),
    ip_stage2_cohort_28d          = b("72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R"),
    threshold_logistic            = b("72_incidence_prognosis_two_stage/03block_threshold_logistic.R"),
    render_tables                 = b("Tables_Blocks/block_render_tables.R")
  )
}

pipeline_checkpoint_id <- function(step_index, block_name) {
  sprintf("step%02d_%s", as.integer(step_index), block_name)
}

pipeline_checkpoint_dir <- function(root, pipeline) {
  ck_cfg <- pipeline$checkpoint %||% list()
  ck <- ck_cfg$dir %||% "checkpoints"
  if (!is_absolute_path(ck)) file.path(root, ck) else ck
}

pipeline_resolve_token_to_index <- function(token, blocks) {
  token <- trimws(as.character(token)[1L])
  if (!nzchar(token)) return(NA_integer_)
  blocks <- as.character(blocks)

  if (grepl("^step\\d{2}_", token, ignore.case = TRUE)) {
    for (i in seq_along(blocks)) {
      if (identical(pipeline_checkpoint_id(i, blocks[[i]]), token)) return(i)
    }
    stop("未在 pipeline$blocks 中找到检查点 ID: ", token, call. = FALSE)
  }

  if (grepl("^\\d+$", token)) {
    i <- as.integer(token)
    if (i >= 1L && i <= length(blocks)) return(i)
    stop("步骤序号超出范围: ", token, "（共 ", length(blocks), " 步）", call. = FALSE)
  }

  hit <- which(blocks == token)
  if (length(hit) == 1L) return(hit[[1L]])
  if (length(hit) > 1L) {
    stop("block 名 '", token, "' 在 pipeline 中出现多次，请用 stepNN_name 指定。", call. = FALSE)
  }

  stop(
    "无法解析步骤 '", token, "'。可用: block 名、步骤号(1-", length(blocks),
    ")、或 stepNN_blockname。", call. = FALSE
  )
}

pipeline_list_checkpoints <- function(root, pipeline) {
  ck_dir <- pipeline_checkpoint_dir(root, pipeline)
  if (!dir.exists(ck_dir)) {
    cli::cli_alert_info("检查点目录不存在: {.file {ck_dir}}")
    return(invisible(character(0)))
  }
  files <- sort(list.files(ck_dir, pattern = "\\.rds$", full.names = FALSE))
  if (!length(files)) {
    cli::cli_alert_info("检查点目录为空: {.file {ck_dir}}")
    return(invisible(character(0)))
  }
  cli::cli_h2("可用检查点 ({ck_dir})")
  for (f in files) {
    meta <- tryCatch(readRDS(file.path(ck_dir, f)), error = function(e) NULL)
    step_lab <- if (is.list(meta) && !is.null(meta$step)) meta$step else "?"
    ts <- if (is.list(meta) && !is.null(meta$saved_at)) meta$saved_at else ""
    cli::cli_li("{sub('\\\\.rds$', '', f)}{if (nzchar(ts)) paste0('  (', ts, ')') else ''}")
  }
  invisible(files)
}

pipeline_source_block <- function(root, block_name, sourced = character(0)) {
  src_map <- pipeline_block_sources(root)
  if (!block_name %in% names(src_map)) {
    stop("pipeline_source_block: unknown block '", block_name,
         "'. Add mapping in R/pipeline_runner.R.", call. = FALSE)
  }
  path <- src_map[[block_name]]
  if (!file.exists(path)) {
    stop("pipeline_source_block: file not found for '", block_name, "': ", path,
         call. = FALSE)
  }
  if (block_name %in% sourced) return(sourced)
  source(path, local = FALSE)
  c(sourced, block_name)
}

pipeline_save_checkpoint <- function(ctx, config, pipeline, step_index, block_name, checkpoint_dir) {
  if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)
  ck_id <- pipeline_checkpoint_id(step_index, block_name)
  path <- file.path(checkpoint_dir, paste0(ck_id, ".rds"))
  payload <- list(
    ctx       = ctx,
    config    = config,
    pipeline  = pipeline,
    step      = ck_id,
    block     = block_name,
    step_index = as.integer(step_index),
    saved_at  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    pub_counters = .pub_counters_snapshot()
  )
  saveRDS(payload, path)
  alias <- file.path(checkpoint_dir, paste0(block_name, ".rds"))
  tryCatch(file.copy(path, alias, overwrite = TRUE), error = function(e) NULL)
  cli::cli_alert_info("Checkpoint saved: {.file {basename(path)}}")
  invisible(path)
}

pipeline_load_checkpoint <- function(root, pipeline, from_token, blocks) {
  ck_dir <- pipeline_checkpoint_dir(root, pipeline)
  idx <- pipeline_resolve_token_to_index(from_token, blocks)
  ck_id <- pipeline_checkpoint_id(idx, blocks[[idx]])
  path <- file.path(ck_dir, paste0(ck_id, ".rds"))
  if (!file.exists(path)) {
    alias <- file.path(ck_dir, paste0(blocks[[idx]], ".rds"))
    if (file.exists(alias)) path <- alias else {
      stop(
        "检查点不存在: ", ck_id, ".rds\n",
        "请先开启 pipeline$checkpoint$enable 并完整跑到该步，或使用 --list-checkpoints 查看。",
        call. = FALSE
      )
    }
  }
  obj <- readRDS(path)
  if (is.null(obj$ctx)) stop("检查点文件无效（缺少 ctx）: ", path, call. = FALSE)
  if (!is.null(obj$pub_counters)) {
    .pub_counters_restore(obj$pub_counters)
  } else if (!is.null(obj$ctx$log$pub_counters)) {
    .pub_counters_restore(obj$ctx$log$pub_counters)
  }
  cli::cli_alert_success("已恢复检查点: {.field {obj$step %||% ck_id}}")
  list(ctx = obj$ctx, resume_after_index = idx)
}

pipeline_plan_run <- function(blocks, run_opts = list()) {
  blocks <- as.character(blocks)
  n <- length(blocks)
  if (!n) stop("pipeline$blocks 为空。", call. = FALSE)

  only <- run_opts$only %||% NULL
  if (!is.null(only) && length(only)) {
    only <- trimws(as.character(unlist(only)))
    only <- only[nzchar(only)]
    blocks <- blocks[blocks %in% only]
    if (!length(blocks)) stop("--only 与 pipeline$blocks 无交集。", call. = FALSE)
    idx_map <- match(blocks, as.character(run_opts$blocks_full %||% blocks))
  } else {
    idx_map <- seq_along(blocks)
  }

  start_i <- 1L
  end_i <- length(blocks)
  resume_from_full <- FALSE
  loaded <- NULL

  from_t <- run_opts$from %||% NULL
  to_t   <- run_opts$to %||% NULL

  if (!is.null(from_t) && nzchar(trimws(as.character(from_t)[1L]))) {
    resume_from_full <- TRUE
  }

  if (!is.null(to_t) && nzchar(trimws(as.character(to_t)[1L]))) {
    to_idx <- pipeline_resolve_token_to_index(to_t, run_opts$blocks_full %||% blocks)
    end_i <- which(idx_map == to_idx)
    if (!length(end_i)) {
      stop("--to '", to_t, "' 不在本次要执行的 block 列表中。", call. = FALSE)
    }
    end_i <- end_i[[1L]]
  }

  list(
    blocks = blocks,
    idx_map = idx_map,
    start_i = start_i,
    end_i = end_i,
    resume_from_full = resume_from_full,
    from_token = from_t,
    to_token = to_t
  )
}

pipeline_parse_cli <- function(args) {
  opts <- list(
    root = NULL,
    from = Sys.getenv("PIPELINE_RESUME_FROM", unset = ""),
    to = Sys.getenv("PIPELINE_STOP_AFTER", unset = ""),
    only = Sys.getenv("PIPELINE_ONLY", unset = ""),
    list_ck = FALSE
  )
  if (!nzchar(opts$from)) opts$from <- NULL
  if (!nzchar(opts$to)) opts$to <- NULL
  if (!nzchar(opts$only)) opts$only <- NULL

  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--from" && i < length(args)) {
      opts$from <- args[[i + 1L]]
      i <- i + 2L
    } else if (a == "--to" && i < length(args)) {
      opts$to <- args[[i + 1L]]
      i <- i + 2L
    } else if (a == "--only" && i < length(args)) {
      opts$only <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]
      opts$only <- trimws(opts$only)
      i <- i + 2L
    } else if (a %in% c("--list-checkpoints", "--list")) {
      opts$list_ck <- TRUE
      i <- i + 1L
    } else if (startsWith(a, "--")) {
      stop("未知参数: ", a, call. = FALSE)
    } else if (is.null(opts$root)) {
      opts$root <- a
      i <- i + 1L
    } else {
      stop("多余参数: ", a, call. = FALSE)
    }
  }
  opts
}

#' Figures 目录是否属于 dual-batch 分库槽位（run_pipeline 收口 export 应跳过）
pipeline_figures_is_dual_slot <- function(figs, config) {
  dual <- config$dual_db %||% list()
  cur <- dual$current_db
  if (!is.null(cur) && nzchar(as.character(cur)[1L])) return(TRUE)
  if (!isTRUE(dual$enable)) return(FALSE)

  figs_norm <- normalizePath(figs, winslash = "/", mustWork = FALSE)
  db_names <- character(0)
  for (key in c("primary", "secondary", "tertiary")) {
    nm <- (dual[[key]] %||% list())$name
    if (!is.null(nm) && nzchar(as.character(nm)[1L])) {
      db_names <- c(db_names, as.character(nm)[1L])
    }
  }
  dbs <- dual$databases
  if (!is.null(dbs) && length(dbs)) db_names <- c(db_names, as.character(dbs))
  if (exists("dual_db_sanitize_path_name", mode = "function")) {
    db_names <- unique(vapply(db_names, dual_db_sanitize_path_name, character(1L)))
  } else {
    db_names <- unique(trimws(as.character(db_names)))
  }
  db_names <- db_names[nzchar(db_names)]
  parent_dir <- basename(dirname(figs_norm))
  if (length(db_names) && parent_dir %in% db_names) return(TRUE)

  # by_index/<ix>/<slot>/Figures — 分库槽位，非指标根 aggregate Figures
  grepl("/by_index/[^/]+/[^/]+/Figures/?$", figs_norm)
}

run_pipeline <- function(root, config, pipeline, run_opts = list()) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (exists("pipeline_normalize_project_outcome_labels", mode = "function")) {
    config <- pipeline_normalize_project_outcome_labels(config)
  }
  dual_harm_path <- file.path(root, "R", "dual_db_harmonize.R")
  if (file.exists(dual_harm_path)) source(dual_harm_path, local = FALSE)
  for (gate_file in c("cox_gate.R", "logistic_gate.R", "model3_required.R", "cox_ph_test.R")) {
    gate_path <- file.path(root, "R", gate_file)
    if (file.exists(gate_path)) source(gate_path, local = FALSE)
  }
  attr_log <- file.path(root, "R", "attrition_log.R")
  if (file.exists(attr_log)) source(attr_log, local = FALSE)
  logistic_common <- file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")
  if (file.exists(logistic_common)) source(logistic_common, local = FALSE)
  logistic_iptw_common <- file.path(root, "Blocks/11_logistic/00logistic_iptw_weighted_common.R")
  if (file.exists(logistic_iptw_common)) source(logistic_iptw_common, local = FALSE)
  blocks_full <- as.character(pipeline$blocks)
  if (!length(blocks_full)) {
    stop("run_pipeline: pipeline$blocks is empty.", call. = FALSE)
  }

  if (isTRUE(run_opts$list_ck)) {
    return(pipeline_list_checkpoints(root, pipeline))
  }

  ck_cfg <- pipeline$checkpoint %||% list()
  checkpoint_enable <- isTRUE(ck_cfg$enable)
  checkpoint_dir <- pipeline_checkpoint_dir(root, pipeline)

  from_t <- run_opts$from %||% pipeline$start_from %||% NULL
  to_t   <- run_opts$to   %||% pipeline$stop_after %||% NULL
  only_t <- run_opts$only %||% pipeline$blocks_to_run %||% NULL

  run_opts$blocks_full <- blocks_full
  if (!is.null(only_t) && length(only_t)) {
    run_opts$only <- only_t
  }
  run_opts$from <- from_t
  run_opts$to <- to_t

  plan <- pipeline_plan_run(blocks_full, run_opts)
  blocks <- plan$blocks
  idx_map <- plan$idx_map

  render_tables_after  <- as.character(pipeline$render_tables_after  %||% character(0))
  render_figures_after <- as.character(pipeline$render_figures_after %||% character(0))

  cli::cli_h1("Pipeline: {pipeline$name %||% 'unnamed'}")
  if (checkpoint_enable) {
    cli::cli_alert_info("检查点: {.file {checkpoint_dir}}（关闭: pipeline$checkpoint$enable = FALSE）")
  }
  if (!is.null(from_t) && nzchar(as.character(from_t)[1L])) {
    cli::cli_alert_info("续跑: 从 {.field {from_t}} 之后继续")
  }
  if (!is.null(to_t) && nzchar(as.character(to_t)[1L])) {
    cli::cli_alert_info("范围: 执行到 {.field {to_t}}（含）")
  }
  if (!is.null(only_t) && length(only_t)) {
    cli::cli_alert_info("仅执行: {paste(blocks, collapse = ', ')}")
  } else {
    cli::cli_alert_info("Blocks ({length(blocks_full)}): {paste(blocks_full, collapse = ' → ')}")
  }
  cli::cli_alert_info("Output: {.file {config$project$output_dir %||% 'Output'}}")

  ctx <- NULL
  start_i <- 1L

  if (!is.null(run_opts$initial_ctx)) {
    ctx <- run_opts$initial_ctx
    ctx$config <- config
    ctx$root_output_dir <- config$project$output_dir %||% ctx$root_output_dir
    start_i <- 1L
    cli::cli_alert_info("已注入 initial_ctx（跳过 --from 检查点解析）")
  } else if (!is.null(from_t) && nzchar(as.character(from_t)[1L])) {
    if (!checkpoint_enable) {
      stop("使用 --from 续跑须开启 pipeline$checkpoint$enable = TRUE。", call. = FALSE)
    }
    loaded <- pipeline_load_checkpoint(root, pipeline, from_t, blocks_full)
    ctx <- loaded$ctx
    ctx$config <- config
    if (exists("environment_batch_sync_config_from_ctx", mode = "function")) {
      config <- environment_batch_sync_config_from_ctx(config, ctx)
      ctx$config <- config
    }
    # 同步输出根目录：确保各 block 写到 config$project$output_dir 而非 checkpoint 里的旧路径
    ctx$root_output_dir <- config$project$output_dir %||% ctx$root_output_dir
    resume_idx <- loaded$resume_after_index
    if (!is.null(only_t) && length(only_t)) {
      start_i <- which(idx_map > resume_idx)[1L]
    } else {
      start_i <- which(idx_map == resume_idx) + 1L
    }
    if (length(start_i) == 0L || is.na(start_i[[1L]]) || start_i[[1L]] > length(blocks)) {
      cli::cli_alert_warning("续跑起点已是本次计划的最后一步，无需执行。")
      return(invisible(ctx))
    }
    if (start_i < 1L) start_i <- 1L
  }

  if (is.null(ctx)) {
    ctx <- init_ctx(config)
  }

  end_i <- plan$end_i
  if (is.null(end_i) || end_i > length(blocks)) end_i <- length(blocks)

  ctx$pipeline_blocks <- blocks_full

  sourced <- character(0)

  for (i in seq_along(blocks)) {
    if (i < start_i) next
    if (i > end_i) break

    block_name <- blocks[[i]]
    full_idx <- idx_map[[i]]
    sourced <- pipeline_source_block(root, block_name, sourced)
    if ((block_name %in% c(
      "multicollinearity_nhanes_final",
      "logistic_quartile_nhanes_weighted", "logistic_quartile_nhanes_weighted_rcs",
      "logistic_tertile_nhanes_weighted", "logistic_tertile_nhanes_weighted_rcs",
      "logistic_binary_nhanes_weighted", "logistic_binary_nhanes_weighted_rcs",
      "rcs_nhanes", "mediation_nhanes_weighted"
    ) || grepl("^logistic_", block_name)) &&
        !"logistic_nhanes_weighted_common" %in% sourced) {
      sourced <- pipeline_source_block(root, "logistic_nhanes_weighted_common", sourced)
    }
    if ((block_name %in% c(
      "subgroup_iptw_weighted", "rcs_iptw_weighted",
      "logistic_binary_iptw_weighted", "logistic_tertile_iptw_weighted",
      "logistic_quartile_iptw_weighted"
    ) || grepl("_iptw_weighted$", block_name)) &&
        !"logistic_iptw_weighted_common" %in% sourced) {
      sourced <- pipeline_source_block(root, "logistic_iptw_weighted_common", sourced)
    }

    if (exists(".lnw00_should_skip_cascade_block", mode = "function") &&
        .lnw00_should_skip_cascade_block(block_name, ctx)) {
      cli::cli_alert_info(
        "logistic cascade 跳过 {.field {block_name}}（已选定 {ctx$results$nhanes_logistic_selected_scheme}）"
      )
      next
    }

    if (exists("pipeline_cox_gate_should_skip", mode = "function") &&
        pipeline_cox_gate_should_skip(block_name, ctx, pipeline)) {
      cli::cli_alert_info(
        "cox_gate 跳过 {.field {block_name}}（分支: {ctx$results$cox_branch %||% '?'}）"
      )
      next
    }

    if (exists("pipeline_logistic_gate_should_skip", mode = "function") &&
        pipeline_logistic_gate_should_skip(block_name, ctx, pipeline)) {
      cli::cli_alert_info(
        "logistic_gate 跳过 {.field {block_name}}（分支: {ctx$results$logistic_branch %||% '?'}）"
      )
      next
    }

    n_before <- if (exists("attrition_n_current", mode = "function")) attrition_n_current(ctx) else NA_integer_

    ctx <- tryCatch(
      run_block(ctx, block_name),
      error = function(e) {
        msg <- conditionMessage(e)
        if (grepl("^COX_SEARCH_DEGRADE:", msg)) {
          cli::cli_alert_warning(
            "协变量搜索降级: {sub('^COX_SEARCH_DEGRADE: ', '', msg)}；继续下一 block（cox_branch={ctx$results$cox_branch %||% '?'}）"
          )
          return(ctx)
        }
        if (grepl("^COX_(BOTH_MODELS_SIG|M2_NOSIG)_DEGRADE:", msg)) {
          cli::cli_alert_warning(
            "Cox 双模型显著性降级: {sub('^COX_(BOTH_MODELS_SIG|M2_NOSIG)_DEGRADE: ', '', msg)}；继续下一 block（cox_branch={ctx$results$cox_branch %||% '?'}）"
          )
          return(ctx)
        }
        stop(e)
      }
    )

    if (exists("attrition_auto_append_nrow", mode = "function") &&
        !identical(block_name, "attrition_flowchart")) {
      n_after <- attrition_n_current(ctx)
      ctx <- attrition_auto_append_nrow(ctx, block_name, n_before, n_after)
    }

    if (block_name %in% render_tables_after &&
        exists("render_queued_tables", mode = "function")) {
      ctx <- render_queued_tables(ctx)
    }
    if (block_name %in% render_figures_after &&
        exists("render_queued_figures", mode = "function")) {
      ctx <- render_queued_figures(ctx)
    }

    if (checkpoint_enable) {
      pipeline_save_checkpoint(ctx, config, pipeline, full_idx, block_name, checkpoint_dir)
    }
  }

  cli::cli_alert_success("Pipeline finished: {pipeline$name %||% 'unnamed'}")
  if (exists("sync_all_block_pub_outputs_to_root", mode = "function")) {
    ctx <- sync_all_block_pub_outputs_to_root(ctx)
    # 删表后发表编号自动顺延（文件名 + xlsx/tex 内标题）；可用 config$pub$renumber = FALSE 关闭
    pub_cfg <- (config$pub %||% list())
    if (isTRUE(pub_cfg$renumber %||% TRUE) &&
        exists("pub_renumber_pub_dir", mode = "function")) {
      out_root <- ctx$root_output_dir %||% config$project$output_dir
      if (!is.null(out_root) && dir.exists(out_root)) {
        for (sub in c("Tables", "Figures")) {
          tryCatch(
            pub_renumber_pub_dir(file.path(out_root, sub)),
            error = function(e) cli::cli_alert_warning("编号重排失败[{sub}]: {e$message}")
          )
        }
      }
    }
  }
  if (exists("export_pub_figures", mode = "function") ||
      file.exists(file.path(root, "R/pub_figure_export.R"))) {
    if (!exists("export_pub_figures", mode = "function")) {
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    }
    out_root <- ctx$root_output_dir %||% config$project$output_dir
    figs <- file.path(out_root, "Figures")
    is_dual_slot <- pipeline_figures_is_dual_slot(figs, config)
    if (!isTRUE(is_dual_slot) && dir.exists(figs) && !dir.exists(file.path(figs, "pdf"))) {
      tryCatch(
        export_pub_figures(figs, meta = list(
          exposure = config$project$exposure_var %||% config$project$index_var %||% "",
          outcome = config$data$outcome_column %||% "",
          databases = config$project$database %||% character(0),
          combined = FALSE
        ), config = config),
        error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
      )
    }
  }
  invisible(ctx)
}
