#!/usr/bin/env Rscript
# Add AP-style sensitivity supplements to AKI WPR(class=4):
#   Primary = 4-class; Sensitivity = 2-class
#   Table S7 AvePP/OCC | Table S8 mortality+LRT | Table S9 rescaled WPR HR
#   Figure S9 2-class trajectory | Figure S10 mortality bars (4 vs 2)
#
#   Rscript run/trajectory_prognosis/add_aki_wpr4_sensitivity_2class_ap.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(cli)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
index_root <- file.path(
  block_root,
  "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/by_index/WPR(class=4)"
)
proj_root <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
stopifnot(dir.exists(index_root))

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_paper_tables.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)
cfg_path <- file.path(proj_root, "config.R")
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)

fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
dir.create(fig_root, showWarnings = FALSE, recursive = TRUE)
dir.create(tab_root, showWarnings = FALSE, recursive = TRUE)

# 4-class align (already used in main): old -> new
.map4 <- list(
  mimic = stats::setNames(c(2L, 3L, 1L, 4L), c("1", "2", "3", "4")), # 1→2,2→3,3→1,4→4
  eicu  = stats::setNames(c(1L, 3L, 2L, 4L), c("1", "2", "3", "4"))  # 1→1,2→3,3→2,4→4
)

.npar <- function(m) {
  m <- trajectory_unwrap_jointlcmm(m)
  aic <- as.numeric(m$AIC); ll <- as.numeric(m$loglik)
  if (!is.finite(aic) || !is.finite(ll)) return(NA_real_)
  (aic + 2 * ll) / 2
}

.ave_occ <- function(m, class_map = NULL) {
  m <- trajectory_unwrap_jointlcmm(m)
  pp <- as.data.frame(m$pprob)
  prob_cols <- grep("^prob", names(pp), value = TRUE)
  cls_raw <- as.integer(pp$class)
  cls <- if (!is.null(class_map) && length(class_map))
    trajectory_apply_class_swap(cls_raw, class_map) else cls_raw
  ng <- length(prob_cols)
  # reorder prob columns to display class order if mapped
  P <- as.matrix(pp[, prob_cols, drop = FALSE])
  if (!is.null(class_map) && length(class_map) == ng) {
    Pnew <- P
    old_idx <- as.integer(names(class_map))
    new_idx <- as.integer(unname(class_map))
    for (k in seq_along(old_idx)) {
      if (old_idx[k] <= ncol(P) && new_idx[k] <= ncol(Pnew))
        Pnew[, new_idx[k]] <- P[, old_idx[k]]
    }
    P <- Pnew
  }
  tab <- table(factor(cls, levels = seq_len(ng)))
  pi <- as.numeric(prop.table(tab))
  ave <- vapply(seq_len(ng), function(k) {
    idx <- which(cls == k)
    if (!length(idx)) return(NA_real_)
    mean(P[idx, k], na.rm = TRUE)
  }, numeric(1))
  occ <- vapply(seq_len(ng), function(k) {
    if (!is.finite(ave[k]) || ave[k] >= 1 || pi[k] <= 0 || pi[k] >= 1) return(NA_real_)
    (ave[k] / (1 - ave[k])) / (pi[k] / (1 - pi[k]))
  }, numeric(1))
  data.frame(
    Class = paste0("Class", seq_len(ng)),
    n = as.integer(tab),
    Proportion_pct = round(100 * pi, 2),
    AvePP = round(ave, 5),
    OCC = round(occ, 2),
    stringsAsFactors = FALSE
  )
}

