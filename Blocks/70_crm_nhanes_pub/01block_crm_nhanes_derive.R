###############################################################################
#  crm_nhanes_derive — NHANES CRM×MR 共享入排 + 派生（Task 2 / 70_crm_nhanes_pub）
#
#  依据：Han et al. 2025 JAHA e038723；本仓库设计
#  docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md
#
#  【必须核对】CKD-EPI 公式版本（2009 含种族项 vs 2021 race-free）与男女分层高尿酸
#  cut 值（single 7 mg/dL vs male 7 / female 6）本仓库均未在可读文本证据中逐字核对
#  Han 2025 JAHA e038723 Methods 原文的确切选择——当前默认值（ckd_epi_version="2009"，
#  单一 hyperuricemia cut=7）仅为保持既有 smoke/checkpoint 复现性的工程默认，
#  并非文献确证的复刻口径。正式投稿/复刻前必须对照原文 Methods 逐句核实并在此处
#  更新为已核实状态；核实前一律视为【证据不足】。
#
#  Consumes:
#    ctx$data$cleaned %||% ctx$data$raw   （data_clean 之后）
#    ctx$config$crm_nhanes_pub / $nhanes / $dual_incidence_mr
#
#  Produces (写回 ctx$data$cleaned / ctx$data$raw):
#    SUA, hyperuricemia, CVD, CKD, Diabetes, CRM_count,
#    new_Weight, futime, fustatus, 可选 gout, 可选 eGFR
#    Hyperuricemia（hyperuricemia 大写别名，始终写出）
#    Gout（gout_col 命中时为其派生值；否则 NA_integer_——【证据不足】不臆造为 0，
#          始终写出该列供 crm_gout_strata 等下游按列名读取）
#    ctx$results$crm_nhanes_derive = list(
#      n_merged=, n_age=, n_sua=, n_mort_elig=, n=, n_death=, ...
#    )  # n_merged/n_age/n_sua/n_mort_elig/n 为流程图漏斗计数，供
#       # crm_nhanes_flowchart 直接引用（见该文件说明）
#
#  config$crm_nhanes_pub 支持的键（均有默认值，全部可选）：
#    mortality_path        死亡链接 RData 路径（必填，否则 stop）
#    mortality_obj         死亡对象名，默认 "combined_data"
#    sua_col                默认 "UricAcid"
#    hyperuricemia_cut_mgdl 默认 7（男女同一 cut，即 male=female=7；配置已就绪
#                           支持男女分层：显式设置 hyperuricemia_cut_male / _female
#                           即可切换，如常见的 male=7 / female=6 定义）——
#                           【证据不足】本仓库尚未逐字核对 Han 2025 JAHA e038723
#                           Methods 是用单一 cut=7 还是男女分层 7/6；保持单一 cut=7
#                           为默认只是不改变现有 smoke 复现性的工程选择，核实前不得
#                           视为已确认的文献口径。
#    diabetes_col           默认 "T2DM"
#    cvd_cols               默认 c("MCQ160B","MCQ160C","MCQ160E","MCQ160F")
#    ckd_rule               默认 "ckd_epi"（CKD-EPI 全量实现，见下）
#    ckd_epi_version        默认 "2009"；可选 "2021"——【必须核对】Han 2025 JAHA
#                           e038723 Methods 实际采用的 CKD-EPI 版本后再决定是否切换：
#                           - "2009"：Levey 2009 含黑人种族修正项（×1.159），为保持本仓库
#                             现有 smoke/checkpoint 复现性，默认保持不变。
#                           - "2021"：CKD-EPI 2021（Inker et al. 2021 NEJM）无种族项的
#                             "race-free" 公式，现代论文更推荐使用；若切换为 "2021"，
#                             不再应用种族修正（即使 race_col 存在也忽略），
#                             ckd_race_adjusted 恒为 FALSE。
#    creatinine_col         默认 "Creatinine"
#    race_col               默认 "Race"（可选；缺失时 CKD-EPI 不做种族项调整）
#    race_black_values      默认 c("black","african american","aa","3","non-hispanic black","黑人")
#    weight_col             默认 "WTMEC2YR"
#    min_age                默认 45
#    gout_col               默认 NULL（NHANES_文献_0722.RData 目前未见痛风列——
#                           Task 1 smoke 审计 gout_candidates 为空）
#    pause_on_missing_gout  默认 FALSE（不发明痛风变量；缺列时静默跳过 gout 派生，
#                           留给下游 obs_strata / crm_gout_strata 在需要痛风分层时
#                           自行判定并标注【证据不足】，而不是在共享派生层强行 pause）
#
#  说明（CKD 证据链）：
#    - 若 creatinine_col / Age / Gender 均存在，按 ckd_epi_version 选定的 CKD-EPI
#      公式（"2009" 或 "2021"）计算 eGFR 并令 CKD = (eGFR < 60)。
#    - 若肌酐列缺失，CKD 保持 NA_integer_（不臆造），CRM_count 中 NA 视为 0 用于
#      计数上限截断前的求和；结果里会记录 ckd_available = FALSE，供下游/报告识别
#      为【证据不足】。
#    - CKD-EPI 2009 的黑人种族修正项（×1.159）仅在 ckd_epi_version="2009" 且检测到
#      可用种族列并能判定黑人身份时应用；若种族列不存在，种族项按 1（不调整）处理，
#      并在 ctx$results$crm_nhanes_derive$ckd_race_adjusted 中记录 FALSE，避免把
#      “未调整”误当成“已确认非黑人人群”。ckd_epi_version="2021" 时种族项恒不应用
#      （race-free 公式本身不含该项），ckd_race_adjusted 恒为 FALSE。
#    - 【证据不足】究竟应使用哪个版本核算本文复刻结果，需对照 Han 2025 JAHA e038723
#      Methods 原文逐句核实（见文件头“必须核对”提示）；核实前，ctx$results$
#      crm_nhanes_derive$ckd_epi_version 会原样记录实际使用的版本，供审计追溯。
###############################################################################

