#!/usr/bin/env Rscript
# TDD: threshold_logistic — 连续 index 网格/分段 logistic；阈值 + 下/上 OR；CSV+PDF
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)

block_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R")
if (file.exists(block_src)) source(block_src, local = FALSE)
stopifnot(exists("block_threshold_logistic", mode = "function"))

.thl_ctx <- function(dat, out_dir, extra_cfg = list(), profile = NULL, study = "incidence") {
  tbl <- file.path(out_dir, "Tables")
  fig <- file.path(out_dir, "Figures")
  dir.create(tbl, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig, recursive = TRUE, showWarnings = FALSE)
  cfg <- list(
    project = list(
      study_type = study,
      disease = "AKI",
      analysis_group = "AKI",
      output_dir = out_dir
    ),
    incidence = list(index_var = "NLR", outcome_var = "Disease"),
    data = list(outcome_column = "Disease"),
    threshold_logistic = extra_cfg,
    pub_figure = if (is.null(profile)) list() else list(profile = profile)
  )
  list(
    config = cfg,
    data = list(imputed = dat),
    results = list(Model1Factors = "Age", Model2Factors = "Age"),
    output_dir = out_dir,
    output_dir_tables = tbl,
    output_dir_figures = fig,
    root_output_dir = out_dir
  )
}

# --- 假数据：hinge 约在 5；应估出有限阈值与两侧 OR ---
set.seed(5L)
n <- 360L
Age <- round(rnorm(n, 55, 12), 1)
NLR <- runif(n, 0.5, 12)
lp <- -2.2 + 0.05 * pmin(NLR, 5) + 0.55 * pmax(NLR - 5, 0) + 0.015 * (Age - 55)
p <- 1 / (1 + exp(-lp))
dat <- data.frame(
  ID = seq_len(n),
  NLR = NLR,
  Age = Age,
  Disease = rbinom(n, 1L, p),
  stringsAsFactors = FALSE
)
stopifnot(sum(dat$Disease) >= 40L, sum(dat$Disease == 0L) >= 40L)

td <- tempfile("thl_")
dir.create(td)
ctx <- block_threshold_logistic(.thl_ctx(dat, td))
res <- ctx$results$threshold_logistic
stopifnot(is.list(res) || is.data.frame(res))
if (is.data.frame(res)) {
  stopifnot(nrow(res) >= 1L)
  tau <- as.numeric(res$threshold[[1L]])
} else {
  tau <- as.numeric(res$threshold)[1L]
}
stopifnot(is.finite(tau))
stopifnot(tau > min(dat$NLR), tau < max(dat$NLR))
or_lo <- as.numeric(res$or_below)[1L]
or_hi <- as.numeric(res$or_above)[1L]
stopifnot(is.finite(or_lo), is.finite(or_hi), or_lo > 0, or_hi > 0)
p_lo <- as.numeric(res$p_below)[1L]
p_hi <- as.numeric(res$p_above)[1L]
stopifnot(is.finite(p_lo), is.finite(p_hi), p_lo >= 0, p_lo <= 1, p_hi >= 0, p_hi <= 1)

tab_files <- list.files(file.path(td, "Tables"), pattern = "Threshold.*logistic.*\\.csv$", ignore.case = TRUE)
if (!length(tab_files)) {
  tab_files <- list.files(file.path(td, "Tables"), pattern = "\\.csv$", ignore.case = TRUE)
}
stopifnot(length(tab_files) >= 1L)
tab <- utils::read.csv(file.path(td, "Tables", tab_files[[1L]]), stringsAsFactors = FALSE)
need <- c("threshold", "or_below", "or_above", "p_below", "p_above")
stopifnot(all(need %in% names(tab)))
stopifnot(is.finite(as.numeric(tab$threshold[[1L]])))

fig_files <- list.files(file.path(td, "Figures"), pattern = "Threshold.*\\.pdf$", ignore.case = TRUE)
if (!length(fig_files)) {
  fig_files <- list.files(file.path(td, "Figures"), pattern = "\\.pdf$", ignore.case = TRUE)
}
stopifnot(length(fig_files) >= 1L)
fig_path <- file.path(td, "Figures", fig_files[[1L]])
stopifnot(file.info(fig_path)$size > 500)

