#!/usr/bin/env Rscript
# Blocks/54_cross_lagged_full/phases/phase_long_figs.R
# 多年纵向：long_prepare（含无随访剔除+纳排图）→ corr/forest/network/bar/fig1/change → mediation
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
study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
sims <- 200L
only_dbs <- NULL
change_only <- FALSE
corr_mediation_only <- FALSE
pooled_mediation_only <- FALSE
skip_network <- FALSE
.scheme_override <- NULL
rescreen_med_covars <- FALSE
# 纵向/交叉滞后默认三库；Pooled 仅主文 logistic 阶段保留（加 --with-pooled 才跑）
run_pooled_long <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--sims" && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--only" && i < length(args)) {
    only_dbs <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (args[[i]] %in% c("--change-only", "--only-change")) {
    change_only <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--corr-mediation-only", "--only-corr-mediation")) {
    corr_mediation_only <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--pooled-mediation-only", "--only-pooled-mediation")) {
    # 定点：prepare 两库 → 合并中介表（库内百分位）→ 只跑 Pooled 中介 → Table S9.2
    pooled_mediation_only <- TRUE
    run_pooled_long <- TRUE
    corr_mediation_only <- TRUE
    i <- i + 1L
  } else if (args[[i]] %in% c("--skip-network", "--no-network")) {
    skip_network <- TRUE; i <- i + 1L
  } else if (args[[i]] == "--scheme" && i < length(args)) {
    .scheme_override <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
  } else if (args[[i]] %in% c("--rescreen-mediation-covars", "--rescreen-med-covars")) {
    rescreen_med_covars <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--with-pooled", "--pooled")) {
    run_pooled_long <- TRUE; i <- i + 1L
  } else if (args[[i]] %in% c("--no-pooled")) {
    run_pooled_long <- FALSE; i <- i + 1L
  } else i <- i + 1L
}
study_root <- .cl_pick_study_root(args, study_root %||% NULL)
if (is.null(study_root) || !nzchar(as.character(study_root)[1L])) {
  study_root <- .cl_pick_study_root(args, "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
data_root <- file.path(study_root, "data")
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/cross_lagged_covariate_lock.R"))
source(file.path(root, "R/cross_lagged_mediation_covar_select.R"))
source(file.path(root, "R/cross_lagged_fi_item_labels.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/15block_cross_lagged_corr_table.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/16block_cross_lagged_forest_or.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/17block_cross_lagged_network.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/18block_cross_lagged_country_year_bar.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/19block_cross_lagged_fig1_group.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/20block_cross_lagged_change_logistic.R"))
# 马卡龙中介图辅助（.mp01_*）；纵向中介块复用
source(file.path(root, "Blocks/20_mediation/01block_mediation_prognosis.R"))
source(file.path(root, "Blocks/20_mediation/06block_mediation_longitudinal.R"))

options(warn = 1, cli.hyperlink = FALSE)

# 主文闸门分位 + 锁定协变量（与 Table 2 / S-XX 一致）
# 分位一致性铁律：change/S5 必须与主文 logistic 同分位。
# 兜底顺序：study_meta → relock acceptance → tertile。禁止用 acceptance 覆盖已正确的 meta
# （髋部旧模板曾把 acceptance 写死 tertile，会把昼夜 quartile 主文带偏）。
.lock_scheme <- tryCatch({
  as.character(cross_lagged_study_meta(study_root)$grouping %||% "")[1L]
}, error = function(e) "")
.lock_m2 <- c("Age", "Alcohol_drinking")
.lock_m1 <- "Age"
acc <- file.path(study_root, "phase3_relock_acceptance.txt")
if (file.exists(acc)) {
  lines <- readLines(acc, warn = FALSE)
  if (!nzchar(.lock_scheme)) {
    mg <- grep("^main_grouping=", lines, value = TRUE)
    if (length(mg)) {
      .lock_scheme <- sub("^main_grouping=([^ (]+).*$", "\\1", mg[[1L]])
    }
  }
  m2l <- grep("^Model2_single=", lines, value = TRUE)
  if (length(m2l)) {
    raw <- sub("^Model2_single=", "", m2l[[1L]])
    .lock_m2 <- trimws(unlist(strsplit(raw, "\\+|,")))
    .lock_m2 <- .lock_m2[nzchar(.lock_m2)]
  }
  m1l <- grep("^Model1=", lines, value = TRUE)
  if (length(m1l)) {
    .lock_m1 <- trimws(sub("^Model1=", "", m1l[[1L]]))
  }
}
if (!nzchar(.lock_scheme)) .lock_scheme <- "tertile"
if (!is.null(.scheme_override) && .scheme_override %in% c("binary", "tertile", "quartile", "quintile")) {
  cli::cli_alert_warning(
    "本轮 --scheme={(.scheme_override)} 覆盖 meta 分位 {(.lock_scheme)}；不改 study_meta / 主文闸门"
  )
  .lock_scheme <- .scheme_override
}
cli::cli_alert_info(
  "Change/long: scheme={(.lock_scheme)}; M2={paste(.lock_m2, collapse='+')}"
)
.lockf <- file.path(study_root, "phase2_Pooled", "locked_covariates.txt")
if (file.exists(.lockf)) {
  .ll <- readLines(.lockf, warn = FALSE)
  .grab <- function(header) {
    i <- which(trimws(.ll) == header)
    if (!length(i)) return(character(0))
    rest <- .ll[(i[[1L]] + 1L):length(.ll)]
    stop_at <- which(nzchar(trimws(rest)) & grepl("^Model", rest))
    chunk <- if (length(stop_at)) rest[seq_len(stop_at[[1L]] - 1L)] else rest
    chunk <- trimws(chunk)
    chunk[nzchar(chunk) & !startsWith(chunk, "#")]
  }
  m1p <- .grab("Model1:")
  m2p <- .grab("Model2:")
  if (length(m1p)) .lock_m1 <- m1p
  if (length(m2p)) .lock_m2 <- m2p
  cli::cli_alert_info("锁定协变量覆盖自 phase2_Pooled: M1={paste(.lock_m1, collapse='+')}; M2={paste(.lock_m2, collapse='+')}")
}

panel <- list(
  CHARLS = list(
    baseline_year = 2011L, country = "China",
    dep_file = "CHARLS_2013_抑郁.csv", dep_id = "ID", dep_score = "cesd10_total",
    years = list(
      list(year = 2011L, id_col = "ID",
           frailty_csv = file.path(data_root, "CHARLS/虚弱_charls_2011.csv"),
           outcome_rdata = file.path(data_root, "CHARLS/D03_result_CHARLS_2011.RData")),
      list(year = 2015L, id_col = "ID",
           frailty_csv = file.path(data_root, "CHARLS/虚弱_charls_2015.csv"),
           outcome_rdata = file.path(data_root, "CHARLS/D03_result_CHARLS_2015.RData"))
    )
  ),
  ELSA = list(
    # 课题约定：ELSA 2004 / 2008 / 2012 / 2016（wave2/4/6/8）
    baseline_year = 2004L, country = "UK",
    dep_file = "ELSA_wave3_抑郁.csv", dep_id = "idauniq", dep_score = "cesd8_total",
    years = list(
      list(year = 2004L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave2.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA2.RData")),
      list(year = 2008L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave4.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA4.RData")),
      list(year = 2012L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave6.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA6.RData")),
      list(year = 2016L, id_col = "idauniq",
           frailty_csv = file.path(data_root, "ELSA/虚弱_elsa_wave8.csv"),
           outcome_rdata = file.path(data_root, "ELSA/D03_result_ELSA8.RData"))
    )
  ),
  HRS = list(
    baseline_year = 2012L, country = "America",
    dep_file = "HRS_2014_抑郁.csv", dep_id = "HHID_PN", dep_score = "cesd8_total",
    years = list(
      list(year = 2012L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2012.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS12.RData")),
      list(year = 2014L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2014.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS14.RData")),
      list(year = 2016L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2016.csv"),
           outcome_rdata = file.path(data_root, "HRS/D03_result_HRS16.RData")),
      list(year = 2018L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2018.csv"),
           outcome_rdata = NULL),
      list(year = 2020L, id_col = "hhidpn",
           frailty_csv = file.path(data_root, "HRS/虚弱_hrs_2020.csv"),
           outcome_rdata = NULL)
    )
  )
)

.study_panel <- file.path(study_root, "config_long_panel.R")
if (file.exists(.study_panel)) {
  sys.source(.study_panel, envir = environment())
  cli::cli_alert_info("已加载课题纵向 panel: { .study_panel }")
}
.circ_exp_lab <- "Frailty Index"
.circ_med_lab <- "Depression"
.circ_out_lab <- "Hip fracture"
.ev_ag <- "Hip_Fracture"
.ev_rg <- "No_Fracture"
.cl_meta <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
if (!is.null(.cl_meta)) {
  .ev_ag <- as.character(.cl_meta$analysis_group %||% .ev_ag)[1L]
  .ev_rg <- as.character(.cl_meta$reference_group %||% .ev_rg)[1L]
  if (!is.null(.cl_meta$labels$outcome_label) &&
      nzchar(as.character(.cl_meta$labels$outcome_label)[1L])) {
    .circ_out_lab <- as.character(.cl_meta$labels$outcome_label)[1L]
  }
  if (!is.null(.cl_meta$labels$mediator_label) &&
      nzchar(as.character(.cl_meta$labels$mediator_label)[1L])) {
    .circ_med_lab <- as.character(.cl_meta$labels$mediator_label)[1L]
  }
  if (!is.null(.cl_meta$labels$exposure_label) &&
      nzchar(as.character(.cl_meta$labels$exposure_label)[1L])) {
    .circ_exp_lab <- as.character(.cl_meta$labels$exposure_label)[1L]
  }
}
if (exists(".circadian_index_var", inherits = TRUE)) {
  .circ_exp_lab <- as.character(
    if (exists(".circadian_exposure_label", inherits = TRUE) &&
        nzchar(as.character(.circadian_exposure_label)[1L])) {
      .circadian_exposure_label
    } else {
      .circadian_index_var
    }
  )[1L]
  .circ_med_lab <- as.character(.circadian_mediator_label %||% "Frailty Index")[1L]
  .circ_out_lab <- as.character(.circadian_outcome_label %||% "Circadian disorder")[1L]
  .ev_ag <- "Circadian_Disorder"
  .ev_rg <- "No_Disorder"
}
# 昼夜中介变量：默认 FI；课题可设 .circadian_mediator_var = "CRP"
.circ_med_var <- if (exists(".circadian_mediator_var", inherits = TRUE) &&
                    nzchar(as.character(.circadian_mediator_var)[1L])) {
  as.character(.circadian_mediator_var)[1L]
} else if (exists(".circadian_index_var", inherits = TRUE)) {
  "FI"
} else {
  "Depression_cont"
}
.circ_med_xf <- if (exists(".circadian_mediator_transform", inherits = TRUE) &&
                   nzchar(as.character(.circadian_mediator_transform)[1L])) {
  as.character(.circadian_mediator_transform)[1L]
} else {
  ""
}
# 中介/相关回归可从 Table2 Model2 剔除变量（如 CRP 中介时踢 WBC）；Change/Table2 仍用完整 .lock_m2
.med_exclude_covars <- if (exists(".circadian_mediation_exclude_covars", inherits = TRUE)) {
  unique(as.character(.circadian_mediation_exclude_covars))
} else {
  character(0)
}
.med_exclude_covars <- .med_exclude_covars[nzchar(.med_exclude_covars) & !is.na(.med_exclude_covars)]
.pooled_harm <- if (exists(".circadian_pooled_harmonize", inherits = TRUE) &&
                    nzchar(as.character(.circadian_pooled_harmonize)[1L])) {
  tolower(as.character(.circadian_pooled_harmonize)[1L])
} else {
  ""
}
.change_leisure <- exists(".circadian_index_var", inherits = TRUE) &&
  identical(as.character(.circadian_index_var)[1L], "Leisure_score")
.change_mean_lab <- if (isTRUE(.change_leisure)) paste("Mean", .circ_exp_lab) else "Mean FI"
.change_chg_lab <- if (isTRUE(.change_leisure)) paste(.circ_exp_lab, "change") else "FI change"
.change_stem <- if (isTRUE(.change_leisure)) {
  "Table_Change_Leisure_activity_score_mean_and_change"
} else {
  "Table_Change_FI_mean_and_change"
}

load_ck <- function(db) {
  cdir <- file.path(cross_lagged_phase1_dir(study_root, db), "checkpoints")
  cands <- c(
    file.path(cdir, "step10_multicollinearity_final.rds"),
    file.path(cdir, "step09_multicollinearity_final.rds"),
    file.path(cdir, "multicollinearity_final.rds"),
    file.path(cdir, "step06_baseline_binary.rds"),
    file.path(cdir, "step05_baseline_binary.rds")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("无检查点: ", db)
  ck <- readRDS(hit)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

# 抑郁中介：默认与 Table2 锁定 Model2 三库共用（不按库重筛不同集）
.med_lock_rds <- file.path(study_root, "mediation_depression_covar_lock.rds")
.med_lock_txt <- file.path(study_root, "mediation_depression_covar_lock.txt")
.med_lock <- NULL

.resolve_db_covars <- function(db, fallback_m1 = .lock_m1, fallback_m2 = .lock_m2,
                               for_mediation = TRUE) {
  # 中介/相关：优先用 .med_lock（已剔 .circadian_mediation_exclude_covars）
  # Change 等仍可传 for_mediation=FALSE 用完整 Table2 Model2
  m2 <- fallback_m2
  m1 <- fallback_m1
  use_lock <- !is.null(.med_lock) && (isTRUE(for_mediation) || isTRUE(rescreen_med_covars))
  if (isTRUE(use_lock)) {
    if (is.list(.med_lock$model2_by_db) && db %in% names(.med_lock$model2_by_db)) {
      m2 <- as.character(.med_lock$model2_by_db[[db]] %||% m2)
    } else if (is.list(.med_lock$covariates_by_db) && db %in% names(.med_lock$covariates_by_db)) {
      m2 <- as.character(.med_lock$covariates_by_db[[db]] %||% m2)
    }
    if (is.list(.med_lock$model1_by_db) && db %in% names(.med_lock$model1_by_db)) {
      m1 <- as.character(.med_lock$model1_by_db[[db]] %||% m1)
    }
  }
  if (isTRUE(for_mediation) && length(.med_exclude_covars)) {
    m2 <- setdiff(as.character(m2), .med_exclude_covars)
  }
  m2 <- m2[!is.na(m2) & nzchar(m2)]
  m1 <- m1[!is.na(m1) & nzchar(as.character(m1))]
  if (!length(m1)) m1 <- "Age"
  if (!length(m2)) m2 <- unique(c(as.character(m1), "Alcohol_drinking"))
  if (length(setdiff(m2, m1)) == 0L) {
    # 仅 Age 时不要硬塞 Alcohol_drinking（可能不在数据）；保留 m1
    m2 <- unique(as.character(m1))
  }
  list(m1 = m1, m2 = m2)
}

run_blocks_after_prepare <- function(ctx) {
  if (isTRUE(change_only)) {
    tryCatch({ ctx <- block_cross_lagged_change_logistic(ctx) },
             error = function(e) cli::cli_alert_warning("change: {e$message}"))
    return(ctx)
  }
  if (!isTRUE(corr_mediation_only)) {
    tryCatch({ ctx <- block_cross_lagged_forest_or(ctx) },
             error = function(e) cli::cli_alert_warning("forest: {e$message}"))
  }
  tryCatch({ ctx <- block_cross_lagged_corr_table(ctx) },
           error = function(e) cli::cli_alert_warning("corr: {e$message}"))
  if (!isTRUE(corr_mediation_only)) {
    tryCatch({ ctx <- block_cross_lagged_country_year_bar(ctx) },
             error = function(e) cli::cli_alert_warning("country_year: {e$message}"))
    tryCatch({ ctx <- block_cross_lagged_fig1_group(ctx) },
             error = function(e) cli::cli_alert_warning("fig1: {e$message}"))
    if (isTRUE(skip_network)) {
      cli::cli_alert_info("跳过 cross_lagged_network（--skip-network）")
    } else {
      tryCatch({ ctx <- block_cross_lagged_network(ctx) },
               error = function(e) cli::cli_alert_warning("network: {e$message}"))
    }
    tryCatch({ ctx <- block_cross_lagged_change_logistic(ctx) },
             error = function(e) cli::cli_alert_warning("change: {e$message}"))
  }
  if (!is.null(ctx$data$longitudinal_mediation) && nrow(ctx$data$longitudinal_mediation) >= 30L) {
    tryCatch({
      ctx$config$mediation_longitudinal$sims <- sims
      ctx <- block_mediation_longitudinal(ctx)
    }, error = function(e) cli::cli_alert_warning("mediation: {e$message}"))
  } else {
    cli::cli_alert_warning("mediation 跳过（表过小或缺失）")
  }
  ctx
}

dbs <- if (exists(".circadian_dbs", inherits = TRUE)) {
  as.character(.circadian_dbs)
} else {
  c("CHARLS", "ELSA", "HRS")
}
dbs <- setdiff(dbs, "NHANES")
if (!is.null(only_dbs)) {
  dbs <- intersect(dbs, setdiff(only_dbs, c("Pooled", "NHANES")))
  if ("Pooled" %in% only_dbs) run_pooled_long <- TRUE
}
.long_cohorts <- dbs
if (isTRUE(run_pooled_long)) .long_cohorts <- c(.long_cohorts, "Pooled")
cli::cli_alert_info(
  "纵向/交叉滞后队列: {paste(.long_cohorts, collapse=', ')}{if (!isTRUE(run_pooled_long)) '（默认无 Pooled；--with-pooled 可开）' else ''}"
)

all_long <- list()
all_wide <- list()
all_med <- list()
all_flow <- list()
all_ck_data <- list()

# ── Pass 1：long_prepare（拿中介分析表，供按库筛协变量）────────────────────
for (db in dbs) {
  cli::cli_h1("Cross-lagged prepare: {db}")
  ck <- load_ck(db)
  all_ck_data[[db]] <- ck$data
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)

  ctx <- list(
    data = ck$data,
    results = list(
      Model1Factors = .lock_m1,
      Model2Factors = .lock_m2,
      logistic_grouping_scheme = .lock_scheme
    ),
    config = list(
      project = list(
        database = db,
        output_dir = out_dir,
        analysis_group = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        reference_group = if (exists(".circadian_index_var", inherits = TRUE)) "No_Disorder" else .ev_rg
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      incidence = list(index_var = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
      mediation_longitudinal = list(
        treat = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI",
        # 昼夜默认 FI；可由 .circadian_mediator_var 覆盖（如 CRP）
        mediator = .circ_med_var,
        mediator_transform = .circ_med_xf,
        outcome = "Disease_Group",
        outcome_event_level = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        sims = sims,
        seed = 40595747L
      ),
      cross_lagged_network = list(
        node_stems = if (exists(".circadian_node_stems", inherits = TRUE)) .circadian_node_stems else character(0),
        fi_items_only = FALSE,
        include_outcome = FALSE,
        include_lipids = FALSE,
        keep_forced_nodes = TRUE,
        max_nodes = 8L
      ),
      cross_lagged_long_prepare = list(
        medition_dir = file.path(data_root, "medition"),
        require_baseline_free = TRUE,
        carry_vars = if (exists(".circadian_carry_vars", inherits = TRUE)) .circadian_carry_vars else character(0),
        rebuild_circadian_conditions = if (exists(".circadian_rebuild_conditions", inherits = TRUE)) {
          isTRUE(.circadian_rebuild_conditions)
        } else {
          TRUE
        },
        panel = panel,
        require_complete_fi = !isTRUE(.change_leisure)
      )
    )
  )
  ctx <- block_cross_lagged_long_prepare(ctx)
  all_long[[db]] <- ctx$data$longitudinal
  all_wide[[db]] <- ctx$data$longitudinal_wide
  all_med[[db]] <- ctx$data$longitudinal_mediation
  all_flow[[db]] <- ctx$results$long_prepare
  print(ctx$results$long_prepare)
}

# ── 抑郁中介协变量：与 Table2 锁定 Model2 三库共用 ──────────────────────────
if (!isTRUE(change_only)) {
  if (isTRUE(rescreen_med_covars)) {
    cli::cli_h1("Screen best depression-mediation covariates (per DB; 可选)")
    sims_screen <- as.integer(min(as.integer(sims), 100L))
    .med_lock <- cross_lagged_mediation_lock_depression_covars(
      all_med,
      outfile_rds = .med_lock_rds,
      outfile_txt = .med_lock_txt,
      sims = sims_screen,
      seed = 1000L
    )
    scr_dir <- file.path(study_root, "phase3_long_Pooled", "Tables")
    dir.create(scr_dir, recursive = TRUE, showWarnings = FALSE)
    for (db in names(.med_lock$screens %||% list())) {
      utils::write.csv(
        .med_lock$screens[[db]]$table,
        file.path(scr_dir, paste0("Mediation_covar_screen_", db, ".csv")),
        row.names = FALSE
      )
    }
  } else {
    # 三库同一套：Table2 Model2 减去 .circadian_mediation_exclude_covars（默认不剔）
    common_cov <- as.character(.lock_m2)
    if (!length(common_cov)) common_cov <- c("Age", "Alcohol_drinking")
    table2_cov <- common_cov
    if (length(.med_exclude_covars)) {
      common_cov <- setdiff(common_cov, .med_exclude_covars)
      if (!length(common_cov)) common_cov <- setdiff(table2_cov, .med_exclude_covars)
      if (!length(common_cov)) common_cov <- c("Age")
    }
    locks <- setNames(replicate(3L, common_cov, simplify = FALSE), c("CHARLS", "ELSA", "HRS"))
    m1s <- setNames(replicate(3L, as.character(.lock_m1 %||% "Age"), simplify = FALSE),
                    c("CHARLS", "ELSA", "HRS"))
    .med_lock <- list(
      covariates_by_db = locks,
      model2_by_db = locks,
      model1_by_db = m1s,
      table2_model2 = table2_cov,
      exclude_covars = .med_exclude_covars,
      source = "table2_model2_minus_mediation_exclude"
    )
    saveRDS(.med_lock, .med_lock_rds)
    writeLines(c(
      paste0("# Mediation/corr covariates = Table2 Model2 minus exclude (三库共用)"),
      paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      paste0("Table2_Model2=", paste(table2_cov, collapse = "+")),
      paste0("Exclude=", if (length(.med_exclude_covars)) paste(.med_exclude_covars, collapse = "+") else "(none)"),
      paste0("Model1=", paste(.lock_m1, collapse = "+")),
      paste0("Model2=", paste(common_cov, collapse = "+")),
      "CHARLS_Model2=", paste(common_cov, collapse = "+"),
      "ELSA_Model2=", paste(common_cov, collapse = "+"),
      "HRS_Model2=", paste(common_cov, collapse = "+")
    ), .med_lock_txt)
    cli::cli_alert_success(
      "中介/相关协变量（三库共用）: {paste(common_cov, collapse='+')}{if (length(.med_exclude_covars)) paste0('；已剔 ', paste(.med_exclude_covars, collapse='+')) else ''}"
    )
  }
  for (db in names(.med_lock$covariates_by_db %||% list())) {
    cli::cli_alert_success(
      "{db}: S6/S7 Model2 = {paste(.med_lock$covariates_by_db[[db]], collapse = '+')}"
    )
  }
}

# ── Pass 2：用锁定协变量跑图/表/中介 ─────────────────────────────────────────
# pooled-mediation-only：跳过分库 Pass2，避免冲掉已定稿 S8/S9；只用 Pass1 的 med 表合并
if (isTRUE(pooled_mediation_only)) {
  cli::cli_alert_info("pooled-mediation-only：跳过分库 Pass2（corr/中介/图），直接合并跑 Pooled 中介")
}
for (db in dbs) {
  if (isTRUE(pooled_mediation_only)) next
  cli::cli_h1("Cross-lagged figs: {db}")
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  cv_med <- .resolve_db_covars(db, for_mediation = TRUE)
  cv_tab <- .resolve_db_covars(db, for_mediation = FALSE)
  m1 <- cv_med$m1
  m2_med <- cv_med$m2
  m2_tab <- cv_tab$m2
  cli::cli_alert_info(
    "{db} corr/mediation M2={paste(m2_med, collapse='+')}; change/Table2 M2={paste(m2_tab, collapse='+')}"
  )

  ctx <- list(
    data = list(
      longitudinal = all_long[[db]],
      longitudinal_wide = all_wide[[db]],
      longitudinal_mediation = all_med[[db]],
      imputed = all_ck_data[[db]]$imputed %||% all_long[[db]],
      cleaned = all_ck_data[[db]]$cleaned %||% NULL
    ),
    results = list(
      Model1Factors = m1,
      Model2Factors = m2_tab,
      logistic_grouping_scheme = .lock_scheme,
      mediation_covars_by_db = .med_lock$covariates_by_db %||% NULL
    ),
    config = list(
      project = list(
        database = db,
        output_dir = out_dir,
        analysis_group = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        reference_group = if (exists(".circadian_index_var", inherits = TRUE)) "No_Disorder" else .ev_rg
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      incidence = list(index_var = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
      cross_lagged_corr_table = list(
        model1 = m1, model2 = m2_med,
        exposure = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI",
        mediator = .circ_med_var,
        outcome_event_level = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        exposure_label = if (exists(".circadian_index_var", inherits = TRUE)) .circ_exp_lab else "Frailty Index",
        mediator_label = .circ_med_lab,
        outcome_label = .circ_out_lab
      ),
      cross_lagged_forest_or = list(),
      cross_lagged_network = if (exists(".circadian_node_stems", inherits = TRUE)) {
        list(
          node_stems = .circadian_node_stems,
          fi_items_only = FALSE,
          include_outcome = FALSE,
          include_lipids = FALSE,
          keep_forced_nodes = TRUE,
        max_nodes = 8L
        )
      } else {
        list(fi_items_only = TRUE, include_outcome = TRUE, include_lipids = FALSE)
      },
      cross_lagged_country_year_bar = list(year_col = "Year", country_col = "Country"),
      cross_lagged_fig1_group = list(year_col = "Year"),
      cross_lagged_change_logistic = list(
        scheme = .lock_scheme,
        covariates = m2_tab,
        fi_t1 = paste0("T1_", if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
        fi_t2 = paste0("T2_", if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
        mean_section = .change_mean_lab,
        change_section = .change_chg_lab,
        file_stem = .change_stem
      ),
      mediation_longitudinal = list(
        treat = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI",
        mediator = .circ_med_var,
        mediator_transform = .circ_med_xf,
        outcome = "Disease_Group",
        outcome_event_level = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        sims = sims, seed = 40595747L,
        diagram_enable = TRUE,
        path_use_covariates = TRUE,
        covariates = setdiff(as.character(m2_med), c("Age", "SBP", "DBP", "MBP")),
        covariates_by_db = .med_lock$covariates_by_db %||% NULL,
        treat_label = .circ_exp_lab,
        mediator_label = .circ_med_lab,
        outcome_label = .circ_out_lab
      )
    )
  )
  ctx <- run_blocks_after_prepare(ctx)
  all_long[[db]] <- ctx$data$longitudinal %||% all_long[[db]]
  all_wide[[db]] <- ctx$data$longitudinal_wide %||% all_wide[[db]]
  all_med[[db]] <- ctx$data$longitudinal_mediation %||% all_med[[db]]
}

# ── Pooled（可选；交叉滞后默认关闭）──────────────────────────────────────────
if (isTRUE(run_pooled_long) && (is.null(only_dbs) || "Pooled" %in% only_dbs)) {
  cli::cli_h1("Cross-lagged figs: Pooled")
  out_dir <- file.path(study_root, "phase3_long_Pooled")
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)

  # rbind long_all / wide / med（列对齐）
  .align_bind <- function(lst) {
    lst <- lst[!vapply(lst, is.null, logical(1))]
    if (!length(lst)) return(NULL)
    cols <- Reduce(union, lapply(lst, names))
    do.call(rbind, lapply(names(lst), function(nm) {
      d <- lst[[nm]]
      for (c in setdiff(cols, names(d))) d[[c]] <- NA
      d$Cohort <- nm
      d[, unique(c(cols, "Cohort")), drop = FALSE]
    }))
  }
  long_p <- .align_bind(all_long)
  wide_p <- .align_bind(all_wide)
  med_p <- .align_bind(all_med)
  # 暴露量纲跨库不可比（如 Leisure_score CHARLS 0–11 vs ELSA 0–26）：
  # 按课题 .circadian_pooled_harmonize 在合并前做库内百分位/z，再标 Cohort=Pooled
  .treat_p <- if (exists(".circadian_index_var", inherits = TRUE)) {
    as.character(.circadian_index_var)[1L]
  } else {
    "FI"
  }
  if (!is.null(med_p) && nrow(med_p) && nzchar(.pooled_harm) &&
      !identical(.pooled_harm, "none") && .treat_p %in% names(med_p) &&
      "Cohort" %in% names(med_p)) {
    med_p[[.treat_p]] <- ave(
      suppressWarnings(as.numeric(med_p[[.treat_p]])),
      as.character(med_p$Cohort),
      FUN = function(x) cross_lagged_harmonize_exposure(x, .pooled_harm)
    )
    cli::cli_alert_info(
      "Pooled mediation: {(.treat_p)} harmonized within Cohort by {(.pooled_harm)}"
    )
  }
  # 合并表强制单一 Cohort，避免 mediation 按原子库拆分拟合
  if (!is.null(med_p) && nrow(med_p)) {
    med_p$Cohort <- "Pooled"
    if (!"Country" %in% names(med_p)) {
      # Country 应已在各库 med 表；缺则按 Cohort 名映射会在 mediation 块丢弃
      cli::cli_alert_warning("Pooled mediation: med 表缺 Country 列")
    }
  }

  # pooled flowchart summary
  flow_rows <- do.call(rbind, lapply(names(all_flow), function(nm) {
    f <- all_flow[[nm]]
    if (is.null(f)) return(NULL)
    data.frame(cohort = nm, n_final = f$n_final %||% NA, n_event = f$n_event %||% NA,
               n_drop_no_followup = f$n_drop_no_followup %||% NA, stringsAsFactors = FALSE)
  }))
  utils::write.csv(flow_rows, file.path(out_dir, "Tables/Flowchart_attrition_by_cohort.csv"), row.names = FALSE)

  cvp <- .resolve_db_covars(
    "Pooled",
    fallback_m1 = .lock_m1,
    fallback_m2 = unique(c(.lock_m2, "Country"))
  )
  m1p <- cvp$m1
  m2p <- unique(c(cvp$m2, "Country"))
  cli::cli_alert_info(
    "Pooled corr/mediation covars: M1={paste(m1p, collapse='+')}; M2={paste(m2p, collapse='+')}"
  )

  ctxp <- list(
    data = list(
      longitudinal = long_p,
      longitudinal_wide = wide_p,
      longitudinal_mediation = med_p,
      imputed = long_p
    ),
    results = list(
      Model1Factors = m1p,
      Model2Factors = m2p,
      logistic_grouping_scheme = .lock_scheme,
      mediation_covars_by_db = .med_lock$covariates_by_db %||% NULL
    ),
    config = list(
      project = list(
        database = "Pooled", output_dir = out_dir,
        analysis_group = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        reference_group = if (exists(".circadian_index_var", inherits = TRUE)) "No_Disorder" else .ev_rg
      ),
      data = list(outcome_column = "Disease_Group"),
      incidence = list(index_var = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
      cross_lagged_country_year_bar = list(year_col = "Year", country_col = "Country"),
      cross_lagged_fig1_group = list(year_col = "Year"),
      cross_lagged_network = if (exists(".circadian_node_stems", inherits = TRUE)) {
        list(
          node_stems = .circadian_node_stems,
          fi_items_only = FALSE,
          include_outcome = FALSE,
          include_lipids = FALSE,
          keep_forced_nodes = TRUE,
        max_nodes = 8L
        )
      } else {
        list()
      },
      cross_lagged_corr_table = list(
        model1 = m1p,
        model2 = m2p,
        exposure = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI",
        mediator = .circ_med_var,
        outcome_event_level = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        exposure_label = .circ_exp_lab,
        mediator_label = .circ_med_lab,
        outcome_label = .circ_out_lab
      ),
      cross_lagged_change_logistic = list(
        scheme = .lock_scheme,
        covariates = m2p
      ),
      mediation_longitudinal = list(
        treat = if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI",
        mediator = .circ_med_var,
        mediator_transform = .circ_med_xf,
        outcome = "Disease_Group",
        outcome_event_level = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag,
        sims = sims, seed = 40595747L,
        diagram_enable = TRUE,
        path_use_covariates = TRUE,
        covariates = setdiff(as.character(m2p), c("Age", "SBP", "DBP", "MBP")),
        covariates_by_db = .med_lock$covariates_by_db %||% NULL,
        treat_label = .circ_exp_lab,
        mediator_label = .circ_med_lab,
        outcome_label = .circ_out_lab
      )
    )
  )
  # build clpn wide for pooled from unit wides if possible
  if (!is.null(wide_p)) {
    stems <- unique(sub("^T1_", "", grep("^T1_", names(wide_p), value = TRUE)))
    stems <- intersect(stems, sub("^T2_", "", grep("^T2_", names(wide_p), value = TRUE)))
    demo <- c("Age", "Gender", "Education", "Marital_Status", "Smoking", "Alcohol_drinking",
              "BMI", "Weight", "Height", "Hypertension", "Disease_Group", "Year", "time")
    stems <- setdiff(stems, demo)
    stems <- unique(c(intersect(c("FI", "Frailty", "Disease01"), stems), setdiff(stems, c("FI", "Frailty", "Disease01"))))
    if (length(stems) > 30L) stems <- stems[seq_len(30L)]
    ctxp$data$longitudinal_wide_clpn <- wide_p[, intersect(
      c("ID", "Country", "Cohort", "T2_time", paste0("T1_", stems), paste0("T2_", stems)),
      names(wide_p)), drop = FALSE]
  }

  if (isTRUE(change_only)) {
    tryCatch({ ctxp <- block_cross_lagged_change_logistic(ctxp) },
             error = function(e) cli::cli_alert_warning("Pooled change: {e$message}"))
  } else if (isTRUE(pooled_mediation_only)) {
    if (!is.null(med_p) && nrow(med_p) >= 30L) {
      tryCatch({ ctxp <- block_mediation_longitudinal(ctxp) },
               error = function(e) cli::cli_alert_warning("Pooled mediation: {e$message}"))
    } else {
      cli::cli_alert_warning("Pooled mediation 跳过（med 表过小或缺失）")
    }
  } else {
    tryCatch({ ctxp <- block_cross_lagged_corr_table(ctxp) }, error = function(e) cli::cli_alert_warning("Pooled corr: {e$message}"))
    tryCatch({ ctxp <- block_cross_lagged_country_year_bar(ctxp) }, error = function(e) cli::cli_alert_warning("Pooled bar: {e$message}"))
    tryCatch({ ctxp <- block_cross_lagged_fig1_group(ctxp) }, error = function(e) cli::cli_alert_warning("Pooled fig1: {e$message}"))
    if (isTRUE(skip_network)) {
      cli::cli_alert_info("跳过 Pooled cross_lagged_network（--skip-network）")
    } else {
      tryCatch({ ctxp <- block_cross_lagged_network(ctxp) }, error = function(e) cli::cli_alert_warning("Pooled network: {e$message}"))
    }
    tryCatch({ ctxp <- block_cross_lagged_change_logistic(ctxp) }, error = function(e) cli::cli_alert_warning("Pooled change: {e$message}"))
    if (!is.null(med_p) && nrow(med_p) >= 30L) {
      tryCatch({ ctxp <- block_mediation_longitudinal(ctxp) },
               error = function(e) cli::cli_alert_warning("Pooled mediation: {e$message}"))
    }
  }

  # Table S9.2：Pooled 纵向中介（独立表，不冲 S9 分库结果）
  .pooled_med_rds <- file.path(out_dir, "Tables", "Table_Mediation_Longitudinal_pub.rds")
  if (file.exists(.pooled_med_rds) &&
      (isTRUE(pooled_mediation_only) || isTRUE(run_pooled_long))) {
    .s92_arrow <- intToUtf8(0x2192L)
    .s92_name <- paste0(
      "Table S9.2. Longitudinal mediation ",
      as.character(.circ_exp_lab %||% "Exposure")[1L], .s92_arrow,
      as.character(.circ_med_lab %||% "Mediator")[1L], .s92_arrow,
      as.character(.circ_out_lab %||% "Outcome")[1L],
      " (Pooled).xlsx"
    )
    .s92_out <- file.path(study_root, "summary_result", "table", .s92_name)
    tryCatch({
      dir.create(dirname(.s92_out), recursive = TRUE, showWarnings = FALSE)
      old_s92 <- list.files(
        dirname(.s92_out),
        pattern = "^Table S9\\.2\\. Longitudinal mediation ",
        full.names = TRUE
      )
      old_s92 <- old_s92[basename(old_s92) != basename(.s92_out)]
      if (length(old_s92)) unlink(old_s92)
      res_s92 <- cross_lagged_mediation_build_table_s7(
        .pooled_med_rds, .s92_out,
        cohorts = "Pooled",
        title = sub("\\.xlsx$", "", .s92_name)
      )
      # 脚注补充：暴露库内百分位 + Country 调整
      if (nzchar(.pooled_harm) && !identical(.pooled_harm, "none")) {
        cli::cli_alert_info(
          "S9.2 暴露口径: within-cohort {(.pooled_harm)}; covariates 含 Country"
        )
      }
      cli::cli_alert_success(
        "Table S9.2 已生成: {basename(.s92_out)}; cohorts={paste(res_s92$cohorts, collapse=', ')}"
      )
    }, error = function(e) cli::cli_alert_warning("Table S9.2 合并失败: {e$message}"))
  }

  # pooled flowchart PDF：各队列 final N 主列（发病 CONSORT 风格；汇总主文 Fig1 仍用分库三拼）
  pdf_path <- file.path(out_dir, "Figures/Figure 1-Pooled. Longitudinal inclusion exclusion flowchart.pdf")
  if (!is.null(flow_rows) && nrow(flow_rows)) {
    if (!exists("attrition_draw_pdf", mode = "function")) {
      .al <- file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), "R/attrition_log.R")
      if (!file.exists(.al)) .al <- file.path(getwd(), "R/attrition_log.R")
      if (file.exists(.al)) source(.al, local = FALSE)
    }
    draw_p <- data.frame(
      step = paste0(flow_rows$cohort, " analytic sample"),
      n = as.integer(flow_rows$n_final),
      exclude_label = NA_character_,
      step_id = paste0("cohort_", flow_rows$cohort),
      stringsAsFactors = FALSE
    )
    # 非递减纳排链：只展示各队列终局 N，禁止假 Exclude
    ok_p <- FALSE
    if (exists("attrition_draw_pdf", mode = "function") && nrow(draw_p) >= 1L) {
      # 用单队列合计一条最终框 + 脚注分队列，避免假递减
      n_sum <- sum(as.integer(flow_rows$n_final), na.rm = TRUE)
      n_ev <- sum(as.integer(flow_rows$n_event), na.rm = TRUE)
      rows1 <- data.frame(
        step = "Pooled analytic sample (CHARLS + ELSA + HRS)",
        n = as.integer(n_sum),
        exclude_label = NA_character_,
        step_id = "analytic_pooled",
        stringsAsFactors = FALSE
      )
      fn <- apply(flow_rows, 1L, function(r) {
        sprintf(
          "%s: N=%s (events=%s; drop no FU=%s)",
          r[["cohort"]],
          format(as.integer(r[["n_final"]]), big.mark = ","),
          format(as.integer(r[["n_event"]]), big.mark = ","),
          format(as.integer(r[["n_drop_no_followup"]]), big.mark = ",")
        )
      })
      ok_p <- isTRUE(tryCatch(
        attrition_draw_pdf(
          rows1,
          "Figure 1. Pooled — Inclusion / Exclusion",
          pdf_path,
          footnote = fn,
          fork = list(
            left_label = "Event",
            left_n = as.integer(n_ev),
            right_label = "No event",
            right_n = as.integer(max(0L, n_sum - n_ev))
          )
        ),
        error = function(e) FALSE
      ))
    }
    if (!isTRUE(ok_p)) {
      grDevices::pdf(pdf_path, width = 8.5, height = 8)
      graphics::plot.new()
      graphics::title("Pooled — attrition by cohort")
      txt <- apply(flow_rows, 1, function(r)
        sprintf("%s: final N=%s, events=%s, drop_no_FU=%s",
                r["cohort"], r["n_final"], r["n_event"], r["n_drop_no_followup"]))
      graphics::text(0.05, seq(0.85, 0.4, length.out = length(txt)), labels = txt, adj = 0, cex = 1.1)
      grDevices::dev.off()
    }
  }
}

# ── Table S5：自动设计（2年=two_wave；≥3年=three_plus）──────────────────────
# 合并时尽量拼上 Pooled（即使本 run 未 --with-pooled，只要盘上已有 rds）
.s5_merge_cohorts <- unique(c(.long_cohorts, "CHARLS", "ELSA", "HRS", "Pooled"))
s5_rds <- file.path(
  study_root,
  paste0("phase3_long_", .s5_merge_cohorts),
  "Tables", paste0(.change_stem, "_pub.rds")
)
s5_out <- file.path(
  study_root, "summary_result", "table",
  if (isTRUE(.change_leisure)) {
    "Table S5. Change analysis of Leisure activity score.xlsx"
  } else {
    "Table S5. Change analysis Mean FI and FI change.xlsx"
  }
)
if (!isTRUE(corr_mediation_only) && any(file.exists(s5_rds))) {
  tryCatch({
    dir.create(dirname(s5_out), recursive = TRUE, showWarnings = FALSE)
    res_s5 <- cross_lagged_change_build_table_s5(
      s5_rds, s5_out, cohorts = .s5_merge_cohorts,
      title = if (isTRUE(.change_leisure)) {
        "Table S5. Change analysis of Leisure activity score"
      } else "Table S5. Change analysis Mean FI and FI change"
    )
    cli::cli_alert_success(
      "Table S5 已生成: scheme={res_s5$scheme}; cohorts={paste(res_s5$cohorts, collapse=', ')}"
    )
  }, error = function(e) cli::cli_alert_warning("Table S5 合并失败: {e$message}"))
}

# ── Table S5.1：全库强制 two_wave（敏感性；与 S5 一并进汇总）────────────────
if (!isTRUE(corr_mediation_only)) {
cli::cli_h1("Table S5.1: force two_wave for all cohorts")
.run_change_twowave <- function(ctx_in, db_lab) {
  if (is.null(ctx_in) || is.null(ctx_in$data$longitudinal_wide)) {
    cli::cli_alert_warning("{db_lab}: 无 wide，跳过 S5.1")
    return(invisible(NULL))
  }
  ctx2 <- ctx_in
  if (is.null(ctx2$config$cross_lagged_change_logistic))
    ctx2$config$cross_lagged_change_logistic <- list()
  ctx2$config$cross_lagged_change_logistic$design <- "two_wave"
  ctx2$config$cross_lagged_change_logistic$output_suffix <- "_twowave"
  ctx2$config$cross_lagged_change_logistic$scheme <-
    ctx2$config$cross_lagged_change_logistic$scheme %||% .lock_scheme
  ctx2$config$cross_lagged_change_logistic$covariates <-
    ctx2$config$cross_lagged_change_logistic$covariates %||%
    as.character(ctx2$results$Model2Factors %||% .lock_m2)
  tryCatch({
    block_cross_lagged_change_logistic(ctx2)
  }, error = function(e) {
    cli::cli_alert_warning("{db_lab} S5.1 two_wave 失败: {e$message}")
    NULL
  })
}

# 单库：需有 longitudinal_wide；change_only 时上面已 prepare
# 重新从刚跑完的 all_wide / 或再读 phase 不现实——在循环里保存 ctx
# 若 all_wide 有值则现场构造最小 ctx
for (db in c("CHARLS", "ELSA", "HRS")) {
  if (!is.null(only_dbs) && !db %in% only_dbs) next
  wide <- all_wide[[db]]
  long <- all_long[[db]]
  if (is.null(wide)) {
    # 尝试从本轮未跑时跳过
    cli::cli_alert_warning("S5.1 {db}: 无本轮 wide（请先跑 long_prepare/change）")
    next
  }
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  ctx_tw <- list(
    data = list(longitudinal_wide = wide, longitudinal = long),
    results = list(
      Model1Factors = .lock_m1,
      Model2Factors = .lock_m2,
      logistic_grouping_scheme = .lock_scheme
    ),
    config = list(
      project = list(
        database = db, output_dir = out_dir,
        analysis_group = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag
      ),
      cross_lagged_long_prepare = list(panel = panel),
      cross_lagged_change_logistic = list(
        scheme = .lock_scheme,
        covariates = .lock_m2,
        design = "two_wave",
        output_suffix = "_twowave",
        fi_t1 = paste0("T1_", if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
        fi_t2 = paste0("T2_", if (exists(".circadian_index_var", inherits = TRUE)) .circadian_index_var else "FI"),
        mean_section = .change_mean_lab,
        change_section = .change_chg_lab,
        file_stem = .change_stem
      )
    )
  )
  .run_change_twowave(ctx_tw, db)
}

if (isTRUE(run_pooled_long) && (is.null(only_dbs) || "Pooled" %in% only_dbs) &&
    !is.null(all_wide) && length(all_wide)) {
  .align_bind2 <- function(lst) {
    lst <- lst[!vapply(lst, is.null, logical(1))]
    if (!length(lst)) return(NULL)
    cols <- Reduce(union, lapply(lst, names))
    do.call(rbind, lapply(names(lst), function(nm) {
      d <- lst[[nm]]
      for (c in setdiff(cols, names(d))) d[[c]] <- NA
      d$Cohort <- nm
      d[, unique(c(cols, "Cohort")), drop = FALSE]
    }))
  }
  wide_p2 <- .align_bind2(all_wide)
  long_p2 <- .align_bind2(all_long)
  out_dir <- file.path(study_root, "phase3_long_Pooled")
  ctx_twp <- list(
    data = list(longitudinal_wide = wide_p2, longitudinal = long_p2),
    results = list(
      Model1Factors = .lock_m1,
      Model2Factors = unique(c(.lock_m2, "Country")),
      logistic_grouping_scheme = .lock_scheme
    ),
    config = list(
      project = list(
        database = "Pooled", output_dir = out_dir,
        analysis_group = if (exists(".circadian_index_var", inherits = TRUE)) "Circadian_Disorder" else .ev_ag
      ),
      cross_lagged_change_logistic = list(
        scheme = .lock_scheme,
        covariates = unique(c(.lock_m2, "Country")),
        design = "two_wave",
        output_suffix = "_twowave"
      )
    )
  )
  .run_change_twowave(ctx_twp, "Pooled")
}

s51_rds <- file.path(
  study_root,
  paste0("phase3_long_", .s5_merge_cohorts),
  "Tables", paste0(.change_stem, "_twowave_pub.rds")
)
s51_out <- file.path(
  study_root, "summary_result", "table",
  if (isTRUE(.change_leisure)) {
    "Table S5.1. Change analysis of Leisure activity score.xlsx"
  } else {
    "Table S5.1. Change analysis Mean FI and FI change.xlsx"
  }
)
if (any(file.exists(s51_rds))) {
  tryCatch({
    dir.create(dirname(s51_out), recursive = TRUE, showWarnings = FALSE)
    res_s51 <- cross_lagged_change_build_table_s5(
      s51_rds, s51_out,
      cohorts = .s5_merge_cohorts,
      title = if (isTRUE(.change_leisure)) {
        "Table S5.1. Change analysis of Leisure activity score"
      } else "Table S5.1. Change analysis Mean FI and FI change"
    )
    cli::cli_alert_success(
      "Table S5.1 已生成: cohorts={paste(res_s51$cohorts, collapse=', ')}"
    )
  }, error = function(e) cli::cli_alert_warning("Table S5.1 合并失败: {e$message}"))
}
} # end !corr_mediation_only (S5.1)

# ── Table S6/S8：相关回归（三库合并；有 MV/VIF 槽位时写 S8）────────────────
# pooled-mediation-only：S9.2 已单独写出；勿重拼 S8/S9 以免把分库定稿冲成含 Pooled
if (isTRUE(pooled_mediation_only)) {
  cli::cli_alert_info("pooled-mediation-only：跳过 Table S8/S9 重拼（保留分库定稿）")
}
s6_rds <- file.path(
  study_root,
  paste0("phase3_long_", .long_cohorts),
  "Tables", "Table3_Correlation_Regression_pub.rds"
)
.has_mv_slots <- length(list.files(
  file.path(study_root, "summary_result", "table"),
  pattern = "^Table S5-.*Multivariable", full.names = FALSE
)) > 0L
.s6_slot <- if (isTRUE(.has_mv_slots)) "S8" else "S6"
.s6_title_core <- if (exists(".circadian_index_var", inherits = TRUE)) {
  paste(
    as.character(.circ_exp_lab %||% "Exposure")[1L],
    as.character(.circ_med_lab %||% "Mediator")[1L],
    as.character(.circ_out_lab %||% "Outcome")[1L]
  )
} else {
  "FI Depression Hip fracture"
}
.s6_fname <- paste0("Table ", .s6_slot, ". Correlation regression ", .s6_title_core, ".xlsx")
.s6_title <- paste0(
  "Table ", .s6_slot, ". Correlation regression of ",
  if (exists(".circadian_index_var", inherits = TRUE)) {
    paste(
      as.character(.circ_exp_lab)[1L], ",",
      as.character(.circ_med_lab)[1L], "and",
      as.character(.circ_out_lab)[1L]
    )
  } else {
    "Frailty Index, Depression and Hip fracture"
  }
)
s6_out <- file.path(study_root, "summary_result", "table", .s6_fname)
if (!isTRUE(pooled_mediation_only) && any(file.exists(s6_rds))) {
  tryCatch({
    dir.create(dirname(s6_out), recursive = TRUE, showWarnings = FALSE)
    # 清掉旧 FI 误标文件名，避免与 CRP 并存
    if (exists(".circadian_index_var", inherits = TRUE)) {
      old_corr <- list.files(
        dirname(s6_out),
        pattern = paste0("^Table S[68]\\. Correlation regression .*"),
        full.names = TRUE
      )
      old_corr <- old_corr[basename(old_corr) != basename(s6_out)]
      if (length(old_corr)) unlink(old_corr)
    }
    res_s6 <- cross_lagged_corr_build_table_s6(
      s6_rds, s6_out, cohorts = .long_cohorts, title = .s6_title
    )
    cli::cli_alert_success(
      "Table { .s6_slot } 已生成: cohorts={paste(res_s6$cohorts, collapse=', ')}"
    )
  }, error = function(e) cli::cli_alert_warning("Table 相关回归合并失败: {e$message}"))
}

# ── Table S7/S9：纵向中介（三库合并；有 MV/VIF 槽位时写 S9）────────────────
s7_rds <- file.path(
  study_root,
  paste0("phase3_long_", .long_cohorts),
  "Tables", "Table_Mediation_Longitudinal_pub.rds"
)
.s7_arrow <- intToUtf8(0x2192L)
.s7_slot <- if (isTRUE(.has_mv_slots)) "S9" else "S7"
.s7_name <- if (exists(".circadian_index_var", inherits = TRUE)) {
  paste0(
    "Table ", .s7_slot, ". Longitudinal mediation ",
    as.character(.circ_exp_lab %||% "Exposure")[1L], .s7_arrow,
    as.character(.circ_med_lab %||% "FI")[1L], .s7_arrow,
    as.character(.circ_out_lab %||% "Circadian disorder")[1L], ".xlsx"
  )
} else {
  paste0(
    "Table ", .s7_slot, ". Longitudinal mediation Frailty Index", .s7_arrow,
    "Depression", .s7_arrow, "Hip fracture.xlsx"
  )
}
.s7_title <- sub("\\.xlsx$", "", .s7_name)
s7_out <- file.path(study_root, "summary_result", "table", .s7_name)
if (!isTRUE(pooled_mediation_only) && any(file.exists(s7_rds))) {
  tryCatch({
    dir.create(dirname(s7_out), recursive = TRUE, showWarnings = FALSE)
    if (exists(".circadian_index_var", inherits = TRUE)) {
      old_med <- list.files(
        dirname(s7_out),
        pattern = paste0("^Table S[79]\\. Longitudinal mediation "),
        full.names = TRUE
      )
      old_med <- old_med[basename(old_med) != basename(s7_out)]
      if (length(old_med)) unlink(old_med)
    }
    res_s7 <- cross_lagged_mediation_build_table_s7(
      s7_rds, s7_out, cohorts = .long_cohorts, title = .s7_title
    )
    cli::cli_alert_success(
      "Table { .s7_slot } 已生成: cohorts={paste(res_s7$cohorts, collapse=', ')}"
    )
  }, error = function(e) cli::cli_alert_warning("Table 中介合并失败: {e$message}"))
}

cli::cli_alert_success("纵向交叉滞后完成 → phase3_long_CHARLS/ELSA/HRS")
# corr/mediation 定点返工勿整包 collect（会冲掉已 renumber 的 MV/VIF/S 号）
if (!isTRUE(corr_mediation_only) && !isTRUE(change_only)) {
  source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
} else {
  cli::cli_alert_info("跳过 auto_collect（corr-mediation-only / change-only）")
}
