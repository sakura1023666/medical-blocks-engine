###############################################################################
#  incidence_single_pub_finalize.R — 单库发病发表收口（引擎级）
#
#  口径对齐 cute_ran / HHR summary_results：
#    Figure 1 Flowchart → Figure 2 RCS → Figure 3 Subgroup
#    Figure S1 仅暴露箱线图 → Figure S2 ROC → Figure S3 Mediation
#  跑完写指标根 summary_results（Figures/Tables/Methods md/软件版本）
#
#  开关（可选）：
#    config$boxplot$exposure_only = FALSE           # 关闭「只画暴露」
#    config$boxplot$keep_all_response_vars = TRUE   # 同上
#    config$pub$write_index_summary_results = FALSE # 关闭 summary_results
#    config$pub$curate_incidence_figures = FALSE    # 关闭图序整理
###############################################################################

#' 解析发病暴露指标名
incidence_resolve_index_var <- function(config = NULL) {
  cfg <- config %||% list()
  ix <- as.character(
    cfg$incidence$index_var %||%
      cfg$logistic$index_var %||%
      (cfg$prediction$index_vars %||% character(0))[1L] %||%
      cfg$project$index_var %||%
      ""
  )[1L]
  ix <- trimws(ix)
  if (!nzchar(ix) || tolower(ix) %in% c("null", "na", "none")) return(NA_character_)
  ix
}

#' 是否强制箱线图只保留暴露
incidence_boxplot_exposure_only_enabled <- function(config = NULL) {
  bp <- (config %||% list())$boxplot %||% list()
  if (isFALSE(bp$exposure_only)) return(FALSE)
  if (isTRUE(bp$keep_all_response_vars)) return(FALSE)
  st <- tolower(as.character((config %||% list())$project$study_type %||% "")[1L])
  identical(st, "incidence") || identical(st, "prognosis")
}

#' 强制 config$boxplot$response_vars = 暴露（发病/预后默认）
incidence_force_boxplot_exposure_only <- function(config) {
  if (!is.list(config)) return(config)
  if (!incidence_boxplot_exposure_only_enabled(config)) return(config)
  ix <- incidence_resolve_index_var(config)
  if (is.na(ix) || !nzchar(ix)) return(config)
  if (is.null(config$boxplot)) config$boxplot <- list()
  old <- as.character(config$boxplot$response_vars %||% character(0))
  config$boxplot$response_vars <- ix
  if (length(old) && !identical(unique(old), ix)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info(
        "boxplot 引擎铁律：仅保留暴露 {ix}（原 response_vars n={length(old)}）"
      )
    }
  }
  config
}

#' 箱线图 basename 是否对应当前暴露
incidence_boxplot_bn_is_exposure <- function(bn, index_var) {
  bn <- as.character(bn)[1L]
  ix <- as.character(index_var)[1L]
  if (!nzchar(ix) || is.na(ix)) return(TRUE)
  if (!grepl("Boxplot", bn, ignore.case = TRUE)) return(FALSE)
  # Figure S?. Boxplot <INDEX> by ... 或 含 "Boxplot INDEX "
  grepl(
    paste0("(^|[^A-Za-z0-9_])", gsub("([.\\(\\)])", "\\\\\\1", ix), "([^A-Za-z0-9_]|$)"),
    bn,
    ignore.case = TRUE,
    perl = TRUE
  ) || grepl(paste0("Boxplot\\s+", gsub("([.\\(\\)])", "\\\\\\1", ix), "\\b"), bn, ignore.case = TRUE)
}

#' 是否为 FPG–HbA1c 回归散点图（文献 Figure 1）
incidence_is_fpg_hba1c_figure <- function(bn) {
  bn <- as.character(bn)[1L]
  grepl(
    "Linear regression.*(FPG|HbA1c)|FPG on HbA1c|HbA1c.*FPG|FPG.*HbA1c",
    bn,
    ignore.case = TRUE
  )
}

