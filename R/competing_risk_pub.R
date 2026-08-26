###############################################################################
#  competing_risk_pub.R — Lai 风格 Figure 绘图工具（森林图 / RCS / CIF+风险表）
###############################################################################

.competing_pub_db <- function(cfg) {
  db <- as.character((cfg$project %||% list())$database %||% "MIMIC")[1L]
  if (!nzchar(db)) "MIMIC" else db
}

.competing_pub_write_xlsx <- function(df, path, title = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (is.null(title) || !nzchar(title)) {
    title <- sub("\\.xlsx$", "", basename(path))
  }
  if (exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch({
      sci_xlsx_single_header_booktabs(path, title = title, df_body = as.data.frame(df, stringsAsFactors = FALSE))
      return(invisible(path))
    }, error = function(e) NULL)
  }
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "Table", gridLines = FALSE)
    openxlsx::writeData(wb, "Table", title, startRow = 1, colNames = FALSE)
    openxlsx::mergeCells(wb, "Table", rows = 1, cols = 1:max(1L, ncol(df)))
    openxlsx::writeData(wb, "Table", df, startRow = 3, colNames = TRUE)
    hs <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11, textDecoration = "bold",
                                border = "TopBottom", borderStyle = c("medium", "thin"),
                                halign = "center", valign = "center")
    bs <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11, halign = "center")
    openxlsx::addStyle(wb, "Table", hs, rows = 3, cols = 1:ncol(df), gridExpand = TRUE)
    if (nrow(df) > 0) {
      openxlsx::addStyle(wb, "Table", bs, rows = 4:(3 + nrow(df)), cols = 1:ncol(df), gridExpand = TRUE)
    }
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  } else {
    utils::write.csv(df, sub("\\.xlsx$", ".csv", path), row.names = FALSE, fileEncoding = "UTF-8")
  }
  invisible(path)
}

.competing_cov_footnote <- function(ctx, dual_section = TRUE) {
  covs <- ctx$results$competing_model_covs
  fn <- if (!is.null(covs$footnote) && nzchar(as.character(covs$footnote)[1L])) {
    as.character(covs$footnote)[1L]
  } else {
    "Model 1/4: unadjusted; Model 2/5: demographics; Model 3/6: demographics + selected covariates"
  }
  # 剥调试尾注（历史结果可能仍含）
  fn <- sub("\\s*\\[model3_sig_search:[^\\]]*\\]", "", fn, perl = TRUE)
  fn <- trimws(fn)
  # Fig2/7 仅 Model 1–3：勿写 Model 1/4 模板
  if (!isTRUE(dual_section)) {
    fn <- gsub("Model 1/4", "Model 1", fn, fixed = TRUE)
    fn <- gsub("Model 2/5", "Model 2", fn, fixed = TRUE)
    fn <- gsub("Model 3/6", "Model 3", fn, fixed = TRUE)
  }
  fn
}

