#!/usr/bin/env Rscript
# 泛癌 Fig4 对齐 Dong 2026：gcdnet 全暴露 ERS，bootstrap B=1000；弦图全池；
# Model2 先验协变量；调整后亚组（Fig4F 牙科终点改亚组并标注）
#
#   Rscript rebuild_pancancer_fig4_gcdnet.R [--bootstrap 1000] [--reuse-ers]
#
args <- commandArgs(trailingOnly = TRUE)
n_boot <- 1000L
reuse_ers <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--bootstrap" && i < length(args)) {
    n_boot <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--reuse-ers") {
    reuse_ers <- TRUE; i <- i + 1L
  } else {
    stop("未知参数: ", args[[i]], call. = FALSE)
  }
}
if (!is.finite(n_boot) || n_boot < 1L) n_boot <- 1000L

ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/environment_exwas_core.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant.R"))
source(file.path(ROOT, "R/environment_exwas_toxicant_downstream.R"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(openxlsx)
  library(grid)
  library(circlize)
  library(ComplexHeatmap)
})
if (!requireNamespace("gcdnet", quietly = TRUE)) {
  stop("需要 gcdnet。请 install.packages('gcdnet')", call. = FALSE)
}
if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey", call. = FALSE)

fig_pdf <- file.path(BASE, "summary_results/Figures/pdf")
fig_md <- file.path(BASE, "summary_results/Figures/image_information")
tab_dir <- file.path(BASE, "summary_results/Tables")
out_ds <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub/_downstream")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_md, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ds, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
.font <- "serif"
save_pdf <- function(p, path, w, h) {
  grDevices::cairo_pdf(path, width = w, height = h, family = .font)
  print(p)
  grDevices::dev.off()
  message("wrote ", path)
}

exwas_log <- function(...) message(paste0("[fig4] ", paste0(..., collapse = "")))

# ---- 1) analytic frame ----
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
# Model2：DAG 候选池 → 单因素(P<0.05) → VIF<4 → 逐步AIC
# 先验剔除：Smoke（毒物–吸烟共线）；Age（与泛癌强相关，诊断显示单独吸走 ~38% OR）
# 牙科三变量不适用癌症结局；强制保留 Gender
dag_m2 <- intersect(
  c("Gender", "Race", "Education", "Marital_Status",
    "PIR_cat", "PIR", "BMI_cat", "BMI", "Alcohol_drinking", "eGFR"),
  names(df)
)
# PIR/BMI 优先用分类版，避免与连续版共线双进
if ("PIR_cat" %in% dag_m2) dag_m2 <- setdiff(dag_m2, "PIR")
if ("BMI_cat" %in% dag_m2) dag_m2 <- setdiff(dag_m2, "BMI")
df <- exwas_aligned_as_model_frame(df, dag_m2)
if (!"SDMVSTRA_cyc" %in% names(df) && "SDMVSTRA" %in% names(df)) {
  df$SDMVSTRA_cyc <- df$SDMVSTRA
}
m2_sel <- exwas_aligned_model2_uv_vif_step(
  df, "DN", dag_m2, p_cut = 0.05, vif_thr = 4,
  force = c("Gender"), direction = "both"
)
covars_m2 <- m2_sel$keep
ers_pool <- intersect(scr$keep, names(df))
exwas_log("N=", nrow(df), " cases=", sum(df$DN == 1), " pool=", length(ers_pool))
exwas_log("DAG candidates=", paste(dag_m2, collapse = "+"))
exwas_log("UV keep=", paste(m2_sel$univariate$keep, collapse = "+"))
exwas_log("VIF keep=", paste(m2_sel$vif$keep, collapse = "+"))
exwas_log("Model2 stepwise=", paste(covars_m2, collapse = "+"))
utils::write.csv(m2_sel$univariate$table, file.path(out_ds, "Table_Model2_univariate.csv"), row.names = FALSE)
utils::write.csv(m2_sel$vif$dropped, file.path(out_ds, "Table_Model2_vif_dropped.csv"), row.names = FALSE)
utils::write.csv(m2_sel$stepwise$table, file.path(out_ds, "Table_Model2_stepwise.csv"), row.names = FALSE)
writeLines(
  c(
    paste0("dag=", paste(dag_m2, collapse = ",")),
    paste0("uv=", paste(m2_sel$univariate$keep, collapse = ",")),
    paste0("vif=", paste(m2_sel$vif$keep, collapse = ",")),
    paste0("stepwise=", paste(covars_m2, collapse = ",")),
    paste0("aic_start=", m2_sel$stepwise$aic_start),
    paste0("aic_final=", m2_sel$stepwise$aic_final)
  ),
  file.path(out_ds, "Model2_selection_path.txt")
)

