#!/usr/bin/env Rscript
# Align AP WPR dual-db root Figures/Tables to the published
# 【success】WPR set, but dual-database:
#   Figures = A/B 拼图（A=MIMIC, B=eICU）
#   Tables  = 预后命名 Table N-DB. caption，角色对齐原 WPR 根目录
#
#   Rscript run/trajectory_prognosis/align_ap_wpr_dual_pub_to_reference.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(lcmm)
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

source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.root, "R/trajectory_paper_tables.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "R/trajectory_pub_curate.R"), local = FALSE)
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)
source("configs/config_trajectory_prognosis_ap_wpr_dual.R")

fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
arch_root <- file.path(tab_root, "_archive_messy")
dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)
dir.create(arch_root, recursive = TRUE, showWarnings = FALSE)

# ── 1) Restore MIMIC S3 and stage tagged PDFs into root Figures/ (flat) ─────
mimic_s3_src <- file.path(
  index_root, "mimic/Figures/_raw/Figure Piecewise Cox CutSearch WPR.pdf"
)
mimic_s3_dest <- file.path(
  index_root, "mimic/Figures/Figure S3-MIMIC. Piecewise Cox cut point search.pdf"
)
if (file.exists(mimic_s3_src) && !file.exists(mimic_s3_dest)) {
  file.copy(mimic_s3_src, mimic_s3_dest, overwrite = TRUE)
}

# Keep the existing dual Fig1; do not let four-dir leftovers block pairing.
flat_old <- list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE)
if (length(flat_old)) {
  keep_fig1 <- grepl("^Figure 1\\. Flowchart", basename(flat_old), ignore.case = TRUE)
  unlink(flat_old[!keep_fig1])
}

for (db in c("eicu", "mimic")) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  srcs <- list.files(
    file.path(index_root, db, "Figures"),
    pattern = sprintf("^Figure .+-%s\\. .+\\.pdf$", db_lab),
    full.names = TRUE
  )
  # skip per-db Fig1: root already has dual CONSORT
  srcs <- srcs[!grepl("^Figure 1-", basename(srcs))]
  # 不要 Missing overview；S3 只留主库 MIMIC
  srcs <- srcs[!grepl("Missing value overview", basename(srcs), ignore.case = TRUE)]
  srcs <- srcs[!grepl("^Figure S3-eICU", basename(srcs))]
  for (fp in srcs) file.copy(fp, file.path(fig_root, basename(fp)), overwrite = TRUE)
}

# ── 2) Combine paired figures (keep S1; A=MIMIC B=eICU) ─────────────────────
cfg <- config
cfg$dual_db$combine_figures$enable <- TRUE
cfg$dual_db$combine_figures$remove_singles <- TRUE
cfg$dual_db$combine_figures$drop_missing_overview <- FALSE
cfg$dual_db$combine_figures$panel_order <- "secondary_first"
cfg$dual_db$combine_figures$layout_by_role <- list(
  Trajectory = "stack",
  Dynpred = "stack",
  "Dynamic prediction" = "stack",
  "Kaplan Meier" = "stack",
  "latent classes" = "stack",
  Subgroup = "stack",
  Weibull = "stack"
)

