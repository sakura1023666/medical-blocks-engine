#!/usr/bin/env Rscript
# 1) 全表图展示「7-<9 h」  2) S12–S14 改用各库 RCS Model3 切点（弃 465）
# 3) 重画 Fig3/7  4) 刷新 Methods + 中期 + prune
suppressPackageStartupMessages({
  library(data.table); library(survival); library(survey); library(ggplot2)
})
engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine, PV2_PROFILE = "sleep_dyslipidemia")
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")
message("labels: ", paste(pv2_sleep_labels, collapse = " | "))

# ---- restore checkpoints if pruned ----
.ws_latest <- function() {
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  if (!dir.exists(ws)) return(NA_character_)
  stamps <- list.dirs(ws, full.names = TRUE, recursive = FALSE)
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(stamps, ws)) {
    if (file.exists(file.path(d, "checkpoints", "imputed_dbs.rds")) ||
        file.exists(file.path(d, "imputed_dbs.rds"))) return(d)
  }
  NA_character_
}
if (is.na(tryCatch(pv2_artifact("imputed_dbs.rds", must_exist = FALSE), error = function(e) NA))) {
  w <- .ws_latest()
  if (!is.na(w)) {
    ck <- if (dir.exists(file.path(w, "checkpoints"))) file.path(w, "checkpoints") else w
    for (f in c("imputed_dbs.rds", "imputed_mids.rds", "Covariate_selection_note.txt",
                "Subgroup_rows.csv", "Table S1. Definitions.csv")) {
      src <- file.path(ck, f)
      if (!file.exists(src)) src <- file.path(w, f)
      if (file.exists(src)) {
        file.copy(src, file.path(pv2_ckpt_dir, basename(src)), overwrite = TRUE)
        message("restored ", basename(src))
      }
    }
  }
}

# ---- S1 definitions ----
s1 <- data.frame(
  Item = c(
    "Population", "Dyslipidemia",
    "Sleep <5 h", "Sleep 5-6 h", "Sleep 6-7 h", "Sleep 7-<9 h", "Sleep >=9 h",
    "Outcome", "Follow-up", "Weights", "Model 1", "Model 2", "Model 3", "DBP", "SBP",
    "RCS cutoff"
  ),
  Definition = c(
    "Adults aged 45 years or older with laboratory dyslipidemia. Community cohorts; not restricted to OSA-free participants.",
    "TG >= 150 or TC >= 200 or LDL-C >= 130 or HDL-C <= 40 mg/dL.",
    "Extreme short sleep (<5 hours).",
    "Short sleep (5 to <6 hours).",
    "Short-to-normal sleep (6 to <7 hours).",
    "Reference group: sleep duration in [7, 9) hours (labelled 7-<9 h).",
    "Long sleep (>=9 hours).",
    "All-cause mortality. Cardiovascular death is used only in the competing-risk table.",
    "NHANES and SHHS in years from the source files. CHARLS from 2011-06-15 to death or 2014-01-31, in years.",
    "NHANES Cox and subgroup models use WTMEC2YR, PSU and strata. CHARLS and SHHS are unweighted.",
    "Sleep group only.",
    "Sleep group, age and sex.",
    "Sleep group, age, sex, SBP, education, diabetes, hypertension, alcohol, smoking and BMI (primary-cohort Boruta∩VIF).",
    "Diastolic blood pressure (mmHg); mediator in unadjusted path models.",
    "Systolic blood pressure (mmHg).",
    "Binary clinical cutoffs for Tables S12–S14 are each cohort's own Model 3 RCS minimum-risk hour from Table S10; an external 465-minute cut-point is not used."
  ),
  stringsAsFactors = FALSE
)
fwrite(s1, file.path(pv2_ckpt_dir, "Table S1. Definitions.csv"))

message("==== Export Table1-4 / S1 ====")
Sys.setenv(PV2_SKIP_TABLE1 = "0")
source(file.path(engine, "run/prognosis_v2/pv2_export_pub_xlsx.R"), local = FALSE)

message("==== Extension S9-S14 (RCS cut, not 465) ====")
source(file.path(engine, "run/prognosis_v2/pv2_mainval_extension.R"), local = FALSE)

message("==== S3/S5 ====")
source(file.path(engine, "run/prognosis_v2/pv2_table_s3_s5_mainval.R"), local = FALSE)

