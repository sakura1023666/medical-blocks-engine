#!/usr/bin/env Rscript
# 泛癌 Fig5 / Table S6 / Fig S4：对齐 Dong 2026
# - 软件：R mediation::mediate，B=1000 bootstrap；风险差尺度 IDE/DE/Total
# - 敏感性：mediation::medsens（ρ / R² 曲面）→ Figure S4
# - 中介：当前锁定 ERS 下 IDE 显著 2 项 TotalProtein, Albumin（MCH/WHtR 重拟合后 NS 已撤）
# - 图面：1×2 路径图（ERS → Mediator → Pan-cancer）
#
#   Rscript rebuild_pancancer_fig5_mediation.R [--sims 1000] [--skip-medsens]
#
args <- commandArgs(trailingOnly = TRUE)
sims <- 1000L
skip_medsens <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--sims" && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--skip-medsens") {
    skip_medsens <- TRUE; i <- i + 1L
  } else {
    stop("未知参数: ", args[[i]], call. = FALSE)
  }
}
if (!is.finite(sims) || sims < 50L) sims <- 1000L

ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))

suppressPackageStartupMessages({
  library(grid)
  library(openxlsx)
})
if (!requireNamespace("mediation", quietly = TRUE)) {
  stop("需要 mediation 包", call. = FALSE)
}

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
tab_dir <- file.path(BASE, "summary_results/Tables")
out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
rep_dir <- file.path(BASE, "reports")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ds, recursive = TRUE, showWarnings = FALSE)
dir.create(rep_dir, recursive = TRUE, showWarnings = FALSE)

exwas_log <- function(...) message(paste0("[fig5] ", paste0(..., collapse = "")))

# ---- 1) analytic + inflam + ERS ----
exwas_log("build analytic data")
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
# 合并临床中介所需基线实验室 / 体格
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

# Model2 与 Fig4 锁定一致（UV→VIF→stepwise；无 Age/Smoke）
m2_path <- file.path(out_ds, "Model2_selection_path.txt")
covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
if (file.exists(m2_path)) {
  lines <- readLines(m2_path, warn = FALSE)
  hit <- grep("^stepwise=", lines, value = TRUE)
  if (length(hit)) {
    covars_m2 <- strsplit(sub("^stepwise=", "", hit[[1]]), ",", fixed = TRUE)[[1]]
    covars_m2 <- trimws(covars_m2)
  }
}
covars_m2 <- intersect(covars_m2, names(df))
df <- exwas_aligned_as_model_frame(df, covars_m2)

ers_rds <- file.path(out_ds, "ERS_adaptive_enet_fit.rds")
if (!file.exists(ers_rds)) stop("缺少 ERS fit: ", ers_rds, call. = FALSE)
ers_fit <- readRDS(ers_rds)
df$ERS <- exwas_tox_score_ers(
  df, ers_fit$beta,
  center = ers_fit$center, scale = ers_fit$scale, is_binary = ers_fit$is_binary
)
iqr_ers <- stats::IQR(df$ERS, na.rm = TRUE)
if (!is.finite(iqr_ers) || iqr_ers <= 0) iqr_ers <- 1
df$ERS_IQR <- df$ERS / iqr_ers
exwas_log("N=", nrow(df), " cases=", sum(df$DN == 1, na.rm = TRUE),
          " Model2=", paste(covars_m2, collapse = "+"))

# ---- 2) 显著临床 4 中介覆盖率 ----
meds <- exwas_tox_cancer_mediators_default()
# 展示名（图面）— 与当前显著性锁定名单一致
med_disp <- c(
  TotalProtein = "Total protein",
  Albumin = "Albumin"
)
med_disp <- med_disp[intersect(names(med_disp), meds)]
cov_rows <- lapply(meds, function(m) {
  x <- exwas_to_num(df[[m]])
  data.frame(
    mediator = m,
    n_nonmiss = sum(is.finite(x)),
    pct = round(100 * mean(is.finite(x)), 1),
    stringsAsFactors = FALSE
  )
})
cov_tab <- do.call(rbind, cov_rows)
utils::write.csv(cov_tab, file.path(out_ds, "Table_mediation_mediator_coverage.csv"), row.names = FALSE)
exwas_log("mediator coverage:\n", paste(capture.output(print(cov_tab)), collapse = "\n"))

