#!/usr/bin/env Rscript
# 三库亚组森林图（Fig 3）重跑：变量集 + 水平名 + 顺序强制一致；不含 Pooled
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

.cl_pick_study_root <- function(args, default = NULL) {
  env <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
  if (nzchar(env)) return(env)
  i <- match("--study-root", args)
  if (!is.na(i) && i < length(args)) {
    tail_args <- args[(i + 1L):length(args)]
    next_flag <- which(grepl("^--", tail_args))
    chunk <- if (length(next_flag)) tail_args[seq_len(next_flag[1] - 1L)] else tail_args
    if (length(chunk)) return(paste(chunk, collapse = " "))
  }
  default
}

args <- commandArgs(trailingOnly = TRUE)
study_root <- NULL
only_dbs <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_dbs <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else i <- i + 1L
}
if (is.null(study_root) || !nzchar(study_root))
  study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
study_root <- .cl_pick_study_root(args, study_root)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/subgroup_vars.R"))
source(file.path(root, "R/subgroup_forest_plot.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "Blocks/18_subgroup/02block_subgroup_incidence.R"))

options(warn = 1, cli.hyperlink = FALSE)

.meta <- cross_lagged_study_meta(study_root)
.sg <- cross_lagged_fig3_lock(.meta)
.SG_LOCK <- .sg$vars
.SG_AGE_CUT <- as.integer(.sg$age_cutoff %||% 70L)[1L]
.index <- as.character(.sg$index_var %||% .meta$index_var %||% "FI")[1L]

if (is.null(only_dbs) || !length(only_dbs)) {
  only_dbs <- as.character(.meta$cohorts_xs %||% c("CHARLS", "ELSA", "HRS"))
}
only_dbs <- setdiff(only_dbs, "Pooled")
if (!length(only_dbs)) only_dbs <- as.character(.meta$cohorts_xs)

.lock_read_factors <- function(path, which = "Model2") {
  if (!file.exists(path)) return(character(0))
  lines <- readLines(path, warn = FALSE)
  hit <- grep(paste0("^", which, "="), lines, value = TRUE)
  if (length(hit)) {
    raw <- sub(paste0("^", which, "="), "", hit[[1L]])
    out <- trimws(unlist(strsplit(raw, ",")))
    return(out[nzchar(out)])
  }
  hdr <- grep(paste0("^", which, ":\\s*$"), lines)
  if (!length(hdr)) return(character(0))
  rest <- lines[(hdr[[1L]] + 1L):length(lines)]
  stop_at <- grep("^(Model|#|[A-Za-z_]+=)", rest)
  if (length(stop_at)) rest <- rest[seq_len(stop_at[[1L]] - 1L)]
  rest <- trimws(rest)
  rest[nzchar(rest) & !grepl("^#", rest)]
}

lock_file <- file.path(study_root, "phase2_Pooled", "locked_covariates.txt")
acc <- file.path(study_root, "phase3_relock_acceptance.txt")
m1 <- .lock_read_factors(lock_file, "Model1")
m2 <- .lock_read_factors(lock_file, "Model2")
if (!length(m2) && file.exists(acc)) {
  m2l <- grep("^Model2_single=", readLines(acc, warn = FALSE), value = TRUE)
  if (length(m2l)) {
    raw <- sub("^Model2_single=", "", m2l[[1L]])
    m2 <- trimws(unlist(strsplit(raw, "\\+|,")))
    m2 <- m2[nzchar(m2)]
  }
}
if (!length(m1)) m1 <- if (identical(.meta$kind, "circadian")) c("Gender", "Marital_Status") else "Age"
if (!length(m2)) m2 <- if (identical(.meta$kind, "circadian")) {
  c("Gender", "Marital_Status", "Alcohol_drinking", "Weight", "Hypertension", "Diabetes")
} else {
  c("Age", "Alcohol_drinking")
}

for (db in only_dbs) {
  cli::cli_h1("Subgroup harmonized re-run: {db}")
  out_dir <- cross_lagged_phase1_dir(study_root, db)
  ck_path <- file.path(out_dir, "checkpoints", "step09_multicollinearity_final.rds")
  if (!file.exists(ck_path))
    ck_path <- file.path(out_dir, "checkpoints", "multicollinearity_final.rds")
  if (!file.exists(ck_path)) stop("无检查点: ", db, " @ ", ck_path)
  ck <- readRDS(ck_path)
  if (!is.null(ck$ctx)) ck <- ck$ctx

  cfg_path <- file.path(study_root, paste0("config_phase1_", db, ".R"))
  e <- new.env(parent = globalenv())
  if (file.exists(cfg_path)) sys.source(cfg_path, envir = e)
  config <- e$config %||% list()
  config$project$output_dir <- out_dir
  if (identical(db, "NHANES")) {
    config$project$database <- "USA"
    config$project$database_type <- config$project$database_type %||% "regular"
  } else {
    config$project$database <- db
  }
  config$project$analysis_group <- config$project$analysis_group %||% .sg$analysis_group
  config$project$reference_group <- config$project$reference_group %||% .sg$reference_group
  if (is.null(config$data)) config$data <- list()
  config$data$outcome_column <- config$data$outcome_column %||% .sg$outcome_column
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$index_var <- .index
  if (is.null(config$incidence)) config$incidence <- list()
  config$incidence$index_var <- .index
  config$incidence$outcome_var <- config$data$outcome_column
  if (is.null(config$subgroup)) config$subgroup <- list()
  config$subgroup$var_source <- "required"
  config$subgroup$required_subgroup_vars <- .SG_LOCK
  config$subgroup$age_cutoff <- .SG_AGE_CUT
  config$subgroup$min_n <- 20L
  config$subgroup$continuous_subgroup_vars <- character(0)
  config$subgroup$level_order <- utils::modifyList(
    config$subgroup$level_order %||% list(),
    .sg$level_order %||% list()
  )

  dat <- ck$data$imputed %||% ck$data$cleaned
  dat <- cross_lagged_attach_harmonize_fig3(dat, study_root, db, .sg)
  miss <- setdiff(.SG_LOCK, names(dat))
  if (length(miss)) {
    stop(db, " 亚组锁定列仍缺失: ", paste(miss, collapse = ", "))
  }
  ck$data$imputed <- dat
  if (!is.null(ck$data$cleaned)) {
    ck$data$cleaned <- cross_lagged_attach_harmonize_fig3(
      ck$data$cleaned, study_root, db, .sg
    )
  }

  ctx <- list(
    data = ck$data,
    results = list(
      Model1Factors = m1,
      Model2Factors = m2,
      categorical_vars = .SG_LOCK
    ),
    config = config,
    log = list(),
    root_output_dir = out_dir,
    output_dir = out_dir,
    output_dir_figures = file.path(out_dir, "Figures"),
    output_dir_tables = file.path(out_dir, "Tables")
  )
  dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)

  ctx <- block_subgroup_incidence(ctx)
  used <- ctx$results$subgroup_vars_used %||% character(0)
  cli::cli_alert_success(
    "{db} Fig3 vars ({length(used)}): {paste(used, collapse=' → ')}"
  )
  if (!identical(as.character(used), as.character(.SG_LOCK))) {
    cli::cli_alert_warning(
      "{db} 实际亚组与锁定不一致: used={paste(used, collapse='+')} lock={paste(.SG_LOCK, collapse='+')}"
    )
  }

  fig_pat <- paste0("Subgroup Forest analyses of ", .index, "\\.pdf$")
  hits <- list.files(
    file.path(out_dir, "Figures"),
    pattern = fig_pat,
    full.names = TRUE, ignore.case = TRUE
  )
  hits_new <- hits[!grepl(paste0("^Figure 3-", db, "\\."), basename(hits))]
  if (!length(hits_new)) hits_new <- hits
  fig_src <- if (length(hits_new)) {
    hits_new[order(file.info(hits_new)$mtime, decreasing = TRUE)][[1L]]
  } else NA_character_
  dest_name <- paste0("Figure 3-", db, ". Subgroup Forest analyses of ", .index, ".pdf")
  dest_phase <- file.path(out_dir, "Figures", dest_name)
  dest_sum <- file.path(study_root, "summary_result", "figure", dest_name)
  if (isTRUE(file.exists(fig_src))) {
    dir.create(dirname(dest_sum), recursive = TRUE, showWarnings = FALSE)
    if (!identical(normalizePath(fig_src, winslash = "/", mustWork = FALSE),
                   normalizePath(dest_phase, winslash = "/", mustWork = FALSE))) {
      file.copy(fig_src, dest_phase, overwrite = TRUE)
    }
    file.copy(fig_src, dest_sum, overwrite = TRUE)
    cli::cli_alert_success("copied {basename(fig_src)} → {dest_name}")
  } else {
    cli::cli_alert_warning("未找到 Subgroup Forest PDF for {db}")
  }
}

txt <- c(
  paste0("time=", format(Sys.time(), "%F %T")),
  paste0("figure=Figure 3 Subgroup Forest analyses of ", .index),
  paste0("kind=", .meta$kind %||% "unknown"),
  paste0("cohorts=", paste(only_dbs, collapse = ","), " (no Pooled)"),
  "var_source=required",
  paste0("locked_vars=", paste(.SG_LOCK, collapse = "+")),
  paste0("age_cutoff=", .SG_AGE_CUT, if (isTRUE(.sg$use_age_group)) " (Age_Group on)" else " (Age_Group off)"),
  paste0("order=", paste(.SG_LOCK, collapse = " → ")),
  paste0("note=", .sg$note %||% "Pooled subgroup forest not included")
)
dir.create(file.path(study_root, "summary_result", "table"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(study_root, "phase2_Pooled"), recursive = TRUE, showWarnings = FALSE)
writeLines(txt, file.path(study_root, "phase2_Pooled", "Figure3_subgroup_var_lock.txt"))
writeLines(txt, file.path(study_root, "summary_result", "table", "Figure3_subgroup_var_lock.txt"))
unlink(file.path(
  study_root, "summary_result", "figure",
  paste0("Figure 3-Pooled. Subgroup Forest analyses of ", .index, ".pdf")
))
unlink(file.path(
  study_root, "summary_result", "figure",
  "Figure 3-Pooled. Subgroup Forest analyses of FI.pdf"
))
cli::cli_alert_success(
  "三库亚组 Fig3 锁定重跑完成（无 Pooled；vars={paste(.SG_LOCK, collapse='+')}）"
)
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
