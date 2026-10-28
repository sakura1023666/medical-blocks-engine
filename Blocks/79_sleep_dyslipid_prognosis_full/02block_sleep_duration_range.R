###############################################################################
#  sleep_duration_range — 短 / 7–8 / 长 主分组，RCS 谷底核对，连续与四分位作辅
#
#  register_block: "sleep_duration_range"
#  典型流水线: sleep_dyslipid_cohort 之后
#
#  config$prognosis_v2$short_lt = 7
#  config$prognosis_v2$long_ge = 9
#  config$prognosis_v2$full_covariates = c("Age","Gender","BMI")
#
#  写: Sleep_Group、Sleep_Q；Tables 主 Cox / 辅表 / 人年发病率；
#      Figures RCS 与 KM。随访时间进入 Cox 与 KM，不把死亡压成无关时间的 0/1。
###############################################################################

# .sd_load_common 由 01 块定义；单独 source 本文件时再补一次
if (!exists(".sd_load_common", mode = "function")) {
  .sd_load_common <- function() {
    p <- file.path(getwd(), "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R")
    if (!file.exists(p)) stop("找不到 00_sleep_dyslipid_common.R", call. = FALSE)
    source(p, local = FALSE)
  }
}

.sd_rcs_nadir <- function(data) {
  d <- data[!is.na(data$Sleep_hours) & !is.na(data$futime_years) & !is.na(data$fustatus), , drop = FALSE]
  if (nrow(d) < 40L || length(unique(d$fustatus)) < 2L) return(list(nadir = NA_real_, p_overall = NA_real_))
  d$time <- d$futime_years
  d$event <- d$fustatus
  fit <- tryCatch(
    survival::coxph(survival::Surv(time, event) ~ splines::ns(Sleep_hours, df = 3), data = d, ties = "efron"),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(nadir = NA_real_, p_overall = NA_real_))
  grid <- seq(max(3, min(d$Sleep_hours, na.rm = TRUE)),
              min(12, max(d$Sleep_hours, na.rm = TRUE)), length.out = 91)
  nd <- data.frame(Sleep_hours = grid)
  lp <- as.numeric(stats::predict(fit, newdata = nd, type = "lp"))
  nadir <- grid[which.min(lp)]
  p_overall <- tryCatch(summary(fit)$logtest["pvalue"], error = function(e) NA_real_)
  list(nadir = nadir, p_overall = p_overall, grid = grid, lp = lp - min(lp))
}

