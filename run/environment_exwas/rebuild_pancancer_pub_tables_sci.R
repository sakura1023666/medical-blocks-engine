#!/usr/bin/env Rscript
# 泛癌 ExWAS 交付 Tables → 标准 SCI 三线表（Times New Roman）
# 对齐 Dong 主文/补充表角色与版式；剔除 Table 0 / S0 / csv 等非交付项
#
#   Rscript run/environment_exwas/rebuild_pancancer_pub_tables_sci.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607"
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/environment_exwas_core.R"))

root <- opt$root
sum_tab <- file.path(root, "summary_results", "Tables")
src_tab <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
down <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "_downstream")
arch <- file.path(root, "summary_results_delivery_workspace", "archived_non_pub_tables")
dir.create(arch, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

exwas_log <- function(...) message("[exwas] ", paste0(..., collapse = ""))

.read_csv <- function(...) {
  p <- file.path(...)
  if (!file.exists(p)) return(NULL)
  utils::read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}
.find_csv <- function(nms) {
  for (nm in nms) {
    for (base in c(src_tab, down, sum_tab)) {
      p <- file.path(base, nm)
      if (file.exists(p)) return(p)
    }
  }
  NULL
}
.fmt_or_ci <- function(or, lo, hi) {
  or <- as.numeric(or); lo <- as.numeric(lo); hi <- as.numeric(hi)
  ifelse(
    is.finite(or) & is.finite(lo) & is.finite(hi),
    sprintf("%.3f (%.3f, %.3f)", or, lo, hi),
    ""
  )
}
.fmt_p <- function(p) {
  if (exists("pub_format_p", mode = "function")) {
    return(vapply(as.numeric(p), function(x) {
      if (!is.finite(x)) return("")
      pub_format_p(x)
    }, character(1)))
  }
  vapply(as.numeric(p), function(x) {
    if (!is.finite(x)) return("")
    if (x < 0.001) "<0.001" else sprintf("%.3f", x)
  }, character(1))
}
.disp <- function(x) {
  x <- as.character(x)
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x
}
.write_sci <- function(df, path, title, footnotes = NULL) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  names(df) <- .disp(names(df))
  for (j in seq_along(df)) if (is.character(df[[j]])) df[[j]] <- .disp(df[[j]])
  sci_xlsx_single_header_booktabs(
    filepath = path,
    title = title,
    df_body = df,
    sheet = "Table",
    footnotes = footnotes
  )
  exwas_log("写 ", basename(path), " n=", nrow(df))
}

# ---------- 归档非发表杂项 ----------
# 交付只到 S12（对齐原文补充表号）；S12b/S13–S15 与裸 csv 一律归档
junk_pat <- c(
  "^Table 0\\.",
  "^Table S0\\.",
  "^Table S0b\\.",
  "^Table S12b\\.",
  "^Table S13\\.",
  "^Table S14\\.",
  "^Table S15\\.",
  "^Table\\. ERS",
  "\\.csv$",
  "_summary\\.csv$"
)
for (bn in list.files(sum_tab)) {
  if (any(vapply(junk_pat, function(p) grepl(p, bn), logical(1)))) {
    file.rename(file.path(sum_tab, bn), file.path(arch, bn))
    exwas_log("归档 ", bn)
  }
}

# ---------- Table 1：Dong 版式（Variables / Total(n=) / 缩进水平 / italic P）----------
# 禁止再用扁平 gtsummary CSV 覆盖；走专用脚本
dong_t1 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table1_dong_style.R")
if (file.exists(dong_t1)) {
  exwas_log("Table 1 → Dong-style rebuild")
  status <- system2("Rscript", dong_t1, stdout = TRUE, stderr = TRUE)
  writeLines(status)
} else {
  exwas_log("WARN: Dong Table1 脚本缺失，跳过 Table 1")
}

# ---------- Table 2：Dong 主文版式（家族分组 + Median + Model1/Model2）----------
dong_t2 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table2_dong_style.R")
if (file.exists(dong_t2)) {
  exwas_log("Table 2 → Dong-style Model1+Model2 rebuild")
  status2 <- system2("Rscript", dong_t2, stdout = TRUE, stderr = TRUE)
  writeLines(status2)
} else {
  exwas_log("WARN: Dong Table2 脚本缺失，跳过 Table 2")
}

