#!/usr/bin/env Rscript
# 修复听力 UHR 三库汇总：从 archive 恢复有效表/图 → Liling 改 Single → 三库 aggregate + summary_result
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
if (!dir.exists(study)) study <- "G:/02block_result/15_hearing_loss/incidence_38341157"

arc <- file.path(study, "_archive/by_index_before_unify_20260729_134507")
arc_success <- file.path(arc, "【success】UHR")
arc_lil <- file.path(arc, "UHR", "Liling")

success_dir <- file.path(study, "by_index", "【success】UHR")
copy_dir <- file.path(study, "by_index", "【success】UHR - 副本")

stopifnot(dir.exists(arc_success), dir.exists(arc_lil))

rename_liling_to_single <- function(path) {
  gsub("Liling", "Single", path, fixed = TRUE)
}

rename_tree <- function(dir_path) {
  if (!dir.exists(dir_path)) return(invisible())
  # depth-first: rename files then dirs
  entries <- list.files(dir_path, full.names = TRUE, recursive = FALSE, all.files = TRUE, no.. = TRUE)
  for (e in entries) {
    if (dir.exists(e)) rename_tree(e)
  }
  for (e in entries) {
    if (!file.exists(e) && !dir.exists(e)) next
    new_e <- rename_liling_to_single(e)
    if (!identical(e, new_e) && !file.exists(new_e)) {
      file.rename(e, new_e)
    }
  }
  parent_new <- rename_liling_to_single(dir_path)
  if (!identical(dir_path, parent_new) && dir.exists(dir_path) && !dir.exists(parent_new)) {
    file.rename(dir_path, parent_new)
  }
  invisible(parent_new)
}

