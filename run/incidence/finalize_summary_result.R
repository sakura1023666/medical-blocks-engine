#!/usr/bin/env Rscript
# 发病/预后 dual-batch → summary_result 收口（引擎级 CLI）
#
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/incidence/finalize_summary_result.R \
#     --project /mnt/g/02block_result/22_depression/incidence_38341157 \
#     [--index Periodontitis] [--redraw-fig1] [--config path/to/config.R]
#
# 行为：
#   1) 可选：按 Cataract/pv2 版式重画指标 Figure 1（旧竖链强制升级）
#   2) 敏感性附表晋升：优先 SA_complete_case（可要求 Model2 显著）；
#      完整病例失败/不显著则回退任选一个【success】SA_*，并入 summary Tables
#   3) 拷贝 Figures 四目录；写 Methods_statistical_analysis.md + Methods_software_versions.txt
#   4) pub_figure_ensure_formats（dpi≥600）
#   5) pub_prune_delivery_root：交付根只留 Figures/Tables/Methods md/软件版本 txt/中期 PDF
#      （summary_result 与 summary_results 同口径；仅当显式
#       config$pub$tables_figures_only=TRUE 时才只留 Figures+Tables）

suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
})

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
.has <- function(flag) !is.na(match(flag, args))

engine <- {
  cands <- c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", ""),
    "E:/01block/01Block-new-Final",
    "/mnt/e/01block/01Block-new-Final"
  )
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  if (!length(hit)) stop("MEDICAL_BLOCKS_ROOT not found")
  hit[[1L]]
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
if (!nzchar(Sys.getenv("MEDICAL_BLOCKS_PYTHON", "")) && file.exists("/usr/bin/python3")) {
  Sys.setenv(MEDICAL_BLOCKS_PYTHON = "/usr/bin/python3")
}

proj <- .arg("--project", "")
if (!nzchar(proj) || !dir.exists(proj)) {
  stop("--project <课题产出根> 必填且目录须存在", call. = FALSE)
}
ix <- .arg("--index", NULL)
cfg_path <- .arg("--config", NULL)
redraw_fig1 <- .has("--redraw-fig1") || .has("--force-fig1")

for (rel in c(
  "R/utils.R",
  "R/attrition_log.R",
  "R/pub_software_versions.R",
  "R/pub_figure_export.R",
  "R/pub_delivery_prune.R",
  "R/incidence_summary_result.R",
  "R/incidence_dual_batch_runner.R"
)) {
  p <- file.path(engine, rel)
  if (file.exists(p)) source(p, local = FALSE)
}

config <- list()
if (!is.null(cfg_path) && nzchar(cfg_path) && file.exists(cfg_path)) {
  env <- new.env(parent = globalenv())
  sys.source(cfg_path, envir = env)
  if (exists("config", envir = env, inherits = FALSE)) {
    config <- get("config", envir = env, inherits = FALSE)
  }
}
if (!is.list(config$pub)) config$pub <- list()
config$pub$summary_result <- TRUE
config$pub$include_sa_complete_case <- TRUE
# 默认：完整病例须 Model2 双库显著才优先；否则引擎回退其它成功 SA
config$pub$sa_complete_case_require_sig <- isTRUE(
  config$pub$sa_complete_case_require_sig %||% TRUE
)
sum_name <- as.character(config$pub$summary_dirname %||% "summary_result")[1L]
# 全项目默认完整交付白名单（含 Methods + 软件版本）；勿因目录名 summary_results
# 自动降级为仅图表（cute_ran 2026-10 踩坑）
tf_only <- isTRUE(config$pub$tables_figures_only %||% FALSE)

by_ix <- file.path(proj, "by_index")
success_dirs <- character(0)
if (dir.exists(by_ix)) {
  all_ok <- list.files(by_ix, pattern = "^\u3010success\u3011", full.names = TRUE)
  if (!is.null(ix) && nzchar(as.character(ix)[1L])) {
    want <- paste0("\u3010success\u3011", as.character(ix)[1L])
    success_dirs <- all_ok[basename(all_ok) == want]
  } else {
    success_dirs <- all_ok
  }
}
if (!length(success_dirs)) {
  stop("未找到【success】指标目录: ", by_ix, call. = FALSE)
}

