###############################################################################
# literature_trajectory_joint_pub.R — 联合轨迹发病 对标文献版式产物
#   （Liu et al. 2026 "Joint longitudinal trajectories..." Fig1-5 / ST1-8）
#
# 图面板（拼成主图，单页 ≤ 11 in）：
#   tj_panel_ridge      Fig2 对标：各指标逐波 ridge 密度
#   tj_panel_select     Fig3A/B 对标：逐体系 AIC/BIC（+entropy）vs K
#   tj_panel_joint_traj Fig3C/D 对标：双指标原始尺度 类别均值轨迹（含 SE 带）
#   tj_panel_cuminc     Fig4 对标：累积发病率 1-S(t) + Number at risk
# 表：
#   tj_lit_missing_table   ST2 对标：协变量缺失率
#   tj_lit_wave_desc_table ST3 对标：各指标逐波描述统计
#   tj_lit_merge_ic        ST4 对标：全体系选型标准合并表
#   tj_lit_discrim_table   ST8 对标：C-index / NRI / IDI 判别力比较
#
# 依赖 R/literature_trajectory_joint.R 的 tj_theme；字体/三行表/QC 与 pub_* 铁律一致。
###############################################################################

## ── 面板：Ridge 密度（每波一条，原始尺度）──────────────────────────────────
tj_panel_ridge <- function(df, ind, wave_cols, id_col = "id", fam = "serif",
                           lab = NULL) {
  lab <- lab %||% ind
  rows <- do.call(rbind, lapply(seq_along(wave_cols), function(j) {
    cn <- wave_cols[j]
    if (!cn %in% names(df)) return(NULL)
    data.frame(id = as.character(df[[id_col]]), wave = paste0("Wave ", j),
               value = suppressWarnings(as.numeric(df[[cn]])),
               ord = j, stringsAsFactors = FALSE)
  }))
  rows <- rows[!is.na(rows$value), , drop = FALSE]
  if (!nrow(rows)) return(NULL)
  if (!requireNamespace("ggridges", quietly = TRUE)) return(NULL)
  rows$wave <- factor(rows$wave, levels = paste0("Wave ", sort(unique(rows$ord))))
  ggplot2::ggplot(rows, ggplot2::aes(x = value, y = wave,
                                     fill = ggplot2::after_stat(x))) +
    ggridges::geom_density_ridges_gradient(scale = 0.9, rel_min_height = 0.01,
                                           color = NA, alpha = 0.85) +
    ggplot2::scale_fill_viridis_c(name = NULL, option = "mako") +
    ggplot2::labs(title = lab, x = NULL, y = NULL) +
    tj_theme(fam) +
    ggplot2::theme(legend.position = "none",
                   axis.text.y = ggplot2::element_text(size = 8))
}

## ── 面板：选型曲线 AIC/BIC（+ entropy 右轴）vs K ────────────────────────────
tj_panel_select <- function(tab, k_opt = NULL, fam = "serif", lab = NULL,
                            show_entropy = TRUE) {
  if (is.null(tab) || !nrow(tab)) return(NULL)
  d <- data.frame(K = as.integer(tab$K), AIC = as.numeric(tab$AIC),
                  BIC = as.numeric(tab$BIC), ENT = as.numeric(tab$entropy))
  d <- d[is.finite(d$AIC) & is.finite(d$BIC), ]
  long <- rbind(
    data.frame(K = d$K, metric = "BIC", value = d$BIC),
    data.frame(K = d$K, metric = "AIC", value = d$AIC))
  gg <- ggplot2::ggplot(long, ggplot2::aes(x = K, y = value, color = metric,
                                           shape = metric, group = metric)) +
    ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 2.2)
  if (!is.null(k_opt) && k_opt %in% d$K) {
    gg <- gg + ggplot2::geom_vline(xintercept = k_opt, linetype = 2,
                                   color = "grey45", linewidth = 0.5)
  }
  gg <- gg +
    ggplot2::scale_x_continuous(breaks = d$K, name = "Number of trajectory groups (K)") +
    ggplot2::scale_color_manual(values = c(BIC = "#2C5F8A", AIC = "#C0392B"), name = NULL) +
    ggplot2::labs(title = lab, y = "Value") +
    tj_theme(fam) +
    ggplot2::theme(legend.position = c(0.2, 0.85), legend.background = ggplot2::element_blank())
  if (show_entropy && any(is.finite(d$ENT))) {
    ent <- ggplot2::ggplot(d, ggplot2::aes(x = K, y = ENT)) +
      ggplot2::geom_line(color = "#4E7A3A", linetype = 2, linewidth = 0.7) +
      ggplot2::geom_point(color = "#4E7A3A", size = 2) +
      ggplot2::ylim(0, 1) +
      ggplot2::labs(title = NULL, x = "K", y = "Entropy") +
      tj_theme(fam)
    attr(gg, "entropy_panel") <- ent
  }
  gg
}