block_sleep_duration_range <- function(ctx, ...) {
  .sd_load_common()
  if (!.sd_ready(ctx)) {
    cli::cli_alert_warning("睡眠分组跳过：纳排尚未同时具备睡眠和死亡时间")
    return(ctx)
  }
  cfg <- .sd_cfg(ctx)
  d <- .sd_dat(ctx)
  short_lt <- cfg$short_lt %||% 7
  long_ge <- cfg$long_ge %||% 9
  d$Sleep_Group <- .sd_sleep_group(d$Sleep_hours, short_lt, long_ge)
  d$Sleep_Q <- .sd_quartiles(d$Sleep_hours)
  d <- d[!is.na(d$Sleep_Group), , drop = FALSE]
  ctx <- .sd_put(ctx, d)

  rcs <- .sd_rcs_nadir(d)
  nadir_in <- !is.na(rcs$nadir) && rcs$nadir >= short_lt && rcs$nadir < long_ge
  nadir_df <- data.frame(
    nadir_hours = round(rcs$nadir, 3),
    p_spline = signif(rcs$p_overall, 3),
    inside_recommended_7_8 = nadir_in,
    stringsAsFactors = FALSE
  )
  .sd_write_csv(nadir_df, file.path(.sd_dir(ctx, "tables"), "RCS_nadir_check.csv"))

  d$time <- d$futime_years
  d$event <- as.integer(d$fustatus)
  w <- if (any(!is.na(d$survey_weight))) d$survey_weight else NULL
  full_cov <- intersect(cfg$full_covariates %||% c("Age", "Gender", "BMI"), names(d))
  full_cov <- full_cov[vapply(full_cov, function(v) {
    x <- d[[v]]
    sum(!is.na(x)) > 10 && length(unique(x[!is.na(x)])) > 1
  }, logical(1))]

  tabs <- list()
  .one <- function(rhs, model) {
    fit <- tryCatch(.sd_fit_cox(d$time, d$event, rhs, d, w), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    .sd_cox_table(fit, model)
  }
  tabs[[1]] <- .one("Sleep_Group", "range_crude")
  if ("Age" %in% names(d) && "Gender" %in% names(d)) {
    tabs[[length(tabs) + 1L]] <- .one("Sleep_Group + Age + Gender", "range_age_sex")
  }
  if (length(full_cov)) {
    tabs[[length(tabs) + 1L]] <- .one(
      paste(c("Sleep_Group", full_cov), collapse = " + "), "range_full"
    )
  }
  tabs[[length(tabs) + 1L]] <- .one("Sleep_hours", "continuous_per_hour")
  if (nlevels(droplevels(d$Sleep_Q)) >= 2L) {
    tabs[[length(tabs) + 1L]] <- .one("Sleep_Q", "quartile_auxiliary")
  }
  tab <- do.call(rbind, tabs)
  .sd_write_csv(tab, file.path(.sd_dir(ctx, "tables"), "Table_sleep_cox.csv"))

  py <- lapply(levels(d$Sleep_Group), function(g) {
    sub <- d[d$Sleep_Group == g, , drop = FALSE]
    data.frame(
      Sleep_Group = g,
      N = nrow(sub),
      Events = sum(sub$event == 1, na.rm = TRUE),
      Person_years = round(sum(sub$time, na.rm = TRUE), 3),
      Rate_per_10000py = round(1e4 * sum(sub$event == 1, na.rm = TRUE) / sum(sub$time, na.rm = TRUE), 3),
      stringsAsFactors = FALSE
    )
  })
  .sd_write_csv(do.call(rbind, py), file.path(.sd_dir(ctx, "tables"), "Table_person_year.csv"))

  if (!is.null(rcs$grid)) {
    pdf(file.path(.sd_dir(ctx, "figures"), "Figure_RCS_sleep.pdf"), width = 6, height = 4.5)
    plot(rcs$grid, exp(rcs$lp), type = "l", lwd = 2,
         xlab = "Sleep hours", ylab = "Relative hazard (nadir = 1)",
         main = sprintf("RCS nadir %.2f h", rcs$nadir))
    abline(v = c(short_lt, long_ge), lty = 2, col = "grey40")
    dev.off()
  }
  sf <- tryCatch(survival::survfit(survival::Surv(time, event) ~ Sleep_Group, data = d), error = function(e) NULL)
  if (!is.null(sf)) {
    pdf(file.path(.sd_dir(ctx, "figures"), "Figure_KM_sleep_group.pdf"), width = 6.5, height = 4.8)
    plot(sf, col = c("#222222", "#C0392B", "#2471A3"), lwd = 2,
         xlab = "Follow-up (years)", ylab = "Survival",
         main = "All-cause death by sleep range")
    legend("bottomleft", legend = levels(d$Sleep_Group),
           col = c("#222222", "#C0392B", "#2471A3"), lwd = 2, bty = "n")
    dev.off()
  }
  ctx$results$sleep_duration_range <- list(nadir = nadir_df, cox = tab)
  cli::cli_alert_success("睡眠范围 Cox 已写出；RCS 谷底 {round(rcs$nadir, 2)} h，落在 7–8：{nadir_in}")
  ctx
}

register_block("sleep_duration_range", block_sleep_duration_range,
               "预后2.0 睡眠范围主分析与 RCS 谷底核对")