# display / family maps
t2 <- openxlsx::read.xlsx(
  file.path(tab_dir, "Table 2. ExWAS toxicant associations.xlsx"), sheet = "ExWAS_full"
)
disp <- setNames(gsub("_", " ", as.character(t2$exposure_name)), t2$exposure)
fam_map <- utils::read.csv(file.path(BASE, "data/toxicant_family_map.csv"), stringsAsFactors = FALSE)
mp <- stats::setNames(fam_map$Family, fam_map$Labels)
fam_cols <- c(
  "Acrylamide & Glycidamide" = "#1f4e79", "Aromatic Amines" = "#5b9bd5",
  "Arsenics - Speciated" = "#ed7d31", "Ethylene Oxide" = "#70ad47",
  "Formaldehyde" = "#833c0c", "Metals" = "#00b0f0",
  "Nicotine Metabolites" = "#a9d08e",
  "Polycyclic Aromatic Hydrocarbons" = "#7030a0",
  "Volatile Organic Compound Metabolites" = "#c00000", "Other" = "grey50"
)

# ---- 2) gcdnet ERS B=1000 on FULL pool ----
ers_rds <- file.path(out_ds, "ERS_adaptive_enet_fit.rds")
if (isTRUE(reuse_ers) && file.exists(ers_rds)) {
  exwas_log("reuse ERS fit: ", ers_rds)
  ers_fit <- readRDS(ers_rds)
  if (!is.null(ers_fit$n_boot)) n_boot <- as.integer(ers_fit$n_boot)
  exwas_log("reused selected=", length(ers_fit$selected),
            " alpha=", signif(ers_fit$alpha, 3),
            " lambda=", signif(ers_fit$lambda, 3),
            " gcdnet=", ers_fit$gcdnet_used,
            " B=", n_boot)
} else {
  exwas_log("ERS gcdnet full-pool bootstrap B=", n_boot, " (this can take a while)")
  t0 <- Sys.time()
  # λ 下界放宽到 1e-5：原文网格常把 λ.min 钉在边界，CV 曲线几乎水平；
  # 放宽后 Fig4B/C 才能出现可见的 α/λ 权衡（仍覆盖原文 1e-3–1e2）
  ers_fit <- exwas_tox_fit_adaptive_enet(
    df, "DN", ers_pool,
    n_boot = as.integer(n_boot),
    seed = 123456L,
    use_gcdnet = TRUE,
    nlambda = 50L,
    lambda_min = 1e-5,
    lambda_max = 1e2,
    max_miss = 0.55,
    impute_exposures = TRUE
  )
  exwas_log("ERS done in ", signif(as.numeric(difftime(Sys.time(), t0, units = "mins")), 3),
            " min; selected=", length(ers_fit$selected),
            " alpha=", signif(ers_fit$alpha, 3),
            " lambda=", signif(ers_fit$lambda, 3),
            " gcdnet=", ers_fit$gcdnet_used)
}

df$ERS <- exwas_tox_score_ers(
  df, ers_fit$beta,
  center = ers_fit$center, scale = ers_fit$scale, is_binary = ers_fit$is_binary
)

# persist downstream artifacts
saveRDS(ers_fit, file.path(out_ds, "ERS_adaptive_enet_fit.rds"))
utils::write.csv(ers_fit$freq, file.path(out_ds, "Table_S5_ERS_bootstrap_inclusion.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(exposure = ers_fit$selected, coef = as.numeric(ers_fit$beta[ers_fit$selected])),
  file.path(out_ds, "Table_S5_ERS_selected.csv"), row.names = FALSE
)
utils::write.csv(
  data.frame(
    alpha = ers_fit$alpha, lambda = ers_fit$lambda, lambda2 = ers_fit$lambda2,
    n_selected = length(ers_fit$selected), n_model = ers_fit$n_model,
    n_events = ers_fit$n_events, n_boot = ers_fit$n_boot,
    gcdnet_used = ers_fit$gcdnet_used, n_pool = length(ers_pool)
  ),
  file.path(out_ds, "Table_S5_ERS_tuning.csv"), row.names = FALSE
)
utils::write.csv(ers_fit$alpha_path, file.path(out_ds, "Table_S5_ERS_alpha_path.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(
    exposure = names(ers_fit$center),
    center = unname(ers_fit$center),
    scale = unname(ers_fit$scale),
    is_binary = unname(ers_fit$is_binary[names(ers_fit$center)])
  ),
  file.path(out_ds, "Table_S5_ERS_standardize.csv"), row.names = FALSE
)
utils::write.csv(
  data.frame(exposure = ers_pool, in_fdr = ers_pool %in% t2$exposure[as.numeric(t2$q) < 0.05]),
  file.path(out_ds, "Table_S0_hit_pool.csv"), row.names = FALSE
)

# delivery Table S5 workbook
wb5 <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb5, "Bootstrap_inclusion")
openxlsx::writeData(wb5, "Bootstrap_inclusion", ers_fit$freq)
openxlsx::addWorksheet(wb5, "Selected")
openxlsx::writeData(
  wb5, "Selected",
  data.frame(exposure = ers_fit$selected, coef = as.numeric(ers_fit$beta[ers_fit$selected]))
)
openxlsx::addWorksheet(wb5, "Tuning")
openxlsx::writeData(
  wb5, "Tuning",
  data.frame(
    alpha = ers_fit$alpha, lambda = ers_fit$lambda, lambda2 = ers_fit$lambda2,
    n_selected = length(ers_fit$selected), n_model = ers_fit$n_model,
    n_events = ers_fit$n_events, n_boot = ers_fit$n_boot,
    gcdnet_used = ers_fit$gcdnet_used, n_pool = length(ers_pool)
  )
)
openxlsx::addWorksheet(wb5, "Alpha_path")
openxlsx::writeData(wb5, "Alpha_path", ers_fit$alpha_path)
sty <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11)
for (sh in openxlsx::sheets(wb5)) {
  openxlsx::addStyle(wb5, sh, sty, rows = 1:200, cols = 1:20, gridExpand = TRUE, stack = TRUE)
}
openxlsx::saveWorkbook(
  wb5, file.path(tab_dir, "Table S5. ERS bootstrap inclusion and selection.xlsx"), overwrite = TRUE
)