## ── 面板：双指标原始尺度类别均值轨迹（每指标一 y 轴，同面板）────────────────
tj_panel_joint_traj <- function(fitobj, df, inds, id_col = "id", prefix = "grp_",
                                sys = NULL, fam = "serif", lab = NULL) {
  gv <- paste0(prefix, sys)
  if (is.null(df[[gv]])) return(NULL)
  lv <- unique(as.character(df[[gv]]))
  lv <- lv[order(as.integer(sub("^T", "", lv)))]
  cls_lab <- setNames(as.integer(sub("^T", "", lv)), lv)
  waves <- sort(unique(fitobj$long$t))
  rows <- list(); zrows <- list()
  for (ind in inds) {
    for (cl in names(cls_lab)) {
      ids <- as.character(df[[id_col]][!is.na(df[[gv]]) & df[[gv]] == cl])
      for (w in waves) {
        cn <- paste0(ind, "_", w)
        if (!cn %in% names(df)) next
        v <- suppressWarnings(as.numeric(df[[cn]]))[match(ids, df[[id_col]])]
        v <- v[!is.na(v)]
        if (!length(v)) next
        se <- if (length(v) > 1) stats::sd(v) / sqrt(length(v)) else 0
        rows[[length(rows) + 1L]] <- data.frame(
          ind = ind, wave = w, class = cl, mean = mean(v), se = se,
          stringsAsFactors = FALSE)
      }
    }
    # z 尺度（跨指标可比）仅备查
    d1 <- fitobj$long[fitobj$long$ind == ind, , drop = FALSE]
    if (nrow(d1)) {
      cm <- fitobj$fit$class_map
      d1$class_int <- as.integer(cm[match(d1$id, names(cm))])
      agg <- stats::aggregate(list(z = d1$z), list(wave = d1$t, class = d1$class_int), mean)
      zrows[[length(zrows) + 1L]] <- agg
    }
  }
  dd <- do.call(rbind, rows)
  if (is.null(dd) || !nrow(dd)) return(NULL)
  dd$class <- factor(dd$class, levels = names(cls_lab))
  # 每指标面板内自动量纲归一（双指标尺度不同：PLT~200 vs MPV~10），轴标各自真实均值
  dd$.scale_fac <- ave(dd$mean, dd$ind, FUN = function(x) max(x, na.rm = TRUE) * 1.22 + 1e-9)
  dd$ym <- dd$mean / dd$.scale_fac
  dd$ylo <- (dd$mean - 1.96 * dd$se) / dd$.scale_fac
  dd$yhi <- (dd$mean + 1.96 * dd$se) / dd$.scale_fac
  ggplot2::ggplot(dd, ggplot2::aes(x = wave, y = ym, color = class, group = interaction(ind, class))) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = ylo, ymax = yhi), fill = "grey70",
                         alpha = 0.25, color = NA, show.legend = FALSE) +
    ggplot2::geom_line(linewidth = 0.9) + ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~ind, scales = "free_y", ncol = length(inds)) +
    ggplot2::scale_x_continuous(breaks = waves, name = "Examination wave") +
    ggplot2::scale_y_continuous(name = NULL, breaks = NULL, labels = NULL) +
    ggplot2::scale_color_brewer(palette = "Dark2", name = "") +
    ggplot2::labs(title = lab, subtitle = NULL) +
    tj_theme(fam) +
    ggplot2::theme(legend.position = "top")
}