.compose_named_pair <- function(stem) {
  a <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  b <- file.path(fig_root, sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  out <- file.path(fig_root, stem)
  if (!file.exists(a) || !file.exists(b)) return(invisible(FALSE))
  ok <- tryCatch({
    .dual_db_compose_pair_pdf(
      a, b, out, layout = "stack",
      label_a = "A. MIMIC", label_b = "B. eICU",
      dpi = 200L, label_cex = 1.15
    )
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("手工拼图失败 {stem}: {e$message}")
    FALSE
  })
  if (isTRUE(ok) && file.exists(out)) {
    unlink(c(a, b))
    cli::cli_alert_success("已拼 {stem}")
  }
  invisible(isTRUE(ok))
}

comb <- dual_db_combine_paired_figures(index_root, cfg, figures_dir = fig_root)
cli::cli_alert_info(
  "拼图 combined={length(comb$combined)} skipped={length(comb$skipped)}"
)
# 不要 Figure S1 Missing overview
# S3 强制主库单图，禁止双库拼图残留
if (file.exists(mimic_s3_src)) {
  file.copy(
    mimic_s3_src,
    file.path(fig_root, "Figure S3. Piecewise Cox cut point search.pdf"),
    overwrite = TRUE
  )
  unlink(list.files(fig_root, pattern = "Figure S3-eICU", full.names = TRUE))
}

# ── 3) Reviewer supplements S7–S9 / S10–S11, both DBs ───────────────────────
.npar <- function(m) {
  aic <- as.numeric(m$AIC)
  ll <- as.numeric(m$loglik)
  if (!is.finite(aic) || !is.finite(ll)) return(NA_real_)
  (aic + 2 * ll) / 2
}
.ave_occ <- function(m) {
  pp <- as.data.frame(m$pprob)
  prob_cols <- grep("^prob", names(pp), value = TRUE)
  cls <- as.integer(pp$class)
  ng <- length(prob_cols)
  tab <- table(factor(cls, levels = seq_len(ng)))
  pi <- as.numeric(prop.table(tab))
  ave <- vapply(seq_len(ng), function(k) {
    idx <- which(cls == k)
    if (!length(idx)) return(NA_real_)
    mean(as.numeric(pp[idx, prob_cols[k]]), na.rm = TRUE)
  }, numeric(1))
  occ <- vapply(seq_len(ng), function(k) {
    if (!is.finite(ave[k]) || ave[k] >= 1 || pi[k] <= 0 || pi[k] >= 1) {
      return(NA_real_)
    }
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
.mortality_by_class <- function(m, base) {
  pp <- as.data.frame(m$pprob)[, c("subject_id_num", "class")]
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
.parse_s3_wpr_hr <- function(xlsx) {
  if (!file.exists(xlsx)) return(NULL)
  raw <- tryCatch(
    openxlsx::read.xlsx(xlsx, colNames = FALSE),
    error = function(e) NULL
  )
  if (is.null(raw) || !nrow(raw)) return(NULL)
  hit <- which(apply(raw, 1L, function(r) any(grepl("^\\s*WPR\\s*$", as.character(r)))))
  if (!length(hit)) {
    hit <- which(apply(raw, 1L, function(r) any(grepl("\\bWPR\\b", as.character(r)))))
  }
  if (!length(hit)) return(NULL)
  row <- as.character(unlist(raw[hit[[1L]], , drop = TRUE]))
  row <- row[!is.na(row) & nzchar(row)]
  # Prefer the HR cell (…, p=…) over descriptive median (Q1, Q3)
  cell <- row[grepl("\\bp\\s*[=<>]", row, ignore.case = TRUE)][1L]
  if (is.na(cell) || !nzchar(cell)) {
    cells <- row[grepl("[0-9.]+\\s*\\(", row)]
    cell <- if (length(cells)) cells[[length(cells)]] else NA_character_
  }
  if (is.na(cell) || !nzchar(cell)) return(NULL)
  nums <- as.numeric(unlist(regmatches(
    cell, gregexpr("[0-9]+\\.[0-9]+|[0-9]+", cell)
  )))
  if (length(nums) < 3L) return(NULL)
  list(hr = nums[[1L]], lo = nums[[2L]], hi = nums[[3L]])
}

.make_db_supplements <- function(db, db_lab) {
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
  s7_3 <- .ave_occ(m3); s7_3$Model <- "3-class (supplement)"
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
      "OCC >> 5 indicates good classification quality."
    )
  )

  mort2 <- .mortality_by_class(m2, base); mort2$Model <- "2-class (primary)"
  mort3 <- .mortality_by_class(m3, base); mort3$Model <- "3-class (supplement)"
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
      "Panel B: 2ΔLL is shown for transparency. Naive P is exploratory only.",
      "Primary class solution remains 2-class, locked from the MIMIC published analysis."
    )
  )

  s3_path <- file.path(
    db_dir, "Tables",
    sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab)
  )
  hr <- .parse_s3_wpr_hr(s3_path)
  ids <- unique(as.character(model_data_final$subject_id))
  w1 <- as.numeric(index_df$WPR_1[as.character(index_df$subject_id) %in% ids])
  sdw <- stats::sd(w1, na.rm = TRUE)
  s9_title <- sprintf(
    "Table S9-%s. Rescaled univariable HRs for continuous baseline WPR",
    db_lab
  )
  s9_fp <- file.path(tab_root, paste0(s9_title, ".xlsx"))
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
      rescale(sdw, sprintf("Per +1 SD (SD=%.4f of baseline WPR_1)", sdw))
    )
    export_sci_table(
      s9, s9_fp, title = s9_title, sheet = "TableS9",
      table_footnotes = list(
        sprintf(
          "Source: univariable Cox HR for WPR in Table S3-%s.",
          db_lab
        ),
        "Rescaling uses HR(delta)=HR(1)^delta.",
        sprintf(
          "Baseline WPR_1 SD in JLCM analysis set (n=%d): %.4f.",
          sum(is.finite(w1)), sdw
        )
      )
    )
  }

  p10 <- .tpj04_make_plot(
    model_obj = models_list_with_cov$m3,
    long_data = long3,
    Index = "WPR",
    D = 3L,
    cycle = 28L,
    id_col = "subject_id",
    font_family = "sans"
  )
  fig10_db <- file.path(
    db_dir, "Figures",
    sprintf("Figure S10-%s. Trajectory of WPR three latent classes.pdf", db_lab)
  )
  ggplot2::ggsave(fig10_db, p10, width = 10, height = 4.2, device = grDevices::cairo_pdf)
  file.copy(fig10_db, file.path(fig_root, basename(fig10_db)), overwrite = TRUE)

  plot_df <- dplyr::bind_rows(
    dplyr::mutate(mort2, Model = "2-class (primary)"),
    dplyr::mutate(mort3, Model = "3-class (supplement)")
  )
  plot_df$label <- sprintf(
    "%.1f%%\n(%d/%d)", plot_df$Mortality_28d_pct, plot_df$Events, plot_df$n
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

  for (fp in c(s7_fp, s8_fp, s9_fp)) {
    if (file.exists(fp)) {
      file.copy(fp, file.path(db_dir, "Tables", basename(fp)), overwrite = TRUE)
    }
  }
  list(s7 = s7_fp, s8 = s8_fp, s9 = s9_fp, mort2 = mort2, mort3 = mort3)
}

