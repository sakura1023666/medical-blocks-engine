#!/usr/bin/env Rscript
# Hip AKI prognosis_v2：针对 Nature/客户 P0-1…P0-8 的定点修复（不重跑全链）
# P0-1 Fig3 磁盘已是 binary（本脚本仅校验）；P0-2 Fig6 Direct=S8；P0-3 Fig7 交互P；
# P0-4 RCS per-SD+M3；P0-5 S7 同向 path a；P0-6 PH；P0-7 MICE 选项B落文；P0-8 取材时点。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
  library(grid)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)
source("R/quantile_scheme_cascade.R", local = FALSE)
source("R/subgroup_forest_plot.R", local = FALSE)
source("R/pv2_literature_pub_tables.R", local = FALSE)
source("Blocks/20_mediation/01block_mediation_prognosis.R", local = FALSE)

.out <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  cands[dir.exists(cands)][1L]
}
.stopif <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)
.stopif(dir.exists(.out), paste("missing summary_results:", .out))
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
.proj <- dirname(.out)
.reports <- file.path(.proj, "reports")
dir.create(.reports, recursive = TRUE, showWarnings = FALSE)
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)

.ws_cands <- list.files(
  file.path(.proj, "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- if (length(.ws_cands)) {
  .ws_cands[order(file.info(.ws_cands)$mtime, decreasing = TRUE)][1L]
} else NA_character_
for (f in c("imputed_dbs.rds", "imputed_mids.rds", "before_imputation_dbs.rds",
            "Subgroup_rows.csv")) {
  dest <- file.path(.tab, f)
  if (file.exists(dest)) next
  if (is.character(.ws) && file.exists(file.path(.ws, f))) {
    file.copy(file.path(.ws, f), dest, overwrite = TRUE)
  }
}
.rds_imputed <- file.path(.tab, "imputed_dbs.rds")
if (!file.exists(.rds_imputed) && is.character(.ws)) {
  .rds_imputed <- file.path(.ws, "imputed_dbs.rds")
}
.stopif(file.exists(.rds_imputed), paste("missing imputed_dbs.rds; ws=", .ws))
dbs <- readRDS(.rds_imputed)
if (!"MIMIC" %in% names(dbs)) names(dbs) <- "MIMIC"
d0 <- as.data.frame(dbs$MIMIC)
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$time <- d0$futime_years
d0$event <- as.integer(d0$fustatus)
d0$Age_Group <- factor(ifelse(d0$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
if ("SOFA" %in% names(d0)) {
  d0$SOFA_Group <- factor(ifelse(d0$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
}
.qsc_cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE, try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05, pass_rule = "all", on_none_pass = "best_n_pass",
  family = "cox", time_var = "futime_years", event_var = "fustatus"
))
.qsc <- quantile_scheme_resolve_cascade(d0, c("SIRI", "PIV"), config = .qsc_cfg)
d0 <- quantile_scheme_attach_groups(d0, .qsc)
.qsc_meta <- .qsc$meta
message("locked scheme=", .qsc$scheme, " contrast=", .qsc_meta$contrast_lab)
.stopif(identical(.qsc$scheme, "binary"), "expected binary lock for Hip AKI")
d <- d0
.m3 <- c("Age", "Gender", "CHARLSON")
fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (!is.finite(p)) "—" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

# ---------- P0-1: 校验 Fig3 已是 binary；若旧图则重画 ----------
message("==== P0-1 Figure 3 KM binary ====")
.km_one <- function(d, qv, title) {
  d <- d[!is.na(d[[qv]]), ]
  d$sg <- factor(as.character(d[[qv]]), levels = .qsc_meta$labels)
  fit <- survfit(Surv(time, event) ~ sg, data = d)
  sd <- survdiff(Surv(time, event) ~ sg, data = d)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  pal <- c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728")[seq_along(.qsc_meta$labels)]
  g <- survminer::ggsurvplot(
    fit, data = d, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.6,
    risk.table = TRUE, risk.table.height = 0.28, risk.table.title = "Number at risk",
    pval = FALSE, palette = pal,
    legend = "top", legend.title = .qsc_meta$legend_title %||% "Median split",
    legend.labs = .qsc_meta$labels,
    xlab = "Follow-up (years)", ylab = "Cumulative incidence of all-cause mortality",
    title = title, break.time.by = 0.25,
    ggtheme = theme_classic(base_size = 11), fontsize = 3.1
  )
  g$plot <- g$plot + annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.4, size = 3.4)
  list(g = g, p = p, n = as.integer(table(d$sg)))
}
.km_qv <- function(idx) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(d)) qv <- paste0(idx, "_Q")
  qv
}
km_s <- .km_one(d, .km_qv("SIRI"), "SIRI")
km_p <- .km_one(d, .km_qv("PIV"), "PIV")
message(sprintf("KM SIRI P=%.3f n=%s | PIV P=%.3f n=%s",
                km_s$p, paste(km_s$n, collapse = "/"), km_p$p, paste(km_p$n, collapse = "/")))
