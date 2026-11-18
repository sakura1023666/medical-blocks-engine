# Table S5：敏感性分析。排除基线后第 1 年内死亡的人，再拟合与 Table 3 相同的全因 Cox。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(survey)
})
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"))
options(survey.lonely.psu = "adjust")

tab_dir <- "G:/02block_result/49_Dyslipidemia/prognosis_v2_41904528/summary_results/Tables"
dbs <- readRDS(if (exists("pv2_artifact", mode = "function")) pv2_artifact("imputed_dbs.rds") else file.path(tab_dir, "imputed_dbs.rds"))

fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
cox_extract <- function(d, rhs) {
  d$time <- d$futime_years
  d$event <- as.integer(d$fustatus)
  weighted <- isTRUE(d$database[1] == "NHANES") && any(!is.na(d$survey_weight))
  if (weighted) {
    d <- d[!is.na(d$survey_weight) & d$survey_weight > 0 & !is.na(d$psu) & !is.na(d$strata), ]
    des <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = d, nest = TRUE)
    fit <- survey::svycoxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), design = des)
    sm <- summary(fit)
    co <- sm$coefficients
    ci <- sm$conf.int
    pcol <- intersect(c("Pr(>|z|)", "p"), colnames(co))[1]
    data.frame(term = rownames(co), hr = ci[, 1], lo = ci[, 3], hi = ci[, 4],
               p = co[, pcol], stringsAsFactors = FALSE)
  } else {
    fit <- survival::coxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), data = d, ties = "efron")
    s <- summary(fit)
    data.frame(term = rownames(s$conf.int), hr = s$conf.int[, 1], lo = s$conf.int[, 3],
               hi = s$conf.int[, 4], p = s$coefficients[, "Pr(>|z|)"], stringsAsFactors = FALSE)
  }
}
one_term <- function(fit, key) {
  i <- grep(key, fit$term, fixed = TRUE)
  if (!length(i)) return(NULL)
  fit[i[1], , drop = FALSE]
}
hr_txt <- function(row) {
  if (is.null(row)) return("")
  sprintf("%.3f (%.3f–%.3f)", row$hr, row$lo, row$hi)
}

m3_cov <- c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI")
h1 <- c("", "", "Model 1", "Model 1", "Model 2", "Model 2", "Model 3", "Model 3")
h2 <- c("Variable", "N (%)", "HR (95% CI)", "P", "HR (95% CI)", "P", "HR (95% CI)", "P")
model_fn <- c(
  "The Model 1 was non-adjusted.",
  "The Model 2 was adjusted by: Age, Gender.",
  "The Model 3 was adjusted by: Age, Gender, SBP, Education, Hypertension, Alcohol, Smoke, BMI."
)

