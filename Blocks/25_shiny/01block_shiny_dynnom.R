###############################################################################
#  shiny_dynnom — 动态列线图（C02 / DynNomapp，rms::lrm + DNbuilder_czx_lrm）
#
#  register_block: "shiny_dynnom"
#  典型流水线: feature_selection → train_validation → shiny_dynnom
#              （logistic 为最优模型时；或由 block_shiny 调度）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = train_validation/Data/df_train_RData.RData
#  require_results = Model2Factors（ctx 或 feature_selection/Model2Factors.RData）
#
#  shiny_dynnom = list(
#    enable = TRUE, index_var = NULL, dynnom_clevel = 0.95,
#    dynnom_exclude_cols = NULL, run_interactive = FALSE
#  ),
#  未设 shiny_dynnom 时回退 config$shiny 同名键
###############################################################################

.sdn_merged_cfg <- function(cfg) {
  sh <- cfg$shiny %||% list()
  sdn <- cfg$shiny_dynnom %||% list()
  if (length(sdn)) utils::modifyList(sh, sdn) else sh
}

.sdn_resolve_tv_data_dir <- function(ctx) {
  tv <- ctx$log$block_output_dirs[["train_validation"]] %||% ""
  tv <- as.character(tv)[1L]
  if (nzchar(tv)) {
    d <- file.path(tv, "Data")
    if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  }
  d2 <- file.path(ctx$output_dir, "Data")
  if (dir.exists(d2)) return(normalizePath(d2, winslash = "/", mustWork = FALSE))
  ""
}

.sdn_resolve_index_vars <- function(cfg, sdn_cfg) {
  idx <- sdn_cfg$index_var %||% cfg$incidence$index_var %||% NULL
  idx <- unique(as.character(idx))
  idx <- idx[nzchar(trimws(idx))]
  if (!length(idx)) {
    stop(
      "block_shiny_dynnom: 无法解析 index（请设置 shiny_dynnom$index_var 或 incidence$index_var）。",
      call. = FALSE
    )
  }
  if (length(idx) > 1L) {
    cli::cli_alert_info(
      "block_shiny_dynnom: 纳入 {length(idx)} 个 index 指标: {paste(idx, collapse = ', ')}"
    )
  }
  idx
}

.sdn_resolve_model2_factors <- function(ctx) {
  Model2Factors <- as.character(ctx$results$Model2Factors %||% character(0))
  Model2Factors <- unique(Model2Factors[nzchar(Model2Factors)])
  if (length(Model2Factors)) return(Model2Factors)
  fs_dir <- as.character(ctx$log$block_output_dirs[["feature_selection"]] %||% "")[1L]
  m2_path <- if (nzchar(fs_dir)) file.path(fs_dir, "Model2Factors.RData") else ""
  if (nzchar(m2_path) && file.exists(m2_path)) {
    e_m2 <- new.env(parent = emptyenv())
    load(m2_path, envir = e_m2)
    if (exists("Model2Factors", envir = e_m2)) {
      Model2Factors <- as.character(e_m2$Model2Factors)
    }
  }
  unique(Model2Factors[nzchar(Model2Factors)])
}

.sdn_copy_if_exists <- function(src, dst) {
  if (!nzchar(src) || !file.exists(src)) return(FALSE)
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  isTRUE(tryCatch(file.copy(src, dst, overwrite = TRUE), error = function(e) FALSE))
}

.sdn_resolve_lrm_outcome_col <- function(df, cfg) {
  preferred <- as.character(
    cfg$incidence$outcome_var %||% cfg$data$outcome_column %||% "Disease"
  )
  preferred <- preferred[nzchar(preferred)]
  for (oc in preferred) {
    if (oc %in% names(df)) return(oc)
  }
  if ("Group" %in% names(df)) {
    cli::cli_alert_info(
      "block_shiny_dynnom: 训练集无 {paste(preferred, collapse='/')}，使用 Group 作为结局。"
    )
    return("Group")
  }
  stop(
    "block_shiny_dynnom: 训练集既无 ",
    paste(preferred, collapse = " / "),
    " 也无 Group。",
    call. = FALSE
  )
}

.sdn_dynnom_exclude_cols <- function(cfg, sdn_cfg, outcome_var) {
  ex <- sdn_cfg$dynnom_exclude_cols
  if (!is.null(ex)) {
    ex <- unique(as.character(ex)[nzchar(as.character(ex))])
    return(setdiff(ex, outcome_var))
  }
  unique(setdiff(c(
    as.character(cfg$data$id_column %||% character(0)),
    as.character(cfg$obj$exclude_cols %||% character(0)),
    as.character(cfg$data$strip_id_columns_after_imputation %||% character(0)),
    "ID", "Class", "SEQN", "Source_File", "SDDSRVYR", "Group"
  ), outcome_var))
}

