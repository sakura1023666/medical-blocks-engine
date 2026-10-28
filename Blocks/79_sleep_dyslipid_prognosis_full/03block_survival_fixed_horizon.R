###############################################################################
#  survival_fixed_horizon — 固定随访窗口（主分析 2 年）与心血管死亡 Fine–Gray
#
#  register_block: "survival_fixed_horizon"
#  典型流水线: sleep_duration_range 之后
#
#  config$prognosis_v2$horizon_years = 2
#  config$prognosis_v2$horizon_alt_years = 5
#  备选窗口只对 NHANES / SHHS 打开。CHARLS 若只有到 2013 的结局，不硬做 5 年。
#
#  写: event_h / time_h（主窗口）；Tables/Table_horizon_cox.csv；
#      有 cvd_status 时 Tables/Table_finegray_cvd.csv（敏感性，不是全因主分析）
###############################################################################

if (!exists(".sd_load_common", mode = "function")) {
  .sd_load_common <- function() {
    p <- file.path(getwd(), "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R")
    if (!file.exists(p)) stop("找不到 00_sleep_dyslipid_common.R", call. = FALSE)
    source(p, local = FALSE)
  }
}

.sd_apply_horizon <- function(d, years) {
  d$time_h <- pmin(d$futime_years, years)
  d$event_h <- as.integer(d$fustatus == 1L & d$futime_years <= years)
  d
}

block_survival_fixed_horizon <- function(ctx, ...) {
  .sd_load_common()
  if (!.sd_ready(ctx)) {
    cli::cli_alert_warning("固定窗口跳过：还没有可建模的死亡时间")
    return(ctx)
  }
  cfg <- .sd_cfg(ctx)
  d <- .sd_dat(ctx)
  h_main <- as.numeric(cfg$horizon_years %||% 2)
  d <- .sd_apply_horizon(d, h_main)
  db <- toupper(as.character(ctx$results$prognosis_v2_database %||% cfg$database %||% "")[1L])
  h_alt <- as.numeric(cfg$horizon_alt_years %||% 5)
  do_alt <- db %in% c("NHANES", "SHHS") && is.finite(h_alt) &&
    max(d$futime_years, na.rm = TRUE) > h_main
  if (do_alt) {
    d$time_alt <- pmin(d$futime_years, h_alt)
    d$event_alt <- as.integer(d$fustatus == 1L & d$futime_years <= h_alt)
  }
  ctx <- .sd_put(ctx, d)

  d$time <- d$time_h
  d$event <- d$event_h
  w <- if (any(!is.na(d$survey_weight))) d$survey_weight else NULL
  rows <- list()
  fit1 <- tryCatch(.sd_fit_cox(d$time, d$event, "Sleep_Group", d, w), error = function(e) NULL)
  if (!is.null(fit1)) rows[[length(rows) + 1L]] <- .sd_cox_table(fit1, sprintf("horizon_%sy_crude", h_main))
  if (all(c("Age", "Gender") %in% names(d))) {
    fit2 <- tryCatch(.sd_fit_cox(d$time, d$event, "Sleep_Group + Age + Gender", d, w), error = function(e) NULL)
    if (!is.null(fit2)) rows[[length(rows) + 1L]] <- .sd_cox_table(fit2, sprintf("horizon_%sy_age_sex", h_main))
  }
  if (do_alt) {
    d$time <- d$time_alt
    d$event <- d$event_alt
    fita <- tryCatch(.sd_fit_cox(d$time, d$event, "Sleep_Group", d, w), error = function(e) NULL)
    if (!is.null(fita)) rows[[length(rows) + 1L]] <- .sd_cox_table(fita, sprintf("horizon_%sy_crude", h_alt))
  }
  if (length(rows)) {
    .sd_write_csv(do.call(rbind, rows), file.path(.sd_dir(ctx, "tables"), "Table_horizon_cox.csv"))
  }

  fg_note <- "全因死亡没有竞争事件。Fine–Gray 只在能分出心血管死亡时作为敏感性。"
  if ("cvd_status" %in% names(d) && any(d$cvd_status == 1L, na.rm = TRUE) &&
      requireNamespace("cmprsk", quietly = TRUE)) {
    # 1 = 心血管死亡，2 = 其他死亡，0 = 删失
    fstatus <- ifelse(d$cvd_status == 1L, 1L,
                      ifelse(d$fustatus == 1L, 2L, 0L))
    cov <- stats::model.matrix(~ Sleep_Group, data = d)[, -1L, drop = FALSE]
    fit <- tryCatch(
      cmprsk::crr(ftime = d$futime_years, fstatus = fstatus, cov1 = cov, failcode = 1, cencode = 0),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      sm <- summary(fit)
      fg <- data.frame(
        term = rownames(sm$coef),
        sHR = round(sm$conf.int[, "exp(coef)"], 3),
        lo = round(sm$conf.int[, "2.5%"], 3),
        hi = round(sm$conf.int[, "97.5%"], 3),
        p = signif(sm$coef[, "p-value"], 3),
        stringsAsFactors = FALSE
      )
      .sd_write_csv(fg, file.path(.sd_dir(ctx, "tables"), "Table_finegray_cvd.csv"))
      ctx$results$finegray_cvd <- fg
      fg_note <- "已输出心血管死亡 Fine–Gray 敏感性。"
    }
  }
  writeLines(fg_note, file.path(.sd_dir(ctx, "tables"), "FineGray_note.txt"))
  ctx$results$survival_fixed_horizon <- list(horizon_years = h_main, alt = if (do_alt) h_alt else NA_real_)
  cli::cli_alert_success("固定窗口 {h_main} 年已生成。{fg_note}")
  ctx
}

register_block("survival_fixed_horizon", block_survival_fixed_horizon,
               "预后2.0 固定随访窗口与心血管死亡 Fine-Gray")
