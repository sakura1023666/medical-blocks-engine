#!/usr/bin/env Rscript
# run/hearing_loss_uhr/prep_hearing_loss_uhr_triple.R
suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("需要 jsonlite")
})

study_root <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
# Windows 下若该路径不可用，回退：
if (!dir.exists(study_root)) {
  study_root <- "G:/02block_result/15_hearing_loss/incidence_38341157"
}
raw_dir <- file.path(study_root, "data")
out_dir <- file.path(raw_dir, "harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

load_obj <- function(path, obj) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (!exists(obj, envir = e, inherits = FALSE))
    stop("对象不存在: ", obj, " in ", path)
  e[[obj]]
}

recode_outcome <- function(x) {
  if (is.null(x)) return(NA_character_)
  if (is.numeric(x) || is.integer(x)) {
    return(ifelse(is.na(x), NA_character_,
                  ifelse(as.integer(x) == 1L, "Hearing_Loss", "Normal")))
  }
  s <- trimws(as.character(x))
  s[s %in% c("1", "Hearing Loss", "Hearing_Loss")] <- "Hearing_Loss"
  s[s %in% c("0", "Normal")] <- "Normal"
  s[!(s %in% c("Hearing_Loss", "Normal"))] <- NA_character_
  s
}

rename_if <- function(d, from, to) {
  if (from %in% names(d) && !identical(from, to)) {
    names(d)[names(d) == from] <- to
  }
  d
}

harmonize_nhanes <- function(dabiao) {
  dabiao$Disease_Group <- recode_outcome(dabiao$Disease_Group)
  dabiao <- rename_if(dabiao, "UricAcid", "Uric_Acid")
  dabiao <- rename_if(dabiao, "UreaNitrogen", "BUN")
  dabiao <- rename_if(dabiao, "PlateletCount", "Platelet_Count")
  dabiao
}

harmonize_charls <- function(dabiao) {
  if ("Disease" %in% names(dabiao)) {
    dabiao$Disease_Group <- recode_outcome(dabiao$Disease)
    dabiao$Disease <- NULL
  } else if ("Disease_Group" %in% names(dabiao)) {
    dabiao$Disease_Group <- recode_outcome(dabiao$Disease_Group)
  }
  dabiao <- rename_if(dabiao, "Uric_acid_mg_dL", "Uric_Acid")
  dabiao <- rename_if(dabiao, "Direct_HDL_Cholesterol_mg_dL", "HDL")
  dabiao <- rename_if(dabiao, "Blood_Urea_Nitrogen_mg_dL", "BUN")
  dabiao <- rename_if(dabiao, "Creatinine_refrigerated_serum_mg_dL", "Creatinine")
  dabiao <- rename_if(dabiao, "Total_Cholesterol_mg_dL", "TC")
  dabiao <- rename_if(dabiao, "Triglycerides_refrig_serum_mg_dL", "TG")
  dabiao <- rename_if(dabiao, "LDL_Cholesterol_Friedewald_mg_dL", "LDL")
  dabiao <- rename_if(dabiao, "White_blood_cell_count_1000_cells_uL", "WBC")
  dabiao <- rename_if(dabiao, "platelet_count", "Platelet_Count")
  dabiao
}

