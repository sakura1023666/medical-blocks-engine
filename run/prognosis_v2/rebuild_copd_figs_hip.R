#!/usr/bin/env Rscript
# COPD prognosis_v2：按缺血卒中 summary_results_14d / Hip 版式重画 Fig1–7
# 用法: Rscript rebuild_copd_figs_hip.R --index ALBI --slug albi [--days 28]
# 数据读自 _archive_flat_summary_results/summary_results_<slug>/Tables
# 写出 by_index/【success】<INDEX>/Figures/{pdf,image_information}

suppressPackageStartupMessages({
  library(data.table); library(survival); library(ggplot2); library(grid); library(splines)
})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args); if (is.na(i) || i >= length(args)) return(default); args[[i + 1L]]
}
IDX <- get_arg("--index", "ALBI")
slug <- get_arg("--slug", tolower(gsub("[^A-Za-z0-9]+", "_", IDX)))
.days <- as.integer(get_arg("--days", "28"))
.day_lab <- paste0(.days, "-day")
.endpoint <- paste0(.day_lab, " all-cause mortality")
.proj <- get_arg("--proj", "/home/user01/medical-blocks/studies-iface/studies/01_COPD/prognosis_v2_41904528")
.engine <- get_arg("--engine", "/home/user01/medical-blocks/engine")
.arch <- file.path(.proj, "_archive_flat_summary_results", paste0("summary_results_", slug), "Tables")
if (!dir.exists(.arch)) stop("missing archive: ", .arch)

.bi <- file.path(.proj, "by_index")
.cands <- list.files(.bi, pattern = paste0("】", IDX, "$"))
if (!length(.cands)) stop("no by_index for ", IDX)
.out <- file.path(.bi, .cands[[1]])
.tab_pub <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
.info <- file.path(.out, "Figures", "image_information")
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.info, recursive = TRUE, showWarnings = FALSE)

setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.engine, "R/subgroup_forest_plot.R"), local = FALSE)
source(file.path(.engine, "R/attrition_log.R"), local = FALSE)
source(file.path(.engine, "R/pv2_index_roc.R"), local = FALSE)
source(file.path(.engine, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)

dbs <- readRDS(file.path(.arch, "imputed_dbs.rds"))
.lock <- readRDS(file.path(.arch, "quantile_scheme_resolved.rds"))
.qsc_meta <- .lock$meta
fmt_p <- function(p) {
  if (!is.finite(p)) return("NA")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
fmt_p_clause <- function(p) {
  if (!is.finite(p)) return("= NA")
  if (p < 0.001) "< 0.001" else sprintf("= %.3f", p)
}
.lab_map <- c(
  Gender = "Sex", Sex = "Sex",
  PlateletCount = "Platelet count", UreaNitrogen = "Urea nitrogen",
  Heart_Failure = "Heart failure", Myocardial_Infarction = "Myocardial infarction",
  Malignant_Tumor = "Malignant tumor", Liver_cirrhosis = "Liver cirrhosis",
  Hyperlipidemia = "Hyperlipidemia", Hypertension = "Hypertension",
  NBPS = "SBP", NBPD = "DBP", RR = "Respiratory rate", HR = "Heart rate",
  SpO2 = "SpO2", Temperature = "Temperature", Ventilation = "Ventilation",
  APSIII = "APSIII", OASIS = "OASIS", GCS = "GCS", RDW = "RDW",
  WBC = "WBC", RBC = "RBC", Hematocrit = "Hematocrit", Hemoglobin = "Hemoglobin",
  Creatinine = "Creatinine", Glucose = "Glucose", Sodium = "Sodium",
  Potassium = "Potassium", Diabetes = "Diabetes", Race = "Race", CKD = "CKD",
  Hepatitis = "Hepatitis", Age = "Age"
)
.lab_disp <- function(x) {
  x <- as.character(x)
  hit <- x %in% names(.lab_map)
  x[hit] <- unname(.lab_map[x[hit]])
  x <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", x)
  pipeline_display_label(x)
}
.write_md <- function(stem, body) writeLines(body, file.path(.info, paste0(stem, ".md")))
# 拉丁衬线：优先 resolve（已拒 NotoCJK）；再兜底 DejaVu
.plot_ff <- if (exists("resolve_plot_font_family", mode = "function")) {
  tryCatch(resolve_plot_font_family("Times New Roman"), error = function(e) "DejaVu Serif")
} else {
  "DejaVu Serif"
}
message("plot font family = ", .plot_ff)
.pdf_dev <- function(path, width, height) {
  if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(path, width = width, height = height, family = .plot_ff)
  } else {
    grDevices::pdf(path, width = width, height = height, useDingbats = FALSE)
  }
}

message("[", IDX, "] figs -> ", .fig)

# ---- Fig1：卒中同款 attrition_draw_outcome_figure（扁双栏 A/B）----
message("==== Fig1 ====")
.fig1_stem <- sprintf("Figure 1. Flow diagram of adults with COPD (%s)", IDX)
tryCatch({
  .fmtn <- function(n) format(as.integer(n), big.mark = ",", trim = TRUE)
  .panel_one <- function(nm) {
    p <- file.path(.arch, sprintf("Flowchart_attrition_%s.csv", nm))
    if (!file.exists(p)) stop("missing attrition ", nm)
    a <- as.data.frame(fread(p))
    nr <- if ("n_remain" %in% names(a)) as.integer(a$n_remain) else as.integer(a$n)
    if (length(nr) < 4L) stop("attrition steps < 4 for ", nm)
    n_top <- nr[1]; n_age <- nr[2]; n_idx <- nr[3]; n_fu <- nr[4]
    d <- as.data.frame(dbs[[nm]])
    n_inc <- nrow(d)
    n_death <- sum(as.integer(d$fustatus) == 1L, na.rm = TRUE)
    n_alive <- n_inc - n_death
    list(
      letter = paste0(if (nm == "MIMIC") "A  " else "B  ", nm),
      top = sprintf("COPD in %s\n(n = %s)", nm, .fmtn(n_top)),
      mid = sprintf("Aged >= 18 years\n(n = %s)", .fmtn(n_age)),
      inc = sprintf("Participants included\n(n = %s)", .fmtn(n_inc)),
      side1 = sprintf("Age < 18\n(n = %s)", .fmtn(n_top - n_age)),
      side2 = paste0(
        sprintf("1. %s missing\n(n = %s)\n", IDX, .fmtn(n_age - n_idx)),
        sprintf("2. Follow-up missing\n(n = %s)", .fmtn(max(0L, n_idx - n_inc)))
      ),
      death = sprintf("%s death\n(n = %s)", .day_lab, .fmtn(n_death)),
      alive = sprintf("Alive day %d\n(n = %s)", .days, .fmtn(n_alive))
    )
  }
  panels <- lapply(c("MIMIC", "eICU"), .panel_one)
  out1 <- file.path(.fig, paste0(.fig1_stem, ".pdf"))
  unlink(out1)
  attrition_draw_outcome_figure(
    out1, panels, width = 12.0, height = 7.0, family = .plot_ff,
    csv_path = file.path(.tab_pub, "Flowchart_attrition.csv")
  )
  .write_md(.fig1_stem, c(
    paste0("# ", .fig1_stem), "", "## 图面说明",
    "双库 A/B 纳排图（对齐卒中 summary_results_14d Fig1）：主列 COPD → Age≥18 → Participants included；",
    paste0("右侧 Exclude：年龄与 ", IDX, " 不可算 / 随访缺失；底部分叉 ", .day_lab, " death vs Alive。"),
    "", "## 分析上下文",
    paste0("- 暴露: ", IDX), paste0("- 结局: ", .endpoint),
    paste0("- 样本量: MIMIC N=", nrow(dbs$MIMIC), "；eICU N=", nrow(dbs$eICU)),
    "- 数据库: MIMIC + eICU", "- 是否拼图: 是（左右分库）"
  ))
  message("Fig1 OK size=", file.info(out1)$size)
}, error = function(e) message("Fig1 fail: ", conditionMessage(e)))

# ---- Fig2：Boruta A(boxplot)+B(Z轨迹)；无 SHAP 时仅 A|B，双库上下 ----
message("==== Fig2 ====")
.fig2_stem <- "Figure 2. Boruta confirmation for all-cause mortality"
tryCatch({
  if (!requireNamespace("Boruta", quietly = TRUE)) stop("need Boruta")
  bor_path <- file.path(.arch, "Boruta_objects.rds")
  if (!file.exists(bor_path)) stop("no Boruta_objects.rds")
  bor_list <- readRDS(bor_path)
  .fig2_ab <- function(bor, db_lab) {
    h <- as.data.frame(bor$ImpHistory)
    h$iter <- seq_len(nrow(h))
    st <- Boruta::attStats(bor)
    real <- setdiff(intersect(rownames(st), colnames(h)), c("shadowMax", "shadowMean", "shadowMin"))
    dec <- setNames(as.character(st$decision), rownames(st))
    box <- do.call(rbind, lapply(real, function(v) {
      data.frame(variable = v, z = h[[v]], stringsAsFactors = FALSE)
    }))
    box$decision <- dec[box$variable]
    box$z[!is.finite(box$z)] <- NA_real_
    med <- tapply(box$z, box$variable, median, na.rm = TRUE)
    box$variable <- factor(.lab_disp(box$variable), levels = .lab_disp(names(sort(med))))
    pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00")
    th_a <- theme_classic(base_size = 7, base_family = .plot_ff) +
      theme(
        axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 4.2),
        legend.position = "top", legend.key.size = unit(0.18, "cm"),
        legend.text = element_text(size = 5),
        legend.margin = margin(0, 0, 0, 0),
        plot.title = element_text(face = "bold", size = 8),
        plot.subtitle = element_text(face = "bold", size = 9, hjust = 0),
        plot.margin = margin(6, 8, 30, 6)
      )
    pA <- ggplot(box, aes(variable, z, fill = decision)) +
      geom_boxplot(outlier.size = 0.12, linewidth = 0.2, na.rm = TRUE) +
      scale_fill_manual(values = pal, name = NULL, drop = TRUE) +
      labs(x = NULL, y = "Importance", title = "A") + th_a +
      coord_cartesian(clip = "off")
    lines <- do.call(rbind, lapply(real, function(v) {
      data.frame(iter = h$iter, variable = v, z = h[[v]], stringsAsFactors = FALSE)
    }))
    lines$group <- ifelse(lines$variable == IDX, "Index", "Other")
    pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
      geom_line(linewidth = 0.2, na.rm = TRUE) +
      scale_color_manual(values = c(Index = "#e74c3c", Other = "#4c78a8"), name = NULL) +
      labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
      theme_classic(base_size = 7, base_family = .plot_ff) +
      theme(
        legend.position = "top", legend.key.size = unit(0.18, "cm"),
        legend.text = element_text(size = 5),
        plot.title = element_text(face = "bold", size = 8),
        plot.margin = margin(4, 6, 10, 4)
      )
    list(title = db_lab, A = pA, B = pB)
  }
  blocks <- lapply(intersect(c("MIMIC", "eICU"), names(bor_list)), function(nm) {
    .fig2_ab(bor_list[[nm]], nm)
  })
  out2 <- file.path(.fig, paste0(.fig2_stem, ".pdf"))
  unlink(out2)
  # 禁止 print(ggplot, vp=) 嵌套 cairo（部分 PDF 阅读器打不开）；改 patchwork/ggsave
  if (!requireNamespace("patchwork", quietly = TRUE)) stop("need patchwork for Fig2")
  row_plots <- lapply(blocks, function(b) {
    (b$A + ggplot2::labs(subtitle = b$title)) | b$B
  })
  p2 <- if (length(row_plots) == 1L) {
    row_plots[[1]]
  } else {
    Reduce(`/`, row_plots)
  }
  p2 <- p2 + patchwork::plot_layout(heights = rep(1, length(row_plots)))
  ggplot2::ggsave(
    out2, p2, width = 11.5, height = 13.5, device = grDevices::cairo_pdf,
    family = .plot_ff, limitsize = FALSE
  )
  # 清理旧 SHAP 角色文件名残留
  unlink(list.files(.fig, pattern = "^Figure 2\\..*SHAP", full.names = TRUE))
  unlink(list.files(.info, pattern = "^Figure 2\\..*SHAP", full.names = TRUE))
  .write_md(.fig2_stem, c(
    paste0("# ", .fig2_stem), "", "## 图面说明",
    "上下 MIMIC / eICU；每库 A=Boruta importance 箱线（Confirmed/Rejected/Tentative），B=Boruta Z-score 迭代轨迹（Index 高亮）。",
    "轴标签为展示名（Sex / Platelet count / Urea nitrogen 等），无编程下划线。",
    "", "## 分析上下文",
    paste0("- 暴露: ", IDX), "- 结局: all-cause mortality",
    "- 数据库: MIMIC + eICU", "- 是否拼图: 是（上下分库）"
  ))
  message("Fig2 OK size=", file.info(out2)$size)
}, error = function(e) message("Fig2 fail: ", conditionMessage(e)))

