###############################################################################
#  crm_nhanes_subgroup_supp — NHANES 年龄/性别/BMI 亚组加权有序 OR + Cox HR（Table S9）
#
#  依据：Han et al. 2025 JAHA e038723；本仓库设计
#  docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md
#
#  说明（本块存在的证据链背景）：此前 Decisiontree/decision_tree_crm_nhanes_mr.md
#  将本块标注为"计划注册"，但 `obs_strata` worker 实际只跑 `crm_gout_strata`
#  （见 config_crm_nhanes_mr_batch.template.R 的 branch_map$obs_strata$blocks），
#  年龄/性别/BMI 亚组此前**完全没有代码产出**——本文件补上该缺口，注册为独立 block
#  `crm_nhanes_subgroup_supp`，并接在 `crm_gout_strata` 之后加入 `obs_strata`。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data      = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  requires_packages = c("survey")；survival 由 survey 依赖自动加载
#
#  说明（分组变量与切点，证据链）：原文 Table S9 具体的亚组切点（年龄二分/BMI 三分
#  是否恰好为 65 岁 / 25 / 30 kg/m^2）在本仓库可读文本证据中未逐字确证——
#  【证据不足】。本块采用临床通行切点作为方法学默认（非文献确证复刻）：
#    - Age    : <65 / >=65
#    - Gender : Male / Female（原始编码）
#    - BMI    : <25 / 25-<30 / >=30
#  切点均可通过 config$crm_nhanes_subgroup_supp 覆盖。
#
#  说明（两套分析集，与 05/06block 一致的证据链）：每个亚组内同时报告
#    (1) Ordinal_OR：CRM_count 有序 logistic（横断面，不要求死亡随访完整，
#        分析集口径与 05block_crm_nhanes_ordinal_pub.R 一致）
#    (2) Cox_HR    ：全因死亡 Cox（要求死亡随访完整，分析集口径与
#        06block_crm_nhanes_cox_pub.R 一致）
#  暴露变量默认仅 hyperuricemia（0/1，稳定跨亚组可比）；SUA 连续暴露可选加入。
#
#  crm_nhanes_subgroup_supp = list(
#    exposures      = c("hyperuricemia"),  # 可加 "SUA"；gout 缺列时不纳入
#    outcome_col    = "CRM_count",         # Ordinal_OR 结局
#    time_var       = "futime",            # Cox_HR 时间
#    event_var      = "fustatus",          # Cox_HR 事件
#    sua_col        = "SUA",
#    eligibility_col = "eligstat",
#    age_col        = "Age", age_cut = 65,               # <65 / >=65
#    sex_col        = "Gender",
#    bmi_col        = "BMI", bmi_cuts = c(25, 30),        # <25 / 25-<30 / >=30
#    adjust_vars    = NULL,     # NULL → c("Age","Gender","BMI") ∩ 数据列，
#                                 # 分层变量本身自动从协变量中剔除（避免与分层共线）
#    weight_col     = NULL,     # NULL → config$nhanes$survey_weight %||% "new_Weight"
#    cluster_col    = NULL,     # NULL → config$nhanes$survey_cluster %||% "SDMVPSU"
#    strata_col     = NULL,     # NULL → config$nhanes$survey_strata %||% "SDMVSTRA"
#    min_stratum_n  = 20L,      # 亚组样本量低于此值跳过（不臆造小样本估计）
#    table_filename = "Table_S9_Subgroup_NHANES.csv",
#    pause_enable         = TRUE,
#    pause_on_no_output   = TRUE
#  )
#
#  register_block: "crm_nhanes_subgroup_supp"
#  典型位置: obs_strata worker：crm_gout_strata → crm_nhanes_subgroup_supp
#
#  读: ctx$data$cleaned %||% ctx$data$raw
#  写: ctx$results$crm_nhanes_subgroup_supp（tidy 长表、各亚组 analytic_n、跳过记录）
#
#  产出:
#    - [固定名] Tables/Table_S9_Subgroup_NHANES.csv
#      （StratifyVar/StratumLevel/Analysis/Exposure/Term/Estimate/Lower95/Upper95/P/N/Events）
#
#  pause: config$crm_nhanes_subgroup_supp$pause_enable
###############################################################################