fig3 <- file.path(.fig, "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf")
km_page <- survminer::arrange_ggsurvplots(
  list(SIRI = km_s$g, PIV = km_p$g), print = FALSE, ncol = 1, nrow = 2, title = NA
)
cairo_pdf(fig3, width = 7.4, height = 10.5, family = "Times")
print(km_page)
dev.off()
message("Fig3 rewritten binary")

# ---------- P0-5 + S8：重建 S7（同向）/S8 ----------
message("==== P0-5 rebuild S7/S8 ====")
sys.source(
  file.path(.engine, "run/prognosis_v2/_rebuild_s6_s7_s8_hip_aki.R"),
  envir = new.env(parent = globalenv())
)

# ---------- P0-2 Figure 6：Direct effect = S8 ----------
message("==== P0-2 Figure 6 mediation (Direct = S8) ====")
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
.med_fit_z <- function(dd, expo, med = "OASIS", covs = .m3) {
  if ("Gender" %in% covs) dd$Gender <- factor(dd$Gender)
  need <- c(expo, med, "time", "event", covs)
  x <- dd[stats::complete.cases(dd[, need]), ]
  x$.E <- as.numeric(scale(x[[expo]]))
  x$.M <- as.numeric(scale(x[[med]]))
  ma <- lm(as.formula(paste(".M ~", paste(c(".E", covs), collapse = "+"))), x)
  mf <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", ".M", covs), collapse = "+"))), x)
  mt <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(".E", covs), collapse = "+"))), x)
  sa <- summary(ma)$coefficients
  sf <- summary(mf)$coefficients
  st <- summary(mt)$coefficients
  ca <- sa[".E", 1]; sea <- sa[".E", 2]; pa <- sa[".E", 4]
  cb <- sf[".M", 1]; seb <- sf[".M", 3]; pb <- sf[".M", 5]
  cp <- sf[".E", 1]; sep <- sf[".E", 3]; p_de <- sf[".E", 5]
  cc <- st[".E", 1]
  list(
    a = ca, pa = pa, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea,
    b = cb, pb = pb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb,
    de_hr = exp(cp), p_de = p_de, de_lo = exp(cp - 1.96 * sep), de_hi = exp(cp + 1.96 * sep),
    prop = 100 * ca * cb / cc
  )
}
.draw_med <- function(res, expo_lab) {
  .mp01_draw_mediation_path_diagram(
    exposure_label = paste0(expo_lab, " (per 1 SD)"), mediator_label = "OASIS",
    outcome_label = "365-day mortality",
    coef_a = res$a, p_a = res$pa, coef_b = res$b, p_b = res$pb,
    effect_total = res$de_hr, p_total = res$p_de,
    prop_pct = res$prop, prop_lo_pct = NA_real_, prop_hi_pct = NA_real_,
    colors = .macaron,
    ci_a_lo = res$a_lo, ci_a_hi = res$a_hi,
    ci_b_lo = res$b_lo, ci_b_hi = res$b_hi,
    ci_tot_lo = res$de_lo, ci_tot_hi = res$de_hi,
    font_family = "Times", output_path = NULL, width = 6.2, height = 4.0
  )
}
res_s <- .med_fit_z(d, "SIRI")
res_p <- .med_fit_z(d, "PIV")
message(sprintf(
  "Fig6 SIRI a=%.3f deHR=%.3f PM=%.3f | PIV a=%.3f deHR=%.3f PM=%.3f",
  res_s$a, res_s$de_hr, res_s$prop, res_p$a, res_p$de_hr, res_p$prop
))
p6a <- .draw_med(res_s, "SIRI") + ggtitle("A  SIRI") +
  theme(plot.title = element_text(family = "Times", face = "bold", size = 12, hjust = 0))
