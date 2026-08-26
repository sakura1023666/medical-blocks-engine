###############################################################################
#  crm_nhanes_cox_pub — NHANES 加权 Cox 发表表（正表 Table 2 / 原文 Table 4）
#  按 CRM_count 分层（0/1/2/3/≥1），暴露为：
#    连续 SUA；Asymptomatic hyperuricemia；Gout with normal UA；
#    Gout with poorly-controlled hyperuricemia（对照：无高尿酸且无痛风）
#  模型：Crude / Model 1 / Model 2
#
#  说明（gout 证据链）：本库 gout 常为 SUA≥8 代理（见 crm_nhanes_derive$gout_proxy_note）。
#  此时「Gout with normal UA」与代理定义互斥，该列为空并在脚注标明——【证据不足】相对原文
#  真实痛风诊断口径。
###############################################################################

.crm70c_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70c_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_cox_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_cox_pub halted. See ctx$results$pause_point. / ",
    "NHANES 加权 Cox 发表表异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.crm70c_apply_analytic_filters <- function(data, tvar, yvar, sua_col, elig_col) {
  d <- data
  if (sua_col %in% names(d)) d <- d[!is.na(d[[sua_col]]), , drop = FALSE]
  if (elig_col %in% names(data)) {
    d <- d[d[[elig_col]] %in% c(1, "1"), , drop = FALSE]
  }
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  if (!elig_col %in% names(data)) {
    keep_fu <- !is.na(d[[tvar]]) & !is.na(d[[yvar]]) & is.finite(d[[tvar]]) & d[[tvar]] >= 0
    keep_fu[is.na(keep_fu)] <- FALSE
    d <- d[keep_fu, , drop = FALSE]
  }
  d[is.finite(d[[tvar]]) & d[[tvar]] >= 0 & !is.na(d[[yvar]]), , drop = FALSE]
}

.crm70c_build_design <- function(d, wt_col, psu_col, str_col) {
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

.crm70c_fmt_hr_stars <- function(hr, lo, hi, p) {
  hr <- suppressWarnings(as.numeric(hr))
  lo <- suppressWarnings(as.numeric(lo))
  hi <- suppressWarnings(as.numeric(hi))
  p <- suppressWarnings(as.numeric(p))
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) return("")
  stars <- if (is.finite(p) && p < 0.01) "**" else if (is.finite(p) && p < 0.05) "*" else ""
  sprintf("%.3f (%.3f–%.3f)%s", hr, lo, hi, stars)
}

#' 拟合 svycoxph，提取单一项（连续或指定因子水平）的 HR/CI/P
.crm70c_extract_one <- function(design, tvar, yvar, term_expr, covs, coef_name = NULL) {
  fml <- stats::as.formula(paste0(
    "survival::Surv(", tvar, ",", yvar, ") ~ ", term_expr,
    if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
  ))
  fit <- tryCatch(survey::svycoxph(fml, design = design), error = function(e) {
    cli::cli_alert_warning("crm_nhanes_cox_pub: svycoxph({term_expr}) 失败: {e$message}")
    NULL
  })
  if (is.null(fit)) {
    return(list(HR = NA_real_, Lower95 = NA_real_, Upper95 = NA_real_, P = NA_real_))
  }
  invisible(utils::capture.output(s <- summary(fit)))
  ci <- s$conf.int
  coefs <- s$coefficients
  if (is.null(ci) || !nrow(ci)) {
    return(list(HR = NA_real_, Lower95 = NA_real_, Upper95 = NA_real_, P = NA_real_))
  }
  rn <- rownames(ci)
  pick <- if (!is.null(coef_name) && nzchar(coef_name)) {
    hit <- which(rn == coef_name | endsWith(rn, coef_name) | grepl(coef_name, rn, fixed = TRUE))
    if (length(hit)) hit[1L] else NA_integer_
  } else {
    1L
  }
  if (!is.finite(pick)) {
    return(list(HR = NA_real_, Lower95 = NA_real_, Upper95 = NA_real_, P = NA_real_))
  }
  p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
  lo_col <- grep("lower", colnames(ci), ignore.case = TRUE)[1L]
  hi_col <- grep("upper", colnames(ci), ignore.case = TRUE)[1L]
  list(
    HR = unname(ci[pick, "exp(coef)"]),
    Lower95 = unname(ci[pick, lo_col]),
    Upper95 = unname(ci[pick, hi_col]),
    P = unname(coefs[rn[pick], p_col])
  )
}

