#!/usr/bin/env Rscript
# 髋关节 AKI 预后 v2：按 49_Dyslipidemia/prognosis_v2 版式重画全套表图（单库无前缀）
# 用户授权：本课题交付对齐参考清单「一个也不能少」；中介表/图标注 Exploratory。

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
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/attrition_log.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/cox_gate.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/subgroup_forest_plot.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/draw_fig1_nhanes.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)

.out <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  cands[dir.exists(file.path(dirname(cands[1]), "data")) | dir.exists(cands)][1L]
}
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
.ckpt <- file.path(.out, "checkpoints")
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.ckpt, recursive = TRUE, showWarnings = FALSE)

# 优先用本次 runner 写入的 Tables/；仅当缺失时才回退 delivery_workspace
.ws_cands <- list.files(
  file.path(dirname(.out), "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- if (length(.ws_cands)) {
  .ws_cands[order(file.info(.ws_cands)$mtime, decreasing = TRUE)][1L]
} else {
  NA_character_
}
for (f in c("imputed_dbs.rds", "imputed_mids.rds", "before_imputation_dbs.rds",
            "Boruta_objects.rds", "SHAP_long.rds", "Boruta_by_database.csv",
            "SHAP_by_database.csv", "Table 3. Cox.csv", "Subgroup_rows.csv")) {
  dest <- file.path(.tab, f)
  if (file.exists(dest)) next
  if (is.character(.ws) && file.exists(file.path(.ws, f))) {
    file.copy(file.path(.ws, f), dest, overwrite = TRUE)
    file.copy(file.path(.ws, f), file.path(.ckpt, f), overwrite = TRUE)
  }
}

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
if (!"MIMIC" %in% names(dbs)) names(dbs) <- "MIMIC"
d0 <- as.data.frame(dbs$MIMIC)
if (!"futime_years" %in% names(d0)) d0$futime_years <- d0$futime / 365.25
d0$time <- d0$futime_years
d0$event <- as.integer(d0$fustatus)
d0$Age_Group <- factor(ifelse(d0$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
if ("SOFA" %in% names(d0)) {
  d0$SOFA_Group <- factor(ifelse(d0$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
}
# 引擎分位级联：quartile→tertile→binary（crude 最高档；多指标 pass_rule=all）
.qsc_cfg <- list(quantile_scheme_cascade = list(
  enable = TRUE,
  try_schemes = c("quartile", "tertile", "binary"),
  p_threshold = 0.05,
  pass_rule = "all",
  on_none_pass = "best_n_pass",
  family = "cox",
  time_var = "futime_years",
  event_var = "fustatus"
))
.qsc <- quantile_scheme_resolve_cascade(d0, c("SIRI", "PIV"), config = .qsc_cfg)
d0 <- quantile_scheme_attach_groups(d0, .qsc)
for (idx in c("SIRI", "PIV")) {
  d0[[paste0(idx, "_z")]] <- as.numeric(scale(d0[[idx]]))
}
.qsc_meta <- .qsc$meta
message("quantile_scheme_cascade locked: ", .qsc$scheme, " (", .qsc_meta$contrast_lab, ")")
writeLines(
  c(paste0("scheme=", .qsc$scheme), paste0("reason=", .qsc$reason),
    quantile_scheme_footnote_lines(.qsc)),
  file.path(.tab, "Quantile_scheme_cascade_lock.txt")
)
dbs$MIMIC <- d0
mids <- tryCatch(readRDS(file.path(.tab, "imputed_mids.rds"))$MIMIC, error = function(e) NULL)
if (is.null(mids) && !is.na(.ws) && nzchar(.ws)) {
  mids <- tryCatch(readRDS(file.path(.ws, "imputed_mids.rds"))$MIMIC, error = function(e) NULL)
}

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi) {
  hr <- as.numeric(hr)[1L]; lo <- as.numeric(lo)[1L]; hi <- as.numeric(hi)[1L]
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) return("")
  sprintf("%.3f (%.3f\u2013%.3f)", hr, lo, hi)
}
mean_sd <- function(x) sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
med_iqr <- function(x) {
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f%%)", k, if (n > 0) 100 * k / n else NA_real_)
is_normal_vec <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3L) return(FALSE)
  p <- tryCatch(if (length(x) > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value,
                error = function(e) 0)
  is.finite(p) && p >= 0.05
}

write_one <- function(title, df, footnotes = character(0), level_rows = integer(0)) {
  stem <- sub("^Table (S?[0-9]+)\\. ", "", title)
  num <- sub("^Table (S?[0-9]+)\\. .*", "Table \\1", title)
  path <- file.path(.tab, pv2_table_xlsx_name(num, stem, single_db = TRUE))
  sci_xlsx_single_header_booktabs(
    path, title = pv2_table_title(num, stem), df_body = df,
    footnotes = footnotes,
    level_row_idx = if (length(level_rows)) level_rows + 1L else NULL
  )
  message("wrote ", basename(path))
}

message("==== Figure 1：引擎预后纳排版式（单库 MIMIC）====")
n_top <- 360L
n_age <- 260L
n_idx <- 229L
n_inc <- nrow(d0)
n_death <- sum(d0$event == 1)
n_alive <- sum(d0$event == 0)
panel <- list(
  letter = "A  MIMIC",
  top = sprintf("Hip arthroplasty with AKI\nin MIMIC-IV\n(n = %s)", format(n_top, big.mark = ",")),
  mid = sprintf("Aged >= 65 years\n(n = %s)", format(n_age, big.mark = ",")),
  inc = sprintf("Participants included\n(n = %s)", format(n_inc, big.mark = ",")),
  side1 = sprintf("Age < 65 years or\nmissing age (n = %s)", format(n_top - n_age, big.mark = ",")),
  side2 = paste0(
    sprintf("1. SIRI or PIV not\ncomputable (n = %s)\n", format(n_age - n_idx, big.mark = ",")),
    sprintf("2. Missing 365-day follow-up\nor invalid exposure (n = %s)", format(n_idx - n_inc, big.mark = ","))
  ),
  death = sprintf("365-day all-cause death\n(n = %s)", format(n_death, big.mark = ",")),
  alive = sprintf("Alive at 365 days\n(n = %s)", format(n_alive, big.mark = ","))
)
fig1 <- file.path(.fig, "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI.pdf")
csv1 <- file.path(.tab, "Flowchart_attrition.csv")
attrition_draw_outcome_figure(fig1, list(panel), width = 5.4, height = 6.35, family = "Times", csv_path = csv1)
message("Fig1 OK")

message("==== Table 1 Survivor / Non-survivor（三线表）====")
d <- d0
d$status <- factor(ifelse(d$event == 1, "Non-survivor", "Survivor"),
                   levels = c("Survivor", "Non-survivor"))
layout <- list(
  Demographics = list(
    cont = c(Age = "Age, years"),
    cats = list(Gender = c("Male", "Female"))
  ),
  Severity = list(
    cont = c(
      SOFA = "SOFA", GCS = "GCS", CHARLSON = "Charlson comorbidity index",
      OASIS = "OASIS"
    ),
    cats = list(Ventilation = c("Yes", "No"))
  ),
  `Vital Signs` = list(
    cont = c(HR = "Heart rate", NBPS = "SBP, mmHg"),
    cats = list()
  ),
  Laboratory = list(
    cont = c(Hemoglobin = "Hemoglobin", Glucose = "Glucose", Lactate = "Lactate",
             Sodium = "Sodium", Potassium = "Potassium"),
    cats = list()
  ),
  Comorbidities = list(
    cont = c(),
    cats = list(
      Hypertension = c("Yes", "No"), Diabetes = c("Yes", "No"),
      Heart_Failure = c("Yes", "No"), Myocardial_Infarction = c("Yes", "No"),
      Stroke = c("Yes", "No"), COPD = c("Yes", "No"), Pneumonia = c("Yes", "No"),
      Malignant_Tumor = c("Yes", "No")
    )
  ),
  Exposure = list(
    cont = c(SIRI = "SIRI", PIV = "PIV"),
    cats = list()
  )
)
cat_lab <- c(
  Gender = "Sex", Ventilation = "Mechanical ventilation",
  Hypertension = "Hypertension", Diabetes = "Diabetes",
  Heart_Failure = "Heart failure", Myocardial_Infarction = "Myocardial infarction",
  Stroke = "Stroke", COPD = "COPD", Pneumonia = "Pneumonia",
  Malignant_Tumor = "Malignant tumor"
)
slices <- list(Overall = d, Survivor = d[d$status == "Survivor", ],
               `Non-survivor` = d[d$status == "Non-survivor", ])
headers <- c(
  sprintf("Overall, N = %d", nrow(slices$Overall)),
  sprintf("Survivor, N = %d", nrow(slices$Survivor)),
  sprintf("Non-survivor, N = %d", nrow(slices[["Non-survivor"]]))
)
rows <- list(); level_rows <- integer(0); section_names <- character(0)
add <- function(lab, vals, p = "") rows[[length(rows) + 1L]] <<- c(lab, vals, p)
cont_cell <- function(dd, var, normal) if (normal) mean_sd(dd[[var]]) else med_iqr(dd[[var]])
cat_cell <- function(dd, var, lv) {
  k <- sum(as.character(dd[[var]]) == lv, na.rm = TRUE)
  n <- sum(!is.na(dd[[var]]))
  n_pct(k, n)
}
for (sec in names(layout)) {
  section_names <- c(section_names, sec)
  add(sec, rep("", 3), "")
  spec <- layout[[sec]]
  for (v in names(spec$cont)) {
    if (!v %in% names(d)) next
    normal <- is_normal_vec(d[[v]])
    vals <- vapply(slices, function(dd) cont_cell(dd, v, normal), character(1))
    p <- tryCatch(stats::wilcox.test(d[[v]] ~ d$status)$p.value, error = function(e) NA_real_)
    add(spec$cont[[v]], vals, fmt_p(p))
  }
  for (v in names(spec$cats)) {
    if (!v %in% names(d)) next
    p <- tryCatch({
      tab <- table(d[[v]], d$status)
      if (any(tab < 5)) stats::fisher.test(tab)$p.value else suppressWarnings(stats::chisq.test(tab)$p.value)
    }, error = function(e) NA_real_)
    add(cat_lab[[v]] %||% v, rep("", 3), fmt_p(p))
    for (lv in spec$cats[[v]]) {
      level_rows <- c(level_rows, length(rows) + 1L)
      vals <- vapply(slices, function(dd) cat_cell(dd, v, lv), character(1))
      add(paste0("  ", lv), vals, "")
    }
  }
}
body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
names(body) <- c("Characteristic", headers, "p-value")
hdr <- stats::setNames(as.data.frame(t(names(body)), stringsAsFactors = FALSE), names(body))
show <- rbind(hdr, body); show[1, ] <- as.character(show[1, ])
path_t1 <- file.path(.tab, "Table 1. Baseline characteristics.xlsx")
.sci_xlsx_write_three_line_workbook(
  path_t1, title = "Table 1. Baseline characteristics", tbl_df_new = show,
  footnotes = c(
    "Continuous variables are mean (SD) if approximately normal, otherwise median (IQR). Categorical variables are n (%).",
    "P values compare Survivor vs Non-survivor (Wilcoxon or chi-square/Fisher).",
    sprintf("Analytic cohort: hip arthroplasty with AKI, Age\u226565, MIMIC-IV; 365-day all-cause mortality (N=%d, deaths=%d).",
            nrow(d), n_death)
  ),
  insert_map = stats::setNames(rep(1L, length(section_names)), section_names),
  level_row_idx = level_rows + 1L
)
message("Table 1 OK")

message("==== Table 2 发病率（跟分位级联锁定 scheme）====")
t2_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(d)) qv <- paste0(idx, "_Q")
  dd <- d[!is.na(d[[qv]]), ]
  dd$ord <- as.integer(dd[[qv]])
  tr <- tryCatch(
    stats::glm(event ~ ord, offset = log(pmax(time, 1e-8)), family = poisson(), data = dd),
    error = function(e) NULL
  )
  p_tr <- if (!is.null(tr)) summary(tr)$coefficients["ord", "Pr(>|z|)"] else NA_real_
  t2_rows[[length(t2_rows) + 1L]] <- c(idx, "", "", "", "")
  for (g in .qsc_meta$labels) {
    sub <- dd[as.character(dd[[qv]]) == g, ]
    n <- nrow(sub); ev <- sum(sub$event == 1); pyrs <- sum(sub$time)
    ci <- stats::poisson.test(ev, T = max(pyrs, .Machine$double.eps))$conf.int * 1e2
    t2_rows[[length(t2_rows) + 1L]] <- c(
      quantile_scheme_level_display(g, .qsc$scheme), as.character(n), as.character(ev),
      sprintf("%.2f", 100 * ev / max(n, 1L)),
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
write_one(
  "Table 2. Incidence of all-cause mortality", body2,
  c(
    "Per 100 person-year is events / person-years x 100. Interval is the exact Poisson 95% CI.",
    sprintf("P for trend is from an unadjusted Poisson model with %s coded 1-%d.",
            .qsc_meta$legend_title, .qsc_meta$n_groups),
    "Outcome: all-cause death within 365 days after ICU admission.",
    quantile_scheme_footnote_lines(.qsc)
  ),
  level_rows = which(startsWith(body2$Variable, "  "))
)

message("==== Table 3 Cox 宽表（跟分位级联；Variable | M1 | P | M2 | P | M3 | P）====")
.m2_cox <- c("Age", "Gender")
.m3_cox <- c("Age", "Gender", "CHARLSON")
.rhs_cox <- function(expo, model) {
  if (model == "Model1") return(expo)
  if (model == "Model2") return(paste(c(expo, .m2_cox), collapse = " + "))
  paste(c(expo, .m3_cox), collapse = " + ")
}
cox_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(d)) qv <- paste0(idx, "_Q")
  zv <- paste0(idx, "_z")
  for (mod in c("Model1", "Model2", "Model3")) {
    for (kind in c("continuous", "grouped")) {
      expo <- if (kind == "continuous") zv else qv
      res <- tryCatch(
        pv2_cox_extract(
          d, .rhs_cox(expo, mod), mids = mids, time_var = "futime_years", event_var = "fustatus",
          exposure_keep = c("SIRI", "PIV", "SIRI_Group", "PIV_Group", "SIRI_Q", "PIV_Q", "SIRI_z", "PIV_z"),
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
        d, .rhs_cox("qnum", mod), mids = mids, time_var = "futime_years", event_var = "fustatus",
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
if (!is.na(.ws) && nzchar(.ws)) fwrite(cox_out, file.path(.ws, "Table 3. Cox.csv"))
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
  non_ref <- .qsc_meta$labels[-1L]
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
      Variable = quantile_scheme_level_display(.qsc_meta$ref, .qsc$scheme),
      M1 = "Reference", P1 = "", M2 = "Reference", P2 = "", M3 = "Reference", P3 = ""
    )
    for (lv in non_ref) {
      a <- hr_only("Model1", "grouped", lv, idx)
      b <- hr_only("Model2", "grouped", lv, idx)
      c3 <- hr_only("Model3", "grouped", lv, idx)
      rows[[length(rows) + 1L]] <- c(
        Variable = quantile_scheme_level_display(lv, .qsc$scheme),
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
    "Variable",
    "Model 1 HR (95% CI)", "P1",
    "Model 2 HR (95% CI)", "P2",
    "Model 3 HR (95% CI)", "P3"
  )
  out
}
t3 <- .pub_cox_wide(cox_out)
level_idx <- which(startsWith(t3$Variable, "  "))
write_one(
  "Table 3. Cox proportional hazards models", t3,
  c(
    "The Model 1 was non-adjusted.",
    "The Model 2 was adjusted by: Age, Gender.",
    "The Model 3 was adjusted by: Age, Gender, CHARLSON.",
    "Covariate sets are identical across Table 3, Table 4, sensitivity and mediation path models.",
    "SOFA/OASIS were not included in Model 3 to avoid over-adjustment along the acute-severity mediation pathway.",
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample.",
    sprintf("Grouped contrasts use %s as the reference (%s).", .qsc_meta$ref, .qsc_meta$contrast_lab),
    quantile_scheme_footnote_lines(.qsc)
  ),
  level_rows = level_idx
)
# 表头 P1/P2/P3 → P（与参考图一致；不用 surgical/python，避免 WindowsApps python 坏路径）
.t3_path <- file.path(.tab, "Table 3. Cox proportional hazards models.xlsx")
if (file.exists(.t3_path)) {
  .wb <- openxlsx::loadWorkbook(.t3_path)
  .x <- openxlsx::read.xlsx(.t3_path, colNames = FALSE)
  .hdr <- NA_integer_
  for (.i in 1:5) {
    .v <- as.character(unlist(.x[.i, ]))
    if (any(grepl("^P1$|^P2$|Model 1 HR", .v))) {
      .hdr <- .i
      break
    }
  }
  if (is.finite(.hdr)) {
    for (.col in c(3L, 5L, 7L)) {
      openxlsx::writeData(.wb, 1, x = "P", startCol = .col, startRow = .hdr)
    }
    openxlsx::saveWorkbook(.wb, .t3_path, overwrite = TRUE)
  }
}

message("==== Table 4：用户不要主文 Table 4（敏感性只放 S5）====")
.t4_arch <- file.path(dirname(.out), "summary_results_delivery_workspace", "_archive_table4_retired")
dir.create(.t4_arch, recursive = TRUE, showWarnings = FALSE)
for (.f in list.files(.tab, pattern = "^Table 4\\.", full.names = TRUE)) {
  file.rename(.f, file.path(.t4_arch, basename(.f)))
  message("archived ", basename(.f))
}

message("==== Table S1–S8 ====")
write_one("Table S1. Definitions", data.frame(
  Item = c("Cohort", "Age", "SIRI", "PIV", "Primary outcome", "Landmark", "Database",
           "Imputation", "Covariate selection", "Sensitivity (Table S5)"),
  Definition = c(
    "Hip arthroplasty with AKI; renal transplant-related codes excluded",
    "Age >= 65 years at ICU admission",
    "Neutrophil count x monocyte / lymphocyte",
    "Neutrophil count x platelet count x monocyte / lymphocyte",
    "All-cause death within 365 days after ICU intime",
    "Follow-up censored at 365 days",
    "MIMIC-IV v3.1 (unweighted, single database)",
    "MICE cart m=5 seed=1234; Cox pooled by Rubin; plots use complete #1",
    "Boruta + SHAP (Jin 2026); Model1 unadjusted; Model2 Age+Gender; Model3 Age+Gender+CHARLSON",
    "90-day all-cause mortality endpoint (Table S5; primary remains 365-day). No main-text Table 4; cause-specific Fine-Gray unavailable in MIMIC-IV."
  ),
  stringsAsFactors = FALSE
))

# S2 VIF from car
vv <- c("Age", "Gender", "SOFA", "CHARLSON")
vv <- vv[vv %in% names(d)]
ddv <- d[stats::complete.cases(d[, c("event", vv)]), c("event", vv)]
for (v in vv) if (is.character(ddv[[v]])) ddv[[v]] <- factor(ddv[[v]])
vfit <- tryCatch(car::vif(stats::lm(event ~ ., data = ddv)), error = function(e) NULL)
if (!is.null(vfit)) {
  if (is.matrix(vfit)) {
    stat <- if ("GVIF^(1/(2*Df))" %in% colnames(vfit)) vfit[, "GVIF^(1/(2*Df))"]^2 else vfit[, 1]
    vif_df <- data.frame(Variable = rownames(vfit), VIF = round(as.numeric(stat), 3))
  } else {
    vif_df <- data.frame(Variable = names(vfit), VIF = round(as.numeric(vfit), 3))
  }
  write_one("Table S2. Assessment of multicollinearity", vif_df, "VIF < 5 considered acceptable.")
}

# S3：文献 Model 4 宽表（Variable | HR | P；per 1 SD + 级联分位）
.s3_script <- file.path(.engine, "run/prognosis_v2/_rebuild_tables3_hip_aki.R")
if (file.exists(.s3_script)) {
  sys.source(.s3_script, envir = new.env(parent = globalenv()))
} else {
  warning("missing _rebuild_tables3_hip_aki.R")
}

# S4 ROC：与 Fig5 同源（Cox LP；图注不写协变量名单）
.roc_covs <- intersect(c("Age", "CHARLSON", "Sodium"), names(d))
yd <- list()
for (idx in c("SIRI", "PIV")) {
  dd <- d[stats::complete.cases(d[, c(idx, "time", "event", .roc_covs)]), ]
  fit <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(idx, .roc_covs), collapse = "+"))), dd)
  lp <- as.numeric(predict(fit, type = "lp"))
  roc <- pROC::roc(dd$event, lp, quiet = TRUE, direction = "<")
  cd <- pROC::coords(roc, "best", ret = c("threshold", "sensitivity", "specificity"),
                     best.method = "youden", transpose = FALSE)
  yd[[idx]] <- data.frame(
    Index = idx, AUC = round(as.numeric(pROC::auc(roc)), 3),
    Sensitivity = round(cd$sensitivity[1], 3),
    Specificity = round(cd$specificity[1], 3)
  )
}
write_one(
  "Table S4. Predictive performance for 365-day all-cause mortality",
  do.call(rbind, yd),
  "Youden index on the ROC curve of the linear predictor."
)

# S5/S6–S8：课题薄封装 → 引擎 R/pv2_literature_pub_tables.R（勿再抄算法）
.s5_script <- file.path(.engine, "run/prognosis_v2/_rebuild_tables5_hip_aki.R")
if (file.exists(.s5_script)) {
  sys.source(.s5_script, envir = new.env(parent = globalenv()))
} else {
  warning("missing _rebuild_tables5_hip_aki.R")
}
.s678_script <- file.path(.engine, "run/prognosis_v2/_rebuild_s6_s7_s8_hip_aki.R")
if (file.exists(.s678_script)) {
  sys.source(.s678_script, envir = new.env(parent = globalenv()))
} else {
  warning("missing _rebuild_s6_s7_s8_hip_aki.R")
}

# Fig6：OASIS 中介路径图（数字与 Table S8 同源：暴露 per 1 SD）
message("==== Figure 6 mediation path (OASIS) ====")
if (!"OASIS" %in% names(d)) stop("OASIS not in imputed data")
source(file.path(.engine, "Blocks/20_mediation/01block_mediation_prognosis.R"), local = FALSE)
.macaron <- list(
  exposure = "#A8D5E5", mediator = "#F6C6C6", outcome = "#C8E6C9",
  path_a = "#5B9BD5", path_b = "#ED7D31", path_c = "#70AD47", prop = "#7F7F7F"
)
# 中介路径与 Table S8 同源：Table 3 Model 2（Age+Gender）
.med_fit_z <- function(d, expo, med = "OASIS", covs = c("Age", "Gender")) {
  if ("Gender" %in% covs && "Gender" %in% names(d)) d$Gender <- factor(d$Gender)
  need <- c(expo, med, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]), ]
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
  # 底边箭 = Direct effect（与 Table S8 Direct effect HR 同源）；prop 仍用 total log-HR
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
p6a <- .draw_med(res_s, "SIRI") + ggplot2::ggtitle("A  SIRI") +
  ggplot2::theme(plot.title = ggplot2::element_text(family = "Times", face = "bold", size = 12, hjust = 0))
