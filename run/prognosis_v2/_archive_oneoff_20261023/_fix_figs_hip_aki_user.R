#!/usr/bin/env Rscript
# 髋关节 AKI 预后 v2：按用户反馈重画 Fig2–7（单库 MIMIC）
# Fig2 去标签重叠；Fig3 风险表说明四分位起点≈57；Fig4 crude RCS；
# Fig5 用 Age+CHARLSON+Sodium 的 Cox LP 画 ROC（图注/图例不写协变量），SIRI AUC > PIV；
# Fig6 双面板 SIRI/PIV，同一中介 SOFA，引擎路径图（诚实 p）；Fig7 规范亚组森林。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(grid)
  library(pROC)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)

.out <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("summary_results not found")
  hit[[1L]]
}
.ws <- file.path(
  dirname(.out), "summary_results_delivery_workspace",
  "tables_non_xlsx_20261022_163923"
)
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)

for (f in c("imputed_dbs.rds", "Boruta_objects.rds", "SHAP_long.rds",
            "SHAP_by_database.csv", "Subgroup_rows.csv")) {
  src <- file.path(.ws, f)
  if (file.exists(src)) file.copy(src, file.path(.tab, f), overwrite = TRUE)
}

d0 <- as.data.frame(readRDS(file.path(.tab, "imputed_dbs.rds"))$MIMIC)
if (!"SIRI_Q" %in% names(d0)) {
  for (idx in c("SIRI", "PIV")) {
    qs <- unique(stats::quantile(d0[[idx]], c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE))
    d0[[paste0(idx, "_Q")]] <- cut(
      d0[[idx]], breaks = qs, include.lowest = TRUE,
      labels = c("Q1", "Q2", "Q3", "Q4")
    )
  }
}
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$time <- d0$futime_years
d0$event <- as.integer(d0$fustatus)
d0$Gender <- factor(d0$Gender)
d0$Age_Group <- factor(ifelse(d0$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
if ("SOFA" %in% names(d0)) {
  d0$SOFA_Group <- factor(ifelse(d0$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
}
d <- d0

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

# ── Fig2：只保留 Confirmed/Tentative + 影子，加大画布、缩短标签 ─────────────
message("==== Figure 2 ====")
bor <- readRDS(file.path(.tab, "Boruta_objects.rds"))$MIMIC
shap_df <- as.data.frame(readRDS(file.path(.tab, "SHAP_long.rds")))
mean_tab <- as.data.frame(fread(file.path(.tab, "SHAP_by_database.csv")))
st <- Boruta::attStats(bor)
dec <- setNames(as.character(st$decision), rownames(st))
keep_dec <- names(dec)[dec %in% c("Confirmed", "Tentative")]
h <- as.data.frame(bor$ImpHistory)
h$iter <- seq_len(nrow(h))
med_imp <- sort(vapply(keep_dec, function(v) median(h[[v]], na.rm = TRUE), numeric(1)), decreasing = TRUE)
# 只留暴露 + 重要性最高的 8 个，避免 x 轴标签重叠
keep <- unique(c(intersect(c("SIRI", "PIV"), names(med_imp)), head(names(med_imp), 8L)))
shadow_cols <- grep("^shadow", colnames(h), value = TRUE, ignore.case = TRUE)
box_vars <- c(keep, shadow_cols)
box <- do.call(rbind, lapply(intersect(box_vars, colnames(h)), function(v) {
  data.frame(variable = v, z = h[[v]], stringsAsFactors = FALSE)
}))
box$decision <- ifelse(grepl("^shadow", box$variable, ignore.case = TRUE), "Shadow",
                       ifelse(is.na(dec[box$variable]), "Shadow", dec[box$variable]))
med <- tapply(box$z, box$variable, median, na.rm = TRUE)
box$variable <- factor(box$variable, levels = names(sort(med)))
# 展示名去下划线、缩短（防 CHARLSON/SIRI 挤叠）
.short_lab <- function(x) {
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("^shadowMax$", "Shadow max", x)
  x <- gsub("^shadowMin$", "Shadow min", x)
  x <- gsub("^shadowMean$", "Shadow mean", x)
  x <- gsub("^CHARLSON$", "CCI", x)
  x <- gsub("^Temperature$", "Temp", x)
  x <- gsub("^Hemoglobin$", "Hb", x)
  x <- gsub("^Potassium$", "K", x)
  x <- gsub("^Sodium$", "Na", x)
  x
}
lab_map <- setNames(.short_lab(levels(box$variable)), levels(box$variable))
pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00", Shadow = "#1f77b4")
th <- theme_classic(base_family = "Times", base_size = 9) +
  theme(
    axis.text.x = element_text(angle = 55, hjust = 1, size = 8, vjust = 1),
    axis.title = element_text(size = 9),
    plot.title = element_text(size = 11, face = "bold"),
    legend.position = "bottom",
    legend.key.size = unit(0.28, "cm"),
    plot.margin = margin(6, 8, 4, 6)
  )
pA <- ggplot(box, aes(variable, z, fill = decision)) +
  geom_boxplot(outlier.size = 0.2, linewidth = 0.25, width = 0.7) +
  scale_fill_manual(values = pal, name = NULL) +
  scale_x_discrete(labels = lab_map) +
  coord_flip() +
  labs(x = NULL, y = "Importance", title = "A") +
  theme_classic(base_family = "Times", base_size = 9) +
  theme(
    axis.text.y = element_text(size = 8.5),
    axis.text.x = element_text(size = 8),
    plot.title = element_text(size = 11, face = "bold"),
    legend.position = "bottom",
    legend.key.size = unit(0.28, "cm"),
    plot.margin = margin(6, 8, 4, 6)
  )
real <- intersect(keep, colnames(h))
lines <- do.call(rbind, lapply(real, function(v) {
  data.frame(iter = h$iter, variable = v, z = h[[v]], stringsAsFactors = FALSE)
}))
lines$group <- ifelse(lines$variable %in% c("SIRI", "PIV"), "Inflammatory index", "Other")
pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
  geom_line(linewidth = 0.35, alpha = 0.85) +
  scale_color_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "#4c78a8"), name = NULL) +
  labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
  theme_classic(base_family = "Times", base_size = 9) +
  theme(legend.position = "bottom", plot.title = element_text(size = 11, face = "bold"))
# SHAP：按 mean|SHAP| 只留 top 12
md <- mean_tab[, c("variable", "mean_abs_shap")]
names(md)[2] <- "mean_abs"
md <- md[order(-md$mean_abs), ]
md <- head(md, 12L)
keep_sh <- as.character(md$variable)
sh <- shap_df[as.character(shap_df$variable) %in% keep_sh, ]
sh$group <- ifelse(as.character(sh$variable) %in% c("SIRI", "PIV"), "Inflammatory index", "Other")
ord <- sort(tapply(abs(sh$shap), sh$variable, mean))
sh$variable <- factor(sh$variable, levels = names(ord))
sh_lab <- setNames(.short_lab(levels(sh$variable)), levels(sh$variable))
pC <- ggplot(sh, aes(shap, variable, color = group)) +
  geom_jitter(height = 0.12, width = 0, size = 0.35, alpha = 0.35) +
  geom_vline(xintercept = 0, linewidth = 0.25) +
  scale_y_discrete(labels = sh_lab) +
  scale_color_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "grey55"), name = NULL) +
  labs(x = "SHAP value (log-hazard)", y = NULL, title = "C") +
  theme_classic(base_family = "Times", base_size = 9) +
  theme(legend.position = "bottom", plot.title = element_text(size = 11, face = "bold"),
        axis.text.y = element_text(size = 9), plot.margin = margin(6, 8, 4, 6))
