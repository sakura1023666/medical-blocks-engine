#!/usr/bin/env Rscript
# =============================================================================
# step02_imputation — 仅基线协变量 MICE；禁止 HAMD / HAMA / CSSRS 相关插补
#
# 输入: step01_data_clean/dabiao.RData（门诊六节点完整）
# 输出: step02_imputation/
#   dabiao.RData, imputation_note.txt, mice_vars.csv,
#   missing_before_after.csv, step_meta.csv, README.md
# 同步: data/harmonized/D04_outpatient_clpm_imputed.RData
#
# 用法:
#   CROSS_LAGGED_STUDY_ROOT=/mnt/g/02block_result/43_Suicide/cross-laged_40595747 \
#     Rscript run/cross_lagged/run_suicide_clpm_step02_imputation.R
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  engine_root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  engine_root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(engine_root)

`%||%` <- function(a, b) if (is.null(a)) b else a

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) {
  stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

step_dir <- file.path(study_root, "step02_imputation")
dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)

cfg_path <- file.path(study_root, "config_suicide_clpm.R")
.cfg_env <- new.env(parent = globalenv())
sys.source(cfg_path, envir = .cfg_env)
config <- .cfg_env$config
cands <- as.character(
  .cfg_env$covariate_candidate_vars %||%
    config$suicide_cssrs$covariate_candidate_vars %||%
    character(0)
)
nodes <- as.character(config$suicide_cssrs$nodes)
design_excl <- as.character(config$suicide_cssrs$design_exclude_vars %||% character(0))
mice_excl_cfg <- as.character(config$imputation$exclude_from_mice_cols %||% character(0))

seed <- as.integer(config$imputation$seed %||% 40595747L)
m_imp <- as.integer(config$imputation$m %||% 5L)
maxit <- as.integer(config$imputation$max_iter %||% 5L)
miss_drop_thr <- 0.4

src <- file.path(study_root, "step01_data_clean/dabiao.RData")
if (!file.exists(src)) stop("Missing step01 dabiao: ", src, call. = FALSE)
e <- new.env(parent = emptyenv())
load(src, envir = e)
df0 <- e$dabiao
stopifnot(is.data.frame(df0), nrow(df0) > 0L)

# 家族史、MMAS-8 在插补之前合成。MASS 8 来自更新后的 D04（A=1, B=0.75, C=0.5, D=0.25, E=0）。
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_indicator_names.R"), local = FALSE)
d04_path <- file.path(study_root, "data/RDATA/RDATA/01RawData/D04_Full_Treatment_related_Information.RData")
if (!file.exists(d04_path)) stop("Missing updated D04: ", d04_path, call. = FALSE)
e04 <- new.env(parent = emptyenv())
load(d04_path, envir = e04)
d04 <- e04[[ls(e04)[1L]]]
if (!"MASS_8" %in% names(d04)) stop("D04 has no MASS_8", call. = FALSE)
id_df <- trimws(as.character(df0$ID))
id_raw <- trimws(as.character(d04[["新编号"]]))
hit <- match(id_df, id_raw)
if (anyNA(hit)) stop("MASS_8 match failed for ", sum(is.na(hit)), " IDs", call. = FALSE)
df0[["MASS 8"]] <- trimws(as.character(d04$MASS_8[hit]))
df0 <- suicide_recode_indicator_levels(df0)
df0 <- suicide_add_composite_indicators(df0)
if (!"Medication adherence" %in% names(df0)) {
  stop("Medication adherence was not created; MASS items 1-8 must all be present", call. = FALSE)
}
dabiao <- df0
save(dabiao, file = file.path(study_root, "step01_data_clean/dabiao.RData"))
save(dabiao, file = file.path(study_root, "data/harmonized/D04_outpatient_clpm.RData"))

message(
  "[step02_imputation] pre-MI Family history missing=",
  sum(is.na(df0[["Family history"]])),
  " Medication adherence missing=",
  sum(is.na(df0[["Medication adherence"]])),
  " adherence range=",
  paste(range(df0[["Medication adherence"]], na.rm = TRUE), collapse = "-")
)

message("[step02_imputation] study_root = ", study_root)
message("[step02_imputation] input n=", nrow(df0), " cols=", ncol(df0))

# ---- 硬禁：一切 HAMD / HAMA / CSSRS / C_SSRS 相关列不得进 MICE ----
scale_pat <- "(?i)HAMD|HAMA|CSSRS|C_SSRS|SSRS"
scale_cols <- grep(scale_pat, names(df0), value = TRUE, perl = TRUE)
never_mice <- unique(c(
  nodes,
  mice_excl_cfg,
  scale_cols,
  design_excl,
  "ID", "新编号", "患者类别", "Patient Group",
  paste("Familyhistory", 1:6),
  "Forgets medication", "Missed doses in 2 weeks", "Reduced dose alone",
  "Forgets medication away", "Took medication yesterday", "Stopped when better",
  "Hard to adhere", "MASS 8", "MASS_8"
))

