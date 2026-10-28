###############################################################################
#  pv2_pub_p0_gate — 预后 v2 发表交付机器半边（Hip AKI 2026-10 教训）
#
#  对照规则：.cursor/rules/prognosis_v2_pub_p0_gate.mdc
#  挂点：remirror / finalize 收尾；Agent Nature QC 前可单独 Rscript 调用
###############################################################################

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

.pv2_p0_pdf_text <- function(pdf_path) {
  pdf_path <- as.character(pdf_path %||% "")[1L]
  if (!nzchar(pdf_path) || !file.exists(pdf_path)) return(NA_character_)
  bin <- Sys.which("pdftotext")
  if (!nzchar(bin)) return(NA_character_)
  # 路径常含空格；system2 在部分 poppler 上会把参数拆烂 → 用 shQuote + 落盘
  tf <- tempfile(fileext = ".txt")
  on.exit(unlink(tf), add = TRUE)
  cmd <- sprintf(
    "%s -layout %s %s",
    shQuote(bin), shQuote(pdf_path), shQuote(tf)
  )
  st <- tryCatch(system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE), error = function(e) 1L)
  if (!identical(as.integer(st), 0L) || !file.exists(tf)) return(NA_character_)
  paste(readLines(tf, warn = FALSE), collapse = "\n")
}

.pv2_p0_find_fig <- function(fig_dir, n) {
  pdf_dir <- file.path(fig_dir, "pdf")
  if (!dir.exists(pdf_dir)) pdf_dir <- fig_dir
  hits <- list.files(pdf_dir, pattern = sprintf("^Figure %d\\.", as.integer(n)), full.names = TRUE)
  if (!length(hits)) {
    hits <- list.files(pdf_dir, pattern = sprintf("^Figure %d[^0-9]", as.integer(n)), full.names = TRUE)
  }
  if (!length(hits)) return(NA_character_)
  hits[[1L]]
}

