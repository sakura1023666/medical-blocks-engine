#!/usr/bin/env Rscript
# 缺血性卒中 · ANLR · 预后 v2 双库（默认 28d；可用环境变量切 7d/14d）
# Spec: docs/superpowers/specs/2026-11-05-stroke-anlr-prognosis-v2-dual-design.md
# STROKE_ANLR_DAYS=7|14|28  STROKE_ANLR_OUT=summary_results[_7d|_14d]

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(openxlsx)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

.engine <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pv2_pub_names.R"), local = FALSE)
source(file.path(.engine, "R/quantile_scheme_cascade.R"), local = FALSE)
source(file.path(.engine, "R/pv2_literature_pub_tables.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
source(file.path(.engine, "R/attrition_log.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/stroke_anlr_env.R"), local = FALSE)

# CLI: --days 7 --out summary_results_7d
.args <- commandArgs(trailingOnly = TRUE)
if ("--days" %in% .args) {
  .di <- which(.args == "--days")[1L]
  if (.di < length(.args)) Sys.setenv(STROKE_ANLR_DAYS = .args[[.di + 1L]])
}
if ("--out" %in% .args) {
  .oi <- which(.args == "--out")[1L]
  if (.oi < length(.args)) Sys.setenv(STROKE_ANLR_OUT = .args[[.oi + 1L]])
}

.proj <- stroke_anlr_proj()
.days <- stroke_anlr_days()
.day_lab <- stroke_anlr_day_lab()
.endpoint <- stroke_anlr_endpoint_phrase()
.data_root <- file.path(.proj, "data")
.out_root <- stroke_anlr_out(.proj)
tab_dir <- file.path(.out_root, "Tables")
fig_dir <- file.path(.out_root, "Figures", "pdf")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
message("Landmark days=", .days, "  out=", .out_root)

pool <- jsonlite::fromJSON(file.path(.data_root, "shared_feature_pool.json"))
IDX <- "ANLR"
indices <- IDX

num <- function(x) suppressWarnings(as.numeric(x))
yn <- function(x) {
  xc <- trimws(as.character(x))
  ifelse(is.na(x) | xc %in% c("", "NA"), NA_character_,
         ifelse(xc %in% c("Yes", "Y", "1", "TRUE", "True"), "Yes",
                ifelse(xc %in% c("No", "N", "0", "FALSE", "False"), "No", xc)))
}
fmt_p <- function(p) ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
hr_cell <- function(hr, lo, hi) {
  ifelse(!is.finite(hr) | !is.finite(lo) | !is.finite(hi), "",
         sprintf("%.3f (%.3f-%.3f)", hr, lo, hi))
}
med_iqr <- function(x) {
  x <- num(x); q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f-%.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f)", k, ifelse(n > 0, 100 * k / n, NA_real_))

write_sci_xlsx <- function(df, path, title, footnotes = character(0)) {
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    sci_xlsx_single_header_booktabs(path, title = title, df_body = df, footnotes = footnotes)
  } else {
    wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
    writeData(wb, 1, title, startRow = 1); writeData(wb, 1, df, startRow = 3)
    if (length(footnotes)) {
      r0 <- 3L + nrow(df) + 2L
      for (i in seq_along(footnotes)) writeData(wb, 1, footnotes[i], startRow = r0 + i - 1L)
    }
    saveWorkbook(wb, path, overwrite = TRUE)
  }
}

load_d02 <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(.data_root, db, "D02_rt_Stroke_surv28.RData"), envir = e)
  as.data.frame(e$rt)
}

attach_hosp <- function(d, db) {
  if (identical(db, "mimic")) {
    csv <- file.path(.data_root, "mimic", "mimic预后数据-all.csv")
    h <- fread(csv, select = c(
      "subject_id", "is_dead", "hosp_survival_day", "is_hosp_dead", "hosp_day"
    ))
    h[, subject_id := as.character(subject_id)]
    d$subject_id <- as.character(d$subject_id %||% d$ID)
    m <- match(d$subject_id, h$subject_id)
    d$is_dead <- as.integer(h$is_dead[m])
    d$fu_surv_day <- num(h$hosp_survival_day[m])
    d$hosp_dead <- as.integer(h$is_hosp_dead[m])
    d$hosp_futime <- num(h$hosp_day[m])
  } else {
    csv <- file.path(.data_root, "eicu", "EICU预后数据-all.csv")
    h <- fread(csv, select = c("patientunitstayid", "hospdischargestatus", "hosplosday"))
    h[, pid := as.character(patientunitstayid)]
    d$ID <- as.character(d$ID)
    m <- match(d$ID, h$pid)
    st <- as.character(h$hospdischargestatus[m])
    d$hosp_dead <- ifelse(is.na(st), NA_integer_, as.integer(tolower(st) == "expired"))
    d$hosp_futime <- pmax(num(h$hosplosday[m]), 0.01)
    d$is_dead <- d$hosp_dead
    d$fu_surv_day <- d$hosp_futime
  }
  d$hosp_futime[!is.finite(d$hosp_futime) | d$hosp_futime <= 0] <- NA_real_
  d
}

