###############################################################################
#  modmed_mediation_batch — Yan2026 步2–4：批量中介 + 显著筛选
#
#  register_block: "modmed_mediation_batch"
###############################################################################

block_modmed_mediation_batch <- function(ctx, ...) {
  root <- ctx$root %||% getwd()
  source(file.path(root, "R/moderated_mediation_process.R"), local = FALSE)
  modmed_ensure_pkgs("mediation")
  if (!requireNamespace("mediation", quietly = TRUE)) {
    stop("需要 mediation 包", call. = FALSE)
  }

  cfg <- ctx$config
  bl <- cfg$modmed_mediation_batch %||% cfg$modmed %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("modmed_mediation_batch: 无数据", call. = FALSE)

  exposures <- bl$exposures %||% cfg$modmed$exposures
  mediators <- bl$mediators %||% cfg$modmed$mediators
  outcome <- bl$outcome %||% cfg$modmed$outcome %||% "Group_bin"
  sims <- as.integer(bl$sims %||% cfg$modmed$sims %||% 5000L)
  seed <- as.integer(bl$seed %||% cfg$modmed$seed %||% 1234L)
  covariates <- bl$covariates %||% character(0)
  # 环境变量可覆盖（冒烟）
  env_sims <- Sys.getenv("MODMED_SIMS", unset = "")
  if (nzchar(env_sims)) sims <- as.integer(env_sims)

  exposures <- exposures[exposures %in% names(data)]
  mediators <- mediators[mediators %in% names(data)]
  if (!outcome %in% names(data)) stop("结局列不存在: ", outcome, call. = FALSE)
  if (!length(exposures) || !length(mediators)) {
    stop("modmed_mediation_batch: exposures/mediators 为空", call. = FALSE)
  }

  ck_dir <- ctx$output_dir_checkpoints %||%
    file.path(ctx$output_dir %||% ".", "checkpoints")
  dir.create(ck_dir, recursive = TRUE, showWarnings = FALSE)
  partial_path <- file.path(ck_dir, "med_batch_partial.rds")

  done_keys <- character(0)
  rows <- list()
  if (file.exists(partial_path) && isTRUE(bl$resume %||% TRUE)) {
    old <- tryCatch(readRDS(partial_path), error = function(e) NULL)
    if (is.list(old) && !is.null(old$rows) && identical(as.integer(old$sims %||% -1L), as.integer(sims))) {
      rows <- old$rows
      done_keys <- old$done_keys %||% character(0)
      cli::cli_alert_info("从断点恢复: 已完成 {length(done_keys)} 对（sims={sims}）")
    } else if (is.list(old) && !identical(as.integer(old$sims %||% -1L), as.integer(sims))) {
      cli::cli_alert_warning("断点 sims 与当前不一致，忽略旧断点并重跑")
    }
  }

  total <- length(exposures) * length(mediators)
  cli::cli_h2("批量中介: {length(exposures)} X × {length(mediators)} M = {total}（sims={sims}）")
  k <- 0L
  for (x in exposures) {
    for (m in mediators) {
      k <- k + 1L
      key <- paste(x, m, sep = "||")
      if (key %in% done_keys) next
      cli::cli_alert_info("[{k}/{total}] {x} → {m} → {outcome}")
      one <- tryCatch(
        modmed_run_mediate(
          data, exposure = x, mediator = m, outcome = outcome,
          sims = sims, seed = seed + k, covariates = covariates
        ),
        error = function(e) {
          cli::cli_alert_warning("失败: {e$message}")
          NULL
        }
      )
      if (!is.null(one)) rows[[length(rows) + 1L]] <- one
      done_keys <- c(done_keys, key)
      saveRDS(list(rows = rows, done_keys = done_keys, sims = sims), partial_path)
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else {
    data.frame(
      exposure = character(), mediator = character(), significant = logical(),
      stringsAsFactors = FALSE
    )
  }
  sig <- tab[isTRUE(tab$significant) | tab$significant %in% TRUE, , drop = FALSE]

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  modmed_write_csv(tab, file.path(tbl_dir, "Table_Mediation_Batch.csv"))
  modmed_write_csv(sig, file.path(tbl_dir, "Table_Mediation_Significant.csv"))

  ctx$results$modmed_mediation_table <- tab
  ctx$results$modmed_significant <- sig
  ctx$results$modmed_significant_pairs <- if (nrow(sig)) {
    unique(sig[, c("exposure", "mediator"), drop = FALSE])
  } else {
    data.frame(exposure = character(), mediator = character(), stringsAsFactors = FALSE)
  }

  cli::cli_alert_success(
    "中介完成: {nrow(tab)} 行，显著 {nrow(sig)}（ACME CI 不含 0）"
  )
  ctx
}

register_block("modmed_mediation_batch", block_modmed_mediation_batch, "OA Yan2026: 批量中介与筛选")
