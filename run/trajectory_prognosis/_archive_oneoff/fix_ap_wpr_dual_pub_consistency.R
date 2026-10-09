#!/usr/bin/env Rscript
# AP WPR dual-db publication consistency:
#   Fig1  两库同一纳排步骤
#   Fig S3 / Table 3  只留 MIMIC 主库
#   Fig S4  双库同一亚组名单
#   Fig S10 / S11 / Table S7–S8  3 类按主库表型对齐
#
#   Rscript run/trajectory_prognosis/fix_ap_wpr_dual_pub_consistency.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(lcmm)
  library(survival)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.engine)

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
index_root <- file.path(
  block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/by_index/WPR"
)
stopifnot(dir.exists(index_root))

source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/attrition_log.R"), local = FALSE)
source(file.path(.engine, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.engine, "R/trajectory_paper_tables.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.engine, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(
  file.path(.engine, "Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R"),
  local = FALSE
)
source(file.path(.engine, "configs/config_trajectory_prognosis_ap_wpr_dual.R"))

fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
arch_root <- file.path(tab_root, "_archive_messy")
sum_dir <- file.path(tab_root, "Summary")
dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)
dir.create(arch_root, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
pdf_dir <- file.path(fig_root, "pdf")
dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)

.compose_ab <- function(stem, layout = "stack") {
  a <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  b <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  out <- file.path(fig_root, stem)
  if (!file.exists(a) || !file.exists(b)) {
    cli::cli_alert_warning("缺拼图源: {basename(a)} / {basename(b)}")
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
    cli::cli_alert_warning("拼图失败 {stem}: {e$message}")
    FALSE
  })
  if (isTRUE(ok) && file.exists(out)) {
    unlink(c(a, b))
    file.copy(out, file.path(pdf_dir, basename(out)), overwrite = TRUE)
    cli::cli_alert_success("已拼 {stem}")
  }
  invisible(isTRUE(ok))
}

.attrition_df <- function(steps, ns, ids, excludes, db) {
  n <- length(steps)
  data.frame(
    step = steps,
    n = as.integer(ns),
    source = c("rawdata", rep("log", n - 1L)),
    kind = "include",
    step_id = ids,
    exclude_label = excludes,
    fork_left_label = NA_character_,
    fork_left_n = NA_real_,
    fork_right_label = NA_character_,
    fork_right_n = NA_real_,
    database = db,
    stringsAsFactors = FALSE
  )
}

# ── 1) Fig1: 两库同一 4 步纳排 ─────────────────────────────────────────────
# eICU 人数来自 prepare 落盘；MIMIC 来自本双库 shared/worker。
steps <- c(
  "AP ICU cohort identified",
  "Baseline and 28-day outcome complete",
  "At least 2 daily WPR measurements",
  "Analysis set after imputation"
)
ids <- c("starting_cohort", "complete_outcome", "wpr_ge2_days", "after_imputation")
rows_m <- .attrition_df(
  steps, c(932L, 932L, 916L, 910L), ids,
  c(NA, "Missing baseline or 28-day outcome",
    "Fewer than 2 daily WPR values", "Incomplete after multiple imputation"),
  "MIMIC"
)
rows_e <- .attrition_df(
  steps, c(659L, 552L, 470L, 447L), ids,
  c(NA, "Missing ICU-first baseline or 28-day outcome",
    "Fewer than 2 daily WPR values", "Incomplete after multiple imputation"),
  "eICU"
)
.write_attr <- function(rows, db) {
  dests <- c(
    file.path(index_root, db, "step24_attrition_flowchart/Tables",
              sprintf("Flowchart_attrition_%s.csv", db)),
    file.path(tab_root, sprintf("Flowchart_attrition_%s.csv", db))
  )
  for (fp in dests) {
    dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(rows, fp, row.names = FALSE)
  }
}
.write_attr(rows_m, "mimic")
.write_attr(rows_e, "eicu")

fig1_dest <- file.path(pdf_dir, "Figure 1. Flowchart of patient selection.pdf")
ok1 <- attrition_draw_dual_panel_pdf(
  list(MIMIC = rows_m, eICU = rows_e),
  fig1_dest,
  titles = c("MIMIC-IV — trajectory prognosis", "eICU-CRD — trajectory prognosis")
)
# 分库单页（不进根目录拼图）
attrition_draw_pdf(
  rows_m, "MIMIC-IV — trajectory prognosis",
  file.path(index_root, "mimic/Figures",
            "Figure 1-MIMIC. Flowchart of patient selection.pdf")
)
attrition_draw_pdf(
  rows_e, "eICU-CRD — trajectory prognosis",
  file.path(index_root, "eicu/Figures",
            "Figure 1-eICU. Flowchart of patient selection.pdf")
)
cli::cli_alert_info("Fig1 dual draw ok={ok1}")