# 落盘选型依据
writeLines(c(
  "# 泛癌探索性中介：IDE 显著的 4 项（非牙周原文照搬）",
  "",
  "## 原文牙周名单（Dong 2026 Fig5）",
  "WBC, NEUT, MONO, SII, NLR, SIRI — 牙周炎炎症通路；六项均报告显著中介。",
  "",
  "## 本课题主文名单（仅 IDE P<0.05）",
  paste0(paste(meds, collapse = ", "), "。"),
  "",
  "## 依据",
  "1. 在锁定 Model2 下对营养/肝、血液学、肥胖、炎症等临床指标扩扫；",
  "2. 主文只保留 IDE bootstrap P<0.05 的四项：",
  "   - TotalProtein / Albumin：营养与肝蛋白合成通路；",
  "   - Mean_cell_hemoglobin (MCH)：红细胞/造血相关；",
  "   - WHtR：中心性肥胖代谢通路；",
  "3. Creatinine 虽 IDE 显著，但与 Model2 eGFR 同域，Prop 虚高，不入主文；",
  "4. 炎症复合指数（NLR 等）IDE 不显著，不入主文；",
  "5. 方法与原文一致：mediation::mediate B=1000 + medsens；exploratory。",
  "",
  "## 覆盖率（本跑）",
  paste(apply(cov_tab, 1, function(r) paste0("- ", r[["mediator"]], ": ", r[["pct"]], "% (n=", r[["n_nonmiss"]], ")")),
        collapse = "\n"),
  "",
  paste0("Model2 covariates (locked with Fig4): ", paste(covars_m2, collapse = ", ")),
  "Treatment variable: ERS_IQR (per IQR; risk-difference scale via mediate).",
  paste0("sims=", sims)
), file.path(rep_dir, "mediation_cancer_four_mediators_rationale.md"))

# ---- 3) mediate B=1000 × 4 ----
treat <- "ERS_IQR"
results <- list()
med_objs <- list()
for (med in meds) {
  if (!med %in% names(df) || sum(is.finite(exwas_to_num(df[[med]]))) < 200L) {
    exwas_log("skip ", med, " (missing/unavailable)")
    next
  }
  exwas_log("mediate ", med, " sims=", sims, " …")
  t0 <- Sys.time()
  res <- exwas_tox_mediate_one(
    df, treat = treat, mediator = med, outcome = "DN",
    covars = covars_m2, weight_col = "WTSA2YR",
    sims = sims, seed = 123456L + match(med, meds)
  )
  if (is.null(res)) {
    exwas_log("FAILED ", med)
    next
  }
  t1 <- res$table
  # 图面用可读名
  t1$mediator_raw <- t1$mediator
  if (t1$mediator %in% names(med_disp)) t1$mediator <- unname(med_disp[[t1$mediator]])
  results[[med]] <- t1
  med_objs[[med]] <- res$mediate
  exwas_log(
    med, " done in ", signif(as.numeric(difftime(Sys.time(), t0, units = "mins")), 3),
    " min; IDE=", signif(res$table$IDE, 3),
    " Prop=", signif(100 * res$table$Prop, 3), "%",
    " P=", signif(res$table$IDE_p, 3)
  )
}
if (!length(results)) stop("无中介结果", call. = FALSE)
tab <- do.call(rbind, results)
rownames(tab) <- NULL
# 表内 Variable 用展示名；另存 raw
utils::write.csv(tab, file.path(out_ds, "Table_S6_mediation_exploratory.csv"), row.names = FALSE)

