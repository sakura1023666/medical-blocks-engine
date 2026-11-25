###############################################################################
#  competing_baseline_quartile — Table 1（Lai 风格：Variables / Number of patients /
#  二分类阳性行 / Total 列；剔除 ID·结局·随访·其它指标）
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
  # 其它复合指标列（当前暴露除外）不得进 Table1
  other_idx <- character(0)
  if (exists(".composite_index_vars", inherits = TRUE)) {
    civ <- .composite_index_vars
    civ_nms <- if (is.character(civ)) {
      unname(civ)
    } else if (is.list(civ)) {
      unique(c(names(civ), unlist(lapply(civ, function(z) {
        if (is.character(z)) z else names(z)
      }), use.names = FALSE)))
    } else {
      character(0)
    }
    other_idx <- setdiff(as.character(civ_nms), index_var)
  }
  # 常见比值/姊妹指标（未必都在 composite 名单）一并剔除
  sibling_idx <- setdiff(
    c("KAR", "GAR", "NAR", "PAR", "LAR", "MAR", "UAR", "AAR",
      "NLR", "PLR", "LMR", "MLR", "SII", "SIRI", "PIV", "AISI",
      "TyG", "AIP", "TG_HDL", "Non_HDL"),
    index_var
  )
  other_idx <- unique(c(other_idx, sibling_idx))
  unique(c(
    as.character((cfg$data %||% list())$id_column %||% character(0)),
    "ID", "subject_id", "SEQN", "stay_id", "stayid", "hadm_id", "icustay_id",
    "row_id", "anchor_age", "anchor_year",
    as.character(bl$time_var %||% character(0)),
    as.character(bl$event_type_col %||% character(0)),
    "hosp_day", "is_hosp_dead", "in-hospital mortality", "fustatus",
    "futime", "DN", "dn", "death", "los", "LOS", "Hospital_LOS", "ICU_LOS",
    "competing_time_28d", "competing_status_28d", "competing_primary_event",
    "Acute_Renal_Failure", "AKI",
    paste0(index_var, c("_quartile", "_trajectory")),
    other_idx,
    as.character((cfg$imputation %||% list())$table_s1_exclude_vars %||% character(0)),
    as.character(bl$table1_exclude_vars %||% character(0)),
    drop_manifest
  ))
}

.competing_baseline_all_vars <- function(data, cfg, bl, index_var, group_var) {
  excl <- .competing_baseline_exclude_vars(cfg, bl, index_var)
  # 名称模糊匹配：stay id / futime 变体
  nm <- names(data)
  excl_fuzzy <- nm[grepl(
    "(?i)^(stay[ _]?id|hadm|icustay|subject|futime|\\bdn\\b|fustatus|row[ _]?id)$",
    nm, perl = TRUE
  )]
  vars <- setdiff(nm, unique(c(excl, excl_fuzzy, group_var)))
  vars <- unique(c(index_var, vars))
  vars <- vars[vars %in% nm]
  keep <- vapply(vars, function(v) {
    x <- data[[v]]
    if (all(is.na(x))) return(FALSE)
    if (is.numeric(x) && length(unique(stats::na.omit(x))) <= 1L) return(FALSE)
    TRUE
  }, logical(1))
  vars[keep]
}

.competing_baseline_display_name <- function(v) {
  if (exists("pipeline_display_label", mode = "function")) {
    lab <- tryCatch(pipeline_display_label(v), error = function(e) NULL)
    if (!is.null(lab) && nzchar(lab)) return(as.character(lab)[1L])
  }
  gsub("_", " ", as.character(v)[1L])
}

.competing_baseline_var_label <- function(v, x = NULL) {
  lab <- .competing_baseline_display_name(v)
  if (exists("is_hematology_platelet_name", mode = "function") &&
      isTRUE(is_hematology_platelet_name(v))) {
    return(paste0(lab, ", K/uL, (median [IQR])"))
  }
  if (is.numeric(x) && length(unique(stats::na.omit(x))) > 5L) {
    return(paste0(lab, ", (median [IQR])"))
  }
  lab
}

# 二分类阳性水平：Female / Yes；多分类返回 NULL
.competing_baseline_positive_level <- function(lvls) {
  lv <- as.character(lvls)
  lv <- lv[!is.na(lv) & nzchar(lv)]
  if (!length(lv)) return(NULL)
  prefer <- c("Yes", "Female", "1", "TRUE", "True", "Positive", "Present")
  hit <- prefer[prefer %in% lv]
  if (length(hit)) return(hit[[1L]])
  if (setequal(tolower(lv), c("female", "male"))) {
    return(lv[tolower(lv) == "female"][1L])
  }
  if (setequal(tolower(lv), c("yes", "no"))) {
    return(lv[tolower(lv) == "yes"][1L])
  }
  if (length(lv) == 2L) return(lv[[2L]])
  NULL
}

.competing_baseline_fmt_n_pct <- function(n, denom) {
  pct <- if (denom > 0) 100 * n / denom else NA_real_
  sprintf("%d (%.1f)", as.integer(n), pct)
}