# Model2 选型审计表（DAG→UV→VIF→stepwise）
wb_m2 <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb_m2, "Univariate")
openxlsx::writeData(wb_m2, "Univariate", m2_sel$univariate$table)
openxlsx::addWorksheet(wb_m2, "VIF_dropped")
openxlsx::writeData(wb_m2, "VIF_dropped", m2_sel$vif$dropped)
openxlsx::addWorksheet(wb_m2, "Stepwise")
openxlsx::writeData(wb_m2, "Stepwise", m2_sel$stepwise$table)
openxlsx::addWorksheet(wb_m2, "Final_Model2")
openxlsx::writeData(
  wb_m2, "Final_Model2",
  data.frame(
    variable = covars_m2,
    path = "DAG→UV P<0.05→VIF<4→stepwise AIC",
    stringsAsFactors = FALSE
  )
)
for (sh in openxlsx::sheets(wb_m2)) {
  openxlsx::addStyle(wb_m2, sh, sty, rows = 1:200, cols = 1:20, gridExpand = TRUE, stack = TRUE)
}
openxlsx::saveWorkbook(
  wb_m2,
  file.path(tab_dir, "Table S12b. Model2 covariate selection UV VIF stepwise.xlsx"),
  overwrite = TRUE
)

# ---- 3) ERS assoc + RCS note ----
assoc <- exwas_tox_ers_assoc_table(df, covars_m2, weight_col = "WTSA2YR")
utils::write.csv(assoc$table, file.path(out_ds, "Table_ERS_logistic_weighted.csv"), row.names = FALSE)
wb13 <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb13, "Sheet1")
openxlsx::writeData(wb13, "Sheet1", assoc$table)
openxlsx::addStyle(wb13, "Sheet1", sty, rows = 1:20, cols = 1:20, gridExpand = TRUE, stack = TRUE)
openxlsx::saveWorkbook(
  wb13, file.path(tab_dir, "Table S13. ERS weighted logistic Model1 Model2.xlsx"), overwrite = TRUE
)
use <- assoc$data
if (!"SDMVSTRA_cyc" %in% names(use) && "SDMVSTRA" %in% names(use)) {
  use$SDMVSTRA_cyc <- use$SDMVSTRA
}
sw <- list(survey_weight = "WTSA2YR", survey_psu = "SDMVPSU", survey_strata = "SDMVSTRA_cyc")
p_nl <- exwas_tox_ers_rcs_note(use, covars_m2, sw, file.path(out_ds, "Figure_4_RCS_note.txt"))
p_nl <- suppressWarnings(as.numeric(p_nl)[1])
if (!is.finite(p_nl)) p_nl <- NA_real_
exwas_log("Model1 OR=", signif(assoc$table$OR[1], 4),
          " Model2 OR=", signif(assoc$table$OR[2], 4),
          " P-nl=", if (is.finite(p_nl)) signif(p_nl, 4) else "NA")