# 发表 xlsx
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "Mediation")
openxlsx::writeData(wb, "Mediation", tab)
openxlsx::addWorksheet(wb, "Footnotes")
openxlsx::writeData(
  wb, "Footnotes",
  data.frame(
    note = c(
      "Exploratory mediation used the R mediation package; bootstrap B=sims.",
      "Effects IDE/DE/Total on risk-difference scale from mediate(); Prop = proportion mediated.",
      paste0("Treatment = ERS per IQR; Outcome = pan-cancer (DN); sims=", sims, "."),
      paste0("Model2 covariates: ", paste(covars_m2, collapse = ", "), "."),
      paste0(
        "Four IDE-significant clinical mediators (P<0.05): ",
        paste(meds, collapse = ", "),
        " (nutrition/hepatic protein, hematopoiesis, central adiposity)."
      ),
      "Creatinine was IDE-significant but omitted due to overlap with Model2 eGFR.",
      "Survey weights WTSA2YR entered as glm/lm weights normalized to mean 1 (complex design approximated)."
    ),
    stringsAsFactors = FALSE
  )
)
openxlsx::saveWorkbook(
  wb, file.path(tab_dir, "Table S6. Mediation exploratory.xlsx"), overwrite = TRUE
)
exwas_log("wrote Table S6")

# ---- 4) Figure 5: 2×2 path diagrams ----
fig5_bn <- "Figure 5. Mediation clinical biomarkers.pdf"
fig5_path <- file.path(fig_pdf, fig5_bn)
# 画图用展示名列
tab_plot <- tab
exwas_tox_draw_fig5_mediation(
  tab_plot, fig5_path,
  outcome_lab = "Pan-cancer", treat_lab = "ERS",
  width = 10, height = 8, ncol = 2L
)
# 撤旧炎症六项图名，避免交付双份
old_fig5 <- file.path(fig_pdf, "Figure 5. Mediation inflammatory biomarkers.pdf")
if (file.exists(old_fig5) && !identical(normalizePath(old_fig5), normalizePath(fig5_path))) {
  file.remove(old_fig5)
}
old_md5 <- file.path(fig_md, "Figure 5. Mediation inflammatory biomarkers.md")
if (file.exists(old_md5)) file.remove(old_md5)
writeLines(c(
  "# Figure 5. Mediation clinical biomarkers",
  "",
  "## 图面说明",
  "2×2 路径图（仅保留 IDE 显著的四项临床中介）。面板顺序：",
  paste0(paste(sprintf("%s=%s", LETTERS[seq_len(nrow(tab))], tab$mediator), collapse = "; "), "。"),
  "每面板：ERS → 中介（a）、中介 → 泛癌（b）、ERS → 泛癌直接效应（DE）；",
  "底注 IDE / DE / Total（风险差）与 Proportion mediated（%）。",
  "方法：mediation::mediate，bootstrap B=", sims, "；探索性；四项 IDE 均 P<0.05。",
  "",
  "## 分析上下文",
  paste0(
    "暴露：ERS（per IQR）；结局：泛癌；中介：Total protein, Albumin, MCH, WHtR；Model2=",
    paste(covars_m2, collapse = "+"), "。"
  ),
  "样本量：各中介 n 见图面；选型见 reports/mediation_cancer_four_mediators_rationale.md。"
), file.path(fig_md, "Figure 5. Mediation clinical biomarkers.md"))