#' Lai 风格多时点森林图；可选双段（Competing / Standard）与 Model1–6
.competing_pub_forest_lai <- function(tab, title, outfile, horizons = c(7, 14, 28),
                                      term_pat = "Q[2-4]|T[2-9]|Stable|Increasing",
                                      methods = NULL,
                                      footnote = NULL,
                                      dual_section = FALSE) {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  title <- gsub("_", " ", title, fixed = TRUE)
  pdf(outfile, width = 12.5, height = if (isTRUE(dual_section)) 10 else 8)
  on.exit(dev.off(), add = TRUE)
  if (is.null(tab) || !nrow(tab) || !"HR" %in% names(tab)) {
    plot.new(); title(main = paste0(title, "\n(no data)")); return(invisible(NULL))
  }
  d <- tab
  if (!"horizon" %in% names(d)) d$horizon <- 28L
  d$HR <- suppressWarnings(as.numeric(d$HR))
  d$lo <- suppressWarnings(as.numeric(d$HR_low %||% NA_real_))
  d$hi <- suppressWarnings(as.numeric(d$HR_high %||% NA_real_))
  d$p  <- suppressWarnings(as.numeric(d$p %||% NA_real_))
  # 剔除非有限 HR（cox 发散）
  ok <- is.finite(d$HR) & is.finite(d$lo) & is.finite(d$hi)
  d <- d[ok, , drop = FALSE]
  keep <- grepl(term_pat, d$term, ignore.case = TRUE)
  if (any(keep)) d <- d[keep, , drop = FALSE]
  if (!nrow(d)) { plot.new(); title(main = paste0(title, "\n(no finite exposure terms)")); return(invisible(NULL)) }

  d$level <- sub(".*?((Q[1-4])|(T[0-9]+)|(Decreasing|Stable|Increasing)).*", "\\1", d$term, ignore.case = TRUE)
  if (any(grepl("^Q", d$level))) {
    levels_order <- c("Q1", "Q2", "Q3", "Q4"); ref_lv <- "Q1"
  } else if (any(grepl("^T", d$level, ignore.case = TRUE))) {
    # 轨迹项只含非参考水平（T2..Tk），参考类 T1 不出现在模型项中；
    # 必须显式补出 T1 作为参考，否则会把 T2 误当参考跳过 → 图空白。
    nums <- suppressWarnings(as.integer(sub("^[Tt]", "", d$level)))
    nums <- nums[is.finite(nums)]
    kmax <- if (length(nums)) max(nums) else 2L
    levels_order <- paste0("T", seq_len(max(2L, kmax))); ref_lv <- "T1"
  } else {
    levels_order <- c("Decreasing", "Stable", "Increasing"); ref_lv <- "Decreasing"
  }
  horizons <- as.integer(horizons)

  if (isTRUE(dual_section) && "method" %in% names(d) && "model_id" %in% names(d)) {
    # Competing M1-3 + Standard M4-6
    sections <- list(
      list(title = "Competing risk Cox regression", ids = 1:3),
      list(title = "Cox proportional hazards regression", ids = 4:6)
    )
  } else if (isTRUE(dual_section) && "method" %in% names(d)) {
    sections <- list(
      list(title = "Fine-Gray competing risk regression", method = "competing", models = c("Model 1", "Model 2", "Model 3")),
      list(title = "Standard Cox regression", method = "standard", models = c("Model 4", "Model 5", "Model 6"))
    )
  } else {
    # 仅 Competing M1-3（Fig2/7）
    if ("model_id" %in% names(d)) d <- d[d$model_id %in% 1:3 | d$model %in% c("Model 1", "Model 2", "Model 3"), , drop = FALSE]
    sections <- list(list(title = NULL, ids = 1:3, models = c("Model 1", "Model 2", "Model 3")))
  }

  # 构建行
  row_df <- do.call(rbind, lapply(sections, function(sec) {
    rows <- list()
    if (!is.null(sec$title)) {
      rows[[length(rows) + 1L]] <- data.frame(
        section = sec$title, model = NA_character_, level = NA_character_,
        is_section = TRUE, is_header = FALSE, stringsAsFactors = FALSE
      )
    }
    mods <- if (!is.null(sec$ids) && "model_id" %in% names(d)) {
      paste("Model", sec$ids)
    } else {
      sec$models %||% c("Model 1", "Model 2", "Model 3")
    }
    for (m in mods) {
      rows[[length(rows) + 1L]] <- data.frame(
        section = sec$title %||% "", model = m, level = NA_character_,
        is_section = FALSE, is_header = TRUE, stringsAsFactors = FALSE
      )
      for (lv in levels_order) {
        rows[[length(rows) + 1L]] <- data.frame(
          section = sec$title %||% "", model = m, level = lv,
          is_section = FALSE, is_header = FALSE, stringsAsFactors = FALSE
        )
      }
    }
    do.call(rbind, rows)
  }))

  n_row <- nrow(row_df)
  y_at <- rev(seq_len(n_row))
  n_h <- length(horizons)
  widths <- c(2.0, rep(c(2.0, 1.55, 0.65), n_h))
  layout(matrix(seq_len(1L + 3L * n_h), nrow = 1L), widths = widths)
  op <- par(mar = c(4.2, 0.15, 3.2, 0.15), oma = c(2.8, 0, 0.5, 0))
  on.exit(par(op), add = TRUE)

  # 左标签
  plot(1, type = "n", xlim = c(0, 1), ylim = c(0.5, n_row + 0.5), axes = FALSE, xlab = "", ylab = "")
  for (i in seq_len(n_row)) {
    if (isTRUE(row_df$is_section[i])) {
      rect(0, y_at[i] - 0.5, 1, y_at[i] + 0.5, col = "#D9D9D9", border = NA)
      text(0.02, y_at[i], row_df$section[i], adj = 0, font = 2, cex = 0.78)
    } else if (isTRUE(row_df$is_header[i])) {
      rect(0, y_at[i] - 0.5, 1, y_at[i] + 0.5, col = "#E8E8E8", border = NA)
      text(0.06, y_at[i], row_df$model[i], adj = 0, font = 2, cex = 0.82)
    } else {
      text(0.18, y_at[i], row_df$level[i], adj = 0, cex = 0.72)
    }
  }
  mtext("Model", side = 3, line = 0.4, font = 2, cex = 0.85, adj = 0)

  .lookup <- function(m, h, lv, section_title = NULL) {
    mid <- suppressWarnings(as.integer(sub("Model\\s*", "", m)))
    hit <- rep(TRUE, nrow(d))
    if ("model_id" %in% names(d) && is.finite(mid)) hit <- hit & d$model_id == mid
    else hit <- hit & grepl(paste0("^", gsub("([()])", "\\\\\\1", m), "$"), d$model)
    hit <- hit & d$horizon == h & grepl(paste0(lv, "$"), d$level, ignore.case = TRUE)
    if (!is.null(section_title) && grepl("Competing", section_title) && "method" %in% names(d))
      hit <- hit & d$method == "competing"
    if (!is.null(section_title) && grepl("proportional|Standard", section_title, ignore.case = TRUE) && "method" %in% names(d))
      hit <- hit & d$method == "standard"
    if (!any(hit)) return(NULL)
    d[which(hit)[1L], , drop = FALSE]
  }

  for (hi in seq_along(horizons)) {
    h <- horizons[hi]
    sub_h <- d[d$horizon == h, , drop = FALSE]
    xlim <- range(c(0.5, 1, sub_h$lo, sub_h$hi), na.rm = TRUE)
    if (!all(is.finite(xlim))) xlim <- c(0.5, 3)
    xlim <- c(max(0.05, xlim[1] * 0.85), xlim[2] * 1.15)

    plot(1, type = "n", xlim = xlim, ylim = c(0.5, n_row + 0.5), log = "x", axes = FALSE, xlab = "", ylab = "")
    abline(v = 1, lty = 2, col = "grey50")
    axis(1, cex.axis = 0.65)
    for (i in seq_len(n_row)) {
      if (isTRUE(row_df$is_section[i]) || isTRUE(row_df$is_header[i])) {
        col <- if (isTRUE(row_df$is_section[i])) "#D9D9D9" else "#E8E8E8"
        rect(10^par("usr")[1], y_at[i] - 0.5, 10^par("usr")[2], y_at[i] + 0.5, col = col, border = NA)
        next
      }
      lv <- row_df$level[i]
      if (identical(lv, ref_lv)) next
      rr <- .lookup(row_df$model[i], h, lv, row_df$section[i])
      if (is.null(rr) || !is.finite(rr$HR[1])) next
      arrows(rr$lo[1], y_at[i], rr$hi[1], y_at[i], code = 3, angle = 90, length = 0.035, lwd = 1.15)
      points(rr$HR[1], y_at[i], pch = 15, cex = 1.05)
    }
    mtext(paste0(h, "-day"), side = 3, line = 1.35, font = 2, cex = 0.88)
    mtext("HR", side = 3, line = 0.15, cex = 0.65)

    plot(1, type = "n", xlim = c(0, 1), ylim = c(0.5, n_row + 0.5), axes = FALSE, xlab = "", ylab = "")
    mtext(sprintf("HR%d (95%% CI)", hi), side = 3, line = 0.4, font = 2, cex = 0.68)
    for (i in seq_len(n_row)) {
      if (isTRUE(row_df$is_section[i]) || isTRUE(row_df$is_header[i])) {
        col <- if (isTRUE(row_df$is_section[i])) "#D9D9D9" else "#E8E8E8"
        rect(0, y_at[i] - 0.5, 1, y_at[i] + 0.5, col = col, border = NA); next
      }
      if (identical(row_df$level[i], ref_lv)) { text(0.5, y_at[i], "Reference", cex = 0.65); next }
      rr <- .lookup(row_df$model[i], h, row_df$level[i], row_df$section[i])
      if (is.null(rr) || !is.finite(rr$HR[1])) next
      text(0.5, y_at[i], sprintf("%.2f (%.2f-%.2f)", rr$HR[1], rr$lo[1], rr$hi[1]), cex = 0.58)
    }

    plot(1, type = "n", xlim = c(0, 1), ylim = c(0.5, n_row + 0.5), axes = FALSE, xlab = "", ylab = "")
    mtext(sprintf("P%d", hi), side = 3, line = 0.4, font = 2, cex = 0.68)
    for (i in seq_len(n_row)) {
      if (isTRUE(row_df$is_section[i]) || isTRUE(row_df$is_header[i])) {
        col <- if (isTRUE(row_df$is_section[i])) "#D9D9D9" else "#E8E8E8"
        rect(0, y_at[i] - 0.5, 1, y_at[i] + 0.5, col = col, border = NA); next
      }
      if (identical(row_df$level[i], ref_lv)) next
      rr <- .lookup(row_df$model[i], h, row_df$level[i], row_df$section[i])
      if (is.null(rr) || !is.finite(rr$p[1])) next
      p_txt <- if (exists("pub_format_p", mode = "function")) {
        pub_format_p(rr$p[1])
      } else {
        format(signif(rr$p[1], 3), scientific = FALSE)
      }
      text(0.5, y_at[i], p_txt, cex = 0.65)
    }
  }
  mtext(title, side = 3, outer = TRUE, line = -1.0, font = 2, cex = 0.95)
  if (!is.null(footnote) && nzchar(footnote)) {
    fn <- as.character(footnote)[1L]
    # 长脚注拆两行，避免 Figure 5/9 被截断
    if (nchar(fn) > 140L && grepl(" \\| ", fn)) {
      parts <- strsplit(fn, " \\| ", perl = TRUE)[[1L]]
      mtext(parts[[1L]], side = 1, outer = TRUE, line = 0.85, cex = 0.58, adj = 0)
      mtext(paste(parts[-1L], collapse = " | "), side = 1, outer = TRUE, line = 1.75, cex = 0.58, adj = 0)
    } else {
      mtext(fn, side = 1, outer = TRUE, line = 1.4, cex = 0.58, adj = 0)
    }
  }
  invisible(NULL)
}