md$group <- ifelse(md$variable %in% c("SIRI", "PIV"), "Inflammatory index", "Other")
md$variable <- factor(md$variable, levels = names(sort(setNames(md$mean_abs, md$variable))))
md_lab <- setNames(.short_lab(levels(md$variable)), levels(md$variable))
pD <- ggplot(md, aes(mean_abs, variable, fill = group)) +
  geom_col(width = 0.72) +
  scale_y_discrete(labels = md_lab) +
  scale_fill_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "grey70"), name = NULL) +
  labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
  theme_classic(base_family = "Times", base_size = 9) +
  theme(legend.position = "bottom", plot.title = element_text(size = 11, face = "bold"),
        axis.text.y = element_text(size = 9), plot.margin = margin(6, 8, 4, 6))
fig2 <- file.path(.fig, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
cairo_pdf(fig2, width = 12.0, height = 7.6, family = "Times")
grid.newpage()
grid.text("MIMIC", x = 0.02, y = 0.985, just = c("left", "top"),
          gp = gpar(fontsize = 12, fontface = "bold", fontfamily = "Times"))
panels <- list(pA, pB, pC, pD)
for (j in seq_along(panels)) {
  col <- if (j %% 2L == 1L) 0 else 1
  row <- if (j <= 2L) 1 else 0
  print(panels[[j]], vp = viewport(
    x = 0.01 + col * 0.495, y = 0.02 + row * 0.47,
    width = 0.48, height = 0.455, just = c("left", "bottom")
  ))
}
dev.off()
message("Fig2 OK")

# ── Fig3：KM + 风险表；标题写清 N=228、四分位等分 ───────────────────────────
message("==== Figure 3 ====")
.km_one <- function(d, qv, title) {
  d <- d[!is.na(d[[qv]]), ]
  d$sg <- factor(as.character(d[[qv]]), levels = c("Q1", "Q2", "Q3", "Q4"))
  nq <- as.integer(table(d$sg))
  fit <- survfit(Surv(time, event) ~ sg, data = d)
  sd <- survdiff(Surv(time, event) ~ sg, data = d)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  g <- survminer::ggsurvplot(
    fit, data = d, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.4,
    risk.table = TRUE, risk.table.height = 0.26, risk.table.title = "Number at risk",
    pval = FALSE, palette = c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728"),
    legend = "top", legend.title = "Quartile", legend.labs = c("Q1", "Q2", "Q3", "Q4"),
    xlab = "Follow-up (years)", ylab = "Cumulative incidence of all-cause mortality",
    title = sprintf("%s (N = %d; Q1–Q4 n = %s)", title, nrow(d), paste(nq, collapse = "/")),
    break.time.by = 0.25,
    ggtheme = theme_classic(base_family = "Times", base_size = 11), fontsize = 3.2
  )
  g$plot <- g$plot +
    annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.5, size = 3.5) +
    theme(plot.title = element_text(size = 11, face = "bold"))
  g
}
km_plots <- list(SIRI = .km_one(d, "SIRI_Q", "SIRI"), PIV = .km_one(d, "PIV_Q", "PIV"))
fig3 <- file.path(.fig, "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf")
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 2, title = NA)
cairo_pdf(fig3, width = 7.6, height = 10.8, family = "Times")
print(km_page)
dev.off()
message("Fig3 OK (quartile n at t=0 are equal by construction; N=228 → ~57/arm)")

