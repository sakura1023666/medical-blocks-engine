# S7/S8：舒张压（DBP）中介；图6仅主库；表含验证库（若有 DBP）。
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_mediation.R"), local = FALSE)
source(file.path(engine, "Blocks/20_mediation/13block_mediation_multi_db_cox.R"), local = FALSE)
pv2_ensure_dirs()
tab_dir <- pv2_tab_dir
ckpt <- pv2_ckpt_dir
fig_dir <- pv2_fig_dir
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))

# 图6：仅主库
invisible(pv2_run_mediation(
  dbs, ckpt, fig_dir, bootstrap_iter = 200L, seed = 41904528L,
  databases = pv2_primary_dbs
))

# 表：主库 + 验证库
res <- pv2_run_mediation(
  dbs, ckpt, fig_dir = NULL, bootstrap_iter = 200L, seed = 41904528L,
  databases = intersect(c(pv2_primary_dbs, pv2_validation_dbs), names(dbs))
)

# 引擎把 csv 写到 tab_dir=ckpt；再拷到 Tables
for (f in c("Table mediation cox.csv", "Table mediation correlation.csv")) {
  src <- file.path(ckpt, f)
  if (file.exists(src)) file.copy(src, file.path(tab_dir, f), overwrite = TRUE)
}

dbs_out <- unique(as.character(res$mediation$database))
mediation_multi_db_write_xlsx(
  res, tab_dir,
  databases = dbs_out,
  corr_title = "Table S7. Correlation between sleep duration and other indicators",
  med_title = "Table S8. Mediation analysis",
  corr_filename = function(db) sprintf(
    "Table S7-%s. Correlation between sleep duration and other indicators.xlsx", db
  ),
  med_filename = function(db) sprintf("Table S8-%s. Mediation analysis.xlsx", db),
  corr_footnotes = c(
    "The Crude Model was non-adjusted.",
    "The Model 1 was adjusted by: Age.",
    "The Model 2 was adjusted by: Age, Gender.",
    "The outcome of each linear model is sleep duration. Diastolic blood pressure is standardized to 1 SD.",
    "Lipids are not used. The cohort is already restricted to dyslipidemia.",
    "Primary cohorts: NHANES, SHHS. CHARLS is external validation and is not used to select the mediator."
  ),
  med_footnotes = c(
    "Path models are unweighted Cox models, including in NHANES. They are not the survey-weighted Cox models in Table 3.",
    "The mediator is diastolic blood pressure (DBP), standardized to 1 SD.",
    "Path models were unadjusted (no covariates). In pre-specified screening, paths a, b and c were significant in both primary cohorts without covariates; adding Age removed joint significance.",
    "Path a is the linear coefficient of sleep duration on standardized DBP. Path b and the direct effect are Cox log-hazard coefficients.",
    "The path diagram uses diastolic blood pressure.",
    "A negative proportion mediated indicates suppression, not a mediated fraction.",
    "Lipids are not used. The cohort is already restricted to dyslipidemia.",
    "Primary cohorts: NHANES, SHHS. CHARLS is external validation."
  )
)
message("done S7/S8 DBP; databases=", paste(dbs_out, collapse = ","))
