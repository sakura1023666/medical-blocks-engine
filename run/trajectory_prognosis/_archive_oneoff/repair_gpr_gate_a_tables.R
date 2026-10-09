#!/usr/bin/env Rscript
# GPR：预后 Gate A 对齐 Table1/S1/正态/单因素，并锁 Model2 交集刷多因素表
# 不重跑 JLCM / 轨迹下游。
#
#   Rscript run/trajectory_prognosis/repair_gpr_gate_a_tables.R [study_root]

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      return(normalizePath(file.path(d, "..", ".."), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

root <- .init_root()
setwd(root)
args <- commandArgs(trailingOnly = TRUE)
study_root <- if (length(args) && nzchar(args[[1L]])) args[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
db_seq <- c("eicu", "mimic")

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(study_root, "config.R"))
config_ix <- trajectory_batch_patch_config_for_index(config, ix)

.out_ix_dir <- function() {
  base <- file.path(study_root, "by_index")
  hits <- list.files(base, full.names = TRUE)
  hits <- hits[dir.exists(hits) & grepl(paste0(ix, "$"), basename(hits))]
  if (length(hits)) hits[[1L]] else file.path(base, ix)
}
out_ix <- .out_ix_dir()
ck_base <- file.path(study_root, "checkpoints", "by_index", ix)
disease <- "Sepsis AKI"
gate_dir <- file.path(study_root, "data", "harmonized")
dir.create(gate_dir, recursive = TRUE, showWarnings = FALSE)

cli::cli_h1("GPR Gate A 表修复")
cli::cli_alert_info("产出: {.file {out_ix}} | ck: {.file {ck_base}}")

# ── helpers ──────────────────────────────────────────────────────────────────
.filter_df <- function(d, keep, db) {
  if (is.null(d) || !is.data.frame(d)) return(d)
  extra <- grep(paste0("(^|_)", ix, "(_|$)"), names(d), value = TRUE)
  k <- unique(c(intersect(keep, names(d)), extra))
  if (length(k) < 8L) stop("[", db, "] Gate A 过滤后列过少: ", length(k))
  d[, k, drop = FALSE]
}

.filter_ctx <- function(ctx, keep, db) {
  for (slot in c("imputed", "mapped", "cleaned", "raw", "train", "test")) {
    ctx$data[[slot]] <- .filter_df(ctx$data[[slot]], keep, db)
  }
  ctx
}

.save_ck <- function(ck_dir, block, ctx) {
  dir.create(ck_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(ctx = ctx, pub_counters = NULL, block = block, saved_at = Sys.time()),
          file.path(ck_dir, paste0(block, ".rds")))
}

.unlink_blocks <- function(ck_dir, blocks) {
  for (b in blocks) {
    f <- file.path(ck_dir, paste0(b, ".rds"))
    if (file.exists(f)) unlink(f)
    # step aliases
    ss <- list.files(ck_dir, pattern = paste0("^step[0-9]+_", b, "\\.rds$"), full.names = TRUE)
    if (length(ss)) unlink(ss)
  }
}

.read_m2 <- function(db) {
  cands <- c(
    file.path(out_ix, db, "step13_multicollinearity_final", "Model2Factors.txt"),
    file.path(out_ix, db, "step10_multicollinearity_screen", "Model2Factors.txt"),
    file.path(ck_base, db, "Model2Factors.txt")
  )
  for (p in cands) {
    if (file.exists(p)) {
      x <- unique(trimws(readLines(p, warn = FALSE)))
      x <- x[nzchar(x) & !startsWith(x, "#")]
      if (length(x)) return(x)
    }
  }
  ck <- file.path(ck_base, db, "multicollinearity_final.rds")
  if (file.exists(ck)) {
    m2 <- tryCatch(readRDS(ck)$ctx$results$Model2Factors, error = function(e) NULL)
    if (length(m2)) return(as.character(m2))
  }
  character(0)
}

.run_pl <- function(db, keep, blocks, from_block, locked_m2 = NULL) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  ck <- file.path(ck_base, db)
  ctx <- study_batch_load_checkpoint_ctx(ck, from_block)
  ctx <- .filter_ctx(ctx, keep, db)

  cfg <- config_ix
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg$project$database <- db_cfg$name %||% toupper(db)
  cfg$project$output_dir <- file.path(out_ix, db)
  cfg$dual_db$current_db <- db
  cfg$dual_db$enable <- TRUE
  cfg$dual_db$harmonization <- utils::modifyList(
    cfg$dual_db$harmonization %||% list(),
    list(column_keep_eicu = keep_e, column_keep_mimic = keep_m,
         column_keep_nhanes = keep_e, common_non_demo_cols = common_clin)
  )
  if (length(locked_m2)) {
    ctx$results$Model2Factors <- locked_m2
    ctx$results$vif_screen_pass <- locked_m2
    m1 <- locked_m2[grepl("^(Age|Gender|Sex|Race|Weight|Height|BMI)$", locked_m2, ignore.case = TRUE)]
    if (!length(m1)) m1 <- "Age"
    ctx$results$Model1Factors <- m1
    cfg$multivariate_prognosis_harmonized <- cfg$multivariate_prognosis_harmonized %||% list()
    cfg$multivariate_prognosis_harmonized$fixed_model2_factors <- locked_m2
  }
  ctx$config <- cfg
  ctx$root_output_dir <- cfg$project$output_dir

  .unlink_blocks(ck, blocks)
  for (st in blocks) {
    p <- file.path(out_ix, db)
    old <- list.files(p, pattern = paste0("^step[0-9]+_", st, "$"), full.names = TRUE)
    if (length(old)) unlink(old, recursive = TRUE)
  }

  pl <- list(
    name = paste0("gpr_gateA_", db),
    blocks = blocks,
    render_tables_after = blocks,
    checkpoint = list(enable = TRUE, dir = ck)
  )
  cli::cli_h2("[{db_lab}] {paste(blocks, collapse=' -> ')}")
  run_pipeline(root, config = cfg, pipeline = pl, run_opts = list(initial_ctx = ctx))
}

# ── Gate A ───────────────────────────────────────────────────────────────────
ctx_e0 <- study_batch_load_checkpoint_ctx(file.path(ck_base, "eicu"), "imputation")
ctx_m0 <- study_batch_load_checkpoint_ctx(file.path(ck_base, "mimic"), "imputation")
cols_e <- names(ctx_e0$data$imputed %||% ctx_e0$data$cleaned)
cols_m <- names(ctx_m0$data$imputed %||% ctx_m0$data$cleaned)

demo_kw <- c("Age", "Gender", "Sex", "Race", "Ethnicity", "Education", "Marital",
             "Language", "Insurance", "Height", "Weight", "BMI")
protected <- unique(c(
  "subject_id", "ID", "survival_time_28d", "survival_28d", "Mortality_28d",
  "fustatus", "futime", ix,
  as.character((config_ix$data %||% list())$id_column %||% "subject_id")
))
demo_e <- cols_e[dual_db_is_demo_col(cols_e, demo_kw)]
demo_m <- cols_m[dual_db_is_demo_col(cols_m, demo_kw)]
demo_common <- intersect(demo_e, demo_m)
non_e <- setdiff(cols_e, unique(c(demo_e, protected)))
non_m <- setdiff(cols_m, unique(c(demo_m, protected)))
common_clin <- sort(intersect(non_e, non_m))
if (exists("pipeline_gate_a_align_ventilation_cols", mode = "function")) {
  common_clin <- pipeline_gate_a_align_ventilation_cols(cols_e, cols_m, common_clin)
}
keep_e <- unique(c(intersect(protected, cols_e), demo_common, common_clin))
keep_m <- unique(c(intersect(protected, cols_m), demo_common, common_clin))
if (exists("pipeline_ventilation_keep_alias", mode = "function")) {
  keep_e <- pipeline_ventilation_keep_alias(keep_e, cols_e)
  keep_m <- pipeline_ventilation_keep_alias(keep_m, cols_m)
}

cli::cli_alert_success(
  "Gate A: 共同临床 {length(common_clin)} | 共同人口学 {length(demo_common)} | keep eICU={length(keep_e)} MIMIC={length(keep_m)}"
)
cli::cli_alert_info("丢弃 eICU: {paste(head(sort(setdiff(cols_e, keep_e)), 15), collapse=', ')}")
cli::cli_alert_info("丢弃 MIMIC: {paste(head(sort(setdiff(cols_m, keep_m)), 15), collapse=', ')}")
saveRDS(list(keep_e = keep_e, keep_m = keep_m, common_clin = common_clin, demo_common = demo_common),
        file.path(gate_dir, "gate_a_columns_GPR.rds"))

# 写回过滤后的 imputation checkpoint（供 S1/后续）
for (db in db_seq) {
  keep <- if (identical(db, "eicu")) keep_e else keep_m
  ck <- file.path(ck_base, db)
  ctx <- study_batch_load_checkpoint_ctx(ck, "imputation")
  ctx <- .filter_ctx(ctx, keep, db)
  .save_ck(ck, "imputation", ctx)
  if (file.exists(file.path(ck, "step01_imputation.rds")))
    .save_ck(ck, "step01_imputation", ctx) # name wrong but ok; rewrite properly:
  file.copy(file.path(ck, "imputation.rds"), file.path(ck, "step01_imputation.rds"), overwrite = TRUE)
}

prefix_blocks <- c(
  "analysis_exclusion", "baseline_binary", "univariate_prognosis",
  "multicollinearity_screen", "multivariate_prognosis",
  "multivariate_covariate_resolve", "multicollinearity_final"
)

# ── 仅重导 Table S1（不重跑 MICE）：调用 .imp01_build_table_s1 ───────────────
imp_block <- file.path(root, "Blocks/03_imputation/01block_imputation.R")
if (file.exists(imp_block)) source(imp_block, local = FALSE)
.rebuild_s1 <- function(db, keep) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  ck <- file.path(ck_base, db)
  ctx <- study_batch_load_checkpoint_ctx(ck, "imputation")
  ctx <- .filter_ctx(ctx, keep, db)
  cfg <- config_ix
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg$project$database <- db_cfg$name %||% toupper(db)
  cfg$project$output_dir <- file.path(out_ix, db)
  ctx$config <- cfg
  before <- ctx$data$cleaned %||% ctx$data$mapped
  after <- ctx$data$imputed
  if (is.null(before) || is.null(after)) {
    cli::cli_alert_warning("[{db_lab}] 缺 cleaned/imputed，跳过 S1")
    return(invisible(FALSE))
  }
  before <- .filter_df(before, keep, db)
  after <- .filter_df(after, keep, db)
  out_tab <- file.path(cfg$project$output_dir, "step06_imputation", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  ctx$output_dir <- file.path(cfg$project$output_dir, "step06_imputation")
  ctx$output_dir_tables <- out_tab
  if (!exists(".imp01_build_table_s1", mode = "function")) {
    cli::cli_alert_warning("[{db_lab}] 无 .imp01_build_table_s1")
    return(invisible(FALSE))
  }
  outcome_col <- cfg$data$outcome_column %||% cfg$survival$event_var %||% "survival_28d"
  study_type <- tolower(cfg$project$study_type %||% "prognosis")
  outcome_lbl <- if (exists("pipeline_resolve_outcome_display_labels", mode = "function")) {
    pipeline_resolve_outcome_display_labels(cfg)
  } else list(analysis = "1", reference = "0")
  table_strata <- if (identical(study_type, "prognosis")) {
    cfg$survival$event_var %||% outcome_col
  } else outcome_col
  imp_cfg <- cfg$imputation %||% list()
  ctx <- .imp01_build_table_s1(
    ctx, cfg, before, after,
    table_strata = table_strata,
    analysis_grp = outcome_lbl$analysis %||% "1",
    reference_grp = outcome_lbl$reference %||% "0",
    imp_cfg = imp_cfg
  )
  if (exists("render_queued_tables", mode = "function")) render_queued_tables(ctx)
  .save_ck(ck, "imputation", ctx)
  file.copy(file.path(ck, "imputation.rds"), file.path(ck, "step01_imputation.rds"), overwrite = TRUE)
  cli::cli_alert_success("[{db_lab}] Table S1 已按 Gate A 重导")
  invisible(TRUE)
}

for (db in db_seq) {
  keep <- if (identical(db, "eicu")) keep_e else keep_m
  .rebuild_s1(db, keep)
}

# ── Pass1: Gate A 列池重跑 baseline→多因素前缀（不重跑 JLCM）────────────────
for (db in db_seq) {
  keep <- if (identical(db, "eicu")) keep_e else keep_m
  .run_pl(db, keep, blocks = prefix_blocks, from_block = "imputation")
}

m2_e <- .read_m2("eicu")
m2_m <- .read_m2("mimic")
cli::cli_h2("Model2 双库交集锁定")
cli::cli_alert_info("eICU: {paste(m2_e, collapse=', ')}")
cli::cli_alert_info("MIMIC: {paste(m2_m, collapse=', ')}")
m2_lock <- intersect(m2_e, m2_m)
if (!"Age" %in% m2_lock) m2_lock <- unique(c("Age", m2_lock))
if (length(m2_lock) <= 1L) {
  m2_lock <- unique(c("Age", intersect(c("Temperature", "OASIS", "APSIII", "RR"), common_clin)))
}
cli::cli_alert_success("锁定 Model2 = {paste(m2_lock, collapse=', ')}")
writeLines(m2_lock, file.path(gate_dir, "Model2_locked_GPR.txt"))

# ── Pass2: 锁 Model2 后重刷 VIF screen / 多因素 / final ──────────────────────
mv_blocks <- c(
  "multicollinearity_screen", "multivariate_prognosis",
  "multivariate_covariate_resolve", "multicollinearity_final"
)
for (db in db_seq) {
  keep <- if (identical(db, "eicu")) keep_e else keep_m
  .run_pl(db, keep, blocks = mv_blocks, from_block = "univariate_prognosis", locked_m2 = m2_lock)
}

# ── 同步到分库 Tables + curate + 根镜像 ──────────────────────────────────────
.sync_unit_tables <- function(db) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  tab <- file.path(unit, "Tables")
  dir.create(tab, recursive = TRUE, showWarnings = FALSE)
  step_map <- list(
    "step06_imputation" = sprintf("^Table S1-%s", db_lab),
    "step08_baseline_binary" = sprintf("^Table (1|S2)-%s", db_lab),
    "step09_univariate_prognosis" = sprintf("^Table S3-%s", db_lab),
    "step10_multicollinearity_screen" = sprintf("^Table S4-%s", db_lab),
    "step11_multivariate_prognosis" = sprintf("^Table S5-%s", db_lab),
    "step13_multicollinearity_final" = sprintf("^Table S6-%s", db_lab)
  )
  # step 编号可能因 pipeline 变化，按内容搜
  for (st in list.dirs(unit, recursive = FALSE, full.names = TRUE)) {
    tdir <- file.path(st, "Tables")
    if (!dir.exists(tdir)) next
    xs <- list.files(tdir, pattern = "\\.xlsx$", full.names = TRUE)
    for (f in xs) {
      bn <- basename(f)
      if (grepl(sprintf("^Table (1|S[1-6])-%s", db_lab), bn)) {
        file.copy(f, file.path(tab, bn), overwrite = TRUE)
      }
    }
  }
}

for (db in db_seq) .sync_unit_tables(db)

trajectory_curate_pub_outputs(
  base_dir = out_ix, index_name = ix, dbs = db_seq, disease = disease
)

root_tab <- file.path(out_ix, "Tables")
dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
# 去掉旧错名
old_junk <- list.files(root_tab, pattern = "(VIF screen|VIF final|training set|Table3 |Table_S5_)", full.names = TRUE)
if (length(old_junk)) unlink(old_junk)
for (db in db_seq) {
  xs <- list.files(file.path(out_ix, db, "Tables"), pattern = "^Table .*\\.xlsx$", full.names = TRUE)
  for (f in xs) file.copy(f, file.path(root_tab, basename(f)), overwrite = TRUE)
}

cli::cli_h2("结果")
for (db in db_seq) {
  cli::cli_alert_info("{db} Model2={paste(.read_m2(db), collapse=', ')}")
  cli::cli_alert_info("{db} n_xlsx={length(list.files(file.path(out_ix, db, 'Tables'), pattern='\\\\.xlsx$'))}")
}
cli::cli_alert_success("根目录 xlsx={length(list.files(root_tab, pattern='\\\\.xlsx$'))}；JLCM 未重跑。")