# ---- Fig3 KM dual vertical ----
message("==== Fig3 ====")
.fig3_stem <- sprintf("Figure 3. Cumulative incidence of %s by %s", .endpoint, IDX)
if (!requireNamespace("survminer", quietly = TRUE)) stop("need survminer")
.km_one <- function(d, qv, title) {
  d <- as.data.frame(d)
  d$time <- if ("futime" %in% names(d)) as.numeric(d$futime) else as.numeric(d$futime_years) * 365.25
  d$event <- as.integer(d$fustatus)
  d <- d[!is.na(d[[qv]]) & is.finite(d$time) & d$time > 0 & !is.na(d$event), ]
  labs <- .qsc_meta$labels
  d$sg <- factor(as.character(d[[qv]]), levels = labs)
  d <- d[!is.na(d$sg), ]
  fit <- survfit(Surv(time, event) ~ sg, data = d)
  sd <- survdiff(Surv(time, event) ~ sg, data = d)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  pal <- c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728", "#1f77b4")[seq_along(labs)]
  tmax <- as.numeric(.days)
  brk <- if (tmax <= 14) 2 else if (tmax <= 28) 7 else if (tmax <= 90) 14 else 30
  g <- survminer::ggsurvplot(
    fit, data = d, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.6,
    risk.table = TRUE, risk.table.height = 0.28, risk.table.title = "Number at risk",
    pval = FALSE, palette = pal,
    legend = "top", legend.title = .qsc_meta$legend_title %||% .lock$scheme,
    legend.labs = labs,
    xlab = "Follow-up (days)",
    ylab = "Cumulative incidence",
    title = title, break.time.by = brk, xlim = c(0, tmax),
    ggtheme = theme_classic(base_size = 11, base_family = "Times"), fontsize = 3.2
  )
  g$plot <- g$plot +
    annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.4, size = 3.4) +
    theme(plot.margin = margin(8, 10, 4, 14), axis.title.y = element_text(size = 10))
  g$table <- g$table + theme(plot.margin = margin(0, 10, 4, 14))
  g
}
qv <- paste0(IDX, "_Group")
km_plots <- lapply(names(dbs), function(nm) .km_one(dbs[[nm]], qv, paste0(nm, " — ", IDX)))
names(km_plots) <- names(dbs)
unlink(list.files(.fig, pattern = "^Figure 3\\.", full.names = TRUE))
fig3 <- file.path(.fig, paste0(.fig3_stem, ".pdf"))
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 2, title = NA)
.pdf_dev(fig3, 8.2, 10.5)
print(km_page)
dev.off()
.write_md(.fig3_stem, c(
  paste0("# ", .fig3_stem), "", "## 图面说明",
  paste0("双库累积发病率（1−KM），分组=", .lock$scheme, "；含 Number at risk 与 Log-rank P；横轴 Follow-up (days) 上限=", .days, "。"),
  "", "## 分析上下文",
  paste0("- 暴露: ", IDX), paste0("- 结局: ", .endpoint),
  paste0("- Grouping: ", .lock$scheme),
  paste0("- 样本量: MIMIC N=", nrow(dbs$MIMIC), "；eICU N=", nrow(dbs$eICU)),
  "- 数据库: MIMIC + eICU", "- 是否拼图: 是（上下分库）"
))
message("Fig3 OK")