#' 单库发病图方案：hgi_lit（有 FPG 散点）| main_mediation（默认）
#'
#' 铁律：boxplot + ROC 一律 Figure S；其余正文。
#' hgi_lit（对齐 CHARLS HGI 文献）：Fig1 散点 → Fig2 流程 → Fig3 RCS → Fig4 亚组 → Fig5 中介；S1 箱线；S2 ROC
#' main_mediation（无散点）：Fig1 流程 → Fig2 RCS → Fig3 亚组 → Fig4 中介；S1 箱线；S2 ROC
incidence_single_pub_figure_scheme <- function(config = NULL, figure_names = character(0)) {
  pub <- (config %||% list())$pub %||% list()
  forced <- tolower(trimws(as.character(pub$figure_scheme %||% "")[1L]))
  if (nzchar(forced) && !forced %in% c("null", "na", "auto", "default")) {
    return(forced)
  }
  nms <- as.character(figure_names %||% character(0))
  if (any(vapply(nms, incidence_is_fpg_hba1c_figure, logical(1L)))) {
    return("hgi_lit")
  }
  "main_mediation"
}

#' 发病图角色（单库；非暴露箱线 drop）
incidence_single_figure_role <- function(bn, index_var = NA_character_, scheme = "main_mediation") {
  bn <- as.character(bn)[1L]
  scheme <- tolower(as.character(scheme)[1L])
  if (grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Cutoff Point|maxstat", bn, ignore.case = TRUE)) return("drop")
  if (incidence_is_fpg_hba1c_figure(bn)) {
    return(if (identical(scheme, "hgi_lit")) "fig1_fpg" else "other")
  }
  if (grepl("Flowchart|Inclusion exclusion", bn, ignore.case = TRUE)) {
    return(if (identical(scheme, "hgi_lit")) "fig2_flow" else "fig1_flow")
  }
  if (grepl("RCS Analysis|RCS of|RCS plot|\\bRCS\\b|Restricted Cubic|Weighted RCS", bn, ignore.case = TRUE)) {
    return(if (identical(scheme, "hgi_lit")) "fig3_rcs" else "fig2_rcs")
  }
  if (grepl("Subgroup", bn, ignore.case = TRUE)) {
    return(if (identical(scheme, "hgi_lit")) "fig4_subgroup" else "fig3_subgroup")
  }
  if (grepl("Boxplot", bn, ignore.case = TRUE)) {
    if (!is.na(index_var) && nzchar(index_var) &&
        !incidence_boxplot_bn_is_exposure(bn, index_var)) {
      return("drop")
    }
    return("s1_boxplot")
  }
  if (grepl("Mediation|mediator|path diagram", bn, ignore.case = TRUE)) {
    return(if (identical(scheme, "hgi_lit")) "fig5_mediation" else "fig4_mediation")
  }
  if (grepl("\\bROC\\b", bn, ignore.case = TRUE)) return("s2_roc")
  "other"
}

#' 单库发病图目标文件名
incidence_single_figure_target_bn <- function(role, src_bn, db = NA_character_) {
  db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
  cap <- as.character(src_bn)[1L]
  if (exists("incidence_batch_ml_pub_figure_clean_cap", mode = "function")) {
    cap <- incidence_batch_ml_pub_figure_clean_cap(cap)
  } else {
    cap <- sub("^Figure (?:S)?[0-9]+(?:-[A-Za-z0-9_]+)?\\. ", "", cap, perl = TRUE)
    cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  }
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  switch(
    role,
    fig1_fpg = sprintf("Figure 1%s. %s.pdf", db_sfx, cap),
    fig1_flow = sprintf("Figure 1%s. %s.pdf", db_sfx, cap),
    fig2_flow = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig2_rcs = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig3_rcs = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    fig3_subgroup = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    fig4_subgroup = sprintf("Figure 4%s. %s.pdf", db_sfx, cap),
    fig4_mediation = sprintf("Figure 4%s. %s.pdf", db_sfx, cap),
    fig5_mediation = sprintf("Figure 5%s. %s.pdf", db_sfx, cap),
    s1_boxplot = sprintf("Figure S1%s. %s.pdf", db_sfx, cap),
    s2_roc = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    NULL
  )
}

#' 整理单库发病 Figures（pdf 子目录 + 根目录平铺）
#'
#' @return 删除文件数（近似）
#' ML 课题判定：勿套「发病 S1 箱线 / S2 ROC」单库图序
incidence_single_is_ml_project <- function(config = NULL) {
  cfg <- config %||% list()
  if (isTRUE(cfg$ml_batch$enable %||% FALSE)) return(TRUE)
  if (is.list(cfg$ml_batch) && length(cfg$ml_batch)) {
    sch <- as.character(
      cfg$ml_batch$pub_figure_scheme %||%
        cfg$incidence_batch$pub_figure_scheme %||%
        cfg$survival_batch$pub_figure_scheme %||% ""
    )[1L]
    if (grepl("^ml_", sch)) return(TRUE)
    ## 有 ML 块开关即视为 ML 课题（单库 ML 发病常见）
    if (!is.null(cfg$ml_batch$omit_figure_s2) ||
        !is.null(cfg$ml_batch$write_index_summary_results) ||
        !is.null(cfg$ml_batch$curate_purge_pub_figures)) {
      return(TRUE)
    }
  }
  pipe <- as.character(cfg$pipeline$blocks %||% cfg$blocks %||% character(0))
  if (any(grepl("^ml_|performance_ml|^shap$", pipe))) return(TRUE)
  FALSE
}

incidence_curate_single_delivery_figures <- function(out_root, config = NULL) {
  out_root <- as.character(out_root %||% "")[1L]
  if (!nzchar(out_root) || !dir.exists(out_root)) return(invisible(0L))
  pub <- (config %||% list())$pub %||% list()
  if (isFALSE(pub$curate_incidence_figures)) return(invisible(0L))
  st <- tolower(as.character((config %||% list())$project$study_type %||% "")[1L])
  if (!identical(st, "incidence")) return(invisible(0L))
  ## ML 单库发病：走 ml_* 图序（S1=LASSO），禁止套 main_mediation 的 S1 箱线/S2 ROC
  if (isTRUE(incidence_single_is_ml_project(config))) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("跳过单库发病图序：本课题为 ML（S1=特征选择，非箱线/ROC）")
    }
    return(invisible(0L))
  }

  if (!exists("incidence_batch_dedupe_pub_figures_by_role", mode = "function")) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    src <- file.path(eng, "R/incidence_dual_batch_runner.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (!exists("incidence_batch_dedupe_pub_figures_by_role", mode = "function")) {
    return(invisible(0L))
  }

  ix <- incidence_resolve_index_var(config)
  fig_root <- file.path(out_root, "Figures")
  dirs <- character(0)
  if (dir.exists(file.path(fig_root, "pdf"))) dirs <- c(dirs, file.path(fig_root, "pdf"))
  if (dir.exists(fig_root)) dirs <- c(dirs, fig_root)
  if (dir.exists(file.path(out_root, "pdf"))) dirs <- c(dirs, file.path(out_root, "pdf"))
  dirs <- unique(dirs[dir.exists(dirs)])

  all_pdf_names <- unique(unlist(lapply(dirs, function(d) {
    list.files(d, pattern = "^Figure.*\\.pdf$", full.names = FALSE, ignore.case = TRUE)
  }), use.names = FALSE))
  scheme <- incidence_single_pub_figure_scheme(config, all_pdf_names)
  role_fn <- function(bn) incidence_single_figure_role(bn, ix, scheme = scheme)

  n <- 0L
  for (d in dirs) {
    if (grepl("/(png|tiff|image_information)$", d)) next
    pdfs <- list.files(d, pattern = "^Figure.*\\.pdf$", full.names = FALSE, ignore.case = TRUE)
    if (!length(pdfs)) next
    n <- n + (
      incidence_batch_dedupe_pub_figures_by_role(
        d,
        config = config,
        role_fn = role_fn,
        target_fn = incidence_single_figure_target_bn
      ) %||% 0L
    )
  }

  # 四目录：强制出 png + tiff（≥600 dpi；见 pub_figures$export_*）
  if (dir.exists(fig_root) && exists("pub_figure_ensure_formats", mode = "function")) {
    cfg_fmt <- config %||% list()
    if (!is.list(cfg_fmt$pub_figures)) cfg_fmt$pub_figures <- list()
    # 默认开栅格；可用 pub_figures$export_png/tiff=FALSE 关
    if (is.null(cfg_fmt$pub_figures$export_png)) cfg_fmt$pub_figures$export_png <- TRUE
    if (is.null(cfg_fmt$pub_figures$export_tiff)) cfg_fmt$pub_figures$export_tiff <- TRUE
    cfg_fmt$pub_figures$dpi <- as.integer(cfg_fmt$pub_figures$dpi %||% 600L)
    tryCatch(
      pub_figure_ensure_formats(fig_root, config = cfg_fmt),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("单库图四目录刷新跳过: {e$message}")
        }
      }
    )
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "单库发病图已整理（scheme={scheme}；正文含中介；S1 箱线 / S2 ROC；png/tiff@600）"
    )
  }
  invisible(n)
}

