###############################################################################
#  cross_lagged_pooled_bind — 三库插补后 rbind 为 Pooled（+ Country）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = ctx$results$cohort_imputed_list
#    或 config$cross_lagged_pooled_bind$imputed_paths（命名 list/字符路径）
#  require_ctx_results = Model2Factors（可选；缺则用 config 锁定名单）
#
#  cross_lagged_pooled_bind = list(
#    country_map = list(CHARLS = "China", ELSA = "UK", HRS = "America"),
#    imputed_paths = NULL,   # list(CHARLS=path, ...) 或从 results 读
#    model2_clinical = NULL, # 锁定临床协变量（可含 Age）；NULL → 三库 Model2 交集
#    model1_locked = NULL,   # 可选；NULL → Age（若在 model2 中）或 Age/Gender/Education ∩ model2
#    model2_locked = NULL,   # 可选完整锁定集（优先于 model2_clinical / 自动交集）
#    lock_source = NULL,     # 记录 "vif_final" | "vif_screen_fallback"
#    force_country_in_model = TRUE,
#    id_column = "ID",
#    outcome_column = "Disease_Group",
#    index_var = "FI"
#  ),
#
#  register_block: "cross_lagged_pooled_bind"
#  写: ctx$data$imputed（Pooled）；ctx$results$Model1Factors / Model2Factors（含 Country）
#  注意: 禁止在本块之前对 Pooled 跑 UV/VIF；本块也不跑筛选
###############################################################################