# ---- Fig4 RCS ----
message("==== Fig4 ====")
.fig4_stem <- sprintf("Figure 4. Restricted cubic spline of %s and all-cause mortality", IDX)
.rcs_crude <- function(d, idx) {
  d2 <- as.data.frame(d)
  d2$time <- as.numeric(d2$futime_years)
  d2$event <- as.integer(d2$fustatus)
  d2 <- d2[is.finite(d2$time) & d2$time > 0 & !is.na(d2$event) & is.finite(d2[[idx]]), ]
  d2$expo <- as.numeric(scale(d2[[idx]]))
  kts <- unique(as.numeric(quantile(d2$expo, c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE)))
  inner <- if (length(kts) >= 4L) kts[2:(length(kts) - 1)] else kts
  fit <- tryCatch(coxph(Surv(time, event) ~ splines::ns(expo, knots = inner), data = d2), error = function(e) NULL)
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
  pr <- predict(fit, newdata = data.frame(expo = grid), type = "lp", se.fit = TRUE)
  ref_i <- which.min(abs(grid - 0))
  hr <- exp(pr$fit - pr$fit[ref_i]); se <- pr$se.fit
  lo <- exp(pr$fit - pr$fit[ref_i] - 1.96 * sqrt(se^2 + se[ref_i]^2))
  hi <- exp(pr$fit - pr$fit[ref_i] + 1.96 * sqrt(se^2 + se[ref_i]^2))
  list(df = data.frame(x = grid, hr = hr, lo = lo, hi = hi), p_lin = p_lin, p_nl = p_nl)
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
    labs(title = nm,
         subtitle = sprintf("P-linear %s; P-nonlinear %s", fmt_p_clause(x$p_lin), fmt_p_clause(x$p_nl)),
         x = paste0(IDX, " (per 1 SD)"),
         y = "Hazard ratio (reference = mean / 0 SD)")
})
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) p_rcs[[1]] + p_rcs[[2]] else p_rcs[[1]]
unlink(list.files(.fig, pattern = "^Figure 4\\.", full.names = TRUE))
ggsave(file.path(.fig, paste0(.fig4_stem, ".pdf")), p4, width = 11.2, height = 4.2,
       device = cairo_pdf, family = "Times")
