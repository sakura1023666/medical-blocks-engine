###############################################################################
# pub_figure_export.R — 汇总 Figures → pdf/png/tiff + image_information
# Spec: docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

.PUB_FIGURE_EXPORT_DIR <- tryCatch({
  of <- sys.frame(1)$ofile
  if (!is.null(of) && nzchar(as.character(of)[1L])) {
    dirname(normalizePath(of, winslash = "/", mustWork = FALSE))
  } else NA_character_
}, error = function(e) NA_character_)

.pub_figure_cfg <- function(config = list()) {
  cfg <- (config$pub_figures %||% list())
  list(
    enable = isTRUE(cfg$formats_dir %||% TRUE),
    dpi = as.integer(cfg$dpi %||% 300L)[1L],
    tiff_compression = "lzw",
    write_image_information = isTRUE(cfg$write_image_information %||% TRUE)
  )
}

pub_figure_ensure_format_dirs <- function(figures_dir) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  stopifnot(nzchar(figures_dir))
  dirs <- c(
    pdf = file.path(figures_dir, "pdf"),
    png = file.path(figures_dir, "png"),
    tiff = file.path(figures_dir, "tiff"),
    image_information = file.path(figures_dir, "image_information")
  )
  for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dirs
}

#' 清空 pdf/png/tiff/image_information，避免旧命名残留
#' 清空汇总图四目录中的旧导出。
#' @param only_stems 非 NULL 时【外科式】只删这些 stem 的文件（本次将被重导出的图）；
#'   其余图的 pdf/png/tiff/md 一律保留。否则部分块单独重跑（如 pub_finalize 只出
#'   Figures 1–6）会把其它块的 Figure 7/8/9 全目录清光且无人补写。
#' @param keep_md TRUE 时完全不动 image_information（补格式调用）。
pub_figure_purge_format_subdirs <- function(figures_dir, keep_md = FALSE, only_stems = NULL) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) return(invisible(0L))
  n <- 0L
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    d <- file.path(figures_dir, sub)
    if (!dir.exists(d)) next
    files <- list.files(d, full.names = TRUE, recursive = FALSE)
    if (!is.null(only_stems) && length(files)) {
      stems <- sub("\\.(pdf|png|tiff|md)$", "", basename(files), ignore.case = TRUE)
      files <- files[stems %in% only_stems]
    }
    if (sub == "image_information" && isTRUE(keep_md)) files <- character(0)
    if (length(files)) {
      unlink(files)
      n <- n + length(files)
    }
  }
  invisible(n)
}

.pub_figure_is_missing_overview <- function(bn) {
  grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)
}

.pub_figure_caption_from_stem <- function(stem) {
  sub("^Figure\\s+[0-9S]+\\.\\s*", "", as.character(stem %||% "")[1L], ignore.case = TRUE)
}

#' 结局/暴露等字段转成正文可读短词（不编造；未知则原样）
.pub_figure_plain_term <- function(x, kind = c("outcome", "exposure", "grouping")) {
  kind <- match.arg(kind)
  x <- as.character(x %||% "")[1L]
  if (!nzchar(x) || identical(x, "未记录")) return("")
  if (identical(kind, "outcome")) {
    key <- tolower(gsub("[^A-Za-z0-9]+", "", x))
    map <- c(
      death = "死亡", mortality = "死亡", dead = "死亡",
      survival = "生存", hospitalmortality = "住院死亡",
      fustatus = "住院死亡", inhospitalmortality = "住院死亡",
      aki = "AKI", acutekidneyinjury = "AKI",
      day28mortality = "28天死亡", twentyeightdaymortality = "28天死亡",
      hipfracture = "髋部骨折", dementia = "痴呆",
      stroke = "卒中", diabetes = "糖尿病",
      diseasegroup = "疾病结局", disease_group = "疾病结局"
    )
    if (key %in% names(map)) return(unname(map[[key]]))
    return(x)
  }
  if (identical(kind, "grouping")) {
    g <- tolower(x)
    if (g %in% c("binary", "二分")) return("二分位")
    if (g %in% c("tertile", "三分", "三分位")) return("三分位")
    if (g %in% c("quartile", "四分", "四分位")) return("四分位")
    if (g %in% c("quintile", "五分", "五分位")) return("五分位")
    return(x)
  }
  x
}

.pub_figure_db_labels <- function(meta) {
  dbs <- as.character(meta$databases %||% character(0))
  dbs <- dbs[nzchar(dbs)]
  if (!length(dbs)) return(character(0))
  # 展示名原样规范；禁止把 NHANES 误映射成 eICU（发病/ML 双库常见）
  vapply(dbs, function(d) {
    raw <- trimws(as.character(d)[1L])
    key <- tolower(gsub("[^A-Za-z0-9]+", "", raw))
    if (key == "nhanes") return("NHANES")
    if (key == "charls") return("CHARLS")
    if (key == "elsa") return("ELSA")
    if (key == "hrs") return("HRS")
    if (key %in% c("eicu", "eicuiv")) return("eICU")
    if (key == "mimic") return("MIMIC")
    if (key == "primary") return("eICU")
    if (key == "secondary") return("MIMIC")
    raw
  }, character(1), USE.NAMES = FALSE)
}

.pub_figure_cohort_clause <- function(meta) {
  dbs <- .pub_figure_db_labels(meta)
  if (!length(dbs)) return("")
  if (isTRUE(meta$combined) && length(dbs) >= 2L) {
    return(sprintf("（%s 左右拼图）", paste(dbs, collapse = " 与 ")))
  }
  sprintf("（%s）", paste(dbs, collapse = "、"))
}

.pub_figure_read_xlsx_mat <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch({
    if (requireNamespace("readxl", quietly = TRUE)) {
      as.data.frame(readxl::read_excel(path, sheet = 1L, col_names = FALSE),
                    stringsAsFactors = FALSE)
    } else if (requireNamespace("openxlsx", quietly = TRUE)) {
      openxlsx::read.xlsx(path, sheet = 1L, colNames = FALSE)
    } else {
      NULL
    }
  }, error = function(e) NULL)
}

#' 从发表 Table 2 矩阵解析：最高分位 Model2 效应 + trend P + 连续变量效应
.pub_figure_parse_table2_mat <- function(mat, db = "") {
  if (is.null(mat) || !nrow(mat) || !ncol(mat)) return(NULL)
  mat[] <- lapply(mat, function(col) as.character(col))
  mat[is.na(mat)] <- ""
  # 找表头行：含 Model2 与 P-value / HR|OR
  hdr_i <- NA_integer_
  for (i in seq_len(min(12L, nrow(mat)))) {
    row <- tolower(paste(mat[i, ], collapse = " "))
    if (grepl("model\\s*2", row) && grepl("p-?value|p value", row)) {
      hdr_i <- i
      break
    }
  }
  if (!is.finite(hdr_i)) {
    for (i in seq_len(min(12L, nrow(mat)))) {
      row <- tolower(paste(mat[i, ], collapse = " "))
      if (grepl("p-?value", row) && grepl("\\bhr\\b|\\bor\\b", row)) {
        hdr_i <- i
        break
      }
    }
  }
  if (!is.finite(hdr_i)) return(NULL)

  hdr <- tolower(as.character(mat[hdr_i, ]))

  # 优先锁定 Model2 列块：上一行（或同区）标有 Model2，通常落在 95%CI 列
  model_row <- if (hdr_i > 1L) hdr_i - 1L else hdr_i
  model_cells <- tolower(as.character(mat[model_row, ]))
  m2_anchor <- which(grepl("^model\\s*2$", model_cells))
  if (!length(m2_anchor)) {
    # 偶尔 Model2 与表头同行
    m2_anchor <- which(grepl("^model\\s*2$", hdr))
  }
  if (length(m2_anchor)) {
    anc <- m2_anchor[[1L]]
    # 常见：Model2 标在 CI 列 → HR=anc-1, CI=anc, P=anc+1
    if (anc >= 2L && grepl("^hr$|^or$", hdr[[anc - 1L]]) &&
        grepl("p-?value|^p$", hdr[min(anc + 1L, length(hdr))])) {
      est_col <- anc - 1L
      ci_col <- anc
      p_col <- anc + 1L
    } else {
      # 回退：Model2 锚点右侧最近的 HR/CI/P 三元组
      est_col <- {
        cands <- which(grepl("^hr$|^or$", hdr) & seq_along(hdr) >= anc - 1L & seq_along(hdr) <= anc + 2L)
        if (length(cands)) cands[[1L]] else NA_integer_
      }
      if (!is.finite(est_col)) return(NULL)
      ci_col <- {
        cands <- which(grepl("95%\\s*ci|95%ci|^ci$", hdr) & seq_along(hdr) > est_col)
        if (length(cands)) cands[[1L]] else NA_integer_
      }
      p_col <- {
        cands <- which(grepl("^p-?value$|^p$", hdr) & seq_along(hdr) > est_col)
        if (length(cands)) cands[[1L]] else NA_integer_
      }
    }
  } else {
    # 无 Model2 标签：取倒数第二组 HR/P（避开可能的 Model3）；若只有一组则用该组
    p_cols <- which(grepl("^p-?value$|^p$", hdr))
    est_cols <- which(grepl("^hr$|^or$", hdr))
    if (!length(p_cols) || !length(est_cols)) return(NULL)
    if (length(p_cols) >= 2L) {
      p_col <- p_cols[[length(p_cols) - 1L]]
    } else {
      p_col <- p_cols[[1L]]
    }
    est_col <- max(est_cols[est_cols < p_col], na.rm = TRUE)
    if (!is.finite(est_col)) return(NULL)
    ci_cols <- which(grepl("95%\\s*ci|95%ci|^ci$", hdr))
    ci_col <- if (length(ci_cols)) {
      cands <- ci_cols[ci_cols > est_col & ci_cols < p_col]
      if (length(cands)) max(cands) else NA_integer_
    } else NA_integer_
  }
  if (!is.finite(est_col) || !is.finite(p_col)) return(NULL)
  metric <- toupper(gsub("\\s+", "", hdr[[est_col]]))
  if (!metric %in% c("HR", "OR")) metric <- "HR"

  # 最高非 Ref 分位行：Q4/Q5/Q3/T3/Highest
  lab_col <- 1L
  q_rows <- integer(0)
  for (i in seq.int(hdr_i + 1L, nrow(mat))) {
    lab <- mat[i, lab_col]
    if (grepl("^Q[2-9]|^T[2-9]|^Highest|^High\\b", lab, ignore.case = TRUE) &&
        !grepl("trend|continuous|Ref", lab, ignore.case = TRUE)) {
      q_rows <- c(q_rows, i)
    }
  }
  if (!length(q_rows)) return(NULL)
  # 取编号最大的 Q/T
  score <- vapply(q_rows, function(i) {
    lab <- mat[i, lab_col]
    m <- regmatches(lab, regexpr("[0-9]+", lab))
    if (length(m) && nzchar(m)) as.integer(m) else 0L
  }, integer(1L))
  hi <- q_rows[[which.max(score)]]
  high_lab <- mat[hi, lab_col]
  est <- mat[hi, est_col]
  pval <- mat[hi, p_col]
  ci <- if (is.finite(ci_col)) mat[hi, ci_col] else ""
  if (!nzchar(est) || grepl("^ref$", est, ignore.case = TRUE)) return(NULL)

  trend_p <- ""
  for (i in seq.int(hdr_i + 1L, nrow(mat))) {
    if (grepl("p\\s*for\\s*trend|trend", mat[i, lab_col], ignore.case = TRUE)) {
      trend_p <- mat[i, p_col]
      break
    }
  }

  cont_est <- ""; cont_p <- ""; cont_ci <- ""
  for (i in seq.int(hdr_i + 1L, nrow(mat))) {
    if (grepl("continuous", mat[i, lab_col], ignore.case = TRUE)) {
      cont_est <- mat[i, est_col]
      cont_p <- mat[i, p_col]
      cont_ci <- if (is.finite(ci_col)) mat[i, ci_col] else ""
      break
    }
  }

  list(
    db = as.character(db %||% "")[1L],
    metric = metric,
    high_label = high_lab,
    estimate = est,
    ci = ci,
    p = pval,
    trend_p = trend_p,
    continuous_est = cont_est,
    continuous_ci = cont_ci,
    continuous_p = cont_p
  )
}

.pub_figure_assoc_clause <- function(a) {
  if (is.null(a) || !nzchar(a$estimate %||% "")) return("")
  bits <- sprintf(
    "%s相对Q1的Model2 %s=%s",
    a$high_label %||% "最高分组",
    a$metric %||% "HR",
    a$estimate
  )
  if (nzchar(a$ci %||% "") && !grepl("^ref$", a$ci, ignore.case = TRUE)) {
    bits <- paste0(bits, sprintf("（95%%CI %s", gsub("[()]", "", a$ci)))
    if (nzchar(a$p %||% "")) bits <- paste0(bits, sprintf("，P=%s", a$p))
    bits <- paste0(bits, "）")
  } else if (nzchar(a$p %||% "")) {
    bits <- paste0(bits, sprintf("（P=%s）", a$p))
  }
  if (nzchar(a$db %||% "")) bits <- paste0(a$db, "：", bits)
  if (nzchar(a$trend_p %||% "")) {
    bits <- paste0(bits, sprintf("，P for trend=%s", a$trend_p))
  }
  bits
}