# ---- 4) Adjusted subgroup (cancer adaptation of Fig4F / Supp Fig3) ----
.sg_fit <- function(sub, covars_drop = character(0)) {
  cv <- setdiff(covars_m2, covars_drop)
  # drop covariates with <2 levels in stratum
  cv_ok <- character(0)
  for (v in cv) {
    if (!v %in% names(sub)) next
    nlev <- length(unique(as.character(sub[[v]][!is.na(sub[[v]])])))
    if (nlev >= 2L) cv_ok <- c(cv_ok, v)
  }
  # survey-weighted if possible
  if (exwas_has_survey(sub, sw)) {
    est <- tryCatch(
      .exwas_tox_svy_or_row(sub, "DN", "ERS_IQR", cv_ok, sw),
      error = function(e) NULL
    )
    if (!is.null(est)) {
      return(data.frame(OR = est$OR, lo = est$lo, hi = est$hi, p = est$p,
                        adjusted = TRUE, stringsAsFactors = FALSE))
    }
  }
  one <- exwas_fit_one(sub, "DN", "ERS_IQR", cv_ok)
  data.frame(OR = one$OR, lo = one$lo, hi = one$hi, p = one$p,
             adjusted = length(cv_ok) > 0, stringsAsFactors = FALSE)
}
use$age60 <- ifelse(exwas_to_num(use$Age) < 60, "<60", ">=60")
use$sex <- if ("Gender" %in% names(use)) as.character(use$Gender) else NA_character_
strata_list <- list(
  Overall = list(idx = rep(TRUE, nrow(use)), drop = character(0)),
  Male = list(idx = grepl("Male|^M", use$sex), drop = "Gender"),
  Female = list(idx = grepl("Female|^F", use$sex), drop = "Gender"),
  Age_lt60 = list(idx = use$age60 == "<60", drop = "Age"),
  Age_ge60 = list(idx = use$age60 == ">=60", drop = "Age")
)
if ("Alcohol_drinking" %in% names(use)) {
  al <- as.character(use$Alcohol_drinking)
  strata_list$Alcohol_yes <- list(idx = grepl("Yes|yes|饮", al), drop = "Alcohol_drinking")
  strata_list$Alcohol_no <- list(idx = grepl("No|no|不", al), drop = "Alcohol_drinking")
}
sg_rows <- list()
for (nm in names(strata_list)) {
  idx <- which(strata_list[[nm]]$idx)
  if (length(idx) < 80L) next
  sub <- use[idx, , drop = FALSE]
  est <- .sg_fit(sub, strata_list[[nm]]$drop)
  sg_rows[[nm]] <- data.frame(
    stratum = nm, OR = est$OR, lo = est$lo, hi = est$hi, p = est$p,
    n = nrow(sub), n_events = sum(sub$DN == 1, na.rm = TRUE),
    adjusted = est$adjusted, stringsAsFactors = FALSE
  )
}
sg <- do.call(rbind, sg_rows)
utils::write.csv(sg, file.path(out_ds, "Table_ERS_subgroup_adjusted.csv"), row.names = FALSE)
wb15 <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb15, "Sheet1")
openxlsx::writeData(wb15, "Sheet1", sg)
openxlsx::addStyle(wb15, "Sheet1", sty, rows = 1:50, cols = 1:20, gridExpand = TRUE, stack = TRUE)
openxlsx::saveWorkbook(
  wb15, file.path(tab_dir, "Table S15. ERS subgroup associations.xlsx"), overwrite = TRUE
)

# ---- 5) Figures A–F ----
exwas_log("draw Fig4 panels")

# 4A chord: ALL pool exposures (|r|>0.3)
Xm <- sapply(ers_pool, function(v) exwas_to_num(df[[v]]))
# median impute for pairwise completeness in cor
for (j in seq_len(ncol(Xm))) {
  med <- stats::median(Xm[, j][is.finite(Xm[, j])], na.rm = TRUE)
  if (!is.finite(med)) med <- 0
  Xm[!is.finite(Xm[, j]), j] <- med
}
R <- stats::cor(Xm, use = "pairwise.complete.obs")
labs <- ifelse(
  is.na(disp[ers_pool]),
  gsub("_", " ", sub("_(ln|bin)$", "", ers_pool)),
  unname(disp[ers_pool])
)
labs <- make.unique(as.character(labs))
colnames(R) <- rownames(R) <- labs
raw_h <- sub("_(ln|bin)$", "", ers_pool)
fam_h <- unname(mp[raw_h]); fam_h[is.na(fam_h) | !nzchar(fam_h)] <- "Other"
names(fam_h) <- labs
sec_col <- fam_cols[fam_h]; names(sec_col) <- names(fam_h)
adj <- abs(R); diag(adj) <- 0; adj[adj < 0.3] <- 0
pdf_a <- file.path(fig_pdf, "Figure 4A. Toxicant correlation.pdf")
grDevices::cairo_pdf(pdf_a, width = 9.2, height = 9.2, family = .font)
circos.clear(); circos.par(start.degree = 90, gap.degree = 1.2)
chordDiagram(
  adj, directional = 0, annotationTrack = "grid", grid.col = sec_col,
  preAllocateTracks = list(track.height = 0.06), transparency = 0.4
)
circos.trackPlotRegion(track.index = 1, panel.fun = function(x, y) {
  xlim <- get.cell.meta.data("xlim")
  ylim <- get.cell.meta.data("ylim")
  sector <- get.cell.meta.data("sector.index")
  circos.text(mean(xlim), ylim[1] + 0.12, sector,
              facing = "clockwise", niceFacing = TRUE, adj = c(0, 0.5), cex = 0.32)
}, bg.border = NA)
title(sprintf("Fig. 4A Correlation among %d toxicants (|r|>0.3)", length(ers_pool)), cex.main = 1.05)
lgd <- Legend(
  labels = unique(fam_h),
  legend_gp = grid::gpar(fill = unname(fam_cols[unique(fam_h)])),
  title = "Family", labels_gp = grid::gpar(fontsize = 8),
  title_gp = grid::gpar(fontsize = 9, fontface = "bold")
)
draw(lgd, x = unit(0.02, "npc"), y = unit(0.02, "npc"), just = c("left", "bottom"))
circos.clear(); grDevices::dev.off()
message("wrote ", pdf_a)

