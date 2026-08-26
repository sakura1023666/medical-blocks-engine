###############################################################################
#  cftraj_wide_to_long — 认知总分/情景记忆 2011–2018 宽转长
#  文献: Ma 2026 Alzheimers Dement CHARLS 认知轨迹
###############################################################################

block_cftraj_wide_to_long <- function(ctx, ...) {
  suppressPackageStartupMessages(library(tidyr))
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_data_utils.R"), local = FALSE)
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("cftraj_wide_to_long: 无数据", call. = FALSE)

  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "ID"
  data <- literature_ensure_id_column(data, id_col)
  waves <- as.character(bl$cognitive_waves %||% c(2011, 2013, 2015, 2018))

  .pivot_cog <- function(prefix, label) {
    cols <- paste0(prefix, waves)
    hit <- intersect(cols, names(data))
    if (!length(hit)) {
      pat <- paste0("^", prefix)
      hit <- grep(pat, names(data), value = TRUE)
    }
    if (!length(hit)) {
      cli::cli_alert_warning("未找到认知列 prefix={prefix}")
      return(NULL)
    }
    long <- tidyr::pivot_longer(
      data, tidyr::all_of(hit),
      names_to = "time_label", values_to = "Value"
    )
    long$Time <- suppressWarnings(as.numeric(sub(prefix, "", long$time_label, fixed = TRUE)))
    if (any(is.na(long$Time))) {
      long$Time <- suppressWarnings(as.numeric(gsub("[^0-9]", "", long$time_label)))
    }
    long <- long[!is.na(long$Value) & !is.na(long$Time), , drop = FALSE]
    long$cognitive_domain <- label
    if ("Cohort" %in% names(data) && id_col %in% names(long)) {
      long <- merge(long, unique(data[, c(id_col, "Cohort")]), by = id_col, all.x = TRUE)
    }
    long
  }

  global_prefix <- bl$cognitive_wave_prefix %||% "CogGlobal_"
  episodic_prefix <- bl$cognitive_episodic_prefix %||% "CogEpisodic_"
  long_global <- .pivot_cog(global_prefix, "global")
  long_episodic <- .pivot_cog(episodic_prefix, "episodic_memory")
  if (is.null(long_global) && is.null(long_episodic))
    stop("cftraj_wide_to_long: 未找到认知宽表列", call. = FALSE)

  if (is.null(ctx$data$cftraj_long)) ctx$data$cftraj_long <- list()
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "CfTraj")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(long_global)) {
    ctx$data$cftraj_long$global <- long_global
    csv_g <- file.path(out_dir, "_cftraj_global_long.csv")
    utils::write.csv(long_global, csv_g, row.names = FALSE)
  }
  if (!is.null(long_episodic)) {
    ctx$data$cftraj_long$episodic <- long_episodic
    csv_e <- file.path(out_dir, "_cftraj_episodic_long.csv")
    utils::write.csv(long_episodic, csv_e, row.names = FALSE)
  }

  long_all <- if (!is.null(long_global) && !is.null(long_episodic)) {
    if (requireNamespace("dplyr", quietly = TRUE)) {
      dplyr::bind_rows(long_global, long_episodic)
    } else {
      cn <- union(names(long_global), names(long_episodic))
      for (nm in setdiff(cn, names(long_global))) long_global[[nm]] <- NA
      for (nm in setdiff(cn, names(long_episodic))) long_episodic[[nm]] <- NA
      rbind(long_global[, cn, drop = FALSE], long_episodic[, cn, drop = FALSE])
    }
  } else long_global %||% long_episodic
  utils::write.csv(utils::head(long_all, 5000L), file.path(out_dir, "Table_CfTraj_Cognitive_Long_Preview.csv"), row.names = FALSE)

  ctx$results$cftraj_wide_to_long <- list(
    n_global = if (!is.null(long_global)) nrow(long_global) else 0L,
    n_episodic = if (!is.null(long_episodic)) nrow(long_episodic) else 0L,
    waves = waves, output_dir = out_dir
  )
  cli::cli_alert_success("认知宽转长完成 (waves={paste(waves, collapse=', ')})")
  ctx
}

register_block("cftraj_wide_to_long", block_cftraj_wide_to_long, "认知 2011-2018 宽转长")
