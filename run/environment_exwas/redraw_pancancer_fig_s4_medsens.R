#!/usr/bin/env Rscript
# Figure S4：对齐 Dong Supp Fig4 版式（每中介一行：ACME0ρ | ACME1ρ | ACME0 R² | ACME1 R²）
# 算法与原文相同：mediation::medsens；中介为本队列 IDE 显著临床四项（非牙周炎症六项）
#
#   Rscript redraw_pancancer_fig_s4_medsens.R [--sims 200]
#
args <- commandArgs(trailingOnly = TRUE)
sims <- 200L
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--sims" && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else {
    stop("未知参数: ", args[[i]], call. = FALSE)
  }
}
if (!is.finite(sims) || sims < 50L) sims <- 200L

ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))

if (!requireNamespace("mediation", quietly = TRUE)) stop("需要 mediation", call. = FALSE)

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

message("[S4] build analytic + ERS")
built <- exwas_tox_build_cancer_table("pancancer", file.path(BASE, "data"), 20L)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox)$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, 1 / 3, "cycle", sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
df <- exwas_tox_merge_inflam(df, file.path(BASE, "data"))
e_base <- new.env()
load(file.path(BASE, "data/D01_baseline_NHANES_0920.RData"), envir = e_base)
b0 <- e_base$baseline
b0$cycle <- as.character(b0$Source_File)
b0$SEQN <- as.character(b0$ID)
lab_keep <- c(
  "TotalProtein", "Albumin", "Mean_cell_hemoglobin",
  "Waist_circumference", "Height", "Hematocrit", "Creatinine"
)
lab_keep <- setdiff(intersect(lab_keep, names(b0)), names(df))
if (length(lab_keep)) {
  df <- merge(
    df, b0[, c("cycle", "SEQN", lab_keep), drop = FALSE],
    by = c("cycle", "SEQN"), all.x = TRUE
  )
}
df$WHtR <- ifelse(
  is.finite(exwas_to_num(df$Height)) & exwas_to_num(df$Height) > 0,
  exwas_to_num(df$Waist_circumference) / exwas_to_num(df$Height),
  NA_real_
)
m2_path <- file.path(out_ds, "Model2_selection_path.txt")
covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
if (file.exists(m2_path)) {
  hit <- grep("^stepwise=", readLines(m2_path, warn = FALSE), value = TRUE)
  if (length(hit)) {
    covars_m2 <- trimws(strsplit(sub("^stepwise=", "", hit[[1]]), ",", fixed = TRUE)[[1]])
  }
}
covars_m2 <- intersect(covars_m2, names(df))
df <- exwas_aligned_as_model_frame(df, covars_m2)
ers_fit <- readRDS(file.path(out_ds, "ERS_adaptive_enet_fit.rds"))
df$ERS <- exwas_tox_score_ers(
  df, ers_fit$beta,
  center = ers_fit$center, scale = ers_fit$scale, is_binary = ers_fit$is_binary
)
iqr_ers <- stats::IQR(df$ERS, na.rm = TRUE)
if (!is.finite(iqr_ers) || iqr_ers <= 0) iqr_ers <- 1
df$ERS_IQR <- df$ERS / iqr_ers

meds <- exwas_tox_cancer_mediators_default()
med_disp <- c(
  TotalProtein = "Total protein",
  Albumin = "Albumin",
  Mean_cell_hemoglobin = "MCH",
  WHtR = "WHtR"
)

message("[S4] mediate + medsens (layout only; Table S6 仍以 B=1000 主文为准)")
sens_ok <- list()
for (med in meds) {
  if (!med %in% names(df)) next
  message("[S4] mediate ", med, " sims=", sims)
  res <- exwas_tox_mediate_one(
    df, treat = "ERS_IQR", mediator = med, outcome = "DN",
    covars = covars_m2, weight_col = "WTSA2YR",
    sims = sims, seed = 123456L + match(med, meds)
  )
  if (is.null(res)) {
    message("[S4] mediate FAILED ", med)
    next
  }
  s <- tryCatch(
    mediation::medsens(
      res$mediate,
      rho.by = 0.1,
      effect.type = "indirect",
      sims = min(150L, as.integer(sims))
    ),
    error = function(e) e
  )
  if (inherits(s, "error")) {
    message("[S4] medsens FAILED ", med, ": ", conditionMessage(s))
    next
  }
  sens_ok[[med]] <- s
  message("[S4] ok ", med)
}
if (!length(sens_ok)) stop("medsens 全部失败", call. = FALSE)
saveRDS(sens_ok, file.path(out_ds, "medsens_objects_fig5.rds"))

n <- length(sens_ok)
s4_path <- file.path(fig_pdf, "Figure S4. Mediation sensitivity.pdf")
old_s4b <- file.path(fig_pdf, "Figure S4b. Mediation sensitivity R2.pdf")
if (file.exists(old_s4b)) file.remove(old_s4b)

grDevices::cairo_pdf(s4_path, width = 11.5, height = max(8.5, 2.35 * n), family = "serif")
op <- par(
  mfrow = c(n, 4L),
  mar = c(3.6, 3.8, 2.2, 0.6),
  oma = c(0.2, 2.4, 1.6, 0.2),
  family = "serif",
  ask = FALSE
)
on.exit(par(op), add = TRUE)
row_labs <- character(0)
for (nm in names(sens_ok)) {
  lab <- if (nm %in% names(med_disp)) med_disp[[nm]] else nm
  row_labs <- c(row_labs, lab)
  tryCatch(
    plot(sens_ok[[nm]], sens.par = "rho", ask = FALSE),
    error = function(e) {
      plot.new(); title(main = paste0(lab, " rho failed")); plot.new()
    }
  )
  tryCatch(
    plot(
      sens_ok[[nm]],
      sens.par = "R2",
      r.type = "total",
      sign.prod = "positive",
      ask = FALSE
    ),
    error = function(e) {
      plot.new(); title(main = paste0(lab, " R2 failed")); plot.new()
    }
  )
}
for (i in seq_along(row_labs)) {
  mtext(
    row_labs[[i]],
    side = 2, outer = TRUE, line = 0.7, cex = 0.85, font = 2, las = 0,
    at = 1 - (i - 0.5) / n
  )
}
mtext(
  "Figure S4. Sensitivity analysis for mediation (medsens)",
  side = 3, outer = TRUE, line = 0.35, cex = 1.05, font = 2
)
grDevices::dev.off()
message("wrote ", s4_path, " n_mediators=", n)

writeLines(c(
  "# Figure S4. Mediation sensitivity",
  "",
  "## 图面说明",
  "对齐 Dong Supplementary Figure 4：每个中介一行、四列——",
  "ACME0(ρ)、ACME1(ρ)、ACME0(R² total, sgn+)、ACME1(R²)。",
  paste0(
    "中介（本队列 IDE 显著临床四项，非原文牙周炎症六项）：",
    paste(row_labs, collapse = "; "), "。"
  ),
  "算法与原文相同：R `mediation::medsens`；数值因暴露(ERS)/结局(泛癌)/中介不同而不同。",
  "exploratory。主文 Table S6 / Figure 5 仍以 bootstrap B=1000 为准。",
  "",
  "## 分析上下文",
  paste0(
    "treat=ERS_IQR; outcome=pan-cancer; Model2=",
    paste(covars_m2, collapse = "+"),
    "; mediate sims=", sims, " (S4 重绘); medsens sims<=150."
  )
), file.path(fig_md, "Figure S4. Mediation sensitivity.md"))

message("DONE Fig S4 Dong-layout")
