###############################################################################
# config_trajectory_incidence_joint.template.R
# 「轨迹发病」套路（Joint Trajectory Incidence）—— 已定稿模板
#
# 套路名: 轨迹发病（GBMTM 双指标联合纵向轨迹 → 新发结局序贯 Cox）
# 对标文献: Liu et al. Cardiovasc Diabetol 2026;25:207 (PMID 串 13393250 课题)
# 验证跑通: ELSA Wave 2-9, N=2,849, TyG×BMI / TyG×WHtR 双体系 K=4, 2026-11
#
# 引擎链 Blocks/82_trajectory_incidence_joint:
#   01 tj_data_ingest -> 02 tj_gbmtm_fit -> imputation -> 03 tj_cox_rubin
#   -> 04 tj_subgroup -> 05 tj_sensitivity -> 06 tj_pub_export
# 入口: run/trajectory_incidence/run_trajectory_incidence_joint.R
# 指标预检: run/trajectory_incidence/screen_trajectory_joint_index_pool.R
#
# 换项目只需改本文件：疾病 / 数据库 / 指标体系(index_pairs) / 波次 / 协变量集 / 结局列
# 铁律联动：
#   - mi_m5_rubin_pool：推断 Cox/亚组/敏感性 m>=5 + Rubin（本套定稿对标文献用 m=20）
#   - index_pool_screening：index_pairs 必须先过「指标筛选门控」落盘再写 config
#   - disease_component_hard_exclusion：疾病泄漏变量不入协变量池
#   - attrition_consort_flowchart：Fig1 诚实分项（年龄 + 指标成分缺失 n）
#   - pub_three_line_table_gate：三线表 + 表注在表头之上（06 pub_export 收口）
#   - pub_times_new_roman / pub_no_underscore_display：交付字体与展示名
###############################################################################

.block_repo_root <- {
  env <- Sys.getenv("BLOCK_REPO_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else "E:/01block/01Block-new-Final"
}
.block_result_root <- {
  env <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(env) && dir.exists(env)) env
  else if (dir.exists("G:/02block_result")) "G:/02block_result"
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}

# ── 项目定位（换项目改这里）────────────────────────────────────────────
.project_root <- file.path(.block_result_root, "56_CVD", "incidence_trajectory_joint")
.raw_rds      <- file.path(.project_root, "data", "master_wide.rds")  # 多波宽表（含各成分 <comp>_w<k>）
.raw_obj      <- "master"                                            # rds 内对象名