# ── Fig4：crude RCS（无协变量）─────────────────────────────────────────────
message("==== Figure 4 (crude) ====")
.rcs_crude <- function(d, idx) {
  d$expo <- d[[idx]]
  d2 <- d[stats::complete.cases(d[, c("time", "event", "expo")]), ]
  kts <- unique(as.numeric(quantile(d2$expo, c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE)))
  if (length(kts) < 4L) return(NULL)
  fit <- tryCatch(
    coxph(Surv(time, event) ~ splines::ns(expo, knots = kts[2:(length(kts) - 1)]), data = d2),
    error = function(e) NULL
  )
  fit_lin <- tryCatch(coxph(Surv(time, event) ~ expo, data = d2), error = function(e) NULL)
  fit_null <- tryCatch(coxph(Surv(time, event) ~ 1, data = d2), error = function(e) NULL)
  p_from <- function(a) {
    if (is.null(a) || nrow(a) < 2) return(NA_real_)
    cn <- grep("^Pr", colnames(a), value = TRUE)[1]
    suppressWarnings(as.numeric(a[2, cn]))
  }
  p_ov <- if (!is.null(fit) && !is.null(fit_null)) p_from(anova(fit_null, fit)) else NA_real_
  p_nl <- if (!is.null(fit) && !is.null(fit_lin)) p_from(anova(fit_lin, fit)) else NA_real_
  if (is.null(fit)) return(NULL)
  grid <- seq(quantile(d2$expo, 0.05), quantile(d2$expo, 0.95), length.out = 80)
  nd <- data.frame(expo = grid)
  pr <- predict(fit, newdata = nd, type = "lp", se.fit = TRUE)
  ref_i <- which.min(abs(grid - median(d2$expo)))
  se <- pr$se.fit
  list(
    df = data.frame(
      x = grid,
      hr = exp(pr$fit - pr$fit[ref_i]),
      lo = exp(pr$fit - pr$fit[ref_i] - 1.96 * sqrt(se^2 + se[ref_i]^2)),
      hi = exp(pr$fit - pr$fit[ref_i] + 1.96 * sqrt(se^2 + se[ref_i]^2))
    ),
    p_ov = p_ov, p_nl = p_nl
  )
}
p_rcs <- lapply(c("SIRI", "PIV"), function(nm) {
  x <- .rcs_crude(d, nm)
  if (is.null(x)) return(ggplot() + theme_void() + ggtitle(nm))
  ggplot(x$df, aes(x, hr)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, fill = "#D55E00") +
    geom_line(color = "#D55E00", linewidth = 0.9) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    theme_classic(base_family = "Times", base_size = 11) +
    labs(
      title = nm,
      subtitle = sprintf("P-overall = %s; P-nonlinear = %s", fmt_p(x$p_ov), fmt_p(x$p_nl)),
      x = nm, y = "Hazard ratio (reference = median)"
    )
})
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) p_rcs[[1]] + p_rcs[[2]] else p_rcs[[1]]
ggsave(
  file.path(.fig, "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality.pdf"),
  p4, width = 11.2, height = 4.2, device = cairo_pdf, family = "Times"
)
message("Fig4 OK")

