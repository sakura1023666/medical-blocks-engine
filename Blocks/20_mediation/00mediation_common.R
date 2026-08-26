###############################################################################
#  mediation 共用：路径三角图 + 显著性判定（incidence / NHANES weighted 复用）
###############################################################################

.mediation_diag_pretty_label <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("_", " ", x, fixed = TRUE)
  trimws(x)
}

.mediation_outcome_diag_label <- function(cfg) {
  proj <- cfg$project %||% list()
  .mediation_diag_pretty_label(proj$disease %||% proj$analysis_group %||% "Outcome")
}

.mediation_format_prop_med_table <- function(prop_med_num) {
  if (is.null(prop_med_num) || length(prop_med_num) == 0L ||
      is.na(prop_med_num) || !is.finite(prop_med_num)) {
    return(NA_character_)
  }
  paste0(formatC(prop_med_num, format = "f", digits = 2), "%")
}

.mi02_palettes <- list(
  sakura    = list(exposure = "#F2A7B8", mediator = "#C47EBE", outcome = "#F0875A"),
  matcha    = list(exposure = "#85C8AC", mediator = "#6AAAC8", outcome = "#E89A7A"),
  blueberry = list(exposure = "#95B8E0", mediator = "#7A80C8", outcome = "#E08888"),
  mango     = list(exposure = "#F0C07A", mediator = "#D47A8A", outcome = "#7AB8A8"),
  lavender  = list(exposure = "#B8A0D8", mediator = "#D47890", outcome = "#78B8A8"),
  rosepeach = list(exposure = "#F0A898", mediator = "#B880C8", outcome = "#88B8D0")
)

