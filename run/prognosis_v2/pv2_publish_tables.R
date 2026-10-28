# 亚组（NHANES 加权）+ 发表表。Table 1 为按睡眠分组的基线表。
# 其余主表 / 附表与 Jin 2026 正文和补充材料对应；另加插补、相关、中介。

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(survey)
  library(ggplot2)
})

engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
out_root <- pv2_out_root
tab_dir <- pv2_tab_dir
fig_dir <- pv2_fig_dir
ckpt <- pv2_ckpt_dir
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")

fmt_p <- function(p) {
  ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
hr_cell <- function(hr, lo, hi) {
  ifelse(!is.finite(hr) | !is.finite(lo) | !is.finite(hi), "",
         sprintf("%.3f (%.3f-%.3f)", hr, lo, hi))
}
mean_sd <- function(x) sprintf("%.2f \u00b1 %.2f", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
med_iqr <- function(x) {
  q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  sprintf("%.2f (%.2f-%.2f)", q[2], q[1], q[3])
}
n_pct <- function(k, n) sprintf("%d (%.1f)", k, ifelse(n > 0, 100 * k / n, NA))

pick <- function(name) {
  a <- file.path(tab_dir, name)
  b <- file.path(ckpt, name)
  if (file.exists(a)) a else b
}
dbs <- readRDS(pick("imputed_dbs.rds"))

# ---- 亚组 ----
sub_rows <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- d$futime_years
  d$event <- d$fustatus
  d$Gender <- factor(d$Gender)
  if (!exists("pv2_sleep_group5", mode = "function")) {
    d$Sleep_Group <- factor(d$Sleep_Group, levels = c("7-8", "<7", ">=9"))
  } else {
    d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  }
  d$Age_Group <- factor(ifelse(d$Age < 60, "<60", ">=60"), levels = c("<60", ">=60"))
  d$BMI_Group <- factor(ifelse(d$BMI < 30, "<30", ">=30"), levels = c("<30", ">=30"))
  terms <- if (exists("pv2_sleep_levels_cox")) {
    paste0("Sleep_Group", setdiff(pv2_sleep_levels_cox, "7-8"))
  } else {
    c("Sleep_Group<7", "Sleep_Group>=9")
  }
  for (sv in c("Age_Group", "Gender", "BMI_Group", "Smoke", "Hypertension", "Diabetes")) {
    if (!sv %in% names(d)) next
    for (lv in levels(factor(d[[sv]]))) {
      if (!nzchar(lv) || is.na(lv)) next
      sub <- d[!is.na(d[[sv]]) & as.character(d[[sv]]) == lv, ]
      ref_events <- sum(sub$event == 1 & sub$Sleep_Group == "7-8", na.rm = TRUE)
      rhs <- "Sleep_Group + Age"
      if (length(unique(na.omit(as.character(sub$Gender)))) > 1L) rhs <- paste(rhs, "+ Gender")
      need <- c("time", "event", "Sleep_Group", "Age", "Gender")
      sub <- sub[stats::complete.cases(sub[, need]) & sub$time > 0, ]
      estimable <- nrow(sub) >= 40 && ref_events >= 2 &&
        length(unique(as.character(sub$Sleep_Group))) >= 2
      n_terms <- length(terms)
      hr <- lo <- hi <- p <- rep(NA_real_, n_terms)
      if (estimable && nm == "NHANES") {
        sub <- sub[!is.na(sub$survey_weight) & sub$survey_weight > 0 & !is.na(sub$psu) & !is.na(sub$strata), ]
        fit <- tryCatch({
          des <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight,
                                   data = sub, nest = TRUE)
          survey::svycoxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), design = des)
        }, error = function(e) NULL)
        if (is.null(fit)) estimable <- FALSE
      } else if (estimable) {
        fit <- tryCatch(survival::coxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), data = sub),
                        error = function(e) NULL)
        if (is.null(fit)) estimable <- FALSE
      }
      if (estimable) {
        ci <- summary(fit)$conf.int
        co <- summary(fit)$coefficients
        for (i in seq_along(terms)) {
          key <- sub("^Sleep_Group", "", terms[i])
          hit <- grep(key, rownames(ci), fixed = TRUE)[1]
          if (is.na(hit)) next
          hr[i] <- ci[hit, 1]
          lo[i] <- ci[hit, 3]
          hi[i] <- ci[hit, 4]
          p[i] <- co[rownames(ci)[hit], "Pr(>|z|)"]
        }
        if (any(!is.finite(c(hr, lo, hi))) || any(hi > 80, na.rm = TRUE)) estimable <- FALSE
      }
      sub_rows[[length(sub_rows) + 1L]] <- data.frame(
        database = nm, stratum = sv, level = lv, term = terms,
        HR = hr, lo = lo, hi = hi, p = p, estimable = estimable,
        stringsAsFactors = FALSE
      )
      message(sprintf("subgroup %s %s=%s estimable=%s", nm, sv, lv, estimable))
    }
  }
}
sub_tab <- do.call(rbind, sub_rows)
fwrite(sub_tab, file.path(ckpt, "Subgroup_rows.csv"))

