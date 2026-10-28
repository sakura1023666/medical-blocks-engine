#!/usr/bin/env Rscript
# 按 Jin 2026 的图序重画三库拼图，并用项目纳排框画 Figure 1。
# 不重跑 Cox 表。Boruta 需重拟合才能画出 Z 分数轨迹（原文 Fig 2B）。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
})

engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/attrition_log.R"), local = FALSE)
pv2_ensure_dirs()
data_root <- pv2_data_root
out_root <- pv2_out_root
fig_dir <- pv2_fig_dir
tab_dir <- pv2_tab_dir
ckpt_dir <- pv2_ckpt_dir

num <- function(x) suppressWarnings(as.numeric(x))
yn <- function(x, yes = c("Yes", "Y", "1")) {
  xc <- trimws(as.character(x))
  ifelse(is.na(x) | xc %in% c("", "NA"), NA_character_, ifelse(xc %in% yes, "Yes", "No"))
}
fmt_p <- function(p) {
  vapply(p, function(x) {
    x <- suppressWarnings(as.numeric(x)[1L])
    if (!is.finite(x)) return("未计算")
    if (x < 0.001) return("<0.001")
    sprintf("%.3f", x)
  }, character(1))
}

message("读取三库并记纳排")
# ---- NHANES ----
e <- new.env(); load(file.path(data_root, "NHANES/D01_baseline_NHANES_0920.RData"), envir = e)
base <- as.data.frame(e$baseline)
n_nh_base <- nrow(base)
base$ID <- as.character(base$ID)
sl <- fread(file.path(data_root, "NHANES/最终数据/血脂异常-排除心血管疾病.csv"))
sl[, ID := as.character(SEQN)]
n_nh_dys <- nrow(sl)
nh <- merge(base, sl[, .(ID, SLD01, DN)], by = "ID")
nh <- nh[!is.na(nh$DN) & nh$DN == 1, ]
n_nh_dn <- nrow(nh)
mrt <- new.env(); load(file.path(data_root, "NHANES/nhanes-死亡.Rdata"), envir = mrt)
death <- as.data.frame(mrt$combined_data)
death$ID <- as.character(death$seqn)
death <- death[!duplicated(death$ID), ]
nh <- merge(nh, death[, c("ID", "eligstat", "mortstat", "ucod_leading", "permth_exm")], by = "ID")
n_nh_linked <- nrow(nh)
nh <- nh[nh$eligstat == 1 & nh$mortstat %in% c(0, 1) & !is.na(nh$permth_exm) & nh$permth_exm > 0, ]
n_nh_elig <- nrow(nh)
nh$Sleep_hours <- num(nh$SLD01)
nh <- nh[!is.na(nh$Sleep_hours) & nh$Sleep_hours > 0 & nh$Sleep_hours < 24, ]
n_nh <- nrow(nh)
nh$futime_years <- num(nh$permth_exm) / 12
nh$fustatus <- as.integer(nh$mortstat == 1)
nh$database <- "NHANES"
nh$Age <- num(nh$Age)
nh$Gender <- ifelse(nh$Gender %in% c("Male", "M", "1"), "Male",
                   ifelse(nh$Gender %in% c("Female", "F", "2"), "Female", NA_character_))
nh$BMI <- num(nh$BMI)
nh$Smoke <- ifelse(nh$Smoke %in% c("Former", "Current"), "Yes", ifelse(nh$Smoke == "Never", "No", NA))
nh$Hypertension <- yn(nh$Hypertension, c("Yes", "Y", "1"))
nh$Diabetes <- yn(nh$Diabetes, c("Yes", "Y", "1"))
nh$Alcohol <- yn(nh$Alcohol_drinking, c("Yes", "Y", "1"))
nh$Education <- ifelse(nh$Education == "Higher education", "Higher",
                       ifelse(nh$Education == "Non-higher education", "Below", NA))
nh$SBP <- num(nh$NBPS)
nh$survey_weight <- num(nh$WTMEC2YR)