## ── 面板：累积发病率 1-S(t) + Number at risk ───────────────────────────────
tj_panel_cuminc <- function(df, gv, ev, tm, out, fam = "serif", lab = NULL,
                            time_unit_lab = "Follow-up (months)", breaks = NULL) {
  suppressMessages(requireNamespace("survival", quietly = TRUE))
  d <- df[!is.na(df[[gv]]), , drop = FALSE]
  d$.ev <- as.integer(ev[match(rownames(d), rownames(df))])
  d$.tm <- as.numeric(tm[match(rownames(d), rownames(df))])
  d <- d[!is.na(d$.tm) & d$.tm > 0 & !is.na(d$.ev), , drop = FALSE]
  d[[gv]] <- factor(d[[gv]])
  if (nlevels(d[[gv]]) < 2) return(NULL)
  km_fml <- stats::as.formula(paste0("survival::Surv(.tm, .ev) ~ ", gv))
  sfit <- eval(bquote(survival::survfit(.(km_fml), data = d)))
  lr <- survival::survdiff(km_fml, data = d)
  pval <- stats::pchisq(lr$chisq, df = length(lr$n) - 1L, lower.tail = FALSE)
  # strata 标签取 names()（as.character(strata) 在 integer 向量上是计数而非标签）
  snames <- names(sfit$strata)
  if (is.null(snames)) snames <- as.character(sfit$strata)
  g_lab <- unique(sub("^[^=]*=", "", snames))
  g_lab <- g_lab[order(as.integer(sub("^T", "", g_lab)))]
  ord <- match(g_lab, sub("^[^=]*=", "", snames))
  curve <- data.frame(
    t = as.numeric(sfit$time), ci = 1 - as.numeric(sfit$surv),
    lo = 1 - as.numeric(sfit$upper), hi = 1 - as.numeric(sfit$lower),
    class = rep(sub("^[^=]*=", "", snames), as.integer(sfit$strata)))
  curve <- curve[curve$class %in% g_lab, ]
  # t=0 基线行 log-log CI 为 NA → ribbon 删行警告；NA 处令 CI 塌缩到点值
  bad <- is.na(curve$lo) | is.na(curve$hi)
  curve$lo[bad] <- curve$ci[bad]
  curve$hi[bad] <- curve$ci[bad]
  curve$class <- factor(curve$class, levels = g_lab)
  cols <- scales::hue_pal()(length(g_lab))
  if (is.null(breaks)) breaks <- pretty(range(c(0, d$.tm)), n = 5)
  breaks <- breaks[breaks >= 0 & breaks <= max(d$.tm) * 1.02]
  nar <- list()
  for (i in seq_along(breaks)) {
    tt <- breaks[i]
    # 直接从数据算 risk set（= t 时点仍随访人数；多分层 summary 对象结构不稳）
    n_at <- stats::setNames(
      vapply(g_lab, function(gl)
        sum(d$.tm[as.character(d[[gv]]) == gl] >= tt), numeric(1)),
      g_lab)
    nar[[i]] <- data.frame(t = tt, class = g_lab,
                           n = as.integer(n_at[g_lab]),
                           row = i, stringsAsFactors = FALSE)
  }
  ntab <- do.call(rbind, nar)
  ntab$class <- factor(ntab$class, levels = g_lab)
  xmax <- max(d$.tm)
  lab_p <- if (is.finite(pval) && pval < 0.001) "< 0.001" else sprintf("= %.3f", pval)
  gg <- ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = curve,
                         ggplot2::aes(x = t, ymin = lo, ymax = hi, group = class, fill = class),
                         alpha = 0.16, color = NA, show.legend = FALSE) +
    ggplot2::geom_step(data = curve,
                       ggplot2::aes(x = t, y = ci, color = class, group = class),
                       direction = "vh", linewidth = 0.9) +
    ggplot2::scale_color_manual(values = cols, name = "", breaks = g_lab) +
    ggplot2::scale_fill_manual(values = cols, guide = "none") +
    ggplot2::coord_cartesian(xlim = c(0, xmax), ylim = c(0, min(1, max(curve$ci, na.rm = TRUE) * 1.15))) +
    ggplot2::scale_x_continuous(breaks = breaks, name = time_unit_lab) +
    ggplot2::labs(title = lab,
                  subtitle = sprintf("Log-rank P%s", lab_p),
                  y = "Cumulative incidence") +
    tj_theme(fam) +
    ggplot2::theme(legend.position = "top")
  # 风险表（与曲线同 x 轴；行名 T1..TK）
  tbl <- ggplot2::ggplot(ntab, ggplot2::aes(x = t, y = factor(class), label = n)) +
    ggplot2::geom_text(size = 2.6, family = fam) +
    ggplot2::scale_x_continuous(breaks = breaks, limits = c(0, xmax), name = NULL,
                                labels = NULL) +
    ggplot2::scale_y_discrete(name = "", breaks = g_lab, labels = g_lab) +
    ggplot2::theme_minimal(base_family = fam) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   plot.margin = ggplot2::margin(0, 6, 2, 2))
  # 标题行 "Number at risk"
  hdr <- ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 1, label = "Number at risk",
                      hjust = 0, size = 3, family = fam, fontface = "bold") +
    ggplot2::xlim(0, xmax) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void(base_family = fam) +
    ggplot2::theme(plot.margin = ggplot2::margin(0, 6, 0, 2))
  if (requireNamespace("patchwork", quietly = TRUE)) {
    comb <- gg + tbl / hdr + patchwork::plot_layout(heights = c(4, 0.55, 0.12))
    return(comb)
  }
  gg
}