# helper for ExWAS-like sensitivity tables
.exwas_pub <- function(df) {
  nm <- if ("exposure_name" %in% names(df)) df$exposure_name else {
    if ("exposure" %in% names(df)) sub("_(ln|bin)$", "", df$exposure) else df[[1]]
  }
  fam <- if ("family" %in% names(df)) df$family else NA_character_
  data.frame(
    Family = .disp(fam),
    Exposure = .disp(nm),
    N = if ("n" %in% names(df)) as.integer(df$n) else NA_integer_,
    `OR (95% CI)` = .fmt_or_ci(df$OR, df$lo, df$hi),
    P = .fmt_p(df$p),
    q = .fmt_p(df$q),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

# ---------- S1：Dong 补充材料 12 列版式 ----------
dong_s1 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s1_dong_style.R")
if (file.exists(dong_s1)) {
  exwas_log("Table S1 → Dong-style rebuild")
  status_s1 <- system2("Rscript", dong_s1, stdout = TRUE, stderr = TRUE)
  writeLines(status_s1)
} else {
  exwas_log("WARN: Dong Table S1 脚本缺失，跳过")
}

# ---------- S2：Dong 版式 + 家族内 FDR ----------
dong_s2 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s2_dong_style.R")
if (file.exists(dong_s2)) {
  exwas_log("Table S2 → Dong-style familywise FDR rebuild")
  status_s2 <- system2("Rscript", dong_s2, stdout = TRUE, stderr = TRUE)
  writeLines(status_s2)
} else {
  exwas_log("WARN: Dong Table S2 脚本缺失，跳过")
}

# ---------- S3：Dong 性别分层宽表 ----------
dong_s3 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s3_dong_style.R")
if (file.exists(dong_s3)) {
  exwas_log("Table S3 → Dong-style sex-stratified wide rebuild")
  status_s3 <- system2("Rscript", dong_s3, stdout = TRUE, stderr = TRUE)
  writeLines(status_s3)
} else {
  exwas_log("WARN: Dong Table S3 脚本缺失，跳过")
}

# ---------- S4：Dong 年龄分层宽表 ----------
dong_s4 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s4_dong_style.R")
if (file.exists(dong_s4)) {
  exwas_log("Table S4 → Dong-style age-stratified wide rebuild")
  status_s4 <- system2("Rscript", dong_s4, stdout = TRUE, stderr = TRUE)
  writeLines(status_s4)
} else {
  exwas_log("WARN: Dong Table S4 脚本缺失，跳过")
}

# ---------- S5 ERS bootstrap ----------
s5p <- .find_csv(c(
  "Table S5. ERS bootstrap inclusion frequencies.csv",
  file.path(down, "Table_S5_ERS_bootstrap_inclusion.csv")
))
# .find_csv only looks in dirs with basename — handle down explicitly
if (is.null(s5p) && file.exists(file.path(down, "Table_S5_ERS_bootstrap_inclusion.csv"))) {
  s5p <- file.path(down, "Table_S5_ERS_bootstrap_inclusion.csv")
}
if (!is.null(s5p)) {
  s5 <- utils::read.csv(s5p, stringsAsFactors = FALSE)
  if ("exposure" %in% names(s5)) s5$Exposure <- .disp(sub("_(ln|bin)$", "", s5$exposure))
  keep <- intersect(c("Exposure", "exposure", "inclusion_n", "inclusion_freq", "selected_final", "coef",
                      "mean", "sd", "min", "max"), names(s5))
  if (!"Exposure" %in% names(s5) && "exposure" %in% names(s5)) {
    s5$Exposure <- .disp(sub("_(ln|bin)$", "", s5$exposure))
  }
  body <- s5[, intersect(c("Exposure", "inclusion_n", "inclusion_freq", "selected_final", "coef",
                           "mean", "sd"), names(s5)), drop = FALSE]
  names(body) <- .disp(names(body))
  .write_sci(
    body,
    file.path(sum_tab, "Table S5. ERS bootstrap inclusion and selection.xlsx"),
    "Table S5. Bootstrap inclusion frequencies and coefficients for ERS variables",
    footnotes = c(
      "Adaptive elastic-net on the full screened toxicant panel; bootstrap inclusion frequencies.",
      "Selected_final indicates variables retained in the final ERS."
    )
  )
}

# ---------- S6 mediation ----------
s6p <- .find_csv(c("Table S6. Mediation exploratory.csv"))
if (is.null(s6p) && file.exists(file.path(down, "Table_S6_mediation_exploratory.csv"))) {
  s6p <- file.path(down, "Table_S6_mediation_exploratory.csv")
}
if (!is.null(s6p)) {
  s6 <- utils::read.csv(s6p, stringsAsFactors = FALSE)
  names(s6) <- .disp(names(s6))
  .write_sci(
    s6,
    file.path(sum_tab, "Table S6. Mediation exploratory.xlsx"),
    "Table S6. Exploratory mediation between ERS and pan-cancer via clinical biomarkers",
    footnotes = c(
      "Exploratory mediation (R mediation package, 1000 bootstrap resamples); risk-difference scale.",
      "Mediators were selected by IDE significance under the locked Model 2 covariate set."
    )
  )
}

# ---------- S7 survey-weighted ExWAS（本课题敏感性；非 Dong 无插补）----------
s7p <- .find_csv(c("Table S7. ExWAS survey-weighted.csv"))
if (is.null(s7p) && file.exists(file.path(sum_tab, "..", "Tables"))) {
  # may have been archived? check src
  s7p <- .find_csv("Table S7. ExWAS survey-weighted.csv")
}
# also look in arch from earlier move? rebuild may need src_pub copy
if (is.null(s7p)) {
  cand <- file.path(src_tab, "Table S7. ExWAS survey-weighted.csv")
  if (file.exists(cand)) s7p <- cand
}
if (!is.null(s7p)) {
  raw <- utils::read.csv(s7p, stringsAsFactors = FALSE)
  body <- .exwas_pub(raw)
  .write_sci(
    body,
    file.path(sum_tab, "Table S7. ExWAS survey-weighted.xlsx"),
    "Table S7. Sensitivity analysis: survey-weighted ExWAS of environmental toxicants and pan-cancer",
    footnotes = c(
      "Dong main ExWAS was unweighted; this sensitivity uses WTSA2YR with complex survey design.",
      "Covariates multiply imputed (m=5) and pooled by Rubin's rules; same covariate set as Table 2."
    )
  )
}

# ---------- S8 / S9 smoke ----------
for (spec in list(
  list(csv = "Table S8. ExWAS additional Smoke adjustment.csv",
       out = "Table S8. ExWAS additional Smoke adjustment.xlsx",
       title = "Table S8. Sensitivity analysis: ExWAS with additional adjustment for smoking status",
       note = "Main ExWAS covariates plus Smoke."),
  list(csv = "Table S9. ExWAS among never-smokers.csv",
       out = "Table S9. ExWAS among never-smokers.xlsx",
       title = "Table S9. Sensitivity analysis: ExWAS among never-smokers",
       note = "Restricted to never-smokers; same covariates as Table 2 (without Smoke).")
)) {
  p <- .find_csv(spec$csv)
  if (is.null(p)) next
  body <- .exwas_pub(utils::read.csv(p, stringsAsFactors = FALSE))
  .write_sci(body, file.path(sum_tab, spec$out), spec$title, footnotes = spec$note)
}

# ---------- S10 ----------
s10p <- .find_csv(c(
  "Table S10. Per IQR and per unit associations for FDR hits.csv",
  "Table S10. Per IQR and per unit associations.csv"
))
if (!is.null(s10p)) {
  s10 <- utils::read.csv(s10p, stringsAsFactors = FALSE)
  names(s10) <- .disp(names(s10))
  .write_sci(
    s10,
    file.path(sum_tab, "Table S10. Per IQR and per unit associations.xlsx"),
    "Table S10. Association results per IQR and per unit increase for exposures",
    footnotes = c("Per-IQR estimates align with Table 2; per-unit estimates provided for interpretability.")
  )
}

# ---------- S11 E-value ----------
s11p <- .find_csv(c("Table S11. E-values for ERS association.csv"))
if (is.null(s11p) && file.exists(file.path(down, "Table_S11_Evalue_ERS.csv"))) {
  s11p <- file.path(down, "Table_S11_Evalue_ERS.csv")
}
if (!is.null(s11p)) {
  s11 <- utils::read.csv(s11p, stringsAsFactors = FALSE)
  names(s11) <- .disp(names(s11))
  .write_sci(
    s11,
    file.path(sum_tab, "Table S11. E-values for ERS association.xlsx"),
    "Table S11. E-values for the association between ERS and pan-cancer",
    footnotes = c("E-values for the survey-weighted Model 2 continuous ERS association.")
  )
}

# ---------- S12 methods comparison（四列：Aspect / Previous / Current / Novelty）----------
dong_s12 <- file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s12_dong_style.R")
if (file.exists(dong_s12)) {
  exwas_log("Table S12 → four-column methodological comparison rebuild")
  status_s12 <- system2("Rscript", dong_s12, stdout = TRUE, stderr = TRUE)
  writeLines(status_s12)
} else {
  exwas_log("WARN: Table S12 rebuild script missing, skip")
}

# S13–S15 / S12b 不进交付（图注数据留在 Output/_downstream）；末尾再扫 junk_pat 归档残留
for (bn in list.files(sum_tab)) {
  if (any(vapply(junk_pat, function(p) grepl(p, bn), logical(1)))) {
    file.rename(file.path(sum_tab, bn), file.path(arch, bn))
    exwas_log("归档 ", bn)
  }
}

# ---------- 校验字体 ----------
if (requireNamespace("openxlsx", quietly = TRUE)) {
  for (bn in list.files(sum_tab, pattern = "\\.xlsx$")) {
    p <- file.path(sum_tab, bn)
    ok <- tryCatch({
      # strip broken drawings first
      if (exists("pub_xlsx_strip", mode = "function")) {
        try(pub_xlsx_strip(p), silent = TRUE)
      }
      wb <- openxlsx::loadWorkbook(p)
      TRUE
    }, error = function(e) {
      exwas_log("仍不可读: ", bn, " — ", conditionMessage(e))
      FALSE
    })
  }
}

exwas_log("交付 Tables 现有: ", paste(list.files(sum_tab), collapse = " | "))
exwas_log("DONE")