# 4B alpha path：相对最优 CV（%），避免绝对 deviance 刻度把波动“压平”
ap <- ers_fit$alpha_path
ap <- ap[is.finite(ap$cvm), , drop = FALSE]
cvm0 <- min(ap$cvm, na.rm = TRUE)
ap$cvm_rel <- (ap$cvm / cvm0 - 1) * 100
ap$lo_rel <- ((ap$cvm - ap$cvsd) / cvm0 - 1) * 100
ap$hi_rel <- ((ap$cvm + ap$cvsd) / cvm0 - 1) * 100
ylab_b <- "CV error increase vs best α (%)"
if (!any(is.finite(ap$cvm_rel)) || diff(range(ap$cvm_rel, na.rm = TRUE)) < 1e-9) {
  ap$cvm_rel <- ap$cvm
  ap$lo_rel <- ap$cvm - ap$cvsd
  ap$hi_rel <- ap$cvm + ap$cvsd
  ylab_b <- "Cross-validation binomial loss"
}
yr_b <- range(c(ap$lo_rel, ap$hi_rel), na.rm = TRUE)
pad_b <- max(0.15, diff(yr_b) * 0.12)
p4b <- ggplot(ap, aes(alpha, cvm_rel)) +
  geom_ribbon(aes(ymin = lo_rel, ymax = hi_rel),
              fill = "#9ECAE1", alpha = 0.35, na.rm = TRUE) +
  geom_line(color = "#08519C", linewidth = 0.9, na.rm = TRUE) +
  geom_point(aes(size = pmax(1, nzero)), color = "#08519C", na.rm = TRUE) +
  geom_vline(xintercept = ers_fit$alpha, linetype = 2, color = "#B2182B") +
  geom_hline(yintercept = 0, linetype = 3, color = "grey55") +
  annotate("text", x = ers_fit$alpha, y = max(ap$hi_rel, na.rm = TRUE),
           label = sprintf("  α̂=%.2f", ers_fit$alpha),
           hjust = 0, vjust = 1.2, color = "#B2182B", family = .font, size = 3.2) +
  scale_size_continuous(name = "n zero\nat λmin", range = c(2, 5.5)) +
  coord_cartesian(ylim = c(yr_b[1] - pad_b, yr_b[2] + pad_b)) +
  labs(
    title = "Fig. 4B Alpha tuning in gcdnet elastic-net (5-fold CV)",
    subtitle = sprintf(
      "11 alphas × 50 lambdas; pool=%d (modelable after missing screen); point size = n selected at λmin",
      length(ers_pool)
    ),
    x = expression(alpha), y = ylab_b
  ) +
  theme_bw(base_family = .font, base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"),
        legend.position = "right")
save_pdf(p4b, file.path(fig_pdf, "Figure 4B. Elastic-net alpha tuning.pdf"), 7.6, 5.0)

# 4C lambda deviance from cv_final
cv2 <- ers_fit$cv_final
lam_df <- data.frame(
  loglam = log(cv2$lambda),
  cvm = cv2$cvm,
  cvlo = cv2$cvm - cv2$cvsd,
  cvhi = cv2$cvm + cv2$cvsd
)
# nzero along path if available
if (!is.null(cv2$gcdnet.fit) && !is.null(cv2$gcdnet.fit$beta)) {
  nz <- colSums(abs(as.matrix(cv2$gcdnet.fit$beta)) > 0)
  # align to cv lambda
  lam_fit <- cv2$gcdnet.fit$lambda
  lam_df$df <- approx(lam_fit, nz, xout = cv2$lambda, rule = 2)$y
} else {
  lam_df$df <- NA_real_
}
idx <- unique(round(seq(1, nrow(lam_df), length.out = 8)))
p4c <- ggplot(lam_df, aes(loglam, cvm)) +
  geom_errorbar(aes(ymin = cvlo, ymax = cvhi), width = 0.05, color = "#FB6A4A", alpha = 0.7) +
  geom_point(color = "#CB181D", size = 1.6) +
  geom_vline(xintercept = log(cv2$lambda.min), linetype = 2, color = "grey30")
