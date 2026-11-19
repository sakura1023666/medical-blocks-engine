###############################################################################
#  psychometrics_scale_score — 问卷条目 → 总分/维度（通用，不写死病种）
#
#  register_block: "psychometrics_scale_score"
#  典型位置: data_clean 之后、imputation / LPA / 中介之前
#
#  config$psychometrics_scale_score = list(
#    scales = list(
#      list(
#        name = "PHQ15",
#        items = paste0("PHQ15", 1:15),
#        value_map = c("No" = 0, "some" = 1, "a lot" = 2),
#        na_rm = TRUE
#      ),
#      ...
#    ),
#    write_to = c("cleaned", "imputed")
#  )
###############################################################################

block_psychometrics_scale_score <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$psychometrics_scale_score %||% list()
  scales <- bl$scales %||% list()
  if (!length(scales)) {
    cli::cli_alert_warning("psychometrics_scale_score: scales 为空，跳过")
    return(ctx)
  }

  slots <- bl$write_to %||% c("cleaned", "imputed", "raw")
  scored <- list()

  # 行级 ID：门诊表 number 可能非唯一
  for (slot in unique(c(slots, "cleaned", "raw"))) {
    df0 <- ctx$data[[slot]]
    if (is.null(df0) || !is.data.frame(df0)) next
    if (!"row_id" %in% names(df0)) {
      df0$row_id <- seq_len(nrow(df0))
      ctx$data[[slot]] <- df0
    }
  }

  .apply_map <- function(x, value_map) {
    if (is.null(value_map) || !length(value_map)) {
      return(suppressWarnings(as.numeric(x)))
    }
    # 已是数值则保留
    xn <- suppressWarnings(as.numeric(x))
    if (all(is.na(x) | is.finite(xn))) return(xn)
    key <- trimws(as.character(x))
    # 大小写不敏感匹配
    nm <- names(value_map)
    lut <- setNames(as.numeric(value_map), tolower(nm))
    out <- unname(lut[tolower(key)])
    out[key == "" | is.na(key)] <- NA_real_
    out
  }

  .score_one <- function(df, sc) {
    nm <- as.character(sc$name %||% "")[1L]
    items <- as.character(sc$items %||% character(0))
    items <- items[items %in% names(df)]
    if (!nzchar(nm) || !length(items)) return(df)
    vmap <- sc$value_map %||% NULL
    mat <- as.data.frame(lapply(df[items], function(x) .apply_map(x, vmap)))
    # 回写数值化条目（供 LPA / CFA / 网络）
    if (isTRUE(sc$write_items %||% TRUE)) {
      for (it in items) df[[it]] <- mat[[it]]
    }
    na_rm <- isTRUE(sc$na_rm %||% TRUE)
    if (isTRUE(na_rm)) {
      df[[nm]] <- rowSums(mat, na.rm = TRUE)
      all_na <- apply(mat, 1L, function(r) all(is.na(r)))
      df[[nm]][all_na] <- NA_real_
    } else {
      df[[nm]] <- rowSums(mat, na.rm = FALSE)
    }
    scored[[nm]] <<- data.frame(
      scale = nm, n_items = length(items),
      n_nonmiss = sum(!is.na(df[[nm]])),
      mean = mean(df[[nm]], na.rm = TRUE),
      sd = stats::sd(df[[nm]], na.rm = TRUE)
    )
    df
  }

  for (slot in slots) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df)) next
    for (sc in scales) df <- .score_one(df, sc)
    ctx$data[[slot]] <- df
  }

  if (is.null(ctx$data$cleaned) && !is.null(ctx$data$raw)) {
    df <- ctx$data$raw
    for (sc in scales) df <- .score_one(df, sc)
    ctx$data$cleaned <- df
  }

  tab <- if (length(scored)) do.call(rbind, scored) else data.frame()
  ctx$results$psychometrics_scale_score <- list(summary = tab, scales = scales)
  out_dir <- file.path(ctx$output_dir %||% ".", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (nrow(tab)) {
    utils::write.csv(tab, file.path(out_dir, "Scale_score_summary.csv"), row.names = FALSE)
  }
  cli::cli_alert_success("psychometrics_scale_score: 完成 {nrow(tab)} 个量表总分")
  ctx
}

register_block(
  "psychometrics_scale_score",
  block_psychometrics_scale_score,
  "问卷条目汇总为总分/维度"
)