.crm70c_make_ua_gout_group <- function(d, hu_col, gout_col) {
  hu <- suppressWarnings(as.integer(d[[hu_col]]))
  gt <- suppressWarnings(as.integer(d[[gout_col]]))
  out <- rep(NA_character_, nrow(d))
  ok <- !is.na(hu) & !is.na(gt)
  out[ok & hu == 0L & gt == 0L] <- "Ref_no_HU_gout"
  out[ok & hu == 1L & gt == 0L] <- "Asymptomatic_HU"
  out[ok & hu == 0L & gt == 1L] <- "Gout_normal_UA"
  out[ok & hu == 1L & gt == 1L] <- "Gout_poor_HU"
  factor(
    out,
    levels = c("Ref_no_HU_gout", "Asymptomatic_HU", "Gout_normal_UA", "Gout_poor_HU")
  )
}

block_crm_nhanes_cox_pub <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_cox_pub %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70c_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70c_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_cox_pub: 无分析数据。", call. = FALSE)
  }
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("crm_nhanes_cox_pub: 缺少 survey 包。", call. = FALSE)
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(survival, warn.conflicts = FALSE)
  })
  options(survey.lonely.psu = "adjust")

  crm_var <- as.character(bl_cfg$crm_var %||% "CRM_count")[1L]
  tvar <- as.character(bl_cfg$time_var %||% "futime")[1L]
  yvar <- as.character(bl_cfg$event_var %||% "fustatus")[1L]
  sua_col <- as.character(bl_cfg$sua_col %||% "SUA")[1L]
  hu_col <- as.character(bl_cfg$hu_col %||% "hyperuricemia")[1L]
  gout_col <- as.character(bl_cfg$gout_col %||% "gout")[1L]
  elig_col <- as.character(bl_cfg$eligibility_col %||% "eligstat")[1L]
  wt_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]
  psu_col <- as.character(bl_cfg$cluster_col %||% nh_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(bl_cfg$strata_col %||% nh_cfg$survey_strata %||% "SDMVSTRA")[1L]

  need <- unique(c(crm_var, tvar, yvar, sua_col, wt_col))
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    stop("crm_nhanes_cox_pub: 数据缺少列: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  has_hu <- hu_col %in% names(data)
  has_gout <- gout_col %in% names(data) && !all(is.na(data[[gout_col]]))
  if (!has_hu || !has_gout) {
    cli::cli_alert_warning(
      "crm_nhanes_cox_pub: 缺 hyperuricemia/gout，分类暴露列将为空（不臆造）。"
    )
  }

  model1_default <- c("Age", "Gender", "Race")
  model2_default <- c(
    "Age", "Gender", "Race", "Education", "PIR", "BMI",
    "Hypertension", "Smoke", "eGFR", "TG"
  )
  strip_exp <- c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
  m1_ctx <- setdiff(intersect(as.character(ctx$results$Model1Factors %||% character(0)), names(data)), strip_exp)
  m2_ctx <- setdiff(intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data)), strip_exp)
  model1_vars <- if (!is.null(bl_cfg$model1_vars) && length(bl_cfg$model1_vars)) {
    intersect(as.character(bl_cfg$model1_vars), names(data))
  } else if (length(m1_ctx)) {
    m1_ctx
  } else intersect(model1_default, names(data))
  model2_vars <- if (!is.null(bl_cfg$model2_vars) && length(bl_cfg$model2_vars)) {
    intersect(as.character(bl_cfg$model2_vars), names(data))
  } else if (!is.null(bl_cfg$adjust_vars) && length(bl_cfg$adjust_vars)) {
    intersect(as.character(bl_cfg$adjust_vars), names(data))
  } else if (length(m2_ctx)) {
    m2_ctx
  } else intersect(model2_default, names(data))

  if (length(m2_ctx)) {
    cli::cli_alert_info(
      "crm_nhanes_cox_pub: 使用筛选 Model2Factors ({length(model2_vars)}): {paste(model2_vars, collapse=', ')}"
    )
  }
  miss_m2 <- setdiff(model2_default, model2_vars)
  if (length(miss_m2) && !length(m2_ctx)) {
    cli::cli_alert_warning(
      "crm_nhanes_cox_pub: Model2 缺列: {paste(miss_m2, collapse=', ')}；用可得列拟合。"
    )
  }

  keep_cols <- unique(c(
    need, hu_col, gout_col, elig_col, psu_col, str_col, model1_vars, model2_vars
  ))
  keep_cols <- intersect(keep_cols, names(data))
  d0 <- data[, keep_cols, drop = FALSE]
  d0 <- .crm70c_apply_analytic_filters(d0, tvar, yvar, sua_col, elig_col)
  d0[[wt_col]] <- suppressWarnings(as.numeric(d0[[wt_col]]))
  d0[[sua_col]] <- suppressWarnings(as.numeric(d0[[sua_col]]))
  d0[[crm_var]] <- suppressWarnings(as.integer(d0[[crm_var]]))
  complete_cols <- intersect(c(crm_var, tvar, yvar, sua_col, wt_col, model2_vars), names(d0))
  keep <- stats::complete.cases(d0[, complete_cols, drop = FALSE]) & is.finite(d0[[wt_col]])
  d <- d0[keep, , drop = FALSE]
  if (!nrow(d)) {
    stop("crm_nhanes_cox_pub: 有效分析集为空。", call. = FALSE)
  }

  if (has_hu && has_gout) {
    d$ua_gout_grp <- .crm70c_make_ua_gout_group(d, hu_col, gout_col)
  } else {
    d$ua_gout_grp <- factor(NA_character_)
  }
  gout_proxy_note <- tryCatch(
    ctx$results$crm_nhanes_derive$gout_proxy_note %||% NA_character_,
    error = function(e) NA_character_
  )

  strata_spec <- list(
    list(label = "0 CRM", levels = 0L),
    list(label = "1 CRM", levels = 1L),
    list(label = "2 CRM", levels = 2L),
    list(label = "3 CRM", levels = 3L),
    list(label = ">=1 CRM", levels = c(1L, 2L, 3L))
  )
  model_specs <- list(
    list(name = "Crude", covs = character(0)),
    list(name = "Model 1", covs = model1_vars),
    list(name = "Model 2", covs = model2_vars)
  )
  cat_levels <- c("Asymptomatic_HU", "Gout_normal_UA", "Gout_poor_HU")
  cat_colnames <- c(
    "Asymptomatic hyperuricemia",
    "Gout with normal UA",
    "Gout with poorly-controlled hyperuricemia"
  )

  long_rows <- list()
  wide_rows <- list()

  for (ss in strata_spec) {
    dsub <- d[d[[crm_var]] %in% ss$levels, , drop = FALSE]
    n_sub <- nrow(dsub)
    n_ev <- sum(dsub[[yvar]] == 1, na.rm = TRUE)
    sec_lab <- sprintf("%s (n=%d)", ss$label, n_sub)
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Model = sec_lab,
      `Serum uric acid (mg/dL)` = "",
      `Asymptomatic hyperuricemia` = "",
      `Gout with normal UA` = "",
      `Gout with poorly-controlled hyperuricemia` = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )

    if (n_sub < 30L || n_ev < 5L) {
      cli::cli_alert_warning("crm_nhanes_cox_pub: {sec_lab} 样本量/事件不足，跳过拟合。")
      for (ms in model_specs) {
        wide_rows[[length(wide_rows) + 1L]] <- data.frame(
          Model = ms$name,
          `Serum uric acid (mg/dL)` = "",
          `Asymptomatic hyperuricemia` = "",
          `Gout with normal UA` = "",
          `Gout with poorly-controlled hyperuricemia` = "",
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
      next
    }

    for (ms in model_specs) {
      # 连续 SUA：本层全部人
      design_sua <- .crm70c_build_design(dsub, wt_col, psu_col, str_col)
      sua_res <- if (!is.null(design_sua)) {
        .crm70c_extract_one(design_sua, tvar, yvar, sua_col, ms$covs, coef_name = sua_col)
      } else list(HR = NA, Lower95 = NA, Upper95 = NA, P = NA)
      sua_cell <- .crm70c_fmt_hr_stars(sua_res$HR, sua_res$Lower95, sua_res$Upper95, sua_res$P)
      long_rows[[length(long_rows) + 1L]] <- data.frame(
        Stratum = ss$label, N = n_sub, Events = n_ev, Model = ms$name,
        Exposure = "SUA", HR = sua_res$HR, Lower95 = sua_res$Lower95,
        Upper95 = sua_res$Upper95, P = sua_res$P, stringsAsFactors = FALSE
      )

      cat_cells <- setNames(rep("", length(cat_levels)), cat_colnames)
      # 对各分类暴露：仅保留「参照 + 该暴露」做二分类 Cox（对照=无高尿酸且无痛风）
      # 避免空水平（如 gout 代理下 Gout_normal_UA=0）导致 factor 奇异
      for (ii in seq_along(cat_levels)) {
        lv <- cat_levels[[ii]]
        cn <- cat_colnames[[ii]]
        dbin <- dsub[!is.na(dsub$ua_gout_grp) &
                       dsub$ua_gout_grp %in% c("Ref_no_HU_gout", lv), , drop = FALSE]
        dbin$ua_gout_grp <- droplevels(factor(
          as.character(dbin$ua_gout_grp),
          levels = c("Ref_no_HU_gout", lv)
        ))
        n_exp <- sum(dbin$ua_gout_grp == lv, na.rm = TRUE)
        n_ref <- sum(dbin$ua_gout_grp == "Ref_no_HU_gout", na.rm = TRUE)
        n_ev_bin <- sum(dbin[[yvar]] == 1, na.rm = TRUE)
        if (n_exp < 5L || n_ref < 5L || n_ev_bin < 3L || nlevels(dbin$ua_gout_grp) < 2L) {
          cat_cells[[cn]] <- ""
          long_rows[[length(long_rows) + 1L]] <- data.frame(
            Stratum = ss$label, N = n_sub, Events = n_ev, Model = ms$name,
            Exposure = lv, HR = NA_real_, Lower95 = NA_real_,
            Upper95 = NA_real_, P = NA_real_, stringsAsFactors = FALSE
          )
          next
        }
        design_bin <- .crm70c_build_design(dbin, wt_col, psu_col, str_col)
        if (is.null(design_bin)) {
          cat_cells[[cn]] <- ""
          next
        }
        res_bin <- .crm70c_extract_one(
          design_bin, tvar, yvar, "ua_gout_grp", ms$covs, coef_name = lv
        )
        cat_cells[[cn]] <- .crm70c_fmt_hr_stars(
          res_bin$HR, res_bin$Lower95, res_bin$Upper95, res_bin$P
        )
        long_rows[[length(long_rows) + 1L]] <- data.frame(
          Stratum = ss$label, N = n_sub, Events = n_ev, Model = ms$name,
          Exposure = lv, HR = res_bin$HR, Lower95 = res_bin$Lower95,
          Upper95 = res_bin$Upper95, P = res_bin$P, stringsAsFactors = FALSE
        )
      }

      wide_rows[[length(wide_rows) + 1L]] <- data.frame(
        Model = ms$name,
        `Serum uric acid (mg/dL)` = sua_cell,
        `Asymptomatic hyperuricemia` = cat_cells[["Asymptomatic hyperuricemia"]],
        `Gout with normal UA` = cat_cells[["Gout with normal UA"]],
        `Gout with poorly-controlled hyperuricemia` =
          cat_cells[["Gout with poorly-controlled hyperuricemia"]],
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }

  out_long <- if (length(long_rows)) do.call(rbind, long_rows) else data.frame()
  if (nrow(out_long)) {
    out_long$HR <- round(out_long$HR, 3)
    out_long$Lower95 <- round(out_long$Lower95, 3)
    out_long$Upper95 <- round(out_long$Upper95, 3)
    out_long$P_fmt <- pub_format_p(out_long$P)
  }
  wide_tab <- do.call(rbind, wide_rows)
  rownames(wide_tab) <- NULL

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_4_Cox_NHANES.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(out_long, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_cox_pub CSV 写出失败: {e$message}")
  )
  wide_csv <- file.path(tbl_dir, "Table_2_Cox_NHANES_wide.csv")
  tryCatch(
    utils::write.csv(wide_tab, wide_csv, row.names = FALSE),
    error = function(e) NULL
  )

  pub_xlsx <- as.character(
    bl_cfg$pub_xlsx_filename %||%
      "Table 2-NHANES. Weighted Cox HR by CRM.xlsx"
  )[1L]
  pub_title <- as.character(
    bl_cfg$pub_title %||%
      paste0(
        "Table 2-NHANES. Weighted hazard ratios (95% CIs) for all-cause mortality ",
        "according to serum uric acid, hyperuricemia, and gout among participants ",
        "with different CRM conditions"
      )
  )[1L]
  footnotes <- bl_cfg$table_footnotes %||% {
    ft <- c(
      "CRM indicates cardiac, renal, and metabolic; NHANES, National Health and Nutrition Examination Survey.",
      paste0(
        "Model 1: Adjusted for age, sex, and race",
        if (length(model1_vars)) paste0(" (used: ", paste(model1_vars, collapse = ", "), ")") else "",
        "."
      ),
      paste0(
        "Model 2: Adjusted for age, sex, race, education, poverty, body mass index, ",
        "hypertension, smoking status, eGFR, and triglyceride",
        if (length(model2_vars)) paste0(" (used: ", paste(model2_vars, collapse = ", "), ")") else "",
        "."
      ),
      paste0(
        "Comparison group for categorical columns: participants without hyperuricemia or gout."
      ),
      "*P<0.05; **P<0.01."
    )
    if (!is.na(gout_proxy_note) && nzchar(gout_proxy_note)) {
      ft <- c(
        ft,
        paste0(
          "Note: gout was derived as a proxy (", gout_proxy_note,
          "); \"Gout with normal UA\" is empty under this proxy definition ",
          "(evidence insufficient vs paper clinical gout)."
        )
      )
    }
    ft
  }

  xlsx_path <- file.path(tbl_dir, pub_xlsx)
  if (exists("export_sci_table", mode = "function")) {
    # 单行表头（列名即暴露）；CRM 分层行作为表体首列
    tryCatch(
      export_sci_table(
        wide_tab, xlsx_path, title = pub_title,
        excel_use_prepared = FALSE,
        table_footnotes = footnotes
      ),
      error = function(e) cli::cli_alert_warning("crm_nhanes_cox_pub xlsx 导出失败: {e$message}")
    )
  }
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
    if (file.exists(xlsx_path)) mirror_pub_output_to_root(ctx, xlsx_path)
  }

  ctx$results$crm_nhanes_cox_pub <- list(
    table = out_long,
    table_wide = wide_tab,
    model1_vars = model1_vars,
    model2_vars = model2_vars,
    analytic_n = nrow(d),
    analytic_events = sum(d[[yvar]] == 1, na.rm = TRUE),
    gout_available = has_gout,
    gout_proxy_note = gout_proxy_note,
    table_path = tbl_path,
    pub_xlsx_path = xlsx_path
  )
  cli::cli_alert_success(
    "crm_nhanes_cox_pub 完成（n={nrow(d)}, events={sum(d[[yvar]]==1, na.rm=TRUE)}, paper-Table4 layout）"
  )
  ctx
}

register_block(
  "crm_nhanes_cox_pub",
  block_crm_nhanes_cox_pub,
  "NHANES 加权 Cox 发表宽表（正表 Table 2 / 原文 Table 4：CRM 分层 × SUA/痛风暴露）"
)