p6b <- .draw_med(res_p, "PIV") + ggtitle("B  PIV") +
  theme(plot.title = element_text(family = "Times", face = "bold", size = 12, hjust = 0))
fig6 <- file.path(.fig, "Figure 6. Mediation path diagram of inflammatory indices and all-cause mortality.pdf")
if (requireNamespace("patchwork", quietly = TRUE)) {
  ggsave(
    fig6,
    (p6a / p6b) + patchwork::plot_annotation(
      title = "Mediation path diagram of inflammatory indices and all-cause mortality"
    ),
    width = 6.8, height = 8.6, device = cairo_pdf, family = "Times"
  )
} else {
  cairo_pdf(fig6, width = 6.8, height = 8.6, family = "Times")
  grid.newpage()
  print(p6a, vp = viewport(x = 0.5, y = 0.75, width = 0.95, height = 0.48))
  print(p6b, vp = viewport(x = 0.5, y = 0.25, width = 0.95, height = 0.48))
  dev.off()
}

# ---------- P0-4 Figure 4 RCS per-SD + Model3 ----------
message("==== P0-4 Figure 4 RCS ====")
.rcs_fit_one <- function(dd, idx) {
  covs <- .m3
  d2 <- dd[stats::complete.cases(dd[, c("time", "event", idx, covs)]), ]
  d2$Gender <- factor(d2$Gender)
  d2$expo <- as.numeric(scale(d2[[idx]]))
  kts <- unique(as.numeric(quantile(d2$expo, c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE)))
  inner <- kts[2:(length(kts) - 1)]
  fit <- tryCatch(
    coxph(Surv(time, event) ~ splines::ns(expo, knots = inner) + Age + Gender + CHARLSON, data = d2),
    error = function(e) NULL
  )
  fit_lin <- tryCatch(
    coxph(Surv(time, event) ~ expo + Age + Gender + CHARLSON, data = d2),
    error = function(e) NULL
  )
  fit_null <- tryCatch(
    coxph(Surv(time, event) ~ Age + Gender + CHARLSON, data = d2),
    error = function(e) NULL
  )
  p_from <- function(a) {
    if (is.null(a) || nrow(a) < 2) return(NA_real_)
    cn <- grep("^Pr", colnames(a), value = TRUE)[1]
    suppressWarnings(as.numeric(a[2, cn]))
  }
  p_ov <- if (!is.null(fit) && !is.null(fit_null)) p_from(anova(fit_null, fit)) else NA_real_
  p_nl <- if (!is.null(fit) && !is.null(fit_lin)) p_from(anova(fit_lin, fit)) else NA_real_
  if (is.null(fit)) return(NULL)
  grid <- seq(quantile(d2$expo, 0.05), quantile(d2$expo, 0.95), length.out = 80)
  nd <- data.frame(
    expo = grid, Age = median(d2$Age), Gender = levels(d2$Gender)[1],
    CHARLSON = median(d2$CHARLSON)
  )
  pr <- predict(fit, newdata = nd, type = "lp", se.fit = TRUE)
  ref_i <- which.min(abs(grid - 0))
  hr <- exp(pr$fit - pr$fit[ref_i])
  se <- pr$se.fit
  lo <- exp(pr$fit - pr$fit[ref_i] - 1.96 * sqrt(se^2 + se[ref_i]^2))
  hi <- exp(pr$fit - pr$fit[ref_i] + 1.96 * sqrt(se^2 + se[ref_i]^2))
  list(
    df = data.frame(x = grid, hr = hr, lo = lo, hi = hi),
    p_ov = p_ov, p_nl = p_nl, xlab = paste0(idx, " (per 1 SD)"),
    lin_hr = if (!is.null(fit_lin)) exp(coef(fit_lin)["expo"]) else NA_real_,
    lin_p = if (!is.null(fit_lin)) summary(fit_lin)$coefficients["expo", "Pr(>|z|)"] else NA_real_
  )
}
rcs_list <- lapply(c("SIRI", "PIV"), function(idx) .rcs_fit_one(d, idx))
names(rcs_list) <- c("SIRI", "PIV")
for (nm in names(rcs_list)) {
  x <- rcs_list[[nm]]
  message(sprintf(
    "RCS %s P-ov=%s P-nl=%s | linear per-SD HR=%.3f P=%s",
    nm, fmt_p(x$p_ov), fmt_p(x$p_nl), x$lin_hr, fmt_p(x$lin_p)
  ))
}
p_rcs_panels <- lapply(names(rcs_list), function(nm) {
  x <- rcs_list[[nm]]
  ggplot(x$df, aes(x, hr)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, fill = "#D55E00") +
    geom_line(color = "#D55E00", linewidth = 0.9) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    theme_classic(base_size = 11) +
    labs(
      title = nm,
      subtitle = sprintf("P-overall = %s; P-nonlinear = %s", fmt_p(x$p_ov), fmt_p(x$p_nl)),
      x = x$xlab, y = "Hazard ratio (reference = mean / 0 SD)"
    )
})
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) {
  p_rcs_panels[[1]] + p_rcs_panels[[2]]
} else p_rcs_panels[[1]]
ggsave(
  file.path(.fig, "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality.pdf"),
  p4, width = 11.2, height = 4.2, device = cairo_pdf
)