# 主结局：按 landmark 天构建
# MIMIC：is_dead + hosp_survival_day（无死亡记录 → 行政删失至 L）；L=28 时与 D02 一致
# eICU：院内 Expired + hosplosday，Alive 提前出院在出院日删失（与 D02 28d 同源规则）
assign_landmark_outcome <- function(d, db_folder, L) {
  L <- as.numeric(L)
  if (identical(db_folder, "mimic")) {
    if (identical(as.integer(L), 28L) &&
        "survival_time_28d" %in% names(d) && "Mortality_28d" %in% names(d)) {
      d$futime <- num(d$survival_time_28d)
      d$fustatus <- as.integer(d$Mortality_28d)
    } else {
      n <- nrow(d)
      t <- rep(NA_real_, n)
      ev <- rep(NA_integer_, n)
      dead_ok <- !is.na(d$is_dead) & d$is_dead == 1L &
        is.finite(d$fu_surv_day) & d$fu_surv_day > 0
      t[dead_ok] <- pmin(d$fu_surv_day[dead_ok], L)
      ev[dead_ok] <- as.integer(d$fu_surv_day[dead_ok] <= L)
      alive <- is.na(d$is_dead)
      t[alive] <- L
      ev[alive] <- 0L
      d$futime <- t
      d$fustatus <- ev
    }
  } else {
    # eICU：始终用预后表院内规则（含 L=28，与 D02 逐人一致）
    los <- num(d$hosp_futime)
    dead <- as.integer(d$hosp_dead == 1L)
    d$futime <- pmin(pmax(los, 0.01), L)
    d$fustatus <- as.integer(dead == 1L & is.finite(los) & los <= L)
    d$fustatus[dead == 1L & is.finite(los) & los > L] <- 0L
    d$fustatus[dead == 0L] <- 0L
  }
  d
}

prepare_one <- function(db_label, db_folder) {
  raw0 <- load_d02(db_folder)
  n0 <- nrow(raw0)
  raw0$Age <- num(raw0$Age)
  raw0$Gender <- ifelse(as.character(raw0$Gender) %in% c("Male", "M", "1"), "Male",
                        ifelse(as.character(raw0$Gender) %in% c("Female", "F", "2"), "Female", NA_character_))
  raw0$Neutrophil_Count <- num(raw0$NeutrophilCount)
  raw0$Lymphocytes <- num(raw0$Lymphocytes)
  raw0$Albumin <- num(raw0$Albumin)
  raw0$ANLR <- raw0$Albumin / (raw0$Neutrophil_Count / raw0$Lymphocytes)
  raw0$ID <- as.character(raw0$ID %||% raw0$subject_id)
  raw0$database <- db_label
  raw0 <- attach_hosp(raw0, db_folder)
  raw0 <- assign_landmark_outcome(raw0, db_folder, .days)

  n_age <- sum(is.finite(raw0$Age) & raw0$Age >= 18)
  ok_idx <- is.finite(raw0$ANLR) & raw0$ANLR > 0
  n_idx <- sum(is.finite(raw0$Age) & raw0$Age >= 18 & ok_idx)
  ok <- is.finite(raw0$Age) & raw0$Age >= 18 & ok_idx &
    is.finite(raw0$futime) & raw0$futime > 0 & !is.na(raw0$fustatus)
  d <- raw0[ok, , drop = FALSE]
  d$futime_years <- d$futime / 365.25

  # shared covariates only
  cov_pool <- intersect(pool$covariate_pool, names(d))
  for (v in cov_pool) {
    if (v %in% c("Ventilation", "Hypertension", "Diabetes", "Heart_Failure",
                 "Myocardial_Infarction", "Malignant_Tumor", "CKD", "Pneumonia",
                 "COPD", "Hyperlipidemia", "Liver_cirrhosis", "Hepatitis")) {
      d[[v]] <- yn(d[[v]])
    } else if (!v %in% c("Gender", "Race")) {
      d[[v]] <- num(d[[v]])
    }
  }
  if ("SOFA" %in% names(d)) d$SOFA <- num(d$SOFA)
  if ("OASIS" %in% names(d)) d$OASIS <- num(d$OASIS)
  if ("APSIII" %in% names(d)) d$APSIII <- num(d$APSIII)
  if ("GCS" %in% names(d)) d$GCS <- num(d$GCS)

  miss <- vapply(cov_pool, function(v) mean(is.na(d[[v]])), numeric(1))
  drop40 <- names(miss)[miss > as.numeric(pool$drop_if_miss_gt %||% 0.4)]
  cov_use <- setdiff(cov_pool, drop40)

  attr <- data.frame(
    database = db_label,
    step = c(
      "Ischemic stroke ICU cohort (D02)",
      "Age >= 18 years",
      "ANLR computable (albumin, neutrophil, lymphocyte)",
      sprintf("%s follow-up and vital status available", .day_lab)
    ),
    n_remain = c(n0, n_age, n_idx, nrow(d)),
    stringsAsFactors = FALSE
  )
  list(data = d, cov_use = cov_use, attrition = attr, n0 = n0, drop40 = drop40)
}

