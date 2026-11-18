# prognosis_v2 Table 1 helpers: descriptive cells + standardized mean difference (SMD)
# Used by remirror / repair scripts. SMD formulas follow Austin (2009) / tableone.

pv2_smd_continuous <- function(x0, x1) {
  x0 <- as.numeric(x0); x0 <- x0[is.finite(x0)]
  x1 <- as.numeric(x1); x1 <- x1[is.finite(x1)]
  if (length(x0) < 2L || length(x1) < 2L) return(NA_real_)
  s0 <- stats::sd(x0); s1 <- stats::sd(x1)
  sp <- sqrt((s0^2 + s1^2) / 2)
  if (!is.finite(sp) || sp <= 0) return(NA_real_)
  (mean(x1) - mean(x0)) / sp
}

pv2_smd_binary <- function(x0, x1, level) {
  p0 <- mean(as.character(x0) == as.character(level), na.rm = TRUE)
  p1 <- mean(as.character(x1) == as.character(level), na.rm = TRUE)
  if (!is.finite(p0) || !is.finite(p1)) return(NA_real_)
  p <- (p0 + p1) / 2
  den <- sqrt(p * (1 - p))
  if (!is.finite(den) || den <= 0) return(0)
  (p1 - p0) / den
}

pv2_fmt_smd <- function(x) {
  x <- as.numeric(x)[1L]
  if (!is.finite(x)) return("")
  sprintf("%.3f", x)
}

#' Build a Survivor / Non-survivor baseline body with SMD column.
#' @param d analysis data.frame with status factor (Survivor, Non-survivor)
#' @param layout named list of sections: each list(cont=named char, cats=named list of levels)
#' @param cat_lab named character display labels for categorical vars
#' @return list(body, level_rows, section_names)
pv2_baseline_survivor_smd_body <- function(
    d,
    layout,
    cat_lab = character(0),
    fmt_p = function(p) {
      p <- as.numeric(p)[1L]
      if (!is.finite(p)) return("")
      if (p < 0.001) "<0.001" else sprintf("%.3f", p)
    },
    mean_sd = function(x) sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE)),
    med_iqr = function(x) {
      q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
      sprintf("%.2f (%.2f, %.2f)", q[2], q[1], q[3])
    },
    n_pct = function(k, n) sprintf("%d (%.1f%%)", k, if (n > 0) 100 * k / n else NA_real_),
    is_normal_vec = function(x) {
      x <- x[!is.na(x)]
      if (length(x) < 3L) return(FALSE)
      p <- tryCatch(
        if (length(x) > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value,
        error = function(e) 0
      )
      is.finite(p) && p >= 0.05
    }
) {
  stopifnot("status" %in% names(d))
  slices <- list(
    Overall = d,
    Survivor = d[d$status == "Survivor", , drop = FALSE],
    `Non-survivor` = d[d$status == "Non-survivor", , drop = FALSE]
  )
  g0 <- slices$Survivor
  g1 <- slices[["Non-survivor"]]
  rows <- list()
  level_rows <- integer(0)
  section_names <- character(0)
  add <- function(lab, vals, p = "", smd = "") {
    rows[[length(rows) + 1L]] <<- c(lab, vals, p, smd)
  }
  cont_cell <- function(dd, var, normal) {
    if (normal) mean_sd(dd[[var]]) else med_iqr(dd[[var]])
  }
  cat_cell <- function(dd, var, lv) {
    k <- sum(as.character(dd[[var]]) == lv, na.rm = TRUE)
    n <- sum(!is.na(dd[[var]]))
    n_pct(k, n)
  }
  for (sec in names(layout)) {
    section_names <- c(section_names, sec)
    add(sec, rep("", 3L), "", "")
    spec <- layout[[sec]]
    for (v in names(spec$cont %||% character(0))) {
      if (!v %in% names(d)) next
      normal <- is_normal_vec(d[[v]])
      vals <- vapply(slices, function(dd) cont_cell(dd, v, normal), character(1))
      p <- tryCatch(stats::wilcox.test(d[[v]] ~ d$status)$p.value, error = function(e) NA_real_)
      smd <- pv2_smd_continuous(g0[[v]], g1[[v]])
      add(spec$cont[[v]], vals, fmt_p(p), pv2_fmt_smd(smd))
    }
    for (v in names(spec$cats %||% list())) {
      if (!v %in% names(d)) next
      p <- tryCatch({
        tab <- table(d[[v]], d$status)
        if (any(tab < 5)) stats::fisher.test(tab)$p.value else suppressWarnings(stats::chisq.test(tab)$p.value)
      }, error = function(e) NA_real_)
      add(unname(cat_lab[[v]] %||% v), rep("", 3L), fmt_p(p), "")
      for (lv in spec$cats[[v]]) {
        level_rows <- c(level_rows, length(rows) + 1L)
        vals <- vapply(slices, function(dd) cat_cell(dd, v, lv), character(1))
        smd <- pv2_smd_binary(g0[[v]], g1[[v]], lv)
        add(paste0("  ", lv), vals, "", pv2_fmt_smd(smd))
      }
    }
  }
  headers <- c(
    sprintf("Overall, N = %d", nrow(slices$Overall)),
    sprintf("Survivor, N = %d", nrow(slices$Survivor)),
    sprintf("Non-survivor, N = %d", nrow(slices[["Non-survivor"]]))
  )
  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c("Characteristic", headers, "p-value", "SMD")
  list(body = body, level_rows = level_rows, section_names = section_names)
}

#' Absolute risk difference + NNT from observed events (High vs Low).
pv2_absolute_risk_from_events <- function(n_low, deaths_low, n_high, deaths_high) {
  r_low <- as.numeric(deaths_low) / max(as.numeric(n_low), 1)
  r_high <- as.numeric(deaths_high) / max(as.numeric(n_high), 1)
  rd <- r_high - r_low
  nnt <- if (is.finite(rd) && abs(rd) > 0) 1 / abs(rd) else NA_real_
  list(
    risk_low_pct = 100 * r_low,
    risk_high_pct = 100 * r_high,
    rd_pct = 100 * rd,
    nnt = nnt,
    deaths_low = as.integer(deaths_low),
    deaths_high = as.integer(deaths_high),
    n_low = as.integer(n_low),
    n_high = as.integer(n_high)
  )
}