harmonize_liling <- function(dabiao) {
  ua_raw <- dabiao$UricAcid
  hdl_raw <- dabiao$HDL
  ua_mg <- ua_raw / 59.48
  hdl_mg <- ifelse(!is.na(hdl_raw) & hdl_raw > 10, hdl_raw, hdl_raw * 38.67)
  dabiao$Uric_Acid <- ua_mg
  dabiao$HDL <- hdl_mg
  dabiao$Disease_Group <- recode_outcome(dabiao$Disease_Group)
  dabiao <- rename_if(dabiao, "UreaNitrogen", "BUN")
  dabiao <- rename_if(dabiao, "PlateletCount", "Platelet_Count")
  list(
    dabiao = dabiao,
    liling_qc = data.frame(
      ua_before_median = median(ua_raw, na.rm = TRUE),
      ua_after_median = median(ua_mg, na.rm = TRUE),
      hdl_before_median = median(hdl_raw, na.rm = TRUE),
      hdl_after_median = median(hdl_mg, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  )
}

flag_ua_hdl_invalid <- function(dabiao) {
  ua <- dabiao$Uric_Acid
  hdl <- dabiao$HDL
  is.na(ua) | is.na(hdl) | ua <= 0 | hdl <= 0
}

prep_db <- function(dabiao, db_name, liling_qc = NULL) {
  n_before <- nrow(dabiao)
  dabiao <- dabiao[!is.na(dabiao$Disease_Group), , drop = FALSE]
  n_after_outcome <- nrow(dabiao)
  invalid <- flag_ua_hdl_invalid(dabiao)
  n_invalid <- sum(invalid)
  n_valid_ua_hdl <- sum(!invalid)
  n_events <- sum(dabiao$Disease_Group == "Hearing_Loss", na.rm = TRUE)

  qc_row <- data.frame(
    database = db_name,
    n_before_outcome_drop = n_before,
    n = n_after_outcome,
    n_events = n_events,
    n_ua_hdl_invalid = n_invalid,
    n_ua_hdl_valid = n_valid_ua_hdl,
    uric_acid_median = median(dabiao$Uric_Acid, na.rm = TRUE),
    hdl_median = median(dabiao$HDL, na.rm = TRUE),
    liling_ua_before_median = NA_real_,
    liling_ua_after_median = NA_real_,
    liling_hdl_before_median = NA_real_,
    liling_hdl_after_median = NA_real_,
    stringsAsFactors = FALSE
  )
  if (!is.null(liling_qc)) {
    qc_row$liling_ua_before_median <- liling_qc$ua_before_median
    qc_row$liling_ua_after_median <- liling_qc$ua_after_median
    qc_row$liling_hdl_before_median <- liling_qc$hdl_before_median
    qc_row$liling_hdl_after_median <- liling_qc$hdl_after_median
  }
  list(dabiao = dabiao, qc = qc_row, n_valid_ua_hdl = n_valid_ua_hdl)
}

# Prefer updated *_0821.RData; fall back to legacy names if absent.
resolve_raw <- function(stem) {
  cand <- c(
    file.path(raw_dir, paste0(stem, "_0821.RData")),
    file.path(raw_dir, paste0(stem, ".RData"))
  )
  hit <- cand[file.exists(cand)]
  if (!length(hit))
    stop("找不到原始数据: ", stem, " (_0821 或无后缀)")
  hit[[1L]]
}

# Align lock names with column_mapping (TC/TG → Total_Cholesterol/Triglycerides).
# Full per-DB columns are still kept; only names used for the 3-DB covariate
# intersection are standardized here.
standardize_lock_aliases <- function(d) {
  d <- rename_if(d, "TC", "Total_Cholesterol")
  d <- rename_if(d, "TG", "Triglycerides")
  d <- rename_if(d, "Smoke", "Smoking")
  d <- rename_if(d, "PlateletCount", "Platelet_Count")
  d <- rename_if(d, "NeutrophilCount", "Neutrophil_Count")
  d
}

# --- load & harmonize ---
# Option A: keep all columns per DB; only covariate_lock uses 3-DB intersection.
dabiao_n <- load_obj(resolve_raw("D04_dabiao_N_听力损失_45_69"), "dabiao")
dabiao_n <- standardize_lock_aliases(harmonize_nhanes(dabiao_n))
prep_n <- prep_db(dabiao_n, "NHANES")

dabiao_c <- load_obj(resolve_raw("D04_dabiao_C_听力损失_45_69"), "dabiao")
dabiao_c <- standardize_lock_aliases(harmonize_charls(dabiao_c))
prep_c <- prep_db(dabiao_c, "CHARLS")

dabiao_l_raw <- load_obj(resolve_raw("D04_dabiao_李玲_听力损失_45_69"), "dabiao")
liling_h <- harmonize_liling(dabiao_l_raw)
liling_h$dabiao <- standardize_lock_aliases(liling_h$dabiao)
prep_l <- prep_db(liling_h$dabiao, "Liling", liling_qc = liling_h$liling_qc)

if (prep_l$n_valid_ua_hdl < 50L) {
  stop("李玲有效 n < 50 (n_valid_ua_hdl = ", prep_l$n_valid_ua_hdl, ")")
}

dabiao_n <- prep_n$dabiao
dabiao_c <- prep_c$dabiao
dabiao_l <- prep_l$dabiao
nrow_n <- nrow(dabiao_n)
nrow_c <- nrow(dabiao_c)
nrow_l <- nrow(dabiao_l)

dabiao <- dabiao_n
save(dabiao, file = file.path(out_dir, "D04_NHANES_hearing_45_69.RData"))
dabiao <- dabiao_c
save(dabiao, file = file.path(out_dir, "D04_CHARLS_hearing_45_69.RData"))
dabiao <- dabiao_l
save(dabiao, file = file.path(out_dir, "D04_Liling_hearing_45_69.RData"))

# --- covariate lock (3-DB name intersection only; columns otherwise per-DB) ---
drop_cols <- c(
  "Disease_Group", "Disease", "Uric_Acid", "UricAcid", "HDL", "UHR",
  "ID", "SEQN", "subject_id",
  "SDMVPSU", "SDMVSTRA", "WTMEC2YR", "WTMEC4YR", "WTINT2YR",
  "WTSAF2YR", "WTSAF4YR", "new_Weight", "Source_File"
)
# Also drop survey weight / design leftovers present in any DB
drop_pat <- "^(WT|SDMV)"
covariates <- Reduce(
  intersect,
  list(names(dabiao_n), names(dabiao_c), names(dabiao_l))
)
covariates <- setdiff(covariates, drop_cols)
covariates <- covariates[!grepl(drop_pat, covariates)]
# Drop vars with miss >40% in any DB (align with imputation missing_col_threshold)
miss_drop <- character(0)
for (v in covariates) {
  rates <- c(
    mean(is.na(dabiao_n[[v]])),
    mean(is.na(dabiao_c[[v]])),
    mean(is.na(dabiao_l[[v]]))
  )
  if (any(rates > 0.4, na.rm = TRUE)) miss_drop <- c(miss_drop, v)
}
if (length(miss_drop)) {
  cat("covariate miss>40% dropped from lock: ",
      paste(miss_drop, collapse = ", "), "\n", sep = "")
  covariates <- setdiff(covariates, miss_drop)
}
covariates <- sort(covariates)

model1 <- intersect(c("Age", "Gender"), covariates)
if (length(covariates) < 3L) {
  stop("covariates 少于 3 个: ", paste(covariates, collapse = ", "))
}
if (length(setdiff(covariates, model1)) < 1L) {
  stop("除 model1 外无额外协变量")
}
model2 <- covariates
common_model_factors <- setdiff(model2, model1)

lock <- list(
  covariates = covariates,
  model1 = model1,
  model2 = model2,
  common_model_factors = common_model_factors,
  n_by_db = list(NHANES = nrow_n, CHARLS = nrow_c, Liling = nrow_l),
  created_at = as.character(Sys.time()),
  note = paste0(
    "Option A: per-DB keep all columns; Model1/2 = 3-DB column-name ",
    "intersection (excl. outcome / UHR components / IDs / weights). ",
    "Gate A keep-all via rerun_uhr_cov_lock_no_gate_a.R."
  ),
  raw_files = list(
    NHANES = basename(resolve_raw("D04_dabiao_N_听力损失_45_69")),
    CHARLS = basename(resolve_raw("D04_dabiao_C_听力损失_45_69")),
    Liling = basename(resolve_raw("D04_dabiao_李玲_听力损失_45_69"))
  )
)
jsonlite::write_json(
  lock,
  file.path(out_dir, "covariate_lock.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

prep_qc <- rbind(prep_n$qc, prep_c$qc, prep_l$qc)
write.csv(prep_qc, file.path(out_dir, "prep_qc.csv"), row.names = FALSE)

cat("Harmonized outputs written to:", out_dir, "\n")
cat("covariates (n=", length(covariates), "): ",
    paste(covariates, collapse = ", "), "\n", sep = "")
cat("n_by_db: NHANES=", nrow_n, " CHARLS=", nrow_c, " Liling=", nrow_l, "\n", sep = "")
