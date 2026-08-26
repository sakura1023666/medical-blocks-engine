#!/usr/bin/env Rscript
# TDD: ip_cohort_sle_aki — 10 baseline ∩ 5 SLE → nrow==5；纳排表列；ARF 结局
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)

block_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R")
if (file.exists(block_src)) source(block_src, local = FALSE)
stopifnot(exists("block_ip_cohort_sle_aki"))

.ip_write_fake <- function(td, bl, sle, arf) {
  e <- new.env(parent = emptyenv())
  e$baseline <- bl
  bl_path <- file.path(td, "baseline.RData")
  save(list = "baseline", file = bl_path, envir = e)
  sle_path <- file.path(td, "SLE.csv")
  arf_path <- file.path(td, "ARF.csv")
  utils::write.csv(sle, sle_path, row.names = FALSE)
  utils::write.csv(arf, arf_path, row.names = FALSE)
  list(baseline_path = bl_path, sle_path = sle_path, arf_path = arf_path)
}

.ip_make_ctx <- function(paths, extra = list()) {
  cfg <- c(
    list(
      baseline_path = paths$baseline_path,
      baseline_obj = "baseline",
      sle_path = paths$sle_path,
      arf_path = paths$arf_path,
      baseline_id_col = "ID",
      aki_window_note = "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv)"
    ),
    extra
  )
  list(
    config = list(ip_two_stage = cfg),
    data = list(),
    results = list()
  )
}

# --- 最小：10 人 baseline ∩ 5 SLE → nrow==5 ---
td <- tempfile("ip_cohort_")
dir.create(td)
bl <- data.frame(
  ID = 1:10,
  Age = c(40, 50, 60, 70, 45, 30, 22, 80, 33, 41),
  stringsAsFactors = FALSE
)
sle <- data.frame(subject_id = 1:5, stringsAsFactors = FALSE)
arf <- data.frame(subject_id = c(1L, 2L, 3L), stringsAsFactors = FALSE)
paths <- .ip_write_fake(td, bl, sle, arf)
ctx <- block_ip_cohort_sle_aki(.ip_make_ctx(paths))
stopifnot(nrow(ctx$data$raw) == 5L)
stopifnot(identical(sort(as.integer(ctx$data$raw$ID)), 1:5))
stopifnot("Disease" %in% names(ctx$data$raw))
stopifnot("Acute_Renal_Failure" %in% names(ctx$data$raw))
stopifnot(identical(as.integer(sum(ctx$data$raw$Disease == 1L, na.rm = TRUE)), 3L))

att <- ctx$results$ip_attrition_steps
stopifnot(is.data.frame(att))
need_cols <- c("step", "n_in", "n_out", "n_excluded", "reason")
stopifnot(all(need_cols %in% names(att)))
stopifnot("baseline_icu" %in% att$step)
stopifnot("intersect_SLE" %in% att$step)
sle_row <- att[att$step == "intersect_SLE", , drop = FALSE]
stopifnot(nrow(sle_row) == 1L)
stopifnot(identical(as.integer(sle_row$n_out[[1L]]), 5L))
stopifnot(identical(as.integer(sle_row$n_in[[1L]]), 10L))
stopifnot(identical(as.integer(sle_row$n_excluded[[1L]]), 5L))
stopifnot(identical(as.character(ctx$results$ip_aki_window_note),
                    "ICU stay ARF/AKI (Acute_Renal_Failure or ARF.csv)"))

# --- Age < 18 从 SLE 交集中剔除 ---
td2 <- tempfile("ip_cohort_age_")
dir.create(td2)
bl2 <- bl
bl2$Age[bl2$ID == 5L] <- 16
paths2 <- .ip_write_fake(td2, bl2, sle, arf)
ctx2 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths2))
stopifnot(nrow(ctx2$data$raw) == 4L)
stopifnot(!5L %in% as.integer(ctx2$data$raw$ID))
age_row <- ctx2$results$ip_attrition_steps
age_row <- age_row[age_row$step == "age_ge_18", , drop = FALSE]
stopifnot(nrow(age_row) == 1L)
stopifnot(identical(as.integer(age_row$n_out[[1L]]), 4L))

