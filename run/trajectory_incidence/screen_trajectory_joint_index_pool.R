#!/usr/bin/env Rscript
# screen_trajectory_joint_index_pool.R — 联合轨迹发病 指标池可算性预检（Gate 1）
# 用法:
#   Rscript run/trajectory_incidence/screen_trajectory_joint_index_pool.R --config <cfg.R>
# 输出:
#   <Output>/reports/tj_index_screen_<db>.md   逐波覆盖 + 成分缺失 + 建议入池对
# 逻辑:
#   1) 载入 master 宽表（或 config$data$rawdata_path）
#   2) 候选复合指标池 = config$joint_trajectory$index_pool_candidates（NULL → 从 index_pairs 展开）
#   3) 每指标每波：按 00_index 公式可算率；基线波成分缺失 n
#   4) Gate 0：disease_vars 成分整指标剔除
#   铁律联动：trajectory_joint_index_screening

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- if (basename(dirname(script_path)) == "run")
  normalizePath(file.path(script_path, "..", ".."), winslash = "/") else script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
i <- match("--config", args)
if (!is.na(i) && i < length(args)) {
  config_path <- normalizePath(args[i + 1L], winslash = "/")
} else {
  config_path <- file.path(root, "configs/templates/config_trajectory_incidence_joint.template.R")
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/literature_trajectory_joint.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

bl <- config$joint_trajectory %||% stop("缺 config$joint_trajectory")
waves <- as.integer(bl$waves)
sfx <- bl$wave_suffix %||% "_w"
id_col <- bl$id_column %||% config$data$id_column %||% "id"
db <- config$project$database %||% "STUDY"

df <- if (!is.null(config$data$rawdata_path) && file.exists(config$data$rawdata_path)) {
  e <- new.env(parent = emptyenv())
  load(config$data$rawdata_path, envir = e)
  as.data.frame(e[[config$data$rawdata_obj %||% "master"]])
} else stop("缺原始宽表")

cand <- unique(as.character(bl$index_pool_candidates %||% unlist(bl$index_pairs)))
cand <- cand[nzchar(cand)]

# Gate 0：疾病派生指标剔除
.idx_path <- file.path(root, "Blocks/00_index/01block_index.R")
if (file.exists(.idx_path)) source(.idx_path, local = FALSE)
dv <- as.character((config$analysis_exclusion %||% list())$disease_vars %||% character(0))
drop_ix <- character(0)
if (length(dv) && exists("pipeline_indices_using_vars", mode = "function")) {
  drop_ix <- tryCatch(pipeline_indices_using_vars(dv), error = function(e) character(0))
}
cand_pool <- setdiff(cand, drop_ix)

lines <- c(sprintf("# 联合轨迹发病 指标池可算性预检 (%s) %s", db, format(Sys.time())), "",
  sprintf("- 轨迹波次: %s", paste(waves, collapse = ", ")),
  sprintf("- Gate 0 disease_vars: %s", paste(dv, collapse = ", ")),
  sprintf("- 因疾病成分整指标剔除: %s", if (length(drop_ix)) paste(drop_ix, collapse = ", ") else "(无)"),
  "")
lines <- c(lines, "| index | 成分 | 各波可算率 | 基线缺失 n | 建议 |", "|---|---|---|---|---|")

dmap <- if (exists("pipeline_index_definition_map", mode = "function")) pipeline_index_definition_map() else NULL

# 迭代逐层计算复合指标列（成分本身可能是另一指标，如 ABSI←BMI）。
# 每轮尝试所有未算指标；某指标各波列全生成 → 成功；一轮无任何进展 → 剩余不可算。
df_work <- df
computed <- character(0)
repeat {
  progressed <- FALSE
  for (ix2 in setdiff(cand_pool, computed)) {
    suppressWarnings(suppressMessages(
      ok <- tj_calc_index_waves(df_work, ix2, waves, wave_suffix = sfx, root = root)))
    cols2 <- paste0(ix2, sfx, waves)
    if (!is.null(ok) && all(cols2 %in% names(ok))) {
      df_work <- ok; computed <- c(computed, ix2); progressed <- TRUE
    }
  }
  if (!progressed) break
}

comp_txt_of <- function(ix) {
  if (is.null(dmap) || is.null(dmap[[ix]])) return("-")
  paste(all.vars(stats::as.formula(paste0("~", dmap[[ix]]))), collapse = "+")
}
pass_pool <- character(0)
for (ix in cand_pool) {
  comp_txt <- comp_txt_of(ix)
  if (!(ix %in% computed)) {
    lines <- c(lines, sprintf("| %s | %s | 公式/成分不可算 | — | 剔除 |", ix, comp_txt)); next
  }
  cols <- paste0(ix, sfx, waves)
  cov <- vapply(cols, function(cn) if (cn %in% names(df_work)) mean(!is.na(df_work[[cn]])) else NA_real_, numeric(1))
  cov_txt <- paste(sprintf("w%d=%.1f%%", waves, 100 * ifelse(is.na(cov), 0, cov)), collapse = " ")
  n0miss <- if (cols[1] %in% names(df_work)) sum(is.na(df_work[[cols[1]]])) else nrow(df_work)
  ok_cov <- sum(!is.na(cov) & cov >= 0.5) >= 2L
  if (ok_cov) pass_pool <- c(pass_pool, ix)
  lines <- c(lines, sprintf("| %s | %s | %s | %d | %s |", ix, comp_txt,
    cov_txt, n0miss, if (ok_cov) "入池候选" else "覆盖不足，剔除"))
}
lines <- c(lines, "",
  "## Gate 2（人工）",
  "每对候选须在 PubMed 检索 疾病×A、疾病×B、疾病×A+B（近15年），命中/Exploratory 分级后",
  "由用户确认 config$joint_trajectory$index_pairs。", "")
if (length(pass_pool) >= 2L) {
  pair_txt <- vapply(utils::combn(pass_pool, 2L, simplify = FALSE),
                     function(p) paste(p, collapse = " x "), character(1))
  lines <- c(lines, sprintf("候选配对（覆盖通过 %d 对）：%s", length(pair_txt),
                            paste(pair_txt, collapse = " | ")))
} else {
  lines <- c(lines, "候选配对：覆盖通过指标不足 2 个，无法成对，须回到 Gate 1 换指标或波次。")
}

out_dir <- file.path(config$project$output_dir %||% "Output", "reports")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out <- file.path(out_dir, paste0("tj_index_screen_", tolower(db), ".md"))
writeLines(lines, out)
cli::cli_alert_success("指标池预检落盘: {out}")
cat(paste(lines, collapse = "\n"), "\n")
