# Table S3：Model 4 = Model 3 + 血脂异常项数（TG/TC/LDL/HDL）。全因死亡 Cox。

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

out_root <- "G:/02block_result/49_Dyslipidemia/prognosis_v2_41904528/summary_results"
tab_dir <- file.path(out_root, "Tables")
data_root <- "G:/02block_result/49_Dyslipidemia/prognosis_41904528/data"
dbs <- readRDS(if (exists("pv2_artifact", mode = "function")) pv2_artifact("imputed_dbs.rds") else file.path(tab_dir, "imputed_dbs.rds"))

fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
num <- function(x) suppressWarnings(as.numeric(x))
lipid_n <- function(tg, tc, ldl, hdl) {
  as.integer((!is.na(tg) & tg >= 150) + (!is.na(tc) & tc >= 200) +
               (!is.na(ldl) & ldl >= 130) + (!is.na(hdl) & hdl <= 40))
}

e <- new.env()
load(file.path(data_root, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
nh <- as.data.frame(e$baseline)
nh <- data.frame(ID = as.character(nh$ID), TG = num(nh$TG), TC = num(nh$TC),
                 LDL = num(nh$LDL), HDL = num(nh$HDL), stringsAsFactors = FALSE)

cenv <- new.env()
load(file.path(data_root, "CHARLS/最终数据/D01_baseline_2011_DN.RData"), envir = cenv)
ch <- as.data.frame(cenv$baseline)
ch <- data.frame(ID = as.character(ch$ID), TG = num(ch$TG), TC = num(ch$TC),
                 LDL = num(ch$LDL), HDL = num(ch$HDL), stringsAsFactors = FALSE)

s1 <- fread(file.path(data_root, "SHHS(1)/EXCEL/shhs1-dataset-0.18.0.csv"),
            select = c("nsrrid", "chol", "hdl", "trig"))
ldl <- ifelse(!is.na(s1$trig) & s1$trig < 400 & !is.na(s1$chol) & !is.na(s1$hdl),
              s1$chol - s1$hdl - s1$trig / 5, NA_real_)
sh <- data.frame(ID = as.character(s1$nsrrid), TG = num(s1$trig), TC = num(s1$chol),
                 LDL = ldl, HDL = num(s1$hdl), stringsAsFactors = FALSE)
lip <- list(NHANES = nh, CHARLS = ch, SHHS = sh)

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
h1 <- c("", "", "Model 4", "Model 4")
h2 <- c("Variable", "N (%)", "HR (95% CI)", "P")

for (nm in c("NHANES", "CHARLS", "SHHS")) {
  d <- as.data.frame(dbs[[nm]])
  d$ID <- as.character(d$ID)
  d$database <- nm
  extra <- lip[[nm]]
  extra$lipid_n <- lipid_n(extra$TG, extra$TC, extra$LDL, extra$HDL)
  extra <- extra[!duplicated(extra$ID), c("ID", "lipid_n")]
  d$lipid_n <- NULL
  d <- merge(d, extra, by = "ID", all.x = TRUE)
  d$Sleep_Group <- factor(as.character(d$Sleep_Group), levels = c("7-8", "<7", ">=9"))
  need <- c("futime_years", "fustatus", "Sleep_hours", "Sleep_Group", "lipid_n", m3_cov)
  d <- d[stats::complete.cases(d[, need]), ]
  d <- d[!is.na(d$futime_years) & d$futime_years > 0 & d$lipid_n >= 1, ]
  n_all <- nrow(d)
  message(nm, " n=", n_all, " lipid_n ", paste(names(table(d$lipid_n)), table(d$lipid_n), sep = ":", collapse = " "))
  d$sleep_sd <- as.numeric(scale(d$Sleep_hours))
  d$sleep_ord <- match(as.character(d$Sleep_Group), c("<7", "7-8", ">=9"))
  rhs_sd <- paste(c("sleep_sd", m3_cov, "lipid_n"), collapse = " + ")
  rhs_grp <- paste(c("Sleep_Group", m3_cov, "lipid_n"), collapse = " + ")
  rhs_ord <- paste(c("sleep_ord", m3_cov, "lipid_n"), collapse = " + ")
  fit_sd <- cox_extract(d, rhs_sd)
  fit_grp <- cox_extract(d, rhs_grp)
  fit_ord <- cox_extract(d, rhs_ord)
  cell <- function(fit, key, hr = TRUE) {
    row <- if (nzchar(key)) one_term(fit, key) else NULL
    c(if (hr) hr_txt(row) else "", if (is.null(row)) "" else fmt_p(row$p))
  }
  n_of <- function(g) sum(as.character(d$Sleep_Group) == g)
  body <- rbind(
    c("Sleep duration", "", "", ""),
    c("  per 1 SD", as.character(n_all), cell(fit_sd, "sleep_sd")),
    c("  7-8 h", sprintf("%d (%.2f%%)", n_of("7-8"), 100 * n_of("7-8") / n_all), "Reference", ""),
    c("  <7 h", sprintf("%d (%.2f%%)", n_of("<7"), 100 * n_of("<7") / n_all), cell(fit_grp, "Sleep_Group<7")),
    c("  >=9 h", sprintf("%d (%.2f%%)", n_of(">=9"), 100 * n_of(">=9") / n_all), cell(fit_grp, "Sleep_Group>=9")),
    c("p for trend", "", cell(fit_ord, "sleep_ord", hr = FALSE))
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
      "Table S3", "Cox model including dyslipidemia component count",
      db = nm, single_db = pv2_is_single_db(names(dbs))
    )
  )
  ft <- c(
    "The Model 4 was adjusted by: Age, Gender, SBP, Education, Hypertension, Alcohol, Smoke, BMI, and the number of abnormal lipid components.",
    "The component count is the number of abnormalities among triglycerides >=150 mg/dL, total cholesterol >=200 mg/dL, LDL cholesterol >=130 mg/dL and HDL cholesterol <=40 mg/dL, ranging from 1 to 4.",
    if (nm == "SHHS") "SHHS LDL cholesterol is calculated by the Friedewald equation when triglycerides are below 400 mg/dL." else NULL,
    if (nm == "NHANES") "NHANES models are survey-weighted (WTMEC2YR, PSU and strata)." else "Models are unweighted.",
    "per 1 SD is sleep duration standardized within the cohort. p for trend codes <7 h, 7-8 h and >=9 h as 1, 2 and 3.",
    "This is a sensitivity analysis. The primary Cox models are in Table 3."
  )
  .sci_xlsx_double_header_booktabs(
    path, title = "Table S3. Cox model including dyslipidemia component count (Model 4)",
    df_body = body, h1 = h1, h2 = h2, footnotes = ft
  )
  message(basename(path))
  message("  <7 ", hr_txt(one_term(fit_grp, "Sleep_Group<7")), " ", fmt_p(one_term(fit_grp, "Sleep_Group<7")$p))
  message("  >=9 ", hr_txt(one_term(fit_grp, "Sleep_Group>=9")), " ", fmt_p(one_term(fit_grp, "Sleep_Group>=9")$p))
}
