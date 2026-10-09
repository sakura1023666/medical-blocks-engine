#!/usr/bin/env Rscript
# Blocks/54_cross_lagged_full/phases/phase_vif_pooled.R
# 三库 --from baseline_binary --to multicollinearity_final，再按锁定规则 pooled_bind
#
# 三库协变量锁定：
#   VIF final 交集 → 若空则回退 VIF screen（UV p<0.1）交集
#   （见 R/cross_lagged_covariate_lock.R）
# --- engine root (Blocks/54/.../phases 或 legacy run/cross_lagged) ---
.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
.cl_resolve_engine_root <- function(script_path) {
  if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run")
    return(normalizePath(file.path(script_path, "..", ".."), winslash = "/"))
  if (basename(script_path) == "phases" && grepl("54_cross_lagged", basename(dirname(script_path)), fixed = TRUE))
    return(normalizePath(file.path(script_path, "..", "..", ".."), winslash = "/"))
  if (grepl("54_cross_lagged", basename(script_path), fixed = TRUE))
    return(normalizePath(file.path(script_path, "..", ".."), winslash = "/"))
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env) && dir.exists(env)) return(normalizePath(env, winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- .cl_resolve_engine_root(script_path)
setwd(root)

# study_root: prefer env (spaces-safe), then CLI; rejoin if path was split
.cl_pick_study_root <- function(args, default = NULL) {
  env <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
  if (nzchar(env)) return(env)
  i <- match("--study-root", args)
  if (!is.na(i) && i < length(args)) {
    # take rest of argv if accidental shell split on spaces after --study-root
    tail_args <- args[(i + 1L):length(args)]
    next_flag <- which(grepl("^--", tail_args))
    chunk <- if (length(next_flag)) tail_args[seq_len(next_flag[1] - 1L)] else tail_args
    if (length(chunk)) return(paste(chunk, collapse = " "))
  }
  default
}


args <- commandArgs(trailingOnly = TRUE)
study_root <- NULL
# will resolve via .cl_pick_study_root after args parse
skip_vif <- FALSE
from_start <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--pooled-only") {
    skip_vif <- TRUE; i <- i + 1L
  } else if (args[[i]] == "--from-start") {
    from_start <- TRUE; i <- i + 1L
  } else i <- i + 1L
}
if (is.null(study_root) || !nzchar(study_root))
  study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
study_root <- .cl_pick_study_root(args, study_root %||% NULL)
if (is.null(study_root) || !nzchar(as.character(study_root)[1L])) {
  study_root <- .cl_pick_study_root(args, "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/cross_lagged_table1_harmonize.R"))
source(file.path(root, "R/cross_lagged_covariate_lock.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R"))

.meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
vif_cohorts <- if (!is.null(.meta)) {
  cross_lagged_covariate_lock_cohorts(.meta)
} else {
  c("CHARLS", "ELSA", "HRS")
}
pooled_cohorts <- if (!is.null(.meta)) {
  cross_lagged_pooled_cohorts(.meta)
} else {
  vif_cohorts
}
if (!length(vif_cohorts)) {
  vif_cohorts <- c("CHARLS", "ELSA", "HRS")
  if (file.exists(file.path(study_root, "config_phase2_NHANES.R")) &&
      !"NHANES" %in% cross_lagged_validation_cohorts(.meta %||% list()))
    vif_cohorts <- c("CHARLS", "ELSA", "NHANES")
}
.idx_var <- as.character((.meta$index_var %||% "FI"))[1L]
.cfg1 <- file.path(study_root, "config_phase1_CHARLS.R")
if (file.exists(.cfg1)) {
  .e1 <- new.env(parent = globalenv())
  try(sys.source(.cfg1, envir = .e1), silent = TRUE)
  .idx_var <- as.character((.e1$config$incidence %||% list())$index_var %||% "FI")[1L]
}
options(warn = 1, cli.hyperlink = FALSE)

if (!isTRUE(skip_vif)) {
  for (db in vif_cohorts) {
    cfg_path <- file.path(study_root, paste0("config_phase2_", db, ".R"))
    cli::cli_h1("Phase2 VIF: {db}")
    e <- new.env(parent = globalenv())
    sys.source(cfg_path, envir = e)
    e$config <- cross_lagged_apply_table1_harmonized(e$config, root)
    run_opts <- if (isTRUE(from_start)) {
      list(to = "multicollinearity_final")
    } else {
      list(from = "baseline_binary", to = "multicollinearity_final")
    }
    run_pipeline(
      root,
      config = e$config,
      pipeline = e$pipeline,
      run_opts = run_opts
    )
  }
}

# --- collect imputed ---
load_ck <- function(db) {
  cdir <- file.path(cross_lagged_phase1_dir(study_root, db), "checkpoints")
  cands <- list.files(cdir, pattern = "multicollinearity_final\\.rds$", full.names = TRUE)
  if (!length(cands)) cands <- list.files(cdir, pattern = "final\\.rds$", full.names = TRUE)
  if (!length(cands)) stop("找不到 multicollinearity_final 检查点: ", db)
  hit <- cands[grepl("multicollinearity_final", basename(cands))]
  if (!length(hit)) hit <- cands
  readRDS(hit[[1]])
}