# ---- helpers (prefix .crm70d_) ---------------------------------------------

#' 二值化任意编码（1/"1"/TRUE/"Yes"/"Male" 等）为整数 0/1，NA 保留
#' 注意：`%in%` 本身对 NA 输入恒返回 FALSE，必须显式回填 NA，否则缺失问卷答案
#' 会被错误计为“无病”（0）。
.crm70d_as_binary <- function(x, true_vals = c(1, "1", TRUE, "Yes", "yes", "Y", "y",
                                               "TRUE", "True", "是")) {
  if (is.null(x)) return(integer(0))
  # 因子水平常带尾随空格（如 "Yes "/"No "）；统一 trim + 大小写不敏感
  xc <- trimws(as.character(x))
  tv <- unique(c(
    as.character(true_vals),
    tolower(trimws(as.character(true_vals)))
  ))
  hit <- (xc %in% tv) | (tolower(xc) %in% tolower(tv))
  out <- as.integer(hit)
  out[is.na(x) | xc %in% c("", "NA", "Na")] <- NA_integer_
  out
}

#' 判定女性（Gender 列可能是 "Male"/"Female"、"男"/"女"、1/2 等混合编码）
.crm70d_is_female <- function(gender) {
  g <- tolower(trimws(as.character(gender)))
  g %in% c("f", "female", "2", "女", "女性")
}

#' 判定黑人/非裔（用于 CKD-EPI 2009 种族修正项；缺失种族信息时整体返回 FALSE）
.crm70d_is_black <- function(race, black_values) {
  if (is.null(race)) return(rep(FALSE, 0L))
  r <- tolower(trimws(as.character(race)))
  bv <- tolower(trimws(as.character(black_values)))
  r %in% bv
}