cp_dir <- function(src, dest) {
  if (!dir.exists(src)) stop("missing: ", src)
  if (dir.exists(dest)) unlink(dest, recursive = TRUE, force = TRUE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(from = src, to = dirname(dest), recursive = TRUE, copy.mode = TRUE)
  # file.copy 会把 src 拷到 dirname(dest)/basename(src)
  staged <- file.path(dirname(dest), basename(src))
  if (dir.exists(staged) && !identical(staged, dest)) {
    file.rename(staged, dest)
  }
  if (!dir.exists(dest)) {
    # fallback: shell cp -a（9p 网络盘更稳）
    cmd <- sprintf("cp -a %s %s", shQuote(src), shQuote(dest))
    ok2 <- system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
    if (ok2 != 0L || !dir.exists(dest)) stop("copy failed: ", src, " -> ", dest)
  }
  invisible(dest)
}

cp_xlsx_dir <- function(src_tab, dest_tab, skip_mv = TRUE) {
  dir.create(dest_tab, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(src_tab, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  for (f in files) {
    bn <- basename(f)
    if (isTRUE(skip_mv) && grepl("Multivariable|VIF, multivariate", bn, ignore.case = TRUE)) next
    dest <- file.path(dest_tab, rename_liling_to_single(bn))
    file.copy(f, dest, overwrite = TRUE)
  }
}

cp_fig_dir <- function(src_fig, dest_fig) {
  dir.create(dest_fig, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(src_fig)) return(invisible(0L))
  files <- list.files(src_fig, pattern = "\\.(pdf|png)$", full.names = TRUE, ignore.case = TRUE, recursive = TRUE)
  n <- 0L
  for (f in files) {
    bn <- rename_liling_to_single(basename(f))
    dest <- file.path(dest_fig, bn)
    if (file.exists(dest)) next
    file.copy(f, dest, overwrite = TRUE)
    n <- n + 1L
  }
  invisible(n)
}

cli::cli_h1("1/5 从 archive 恢复 【success】UHR")
cp_dir(arc_success, success_dir)

cli::cli_h1("2/5 恢复 Single 库（原 Liling）")
single_src_tmp <- file.path(study, "by_index", ".tmp_liling_restore")
cp_dir(arc_lil, single_src_tmp)
single_dir <- file.path(success_dir, "Single")
if (dir.exists(single_dir)) unlink(single_dir, recursive = TRUE, force = TRUE)
file.rename(single_src_tmp, single_dir)
rename_tree(single_dir)

cli::cli_h1("3/5 合并三库 Tables / Figures 到指标根")
agg_tab <- file.path(success_dir, "Tables")
agg_fig <- file.path(success_dir, "Figures")
dir.create(agg_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(agg_fig, recursive = TRUE, showWarnings = FALSE)

for (db in c("NHANES", "CHARLS")) {
  cp_xlsx_dir(file.path(success_dir, db, "Tables"), agg_tab, skip_mv = TRUE)
}
cp_xlsx_dir(file.path(single_dir, "Tables"), agg_tab, skip_mv = TRUE)

for (db in c("NHANES", "CHARLS")) {
  cp_fig_dir(file.path(success_dir, db, "Figures"), agg_fig)
}
cp_fig_dir(file.path(single_dir, "Figures"), agg_fig)

# 清理 0 字节残留
zempty <- list.files(success_dir, pattern = "\\.(xlsx|pdf|png)$", full.names = TRUE, recursive = TRUE)
zempty <- zempty[file.info(zempty)$size == 0]
if (length(zempty)) {
  unlink(zempty)
  cli::cli_alert_info("已删除 {length(zempty)} 个 0 字节残留")
}

cli::cli_h1("4/5 finalize 发表图 + 编号对齐")
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
Sys.setenv(STUDY_CONFIG_DIR = study)
source(file.path(study, "config_incidence_dual_batch.R"))

if (!exists("export_pub_figures", mode = "function")) {
  source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
}
tryCatch(
  export_pub_figures(
    agg_fig,
    meta = list(
      exposure = "UHR",
      outcome = "Hearing Loss",
      databases = c("NHANES", "CHARLS", "Single"),
      combined = TRUE,
      grouping = "quartile"
    ),
    config = config
  ),
  error = function(e) cli::cli_alert_warning("export_pub_figures: {e$message}")
)

align <- file.path(root, "run/hearing_loss_uhr/align_numbering_to_mafld.R")
if (file.exists(align)) {
  tryCatch(
    source(align, local = FALSE),
    error = function(e) cli::cli_alert_warning("align_numbering: {e$message}")
  )
}

cli::cli_h1("5/5 同步副本 + summary_result")
if (dir.exists(copy_dir)) unlink(copy_dir, recursive = TRUE, force = TRUE)
cp_ok <- system(sprintf("cp -a %s %s", shQuote(success_dir), shQuote(copy_dir)), ignore.stdout = TRUE)
if (cp_ok != 0L || !dir.exists(copy_dir)) stop("copy to 副本 failed")

collect_sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(collect_sh)) {
  system2("bash", c(collect_sh, study), stdout = TRUE, stderr = TRUE)
}

# 验收
t2 <- list.files(agg_tab, pattern = "^Table 2", full.names = TRUE)
need_dbs <- c("NHANES", "CHARLS", "Single")
have <- vapply(need_dbs, function(db) any(grepl(paste0("-", db, "\\."), basename(t2))), logical(1))
cli::cli_alert_info("Table2 bytes: {paste(basename(t2), file.info(t2)$size, sep='=', collapse='; ')}")
if (!all(have)) stop("Table 2 缺少库: ", paste(need_dbs[!have], collapse = ", "))
if (any(file.info(t2)$size < 1000)) stop("Table 2 仍有空文件")

sum_tab <- file.path(study, "summary_result/table")
sum_fig <- file.path(study, "summary_result/figure")
cli::cli_alert_success(
  "完成: aggregate tables={length(list.files(agg_tab, pattern='xlsx'))} figures={length(list.files(agg_fig, pattern='pdf', recursive=TRUE))} | summary table={length(list.files(sum_tab))} figure={length(list.files(sum_fig))}"
)