.mi02_draw_mediation_path_diagram <- function(
    exposure_label, mediator_label, outcome_label,
    coef_a, p_a, coef_b, p_b, effect_total, p_total,
    prop_pct, prop_lo_pct, prop_hi_pct, colors,
    ci_a_lo = NA_real_, ci_a_hi = NA_real_,
    ci_b_lo = NA_real_, ci_b_hi = NA_real_,
    ci_tot_lo = NA_real_, ci_tot_hi = NA_real_,
    font_family = "Times New Roman", output_path = NULL,
    width = NULL, height = NULL) {

  suppressPackageStartupMessages(library(ggplot2))

  if (exists("resolve_plot_font_family", mode = "function")) {
    font_family <- resolve_plot_font_family(font_family)
  }

  exposure_label <- .mediation_diag_pretty_label(exposure_label)
  mediator_label <- .mediation_diag_pretty_label(mediator_label)
  outcome_label  <- .mediation_diag_pretty_label(outcome_label)

  .fp <- function(p) {
    if (is.null(p) || length(p) == 0L || is.na(p) || !is.finite(p)) return("p=NA")
    if (p < 0.001) "p<0.001" else paste0("p=", formatC(round(p, 3), format = "f", digits = 3))
  }
  .fc <- function(x, d = 3) {
    if (is.null(x) || length(x) == 0L || is.na(x) || !is.finite(x)) return("NA")
    formatC(round(x, d), format = "f", digits = d)
  }
  .lines_equal_width <- function(lines) {
    nc <- nchar(lines, type = "chars", allowNA = TRUE)
    nc[is.na(nc)] <- 0L
    w <- max(nc, na.rm = TRUE)
    paste(vapply(seq_along(lines), function(i) {
      pad <- as.integer(w - nc[i])
      if (pad <= 0L) return(lines[i])
      L <- pad %/% 2L
      R <- pad - L
      paste0(strrep(" ", L), lines[i], strrep(" ", R))
    }, character(1L), USE.NAMES = FALSE), collapse = "\n")
  }
  .path_lbl_p_below_ci <- function(est, p, lo, hi, d_est = 3L) {
    L1 <- paste0(.fc(est, d_est), " (", .fp(p), ")")
    lines <- if (is.finite(lo) && is.finite(hi)) {
      c(L1, paste0("(", .fc(lo, d_est), ", ", .fc(hi, d_est), ")"))
    } else {
      L1
    }
    if (length(lines) == 1L) lines else .lines_equal_width(lines)
  }

  lbl_a <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, 3L)
  lbl_b <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, 3L)
  lbl_d <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, 3L)
  pm_c <- if (!is.na(prop_pct) && is.finite(prop_pct)) .fc(prop_pct, 2) else "?"
  lbl_pm <- paste0("Proportion mediated\n", pm_c, "%")

  .pad_equal_width <- function(s1, s2, s3) {
    labs <- c(as.character(s1)[1L], as.character(s2)[1L], as.character(s3)[1L])
    nw <- max(nchar(labs, type = "chars", allowNA = TRUE), na.rm = TRUE)
    vapply(labs, function(s) {
      n <- nchar(s, type = "chars", allowNA = TRUE)
      if (is.na(n)) n <- 0L
      pad <- as.integer(nw - n)
      if (pad <= 0L) return(s)
      L <- pad %/% 2L
      R <- pad - L
      paste0(strrep(" ", L), s, strrep(" ", R))
    }, character(1), USE.NAMES = FALSE)
  }
  lab3 <- .pad_equal_width(exposure_label, mediator_label, outcome_label)

  tri_cx <- 5.0; tri_by <- 1.48; base_hw <- 2.45; apex_h <- 2.38
  ex <- tri_cx - base_hw; ox <- tri_cx + base_hw
  ey <- tri_by; oy <- tri_by; mx <- tri_cx; my <- tri_by + apex_h
  bw_half <- 1.42; bh_half <- 0.56

  .box_edge <- function(cx, cy, tx, ty) {
    dx <- tx - cx; dy <- ty - cy
    if (abs(dx) < 1e-9 && abs(dy) < 1e-9) return(c(cx, cy))
    len <- sqrt(dx^2 + dy^2); ux <- dx / len; uy <- dy / len
    t <- min(
      if (abs(ux) > 1e-9) bw_half / abs(ux) else Inf,
      if (abs(uy) > 1e-9) bh_half / abs(uy) else Inf
    )
    c(cx + t * ux, cy + t * uy)
  }
  .shorten_to <- function(xs, ys, xe, ye, eps) {
    dx <- xe - xs; dy <- ye - ys
    len <- sqrt(dx^2 + dy^2)
    if (len < 1e-9) return(c(xe, ye))
    ux <- dx / len; uy <- dy / len
    c(xe - eps * ux, ye - eps * uy)
  }
  tip_eps <- 0.028
  as1 <- .box_edge(ex, ey, mx, my); be1 <- .box_edge(mx, my, ex, ey)
  ae1 <- .shorten_to(as1[1], as1[2], be1[1], be1[2], tip_eps)
  as2 <- .box_edge(mx, my, ox, oy); be2 <- .box_edge(ox, oy, mx, my)
  ae2 <- .shorten_to(as2[1], as2[2], be2[1], be2[2], tip_eps)
  as3 <- .box_edge(ex, ey, ox, oy); be3 <- .box_edge(ox, oy, ex, ey)
  ae3 <- .shorten_to(as3[1], as3[2], be3[1], be3[2], tip_eps)
  am1 <- (as1 + ae1) / 2; am2 <- (as2 + ae2) / 2; am3 <- (as3 + ae3) / 2

  lft_off <- function(dx, dy, d) {
    len <- sqrt(dx^2 + dy^2)
    c(-dy / len * d, dx / len * d)
  }
  off_a <- lft_off(mx - ex, my - ey, 0.58)
  off_b <- lft_off(ox - mx, oy - my, 0.58)
  off_d_base <- lft_off(ox - ex, oy - ey, -0.42)
  cent_x <- (ex + mx + ox) / 3; cent_y <- (ey + my + oy) / 3 - 0.28

  # 自适应：坐标贴内容，避免半页白边
  pad_x <- 0.42; pad_y <- 0.38
  bw_lim <- bw_half * 0.78; bh_lim <- bh_half * 0.85
  xs_all <- c(
    ex - bw_lim, ex + bw_lim, mx - bw_lim, mx + bw_lim,
    ox - bw_lim, ox + bw_lim,
    as1[1], ae1[1], as2[1], ae2[1], as3[1], ae3[1],
    am1[1] + off_a[1], am2[1] + off_b[1], am3[1] + off_d_base[1], cent_x
  )
  ys_all <- c(
    ey - bh_lim, ey + bh_lim, my - bh_lim, my + bh_lim,
    oy - bh_lim, oy + bh_lim,
    as1[2], ae1[2], as2[2], ae2[2], as3[2], ae3[2],
    am1[2] + off_a[2], am2[2] + off_b[2], am3[2] + off_d_base[2], cent_y
  )
  x_lim <- c(min(xs_all, na.rm = TRUE) - pad_x, max(xs_all, na.rm = TRUE) + pad_x)
  y_lim <- c(min(ys_all, na.rm = TRUE) - pad_y, max(ys_all, na.rm = TRUE) + pad_y)
  x_rng <- max(diff(x_lim), 1e-6)
  y_rng <- max(diff(y_lim), 1e-6)
  ar <- x_rng / y_rng
  if (is.null(width) || !is.finite(as.numeric(width)[1L])) {
    if (ar >= 1) {
      width  <- 6.4
      height <- max(3.2, min(5.0, width / ar))
    } else {
      height <- 5.0
      width  <- max(4.2, min(6.8, height * ar))
    }
  } else {
    width <- as.numeric(width)[1L]
    if (is.null(height) || !is.finite(as.numeric(height)[1L])) {
      height <- max(3.2, min(5.5, width / ar))
    } else {
      height <- as.numeric(height)[1L]
    }
  }
  vangle <- function(dx, dy) {
    atan2(dy * (height / y_rng), dx * (width / x_rng)) * 180 / pi
  }
  ang_a <- vangle(mx - ex, my - ey)
  ang_b <- vangle(ox - mx, oy - my)
  ang_d <- vangle(ox - ex, oy - ey)
  arw <- arrow(length = unit(0.24, "cm"), type = "closed")

  plt <- ggplot() +
    coord_cartesian(xlim = x_lim, ylim = y_lim, expand = FALSE, clip = "off") +
    theme_void(base_family = font_family) +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(2, 2, 2, 2, "mm")
    ) +
    annotate("text", x = am1[1] + off_a[1], y = am1[2] + off_a[2],
             label = lbl_a, angle = ang_a, hjust = 0.5, vjust = 0.5,
             size = 2.85, lineheight = 0.98, family = font_family,
             fontface = "bold", color = "gray30") +
    annotate("text", x = am2[1] + off_b[1], y = am2[2] + off_b[2],
             label = lbl_b, angle = ang_b, hjust = 0.5, vjust = 0.5,
             size = 2.85, lineheight = 0.98, family = font_family,
             fontface = "bold", color = "gray30") +
    annotate("text", x = am3[1] + off_d_base[1], y = am3[2] + off_d_base[2],
             label = lbl_d, angle = ang_d, hjust = 0.5, vjust = 0.5,
             size = 2.85, lineheight = 0.98, family = font_family,
             fontface = "bold", color = "gray30") +
    annotate("text", x = cent_x, y = cent_y, label = lbl_pm,
             hjust = 0.5, vjust = 0.5, size = 3.75, lineheight = 1.35,
             family = font_family, fontface = "bold", color = "gray25") +
    annotate("label", x = ex, y = ey, label = lab3[1L], fill = colors$exposure,
             colour = "white", family = font_family, fontface = "bold", size = 4.55,
             linewidth = 0, label.r = grid::unit(0.45, "lines"),
             label.padding = grid::unit(0.62, "lines")) +
    annotate("label", x = mx, y = my, label = lab3[2L], fill = colors$mediator,
             colour = "white", family = font_family, fontface = "bold", size = 4.55,
             linewidth = 0, label.r = grid::unit(0.45, "lines"),
             label.padding = grid::unit(0.62, "lines")) +
    annotate("label", x = ox, y = oy, label = lab3[3L], fill = colors$outcome,
             colour = "white", family = font_family, fontface = "bold", size = 4.55,
             linewidth = 0, label.r = grid::unit(0.45, "lines"),
             label.padding = grid::unit(0.62, "lines")) +
    annotate("segment", x = as1[1], y = as1[2], xend = ae1[1], yend = ae1[2],
             arrow = arw, linewidth = 0.95, color = "gray32") +
    annotate("segment", x = as2[1], y = as2[2], xend = ae2[1], yend = ae2[2],
             arrow = arw, linewidth = 0.95, color = "gray32") +
    annotate("segment", x = as3[1], y = as3[2], xend = ae3[1], yend = ae3[2],
             arrow = arw, linewidth = 0.95, color = "gray32")

  if (!is.null(output_path)) {
    tryCatch({
      pdf_dev <- tryCatch(grDevices::cairo_pdf, error = function(e) grDevices::pdf)
      ggplot2::ggsave(output_path, plt, device = pdf_dev, width = width, height = height, bg = "white")
      cli::cli_alert_success("中介路径图已保存: {.file {basename(output_path)}}")
    }, error = function(e) {
      cli::cli_alert_warning("中介路径图保存失败: {e$message}")
    })
  }
  invisible(plt)
}

