#!/usr/bin/env Rscript
# Prep MIMIC dabiao: RA ∩ glucocorticoid → ASCVD incidence cohort
study <- "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157"
mimic_dir <- file.path(study, "data", "mimic")
out_dir <- file.path(study, "Data", "mimic")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(study, "Tables"), recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
rdata <- file.path(mimic_dir, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
if (!file.exists(rdata)) stop("missing baseline: ", rdata)
load(rdata, envir = e)
bl <- e$baseline
stopifnot(is.data.frame(bl), "ID" %in% names(bl))

ra <- utils::read.csv(file.path(mimic_dir, "类风湿性关节炎.csv"),
                      stringsAsFactors = FALSE, check.names = FALSE)
gc <- utils::read.csv(file.path(mimic_dir, "糖皮质激素.csv"),
                      stringsAsFactors = FALSE, check.names = FALSE)
ascvd <- utils::read.csv(file.path(mimic_dir, "动脉粥样硬化性心血管疾病.csv"),
                         stringsAsFactors = FALSE, check.names = FALSE)

bl$ID <- as.character(bl$ID)
ra$subject_id <- as.character(ra$subject_id)
gc$subject_id <- as.character(gc$subject_id)
ascvd$subject_id <- as.character(ascvd$subject_id)

n0 <- nrow(bl)
ra_ids <- unique(ra$subject_id)
n_ra <- length(intersect(ra_ids, bl$ID))

gc_use_ids <- unique(gc$subject_id[
  !is.na(gc$rxglucocorticoids) & as.integer(gc$rxglucocorticoids) == 1L
])
n_ra_gc <- length(intersect(intersect(ra_ids, gc_use_ids), bl$ID))

cohort_ids <- intersect(intersect(ra_ids, gc_use_ids), bl$ID)
ascvd_ids <- unique(ascvd$subject_id)
n_case <- length(intersect(cohort_ids, ascvd_ids))
n_ctrl <- length(cohort_ids) - n_case

mimic <- bl[bl$ID %in% cohort_ids, , drop = FALSE]
mimic$Disease_Group <- ifelse(mimic$ID %in% ascvd_ids, "ASCVD", "Non_ASCVD")
mimic$Disease_Group <- factor(mimic$Disease_Group, levels = c("Non_ASCVD", "ASCVD"))
ord <- c("ID", "Disease_Group", setdiff(names(mimic), c("ID", "Disease_Group")))
mimic <- mimic[, ord, drop = FALSE]
rownames(mimic) <- NULL

stopifnot(nrow(mimic) == length(cohort_ids))
stopifnot(as.integer(sum(mimic$Disease_Group == "ASCVD")) == n_case)

out_rdata <- file.path(out_dir, "D01_mimic_RA_GC_ASCVD.RData")
save(mimic, file = out_rdata)
save(mimic, file = file.path(mimic_dir, "D01_mimic_RA_GC_ASCVD.RData"))

attrition <- data.frame(
  step = c(
    "MIMIC-IV ICU first-stay baseline",
    "Rheumatoid arthritis (RA)",
    "RA + glucocorticoid use (rxglucocorticoids=1)",
    "Analytic cohort with ASCVD outcome labeled"
  ),
  n = c(n0, n_ra, n_ra_gc, nrow(mimic)),
  n_ASCVD = c(NA_integer_, NA_integer_, NA_integer_, n_case),
  n_Non_ASCVD = c(NA_integer_, NA_integer_, NA_integer_, n_ctrl),
  stringsAsFactors = FALSE
)
utils::write.csv(
  attrition,
  file.path(study, "Tables", "Flowchart_attrition_MIMIC.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

qc <- data.frame(
  item = c(
    "baseline_n", "RA_in_baseline", "GC_use_in_baseline",
    "cohort_RA_GC", "ASCVD_cases", "Non_ASCVD", "dabiao_path"
  ),
  value = c(
    n0, n_ra, length(intersect(gc_use_ids, bl$ID)),
    nrow(mimic), n_case, n_ctrl, out_rdata
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  qc,
  file.path(study, "Tables", "cohort_prep_qc.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)

message("=== Prep OK ===")
print(attrition)
message("Saved: ", out_rdata)
print(table(mimic$Disease_Group))