.competing_baseline_fmt_median_iqr <- function(xx) {
  sprintf(
    "%.1f (%.1f, %.1f)",
    stats::median(xx, na.rm = TRUE),
    stats::quantile(xx, 0.25, na.rm = TRUE),
    stats::quantile(xx, 0.75, na.rm = TRUE)
  )
}

.competing_baseline_traj_t_label <- function(lv, levels_g) {
  lv <- as.character(lv)[1L]
  alias <- c(
    Decreasing = "T1", Stable = "T2", Increasing = "T3",
    Low = "T1", Middle = "T2", High = "T3",
    T1 = "T1", T2 = "T2", T3 = "T3", T4 = "T4"
  )
  if (lv %in% names(alias)) return(unname(alias[[lv]]))
  i <- match(lv, levels_g)
  if (!is.na(i)) return(paste0("T", i))
  lv
}

.competing_baseline_group_headers <- function(data, group_var, index_var = NULL) {
  g <- factor(data[[group_var]])
  levels_g <- levels(g)
  # 轨迹：Lai Table3 = T1 (N = 167) | T2 | T3
  if (grepl("trajectory", group_var, ignore.case = TRUE)) {
    hdr <- vapply(levels_g, function(lv) {
      tlab <- .competing_baseline_traj_t_label(lv, levels_g)
      n <- sum(g == lv, na.rm = TRUE)
      n_lab <- if (exists("pub_format_int", mode = "function")) {
        pub_format_int(n)
      } else {
        format(as.integer(n), big.mark = ",", scientific = FALSE, trim = TRUE)
      }
      sprintf("%s (N = %s)", tlab, n_lab)
    }, character(1))
    return(unname(hdr))
  }
  # 四分位列头带指标范围（Lai：Q1 (7.3–8.4)）
  if (!is.null(index_var) && index_var %in% names(data) &&
      grepl("quartile|Q[1-4]", group_var, ignore.case = TRUE)) {
    hdr <- vapply(levels_g, function(lv) {
      xx <- suppressWarnings(as.numeric(data[[index_var]][g == lv]))
      xx <- xx[is.finite(xx)]
      if (!length(xx)) return(as.character(lv))
      lo <- stats::quantile(xx, 0, na.rm = TRUE)
      hi <- stats::quantile(xx, 1, na.rm = TRUE)
      sprintf("%s (%.1f\u2013%.1f)", as.character(lv), lo, hi)
    }, character(1))
    return(unname(hdr))
  }
  as.character(levels_g)
}

# Lai Table1 末行：主结局 + Overall mortality（不进中间变量池，只挂表尾）
.competing_baseline_outcome_flag <- function(data, bl, kind = c("primary", "death")) {
  kind <- match.arg(kind)
  event_col <- as.character(bl$event_type_col %||% "competing_status_28d")[1L]
  if (identical(kind, "death") && "DN" %in% names(data)) {
    return(as.integer(data$DN) == 1L)
  }
  if (!event_col %in% names(data)) return(NULL)
  code <- if (identical(kind, "primary")) {
    as.integer(bl$primary_cause %||% 1L)[1L]
  } else {
    as.integer(bl$death_cause %||% 2L)[1L]
  }
  as.integer(data[[event_col]]) == code
}

.competing_baseline_append_outcome_rows <- function(tab, data, group_var, levels_g, bl = list()) {
  if (is.null(bl) || !length(bl)) return(tab)
  add_one <- function(flag, lab) {
    if (is.null(flag) || length(flag) != nrow(data)) return(NULL)
    flag <- as.logical(flag)
    flag[is.na(flag)] <- FALSE
    cell_g <- vapply(levels_g, function(lv) {
      ok <- data[[group_var]] == lv
      .competing_baseline_fmt_n_pct(sum(flag[ok]), sum(ok))
    }, character(1))
    cell_tot <- .competing_baseline_fmt_n_pct(sum(flag), length(flag))
    p <- tryCatch(
      stats::chisq.test(table(flag, data[[group_var]]))$p.value,
      error = function(e) NA_real_
    )
    c(
      Variables = lab,
      Total = cell_tot,
      setNames(cell_g, names(tab)[seq(3L, 2L + length(levels_g))]),
      `P value` = if (exists("pub_format_p", mode = "function")) pub_format_p(p) else sprintf("%.3f", p)
    )
  }
  primary_lbl <- as.character(bl$primary_event_label %||% "Primary event")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "Primary event"
  rows_extra <- list(
    add_one(.competing_baseline_outcome_flag(data, bl, "primary"), paste0(primary_lbl, ", n (%)")),
    add_one(.competing_baseline_outcome_flag(data, bl, "death"), "Overall mortality, n (%)")
  )
  rows_extra <- Filter(Negate(is.null), rows_extra)
  if (!length(rows_extra)) return(tab)
  extra <- as.data.frame(do.call(rbind, rows_extra), stringsAsFactors = FALSE)
  names(extra) <- names(tab)
  rbind(tab, extra)
}

