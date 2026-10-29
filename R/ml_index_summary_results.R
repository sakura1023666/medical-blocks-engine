###############################################################################
#  ml_index_summary_results.R — 指标级 summary_results 收口（全项目复用）
#
#  落盘：by_index/【success】<INDEX>/summary_results/
#    交付白名单（与 pub_delivery_whitelist 一致）：
#      Figures/  Tables/
#      Methods_statistical_analysis.md
#      Methods_software_versions.txt
#      *中期*.pdf
#  用于单库 / 双库 ML 发病预测；config：
#    config$ml_batch$write_index_summary_results = TRUE
#    config$pub$index_summary_results_dir = "summary_results"  # 或 summary_result
###############################################################################

#' ML 指标交付 Methods 正文（从 config 填疾病 / 库 / 暴露）
ml_index_methods_statistical_lines <- function(config = NULL) {
  cfg <- config %||% list()
  proj <- cfg$project %||% list()
  mb <- cfg$ml_batch %||% cfg$incidence_batch %||% list()
  st <- tolower(trimws(as.character(proj$study_type %||% "")[1L]))
  is_prog <- identical(st, "prognosis")
  disease <- as.character(
    proj$analysis_group %||% proj$disease %||% mb$analysis_group %||%
      "the study outcome"
  )[1L]
  exposure <- as.character(
    proj$exposure %||% mb$index_vars[[1L]] %||% cfg$index$vars[[1L]] %||%
      "the primary exposure index"
  )[1L]
  db <- as.character(
    proj$database %||%
      (cfg$dual_db$primary %||% list())$name %||%
      mb$primary_name %||% proj$databases[[1L]] %||% "the study database"
  )[1L]
  age_f <- as.character((cfg$data_clean %||% list())$age_filter %||% "")[1L]
  age_note <- if (nzchar(age_f)) {
    paste0(" Age eligibility followed `", age_f, "`.")
  } else {
    ""
  }
  surv <- cfg$survival %||% list()
  time_var <- as.character(surv$time_var %||% "follow-up time")[1L]
  event_var <- as.character(surv$event_var %||% disease)[1L]
  horiz <- suppressWarnings(as.numeric((cfg$performance_ml %||% list())$surv_horizon %||% NA_real_)[1L])
  horiz_u <- as.character((cfg$performance_ml %||% list())$surv_horizon_unit %||% "month")[1L]
  best_metric <- tolower(trimws(as.character(
    (cfg$ml_aggregate %||% list())$best_metric %||%
      (cfg$ml_best %||% list())$metric %||%
      if (is_prog) "c_index" else "roc_auc"
  )[1L]))
  if (best_metric %in% c("auc", "roc_auc")) best_metric <- "validation AUC"
  if (identical(best_metric, "c_index")) best_metric <- "validation C-index"
  wt <- as.character((cfg$nhanes %||% list())$survey_weight %||% "")[1L]
  db_type <- tolower(trimws(as.character(proj$database_type %||% "")[1L]))
  ## 模板常残留 nhanes$survey_weight；仅当库名/类型真是 NHANES 才写调查权重
  is_nhanes <- identical(toupper(db), "NHANES") ||
    identical(db_type, "nhanes") ||
    (nzchar(wt) && grepl("nhanes", tolower(paste(db, db_type)), fixed = TRUE))
  wt_note <- if (is_nhanes) {
    paste0(
      " For NHANES, descriptive tables and association models used the complex ",
      "survey design (strata, PSUs, and ",
      if (nzchar(wt)) paste0("weight `", wt, "`") else "the study survey weight",
      "). Weighted percentages are paired with design-based tests as stated in table footnotes."
    )
  } else {
    ""
  }
  mi <- cfg$imputation %||% list()
  m <- suppressWarnings(as.integer(mi$m %||% 5L)[1L])
  if (!is.finite(m) || m < 1L) m <- 5L
  rubin <- isTRUE(mi$rubin_pool %||% TRUE)
  mi_note <- if (identical(as.character(mi$method %||% ""), "none")) {
    "Analyses used complete cases without multiple imputation."
  } else {
    paste0(
      "Missing covariates were handled with multiple imputation by chained equations ",
      "(m = ", m, "). ",
      if (isTRUE(rubin)) {
        if (is_prog) {
          "Cox regression estimates were pooled across imputations with Rubin's rules. "
        } else {
          "Logistic regression estimates were pooled across imputations with Rubin's rules. "
        }
      } else {
        ""
      },
      "Operational steps (feature selection, KM/RCS/SHAP plots, descriptive tables) used the first completed dataset."
    )
  }
  if (is_prog) {
    design_line <- paste0(
      "This was a prognostic survival analysis of ", disease,
      " in ", db, ".", age_note,
      " The analytic sample followed the study inclusion flowchart (Figure 1). ",
      "Overall survival time was recorded in `", time_var,
      "` with event indicator `", event_var, "`."
    )
    exposure_line <- paste0(
      "Candidate clinical, imaging, and treatment variables entered feature selection. ",
      "Continuous features retained after selection were analysed with Cox proportional hazards models ",
      "(continuous and quartile forms; lowest quartile as reference) and Kaplan–Meier curves. ",
      "Restricted cubic splines and subgroup forests focused on Age when that exposure was significant. ",
      if (is.finite(horiz)) {
        paste0("Machine-learning discrimination was summarised at a ", horiz, "-", horiz_u, " horizon where applicable. ")
      } else {
        ""
      },
      "The clinical endpoint was ", disease, "."
    )
    assoc_line <- paste0(
      "Cox models reported hazard ratios (HRs) with 95% confidence intervals. ",
      "Model 1 and Model 2 covariates follow the regression table footnotes ",
      "(Age was not used as a covariate when Age was the exposure). ",
      "Restricted cubic splines described the Age–mortality dose–response. ",
      "Subgroup forests estimated the highest-versus-lowest Age quartile contrast ",
      "within strata on the full analytic sample."
    )
    ml_line <- paste0(
      "Participants were randomly split into training and validation sets for supervised survival prediction of ",
      disease, ". ",
      "Feature selection used univariate Cox screening, VIF filtering, and LASSO-Cox. ",
      "Multiple survival learners were trained; the primary model for SHAP explanation and the Shiny tool ",
      "was the learner with the highest ", best_metric, " on the validation set. ",
      "Discrimination (AUC, C-index), calibration, and decision-curve analyses are reported in the performance tables."
    )
  } else {
    design_line <- paste0(
      "This was a cross-sectional analysis of ", disease,
      " in ", db, ".", age_note,
      " The analytic sample followed the study inclusion flowchart (Figure 1). ",
      "Unweighted participant counts are reported alongside weighted percentages where labelled."
    )
    outcome_def <- trimws(as.character(
      (config$methods %||% list())$outcome_definition %||%
        (config$pub %||% list())$outcome_definition %||% ""
    )[1L])
    exposure_line <- paste0(
      "The primary exposure was ", exposure,
      " (composite index as defined in the study configuration). ",
      "The exposure entered models as a continuous variable and as quantiles with cut-points ",
      "aligned to the main regression table; the lowest quantile was the reference. ",
      "Tests for trend used the numeric quantile score. ",
      if (nzchar(outcome_def)) {
        outcome_def
      } else {
        paste0("The binary outcome was ", disease, ".")
      }
    )
    assoc_line <- paste0(
      if (is_nhanes) {
        "Survey-weighted logistic regression estimated odds ratios (ORs) with 95% confidence intervals. "
      } else {
        "Logistic regression estimated odds ratios (ORs) with 95% confidence intervals. "
      },
      "Model 1 and Model 2 covariates are those named in the main regression table footnote. ",
      "Restricted cubic splines described dose–response. ",
      "Subgroup forests estimated the highest-versus-lowest quantile contrast within strata ",
      "on the full analytic sample (forest N = stratum totals)."
    )
    ml_line <- paste0(
      "Participants were split into training and validation sets for supervised prediction of ",
      disease, ". ",
      "Feature selection (LASSO) and candidate classifiers followed the study ML blocks. ",
      "The primary model for SHAP/Shiny used the highest ", best_metric, " on the validation set. ",
      "Discrimination, calibration, and related metrics are reported in the performance tables."
    )
  }
  c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    "",
    design_line,
    wt_note,
    "",
    "## Exposure and outcome",
    "",
    exposure_line,
    "",
    "## Missing data",
    "",
    mi_note,
    "",
    "## Association analyses",
    "",
    assoc_line,
    "",
    "## Machine learning",
    "",
    ml_line,
    "",
    "## Software",
    "",
    "Package versions are listed in Methods_software_versions.txt and the Software subsection below.",
    ""
  )
}

