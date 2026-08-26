#!/usr/bin/env Rscript
# 将听力损失 UHR 三库表/图编号与内容对齐到 MAFLD TyG_WHtR 模板：
# S1 插补 | S2 正态 | S3 单因素 | S4 单因素VIF | S5 多因素 | S6 最终VIF
# S7 指标~实验室关联 | S8 中介 | S9/S10 NHANES不加权敏感性 | S-XX RCS分组logistic
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
dual_dir <- file.path(study, "by_index", "【success】UHR")
arc <- file.path(study, "_archive/by_index_before_unify_20260729_134507")
arc_success <- file.path(arc, "【success】UHR")
arc_lil <- file.path(arc, "UHR", "Liling")  # archive 仍用旧名 Liling
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
Sys.setenv(STUDY_CONFIG_DIR = study)
source(file.path(study, "config_incidence_dual_batch.R"))

cp_one <- function(src, dest) {
  if (!file.exists(src)) {
    cli::cli_alert_warning("missing src: {src}")
    return(FALSE)
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest, overwrite = TRUE)
  cli::cli_alert_success("→ {basename(dest)}")
  TRUE
}

# 1) 各库 Tables：补齐角色文件（编号交给 realign / 手动 Liling）
align_db_tables <- function(db, tab_dir, src_s5, src_s6, src_assoc) {
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  # 当前错位：S5=RCS → 先改成可识别的 RCS 名；S6=中介保留关键词
  rcs <- list.files(tab_dir, pattern = "RCS groups|RCS cutoff", full.names = TRUE, ignore.case = TRUE)
  for (f in rcs) {
    bn <- basename(f)
    if (!grepl("Table S-XX", bn, ignore.case = TRUE)) {
      new <- file.path(tab_dir, sub("^Table S\\d+", "Table S-XX", bn, perl = TRUE))
      if (!identical(f, new)) {
        if (file.exists(new)) unlink(new)
        file.rename(f, new)
      }
    }
  }
  med <- list.files(tab_dir, pattern = "mediation by laboratory", full.names = TRUE, ignore.case = TRUE)
  # 去掉错误占位的 S5/S6 若已是 RCS/med 已处理

  # 删掉误标的敏感性号（稍后用正确角色名放回）
  # NHANES 敏感性
  if (identical(db, "NHANES")) {
    ub <- list.files(tab_dir, pattern = "unweighted sensitivity analysis", full.names = TRUE, ignore.case = TRUE)
    ul <- list.files(tab_dir, pattern = "unweighted sensitivity\\)\\.xlsx$|GLM, unweighted sensitivity", full.names = TRUE, ignore.case = TRUE)
    # ensure names classifiable
    for (f in ub) {
      dest <- file.path(tab_dir, sprintf(
        "Table S9-%s. Baseline characteristics of hearing loss (unweighted sensitivity analysis).xlsx", db
      ))
      if (!identical(normalizePath(f, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) {
        file.copy(f, dest, overwrite = TRUE)
        if (!identical(f, dest)) unlink(f)
      }
    }
    for (f in ul) {
      dest <- file.path(tab_dir, sprintf(
        "Table S10-%s. Logistic regression analysis of UHR and hearing loss - quartile (GLM, unweighted sensitivity).xlsx", db
      ))
      if (!identical(normalizePath(f, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) {
        file.copy(f, dest, overwrite = TRUE)
        if (!identical(f, dest)) unlink(f)
      }
    }
  }

  # 恢复 S5 多因素 / S6 最终 VIF / S7 关联
  cp_one(src_s5, file.path(tab_dir, sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db)))
  if (identical(db, "NHANES")) {
    cp_one(src_s6, file.path(tab_dir, sprintf(
      "Table S6-%s. Weighted Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx", db
    )))
    cp_one(src_assoc, file.path(tab_dir, sprintf(
      "Table S7-%s. Weighted associations between UHR and laboratory indicators (NHANES).xlsx", db
    )))
  } else {
    cp_one(src_s6, file.path(tab_dir, sprintf(
      "Table S6-%s. Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx", db
    )))
    cp_one(src_assoc, file.path(tab_dir, sprintf(
      "Table S7-%s. The associations between UHR and laboratory indicators.xlsx", db
    )))
  }

  # 中介统一为可分类名（暂用 S8，realign 会校正）
  meds <- list.files(tab_dir, pattern = "mediation by laboratory", full.names = TRUE, ignore.case = TRUE)
  if (length(meds)) {
    src_med <- meds[1]
    if (identical(db, "NHANES")) {
      dest <- file.path(tab_dir, sprintf(
        "Table S8-%s. Weighted mediation by laboratory indicators of the associations of UHR (NHANES).xlsx", db
      ))
    } else {
      dest <- file.path(tab_dir, sprintf(
        "Table S8-%s. Analysis of the mediation by laboratory indicators of the associations of UHR.xlsx", db
      ))
    }
    file.copy(src_med, dest, overwrite = TRUE)
    for (f in meds) if (!identical(normalizePath(f, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) unlink(f)
  }

  invisible(TRUE)
}

align_db_tables(
  "NHANES",
  file.path(dual_dir, "NHANES", "Tables"),
  file.path(arc_success, "NHANES/Tables/Table S5-NHANES. Multivariable Regression Analysis.xlsx"),
  file.path(arc_success, "NHANES/Tables/Table S6-NHANES. Weighted Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx"),
  file.path(arc_success, "NHANES/Tables/Table S8-NHANES. Weighted associations between UHR and laboratory indicators (NHANES).xlsx")
)
align_db_tables(
  "CHARLS",
  file.path(dual_dir, "CHARLS", "Tables"),
  file.path(arc_success, "CHARLS/Tables/Table S5-CHARLS. Multivariable Regression Analysis.xlsx"),
  file.path(arc_success, "CHARLS/Tables/Table S6-CHARLS. Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx"),
  file.path(arc_success, "CHARLS/Tables/Table S8-CHARLS. The associations between UHR and laboratory indicators.xlsx")
)
align_db_tables(
  "Single",
  file.path(dual_dir, "Single", "Tables"),
  file.path(arc_lil, "Tables/Table S5-Liling. Multivariable Regression Analysis.xlsx"),
  file.path(arc_lil, "Tables/Table S6-Liling. Multicollinearity Analysis (VIF, multivariate p 0.05).xlsx"),
  file.path(arc_lil, "Tables/Table S8-Liling. The associations between UHR and laboratory indicators.xlsx")
)

# 2) realign NHANES/CHARLS（引擎只认 dual 两库标签）
for (db in c("NHANES", "CHARLS")) {
  n <- incidence_batch_realign_dual_supp_tables(file.path(dual_dir, db, "Tables"), config)
  cli::cli_alert_info("{db} realign touched ~{n}")
}

# 3) Single 手动对齐到同一角色序号（引擎 extract 不含 Single 单库）
single_map <- list(
  list(pat = "before and after multiple imputation", s = 1L),
  list(pat = "Normality test", s = 2L),
  list(pat = "Univariate Regression", s = 3L),
  list(pat = "univariate p", s = 4L),
  list(pat = "Multivariable Regression", s = 5L),
  list(pat = "multivariate p", s = 6L),
  list(pat = "associations between", s = 7L),
  list(pat = "mediation by laboratory", s = 8L)
)
single_tab <- file.path(dual_dir, "Single", "Tables")
for (m in single_map) {
  fs <- list.files(single_tab, pattern = m$pat, full.names = TRUE, ignore.case = TRUE)
  fs <- fs[grepl("\\.xlsx$", fs, ignore.case = TRUE)]
  if (!length(fs)) next
  f <- fs[1]
  bn <- basename(f)
  new_bn <- sub("^Table S(?:\\d+|-XX)", sprintf("Table S%d", m$s), bn, perl = TRUE, ignore.case = TRUE)
  new_bn <- gsub("-Liling\\.", "-Single.", new_bn)
  new_path <- file.path(single_tab, new_bn)
  if (!identical(normalizePath(f, mustWork = FALSE), normalizePath(new_path, mustWork = FALSE))) {
    if (file.exists(new_path)) unlink(new_path)
    file.copy(f, new_path, overwrite = TRUE)
    if (!identical(f, new_path)) unlink(f)
    f <- new_path
  }
  incidence_batch_sync_supp_table_title(f, new_s = m$s)
}
# Single RCS → S-XX
rcs_l <- list.files(single_tab, pattern = "RCS groups|RCS cutoff", full.names = TRUE, ignore.case = TRUE)
for (f in rcs_l) {
  bn <- basename(f)
  new_bn <- sub("^Table S(?:\\d+|-XX)", "Table S-XX", bn, perl = TRUE, ignore.case = TRUE)
  new_bn <- gsub("-Liling\\.", "-Single.", new_bn)
  new_path <- file.path(single_tab, new_bn)
  if (!identical(normalizePath(f, mustWork = FALSE), normalizePath(new_path, mustWork = FALSE))) {
    if (file.exists(new_path)) unlink(new_path)
    file.copy(f, new_path, overwrite = TRUE)
    if (!identical(f, new_path)) unlink(f)
    f <- new_path
  }
  incidence_batch_sync_supp_table_title(f, new_s = "XX")
}

# 4) 重建指标根 Tables/Figures（对齐 MAFLD 扁平汇总）
agg_tab <- file.path(dual_dir, "Tables")
agg_fig <- file.path(dual_dir, "Figures")
dir.create(agg_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(agg_fig, recursive = TRUE, showWarnings = FALSE)
# 清旧再汇
unlink(list.files(agg_tab, full.names = TRUE))
# 保留 flowchart
keep_fc <- list.files(agg_fig, pattern = "Figure 1\\. Flowchart", full.names = TRUE)
unlink(setdiff(list.files(agg_fig, full.names = TRUE), keep_fc))

for (db in c("NHANES", "CHARLS", "Single")) {
  src_t <- file.path(dual_dir, db, "Tables")
  src_f <- file.path(dual_dir, db, "Figures")
  for (f in list.files(src_t, pattern = "\\.xlsx$", full.names = TRUE)) {
    file.copy(f, file.path(agg_tab, basename(f)), overwrite = TRUE)
  }
  for (f in list.files(src_f, pattern = "\\.(pdf|png)$", full.names = TRUE, ignore.case = TRUE)) {
    bn <- basename(f)
    if (identical(bn, "Figure Missing Value Overview.pdf")) {
      # MAFLD 根目录只留一份；三库则带库标签放到 summary，根目录也按 MAFLD 留无标签一份优先 NHANES
      if (identical(db, "NHANES")) {
        file.copy(f, file.path(agg_fig, bn), overwrite = TRUE)
      }
    } else {
      file.copy(f, file.path(agg_fig, bn), overwrite = TRUE)
    }
  }
}
# flowchart
fc_cands <- c(
  file.path(dual_dir, "Figures/Figure 1. Flowchart.pdf"),
  file.path(study, "by_index/UHR/Figures/Figure 1. Flowchart.pdf")
)
for (fc in fc_cands) {
  if (file.exists(fc)) {
    if (!identical(normalizePath(fc, mustWork=FALSE), normalizePath(file.path(agg_fig, "Figure 1. Flowchart.pdf"), mustWork=FALSE))) file.copy(fc, file.path(agg_fig, "Figure 1. Flowchart.pdf"), overwrite = TRUE)
    break
  }
}

# aggregate realign（NHANES+CHARLS）
incidence_batch_realign_dual_supp_tables(agg_tab, config)

cli::cli_h2("Aligned inventory")
for (db in c("NHANES", "CHARLS", "Single", "")) {
  d <- if (nzchar(db)) file.path(dual_dir, db, "Tables") else agg_tab
  label <- if (nzchar(db)) db else "AGG"
  cli::cli_alert_info("{label}:")
  print(sort(list.files(d, pattern = "\\.xlsx$")))
}
cli::cli_alert_info("AGG Figures:")
print(sort(list.files(agg_fig, pattern = "\\.(pdf|png)$", ignore.case = TRUE)))

cli::cli_alert_success("MAFLD-style numbering restore done")
