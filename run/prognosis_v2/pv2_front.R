# 预后 2.0 的前段：列名对齐之后、建模之前做 MICE。
# 不插补暴露、随访、结局、权重。不插补疾病定义列。
#
# 插补铁律（2026-10，对标专业 MI / 本库竞争风险块）：
# - 默认 m=5, maxit=5, seed=1234（cart）。
# - 禁止「m=5 却只报 complete#1 的 Cox HR」并写成多重插补。
# - 推断层（Cox）：m 套拟合 → R/mi_rubin_pool.R Rubin 合并（见 pv2_mi_cox.R）。
# - 操作层（Boruta/SHAP/KM/RCS/Table1）：用 complete#1，方法学须写明分层口径。
# - 索引文献 Jin 2026：关键变量缺失为删除（complete-case），未做 MICE；
#   本套路若做插补，须按 Rubin，不能只取第 1 套交差。

pv2_alignment_dict <- function() {
  data.frame(
    standard = c("Age", "Gender", "BMI", "Smoke", "Alcohol", "Hypertension", "Diabetes", "Education", "SBP",
                 "Sleep_hours", "futime_years", "fustatus"),
    role = c(rep("covariate_impute", 9), "exposure_no_impute", "time_no_impute", "event_no_impute"),
    NHANES = c("Age", "Gender", "BMI", "Smoke", "Alcohol_drinking", "Hypertension", "Diabetes", "Education", "NBPS",
               "SLD01", "permth_exm/12", "mortstat"),
    CHARLS = c("Age", "Gender", "BMI", "Smoke", "Alcohol_drinking", "Hypertension", "Diabetes", "Education", "NBPS",
               "da049_sleep_hrs", "exb001 year-month", "death_status"),
    SHHS = c("age_s1", "gender", "bmi_s1", "smokstat_s1", "alcoh", "htnderv_s1", "parrptdiab", "educat", "systbp",
             "hrswd02", "censdate/365.25", "vital==0"),
    stringsAsFactors = FALSE
  )
}

pv2_impute_aligned <- function(d, seed = 1234L, missing_col_threshold = 0.4,
                               m = 5L, maxit = 5L,
                               no_impute_extra = character(0)) {
  covs <- c("Age", "Gender", "BMI", "Smoke", "Alcohol", "Hypertension", "Diabetes", "Education", "SBP")
  covs <- covs[covs %in% names(d)]
  miss <- vapply(covs, function(v) mean(is.na(d[[v]])), numeric(1))
  drop <- names(miss)[is.finite(miss) & miss > missing_col_threshold]
  use <- setdiff(covs, drop)
  if (!length(use) || !any(vapply(use, function(v) anyNA(d[[v]]), logical(1)))) {
    return(list(data = d, miss = miss, dropped = drop, imputed = FALSE, mids = NULL, m = 0L))
  }
  m <- as.integer(m)[1L]
  if (!is.finite(m) || m < 1L) m <- 5L
  dat <- d[, use, drop = FALSE]
  for (v in use) {
    if (is.character(dat[[v]]) || is.factor(dat[[v]])) dat[[v]] <- factor(dat[[v]])
  }
  aux <- unique(c("fustatus", "Sleep_hours", no_impute_extra))
  aux <- aux[aux %in% names(d)]
  for (v in aux) dat[[v]] <- d[[v]]
  ini <- mice::mice(dat, maxit = 0, printFlag = FALSE)
  meth <- ini$method
  pred <- ini$predictorMatrix
  meth[aux] <- ""
  for (v in aux) pred[v, ] <- 0
  imp <- mice::mice(
    dat, m = m, maxit = as.integer(maxit)[1L], method = meth, predictorMatrix = pred,
    seed = seed, printFlag = FALSE
  )
  # 操作层：complete #1（Boruta/图）；推断层另存 mids 做 Rubin
  comp <- mice::complete(imp, 1L)
  for (v in use) d[[v]] <- comp[[v]]
  list(data = d, miss = miss, dropped = drop, imputed = TRUE, mids = imp, m = m)
}

pv2_impute_databases <- function(dbs, tab_dir, m = 5L, maxit = 5L, seed = 1234L) {
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite <- data.table::fwrite
  fwrite(pv2_alignment_dict(), file.path(tab_dir, "Column_alignment.csv"))
  rows <- list()
  out <- dbs
  mids_list <- list()
  for (nm in names(dbs)) {
    message(nm, " 插补（cart, m=", m, ", seed=", seed, "；Cox 将 Rubin 合并）")
    res <- pv2_impute_aligned(dbs[[nm]], seed = seed, m = m, maxit = maxit)
    out[[nm]] <- res$data
    if (!is.null(res$mids)) mids_list[[nm]] <- res$mids
    rows[[nm]] <- data.frame(
      database = nm, variable = names(res$miss),
      missing_rate = round(unname(res$miss), 4),
      dropped_over_40pct = names(res$miss) %in% res$dropped,
      stringsAsFactors = FALSE
    )
    if (length(res$dropped)) message(nm, " 缺失>40% 未插补: ", paste(res$dropped, collapse = ", "))
  }
  art_dir <- if (exists("pv2_ckpt_dir", inherits = TRUE)) get("pv2_ckpt_dir", inherits = TRUE) else tab_dir
  dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(do.call(rbind, rows), file.path(art_dir, "Imputation_missingness.csv"))
  saveRDS(out, file.path(art_dir, "imputed_dbs.rds"))
  if (length(mids_list)) {
    saveRDS(mids_list, file.path(art_dir, "imputed_mids.rds"))
  }
  src_mi <- c(
    "E:/01block/01Block-new-Final/run/prognosis_v2/pv2_mi_cox.R",
    "/mnt/e/01block/01Block-new-Final/run/prognosis_v2/pv2_mi_cox.R"
  )
  src_mi <- src_mi[file.exists(src_mi)][1L]
  if (!is.na(src_mi)) source(src_mi, local = FALSE)
  writeLines(
    if (exists("pv2_mi_methods_footnote", mode = "function")) {
      pv2_mi_methods_footnote(m, maxit, seed)
    } else {
      sprintf("MICE cart m=%d maxit=%d seed=%d; Cox uses Rubin's rules.", m, maxit, seed)
    },
    file.path(art_dir, "Imputation_methods_note.txt")
  )
  out
}