p6b <- .draw_med(res_p, "PIV") + ggplot2::ggtitle("B  PIV") +
  ggplot2::theme(plot.title = ggplot2::element_text(family = "Times", face = "bold", size = 12, hjust = 0))
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
message("Fig6 OK")

message("==== Figures 2–5, 7（对齐参考风格）====")
# Fig2 Boruta 4-panel（展示名去下划线）
.lab_disp <- function(x) {
  x <- as.character(x)
  # GenderMale → Gender: Male；其余走 pipeline_display_label
  x <- gsub("^Gender(Male|Female)$", "Gender: \\1", x)
  x <- gsub("^Race([A-Z].*)$", "Race: \\1", x)
  x <- gsub("^(Ventilation|Hypertension|Diabetes|Heart_Failure|Myocardial_Infarction|Stroke|COPD|Pneumonia|Malignant_Tumor)(Yes|No)$",
            "\\1: \\2", x)
  pipeline_display_label(x)
}
bor_obj <- readRDS(file.path(.tab, "Boruta_objects.rds"))
shap_df <- as.data.frame(readRDS(file.path(.tab, "SHAP_long.rds")))
mean_tab <- as.data.frame(fread(file.path(.tab, "SHAP_by_database.csv")))
bor <- bor_obj$MIMIC
h <- as.data.frame(bor$ImpHistory)
h$iter <- seq_len(nrow(h))
st <- Boruta::attStats(bor)
dec <- setNames(as.character(st$decision), rownames(st))
vars <- setdiff(colnames(h), "iter")
box <- do.call(rbind, lapply(vars, function(v) data.frame(variable = v, z = h[[v]])))
box$decision <- dec[box$variable]; box$decision[is.na(box$decision)] <- "Shadow"
med <- tapply(box$z, box$variable, median, na.rm = TRUE)
box$variable <- factor(.lab_disp(box$variable), levels = .lab_disp(names(sort(med))))
pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00", Shadow = "#1f77b4")
th <- theme_classic(base_size = 8) +
  theme(axis.text.x = element_text(angle = 55, hjust = 1, size = 5.5),
        legend.position = "bottom", legend.key.size = unit(0.3, "cm"))
