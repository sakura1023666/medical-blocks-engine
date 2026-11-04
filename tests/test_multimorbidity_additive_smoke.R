# tests/test_multimorbidity_additive_smoke.R — 冒烟：无 proxy、非正式摘要图、敏感性规格
root <- Sys.getenv("BLOCK_REPO_ROOT", unset = normalizePath("."))
setwd(root)
options(warn = 1)

source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/color_palettes.R"), local = FALSE)
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)

smoke_rdata <- file.path(root, "Data/smoke/D01_multimorbidity_additive.RData")
stopifnot(file.exists(smoke_rdata))

out <- file.path(root, "Output/_smoke_multimorbidity_additive")
unlink(out, recursive = TRUE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)

e <- new.env()
load(smoke_rdata, envir = e)
dat <- e$Multimorbidity

config <- list(
  data = list(id_column = "ID", outcome_column = "Cognition_z"),
  project = list(output_dir = out, database = "SMOKE", name = "mm_smoke"),
  multimorbidity = list(
    obesity_indicator = "BMI",
    bmi_col = "BMI", bmi_cutoff = 28, whtr_cutoff = 0.6,
    wc_col = "WC", height_col = "Height", weight_col = "Weight",
    depression_score_col = "Depression_Score", depression_cutoff = 10,
    depression_binary_col = "Depression", obesity_binary_col = "Obesity",
    exposure_a_col = "BMI", exposure_b_col = "Depression_Score",
    category_col = "Multimorbidity_cat",
    wave_col = "Followup_wave", waves = c(1L, 2L, 3L),
    baseline_wave = 1L, outcome_wave = 3L, id_col = "ID",
    kml3d_k_candidates = 2:4, min_cluster_prop = 0.05,
    trajectory_cluster_col = "trajectory_cluster",
    cognition_raw_col = "Cognition", cognition_z_col = "Cognition_z",
    cognition_zscore = list(enable = TRUE),
    graphical_abstract = list(
      cohorts = "SMOKE", exposure_a = "BMI", exposure_b = "Depression",
      outcome = "Cognition_z"
    )
  ),
  multimorbidity_gee = list(
    outcome_col = "Cognition_z", family = "gaussian",
    time_col = "Followup_wave",
    covariates_m2 = c("Age", "Gender"),
    covariates_m3 = c("Age", "Gender", "Education"),
    stratify_vars = c("Gender"),
    ref_category = "Neither",
    sensitivity_include_ar1 = TRUE
  )
)

ctx <- list(
  config = config,
  data = list(cleaned = dat, imputed = dat),
  results = list(),
  project_root = root
)

# 直接 source 文件
srcs <- c(
  "Blocks/44_multimorbidity/05block_multimorbidity_define_exposures.R",
  "Blocks/44_multimorbidity/06block_multimorbidity_cognition_zscore.R",
  "Blocks/44_multimorbidity/01block_multimorbidity_baseline_category.R",
  "Blocks/26_trajectory/27block_trajectory_kml3d.R",
  "Blocks/44_multimorbidity/02block_multimorbidity_gee_cognition.R",
  "Blocks/44_multimorbidity/07block_multimorbidity_gee_trajectory.R",
  "Blocks/44_multimorbidity/08block_multimorbidity_sankey_transition.R",
  "Blocks/44_multimorbidity/09block_multimorbidity_empirical_transition.R",
  "Blocks/44_multimorbidity/02block_multimorbidity_gee_stratified.R",
  "Blocks/44_multimorbidity/03block_multimorbidity_gee_interaction.R",
  "Blocks/44_multimorbidity/04block_multimorbidity_sensitivity_suite.R",
  "Blocks/44_multimorbidity/10block_multimorbidity_graphical_abstract.R"
)
for (s in srcs) source(file.path(root, s), local = FALSE)

funs <- c(
  block_multimorbidity_define_exposures,
  block_multimorbidity_cognition_zscore,
  block_multimorbidity_baseline_category,
  block_multimorbidity_kml3d_trajectory,
  block_multimorbidity_gee_cognition,
  block_multimorbidity_gee_trajectory,
  block_multimorbidity_sankey_transition,
  block_multimorbidity_empirical_transition,
  block_multimorbidity_gee_stratified,
  block_multimorbidity_gee_interaction,
  block_multimorbidity_sensitivity_suite,
  block_multimorbidity_graphical_abstract
)
for (f in funs) ctx <- f(ctx)

# 验收
stopifnot("Obesity" %in% names(ctx$data$imputed))
stopifnot("Cognition_z" %in% names(ctx$data$imputed))
stopifnot("trajectory_cluster" %in% names(ctx$data$imputed))
stopifnot(!any(grepl("BMI_proxy|rnorm\\(nrow", readLines(file.path(root, "Blocks/26_trajectory/27block_trajectory_kml3d.R")))))
stopifnot(file.exists(file.path(out, "Tables", "Table_GEE_Cognition_Multimorbidity.csv")))
stopifnot(file.exists(file.path(out, "Tables", "Table_GEE_Trajectory_Multimorbidity.csv")))
sens <- utils::read.csv(file.path(out, "Tables", "Table_GEE_Sensitivity.csv"), stringsAsFactors = FALSE)
stopifnot(any(grepl("Exclude_BMI", sens$spec)))
stopifnot(any(grepl("Jackknife", sens$spec)))
ga <- file.path(out, "Figures", "graphical_abstract", "Graphical_abstract_research_process.pdf")
stopifnot(file.exists(ga))
# 非正式：不得出现在 Figures/pdf 正式 Figure 列表强命名以外即可；确认 README
stopifnot(file.exists(file.path(out, "Figures", "graphical_abstract", "README_non_formal.txt")))
formal_pdfs <- list.files(file.path(out, "Figures", "pdf"), pattern = "\\.pdf$", full.names = FALSE)
stopifnot(!any(grepl("Graphical_abstract", formal_pdfs, ignore.case = TRUE)))

message("OK: test_multimorbidity_additive_smoke passed")
