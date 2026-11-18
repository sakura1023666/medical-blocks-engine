#!/usr/bin/env Rscript
# 预后 2.0 全量发表产物（主库 NHANES+SHHS / 验证 CHARLS）。
# 协变量：主库 Boruta Confirmed 交集 + VIF<5；CHARLS 只用这套做验证。
# Model1 不调整；Model2 年龄+性别；Model3 主库定。
# 只有 NHANES 加权。旧 run/survival 不调用。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
})

.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(.engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
pv2_ensure_dirs()
data_root <- pv2_data_root
out_root <- pv2_out_root
fig_dir <- pv2_fig_dir
tab_dir <- pv2_tab_dir
ckpt_dir <- pv2_ckpt_dir
dir.create(ckpt_dir, recursive = TRUE, showWarnings = FALSE)
message("新项目输出: ", out_root)
message("主库: ", paste(pv2_primary_dbs, collapse = ", "),
        " | 验证: ", paste(pv2_validation_dbs, collapse = ", "))

yn <- function(x, yes = c("Yes", "Y", "1", "Current", "Former", "Ever")) {
  xc <- trimws(as.character(x))
  ifelse(is.na(x) | xc %in% c("", "NA"), NA_character_,
         ifelse(xc %in% yes, "Yes", "No"))
}
num <- function(x) suppressWarnings(as.numeric(x))

message("读取三库")
# ---- NHANES ----
e <- new.env(); load(file.path(data_root, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
base <- as.data.frame(e$baseline)
base$ID <- as.character(base$ID)
sl <- fread(file.path(data_root, "NHANES/最终数据/血脂异常-排除心血管疾病.csv"))
sl[, ID := as.character(SEQN)]
mrt <- new.env(); load(file.path(data_root, "NHANES/nhanes-死亡.Rdata"), envir = mrt)
death <- as.data.frame(mrt$combined_data)
death$ID <- as.character(death$seqn)
death <- death[!duplicated(death$ID), ]
nh <- merge(base, sl[, .(ID, SLD01, DN)], by = "ID")
nh <- nh[!is.na(nh$DN) & nh$DN == 1, ]
nh <- merge(nh, death[, c("ID", "eligstat", "mortstat", "ucod_leading", "permth_exm")], by = "ID")
nh <- nh[nh$eligstat == 1 & nh$mortstat %in% c(0, 1) & !is.na(nh$permth_exm) & nh$permth_exm > 0, ]
nh$Sleep_hours <- num(nh$SLD01)
nh <- nh[!is.na(nh$Sleep_hours) & nh$Sleep_hours > 0 & nh$Sleep_hours < 24, ]
nh$futime_years <- num(nh$permth_exm) / 12
nh$fustatus <- as.integer(nh$mortstat == 1)
nh$cvd_status <- as.integer(nh$fustatus == 1 & nh$ucod_leading %in% c(1, 5))
nh$database <- "NHANES"
nh$Age <- num(nh$Age)
nh$Gender <- ifelse(nh$Gender %in% c("Male", "M", "1"), "Male",
                   ifelse(nh$Gender %in% c("Female", "F", "2"), "Female", NA_character_))
nh$BMI <- num(nh$BMI)
nh$Smoke <- ifelse(nh$Smoke %in% c("Former", "Current"), "Yes", ifelse(nh$Smoke == "Never", "No", NA))
nh$Alcohol <- yn(nh$Alcohol_drinking, c("Yes", "Y", "1"))
nh$Hypertension <- yn(nh$Hypertension, c("Yes", "Y", "1"))
nh$Diabetes <- yn(nh$Diabetes, c("Yes", "Y", "1"))
nh$Education <- ifelse(nh$Education == "Higher education", "Higher",
                       ifelse(nh$Education == "Non-higher education", "Below", NA))
nh$SBP <- num(nh$NBPS)
nh$DBP <- num(nh$NBPD)
nh$survey_weight <- num(nh$WTMEC2YR)
nh$psu <- nh$SDMVPSU
nh$strata <- nh$SDMVSTRA

# ---- CHARLS ----
cenv <- new.env(); load(file.path(data_root, "CHARLS/最终数据/D01_baseline_2011_DN.RData"), envir = cenv)
ch <- as.data.frame(cenv$baseline)
ch$ID <- as.character(ch$ID)
# 与 NHANES / SHHS 同一套 mg/dL 切点，不用自报 Hyperlipidemia
tg <- num(ch$TG); tc <- num(ch$TC); hdl <- num(ch$HDL); ldl <- num(ch$LDL)
ch$lab_dyslipid <- (!is.na(tg) & tg >= 150) | (!is.na(tc) & tc >= 200) |
  (!is.na(ldl) & ldl >= 130) | (!is.na(hdl) & hdl <= 40)
n_charls_lab <- sum(ch$lab_dyslipid %in% TRUE)
ch <- ch[ch$lab_dyslipid %in% TRUE, ]
slc <- fread(file.path(data_root, "CHARLS/CHARLS_2011_sleep_duration_check/CHARLS-2011-sleep-duration_sample_17596.csv"),
             colClasses = c(ID_h_charls = "character"))
slc[, ID := as.character(ID_h_charls)]
ch <- merge(ch, slc[, .(ID, sleep = da049_sleep_hrs)], by = "ID", all.x = TRUE)
dth <- fread(file.path(data_root, "CHARLS/merged_baseline_death.csv"), colClasses = c(ID = "character"))
dth[, ID := as.character(ID)]
ch <- merge(ch, dth[, .(ID, death_status)], by = "ID", all.x = TRUE)
ch$Sleep_hours <- num(ch$sleep)
ch <- ch[!is.na(ch$Sleep_hours) & ch$Sleep_hours > 0 & ch$Sleep_hours <= 15 & !is.na(ch$death_status), ]
.cf <- c("E:/01block/01Block-new-Final/run/prognosis_v2/charls_followup.R",
         "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/charls_followup.R")
source(.cf[file.exists(.cf)][1], local = FALSE)
.pf <- c("E:/01block/01Block-new-Final/run/prognosis_v2/pv2_front.R",
         "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/pv2_front.R")
source(.pf[file.exists(.pf)][1], local = FALSE)
fu <- charls_assign_followup(ch$exb001_1, ch$exb001_2, ch$exb002, ch$death_status == 1)
ch$futime_years <- fu$time
ch$fustatus <- fu$event
eol_cause <- fread(file.path(data_root, "CHARLS/Exit_Interview/charls_eol_cause.csv"),
                    colClasses = c(ID = "character"))
eol_cause[, ID := as.character(ID)]
ch <- merge(ch, eol_cause[, .(ID, ragcod)], by = "ID", all.x = TRUE)
ch$cvd_status <- ifelse(ch$fustatus == 1 & is.na(ch$ragcod), NA_integer_,
                        as.integer(ch$fustatus == 1 & ch$ragcod == 2))
ch$database <- "CHARLS"
ch$Age <- num(ch$Age)
ch$Gender <- ifelse(as.character(ch$Gender) %in% c("Male", "M", "1"), "Male",
                   ifelse(as.character(ch$Gender) %in% c("Female", "F", "2"), "Female", NA_character_))
ch$BMI <- num(ch$BMI)
ch$Smoke <- ifelse(as.character(ch$Smoke) == "Current", "Yes", ifelse(as.character(ch$Smoke) == "Never", "No", NA))
ch$Alcohol <- yn(ch$Alcohol_drinking, c("Yes", "Y", "1"))
ch$Hypertension <- yn(ch$Hypertension, c("Yes", "Y", "1"))
ch$Diabetes <- yn(ch$Diabetes, c("Yes", "Y", "1"))
ch$Education <- ifelse(grepl("Above", as.character(ch$Education)), "Higher",
                       ifelse(grepl("Below", as.character(ch$Education)), "Below", NA))
ch$SBP <- num(ch$NBPS)
ch$DBP <- num(ch$NBPD)
ch$survey_weight <- NA_real_
ch$psu <- NA
ch$strata <- NA
message(sprintf(
  "CHARLS follow-up: deaths=%d solar=%d lunar=%d early=%d late=%d date_missing=%d median_years=%.2f",
  sum(ch$fustatus == 1), attr(fu$time, "n_solar"), attr(fu$time, "n_lunar"),
  attr(fu$time, "n_early"), attr(fu$time, "n_late"), attr(fu$time, "n_date_missing"),
  stats::median(ch$futime_years)
))

# ---- SHHS ----
s1 <- fread(file.path(data_root, "SHHS(1)/EXCEL/shhs1-dataset-0.18.0.csv"),
            select = c("nsrrid", "hrswd02", "chol", "hdl", "trig", "age_s1", "gender", "bmi_s1",
                       "smokstat_s1", "alcoh", "educat", "htnderv_s1", "parrptdiab", "systbp"))
cv <- fread(file.path(data_root, "SHHS(1)/EXCEL/shhs-cvd-summary-dataset-0.18.0.csv"),
            select = c("nsrrid", "vital", "censdate", "cvd_death"))
sh <- merge(s1, cv, by = "nsrrid")
ldl <- ifelse(!is.na(sh$trig) & sh$trig < 400 & !is.na(sh$chol) & !is.na(sh$hdl),
              sh$chol - sh$hdl - sh$trig / 5, NA_real_)
abn <- (!is.na(sh$trig) & sh$trig >= 150) | (!is.na(sh$chol) & sh$chol >= 200) |
  (!is.na(ldl) & ldl >= 130) | (!is.na(sh$hdl) & sh$hdl <= 40)
sh <- sh[abn %in% TRUE]
sh$Sleep_hours <- num(sh$hrswd02)
sh <- sh[!is.na(sh$Sleep_hours) & sh$Sleep_hours > 0 & sh$Sleep_hours < 24 & !is.na(sh$vital) & sh$censdate > 0]
sh$futime_years <- num(sh$censdate) / 365.25
sh$fustatus <- as.integer(sh$vital == 0)
sh$cvd_status <- as.integer(sh$cvd_death == 1)
sh$database <- "SHHS"
sh$ID <- as.character(sh$nsrrid)
sh$Age <- num(sh$age_s1)
sh$Gender <- ifelse(sh$gender == 1, "Male", ifelse(sh$gender == 2, "Female", NA))
sh$BMI <- num(sh$bmi_s1)
sh$Smoke <- ifelse(sh$smokstat_s1 %in% c(1, 2), "Yes", ifelse(sh$smokstat_s1 == 0, "No", NA))
sh$Alcohol <- ifelse(!is.na(sh$alcoh) & sh$alcoh > 0, "Yes", ifelse(!is.na(sh$alcoh) & sh$alcoh == 0, "No", NA))
sh$Hypertension <- ifelse(sh$htnderv_s1 == 1, "Yes", ifelse(sh$htnderv_s1 == 0, "No", NA))
sh$Diabetes <- ifelse(sh$parrptdiab == 1, "Yes", ifelse(sh$parrptdiab == 0, "No", NA))
sh$Education <- ifelse(sh$educat %in% c(3, 4), "Higher", ifelse(sh$educat %in% c(1, 2), "Below", NA))
sh$SBP <- num(sh$systbp)
sh$DBP <- num(sh$diasbp)
sh$survey_weight <- NA_real_
sh$psu <- NA
sh$strata <- NA

keep <- c("ID", "database", "Age", "Gender", "BMI", "Smoke", "Alcohol", "Hypertension",
          "Diabetes", "Education", "SBP", "DBP", "Sleep_hours", "futime_years", "fustatus",
          "cvd_status", "survey_weight", "psu", "strata")
.take <- function(d) {
  d <- as.data.frame(d)
  d[, intersect(keep, names(d)), drop = FALSE]
}
dbs <- list(NHANES = .take(nh), CHARLS = .take(ch), SHHS = .take(sh))
for (nm in names(dbs)) {
  d <- dbs[[nm]]
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d$fustatus_f <- factor(d$fustatus, levels = c(0, 1))
  d <- d[!is.na(d$Age) & d$Age >= 45, ]
  dbs[[nm]] <- d
  message(nm, " 保留年龄>=45 n=", nrow(d), " deaths=", sum(d$fustatus == 1, na.rm = TRUE))
}
nh0 <- dbs$NHANES
dbs$NHANES <- nh0[!is.na(nh0$survey_weight) & nh0$survey_weight > 0 & !is.na(nh0$psu) & !is.na(nh0$strata), ]
message("NHANES 有权重 n=", nrow(dbs$NHANES), "（插补前锁定，三模型同一批人）")
if (identical(Sys.getenv("PV2_SAVE_BEFORE_MI"), "1")) {
  saveRDS(dbs, file.path(ckpt_dir, "before_imputation_dbs.rds"))
  quit(save = "no")
}
dbs <- pv2_impute_databases(dbs, tab_dir)

cands <- c("Age", "Gender", "BMI", "Smoke", "Alcohol", "Hypertension", "Diabetes", "Education", "SBP")
# 血脂定义列不进入候选池。睡眠时长进入 Boruta / SHAP，与原文把暴露放进特征筛选一致，但不进入 Model 3。

message("Boruta + SHAP")
bor_csv <- pv2_artifact("Boruta_by_database.csv", must_exist = FALSE)
shap_csv <- pv2_artifact("SHAP_by_database.csv", must_exist = FALSE)
if (is.na(bor_csv)) bor_csv <- file.path(ckpt_dir, "Boruta_by_database.csv")
if (is.na(shap_csv)) shap_csv <- file.path(ckpt_dir, "SHAP_by_database.csv")
reuse_boruta <- (identical(Sys.getenv("REUSE_BORUTA"), "1") ||
  file.exists("E:/01block/01Block-new-Final/run/prognosis_v2/.reuse_boruta") ||
  file.exists("/mnt/e/01block/01Block-new-Final/run/prognosis_v2/.reuse_boruta")) &&
  file.exists(bor_csv) && file.exists(shap_csv)
if (reuse_boruta) {
  message("复用已有 Boruta / SHAP")
  bor_all <- as.data.frame(fread(bor_csv))
  shap_all <- as.data.frame(fread(shap_csv))
} else {
bor_rows <- list()
shap_rows <- list()
bor_obj <- list()
shap_long <- list()
# 协变量筛选只在主库跑；CHARLS 为外验，直接套用主库 Model 3，不参与 Boruta/SHAP/图2。
for (nm in pv2_primary_dbs) {
  d <- dbs[[nm]]
  use <- c("Sleep_hours", cands)
  use <- use[vapply(use, function(v) v %in% names(d) && sum(!is.na(d[[v]])) > 50 && length(unique(na.omit(d[[v]]))) > 1, logical(1))]
  dd <- d[stats::complete.cases(d[, c("fustatus", "futime_years", use)]) & d$futime_years > 0, c("fustatus", "futime_years", use)]
  dd$fustatus_f <- factor(dd$fustatus, levels = c(0, 1))
  for (v in use) if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
  set.seed(41904528)
  # Jin 2026 Fig 2：Boruta 默认 randomForest Z 分数（mean decrease accuracy），500 棵树。
  message(nm, " Boruta Z-score n=", nrow(dd))
  bor <- Boruta::Boruta(
    stats::as.formula(paste("fustatus_f ~", paste(use, collapse = "+"))),
    data = dd, doTrace = 1, maxRuns = 100, ntree = 500
  )
  bor <- Boruta::TentativeRoughFix(bor)
  bor_obj[[nm]] <- bor
  st <- Boruta::attStats(bor)
  st$variable <- rownames(st)
  st$database <- nm
  bor_rows[[nm]] <- st
  # SHAP：xgboost survival:cox 的 TreeSHAP，单位是 log-hazard，不是二分类概率。
  mm <- stats::model.matrix(stats::as.formula(paste("~", paste(use, collapse = "+"))), data = dd)
  mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
  lab <- ifelse(dd$fustatus == 1, dd$futime_years, -dd$futime_years)
  fit <- xgboost::xgboost(
    data = mm, label = lab, nrounds = 80, max_depth = 3, eta = 0.05,
    objective = "survival:cox", verbose = 0
  )
  ex <- predict(fit, newdata = mm, predcontrib = TRUE)
  ex <- ex[, colnames(ex) != "BIAS", drop = FALSE]
  imp <- sort(colMeans(abs(ex)), decreasing = TRUE)
  shap_rows[[nm]] <- data.frame(
    database = nm, variable = names(imp), mean_abs_shap = as.numeric(imp),
    stringsAsFactors = FALSE
  )
  # 蜂群图保留最多 1500 人，平均绝对 SHAP 用全样本。
  set.seed(41904528)
  idx <- sample(seq_len(nrow(ex)), min(1500L, nrow(ex)))
  sl <- as.data.frame(ex[idx, , drop = FALSE])
  sl$i <- seq_len(nrow(sl))
  sl <- data.table::melt(as.data.table(sl), id.vars = "i", variable.name = "variable", value.name = "shap")
  sl$database <- nm
  shap_long[[nm]] <- as.data.frame(sl)
  message(nm, " Boruta + SHAP done")
}
bor_all <- do.call(rbind, bor_rows)
shap_all <- do.call(rbind, shap_rows)
fwrite(bor_all, file.path(ckpt_dir, "Boruta_by_database.csv"))
fwrite(shap_all, file.path(ckpt_dir, "SHAP_by_database.csv"))
saveRDS(bor_obj, file.path(ckpt_dir, "Boruta_objects.rds"))
saveRDS(do.call(rbind, shap_long), file.path(ckpt_dir, "SHAP_long.rds"))
}

confirmed <- lapply(split(bor_all, bor_all$database), function(x) x$variable[x$decision == "Confirmed"])
# Model 3 = 主库 NHANES∩SHHS Confirmed 交集；CHARLS 不参与筛选。
shared <- Reduce(intersect, confirmed[pv2_primary_dbs])
shared <- setdiff(shared, c("Age", "Gender", "Sleep_hours"))
message("主库都确认的额外变量: ", paste(shared, collapse = ", "))
for (nm in pv2_primary_dbs) {
  message(sprintf("  %s [Primary] Confirmed: %s", nm, paste(confirmed[[nm]], collapse = ", ")))
}

vif_drop <- character(0)
vif_tab <- list()
if (length(shared)) {
  for (nm in pv2_primary_dbs) {
    d <- dbs[[nm]]
    vv <- c("Age", "Gender", shared)
    dd <- d[stats::complete.cases(d[, c("fustatus", vv)]), c("fustatus", vv)]
    v <- tryCatch(car::vif(stats::lm(fustatus ~ ., data = dd)), error = function(e) {
      message(nm, " VIF failed: ", conditionMessage(e))
      NULL
    })
    if (!is.null(v)) {
      if (is.matrix(v)) {
        stat <- if ("GVIF^(1/(2*Df))" %in% colnames(v)) v[, "GVIF^(1/(2*Df))"]^2 else v[, 1]
        vif_tab[[nm]] <- data.frame(database = nm, variable = rownames(v), VIF = round(as.numeric(stat), 3))
      } else {
        vif_tab[[nm]] <- data.frame(database = nm, variable = names(v), VIF = round(as.numeric(v), 3))
      }
    }
  }
}
if (length(vif_tab)) {
  vt <- do.call(rbind, vif_tab)
  fwrite(vt, file.path(tab_dir, "Table S2. VIF.csv"))
  fwrite(vt, file.path(ckpt_dir, "Table S2. VIF.csv"))
  bad <- unique(vt$variable[vt$VIF >= 5])
  vif_drop <- intersect(shared, bad)
  shared <- setdiff(shared, vif_drop)
}
m3 <- unique(c("Age", "Gender", shared))
writeLines(c(
  "角色：NHANES、SHHS=主库；CHARLS=验证库。",
  "协变量按 Jin 2026：Boruta + SHAP；Model 3 取主库 Confirmed 交集，再在主库上 VIF<5。",
  "Model 1 不调整。Model 2 = Age + Gender。",
  paste("Model 3 =", paste(m3, collapse = " + ")),
  paste("VIF>=5 剔除（仅主库判定）:", paste(vif_drop, collapse = ", ")),
  "CHARLS 为外部验证库：不跑 Boruta/SHAP，不参与定模；验证时直接使用同一套 Model 3。",
  "血脂定义列未进入候选池。血脂异常切点：TG>=150 或 TC>=200 或 LDL>=130 或 HDL<=40（mg/dL）。只有 NHANES 的 Cox 使用 WTMEC2YR。",
  "MICE（cart, m=5, seed=1234）；Cox 用 Rubin。睡眠、随访、死亡、权重、血脂不插补。",
  "年龄>=45。性别缺失不排除，随协变量 MICE。",
  "Boruta: 仅主库（NHANES、SHHS）；randomForest Z-score，500 树，maxRuns=100，TentativeRoughFix。睡眠时长不进入 Model 3。"
), file.path(ckpt_dir, "Covariate_selection_note.txt"))
message("Model3 (主库定): ", paste(m3, collapse = ", "))

cox_one <- function(d, rhs, model) {
  d <- d[stats::complete.cases(d[, c("futime_years", "fustatus", "Sleep_Group", all.vars(stats::as.formula(paste("~", rhs))))]), ]
  d$time <- d$futime_years
  d$event <- d$fustatus
  if (identical(d$database[1], "NHANES") && any(!is.na(d$survey_weight))) {
    d <- d[!is.na(d$survey_weight) & d$survey_weight > 0 & !is.na(d$psu) & !is.na(d$strata), ]
    options(survey.lonely.psu = "adjust")
    des <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = d, nest = TRUE)
    fit <- survey::svycoxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), design = des)
    co <- summary(fit)$coefficients
    ci <- summary(fit)$conf.int
    data.frame(database = "NHANES", model = model, term = rownames(co),
               HR = round(ci[, 1], 3), lo = round(ci[, 3], 3), hi = round(ci[, 4], 3),
               p = signif(co[, "Pr(>|z|)"], 3), weighted = TRUE, stringsAsFactors = FALSE)
  } else {
    fit <- survival::coxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), data = d, ties = "efron")
    s <- summary(fit)
    data.frame(database = d$database[1], model = model, term = rownames(s$conf.int),
               HR = round(s$conf.int[, 1], 3), lo = round(s$conf.int[, 3], 3), hi = round(s$conf.int[, 4], 3),
               p = signif(s$coefficients[, "Pr(>|z|)"], 3), weighted = FALSE, stringsAsFactors = FALSE)
  }
}

