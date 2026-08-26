#!/usr/bin/env Rscript
# TDD: ip_stage2_cohort_28d — 28 天行政截尾；AKI 亚队列；规则 C 时间零点
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)

common_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/00ip_common.R")
block_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R")
if (file.exists(common_src)) source(common_src, local = FALSE)
if (file.exists(block_src)) source(block_src, local = FALSE)

stopifnot(exists("ip_admin_censor_28", mode = "function"))
stopifnot(exists("block_ip_stage2_cohort_28d", mode = "function"))

# --- 行政截尾：futime=min(t,28); fustatus=1 iff dead & t<=28 ---
x <- ip_admin_censor_28(c(10, 40, 28, 5), c(1, 1, 0, 0))
stopifnot(identical(x$fustatus, c(1L, 0L, 0L, 0L)))
stopifnot(identical(as.numeric(x$futime), c(10, 28, 28, 5)))

# 恰 28 天死亡算事件；dead=NA 视为未死亡
x28 <- ip_admin_censor_28(c(28, 10), c(1, NA))
stopifnot(identical(x28$fustatus, c(1L, 0L)))
stopifnot(identical(as.numeric(x28$futime), c(28, 10)))

# t 缺失：fustatus=0，futime=NA
xna <- ip_admin_censor_28(c(10, NA_real_), c(1, 1))
stopifnot(identical(xna$fustatus, c(1L, 0L)))
stopifnot(is.na(xna$futime[[2L]]))

cat("OK censor logic\n")

.ip_s2_write_prog <- function(td, prog) {
  path <- file.path(td, "mimic_prog.csv")
  utils::write.csv(prog, path, row.names = FALSE, na = "")
  path
}

.ip_s2_ctx <- function(imputed, prog_path, extra_cfg = list(), locked = NULL) {
  cfg <- c(
    list(
      prognosis_path = prog_path,
      baseline_id_col = "ID",
      prognosis_id_col = "subject_id"
    ),
    extra_cfg
  )
  list(
    config = list(
      ip_two_stage = cfg,
      project = list(study_type = "incidence"),
      data = list(outcome_column = "Disease"),
      survival = list()
    ),
    data = list(imputed = imputed, locked = locked),
    results = list()
  )
}