#' 单库发表名：去掉「Table/Figure …-库名.」中的库名（文件名 + 表 A1 标题）
#' @param root Tables 或 Figures 目录（或含二者的指标根 / summary_results）
#' @param db_tags 要剥掉的库标签；NULL 时用常见库名 + config 主库名
pub_strip_db_tags_from_delivery <- function(root, config = NULL, db_tags = NULL) {
  root <- as.character(root %||% "")[1L]
  if (!nzchar(root) || !dir.exists(root)) return(invisible(0L))
  tags <- unique(c(
    as.character(db_tags %||% character(0)),
    "CHARLS", "NHANES", "Nhance", "MIMIC", "MIMIC_IV", "MIMIC IV", "eICU", "ELSA", "Hosp",
    "NPC", "VitalDB", "BlendedICU"
  ))
  if (!is.null(config)) {
    dd <- config$dual_db %||% list()
    pr <- config$project %||% list()
    for (slot in c("primary", "secondary")) {
      nm <- as.character((dd[[slot]] %||% list())$name %||% "")[1L]
      if (nzchar(nm) && !identical(toupper(nm), "UNUSED")) tags <- c(tags, nm)
    }
    ## 单库常用 project$database（如 NPC）也会写进 Table 1-NPC. …
    for (nm in c(pr$database, pr$database_code, pr$disease_code)) {
      nm <- as.character(nm %||% "")[1L]
      if (!nzchar(nm) || identical(toupper(nm), "UNUSED")) next
      ## disease_code 形如 53_NPC → 也收 NPC
      tags <- c(tags, nm, sub("^.*_", "", nm))
    }
  }
  tags <- unique(tags[nzchar(tags) & !identical(toupper(tags), "UNUSED")])
  tags <- tags[order(-nchar(tags))]
  flex_one <- function(t) {
    t <- gsub("[ _]+", " ", t)
    parts <- strsplit(t, " ", fixed = TRUE)[[1L]]
    paste(vapply(parts, function(p) gsub("(\\\\|[][{}()+*^$?.|^-])", "\\\\\\1", p, perl = TRUE),
                 character(1L)), collapse = "[ _]+")
  }
  strip_bn <- function(bn) {
    out <- bn
    for (tg in tags) {
      flex <- flex_one(tg)
      # Table 1-CHARLS. / Figure S2A-CHARLS. / Figure S-CHARLS.
      out <- gsub(
        paste0("^((?:Table|Figure)\\s+(?:S?[0-9]+[A-Za-z]?|S)?)-(?:", flex, ")(\\.)"),
        "\\1\\2",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
      # 误套：Figure S1. S-CHARLS. caption → Figure S1. caption
      out <- gsub(
        paste0("\\.\\s*S-(?:", flex, ")\\.\\s*"),
        ". ",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
      out <- gsub(
        paste0("-(?:", flex, ")(?=\\.)"),
        "",
        out,
        ignore.case = TRUE,
        perl = TRUE
      )
    }
    out <- gsub("\\s{2,}", " ", out)
    out <- sub("^((?:Table|Figure)\\s+S)\\.\\s*", "\\1. ", out, perl = TRUE)
    out
  }
  n <- 0L
  # Tables xlsx
  tab_dirs <- unique(c(
    if (dir.exists(file.path(root, "Tables"))) file.path(root, "Tables") else character(0),
    if (grepl("/Tables$", root)) root else character(0)
  ))
  for (td in tab_dirs) {
    files <- list.files(td, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    for (f in files) {
      new_bn <- strip_bn(basename(f))
      dest <- file.path(td, new_bn)
      if (!identical(basename(f), new_bn)) {
        if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"),
                                            normalizePath(dest, winslash = "/", mustWork = FALSE))) {
          unlink(dest)
        }
        if (isTRUE(file.rename(f, dest))) {
          n <- n + 1L
          f <- dest
        } else if (isTRUE(file.copy(f, dest, overwrite = TRUE))) {
          unlink(f)
          n <- n + 1L
          f <- dest
        }
      }
      # A1 标题去库名：字节级替换 sharedStrings（避免 openpyxl/ET 损坏 drawing）
      tryCatch(
        {
          py <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
          if (!nzchar(py)) py <- getwd()
          helper <- file.path(py, "python", "pub_strip_db_in_xlsx_title.py")
          if (file.exists(helper)) {
            system2("python3", c(helper, f), stdout = FALSE, stderr = FALSE)
          } else if (requireNamespace("openxlsx", quietly = TRUE)) {
            d <- tryCatch(openxlsx::read.xlsx(f, colNames = FALSE, rows = 1, cols = 1),
                          error = function(e) NULL)
            t1 <- if (!is.null(d) && nrow(d)) as.character(d[1, 1]) else ""
            t1b <- strip_bn(t1)
            if (nzchar(t1) && !identical(t1, t1b) &&
                exists("pub_xlsx_edit_cells", mode = "function")) {
              pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = t1b))
            }
          }
        },
        error = function(e) NULL
      )
    }
  }
  # Figures：pdf/png/tiff/image_information + 根平铺
  fig_root <- if (dir.exists(file.path(root, "Figures"))) {
    file.path(root, "Figures")
  } else if (grepl("/Figures$", root)) {
    root
  } else {
    character(0)
  }
  if (length(fig_root) && dir.exists(fig_root)) {
    subdirs <- c(
      fig_root,
      file.path(fig_root, c("pdf", "png", "tiff", "image_information"))
    )
    for (fd in subdirs) {
      if (!dir.exists(fd)) next
      files <- list.files(fd, full.names = TRUE, no.. = TRUE)
      files <- files[!dir.exists(files)]
      for (f in files) {
        new_bn <- strip_bn(basename(f))
        if (identical(basename(f), new_bn)) next
        dest <- file.path(fd, new_bn)
        if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"),
                                            normalizePath(dest, winslash = "/", mustWork = FALSE))) {
          unlink(dest)
        }
        if (isTRUE(file.rename(f, dest)) || isTRUE(file.copy(f, dest, overwrite = TRUE))) {
          if (file.exists(dest) && file.exists(f) &&
              !identical(normalizePath(f, winslash = "/"), normalizePath(dest, winslash = "/"))) {
            unlink(f)
          }
          n <- n + 1L
          # md 标题同步
          if (grepl("\\.md$", dest, ignore.case = TRUE)) {
            lines <- tryCatch(readLines(dest, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
            if (!is.null(lines) && length(lines) && grepl("^#\\s*Figure", lines[[1L]])) {
              lines[[1L]] <- paste0("# ", sub("\\.md$", "", new_bn, ignore.case = TRUE))
              writeLines(lines, dest, useBytes = TRUE)
            }
          }
        }
      }
    }
  }
  if (requireNamespace("cli", quietly = TRUE) && n > 0L) {
    cli::cli_alert_success("单库发表去库名: {n} 个文件 @ {root}")
  }
  invisible(n)
}