message("==== Stroke ANLR prognosis_v2 dual ====")
prep <- list(
  MIMIC = prepare_one("MIMIC", "mimic"),
  eICU = prepare_one("eICU", "eicu")
)

# lock shared cov intersection after drop40
cov_shared <- Reduce(intersect, lapply(prep, `[[`, "cov_use"))
message("共享协变量: ", paste(cov_shared, collapse = ", "))

attr_all <- rbind(prep$MIMIC$attrition, prep$eICU$attrition)
fwrite(attr_all, file.path(tab_dir, "Flowchart_attrition.csv"))
for (nm in names(prep)) {
  saveRDS(prep[[nm]]$data, file.path(.data_root, sprintf("analysis_ready_ANLR_%sd_%s.rds", .days, tolower(nm))))
  fwrite(prep[[nm]]$attrition, file.path(tab_dir, sprintf("Flowchart_attrition_%s.csv", nm)))
}

# ---- Fig1 dual ----
.panels <- lapply(names(prep), function(nm) {
  a <- prep[[nm]]$attrition
  d <- prep[[nm]]$data
  n_top <- as.integer(a$n_remain[1]); n_age <- as.integer(a$n_remain[2])
  n_idx <- as.integer(a$n_remain[3]); n_inc <- as.integer(a$n_remain[4])
  n_death <- sum(d$fustatus == 1L); n_alive <- n_inc - n_death
  list(
    letter = paste0(if (nm == "MIMIC") "A  " else "B  ", nm),
    top = sprintf("Ischemic stroke\nin %s\n(n = %s)", nm, format(n_top, big.mark = ",")),
    mid = sprintf("Aged >= 18 years\n(n = %s)", format(n_age, big.mark = ",")),
    inc = sprintf("Participants included\n(n = %s)", format(n_inc, big.mark = ",")),
    side1 = sprintf("Age < 18 years or\nmissing age (n = %s)", format(n_top - n_age, big.mark = ",")),
    side2 = paste0(
      sprintf("1. ANLR not computable\n(n = %s)\n", format(n_age - n_idx, big.mark = ",")),
      sprintf("2. Missing %s follow-up\nor invalid status (n = %s)", .day_lab, format(n_idx - n_inc, big.mark = ","))
    ),
    death = sprintf("%s all-cause death\n(n = %s)", .day_lab, format(n_death, big.mark = ",")),
    alive = sprintf("Alive at %d days\n(n = %s)", .days, format(n_alive, big.mark = ","))
  )
})
tryCatch({
  attrition_draw_outcome_figure(
    file.path(fig_dir, "Figure 1. Flow diagram of adults with ischemic stroke.pdf"),
    .panels, width = 10.5, height = 6.35, family = "Times",
    csv_path = file.path(tab_dir, "Flowchart_attrition.csv")
  )
}, error = function(e) message("Fig1 warn: ", conditionMessage(e)))

