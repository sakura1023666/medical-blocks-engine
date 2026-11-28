#!/usr/bin/env Rscript
###############################################################################
# build_multimorbidity_panels.R — 三库结局主件 ∪ 基线 → 分析 long 面板
# 用法:
#   Rscript run/multimorbidity/scripts/build_multimorbidity_panels.R
#   Rscript ... --cohort CHARLS [--hrs-mode mean|early|late]
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
.root_candidates <- c(
  normalizePath(getwd(), winslash = "/", mustWork = FALSE),
  "E:/01block/01Block",
  "/mnt/e/01block/01Block"
)
root <- NA_character_
for (cand in .root_candidates) {
  if (file.exists(file.path(cand, "R", "pipeline_runner.R"))) {
    root <- cand
    break
  }
}
if (is.na(root)) stop("Cannot locate 01Block root", call. = FALSE)
setwd(root)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !(length(a) == 1 && is.na(a))) a else b

.opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
only_cohort <- toupper(trimws(.opt("--cohort", "ALL")))
hrs_mode <- tolower(trimws(.opt("--hrs-mode", "mean")))

data_root <- file.path(root, "Data", "multimorbidity_04298")
out_dir <- file.path(data_root, "panels")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
attr_dir <- file.path(out_dir, "attrition")
dir.create(attr_dir, recursive = TRUE, showWarnings = FALSE)

.read_csv_utf8 <- function(path) {
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                  fileEncoding = "UTF-8-BOM", na.strings = c("", "NA", "NaN"))
}

.find_main <- function(cohort, pheno, hrs_mode = "mean") {
  base <- file.path(data_root, cohort, pheno)
  if (identical(cohort, "HRS") && hrs_mode %in% c("early", "late") &&
      pheno %in% c("抑郁", "认知")) {
    sub <- if (identical(hrs_mode, "early")) "早波" else "晚波"
    hits <- list.files(file.path(base, sub), pattern = "纵向主件_.*\\.csv$", full.names = TRUE)
    if (length(hits)) return(hits[[1L]])
  }
  hits <- list.files(base, pattern = "纵向主件_.*\\.csv$", full.names = TRUE)
  hits <- hits[!grepl("/早波/|/晚波/", hits)]
  if (!length(hits)) stop("缺纵向主件: ", cohort, "/", pheno, call. = FALSE)
  hits[[1L]]
}

.load_baseline <- function(cohort) {
  bf <- switch(
    cohort,
    CHARLS = "D01_baseline_CHARLS_2011_1028_1427.RData",
    ELSA = "D01_baseline_ELSA2_2004_1028_1448.RData",
    HRS = "D01_baseline_HRS_2006_1028_1513.RData",
    stop("unknown cohort")
  )
  e <- new.env(parent = emptyenv())
  load(file.path(data_root, "baseline", bf), envir = e)
  bl <- e$baseline
  if (is.null(bl)) bl <- e[[ls(e)[1L]]]
  bl
}

.wave_map <- function(cohort) {
  if (identical(cohort, "CHARLS")) {
    return(list(labels = c("2011", "2013", "2015"), waves = c(1L, 2L, 3L),
                bmi_cut = 28, dep_cut = 10, dep_score_pat = "cesd10_std"))
  }
  if (identical(cohort, "ELSA")) {
    return(list(labels = c("2004", "2008", "2012", "2016"), waves = c(1L, 2L, 3L, 4L),
                bmi_cut = 30, dep_cut = 4, dep_score_pat = "cesd8_std"))
  }
  # HRS pseudo-waves
  list(labels = c("2006-2008", "2010-2012", "2014-2016"), waves = c(1L, 2L, 3L),
       bmi_cut = 30, dep_cut = 4, dep_score_pat = "cesd_std")
}

.pick_col <- function(nms, stem, label) {
  cand <- paste0(stem, "_", label)
  if (cand %in% nms) return(cand)
  # HRS labels already contain hyphen
  NA_character_
}