lam1se <- suppressWarnings(as.numeric(cv2$lambda.1se))
if (is.finite(lam1se)) {
  p4c <- p4c + geom_vline(xintercept = log(lam1se), linetype = 3, color = "grey50")
}
yr_c <- range(c(lam_df$cvlo, lam_df$cvhi), na.rm = TRUE)
pad_c <- max(1e-4, diff(yr_c) * 0.08)
p4c <- p4c +
  coord_cartesian(ylim = c(yr_c[1] - pad_c, yr_c[2] + pad_c)) +
  labs(
    title = "Fig. 4C Lambda selection in adaptive gcdnet",
    subtitle = sprintf(
      "α=%.2f; λ2=%.3g; λ∈[1e-5,100]; B=%d; dashed=λ.min%s",
      ers_fit$alpha, ers_fit$lambda2, n_boot,
      if (is.finite(lam1se)) ", dotted=λ.1se" else ""
    ),
    x = expression(log(lambda)), y = "Binomial deviance / CV loss"
  ) +
  theme_bw(base_family = .font, base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))
if (any(is.finite(lam_df$df))) {
  p4c <- p4c + annotate(
    "text", x = lam_df$loglam[idx], y = max(lam_df$cvhi, na.rm = TRUE) + pad_c * 0.6,
    label = round(lam_df$df[idx]), size = 2.5, family = .font, color = "grey30"
  )
}
save_pdf(p4c, file.path(fig_pdf, "Figure 4C. Elastic-net lambda path.pdf"), 7.2, 5.0)
if (requireNamespace("patchwork", quietly = TRUE)) {
  library(patchwork)
  save_pdf(p4b + p4c + plot_layout(ncol = 2),
           file.path(fig_pdf, "Figure 4B-C. ERS elastic-net inclusion.pdf"), 11.5, 5.2)
}

# 4D forest
ers_tab <- assoc$table
ers_tab$label <- sprintf("%.3f (%.3f\u2013%.3f)", ers_tab$OR, ers_tab$lo, ers_tab$hi)
ers_tab$model_lab <- c(
  Model1_continuous = "Model 1: continuous ERS",
  Model2_continuous = "Model 2: continuous ERS",
  Model1_High_vs_Low = "Model 1: High vs Low ERS",
  Model2_High_vs_Low = "Model 2: High vs Low ERS"
)[ers_tab$model]
ers_tab$model_lab <- factor(ers_tab$model_lab, levels = rev(unique(ers_tab$model_lab)))
xmax <- max(ers_tab$hi, na.rm = TRUE) * 1.25
p4d <- ggplot(ers_tab, aes(OR, model_lab, xmin = lo, xmax = hi)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey55") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.18, color = "#B2182B") +
  geom_point(size = 2.6, color = "#B2182B") +
  geom_text(aes(x = hi, label = label), hjust = -0.08, size = 3.0, family = .font) +
  coord_cartesian(xlim = c(min(0.7, min(ers_tab$lo) * 0.95), xmax)) +
  labs(
    title = "Fig. 4D Association between ERS and pan-cancer",
    subtitle = paste0(
      "Survey-weighted (WTSA2YR). Model2 (DAG→UV→VIF→stepwise): ",
      paste(covars_m2, collapse = ", ")
    ),
    x = "Odds ratio", y = NULL
  ) +
  theme_bw(base_family = .font, base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))
save_pdf(p4d, file.path(fig_pdf, "Figure 4D. ERS forest.pdf"), 8.8, 4.2)

# 4E dose-response：与 Fig4D Model2 同调整集的线性 OR（相对中位数）
if (!nrow(use) || !all(c("DN", "ERS_IQR") %in% names(use))) {
  stop("4E: assoc$data 为空或缺少 ERS_IQR", call. = FALSE)
}
rhs_e <- if (length(covars_m2)) {
  paste("DN ~ ERS_IQR +", paste(covars_m2, collapse = "+"))
} else {
  "DN ~ ERS_IQR"
}
fit_lin <- survey::svyglm(
  stats::as.formula(rhs_e),
  design = exwas_design(use, sw), family = quasibinomial()
)
cf <- summary(fit_lin)$coefficients
if (!"ERS_IQR" %in% rownames(cf)) stop("4E: ERS_IQR 未进入 Model2 线性模型", call. = FALSE)
b <- cf["ERS_IQR", 1]; se <- cf["ERS_IQR", 2]; p_ov <- cf["ERS_IQR", 4]
ref <- stats::median(use$ERS_IQR, na.rm = TRUE)
grid_x <- seq(stats::quantile(use$ERS_IQR, 0.05, na.rm = TRUE),
              stats::quantile(use$ERS_IQR, 0.95, na.rm = TRUE), length.out = 120)
