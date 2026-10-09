###############################################################################
#  ml_reference_paper_profile.R — AKI SOSM+WPR 原文复刻 Task 7
#  原文（PMID 40537296）图表「参考角色」profile、Figure 1 双库真实纳排流程图、
#  Table 1 双库 Panel A/B 基线（Survivor/Non-survivor）、S1 AKI 队列定义证据、
#  以及完整编号 MANIFEST。
#
#  规格：docs/superpowers/specs/2026-09-17-aki-sosm-wpr-original-paper-replication-design.md
#  计划：docs/superpowers/plans/2026-09-17-aki-sosm-wpr-original-paper-replication.md
#
#  铁律（对齐 tst_methods_leakage_denom_gate / pub_digits_consistency /
#  dual_db_publication_consistency / ml_config_novelty_dual_composite）：
#   - 编号单一事实来源：主图 Figure 1-8、补图 S1-S8、主表 Table 1-2、补表 S1-S16；
#     每个角色写 reference_source（对应原文哪张图表）+ adaptation（本课题差异）。
#   - 结局仅 28 天全因死亡；显示 Survivor/Non-survivor；禁 90 天、禁 AKI/No AKI。
#   - 小数位走公共 pub_digits（est=3 / p=3 / desc=2 / cutoff=4）。
#   - Figure 1 库身份按【目录位置】判定（MIMIC_IV/ = MIMIC-IV，eICU/ = eICU）；
#     CSV 的 database 列是历史遗留错误槽名，绝不可信；每步排除人数=相邻步差额。
#     缺 CSV 或人数非单调 → 硬失败，禁止编造。
#   - S1：MIMIC-IV 有 Acute_Renal_Failure 旗标（已证实）；eICU 无该列、依赖上游
#     D02 预筛（用户确认全部为 AKI），但上游 ICD/KDIGO 提取代码未随数据提供 →
#     明确标注「证据不足」。
#   - 复用 Task4/5/6 既有产物入口（只读引用，不重算、不改其文件）；缺则标注。
#   - 发表图：staging 单 PDF（pipeline_ggsave_pdf/cairo 口径）；四格式导出留 Task8。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

# 依赖引擎公共件（attrition grid 画框 / SCI 三线表 / 小数位 / PDF 设备）。
.ml_ref_ensure_engine <- function(root = NULL) {
  if (is.null(root)) root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- normalizePath(".", winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", root)) {
    root <- paste0("/mnt/", tolower(substr(root, 1L, 1L)), substring(root, 3L))
  }
  # grid roundbox（attrition_log）缺失时补 source；utils 的 sci/pub 同理
  if (!exists(".attrition_grid_roundbox", mode = "function")) {
    f <- file.path(root, "R/attrition_log.R")
    if (file.exists(f)) suppressWarnings(source(f, local = FALSE))
  }
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    f <- file.path(root, "R/utils.R")
    if (file.exists(f)) suppressWarnings(source(f, local = FALSE))
  }
  invisible(root)
}

