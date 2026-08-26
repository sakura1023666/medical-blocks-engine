###############################################################################
#  competing_stratified — 分层分析（性别/年龄）
###############################################################################

block_competing_stratified <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_stratified: 无数据", call. = FALSE)
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  if ("Age" %in% names(data)) data$Age_group <- ifelse(data$Age >= 75, "75+", "<75")
  strata <- bl$stratify_vars %||% c("Gender", "Age_group")
  time_var <- bl$time_var %||% "futime"
  event_col <- bl$event_type_col %||% "event_type"
  exp_var <- bl$exposure_var %||% "TyG_quartile"
  data$evt_whf <- as.integer(data[[event_col]] == 1L)
  rows <- list()
  for (sg in strata) {
    if (!sg %in% names(data)) next
    for (lv in unique(data[[sg]])) {
      sub <- data[data[[sg]] == lv, , drop = FALSE]
      if (nrow(sub) < 20L) next
      fit <- tryCatch(survival::coxph(as.formula(paste0("Surv(", time_var, ", evt_whf)~", exp_var)), data = sub), error = function(e) NULL)
      if (is.null(fit)) next
      s <- summary(fit)
      rows[[length(rows) + 1L]] <- data.frame(strata = sg, level = as.character(lv), n = nrow(sub),
        HR = round(s$conf.int[1, "exp(coef)"], 3), p = signif(s$coefficients[1, "Pr(>|z|)"], 3),
        stringsAsFactors = FALSE)
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no strata")
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables",
                    paste0("Table_Stratified_", bl$index_var %||% "TyG", ".csv"))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)
  ctx$results$competing_stratified <- list(table = tab)
  cli::cli_alert_success("分层分析完成")
  ctx
}

register_block("competing_stratified", block_competing_stratified, "分层分析")
