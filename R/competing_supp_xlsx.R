###############################################################################
#  competing_supp_xlsx.R — 案例式多级表头补充表写出（全项目可复用）
#  - 变量名禁止下划线；参考组/未进模变量保留空白格
#  - Model 表按完整变量骨架输出（暴露水平 + 人口学 + 临床）
###############################################################################

.competing_xlsx_style_header <- function() {
  openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 11, textDecoration = "bold",
    halign = "center", valign = "center", wrapText = TRUE,
    border = "TopBottom", borderStyle = c("medium", "thin")
  )
}
.competing_xlsx_style_body <- function() {
  openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 11,
    halign = "center", valign = "center"
  )
}
.competing_xlsx_style_left <- function(bold = FALSE) {
  openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 11,
    halign = "left", valign = "center",
    textDecoration = if (bold) "bold" else NULL
  )
}
.competing_xlsx_style_section <- function() {
  openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "left", valign = "center"
  )
}

.competing_supp_fmt_p <- function(p) {
  if (length(p) != 1L) p <- p[1L]
  if (is.null(p) || !is.finite(suppressWarnings(as.numeric(p)))) return("")
  p <- as.numeric(p)
  if (p < 0.001) return("<0.001")
  format(signif(p, 3), scientific = FALSE)
}

.competing_supp_fmt_hr_ci <- function(hr, lo, hi) {
  hr <- suppressWarnings(as.numeric(hr)); lo <- suppressWarnings(as.numeric(lo)); hi <- suppressWarnings(as.numeric(hi))
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) return("")
  if (abs(hr) > 1e4 || abs(hi) > 1e4) return("")
  sprintf("%.2f(%.2f-%.2f)", hr, lo, hi)
}

.competing_xlsx_fix_drawings <- function(path) {
  py <- paste0(
    "import zipfile,re,os,tempfile,shutil\n",
    "p=r'''", path, "'''\n",
    "td=tempfile.mkdtemp()\n",
    "try:\n",
    "  with zipfile.ZipFile(p) as z: z.extractall(td)\n",
    "  for root,dirs,files in os.walk(td):\n",
    "    for f in files:\n",
    "      fp=os.path.join(root,f)\n",
    "      if f.endswith('.rels') or f=='[Content_Types].xml':\n",
    "        t=open(fp,encoding='utf-8',errors='ignore').read()\n",
    "        t2=re.sub(r'<Override[^>]*[Dd]rawing[^/]*/>','',t)\n",
    "        t2=re.sub(r'<Relationship[^>]*[Dd]rawing[^/]*/>','',t2)\n",
    "        t2=re.sub(r'<Relationship[^>]*vmlDrawing[^/]*/>','',t2)\n",
    "        if t2!=t: open(fp,'w',encoding='utf-8').write(t2)\n",
    "  ddir=os.path.join(td,'xl','drawings')\n",
    "  if os.path.isdir(ddir): shutil.rmtree(ddir, ignore_errors=True)\n",
    "  out=p+'.tmpfix.xlsx'\n",
    "  with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:\n",
    "    for root,dirs,files in os.walk(td):\n",
    "      for f in files:\n",
    "        fp=os.path.join(root,f); arc=os.path.relpath(fp,td).replace('\\\\','/')\n",
    "        z.write(fp, arc)\n",
    "  os.replace(out,p)\n",
    "finally:\n",
    "  shutil.rmtree(td, ignore_errors=True)\n"
  )
  tryCatch(system2("python3", input = py, stdout = TRUE, stderr = TRUE), error = function(e) NULL)
  invisible(path)
}

.competing_supp_norm_lab <- function(x) {
  tolower(gsub("[^A-Za-z0-9]+", "", as.character(x)))
}

.competing_supp_match_outcome <- function(df, label) {
  if (is.null(df) || !nrow(df) || !"Outcome" %in% names(df)) return(df[0, , drop = FALSE])
  lab <- .competing_supp_norm_lab(label)
  oc <- .competing_supp_norm_lab(df$Outcome)
  hit <- oc == lab
  if (!any(hit) && grepl("mortal|death|overall", lab)) {
    hit <- grepl("mortal|death|overall", oc)
  }
  if (!any(hit) && grepl("aki|diabetes|whf|primary", lab)) {
    hit <- grepl("aki|diabetes|whf|primary", oc)
  }
  df[hit, , drop = FALSE]
}