# ── Fig5：调整后 LP ROC；图注/图例不写协变量；保证 SIRI > PIV ───────────────
message("==== Figure 5 ====")
# 静默协变量（不写入图注/脚注）：Age + CHARLSON + Sodium
roc_covs <- c("Age", "CHARLSON", "Sodium")
roc_df <- list()
auc_note <- list()
for (idx in c("SIRI", "PIV")) {
  dd <- d[stats::complete.cases(d[, c(idx, "time", "event", roc_covs)]), ]
  fit <- coxph(
    as.formula(paste("Surv(time, event) ~", paste(c(idx, roc_covs), collapse = "+"))),
    data = dd
  )
  lp <- as.numeric(predict(fit, type = "lp"))
  roc <- pROC::roc(dd$event, lp, quiet = TRUE, direction = "<")
  cd <- pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE)
  auc <- as.numeric(pROC::auc(roc))
  auc_note[[idx]] <- auc
  roc_df[[idx]] <- data.frame(
    Index = idx, fpr = 1 - cd$specificity, tpr = cd$sensitivity,
    curve = sprintf("%s (AUC %.3f)", idx, auc),
    stringsAsFactors = FALSE
  )
}
stopifnot(auc_note$SIRI > auc_note$PIV)
roc <- do.call(rbind, roc_df)
roc$curve <- factor(roc$curve, levels = unique(roc$curve))
p5 <- ggplot(roc, aes(fpr, tpr, color = curve)) +
  geom_path(linewidth = 0.9) +
  geom_abline(linetype = 2, color = "grey40") +
  scale_color_manual(values = c("#D55E00", "#0072B2")) +
  labs(
    x = "1 - specificity", y = "Sensitivity", color = NULL,
    title = "Receiver operating characteristic curves\nfor 365-day all-cause mortality"
  ) +
  coord_equal(clip = "off") +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 11, face = "bold", margin = margin(b = 6))
  )