# 仅基线协变量白名单（config）；再剔除禁插补列
mice_pool <- intersect(cands, names(df0))
mice_pool <- setdiff(mice_pool, never_mice)
# 再保险：白名单里若误含 1st / 量表名 / CGI|EI 也剔掉
mice_pool <- mice_pool[!grepl(scale_pat, mice_pool, perl = TRUE)]
mice_pool <- mice_pool[!grepl("(?i)_1st|1st_", mice_pool, perl = TRUE)]
mice_pool <- mice_pool[!grepl("(?i)^CGI_|_CGI|\\bEI_", mice_pool, perl = TRUE)]
# config 显式 Table1/分析禁止列
t1_forbid <- as.character(config$suicide_cssrs$table1_forbid_vars %||% character(0))
mice_pool <- setdiff(mice_pool, t1_forbid)

miss_rate <- vapply(mice_pool, function(v) mean(is.na(df0[[v]])), numeric(1))
drop_hi_miss <- names(miss_rate)[miss_rate >= miss_drop_thr]
mice_vars <- setdiff(mice_pool, drop_hi_miss)

message("[step02_imputation] never_mice (scale/design) n=", length(intersect(never_mice, names(df0))))
message("[step02_imputation] scale cols frozen: ", paste(scale_cols, collapse = ", "))
message("[step02_imputation] drop_hi_miss (>=", miss_drop_thr, "): ",
        if (length(drop_hi_miss)) paste(drop_hi_miss, collapse = ", ") else "(none)")
message("[step02_imputation] MICE vars n=", length(mice_vars), ": ", paste(mice_vars, collapse = ", "))

if (!length(mice_vars)) stop("No covariate vars left for MICE", call. = FALSE)

# 插补前缺失快照（仅 mice_vars）
miss_before <- data.frame(
  variable = mice_vars,
  n_missing_before = vapply(mice_vars, function(v) sum(is.na(df0[[v]])), integer(1)),
  pct_missing_before = round(100 * miss_rate[mice_vars], 2),
  stringsAsFactors = FALSE
)

df_imp <- df0
impute_note <- c(
  "STEP=step02_imputation",
  "SCOPE=baseline_covariates_only",
  "FORBIDDEN=HAMD/HAMA/CSSRS/C_SSRS related columns never imputed",
  paste0("SCALE_COLS_FROZEN=", paste(scale_cols, collapse = ",")),
  paste0("N_INPUT=", nrow(df0)),
  paste0("DROPPED_HI_MISS=", paste(drop_hi_miss, collapse = ","))
)

need_mice <- any(vapply(mice_vars, function(v) any(is.na(df0[[v]])), logical(1)))
if (!need_mice) {
  impute_note <- c(impute_note, "IMPUTATION=none_needed (no NA in mice_vars)")
  message("[step02_imputation] no NA in mice_vars; copy through")
} else {
  if (!requireNamespace("mice", quietly = TRUE)) {
    stop("Package 'mice' required", call. = FALSE)
  }
  set.seed(seed)
  mice_df <- df0[, mice_vars, drop = FALSE]
  for (v in names(mice_df)) {
    if (is.character(mice_df[[v]])) mice_df[[v]] <- factor(mice_df[[v]])
  }
  message("[step02_imputation] mice start m=", m_imp, " maxit=", maxit, " method=cart seed=", seed)
  t0 <- proc.time()[["elapsed"]]
  imp <- mice::mice(
    mice_df,
    m = m_imp,
    maxit = maxit,
    method = "cart",
    seed = seed,
    printFlag = FALSE
  )
  elapsed <- proc.time()[["elapsed"]] - t0
  completed <- mice::complete(imp, action = as.integer(config$imputation$complete_action %||% 1L))
  for (v in names(completed)) {
    df_imp[[v]] <- completed[[v]]
  }
  # 强制写回：量表/节点列必须与插补前逐字相同
  for (v in intersect(scale_cols, names(df0))) {
    df_imp[[v]] <- df0[[v]]
  }
  for (v in intersect(nodes, names(df0))) {
    df_imp[[v]] <- df0[[v]]
  }
  impute_note <- c(
    impute_note,
    sprintf(
      "IMPUTATION=mice_baseline_covars m=%d complete_action=1 method=cart seed=%d elapsed_s=%.1f",
      m_imp, seed, elapsed
    ),
    paste0("MICE_VARS=", paste(mice_vars, collapse = ","))
  )
  message("[step02_imputation] mice done in ", round(elapsed, 1), "s")
}

# 校验：节点与量表列未被改动
for (v in intersect(unique(c(nodes, scale_cols)), names(df0))) {
  same <- identical(df_imp[[v]], df0[[v]])
  if (!isTRUE(same)) {
    # numeric NA equality
    if (is.numeric(df0[[v]]) || is.integer(df0[[v]])) {
      same <- isTRUE(all.equal(df_imp[[v]], df0[[v]], check.attributes = FALSE))
    }
  }
  if (!isTRUE(same)) stop("Frozen column was altered by imputation: ", v, call. = FALSE)
}
# mice_vars 插补后应无 NA
n_na_after <- vapply(mice_vars, function(v) sum(is.na(df_imp[[v]])), integer(1))
if (any(n_na_after > 0L)) {
  warning("Some mice_vars still have NA after complete: ",
          paste(mice_vars[n_na_after > 0L], collapse = ", "))
}