# 默认对 legacy Fig1 升级为 Cataract/pv2；--redraw-fig1 强制重画
for (ix_root in success_dirs) {
  f1_cands <- c(
    file.path(ix_root, "Figures", "Figure 1. Flowchart.pdf"),
    file.path(ix_root, "Figures", "pdf", "Figure 1. Flowchart.pdf")
  )
  f1_cands <- f1_cands[file.exists(f1_cands)]
  is_legacy <- length(f1_cands) == 0L ||
    any(vapply(f1_cands, function(p) {
      exists("incidence_batch_figure1_is_legacy_style", mode = "function") &&
        isTRUE(incidence_batch_figure1_is_legacy_style(p))
    }, logical(1L)))
  force_one <- isTRUE(redraw_fig1) || isTRUE(is_legacy)
  if (!isTRUE(force_one)) next
  cli::cli_h2("Redraw Figure 1 (pv2): {basename(ix_root)}")
  ok <- FALSE
  if (exists("incidence_batch_write_flowchart_from_attrition_csv", mode = "function")) {
    ok <- isTRUE(tryCatch(
      incidence_batch_write_flowchart_from_attrition_csv(
        index_root = ix_root,
        config = config,
        db_seq = NULL,
        ix = sub("^\u3010success\u3011", "", basename(ix_root)),
        force = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning(e$message)
        FALSE
      }
    ))
  }
  if (isTRUE(ok) && exists("pub_figure_ensure_formats", mode = "function")) {
    fig_root <- file.path(ix_root, "Figures")
    f1 <- file.path(fig_root, "Figure 1. Flowchart.pdf")
    pdf_dir <- file.path(fig_root, "pdf")
    if (file.exists(f1) && dir.exists(pdf_dir)) {
      file.copy(f1, file.path(pdf_dir, "Figure 1. Flowchart.pdf"), overwrite = TRUE)
    }
    tryCatch(
      pub_figure_ensure_formats(fig_root, config = config),
      error = function(e) cli::cli_alert_warning("四目录刷新: {e$message}")
    )
  }
}

# 指标级 summary_results（by_index/【success】*/summary_results）优先
if (!exists("ml_index_summary_results_enabled", mode = "function")) {
  mir <- file.path(engine, "R", "ml_index_summary_results.R")
  if (file.exists(mir)) source(mir, local = FALSE)
}
use_index_sum <- exists("ml_index_summary_results_enabled", mode = "function") &&
  isTRUE(ml_index_summary_results_enabled(config))

res <- list(ok = NA, summary_root = NA_character_, n_tables = NA_integer_)
if (isTRUE(use_index_sum)) {
  cli::cli_h1("指标级 summary_results → by_index/【success】*/{sum_name}")
  for (ix_root in success_dirs) {
    ix_nm <- sub("^\u3010success\u3011", "", basename(ix_root))
    # 先晋升敏感性附表到指标 Tables，再 sync 到 summary_results
    if (exists("incidence_promote_sensitivity_for_summary", mode = "function")) {
      tryCatch(
        incidence_promote_sensitivity_for_summary(
          ix_root,
          require_model2_sig = isTRUE(config$pub$sa_complete_case_require_sig %||% TRUE)
        ),
        error = function(e) cli::cli_alert_warning("敏感性晋升跳过: {e$message}")
      )
    }
    if (exists("ml_finalize_index_summary_results", mode = "function")) {
      sum_p <- tryCatch(
        ml_finalize_index_summary_results(
          ix_root,
          config = config,
          figures_tables_only = tf_only
        ),
        error = function(e) {
          cli::cli_alert_danger(e$message)
          NULL
        }
      )
      if (!is.null(sum_p)) {
        res$summary_root <- sum_p
        res$n_tables <- length(list.files(file.path(sum_p, "Tables"), pattern = "\\.xlsx$"))
        res$ok <- TRUE
        cli::cli_alert_success("指标交付: {sum_p}")
      }
    } else {
      cli::cli_alert_warning("未加载 ml_finalize_index_summary_results")
    }
  }
} else {
  cli::cli_h1("summary: {proj} → {sum_name}")
  res <- incidence_finalize_summary_result(
    project_root = proj,
    config = config,
    index = if (!is.null(ix) && nzchar(as.character(ix)[1L])) as.character(ix)[1L] else NULL,
    include_sa_complete_case = TRUE,
    summary_dirname = sum_name,
    tables_figures_only = tf_only
  )
}

# 指标根也落一份软件版本（与 finalize 挂点一致）
if (exists("pub_write_software_versions", mode = "function")) {
  for (ix_root in success_dirs) {
    tryCatch(
      pub_write_software_versions(
        index_root = ix_root, project_root = proj, config = config
      ),
      error = function(e) NULL
    )
  }
}

cli::cli_alert_success(
  "Done: summary_root={res$summary_root %||% NA}; n_tables={res$n_tables %||% NA}"
)
invisible(res)