# ---- MICE per DB ----
.impute_one <- function(d, cov_use, seed = 1234L, m = 5L, maxit = 5L) {
  keep <- unique(c("ID", "database", "Age", "Gender", "Race", cov_use, IDX, "SOFA",
                   "futime", "futime_years", "fustatus", "hosp_dead", "hosp_futime"))
  keep <- keep[keep %in% names(d)]
  d0 <- d[, keep, drop = FALSE]
  covs <- setdiff(names(d0), c("ID", "database", IDX, "futime", "futime_years", "fustatus",
                               "hosp_dead", "hosp_futime"))
  miss <- vapply(covs, function(v) mean(is.na(d0[[v]])), numeric(1))
  drop <- names(miss)[is.finite(miss) & miss > 0.4]
  use <- setdiff(covs, drop)
  if (!length(use) || !any(vapply(use, function(v) anyNA(d0[[v]]), logical(1)))) {
    return(list(data = d0, miss = miss, dropped = drop, mids = NULL))
  }
  dat <- d0[, use, drop = FALSE]
  for (v in use) if (is.character(dat[[v]]) || is.logical(dat[[v]])) dat[[v]] <- factor(dat[[v]])
  aux <- c("fustatus", IDX)
  aux <- aux[aux %in% names(d0)]
  for (v in aux) dat[[v]] <- d0[[v]]
  ini <- mice::mice(dat, maxit = 0, printFlag = FALSE)
  meth <- ini$method; pred <- ini$predictorMatrix
  meth[aux] <- ""; for (v in aux) pred[v, ] <- 0
  for (v in use) if (nzchar(meth[v])) meth[v] <- "cart"
  imp <- mice::mice(dat, m = m, maxit = maxit, method = meth, predictorMatrix = pred,
                    seed = seed, printFlag = FALSE)
  comp <- mice::complete(imp, 1L)
  for (v in use) d0[[v]] <- comp[[v]]
  list(data = d0, miss = miss, dropped = drop, mids = imp)
}

before <- list(); after <- list(); mids_list <- list(); m3_by_db <- list()
miss_rows <- list()

for (nm in names(prep)) {
  message("--- ", nm, " MICE ---")
  d_raw <- prep[[nm]]$data
  # force shared cov only
  imp <- .impute_one(d_raw, cov_shared)
  before[[nm]] <- d_raw
  after[[nm]] <- imp$data
  mids_list[[nm]] <- imp$mids
  miss_rows[[nm]] <- data.frame(
    database = nm, variable = names(imp$miss),
    missing_rate = round(unname(imp$miss), 4),
    dropped_over_40pct = names(imp$miss) %in% imp$dropped
  )
}

saveRDS(before, file.path(tab_dir, "before_imputation_dbs.rds"))
saveRDS(after, file.path(tab_dir, "imputed_dbs.rds"))
saveRDS(mids_list, file.path(tab_dir, "imputed_mids.rds"))
fwrite(rbindlist(miss_rows, fill = TRUE), file.path(tab_dir, "Imputation_missingness.csv"))
writeLines(c(
  "MICE cart m=5 maxit=5 seed=1234.",
  "Exposure ANLR, follow-up time and death status were not imputed.",
  "Inferential Cox models pooled by Rubin's rules; figures/Boruta use complete #1."
), file.path(tab_dir, "Imputation_methods_note.txt"))

# ---- Quantile cascade: lock on MIMIC, force same scheme on eICU ----
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
.lock <- quantile_scheme_resolve_cascade(after$MIMIC, indices, config = .qsc_cfg)
message("Locked scheme (MIMIC): ", .lock$scheme, " — ", .lock$meta$contrast_lab)
writeLines(
  c(paste0("scheme=", .lock$scheme), paste0("reason=", .lock$reason),
    quantile_scheme_footnote_lines(.lock)),
  file.path(tab_dir, "Quantile_scheme_cascade_lock.txt")
)

