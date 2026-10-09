#!/usr/bin/env Rscript
# Blocks/54_cross_lagged_full/phases/phase_relock_logistic.R
# 锁定三库协变量（Table S4 / VIF_screen 三库交集），重跑 tertile / binary / quartile logistic。
# Pooled Model2 另加 Country。禁止硬编码 Age+Gender。
# 主文分位写自 cross_lagged_study_meta()$grouping（昼夜=quartile；髋部=tertile）。
# 禁止写死 tertile：会把 Change/S5 闸门一并带偏。
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
rcs_only <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_dbs <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
    i <- i + 2L
  } else if (args[[i]] == "--rcs-only") {
    rcs_only <- TRUE; i <- i + 1L
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
source(file.path(root, "configs/indices/composite_index_vars.R"))

options(warn = 1, cli.hyperlink = FALSE)

# 协变量锁定：开发队列（CHARLS+ELSA）VIF screen 交集；验证队列不参与
.meta_lock <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
.lock <- cross_lagged_resolve_covariate_lock(study_root, .meta_lock)
cli::cli_h1("协变量锁定（开发队列 VIF 交集）")
for (line in cross_lagged_format_lock_report(.lock)) cli::cli_alert_info(line)
if (isTRUE(.lock$empty) || !length(.lock$model2)) {
  stop("开发队列 VIF 交集为空，无法锁定 Model2（请检查 Table S4 / VIF_screen_pass）", call. = FALSE)
}
.M1_LOCK <- if (length(.lock$model1)) .lock$model1 else {
  if ("Age" %in% .lock$model2) "Age" else .lock$model2[[1]]
}
.M2_LOCK <- .lock$model2
.M2_POOLED <- unique(c(.M2_LOCK, "Country"))
cli::cli_alert_success(paste0(
  "Model1=", paste(.M1_LOCK, collapse = "+"),
  " | Model2=", paste(.M2_LOCK, collapse = "+"),
  " | PooledM2=", paste(.M2_POOLED, collapse = "+"),
  " | source=", as.character(.lock$source %||% "unknown")
))


.log_blocks <- c(
  "logistic_tertile_glm", "logistic_binary_glm", "logistic_quartile_glm"
)
# Table S-XX 来源：RCS cutoff 组 logistic（与主文锁定协变量一致；四库均需）
.rcs_sxx_block <- "logistic_quartile_glm_rcs"

.pre_blocks <- c(
  "data_clean", "column_mapping", "imputation", "baseline_binary",
  "univariate_incidence_binary", "multicollinearity_screen",
  "multivariate_incidence_binary", "multicollinearity_final"
)

.lock_cfg <- function(config, m1, m2, blocks = .log_blocks) {
  for (nm in blocks) {
    if (is.null(config[[nm]])) config[[nm]] <- list()
    config[[nm]]$pause_enable <- FALSE
    config[[nm]]$pause_on_search_fail <- FALSE
    config[[nm]]$gate_enable <- FALSE
    config[[nm]]$model1_factors <- m1
    config[[nm]]$model2_factors <- m2
    if (!is.null(config[[nm]]$random_search)) {
      config[[nm]]$random_search$enable <- FALSE
    }
  }
  if (is.null(config$logistic_covariates)) config$logistic_covariates <- list()
  config$logistic_covariates$model1_factors <- m1
  config$logistic_covariates$model2_factors <- m2
  if (is.null(config$logistic_covariates$random_search))
    config$logistic_covariates$random_search <- list()
  config$logistic_covariates$random_search$enable <- FALSE
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$model2_max_covariates <- 9999L
  if (is.null(config$incidence)) config$incidence <- list()
  config$incidence$model2_max_covariates <- 9999L
  # 仅当锁定集含 Gender 时才强制 sex；避免 force_sex 把 Gender 掺进 Model2
  if (is.null(config$covariate_policy)) config$covariate_policy <- list()
  config$covariate_policy$force_age <- "Age" %in% m2 || "Age" %in% m1
  config$covariate_policy$force_sex <- any(c("Gender", "Sex") %in% m2)
  config$covariate_policy$force_sex_to_model1 <- FALSE
  # 展示名：FI 课题才回退 Frailty Index；休闲活动用 Leisure activity score
  if (is.null(config$incidence)) config$incidence <- list()
  .idx_disp <- as.character(config$incidence$index_var %||% "")[1L]
  .disp_fallback <- if (.idx_disp %in% c("FI", "Frailty", "Frailty_Index", "frailty_index", "")) {
    "Frailty Index"
  } else if (identical(.idx_disp, "Leisure_score")) {
    "Leisure activity score"
  } else {
    gsub("_", " ", .idx_disp, fixed = TRUE)
  }
  config$incidence$index_var_display_name <-
    config$incidence$index_var_display_name %||% .disp_fallback
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$index_var_display_name <-
    config$logistic$index_var_display_name %||% config$incidence$index_var_display_name
  config
}

.write_lock_note <- function(out_dir, db, m1, m2, lock = NULL) {
  dir.create(file.path(out_dir, "Tables", "Summary"), recursive = TRUE, showWarnings = FALSE)
  src <- if (!is.null(lock)) lock$source else "manual"
  lines <- c(
    paste0("# Locked covariates — ", db),
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "# Rule: VIF final 三库交集；若空则回退 VIF screen（UV p<0.1）三库交集；去掉 FI/Frailty",
    paste0("# lock_source=", src),
    if (!is.null(lock)) paste0("# intersect_final=", paste(lock$intersect_final, collapse = ", ")),
    if (!is.null(lock)) paste0("# intersect_screen=", paste(lock$intersect_screen, collapse = ", ")),
    paste0("# Model2 locked = ", paste(m2, collapse = ", ")),
    "",
    "Model1:",
    paste(m1, collapse = "\n"),
    "",
    "Model2:",
    paste(m2, collapse = "\n")
  )
  writeLines(lines, file.path(out_dir, "Tables", "Summary",
                            paste0("FinalCovariates_Locked_", tolower(db), ".txt")))
  writeLines(
    c(
      paste0("# Final covariates (Model2Factors) — Index / ", db, " (LOCKED ", src, ")"),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      "",
      m2
    ),
    file.path(out_dir, "Tables", "Summary",
              paste0("FinalCovariates_Index_", tolower(db), ".txt"))
  )
}

.load_vif_checkpoint <- function(ck_dir) {
  cands <- list.files(ck_dir, pattern = "multicollinearity_final\\.rds$", full.names = TRUE)
  if (!length(cands)) stop("无 multicollinearity_final 检查点: ", ck_dir)
  hit <- cands[grepl("multicollinearity_final", basename(cands))]
  if (!length(hit)) hit <- cands
  ck <- readRDS(hit[[1]])
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

.load_rcs_checkpoint <- function(ck_dir) {
  cands <- list.files(ck_dir, pattern = "rcs_incidence\\.rds$", full.names = TRUE)
  if (!length(cands)) return(NULL)
  hit <- cands[grepl("step\\d+_rcs_incidence", basename(cands))]
  if (!length(hit)) hit <- cands
  ck <- readRDS(hit[[1]])
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

#' Pooled 无 VIF 检查点：从 D04_Pooled_postvif.RData（或最近 logistic ck）建 ctx
.load_pooled_ctx_for_rcs <- function(study_root, config, m1, m2, ck_dir) {
  # 优先：已有 logistic relock 检查点（含 imputed）
  log_cands <- list.files(
    ck_dir,
    pattern = "(logistic_quartile_glm|logistic_tertile_glm|logistic_binary_glm)\\.rds$",
    full.names = TRUE
  )
  if (length(log_cands)) {
    hit <- log_cands[grepl("step\\d+_", basename(log_cands))]
    if (!length(hit)) hit <- log_cands
    # 取最新修改的
    hit <- hit[order(file.info(hit)$mtime, decreasing = TRUE)]
    ck <- tryCatch({
      x <- readRDS(hit[[1L]])
      if (!is.null(x$ctx)) x <- x$ctx
      x
    }, error = function(e) NULL)
    if (!is.null(ck) && is.data.frame(ck$data$imputed %||% ck$data$cleaned)) {
      cli::cli_alert_info("Pooled RCS: 复用 logistic 检查点 {basename(hit[[1L]])}")
      return(ck)
    }
  }
  pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData")
  if (!file.exists(pooled_path))
    pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_hip_postvif.RData")
  if (!file.exists(pooled_path))
    stop("Pooled RCS: 无 multicollinearity_final，且缺少 D04_Pooled_postvif.RData", call. = FALSE)
  ee <- new.env(parent = emptyenv())
  load(pooled_path, envir = ee)
  dabiao <- ee$dabiao
  if (!is.data.frame(dabiao)) stop("Pooled RData 无 dabiao", call. = FALSE)
  if ("Country" %in% names(dabiao)) {
    dabiao$Country <- factor(dabiao$Country, levels = sort(unique(as.character(dabiao$Country))))
  }
  cli::cli_alert_info("Pooled RCS: 从 {basename(pooled_path)} 构建上下文")
  list(
    config = config,
    data = list(raw = dabiao, cleaned = dabiao, mapped = dabiao, imputed = dabiao),
    results = list(
      Model1Factors = m1,
      Model2Factors = m2,
      vif_final_pass = m2
    ),
    log = list(),
    root_output_dir = dirname(ck_dir)
  )
}

run_unit <- function(db) {
  cli::cli_h1("Relock logistic: {db}")
  cfg_path <- file.path(study_root, paste0("config_phase1_", db, ".R"))
  e <- new.env(parent = globalenv())
  sys.source(cfg_path, envir = e)
  out_dir <- cross_lagged_phase1_dir(study_root, db)
  ck_dir <- file.path(out_dir, "checkpoints")

  m1 <- .M1_LOCK
  m2 <- .M2_LOCK
  config <- .lock_cfg(e$config, m1, m2)
  config$project$name <- paste0("Hip_Frailty_", db, "_relock_logistic")
  config$project$database <- db
  config$project$output_dir <- out_dir

  ck <- .load_vif_checkpoint(ck_dir)
  ck$results$Model1Factors <- m1
  ck$results$Model2Factors <- m2
  ck$results$vif_final_pass <- m2
  ck$config <- config

  pipe <- list(
    name = paste0("cross_lagged_relock_", db),
    blocks = c(.pre_blocks, .log_blocks),
    logistic_gate = list(enable = FALSE),
    checkpoint = list(enable = TRUE, dir = ck_dir),
    render_tables_after = .log_blocks,
    render_figures_after = character(0),
    dual_db = list(enable = FALSE)
  )

  .write_lock_note(out_dir, db, m1, m2, .lock)
  run_pipeline(
    root, config = config, pipeline = pipe,
    run_opts = list(only = .log_blocks, initial_ctx = ck)
  )
  cli::cli_alert_success("{db} logistic relock done (M1={paste(m1, collapse='+')}; M2={paste(m2, collapse='+')})")
}

#' Table S-XX：RCS cutoff 组 logistic，协变量与主文锁定一致（四库均需：CHARLS/ELSA/HRS/Pooled）
#' Pooled RCS：rcs(暴露) * Country，检验样条形状在库间是否不同
.pooled_rcs_interaction <- function(data, index, covars, case_label, out_dir, nk = NULL) {
  if (!requireNamespace("rms", quietly = TRUE)) {
    stop("需要 rms 包做 Pooled RCS 交互检验", call. = FALSE)
  }
  suppressPackageStartupMessages(library(rms))
  covars <- setdiff(as.character(covars), c("Country", "Cohort", index))
  covars <- covars[covars %in% names(data)]
  y <- as.integer(as.character(data$Disease_Group) == case_label)
  dat <- data.frame(Disease = y, Country = factor(data$Country), stringsAsFactors = FALSE)
  dat[[index]] <- as.numeric(data[[index]])
  for (v in covars) dat[[v]] <- data[[v]]
  dat <- dat[stats::complete.cases(dat), , drop = FALSE]
  assign("dd_pool", rms::datadist(dat), envir = .GlobalEnv)
  options(datadist = "dd_pool")
  if (is.null(nk) || !is.finite(as.numeric(nk))) {
    nk <- 4L
    best <- Inf
    for (i in 3:5) {
      f0 <- stats::as.formula(paste0("Disease ~ rms::rcs(", index, ", ", i, ")"))
      fit0 <- tryCatch(rms::lrm(f0, data = dat), error = function(e) NULL)
      if (is.null(fit0)) next
      aic <- tryCatch(stats::AIC(fit0), error = function(e) Inf)
      if (is.finite(aic) && aic < best) {
        best <- aic
        nk <- i
      }
    }
  }
  nk <- as.integer(nk)
  rhs_cov <- if (length(covars)) paste(covars, collapse = " + ") else "1"
  form <- stats::as.formula(paste0(
    "Disease ~ rms::rcs(", index, ", ", nk, ") * Country + ", rhs_cov
  ))
  fit <- rms::lrm(form, data = dat, x = TRUE, y = TRUE)
  a <- stats::anova(fit)
  tab <- as.data.frame(a, stringsAsFactors = FALSE)
  tab$term <- rownames(a)
  # as.data.frame 会把 * 换成点，匹配用原始行名
  hit <- grep(paste0("^", index, " \\* Country"), tab$term)
  if (!length(hit)) {
    hit <- grep(paste0("^", index, ".*Country.*Factor"), tab$term)
  }
  if (!length(hit)) stop("anova 中未找到暴露×Country 交互行", call. = FALSE)
  row <- tab[hit[[1L]], , drop = FALSE]
  pcol <- names(row)[grepl("^P$", names(row))][1L]
  pval <- suppressWarnings(as.numeric(row[[pcol]]))
  nl <- grep("Nonlinear Interaction", tab$term)
  p_nl <- if (length(nl)) suppressWarnings(as.numeric(tab[[pcol]][nl[[1L]]])) else NA_real_
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(out_dir, "Pooled_RCS_interaction.txt")
  lines <- c(
    paste0("index=", index),
    paste0("nk=", nk),
    paste0("n=", nrow(dat)),
    paste0("covariates=", paste(covars, collapse = "+")),
    paste0("interaction_term=", row$term[1L]),
    paste0("df=", row[["d.f."]][1L]),
    paste0("P_interaction=", signif(pval, 4)),
    paste0("P_nonlinear_interaction=", signif(p_nl, 4)),
    if (is.finite(pval) && pval > 0.05) {
      "interpretation=P>0.05：库内百分位与结局的样条形状在两库无统计学显著差异，Pooled 曲线可共同解释。"
    } else if (is.finite(pval)) {
      "interpretation=P<=0.05：两库样条形状存在统计学差异，Pooled 曲线不能视为形状完全一致。"
    } else {
      "interpretation=交互 P 未能估计"
    }
  )
  writeLines(lines, out)
  utils::write.csv(tab, file.path(out_dir, "Pooled_RCS_interaction_anova.csv"), row.names = FALSE)
  cli::cli_alert_success("Pooled RCS 交互 P={signif(pval, 4)} → {out}")
  invisible(pval)
}

run_rcs_sxx <- function(db) {
  cli::cli_h1("Relock Table S-XX (RCS cutoff): {db}")
  is_pooled <- identical(db, "Pooled")
  if (is_pooled) {
    out_dir <- file.path(study_root, "phase3_post_Pooled")
    ck_dir <- file.path(out_dir, "checkpoints")
    m1 <- .M1_LOCK
    m2 <- .M2_POOLED
    e <- new.env(parent = globalenv())
    sys.source(file.path(study_root, "config_phase1_CHARLS.R"), envir = e)
  } else {
    out_dir <- cross_lagged_phase1_dir(study_root, db)
    ck_dir <- file.path(out_dir, "checkpoints")
    m1 <- .M1_LOCK
    m2 <- .M2_LOCK
    e <- new.env(parent = globalenv())
    sys.source(file.path(study_root, paste0("config_phase1_", db, ".R")), envir = e)
  }
  .hidx_early <- as.character((.meta_lock %||% list())$pooled_index %||% "")[1L]
  ck <- NULL
  # 换了 Pooled 暴露尺度后，旧 RCS 检查点仍是原始分，不能续跑
  if (!(is_pooled && nzchar(.hidx_early)))
    ck <- .load_rcs_checkpoint(ck_dir)
  if (is.null(ck)) {
    # 无 RCS 检查点：单库用 VIF final；Pooled 无 VIF，改从 D04 / logistic ck 建 ctx
    if (is_pooled) {
      cli::cli_alert_warning(
        "Pooled: 无 rcs_incidence；Pooled 不做 VIF，改从 postvif RData / logistic 检查点续跑 rcs → S-XX"
      )
      # config 稍后 .lock_cfg；此处先用 e$config 占位，后面再覆盖
      ck <- .load_pooled_ctx_for_rcs(
        study_root, e$config, m1, m2, ck_dir
      )
    } else {
      cli::cli_alert_warning("{db}: 无 rcs_incidence 检查点，尝试从 VIF final 续跑 rcs → S-XX")
      ck <- .load_vif_checkpoint(ck_dir)
    }
  }
  d <- ck$data$imputed %||% ck$data$cleaned
  .idx_nm <- as.character(
    (e$config$incidence %||% list())$index_var %||%
      (.meta_lock$index_var %||% "FI")
  )[1L]
  .hidx <- as.character((.meta_lock %||% list())$pooled_index %||% "")[1L]
  if (is_pooled && nzchar(.hidx) && !is.null(d) && .hidx %in% names(d)) {
    .idx_nm <- .hidx
    cli::cli_alert_info("Pooled RCS 暴露: {(.idx_nm)}")
  }
  .rcs_grp <- paste0(.idx_nm, "_RCS_Group")
  if (!is.null(d) && !.rcs_grp %in% names(d) && "FI_RCS_Group" %in% names(d))
    .rcs_grp <- "FI_RCS_Group"
  has_grp <- !is.null(d) && .rcs_grp %in% names(d)
  nlev <- if (has_grp) length(unique(stats::na.omit(as.character(d[[.rcs_grp]])))) else 0L

  config <- .lock_cfg(e$config, m1, m2, blocks = c(.log_blocks, .rcs_sxx_block, "rcs_incidence"))
  # 强制 primary 二分（图可标全部交点；表/分组只用主 cutoff）
  if (is.null(config$rcs_incidence)) config$rcs_incidence <- list()
  config$rcs_incidence$group_cutoffs <- "primary"
  config$rcs_incidence$index_var <- .idx_nm
  if (is.null(config$logistic)) config$logistic <- list()
  config$logistic$index_var <- .idx_nm
  if (is.null(config$incidence)) config$incidence <- list()
  config$incidence$index_var <- .idx_nm
  if (is_pooled && grepl("harmonized", .idx_nm, fixed = TRUE)) {
    config$incidence$index_var_display_name <- "Leisure activity percentile"
    config$logistic$index_var_display_name <- "Leisure activity percentile"
  }
  config$project$name <- paste0("CrossLagged_", db, "_relock_rcs_sxx")
  config$project$database <- db
  config$project$output_dir <- out_dir
  if (is_pooled) {
    .pp <- file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData")
    if (!file.exists(.pp))
      .pp <- file.path(study_root, "data/harmonized/D04_Pooled_hip_postvif.RData")
    config$data$rawdata_path <- .pp
    config$data$rawdata_obj <- "dabiao"
  }

  # 同步 RCS 组标签为数据中实际出现的水平（去掉空档组，否则 glm 表构建失败）
  if (!is.null(d) && .rcs_grp %in% names(d)) {
    d[[.rcs_grp]] <- droplevels(factor(as.character(d[[.rcs_grp]])))
    ck$data$imputed <- d
    if (!is.null(ck$data$cleaned)) ck$data$cleaned <- d
    labs <- levels(d[[.rcs_grp]])
    ck$results$rcs_cutoff_group_labels <- labs
    ck$results$rcs_cutoff_group_col <- .rcs_grp
    if (is.null(config$logistic_quartile_glm_rcs)) config$logistic_quartile_glm_rcs <- list()
    config$logistic_quartile_glm_rcs$group_levels <- labs
    config$logistic_quartile_glm_rcs$group_var <- .rcs_grp
    nlev <- length(labs)
    has_grp <- nlev >= 2L
  }

  ck$results$Model1Factors <- m1
  ck$results$Model2Factors <- m2
  ck$results$vif_final_pass <- m2
  ck$config <- config

  # 始终重跑 rcs_incidence：保证 FI_RCS_Group = primary cutoff 二分（与 ELSA/HRS 一致）
  only_blocks <- c("rcs_incidence", .rcs_sxx_block)
  pipe_blocks <- c(.pre_blocks, "rcs_incidence", .rcs_sxx_block)

  pipe <- list(
    name = paste0("cross_lagged_relock_rcs_sxx_", db),
    blocks = pipe_blocks,
    logistic_gate = list(enable = FALSE),
    checkpoint = list(enable = TRUE, dir = ck_dir),
    render_tables_after = .rcs_sxx_block,
    render_figures_after = character(0),
    dual_db = list(enable = FALSE)
  )

  tryCatch({
    run_pipeline(
      root, config = config, pipeline = pipe,
      run_opts = list(only = only_blocks, initial_ctx = ck)
    )
    # 验收：primary 二分
    ck2 <- .load_rcs_checkpoint(ck_dir)
    if (!is.null(ck2)) {
      d2 <- ck2$data$imputed %||% ck2$data$cleaned
      gcol <- ck2$results$rcs_cutoff_group_col %||% .rcs_grp
      if (!gcol %in% names(d2) && "FI_RCS_Group" %in% names(d2)) gcol <- "FI_RCS_Group"
      if (!gcol %in% names(d2)) {
        alt <- grep("_RCS_Group$", names(d2), value = TRUE)
        if (length(alt)) gcol <- alt[[1L]]
      }
      g <- d2[[gcol]]
      n2 <- length(unique(stats::na.omit(as.character(g))))
      mode2 <- ck2$results$rcs_group_cutoffs_mode %||% "?"
      if (!identical(as.character(mode2), "primary") || n2 != 2L) {
        stop(
          db, " Table S-XX 验收失败：期望 group_cutoffs=primary 且 2 组，实际 mode=",
          mode2, " n=", n2, " col=", gcol, call. = FALSE
        )
      }
    }
    if (is_pooled && grepl("harmonized", .idx_nm, fixed = TRUE)) {
      .ppx <- file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData")
      .ex <- new.env()
      load(.ppx, envir = .ex)
      .nk_use <- NULL
      .ckr <- .load_rcs_checkpoint(ck_dir)
      if (!is.null(.ckr)) .nk_use <- .ckr$results$rcs_incidence_nk
      .pooled_rcs_interaction(
        .ex$dabiao,
        .idx_nm,
        m2,
        e$config$project$analysis_group %||% "Circadian_Disorder",
        file.path(out_dir, "Tables"),
        nk = .nk_use
      )
    }
    cli::cli_alert_success(
      "{db} Table S-XX (RCS primary 二分) relock done; M2={paste(m2, collapse='+')}"
    )
  }, error = function(err) {
    cli::cli_alert_danger("{db} Table S-XX relock 失败: {conditionMessage(err)}")
    stop(err)
  })
  invisible(TRUE)
}

run_pooled <- function() {
  cli::cli_h1("Relock logistic: Pooled")
  pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData")
  if (!file.exists(pooled_path))
    pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_hip_postvif.RData")
  if (!file.exists(pooled_path)) stop("缺少 Pooled RData: ", pooled_path)
  ee <- new.env(); load(pooled_path, envir = ee)
  dabiao <- ee$dabiao
  ctry_lvls <- sort(unique(as.character(dabiao$Country)))
  dabiao$Country <- factor(dabiao$Country, levels = ctry_lvls)

  m1 <- .M1_LOCK
  m2 <- .M2_POOLED
  miss <- setdiff(.M2_LOCK, names(dabiao))
  if (length(miss))
    stop("Pooled 缺锁定协变量: ", paste(miss, collapse = ", "))
  if (!"Country" %in% names(dabiao))
    stop("Pooled 缺 Country")

  e <- new.env(parent = globalenv())
  sys.source(file.path(study_root, "config_phase1_CHARLS.R"), envir = e)
  out_dir <- file.path(study_root, "phase3_post_Pooled")
  ck_dir <- file.path(out_dir, "checkpoints")
  dir.create(ck_dir, recursive = TRUE, showWarnings = FALSE)

  config <- .lock_cfg(e$config, m1, m2)
  config$project$name <- "Hip_Frailty_Pooled_relock_logistic"
  config$project$database <- "Pooled"
  config$project$output_dir <- out_dir
  config$data$rawdata_path <- pooled_path
  config$data$rawdata_obj <- "dabiao"
  config$column_mapping$database_type <- "regular"
  .hidx <- as.character((.meta_lock %||% list())$pooled_index %||% "")[1L]
  if (nzchar(.hidx) && .hidx %in% names(dabiao)) {
    config$incidence$index_var <- .hidx
    if (is.null(config$logistic)) config$logistic <- list()
    config$logistic$index_var <- .hidx
    config$prediction$index_vars <- .hidx
    if (is.null(config$rcs_incidence)) config$rcs_incidence <- list()
    config$rcs_incidence$index_var <- .hidx
    if (is.null(config$logistic_quartile_glm)) config$logistic_quartile_glm <- list()
    config$logistic_quartile_glm$force_export <- TRUE
    config$logistic_quartile_glm$index_var <- .hidx
    config$incidence$index_var_display_name <- "Leisure activity percentile"
    config$logistic$index_var_display_name <- "Leisure activity percentile"
    cli::cli_alert_info("Pooled 暴露改用库内标准化列: {(.hidx)}")
  }

  initial_ctx <- list(
    config = config,
    data = list(raw = dabiao, cleaned = dabiao, mapped = dabiao, imputed = dabiao),
    results = list(
      Model1Factors = m1,
      Model2Factors = m2,
      vif_final_pass = m2,
      cross_lagged_covariate_lock = .lock
    ),
    log = list(),
    root_output_dir = out_dir
  )

  pipe <- list(
    name = "cross_lagged_relock_Pooled",
    blocks = .log_blocks,
    logistic_gate = list(enable = FALSE),
    checkpoint = list(enable = TRUE, dir = ck_dir),
    render_tables_after = .log_blocks,
    render_figures_after = character(0),
    dual_db = list(enable = FALSE)
  )

  dir.create(file.path(study_root, "phase2_Pooled"), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c(
      paste("Model1:", paste(m1, collapse = " + ")),
      paste("Model2:", paste(m2, collapse = " + ")),
      "Country_in_Model2: TRUE",
      paste("lock_source:", .lock$source),
      paste("Lock:", paste(.M2_LOCK, collapse = "+"), "+ Country")
    ),
    file.path(study_root, "phase2_Pooled", "pooled_model_factors.txt")
  )
  .write_lock_note(out_dir, "Pooled", m1, m2, .lock)

  run_pipeline(
    root, config = config, pipeline = pipe,
    run_opts = list(only = .log_blocks, initial_ctx = initial_ctx)
  )
  cli::cli_alert_success("Pooled logistic relock done")
}

# acceptance：main_grouping 必须跟课题 meta（=主文 Table 2 闸门），供 long_figs/Change 读取
.main_grouping <- as.character(.meta_lock$grouping %||% "tertile")[1L]
.main_grouping_note <- if (identical(.main_grouping, "quartile")) {
  "main_grouping=quartile (aligned with study_meta / Table 2)"
} else if (identical(.main_grouping, "tertile")) {
  "main_grouping=tertile (aligned with study_meta / Table 2; hip default)"
} else {
  paste0("main_grouping=", .main_grouping, " (aligned with study_meta / Table 2)")
}
acc <- file.path(study_root, "phase3_relock_acceptance.txt")
writeLines(
  c(
    paste0("time=", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    .main_grouping_note,
    "Table_S-XX=logistic_quartile_glm_rcs; group_cutoffs=primary (2 levels); required CHARLS/ELSA/HRS/Pooled",
    "RCS_rule=Fig may annotate rcs_cutoffs_all; FI_RCS_Group/Table S-XX use primary cutoff only",
    paste0("Model1=", paste(.M1_LOCK, collapse = " + ")),
    paste0("Model2_single=", paste(.M2_LOCK, collapse = " + ")),
    paste0("Model2_pooled=", paste(.M2_POOLED, collapse = " + ")),
    paste0("lock_source=", .lock$source),
    paste0("intersect_final=", paste(.lock$intersect_final, collapse = ", ")),
    paste0("intersect_screen=", paste(.lock$intersect_screen, collapse = ", ")),
    paste0("lock_cohorts=", paste(.lock$lock_cohorts %||% character(0), collapse = ", ")),
    paste0("validation_cohorts=", paste(.lock$validation_cohorts %||% character(0), collapse = ", ")),
    "rule=CHARLS+ELSA TableS4/VIF_screen 交集锁定 Model2；Pooled Model2+=Country；NHANES 验证队列套用锁定集"
  ),
  acc
)

.main_xs <- if (!is.null(.meta_lock)) cross_lagged_main_cohorts(.meta_lock) else character(0)
if (!length(.main_xs)) .main_xs <- c("CHARLS", "ELSA", "HRS")
dbs <- c(.main_xs, "Pooled")
if (!is.null(only_dbs) && length(only_dbs)) dbs <- intersect(dbs, only_dbs)
if (!length(dbs)) stop("无有效 --only 库")

if (!isTRUE(rcs_only)) {
  for (db in dbs) {
    if (identical(db, "Pooled")) run_pooled() else run_unit(db)
  }
}
# Table S-XX（RCS cutoff）与主文同一锁定协变量
for (db in dbs) {
  run_rcs_sxx(db)
}
cli::cli_alert_success("Relock logistic + Table S-XX 完成: {paste(dbs, collapse = ', ')}")
cli::cli_alert_info("见 {acc}")
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