#' 指标级 summary_results 目录名
ml_index_summary_results_dirname <- function(config = NULL) {
  pub <- config$pub %||% list()
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  nm <- as.character(
    pub$index_summary_results_dir %||%
      bc$index_summary_results_dir %||%
      "summary_results"
  )[1L]
  if (!nzchar(nm)) nm <- "summary_results"
  nm
}

#' 是否在 finalize 后写指标级 summary_results
#'
#' 交付面：`by_index/【success】<INDEX>/summary_results/`（白名单五件套）。
#' 发病/预后 dual-batch、**双库/单库 ML** 均默认开（须在 by_index 下，勿只落课题根）。
#' 显式 `write_index_summary_results=FALSE` 可关。
ml_index_summary_results_enabled <- function(config = NULL) {
  bc <- config$ml_batch %||% config$incidence_batch %||% config$survival_batch %||% list()
  pub <- config$pub %||% list()
  if (!is.null(bc$write_index_summary_results)) {
    return(isTRUE(bc$write_index_summary_results))
  }
  if (!is.null(pub$write_index_summary_results)) {
    return(isTRUE(pub$write_index_summary_results))
  }
  ## 发病 / 预后 / ML dual-batch：默认写指标级 summary_results
  if (!is.null(config$incidence_batch) ||
      !is.null(config$survival_batch) ||
      !is.null(config$ml_batch)) {
    return(TRUE)
  }
  TRUE
}

