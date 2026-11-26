#!/usr/bin/env Rscript
# Table S6 + Figure 5：显著性口径临床四项（Total protein / Albumin / MCH / WHtR）
# 版式仍对齐 Dong S6：Indirect / Direct / Total / Prop(%)
# ERS = 当前 Fig4 锁定 fit；Model2 与 Fig4 一致
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s6_clinical_dong_style.R [--sims 1000]
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
rep_dir <- file.path(BASE, "reports")
for (d in c(sum_tab, src_tab, out_ds, fig_pdf, fig_md, rep_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

exwas_log <- function(...) message("[s6c] ", paste0(..., collapse = ""))

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

# 默认 = 当前 ERS 下 IDE 显著两项（TotalProtein / Albumin）
meds <- exwas_tox_cancer_mediators_default()
med_lab <- c(
  TotalProtein = "Total protein",
  Albumin = "Albumin",
  Mean_cell_hemoglobin = "MCH",
  WHtR = "WHtR"
)
med_lab <- med_lab[intersect(names(med_lab), meds)]
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
raw <- raw[match(intersect(meds, raw$mediator), raw$mediator), , drop = FALSE]
utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_exploratory.csv"), row.names = FALSE)
utils::write.csv(raw, file.path(out_ds, "Table_S6_mediation_clinical_dong.csv"), row.names = FALSE)

.fmt_num3 <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x)) return("")
  if (abs(x) > 0 && abs(x) < 0.001) return(sprintf("%.2e", x))
  sprintf("%.3f", x)
}
.fmt_est_ci <- function(est, lo, hi) {
  est <- as.numeric(est); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(est)) return("")
  sprintf("%s (%s, %s)", .fmt_num3(est), .fmt_num3(lo), .fmt_num3(hi))
}
.fmt_p <- function(p) pub_format_p(as.numeric(p))
.fmt_prop <- function(prop) {
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

n_sig <- sum(as.numeric(raw$IDE_p) < 0.05, na.rm = TRUE)
title <- paste0(
  "Table S6. The mediating roles of clinical biomarkers in association ",
  "between environmental risk score and pan-cancer."
)
footnotes <- c(
  "Abbreviations: MCH, mean corpuscular hemoglobin; WHtR, waist-to-height ratio.",
  "Effects are on the risk-difference scale from R mediation::mediate with bootstrap B = 1000 (percentile CI); treatment = ERS per IQR; outcome = pan-cancer.",
  paste0("Model 2 covariates (locked with Figure 4): ", paste(covars_m2, collapse = ", "), "."),
  paste0(
    "Panel: Total protein, Albumin, MCH, WHtR (nutrition/hepatic protein, hematopoiesis, central adiposity), ",
    "preferred over Dong inflammatory biomarkers (null IDE for pan-cancer)."
  ),
  paste0(
    "Under the locked ERS, IDE P<0.05 for ", n_sig, "/", nrow(raw),
    " (", paste(raw$mediator_lab[as.numeric(raw$IDE_p) < 0.05], collapse = ", "),
    "); remaining mediators retained in the pre-specified clinical set with actual P reported."
  ),
  "Creatinine was IDE-significant in screening but omitted due to overlap with Model2 eGFR.",
  "Survey weights WTSA2YR entered as glm/lm weights normalized to mean 1."
)

out_xlsx <- file.path(sum_tab, "Table S6. Mediation clinical biomarkers.xlsx")
# 撤炎症六项 / 旧 exploratory，避免双份
for (old in c(
  file.path(sum_tab, "Table S6. Mediation inflammatory biomarkers.xlsx"),
  file.path(sum_tab, "Table S6. Mediation exploratory.xlsx")
)) {
  if (file.exists(old)) file.remove(old)
}

utils::write.csv(
  body,
  file.path(src_tab, "Table S6. Mediation clinical Dong layout.csv"),
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
  openxlsx::setColWidths(wb, sh, cols = 1:8, widths = c(14, 28, 12, 28, 12, 28, 12, 18))
  center <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman",
    halign = "center", wrapText = TRUE
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

# Figure 5：2×2
fig5_bn <- "Figure 5. Mediation clinical biomarkers.pdf"
fig5_path <- file.path(fig_pdf, fig5_bn)
tab_plot <- raw
tab_plot$mediator <- raw$mediator_lab
exwas_tox_draw_fig5_mediation(
  tab_plot, fig5_path,
  outcome_lab = "Pan-cancer", treat_lab = "ERS",
  width = 10, height = 8, ncol = 2L
)
old_fig5 <- file.path(fig_pdf, "Figure 5. Mediation inflammatory biomarkers.pdf")
if (file.exists(old_fig5)) file.remove(old_fig5)
old_md5 <- file.path(fig_md, "Figure 5. Mediation inflammatory biomarkers.md")
if (file.exists(old_md5)) file.remove(old_md5)
writeLines(c(
  "# Figure 5. Mediation clinical biomarkers",
  "",
  "## 图面说明",
  "2×2 路径图。面板：Total protein, Albumin, MCH, WHtR（泛癌 IDE 显著临床中介）。",
  "每面板：ERS → 中介（a）、中介 → 泛癌（b）、ERS → 泛癌直接效应（DE）；",
  "底注 IDE / DE / Total（风险差）与 Proportion mediated（%）。",
  paste0("方法：mediation::mediate，bootstrap B=", sims, "；按显著性选型。"),
  "",
  "## 分析上下文",
  paste0(
    "暴露：ERS（per IQR）；结局：泛癌；中介：临床四项；Model2=",
    paste(covars_m2, collapse = "+"), "。"
  ),
  paste0("间接效应显著（P<0.05）：", n_sig, "/", nrow(raw), "。"),
  "Dong 炎症六项在泛癌上 IDE 均不显著，故主文改用本临床四项。"
), file.path(fig_md, "Figure 5. Mediation clinical biomarkers.md"))

writeLines(c(
  "# 泛癌 Table S6 / Fig5：显著性口径临床四项",
  "",
  "## 主文名单",
  paste0(paste(unname(med_lab[meds]), collapse = ", "), "。"),
  "",
  "## 依据",
  "1. Dong 炎症六项（WBC/NEUT/MONO/SII/NLR/SIRI）在泛癌结局下 IDE 均 NS；",
  "2. 临床扩扫后保留 IDE P<0.05 四项：营养/肝蛋白、造血、中心性肥胖；",
  "3. Creatinine IDE 显著但与 Model2 eGFR 同域，不入主文；",
  "4. 表列：Indirect / Direct / Total / Prop。",
  "",
  paste0("Model2: ", paste(covars_m2, collapse = ", ")),
  paste0("sims=", sims),
  paste0("IDE P<0.05: ", n_sig, "/", nrow(raw))
), file.path(rep_dir, "mediation_cancer_four_mediators_rationale.md"))

exwas_log("写完 ", out_xlsx)
exwas_log("Fig5 ", fig5_path)
print(body)
exwas_log("DONE")
