# ExWAS / 环境暴露发表数字位数（引擎级）
# 对标环境暴露 ExWAS 主文/补充表常见口径（OR 三位、P/q 三位、<0.001；E-value 三位；
# 描述 median/IQR 三位；权重三位）。禁止课题手写 sprintf 分叉。
#
#   source("R/exwas_pub_digits.R")
#   exwas_apply_pub_digits(config)

exwas_pub_digits_spec <- function() {
  list(
    # 效应量 OR / CI / E-value / β
    est = 3L,
    # P / q：固定 3 位；极小值 <0.001（与文献表 P 列一致）
    p = 3L,
    p_style = "fixed",
    # 描述：median/IQR、%、LOD 等上限 3 位并 trim
    desc = 3L,
    desc_trim = TRUE,
    cutoff = 3L,
    int_big_mark = TRUE,
    # 混合物权重
    weight = 3L,
    # 纳入频率
    freq = 3L
  )
}

exwas_apply_pub_digits <- function(config = NULL) {
  spec <- exwas_pub_digits_spec()
  if (is.null(config)) config <- list()
  if (!is.list(config$pub_digits)) config$pub_digits <- list()
  for (nm in names(spec)) {
    if (is.null(config$pub_digits[[nm]])) config$pub_digits[[nm]] <- spec[[nm]]
  }
  if (exists("pipeline_apply_pub_digits", mode = "function")) {
    config <- pipeline_apply_pub_digits(config)
  }
  invisible(config)
}

exwas_fmt_or_ci <- function(or, lo, hi, digits = 3L) {
  or <- as.numeric(or); lo <- as.numeric(lo); hi <- as.numeric(hi)
  d <- as.integer(digits)[1L]
  ifelse(
    is.finite(or) & is.finite(lo) & is.finite(hi),
    sprintf(paste0("%.", d, "f (%.", d, "f, %.", d, "f)"), or, lo, hi),
    ""
  )
}

exwas_fmt_p <- function(p, digits = 3L) {
  if (exists("pub_format_p", mode = "function")) {
    return(vapply(as.numeric(p), function(x) {
      if (!is.finite(x)) return("")
      pub_format_p(x, style = "fixed", digits = as.integer(digits)[1L])
    }, character(1)))
  }
  vapply(as.numeric(p), function(x) {
    if (!is.finite(x)) return("")
    if (x < 0.001) "<0.001" else sprintf(paste0("%.", as.integer(digits)[1L], "f"), x)
  }, character(1))
}

exwas_fmt_evalue <- function(ev, ev_ci, digits = 3L) {
  ev <- as.numeric(ev); ev_ci <- as.numeric(ev_ci)
  d <- as.integer(digits)[1L]
  ifelse(
    is.finite(ev) & is.finite(ev_ci),
    sprintf(paste0("%.", d, "f (%.", d, "f)"), ev, ev_ci),
    ""
  )
}

exwas_fmt_weight <- function(w, digits = 3L) {
  w <- as.numeric(w)
  d <- as.integer(digits)[1L]
  # 真零写成 "0"（勿 0.000，避免发表数字门控误判为裸 P）
  ifelse(
    is.finite(w),
    ifelse(abs(w) < 5 * 10^(-(d + 1L)), "0", sprintf(paste0("%.", d, "f"), w)),
    ""
  )
}

exwas_fmt_coef <- function(b, digits = 3L) {
  b <- as.numeric(b)
  d <- as.integer(digits)[1L]
  ifelse(
    is.finite(b),
    ifelse(abs(b) < 0.001 & abs(b) > 0, "<0.001",
           ifelse(abs(b) < 5 * 10^(-(d + 1L)), "0", sprintf(paste0("%.", d, "f"), b))),
    ""
  )
}

exwas_display_label <- function(x) {
  x <- as.character(x)
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}