#' 跳过导出时：清发表队列中的中介/关联表/路径图，并删除已落盘残留
#' （中介不达标时实验室关联表一并不要；与 skip_export_if_ns 同规则）
.mi02_mediation_export_name_pat <- function() {
  paste0(
    "(?i)(",
    "mediation analysis|",
    "path diagram|",
    "(the )?associations? (of|between) .+ laboratory indicators|",
    "weighted associations? (of|between) .+ laboratory|",
    "weighted mediation",
    ")"
  )
}

.mi02_dequeue_mediation_exports <- function() {
  pat <- .mi02_mediation_export_name_pat()
  n <- 0L
  if (exists(".table_queue_env", inherits = TRUE)) {
    q <- .table_queue_env$items %||% list()
    if (length(q)) {
      keep <- vapply(q, function(it) {
        fp <- as.character(it$filepath %||% it$path %||% "")[1L]
        !grepl(pat, basename(fp), perl = TRUE)
      }, logical(1L))
      n <- n + sum(!keep)
      .table_queue_env$items <- q[keep]
    }
  }
  if (exists(".figure_queue_env", inherits = TRUE)) {
    qf <- .figure_queue_env$items %||% list()
    if (length(qf)) {
      keep <- vapply(qf, function(it) {
        fp <- as.character(it$filepath %||% it$path %||% it$filename %||% "")[1L]
        !grepl(pat, basename(fp), perl = TRUE)
      }, logical(1L))
      n <- n + sum(!keep)
      .figure_queue_env$items <- qf[keep]
    }
  }
  invisible(n)
}