config <- list(
  project = list(
    name = "CVD_Joint_Trajectory_Incidence",
    disease = "cvd",
    disease_code = "56",
    study_type = "incidence",
    literature_pmid = "13393250",        # 对标文献索引；换文献改此
    database = "ELSA",                   # 单库；换库改此
    root = .block_repo_root,
    output_dir = file.path(.project_root, "Output")
  ),

  data = list(
    rawdata_path = .raw_rds,
    rawdata_obj  = .raw_obj,
    id_column    = "id"
  ),

  # ── 多重插补（mi_m5_rubin_pool；定稿对标文献 m=20，引擎铁律 m>=5）───────
  imputation = list(
    enable = TRUE,
    method = "mice",
    m = 20L,                 # 定稿口径 = Liu 2026 m=20；最低可降 5L（铁律）
    maxit = 20L,
    seed = 42L,
    fit_on = "all",          # 轨迹定类锁全样本；协变量插补可改 "train" 视设计
    rubin_pool = TRUE,       # 推断 Cox/亚组/敏感性跨 m 套 Rubin 合并
    complete_action = 1L     # 仅操作层（Table1/KM/画图）；推断走 Rubin
  ),

  # ── 轨迹发病核心配置 ──────────────────────────────────────────────────
  joint_trajectory = list(
    id_column = "id",
    waves = c(2, 4, 6),                # 轨迹测量波（对照文献随访波次）
    wave_suffix = "_w",
    recompute_indices = TRUE,          # 用 00_index 公式按波重算；master 已含 <IX>_w<k> 列时置 FALSE
    age_filter = "age >= 50",          # 人群门控（依据文献纳排；换病种必查并注释）

    # 指标体系：每个体系 = 一联合轨迹对（多指标课题默认多对，逐对出图）
    # ⚠ 须先过「指标筛选门控」(index_pool_screening)：
    #   1) 组成 ∈ 复合指标库真公式（configs/indices/composite_index_vars.R），
    #      禁止裸原始单列当轴；2) 检索本病×本指标轨迹预后文献落盘
    #      reports/tst_feature_lit_*（或等价）；3) 各波均可算；4) 用户确认名单。
    index_pairs = list(
      BMI_TyG  = c("TyG", "BMI"),
      WHtR_TyG = c("TyG", "WHtR")
    ),
    group_col_prefix = "grp_",

    # GBMTM 参数（内核 R/gbmtm_core.R：gbmtm_select）
    # 选 K 六项标准（文献口径，缺一不可写进 Table S4 表注）：
    #   BIC、AIC、entropy、AvePP>=0.80、OCC、最小类占比>=5% + 临床可解释性。
    #   大队列 AIC/BIC 常单调下降无低谷 —— 此时【禁止】naive 取最低点，
    #   按质量标准否决 K>=5 退化解，锁文献一致 K 并如实披露（见 force_K_by_system）。
    k_range = 2:6,
    poly_degree = 2L,
    n_start = 10L,
    seed = 42L,
    force_K = NULL,                    # NULL = 数据驱动（AIC/BIC + AvePP>=0.70 + 最小类>=5%）
    force_K_by_system = list(),        # 定稿对标 Liu 2026 用 list(BMI_TyG = 4L, WHtR_TyG = 4L)
    avepp_min = 0.70,                  # 质量门槛（定稿实际各类 AvePP 0.881 >= 0.80）
    min_prop_floor = 0.05,             # 最小类占比 >= 5%；锁 K 后 <5% 须 Methods/Limitations 披露

    # 基线现患剔除（结局定义相关诊断，防 prevalence 混入 incidence）
    prevalent_exclude = list(cvd0 = c("angina", "mi", "hf", "arry", "stroke")),

    # 结局列（须由独立结局步预生成到 master：新发 event 0/1 + 中点随访 time_m；
    #  区间删失口径 = 末次无事件访视与事件访视的中点，Methods 写实）
    exclude_first_years = 2,
    outcome = list(
      primary = list(name = "cvd", event_col = "cvd_event", time_col = "cvd_time_m",
                     # S8 区间删失窗来源：随访波访谈月（相对基线 0）。缺列时 S8 自动回退
                     # ±sensitivity$interval_half_months 等宽窗（表注/日志写明，不冒充访视窗）。
                     visit_time_cols = c("tvisit_w3", "tvisit_w5", "tvisit_w6",
                                         "tvisit_w7", "tvisit_w8", "tvisit_w9")),
      secondaries = list(
        list(name = "heart",  event_col = "heart_event",  time_col = "heart_time_m"),
        list(name = "stroke", event_col = "stroke_event", time_col = "stroke_time_m")
      )
    ),

    # 竞争风险（Fine-Gray）：enable=TRUE 时 pipeline 追加 tj_finegray_rubin。
    # 要求 master 有 0/1 死亡事件列（death_event_col）；有死亡时间列更佳
    # （death_time_col，月；缺则竞争事件沿用结局 time，Methods 须如实说明）。
    # fstatus: 主事件=cause(1) / 死亡=death_cause(2) / 其余=删失 cencode(0)。
    # 竞争事件语义（文献敏感性②= non-CVD death，Table 4 脚注自动写明所用口径）：
    #   a) master 有死因列 -> main_cause_regex 匹配主结局死因，其余死亡=竞争（严格复现）；
    #   b) 无死因列 -> 默认「未报告主结局事件的死亡」近似 non-CVD death（引擎自证计数）；
    #   c) competing_is_all_cause=TRUE -> 明示全因死亡（禁止用于复现敏感性②却不自知）。
    competing_risk = list(
      enable = FALSE,                 # <TO_CONFIRM> 竞争风险版置 TRUE
      cause = 1L, cencode = 0L, death_cause = 2L,
      death_event_col = "death_event",
      death_time_col  = "death_time_m",
      death_cause_icd_col = NULL,     # 如 "death_icd_chapter"；NULL=无语义口径 b
      main_cause_regex = NULL,        # 如 "^I0|^I1|^I2|^I6"（主结局=心脑血管死因）
      competing_is_all_cause = FALSE
    ),

    # 序贯 Cox 协变量集（文献四段式 Model 1–4；换病种须裁剪成分/泄漏变量）
    # 定稿 Model 4 = Model 3 + 降压/降糖/胰岛素/降脂药 + FVC
    model_sets = list(
      model1 = c("age", "sex", "race_white", "edu"),
      model2 = c("age", "sex", "race_white", "edu", "smoke", "drink"),
      model3 = c("age", "sex", "race_white", "edu", "smoke", "drink",
                 "hbp_d", "dm_d", "chol_d"),
      model4 = c("age", "sex", "race_white", "edu", "smoke", "drink",
                 "hbp_d", "dm_d", "chol_d", "bpmed", "dmmed", "insulin",
                 "lipid_med", "fvc")
    ),

    subgroup = list(
      vars = c("Age_Group", "Sex_lbl", "Edu_Group", "DM_lbl", "HBP_lbl", "Smoke_lbl"),
      age_cutoff = 65L,                 # 年龄亚组二分类切点（病种文献依据；age_subgroup_binary）
      model = "model4",
      min_events = 15L,                 # 层内事件 < 15 → NE（图注/表注写明）
      p_interaction = TRUE              # 轨迹 x 分层 LRT 交互 P（Rubin 跨套合并）
    ),

    sensitivity = list(
      model = "model4",
      # 文献九项全实现（Liu 2026 Supplement）：
      #   S8_cloglog_interval 需 outcome$primary$visit_time_cols（各随访波访谈月）；
      #   缺访视列时自动回退 ±interval_half_months 等宽窗（定稿 Weibull 口径，日志/表注写明）。
      #   S10_cross_class = 体系两成分基线波中位数四格 Cox（参照=双低）。
      #   p_bh 列 = 跨轨迹组 Benjamini–Hochberg FDR（文献正文口径）。
      visit_cols = NULL,                  # NULL -> 读 outcome$primary$visit_time_cols
      interval_half_months = 24L,         # 双年度随访 -> ±24 月窗
      items = c("S0_main", "S1_exclude_first2y", "S3_exclude_DM", "S4_exclude_HBP",
                "S5_complete_case", "S6_exclude_glucose_lipid_med", "S7_PP_weighted",
                "S8_cloglog_interval",
                "S9a_linear_time", "S9b_cubic_time", "S10_cross_class")
    ),

    # 判别增量（定稿 Table S8：ΔC-index Harrell / 连续 NRI / IDI@60,120 月；
    #  100 permutations + 三层 bootstrap，Rubin m 套合并。引擎 06 块含则自动，
    #  否则按定稿课题 discrimination_phase8 脚本补跑并在 Methods 写实现）
    discrimination = list(
      enable = TRUE,
      base_model = "model4",
      horizons_months = c(60L, 120L),
      n_boot = 200L, seed = 42L
    ),

    pub = list(
      delivery_root = NULL,             # NULL -> <Output>/summary_results
      table1_cont = NULL,               # NULL -> 自动探测
      table1_cat  = NULL,
      fig3_lock_note = TRUE             # A/B 面板标 "K locked per reference; see Table S4"
    )
  ),

  # 疾病成分/泄漏硬排除（disease_component_hard_exclusion；换病种逐列重审 Data/_column_review.md）
  analysis_exclusion = list(
    disease_vars = c("hbp_d", "dm_d", "insulin", "bpmed", "dmmed"),  # 视课题
    exclude_exposure_if_uses_disease_var = FALSE                      # 暴露即指标成分本身
  ),

  # 小数位 / 字体（pub_digits_consistency / pub_times_new_roman）
  pub_digits = list(est = 3L, p = 3L, desc = 3L, cutoff = 3L,
                    int_big_mark = TRUE, desc_trim = TRUE, p_style = "fixed"),
  pub_figures = list(export_png = FALSE, export_tiff = FALSE, require_vector_pdf = TRUE)
)

