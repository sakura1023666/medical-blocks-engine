###############################################################################
#  modmed_moderated_mediation — Yan2026 步7：有调节中介（条件间接效应）
#
#  register_block: "modmed_moderated_mediation"
###############################################################################

block_modmed_moderated_mediation <- function(ctx, ...) {
  root <- ctx$root %||% getwd()
  source(file.path(root, "R/moderated_mediation_process.R"), local = FALSE)

  cfg <- ctx$config
  bl <- cfg$modmed_moderated_mediation %||% cfg$modmed %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("modmed_moderated_mediation: 无数据", call. = FALSE)

  outcome <- bl$outcome %||% cfg$modmed$outcome %||% "Group_bin"
  sims <- as.integer(bl$sims %||% cfg$modmed$sims %||% 5000L)
  seed <- as.integer(bl$seed %||% cfg$modmed$seed %||% 1234L)
  env_sims <- Sys.getenv("MODMED_SIMS", unset = "")
  if (nzchar(env_sims)) sims <- as.integer(env_sims)

  sig <- ctx$results$modmed_moderation_significant
  if (is.null(sig) || !nrow(sig)) {
    cli::cli_alert_warning("无显著调节路径，跳过有调节中介")
    ctx$results$modmed_moderated_mediation_table <- data.frame()
    return(ctx)
  }

  # 每个 exposure×mediator×moderator 取显著 path（优先 a）
  keys <- unique(sig[, c("exposure", "mediator", "moderator"), drop = FALSE])
  rows <- list()
  for (i in seq_len(nrow(keys))) {
    x <- as.character(keys$exposure[i])
    m <- as.character(keys$mediator[i])
    w <- as.character(keys$moderator[i])
    paths <- unique(as.character(sig$path[
      sig$exposure == x & sig$mediator == m & sig$moderator == w
    ]))
    # 映射到条件间接：有 a 用 a；有 b 用 b；两者都有用 a_and_b
    path_use <- if ("a" %in% paths && "b" %in% paths) {
      "a_and_b"
    } else if ("a" %in% paths) {
      "a"
    } else if ("b" %in% paths) {
      "b"
    } else {
      "a"
    }
    # Gender_num 当作连续 0/1 取两水平
    w_levels <- NULL
    if (identical(w, "Gender_num") || identical(w, "Gender")) {
      if (identical(w, "Gender_num")) {
        w_levels <- c(Female = 0, Male = 1)
      }
    }
    cli::cli_alert_info("有调节中介: {x}→{m} | W={w} | path={path_use}")
    one <- tryCatch(
      modmed_conditional_indirect(
        data, x, m, outcome, w,
        path = path_use, sims = sims, seed = seed + i,
        w_levels = w_levels
      ),
      error = function(e) {
        cli::cli_alert_warning("失败: {e$message}")
        NULL
      }
    )
    if (!is.null(one)) rows[[length(rows) + 1L]] <- one
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  modmed_write_csv(tab, file.path(tbl_dir, "Table_Moderated_Mediation.csv"))
  ctx$results$modmed_moderated_mediation_table <- tab
  cli::cli_alert_success("有调节中介: {nrow(tab)} 行条件间接效应")
  ctx
}

register_block(
  "modmed_moderated_mediation",
  block_modmed_moderated_mediation,
  "OA Yan2026: 有调节中介"
)