block_cross_lagged_pooled_bind <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$cross_lagged_pooled_bind %||% list()
  country_map <- bl$country_map %||% list(CHARLS = "China", ELSA = "UK", HRS = "America")
  id_col <- bl$id_column %||% cfg$data$id_column %||% "ID"
  out_col <- bl$outcome_column %||% cfg$data$outcome_column %||% "Disease_Group"
  index_var <- bl$index_var %||% cfg$incidence$index_var %||% "FI"

  # --- gather per-cohort imputed data.frames ---
  src <- ctx$results$cohort_imputed_list
  if (is.null(src) || !length(src)) {
    paths <- bl$imputed_paths
    if (is.null(paths) || !length(paths)) {
      stop("cross_lagged_pooled_bind: 需要 ctx$results$cohort_imputed_list 或 config$cross_lagged_pooled_bind$imputed_paths",
           call. = FALSE)
    }
    src <- list()
    for (nm in names(paths)) {
      p <- paths[[nm]]
      if (is.null(p) || !nzchar(p) || !file.exists(p))
        stop("cross_lagged_pooled_bind: 缺失 imputed 路径: ", nm, " -> ", p, call. = FALSE)
      e <- new.env(parent = emptyenv())
      load(p, envir = e)
      # accept dabiao / data_imp / first data.frame
      cand <- ls(e)
      df <- NULL
      for (obj in c("dabiao", "data_imp", "imputed", cand)) {
        if (exists(obj, envir = e, inherits = FALSE) && is.data.frame(e[[obj]])) {
          df <- e[[obj]]; break
        }
      }
      if (is.null(df)) stop("cross_lagged_pooled_bind: ", p, " 中无 data.frame", call. = FALSE)
      src[[nm]] <- df
    }
  }

  if (!length(src)) stop("cross_lagged_pooled_bind: 无队列数据可合并", call. = FALSE)

  parts <- list()
  for (nm in names(src)) {
    d <- as.data.frame(src[[nm]])
    ctry <- country_map[[nm]]
    if (is.null(ctry) || !nzchar(ctry))
      stop("cross_lagged_pooled_bind: country_map 缺少 ", nm, call. = FALSE)
    d$Country <- as.character(ctry)
    d$Cohort <- as.character(nm)
    if (!id_col %in% names(d))
      stop("cross_lagged_pooled_bind: ", nm, " 缺 ID 列 ", id_col, call. = FALSE)
    d[[id_col]] <- paste0(nm, "_", as.character(d[[id_col]]))
    parts[[nm]] <- d
  }

  common_cols <- Reduce(intersect, lapply(parts, names))
  must <- c(id_col, out_col, index_var, "Country", "Cohort")
  miss_must <- setdiff(must, common_cols)
  if (length(miss_must))
    stop("cross_lagged_pooled_bind: 三库交集缺少列: ", paste(miss_must, collapse = ", "), call. = FALSE)

  parts <- lapply(parts, function(d) d[, common_cols, drop = FALSE])
  pooled <- do.call(rbind, parts)
  rownames(pooled) <- NULL
  pooled$Country <- factor(pooled$Country, levels = unique(unlist(country_map, use.names = FALSE)))

  # --- Model factors（优先显式锁定；禁止无脑塞入 Gender/Education）---
  locked_full <- bl$model2_locked %||% bl$model2_clinical
  if (is.null(locked_full) || !length(locked_full)) {
    m2_list <- ctx$results$cohort_model2_list
    if (!is.null(m2_list) && length(m2_list)) {
      locked_full <- Reduce(intersect, lapply(m2_list, as.character))
    } else {
      locked_full <- character(0)
    }
  }
  locked_full <- setdiff(
    as.character(locked_full),
    c("Country", "Cohort", id_col, out_col, index_var, "Frailty", "FI")
  )
  locked_full <- locked_full[locked_full %in% names(pooled)]

  model1 <- bl$model1_locked
  if (is.null(model1) || !length(model1)) {
    if ("Age" %in% locked_full) {
      model1 <- "Age"
    } else {
      model1 <- intersect(c("Age", "Gender", "Education"), locked_full)
    }
  }
  model1 <- unique(as.character(model1))
  model1 <- model1[model1 %in% names(pooled)]

  model2 <- unique(c(model1, locked_full))
  if (isTRUE(bl$force_country_in_model %||% TRUE)) {
    if (!"Country" %in% names(pooled))
      stop("cross_lagged_pooled_bind: Country 列缺失", call. = FALSE)
    model1 <- unique(c(model1, "Country"))
    model2 <- unique(c(model2, "Country"))
  }

  if (!length(setdiff(model2, "Country"))) {
    cli::cli_alert_warning(
      "cross_lagged_pooled_bind: 锁定协变量为空（仅 Country）。请检查三库 VIF final/screen 交集回退。"
    )
  } else if (!is.null(bl$lock_source) && nzchar(as.character(bl$lock_source)[1L])) {
    cli::cli_alert_info(
      "Pooled 协变量锁定来源: {bl$lock_source}; Model2={paste(model2, collapse=', ')}"
    )
  }

  ctx$data$imputed <- pooled
  ctx$data$cleaned <- pooled
  ctx$results$Model1Factors <- model1
  ctx$results$Model2Factors <- model2
  ctx$results$pooled_bind <- list(
    n = nrow(pooled),
    cohorts = names(src),
    n_by_cohort = vapply(parts, nrow, integer(1)),
    model1 = model1,
    model2 = model2,
    lock_source = bl$lock_source %||% NA_character_,
    common_cols = common_cols
  )

  out_dir <- cfg$project$output_dir %||% "Output"
  tab_dir <- file.path(out_dir, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      Cohort = names(ctx$results$pooled_bind$n_by_cohort),
      N = as.integer(ctx$results$pooled_bind$n_by_cohort),
      stringsAsFactors = FALSE
    ),
    file.path(tab_dir, "Table_Pooled_bind_N.csv"),
    row.names = FALSE
  )
  cli::cli_alert_success(
    "Pooled rbind 完成: N={nrow(pooled)}; Model2 含 Country={ 'Country' %in% model2 }"
  )
  ctx
}

register_block("cross_lagged_pooled_bind", block_cross_lagged_pooled_bind, "三库插补 rbind Pooled")
