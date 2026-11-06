#!/usr/bin/env Rscript
# Fig4–7 对齐 Hip prognosis_v2_41904528：
# Fig4 RCS 不加协变量；Fig5 ggplot ROC；Fig6 引擎中介路径图；Fig7 森林图版式

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(grid)
  library(splines)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/subgroup_forest_plot.R"), local = FALSE)
source(file.path(.engine, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)

.proj <- stroke_anlr_proj()
.out <- stroke_anlr_out(.proj)
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
IDX <- "ANLR"

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
.qsc_meta <- .lock$meta
fmt_p <- function(p) {
  if (!is.finite(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

# ============================================================
# Fig4：不加协变量（crude / Model 1）；双库并排；HR 锚定 mean/0 SD
# ============================================================
message("==== Fig4 RCS unadjusted ====")
.rcs_crude <- function(d, idx) {
  d2 <- as.data.frame(d)
  d2$time <- as.numeric(d2$futime_years)
  d2$event <- as.integer(d2$fustatus)
  d2 <- d2[is.finite(d2$time) & d2$time > 0 & !is.na(d2$event) & is.finite(d2[[idx]]), ]
  d2$expo <- as.numeric(scale(d2[[idx]]))
  kts <- unique(as.numeric(quantile(d2$expo, c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE)))
  inner <- if (length(kts) >= 4L) kts[2:(length(kts) - 1)] else kts
  fit <- tryCatch(
    coxph(Surv(time, event) ~ splines::ns(expo, knots = inner), data = d2),
    error = function(e) NULL
  )
  fit_lin <- tryCatch(coxph(Surv(time, event) ~ expo, data = d2), error = function(e) NULL)
  p_from <- function(a) {
    if (is.null(a) || nrow(a) < 2) return(NA_real_)
    cn <- grep("^Pr", colnames(a), value = TRUE)[1]
    suppressWarnings(as.numeric(a[2, cn]))
  }
  p_lin <- if (!is.null(fit_lin)) summary(fit_lin)$coefficients["expo", "Pr(>|z|)"] else NA_real_
  p_nl <- if (!is.null(fit) && !is.null(fit_lin)) p_from(anova(fit_lin, fit)) else NA_real_
  if (is.null(fit)) return(NULL)
  grid <- seq(quantile(d2$expo, 0.05), quantile(d2$expo, 0.95), length.out = 80)
  nd <- data.frame(expo = grid)
  pr <- predict(fit, newdata = nd, type = "lp", se.fit = TRUE)
  ref_i <- which.min(abs(grid - 0))
  hr <- exp(pr$fit - pr$fit[ref_i])
  se <- pr$se.fit
  lo <- exp(pr$fit - pr$fit[ref_i] - 1.96 * sqrt(se^2 + se[ref_i]^2))
  hi <- exp(pr$fit - pr$fit[ref_i] + 1.96 * sqrt(se^2 + se[ref_i]^2))
  list(
    df = data.frame(x = grid, hr = hr, lo = lo, hi = hi),
    p_lin = p_lin, p_nl = p_nl,
    lin_hr = if (!is.null(fit_lin)) unname(exp(coef(fit_lin)["expo"])) else NA_real_
  )
}
rcs_list <- lapply(names(dbs), function(nm) .rcs_crude(dbs[[nm]], IDX))
names(rcs_list) <- names(dbs)
p_rcs <- lapply(names(rcs_list), function(nm) {
  x <- rcs_list[[nm]]
  if (is.null(x)) return(ggplot() + theme_void() + ggtitle(nm))
  ggplot(x$df, aes(x, hr)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, fill = "#D55E00") +
    geom_line(color = "#D55E00", linewidth = 0.9) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    theme_classic(base_size = 11, base_family = "Times") +
    labs(
      title = nm,
      subtitle = sprintf("P-linear = %s; P-nonlinear = %s", fmt_p(x$p_lin), fmt_p(x$p_nl)),
      x = paste0(IDX, " (per 1 SD)"),
      y = "Hazard ratio (reference = mean / 0 SD)"
    )
})
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) p_rcs[[1]] + p_rcs[[2]] else p_rcs[[1]]
ggsave(
  file.path(.fig, "Figure 4. Restricted cubic spline of ANLR and all-cause mortality.pdf"),
  p4, width = 11.2, height = 4.2, device = cairo_pdf, family = "Times"
)
for (nm in names(rcs_list)) {
  x <- rcs_list[[nm]]
  message(sprintf("  Fig4 %s unadj: P-lin=%s P-nl=%s linHR=%.3f",
                  nm, fmt_p(x$p_lin), fmt_p(x$p_nl), x$lin_hr))
}

# ============================================================
# Fig5：Hip 同款 ggplot ROC（双库两条曲线；Cox LP；图例只写 AUC）
# ============================================================
message("==== Fig5 ROC Hip style ====")
.roc_covs_prefer <- c("Age", "Sodium", "GCS")
roc_df <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  covs <- intersect(.roc_covs_prefer, names(d))
  need <- c(IDX, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, ]
  fit <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(IDX, covs), collapse = "+"))), dd)
  lp <- as.numeric(predict(fit, type = "lp"))
  roc <- pROC::roc(dd$event, lp, quiet = TRUE, direction = "<")
  cd <- pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE)
  auc <- as.numeric(pROC::auc(roc))
  roc_df[[nm]] <- data.frame(
    Database = nm, fpr = 1 - cd$specificity, tpr = cd$sensitivity,
    curve = sprintf("%s (AUC %.3f)", nm, auc),
    stringsAsFactors = FALSE
  )
}
roc <- do.call(rbind, roc_df)
roc$curve <- factor(roc$curve, levels = unique(roc$curve))
p5 <- ggplot(roc, aes(fpr, tpr, color = curve)) +
  geom_path(linewidth = 0.9) +
  geom_abline(linetype = 2, color = "grey40") +
  scale_color_manual(values = c("#D55E00", "#0072B2")) +
  labs(
    x = "1 - specificity", y = "Sensitivity", color = NULL,
    title = paste0("Receiver operating characteristic curves\nfor ", .endpoint)
  ) +
  coord_equal(clip = "off") +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(size = 11, face = "bold", margin = margin(b = 6))
  )