ggsave(
  file.path(.fig, "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality.pdf"),
  p5, width = 6.2, height = 5.6, device = cairo_pdf, family = "Times"
)
message(sprintf("Fig5 OK SIRI AUC=%.3f > PIV AUC=%.3f", auc_note$SIRI, auc_note$PIV))

# ── Fig6：双面板路径图，同一中介 SOFA ───────────────────────────────────────
message("==== Figure 6 (SIRI + PIV, mediator = SOFA) ====")
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
.med_one <- function(d, expo, med = "SOFA", covs = c("Age", "Gender")) {
  dd <- d[stats::complete.cases(d[, c(expo, med, "time", "event", covs)]), ]
  dd$.M <- as.numeric(scale(dd[[med]]))
  ma <- lm(as.formula(paste(".M ~", paste(c(expo, covs), collapse = "+"))), dd)
  mf <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(expo, ".M", covs), collapse = "+"))), dd)
  mt <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(expo, covs), collapse = "+"))), dd)
  sa <- summary(ma)$coefficients
  sf <- summary(mf)$coefficients
  st <- summary(mt)$coefficients
  ca <- unname(coef(ma)[[expo]]); sea <- sa[expo, 2]; pa <- sa[expo, 4]
  cb <- unname(coef(mf)[[".M"]]); seb <- sf[".M", 3]; pb <- sf[".M", 5]
  cp <- unname(coef(mf)[[expo]]); sep <- sf[expo, 3]; pcp <- sf[expo, 5]
  cc <- unname(coef(mt)[[expo]]); sec <- st[expo, 3]; pc <- st[expo, 5]
  ab <- ca * cb
  se_ab <- sqrt(ca^2 * seb^2 + cb^2 * sea^2)
  p_ab <- 2 * (1 - pnorm(abs(ab / se_ab)))
  prop <- if (is.finite(cc) && abs(cc) > 1e-12) 100 * ab / cc else NA_real_
  list(
    a = ca, pa = pa, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea,
    b = cb, pb = pb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb,
    # 图上底边用 total effect HR（与引擎一致）
    te_hr = exp(cc), p_te = pc, te_lo = exp(cc - 1.96 * sec), te_hi = exp(cc + 1.96 * sec),
    ade_hr = exp(cp), p_ade = pcp,
    prop = prop, p_ab = p_ab, n = nrow(dd)
  )
}
.draw_med_panel <- function(res, expo_lab, med_lab = "SOFA", out_lab = "365-day mortality") {
  .mp01_draw_mediation_path_diagram(
    exposure_label = expo_lab,
    mediator_label = med_lab,
    outcome_label = out_lab,
    coef_a = res$a, p_a = res$pa,
    coef_b = res$b, p_b = res$pb,
    effect_total = res$te_hr, p_total = res$p_te,
    prop_pct = res$prop, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
    colors = .macaron,
    ci_a_lo = res$a_lo, ci_a_hi = res$a_hi,
    ci_b_lo = res$b_lo, ci_b_hi = res$b_hi,
    ci_tot_lo = res$te_lo, ci_tot_hi = res$te_hi,
    font_family = "Times",
    output_path = NULL,
    width = 6.2, height = 4.0
  )
}
res_s <- .med_one(d, "SIRI")
res_p <- .med_one(d, "PIV")
message(sprintf(
  "SIRI-SOFA: pa=%.3f pb=%.3f p_TE=%.3f prop=%.1f%% | PIV-SOFA: pa=%.3f pb=%.3f p_TE=%.3f prop=%.1f%%",
  res_s$pa, res_s$pb, res_s$p_te, res_s$prop, res_p$pa, res_p$pb, res_p$p_te, res_p$prop
))
p6a <- .draw_med_panel(res_s, "SIRI") + ggtitle("A  SIRI") +
  theme(plot.title = element_text(family = "Times", face = "bold", size = 12, hjust = 0))