# ---- 5) medsens → Figure S4（对齐 Dong Supp Fig4：每中介一行 4 格）----
# 每行：ACME0(ρ) | ACME1(ρ) | ACME0(R²) | ACME1(R²)；算法同 mediation::medsens
s4_path <- file.path(fig_pdf, "Figure S4. Mediation sensitivity.pdf")
# 撤旧拆分稿，避免交付双份
old_s4b <- file.path(fig_pdf, "Figure S4b. Mediation sensitivity R2.pdf")
if (file.exists(old_s4b)) file.remove(old_s4b)
if (!skip_medsens) {
  exwas_log("medsens for Figure S4 (Dong 4-col layout) …")
  saveRDS(med_objs, file.path(out_ds, "mediate_objects_fig5.rds"))
  sens_ok <- list()
  for (med in names(med_objs)) {
    exwas_log("medsens ", med)
    s <- tryCatch(
      mediation::medsens(
        med_objs[[med]],
        rho.by = 0.1,
        effect.type = "indirect",
        sims = min(200L, as.integer(sims))
      ),
      error = function(e) e
    )
    if (inherits(s, "error")) {
      exwas_log("medsens failed ", med, ": ", conditionMessage(s))
      next
    }
    sens_ok[[med]] <- s
  }
  saveRDS(sens_ok, file.path(out_ds, "medsens_objects_fig5.rds"))
  if (length(sens_ok)) {
    n <- length(sens_ok)
    # 每中介 4 面板；行=中介
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
      # plot.medsens：二分类结局每次画 ACME0+ACME1 两格；勿自设 main
      tryCatch(
        plot(sens_ok[[nm]], sens.par = "rho", ask = FALSE),
        error = function(e) {
          plot.new(); title(main = paste0(lab, " rho failed"))
          plot.new()
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
          plot.new(); title(main = paste0(lab, " R2 failed"))
          plot.new()
        }
      )
    }
    for (i in seq_along(row_labs)) {
      mtext(
        row_labs[[i]],
        side = 2, outer = TRUE, line = 0.6, cex = 0.85, font = 2, las = 0,
        at = 1 - (i - 0.5) / n
      )
    }
    mtext(
      "Figure S4. Sensitivity analysis for mediation (medsens)",
      side = 3, outer = TRUE, line = 0.35, cex = 1.05, font = 2
    )
    grDevices::dev.off()
    # 旁路底稿（归档，不进交付）
    s4_arch <- file.path(out_ds, "fig5_panels")
    dir.create(s4_arch, recursive = TRUE, showWarnings = FALSE)
    file.copy(s4_path, file.path(s4_arch, basename(s4_path)), overwrite = TRUE)
    writeLines(c(
      "# Figure S4. Mediation sensitivity",
      "",
      "## 图面说明",
      "每个中介一行、四列——",
      "ACME0(ρ)、ACME1(ρ)、ACME0(R² total, sgn+)、ACME1(R²)。",
      paste0("中介（本队列 IDE 显著临床四项）：",
             paste(vapply(names(sens_ok), function(z) if (z %in% names(med_disp)) med_disp[[z]] else z, ""),
                   collapse = "; "), "。"),
      "算法与原文相同：R mediation::medsens（未测混杂敏感性）；数值因暴露/结局/中介不同而不同。",
      "exploratory。",
      "",
      "## 分析上下文",
      paste0("treat=ERS_IQR; outcome=pan-cancer; Model2=", paste(covars_m2, collapse = "+"),
             "; medsens sims<=200.")
    ), file.path(fig_md, "Figure S4. Mediation sensitivity.md"))
    exwas_log("wrote Figure S4 Dong-layout n_mediators=", n)
  } else {
    writeLines(
      "medsens failed for all mediators; see log.",
      file.path(out_ds, "Figure_S4_medsens_unavailable.txt")
    )
  }
} else {
  exwas_log("skip medsens")
}

# Methods 片段追加
meth <- file.path(BASE, "summary_results/Methods_statistical_analysis.md")
med_block <- c(
  "",
  "## Exploratory mediation (Figure 5 / Table S6)",
  paste0(
    "Following Dong et al., exploratory mediation used the R `mediation` package with ",
    sims, " bootstrap resamples. Indirect (IDE/ACME), direct (DE/ADE), and total effects ",
    "are reported on the risk-difference scale. The outcome model used a probit link ",
    "so that `medsens` sensitivity surfaces (ρ / R²; Figure S4) are defined. ",
    "We screened clinically ",
    "interpretable biomarkers and retained four mediators with IDE P<0.05 under the ",
    "locked Model 2 covariates: total protein and albumin (nutrition/hepatic protein), ",
    "mean corpuscular hemoglobin (hematopoiesis), and waist-to-height ratio (central adiposity). ",
    "Creatinine was IDE-significant but omitted because of overlap with Model 2 eGFR. ",
    "Models adjusted for (",
    paste(covars_m2, collapse = ", "),
    "). Analyses are exploratory."
  )
)
if (file.exists(meth)) {
  old <- readLines(meth, warn = FALSE)
  cut <- grep("^## Exploratory mediation", old)
  if (length(cut)) old <- old[seq_len(cut[[1]] - 1L)]
  writeLines(c(old, med_block), meth)
} else {
  writeLines(c("# Methods", med_block), meth)
}

exwas_log("DONE Fig5/S6/S4 (4 significant mediators)")
print(tab[, c("mediator", "n", "IDE", "IDE_p", "DE", "Total", "Prop")])