# 双库同 scheme 名/水平数；切点各库自算（平权，避免把 MIMIC 切点硬套 eICU）
sch <- .lock$scheme
for (nm in names(after)) {
  d <- after[[nm]]
  x <- num(d[[IDX]])
  if (identical(sch, "binary")) {
    med <- stats::median(x, na.rm = TRUE)
    d[[paste0(IDX, "_Group")]] <- factor(ifelse(x <= med, "Low", "High"), levels = c("Low", "High"))
  } else if (identical(sch, "tertile")) {
    qs <- unique(as.numeric(stats::quantile(x, probs = c(0, 1/3, 2/3, 1), na.rm = TRUE)))
    d[[paste0(IDX, "_Group")]] <- cut(x, breaks = qs, include.lowest = TRUE, labels = c("T1", "T2", "T3"))
  } else {
    qs <- unique(as.numeric(stats::quantile(x, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)))
    d[[paste0(IDX, "_Group")]] <- cut(x, breaks = qs, include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4"))
  }
  d[[paste0(IDX, "_z")]] <- as.numeric(scale(d[[IDX]]))
  d$Age_Group <- factor(ifelse(d$Age < 65, "< 65", "\u2265 65"), levels = c("< 65", "\u2265 65"))
  after[[nm]] <- d
  message(nm, " ", sch, " levels: ", paste(levels(d[[paste0(IDX, "_Group")]]), collapse = "/"))
}
saveRDS(after, file.path(tab_dir, "imputed_dbs.rds"))
saveRDS(.lock, file.path(tab_dir, "quantile_scheme_resolved.rds"))

# ---- per-DB Boruta/SHAP/Model3/Tables ----
bor_list <- list(); shap_long_all <- list(); shap_sum_all <- list()

for (nm in names(after)) {
  message("==== tables ", nm, " ====")
  d <- after[[nm]]
  mids <- mids_list[[nm]]
  single_db <- FALSE

  # Boruta + SHAP
  cands <- setdiff(cov_shared, c("Age", "Gender"))
  cands <- cands[vapply(cands, function(v) v %in% names(d) && length(unique(na.omit(d[[v]]))) > 1, logical(1))]
  use_fs <- unique(c(IDX, "Age", "Gender", cands))
  use_fs <- use_fs[use_fs %in% names(d)]
  dd <- d[stats::complete.cases(d[, c("fustatus", "futime_years", use_fs)]) & d$futime_years > 0,
          c("fustatus", "futime_years", use_fs)]
  dd$fustatus_f <- factor(dd$fustatus, levels = c(0, 1))
  for (v in use_fs) if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
  set.seed(41904528)
  bor <- tryCatch({
    b <- Boruta::Boruta(stats::as.formula(paste("fustatus_f ~", paste(use_fs, collapse = "+"))),
                        data = dd, doTrace = 0, maxRuns = 80, ntree = 300)
    Boruta::TentativeRoughFix(b)
  }, error = function(e) { message("Boruta fail ", nm, ": ", e$message); NULL })
  bor_list[[nm]] <- bor
  st <- if (!is.null(bor)) {
    s <- Boruta::attStats(bor); s$variable <- rownames(s); s$database <- nm; s
  } else {
    data.frame(database = nm, variable = use_fs, meanImp = NA, decision = "Rejected")
  }
  fwrite(st, file.path(tab_dir, sprintf("Boruta_by_database_%s.csv", nm)))

  shap_all <- NULL
  if (requireNamespace("xgboost", quietly = TRUE) && nrow(dd) > 30) {
    mm <- tryCatch(stats::model.matrix(stats::as.formula(paste("~", paste(use_fs, collapse = "+"))), data = dd),
                   error = function(e) NULL)
    if (!is.null(mm)) {
      mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
      lab <- ifelse(dd$fustatus == 1, dd$futime_years, -dd$futime_years)
      fit_xgb <- tryCatch(xgboost::xgboost(
        data = mm, label = lab, nrounds = 60, max_depth = 3, eta = 0.05,
        objective = "survival:cox", verbose = 0
      ), error = function(e) NULL)
      if (!is.null(fit_xgb)) {
        ex <- predict(fit_xgb, newdata = mm, predcontrib = TRUE)
        ex <- ex[, colnames(ex) != "BIAS", drop = FALSE]
        imp <- sort(colMeans(abs(ex)), decreasing = TRUE)
        shap_all <- data.frame(database = nm, variable = names(imp), mean_abs_shap = as.numeric(imp))
        set.seed(41904528)
        idx_s <- sample(seq_len(nrow(ex)), min(1200L, nrow(ex)))
        sl <- as.data.frame(ex[idx_s, , drop = FALSE]); sl$i <- seq_len(nrow(sl))
        sl <- data.table::melt(as.data.table(sl), id.vars = "i", variable.name = "variable", value.name = "shap")
        sl$database <- nm
        shap_long_all[[nm]] <- as.data.frame(sl)
        shap_sum_all[[nm]] <- shap_all
      }
    }
  }

  confirmed <- if (!is.null(bor)) st$variable[st$decision == "Confirmed"] else character(0)
  shared <- setdiff(confirmed, c("Age", "Gender", IDX, grep(paste0("^", IDX), confirmed, value = TRUE)))
  shared <- unique(vapply(shared, function(v) {
    hit <- cov_shared[vapply(cov_shared, function(c) startsWith(v, c), logical(1))]
    if (length(hit)) hit[[1]] else v
  }, character(1)))
  shared <- intersect(shared, names(d))
  shared <- setdiff(shared, c(pool$exposure_components, pool$always_drop_from_model3, "SOFA"))

  vif_df <- NULL; vif_drop <- character(0)
  if (length(shared)) {
    vv <- unique(c("Age", "Gender", shared))
    dd2 <- d[stats::complete.cases(d[, intersect(c("fustatus", vv), names(d))]),
             intersect(c("fustatus", vv), names(d)), drop = FALSE]
    for (v in vv) if (is.character(dd2[[v]])) dd2[[v]] <- factor(dd2[[v]])
    v <- tryCatch(car::vif(stats::lm(fustatus ~ ., data = dd2)), error = function(e) NULL)
    if (!is.null(v)) {
      if (is.matrix(v)) {
        stat <- if ("GVIF^(1/(2*Df))" %in% colnames(v)) v[, "GVIF^(1/(2*Df))"]^2 else v[, 1]
        vif_df <- data.frame(variable = rownames(v), VIF = round(as.numeric(stat), 3))
      } else {
        vif_df <- data.frame(variable = names(v), VIF = round(as.numeric(v), 3))
      }
      vif_drop <- intersect(shared, vif_df$variable[vif_df$VIF >= 5])
      shared <- setdiff(shared, vif_drop)
    }
  }
  m3 <- unique(c("Age", "Gender", shared))
  extra <- setdiff(m3, c("Age", "Gender"))
  if (length(extra) > 5L && !is.null(shap_all)) {
    keep_e <- character(0)
    for (nmv in shap_all$variable) {
      hit <- extra[vapply(extra, function(e) grepl(e, nmv, fixed = TRUE), logical(1))]
      keep_e <- unique(c(keep_e, hit))
      if (length(keep_e) >= 5L) break
    }
    if (!length(keep_e)) keep_e <- head(extra, 5L)
    m3 <- unique(c("Age", "Gender", keep_e))
  }
  m3_by_db[[nm]] <- m3
  message(nm, " Model3: ", paste(m3, collapse = ", "))

  if (!is.null(vif_df)) {
    write_sci_xlsx(
      vif_df,
      file.path(tab_dir, pv2_table_xlsx_name("Table S2", "Assessment of multicollinearity", db = nm)),
      pv2_table_title("Table S2", "Assessment of multicollinearity"),
      "VIF < 5 considered acceptable. Shared dual-DB covariate pool."
    )
  }

  # Table 1
  .tab1 <- function(sub) {
    n <- nrow(sub)
    rows <- list(data.frame(Variable = "N", Overall = as.character(n), stringsAsFactors = FALSE))
    add_cont <- function(lab, v) {
      if (!v %in% names(sub)) return()
      rows[[length(rows) + 1]] <<- data.frame(Variable = lab, Overall = med_iqr(sub[[v]]), stringsAsFactors = FALSE)
    }
    add_cat <- function(lab, v) {
      if (!v %in% names(sub)) return()
      x <- factor(sub[[v]])
      for (lv in levels(x)) {
        rows[[length(rows) + 1]] <<- data.frame(
          Variable = paste0(lab, ": ", lv), Overall = n_pct(sum(x == lv, na.rm = TRUE), n),
          stringsAsFactors = FALSE)
      }
    }
    add_cont("Age, years", "Age"); add_cat("Gender", "Gender"); add_cat("Race", "Race")
    add_cont("ANLR", IDX)
    for (v in c("HR", "NBPS", "NBPD", "RR", "SpO2", "Temperature", "SOFA", "APSIII", "OASIS", "GCS",
                "Hemoglobin", "WBC", "PlateletCount", "Glucose", "Creatinine", "UreaNitrogen")) {
      add_cont(v, v)
    }
    for (v in c("Ventilation", "Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
                "Malignant_Tumor", "CKD", "Pneumonia", "COPD", "Hyperlipidemia")) {
      add_cat(v, v)
    }
    add_cat(sprintf("%s death", .day_lab), "fustatus")
    do.call(rbind, rows)
  }
  t1 <- .tab1(d)
  # fix death label
  t1$Variable[t1$Variable == sprintf("%s death: 0", .day_lab)] <- sprintf("%s death: No", .day_lab)
  t1$Variable[t1$Variable == sprintf("%s death: 1", .day_lab)] <- sprintf("%s death: Yes", .day_lab)
  write_sci_xlsx(
    t1,
    file.path(tab_dir, pv2_table_xlsx_name("Table 1", "Baseline characteristics", db = nm)),
    pv2_table_title("Table 1", "Baseline characteristics"),
    c("Values are median (IQR) or n (%).", "Shared dual-database covariate columns only.")
  )

  # Table 2 incidence
  g <- d[[paste0(IDX, "_Group")]]
  lev <- levels(g)
  t2_rows <- lapply(lev, function(lv) {
    sub <- d[g == lv & !is.na(g), , drop = FALSE]
    py <- sum(sub$futime_years, na.rm = TRUE)
    ev <- sum(sub$fustatus == 1L)
    data.frame(
      Group = as.character(lv), N = nrow(sub), Events = ev,
      Person_years = round(py, 2),
      Incidence_per_100PY = ifelse(py > 0, round(100 * ev / py, 2), NA_real_),
      stringsAsFactors = FALSE
    )
  })
  write_sci_xlsx(
    do.call(rbind, t2_rows),
    file.path(tab_dir, pv2_table_xlsx_name("Table 2", "Incidence of all-cause mortality", db = nm)),
    pv2_table_title("Table 2", "Incidence of all-cause mortality"),
    c(sprintf("Grouping=%s (locked dual-DB scheme).", .lock$scheme),
      sprintf("Primary endpoint: %s.", .endpoint))
  )

  # Table 3 Cox wide
  body <- pv2_cox_wide_m123_body(
    d, indices, .lock, mids = mids,
    m2_covs = c("Age", "Gender"), m3_covs = m3,
    time_var = "futime_years", event_var = "fustatus", rubin = TRUE
  )
  pv2_write_cox_wide_xlsx(
    file.path(tab_dir, pv2_table_xlsx_name("Table 3", "Cox proportional hazards models", db = nm)),
    pv2_table_title("Table 3", "Cox proportional hazards models"),
    body,
    footnotes = c(
      "Model 1: unadjusted. Model 2: Age + Gender.",
      paste0("Model 3: ", paste(m3, collapse = " + "), "."),
      "HRs pooled across MICE m=5 by Rubin's rules when applicable.",
      "SOFA reserved as mediator (not in Model 3). ANLR components excluded.",
      quantile_scheme_footnote_lines(.lock)
    )
  )

  # S4 ROC
  if (requireNamespace("pROC", quietly = TRUE)) {
    roc <- tryCatch(pROC::roc(d$fustatus, d[[IDX]], quiet = TRUE), error = function(e) NULL)
    if (!is.null(roc)) {
      auc <- as.numeric(pROC::auc(roc))
      ci <- as.numeric(pROC::ci.auc(roc))
      best <- tryCatch(pROC::coords(roc, "best", ret = c("threshold", "sensitivity", "specificity"),
                                    transpose = FALSE), error = function(e) NULL)
      s4 <- data.frame(
        Metric = c("AUC", "AUC 95% CI lower", "AUC 95% CI upper", "Youden cutoff", "Sensitivity", "Specificity"),
        Value = c(
          sprintf("%.3f", auc), sprintf("%.3f", ci[1]), sprintf("%.3f", ci[3]),
          if (!is.null(best)) sprintf("%.3f", best$threshold[1]) else "",
          if (!is.null(best)) sprintf("%.3f", best$sensitivity[1]) else "",
          if (!is.null(best)) sprintf("%.3f", best$specificity[1]) else ""
        ),
        stringsAsFactors = FALSE
      )
      write_sci_xlsx(
        s4,
        file.path(tab_dir, pv2_table_xlsx_name(
          "Table S4", sprintf("Predictive performance for %s", .endpoint), db = nm)),
        pv2_table_title("Table S4", sprintf("Predictive performance for %s", .endpoint)),
        "Youden index on complete #1 analysis set; ANLR continuous."
      )
      saveRDS(roc, file.path(tab_dir, sprintf("simple_ROC_%s.rds", nm)))
    }
  }

  # S5 in-hospital
  if ("hosp_dead" %in% names(d) && sum(is.finite(d$hosp_futime) & !is.na(d$hosp_dead)) > 50) {
    dh <- d[is.finite(d$hosp_futime) & d$hosp_futime > 0 & !is.na(d$hosp_dead), ]
    dh$futime_years_h <- dh$hosp_futime / 365.25
    dh$fustatus_h <- as.integer(dh$hosp_dead)
    # reuse groups from 28d
    lock_h <- .lock
    body_h <- tryCatch(
      pv2_cox_wide_m123_body(
        within(dh, { futime_years <- futime_years_h; fustatus <- fustatus_h }),
        indices, lock_h, mids = NULL,
        m2_covs = c("Age", "Gender"), m3_covs = m3,
        time_var = "futime_years", event_var = "fustatus", rubin = FALSE
      ),
      error = function(e) NULL
    )
    if (!is.null(body_h)) {
      pv2_write_cox_wide_xlsx(
        file.path(tab_dir, pv2_table_xlsx_name(
          "Table S5", "Sensitivity analysis using in-hospital all-cause mortality", db = nm)),
        pv2_table_title("Table S5", "Sensitivity analysis using in-hospital all-cause mortality"),
        body_h,
        footnotes = c(
          "Endpoint redefined as in-hospital all-cause death.",
          sprintf("Exposure cut-points follow the primary %s locked grouping scheme.", .day_lab),
          paste0("Model 3: ", paste(m3, collapse = " + "), ".")
        )
      )
    }
  }

  # S6 before/after — simplified overall N + key vars
  b0 <- before[[nm]]
  s6 <- data.frame(
    Variable = c("N", "Age", "ANLR", "SOFA", sprintf("%s deaths", .day_lab)),
    Before = c(nrow(b0), med_iqr(b0$Age), med_iqr(b0[[IDX]]),
               if ("SOFA" %in% names(b0)) med_iqr(b0$SOFA) else "",
               as.character(sum(b0$fustatus == 1L))),
    After = c(nrow(d), med_iqr(d$Age), med_iqr(d[[IDX]]),
              if ("SOFA" %in% names(d)) med_iqr(d$SOFA) else "",
              as.character(sum(d$fustatus == 1L))),
    stringsAsFactors = FALSE
  )
  write_sci_xlsx(
    s6,
    file.path(tab_dir, pv2_table_xlsx_name(
      "Table S6", "Baseline characteristics before and after imputation", db = nm)),
    pv2_table_title("Table S6", "Baseline characteristics before and after imputation"),
    "After = MICE complete #1 operational layer."
  )

  # S9 PH
  ph_rows <- list()
  for (model_nm in c("Model1", "Model2", "Model3")) {
    rhs <- if (model_nm == "Model1") paste0(IDX, "_z") else if (model_nm == "Model2")
      paste(c(paste0(IDX, "_z"), "Age", "Gender"), collapse = " + ")
    else paste(c(paste0(IDX, "_z"), m3), collapse = " + ")
    fit <- tryCatch(survival::coxph(
      stats::as.formula(paste("Surv(futime_years, fustatus) ~", rhs)), data = d
    ), error = function(e) NULL)
    if (is.null(fit)) next
    zph <- tryCatch(survival::cox.zph(fit), error = function(e) NULL)
    if (is.null(zph)) next
    tb <- as.data.frame(zph$table)
    tb$term <- rownames(tb); tb$model <- model_nm
    ph_rows[[length(ph_rows) + 1]] <- tb
  }
  if (length(ph_rows)) {
    ph <- rbindlist(ph_rows, fill = TRUE)
    ph$p <- fmt_p(ph$p)
    write_sci_xlsx(
      as.data.frame(ph),
      file.path(tab_dir, pv2_table_xlsx_name("Table S9", "Proportional hazards assumption", db = nm)),
      pv2_table_title("Table S9", "Proportional hazards assumption"),
      "Schoenfeld residual tests (cox.zph) on complete #1."
    )
  }

  # S1 definitions
  s1 <- data.frame(
    Item = c("Population", "Exposure", "Primary endpoint", "Sensitivity endpoint", "Mediator", "Databases"),
    Definition = c(
      "Adults aged >=18 years with ischemic stroke in ICU",
      "ANLR = Albumin / (Neutrophil count / Lymphocyte count)",
      sprintf("%s from ICU admission", .endpoint),
      "In-hospital all-cause mortality",
      "SOFA (path diagram / Table S8)",
      paste(nm, "analysis; dual-DB equal footing with shared covariates")
    ),
    stringsAsFactors = FALSE
  )
  write_sci_xlsx(
    s1,
    file.path(tab_dir, pv2_table_xlsx_name("Table S1", "Definitions", db = nm)),
    pv2_table_title("Table S1", "Definitions")
  )
}

saveRDS(bor_list, file.path(tab_dir, "Boruta_objects.rds"))
if (length(shap_long_all)) saveRDS(rbindlist(shap_long_all, fill = TRUE), file.path(tab_dir, "SHAP_long.rds"))
if (length(shap_sum_all)) fwrite(rbindlist(shap_sum_all, fill = TRUE), file.path(tab_dir, "SHAP_by_database.csv"))
fwrite(rbindlist(lapply(names(m3_by_db), function(nm) {
  data.frame(database = nm, model3 = paste(m3_by_db[[nm]], collapse = "+"))
})), file.path(tab_dir, "Model3_by_database.csv"))
saveRDS(m3_by_db, file.path(tab_dir, "Model3_by_database.rds"))
saveRDS(after, file.path(tab_dir, "imputed_dbs.rds"))

# Harmonize Model3 to intersection for dual consistency note
m3_shared <- Reduce(intersect, m3_by_db)
writeLines(c(
  "Dual-DB Model3 intersection (for Methods / remirror preference):",
  paste(m3_shared, collapse = " + "),
  "Per-database Model3 may include UV/Boruta extras within shared pool; remirror may re-fit with intersection."
), file.path(tab_dir, "Covariate_selection_note.txt"))

message("==== runner done ====")
message("Tables: ", tab_dir)
message("N MIMIC=", nrow(after$MIMIC), " eICU=", nrow(after$eICU))
message("Scheme=", .lock$scheme)
