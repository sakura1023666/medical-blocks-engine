#!/usr/bin/env Rscript
# 将原「无插补完整病例」S5/S7 换成 Dong 原文未做的敏感性：
# 调查加权 ExWAS（WTSA2YR + SDMVPSU + SDMVSTRA×cycle；协变量仍 MICE m=5 Rubin）
# Dong Methods：主 ExWAS 刻意 unweighted；本敏感性专门补加权稳健性。
#
# 用法:
#   Rscript run/environment_exwas/rerun_pancancer_s5_survey_weighted.R
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  root_proj = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L, m = 5L, maxit = 5L, seed = 123456L
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--root" && i < length(args)) { opt$root_proj <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--data-dir" && i < length(args)) { opt$data_dir <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))

root <- opt$root_proj
sum_dir <- file.path(root, "summary_results")
src_pub <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub")
tab_dir <- file.path(sum_dir, "Tables")
fig_pdf <- file.path(sum_dir, "Figures", "pdf")
fig_md <- file.path(sum_dir, "Figures", "image_information")
arch <- file.path(root, "summary_results_delivery_workspace", "archived_complete_case_S5_S7")
dir.create(arch, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
# also mirror into full_pub Tables if present
if (dir.exists(file.path(src_pub, "Tables"))) {
  dir.create(file.path(src_pub, "Tables"), showWarnings = FALSE)
}

exwas_log("==== replace S5/S7 with survey-weighted ExWAS ====")
exwas_log("data=", opt$data_dir)
exwas_log("root=", root)

# archive old complete-case products
old_files <- c(
  file.path(tab_dir, "Table S7. ExWAS without imputation.csv"),
  file.path(tab_dir, "Table S7. ExWAS without imputation.xlsx"),
  file.path(fig_pdf, "Figure S5. ExWAS without imputation.pdf"),
  file.path(fig_md, "Figure S5. ExWAS without imputation.md")
)
for (fp in old_files) {
  if (file.exists(fp)) {
    file.copy(fp, file.path(arch, basename(fp)), overwrite = TRUE)
    unlink(fp)
  }
}

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
ucr0 <- exwas_to_num(d0$URXUCR)
d0 <- d0[is.finite(ucr0) & ucr0 > 0, , drop = FALSE]
ww0 <- exwas_to_num(d0$WTSA2YR)
d0 <- d0[is.finite(ww0) & ww0 > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
df$SDMVSTRA_cyc <- as.integer(
  interaction(as.character(df$cycle), exwas_to_num(df$SDMVSTRA), drop = TRUE, lex.order = TRUE)
)
covars_full <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars_full)
stopifnot(all(c("WTSA2YR", "SDMVPSU", "SDMVSTRA_cyc") %in% names(df)))

lab_map <- stats::setNames(built$code$Exposure, built$code$Labels)
fam_map <- stats::setNames(built$code$Family, built$code$Labels)
disp_of <- function(raw) ifelse(is.na(lab_map[raw]), raw, unname(lab_map[raw]))

exps <- scr$keep
wmap <- stats::setNames(rep("WTSA2YR", length(exps)), exps)
exwas_log("N=", nrow(df), " exposures=", length(exps), " covars=", paste(covars_full, collapse = ","))
exwas_log("survey-weighted mice ExWAS m=", opt$m, " …")

fit <- exwas_run_survey_mice(
  df, "DN", exps, covars_full, weight_map = wmap,
  families = NULL, energy_col = NULL, diet_impute_cols = NULL,
  m = as.integer(opt$m), maxit = as.integer(opt$maxit), seed = as.integer(opt$seed),
  psu = "SDMVPSU", strata = "SDMVSTRA_cyc"
)
s7 <- fit$table
s7$exposure_raw <- sub("_(ln|bin)$", "", s7$exposure)
s7$transform <- ifelse(endsWith(s7$exposure, "_bin"), "binary",
                       ifelse(endsWith(s7$exposure, "_ln"), "log", "other"))
s7$exposure_name <- disp_of(s7$exposure_raw)
s7$family <- unname(fam_map[s7$exposure_raw])
s7$q <- exwas_fdr(s7$p)
s7$analysis <- "survey_weighted_mice_m5"
s7$note_method <- "Dong did not run weighted ExWAS; this replaces complete-case S5/S7"

n_q <- sum(is.finite(s7$q) & s7$q < 0.05, na.rm = TRUE)
n_p <- sum(is.finite(s7$p) & s7$p < 0.05, na.rm = TRUE)
exwas_log("weighted FDR q<0.05=", n_q, " nominal P<0.05=", n_p)

# compare to main unweighted Table2 if present
main_csv <- file.path(src_pub, "Tables", "Table 2. ExWAS toxicant associations.csv")
if (!file.exists(main_csv)) {
  main_csv <- file.path(root, "Output_pancancer_paperflow_age20_full_noSmoke_UCR_WTSA",
                        "Table_2_ExWAS_toxicant_screen.csv")
}
cmp_note <- ""
if (file.exists(main_csv)) {
  main <- utils::read.csv(main_csv, stringsAsFactors = FALSE)
  main_hits <- main$exposure[is.finite(main$q) & main$q < 0.05]
  w_hits <- s7$exposure[is.finite(s7$q) & s7$q < 0.05]
  cmp_note <- sprintf(
    "Main unweighted FDR hits=%d; weighted FDR hits=%d; overlap=%d; weighted-only=%d; main-only=%d.",
    length(main_hits), length(w_hits),
    length(intersect(main_hits, w_hits)),
    length(setdiff(w_hits, main_hits)),
    length(setdiff(main_hits, w_hits))
  )
  exwas_log(cmp_note)
}

out_csv <- "Table S7. ExWAS survey-weighted.csv"
out_fig <- "Figure S5. ExWAS survey-weighted.pdf"
utils::write.csv(s7, file.path(tab_dir, out_csv), row.names = FALSE)
if (dir.exists(file.path(src_pub, "Tables"))) {
  utils::write.csv(s7, file.path(src_pub, "Tables", out_csv), row.names = FALSE)
}

# volcano (Dong Fig2 style)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  s7$logp <- -log10(pmax(s7$p, 1e-300))
  s7$sig_q <- is.finite(s7$q) & s7$q < 0.05
  s7$sig_p <- is.finite(s7$p) & s7$p < 0.05
  present <- sort(unique(stats::na.omit(s7$family)))
  if (!length(present)) {
    s7$family <- "Other"
    present <- "Other"
  }
  s7$family <- factor(s7$family, levels = present)
  lab_idx <- which(s7$sig_q)
  if (!length(lab_idx)) {
    lab_idx <- which(s7$sig_p)
    if (length(lab_idx) > 12L) lab_idx <- lab_idx[order(s7$p[lab_idx])][seq_len(12L)]
  } else if (length(lab_idx) > 14L) {
    lab_idx <- lab_idx[order(s7$q[lab_idx], s7$p[lab_idx])][seq_len(14L)]
  }
  s7$lab <- ""
  s7$lab[lab_idx] <- s7$exposure_name[lab_idx]
  or_rng <- range(s7$OR[is.finite(s7$OR)], na.rm = TRUE)
  pad <- max(0.03, diff(or_rng) * 0.08)
  xlim <- c(or_rng[1] - pad, or_rng[2] + pad)
  .font <- if (requireNamespace("extrafont", quietly = TRUE)) "Times New Roman" else "serif"
  p <- ggplot2::ggplot(s7, ggplot2::aes(x = OR, y = logp, color = family)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, color = "grey55", linewidth = 0.45) +
    ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2, color = "grey55", linewidth = 0.45) +
    ggplot2::geom_point(size = 2.2, alpha = 0.92) +
    ggplot2::scale_x_continuous(limits = xlim, expand = c(0.02, 0)) +
    ggplot2::labs(
      title = "Sensitivity analysis: survey-weighted ExWAS",
      subtitle = sprintf(
        "WTSA2YR + complex survey; covariates MICE m=5 Rubin (same as main). FDR q<0.05: %d; P<0.05: %d. Dong main ExWAS was unweighted.",
        n_q, n_p
      ),
      x = "Odds ratio (per IQR)",
      y = expression(-log[10](P-value)),
      color = NULL
    ) +
    ggplot2::theme_bw(base_size = 11, base_family = .font) +
    ggplot2::theme(legend.position = "top", legend.text = ggplot2::element_text(size = 8))
  if (requireNamespace("ggrepel", quietly = TRUE) && any(nzchar(s7$lab))) {
    p <- p + ggrepel::geom_text_repel(
      data = subset(s7, lab != ""),
      ggplot2::aes(label = lab),
      size = 3.0, family = .font, fontface = "bold",
      max.overlaps = 30, box.padding = 0.35, segment.color = "grey60", seed = 42,
      show.legend = FALSE
    )
  }
  ggplot2::ggsave(file.path(fig_pdf, out_fig), p, width = 9.0, height = 6.6, device = grDevices::cairo_pdf)
}

