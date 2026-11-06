#!/usr/bin/env Rscript
# 卒中 ANLR 发表表：按 Hip prognosis_v2_41904528 summary_results 版式重写（双库各一份）

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(openxlsx)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
setwd(.engine)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/pv2_literature_pub_tables.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)

.proj <- stroke_anlr_proj()
.out <- stroke_anlr_out(.proj)
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.tab <- file.path(.out, "Tables")
IDX <- "ANLR"

dbs <- readRDS(file.path(.tab, "imputed_dbs.rds"))
before <- readRDS(file.path(.tab, "before_imputation_dbs.rds"))
mids_list <- readRDS(file.path(.tab, "imputed_mids.rds"))
.lock <- readRDS(file.path(.tab, "quantile_scheme_resolved.rds"))
m3_by <- readRDS(file.path(.tab, "Model3_by_database.rds"))
m3_shared <- Reduce(intersect, m3_by)
.qsc_meta <- .lock$meta
m2_covs <- c("Age", "Gender")

fmt_p <- pv2_fmt_p
mean_sd <- function(x) sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
med_iqr <- function(x) {
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f%%)", as.integer(k), if (n > 0) 100 * k / n else NA_real_)
is_normal_vec <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3L) return(FALSE)
  p <- tryCatch(
    if (length(x) > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value,
    error = function(e) 0
  )
  is.finite(p) && p >= 0.05
}
disp <- function(x) pipeline_display_label(as.character(x))

write_df <- function(path, title, df, footnotes = character(0), level_rows = integer(0)) {
  sci_xlsx_single_header_booktabs(
    path, title = title, df_body = df, footnotes = footnotes,
    level_row_idx = if (length(level_rows)) level_rows + 1L else NULL
  )
  message("wrote ", basename(path))
}

# Hip 同款 Table 1 分区（卒中可用列）
.layout <- list(
  Demographics = list(
    cont = c(Age = "Age, years"),
    cats = list(Gender = c("Male", "Female"), Race = NULL)
  ),
  Severity = list(
    cont = c(
      SOFA = "SOFA", GCS = "GCS", APSIII = "APSIII", OASIS = "OASIS"
    ),
    cats = list(Ventilation = c("Yes", "No"))
  ),
  `Vital Signs` = list(
    cont = c(
      HR = "Heart rate", NBPS = "SBP, mmHg", NBPD = "DBP, mmHg",
      RR = "Respiratory rate", SpO2 = "SpO2, %", Temperature = "Temperature, °C"
    ),
    cats = list()
  ),
  Laboratory = list(
    cont = c(
      Hemoglobin = "Hemoglobin", WBC = "WBC", PlateletCount = "Platelet count",
      RDW = "RDW", Glucose = "Glucose", Creatinine = "Creatinine",
      UreaNitrogen = "Urea nitrogen", Sodium = "Sodium", Potassium = "Potassium"
    ),
    cats = list()
  ),
  Comorbidities = list(
    cont = c(),
    cats = list(
      Hypertension = c("Yes", "No"), Diabetes = c("Yes", "No"),
      Heart_Failure = c("Yes", "No"), Myocardial_Infarction = c("Yes", "No"),
      CKD = c("Yes", "No"), COPD = c("Yes", "No"), Pneumonia = c("Yes", "No"),
      Malignant_Tumor = c("Yes", "No"), Hyperlipidemia = c("Yes", "No")
    )
  ),
  Exposure = list(
    cont = c(ANLR = "ANLR"),
    cats = list()
  )
)
.cat_lab <- c(
  Gender = "Sex", Race = "Race", Ventilation = "Mechanical ventilation",
  Hypertension = "Hypertension", Diabetes = "Diabetes",
  Heart_Failure = "Heart failure", Myocardial_Infarction = "Myocardial infarction",
  CKD = "CKD", COPD = "COPD", Pneumonia = "Pneumonia",
  Malignant_Tumor = "Malignant tumor", Hyperlipidemia = "Hyperlipidemia"
)

