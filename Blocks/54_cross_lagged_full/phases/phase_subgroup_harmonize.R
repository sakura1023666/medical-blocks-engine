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
.sg_scheme <- NULL
.want_pooled <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_dbs <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (args[[i]] == "--scheme" && i < length(args)) {
    .sg_scheme <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
  } else if (args[[i]] == "--pooled") {
    .want_pooled <- TRUE; i <- i + 1L
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
if (any(toupper(only_dbs) == "POOLED")) .want_pooled <- TRUE
only_dbs <- only_dbs[!toupper(only_dbs) %in% "POOLED"]

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
  config$subgroup$continuous_index_mode <- "highest_vs_lowest"
  config$subgroup$forest_n_source <- "full_stratum"
  config$subgroup$figure_number <- 3L
  options(pipeline.database_name = db)
  if (!is.null(.sg_scheme) && .sg_scheme %in% c("tertile", "quartile", "binary")) {
    if (is.null(config$logistic_quartile_glm)) config$logistic_quartile_glm <- list()
    config$logistic_quartile_glm$scheme <- .sg_scheme
    cli::cli_alert_info("{db} 亚组暴露分位: {(.sg_scheme)}（本轮指定，不改主文闸门）")
  }

  dat <- ck$data$imputed %||% ck$data$cleaned
  dat <- cross_lagged_attach_harmonize_fig3(dat, study_root, db, .sg)
  miss <- setdiff(.SG_LOCK, names(dat))
  # Age_Group 由亚组 block 按 age_cutoff 从 Age 现算
  if ("Age_Group" %in% miss && any(c("Age", "Age_Years") %in% names(dat))) {
    miss <- setdiff(miss, "Age_Group")
  }
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

  fig_pat <- paste0(
    "Subgroup Forest analyses of ",
    gsub("_", "[ _]", .index, fixed = TRUE),
    "\\.pdf$"
  )
  hits <- list.files(
    file.path(out_dir, "Figures"),
    pattern = fig_pat,
    full.names = TRUE, ignore.case = TRUE
  )
  fig_src <- if (length(hits)) {
    hits[order(file.info(hits)$mtime, decreasing = TRUE)][[1L]]
  } else NA_character_
  if (isTRUE(file.exists(fig_src))) {
    dest_sum <- file.path(study_root, "summary_result", "figure", basename(fig_src))
    dir.create(dirname(dest_sum), recursive = TRUE, showWarnings = FALSE)
    file.copy(fig_src, dest_sum, overwrite = TRUE)
    stale <- hits[basename(hits) != basename(fig_src)]
    if (length(stale)) unlink(stale)
    cli::cli_alert_success("subgroup forest: {basename(fig_src)}")
  } else {
    cli::cli_alert_warning("未找到 Subgroup Forest PDF for {db}")
  }
}