cli::cli_h1("开发队列协变量锁定（Table S4 / VIF_screen 交集）")
lock <- cross_lagged_resolve_covariate_lock(study_root, .meta)
for (line in cross_lagged_format_lock_report(lock)) cli::cli_alert_info(line)
if (isTRUE(lock$empty) || !length(lock$model2)) {
  stop("开发队列 VIF 交集为空，无法锁定 Model2", call. = FALSE)
}
if (!length(lock$model1) && "Age" %in% lock$model2) lock$model1 <- "Age"
cli::cli_alert_success(
  "Model1={paste(lock$model1, collapse=' + ')} | Model2={paste(lock$model2, collapse=' + ')}  [source={lock$source}; cohorts={paste(lock$lock_cohorts, collapse=',')}]"
)

imputed_list <- list()
model2_list <- list()
for (db in pooled_cohorts) {
  ck <- load_ck(db)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  d <- ck$data$imputed %||% ck$data$cleaned
  if (is.null(d)) stop("无 imputed: ", db)
  # 缺列警告（如 CHARLS 可能缺某协变量时剔除但保持尽量一致）
  miss_v <- setdiff(lock$model2, names(d))
  if (length(miss_v)) {
    cli::cli_alert_warning("{db} imputed 缺锁定列: {paste(miss_v, collapse = ', ')}")
  }
  imputed_list[[db]] <- d
  model2_list[[db]] <- lock$model2
  cli::cli_alert_info(
    "{db}: N={nrow(d)}; locked_M2={paste(lock$model2, collapse=', ')}; raw_final={paste(lock$by_db_final[[db]] %||% character(0), collapse=', ')}; raw_screen={paste(lock$by_db_screen[[db]] %||% character(0), collapse=', ')}"
  )
}

cli::cli_h1("Pooled bind")
ctx <- list(
  config = list(
    project = list(output_dir = file.path(study_root, "phase2_Pooled")),
    cross_lagged_pooled_bind = list(
      country_map = list(CHARLS = "China", ELSA = "UK", HRS = "America", NHANES = "America"),
      force_country_in_model = TRUE,
      model1_locked = lock$model1,
      model2_locked = lock$model2,
      model2_clinical = lock$model2,
      lock_source = lock$source,
      index_var = .idx_var,
      harmonize = as.character((.meta %||% list())$pooled_harmonize %||% "")[1L],
      harmonized_index = as.character((.meta %||% list())$pooled_index %||% "")[1L],
      outcome_column = "Disease_Group",
      id_column = "ID"
    ),
    incidence = list(index_var = .idx_var),
    data = list(outcome_column = "Disease_Group", id_column = "ID")
  ),
  results = list(
    cohort_imputed_list = imputed_list,
    cohort_model2_list = model2_list,
    cross_lagged_covariate_lock = lock
  ),
  data = list()
)
dir.create(file.path(study_root, "phase2_Pooled", "Tables"), recursive = TRUE, showWarnings = FALSE)
ctx <- block_cross_lagged_pooled_bind(ctx)

dabiao <- ctx$data$imputed
save(dabiao, file = file.path(study_root, "data/harmonized/D04_Pooled_hip_postvif.RData"))
save(dabiao, file = file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData"))

lock_lines <- c(
  paste(c("Model1:", paste(ctx$results$Model1Factors, collapse = " + ")),
        paste("Model2:", paste(ctx$results$Model2Factors, collapse = " + ")),
        paste("Country_in_Model2:", "Country" %in% ctx$results$Model2Factors),
        paste("lock_source:", lock$source),
        paste("intersect_final:", paste(lock$intersect_final, collapse = ", ")),
        paste("intersect_screen:", paste(lock$intersect_screen, collapse = ", ")),
        "rule: VIF final 三库交集；若空回退 VIF screen 三库交集；Pooled + Country",
        sep = "\n")
)
writeLines(lock_lines, file.path(study_root, "phase2_Pooled", "pooled_model_factors.txt"))
# 单库下游也可读同一锁定
writeLines(
  c(
    "# Cross-lagged locked covariates (development cohorts only)",
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    cross_lagged_format_lock_report(lock),
    "",
    "Model1:",
    lock$model1,
    "",
    "Model2:",
    lock$model2,
    "",
    "Model2_Pooled:",
    unique(c(lock$model2, "Country"))
  ),
  file.path(study_root, "phase2_Pooled", "locked_covariates.txt")
)

notes <- c(
  paste0("Pooled N=", nrow(dabiao)),
  paste0("Country in Model2=", "Country" %in% ctx$results$Model2Factors),
  paste0("Model2=", paste(ctx$results$Model2Factors, collapse = ", ")),
  paste0("lock_source=", lock$source),
  paste0("intersect_final=", paste(lock$intersect_final, collapse = ", ")),
  paste0("intersect_screen=", paste(lock$intersect_screen, collapse = ", ")),
  paste0("lock_cohorts=", paste(lock$lock_cohorts, collapse = ", ")),
  paste0("pooled_cohorts=", paste(pooled_cohorts, collapse = ", ")),
  paste0("validation_cohorts=", paste(lock$validation_cohorts %||% character(0), collapse = ", ")),
  "Pooled was NOT run through UV/VIF (bind after multicollinearity_final only).",
  "Lock rule: CHARLS+ELSA VIF screen intersect; validation cohorts apply locked set without re-screen."
)
writeLines(notes, file.path(study_root, "phase2_acceptance.txt"))
cli::cli_alert_success("Phase2 done. See phase2_acceptance.txt / locked_covariates.txt")
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