ggsave(
  file.path(.fig, sprintf("Figure 5. Receiver operating characteristic curves for %s.pdf", .endpoint)),
  p5, width = 6.2, height = 5.6, device = cairo_pdf, family = "Times"
)
message("Fig5 OK")

# ============================================================
# Fig6：引擎马卡龙路径图（MIMIC / eICU 上下；数字与 S8 Direct 同源）
# ============================================================
message("==== Fig6 mediation Hip style ====")
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
# 中介优先读 S7 筛选落盘；无则回退 SOFA（旧锁）
.best_med <- {
  pref <- file.path(.tab, "preferred_mediator.txt")
  if (file.exists(pref)) {
    ln <- grep("^best_mediator=", readLines(pref, warn = FALSE), value = TRUE)
    if (length(ln)) sub("^best_mediator=", "", ln[[1]]) else "SOFA"
  } else "SOFA"
}
message("Fig6 mediator = ", .best_med, " (correlation-first)")
.med_fit_z <- function(d, expo, med = .best_med, covs = c("Age", "Gender")) {
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  if ("Gender" %in% covs && "Gender" %in% names(d)) d$Gender <- factor(d$Gender)
  need <- c(expo, med, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, ]
  dd$.E <- as.numeric(scale(dd[[expo]]))
  dd$.M <- as.numeric(scale(dd[[med]]))
  ma <- lm(as.formula(paste(".M ~", paste(c(".E", covs), collapse = "+"))), dd)
  mf <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", ".M", covs), collapse = "+"))), dd)
  mt <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", covs), collapse = "+"))), dd)
  sa <- summary(ma)$coefficients
  sf <- summary(mf)$coefficients
  st <- summary(mt)$coefficients
  ca <- sa[".E", 1]; sea <- sa[".E", 2]; pa <- sa[".E", 4]
  cb <- sf[".M", 1]; seb <- sf[".M", 3]; pb <- sf[".M", 5]
  cp <- sf[".E", 1]; sep <- sf[".E", 3]; p_de <- sf[".E", 5]
  cc <- st[".E", 1]
  ab <- ca * cb
  list(
    a = ca, pa = pa, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea,
    b = cb, pb = pb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb,
    de_hr = exp(cp), p_de = p_de, de_lo = exp(cp - 1.96 * sep), de_hi = exp(cp + 1.96 * sep),
    te_hr = exp(cc), prop = 100 * ab / cc, n = nrow(dd)
  )
}
.draw_med <- function(res, db_lab) {
  .mp01_draw_mediation_path_diagram(
    exposure_label = paste0(IDX, " (per 1 SD)"), mediator_label = .best_med,
    outcome_label = paste0(.day_lab, " mortality"),
    coef_a = res$a, p_a = res$pa, coef_b = res$b, p_b = res$pb,
    effect_total = res$de_hr, p_total = res$p_de,
    prop_pct = res$prop, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
    colors = .macaron,
    ci_a_lo = res$a_lo, ci_a_hi = res$a_hi,
    ci_b_lo = res$b_lo, ci_b_hi = res$b_hi,
    ci_tot_lo = res$de_lo, ci_tot_hi = res$de_hi,
    font_family = "Times", output_path = NULL, width = 6.2, height = 4.0
  ) + ggplot2::ggtitle(db_lab) +
    ggplot2::theme(plot.title = ggplot2::element_text(family = "Times", face = "bold", size = 12, hjust = 0))
}
db_order <- intersect(c("MIMIC", "eICU"), names(dbs))
med_res <- lapply(db_order, function(nm) .med_fit_z(dbs[[nm]], IDX))
names(med_res) <- db_order
p6_list <- Map(.draw_med, med_res, paste0(c("A  ", "B  "), db_order))
.fig6_title <- paste0("Mediation path diagram of ANLR and ", .endpoint)
unlink(list.files(.fig, pattern = "^Figure 6\\. Mediation path diagram.*\\.pdf$", full.names = TRUE))
fig6 <- file.path(.fig, paste0("Figure 6. ", .fig6_title, ".pdf"))
if (requireNamespace("patchwork", quietly = TRUE)) {
  ggsave(
    fig6,
    (p6_list[[1]] / p6_list[[2]]) + patchwork::plot_annotation(title = .fig6_title),
    width = 6.8, height = 8.6, device = cairo_pdf, family = "Times"
  )
} else {
  cairo_pdf(fig6, width = 6.8, height = 8.6, family = "Times")
  grid.newpage()
  print(p6_list[[1]], vp = viewport(x = 0.5, y = 0.75, width = 0.95, height = 0.48))
  print(p6_list[[2]], vp = viewport(x = 0.5, y = 0.25, width = 0.95, height = 0.48))
  dev.off()
}
message("Fig6 OK")