.wide_to_long_core <- function(wide, id_col = "ID", labels, waves, specs) {
  # specs: named list of output_col = stem
  rows <- list()
  for (i in seq_along(labels)) {
    lab <- labels[[i]]
    w <- waves[[i]]
    piece <- data.frame(ID = as.character(wide[[id_col]]), Followup_wave = w,
                        stringsAsFactors = FALSE)
    for (out_nm in names(specs)) {
      stem <- specs[[out_nm]]
      cn <- paste0(stem, "_", lab)
      if (cn %in% names(wide)) {
        piece[[out_nm]] <- suppressWarnings(as.numeric(wide[[cn]]))
      } else {
        piece[[out_nm]] <- NA_real_
      }
    }
    rows[[length(rows) + 1L]] <- piece
  }
  do.call(rbind, rows)
}

.norm_factor01 <- function(x) {
  if (is.null(x)) return(NA_integer_)
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x)) return(as.integer(x > 0))
  xl <- tolower(trimws(as.character(x)))
  ifelse(xl %in% c("1", "yes", "y", "true"), 1L,
         ifelse(xl %in% c("0", "no", "n", "false"), 0L, NA_integer_))
}

.build_one <- function(cohort, hrs_mode = "mean") {
  meta <- .wave_map(cohort)
  labels <- meta$labels
  waves <- meta$waves

  obesity <- .read_csv_utf8(.find_main(cohort, "肥胖", hrs_mode))
  abdo <- .read_csv_utf8(.find_main(cohort, "腹型肥胖", hrs_mode))
  dep <- .read_csv_utf8(.find_main(cohort, "抑郁", hrs_mode))
  cog <- .read_csv_utf8(.find_main(cohort, "认知", hrs_mode))
  names(obesity)[1] <- "ID"
  names(abdo)[1] <- "ID"
  names(dep)[1] <- "ID"
  names(cog)[1] <- "ID"
  .norm_id <- function(x, cohort) {
    x <- gsub("^\\s+|\\s+$", "", as.character(x))
    x <- sub("\\.0$", "", x)
    if (identical(cohort, "CHARLS")) {
      # baseline 12 位前导零；主件可能 11 位
      nc <- nchar(x)
      need <- pmax(0L, 12L - nc)
      x <- paste0(vapply(need, function(n) paste(rep("0", n), collapse = ""), character(1)), x)
    }
    x
  }
  obesity$ID <- .norm_id(obesity$ID, cohort)
  abdo$ID <- .norm_id(abdo$ID, cohort)
  dep$ID <- .norm_id(dep$ID, cohort)
  cog$ID <- .norm_id(cog$ID, cohort)

  long_ob <- .wide_to_long_core(
    obesity, labels = labels, waves = waves,
    specs = list(BMI = "bmi_calc", Height_m = "mheight_m", Weight = "mweight_kg",
                 Obesity_DN = "DN")
  )
  long_ao <- .wide_to_long_core(
    abdo, labels = labels, waves = waves,
    specs = list(WC = "mwaist_cm", Height_cm = "height_cm", WHtR = "whtr_calc",
                 AO_DN = "DN")
  )
  # depression score stem differs
  dep_stem <- meta$dep_score_pat
  long_dep <- .wide_to_long_core(
    dep, labels = labels, waves = waves,
    specs = list(Depression_Score = dep_stem, Depression_DN = "DN")
  )
  long_cog <- .wide_to_long_core(
    cog, labels = labels, waves = waves,
    specs = list(Cognition_z = "z_global", Cognition_DN = "DN",
                 Cognition_z_avg = "z_avg")
  )

  long <- Reduce(function(a, b) merge(a, b, by = c("ID", "Followup_wave"), all = TRUE),
                 list(long_ob, long_ao, long_dep, long_cog))

  # Height in cm for downstream WHtR/BMI helpers
  long$Height <- ifelse(!is.na(long$Height_cm), long$Height_cm,
                        ifelse(!is.na(long$Height_m), long$Height_m * 100, NA_real_))

  bl <- .load_baseline(cohort)
  bl$ID <- .norm_id(bl$ID, cohort)
  cov_keep <- intersect(
    c("ID", "Age", "Gender", "Race", "Education", "Marital_Status", "Residence",
      "Smoke", "Alcohol_drinking", "Hypertension", "Diabetes", "Malignant_Tumor",
      "Stroke", "Rheumatic_Diseases", "Amnesia", "Incometotal",
      "Family_per_capita_consumption", "Psychiatric"),
    names(bl)
  )
  bl_small <- bl[, cov_keep, drop = FALSE]
  # rename for pipeline
  if ("Marital_Status" %in% names(bl_small)) names(bl_small)[names(bl_small) == "Marital_Status"] <- "Marital"
  if ("Alcohol_drinking" %in% names(bl_small)) names(bl_small)[names(bl_small) == "Alcohol_drinking"] <- "Alcohol"
  if ("Malignant_Tumor" %in% names(bl_small)) names(bl_small)[names(bl_small) == "Malignant_Tumor"] <- "Cancer"
  if ("Rheumatic_Diseases" %in% names(bl_small)) names(bl_small)[names(bl_small) == "Rheumatic_Diseases"] <- "Arthritis"

  n0 <- length(unique(long$ID))
  long <- merge(long, bl_small, by = "ID", all.x = TRUE)

  # Age_group for stratified GEE
  long$Age_group <- ifelse(suppressWarnings(as.numeric(long$Age)) >= 65, ">=65", "<65")

  # Economic tertile if income-like available
  econ_col <- if ("Family_per_capita_consumption" %in% names(long)) {
    "Family_per_capita_consumption"
  } else if ("Incometotal" %in% names(long)) {
    "Incometotal"
  } else {
    NULL
  }
  if (!is.null(econ_col)) {
    v <- suppressWarnings(as.numeric(long[[econ_col]]))
    # tertile on baseline wave only then propagate — simple: person-level from baseline row
    base_ids <- long$Followup_wave == min(waves)
    qq <- stats::quantile(v[base_ids], probs = c(1 / 3, 2 / 3), na.rm = TRUE)
    long$Economic <- cut(v, breaks = c(-Inf, qq[1], qq[2], Inf),
                         labels = c("Low", "Mid", "High"))
  }

  attrition <- data.frame(
    step = character(), n_id = integer(), n_row = integer(), note = character(),
    stringsAsFactors = FALSE
  )
  .push <- function(step, dat, note = "") {
    attrition <<- rbind(
      attrition,
      data.frame(step = step, n_id = length(unique(dat$ID)), n_row = nrow(dat),
                 note = note, stringsAsFactors = FALSE)
    )
  }
  .push("00_merged_phenotype_pool", long, "四表型∪基线全并")

  # age >= 45 at baseline
  base_w <- min(waves)
  base_age <- long[long$Followup_wave == base_w, c("ID", "Age"), drop = FALSE]
  keep_age <- base_age$ID[is.finite(suppressWarnings(as.numeric(base_age$Age))) &
                            as.numeric(base_age$Age) >= 45]
  # if Age missing for many, keep those with missing age but flag
  miss_age_ids <- base_age$ID[is.na(base_age$Age)]
  keep_age <- unique(c(keep_age, miss_age_ids))
  long <- long[long$ID %in% keep_age, , drop = FALSE]
  .push("01_age_ge_45_or_age_missing", long, "基线 Age>=45（Age 缺失暂保留）")

  # cognitive disease exclusion when column present
  if ("Amnesia" %in% names(long)) {
    am <- .norm_factor01(long$Amnesia[long$Followup_wave == base_w])
    bad <- unique(long$ID[long$Followup_wave == base_w][!is.na(am) & am == 1L])
    long <- long[!long$ID %in% bad, , drop = FALSE]
    .push("02_exclude_amnesia_CHARLS", long, paste0("排除 Amnesia=", length(bad)))
  }

  # Complete-case (文献口径近似):
  # - 基线波 BMI+抑郁+认知z 齐全
  # - 至少 1 个随访波三者齐全（不强制必须是最后一波）
  # - 轨迹分析另要求 ≥2（含基线）完整波；此处一并纳入主分析面板
  outcome_w <- max(waves)
  req_ok <- function(df) {
    is.finite(df$BMI) & is.finite(df$Depression_Score) & is.finite(df$Cognition_z)
  }
  id_base_ok <- unique(long$ID[long$Followup_wave == base_w & req_ok(long)])
  id_fu_ok <- unique(long$ID[long$Followup_wave > base_w & req_ok(long)])
  ids_bo <- intersect(id_base_ok, id_fu_ok)
  tab <- as.data.frame(table(long$ID[req_ok(long)]))
  names(tab) <- c("ID", "n_ok")
  ids_traj <- as.character(tab$ID[tab$n_ok >= 2L])
  ids_cc <- intersect(ids_bo, ids_traj)
  long_cc <- long[long$ID %in% ids_cc, , drop = FALSE]
  .push("03_complete_case_BMI_path", long_cc,
        "基线+≥1随访波 BMI/抑郁/认知z 齐全")

  req_ao <- function(df) {
    is.finite(df$WHtR) & is.finite(df$Depression_Score) & is.finite(df$Cognition_z)
  }
  long_ao_src <- long_cc
  if (identical(cohort, "ELSA")) {
    long_ao_src <- long_ao_src[long_ao_src$Followup_wave %in% c(1L, 2L, 3L), , drop = FALSE]
  }
  id_b <- unique(long_ao_src$ID[long_ao_src$Followup_wave == base_w & req_ao(long_ao_src)])
  id_o <- unique(long_ao_src$ID[long_ao_src$Followup_wave > base_w & req_ao(long_ao_src)])
  tab2 <- as.data.frame(table(long_ao_src$ID[req_ao(long_ao_src)]))
  names(tab2) <- c("ID", "n_ok")
  ids_whtr <- intersect(intersect(id_b, id_o), as.character(tab2$ID[tab2$n_ok >= 2L]))
  long_cc$WHtR_analysis_eligible <- as.integer(long_cc$ID %in% ids_whtr)
  .push("04_WHtR_eligible_flag", long_cc[long_cc$ID %in% ids_whtr, , drop = FALSE],
        "WHtR 完整病例子集")

  # Exposure_a continuous aliases already BMI/WHtR
  long_cc$Cohort <- cohort
  long_cc$hrs_mode <- if (identical(cohort, "HRS")) hrs_mode else NA_character_

  list(data = long_cc, attrition = attrition, meta = meta,
       n_bmi = length(unique(long_cc$ID)),
       n_whtr = length(ids_whtr))
}

