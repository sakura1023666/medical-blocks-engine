#!/usr/bin/env Rscript
# 重跑 Table S3（性别）/ S4（年龄65）分层 ExWAS，强制与主文锁定 Model2 同协变量：
# Gender, Race, PIR_cat, Alcohol_drinking, eGFR
# 性别层内去掉 Gender；年龄层内去掉 Age（Age 本就不在锁定 Model2）
# 随后重建 Dong 宽表 + 无图注 Fig3
#
#   Rscript run/environment_exwas/align_pancancer_s34_model2.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L,
  age_cut = 65L
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))
source(file.path(repo, "run/environment_exwas/pancancer_model2_covars.R"))

root <- opt$root
age_cut <- as.integer(opt$age_cut)
tab_dir <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
exwas_log <- function(...) message("[align-s34] ", paste0(..., collapse = ""))

covars_m2 <- pancancer_model2_covars_from_path(root)
exwas_log("Model2=", paste(covars_m2, collapse = "+"))

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, , drop = FALSE]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
need <- unique(c(covars_m2, "Gender", "Age", "DN"))
df <- exwas_aligned_as_model_frame(df, intersect(need, names(df)))
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
df$Age_num <- exwas_to_num(df$Age)
exwas_log("N=", nrow(df), " exp=", length(scr$keep))

fam_df <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  ifelse(is.na(x) | !nzchar(as.character(x)), raw, x)
}

run_stratum <- function(idx, name, covars) {
  if (length(idx) < 100L) return(NULL)
  sub <- df[idx, , drop = FALSE]
  covars <- intersect(covars, names(sub))
  one <- exwas_run_unweighted(sub, "DN", scr$keep, covars)
  one$stratum <- name
  one$n_stratum <- nrow(sub)
  one$n_events <- sum(sub$DN == 1, na.rm = TRUE)
  raw <- sub("_(ln|bin)$", "", one$exposure)
  one$exposure_name <- disp_of(raw)
  one$family <- unname(fam_map[raw])
  one$family[is.na(one$family) | !nzchar(as.character(one$family))] <- "Other"
  one
}

# Sex
g <- as.character(df$Gender)
idx_m <- which(grepl("^[Mm]", g) | g %in% c("1", "Male"))
idx_f <- which(grepl("^[Ff]", g) | g %in% c("2", "Female"))
if (!length(idx_m) || !length(idx_f)) {
  # factor codes
  ug <- unique(stats::na.omit(g))
  exwas_log("Gender levels: ", paste(ug, collapse = "|"))
}
cov_sex <- setdiff(covars_m2, "Gender")
exwas_log("Sex Male n=", length(idx_m), " Female n=", length(idx_f),
          " covars=", paste(cov_sex, collapse = "+"))
st_m <- run_stratum(idx_m, "Male", cov_sex)
st_f <- run_stratum(idx_f, "Female", cov_sex)
st_sex <- rbind(st_m, st_f)
utils::write.csv(st_sex, file.path(tab_dir, "Table S3. ExWAS stratified by sex_long.bak.csv"), row.names = FALSE)
utils::write.csv(st_sex, file.path(tab_dir, "Table S3. ExWAS stratified by sex.csv"), row.names = FALSE)
exwas_log("S3 long rows=", nrow(st_sex))

# Age
lab_lt <- paste0("Age_lt", age_cut)
lab_ge <- paste0("Age_ge", age_cut)
idx_lt <- which(is.finite(df$Age_num) & df$Age_num < age_cut)
idx_ge <- which(is.finite(df$Age_num) & df$Age_num >= age_cut)
cov_age <- setdiff(covars_m2, "Age")
exwas_log("Age <", age_cut, " n=", length(idx_lt), " >=", age_cut, " n=", length(idx_ge),
          " covars=", paste(cov_age, collapse = "+"))
st_lt <- run_stratum(idx_lt, lab_lt, cov_age)
st_ge <- run_stratum(idx_ge, lab_ge, cov_age)
st_age <- rbind(st_lt, st_ge)
utils::write.csv(st_age, file.path(tab_dir, "Table S4. ExWAS stratified by age_long.bak.csv"), row.names = FALSE)
utils::write.csv(st_age, file.path(tab_dir, "Table S4. ExWAS stratified by age.csv"), row.names = FALSE)
exwas_log("S4 long rows=", nrow(st_age))

# rebuild display tables
exwas_log("rebuild S3/S4 display xlsx")
system2("Rscript", file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s3_dong_style.R"))
system2("Rscript", file.path(repo, "run/environment_exwas/rebuild_pancancer_table_s4_dong_style.R"))
exwas_log("DONE — then redraw Fig3 without titles from long.bak")