sg <- sub_tab
sg$contrast <- ifelse(grepl("<5", sg$term, fixed = TRUE), "<5 h vs 7-8 h",
               ifelse(grepl("5-6", sg$term, fixed = TRUE), "5-6 h vs 7-8 h",
               ifelse(grepl("6-7", sg$term, fixed = TRUE), "6-7 h vs 7-8 h",
               ifelse(grepl(">=9", sg$term, fixed = TRUE), ">=9 h vs 7-8 h",
               ifelse(grepl("<7", sg$term, fixed = TRUE), "<7 h vs 7-8 h", sg$term)))))
sg$stratum <- gsub("_", " ", sg$stratum)
sg$row <- paste0(sg$stratum, ": ", sg$level)
sg$HR[!sg$estimable] <- NA_real_
sg_ok <- sg[sg$estimable, ]
sg_bad <- sg[!sg$estimable & !duplicated(sg[, c("database", "row")]), ]
theme_pub <- function() {
  theme_classic(base_size = 11, base_family = "Times") +
    theme(plot.title = element_text(face = "bold", size = 12),
          strip.background = element_blank(),
          strip.text = element_text(face = "bold"))
}
p_sg <- ggplot(sg_ok, aes(HR, row, color = contrast)) +
  geom_vline(xintercept = 1, linetype = 2) +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = 0.6), size = 0.25) +
  geom_text(data = sg_bad, aes(x = 1, y = row), label = "Not estimable",
            inherit.aes = FALSE, size = 2.6, color = "grey35") +
  facet_wrap(~database, nrow = 1, scales = "free_y") +
  scale_x_log10() +
  labs(x = "Hazard ratio (log scale)", y = NULL, color = NULL,
       title = "Subgroup analyses of sleep duration and all-cause mortality") +
  theme_pub() +
  theme(axis.text.y = element_text(size = 7))
fig7 <- file.path(fig_dir, "Figure 7. Subgroup analyses of sleep duration and all-cause mortality.pdf")
ggsave(fig7, p_sg, width = 11.5, height = 6.6, device = grDevices::cairo_pdf)
message("fig7 ", fig7)

# ---- Table 1：按睡眠分组 ----
cont_vars <- c(Age = "Age, years", BMI = "BMI, kg/m2", SBP = "SBP, mmHg", Sleep_hours = "Sleep duration, hours")
bin_vars <- c(Gender = "Male", Smoke = "Smoke", Alcohol = "Alcohol",
              Hypertension = "Hypertension", Diabetes = "Diabetes", Education = "Higher education")
bin_yes <- c(Gender = "Male", Smoke = "Yes", Alcohol = "Yes", Hypertension = "Yes",
             Diabetes = "Yes", Education = "Higher")
