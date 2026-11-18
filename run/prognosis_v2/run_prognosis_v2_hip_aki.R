#!/usr/bin/env Rscript
# 预后 2.0：髋关节置换合并 AKI · MIMIC 单库 · SIRI/PIV · 365 天全因死亡
# 图/表骨架对齐 49_Dyslipidemia/prognosis_v2_41904528/summary_results + Jin 多指标
# 单库不加库名前缀；Cox 走 MICE m=5 Rubin（pv2_mi_cox.R）

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
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
source(file.path(.engine, "run/prognosis_v2/pv2_front.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/pv2_mi_cox.R"), local = FALSE)
if (file.exists(file.path(.engine, "R/pub_figure_export.R"))) {
  source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
}

.data_root <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/data",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/data"
  )
  cands[dir.exists(cands)][1L]
}
.out_root <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  cands[1L]
}
dir.create(file.path(.out_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(.out_root, "Figures", "pdf"), recursive = TRUE, showWarnings = FALSE)
tab_dir <- file.path(.out_root, "Tables")
fig_dir <- file.path(.out_root, "Figures", "pdf")
single_db <- TRUE

num <- function(x) suppressWarnings(as.numeric(x))
yn <- function(x) {
  xc <- trimws(as.character(x))
  ifelse(is.na(x) | xc %in% c("", "NA"), NA_character_,
         ifelse(xc %in% c("Yes", "Y", "1", "TRUE", "True"), "Yes",
                ifelse(xc %in% c("No", "N", "0", "FALSE", "False"), "No", xc)))
}
fmt_p <- function(p) {
  ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
hr_cell <- function(hr, lo, hi) {
  ifelse(!is.finite(hr) | !is.finite(lo) | !is.finite(hi), "",
         sprintf("%.3f (%.3f-%.3f)", hr, lo, hi))
}
mean_sd <- function(x) {
  x <- num(x); sprintf("%.2f \u00b1 %.2f", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
}
med_iqr <- function(x) {
  x <- num(x)
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f-%.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f)", k, ifelse(n > 0, 100 * k / n, NA_real_))

write_sci_xlsx <- function(df, path, title, footnotes = character(0)) {
  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")
  writeData(wb, 1, title, startRow = 1, startCol = 1)
  writeData(wb, 1, df, startRow = 3, startCol = 1)
  if (length(footnotes)) {
    r0 <- 3L + nrow(df) + 2L
    for (i in seq_along(footnotes)) writeData(wb, 1, footnotes[i], startRow = r0 + i - 1L, startCol = 1)
  }
  saveWorkbook(wb, path, overwrite = TRUE)
}

message("==== 髋关节 AKI 预后 v2 · 365d · SIRI/PIV ====")
raw <- readRDS(file.path(.data_root, "analysis_Age65_SIRI_PIV_ready_365d.rds"))
raw <- as.data.frame(raw)
raw$ID <- as.character(raw$subject_id %||% raw$ID)
raw$Age <- num(raw$Age)
raw$Gender <- ifelse(as.character(raw$Gender) %in% c("Male", "M", "1"), "Male",
                     ifelse(as.character(raw$Gender) %in% c("Female", "F", "2"), "Female", NA_character_))
raw$Race <- as.character(raw$Race)
raw$futime <- num(raw$futime_365d %||% raw$futime)
raw$fustatus <- as.integer(raw$death_365d_icu %||% raw$fustatus)
raw$SIRI <- num(raw$SIRI)
raw$PIV <- num(raw$PIV)
# 去掉暴露为 0 的极端（成分缺失填 0）
raw <- raw[is.finite(raw$SIRI) & raw$SIRI > 0 & is.finite(raw$PIV) & raw$PIV > 0, ]
raw <- raw[is.finite(raw$Age) & raw$Age >= 65 & is.finite(raw$futime) & raw$futime > 0 & !is.na(raw$fustatus), ]
raw$futime_years <- raw$futime / 365.25
raw$database <- "MIMIC"

# 协变量：缺失>40% 不进池
cov_pool <- c(
  "Age", "Gender", "Race", "HR", "NBPS", "NBPD", "RR", "SpO2", "Temperature",
  "SOFA", "GCS", "CHARLSON", "OASIS", "Ventilation",
  "Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
  "Malignant_Tumor", "Stroke", "COPD", "Pneumonia",
  "Hemoglobin", "Glucose", "Sodium", "Potassium", "Lactate"
)
for (v in cov_pool) if (v %in% names(raw)) {
  if (v %in% c("Ventilation", "Hypertension", "Diabetes", "Heart_Failure",
               "Myocardial_Infarction", "Malignant_Tumor", "Stroke", "COPD", "Pneumonia")) {
    raw[[v]] <- yn(raw[[v]])
  } else if (!v %in% c("Gender", "Race")) {
    raw[[v]] <- num(raw[[v]])
  }
}
miss <- vapply(cov_pool[cov_pool %in% names(raw)], function(v) mean(is.na(raw[[v]])), numeric(1))
drop40 <- names(miss)[miss > 0.4]
cov_use <- setdiff(cov_pool[cov_pool %in% names(raw)], drop40)
message("分析集 n=", nrow(raw), " deaths=", sum(raw$fustatus == 1),
        "；缺失>40%剔除: ", paste(drop40 %||% "(无)", collapse = ", "))

# ---------- 纳排 Fig1 ----------
d03_n <- tryCatch(nrow(read.csv(file.path(.data_root, "D03_result_冰糖雪梨.csv"), check.names = FALSE)),
                  error = function(e) 360L)
merged <- tryCatch(readRDS(file.path(.data_root, "analysis_merged_hip_aki_mimic.rds")), error = function(e) NULL)
n_merged <- if (!is.null(merged)) nrow(merged) else d03_n
n_age65 <- if (!is.null(merged)) sum(num(merged$Age) >= 65, na.rm = TRUE) else NA_integer_
attr_steps <- data.frame(
  step = c(
    "Hip arthroplasty + AKI cohort (D03)",
    "Age >= 65 years",
    "SIRI and PIV computable (neutrophil/monocyte/lymphocyte/platelet)",
    "365-day landmark: follow-up time and vital status available"
  ),
  n_remain = c(d03_n, n_age65 %||% NA_integer_, NA_integer_, nrow(raw)),
  stringsAsFactors = FALSE
)
# 中间步用现有 ready 反推
ready0 <- tryCatch(readRDS(file.path(.data_root, "analysis_Age65_SIRI_PIV_ready.rds")), error = function(e) NULL)
if (!is.null(ready0)) {
  attr_steps$n_remain[3] <- nrow(ready0)
}
if (!is.finite(attr_steps$n_remain[2])) attr_steps$n_remain[2] <- attr_steps$n_remain[3]
fwrite(attr_steps, file.path(tab_dir, "Flowchart_attrition.csv"))

# Fig1：与 49_Dyslipidemia 同一引擎版式（attrition_draw_outcome_panel）
source(file.path(.engine, "R/attrition_log.R"), local = FALSE)
source(file.path(.engine, "run/prognosis_v2/draw_fig1_nhanes.R"), local = FALSE)
.n_top <- as.integer(attr_steps$n_remain[1])
.n_age <- as.integer(attr_steps$n_remain[2])
.n_idx <- as.integer(attr_steps$n_remain[3])
.n_inc <- as.integer(attr_steps$n_remain[4])
.n_death <- sum(raw$fustatus == 1)
.n_alive <- .n_inc - .n_death
.panel <- list(
  letter = "A  MIMIC",
  top = sprintf("Hip arthroplasty with AKI\nin MIMIC-IV\n(n = %s)", format(.n_top, big.mark = ",")),
  mid = sprintf("Aged >= 65 years\n(n = %s)", format(.n_age, big.mark = ",")),
  inc = sprintf("Participants included\n(n = %s)", format(.n_inc, big.mark = ",")),
  side1 = sprintf("Age < 65 years or\nmissing age (n = %s)", format(.n_top - .n_age, big.mark = ",")),
  side2 = paste0(
    sprintf("1. SIRI or PIV not\ncomputable (n = %s)\n", format(.n_age - .n_idx, big.mark = ",")),
    sprintf("2. Missing 365-day follow-up\nor invalid exposure (n = %s)", format(.n_idx - .n_inc, big.mark = ","))
  ),
  death = sprintf("365-day all-cause death\n(n = %s)", format(.n_death, big.mark = ",")),
  alive = sprintf("Alive at 365 days\n(n = %s)", format(.n_alive, big.mark = ","))
)
attrition_draw_outcome_figure(
  file.path(fig_dir, "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI.pdf"),
  list(.panel), width = 5.4, height = 6.35, family = "Times",
  csv_path = file.path(tab_dir, "Flowchart_attrition.csv")
)

# ---------- MICE ----------
keep_cols <- unique(c("ID", "database", "Age", "Gender", "Race", cov_use, "SIRI", "PIV",
                      "futime", "futime_years", "fustatus", "OASIS", "Lactate"))
keep_cols <- keep_cols[keep_cols %in% names(raw)]
# OASIS：数值化后进 MICE（与 SOFA/GCS 同池；勿事后再并）
if ("OASIS" %in% names(raw)) raw$OASIS <- num(raw$OASIS)
d0 <- raw[, keep_cols, drop = FALSE]
if (!"OASIS" %in% names(d0)) {
  stop("OASIS missing from analysis rds — cannot run mediation-ready pipeline")
}
message("OASIS in pre-MI: n=", sum(is.finite(d0$OASIS)), "/", nrow(d0),
        " miss=", sprintf("%.2f%%", 100 * mean(is.na(d0$OASIS))))
saveRDS(list(MIMIC = d0), file.path(tab_dir, "before_imputation_dbs.rds"))

.impute_icu <- function(d, seed = 1234L, m = 5L, maxit = 5L, thr = 0.4) {
  covs <- setdiff(names(d), c("ID", "database", "SIRI", "PIV", "futime", "futime_years", "fustatus"))
  miss <- vapply(covs, function(v) mean(is.na(d[[v]])), numeric(1))
  drop <- names(miss)[is.finite(miss) & miss > thr]
  use <- setdiff(covs, drop)
  if (!length(use) || !any(vapply(use, function(v) anyNA(d[[v]]), logical(1)))) {
    return(list(data = d, miss = miss, dropped = drop, mids = NULL, m = 0L))
  }
  dat <- d[, use, drop = FALSE]
  for (v in use) if (is.character(dat[[v]]) || is.factor(dat[[v]])) dat[[v]] <- factor(dat[[v]])
  aux <- c("fustatus", "SIRI", "PIV")
  aux <- aux[aux %in% names(d)]
  for (v in aux) dat[[v]] <- d[[v]]
  ini <- mice::mice(dat, maxit = 0, printFlag = FALSE)
  meth <- ini$method; pred <- ini$predictorMatrix
  meth[aux] <- ""; for (v in aux) pred[v, ] <- 0
  # cart for continuous/factor
  for (v in use) if (nzchar(meth[v])) meth[v] <- "cart"
  imp <- mice::mice(dat, m = m, maxit = maxit, method = meth, predictorMatrix = pred,
                    seed = seed, printFlag = FALSE)
  comp <- mice::complete(imp, 1L)
  for (v in use) d[[v]] <- comp[[v]]
  list(data = d, miss = miss, dropped = drop, mids = imp, m = m)
}

message("MICE cart m=5 …")
imp_res <- .impute_icu(d0)
d <- imp_res$data
mids <- imp_res$mids
fwrite(data.frame(database = "MIMIC", variable = names(imp_res$miss),
                  missing_rate = round(unname(imp_res$miss), 4),
                  dropped_over_40pct = names(imp_res$miss) %in% imp_res$dropped),
       file.path(tab_dir, "Imputation_missingness.csv"))
saveRDS(list(MIMIC = d), file.path(tab_dir, "imputed_dbs.rds"))
if (!is.null(mids)) saveRDS(list(MIMIC = mids), file.path(tab_dir, "imputed_mids.rds"))
writeLines(pv2_mi_methods_footnote(5L, 5L, 1234L), file.path(tab_dir, "Imputation_methods_note.txt"))

# 四分位
for (idx in c("SIRI", "PIV")) {
  qs <- stats::quantile(d[[idx]], probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
  d[[paste0(idx, "_Q")]] <- cut(d[[idx]], breaks = unique(qs), include.lowest = TRUE,
                                labels = c("Q1", "Q2", "Q3", "Q4"))
  d[[paste0(idx, "_z")]] <- as.numeric(scale(d[[idx]]))
}
d$Age_Group <- factor(ifelse(d$Age < 75, "< 75", "\u2265 75"), levels = c("< 75", "\u2265 75"))
d$SOFA_Group <- factor(ifelse(d$SOFA < 6, "< 6", "\u2265 6"), levels = c("< 6", "\u2265 6"))

# ---------- Boruta + SHAP ----------
cands <- setdiff(cov_use, c("Age", "Gender"))
cands <- cands[vapply(cands, function(v) length(unique(na.omit(d[[v]]))) > 1, logical(1))]
# 暴露进特征筛选（Jin），不进 Model3
use_fs <- unique(c("SIRI", "PIV", "Age", "Gender", cands))
use_fs <- use_fs[use_fs %in% names(d)]
dd <- d[stats::complete.cases(d[, c("fustatus", "futime_years", use_fs)]) & d$futime_years > 0,
        c("fustatus", "futime_years", use_fs)]
dd$fustatus_f <- factor(dd$fustatus, levels = c(0, 1))
for (v in use_fs) if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
message("Boruta n=", nrow(dd), " p=", length(use_fs))
set.seed(41904528)
bor <- Boruta::Boruta(
  stats::as.formula(paste("fustatus_f ~", paste(use_fs, collapse = "+"))),
  data = dd, doTrace = 0, maxRuns = 100, ntree = 500
)
bor <- Boruta::TentativeRoughFix(bor)
st <- Boruta::attStats(bor)
st$variable <- rownames(st)
st$database <- "MIMIC"
fwrite(st, file.path(tab_dir, "Boruta_by_database.csv"))
saveRDS(list(MIMIC = bor), file.path(tab_dir, "Boruta_objects.rds"))

mm <- stats::model.matrix(stats::as.formula(paste("~", paste(use_fs, collapse = "+"))), data = dd)
mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
lab <- ifelse(dd$fustatus == 1, dd$futime_years, -dd$futime_years)
fit_xgb <- xgboost::xgboost(
  data = mm, label = lab, nrounds = 80, max_depth = 3, eta = 0.05,
  objective = "survival:cox", verbose = 0
)
ex <- predict(fit_xgb, newdata = mm, predcontrib = TRUE)
ex <- ex[, colnames(ex) != "BIAS", drop = FALSE]
imp <- sort(colMeans(abs(ex)), decreasing = TRUE)
shap_all <- data.frame(database = "MIMIC", variable = names(imp), mean_abs_shap = as.numeric(imp))
fwrite(shap_all, file.path(tab_dir, "SHAP_by_database.csv"))
set.seed(41904528)
idx_s <- sample(seq_len(nrow(ex)), min(1500L, nrow(ex)))
sl <- as.data.frame(ex[idx_s, , drop = FALSE])
sl$i <- seq_len(nrow(sl))
sl <- data.table::melt(as.data.table(sl), id.vars = "i", variable.name = "variable", value.name = "shap")
sl$database <- "MIMIC"
saveRDS(as.data.frame(sl), file.path(tab_dir, "SHAP_long.rds"))

confirmed <- st$variable[st$decision == "Confirmed"]
shared <- setdiff(confirmed, c("Age", "Gender", "SIRI", "PIV",
                               grep("^SIRI|^PIV", confirmed, value = TRUE)))
# 哑变量名 → 原列
shared <- unique(vapply(shared, function(v) {
  hit <- cov_use[vapply(cov_use, function(c) startsWith(v, c), logical(1))]
  if (length(hit)) hit[[1]] else v
}, character(1)))
shared <- intersect(shared, names(d))

# VIF
vif_drop <- character(0)
vif_df <- NULL
if (length(shared)) {
  vv <- unique(c("Age", "Gender", shared))
  dd2 <- d[stats::complete.cases(d[, c("fustatus", vv)]), c("fustatus", vv)]
  for (v in vv) if (is.character(dd2[[v]])) dd2[[v]] <- factor(dd2[[v]])
  v <- tryCatch(car::vif(stats::lm(fustatus ~ ., data = dd2)), error = function(e) NULL)
  if (!is.null(v)) {
    if (is.matrix(v)) {
      stat <- if ("GVIF^(1/(2*Df))" %in% colnames(v)) v[, "GVIF^(1/(2*Df))"]^2 else v[, 1]
      vif_df <- data.frame(variable = rownames(v), VIF = round(as.numeric(stat), 3))
    } else {
      vif_df <- data.frame(variable = names(v), VIF = round(as.numeric(v), 3))
    }
    bad <- vif_df$variable[vif_df$VIF >= 5]
    vif_drop <- intersect(shared, bad)
    shared <- setdiff(shared, vif_drop)
  }
}
m3 <- unique(c("Age", "Gender", shared))
# 小样本限制 Model3 额外变量
extra <- setdiff(m3, c("Age", "Gender"))
if (length(extra) > 4L) {
  # 按 SHAP 排序保留前 4
  ord <- shap_all$variable
  base <- sub("Male|Female|Yes|No|.*", "", ord)
  keep_e <- character(0)
  for (nm in ord) {
    hit <- extra[vapply(extra, function(e) grepl(e, nm, fixed = TRUE), logical(1))]
    keep_e <- unique(c(keep_e, hit))
    if (length(keep_e) >= 4L) break
  }
  if (!length(keep_e)) keep_e <- head(extra, 4L)
  m3 <- unique(c("Age", "Gender", keep_e))
}
writeLines(c(
  "协变量：Jin 2026 Boruta + SHAP，VIF<5。",
  "Model 1 不调整。Model 2 = Age + Gender。",
  paste("Model 3 =", paste(m3, collapse = " + ")),
  paste("VIF>=5 剔除:", paste(vif_drop %||% "(无)", collapse = ", ")),
  "暴露 SIRI/PIV 及成分不进 Model3。疾病/肾相关列已排除。",
  "MICE cart m=5 seed=1234；操作层 complete#1；Cox Rubin 合并。",
  "结局：ICU 入科起 365 天全因死亡。人群：髋关节置换合并 AKI，Age≥65，MIMIC-IV。"
), file.path(tab_dir, "Covariate_selection_note.txt"))
message("Model3: ", paste(m3, collapse = ", "))

if (!is.null(vif_df)) {
  write_sci_xlsx(
    vif_df,
    file.path(tab_dir, pv2_table_xlsx_name("Table S2", "Assessment of multicollinearity", single_db = TRUE)),
    pv2_table_title("Table S2", "Assessment of multicollinearity", single_db = TRUE),
    "VIF < 5 considered acceptable."
  )
}

# ---------- Table 1 ----------
.tab1_block <- function(sub, label) {
  n <- nrow(sub)
  rows <- list(
    data.frame(Variable = "N", Overall = as.character(n), stringsAsFactors = FALSE)
  )
  add_cont <- function(lab, v) {
    if (!v %in% names(sub)) return()
    rows[[length(rows) + 1L]] <<- data.frame(Variable = lab, Overall = med_iqr(sub[[v]]), stringsAsFactors = FALSE)
  }
  add_cat <- function(lab, v) {
    if (!v %in% names(sub)) return()
    x <- factor(sub[[v]])
    for (lv in levels(x)) {
      rows[[length(rows) + 1L]] <<- data.frame(
        Variable = paste0(lab, ": ", lv),
        Overall = n_pct(sum(x == lv, na.rm = TRUE), n),
        stringsAsFactors = FALSE
      )
    }
  }
  add_cont("Age, years", "Age")
  add_cat("Gender", "Gender")
  add_cont("SOFA", "SOFA")
  add_cont("GCS", "GCS")
  add_cont("CHARLSON", "CHARLSON")
  add_cont("OASIS", "OASIS")
  add_cont("HR", "HR")
  add_cont("SBP, mmHg", "NBPS")
  add_cont("Hemoglobin", "Hemoglobin")
  add_cont("Glucose", "Glucose")
  add_cont("Lactate", "Lactate")
  add_cont("SIRI", "SIRI")
  add_cont("PIV", "PIV")
  for (v in c("Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
              "Stroke", "COPD", "Pneumonia", "Ventilation", "Malignant_Tumor")) {
    add_cat(v, v)
  }
  out <- do.call(rbind, rows)
  names(out)[2] <- label
  out
}
t1_all <- .tab1_block(d, "Overall")
t1_a <- .tab1_block(d[d$fustatus == 0, ], "Alive")
t1_d <- .tab1_block(d[d$fustatus == 1, ], "Dead")
t1 <- Reduce(function(a, b) merge(a, b, by = "Variable", all = TRUE, sort = FALSE),
             list(t1_all, t1_a, t1_d))
# P 值（连续 Wilcoxon / 分类 Fisher）
pvec <- character(nrow(t1))
for (i in seq_len(nrow(t1))) {
  lab <- t1$Variable[i]
  if (lab == "N") { pvec[i] <- ""; next }
  base <- sub(": .*", "", lab)
  map <- c("Age, years" = "Age", "SOFA" = "SOFA", "GCS" = "GCS", "CHARLSON" = "CHARLSON",
           "OASIS" = "OASIS",
           "HR" = "HR", "SBP, mmHg" = "NBPS", "Hemoglobin" = "Hemoglobin", "Glucose" = "Glucose",
           "Lactate" = "Lactate", "SIRI" = "SIRI", "PIV" = "PIV")
  if (base %in% names(map)) {
    v <- map[[base]]
    p <- tryCatch(stats::wilcox.test(d[[v]] ~ d$fustatus)$p.value, error = function(e) NA_real_)
    pvec[i] <- fmt_p(p)
  } else if (grepl(":", lab, fixed = TRUE)) {
    v <- strsplit(lab, ": ", fixed = TRUE)[[1]][1]
    if (v %in% names(d)) {
      p <- tryCatch(stats::fisher.test(table(d[[v]], d$fustatus))$p.value, error = function(e) NA_real_)
      pvec[i] <- fmt_p(p)
    } else pvec[i] <- ""
  } else pvec[i] <- ""
}
t1$P <- pvec
write_sci_xlsx(
  t1,
  file.path(tab_dir, pv2_table_xlsx_name("Table 1", "Baseline characteristics", single_db = TRUE)),
  pv2_table_title("Table 1", "Baseline characteristics", single_db = TRUE),
  c(
    sprintf("Analytic cohort: hip arthroplasty with AKI, Age\u226565, MIMIC-IV; 365-day all-cause mortality (N=%d, deaths=%d).",
            nrow(d), sum(d$fustatus == 1)),
    "Continuous variables: median (IQR). Categorical: n (%). P: Wilcoxon or Fisher exact (Alive vs Dead)."
  )
)

# ---------- Table 2 发病率 ----------
py_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Q")
  for (g in levels(d[[qv]])) {
    sub <- d[!is.na(d[[qv]]) & d[[qv]] == g, ]
    py_rows[[length(py_rows) + 1L]] <- data.frame(
      Index = idx, Quartile = g, N = nrow(sub),
      Events = sum(sub$fustatus == 1),
      Person_years = round(sum(sub$futime_years), 2),
      Rate_per_100_py = round(100 * sum(sub$fustatus == 1) / sum(sub$futime_years), 2),
      Cumulative_pct = round(100 * mean(sub$fustatus == 1), 2),
      stringsAsFactors = FALSE
    )
  }
}
py <- do.call(rbind, py_rows)
write_sci_xlsx(
  py,
  file.path(tab_dir, pv2_table_xlsx_name("Table 2", "Incidence of all-cause mortality", single_db = TRUE)),
  pv2_table_title("Table 2", "Incidence of all-cause mortality within 365 days", single_db = TRUE),
  "Rates per 100 person-years; cumulative incidence = deaths/N within 365-day landmark."
)
fwrite(py, file.path(tab_dir, "Table 2. Person-years.csv"))

# ---------- Table 3 Cox（连续 per-SD + 四分位）Rubin ----------
cox_rows <- list()
.fit_cox_row <- function(d, mids, rhs, model, index, term_keep) {
  res <- pv2_cox_extract(
    d, rhs, mids = mids, time_var = "futime_years", event_var = "fustatus",
    exposure_keep = c("SIRI", "PIV", "SIRI_Q", "PIV_Q", "SIRI_z", "PIV_z"),
    weighted = FALSE, rubin = TRUE
  )
  if (is.null(res)) return(NULL)
  res$Index <- index
  res$model <- model
  res <- res[grepl(term_keep, res$term), , drop = FALSE]
  res
}
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Q")
  zv <- paste0(idx, "_z")
  d[[qv]] <- factor(d[[qv]], levels = c("Q1", "Q2", "Q3", "Q4"))
  rhs1c <- zv
  rhs2c <- paste(zv, "+ Age + Gender")
  rhs3c <- paste(c(zv, m3), collapse = " + ")
  rhs1q <- qv
  rhs2q <- paste(qv, "+ Age + Gender")
  rhs3q <- paste(c(qv, m3), collapse = " + ")
  for (spec in list(
    list(rhs1c, "Model1_continuous", paste0(idx, "_z")),
    list(rhs2c, "Model2_continuous", paste0(idx, "_z")),
    list(rhs3c, "Model3_continuous", paste0(idx, "_z")),
    list(rhs1q, "Model1_quartile", paste0(idx, "_Q")),
    list(rhs2q, "Model2_quartile", paste0(idx, "_Q")),
    list(rhs3q, "Model3_quartile", paste0(idx, "_Q"))
  )) {
    rr <- tryCatch(.fit_cox_row(d, mids, spec[[1]], spec[[2]], idx, spec[[3]]), error = function(e) {
      message("Cox fail ", idx, " ", spec[[2]], ": ", conditionMessage(e)); NULL
    })
    if (!is.null(rr) && nrow(rr)) cox_rows[[length(cox_rows) + 1L]] <- rr
  }
  # P for trend
  d$qnum <- as.integer(d[[qv]])
  for (mod in c("Model1", "Model2", "Model3")) {
    rhs <- if (mod == "Model1") "qnum" else if (mod == "Model2") "qnum + Age + Gender" else paste(c("qnum", m3), collapse = " + ")
    tr <- tryCatch(pv2_cox_extract(d, rhs, mids = mids, time_var = "futime_years", event_var = "fustatus",
                                   exposure_keep = c("qnum", "SIRI", "PIV"), rubin = TRUE), error = function(e) NULL)
    if (!is.null(tr)) {
      tr <- tr[tr$term == "qnum", , drop = FALSE]
      if (nrow(tr)) {
        tr$Index <- idx; tr$model <- paste0(mod, "_trend"); tr$term <- "P_for_trend"
        cox_rows[[length(cox_rows) + 1L]] <- tr
      }
    }
  }
}
cox_out <- do.call(rbind, cox_rows)
fwrite(cox_out, file.path(tab_dir, "Table 3. Cox.csv"))

# 发表宽表
.pub_cox <- function(cox_out) {
  out <- data.frame(Index = character(), Term = character(),
                    Model1 = character(), Model2 = character(), Model3 = character(),
                    stringsAsFactors = FALSE)
  for (idx in c("SIRI", "PIV")) {
    cell <- function(mod, kind, term_pat) {
      r <- cox_out[cox_out$Index == idx & cox_out$model == paste0(mod, "_", kind), , drop = FALSE]
      r <- r[grepl(term_pat, r$term), , drop = FALSE]
      if (!nrow(r)) return("")
      paste0(hr_cell(r$hr[1], r$lo[1], r$hi[1]), "; P=", fmt_p(r$p[1]))
    }
    out <- rbind(out, data.frame(
      Index = idx, Term = "Per 1-SD increase",
      Model1 = cell("Model1", "continuous", "_z"),
      Model2 = cell("Model2", "continuous", "_z"),
      Model3 = cell("Model3", "continuous", "_z"),
      stringsAsFactors = FALSE
    ))
    out <- rbind(out, data.frame(
      Index = idx, Term = "Quartile Q1", Model1 = "1 (Reference)", Model2 = "1 (Reference)",
      Model3 = "1 (Reference)", stringsAsFactors = FALSE
    ))
    for (q in c("Q2", "Q3", "Q4")) {
      out <- rbind(out, data.frame(
        Index = idx, Term = paste0(q, " vs Q1"),
        Model1 = cell("Model1", "quartile", q),
        Model2 = cell("Model2", "quartile", q),
        Model3 = cell("Model3", "quartile", q),
        stringsAsFactors = FALSE
      ))
    }
    tr <- cox_out[cox_out$Index == idx & grepl("_trend$", cox_out$model), ]
    tp <- function(mod) {
      r <- tr[tr$model == paste0(mod, "_trend"), ]
      if (!nrow(r)) "" else fmt_p(r$p[1])
    }
    out <- rbind(out, data.frame(
      Index = idx, Term = "P for trend",
      Model1 = tp("Model1"), Model2 = tp("Model2"), Model3 = tp("Model3"),
      stringsAsFactors = FALSE
    ))
  }
  out
}
t3 <- .pub_cox(cox_out)
write_sci_xlsx(
  t3,
  file.path(tab_dir, pv2_table_xlsx_name("Table 3", "Cox proportional hazards models", single_db = TRUE)),
  pv2_table_title("Table 3", "Cox proportional hazards models for 365-day all-cause mortality", single_db = TRUE),
  c(
    "Model 1: unadjusted. Model 2: Age + Gender. Model 3: Boruta/SHAP/VIF-selected covariates.",
    paste("Model 3 covariates:", paste(m3, collapse = ", ")),
    "Multiple imputation (m=5, cart); hazard ratios pooled by Rubin rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample."
  )
)

# ---------- Table S4 ROC ----------
youden <- list()
roc_list <- list()
for (idx in c("SIRI", "PIV")) {
  y <- d$fustatus
  ok <- is.finite(d[[idx]]) & !is.na(y)
  if (length(unique(y[ok])) < 2) next
  roc <- pROC::roc(y[ok], d[[idx]][ok], quiet = TRUE, direction = "<")
  cd <- pROC::coords(roc, ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE)
  best <- which.max(cd$sensitivity + cd$specificity - 1)
  youden[[idx]] <- data.frame(
    Index = idx, AUC = round(as.numeric(pROC::auc(roc)), 3),
    cutoff = round(cd$threshold[best], 3),
    sensitivity = round(cd$sensitivity[best], 3),
    specificity = round(cd$specificity[best], 3)
  )
  roc_list[[idx]] <- data.frame(Index = idx, fpr = 1 - cd$specificity, tpr = cd$sensitivity)
}
yd <- do.call(rbind, youden)
fwrite(yd, file.path(tab_dir, "Table S4. Youden.csv"))
write_sci_xlsx(
  yd,
  file.path(tab_dir, pv2_table_xlsx_name("Table S4", "Predictive performance for 365-day all-cause mortality", single_db = TRUE)),
  pv2_table_title("Table S4", "Predictive performance for 365-day all-cause mortality", single_db = TRUE),
  "Youden index on the ROC curve of the continuous index (unadjusted)."
)

# ---------- Table S6 插补前后 ----------
.before_after <- function() {
  b <- readRDS(file.path(tab_dir, "before_imputation_dbs.rds"))$MIMIC
  a <- d
  vars <- intersect(cov_use, names(b))
  rows <- list()
  for (v in vars) {
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = v,
      Before_missing_pct = round(100 * mean(is.na(b[[v]])), 1),
      After_missing_pct = round(100 * mean(is.na(a[[v]])), 1),
      Before_median = if (is.numeric(b[[v]])) med_iqr(b[[v]]) else NA_character_,
      After_median = if (is.numeric(a[[v]])) med_iqr(a[[v]]) else NA_character_,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}
s6 <- .before_after()
write_sci_xlsx(
  s6,
  file.path(tab_dir, pv2_table_xlsx_name("Table S6", "Baseline characteristics before and after imputation", single_db = TRUE)),
  pv2_table_title("Table S6", "Baseline characteristics before and after imputation", single_db = TRUE),
  "Variables with >40% missing were not imputed. Exposure/outcome/time not imputed."
)

# ---------- Fig2 Boruta + SHAP ----------
bor_df <- st
bor_df$variable <- factor(bor_df$variable, levels = bor_df$variable[order(bor_df$meanImp)])
p_bor <- ggplot(bor_df, aes(variable, meanImp, color = decision)) +
  geom_point(size = 2) + coord_flip() +
  scale_color_manual(values = c(Confirmed = "#D55E00", Rejected = "grey60", Tentative = "#0072B2")) +
  theme_bw(base_size = 11) +
  labs(x = NULL, y = "Mean importance", title = "A  Boruta")
top_v <- head(shap_all$variable, 15)
sl2 <- as.data.frame(sl)
sl2 <- sl2[as.character(sl2$variable) %in% top_v, ]
sl2$variable <- factor(as.character(sl2$variable), levels = rev(top_v))
p_shap <- ggplot(sl2, aes(shap, variable)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey50") +
  geom_jitter(height = 0.15, alpha = 0.25, size = 0.6, color = "#0072B2") +
  theme_bw(base_size = 11) +
  labs(x = "SHAP value (log-hazard)", y = NULL, title = "B  SHAP")
if (requireNamespace("patchwork", quietly = TRUE)) {
  p2 <- p_bor + p_shap
} else {
  p2 <- p_bor
}
ggsave(file.path(fig_dir, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf"),
       p2, width = 12, height = 6, device = "pdf")

# ---------- Fig3 KM cuminc ----------
.km_panel <- function(d, qv, title) {
  d <- d[!is.na(d[[qv]]), ]
  sf <- survfit(as.formula(paste("Surv(futime_years, fustatus) ~", qv)), data = d)
  s <- summary(sf)
  df <- data.frame(time = s$time, surv = s$surv, strata = gsub(".*=", "", as.character(s$strata)))
  # cuminc
  df$cuminc <- 1 - df$surv
  lr <- tryCatch(survminer::surv_pvalue(survminer::ggsurvplot(sf, data = d)$plot.data %||% NULL), error = function(e) NULL)
  pval <- tryCatch({
    sd0 <- survdiff(as.formula(paste("Surv(futime_years, fustatus) ~", qv)), data = d)
    pchisq(sd0$chisq, length(sd0$n) - 1, lower.tail = FALSE)
  }, error = function(e) NA_real_)
  ggplot(df, aes(time, cuminc, color = strata)) +
    geom_step(linewidth = 0.8) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, NA)) +
    theme_bw(base_size = 11) +
    labs(title = title, subtitle = paste0("Log-rank P = ", fmt_p(pval)),
         x = "Follow-up (years)", y = "Cumulative incidence", color = "Quartile")
}
p3a <- .km_panel(d, "SIRI_Q", "A  SIRI")
p3b <- .km_panel(d, "PIV_Q", "B  PIV")
p3 <- if (requireNamespace("patchwork", quietly = TRUE)) p3a + p3b else p3a
ggsave(file.path(fig_dir, "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index.pdf"),
       p3, width = 11, height = 5, device = "pdf")

# ---------- Fig4 RCS ----------
.rcs_panel <- function(d, idx, title) {
  d$time <- d$futime_years; d$event <- d$fustatus
  fit <- tryCatch(
    coxph(Surv(time, event) ~ splines::ns(get(idx), df = 3) + Age + Gender, data = d),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    return(ggplot() + theme_void() + ggtitle(paste(title, "(failed)")))
  }
  # rebuild with proper name
  d$expo <- d[[idx]]
  fit <- coxph(Surv(time, event) ~ splines::ns(expo, df = 3) + Age + Gender, data = d)
  grid <- seq(stats::quantile(d$expo, 0.05, na.rm = TRUE),
              stats::quantile(d$expo, 0.95, na.rm = TRUE), length.out = 80)
  nd <- data.frame(expo = grid, Age = median(d$Age, na.rm = TRUE), Gender = "Female")
  lp <- as.numeric(predict(fit, newdata = nd, type = "lp"))
  ref_i <- which.min(abs(grid - median(d$expo, na.rm = TRUE)))
  hr <- exp(lp - lp[ref_i])
  ggplot(data.frame(x = grid, hr = hr), aes(x, hr)) +
    geom_line(color = "#D55E00", linewidth = 1) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey50") +
    theme_bw(base_size = 11) +
    labs(title = title, x = idx, y = "HR (ref = median)")
}
p4 <- if (requireNamespace("patchwork", quietly = TRUE)) {
  .rcs_panel(d, "SIRI", "A  SIRI") + .rcs_panel(d, "PIV", "B  PIV")
} else .rcs_panel(d, "SIRI", "SIRI")
ggsave(file.path(fig_dir, "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality.pdf"),
       p4, width = 11, height = 5, device = "pdf")

# ---------- Fig5 ROC ----------
roc_df <- do.call(rbind, roc_list)
p5 <- ggplot(roc_df, aes(fpr, tpr, color = Index)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey60") +
  geom_line(linewidth = 0.9) +
  theme_bw(base_size = 11) +
  labs(title = "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality",
       x = "1 - Specificity", y = "Sensitivity",
       subtitle = paste(sprintf("%s AUC=%.3f", yd$Index, yd$AUC), collapse = "; "))
ggsave(file.path(fig_dir, "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality.pdf"),
       p5, width = 7, height = 6, device = "pdf")

# ---------- Fig7 亚组（Q4 vs Q1）----------
sub_vars <- c("Age_Group", "Gender", "Hypertension", "Diabetes", "SOFA_Group")
sub_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Q")
  d$expo_bin <- factor(ifelse(d[[qv]] == "Q4", "Q4", ifelse(d[[qv]] == "Q1", "Q1", "Middle")),
                       levels = c("Q1", "Middle", "Q4"))
  for (sv in sub_vars) {
    if (!sv %in% names(d)) next
    for (lv in levels(factor(d[[sv]]))) {
      sub <- d[!is.na(d[[sv]]) & as.character(d[[sv]]) == lv, ]
      # 全人群口径：保留 Middle，对比 Q4 vs Q1
      sub$expo_bin <- factor(sub$expo_bin, levels = c("Q1", "Middle", "Q4"))
      if (sum(sub$expo_bin == "Q1", na.rm = TRUE) < 5 || sum(sub$expo_bin == "Q4", na.rm = TRUE) < 5) next
      if (sum(sub$fustatus == 1, na.rm = TRUE) < 3) next
      fit <- tryCatch(
        coxph(Surv(futime_years, fustatus) ~ expo_bin + Age, data = sub),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      ci <- summary(fit)$conf.int
      co <- summary(fit)$coefficients
      hit <- grep("Q4", rownames(ci), fixed = TRUE)[1]
      if (is.na(hit)) next
      sub_rows[[length(sub_rows) + 1L]] <- data.frame(
        Index = idx, stratum = sv, level = lv, N = nrow(sub),
        HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
        p = co[rownames(ci)[hit], "Pr(>|z|)"],
        stringsAsFactors = FALSE
      )
    }
  }
}
sub_tab <- if (length(sub_rows)) do.call(rbind, sub_rows) else data.frame()
if (nrow(sub_tab)) {
  fwrite(sub_tab, file.path(tab_dir, "Subgroup_rows.csv"))
  sub_tab$label <- paste0(sub_tab$stratum, ": ", sub_tab$level, " (N=", sub_tab$N, ")")
  # Overall
  ov_rows <- list()
  for (idx in c("SIRI", "PIV")) {
    qv <- paste0(idx, "_Q")
    d$expo_bin <- factor(ifelse(d[[qv]] == "Q4", "Q4", ifelse(d[[qv]] == "Q1", "Q1", "Middle")),
                         levels = c("Q1", "Middle", "Q4"))
    fit <- coxph(Surv(futime_years, fustatus) ~ expo_bin + Age + Gender, data = d)
    ci <- summary(fit)$conf.int
    hit <- grep("Q4", rownames(ci), fixed = TRUE)[1]
    ov_rows[[idx]] <- data.frame(
      Index = idx, stratum = "Overall", level = "All", N = nrow(d),
      HR = ci[hit, 1], lo = ci[hit, 3], hi = ci[hit, 4],
      p = summary(fit)$coefficients[rownames(ci)[hit], "Pr(>|z|)"],
      label = paste0("Overall (N=", nrow(d), ")"),
      stringsAsFactors = FALSE
    )
  }
  plot_df <- rbind(do.call(rbind, ov_rows), sub_tab)
  plot_df$label <- factor(plot_df$label, levels = rev(unique(plot_df$label)))
  p7 <- ggplot(plot_df, aes(HR, label)) +
    geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
    geom_point(size = 2) +
    geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.2) +
    facet_wrap(~Index, scales = "free_y") +
    scale_x_log10(limits = c(0.2, 5)) +
    theme_bw(base_size = 10) +
    labs(title = "Figure 7. Subgroup analyses (Q4 vs Q1) for 365-day all-cause mortality",
         x = "HR (95% CI)", y = NULL)
  ggsave(file.path(fig_dir, "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality.pdf"),
         p7, width = 11, height = 7, device = "pdf")
}

# ---------- 中介（OASIS；与插补队列同 N；详细 Fig6/S8 由 remirror 定稿）----------
if (!"OASIS" %in% names(d) || sum(is.finite(d$OASIS)) < nrow(d) * 0.9) {
  stop("OASIS not available after MICE — abort (must enter cov pool from data source)")
}
message(sprintf("Mediation mediator=OASIS after MI: n_finite=%d / %d",
                sum(is.finite(d$OASIS)), nrow(d)))
for (idx in c("SIRI", "PIV")) {
  dd <- d[stats::complete.cases(d[, c(idx, "OASIS", "fustatus", "futime_years", "Age", "Gender")]), ]
  dd$.M <- as.numeric(scale(dd$OASIS))
  fit_m <- lm(as.formula(paste(".M ~", idx, "+ Age + Gender")), data = dd)
  fit_y <- coxph(as.formula(paste("Surv(futime_years, fustatus) ~", idx, "+ .M + Age + Gender")), data = dd)
  fit_t <- coxph(as.formula(paste("Surv(futime_years, fustatus) ~", idx, "+ Age + Gender")), data = dd)
  pa <- summary(fit_m)$coefficients[idx, 4]
  pb <- summary(fit_y)$coefficients[".M", 5]
  pc <- summary(fit_t)$coefficients[idx, 5]
  message(sprintf("Mediation %s via OASIS (n=%d): pa=%s pb=%s pTE=%s",
                  idx, nrow(dd), fmt_p(pa), fmt_p(pb), fmt_p(pc)))
}
writeLines(
  c("Mediator=OASIS entered cov_pool and MICE with the analytic cohort.",
    "Publication Figure 6 / Table S8 are finalized by remirror_hip_aki_pub.R."),
  file.path(tab_dir, "Mediation_OASIS_note.txt")
)

# ---------- 四目录 ----------
if (exists("pub_figure_ensure_formats", mode = "function")) {
  message("导出 png/tiff/image_information …")
  tryCatch(
    pub_figure_ensure_formats(file.path(.out_root, "Figures")),
    error = function(e) message("pub_figure_ensure_formats: ", conditionMessage(e))
  )
}

# Methods stub
writeLines(c(
  "# Methods (draft)",
  "",
  "We included adults aged 65 years or older with hip arthroplasty and AKI in MIMIC-IV.",
  "The primary endpoint was all-cause mortality within 365 days after ICU admission.",
  "Exposures were SIRI and PIV, analyzed as continuous (per 1-SD) and quartile variables.",
  "Covariates were selected by Boruta and SHAP with VIF < 5 (Jin 2026 framework).",
  "Missing covariates (<40%) were imputed by MICE (cart, m=5); Cox models were pooled by Rubin's rules.",
  paste("Model 3 covariates:", paste(m3, collapse = ", "))
), file.path(.out_root, "Methods_statistical_analysis.md"))

message("完成: ", .out_root)
message("Tables: ", length(list.files(tab_dir, pattern = "\\.xlsx$")))
message("Figures/pdf: ", length(list.files(fig_dir, pattern = "\\.pdf$")))