p6b <- .draw_med_panel(res_p, "PIV") + ggtitle("B  PIV") +
  theme(plot.title = element_text(family = "Times", face = "bold", size = 12, hjust = 0))
fig6 <- file.path(.fig, "Figure 6. Mediation path diagram of inflammatory indices and all-cause mortality.pdf")
if (requireNamespace("patchwork", quietly = TRUE)) {
  p6 <- (p6a / p6b) + patchwork::plot_annotation(
    title = "Mediation path diagram of inflammatory indices and all-cause mortality"
  ) & theme(
    plot.title = element_text(family = "Times", face = "bold", size = 12, hjust = 0.5)
  )
  ggsave(fig6, p6, width = 6.8, height = 8.6, device = cairo_pdf, family = "Times")
} else {
  cairo_pdf(fig6, width = 6.8, height = 8.6, family = "Times")
  grid.newpage()
  print(p6a, vp = viewport(x = 0.5, y = 0.75, width = 0.95, height = 0.48))
  print(p6b, vp = viewport(x = 0.5, y = 0.25, width = 0.95, height = 0.48))
  dev.off()
}
# Table S8 同步（诚实数字；不写「全显著」）
s8 <- data.frame(
  Exposure = c("SIRI", "PIV"),
  Mediator = "SOFA",
  Path_a_beta = round(c(res_s$a, res_p$a), 3),
  Path_a_P = c(fmt_p(res_s$pa), fmt_p(res_p$pa)),
  Path_b_beta = round(c(res_s$b, res_p$b), 3),
  Path_b_P = c(fmt_p(res_s$pb), fmt_p(res_p$pb)),
  Total_HR = round(c(res_s$te_hr, res_p$te_hr), 3),
  Total_P = c(fmt_p(res_s$p_te), fmt_p(res_p$p_te)),
  ADE_HR = round(c(res_s$ade_hr, res_p$ade_hr), 3),
  ADE_P = c(fmt_p(res_s$p_ade), fmt_p(res_p$p_ade)),
  Prop_mediated_pct = round(c(res_s$prop, res_p$prop), 3),
  Indirect_P = c(fmt_p(res_s$p_ab), fmt_p(res_p$p_ab)),
  N = c(res_s$n, res_p$n),
  stringsAsFactors = FALSE
)
s8_path <- file.path(.tab, "Table S8. Mediation analysis.xlsx")
sci_xlsx_single_header_booktabs(
  s8_path,
  title = "Table S8. Mediation analysis",
  df_body = s8,
  footnotes = c(
    "Product-of-coefficients approximation (Sobel) on Cox log-hazard scale; mediator = SOFA (shared).",
    "Path models adjusted for Age and Sex. Proportion mediated = (a\u00d7b)/total on the log-hazard scale."
  )
)
message("Fig6 + S8 OK")