.mi02_unlink_mediation_exports <- function(ctx) {
  n_q <- .mi02_dequeue_mediation_exports()
  root <- as.character(ctx$root_output_dir %||% "")[1L]
  out_db <- as.character(ctx$output_dir %||% "")[1L]
  dirs <- unique(c(
    ctx$output_dir_tables,
    ctx$output_dir_figures,
    if (nzchar(out_db)) file.path(out_db, "Tables") else NULL,
    if (nzchar(out_db)) file.path(out_db, "Figures") else NULL,
    if (nzchar(root)) file.path(root, "Tables") else NULL,
    if (nzchar(root)) file.path(root, "Figures") else NULL
  ))
  dirs <- dirs[nzchar(as.character(dirs)) & dir.exists(dirs)]
  pat <- .mi02_mediation_export_name_pat()
  n_rm <- 0L
  for (d in dirs) {
    fs <- list.files(d, full.names = TRUE)
    if (!length(fs)) next
    hit <- grepl(pat, basename(fs), perl = TRUE)
    if (any(hit)) {
      unlink(fs[hit])
      n_rm <- n_rm + sum(hit)
    }
  }
  n_tot <- n_rm + n_q
  if (n_tot > 0L && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "已清除 {n_tot} 个中介/关联表（队列 {n_q} + 磁盘 {n_rm}；中介未达导出门槛）"
    )
  }
  invisible(n_tot)
}