#' 同步指标根 Tables/Figures → summary_results，并写 Methods / 软件版本后白名单修剪
#'
#' @param index_root by_index/【success】INDEX 或裸名 INDEX
#' @param config 可选；用于四目录 dpi、目录名与 Methods 字段
#' @param figures_tables_only TRUE 时仅留 Figures/Tables（旧行为）；
#'   默认 FALSE = 完整交付白名单（含 Methods / 软件版本 / 中期 PDF）
#' @param write_methods 是否写出 Methods_statistical_analysis.md + 软件版本（默认 TRUE）
#' @param methods_lines 可选课题自定义 Methods 行；NULL 时用 ml_index_methods_statistical_lines
#' @return summary_results 绝对路径
ml_finalize_index_summary_results <- function(index_root,
                                              config = NULL,
                                              figures_tables_only = FALSE,
                                              write_methods = TRUE,
                                              methods_lines = NULL) {
  index_root <- as.character(index_root %||% "")[1L]
  if (!nzchar(index_root) || !dir.exists(index_root)) {
    stop("ml_finalize_index_summary_results: index_root 无效: ", index_root)
  }
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng)) eng <- getwd()
  .ml_src <- function(rel) {
    p <- file.path(eng, rel)
    if (file.exists(p)) source(p, local = FALSE)
  }
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    .ml_src("R/pub_delivery_prune.R")
  }
  if (!exists("pub_write_software_versions", mode = "function")) {
    .ml_src("R/pub_software_versions.R")
  }
  if (!exists("pub_figure_ensure_formats", mode = "function")) {
    .ml_src("R/pub_figure_export.R")
  }

  ## 单库：指标根先剥掉 -CHARLS/-NHANES/-NPC 等库名，再同步到 summary_results
  .do_strip <- exists("pub_config_is_single_db", mode = "function") &&
    isTRUE(pub_config_is_single_db(config))
  if (isTRUE(.do_strip)) {
    tryCatch(
      pub_strip_db_tags_from_delivery(index_root, config = config),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results: 去库名失败: {e$message}")
        }
      }
    )
  }
  ## 命名 options：单库禁止后续 block 再写 -库名
  if (exists("pub_apply_naming_options", mode = "function")) {
    tryCatch(pub_apply_naming_options(config), error = function(e) NULL)
  }
  sum_nm <- ml_index_summary_results_dirname(config)
  sum_root <- file.path(index_root, sum_nm)
  dir.create(sum_root, recursive = TRUE, showWarnings = FALSE)

  ## 确保指标根 Figures 四目录齐全
  fig_src <- file.path(index_root, "Figures")
  if (dir.exists(fig_src) && exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(fig_src, config = config),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results: 四目录补齐失败: {e$message}")
        }
      }
    )
  }

  tab_src <- file.path(index_root, "Tables")
  tab_dst <- file.path(sum_root, "Tables")
  fig_dst <- file.path(sum_root, "Figures")
  dir.create(tab_dst, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dst, recursive = TRUE, showWarnings = FALSE)

  ## Tables：只同步发表 xlsx
  if (dir.exists(tab_src)) {
    xlsx <- list.files(tab_src, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    for (f in xlsx) {
      file.copy(f, file.path(tab_dst, basename(f)), overwrite = TRUE)
    }
  }

  ## Figures：整树同步（含 pdf/png/tiff/image_information）
  if (dir.exists(fig_src)) {
    unlink(fig_dst, recursive = TRUE, force = TRUE)
    ## file.copy(src_dir, parent) → parent/basename(src_dir)
    file.copy(fig_src, sum_root, recursive = TRUE, overwrite = TRUE)
  }

  ## 同步后再剥一次库名（防止 copy 带回旧 -NPC 名）
  if (isTRUE(.do_strip)) {
    tryCatch(
      pub_strip_db_tags_from_delivery(sum_root, config = config),
      error = function(e) NULL
    )
  }

  ## 汇总只留主文/必要补充：剔除 ML panel、Prognosis 校准/DCA、重复 LASSO、单层 KM
  if (dir.exists(fig_dst)) {
    if (!exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
      .ml_src("R/incidence_dual_batch_runner.R")
    }
    if (exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
      tryCatch(
        incidence_batch_purge_non_delivery_figures(fig_dst),
        error = function(e) {
          if (requireNamespace("cli", quietly = TRUE)) {
            cli::cli_alert_warning("summary_results 图清理跳过: {e$message}")
          }
        }
      )
    }
  }

  if (dir.exists(fig_dst) && exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(fig_dst, config = config),
      error = function(e) NULL
    )
  }
  ## ensure_formats 可能从旧根再生成冗余 panel → 再清一次
  if (dir.exists(fig_dst) &&
      exists("incidence_batch_purge_non_delivery_figures", mode = "function")) {
    tryCatch(incidence_batch_purge_non_delivery_figures(fig_dst), error = function(e) NULL)
  }

  ## 保留指标根已有中期 PDF
  mid_src <- list.files(index_root, pattern = "\u4e2d\u671f.*\\.pdf$", full.names = TRUE)
  mid_src <- c(mid_src, list.files(index_root, pattern = "(?i)midterm.*\\.pdf$", full.names = TRUE))
  for (f in unique(mid_src)) {
    if (file.exists(f)) {
      file.copy(f, file.path(sum_root, basename(f)), overwrite = TRUE)
    }
  }

  ## Methods + 软件版本（交付白名单）
  if (isTRUE(write_methods) && !isTRUE(figures_tables_only)) {
    if (is.null(methods_lines) || !length(methods_lines)) {
      methods_lines <- ml_index_methods_statistical_lines(config)
    }
    md_path <- file.path(sum_root, "Methods_statistical_analysis.md")
    writeLines(as.character(methods_lines), md_path, useBytes = TRUE)
    if (exists("pub_write_software_versions", mode = "function")) {
      tryCatch(
        pub_write_software_versions(sum_root, project_root = NULL, config = config),
        error = function(e) NULL
      )
    }
    if (exists("pub_write_methods_software_section", mode = "function")) {
      st <- tolower(trimws(as.character((config$project %||% list())$study_type %||% "")[1L]))
      roles <- if (identical(st, "prognosis")) {
        c(
          mice = "Multiple imputation (m=5; Rubin pool for Cox)",
          survival = "Cox proportional hazards / Kaplan-Meier",
          glmnet = "LASSO-Cox / penalized Cox",
          xgboost = "XGBoost-Cox",
          randomForestSRC = "Random survival forest",
          rms = "Restricted cubic splines",
          pROC = "Time-dependent ROC / AUC",
          forestploter = "Subgroup forest plots",
          ggplot2 = "Publication figures",
          patchwork = "Multi-panel layout",
          openxlsx = "SCI three-line tables",
          car = "Variance inflation factors"
        )
      } else {
        c(
          mice = "Multiple imputation (m=5; Rubin pool for regression)",
          survey = "NHANES complex survey design",
          rms = "Restricted cubic splines",
          glmnet = "LASSO / elastic net",
          pROC = "ROC / AUC / DeLong",
          forestploter = "Subgroup forest plots",
          ggplot2 = "Publication figures",
          patchwork = "Multi-panel layout",
          openxlsx = "SCI three-line tables",
          car = "Variance inflation factors"
        )
      }
      ## 非 NHANES 课题去掉 survey 角色
      db <- toupper(as.character((config$project %||% list())$database %||% "")[1L])
      if (!identical(db, "NHANES")) roles <- roles[names(roles) != "survey"]
      soft_tmp <- tempfile(fileext = ".md")
      tryCatch(
        {
          pub_write_methods_software_section(
            out_path = soft_tmp,
            roles = roles,
            extra_pkgs = names(roles),
            append_to = md_path
          )
          if (file.exists(soft_tmp)) unlink(soft_tmp)
          sec <- file.path(sum_root, "Methods_software_section.md")
          if (file.exists(sec)) unlink(sec)
        },
        error = function(e) NULL
      )
    }
  }

  ## 白名单修剪
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    .ml_src("R/pub_delivery_prune.R")
  }
  if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
    tryCatch(pub_delivery_normalize_fig_tab_dirs(sum_root), error = function(e) NULL)
  }
  if (exists("pub_delivery_clean_tables_xlsx_only", mode = "function")) {
    tryCatch(pub_delivery_clean_tables_xlsx_only(sum_root), error = function(e) NULL)
  }
  if (exists("pub_prune_delivery_root", mode = "function")) {
    tryCatch(
      pub_prune_delivery_root(
        sum_root,
        dry_run = FALSE,
        figures_tables_only = isTRUE(figures_tables_only)
      ),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("summary_results prune: {e$message}")
        }
      }
    )
  } else if (isTRUE(figures_tables_only)) {
    ents <- list.files(sum_root, all.files = TRUE, no.. = TRUE)
    for (nm in setdiff(ents, c("Figures", "Tables"))) {
      unlink(file.path(sum_root, nm), recursive = TRUE, force = TRUE)
    }
  }

  n_tab <- length(list.files(tab_dst, pattern = "\\.xlsx$", ignore.case = TRUE))
  n_pdf <- length(list.files(file.path(fig_dst, "pdf"), pattern = "\\.pdf$", ignore.case = TRUE))
  has_md <- file.exists(file.path(sum_root, "Methods_statistical_analysis.md"))
  has_soft <- file.exists(file.path(sum_root, "Methods_software_versions.txt"))
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      paste0(
        "指标 summary_results: ", sum_root,
        "（Tables xlsx=", n_tab, ", Figures pdf=", n_pdf,
        ", Methods=", has_md, ", software=", has_soft, "）"
      )
    )
  }
  if (n_tab < 1L || n_pdf < 1L) {
    warning(
      "ml_finalize_index_summary_results: 表或图为空 (xlsx=", n_tab, ", pdf=", n_pdf, ")",
      call. = FALSE
    )
  }
  invisible(sum_root)
}

#' finalize 挂点：从 config + ix 定位指标根并写 summary_results
ml_batch_finalize_index_summary_results <- function(root, config, ix) {
  if (!isTRUE(ml_index_summary_results_enabled(config))) {
    return(invisible(NULL))
  }
  index_root <- if (exists("incidence_batch_index_output_root", mode = "function")) {
    incidence_batch_index_output_root(config, ix)
  } else {
    file.path(root, "by_index", as.character(ix)[1L])
  }
  if (!is_absolute_path(index_root)) {
    index_root <- file.path(root, index_root)
  }
  if (!dir.exists(index_root)) {
    ## success 改名后
    alt <- file.path(
      dirname(index_root),
      paste0("\u3010success\u3011", as.character(ix)[1L])
    )
    if (dir.exists(alt)) index_root <- alt
  }
  if (!exists("export_pub_figures", mode = "function") &&
      !exists("pub_figure_ensure_formats", mode = "function")) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = root)
    pf <- file.path(eng, "R", "pub_figure_export.R")
    if (file.exists(pf)) source(pf, local = FALSE)
  }
  ml_finalize_index_summary_results(index_root, config = config)
}