.write_md(.fig4_stem, c(
  paste0("# ", .fig4_stem), "", "## 图面说明",
  paste0("双库并排 RCS（crude）；", IDX, " per 1 SD；标注 P-linear / P-nonlinear。"),
  "", "## 分析上下文",
  paste0("- 暴露: ", IDX), paste0("- 结局: ", .endpoint),
  "- 调整: none", "- 数据库: MIMIC + eICU", "- 是否拼图: 是（左右分库）"
))
message("Fig4 OK")

# ---- Fig5 ROC：引擎 pv2_index_roc（与 Table S4 同源；禁 Cox LP）----
message("==== Fig5 ====")
.fig5_stem <- sprintf("Figure 5. Receiver operating characteristic curves for %s", .endpoint)
roc <- pv2_index_roc_curve_by_db(dbs, IDX, event_col = "fustatus")
if (is.null(roc) || !nrow(roc)) stop("Fig5: pv2_index_roc_curve_by_db returned empty")
roc$curve <- factor(roc$curve, levels = unique(roc$curve))
p5 <- ggplot(roc, aes(fpr, tpr, color = curve)) +
  geom_path(linewidth = 0.9) + geom_abline(linetype = 2, color = "grey40") +
  scale_color_manual(values = c("#D55E00", "#0072B2")) +
  labs(x = "1 - specificity", y = "Sensitivity", color = NULL,
       title = paste0("Receiver operating characteristic curves\nfor ", .endpoint),
       subtitle = paste0(IDX, " continuous, unadjusted")) +
  coord_equal(clip = "off") +
  theme_bw(base_family = .plot_ff, base_size = 11) +
  theme(legend.position = "bottom", plot.title = element_text(size = 11, face = "bold"),
        plot.subtitle = element_text(size = 9))
unlink(list.files(.fig, pattern = "^Figure 5\\.", full.names = TRUE))
ggsave(file.path(.fig, paste0(.fig5_stem, ".pdf")), p5, width = 6.2, height = 5.6,
       device = cairo_pdf, family = .plot_ff)
.write_md(.fig5_stem, pv2_index_roc_image_md(.fig5_stem, IDX, .endpoint, dual_db = TRUE))
message("Fig5 OK")

