###############################################################################
#  预后 2.0 公共函数 — 睡眠时长 × 血脂异常 × 死亡
#  不 register_block。由同目录 01–05 块 source。
#  旧预后流水线（config_survival_dual_batch）不引用本文件。
###############################################################################

.sd_cfg <- function(ctx) {
  ctx$config$prognosis_v2 %||% list()
}

.sd_dat <- function(ctx) {
  ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
}

.sd_put <- function(ctx, df) {
  ctx$data$raw <- df
  ctx$data$cleaned <- df
  ctx$data$imputed <- df
  ctx
}

.sd_dir <- function(ctx, kind = c("tables", "figures")) {
  kind <- match.arg(kind)
  p <- if (kind == "tables") ctx$output_dir_tables else ctx$output_dir_figures
  if (is.null(p) || !nzchar(p)) {
    p <- file.path(ctx$config$project$output_dir %||% "Output",
                   if (kind == "tables") "Tables" else "Figures")
  }
  if (!dir.exists(p)) dir.create(p, recursive = TRUE)
  p
}

.sd_write_csv <- function(df, path) {
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

.sd_num <- function(x) suppressWarnings(as.numeric(x))

.sd_dyslipidemia_flag <- function(tg, tc, hdl, ldl) {
  tg <- .sd_num(tg); tc <- .sd_num(tc); hdl <- .sd_num(hdl); ldl <- .sd_num(ldl)
  ldl_use <- ldl
  need <- is.na(ldl_use) & !is.na(tg) & !is.na(tc) & !is.na(hdl) & tg < 400
  ldl_use[need] <- tc[need] - hdl[need] - tg[need] / 5
  abn <- (!is.na(tg) & tg >= 150) |
    (!is.na(tc) & tc >= 200) |
    (!is.na(ldl_use) & ldl_use >= 130) |
    (!is.na(hdl) & hdl <= 40)
  known <- !is.na(tg) | !is.na(tc) | !is.na(hdl) | !is.na(ldl_use)
  flag <- ifelse(!known, NA_integer_, ifelse(abn, 1L, 0L))
  list(flag = flag, ldl_calc = ldl_use)
}

.sd_sleep_group <- function(hours, short_lt = 7, long_ge = 9) {
  h <- .sd_num(hours)
  g <- rep(NA_character_, length(h))
  g[!is.na(h) & h < short_lt] <- "<7"
  g[!is.na(h) & h >= short_lt & h < long_ge] <- "7-8"
  g[!is.na(h) & h >= long_ge] <- ">=9"
  factor(g, levels = c("7-8", "<7", ">=9"))
}

.sd_quartiles <- function(x) {
  x <- .sd_num(x)
  ok <- !is.na(x)
  out <- rep(NA_character_, length(x))
  if (sum(ok) < 8L) return(factor(out))
  qs <- stats::quantile(x[ok], probs = c(0.25, 0.5, 0.75), na.rm = TRUE, type = 7)
  # 左闭右开，最上组含最大值
  br <- c(-Inf, qs, Inf)
  lab <- c("Q1", "Q2", "Q3", "Q4")
  out[ok] <- as.character(cut(x[ok], breaks = br, labels = lab, include.lowest = TRUE, right = FALSE))
  # 最大值若落在右开之外，归入 Q4
  out[ok & is.na(out)] <- "Q4"
  factor(out, levels = lab)
}

.sd_event01 <- function(x, death_values) {
  if (is.null(x)) return(NULL)
  xc <- trimws(as.character(x))
  as.integer(tolower(xc) %in% tolower(death_values) | xc %in% as.character(death_values))
}

.sd_cox_table <- function(fit, model_name) {
  s <- summary(fit)
  ci <- s$conf.int
  co <- s$coefficients
  if (is.null(ci) || !nrow(ci)) {
    return(data.frame(model = model_name, term = NA_character_, HR = NA_real_,
                      lo = NA_real_, hi = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
  }
  data.frame(
    model = model_name,
    term = rownames(ci),
    HR = round(ci[, "exp(coef)"], 3),
    lo = round(ci[, "lower .95"], 3),
    hi = round(ci[, "upper .95"], 3),
    p = signif(co[, "Pr(>|z|)"], 3),
    stringsAsFactors = FALSE
  )
}

.sd_fit_cox <- function(time, event, rhs, data, weights = NULL) {
  fml <- stats::as.formula(paste0("survival::Surv(time, event) ~ ", rhs))
  if (!is.null(weights)) {
    data$.sd_w <- weights
    survival::coxph(fml, data = data, weights = .sd_w, ties = "efron")
  } else {
    survival::coxph(fml, data = data, ties = "efron")
  }
}

.sd_ready <- function(ctx) {
  isTRUE(ctx$results$prognosis_v2_ready)
}