# ---- CHARLS ----
cenv <- new.env(); load(file.path(data_root, "CHARLS/最终数据/D01_baseline_2011_DN.RData"), envir = cenv)
ch <- as.data.frame(cenv$baseline)
n_ch_base <- nrow(ch)
ch$ID <- as.character(ch$ID)
tg <- num(ch$TG); tc <- num(ch$TC); hdl <- num(ch$HDL); ldl <- num(ch$LDL)
ch$lab <- (!is.na(tg) & tg >= 150) | (!is.na(tc) & tc >= 200) | (!is.na(ldl) & ldl >= 130) | (!is.na(hdl) & hdl <= 40)
n_ch_lab <- sum(ch$lab %in% TRUE)
ch <- ch[ch$lab %in% TRUE, ]
slc <- fread(file.path(data_root, "CHARLS/CHARLS_2011_sleep_duration_check/CHARLS-2011-sleep-duration_sample_17596.csv"),
             colClasses = c(ID_h_charls = "character"))
slc[, ID := as.character(ID_h_charls)]
ch <- merge(ch, slc[, .(ID, sleep = da049_sleep_hrs)], by = "ID", all.x = TRUE)
n_ch_sleep <- sum(!is.na(num(ch$sleep)) & num(ch$sleep) > 0 & num(ch$sleep) <= 15)
dth <- fread(file.path(data_root, "CHARLS/merged_baseline_death.csv"), colClasses = c(ID = "character"))
ch <- merge(ch, dth[, .(ID, death_status)], by = "ID", all.x = TRUE)
ch$Sleep_hours <- num(ch$sleep)
ch <- ch[!is.na(ch$Sleep_hours) & ch$Sleep_hours > 0 & ch$Sleep_hours <= 15 & !is.na(ch$death_status), ]
n_ch <- nrow(ch)
.cf <- c("E:/01block/01Block-new-Final/run/prognosis_v2/charls_followup.R",
         "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/charls_followup.R")
source(.cf[file.exists(.cf)][1], local = FALSE)
.pf <- c("E:/01block/01Block-new-Final/run/prognosis_v2/pv2_front.R",
         "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/pv2_front.R")
source(.pf[file.exists(.pf)][1], local = FALSE)
fu <- charls_assign_followup(ch$exb001_1, ch$exb001_2, ch$exb002, ch$death_status == 1)
ch$futime_years <- fu$time
ch$fustatus <- fu$event
ch$database <- "CHARLS"
ch$Age <- num(ch$Age)
ch$Gender <- ifelse(as.character(ch$Gender) %in% c("Male", "M", "1"), "Male",
                   ifelse(as.character(ch$Gender) %in% c("Female", "F", "2"), "Female", NA_character_))
ch$BMI <- num(ch$BMI)
ch$Smoke <- ifelse(as.character(ch$Smoke) == "Current", "Yes", ifelse(as.character(ch$Smoke) == "Never", "No", NA))
ch$Hypertension <- yn(ch$Hypertension, c("Yes", "Y", "1"))
ch$Diabetes <- yn(ch$Diabetes, c("Yes", "Y", "1"))
ch$Alcohol <- yn(ch$Alcohol_drinking, c("Yes", "Y", "1"))
ch$Education <- ifelse(grepl("Above", as.character(ch$Education)), "Higher",
                       ifelse(grepl("Below", as.character(ch$Education)), "Below", NA))
ch$SBP <- num(ch$NBPS)

# ---- SHHS ----
s1 <- fread(file.path(data_root, "SHHS(1)/EXCEL/shhs1-dataset-0.18.0.csv"),
            select = c("nsrrid", "hrswd02", "chol", "hdl", "trig", "age_s1", "gender", "bmi_s1",
                       "smokstat_s1", "alcoh", "educat", "htnderv_s1", "parrptdiab", "systbp"))
cv <- fread(file.path(data_root, "SHHS(1)/EXCEL/shhs-cvd-summary-dataset-0.18.0.csv"),
            select = c("nsrrid", "vital", "censdate"))
sh0 <- merge(s1, cv, by = "nsrrid")
n_sh_base <- nrow(sh0)
ldl <- ifelse(!is.na(sh0$trig) & sh0$trig < 400 & !is.na(sh0$chol) & !is.na(sh0$hdl),
              sh0$chol - sh0$hdl - sh0$trig / 5, NA_real_)
abn <- (!is.na(sh0$trig) & sh0$trig >= 150) | (!is.na(sh0$chol) & sh0$chol >= 200) |
  (!is.na(ldl) & ldl >= 130) | (!is.na(sh0$hdl) & sh0$hdl <= 40)