# ---- Fig6 mediation ----
message("==== Fig6 ====")
.fig6_title <- paste0("Mediation path diagram of ", IDX, " and ", .endpoint)
.fig6_stem <- paste0("Figure 6. ", .fig6_title)
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
.best_med <- {
  pref <- file.path(.arch, "preferred_mediator.txt")
  if (file.exists(pref)) {
    ln <- grep("^best_mediator=", readLines(pref, warn = FALSE), value = TRUE)
    if (length(ln)) sub("^best_mediator=", "", ln[[1]]) else "SOFA"
  } else "SOFA"
}
# Prefer mediator from published S8 if present
s8m <- list.files(.tab_pub, pattern = "^Table S8-MIMIC\\. Mediation", full.names = TRUE)
if (length(s8m)) {
  x <- tryCatch(openxlsx::read.xlsx(s8m[[1]], colNames = TRUE), error = function(e) NULL)
  if (!is.null(x) && "Mediator" %in% names(x) && nrow(x) >= 1L) {
    .best_med <- as.character(x$Mediator[[1]])
  }
}
.med_fit_z <- function(d, expo, med = .best_med, covs = c("Age", "Gender")) {
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years); d$event <- as.integer(d$fustatus)
  if ("Gender" %in% covs && "Gender" %in% names(d)) d$Gender <- factor(d$Gender)
  need <- c(expo, med, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, ]
  dd$.E <- as.numeric(scale(dd[[expo]])); dd$.M <- as.numeric(scale(dd[[med]]))
  ma <- lm(as.formula(paste(".M ~", paste(c(".E", covs), collapse = "+"))), dd)
  mf <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", ".M", covs), collapse = "+"))), dd)
  mt <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", covs), collapse = "+"))), dd)
  sa <- summary(ma)$coefficients; sf <- summary(mf)$coefficients; st <- summary(mt)$coefficients
  ca <- sa[".E", 1]; sea <- sa[".E", 2]; pa <- sa[".E", 4]
  cb <- sf[".M", 1]; seb <- sf[".M", 3]; pb <- sf[".M", 5]
  cp <- sf[".E", 1]; sep <- sf[".E", 3]; p_de <- sf[".E", 5]
  cc <- st[".E", 1]; ab <- ca * cb
  list(a = ca, pa = pa, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea,
       b = cb, pb = pb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb,
       de_hr = exp(cp), p_de = p_de, de_lo = exp(cp - 1.96 * sep), de_hi = exp(cp + 1.96 * sep),
       te_hr = exp(cc), prop = 100 * ab / cc, n = nrow(dd))
}
.draw_med <- function(res, db_lab) {
  .mp01_draw_mediation_path_diagram(
    exposure_label = paste0(IDX, " (per 1 SD)"), mediator_label = .best_med,
    outcome_label = paste0(.day_lab, " mortality"),
    coef_a = res$a, p_a = res$pa, coef_b = res$b, p_b = res$pb,
    effect_total = res$de_hr, p_total = res$p_de, prop_pct = round(as.numeric(res$prop), 1),
    prop_lo_pct = NA_real_, prop_hi_pct = NA_real_, colors = .macaron,
    ci_a_lo = res$a_lo, ci_a_hi = res$a_hi, ci_b_lo = res$b_lo, ci_b_hi = res$b_hi,
    ci_tot_lo = res$de_lo, ci_tot_hi = res$de_hi,
    font_family = "Times", output_path = NULL, width = 6.2, height = 4.0
  ) + ggplot2::ggtitle(db_lab) +
    ggplot2::theme(plot.title = ggplot2::element_text(family = "Times", face = "bold", size = 12, hjust = 0))
}
db_order <- intersect(c("MIMIC", "eICU"), names(dbs))
med_res <- lapply(db_order, function(nm) .med_fit_z(dbs[[nm]], IDX))
names(med_res) <- db_order
p6_list <- Map(.draw_med, med_res, paste0(c("A  ", "B  "), db_order))
unlink(list.files(.fig, pattern = "^Figure 6\\.", full.names = TRUE))
fig6 <- file.path(.fig, paste0(.fig6_stem, ".pdf"))
if (requireNamespace("patchwork", quietly = TRUE)) {
  ggsave(fig6, (p6_list[[1]] / p6_list[[2]]) + patchwork::plot_annotation(title = .fig6_title),
         width = 6.8, height = 8.6, device = cairo_pdf, family = "Times")
} else {
  .pdf_dev(fig6, 6.8, 8.6)
  grid.newpage()
  print(p6_list[[1]], vp = viewport(x = 0.5, y = 0.75, width = 0.95, height = 0.48))
  print(p6_list[[2]], vp = viewport(x = 0.5, y = 0.25, width = 0.95, height = 0.48))
  dev.off()
}
.write_md(.fig6_stem, c(
  paste0("# ", .fig6_stem), "", "## 图面说明",
  paste0("上下面板 A MIMIC / B eICU；", IDX, " → ", .best_med, " → ", .endpoint, "；底边 Direct HR 对齐 Table S8。"),
  "", "## 分析上下文",
  paste0("- 暴露: ", IDX), paste0("- 中介: ", .best_med), paste0("- 结局: ", .endpoint),
  "- 数据库: MIMIC + eICU", "- 是否拼图: 是（上下分库）"
))
message("Fig6 OK mediator=", .best_med)

# ---- Fig7 forestploter lit style ----
message("==== Fig7 ====")
.fig7_stem <- paste0("Figure 7. Subgroup analyses of ", IDX, " and ", .endpoint)
.sg_prep <- function(dd) {
  qv <- paste0(IDX, "_Group")
  dd <- as.data.frame(dd)
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$time <- as.numeric(dd$futime_years); dd$event <- as.integer(dd$fustatus)
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
  data.frame(HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
             p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
             N = nrow(dd), events = sum(dd$event == 1L), stringsAsFactors = FALSE)
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
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$Age_Group <- factor(ifelse(d$Age < 65, "< 65", "\u2265 65"), levels = c("< 65", "\u2265 65"))
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
  list(lab = "SOFA", var = "SOFA_Group")
)
rows <- list(); y_order <- character(0)
for (nm in db_order) {
  d <- dbs[[nm]]
  for (sp in strata_spec) {
    if (is.null(sp$var)) {
      r <- .sg_fit(d); if (is.null(r)) next
      rows[[length(rows) + 1L]] <- cbind(
        Database = nm, row_lab = "Overall", is_header = FALSE,
        pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE)
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      pint <- .sg_pint(d, sp$var)
      pint_lab <- if (is.finite(pint)) {
        if (pint < 0.001) "P-int <0.001" else sprintf("%.3f", pint)
      } else "—"
      rows[[length(rows) + 1L]] <- data.frame(
        Database = nm, row_lab = sp$lab, is_header = TRUE, pint_lab = pint_lab,
        p_interaction = pint, HR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        N = NA_integer_, events = NA_integer_, stringsAsFactors = FALSE)
      y_order <- c(y_order, sp$lab)
      for (lv in levels(factor(d[[sp$var]]))) {
        sub <- d[!is.na(d[[sp$var]]) & as.character(d[[sp$var]]) == lv, ]
        r <- .sg_fit(sub); if (is.null(r)) next
        rl <- paste0(" ", lv)
        rows[[length(rows) + 1L]] <- cbind(
          Database = nm, row_lab = rl, is_header = FALSE,
          pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE)
        y_order <- c(y_order, rl)
      }
    }
  }
}
sg <- do.call(rbind, rows)
fwrite(sg, file.path(.tab_pub, "Subgroup_rows.csv"))