writeLines(c(
  "# Figure S5. ExWAS survey-weighted",
  "",
  "## 图面说明",
  paste0(
    "替换原「完整病例无插补」敏感性。Dong 主 ExWAS 为不加权；本图为调查加权 ExWAS（WTSA2YR，",
    "SDMVPSU，周期×层），协变量仍 MICE m=5 + Rubin，与主分析同协变量集。",
    sprintf("FDR q<0.05=%d；名义 P<0.05=%d。", n_q, n_p),
    if (nzchar(cmp_note)) paste0(" ", cmp_note) else ""
  ),
  "",
  "## 分析上下文",
  "敏感性（原文未做）；泛癌；同主分析协变量；权重 WTSA2YR。"
), file.path(fig_md, "Figure S5. ExWAS survey-weighted.md"))

# Methods patch
md_path <- file.path(sum_dir, "Methods_statistical_analysis.md")
if (file.exists(md_path)) {
  md <- readLines(md_path, warn = FALSE)
  md <- gsub(
    "Figure S5 unimputed ExWAS",
    "Figure S5 survey-weighted ExWAS (Dong main ExWAS was unweighted; replaces prior complete-case S5)",
    md, fixed = TRUE
  )
  md <- gsub(
    "S5 unimputed",
    "S5 survey-weighted",
    md, fixed = TRUE
  )
  # drop leftover complete-case wording if present
  md <- gsub(
    "complete-case|without imputation|unimputed datasets",
    "survey-weighted ExWAS",
    md, ignore.case = TRUE
  )
  writeLines(md, md_path)
}

# short compare CSV
utils::write.csv(
  data.frame(
    metric = c("n_exposures", "n_FDR_q005", "n_nominal_p005", "compare_to_main"),
    value = c(as.character(nrow(s7)), as.character(n_q), as.character(n_p), cmp_note),
    stringsAsFactors = FALSE
  ),
  file.path(tab_dir, "Table S7. ExWAS survey-weighted_summary.csv"),
  row.names = FALSE
)

exwas_log("写完 ", file.path(tab_dir, out_csv))
exwas_log("写完 ", file.path(fig_pdf, out_fig))
exwas_log("旧完整病例产物归档至 ", arch)
exwas_log("DONE")
