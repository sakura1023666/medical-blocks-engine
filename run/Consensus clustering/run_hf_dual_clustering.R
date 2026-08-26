#!/usr/bin/env Rscript
# =============================================================================
#  HF 双库无监督聚类流水线入口（薄脚本）
#  配置: configs/templates/config_hf_dual_clustering.template.R（config + pipeline）
#  引擎: R/pipeline_runner.R
#
#  用法（项目根目录）:
#    Rscript run_hf_dual_clustering.R --db both
#    Rscript run_hf_dual_clustering.R --db eicu
#    Rscript run_hf_dual_clustering.R --db mimic --to imputation
#    Rscript run_hf_dual_clustering.R --db both --only data_clean,imputation
#
#  Windows R（WSL 推荐）:
#    "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run_hf_dual_clustering.R --db eicu
#    bash run_hf_dual_clustering_win.sh --db both
# =============================================================================

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
  if (!db %in% c("eicu", "mimic", "both")) {
    stop("--db 仅支持 eicu|mimic|both", call. = FALSE)
  }
  db
}

.strip_db_args <- function(args) {
  out <- character(0)
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--db") {
      i <- i + 2L
    } else {
      out <- c(out, args[[i]])
      i <- i + 1L
    }
  }
  out
}

.continuous_common_vars <- function(root, cfg) {
  p <- cfg$dual_db$primary
  s <- cfg$dual_db$secondary
  map_src <- file.path(root, "Blocks/01_column_mappings/01block_column_mapping.R")
  if (file.exists(map_src)) source(map_src, local = FALSE)

  env1 <- new.env()
  env2 <- new.env()
  load(file.path(root, p$rawdata_path), envir = env1)
  load(file.path(root, s$rawdata_path), envir = env2)
  d1 <- get(p$rawdata_obj, envir = env1)
  d2 <- get(s$rawdata_obj, envir = env2)
  if (exists("auto_map_column_names", mode = "function")) {
    d1 <- auto_map_column_names(d1, p$column_mapping_type %||% "eICU")
    d2 <- auto_map_column_names(d2, s$column_mapping_type %||% "MIMIC")
  }
  is_cont <- function(d) {
    nms <- names(d)
    keep <- vapply(nms, function(v) {
      x <- d[[v]]
      is.numeric(x) && length(unique(stats::na.omit(x))) > 5
    }, logical(1))
    nms[keep]
  }
  drop_cols <- c(
    "ID", "subject_id", "survival_time_28d", "survival_28d",
    "in-hospital mortality", "is_hosp_dead", "hospdischargestatus",
    "hosplosday", "unitadmitsource", "unitdischargelocation",
    "unitdischargestatus", "unitlosday", "unittype"
  )
  common <- intersect(is_cont(d1), is_cont(d2))
  setdiff(common, drop_cols)
}

.apply_db_overrides <- function(cfg, db_name, root, common_vars) {
  db_cfg <- if (db_name == "eicu") cfg$dual_db$primary else cfg$dual_db$secondary
  cfg$data$rawdata_path <- db_cfg$rawdata_path
  cfg$data$rawdata_obj <- db_cfg$rawdata_obj
  cfg$data$outcome_column <- "in-hospital mortality"
  cfg$column_mapping$database_type <- db_cfg$column_mapping_type
  cfg$project$database <- db_cfg$name
  cfg$project$output_dir <- file.path("Output/HF_dual_clustering", tolower(db_cfg$name))
  cfg$plot_histogram$event_var <- "in-hospital mortality"
  cfg$baseline_binary$include_vars <- common_vars
  cfg$lca$required_any_of <- list(c("SBP", "MAP"))

  # lca$candidate_vars：
  #   - 若 config 已显式设置（非 NULL）→ 取其与 common_vars 的交集，确保两库变量集一致
  #   - 否则 → 使用 common_vars（旧行为）
  preset_lca_vars <- as.character(cfg$lca$candidate_vars %||% character(0))
  if (length(preset_lca_vars) > 0) {
    lca_vars <- intersect(preset_lca_vars, common_vars)
    if (length(lca_vars) == 0) {
      warning(".apply_db_overrides: lca$candidate_vars 与 common_vars 无交集，回退使用 common_vars")
      lca_vars <- common_vars
    }
    # 双库闸门：两库必须使用完全相同的聚类变量列表（按 config 顺序）
    lca_vars <- preset_lca_vars[preset_lca_vars %in% lca_vars]
    missing <- setdiff(preset_lca_vars, lca_vars)
    if (length(missing)) {
      stop(
        db_name, ": LCA 聚类变量在 common_vars 中缺失: ",
        paste(missing, collapse = ", "),
        "。请检查 column_mapping 或缩小 config$lca$candidate_vars。",
        call. = FALSE
      )
    }
    cfg$lca$candidate_vars <- lca_vars
  } else {
    cfg$lca$candidate_vars <- common_vars
  }

  mc_excl <- cfg$multicollinearity$exclude_vars %||% character(0)
  if (length(mc_excl)) {
    common_vars <- setdiff(common_vars, mc_excl)
    cfg$baseline_binary$include_vars <- common_vars
    # lca$candidate_vars 已由上面逻辑处理，不再被 mc_excl 覆盖（block_lca 内会排除 exclude_vars）
  }

  # 单因素 / 多因素 / VIF 链 / 相关热图：与 Table 1 使用同一双库 common_vars 池
  cfg$dual_db$harmonization$prognosis_include_vars <- common_vars
  cfg$univariate_prognosis$include_predictors <- common_vars
  cfg$multivariate_prognosis$include_predictors <- common_vars
  cfg$correlation$include_vars <- common_vars
  cfg$baseline_binary$exclude_vars <- unique(c(
    cfg$baseline_binary$exclude_vars %||% character(0),
    "survival_time_28d", "survival_28d", "ID",
    "hosplosday", "unitadmitsource", "unitdischargelocation",
    "unitdischargestatus", "unitlosday", "unittype"
  ))
  cfg
}

# 从 args 中提取并剥离 --config <path>
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

script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  script_path <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
           basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args_raw  <- commandArgs(trailingOnly = TRUE)
db_target <- .parse_db_arg(args_raw)
args_no_db <- .strip_db_args(args_raw)

cfg_result  <- .extract_config_arg(args_no_db, NULL)
args2       <- cfg_result$args

root_guess <- normalizePath(getwd(), winslash = "/")
if (length(args2) >= 1L && !startsWith(args2[[1L]], "--")) {
  root_guess <- normalizePath(args2[[1L]], winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

config_path <- if (!is.null(cfg_result$config_path) && nzchar(cfg_result$config_path)) {
  normalizePath(cfg_result$config_path, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_hf_dual_clustering.template.R")
}

source(file.path(root, "R/utils.R"))
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

common_vars <- .continuous_common_vars(root, config)
vif_drop <- config$multicollinearity$exclude_vars %||% character(0)
if (length(vif_drop)) {
  common_vars <- setdiff(common_vars, vif_drop)
}

db_seq <- switch(db_target,
  eicu = c("eicu"),
  mimic = c("mimic"),
  both = c("eicu", "mimic")
)

for (db in db_seq) {
  cfg_i <- .apply_db_overrides(config, db, root, common_vars)
  pipe_i <- pipeline
  pipe_i$name <- paste0(pipeline$name, "_", db)
  pipe_i$checkpoint$dir <- file.path("checkpoints_hf_dual", db)
  cli::cli_h1("Run database: {toupper(db)}")
  run_pipeline(root, config = cfg_i, pipeline = pipe_i, run_opts = run_opts)
}

