#!/usr/bin/env Rscript
# Table S6 → 对齐 Dong Supplementary Table 6：
# Mediator | Indirect β(95%CI) P | Direct β(95%CI) P | Total β(95%CI) P | Prop (%)
# 中介名单与原文一致：WBC, NEUT, MONO, SII, NLR, SIRI
# ERS 用当前 Fig4 锁定 fit（α=0.9）；Model2 与 Fig4 一致
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s6_dong_style.R [--sims 1000]
#
args <- commandArgs(trailingOnly = TRUE)
sims <- 1000L
i <- 1L
while (i <= length(args)) {
  if (identical(args[[i]], "--sims") && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else {
    stop("未知参数: ", args[[i]], call. = FALSE)
  }
}
if (!is.finite(sims) || sims < 50L) sims <- 1000L

ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}
if (!requireNamespace("mediation", quietly = TRUE)) {
  stop("需要 mediation 包", call. = FALSE)
}

out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
sum_tab <- file.path(BASE, "summary_results/Tables")
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/Tables")
fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ds, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)

exwas_log <- function(...) message("[s6] ", paste0(..., collapse = ""))

# ---- analytic + inflam + ERS ----
exwas_log("build analytic")
built <- exwas_tox_build_cancer_table("pancancer", file.path(BASE, "data"), 20L)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox)$data
scr <- exwas_tox_screen_transform(d1, tox)
df <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, 1 / 3, "cycle", sub("_(ln|bin)$", "", scr$keep)
)$data
df <- exwas_tox_merge_inflam(df, file.path(BASE, "data"))

covars_m2 <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
m2_path <- file.path(out_ds, "Model2_selection_path.txt")
if (file.exists(m2_path)) {
  lines <- readLines(m2_path, warn = FALSE)
  hit <- grep("^stepwise=", lines, value = TRUE)
  if (length(hit)) {
    covars_m2 <- trimws(strsplit(sub("^stepwise=", "", hit[[1]]), ",", fixed = TRUE)[[1]])
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

# 原文 S6 六项炎症中介（名单对齐 Dong）
meds <- c("WBC", "NEUT", "MONO", "SII", "NLR", "SIRI")
med_lab <- c(
  WBC = "WBC", NEUT = "NEUT", MONO = "MONO",
  SII = "SII", NLR = "NLR", SIRI = "SIRI"
)
exwas_log("Model2=", paste(covars_m2, collapse = "+"),
          " meds=", paste(meds, collapse = "+"), " sims=", sims)

treat <- "ERS_IQR"
results <- list()
for (j in seq_along(meds)) {
  med <- meds[[j]]
  if (!med %in% names(df) || sum(is.finite(exwas_to_num(df[[med]]))) < 200L) {
    exwas_log("skip ", med)
    next
  }
  exwas_log("mediate ", med, " …")
  t0 <- Sys.time()
  res <- exwas_tox_mediate_one(
    df, treat = treat, mediator = med, outcome = "DN",
    covars = covars_m2, weight_col = "WTSA2YR",
    sims = sims, seed = 123456L + j
  )
  if (is.null(res)) {
    exwas_log("FAILED ", med)
    next
  }
  t1 <- res$table
  t1$mediator_lab <- unname(med_lab[[med]])
  results[[med]] <- t1
  exwas_log(
    med, " ", signif(as.numeric(difftime(Sys.time(), t0, units = "mins")), 3), " min; ",
    "IDE=", signif(t1$IDE, 3), " Prop%=", signif(100 * t1$Prop, 3),
    " P=", signif(t1$IDE_p, 3)
  )
}
if (!length(results)) stop("无中介结果", call. = FALSE)
raw <- do.call(rbind, results)
rownames(raw) <- NULL
# 按原文顺序
raw <- raw[match(intersect(meds, raw$mediator), raw$mediator), , drop = FALSE]
utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_inflam_dong.csv"), row.names = FALSE)
utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_exploratory.csv"), row.names = FALSE)

# ---- Dong 版式单元格 ----
.fmt_num3 <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x)) return("")
  # 泛癌炎症中介 IDE 常 <0.001；三位会收成 0.000，改用最多 3 位有效+固定三位小数
  if (abs(x) > 0 && abs(x) < 0.001) return(sprintf("%.2e", x))
  sprintf("%.3f", x)
}
.fmt_est_ci <- function(est, lo, hi) {
  est <- as.numeric(est); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(est)) return("")
  sprintf("%s (%s, %s)", .fmt_num3(est), .fmt_num3(lo), .fmt_num3(hi))
}
.fmt_p <- function(p) {
  pub_format_p(as.numeric(p))
}
.fmt_prop <- function(prop) {
  # 原文为百分比数值（如 11.494），保留 3 位
  x <- 100 * as.numeric(prop)
  if (!is.finite(x)) return("")
  sprintf("%.3f", x)
}

