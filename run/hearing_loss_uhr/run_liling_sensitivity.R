#!/usr/bin/env Rscript
# Liling UHR 敏感性：与 dual sensitivity_suite 同场景、同协变量锁、同 Table1 顺序
# 产物：by_index/【success】UHR/sensitivity/<label>/Liling/
suppressPackageStartupMessages({
  library(cli)
})

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
script_dir <- .init_script_dir()
root <- if (basename(dirname(script_dir)) == "run") {
  normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
} else {
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(root)

study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
cfg_path <- file.path(study, "config_incidence_liling.R")
parent <- file.path(study, "by_index", "【success】UHR")
src_ck_dir <- file.path(study, "checkpoints", "Liling_UHR")
src_index <- file.path(src_ck_dir, "index.rds")
if (!file.exists(src_index)) stop("缺少 Liling shared/index ck: ", src_index)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

source(file.path(study, "config_incidence_dual_batch.R"))
sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
age_cut <- as.integer(sens$age_cutoff %||% 65L)
scenarios <- sens$scenarios %||% list()
scenarios <- lapply(scenarios, function(sg) {
  list(
    label = gsub("\\{age_cutoff\\}", as.character(age_cut), sg$label),
    expr  = gsub("\\{age_cutoff\\}", as.character(age_cut), sg$expr)
  )
})
rm(config)

alias_df <- function(df) {
  if (is.null(df) || !is.data.frame(df)) return(df)
  if ("T2DM" %in% names(df) && !"Diabetes" %in% names(df)) df$Diabetes <- df$T2DM
  if ("Diabetes" %in% names(df) && !"T2DM" %in% names(df)) df$T2DM <- df$Diabetes
  df
}

for (sg in scenarios) {
  label <- sg$label
  expr  <- sg$expr
  dst_parent <- file.path(parent, "sensitivity", label)
  dst <- file.path(dst_parent, "Liling")
  status_path <- file.path(dst, "_liling_sa_status.json")
  if (file.exists(status_path)) {
    st <- tryCatch(jsonlite::fromJSON(status_path), error = function(e) NULL)
    if (!is.null(st) && identical(st$status, "success")) {
      cli::cli_alert_info("[Liling/{label}] 已成功，跳过")
      next
    }
  }

  cli::cli_h1("Liling 敏感性: {label}")
  cli::cli_alert_info("过滤: {expr}")

  # 临时 ck / 输出
  sa_ck <- file.path(study, "checkpoints", "by_index_sensitivity", "UHR", label, "Liling")
  if (dir.exists(sa_ck)) unlink(sa_ck, recursive = TRUE)
  dir.create(sa_ck, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(src_ck_dir, full.names = TRUE), sa_ck, recursive = TRUE)

  # 别名 + 亚组过滤
  ck_path <- file.path(sa_ck, "index.rds")
  obj <- readRDS(ck_path)
  for (slot in names(obj$ctx$data)) {
    if (is.data.frame(obj$ctx$data[[slot]]))
      obj$ctx$data[[slot]] <- alias_df(obj$ctx$data[[slot]])
  }
  saveRDS(obj, ck_path)
  incidence_batch_apply_subgroup_filter(ck_path, expr, "UHR")

  obj <- readRDS(ck_path)
  df <- obj$ctx$data$imputed %||% obj$ctx$data$mapped %||% obj$ctx$data$cleaned
  n_after <- if (is.data.frame(df)) nrow(df) else NA_integer_
  if (is.na(n_after) || n_after < 50L) {
    cli::cli_alert_warning("[Liling/{label}] 样本不足 n={n_after}，跳过")
    next
  }

  # 输出目录
  if (dir.exists(dst)) unlink(dst, recursive = TRUE)
  dir.create(dst, recursive = TRUE, showWarnings = FALSE)

  # 加载 liling config 并覆盖 ck / 输出 / lock
  source(cfg_path)
  config$project$output_dir <- dst
  config$incidence$index_var <- "UHR"
  if (!is.null(config$logistic)) config$logistic$index_var <- "UHR"
  if (!is.null(config$index)) {
    config$index$enable <- TRUE
    config$index$only <- "UHR"
  }
  if (exists(".table1_vars") && length(.table1_vars)) {
    config$baseline_binary$include_vars <- as.character(.table1_vars)
  }
  if (!is.null(config$column_mapping)) config$column_mapping$enable <- TRUE
  if (!is.null(config$baseline_binary)) config$baseline_binary$early_stop_if_index_ns <- FALSE
  for (.lg in c("logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
                "logistic_quartile", "logistic_tertile", "logistic_binary")) {
    if (!is.null(config[[.lg]])) {
      config[[.lg]]$gate_enable <- FALSE
      config[[.lg]]$stop_if_crude_all_ns <- FALSE
      config[[.lg]]$stop_if_crude_highest_ns <- FALSE
    }
  }
  # 与 dual SA 一致：排除高血压 → Model2 去 Hypertension；年龄分层 → 亚组去掉 Age_Group
  if (grepl("no_hypertension", label, ignore.case = TRUE)) {
    .drop_sg <- function(x) setdiff(as.character(x %||% character(0)), "Hypertension")
    if (!is.null(config$subgroup)) {
      config$subgroup$required_subgroup_vars <- .drop_sg(config$subgroup$required_subgroup_vars)
      config$subgroup$locked_subgroup_vars <- .drop_sg(config$subgroup$locked_subgroup_vars)
    }
    .m2_sa <- setdiff(as.character(.m2), "Hypertension")
    if (!length(.m2_sa)) .m2_sa <- c("Age", "WBC")
    for (nm in names(config)) {
      if (is.list(config[[nm]]) && !is.null(config[[nm]]$model2_factors)) {
        config[[nm]]$model2_factors <- .m2_sa
        if (!is.null(config[[nm]]$model1_factors))
          config[[nm]]$model1_factors <- as.character(.m1)
      }
    }
  }
  if (grepl("age_(ge|lt)_", label, ignore.case = TRUE)) {
    .drop_age <- function(x) setdiff(as.character(x %||% character(0)), c("Age_Group", "Age"))
    if (!is.null(config$subgroup)) {
      config$subgroup$required_subgroup_vars <- .drop_age(config$subgroup$required_subgroup_vars)
      config$subgroup$locked_subgroup_vars <- .drop_age(config$subgroup$locked_subgroup_vars)
    }
  }
  pipeline$checkpoint$dir <- sa_ck
  pipeline$dual_db <- list(enable = FALSE)

  log_path <- file.path(dst_parent, paste0("liling_", label, ".log"))
  ok <- FALSE
  tryCatch({
    run_pipeline(root, config = config, pipeline = pipeline,
                 run_opts = list(from = "index"))
    ok <- TRUE
  }, error = function(e) {
    cli::cli_alert_danger("[Liling/{label}] 失败: {e$message}")
    writeLines(conditionMessage(e), log_path)
  })

  jsonlite::write_json(
    list(status = if (ok) "success" else "failed", label = label, n_after = n_after,
         model1 = as.character(.m1), model2 = as.character(.m2),
         table1_vars = as.character(.table1_vars), finished_at = as.character(Sys.time())),
    status_path, auto_unbox = TRUE, pretty = TRUE
  )
  if (ok) cli::cli_alert_success("[Liling/{label}] 完成 n={n_after}")
}

cli::cli_alert_success("Liling 敏感性全部场景处理完毕")
