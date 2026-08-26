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
  vapply(dbs, function(d) {
    key <- tolower(gsub("[^A-Za-z0-9]+", "", d))
    if (key %in% c("nhanes", "eicu", "primary")) return("eICU")
    if (key %in% c("mimic", "secondary")) return("MIMIC")
    as.character(d)[1L]
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
    pint_col <- grep("interaction", names(df), ignore.case = TRUE)[1L]
    if (!length(var_col) || is.na(var_col) || !nzchar(var_col)) {
      out <- c(out, "- 未收获：subgroup 缺 Variable 列", "")
      next
    }
    for (i in seq_len(nrow(df))) {
      v <- as.character(df[[var_col]][i])
      if (!nzchar(v) || grepl("^-+$", v)) next
      est <- if (!is.na(est_col)) suppressWarnings(as.numeric(df[[est_col]][i])) else NA_real_
      lo <- if (!is.na(lo_col)) suppressWarnings(as.numeric(df[[lo_col]][i])) else NA_real_
      hi <- if (!is.na(hi_col)) suppressWarnings(as.numeric(df[[hi_col]][i])) else NA_real_
      bits <- character(0)
      if (is.finite(est)) {
        if (is.finite(lo) && is.finite(hi)) {
          bits <- c(bits, sprintf("%s (95%%CI %s–%s)",
                                  formatC(est, digits = 2, format = "f"),
                                  signif(lo, 4), signif(hi, 4)))
        } else {
          bits <- c(bits, as.character(signif(est, 4)))
        }
      }
      if (length(pint_col) && is.finite(pint_col)) {
        pv <- suppressWarnings(as.numeric(df[[pint_col]][i]))
        if (is.finite(pv)) bits <- c(bits, .pub_figure_fmt_p_label("P for interaction", pv))
      }
      if (length(bits)) out <- c(out, sprintf("- %s：%s", v, paste(bits, collapse = "；")))
    }
    out <- c(out, "")
  }
  out
}

#' 从 Figures 旁 Tables/ 与各库 step* cutoff_*.csv / checkpoint 收获可写入正文的结果要点
pub_figure_harvest_findings <- function(figures_dir, meta = list()) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  index_root <- dirname(figures_dir)
  tab_dir <- file.path(index_root, "Tables")
  out <- list(association = list(), cutoffs = list(), attrition = list(), roc = list(),
              maxstat = list())

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

    # 纳排逐步人数：Flowchart_attrition*.csv
    attr_csv <- list.files(
      tab_dir, pattern = "^Flowchart_attrition.*\\.csv$",
      full.names = TRUE, ignore.case = TRUE
    )
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
          db = db, step = step, n = n, path = fp
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
    file.path(ck_root, "eICU"), file.path(ck_root, "MIMIC"),
    file.path(ck_root, "nhanes"), file.path(ck_root, "mimic")
  )
  for (dd in unique(db_dirs)) {
    if (!dir.exists(dd)) next
    db_lab <- basename(dd)
    if (tolower(db_lab) %in% c("nhanes", "eicu")) db_lab <- "eICU"
    if (tolower(db_lab) %in% c("mimic")) db_lab <- "MIMIC"

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
    if (key %in% c("nhanes", "eicu", "primary")) return("eICU")
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
    out <- c(out, "")
  }
  out
}

#' 图面详细说明（多段；纳排图含逐步人数）
.pub_figure_detailed_body <- function(stem, meta = list()) {
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

  if (grepl("Flowchart|Inclusion|Exclusion|Attrition", s, ignore.case = TRUE)) {
    who <- if (nzchar(out)) sprintf("%s", out) else "本研究"
    lines <- c(
      lines,
      sprintf(
        "本图为纳排流程图%s，展示%s相关分析队列从原始提取到最终纳入的逐步筛选；每一步框内数字为该步保留人数。",
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

  # 兜底：展开旧一句话 + 上下文
  legacy <- .pub_figure_manuscript_sentence_legacy(stem, meta)
  c(legacy, "", if (nzchar(panel_note)) panel_note else NULL, "")
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
  out_show <- .pub_figure_plain_term(out_raw, "outcome")
  if (!nzchar(out_show)) out_show <- if (nzchar(out_raw)) out_raw else "未记录"
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
    paste0("- 结局: ", out_show, if (nzchar(out_raw) && !identical(out_show, out_raw)) sprintf("（原字段 %s）", out_raw) else ""),
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
    pub_figure_write_image_md(
      md_path, stem, meta = meta,
      tech = list(),
      raster_ok = isTRUE(png_ok && tiff_ok)
    )
    md_files <- c(md_files, md_path)
    readme_rows[[length(readme_rows) + 1L]] <- data.frame(
      figure = stem,
      caption = .pub_figure_caption_from_stem(stem),
      combined = isTRUE(meta$combined),
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

.pub_figure_rasterize_one <- function(pdf_path, png_path, tiff_path, dpi, root_hint = NULL) {
  script <- NULL
  cands <- c(
    if (!is.null(root_hint)) file.path(root_hint, "python", "pub_figure_rasterize.py"),
    if (!is.na(.PUB_FIGURE_EXPORT_DIR)) file.path(dirname(.PUB_FIGURE_EXPORT_DIR), "python", "pub_figure_rasterize.py"),
    file.path(getwd(), "python", "pub_figure_rasterize.py")
  )
  for (c in cands) if (!is.null(c) && file.exists(c)) { script <- c; break }
  if (is.null(script)) stop("找不到 python/pub_figure_rasterize.py", call. = FALSE)
  cmd <- paste(
    "python3",
    shQuote(script),
    "--pdf", shQuote(pdf_path),
    "--png", shQuote(png_path),
    "--tiff", shQuote(tiff_path),
    "--dpi", as.character(as.integer(dpi)[1L])
  )
  err <- tempfile()
  on.exit(unlink(err), add = TRUE)
  status <- system(paste(cmd, "2>", shQuote(err)))
  if (!is.null(status) && status != 0) {
    stop(paste(readLines(err, warn = FALSE), collapse = "\n"), call. = FALSE)
  }
  invisible(TRUE)
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
    meta$outcome <- "28-day mortality"
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

#' 汇总 Figures 定稿导出
#' @param figures_dir 汇总图目录（顶层此时应为无库标签 PDF）
#' @param meta list: exposure, outcome, n_total, n_by_db, databases, combined, layout, grouping
#' @param config 完整或含 pub_figures 的 list
export_pub_figures <- function(figures_dir, meta = list(), config = list()) {
  cfg <- .pub_figure_cfg(config)
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
  }
  dirs <- pub_figure_ensure_format_dirs(figures_dir)
  if (!isTRUE(cfg$enable)) {
    return(invisible(list(exported = character(), missing_raster = character(), md = character())))
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
    if (.pub_figure_is_missing_overview(bn)) {
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
      pub_figure_write_image_md(
        md_path, stem, meta = meta_i,
        tech = list(dpi = cfg$dpi, width = "未记录", height = "未记录"),
        raster_ok = isTRUE(ok_r)
      )
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

  # 空目录也写 README
  if (isTRUE(cfg$write_image_information)) {
    readme <- file.path(dirs[["image_information"]], "README.md")
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
    } else {
      lines <- c("# Image information index", "", "_No publication figures._", "")
    }
    writeLines(lines, readme, useBytes = TRUE)
  }

  invisible(list(exported = unique(exported), missing_raster = unique(missing_raster), md = md_files))
}
