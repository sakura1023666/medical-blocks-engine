# refit_gpr_new_rubin_models.R — 仅重跑 Models123（含 Rubin）+ death + 写表
root <- Sys.getenv("BLOCK_REPO_ROOT", "/mnt/e/01block/01Block-new-Final")
unit_dir <- "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/by_unit/GPR[new]"
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/mi_rubin_pool.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "Blocks/55_competing_risk_full/09block_competing_models_123.R"))
source(file.path(root, "Blocks/55_competing_risk_full/16block_competing_models_123_death.R"))

ck <- file.path(unit_dir, "checkpoints", "competing_mixed_cox.rds")
stopifnot(file.exists(ck))
obj <- readRDS(ck)
ctx <- obj$ctx
stopifnot(length(ctx$results$mice_row_ids) == nrow(ctx$results$mice_model$data))
ctx$config$project$output_dir <- unit_dir
ctx$config$imputation$rubin_pool <- TRUE
message("rubin_enabled=", mi_rubin_enabled(ctx), " n_ids=", length(ctx$results$mice_row_ids))

ctx <- block_competing_models_123(ctx)
message("AKI models done")
ctx <- block_competing_models_123_death(ctx)
message("death models done")

# quick check
aki <- read.csv(file.path(unit_dir, "Tables", "Table_Models_123_GPR_quartile_AKI.csv"))
message("mi_pool table: ", paste(names(table(aki$mi_pool)), collapse = ","))
print(table(aki$mi_pool, useNA = "ifany"))
print(table(aki$mi_m, useNA = "ifany"))
message("OK refit")