.mortality_by_class <- function(m, base, class_map = NULL) {
  m <- trajectory_unwrap_jointlcmm(m)
  pp <- as.data.frame(m$pprob)[, c("subject_id_num", "class")]
  d <- merge(base, pp, by = "subject_id_num")
  d$class_disp <- if (!is.null(class_map) && length(class_map))
    trajectory_apply_class_swap(d$class, class_map) else as.integer(d$class)
  out <- lapply(sort(unique(d$class_disp)), function(k) {
    x <- d$survival_28d[d$class_disp == k]
    data.frame(
      Class = paste0("Class", k),
      n = length(x),
      Events = sum(x == 1L, na.rm = TRUE),
      Mortality_28d_pct = round(100 * mean(x == 1L, na.rm = TRUE), 1),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(out)
}

.parse_s3_wpr_hr <- function(xlsx) {
  if (!file.exists(xlsx)) return(NULL)
  raw <- tryCatch(openxlsx::read.xlsx(xlsx, colNames = FALSE), error = function(e) NULL)
  if (is.null(raw) || !nrow(raw)) return(NULL)
  hit <- which(apply(raw, 1L, function(r) any(grepl("^\\s*WPR\\s*$", as.character(r)))))
  if (!length(hit)) {
    hit <- which(apply(raw, 1L, function(r) any(grepl("\\bWPR\\b", as.character(r)))))
  }
  if (!length(hit)) return(NULL)
  row <- as.character(unlist(raw[hit[[1L]], , drop = TRUE]))
  row <- row[!is.na(row) & nzchar(row)]
  cell <- row[grepl("\\bp\\s*[=<>]", row, ignore.case = TRUE)][1L]
  if (is.na(cell) || !nzchar(cell)) {
    cells <- row[grepl("[0-9.]+\\s*\\(", row)]
    cell <- if (length(cells)) cells[[length(cells)]] else NA_character_
  }
  if (is.na(cell) || !nzchar(cell)) return(NULL)
  nums <- as.numeric(unlist(regmatches(cell, gregexpr("[0-9]+\\.[0-9]+|[0-9]+", cell))))
  if (length(nums) < 3L) return(NULL)
  list(hr = nums[[1L]], lo = nums[[2L]], hi = nums[[3L]])
}

.lrt_row <- function(label, m_lo, m_hi, npar_lo, npar_hi) {
  m_lo <- trajectory_unwrap_jointlcmm(m_lo)
  m_hi <- trajectory_unwrap_jointlcmm(m_hi)
  ll_lo <- as.numeric(m_lo$loglik); ll_hi <- as.numeric(m_hi$loglik)
  stat <- 2 * (ll_hi - ll_lo)
  df <- npar_hi - npar_lo
  p_naive <- if (is.finite(stat) && is.finite(df) && df > 0)
    pchisq(stat, df = df, lower.tail = FALSE) else NA_real_
  data.frame(
    Comparison = label,
    LogLik_simpler = round(ll_lo, 1),
    LogLik_complex = round(ll_hi, 1),
    LRT_2deltaLL = round(stat, 2),
    Naive_chisq_P = ifelse(
      is.finite(p_naive),
      ifelse(p_naive < 0.001, "<0.001", sprintf("%.3f", p_naive)),
      "NA"
    ),
    stringsAsFactors = FALSE
  )
}

# 2-class: Class1 = majority (AP primary style). If Class1 already majority → identity.
.map2_for <- function(m) {
  m <- trajectory_unwrap_jointlcmm(m)
  cl <- as.integer(as.data.frame(m$pprob)$class)
  tab <- table(cl)
  # identity if class1 is majority or only one class; else swap so Class1=majority low-risk label convention
  # AP 2-class: Class1 majority low mort — use majority as Class1
  maj <- as.integer(names(which.max(tab))[1])
  if (identical(maj, 1L)) {
    stats::setNames(c(1L, 2L), c("1", "2"))
  } else {
    # swap so majority becomes display Class1
    stats::setNames(c(2L, 1L), c("1", "2"))
  }
}

.make_db <- function(db, db_lab) {
  db_dir <- file.path(index_root, db)
  jlcm_path <- file.path(db_dir, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData")
  long1_path <- file.path(db_dir, "step14_trajectory_jlcm/Data/D01_long_WPR_D_1.RData")
  index_path <- file.path(proj_root, "data", db, "12_WPR.RData")
  stopifnot(file.exists(jlcm_path), file.exists(long1_path))

  e <- new.env(parent = emptyenv())
  load(jlcm_path, envir = e)
  models <- e$models_list_with_cov
  md <- as.data.frame(e$model_data_final)
  m1 <- models$m1; m2 <- models$m2; m4 <- models$m4
  map4 <- .map4[[db]]
  map2 <- .map2_for(m2)

  base <- md[!duplicated(md$subject_id_num),
             c("subject_id_num", "subject_id", "survival_28d", "survival_time_28d")]

  # —— Table S7 ——
  s7_4 <- .ave_occ(m4, map4); s7_4$Model <- "4-class (primary)"
  s7_2 <- .ave_occ(m2, map2); s7_2$Model <- "2-class (sensitivity)"
  s7 <- dplyr::bind_rows(s7_4, s7_2)[, c(
    "Model", "Class", "n", "Proportion_pct", "AvePP", "OCC"
  )]
  s7_title <- sprintf(
    "Table S7-%s. Average posterior probability and OCC for 4-class and 2-class WPR models",
    db_lab
  )
  s7_fp <- file.path(tab_root, paste0(s7_title, ".xlsx"))
  export_sci_table(
    s7, s7_fp, title = s7_title, sheet = "TableS7",
    table_footnotes = list(
      "AvePP = mean posterior probability of the assigned class; OCC = odds of correct classification (Nagin).",
      "Primary analysis used the 4-class solution; 2-class metrics are shown as sensitivity (AP-aligned package).",
      "4-class labels: Class1 = lowest 28-day mortality (majority); Class4 = highest (see class_align_WPR.csv).",
      "2-class labels: Class1 = majority; Class2 = minority (AP primary Fig2 style).",
      "OCC >> 5 indicates good classification quality."
    )
  )

  # —— Table S8 ——
  mort4 <- .mortality_by_class(m4, base, map4); mort4$Model <- "4-class (primary)"
  mort2 <- .mortality_by_class(m2, base, map2); mort2$Model <- "2-class (sensitivity)"
  s8a <- dplyr::bind_rows(mort4, mort2)[, c(
    "Model", "Class", "n", "Events", "Mortality_28d_pct"
  )]
  npar1 <- .npar(m1); npar2 <- .npar(m2); npar4 <- .npar(m4)
  s8b <- dplyr::bind_rows(
    .lrt_row("2-class vs 1-class", m1, m2, npar1, npar2),
    .lrt_row("4-class vs 2-class", m2, m4, npar2, npar4)
  )
  s8_title <- sprintf(
    "Table S8-%s. Class-specific 28-day mortality and approximate likelihood-ratio comparisons",
    db_lab
  )
  s8_body <- dplyr::bind_rows(
    data.frame(
      Section = "A. 28-day in-hospital mortality by latent class",
      Col1 = "Model", Col2 = "Class", Col3 = "n", Col4 = "Events",
      Col5 = "Mortality (%)", stringsAsFactors = FALSE
    ),
    data.frame(
      Section = "", Col1 = s8a$Model, Col2 = s8a$Class,
      Col3 = as.character(s8a$n), Col4 = as.character(s8a$Events),
      Col5 = as.character(s8a$Mortality_28d_pct), stringsAsFactors = FALSE
    ),
    data.frame(Section = "", Col1 = "", Col2 = "", Col3 = "", Col4 = "", Col5 = "",
               stringsAsFactors = FALSE),
    data.frame(
      Section = "B. Approximate nested LRT (not formal BLRT/LMR-LRT)",
      Col1 = "Comparison", Col2 = "LL simpler", Col3 = "LL complex",
      Col4 = "2ΔLL", Col5 = "Naive P", stringsAsFactors = FALSE
    ),
    data.frame(
      Section = "",
      Col1 = s8b$Comparison,
      Col2 = as.character(s8b$LogLik_simpler),
      Col3 = as.character(s8b$LogLik_complex),
      Col4 = as.character(s8b$LRT_2deltaLL),
      Col5 = s8b$Naive_chisq_P,
      stringsAsFactors = FALSE
    )
  )
  names(s8_body) <- c("Section", "V1", "V2", "V3", "V4", "V5")
  s8_fp <- file.path(tab_root, paste0(s8_title, ".xlsx"))
  export_sci_table(
    s8_body, s8_fp, title = s8_title, sheet = "TableS8",
    table_footnotes = list(
      "Panel A: event = 28-day in-hospital death (survival_28d).",
      "Panel B: 2ΔLL is shown for transparency. Naive P is exploratory only.",
      "Primary class solution is 4-class; 2-class is sensitivity (AP package roles)."
    )
  )

  # —— Table S9 ——
  s3_path <- file.path(
    db_dir, "Tables",
    sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab)
  )
  if (!file.exists(s3_path)) {
    s3_path <- file.path(tab_root, basename(s3_path))
  }
  hr <- .parse_s3_wpr_hr(s3_path)
  s9_title <- sprintf(
    "Table S9-%s. Rescaled univariable HRs for continuous baseline WPR",
    db_lab
  )
  s9_fp <- file.path(tab_root, paste0(s9_title, ".xlsx"))
  sdw <- NA_real_
  if (file.exists(index_path)) {
    e_ix <- new.env(parent = emptyenv())
    load(index_path, envir = e_ix)
    index_df <- e_ix$index_df
    ids <- unique(as.character(md$subject_id))
    w1 <- as.numeric(index_df$WPR_1[as.character(index_df$subject_id) %in% ids])
    sdw <- stats::sd(w1, na.rm = TRUE)
  } else {
    w1 <- numeric(0)
  }
  if (!is.null(hr)) {
    rescale <- function(delta, label) {
      data.frame(
        Contrast = label,
        HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr^delta, hr$lo^delta, hr$hi^delta),
        stringsAsFactors = FALSE
      )
    }
    s9 <- dplyr::bind_rows(
      data.frame(
        Contrast = "Per +1.00 unit (as in Table S3)",
        HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr, hr$lo, hr$hi),
        stringsAsFactors = FALSE
      ),
      rescale(0.01, "Per +0.01 unit"),
      rescale(0.05, "Per +0.05 unit"),
      if (is.finite(sdw)) {
        rescale(sdw, sprintf("Per +1 SD (SD=%.4f of baseline WPR_1)", sdw))
      } else {
        NULL
      }
    )
    export_sci_table(
      s9, s9_fp, title = s9_title, sheet = "TableS9",
      table_footnotes = list(
        sprintf("Source: univariable Cox HR for WPR in Table S3-%s.", db_lab),
        "Rescaling uses HR(delta)=HR(1)^delta.",
        if (is.finite(sdw)) {
          sprintf("Baseline WPR_1 SD in JLCM analysis set (n=%d): %.4f.",
                  sum(is.finite(w1)), sdw)
        } else {
          "Baseline WPR_1 SD not available."
        }
      )
    )
  } else {
    cli_alert_warning("Could not parse WPR HR from {s3_path}; skip S9 for {db_lab}")
  }

  # flush tables
  ctx <- list(config = list(project = list(database = db_lab)))
  if (exists("render_queued_tables", mode = "function")) {
    try(render_queued_tables(ctx), silent = TRUE)
  }

  # —— Figure S9: 2-class trajectory ——
  e_long <- new.env(parent = emptyenv())
  load(long1_path, envir = e_long)
  long <- e_long$long
  # attach raw class from m2 for plot remapping
  pp2 <- as.data.frame(trajectory_unwrap_jointlcmm(m2)$pprob)
  id_map <- unique(md[, c("subject_id", "subject_id_num")])
  id_map$class_raw <- pp2$class[match(id_map$subject_id_num, pp2$subject_id_num)]
  long$Class <- id_map$class_raw[match(as.character(long$subject_id), as.character(id_map$subject_id))]
  cov <- character(0)
  if (exists("trajectory_jlcm_cov_cols", mode = "function")) {
    cov <- trajectory_jlcm_cov_cols(list(), trajectory_unwrap_jointlcmm(m2))
  }
  p9 <- .tpj04_make_plot(
    trajectory_unwrap_jointlcmm(m2), long, "WPR", 2L, 28L, "subject_id",
    font_family = "sans", cov_cols = cov, class_map = map2, ylim = NULL
  )
  fig9_db <- file.path(
    db_dir, "Figures",
    sprintf("Figure S9-%s. Trajectory of WPR two latent classes.pdf", db_lab)
  )
  stopifnot(!is.null(p9))
  ggsave(fig9_db, p9, width = 7.2, height = 5.2, device = grDevices::cairo_pdf)
  file.copy(fig9_db, file.path(fig_root, basename(fig9_db)), overwrite = TRUE)

  # —— Figure S10: mortality bars ——
  plot_df <- dplyr::bind_rows(mort4, mort2)
  plot_df$Model <- factor(
    plot_df$Model,
    levels = c("4-class (primary)", "2-class (sensitivity)")
  )
  plot_df$label <- sprintf(
    "%.1f%%\n(%d/%d)", plot_df$Mortality_28d_pct, plot_df$Events, plot_df$n
  )
  fill_vals <- c(
    "Class1" = "#D55E00", "Class2" = "#E69F00",
    "Class3" = "#56B4E9", "Class4" = "#009E73"
  )
  p10 <- ggplot(plot_df, aes(x = Class, y = Mortality_28d_pct, fill = Class)) +
    geom_col(width = 0.7, color = "grey20", linewidth = 0.2) +
    geom_text(aes(label = label), vjust = -0.15, size = 2.8, lineheight = 0.9) +
    facet_wrap(~ Model, scales = "free_x") +
    scale_fill_manual(values = fill_vals, guide = "none") +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    labs(
      title = "28-day in-hospital mortality by WPR latent class",
      x = NULL, y = "Mortality (%)"
    ) +
    theme_classic(base_size = 11) +
    theme(
      strip.background = element_blank(),
      strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold", hjust = 0.5)
    )
  fig10_db <- file.path(
    db_dir, "Figures",
    sprintf("Figure S10-%s. Twenty-eight day mortality by WPR trajectory class.pdf", db_lab)
  )
  ggsave(fig10_db, p10, width = 9.0, height = 4.6, device = grDevices::cairo_pdf)
  file.copy(fig10_db, file.path(fig_root, basename(fig10_db)), overwrite = TRUE)

  for (fp in c(s7_fp, s8_fp, s9_fp)) {
    if (file.exists(fp)) {
      file.copy(fp, file.path(db_dir, "Tables", basename(fp)), overwrite = TRUE)
    }
  }

  # save 2-class map note
  utils::write.csv(
    data.frame(db = db, old_class = as.integer(names(map2)), new_class = as.integer(unname(map2))),
    file.path(tab_root, "Summary", sprintf("class_align_2class_%s_WPR.csv", db)),
    row.names = FALSE
  )

  list(
    s7 = s7_fp, s8 = s8_fp, s9 = s9_fp,
    mort2 = mort2, mort4 = mort4, map2 = map2
  )
}

cli_h1("Add 2-class sensitivity (AP roles S7–S9 / Fig S9–S10)")
sup_m <- .make_db("mimic", "MIMIC")
sup_e <- .make_db("eicu", "eICU")

# Compose dual panels for S9/S10 into root flat then four-dir
.compose_named_pair <- function(stem, layout = "stack") {
  a <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  b <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  out <- file.path(fig_root, stem)
  if (!file.exists(a) || !file.exists(b)) {
    cli_alert_warning("缺配对 {stem}")
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    .dual_db_compose_pair_pdf(
      a, b, out, layout = layout,
      label_a = "A. MIMIC", label_b = "B. eICU",
      dpi = 200L, label_cex = 1.15
    )
    TRUE
  }, error = function(e) {
    cli_alert_danger("{stem}: {e$message}"); FALSE
  })
  if (isTRUE(ok)) {
    unlink(c(a, b))
    cli_alert_success("已拼 {stem}")
  }
  invisible(isTRUE(ok))
}