#' 中介门控通过后导出「暴露–实验室关联」表（门控失败则永不落盘）
.mi02_export_lab_association_table <- function(ctx, rt, exposure, weighted = FALSE) {
  if (is.null(rt) || !is.data.frame(rt) || !nrow(rt)) return(invisible(FALSE))
  exposure <- as.character(exposure %||% "Index")[1L]
  cap <- if (isTRUE(weighted)) {
    paste0("Weighted associations of ", gsub("_", " ", exposure), " with laboratory indicators")
  } else {
    paste0("Associations of ", gsub("_", " ", exposure), " with laboratory indicators")
  }
  corr_pub <- pub_paths(ctx, ctx$output_dir_tables, "supp_table", cap, "xlsx")
  export_sci_table(
    rt, corr_pub$filepath, title = corr_pub$title,
    table_footnotes = "β values are per 1-SD of the laboratory variable."
  )
  invisible(TRUE)
}

.mi02_mediation_paths_significant <- function(one_row, alpha) {
  if (is.null(one_row) || nrow(one_row) != 1L) return(FALSE)
  pa <- suppressWarnings(as.numeric(one_row$.raw_p_a[1L]))
  pb <- suppressWarnings(as.numeric(one_row$.raw_p_b[1L]))
  pi <- if (".raw_p_indirect" %in% names(one_row)) {
    suppressWarnings(as.numeric(one_row$.raw_p_indirect[1L]))
  } else {
    NA_real_
  }
  is.finite(pa) && is.finite(pb) && is.finite(pi) && pa < alpha && pb < alpha && pi < alpha
}

#' Proportion mediated 显著：bootstrap P < alpha，或 bootstrap CI 不含 0
.mi02_mediation_proportion_significant <- function(one_row, alpha) {
  if (is.null(one_row) || nrow(one_row) != 1L) return(FALSE)
  if (".raw_p_proportion" %in% names(one_row)) {
    pp <- suppressWarnings(as.numeric(one_row$.raw_p_proportion[1L]))
    if (is.finite(pp)) return(pp < alpha)
  }
  lo <- suppressWarnings(as.numeric(one_row$.raw_prop_lo[1L]))
  hi <- suppressWarnings(as.numeric(one_row$.raw_prop_hi[1L]))
  if (is.finite(lo) && is.finite(hi)) {
    return(lo > 0 || hi < 0)
  }
  FALSE
}

#' Direct Effect (c') 显著
.mi02_mediation_direct_significant <- function(one_row, alpha) {
  if (is.null(one_row) || nrow(one_row) != 1L) return(FALSE)
  pd <- if (".raw_p_direct" %in% names(one_row)) {
    suppressWarnings(as.numeric(one_row$.raw_p_direct[1L]))
  } else {
    NA_real_
  }
  # 预后旧结果偶发未写 .raw_p_direct：从 DirectEffect_* 展示串末尾解析 P
  if (!is.finite(pd)) {
    de_cols <- grep("^(DirectEffect_|Direct Effect)", names(one_row), value = TRUE)
    if (length(de_cols)) {
      s <- as.character(one_row[[de_cols[1L]]][1L])
      m <- regmatches(s, regexpr("([0-9.]+|\\d+e-?\\d+)\\s*$", s, ignore.case = TRUE, perl = TRUE))
      if (length(m) && nzchar(m)) pd <- suppressWarnings(as.numeric(m))
    }
  }
  is.finite(pd) && pd < alpha
}