#' 判定女性（与 01block_crm_nhanes_derive.R 的 .crm70d_is_female 逻辑一致；本文件
#' 独立定义一份，因为 pipeline_source_block() 按 block 名逐个 source，obs_strata
#' worker 只跑 crm_gout_strata + crm_nhanes_subgroup_supp，crm_nhanes_derive 所在的
#' 01block 文件不会被 source，不能依赖其内部 helper）。
.crm70s_is_female <- function(gender) {
  g <- tolower(trimws(as.character(gender)))
  g %in% c("f", "female", "2", "\u5973", "\u5973\u6027")
}

.crm70s_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70s_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_subgroup_supp",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_subgroup_supp halted. See ctx$results$pause_point. / ",
    "NHANES 亚组加权分析异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

#' 按 age/sex/BMI 切点派生分层标签列表：list(StratifyVar = list(level_name = logical_index))
.crm70s_build_strata <- function(data, bl_cfg) {
  strata <- list()

  age_col <- as.character(bl_cfg$age_col %||% "Age")[1L]
  if (age_col %in% names(data)) {
    age_cut <- as.numeric(bl_cfg$age_cut %||% 65)[1L]
    age_num <- suppressWarnings(as.numeric(data[[age_col]]))
    strata[["Age"]] <- list(
      lt = list(label = paste0("<", age_cut), idx = !is.na(age_num) & age_num < age_cut),
      ge = list(label = paste0(">=", age_cut), idx = !is.na(age_num) & age_num >= age_cut)
    )
  }

  sex_col <- as.character(bl_cfg$sex_col %||% "Gender")[1L]
  if (sex_col %in% names(data)) {
    is_female <- .crm70s_is_female(data[[sex_col]])
    is_known <- !is.na(data[[sex_col]])
    strata[["Sex"]] <- list(
      male = list(label = "Male", idx = is_known & !is_female),
      female = list(label = "Female", idx = is_known & is_female)
    )
  }

  bmi_col <- as.character(bl_cfg$bmi_col %||% "BMI")[1L]
  if (bmi_col %in% names(data)) {
    bmi_cuts <- as.numeric(bl_cfg$bmi_cuts %||% c(25, 30))
    bmi_cuts <- sort(bmi_cuts[!is.na(bmi_cuts)])
    if (length(bmi_cuts) == 2L) {
      bmi_num <- suppressWarnings(as.numeric(data[[bmi_col]]))
      lo <- bmi_cuts[1L]; hi <- bmi_cuts[2L]
      strata[["BMI"]] <- list(
        lo = list(label = paste0("<", lo), idx = !is.na(bmi_num) & bmi_num < lo),
        mid = list(label = paste0(lo, "-<", hi), idx = !is.na(bmi_num) & bmi_num >= lo & bmi_num < hi),
        hi = list(label = paste0(">=", hi), idx = !is.na(bmi_num) & bmi_num >= hi)
      )
    }
  }

  strata
}

.crm70s_build_design <- function(d, wt_col, psu_col, str_col) {
  has_design_cols <- all(c(psu_col, str_col) %in% names(d))
  tryCatch({
    if (has_design_cols) {
      survey::svydesign(
        ids = stats::as.formula(paste0("~", psu_col)),
        strata = stats::as.formula(paste0("~", str_col)),
        weights = stats::as.formula(paste0("~", wt_col)),
        data = d, nest = TRUE
      )
    } else {
      survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt_col)), data = d)
    }
  }, error = function(e) NULL)
}