## ── 表：协变量缺失率（ST2 对标）────────────────────────────────────────────
tj_lit_missing_table <- function(df, vars, labels = NULL) {
  vars <- intersect(as.character(vars), names(df))
  out <- data.frame(
    Variable = vapply(vars, function(v) {
      if (!is.null(labels) && v %in% names(labels)) as.character(labels[[v]])
      else if (exists("pipeline_display_label", mode = "function"))
        tryCatch(pipeline_display_label(v), error = function(e) gsub("[_.]", " ", v))
      else gsub("[_.]", " ", v)
    }, character(1)),
    check.names = FALSE)
  n_total <- nrow(df)
  miss <- vapply(vars, function(v) sum(is.na(df[[v]])), integer(1))
  if (exists("pub_format_int", mode = "function")) {
    out$Total <- pub_format_int(n_total)
    out$Missing <- pub_format_int(miss)
  } else {
    out$Total <- format(n_total, big.mark = ",", trim = TRUE)
    out$Missing <- format(miss, big.mark = ",", trim = TRUE)
  }
  out$`Missing rate, %` <- vapply(miss / max(1L, n_total) * 100,
                                  function(x) sprintf("%.1f", x), character(1))
  out
}

## ── 表：各指标逐波描述统计（ST3 对标）──────────────────────────────────────
tj_lit_wave_desc_table <- function(df, inds, waves, id_col = "id") {
  rows <- list()
  for (ind in inds) for (w in waves) {
    cn <- paste0(ind, "_", w)
    if (!cn %in% names(df)) next
    x <- suppressWarnings(as.numeric(df[[cn]]))
    if (all(is.na(x))) next
    q <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      Variable = ind, Wave = paste0("Wave ", w),
      N = sum(!is.na(x)), Mean = mean(x, na.rm = TRUE), SD = stats::sd(x, na.rm = TRUE),
      Median = q[2], Q1 = q[1], Q3 = q[3],
      Min = min(x, na.rm = TRUE), Max = max(x, na.rm = TRUE),
      stringsAsFactors = FALSE, check.names = FALSE)
  }
  d <- do.call(rbind, rows)
  if (is.null(d) || !nrow(d)) return(NULL)
  d$N <- if (exists("pub_format_int", mode = "function")) pub_format_int(d$N) else
    format(d$N, big.mark = ",", trim = TRUE)
  fmt <- function(v) vapply(v, function(k) if (k == round(k) && abs(k) >= 100)
    format(round(k), scientific = FALSE, trim = TRUE) else
    formatC(k, format = "f", digits = 2, drop0trailing = TRUE), character(1))
  d[, c("Mean", "SD", "Median", "Q1", "Q3", "Min", "Max")] <-
    lapply(d[, c("Mean", "SD", "Median", "Q1", "Q3", "Min", "Max")], fmt)
  d
}