.build_table1 <- function(d, db_nm) {
  d <- as.data.frame(d)
  d$event <- as.integer(d$fustatus)
  d$status <- factor(
    ifelse(d$event == 1L, "Non-survivor", "Survivor"),
    levels = c("Survivor", "Non-survivor")
  )
  if ("Gender" %in% names(d)) {
    g <- as.character(d$Gender)
    g[g %in% c("M", "male", "Male")] <- "Male"
    g[g %in% c("F", "female", "Female")] <- "Female"
    d$Gender <- factor(g, levels = c("Male", "Female"))
  }
  for (v in names(.layout$Comorbidities$cats)) {
    if (!v %in% names(d)) next
    x <- as.character(d[[v]])
    x[x %in% c("1", "Yes", "yes", "TRUE")] <- "Yes"
    x[x %in% c("0", "No", "no", "FALSE")] <- "No"
    d[[v]] <- factor(x, levels = c("Yes", "No"))
  }
  if ("Ventilation" %in% names(d)) {
    x <- as.character(d$Ventilation)
    x[x %in% c("1", "Yes", "yes", "TRUE")] <- "Yes"
    x[x %in% c("0", "No", "no", "FALSE")] <- "No"
    d$Ventilation <- factor(x, levels = c("Yes", "No"))
  }

  slices <- list(
    Overall = d,
    Survivor = d[d$status == "Survivor", , drop = FALSE],
    `Non-survivor` = d[d$status == "Non-survivor", , drop = FALSE]
  )
  headers <- c(
    sprintf("Overall, N = %s", pub_format_int(nrow(slices$Overall))),
    sprintf("Survivor, N = %s", pub_format_int(nrow(slices$Survivor))),
    sprintf("Non-survivor, N = %s", pub_format_int(nrow(slices[["Non-survivor"]])))
  )
  rows <- list(); level_rows <- integer(0); section_names <- character(0)
  add <- function(lab, vals, p = "") {
    rows[[length(rows) + 1L]] <<- c(lab, vals, p)
  }
  cont_cell <- function(dd, var, normal) if (normal) mean_sd(dd[[var]]) else med_iqr(dd[[var]])
  cat_cell <- function(dd, var, lv) {
    k <- sum(as.character(dd[[var]]) == lv, na.rm = TRUE)
    n <- sum(!is.na(dd[[var]]))
    n_pct(k, n)
  }

  for (sec in names(.layout)) {
    section_names <- c(section_names, sec)
    add(sec, rep("", 3), "")
    spec <- .layout[[sec]]
    for (v in names(spec$cont)) {
      if (!v %in% names(d)) next
      normal <- is_normal_vec(d[[v]])
      vals <- vapply(slices, function(dd) cont_cell(dd, v, normal), character(1))
      p <- tryCatch(stats::wilcox.test(d[[v]] ~ d$status)$p.value, error = function(e) NA_real_)
      add(spec$cont[[v]], vals, fmt_p(p))
    }
    for (v in names(spec$cats)) {
      if (!v %in% names(d)) next
      levs <- spec$cats[[v]]
      if (is.null(levs)) {
        levs <- sort(unique(as.character(d[[v]][!is.na(d[[v]])])))
      }
      p <- tryCatch({
        tab <- table(d[[v]], d$status)
        if (any(tab < 5)) stats::fisher.test(tab)$p.value else suppressWarnings(stats::chisq.test(tab)$p.value)
      }, error = function(e) NA_real_)
      add(.cat_lab[[v]] %||% disp(v), rep("", 3), fmt_p(p))
      for (lv in levs) {
        level_rows <- c(level_rows, length(rows) + 1L)
        vals <- vapply(slices, function(dd) cat_cell(dd, v, lv), character(1))
        add(paste0("  ", lv), vals, "")
      }
    }
  }
  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c("Characteristic", headers, "p-value")
  list(
    body = body, level_rows = level_rows, section_names = section_names,
    n = nrow(d), n_death = sum(d$event == 1L)
  )
}