# ── 执行链（run_pipeline 的 pipeline$blocks）──────────────────────────
# 顺序铁律：轨迹定类(操作层锁全样本) -> MICE(仅补 Cox 协变量) -> 推断(Rubin)。
#   tj_gbmtm_fit 在 imputation 之前跑，类别列 grp_* 一旦写死便不参与插补；
#   tj_cox_rubin/subgroup/sensitivity 经 mi_complete_aligned(keep_vars=类别/结局) 取每套 complete。
pipeline <- list(
  blocks = c("tj_data_ingest", "tj_gbmtm_fit", "imputation", "tj_cox_rubin",
             "tj_subgroup", "tj_sensitivity", "tj_pub_export")
)
# 竞争风险版：enable=TRUE 时在推断链插入 tj_finegray_rubin（Rubin m 套 crr 合并）
if (isTRUE(config$joint_trajectory$competing_risk$enable)) {
  pipeline$blocks <- append(pipeline$blocks, "tj_finegray_rubin",
                            after = match("tj_cox_rubin", pipeline$blocks))
}

# 类别列 / 结局事件时间 / 波次成分不作为 MICE 插补目标（只作预测因子或纯标签）
config$imputation$exclude_from_mice_cols <- c(
  paste0("grp_", names(config$joint_trajectory$index_pairs)),
  ".tj_row_id",
  unlist(lapply(c(list(config$joint_trajectory$outcome$primary),
                  config$joint_trajectory$outcome$secondaries %||% list()),
                function(o) c(o$event_col, o$time_col))),
  # 竞争风险：死亡事件/时间不进插补目标（事件标签不可插补，铁律同结局列）
  local({ cr <- config$joint_trajectory$competing_risk %||% list()
          c(cr$death_event_col %||% "death_event", cr$death_time_col %||% character(0)) })
)
# 轨迹成分波次列（TyG_w2…）保留为预测因子，不作删列/整列剔除
config$imputation$force_keep_columns <- unique(c(
  config$imputation$force_keep_columns %||% character(0),
  ".tj_row_id"))

