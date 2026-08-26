###############################################################################
#  config_burden_gbd.template.R — GBD 二次数据【全球负担描述】通用模板
#  源自 paper_005（EO-IBD, Chen et al. Gut and Liver 2026, PMID 40910275）抽取：
#    数据导入 → 列映射 → 年龄标化 → Joinpoint 趋势 → BAPC 投影
#    → 分层描述率（age/sex/SDI/region）→ SII/CI 不平等 → 地理排名
#  source 后得到: config, pipeline
#  用法: 由 run_burden_gbd.R 加载
#
#  ⚠️ 这是【研究型通用模板】，含占位符；论文级可运行实例须经 wizard 交互门：
#     数据探查（读 Data/）→ 决策树确认 → 试跑确认，再回填下方 ❓ 占位符。
#  ⚠️ 库内尚无 burden/GBD 专用 block；GAP1–GAP8 以 TODO 注释占位，
#     建成并注册于 R/pipeline_runner.R 前不得放入 pipeline$blocks。
#  ⚠️ 库内 index$SII = 炎症复合指标，≠ 健康不平等 Slope Index of Inequality。
#  ⚠️ D04_dabiao（MIMIC 个体宽表）与本模板不兼容；须 GBD 面板/长表率数据。
###############################################################################

config <- list(
  data = list(
    rawdata_path     = "Data/gbd/<TO_CONFIRM>.RData",              # ❓ GBD 面板/长表
    rawdata_obj      = "<TO_CONFIRM>",                              # ❓
    outcome_path     = NULL,
    outcome_column   = NULL,                                        # 负担研究无二元个体结局
    id_column        = "<location_id>",                             # ❓ 国/地区或 location 键
    strip_id_columns_after_imputation = character(0)
  ),

  project = list(
    name                = "burden_gbd",
    disease             = "<TO_CONFIRM>",                           # ❓ 用户确认疾病名
    database            = "GBD",
    study_type          = "burden",                                 # 库内新语义（无现成 block 变体）
    classification_mode = "rate_panel",
    analysis_group      = NULL,
    reference_group     = NULL,
    output_dir          = "Output/<TO_CONFIRM>",                    # ❓
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix  = "step",
    mirror_pub_outputs_to_root = TRUE                               # ❓ 须 wizard 确认 TRUE/FALSE
  ),

  gbd = list(
    age_cutoff           = "<TO_CONFIRM>",                          # ❓ 如 20（纳入阈值，非分组变量）
    metrics              = c("<incidence>", "<prevalence>", "<mortality>", "<dalys>"),  # ❓ 四指标列名
    standard_population  = "GBD2021",                               # 年龄标化权重来源
    age_interval_years   = 5L,
    strata_vars          = c("age_group", "sex", "sdi_quintile", "gbd_region", "country"),
    sdi_temporal         = TRUE,                                    # N22：SDI quintile 成员时变
    year_range           = c(1990L, 2021L),
    projection_end_year  = 2036L,
    subtype_stratify     = "none",                                  # N19：UC vs Crohn 未分析
    include_proportion_reference = FALSE                            # GAP5 Supp Fig 2；可选
  ),

  plot = list(
    font_family = "Times New Roman"
  ),

  data_clean = list(
    missing_threshold = 0.3,
    age_filter        = NULL,                                       # 由 gbd$age_cutoff 在 block 内处理
    drop_columns      = NULL
  ),

  column_mapping = list(
    enable        = TRUE,
    database_type = "GBD"                                           # ❓ 可能需扩展 column_mapping block
  ),

  # ── GAP1：年龄标化（Methods §5）──
  # age_standardization_burden = list(
  #   metrics = NULL,                                               # 默认 gbd$metrics
  #   standard_population = "GBD2021"
  # ),

  # ── GAP2：Joinpoint 趋势（Results §1）──
  # joinpoint_trend = list(
  #   metrics = NULL,
  #   joinpoint_software = "NCI_5.1.0.0",
  #   alpha = 0.05,
  #   report_full_segments = TRUE                                   # N26：补 K 未披露
  # ),

  # ── GAP3：BAPC 投影（Results §2）──
  # bapc_projection = list(
  #   metrics = NULL,
  #   forecast_years = c(2022L, 2036L),
  #   causal_claim = FALSE                                          # N17：外推非因果
  # ),

  # ── GAP4：分层描述率（Results §3–§4）──
  # descriptive_stratified_rates_gbd = list(
  #   stratify_by = c("age_group", "sex", "sdi_quintile", "gbd_region"),
  #   report_aapc = TRUE
  # ),

  # ── GAP5：占全病比例参照（Supp Fig 2；可选）──
  # proportion_reference = list(
  #   denominator_condition = "<ALL_IBD>",
  #   metrics = NULL
  # ),

  # ── GAP6/GAP7：健康不平等（Results §4）──
  # health_inequality_sii = list(
  #   gradient_var = "sdi",
  #   linear_sii = TRUE,
  #   concentration_index = TRUE,
  #   allow_nonlinear_dalys = FALSE                                  # GAP7：U 形扩展待建
  # ),

  # ── GAP8：地理排名（Results §5）──
  # geographic_burden_rank = list(
  #   level = c("country", "gbd_region"),
  #   top_n = 10L,
  #   map_metric = "<incidence>"
  # )
)

pipeline <- list(
  blocks = c(
    "data_clean",
    "column_mapping"
    # TODO(GAP1): "age_standardization_burden",
    # TODO(GAP2): "joinpoint_trend",
    # TODO(GAP3): "bapc_projection",
    # TODO(GAP4): "descriptive_stratified_rates_gbd",
    # TODO(GAP5): "proportion_reference",
    # TODO(GAP6): "health_inequality_sii",
    # TODO(GAP8): "geographic_burden_rank"
  ),
  checkpoint = list(
    dir = "checkpoints/<TO_CONFIRM>"                                # ❓
  )
)
