#!/usr/bin/env Rscript
# Blocks/54_cross_lagged_full/phases/phase_post_vif.R
# 阶段 D：三库从 multicollinearity_final 后续跑 logistic/RCS/亚组；Pooled 注入 initial_ctx 同跑。
# RCS：Fig Model2 默认仅 primary 一条 cutoff 竖虚线（cutoff_vlines="all" 可标全部交点）；
# FI_RCS_Group / Table S-XX 强制 group_cutoffs="primary"（二分）。
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
study_root <- .cl_pick_study_root(args, study_root %||% NULL)
if (is.null(study_root) || !nzchar(as.character(study_root)[1L])) {
  study_root <- .cl_pick_study_root(args, "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/cross_lagged_covariate_lock.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

options(warn = 1, cli.hyperlink = FALSE)

.meta <- cross_lagged_study_meta(study_root)
.sg_fig3 <- cross_lagged_fig3_lock(.meta)
.main_units <- cross_lagged_main_cohorts(.meta)
if (!length(.main_units)) {
  .main_units <- c("CHARLS", "ELSA", "HRS")
  if (file.exists(file.path(study_root, "config_phase1_NHANES.R")) &&
      !"NHANES" %in% cross_lagged_validation_cohorts(.meta))
    .main_units <- c("CHARLS", "ELSA", "NHANES")
}

# 开发队列 VIF 交集锁定（验证队列不参与）
.lock <- cross_lagged_resolve_covariate_lock(study_root, .meta)
if (isTRUE(.lock$empty) || !length(.lock$model2)) {
  stop("phase_post_vif: 开发队列 VIF 交集为空，无法锁定 Model2", call. = FALSE)
}
.M1_LOCK <- if (length(.lock$model1)) .lock$model1 else {
  if ("Age" %in% .lock$model2) "Age" else .lock$model2[[1]]
}
.M2_LOCK <- .lock$model2
.M2_POOLED <- unique(c(.M2_LOCK, "Country"))
cli::cli_alert_info(paste0(
  "post_vif lock M1=", paste(.M1_LOCK, collapse = "+"),
  " M2=", paste(.M2_LOCK, collapse = "+"),
  " source=", as.character(.lock$source %||% "unknown"),
  " lock_cohorts=", paste(.lock$lock_cohorts, collapse = ",")
))


# RCS 分组若出现空档，*_glm_rcs 易在默认 Model 表构建处失败；先跑核心后段，再可选尝试 rcs 表
.post_blocks_core <- c(
  "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
  "logistic_quintile_glm",
  "rcs_incidence",
  "subgroup_incidence",
  "simple_ROC", "boxplot"
)
.post_blocks_rcs_tab <- c(
  "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
  "logistic_quintile_glm_rcs"
)
.post_blocks <- c(.post_blocks_core, .post_blocks_rcs_tab)

.pre_blocks <- c(
  "data_clean", "column_mapping", "imputation", "baseline_binary",
  "univariate_incidence_binary", "multicollinearity_screen",
  "multivariate_incidence_binary", "multicollinearity_final"
)

.patch_post_cfg <- function(config, db, out_dir, ck_dir, m1, m2) {
  config$project$name <- paste0("Circadian_ePWV_", db, "_phase3_post")
  if (identical(db, "NHANES")) {
    config$project$database <- "USA"
    config$project$database_type <- "regular"
  } else {
    config$project$database <- db
  }
  config$project$output_dir <- out_dir
  .ix <- as.character((config$incidence %||% list())$index_var %||% "FI")[1L]
  if (exists("logistic_gate_apply_cascade_defaults", mode = "function")) {
    config <- logistic_gate_apply_cascade_defaults(config, index_var = .ix)
  }
  # 三库亚组强制同一变量集 + 同一顺序（Fig 3；Pooled 不进 Fig3）
  # 禁止与 Model1/2 intersect：否则 NHANES 会丢掉 Education/Smoking 等
  .sg_lock <- as.character(.sg_fig3$vars %||% character(0))
  if (is.null(config$subgroup)) config$subgroup <- list()
  config$subgroup$var_source <- "required"
  config$subgroup$required_subgroup_vars <- .sg_lock
  config$subgroup$age_cutoff <- as.integer(.sg_fig3$age_cutoff %||% 70L)[1L]
  config$subgroup$min_n <- 20L
  config$subgroup$continuous_subgroup_vars <- character(0)
  config$subgroup$level_order <- utils::modifyList(
    config$subgroup$level_order %||% list(),
    .sg_fig3$level_order %||% list(Age_Group = c("< 70", "\u2265 70"))
  )
  # 加快搜索：Model2 已锁定，失败时也出表
  for (nm in c("logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
               "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
               "logistic_quintile_glm", "logistic_quintile_glm_rcs")) {
    if (!is.null(config[[nm]])) {
      config[[nm]]$pause_enable <- FALSE
      config[[nm]]$pause_on_search_fail <- FALSE
      if (!is.null(config[[nm]]$random_search)) {
        config[[nm]]$random_search$max_outer_attempts <- 30L
        config[[nm]]$random_search$max_inner_attempts <- 5L
      }
      config[[nm]]$model1_factors <- m1
      config[[nm]]$model2_factors <- m2
    }
  }
  if (is.null(config$covariate_policy)) config$covariate_policy <- list()
  config$covariate_policy$force_age <- "Age" %in% c(m1, m2)
  config$covariate_policy$force_sex <- any(c("Gender", "Sex") %in% m2)
  config$covariate_policy$force_sex_to_model1 <- FALSE
  if (is.null(config$logistic_covariates)) config$logistic_covariates <- list()
  config$logistic_covariates$model1_factors <- m1
  config$logistic_covariates$model2_factors <- m2
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$model2_max_covariates <- 9999L
  if (is.null(config$incidence)) config$incidence <- list()
  config$incidence$model2_max_covariates <- 9999L
  if (!is.null(config$roc_simple)) config$roc_simple$enable <- TRUE
  if (!is.null(config$boxplot)) {
    config$boxplot$response_vars <- unique(c(.ix, "BMI"))
  }
  if (is.null(config$rcs_incidence)) config$rcs_incidence <- list()
  config$rcs_incidence$group_cutoffs <- "primary"
  config$rcs_incidence$index_var <- .ix
  list(
    config = config,
    pipeline = list(
      name = paste0("cross_lagged_phase3_post_", db),
      blocks = c(.pre_blocks, .post_blocks),
      logistic_gate = list(enable = TRUE),
      checkpoint = list(enable = TRUE, dir = ck_dir),
      render_tables_after = .post_blocks,
      render_figures_after = c("rcs_incidence", "subgroup_incidence", "simple_ROC", "boxplot"),
      dual_db = list(enable = FALSE)
    )
  )
}

.drop_empty_rcs_levels <- function(ctx) {
  d <- ctx$data$imputed
  if (is.null(d) || !"FI_RCS_Group" %in% names(d)) return(ctx)
  g <- d$FI_RCS_Group
  if (is.factor(g)) {
    d$FI_RCS_Group <- droplevels(g)
  } else {
    tab <- table(as.character(g), useNA = "no")
    keep <- names(tab)[tab > 0]
    d$FI_RCS_Group <- factor(as.character(g), levels = keep)
  }
  ctx$data$imputed <- d
  if (!is.null(ctx$data$cleaned) && "FI_RCS_Group" %in% names(ctx$data$cleaned))
    ctx$data$cleaned$FI_RCS_Group <- d$FI_RCS_Group[match(ctx$data$cleaned$ID %||% seq_len(nrow(ctx$data$cleaned)), d$ID %||% seq_len(nrow(d)))]
  ctx
}

.run_core_then_rcs <- function(patched, from_token = "multicollinearity_final", initial_ctx = NULL) {
  post_core <- .post_blocks_core
  dbn <- as.character((patched$config$project %||% list())$database %||% "")[1L]
  if (identical(dbn, "Pooled") || isFALSE((patched$config$subgroup %||% list())$enable)) {
    post_core <- setdiff(post_core, "subgroup_incidence")
  }
  # 1) 核心后段（不含 *_glm_rcs）
  pipe_core <- patched$pipeline
  pipe_core$blocks <- c(.pre_blocks, post_core)
  pipe_core$render_tables_after <- post_core
  pipe_core$render_figures_after <- intersect(
    c("rcs_incidence", "subgroup_incidence", "simple_ROC", "boxplot"),
    post_core
  )
  opts <- if (!is.null(initial_ctx)) {
    list(only = post_core, initial_ctx = initial_ctx)
  } else {
    list(from = from_token)
  }
  ctx <- run_pipeline(root, config = patched$config, pipeline = pipe_core, run_opts = opts)

  # 2) 尝试 RCS 分组表：丢掉空水平后再跑
  ctx2 <- .drop_empty_rcs_levels(ctx)
  nlev <- nlevels(factor(ctx2$data$imputed$FI_RCS_Group))
  if (!is.finite(nlev) || nlev < 2L) {
    cli::cli_alert_warning("跳过 *_glm_rcs：FI_RCS_Group 有效水平 < 2")
    return(invisible(ctx2))
  }
  pipe_rcs <- patched$pipeline
  pipe_rcs$blocks <- c(.pre_blocks, .post_blocks_core, .post_blocks_rcs_tab)
  pipe_rcs$render_tables_after <- .post_blocks_rcs_tab
  pipe_rcs$render_figures_after <- character(0)
  tryCatch({
    run_pipeline(
      root,
      config = patched$config,
      pipeline = pipe_rcs,
      run_opts = list(only = .post_blocks_rcs_tab, initial_ctx = ctx2)
    )
  }, error = function(e) {
    cli::cli_alert_warning("*_glm_rcs 跳过: {conditionMessage(e)}")
    invisible(NULL)
  })
  invisible(ctx2)
}

run_unit <- function(db) {
  cli::cli_h1("Phase3 post-VIF: {db}")
  cfg_path <- file.path(study_root, paste0("config_phase1_", db, ".R"))
  if (!file.exists(cfg_path)) stop("缺少 config: ", cfg_path)
  e <- new.env(parent = globalenv())
  sys.source(cfg_path, envir = e)
  out_dir <- {
    d1 <- file.path(study_root, paste0("phase1_", db, "_allages"))
    d2 <- file.path(study_root, paste0("phase1_", db))
    if (dir.exists(d1)) d1 else d2
  }
  ck_dir <- file.path(out_dir, "checkpoints")
  patched <- .patch_post_cfg(e$config, db, out_dir, ck_dir, .M1_LOCK, .M2_LOCK)
  # 从 VIF final 注入 initial_ctx；先按 ID 从 D04 补齐 Fig3 锁定变量（Education/Smoking）
  ck_mvf <- file.path(ck_dir, "step10_multicollinearity_final.rds")
  if (!file.exists(ck_mvf)) ck_mvf <- file.path(ck_dir, "multicollinearity_final.rds")
  if (file.exists(ck_mvf)) {
    ck <- readRDS(ck_mvf)
    if (!is.null(ck$ctx)) ck <- ck$ctx
    dat <- as.data.frame(ck$data$imputed %||% ck$data$cleaned)
    if ("Smoke" %in% names(dat) && !"Smoking" %in% names(dat)) dat$Smoking <- dat$Smoke
    lock <- list(
      vars = unique(c(as.character(.sg_fig3$vars %||% character(0)), "Education", "Smoking")),
      level_order = .sg_fig3$level_order %||% list()
    )
    dat2 <- cross_lagged_attach_harmonize_fig3(dat, study_root, db, lock)
    if (!is.null(ck$data$imputed)) ck$data$imputed <- dat2
    if (!is.null(ck$data$cleaned)) ck$data$cleaned <- dat2
    ck$config <- patched$config
    ck$root_output_dir <- out_dir
    .run_core_then_rcs(patched, initial_ctx = ck)
  } else {
    .run_core_then_rcs(patched, from_token = "multicollinearity_final")
  }
}

run_pooled <- function() {
  cli::cli_h1("Phase3 post-VIF: Pooled")
  pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_hip_postvif.RData")
  if (!file.exists(pooled_path)) stop("缺少 Pooled RData: ", pooled_path)
  factors_path <- file.path(study_root, "phase2_Pooled", "pooled_model_factors.txt")
  m2 <- .M2_POOLED
  if (file.exists(factors_path)) {
    lines <- readLines(factors_path, warn = FALSE)
    hit <- grep("^Model2:", lines, value = TRUE)
    if (length(hit)) {
      raw <- sub("^Model2:\\s*", "", hit[[1]])
      parts <- trimws(unlist(strsplit(raw, "[+,]")))
      parts <- parts[nzchar(parts)]
      if (length(parts)) m2 <- parts
    }
  }
  m1 <- .M1_LOCK
  if (!"Country" %in% m2) m2 <- unique(c(m2, "Country"))
  # Pooled：Country 进入 Crude / Model1 / Model2（消除库间混杂；单库 RCS 仍不调 Country）
  m1 <- unique(c(m1, "Country"))

  ee <- new.env()
  load(pooled_path, envir = ee)
  dabiao <- ee$dabiao
  if (!"Country" %in% names(dabiao)) stop("Pooled 缺 Country")
  ctry_lvls <- sort(unique(as.character(dabiao$Country)))
  dabiao$Country <- factor(dabiao$Country, levels = ctry_lvls)

  # 以 CHARLS phase1 为模板改 Pooled
  e <- new.env(parent = globalenv())
  sys.source(file.path(study_root, "config_phase1_CHARLS.R"), envir = e)
  out_dir <- file.path(study_root, "phase3_post_Pooled")
  ck_dir <- file.path(out_dir, "checkpoints")
  dir.create(ck_dir, recursive = TRUE, showWarnings = FALSE)
  e$config$data$rawdata_path <- pooled_path
  e$config$data$rawdata_obj <- "dabiao"
  if (is.null(e$config$covariate_policy)) e$config$covariate_policy <- list()
  e$config$covariate_policy$force_age <- "Age" %in% c(m1, m2)
  e$config$covariate_policy$force_sex <- any(c("Gender", "Sex") %in% m2)
  e$config$covariate_policy$force_sex_to_model1 <- FALSE
  patched <- .patch_post_cfg(e$config, "Pooled", out_dir, ck_dir, m1, m2)
  patched$config$project$database <- "Pooled"
  patched$config$column_mapping$database_type <- "regular"
  if (is.null(patched$config$rcs_incidence)) patched$config$rcs_incidence <- list()
  # RCS Model1 在 Gender+Education+Country 上再加 Weight：右尾 OR 可稳住 >1（筛查见 model1_screen.csv）
  m1_rcs <- unique(c(m1, "Weight"))
  patched$config$rcs_incidence$crude_factors <- "Country"
  patched$config$rcs_incidence$model1_factors <- m1_rcs
  patched$config$rcs_incidence$model2_factors <- m2
  cli::cli_alert_info(
    "Pooled RCS: Crude=+Country; Model1={paste(m1_rcs, collapse='+')}; Model2={paste(m2, collapse='+')}"
  )
  # Pooled logistic：Crude / Model1 也调 Country（与 RCS 口径一致；Model1 不含 Weight，Weight 仅 RCS）
  for (nm in c("logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
               "logistic_quintile_glm")) {
    if (is.null(patched$config[[nm]])) patched$config[[nm]] <- list()
    patched$config[[nm]]$crude_factors <- "Country"
    patched$config[[nm]]$model1_factors <- m1
    patched$config[[nm]]$model2_factors <- m2
    patched$config[[nm]]$pause_enable <- FALSE
    patched$config[[nm]]$pause_on_search_fail <- FALSE
  }
  if (is.null(patched$config$logistic_covariates)) patched$config$logistic_covariates <- list()
  patched$config$logistic_covariates$crude_factors <- "Country"
  patched$config$logistic_covariates$model1_factors <- m1
  patched$config$logistic_covariates$model2_factors <- m2
  cli::cli_alert_info(
    "Pooled logistic: Crude=+Country; Model1={paste(m1, collapse='+')}; Model2={paste(m2, collapse='+')}"
  )
  # Fig3 不要 Pooled：后段去掉 subgroup_incidence
  patched$pipeline$blocks <- setdiff(patched$pipeline$blocks, "subgroup_incidence")
  patched$pipeline$render_tables_after <- setdiff(
    patched$pipeline$render_tables_after %||% character(0), "subgroup_incidence"
  )
  patched$pipeline$render_figures_after <- setdiff(
    patched$pipeline$render_figures_after %||% character(0), "subgroup_incidence"
  )
  if (!is.null(patched$config$subgroup)) {
    patched$config$subgroup$enable <- FALSE
  }

  initial_ctx <- list(
    config = patched$config,
    data = list(raw = dabiao, cleaned = dabiao, mapped = dabiao, imputed = dabiao),
    results = list(
      Model1Factors = m1,
      Model2Factors = m2,
      vif_final_pass = m2
    ),
    log = list(),
    root_output_dir = out_dir
  )

  .run_core_then_rcs(patched, initial_ctx = initial_ctx)
}

dbs <- c(.main_units, "Pooled")
if (!is.null(only_dbs) && length(only_dbs)) dbs <- intersect(dbs, only_dbs)
if (!length(dbs)) stop("无有效 --only 库")

for (db in dbs) {
  if (identical(db, "Pooled")) run_pooled() else run_unit(db)
}

cli::cli_alert_success("Phase3 post-VIF 完成: {paste(dbs, collapse = ', ')}")
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