# --- 已有 Acute_Renal_Failure 时不覆盖，仅派生 Disease ---
td3 <- tempfile("ip_cohort_arfcol_")
dir.create(td3)
bl3 <- bl
bl3$Acute_Renal_Failure <- c("Yes", "No", "Yes", "No", "No",
                             "No", "No", "No", "No", "No")
paths3 <- .ip_write_fake(td3, bl3, sle, arf)
ctx3 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths3))
stopifnot(nrow(ctx3$data$raw) == 5L)
stopifnot(identical(as.character(ctx3$data$raw$Acute_Renal_Failure[ctx3$data$raw$ID == 1L]), "Yes"))
stopifnot(identical(as.integer(ctx3$data$raw$Disease[ctx3$data$raw$ID == 1L]), 1L))
stopifnot(identical(as.integer(ctx3$data$raw$Disease[ctx3$data$raw$ID == 2L]), 0L))

# --- ID 类型不一致（character subject_id vs numeric ID）仍能交集 ---
td4 <- tempfile("ip_cohort_idtype_")
dir.create(td4)
sle4 <- data.frame(subject_id = as.character(1:5), stringsAsFactors = FALSE)
paths4 <- .ip_write_fake(td4, bl, sle4, arf)
ctx4 <- block_ip_cohort_sle_aki(.ip_make_ctx(paths4))
stopifnot(nrow(ctx4$data$raw) == 5L)

# --- pipeline_block_sources 注册 ---
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
src_map <- pipeline_block_sources(root)
stopifnot("ip_cohort_sle_aki" %in% names(src_map))
stopifnot(grepl("01block_ip_cohort_sle_aki\\.R$", src_map$ip_cohort_sle_aki))
stopifnot(file.exists(src_map$ip_cohort_sle_aki))

# --- 真数据冒烟（路径存在才跑；Windows G: 与 WSL /mnt/g） ---
mim_cands <- c(
  "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/mimic",
  "/mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/mimic"
)
mim <- NULL
for (p in mim_cands) {
  if (dir.exists(p)) {
    mim <- p
    break
  }
}
if (!is.null(mim)) {
  bl_real <- file.path(mim, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
  sle_real <- file.path(mim, "SLE.csv")
  arf_real <- file.path(mim, "ARF.csv")
  if (file.exists(bl_real) && file.exists(sle_real) && file.exists(arf_real)) {
    ctx_r <- list(
      config = list(ip_two_stage = list(
        baseline_path = bl_real,
        baseline_obj = "baseline",
        sle_path = sle_real,
        arf_path = arf_real,
        baseline_id_col = "ID",
        aki_window_note = "ICU stay ARF/AKI"
      )),
      data = list(),
      results = list()
    )
    ctx_r <- block_ip_cohort_sle_aki(ctx_r)
    att_r <- ctx_r$results$ip_attrition_steps
    n_intersect <- as.integer(att_r$n_out[att_r$step == "intersect_SLE"][[1L]])
    n_analytic <- nrow(ctx_r$data$raw)
    n_aki <- as.integer(sum(ctx_r$data$raw$Disease == 1L, na.rm = TRUE))
    # Task 1: SLE ∩ baseline = 271；1 例 Age=NA 按 brief `!is.na(Age) & Age>=18` 剔除 → 270
    stopifnot(identical(n_intersect, 271L))
    stopifnot(identical(as.integer(n_analytic), 270L))
    stopifnot(identical(n_aki, 110L))
    message("real-data smoke: intersect_SLE=", n_intersect,
            " analytic=", n_analytic, " n_AKI=", n_aki)
  } else {
    message("real-data smoke skipped: missing baseline/SLE/ARF under ", mim)
  }
} else {
  message("real-data smoke skipped: mimic dir not found")
}

unlink(c(td, td2, td3, td4), recursive = TRUE)
cat("OK test_ip_cohort_sle_aki\n")