#' Figure 3: 2×3 RCS（主事件 7/14/28 + 死亡 7/14/28），可带 Model3 协变量
.competing_pub_rcs_grid <- function(data, index_var, time_var, event_col,
                                    primary, death, horizons = c(7, 14, 28),
                                    covs = character(0), title, outfile,
                                    primary_lab = "Diabetes") {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  pdf(outfile, width = 11, height = 7.2)
  on.exit(dev.off(), add = TRUE)
  op <- par(mfrow = c(2, 3), mar = c(4, 4, 2.5, 1))
  on.exit(par(op), add = TRUE)
  primary_lab <- as.character(primary_lab %||% "Diabetes")[1L]
  if (!nzchar(primary_lab)) primary_lab <- "Diabetes"
  panels <- list(
    list(cause = primary, lab = primary_lab, letters = c("A", "B", "C")),
    list(cause = death, lab = "Mortality", letters = c("D", "E", "F"))
  )
  for (pn in panels) {
    for (i in seq_along(horizons)) {
      h <- horizons[i]
      d <- data
      t0 <- suppressWarnings(as.numeric(d[[time_var]]))
      e0 <- suppressWarnings(as.integer(d[[event_col]]))
      d[[time_var]] <- pmin(t0, h)
      e1 <- e0; e1[is.na(t0) | t0 > h] <- 0L
      d[[event_col]] <- e1
      d$evt <- as.integer(d[[event_col]] == pn$cause)
      use_covs <- intersect(covs, names(d))
      keep <- c(index_var, time_var, "evt", use_covs)
      dd <- d[stats::complete.cases(d[keep]), , drop = FALSE]
      lab <- sprintf("%s) %s — %d-day", pn$letters[i], pn$lab, h)
      if (nrow(dd) < 40L || !requireNamespace("survival", quietly = TRUE)) {
        plot.new(); title(main = lab); next
      }
      rhs <- paste(c(paste0("splines::ns(", index_var, ", df=3)"), use_covs), collapse = " + ")
      fit <- tryCatch(
        survival::coxph(as.formula(paste0("Surv(", time_var, ", evt) ~ ", rhs)), data = dd),
        error = function(e) NULL
      )
      if (is.null(fit)) { plot.new(); title(main = lab); next }
      xx <- seq(stats::quantile(dd[[index_var]], 0.05, na.rm = TRUE),
                stats::quantile(dd[[index_var]], 0.95, na.rm = TRUE), length.out = 80)
      nd <- as.data.frame(matrix(NA, nrow = length(xx), ncol = length(use_covs) + 1L))
      names(nd) <- c(index_var, use_covs)
      nd[[index_var]] <- xx
      for (cv in use_covs) {
        if (is.numeric(dd[[cv]])) nd[[cv]] <- median(dd[[cv]], na.rm = TRUE)
        else nd[[cv]] <- names(sort(table(dd[[cv]]), decreasing = TRUE))[1]
      }
      pr <- tryCatch(predict(fit, newdata = nd, type = "lp", se.fit = TRUE), error = function(e) NULL)
      if (is.null(pr)) { plot.new(); title(main = lab); next }
      ref <- which.min(abs(xx - median(dd[[index_var]], na.rm = TRUE)))
      hr <- exp(pr$fit - pr$fit[ref])
      lo <- exp((pr$fit - 1.96 * pr$se.fit) - pr$fit[ref])
      hi <- exp((pr$fit + 1.96 * pr$se.fit) - pr$fit[ref])
      yr <- range(c(lo, hi, 1), na.rm = TRUE)
  if (!all(is.finite(yr)) || diff(yr) == 0) yr <- c(0.5, 2)
  plot(xx, hr, type = "l", lwd = 2, col = "#C0392B", xlab = index_var, ylab = "HR",
       main = lab, ylim = yr, cex.main = 0.95)
      polygon(c(xx, rev(xx)), c(lo, rev(hi)), col = grDevices::adjustcolor("#C0392B", 0.2), border = NA)
      lines(xx, hr, lwd = 2, col = "#C0392B")
      abline(h = 1, lty = 2, col = "grey40")
    }
  }
  invisible(NULL)
}