# ── 2) Fig S3 / Table 3: 只留 MIMIC 主库 ───────────────────────────────────
mimic_s3_src <- file.path(
  index_root, "mimic/Figures/_raw/Figure Piecewise Cox CutSearch WPR.pdf"
)
if (!file.exists(mimic_s3_src)) {
  mimic_s3_src <- file.path(
    index_root, "mimic/step20_trajectory_piecewise_cox/Figures",
    "Figure Piecewise Cox CutSearch WPR.pdf"
  )
}
s3_name <- "Figure S3. Piecewise Cox cut point search.pdf"
stopifnot(file.exists(mimic_s3_src))
file.copy(mimic_s3_src, file.path(pdf_dir, s3_name), overwrite = TRUE)
file.copy(mimic_s3_src, file.path(fig_root, s3_name), overwrite = TRUE)
unlink(list.files(
  fig_root, pattern = "Figure S3-eICU", full.names = TRUE, recursive = TRUE
))
file.copy(
  mimic_s3_src,
  file.path(index_root, "mimic/Figures",
            "Figure S3-MIMIC. Piecewise Cox cut point search.pdf"),
  overwrite = TRUE
)
t3_e <- file.path(tab_root, "Table 3-eICU. Time-dependent HR for trajectory classes.xlsx")
if (file.exists(t3_e)) {
  file.copy(t3_e, file.path(arch_root, basename(t3_e)), overwrite = TRUE)
  unlink(t3_e)
}
cli::cli_alert_success("Fig S3 / Table 3 仅保留 MIMIC（cut=7）")