## ── 表：全体系选型标准合并（ST4 对标）──────────────────────────────────────
tj_lit_merge_ic <- function(ic_map, k_opt_map = NULL) {
  rows <- list()
  for (sys in names(ic_map)) {
    tab <- ic_map[[sys]]
    if (is.null(tab) || !nrow(tab)) next
    for (ri in seq_len(nrow(tab))) {
      rows[[length(rows) + 1L]] <- data.frame(
        System = sys, K = tab$K[ri], AIC = tab$AIC[ri], BIC = tab$BIC[ri],
        Entropy = tab$entropy[ri],
        MinAvePP = tab$min_avepp[ri], MinOCC = tab$min_occ[ri],
        MinClassProp = tab$min_prop[ri],
        Selected = if (!is.null(k_opt_map) && !is.na(k_opt_map[[sys]]) &&
                       as.integer(tab$K[ri]) == as.integer(k_opt_map[[sys]])) "Yes" else "No",
        stringsAsFactors = FALSE, check.names = FALSE)
    }
  }
  d <- do.call(rbind, rows)
  if (is.null(d) || !nrow(d)) return(NULL)
  d$System <- if (exists("pipeline_display_label", mode = "function"))
    vapply(d$System, function(s) tryCatch(pipeline_display_label(s),
      error = function(e) gsub("_", " ", s)), character(1)) else gsub("_", " ", d$System)
  d$MinClassProp <- sprintf("%.1f%%", 100 * as.numeric(d$MinClassProp))
  d$MinOCC <- vapply(as.numeric(d$MinOCC), function(x)
    if (!is.finite(x)) "NA" else sprintf("%.1f", x), character(1))
  for (cc in c("AIC", "BIC")) d[[cc]] <- sprintf("%.1f", as.numeric(d[[cc]]))
  for (cc in c("Entropy", "MinAvePP"))
    d[[cc]] <- vapply(as.numeric(d[[cc]]), function(x)
      if (!is.finite(x)) "NA" else sprintf("%.3f", x), character(1))
  d
}