#' CIF + 底部 At Risk / Events 联合表（紧凑风险表 + 自适应 y 轴）
.competing_pub_cif_with_risk_table <- function(data, time_var, event_col, strata, cause,
                                               horizon, title, outfile,
                                               times = NULL) {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  title <- gsub("_", " ", title, fixed = TRUE)
  d <- data[!is.na(data[[strata]]) & !is.na(data[[time_var]]) & !is.na(data[[event_col]]), , drop = FALSE]
  if (!nrow(d) || !is.finite(horizon) || horizon <= 0) {
    pdf(outfile, width = 8, height = 6); plot.new(); title(main = paste0(title, "\n(no data)")); dev.off()
    return(invisible(NULL))
  }
  d[[strata]] <- factor(gsub("_", " ", as.character(d[[strata]]), fixed = TRUE))
  groups <- levels(d[[strata]])
  if (!length(groups)) {
    pdf(outfile, width = 8, height = 6); plot.new(); title(main = paste0(title, "\n(no strata)")); dev.off()
    return(invisible(NULL))
  }
  cols <- grDevices::hcl.colors(max(1L, length(groups)), "Dark 3")

  if (is.null(times) || !length(times)) {
    times <- seq(0, horizon, by = max(1, floor(horizon / 6)))
  }
  times <- sort(unique(c(0, times[is.finite(times) & times <= horizon], horizon)))
  times <- times[is.finite(times)]
  if (!length(times)) times <- c(0, horizon)

  at_risk <- matrix(NA_integer_, nrow = length(groups), ncol = length(times),
                    dimnames = list(groups, as.character(times)))
  events <- at_risk
  for (gi in seq_along(groups)) {
    g <- groups[gi]
    sub <- d[d[[strata]] == g, , drop = FALSE]
    for (j in seq_along(times)) {
      t <- times[j]
      at_risk[gi, j] <- sum(sub[[time_var]] >= t, na.rm = TRUE)
      events[gi, j] <- sum(sub[[event_col]] == cause & sub[[time_var]] <= t, na.rm = TRUE)
    }
  }

  # 先算 CIF 以便自适应 y 轴
  curve_list <- list()
  y_max <- 0.05
  if (requireNamespace("cmprsk", quietly = TRUE)) {
    tryCatch({
      ci <- cmprsk::cuminc(ftime = d[[time_var]], fstatus = d[[event_col]], group = d[[strata]])
      nm <- names(ci)
      cause_nm <- nm[grepl(paste0(" ", cause, "$"), nm)]
      if (!length(cause_nm)) cause_nm <- nm[!nm %in% "Tests"]
      for (k in seq_along(cause_nm)) {
        est <- ci[[cause_nm[k]]]$est
        curve_list[[k]] <- list(time = ci[[cause_nm[k]]]$time, est = est,
                                col = cols[((k - 1) %% length(cols)) + 1])
        if (length(est)) y_max <- max(y_max, max(est, na.rm = TRUE), na.rm = TRUE)
      }
    }, error = function(e) NULL)
  }
  if (!length(curve_list) && requireNamespace("survival", quietly = TRUE)) {
    d$evt <- as.integer(d[[event_col]] == cause)
    fit <- survival::survfit(as.formula(paste0("Surv(", time_var, ", evt) ~ ", strata)), data = d)
    # survfit multi-strata: extract max 1-surv
    y_max <- max(y_max, 1 - min(fit$surv, na.rm = TRUE), na.rm = TRUE)
  }
  if (!is.finite(y_max) || y_max <= 0) y_max <- 0.5
  # 向上取整到较美观刻度，至少留 10% 余量，不超过 1
  y_top <- min(1, ceiling(y_max * 1.12 * 20) / 20)
  if (y_top < y_max * 1.05) y_top <- min(1, y_max * 1.15)
  if (y_top < 0.1) y_top <- 0.1

  pdf(outfile, width = 8.8, height = 6.8)
  on.exit(dev.off(), add = TRUE)
  # 风险表更矮更紧凑
  layout(matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE),
         widths = c(1.1, 4.8), heights = c(3.85, 1.25))
  pad_r <- max(horizon * 0.04, 1.0)
  xlim_plot <- c(0, horizon + pad_r)
  n_g <- length(groups)
  # 两块紧挨：At Risk 上半、Events 下半，行距压缩
  y_at_title <- 0.98
  y_ev_title <- 0.48
  ys_at <- if (n_g == 1L) 0.80 else seq(0.88, 0.58, length.out = n_g)
  ys_ev <- if (n_g == 1L) 0.28 else seq(0.38, 0.10, length.out = n_g)

  par(mar = c(2.0, 0.15, 2.4, 0.05))
  plot.new()
  text(0.65, 0.5, "Cumulative incidence", srt = 90, cex = 1.0)

  par(mar = c(2.0, 0.55, 2.4, 1.0))
  plot(1, type = "n", xlim = xlim_plot, ylim = c(0, y_top),
       xlab = "", ylab = "", main = title, xaxs = "i", yaxs = "i", axes = FALSE)
  axis(2)
  axis(1, at = times)
  mtext("Days", side = 1, line = 1.35, cex = 0.85)
  box()
  if (length(curve_list)) {
    for (k in seq_along(curve_list)) {
      lines(curve_list[[k]]$time, curve_list[[k]]$est, col = curve_list[[k]]$col, lwd = 2)
    }
  } else if (requireNamespace("survival", quietly = TRUE)) {
    d$evt <- as.integer(d[[event_col]] == cause)
    fit <- survival::survfit(as.formula(paste0("Surv(", time_var, ", evt) ~ ", strata)), data = d)
    lines(fit, fun = "event", col = cols, lwd = 2, conf.int = FALSE)
  }
  legend("topleft", legend = groups, col = cols, lty = 1, lwd = 2, bty = "n", cex = 0.75)

  par(mar = c(0.15, 0.15, 0.02, 0.05))
  plot(1, type = "n", xlim = c(0, 1), ylim = c(0, 1), axes = FALSE, xlab = "", ylab = "")
  text(0.98, y_at_title, "At Risk", adj = 1, font = 2, cex = 0.68)
  text(0.98, y_ev_title, "Events", adj = 1, font = 2, cex = 0.68)
  for (gi in seq_along(groups)) {
    text(0.98, ys_at[gi], groups[gi], adj = 1, cex = 0.62)
    text(0.98, ys_ev[gi], groups[gi], adj = 1, cex = 0.62)
  }

  par(mar = c(0.15, 0.55, 0.02, 1.0))
  plot(1, type = "n", xlim = xlim_plot, ylim = c(0, 1),
       axes = FALSE, xlab = "", ylab = "", xaxs = "i", yaxs = "i")
  for (gi in seq_along(groups)) {
    x_num <- ifelse(times <= 0, 0.35, times)
    text(x_num, ys_at[gi], as.character(at_risk[gi, ]), cex = 0.60)
    text(x_num, ys_ev[gi], as.character(events[gi, ]), cex = 0.60)
  }
  invisible(list(at_risk = at_risk, events = events, times = times, y_top = y_top))
}