n_sh_lab <- sum(abn %in% TRUE)
sh <- sh0[abn %in% TRUE]
sh$Sleep_hours <- num(sh$hrswd02)
sh <- sh[!is.na(sh$Sleep_hours) & sh$Sleep_hours > 0 & sh$Sleep_hours < 24 & !is.na(sh$vital) & sh$censdate > 0]
n_sh <- nrow(sh)
sh$futime_years <- num(sh$censdate) / 365.25
sh$fustatus <- as.integer(sh$vital == 0)
sh$database <- "SHHS"
sh$Age <- num(sh$age_s1)
sh$Gender <- ifelse(sh$gender == 1, "Male", ifelse(sh$gender == 2, "Female", NA))
sh$BMI <- num(sh$bmi_s1)
sh$Smoke <- ifelse(sh$smokstat_s1 %in% c(1, 2), "Yes", ifelse(sh$smokstat_s1 == 0, "No", NA))
sh$Hypertension <- ifelse(sh$htnderv_s1 == 1, "Yes", ifelse(sh$htnderv_s1 == 0, "No", NA))
sh$Diabetes <- ifelse(sh$parrptdiab == 1, "Yes", ifelse(sh$parrptdiab == 0, "No", NA))
sh$Alcohol <- ifelse(!is.na(sh$alcoh) & sh$alcoh > 0, "Yes", ifelse(!is.na(sh$alcoh) & sh$alcoh == 0, "No", NA))
sh$Education <- ifelse(sh$educat %in% c(3, 4), "Higher", ifelse(sh$educat %in% c(1, 2), "Below", NA))
sh$SBP <- num(sh$systbp)

prep <- function(d) {
  d <- as.data.frame(d)
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d$time <- d$futime_years
  d$event <- d$fustatus
  d <- d[!is.na(d$Age) & d$Age >= 45, ]
  d
}
dbs <- list(NHANES = prep(nh), CHARLS = prep(ch), SHHS = prep(sh))
imp_rds <- if (exists("pv2_artifact", mode = "function")) pv2_artifact("imputed_dbs.rds", must_exist = FALSE) else NA_character_
if (is.na(imp_rds) || !file.exists(imp_rds)) imp_rds <- file.path(tab_dir, "imputed_dbs.rds")
if (file.exists(imp_rds)) {
  message("图使用列对齐后的插补数据")
  saved <- readRDS(imp_rds)
  for (nm in names(saved)) {
    d <- as.data.frame(saved[[nm]])
    d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
    d$time <- d$futime_years
    d$event <- d$fustatus
    dbs[[nm]] <- d
  }
} else {
  nh0 <- dbs$NHANES
  dbs$NHANES <- nh0[!is.na(nh0$survey_weight) & nh0$survey_weight > 0 & !is.na(nh0$psu) & !is.na(nh0$strata), ]
  dbs <- pv2_impute_databases(dbs, tab_dir)
  for (nm in names(dbs)) {
    dbs[[nm]]$time <- dbs[[nm]]$futime_years
    dbs[[nm]]$event <- dbs[[nm]]$fustatus
  }
}

# 纳排底账只由图1（attrition_draw_outcome_figure）写出，禁止再写年龄门之前的旧筛选。

message("Boruta / SHAP 图读取 Z 分数对象和 log-hazard SHAP")
only_kmrcs <- file.exists(file.path(engine, "run/prognosis_v2/.only_kmrcs"))
bor_obj <- NULL
shap_df <- NULL
if (!only_kmrcs) {
  bor_rds <- if (exists("pv2_artifact", mode = "function")) pv2_artifact("Boruta_objects.rds", must_exist = FALSE) else NA_character_
  shap_rds <- if (exists("pv2_artifact", mode = "function")) pv2_artifact("SHAP_long.rds", must_exist = FALSE) else NA_character_
  if (is.na(bor_rds)) bor_rds <- file.path(tab_dir, "Boruta_objects.rds")
  if (is.na(shap_rds)) shap_rds <- file.path(tab_dir, "SHAP_long.rds")
  if (!file.exists(bor_rds) || !file.exists(shap_rds)) {
    stop("缺少 Boruta_objects.rds 或 SHAP_long.rds，先跑 run_prognosis_v2_literature.R")
  }
  bor_obj <- readRDS(bor_rds)
  shap_df <- as.data.frame(readRDS(shap_rds))
}
if (only_kmrcs) message("跳过 Boruta，只重画 KM 与 RCS")