# Lock Overall to Table3 Model 1 highest-vs-lowest (Q4/T3/High 行第 1 个 HR 单元格)
.lock_overall <- function(sg_df, db) {
  t3 <- list.files(.tab_pub, pattern = sprintf("^Table 3-%s.*\\.xlsx$", db), full.names = TRUE)
  if (!length(t3)) return(sg_df)
  x <- tryCatch(openxlsx::read.xlsx(t3[[1]], colNames = FALSE), error = function(e) NULL)
  if (is.null(x) || ncol(x) < 2L) return(sg_df)
  lab <- as.character(x[[1]])
  hit <- which(grepl("Quartile\\s*4|Tertile\\s*3|^High$|Group.*High", lab, ignore.case = TRUE))[1]
  if (!is.finite(hit)) return(sg_df)
  cell <- as.character(x[[2]][hit])
  cell <- gsub("\u2013", "-", cell, fixed = TRUE)
  cell <- gsub("&#8211;", "-", cell, fixed = TRUE)
  m <- regexec("([0-9]+\\.[0-9]{3})\\s*\\(([0-9]+\\.[0-9]{3})-([0-9]+\\.[0-9]{3})\\)", cell, perl = TRUE)
  mm <- regmatches(cell, m)
  if (!(length(mm) && length(mm[[1]]) >= 4L)) return(sg_df)
  i <- which(sg_df$Database == db & sg_df$row_lab == "Overall")
  if (!length(i)) return(sg_df)
  message(sprintf("Fig7 Overall lock %s <- Table3 high M1: %s", db, cell))
  sg_df$HR[i[1]] <- as.numeric(mm[[1]][2])
  sg_df$lo[i[1]] <- as.numeric(mm[[1]][3])
  sg_df$hi[i[1]] <- as.numeric(mm[[1]][4])
  sg_df
}
for (db in db_order) sg <- .lock_overall(sg, db)