#' 从 Table 2 文件名解析主分位方案（quartile/tertile/binary/quintile）
incidence_single_main_logistic_scheme <- function(tables_dir) {
  tabs <- list.files(tables_dir, pattern = "^Table 2.*\\.xlsx$", ignore.case = TRUE)
  if (!length(tabs)) return(NA_character_)
  bn <- tabs[[1L]]
  if (grepl("tertile", bn, ignore.case = TRUE)) return("tertile")
  if (grepl("quartile", bn, ignore.case = TRUE)) return("quartile")
  if (grepl("quintile", bn, ignore.case = TRUE)) return("quintile")
  if (grepl("binary|median", bn, ignore.case = TRUE)) return("binary")
  NA_character_
}

#' 单库发病 Tables 交付白名单：去掉闸门淘汰分位表、Final multivariable model
#'
#' 保留过程表：S4 VIF screen、S5 多因素、S6 VIF final（终模型前共线性复核）。
#' 不进 summary：非主分位 Logistic（如 Table2=tertile 时的 quartile）、Final multivariable model。
#' 删除后按角色重排 S 号：MI→正态→UV→VIF screen→MV→VIF final→lab→mediation…
incidence_single_curate_delivery_tables <- function(tables_dir, config = NULL) {
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) return(invisible(0L))
  pub <- (config %||% list())$pub %||% list()
  drop_final_mv <- !isFALSE(pub$drop_final_multivariable_model %||% TRUE)
  drop_non_main_logit <- !isFALSE(pub$drop_non_main_logistic %||% TRUE)

  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  main_scheme <- incidence_single_main_logistic_scheme(tables_dir)
  n_drop <- 0L
  keep <- character(0)
  for (f in files) {
    bn <- basename(f)
    drop <- FALSE
    if (isTRUE(drop_final_mv) &&
        grepl("Final multivariable model", bn, ignore.case = TRUE)) {
      drop <- TRUE
    }
    if (isTRUE(drop_non_main_logit) &&
        grepl("Logistic regression", bn, ignore.case = TRUE) &&
        !grepl("^Table 2", bn, ignore.case = TRUE)) {
      # 非 Table2 的分位/二分 Logistic（闸门淘汰或敏感性）不进交付
      if (grepl("quartile|tertile|binary|quintile|median|RCS cutoff", bn, ignore.case = TRUE)) {
        # 若文件名分位与主方案相同且不是 Table2，仍视为过程/重复，交付只留 Table2
        drop <- TRUE
      }
    }
    if (isTRUE(drop)) {
      unlink(f)
      # companion tex/csv
      for (ext in c(".tex", ".csv")) {
        alt <- sub("\\.xlsx$", ext, f, ignore.case = TRUE)
        if (file.exists(alt)) unlink(alt)
      }
      n_drop <- n_drop + 1L
    } else {
      keep <- c(keep, f)
    }
  }

  ## 重排 S 编号（主表 Table1/2 不动）
  role_rank <- function(bn) {
    if (grepl("^Table [0-9]+", bn) && !grepl("^Table S", bn)) return(NA_integer_)
    if (grepl("before and after imputation", bn, ignore.case = TRUE)) return(1L)
    if (grepl("Normality test", bn, ignore.case = TRUE)) return(2L)
    if (grepl("Univariate Regression", bn, ignore.case = TRUE)) return(3L)
    if (grepl("Multicollinearity", bn, ignore.case = TRUE) &&
        grepl("VIF screen|univariate p|univariate screen", bn, ignore.case = TRUE)) {
      return(4L)
    }
    if (grepl("Multivariable Regression", bn, ignore.case = TRUE)) return(5L)
    if (grepl("Multicollinearity", bn, ignore.case = TRUE) &&
        grepl("VIF final|multivariate p|multivariate final", bn, ignore.case = TRUE)) {
      return(6L)
    }
    # 裸 Multicollinearity：按原 S 号区分 screen(~S4) / final(~S6)
    if (grepl("Multicollinearity", bn, ignore.case = TRUE)) {
      old_s <- suppressWarnings(as.integer(sub("(?i)^Table S([0-9]+).*", "\\1", bn, perl = TRUE)))
      if (is.finite(old_s) && old_s <= 4L) return(4L)
      return(6L)
    }
    if (grepl("laboratory indicators|Associations of", bn, ignore.case = TRUE)) return(7L)
    if (grepl("Mediation analysis", bn, ignore.case = TRUE)) return(8L)
    if (grepl("^Table S", bn, ignore.case = TRUE)) return(90L)
    NA_integer_
  }
  keep_bn <- basename(keep)
  rk <- vapply(keep_bn, role_rank, integer(1L))
  ord <- order(rk, keep_bn, na.last = TRUE)
  keep <- keep[ord]
  rk <- rk[ord]
  s_i <- 1L
  for (i in seq_along(keep)) {
    if (is.na(rk[[i]]) || rk[[i]] >= 90L) next
    if (rk[[i]] < 1L) next
    f <- keep[[i]]
    bn <- basename(f)
    if (!grepl("^Table S[0-9]+", bn, ignore.case = TRUE)) next
    # caption after "Table S#-" or "Table S#. "
    rest <- sub("^Table S[0-9]+[-.]\\s*", "", bn, ignore.case = TRUE, perl = TRUE)
    # preserve DB infix: Table S4-CHARLS. Title.xlsx
    db_m <- regmatches(bn, regexpr("^Table S[0-9]+-([A-Za-z0-9_]+)\\.", bn, perl = TRUE))
    if (length(db_m) && nzchar(db_m)) {
      db <- sub("^Table S[0-9]+-([A-Za-z0-9_]+)\\..*$", "\\1", bn, perl = TRUE)
      new_bn <- sprintf("Table S%d-%s. %s", s_i, db, sub(paste0("^", db, "\\.\\s*"), "", rest))
      # rest already like "CHARLS. Multicollinearity...." when pattern was S4-CHARLS.
      if (grepl(paste0("^", db, "\\."), rest)) {
        new_bn <- sprintf("Table S%d-%s", s_i, rest)
      } else {
        new_bn <- sprintf("Table S%d-%s. %s", s_i, db, rest)
      }
    } else {
      new_bn <- sprintf("Table S%d. %s", s_i, rest)
    }
    new_bn <- sub("\\.xlsx\\.xlsx$", ".xlsx", new_bn, ignore.case = TRUE)
    if (!grepl("\\.xlsx$", new_bn, ignore.case = TRUE)) new_bn <- paste0(new_bn, ".xlsx")
    dest <- file.path(tables_dir, new_bn)
    if (!identical(normalizePath(f, winslash = "/", mustWork = FALSE),
                   normalizePath(dest, winslash = "/", mustWork = FALSE))) {
      if (file.exists(dest)) unlink(dest)
      file.rename(f, dest)
    }
    s_i <- s_i + 1L
  }
  if (requireNamespace("cli", quietly = TRUE) && n_drop > 0L) {
    cli::cli_alert_success(
      "单库发病表已整理：剔除 {n_drop} 张（淘汰分位/Final multivariable）；主方案={main_scheme %||% NA}"
    )
  }
  invisible(n_drop)
}

