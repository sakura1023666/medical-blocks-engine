###############################################################################
#  mediation_longitudinal — 纵向中介（X 基线暴露 → M 中间中介 → Y 晚波结局）
#
#  出版：Table S7（Cohort × Total/Direct/Indirect / Path a/b / Proportion）
#  图：马卡龙色系路径三角图（复用 .mp01_draw_mediation_path_diagram）
#
#  mediation_longitudinal = list(
#    treat = "FI",
#    mediator = "Depression_cont",
#    outcome = "Disease_Group",
#    outcome_event_level = "Hip_Fracture",
#    covariates = NULL,
#    path_use_covariates = TRUE,   # 纵向主文默认开（对齐原文调整）
#    sims = 1000, seed = 1000,
#    cohorts_col = "Cohort",
#    diagram_enable = TRUE,
#    treat_label / mediator_label / outcome_label
#  ),
#
#  register_block: "mediation_longitudinal"
###############################################################################

block_mediation_longitudinal <- function(ctx, ...) {
  suppressPackageStartupMessages({
    if (!requireNamespace("mediation", quietly = TRUE))
      stop("mediation_longitudinal: 需要 mediation 包", call. = FALSE)
    if (!requireNamespace("openxlsx", quietly = TRUE))
      stop("mediation_longitudinal: 需要 openxlsx 包", call. = FALSE)
  })

  cfg <- ctx$config
  bl <- cfg$mediation_longitudinal %||% list()
  data <- ctx$data$longitudinal_mediation %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("mediation_longitudinal: 无数据。请先跑 cross_lagged_long_prepare 或提供 imputed。", call. = FALSE)

  treat <- bl[["treat"]] %||% cfg$incidence$index_var %||% "FI"
  mediator <- bl[["mediator"]] %||% "Depression_cont"
  outcome <- bl[["outcome"]] %||% cfg$data$outcome_column %||% "Disease_Group"
  event_lvl <- bl[["outcome_event_level"]] %||% cfg$project$analysis_group %||% "Hip_Fracture"
  treat_lab <- bl[["treat_label"]] %||% "Frailty Index"
  med_lab <- bl[["mediator_label"]] %||% "Depression"
  out_lab <- bl[["outcome_label"]] %||% gsub("_", " ", as.character(event_lvl), fixed = TRUE)
  sims <- as.integer(bl[["sims"]] %||% 1000L)
  seed <- as.integer(bl[["seed"]] %||% 1000L)

  # 纵向默认用协变量（path_use_covariates 缺省 TRUE）；仍尊重显式 FALSE
  if (is.null(bl[["path_use_covariates"]]) && is.null(bl[["use_path_covariates"]])) {
    bl$path_use_covariates <- TRUE
  }
  # 优先：按库锁定（depression 中介筛出的 best set）
  db_name <- as.character(cfg$project$database %||% "")[1L]
  covars_by_db <- bl[["covariates_by_db"]] %||% ctx$results$mediation_covars_by_db %||% NULL
  covars <- character(0)
  if (is.list(covars_by_db) && nzchar(db_name) && db_name %in% names(covars_by_db)) {
    covars <- as.character(covars_by_db[[db_name]] %||% character(0))
  }
  if (!length(covars) && exists("pipeline_mediation_resolve_path_covariates", mode = "function")) {
    covars <- pipeline_mediation_resolve_path_covariates(cfg, bl, names(data), ctx = ctx)
  }
  if (isTRUE(bl[["path_use_covariates"]] %||% bl[["use_path_covariates"]] %||% TRUE) && !length(covars)) {
    covars <- bl[["covariates"]]
    if (is.null(covars)) covars <- ctx$results$Model2Factors %||% character(0)
  }
  covars <- setdiff(as.character(covars), c(treat, mediator, outcome))

  need <- c(treat, mediator, outcome)
  miss <- setdiff(need, names(data))
  if (length(miss))
    stop("mediation_longitudinal: 缺列 ", paste(miss, collapse = ", "), call. = FALSE)
  covars <- covars[covars %in% names(data)]
  if (length(setdiff(as.character(bl[["covariates"]] %||% character(0)), names(data)))) {
    miss_cov <- setdiff(as.character(bl[["covariates"]] %||% character(0)), names(data))
    cli::cli_alert_warning(
      "mediation_longitudinal: 协变量列缺失（已跳过）: {paste(miss_cov, collapse = ', ')}"
    )
  }

  y_raw <- data[[outcome]]
  if (is.numeric(y_raw) || is.integer(y_raw)) {
    data$.__y_bin <- as.integer(y_raw == 1L)
  } else {
    data$.__y_bin <- as.integer(as.character(y_raw) == as.character(event_lvl))
  }

  cohort_col <- bl[["cohorts_col"]] %||% "Cohort"
  db_name <- as.character(cfg$project$database %||% "")[1L]
  # Pooled / 显式 force_single：整表一次拟合（Country 进协变量）
  force_single <- isTRUE(bl[["force_single_cohort"]]) ||
    identical(toupper(db_name), "POOLED")
  if (!force_single && cohort_col %in% names(data) &&
      length(unique(stats::na.omit(data[[cohort_col]]))) > 1L) {
    cohorts <- as.character(unique(stats::na.omit(data[[cohort_col]])))
  } else {
    cohorts <- "_ALL_"
  }

  fmt_cell <- function(est, ci_lo, ci_hi, p) {
    p_str <- if (is.na(p) || !is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", round(p, 3))
    paste0(sprintf("%.4f", est), "[", sprintf("%.4f", ci_lo), ", ", sprintf("%.4f", ci_hi), "]", p_str)
  }
  fmt_prop <- function(prop) {
    if (is.null(prop) || length(prop) == 0L || is.na(prop) || !is.finite(prop)) return("")
    paste0(sprintf("%.1f", abs(as.numeric(prop)) * 100), "%")
  }

  all_results <- list()
  rows <- list()

  for (d in cohorts) {
    mydata <- if (identical(d, "_ALL_")) {
      data
    } else {
      data[as.character(data[[cohort_col]]) == d, , drop = FALSE]
    }
    cov_d <- covars
    # 多队列循环时允许按队列覆盖
    if (!identical(d, "_ALL_") && is.list(covars_by_db) && d %in% names(covars_by_db)) {
      cov_d <- as.character(covars_by_db[[d]] %||% cov_d)
      cov_d <- intersect(cov_d, names(mydata))
    }
    if (identical(d, "Pooled") || identical(toupper(db_name), "POOLED") ||
        ("Country" %in% names(mydata) && length(unique(stats::na.omit(mydata$Country))) > 1L)) {
      if ("Country" %in% names(mydata) && !"Country" %in% cov_d) cov_d <- c(cov_d, "Country")
    }
    # 分类协变量：强制 factor，并丢掉仅 1 水平的列（避免 contrasts 报错）
    drop_cov <- character(0)
    for (cv in cov_d) {
      if (!cv %in% names(mydata)) { drop_cov <- c(drop_cov, cv); next }
      v <- mydata[[cv]]
      if (is.character(v) || is.factor(v) || is.logical(v)) {
        mydata[[cv]] <- factor(as.character(v))
        if (nlevels(droplevels(stats::na.omit(mydata[[cv]]))) < 2L)
          drop_cov <- c(drop_cov, cv)
      } else if (is.numeric(v) && length(unique(stats::na.omit(v))) < 2L) {
        drop_cov <- c(drop_cov, cv)
      }
    }
    if (length(drop_cov)) {
      cli::cli_alert_warning(
        "mediation_longitudinal ({d}): 丢弃无变异协变量 {paste(unique(drop_cov), collapse=', ')}"
      )
      cov_d <- setdiff(cov_d, unique(drop_cov))
    }
    need_cols <- c(treat, mediator, ".__y_bin", cov_d)
    mydata <- mydata[stats::complete.cases(mydata[, need_cols, drop = FALSE]), , drop = FALSE]
    if (nrow(mydata) < 30L) {
      cli::cli_alert_warning("mediation_longitudinal: {d} N={nrow(mydata)} 过小，跳过")
      next
    }

    rhs_a <- paste(c(treat, cov_d), collapse = " + ")
    rhs_b <- paste(c(mediator, treat, cov_d), collapse = " + ")
    med_fml <- stats::as.formula(paste(mediator, "~", rhs_a))
    out_fml <- stats::as.formula(paste(".__y_bin ~", rhs_b))

    b_fit <- stats::lm(med_fml, data = mydata)
    c_fit <- stats::glm(out_fml, data = mydata, family = binomial())
    set.seed(seed)
    cc <- mediation::mediate(b_fit, c_fit, sims = sims, treat = treat, mediator = mediator)
    s <- summary(cc)

    med_type <- if (sign(s$d0) == sign(s$z0)) "Complementary" else "Competitive (suppression)"
    a_ci <- tryCatch(stats::confint(b_fit)[treat, ], error = function(e) c(NA_real_, NA_real_))
    b_ci <- tryCatch(stats::confint.default(c_fit)[mediator, ], error = function(e) c(NA_real_, NA_real_))
    a_p <- summary(b_fit)$coefficients[treat, 4]
    b_p <- summary(c_fit)$coefficients[mediator, 4]

    label <- if (identical(d, "_ALL_")) (cfg$project$database %||% "All") else d
    all_results[[label]] <- list(
      N = nrow(mydata), n_event = sum(mydata$.__y_bin == 1L, na.rm = TRUE),
      tau = s$tau.coef, tau_ci = s$tau.ci, tau_p = s$tau.p,
      z0 = s$z0, z0_ci = s$z0.ci, z0_p = s$z0.p,
      d0 = s$d0, d0_ci = s$d0.ci, d0_p = s$d0.p,
      prop = s$n.avg,
      a_coef = unname(coef(b_fit)[treat]), a_ci = a_ci, a_p = a_p,
      b_coef = unname(coef(c_fit)[mediator]), b_ci = b_ci, b_p = b_p,
      med_type = med_type,
      covariates = cov_d
    )
    r <- all_results[[label]]
    rows[[label]] <- c(
      label,
      fmt_cell(r$tau, r$tau_ci[1], r$tau_ci[2], r$tau_p),
      fmt_cell(r$z0, r$z0_ci[1], r$z0_ci[2], r$z0_p),
      fmt_cell(r$d0, r$d0_ci[1], r$d0_ci[2], r$d0_p),
      paste0(sprintf("%.4f", r$a_coef), "[", sprintf("%.4f", r$a_ci[1]), ", ", sprintf("%.4f", r$a_ci[2]), "]",
             if (isTRUE(r$a_p < 0.001)) "<0.001" else sprintf("%.3f", round(r$a_p, 3))),
      paste0(sprintf("%.4f", r$b_coef), "[", sprintf("%.4f", r$b_ci[1]), ", ", sprintf("%.4f", r$b_ci[2]), "]",
             if (isTRUE(r$b_p < 0.001)) "<0.001" else sprintf("%.3f", round(r$b_p, 3))),
      fmt_prop(r$prop)
    )
    cli::cli_alert_success(
      "mediation_longitudinal: {label} done ({med_type}; cov={paste(cov_d, collapse='+')})"
    )
  }

  if (!length(rows)) {
    cli::cli_alert_warning("mediation_longitudinal: 无可用队列结果")
    return(ctx)
  }

  col_a <- paste0("Path a (", treat_lab, "->", med_lab, ")")
  col_b <- paste0("Path b (", med_lab, "->", out_lab, ")")
  tbl <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  colnames(tbl) <- c(
    "Cohort", "Total effect (c)", "Direct effect (c')", "Indirect effect (a*b)",
    col_a, col_b, "Proportion mediated"
  )
  rownames(tbl) <- NULL

  type_note <- paste(
    vapply(names(all_results), function(nm) {
      paste0(nm, ": ", all_results[[nm]]$med_type, " mediation")
    }, character(1)),
    collapse = "; "
  )
  cov_note <- {
    u <- unique(unlist(lapply(all_results, function(r) r$covariates %||% character(0))))
    if (!length(u)) "none (crude)" else paste(u, collapse = ", ")
  }
  note <- paste0(
    "Note: Effects are risk difference (95% CI) P value. ",
    "Path a/b are regression coefficients (95% CI) P value. ",
    "Covariates: ", cov_note, ". ",
    type_note, "."
  )

  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  xlsx_path <- file.path(out_dir, "Table_Mediation_Longitudinal_FI_Depression_Hip.xlsx")
  title <- paste0("Table. Longitudinal mediation: ", treat_lab, " → ", med_lab, " → ", out_lab)

  if (exists(".sci_xlsx_write_three_line_workbook", mode = "function")) {
    body2 <- tbl
    for (j in seq_len(ncol(body2))) body2[[j]] <- as.character(body2[[j]])
    hdr <- setNames(as.data.frame(as.list(names(tbl)), stringsAsFactors = FALSE), names(tbl))
    tbl_df_new <- rbind(hdr, body2)
    .sci_xlsx_write_three_line_workbook(
      xlsx_path,
      title = title,
      tbl_df_new = tbl_df_new,
      sheet = "Table",
      footnotes = note
    )
  } else {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Sheet1")
    openxlsx::writeData(wb, 1, title, startRow = 1, startCol = 1)
    openxlsx::writeData(wb, 1, tbl, startRow = 3, startCol = 1, colNames = TRUE)
    openxlsx::writeData(wb, 1, note, startRow = 3L + nrow(tbl) + 2L, startCol = 1)
    openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  }

  db_lab <- as.character(cfg$project$database %||% "DB")[1L]
  saveRDS(
    list(db = db_lab, table = tbl, results = all_results, note = note,
         treat = treat, mediator = mediator, outcome = outcome,
         treat_lab = treat_lab, med_lab = med_lab, out_lab = out_lab,
         covariates = covars),
    file.path(out_dir, "Table_Mediation_Longitudinal_pub.rds")
  )

  # 马卡龙色系路径图
  if (isTRUE(bl$diagram_enable %||% TRUE)) {
    if (!exists(".mp01_draw_mediation_path_diagram", mode = "function") ||
        !exists(".mp01_palettes", mode = "any")) {
      # 尝试加载预后块中的绘图辅助（仅定义 .mp01_*）
      cand <- c(
        file.path(dirname(sys.frame(1)$ofile %||% "."), "01block_mediation_prognosis.R"),
        "Blocks/20_mediation/01block_mediation_prognosis.R"
      )
      for (p in cand) {
        if (file.exists(p)) {
          tryCatch(source(p, local = FALSE), error = function(e) NULL)
          break
        }
      }
    }
    fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    if (exists(".mp01_draw_mediation_path_diagram", mode = "function") &&
        exists(".mp01_palettes", mode = "any")) {
      set.seed(seed)
      sel_colors <- .mp01_palettes[[sample(names(.mp01_palettes), 1L)]]
      for (nm in names(all_results)) {
        r <- all_results[[nm]]
        pdf_file <- file.path(
          fig_dir,
          paste0("Fig_Mediation_Longitudinal_", gsub("[^A-Za-z0-9]+", "_", nm), ".pdf")
        )
        prop_pct <- if (is.finite(r$prop)) abs(as.numeric(r$prop)) * 100 else NA_real_
        tryCatch({
          .mp01_draw_mediation_path_diagram(
            exposure_label = treat_lab,
            mediator_label = med_lab,
            outcome_label  = out_lab,
            coef_a = r$a_coef, p_a = r$a_p,
            coef_b = r$b_coef, p_b = r$b_p,
            effect_total = r$tau, p_total = r$tau_p,
            prop_pct = prop_pct, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
            colors = sel_colors,
            ci_a_lo = r$a_ci[1], ci_a_hi = r$a_ci[2],
            ci_b_lo = r$b_ci[1], ci_b_hi = r$b_ci[2],
            ci_tot_lo = r$tau_ci[1], ci_tot_hi = r$tau_ci[2],
            output_path = pdf_file
          )
        }, error = function(e) {
          cli::cli_alert_warning("马卡龙中介图失败 ({nm}): {e$message}")
        })
      }
    } else if (requireNamespace("grid", quietly = TRUE)) {
      cli::cli_alert_warning("未找到 .mp01_draw_mediation_path_diagram，回退简易 grid 图")
      for (nm in names(all_results)) {
        r <- all_results[[nm]]
        pdf_file <- file.path(fig_dir, paste0("Fig_Mediation_Longitudinal_", gsub("[^A-Za-z0-9]+", "_", nm), ".pdf"))
        grDevices::pdf(pdf_file, width = 8, height = 5)
        grid::grid.newpage()
        grid::grid.text(
          paste0("Mediation: ", nm, " (N=", r$N, ") [", r$med_type, "]"),
          x = 0.5, y = 0.95, gp = grid::gpar(fontsize = 13, fontface = "bold")
        )
        grid::grid.text(treat_lab, x = 0.15, y = 0.3, gp = grid::gpar(fontsize = 11, fontface = "bold"))
        grid::grid.text(med_lab, x = 0.5, y = 0.7, gp = grid::gpar(fontsize = 11, fontface = "bold"))
        grid::grid.text(out_lab, x = 0.85, y = 0.3, gp = grid::gpar(fontsize = 11, fontface = "bold"))
        grid::grid.text(sprintf("a=%.3f", r$a_coef), x = 0.32, y = 0.55, gp = grid::gpar(col = "#E41A1C"))
        grid::grid.text(sprintf("b=%.3f", r$b_coef), x = 0.68, y = 0.55, gp = grid::gpar(col = "#E41A1C"))
        grid::grid.text(sprintf("c'=%.3f", r$z0), x = 0.5, y = 0.18, gp = grid::gpar(col = "#377EB8"))
        grDevices::dev.off()
      }
    }
  }

  ctx$results$mediation_longitudinal <- list(table = tbl, results = all_results, path = xlsx_path, note = note)
  cli::cli_alert_success("纵向中介表已写: {xlsx_path}")
  ctx
}

#' 多库合并 Table S7（纵向中介）
cross_lagged_mediation_build_table_s7 <- function(
    rds_paths,
    outfile,
    cohorts = c("CHARLS", "ELSA", "HRS"),
    title = "Table S7. Longitudinal mediation Frailty Index→Depression→Hip fracture"
) {
  objs <- list()
  for (p in rds_paths) {
    if (!file.exists(p)) next
    o <- readRDS(p)
    db <- as.character(o$db %||% NA_character_)[1L]
    if (!nzchar(db) || is.na(db)) next
    objs[[db]] <- o
  }
  cohorts <- cohorts[cohorts %in% names(objs)]
  if (!length(cohorts)) stop("cross_lagged_mediation_build_table_s7: 无可用结果", call. = FALSE)

  # 统一列名（取第一张表的 colnames）
  base_cols <- names(objs[[cohorts[[1L]]]]$table)
  body <- do.call(rbind, lapply(cohorts, function(db) {
    t <- objs[[db]]$table
    if (is.null(t) || !nrow(t)) return(NULL)
    # 每库只保留一行（Pooled 误拆时取与库名匹配行或首行）
    if (nrow(t) > 1L) {
      hit <- which(as.character(t$Cohort) == db)
      t <- t[if (length(hit)) hit[[1L]] else 1L, , drop = FALSE]
    }
    t$Cohort <- db
    # 列对齐
    for (cc in setdiff(base_cols, names(t))) t[[cc]] <- ""
    t[, base_cols, drop = FALSE]
  }))
  body <- body[!vapply(seq_len(NROW(body)), function(i) FALSE, logical(1))]
  if (is.null(body) || !nrow(body))
    stop("cross_lagged_mediation_build_table_s7: 无行", call. = FALSE)
  rownames(body) <- NULL

  type_note <- paste(
    vapply(cohorts, function(db) {
      r <- objs[[db]]$results[[db]] %||% objs[[db]]$results[[1L]]
      cv <- objs[[db]]$covariates %||% character(0)
      cv_s <- if (length(cv)) paste(cv, collapse = "+") else "(none)"
      paste0(db, ": ", r$med_type %||% "NA", " mediation (cov=", cv_s, ")")
    }, character(1)),
    collapse = "; "
  )
  note <- paste0(
    "Note: Effects are risk difference (95% CI) P value. ",
    "Path a/b are regression coefficients (95% CI) P value. ",
    "Per-database path covariates locked by depression-mediation screen. ",
    type_note, "."
  )

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  if (exists(".sci_xlsx_write_three_line_workbook", mode = "function")) {
    body2 <- body
    for (j in seq_len(ncol(body2))) body2[[j]] <- as.character(body2[[j]])
    hdr <- setNames(as.data.frame(as.list(names(body)), stringsAsFactors = FALSE), names(body))
    tbl_df_new <- rbind(hdr, body2)
    .sci_xlsx_write_three_line_workbook(
      outfile, title = title, tbl_df_new = tbl_df_new, sheet = "Table S7", footnotes = note
    )
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(body, outfile)
  }
  invisible(list(path = outfile, cohorts = cohorts))
}

register_block("mediation_longitudinal", block_mediation_longitudinal, "纵向中介 FI→抑郁→结局 (Table S7)")