pA <- ggplot(box, aes(variable, z, fill = decision)) +
  geom_boxplot(outlier.size = 0.25, linewidth = 0.25) +
  scale_fill_manual(values = pal, name = NULL) +
  labs(x = "Attributes", y = "Importance", title = "A") + th
real <- intersect(rownames(st), colnames(h))
lines <- do.call(rbind, lapply(real, function(v) data.frame(iter = h$iter, variable = v, z = h[[v]])))
lines$group <- ifelse(lines$variable %in% c("SIRI", "PIV"), "Inflammatory index", "Other")
pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
  geom_line(linewidth = 0.3) +
  scale_color_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "#4c78a8"), name = NULL) +
  labs(x = "Iteration", y = "Boruta Z-score", title = "B") +
  theme_classic(base_size = 8) + theme(legend.position = "bottom")
sh <- shap_df
sh$group <- ifelse(as.character(sh$variable) %in% c("SIRI", "PIV") |
                     grepl("^SIRI|^PIV", as.character(sh$variable)), "Inflammatory index", "Other")
sh$variable_raw <- as.character(sh$variable)
ord_raw <- names(sort(tapply(abs(sh$shap), sh$variable_raw, mean)))
sh$variable <- factor(.lab_disp(sh$variable_raw), levels = .lab_disp(ord_raw))
pC <- ggplot(sh, aes(shap, variable, color = group)) +
  geom_jitter(height = 0.15, width = 0, size = 0.2, alpha = 0.4) +
  geom_vline(xintercept = 0, linewidth = 0.25) +
  scale_color_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "grey55"), name = NULL) +
  labs(x = "SHAP value (log-hazard)", y = "Feature", title = "C") +
  theme_classic(base_size = 8) + theme(legend.position = "bottom")