sup_e <- .make_db_supplements("eicu", "eICU")
sup_m <- .make_db_supplements("mimic", "MIMIC")

comb2 <- dual_db_combine_paired_figures(index_root, cfg, figures_dir = fig_root)
cli::cli_alert_info(
  "S10/S11 拼图 combined={length(comb2$combined)} skipped={length(comb2$skipped)}"
)
.compose_named_pair("Figure S10. Trajectory of WPR three latent classes.pdf")
.compose_named_pair("Figure S11. Twenty-eight day mortality by WPR trajectory class.pdf")

# ── 4) Realign root table numbers to published WPR roles ────────────────────
.move_if_exists <- function(src, dest_dir) {
  if (!file.exists(src)) return(invisible(FALSE))
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  file.rename(src, file.path(dest_dir, basename(src)))
}
.rename_pub <- function(src, dest) {
  if (!file.exists(src)) return(invisible(FALSE))
  if (file.exists(dest) && !identical(src, dest)) {
    .move_if_exists(dest, arch_root)
  }
  ok <- file.rename(src, dest)
  if (isTRUE(ok)) trajectory_sync_xlsx_a1_from_filename(dest)
  isTRUE(ok)
}

for (db_lab in c("MIMIC", "eICU")) {
  .move_if_exists(
    file.path(tab_root, sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db_lab)),
    arch_root
  )
  .move_if_exists(
    file.path(
      tab_root,
      sprintf("Table S6-%s. Multicollinearity Analysis (VIF, multivariate final).xlsx", db_lab)
    ),
    arch_root
  )
  .rename_pub(
    file.path(
      tab_root,
      sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab)
    ),
    file.path(
      tab_root,
      sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab)
    )
  )
  .rename_pub(
    file.path(tab_root, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab)),
    file.path(tab_root, sprintf("Table S6-%s. Posterior classification table.xlsx", db_lab))
  )
}

if (exists("render_queued_tables", mode = "function")) {
  ctx <- list(config = list(project = list(database = "eICU+MIMIC")))
  tryCatch(render_queued_tables(ctx), error = function(e) {
    cli::cli_alert_warning("render_queued_tables: {e$message}")
  })
}

# ── 5) Four-format export (do not purge S10/S11) ────────────────────────────
# Move any leftover tagged singles out of the root so only combined stems remain
tagged <- list.files(
  fig_root, pattern = "-(eICU|MIMIC)\\.", full.names = TRUE, ignore.case = TRUE
)
if (length(tagged)) unlink(tagged)

pub_figure_ensure_formats(fig_root, config = config)

readme <- c(
  "# Tables（WPR 双库发表用）",
  "",
  "角色对齐 `Prognosis_Trajectory_38882552/by_index/【success】WPR`；",
  "双库用预后命名 `Table N-MIMIC` / `Table N-eICU`。",
  "",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Table 1 | 基线特征 |",
  "| Table 2 | 选类指标 |",
  "| Table 3 | 分段/时变 HR |",
  "| Table S1 | 插补前后基线 |",
  "| Table S2 | 正态性 |",
  "| Table S3 | 单因素 |",
  "| Table S4 | VIF（单因素筛） |",
  "| Table S5 | 按轨迹类基线 |",
  "| Table S6 | 后验分类表 |",
  "| Table S7 | 2类+3类 AvePP / OCC |",
  "| Table S8 | 类间28天死亡 + 近似LRT |",
  "| Table S9 | WPR HR 换算 |",
  "",
  "多因素 / VIF final 仍在分库 `eicu/Tables`、`mimic/Tables`。",
  "",
  "Figures 根目录为双库拼图（A=MIMIC，B=eICU）：Fig1–4 + S1–S11。",
  sprintf("整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
writeLines(readme, file.path(tab_root, "README.md"))

cli::cli_alert_success("已按原 【success】WPR 角色整理双库发表图/表: {index_root}")
