###############################################################################
# cum_egdr_kmeans_pub.R — 两波 k-means 累积暴露发表层 helpers（跨课题复用）
#
# 依赖：R/literature_ckm_cum_egdr.R（数据/索引/kmeans/OR-HR）
# 入口：run/cum_egdr_kmeans_ckm/rebuild_publication.R
# 下一课题（CHARLS 两波 × 任意 index）：用 cfg 覆盖 class_map / 暴露列 / 标签即可。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || (length(x) == 1L && is.na(x))) y else x
}

.ckm_pub_ensure_literature <- function(root = NULL) {
  root <- root %||% Sys.getenv("BLOCK_REPO_ROOT", unset = "")
  if (!nzchar(root)) root <- getwd()
  lit <- file.path(root, "R", "literature_ckm_cum_egdr.R")
  if (file.exists(lit) && !exists("ckm_stroke_fit_or_row", mode = "function")) {
    source(lit, local = FALSE)
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
ckm_stroke_resolve_engine_paths <- function(
    engine_win = "E:/01block/01Block-new-Final",
    engine_wsl = "/mnt/e/01block/01Block-new-Final",
    result_win = "G:/02block_result",
    result_wsl = "/mnt/g/02block_result") {
  is_linux <- identical(.Platform$OS.type, "unix")
  root <- if (is_linux && dir.exists(engine_wsl)) engine_wsl else if (dir.exists(engine_win)) engine_win else engine_wsl
  res_root <- if (is_linux && dir.exists(result_wsl)) result_wsl else if (dir.exists(result_win)) result_win else result_wsl
  list(root = root, res_root = res_root, is_linux = is_linux)
}

ckm_stroke_default_project_paths <- function(
    res_root,
    study_rel = file.path("46_CKM", "\u7d2f\u8ba1\u66b4\u9732\u805a\u7c7b_41654871"),
    index = "eGDR") {
  proj <- file.path(res_root, study_rel)
  list(
    proj = proj,
    checkpoint = file.path(proj, "by_unit", paste0("\u3010success\u3011", index),
                           "checkpoints", "table1_by_class_ckm.rds"),
    elbow_csv = file.path(proj, "by_unit", paste0("\u3010success\u3011", index),
                          "by_index", index, "Tables", "Kmeans_elbow_WCSS.csv"),
    summary = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results"),
    tables = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Tables"),
    figures = file.path(proj, "by_index", paste0("\u3010success\u3011", index), "summary_results", "Figures")
  )
}

# -----------------------------------------------------------------------------
# Class map (paper Class 1–4) — disease-agnostic via overrides
# -----------------------------------------------------------------------------
ckm_stroke_class_map_paper <- function(
    map = c(
      Moderate_high_stable = "Class 1",
      Persistent_low = "Class 2",
      Stable_high = "Class 3",
      Rapid_decrease = "Class 4"
    ),
    order_paper = c("Class 1", "Class 2", "Class 3", "Class 4"),
    order_table_ref_first = c("Class 2", "Class 1", "Class 3", "Class 4"),
    colors = c(`Class 1` = "#E41A1C", `Class 2` = "#4DAF4A",
               `Class 3` = "#377EB8", `Class 4` = "#984EA3"),
    shapes = c(`Class 1` = 16, `Class 2` = 17, `Class 3` = 15, `Class 4` = 8),
    semantic_of = NULL) {
  if (is.null(semantic_of)) {
    semantic_of <- setNames(names(map), unname(map))
  }
  list(
    map = map,
    order_paper = order_paper,
    order_table_ref_first = order_table_ref_first,
    colors = colors,
    shapes = shapes,
    semantic_of = semantic_of,
    ref_class = "Class 2",
    ref_semantic = "Persistent_low"
  )
}

ckm_stroke_attach_class_paper <- function(data, class_col = "eGDR_Class",
                                          cmap = ckm_stroke_class_map_paper()) {
  stopifnot(class_col %in% names(data))
  data$Class_paper <- factor(
    unname(cmap$map[as.character(data[[class_col]])]),
    levels = cmap$order_paper
  )
  data[[class_col]] <- stats::relevel(
    factor(data[[class_col]]),
    ref = cmap$ref_semantic
  )
  data
}

# Safe relevel: if reference level absent in a stratum, keep factor as-is (fit returns NE)
.ckm_relevel_class_safe <- function(x, ref) {
  x <- factor(x)
  if (as.character(ref)[1L] %in% levels(x)) {
    stats::relevel(x, ref = as.character(ref)[1L])
  } else {
    x
  }
}

# -----------------------------------------------------------------------------
# Formatting
# -----------------------------------------------------------------------------
ckm_stroke_fmt_p <- function(p) {
  if (length(p) != 1L || is.na(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
ckm_stroke_fmt_orci <- function(or, lo, hi) {
  if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("NE")
  sprintf("%.2f (%.2f\u2013%.2f)", or, lo, hi)
}
ckm_stroke_fmt_or_tilde <- function(est, lo, hi, digits = 2L) {
  # 与表内 OR/HR 一致：en-dash（–），不用波浪号 ~
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return("")
  sprintf(
    paste0("%.", digits, "f (%.", digits, "f\u2013%.", digits, "f)"),
    est, lo, hi
  )
}
ckm_stroke_mean_sd <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (!length(x)) return("")
  sprintf("%.2f (%.2f)", mean(x), stats::sd(x))
}
ckm_stroke_n_pct <- function(n, den) {
  if (!is.finite(den) || den <= 0) return("")
  sprintf("%d (%.1f)", as.integer(n), 100 * n / den)
}
ckm_stroke_events_cell <- function(y) {
  y <- as.integer(y == 1L)
  ckm_stroke_n_pct(sum(y, na.rm = TRUE), sum(!is.na(y)))
}

# -----------------------------------------------------------------------------
# Forest / subgroup groups
# -----------------------------------------------------------------------------
ckm_stroke_prepare_forest_groups <- function(
    df,
    age_cutoff = 60L,
    bmi_cut = 30,
    age_labels_compact = TRUE,
    drop_extreme_bmi = FALSE,
    ckm_col = "CKM_stage") {
  .ckm_pub_ensure_literature()
  df <- ckm_stroke_prepare_age_group(df, age_cutoff)
  cut <- as.numeric(age_cutoff)[1L]
  if ("Age" %in% names(df)) {
    if (isTRUE(age_labels_compact)) {
      df$Age_Group <- factor(
        ifelse(as.numeric(df$Age) < cut, paste0("<", cut), paste0(">=", cut)),
        levels = c(paste0("<", cut), paste0(">=", cut))
      )
    } else {
      df$Age_Group <- factor(
        ifelse(as.numeric(df$Age) < cut, paste0("< ", cut), paste0("\u2265 ", cut)),
        levels = c(paste0("< ", cut), paste0("\u2265 ", cut))
      )
    }
  }
  if ("BMI" %in% names(df)) {
    bmi <- as.numeric(df$BMI)
    if (isTRUE(drop_extreme_bmi)) {
      bmi[!is.finite(bmi) | bmi < 10 | bmi > 80] <- NA_real_
      df$BMI <- bmi
    }
    lab_lo <- if (isTRUE(age_labels_compact)) paste0("<", bmi_cut) else paste0("< ", bmi_cut)
    lab_hi <- if (isTRUE(age_labels_compact)) paste0(">=", bmi_cut) else paste0("\u2265 ", bmi_cut)
    df$BMI_Group <- factor(
      ifelse(is.finite(bmi) & bmi < bmi_cut, lab_lo,
             ifelse(is.finite(bmi), lab_hi, NA_character_)),
      levels = c(lab_lo, lab_hi)
    )
  }
  .yes_no_to_never_ever <- function(x) {
    x <- as.character(x)
    out <- rep(NA_character_, length(x))
    out[x %in% c("Yes", "Ever", "ever", "Current", "Former")] <- "Ever"
    out[x %in% c("No", "Never", "never")] <- "Never"
    factor(out, levels = c("Never", "Ever"))
  }
  if ("Smoke" %in% names(df)) df$Smoke_ne <- .yes_no_to_never_ever(df$Smoke)
  if ("Drink" %in% names(df)) df$Drink_ne <- .yes_no_to_never_ever(df$Drink)
  if (ckm_col %in% names(df)) {
    st <- as.integer(as.numeric(as.character(df[[ckm_col]])))
    # Table3 style (en-dash) + forest style (hyphen)
    df$CKM_group <- factor(
      ifelse(st %in% 0:2, "0\u20132", ifelse(st %in% 3:4, "3\u20134", NA)),
      levels = c("0\u20132", "3\u20134")
    )
    df$CKM_stage_group <- factor(
      ifelse(st %in% 0:2, "0-2", ifelse(st %in% 3:4, "3-4", NA_character_)),
      levels = c("0-2", "3-4")
    )
  }
  if ("Gender" %in% names(df)) {
    df$Gender <- factor(as.character(df$Gender), levels = c("Female", "Male"))
  }
  if (!"Hypertension" %in% names(df)) {
    if ("Hypertension_t2" %in% names(df)) {
      df$Hypertension <- df$Hypertension_t2
    } else if ("htn1" %in% names(df)) {
      df$Hypertension <- factor(
        ifelse(as.integer(df$htn1) == 1L, "Yes", "No"),
        levels = c("No", "Yes")
      )
    }
  }
  df
}

# LRT P for interaction — glm: Pr(>Chi); coxph: Pr(>|Chi|) via test=Chisq
ckm_stroke_lrt_pint <- function(df, expo, sg_var, covars, is_hr = FALSE,
                                outcome = "Stroke") {
  need <- unique(c(expo, sg_var, covars, if (is_hr) c("futime", "status") else outcome))
  need <- intersect(need, names(df))
  d <- df[, need, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 40L) return(NA_real_)
  d[[sg_var]] <- factor(d[[sg_var]])
  if (nlevels(d[[sg_var]]) < 2L) return(NA_real_)
  if (!is_hr && outcome %in% names(d)) {
    d[[outcome]] <- as.integer(as.numeric(d[[outcome]]) == 1L)
  }
  rhs0 <- paste(c(expo, sg_var, covars), collapse = " + ")
  rhs1 <- paste(c(paste0(expo, " * ", sg_var), covars), collapse = " + ")
  if (is_hr) {
    f0 <- stats::as.formula(paste("survival::Surv(futime, status) ~", rhs0))
    f1 <- stats::as.formula(paste("survival::Surv(futime, status) ~", rhs1))
    m0 <- tryCatch(survival::coxph(f0, data = d), error = function(e) NULL)
    m1 <- tryCatch(survival::coxph(f1, data = d), error = function(e) NULL)
  } else {
    f0 <- stats::as.formula(paste(outcome, "~", rhs0))
    f1 <- stats::as.formula(paste(outcome, "~", rhs1))
    m0 <- tryCatch(stats::glm(f0, data = d, family = stats::binomial()), error = function(e) NULL)
    m1 <- tryCatch(stats::glm(f1, data = d, family = stats::binomial()), error = function(e) NULL)
  }
  if (is.null(m0) || is.null(m1)) return(NA_real_)
  a <- tryCatch({
    if (is_hr) stats::anova(m0, m1, test = "Chisq") else stats::anova(m0, m1, test = "LRT")
  }, error = function(e) NULL)
  if (is.null(a)) return(NA_real_)
  pcol <- intersect(c("Pr(>Chi)", "Pr(>|Chi|)", "Pr(>Chisq)", "P(>|Chi|)"), names(a))
  if (!length(pcol)) return(NA_real_)
  as.numeric(a[[pcol[1L]]][2L])
}

# -----------------------------------------------------------------------------
# Table 1
# -----------------------------------------------------------------------------
ckm_stroke_build_table1_by_class <- function(
    data,
    class_col = "Class_paper",
    cmap = ckm_stroke_class_map_paper(),
    exposure_cols = c(cum = "cum_eGDR", t1 = "eGDR_t1", t2 = "eGDR_t2"),
    exposure_labs = c(
      cum = "Cumulative eGDR, mean (SD)",
      t1 = "eGDR2012, mean (SD)",
      t2 = "eGDR2015, mean (SD)"
    ),
    outcome = "Stroke",
    outcome_lab = "Incident stroke, n (%)") {
  levels_cls <- cmap$order_paper
  cls <- factor(data[[class_col]], levels = levels_cls)
  n_all <- nrow(data)
  n_by_class <- as.integer(table(cls))
  names(n_by_class) <- names(table(cls))

  .empty_row <- function(lab, p = "") {
    data.frame(
      Characteristics = lab, Overall = "",
      `Class 1` = "", `Class 2` = "", `Class 3` = "", `Class 4` = "",
      `P-value` = p, check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  .cont_row <- function(lab, x) {
    overall <- ckm_stroke_mean_sd(x)
    by <- vapply(levels_cls, function(lv) ckm_stroke_mean_sd(x[as.character(cls) == lv]), character(1))
    pv <- tryCatch(stats::kruskal.test(x ~ cls)$p.value, error = function(e) NA_real_)
    data.frame(
      Characteristics = lab, Overall = overall,
      `Class 1` = by["Class 1"], `Class 2` = by["Class 2"],
      `Class 3` = by["Class 3"], `Class 4` = by["Class 4"],
      `P-value` = ckm_stroke_fmt_p(pv),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  .cat_block <- function(lab, x) {
    x <- factor(x)
    pv <- tryCatch(suppressWarnings(stats::chisq.test(table(x, cls))$p.value),
                   error = function(e) NA_real_)
    rows <- list(.empty_row(lab, ckm_stroke_fmt_p(pv)))
    for (lvx in levels(x)) {
      n_o <- sum(as.character(x) == lvx, na.rm = TRUE)
      den_o <- sum(!is.na(x))
      by <- vapply(levels_cls, function(lv) {
        keep <- as.character(cls) == lv
        n <- sum(as.character(x[keep]) == lvx, na.rm = TRUE)
        den <- sum(!is.na(x[keep]))
        ckm_stroke_n_pct(n, den)
      }, character(1))
      rows[[length(rows) + 1L]] <- data.frame(
        Characteristics = paste0("  ", lvx),
        Overall = ckm_stroke_n_pct(n_o, den_o),
        `Class 1` = by["Class 1"], `Class 2` = by["Class 2"],
        `Class 3` = by["Class 3"], `Class 4` = by["Class 4"],
        `P-value` = "", check.names = FALSE, stringsAsFactors = FALSE
      )
    }
    do.call(rbind, rows)
  }

  parts <- list()
  parts[[length(parts) + 1L]] <- .empty_row("Demographics")
  if ("Age" %in% names(data)) parts[[length(parts) + 1L]] <- .cont_row("Age, mean (SD), years", data$Age)
  if ("Gender" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Gender, n (%)", data$Gender)
  if ("BMI" %in% names(data)) parts[[length(parts) + 1L]] <- .cont_row("BMI, mean (SD), kg/m\u00b2", data$BMI)
  if ("Education" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Educational level, n (%)", data$Education)
  if ("Smoke" %in% names(data)) {
    sm <- factor(ifelse(as.character(data$Smoke) == "Yes", "Ever",
                 ifelse(as.character(data$Smoke) == "No", "Never", NA_character_)),
                 levels = c("Never", "Ever"))
    parts[[length(parts) + 1L]] <- .cat_block("Smoking status, n (%)", sm)
  }
  if ("Drink" %in% names(data)) {
    dr <- factor(ifelse(as.character(data$Drink) == "Yes", "Ever",
                 ifelse(as.character(data$Drink) == "No", "Never", NA_character_)),
                 levels = c("Never", "Ever"))
    parts[[length(parts) + 1L]] <- .cat_block("Drinking status, n (%)", dr)
  }
  if ("Marital" %in% names(data)) parts[[length(parts) + 1L]] <- .cat_block("Marital status, n (%)", data$Marital)

  parts[[length(parts) + 1L]] <- .empty_row("Vital signs and laboratory tests")
  for (v in c("SBP", "DBP", "Waist_circumference", "Glucose", "Total_Cholesterol",
              "Triglycerides", "HDL", "LDL", "HbA1c", "UA", "eGFR")) {
    if (!v %in% names(data)) next
    lab <- switch(v,
      SBP = "SBP, mean (SD), mmHg", DBP = "DBP, mean (SD), mmHg",
      Waist_circumference = "WC, mean (SD), cm",
      Glucose = "Glucose, mean (SD), mg/dL",
      Total_Cholesterol = "TC, mean (SD), mg/dL",
      Triglycerides = "TG, mean (SD), mg/dL",
      HDL = "HDL, mean (SD), mg/dL", LDL = "LDL, mean (SD), mg/dL",
      HbA1c = "HbA1c, mean (SD), %", UA = "Uric acid, mean (SD), mg/dL",
      eGFR = "eGFR, mean (SD), mL/min/1.73 m\u00b2", v
    )
    parts[[length(parts) + 1L]] <- .cont_row(lab, data[[v]])
  }

  parts[[length(parts) + 1L]] <- .empty_row("Comorbidities")
  for (v in c("Hypertension", "Diabetes", "Dyslipidemia")) {
    if (!v %in% names(data)) next
    parts[[length(parts) + 1L]] <- .cat_block(paste0(v, ", n (%)"), data[[v]])
  }
  if (outcome %in% names(data)) {
    st <- factor(ifelse(as.integer(data[[outcome]]) == 1L, "Yes", "No"), levels = c("No", "Yes"))
    parts[[length(parts) + 1L]] <- .cat_block(
      as.character(outcome_lab %||% "Incident stroke, n (%)")[1L], st
    )
  }
  if ("CKM_stage" %in% names(data)) {
    st_vals <- sort(unique(stats::na.omit(as.integer(data$CKM_stage))))
    ckf <- factor(paste0("Stage ", as.integer(data$CKM_stage)),
                  levels = paste0("Stage ", st_vals))
    parts[[length(parts) + 1L]] <- .cat_block("CKM syndrome stages, n (%)", ckf)
  }

  parts[[length(parts) + 1L]] <- .empty_row("Exposure")
  for (nm in names(exposure_cols)) {
    col <- exposure_cols[[nm]]
    if (!col %in% names(data)) next
    lab <- exposure_labs[[nm]] %||% paste0(col, ", mean (SD)")
    parts[[length(parts) + 1L]] <- .cont_row(lab, data[[col]])
  }

  t1 <- do.call(rbind, parts)
  rownames(t1) <- NULL
  names(t1) <- c(
    "Characteristics",
    sprintf("Overall\n(N = %s)", format(n_all, big.mark = ",")),
    sprintf("Class 1\n(N = %s)", format(n_by_class[["Class 1"]] %||% 0L, big.mark = ",")),
    sprintf("Class 2\n(N = %s)", format(n_by_class[["Class 2"]] %||% 0L, big.mark = ",")),
    sprintf("Class 3\n(N = %s)", format(n_by_class[["Class 3"]] %||% 0L, big.mark = ",")),
    sprintf("Class 4\n(N = %s)", format(n_by_class[["Class 4"]] %||% 0L, big.mark = ",")),
    "P-value"
  )
  level_idx <- which(grepl("^  ", t1[[1]])) + 1L
  list(df = t1, n_all = n_all, n_by_class = n_by_class, excel_level_row_idx = level_idx)
}

ckm_stroke_style_table1_xlsx <- function(xlsx_path) {
  # R/openxlsx 加粗小节标题（Demographics 等）；不依赖 Windows python3
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    warning("openxlsx missing; skip Table1 style: ", xlsx_path)
    return(invisible(FALSE))
  }
  if (!file.exists(xlsx_path)) return(invisible(FALSE))
  wb <- openxlsx::loadWorkbook(xlsx_path)
  sh <- names(wb)[1L]
  vals <- openxlsx::read.xlsx(xlsx_path, sheet = 1L, colNames = FALSE)
  secs <- c(
    "Demographics",
    "Vital signs and laboratory tests",
    "Comorbidities",
    "Exposure"
  )
  levels <- c(
    "Female", "Male", "Never", "Ever", "Single", "Married", "No", "Yes",
    "Illiterate", "Primary", "Middle", "High+",
    "Below High school", "High school and above",
    "Stage 0", "Stage 1", "Stage 2", "Stage 3", "Stage 4"
  )
  sty_sec <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "left", valign = "center"
  )
  sty_plain <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12,
    halign = "left", valign = "center", indent = 1L
  )
  sty_var <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12,
    halign = "left", valign = "center"
  )
  sty_title <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "left", valign = "center"
  )
  # 表题 + Characteristics 表头加粗
  openxlsx::addStyle(wb, sh, sty_title, rows = 1L, cols = 1L, stack = TRUE)
  if (nrow(vals) >= 2L) {
    openxlsx::addStyle(wb, sh, sty_title, rows = 2L, cols = seq_len(ncol(vals)), stack = TRUE)
  }
  for (i in seq_len(nrow(vals))) {
    v <- as.character(vals[i, 1L])
    if (is.na(v) || !nzchar(v)) next
    if (grepl("^(Values are|Class mapping|Analytic|Section order)", v)) break
    vs <- trimws(v)
    if (vs %in% secs) {
      openxlsx::addStyle(wb, sh, sty_sec, rows = i, cols = 1L, stack = TRUE)
    } else if (startsWith(v, "  ") || vs %in% levels) {
      # 分类水平：去前导空格 + 缩进样式
      openxlsx::writeData(wb, sh, vs, startCol = 1L, startRow = i, colNames = FALSE)
      openxlsx::addStyle(wb, sh, sty_plain, rows = i, cols = 1L, stack = TRUE)
    } else if (i > 2L) {
      openxlsx::addStyle(wb, sh, sty_var, rows = i, cols = 1L, stack = TRUE)
    }
  }
  openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  invisible(TRUE)
}

#' 写入分析软件版本说明（Nature 统计报告要求）
ckm_stroke_write_software_versions <- function(out_dir, extra = character(0)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  pkgs <- c(
    "rms", "survival", "ggplot2", "forestploter", "mice",
    "openxlsx", "data.table", "arrow"
  )
  lines <- c(
    "Statistical software and package versions",
    sprintf("R version: %s", paste(R.version$major, R.version$minor, sep = ".")),
    sprintf("Platform: %s", R.version$platform),
    ""
  )
  for (p in pkgs) {
    ver <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed")
    lines <- c(lines, sprintf("%s: %s", p, ver))
  }
  if (length(extra)) lines <- c(lines, "", extra)
  lines <- c(
    lines,
    "",
    "Primary analyses: logistic / Cox models (glm, survival::coxph); restricted cubic splines (rms::rcs);",
    "k-means clustering (stats::kmeans); forest plots (forestploter); multiple imputation (mice) where applicable."
  )
  out <- file.path(out_dir, "Methods_software_versions.txt")
  writeLines(lines, out, useBytes = TRUE)
  invisible(out)
}

#' 表脚注用的一行软件版本（复用，勿课题手写）
ckm_stroke_software_footnote <- function() {
  sprintf(
    "Software: see Methods_software_versions.txt (R %s; rms/survival/ggplot2/forestploter/mice).",
    paste(R.version$major, R.version$minor, sep = ".")
  )
}

# -----------------------------------------------------------------------------
# Association tables (Table2 / S1 / S3 / S4)
# -----------------------------------------------------------------------------
.ckm_get_term <- function(fit_df, term_pat) {
  if (is.null(fit_df) || !nrow(fit_df)) return(NULL)
  hit <- grepl(term_pat, fit_df$term)
  if (!any(hit)) return(NULL)
  fit_df[which(hit)[1L], , drop = FALSE]
}

.ckm_p_trend_class <- function(d, covars, is_hr = FALSE, outcome = "Stroke",
                               cmap = ckm_stroke_class_map_paper()) {
  d$Class_num <- as.integer(factor(as.character(d$Class_paper), levels = cmap$order_paper))
  keep <- unique(c(if (is_hr) c("futime", "status") else outcome, "Class_num", covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L) return(NA_real_)
  if (is_hr) {
    fml <- if (length(covars)) {
      stats::as.formula(paste("survival::Surv(futime, status) ~ Class_num +",
                              paste(covars, collapse = "+")))
    } else survival::Surv(futime, status) ~ Class_num
    fit <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    return(as.numeric(summary(fit)$coefficients["Class_num", 5]))
  }
  fml <- if (length(covars)) {
    stats::as.formula(paste(outcome, "~ Class_num +", paste(covars, collapse = "+")))
  } else stats::as.formula(paste(outcome, "~ Class_num"))
  fit <- tryCatch(stats::glm(fml, data = dd, family = binomial()), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  as.numeric(summary(fit)$coefficients["Class_num", 4])
}

.ckm_p_trend_tert <- function(d, covars, is_hr = FALSE, outcome = "Stroke",
                              tert_col = "eGDR_tertile") {
  d$T_num <- as.integer(factor(as.character(d[[tert_col]]), levels = c("T1", "T2", "T3")))
  keep <- unique(c(if (is_hr) c("futime", "status") else outcome, "T_num", covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L) return(NA_real_)
  if (is_hr) {
    fml <- if (length(covars)) {
      stats::as.formula(paste("survival::Surv(futime, status) ~ T_num +", paste(covars, collapse = "+")))
    } else survival::Surv(futime, status) ~ T_num
    fit <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    return(as.numeric(summary(fit)$coefficients["T_num", 5]))
  }
  fml <- if (length(covars)) {
    stats::as.formula(paste(outcome, "~ T_num +", paste(covars, collapse = "+")))
  } else stats::as.formula(paste(outcome, "~ T_num"))
  fit <- tryCatch(stats::glm(fml, data = dd, family = binomial()), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  as.numeric(summary(fit)$coefficients["T_num", 4])
}

ckm_stroke_build_table2_assoc <- function(
    data, models, is_hr = FALSE,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cont_col = "cum_eGDR",
    tert_col = "eGDR_tertile",
    cmap = ckm_stroke_class_map_paper(),
    index_lab = "eGDR") {
  .ckm_pub_ensure_literature()
  index_lab <- as.character(index_lab %||% "eGDR")[1L]
  if (!nzchar(index_lab)) index_lab <- "eGDR"
  est_lab <- if (is_hr) "HR (95% CI)" else "OR (95% CI)"
  n_all <- nrow(data)

  d0 <- data
  d0[[class_col]] <- stats::relevel(factor(d0[[class_col]]), ref = cmap$ref_semantic)
  .model_names <- c("Model1", "Model2", "Model3")
  class_fits <- list()
  for (mn in .model_names) {
    class_fits[[mn]] <- if (is_hr) ckm_stroke_fit_hr_row(d0, class_col, models[[mn]])
    else ckm_stroke_fit_or_row(d0, class_col, outcome, models[[mn]])
  }
  cont_fits <- list()
  for (mn in .model_names) {
    cont_fits[[mn]] <- if (is_hr) ckm_stroke_fit_hr_row(data, cont_col, models[[mn]])
    else ckm_stroke_fit_or_row(data, cont_col, outcome, models[[mn]])
  }
  dtert <- data
  dtert[[tert_col]] <- stats::relevel(factor(dtert[[tert_col]]), ref = "T1")
  tert_fits <- list()
  for (mn in .model_names) {
    tert_fits[[mn]] <- if (is_hr) ckm_stroke_fit_hr_row(dtert, tert_col, models[[mn]])
    else ckm_stroke_fit_or_row(dtert, tert_col, outcome, models[[mn]])
  }

  .model_cells <- function(rr, term_pat) {
    out <- list()
    for (mn in c("Model1", "Model2", "Model3")) {
      hit <- .ckm_get_term(rr[[mn]], term_pat)
      if (is.null(hit)) {
        out[[paste0(mn, "_est")]] <- ""; out[[paste0(mn, "_p")]] <- ""
      } else if (is_hr) {
        out[[paste0(mn, "_est")]] <- ckm_stroke_fmt_orci(hit$HR, hit$CI_low, hit$CI_high)
        out[[paste0(mn, "_p")]] <- ckm_stroke_fmt_p(hit$P)
      } else {
        out[[paste0(mn, "_est")]] <- ckm_stroke_fmt_orci(hit$OR, hit$CI_low, hit$CI_high)
        out[[paste0(mn, "_p")]] <- ckm_stroke_fmt_p(hit$P)
      }
    }
    out
  }
  mk_row <- function(var, n, ev, cells, is_ref = FALSE) {
    if (is_ref) {
      data.frame(
        Variable = var, `Total number` = as.character(n), `Events, n (%)` = ev,
        Model1_OR = "Reference", Model1_P = "", Model2_OR = "Reference", Model2_P = "",
        Model3_OR = "Reference", Model3_P = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        Variable = var, `Total number` = as.character(n), `Events, n (%)` = ev,
        Model1_OR = cells$Model1_est, Model1_P = cells$Model1_p,
        Model2_OR = cells$Model2_est, Model2_P = cells$Model2_p,
        Model3_OR = cells$Model3_est, Model3_P = cells$Model3_p,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  sec <- function(lab) {
    data.frame(
      Variable = lab, `Total number` = "", `Events, n (%)` = "",
      Model1_OR = "", Model1_P = "", Model2_OR = "", Model2_P = "",
      Model3_OR = "", Model3_P = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }

  rows <- list(sec(sprintf("%s change patterns", index_lab)))
  for (cl in cmap$order_table_ref_first) {
    keep <- as.character(data$Class_paper) == cl
    n <- sum(keep)
    ev <- ckm_stroke_events_cell(data[[outcome]][keep])
    if (cl == cmap$ref_class) {
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", cl), n, ev, NULL, is_ref = TRUE)
    } else {
      sem <- names(cmap$map)[cmap$map == cl]
      cells <- .model_cells(class_fits, paste0(sem, "$"))
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", cl), n, ev, cells)
    }
  }
  rows[[length(rows) + 1L]] <- {
    cells <- .model_cells(cont_fits, paste0("^", cont_col, "$"))
    mk_row(sprintf("Cumulative %s", index_lab), n_all, ckm_stroke_events_cell(data[[outcome]]), cells)
  }
  rows[[length(rows) + 1L]] <- sec(sprintf("Tertiles of cumulative %s", index_lab))
  for (tv in c("T1", "T2", "T3")) {
    keep <- as.character(data[[tert_col]]) == tv
    n <- sum(keep, na.rm = TRUE)
    ev <- ckm_stroke_events_cell(data[[outcome]][keep])
    if (tv == "T1") {
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", tv), n, ev, NULL, is_ref = TRUE)
    } else {
      cells <- .model_cells(tert_fits, paste0(tv, "$"))
      rows[[length(rows) + 1L]] <- mk_row(paste0("  ", tv), n, ev, cells)
    }
  }
  ptr <- vapply(.model_names, function(mn) {
    ckm_stroke_fmt_p(.ckm_p_trend_tert(data, models[[mn]], is_hr = is_hr,
                                       outcome = outcome, tert_col = tert_col))
  }, character(1))
  names(ptr) <- .model_names
  rows[[length(rows) + 1L]] <- data.frame(
    Variable = "  P for trend",
    `Total number` = "", `Events, n (%)` = "",
    Model1_OR = "", Model1_P = ptr[["Model1"]],
    Model2_OR = "", Model2_P = ptr[["Model2"]],
    Model3_OR = "", Model3_P = ptr[["Model3"]],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  names(out) <- c("Variable", "Total number", "Events, n (%)",
                  "M1e", "M1p", "M2e", "M2p", "M3e", "M3p")
  list(df = out, est_lab = est_lab)
}

ckm_stroke_build_table_s1_cox <- function(...) {
  ckm_stroke_build_table2_assoc(..., is_hr = TRUE)
}

ckm_stroke_export_assoc_xlsx <- function(built, filepath, title, footnotes) {
  df <- built$df
  h1 <- c("Variable", "Total number", "Events, n (%)",
          "Model 1", "Model 1", "Model 2", "Model 2", "Model 3", "Model 3")
  h2 <- c("", "", "",
          built$est_lab, "P value",
          built$est_lab, "P value",
          built$est_lab, "P value")
  export_sci_table(
    df, filepath, title = title,
    header_row1 = h1, header_row2 = h2,
    latex_include_colnames = FALSE,
    table_footnotes = footnotes,
    excel_level_row_idx = which(grepl("^  ", df$Variable) & df$Variable != "  P for trend")
  )
}

# -----------------------------------------------------------------------------
# Table 3 subgroup (Class2 ref wide)
# -----------------------------------------------------------------------------
ckm_stroke_build_table3_subgroup <- function(
    data, models,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cmap = ckm_stroke_class_map_paper(),
    sg_defs = NULL) {
  .ckm_pub_ensure_literature()
  data_sg <- ckm_stroke_prepare_forest_groups(
    data, age_labels_compact = FALSE, drop_extreme_bmi = FALSE
  )
  if (is.null(sg_defs)) {
    sg_defs <- list(
      list(label = "Age, years", var = "Age_Group"),
      list(label = "Gender", var = "Gender"),
      list(label = "BMI, kg/m\u00b2", var = "BMI_Group"),
      list(label = "Smoke", var = "Smoke_ne"),
      list(label = "Drink", var = "Drink_ne"),
      list(label = "Dyslipidemia", var = "Dyslipidemia"),
      list(label = "Diabetes", var = "Diabetes"),
      list(label = "CKM", var = "CKM_group")
    )
  }
  .cov_drop <- function(sg_var) {
    if (sg_var == "Age_Group") return("Age")
    if (sg_var == "BMI_Group") return("BMI")
    if (sg_var == "Smoke_ne") return("Smoke")
    if (sg_var == "Drink_ne") return("Drink")
    if (sg_var %in% c("Gender", "Dyslipidemia", "Diabetes")) return(sg_var)
    character(0)
  }
  t3_rows <- list()
  for (sg in sg_defs) {
    if (!sg$var %in% names(data_sg)) next
    cov_base <- setdiff(models$Model3, .cov_drop(sg$var))
    pint <- ckm_stroke_lrt_pint(data_sg, class_col, sg$var, cov_base,
                                is_hr = FALSE, outcome = outcome)
    t3_rows[[length(t3_rows) + 1L]] <- data.frame(
      Subgroup = sg$label,
      `Class 2` = "", `Class 1` = "", `Class 3` = "", `Class 4` = "",
      `P for trend` = "", `P for interaction` = ckm_stroke_fmt_p(pint),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    for (lv in levels(factor(data_sg[[sg$var]]))) {
      dsub <- data_sg[as.character(data_sg[[sg$var]]) == lv, , drop = FALSE]
      cov <- setdiff(models$Model3, .cov_drop(sg$var))
      dsub[[class_col]] <- .ckm_relevel_class_safe(dsub[[class_col]], cmap$ref_semantic)
      rr <- if (nrow(dsub) >= 40L) ckm_stroke_fit_or_row(dsub, class_col, outcome, cov) else NULL
      cell <- function(pat) {
        h <- .ckm_get_term(rr, pat)
        if (is.null(h)) return("NE")
        ckm_stroke_fmt_orci(h$OR, h$CI_low, h$CI_high)
      }
      ptr <- ckm_stroke_fmt_p(.ckm_p_trend_class(dsub, cov, is_hr = FALSE,
                                                 outcome = outcome, cmap = cmap))
      t3_rows[[length(t3_rows) + 1L]] <- data.frame(
        Subgroup = paste0("  ", lv),
        `Class 2` = "Reference",
        `Class 1` = cell("Moderate_high_stable"),
        `Class 3` = cell("Stable_high"),
        `Class 4` = cell("Rapid_decrease"),
        `P for trend` = ptr, `P for interaction` = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  t3 <- do.call(rbind, t3_rows)
  rownames(t3) <- NULL
  names(t3) <- c("Subgroup", "Class 2 Reference", "Class 1", "Class 3", "Class 4",
                 "P for trend", "P for interaction")
  list(df = t3, excel_level_row_idx = which(grepl("^  ", t3$Subgroup)) + 1L)
}

# -----------------------------------------------------------------------------
# Table S2 MOESM long
# -----------------------------------------------------------------------------
ckm_stroke_build_table_s2_long <- function(
    data, models,
    outcome = "Stroke",
    class_col = "eGDR_Class",
    cmap = ckm_stroke_class_map_paper(),
    sg_defs = NULL) {
  .ckm_pub_ensure_literature()
  data_sg <- ckm_stroke_prepare_forest_groups(
    data, age_labels_compact = FALSE, drop_extreme_bmi = FALSE
  )
  if (is.null(sg_defs)) {
    sg_defs <- list(
      list(label = "Age, years", var = "Age_Group"),
      list(label = "Gender", var = "Gender"),
      list(label = "BMI, kg/m\u00b2", var = "BMI_Group"),
      list(label = "Smoke", var = "Smoke_ne"),
      list(label = "Drink", var = "Drink_ne"),
      list(label = "Dyslipidemia", var = "Dyslipidemia"),
      list(label = "Diabetes", var = "Diabetes"),
      list(label = "CKM", var = "CKM_group")
    )
  }
  .cov_drop <- function(sg_var) {
    if (sg_var == "Age_Group") return("Age")
    if (sg_var == "BMI_Group") return("BMI")
    if (sg_var == "Smoke_ne") return("Smoke")
    if (sg_var == "Drink_ne") return("Drink")
    if (sg_var %in% c("Gender", "Dyslipidemia", "Diabetes")) return(sg_var)
    character(0)
  }
  rows <- list()
  for (sg in sg_defs) {
    if (!sg$var %in% names(data_sg)) next
    cov <- setdiff(models$Model3, .cov_drop(sg$var))
    pint <- ckm_stroke_lrt_pint(data_sg, class_col, sg$var, cov, is_hr = TRUE, outcome = outcome)
    rows[[length(rows) + 1L]] <- data.frame(
      Subgroup = sg$label, Variable = "", N = "", `Events, n (%)` = "",
      `HR (95%CI)` = "", `P value` = "", `P for interaction` = ckm_stroke_fmt_p(pint),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    for (lv in levels(factor(data_sg[[sg$var]]))) {
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = lv, Variable = "", N = "", `Events, n (%)` = "",
        `HR (95%CI)` = "", `P value` = "", `P for interaction` = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
      dsub <- data_sg[as.character(data_sg[[sg$var]]) == lv, , drop = FALSE]
      dsub[[class_col]] <- .ckm_relevel_class_safe(dsub[[class_col]], cmap$ref_semantic)
      rr <- if (nrow(dsub) >= 40L) ckm_stroke_fit_hr_row(dsub, class_col, cov) else NULL
      for (cl in cmap$order_table_ref_first) {
        keep <- as.character(dsub$Class_paper) == cl
        n <- sum(keep)
        ev <- ckm_stroke_events_cell(dsub[[outcome]][keep])
        if (cl == cmap$ref_class) {
          hr_cell <- "1(Ref)"; p_cell <- ""
        } else {
          sem <- names(cmap$map)[cmap$map == cl]
          h <- .ckm_get_term(rr, paste0(sem, "$"))
          if (is.null(h)) {
            hr_cell <- "NE"; p_cell <- ""
          } else {
            hr_cell <- ckm_stroke_fmt_orci(h$HR, h$CI_low, h$CI_high)
            p_cell <- ckm_stroke_fmt_p(h$P)
          }
        }
        rows[[length(rows) + 1L]] <- data.frame(
          Subgroup = "", Variable = tolower(gsub(" ", "", cl)),
          N = as.character(n), `Events, n (%)` = ev,
          `HR (95%CI)` = hr_cell, `P value` = p_cell, `P for interaction` = "",
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
      ptr <- .ckm_p_trend_class(dsub, cov, is_hr = TRUE, outcome = outcome, cmap = cmap)
      n_tot <- nrow(dsub)
      ev_tot <- ckm_stroke_events_cell(dsub[[outcome]])
      dsub$Class_num <- as.integer(factor(as.character(dsub$Class_paper), levels = cmap$order_paper))
      trend_hr <- tryCatch({
        keep <- unique(c("futime", "status", "Class_num", cov))
        dd <- dsub[, intersect(keep, names(dsub)), drop = FALSE]
        dd <- dd[stats::complete.cases(dd), , drop = FALSE]
        fit <- survival::coxph(
          stats::as.formula(paste("survival::Surv(futime, status) ~ Class_num +",
                                  paste(cov, collapse = "+"))), data = dd)
        sm <- summary(fit)$coefficients
        ci <- exp(stats::confint(fit))
        ckm_stroke_fmt_orci(exp(sm["Class_num", 1]), ci["Class_num", 1], ci["Class_num", 2])
      }, error = function(e) "")
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = "", Variable = "P for trend",
        N = as.character(n_tot), `Events, n (%)` = ev_tot,
        `HR (95%CI)` = trend_hr, `P value` = ckm_stroke_fmt_p(ptr),
        `P for interaction` = "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  list(df = out)
}

# -----------------------------------------------------------------------------
# Figure 2: A elbow | B scatter+hull | C mean±SE
# -----------------------------------------------------------------------------
ckm_stroke_theme_paper <- function(base = 11) {
  ggplot2::theme_classic(base_size = base) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = base + 2, hjust = 0),
      axis.title = ggplot2::element_text(size = base),
      axis.text = ggplot2::element_text(color = "black", size = base - 1),
      legend.title = ggplot2::element_text(size = base - 1),
      legend.text = ggplot2::element_text(size = base - 1),
      panel.grid = ggplot2::element_blank(),
      legend.key = ggplot2::element_blank()
    )
}

ckm_stroke_fig2_abc <- function(
    data,
    elbow_csv = NULL,
    outfile = NULL,
    t1_col = "eGDR_t1",
    t2_col = "eGDR_t2",
    class_col = "Class_paper",
    cmap = ckm_stroke_class_map_paper(),
    chosen_k = 4L,
    year_labs = c(2012, 2015),
    ylab_c = "Mean eGDR (\u00b1 SE)",
    xlab_b = NULL,
    ylab_b = NULL,
    xlab_c = "Year",
    width = 12.5, height = 4.0) {
  .ckm_pub_ensure_literature()
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("need ggplot2")
  if (!requireNamespace("gridExtra", quietly = TRUE)) stop("need gridExtra")

  if (!is.null(elbow_csv) && file.exists(elbow_csv)) {
    el_df <- utils::read.csv(elbow_csv)
    if ("chosen_k" %in% names(el_df) && is.finite(as.numeric(el_df$chosen_k[1L]))) {
      chosen_k <- as.integer(el_df$chosen_k[1L])
    }
    if (!"chosen_k" %in% names(el_df)) el_df$chosen_k <- chosen_k
    # 若 CSV 只到 k<10，补齐 WCSS 曲线到 10（虚线仍用 CSV 的 chosen_k）
    if (max(as.numeric(el_df$k), na.rm = TRUE) < 10) {
      mat <- cbind(as.numeric(data[[t1_col]]), as.numeric(data[[t2_col]]))
      el <- ckm_stroke_kmeans_elbow(mat, k_max = 10L, seed = 2026L, nstart = 25L)
      el_df <- data.frame(k = seq_along(el$wcss), WCSS = el$wcss, chosen_k = chosen_k)
    }
  } else {
    mat <- cbind(as.numeric(data[[t1_col]]), as.numeric(data[[t2_col]]))
    el <- ckm_stroke_kmeans_elbow(mat, k_max = 10L, seed = 2026L, nstart = 25L)
    el_df <- data.frame(k = seq_along(el$wcss), WCSS = el$wcss, chosen_k = chosen_k)
  }

  pA <- ggplot2::ggplot(el_df, ggplot2::aes(k, WCSS)) +
    ggplot2::geom_line(color = "#2C7FB8", linewidth = 0.9) +
    ggplot2::geom_point(color = "#2C7FB8", size = 2.2) +
    ggplot2::geom_vline(xintercept = chosen_k, linetype = 2, color = "grey50", linewidth = 0.7) +
    ggplot2::scale_x_continuous(breaks = seq(1, max(el_df$k), 1)) +
    ggplot2::labs(title = "A", x = "Number of clusters (k)", y = "Total Within Sum of Squares") +
    ckm_stroke_theme_paper(10)

  sc <- data.frame(
    x = as.numeric(data[[t1_col]]),
    y = as.numeric(data[[t2_col]]),
    Cluster = factor(data[[class_col]], levels = cmap$order_paper)
  )
  sc <- sc[stats::complete.cases(sc), ]
  if (is.null(xlab_b)) xlab_b <- expression(eGDR[2012])
  if (is.null(ylab_b)) ylab_b <- expression(eGDR[2015])
  # 原文 Fig2B：各类凸包多边形（非正态椭圆）
  hulls <- do.call(rbind, lapply(split(sc, sc$Cluster), function(d) {
    if (nrow(d) < 3L) return(NULL)
    idx <- grDevices::chull(d$x, d$y)
    out <- d[c(idx, idx[1L]), , drop = FALSE]
    out
  }))
  pB <- ggplot2::ggplot(sc, ggplot2::aes(x, y, color = Cluster, fill = Cluster, shape = Cluster)) +
    ggplot2::geom_polygon(
      data = hulls,
      ggplot2::aes(x = x, y = y, group = Cluster, fill = Cluster, color = Cluster),
      alpha = 0.18, linewidth = 0.55, show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 1.05, alpha = 0.65, stroke = 0.2) +
    ggplot2::scale_color_manual(values = cmap$colors) +
    ggplot2::scale_fill_manual(values = cmap$colors) +
    ggplot2::scale_shape_manual(values = cmap$shapes) +
    ggplot2::coord_cartesian(
      xlim = range(sc$x, na.rm = TRUE),
      ylim = range(sc$y, na.rm = TRUE),
      expand = TRUE
    ) +
    ggplot2::labs(title = "B", x = xlab_b, y = ylab_b,
                  color = "Cluster", shape = "Cluster") +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(legend.position = "right") +
    ggplot2::guides(fill = "none")

  agg <- do.call(rbind, lapply(cmap$order_paper, function(cl) {
    d <- data[as.character(data[[class_col]]) == cl, ]
    n1 <- sum(is.finite(as.numeric(d[[t1_col]])))
    n2 <- sum(is.finite(as.numeric(d[[t2_col]])))
    data.frame(
      Cluster = cl,
      Year = year_labs,
      Mean = c(mean(d[[t1_col]], na.rm = TRUE), mean(d[[t2_col]], na.rm = TRUE)),
      SE = c(stats::sd(d[[t1_col]], na.rm = TRUE) / sqrt(max(n1, 1)),
             stats::sd(d[[t2_col]], na.rm = TRUE) / sqrt(max(n2, 1)))
    )
  }))
  agg$Cluster <- factor(agg$Cluster, levels = cmap$order_paper)
  pC <- ggplot2::ggplot(agg, ggplot2::aes(Year, Mean, color = Cluster, shape = Cluster, group = Cluster)) +
    ggplot2::geom_line(linewidth = 1.05) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = Mean - SE, ymax = Mean + SE),
      width = 0.22, linewidth = 0.85, show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 2.6) +
    ggplot2::scale_color_manual(values = cmap$colors) +
    ggplot2::scale_shape_manual(values = cmap$shapes) +
    ggplot2::scale_x_continuous(breaks = year_labs) +
    ggplot2::coord_cartesian(
      ylim = range(c(agg$Mean - agg$SE, agg$Mean + agg$SE), na.rm = TRUE) + c(-0.35, 0.35)
    ) +
    ggplot2::labs(title = "C", x = xlab_c, y = ylab_c, color = "Cluster", shape = "Cluster") +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(legend.position = "right")

  if (!is.null(outfile) && nzchar(outfile)) {
    dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
    grDevices::pdf(outfile, width = width, height = height, useDingbats = FALSE)
    gridExtra::grid.arrange(pA, pB, pC, ncol = 3, widths = c(1, 1.15, 1.1))
    grDevices::dev.off()
  }
  invisible(list(A = pA, B = pB, C = pC, elbow = el_df, traj = agg))
}

# -----------------------------------------------------------------------------
# Fig1 flowchart (attrition counts overridable)
# -----------------------------------------------------------------------------
ckm_stroke_fig1_flowchart <- function(
    outfile,
    attrition = list(n0 = 17708L, e1 = 8358L, n1 = 9350L,
                     e2 = 1804L, n2 = 7546L, e3 = 709L, n3 = 6837L,
                     e4 = 1854L, n_final = 4983L),
    class_n = NULL,
    cohort_lab = "CHARLS Wave 1 participants",
    excl1_lab = "Excluded: incomplete CKM-stage\n(0\u20134) data (n=%s)",
    eligible_lab = "Eligible with CKM stages 0\u20134\n(n=%s)",
    excl2_lab = NULL,
    note = "Note: denominators follow project construction (final N=4,983), not verbatim paper N=5,248.",
    width = 8.8, height = 7.6) {
  pdf(outfile, width = width, height = height, useDingbats = FALSE)
  on.exit(try(dev.off(), silent = TRUE), add = TRUE)
  par(mar = c(0.35, 0.35, 0.35, 0.35), xpd = NA, family = "sans")
  plot(0, 0, type = "n", xlim = c(0, 10), ylim = c(1.85, 10.15),
       axes = FALSE, xlab = "", ylab = "")
  .box <- function(x, y, w, h, txt, cex = 0.85, font = 1) {
    rect(x - w / 2, y - h / 2, x + w / 2, y + h / 2,
         border = "black", lwd = 1.25, col = "white")
    text(x, y, txt, cex = cex, font = font)
  }
  .fmtn <- function(x) format(as.integer(x), big.mark = " ")
  .sprintf_excl <- function(tpl, a) {
    slots <- gregexpr("%s", tpl, fixed = TRUE)[[1L]]
    n_slot <- if (length(slots) == 1L && identical(as.integer(slots), -1L)) 0L else length(slots)
    if (n_slot < 1L) return(tpl)
    vals <- list(a$e2, a$e3, a$e4, a$e5, a$e6)
    vals <- vals[seq_len(min(n_slot, length(vals)))]
    do.call(sprintf, c(list(tpl), lapply(vals, .fmtn)))
  }
  a <- attrition
  if (is.null(excl2_lab)) {
    excl2_lab <- paste0(
      "Excluded sequentially:\n",
      "Stroke or missing stroke status\nWaves 1\u20133 (n=%s)\n",
      "Missing stroke data at Wave 4\n(n=%s)\n",
      "Incomplete eGDR data in Wave 1\nor Wave 3 (n=%s)"
    )
  }
  xc <- 3.15
  xe <- 7.55
  bw <- 4.5
  bh <- 0.72
  bw_ex1 <- 3.7
  bh_ex1 <- 0.85
  bw_ex2 <- 3.85
  n_ex2_lines <- length(strsplit(excl2_lab, "\n", fixed = TRUE)[[1L]])
  bh_ex2 <- if (n_ex2_lines >= 5L) 1.95 else 1.65

  y0 <- 9.55
  y1 <- 8.05
  y2 <- 5.85
  y_cls <- 3.3
  bh_cls <- 0.7

  .box(xc, y0, bw, bh,
       sprintf("%s\n(n=%s)", cohort_lab, .fmtn(a$n0)), cex = 0.92)
  y_j1 <- (y0 - bh / 2 + y1 + bh / 2) / 2
  arrows(xc, y0 - bh / 2, xc, y1 + bh / 2, length = 0.1, lwd = 1.3)
  arrows(xc, y_j1, xe - bw_ex1 / 2, y_j1, length = 0.1, lwd = 1.3)
  .box(xe, y_j1, bw_ex1, bh_ex1, sprintf(excl1_lab, .fmtn(a$e1)), cex = 0.72)

  .box(xc, y1, bw, bh, sprintf(eligible_lab, .fmtn(a$n1)), cex = 0.9)
  y_j2 <- (y1 - bh / 2 + y2 + bh / 2) / 2
  arrows(xc, y1 - bh / 2, xc, y2 + bh / 2, length = 0.1, lwd = 1.3)
  arrows(xc, y_j2, xe - bw_ex2 / 2, y_j2, length = 0.1, lwd = 1.3)
  .box(xe, y_j2, bw_ex2, bh_ex2, .sprintf_excl(excl2_lab, a), cex = 0.64)

  .box(xc, y2, bw, bh,
       sprintf("%s subjects in final analysis", .fmtn(a$n_final)), cex = 0.95)

  y_bar <- y_cls + bh_cls / 2 + 0.42
  arrows(xc, y2 - bh / 2, xc, y_bar, length = 0.08, lwd = 1.3)
  xs <- c(1.2, 3.4, 5.6, 7.8)
  segments(xs[1], y_bar, xs[4], y_bar, lwd = 1.3)
  for (i in seq_along(xs)) {
    lab <- paste0("Class ", i)
    nn <- if (!is.null(class_n) && lab %in% names(class_n)) as.integer(class_n[[lab]]) else 0L
    arrows(xs[i], y_bar, xs[i], y_cls + bh_cls / 2, length = 0.08, lwd = 1.3)
    .box(xs[i], y_cls, 1.95, bh_cls,
         sprintf("%s\n(n=%s)", lab, .fmtn(nn)), cex = 0.82)
  }
  if (nzchar(as.character(note %||% "")[1L])) {
    text(5, 2.1, note, cex = 0.62, col = "grey30")
  }
  invisible(outfile)
}

# -----------------------------------------------------------------------------
# RCS panel (Fig3 / S1)
# -----------------------------------------------------------------------------
ckm_stroke_rcs_one_panel <- function(
    d, xcol, y_binary = TRUE, title_letter = "A",
    ylab = "Odds Ratio of Stroke", covars, outcome = "Stroke",
    xlab = "Cumulative eGDR",
    xlim_probs = c(0.05, 0.95),
    or_cap = c(0.3, 3),
    nknots = 4L) {
  if (!requireNamespace("rms", quietly = TRUE)) stop("need rms")
  nknots <- as.integer(nknots)[1L]
  if (!is.finite(nknots) || nknots < 3L) nknots <- 3L
  keep <- unique(c(if (y_binary) outcome else c("futime", "status"), xcol, covars))
  dd <- d[, intersect(keep, names(d)), drop = FALSE]
  for (cv in covars) if (is.character(dd[[cv]])) dd[[cv]] <- factor(dd[[cv]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 100) {
    return(ggplot2::ggplot() + ggplot2::theme_void() + ggplot2::ggtitle(title_letter))
  }
  xref <- as.numeric(stats::median(dd[[xcol]], na.rm = TRUE))
  x_lim <- as.numeric(stats::quantile(dd[[xcol]], probs = xlim_probs, na.rm = TRUE, names = FALSE))
  if (!all(is.finite(x_lim)) || x_lim[2] <= x_lim[1]) {
    x_lim <- range(dd[[xcol]], na.rm = TRUE)
  }
  ddn <- paste0("dd_", gsub("[^A-Za-z0-9]", "", title_letter), sample.int(1e6, 1))
  assign(ddn, rms::datadist(dd), envir = .GlobalEnv)
  options(datadist = ddn)
  dist <- get(ddn, envir = .GlobalEnv)
  dist$limits[[xcol]][2] <- xref
  assign(ddn, dist, envir = .GlobalEnv)
  if (!"package:rms" %in% search()) suppressPackageStartupMessages(library(rms))
  if (!"package:survival" %in% search()) suppressPackageStartupMessages(library(survival))

  .rcs_rhs <- paste0("rcs(", xcol, ", ", nknots, ")")
  if (length(covars)) .rcs_rhs <- paste(.rcs_rhs, paste(covars, collapse = "+"), sep = " + ")

  if (y_binary) {
    fml <- stats::as.formula(paste0(outcome, " ~ ", .rcs_rhs))
    fit <- rms::lrm(fml, data = dd, x = TRUE, y = TRUE)
    a <- anova(fit)
    rn <- rownames(a)
    p_overall <- tryCatch(as.numeric(a[grep(xcol, rn)[1], "P"]), error = function(e) NA_real_)
    p_nonlin <- tryCatch(as.numeric(a[grep("Nonlinear|nonlinear", rn, ignore.case = TRUE)[1], "P"]),
                         error = function(e) NA_real_)
    pp <- as.data.frame(rms::Predict(fit, name = xcol, ref.zero = TRUE, fun = exp))
  } else {
    fml <- stats::as.formula(paste0("Surv(futime, status) ~ ", .rcs_rhs))
    fit <- rms::cph(fml, data = dd, x = TRUE, y = TRUE, surv = TRUE)
    a <- anova(fit)
    rn <- rownames(a)
    p_overall <- tryCatch(as.numeric(a[grep(xcol, rn)[1], "P"]), error = function(e) NA_real_)
    p_nonlin <- tryCatch(as.numeric(a[grep("Nonlinear|nonlinear", rn, ignore.case = TRUE)[1], "P"]),
                         error = function(e) NA_real_)
    pp <- as.data.frame(rms::Predict(fit, name = xcol, ref.zero = TRUE, fun = exp))
  }
  .fmtp <- function(p) {
    if (is.na(p)) return("NA")
    if (p < 0.001) "<0.001" else sprintf("%.3f", p)
  }
  xname <- names(pp)[1]
  # 仅截横轴到中央分位；纵轴用 coord 裁切，禁止把点估计压成地板线
  pp <- pp[is.finite(pp[[xname]]) & pp[[xname]] >= x_lim[1] & pp[[xname]] <= x_lim[2], , drop = FALSE]
  if (!nrow(pp)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() + ggplot2::ggtitle(title_letter))
  }
  hist_df <- data.frame(x = dd[[xcol]])
  hist_df <- hist_df[hist_df$x >= x_lim[1] & hist_df$x <= x_lim[2], , drop = FALSE]
  br <- pretty(range(hist_df$x, na.rm = TRUE), n = 28)
  h <- hist(hist_df$x, breaks = br, plot = FALSE)
  h_df <- data.frame(xmin = head(h$breaks, -1), xmax = tail(h$breaks, -1), count = h$counts)
  or_lo <- as.numeric(or_cap[1]); or_hi <- as.numeric(or_cap[2])
  # 直方图高度映射到 log 轴可视高度
  h_df$ymin <- or_lo
  h_df$ymax <- or_lo * (or_hi / or_lo)^(0.20 * h_df$count / max(h_df$count, 1))
  annot_lab <- sprintf("P for overall = %s\nP for non-linearity = %s", .fmtp(p_overall), .fmtp(p_nonlin))
  # P / Ref 放 subtitle+caption（绘图区外），避免与 vline/曲线 text-stroke FAIL
  ggplot2::ggplot() +
    ggplot2::geom_rect(data = h_df, ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                       fill = "#9ECAE1", color = NA, alpha = 0.55) +
    ggplot2::geom_ribbon(data = pp, ggplot2::aes(x = .data[[xname]], ymin = lower, ymax = upper),
                         fill = "#FCBBA1", alpha = 0.45) +
    ggplot2::geom_line(data = pp, ggplot2::aes(x = .data[[xname]], y = yhat),
                       color = "#CB181D", linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = 2, color = "#41B6C4", linewidth = 0.6) +
    ggplot2::geom_vline(xintercept = xref, linetype = 2, color = "#41B6C4", linewidth = 0.6) +
    ggplot2::scale_y_continuous(
      trans = "log10",
      breaks = c(0.3, 0.5, 1, 2, 3),
      labels = c("0.3", "0.5", "1.0", "2.0", "3.0")
    ) +
    ggplot2::coord_cartesian(xlim = x_lim, ylim = c(or_lo, or_hi), clip = "on") +
    ggplot2::labs(
      title = title_letter,
      subtitle = annot_lab,
      caption = sprintf("Ref. point = %.2f", xref),
      x = xlab, y = ylab
    ) +
    ckm_stroke_theme_paper(10) +
    ggplot2::theme(
      plot.subtitle = ggplot2::element_text(size = 9, face = "bold", hjust = 0),
      plot.caption = ggplot2::element_text(size = 8, face = "bold", colour = "#41B6C4", hjust = 0.5)
    )
}

# -----------------------------------------------------------------------------
# Free-Statistics forest (Fig S2/S3) — continuous per-SD
# -----------------------------------------------------------------------------
ckm_stroke_forest_free_stats <- function(
    data, expo_raw = "cum_eGDR", is_hr = FALSE, outfile,
    title = NULL, outcome = "Stroke",
    expo_lab = "cumulative eGDR",
    model3 = c("Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
               "eGFR", "Dyslipidemia", "Diabetes")) {
  .ckm_pub_ensure_literature()
  if (!requireNamespace("forestploter", quietly = TRUE)) stop("need forestploter")
  stopifnot(expo_raw %in% names(data))
  # 与 Table3 同口径：Age "< 60"/"≥ 60"；Smoke/Drink Never/Ever
  data <- ckm_stroke_prepare_forest_groups(data, age_labels_compact = FALSE, drop_extreme_bmi = TRUE)
  # 仅当尚无可用 futime 时才回填；已并入访视月差时勿覆盖成常数 4
  if (is_hr) {
    has_ft <- "futime" %in% names(data) &&
      any(is.finite(as.numeric(data$futime)) & as.numeric(data$futime) > 0)
    if (!has_ft) data <- ckm_stroke_add_futime(data)
    if (!"status" %in% names(data) && outcome %in% names(data)) {
      data$status <- as.integer(as.numeric(data[[outcome]]) == 1L)
    }
  }

  x <- as.numeric(data[[expo_raw]])
  sd_x <- stats::sd(x, na.rm = TRUE)
  data$cum_eGDR_z <- as.numeric(scale(x))
  expo <- "cum_eGDR_z"
  models3 <- intersect(model3, names(data))

  sub_specs <- list(
    list(var = "Age_Group", label = "Age, years", drop = "Age"),
    list(var = "Gender", label = "Gender", drop = "Gender"),
    list(var = "BMI_Group", label = "BMI, kg/m\u00b2", drop = "BMI"),
    list(var = "Education", label = "Education", drop = "Education"),
    list(var = "Smoke_ne", label = "Smoke", drop = "Smoke"),
    list(var = "Drink_ne", label = "Drink", drop = "Drink"),
    list(var = "CKM_stage_group", label = "CKM stage", drop = character(0)),
    list(var = "Diabetes", label = "Diabetes", drop = "Diabetes"),
    list(var = "Hypertension", label = "Hypertension", drop = "Hypertension"),
    list(var = "Dyslipidemia", label = "Dyslipidemia", drop = "Dyslipidemia")
  )
  sub_specs <- Filter(function(s) s$var %in% names(data), sub_specs)
  effect_lab <- if (is_hr) "HR (95%CI)" else "OR (95%CI)"
  fit1 <- function(d, cov) {
    if (is_hr) ckm_stroke_fit_hr_row(d, expo, cov) else ckm_stroke_fit_or_row(d, expo, outcome, cov)
  }
  .stroke01 <- function(d) as.integer(as.numeric(d[[outcome]]) == 1L)
  .mk <- function(subgroup, total = "", event = "", effect_txt = "", pint = "",
                  est = NA_real_, lo = NA_real_, hi = NA_real_, is_header = FALSE) {
    out <- data.frame(
      Subgroup = as.character(subgroup)[1L],
      Total = as.character(total)[1L],
      `Event (%)` = as.character(event)[1L],
      check.names = FALSE, stringsAsFactors = FALSE
    )
    out[[effect_lab]] <- as.character(effect_txt)[1L]
    out[[" "]] <- paste(rep(" ", 20L), collapse = "")
    out[["P for interaction"]] <- as.character(pint)[1L]
    out$`Point Estimate` <- as.numeric(est)[1L]
    out$Lower <- as.numeric(lo)[1L]
    out$Upper <- as.numeric(hi)[1L]
    out$is_header <- isTRUE(is_header)
    out
  }
  .fmt_event <- function(n_event, n_tot) {
    if (!is.finite(n_tot) || n_tot <= 0) return("")
    sprintf("%d (%.1f)", as.integer(n_event), 100 * n_event / n_tot)
  }

  rows <- list()
  rr <- fit1(data, models3)
  cc_cols <- unique(c(expo, if (is_hr) c("futime", "status") else outcome, models3))
  ok_all <- stats::complete.cases(data[, intersect(cc_cols, names(data)), drop = FALSE])
  n_tot <- sum(ok_all)
  n_evt <- if (is_hr) sum(as.integer(data$status[ok_all]) == 1L) else sum(.stroke01(data[ok_all, , drop = FALSE]))
  if (!is.null(rr) && nrow(rr)) {
    hit <- rr[1, , drop = FALSE]
    est0 <- if (is_hr) hit$HR[1] else hit$OR[1]
    if (is.finite(est0) && is.finite(hit$CI_low[1]) && hit$CI_low[1] > 0 &&
        is.finite(hit$CI_high[1]) && hit$CI_high[1] > 0 && est0 > 0) {
      rows[[length(rows) + 1L]] <- .mk(
        "Overall", n_tot, .fmt_event(n_evt, n_tot),
        ckm_stroke_fmt_or_tilde(est0, hit$CI_low[1], hit$CI_high[1]), "",
        est0, hit$CI_low[1], hit$CI_high[1], FALSE
      )
    }
  }
  for (sp in sub_specs) {
    sv <- sp$var
    cov_i <- setdiff(models3, sp$drop)
    levs <- if (is.factor(data[[sv]])) levels(data[[sv]]) else unique(stats::na.omit(as.character(data[[sv]])))
    levs <- as.character(levs); levs <- levs[nzchar(levs)]
    pint <- ckm_stroke_lrt_pint(data, expo, sv, cov_i, is_hr = is_hr, outcome = outcome)
    pint_txt <- ckm_stroke_fmt_p(pint)
    rows[[length(rows) + 1L]] <- .mk(sp$label, "", "", "", pint_txt, NA_real_, NA_real_, NA_real_, TRUE)
    for (lev in levs) {
      dsub <- data[as.character(data[[sv]]) == lev & !is.na(data[[sv]]), , drop = FALSE]
      if (nrow(dsub) < 30L) next
      need_cols <- unique(c(expo, if (is_hr) c("futime", "status") else outcome, cov_i))
      ok_cc <- stats::complete.cases(dsub[, intersect(need_cols, names(dsub)), drop = FALSE])
      dfit <- dsub[ok_cc, , drop = FALSE]
      n_i <- nrow(dfit)
      if (n_i < 30L) next
      n_e <- if (is_hr) sum(as.integer(dfit$status) == 1L) else sum(.stroke01(dfit))
      if (n_e < 1L) next
      rr <- fit1(dfit, cov_i)
      if (is.null(rr) || !nrow(rr)) next
      hit <- rr[1, , drop = FALSE]
      est0 <- if (is_hr) hit$HR[1] else hit$OR[1]
      lo0 <- hit$CI_low[1]; hi0 <- hit$CI_high[1]
      if (!(is.finite(est0) && est0 > 0 && is.finite(lo0) && lo0 > 0 && is.finite(hi0) && hi0 > 0)) next
      rows[[length(rows) + 1L]] <- .mk(
        paste0("  ", lev), n_i, .fmt_event(n_e, n_i),
        ckm_stroke_fmt_or_tilde(est0, lo0, hi0), "",
        est0, lo0, hi0, FALSE
      )
    }
  }
  plot_df <- do.call(rbind, rows)
  rownames(plot_df) <- NULL
  if (!nrow(plot_df)) stop("empty forest rows")

  disp_cols <- c("Subgroup", "Total", "Event (%)", effect_lab, " ", "P for interaction")
  disp <- plot_df[, disp_cols, drop = FALSE]
  pint_col <- "P for interaction"
  disp[[pint_col]] <- ifelse(
    nzchar(as.character(disp[[pint_col]])),
    paste0(as.character(disp[[pint_col]]), "   "),
    paste(rep(" ", 12L), collapse = "")
  )
  teal <- "#008B8B"
  tm <- forestploter::forest_theme(
    base_size = 9,
    refline_gp = grid::gpar(lty = 1, col = "grey60", lwd = 1),
    ci_pch = 16, ci_col = teal, ci_fill = teal, ci_alpha = 1,
    ci_lty = 1, ci_lwd = 1.6, ci_Theight = 0,
    xaxis_gp = grid::gpar(fontsize = 7.5, col = "grey20"),
    core = list(fg_params = list(hjust = 0, x = 0.01, fontfamily = ""),
                bg_params = list(fill = "white")),
    colhead = list(fg_params = list(hjust = 0, x = 0.01, fontface = "bold", fontfamily = ""))
  )
  est <- as.numeric(plot_df$`Point Estimate`)
  lo <- as.numeric(plot_df$Lower)
  hi <- as.numeric(plot_df$Upper)
  bad <- !(is.finite(est) & is.finite(lo) & is.finite(hi) & est > 0 & lo > 0 & hi > 0)
  est[bad] <- lo[bad] <- hi[bad] <- NA_real_
  xlim <- c(0.15, 1.8)
  finite_lo <- lo[is.finite(lo) & lo > 0]
  finite_hi <- hi[is.finite(hi) & hi > 0]
  if (length(finite_lo)) xlim[1] <- max(0.08, min(as.numeric(stats::quantile(finite_lo, 0.05)) * 0.9, 0.3))
  if (length(finite_hi)) xlim[2] <- min(4, max(1.3, as.numeric(stats::quantile(finite_hi, 0.95)) * 1.1))
  if (!(is.finite(xlim[1]) && xlim[1] > 0 && is.finite(xlim[2]) && xlim[2] > xlim[1])) xlim <- c(0.2, 2)
  lo_draw <- pmax(lo, xlim[1] * 0.999); hi_draw <- pmin(hi, xlim[2] * 1.001)
  lo_draw[!is.finite(lo)] <- NA_real_; hi_draw[!is.finite(hi)] <- NA_real_
  # 稀疏刻度，避免 log 轴上 1 / 1.5 / 2 挤叠
  ticks_cand <- c(0.25, 0.5, 1, 2, 3, 4)
  ticks <- ticks_cand[ticks_cand >= xlim[1] * 0.98 & ticks_cand <= xlim[2] * 1.02]
  if (!any(abs(ticks - 1) < 1e-8)) ticks <- sort(unique(c(ticks, 1)))
  if (length(ticks) < 2L) ticks <- sort(unique(c(xlim[1], 1, xlim[2])))
  # 若仍偏密（相邻比 <1.6），再抽稀
  if (length(ticks) >= 4L) {
    keep <- rep(TRUE, length(ticks))
    last <- ticks[1]
    for (i in seq_along(ticks)[-1]) {
      if (ticks[i] / last < 1.6 && abs(ticks[i] - 1) > 1e-8) {
        keep[i] <- FALSE
      } else {
        last <- ticks[i]
      }
    }
    ticks <- ticks[keep]
  }

  p <- forestploter::forest(
    disp, est = est, lower = lo_draw, upper = hi_draw, sizes = 0.4,
    ci_column = which(disp_cols == " ")[1L], ref_line = 1,
    xlim = xlim, ticks_at = ticks, x_trans = "log", theme = tm
  )
  p <- forestploter::edit_plot(p, part = "header", gp = grid::gpar(fontface = "bold"))
  hdr <- which(isTRUE(plot_df$is_header) | plot_df$is_header %in% TRUE)
  if (length(hdr)) p <- forestploter::edit_plot(p, row = hdr, gp = grid::gpar(fontface = "bold"))
  pint_idx <- which(disp_cols == pint_col)[1L]
  if (!is.null(p$widths) && is.finite(pint_idx)) {
    g_pint <- as.integer(pint_idx) + 1L
    if (g_pint >= 1L && g_pint <= length(p$widths)) {
      cur <- tryCatch(as.numeric(grid::convertWidth(p$widths[[g_pint]], "in", valueOnly = TRUE)),
                      error = function(e) NA_real_)
      if (!is.finite(cur) || cur < 0.55) cur <- 0.7
      p$widths[[g_pint]] <- grid::unit(max(cur, 0.95), "in")
    }
  }
  # 加宽 CI 列，减轻刻度拥挤
  ci_idx <- which(disp_cols == " ")[1L]
  if (!is.null(p$widths) && is.finite(ci_idx)) {
    g_ci <- as.integer(ci_idx) + 1L
    if (g_ci >= 1L && g_ci <= length(p$widths)) {
      cur_ci <- tryCatch(as.numeric(grid::convertWidth(p$widths[[g_ci]], "in", valueOnly = TRUE)),
                         error = function(e) NA_real_)
      if (!is.finite(cur_ci)) cur_ci <- 1.6
      p$widths[[g_ci]] <- grid::unit(max(cur_ci, 2.2), "in")
    }
  }
  if (!is.null(p$layout) && "clip" %in% names(p$layout)) p$layout$clip[] <- "off"

  sd_note <- sprintf(
    "Exposure: per 1-SD increase in %s (SD = %.3f). Continuous OR/HR in tables is per 1-unit. Model 3 covariates (stratification variable dropped). P for interaction: LRT.",
    as.character(expo_lab)[1L], sd_x
  )
  fig_w <- 10.2
  fig_h <- max(5.4, min(7.6, 0.245 * nrow(plot_df) + 1.35))
  grDevices::pdf(outfile, width = fig_w, height = fig_h, useDingbats = FALSE)
  grid::grid.newpage()
  # 上下留白：避免标题压 Subgroup 表头、脚注压横轴刻度
  grid::pushViewport(grid::viewport(x = 0.5, y = 0.50, width = 0.98, height = 0.78))
  grid::grid.draw(p)
  grid::popViewport()
  if (!is.null(title) && nzchar(title)) {
    grid::grid.text(title, x = 0.02, y = 0.975, just = c("left", "top"),
                    gp = grid::gpar(fontsize = 9, fontface = "bold", col = "grey15"))
  }
  grid::grid.text(sd_note, x = 0.02, y = 0.018, just = c("left", "bottom"),
                  gp = grid::gpar(fontsize = 6.5, col = "grey25", fontfamily = ""))
  grDevices::dev.off()
  attr(plot_df, "sd") <- sd_x
  attr(plot_df, "exposure_scale") <- "per_1_SD"
  invisible(plot_df)
}

# -----------------------------------------------------------------------------
# Junk cleanup + kill old Fig2 split panels
# -----------------------------------------------------------------------------
ckm_stroke_clean_summary_junk <- function(tab_dir, fig_dir, sr_dir = dirname(tab_dir)) {
  junk_pat <- c(
    "^_raw_", "^_style_test", "Figure_S.*_forest_rows\\.csv$",
    "^Kmeans_elbow_WCSS\\.csv$", "^Flowchart_attrition",
    "^Covariate_UV_VIF_selection\\.csv$"
  )
  junk_dir <- file.path(sr_dir, "_archive_non_pub_tables")
  dir.create(junk_dir, recursive = TRUE, showWarnings = FALSE)
  moved <- character(0)
  for (f in list.files(tab_dir, full.names = TRUE)) {
    bn <- basename(f)
    if (any(vapply(junk_pat, function(p) grepl(p, bn), logical(1)))) {
      file.rename(f, file.path(junk_dir, bn))
      moved <- c(moved, bn)
    }
  }
  fr <- file.path(fig_dir, "Figure_S3_forest_rows.csv")
  if (file.exists(fr)) {
    file.rename(fr, file.path(junk_dir, basename(fr)))
    moved <- c(moved, basename(fr))
  }
  invisible(moved)
}

ckm_stroke_kill_fig2_splits <- function(fig_dir) {
  stems <- c(
    "Figure 2A. Elbow method WCSS",
    "Figure 2B. Mean eGDR trajectories by class",
    "Figure 2C. eGDR distribution by class",
    "Figure. Table3 Class subgroup forest OR"
  )
  for (sub in c("", "pdf", "png", "tiff", "image_information")) {
    base <- if (nzchar(sub)) file.path(fig_dir, sub) else fig_dir
    if (!dir.exists(base)) next
    for (stem in stems) {
      for (ext in c(".pdf", ".png", ".tiff", ".md")) {
        p <- file.path(base, paste0(stem, ext))
        if (file.exists(p)) unlink(p)
      }
    }
  }
  invisible(TRUE)
}
