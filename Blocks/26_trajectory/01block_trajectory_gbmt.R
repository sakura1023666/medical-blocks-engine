###############################################################################
#  trajectory_gbmt — GBMT 轨迹模型拟合：宽转长→Winsorize→变换→拟合→类别分配→IC表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed_with_id %||% ctx$data$imputed   # pipeline 决定，块内不选源
#  require_pkg  = gbmt, dplyr, tidyr, stringr, cli
#
#  trajectory_gbmt = list(
#    index_vars            = c("BAR"),              # 指标变量列表
#    class_range           = 2:8,                   # 拟合类别数范围
#    rawdata_path_template = "RawData/12_{Index}.RData",
#    rawdata_obj           = "index_df",
#    id_column             = NULL,                  # NULL → config$data$id_column
#    non_na_col            = "non_na_count",
#    time_col_start        = 2L,
#    time_col_end          = 29L,
#    time_col_sep          = "_",
#    outlier_quantiles     = c(0.01, 0.99),
#    value_transform       = "none",                # none | log1p | yeojohnson | robust
#    poly_degree           = 3L,                    # gbmt() 的 d 参数
#    scaling               = 0,                     # gbmt 标准化方式
#    pause_enable          = TRUE,
#    pause_on_no_output    = TRUE
#  ),
#
#  register_block: "trajectory_gbmt"
#  写: ctx$data$trajectory_long, ctx$results$trajectory_models, ctx$results$trajectory_ic_table
#  落盘: Data/D01_long_{Index}_D_{D}.RData, Tables/Table_Trajectory_IC_GBMT.xlsx
###############################################################################

.tfg01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tfg01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block         = "trajectory_gbmt",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tfg01_resolve_path <- function(p) {
  if (grepl("^(/|[A-Za-z]:[/\\\\])", p)) p else file.path(getwd(), p)
}

.tfg01_apply_value_transform <- function(x, method) {
  method <- tolower(method %||% "none")
  switch(method,
    "log1p" = log1p(pmax(x, 0)),
    "yeojohnson" = {
      if (!requireNamespace("car", quietly = TRUE))
        stop("yeojohnson 变换需要 car 包：install.packages('car')")
      x_clean <- x[!is.na(x) & is.finite(x)]
      if (length(x_clean) < 10) return(x)
      lambda <- tryCatch({
        pt <- car::powerTransform(x_clean, family = "yjPower")
        as.numeric(pt$lambda)
      }, error = function(e) 0)
      car::yjPower(x, lambda = lambda, jacobian.adjusted = FALSE)
    },
    "robust" = {
      med <- stats::median(x, na.rm = TRUE)
      iqr <- stats::IQR(x, na.rm = TRUE)
      if (is.na(iqr) || iqr == 0) return(x)
      (x - med) / iqr
    },
    x
  )
}

.tfg01_winsorize <- function(x, probs = c(0.01, 0.99)) {
  q <- stats::quantile(x, probs = probs, na.rm = TRUE)
  x[!is.na(x) & x < q[1]] <- q[1]
  x[!is.na(x) & x > q[2]] <- q[2]
  x
}

.tfg01_wide_to_long <- function(index_df, id_col, time_start, time_end, time_sep,
                                 non_na_col, outlier_q, value_transform) {
  if (non_na_col %in% names(index_df))
    index_df <- index_df[, !names(index_df) %in% non_na_col, drop = FALSE]

  ncols_actual <- ncol(index_df)
  if (time_start > ncols_actual) return(NULL)
  time_end_use <- min(time_end, ncols_actual)
  time_cols    <- names(index_df)[time_start:time_end_use]

  long <- index_df |>
    tidyr::pivot_longer(cols = tidyselect::all_of(time_cols),
                        names_to = "Time", values_to = "Value") |>
    as.data.frame()

  long$Value <- as.numeric(long$Value)
  long$Value[is.infinite(long$Value)] <- NA

  parts        <- stringr::str_split(long$Time, stringr::fixed(time_sep), simplify = TRUE)
  time_numeric <- suppressWarnings(as.numeric(parts[, ncol(parts)]))
  if (all(is.na(time_numeric))) return(NULL)
  long$Time <- time_numeric

  long$Value <- .tfg01_winsorize(long$Value, probs = outlier_q)
  long$Value <- .tfg01_apply_value_transform(long$Value, value_transform)
  long
}