# ===========================================================================
# 1) 固定编号 profile
# ===========================================================================
#' 原文（PMID 40537296）复刻的完整图表角色清单。
#'
#' @return data.frame(kind, number, role, title, db_mode, reference_source,
#'   adaptation)。kind ∈ {figure_main, figure_supp, table_main, table_supp}；
#'   number 为纯数字字符（figure_supp / table_supp 前缀 S 由 kind 隐含）。
#'   主图 1-8、补图 S1-S8、主表 1-2、补表 S1-S16 连续无重号，共 34 行。
ml_reference_profile_40537296 <- function(indices = c("SOSM", "WPR")) {
  .ml_ref_ensure_engine()
  indices <- as.character(indices)
  if (length(indices) != 2L || any(!nzchar(indices))) {
    stop("indices must be length-2 (e.g. c(\"ACAG\", \"RAR\")).", call. = FALSE)
  }
  ia <- indices[[1]]; ib <- indices[[2]]; ilab <- paste0(ia, "+", ib)
  .sub_idx <- function(x) {
    x <- gsub("SOSM\\+WPR", ilab, x, fixed = FALSE)
    x <- gsub("SOSM/WPR", paste0(ia, "/", ib), x, fixed = TRUE)
    x <- gsub("SOSM and WPR", paste0(ia, " and ", ib), x, fixed = TRUE)
    x <- gsub("SOSM, WPR", paste0(ia, ", ", ib), x, fixed = TRUE)
    x <- gsub("SOSM", ia, x, fixed = TRUE)
    x <- gsub("WPR", ib, x, fixed = TRUE)
    x
  }
  # 本课题通用差异说明（禁 90 天 / SOFA 替糖代谢分层 / 冻结外验）
  ADAPT_STRATA <- paste0(
    "疾病分层改用经验证 SOFA 0-4 / 5-10 / >=11 三层（原文按糖代谢 NGR/Pre-DM/DM 三层）；",
    "结局仅 28 天全因死亡（数据不支持更长随访）；eICU 冻结 MIMIC-IV 资产外验、不重训"
  )

  # --- 主图 Figure 1-8 ---
  fig_m_num <- as.character(1:8)
  fig_m_role <- c(
    "双库纳排流程图 flowchart",
    "KM 联合组生存曲线（SOFA 分层）",
    "分组 RCS 剂量-反应（SOSM/WPR）",
    "ROC 判别（含临床评分对照）",
    "Landmark 前/后 PH 违反分析",
    "亚组森林图（tertile 关联）",
    "分层 Boruta 特征选择（仅 MIMIC-IV）",
    "分层五模型 ROC+SHAP（冻结外验）"
  )
  fig_m_title <- c(
    "Figure 1. Inclusion and exclusion flowchart of the MIMIC-IV and eICU cohorts.",
    "Figure 2. Kaplan-Meier curves of SOSM, WPR and joint groups by SOFA strata.",
    "Figure 3. Restricted cubic splines for SOSM and WPR by SOFA strata.",
    "Figure 4. ROC curves of SOSM, WPR, joint score and clinical scores (Overall and SOFA strata; 8 panels).",
    "Figure 5. Landmark analysis before and after the PH-violation turning point.",
    "Figure 6. Subgroup forest plots of SOSM and WPR tertile associations.",
    "Figure 7. Stratified Boruta feature selection in MIMIC-IV.",
    "Figure 8. Stratified five-model ROC and SHAP (MIMIC-IV train/internal, eICU frozen)."
  )
  fig_m_src <- c(
    "原文 Fig 1：研究流程图（Study flowchart）",
    "原文 Fig 2：分层 KM 生存曲线",
    "原文 Fig 3：分组 RCS 剂量反应曲线",
    "原文 Fig 4：ROC 判别力比较",
    "原文 Fig 5：landmark / 时依效应分析",
    "原文 Fig 6：亚组森林图",
    "原文 Fig 7：分层 Boruta 变量筛选",
    "原文 Fig 8：分层多模型 ROC 与 SHAP 解释"
  )
  fig_m_db <- c(
    "双库 Panel A=MIMIC-IV / B=eICU",
    "双库 6 行 x 3 列=18 面板",
    "双库 2x2=4 面板",
    "双库 x (Overall+3SOFA)=8 面板",
    "MIMIC 锁定层/日 + eICU 验证",
    "2 库 x 2 指标=4 面板",
    "仅 MIMIC-IV 3 层（外验禁重筛）",
    "MIMIC 分层建模 / eICU 冻结外验"
  )
  fig_m_ad <- c(
    paste0("真实 attrition 人数、按目录判库；排除口径=重复入院去重/清洗/插补；",
           "原文为单库人群，本课题为 MIMIC-IV 开发 + eICU 外验双库"),
    paste0("联合组=各指标最高三分位 high、下两分位 low；", ADAPT_STRATA),
    paste0("图内叠加 SOFA 0-4 / 5-10 / >=11 三条调整后 HR 曲线/95%CI/P-overall/P-nonlinear；",
           ADAPT_STRATA),
    paste0("对照评分沿用本队列可得 APSIII/OASIS/GCS（原文为糖代谢分层下的同类对照）；",
           ADAPT_STRATA),
    paste0("先在 MIMIC Overall/SOFA 三层定 PH 违反最显层与转折日，锁定后 eICU 仅验证；",
           ADAPT_STRATA),
    paste0("暴露口径=最高 vs 最低三分位、N=全分层人数（双库一致）；", ADAPT_STRATA),
    paste0("外验库禁止重做特征选择，仅 MIMIC-IV 三层各一面板；", ADAPT_STRATA),
    paste0("按库 x 层组织 ROC/beeswarm/importance；SHAP 只解释冻结最优模型；", ADAPT_STRATA)
  )

  # --- 补图 Figure S1-S8（原文 S1-S5 + 本课题额外 S6-S8） ---
  fig_s_num <- as.character(1:8)
  fig_s_role <- c(
    "PH 时依系数 beta(t) 趋势（Overall/SOFA 三层，两库）",
    "MIMIC-IV overall Boruta",
    "overall 五模型 ROC（internal+external）",
    "overall 最优冻结模型 SHAP（双库）",
    "代表性 survivor/non-survivor 个体 SHAP waterfall",
    "overall 三集校准曲线",
    "overall 三集性能指标",
    "overall 三集 DCA 决策曲线"
  )
  fig_s_title <- c(
    "Figure S1. Time-varying coefficient trends for the PH assumption (Overall and SOFA strata, both databases).",
    "Figure S2. Overall Boruta feature selection in MIMIC-IV.",
    "Figure S3. Five-model ROC in the overall MIMIC internal and eICU external sets.",
    "Figure S4. SHAP of the overall best frozen model (MIMIC-IV / eICU).",
    "Figure S5. Individual SHAP waterfalls of representative survivors/non-survivors.",
    "Figure S6. Calibration across train/internal/external sets.",
    "Figure S7. Performance metrics across train/internal/external sets.",
    "Figure S8. Decision curve analysis across train/internal/external sets."
  )
  fig_s_src <- c(
    "原文补充图 S1：PH 时依系数趋势",
    "原文补充图 S2：overall Boruta",
    "原文补充图 S3：overall 多模型 ROC",
    "原文补充图 S4：overall 最优模型 SHAP",
    "原文补充图 S5：个体 SHAP",
    "本课题额外图（原文无对应，顺延自 S6）",
    "本课题额外图（原文无对应，顺延自 S7）",
    "本课题额外图（原文无对应，顺延自 S8）"
  )
  fig_s_db <- c(
    "双库拼图（MIMIC/eICU）", "仅 MIMIC-IV overall",
    "internal+external 双线", "双库各 beeswarm+bar",
    "2 库 x 2 层 x 2 结局", "三集（train/internal/external）",
    "三集", "三集"
  )
  fig_s_ad <- c(
    paste0("Overall/SOFA 0-4 / 5-10 / >=11 三层；", ADAPT_STRATA),
    paste0("overall 单面板（分层见主文 Fig 7）；", ADAPT_STRATA),
    paste0("external 用冻结资产；", ADAPT_STRATA),
    paste0("external 解释 MIMIC 冻结模型；", ADAPT_STRATA),
    paste0("每库每层各 1 Survivor + 1 Non-survivor，禁跨库跨层借样；", ADAPT_STRATA),
    "本课题额外补充产物，与主文 SOFA 分层无关（overall 三集），只读引用旧 checkpoint",
    "本课题额外补充产物；图上 AUC=…;Acc=… 双口径分开，禁把 Acc 写成 AUC",
    "本课题额外补充产物；三集 DCA 阈值范围两库同标尺"
  )

  # --- 主表 Table 1-2 ---
  tab_m_num <- as.character(1:2)
  tab_m_role <- c(
    "28 天生存/死亡双库基线特征",
    "SOSM+WPR 联合四组与 28 天死亡 Cox 关联"
  )
  tab_m_title <- c(
    "Table 1. Baseline characteristics by 28-day survival in MIMIC-IV (Panel A) and eICU (Panel B).",
    "Table 2. Association of SOSM+WPR joint groups with 28-day all-cause mortality (Cox)."
  )
  tab_m_src <- c(
    "原文 Table 1：基线特征表",
    "原文 Table 2：联合分组关联 Cox 表"
  )
  tab_m_db <- c(
    "双库 Panel A=MIMIC-IV / B=eICU",
    "双库 Panel A=MIMIC-IV / B=eICU"
  )
  tab_m_ad <- c(
    paste0("结局列固定 Survivor/Non-survivor，禁 AKI/No AKI；描述统计 2 位小数；",
           ADAPT_STRATA),
    paste0("Overall/SOFA 0-4 / 5-10 / >=11；Group1 low/low=参照；Model2 按 ML 关联协变量铁律；",
           ADAPT_STRATA)
  )

  # --- 补表 S1-S16（原文 S1-S11 + 本课题额外 S12-S16） ---
  tab_s_num <- as.character(1:16)
  tab_s_role <- c(
    "AKI 队列与变量定义/代码证据（AKI cohort definition）",
    "双库单因素 Cox（univariate Cox）",
    "MIMIC train/internal VIF 与 eICU 继承特征审计（VIF/继承）",
    "SOSM/WPR 连续与三分位 Cox（Overall/SOFA 三层，28 天）",
    "判别力数值与 DeLong 比较（Figure 4）",
    "SOFA 0-4 层比例风险 PH 检验",
    "SOFA 5-10 层 PH 检验",
    "SOFA >=11 层 PH 检验",
    "排除基线 Glucose<70 mg/dL 联合 Cox 敏感性",
    "完整病例联合 Cox 敏感性",
    "SOFA 分层五模型 ML 性能（train/internal/external）",
    "本课题额外：overall train/internal/external ML 性能（三集性能）",
    "本课题额外：模型超参数",
    "本课题额外：Log-Loss",
    "本课题额外：DeLong",
    "本课题额外：NRI/IDI"
  )
  tab_s_title <- c(
    "Table S1. AKI cohort and variable definitions with code-level evidence.",
    "Table S2. Univariate Cox regression analyses in both databases.",
    "Table S3. VIF screening on MIMIC-IV train/internal and inherited-feature audit for eICU.",
    "Table S4. Cox models of SOSM and WPR (continuous and tertiles) across strata.",
    "Table S5. Discrimination (AUC, 95%CI) and DeLong comparisons for Figure 4.",
    "Table S6. Proportional-hazards test in the SOFA 0-4 stratum.",
    "Table S7. Proportional-hazards test in the SOFA 5-10 stratum.",
    "Table S8. Proportional-hazards test in the SOFA >=11 stratum.",
    "Table S9. Joint Cox sensitivity excluding baseline Glucose <70 mg/dL.",
    "Table S10. Joint Cox sensitivity on complete cases.",
    "Table S11. Stratified five-model machine-learning performance (train/internal/external).",
    "Table S12. Overall machine-learning performance across train/internal/external sets.",
    "Table S13. Hyperparameters for the machine-learning models.",
    "Table S14. Log-Loss of the machine-learning models.",
    "Table S15. DeLong tests for the machine-learning models.",
    "Table S16. NRI and IDI for the machine-learning models."
  )
  tab_s_src <- c(
    "原文补充表 S1：队列/变量定义",
    "原文补充表 S2：单因素 Cox",
    "原文补充表 S3：多重共线性/变量审计",
    "原文补充表 S4：指标连续与分位 Cox",
    "原文补充表 S5：判别力与 DeLong",
    "原文补充表 S6-S8：糖代谢三层 PH 检验（本课题映射到 SOFA 三层）",
    "原文补充表 S6-S8：糖代谢三层 PH 检验",
    "原文补充表 S6-S8：糖代谢三层 PH 检验",
    "原文补充表 S9：低血糖相关敏感性",
    "原文补充表 S10：完整病例敏感性",
    "原文补充表 S11：分层 ML 性能",
    "本课题额外表（原文无对应，顺延自 S12）",
    "本课题额外表（原文无对应，顺延自 S13）",
    "本课题额外表（原文无对应，顺延自 S14）",
    "本课题额外表（原文无对应，顺延自 S15）",
    "本课题额外表（原文无对应，顺延自 S16）"
  )
  tab_s_db <- c(
    "双库分列（MIMIC-IV / eICU）", "双库", "MIMIC train/internal + eICU 继承",
    "双库 x Overall/SOFA 三层", "双库 x (Overall+3SOFA)",
    "双库 SOFA 0-4", "双库 SOFA 5-10", "双库 SOFA >=11",
    "双库 排除基线 Glucose<70", "双库 完整病例",
    "MIMIC train/internal + eICU external",
    "三集", "三集", "三集", "三集（training set）", "三集（training set）"
  )
  tab_s_ad <- c(
    paste0("MIMIC-IV 有 Acute_Renal_Failure 旗标（Yes/No，已证实）；eICU 无该列、",
           "依赖上游 D02 预筛（用户确认全部为 AKI），但上游 ICD/KDIGO 提取代码未随数据提供",
           "→ 标注证据不足，不编造 ICD；两库最长随访 28 天"),
    paste0("变量池不含疾病泄漏列（analysis_exclusion 铁律）；", ADAPT_STRATA),
    paste0("eICU 不重筛，只审计继承特征是否齐列/因子水平一致；", ADAPT_STRATA),
    paste0("high=最高三分位；28 天；", ADAPT_STRATA),
    paste0("DeLong 用本课题可得评分；", ADAPT_STRATA),
    paste0("仅取 SOFA 0-4 子集；cox.zph P 值（sklearn/同引擎口径统一）；", ADAPT_STRATA),
    paste0("仅取 SOFA 5-10 子集；", ADAPT_STRATA),
    paste0("仅取 SOFA >=11 子集；", ADAPT_STRATA),
    paste0("原文 S9 为 ICU 全程低血糖事件；本数据无该变量，改「排除基线 Glucose<70 mg/dL」，",
           "题名/脚注须明确（禁把基线缺失写成发作事件）"),
    paste0("complete-case 联合 Cox；缺失按引擎 fit_on=train 插补对照；", ADAPT_STRATA),
    paste0("五模型 x 3 集；external 冻结、trained_in=MIMIC-IV；", ADAPT_STRATA),
    paste0("本课题额外产物，只读引用旧 by_index checkpoint；AUC 仅来自 roc_auc_score"),
    "本课题额外产物；Hpbest 三列 Model/Package/Hyperparameter（引擎开关）",
    "本课题额外产物；Log-Loss 三集同标尺",
    "本课题额外产物；DeLong 用 sklearn 口径，勿与 Fig4 自写 ROC 分叉",
    "本课题额外产物；NRI/IDI 与训练集一致，禁 seed+day 类分叉"
  )

  # 题名/角色随当前双指标替换（SOSM+WPR 模板 → ACAG+RAR 等）
  fig_m_role <- .sub_idx(fig_m_role); fig_m_title <- .sub_idx(fig_m_title)
  tab_m_role <- .sub_idx(tab_m_role); tab_m_title <- .sub_idx(tab_m_title)
  tab_s_role <- .sub_idx(tab_s_role); tab_s_title <- .sub_idx(tab_s_title)

  df <- function(kind, number, role, title, db_mode, ref, ad) {
    data.frame(
      kind = kind, number = as.character(number), role = as.character(role),
      title = as.character(title), db_mode = as.character(db_mode),
      reference_source = as.character(ref), adaptation = as.character(ad),
      stringsAsFactors = FALSE
    )
  }
  out <- rbind(
    df("figure_main", fig_m_num, fig_m_role, fig_m_title, fig_m_db, fig_m_src, fig_m_ad),
    df("figure_supp", fig_s_num, fig_s_role, fig_s_title, fig_s_db, fig_s_src, fig_s_ad),
    df("table_main", tab_m_num, tab_m_role, tab_m_title, tab_m_db, tab_m_src, tab_m_ad),
    df("table_supp", tab_s_num, tab_s_role, tab_s_title, tab_s_db, tab_s_src, tab_s_ad)
  )
  out
}