.pub_figure_cutoff_clause <- function(cut_info, exp = "") {
  if (is.null(cut_info) || !length(cut_info$values)) return("")
  vals <- paste(signif(as.numeric(cut_info$values), 4), collapse = "、")
  who <- if (nzchar(cut_info$db %||% "")) paste0(cut_info$db, "中") else ""
  what <- if (nzchar(exp)) paste0(exp, " ") else ""
  sprintf("%s%sHR=1参考/切点约在 %s", who, what, vals)
}

.pub_figure_fmt_p_label <- function(label, pv) {
  label <- as.character(label %||% "P")[1L]
  pv <- suppressWarnings(as.numeric(pv)[1L])
  if (!is.finite(pv)) return(paste0(label, " = NA"))
  if (pv < 0.001) return(paste0(label, " < 0.001"))
  paste0(label, " = ", formatC(pv, digits = 3, format = "f"))
}

.pub_figure_extract_cox_rcs_p <- function(p) {
  list(
    p_overall = tryCatch(
      suppressWarnings(as.numeric(p$logtest[3L]))[1L],
      error = function(e) NA_real_
    ),
    p_nonlinear = tryCatch(
      suppressWarnings(as.numeric(p$coefficients[2L, 5L]))[1L],
      error = function(e) NA_real_
    )
  )
}

.pub_figure_extract_lrm_anova_p <- function(an) {
  an <- tryCatch(as.matrix(an), error = function(e) NULL)
  if (is.null(an) || !nrow(an) || ncol(an) < 3L) {
    return(list(p_overall = NA_real_, p_nonlinear = NA_real_))
  }
  list(
    p_overall = suppressWarnings(as.numeric(an[nrow(an), 3L]))[1L],
    p_nonlinear = suppressWarnings(as.numeric(an[min(2L, nrow(an)), 3L]))[1L]
  )
}

.pub_figure_rcs_annotation_lines <- function(rcs_findings) {
  if (!length(rcs_findings)) return(character(0))
  out <- character(0)
  for (item in rcs_findings) {
    db <- as.character(item$db %||% "")[1L]
    for (pan in item$panels %||% list()) {
      nm <- as.character(pan$name %||% "Model2")[1L]
      bits <- c(
        .pub_figure_fmt_p_label("P-overall", pan$p_overall),
        .pub_figure_fmt_p_label("P-non-linear", pan$p_nonlinear)
      )
      cuts <- suppressWarnings(as.numeric(pan$cutoffs %||% numeric(0)))
      cuts <- cuts[is.finite(cuts)]
      if (length(cuts)) {
        bits <- c(bits, paste0("cutoff = ", paste(signif(cuts, 4), collapse = "、")))
      }
      who <- if (nzchar(db)) paste0(db, " ", nm) else nm
      out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
    }
  }
  out
}

.pub_figure_km_annotation_lines <- function(km_findings) {
  if (!length(km_findings)) return(character(0))
  out <- character(0)
  for (item in km_findings) {
    db <- as.character(item$db %||% "库")[1L]
    strata <- as.character(item$strata %||% "")[1L]
    who <- if (nzchar(strata)) paste0(db, " ", strata) else db
    bits <- character(0)
    if (!is.null(item$logrank_p)) {
      bits <- c(bits, .pub_figure_fmt_p_label("Log-rank P", item$logrank_p))
    }
    cv <- suppressWarnings(as.numeric(item$cutoff %||% NA_real_)[1L])
    if (is.finite(cv)) bits <- c(bits, sprintf("cutoff = %s", signif(cv, 4)))
    if (length(bits)) out <- c(out, sprintf("- %s：%s", who, paste(bits, collapse = "；")))
  }
  out
}

.pub_figure_forest_annotation_lines <- function(forest_findings) {
  if (!length(forest_findings)) return(character(0))
  out <- character(0)
  for (item in forest_findings) {
    db <- as.character(item$db %||% "")[1L]
    if (nzchar(db)) out <- c(out, paste0("#### ", db), "")
    df <- item$rows
    if (!is.data.frame(df) || !nrow(df)) {
      out <- c(out, "- 未收获：subgroup 表为空", "")
      next
    }
    var_col <- intersect(c("Variable", "Subgroup", "variable"), names(df))[1L]
    est_col <- intersect(c("Point Estimate", "HR", "OR"), names(df))[1L]
    lo_col <- intersect(c("Lower", "lower", "CI_low"), names(df))[1L]
    hi_col <- intersect(c("Upper", "upper", "CI_high"), names(df))[1L]
    pint_col <- grep("interaction|P(\\.|_| )?inter", names(df), ignore.case = TRUE)[1L]
    lev_col <- intersect(c("Levels", "Level", "levels"), names(df))[1L]
    if (!length(var_col) || is.na(var_col) || !nzchar(var_col)) {
      out <- c(out, "- 未收获：subgroup 缺 Variable 列", "")
      next
    }
    prev_sg <- ""
    for (i in seq_len(nrow(df))) {
      v <- as.character(df[[var_col]][i])
      if (!nzchar(v) || grepl("^-+$", v)) next
      lev <- if (!is.na(lev_col) && length(lev_col)) {
        trimws(as.character(df[[lev_col]][i]))
      } else {
        ""
      }
      est <- if (!is.na(est_col)) suppressWarnings(as.numeric(df[[est_col]][i])) else NA_real_
      lo <- if (!is.na(lo_col)) suppressWarnings(as.numeric(df[[lo_col]][i])) else NA_real_
      hi <- if (!is.na(hi_col)) suppressWarnings(as.numeric(df[[hi_col]][i])) else NA_real_
      is_hdr <- !nzchar(lev) && !is.finite(est)
      if (nzchar(lev) && !identical(trimws(v), prev_sg)) {
        pv <- if (length(pint_col) && is.finite(pint_col)) {
          suppressWarnings(as.numeric(df[[pint_col]][i]))
        } else {
          NA_real_
        }
        hdr_bit <- if (is.finite(pv)) .pub_figure_fmt_p_label("P for interaction", pv) else ""
        out <- c(out, sprintf("- %s：%s", trimws(v), if (nzchar(hdr_bit)) hdr_bit else " "))
        prev_sg <- trimws(v)
      }
      if (nzchar(lev)) v <- paste0("   ", lev)
      bits <- character(0)
      n_col <- intersect(c("Count", "N", "n"), names(df))[1L]
      if (!is.na(n_col) && length(n_col)) {
        nv <- suppressWarnings(as.numeric(df[[n_col]][i]))
        if (is.finite(nv)) bits <- c(bits, sprintf("N=%s", as.integer(nv)))
      }
      if (is.finite(est)) {
        if (is.finite(lo) && is.finite(hi)) {
          bits <- c(bits, sprintf("%s (95%%CI %s–%s)",
                                  formatC(est, digits = 2, format = "f"),
                                  signif(lo, 4), signif(hi, 4)))
        } else {
          bits <- c(bits, as.character(signif(est, 4)))
        }
      }
      if (isTRUE(is_hdr) && length(pint_col) && is.finite(pint_col)) {
        pv <- suppressWarnings(as.numeric(df[[pint_col]][i]))
        if (is.finite(pv)) bits <- c(bits, .pub_figure_fmt_p_label("P for interaction", pv))
      }
      if (length(bits)) out <- c(out, sprintf("- %s：%s", v, paste(bits, collapse = "；")))
    }
    out <- c(out, "")
  }
  out
}

.PUB_FIGURE_RCS_PANEL_STATS_KEYS <- c(
  "rcs_prognosis_panel_stats",
  "rcs_incidence_panel_stats",
  "rcs_nhanes_panel_stats",
  "rcs_iptw_panel_stats"
)

#' RCS 图上竖线 x：须与 vline drawer 同一向量（incidence `cutoff_vline_mode`；预后/NHANES/IPTW 画 `$all`）
#' @param cutoffs list with or1 / peak / all（与 rcs_primary_cutoff 同源）
#' @param mode "primary"：仅主 cutoff；"all"：全部交点
.pub_figure_rcs_vline_cutoffs <- function(cutoffs, mode = c("primary", "all")) {
  mode <- match.arg(mode)
  if (is.null(cutoffs)) return(numeric(0))
  if (identical(mode, "all")) {
    xs <- sort(unique(as.numeric(cutoffs$all %||% numeric(0))))
  } else {
    primary <- if (exists("rcs_primary_cutoff", mode = "function")) {
      suppressWarnings(as.numeric(rcs_primary_cutoff(cutoffs))[1L])
    } else if (is.list(cutoffs)) {
      if (length(cutoffs$or1) == 1L) as.numeric(cutoffs$or1[1L])
      else if (length(cutoffs$peak)) as.numeric(cutoffs$peak[1L])
      else if (length(cutoffs$or1)) as.numeric(cutoffs$or1[1L])
      else if (length(cutoffs$all)) as.numeric(cutoffs$all[1L])
      else NA_real_
    } else {
      NA_real_
    }
    xs <- if (is.finite(primary)) primary else numeric(0)
  }
  xs[is.finite(xs)]
}

#' 仅当该面板实际画竖线时写入 cutoff；否则空向量
.pub_figure_rcs_panel_vline_cutoffs <- function(cutoffs, show_vlines,
                                                mode = c("primary", "all", "none")) {
  mode <- match.arg(mode)
  if (!isTRUE(show_vlines) || identical(mode, "none")) return(numeric(0))
  .pub_figure_rcs_vline_cutoffs(cutoffs, mode)
}

#' Harvest 只打开可能含 RCS/KM/Forest 的 checkpoint（basename 匹配 rcs|km|subgroup）
.pub_figure_harvest_onplot_rds <- function(rds_files) {
  rds_files <- as.character(rds_files %||% character(0))
  if (!length(rds_files)) return(character(0))
  bn <- basename(rds_files)
  keep <- grepl("rcs|km|subgroup", bn, ignore.case = TRUE)
  rds_files <- rds_files[keep]
  if (!length(rds_files)) return(character(0))
  bn <- basename(rds_files)
  prio <- grepl("rcs|km|subgroup", bn, ignore.case = TRUE)
  c(rds_files[prio], rds_files[!prio])
}

#' 本库 RCS + forest + km_binary 已齐，且剩余文件不再含 km*（strata）时可跳过
.pub_figure_harvest_skip_rest <- function(remaining_files, db_lab,
                                         seen_rcs, seen_forest, seen_km_bin) {
  isTRUE(db_lab %in% seen_rcs) &&
    isTRUE(db_lab %in% seen_forest) &&
    isTRUE(db_lab %in% seen_km_bin) &&
    !any(grepl("km", basename(remaining_files %||% character(0)), ignore.case = TRUE))
}

#' 将 rcs_*_panel_stats 规范为 helpers 所需结构；无 panel_stats 则返回 NULL（不合成假 P）
.pub_figure_harvest_normalize_rcs <- function(res, db_lab) {
  if (!is.list(res) || !length(res)) return(NULL)
  ps <- NULL
  for (k in .PUB_FIGURE_RCS_PANEL_STATS_KEYS) {
    cand <- res[[k]]
    if (is.list(cand) && length(cand)) {
      ps <- cand
      break
    }
  }
  if (is.null(ps)) return(NULL)
  child_is_panel <- function(x) {
    is.list(x) && (!is.null(x$p_overall) || !is.null(x$p_nonlinear) || !is.null(x$name))
  }
  panels <- list()
  append_panel <- function(nm, pan) {
    if (!is.list(pan)) return()
    panels[[length(panels) + 1L]] <<- list(
      name = as.character(nm %||% pan$name %||% "Model2")[1L],
      p_overall = suppressWarnings(as.numeric(pan$p_overall %||% NA_real_)[1L]),
      p_nonlinear = suppressWarnings(as.numeric(pan$p_nonlinear %||% NA_real_)[1L]),
      cutoffs = pan$cutoffs
    )
  }
  nms <- names(ps)
  if (any(vapply(ps, child_is_panel, logical(1)))) {
    for (i in seq_along(ps)) {
      nm <- if (!is.null(nms) && nzchar(nms[[i]])) nms[[i]] else NULL
      append_panel(nm, ps[[i]])
    }
  } else if (child_is_panel(ps)) {
    append_panel(ps$name %||% "Model2", ps)
  }
  if (!length(panels)) return(NULL)
  list(db = as.character(db_lab %||% "")[1L], panels = panels)
}

