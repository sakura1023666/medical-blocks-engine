###############################################################################
#  mediation_subgroup_router — 按暴露路由批量中介/亚组
#
#  register_block: "mediation_subgroup_router"
#  exposure_mode:
#    - primary_only（默认 / auto）：只跑主暴露
#    - all_ml_features：对最终 ML 特征逐一运行（纯 ML 项目）
###############################################################################

block_mediation_subgroup_router <- function(ctx, ...) {
  cfg <- ctx$config %||% list()
  bl <- cfg$mediation_subgroup %||% cfg$capability$mediation_subgroup %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("mediation_subgroup_router: enable=FALSE，跳过。")
    return(ctx)
  }

  route <- if (exists("pipeline_resolve_exposure_targets", mode = "function")) {
    pipeline_resolve_exposure_targets(ctx)
  } else {
    list(mode = "primary_only", exposures = character(0), primary = character(0))
  }
  exposures <- unique(as.character(route$exposures %||% character(0)))
  exposures <- exposures[nzchar(exposures)]
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.null(data)) exposures <- intersect(exposures, names(data))

  if (!length(exposures)) {
    cli::cli_alert_warning(
      "mediation_subgroup_router: 无暴露目标（mode={route$mode}）。纯 ML 请设 exposure_mode=all_ml_features 并确保已完成特征选择。"
    )
    return(ctx)
  }

  study_type <- tolower(trimws(as.character(cfg$project$study_type %||% "incidence")[1L]))
  run_mediation <- isTRUE(bl$run_mediation %||% TRUE)
  run_subgroup <- isTRUE(bl$run_subgroup %||% TRUE)

  # 预后中介进入标准预后流水线接线
  if (identical(study_type, "prognosis") || isTRUE(bl$force_prognosis %||% FALSE)) {
    med_fun <- if (exists("block_mediation_prognosis", mode = "function")) block_mediation_prognosis else NULL
    sub_fun <- if (exists("block_subgroup_prognosis", mode = "function")) block_subgroup_prognosis else NULL
  } else {
    med_fun <- if (exists("block_mediation_incidence", mode = "function")) block_mediation_incidence else NULL
    sub_fun <- if (exists("block_subgroup_incidence", mode = "function")) block_subgroup_incidence else NULL
  }

  # 若函数尚未注册，尝试 source
  root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  if (is.null(med_fun) && run_mediation) {
    fp <- if (identical(study_type, "prognosis") || isTRUE(bl$force_prognosis %||% FALSE)) {
      file.path(root, "Blocks/20_mediation/01block_mediation_prognosis.R")
    } else {
      file.path(root, "Blocks/20_mediation/02block_mediation_incidence.R")
    }
    if (file.exists(fp)) source(fp, local = FALSE)
    med_fun <- if (identical(study_type, "prognosis") || isTRUE(bl$force_prognosis %||% FALSE)) {
      if (exists("block_mediation_prognosis", mode = "function")) block_mediation_prognosis else NULL
    } else {
      if (exists("block_mediation_incidence", mode = "function")) block_mediation_incidence else NULL
    }
  }
  if (is.null(sub_fun) && run_subgroup) {
    fp <- if (identical(study_type, "prognosis") || isTRUE(bl$force_prognosis %||% FALSE)) {
      file.path(root, "Blocks/18_subgroup/01block_subgroup_prognosis.R")
    } else {
      file.path(root, "Blocks/18_subgroup/02block_subgroup_incidence.R")
    }
    if (file.exists(fp)) source(fp, local = FALSE)
    sub_fun <- if (identical(study_type, "prognosis") || isTRUE(bl$force_prognosis %||% FALSE)) {
      if (exists("block_subgroup_prognosis", mode = "function")) block_subgroup_prognosis else NULL
    } else {
      if (exists("block_subgroup_incidence", mode = "function")) block_subgroup_incidence else NULL
    }
  }

  cli::cli_alert_info(
    "mediation_subgroup_router: mode={route$mode}, exposures={length(exposures)}, mediation={run_mediation}, subgroup={run_subgroup}"
  )

  logs <- list()
  base_out <- ctx$output_dir
  for (ex in exposures) {
    cli::cli_h2("暴露目标: {ex}")
    # 临时注入主暴露，兼容只读 config$logistic$index_var 的块
    ctx$config$logistic <- modifyList(ctx$config$logistic %||% list(), list(index_var = ex))
    ctx$config$incidence <- modifyList(ctx$config$incidence %||% list(), list(index_var = ex))
    ctx$config$survival <- modifyList(ctx$config$survival %||% list(), list(index_var = ex))
    ctx$config$mediation_incidence <- modifyList(
      ctx$config$mediation_incidence %||% list(), list(exposure = ex)
    )
    ctx$config$mediation_prognosis <- modifyList(
      ctx$config$mediation_prognosis %||% list(), list(exposure = ex)
    )

    # 分目录输出，避免互相覆盖
    if (!is.null(base_out) && nzchar(base_out)) {
      sub_dir <- file.path(base_out, "by_exposure", gsub("[^A-Za-z0-9._-]+", "_", ex))
      dir.create(file.path(sub_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
      dir.create(file.path(sub_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
      ctx$output_dir <- sub_dir
      ctx$output_dir_tables <- file.path(sub_dir, "Tables")
      ctx$output_dir_figures <- file.path(sub_dir, "Figures")
    }

    status_m <- "skipped"; status_s <- "skipped"
    if (run_mediation && !is.null(med_fun)) {
      status_m <- tryCatch({
        ctx <- med_fun(ctx, exposure = ex)
        "ok"
      }, error = function(e) {
        cli::cli_alert_warning("mediation [{ex}] 失败: {e$message}")
        paste0("error: ", e$message)
      })
    }
    if (run_subgroup && !is.null(sub_fun)) {
      status_s <- tryCatch({
        ctx <- sub_fun(ctx)
        "ok"
      }, error = function(e) {
        cli::cli_alert_warning("subgroup [{ex}] 失败: {e$message}")
        paste0("error: ", e$message)
      })
    }
    logs[[length(logs) + 1L]] <- data.frame(
      exposure = ex, mediation = status_m, subgroup = status_s,
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(base_out) && nzchar(base_out)) {
    ctx$output_dir <- base_out
    ctx$output_dir_tables <- file.path(base_out, "Tables")
    ctx$output_dir_figures <- file.path(base_out, "Figures")
  }
  tab <- do.call(rbind, logs)
  ctx$results$mediation_subgroup_router_log <- tab
  if (!is.null(base_out)) {
    utils::write.csv(
      tab, file.path(base_out, "mediation_subgroup_router_log.csv"), row.names = FALSE
    )
  }
  cli::cli_alert_success("mediation_subgroup_router 完成: {nrow(tab)} 个暴露。")
  ctx
}

register_block(
  "mediation_subgroup_router",
  block_mediation_subgroup_router,
  "按配置路由批量中介/亚组（主暴露 or 全部 ML 特征）"
)