.build_table2 <- function(d) {
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  qv <- paste0(IDX, "_Group")
  dd <- d[!is.na(d[[qv]]) & is.finite(d$time) & d$time > 0, , drop = FALSE]
  dd$ord <- as.integer(dd[[qv]])
  tr <- tryCatch(
    stats::glm(event ~ ord, offset = log(pmax(time, 1e-8)), family = poisson(), data = dd),
    error = function(e) NULL
  )
  p_tr <- if (!is.null(tr)) summary(tr)$coefficients["ord", "Pr(>|z|)"] else NA_real_
  t2_rows <- list()
  t2_rows[[1L]] <- c(IDX, "", "", "", "")
  for (g in .qsc_meta$labels) {
    sub <- dd[as.character(dd[[qv]]) == g, , drop = FALSE]
    n <- nrow(sub); ev <- sum(sub$event == 1L); pyrs <- sum(sub$time)
    ci <- stats::poisson.test(ev, T = max(pyrs, .Machine$double.eps))$conf.int * 1e2
    t2_rows[[length(t2_rows) + 1L]] <- c(
      quantile_scheme_level_display(g, .lock$scheme),
      as.character(n), as.character(ev),
      sprintf("%.2f", 100 * ev / max(n, 1L)),
      sprintf("%.2f (%.2f\u2013%.2f)", 100 * ev / max(pyrs, .Machine$double.eps), ci[1], ci[2])
    )
  }
  t2_rows[[length(t2_rows) + 1L]] <- c("P for trend", fmt_p(p_tr), "", "", "")
  body2 <- as.data.frame(do.call(rbind, t2_rows), stringsAsFactors = FALSE)
  names(body2) <- c(
    "Variable", "Participants", "All-cause mortality", "Cumulative incidence (%)",
    "Per 100 person-year (95% CI)"
  )
  body2
}

