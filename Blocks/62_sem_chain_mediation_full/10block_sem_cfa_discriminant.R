###############################################################################
#  sem_cfa_discriminant — 两量表 CFA 区分效度（lavaan）
#
#  register_block: "sem_cfa_discriminant"
#  方法目录: Blocks/62_sem_chain_mediation_full/（SEM 族接着排号）
#
#  config$sem_cfa_discriminant = list(
#    factor_a = list(name = "SSD12", items = paste0("SSD12", 1:12)),
#    factor_b = list(name = "Whiteley", items = c("WHITELEY", paste0("WHITELE", 1:7))),
#    estimator = "MLR"
#  )
###############################################################################

block_sem_cfa_discriminant <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$sem_cfa_discriminant %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("sem_cfa_discriminant: 无数据", call. = FALSE)
  if (!requireNamespace("lavaan", quietly = TRUE)) {
    stop("需要 lavaan 包", call. = FALSE)
  }

  fa <- bl$factor_a %||% list()
  fb <- bl$factor_b %||% list()
  a_name <- as.character(fa$name %||% "F1")[1L]
  b_name <- as.character(fb$name %||% "F2")[1L]
  a_items <- intersect(as.character(fa$items %||% character(0)), names(data))
  b_items <- intersect(as.character(fb$items %||% character(0)), names(data))
  if (length(a_items) < 2L || length(b_items) < 2L) {
    stop("sem_cfa_discriminant: 两因子条目不足", call. = FALSE)
  }

  for (v in c(a_items, b_items)) {
    data[[v]] <- suppressWarnings(as.numeric(data[[v]]))
  }
  d <- data[, c(a_items, b_items), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 50L) stop("sem_cfa_discriminant: 完整病例 < 50", call. = FALSE)

  model <- paste0(
    a_name, " =~ ", paste(a_items, collapse = " + "), "\n",
    b_name, " =~ ", paste(b_items, collapse = " + "), "\n",
    a_name, " ~~ ", b_name, "\n"
  )
  est <- as.character(bl$estimator %||% "MLR")[1L]
  fit <- tryCatch(
    lavaan::cfa(model, data = d, estimator = est, std.lv = TRUE),
    error = function(e) {
      cli::cli_alert_warning("MLR 失败，回退 ML: {e$message}")
      lavaan::cfa(model, data = d, estimator = "ML", std.lv = TRUE)
    }
  )
  pe <- lavaan::parameterEstimates(fit, standardized = TRUE)
  fm <- lavaan::fitMeasures(fit, c("cfi", "tli", "rmsea", "srmr", "chisq", "df", "pvalue"))
  phi <- pe[pe$op == "~~" & pe$lhs == a_name & pe$rhs == b_name, , drop = FALSE]
  phi_std <- if (nrow(phi)) as.numeric(phi$std.all[1L]) else NA_real_

  # Fornell–Larcker 粗检：AVE vs 相关^2（简化：标准化载荷平方均值）
  .ave <- function(factor, items) {
    loads <- pe$std.all[pe$op == "=~" & pe$lhs == factor]
    if (!length(loads)) return(NA_real_)
    mean(loads^2, na.rm = TRUE)
  }
  ave_a <- .ave(a_name, a_items)
  ave_b <- .ave(b_name, b_items)
  disc_ok <- is.finite(phi_std) && is.finite(ave_a) && is.finite(ave_b) &&
    (ave_a > phi_std^2) && (ave_b > phi_std^2)

  fit_tab <- data.frame(
    CFI = unname(fm["cfi"]), TLI = unname(fm["tli"]),
    RMSEA = unname(fm["rmsea"]), SRMR = unname(fm["srmr"]),
    phi_std = phi_std, AVE_A = ave_a, AVE_B = ave_b,
    fornell_larcker_pass = disc_ok,
    n = nrow(d), estimator = fit@Options$estimator %||% est
  )

  out_dir <- file.path(ctx$output_dir %||% ".", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(fit_tab, file.path(out_dir, "Table_CFA_discriminant_fit.csv"), row.names = FALSE)
  utils::write.csv(pe, file.path(out_dir, "Table_CFA_parameter_estimates.csv"), row.names = FALSE)

  ctx$results$sem_cfa_discriminant <- list(
    fit = fit, table = fit_tab, model = model, n = nrow(d)
  )
  cli::cli_alert_success(
    "sem_cfa_discriminant: phi={round(phi_std,3)}; Fornell-Larcker={disc_ok}"
  )
  ctx
}

register_block(
  "sem_cfa_discriminant",
  block_sem_cfa_discriminant,
  "两量表 CFA 区分效度"
)
