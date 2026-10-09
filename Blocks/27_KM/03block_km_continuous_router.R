###############################################################################
#  km_continuous_router — 连续变量 KM，切点与 Cox/logistic 分位一致
#
#  register_block: "km_continuous_router"
#  读 ctx$results$continuous_km_cutpoints（由 cox_ml_continuous_batch / Cox 块写入）
#  或现场按 quartile/tertile 计算；再委派 km_strata 出图。
###############################################################################

block_km_continuous_router <- function(ctx, ...) {
  cfg <- ctx$config %||% list()
  bl <- cfg$km_continuous %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("km_continuous_router: enable=FALSE，跳过。")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    cli::cli_alert_warning("km_continuous_router: 无分析数据。")
    return(ctx)
  }

  method <- as.character(bl$method %||% "quartile")[1L]
  vars <- as.character(
    bl$vars %||%
      ctx$results$cox_ml_continuous_batch_features %||%
      names(ctx$results$continuous_km_cutpoints %||% list()) %||%
      character(0)
  )
  vars <- unique(vars[nzchar(vars)])
  exclude_vars <- unique(c(
    as.character(bl$exclude_vars %||% character(0)),
    as.character(cfg$force_factor_vars %||% character(0))
  ))
  exclude_vars <- exclude_vars[nzchar(exclude_vars)]
  if (length(exclude_vars)) vars <- setdiff(vars, exclude_vars)
  vars <- vars[vapply(vars, function(v) {
    v %in% names(data) && is.numeric(data[[v]]) && !is.factor(data[[v]]) &&
      length(unique(stats::na.omit(data[[v]]))) > 4L
  }, logical(1L))]

  if (!length(vars)) {
    cli::cli_alert_warning("km_continuous_router: 无可用连续变量。")
    return(ctx)
  }

  for (v in vars) {
    store <- ctx$results$continuous_km_cutpoints[[v]]
    br <- store$breaks %||% NULL
    store_method <- as.character(store$method %||% "")[1L]
    need_recompute <- is.null(br) || !length(br) ||
      (!identical(store_method, method))
    if (isTRUE(need_recompute)) {
      if (exists("pipeline_quantile_breaks", mode = "function")) {
        br <- pipeline_quantile_breaks(data[[v]], method = method)
      } else {
        probs <- switch(method,
          quartile = c(0, 0.25, 0.5, 0.75, 1),
          tertile = c(0, 1/3, 2/3, 1),
          c(0, 0.5, 1)
        )
        br <- as.numeric(stats::quantile(data[[v]], probs = probs, na.rm = TRUE, type = 7))
      }
      if (!is.null(br) && exists("pipeline_store_continuous_km_cutpoints", mode = "function")) {
        ctx <- pipeline_store_continuous_km_cutpoints(ctx, v, br, method)
      }
    }
  }

  built <- if (exists("pipeline_build_km_strata_defs_from_cutpoints", mode = "function")) {
    pipeline_build_km_strata_defs_from_cutpoints(ctx, vars = vars, method = method)
  } else {
    list(strata_vars = character(0), strata_defs = list())
  }
  if (!length(built$strata_vars)) {
    cli::cli_alert_warning("km_continuous_router: 未能构建 strata_defs。")
    return(ctx)
  }

  surv <- cfg$survival %||% list()
  km_cfg <- cfg$km_strata %||% list()
  ctx$config$km_strata <- modifyList(km_cfg, list(
    strata_vars = built$strata_vars,
    strata_defs = built$strata_defs,
    time_var = bl$time_var %||% km_cfg$time_var %||% surv$time_var,
    event_var = bl$event_var %||% km_cfg$event_var %||% surv$event_var,
    single_use_main_figure = isTRUE(bl$single_use_main_figure %||% FALSE),
    single_filename_template = bl$single_filename_template %||%
      "KM continuous {strata}.pdf"
  ))

  if (!exists("block_km_strata", mode = "function")) {
    root <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    fp <- file.path(root, "Blocks/27_KM/02block_km_strata.R")
    if (file.exists(fp)) source(fp, local = FALSE)
  }
  if (!exists("block_km_strata", mode = "function")) {
    stop("km_continuous_router: 无法加载 block_km_strata。", call. = FALSE)
  }

  cli::cli_alert_info(
    "km_continuous_router: method={method}, vars={length(vars)}, strata={length(built$strata_vars)}"
  )
  ctx <- block_km_strata(ctx)
  ctx$results$km_continuous_router <- list(
    method = method, vars = vars, strata_vars = built$strata_vars
  )
  ctx
}

register_block(
  "km_continuous_router",
  block_km_continuous_router,
  "连续变量 KM：使用与 Cox/logistic 相同的分位切点"
)
