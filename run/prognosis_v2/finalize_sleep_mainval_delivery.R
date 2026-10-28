#!/usr/bin/env Rscript
# 睡眠×血脂异常×全因死亡（mainval）发表收口 — 引擎级入口
# 每次本课题定稿后应跑本脚本：P0 修补（Fig4 P-linear、PH 表）→ Methods/软件版本
# → Nature 结构 QC stub → 中期 PDF → 白名单 prune（summary_results 只留图/表/方法/软件/中期）
#
#   Rscript run/prognosis_v2/finalize_sleep_mainval_delivery.R
#   Rscript run/prognosis_v2/finalize_sleep_mainval_delivery.R --skip-midterm
#   Rscript run/prognosis_v2/finalize_sleep_mainval_delivery.R --prune-only

args <- commandArgs(trailingOnly = TRUE)
has_flag <- function(flag) flag %in% args

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    engine <- normalizePath(file.path(dirname(f[[1]]), "..", ".."),
                            winslash = "/", mustWork = FALSE)
  }
}
if (!dir.exists(file.path(engine, "R"))) {
  engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final/R")) {
    "/mnt/e/01block/01Block-new-Final"
  } else {
    "E:/01block/01Block-new-Final"
  }
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)

sum_root <- pv2_out_root
proj_root <- pv2_project_root
tab_dir <- pv2_tab_dir
fig_dir <- pv2_fig_dir
ckpt <- pv2_ckpt_dir
pv2_ensure_dirs()

if (isTRUE(has_flag("--prune-only"))) {
  cmd <- sprintf(
    "Rscript %s --dir %s --prune-only",
    shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
    shQuote(sum_root)
  )
  status <- system(cmd)
  quit(save = "no", status = as.integer(status))
}

message("==== [1/6] Fix Fig4 RCS labels (P-linear + P-nonlinear) ====")
suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(ggplot2)
})
source(file.path(engine, "Blocks/15_rcs/05block_rcs_cox_models_panel.R"), local = FALSE)
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))
for (nm in names(dbs)) {
  dbs[[nm]]$time <- dbs[[nm]]$futime_years
  dbs[[nm]]$event <- dbs[[nm]]$fustatus
}
rcs_fit <- rcs_cox_models_panel_fit(dbs)
p_rcs <- rcs_cox_models_panel_plot(
  rcs_fit,
  which_models = "Model 1",
  show_model_strip = FALSE,
  title = "Restricted cubic spline of sleep duration and all-cause mortality",
  xlab = "Sleep duration, hours",
  ylab = "Hazard ratio (reference 7.5 h)",
  vlines = c(7, 9)
)
fig4 <- file.path(fig_dir, "Figure 4. Restricted cubic spline of sleep duration and all-cause mortality.pdf")
ggplot2::ggsave(fig4, p_rcs, width = 11.2, height = 4.2, device = grDevices::cairo_pdf)
data.table::fwrite(rcs_fit$rp, file.path(ckpt, "Figure4_rcs_p.csv"))
message("Fig4 rewritten: ", fig4)

message("==== [2/6] Table S15 proportional hazards (cox.zph) ====")
source(file.path(engine, "R/pv2_pub_names.R"), local = FALSE)
m3 <- c("Age", "Gender", "SBP", "Education", "Diabetes", "Hypertension", "Alcohol", "Smoke", "BMI")
note <- file.path(ckpt, "Covariate_selection_note.txt")
if (file.exists(note)) {
  hit <- grep("^Model 3 =", readLines(note, warn = FALSE), value = TRUE)[1]
  if (length(hit) && !is.na(hit)) {
    m3 <- trimws(strsplit(sub("^Model 3 =\\s*", "", hit), "\\s*\\+\\s*")[[1]])
  }
}
fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
ph_rows <- list()
for (nm in names(dbs)) {
  d <- as.data.frame(dbs[[nm]])
  if (exists("pv2_sleep_group5", mode = "function")) {
    d$Sleep_Group <- pv2_sleep_group5(d$Sleep_hours, ref_first = TRUE)
  }
  need <- c("futime_years", "fustatus", "Sleep_Group", m3)
  d <- d[stats::complete.cases(d[, need]) & d$futime_years > 0, ]
  for (v in intersect(c("Gender", "Education", "Diabetes", "Hypertension", "Alcohol", "Smoke"), names(d))) {
    d[[v]] <- factor(d[[v]])
  }
  rhs <- paste(c("Sleep_Group", m3), collapse = " + ")
  fit <- tryCatch(
    survival::coxph(stats::as.formula(paste("Surv(futime_years, fustatus) ~", rhs)), data = d),
    error = function(e) NULL
  )
  if (is.null(fit)) next
  z <- tryCatch(survival::cox.zph(fit), error = function(e) NULL)
  if (is.null(z)) next
  tab <- as.data.frame(z$table)
  tab$term <- rownames(z$table)
  for (i in seq_len(nrow(tab))) {
    ph_rows[[length(ph_rows) + 1L]] <- data.frame(
      database = nm,
      Term = tab$term[i],
      chisq = round(tab$chisq[i], 3),
      df = tab$df[i],
      P = fmt_p(tab$p[i]),
      stringsAsFactors = FALSE
    )
  }
}
if (length(ph_rows)) {
  ph_df <- do.call(rbind, ph_rows)
  data.table::fwrite(ph_df, file.path(ckpt, "Table S15. Proportional hazards cox.zph.csv"))
  for (nm in unique(ph_df$database)) {
    sub <- ph_df[ph_df$database == nm, c("Term", "chisq", "df", "P")]
    names(sub) <- c("Term", "Chi-square", "df", "P")
    sci_xlsx_single_header_booktabs(
      file.path(tab_dir, sprintf("Table S15-%s. Proportional hazards assessment.xlsx", nm)),
      title = "Table S15. Proportional hazards assessment (Schoenfeld residuals, cox.zph)",
      df_body = sub,
      footnotes = c(
        "Global and term-wise Schoenfeld residual tests from Model 3 Cox models with the five-level sleep grouping.",
        paste0("Model 3 covariates: ", paste(m3, collapse = ", "), "."),
        "NHANES models in the primary Cox tables are survey-weighted; this diagnostic uses the unweighted complete-case Model 3 fit on the first imputed dataset for operational consistency."
      )
    )
    message("S15 ", nm)
  }
}