#' CKD-EPI 2009 全量公式（Levey et al. 2009, Ann Intern Med）
#'   eGFR = 141 * min(Scr/kappa,1)^alpha * max(Scr/kappa,1)^(-1.209)
#'          * 0.993^Age * 1.018[female] * 1.159[black]
#' scr: 血肌酐 (mg/dL); age: 岁; female/black: 逻辑向量（与 scr 等长，NA 允许）
.crm70d_ckd_epi_2009 <- function(scr, age, female, black) {
  n <- length(scr)
  female <- as.logical(female); black <- as.logical(black)
  if (length(female) != n) female <- rep(female, length.out = n)
  if (length(black) != n) black <- rep(black, length.out = n)

  kappa <- ifelse(female, 0.7, 0.9)
  alpha <- ifelse(female, -0.329, -0.411)

  scr_over_kappa <- scr / kappa
  min_term <- pmin(scr_over_kappa, 1)^alpha
  max_term <- pmax(scr_over_kappa, 1)^(-1.209)

  egfr <- 141 * min_term * max_term * (0.993^age)
  egfr <- egfr * ifelse(female, 1.018, 1)
  egfr <- egfr * ifelse(black, 1.159, 1)
  egfr
}

#' CKD-EPI 2021 race-free 全量公式（Inker et al. 2021, NEJM 385:1737）
#'   eGFR = 142 * min(Scr/kappa,1)^alpha * max(Scr/kappa,1)^(-1.200)
#'          * 0.9938^Age * 1.012[female]   （无种族项）
#' scr: 血肌酐 (mg/dL); age: 岁; female: 逻辑向量（与 scr 等长，NA 允许）
.crm70d_ckd_epi_2021 <- function(scr, age, female) {
  n <- length(scr)
  female <- as.logical(female)
  if (length(female) != n) female <- rep(female, length.out = n)

  kappa <- ifelse(female, 0.7, 0.9)
  alpha <- ifelse(female, -0.241, -0.302)

  scr_over_kappa <- scr / kappa
  min_term <- pmin(scr_over_kappa, 1)^alpha
  max_term <- pmax(scr_over_kappa, 1)^(-1.200)

  egfr <- 142 * min_term * max_term * (0.9938^age)
  egfr <- egfr * ifelse(female, 1.012, 1)
  egfr
}

# ---- main block --------------------------------------------------------