md <- mean_tab[, c("variable", "mean_abs_shap")]
names(md)[2] <- "mean_abs"
md$group <- ifelse(md$variable %in% c("SIRI", "PIV") | grepl("^SIRI|^PIV", md$variable),
                   "Inflammatory index", "Other")
ord_md <- names(sort(setNames(md$mean_abs, md$variable)))
md$variable <- factor(.lab_disp(md$variable), levels = .lab_disp(ord_md))
pD <- ggplot(md, aes(mean_abs, variable, fill = group)) +
  geom_col(width = 0.72) +
  scale_fill_manual(values = c("Inflammatory index" = "#e74c3c", "Other" = "grey70"), name = NULL) +
  labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
  theme_classic(base_size = 8) + theme(legend.position = "bottom")
fig2 <- file.path(.fig, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
cairo_pdf(fig2, width = 10.5, height = 6.2, family = "Times")
grid.newpage()
grid.text("MIMIC", x = 0.02, y = 0.98, just = c("left", "top"),
          gp = gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
panels <- list(pA, pB, pC, pD)
for (j in seq_along(panels)) {
  col <- if (j %% 2L == 1L) 0 else 1
  row <- if (j <= 2L) 1 else 0
  print(panels[[j]], vp = viewport(
    x = 0.02 + col * 0.49, y = 0.04 + row * 0.46,
    width = 0.47, height = 0.44, just = c("left", "bottom")
  ))
}
dev.off()

# Fig3 KM cuminc — 分组跟分位级联
.km_one <- function(d, qv, title) {
  d <- d[!is.na(d[[qv]]), ]
  d$sg <- factor(as.character(d[[qv]]), levels = .qsc_meta$labels)
  fit <- survfit(Surv(time, event) ~ sg, data = d)
  sd <- survdiff(Surv(time, event) ~ sg, data = d)
  p <- pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
  plab <- if (p < 0.001) "Log-rank P < 0.001" else sprintf("Log-rank P = %.3f", p)
  pal <- c("#2ca02c", "#ff7f0e", "#9467bd", "#d62728", "#1f77b4")[seq_along(.qsc_meta$labels)]
  g <- survminer::ggsurvplot(
    fit, data = d, fun = "event", conf.int = FALSE, censor = TRUE, censor.size = 1.6,
    risk.table = TRUE, risk.table.height = 0.28, risk.table.title = "Number at risk",
    pval = FALSE, palette = pal,
    legend = "top", legend.title = .qsc_meta$legend_title, legend.labs = .qsc_meta$labels,
    xlab = "Follow-up (years)", ylab = "Cumulative incidence of all-cause mortality",
    title = title, break.time.by = 0.25,
    ggtheme = theme_classic(base_size = 11), fontsize = 3.1
  )
  g$plot <- g$plot + annotate("text", x = 0, y = Inf, label = plab, hjust = 0, vjust = 1.4, size = 3.4)
  g
}
.km_qv <- function(idx) {
  qv <- paste0(idx, "_Group")
  if (!qv %in% names(d)) qv <- paste0(idx, "_Q")
  qv
}
km_plots <- list(
  SIRI = .km_one(d, .km_qv("SIRI"), "SIRI"),
  PIV = .km_one(d, .km_qv("PIV"), "PIV")
)
fig3 <- file.path(.fig, "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf")
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 2, title = NA)
cairo_pdf(fig3, width = 7.4, height = 10.5, family = "Times")
print(km_page)
dev.off()

# Fig4 RCS：暴露 per 1 SD + Model 3；图注报 P-linear（对齐 Table 3）+ P-nonlinear（形状）
.rcs_fit_one <- function(d, idx) {
  covs <- c("Age", "Gender", "CHARLSON")
  d2 <- d[stats::complete.cases(d[, c("time", "event", idx, covs)]), ]
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
  p_from <- function(a) {
    if (is.null(a) || nrow(a) < 2) return(NA_real_)
    cn <- grep("^Pr", colnames(a), value = TRUE)[1]
    suppressWarnings(as.numeric(a[2, cn]))
  }
  # P-linear：与 Table 3 连续 per-SD 同模型（操作层 complete#1）
  p_lin <- if (!is.null(fit_lin)) {
    summary(fit_lin)$coefficients["expo", "Pr(>|z|)"]
  } else NA_real_
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
    p_lin = p_lin, p_nl = p_nl,
    lin_hr = if (!is.null(fit_lin)) exp(coef(fit_lin)["expo"]) else NA_real_,
    xlab = paste0(idx, " (per 1 SD)")
  )
}
rcs_list <- lapply(c("SIRI", "PIV"), function(idx) .rcs_fit_one(d, idx))
names(rcs_list) <- c("SIRI", "PIV")
p_rcs_panels <- lapply(names(rcs_list), function(nm) {
  x <- rcs_list[[nm]]
  if (is.null(x)) return(ggplot() + theme_void() + ggtitle(nm))
  ggplot(x$df, aes(x, hr)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, fill = "#D55E00") +
    geom_line(color = "#D55E00", linewidth = 0.9) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey40") +
    theme_classic(base_size = 11) +
    labs(
      title = nm,
      subtitle = sprintf("P-linear = %s; P-nonlinear = %s", fmt_p(x$p_lin), fmt_p(x$p_nl)),
      x = x$xlab, y = "Hazard ratio (reference = mean / 0 SD)"
    )
})
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) {
  p_rcs_panels[[1]] + p_rcs_panels[[2]]
} else p_rcs_panels[[1]]
ggsave(file.path(.fig, "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality.pdf"),
       p4, width = 11.2, height = 4.2, device = cairo_pdf)