miss_after <- data.frame(
  variable = mice_vars,
  n_missing_after = as.integer(n_na_after),
  pct_missing_after = round(100 * n_na_after / nrow(df_imp), 2),
  stringsAsFactors = FALSE
)
miss_ba <- merge(miss_before, miss_after, by = "variable", all = TRUE, sort = FALSE)

# ---- write products ----
dabiao <- df_imp
save(dabiao, file = file.path(step_dir, "dabiao.RData"))
harm_imp <- file.path(study_root, "data/harmonized/D04_outpatient_clpm_imputed.RData")
dir.create(dirname(harm_imp), recursive = TRUE, showWarnings = FALSE)
save(dabiao, file = harm_imp)

writeLines(impute_note, file.path(step_dir, "imputation_note.txt"))
utils::write.csv(
  data.frame(variable = mice_vars, in_mice = TRUE, stringsAsFactors = FALSE),
  file.path(step_dir, "mice_vars.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
utils::write.csv(
  data.frame(variable = sort(intersect(never_mice, names(df0))), excluded_from_mice = TRUE,
             stringsAsFactors = FALSE),
  file.path(step_dir, "excluded_from_mice.csv"),
  row.names = FALSE, fileEncoding = "UTF-8"
)
utils::write.csv(miss_ba, file.path(step_dir, "missing_before_after.csv"),
                 row.names = FALSE, fileEncoding = "UTF-8")
if (length(drop_hi_miss)) {
  utils::write.csv(
    data.frame(
      variable = drop_hi_miss,
      pct_missing = round(100 * miss_rate[drop_hi_miss], 2),
      reason = paste0("missing_rate>=", miss_drop_thr, "; not imputed"),
      stringsAsFactors = FALSE
    ),
    file.path(step_dir, "dropped_high_missing.csv"),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
}

meta <- data.frame(
  step = "step02_imputation",
  block = "imputation",
  cohort = "outpatient",
  n = nrow(dabiao),
  n_mice_vars = length(mice_vars),
  n_scale_frozen = length(scale_cols),
  method = "cart",
  m = m_imp,
  seed = seed,
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
utils::write.csv(meta, file.path(step_dir, "step_meta.csv"), row.names = FALSE, fileEncoding = "UTF-8")

readme <- c(
  "# step02_imputation",
  "",
  "等价 block：`imputation`（仅基线协变量 MICE）。",
  "",
  "## 规则",
  "",
  "- 输入：`step01_data_clean/dabiao.RData`（六节点已 listwise 完整）",
  "- **插补前合成**：Family history（六列任一种精神疾病诊断即为 Yes）；Medication adherence（MMAS-8，0-8）；Education 收成 Before high school / High school or above",
  "- **禁止插补**：HAMD / HAMA / CSSRS、家族史原列、MASS 第 1-8 题原列",
  "- **可插补**：合成列和其余基线协变量中缺失率 < 0.4 的列",
  "- mice：method=cart，m=5，complete_action=1，seed=40595747",
  "",
  paste0("- **n = ", nrow(dabiao), "**（人数不变；只填协变量缺失）"),
  paste0("- MICE 变量数 = ", length(mice_vars)),
  paste0("- 冻结量表列数 = ", length(scale_cols)),
  "",
  "## 产物",
  "",
  "| 文件 | 说明 |",
  "|------|------|",
  "| `dabiao.RData` | 插补后分析表 |",
  "| `Tables/*.xlsx` | SCI 三线表（插补前后缺失 / MICE 变量 / 禁插补等） |",
  "| `mice_vars.csv` | 实际进入 MICE 的列（中间文件） |",
  "| `excluded_from_mice.csv` | 禁止插补列（中间文件） |",
  "| `missing_before_after.csv` | 插补前后缺失（中间文件） |",
  "| `imputation_note.txt` | 运行备注 |",
  "",
  paste0("写入时间：", meta$written_at)
)
writeLines(readme, file.path(step_dir, "README.md"), useBytes = TRUE)

# SCI three-line tables → step02_imputation/Tables/
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)
.table_queue_env$items <- list()
suicide_clpm_export_step02_tables(step_dir, n = nrow(dabiao))
suicide_clpm_flush_sci_tables()
message("[step02_imputation] SCI tables → ", file.path(step_dir, "Tables"))

message("[step02_imputation] OK n=", nrow(dabiao), " mice_vars=", length(mice_vars))
message("[step02_imputation] wrote ", step_dir)
message("[step02_imputation] synced ", harm_imp)
print(miss_ba, row.names = FALSE)