message("Cox / 人年 / RCS / KM / ROC / 中介 / 亚组")
rhs2 <- "Sleep_Group + Age + Gender"
rhs3 <- paste(c("Sleep_Group", m3), collapse = " + ")
cox_tabs <- list()
py_tabs <- list()
rcs_df <- list()
km_df <- list()
roc_df <- list()
youden <- list()
sub_df <- list()
med_df <- list()
for (nm in names(dbs)) {
  d <- dbs[[nm]]
  cox_tabs[[length(cox_tabs) + 1L]] <- tryCatch(cox_one(d, "Sleep_Group", "Model1"), error = function(e) NULL)
  cox_tabs[[length(cox_tabs) + 1L]] <- tryCatch(cox_one(d, rhs2, "Model2"), error = function(e) NULL)
  cox_tabs[[length(cox_tabs) + 1L]] <- tryCatch(cox_one(d, rhs3, "Model3"), error = function(e) NULL)
  # 5 年窗口（CHARLS 随访只有 2 年，跳过）
  if (nm != "CHARLS") {
    d5 <- d
    d5$fustatus <- as.integer(d$fustatus == 1 & d$futime_years <= 5)
    d5$futime_years <- pmin(d$futime_years, 5)
    cox_tabs[[length(cox_tabs) + 1L]] <- tryCatch(cox_one(d5, rhs3, "S3_horizon5y_Model3"), error = function(e) NULL)
  }
  d$time <- d$futime_years
  d$event <- d$fustatus
  for (g in levels(d$Sleep_Group)) {
    sub <- d[d$Sleep_Group == g & !is.na(d$Sleep_Group), ]
    py_tabs[[length(py_tabs) + 1L]] <- data.frame(
      database = nm, Sleep_Group = g, N = nrow(sub),
      Events = sum(sub$event == 1, na.rm = TRUE),
      Person_years = round(sum(sub$time, na.rm = TRUE), 1),
      stringsAsFactors = FALSE)
  }
  # RCS
  fit <- tryCatch(survival::coxph(Surv(time, event) ~ splines::ns(Sleep_hours, df = 3) + Age + Gender, data = d), error = function(e) NULL)
  if (!is.null(fit)) {
    grid <- seq(4, 11, by = 0.1)
    nd <- data.frame(Sleep_hours = grid, Age = median(d$Age, na.rm = TRUE), Gender = "Female")
    lp <- as.numeric(predict(fit, newdata = nd, type = "lp"))
    rcs_df[[nm]] <- data.frame(database = nm, hours = grid, HR = exp(lp - min(lp)))
  }
  sf <- survival::survfit(Surv(time, event) ~ Sleep_Group, data = d)
  ss <- summary(sf)
  km_df[[nm]] <- data.frame(database = nm, time = ss$time, surv = ss$surv, strata = ss$strata)
  # ROC at 2 years
  y <- as.integer(d$fustatus == 1 & d$futime_years <= 2)
  ok <- stats::complete.cases(d[, c("Sleep_hours", "Age", "Gender")]) & !is.na(y)
  if (length(unique(y[ok])) == 2) {
    dd <- d[ok, ]
    dd$y <- y[ok]
    dd$Gender <- factor(dd$Gender)
    w <- if (nm == "NHANES") dd$survey_weight else NULL
    fit <- stats::glm(dd$y ~ Sleep_hours + Age + Gender, data = dd, family = stats::binomial())
    roc <- pROC::roc(dd$y, stats::predict(fit, type = "response"), weights = w, quiet = TRUE, direction = "<")
    cd <- pROC::coords(roc, ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE)
    roc_df[[nm]] <- data.frame(database = nm, fpr = 1 - cd$specificity, tpr = cd$sensitivity)
    best <- which.max(cd$sensitivity + cd$specificity - 1)
    youden[[nm]] <- data.frame(database = nm, AUC = round(as.numeric(pROC::auc(roc)), 3),
                               cutoff = round(cd$threshold[best], 3),
                               sensitivity = round(cd$sensitivity[best], 3),
                               specificity = round(cd$specificity[best], 3))
  }
}
# 亚组与 Table 1–3 的 csv 由 pv2_publish_tables.R 写出。
# Table 4 xlsx、S6–S8 不在该脚本里覆盖：表4见 pv2_export_pub_xlsx.R，S6–S8 见 pv2_s6_s7_s8.R。

cox_out <- do.call(rbind, cox_tabs)
fwrite(cox_out[cox_out$model %in% c("Model1", "Model2", "Model3"), ], file.path(tab_dir, "Table 3. Cox.csv"))
fwrite(cox_out[cox_out$model == "S3_horizon5y_Model3", ], file.path(tab_dir, "Table S3. Cox 5-year horizon.csv"))
py <- do.call(rbind, py_tabs)
py$Rate_per_10000py <- round(1e4 * py$Events / py$Person_years, 2)
fwrite(py, file.path(tab_dir, "Table 2. Person-years.csv"))
fwrite(do.call(rbind, youden), file.path(tab_dir, "Table S4. Youden.csv"))
if (length(med_df)) fwrite(do.call(rbind, med_df), file.path(tab_dir, "Table mediation horizon.csv"))
pub <- c("E:/01block/01Block-new-Final/run/prognosis_v2/pv2_publish_tables.R",
         "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/pv2_publish_tables.R")
source(pub[file.exists(pub)][1], local = FALSE)
message("表已写出。图由 run/prognosis_v2/redraw_pub_figures.R 按原文面板重画，本脚本不再写简图。")
message("完成: ", out_root)