# Fig5 ROC（同源 LP；图例只写 AUC，不写协变量）
.roc_covs <- intersect(c("Age", "CHARLSON", "Sodium"), names(d))
roc_df <- list()
for (idx in c("SIRI", "PIV")) {
  dd <- d[stats::complete.cases(d[, c(idx, "time", "event", .roc_covs)]), ]
  fit <- coxph(as.formula(paste("Surv(time, event) ~", paste(c(idx, .roc_covs), collapse = "+"))), dd)
  lp <- as.numeric(predict(fit, type = "lp"))
  roc <- pROC::roc(dd$event, lp, quiet = TRUE, direction = "<")
  cd <- pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE)
  auc <- as.numeric(pROC::auc(roc))
  roc_df[[idx]] <- data.frame(
    Index = idx, fpr = 1 - cd$specificity, tpr = cd$sensitivity,
    curve = sprintf("%s (AUC %.3f)", idx, auc),
    stringsAsFactors = FALSE
  )
}
roc <- do.call(rbind, roc_df)
roc$curve <- factor(roc$curve, levels = unique(roc$curve))
p5 <- ggplot(roc, aes(fpr, tpr, color = curve)) +
  geom_path(linewidth = 0.9) +
  geom_abline(linetype = 2, color = "grey40") +
  scale_color_manual(values = c("#D55E00", "#0072B2")) +
  labs(x = "1 - specificity", y = "Sensitivity", color = NULL,
       title = "Receiver operating characteristic curves\nfor 365-day all-cause mortality") +
  coord_equal(clip = "off") +
  theme_bw(base_family = "Times", base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(size = 11, face = "bold", margin = margin(b = 6)))