theme_pub <- function() {
  theme_bw(base_size = 11) +
    theme(strip.background = element_rect(fill = "grey95"),
          strip.text = element_text(face = "bold"),
          legend.position = "bottom")
}
pv2_fig2_database <- function(bor, shap, db, mean_tab) {
  h <- as.data.frame(bor$ImpHistory)
  h$iter <- seq_len(nrow(h))
  st <- Boruta::attStats(bor)
  dec <- setNames(as.character(st$decision), rownames(st))
  vars <- setdiff(colnames(h), "iter")
  box <- do.call(rbind, lapply(vars, function(v) {
    data.frame(variable = v, z = h[[v]], stringsAsFactors = FALSE)
  }))
  box$decision <- dec[box$variable]
  box$decision[is.na(box$decision)] <- "Shadow"
  med <- tapply(box$z, box$variable, stats::median, na.rm = TRUE)
  box$variable <- factor(box$variable, levels = names(sort(med)))
  pal <- c(Confirmed = "#2ca02c", Rejected = "#d62728", Tentative = "#ffbf00", Shadow = "#1f77b4")
  th <- theme_classic(base_size = 8) +
    theme(axis.text.x = element_text(angle = 55, hjust = 1, size = 5.5),
          legend.position = "bottom", legend.key.size = grid::unit(0.3, "cm"))
  pA <- ggplot(box, aes(variable, z, fill = decision)) +
    geom_boxplot(outlier.size = 0.25, linewidth = 0.25) +
    scale_fill_manual(values = pal, name = NULL) +
    labs(x = "Attributes", y = "Importance", title = "A") + th
  real <- intersect(rownames(st), colnames(h))
  lines <- do.call(rbind, lapply(real, function(v) {
    data.frame(iter = h$iter, variable = v, z = h[[v]], stringsAsFactors = FALSE)
  }))
  lines$group <- ifelse(lines$variable == "Sleep_hours", "Sleep duration", "Other")
  pB <- ggplot(lines, aes(iter, z, group = variable, color = group)) +
    geom_line(linewidth = 0.3) +
    scale_color_manual(values = c("Sleep duration" = "#e74c3c", "Other" = "#4c78a8"), name = NULL) +
    labs(x = "Iteration", y = "Boruta Z-score (mean decrease accuracy)", title = "B") +
    theme_classic(base_size = 8) +
    theme(legend.position = "bottom", legend.key.size = grid::unit(0.3, "cm"))
  sh <- shap[shap$database == db, , drop = FALSE]
  sh$group <- ifelse(grepl("^Sleep", sh$variable), "Sleep duration", "Other")
  ord <- sort(tapply(abs(sh$shap), sh$variable, mean))
  sh$variable <- factor(sh$variable, levels = names(ord))
  pC <- ggplot(sh, aes(shap, variable, color = group)) +
    geom_jitter(height = 0.15, width = 0, size = 0.2, alpha = 0.4) +
    geom_vline(xintercept = 0, linewidth = 0.25) +
    scale_color_manual(values = c("Sleep duration" = "#e74c3c", "Other" = "grey55"), name = NULL) +
    labs(x = "SHAP value (log-hazard)", y = "Feature", title = "C") +
    theme_classic(base_size = 8) +
    theme(legend.position = "bottom", legend.key.size = grid::unit(0.3, "cm"))
  md <- mean_tab[mean_tab$database == db, c("variable", "mean_abs_shap"), drop = FALSE]
  names(md)[2] <- "mean_abs"
  md$group <- ifelse(grepl("^Sleep", md$variable), "Sleep duration", "Other")
  md$variable <- factor(md$variable, levels = names(sort(setNames(md$mean_abs, md$variable))))
  pD <- ggplot(md, aes(mean_abs, variable, fill = group)) +
    geom_col(width = 0.72) +
    scale_fill_manual(values = c("Sleep duration" = "#e74c3c", "Other" = "grey70"), name = NULL) +
    labs(x = "Mean |SHAP value|", y = NULL, title = "D") +
    theme_classic(base_size = 8) +
    theme(legend.position = "bottom", legend.key.size = grid::unit(0.3, "cm"))
  list(A = pA, B = pB, C = pC, D = pD, title = db)
}