# 非 incidence 应跳过、不写新表
td_skip <- tempfile("thl_skip_")
dir.create(td_skip)
ctx_skip <- block_threshold_logistic(.thl_ctx(dat, td_skip, study = "prognosis"))
stopifnot(is.null(ctx_skip$results$threshold_logistic))
stopifnot(!length(list.files(file.path(td_skip, "Tables"), pattern = "\\.csv$")))

# profile 文献版：同样落盘 PDF
td_lit <- tempfile("thl_lit_")
dir.create(td_lit)
ctx_lit <- block_threshold_logistic(
  .thl_ctx(dat, td_lit, profile = "mimic_inc_prog_sle_aki")
)
stopifnot(!is.null(ctx_lit$results$threshold_logistic))
fig_lit <- list.files(file.path(td_lit, "Figures"), pattern = "\\.pdf$", ignore.case = TRUE)
stopifnot(length(fig_lit) >= 1L)

# --- pipeline_block_sources 注册 ---
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
src_map <- pipeline_block_sources(root)
stopifnot("threshold_logistic" %in% names(src_map))
stopifnot(grepl("03block_threshold_logistic\\.R$", src_map$threshold_logistic))
stopifnot(file.exists(src_map$threshold_logistic))
stopifnot("ip_stage2_cohort_28d" %in% names(src_map))
stopifnot("data_clean" %in% names(src_map))

# --- 真数据冒烟：SLE 队列 Age 当连续暴露 ---
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
  cohort_src <- file.path(root, "Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R")
  bl_real <- file.path(mim, "D01_baseline_MIMIC_ICU_frist_0626 (1).RData")
  sle_real <- file.path(mim, "SLE.csv")
  arf_real <- file.path(mim, "ARF.csv")
  if (file.exists(cohort_src) && file.exists(bl_real) && file.exists(sle_real) && file.exists(arf_real)) {
    source(cohort_src, local = FALSE)
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
    td_r <- tempfile("thl_real_")
    dir.create(td_r)
    d_r <- ctx_r$data$raw
    ctx_r$data$imputed <- d_r
    ctx_r$config$project$study_type <- "incidence"
    ctx_r$config$project$disease <- "AKI"
    ctx_r$config$incidence <- list(index_var = "Age", outcome_var = "Disease")
    ctx_r$config$data <- list(outcome_column = "Disease")
    ctx_r$config$threshold_logistic <- list(min_segment_n = 20L)
    ctx_r$results$Model1Factors <- character(0)
    ctx_r$results$Model2Factors <- character(0)
    ctx_r$output_dir <- td_r
    ctx_r$output_dir_tables <- file.path(td_r, "Tables")
    ctx_r$output_dir_figures <- file.path(td_r, "Figures")
    dir.create(ctx_r$output_dir_tables, recursive = TRUE)
    dir.create(ctx_r$output_dir_figures, recursive = TRUE)
    ctx_r <- block_threshold_logistic(ctx_r)
    stopifnot(!is.null(ctx_r$results$threshold_logistic))
    stopifnot(length(list.files(ctx_r$output_dir_tables, pattern = "\\.csv$")) >= 1L)
    stopifnot(length(list.files(ctx_r$output_dir_figures, pattern = "\\.pdf$")) >= 1L)
    message(
      "real-data smoke: n=", nrow(d_r),
      " events=", sum(d_r$Disease == 1L, na.rm = TRUE),
      " threshold=", signif(as.numeric(ctx_r$results$threshold_logistic$threshold)[1L], 4)
    )
    unlink(td_r, recursive = TRUE)
  } else {
    message("real-data smoke skipped: missing cohort files under ", mim)
  }
} else {
  message("real-data smoke skipped: mimic dir not found")
}

unlink(c(td, td_skip, td_lit), recursive = TRUE)
cat("OK test_threshold_logistic\n")