message("==== [3/6] Refresh figure formats (dpi>=600) ====")
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
# only force-refresh Fig4 raster; ensure_formats will sync all stems from pdf
unlink(list.files(file.path(sum_root, "Figures", "png"), pattern = "^Figure 4\\.", full.names = TRUE))
unlink(list.files(file.path(sum_root, "Figures", "tiff"), pattern = "^Figure 4\\.", full.names = TRUE))
pub_figure_ensure_formats(
  file.path(sum_root, "Figures"),
  meta = list(
    databases = c("NHANES", "CHARLS", "SHHS"),
    exposure = "Sleep duration",
    outcome = "All-cause mortality",
    tables_dir = tab_dir
  )
)

message("==== [4/6] Methods + software versions (finalize_delivery_root) ====")
Sys.setenv(
  PV2_PROFILE = "sleep_dyslipidemia",
  PV2_COHORT = "adults aged 45 years or older with dyslipidemia",
  PV2_MODEL3 = paste(m3, collapse = ", "),
  PV2_GROUPING = "five mutually exclusive categories (<5 h, 5-6 h, 6-7 h, 7-8 h, >=9 h; reference 7-8 h)",
  PV2_SENSITIVITY = "exclusion of deaths within the first year (Table S5) and a 5-year administrative horizon (Table S3)",
  PV2_MEDIATOR = "diastolic blood pressure (DBP)",
  PV2_EXPOSURE = "sleep duration"
)
cmd_fin <- sprintf(
  "Rscript %s --dir %s --study-type prognosis_v2 --outcome %s --exposure %s --databases %s",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(sum_root),
  shQuote("all-cause mortality"),
  shQuote("sleep duration"),
  shQuote("NHANES,SHHS,CHARLS")
)
status <- system(cmd_fin)
if (!identical(as.integer(status), 0L)) stop("finalize_delivery_root failed")

message("==== [5/6] Nature structure QC stub ====")
cmd_qc <- sprintf(
  "Rscript %s --project %s",
  shQuote(file.path(engine, "run/pub/run_pub_qc_after_project.R")),
  shQuote(proj_root)
)
# QC writes into reports/; later pruned to workspace
invisible(system(cmd_qc))

if (!isTRUE(has_flag("--skip-midterm"))) {
  message("==== [6/6] Midterm PDF + prune whitelist ====")
  content <- file.path(sum_root, "content.json")
  .pv2_latest_workspace <- function(root) {
    ws <- paste0(root, "_delivery_workspace")
    if (!dir.exists(ws)) return(NA_character_)
    # prefer newest timestamped stamp, else workspace root
    stamps <- list.dirs(ws, full.names = TRUE, recursive = FALSE)
    stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
    cands <- c(stamps, ws)
    for (d in cands) {
      if (file.exists(file.path(d, "content.json"))) return(d)
    }
    NA_character_
  }
  if (!file.exists(content)) {
    wdir <- .pv2_latest_workspace(sum_root)
    if (!is.na(wdir)) {
      file.copy(file.path(wdir, "content.json"), content, overwrite = TRUE)
      info <- file.path(wdir, "项目信息-中期.md")
      if (file.exists(info)) {
        file.copy(info, file.path(sum_root, "项目信息-中期.md"), overwrite = TRUE)
      }
    }
  }
  build_py <- file.path(engine, ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py")
  # 交付根只保留一份中期 PDF（课题描述文件名）；勿再双写「中期分析报告.pdf」
  out_pdf <- file.path(sum_root, "睡眠时间_全因死亡_Cox比例风险模型_中期分析结果.pdf")
  if (file.exists(build_py) && file.exists(content)) {
    cmd_m <- sprintf(
      "python3 %s --build --project %s --content %s --out %s",
      shQuote(build_py), shQuote(sum_root), shQuote(content), shQuote(out_pdf)
    )
    status_m <- system(cmd_m)
    if (identical(as.integer(status_m), 0L) && file.exists(out_pdf)) {
      # 清理历史双写残留
      old_dup <- file.path(sum_root, "中期分析报告.pdf")
      if (file.exists(old_dup)) unlink(old_dup)
    } else {
      warning("midterm build failed or skipped; continuing to prune")
    }
  } else {
    warning("content.json or build_report.py missing; skip midterm rebuild")
  }
}

# final prune — delivery root whitelist only
cmd_pr <- sprintf(
  "Rscript %s --dir %s --prune-only",
  shQuote(file.path(engine, "run/pub/finalize_delivery_root.R")),
  shQuote(sum_root)
)
status_p <- system(cmd_pr)
message("DELIVERY_OK root=", sum_root, " prune_status=", status_p)
invisible(TRUE)
