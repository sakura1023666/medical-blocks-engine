# 新项目收尾扩展：<5/<6、RCS cutoff、5/10年预测、465分钟临床包
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
source(file.path(engine, "Blocks/15_rcs/05block_rcs_cox_models_panel.R"), local = FALSE)
pv2_ensure_dirs()
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(survey)
  library(pROC)
})
options(survey.lonely.psu = "adjust")

tab_dir <- pv2_tab_dir
ckpt <- pv2_ckpt_dir
fig_dir <- pv2_fig_dir
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))
mids_all <- {
  p <- pv2_artifact("imputed_mids.rds", must_exist = FALSE)
  if (!is.na(p) && file.exists(p)) readRDS(p) else list()
}
note <- pv2_artifact("Covariate_selection_note.txt")
m3_line <- grep("^Model 3 =", readLines(note, warn = FALSE), value = TRUE)[1]
m3_cov <- trimws(strsplit(sub("^Model 3 =\\s*", "", m3_line), "\\s*\\+\\s*")[[1]])
message("Model 3: ", paste(m3_cov, collapse = ", "))

fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1])
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi, p) {
  sprintf("%.3f (%.3f–%.3f)", hr, lo, hi)
}
cox_fit <- function(d, rhs, db) {
  d <- as.data.frame(d)
  d$database <- db
  need <- unique(c("futime_years", "fustatus", all.vars(stats::as.formula(paste("~", rhs)))))
  need <- intersect(need, names(d))
  d <- d[stats::complete.cases(d[, need]) & d$futime_years > 0, ]
  weighted <- identical(db, "NHANES") && "survey_weight" %in% names(d) && any(!is.na(d$survey_weight))
  mids <- if (db %in% names(mids_all)) mids_all[[db]] else NULL
  expo_keep <- intersect(c("Sleep_hours", "Sleep_Group", "sleep_lt5", "sleep_lt6",
                           "sleep_cut_rcs", "sleep_lt465", "futime_years", "fustatus", "ID"), names(d))
  out <- tryCatch(
    pv2_cox_extract(d, rhs, mids = mids, weighted = weighted, rubin = TRUE, exposure_keep = expo_keep),
    error = function(e) NULL
  )
  if (is.null(out)) {
    out <- pv2_cox_extract(d, rhs, mids = NULL, weighted = weighted, rubin = FALSE, exposure_keep = expo_keep)
  }
  list(fit = out, n = nrow(d), deaths = sum(d$fustatus == 1))
}
pick <- function(fit, key) {
  if (is.null(fit) || !nrow(fit)) return(NULL)
  i <- grep(key, fit$term, fixed = TRUE)
  if (!length(i)) return(NULL)
  fit[i[1], , drop = FALSE]
}
row_models <- function(d, db, expo_term, key, label) {
  specs <- list(
    Model1 = expo_term,
    Model2 = paste(expo_term, "Age + Gender", sep = " + "),
    Model3 = paste(c(expo_term, m3_cov), collapse = " + ")
  )
  out <- list()
  for (md in names(specs)) {
    r <- cox_fit(d, specs[[md]], db)
    hit <- pick(r$fit, key)
    if (is.null(hit)) next
    out[[length(out) + 1L]] <- data.frame(
      database = db, role = pv2_role_label(db), contrast = label, model = md,
      n = r$n, deaths = r$deaths,
      HR = hit$hr, lo = hit$lo, hi = hit$hi, P = hit$p,
      `HR (95% CI)` = hr_cell(hit$hr, hit$lo, hit$hi),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

# ---------- S9: <5 / <6 vs 7-8 ----------
s9 <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$Sleep_Group <- factor(as.character(d$Sleep_Group), levels = c("7-8", "<7", ">=9"))
  # 只保留参照 7-8 与极端短睡，便于 vs 7-8
  for (cut in c(5, 6)) {
    lab <- sprintf("<%d h vs 7-8 h", cut)
    dd <- d
    dd$sleep_ext <- NA_character_
    dd$sleep_ext[dd$Sleep_hours >= 7 & dd$Sleep_hours < 9] <- "7-8"
    dd$sleep_ext[dd$Sleep_hours < cut] <- sprintf("<%d", cut)
    dd$sleep_ext <- factor(dd$sleep_ext, levels = c("7-8", sprintf("<%d", cut)))
    dd <- dd[!is.na(dd$sleep_ext), ]
    key <- paste0("sleep_ext<", cut)
    # term name in R: sleep_ext<5
    s9[[length(s9) + 1L]] <- row_models(dd, nm, "sleep_ext", paste0("sleep_ext<", cut), lab)
  }
}
s9_df <- do.call(rbind, s9)
data.table::fwrite(s9_df, file.path(ckpt, "Table S9. Extreme short sleep Cox.csv"))
for (nm in unique(s9_df$database)) {
  sub <- s9_df[s9_df$database == nm, ]
  body <- data.frame(
    Contrast = sub$contrast, Model = sub$model, `N (deaths)` = sprintf("%d (%d)", sub$n, sub$deaths),
    `HR (95% CI)` = sub$`HR (95% CI)`, P = fmt_p(sub$P),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S9-%s. Extreme short sleep and all-cause mortality.xlsx", nm)),
    title = "Table S9. Extreme short sleep (<5 h, <6 h) versus 7-8 h and all-cause mortality",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Each contrast keeps the 7-8 h reference group and participants below the short-sleep cut.",
      "The Model 1 was non-adjusted.",
      "The Model 2 was adjusted by: Age, Gender.",
      paste0("The Model 3 was adjusted by: ", paste(m3_cov, collapse = ", "), "."),
      "NHANES models are survey-weighted when applicable. CHARLS is validation only."
    )
  )
}
message("S9 done")

# ---------- S10: RCS cutoff ----------
rcs_fit <- rcs_cox_models_panel_fit(
  dbs,
  models = list("Model 1" = character(0), "Model 3" = m3_cov),
  survey_dbs = "NHANES",
  ref_value = 7.5
)
cut_rows <- list()
for (nm in names(dbs)) {
  for (md in c("Model 1", "Model 3")) {
    sub <- rcs_fit$rcs[as.character(rcs_fit$rcs$database) == nm & as.character(rcs_fit$rcs$model) == md, ]
    if (!nrow(sub)) next
    i_min <- which.min(sub$HR)
    cut_h <- sub$hours[i_min]
    # HR=1 crossings nearest 7.5
    cross <- which(diff(sign(sub$HR - 1)) != 0)
    cross_h <- if (length(cross)) {
      hs <- sub$hours[cross]
      hs[which.min(abs(hs - 7.5))]
    } else NA_real_
    cut_rows[[length(cut_rows) + 1L]] <- data.frame(
      database = nm, role = pv2_role_label(nm), model = md,
      min_risk_hours = round(cut_h, 3),
      nearest_HR1_hours = if (is.finite(cross_h)) round(cross_h, 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
}
cut_df <- do.call(rbind, cut_rows)
data.table::fwrite(cut_df, file.path(ckpt, "Table S10. RCS cutoffs.csv"))

# 用 Model 3 最低风险点做二分（主库；验证也报）
s10_cox <- list()
for (nm in names(dbs)) {
  cut_h <- cut_df$min_risk_hours[cut_df$database == nm & cut_df$model == "Model 3"][1]
  if (!is.finite(cut_h)) next
  d <- as.data.frame(dbs[[nm]])
  d$sleep_cut_rcs <- factor(ifelse(d$Sleep_hours < cut_h, "<cutoff", ">=cutoff"),
                            levels = c(">=cutoff", "<cutoff"))
  r <- row_models(d, nm, "sleep_cut_rcs", "sleep_cut_rcs<cutoff",
                  sprintf("<%.2fh vs >=%.2fh (RCS min-risk)", cut_h, cut_h))
  if (!is.null(r)) {
    r$cutoff_hours <- cut_h
    s10_cox[[length(s10_cox) + 1L]] <- r
  }
}
s10_cox_df <- do.call(rbind, s10_cox)
data.table::fwrite(s10_cox_df, file.path(ckpt, "Table S10. RCS cutoff Cox.csv"))
for (nm in unique(cut_df$database)) {
  c1 <- cut_df[cut_df$database == nm, ]
  c2 <- s10_cox_df[s10_cox_df$database == nm, ]
  body1 <- data.frame(
    Model = c1$model,
    `Minimum-risk sleep, h` = c1$min_risk_hours,
    `Nearest HR=1 sleep, h` = ifelse(is.na(c1$nearest_HR1_hours), "", sprintf("%.3f", c1$nearest_HR1_hours)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  body2 <- if (nrow(c2)) data.frame(
    Contrast = c2$contrast, Model = c2$model,
    `N (deaths)` = sprintf("%d (%d)", c2$n, c2$deaths),
    `HR (95% CI)` = c2$`HR (95% CI)`, P = fmt_p(c2$P),
    check.names = FALSE, stringsAsFactors = FALSE
  ) else data.frame(Contrast = character(), Model = character(), check.names = FALSE)
  # 两段写进一个表：先切点，再 Cox
  body <- if (nrow(body2)) {
    rbind(
      data.frame(Section = "RCS cutoff", A = body1[[1]], B = as.character(body1[[2]]), C = as.character(body1[[3]]), D = "", E = "",
                 check.names = FALSE, stringsAsFactors = FALSE),
      data.frame(Section = "Binary Cox", A = body2$Contrast, B = body2$Model, C = body2$`N (deaths)`,
                 D = body2$`HR (95% CI)`, E = body2$P, check.names = FALSE, stringsAsFactors = FALSE)
    )
  } else {
    data.frame(Section = "RCS cutoff", A = body1[[1]], B = as.character(body1[[2]]), C = as.character(body1[[3]]),
               D = "", E = "", check.names = FALSE, stringsAsFactors = FALSE)
  }
  names(body) <- c("Section", "Item", "Value1", "Value2", "Value3", "Value4")[seq_len(ncol(body))]
  # 更干净：两个单表合并用双块手写
  p <- file.path(tab_dir, sprintf("Table S10-%s. RCS cutoff and binary Cox.xlsx", nm))
  cut_body <- data.frame(
    Model = c1$model,
    `Minimum-risk sleep, h` = sprintf("%.3f", c1$min_risk_hours),
    `Nearest HR=1 sleep, h` = ifelse(is.na(c1$nearest_HR1_hours), "—", sprintf("%.3f", c1$nearest_HR1_hours)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  cox_body <- if (nrow(c2)) data.frame(
    Contrast = c2$contrast, Model = c2$model,
    `N (deaths)` = sprintf("%d (%d)", c2$n, c2$deaths),
    `HR (95% CI)` = c2$`HR (95% CI)`, P = fmt_p(c2$P),
    check.names = FALSE, stringsAsFactors = FALSE
  ) else cut_body[0, , drop = FALSE]
  # 写 Cox 为主表；切点放脚注数字 + 另写 cutoff 行在表顶
  top <- data.frame(
    Contrast = "RCS minimum-risk cutoffs (Model 1 / Model 3)",
    Model = "",
    `N (deaths)` = "",
    `HR (95% CI)` = paste(sprintf("%s: %.3f h", c1$model, c1$min_risk_hours), collapse = "; "),
    P = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    p, title = "Table S10. RCS-derived sleep cutoffs and binary Cox models",
    df_body = rbind(top, cox_body),
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Minimum-risk hour is the sleep duration with the lowest HR on the spline grid (reference 7.5 h).",
      "Binary Cox compares sleep below versus at/above the Model 3 minimum-risk hour.",
      "This binary extreme-short-sleep contrast supplements the main five-level grouping (<5 / 5-6 / 6-7 / 7-8 / >=9 h).",
      paste0("Model 3 covariates: ", paste(m3_cov, collapse = ", "), ".")
    )
  )
}
message("S10 done")

# ---------- S11: 5y / 10y prediction (NHANES, SHHS) ----------
horizons <- c(2, 5, 10)
roc_rows <- list()
for (nm in pv2_primary_dbs) {
  d <- as.data.frame(dbs[[nm]])
  for (h in horizons) {
    if (max(d$futime_years, na.rm = TRUE) < h) next
    y <- as.integer(d$fustatus == 1 & d$futime_years <= h)
    ok <- stats::complete.cases(d[, c("Sleep_hours", "Age", "Gender")]) & !is.na(y)
    if (length(unique(y[ok])) < 2) next
    dd <- d[ok, ]
    dd$y <- y[ok]
    dd$Gender <- factor(dd$Gender)
    w <- if (nm == "NHANES") dd$survey_weight else NULL
    fit <- stats::glm(y ~ Sleep_hours + Age + Gender, data = dd, family = stats::binomial())
    pr <- stats::predict(fit, type = "response")
    roc <- pROC::roc(dd$y, pr, weights = w, quiet = TRUE, direction = "<")
    cd <- pROC::coords(roc, ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE)
    best <- which.max(cd$sensitivity + cd$specificity - 1)
    roc_rows[[length(roc_rows) + 1L]] <- data.frame(
      database = nm, role = "Primary", horizon_years = h,
      n = nrow(dd), events = sum(dd$y == 1),
      AUC = round(as.numeric(pROC::auc(roc)), 3),
      cutoff_prob = round(cd$threshold[best], 3),
      sensitivity = round(cd$sensitivity[best], 3),
      specificity = round(cd$specificity[best], 3),
      stringsAsFactors = FALSE
    )
  }
}
s11 <- do.call(rbind, roc_rows)
data.table::fwrite(s11, file.path(ckpt, "Table S11. Prediction 2_5_10y.csv"))
for (nm in unique(s11$database)) {
  sub <- s11[s11$database == nm, ]
  body <- data.frame(
    Horizon = paste0(sub$horizon_years, "-year"),
    `N (events)` = sprintf("%d (%d)", sub$n, sub$events),
    AUC = sprintf("%.3f", sub$AUC),
    `Youden probability cutoff` = sprintf("%.3f", sub$cutoff_prob),
    Sensitivity = sprintf("%.3f", sub$sensitivity),
    Specificity = sprintf("%.3f", sub$specificity),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S11-%s. Prediction of all-cause mortality at 2, 5 and 10 years.xlsx", nm)),
    title = "Table S11. Predictive performance for all-cause mortality at 2, 5 and 10 years",
    df_body = body,
    footnotes = c(
      "Primary cohorts only (NHANES, SHHS). CHARLS maximum follow-up is about 2.63 years and is not included.",
      "Model: logistic regression of death by horizon ~ sleep hours + age + sex.",
      "The Youden cutoff is on the predicted probability, not on sleep hours.",
      "NHANES AUC uses survey weights in the ROC."
    )
  )
}
# 简单拼图：三时点 AUC 条（可选 PDF）
if (nrow(s11)) {
  p <- ggplot2::ggplot(s11, ggplot2::aes(factor(horizon_years), AUC, fill = database)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.7), width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", AUC)),
                       position = ggplot2::position_dodge(width = 0.7), vjust = -0.3, size = 3) +
    ggplot2::coord_cartesian(ylim = c(0.5, 1)) +
    ggplot2::labs(x = "Horizon, years", y = "AUC", fill = NULL,
                  title = "Prediction AUC for all-cause mortality by horizon") +
    ggplot2::theme_bw(base_size = 11)
  ggplot2::ggsave(file.path(fig_dir, "Figure S1. Prediction AUC at 2 5 and 10 years.pdf"),
                  p, width = 7.2, height = 4.2, device = grDevices::cairo_pdf)
}
message("S11 done")

# ---------- S12–S14: 465 min = 7.75 h ----------
cut465 <- 465 / 60
s12 <- list(); s13 <- list(); s14 <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$sleep_lt465 <- factor(ifelse(d$Sleep_hours < cut465, "<7.75h", ">=7.75h"),
                          levels = c(">=7.75h", "<7.75h"))
  r <- row_models(d, nm, "sleep_lt465", "sleep_lt465<7.75h", "<7.75 h (465 min) vs >=7.75 h")
  if (!is.null(r)) s12[[length(s12) + 1L]] <- r

  # PAR (Levin) using Model 3 HR and exposure prevalence
  m3r <- if (!is.null(r)) r[r$model == "Model3", ][1, ] else NULL
  if (!is.null(m3r) && is.finite(m3r$HR)) {
    dd <- d[stats::complete.cases(d[, c("Sleep_hours", "fustatus", m3_cov)]) & d$futime_years > 0, ]
    if (nm == "NHANES" && "survey_weight" %in% names(dd)) {
      p_exp <- sum(dd$survey_weight[dd$Sleep_hours < cut465], na.rm = TRUE) /
        sum(dd$survey_weight, na.rm = TRUE)
    } else {
      p_exp <- mean(dd$Sleep_hours < cut465, na.rm = TRUE)
    }
    rr <- m3r$HR
    par <- (p_exp * (rr - 1)) / (1 + p_exp * (rr - 1))
    s12[[length(s12)]] <- cbind(s12[[length(s12)]], data.frame(
      expos_prev = round(p_exp, 4), PAR = round(par, 4), stringsAsFactors = FALSE
    ))
  }

  # Diagnostic: sleep <7.75 alone vs death (ever)
  y <- as.integer(d$fustatus == 1)
  x <- as.integer(d$Sleep_hours < cut465)
  ok <- !is.na(y) & !is.na(x)
  tab <- table(pred = x[ok], truth = y[ok])
  # ensure 2x2
  tp <- if (all(c("1", "1") %in% dimnames(tab))) sum(x[ok] == 1 & y[ok] == 1) else sum(x[ok] == 1 & y[ok] == 1)
  tn <- sum(x[ok] == 0 & y[ok] == 0)
  fp <- sum(x[ok] == 1 & y[ok] == 0)
  fn <- sum(x[ok] == 0 & y[ok] == 1)
  sens <- tp / (tp + fn)
  spec <- tn / (tn + fp)
  auc_one <- tryCatch(as.numeric(pROC::auc(pROC::roc(y[ok], x[ok], quiet = TRUE, direction = "<"))), error = function(e) NA_real_)
  # incremental detection: deaths with short sleep beyond age>=60 or HTN
  hi_age <- d$Age >= 60
  hi_htn <- as.character(d$Hypertension) %in% c("Yes", "1")
  base_flag <- hi_age | hi_htn
  short <- d$Sleep_hours < cut465
  deaths <- d$fustatus == 1
  n_death <- sum(deaths, na.rm = TRUE)
  caught_base <- sum(deaths & base_flag, na.rm = TRUE)
  caught_extra <- sum(deaths & short & !base_flag, na.rm = TRUE)
  s13[[length(s13) + 1L]] <- data.frame(
    database = nm, role = pv2_role_label(nm),
    sens = round(sens, 3), spec = round(spec, 3), AUC = round(auc_one, 3),
    deaths = n_death, caught_by_age60_or_HTN = caught_base,
    extra_deaths_by_short_sleep = caught_extra,
    extra_rate_among_deaths = round(caught_extra / n_death, 4),
    stringsAsFactors = FALSE
  )

  # Joint stratification
  d$Age_Group <- ifelse(d$Age < 60, "<60", ">=60")
  for (by in c("Age_Group", "Hypertension")) {
    for (lv in unique(as.character(d[[by]]))) {
      if (is.na(lv)) next
      for (sl in c("<7.75h", ">=7.75h")) {
        sub <- d[as.character(d[[by]]) == lv & as.character(d$sleep_lt465) == sl, ]
        if (!nrow(sub)) next
        ev <- sum(sub$fustatus == 1)
        py <- sum(sub$futime_years)
        s14[[length(s14) + 1L]] <- data.frame(
          database = nm, role = pv2_role_label(nm), stratum_var = by, stratum = lv,
          sleep = sl, n = nrow(sub), deaths = ev, person_years = round(py, 2),
          rate_per_10000py = if (py > 0) round(1e4 * ev / py, 2) else NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
s12_df <- do.call(rbind, s12)
s13_df <- do.call(rbind, s13)
s14_df <- do.call(rbind, s14)
data.table::fwrite(s12_df, file.path(ckpt, "Table S12. Sleep 465min Cox PAR.csv"))
data.table::fwrite(s13_df, file.path(ckpt, "Table S13. Sleep 465min diagnostic.csv"))
data.table::fwrite(s14_df, file.path(ckpt, "Table S14. Sleep 465min joint strata.csv"))

for (nm in unique(s12_df$database)) {
  sub <- s12_df[s12_df$database == nm, ]
  body <- data.frame(
    Model = sub$model,
    `N (deaths)` = sprintf("%d (%d)", sub$n, sub$deaths),
    `HR (95% CI)` = sub$`HR (95% CI)`,
    P = fmt_p(sub$P),
    `Exposure prevalence` = if ("expos_prev" %in% names(sub)) ifelse(sub$model == "Model3", sprintf("%.1f%%", 100 * sub$expos_prev), "") else "",
    PAR = if ("PAR" %in% names(sub)) ifelse(sub$model == "Model3" & is.finite(sub$PAR), sprintf("%.1f%%", 100 * sub$PAR), "") else "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S12-%s. Sleep below 465 min and mortality with PAR.xlsx", nm)),
    title = "Table S12. Sleep duration <465 minutes (7.75 h) and all-cause mortality, with population attributable risk",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Exposure: sleep duration <7.75 h (465 minutes) versus >=7.75 h.",
      "PAR uses Levin formula with Model 3 HR and the exposure prevalence (survey-weighted in NHANES).",
      "PAR is model-based and should not be read as a causal population fraction.",
      paste0("Model 3 covariates: ", paste(m3_cov, collapse = ", "), ".")
    )
  )
}
for (nm in unique(s13_df$database)) {
  sub <- s13_df[s13_df$database == nm, ][1, ]
  body <- data.frame(
    Metric = c("Sensitivity of sleep <7.75 h for death", "Specificity", "AUC (sleep alone)",
               "Deaths", "Deaths flagged by age>=60 or hypertension",
               "Additional deaths flagged only by sleep <7.75 h",
               "Extra detection among deaths"),
    Value = c(sprintf("%.3f", sub$sens), sprintf("%.3f", sub$spec), sprintf("%.3f", sub$AUC),
              as.character(sub$deaths), as.character(sub$caught_by_age60_or_HTN),
              as.character(sub$extra_deaths_by_short_sleep),
              sprintf("%.1f%%", 100 * sub$extra_rate_among_deaths)),
    stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S13-%s. Diagnostic yield of sleep below 465 min.xlsx", nm)),
    title = "Table S13. Diagnostic performance and incremental detection of sleep <465 minutes",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Binary classifier: sleep <7.75 h versus not, for observed all-cause death (not a clinical screening claim).",
      "Incremental detection counts deaths with short sleep who were not already flagged by age >=60 or hypertension."
    )
  )
}
for (nm in unique(s14_df$database)) {
  sub <- s14_df[s14_df$database == nm, ]
  body <- data.frame(
    Stratum = paste(sub$stratum_var, sub$stratum, sep = "="),
    Sleep = sub$sleep,
    N = sub$n, Deaths = sub$deaths,
    `Person-years` = sub$person_years,
    `Rate / 10,000 py` = sub$rate_per_10000py,
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S14-%s. Joint stratification by sleep 465 min.xlsx", nm)),
    title = "Table S14. Joint stratification of sleep <465 minutes with age and hypertension",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Sleep groups: <7.75 h versus >=7.75 h (465 minutes).",
      "Rates are crude events per 10,000 person-years."
    )
  )
}
message("S12-S14 done")
message("extension complete")