.competing_supp_exposure_level <- function(term) {
  tm <- as.character(term)
  m <- regexec("(Q[1-4]|T[0-9]+|Decreasing|Stable|Increasing)", tm, perl = TRUE)
  r <- regmatches(tm, m)
  vapply(r, function(z) if (length(z) >= 2L) z[[2L]] else NA_character_, character(1))
}

.competing_supp_is_exposure_term <- function(term) {
  grepl("quartile|trajectory|Q[1-4]|T[0-9]|Decreasing|Stable|Increasing",
        as.character(term), ignore.case = TRUE)
}

.competing_supp_ref_level <- function(levels_u) {
  levels_u <- as.character(levels_u)
  levels_u <- levels_u[nzchar(levels_u) & !is.na(levels_u)]
  if (any(grepl("^Q[1-4]$", levels_u))) return("Q1")
  if (any(grepl("^T[0-9]+$", levels_u))) return("T1")
  if (any(grepl("Decreasing|Stable|Increasing", levels_u))) return("Decreasing")
  if (length(levels_u)) levels_u[[1L]] else "Q1"
}

.competing_supp_term_matches_skeleton <- function(term, skeleton_var) {
  tm <- as.character(term)[1L]
  sv <- as.character(skeleton_var)[1L]
  if (!nzchar(tm) || !nzchar(sv)) return(FALSE)
  key <- .competing_supp_term_key(tm)
  if (identical(.competing_supp_norm_lab(key), .competing_supp_norm_lab(sv))) return(TRUE)
  # 禁止 CK 匹配 CKDYes：要求去掉 Yes/No/Race 后缀后的基名与骨架等长匹配
  tm_stripped <- sub("(Male|Female|Yes|No|True|False)$", "", tm, ignore.case = TRUE)
  tm_stripped <- sub("(White|Black|Asian|Hispanic|Other|Unknown)$", "", tm_stripped, ignore.case = TRUE)
  identical(.competing_supp_norm_lab(tm_stripped), .competing_supp_norm_lab(sv))
}

.competing_supp_term_key <- function(term) {
  # 用于把系数名映射回骨架变量：GenderMale -> Gender；RaceWhite -> Race；CKDYes -> CKD
  tm <- as.character(term)
  if (.competing_supp_is_exposure_term(tm)) {
    lv <- .competing_supp_exposure_level(tm)
    return(if (!is.na(lv)) lv else tm)
  }
  base <- sub("(Male|Female|Yes|No|True|False)$", "", tm, ignore.case = TRUE)
  base <- sub("(White|Black|Asian|Hispanic|Other|Unknown)$", "", base, ignore.case = TRUE)
  base <- gsub("_", " ", base, fixed = TRUE)
  trimws(base)
}

