#!/usr/bin/env Rscript
# One-off reviewer supplements for AP WPR trajectory (do NOT renumber existing pubs).
# Adds root Table S7–S9 + Figure S10–S11; writes Methods note; refreshes four formats.
# Usage:
#   Rscript run/trajectory_prognosis/supplement_wpr_reviewer_responses.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(lcmm)
  library(splines)
  library(survival)
})

root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
wpr_root <- file.path(
  root, "41_AP/Prognosis_Trajectory_38882552",
  "by_index", "【success】WPR"
)
stopifnot(dir.exists(wpr_root))

engine <- {
  cand <- c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", ""),
    "/mnt/e/01block/01Block-new-Final",
    getwd()
  )
  cand <- cand[nzchar(cand) & dir.exists(cand)]
  cand[[1L]]
}
setwd(engine)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(engine, "R/trajectory_paper_tables.R"), local = FALSE)
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)

jlcm_path <- file.path(
  wpr_root, "mimic/step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"
)
long3_path <- file.path(
  wpr_root, "mimic/step14_trajectory_jlcm/Data/D01_long_WPR_D_3.RData"
)
index_path <- file.path(root, "41_AP/Prognosis_Trajectory_38882552/data/mimic/12_WPR.RData")
stopifnot(file.exists(jlcm_path), file.exists(long3_path), file.exists(index_path))

load(jlcm_path) # models_list_with_cov, model_data_final
e_long <- new.env(parent = emptyenv())
load(long3_path, envir = e_long)
long3 <- e_long$long
e_ix <- new.env(parent = emptyenv())
load(index_path, envir = e_ix)
index_df <- e_ix$index_df

m1 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m1)
m2 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m2)
m3 <- trajectory_unwrap_jointlcmm(models_list_with_cov$m3)

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

base <- model_data_final[!duplicated(model_data_final$subject_id_num),
                         c("subject_id_num", "subject_id", "survival_28d", "survival_time_28d")]