.compose_named_pair("Figure S9. Trajectory of WPR two latent classes.pdf", "stack")
.compose_named_pair("Figure S10. Twenty-eight day mortality by WPR trajectory class.pdf", "stack")

# Export only new figs into four-dir (ensure_formats on whole Figures)
tryCatch(
  pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list()),
  error = function(e) cli_alert_warning("formats: {e$message}")
)

# image_information
imdir <- file.path(fig_root, "image_information")
dir.create(imdir, showWarnings = FALSE, recursive = TRUE)
writeLines(c(
  "# Figure S9. Trajectory of WPR two latent classes",
  "",
  "## 图面说明",
  "敏感性分析：2 类 WPR 轨迹均值曲线双库拼图（A. MIMIC，B. eICU）。",
  "主分析为 4 类（Figure 2）；本图对应 2 类敏感性。",
  "Class 1 = 多数低危，Class 2 = 少数高危（对齐 AP 主文 2 类口径）。",
  "",
  "## 分析上下文",
  "- 暴露: WPR 2-class (sensitivity)",
  "- 结局: 28-day in-hospital death",
  "- Grouping: 2-class sensitivity",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是"
), file.path(imdir, "Figure S9. Trajectory of WPR two latent classes.md"), useBytes = TRUE)

writeLines(c(
  "# Figure S10. Twenty-eight day mortality by WPR trajectory class",
  "",
  "## 图面说明",
  "28 天院内死亡率柱图：左/上为 4 类主分析，右/下为 2 类敏感性；双库拼图。",
  "柱顶标注死亡率%与事件数/人数。类标签与 Table S7–S8 / Figure 2 / Figure S9 一致。",
  "",
  "## 分析上下文",
  "- 暴露: WPR latent class (4-class primary; 2-class sensitivity)",
  "- 结局: 28-day in-hospital death",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是"
), file.path(imdir, "Figure S10. Twenty-eight day mortality by WPR trajectory class.md"), useBytes = TRUE)