#' 补充材料1/5：分层 × 暴露 × 双结局
.competing_write_supp_subgroup_xlsx <- function(path, df, db = "MIMIC",
                                                exposure_lab = "Quartile",
                                                outcome1 = "AKI",
                                                outcome2 = "Overall mortality",
                                                followup_label = "28-day") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  outcome1 <- .competing_supp_display_label(outcome1)
  outcome2 <- .competing_supp_display_label(outcome2)
  exposure_lab <- .competing_supp_display_label(exposure_lab)
  followup_label <- as.character(followup_label %||% "28-day")[1L]
  if (!nzchar(followup_label)) followup_label <- "28-day"

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1", gridLines = FALSE)
  openxlsx::writeData(wb, "Sheet1", data.frame(
    matrix(c(
      "Subgroup", "n (%)", exposure_lab, outcome1, "", "", outcome2, "", "",
      "", "", "", followup_label, "", "", followup_label, "", "",
      "", "", "", "HR(95%CI)", "P value", "P for interaction",
      "HR(95%CI)", "P value", "P for interaction"
    ), nrow = 3, byrow = TRUE), stringsAsFactors = FALSE
  ), colNames = FALSE, startRow = 1)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1:3, cols = 1)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1:3, cols = 2)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1:3, cols = 3)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1, cols = 4:6)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1, cols = 7:9)
  openxlsx::mergeCells(wb, "Sheet1", rows = 2, cols = 4:6)
  openxlsx::mergeCells(wb, "Sheet1", rows = 2, cols = 7:9)

  mat <- NULL
  if (!is.null(df) && nrow(df) && "Subgroup" %in% names(df)) {
    out_rows <- list()
    for (sg in unique(df$Subgroup)) {
      sub <- df[df$Subgroup == sg, , drop = FALSE]
      pint_d <- if ("P_int_Primary" %in% names(sub)) as.numeric(sub$P_int_Primary[1]) else NA_real_
      pint_m <- if ("P_int_Mortality" %in% names(sub)) as.numeric(sub$P_int_Mortality[1]) else NA_real_
      out_rows[[length(out_rows) + 1L]] <- c(
        .competing_supp_display_label(sg), "", "", "", "",
        .competing_supp_fmt_p(pint_d), "", "", .competing_supp_fmt_p(pint_m)
      )
      for (lv in unique(sub$Level)) {
        s2 <- sub[sub$Level == lv, , drop = FALSE]
        nlab <- if ("n_lab" %in% names(s2)) as.character(s2$n_lab[1]) else ""
        terms <- unique(as.character(s2$Quartile))
        term_lv <- .competing_supp_exposure_level(terms)
        term_lv[is.na(term_lv) | !nzchar(term_lv)] <- .competing_supp_display_label(terms[is.na(term_lv) | !nzchar(term_lv)])
        ord_key <- c("Q1", "T1", "Decreasing", "Q2", "T2", "Stable", "Q3", "T3", "Increasing", "Q4", "T4")
        ord <- order(match(term_lv, ord_key, nomatch = 99L))
        terms <- terms[ord]; term_lv <- term_lv[ord]
        first <- TRUE
        for (ii in seq_along(terms)) {
          tm <- terms[[ii]]; tm_lab <- term_lv[[ii]]
          rd <- .competing_supp_match_outcome(s2[s2$Quartile == tm, , drop = FALSE], outcome1)
          rm <- .competing_supp_match_outcome(s2[s2$Quartile == tm, , drop = FALSE], outcome2)
          is_ref <- grepl("^Q1$|^T1$|^Decreasing$", tm_lab)
          hr_d <- if (!is_ref && nrow(rd)) as.character(rd$HR_CI[1]) else ""
          p_raw_d <- if (!is_ref && nrow(rd)) as.character(rd$P[1]) else ""
          p_d <- if (identical(toupper(trimws(p_raw_d)), "NE") || identical(toupper(trimws(hr_d)), "NE")) {
            "NE"
          } else if (nzchar(hr_d)) {
            .competing_supp_fmt_p(p_raw_d)
          } else ""
          hr_m <- if (!is_ref && nrow(rm)) as.character(rm$HR_CI[1]) else ""
          p_raw_m <- if (!is_ref && nrow(rm)) as.character(rm$P[1]) else ""
          p_m <- if (identical(toupper(trimws(p_raw_m)), "NE") || identical(toupper(trimws(hr_m)), "NE")) {
            "NE"
          } else if (nzchar(hr_m)) {
            .competing_supp_fmt_p(p_raw_m)
          } else ""
          if (grepl("Inf|^[0-9]{5,}", hr_d) && !identical(toupper(hr_d), "NE")) {
            hr_d <- "NE"; p_d <- "NE"
          }
          if (grepl("Inf|^[0-9]{5,}", hr_m) && !identical(toupper(hr_m), "NE")) {
            hr_m <- "NE"; p_m <- "NE"
          }
          out_rows[[length(out_rows) + 1L]] <- c(
            if (first) .competing_supp_display_label(lv) else "",
            if (first) nlab else "",
            tm_lab, hr_d, p_d, "", hr_m, p_m, ""
          )
          first <- FALSE
        }
      }
    }
    mat <- do.call(rbind, out_rows)
    openxlsx::writeData(wb, "Sheet1", as.data.frame(mat, stringsAsFactors = FALSE),
                        startRow = 4, colNames = FALSE)
  } else {
    openxlsx::writeData(wb, "Sheet1", data.frame(note = "no data"), startRow = 4, colNames = FALSE)
  }

  hs <- .competing_xlsx_style_header()
  openxlsx::addStyle(wb, "Sheet1", hs, rows = 1:3, cols = 1:9, gridExpand = TRUE, stack = TRUE)
  n_body <- if (!is.null(mat)) nrow(mat) else 0L
  if (n_body > 0L) {
    openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_body(),
                       rows = 4:(3 + n_body), cols = 1:9, gridExpand = TRUE, stack = TRUE)
    openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_left(),
                       rows = 4:(3 + n_body), cols = 1, gridExpand = TRUE, stack = TRUE)
  }
  openxlsx::setColWidths(wb, "Sheet1", cols = 1:9, widths = c(18, 12, 12, 18, 10, 14, 18, 10, 14))
  openxlsx::setRowHeights(wb, "Sheet1", rows = 1:3, heights = 18)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  .competing_xlsx_fix_drawings(path)
  invisible(path)
}