## ── 表：判别力比较（ST8 对标）— C-index / NRI / IDI vs base model ──────────
tj_lit_discrim_table <- function(df, systems, prefix, base_covs, ev, tm,
                                 top_n = NULL, time_lab = "gestational weeks") {
  requireNamespace("survival", quietly = TRUE)
  d <- df
  d$.ev <- as.integer(ev[match(rownames(d), rownames(df))])
  d$.tm <- as.numeric(tm[match(rownames(d), rownames(df))])
  d <- d[!is.na(d$.tm) & d$.tm > 0 & !is.na(d$.ev), , drop = FALSE]
  bc <- intersect(as.character(base_covs), names(d))
  base_f <- stats::as.formula(paste0(
    "survival::Surv(.tm, .ev) ~ ", paste(bc, collapse = " + ")))
  bfit <- tryCatch(survival::coxph(base_f, data = d, x = TRUE), error = function(e) NULL)
  if (is.null(bfit)) return(NULL)
  b_lp <- as.numeric(stats::predict(bfit, type = "lp"))
  b_cidx <- tryCatch(survival::concordance(
    survival::Surv(d$.tm, d$.ev) ~ b_lp)$concordance, error = function(e) NA_real_)
  n_boot <- if (nrow(d) >= 30) 200L else 0L
  sys_in <- as.character(systems)
  sys_in <- sys_in[vapply(sys_in, function(s) paste0(prefix, s) %in% names(df), logical(1))]
  if (!is.null(top_n) && top_n < length(sys_in)) sys_in <- sys_in[seq_len(top_n)]
  out <- data.frame(System = "Base model", Metric = "C-statistic",
                    Value = if (is.finite(b_cidx)) sprintf("%.3f", b_cidx) else "NA",
                    `C-index difference vs base` = "Reference",
                    P = "-", check.names = FALSE, stringsAsFactors = FALSE)
  lp_map <- list()
  for (sys in sys_in) {
    gv <- paste0(prefix, sys)
    if (!gv %in% names(d)) next
    x <- d[[gv]]
    if (is.character(x)) x <- factor(x)
    else x <- as.integer(x)
    d$.cls <- x
    f <- stats::as.formula(paste0(
      "survival::Surv(.tm, .ev) ~ .cls + ", paste(bc, collapse = " + ")))
    fit <- tryCatch(survival::coxph(f, data = d, x = TRUE), error = function(e) NULL)
    if (is.null(fit)) next
    lp <- as.numeric(stats::predict(fit, type = "lp"))
    cc <- tryCatch(survival::concordance(survival::Surv(d$.tm, d$.ev) ~ lp),
                   error = function(e) NULL)
    if (is.null(cc)) next
    lp_map[[sys]] <- lp
    dc <- cc$concordance - b_cidx
    out <- rbind(out,
      data.frame(System = sys, Metric = "C-statistic",
                 Value = sprintf("%.3f", cc$concordance),
                 `C-index difference vs base` = sprintf("%.3f", dc),
                 P = "-", check.names = FALSE, stringsAsFactors = FALSE))
    # NRI / IDI（2 类以上时按参照 vs 其余折叠；事件稀少时仅作方向参考）
    nl <- length(stats::na.omit(unique(as.character(d$.cls))))
    if (nl >= 2) {
      lvl <- sort(unique(as.character(stats::na.omit(d$.cls))))
      ref <- lvl[1]
      pb <- plogis(b_lp); pf <- plogis(lp)
      ev1 <- d$.ev == 1
      if (sum(ev1) >= 5 && sum(!ev1) >= 5) {
        up_e <- sum(pf[ev1] > pb[ev1] + 0.01); dn_e <- sum(pf[ev1] < pb[ev1] - 0.01)
        up_n <- sum(pf[!ev1] > pb[!ev1] + 0.01); dn_n <- sum(pf[!ev1] < pb[!ev1] - 0.01)
        nri <- (up_e - dn_e) / max(1L, sum(ev1)) + (dn_n - up_n) / max(1L, sum(!ev1))
        idi <- mean((pf[ev1] - pb[ev1])) - mean((pf[!ev1] - pb[!ev1]))
        out <- rbind(out,
          data.frame(System = sys, Metric = "NRI (category-free)",
                     Value = sprintf("%.3f", nri),
                     `C-index difference vs base` = "-", P = "-",
                     check.names = FALSE, stringsAsFactors = FALSE),
          data.frame(System = sys, Metric = "IDI",
                     Value = sprintf("%.4f", idi),
                     `C-index difference vs base` = "-", P = "-",
                     check.names = FALSE, stringsAsFactors = FALSE))
      }
    }
  }
  # 配对 bootstrap：同一重抽样内 ΔC（system − base）→ 经验双侧 P
  if (n_boot > 0L && length(lp_map)) {
    set.seed(42L)
    tm_v <- d$.tm; ev_v <- d$.ev
    boot <- lapply(lp_map, function(lp0) numeric(n_boot))
    for (i in seq_len(n_boot)) {
      k <- sample.int(nrow(d), replace = TRUE)
      sb <- tryCatch(survival::concordance(
        survival::Surv(tm_v[k], ev_v[k]) ~ b_lp[k])$concordance,
        error = function(e) NA_real_)
      for (sys in names(lp_map)) {
        ss <- tryCatch(survival::concordance(
          survival::Surv(tm_v[k], ev_v[k]) ~ lp_map[[sys]][k])$concordance,
          error = function(e) NA_real_)
        boot[[sys]][i] <- ss - sb
      }
    }
    for (sys in names(lp_map)) {
      bd <- boot[[sys]][is.finite(boot[[sys]])]
      if (length(bd) < 50) next
      pv <- 2 * min(mean(bd >= 0), mean(bd <= 0))
      ri <- which(out$System == sys & out$Metric == "C-statistic")
      if (length(ri))
        out$P[ri[1]] <- if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
    }
    attr(out, "n_boot") <- n_boot
  }
  out <- out[, setdiff(names(out), "delta"), drop = FALSE]
  out$System <- if (exists("pipeline_display_label", mode = "function"))
    vapply(out$System, function(s) tryCatch(pipeline_display_label(s),
      error = function(e) gsub("_", " ", s)), character(1)) else gsub("_", " ", out$System)
  attr(out, "n_analytic") <- nrow(d)
  attr(out, "base_covs") <- paste(gsub("[_.]", " ", bc), collapse = " + ")
  attr(out, "time_lab") <- time_lab
  out
}
