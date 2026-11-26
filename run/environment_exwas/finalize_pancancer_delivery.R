#!/usr/bin/env Rscript
# 泛癌毒物 ExWAS 交付收口（引擎级）
# 1) pub_digits（文献三位 OR/P/q）
# 2) 展示禁下划线 + Times（pub_delivery_scrub_display）
# 3) Methods md + 软件版本 txt（无迁移复现措辞）
# 4) 图 pdf/ + image_information；白名单 prune
# 5) 可选结构 QC 写入同级 *_delivery_workspace
#
#   Rscript run/environment_exwas/finalize_pancancer_delivery.R \
#     --dir /mnt/g/02block_result/58_cancer/environment_41380607/summary_results
#
opt <- list(
  dir = "/mnt/g/02block_result/58_cancer/environment_41380607/summary_results",
  project = "/mnt/g/02block_result/58_cancer/environment_41380607",
  midterm_pdf = "",
  run_struct_qc = TRUE
)
args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  paste(args[(hit[[1]] + 1L):length(args)][seq_len(which(c(grepl("^--", args[(hit[[1]] + 1L):length(args)]), TRUE))[1] - 1L)], collapse = " ")
}
# simpler get
.pick <- function(flag, default) {
  i <- which(args == flag)
  if (!length(i) || i[1] >= length(args)) return(default)
  args[[i[1] + 1L]]
}
opt$dir <- .pick("--dir", opt$dir)
opt$project <- .pick("--project", opt$project)
opt$midterm_pdf <- .pick("--midterm-pdf", opt$midterm_pdf)
if ("--no-qc" %in% args) opt$run_struct_qc <- FALSE

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
Sys.setenv(MEDICAL_BLOCKS_ROOT = repo)

source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/exwas_pub_digits.R"))
source(file.path(repo, "R/pub_exwas_methods.R"))
source(file.path(repo, "R/pub_delivery_prune.R"))
source(file.path(repo, "R/pub_figure_export.R"))
source(file.path(repo, "R/pub_software_versions.R"))
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}

sr <- normalizePath(opt$dir, winslash = "/", mustWork = TRUE)
message("[exwas-finalize] ", sr)

cfg <- exwas_apply_pub_digits(list())

# 1) scrub display (underscore + Times on xlsx; image md)
if (exists("pub_delivery_scrub_display", mode = "function")) {
  tryCatch(
    pub_delivery_scrub_display(sr, root = repo),
    error = function(e) warning("scrub_display: ", conditionMessage(e), call. = FALSE)
  )
}

# 2) Methods + software（覆盖）
n_total <- 11098L; n_cases <- 1070L; n_exp <- 63L; n_fam <- 9L
t1 <- file.path(sr, "Tables", "Table 1. Baseline characteristics by cancer status.xlsx")
# keep defaults; optional parse skipped for robustness
exwas_write_methods_md(
  file.path(sr, "Methods_statistical_analysis.md"),
  n_total = n_total, n_cases = n_cases, n_exp = n_exp, n_fam = n_fam
)
# ExWAS 专用软件清单（勿用预后模板 pub_write_software_versions 覆盖）
exwas_write_software_versions(file.path(sr, "Methods_software_versions.txt"))
# Append Software section into Methods md if missing
.md <- file.path(sr, "Methods_statistical_analysis.md")
.soft <- file.path(sr, "Methods_software_versions.txt")
if (file.exists(.md) && file.exists(.soft)) {
  md_txt <- readLines(.md, warn = FALSE)
  if (!any(grepl("^## Software", md_txt))) {
    soft_lines <- readLines(.soft, warn = FALSE)
    writeLines(c(md_txt, "", "## Software", soft_lines), .md)
  }
}

# 3) figure formats (PDF + image_information only)
if (exists("pub_figure_ensure_formats", mode = "function")) {
  tryCatch(
    pub_figure_ensure_formats(
      file.path(sr, "Figures"),
      config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))
    ),
    error = function(e) warning("ensure_formats: ", conditionMessage(e), call. = FALSE)
  )
}

# 4) midterm：可选传入已生成 PDF；否则写项目信息模板供中期引擎使用（封面默认无日期）
info <- file.path(sr, "项目信息-中期.md")
if (!file.exists(info)) {
  writeLines(c(
    "客户: 殷毓阳",
    "暴露指标: 环境毒物暴露组（ExWAS / ERS）",
    "结局: 泛癌（既往癌症史，MCQ220）",
    "研究人群: NHANES 成年参与者（≥20 岁）",
    "数据集: NHANES",
    "分析方法: ExWAS、环境风险评分、混合物加权分位数和、探索性中介",
    "类型: 中期分析结果",
    "标题副题: 无",
    "报告标题: 环境毒物暴露组与泛癌关联的 ExWAS 分析",
    "分析日期: 无"
  ), info)
}
if (nzchar(opt$midterm_pdf) && file.exists(opt$midterm_pdf)) {
  file.copy(opt$midterm_pdf, file.path(sr, basename(opt$midterm_pdf)), overwrite = TRUE)
}

# 5) prune whitelist
if (exists("pub_prune_delivery_root", mode = "function")) {
  pub_prune_delivery_root(sr)
} else if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
  pub_delivery_normalize_fig_tab_dirs(sr)
}

# 6) struct QC → workspace
if (isTRUE(opt$run_struct_qc)) {
  qc <- file.path(repo, "run/pub/run_pub_qc_after_project.R")
  ws <- paste0(sr, "_delivery_workspace")
  dir.create(ws, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(qc)) {
    out <- tryCatch(
      system2("Rscript", c(qc, "--project", opt$project), stdout = TRUE, stderr = TRUE),
      error = function(e) conditionMessage(e)
    )
    writeLines(as.character(out), file.path(ws, "pub_qc_stdout.txt"))
  }
}

message("[exwas-finalize] DONE")
message("[exwas-finalize] root listing:")
print(list.files(sr))