# ── 3) Fig S4: 双库同一亚组 ────────────────────────────────────────────────
sg_vars <- c("Gender", "Hypertension", "CKD", "Hepatitis", "Pneumonia", "COPD")
.run_subgroup <- function(db, db_lab) {
  ck <- file.path(
    block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual",
    "checkpoints/by_index/WPR", db, "step01_trajectory_jlcm.rds"
  )
  stopifnot(file.exists(ck))
  pack <- readRDS(ck)
  dat <- pack$ctx$data$imputed
  ctx <- list(
    config = list(
      project = list(root = .engine, database = db_lab,
                     output_dir = file.path(index_root, db)),
      data = list(id_column = "subject_id"),
      survival = list(time_var = "survival_time_28d", event_var = "survival_28d"),
      trajectory = list(skip_class_swap = TRUE)
    )
  )
  bl <- list(
    subgroup_vars = sg_vars,
    age_var = "Age",
    age_cutoff = 65,
    auto_scan_categorical = FALSE,
    min_n_per_subgroup = 5L,
    pause_enable = FALSE,
    ref_class = "1"
  )
  res <- .tsc06_run_one(
    ctx, dat, bl, "WPR", "trajectory_class",
    "survival_time_28d", "survival_28d", 28
  )
  stopifnot(!is.null(res), !is.null(res$plot))
  out_tab <- file.path(index_root, db, "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    res$forest_table,
    file.path(out_tab, "Table_Subgroup_TrajectoryClass_WPR_HR.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    res$count_table,
    file.path(out_tab, "Table_Subgroup_TrajectoryClass_WPR_Counts.csv"),
    row.names = FALSE
  )
  fig_db <- file.path(
    index_root, db, "Figures",
    sprintf("Figure S4-%s. Subgroup analysis by trajectory class.pdf", db_lab)
  )
  ggplot2::ggsave(
    fig_db, res$plot,
    width = 14, height = max(6, nrow(res$count_table) * 0.35),
    device = grDevices::cairo_pdf
  )
  file.copy(fig_db, file.path(fig_root, basename(fig_db)), overwrite = TRUE)
  cli::cli_alert_success("[{db_lab}] S4 亚组 n_rows={nrow(res$count_table)}")
  res
}
sg_m <- .run_subgroup("mimic", "MIMIC")
sg_e <- .run_subgroup("eicu", "eICU")
.compose_ab("Figure S4. Subgroup analysis by trajectory class.pdf", layout = "stack")

# ── 4) S10 / S11 / S7 / S8: 3 类按主库（高 WPR = Class 1）对齐 ─────────────
# MIMIC m3 raw: 1=high, 2=mid, 3=low（保持）
# eICU  m3 raw: 1=low,  2=high, 3=mid → 1→3, 2→1, 3→2
eicu_m3_map <- stats::setNames(c(3L, 1L, 2L), c("1", "2", "3"))
mimic_m3_map <- stats::setNames(c(1L, 2L, 3L), c("1", "2", "3"))
utils::write.csv(
  data.frame(
    database = c("MIMIC", "eICU", "eICU", "eICU"),
    model = c("m3", "m3", "m3", "m3"),
    raw_class = c("identity 1,2,3", "1", "2", "3"),
    display_class = c("1=high WPR / high mortality", "3", "1", "2"),
    stringsAsFactors = FALSE
  ),
  file.path(sum_dir, "class_align_s10_s11_WPR.csv"),
  row.names = FALSE
)

.npar <- function(m) {
  aic <- as.numeric(m$AIC)
  ll <- as.numeric(m$loglik)
  if (!is.finite(aic) || !is.finite(ll)) return(NA_real_)
  (aic + 2 * ll) / 2
}
.ave_occ <- function(m, class_map = NULL) {
  pp <- as.data.frame(m$pprob)
  prob_cols <- grep("^prob", names(pp), value = TRUE)
  cls_raw <- as.integer(pp$class)
  cls <- if (is.null(class_map)) cls_raw else
    trajectory_apply_class_swap(cls_raw, class_map)
  ng <- length(prob_cols)
  # AvePP/OCC 仍按原始 JLCM 类计算，再按展示类重贴标签
  tab_raw <- table(factor(cls_raw, levels = seq_len(ng)))
  pi <- as.numeric(prop.table(tab_raw))
  ave <- vapply(seq_len(ng), function(k) {
    idx <- which(cls_raw == k)
    if (!length(idx)) return(NA_real_)
    mean(as.numeric(pp[idx, prob_cols[k]]), na.rm = TRUE)
  }, numeric(1))
  occ <- vapply(seq_len(ng), function(k) {
    if (!is.finite(ave[k]) || ave[k] >= 1 || pi[k] <= 0 || pi[k] >= 1) {
      return(NA_real_)
    }
    (ave[k] / (1 - ave[k])) / (pi[k] / (1 - pi[k]))
  }, numeric(1))
  disp <- if (is.null(class_map)) seq_len(ng) else
    as.integer(class_map[as.character(seq_len(ng))])
  out <- data.frame(
    Class = paste0("Class", disp),
    n = as.integer(tab_raw),
    Proportion_pct = round(100 * pi, 2),
    AvePP = round(ave, 5),
    OCC = round(occ, 2),
    stringsAsFactors = FALSE
  )
  out[order(disp), , drop = FALSE]
}
.mortality_by_class <- function(m, base, class_map = NULL) {
  pp <- as.data.frame(m$pprob)[, c("subject_id_num", "class")]
  if (!is.null(class_map)) {
    pp$class <- trajectory_apply_class_swap(pp$class, class_map)
  }
  d <- merge(base, pp, by = "subject_id_num")
  out <- lapply(sort(unique(d$class)), function(k) {
    x <- d$survival_28d[d$class == k]
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

.make_aligned_supplements <- function(db, db_lab, m3_map) {
  db_dir <- file.path(index_root, db)
  jlcm_path <- file.path(db_dir, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData")
  long3_path <- file.path(db_dir, "step14_trajectory_jlcm/Data/D01_long_WPR_D_3.RData")
  index_path <- file.path(
    block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/data", db, "12_WPR.RData"
  )
  stopifnot(file.exists(jlcm_path), file.exists(long3_path), file.exists(index_path))
  e <- new.env(parent = emptyenv())
  load(jlcm_path, envir = e)
  models_list_with_cov <- e$models_list_with_cov
  model_data_final <- e$model_data_final
  e_long <- new.env(parent = emptyenv())
  load(long3_path, envir = e_long)
  long3 <- e_long$long
  e_ix <- new.env(parent = emptyenv())
  load(index_path, envir = e_ix)
  index_df <- e_ix$index_df
  m1 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m1)
  m2 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m2)
  m3 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m3)
  base <- model_data_final[
    !duplicated(model_data_final$subject_id_num),
    c("subject_id_num", "subject_id", "survival_28d", "survival_time_28d")
  ]

  s7_2 <- .ave_occ(m2); s7_2$Model <- "2-class (primary)"
  s7_3 <- .ave_occ(m3, m3_map); s7_3$Model <- "3-class (supplement)"
  s7 <- dplyr::bind_rows(s7_2, s7_3)[, c(
    "Model", "Class", "n", "Proportion_pct", "AvePP", "OCC"
  )]
  s7_title <- sprintf(
    "Table S7-%s. Average posterior probability and OCC for 2-class and 3-class WPR models",
    db_lab
  )
  s7_fp <- file.path(tab_root, paste0(s7_title, ".xlsx"))
  export_sci_table(
    s7, s7_fp, title = s7_title, sheet = "TableS7",
    table_footnotes = list(
      "AvePP = mean posterior probability of the assigned class; OCC = odds of correct classification (Nagin).",
      "Primary analysis used the 2-class solution; 3-class metrics are shown for reviewer transparency.",
      "3-class labels aligned to MIMIC: Class1 = highest mean WPR / highest 28-day mortality, Class3 = lowest.",
      "OCC >> 5 indicates good classification quality."
    )
  )

  mort2 <- .mortality_by_class(m2, base)
  mort2$Model <- "2-class (primary)"
  mort3 <- .mortality_by_class(m3, base, m3_map)
  mort3$Model <- "3-class (supplement)"
  s8a <- dplyr::bind_rows(mort2, mort3)[, c(
    "Model", "Class", "n", "Events", "Mortality_28d_pct"
  )]
  npar1 <- .npar(m1); npar2 <- .npar(m2); npar3 <- .npar(m3)
  lrt_row <- function(label, m_lo, m_hi, npar_lo, npar_hi) {
    ll_lo <- as.numeric(m_lo$loglik)
    ll_hi <- as.numeric(m_hi$loglik)
    stat <- 2 * (ll_hi - ll_lo)
    df <- npar_hi - npar_lo
    p_naive <- if (is.finite(stat) && is.finite(df) && df > 0) {
      pchisq(stat, df = df, lower.tail = FALSE)
    } else NA_real_
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
  s8b <- dplyr::bind_rows(
    lrt_row("2-class vs 1-class", m1, m2, npar1, npar2),
    lrt_row("3-class vs 2-class", m2, m3, npar2, npar3)
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
      Section = "",
      Col1 = s8a$Model, Col2 = s8a$Class, Col3 = as.character(s8a$n),
      Col4 = as.character(s8a$Events), Col5 = as.character(s8a$Mortality_28d_pct),
      stringsAsFactors = FALSE
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
      "3-class labels aligned to MIMIC: Class1 = highest mean WPR / highest mortality, Class3 = lowest.",
      "Panel B: 2ΔLL is shown for transparency. Naive P is exploratory only.",
      "Primary class solution remains 2-class, locked from the MIMIC published analysis."
    )
  )

  p10 <- .tpj04_make_plot(
    model_obj = models_list_with_cov$m3,
    long_data = long3,
    Index = "WPR",
    D = 3L,
    cycle = 28L,
    id_col = "subject_id",
    font_family = "sans",
    class_map = m3_map
  )
  fig10_db <- file.path(
    db_dir, "Figures",
    sprintf("Figure S10-%s. Trajectory of WPR three latent classes.pdf", db_lab)
  )
  ggplot2::ggsave(fig10_db, p10, width = 10, height = 4.2, device = grDevices::cairo_pdf)
  file.copy(fig10_db, file.path(fig_root, basename(fig10_db)), overwrite = TRUE)

  plot_df <- dplyr::bind_rows(mort2, mort3)
  plot_df$label <- sprintf(
    "%.1f%%\n(%d/%d)", plot_df$Mortality_28d_pct, plot_df$Events, plot_df$n
  )
  plot_df$Class <- factor(
    plot_df$Class,
    levels = c("Class1", "Class2", "Class3")
  )
  p11 <- ggplot2::ggplot(
    plot_df, ggplot2::aes(x = Class, y = Mortality_28d_pct, fill = Class)
  ) +
    ggplot2::geom_col(width = 0.7, color = "grey20", linewidth = 0.2) +
    ggplot2::geom_text(ggplot2::aes(label = label), vjust = -0.15, size = 3, lineheight = 0.9) +
    ggplot2::facet_wrap(~ Model, scales = "free_x") +
    ggplot2::scale_fill_manual(
      values = c("Class1" = "#D55E00", "Class2" = "#E69F00", "Class3" = "#56B4E9"),
      guide = "none"
    ) +
    ggplot2::scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    ggplot2::labs(
      title = "28-day in-hospital mortality by WPR latent class",
      x = NULL, y = "Mortality (%)"
    ) +
    ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold"),
      plot.title = ggplot2::element_text(face = "bold", hjust = 0.5)
    )
  fig11_db <- file.path(
    db_dir, "Figures",
    sprintf("Figure S11-%s. Twenty-eight day mortality by WPR trajectory class.pdf", db_lab)
  )
  ggplot2::ggsave(fig11_db, p11, width = 8.5, height = 4.5, device = grDevices::cairo_pdf)
  file.copy(fig11_db, file.path(fig_root, basename(fig11_db)), overwrite = TRUE)

  for (fp in c(s7_fp, s8_fp)) {
    if (file.exists(fp)) {
      file.copy(fp, file.path(db_dir, "Tables", basename(fp)), overwrite = TRUE)
    }
  }
  list(s7 = s7, s8a = s8a, mort2 = mort2, mort3 = mort3)
}

sup_m <- .make_aligned_supplements("mimic", "MIMIC", mimic_m3_map)
sup_e <- .make_aligned_supplements("eicu", "eICU", eicu_m3_map)
.compose_ab("Figure S10. Trajectory of WPR three latent classes.pdf", layout = "stack")
.compose_ab("Figure S11. Twenty-eight day mortality by WPR trajectory class.pdf", layout = "stack")

if (exists("render_queued_tables", mode = "function")) {
  ctx <- list(config = list(project = list(database = "eICU+MIMIC")))
  tryCatch(render_queued_tables(ctx), error = function(e) {
    cli::cli_alert_warning("render_queued_tables: {e$message}")
  })
}

# 根目录只留无库标签主图；S3 保留单库 MIMIC
tagged <- list.files(
  fig_root, pattern = "-(eICU|MIMIC)\\.", full.names = TRUE, ignore.case = TRUE
)
if (length(tagged)) unlink(tagged)
flat_pdf <- list.files(fig_root, pattern = "^Figure .+\\.pdf$", full.names = TRUE)
for (fp in flat_pdf) {
  file.copy(fp, file.path(pdf_dir, basename(fp)), overwrite = TRUE)
}

readme <- c(
  "# Tables（WPR 双库发表用）",
  "",
  "角色对齐 `Prognosis_Trajectory_38882552/by_index/【success】WPR`；",
  "双库用预后命名 `Table N-MIMIC` / `Table N-eICU`。",
  "",
  "| 编号 | 内容 | 口径 |",
  "|---|---|---|",
  "| Table 1 | 基线特征 | 双库 |",
  "| Table 2 | 选类指标 | 双库 |",
  "| Table 3 | 分段/时变 HR | **仅 MIMIC**（主库 cut=7；eICU 已归档） |",
  "| Table S1 | 插补前后基线 | 双库 |",
  "| Table S2 | 正态性 | 双库 |",
  "| Table S3 | 单因素 | 双库 |",
  "| Table S4 | VIF（单因素筛） | 双库 |",
  "| Table S5 | 按轨迹类基线 | 双库 |",
  "| Table S6 | 后验分类表 | 双库 |",
  "| Table S7 | 2类+3类 AvePP / OCC | 双库；3 类标签对齐主库 |",
  "| Table S8 | 类间28天死亡 + 近似LRT | 双库；3 类标签对齐主库 |",
  "| Table S9 | WPR HR 换算 | 双库 |",
  "",
  "Figure S3 仅主库 MIMIC 切点搜索（cut=7），不拼 eICU。",
  "Figure S4 亚组锁定：Age(65) / Gender / Hypertension / CKD / Hepatitis / Pneumonia / COPD。",
  "Figure S10/S11 三类：Class1=最高均值 WPR/最高 28 天死亡，Class3=最低。"
)
writeLines(readme, file.path(tab_root, "README.md"), useBytes = TRUE)

pub_figure_ensure_formats(fig_root, config = config)

cli::cli_alert_success("AP WPR dual pub consistency 修复完成")
cat("S4 MIMIC vars:\n")
print(unique(sg_m$count_table$subgroup_var))
cat("S4 eICU vars:\n")
print(unique(sg_e$count_table$subgroup_var))
cat("S8 MIMIC 3-class:\n")
print(sup_m$mort3)
cat("S8 eICU 3-class:\n")
print(sup_e$mort3)
