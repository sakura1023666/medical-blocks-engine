###############################################################################
# table1_by_class_ckm — 文献口径 Table 1（按 eGDR_Class）
# 发表最终版式走 ckm_stroke_build_table1_by_class（R/cum_egdr_kmeans_pub.R）；
# 本 block 在 unit Tables 落 CSV 工作底稿 + 若可则写 paper-layout xlsx。
###############################################################################

block_table1_by_class_ckm <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  pub_helper <- file.path(root, "R/cum_egdr_kmeans_pub.R")
  if (file.exists(pub_helper)) source(pub_helper, local = FALSE)

  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !"eGDR_Class" %in% names(data)) {
    cli::cli_alert_warning("table1_by_class: 缺 eGDR_Class")
    return(ctx)
  }

  tab_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  # Paper-layout helper（优先）
  if (exists("ckm_stroke_build_table1_by_class", mode = "function")) {
    data_h <- ckm_stroke_harmonize_columns(data)
    if ("Gender" %in% names(data_h)) {
      data_h$Gender <- factor(as.character(data_h$Gender), levels = c("Female", "Male"))
    }
    if ("Marital" %in% names(data_h)) {
      mv <- as.character(data_h$Marital)
      mv[mv %in% c("Other", "Unmarried", "Single")] <- "Single"
      data_h$Marital <- factor(mv, levels = c("Single", "Married"))
    }
    cmap <- ckm_stroke_class_map_paper()
    data_h <- ckm_stroke_attach_class_paper(data_h, "eGDR_Class", cmap)
    t1b <- ckm_stroke_build_table1_by_class(data_h, cmap = cmap)
    utils::write.csv(t1b$df, file.path(tab_dir, "Table 1. Baseline by eGDR Class.csv"),
                     row.names = FALSE)
    if (exists("export_sci_table", mode = "function")) {
      tryCatch(
        export_sci_table(
          t1b$df,
          file.path(tab_dir, "Table 1. Baseline characteristics by eGDR change patterns.xlsx"),
          title = "Table 1. Baseline characteristics according to eGDR change patterns",
          table_footnotes = c(
            "Values are mean (SD) or n (%). Unit-level draft; final summary via rebuild_publication.R."
          ),
          excel_level_row_idx = t1b$excel_level_row_idx,
          excel_use_prepared = FALSE,
          latex_include_colnames = TRUE
        ),
        error = function(e) cli::cli_alert_warning("Table1 xlsx: {e$message}")
      )
    }
    ctx$results$table1_by_class_ckm <- t1b$df
    cli::cli_alert_success(
      "Table 1 by Class (paper helper): {nrow(t1b$df)} 行, N={t1b$n_all}"
    )
    return(ctx)
  }

  # Fallback：旧扁平行（无 pub helper 时）
  cont_vars <- intersect(
    c("Age", "BMI", "Waist_circumference", "SBP", "DBP", "Glucose", "HbA1c",
      "Triglycerides", "Total_Cholesterol", "HDL", "LDL", "eGFR",
      "eGDR_t1", "eGDR_t2", "cum_eGDR"),
    names(data)
  )
  cat_vars <- intersect(
    c("Gender", "Marital", "Education", "Smoke", "Drink", "Hypertension",
      "Diabetes", "Dyslipidemia", "CKM_stage"),
    names(data)
  )
  cls <- factor(data$eGDR_Class)
  levels_cls <- levels(droplevels(cls))
  rows <- list()
  n_all <- length(cls)
  n_by <- as.integer(table(cls))
  rows[[length(rows) + 1L]] <- data.frame(
    Variable = "N", Overall = as.character(n_all),
    setNames(as.list(as.character(n_by)), levels_cls),
    P = "", stringsAsFactors = FALSE, check.names = FALSE
  )
  .fmt2 <- function(x) sprintf("%.2f", x)
  for (v in cont_vars) {
    x <- as.numeric(data[[v]])
    overall <- sprintf("%s \u00b1 %s", .fmt2(mean(x, na.rm = TRUE)), .fmt2(stats::sd(x, na.rm = TRUE)))
    by <- vapply(levels_cls, function(lv) {
      xx <- x[as.character(cls) == lv]
      sprintf("%s \u00b1 %s", .fmt2(mean(xx, na.rm = TRUE)), .fmt2(stats::sd(xx, na.rm = TRUE)))
    }, character(1))
    p <- tryCatch({
      pv <- stats::kruskal.test(x ~ cls)$p.value
      if (is.na(pv)) "" else if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
    }, error = function(e) "")
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = v, Overall = overall,
      setNames(as.list(by), levels_cls),
      P = p, stringsAsFactors = FALSE, check.names = FALSE
    )
  }
  for (v in cat_vars) {
    x <- as.factor(data[[v]])
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = v, Overall = "",
      setNames(as.list(rep("", length(levels_cls))), levels_cls),
      P = tryCatch({
        tb <- table(x, cls)
        pv <- suppressWarnings(stats::chisq.test(tb)$p.value)
        if (is.na(pv)) "" else if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
      }, error = function(e) ""),
      stringsAsFactors = FALSE, check.names = FALSE
    )
    for (lvx in levels(x)) {
      n_o <- sum(as.character(x) == lvx, na.rm = TRUE)
      pct_o <- 100 * n_o / sum(!is.na(x))
      by <- vapply(levels_cls, function(lv) {
        keep <- as.character(cls) == lv
        n <- sum(as.character(x[keep]) == lvx, na.rm = TRUE)
        den <- sum(!is.na(x[keep]))
        sprintf("%d (%.2f)", n, if (den > 0) 100 * n / den else NA_real_)
      }, character(1))
      rows[[length(rows) + 1L]] <- data.frame(
        Variable = paste0("  ", lvx),
        Overall = sprintf("%d (%.2f)", n_o, pct_o),
        setNames(as.list(by), levels_cls),
        P = "", stringsAsFactors = FALSE, check.names = FALSE
      )
    }
  }
  tab <- do.call(rbind, rows)
  rownames(tab) <- NULL
  utils::write.csv(tab, file.path(tab_dir, "Table 1. Baseline by eGDR Class.csv"),
                   row.names = FALSE)
  ctx$results$table1_by_class_ckm <- tab
  cli::cli_alert_success("Table 1 by Class (fallback): {nrow(tab)} 行")
  ctx
}

register_block("table1_by_class_ckm", block_table1_by_class_ckm, "按Class基线表1")