message("KM / RCS / ROC")
km_df <- list()
km_p <- list()
rcs_df <- list()
rcs_p <- list()
roc_df <- list()
for (nm in names(dbs)) {
  d <- dbs[[nm]]
  sf <- survfit(Surv(time, event) ~ Sleep_Group, data = d)
  ss <- summary(sf)
  km_df[[nm]] <- data.frame(
    database = nm, time = ss$time, surv = ss$surv, lower = ss$lower, upper = ss$upper,
    group = sub(".*Sleep_Group=", "", ss$strata), stringsAsFactors = FALSE
  )
  sdif <- survdiff(Surv(time, event) ~ Sleep_Group, data = d)
  km_p[[nm]] <- data.frame(database = nm, logrank_p = pchisq(sdif$chisq, length(sdif$n) - 1, lower.tail = FALSE))
  covs <- c("Age", "Gender", "SBP", "Hypertension", "Smoke", "BMI")
  d2 <- d[stats::complete.cases(d[, c("time", "event", "Sleep_hours", covs)]), ]
  d2$Gender <- factor(d2$Gender)
  d2$Hypertension <- factor(d2$Hypertension)
  d2$Smoke <- factor(d2$Smoke)
  kts <- as.numeric(stats::quantile(d2$Sleep_hours, c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE))
  fit <- tryCatch(coxph(Surv(time, event) ~ splines::ns(Sleep_hours, knots = kts) + Age + Gender + SBP + Hypertension + Smoke + BMI, data = d2), error = function(e) NULL)
  fit_lin <- tryCatch(coxph(Surv(time, event) ~ Sleep_hours + Age + Gender + SBP + Hypertension + Smoke + BMI, data = d2), error = function(e) NULL)
  fit_null <- tryCatch(coxph(Surv(time, event) ~ Age + Gender + SBP + Hypertension + Smoke + BMI, data = d2), error = function(e) NULL)
  p_from_anova <- function(a) {
    if (is.null(a) || !(is.data.frame(a) || is.matrix(a)) || nrow(a) < 2) return(NA_real_)
    cn <- grep("^Pr\\(>\\|Chi\\|\\)$|^P\\(>\\|Chi\\|\\)$", colnames(a), value = TRUE)
    if (!length(cn)) return(NA_real_)
    suppressWarnings(as.numeric(a[2, cn[1]]))
  }
  p_ov <- if (!is.null(fit) && !is.null(fit_null)) p_from_anova(anova(fit_null, fit)) else NA_real_
  p_nl <- if (!is.null(fit) && !is.null(fit_lin)) p_from_anova(anova(fit_lin, fit)) else NA_real_
  rcs_p[[nm]] <- data.frame(database = nm, p_overall = p_ov, p_nonlinear = p_nl)
  if (!is.null(fit)) {
    grid <- seq(max(4, min(d2$Sleep_hours)), min(12, max(d2$Sleep_hours)), length.out = 80)
    nd <- d2[which.min(abs(d2$Sleep_hours - median(d2$Sleep_hours))), covs, drop = FALSE]
    nd <- nd[rep(1, length(grid)), , drop = FALSE]
    nd$Sleep_hours <- grid
    pr <- predict(fit, newdata = nd, type = "lp", se.fit = TRUE)
    ref_i <- which.min(abs(grid - 7.5))
    # 置信区间用相对 7.5 小时的对比标准误，参照点应收成一个点。
    X <- model.matrix(fit, data = nd)
    V <- stats::vcov(fit)
    X <- X[, colnames(V), drop = FALSE]
    delta <- sweep(X, 2, X[ref_i, ], FUN = "-")
    se <- sqrt(pmax(0, rowSums((delta %*% V) * delta)))
    lp <- as.numeric(pr$fit) - as.numeric(pr$fit)[ref_i]
    rcs_df[[nm]] <- data.frame(database = nm, hours = grid, HR = exp(lp),
                               lo = exp(lp - 1.96 * se),
                               hi = exp(lp + 1.96 * se))
  }
  y <- as.integer(d$event == 1 & d$time <= 2)
  ok <- stats::complete.cases(d[, c("Sleep_hours", "Age", "Gender")]) & !is.na(y)
  if (length(unique(y[ok])) == 2) {
    dd <- d[ok, ]
    dd$y <- y[ok]
    dd$Gender <- factor(dd$Gender)
    w <- if (nm == "NHANES") dd$survey_weight else NULL
    fit <- stats::glm(y ~ Sleep_hours + Age + Gender, data = dd, family = stats::binomial())
    roc <- pROC::roc(dd$y, stats::predict(fit, type = "response"), weights = w, quiet = TRUE, direction = "<")
    cd <- pROC::coords(roc, ret = c("specificity", "sensitivity"), transpose = FALSE)
    roc_df[[nm]] <- data.frame(database = nm, fpr = 1 - cd$specificity, tpr = cd$sensitivity,
                               AUC = as.numeric(pROC::auc(roc)))
  }
}
km <- do.call(rbind, km_df)
kp <- do.call(rbind, km_p)
kp$lab <- paste0("Log-rank P ", fmt_p(kp$logrank_p))
rcs <- do.call(rbind, rcs_df)
rp <- do.call(rbind, rcs_p)
rp$lab <- paste0("P-overall ", fmt_p(rp$p_overall), "\nP-nonlinear ", fmt_p(rp$p_nonlinear))
roc <- do.call(rbind, roc_df)
auc_lab <- tapply(roc$AUC, roc$database, function(z) sprintf("%s (AUC %.3f)", unique(z)[1], unique(z)[1]))
# fix label
auc_map <- tapply(roc$AUC, roc$database, function(z) round(z[1], 3))
roc$curve <- paste0(roc$database, " (AUC ", sprintf("%.3f", auc_map[roc$database]), ")")