# Update README
readme <- file.path(tab_root, "README.md")
extra <- c(
  "",
  "## 敏感性（对齐 AP：2 类）",
  "| 编号 | 内容 | 口径 |",
  "|---|---|---|",
  "| Table S7 | 4 类(主)+2 类(敏) AvePP / OCC | 双库 |",
  "| Table S8 | 类间 28 天死亡 + 近似 LRT（2vs1、4vs2） | 双库 |",
  "| Table S9 | 连续 WPR HR 换算（+0.01/+0.05/+1SD） | 双库 |",
  "| Figure S9 | 2 类轨迹（敏感性） | 双库拼图 |",
  "| Figure S10 | 28 天死亡率柱图（4 类 vs 2 类） | 双库拼图 |",
  "",
  sprintf("敏感性补齐时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
if (file.exists(readme)) {
  write(extra, readme, append = TRUE)
} else {
  writeLines(c("# Tables", extra), readme, useBytes = TRUE)
}

cli_alert_success("Sensitivity supplements added under {index_root}")
cli_alert_info("pdf now: {paste(list.files(file.path(fig_root,'pdf')), collapse='; ')}")
cli_alert_info("tables S7+: {paste(basename(list.files(tab_root, pattern='Table S[789]', full.names=TRUE)), collapse='; ')}")