ggsave(file.path(.fig, "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality.pdf"),
       p5, width = 6.2, height = 5.6, device = cairo_pdf, family = "Times")

# Fig7：High vs Low（中间并为 Middle）；层内未调整；每层乘性交互 P（expo×stratum）
message("==== Figure 7 subgroup ====")
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
strata_spec <- list(
  list(lab = "Overall", var = NULL),
  list(lab = "Age", var = "Age_Group"),
  list(lab = "Sex", var = "Gender"),
  list(lab = "Hypertension", var = "Hypertension"),
  list(lab = "Diabetes", var = "Diabetes"),
  list(lab = "SOFA", var = "SOFA_Group")
)
if (!"Age_Group" %in% names(d)) {
  d$Age_Group <- factor(ifelse(d$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
}
if (!"SOFA_Group" %in% names(d) && "SOFA" %in% names(d)) {
  d$SOFA_Group <- factor(ifelse(d$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))
}
# Y 轴分层名双库/双指标共享；交互 P 写在面板右侧（勿塞进 row_lab，否则 facet 会串行）
rows <- list(); y_order <- character(0)
for (idx in c("SIRI", "PIV")) {
  for (sp in strata_spec) {
    if (is.null(sp$var)) {
      r <- .sg_fit(d, idx)
      if (is.null(r)) next
      rows[[length(rows) + 1L]] <- cbind(
        Index = idx, row_lab = "Overall", is_header = FALSE,
        pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE
      )
      y_order <- c(y_order, "Overall")
    } else {
      if (!sp$var %in% names(d)) next
      pint <- .sg_pint(d, idx, sp$var)
      pint_lab <- if (is.finite(pint)) {
        if (pint < 0.001) "P-int <0.001" else sprintf("P-int = %.3f", pint)
      } else "P-int = —"
      rows[[length(rows) + 1L]] <- data.frame(
        Index = idx, row_lab = sp$lab, is_header = TRUE,
        pint_lab = pint_lab, p_interaction = pint,
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
          Index = idx, row_lab = rl, is_header = FALSE,
          pint_lab = NA_character_, p_interaction = NA_real_, r, stringsAsFactors = FALSE
        )
        y_order <- c(y_order, rl)
      }
    }
  }
}
sg <- do.call(rbind, rows)
fwrite(sg, file.path(.tab, "Subgroup_rows.csv"))
if (is.character(.ws) && nzchar(.ws) && dir.exists(.ws)) {
  fwrite(sg, file.path(.ws, "Subgroup_rows.csv"))
}
y_levels <- unique(y_order)
sg$Index <- factor(sg$Index, levels = c("SIRI", "PIV"))
sg$row_lab <- factor(sg$row_lab, levels = rev(y_levels))
sg_pt <- sg[!sg$is_header & is.finite(sg$HR), ]
sg_pt$lo_plot <- pmax(sg_pt$lo, 0.12)
sg_pt$hi_plot <- pmin(sg_pt$hi, 10)
sg_hdr <- sg[sg$is_header, ]
.contrast_lab <- if (identical(.qsc$scheme, "binary")) {
  "High vs Low"
} else if (!is.null(.qsc_meta$contrast_lab) && nzchar(.qsc_meta$contrast_lab)) {
  .qsc_meta$contrast_lab
} else {
  "High vs Low"
}
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
  facet_wrap(~Index, nrow = 1) +
  scale_x_log10(limits = c(0.12, 10), breaks = c(0.25, 0.5, 1, 2, 4, 8)) +
  scale_y_discrete(drop = TRUE) +
  labs(
    x = sprintf("Hazard ratio (%s, log scale)", .contrast_lab), y = NULL,
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
  p7, width = 11.2, height = 6.6, device = cairo_pdf, family = "Times"
)

message("==== 四目录导出 ====")
# 清根目录平铺
unlink(list.files(file.path(.out, "Figures"), pattern = "^Figure.*\\.pdf$", full.names = TRUE))
pub_figure_ensure_formats(file.path(.out, "Figures"))

message("==== 清单核对 ====")
need_t <- c(
  "Table 1. Baseline characteristics.xlsx",
  "Table 2. Incidence of all-cause mortality.xlsx",
  "Table 3. Cox proportional hazards models.xlsx",
  "Table S1. Definitions.xlsx",
  "Table S2. Assessment of multicollinearity.xlsx",
  "Table S3. Cox model including comorbidity count (Model 4).xlsx",
  "Table S4. Predictive performance for 365-day all-cause mortality.xlsx",
  "Table S5. Sensitivity analysis using 90-day all-cause mortality.xlsx",
  "Table S6. Baseline characteristics before and after imputation.xlsx",
  "Table S7. Correlation between inflammatory indices and other indicators.xlsx",
  "Table S8. Mediation analysis.xlsx"
)
need_f <- c(
  "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI.pdf",
  "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf",
  "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf",
  "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality.pdf",
  "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality.pdf",
  "Figure 6. Mediation path diagram of inflammatory indices and all-cause mortality.pdf",
  "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality.pdf"
)
have_t <- list.files(.tab, pattern = "\\.xlsx$")
have_f <- list.files(.fig, pattern = "\\.pdf$")
message("Tables missing: ", paste(setdiff(need_t, have_t), collapse = " | ") %||% "(none)")
message("Figures missing: ", paste(setdiff(need_f, have_f), collapse = " | ") %||% "(none)")

# 引擎级收口：图注 → Methods/软件版本 → 交付白名单（仅 Figures/Tables/方法md/软件txt/中期PDF）
.img_script <- file.path(.engine, "run/prognosis_v2/_refresh_image_info_hip_aki.R")
if (file.exists(.img_script)) {
  sys.source(.img_script, envir = new.env(parent = globalenv()))
}
# S1 Sensitivity 与现行 S5 对齐
.s1 <- file.path(.tab, "Table S1. Definitions.xlsx")
if (file.exists(.s1) && requireNamespace("openxlsx", quietly = TRUE)) {
  x <- openxlsx::read.xlsx(.s1, colNames = TRUE)
  if ("Item" %in% names(x) && "Definition" %in% names(x)) {
    hit <- grepl("Sensitivity", x$Item, ignore.case = TRUE)
    if (any(hit)) {
      x$Definition[hit] <- paste0(
        "Table S5: 90-day all-cause mortality endpoint (same Model 1-3 as Table 3). ",
        "No main-text Table 4; Fine-Gray unavailable without COD."
      )
      openxlsx::write.xlsx(x, .s1, overwrite = TRUE)
      # 再走三线表重导以保样式
      if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
        sci_xlsx_single_header_booktabs(
          .s1, title = "Table S1. Definitions", df_body = x,
          footnotes = "Definitions aligned with the primary and sensitivity analyses."
        )
      }
    }
  }
}
Sys.setenv(
  PV2_COHORT = "adults aged 65 years or older with hip arthroplasty and AKI",
  PV2_MODEL3 = "Age, Gender, CHARLSON",
  PV2_GROUPING = "binary (High vs Low)",
  PV2_SENSITIVITY = "90-day all-cause mortality (Table S5)",
  PV2_MEDIATOR = "OASIS"
)
system2(
  file.path(R.home("bin"), "Rscript"),
  c(
    file.path(.engine, "run/pub/finalize_delivery_root.R"),
    "--dir", .out,
    "--study-type", "prognosis_v2",
    "--outcome", "365-day all-cause mortality",
    "--exposure", "SIRI and PIV",
    "--databases", "MIMIC-IV"
  ),
  stdout = TRUE, stderr = TRUE
)
# Hip AKI P0 机器门控（防 Fig3/6/7/4/下划线/PH/Methods 复发）
.gate_src <- file.path(.engine, "R/pv2_pub_p0_gate.R")
if (file.exists(.gate_src)) {
  sys.source(.gate_src, envir = environment())
  pv2_pub_p0_gate(
    summary_root = .out,
    locked_scheme = if (exists(".qsc") && !is.null(.qsc$scheme)) as.character(.qsc$scheme) else "binary",
    contrast_lab = if (exists(".contrast_lab")) .contrast_lab else "High vs Low",
    require_ph_table = TRUE,
    require_mediation = TRUE,
    stop_on_fail = TRUE
  )
}
message("DONE ", .out)
