###############################################################################
#  config_environment_dkd_smoke_n100.R - 100-row smoke test (fast settings)
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()
source(file.path(.cfg_root, "configs/config_environment_dkd_batch.R"), local = FALSE)

.smoke_root <- "Output/DKD_Environment_VOC_SMOKE_n100"
.batch_project_root <- .smoke_root
.batch_ck_root      <- file.path(.smoke_root, "checkpoints")

config$data$rawdata_path <- "Data/nhanes/D03_EnvResultData_n100.RData"
config$data$rawdata_obj  <- "EnvResult"

config$project$output_dir <- .smoke_root
config$project$name       <- "DKD_Environment_VOC_SMOKE_n100"

config$environment_batch$output_base    <- .smoke_root
config$environment_batch$shared_ck_base <- file.path(.batch_ck_root, "_shared", "main")
config$environment_batch$parallel_workers <- 1L
config$environment_batch$voc_vars <- NULL

config$feishu$enable <- FALSE

config$imputation$m <- 2L
config$imputation$max_iter <- 3L

config$remove_outliers$cols <- character(0)

config$lasso_environment$univariate_enable   <- FALSE
config$lasso_environment$cv_times            <- 30L
config$lasso_environment$cv_folds            <- 5L
config$lasso_environment$freq_cutoff_method <- "fraction"
config$lasso_environment$freq_cutoff_frac   <- 0.5

config$wqs_environment$b <- 100L
config$wqs_environment$auto_select_vocs <- FALSE
config$wqs_environment$auto_select$quick_b <- 50L
config$wqs_environment$auto_select$max_trials <- 5L
config$wqs_environment$auto_select$bkmr_quick_iter <- 100L

config$bkmr_fit$iter_candidates <- c(100L, 200L)
config$bkmr_fit$auto_iter       <- FALSE
config$bkmr_fit$iter            <- 100L
config$bkmr_fit$nchains         <- 2L

config$mediation_ers_environment$sims <- 100L
config$mediation_ers_environment$compute_fi_lab <- FALSE
config$mediation_ers_environment$allow_empty_results <- TRUE
config$mediation_ers_environment$mediators <- c(
  "Uric_Acid", "Glucose", "Triglycerides", "CRP", "Albumin"
)

config$rcs_nhanes$index_var <- "URXBMA"
config$incidence$index_var  <- "URXBMA"
config$logistic$index_var   <- "URXBMA"
config$nhanes$cutoff_index_var <- "URXBMA"

pipeline$checkpoint$enable <- TRUE
pipeline_shared$checkpoint$enable <- TRUE
pipeline_tail$checkpoint$enable <- TRUE
pipeline$checkpoint$dir        <- file.path(.batch_ck_root, "full_run")
pipeline_shared$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
pipeline_tail$checkpoint$dir   <- file.path(.batch_ck_root, "_shared", "main")

pipeline$blocks <- c(
  pipeline_shared$blocks,
  "rcs_nhanes",
  pipeline_tail$blocks
)
pipeline$render_tables_after <- unique(c(
  pipeline_shared$render_tables_after,
  pipeline_tail$render_tables_after
))
pipeline$render_figures_after <- unique(c(
  pipeline_shared$render_figures_after,
  "rcs_nhanes",
  pipeline_tail$render_figures_after
))