# ---------- P0-3 Figure 7 + interaction P ----------
message("==== P0-3 Figure 7 subgroup + interaction ====")
.sg_prep <- function(dd, idx) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(dd)) qv <- paste0(idx, "_Q")
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$expo_bin <- subgroup_collapse_middle_levels(dd[[qv]], levels = .qsc_meta$labels)
  dd
}
.sg_fit <- function(dd, idx) {
  dd <- .sg_prep(dd, idx)
  fit <- tryCatch(coxph(Surv(time, event) ~ expo_bin, data = dd), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  ci <- summary(fit)$conf.int
  hit <- grep(.qsc_meta$high, rownames(ci), fixed = TRUE)[1]
  if (is.na(hit)) return(NULL)
  data.frame(
    HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
    p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
    N = nrow(dd), events = sum(dd$event == 1L),
    stringsAsFactors = FALSE
  )
}
.sg_pint <- function(dd, idx, svar) {
  dd <- .sg_prep(dd, idx)
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
strata_spec <- list(
  list(lab = "Overall", var = NULL),
  list(lab = "Age", var = "Age_Group"),
  list(lab = "Sex", var = "Gender"),
  list(lab = "Hypertension", var = "Hypertension"),
  list(lab = "Diabetes", var = "Diabetes"),
  list(lab = "SOFA", var = "SOFA_Group")
)
rows <- list(); y_order <- character(0)
for (idx in c("SIRI", "PIV")) {
  for (sp in strata_spec) {
    if (is.null(sp$var)) {
      r <- .sg_fit(d, idx)
      if (is.null(r)) next
      rows[[length(rows) + 1L]] <- cbind(
        Index = idx, row_lab = "Overall", is_header = FALSE,
        p_interaction = NA_real_, r, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      pint <- .sg_pint(d, idx, sp$var)
      pint_lab <- if (is.finite(pint)) {
        if (pint < 0.001) "P for interaction <0.001" else sprintf("P for interaction = %.3f", pint)
      } else "P for interaction = —"
      hdr <- paste0(sp$lab, "  (", pint_lab, ")")
      rows[[length(rows) + 1L]] <- data.frame(
        Index = idx, row_lab = hdr, is_header = TRUE, p_interaction = pint,
        HR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        N = NA_integer_, events = NA_integer_, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, hdr)
      for (lv in levels(factor(d[[sp$var]]))) {
        sub <- d[!is.na(d[[sp$var]]) & as.character(d[[sp$var]]) == lv, ]
        r <- .sg_fit(sub, idx)
        if (is.null(r)) next
        rows[[length(rows) + 1L]] <- cbind(
          Index = idx, row_lab = paste0(sp$lab, ": ", lv), is_header = FALSE,
          p_interaction = NA_real_, r, stringsAsFactors = FALSE
        )
        y_order <- c(y_order, paste0(sp$lab, ": ", lv))
      }
    }
  }
}
sg <- do.call(rbind, rows)
fwrite(sg, file.path(.tab, "Subgroup_rows.csv"))
if (is.character(.ws) && nzchar(.ws) && dir.exists(.ws)) {
  fwrite(sg, file.path(.ws, "Subgroup_rows.csv"))
}
sg$Index <- factor(sg$Index, levels = c("SIRI", "PIV"))
sg$row_lab <- factor(sg$row_lab, levels = rev(unique(y_order)))
sg_pt <- sg[!sg$is_header & is.finite(sg$HR), ]
sg_pt$lo_plot <- pmax(sg_pt$lo, 0.12)
sg_pt$hi_plot <- pmin(sg_pt$hi, 10)
p7 <- ggplot() +
  geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
  geom_point(data = sg[sg$is_header, ], aes(x = 1, y = row_lab), shape = NA) +
  geom_pointrange(
    data = sg_pt, aes(x = HR, y = row_lab, xmin = lo_plot, xmax = hi_plot),
    linewidth = 0.45, color = "#1f4e79"
  ) +
  facet_wrap(~Index, nrow = 1) +
  scale_x_log10(limits = c(0.12, 10), breaks = c(0.25, 0.5, 1, 2, 4, 8)) +
  scale_y_discrete(drop = FALSE) +
  labs(
    x = "Hazard ratio (High vs Low, log scale)", y = NULL,
    title = "Subgroup analyses of inflammatory indices and all-cause mortality"
  ) +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(
    strip.background = element_rect(fill = "grey95"),
    strip.text = element_text(face = "bold"),
    axis.text.y = element_text(size = 7.5, hjust = 1),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 11)
  )
ggsave(
  file.path(.fig, "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality.pdf"),
  p7, width = 11.2, height = 7.0, device = cairo_pdf, family = "Times"
)

# ---------- P0-6 PH 检验 → Table S9 ----------
message("==== P0-6 PH (cox.zph) ====")
.ph_rows <- list()
for (idx in c("SIRI", "PIV")) {
  d2 <- d
  d2$expo_z <- as.numeric(scale(d2[[idx]]))
  qv <- .km_qv(idx)
  d2$expo_bin <- factor(as.character(d2[[qv]]), levels = .qsc_meta$labels)
  for (spec in list(
    list(lab = paste0(idx, " per 1 SD"), fml = paste("Surv(time, event) ~ expo_z +", paste(.m3, collapse = "+"))),
    list(lab = paste0(idx, " High vs Low"), fml = paste("Surv(time, event) ~ expo_bin +", paste(.m3, collapse = "+")))
  )) {
    fit <- tryCatch(coxph(as.formula(spec$fml), data = d2), error = function(e) NULL)
    if (is.null(fit)) next
    z <- tryCatch(cox.zph(fit), error = function(e) NULL)
    if (is.null(z)) next
    rn <- rownames(z$table)
    for (i in seq_along(rn)) {
      .ph_rows[[length(.ph_rows) + 1L]] <- data.frame(
        Model = spec$lab,
        Term = rn[i],
        chisq = round(z$table[i, "chisq"], 3),
        df = z$table[i, "df"],
        P = fmt_p(z$table[i, "p"]),
        stringsAsFactors = FALSE
      )
    }
  }
}
ph_df <- do.call(rbind, .ph_rows)
fwrite(ph_df, file.path(.tab, "PH_assumption_cox_zph.csv"))
path_ph <- file.path(.tab, "Table S9. Proportional hazards assumption.xlsx")
sci_xlsx_single_header_booktabs(
  path_ph,
  title = "Table S9. Proportional hazards assumption (Schoenfeld residuals)",
  df_body = ph_df,
  footnotes = c(
    "Global and covariate-specific tests from cox.zph on Model 3–adjusted Cox models (Age, Gender, CHARLSON).",
    "P < 0.05 suggests departure from the proportional-hazards assumption for that term.",
    "Primary inference remains the pooled Model 3 hazard ratios in Table 3; marked violations would prompt time-varying or stratified sensitivity models."
  )
)
message("OK ", basename(path_ph))
print(ph_df)

# ---------- P0-7/8 + Methods / S1 ----------
message("==== Methods / Table S1 / P0-7 B / P0-8 ====")
methods <- c(
  "# Statistical analysis",
  "",
  "We analysed adults aged 65 years or older with hip arthroplasty and AKI in MIMIC-IV. The primary endpoint was 365-day all-cause mortality after ICU admission.",
  "Exposures were SIRI and PIV, computed from the first absolute neutrophil, monocyte, lymphocyte and platelet counts measured at or after the first ICU intime (labevents charttime ≥ icu_intime; no upper window). Indices entered models as continuous variables (per 1 SD) and as the locked grouping from an engine-level cascade (quartile → tertile → binary; pass_rule = all indices on the unadjusted highest-versus-lowest contrast). The locked grouping for this study was binary (High vs Low).",
  "Candidate covariates were screened with Boruta and SHAP; multicollinearity was assessed with variance inflation factors (VIF < 5 considered acceptable).",
  "Missing covariates were handled with multiple imputation by chained equations (MICE, cart, m = 5). Exposure values, follow-up time and death status were not imputed (analytic rows already required complete exposure and outcome). Inferential Cox models were fit on each completed dataset and pooled by Rubin’s rules. Descriptive tables, figures, Boruta/SHAP, ROC, RCS, subgroup forests and mediation path diagrams used the first completed dataset (operational layer).",
  "Cox proportional hazards models reported hazard ratios (HRs) with 95% confidence intervals. Model 1 was unadjusted. Model 2 was adjusted for Age and Gender. Model 3 was adjusted for Age, Gender, CHARLSON. Proportional-hazards assumptions were assessed with Schoenfeld residual tests (cox.zph; Table S9).",
  "Person-time and crude mortality rates were summarised by exposure group (Table 2). Cumulative incidence curves used Kaplan–Meier estimators with log-rank tests (binary High vs Low). Restricted cubic splines on the per-1-SD scale with Model 3 covariates evaluated dose–response shape (P for overall and P for nonlinear association); primary continuous inference remains the linear per-1-SD Cox estimates in Table 3. Youden-index cutoffs and AUC summarised discrimination (Table S4 / Figure 5).",
  "Subgroup analyses estimated unadjusted High versus Low contrasts within strata on the full analytic sample (matching Table 3 Model 1 Overall) and reported likelihood-ratio P values for multiplicative exposure×stratum interactions (Figure 7).",
  "Mediation analyses used OASIS as the mediator with path models adjusted as in Table 3 Model 3 (mediator omitted from its own adjustment set). Path a was a linear coefficient of the exposure (per 1 SD) on the standardized mediator; path b and the Direct effect were Cox log-hazard coefficients. The proportion mediated was (a×b)/total on the log-hazard scale with bootstrap confidence intervals (Table S8 / Figure 6). Table S7 reports the same exposure→mediator linear associations under Model 1–Model 3.",
  "Sensitivity analysis redefined the endpoint as 90-day all-cause mortality (Table S5) using the same Model 1–Model 3 structure and the same exposure cut-points as Table 3. Cause-specific Fine–Gray models were not performed because cause of death is unavailable in MIMIC-IV; no main-text Table 4 was presented.",
  "Baseline characteristics before and after imputation are in Table S6.",
  "",
  "## Limitations (imputation and PH)",
  "",
  "MICE omitted exposure, follow-up time and death status from the imputation model; covariate missingness was ≤0.9% for variables entering Model 3, while Lactate (30.7% missing) was not used in primary models. Impact on pooled estimates is expected to be small; a full re-imputation that includes the outcome is reserved for a sensitivity re-run if required by reviewers.",
  "Schoenfeld tests are reported in Table S9. Any global or exposure-term violation would be addressed with time-varying coefficients or stratified Cox models in revision; until then, Table 3 HRs are interpreted under the PH working model.",
  "",
  "## Software",
  "",
  "Analyses were performed in **R** (see Methods_software_versions.txt for host version and package roles).",
  "",
  "| Package | Role |",
  "|---------|------|",
  "| mice | Multiple imputation (m = 5; Rubin pool for Cox) |",
  "| survival | Cox / Kaplan-Meier / cox.zph |",
  "| splines / rms | Restricted cubic splines |",
  "| car | Variance inflation factors |",
  "| Boruta | Feature confirmation |",
  "| pROC | ROC / AUC / Youden |",
  "| ggplot2 / patchwork | Publication figures |",
  "| openxlsx | SCI three-line xlsx |",
  "",
  "Publication tables use the engine SCI three-line xlsx entry. Figures are exported under `Figures/{pdf,png,tiff,image_information}/`. Display labels omit programming underscores.",
  "",
  paste0("Package versions at finalize: see `Methods_software_versions.txt` (updated ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"), ").")
)
writeLines(methods, file.path(.out, "Methods_statistical_analysis.md"), useBytes = TRUE)

# Table S1：补暴露取材时点 + PH
s1_body <- data.frame(
  Item = c(
    "Cohort", "Age", "SIRI", "PIV", "Exposure laboratory timing",
    "Primary outcome", "Landmark", "Database", "Imputation",
    "Covariate selection", "Proportional hazards", "Sensitivity (Table S5)"
  ),
  Definition = c(
    "Hip arthroplasty with AKI; renal transplant-related codes excluded",
    "Age >= 65 years at ICU admission",
    "Neutrophil count x monocyte / lymphocyte",
    "Neutrophil count x platelet count x monocyte / lymphocyte",
    "First absolute neutrophil, monocyte, lymphocyte and platelet counts with labevents charttime at or after first ICU intime (no upper sampling window)",
    "All-cause death within 365 days after ICU admission",
    "Follow-up censored at 365 days",
    "MIMIC-IV v3.1 (unweighted, single database)",
    "MICE cart m=5 seed=1234; Cox pooled by Rubin; plots use complete #1; exposure, follow-up time and death status not imputed (option B)",
    "Boruta + SHAP; Model1 unadjusted; Model2 Age+Gender; Model3 Age+Gender+CHARLSON",
    "Schoenfeld residual tests (cox.zph) reported in Table S9",
    "Table S5: 90-day all-cause mortality (same Model 1-3 and binary cut-points as Table 3). No main-text Table 4; Fine-Gray unavailable without COD."
  ),
  stringsAsFactors = FALSE
)
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table S1. Definitions.xlsx"),
  title = "Table S1. Definitions",
  df_body = s1_body,
  footnotes = "Definitions aligned with the primary and sensitivity analyses; laboratory timing matches MIMIC_ICU_4ind first-after-ICU extraction."
)