# ============================================================
# Fig7：Hip 森林版式；层内未调整；Q4 vs Q1；双库 facet
# ============================================================
message("==== Fig7 subgroup Hip style ====")
.sg_prep <- function(dd) {
  qv <- paste0(IDX, "_Group")
  dd <- as.data.frame(dd)
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$time <- as.numeric(dd$futime_years)
  dd$event <- as.integer(dd$fustatus)
  dd <- dd[is.finite(dd$time) & dd$time > 0 & !is.na(dd$event), ]
  dd$expo_bin <- subgroup_collapse_middle_levels(dd[[qv]], levels = .qsc_meta$labels)
  dd
}
.sg_fit <- function(dd) {
  dd <- .sg_prep(dd)
  if (nrow(dd) < 20L || sum(dd$event) < 3L) return(NULL)
  fit <- tryCatch(coxph(Surv(time, event) ~ expo_bin, data = dd), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  ci <- summary(fit)$conf.int
  high <- .qsc_meta$labels[length(.qsc_meta$labels)]
  hit <- grep(high, rownames(ci), fixed = TRUE)[1]
  if (is.na(hit)) hit <- nrow(ci)
  data.frame(
    HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
    p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
    N = nrow(dd), events = sum(dd$event == 1L),
    stringsAsFactors = FALSE
  )
}
.sg_pint <- function(dd, svar) {
  dd <- .sg_prep(dd)
  if (!svar %in% names(dd)) return(NA_real_)
  dd$sg <- factor(dd[[svar]])
  if (nlevels(dd$sg) < 2L) return(NA_real_)
  m0 <- tryCatch(coxph(Surv(time, event) ~ expo_bin + sg, data = dd), error = function(e) NULL)
  m1 <- tryCatch(coxph(Surv(time, event) ~ expo_bin * sg, data = dd), error = function(e) NULL)
  if (is.null(m0) || is.null(m1)) return(NA_real_)
  a <- tryCatch(anova(m0, m1), error = function(e) NULL)
  if (is.null(a) || nrow(a) < 2L) return(NA_real_)
  cn <- grep("^P", colnames(a), value = TRUE)[1]
  suppressWarnings(as.numeric(a[2, cn]))
}

# 准备分层变量（展示名对齐 Hip：Age / Sex / …）
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  if (!"Age_Group" %in% names(d) || nlevels(factor(d$Age_Group)) != 2L) {
    d$Age_Group <- factor(ifelse(d$Age < 65, "< 65", "\u2265 65"), levels = c("< 65", "\u2265 65"))
  } else {
    # 统一标签空格
    lv <- as.character(d$Age_Group)
    lv <- gsub(">=", "\u2265", lv)
    d$Age_Group <- factor(lv)
  }
  if ("Gender" %in% names(d)) {
    g <- as.character(d$Gender)
    g[g %in% c("M", "male", "Male")] <- "Male"
    g[g %in% c("F", "female", "Female")] <- "Female"
    d$Gender <- factor(g, levels = c("Female", "Male"))
  }
  for (v in c("Hypertension", "Diabetes", "Ventilation")) {
    if (!v %in% names(d)) next
    x <- as.character(d[[v]])
    x[x %in% c("1", "Yes", "yes", "TRUE")] <- "Yes"
    x[x %in% c("0", "No", "no", "FALSE")] <- "No"
    d[[v]] <- factor(x, levels = c("No", "Yes"))
  }
  if ("SOFA" %in% names(d)) {
    d$SOFA_Group <- factor(ifelse(d$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
  }
  dbs[[nm]] <- d
}

strata_spec <- list(
  list(lab = "Overall", var = NULL),
  list(lab = "Age", var = "Age_Group"),
  list(lab = "Sex", var = "Gender"),
  list(lab = "Hypertension", var = "Hypertension"),
  list(lab = "Diabetes", var = "Diabetes"),
  list(lab = "SOFA", var = "SOFA_Group")
)

rows <- list(); y_order <- character(0)
for (nm in db_order) {
  d <- dbs[[nm]]
  for (sp in strata_spec) {
    if (is.null(sp$var)) {
      r <- .sg_fit(d)
      if (is.null(r)) next
      rows[[length(rows) + 1L]] <- cbind(
        Database = nm, row_lab = "Overall", is_header = FALSE,
        pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      pint <- .sg_pint(d, sp$var)
      pint_lab <- if (is.finite(pint)) {
        if (pint < 0.001) "P-int <0.001" else sprintf("P-int = %.3f", pint)
      } else "P-int = —"
      rows[[length(rows) + 1L]] <- data.frame(
        Database = nm, row_lab = sp$lab, is_header = TRUE,
        pint_lab = pint_lab, p_interaction = pint,
        HR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        N = NA_integer_, events = NA_integer_, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, sp$lab)
      for (lv in levels(factor(d[[sp$var]]))) {
        sub <- d[!is.na(d[[sp$var]]) & as.character(d[[sp$var]]) == lv, ]
        r <- .sg_fit(sub)
        if (is.null(r)) next
        rl <- paste0(sp$lab, ": ", lv)
        rows[[length(rows) + 1L]] <- cbind(
          Database = nm, row_lab = rl, is_header = FALSE,
          pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE
        )
        y_order <- c(y_order, rl)
      }
    }
  }
}
sg <- do.call(rbind, rows)
fwrite(sg, file.path(.tab, "Subgroup_rows.csv"))
y_levels <- unique(y_order)
sg$Database <- factor(sg$Database, levels = db_order)
sg$row_lab <- factor(sg$row_lab, levels = rev(y_levels))
sg_pt <- sg[!sg$is_header & is.finite(sg$HR), ]
sg_pt$lo_plot <- pmax(sg_pt$lo, 0.05)
sg_pt$hi_plot <- pmin(sg_pt$hi, 10)
sg_hdr <- sg[sg$is_header, ]
.contrast_lab <- paste(
  .qsc_meta$labels[length(.qsc_meta$labels)], "vs", .qsc_meta$labels[1]
)
p7 <- ggplot() +
  geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
  geom_point(data = sg_hdr, aes(x = 1, y = row_lab), shape = NA) +
  geom_pointrange(
    data = sg_pt, aes(x = HR, y = row_lab, xmin = lo_plot, xmax = hi_plot),
    linewidth = 0.45, color = "#1f4e79"
  ) +
  geom_text(
    data = sg_hdr, aes(x = 8.5, y = row_lab, label = pint_lab),
    hjust = 1, size = 2.6, family = "Times", color = "#333333"
  ) +
  facet_wrap(~Database, nrow = 1) +
  scale_x_log10(limits = c(0.05, 10), breaks = c(0.1, 0.25, 0.5, 1, 2, 4, 8)) +
  scale_y_discrete(drop = TRUE) +
  labs(
    x = sprintf("Hazard ratio (%s, log scale)", .contrast_lab), y = NULL,
    title = paste0("Subgroup analyses of ANLR and ", .endpoint)
  ) +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(
    strip.background = element_rect(fill = "grey95"),
    strip.text = element_text(face = "bold"),
    axis.text.y = element_text(size = 8.5, hjust = 1),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 11)
  )
unlink(list.files(.fig, pattern = "^Figure 7\\. Subgroup analyses.*\\.pdf$", full.names = TRUE))
ggsave(
  file.path(.fig, paste0("Figure 7. Subgroup analyses of ANLR and ", .endpoint, ".pdf")),
  p7, width = 11.2, height = 6.6, device = cairo_pdf, family = "Times"
)
message("Fig7 OK")

# image_information
.write_md <- function(stem, body) {
  writeLines(body, file.path(.out, "Figures", "image_information", paste0(stem, ".md")))
}
.write_md(
  "Figure 4. Restricted cubic spline of ANLR and all-cause mortality",
  c(
    "# Figure 4. Restricted cubic spline of ANLR and all-cause mortality",
    "",
    "## 图面说明",
    "双库并排 RCS；**不加协变量（crude / Model 1）**；暴露 ANLR per 1 SD。",
    "纵轴 Hazard ratio（reference = mean / 0 SD）；阴影 95% CI。",
    paste0(
      "图上标注：",
      paste(vapply(names(rcs_list), function(nm) {
        x <- rcs_list[[nm]]
        sprintf("%s P-linear=%s; P-nonlinear=%s", nm, fmt_p(x$p_lin), fmt_p(x$p_nl))
      }, character(1)), collapse = "；"), "。"
    ),
    "",
    "## 分析上下文",
    "- 暴露: ANLR (per 1 SD)",
    paste0("- 结局: ", .endpoint),
    "- 调整: none (unadjusted)",
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 是（左右分库）"
  )
)
.write_md(
  sprintf("Figure 5. Receiver operating characteristic curves for %s", .endpoint),
  c(
    paste0("# Figure 5. Receiver operating characteristic curves for ", .endpoint),
    "",
    "## 图面说明",
    "单画面双曲线（MIMIC / eICU），Cox 线性预测子 ROC；图例仅 AUC。",
    "版式对齐 Hip Figure 5。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    paste0("- 结局: ", .endpoint),
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 单图双曲线"
  )
)
.write_md(
  paste0("Figure 6. Mediation path diagram of ANLR and ", .endpoint),
  c(
    paste0("# Figure 6. Mediation path diagram of ANLR and ", .endpoint),
    "",
    "## 图面说明",
    paste0("上下两面板（A MIMIC / B eICU）；ANLR (per 1 SD) → ", .best_med, " → ", .endpoint, "。"),
    "底边箭 = Direct effect HR（与 Table S8 同源）；调整 Age + Gender（Table 3 Model 2）。",
    paste0("中介由 Table S7 相关性筛选后按预后套路选出为 ", .best_med, "（非预锁 SOFA）。"),
    "版式对齐 Hip 马卡龙路径图。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    paste0("- 中介: ", .best_med, "（S7→S8）"),
    paste0("- 结局: ", .endpoint),
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 是（上下分库）"
  )
)
.write_md(
  paste0("Figure 7. Subgroup analyses of ANLR and ", .endpoint),
  c(
    paste0("# Figure 7. Subgroup analyses of ANLR and ", .endpoint),
    "",
    "## 图面说明",
    paste0("双库 facet 森林图；主终点=", .endpoint, "；对比 ", .contrast_lab, "（中间分位并为 Middle，全样本估计）。"),
    "层内未调整；分层标题行标注 P-int。分层：Age / Sex / Hypertension / Diabetes / SOFA。",
    "版式对齐 Hip Figure 7。",
    "",
    "## 分析上下文",
    "- 暴露: ANLR",
    paste0("- 结局: ", .endpoint),
    "- 数据库: MIMIC + eICU",
    "- 是否拼图: 是（左右分库）"
  )
)

cfg <- list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
pub_figure_ensure_formats(file.path(.out, "Figures"), config = cfg)
message("done Fig4–7")
