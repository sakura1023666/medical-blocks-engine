#!/usr/bin/env Rscript
# Blocks/54_cross_lagged_full/phases/phase_long_mediation.R
# 用一期/二期检查点 imputed + D03 随访结局 + medition 抑郁 → long_prepare → mediation_longitudinal
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
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--study-root" && i < length(args)) {
    study_root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--sims" && i < length(args)) {
    sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else i <- i + 1L
}
study_root <- .cl_pick_study_root(args, study_root %||% NULL)
if (is.null(study_root) || !nzchar(as.character(study_root)[1L])) {
  study_root <- .cl_pick_study_root(args, "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R"))
source(file.path(root, "Blocks/20_mediation/06block_mediation_longitudinal.R"))

waves <- list(
  CHARLS = list(
    dep_file = "CHARLS_2013_抑郁.csv", dep_id = "ID", dep_score = "cesd10_total",
    y_outcome_rdata = file.path(study_root, "data/CHARLS/D03_result_CHARLS_2015.RData")
  ),
  ELSA = list(
    dep_file = "ELSA_wave3_抑郁.csv", dep_id = "idauniq", dep_score = "cesd8_total",
    y_outcome_rdata = file.path(study_root, "data/ELSA/D03_result_ELSA4.RData")
  ),
  HRS = list(
    dep_file = "HRS_2014_抑郁.csv", dep_id = "HHID_PN", dep_score = "cesd8_total",
    y_outcome_rdata = file.path(study_root, "data/HRS/D03_result_HRS16.RData")
  )
)

load_imputed_ck <- function(db) {
  cdir <- file.path(study_root, paste0("phase1_", db, "_allages"), "checkpoints")
  # prefer post-VIF imputed if available
  cands <- c(
    file.path(cdir, "step09_multicollinearity_final.rds"),
    file.path(cdir, "multicollinearity_final.rds"),
    file.path(cdir, "step05_baseline_binary.rds"),
    file.path(cdir, "step03_imputation.rds"),
    file.path(cdir, "imputation.rds")
  )
  hit <- cands[file.exists(cands)][1]
  if (is.na(hit)) stop("无检查点: ", db)
  ck <- readRDS(hit)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  ck
}

all_long <- list()
options(warn = 1, cli.hyperlink = FALSE)

for (db in names(waves)) {
  cli::cli_h1("Longitudinal mediation: {db}")
  ck <- load_imputed_ck(db)
  out_dir <- file.path(study_root, paste0("phase3_long_", db))
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)

  ctx <- list(
    data = ck$data,
    results = ck$results %||% list(),
    config = list(
      project = list(
        database = db,
        output_dir = out_dir,
        analysis_group = "Hip_Fracture",
        reference_group = "No_Fracture"
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      incidence = list(index_var = "FI"),
      cross_lagged_long_prepare = list(
        medition_dir = file.path(study_root, "data/medition"),
        require_baseline_free = TRUE,
        waves = waves
      ),
      mediation_longitudinal = list(
        treat = "FI",
        mediator = "Depression_cont",
        outcome = "Disease_Group",
        outcome_event_level = "Hip_Fracture",
        covariates = intersect(
          as.character(ck$results$Model2Factors %||% c("Age", "Gender", "Education")),
          names(ck$data$imputed %||% ck$data$cleaned)
        ),
        sims = sims,
        seed = 1000L,
        diagram_enable = TRUE
      )
    )
  )

  ctx <- block_cross_lagged_long_prepare(ctx)
  lp <- ctx$results$long_prepare
  print(lp)
  ctx <- block_mediation_longitudinal(ctx)
  all_long[[db]] <- ctx$data$longitudinal_mediation
  saveRDS(ctx$results$mediation_longitudinal,
          file.path(out_dir, "mediation_longitudinal_results.rds"))
}

# optional pooled longitudinal rbind
cli::cli_h1("Pooled longitudinal mediation")
parts <- lapply(names(all_long), function(nm) {
  d <- all_long[[nm]]
  d$Country <- c(CHARLS = "China", ELSA = "UK", HRS = "America")[[nm]]
  d
})
# column intersect
common <- Reduce(intersect, lapply(parts, names))
parts <- lapply(parts, function(d) d[, common, drop = FALSE])
pooled <- do.call(rbind, parts)
pooled$Cohort <- "Pooled"
out_p <- file.path(study_root, "phase3_long_Pooled")
dir.create(file.path(out_p, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_p, "Figures"), recursive = TRUE, showWarnings = FALSE)
ctx_p <- list(
  data = list(longitudinal_mediation = pooled),
  results = list(Model2Factors = c("Age", "Gender", "Education", "Country")),
  config = list(
    project = list(database = "Pooled", output_dir = out_p, analysis_group = "Hip_Fracture"),
    data = list(outcome_column = "Disease_Group"),
    incidence = list(index_var = "FI"),
    mediation_longitudinal = list(
      treat = "FI", mediator = "Depression_cont", outcome = "Disease_Group",
      outcome_event_level = "Hip_Fracture",
      covariates = intersect(c("Age", "Gender", "Education", "Country"), names(pooled)),
      sims = sims, seed = 1000L, diagram_enable = TRUE,
      cohorts_col = "Cohort"
    )
  )
)
# force single pooled fit: set Cohort constant already Pooled — mediation loops by Cohort
# Use one label by dropping multi if only Pooled
ctx_p$data$longitudinal_mediation$Cohort <- "Pooled"
ctx_p <- block_mediation_longitudinal(ctx_p)
save(pooled, file = file.path(study_root, "data/harmonized/D05_long_mediation_Pooled.RData"))
cli::cli_alert_success("纵向中介完成。各库见 phase3_long_*/Tables/")
source(file.path(root, "Blocks/54_cross_lagged_full/phases/auto_collect_summary.inc.R"), local = FALSE)