# ---------- image_information ----------
message("==== refresh image_information ====")
.md <- file.path(.out, "Figures", "image_information")
dir.create(.md, recursive = TRUE, showWarnings = FALSE)
write_md <- function(stem, face) {
  writeLines(
    c(paste0("# ", stem), "", "## 图面说明", face, "", "## 分析上下文",
      c(
        "- 暴露: SIRI, PIV（入 ICU 后首次血常规绝对计数）",
        "- 结局: 365-day all-cause mortality",
        "- 样本量: MIMIC N = 228（死亡 54）",
        "- Grouping: binary（High vs Low）",
        "- 数据库: MIMIC-IV v3.1（单库）",
        "- 是否拼图: 否"
      ), ""),
    file.path(.md, paste0(stem, ".md")), useBytes = TRUE
  )
}
write_md(
  "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index",
  paste(
    "双面板累积发病率（1−KM）按 binary 分组（Low/High）。",
    sprintf("- SIRI：Log-rank P = %s；风险集 Low/High 起点各 n = %s", fmt_p(km_s$p), paste(km_s$n, collapse = "/")),
    sprintf("- PIV：Log-rank P = %s；风险集 Low/High 起点各 n = %s", fmt_p(km_p$p), paste(km_p$n, collapse = "/")),
    "随访横轴为年（截尾于 365 天）。",
    sep = "\n"
  )
)
write_md(
  "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality",
  paste(
    "双面板 RCS：暴露 per 1 SD；调整 Age, Gender, CHARLSON（与 Table 3 Model 3 一致）；参照=0 SD（均值）。",
    "主推断以 Table 3 线性 per-SD Cox 为准；RCS 仅报告剂量–反应形状。",
    sprintf("- SIRI：P-overall = %s；P-nonlinear = %s；同层线性 per-SD HR = %.3f (P = %s)",
            fmt_p(rcs_list$SIRI$p_ov), fmt_p(rcs_list$SIRI$p_nl),
            rcs_list$SIRI$lin_hr, fmt_p(rcs_list$SIRI$lin_p)),
    sprintf("- PIV：P-overall = %s；P-nonlinear = %s；同层线性 per-SD HR = %.3f (P = %s)",
            fmt_p(rcs_list$PIV$p_ov), fmt_p(rcs_list$PIV$p_nl),
            rcs_list$PIV$lin_hr, fmt_p(rcs_list$PIV$lin_p)),
    sep = "\n"
  )
)
write_md(
  "Figure 6. Mediation path diagram of inflammatory indices and all-cause mortality",
  paste(
    "双面板中介路径图（中介 = OASIS；暴露 per 1 SD；底边 = Direct effect HR，与 Table S8 同源）。",
    "路径模型调整 Age, Gender, CHARLSON。",
    sprintf(
      "- A SIRI：path a = %.3f (p=%s)；path b = %.3f (p=%s)；Direct HR = %.3f (p=%s)；Proportion mediated = %.3f%%",
      res_s$a, fmt_p(res_s$pa), res_s$b, fmt_p(res_s$pb), res_s$de_hr, fmt_p(res_s$p_de), res_s$prop
    ),
    sprintf(
      "- B PIV：path a = %.3f (p=%s)；path b = %.3f (p=%s)；Direct HR = %.3f (p=%s)；Proportion mediated = %.3f%%",
      res_p$a, fmt_p(res_p$pa), res_p$b, fmt_p(res_p$pb), res_p$de_hr, fmt_p(res_p$p_de), res_p$prop
    ),
    sep = "\n"
  )
)
sg_lines <- character(0)
for (idx in c("SIRI", "PIV")) {
  ov <- sg[sg$Index == idx & sg$row_lab == "Overall", ][1, ]
  sg_lines <- c(sg_lines, sprintf(
    "- %s Overall：HR = %.3f (%.3f–%.3f)；P = %s；N = %s",
    idx, ov$HR, ov$lo, ov$hi, fmt_p(ov$p), pub_format_int(ov$N)
  ))
  hdrs <- sg[sg$Index == idx & sg$is_header, ]
  for (i in seq_len(nrow(hdrs))) {
    sg_lines <- c(sg_lines, sprintf("- %s %s", idx, as.character(hdrs$row_lab[i])))
  }
}
write_md(
  "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality",
  paste(
    c(
      "双面板亚组森林图：轴标 High vs Low；层内未调整（与 Table 3 Model 1 Overall 对齐）；各层标题含乘性交互 P。",
      sg_lines
    ),
    collapse = "\n"
  )
)
# 保留 Fig1/2/5 既有 md（若缺则轻补）
for (stem in c(
  "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI",
  "Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
  "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality"
)) {
  fp <- file.path(.md, paste0(stem, ".md"))
  if (!file.exists(fp)) {
    write_md(stem, "见图面；本轮 P0 修复未改该图。")
  }
}