.pub_figure_harvest_km_items <- function(res, db_lab) {
  items <- list()
  if (!is.list(res)) return(items)
  db_lab <- as.character(db_lab %||% "")[1L]
  kb <- res$km_binary
  if (is.list(kb) && !is.data.frame(kb) && (!is.null(kb$logrank_p) || !is.null(kb$cutoff))) {
    items[[length(items) + 1L]] <- list(
      db = db_lab, logrank_p = kb$logrank_p, cutoff = kb$cutoff, .slot = "binary"
    )
  }
  lbs <- NULL
  ks <- res$km_strata
  if (is.list(ks) && !is.data.frame(ks)) lbs <- ks$logrank_by_strata
  if (is.null(lbs) || !length(lbs)) return(items)
  push_strata <- function(st, lp, cu = NULL) {
    items[[length(items) + 1L]] <<- list(
      db = db_lab,
      strata = as.character(st %||% "")[1L],
      logrank_p = lp,
      cutoff = cu,
      .slot = "strata"
    )
  }
  nms <- names(lbs)
  if (is.numeric(lbs) || is.integer(lbs)) {
    for (i in seq_along(lbs)) {
      st <- if (!is.null(nms) && length(nms) >= i && nzchar(nms[[i]])) nms[[i]] else ""
      push_strata(st, unname(lbs[[i]]))
    }
  } else if (is.list(lbs)) {
    for (i in seq_along(lbs)) {
      el <- lbs[[i]]
      st_nm <- if (!is.null(nms) && length(nms) >= i && nzchar(nms[[i]])) nms[[i]] else ""
      if (is.list(el)) {
        push_strata(el$strata %||% st_nm, el$logrank_p %||% el[[1L]], el$cutoff)
      } else if (is.numeric(el) || is.integer(el)) {
        push_strata(st_nm, unname(el))
      }
    }
  }
  items
}