# 纳排诚实分项（attrition_consort_flowchart §8）：年龄 + 指标成分必出框
config$attrition <- list(
  outcome_breakdown = TRUE,
  config_steps_only = TRUE,
  steps = list(
    list(id = "q_start",  label = "Study baseline participants", kind = "include"),
    list(id = "q_age",    label = "Age >= 50",                   kind = "exclude"),
    list(id = "q_index",  label = "Joint trajectory indices computable", kind = "exclude"),
    list(id = "q_prev",   label = "Prevalent CVD at baseline",   kind = "exclude"),
    list(id = "q_final",  label = "Analytic cohort",             kind = "include")
  )
)

# ── 新课题检查清单（定稿「轨迹发病」出厂前逐项勾）─────────────────────
# [ ] 指标筛选门控已过：index_pairs 全为复合指标库真公式 + 检索落盘 + 用户确认
# [ ] age_filter / prevalent_exclude / disease_vars 有本病文献依据注释（非照抄 CVD）
# [ ] imputation: m>=5 且 rubin_pool=TRUE；类别/结局列不入插补目标
# [ ] 选 K：六项标准全披露（Table S4 表注）；锁 K 时 S4/Methods/Limitations 写明
#       本队列 AIC/BIC 无低谷、按文献标准定 K（禁止 naive which.min）
# [ ] 敏感性 10 项含 PP 加权与（若做）Weibull AFT 时间比口径注释
# [ ] 亚组 min_events 门槛 -> NE；P-interaction 有；分层模型剔除分层变量同伴
# [ ] 发表：Table 2/3 Category 列 + Overall 前置 + SMD；三线表表注在表头之上；
#       A1 = 文件名；Fig3 A/B 双曲线 + 锁定注；C/D 双轴 + 线型图例；Times 系
# [ ] 收口链：结构 QC -> nature-statistics + nature-figure P0 清零 -> 中期 PDF -> prune 白名单
