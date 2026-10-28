# 一键：五分组落到 imputed → Table1-4/S1 → Subgroup → S3/S5 → Fig3/7 重画
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
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")

message("==== 1. Persist Sleep_Group5 on imputed_dbs ====")
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))
dbs <- pv2_apply_sleep_group5(dbs)
pv2_artifact_save(dbs, "imputed_dbs.rds")
for (nm in names(dbs)) {
  print(table(dbs[[nm]]$Sleep_Group, useNA = "ifany"))
  message(nm, " deaths by group:")
  print(tapply(dbs[[nm]]$fustatus == 1, dbs[[nm]]$Sleep_Group, sum, na.rm = TRUE))
}

message("==== 2. Export Table 1–4 + S1 ====")
Sys.setenv(PV2_SKIP_TABLE1 = "0")
source(file.path(engine, "run/prognosis_v2/pv2_export_pub_xlsx.R"), local = FALSE)

message("==== 3. Subgroup rows (5-level) ====")
# 仅重建亚组，不跑 publish_tables 里旧三分组写表逻辑
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))
sub_rows <- list()
terms <- paste0("Sleep_Group", setdiff(pv2_sleep_levels_cox, "7-8"))
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- d$futime_years
  d$event <- d$fustatus
  d$Gender <- factor(d$Gender)
  d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  d$Age_Group <- factor(ifelse(d$Age < 60, "<60", ">=60"), levels = c("<60", ">=60"))
  d$BMI_Group <- factor(ifelse(d$BMI < 30, "<30", ">=30"), levels = c("<30", ">=30"))
  for (sv in c("Age_Group", "Gender", "BMI_Group", "Smoke", "Hypertension", "Diabetes")) {
    if (!sv %in% names(d)) next
    for (lv in levels(factor(d[[sv]]))) {
      if (!nzchar(lv) || is.na(lv)) next
      sub <- d[!is.na(d[[sv]]) & as.character(d[[sv]]) == lv, ]
      ref_events <- sum(sub$event == 1 & as.character(sub$Sleep_Group) == "7-8", na.rm = TRUE)
      rhs <- "Sleep_Group + Age"
      if (length(unique(na.omit(as.character(sub$Gender)))) > 1L) rhs <- paste(rhs, "+ Gender")
      need <- c("time", "event", "Sleep_Group", "Age", "Gender")
      sub <- sub[stats::complete.cases(sub[, need]) & sub$time > 0, ]
      estimable <- nrow(sub) >= 40 && ref_events >= 2 &&
        length(unique(as.character(sub$Sleep_Group))) >= 2
      n_terms <- length(terms)
      hr <- lo <- hi <- p <- rep(NA_real_, n_terms)
      fit <- NULL
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
    }
  }
}
sub_tab <- do.call(rbind, sub_rows)
fwrite(sub_tab, file.path(pv2_ckpt_dir, "Subgroup_rows.csv"))
message("Subgroup_rows n=", nrow(sub_tab))

message("==== 4. Table S3 / S5 ====")
source(file.path(engine, "run/prognosis_v2/pv2_table_s3_s5_mainval.R"), local = FALSE)

message("==== 5. Redraw figures (Fig3/7 focus; full redraw) ====")
# only_kmrcs 环境可跳过 Fig2/mediation；这里全量
Sys.setenv(PV2_ONLY_KMRCS = "0")
source(file.path(engine, "run/prognosis_v2/redraw_pub_figures.R"), local = FALSE)

message("==== sleep5 refresh done ====")
