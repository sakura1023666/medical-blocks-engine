###############################################################################
#  bayesian_mediation_horizon — 固定窗口二分类结局上的准贝叶斯中介
#
#  register_block: "bayesian_mediation_horizon"
#  典型流水线: survival_fixed_horizon 之后
#
#  config$prognosis_v2$mediator = "HbA1c"   # 没有则回退 BMI
#  config$prognosis_v2$mediation_sims = 200
#
#  结局是主窗口内是否死亡（event_h），不是无视时间的终身死亡。
#  用 mediation::mediate 的准贝叶斯模拟（sims），报告 ACME / ADE / 中介比例。
#  写: Tables/Table_mediation_horizon.csv
###############################################################################

if (!exists(".sd_load_common", mode = "function")) {
  .sd_load_common <- function() {
    p <- file.path(getwd(), "Blocks/79_sleep_dyslipid_prognosis_full/00_sleep_dyslipid_common.R")
    if (!file.exists(p)) stop("找不到 00_sleep_dyslipid_common.R", call. = FALSE)
    source(p, local = FALSE)
  }
}

block_bayesian_mediation_horizon <- function(ctx, ...) {
  .sd_load_common()
  if (!.sd_ready(ctx)) {
    cli::cli_alert_warning("中介跳过：还没有固定窗口结局")
    return(ctx)
  }
  if (!requireNamespace("mediation", quietly = TRUE)) {
    cli::cli_alert_warning("未安装 mediation 包，中介块跳过。请在 R-4.5.1 安装后再跑。")
    return(ctx)
  }
  cfg <- .sd_cfg(ctx)
  d <- .sd_dat(ctx)
  if (!"event_h" %in% names(d)) return(ctx)
  med <- cfg$mediator %||% "HbA1c"
  if (!med %in% names(d) || sum(!is.na(d[[med]])) < 30L) med <- "BMI"
  if (!med %in% names(d)) {
    cli::cli_alert_warning("没有可用中介列（HbA1c / BMI）")
    return(ctx)
  }
  d <- d[!is.na(d$Sleep_hours) & !is.na(d[[med]]) & !is.na(d$event_h), , drop = FALSE]
  covs <- intersect(c("Age", "Gender"), names(d))
  d$.med <- .sd_num(d[[med]])
  cov_rhs <- if (length(covs)) paste("+", paste(covs, collapse = " + ")) else ""
  model_m <- stats::lm(stats::as.formula(paste(".med ~ Sleep_hours", cov_rhs)), data = d)
  model_y <- stats::glm(stats::as.formula(paste("event_h ~ Sleep_hours + .med", cov_rhs)),
                        data = d, family = stats::binomial())
  sims <- as.integer(cfg$mediation_sims %||% 200L)
  med_out <- tryCatch(
    mediation::mediate(model_m, model_y, treat = "Sleep_hours", mediator = ".med",
                       sims = sims, boot = FALSE),
    error = function(e) e
  )
  if (inherits(med_out, "error")) {
    cli::cli_alert_warning("中介未收敛: {med_out$message}")
    return(ctx)
  }
  sm <- summary(med_out)
  # mediation 对象槽位名在不同版本略有差异，优先取常用字段
  pick <- function(nm) {
    if (!is.null(med_out[[nm]])) return(as.numeric(med_out[[nm]])[1])
    NA_real_
  }
  tab <- data.frame(
    mediator = med,
    outcome = "death_within_primary_horizon",
    ACME = round(pick("d0"), 3),
    ADE = round(pick("z0"), 3),
    Total = round(pick("tau.coef"), 3),
    Prop_mediated = round(pick("n0"), 3),
    sims = sims,
    stringsAsFactors = FALSE
  )
  .sd_write_csv(tab, file.path(.sd_dir(ctx, "tables"), "Table_mediation_horizon.csv"))
  ctx$results$bayesian_mediation_horizon <- tab
  cli::cli_alert_success("固定窗口中介已写出，中介变量 {med}")
  ctx
}

register_block("bayesian_mediation_horizon", block_bayesian_mediation_horizon,
               "预后2.0 固定窗口准贝叶斯中介")