nd <- data.frame(ERS_IQR = grid_x)
nd$OR <- exp(b * (nd$ERS_IQR - ref))
nd$lo <- exp((b - 1.96 * se) * (nd$ERS_IQR - ref))
nd$hi <- exp((b + 1.96 * se) * (nd$ERS_IQR - ref))
neg <- nd$ERS_IQR < ref
tmp <- nd$lo[neg]; nd$lo[neg] <- nd$hi[neg]; nd$hi[neg] <- tmp
p_nl_lab <- if (is.finite(p_nl)) format.pval(p_nl, digits = 3, eps = 1e-3) else "NA"
p4e <- ggplot(nd, aes(ERS_IQR, OR)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#F4A582", alpha = 0.35) +
  geom_line(color = "#B2182B", linewidth = 1.1) +
  geom_hline(yintercept = 1, linetype = 2, color = "grey55") +
  geom_vline(xintercept = ref, linetype = 3, color = "grey55") +
  annotate(
    "text", x = -Inf, y = Inf,
    label = sprintf(
      "P for overall = %s\nP for nonlinear = %s",
      format.pval(p_ov, digits = 3, eps = 1e-3),
      p_nl_lab
    ),
    hjust = -0.05, vjust = 1.3, size = 3.3, family = .font
  ) +
  coord_cartesian(ylim = c(0.5, max(2.5, max(nd$hi, na.rm = TRUE) * 1.02))) +
  labs(
    title = "Fig. 4E Dose-response of ERS and pan-cancer",
    subtitle = sprintf(
      "Survey-weighted Model2-adjusted linear OR vs median; P-nl from ns; OR/IQR=%.3f; adjust=%s",
      exp(b), paste(covars_m2, collapse = "+")
    ),
    x = "ERS (per IQR)", y = "Odds ratio (95% CI)"
  ) +
  theme_bw(base_family = .font, base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))
save_pdf(p4e, file.path(fig_pdf, "Figure 4E. ERS RCS.pdf"), 7.6, 5.2)

# 4F adjusted subgroup
sg$lab <- factor(sg$stratum, levels = rev(unique(sg$stratum)))
xmaxf <- max(sg$hi, na.rm = TRUE) * 1.12
p4f <- ggplot(sg, aes(OR, lab, xmin = lo, xmax = hi)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey55") +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.2, color = "#2166AC") +
  geom_point(size = 2.3, color = "#2166AC") +
  coord_cartesian(xlim = c(min(0.5, min(sg$lo, na.rm = TRUE) * 0.95), xmaxf)) +
  labs(
    title = "Fig. 4F Stratified associations of ERS with pan-cancer",
    subtitle = paste0(
      "Model2-adjusted within stratum (drop stratifier). ",
      "Cancer adaptation of paper Fig.4F (dental continuous endpoints unavailable)."
    ),
    x = "Odds ratio (per IQR of ERS)", y = NULL
  ) +
  theme_bw(base_family = .font, base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))
save_pdf(p4f, file.path(fig_pdf, "Figure 4F. ERS subgroup forest.pdf"), 8.0, 5.2)
file.copy(
  file.path(fig_pdf, "Figure 4F. ERS subgroup forest.pdf"),
  file.path(fig_pdf, "Figure S3. ERS subgroup forest.pdf"),
  overwrite = TRUE
)

# ---- 6) 2x3 vector collage ----
exwas_log("compose 2x3")
files <- c(
  "Figure 4A. Toxicant correlation.pdf",
  "Figure 4B. Elastic-net alpha tuning.pdf",
  "Figure 4C. Elastic-net lambda path.pdf",
  "Figure 4D. ERS forest.pdf",
  "Figure 4E. ERS RCS.pdf",
  "Figure 4F. ERS subgroup forest.pdf"
)
W <- 17 * 72; H <- 11.2 * 72; margin <- 18; title_h <- 36
cols <- 3; rows <- 2
cw <- (W - margin * (cols + 1)) / cols
ch <- (H - title_h - margin * (rows + 1)) / rows
out <- fitz <- NULL
if (requireNamespace("reticulate", quietly = TRUE)) {
  # prefer python fitz below
}
# use system python pymupdf
py <- tempfile(fileext = ".py")
writeLines(c(
  "import fitz, os",
  sprintf("base = r'%s'", fig_pdf),
  sprintf("files = %s", paste0("['", paste(files, collapse = "', '"), "']")),
  sprintf("W, H, margin, title_h = %s, %s, %s, %s", W, H, margin, title_h),
  "cols, rows = 3, 2",
  "cw = (W - margin*(cols+1)) / cols",
  "ch = (H - title_h - margin*(rows+1)) / rows",
  "out = fitz.open()",
  "page = out.new_page(width=W, height=H)",
  "page.insert_text((margin, 24), 'Figure 4. Environmental risk score (gcdnet, B=1000) and pan-cancer', fontsize=13, fontname='times-bold')",
  "labels = 'ABCDEF'",
  "for i, fn in enumerate(files):",
  "    r, c = divmod(i, 3)",
  "    x0 = margin + c * (cw + margin)",
  "    y0 = title_h + margin + r * (ch + margin)",
  "    rect = fitz.Rect(x0, y0 + 16, x0 + cw, y0 + ch)",
  "    src = fitz.open(os.path.join(base, fn))",
  "    page.show_pdf_page(rect, src, 0, keep_proportion=True)",
  "    page.insert_text((x0 + 4, y0 + 12), labels[i], fontsize=14, fontname='times-bold')",
  "    src.close()",
  sprintf("out_path = os.path.join(base, 'Figure 4. ERS panels A-F.pdf')"),
  "out.save(out_path); out.close(); print('wrote', out_path)"
), py)
system2("python3", py)