block_trajectory_gbmt <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr); library(tidyr); library(stringr); library(cli)
    library(gbmt)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$trajectory_gbmt %||% list()

  index_vars  <- bl_cfg$index_vars %||% stop("trajectory_gbmt$index_vars 未配置。")
  class_range <- as.integer(bl_cfg$class_range %||% 2:8)
  rawdata_tpl <- bl_cfg$rawdata_path_template %||%
    stop("trajectory_gbmt$rawdata_path_template 未配置。")
  rawdata_obj   <- bl_cfg$rawdata_obj   %||% "index_df"
  id_col        <- bl_cfg$id_column    %||% cfg$data$id_column %||% "subject_id"
  non_na_col    <- bl_cfg$non_na_col   %||% "non_na_count"
  time_start    <- as.integer(bl_cfg$time_col_start %||% 2L)
  time_end      <- as.integer(bl_cfg$time_col_end   %||% 29L)
  time_sep      <- bl_cfg$time_col_sep %||% "_"
  outlier_q     <- bl_cfg$outlier_quantiles %||% c(0.01, 0.99)
  val_transform <- bl_cfg$value_transform     %||% "none"
  poly_degree   <- as.integer(bl_cfg$poly_degree %||% 3L)
  scaling       <- bl_cfg$scaling %||% 0

  imputed_data <- ctx$data$imputed_with_id %||% ctx$data$imputed
  valid_ids    <- NULL
  if (!is.null(imputed_data)) {
    id_in_imp <- intersect(c(id_col, "ID", "subject_id"), names(imputed_data))[1]
    if (!is.na(id_in_imp)) {
      valid_ids <- unique(as.character(imputed_data[[id_in_imp]]))
      cli::cli_alert_info("筛选有效 subject_id（n = {length(valid_ids)}）")
    }
  } else {
    cli::cli_alert_warning("ctx$data$imputed 为空，不执行 subject_id 过滤")
  }

  if (is.null(ctx$data$trajectory_long))      ctx$data$trajectory_long      <- list()
  if (is.null(ctx$results$trajectory_models)) ctx$results$trajectory_models <- list()

  data_out_dir <- file.path(ctx$output_dir, "Data")
  if (!dir.exists(data_out_dir)) dir.create(data_out_dir, recursive = TRUE)

  ic_rows <- list()
  n_total <- length(index_vars) * length(class_range)
  n_done  <- 0L

  for (Index in index_vars) {
    raw_path <- .tfg01_resolve_path(gsub("\\{Index\\}", Index, rawdata_tpl))
    if (!file.exists(raw_path)) {
      cli::cli_alert_warning("文件不存在，跳过 {Index}: {.file {raw_path}}")
      next
    }
    e_raw <- new.env(parent = emptyenv())
    load(raw_path, envir = e_raw)
    if (!exists(rawdata_obj, envir = e_raw)) {
      cli::cli_alert_warning("对象 '{rawdata_obj}' 不存在，跳过 {Index}")
      next
    }
    index_df <- get(rawdata_obj, envir = e_raw)
    if (!is.null(valid_ids))
      index_df <- index_df[as.character(index_df[[id_col]]) %in% valid_ids, ]
    if (nrow(index_df) == 0) { cli::cli_alert_warning("{Index}: 过滤后无样本"); next }

    long_base <- .tfg01_wide_to_long(index_df, id_col, time_start, time_end, time_sep,
                                      non_na_col, outlier_q, val_transform)
    if (is.null(long_base)) {
      cli::cli_alert_warning("{Index}: 宽转长失败，跳过"); next
    }

    for (D in class_range) {
      n_done <- n_done + 1L
      key    <- paste0(Index, "_D", D)
      cli::cli_h2("[{n_done}/{n_total}] GBMT: {Index}, D={D}")

      model <- tryCatch(
        gbmt::gbmt(x.names = "Value", unit = id_col, time = "Time",
                   d = poly_degree, ng = as.integer(D),
                   data = long_base, scaling = scaling),
        error = function(e) { cli::cli_alert_danger("拟合失败: {e$message}"); NULL }
      )
      if (is.null(model)) next

      unique_ids <- unique(as.character(long_base[[id_col]]))
      assign_vec <- model$assign
      if (length(assign_vec) != length(unique_ids)) {
        cli::cli_alert_danger("类别分配长度不匹配，跳过 {key}"); next
      }
      class_df <- data.frame(.id = unique_ids,
                             Class = paste0("Class", assign_vec),
                             stringsAsFactors = FALSE)
      names(class_df)[1] <- id_col
      long_with_class <- dplyr::left_join(long_base, class_df, by = id_col)

      ctx$data$trajectory_long[[key]]        <- long_with_class
      ctx$results$trajectory_models[[key]]   <- model

      long     <- long_with_class
      out_file <- file.path(data_out_dir, paste0("D01_long_", Index, "_D_", D, ".RData"))
      save(long, file = out_file)
      cli::cli_alert_success("落盘: {.file {basename(out_file)}}")

      n_subj <- length(unique_ids)
      ic_row <- tryCatch({
        ic_vals                <- as.data.frame(as.list(model$ic))
        ic_vals$SABIC          <- round(stats::BIC(model) * ((n_subj + 2) / 24), 3)
        ic_vals$Log_likelihood <- round(model$logLik, 3)
        ic_vals$Index <- Index; ic_vals$D <- D; ic_vals$N <- n_subj
        ic_vals
      }, error = function(e) NULL)
      if (!is.null(ic_row)) ic_rows[[length(ic_rows) + 1L]] <- ic_row
    }
  }

  if (length(ic_rows) > 0) {
    ic_table <- tryCatch(dplyr::bind_rows(ic_rows), error = function(e) NULL)
    if (!is.null(ic_table)) {
      front <- intersect(
        c("Index", "D", "N", "Log_likelihood", "AIC", "BIC", "SABIC",
          "CAIC", "SSBIC", "HQIC", "Entropy", "Conv"),
        names(ic_table)
      )
      ic_table <- ic_table[, c(front, setdiff(names(ic_table), front)), drop = FALSE]
      ic_table <- ic_table[order(ic_table$Index, ic_table$D), ]
      ctx$results$trajectory_ic_table <- ic_table

      fp_ic <- file.path(ctx$output_dir_tables, "Table_Trajectory_IC_GBMT.xlsx")
      export_sci_table(
        ic_table, fp_ic,
        title = "Table. GBMT Model Selection Information Criteria",
        sheet = "IC_Summary"
      )
      cli::cli_alert_success(
        "信息准则表已输出（{nrow(ic_table)} 行）: {.file {basename(fp_ic)}}"
      )
    }
  }

  n_keys <- length(ctx$data$trajectory_long)
  if (n_keys == 0 && .tfg01_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .tfg01_pause(
      ctx,
      "所有 Index × D 均未成功拟合（GBMT）。",
      paste0(
        "请检查 config$trajectory_gbmt：① rawdata_path_template 路径；",
        "② index_vars 变量名；③ class_range / poly_degree。"
      ),
      NULL
    )
  }
  cli::cli_alert_success(
    "trajectory_gbmt 完成: {n_keys} 个 Index×D 写入 ctx。"
  )
  ctx
}

register_block(
  "trajectory_gbmt", block_trajectory_gbmt,
  "GBMT 轨迹模型拟合：Winsorize→变换→拟合→类别分配→落盘→IC表"
)