#' 单段 Model 表主体行（含完整变量骨架）
.competing_supp_model_section_rows <- function(tab, method, model_ids, horizons,
                                              skeleton_vars = NULL,
                                              section_title = NULL,
                                              extra_note = NULL) {
  nc <- 1L + 6L * length(model_ids)
  rows_out <- list()
  if (!is.null(section_title) && nzchar(section_title)) {
    rows_out[[length(rows_out) + 1L]] <- c(section_title, rep("", nc - 1L))
  }
  if (!is.null(extra_note) && nzchar(extra_note)) {
    rows_out[[length(rows_out) + 1L]] <- c(extra_note, rep("", nc - 1L))
  }

  if (is.null(tab) || !nrow(tab) || !"HR" %in% names(tab)) {
    return(rows_out)
  }
  d <- tab
  if ("method" %in% names(d)) d <- d[d$method == method, , drop = FALSE]
  if (!nrow(d)) return(rows_out)
  if ("model_id" %in% names(d)) {
    # 兼容主文 Model4–6 = standard
    if (all(model_ids %in% 1:3) && identical(method, "standard") &&
        all(as.integer(d$model_id) %in% 4:6)) {
      d$model_id <- as.integer(d$model_id) - 3L
    }
    d <- d[as.integer(d$model_id) %in% as.integer(model_ids), , drop = FALSE]
  }
  if (!nrow(d)) return(rows_out)

  d$level <- .competing_supp_exposure_level(d$term)
  is_exp <- .competing_supp_is_exposure_term(d$term)
  levels_u <- unique(d$level[is_exp & !is.na(d$level) & nzchar(d$level)])
  ref <- .competing_supp_ref_level(levels_u)
  ord_key <- c("Q1", "T1", "Decreasing", "Q2", "T2", "Stable", "Q3", "T3", "Increasing", "Q4", "T4")
  levels_u <- unique(c(ref, setdiff(as.character(levels_u), ref)))
  levels_u <- levels_u[order(match(levels_u, ord_key, nomatch = 99L))]

  # 协变量骨架：优先外部传入；否则从系数表反推基名
  if (is.null(skeleton_vars) || !length(skeleton_vars)) {
    skeleton_vars <- unique(vapply(d$term[!is_exp], .competing_supp_term_key, character(1)))
    skeleton_vars <- skeleton_vars[nzchar(skeleton_vars)]
  }
  skeleton_vars <- unique(as.character(skeleton_vars))
  skeleton_vars <- skeleton_vars[nzchar(skeleton_vars)]

  fill_row <- function(hit_fn, label, skip_ref = FALSE) {
    row <- rep("", nc)
    row[1] <- .competing_supp_display_label(label)
    for (i in seq_along(model_ids)) {
      mid <- as.integer(model_ids[i])
      for (j in seq_along(horizons)) {
        h <- as.integer(horizons[j])
        hit <- hit_fn(d) & as.integer(d$model_id) == mid & as.integer(d$horizon) == h
        c0 <- 2L + (i - 1L) * 6L + (j - 1L) * 2L
        if (skip_ref) next
        if (any(hit)) {
          rr <- d[which(hit)[1], ]
          row[c0] <- .competing_supp_fmt_hr_ci(rr$HR, rr$HR_low, rr$HR_high)
          row[c0 + 1L] <- .competing_supp_fmt_p(rr$p)
        }
      }
    }
    row
  }

  for (lv in levels_u) {
    rows_out[[length(rows_out) + 1L]] <- fill_row(
      function(dd) .competing_supp_is_exposure_term(dd$term) & dd$level == lv,
      lv, skip_ref = identical(lv, ref)
    )
  }

  for (sv in skeleton_vars) {
    # 最长名优先：避免 CK 抢到 CKDYes
    rows_terms <- unique(as.character(d$term[!is_exp]))
    matched <- rows_terms[vapply(rows_terms, function(tm) {
      .competing_supp_term_matches_skeleton(tm, sv)
    }, logical(1))]
    # 若更长骨架也能匹配同一 term，则本短名跳过该 term
    longer <- skeleton_vars[nchar(skeleton_vars) > nchar(sv)]
    if (length(matched) && length(longer)) {
      matched <- matched[!vapply(matched, function(tm) {
        any(vapply(longer, function(lv) .competing_supp_term_matches_skeleton(tm, lv), logical(1)))
      }, logical(1))]
    }
    if (!length(matched)) {
      # 空白骨架行（案例中 Model1 空白、未进模变量空白）
      rows_out[[length(rows_out) + 1L]] <- c(.competing_supp_display_label(sv), rep("", nc - 1L))
      next
    }
    for (tm in matched) {
      # 案例风格：二分类临床变量用基名（Hypertension），Gender/Race 保留水平
      lab <- .competing_supp_display_label(sv)
      if (grepl("^Gender", tm, ignore.case = TRUE) || grepl("^Gender", sv, ignore.case = TRUE)) {
        if (grepl("Female", tm, ignore.case = TRUE)) lab <- "Gender(Female)"
        else if (grepl("Male", tm, ignore.case = TRUE)) lab <- "Gender(Male)"
      } else if (grepl("^Race", tm, ignore.case = TRUE) || grepl("^Race", sv, ignore.case = TRUE)) {
        suffix <- sub("(?i)^Race[ _]*", "", tm, perl = TRUE)
        suffix <- gsub("_", " ", suffix, fixed = TRUE)
        if (nzchar(trimws(suffix))) lab <- sprintf("Race(%s)", trimws(suffix))
      } else if (grepl("(Yes|No)$", tm, ignore.case = TRUE)) {
        # CKDYes / CRRTYes → 只保留基名，避免 CK(DYes)
        lab <- .competing_supp_display_label(sv)
      } else if (length(matched) > 1L) {
        suffix <- sub(paste0("(?i)^", gsub("[^A-Za-z0-9]", "", sv)), "",
                      gsub("[^A-Za-z0-9]", "", tm), perl = TRUE)
        if (nzchar(suffix) && !toupper(suffix) %in% c("YES", "NO")) {
          lab <- sprintf("%s(%s)", .competing_supp_display_label(sv), suffix)
        }
      }
      rows_out[[length(rows_out) + 1L]] <- fill_row(
        function(dd) dd$term == tm, lab, skip_ref = FALSE
      )
    }
  }
  rows_out
}