pv2_km_cuminc <- function(dbs) {
  # 分组名不用 < 或 >，否则 survminer 的 gridtext 会把它们当成标记。
  # 顺序与 Cox 参考一致：7-8 为参照（第一条曲线）。
  labs5 <- c("7-8 h", "under 5 h", "5-6 h", "6-7 h", "9 h or more")
  lev5 <- c("7-8", "<5", "5-6", "6-7", ">=9")
  pal5 <- c("#2ca02c", "#d62728", "#ff7f0e", "#1f77b4", "#9467bd")
  fmt_p <- function(p) {
    if (!is.finite(p)) return("Log-rank P not estimated")
    if (p < 0.001) return("Log-rank P < 0.001")
    sprintf("Log-rank P = %.3f", p)
  }
  plots <- lapply(names(dbs), function(nm) {
    d <- as.data.frame(dbs[[nm]])
    if (!"time" %in% names(d)) d$time <- d$futime_years
    if (!"event" %in% names(d)) d$event <- d$fustatus
    if (!"Sleep_Group" %in% names(d) || !all(lev5 %in% levels(factor(d$Sleep_Group)))) {
      d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
    }
    d$sg <- factor(as.character(d$Sleep_Group), levels = lev5, labels = labs5)
    d <- d[!is.na(d$time) & d$time > 0 & !is.na(d$event) & !is.na(d$sg), ]
    fit <- survival::survfit(survival::Surv(time, event) ~ sg, data = d)
    sd <- survival::survdiff(survival::Surv(time, event) ~ sg, data = d)
    p <- stats::pchisq(sd$chisq, length(sd$n) - 1, lower.tail = FALSE)
    xmax <- max(d$time, na.rm = TRUE)
    brk <- if (xmax > 8) 5 else if (xmax > 4) 2 else 1
    g <- survminer::ggsurvplot(
      fit, data = d, fun = "event",
      conf.int = FALSE, censor = TRUE, censor.size = 1.6,
      risk.table = TRUE, risk.table.height = 0.32, risk.table.title = "Number at risk",
      pval = FALSE,
      palette = pal5,
      legend = "top", legend.title = "Sleep duration",
      legend.labs = labs5,
      xlab = "Follow-up (years)",
      ylab = "Cumulative incidence of all-cause mortality",
      title = nm, break.time.by = brk,
      ggtheme = ggplot2::theme_classic(base_size = 11),
      fontsize = 2.8
    )
    g$plot <- g$plot + ggplot2::annotate(
      "text", x = 0, y = Inf, label = fmt_p(p), hjust = 0, vjust = 1.4, size = 3.4
    )
    g
  })
  names(plots) <- names(dbs)
  plots
}
source(file.path(engine, "Blocks/15_rcs/05block_rcs_cox_models_panel.R"), local = FALSE)
rcs_fit <- rcs_cox_models_panel_fit(dbs)
rcs <- rcs_fit$rcs
rp <- rcs_fit$rp
p_rcs <- rcs_cox_models_panel_plot(
  rcs_fit,
  which_models = "Model 1",
  show_model_strip = FALSE,
  title = "Restricted cubic spline of sleep duration and all-cause mortality",
  xlab = "Sleep duration, hours",
  ylab = "Hazard ratio (reference 7.5 h)",
  vlines = c(7, 9)
)
p_roc <- ggplot(roc, aes(fpr, tpr, color = curve)) +
  geom_path(linewidth = 0.8) +
  geom_abline(linetype = 2, color = "grey40") +
  labs(x = "1 - specificity", y = "Sensitivity", color = NULL,
       title = "Receiver operating characteristic curves\nfor 2-year all-cause mortality") +
  coord_equal(clip = "off") +
  theme_pub() +
  theme(plot.title = element_text(size = 11, margin = margin(b = 6)),
        plot.margin = margin(6, 10, 6, 6))