#' Table 2/4：Group × 7/14/28-day Overall mortality (%) + P（文献双层表头）
.competing_write_cif_mortality_xlsx <- function(path, data, time_var, event_col, strata, cause,
                                                horizons = c(7L, 14L, 28L), title = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (is.null(title) || !nzchar(title)) title <- sub("\\.xlsx$", "", basename(path))
  title <- gsub("_", " ", title, fixed = TRUE)
  d <- data[!is.na(data[[strata]]) & !is.na(data[[time_var]]) & !is.na(data[[event_col]]), , drop = FALSE]
  d[[strata]] <- factor(gsub("_", " ", as.character(d[[strata]]), fixed = TRUE))
  groups <- levels(d[[strata]])
  horizons <- as.integer(horizons)
  hlab <- paste0(horizons, "-day")

  # 各时点死亡率 (%) + 组间 P（卡方 / Fisher）
  mort <- matrix(NA_real_, nrow = length(groups), ncol = length(horizons),
                 dimnames = list(groups, hlab))
  pvals <- setNames(rep(NA_real_, length(horizons)), hlab)
  for (j in seq_along(horizons)) {
    h <- horizons[j]
    evt_by_g <- integer(length(groups))
    n_by_g <- integer(length(groups))
    for (gi in seq_along(groups)) {
      sub <- d[d[[strata]] == groups[gi], , drop = FALSE]
      n_by_g[gi] <- nrow(sub)
      evt_by_g[gi] <- sum(sub[[event_col]] == cause & sub[[time_var]] <= h, na.rm = TRUE)
      mort[gi, j] <- if (n_by_g[gi] > 0) round(100 * evt_by_g[gi] / n_by_g[gi], 1) else NA_real_
    }
    tab <- rbind(evt_by_g, pmax(0L, n_by_g - evt_by_g))
    pvals[j] <- tryCatch({
      if (any(tab < 5)) fisher.test(tab)$p.value else chisq.test(tab)$p.value
    }, error = function(e) NA_real_)
  }

  # 双层表头：每时点 2 列（mortality, P）
  nc <- 1L + 2L * length(horizons)
  h1 <- c("Group", rep("", nc - 1L))
  h2 <- c("", rep("", nc - 1L))
  for (j in seq_along(horizons)) {
    c0 <- 2L + (j - 1L) * 2L
    h1[c0] <- hlab[j]
    h2[c0] <- "Overall mortality (%)"
    h2[c0 + 1L] <- "P"
  }
  body <- matrix("", nrow = length(groups), ncol = nc)
  for (gi in seq_along(groups)) {
    body[gi, 1] <- groups[gi]
    for (j in seq_along(horizons)) {
      c0 <- 2L + (j - 1L) * 2L
      body[gi, c0] <- if (is.finite(mort[gi, j])) format(mort[gi, j], nsmall = 1) else ""
      if (gi == 1L && is.finite(pvals[j])) {
        pv <- pvals[j]
        body[gi, c0 + 1L] <- if (pv < 0.001) "<0.001" else sprintf("%.3f", pv)
      }
    }
  }

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Table", gridLines = FALSE)
  openxlsx::writeData(wb, "Table", title, startRow = 1, colNames = FALSE)
  openxlsx::mergeCells(wb, "Table", rows = 1, cols = 1:nc)
  openxlsx::writeData(wb, "Table", rbind(h1, h2), startRow = 3, colNames = FALSE)
  openxlsx::mergeCells(wb, "Table", rows = 3:4, cols = 1)
  for (j in seq_along(horizons)) {
    c0 <- 2L + (j - 1L) * 2L
    openxlsx::mergeCells(wb, "Table", rows = 3, cols = c0:(c0 + 1L))
  }
  openxlsx::writeData(wb, "Table", as.data.frame(body, stringsAsFactors = FALSE),
                      startRow = 5, colNames = FALSE)

  title_st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 12,
                                    textDecoration = "bold", halign = "left", valign = "center")
  head_st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11,
                                   textDecoration = "bold", halign = "center", valign = "center",
                                   border = "TopBottom", borderStyle = c("medium", "thin"))
  body_st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11,
                                   halign = "center", valign = "center")
  left_st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11,
                                   halign = "left", valign = "center")
  bot_st <- openxlsx::createStyle(fontName = "Times New Roman", fontSize = 11,
                                  halign = "center", valign = "center",
                                  border = "Bottom", borderStyle = "medium")
  openxlsx::addStyle(wb, "Table", title_st, rows = 1, cols = 1:nc, gridExpand = TRUE)
  openxlsx::addStyle(wb, "Table", head_st, rows = 3:4, cols = 1:nc, gridExpand = TRUE)
  if (length(groups) > 1L) {
    openxlsx::addStyle(wb, "Table", body_st, rows = 5:(3 + length(groups)), cols = 1:nc, gridExpand = TRUE)
    openxlsx::addStyle(wb, "Table", left_st, rows = 5:(3 + length(groups)), cols = 1, gridExpand = TRUE)
  }
  openxlsx::addStyle(wb, "Table", bot_st, rows = 4 + length(groups), cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, "Table", left_st, rows = 4 + length(groups), cols = 1, stack = TRUE)
  openxlsx::setColWidths(wb, "Table", cols = 1, widths = 14)
  openxlsx::setColWidths(wb, "Table", cols = 2:nc, widths = 14)
  openxlsx::setRowHeights(wb, "Table", rows = 3:4, heights = 16)
  openxlsx::setRowHeights(wb, "Table", rows = 5:(4 + length(groups)), heights = 15)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}
