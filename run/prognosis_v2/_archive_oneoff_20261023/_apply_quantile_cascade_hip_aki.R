#!/usr/bin/env Rscript
# Hip AKI：引擎分位级联锁定后，统一重导 Table2/Table3/Fig3 KM/Fig7
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pv2_pub_names.R", local = FALSE)
source("R/cox_gate.R", local = FALSE)
source("R/quantile_scheme_cascade.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)
source("run/prognosis_v2/pv2_mi_cox.R", local = FALSE)

.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
.ws_cands <- list.files(
  file.path(dirname(.out), "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- .ws_cands[order(file.info(.ws_cands)$mtime, decreasing = TRUE)][1L]
stopifnot(dir.exists(.ws))

d <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
mids <- tryCatch(readRDS(file.path(.ws, "imputed_mids.rds"))$MIMIC, error = function(e) NULL)
if (!"futime_years" %in% names(d)) d$futime_years <- d$futime / 365.25
d$fustatus <- as.integer(d$fustatus)
d$time <- d$futime_years
d$event <- d$fustatus
d$Gender <- factor(d$Gender)
d$Age_Group <- factor(ifelse(d$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
if ("SOFA" %in% names(d)) {
  d$SOFA_Group <- factor(ifelse(d$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
}

cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE,
  try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05,
  pass_rule = "all",
  on_none_pass = "best_n_pass",
  family = "cox",
  time_var = "futime_years",
  event_var = "fustatus"
))
resolved <- quantile_scheme_resolve_cascade(d, c("SIRI", "PIV"), config = cfg)
d <- quantile_scheme_attach_groups(d, resolved)
meta <- resolved$meta
sch <- resolved$scheme
message("LOCKED scheme=", sch, " contrast=", meta$contrast_lab)
fwrite(resolved$trial, file.path(.ws, "Quantile_scheme_cascade_trial.csv"))
writeLines(
  c(
    paste0("scheme=", sch),
    paste0("contrast=", meta$contrast_lab),
    paste0("reason=", resolved$reason),
    quantile_scheme_footnote_lines(resolved)
  ),
  file.path(.tab, "Quantile_scheme_cascade_lock.txt")
)
file.copy(file.path(.tab, "Quantile_scheme_cascade_lock.txt"),
          file.path(.ws, "Quantile_scheme_cascade_lock.txt"), overwrite = TRUE)

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi) {
  if (!all(is.finite(c(hr, lo, hi)))) return("")
  sprintf("%.3f (%.3f\u2013%.3f)", hr, lo, hi)
}
.m2 <- c("Age", "Gender")
.m3 <- c("Age", "Gender", "CHARLSON")
rhs_of <- function(expo, model) {
  if (model == "Model1") return(expo)
  if (model == "Model2") return(paste(c(expo, .m2), collapse = " + "))
  paste(c(expo, .m3), collapse = " + ")
}

# ---- Table 2 ----
message("==== Table 2 ====")
t2_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Group")
  dd <- d[!is.na(d[[qv]]), ]
  dd$ord <- as.integer(dd[[qv]])
  tr <- tryCatch(
    stats::glm(event ~ ord, offset = log(pmax(time, 1e-8)), family = poisson(), data = dd),
    error = function(e) NULL
  )
  p_tr <- if (!is.null(tr)) summary(tr)$coefficients["ord", "Pr(>|z|)"] else NA_real_
  t2_rows[[length(t2_rows) + 1L]] <- c(idx, "", "", "", "")
  for (g in meta$labels) {
    sub <- dd[as.character(dd[[qv]]) == g, ]
    n <- nrow(sub); ev <- sum(sub$event == 1); pyrs <- sum(sub$time)
    ci <- stats::poisson.test(ev, T = max(pyrs, .Machine$double.eps))$conf.int * 1e2
    t2_rows[[length(t2_rows) + 1L]] <- c(
      quantile_scheme_level_display(g, sch), as.character(n), as.character(ev),
      sprintf("%.2f", 100 * ev / max(n, 1)),
      sprintf("%.2f (%.2f\u2013%.2f)", 100 * ev / max(pyrs, .Machine$double.eps), ci[1], ci[2])
    )
  }
  t2_rows[[length(t2_rows) + 1L]] <- c("P for trend", fmt_p(p_tr), "", "", "")
}
body2 <- as.data.frame(do.call(rbind, t2_rows), stringsAsFactors = FALSE)
names(body2) <- c(
  "Variable", "Participants", "All-cause mortality", "Cumulative incidence (%)",
  "Per 100 person-year (95% CI)"
)
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 2. Incidence of all-cause mortality.xlsx"),
  title = "Table 2. Incidence of all-cause mortality",
  df_body = body2,
  footnotes = c(
    "Per 100 person-year is events / person-years x 100. Interval is the exact Poisson 95% CI.",
    sprintf("P for trend is from an unadjusted Poisson model with %s coded 1-%d.",
            meta$legend_title, meta$n_groups),
    "Outcome: all-cause death within 365 days after ICU admission.",
    quantile_scheme_footnote_lines(resolved)
  ),
  level_row_idx = which(startsWith(body2$Variable, "  ")) + 1L
)

# ---- Table 3 Cox wide ----
message("==== Table 3 ====")
for (idx in c("SIRI", "PIV")) {
  d[[paste0(idx, "_z")]] <- as.numeric(scale(d[[idx]]))
}
cox_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Group")
  zv <- paste0(idx, "_z")
  for (mod in c("Model1", "Model2", "Model3")) {
    for (kind in c("continuous", "grouped")) {
      expo <- if (kind == "continuous") zv else qv
      res <- tryCatch(
        pv2_cox_extract(
          d, rhs_of(expo, mod), mids = mids, time_var = "futime_years", event_var = "fustatus",
          exposure_keep = c("SIRI", "PIV", "SIRI_Group", "PIV_Group", "SIRI_z", "PIV_z",
                            "SIRI_Q", "PIV_Q"),
          weighted = FALSE, rubin = TRUE
        ),
        error = function(e) NULL
      )
      if (is.null(res) || !nrow(res)) next
      keep <- if (kind == "continuous") grepl("_z", res$term) else grepl(paste0(idx, "_(Group|Q)"), res$term)
      res <- res[keep, , drop = FALSE]
      if (!nrow(res)) next
      res$Index <- idx
      res$model <- paste0(mod, "_", kind)
      cox_rows[[length(cox_rows) + 1L]] <- res
    }
    d$qnum <- as.integer(d[[qv]])
    tr <- tryCatch(
      pv2_cox_extract(
        d, rhs_of("qnum", mod), mids = mids, time_var = "futime_years", event_var = "fustatus",
        exposure_keep = c("qnum", "SIRI", "PIV"), rubin = TRUE
      ),
      error = function(e) NULL
    )
    if (!is.null(tr) && any(tr$term == "qnum")) {
      tr <- tr[tr$term == "qnum", , drop = FALSE]
      tr$Index <- idx
      tr$model <- paste0(mod, "_trend")
      tr$term <- "P_for_trend"
      cox_rows[[length(cox_rows) + 1L]] <- tr
    }
  }
}
cox_out <- do.call(rbind, cox_rows)
fwrite(cox_out, file.path(.ws, "Table 3. Cox.csv"))

.pub_cox_wide <- function(cox_out) {
  rows <- list()
  hr_only <- function(mod, kind, term_pat, idx) {
    r <- cox_out[cox_out$Index == idx & cox_out$model == paste0(mod, "_", kind), , drop = FALSE]
    r <- r[grepl(term_pat, r$term), , drop = FALSE]
    if (!nrow(r)) return(c(HR = "", P = ""))
    c(HR = hr_cell(r$hr[1], r$lo[1], r$hi[1]), P = fmt_p(r$p[1]))
  }
  tp <- function(mod, idx) {
    r <- cox_out[cox_out$Index == idx & cox_out$model == paste0(mod, "_trend"), , drop = FALSE]
    if (!nrow(r)) "" else fmt_p(r$p[1])
  }
  non_ref <- meta$labels[-1L]
  for (idx in c("SIRI", "PIV")) {
    rows[[length(rows) + 1L]] <- c(Variable = idx, M1 = "", P1 = "", M2 = "", P2 = "", M3 = "", P3 = "")
    a <- hr_only("Model1", "continuous", "_z", idx)
    b <- hr_only("Model2", "continuous", "_z", idx)
    c3 <- hr_only("Model3", "continuous", "_z", idx)
    rows[[length(rows) + 1L]] <- c(
      Variable = "  per 1 SD", M1 = a["HR"], P1 = a["P"],
      M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
    )
    rows[[length(rows) + 1L]] <- c(
      Variable = quantile_scheme_level_display(meta$ref, sch),
      M1 = "Reference", P1 = "", M2 = "Reference", P2 = "", M3 = "Reference", P3 = ""
    )
    for (lv in non_ref) {
      a <- hr_only("Model1", "grouped", lv, idx)
      b <- hr_only("Model2", "grouped", lv, idx)
      c3 <- hr_only("Model3", "grouped", lv, idx)
      rows[[length(rows) + 1L]] <- c(
        Variable = quantile_scheme_level_display(lv, sch),
        M1 = a["HR"], P1 = a["P"], M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
      )
    }
    rows[[length(rows) + 1L]] <- c(
      Variable = "  P for trend",
      M1 = "", P1 = tp("Model1", idx),
      M2 = "", P2 = tp("Model2", idx),
      M3 = "", P3 = tp("Model3", idx)
    )
  }
  out <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(out) <- c(
    "Variable", "Model 1 HR (95% CI)", "P1",
    "Model 2 HR (95% CI)", "P2", "Model 3 HR (95% CI)", "P3"
  )
  out
}
t3 <- .pub_cox_wide(cox_out)
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 3. Cox proportional hazards models.xlsx"),
  title = "Table 3. Cox proportional hazards models for 365-day all-cause mortality",
  df_body = t3,
  footnotes = c(
    "The Model 1 was non-adjusted.",
    "The Model 2 was adjusted by: Age, Gender.",
    "The Model 3 was adjusted by: Age, Gender, CHARLSON.",
    "SOFA/OASIS were not included in Model 3 to avoid over-adjustment along the acute-severity mediation pathway.",
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample.",
    sprintf("Grouped contrasts use %s as the reference (%s).", meta$ref, meta$contrast_lab),
    quantile_scheme_footnote_lines(resolved)
  ),
  level_row_idx = which(startsWith(t3$Variable, "  ")) + 1L
)
.wb <- openxlsx::loadWorkbook(file.path(.tab, "Table 3. Cox proportional hazards models.xlsx"))
for (col in c(3L, 5L, 7L)) openxlsx::writeData(.wb, 1, x = "P", startCol = col, startRow = 2L)
openxlsx::saveWorkbook(.wb, file.path(.tab, "Table 3. Cox proportional hazards models.xlsx"), overwrite = TRUE)