message("亚组森林 / 中介路径")
sg <- as.data.frame(fread(file.path(ckpt_dir, "Subgroup_rows.csv")))
if (!"estimable" %in% names(sg)) sg$estimable <- is.finite(sg$HR) & is.finite(sg$lo) & is.finite(sg$hi) & sg$HR > 0 & sg$hi < 80
sg$contrast <- ifelse(grepl("<5", sg$term, fixed = TRUE), "<5 h vs 7-8 h",
               ifelse(grepl("5-6", sg$term, fixed = TRUE), "5-6 h vs 7-8 h",
               ifelse(grepl("6-7", sg$term, fixed = TRUE), "6-7 h vs 7-8 h",
               ifelse(grepl(">=9", sg$term, fixed = TRUE), ">=9 h vs 7-8 h",
               ifelse(grepl("<7", sg$term, fixed = TRUE), "<7 h vs 7-8 h", sg$term)))))
sg$contrast <- factor(sg$contrast, levels = c("<5 h vs 7-8 h", "5-6 h vs 7-8 h", "6-7 h vs 7-8 h",
                                              ">=9 h vs 7-8 h", "<7 h vs 7-8 h"))
sg$stratum <- gsub("_", " ", sg$stratum)
sg$row <- paste0(sg$stratum, ": ", sg$level)
sg_ok <- sg[isTRUE(sg$estimable) | sg$estimable %in% TRUE, ]
sg_bad <- sg[!(sg$estimable %in% TRUE), ]
sg_bad <- sg_bad[!duplicated(sg_bad[, c("database", "row")]), ]
p_sg <- ggplot(sg, aes(HR, row, color = contrast)) +
  geom_vline(xintercept = 1, linetype = 2) +
  geom_pointrange(data = sg_ok, aes(xmin = lo, xmax = hi),
                  position = position_dodge(width = 0.7), size = 0.22) +
  geom_text(data = sg_bad, aes(x = 1, y = row, label = "Not estimable"),
            inherit.aes = FALSE, size = 2.6, color = "grey40") +
  facet_wrap(~database, nrow = 1, scales = "free_y") +
  scale_x_log10() +
  scale_color_manual(values = c(
    "<5 h vs 7-8 h" = "#d62728", "5-6 h vs 7-8 h" = "#ff7f0e",
    "6-7 h vs 7-8 h" = "#1f77b4", ">=9 h vs 7-8 h" = "#9467bd",
    "<7 h vs 7-8 h" = "#8c564b"
  ), drop = TRUE) +
  labs(x = "Hazard ratio (log scale)", y = NULL, color = NULL,
       title = "Subgroup analyses of sleep duration and all-cause mortality") +
  theme_pub() +
  theme(axis.text.y = element_text(size = 7),
        legend.position = "bottom")

if (!only_kmrcs) {
  old <- list.files(fig_dir, pattern = "\\.pdf$", full.names = TRUE)
  unlink(old)
  source(file.path(engine, "run/prognosis_v2/pv2_mediation.R"), local = FALSE)
  pv2_run_mediation(dbs, tab_dir, fig_dir)
}

