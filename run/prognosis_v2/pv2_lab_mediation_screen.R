# 血检中介筛查。Cox 系数乘积，中介按 1 SD。
# AgeSex = 年龄+性别；Model3 = 年龄+性别+SBP+教育+高血压+饮酒+吸烟+BMI。
# 中介若与协变量同名则从协变量中去掉。不插补血检。

suppressPackageStartupMessages(library(survival))

data_root <- "G:/02block_result/49_Dyslipidemia/prognosis_41904528/data"
out_root <- "G:/02block_result/49_Dyslipidemia/prognosis_v2_41904528/summary_results"
num <- function(x) suppressWarnings(as.numeric(x))

dbs <- readRDS(file.path(out_root, "Tables/imputed_dbs.rds"))
ids <- lapply(dbs, function(d) as.character(d$ID))

message("读取基线血检")
e <- new.env()
load(file.path(data_root, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
nh <- as.data.frame(e$baseline)
nh$ID <- as.character(nh$ID)
nh_labs <- c("Glucose", "HbA1c", "TG", "TC", "HDL", "LDL", "Creatinine", "UricAcid",
             "UreaNitrogen", "WBC", "Hemoglobin", "PlateletCount", "CRP", "HSCRP", "ALT", "AST")
nh <- nh[nh$ID %in% ids$NHANES, c("ID", intersect(nh_labs, names(nh)))]

cenv <- new.env()
load(file.path(data_root, "CHARLS/最终数据/D01_baseline_2011_DN.RData"), envir = cenv)
ch <- as.data.frame(cenv$baseline)
ch$ID <- as.character(ch$ID)
ch_labs <- c("Glucose", "HbA1c", "TG", "TC", "HDL", "LDL", "Creatinine", "UricAcid",
             "UreaNitrogen", "WBC", "Hemoglobin", "PlateletCount", "CRP")
ch <- ch[ch$ID %in% ids$CHARLS, c("ID", intersect(ch_labs, names(ch)))]

s1 <- data.table::fread(
  file.path(data_root, "SHHS(1)/EXCEL/shhs1-dataset-0.18.0.csv"),
  select = c("nsrrid", "chol", "hdl", "trig")
)
sh <- data.frame(
  ID = as.character(s1$nsrrid),
  TC = num(s1$chol), HDL = num(s1$hdl), TG = num(s1$trig),
  stringsAsFactors = FALSE
)
sh$LDL <- ifelse(!is.na(sh$TG) & sh$TG < 400 & !is.na(sh$TC) & !is.na(sh$HDL),
                 sh$TC - sh$HDL - sh$TG / 5, NA_real_)
sh <- sh[sh$ID %in% ids$SHHS, ]

labs <- list(NHANES = nh, CHARLS = ch, SHHS = sh)
base_cov <- c("Age", "Gender", "SBP", "Education", "Hypertension", "Alcohol", "Smoke", "BMI")

one <- function(d, med, covars) {
  need <- c("time", "event", "Sleep_hours", med, covars)
  dd <- d[stats::complete.cases(d[, need]) & d$time > 0, need]
  if (nrow(dd) < 200 || sum(dd$event == 1) < 15) {
    return(data.frame(n = nrow(dd), events = sum(dd$event == 1), stringsAsFactors = FALSE))
  }
  dd$.M <- as.numeric(scale(dd[[med]]))
  fa <- stats::as.formula(paste(".M ~ Sleep_hours +", paste(covars, collapse = " + ")))
  ff <- stats::as.formula(paste("survival::Surv(time, event) ~ Sleep_hours + .M +", paste(covars, collapse = " + ")))
  ft <- stats::as.formula(paste("survival::Surv(time, event) ~ Sleep_hours +", paste(covars, collapse = " + ")))
  ma <- stats::lm(fa, data = dd)
  mf <- survival::coxph(ff, data = dd)
  mt <- survival::coxph(ft, data = dd)
  ca <- stats::coef(ma)[["Sleep_hours"]]
  pa <- summary(ma)$coefficients["Sleep_hours", "Pr(>|t|)"]
  cb <- stats::coef(mf)[[".M"]]
  pb <- summary(mf)$coefficients[".M", "Pr(>|z|)"]
  cc <- stats::coef(mt)[["Sleep_hours"]]
  cprime <- stats::coef(mf)[["Sleep_hours"]]
  prop <- if (is.finite(cc) && abs(cc) > 1e-8) (ca * cb) / cc else NA_real_
  data.frame(
    n = nrow(dd), events = sum(dd$event == 1),
    path_a = ca, path_a_p = pa, path_b = cb, path_b_p = pb,
    total_HR = exp(cc), direct_HR = exp(cprime), prop_pct = 100 * prop,
    stringsAsFactors = FALSE
  )
}

rows <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$ID <- as.character(d$ID)
  d$time <- d$futime_years
  d$event <- d$fustatus
  d$Gender <- factor(d$Gender)
  d$Education <- factor(d$Education)
  d$Hypertension <- factor(d$Hypertension)
  d$Alcohol <- factor(d$Alcohol)
  d$Smoke <- factor(d$Smoke)
  lab <- labs[[nm]]
  lab$ID <- as.character(lab$ID)
  d <- merge(d, lab, by = "ID", all.x = TRUE)
  meds <- setdiff(intersect(names(lab), names(d)), "ID")
  for (med in meds) {
    d[[med]] <- num(d[[med]])
    miss <- mean(is.na(d[[med]]))
    for (spec in c("AgeSex", "Model3")) {
      covars <- if (spec == "AgeSex") c("Age", "Gender") else base_cov
      covars <- setdiff(covars, med)
      r <- tryCatch(one(d, med, covars), error = function(e) {
        data.frame(n = NA, events = NA, path_a = NA, path_a_p = NA, path_b = NA, path_b_p = NA,
                   total_HR = NA, direct_HR = NA, prop_pct = NA, err = conditionMessage(e),
                   stringsAsFactors = FALSE)
      })
      rows[[length(rows) + 1L]] <- data.frame(
        database = nm, mediator = med, adjust = spec, missing = round(miss, 3),
        r, stringsAsFactors = FALSE
      )
      if (!is.null(r$path_a_p) && is.finite(r$path_a_p)) {
        message(sprintf("%s %s %s  n=%d a=%.4f p=%.3g  b p=%.3g  prop=%.1f%%",
                        nm, med, spec, r$n, r$path_a, r$path_a_p, r$path_b_p, r$prop_pct))
      } else {
        message(sprintf("%s %s %s  skip", nm, med, spec))
      }
    }
  }
}

tab <- do.call(rbind, rows)
data.table::fwrite(tab, file.path(out_root, "Tables/Table mediation lab screen.csv"))
message("wrote screen")