cohorts <- if (identical(only_cohort, "ALL")) c("CHARLS", "ELSA", "HRS") else only_cohort
summary_rows <- list()

for (co in cohorts) {
  mode <- if (identical(co, "HRS")) hrs_mode else "mean"
  message("Building panel: ", co, " hrs_mode=", mode)
  res <- .build_one(co, hrs_mode = mode)
  Multimorbidity <- res$data
  attr_path <- file.path(attr_dir, paste0("attrition_", co, if (identical(co, "HRS") && !identical(mode, "mean")) paste0("_", mode) else "", ".csv"))
  utils::write.csv(res$attrition, attr_path, row.names = FALSE, fileEncoding = "UTF-8")

  suffix <- if (identical(co, "HRS") && !identical(mode, "mean")) paste0("_", mode) else ""
  out_rdata <- file.path(out_dir, paste0("D01_panel_", co, suffix, ".RData"))
  save(Multimorbidity, file = out_rdata)
  message("  wrote ", out_rdata, " n_id_BMI=", res$n_bmi, " n_id_WHtR=", res$n_whtr,
          " n_row=", nrow(Multimorbidity))

  summary_rows[[length(summary_rows) + 1L]] <- data.frame(
    cohort = co, hrs_mode = mode, n_bmi = res$n_bmi, n_whtr = res$n_whtr,
    n_row = nrow(Multimorbidity), file = basename(out_rdata),
    lit_n = switch(co, CHARLS = 8286L, ELSA = 5225L, HRS = 10849L, NA_integer_),
    stringsAsFactors = FALSE
  )
}

sum_df <- do.call(rbind, summary_rows)
utils::write.csv(sum_df, file.path(out_dir, "panel_summary.csv"), row.names = FALSE)
print(sum_df)
message("Done. Panels in ", out_dir)