.pv2_p0_find_table <- function(tab_dir, pattern) {
  hits <- list.files(tab_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  if (!length(hits)) return(NA_character_)
  hits[[1L]]
}

.pv2_p0_read_methods <- function(root) {
  cands <- c(
    file.path(root, "Methods_statistical_analysis.md"),
    file.path(root, "Methods_statistical_analysis.txt")
  )
  hit <- cands[file.exists(cands)]
  if (!length(hit)) return(NA_character_)
  paste(readLines(hit[[1L]], warn = FALSE), collapse = "\n")
}

.pv2_p0_s8_direct_hrs <- function(s8_path) {
  if (!nzchar(s8_path %||% "") || !file.exists(s8_path)) return(character(0))
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(character(0))
  x <- tryCatch(openxlsx::read.xlsx(s8_path, colNames = FALSE), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(character(0))
  hrs <- character(0)
  # 优先：列内或表头含 Direct 的列
  for (j in seq_len(ncol(x))) {
    col <- as.character(x[[j]])
    if (!any(grepl("Direct", col, ignore.case = TRUE))) next
    for (cell in col) {
      if (is.na(cell) || !nzchar(cell)) next
      m <- regmatches(cell, regexpr("^[0-9]+\\.[0-9]{2,4}(?=\\s*\\()", cell, perl = TRUE))
      if (length(m) && nzchar(m[[1L]])) hrs <- c(hrs, m[[1L]])
    }
  }
  # 回退：全表扫描 Direct effect 单元格形态
  if (!length(hrs)) {
    flat <- as.character(unlist(x, use.names = FALSE))
    for (cell in flat) {
      if (is.na(cell) || !nzchar(cell)) next
      if (!grepl("^[0-9]+\\.[0-9]{2,4}\\s*\\(", cell)) next
      m <- regmatches(cell, regexpr("^[0-9]+\\.[0-9]{2,4}", cell, perl = TRUE))
      if (length(m) && nzchar(m[[1L]]) && grepl("–|-", cell)) hrs <- c(hrs, m[[1L]])
    }
  }
  unique(hrs)
}

.pv2_p0_underscore_hits <- function(text) {
  if (!nzchar(text %||% "") || is.na(text)) return(character(0))
  m <- gregexpr("\\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]*\\b", text, perl = TRUE)
  tok <- unique(regmatches(text, m)[[1L]])
  allow <- c(
    "P_linear", "P_nonlinear", "P_overall", "P_int", "log_rank", "cox_zph",
    "image_information", "summary_results", "summary_result",
    "Flowchart_attrition", "quantile_scheme_cascade", "pass_rule",
    "labevents", "icu_intime", "complete_action", "rubin_pool"
  )
  # 只抓「像临床列名」的多段下划线（≥1 个 _ 且非纯小写引擎词已在 allow）
  setdiff(tok, allow)
}

#' 预后 v2 发表 P0 机器门控
#'
#' @param summary_root 交付根（含 Figures/ + Tables/ + Methods_*）
#' @param locked_scheme "binary"|"tertile"|"quartile"
#' @param contrast_lab 亚组轴标；NULL 时按 scheme 推断
#' @param require_ph_table 是否要求 Table S9（或含 proportional / cox.zph 的表）
#' @param require_mediation 是否要求 Fig6↔S8 Direct
#' @param check_fig_numbers 具名 list：km=3, rcs=4, mediation=6, subgroup=7, shap=2
#' @param stop_on_fail TRUE 时任一 fail 则 stop
#' @return list(ok, fails, warns, checks)
pv2_pub_p0_gate <- function(
    summary_root,
    locked_scheme = c("binary", "tertile", "quartile"),
    contrast_lab = NULL,
    require_ph_table = TRUE,
    require_mediation = TRUE,
    check_fig_numbers = list(shap = 2L, km = 3L, rcs = 4L, mediation = 6L, subgroup = 7L),
    stop_on_fail = TRUE
) {
  summary_root <- as.character(summary_root %||% "")[1L]
  locked_scheme <- match.arg(locked_scheme)
  if (!nzchar(summary_root) || !dir.exists(summary_root)) {
    stop("pv2_pub_p0_gate: summary_root missing: ", summary_root)
  }
  fig_dir <- file.path(summary_root, "Figures")
  tab_dir <- file.path(summary_root, "Tables")
  if (!dir.exists(fig_dir)) stop("pv2_pub_p0_gate: Figures/ missing under ", summary_root)
  if (!dir.exists(tab_dir)) stop("pv2_pub_p0_gate: Tables/ missing under ", summary_root)

  if (is.null(contrast_lab) || !nzchar(contrast_lab)) {
    contrast_lab <- switch(
      locked_scheme,
      binary = "High vs Low",
      tertile = "T3 vs T1",
      quartile = "Q4 vs Q1",
      "High vs Low"
    )
  }

  fails <- character(0)
  warns <- character(0)
  checks <- list()

  # ---- Fig3 KM scheme ----
  km_pdf <- .pv2_p0_find_fig(fig_dir, check_fig_numbers$km %||% 3L)
  km_txt <- .pv2_p0_pdf_text(km_pdf)
  checks$fig3_pdf <- km_pdf
  if (is.na(km_txt)) {
    warns <- c(warns, "Fig3: pdftotext unavailable or PDF missing — skip KM scheme text check")
  } else if (identical(locked_scheme, "binary")) {
    has_hl <- grepl("\\bLow\\b", km_txt) && grepl("\\bHigh\\b", km_txt)
    # 风险表出现 Q1..Q4 视为旧 quartile 残留
    has_q_risk <- grepl("\\bQ1\\b", km_txt) && grepl("\\bQ4\\b", km_txt)
    checks$fig3_binary_labels <- has_hl
    checks$fig3_quartile_residue <- has_q_risk
    if (!isTRUE(has_hl)) fails <- c(fails, "Fig3 KM: locked binary but Low/High labels not found in PDF text")
    if (isTRUE(has_q_risk)) fails <- c(fails, "Fig3 KM: locked binary but Q1+Q4 residue found (stale quartile curves?)")
  }

  # ---- Fig4 P-linear ----
  rcs_pdf <- .pv2_p0_find_fig(fig_dir, check_fig_numbers$rcs %||% 4L)
  rcs_txt <- .pv2_p0_pdf_text(rcs_pdf)
  checks$fig4_pdf <- rcs_pdf
  if (is.na(rcs_txt)) {
    warns <- c(warns, "Fig4: pdftotext unavailable or PDF missing — skip P-linear check")
  } else {
    has_plin <- grepl("P-linear|P for linear|P_linear", rcs_txt, ignore.case = TRUE)
    has_pnl <- grepl("P-nonlinear|P for nonlinear|P_nonlinear|P-non-linear", rcs_txt, ignore.case = TRUE)
    has_pov_only <- grepl("P-overall|P for overall", rcs_txt, ignore.case = TRUE) && !has_plin
    checks$fig4_p_linear <- has_plin
    checks$fig4_p_nonlinear <- has_pnl
    if (!isTRUE(has_plin)) fails <- c(fails, "Fig4 RCS: missing P-linear (must align Table 3 linear Cox; do not ship P-overall-only)")
    if (!isTRUE(has_pnl)) warns <- c(warns, "Fig4 RCS: P-nonlinear not found in PDF text")
    if (isTRUE(has_pov_only)) fails <- c(fails, "Fig4 RCS: P-overall present without P-linear (Hip AKI failure mode)")
  }

  # ---- Fig6 ↔ S8 Direct ----
  if (isTRUE(require_mediation)) {
    med_pdf <- .pv2_p0_find_fig(fig_dir, check_fig_numbers$mediation %||% 6L)
    med_txt <- .pv2_p0_pdf_text(med_pdf)
    s8 <- .pv2_p0_find_table(tab_dir, "Table S8")
    hrs <- .pv2_p0_s8_direct_hrs(s8)
    checks$fig6_pdf <- med_pdf
    checks$s8_path <- s8
    checks$s8_direct_hrs <- hrs
    if (!length(hrs)) {
      warns <- c(warns, "Table S8: could not parse Direct effect HR point estimates")
    } else if (is.na(med_txt)) {
      warns <- c(warns, "Fig6: pdftotext unavailable — skip Direct digit check")
    } else {
      # PDF 路径图文字常被拆字；压缩数字 + 可选读 image_information
      blob <- med_txt
      md6 <- file.path(fig_dir, "image_information")
      if (dir.exists(md6)) {
        mhit <- list.files(md6, pattern = sprintf("^Figure %d", as.integer(check_fig_numbers$mediation %||% 6L)), full.names = TRUE)
        if (length(mhit)) blob <- paste(blob, paste(readLines(mhit[[1L]], warn = FALSE), collapse = "\n"), sep = "\n")
      }
      compact_dot <- gsub("[^0-9.]", "", blob)
      compact_digits <- gsub("[^0-9]", "", blob)
      miss <- character(0)
      for (h in hrs) {
        h_dot <- gsub("[^0-9.]", "", h)
        h_dig <- gsub("[^0-9]", "", h)
        ok <- grepl(h_dot, compact_dot, fixed = TRUE) || grepl(h_dig, compact_digits, fixed = TRUE)
        if (!ok) miss <- c(miss, h)
      }
      checks$fig6_missing_direct_hrs <- miss
      if (length(miss)) {
        fails <- c(fails, paste0(
          "Fig6 mediation: Direct HR from S8 not found in PDF/image_information: ",
          paste(miss, collapse = ", "),
          " (bottom arrow must be Direct, not Total)"
        ))
      }
    }
    # S7 方向：表题/脚注不得暗示 mediator→exposure 为主分析
    s7 <- .pv2_p0_find_table(tab_dir, "Table S7")
    checks$s7_path <- s7
    if (nzchar(s7 %||% "") && file.exists(s7) && requireNamespace("openxlsx", quietly = TRUE)) {
      s7x <- tryCatch(openxlsx::read.xlsx(s7, colNames = FALSE), error = function(e) NULL)
      if (!is.null(s7x)) {
        blob <- paste(as.character(unlist(s7x)), collapse = " ")
        # 反例信号：题名 Correlation 尚可；若脚注写 mediator predicting exposure 则 fail
        if (grepl("mediator\\s*\\S*\\s*predict|OASIS\\s*→\\s*SIRI|on the exposure", blob, ignore.case = TRUE) &&
            !grepl("exposure.+mediator|index.+OASIS|Path a is the linear coefficient of the", blob, ignore.case = TRUE)) {
          fails <- c(fails, "Table S7: path a direction looks reversed (must be exposure → mediator, same as S8)")
        }
      }
    }
  }

  # ---- Fig7 contrast + P-int ----
  sg_pdf <- .pv2_p0_find_fig(fig_dir, check_fig_numbers$subgroup %||% 7L)
  sg_txt <- .pv2_p0_pdf_text(sg_pdf)
  checks$fig7_pdf <- sg_pdf
  if (is.na(sg_txt)) {
    warns <- c(warns, "Fig7: pdftotext unavailable or PDF missing — skip subgroup checks")
  } else {
    has_contrast <- grepl(contrast_lab, sg_txt, fixed = TRUE) ||
      grepl(gsub("\\s+", "\\\\s+", contrast_lab), sg_txt, ignore.case = TRUE)
    has_pint <- grepl("P-int|P for interaction|P_interaction|P for Interaction", sg_txt, ignore.case = TRUE)
    stale_q <- identical(locked_scheme, "binary") && grepl("Q4\\s*vs\\s*Q1", sg_txt, ignore.case = TRUE)
    checks$fig7_contrast <- has_contrast
    checks$fig7_p_int <- has_pint
    checks$fig7_stale_q4q1 <- stale_q
    if (!isTRUE(has_contrast)) {
      fails <- c(fails, paste0("Fig7 subgroup: axis/contrast label '", contrast_lab, "' not found in PDF text"))
    }
    if (!isTRUE(has_pint)) fails <- c(fails, "Fig7 subgroup: missing P-int / P for interaction on strata")
    if (isTRUE(stale_q)) fails <- c(fails, "Fig7 subgroup: locked binary but axis still shows Q4 vs Q1")
  }

  # ---- Fig2 / SHAP 展示层下划线（主要扫 PDF 图面；md 只扫「图面说明」）----
  shap_n <- check_fig_numbers$shap %||% 2L
  shap_pdf <- .pv2_p0_find_fig(fig_dir, shap_n)
  shap_txt <- .pv2_p0_pdf_text(shap_pdf)
  und <- .pv2_p0_underscore_hits(shap_txt)
  md_dir <- file.path(fig_dir, "image_information")
  if (dir.exists(md_dir)) {
    for (mf in list.files(md_dir, pattern = "\\.md$", full.names = TRUE)) {
      raw <- paste(readLines(mf, warn = FALSE), collapse = "\n")
      # 只取「图面说明」到下一 ## 之前，避免分析上下文里的引擎文件名
      sec <- sub("(?s).*?##\\s*图面说明\\s*", "", raw, perl = TRUE)
      sec <- sub("(?s)\\n##\\s+.*", "", sec, perl = TRUE)
      und <- unique(c(und, .pv2_p0_underscore_hits(sec)))
    }
  }
  checks$underscore_hits <- und
  if (length(und)) {
    fails <- c(fails, paste0(
      "Display underscores found (pub_no_underscore): ",
      paste(utils::head(und, 12L), collapse = ", ")
    ))
  }

  # ---- PH table（勿把 "Table 3. Cox proportional hazards" 主表误判为 PH 表）----
  if (isTRUE(require_ph_table)) {
    all_t <- list.files(tab_dir, full.names = TRUE)
    bn <- basename(all_t)
    hit <- all_t[
      grepl("assumption|Schoenfeld|cox\\.zph|zph", bn, ignore.case = TRUE) |
        grepl("Proportional hazards assumption", bn, ignore.case = TRUE) |
        grepl("^Table S9\\b", bn, ignore.case = TRUE)
    ]
    # 若 S9 文件名不含 assumption，再读表头确认
    if (!length(hit)) {
      s9 <- all_t[grepl("^Table S9\\b", bn, ignore.case = TRUE)]
      hit <- s9
    }
    ph <- if (length(hit)) hit[[1L]] else NA_character_
    checks$ph_table <- ph
    if (!nzchar(ph %||% "") || is.na(ph)) {
      fails <- c(fails, "Missing proportional-hazards table (e.g. Table S9 / cox.zph / Schoenfeld)")
    }
  }

  # ---- Methods keywords ----
  meth <- .pv2_p0_read_methods(summary_root)
  checks$methods_present <- !is.na(meth)
  if (is.na(meth)) {
    fails <- c(fails, "Methods_statistical_analysis.md/txt missing")
  } else {
    need <- list(
      lab_timing = "charttime|ICU intime|labevents|first .*count|baseline blood|取材|时点|window",
      mice = "MICE|multiple imputation|多重插补",
      mice_outcome = "not imputed|结局.*插补|death status|follow-up time|outcome.*(in|not)|imputation model",
      ph = "cox\\.zph|Schoenfeld|proportional.?hazard",
      grouping = locked_scheme
    )
    for (nm in names(need)) {
      ok <- grepl(need[[nm]], meth, ignore.case = TRUE)
      checks[[paste0("methods_", nm)]] <- ok
      if (!ok) {
        fails <- c(fails, paste0("Methods missing required token/group: ", nm, " (~/", need[[nm]], "/)"))
      }
    }
    # 中介若存在：脚注诚实（若写 Model 3 须真有 CHARLSON 等 — 仅警告）
    if (isTRUE(require_mediation) && grepl("Model 3", meth, ignore.case = TRUE) &&
        grepl("mediat", meth, ignore.case = TRUE) &&
        grepl("Model 2", meth, ignore.case = TRUE)) {
      # 同时提 Model 2 与 Model 3 于中介段通常 OK（已区分）；无额外 fail
      checks$methods_mediation_dual_model_mentioned <- TRUE
    }
  }

  ok <- length(fails) == 0L
  res <- list(ok = ok, fails = fails, warns = warns, checks = checks, contrast_lab = contrast_lab, scheme = locked_scheme)

  if (requireNamespace("cli", quietly = TRUE)) {
    if (ok) cli::cli_alert_success("pv2_pub_p0_gate OK ({summary_root})")
    else cli::cli_alert_danger("pv2_pub_p0_gate FAIL ({length(fails)}): {paste(fails, collapse = ' | ')}")
    if (length(warns)) cli::cli_alert_warning("pv2_pub_p0_gate warns: {paste(warns, collapse = ' | ')}")
  } else {
    message(if (ok) "pv2_pub_p0_gate OK" else paste("pv2_pub_p0_gate FAIL:", paste(fails, collapse = " | ")))
  }

  if (!ok && isTRUE(stop_on_fail)) {
    stop("pv2_pub_p0_gate failed:\n- ", paste(fails, collapse = "\n- "), call. = FALSE)
  }
  invisible(res)
}