#' 亚组内拟合 svyolr（Ordinal_OR），失败/不适用时返回 NULL（不臆造行）
.crm70s_fit_ordinal <- function(sub, y, x, covs, wt_col, psu_col, str_col, min_n) {
  need_cols <- unique(c(y, x, covs, wt_col, psu_col, str_col))
  need_cols <- intersect(need_cols, names(sub))
  d <- sub[, need_cols, drop = FALSE]
  d[[wt_col]] <- suppressWarnings(as.numeric(d[[wt_col]]))
  d[[x]] <- suppressWarnings(as.numeric(d[[x]]))
  complete_cols <- intersect(c(y, x, covs, wt_col), names(d))
  keep <- stats::complete.cases(d[, complete_cols, drop = FALSE]) & is.finite(d[[wt_col]])
  d <- d[keep, , drop = FALSE]
  d[[y]] <- factor(d[[y]], ordered = TRUE)
  if (nrow(d) < min_n || nlevels(d[[y]]) < 2L) return(NULL)

  design <- .crm70s_build_design(d, wt_col, psu_col, str_col)
  if (is.null(design)) return(NULL)

  fml <- stats::as.formula(paste0(
    y, " ~ ", x, if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
  ))
  fit <- tryCatch(survey::svyolr(fml, design = design), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  s <- summary(fit)
  ct <- s$coefficients
  if (!x %in% rownames(ct)) return(NULL)
  val <- ct[x, "Value"]; se <- ct[x, "Std. Error"]; tval <- ct[x, "t value"]
  pval <- 2 * stats::pnorm(-abs(tval))
  data.frame(
    Analysis = "Ordinal_OR", Exposure = x, Term = x,
    Estimate = exp(val), Lower95 = exp(val - 1.96 * se), Upper95 = exp(val + 1.96 * se),
    P = pval, N = nrow(d), Events = NA_integer_, stringsAsFactors = FALSE
  )
}

#' 亚组内拟合 svycoxph（Cox_HR），失败/不适用时返回 NULL（不臆造行）
.crm70s_fit_cox <- function(sub, tvar, yvar, x, covs, wt_col, psu_col, str_col, sua_col, elig_col, min_n) {
  d <- sub
  if (sua_col %in% names(d)) d <- d[!is.na(d[[sua_col]]), , drop = FALSE]
  if (elig_col %in% names(sub)) {
    d <- d[d[[elig_col]] %in% c(1, "1"), , drop = FALSE]
  } else {
    d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
    d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
    keep_fu <- !is.na(d[[tvar]]) & !is.na(d[[yvar]]) & is.finite(d[[tvar]]) & d[[tvar]] >= 0
    keep_fu[is.na(keep_fu)] <- FALSE
    d <- d[keep_fu, , drop = FALSE]
  }
  need_cols <- unique(c(tvar, yvar, x, covs, wt_col, psu_col, str_col))
  need_cols <- intersect(need_cols, names(d))
  d <- d[, need_cols, drop = FALSE]
  d[[wt_col]] <- suppressWarnings(as.numeric(d[[wt_col]]))
  d[[x]] <- suppressWarnings(as.numeric(d[[x]]))
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  complete_cols <- intersect(c(tvar, yvar, x, covs, wt_col), names(d))
  keep <- stats::complete.cases(d[, complete_cols, drop = FALSE]) & is.finite(d[[wt_col]]) &
    is.finite(d[[tvar]]) & d[[tvar]] >= 0
  d <- d[keep, , drop = FALSE]
  if (nrow(d) < min_n || length(unique(d[[x]])) < 2L) return(NULL)

  design <- .crm70s_build_design(d, wt_col, psu_col, str_col)
  if (is.null(design)) return(NULL)

  fml <- stats::as.formula(paste0(
    "survival::Surv(", tvar, ",", yvar, ") ~ ", x,
    if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
  ))
  fit <- tryCatch(survey::svycoxph(fml, design = design), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  invisible(utils::capture.output(s <- summary(fit)))
  ci <- s$conf.int
  coefs <- s$coefficients
  if (!x %in% rownames(ci)) return(NULL)
  p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
  data.frame(
    Analysis = "Cox_HR", Exposure = x, Term = x,
    Estimate = unname(ci[x, "exp(coef)"]),
    Lower95 = unname(ci[x, grep("lower", colnames(ci))[1L]]),
    Upper95 = unname(ci[x, grep("upper", colnames(ci))[1L]]),
    P = unname(coefs[x, p_col]),
    N = nrow(d), Events = sum(d[[yvar]] == 1, na.rm = TRUE), stringsAsFactors = FALSE
  )
}

block_crm_nhanes_subgroup_supp <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_subgroup_supp %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70s_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70s_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_subgroup_supp: 无分析数据。", call. = FALSE)
  }
  if (!requireNamespace("survey", quietly = TRUE)) {
    if (.crm70s_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70s_pause(ctx, "缺少 R 包 survey，无法构建加权亚组分析。",
                   "安装 survey 后重试，或设 pause_on_no_output = FALSE。", NULL)
    }
    stop("crm_nhanes_subgroup_supp: 缺少 survey 包。", call. = FALSE)
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(survival, warn.conflicts = FALSE)
  })
  options(survey.lonely.psu = "adjust")

  y <- as.character(bl_cfg$outcome_col %||% "CRM_count")[1L]
  tvar <- as.character(bl_cfg$time_var %||% "futime")[1L]
  yvar <- as.character(bl_cfg$event_var %||% "fustatus")[1L]
  sua_col <- as.character(bl_cfg$sua_col %||% "SUA")[1L]
  elig_col <- as.character(bl_cfg$eligibility_col %||% "eligstat")[1L]
  wt_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]
  psu_col <- as.character(bl_cfg$cluster_col %||% nh_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(bl_cfg$strata_col %||% nh_cfg$survey_strata %||% "SDMVSTRA")[1L]
  min_stratum_n <- as.integer(bl_cfg$min_stratum_n %||% 20L)[1L]

  exposures_cfg <- as.character(bl_cfg$exposures %||% c("hyperuricemia"))
  exposures <- exposures_cfg[exposures_cfg %in% names(data)]
  if (!length(exposures)) {
    msg <- "crm_nhanes_subgroup_supp: 配置的暴露变量均不在数据中。"
    if (.crm70s_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70s_pause(ctx, msg, "检查 config$crm_nhanes_subgroup_supp$exposures。", data)
    }
    stop(msg, call. = FALSE)
  }

  adjust_vars_cfg <- bl_cfg$adjust_vars
  m2_ctx <- setdiff(
    intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data)),
    c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
  )
  adjust_vars_base <- if (!is.null(adjust_vars_cfg) && length(adjust_vars_cfg)) {
    intersect(as.character(adjust_vars_cfg), names(data))
  } else if (length(m2_ctx)) {
    cli::cli_alert_info(
      "crm_nhanes_subgroup_supp: 使用筛选 Model2Factors ({length(m2_ctx)})"
    )
    m2_ctx
  } else {
    intersect(c("Age", "Gender", "BMI"), names(data))
  }

  strata_defs <- .crm70s_build_strata(data, bl_cfg)
  if (!length(strata_defs)) {
    msg <- "crm_nhanes_subgroup_supp: Age/Gender/BMI 均不在数据中，无法构建任何亚组。"
    if (.crm70s_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70s_pause(ctx, msg, "检查 crm_nhanes_derive 输出是否含 Age/Gender/BMI。", data)
    }
    stop(msg, call. = FALSE)
  }

  rows <- vector("list", 0L)
  skipped <- vector("list", 0L)

  for (strat_var in names(strata_defs)) {
    strat_col_used <- switch(strat_var,
      Age = as.character(bl_cfg$age_col %||% "Age")[1L],
      Sex = as.character(bl_cfg$sex_col %||% "Gender")[1L],
      BMI = as.character(bl_cfg$bmi_col %||% "BMI")[1L],
      NA_character_
    )
    covs <- setdiff(adjust_vars_base, strat_col_used)

    for (lvl in strata_defs[[strat_var]]) {
      sub <- data[lvl$idx & !is.na(lvl$idx), , drop = FALSE]
      if (nrow(sub) < min_stratum_n) {
        skipped[[length(skipped) + 1L]] <- data.frame(
          StratifyVar = strat_var, StratumLevel = lvl$label,
          reason = paste0("n=", nrow(sub), " < min_stratum_n=", min_stratum_n),
          stringsAsFactors = FALSE
        )
        next
      }
      for (x in exposures) {
        ord_row <- tryCatch(
          .crm70s_fit_ordinal(sub, y, x, covs, wt_col, psu_col, str_col, min_stratum_n),
          error = function(e) NULL
        )
        cox_row <- tryCatch(
          .crm70s_fit_cox(sub, tvar, yvar, x, covs, wt_col, psu_col, str_col, sua_col, elig_col, min_stratum_n),
          error = function(e) NULL
        )
        for (r in list(ord_row, cox_row)) {
          if (!is.null(r)) {
            r$StratifyVar <- strat_var; r$StratumLevel <- lvl$label
            rows[[length(rows) + 1L]] <- r
          }
        }
        if (is.null(ord_row) && is.null(cox_row)) {
          skipped[[length(skipped) + 1L]] <- data.frame(
            StratifyVar = strat_var, StratumLevel = lvl$label,
            reason = paste0("exposure=", x, " 拟合失败/不适用（Ordinal_OR 与 Cox_HR 均无有效模型）"),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  if (!length(rows)) {
    msg <- "crm_nhanes_subgroup_supp: 所有亚组×暴露均未能拟合有效模型（样本量不足或权重设计失败）。"
    if (.crm70s_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70s_pause(ctx, msg, "检查 min_stratum_n 设置与各亚组样本量。", data)
    }
    stop(msg, call. = FALSE)
  }

  out_tab <- do.call(rbind, rows)
  out_tab <- out_tab[, c("StratifyVar", "StratumLevel", "Analysis", "Exposure", "Term",
                          "Estimate", "Lower95", "Upper95", "P", "N", "Events")]
  out_tab$Estimate <- round(out_tab$Estimate, 3)
  out_tab$Lower95 <- round(out_tab$Lower95, 3)
  out_tab$Upper95 <- round(out_tab$Upper95, 3)
  out_tab$P_raw <- out_tab$P
  out_tab$P <- pub_format_p(out_tab$P)

  skip_tab <- if (length(skipped)) do.call(rbind, skipped) else {
    data.frame(StratifyVar = character(0), StratumLevel = character(0), reason = character(0))
  }

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_S9_Subgroup_NHANES.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(out_tab[, setdiff(names(out_tab), "P_raw")], tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_subgroup_supp CSV 写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  ctx$results$crm_nhanes_subgroup_supp <- list(
    table = out_tab[, setdiff(names(out_tab), "P_raw")],
    table_raw_p = out_tab,
    skipped = skip_tab,
    exposures = exposures,
    strata_vars = names(strata_defs),
    table_path = tbl_path
  )
  cli::cli_alert_success(
    "crm_nhanes_subgroup_supp 完成（strata_vars={paste(names(strata_defs), collapse=',')}, rows={nrow(out_tab)}, skipped={length(skipped)}）"
  )
  ctx
}

register_block(
  "crm_nhanes_subgroup_supp",
  block_crm_nhanes_subgroup_supp,
  "NHANES 年龄/性别/BMI 亚组加权 Ordinal OR + Cox HR 补充表（Table S9）"
)