#' 从 Figures 旁 Tables/ 与各库 step* cutoff_*.csv / checkpoint 收获可写入正文的结果要点
pub_figure_harvest_findings <- function(figures_dir, meta = list()) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  index_root <- dirname(figures_dir)
  tab_dir <- file.path(index_root, "Tables")
  # 自定义课题（如 ml_nafld_cm）：Tables 可能在 index_root 的上级（课题根/Tables），
  # 且 tab_dir 不存在时 harvest 整体不得跳过（纳排/ROC 回退仍要跑）
  if (!dir.exists(tab_dir)) {
    for (anc in c(dirname(index_root), file.path(dirname(index_root), basename(index_root)))) {
      cand <- file.path(anc, "Tables")
      if (dir.exists(cand)) { tab_dir <- cand; break }
    }
  }
  out <- list(association = list(), cutoffs = list(), attrition = list(), roc = list(),
              maxstat = list(), rcs = list(), km = list(), forest = list())

  # Table 2：优先无库标签；否则各库一份
  if (dir.exists(tab_dir)) {
    t2 <- list.files(tab_dir, pattern = "^Table\\s*2.*\\.(xlsx|xls)$",
                     full.names = TRUE, ignore.case = TRUE)
    t2 <- t2[!grepl("Missing", basename(t2), ignore.case = TRUE)]
    if (length(t2)) {
      dbs <- as.character(meta$databases %||% character(0))
      # 无 -DB 的优先
      untagged <- t2[!grepl("-(eICU|MIMIC|NHANES|CHARLS|ELSA|HRS)\\.", basename(t2), ignore.case = TRUE)]
      pick <- if (length(untagged)) untagged else t2
      for (fp in pick) {
        db <- ""
        for (d in dbs) {
          if (grepl(paste0("-", d, "\\."), basename(fp), ignore.case = TRUE)) {
            db <- d
            break
          }
        }
        if (!nzchar(db)) {
          m <- regmatches(basename(fp), regexpr("-(eICU|MIMIC|NHANES|CHARLS|ELSA|HRS)\\.", basename(fp), ignore.case = TRUE, perl = TRUE))
          if (length(m) && nzchar(m)) db <- sub("^-", "", sub("\\.$", "", m))
        }
        mat <- .pub_figure_read_xlsx_mat(fp)
        parsed <- .pub_figure_parse_table2_mat(mat, db = db)
        if (!is.null(parsed)) out$association[[length(out$association) + 1L]] <- parsed
      }
    }

    # 纳排逐步人数：优先指标 Tables，再回退课题根 Tables
    # index_root = .../by_index/【success】IX → study_root = dirname(dirname(index_root))
    attr_pat <- "^Flowchart_attrition.*\\.csv$"
    attr_csv <- list.files(tab_dir, pattern = attr_pat, full.names = TRUE, ignore.case = TRUE)
    if (!length(attr_csv)) {
      study_root <- dirname(dirname(index_root))
      proj_tabs <- unique(c(
        file.path(study_root, "Tables"),
        file.path(dirname(index_root), "Tables") # 兼容误放在 by_index/Tables
      ))
      for (proj_tab in proj_tabs) {
        if (!dir.exists(proj_tab)) next
        attr_csv <- list.files(proj_tab, pattern = attr_pat, full.names = TRUE, ignore.case = TRUE)
        if (length(attr_csv)) break
      }
    }
    for (fp in attr_csv) {
      df <- tryCatch(utils::read.csv(fp, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(df) || !nrow(df)) next
      cn <- tolower(names(df))
      step_col <- if ("step" %in% cn) which(cn == "step")[1L] else 1L
      n_col <- if ("n" %in% cn) which(cn == "n")[1L] else {
        num <- which(vapply(df, is.numeric, logical(1)))
        if (length(num)) num[[1L]] else 2L
      }
      db_col <- if ("database" %in% cn) which(cn == "database")[1L] else NA_integer_
      for (i in seq_len(nrow(df))) {
        db <- if (is.finite(db_col)) as.character(df[[db_col]][i]) else ""
        n <- suppressWarnings(as.integer(df[[n_col]][i]))
        step <- as.character(df[[step_col]][i])
        if (!nzchar(step) || !is.finite(n)) next
        out$attrition[[length(out$attrition) + 1L]] <- list(
          db = db, step = step, n = n, path = fp,
          fork_left_label = if ("fork_left_label" %in% names(df)) as.character(df$fork_left_label[i])[1L] else NA_character_,
          fork_left_n = if ("fork_left_n" %in% names(df)) suppressWarnings(as.integer(df$fork_left_n[i])[1L]) else NA_integer_,
          fork_right_label = if ("fork_right_label" %in% names(df)) as.character(df$fork_right_label[i])[1L] else NA_character_,
          fork_right_n = if ("fork_right_n" %in% names(df)) suppressWarnings(as.integer(df$fork_right_n[i])[1L]) else NA_integer_
        )
      }
    }
  }

  # RCS cutoff csv：index_root/<DB>/step*_rcs*/cutoff_*.csv
  if (dir.exists(index_root)) {
    cuts <- list.files(
      index_root, pattern = "^cutoff_.*\\.csv$",
      full.names = TRUE, recursive = TRUE, ignore.case = TRUE
    )
    # 跳过 sensitivity 深层重复：优先深度较浅
    cuts <- cuts[!grepl("sensitivity|SA_", cuts, ignore.case = TRUE)]
    for (fp in cuts) {
      db <- ""
      parts <- strsplit(fp, "[/\\\\]")[[1]]
      for (d in c(as.character(meta$databases %||% character(0)),
                  "eICU", "MIMIC", "NHANES", "CHARLS", "ELSA", "HRS")) {
        if (d %in% parts) { db <- d; break }
      }
      df <- tryCatch(utils::read.csv(fp, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(df) || !nrow(df)) next
      cn <- tolower(names(df))
      vcol <- if ("cutoff" %in% cn) which(cn == "cutoff")[1L] else {
        num <- which(vapply(df, is.numeric, logical(1)))
        if (length(num)) num[[1L]] else 1L
      }
      vals <- suppressWarnings(as.numeric(df[[vcol]]))
      vals <- vals[is.finite(vals)]
      if (!length(vals)) next
      out$cutoffs[[length(out$cutoffs) + 1L]] <- list(db = db, values = vals, path = fp)
    }
  }

  # ROC / maxstat：从 study checkpoints/by_index/<ix>/<DB>/*.rds 收获
  ix <- sub("^【[^】]+】", "", basename(index_root))
  study_root <- dirname(dirname(index_root))
  ck_root <- file.path(study_root, "checkpoints", "by_index", ix)
  db_dirs <- c(
    file.path(index_root, "eICU"), file.path(index_root, "MIMIC"),
    file.path(index_root, "MIMIC_IV"), file.path(index_root, "NHANES"),
    file.path(index_root, "CHARLS"),
    file.path(ck_root, "eICU"), file.path(ck_root, "MIMIC"),
    file.path(ck_root, "MIMIC_IV"), file.path(ck_root, "NHANES"),
    file.path(ck_root, "CHARLS"),
    file.path(ck_root, "nhanes"), file.path(ck_root, "mimic")
  )
  seen_rcs <- character(0)
  seen_km_bin <- character(0)
  seen_km_str <- character(0)
  seen_forest <- character(0)
  for (dd in unique(db_dirs)) {
    if (!dir.exists(dd)) next
    db_lab <- basename(dd)
    key <- tolower(db_lab)
    if (key == "nhanes") {
      db_lab <- "NHANES"
    } else if (key %in% c("eicu", "e_icu")) {
      db_lab <- "eICU"
    } else if (key == "mimic") {
      db_lab <- "MIMIC"
    } else if (key == "charls") {
      db_lab <- "CHARLS"
    }

    rds_files <- .pub_figure_harvest_onplot_rds(
      list.files(dd, pattern = "\\.rds$", full.names = TRUE)
    )
    if (length(rds_files)) {
      for (i_rp in seq_along(rds_files)) {
        if (.pub_figure_harvest_skip_rest(
          remaining_files = rds_files[i_rp:length(rds_files)],
          db_lab = db_lab,
          seen_rcs = seen_rcs, seen_forest = seen_forest, seen_km_bin = seen_km_bin
        )) {
          break
        }
        rp <- rds_files[[i_rp]]
        obj <- tryCatch(readRDS(rp), error = function(e) NULL)
        if (is.null(obj)) next
        res <- obj$ctx$results %||% obj$results %||% list()
        if (!is.list(res) || !length(res)) next

        if (!(db_lab %in% seen_rcs)) {
          rcs_item <- .pub_figure_harvest_normalize_rcs(res, db_lab)
          if (!is.null(rcs_item)) {
            out$rcs[[length(out$rcs) + 1L]] <- rcs_item
            seen_rcs <- c(seen_rcs, db_lab)
          }
        }

        km_items <- .pub_figure_harvest_km_items(res, db_lab)
        for (it in km_items) {
          slot <- as.character(it$.slot %||% "binary")[1L]
          it$.slot <- NULL
          if (identical(slot, "binary")) {
            if (db_lab %in% seen_km_bin) next
            seen_km_bin <- c(seen_km_bin, db_lab)
          } else {
            key <- paste(db_lab, it$strata %||% "", sep = "\t")
            if (key %in% seen_km_str) next
            seen_km_str <- c(seen_km_str, key)
          }
          out$km[[length(out$km) + 1L]] <- it
        }

        if (!(db_lab %in% seen_forest)) {
          sg_df <- NULL
          if (is.data.frame(res$subgroup) && nrow(res$subgroup) > 0L) {
            sg_df <- res$subgroup
          } else if (is.data.frame(res$nhanes_subgroup) && nrow(res$nhanes_subgroup) > 0L) {
            sg_df <- res$nhanes_subgroup
          }
          if (!is.null(sg_df)) {
            out$forest[[length(out$forest) + 1L]] <- list(db = db_lab, rows = sg_df)
            seen_forest <- c(seen_forest, db_lab)
          }
        }
      }
    }

    roc_p <- file.path(dd, "simple_ROC.rds")
    if (!file.exists(roc_p)) {
      hits <- Sys.glob(file.path(dd, "*simple_ROC*.rds"))
      if (length(hits)) roc_p <- hits[[1L]]
    }
    if (file.exists(roc_p)) {
      obj <- tryCatch(readRDS(roc_p), error = function(e) NULL)
      res <- obj$ctx$results %||% obj$results %||% list()
      auc <- suppressWarnings(as.numeric(res$roc_auc %||% NA_real_)[1L])
      if (is.finite(auc)) {
        ci <- suppressWarnings(as.numeric(res$roc_ci %||% numeric(0)))
        out$roc[[length(out$roc) + 1L]] <- list(
          db = db_lab,
          auc = auc,
          ci_lo = if (length(ci) >= 1L) ci[[1L]] else NA_real_,
          ci_hi = if (length(ci) >= 2L) ci[[2L]] else NA_real_,
          sens = suppressWarnings(as.numeric(res$roc_sensitivity %||% NA_real_)[1L]),
          spec = suppressWarnings(as.numeric(res$roc_specificity %||% NA_real_)[1L]),
          youden = suppressWarnings(as.numeric(res$roc_cutoff %||% NA_real_)[1L])
        )
      }
    }

    pc_p <- file.path(dd, "plot_cutoff.rds")
    if (!file.exists(pc_p)) {
      hits <- Sys.glob(file.path(dd, "*plot_cutoff*.rds"))
      if (length(hits)) pc_p <- hits[[1L]]
    }
    if (file.exists(pc_p)) {
      obj <- tryCatch(readRDS(pc_p), error = function(e) NULL)
      res <- obj$ctx$results %||% obj$results %||% list()
      pc <- res$plot_cutoff %||% list()
      ms <- suppressWarnings(as.numeric(pc$maxstat_cutoff %||% pc$cutoff %||% NA_real_)[1L])
      up <- suppressWarnings(as.numeric(pc$upstream_cutoff %||% res$cutoff_value %||% NA_real_)[1L])
      if (is.finite(ms) || is.finite(up)) {
        out$maxstat[[length(out$maxstat) + 1L]] <- list(
          db = db_lab, maxstat = ms, upstream = up,
          annotate = as.character(pc$annotate_cutoff %||% "maxstat")[1L]
        )
      }
    }
  }
  out
}

.pub_figure_findings_summary <- function(meta, role = c("km", "rcs", "forest", "roc", "other")) {
  role <- match.arg(role)
  # 调用方可直接注入完整句子
  if (nzchar(as.character(meta$result_sentence %||% "")[1L])) {
    return(as.character(meta$result_sentence)[1L])
  }
  find <- meta$findings %||% list()
  assocs <- find$association %||% list()
  cuts <- find$cutoffs %||% list()
  assoc_txt <- character(0)
  for (a in assocs) {
    cl <- .pub_figure_assoc_clause(a)
    if (nzchar(cl)) assoc_txt <- c(assoc_txt, cl)
  }
  assoc_join <- if (length(assoc_txt)) paste(assoc_txt, collapse = "；") else ""
  cut_txt <- character(0)
  exp <- as.character(meta$exposure %||% "")[1L]
  for (c in cuts) {
    cl <- .pub_figure_cutoff_clause(c, exp = exp)
    if (nzchar(cl)) cut_txt <- c(cut_txt, cl)
  }
  cut_join <- if (length(cut_txt)) paste(unique(cut_txt), collapse = "；") else ""

  if (identical(role, "rcs")) {
    bits <- character(0)
    if (nzchar(cut_join)) bits <- c(bits, cut_join)
    # 连续变量效应优先
    cont_bits <- character(0)
    for (a in assocs) {
      if (nzchar(a$continuous_est %||% "")) {
        b <- sprintf(
          "%s连续变量Model2 %s=%s",
          if (nzchar(a$db %||% "")) paste0(a$db, "：") else "",
          a$metric %||% "HR", a$continuous_est
        )
        if (nzchar(a$continuous_ci %||% "")) {
          b <- paste0(b, sprintf("（95%%CI %s", gsub("[()]", "", a$continuous_ci)))
          if (nzchar(a$continuous_p %||% "")) b <- paste0(b, sprintf("，P=%s", a$continuous_p))
          b <- paste0(b, "）")
        } else if (nzchar(a$continuous_p %||% "")) {
          b <- paste0(b, sprintf("（P=%s）", a$continuous_p))
        }
        cont_bits <- c(cont_bits, b)
      }
    }
    if (length(cont_bits)) bits <- c(bits, paste(cont_bits, collapse = "；"))
    if (!length(bits) && nzchar(assoc_join)) bits <- c(bits, assoc_join)
    return(paste(bits, collapse = "；"))
  }
  # KM / forest / other：用最高分位 vs Q1
  assoc_join
}

.pub_figure_attrition_lines <- function(meta) {
  rows <- (meta$findings %||% list())$attrition %||% list()
  if (!length(rows)) return(character(0))
  db_keys <- vapply(rows, function(r) {
    d <- as.character(r$db %||% "")[1L]
    if (!nzchar(d)) return("未知库")
    key <- tolower(gsub("[^A-Za-z0-9]+", "", d))
    if (key == "nhanes") return("NHANES")
    if (key == "charls") return("CHARLS")
    if (key == "elsa") return("ELSA")
    if (key == "hrs") return("HRS")
    if (key %in% c("eicu", "eicuiv", "primary")) return("eICU")
    if (key %in% c("mimic", "secondary")) return("MIMIC")
    d
  }, character(1))
  out <- character(0)
  for (db in unique(db_keys)) {
    out <- c(out, paste0("### ", db), "")
    prev <- NA_integer_
    idx <- which(db_keys == db)
    for (j in idx) {
      r <- rows[[j]]
      n <- suppressWarnings(as.integer(r$n)[1L])
      step <- as.character(r$step %||% "")[1L]
      if (!nzchar(step) || !is.finite(n)) next
      excl <- if (is.finite(prev) && n < prev) as.integer(prev - n) else NA_integer_
      if (is.finite(excl) && excl > 0L) {
        out <- c(out, sprintf(
          "- %s：n=%s（本步排除 %s 人）",
          step, format(n, big.mark = ","), format(excl, big.mark = ",")
        ))
      } else {
        out <- c(out, sprintf("- %s：n=%s", step, format(n, big.mark = ",")))
      }
      prev <- n
    }
    last_r <- rows[[idx[length(idx)]]]
    fl <- as.character(last_r$fork_left_label %||% "")[1L]
    fr <- as.character(last_r$fork_right_label %||% "")[1L]
    fn_l <- suppressWarnings(as.integer(last_r$fork_left_n)[1L])
    fn_r <- suppressWarnings(as.integer(last_r$fork_right_n)[1L])
    if (nzchar(fl) && nzchar(fr) && is.finite(fn_l) && is.finite(fn_r)) {
      out <- c(out, sprintf(
        "- 底部分叉：%s n=%s；%s n=%s",
        fl, format(fn_l, big.mark = ","), fr, format(fn_r, big.mark = ",")
      ))
    }
    out <- c(out, "")
  }
  out
}

#' 图面详细说明（多段；纳排图含逐步人数）
.pub_figure_detailed_body <- function(stem, meta = list()) {
  extra <- meta$figure_body_lines
  if (!is.null(extra) && length(extra)) {
    return(as.character(unlist(extra, use.names = FALSE)))
  }
  s <- as.character(stem %||% "")[1L]
  caption <- .pub_figure_caption_from_stem(s)
  exp <- as.character(meta$exposure %||% "")[1L]
  out_raw <- as.character(meta$outcome %||% "")[1L]
  out <- .pub_figure_plain_term(out_raw, "outcome")
  if (!nzchar(out)) out <- out_raw
  grp <- .pub_figure_plain_term(meta$grouping %||% "", "grouping")
  if (!nzchar(grp) && nzchar(as.character(meta$grouping %||% "")[1L])) {
    grp <- as.character(meta$grouping)[1L]
  }
  by_grp <- if (nzchar(grp) && nzchar(exp)) {
    sprintf("按 %s %s分组", exp, grp)
  } else if (nzchar(exp)) {
    sprintf("按 %s 分组", exp)
  } else {
    "按暴露分组"
  }
  of_out <- if (nzchar(out)) out else "结局事件"
  exp_out <- if (nzchar(exp) && nzchar(out)) {
    sprintf("%s 与 %s", exp, out)
  } else if (nzchar(exp)) {
    exp
  } else if (nzchar(out)) {
    out
  } else {
    "暴露与结局"
  }
  cohort <- .pub_figure_cohort_clause(meta)
  dbs <- .pub_figure_db_labels(meta)
  panel_note <- if (isTRUE(meta$combined) && length(dbs) >= 2L) {
    paste0(
      "多库拼图：",
      paste(sprintf("%s 面板=%s", LETTERS[seq_along(dbs)], dbs), collapse = "；"),
      "。"
    )
  } else {
    ""
  }
  find <- meta$findings %||% list()
  lines <- character(0)

  if (grepl("landmark analysis", s, ignore.case = TRUE)) {
    day <- regmatches(s, regexpr("Day\\s*[- ]?\\d+", s, ignore.case = TRUE))
    if (!length(day) || !nzchar(day)) day <- "预设时间点"
    lines <- c(
      lines,
      sprintf(
        "本图为%s固定地标分析%s：仅纳入地标时点仍处于风险集的患者，横轴为 ICU 入院后的时间，纵轴为条件生存概率；曲线按双指标中位数高/低交叉形成的 Group1–4 分层。",
        day, cohort
      ),
      "",
      "面板按 Diabetes 基线状态分层，用于比较同一代谢背景内联合风险组在地标时点后的生存差异。",
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    lines <- c(
      lines,
      "图上标注：",
      "",
      "- 各面板显示对应的 Log-rank P；结构化数值未从 companion 结果表收获，请以图面标注为准。",
      ""
    )
    return(lines)
  }

  if (grepl("ROC comparison of joint indices", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为双复合指标、联合 Group1–4 与 APSIII 的 ROC 对照%s：横轴为 1−特异度，纵轴为灵敏度；对角线表示无判别能力。",
        cohort
      ),
      "",
      "图例直接标注各预测项 AUC，用于比较双指标及其联合分组相对传统重症评分 APSIII 的判别能力。",
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    lines <- c(
      lines,
      "图上标注：",
      "",
      "- AUC 及 95%CI 同源保存于对应数据库的 `Table S. ROC comparison with APSIII.xlsx`；结构化图面数值未收获时以该表为准。",
      ""
    )
    return(lines)
  }

  if (grepl("Flowchart|Inclusion|Exclusion|Attrition", s, ignore.case = TRUE)) {
    who <- if (nzchar(out)) sprintf("%s", out) else "本研究"
    lines <- c(
      lines,
      sprintf(
        "本图为 CONSORT 式纳排流程图%s，展示%s相关分析队列从原始提取到最终纳入的逐步筛选。主列为纳入人数，右侧 Exclude 框为相邻步差额与排除原因；底部分叉为发病病例/对照（或预后死亡/存活）。",
        cohort, who
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    attr_lines <- .pub_figure_attrition_lines(meta)
    if (length(attr_lines)) {
      lines <- c(lines, "各库逐步人数（来自 `Tables/Flowchart_attrition*.csv`，相邻步差额为本步排除人数）：", "", attr_lines)
    } else {
      lines <- c(lines, "未找到纳排 CSV（`Flowchart_attrition*.csv`），无法逐条列出排除人数；请核对 Tables 目录。", "")
    }
    if (!is.null(meta$n_by_db) && length(meta$n_by_db)) {
      lines <- c(
        lines,
        paste0(
          "指标级最终分析样本量：",
          paste(sprintf("%s=%s", names(meta$n_by_db), meta$n_by_db), collapse = "；"),
          if (!is.null(meta$n_total)) sprintf("；合计 N=%s", meta$n_total) else "",
          "。"
        ),
        ""
      )
    }
    return(lines)
  }

  if (grepl("Lasso", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为 LASSO 特征筛选图%s：上下面板 A 为变量惩罚系数/频次路径（S2A），面板 B 为交叉验证或模型图（S2B）；左上角 A/B 对应两张源图。合成页为矢量 PDF（非栅格拼图），禁止多页 pdf_combine。",
        cohort
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    return(lines)
  }

  if (grepl("Cutoff|maxstat|Maximally\\s*Selected", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为 maxstat（maximally selected rank statistics）最优切点诊断图%s：上方面板为按切点划分的高低组分布，下方面板为标准化 log-rank 统计量随切点变化的曲线；虚线标在曲线峰值对应的真实 maxstat 最优点（不是 RCS 上游切点）。",
        cohort
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    ms <- find$maxstat %||% list()
    if (length(ms)) {
      lines <- c(lines, "图上标注：", "", "各库切点：")
      seen_ms <- character(0)
      for (m in ms) {
        db <- as.character(m$db %||% "库")[1L]
        if (db %in% seen_ms) next
        seen_ms <- c(seen_ms, db)
        bits <- character(0)
        if (is.finite(m$maxstat %||% NA_real_)) {
          bits <- c(bits, sprintf("图上 maxstat=%.4f", m$maxstat))
        }
        if (is.finite(m$upstream %||% NA_real_)) {
          bits <- c(bits, sprintf("上游 RCS/配置切点=%.4f（不钉在图上，可供分段 Cox 使用）", m$upstream))
        }
        if (length(bits)) {
          lines <- c(lines, sprintf("- %s：%s", db, paste(bits, collapse = "；")))
        }
      }
      lines <- c(lines, "")
    }
    return(lines)
  }

  if (grepl("\\bKM\\b|Kaplan", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为 Kaplan–Meier 生存曲线%s：横轴为随访时间，纵轴为累积生存/事件概率；曲线按 %s 分层，用于直观比较组间%s风险差异（log-rank 见主文/图注）。",
        cohort, by_grp, of_out
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    km_find <- .pub_figure_findings_summary(meta, "km")
    if (nzchar(km_find)) {
      lines <- c(lines, paste0("结合同目录 Table 2（多因素 Model2）要点：", km_find, "。"), "")
    } else {
      lines <- c(lines, "具体组间效应量见同目录 Table 2；图本身主要展示累积风险曲线形态。", "")
    }
    lines <- c(lines, "图上标注：", "")
    km_ann <- .pub_figure_km_annotation_lines(find$km %||% list())
    if (length(km_ann)) {
      lines <- c(lines, km_ann, "")
    } else {
      lines <- c(lines, "- 未收获：Log-rank P（及 binary cutoff）", "")
    }
    return(lines)
  }

  if (grepl("\\bRCS\\b|Restricted\\s*Cubic", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为限制性立方样条（RCS）剂量–反应曲线%s，展示连续型 %s 与 %s 的关联形态（是否线性、拐点位置）；阴影/置信带表示不确定性。",
        cohort, if (nzchar(exp)) exp else "暴露", of_out
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    rcs_find <- .pub_figure_findings_summary(meta, "rcs")
    if (nzchar(rcs_find)) {
      lines <- c(lines, paste0("切点与连续变量效应要点：", rcs_find, "。"), "")
    }
    lines <- c(lines, "图上标注（与面板一致）：", "")
    rcs_ann <- .pub_figure_rcs_annotation_lines(find$rcs %||% list())
    if (length(rcs_ann)) {
      lines <- c(lines, rcs_ann, "")
    } else {
      lines <- c(lines, "- 未收获：各库 RCS panel_stats / P-overall / P-non-linear / cutoff", "")
    }
    return(lines)
  }

  if (grepl("Correlation Heatmap|Correlation Matrix|Spearman Correlation", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为连续变量 Spearman 相关热图%s：色块表示两两秩相关强度与方向，单元格标注相关系数及显著性（*/**/***）；聚类排序便于识别共线簇。用于描述基线连续变量相关结构，不替代多因素模型。",
        cohort
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    if (nzchar(exp)) {
      lines <- c(lines, sprintf("暴露指标 %s 若在矩阵中，可对照其与其它化验的相关强弱。", exp), "")
    }
    return(lines)
  }

  if (grepl("Forest|Subgroup", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为亚组森林图%s：在各临床分层内估计 %s 的关联（通常为最高分位相对最低分位），并给出点估计与 95%%CI；用于评估效应是否在亚组间一致及交互。",
        cohort, exp_out
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    fo <- .pub_figure_findings_summary(meta, "forest")
    if (nzchar(fo)) {
      lines <- c(lines, paste0("与主分析 Table 2 对照：", fo, "。"), "")
    }
    lines <- c(lines, "图上标注（按图面行摘录）：", "")
    fo_ann <- .pub_figure_forest_annotation_lines(find$forest %||% list())
    if (length(fo_ann)) {
      lines <- c(lines, fo_ann, "")
    } else {
      lines <- c(lines, "- 未收获：subgroup 结果表", "")
    }
    return(lines)
  }

  if (grepl("ML metrics|parallel metric", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为多模型平行线指标图%s：横轴依次为 roc_auc、accuracy、sens、spec、f_meas（与主库 performance 宽表同口径）；纵轴为估计值。分类指标用主库训练集 Youden 切点套用到三集，各模型折线连接同一模型的五项指标。",
        cohort
      ),
      "",
      "三面板：A=主库训练集；B=主库内部验证；C=次库外部验证（冻结主库模型，不重训）。",
      ""
    )
    return(lines)
  }

  if (grepl("\\bDCA\\b|decision curve", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为决策曲线分析（DCA）%s：横轴为阈值概率，纵轴为净获益；灰色为 treat-all / treat-none，彩色为各机器学习模型。高事件率结局时阈值轴延伸到患病率附近，避免只画 0–50%% 时曲线挤在顶部、图面大片空白。",
        cohort
      ),
      "",
      "三面板：A=主库训练集；B=主库内部验证；C=次库外部验证（冻结主库模型）。",
      ""
    )
    return(lines)
  }

  if (grepl("calibrat", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为多模型校准曲线%s：横轴为预测概率，纵轴为观测事件频率；对角线为完美校准参考。用于评估对 %s 的概率是否可校准，不替代 ROC 判别。",
        cohort, of_out
      ),
      "",
      "三面板：A=主库训练集；B=主库内部验证；C=次库外部验证（冻结主库模型）。",
      ""
    )
    return(lines)
  }

  if (grepl("ML ROC", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为多模型 ROC 曲线%s：横轴 1−特异度，纵轴灵敏度；对角线为无信息参考（AUC=0.5）。比较各机器学习模型对 %s 的判别。",
        cohort, of_out
      ),
      "",
      "三面板：A=主库训练集；B=主库内部验证；C=次库外部验证（冻结主库模型，不重训）。",
      ""
    )
    return(lines)
  }

  if (grepl("\\bROC\\b", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为多变量 ROC 曲线%s：用 %s 联合临床/VIF 协变量拟合预测概率，评估对 %s 的判别能力；对角线为无信息参考线（AUC=0.5）。注意：协变量集可与 Table 2 剪枝后的短名单不同，以完整 VIF/临床集为主。",
        cohort, if (nzchar(exp)) exp else "指标", of_out
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    rocs <- find$roc %||% list()
    # 去重同库
    seen <- character(0)
    if (length(rocs)) {
      lines <- c(lines, "图上标注：", "", "各库判别指标：")
      for (r in rocs) {
        db <- as.character(r$db %||% "")[1L]
        if (db %in% seen) next
        seen <- c(seen, db)
        ci <- if (is.finite(r$ci_lo %||% NA_real_) && is.finite(r$ci_hi %||% NA_real_)) {
          sprintf("（95%%CI %.3f–%.3f）", r$ci_lo, r$ci_hi)
        } else ""
        extra <- character(0)
        if (is.finite(r$youden %||% NA_real_)) {
          extra <- c(extra, sprintf("Youden 切点=%.4f", r$youden))
        }
        if (is.finite(r$sens %||% NA_real_) && is.finite(r$spec %||% NA_real_)) {
          extra <- c(extra, sprintf("灵敏度=%.3f、特异度=%.3f", r$sens, r$spec))
        }
        lines <- c(lines, sprintf(
          "- %s：AUC=%.3f%s%s",
          db, r$auc,
          ci,
          if (length(extra)) paste0("；", paste(extra, collapse = "，")) else ""
        ))
      }
      lines <- c(lines, "")
    }
    return(lines)
  }

  if (grepl("Boxplot|box\\s*plot", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为箱线图%s：按生存状态（或指定分组）比较 %s 的分布差异（中位数、四分位距与离群点）；总体/两两检验方法见课题 boxplot 配置与图注。",
        cohort, if (nzchar(exp)) exp else "指标"
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    return(lines)
  }

  if (grepl("SHAP|Feature\\s*Importance", s, ignore.case = TRUE)) {
    return(c(
      sprintf("本图展示特征对模型预测%s的相对贡献/重要性%s。", if (nzchar(out)) of_out else "", cohort),
      if (nzchar(panel_note)) c("", panel_note) else character(0),
      ""
    ))
  }

  if (grepl("Mediation|path diagram", s, ignore.case = TRUE)) {
    lines <- c(
      lines,
      sprintf(
        "本图为中介路径图%s：展示暴露（%s）→中介→结局（%s）的 path a / path b，以及底边 Direct Effect（c'）与 Proportion mediated；数字须与同目录 Table S9（Mediation analysis）同源同一位数。",
        cohort, if (nzchar(exp)) exp else "指标", of_out
      ),
      ""
    )
    if (nzchar(panel_note)) lines <- c(lines, panel_note, "")
    med_lines <- .pub_figure_mediation_annotation_lines(meta)
    if (length(med_lines)) {
      lines <- c(lines, "图上标注（摘自 Table S9 最佳/对齐中介行）：", "", med_lines, "")
    } else {
      lines <- c(
        lines,
        "图上标注：以路径图面 path a/b、Direct Effect、Proportion mediated 为准；结构化未收获时请核对 Table S9，禁止用 Table 2 分位 HR 代替中介效应。",
        ""
      )
    }
    return(lines)
  }

  # 兜底：展开旧一句话 + 上下文
  legacy <- .pub_figure_manuscript_sentence_legacy(stem, meta)
  c(legacy, "", if (nzchar(panel_note)) panel_note else NULL, "")
}

#' 从同目录 Tables 的 Mediation analysis xlsx 摘最佳中介行（供路径图 image_information）
.pub_figure_mediation_annotation_lines <- function(meta = list()) {
  tab_dir <- as.character(meta$tables_dir %||% "")[1L]
  if (!nzchar(tab_dir) || !dir.exists(tab_dir)) {
    # Figures/ 的上一级 Tables/
    fig_dir <- as.character(meta$figures_dir %||% meta$fig_dir %||% "")[1L]
    if (nzchar(fig_dir)) {
      cand <- file.path(dirname(fig_dir), "Tables")
      if (dir.exists(cand)) tab_dir <- cand
    }
  }
  if (!nzchar(tab_dir) || !dir.exists(tab_dir)) return(character(0))
  files <- list.files(
    tab_dir,
    pattern = "Mediation analysis.*\\.xlsx$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  if (!length(files)) return(character(0))
  out <- character(0)
  for (fp in files) {
    db <- "库"
    bn <- basename(fp)
    if (grepl("-eICU", bn, ignore.case = TRUE)) db <- "eICU"
    else if (grepl("-MIMIC", bn, ignore.case = TRUE)) db <- "MIMIC"
    else if (grepl("-NHANES", bn, ignore.case = TRUE)) db <- "NHANES"
    df <- tryCatch({
      if (requireNamespace("readxl", quietly = TRUE)) {
        as.data.frame(readxl::read_excel(fp, col_names = TRUE), stringsAsFactors = FALSE)
      } else if (requireNamespace("openxlsx", quietly = TRUE)) {
        openxlsx::read.xlsx(fp)
      } else {
        NULL
      }
    }, error = function(e) NULL)
    if (is.null(df) || !nrow(df)) next
    # 跳过标题行：找含 Mediator / Proportion 的表头
    hdr_i <- which(vapply(seq_len(min(5L, nrow(df))), function(i) {
      any(grepl("Mediator|Proportion", paste(df[i, ], collapse = " "), ignore.case = TRUE))
    }, logical(1)))
    if (length(hdr_i)) {
      names(df) <- as.character(unlist(df[hdr_i[1L], ], use.names = FALSE))
      df <- df[-seq_len(hdr_i[1L]), , drop = FALSE]
    }
    nm <- names(df)
    med_col <- nm[grepl("^Mediator$|中介", nm, ignore.case = TRUE)][1L]
    prop_col <- nm[grepl("Proportion|Prop_Med|中介比例", nm, ignore.case = TRUE)][1L]
    dir_col <- nm[grepl("Direct", nm, ignore.case = TRUE)][1L]
    pa_col <- nm[grepl("Path a", nm, ignore.case = TRUE)][1L]
    pb_col <- nm[grepl("Path b", nm, ignore.case = TRUE)][1L]
    if (is.na(med_col) || !nzchar(med_col)) next
    # 取第一行数据（表常已按 Prop_Med 排序；脚注行 Mediator 空）
    keep <- nzchar(trimws(as.character(df[[med_col]])))
    df <- df[keep, , drop = FALSE]
    if (!nrow(df)) next
    row1 <- df[1L, , drop = FALSE]
    bits <- c(sprintf("中介=%s", trimws(as.character(row1[[med_col]])[1L])))
    if (!is.na(pa_col)) bits <- c(bits, sprintf("path a=%s", trimws(as.character(row1[[pa_col]])[1L])))
    if (!is.na(pb_col)) bits <- c(bits, sprintf("path b=%s", trimws(as.character(row1[[pb_col]])[1L])))
    if (!is.na(dir_col)) bits <- c(bits, sprintf("Direct=%s", trimws(as.character(row1[[dir_col]])[1L])))
    if (!is.na(prop_col)) bits <- c(bits, sprintf("Proportion mediated=%s", trimws(as.character(row1[[prop_col]])[1L])))
    out <- c(out, sprintf("- %s：%s", db, paste(bits, collapse = "；")))
  }
  out
}

#' @keywords internal 旧版一句话（兜底）
.pub_figure_manuscript_sentence_legacy <- function(stem, meta = list()) {
  s <- as.character(stem %||% "")[1L]
  caption <- .pub_figure_caption_from_stem(s)
  exp <- as.character(meta$exposure %||% "")[1L]
  out_raw <- as.character(meta$outcome %||% "")[1L]
  out <- .pub_figure_plain_term(out_raw, "outcome")
  if (!nzchar(out)) out <- out_raw
  cohort <- .pub_figure_cohort_clause(meta)
  exp_out <- if (nzchar(exp) && nzchar(out)) sprintf("%s 与 %s", exp, out) else if (nzchar(exp)) exp else out
  find <- .pub_figure_findings_summary(meta, "other")
  if (nzchar(caption) && nzchar(find)) return(sprintf("%s：%s%s。", caption, find, cohort))
  if (nzchar(caption) && nzchar(exp_out)) return(sprintf("%s展示 %s 的关系%s。", caption, exp_out, cohort))
  if (nzchar(caption)) return(sprintf("%s%s。", caption, cohort))
  sprintf("本图展示分析相关图形结果%s。", cohort)
}

#' 正文可用描述（兼容旧调用：返回拼接后的长文本）
.pub_figure_manuscript_sentence <- function(stem, meta = list()) {
  body <- .pub_figure_detailed_body(stem, meta)
  body <- body[nzchar(trimws(body))]
  # 去掉 markdown 标题行，拼成可读长段
  body <- body[!grepl("^###\\s", body)]
  body <- sub("^[-*]\\s+", "", body)
  paste(body, collapse = " ")
}

pub_figure_write_image_md <- function(md_path, stem, meta = list(), tech = list(),
                                    raster_ok = TRUE) {
  stem <- as.character(stem %||% "")[1L]
  out_raw <- as.character(meta$outcome %||% "")[1L]
  # 原字段括注：meta$outcome_column（数据列名，如 DN）存在时优先用它，
  # 让「结局: Uterine fibroids（原字段 DN）」成立；否则沿用 out_raw 括注。
  out_col <- as.character(meta$outcome_column %||% "")[1L]
  out_show <- .pub_figure_plain_term(out_raw, "outcome")
  if (!nzchar(out_show)) out_show <- if (nzchar(out_raw)) out_raw else "未记录"
  out_note <- if (nzchar(out_col) && !identical(out_col, out_show)) out_col else out_raw
  grp_raw <- as.character(meta$grouping %||% "")[1L]
  grp_show <- .pub_figure_plain_term(grp_raw, "grouping")
  if (!nzchar(grp_show)) grp_show <- if (nzchar(grp_raw)) grp_raw else "未记录"
  dbs <- .pub_figure_db_labels(meta)
  if (!length(dbs)) dbs <- "未记录"

  n_line <- if (!is.null(meta$n_by_db) && length(meta$n_by_db)) {
    paste0(
      paste(sprintf("%s=%s", names(meta$n_by_db), meta$n_by_db), collapse = "; "),
      if (!is.null(meta$n_total)) sprintf("；合计 N=%s", meta$n_total) else ""
    )
  } else if (!is.null(meta$n_total)) {
    sprintf("N=%s", meta$n_total)
  } else {
    "未记录"
  }

  body <- .pub_figure_detailed_body(stem, meta)
  # 去掉末尾多余空行
  while (length(body) && !nzchar(trimws(body[[length(body)]]))) {
    body <- body[-length(body)]
  }

  lines <- c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    body,
    "",
    "## 分析上下文",
    paste0("- 暴露: ", meta$exposure %||% "未记录"),
    paste0("- 结局: ", out_show, if (nzchar(out_note) && !identical(out_show, out_note)) sprintf("（原字段 %s）", out_note) else ""),
    paste0("- 样本量: ", n_line),
    paste0("- Grouping: ", grp_show),
    paste0("- 数据库: ", paste(dbs, collapse = ", ")),
    paste0("- 是否拼图: ", if (isTRUE(meta$combined)) "是" else "否"),
    ""
  )
  if (!isTRUE(raster_ok)) {
    lines <- c(
      lines,
      "## 格式交付",
      "- PDF: 已生成",
      "- PNG/TIFF: 栅格化失败，未生成",
      ""
    )
  }
  writeLines(lines, md_path, useBytes = TRUE)
  invisible(md_path)
}

#' 仅重写 image_information/*.md（不重新栅格化；用于改文案后补刷）
pub_figure_refresh_image_information <- function(figures_dir, meta = list(), config = list()) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(character(0)))
  }
  meta$figures_dir <- figures_dir
  if (is.null(meta$tables_dir) || !nzchar(as.character(meta$tables_dir %||% "")[1L])) {
    meta$tables_dir <- file.path(dirname(figures_dir), "Tables")
  }
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  if (is.null(meta$findings) && !nzchar(as.character(meta$result_sentence %||% "")[1L])) {
    meta$findings <- tryCatch(
      pub_figure_harvest_findings(figures_dir, meta),
      error = function(e) list(association = list(), cutoffs = list(), attrition = list(),
                               roc = list(), maxstat = list())
    )
  }
  pdfs <- list.files(dirs[["pdf"]], pattern = "^Figure.*\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  md_files <- character(0)
  readme_rows <- list()
  for (fp in pdfs) {
    stem <- sub("\\.pdf$", "", basename(fp), ignore.case = TRUE)
    png_ok <- file.exists(file.path(dirs[["png"]], paste0(stem, ".png")))
    tiff_ok <- file.exists(file.path(dirs[["tiff"]], paste0(stem, ".tiff")))
    md_path <- file.path(dirs[["image_information"]], paste0(stem, ".md"))
    local_meta <- meta
    db_hit <- regmatches(
      stem,
      regexpr("-(MIMIC(?: IV)?|eICU|NHANES|CHARLS|ELSA|HRS)\\.", stem, ignore.case = TRUE)
    )
    if (length(db_hit) && nzchar(db_hit)) {
      db_one <- sub("^-|\\.$", "", db_hit)
      local_meta$combined <- FALSE
      local_meta$databases <- db_one
      if (!is.null(meta$n_by_db) && length(meta$n_by_db)) {
        ii <- match(tolower(db_one), tolower(names(meta$n_by_db)))
        if (!is.na(ii)) {
          local_meta$n_by_db <- meta$n_by_db[ii]
          names(local_meta$n_by_db) <- names(meta$n_by_db)[ii]
          local_meta$n_total <- as.integer(local_meta$n_by_db[[1L]])
        }
      }
    }
    pub_figure_write_image_md(
      md_path, stem, meta = local_meta,
      tech = list(),
      raster_ok = isTRUE(png_ok && tiff_ok)
    )
    md_files <- c(md_files, md_path)
    readme_rows[[length(readme_rows) + 1L]] <- data.frame(
      figure = stem,
      caption = .pub_figure_caption_from_stem(stem),
      combined = isTRUE(local_meta$combined),
      pdf = file.path("pdf", paste0(stem, ".pdf")),
      stringsAsFactors = FALSE
    )
  }
  if (length(readme_rows)) {
    tab <- do.call(rbind, readme_rows)
    lines <- c(
      "# Image information index",
      "",
      "| Figure | 图题 | Combined | PDF |",
      "|---|---|---|---|",
      sprintf(
        "| %s | %s | %s | `%s` |",
        tab$figure, tab$caption, ifelse(tab$combined, "yes", "no"), tab$pdf
      ),
      ""
    )
    writeLines(lines, file.path(dirs[["image_information"]], "README.md"), useBytes = TRUE)
  }
  invisible(md_files)
}

.pub_figure_python_exe <- function() {
  py <- Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = "")
  if (!nzchar(py) && exists(".dual_db_find_python", mode = "function")) {
    py <- .dual_db_find_python()
  }
  if (!nzchar(py) || grepl("WindowsApps", py, ignore.case = TRUE)) {
    py <- Sys.which("python")
    if (!nzchar(py) || grepl("WindowsApps", py, ignore.case = TRUE)) {
      py <- Sys.which("python3")
    }
  }
  if (!nzchar(py) || grepl("WindowsApps", py, ignore.case = TRUE)) {
    for (cand in c(
      "C:/ProgramData/anaconda3/python.exe",
      "C:/ProgramData/Anaconda3/python.exe",
      file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python312", "python.exe"),
      file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Python", "Python311", "python.exe")
    )) {
      if (nzchar(cand) && file.exists(cand)) { py <- cand; break }
    }
  }
  py
}

.pub_figure_python_script <- function(name, root_hint = NULL) {
  .eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  cands <- c(
    if (!is.null(root_hint)) file.path(root_hint, "python", name),
    if (nzchar(.eng)) file.path(.eng, "python", name),
    if (!is.na(.PUB_FIGURE_EXPORT_DIR)) file.path(dirname(.PUB_FIGURE_EXPORT_DIR), "python", name),
    file.path(getwd(), "python", name)
  )
  for (c in cands) if (!is.null(c) && file.exists(c)) return(c)
  NULL
}

.pub_figure_rasterize_one <- function(pdf_path, png_path, tiff_path, dpi, root_hint = NULL) {
  script <- .pub_figure_python_script("pub_figure_rasterize.py", root_hint = root_hint)
  if (is.null(script)) stop("找不到 python/pub_figure_rasterize.py", call. = FALSE)
  py <- .pub_figure_python_exe()
  if (!nzchar(py)) {
    stop("找不到 Python。可设环境变量 MEDICAL_BLOCKS_PYTHON。", call. = FALSE)
  }

  # ASCII 临时路径：避免【】在 Windows 命令行/编码下失败
  tmp <- tempfile("pub_ras_")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  pdf_s <- file.path(tmp, "in.pdf")
  png_s <- file.path(tmp, "out.png")
  tiff_s <- file.path(tmp, "out.tiff")
  if (!file.copy(pdf_path, pdf_s, overwrite = TRUE)) {
    stop("无法复制 PDF 到临时目录", call. = FALSE)
  }
  args <- c(
    script, "--pdf", pdf_s, "--png", png_s, "--tiff", tiff_s,
    "--dpi", as.character(as.integer(dpi)[1L])
  )
  err <- tempfile(fileext = ".txt")
  out <- tempfile(fileext = ".txt")
  on.exit({ unlink(err); unlink(out) }, add = TRUE)
  status <- system2(py, args = args, stdout = out, stderr = err)
  .read_txt <- function(path) {
    if (!file.exists(path) || !isTRUE(file.info(path)$size > 0)) return("")
    raw <- readBin(path, what = "raw", n = as.integer(file.info(path)$size))
    iconv(rawToChar(raw, multiple = FALSE), from = "", to = "UTF-8", sub = "?")
  }
  ok_tmp <- isTRUE(file.exists(png_s)) || isTRUE(file.exists(tiff_s))
  if (!ok_tmp) {
    msg <- .read_txt(err)
    if (!nzchar(msg)) msg <- .read_txt(out)
    if (!nzchar(msg)) msg <- paste0("rasterize exit=", status)
    stop(msg, call. = FALSE)
  }
  dir.create(dirname(png_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(tiff_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(png_s)) file.copy(png_s, png_path, overwrite = TRUE)
  if (file.exists(tiff_s)) file.copy(tiff_s, tiff_path, overwrite = TRUE)
  ## 铁律兜底：SMB/WSL 上 TIFF 直写常落成 0 字节（历史多次踩坑）。
  ## 只要 tiff 缺失或过小，就用已写好的 PNG 重导 LZW TIFF；失败只告警不阻断。
  if (!pub_figure_ensure_tiff_from_png(png_path, tiff_path, root_hint = root_hint)) {
    cli::cli_alert_warning(
      "TIFF 兜底重导失败：{basename(tiff_path)}（请手工 `pub_figure_ensure_tiff_from_png`）"
    )
  }
  invisible(TRUE)
}

#' TIFF 非零兜底：用 PNG 重导 LZW TIFF（幂等；已合格则直接返回 TRUE）
#'
#' 双路径：① python+PIL（正常 worker 环境）；② R 原生 png+tiff 包
#' （WSL 里 R 调 Windows python 会 interop 失败 status=1033，此时 ② 兜底）。
#' @param png_path,tiff_path 目标路径；tiff 缺失或 size<=800B 时重写
#' @return 逻辑 TRUE=最终 tiff 存在且非零
pub_figure_ensure_tiff_from_png <- function(png_path, tiff_path, root_hint = NULL) {
  png_path <- as.character(png_path %||% "")[1L]
  tiff_path <- as.character(tiff_path %||% "")[1L]
  if (!nzchar(tiff_path)) return(FALSE)
  t_ok <- function() {
    file.exists(tiff_path) && isTRUE(file.info(tiff_path)$size > 800L)
  }
  if (t_ok()) return(TRUE)
  if (!nzchar(png_path) || !file.exists(png_path) ||
      !isTRUE(file.info(png_path)$size > 800L)) return(FALSE)

  ## 路径 ①：python + PIL（ASCII 临时路径，避开【】中文名）
  .try_python <- function() {
    py <- .pub_figure_python_exe()
    if (!nzchar(py)) return(FALSE)
    tmp <- tempfile("pub_tiff_")
    dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
    png_s <- file.path(tmp, "in.png")
    tiff_s <- file.path(tmp, "out.tiff")
    if (!isTRUE(file.copy(png_path, png_s, overwrite = TRUE))) return(FALSE)
    script <- file.path(tmp, "png2tiff.py")
    writeLines(c(
      "import sys",
      "from PIL import Image",
      "im = Image.open(sys.argv[1])",
      "if im.mode not in ('RGB', 'L'): im = im.convert('RGB')",
      "im.save(sys.argv[2], format='TIFF', compression='tiff_lzw')",
      "print('ok')"
    ), script)
    status <- tryCatch(
      system2(py, args = c(script, png_s, tiff_s), stdout = FALSE, stderr = FALSE),
      error = function(e) 1L
    )
    if (identical(as.integer(status), 0L) && file.exists(tiff_s) &&
        isTRUE(file.info(tiff_s)$size > 800L) &&
        isTRUE(file.copy(tiff_s, tiff_path, overwrite = TRUE))) {
      return(t_ok())
    }
    FALSE
  }
  if (.try_python() && t_ok()) return(TRUE)

  ## 路径 ②：R 原生 png + tiff::writeTIFF（LZW）
  .try_r_native <- function() {
    if (!requireNamespace("png", quietly = TRUE) ||
        !requireNamespace("tiff", quietly = TRUE)) return(FALSE)
    tmp <- tempfile(fileext = ".tiff")
    on.exit(unlink(tmp, force = TRUE), add = TRUE)
    arr <- tryCatch(png::readPNG(png_path), error = function(e) NULL)
    if (is.null(arr)) return(FALSE)
    if (dim(arr)[3L] == 4L) {
      # RGBA → RGB（丢弃 alpha，避免 writeTIFF 通道数报错）
      arr <- arr[, , 1:3, drop = FALSE]
    }
    ok <- tryCatch({
      tiff::writeTIFF(arr, tmp, compression = "LZW")
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(ok)) return(FALSE)
    isTRUE(file.copy(tmp, tiff_path, overwrite = TRUE)) && t_ok()
  }
  if (.try_r_native() && t_ok()) return(TRUE)

  ## 路径 ③：magick（若装有）
  if (requireNamespace("magick", quietly = TRUE)) {
    ok <- tryCatch({
      img <- magick::image_read(png_path)
      img <- magick::image_convert(img, format = "tiff", compression = "LZW")
      magick::image_write(img, path = tiff_path, format = "tiff")
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok) && t_ok()) return(TRUE)
  }
  FALSE
}

#' 批量修复：扫描 Figures/tiff 下 0 字节或过小 TIFF，用同名 png 重导
#' @param figures_dir 汇总 Figures 目录（含 png/ 与 tiff/）
#' @return data.frame(stem, fixed)
pub_figure_repair_zero_tiffs <- function(figures_dir) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) return(data.frame(
    stem = character(0), fixed = logical(0)
  ))
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  tfs <- list.files(dirs[["tiff"]], pattern = "\\.tiff$", ignore.case = TRUE,
                    full.names = TRUE)
  bad <- tfs[file.info(tfs)$size <= 800L]
  out <- data.frame(stem = character(0), fixed = logical(0))
  for (tp in bad) {
    stem <- sub("\\.tiff$", "", basename(tp), ignore.case = TRUE)
    pp <- file.path(dirs[["png"]], paste0(stem, ".png"))
    ok <- pub_figure_ensure_tiff_from_png(pp, tp)
    out <- rbind(out, data.frame(stem = stem, fixed = ok))
    if (ok) {
      cli::cli_alert_success("TIFF 兜底重导: {stem}.tiff")
    } else {
      cli::cli_alert_warning("TIFF 兜底失败（无可用 PNG？）: {stem}.tiff")
    }
  }
  out
}

#' 两阶段图：按文件名推断结局（发病 AKI vs 28 天死亡）
.pub_figure_infer_outcome_from_stem <- function(stem, meta = list()) {
  s <- as.character(stem %||% "")[1L]
  if (!nzchar(s)) return(meta)
  if (grepl("Flowchart|attrition|Inclusion", s, ignore.case = TRUE)) {
    meta$outcome <- meta$outcome %||% "cohort attrition"
    return(meta)
  }
  if (grepl("28-day|28 day|Mortality|mortality|death", s, ignore.case = TRUE) &&
      !grepl("and AKI$", s, ignore.case = TRUE)) {
    meta$outcome <- meta$outcome %||% "28-day mortality"
    return(meta)
  }
  if (grepl("and AKI|RCS plot between .+ and AKI", s, ignore.case = TRUE)) {
    meta$outcome <- "AKI"
    return(meta)
  }
  if (grepl("Subgroup Forest", s, ignore.case = TRUE) &&
      grepl("Figure 3", s, ignore.case = TRUE)) {
    meta$outcome <- "AKI"
    return(meta)
  }
  if (grepl("Subgroup Forest", s, ignore.case = TRUE) &&
      grepl("Figure 6", s, ignore.case = TRUE)) {
    meta$outcome <- "28-day mortality"
    return(meta)
  }
  meta
}

#' 两张单页 PDF 合成一张带 A/B 的矢量图。
#' LASSO 默认上下（A 上 B 下）；双库纳排可 stack=FALSE 左右。
#' 从多页 PDF 抽出「内容最丰富」的一页（KM 等常有空白首页）。
#' @param src 源 PDF
#' @param dest 单页 PDF 目标；NULL 则写 tempfile
#' @return dest 路径；失败返回 NA_character_
pub_figure_pdf_best_content_page <- function(src, dest = NULL) {
  src <- as.character(src)[1L]
  if (!nzchar(src) || !file.exists(src)) return(NA_character_)
  if (is.null(dest) || !nzchar(dest)) {
    dest <- tempfile("pub_best_page_", fileext = ".pdf")
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  py <- .pub_figure_python_exe()
  if (!nzchar(py)) return(NA_character_)
  script <- tempfile("pub_best_page_", fileext = ".py")
  on.exit(unlink(script), add = TRUE)
  writeLines(c(
    "import fitz, sys",
    "d = fitz.open(sys.argv[1])",
    "best = max(range(len(d)), key=lambda i: len(d[i].get_drawings()) + 10 * len(d[i].get_images()))",
    "o = fitz.open(); o.insert_pdf(d, from_page=best, to_page=best)",
    "o.save(sys.argv[2]); o.close(); d.close()"
  ), script)
  status <- tryCatch(
    system2(py, args = c(script, src, dest), stdout = FALSE, stderr = FALSE),
    error = function(e) 1L
  )
  if (identical(as.integer(status), 0L) && file.exists(dest) &&
      isTRUE(file.info(dest)$size > 2000L)) {
    return(normalizePath(dest, winslash = "/", mustWork = FALSE))
  }
  NA_character_
}

#' 优先 PyMuPDF show_pdf_page，禁止 magick 栅格嵌 PDF。
#' @param pdf_a,pdf_b 源 PDF（各取第 1 页；可用 pub_figure_pdf_best_content_page 预处理）
#' @param dest 目标单页 PDF
#' @param labels 左上角 A/B 标注
#' @param stack TRUE=上下；FALSE=左右
#' @param density 仅矢量失败时的栅格回退 DPI
#' @param best_content_page TRUE 时先对两端做内容页抽取（KM 空白首页）
#' @param label_band 为 A/B 标签预留的顶部空白（PDF point）；0 保持旧版覆盖式标签
pub_figure_combine_ab_pdfs <- function(pdf_a, pdf_b, dest,
                                       labels = c("A", "B"),
                                       stack = TRUE,
                                       density = 160,
                                       best_content_page = FALSE,
                                       label_band = 0) {
  pdf_a <- as.character(pdf_a)[1L]
  pdf_b <- as.character(pdf_b)[1L]
  dest <- as.character(dest)[1L]
  if (!file.exists(pdf_a) || !file.exists(pdf_b) || !nzchar(dest)) return(FALSE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  labs <- as.character(labels %||% c("A", "B"))
  if (length(labs) < 2L) labs <- c("A", "B")
  if (isTRUE(best_content_page)) {
    a2 <- pub_figure_pdf_best_content_page(pdf_a)
    b2 <- pub_figure_pdf_best_content_page(pdf_b)
    if (!is.na(a2)) pdf_a <- a2
    if (!is.na(b2)) pdf_b <- b2
  }

  script <- .pub_figure_python_script("pub_figure_combine_ab.py")
  py <- .pub_figure_python_exe()
  if (!is.null(script) && nzchar(py)) {
    tmp <- tempfile("pub_ab_")
    dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
    a_s <- file.path(tmp, "a.pdf")
    b_s <- file.path(tmp, "b.pdf")
    out_s <- file.path(tmp, "out.pdf")
    ok_vec <- FALSE
    if (isTRUE(file.copy(pdf_a, a_s, overwrite = TRUE)) &&
        isTRUE(file.copy(pdf_b, b_s, overwrite = TRUE))) {
      # WSL/部分 Unix 上 system2 会按空格拆 argv，标签含空格须 shQuote
      args <- c(
        script, "--pdf-a", a_s, "--pdf-b", b_s, "--dest", out_s,
        "--label-a", shQuote(labs[[1L]]), "--label-b", shQuote(labs[[2L]]),
        "--label-band", as.character(max(0, as.numeric(label_band)[1L]))
      )
      if (!isTRUE(stack)) args <- c(args, "--side")
      else args <- c(args, "--stack")
      status <- tryCatch(
        system2(py, args = args, stdout = FALSE, stderr = FALSE),
        error = function(e) 1L
      )
      ok_vec <- identical(as.integer(status), 0L) &&
        file.exists(out_s) && isTRUE(file.info(out_s)$size > 800L)
    }
    if (isTRUE(ok_vec) && isTRUE(file.copy(out_s, dest, overwrite = TRUE))) {
      return(TRUE)
    }
  }

  ## 最后回退：栅格（仅无 PyMuPDF 时）；LASSO 正式产物应走上面的矢量路径
  if (requireNamespace("pdftools", quietly = TRUE) &&
      requireNamespace("grid", quietly = TRUE)) {
    ok <- tryCatch({
      ra <- pdftools::pdf_render_page(pdf_a, page = 1, dpi = density)
      rb <- pdftools::pdf_render_page(pdf_b, page = 1, dpi = density)
      if (isTRUE(stack)) {
        grDevices::pdf(dest, width = 7.2, height = 10.2)
        grid::grid.newpage()
        grid::pushViewport(grid::viewport(x = 0.5, y = 0.75, width = 0.96, height = 0.48))
        grid::grid.raster(ra, interpolate = TRUE)
        grid::grid.text(labs[[1L]], x = 0.03, y = 0.96, just = c("left", "top"),
                        gp = grid::gpar(fontsize = 16, fontface = "bold"))
        grid::popViewport()
        grid::pushViewport(grid::viewport(x = 0.5, y = 0.26, width = 0.96, height = 0.48))
        grid::grid.raster(rb, interpolate = TRUE)
        grid::grid.text(labs[[2L]], x = 0.03, y = 0.96, just = c("left", "top"),
                        gp = grid::gpar(fontsize = 16, fontface = "bold"))
        grid::popViewport()
      } else {
        grDevices::pdf(dest, width = 11, height = 5.6)
        grid::grid.newpage()
        grid::pushViewport(grid::viewport(x = 0.25, y = 0.48, width = 0.48, height = 0.92))
        grid::grid.raster(ra, interpolate = TRUE)
        grid::grid.text(labs[[1L]], x = 0.04, y = 0.96, just = c("left", "top"),
                        gp = grid::gpar(fontsize = 16, fontface = "bold"))
        grid::popViewport()
        grid::pushViewport(grid::viewport(x = 0.75, y = 0.48, width = 0.48, height = 0.92))
        grid::grid.raster(rb, interpolate = TRUE)
        grid::grid.text(labs[[2L]], x = 0.04, y = 0.96, just = c("left", "top"),
                        gp = grid::gpar(fontsize = 16, fontface = "bold"))
        grid::popViewport()
      }
      grDevices::dev.off()
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok) && file.exists(dest) && isTRUE(file.info(dest)$size > 8000L)) {
      return(TRUE)
    }
  }
  FALSE
}

#' 汇总 Figures 定稿导出
#' @param figures_dir 汇总图目录（顶层此时应为无库标签 PDF）
#' @param meta list: exposure, outcome, n_total, n_by_db, databases, combined, layout, grouping
#' @param config 完整或含 pub_figures 的 list
#' @param purge 导出前是否清空 pdf/png/tiff/image_information。
#'   全量导出用 TRUE；仅补导 Figure 1 等增量必须 FALSE，否则会误删已导出的 Fig2/3。
#' @param preserve_md TRUE=绝不删除/覆盖已有 image_information md（只补缺失）。
#'   多块共享同一汇总目录时（如 TST/NAFLD 的 external_bridge、omics_display 各自写详注），
#'   ensure_formats 这类"补格式"调用必须 TRUE，否则会把其它块的详细图注重写成占位文本。
export_pub_figures <- function(figures_dir, meta = list(), config = list(),
                               purge = TRUE, preserve_md = FALSE) {
  cfg <- .pub_figure_cfg(config)
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
  }
  meta$figures_dir <- figures_dir
  if (is.null(meta$tables_dir) || !nzchar(as.character(meta$tables_dir %||% "")[1L])) {
    meta$tables_dir <- file.path(dirname(figures_dir), "Tables")
  }
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  if (!isTRUE(cfg$enable)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
  }
  if (isTRUE(purge)) {
    # 外科式：只清「根目录有平铺稿=本次将重导」的图；无平铺稿的图（其它块的 7/8/9 等）
    # 四目录文件一律保留，防止单块重跑把别的块产物清光
    .flat <- list.files(figures_dir, pattern = "^Figure.*\\.(pdf|png)$",
                        ignore.case = TRUE)
    .flat <- .flat[file.info(file.path(figures_dir, .flat))$isdir %in% FALSE]
    .purge_stems <- unique(sub("\\.(pdf|png)$", "", .flat, ignore.case = TRUE))
    n_purge <- pub_figure_purge_format_subdirs(
      figures_dir, keep_md = isTRUE(preserve_md), only_stems = .purge_stems)
    if (n_purge > 0L && requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info("已清空旧发表图导出 {n_purge} 个: {.file {basename(figures_dir)}}")
    }
  }

  root_hint <- tryCatch(normalizePath(file.path(figures_dir, "../.."), winslash = "/", mustWork = FALSE), error = function(e) getwd())
  # 若能定位仓库根更好：从本文件推导
  if (!is.na(.PUB_FIGURE_EXPORT_DIR)) {
    root_hint <- dirname(.PUB_FIGURE_EXPORT_DIR)
  }

  # 从旁路 Tables / cutoff_*.csv 收获具体结果，写入正文一句话
  if (is.null(meta$findings) && !nzchar(as.character(meta$result_sentence %||% "")[1L])) {
    meta$findings <- tryCatch(
      pub_figure_harvest_findings(figures_dir, meta),
      error = function(e) list(association = list(), cutoffs = list())
    )
  }

  tops <- list.files(figures_dir, pattern = "\\.(pdf|png)$", full.names = TRUE, ignore.case = TRUE)
  tops <- tops[file.info(tops)$isdir %in% FALSE]
  exported <- character(0)
  missing_raster <- character(0)
  md_files <- character(0)
  readme_rows <- list()

  for (fp in tops) {
    bn <- basename(fp)
    # 只拦「未编号」缺失概览底稿；已按发表白名单编号成 Figure S<n> 的放行
    if (.pub_figure_is_missing_overview(bn) &&
        !grepl("^Figure[ _]?S?[0-9]", bn, ignore.case = TRUE)) {
      unlink(fp)
      next
    }
    if (!grepl("^Figure", bn, ignore.case = TRUE)) next
    stem <- sub("\\.(pdf|png)$", "", bn, ignore.case = TRUE)
    meta_i <- meta
    if (!isFALSE(meta$infer_outcome_from_stem)) {
      meta_i <- .pub_figure_infer_outcome_from_stem(stem, meta_i)
    }
    pdf_src <- fp
    if (grepl("\\.png$", bn, ignore.case = TRUE)) {
      # 仅有 png：仍复制到 png/，pdf/tiff 尽量跳过并记 missing
      file.copy(fp, file.path(dirs[["png"]], paste0(stem, ".png")), overwrite = TRUE)
      exported <- c(exported, stem)
      unlink(fp)
      next
    }
    dest_pdf <- file.path(dirs[["pdf"]], paste0(stem, ".pdf"))
    file.copy(pdf_src, dest_pdf, overwrite = TRUE)
    dest_png <- file.path(dirs[["png"]], paste0(stem, ".png"))
    dest_tiff <- file.path(dirs[["tiff"]], paste0(stem, ".tiff"))
    ok_r <- tryCatch({
      .pub_figure_rasterize_one(dest_pdf, dest_png, dest_tiff, cfg$dpi, root_hint = root_hint)
      TRUE
    }, error = function(e) {
      if (exists("cli_alert_warning", mode = "function") || requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("栅格化失败 [{stem}]: {e$message}")
      }
      FALSE
    })
    if (!isTRUE(ok_r)) missing_raster <- c(missing_raster, stem)

    if (isTRUE(cfg$write_image_information)) {
      md_path <- file.path(dirs[["image_information"]], paste0(stem, ".md"))
      # preserve_md：已有详注（其它块写的）不覆盖；只补缺失
      if (!isTRUE(preserve_md) || !file.exists(md_path)) {
        pub_figure_write_image_md(
          md_path, stem, meta = meta_i,
          tech = list(dpi = cfg$dpi, width = "未记录", height = "未记录"),
          raster_ok = isTRUE(ok_r)
        )
      }
      md_files <- c(md_files, md_path)
    }
    readme_rows[[length(readme_rows) + 1L]] <- data.frame(
      figure = stem,
      caption = .pub_figure_caption_from_stem(stem),
      combined = isTRUE(meta_i$combined),
      pdf = file.path("pdf", paste0(stem, ".pdf")),
      stringsAsFactors = FALSE
    )
    exported <- c(exported, stem)
    unlink(fp)
  }

  # 铁律：汇总 Figures 根目录不得残留发表图；一律进 pdf/png/tiff/image_information
  leftovers <- list.files(
    figures_dir, pattern = "^Figure.*\\.(pdf|png)$",
    full.names = TRUE, ignore.case = TRUE
  )
  leftovers <- leftovers[file.info(leftovers)$isdir %in% FALSE]
  if (length(leftovers) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_warning(
      "发表图仍残留在 Figures 根目录 {length(leftovers)} 个，已强制收进四目录"
    )
  }
  for (fp in leftovers) {
    bn <- basename(fp)
    stem <- sub("\\.(pdf|png)$", "", bn, ignore.case = TRUE)
    if (grepl("\\.png$", bn, ignore.case = TRUE)) {
      file.copy(fp, file.path(dirs[["png"]], paste0(stem, ".png")), overwrite = TRUE)
      unlink(fp)
      exported <- c(exported, stem)
      next
    }
    dest_pdf <- file.path(dirs[["pdf"]], paste0(stem, ".pdf"))
    file.copy(fp, dest_pdf, overwrite = TRUE)
    dest_png <- file.path(dirs[["png"]], paste0(stem, ".png"))
    dest_tiff <- file.path(dirs[["tiff"]], paste0(stem, ".tiff"))
    tryCatch(
      .pub_figure_rasterize_one(dest_pdf, dest_png, dest_tiff, cfg$dpi, root_hint = root_hint),
      error = function(e) NULL
    )
    if (isTRUE(cfg$write_image_information)) {
      md_path <- file.path(dirs[["image_information"]], paste0(stem, ".md"))
      if (!file.exists(md_path)) {
        pub_figure_write_image_md(
          md_path, stem, meta = meta,
          tech = list(dpi = cfg$dpi, width = "未记录", height = "未记录"),
          raster_ok = file.exists(dest_png)
        )
      }
    }
    unlink(fp)
    exported <- c(exported, stem)
  }

  # README 以 pdf/ 实存为准（增量导出也不会覆盖丢图）
  if (isTRUE(cfg$write_image_information)) {
    readme <- file.path(dirs[["image_information"]], "README.md")
    pdfs_now <- list.files(dirs[["pdf"]], pattern = "\\.pdf$", ignore.case = TRUE)
    if (length(pdfs_now)) {
      stems <- sub("\\.pdf$", "", pdfs_now, ignore.case = TRUE)
      lines <- c(
        "# Image information index",
        "",
        "| Figure | 图题 | PDF |",
        "|---|---|---|",
        sprintf(
          "| %s | %s | `%s` |",
          stems,
          vapply(stems, .pub_figure_caption_from_stem, character(1L)),
          file.path("pdf", paste0(stems, ".pdf"))
        ),
        ""
      )
    } else {
      lines <- c("# Image information index", "", "_No publication figures._", "")
    }
    writeLines(lines, readme, useBytes = TRUE)
  }

  if (length(exported) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "发表图已落入四目录（pdf/png/tiff/image_information）: {length(unique(exported))} 张"
    )
  }

  invisible(list(exported = unique(exported), missing_raster = unique(missing_raster), md = md_files))
}

#' 校验 Figures 是否已齐全 pdf/png/tiff（且根目录无残留发表 PDF）
#' @return list(ok, stems, missing_png, missing_tiff, flat_leftovers)
pub_figure_formats_status <- function(figures_dir) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  empty <- list(
    ok = FALSE, stems = character(0), missing_png = character(0),
    missing_tiff = character(0), flat_leftovers = character(0)
  )
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) return(empty)
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  pdfs <- list.files(dirs[["pdf"]], pattern = "^Figure.*\\.pdf$", ignore.case = TRUE)
  stems <- sub("\\.pdf$", "", pdfs, ignore.case = TRUE)
  flat <- list.files(
    figures_dir, pattern = "^Figure.*\\.(pdf|png)$",
    full.names = FALSE, ignore.case = TRUE
  )
  flat <- flat[file.info(file.path(figures_dir, flat))$isdir %in% FALSE]
  # Missing Value Overview 不算发表图残留
  flat <- flat[!vapply(flat, .pub_figure_is_missing_overview, logical(1L))]
  if (!length(stems) && !length(flat)) {
    return(list(
      ok = TRUE, stems = character(0), missing_png = character(0),
      missing_tiff = character(0), flat_leftovers = character(0)
    ))
  }
  # 根目录仍有发表图 → 未完成收纳
  if (length(flat)) {
    return(list(
      ok = FALSE, stems = stems, missing_png = character(0),
      missing_tiff = character(0), flat_leftovers = flat
    ))
  }
  miss_png <- character(0)
  miss_tiff <- character(0)
  # 0 字节 / 过小 TIFF（SMB 直写坑）视为缺失，触发 ensure_formats 兜底重导
  .size_ok <- function(p, min_size = 800L) {
    file.exists(p) && isTRUE(file.info(p)$size > min_size)
  }
  for (st in stems) {
    if (!.size_ok(file.path(dirs[["png"]], paste0(st, ".png")))) miss_png <- c(miss_png, st)
    if (!.size_ok(file.path(dirs[["tiff"]], paste0(st, ".tiff")))) miss_tiff <- c(miss_tiff, st)
  }
  list(
    ok = !length(miss_png) && !length(miss_tiff),
    stems = stems,
    missing_png = miss_png,
    missing_tiff = miss_tiff,
    flat_leftovers = character(0)
  )
}

#' 若四目录不齐，强制 export_pub_figures（可从 pdf/ 回填到根目录再导出）
pub_figure_ensure_formats <- function(figures_dir, meta = list(), config = list(),
                                      purge = NULL) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(list(ok = FALSE, action = "missing_dir")))
  }
  st <- pub_figure_formats_status(figures_dir)
  if (isTRUE(st$ok)) {
    return(invisible(list(ok = TRUE, action = "already_ok", status = st)))
  }
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  # 仅有 pdf/ 子目录、根目录无平铺 PDF：先拷回根目录供 export 收纳
  flat_now <- list.files(figures_dir, pattern = "^Figure.*\\.pdf$", ignore.case = TRUE)
  flat_now <- flat_now[file.info(file.path(figures_dir, flat_now))$isdir %in% FALSE]
  if (!length(flat_now)) {
    pdfs <- list.files(dirs[["pdf"]], pattern = "^Figure.*\\.pdf$", full.names = TRUE, ignore.case = TRUE)
    for (fp in pdfs) {
      file.copy(fp, file.path(figures_dir, basename(fp)), overwrite = TRUE)
    }
  }
  # 默认：有残留平铺或不完整时 purge 重建；调用方可显式指定
  if (is.null(purge)) purge <- TRUE
  if (!exists("export_pub_figures", mode = "function")) {
    return(invisible(list(ok = FALSE, action = "no_export_fn", status = st)))
  }
  # ensure_formats 只补格式，不改写其它块的 image_information 详注
  res <- tryCatch(
    export_pub_figures(figures_dir, meta = meta, config = config, purge = isTRUE(purge),
                       preserve_md = TRUE),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("pub_figure_ensure_formats 导出失败: {e$message}")
      }
      e
    }
  )
  st2 <- pub_figure_formats_status(figures_dir)
  if (!isTRUE(st2$ok) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_danger(
      "发表图四目录仍不完整: missing_png={length(st2$missing_png)}, missing_tiff={length(st2$missing_tiff)}, flat={length(st2$flat_leftovers)}"
    )
  } else if (isTRUE(st2$ok) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "发表图四目录校验通过: {length(st2$stems)} 张 × pdf/png/tiff"
    )
  }
  invisible(list(ok = isTRUE(st2$ok), action = "exported", status = st2, result = res))
}