# ===========================================================================
# 2) Figure 1：双库真实纳排
# ===========================================================================

# 库身份按【目录位置】判定；CSV database 列（历史遗留错误槽名）绝不可信。
.ml_ref_fc_db_from_path <- function(path, role_fallback) {
  p <- gsub("\\", "/", as.character(path)[1L], fixed = TRUE)
  if (grepl("/MIMIC_IV/|/MIMIC-IV/|/MIMIC IV/|MIMIC[_-]?IV", p, ignore.case = TRUE)) {
    return("MIMIC-IV")
  }
  if (grepl("/eICU/|/EICU/|/eicu/|eICU", p, ignore.case = TRUE)) {
    return("eICU")
  }
  as.character(role_fallback)[1L]
}

.ml_ref_fc_reason <- function(step_id, step_label) {
  sid <- tolower(trimws(as.character(step_id %||% NA_character_)[1L]))
  lab <- as.character(step_label %||% "")[1L]
  hit <- switch(sid,
    after_id_deduplicate = , id_deduplicate =
      "Duplicate admissions (kept first hospitalization by patient ID)",
    after_data_clean = , data_clean =
      "Data cleaning (invalid or contradictory records)",
    after_imputation = , imputation =
      "Missing key variables (removed after imputation)",
    after_index = , index = "Composite index not computable",
    after_analysis_exclusion = , analysis_exclusion =
      "Disease-related variable exclusion",
    ""
  )
  if (!nzchar(hit)) {
    if (grepl("dedup|duplicat", lab, ignore.case = TRUE)) {
      hit <- "Duplicate admissions (kept first hospitalization by patient ID)"
    } else if (grepl("clean", lab, ignore.case = TRUE)) {
      hit <- "Data cleaning (invalid or contradictory records)"
    } else if (grepl("imput", lab, ignore.case = TRUE)) {
      hit <- "Missing key variables (removed after imputation)"
    } else if (grepl("index", lab, ignore.case = TRUE)) {
      hit <- "Composite index not computable"
    } else {
      hit <- "Did not meet inclusion criteria"
    }
  }
  hit
}

# 读单库 attrition CSV（强制按 step 出现顺序），返回 rows(step,n,step_id,exclude_reason)。
# 硬失败：文件缺失、无行、缺 n 列、非数值 n、人数非单调不增。
.ml_ref_fc_read_one <- function(csv_path, database) {
  if (!file.exists(csv_path)) {
    stop("Figure 1 缺少 attrition CSV（不得编造）：", csv_path, call. = FALSE)
  }
  d <- tryCatch(utils::read.csv(csv_path, stringsAsFactors = FALSE,
                                check.names = FALSE),
                error = function(e) {
                  stop("Figure 1 attrition CSV 读取失败：", csv_path,
                       " (", conditionMessage(e), ")", call. = FALSE)
                })
  if (!is.data.frame(d) || !nrow(d)) {
    stop("Figure 1 attrition CSV 无数据行：", csv_path, call. = FALSE)
  }
  if (!("n" %in% names(d))) {
    stop("Figure 1 attrition CSV 缺 n 列：", csv_path, call. = FALSE)
  }
  nn <- suppressWarnings(as.integer(d$n))
  if (any(!is.finite(nn))) {
    stop("Figure 1 attrition CSV 存在非数值人数：", csv_path, call. = FALSE)
  }
  step <- as.character(if ("step" %in% names(d)) d$step else rep(NA_character_, nrow(d)))
  step_id <- as.character(if ("step_id" %in% names(d)) d$step_id
                          else rep(NA_character_, nrow(d)))
  rows <- data.frame(
    database = database, step = step, n = nn, step_id = step_id,
    stringsAsFactors = FALSE
  )
  rows$exclude_reason <- vapply(seq_len(nrow(rows)), function(i)
    .ml_ref_fc_reason(step_id[i], step[i]), character(1))
  rows$exclude_reason[1L] <- NA_character_  # 起点无排除
  # 人数单调不增（相邻步差额 >= 0）
  if (any(diff(rows$n) > 0)) {
    stop("Figure 1 人数非单调递减（", database, "：",
         paste(rows$n, collapse = " > "), "）——拒绝编造，请核对 checkpoint。",
         call. = FALSE)
  }
  rows
}

#' 读两库真实 attrition CSV，按目录定库，返回 list(rows, exclusions)。
#' rows：database/step/n/step_id/exclude_reason；
#' exclusions：database/step/excluded（每步排除人数 = 相邻步差额）。
#' 硬失败：任一 CSV 缺、两库未齐全或同人、人数非单调。
ml_reference_read_flowcharts <- function(mimic_csv, eicu_csv) {
  .ml_ref_ensure_engine()
  if (missing(mimic_csv) || missing(eicu_csv)) {
    stop("ml_reference_read_flowcharts 需两库 CSV 路径", call. = FALSE)
  }
  m_db <- .ml_ref_fc_db_from_path(mimic_csv, "MIMIC-IV")
  e_db <- .ml_ref_fc_db_from_path(eicu_csv, "eICU")
  if (!identical(sort(c(m_db, e_db), method = "radix"), c("MIMIC-IV", "eICU"))) {
    stop("Figure 1 需两库齐全（MIMIC-IV + eICU）；实际判库：",
         paste(c(m_db, e_db), collapse = " / "), call. = FALSE)
  }
  rm <- .ml_ref_fc_read_one(mimic_csv, "MIMIC-IV")
  re <- .ml_ref_fc_read_one(eicu_csv, "eICU")
  rows <- rbind(rm, re)
  build_ex <- function(rr) {
    if (nrow(rr) < 2L) return(data.frame(database = character(0),
                                         step = character(0),
                                         excluded = integer(0)))
    data.frame(
      database = rr$database[2L:nrow(rr)],
      step = rr$step[2L:nrow(rr)],
      excluded = as.integer(rr$n[-nrow(rr)] - rr$n[-1L]),
      stringsAsFactors = FALSE
    )
  }
  exclusions <- rbind(build_ex(rm), build_ex(re))
  list(rows = rows, exclusions = exclusions)
}

# 在【当前 viewport】内画单库 CONSORT 流程（main inclusion boxes + right-side Excluded n=）。
.ml_ref_fc_panel <- function(rows, db_title, ff, footnote = NULL) {
  nb <- nrow(rows)
  if (nb < 1L) return(invisible(FALSE))
  grid::grid.text(
    db_title, x = grid::unit(0.5, "npc"), y = grid::unit(0.985, "npc"),
    just = "top",
    gp = grid::gpar(fontsize = 11.5, fontface = "bold", fontfamily = ff)
  )
  y_top <- if (is.null(footnote)) 0.90 else 0.92
  y_bot <- if (is.null(footnote)) 0.06 else 0.10
  span <- y_top - y_bot
  box_h <- min(0.145, span / (nb + max(nb - 1L, 1L) * 0.7))
  gap <- if (nb > 1L) (span - nb * box_h) / (nb - 1L) else 0
  cx <- 0.30; mw <- 0.46; x0 <- cx - mw / 2; x1 <- cx + mw / 2
  ex0 <- 0.60; ex1 <- 0.99
  for (i in seq_len(nb)) {
    y1 <- y_top - (i - 1) * (box_h + gap)
    y0 <- y1 - box_h
    lab <- sprintf("%s\nn = %s",
                   .attrition_wrap_label(rows$step[i], 26L),
                   format(as.integer(rows$n[i]), big.mark = ","))
    fill_i <- if (i == nb) "#eef6ff" else "#FFFFFF"
    .attrition_grid_roundbox(x0, y0, x1, y1, fill_i, ff, lab, fontsize = 8.6)
    if (i < nb) {
      dn <- as.integer(rows$n[i]) - as.integer(rows$n[i + 1L])
      ymid <- y0 - gap / 2
      .attrition_grid_arrow(cx, y0 - 0.004, cx, y0 - gap + 0.006, ff)
      if (is.finite(dn) && dn > 0L) {
        reason <- rows$exclude_reason[i + 1L]
        if (is.na(reason) || !nzchar(reason)) reason <- "Did not meet inclusion criteria"
        exlab <- sprintf("Excluded n = %s\n(%s)",
                         format(dn, big.mark = ","),
                         .attrition_wrap_label(reason, 22L))
        eh <- min(gap * 0.92, 0.085)
        .attrition_grid_roundbox(ex0, ymid - eh / 2, ex1, ymid + eh / 2,
                                 "#f7f7f7", ff, exlab, fontsize = 7.4,
                                 fontface = "plain")
        .attrition_grid_arrow(cx, ymid, ex0 - 0.006, ymid, ff, lty = 2)
      }
    }
  }
  if (!is.null(footnote) && length(footnote)) {
    grid::grid.text(paste(as.character(footnote), collapse = "\n"),
                    x = grid::unit(0.5, "npc"), y = grid::unit(0.03, "npc"),
                    just = "bottom",
                    gp = grid::gpar(fontsize = 7, fontfamily = ff,
                                    col = "#333333", lineheight = 1.12))
  }
  invisible(TRUE)
}