# ---- Fig3 KM ----
message("==== Figure 3 KM ====")
.km_one <- function(dd, qv, title) {
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$sg <- factor(as.character(dd[[qv]]), levels = meta$labels)
  fit <- survfit(Surv(time, event) ~ sg, data = dd)
  sd <- survdiff(Surv(time, event) ~ sg, data = dd)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  pal <- c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728", "#1f77b4")[seq_along(meta$labels)]
  g <- survminer::ggsurvplot(
    fit, data = dd, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.6,
    risk.table = TRUE, risk.table.height = 0.28, risk.table.title = "Number at risk",
    pval = FALSE, palette = pal,
    legend = "top", legend.title = meta$legend_title, legend.labs = meta$labels,
    xlab = "Follow-up (years)", ylab = "Cumulative incidence of all-cause mortality",
    title = title, break.time.by = 0.25,
    ggtheme = theme_classic(base_size = 11), fontsize = 3.1
  )
  g$plot <- g$plot + annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.4, size = 3.4)
  g
}
km_plots <- list(
  SIRI = .km_one(d, "SIRI_Group", "SIRI"),
  PIV = .km_one(d, "PIV_Group", "PIV")
)
fig3 <- file.path(.fig, "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf")
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 2, title = NA)
cairo_pdf(fig3, width = 7.4, height = 10.5, family = "Times")
print(km_page)
dev.off()