# 交付只留主图 Figure 4；分面板挪到 _downstream/fig4_panels
panel_arch <- file.path(out_ds, "fig4_panels")
dir.create(panel_arch, recursive = TRUE, showWarnings = FALSE)
for (fn in c(files, "Figure 4B-C. ERS elastic-net inclusion.pdf",
             "Figure S3. ERS subgroup forest.pdf")) {
  src <- file.path(fig_pdf, fn)
  if (file.exists(src)) {
    file.rename(src, file.path(panel_arch, fn))
  }
}
exwas_log("delivery Figures/pdf keeps only main Figure 4; panels archived under fig4_panels/")

# ---- 7) Methods / covariate note ----
cov_note <- c(
  "# Covariate selection: Dong 2026 vs this pan-cancer delivery",
  "",
  "## Paper (Dong 2026 periodontitis)",
  "- Selected **a priori** from DAG + prior exposome–periodontitis literature.",
  "- Model 2: age, sex, race/ethnicity, education, marital status, PIR, BMI, alcohol,",
  "  dental visit / mouthwash / floss, eGFR. Smoke in sensitivity only.",
  "",
  "## This pan-cancer delivery (user-requested data-driven Model2)",
  "- DAG candidate pool (cancer-adapted; no dental vars): ",
  paste0("  ", paste(dag_m2, collapse = ", "), "."),
  "- **A priori excluded from Model2**: Age (cancer strongly age-related; single-adjust",
  "  attenuated ERS OR by ~38%); Smoke (toxicant–smoking collinearity).",
  "- Selection path: **univariate P<0.05** → **VIF<4** → **stepwise AIC (both)**;",
  "  lower scope forces Gender.",
  paste0("- UV keep: ", paste(m2_sel$univariate$keep, collapse = ", "), "."),
  paste0("- VIF keep: ", paste(m2_sel$vif$keep, collapse = ", "),
         if (nrow(m2_sel$vif$dropped)) paste0(" (dropped: ", paste(m2_sel$vif$dropped$variable, collapse = ","), ")") else "",
         "."),
  paste0("- **Model 2 final**: ", paste(covars_m2, collapse = ", "), "."),
  paste0("- Stepwise AIC: ", signif(m2_sel$stepwise$aic_start, 6), " → ",
         signif(m2_sel$stepwise$aic_final, 6), "."),
  "- Limitations: primary Model2 intentionally omits Age; age-stratified Fig4F retained.",
  "- ERS: **gcdnet** adaptive elastic-net; λ grid [1e-5, 100] (50 values) to avoid λ.min glued to boundary;",
  paste0("  full screened pool n=", length(ers_pool), "; 11 alphas; 5-fold CV; Z-score continuous; B=", n_boot, "; seed=123456."),
  paste0("- Selected n=", length(ers_fit$selected), "; alpha=", signif(ers_fit$alpha, 3),
         "; lambda=", signif(ers_fit$lambda, 3), "; gcdnet_used=", ers_fit$gcdnet_used, "."),
  ""
)
writeLines(cov_note, file.path(BASE, "summary_results", "Methods_covariate_and_ERS_alignment.md"))
# also park under reports if exists
dir.create(file.path(BASE, "reports"), showWarnings = FALSE)
writeLines(cov_note, file.path(BASE, "reports", "covariate_ERS_alignment_dong2026.md"))

writeLines(c(
  "# Figure 4. ERS panels A-F",
  "",
  "## 图面说明",
  paste0(
    "上三下三：A 全池 ", length(ers_pool), " 毒物弦图(|r|>0.3)；",
    "B gcdnet α-CV（11 点）；C adaptive gcdnet λ 路径；",
    "D ERS 加权 logistic；E 剂量反应 OR；F Model2 调整后亚组（牙科终点不可得）。",
    "B=", n_boot, "；gcdnet=", ers_fit$gcdnet_used, "；入选=", length(ers_fit$selected), "。"
  ),
  "",
  "## 分析上下文",
  paste0(
    "ERS 全暴露池；Z-score；Model2=", paste(covars_m2, collapse = "+"),
    "。详见 Methods_covariate_and_ERS_alignment.md。"
  )
), file.path(fig_md, "Figure 4. ERS panels A-F.md"))

exwas_log("DONE Fig4 gcdnet B=", n_boot)
print(assoc$table)
print(sg)