.competing_baseline_table <- function(data, group_var, vars, index_var = NULL, bl = list()) {
  data <- data[!is.na(data[[group_var]]), , drop = FALSE]
  if (exists("scale_hematology_dataframe", mode = "function")) {
    data <- scale_hematology_dataframe(data, verbose = FALSE)
  }
  # 轨迹水平：Decreasing → Stable → Increasing
  if (grepl("trajectory", group_var, ignore.case = TRUE)) {
    pref <- c("Decreasing", "Stable", "Increasing", "Low", "Middle", "High")
    cur <- levels(factor(data[[group_var]]))
    ord <- c(intersect(pref, cur), setdiff(cur, pref))
    data[[group_var]] <- factor(as.character(data[[group_var]]), levels = ord)
  } else {
    data[[group_var]] <- factor(data[[group_var]])
  }
  levels_g <- levels(data[[group_var]])
  headers_g <- .competing_baseline_group_headers(data, group_var, index_var)
  n_total <- nrow(data)
  n_by <- vapply(levels_g, function(lv) sum(data[[group_var]] == lv), integer(1))

  rows <- list()
  for (v in vars) {
    if (!v %in% names(data)) next
    x <- data[[v]]
    is_num <- is.numeric(x) && length(unique(stats::na.omit(x))) > 5L
    if (is_num) {
      cell_g <- vapply(levels_g, function(lv) {
        .competing_baseline_fmt_median_iqr(x[data[[group_var]] == lv])
      }, character(1))
      cell_tot <- .competing_baseline_fmt_median_iqr(x)
      p <- tryCatch(
        stats::kruskal.test(x ~ factor(data[[group_var]]))$p.value,
        error = function(e) NA_real_
      )
      rows[[length(rows) + 1L]] <- c(
        variable = .competing_baseline_var_label(v, x),
        Total = cell_tot,
        cell_g,
        p = if (exists("pub_format_p", mode = "function")) pub_format_p(p) else sprintf("%.3f", p)
      )
    } else {
      xf <- factor(x)
      lvls <- levels(xf)
      pos <- .competing_baseline_positive_level(lvls)
      if (!is.null(pos) && length(lvls) == 2L) {
        # 二分类：仅阳性行，标签 = 「Female, n (%)」/「Hypertension, n (%)」
        base <- .competing_baseline_display_name(v)
        if (tolower(pos) %in% c("yes", "1", "true", "positive", "present")) {
          row_lab <- paste0(base, ", n (%)")
        } else {
          # Female 等：用水平名本身
          row_lab <- paste0(pos, ", n (%)")
        }
        cell_g <- vapply(levels_g, function(lv) {
          xx <- xf[data[[group_var]] == lv]
          .competing_baseline_fmt_n_pct(sum(xx == pos, na.rm = TRUE), length(xx))
        }, character(1))
        cell_tot <- .competing_baseline_fmt_n_pct(sum(xf == pos, na.rm = TRUE), length(xf))
        p <- tryCatch(
          stats::chisq.test(table(xf == pos, data[[group_var]]))$p.value,
          error = function(e) NA_real_
        )
        rows[[length(rows) + 1L]] <- c(
          variable = row_lab,
          Total = cell_tot,
          cell_g,
          p = if (exists("pub_format_p", mode = "function")) pub_format_p(p) else sprintf("%.3f", p)
        )
      } else {
        # 多分类：标题行 + 缩进各水平（Lai / SCI 常见）
        rows[[length(rows) + 1L]] <- c(
          variable = paste0(.competing_baseline_display_name(v), ", n (%)"),
          Total = "",
          setNames(rep("", length(levels_g)), levels_g),
          p = ""
        )
        for (lv2 in lvls) {
          cell_g <- vapply(levels_g, function(lv) {
            xx <- xf[data[[group_var]] == lv]
            .competing_baseline_fmt_n_pct(sum(xx == lv2, na.rm = TRUE), length(xx))
          }, character(1))
          cell_tot <- .competing_baseline_fmt_n_pct(sum(xf == lv2, na.rm = TRUE), length(xf))
          p <- tryCatch(
            stats::chisq.test(table(xf == lv2, data[[group_var]]))$p.value,
            error = function(e) NA_real_
          )
          rows[[length(rows) + 1L]] <- c(
            variable = paste0("  ", lv2),
            Total = cell_tot,
            cell_g,
            p = if (exists("pub_format_p", mode = "function")) pub_format_p(p) else sprintf("%.3f", p)
          )
        }
      }
    }
  }

  n_row <- c(
    variable = "Number of patients",
    Total = as.character(n_total),
    setNames(as.character(n_by), levels_g),
    p = ""
  )
  tab <- as.data.frame(rbind(n_row, do.call(rbind, rows)), stringsAsFactors = FALSE)
  names(tab) <- c("Variables", "Total", headers_g, "P value")
  rownames(tab) <- NULL
  # 原文末行：主结局（如 CRRT/WHF）+ Overall mortality
  .competing_baseline_append_outcome_rows(tab, data, group_var, levels_g, bl = bl)
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
  tab <- .competing_baseline_table(data, group_var, vars, index_var = index_var, bl = bl)
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

register_block("competing_baseline_quartile", block_competing_baseline_quartile, "基线特征表（四分位，Lai SCI）")