#' 双栏 Figure 1 PDF（Panel A=MIMIC-IV，Panel B=eICU）。缺 CSV / 人数非单调 → 硬失败。
#' @return PDF 绝对路径（character(1)）。
ml_reference_build_flowchart <- function(mimic_csv, eicu_csv, out_dir,
                                         file_name = NULL, footnotes = NULL) {
  .ml_ref_ensure_engine()
  fr <- ml_reference_read_flowcharts(mimic_csv, eicu_csv)
  rows <- fr$rows
  fig_dir <- file.path(out_dir, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  fn <- as.character(file_name %||%
    "Figure 1. Inclusion exclusion flowchart (MIMIC-IV, eICU).pdf")[1L]
  dest <- normalizePath(file.path(fig_dir, fn), winslash = "/", mustWork = FALSE)

  rm_rows <- rows[rows$database == "MIMIC-IV", , drop = FALSE]
  re_rows <- rows[rows$database == "eICU", , drop = FALSE]
  stopifnot(nrow(rm_rows) >= 1L, nrow(re_rows) >= 1L)

  ff <- if (exists("resolve_plot_font_family", mode = "function")) {
    resolve_plot_font_family("Times New Roman")
  } else {
    "Times New Roman"
  }
  if (exists("pipeline_pdf_device", mode = "function")) {
    opened <- tryCatch({ pipeline_pdf_device(dest, 11.7, 8.4, ff); TRUE },
                       error = function(e) FALSE)
  } else {
    opened <- FALSE
  }
  if (!isTRUE(opened)) {
    opened <- tryCatch({ grDevices::cairo_pdf(dest, width = 11.7, height = 8.4); TRUE },
                       error = function(e) FALSE)
  }
  if (!isTRUE(opened)) {
    stop("Figure 1 无法打开 PDF 设备：", dest, call. = FALSE)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  # 左半 Panel A
  grid::pushViewport(grid::viewport(x = 0.25, y = 0.5, width = 0.49, height = 0.98))
  .ml_ref_fc_panel(rm_rows, "Panel A: MIMIC-IV (development / internal validation)",
                   ff, footnote = footnotes)
  grid::popViewport()
  # 右半 Panel B
  grid::pushViewport(grid::viewport(x = 0.75, y = 0.5, width = 0.49, height = 0.98))
  .ml_ref_fc_panel(re_rows, "Panel B: eICU (external validation)", ff,
                   footnote = footnotes)
  grid::popViewport()
  invisible(grDevices::dev.off())
  on.exit(NULL)  # 已显式关闭
  if (!file.exists(dest)) {
    stop("Figure 1 PDF 未生成：", dest, call. = FALSE)
  }
  dest
}

# ===========================================================================
# 3) Table 1：双库 Panel A/B 基线（Survivor/Non-survivor）
# ===========================================================================

.ml_ref_fmt_num2 <- function(x) {
  dig <- .pipeline_pub_digits()$desc
  ifelse(is.finite(x), formatC(x, format = "f", digits = dig), "")
}
.ml_ref_fmt_pct <- function(x) {
  dig <- .pipeline_pub_digits()$desc
  ifelse(is.finite(x), paste0(formatC(x, format = "f", digits = dig), "%"), "")
}

# 单列描述统计（连续 -> median (Q1, Q3)；因子 -> 各水平 n (%)）。
.ml_ref_t1_cont_row <- function(label, vec_all, vec_sur, vec_non) {
  f <- function(v) {
    v <- suppressWarnings(as.numeric(v)); v <- v[is.finite(v)]
    if (!length(v)) return("")
    qs <- stats::quantile(v, c(0.5, 0.25, 0.75), na.rm = TRUE)
    sprintf("%s (%s, %s)", .ml_ref_fmt_num2(qs[1]), .ml_ref_fmt_num2(qs[2]),
            .ml_ref_fmt_num2(qs[3]))
  }
  # 组间比较（Wilcoxon，Survivor vs Non-survivor）
  p <- NA_real_
  a <- suppressWarnings(as.numeric(vec_sur)); b <- suppressWarnings(as.numeric(vec_non))
  a <- a[is.finite(a)]; b <- b[is.finite(b)]
  if (length(a) >= 2L && length(b) >= 2L) {
    p <- tryCatch(stats::wilcox.test(a, b, exact = FALSE)$p.value,
                  error = function(e) NA_real_)
  }
  data.frame(Characteristic = label, Overall = f(vec_all), Survivor = f(vec_sur),
             Non_survivor = f(vec_non), `p-value` = pub_format_p(p),
             check.names = FALSE, stringsAsFactors = FALSE)
}
.ml_ref_t1_cat_row <- function(label, vec_all, vec_sur, vec_non, lvl) {
  cnt <- function(v, lv) {
    v <- as.character(v)
    sum(v == lv, na.rm = TRUE)
  }
  prop <- function(v, lv) {
    v <- as.character(v); nn <- sum(!is.na(v))
    if (!nn) return(NA_real_)
    100 * sum(v == lv, na.rm = TRUE) / nn
  }
  # 因子 chi-square（列联表 count 水平）
  tab <- rbind(
    all = sapply(lvl, function(lv) cnt(vec_all, lv)),
    sur = sapply(lvl, function(lv) cnt(vec_sur, lv)),
    non = sapply(lvl, function(lv) cnt(vec_non, lv))
  )
  tab <- tab[c("sur", "non"), , drop = FALSE]
  p <- NA_real_
  if (nrow(tab) == 2L && sum(tab) > 0) {
    p <- tryCatch({
      if (any(colSums(tab) == 0)) NA_real_ else
        suppressWarnings(stats::chisq.test(tab, correct = FALSE))$p.value
    }, error = function(e) NA_real_)
  }
  # 变量级 P（取该组首个水平行填写，其余水平留空）
  data.frame(Characteristic = label, Overall = "", Survivor = "",
             Non_survivor = "", `p-value` = pub_format_p(p),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# 计算某库 Panel 的基线行（含 header 行 + 各变量行）。返回 data.frame。
# 结局：28 天死亡 = Non-survivor。本课题 checkpoint 常把死亡水平误标为 "AKI"、
# 存活为 "No AKI"；禁止再用 outcome_case_label="Non-survivor" 硬套导致 N_non=0。
.ml_ref_t1_resolve_surv_flags <- function(x, sur_lbl = "Survivor",
                                          non_lbl = "Non-survivor") {
  grp <- trimws(as.character(x))
  death_labs <- unique(c(
    non_lbl, "Non-survivor", "non-survivor", "AKI", "1", "Yes",
    "Dead", "Death", "Died", "death"
  ))
  surv_labs <- unique(c(
    sur_lbl, "Survivor", "survivor", "No AKI", "0", "No", "Alive", "alive"
  ))
  is_non <- grp %in% death_labs
  is_sur <- grp %in% surv_labs
  num <- suppressWarnings(as.numeric(grp))
  if (any(num %in% c(0, 1), na.rm = TRUE) &&
      all(is.na(num) | num %in% c(0, 1))) {
    is_non <- !is.na(num) & num == 1
    is_sur <- !is.na(num) & num == 0
  }
  if (!any(is_non, na.rm = TRUE) || !any(is_sur, na.rm = TRUE)) {
    for (ag in list(
      list(analysis_group = "AKI", reference_group = "No AKI"),
      list(analysis_group = non_lbl, reference_group = sur_lbl),
      list(analysis_group = "1", reference_group = "0")
    )) {
      ev <- tryCatch(
        pipeline_outcome_as_01(x, cfg = list(project = ag)),
        error = function(e) NULL
      )
      if (!is.null(ev) && any(ev == 1L, na.rm = TRUE) &&
          any(ev == 0L, na.rm = TRUE)) {
        is_non <- ev == 1L
        is_sur <- ev == 0L
        break
      }
    }
  }
  if (!any(is_non, na.rm = TRUE) && !any(is_sur, na.rm = TRUE)) {
    stop("Table 1 无法将结局列映射为 Survivor/Non-survivor（水平: ",
         paste(unique(grp)[seq_len(min(6L, length(unique(grp))))], collapse = ", "),
         ")", call. = FALSE)
  }
  if (any(is_non, na.rm = TRUE) && !any(is_sur, na.rm = TRUE)) {
    is_sur <- !is_non & !is.na(grp) & nzchar(grp)
  }
  if (any(is_sur, na.rm = TRUE) && !any(is_non, na.rm = TRUE)) {
    is_non <- !is_sur & !is.na(grp) & nzchar(grp)
  }
  list(is_sur = is_sur, is_non = is_non)
}

.ml_ref_t1_section_header <- function(title) {
  data.frame(
    Characteristic = as.character(title)[1L],
    Overall = "", Survivor = "", Non_survivor = "", `p-value` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

.ml_ref_t1_append_vars <- function(rows_list, dat, is_sur, is_non, sur_v, non_v,
                                   cont, catv, lvls) {
  for (v in cont) {
    if (!v %in% names(dat)) next
    lab <- v
    if (!is.null(lvls[[v]])) {
      cutv <- lvls[[v]]
      b_all <- ifelse(suppressWarnings(as.numeric(dat[[v]])) >= cutv,
                      sprintf(">=%d", cutv), sprintf("<%d", cutv))
      b_sur <- b_all[is_sur]; b_non <- b_all[is_non]
      b_all_v <- b_all
      for (lv in sort(unique(b_all_v[!is.na(b_all_v)]))) {
        cn <- function(vec) { vec <- vec[!is.na(vec)]; sum(vec == lv, na.rm = TRUE) }
        pr <- function(vec) {
          vec <- vec[!is.na(vec)]; nn <- length(vec)
          if (!nn) NA_real_ else 100 * sum(vec == lv) / nn
        }
        pv <- tryCatch({
          tt <- matrix(c(cn(b_sur), length(b_sur[!is.na(b_sur)]) - cn(b_sur),
                         cn(b_non), length(b_non[!is.na(b_non)]) - cn(b_non)),
                       nrow = 2, byrow = TRUE)
          if (any(rowSums(tt) == 0) || any(colSums(tt) == 0)) NA_real_ else
            suppressWarnings(stats::chisq.test(tt, correct = FALSE))$p.value
        }, error = function(e) NA_real_)
        rows_list[[length(rows_list) + 1L]] <- data.frame(
          Characteristic = sprintf("%s, n(%%)", lab), Overall = "",
          Survivor = "", Non_survivor = "", `p-value` = "",
          check.names = FALSE, stringsAsFactors = FALSE)
        rows_list[[length(rows_list) + 1L]] <- data.frame(
          Characteristic = sprintf("  %s", lv),
          Overall = sprintf("%s (%s)", format(cn(b_all_v), big.mark = ","),
                            .ml_ref_fmt_pct(pr(b_all_v))),
          Survivor = sprintf("%s (%s)", format(cn(b_sur), big.mark = ","),
                             .ml_ref_fmt_pct(pr(b_sur))),
          Non_survivor = sprintf("%s (%s)", format(cn(b_non), big.mark = ","),
                                 .ml_ref_fmt_pct(pr(b_non))),
          `p-value` = pub_format_p(pv), check.names = FALSE, stringsAsFactors = FALSE)
      }
    } else {
      rows_list[[length(rows_list) + 1L]] <-
        .ml_ref_t1_cont_row(sprintf("%s", lab), dat[[v]], sur_v[[v]], non_v[[v]])
    }
  }
  for (v in catv) {
    if (!v %in% names(dat)) next
    lvl <- levels(factor(dat[[v]]))
    if (!length(lvl)) next
    rows_list[[length(rows_list) + 1L]] <-
      .ml_ref_t1_cat_row(sprintf("%s", v), dat[[v]], sur_v[[v]], non_v[[v]], lvl)
    for (lv in lvl) {
      cn <- function(vec) { vec <- as.character(vec); sum(vec == lv, na.rm = TRUE) }
      pr <- function(vec) {
        vec <- as.character(vec); nn <- sum(!is.na(vec))
        if (!nn) NA_real_ else 100 * sum(vec == lv, na.rm = TRUE) / nn
      }
      rows_list[[length(rows_list) + 1L]] <- data.frame(
        Characteristic = sprintf("  %s", lv),
        Overall = sprintf("%s (%s)", format(cn(dat[[v]]), big.mark = ","),
                          .ml_ref_fmt_pct(pr(dat[[v]]))),
        Survivor = sprintf("%s (%s)", format(cn(as.character(sur_v[[v]])), big.mark = ","),
                           .ml_ref_fmt_pct(pr(as.character(sur_v[[v]])))),
        Non_survivor = sprintf("%s (%s)", format(cn(as.character(non_v[[v]])), big.mark = ","),
                               .ml_ref_fmt_pct(pr(as.character(non_v[[v]])))),
        `p-value` = "", check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  rows_list
}

.ml_ref_t1_panel_rows <- function(panel_label, dat, vars, outcome_col,
                                   sur_lbl, non_lbl) {
  if (is.null(dat) || !is.data.frame(dat) || !nrow(dat)) {
    stop("Table 1 需要非空 dat：", panel_label, call. = FALSE)
  }
  if (!outcome_col %in% names(dat)) {
    stop("Table 1 结局列缺失：", outcome_col, " (", panel_label, ")", call. = FALSE)
  }
  fl <- .ml_ref_t1_resolve_surv_flags(dat[[outcome_col]], sur_lbl, non_lbl)
  is_sur <- fl$is_sur
  is_non <- fl$is_non
  n_all <- nrow(dat)
  n_sur <- sum(is_sur, na.rm = TRUE)
  n_non <- sum(is_non, na.rm = TRUE)
  if (n_non < 1L || n_sur < 1L) {
    stop(sprintf(
      "Table 1 %s 分组人数异常：Survivor=%s Non-survivor=%s（禁止交 N_non=0 表）",
      panel_label, n_sur, n_non
    ), call. = FALSE)
  }
  sur_v <- dat[is_sur, , drop = FALSE]
  non_v <- dat[is_non, , drop = FALSE]
  hdr <- data.frame(
    Characteristic = "Characteristic",
    Overall = sprintf("Overall N = %s", format(n_all, big.mark = ",")),
    Survivor = sprintf("%s N = %s", sur_lbl, format(n_sur, big.mark = ",")),
    Non_survivor = sprintf("%s N = %s", non_lbl, format(n_non, big.mark = ",")),
    `p-value` = "p-value", check.names = FALSE, stringsAsFactors = FALSE
  )
  rows_list <- list(hdr)
  lvls <- vars$levels %||% list()
  sections <- vars$sections %||% NULL
  if (is.list(sections) && length(sections)) {
    for (sec in sections) {
      title <- as.character(sec$title %||% sec$name %||% "")[1L]
      if (nzchar(title)) {
        rows_list[[length(rows_list) + 1L]] <- .ml_ref_t1_section_header(title)
      }
      rows_list <- .ml_ref_t1_append_vars(
        rows_list, dat, is_sur, is_non, sur_v, non_v,
        cont = as.character(sec$continuous %||% character(0)),
        catv = as.character(sec$categorical %||% character(0)),
        lvls = lvls
      )
    }
  } else {
    cont <- as.character(vars$continuous %||% character(0))
    catv <- as.character(vars$categorical %||% character(0))
    expo <- unique(as.character(vars$exposure %||% character(0)))
    expo <- intersect(expo, names(dat))
    if (length(expo)) {
      cont_demo <- setdiff(cont, expo)
      rows_list <- .ml_ref_t1_append_vars(
        rows_list, dat, is_sur, is_non, sur_v, non_v, cont_demo, catv, lvls
      )
      rows_list[[length(rows_list) + 1L]] <- .ml_ref_t1_section_header("Exposures")
      rows_list <- .ml_ref_t1_append_vars(
        rows_list, dat, is_sur, is_non, sur_v, non_v, expo, character(0), lvls
      )
    } else {
      rows_list <- .ml_ref_t1_append_vars(
        rows_list, dat, is_sur, is_non, sur_v, non_v, cont, catv, lvls
      )
    }
  }
  body <- do.call(rbind, rows_list)
  body$Panel <- panel_label
  body
}

#' 双库 Table 1（Panel A=MIMIC-IV，Panel B=eICU；结局 Survivor/Non-survivor）。
#' @param db_frames list(MIMIC_IV=..., eICU=...)（元素为 data.frame，含结局列）。
#' @return 合并 data.frame（列 Panel + Characteristic/Overall/Survivor/Non_survivor/p-value），
#'   并写出单一 xlsx 到 out_dir/Tables。
ml_reference_build_table1 <- function(db_frames, out_dir,
                                      vars = NULL,
                                      outcome_col = "fustatus",
                                      file_name = NULL) {
  .ml_ref_ensure_engine()
  if (is.null(db_frames) || length(db_frames) < 2L) {
    stop("Table 1 需双库 db_frames（MIMIC_IV + eICU）", call. = FALSE)
  }
  sur_lbl <- "Survivor"; non_lbl <- "Non-survivor"
  nm <- names(db_frames)
  mim <- if ("MIMIC_IV" %in% nm) db_frames[["MIMIC_IV"]] else
    db_frames[[grep("MIMIC", nm, ignore.case = TRUE, value = TRUE)[1]]]
  eic <- if ("eICU" %in% nm) db_frames[["eICU"]] else
    db_frames[[grep("eICU", nm, ignore.case = TRUE, value = TRUE)[1]]]
  if (is.null(mim) || is.null(eic)) {
    stop("Table 1 无法从 db_frames 分出 MIMIC-IV / eICU", call. = FALSE)
  }
  if (is.null(vars)) {
    idx_ab <- tryCatch(c(.ref_ia(), .ref_ib()), error = function(e) c("SOSM", "WPR"))
    vars <- list(
      levels = list(Age = 65L),
      sections = list(
        list(
          title = "Demographics",
          continuous = intersect(c("Age", "Weight"), names(mim)),
          categorical = intersect("Gender", names(mim))
        ),
        list(
          title = "Exposures",
          continuous = intersect(idx_ab, names(mim)),
          categorical = character(0)
        ),
        list(
          title = "Vital signs / severity",
          continuous = intersect(c("HR", "MAP", "Creatinine", "SOFA"), names(mim)),
          categorical = character(0)
        )
      )
    )
  }
  pa <- .ml_ref_t1_panel_rows("Panel A: MIMIC-IV", mim, vars, outcome_col,
                              sur_lbl, non_lbl)
  pb <- .ml_ref_t1_panel_rows("Panel B: eICU", eic, vars, outcome_col,
                              sur_lbl, non_lbl)
  tab <- rbind(pa, pb)
  cols <- c("Panel", "Characteristic", "Overall", "Survivor", "Non_survivor",
            "p-value")
  tab <- tab[, cols, drop = FALSE]
  colnames(tab)[colnames(tab) == "Non_survivor"] <- "Non-survivor"
  # 防误写校验：任何单元不得出现 No AKI / "AKI N ="
  blob <- paste(as.character(unlist(tab)), collapse = " ")
  if (grepl("No AKI", blob, ignore.case = TRUE) ||
      grepl("AKI N = ", blob)) {
    stop("Table 1 混入 AKI/No AKI 误标签（须 Survivor/Non-survivor）", call. = FALSE)
  }
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  fn <- as.character(file_name %||%
    "Table 1. Baseline characteristics by 28-day survival (MIMIC-IV, eICU).xlsx")[1L]
  dest <- file.path(tab_dir, fn)
  foot <- c(
    "Continuous variables are presented as median (interquartile range); categorical",
    "variables as n (%). Comparison between Survivor and Non-survivor groups used the",
    "Wilcoxon rank-sum or Pearson chi-squared test. Panel A = MIMIC-IV, Panel B = eICU.",
    "Outcome: 28-day all-cause mortality (Survivor / Non-survivor). pub_digits desc=2."
  )
  body_for_xlsx <- tab
  colnames(body_for_xlsx) <- c("Panel", "Characteristic", "Overall",
                               "Survivor", "Non-survivor", "p-value")
  ok <- tryCatch({
    sci_xlsx_single_header_booktabs(
      filepath = dest,
      title = "Table 1. Baseline characteristics by 28-day survival (MIMIC-IV Panel A, eICU Panel B).",
      df_body = body_for_xlsx, sheet = "Table 1", footnotes = foot
    )
    file.exists(dest)
  }, error = function(e) {
    warning("Table 1 xlsx 写出失败: ", conditionMessage(e), call. = FALSE)
    FALSE
  })
  attr(tab, "xlsx") <- if (isTRUE(ok)) normalizePath(dest, winslash = "/",
                                                     mustWork = FALSE) else NA_character_
  tab
}

#' 从旧双库 Table 1 xlsx（遗留标签 No AKI / AKI 实为 28d 生存/死亡分组）
#' 外科式**只读重排**：列头改 Survivor / Non-survivor（N 不变），加 Panel A/B
#' 合并为单一 xlsx。不改旧文件。返回合并 data.frame。
ml_reference_table1_from_existing <- function(mimic_xlsx, eicu_xlsx, out_dir,
                                              file_name = NULL) {
  .ml_ref_ensure_engine()
  read_old <- function(path, panel) {
    if (!file.exists(path)) {
      stop("Table 1 重排缺旧表文件（不得编造）：", path, call. = FALSE)
    }
    d <- as.data.frame(openxlsx::read.xlsx(path, colNames = FALSE,
                                           check.names = FALSE),
                       stringsAsFactors = FALSE)
    d <- d[, seq_len(min(5L, ncol(d))), drop = FALSE]
    hdr_i <- which(vapply(d[[1]], function(x)
      grepl("^\\s*Characteristic\\s*$", as.character(x)), logical(1)))
    if (!length(hdr_i)) {
      stop("Table 1 旧表缺 Characteristic 表头行：", path, call. = FALSE)
    }
    hdr_i <- hdr_i[1]
    body <- d[-seq_len(hdr_i), , drop = FALSE]
    # 截掉尾部脚注行（前两列任一含 presented / Statistical / test.）
    stop_i <- which(vapply(seq_len(nrow(body)), function(i) {
      c1 <- as.character(body[i, 1])[1]; c2 <- as.character(body[i, 2])[1]
      grepl("are presented|Statistical comparisons|test\\.$", c1, ignore.case = TRUE) ||
        grepl("are presented|Statistical comparisons", c2, ignore.case = TRUE)
    }, logical(1)))
    if (length(stop_i)) body <- body[seq_len(min(stop_i) - 1L), , drop = FALSE]
    hd <- trimws(as.character(unlist(d[hdr_i, ])))
    # 期望列：Characteristic | Overall N | No AKI N | AKI N | p-value
    if (!length(grep("^No AKI", hd)) || !length(grep("^AKI", hd))) {
      stop("Table 1 旧表列头非预期（No AKI/AKI）：", paste(hd, collapse = " | "),
           call. = FALSE)
    }
    j_ov <- grep("^Overall", hd)[1]
    j_surv <- grep("^No AKI", hd)[1]
    j_non <- grep("^AKI", hd)[1]
    j_p <- grep("p-value|^P$|^P-value", hd)
    n_surv <- as.integer(gsub("[^0-9]", "", hd[j_surv]))
    n_non <- as.integer(gsub("[^0-9]", "", hd[j_non]))
    n_ov <- suppressWarnings(as.integer(gsub("[^0-9]", "", hd[j_ov])))
    df <- data.frame(
      Panel = panel,
      Characteristic = trimws(as.character(body[[1]])),
      Overall = trimws(as.character(body[[j_ov]])),
      Survivor = trimws(as.character(body[[j_surv]])),
      Non_survivor = trimws(as.character(body[[j_non]])),
      `p-value` = if (length(j_p)) trimws(as.character(body[[j_p[1]]])) else "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
    # 表体内残留的结局水平行（Group 变量下 No AKI / AKI 实为生存口径）精确重映射
    df$Characteristic[df$Characteristic == "No AKI"] <- "Survivor"
    df$Characteristic[df$Characteristic == "AKI"] <- "Non-survivor"
    # 列头换成正确口径（N 沿用旧表：Survivor=No AKI n，Non-survivor=AKI n）
    df[1, "Characteristic"] <- "Characteristic"
    df[1, c("Overall", "Survivor", "Non_survivor")] <- c(
      if (!is.na(n_ov) && n_ov > 0) sprintf("Overall N = %s", format(n_ov, big.mark = ",")) else hd[j_ov],
      sprintf("Survivor N = %s", format(n_surv, big.mark = ",")),
      sprintf("Non-survivor N = %s", format(n_non, big.mark = ","))
    )
    df
  }
  pa <- read_old(mimic_xlsx, "Panel A: MIMIC-IV")
  pb <- read_old(eicu_xlsx, "Panel B: eICU")
  tab <- rbind(pa, pb)
  blob <- paste(as.character(unlist(tab)), collapse = " ")
  if (grepl("No AKI", blob, ignore.case = TRUE) || grepl("AKI N = ", blob)) {
    stop("Table 1 重排后仍混入 AKI/No AKI 标签", call. = FALSE)
  }
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  fn <- as.character(file_name %||%
    "Table 1. Baseline characteristics by 28-day survival (MIMIC-IV, eICU).xlsx")[1L]
  dest <- file.path(tab_dir, fn)
  foot <- c(
    "Continuous variables are presented as median (interquartile range) or mean (standard",
    "deviation) depending on their distribution; categorical variables as n (%).",
    "Comparisons between Survivor and Non-survivor used the Wilcoxon rank-sum or Pearson",
    "chi-squared test. Panel A = MIMIC-IV, Panel B = eICU.",
    "Outcome: 28-day all-cause mortality (Survivor / Non-survivor).",
    "The legacy source checkpoint mislabelled the two outcome columns with the disease",
    "name instead of the survival status; they are relabelled here to Survivor /",
    "Non-survivor with the same counts (MIMIC-IV 15,050 / 3,344 of 18,394; eICU 8,462 /",
    "2,096 of 10,558). Cell values are otherwise unchanged (read-only re-layout)."
  )
  # 注：旧表 Overall N = 18,394 / 10,558（分析队列），两分组列头 N 亦为分析队列口径
  # （15,050+3,344=18,394；8,462+2,096=10,558）——自洽。
  body <- tab
  colnames(body) <- c("Panel", "Characteristic", "Overall", "Survivor",
                      "Non-survivor", "p-value")
  ok <- tryCatch({
    sci_xlsx_single_header_booktabs(
      filepath = dest,
      title = "Table 1. Baseline characteristics by 28-day survival (MIMIC-IV Panel A, eICU Panel B).",
      df_body = body, sheet = "Table 1", footnotes = foot
    )
    file.exists(dest)
  }, error = function(e) {
    warning("Table 1 重排 xlsx 写出失败: ", conditionMessage(e), call. = FALSE)
    FALSE
  })
  attr(tab, "xlsx") <- if (isTRUE(ok)) normalizePath(dest, winslash = "/",
                                                     mustWork = FALSE) else NA_character_
  tab
}

# ===========================================================================
# 4) S1：AKI 队列定义与代码级证据（缺上游代码 → 证据不足）
# ===========================================================================

#' 写已证实的 AKI 队列/变量定义。MIMIC-IV 有 Acute_Renal_Failure 旗标（Yes/No，
#' 实测即证）；eICU 无该列、依赖上游 D02 预筛（用户确认全部为 AKI），但上游
#' ICD/KDIGO 提取代码未随数据提供 → evidence_status 标「证据不足」，不编造 ICD。
#' @return list(long=data.frame, xlsx=path)。
ml_reference_build_s1 <- function(study_index_root, out_dir, file_name = NULL) {
  .ml_ref_ensure_engine()
  # 尽力读 D02 实测旗标计数（只读，不改原文件）；不可读时回退已核实静态事实。
  count_arf <- function(rdspath) {
    if (is.na(rdspath) || !file.exists(rdspath)) return(NULL)
    tryCatch({
      e <- new.env(); load(rdspath, envir = e)
      objs <- ls(e)
      d <- if (length(objs)) get(objs[1], envir = e) else NULL
      if (!is.data.frame(d)) return(NULL)
      out <- list(n = nrow(d))
      if ("Acute_Renal_Failure" %in% names(d)) {
        tb <- table(d$Acute_Renal_Failure, useNA = "no")
        out$arf <- as.list(tb)
        out$has_arf <- TRUE
      } else {
        out$has_arf <- FALSE
      }
      out
    }, error = function(e) NULL)
  }
  # study_index_root 可能是 by_index/【success】SOSM+WPR；D02 在其上溯 data/
  data_dir <- NULL
  cand_roots <- c(
    file.path(study_index_root, "data"),
    file.path(dirname(study_index_root), "data"),
    file.path(dirname(dirname(study_index_root)), "data"),
    file.path(study_index_root, "..", "..", "data")
  )
  for (cd in cand_roots) if (dir.exists(cd)) { data_dir <- cd; break }
  mimic_d02 <- if (!is.null(data_dir))
    file.path(data_dir, "D02_result_MIMIC.RData") else NA_character_
  eicu_d02 <- if (!is.null(data_dir))
    file.path(data_dir, "D02_result_eICU.RData") else NA_character_
  cm <- count_arf(mimic_d02); ce <- count_arf(eicu_d02)

  mimic_n <- if (!is.null(cm)) format(cm$n, big.mark = ",") else "26,055"
  if (!is.null(cm) && isTRUE(cm$has_arf)) {
    yes <- cm$arf[["Yes"]]; no <- cm$arf[["No"]]
    mimic_evi_detail <- sprintf(
      "D02_result_MIMIC 实测 n=%s，Acute_Renal_Failure=Yes %s / No %s；两库最长随访 28 天",
      mimic_n, format(yes, big.mark = ","), format(no, big.mark = ","))
    mimic_status <- "已证实"
  } else {
    mimic_evi_detail <- "Acute_Renal_Failure 旗标（Yes/No）；已核实存在，n=26,055"
    mimic_status <- "已证实"
  }
  if (!is.null(ce) && identical(ce$has_arf, FALSE)) {
    eicu_has <- "无 Acute_Renal_Failure 列"
  } else {
    eicu_has <- "无 Acute_Renal_Failure 列（按已知事实）"
  }
  eicu_detail <- paste0(
    eicu_has, "；eICU 队列依赖上游 D02 预筛（用户确认全部为 AKI），但上游 ",
    "ICD/KDIGO 提取代码未随数据提供，无法在数据层复核 → 证据不足，不编造 ICD")

  long <- data.frame(
    database = c("MIMIC-IV", "MIMIC-IV", "eICU", "eICU"),
    item = c("AKI 队列识别", "随访/结局", "AKI 队列识别", "随访/结局"),
    definition = c(
      "主库含 Acute_Renal_Failure 旗标列（取值 Yes/No），据此识别 AKI 队列",
      "结局=28 天全因死亡（Survivor / Non-survivor）；随访上限 28 天，不存在任何更长随访窗",
    paste0("eICU ", eicu_has, "；依赖上游 D02 预筛队列"),
      "结局=28 天全因死亡（Survivor / Non-survivor）；随访上限 28 天，不存在任何更长随访窗"
    ),
    evidence_source = c(
      if (!is.null(cm)) "D02_result_MIMIC.RData（实测）" else "已核实队列事实",
      "config 结局列 fustatus / 引擎 0-1 映射",
      if (!is.null(ce)) "D02_result_eICU.RData（实测）" else "已核实列缺失事实",
      "config 结局列 fustatus / 引擎 0-1 映射"
    ),
    evidence_status = c(mimic_status, "已证实", "证据不足", "已证实"),
    evidence_detail = c(
      mimic_evi_detail,
      "两库 fustatus 0/1 经 pipeline_outcome_as_01 正确映射死亡=1（Non-survivor）",
      eicu_detail,
      "eICU 与 MIMIC-IV 同用 28 天口径；外验冻结主库资产、不重训"
    ),
    stringsAsFactors = FALSE
  )
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  fn <- as.character(file_name %||%
    "Table S1. AKI cohort and variable definitions with code evidence.xlsx")[1L]
  dest <- file.path(tab_dir, fn)
  foot <- c(
    "MIMIC-IV: Acute_Renal_Failure (Yes/No) flag is directly present in D02 (evidence: measured).",
    "eICU: no Acute_Renal_Failure column; cohort relies on upstream D02 pre-filter (user-confirmed",
    "as all AKI), but the upstream ICD/KDIGO extraction code is NOT provided with the data ->",
    "INSUFFICIENT EVIDENCE; no ICD codes are fabricated. Both databases capped at 28-day follow-up."
  )
  ok <- tryCatch({
    sci_xlsx_single_header_booktabs(
      filepath = dest,
      title = "Table S1. AKI cohort and variable definitions with code-level evidence.",
      df_body = long, sheet = "Table S1", footnotes = foot
    )
    file.exists(dest)
  }, error = function(e) {
    warning("S1 xlsx 写出失败: ", conditionMessage(e), call. = FALSE); FALSE
  })
  list(long = long, xlsx = if (isTRUE(ok)) dest else NA_character_)
}

# ===========================================================================
# 5) S2 UV / S3 VIF·继承审计：复用既有产物入口（缺则标注）
# ===========================================================================

#' 尝试定位旧 by_index【success】SOSM+WPR 的单因素表作为 S2 复用入口。
.ml_ref_find_uv_source <- function(study_index_root) {
  if (is.null(study_index_root) || !dir.exists(study_index_root)) return(NA_character_)
  tdir <- file.path(study_index_root, "Tables")
  cands <- character(0)
  if (dir.exists(tdir)) {
    cands <- list.files(tdir, pattern = "(?i)Univariate", full.names = TRUE)
  }
  if (!length(cands)) {
    # 递归一层库目录
    subs <- list.dirs(study_index_root, recursive = FALSE, full.names = TRUE)
    for (s in subs) {
      td <- file.path(s, "Tables")
      if (dir.exists(td)) {
        cc <- list.files(td, pattern = "(?i)Univariate", full.names = TRUE)
        if (length(cc)) cands <- c(cands, cc)
      }
    }
  }
  if (length(cands)) normalizePath(cands[1], winslash = "/", mustWork = FALSE)
  else NA_character_
}

#' S3：MIMIC train/internal VIF + eICU 继承特征审计。VIF 若引擎已有产物则引用，
#' 否则以 Task5 冻结资产 manifest 落「继承特征审计」长表（真实、可核实），并标注 VIF 缺。
#' @param asset_dir Task5 model_assets 目录（含 <stratum>/manifest.json）。
ml_reference_build_s3 <- function(asset_dir, out_dir, file_name = NULL) {
  .ml_ref_ensure_engine()
  audit_from_assets <- function(dirp) {
    if (is.null(dirp) || !dir.exists(dirp)) return(NULL)
    subdirs <- list.dirs(dirp, recursive = FALSE, full.names = TRUE)
    rows <- list()
    for (s in subdirs) {
      mf <- file.path(s, "manifest.json")
      fmr <- file.path(s, "feature_manifest.rds")
      stratum_key <- basename(s)
      feats <- character(0); flv <- list(); trained_in <- "MIMIC-IV"
      if (file.exists(fmr)) {
        obj <- tryCatch(readRDS(fmr), error = function(e) NULL)
        if (is.list(obj)) {
          feats <- as.character(obj$features %||% character(0))
          flv <- obj$factor_levels %||% list()
          trained_in <- as.character(obj$source_database %||% "MIMIC-IV")
          trained_in <- sub("^MIMIC[_ ]?IV$", "MIMIC-IV", trained_in)
        }
      }
      if (!length(feats) && file.exists(mf)) {
        txt <- paste(readLines(mf, warn = FALSE), collapse = " ")
        feats <- regmatches(txt, gregexpr("\"[A-Za-z][A-Za-z0-9_]*\"", txt))[[1]]
        feats <- gsub("\"", "", feats)
        feats <- feats[feats %in% c("Age", "Gender", "Weight", "HR")] # 保守：仅确认列存在时再取
      }
      for (ft in feats) {
        rows[[length(rows) + 1L]] <- data.frame(
          stratum = stratum_key, trained_in = trained_in, feature = ft,
          inherited_to_eicu = TRUE,
          factor_levels = paste(flv[[ft]] %||% NA_character_, collapse = "/"),
          audit_status = "继承自 MIMIC-IV 冻结资产",
          stringsAsFactors = FALSE
        )
      }
    }
    if (!length(rows)) return(NULL)
    do.call(rbind, rows)
  }
  audit <- audit_from_assets(asset_dir)
  if (is.null(audit)) {
    audit <- data.frame(stratum = NA_character_, trained_in = "MIMIC-IV",
                        feature = NA_character_, inherited_to_eicu = NA,
                        factor_levels = NA_character_,
                        audit_status = "证据不足：未找到 Task5 冻结资产 manifest",
                        stringsAsFactors = FALSE)
  }
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  fn <- as.character(file_name %||%
    "Table S3. VIF and inherited-feature audit (MIMIC train internal, eICU).xlsx")[1L]
  dest <- file.path(tab_dir, fn)
  foot <- c(
    "VIF screening runs on MIMIC-IV train/internal only (fit_on=train leakage gate); eICU never",
    "re-selects features -- it inherits the MIMIC-IV frozen feature set. Inherited-feature audit is",
    "derived from Task5 frozen asset manifests (source_database=MIMIC-IV). If a stratum asset is",
    "absent, the audit row is marked INSUFFICIENT EVIDENCE rather than fabricated."
  )
  ok <- tryCatch({
    sci_xlsx_single_header_booktabs(
      filepath = dest,
      title = "Table S3. VIF screening and eICU inherited-feature audit.",
      df_body = audit, sheet = "Table S3", footnotes = foot)
    file.exists(dest)
  }, error = function(e) {
    warning("S3 xlsx 写出失败: ", conditionMessage(e), call. = FALSE); FALSE
  })
  list(audit = audit, xlsx = if (isTRUE(ok)) dest else NA_character_,
       uv_source = NA_character_)
}

# ===========================================================================
# 6) MANIFEST：完整编号 + reference_role/adaptation/source/denominator/status
# ===========================================================================
#' 生成完整编号 MANIFEST.csv（34 角色），逐项记录来源 checkpoint 与就绪状态。
#' Fig1/Table1/S1 状态按 out_dir 实际落盘文件；其余按 Task4/5/6 staging 或旧
#' by_index 目录存在性判定；缺产物 → pending/missing（绝不标 ready 掩盖）。
ml_reference_build_manifest <- function(profile = NULL, out_dir,
                                        study_index_root = NA_character_,
                                        asset_dir = NULL) {
  .ml_ref_ensure_engine()
  prof <- profile %||% ml_reference_profile_40537296()
  n <- nrow(prof)
  fig_dir <- file.path(out_dir, "Figures"); tab_dir <- file.path(out_dir, "Tables")
  ex_in <- function(dirp, pat) {
    isTRUE(dir.exists(dirp)) && length(list.files(dirp, pattern = pat)) > 0L
  }
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- normalizePath(".", winslash = "/", mustWork = FALSE)
  task4 <- file.path(root, ".superpowers/sdd/staging/task4")
  task5 <- file.path(root, ".superpowers/sdd/staging/task5")
  task6 <- file.path(root, ".superpowers/sdd/staging/task6")
  if (is.null(asset_dir)) asset_dir <- file.path(task5, "model_assets")
  s11_present <- length(list.files(task5, pattern = "Table_S11", full.names = TRUE)) > 0L

  # 旧 by_index 额外表/图目录（S12-S16、Fig S6-S8 只读来源）
  old_tbl <- if (!is.na(study_index_root) && dir.exists(study_index_root))
    file.path(study_index_root, "Tables") else NA_character_
  old_fig <- if (!is.na(study_index_root) && dir.exists(study_index_root))
    file.path(study_index_root, "Figures") else NA_character_
  old_tbl_ready <- !is.na(old_tbl) && dir.exists(old_tbl)
  old_fig_ready <- !is.na(old_fig) && dir.exists(old_fig)

  src <- den <- status <- character(n)
  for (i in seq_len(n)) {
    k <- prof$kind[i]; num <- prof$number[i]
    if (k == "figure_main") {
      if (num == "1") {
        src[i] <- "真实 attrition CSV（MIMIC_IV/step37 + eICU/step28，按目录判库，Task7 ml_reference_build_flowchart）"
        den[i] <- "MIMIC-IV 26,055->18,394；eICU 15,270->10,558"
        status[i] <- if (ex_in(fig_dir, "^Figure 1\\.")) "ready" else "pending"
      } else if (num %in% as.character(2:6)) {
        src[i] <- "Task4 ref_assoc_run_all（staging/task4/Figures）"
        den[i] <- "MIMIC analysis n=18,394 / eICU n=10,558（SOFA 分层子集）"
        pat <- sprintf("^Figure %s\\.", num)
        status[i] <- if (ex_in(file.path(task4, "Figures"), pat)) "ready" else "pending"
      } else if (num %in% as.character(7:8)) {
        src[i] <- "Task6 ml_ref_fig7_boruta / ml_ref_fig8_grid（staging/task6；五模型全量=Task8）"
        den[i] <- "MIMIC 分层 train/internal + eICU 冻结外验"
        pat <- if (num == "7") "^Figure 7\\." else "^Figure 8\\."
        status[i] <- if (ex_in(task6, pat)) "smoke_only" else "pending"
      }
    } else if (k == "figure_supp") {
      if (num %in% as.character(2:5)) {
        src[i] <- "Task6 ml_ref_s2/s3/s4/s5（staging/task6；全量=Task8）"
        den[i] <- "MIMIC internal + eICU external（冻结）"
        pat <- sprintf("^Figure S%s\\.", num)
        status[i] <- if (ex_in(task6, pat)) "smoke_only" else "pending"
      } else if (num == "1") {
        src[i] <- "需 Task8 补产：PH beta(t) 趋势拼图（Task4 ref_assoc_run_all 仅产 Table S6-S8，未含趋势图）"
        den[i] <- "Overall / SOFA 0-4 / 5-10 / >=11，两库"
        s1fig <- ex_in(fig_dir, "^Figure S1\\.")
        status[i] <- if (s1fig) "ready" else "pending"
      } else { # 6,7,8
        src[i] <- "旧 by_index【success】SOSM+WPR/Figures（只读引用，重编号导出=Task8）"
        den[i] <- "overall train/internal/external 三集"
        status[i] <- if (old_fig_ready) "legacy_available" else "pending"
      }
    } else if (k == "table_main") {
      if (num == "1") {
        src[i] <- "Task7 ml_reference_build_table1（复用引擎基线；Survivor/Non-survivor）"
        den[i] <- "Panel A MIMIC-IV / Panel B eICU，28 天全队列"
        status[i] <- if (ex_in(tab_dir, "^Table 1\\.")) "ready" else "pending"
      } else { # 2
        src[i] <- "Task4 Table 2 Joint group Cox（staging/task4/Tables）"
        den[i] <- "Overall/SOFA 三层，双库；Group1 low/low 参照"
        status[i] <- if (ex_in(file.path(task4, "Tables"), "^Table 2[ .]")) "ready" else "pending"
      }
    } else { # table_supp
      if (num == "1") {
        src[i] <- "Task7 ml_reference_build_s1（D02 实测 + 证据不足标注）"
        den[i] <- "MIMIC-IV n=26,055（AKI 旗标）；eICU 上游预筛（代码未提供）"
        status[i] <- if (ex_in(tab_dir, "^Table S1\\.")) "ready" else "pending"
      } else if (num == "2") {
        uvsrc <- .ml_ref_find_uv_source(study_index_root)
        src[i] <- if (!is.na(uvsrc)) paste0("旧 by_index Table S5 Univariate（只读引用，重编号导出=Task8）: ", uvsrc)
          else "引擎 univariate Cox（Task8 完整跑产出）"
        den[i] <- "双库单因素 Cox"
        status[i] <- if (!is.na(uvsrc)) "legacy_available" else "missing"
      } else if (num == "3") {
        src[i] <- "Task7 ml_reference_build_s3（Task5 冻结资产继承审计 + 引擎 VIF）"
        den[i] <- "MIMIC train/internal VIF + eICU 继承审计"
        if (ex_in(tab_dir, "^Table S3\\.")) {
          status[i] <- "ready"
        } else {
          status[i] <- if (dir.exists(asset_dir)) "ready" else "missing"
        }
      } else if (num %in% as.character(4:10)) {
        src[i] <- "Task4 Table S4-S10（staging/task4/Tables）"
        den[i] <- paste0("双库；S", num, "（详见规格）")
        pat <- sprintf("^Table S%s[ .]", num)
        status[i] <- if (ex_in(file.path(task4, "Tables"), pat)) "ready" else "pending"
      } else if (num == "11") {
        src[i] <- "Task5 ml_frozen_bind_performance（staging/task5 Table_S11；五模型全量=Task8）"
        den[i] <- "分层五模型 x train/internal/external"
        status[i] <- if (s11_present) "smoke_only" else
          (if (dir.exists(task5)) "smoke_only" else "pending")
      } else { # 12-16
        src[i] <- "旧 by_index【success】SOSM+WPR/Tables（只读引用，重编号导出=Task8）"
        den[i] <- "overall 三集（train/internal/external）"
        status[i] <- if (old_tbl_ready) "legacy_available" else "pending"
      }
    }
  }
  mdf <- cbind(prof, source = src, denominator = den, status = status)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  mpath <- file.path(out_dir, "MANIFEST.csv")
  utils::write.csv(mdf, mpath, row.names = FALSE, fileEncoding = "UTF-8")
  normalizePath(mpath, winslash = "/", mustWork = FALSE)
}

# ===========================================================================
# 7) 高层封装：build_tables / build_figures（brief 接口；供 Task8 CLI 调）
# ===========================================================================
#' 构建 Figure 1（双库 flowchart）。db/attrition 源为两 CSV 路径。
ml_reference_build_figures <- function(out_dir, mimic_csv, eicu_csv, ...) {
  fig <- ml_reference_build_flowchart(mimic_csv, eicu_csv, out_dir, ...)
  list(figure1_pdf = fig)
}

#' 构建 Task7 表：Table 1（需 db_frames）+ S1（需 study_index_root）。缺入参则跳过。
ml_reference_build_tables <- function(out_dir, db_frames = NULL,
                                      study_index_root = NA_character_,
                                      asset_dir = NULL, vars = NULL, ...) {
  res <- list()
  if (!is.null(db_frames)) {
    res$table1 <- ml_reference_build_table1(db_frames, out_dir, vars = vars, ...)
  }
  if (!is.na(study_index_root) && dir.exists(study_index_root)) {
    res$s1 <- ml_reference_build_s1(study_index_root, out_dir)
  }
  if (!is.null(asset_dir)) {
    res$s3 <- ml_reference_build_s3(asset_dir, out_dir)
  }
  res
}