t1 <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$Sleep_Group <- factor(as.character(d$Sleep_Group), levels = c("7-8", "<7", ">=9"))
  groups <- levels(d$Sleep_Group)
  weighted <- nm == "NHANES"
  des <- NULL
  if (weighted) {
    d <- d[!is.na(d$survey_weight) & d$survey_weight > 0 & !is.na(d$psu) & !is.na(d$strata), ]
    des <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = d, nest = TRUE)
  }
  cell_cont <- function(g, var) {
    xx <- d[[var]][d$Sleep_Group == g]
    xx <- xx[!is.na(xx)]
    if (weighted) {
      dd <- d[d$Sleep_Group == g & !is.na(d[[var]]), ]
      desg <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = dd, nest = TRUE)
      m <- as.numeric(survey::svymean(stats::as.formula(paste0("~", var)), desg, na.rm = TRUE))
      s <- sqrt(as.numeric(survey::svyvar(stats::as.formula(paste0("~", var)), desg, na.rm = TRUE)))
      sprintf("%.2f \u00b1 %.2f", m, s)
    } else if (length(xx) >= 3 && length(xx) <= 5000 &&
               tryCatch(stats::shapiro.test(xx)$p.value, error = function(e) 0) >= 0.05) {
      mean_sd(xx)
    } else if (length(xx) > 5000) {
      mean_sd(xx)
    } else {
      med_iqr(xx)
    }
  }
  p_cont <- function(var) {
    if (weighted) {
      f <- survey::svyglm(stats::as.formula(paste(var, "~ Sleep_Group")), design = des)
      as.numeric(survey::regTermTest(f, ~Sleep_Group)$p)
    } else {
      x <- d[[var]]
      if (length(na.omit(x)) <= 5000 && tryCatch(stats::shapiro.test(x)$p.value, error = function(e) 0) >= 0.05) {
        summary(stats::aov(x ~ d$Sleep_Group))[[1]][["Pr(>F)"]][1]
      } else {
        stats::kruskal.test(x ~ d$Sleep_Group)$p.value
      }
    }
  }
  cell_bin <- function(var, yes, g) {
    dd <- d[d$Sleep_Group == g & !is.na(d[[var]]), ]
    if (!weighted) return(n_pct(sum(dd[[var]] == yes), nrow(dd)))
    dd$yy <- as.numeric(dd[[var]] == yes)
    desg <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = dd, nest = TRUE)
    pr <- as.numeric(survey::svymean(~yy, desg, na.rm = TRUE))[1]
    sprintf("%.1f%%", 100 * pr)
  }
  p_bin <- function(var) {
    if (weighted) {
      as.numeric(survey::svychisq(stats::as.formula(paste0("~ ", var, " + Sleep_Group")), design = des)$p.value)
    } else {
      stats::chisq.test(table(d[[var]], d$Sleep_Group))$p.value
    }
  }
  add <- function(characteristic, vals, p) {
    t1[[length(t1) + 1L]] <<- data.frame(
      database = nm, Characteristic = characteristic,
      `7-8 h` = vals[1], `<7 h` = vals[2], `>=9 h` = vals[3], P = fmt_p(p),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  for (v in names(cont_vars)) {
    add(cont_vars[[v]], vapply(groups, function(g) cell_cont(g, v), character(1)), p_cont(v))
  }
  for (v in names(bin_vars)) {
    add(bin_vars[[v]], vapply(groups, function(g) cell_bin(v, bin_yes[[v]], g), character(1)), p_bin(v))
  }
}
t1 <- do.call(rbind, t1)
fwrite(t1, file.path(tab_dir, "Table 1. Baseline characteristics by sleep duration.csv"))

# ---- Table 2：发病率 + 精确 Poisson 95% CI + 有序趋势 P ----
py <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d <- d[!is.na(d$Sleep_Group) & !is.na(d$futime_years) & d$futime_years > 0 & !is.na(d$fustatus), ]
  d$ord <- as.integer(factor(as.character(d$Sleep_Group), levels = c("<7", "7-8", ">=9")))
  tr <- stats::glm(fustatus ~ ord, offset = log(futime_years), family = stats::poisson(), data = d)
  p_tr <- summary(tr)$coefficients["ord", "Pr(>|z|)"]
  for (g in c("<7", "7-8", ">=9")) {
    sub <- d[as.character(d$Sleep_Group) == g, ]
    n <- nrow(sub)
    ev <- sum(sub$fustatus == 1, na.rm = TRUE)
    pyrs <- sum(sub$futime_years, na.rm = TRUE)
    ci <- stats::poisson.test(ev, T = pyrs)$conf.int * 1e4
    py[[length(py) + 1L]] <- data.frame(
      database = nm,
      `Sleep group` = ifelse(g == "7-8", "7-8 h", ifelse(g == "<7", "<7 h", ">=9 h")),
      Participants = n,
      `All-cause mortality` = ev,
      `Cumulative incidence, %` = round(100 * ev / n, 2),
      `Per 10000 person-year` = round(1e4 * ev / pyrs, 2),
      CI_low = round(ci[1], 2),
      CI_high = round(ci[2], 2),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  py[[length(py) + 1L]] <- data.frame(
    database = nm, `Sleep group` = "P for trend", Participants = fmt_p(p_tr),
    `All-cause mortality` = "", `Cumulative incidence, %` = "",
    `Per 10000 person-year` = "", CI_low = NA_real_, CI_high = NA_real_,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
fwrite(do.call(rbind, py), file.path(tab_dir, "Table 2. Incidence of all-cause mortality.csv"))

# ---- Table 3：只保留睡眠分组 ----
cox <- as.data.frame(fread(pick("Table 3. Cox.csv")))
cox <- cox[grepl("^Sleep_Group", cox$term) & cox$model %in% c("Model1", "Model2", "Model3"), ]
cox$contrast <- ifelse(grepl(">=9", cox$term), ">=9 h vs 7-8 h", "<7 h vs 7-8 h")
wide <- list()
for (nm in unique(cox$database)) {
  for (ct in c("<7 h vs 7-8 h", ">=9 h vs 7-8 h")) {
    row <- list(database = nm, Contrast = ct)
    for (md in c("Model1", "Model2", "Model3")) {
      hit <- cox[cox$database == nm & cox$contrast == ct & cox$model == md, ][1, ]
      row[[paste0(md, " HR (95% CI)")]] <- hr_cell(hit$HR, hit$lo, hit$hi)
      row[[paste0(md, " P")]] <- fmt_p(hit$p)
    }
    wide[[length(wide) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
  }
}
fwrite(do.call(rbind, wide), file.path(tab_dir, "Table 3. Cox proportional hazards models.csv"))

# ---- Table 4：心血管死亡 Fine-Gray，Model 1-3 ----
m3_rhs <- "Sleep_Group + Age + Gender + SBP + Education + Hypertension + Alcohol + Smoke + BMI"
fg_out <- list()
for (nm in c("NHANES", "SHHS")) {
  d <- as.data.frame(dbs[[nm]])
  d <- d[!is.na(d$cvd_status), ]
  d$etime <- d$futime_years
  d$status <- factor(ifelse(d$cvd_status == 1, "cvd", ifelse(d$fustatus == 1, "other", "censor")),
                     levels = c("censor", "cvd", "other"))
  d$Gender <- factor(d$Gender)
  d$Education <- factor(d$Education)
  d$Hypertension <- factor(d$Hypertension)
  d$Alcohol <- factor(d$Alcohol)
  d$Smoke <- factor(d$Smoke)
  d$Sleep_Group <- factor(d$Sleep_Group, levels = c("7-8", "<7", ">=9"))
  keep <- c("etime", "status", "Sleep_Group", "Age", "Gender", "SBP", "Education",
            "Hypertension", "Alcohol", "Smoke", "BMI", "survey_weight")
  d <- d[, intersect(keep, names(d))]
  fg_rhs <- "Sleep_Group + Age + Gender + SBP + Education + Hypertension + Alcohol + Smoke + BMI"
  if (nm == "NHANES") fg_rhs <- paste(fg_rhs, "+ survey_weight")
  fg <- survival::finegray(stats::as.formula(paste("Surv(etime, status) ~", fg_rhs)),
                           data = d, etype = "cvd")
  for (spec in list(c("Model1", "Sleep_Group"), c("Model2", "Sleep_Group + Age + Gender"), c("Model3", m3_rhs))) {
    f <- stats::as.formula(paste("Surv(fgstart, fgstop, fgstatus) ~", spec[2]))
    w <- if (nm == "NHANES") fg$fgwt * fg$survey_weight else fg$fgwt
    fit <- survival::coxph(f, data = fg, weights = w)
    ci <- summary(fit)$conf.int
    co <- summary(fit)$coefficients
    keep <- grepl("Sleep_Group", rownames(ci))
    fg_out[[length(fg_out) + 1L]] <- data.frame(
      database = nm, model = spec[1], term = rownames(ci)[keep],
      sHR = ci[keep, 1], lo = ci[keep, 3], hi = ci[keep, 4],
      p = co[rownames(ci)[keep], "Pr(>|z|)"],
      stringsAsFactors = FALSE
    )
  }
  message("finegray ", nm)
}
fg <- do.call(rbind, fg_out)
fg$contrast <- ifelse(grepl(">=9", fg$term), ">=9 h vs 7-8 h", "<7 h vs 7-8 h")
fgw <- list()
for (nm in unique(fg$database)) {
  for (ct in c("<7 h vs 7-8 h", ">=9 h vs 7-8 h")) {
    row <- list(database = nm, Contrast = ct)
    for (md in c("Model1", "Model2", "Model3")) {
      hit <- fg[fg$database == nm & fg$contrast == ct & fg$model == md, ][1, ]
      row[[paste0(md, " sHR (95% CI)")]] <- hr_cell(hit$sHR, hit$lo, hit$hi)
      row[[paste0(md, " P")]] <- fmt_p(hit$p)
    }
    fgw[[length(fgw) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
  }
}
# Table 4 的 xlsx 由 pv2_export_pub_xlsx.R 从分析数据重算。这里不再写旧的对比列 csv。

# ---- S1 定义 ----
fwrite(data.frame(
  Item = c("Population", "Dyslipidemia", "Sleep 7-8 h", "Sleep <7 h", "Sleep >=9 h",
           "Outcome", "Follow-up", "Weights", "Model 1", "Model 2", "Model 3"),
  Definition = c(
    "Adults aged 45 years or older. Missing sex is imputed and not excluded.",
    "TG >= 150 or TC >= 200 or LDL-C >= 130 or HDL-C <= 40 mg/dL.",
    "Reference group.",
    "Short sleep.",
    "Long sleep.",
    "All-cause mortality. Cardiovascular death is used only in the competing-risk table.",
    "NHANES and SHHS in years from the source files. CHARLS from 2011-06-15 to death or 2014-01-31, in years.",
    "NHANES Cox and subgroup models use WTMEC2YR, PSU and strata. CHARLS and SHHS are unweighted.",
    "Sleep group only.",
    "Sleep group, age and sex.",
    "Sleep group, age, sex, SBP, education, hypertension, alcohol, smoking and BMI."
  ),
  stringsAsFactors = FALSE
), file.path(tab_dir, "Table S1. Definitions.csv"))

# ---- S2 VIF ----
vif <- as.data.frame(fread(pick("Table S2. VIF.csv")))
vif <- vif[, c("database", "variable", "VIF")]
names(vif) <- c("database", "Variable", "VIF")
fwrite(vif, file.path(tab_dir, "Table S2. Assessment of multicollinearity.csv"))

# ---- S4 预测 ----
you <- as.data.frame(fread(pick("Table S4. Youden.csv")))
fwrite(data.frame(
  database = you$database, AUC = you$AUC,
  `Cutoff (predicted probability)` = you$cutoff,
  Sensitivity = you$sensitivity, Specificity = you$specificity,
  check.names = FALSE, stringsAsFactors = FALSE
), file.path(tab_dir, "Table S4. Predictive performance for 2-year all-cause mortality.csv"))

# S6/S7/S8 的 xlsx 由 pv2_s6_s7_s8.R 写出（插补前后、四项血脂）。本脚本不再写缺失率或 BMI 中介 csv。

# 旧的发表表文件名挪走，避免和正文表并列
old <- c(
  "Table 1. Baseline overall.csv",
  "Table 2. Person-years.csv",
  "Table 3. Cox.csv",
  "Table S2. VIF.csv",
  "Table S3. Cox 5-year horizon.csv",
  "Table S4. Youden.csv",
  "Table S5. FineGray CVD.csv",
  "Table mediation horizon.csv",
  "Table mediation lab screen.csv",
  "Table mediation correlation.csv",
  "Table mediation cox.csv",
  "Column_alignment.csv",
  "Figure3_logrank.csv",
  "Figure5_auc.csv",
  "Covariate_selection_note.txt",
  "Boruta_by_database.csv",
  "SHAP_by_database.csv",
  "Imputation_missingness.csv",
  "Subgroup_rows.csv"
)
for (f in old) {
  src <- file.path(tab_dir, f)
  if (file.exists(src)) file.rename(src, file.path(ckpt, f))
}
message("tables done")