if (isTRUE(.want_pooled)) {
  cli::cli_h1("Subgroup harmonized re-run: Pooled")
  cohorts <- as.character(.meta$cohorts_xs %||% c("CHARLS", "ELSA"))
  cohorts <- cohorts[!toupper(cohorts) %in% "POOLED"]
  country_map <- c(CHARLS = "China", ELSA = "UK", HRS = "America", NHANES = "America")
  hname <- as.character(.meta$pooled_index %||% paste0(.index, "_harmonized"))[1L]
  if (!nzchar(hname)) hname <- paste0(.index, "_harmonized")
  parts <- list()
  for (db in cohorts) {
    ck_path <- file.path(cross_lagged_phase1_dir(study_root, db), "checkpoints", "multicollinearity_final.rds")
    if (!file.exists(ck_path)) stop("Pooled 亚组缺少检查点: ", ck_path)
    ck <- readRDS(ck_path)
    if (!is.null(ck$ctx)) ck <- ck$ctx
    d <- as.data.frame(ck$data$imputed %||% ck$data$cleaned)
    d <- cross_lagged_attach_harmonize_fig3(d, study_root, db, .sg)
    if (!.index %in% names(d)) stop(db, " 缺少暴露 ", .index)
    x <- suppressWarnings(as.numeric(d[[.index]]))
    ok <- is.finite(x)
    d[[hname]] <- NA_real_
    if (any(ok)) {
      r <- rank(x[ok], ties.method = "average")
      d[[hname]][ok] <- 100 * r / sum(ok)
    }
    d$Country <- unname(country_map[[db]])
    d$Cohort <- db
    if ("ID" %in% names(d)) d$ID <- paste0(db, "_", as.character(d$ID))
    parts[[db]] <- d
  }
  keep <- Reduce(intersect, lapply(parts, names))
  pooled <- do.call(rbind, lapply(parts, function(d) d[, keep, drop = FALSE]))
  rownames(pooled) <- NULL
  pooled$Country <- factor(pooled$Country, levels = unique(unname(country_map[cohorts])))
  .sg_pool <- .SG_LOCK
  if ("Country" %in% names(pooled)) .sg_pool <- unique(c(.sg_pool, "Country"))
  out_dir <- file.path(study_root, "phase3_post_Pooled")
  config <- list(
    project = list(
      output_dir = out_dir,
      database = "Pooled",
      analysis_group = .sg$analysis_group,
      reference_group = .sg$reference_group
    ),
    logistic = list(index_var = hname),
    incidence = list(index_var = hname, outcome_var = .sg$outcome_column),
    data = list(outcome_column = .sg$outcome_column),
    subgroup = list(
      var_source = "required",
      required_subgroup_vars = .sg_pool,
      age_cutoff = .SG_AGE_CUT,
      min_n = 20L,
      continuous_subgroup_vars = character(0),
      level_order = utils::modifyList(
        .sg$level_order %||% list(),
        list(Country = levels(pooled$Country))
      ),
      continuous_index_mode = "highest_vs_lowest",
      forest_n_source = "full_stratum",
      figure_number = 3L
    )
  )
  if (!is.null(.sg_scheme) && .sg_scheme %in% c("tertile", "quartile", "binary")) {
    config$logistic_quartile_glm <- list(scheme = .sg_scheme)
    cli::cli_alert_info("Pooled 亚组暴露分位: {(.sg_scheme)}；暴露为库内百分位 {hname}")
  }
  options(pipeline.database_name = "Pooled")
  ctx <- list(
    data = list(imputed = pooled, cleaned = pooled),
    results = list(categorical_vars = .sg_pool),
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
  fig_pat <- paste0(
    "Subgroup Forest analyses of ",
    gsub("_", "[ _]", hname, fixed = TRUE),
    "\\.pdf$"
  )
  hits <- list.files(ctx$output_dir_figures, pattern = fig_pat, full.names = TRUE, ignore.case = TRUE)
  fig_src <- if (length(hits)) hits[order(file.info(hits)$mtime, decreasing = TRUE)][[1L]] else NA_character_
  if (isTRUE(file.exists(fig_src))) {
    dest_sum <- file.path(study_root, "summary_result", "figure", basename(fig_src))
    dir.create(dirname(dest_sum), recursive = TRUE, showWarnings = FALSE)
    file.copy(fig_src, dest_sum, overwrite = TRUE)
    cli::cli_alert_success("Pooled subgroup forest: {basename(fig_src)} N={nrow(pooled)}")
  } else {
    cli::cli_alert_warning("未找到 Pooled Subgroup Forest PDF")
  }
}

txt <- c(
  paste0("time=", format(Sys.time(), "%F %T")),
  paste0("figure=Figure 3 Subgroup Forest analyses of ", .index),
  paste0("kind=", .meta$kind %||% "unknown"),
  paste0("cohorts=", paste(c(only_dbs, if (isTRUE(.want_pooled)) "Pooled"), collapse = ",")),
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
if (!isTRUE(.want_pooled)) {
  unlink(file.path(
    study_root, "summary_result", "figure",
    paste0("Figure 3-Pooled. Subgroup Forest analyses of ", .index, ".pdf")
  ))
}
unlink(file.path(
  study_root, "summary_result", "figure",
  "Figure 3-Pooled. Subgroup Forest analyses of FI.pdf"
))
cli::cli_alert_success(
  "亚组 Fig3 重跑完成（vars={paste(.SG_LOCK, collapse='+')}{if (isTRUE(.want_pooled)) '；含 Pooled' else ''}）"
)
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