if (!only_kmrcs) {
fig2 <- file.path(fig_dir, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
mean_tab <- as.data.frame(fread(file.path(ckpt_dir, "SHAP_by_database.csv")))
# Figure 2 只展示主库协变量筛选；CHARLS 外验不进图。
fig2_dbs <- intersect(pv2_primary_dbs, names(bor_obj))
if (!length(fig2_dbs)) fig2_dbs <- setdiff(names(bor_obj), pv2_validation_dbs)
mean_tab <- mean_tab[mean_tab$database %in% fig2_dbs, , drop = FALSE]
shap_df <- shap_df[shap_df$database %in% fig2_dbs, , drop = FALSE]
blocks <- lapply(fig2_dbs, function(nm) pv2_fig2_database(bor_obj[[nm]], shap_df, nm, mean_tab))
fig2_h <- if (length(blocks) <= 2L) 11.2 else 16.5
grDevices::cairo_pdf(fig2, width = 10.5, height = fig2_h, family = "Times")
grid::grid.newpage()
nblk <- length(blocks)
for (i in seq_len(nblk)) {
  y0 <- 1 - i / nblk
  grid::pushViewport(grid::viewport(y = y0, height = 1 / nblk, just = c("centre", "bottom")))
  grid::grid.text(blocks[[i]]$title, x = 0.02, y = 0.98, just = c("left", "top"),
                  gp = grid::gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
  panels <- blocks[[i]][c("A", "B", "C", "D")]
  for (j in seq_along(panels)) {
    col <- if (j %% 2L == 1L) 0 else 1
    row <- if (j <= 2L) 1 else 0
    print(panels[[j]], vp = grid::viewport(
      x = 0.02 + col * 0.49, y = 0.04 + row * 0.46,
      width = 0.47, height = 0.44, just = c("left", "bottom")
    ))
  }
  grid::popViewport()
}
grDevices::dev.off()
}
ggsave(file.path(fig_dir, "Figure 5. Receiver operating characteristic curves for 2-year all-cause mortality.pdf"), p_roc, width = 6.2, height = 5.6)
ggsave(file.path(fig_dir, "Figure 7. Subgroup analyses of sleep duration and all-cause mortality.pdf"), p_sg, width = 11.5, height = 6.2)
fig3 <- file.path(fig_dir, "Figure 3. Cumulative incidence of all-cause mortality by sleep duration.pdf")
km_plots <- pv2_km_cuminc(dbs)
km_page <- survminer::arrange_ggsurvplots(km_plots, print = FALSE, ncol = 1, nrow = 3, title = NA)
grDevices::cairo_pdf(fig3, width = 7.4, height = 14.2, family = "Times")
print(km_page)
grDevices::dev.off()
old_km <- list.files(fig_dir, pattern = "^Figure 3\\. Kaplan-Meier", full.names = TRUE)
if (length(old_km)) unlink(old_km)
ggsave(file.path(fig_dir, "Figure 4. Restricted cubic spline of sleep duration and all-cause mortality.pdf"), p_rcs, width = 11.2, height = 4.2)
fwrite(kp, file.path(tab_dir, "Figure3_logrank.csv"))
fwrite(rp, file.path(ckpt_dir, "Figure4_rcs_p.csv"))
fwrite(unique(roc[, c("database", "AUC")]), file.path(tab_dir, "Figure5_auc.csv"))
message("面板 PDF 已写，流程图三张在 _flow_panels")
source(file.path(engine, "run/prognosis_v2/draw_fig1_nhanes.R"), local = FALSE)
pv2_draw_fig1_three(
  file.path(fig_dir, "Figure 1. Flow diagram of adults aged 45 years or older with dyslipidemia.pdf"),
  pv2_fig1_default_panels(
    n_death_nh = sum(dbs$NHANES$event == 1), n_alive_nh = sum(dbs$NHANES$event == 0),
    n_death_ch = sum(dbs$CHARLS$event == 1), n_alive_ch = sum(dbs$CHARLS$event == 0),
    n_death_sh = sum(dbs$SHHS$event == 1), n_alive_sh = sum(dbs$SHHS$event == 0)
  )
)
message("Figure 1 已按三库同一版式重画")
fig_root <- file.path(out_root, "Figures")
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
pub_figure_ensure_formats(
  fig_root,
  meta = list(
    databases = c("NHANES", "CHARLS", "SHHS"),
    exposure = "Sleep duration",
    outcome = "All-cause mortality",
    tables_dir = tab_dir
  ),
  config = list(pub_figures = list(dpi = 600L, write_image_information = TRUE))
)
message("pdf / png / tiff / image_information 已导出")