# 与 Fig5 同源：Cox LP = ANLR + Age + Sodium + GCS
.roc_lp_covs <- c("Age", "Sodium", "GCS")
.build_s4 <- function(d) {
  if (!requireNamespace("pROC", quietly = TRUE)) return(NULL)
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  covs <- intersect(.roc_lp_covs, names(d))
  need <- c(IDX, "time", "event", covs)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, , drop = FALSE]
  if (nrow(dd) < 20L) return(NULL)
  fit <- tryCatch(
    survival::coxph(stats::as.formula(paste("Surv(time, event) ~", paste(c(IDX, covs), collapse = " + "))), dd),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  lp <- as.numeric(stats::predict(fit, type = "lp"))
  roc <- tryCatch(pROC::roc(dd$event, lp, quiet = TRUE, direction = "<"), error = function(e) NULL)
  if (is.null(roc)) return(NULL)
  auc <- as.numeric(pROC::auc(roc))
  ci <- tryCatch(as.numeric(pROC::ci.auc(roc)), error = function(e) c(NA, NA, NA))
  best <- tryCatch(
    pROC::coords(roc, "best", ret = c("sensitivity", "specificity"), transpose = FALSE),
    error = function(e) NULL
  )
  data.frame(
    Index = paste0(IDX, " Cox LP"),
    AUC = sprintf("%.3f", auc),
    `AUC 95% CI` = sprintf("%.3f\u2013%.3f", ci[1], ci[3]),
    Sensitivity = if (!is.null(best)) sprintf("%.3f", best$sensitivity[1]) else "",
    Specificity = if (!is.null(best)) sprintf("%.3f", best$specificity[1]) else "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

.build_s9 <- function(d, m3) {
  d <- as.data.frame(d)
  d$time <- as.numeric(d$futime_years)
  d$event <- as.integer(d$fustatus)
  d$expo_z <- as.numeric(scale(d[[IDX]]))
  qv <- paste0(IDX, "_Group")
  d$expo_bin <- factor(as.character(d[[qv]]), levels = .qsc_meta$labels)
  if ("Gender" %in% names(d)) d$Gender <- factor(d$Gender)
  rows <- list()
  specs <- list(
    list(lab = paste0(IDX, " per 1 SD"), rhs = paste(c("expo_z", m3), collapse = " + ")),
    list(
      lab = paste0(IDX, " ", .qsc_meta$labels[length(.qsc_meta$labels)], " vs ", .qsc_meta$labels[1]),
      rhs = paste(c("expo_bin", m3), collapse = " + ")
    )
  )
  for (sp in specs) {
    fit <- tryCatch(
      coxph(as.formula(paste("Surv(time, event) ~", sp$rhs)), data = d),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    zph <- tryCatch(cox.zph(fit), error = function(e) NULL)
    if (is.null(zph)) next
    tb <- as.data.frame(zph$table)
    for (i in seq_len(nrow(tb))) {
      rows[[length(rows) + 1L]] <- data.frame(
        Model = sp$lab,
        Term = disp(rownames(tb)[i]),
        chisq = sprintf("%.3f", tb$chisq[i]),
        df = as.integer(tb$df[i]),
        P = fmt_p(tb$p[i]),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

.build_s1 <- function(db_nm) {
  data.frame(
    Item = c(
      "Cohort", "Age", "ANLR", "Exposure laboratory timing",
      "Primary outcome", "Landmark", "Database", "Imputation",
      "Covariate selection", "Mediator"
    ),
    Definition = c(
      "Adults with ischemic stroke admitted to ICU",
      "Age >= 18 years at ICU admission",
      "Albumin / (neutrophil count / lymphocyte count)",
      "First available albumin, neutrophil and lymphocyte after ICU admission",
      sprintf("%s from ICU admission", .endpoint),
      sprintf("Follow-up censored at %d days", .days),
      paste0(db_nm, " (dual-database equal footing with eICU/MIMIC twin analysis)"),
      "MICE (cart, m = 5); exposure, follow-up and death status not imputed; Cox HRs pooled by Rubin's rules",
      paste0(
        "Model 1 unadjusted; Model 2 Age + Gender; Model 3 dual-DB harmonized: ",
        paste(setdiff(m3_shared, "OASIS"), collapse = ", "),
        ". OASIS reserved as mediator; ANLR components excluded from covariates."
      ),
      "OASIS (Table S7 → Table S8 → Figure 6)"
    ),
    stringsAsFactors = FALSE
  )
}

cox_notes <- function(m3) {
  c(
    "The Model 1 was non-adjusted.",
    paste0("The Model 2 was adjusted by: ", paste(m2_covs, collapse = ", "), "."),
    paste0("The Model 3 was adjusted by: ", paste(m3, collapse = ", "), "."),
    "SOFA was not included in Model 3 to avoid over-adjustment along the mediation pathway.",
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample.",
    paste0(
      "Grouped contrasts use ", .qsc_meta$labels[1], " as the reference (",
      .qsc_meta$labels[length(.qsc_meta$labels)], " vs ", .qsc_meta$labels[1], ")."
    ),
    quantile_scheme_footnote_lines(.lock)
  )
}

for (nm in names(dbs)) {
  message("==== rebuild tables: ", nm, " ====")
  d <- as.data.frame(dbs[[nm]])
  mids <- mids_list[[nm]]
  m3 <- m3_shared

  # ---- Table 1 ----
  t1 <- .build_table1(d, nm)
  write_df(
    file.path(.tab, pv2_table_xlsx_name("Table 1", "Baseline characteristics", db = nm)),
    pv2_table_title("Table 1", "Baseline characteristics"),
    t1$body,
    footnotes = c(
      "Continuous variables are mean (SD) if approximately normal, otherwise median (IQR). Categorical variables are n (%).",
      "P values compare Survivor vs Non-survivor (Wilcoxon or chi-square/Fisher).",
      sprintf(
        "Analytic cohort: ischemic stroke, Age\u226518, %s; %s (N=%s, deaths=%s).",
        nm, .endpoint, pub_format_int(t1$n), pub_format_int(t1$n_death)
      )
    ),
    level_rows = t1$level_rows
  )

  # ---- Table 2 ----
  body2 <- .build_table2(d)
  write_df(
    file.path(.tab, pv2_table_xlsx_name("Table 2", "Incidence of all-cause mortality", db = nm)),
    pv2_table_title("Table 2", "Incidence of all-cause mortality"),
    body2,
    footnotes = c(
      "Per 100 person-year is events / person-years x 100. Interval is the exact Poisson 95% CI.",
      sprintf(
        "P for trend is from an unadjusted Poisson model with %s coded 1-%d.",
        .qsc_meta$legend_title %||% .lock$scheme, .qsc_meta$n_groups
      ),
      sprintf("Outcome: all-cause death within %d days after ICU admission.", .days),
      quantile_scheme_footnote_lines(.lock)
    ),
    level_rows = which(startsWith(body2$Variable, "  "))
  )

  # ---- Table 3 ----
  body3 <- pv2_cox_wide_m123_body(
    d, IDX, .lock, mids = mids,
    m2_covs = m2_covs, m3_covs = m3,
    time_var = "futime_years", event_var = "fustatus", rubin = TRUE
  )
  # Hip 连续行展示为 "per 1 SD"
  body3$Variable <- sub(paste0("^\\s*", IDX, " \\(per 1 SD\\)$"), "  per 1 SD", body3$Variable)
  body3$Variable <- sub("^\\s*P for trend$", "  P for trend", body3$Variable)
  pv2_write_cox_wide_xlsx(
    file.path(.tab, pv2_table_xlsx_name(
      "Table 3", sprintf("Cox proportional hazards models for %s", .endpoint), db = nm)),
    pv2_table_title("Table 3", sprintf("Cox proportional hazards models for %s", .endpoint)),
    body3,
    footnotes = cox_notes(m3)
  )

  # ---- Table S1 ----
  write_df(
    file.path(.tab, pv2_table_xlsx_name("Table S1", "Definitions", db = nm)),
    pv2_table_title("Table S1", "Definitions"),
    .build_s1(nm)
  )

  # ---- Table S2 VIF on Model3 set ----
  if (requireNamespace("car", quietly = TRUE)) {
    dd <- d
    if ("Gender" %in% names(dd)) dd$Gender <- factor(dd$Gender)
    for (v in intersect(m3, names(dd))) {
      if (is.character(dd[[v]]) || is.logical(dd[[v]])) dd[[v]] <- factor(dd[[v]])
    }
    fml <- as.formula(paste("futime_years ~", paste(m3, collapse = " + ")))
    fit_lm <- tryCatch(stats::lm(fml, data = dd), error = function(e) NULL)
    vif_df <- NULL
    if (!is.null(fit_lm)) {
      vf <- tryCatch(car::vif(fit_lm), error = function(e) NULL)
      if (!is.null(vf)) {
        if (is.matrix(vf)) {
          vif_df <- data.frame(Variable = disp(rownames(vf)), VIF = round(as.numeric(vf[, 1]), 3),
                               stringsAsFactors = FALSE)
        } else {
          vif_df <- data.frame(Variable = disp(names(vf)), VIF = round(as.numeric(vf), 3),
                               stringsAsFactors = FALSE)
        }
      }
    }
    if (!is.null(vif_df)) {
      write_df(
        file.path(.tab, pv2_table_xlsx_name("Table S2", "Assessment of multicollinearity", db = nm)),
        pv2_table_title("Table S2", "Assessment of multicollinearity"),
        vif_df,
        footnotes = c(
          "VIF calculated for Table 3 Model 3 covariates.",
          "VIF < 5 considered acceptable."
        )
      )
    }
  }

  # ---- Table S3 Model4（Hip：仅 Model4 一列 HR/P）----
  m4 <- unique(c(m3, "Hypertension", "Diabetes"))
  m4 <- m4[m4 %in% names(d)]
  body_m4wide <- pv2_cox_wide_m123_body(
    d, IDX, .lock, mids = mids,
    m2_covs = m2_covs, m3_covs = m4,
    time_var = "futime_years", event_var = "fustatus", rubin = TRUE
  )
  body_m4wide$Variable <- sub(
    paste0("^\\s*", IDX, " \\(per 1 SD\\)$"), "  per 1 SD", body_m4wide$Variable
  )
  body_s3 <- data.frame(
    Variable = body_m4wide$Variable,
    `HR (95% CI)` = body_m4wide[[6]],
    P = body_m4wide[[7]],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  write_df(
    file.path(.tab, pv2_table_xlsx_name(
      "Table S3", "Cox model including additional comorbidity (Model 4)", db = nm)),
    pv2_table_title("Table S3", "Cox model including additional comorbidity (Model 4)"),
    body_s3,
    footnotes = c(
      paste0(
        "The Model 4 was adjusted by: ", paste(m4, collapse = ", "),
        " (Table 3 Model 3 + ", paste(setdiff(m4, m3), collapse = ", "), ")."
      ),
      "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
      quantile_scheme_footnote_lines(.lock)
    ),
    level_rows = which(startsWith(body_s3$Variable, "  "))
  )

  # ---- Table S4（与 Fig5 同源：Cox LP）----
  s4 <- .build_s4(d)
  if (!is.null(s4)) {
    write_df(
      file.path(.tab, pv2_table_xlsx_name(
        "Table S4", sprintf("Predictive performance for %s", .endpoint), db = nm)),
      pv2_table_title("Table S4", sprintf("Predictive performance for %s", .endpoint)),
      s4,
      footnotes = c(
        paste0(
          "Discrimination for ", .endpoint,
          " using the Cox linear predictor of ANLR + Age, Sodium, GCS (same specification as Figure 5)."
        ),
        "Youden index on the ROC of the Cox linear predictor; AUC with DeLong 95% CI."
      )
    )
  }

  # ---- Table S5 in-hospital ----
  if ("hosp_dead" %in% names(d) && sum(is.finite(d$hosp_futime) & !is.na(d$hosp_dead)) > 50) {
    dh <- d[is.finite(d$hosp_futime) & d$hosp_futime > 0 & !is.na(d$hosp_dead), ]
    dh$futime_years <- dh$hosp_futime / 365.25
    dh$fustatus <- as.integer(dh$hosp_dead)
    body_h <- tryCatch(
      pv2_cox_wide_m123_body(
        dh, IDX, .lock, mids = NULL,
        m2_covs = m2_covs, m3_covs = m3,
        time_var = "futime_years", event_var = "fustatus", rubin = FALSE
      ),
      error = function(e) NULL
    )
    if (!is.null(body_h)) {
      body_h$Variable <- sub(paste0("^\\s*", IDX, " \\(per 1 SD\\)$"), "  per 1 SD", body_h$Variable)
      pv2_write_cox_wide_xlsx(
        file.path(.tab, pv2_table_xlsx_name(
          "Table S5", "Sensitivity analysis using in-hospital all-cause mortality", db = nm)),
        pv2_table_title(
          "Table S5",
          "Sensitivity analysis of the association between ANLR and in-hospital all-cause mortality"
        ),
        body_h,
        footnotes = c(
          "Endpoint redefined as in-hospital all-cause death; exposure cut-points follow the primary 28-day locked grouping.",
          cox_notes(m3)[1:4]
        )
      )
    }
  }

  # ---- Table S6 before/after ----
  b0 <- as.data.frame(before[[nm]])
  secs <- list(
    Demographics = c("Age", "Gender"),
    Severity = c("SOFA", "GCS", "APSIII", "OASIS"),
    Laboratory = c("Hemoglobin", "WBC", "PlateletCount", "Creatinine", "UreaNitrogen", "Glucose"),
    Exposure = c("ANLR")
  )
  cont_spec <- c(
    Age = "Age, years", SOFA = "SOFA", GCS = "GCS", APSIII = "APSIII", OASIS = "OASIS",
    Hemoglobin = "Hemoglobin", WBC = "WBC", PlateletCount = "Platelet count",
    Creatinine = "Creatinine", UreaNitrogen = "Urea nitrogen", Glucose = "Glucose",
    ANLR = "ANLR"
  )
  cat_spec <- list(Gender = c("Male", "Female"))
  # harmonize Gender labels in before
  if ("Gender" %in% names(b0)) {
    g <- as.character(b0$Gender)
    g[g %in% c("M", "male", "Male")] <- "Male"
    g[g %in% c("F", "female", "Female")] <- "Female"
    b0$Gender <- g
  }
  if ("Gender" %in% names(d)) {
    g <- as.character(d$Gender)
    g[g %in% c("M", "male", "Male")] <- "Male"
    g[g %in% c("F", "female", "Female")] <- "Female"
    d$Gender <- g
  }
  s6 <- tryCatch(
    pv2_s6_before_after_body(
      b0, d, sections = secs, cont_spec = cont_spec,
      cat_spec = cat_spec, cat_lab = c(Gender = "Sex")
    ),
    error = function(e) { message("S6 fail ", nm, ": ", e$message); NULL }
  )
  if (!is.null(s6)) {
    write_df(
      file.path(.tab, pv2_table_xlsx_name(
        "Table S6", "Baseline characteristics before and after imputation", db = nm)),
      pv2_table_title("Table S6", "Baseline characteristics before and after imputation"),
      s6$body,
      footnotes = c(
        "Before = analysis set prior to MICE; After = first completed imputed dataset (operational layer).",
        "P values compare before vs after distributions."
      ),
      level_rows = s6$level_rows
    )
  }

  # ---- Table S7 / S8 ----
  lab_pool <- c(
    "SOFA", "APSIII", "OASIS", "GCS", "WBC", "Hemoglobin", "PlateletCount",
    "RDW", "Sodium", "Potassium", "Glucose", "Creatinine", "UreaNitrogen"
  )
  lab_pool <- intersect(lab_pool, names(d))
  lab_pool <- setdiff(lab_pool, c("Albumin", "NeutrophilCount", "Lymphocytes"))
  s7 <- pv2_s7_exposure_mediator_body(
    d, exposures = IDX, mediators = lab_pool,
    m1_covs = character(0), m2_covs = m2_covs, m3_covs = m3
  )
  write_df(
    file.path(.tab, pv2_table_xlsx_name(
      "Table S7", "Correlation between ANLR and other indicators", db = nm)),
    pv2_table_title("Table S7", "Correlation between ANLR and other indicators"),
    s7,
    footnotes = c(
      pv2_table3_covariate_footnotes(m2_covs = m2_covs, m3_covs = m3),
      "Each linear model regresses the standardized indicator on ANLR (per 1 SD), matching Table S8 path a direction.",
      "Table S8 / Figure 6 use the Model 2 adjustment (Age, Gender); Model 2 beta therefore aligns with Table S8 Path a on the same completed dataset."
    )
  )
  s8 <- pv2_s8_mediation_body(
    d, exposures = IDX, mediators = "SOFA",
    covs = m2_covs, time_var = "futime_years", event_var = "fustatus",
    bootstrap_B = 200L, seed = 41904528L
  )
  write_df(
    file.path(.tab, pv2_table_xlsx_name("Table S8", "Mediation analysis", db = nm)),
    pv2_table_title("Table S8", "Mediation analysis"),
    s8,
    footnotes = c(
      "Mediator: SOFA. Path models adjusted for Age and Gender (Table 3 Model 2).",
      "SOFA omitted from its own adjustment set.",
      "Direct effect HR matches Figure 6 bottom arrow.",
      "Proportion mediated = (a\times b)/total on the log-hazard scale; bootstrap 95% CI.",
      "Exploratory when path a is non-significant; proportion mediated may be unstable."
    )
  )

  # ---- Table S9 ----
  s9 <- .build_s9(d, m3)
  if (!is.null(s9)) {
    write_df(
      file.path(.tab, pv2_table_xlsx_name(
        "Table S9", "Proportional hazards assumption (Schoenfeld residuals)", db = nm)),
      pv2_table_title("Table S9", "Proportional hazards assumption (Schoenfeld residuals)"),
      s9,
      footnotes = "Schoenfeld residual tests (cox.zph) on the first completed imputed dataset."
    )
  }
}

# 交付 Tables 只留 xlsx + 必要 rds/txt（中间 csv 挪到本结局 workspace）
.ws <- file.path(.proj, paste0(stroke_anlr_out_name(), "_delivery_workspace"), "tables_non_xlsx_stroke_anlr")
dir.create(.ws, recursive = TRUE, showWarnings = FALSE)
keep_rds <- c(
  "imputed_dbs.rds", "imputed_mids.rds", "before_imputation_dbs.rds",
  "Model3_by_database.rds", "quantile_scheme_resolved.rds",
  "Boruta_objects.rds", "SHAP_long.rds",
  "Covariate_selection_note.txt", "Model3_by_database.csv",
  "preferred_mediator.txt", "Imputation_methods_note.txt",
  "Quantile_scheme_cascade_lock.txt"
)
for (f in list.files(.tab, full.names = TRUE)) {
  bn <- basename(f)
  if (grepl("\\.xlsx$", bn, ignore.case = TRUE)) next
  if (bn %in% keep_rds) next
  if (grepl("\\.(csv|txt|rds)$", bn, ignore.case = TRUE) && !bn %in% keep_rds) {
    file.rename(f, file.path(.ws, bn))
  }
}
# 删掉与当前 landmark 天数不符的旧 Table 3 / S4 文件名
.day_token <- paste0(.days, "-day")
for (pat in c(
  "^Table 3-.*Cox proportional hazards models.*\\.xlsx$",
  "^Table S4-.*Predictive performance.*\\.xlsx$"
)) {
  oldf <- list.files(.tab, pattern = pat, full.names = TRUE)
  drop <- oldf[!grepl(.day_token, oldf, fixed = TRUE)]
  if (length(drop)) unlink(drop)
}

message("==== table rebuild done ====")
print(sort(list.files(.tab, pattern = "\\.xlsx$")))