for (nm in c("NHANES", "CHARLS", "SHHS")) {
  d0 <- as.data.frame(dbs[[nm]])
  d0$database <- nm
  early <- !is.na(d0$fustatus) & d0$fustatus == 1 & !is.na(d0$futime_years) & d0$futime_years < 1
  d <- d0[!early, ]
  d$Sleep_Group <- factor(as.character(d$Sleep_Group), levels = c("7-8", "<7", ">=9"))
  need <- c("futime_years", "fustatus", "Sleep_hours", "Sleep_Group", m3_cov)
  d <- d[stats::complete.cases(d[, need]), ]
  d <- d[!is.na(d$futime_years) & d$futime_years > 0, ]
  n_all <- nrow(d)
  n_death <- sum(d$fustatus == 1)
  message(sprintf("%s excluded early deaths=%d remaining n=%d deaths=%d", nm, sum(early), n_all, n_death))
  d$sleep_sd <- as.numeric(scale(d$Sleep_hours))
  d$sleep_ord <- match(as.character(d$Sleep_Group), c("<7", "7-8", ">=9"))
  specs <- list(
    Model1 = list(sd = "sleep_sd", grp = "Sleep_Group", ord = "sleep_ord"),
    Model2 = list(sd = "sleep_sd + Age + Gender", grp = "Sleep_Group + Age + Gender",
                  ord = "sleep_ord + Age + Gender"),
    Model3 = list(
      sd = paste(c("sleep_sd", m3_cov), collapse = " + "),
      grp = paste(c("Sleep_Group", m3_cov), collapse = " + "),
      ord = paste(c("sleep_ord", m3_cov), collapse = " + ")
    )
  )
  fits <- lapply(specs, function(sp) {
    list(sd = cox_extract(d, sp$sd), grp = cox_extract(d, sp$grp), ord = cox_extract(d, sp$ord))
  })
  cell_grp <- function(md, key) {
    row <- one_term(fits[[md]]$grp, key)
    c(hr_txt(row), if (is.null(row)) "" else fmt_p(row$p))
  }
  cell_sd <- function(md) {
    row <- one_term(fits[[md]]$sd, "sleep_sd")
    c(hr_txt(row), if (is.null(row)) "" else fmt_p(row$p))
  }
  cell_ord <- function(md) {
    row <- one_term(fits[[md]]$ord, "sleep_ord")
    c("", if (is.null(row)) "" else fmt_p(row$p))
  }
  n_of <- function(g) sum(as.character(d$Sleep_Group) == g)
  row_of <- function(lab, ncell, pieces) c(lab, ncell, unlist(pieces))
  body <- rbind(
    row_of("Sleep duration", "", lapply(c("Model1", "Model2", "Model3"), function(md) c("", ""))),
    row_of("  per 1 SD", as.character(n_all), lapply(c("Model1", "Model2", "Model3"), cell_sd)),
    row_of("  7-8 h", sprintf("%d (%.2f%%)", n_of("7-8"), 100 * n_of("7-8") / n_all),
           lapply(c("Model1", "Model2", "Model3"), function(md) c("Reference", ""))),
    row_of("  <7 h", sprintf("%d (%.2f%%)", n_of("<7"), 100 * n_of("<7") / n_all),
           lapply(c("Model1", "Model2", "Model3"), function(md) cell_grp(md, "Sleep_Group<7"))),
    row_of("  >=9 h", sprintf("%d (%.2f%%)", n_of(">=9"), 100 * n_of(">=9") / n_all),
           lapply(c("Model1", "Model2", "Model3"), function(md) cell_grp(md, "Sleep_Group>=9"))),
    row_of("p for trend", "", lapply(c("Model1", "Model2", "Model3"), cell_ord))
  )
  body <- as.data.frame(body, stringsAsFactors = FALSE)
  names(body) <- paste0("c", seq_len(ncol(body)))
  if (!exists("pv2_table_xlsx_name", mode = "function")) {
    .eng <- if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final" else "/mnt/e/01block/01Block-new-Final"
    source(file.path(.eng, "R/pv2_pub_names.R"), local = FALSE)
  }
  path <- file.path(
    tab_dir,
    pv2_table_xlsx_name(
      "Table S5", "Sensitivity analysis excluding deaths within the first year",
      db = nm, single_db = pv2_is_single_db(names(dbs))
    )
  )
  ft <- c(
    "Sensitivity analysis. Participants who died within 1 year after baseline were excluded. The outcome remains all-cause death.",
    model_fn,
    if (nm == "NHANES") "NHANES models are survey-weighted (WTMEC2YR, PSU and strata)." else "Models are unweighted.",
    "per 1 SD is sleep duration standardized within the cohort. p for trend codes <7 h, 7-8 h and >=9 h as 1, 2 and 3.",
    "The primary Cox models, without this exclusion, are in Table 3."
  )
  .sci_xlsx_double_header_booktabs(
    path, title = "Table S5. Sensitivity analysis excluding deaths within the first year",
    df_body = body, h1 = h1, h2 = h2, footnotes = ft
  )
  message(basename(path))
}

old <- list.files(tab_dir, pattern = "^Table S5-.*Pre-specified sleep cutoffs.*\\.xlsx$", full.names = TRUE)
if (length(old)) {
  unlink(old)
  message("removed previous cutoff Table S5: ", length(old))
}