hr_cell <- function(hr, lo, hi) {
  if (!all(is.finite(c(hr, lo, hi))) || hr < 0.01 || hi > 500) return("NE")
  sprintf("%.3f (%.3f-%.3f)", hr, lo, hi)
}
.to_lit_df <- function(dd) {
  rows <- list(); est <- lo <- hi <- numeric(0)
  for (i in seq_len(nrow(dd))) {
    r <- dd[i, ]
    if (isTRUE(as.logical(r$is_header))) {
      pint <- as.character(r$pint_lab %||% " ")
      pint <- gsub("^P-int\\s*=\\s*", "", pint)
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = as.character(r$row_lab),
        ` ` = paste(rep(" ", 18L), collapse = ""),
        `HR (95% CI)` = " ", `P for interaction` = pint,
        check.names = FALSE, stringsAsFactors = FALSE)
      est <- c(est, NA_real_); lo <- c(lo, NA_real_); hi <- c(hi, NA_real_)
    } else {
      lab <- as.character(r$row_lab)
      sub_lab <- if (identical(lab, "Overall")) "Overall" else paste0("  ", gsub("^\\s+", "", lab))
      pe <- as.numeric(r$HR); l <- as.numeric(r$lo); u <- as.numeric(r$hi)
      cell <- hr_cell(pe, l, u)
      if (identical(cell, "NE")) pe <- l <- u <- NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        Subgroup = sub_lab,
        ` ` = paste(rep(" ", 18L), collapse = ""),
        `HR (95% CI)` = cell, `P for interaction` = " ",
        check.names = FALSE, stringsAsFactors = FALSE)
      est <- c(est, pe); lo <- c(lo, l); hi <- c(hi, u)
    }
  }
  list(df = do.call(rbind, rows), est = est, lo = lo, hi = hi)
}
.contrast_lab <- paste(.qsc_meta$labels[length(.qsc_meta$labels)], "vs", .qsc_meta$labels[1])
if (!requireNamespace("forestploter", quietly = TRUE)) stop("need forestploter")
.draw_one <- function(dd, title) {
  lit <- .to_lit_df(dd)
  disp <- lit$df
  disp$` ` <- rep(disp$` `[1L], nrow(disp))
  tm <- forestploter::forest_theme(
    base_size = 9, base_family = "Times",
    refline_gp = grid::gpar(lty = "solid", col = "black", lwd = 1),
    ci_pch = 18, ci_col = "#2ca02c", ci_fill = "#2ca02c", ci_alpha = 0.95,
    ci_lty = 1, ci_lwd = 1.6, ci_Theight = 0.15,
    core = list(bg_params = list(fill = c("#ffffff", "#f7f7f7"), alpha = 0.35)),
    xlab_gp = grid::gpar(fontsize = 8, fontfamily = "Times"),
    ticks_gp = grid::gpar(fontsize = 7, fontfamily = "Times")
  )
  finite_lo <- lit$lo[is.finite(lit$lo) & lit$lo > 0]
  finite_hi <- lit$hi[is.finite(lit$hi) & lit$hi > 0]
  finite_est <- lit$est[is.finite(lit$est) & lit$est > 0]
  x_lo <- if (length(finite_lo)) max(0.05, min(finite_lo) * 0.7) else 0.05
  x_hi <- if (length(finite_hi)) max(c(finite_hi, finite_est), na.rm = TRUE) * 1.15 else 4
  # 保护向/危险向都要盖住 1；上限勿过小导致 ticks 被滤空
  x_lo <- min(x_lo, 0.5)
  x_hi <- max(x_hi, 4)
  if (!is.finite(x_hi) || x_hi <= x_lo) { x_lo <- 0.2; x_hi <- 8 }
  ticks <- c(0.2, 0.5, 1, 2, 4, 8, 16)
  ticks <- ticks[ticks >= x_lo * 0.95 & ticks <= x_hi * 1.05]
  if (length(ticks) < 2L) ticks <- pretty(c(x_lo, x_hi), n = 4)
  if (length(ticks) < 2L) ticks <- c(x_lo, 1, x_hi)
  ticks <- sort(unique(ticks[is.finite(ticks) & ticks > 0]))
  p <- forestploter::forest(
    disp, est = lit$est, lower = lit$lo, upper = lit$hi,
    ci_column = 2L, sizes = 0.4, ref_line = 1,
    xlim = c(x_lo, x_hi), ticks_at = ticks, x_trans = "log",
    arrow_lab = c("Lower risk", "Higher risk"), theme = tm
  )
  p <- forestploter::edit_plot(p, part = "header", gp = grid::gpar(fontface = "bold"))
  hdr_i <- which(!grepl("^\\s+", disp$Subgroup) & disp$Subgroup != "Overall")
  if (length(hdr_i)) p <- forestploter::edit_plot(p, row = hdr_i, gp = grid::gpar(fontface = "bold"))
  if (!is.null(p$layout) && "clip" %in% names(p$layout)) p$layout$clip[] <- "off"
  list(plot = p, title = title)
}
panels <- lapply(seq_along(db_order), function(i) {
  .draw_one(sg[sg$Database == db_order[[i]], , drop = FALSE], paste0(LETTERS[[i]], "  ", db_order[[i]]))
})
names(panels) <- db_order
unlink(list.files(.fig, pattern = "^Figure 7\\.", full.names = TRUE))
fig7 <- file.path(.fig, paste0(.fig7_stem, ".pdf"))
.pdf_dev(fig7, 10.8, 5.4)
grid.newpage()
grid.text(paste0("Subgroup analyses of ", IDX, " and ", .endpoint),
          x = 0.5, y = 0.985, gp = gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
grid.text(paste0("Contrast: ", .contrast_lab, " (middle quartiles collapsed; unadjusted within strata)"),
          x = 0.5, y = 0.955, gp = gpar(fontsize = 8.5, fontfamily = "Times", col = "grey25"))
n_p <- length(panels)
for (i in seq_along(panels)) {
  pushViewport(viewport(x = (i - 0.5) / n_p, y = 0.48, width = 0.985 / n_p, height = 0.92, just = "centre"))
  grid.text(panels[[i]]$title, x = 0.02, y = 0.99, just = c("left", "top"),
            gp = gpar(fontsize = 10, fontface = "bold", fontfamily = "Times"))
  pushViewport(viewport(y = 0.46, height = 0.90, just = "centre"))
  grid.draw(panels[[i]]$plot)
  popViewport(); popViewport()
}
dev.off()
.write_md(.fig7_stem, c(
  paste0("# ", .fig7_stem), "", "## 图面说明",
  paste0("双库 A/B forestploter；对比 ", .contrast_lab, "；层内未调整；Age/Sex/Hypertension/SOFA；Overall 锁 Table3 Model1。"),
  "", "## 分析上下文",
  paste0("- 暴露: ", IDX), paste0("- 结局: ", .endpoint),
  "- 数据库: MIMIC + eICU", "- 是否拼图: 是（左右分库）"
))
message("Fig7 OK")

# cleanup + ensure formats
cfg <- list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, max_edge_in = 11))
pub_figure_ensure_formats(file.path(.out, "Figures"), config = cfg)
message("[", IDX, "] ALL FIGS DONE")