.sdn_prepare_lrm_outcome <- function(df, outcome_var, cfg) {
  if (!outcome_var %in% names(df)) {
    stop("block_shiny_dynnom: 训练集无结局列 ", outcome_var, call. = FALSE)
  }
  y <- df[[outcome_var]]
  if (is.numeric(y) || is.integer(y)) {
    u <- unique(y[!is.na(y)])
    if (length(u) && all(u %in% c(0, 1))) return(df)
  }
  ana <- trimws(as.character(cfg$project$analysis_group %||% cfg$project$disease %||% "1"))
  ref <- trimws(as.character(cfg$project$reference_group %||% "0"))
  y_chr <- trimws(as.character(y))
  df[[outcome_var]] <- ifelse(
    y_chr == ana, 1L,
    ifelse(y_chr == ref, 0L, NA_integer_)
  )
  df
}

.sdn_ensure_dynnom_sourced <- function(root_dir = "") {
  if (exists("DNbuilder_czx_lrm", mode = "function")) return(invisible(TRUE))
  if (!nzchar(root_dir)) {
    root_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
  p <- file.path(root_dir, "R/utils_dynnom.R")
  if (!file.exists(p)) {
    stop("block_shiny_dynnom: 未找到 R/utils_dynnom.R", call. = FALSE)
  }
  source(p, local = FALSE)
  invisible(TRUE)
}

block_shiny_dynnom <- function(ctx, ...) {
  cfg <- ctx$config
  sdn_cfg <- .sdn_merged_cfg(cfg)
  pred_cfg <- cfg$prediction %||% list()

  sh_legacy <- cfg$shiny %||% list()
  if (!isTRUE(sdn_cfg$enable %||% sh_legacy$enable %||% pred_cfg$shiny_app_enable %||% FALSE)) {
    cli::cli_alert_info(
      "block_shiny_dynnom: 未启用（shiny_dynnom$enable / shiny$enable / prediction$shiny_app_enable），跳过。"
    )
    return(ctx)
  }

  for (pkg in c("rms", "DynNom", "shiny")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("block_shiny_dynnom: 需要 ", pkg, " 包。", call. = FALSE)
    }
  }
  suppressPackageStartupMessages({
    library(rms)
    library(DynNom)
  })

  Index_vars <- .sdn_resolve_index_vars(cfg, sdn_cfg)

  root_dir <- Sys.getenv("BLOCK_ML_ROOT", "")
  if (!nzchar(root_dir) && exists("root", inherits = TRUE)) {
    root_dir <- as.character(get("root", inherits = TRUE))[1L]
  }
  if (!nzchar(root_dir)) {
    root_dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
  .sdn_ensure_dynnom_sourced(root_dir)

  tv_dir <- .sdn_resolve_tv_data_dir(ctx)
  if (!nzchar(tv_dir)) {
    stop("block_shiny_dynnom: 未找到 train_validation/Data。", call. = FALSE)
  }
  src_train <- file.path(tv_dir, "df_train_RData.RData")
  if (!file.exists(src_train)) {
    stop("block_shiny_dynnom: 未找到 ", src_train, call. = FALSE)
  }

  Model2Factors <- .sdn_resolve_model2_factors(ctx)
  if (!length(Model2Factors)) {
    stop("block_shiny_dynnom: 无 Model2Factors（请先运行 feature_selection）。", call. = FALSE)
  }

  Model1Factors <- unique(c(Model2Factors, Index_vars))
  Model1Factors <- Model1Factors[nzchar(Model1Factors)]

  e_tr <- new.env(parent = emptyenv())
  load(src_train, envir = e_tr)
  if (!exists("df_train", envir = e_tr)) {
    stop("block_shiny_dynnom: ", src_train, " 中无 df_train。", call. = FALSE)
  }
  training_dataset <- e_tr$df_train

  outcome_var <- .sdn_resolve_lrm_outcome_col(training_dataset, cfg)
  Model1Factors <- setdiff(Model1Factors, outcome_var)

  miss <- setdiff(Model1Factors, names(training_dataset))
  if (length(miss)) {
    stop(
      "block_shiny_dynnom: 训练集缺少协变量: ", paste(miss, collapse = ", "),
      call. = FALSE
    )
  }

  exclude_cols <- .sdn_dynnom_exclude_cols(cfg, sdn_cfg, outcome_var)
  drop_cols <- intersect(exclude_cols, names(training_dataset))
  if (length(drop_cols)) {
    training_dataset <- training_dataset[, !names(training_dataset) %in% drop_cols, drop = FALSE]
  }

  if (!outcome_var %in% names(training_dataset)) {
    stop("block_shiny_dynnom: 排除列后缺少结局列 ", outcome_var, call. = FALSE)
  }

  training_dataset <- .sdn_prepare_lrm_outcome(training_dataset, outcome_var, cfg)
  keep_cols <- unique(c(outcome_var, Model1Factors))
  training_dataset <- training_dataset[, keep_cols, drop = FALSE]
  training_dataset <- training_dataset[stats::complete.cases(training_dataset), , drop = FALSE]
  if (!nrow(training_dataset)) {
    stop("block_shiny_dynnom: 完整病例数为 0。", call. = FALSE)
  }

  fml <- stats::as.formula(paste(
    outcome_var, "~", paste(Model1Factors, collapse = " + ")
  ))
  fml_deparse <- paste(deparse(fml), collapse = " ")

  ddist <- rms::datadist(training_dataset)
  assign("ddist", ddist, envir = .GlobalEnv)
  assign("fml", fml, envir = .GlobalEnv)
  assign("training_dataset", training_dataset, envir = .GlobalEnv)
  options(datadist = "ddist")

  f_lrm <- tryCatch(
    rms::lrm(fml, data = training_dataset, x = TRUE, y = TRUE, maxit = 5000),
    error = function(e) {
      stop("block_shiny_dynnom: lrm 拟合失败: ", conditionMessage(e), call. = FALSE)
    }
  )
  cli::cli_alert_success(
    "block_shiny_dynnom: lrm 已拟合（{outcome_var} ~ {length(Model1Factors)} 协变量）。"
  )

  out_base <- ctx$output_dir
  dyn_dir <- file.path(out_base, "DynNomapp")
  if (dir.exists(dyn_dir)) unlink(dyn_dir, recursive = TRUE)

  clevel <- as.numeric(sdn_cfg$dynnom_clevel %||% 0.95)[1L]
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(out_base)
  DNbuilder_czx_lrm(model = f_lrm, data = training_dataset, clevel = clevel)

  if (!dir.exists(dyn_dir)) {
    stop("block_shiny_dynnom: DNbuilder 未生成 DynNomapp/。", call. = FALSE)
  }

  data_dir <- file.path(out_base, "Data")
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  .sdn_copy_if_exists(src_train, file.path(data_dir, "df_train_RData.RData"))
  save(Model2Factors, file = file.path(data_dir, "model2factors.RData"))
  save(
    list = c("f_lrm", "fml", "Model1Factors", "outcome_var", "Index_vars"),
    file = file.path(dyn_dir, "nomogram_fit.RData")
  )

  writeLines(
    c(
      "Dynamic Nomogram (block_shiny_dynnom / C02)",
      "",
      paste0("Formula: ", fml_deparse),
      paste0("Index: ", paste(Index_vars, collapse = ", ")),
      paste0("Model2Factors + Index: ", paste(Model1Factors, collapse = ", ")),
      "",
      "Run: setwd to this folder; shiny::runApp()",
      "Deploy: upload entire DynNomapp/ to shinyapps.io"
    ),
    file.path(dyn_dir, "README_block_shiny_dynnom.txt"),
    useBytes = TRUE
  )

  if (isTRUE(sdn_cfg$run_interactive %||% FALSE)) {
    cli::cli_alert_info("block_shiny_dynnom: 启动 DynNomapp...")
    shiny::runApp(dyn_dir)
  }

  ctx$results$shiny_app_dir <- dyn_dir
  ctx$results$shiny_app_mode <- "dynnom_lrm"
  ctx$results$shiny_ml_model_tag <- "logistic"
  ctx$results$shiny_index_var <- Index_vars
  ctx$results$shiny_lrm_formula <- fml_deparse
  ctx$results$shiny_final_features <- Model1Factors

  cli::cli_alert_success("block_shiny_dynnom: 已写出 {.file {dyn_dir}/}")
  ctx
}

register_block(
  "shiny_dynnom",
  block_shiny_dynnom,
  "Shiny 动态列线图（logistic / DynNomapp）"
)
