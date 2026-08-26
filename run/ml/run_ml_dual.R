#!/usr/bin/env Rscript
# =============================================================================
#  ML 双库流水线（NHANES 主库 VIF 分步 + MIMIC 验证库仅 ML）
#  固定使用: /mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe
# =============================================================================

{
  rscript_ml <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
  if (file.exists(rscript_ml) && .Platform$OS.type != "windows") {
    ca <- commandArgs(trailingOnly = FALSE)
    self <- grep("^--file=", ca, value = TRUE)
    if (length(self)) {
      self <- sub("^--file=", "", self[1L])
      status <- system2(rscript_ml, c(self, commandArgs(trailingOnly = TRUE)))
      quit(save = "no", status = status)
    }
  }
}

.init_script_dir <- function() {
  sp <- tryCatch(
    normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path), winslash = "/"),
    error = function(e) NA_character_
  )
  if (!is.na(sp) && nzchar(sp)) return(sp)
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.parse_db_arg <- function(args) {
  db <- "both"
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--db" && i < length(args)) {
      db <- tolower(trimws(args[[i + 1L]]))
      i <- i + 2L
    } else {
      i <- i + 1L
    }
  }
  if (!db %in% c("nhanes", "mimic", "both")) {
    stop("--db 仅支持 nhanes|mimic|both", call. = FALSE)
  }
  db
}

.strip_db_args <- function(args) {
  out <- character(0)
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--db") i <- i + 2L else { out <- c(out, args[[i]]); i <- i + 1L }
  }
  out
}

.extract_config_arg <- function(args, default) {
  config_val <- default
  out <- character(0)
  i <- 1L
  while (i <= length(args)) {
    if (identical(args[[i]], "--config") && i < length(args)) {
      config_val <- trimws(args[[i + 1L]]); i <- i + 2L
    } else {
      out <- c(out, args[[i]]); i <- i + 1L
    }
  }
  list(config_path = config_val, args = out)
}

.apply_db_overrides <- function(cfg, db_name, root, gate_a) {
  db_cfg <- if (db_name == "nhanes") cfg$dual_db$primary else cfg$dual_db$secondary
  cfg$data$rawdata_path <- db_cfg$rawdata_path
  cfg$data$rawdata_obj <- db_cfg$rawdata_obj
  cfg$data$id_column <- db_cfg$id_column
  cfg$column_mapping$database_type <- db_cfg$column_mapping_type
  cfg$project$database <- db_cfg$name
  cfg$project$database_type <- db_cfg$db_type
  cfg$project$output_dir <- file.path(
    cfg$project$output_dir %||% "Output/Psoriasis_ML_dual",
    db_name
  )
  cfg$project$root <- root
  cfg$dual_db$current_db <- db_name

  if (!is.null(gate_a) && length(gate_a)) {
    cfg$dual_db$harmonization <- modifyList(
      cfg$dual_db$harmonization %||% list(),
      gate_a
    )
    pool <- if (db_name == "nhanes") {
      unique(c(gate_a$demo_cols_nhanes, gate_a$common_non_demo_cols))
    } else {
      unique(c(gate_a$demo_cols_mimic, gate_a$common_non_demo_cols))
    }
    pool <- pool[nzchar(pool)]
    cfg$baseline_nhanes$include_vars <- pool
    cfg$univariate_nhanes$include_predictors <- pool
    cfg$multivariate_nhanes$include_predictors <- pool
  }
  cfg
}

script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  script_path <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "ml", "feishu", "hf") &&
           basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args_raw  <- commandArgs(trailingOnly = TRUE)
db_target <- .parse_db_arg(args_raw)
args_no_db <- .strip_db_args(args_raw)
cfg_result <- .extract_config_arg(args_no_db, NULL)
args2 <- cfg_result$args

root_guess <- normalizePath(getwd(), winslash = "/")
if (length(args2) >= 1L && !startsWith(args2[[1L]], "--")) {
  root_guess <- normalizePath(args2[[1L]], winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

config_path <- if (!is.null(cfg_result$config_path) && nzchar(cfg_result$config_path)) {
  normalizePath(cfg_result$config_path, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_ml_dual_batch.template.R")
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/ml_dual_pipeline_helpers.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

run_opts <- pipeline_parse_cli(args2)
if (!is.null(run_opts$root) && nzchar(run_opts$root)) {
  root <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)
  setwd(root)
}

options(cli.hyperlink = FALSE)
options(warn = 1)
if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

gate_a <- dual_db_load_gate_a(root, config)
if (db_target == "both" || is.null(gate_a)) {
  gate_a <- dual_db_compute_gate_a(root, config)
  dual_db_save_gate_a(root, config, gate_a)
  cli::cli_alert_success(
    "闸门 A：共享非人口学列 {length(gate_a$common_non_demo_cols)} 个"
  )
}

.run_one_db <- function(db, pipe, run_opts_local) {
  cfg_i <- .apply_db_overrides(config, db, root, gate_a)
  pipe_i <- pipe
  pipe_i$name <- paste0(pipe_i$name, "_", db)
  pipe_i$checkpoint$dir <- file.path(
    config$dual_db$checkpoint_base %||% "checkpoints/Psoriasis_ML_dual",
    db
  )
  cli::cli_h1("Run database: {toupper(db)} ({cfg_i$project$database_type})")
  run_pipeline(root, config = cfg_i, pipeline = pipe_i, run_opts = run_opts_local)
}

if (isTRUE(run_opts$list_ck)) {
  if (db_target %in% c("nhanes", "both")) .run_one_db("nhanes", pipeline_nhanes, run_opts)
  if (db_target %in% c("mimic", "both")) .run_one_db("mimic", pipeline_mimic_ml, run_opts)
} else if (db_target == "both" &&
           !length(run_opts$from %||% NULL) &&
           !length(run_opts$to %||% NULL) &&
           !length(run_opts$only %||% NULL)) {
  opts_n <- run_opts
  opts_n$to <- "ml_feature_selection_bundle"
  .run_one_db("nhanes", pipeline_nhanes, opts_n)
  opts_m <- run_opts
  opts_m$to <- "ml_inherit_primary_features"
  .run_one_db("mimic", pipeline_mimic_ml, opts_m)
  opts_n2 <- run_opts
  opts_n2$from <- "ml_feature_selection_bundle"
  .run_one_db("nhanes", pipeline_nhanes, opts_n2)
  opts_m2 <- run_opts
  opts_m2$from <- "ml_inherit_primary_features"
  .run_one_db("mimic", pipeline_mimic_ml, opts_m2)
} else {
  if (db_target %in% c("nhanes", "both")) {
    .run_one_db("nhanes", pipeline_nhanes, run_opts)
  }
  if (db_target %in% c("mimic", "both")) {
    .run_one_db("mimic", pipeline_mimic_ml, run_opts)
  }
}

if (db_target == "both") {
  mirror_dual_db_aggregate(root, config)
}

cli::cli_alert_success("run_ml_dual 全部结束。")