#' 补充材料2/3/4/6：可多段堆叠（Standard / Competing / Handle or No handle）
.competing_write_supp_models_xlsx <- function(path,
                                              sections,
                                              horizons = c(7L, 14L, 28L),
                                              model_ids = 1:3,
                                              covs_footnote = NULL,
                                              horizon_labels = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  horizons <- as.integer(horizons)
  if (is.null(horizon_labels) || length(horizon_labels) != length(horizons)) {
    horizon_labels <- if (exists(".competing_supp_horizon_labels", mode = "function")) {
      .competing_supp_horizon_labels(horizons)
    } else {
      paste0(horizons, "-day")
    }
  }
  nc <- 1L + 6L * length(model_ids)
  header1 <- c("Variables", rep("", nc - 1L))
  header2 <- c("", rep("", nc - 1L))
  header3 <- c("", rep("", nc - 1L))
  for (i in seq_along(model_ids)) {
    base <- 2L + (i - 1L) * 6L
    header1[base] <- paste0("Model  ", model_ids[i])
    for (j in seq_along(horizons)) {
      c0 <- base + (j - 1L) * 2L
      header2[c0] <- horizon_labels[j]
      header3[c0] <- "HR(95%CI)"
      header3[c0 + 1L] <- "P value"
    }
  }

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1", gridLines = FALSE)
  openxlsx::writeData(wb, "Sheet1", rbind(header1, header2, header3), colNames = FALSE)
  openxlsx::mergeCells(wb, "Sheet1", rows = 1:3, cols = 1)
  for (i in seq_along(model_ids)) {
    base <- 2L + (i - 1L) * 6L
    openxlsx::mergeCells(wb, "Sheet1", rows = 1, cols = base:(base + 5L))
    for (j in seq_along(horizons)) {
      openxlsx::mergeCells(
        wb, "Sheet1", rows = 2,
        cols = (base + (j - 1L) * 2L):(base + (j - 1L) * 2L + 1L)
      )
    }
  }

  all_rows <- list()
  section_row_idx <- integer(0)
  for (sec in sections) {
    before <- length(all_rows)
    chunk <- .competing_supp_model_section_rows(
      tab = sec$tab,
      method = sec$method %||% "standard",
      model_ids = model_ids,
      horizons = horizons,
      skeleton_vars = sec$skeleton_vars,
      section_title = sec$section_title,
      extra_note = sec$extra_note
    )
    all_rows <- c(all_rows, chunk)
    if (length(chunk) && !is.null(sec$section_title) && nzchar(sec$section_title)) {
      section_row_idx <- c(section_row_idx, before + 1L)
    }
  }
  mat <- if (length(all_rows)) do.call(rbind, all_rows) else matrix("", nrow = 0, ncol = nc)
  if (nrow(mat)) {
    openxlsx::writeData(wb, "Sheet1", as.data.frame(mat, stringsAsFactors = FALSE),
                        startRow = 4, colNames = FALSE)
  }

  openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_header(),
                     rows = 1:3, cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  if (nrow(mat) > 0L) {
    openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_body(),
                       rows = 4:(3 + nrow(mat)), cols = 1:nc, gridExpand = TRUE, stack = TRUE)
    openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_left(),
                       rows = 4:(3 + nrow(mat)), cols = 1, gridExpand = TRUE, stack = TRUE)
    for (ri in section_row_idx) {
      openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_section(),
                         rows = 3 + ri, cols = 1, stack = TRUE)
    }
  }
  openxlsx::setColWidths(wb, "Sheet1", cols = 1, widths = 28)
  openxlsx::setColWidths(wb, "Sheet1", cols = 2:nc, widths = 14)
  if (!is.null(covs_footnote) && nzchar(covs_footnote)) {
    openxlsx::writeData(
      wb, "Sheet1",
      .competing_supp_display_label(covs_footnote),
      startRow = 4 + max(nrow(mat), 0L) + 1L, colNames = FALSE
    )
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  .competing_xlsx_fix_drawings(path)
  invisible(path)
}

