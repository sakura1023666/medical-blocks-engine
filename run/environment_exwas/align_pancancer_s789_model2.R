#!/usr/bin/env Rscript
# 将 S7/S8/S9 协变量对齐为 DAG→UV→VIF→stepwise 终末集，并重导 Dong 版式表
#
#   Rscript run/environment_exwas/align_pancancer_s789_model2.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
setwd(ROOT)
source("R/utils.R")
source("R/environment_exwas_core.R")
source("R/environment_exwas_aligned.R")
source("R/environment_exwas_toxicant.R")
source("run/environment_exwas/pancancer_model2_covars.R")

opt <- list(data_dir = file.path(BASE, "data"), min_age = 20L)
src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, ]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, ]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
covars_m2 <- intersect(pancancer_model2_covars_from_path(BASE), names(df))
if (!length(covars_m2)) covars_m2 <- intersect(pancancer_model2_final_default, names(df))
df <- exwas_aligned_as_model_frame(df, unique(c(covars_m2, "Smoke")))
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
if (!"SDMVSTRA_cyc" %in% names(df) && "SDMVSTRA" %in% names(df)) {
  df$SDMVSTRA_cyc <- df$SDMVSTRA
}
exwas_log <- function(...) message("[align-s789] ", paste0(..., collapse = ""))
exwas_log("Model2=", paste(covars_m2, collapse = "+"), " n=", nrow(df), " exp=", length(scr$keep))

fam_df <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  ifelse(is.na(x) | !nzchar(x), raw, x)
}

# ---- S7 survey mice ----
wmap <- stats::setNames(rep("WTSA2YR", length(scr$keep)), scr$keep)
exwas_log("S7 survey mice …")
s7_fit <- exwas_run_survey_mice(
  df, "DN", scr$keep, covars_m2, weight_map = wmap,
  families = NULL, energy_col = NULL, diet_impute_cols = NULL,
  m = 5L, maxit = 5L, seed = 123456L,
  psu = "SDMVPSU", strata = "SDMVSTRA_cyc"
)
s7 <- s7_fit$table
s7$exposure_raw <- sub("_(ln|bin)$", "", s7$exposure)
s7$exposure_name <- disp_of(s7$exposure_raw)
s7$family <- unname(fam_map[s7$exposure_raw])
s7$q <- exwas_fdr(s7$p)
utils::write.csv(s7, file.path(src_tab, "Table S7. ExWAS survey-weighted.csv"), row.names = FALSE)
exwas_log("S7 FDR hits=", sum(is.finite(s7$q) & s7$q < 0.05))

# ---- S8 + Smoke ----
if ("Smoke" %in% names(df)) {
  cov_smoke <- unique(c(covars_m2, "Smoke"))
  exwas_log("S8 +Smoke …")
  s8 <- exwas_run_unweighted(df, "DN", scr$keep, cov_smoke)
  s8$q <- exwas_fdr(s8$p)
  s8$exposure_name <- disp_of(sub("_(ln|bin)$", "", s8$exposure))
  s8$family <- unname(fam_map[sub("_(ln|bin)$", "", s8$exposure)])
  utils::write.csv(s8, file.path(src_tab, "Table S8. ExWAS additional Smoke adjustment.csv"), row.names = FALSE)

  sm <- as.character(df$Smoke)
  never <- grepl("Never|never|从不", sm, ignore.case = TRUE)
  exwas_log("S9 never-smokers n=", sum(never))
  if (sum(never) >= 200L) {
    s9 <- exwas_run_unweighted(df[never, , drop = FALSE], "DN", scr$keep, covars_m2)
    s9$q <- exwas_fdr(s9$p)
    s9$exposure_name <- disp_of(sub("_(ln|bin)$", "", s9$exposure))
    s9$family <- unname(fam_map[sub("_(ln|bin)$", "", s9$exposure)])
    s9$n_stratum <- sum(never)
    s9$n_events <- sum(df$DN[never] == 1, na.rm = TRUE)
    utils::write.csv(s9, file.path(src_tab, "Table S9. ExWAS among never-smokers.csv"), row.names = FALSE)
  }
}

exwas_log("Dong-style display rebuild …")
sys_ok <- function(cmd) {
  message("[align-s789] ", cmd)
  st <- system(cmd)
  if (!identical(st, 0L)) warning("command failed: ", cmd)
}
sys_ok("Rscript run/environment_exwas/rebuild_pancancer_table_s7_dong_style.R")
sys_ok("Rscript run/environment_exwas/rebuild_pancancer_table_s8_dong_style.R")
sys_ok("Rscript run/environment_exwas/rebuild_pancancer_table_s9_dong_style.R")
exwas_log("DONE")