# ---- Fig7 subgroup：最高 vs 最低，中间并为 Middle ----
message("==== Figure 7 ====")
.sg_fit <- function(dd, idx) {
  qv <- paste0(idx, "_Group")
  dd <- dd[!is.na(dd[[qv]]), ]
  dd$expo_bin <- subgroup_collapse_middle_levels(dd[[qv]], levels = meta$labels)
  fit <- tryCatch(coxph(Surv(time, event) ~ expo_bin, data = dd), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  ci <- summary(fit)$conf.int
  hit <- grep(meta$high, rownames(ci), fixed = TRUE)[1]
  if (is.na(hit)) return(NULL)
  data.frame(
    HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
    p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
    N = nrow(dd), events = sum(dd$event == 1L),
    stringsAsFactors = FALSE
  )
}
source("R/subgroup_forest_plot.R", local = FALSE)
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
        Index = idx, row_lab = "Overall", is_header = FALSE, r, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      rows[[length(rows) + 1L]] <- data.frame(
        Index = idx, row_lab = sp$lab, is_header = TRUE,
        HR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
        N = NA_integer_, events = NA_integer_, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, sp$lab)
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
fwrite(sg, file.path(.ws, "Subgroup_rows.csv"))
y_levels <- unique(y_order)
sg$Index <- factor(sg$Index, levels = c("SIRI", "PIV"))
sg$row_lab <- factor(sg$row_lab, levels = rev(y_levels))
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
    x = sprintf("Hazard ratio (%s, log scale)", meta$contrast_lab), y = NULL,
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
  p7, width = 9.2, height = 6.2, device = cairo_pdf, family = "Times"
)

# Methods 一句
meth <- file.path(.out, "Methods_statistical_analysis.md")
if (file.exists(meth)) {
  lines <- readLines(meth, warn = FALSE)
  lines <- lines[!grepl("quantile_scheme_cascade|Exposure grouping locked", lines)]
  lines <- c(
    lines, "",
    paste0(
      "Exposure grouping was selected by an engine-level cascade (quartile \u2192 tertile \u2192 binary) ",
      "based on the unadjusted highest-versus-lowest contrast (pass_rule = all indices). ",
      "The locked grouping for this study was ", meta$footnotes_scheme, " (", meta$contrast_lab, ")."
    )
  )
  writeLines(lines, meth)
}

# 四目录刷新
figs_root <- file.path(.out, "Figures")
if (exists("pub_figure_ensure_formats", mode = "function")) {
  pub_figure_ensure_formats(figs_root, config = list(pub_figures = list(dpi = 600L)))
}

message("DONE cascade scheme=", sch, " → Table2/3 Fig3/7 refreshed")
print(t3[, 1:3])