tab_dir <- file.path(wpr_root, "Tables")
fig_dir <- file.path(wpr_root, "Figures")
sum_dir <- file.path(tab_dir, "Summary")
dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
mimic_tab <- file.path(wpr_root, "mimic", "Tables")
mimic_fig <- file.path(wpr_root, "mimic", "Figures")
dir.create(mimic_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(mimic_fig, recursive = TRUE, showWarnings = FALSE)

# ── Table S7: 3-class AvePP / OCC (+ 2-class side-by-side for transparency) ──
s7_2 <- .ave_occ(m2)
s7_2$Model <- "2-class (primary)"
s7_3 <- .ave_occ(m3)
s7_3$Model <- "3-class (supplement)"
s7 <- dplyr::bind_rows(s7_2, s7_3)[, c(
  "Model", "Class", "n", "Proportion_pct", "AvePP", "OCC"
)]
s7_title <- "Table S7-MIMIC. Average posterior probability and OCC for 2-class and 3-class WPR models"
s7_fp <- file.path(tab_dir, paste0(s7_title, ".xlsx"))
export_sci_table(
  s7, s7_fp, title = s7_title, sheet = "TableS7",
  table_footnotes = list(
    "AvePP = mean posterior probability of the assigned class; OCC = odds of correct classification (Nagin).",
    "Primary analysis used the 2-class solution; 3-class metrics are shown for reviewer transparency.",
    "OCC >> 5 indicates good classification quality."
  )
)

# ── Table S8: mortality by class + approximate LRT (not formal BLRT) ─────────
mort2 <- .mortality_by_class(m2, base)
mort2$Model <- "2-class (primary)"
mort3 <- .mortality_by_class(m3, base)
mort3$Model <- "3-class (supplement)"
s8a <- dplyr::bind_rows(mort2, mort3)[, c(
  "Model", "Class", "n", "Events", "Mortality_28d_pct"
)]

npar1 <- .npar(m1)
npar2 <- .npar(m2)
npar3 <- .npar(m3)
lrt_row <- function(label, m_lo, m_hi, npar_lo, npar_hi) {
  ll_lo <- as.numeric(m_lo$loglik)
  ll_hi <- as.numeric(m_hi$loglik)
  stat <- 2 * (ll_hi - ll_lo)
  df <- npar_hi - npar_lo
  p_naive <- if (is.finite(stat) && is.finite(df) && df > 0) {
    pchisq(stat, df = df, lower.tail = FALSE)
  } else {
    NA_real_
  }
  data.frame(
    Comparison = label,
    LogLik_simpler = round(ll_lo, 1),
    LogLik_complex = round(ll_hi, 1),
    LRT_2deltaLL = round(stat, 2),
    Delta_npar = round(df, 1),
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

s8_title <- "Table S8-MIMIC. Class-specific 28-day mortality and approximate likelihood-ratio comparisons"
s8_fp <- file.path(tab_dir, paste0(s8_title, ".xlsx"))
# Panel-style single sheet: mortality block then LRT block with blank separator
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
  data.frame(
    Section = "", Col1 = "", Col2 = "", Col3 = "", Col4 = "", Col5 = "",
    stringsAsFactors = FALSE
  ),
  data.frame(
    Section = "B. Approximate nested LRT (not formal BLRT/LMR-LRT)",
    Col1 = "Comparison", Col2 = "LL simpler", Col3 = "LL complex",
    Col4 = "2ΔLL", Col5 = "Naive P",
    stringsAsFactors = FALSE
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
names(s8_body) <- c(
  "Section", "V1", "V2", "V3", "V4", "V5"
)
export_sci_table(
  s8_body, s8_fp, title = s8_title, sheet = "TableS8",
  table_footnotes = list(
    "Panel A: event = 28-day in-hospital death (survival_28d).",
    "Panel B: 2ΔLL is shown for transparency. For mixture models the LRT is not chi-square distributed; formal BLRT/LMR-LRT were not implemented in the current pipeline. Naive P is exploratory only.",
    "Primary class solution remains 2-class for sample-size stability (high-risk class n=45 vs 3-class smallest class n=25)."
  )
)

# Also write clean CSVs for audit
utils::write.csv(
  s8a, file.path(sum_dir, "TableS8_mortality_by_class_WPR.csv"), row.names = FALSE
)
utils::write.csv(
  s8b, file.path(sum_dir, "TableS8_approx_LRT_WPR.csv"), row.names = FALSE
)

# ── Table S9: WPR HR rescaled ────────────────────────────────────────────────
# Univariable HR per 1 unit from published Table S3
hr1 <- 85.456
lo1 <- 26.145
hi1 <- 279.313
ids <- unique(as.character(model_data_final$subject_id))
w1 <- as.numeric(index_df$WPR_1[as.character(index_df$subject_id) %in% ids])
sdw <- stats::sd(w1, na.rm = TRUE)
rescale <- function(delta, label) {
  data.frame(
    Contrast = label,
    Delta = delta,
    HR = sprintf("%.3f", hr1^delta),
    CI_low = sprintf("%.3f", lo1^delta),
    CI_high = sprintf("%.3f", hi1^delta),
    HR_CI = sprintf(
      "%.3f (%.3f-%.3f)", hr1^delta, lo1^delta, hi1^delta
    ),
    stringsAsFactors = FALSE
  )
}
s9 <- dplyr::bind_rows(
  data.frame(
    Contrast = "Per +1.00 unit (as in Table S3)",
    Delta = 1, HR = sprintf("%.3f", hr1),
    CI_low = sprintf("%.3f", lo1), CI_high = sprintf("%.3f", hi1),
    HR_CI = sprintf("%.3f (%.3f-%.3f)", hr1, lo1, hi1),
    stringsAsFactors = FALSE
  ),
  rescale(0.01, "Per +0.01 unit"),
  rescale(0.05, "Per +0.05 unit"),
  rescale(sdw, sprintf("Per +1 SD (SD=%.4f of baseline WPR_1)", sdw))
)
s9$logHR_per_unit_note <- sprintf("ln(HR per 1 unit)=%.3f", log(hr1))
s9_title <- "Table S9-MIMIC. Rescaled univariable HRs for continuous baseline WPR"
s9_fp <- file.path(tab_dir, paste0(s9_title, ".xlsx"))
export_sci_table(
  s9[, c("Contrast", "HR_CI")],
  s9_fp, title = s9_title, sheet = "TableS9",
  table_footnotes = list(
    "Source: univariable Cox HR for WPR in Table S3 (per +1 unit = 85.456, 95%CI 26.145-279.313).",
    "Rescaling uses HR(delta)=HR(1)^delta. Baseline WPR median (IQR) in Table S3: 0.07 (0.05-0.10).",
    sprintf("Baseline WPR_1 SD in JLCM analysis set (n=%d): %.4f.", sum(is.finite(w1)), sdw),
    "Prefer reporting per +0.01 or per 1 SD in the main text; per +1 unit retained for audit."
  )
)
utils::write.csv(s9, file.path(sum_dir, "TableS9_WPR_HR_rescaled.csv"), row.names = FALSE)

# flush table queue
if (exists("render_queued_tables", mode = "function")) {
  # minimal ctx for renderer
  ctx <- list(config = list(project = list(database = "MIMIC")))
  tryCatch(render_queued_tables(ctx), error = function(e) {
    message("render_queued_tables: ", e$message)
  })
}

# ── Figure S10: 3-class trajectory ─────────────────────────────────────────────
font_family <- if (.Platform$OS.type == "windows") "sans" else "sans"
p10 <- .tpj04_make_plot(
  model_obj = models_list_with_cov$m3,
  long_data = long3,
  Index = "WPR",
  D = 3L,
  cycle = 28L,
  id_col = "subject_id",
  font_family = font_family
)
stopifnot(!is.null(p10))
fig10_name <- "Figure S10. Trajectory of WPR three latent classes"
fig10_pdf <- file.path(fig_dir, "pdf", paste0(fig10_name, ".pdf"))
dir.create(dirname(fig10_pdf), recursive = TRUE, showWarnings = FALSE)
ggplot2::ggsave(fig10_pdf, p10, width = 10, height = 4.2, device = grDevices::cairo_pdf)
# also drop a copy at mimic raw figures (not replacing Fig2)
ggplot2::ggsave(
  file.path(mimic_fig, paste0(fig10_name, "-MIMIC.pdf")),
  p10, width = 10, height = 4.2, device = grDevices::cairo_pdf
)

# ── Figure S11: mortality bars 2-class vs 3-class ─────────────────────────────
plot_df <- dplyr::bind_rows(
  dplyr::mutate(mort2, Model = "2-class (primary)"),
  dplyr::mutate(mort3, Model = "3-class (supplement)")
)
plot_df$label <- sprintf("%.1f%%\n(%d/%d)", plot_df$Mortality_28d_pct, plot_df$Events, plot_df$n)
p11 <- ggplot2::ggplot(plot_df, ggplot2::aes(x = Class, y = Mortality_28d_pct, fill = Class)) +
  ggplot2::geom_col(width = 0.7, color = "grey20", linewidth = 0.2) +
  ggplot2::geom_text(ggplot2::aes(label = label), vjust = -0.15, size = 3, lineheight = 0.9) +
  ggplot2::facet_wrap(~ Model, scales = "free_x") +
  ggplot2::scale_fill_manual(values = c(
    "Class1" = "#D55E00", "Class2" = "#E69F00", "Class3" = "#56B4E9"
  ), guide = "none") +
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
fig11_name <- "Figure S11. Twenty-eight day mortality by WPR trajectory class"
fig11_pdf <- file.path(fig_dir, "pdf", paste0(fig11_name, ".pdf"))
ggplot2::ggsave(fig11_pdf, p11, width = 8.5, height = 4.5, device = grDevices::cairo_pdf)
ggplot2::ggsave(
  file.path(mimic_fig, paste0(fig11_name, "-MIMIC.pdf")),
  p11, width = 8.5, height = 4.5, device = grDevices::cairo_pdf
)

# Ensure pdf copies also exist if ensure_formats expects pdf/ only
# pub_figure_ensure_formats will build png/tiff/image_information

# ── Methods note (time axis + endpoint) ─────────────────────────────────────
methods_note <- c(
  "# Methods note — WPR trajectory timing and endpoint (reviewer response)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Trajectory exposure clock",
  "- Daily WPR from hospital/ICU day 1 through day 28 (wide columns WPR_1 ... WPR_28).",
  "- Patients required at least 2 non-missing daily values (min_non_na_days = 2).",
  sprintf("- JLCM analysis set: n = %d patients; %d person-day observations.",
          length(unique(model_data_final$subject_id_num)), nrow(model_data_final)),
  "",
  "## Survival clock / endpoint",
  "- Time zero: hospital admission.",
  "- Event: 28-day in-hospital death (source death_within_hosp_28days → survival_28d = 1).",
  "- Event time: hosp_survival_day capped at 28 days (survival_time_28d).",
  "- Non-events: survival_28d = 0 with administrative censoring at day 28 (not censored at discharge day).",
  "",
  "## Class selection (primary = 2 classes)",
  "- Table 2 metrics retained unchanged.",
  "- 3-class AvePP/OCC, mortality, approximate LRT, and trajectory plot added as Table S7–S8 and Figure S10–S11.",
  "- Primary 2-class retained for sample-size stability (high-risk n=45 vs smallest 3-class n=25).",
  "",
  "## Continuous WPR HR reporting",
  "- Table S3 univariable HR per +1 unit unchanged.",
  "- Clinically readable rescales added in new Table S9 (per +0.01 / +0.05 / +1 SD)."
)
writeLines(methods_note, file.path(sum_dir, "Methods_trajectory_time_and_endpoint_note.txt"))

# ── Update Tables README (append only) ──────────────────────────────────────
readme <- file.path(tab_dir, "README.md")
extra <- c(
  "",
  "## Reviewer supplements (2026-09-22) — additive only",
  "| 编号 | 内容 | 说明 |",
  "|---|---|---|",
  "| Table S7 | 2类+3类 AvePP / OCC | 新增；未改 Table S6 |",
  "| Table S8 | 类间28天死亡 + 近似LRT | 新增；非正式BLRT |",
  "| Table S9 | WPR HR 换算（每0.01/0.05/1SD） | 新增；未改 Table S3 单元格 |",
  "| Figure S10 | 3类 WPR 轨迹 | 新增；未改 Figure 2 |",
  "| Figure S11 | 2类/3类 28天死亡率柱图 | 新增 |",
  "| Summary/Methods_trajectory_time_and_endpoint_note.txt | 时间点与终点口径 | 新增 |"
)
if (file.exists(readme)) {
  write(extra, file = readme, append = TRUE)
} else {
  writeLines(c("# Tables（WPR）", extra), readme)
}

# Mirror new xlsx into mimic/Tables with same filenames
for (fp in c(s7_fp, s8_fp, s9_fp)) {
  if (file.exists(fp)) {
    file.copy(fp, file.path(mimic_tab, basename(fp)), overwrite = TRUE)
  }
}

# ── Four-format export for new figures ──────────────────────────────────────
pub_figure_ensure_formats(
  fig_dir,
  meta = list(
    study = "AP_WPR_trajectory",
    index = "WPR",
    note = "reviewer_supplement_2026-09-22"
  ),
  config = list()
)

message("OK: supplements written under ", wpr_root)
message("NEW tables: ", paste(basename(c(s7_fp, s8_fp, s9_fp)), collapse = " | "))
message("NEW figures: ", fig10_name, " | ", fig11_name)
message("UNCHANGED: Table 1–3, S1–S6; Figure 1–4, S1–S9")