block_crm_nhanes_derive <- function(ctx, ...) {
  bl <- ctx$config$crm_nhanes_pub %||% list()
  # 优先 mapped（column_mapping / dual_db 闸门 A 之后）；否则 cleaned/raw
  data <- ctx$data$mapped %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 无数据", call. = FALSE)
  }

  # ---- 1. 合并死亡链接数据（兼容 SEQN 被 column_mapping 映成 ID）----
  mort_path <- as.character(bl$mortality_path %||% "")[1L]
  if (!nzchar(mort_path) || !file.exists(mort_path)) {
    stop("crm_nhanes_derive: mortality_path 无效: ", mort_path, call. = FALSE)
  }
  me <- new.env()
  load(mort_path, envir = me)
  mort_obj <- as.character(bl$mortality_obj %||% "combined_data")[1L]
  mort <- me[[mort_obj]]
  if (is.null(mort) || !is.data.frame(mort)) {
    stop("crm_nhanes_derive: mortality_obj 未在 ", mort_path, " 中找到有效数据框: ", mort_obj, call. = FALSE)
  }
  mort_required <- c("seqn", "mortstat", "permth_int")
  mort_missing <- setdiff(mort_required, names(mort))
  if (length(mort_missing)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 死亡链接表缺少必需列: ",
         paste(mort_missing, collapse = ", "), call. = FALSE)
  }
  mort$seqn <- as.numeric(mort$seqn)
  id_cfg <- as.character(ctx$config$data$id_column %||% "SEQN")[1L]
  id_cands <- unique(c(id_cfg, "SEQN", "ID", "subject_id"))
  id_col <- id_cands[id_cands %in% names(data)][1L]
  if (!length(id_col) || is.na(id_col)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 缺少个体 ID 列（SEQN/ID）", call. = FALSE)
  }
  data$SEQN <- as.numeric(data[[id_col]])
  if (anyNA(data$SEQN)) {
    cli::cli_alert_warning(
      "crm_nhanes_derive: ID 列 {id_col} 含 NA，死亡链接可能不完整。"
    )
  }
  mort_keep <- intersect(c("seqn", "eligstat", "mortstat", "permth_int"), names(mort))
  data <- merge(data, mort[, mort_keep, drop = FALSE],
                by.x = "SEQN", by.y = "seqn", all.x = TRUE)
  n_merged <- nrow(data)

  # ---- 2. SUA / 高尿酸（兼容 column_mapping: UricAcid → Uric_Acid）----
  sua_cfg <- as.character(bl$sua_col %||% "UricAcid")[1L]
  sua_cands <- unique(c(sua_cfg, "UricAcid", "Uric_Acid", "SUA"))
  sua_col <- sua_cands[sua_cands %in% names(data)][1L]
  if (!length(sua_col) || is.na(sua_col)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 缺少 SUA 来源列: ",
         paste(sua_cands, collapse = "/"), call. = FALSE)
  }
  data$SUA <- as.numeric(data[[sua_col]])
  # 回写常用别名，供下游默认协变量池（Smoke/TG）与配置 sua_col 对齐
  if (!"UricAcid" %in% names(data)) data$UricAcid <- data$SUA
  if ("Smoking" %in% names(data) && !"Smoke" %in% names(data)) data$Smoke <- data$Smoking
  if ("Triglycerides" %in% names(data) && !"TG" %in% names(data)) data$TG <- data$Triglycerides
  if ("Smoking" %in% names(data) == FALSE && "Smoke" %in% names(data)) data$Smoking <- data$Smoke
  if ("Triglycerides" %in% names(data) == FALSE && "TG" %in% names(data)) {
    data$Triglycerides <- data$TG
  }

  female_vec <- .crm70d_is_female(data$Gender %||% NA)
  cut_default <- as.numeric(bl$hyperuricemia_cut_mgdl %||% 7)[1L]
  cut_male <- as.numeric(bl$hyperuricemia_cut_male %||% cut_default)[1L]
  cut_female <- as.numeric(bl$hyperuricemia_cut_female %||% cut_default)[1L]
  hyper_cut <- ifelse(female_vec, cut_female, cut_male)
  data$hyperuricemia <- as.integer(data$SUA >= hyper_cut)
  # Hyperuricemia：hyperuricemia 的大写别名，供 57_dual_incidence_mr_full/crm_gout_strata
  # 等消费方按其既有列名约定读取（该 block 不在本任务改动范围内）。
  data$Hyperuricemia <- data$hyperuricemia

  # ---- 3. CRM 组分 ----
  # Diabetes: T2DM
  diabetes_col <- as.character(bl$diabetes_col %||% "T2DM")[1L]
  data$Diabetes <- if (diabetes_col %in% names(data)) {
    .crm70d_as_binary(data[[diabetes_col]])
  } else {
    NA_integer_
  }

  # CVD: MCQ160B/C/E/F 任一为 1；缺失问卷答案不得被当作“无病”（0）——
  # 规则：任一列命中 1 → CVD=1（即使其它列缺失）；无命中但存在缺失列 → CVD=NA；
  # 全部列均为非缺失且非命中 → CVD=0。
  cvd_cols <- as.character(bl$cvd_cols %||% c("MCQ160B", "MCQ160C", "MCQ160E", "MCQ160F"))
  cvd_cols <- cvd_cols[cvd_cols %in% names(data)]
  data$CVD <- if (length(cvd_cols)) {
    hit <- vapply(cvd_cols, function(cc) data[[cc]] %in% c(1, "1"), logical(nrow(data)))
    if (is.null(dim(hit))) hit <- matrix(hit, nrow = nrow(data))
    na_mat <- vapply(cvd_cols, function(cc) is.na(data[[cc]]), logical(nrow(data)))
    if (is.null(dim(na_mat))) na_mat <- matrix(na_mat, nrow = nrow(data))
    any_hit <- rowSums(hit, na.rm = TRUE) > 0
    any_na <- rowSums(na_mat) > 0
    ifelse(any_hit, 1L, ifelse(any_na, NA_integer_, 0L))
  } else {
    NA_integer_
  }

  # CKD: CKD-EPI 全公式（肌酐 + 年龄 + 性别 [+ 种族可选，仅 2009 版]）
  ckd_rule <- as.character(bl$ckd_rule %||% "ckd_epi")[1L]
  ckd_epi_version <- as.character(bl$ckd_epi_version %||% "2009")[1L]
  if (!ckd_epi_version %in% c("2009", "2021")) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive ckd_epi_version 仅支持 \"2009\"/\"2021\"，收到: ",
         ckd_epi_version, call. = FALSE)
  }
  creat_col <- as.character(bl$creatinine_col %||% "Creatinine")[1L]
  race_col <- as.character(bl$race_col %||% "Race")[1L]
  race_black_values <- as.character(
    bl$race_black_values %||%
      c("black", "african american", "aa", "3", "non-hispanic black", "黑人")
  )

  data$CKD <- NA_integer_
  ckd_available <- FALSE
  ckd_race_adjusted <- FALSE
  if (identical(ckd_rule, "ckd_epi") &&
      all(c(creat_col, "Age", "Gender") %in% names(data))) {
    scr <- as.numeric(data[[creat_col]])
    age <- as.numeric(data$Age)
    female_ckd <- .crm70d_is_female(data$Gender)
    if (identical(ckd_epi_version, "2021")) {
      # CKD-EPI 2021 race-free：不应用种族修正项（公式本身不含该项）
      egfr <- .crm70d_ckd_epi_2021(scr, age, female_ckd)
      ckd_race_adjusted <- FALSE
    } else {
      if (race_col %in% names(data)) {
        black_ckd <- .crm70d_is_black(data[[race_col]], race_black_values)
        ckd_race_adjusted <- TRUE
      } else {
        black_ckd <- rep(FALSE, nrow(data))
        ckd_race_adjusted <- FALSE
      }
      egfr <- .crm70d_ckd_epi_2009(scr, age, female_ckd, black_ckd)
    }
    egfr[!is.finite(egfr) | is.na(scr) | is.na(age)] <- NA_real_
    data$eGFR <- egfr
    data$CKD <- as.integer(egfr < 60)
    ckd_available <- TRUE
  }

  # CRM_count：CVD/CKD/Diabetes 三者任一为 NA 时，计数本身不可信，必须为 NA
  # （不得将缺失问卷/缺失肌酐等同于“无病”参与求和）；`rowSums(na.rm = FALSE)`
  # 天然满足“任一 NA 则整行 NA”的语义。
  crm_mat <- cbind(data$CVD, data$CKD, data$Diabetes)
  crm_sum <- rowSums(crm_mat)
  data$CRM_count <- ifelse(is.na(crm_sum), NA_integer_, pmin(as.integer(crm_sum), 3L))

  # ---- 4. 权重 / 随访 ----
  wt_col <- as.character(bl$weight_col %||% "WTMEC2YR")[1L]
  if (!wt_col %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 缺少权重列: ", wt_col, call. = FALSE)
  }
  data$new_Weight <- as.numeric(data[[wt_col]])
  data$futime <- as.numeric(data$permth_int)
  data$fustatus <- as.integer(data$mortstat == 1)

  # ---- 5. 年龄入排（中老年，默认 >=45） ----
  min_age <- as.numeric(bl$min_age %||% 45)[1L]
  if (!"Age" %in% names(data)) {
    stop("PAUSE_FOR_USER_DECISION: crm_nhanes_derive 缺少 Age 列，无法应用年龄入排", call. = FALSE)
  }
  data <- data[!is.na(data$Age) & data$Age >= min_age, , drop = FALSE]
  n_age <- nrow(data)

  # ---- 5b. 流程图漏斗计数（仅计数，不对 ctx$data 做二次过滤；下游各 worker 仍按
  #      自身列的非缺失情况自行过滤）：SUA 非缺失 → 死亡随访合格 → 分析集(CRM_count 有值) ----
  n_sua <- sum(!is.na(data$SUA))
  .after_sua <- data[!is.na(data$SUA), , drop = FALSE]

  if ("eligstat" %in% names(.after_sua)) {
    .keep_elig <- .after_sua$eligstat %in% c(1, "1")
  } else if (all(c("futime", "fustatus") %in% names(.after_sua))) {
    .keep_elig <- !is.na(.after_sua$futime) & !is.na(.after_sua$fustatus) &
      suppressWarnings(as.numeric(.after_sua$futime)) >= 0
    .keep_elig[is.na(.keep_elig)] <- FALSE
  } else {
    .keep_elig <- rep(TRUE, nrow(.after_sua))
  }
  n_mort_elig <- sum(.keep_elig)
  .after_elig <- .after_sua[.keep_elig, , drop = FALSE]

  n_analytic <- sum(!is.na(.after_elig$CRM_count))

  # ---- 6. 痛风（可选；NHANES_文献_0722.RData 当前无痛风列） ----
  # Task 1 审计：gout_candidates 为空，
  # 因此默认不 pause、不臆造 gout：仅当用户显式配置 gout_col 且列存在时才派生；
  # 若确需痛风分层（obs_strata / crm_gout_strata）而列仍缺失，由该下游 worker
  # 自行判定并在报告中标注【证据不足】，而不是在共享派生层强行阻断整条 pipeline。
  gout_col <- bl$gout_col
  gout_available <- FALSE
  gout_proxy_note <- NA_character_
  if (!is.null(gout_col) && nzchar(as.character(gout_col)[1L]) && gout_col %in% names(data)) {
    data$gout <- .crm70d_as_binary(data[[gout_col]])
    gout_available <- TRUE
  } else if (!is.null(bl$gout_proxy_sua_cut) && is.finite(as.numeric(bl$gout_proxy_sua_cut)[1L])) {
    # 数据无痛风问卷列时的临床代理：SUA >= cut（默认 8 mg/dL，近似“重度高尿酸/痛风样”）
    # 【证据不足】非原文痛风定义，仅用于补齐分层臂；产出表需标注 proxy。
    cut_g <- as.numeric(bl$gout_proxy_sua_cut)[1L]
    data$gout <- as.integer(!is.na(data$SUA) & data$SUA >= cut_g)
    gout_available <- TRUE
    gout_proxy_note <- sprintf("SUA_ge_%.2f_proxy", cut_g)
  } else if (isTRUE(bl$pause_on_missing_gout %||% FALSE)) {
    stop("PAUSE_FOR_USER_DECISION: 无痛风列，见 crm_nhanes_pub$gout_col / gout_proxy_sua_cut", call. = FALSE)
  }
  # Gout：始终写出大写别名列，供 crm_gout_strata（57_dual_incidence_mr_full）分层消费。
  # 痛风列缺失且无 proxy 时【证据不足】——保持 NA；有 proxy 时写入 0/1 并在 results 记录代理规则。
  data$Gout <- if (gout_available) data$gout else NA_integer_

  ctx$data$cleaned <- data
  ctx$data$raw <- data
  ctx$data$mapped <- data
  ctx$results$crm_nhanes_derive <- list(
    # 漏斗计数（供 crm_nhanes_flowchart 直接引用，避免下游重算/编造）：
    #   n_merged    合并死亡链接后（年龄入排前）
    #   n_age       年龄入排(Age >= min_age)后
    #   n_sua       SUA 非缺失
    #   n_mort_elig 死亡随访合格（eligstat==1，或退化为 futime/fustatus 非缺失）
    #   n           最终分析集（CRM_count 有值）＝流程图末框
    n_merged = n_merged,
    n_age = n_age,
    n_sua = n_sua,
    n_mort_elig = n_mort_elig,
    n = n_analytic,
    n_death = sum(data$fustatus == 1, na.rm = TRUE),
    ckd_available = ckd_available,
    ckd_epi_version = ckd_epi_version,
    ckd_race_adjusted = ckd_race_adjusted,
    gout_available = gout_available,
    gout_proxy_note = gout_proxy_note,
    min_age = min_age
  )
  cli::cli_alert_success(
    "crm_nhanes_derive n_merged={n_merged} n_age={n_age} n_sua={n_sua} n_mort_elig={n_mort_elig} n(analytic)={n_analytic} (ckd_available={ckd_available}, ckd_epi_version={ckd_epi_version}, gout_available={gout_available})"
  )
  ctx
}

register_block("crm_nhanes_derive", block_crm_nhanes_derive, "NHANES CRM 派生（合并死亡链接 + SUA/CVD/CKD/Diabetes/CRM_count/权重/随访/年龄入排/可选痛风）")