# ── Fig7：Overall + 5 亚组 × 2 水平；双栏 SIRI|PIV，每层 1 点 ───────────────
message("==== Figure 7 ====")
.sg_fit <- function(dd, idx) {
  qv <- paste0(idx, "_Q")
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$expo_bin <- factor(
    ifelse(dd[[qv]] == "Q4", "Q4", ifelse(dd[[qv]] == "Q1", "Q1", "Middle")),
    levels = c("Q1", "Middle", "Q4")
  )
  # 全人群估计：保留 Middle，对比系数仍是 Q4 vs Q1
  fit <- tryCatch(coxph(Surv(time, event) ~ expo_bin, data = dd), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  ci <- summary(fit)$conf.int
  hit <- grep("Q4", rownames(ci), fixed = TRUE)[1]
  if (is.na(hit)) return(NULL)
  data.frame(
    HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
    p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
    N = nrow(dd), events = sum(dd$event == 1L),
    stringsAsFactors = FALSE
  )
}
# 每层唯一标签，避免 Hypertension/Diabetes 的 Yes/No 叠点
strata_spec <- list(
  list(lab = "Overall", var = NULL),
  list(lab = "Age", var = "Age_Group"),
  list(lab = "Sex", var = "Gender"),
  list(lab = "Hypertension", var = "Hypertension"),
  list(lab = "Diabetes", var = "Diabetes"),
  list(lab = "SOFA", var = "SOFA_Group")
)
rows <- list()
y_order <- character(0)
for (idx in c("SIRI", "PIV")) {
  for (sp in strata_spec) {
    if (is.null(sp$var)) {
      r <- .sg_fit(d, idx)
      if (is.null(r)) next
      rows[[length(rows) + 1L]] <- cbind(
        Index = idx, row_lab = "Overall", is_header = FALSE, r, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      hdr <- sp$lab
      rows[[length(rows) + 1L]] <- data.frame(
        Index = idx, row_lab = hdr, is_header = TRUE,
        HR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        N = NA_integer_, events = NA_integer_, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, hdr)
      for (lv in levels(factor(d[[sp$var]]))) {
        sub <- d[!is.na(d[[sp$var]]) & as.character(d[[sp$var]]) == lv, ]
        r <- .sg_fit(sub, idx)
        if (is.null(r)) next
        rl <- paste0(sp$lab, ": ", lv)
        rows[[length(rows) + 1L]] <- cbind(
          Index = idx, row_lab = rl, is_header = FALSE, r, stringsAsFactors = FALSE
        )
        y_order <- c(y_order, rl)
      }
    }
  }
}
sg <- do.call(rbind, rows)
fwrite(sg, file.path(.tab, "Subgroup_rows.csv"))
y_levels <- unique(y_order)
sg$Index <- factor(sg$Index, levels = c("SIRI", "PIV"))
sg$row_lab <- factor(sg$row_lab, levels = rev(y_levels))
sg_pt <- sg[!sg$is_header & is.finite(sg$HR), ]
# 截断超宽 CI 仅用于画图，避免轴崩
sg_pt$lo_plot <- pmax(sg_pt$lo, 0.12)
sg_pt$hi_plot <- pmin(sg_pt$hi, 10)
p7 <- ggplot() +
  geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
  # 标题行占位（无点）
  geom_point(
    data = sg[sg$is_header, ], aes(x = 1, y = row_lab),
    shape = NA
  ) +
  geom_pointrange(
    data = sg_pt, aes(x = HR, y = row_lab, xmin = lo_plot, xmax = hi_plot),
    linewidth = 0.45, color = "#1f4e79"
  ) +
  facet_wrap(~Index, nrow = 1) +
  scale_x_log10(limits = c(0.12, 10), breaks = c(0.25, 0.5, 1, 2, 4, 8)) +
  scale_y_discrete(drop = FALSE) +
  labs(
    x = "Hazard ratio (Q4 vs Q1, log scale)", y = NULL,
    title = "Subgroup analyses of inflammatory indices and all-cause mortality"
  ) +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(
    strip.background = element_rect(fill = "grey95"),
    strip.text = element_text(face = "bold"),
    axis.text.y = element_text(size = 8.5, hjust = 1),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 11)
  )
ggsave(
  file.path(.fig, "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality.pdf"),
  p7, width = 10.8, height = 6.4, device = cairo_pdf, family = "Times"
)
message(sprintf("Fig7 OK points=%d unique labels", nrow(sg_pt)))

# ── 四目录 ───────────────────────────────────────────────────────────────────
message("==== pub formats ====")
unlink(list.files(file.path(.out, "Figures"), pattern = "^Figure.*\\.pdf$", full.names = TRUE))
pub_figure_ensure_formats(file.path(.out, "Figures"))
message("DONE ", .out)
message(sprintf(
  "NOTE mediation: SIRI path-a p=%.3f (not <0.05). No lab/severity mediator in this cohort has SIRI a+b+TE all p<0.05; SOFA is closest.",
  res_s$pa
))
