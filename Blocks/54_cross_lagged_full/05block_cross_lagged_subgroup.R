###############################################################################
#  cross_lagged_subgroup — 亚组 Cox（性别/年龄）
###############################################################################

block_cross_lagged_subgroup <- function(ctx, ...) {
  bl <- ctx$config$cross_lagged %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("cross_lagged_subgroup: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  fi_var <- bl$fi_var %||% "FI_T1"
  time_var <- bl$time_var %||% "futime"
  event_var <- bl$event_var %||% "CVD_event"
  strata <- bl$subgroup_vars %||% c("Gender")
  rows <- list()
  for (sg in strata) {
    if (!sg %in% names(data)) next
    for (lv in unique(data[[sg]])) {
      sub <- data[data[[sg]] == lv, , drop = FALSE]
      if (nrow(sub) < 20L) next
      fit <- tryCatch(
        survival::coxph(as.formula(paste0("Surv(", time_var, ",", event_var, ")~", fi_var)), data = sub),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      s <- summary(fit)
      rows[[length(rows) + 1L]] <- data.frame(
        subgroup = sg, level = as.character(lv), n = nrow(sub),
        HR = round(s$conf.int[fi_var, "exp(coef)"], 3),
        p = signif(s$coefficients[fi_var, "Pr(>|z|)"], 3),
        stringsAsFactors = FALSE
      )
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no subgroup")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Subgroup_Frailty_CVD.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$cross_lagged_subgroup <- list(table = tab)
  cli::cli_alert_success("亚组 Cox 完成")
  ctx
}

register_block("cross_lagged_subgroup", block_cross_lagged_subgroup, "亚组 Cox")