body <- data.frame(
  Mediator = raw$mediator_lab,
  `Indirect effect` = mapply(.fmt_est_ci, raw$IDE, raw$IDE_lo, raw$IDE_hi),
  `P (indirect)` = vapply(raw$IDE_p, .fmt_p, character(1)),
  `Direct effect` = mapply(.fmt_est_ci, raw$DE, raw$DE_lo, raw$DE_hi),
  `P (direct)` = vapply(raw$DE_p, .fmt_p, character(1)),
  `Total effect` = mapply(.fmt_est_ci, raw$Total, raw$Total_lo, raw$Total_hi),
  `P (total)` = vapply(raw$Total_p, .fmt_p, character(1)),
  `Proportion of mediation (%)` = vapply(raw$Prop, .fmt_prop, character(1)),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

title <- paste0(
  "Table S6. The mediating roles of systemic inflammatory biomarkers in association ",
  "between environmental risk score and pan-cancer."
)
n_sig <- sum(as.numeric(raw$IDE_p) < 0.05, na.rm = TRUE)
footnotes <- c(
  "Abbreviations: WBC, white blood cell; NEUT, neutrophil; MONO, monocyte; SII, systemic immune-inflammation index; NLR, neutrophil-to-lymphocyte ratio; SIRI, systemic inflammatory response index.",
  "Effects are on the risk-difference scale from R mediation::mediate with bootstrap B = 1000 (percentile CI); treatment = ERS per IQR; outcome = pan-cancer.",
  paste0(
    "Model 2 covariates (locked with Figure 4): ",
    paste(covars_m2, collapse = ", "), "."
  ),
  paste0(
    "Mediator panel as reported in Table S6; ",
    "adapted only in outcome (pan-cancer). Indirect-effect P<0.05 for ",
    n_sig, "/", nrow(raw), " mediators."
  ),
  "Survey weights WTSA2YR entered as glm/lm weights normalized to mean 1."
)

out_xlsx <- file.path(sum_tab, "Table S6. Mediation inflammatory biomarkers.xlsx")
# 撤旧 exploratory 文件名，避免交付双份
old_xlsx <- file.path(sum_tab, "Table S6. Mediation exploratory.xlsx")
if (file.exists(old_xlsx)) file.remove(old_xlsx)

utils::write.csv(
  body,
  file.path(src_tab, "Table S6. Mediation inflammatory Dong layout.csv"),
  row.names = FALSE
)

sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S6",
  footnotes = footnotes
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  openxlsx::setColWidths(wb, sh, cols = 1:8, widths = c(12, 28, 12, 28, 12, 28, 12, 18))
  center <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "center", wrapText = TRUE
  )
  left <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "left"
  )
  nr <- 2L + nrow(body)
  openxlsx::addStyle(wb, sh, left, rows = 3:nr, cols = 1, gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, sh, center, rows = 3:nr, cols = 2:8, gridExpand = TRUE, stack = TRUE)
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

# ---- Figure 5：2×3 对齐 Dong 炎症六项 ----
fig5_bn <- "Figure 5. Mediation inflammatory biomarkers.pdf"
fig5_path <- file.path(fig_pdf, fig5_bn)
tab_plot <- raw
tab_plot$mediator <- raw$mediator_lab
exwas_tox_draw_fig5_mediation(
  tab_plot, fig5_path,
  outcome_lab = "Pan-cancer", treat_lab = "ERS",
  width = 12, height = 8, ncol = 3L
)
# 撤旧临床四项图名
old_fig5 <- file.path(fig_pdf, "Figure 5. Mediation clinical biomarkers.pdf")
if (file.exists(old_fig5)) file.remove(old_fig5)
old_md <- file.path(fig_md, "Figure 5. Mediation clinical biomarkers.md")
if (file.exists(old_md)) file.remove(old_md)
writeLines(c(
  "# Figure 5. Mediation inflammatory biomarkers",
  "",
  "## 图面说明",
  "2×3 路径图，中介与 Dong Fig5 / Table S6 一致：WBC, NEUT, MONO, SII, NLR, SIRI。",
  "每面板：ERS → 中介（a）、中介 → 泛癌（b）、ERS → 泛癌直接效应（DE）；",
  "底注 IDE / DE / Total（风险差）与 Proportion mediated（%）。",
  paste0("方法：mediation::mediate，bootstrap B=", sims, "。"),
  "",
  "## 分析上下文",
  paste0(
    "暴露：ERS（per IQR）；结局：泛癌；中介：全身炎症六项；Model2=",
    paste(covars_m2, collapse = "+"), "。"
  ),
  paste0("间接效应显著（P<0.05）：", n_sig, "/", nrow(raw), "。")
), file.path(fig_md, "Figure 5. Mediation inflammatory biomarkers.md"))

exwas_log("写完 ", out_xlsx)
exwas_log("Fig5 ", fig5_path)
print(body)
exwas_log("DONE")
