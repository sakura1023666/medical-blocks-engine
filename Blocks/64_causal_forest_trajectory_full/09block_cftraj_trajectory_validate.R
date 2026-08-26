###############################################################################
#  cftraj_trajectory_validate — 轨迹类比例 + multinomial OR 与 Ma 2026 原文对照
###############################################################################

.cftraj_read_lcmm_pct <- function(out_base, domain) {
  fname <- if (domain == "episodic") "Table_CfTraj_LCMM_Assignment_episodic.csv" else "Table_CfTraj_LCMM_Assignment.csv"
  paths <- literature_find_table(out_base, fname)
  unit_pref <- if (domain == "episodic") "Episodic" else "Global"
  hit <- paths[grepl(paste0("/by_unit/", unit_pref, "/"), paths)][1L]
  if (is.na(hit) || !nzchar(hit)) hit <- paths[1L]
  if (is.na(hit) || !file.exists(hit)) return(NULL)
  df <- utils::read.csv(hit, stringsAsFactors = FALSE)
  lab_col <- intersect(c("trajectory_class_label", "trajectory_label", "class_label"), names(df))[1L]
  if (is.na(lab_col)) {
    if ("trajectory_class" %in% names(df)) {
      df$trajectory_class_label <- c("high", "moderate", "low")[pmin(df$trajectory_class + 1L, 3L)]
      lab_col <- "trajectory_class_label"
    } else return(NULL)
  }
  prop.table(table(df[[lab_col]])) * 100
}

block_cftraj_trajectory_validate <- function(ctx, ...) {
  bl <- ctx$config$cftraj %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  out_base <- literature_batch_output_base(ctx)

  targets <- bl$literature_trajectory_pct %||% c(high = 40.29, moderate = 43.78, low = 15.93)
  or_targets <- bl$literature_or_targets %||% list(
    global_low = list(OR = 1.27, lo = 1.06, hi = 1.52),
    episodic_low = list(OR = 1.28, lo = 1.06, hi = 1.55)
  )
  tol <- as.numeric(bl$literature_tol_pct %||% 15)
  rows <- list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  for (domain in c("global", "episodic")) {
    y_col <- if (domain == "global") "trajectory_class_label" else "trajectory_class_label_episodic"
    tab <- NULL
    if (!is.null(data) && y_col %in% names(data)) tab <- prop.table(table(data[[y_col]])) * 100
    if (is.null(tab)) tab <- .cftraj_read_lcmm_pct(out_base, domain)
    if (is.null(tab)) next
    for (nm in names(targets)) {
      if (!nm %in% names(tab)) next
      rows[[length(rows) + 1L]] <- cbind(
        literature_compare_metric(tab[[nm]], targets[[nm]], tol, paste0(domain, "_pct_", nm)),
        domain = domain, class = nm
      )
    }
  }

  mn_dir <- file.path(out_base, "Tables", "CfTraj")
  for (domain in c("global", "episodic")) {
    f <- file.path(mn_dir, paste0("Table_CfTraj_Multinomial_CircS_", domain, ".csv"))
    if (!file.exists(f)) {
      hits <- literature_find_table(out_base, paste0("Table_CfTraj_Multinomial_CircS_", domain, ".csv"))
      f <- hits[1L]
    }
    if (is.na(f) || !file.exists(f)) {
      hits <- literature_find_table(out_base, "Table_CfTraj_Multinomial_CircS.csv")
      f <- hits[grepl(paste0("/by_unit/", if (domain == "episodic") "Episodic" else "Global", "/"), hits)][1L]
    }
    if (is.na(f) || !file.exists(f)) next
    mn <- utils::read.csv(f, stringsAsFactors = FALSE)
    low_hit <- mn[grepl("low", mn$outcome_class, ignore.case = TRUE), , drop = FALSE]
    if (nrow(low_hit)) {
      tgt <- if (domain == "episodic") or_targets$episodic_low else or_targets$global_low
      rows[[length(rows) + 1L]] <- cbind(
        literature_compare_metric(low_hit$OR[1L], tgt$OR, tol, paste0(domain, "_CircS→low OR")),
        domain = domain, class = "OR_low"
      )
    }
  }

  out <- file.path(mn_dir, "Table_CfTraj_Literature_Validation.csv")
  tab <- literature_write_validation(rows, out, meta = list(
    paper = "Ma 2026 Alz Dement",
    note = "smoke/LCMM-Python 回退时比例/OR 不与原文一致；需 CHARLS 真实数据 + R lcmm"
  ))
  n_pass <- sum(tab$within_tol %in% TRUE, na.rm = TRUE)
  n_tot <- sum(!is.na(tab$within_tol))
  ctx$results$cftraj_trajectory_validate <- list(table = tab, pass = n_pass, total = n_tot)
  cli::cli_alert_success("CfTraj 文献对照: {n_pass}/{n_tot} 通过（smoke 预期 FAIL）")
  ctx
}

register_block("cftraj_trajectory_validate", block_cftraj_trajectory_validate, "轨迹比例/OR 原文对照")