#' 与路径图一致：shared preferred → config best_mediator → Prop_Med 最大
.mi02_mediation_pick_best_row <- function(final_table, cfg, bl_cfg) {
  if (is.null(final_table) || !nrow(final_table)) return(NULL)
  best_med_cfg <- as.character(bl_cfg$best_mediator %||% "")[1L]
  pref_shared <- NA_character_
  if (isTRUE((cfg$dual_db %||% list())$enable) &&
      exists("dual_db_load_preferred_mediator", mode = "function")) {
    root_m <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
    pref_shared <- dual_db_load_preferred_mediator(root_m, cfg)
  }
  if (nzchar(as.character(pref_shared %||% "")[1L]) &&
      pref_shared %in% final_table$Mediator) {
    return(final_table[final_table$Mediator == pref_shared, , drop = FALSE][1L, , drop = FALSE])
  }
  if (nzchar(best_med_cfg) && best_med_cfg %in% final_table$Mediator) {
    return(final_table[final_table$Mediator == best_med_cfg, , drop = FALSE][1L, , drop = FALSE])
  }
  valid_rows <- final_table[!is.na(final_table$Prop_Med_num), , drop = FALSE]
  if (nrow(valid_rows)) {
    return(valid_rows[which.max(valid_rows$Prop_Med_num), , drop = FALSE])
  }
  final_table[1L, , drop = FALSE]
}

#' skip_export_if_ns=TRUE 时决定是否导出中介表/图
#' export_criterion: best_proportion（默认：最佳中介 Proportion + Direct 均显著）| any_indirect
.mi02_mediation_should_export <- function(final_table, cfg, bl_cfg) {
  if (!isTRUE(bl_cfg$skip_export_if_ns %||% TRUE)) return(TRUE)
  alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  criterion <- as.character(bl_cfg$export_criterion %||% "best_proportion")[1L]
  if (identical(criterion, "any_indirect")) {
    return(any(vapply(seq_len(nrow(final_table)), function(i) {
      .mi02_mediation_paths_significant(final_table[i, , drop = FALSE], alpha)
    }, logical(1L))))
  }
  best_row <- .mi02_mediation_pick_best_row(final_table, cfg, bl_cfg)
  if (is.null(best_row)) return(FALSE)
  # 默认：Proportion mediated 显著 且 Direct Effect 显著，缺一不出
  .mi02_mediation_proportion_significant(best_row, alpha) &&
    .mi02_mediation_direct_significant(best_row, alpha)
}

#' 跳过导出时的可读原因（供 cli 提示）
.mi02_mediation_skip_reason <- function(final_table, cfg, bl_cfg) {
  alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  best_row <- .mi02_mediation_pick_best_row(final_table, cfg, bl_cfg)
  med <- as.character(best_row$Mediator[1L] %||% "?")
  prop_ok <- .mi02_mediation_proportion_significant(best_row, alpha)
  dir_ok  <- .mi02_mediation_direct_significant(best_row, alpha)
  if (!prop_ok && !dir_ok) {
    sprintf("最佳中介 [%s] Proportion mediated 与 Direct Effect 均不显著（P>=%s）", med, alpha)
  } else if (!prop_ok) {
    sprintf("最佳中介 [%s] Proportion mediated 不显著（P>=%s）", med, alpha)
  } else if (!dir_ok) {
    sprintf("最佳中介 [%s] Direct Effect 不显著（P>=%s）", med, alpha)
  } else {
    sprintf("最佳中介 [%s] 未达导出门槛", med)
  }
}