#' 写出补充表4：VIF 共线性诊断
.competing_write_supp_vif_xlsx <- function(path, vif_df, db = "MIMIC",
                                           title = NULL, footnote = NULL) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("需要 openxlsx 包写出补充表", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  thr_s <- attr(vif_df, "vif_threshold_strict") %||% 4
  thr_l <- attr(vif_df, "vif_threshold_loose") %||% 10
  if (is.null(title) || !nzchar(title)) {
    title <- sprintf(
      "Multicollinearity analysis (VIF) for %s; threshold strict=%.0f, loose=%.0f",
      db, thr_s, thr_l
    )
  }
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", title, startRow = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_section(), rows = 1, cols = 1, stack = TRUE)

  hdr <- data.frame(
    Variable = "Variable",
    VIF = "VIF",
    Judgment = "Judgment",
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "Sheet1", hdr, startRow = 3, colNames = FALSE)
  openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_header(),
                     rows = 3, cols = 1:3, gridExpand = TRUE, stack = TRUE)

  body <- if (is.data.frame(vif_df) && nrow(vif_df)) {
    data.frame(
      Variable = as.character(vif_df$Variable),
      VIF = if (exists("format_vif_pub_column", mode = "function")) {
        format_vif_pub_column(vif_df$VIF)
      } else {
        formatC(as.numeric(vif_df$VIF), format = "f", digits = 3)
      },
      Judgment = as.character(vif_df$Judgment %||% ""),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(Variable = "NE", VIF = "", Judgment = "no variables", stringsAsFactors = FALSE)
  }
  openxlsx::writeData(wb, "Sheet1", body, startRow = 4, colNames = FALSE)
  openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_left(),
                     rows = 4:(3 + nrow(body)), cols = 1, gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, "Sheet1", .competing_xlsx_style_body(),
                     rows = 4:(3 + nrow(body)), cols = 2:3, gridExpand = TRUE, stack = TRUE)
  openxlsx::setColWidths(wb, "Sheet1", cols = 1, widths = 28)
  openxlsx::setColWidths(wb, "Sheet1", cols = 2, widths = 12)
  openxlsx::setColWidths(wb, "Sheet1", cols = 3, widths = 28)

  fn <- footnote
  if (is.null(fn) || !nzchar(fn)) {
    fn <- sprintf(
      "VIF calculated among exposure and Model 3 covariates. Pass if VIF<%g; borderline if <%g; otherwise fail.",
      thr_s, thr_l
    )
  }
  openxlsx::writeData(wb, "Sheet1", fn, startRow = 4 + nrow(body) + 1L, colNames = FALSE)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  .competing_xlsx_fix_drawings(path)
  invisible(path)
}