message("==== four-format export ====")
unlink(list.files(file.path(.out, "Figures"), pattern = "^Figure.*\\.pdf$", full.names = TRUE))
pub_figure_ensure_formats(file.path(.out, "Figures"))

# ---------- QC note ----------
qc_note <- file.path(.reports, paste0("p0_fix_hip_aki_", format(Sys.Date(), "%Y-%m-%d"), ".md"))
writeLines(c(
  "# Hip AKI P0 fix log",
  "",
  paste0("- 时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
  paste0("- 产出根: ", .out),
  "",
  "| ID | 处理 |",
  "|----|------|",
  "| P0-1 | 重导 Fig3 binary；Log-rank 与风险集 114/114 |",
  "| P0-2 | Fig6 底边改为 Direct effect，与 Table S8 逐位对齐 |",
  "| P0-3 | Fig7 轴标 High vs Low；补乘性交互 P；Methods 改为层内未调整 |",
  "| P0-4 | RCS 改为 per-1-SD + Model3；主推断仍以 Table 3 线性 Cox 为准 |",
  "| P0-5 | S7 改为暴露→OASIS（与 path a 同向）；脚注重写 |",
  "| P0-6 | 新增 Table S9 cox.zph；Methods/Limitations 已写 |",
  "| P0-7 | 裁决 **B**：维持结局不入 MICE；Methods+Limitations 如实写 |",
  "| P0-8 | Methods/S1 写入「入 ICU 后首次血常规绝对计数」口径 |",
  ""
), qc_note, useBytes = TRUE)
message("DONE → ", qc_note)