# --- 假数据：5 人 Stage1，3 例 AKI；死亡 10d / 40d / 存活出院 5d ---
td <- tempfile("ip_stage2_")
dir.create(td)
t0 <- as.POSIXct("2180-07-23 14:00:00", tz = "UTC")
imputed <- data.frame(
  ID = 1:5,
  Disease = c(1L, 1L, 1L, 0L, 0L),
  Age = c(40, 50, 60, 70, 45),
  stringsAsFactors = FALSE
)
prog <- data.frame(
  subject_id = 1:5,
  icu_intime = format(t0, "%Y-%m-%d %H:%M:%S"),
  dead_time = c(
    format(t0 + 10 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 40 * 86400, "%Y-%m-%d %H:%M:%S"),
    "",
    format(t0 + 3 * 86400, "%Y-%m-%d %H:%M:%S"),
    ""
  ),
  is_dead = c(1L, 1L, NA_integer_, 1L, NA_integer_),
  disch_time = c(
    format(t0 + 8 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 12 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 5 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 3 * 86400, "%Y-%m-%d %H:%M:%S"),
    format(t0 + 2 * 86400, "%Y-%m-%d %H:%M:%S")
  ),
  icu_outtime = format(t0 + 1 * 86400, "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
prog_path <- .ip_s2_write_prog(td, prog)
ctx <- block_ip_stage2_cohort_28d(.ip_s2_ctx(imputed, prog_path))

stopifnot(is.data.frame(ctx$data$stage2))
stopifnot(identical(nrow(ctx$data$stage2), 3L))
stopifnot(identical(sort(as.integer(ctx$data$stage2$ID)), 1:3))
stopifnot(all(c("futime", "fustatus") %in% names(ctx$data$stage2)))
stopifnot(identical(ctx$results$ip_stage2_timezero_source, "icu_intime"))

ord <- order(as.integer(ctx$data$stage2$ID))
s2 <- ctx$data$stage2[ord, , drop = FALSE]
stopifnot(identical(as.integer(s2$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(as.numeric(s2$futime), c(10, 28, 5), tolerance = 1e-6)))

stopifnot(identical(ctx$config$project$study_type, "prognosis"))
stopifnot(identical(ctx$config$data$outcome_column, "fustatus"))
stopifnot(identical(ctx$config$survival$time_var, "futime"))
stopifnot(identical(ctx$config$survival$event_var, "fustatus"))
stopifnot(identical(nrow(ctx$data$imputed), 3L))
stopifnot(all(as.numeric(ctx$data$imputed$futime) <= 28))

# --- 规则 C：有 aki_time 则时间零点 = aki_onset ---
td_aki <- tempfile("ip_stage2_aki_")
dir.create(td_aki)
imputed_aki <- imputed
imputed_aki$aki_time <- format(t0 + 2 * 86400, "%Y-%m-%d %H:%M:%S")
prog_aki_path <- .ip_s2_write_prog(td_aki, prog)
ctx_aki <- block_ip_stage2_cohort_28d(.ip_s2_ctx(imputed_aki, prog_aki_path))
stopifnot(identical(ctx_aki$results$ip_stage2_timezero_source, "aki_onset"))
s2a <- ctx_aki$data$stage2[order(as.integer(ctx_aki$data$stage2$ID)), , drop = FALSE]
# ID1: 死亡相对 aki_time = 8d → 事件；ID2: 38d → 截在 28；ID3: 出院相对 aki = 3d
stopifnot(identical(as.integer(s2a$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(as.numeric(s2a$futime), c(8, 28, 3), tolerance = 1e-6)))

# --- locked 回退（无 imputed）---
td_lock <- tempfile("ip_stage2_lock_")
dir.create(td_lock)
prog_lock <- .ip_s2_write_prog(td_lock, prog)
ctx_lock <- .ip_s2_ctx(NULL, prog_lock, locked = imputed)
ctx_lock$data$imputed <- NULL
ctx_lock <- block_ip_stage2_cohort_28d(ctx_lock)
stopifnot(identical(nrow(ctx_lock$data$stage2), 3L))
stopifnot(identical(ctx_lock$results$ip_stage2_timezero_source, "icu_intime"))

# --- d/m/yyyy 预后 CSV（与 MIMIC 真数据格式一致）---
td_dm <- tempfile("ip_stage2_dm_")
dir.create(td_dm)
prog_dm <- data.frame(
  subject_id = 1:5,
  icu_intime = "23/7/2180 14:00:00",
  dead_time = c("2/8/2180 14:00:00", "1/9/2180 14:00:00", "", "26/7/2180 14:00:00", ""),
  is_dead = c(1L, 1L, NA_integer_, 1L, NA_integer_),
  disch_time = c(
    "31/7/2180 14:00:00", "4/8/2180 14:00:00", "28/7/2180 14:00:00",
    "26/7/2180 14:00:00", "25/7/2180 14:00:00"
  ),
  stringsAsFactors = FALSE
)
ctx_dm <- block_ip_stage2_cohort_28d(
  .ip_s2_ctx(imputed, .ip_s2_write_prog(td_dm, prog_dm))
)
s2d <- ctx_dm$data$stage2[order(as.integer(ctx_dm$data$stage2$ID)), , drop = FALSE]
# 23/7 → 2/8 = 10d 事件；23/7 → 1/9 ≈ 40d 截 28；存活 23/7→28/7 = 5d
stopifnot(identical(as.integer(s2d$fustatus), c(1L, 0L, 0L)))
stopifnot(isTRUE(all.equal(round(as.numeric(s2d$futime), 6), c(10, 28, 5), tolerance = 1e-4)))

# --- pipeline_block_sources 注册 ---
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
src_map <- pipeline_block_sources(root)
stopifnot("ip_stage2_cohort_28d" %in% names(src_map))
stopifnot(grepl("02block_ip_stage2_cohort_28d\\.R$", src_map$ip_stage2_cohort_28d))
stopifnot(file.exists(src_map$ip_stage2_cohort_28d))
# 旧课题映射仍在
stopifnot("ip_cohort_sle_aki" %in% names(src_map))
stopifnot("data_clean" %in% names(src_map))

# --- 真数据冒烟（路径存在才跑）---
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
  prog_real <- file.path(mim, "mimic预后数据-all.csv")
  cohort_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R")
  if (file.exists(bl_real) && file.exists(sle_real) && file.exists(arf_real) &&
      file.exists(prog_real) && file.exists(cohort_src)) {
    source(cohort_src, local = FALSE)
    ctx_r <- list(
      config = list(ip_two_stage = list(
        baseline_path = bl_real,
        baseline_obj = "baseline",
        sle_path = sle_real,
        arf_path = arf_real,
        baseline_id_col = "ID",
        prognosis_path = prog_real,
        aki_window_note = "ICU stay ARF/AKI"
      )),
      data = list(),
      results = list()
    )
    ctx_r <- block_ip_cohort_sle_aki(ctx_r)
    ctx_r$data$imputed <- ctx_r$data$raw
    n_aki <- as.integer(sum(ctx_r$data$imputed$Disease == 1L, na.rm = TRUE))
    ctx_r <- block_ip_stage2_cohort_28d(ctx_r)
    n_s2 <- nrow(ctx_r$data$stage2)
    stopifnot(identical(n_aki, 110L))
    stopifnot(n_s2 <= n_aki)
    stopifnot(n_s2 >= 1L)
    stopifnot(identical(ctx_r$results$ip_stage2_timezero_source, "icu_intime"))
    stopifnot(all(as.numeric(ctx_r$data$stage2$futime) <= 28, na.rm = TRUE))
    stopifnot(all(ctx_r$data$stage2$fustatus %in% c(0L, 1L)))
    stopifnot(identical(ctx_r$config$project$study_type, "prognosis"))
    message("real-data smoke: n_AKI=", n_aki, " stage2=", n_s2,
            " events=", sum(ctx_r$data$stage2$fustatus == 1L, na.rm = TRUE),
            " timezero=", ctx_r$results$ip_stage2_timezero_source)
  } else {
    message("real-data smoke skipped: missing cohort/prognosis files under ", mim)
  }
} else {
  message("real-data smoke skipped: mimic dir not found")
}

unlink(c(td, td_aki, td_lock, td_dm), recursive = TRUE)
cat("OK test_ip_stage2_28d\n")