#' 单库发病是否默认写 summary_results
incidence_single_summary_results_wanted <- function(config = NULL) {
  pub <- (config %||% list())$pub %||% list()
  if (!is.null(pub$write_summary_results)) return(isTRUE(pub$write_summary_results))
  if (!is.null(pub$write_index_summary_results)) {
    return(isTRUE(pub$write_index_summary_results))
  }
  st <- tolower(as.character((config %||% list())$project$study_type %||% "")[1L])
  identical(st, "incidence")
}

#' pipeline 末尾：整理图 + 写 summary_results
incidence_single_finalize_after_pipeline <- function(out_root, config = NULL) {
  out_root <- as.character(out_root %||% "")[1L]
  if (!nzchar(out_root) || !dir.exists(out_root)) return(invisible(NULL))
  st <- tolower(as.character((config %||% list())$project$study_type %||% "")[1L])
  if (!identical(st, "incidence")) return(invisible(NULL))
  ## ML 课题：表/图定稿由 ml dual-batch finalize 负责，勿套发病 S1 箱线口径
  if (isTRUE(incidence_single_is_ml_project(config))) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("跳过 incidence_single_finalize：ML 课题")
    }
    return(invisible(NULL))
  }

  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  for (rel in c(
    "R/incidence_dual_batch_runner.R",
    "R/pub_figure_export.R",
    "R/ml_index_summary_results.R",
    "R/pub_delivery_prune.R"
  )) {
    p <- file.path(eng, rel)
    if (file.exists(p) && !exists(sub("\\.R$", "", basename(p)), mode = "function")) {
      # source files; presence of key fns checked below
    }
    if (file.exists(p)) {
      # always source finalize helpers (idempotent)
      tryCatch(source(p, local = FALSE), error = function(e) NULL)
    }
  }
  # ensure this file's helpers exist even if sourced from elsewhere first
  if (!exists("incidence_curate_single_delivery_figures", mode = "function")) {
    this <- file.path(eng, "R/incidence_single_pub_finalize.R")
    if (file.exists(this)) source(this, local = FALSE)
  }

  tryCatch(
    incidence_curate_single_delivery_figures(out_root, config = config),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("单库发病图整理跳过: {e$message}")
      }
    }
  )
  tryCatch(
    incidence_single_curate_delivery_tables(
      file.path(out_root, "Tables"), config = config
    ),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("单库发病表整理跳过: {e$message}")
      }
    }
  )

  if (!isTRUE(incidence_single_summary_results_wanted(config))) {
    return(invisible(NULL))
  }
  if (!exists("ml_finalize_index_summary_results", mode = "function")) {
    return(invisible(NULL))
  }
  cfg2 <- config %||% list()
  if (!is.list(cfg2$pub)) cfg2$pub <- list()
  if (is.null(cfg2$pub$index_summary_results_dir) &&
      is.null(cfg2$pub$summary_dirname)) {
    cfg2$pub$index_summary_results_dir <- "summary_results"
    cfg2$pub$summary_dirname <- "summary_results"
  }
  if (!is.list(cfg2$pub_figures)) cfg2$pub_figures <- list()
  if (is.null(cfg2$pub_figures$export_png)) cfg2$pub_figures$export_png <- TRUE
  if (is.null(cfg2$pub_figures$export_tiff)) cfg2$pub_figures$export_tiff <- TRUE
  if (is.null(cfg2$pub_figures$dpi)) cfg2$pub_figures$dpi <- 600L
  sum_p <- tryCatch(
    ml_finalize_index_summary_results(out_root, config = cfg2),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("单库 summary_results 跳过: {e$message}")
      }
      NULL
    }
  )
  if (!is.null(sum_p)) {
    tryCatch(
      incidence_single_curate_delivery_tables(
        file.path(sum_p, "Tables"), config = cfg2
      ),
      error = function(e) NULL
    )
  }
  invisible(sum_p)
}
