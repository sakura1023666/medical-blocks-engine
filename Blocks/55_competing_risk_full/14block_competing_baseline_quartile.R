###############################################################################
#  competing_baseline_quartile — Table 1（全变量，对齐 Table S1 变量集 + SCI）
###############################################################################

.competing_baseline_exclude_vars <- function(cfg, bl, index_var) {
  drop_manifest <- character(0)
  if (length(cfg$analysis_exclusion %||% list())) {
    if (!exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
      root <- cfg$project$root %||% getwd()
      src <- file.path(root, "Blocks/03_imputation/03block_analysis_exclusion.R")
      if (file.exists(src)) source(src, local = FALSE)
    }
    if (exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
      man <- tryCatch(
        pipeline_analysis_exclusion_manifest(cfg),
        error = function(e) NULL
      )
      drop_manifest <- as.character(man$drop_vars %||% character(0))
    }
    drop_manifest <- unique(c(
      drop_manifest,
      as.character((cfg$analysis_exclusion %||% list())$resolved_drop_vars %||% character(0)),
      as.character((cfg$analysis_exclusion %||% list())$disease_vars %||% character(0))
    ))
  }
  unique(c(
    as.character((cfg$data %||% list())$id_column %||% character(0)),
    "ID", "subject_id", "SEQN",
    as.character(bl$time_var %||% character(0)),
    as.character(bl$event_type_col %||% character(0)),
    "hosp_day", "is_hosp_dead", "in-hospital mortality",
    "competing_time_28d", "competing_status_28d", "competing_primary_event",
    paste0(index_var, c("_quartile", "_trajectory")),
    as.character((cfg$imputation %||% list())$table_s1_exclude_vars %||% character(0)),
    drop_manifest
  ))
}

.competing_baseline_all_vars <- function(data, cfg, bl, index_var, group_var) {
  excl <- .competing_baseline_exclude_vars(cfg, bl, index_var)
  vars <- setdiff(names(data), c(excl, group_var))
  # 优先把暴露指标放前面
  vars <- unique(c(index_var, vars))
  vars <- vars[vars %in% names(data)]
  # 去掉全 NA / 常量
  keep <- vapply(vars, function(v) {
    x <- data[[v]]
    if (all(is.na(x))) return(FALSE)
    if (is.numeric(x) && length(unique(stats::na.omit(x))) <= 1L) return(FALSE)
    TRUE
  }, logical(1))
  vars[keep]
}

.competing_baseline_var_label <- function(v, x = NULL) {
  lab <- gsub("_", " ", as.character(v)[1L])
  # 血小板统一展示为 K/uL（与 hematology_units / Table S1 一致）
  if (exists("is_hematology_platelet_name", mode = "function") &&
      isTRUE(is_hematology_platelet_name(v))) {
    return(paste0(lab, ", K/uL, median (IQR)"))
  }
  if (is.numeric(x) && length(unique(stats::na.omit(x))) > 5L) {
    return(paste0(lab, ", median (IQR)"))
  }
  lab
}

.competing_baseline_table <- function(data, group_var, vars) {
  data <- data[!is.na(data[[group_var]]), , drop = FALSE]
  # 基线表导出前统一血细胞单位，避免 Table1≈200 而 Table3≈0.2
  if (exists("scale_hematology_dataframe", mode = "function")) {
    data <- scale_hematology_dataframe(data, verbose = FALSE)
  }
  levels_g <- levels(factor(data[[group_var]]))
  rows <- list()
  for (v in vars) {
    if (!v %in% names(data)) next
    x <- data[[v]]
    is_num <- is.numeric(x) && length(unique(stats::na.omit(x))) > 5L
    if (is_num) {
      cell <- vapply(levels_g, function(lv) {
        xx <- x[data[[group_var]] == lv]
        sprintf("%.2f (%.2f, %.2f)", stats::median(xx, na.rm = TRUE),
                stats::quantile(xx, 0.25, na.rm = TRUE), stats::quantile(xx, 0.75, na.rm = TRUE))
      }, character(1))
      p <- tryCatch(stats::kruskal.test(x ~ factor(data[[group_var]]))$p.value, error = function(e) NA_real_)
      rows[[length(rows) + 1L]] <- c(
        variable = .competing_baseline_var_label(v, x),
        cell, p = pub_format_p(p)
      )
    } else {
      xf <- factor(x)
      for (lv2 in levels(xf)) {
        cell <- vapply(levels_g, function(lv) {
          xx <- xf[data[[group_var]] == lv]
          sprintf("%d (%.1f%%)", sum(xx == lv2, na.rm = TRUE), 100 * mean(xx == lv2, na.rm = TRUE))
        }, character(1))
        p <- tryCatch(stats::chisq.test(table(xf == lv2, data[[group_var]]))$p.value, error = function(e) NA_real_)
        rows[[length(rows) + 1L]] <- c(variable = paste0(v, " = ", lv2, ", n (%)"), cell, p = pub_format_p(p))
      }
    }
  }
  n_row <- c(variable = "N", vapply(levels_g, function(lv) as.character(sum(data[[group_var]] == lv)), character(1)), p = "")
  tab <- as.data.frame(rbind(n_row, do.call(rbind, rows)), stringsAsFactors = FALSE)
  names(tab) <- c("Variable", levels_g, "P value")
  rownames(tab) <- NULL
  tab
}

block_competing_baseline_quartile <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("competing_baseline_quartile: 无数据", call. = FALSE)
  index_var <- bl$index_var %||% bl$tyg_var %||% "TyG"
  group_var <- bl$exposure_var %||% paste0(index_var, "_quartile")
  if (!group_var %in% names(data)) {
    cli::cli_alert_warning("competing_baseline_quartile: 缺少 {group_var}，跳过")
    return(ctx)
  }
  vars <- .competing_baseline_all_vars(data, cfg, bl, index_var, group_var)
  tab <- .competing_baseline_table(data, group_var, vars)
  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, paste0("Table1_Baseline_", index_var, "_Quartile.csv")),
                   row.names = FALSE)
  db <- as.character(cfg$project$database %||% "MIMIC")[1L]
  title <- sprintf("Table 1-%s. Baseline characteristics by %s quartile", db, index_var)
  dest <- file.path(out_dir, paste0(title, ".xlsx"))
  if (exists("export_sci_table", mode = "function")) {
    export_sci_table(tab, dest, title = title)
    if (exists("render_queued_tables", mode = "function")) {
      ctx <- tryCatch(render_queued_tables(ctx), error = function(e) ctx)
    }
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(tab, dest, overwrite = TRUE)
  }
  ctx$results$competing_baseline_quartile <- list(table = tab, vars = vars)
  cli::cli_alert_success("Table1 完成: {length(vars)} 变量 × {group_var}")
  ctx
}

register_block("competing_baseline_quartile", block_competing_baseline_quartile, "基线特征表（四分位，全变量 SCI）")