message("==== Subgroup + Fig redraw (only KM/RCS/Fig7) ====")
# rebuild subgroup contrasts labels via publish subgroup block is heavy; refresh Subgroup then redraw
touch <- file.path(engine, "run/prognosis_v2/.only_kmrcs")
writeLines("", touch)
# quick subgroup regenerate (same as _refresh_sleep5)
dbs <- pv2_apply_sleep_group5(readRDS(pv2_artifact("imputed_dbs.rds")))
sub_rows <- list()
terms <- paste0("Sleep_Group", setdiff(pv2_sleep_levels_cox, "7-8"))
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  d$time <- d$futime_years; d$event <- d$fustatus
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
      estimable <- nrow(sub) >= 40 && ref_events >= 2 && length(unique(as.character(sub$Sleep_Group))) >= 2
      n_terms <- length(terms)
      hr <- lo <- hi <- p <- rep(NA_real_, n_terms)
      fit <- NULL
      if (estimable && nm == "NHANES") {
        sub <- sub[!is.na(sub$survey_weight) & sub$survey_weight > 0 & !is.na(sub$psu) & !is.na(sub$strata), ]
        fit <- tryCatch({
          des <- survey::svydesign(ids = ~psu, strata = ~strata, weights = ~survey_weight, data = sub, nest = TRUE)
          survey::svycoxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), design = des)
        }, error = function(e) NULL)
        if (is.null(fit)) estimable <- FALSE
      } else if (estimable) {
        fit <- tryCatch(survival::coxph(stats::as.formula(paste("Surv(time, event) ~", rhs)), data = sub), error = function(e) NULL)
        if (is.null(fit)) estimable <- FALSE
      }
      if (estimable) {
        ci <- summary(fit)$conf.int; co <- summary(fit)$coefficients
        for (i in seq_along(terms)) {
          key <- sub("^Sleep_Group", "", terms[i])
          hit <- grep(key, rownames(ci), fixed = TRUE)[1]
          if (is.na(hit)) next
          hr[i] <- ci[hit, 1]; lo[i] <- ci[hit, 3]; hi[i] <- ci[hit, 4]
          p[i] <- co[rownames(ci)[hit], "Pr(>|z|)"]
        }
        if (any(!is.finite(c(hr, lo, hi))) || any(hi > 80, na.rm = TRUE)) estimable <- FALSE
      }
      sub_rows[[length(sub_rows) + 1L]] <- data.frame(
        database = nm, stratum = sv, level = lv, term = terms,
        HR = hr, lo = lo, hi = hi, p = p, estimable = estimable, stringsAsFactors = FALSE
      )
    }
  }
}
fwrite(do.call(rbind, sub_rows), file.path(pv2_ckpt_dir, "Subgroup_rows.csv"))
source(file.path(engine, "run/prognosis_v2/redraw_pub_figures.R"), local = FALSE)
unlink(touch)

message("==== content.json patch + midterm + methods finalize ====")
# patch content if present / restore
w <- .ws_latest()
content <- file.path(pv2_out_root, "content.json")
if (!file.exists(content) && !is.na(w) && file.exists(file.path(w, "content.json"))) {
  file.copy(file.path(w, "content.json"), content, overwrite = TRUE)
}
if (!file.exists(content) && !is.na(w)) {
  # timestamped
  stamps <- list.dirs(paste0(pv2_out_root, "_delivery_workspace"), full.names = TRUE, recursive = FALSE)
  for (d in stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]) {
    if (file.exists(file.path(d, "content.json"))) {
      file.copy(file.path(d, "content.json"), content, overwrite = TRUE)
      if (file.exists(file.path(d, "项目信息-中期.md"))) {
        file.copy(file.path(d, "项目信息-中期.md"), file.path(pv2_out_root, "项目信息-中期.md"), overwrite = TRUE)
      }
      break
    }
  }
}
if (file.exists(content)) {
  py <- paste0(
    "import json\n",
    "from pathlib import Path\n",
    "p=Path(r'", content, "')\n",
    "obj=json.loads(p.read_text(encoding='utf-8'))\n",
    "def walk(o):\n",
    "  if isinstance(o, dict):\n",
    "    for k,v in list(o.items()):\n",
    "      if isinstance(v,str):\n",
    "        v=v.replace('7–8小时','7–<9小时').replace('7-8小时','7-<9小时')\n",
    "        v=v.replace('7–8 h','7–<9 h').replace('7-8 h','7-<9 h')\n",
    "        v=v.replace('465分钟','各库RCS最低风险切点').replace('465 min','cohort RCS min-risk cutoff')\n",
    "        o[k]=v\n",
    "      else: walk(v)\n",
    "  elif isinstance(o, list):\n",
    "    for i in o: walk(i)\n",
    "walk(obj)\n",
    "p.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\\n', encoding='utf-8')\n",
    "print('content patched')\n"
  )
  writeLines(py, "/tmp/patch_content_sleep.py")
  system("python3 /tmp/patch_content_sleep.py")
}

Sys.setenv(
  PV2_PROFILE = "sleep_dyslipidemia",
  PV2_COHORT = "adults aged 45 years or older with dyslipidemia",
  PV2_EXPOSURE = "sleep duration",
  PV2_MEDIATOR = "diastolic blood pressure (DBP)",
  PV2_GROUPING = "five mutually exclusive categories (<5 h, 5-6 h, 6-7 h, 7-<9 h [7 to <9 hours], >=9 h; reference 7-<9 h)"
)
system(sprintf(
  "Rscript %s --dir %s --study-type prognosis_v2 --outcome %s --exposure %s --databases %s",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(pv2_out_root),
  shQuote("all-cause mortality"),
  shQuote("sleep duration"),
  shQuote("NHANES,SHHS,CHARLS")
))

# midterm after finalize may have pruned content — restore again
if (!file.exists(content)) {
  stamps <- list.dirs(paste0(pv2_out_root, "_delivery_workspace"), full.names = TRUE, recursive = FALSE)
  for (d in stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]) {
    if (file.exists(file.path(d, "content.json"))) {
      file.copy(file.path(d, "content.json"), content, overwrite = TRUE)
      info <- file.path(d, "项目信息-中期.md")
      if (file.exists(info)) file.copy(info, file.path(pv2_out_root, "项目信息-中期.md"), overwrite = TRUE)
      break
    }
  }
}
build_py <- file.path(engine, ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py")
out_pdf <- file.path(pv2_out_root, "睡眠时间_全因死亡_Cox比例风险模型_中期分析结果.pdf")
if (file.exists(build_py) && file.exists(content)) {
  system(sprintf(
    "python3 %s --build --project %s --content %s --out %s",
    shQuote(build_py), shQuote(pv2_out_root), shQuote(content), shQuote(out_pdf)
  ))
  old <- file.path(pv2_out_root, "中期分析报告.pdf")
  if (file.exists(old)) unlink(old)
}
system(sprintf(
  "Rscript %s --dir %s --prune-only",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(pv2_out_root)
))
message("ALL DONE")
