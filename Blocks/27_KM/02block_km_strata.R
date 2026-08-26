###############################################################################
#  km_strata — 多水平分层变量批量 Kaplan–Meier（含 strata_defs 派生分组）。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  写: ctx$data$km_strata_derived（仅 ID + 派生/分层列 + time/event，不污染 imputed）
#
#  km_strata = list(
#    strata_vars   = c("RAR_quartile"),                    # 要画 KM 的列（仅此列表出图）
#    strata_vars_by_branch = list(                         # 可选：按 ctx$results$cox_branch 切换
#      extend_quartile = c("RAR_quartile"),
#      extend_tertile  = c("RAR_tertile")
#    ),
#    strata_defs   = list(                                 # 派生分组定义（须与 strata_vars 名一致）
#      Age_Group = list(
#        source = "Age", type = "cut_manual",
#        breaks = c(25, 35, 45),
#        labels = c("< 25", "25-34", "35-44", "\u2265 45"),
#        levels = c("< 25", "25-34", "35-44", "\u2265 45")
#      ),
#      AMH_factor = list(
#        source = "AMH", type = "cut_quantile",
#        probs = c(0, .25, .5, .75, 1),
#        labels = c("AMH Q1", "AMH Q2", "AMH Q3", "AMH Q4")
#      ),
#      Specimen_Bag = list(
#        source = "Specimen_Bag", type = "factor_relabel",
#        levels = c(0, 1), labels = c("No Bag", "Bag")
#      ),
#      Dysmenorrhea_VAS = list(
#        source = "Dysmenorrhea_VAS", type = "case_when",
#        rules = list(
#          list(op = "range", min = 0, max = 3, label = "Mild (0-3)"),
#          list(op = "range", min = 4, max = 6, label = "Moderate (4-6)"),
#          list(op = "range", min = 7, max = 10, label = "Severe (7-10)")
#        ),
#        levels = c("Mild (0-3)", "Moderate (4-6)", "Severe (7-10)")
#      )
#    ),
#    time_var = "RFS_Months", event_var = "Is_Recurrence_factor",
#    event_value = 1, time_divisor = 12,
#    fun = "pct", palette = c("#4E79A7", ...),
#    risk_table = TRUE, fallback_no_pval = TRUE,
#    export_combined = TRUE, combined_ncol = 3, combined_nrow = 4,
#    single_filename_template = "KM Plot {strata}.pdf",  # 不占 main/supp Figure 编号
#    figure_number = 4L,  # 固定主文 Figure 4（双库各自 -eICU / -MIMIC）
#    figure_caption_template = "Kaplan-Meier curves of {index} {method} and mortality in {disease}",
#    single_use_main_figure = TRUE,  # template 为空时 TRUE→pub_figure_file；FALSE→默认 template
#    combined 仍用 main_figure（如 Figure 3. Combined KM Plots）
#    pause_enable = TRUE, pause_on_no_figures = TRUE
#  ),
#
#  strata_defs$type: identity | factor_relabel | cut_manual | cut_quantile | case_when
#  case_when$rules$op: range | lt | lte | gte | gt | eq | in
#
#  register_block: "km_strata"
###############################################################################

.kms02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.kms02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "km_strata", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.kms02_sanitize_legend <- function(x) {
  if (!length(x)) return(x)
  v <- as.character(x)
  v <- gsub("<", "\u2039", v, fixed = TRUE)
  v <- gsub(">", "\u203a", v, fixed = TRUE)
  v <- gsub("\uff1c", "\u2039", v, fixed = TRUE)
  v <- gsub("\uff1e", "\u203a", v, fixed = TRUE)
  v
}

.kms02_coerce_event_01 <- function(x, cfg, event_var) {
  if (is.numeric(x)) {
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (length(ux) && all(ux %in% c(0, 1))) return(as.numeric(x))
    stop("km_strata: ", event_var, " 非 0/1 数值编码。")
  }
  if (is.logical(x)) return(as.integer(x))
  xc <- trimws(as.character(x))
  ref_lbl <- trimws(cfg$project$reference_group %||% "")
  ana_lbl <- trimws(cfg$project$analysis_group %||% "")
  out <- rep(NA_integer_, length(xc))
  if (nzchar(ana_lbl)) out[xc == ana_lbl] <- 1L
  if (nzchar(ref_lbl)) out[xc == ref_lbl] <- 0L
  if (nzchar(ana_lbl)) out[tolower(xc) == tolower(ana_lbl) & is.na(out)] <- 1L
  if (nzchar(ref_lbl)) out[tolower(xc) == tolower(ref_lbl) & is.na(out)] <- 0L
  if (!nzchar(ana_lbl) && !nzchar(ref_lbl)) {
    ev <- cfg$km_strata$event_value %||% cfg$survival$event_value %||% 1
    if (is.numeric(ev)) {
      out[suppressWarnings(as.numeric(xc)) == ev] <- 1L
      out[suppressWarnings(as.numeric(xc)) != ev & !is.na(suppressWarnings(as.numeric(xc)))] <- 0L
    }
  }
  out[is.na(xc)] <- NA_integer_
  out
}

.kms02_index_var_from_ctx <- function(ctx, cfg, strata_col) {
  ix <- cfg$survival$index_var %||% cfg$km_strata$index_var %||% NULL
  if (!is.null(ix) && nzchar(as.character(ix)[1L])) return(as.character(ix)[1L])
  sub("_(tertile|quartile)$", "", as.character(strata_col)[1L], perl = TRUE)
}

.kms02_method_label <- function(strata_col) {
  sc <- as.character(strata_col)[1L]
  if (grepl("_tertile$", sc, ignore.case = TRUE)) return("tertile")
  if (grepl("_quartile$", sc, ignore.case = TRUE)) return("quartile")
  gsub("_", " ", sc, fixed = TRUE)
}

.kms02_figure_caption <- function(ctx, cfg, bl_cfg, strata_col, index_var) {
  tpl <- as.character(bl_cfg$figure_caption_template %||% "")[1L]
  disease <- gsub("_", " ", cfg$project$disease %||% cfg$project$analysis_group %||% "patients")
  method <- .kms02_method_label(strata_col)
  strata_lab <- gsub("_", " ", as.character(strata_col)[1L], fixed = TRUE)
  if (nzchar(tpl)) {
    out <- tpl
    out <- gsub("\\{index\\}", index_var, out, fixed = FALSE)
    out <- gsub("\\{method\\}", method, out, fixed = FALSE)
    out <- gsub("\\{disease\\}", disease, out, fixed = FALSE)
    out <- gsub("\\{strata\\}", strata_lab, out, fixed = FALSE)
    return(out)
  }
  paste0(
    "Kaplan\u2013Meier curves of ", index_var, " ", method,
    " and mortality in ", disease
  )
}

.kms02_cut_by_breaks <- function(x, breaks, labels) {
  breaks <- as.numeric(breaks)
  labels <- as.character(labels)
  if (!length(breaks) || !length(labels)) return(NULL)
  x <- suppressWarnings(as.numeric(x))
  # 与 cox_quartile / pipeline_quartile_factor 一致：左闭右开，切点值进入较高组
  if (exists("pipeline_quantile_group_factor", mode = "function") &&
      length(labels) %in% c(3L, 4L)) {
    method <- if (length(labels) == 4L) "quartile" else "tertile"
    fac <- tryCatch(
      pipeline_quantile_group_factor(x, method = method, breaks = breaks),
      error = function(e) NULL
    )
    if (!is.null(fac)) return(fac)
  }
  if (length(labels) != length(breaks) + 1L) return(NULL)
  factor(
    cut(
      x,
      breaks = c(-Inf, breaks, Inf),
      labels = labels, right = FALSE, include.lowest = TRUE
    ),
    levels = labels
  )
}

.kms02_try_strata_from_cox <- function(dat, col, index_var, ctx) {
  cg <- ctx$results$cox_grouping %||% NULL
  br <- ctx$results$cox_index_breaks %||% NULL
  if (is.null(cg) || is.null(br) || !length(br)) return(NULL)
  ix <- as.character(index_var)[1L]
  want <- switch(as.character(cg$method %||% ""),
    tertile = paste0(ix, "_tertile"),
    quartile = paste0(ix, "_quartile"),
    NULL)
  if (is.null(want) || col != want || !ix %in% names(dat)) return(NULL)
  lv <- as.character(cg$group_levels %||% NULL)
  if (!length(lv)) {
    lv <- if (identical(cg$method, "tertile")) c("T1", "T2", "T3") else c("Q1", "Q2", "Q3", "Q4")
  }
  fac <- .kms02_cut_by_breaks(dat[[ix]], br, lv)
  if (is.null(fac)) return(NULL)
  levels(fac) <- .kms02_sanitize_legend(levels(fac))
  fac
}

#' 单张 KM 文件名（不调用 pub_next_id，不占 Figure / Figure S 序号）
.kms02_single_km_filepath <- function(fig_dir, strata_col, template = NULL) {
  label <- gsub("_", " ", as.character(strata_col)[1L], fixed = TRUE)
  tpl <- as.character(template %||% "KM Plot {strata}.pdf")[1L]
  fn <- gsub("\\{strata\\}", label, tpl, fixed = FALSE)
  if (!grepl("\\.[Pp][Dd][Ff]$", fn)) fn <- paste0(fn, ".pdf")
  if (exists(".inject_db_into_pub_label", mode = "function")) {
    fn <- .inject_db_into_pub_label(fn, sanitize_for_file = TRUE)
  }
  file.path(fig_dir, fn)
}

.kms02_resolve_single_km_path <- function(ctx, fig_dir, strata_col, bl_cfg, cfg) {
  tpl <- bl_cfg$single_filename_template
  if (!is.null(tpl) && nzchar(tpl)) {
    return(.kms02_single_km_filepath(fig_dir, strata_col, tpl))
  }
  fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% NA_integer_))
  fig_kind <- as.character(bl_cfg$figure_kind %||% "main_figure")[1L]
  if (!nzchar(fig_kind)) fig_kind <- "main_figure"
  if (is.finite(fig_no) && fig_no >= 1L &&
      exists("pub_figure_filepath_at", mode = "function")) {
    ix <- .kms02_index_var_from_ctx(ctx, cfg, strata_col)
    cap <- .kms02_figure_caption(ctx, cfg, bl_cfg, strata_col, ix)
    return(pub_figure_filepath_at(
      fig_dir, fig_no, cap, ext = "pdf", bump_counter = TRUE, kind = fig_kind
    ))
  }
  if (isTRUE(bl_cfg$single_use_main_figure %||% identical(fig_kind, "main_figure"))) {
    cap <- paste0("KM Plot ", gsub("_", " ", strata_col, fixed = TRUE))
    return(file.path(fig_dir, pub_figure_file(ctx, fig_kind, cap)))
  }
  .kms02_single_km_filepath(fig_dir, strata_col, "KM Plot {strata}.pdf")
}

.kms02_strip_strata_labels <- function(labels, var_name) {
  v <- trimws(as.character(labels))
  if (!length(v)) return(v)
  pe <- paste0(var_name, "=")
  hit <- startsWith(v, pe)
  v[hit] <- trimws(substring(v[hit], nchar(pe) + 1L))
  hit2 <- startsWith(v, var_name)
  v[hit2] <- trimws(substring(v[hit2], nchar(var_name) + 1L))
  v <- sub("^=+", "", v)
  has_eq <- grepl("=", v, fixed = TRUE)
  v[has_eq] <- sub("^[^=]+=", "", v[has_eq])
  .kms02_sanitize_legend(trimws(v))
}

.kms02_logrank_p_numeric <- function(formula, data) {
  sd <- tryCatch(survival::survdiff(formula, data = data), error = function(e) NULL)
  if (is.null(sd)) return(NA_real_)
  ch <- sd$chisq
  df <- length(sd$n) - 1L
  if (!is.finite(ch) || ch < 0 || df < 1L) return(NA_real_)
  pv <- stats::pchisq(ch, df = df, lower.tail = FALSE)
  if (!is.finite(pv)) return(NA_real_)
  min(max(pv, 0), 1)
}

.kms02_safe_logrank_p <- function(formula, data) {
  pv <- .kms02_logrank_p_numeric(formula, data)
  if (!is.finite(pv)) return("Log-rank P = NA")
  # 保留 3 位小数；p < 0.001 显示为 P < 0.001
  if (pv < 0.001) return("Log-rank P < 0.001")
  paste0("Log-rank P = ", formatC(pv, digits = 3, format = "f"))
}

.kms02_pdf_open <- function(path, width, height, family = "Times New Roman") {
  ff <- as.character(family %||% "Times New Roman")[1L]
  if (!nzchar(ff)) ff <- "Times New Roman"
  # cairo 可嵌入系统 Times New Roman；失败再回退 pdf()+Times
  opened <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    opened <- tryCatch({
      grDevices::cairo_pdf(file = path, width = width, height = height, family = ff)
      TRUE
    }, error = function(e) FALSE)
  }
  if (!isTRUE(opened)) {
    ff2 <- if (exists("resolve_plot_font_family", mode = "function")) {
      resolve_plot_font_family(ff)
    } else {
      "Times"
    }
    grDevices::pdf(
      file = path, width = width, height = height, family = ff2,
      useDingbats = FALSE, onefile = TRUE, compress = TRUE, version = "1.7"
    )
  }
  invisible(TRUE)
}

.kms02_write_pdf_atomic <- function(obj, path, width, height,
                                    family = "Times New Roman") {
  tmp <- tempfile(pattern = "km_", fileext = ".pdf")
  tryCatch({
    .kms02_pdf_open(tmp, width, height, family = family)
    if (inherits(obj, "ggsurvplot")) print(obj, newpage = FALSE) else print(obj)
    grDevices::dev.off()
    fi <- file.info(tmp)
    if (is.na(fi$size) || fi$size < 200L) stop("临时 PDF 过小")
    if (file.exists(path)) unlink(path, force = TRUE)
    if (!file.copy(tmp, path, overwrite = TRUE)) stop("无法复制 PDF")
    invisible(path)
  }, finally = {
    if (grDevices::dev.cur() > 1L) try(grDevices::dev.off(), silent = TRUE)
    if (file.exists(tmp)) unlink(tmp, force = TRUE)
  })
}

.kms02_match_case_rule <- function(x, rule) {
  op <- tolower(rule$op %||% "range")
  if (op == "range") {
    mn <- rule$min %||% -Inf
    mx <- rule$max %||% Inf
    !is.na(x) & x >= mn & x <= mx
  } else if (op == "lt") {
    !is.na(x) & x < rule$value
  } else if (op == "lte") {
    !is.na(x) & x <= rule$value
  } else if (op == "gt") {
    !is.na(x) & x > rule$value
  } else if (op == "gte") {
    !is.na(x) & x >= rule$value
  } else if (op == "eq") {
    !is.na(x) & x == rule$value
  } else if (op == "in") {
    !is.na(x) & x %in% unlist(rule$values)
  } else {
    rep(FALSE, length(x))
  }
}

.kms02_apply_case_when <- function(x, rules) {
  out <- rep(NA_character_, length(x))
  for (rule in rules) {
    lab <- rule$label %||% NULL
    if (is.null(lab)) next
    hit <- .kms02_match_case_rule(x, rule)
    out[hit & is.na(out)] <- as.character(lab)
  }
  out
}

.kms02_apply_cut_manual <- function(x, breaks, labels) {
  if (length(labels) != length(breaks) + 1L) {
    stop("cut_manual: labels 长度须为 breaks + 1")
  }
  out <- rep(NA_character_, length(x))
  brk <- as.numeric(breaks)
  for (i in seq_along(labels)) {
    if (i == 1L) {
      mask <- !is.na(x) & x < brk[1L]
    } else if (i < length(labels)) {
      mask <- !is.na(x) & x >= brk[i - 1L] & x < brk[i]
    } else {
      mask <- !is.na(x) & x >= brk[length(brk)]
    }
    out[mask] <- labels[i]
  }
  out
}

.kms02_to_factor <- function(vec, levels = NULL) {
  if (!is.null(levels) && length(levels)) {
    factor(vec, levels = levels)
  } else {
    factor(vec)
  }
}

.kms02_apply_strata_def <- function(dat, out_col, def) {
  src  <- def$source %||% out_col
  type <- tolower(def$type %||% "identity")
  if (!src %in% names(dat)) {
    cli::cli_alert_warning("strata_defs${out_col}: 源列 {src} 不存在，跳过")
    return(NULL)
  }
  x <- dat[[src]]
  vec <- switch(type,
    identity = as.character(x),
    factor_relabel = {
      lv <- def$levels %||% levels(def$labels)
      lb <- def$labels %||% lv
      factor(x, levels = lv, labels = lb)
    },
    cut_manual = .kms02_apply_cut_manual(
      suppressWarnings(as.numeric(x)),
      def$breaks, def$labels
    ),
    tertile_factor = {
      if (!exists("pipeline_tertile_factor", mode = "function")) {
        stop("km_strata: tertile_factor 需要 pipeline_tertile_factor", call. = FALSE)
      }
      as.character(pipeline_tertile_factor(
        suppressWarnings(as.numeric(x)),
        breaks = def$breaks_full %||% def$breaks
      ))
    },
    quartile_factor = {
      if (!exists("pipeline_quartile_factor", mode = "function")) {
        stop("km_strata: quartile_factor 需要 pipeline_quartile_factor", call. = FALSE)
      }
      as.character(pipeline_quartile_factor(
        suppressWarnings(as.numeric(x)),
        breaks = def$breaks_full %||% def$breaks
      ))
    },
    cut_quantile = {
      probs <- def$probs %||% c(0, 0.25, 0.5, 0.75, 1)
      br <- unique(stats::quantile(
        suppressWarnings(as.numeric(x)), probs = probs, na.rm = TRUE
      ))
      if (length(br) < 2L) rep(NA_character_, length(x)) else {
        cut(
          suppressWarnings(as.numeric(x)),
          breaks = br, labels = def$labels,
          include.lowest = isTRUE(def$include_lowest %||% TRUE),
          right = isTRUE(def$right %||% FALSE)
        )
      }
    },
    case_when = .kms02_apply_case_when(
      suppressWarnings(as.numeric(x)),
      def$rules %||% list()
    ),
    stop("km_strata: 未知 strata_defs$type: ", type)
  )
  if (inherits(vec, "factor")) vec else .kms02_to_factor(vec, def$levels)
}

#' 按 cox_branch 选 strata_vars；仅 strata_vars 参与出图（strata_defs 只负责派生列）
.kms02_resolve_strata_vars <- function(bl_cfg, ctx) {
  branch <- as.character(ctx$results$cox_branch %||% "")[1L]
  by_branch <- bl_cfg$strata_vars_by_branch %||% NULL
  if (is.list(by_branch) && nzchar(branch) && !is.null(by_branch[[branch]])) {
    return(unique(trimws(as.character(unlist(by_branch[[branch]])))))
  }
  unique(trimws(as.character(bl_cfg$strata_vars %||% character(0))))
}

.kms02_prepare_strata_column <- function(dat, col, strata_defs, ctx = NULL, index_var = NULL) {
  # 优先使用 cox_quartile 已写入的分位列（与 Table 2 / S10 完全同一分组）
  if (col %in% names(dat) && is.factor(dat[[col]])) {
    lv <- as.character(levels(dat[[col]]))
    if (length(lv) >= 2L && all(lv %in% c("Q1", "Q2", "Q3", "Q4", "T1", "T2", "T3"))) {
      x <- dat[[col]]
      levels(x) <- .kms02_sanitize_legend(levels(x))
      return(x)
    }
  }
  if (!is.null(ctx) && !is.null(index_var) && nzchar(index_var)) {
    fac <- .kms02_try_strata_from_cox(dat, col, index_var, ctx)
    if (!is.null(fac)) return(fac)
  }
  if (col %in% names(strata_defs)) {
    fac <- .kms02_apply_strata_def(dat, col, strata_defs[[col]])
    if (is.null(fac)) return(NULL)
    return(fac)
  }
  if (!col %in% names(dat)) {
    cli::cli_alert_warning("分层列 {col} 不在数据中且无 strata_defs，跳过")
    return(NULL)
  }
  x <- dat[[col]]
  if (!is.factor(x)) x <- factor(as.character(x))
  levels(x) <- .kms02_sanitize_legend(levels(x))
  x
}

.kms02_max_at_risk_time <- function(fit) {
  s <- tryCatch(summary(fit, extend = TRUE), error = function(e) NULL)
  if (!is.null(s) && length(s$time) && length(s$n.risk)) {
    t <- suppressWarnings(as.numeric(s$time))
    r <- suppressWarnings(as.numeric(s$n.risk))
    if (length(t) == length(r)) {
      keep <- is.finite(t) & is.finite(r) & r > 0
      if (any(keep)) return(max(t[keep], na.rm = TRUE))
    }
  }
  tb <- tryCatch(as.matrix(summary(fit)$table), error = function(e) NULL)
  if (!is.null(tb) && "records" %in% colnames(tb)) {
    mx <- suppressWarnings(max(as.numeric(tb[, "records"]), na.rm = TRUE))
    if (is.finite(mx) && mx > 0) return(mx)
  }
  NA_real_
}

.kms02_resolve_time_axis <- function(fit, rt_plot, time_col, time_div, bl_cfg, km_cfg) {
  auto_x <- isTRUE(bl_cfg$auto_xlim %||% km_cfg$auto_xlim %||% TRUE)
  auto_br <- isTRUE(bl_cfg$auto_break_time %||% km_cfg$auto_break_time %||% TRUE)
  cfg_xlim <- bl_cfg$xlim %||% km_cfg$xlim
  cfg_break <- bl_cfg$break_time_by %||% km_cfg$break_time_by
  div <- if (is.finite(time_div) && time_div > 0) time_div else 1

  data_max <- suppressWarnings(max(as.numeric(rt_plot[[time_col]]) / div, na.rm = TRUE))
  risk_max <- .kms02_max_at_risk_time(fit)
  upper <- risk_max
  if (!is.finite(upper)) upper <- data_max
  else if (is.finite(data_max)) upper <- min(upper, data_max)
  if (!is.finite(upper) || upper <= 0) upper <- max(data_max, 1, na.rm = TRUE)

  pad <- max(1, ceiling(upper * 0.05))
  auto_upper <- ceiling(upper + pad)

  if (auto_x || is.null(cfg_xlim)) {
    xlim <- c(0, auto_upper)
  } else {
    xlim <- as.numeric(cfg_xlim)
    if (length(xlim) < 2L) xlim <- c(0, auto_upper)
    xlim[2] <- min(xlim[2], auto_upper)
    if (diff(xlim) <= 0) xlim <- c(0, auto_upper)
  }

  if (auto_br || is.null(cfg_break)) {
    span <- diff(xlim)
    break_by <- if (span <= 28) 7 else if (span <= 84) 14 else if (span <= 168) 28 else
      max(7L, ceiling(span / 8))
  } else {
    break_by <- as.numeric(cfg_break)[1]
  }
  list(xlim = xlim, break_time_by = break_by)
}

.kms02_plot_one_strata <- function(rt_plot, plot_col, display_name, formula, bl_cfg, palette,
                                    font_family, km_cfg, time_col, time_div = 1,
                                    for_combined = FALSE, config = NULL) {
  suppressPackageStartupMessages({
    library(survival)
    library(survminer)
    library(ggplot2)
  })

  fit <- survival::survfit(formula, data = rt_plot)
  fit$call$formula <- formula

  # 图例 N/E = 全随访总人数与总事件（与 Table 1 / Cox 同源）；禁止用 28 天 landmark 事件数
  cnt <- if (exists("pipeline_km_stratum_counts", mode = "function")) {
    pipeline_km_stratum_counts(fit)
  } else {
    data.frame(n = as.integer(fit$n), n_event = as.integer(fit$n.event))
  }
  sn <- .kms02_strip_strata_labels(names(fit$strata) %||% levels(rt_plot[[plot_col]]), plot_col)
  if (!length(sn) || length(sn) != nrow(cnt)) {
    sn <- as.character(levels(rt_plot[[plot_col]]))
  }
  n_lab <- min(length(sn), nrow(cnt))
  labs <- sprintf("%-15s (N=%d, E=%d)", sn[seq_len(n_lab)], cnt$n[seq_len(n_lab)],
                  cnt$n_event[seq_len(n_lab)])
  labs <- .kms02_sanitize_legend(labs)

  med_values <- summary(fit)$table
  has_na_med <- if (is.matrix(med_values)) any(is.na(med_values[, "median"])) else
    is.na(med_values["median"])
  median_line <- if (has_na_med) "none" else "hv"

  fun_arg <- bl_cfg$fun %||% "pct"
  if (identical(fun_arg, "none") || identical(fun_arg, NULL)) fun_arg <- NULL

  xlab <- bl_cfg$xlab %||% km_cfg$xlab %||% "Follow-up time (days)"
  ylab <- bl_cfg$ylab %||% km_cfg$ylab %||% "Survival probability (%)"
  time_axis <- .kms02_resolve_time_axis(fit, rt_plot, time_col, time_div, bl_cfg, km_cfg)
  km_xlim <- time_axis$xlim
  km_break <- time_axis$break_time_by
  risk_tbl <- isTRUE(bl_cfg$risk_table %||% TRUE) && !for_combined
  fallback <- isTRUE(bl_cfg$fallback_no_pval %||% TRUE)

  ## 全图强制 Times New Roman（cairo_pdf 可嵌入；禁止 mono/sans/Helvetica）
  ff <- as.character(font_family %||% "Times New Roman")[1L]
  if (!nzchar(ff)) ff <- "Times New Roman"
  .kms02_tnr_theme <- function(base_size = 11, title_size = NULL) {
    title_size <- title_size %||% base_size
    ggplot2::theme_classic(base_size = base_size, base_family = ff) +
      ggplot2::theme(
        text = ggplot2::element_text(family = ff),
        plot.title = ggplot2::element_text(
          hjust = 0.5, face = "bold", family = ff, size = title_size
        ),
        legend.text = ggplot2::element_text(family = ff),
        legend.title = ggplot2::element_text(family = ff),
        strip.text = ggplot2::element_text(family = ff),
        axis.text = ggplot2::element_text(family = ff),
        axis.title = ggplot2::element_text(family = ff)
      )
  }
  gg_km <- .kms02_tnr_theme(11)
  tbl_km <- .kms02_tnr_theme(10)

  build_plot <- function(with_risk, show_pval) {
    pv <- if (isTRUE(show_pval)) .kms02_safe_logrank_p(formula, rt_plot) else FALSE
    risk_h <- suppressWarnings(as.numeric(bl_cfg$risk_table_height %||% 0.28)[1L])
    if (!is.finite(risk_h) || risk_h <= 0 || risk_h >= 1) risk_h <- 0.28
    p <- ggsurvplot(
      fit, data = rt_plot,
      risk.table = with_risk,
      risk.table.height = risk_h,
      risk.table.y.text = FALSE,
      tables.height = risk_h,
      conf.int = FALSE,
      surv.median.line = median_line,
      xlim = if (for_combined) NULL else km_xlim,
      break.time.by = if (for_combined) NULL else km_break,
      title = .kms02_sanitize_legend(
        if (for_combined) {
          display_name
        } else if (!is.null(bl_cfg$title)) {
          as.character(bl_cfg$title)[1L]
        } else {
          paste("Survival Analysis by", display_name)
        }
      ),
      xlab = .kms02_sanitize_legend(if (for_combined) "Time (d)" else xlab),
      ylab = .kms02_sanitize_legend(if (for_combined) "Prob (%)" else ylab),
      legend.title = .kms02_sanitize_legend(if (for_combined) "" else display_name),
      legend.labs = labs,
      fun = fun_arg,
      pval = pv,
      pval.size = if (for_combined) 3 else 4,
      palette = palette,
      ggtheme = if (for_combined) {
        .kms02_tnr_theme(8, title_size = 10)
      } else gg_km,
      tables.theme = if (with_risk) tbl_km else NULL
    )
    # survminer 部分图层会落到 Helvetica/Courier；强制整图 Times New Roman
    .force_tnr <- function(g) {
      if (is.null(g) || !inherits(g, "ggplot")) return(g)
      g + ggplot2::theme(
        text = ggplot2::element_text(family = ff),
        plot.title = ggplot2::element_text(family = ff),
        legend.text = ggplot2::element_text(family = ff),
        legend.title = ggplot2::element_text(family = ff),
        axis.text = ggplot2::element_text(family = ff),
        axis.title = ggplot2::element_text(family = ff),
        strip.text = ggplot2::element_text(family = ff)
      )
    }
    if (!is.null(p$plot)) p$plot <- .force_tnr(p$plot)
    if (!is.null(p$table)) p$table <- .force_tnr(p$table)
    if (!is.null(p$cumevents)) p$cumevents <- .force_tnr(p$cumevents)
    if (!is.null(p$cumcensor)) p$cumcensor <- .force_tnr(p$cumcensor)
    # 主文 KM：上下图共用同一 x 轴 limits/breaks，避免 risk table 错位
    if (!for_combined && length(km_xlim) >= 2L && all(is.finite(km_xlim))) {
      br <- km_break
      if (!is.finite(br) || br <= 0) br <- max(diff(km_xlim) / 4, 1)
      breaks <- seq(km_xlim[1L], km_xlim[2L], by = br)
      sx <- ggplot2::scale_x_continuous(
        limits = km_xlim, breaks = breaks, expand = c(0.02, 0)
      )
      if (inherits(p$plot, "ggplot")) {
        p$plot <- p$plot + sx +
          ggplot2::theme(plot.margin = ggplot2::margin(6, 14, 2, 10))
      }
      if (inherits(p$table, "ggplot")) {
        p$table <- p$table + sx +
          ggplot2::theme(
            plot.margin = ggplot2::margin(0, 14, 6, 10),
            axis.title.x = ggplot2::element_blank()
          )
      }
    }
    if (exists("is_pub_profile", mode = "function") &&
        is_pub_profile(config, "mimic_inc_prog_sle_aki") &&
        exists("pub_figure_profile_apply_ggplot", mode = "function")) {
      if (inherits(p$plot, "ggplot")) {
        p$plot <- pub_figure_profile_apply_ggplot(p$plot, config)
      }
      if (inherits(p$table, "ggplot")) {
        p$table <- pub_figure_profile_apply_ggplot(p$table, config)
      }
    }
    p
  }

  list(
    build = build_plot,
    risk_table = risk_tbl,
    fallback = fallback
  )
}

.kms02_save_single_km <- function(build_fn, risk_tbl, fallback, out_path, w, h,
                                   family = "Times New Roman") {
  last_err <- NULL
  for (spec in list(
    list(risk = risk_tbl, pval = TRUE),
    if (fallback) list(risk = risk_tbl, pval = FALSE) else NULL,
    if (fallback) list(risk = FALSE, pval = TRUE) else NULL
  )) {
    if (is.null(spec)) next
    ok <- tryCatch({
      .kms02_write_pdf_atomic(
        build_fn(spec$risk, spec$pval), out_path, w, h, family = family
      )
      fi <- file.info(out_path)
      !is.na(fi$size) && fi$size >= 200L
    }, error = function(e) {
      last_err <<- conditionMessage(e)
      FALSE
    })
    if (isTRUE(ok)) return(invisible(out_path))
  }
  ok_gg <- tryCatch({
    p <- NULL
    for (spec in list(
      list(risk = risk_tbl, pval = TRUE),
      list(risk = risk_tbl, pval = FALSE),
      list(risk = FALSE, pval = FALSE)
    )) {
      p <- tryCatch(build_fn(spec$risk, spec$pval), error = function(e) NULL)
      if (!is.null(p)) break
    }
    if (is.null(p)) stop("ggsurvplot 构建失败")
    comb <- tryCatch(
      survminer::arrange_ggsurvplot(p, print = FALSE),
      error = function(e) if (!is.null(p$plot)) p$plot else NULL
    )
    if (is.null(comb)) stop("arrange_ggsurvplot 失败")
    if (file.exists(out_path)) unlink(out_path, force = TRUE)
    ggplot2::ggsave(
      out_path, plot = comb, width = w, height = h,
      device = grDevices::cairo_pdf, family = family
    )
    fi <- file.info(out_path)
    !is.na(fi$size) && fi$size >= 200L
  }, error = function(e) {
    last_err <<- conditionMessage(e)
    FALSE
  })
  if (isTRUE(ok_gg)) return(invisible(out_path))
  stop("km_strata PDF 保存失败: ", last_err %||% "unknown", call. = FALSE)
}

block_km_strata <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(cli)
    library(dplyr)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$km_strata %||% list()
  km_cfg <- cfg$km %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.kms02_should_pause(bl_cfg, "pause_on_no_figures", TRUE)) {
      .kms02_pause(ctx, "无分析数据。", "请先运行 imputation / data_clean。", NULL)
    }
    stop("km_strata: 无分析数据。")
  }
  # 若分层变量含 Subphenotype，从 df_final 合并
  df_lca <- ctx$results$df_final
  if (!is.null(df_lca) && is.data.frame(df_lca) && "Subphenotype" %in% names(df_lca)) {
    extra <- setdiff(names(df_lca), names(data))
    if (length(extra) > 0L) {
      rn_data <- rownames(data); rn_lca <- rownames(df_lca)
      if (!is.null(rn_data) && !is.null(rn_lca) && length(intersect(rn_data, rn_lca)) > 0L) {
        data <- merge(data, df_lca[, extra, drop = FALSE], by = "row.names", all.x = TRUE)
        rownames(data) <- data$Row.names; data$Row.names <- NULL
      } else if (nrow(df_lca) == nrow(data)) {
        data <- cbind(data, df_lca[, extra, drop = FALSE])
      }
    }
  }

  surv_cfg    <- cfg$survival %||% list()
  time_var    <- bl_cfg$time_var  %||% surv_cfg$time_var %||%
    stop("km_strata$time_var 未配置（且 survival$time_var 亦缺失）。")
  event_var   <- bl_cfg$event_var %||% surv_cfg$event_var %||%
    stop("km_strata$event_var 未配置（且 survival$event_var 亦缺失）。")
  event_val   <- bl_cfg$event_value %||% surv_cfg$event_value %||% 1
  time_div    <- as.numeric(bl_cfg$time_divisor %||% surv_cfg$time_divisor %||% 1)
  id_col      <- bl_cfg$id_column %||% cfg$data$id_column %||% NULL

  strata_defs <- bl_cfg$strata_defs %||% list()
  if (!is.list(strata_defs)) strata_defs <- list()

  strata_vars <- .kms02_resolve_strata_vars(bl_cfg, ctx)
  plot_vars <- strata_vars
  if (!length(plot_vars)) {
    stop("km_strata: strata_vars 为空（检查 strata_vars / strata_vars_by_branch 与 ctx$results$cox_branch）。")
  }
  branch <- as.character(ctx$results$cox_branch %||% "")[1L]
  if (nzchar(branch)) {
    cli::cli_alert_info("km_strata: cox_branch={branch} → 出图变量: {paste(plot_vars, collapse = ', ')}")
  }

  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("km_strata: time_var / event_var 不在数据中。")
  }

  dat <- data.frame(data, stringsAsFactors = FALSE, check.names = FALSE)
  dat[[event_var]] <- as.numeric(.kms02_coerce_event_01(dat[[event_var]], cfg, event_var))
  if (!any(dat[[event_var]] == 1L, na.rm = TRUE)) {
    stop("km_strata: 事件列转换后无 event=1，请检查 analysis_group / reference_group。")
  }

  index_var <- .kms02_index_var_from_ctx(ctx, cfg, plot_vars[1L])

  def_cols <- intersect(names(strata_defs), plot_vars)
  for (out_col in def_cols) {
    # 已有 cox 写入的 Q1–Q4 / T1–T3 列时不要用 cut_quantile 覆盖（否则与 Table 2 N 不一致）
    if (out_col %in% names(dat) && is.factor(dat[[out_col]])) {
      lv <- as.character(levels(dat[[out_col]]))
      if (length(lv) >= 2L && all(lv %in% c("Q1", "Q2", "Q3", "Q4", "T1", "T2", "T3"))) {
        next
      }
    }
    fac <- .kms02_apply_strata_def(dat, out_col, strata_defs[[out_col]])
    if (!is.null(fac)) {
      levels(fac) <- .kms02_sanitize_legend(levels(fac))
      dat[[out_col]] <- fac
    }
  }

  derived_cols <- unique(c(
    if (!is.null(id_col) && id_col %in% names(dat)) id_col else character(0),
    plot_vars,
    time_var, event_var
  ))
  derived_cols <- intersect(derived_cols, names(dat))
  ctx$data$km_strata_derived <- dat[, derived_cols, drop = FALSE]
  ctx$results$km_strata_vars <- plot_vars

  palette <- bl_cfg$palette %||% block_default_palette(5L, cfg)
  font_family <- bl_cfg$font_family %||% cfg$plot$font_family %||% "Times New Roman"
  if (exists("resolve_plot_font_family", mode = "function") &&
      isTRUE(capabilities("cairo"))) {
    # cairo 直接用系统 Times New Roman；不回退到 Helvetica/sans
    font_family <- as.character(font_family)[1L]
  } else if (exists("plot_font_from_config", mode = "function")) {
    font_family <- plot_font_from_config(cfg)
  }
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  plot_w <- bl_cfg$plot_width  %||% 10
  plot_h <- bl_cfg$plot_height %||% 8.5

  ev_col <- ".__km_event__"
  plot_col <- ".__km_plot_group__"
  time_expr <- if (time_div != 1) {
    paste0(time_var, "/", time_div)
  } else {
    time_var
  }

  n_ok <- 0L
  plot_list <- list()
  logrank_by_strata <- list()

  for (strata_col in plot_vars) {
    fac <- .kms02_prepare_strata_column(dat, strata_col, strata_defs, ctx, index_var)
    if (is.null(fac)) next

    rt_plot <- dat
    rt_plot[[plot_col]] <- fac
    rt_plot[[ev_col]] <- dat[[event_var]]
    if (any(is.na(rt_plot[[plot_col]]))) {
      rt_plot <- rt_plot[!is.na(rt_plot[[plot_col]]), , drop = FALSE]
    }
    if (nrow(rt_plot) < 2L || dplyr::n_distinct(rt_plot[[plot_col]]) < 2L) {
      cli::cli_alert_warning("{strata_col}: 有效分层不足，跳过")
      next
    }

    display_name <- gsub("_", " ", strata_col, fixed = TRUE)
    formula <- stats::as.formula(paste0(
      "Surv(", time_expr, ", ", ev_col, ") ~ ", plot_col
    ))

    pinfo <- .kms02_plot_one_strata(
      rt_plot, plot_col, display_name, formula, bl_cfg, palette, font_family, km_cfg,
      time_col = time_var, time_div = time_div,
      for_combined = FALSE, config = cfg
    )
    out_file <- .kms02_resolve_single_km_path(ctx, fig_dir, strata_col, bl_cfg, cfg)
    tryCatch({
      .kms02_save_single_km(
        pinfo$build, pinfo$risk_table, pinfo$fallback,
        out_file, plot_w, plot_h, family = font_family
      )
      n_ok <- n_ok + 1L
      logrank_by_strata[[strata_col]] <- .kms02_logrank_p_numeric(formula, rt_plot)
      cli::cli_alert_success("KM 已保存: {.file {basename(out_file)}}")
      if (exists("pub_mirror_saved", mode = "function")) {
        pub_mirror_saved(ctx, out_file)
      }
    }, error = function(e) {
      cli::cli_alert_warning("{strata_col} KM 保存失败: {e$message}")
    })

    if (isTRUE(bl_cfg$export_combined %||% TRUE)) {
      pinfo_c <- .kms02_plot_one_strata(
        rt_plot, plot_col, display_name, formula, bl_cfg, palette, font_family, km_cfg,
        time_col = time_var, time_div = time_div,
        for_combined = TRUE, config = cfg
      )
      plot_list[[strata_col]] <- pinfo_c$build(FALSE, TRUE)
    }
  }

  if (isTRUE(bl_cfg$export_combined %||% TRUE) && length(plot_list) > 0L) {
    comb_kind <- as.character(bl_cfg$combined_figure_kind %||% "main_figure")[1L]
    if (!nzchar(comb_kind)) comb_kind <- "main_figure"
    comb_name <- bl_cfg$combined_filename %||%
      pub_figure_file(ctx, comb_kind, "Combined KM Plots")
    comb_path <- file.path(fig_dir, comb_name)
    ncol <- as.integer(bl_cfg$combined_ncol %||% 3L)
    nrow <- as.integer(bl_cfg$combined_nrow %||% ceiling(length(plot_list) / ncol))
    tryCatch({
      res <- survminer::arrange_ggsurvplots(
        plot_list, print = FALSE, ncol = ncol, nrow = nrow
      )
      .kms02_write_pdf_atomic(
        res, comb_path,
        bl_cfg$combined_width  %||% 18,
        bl_cfg$combined_height %||% 23
      )
      cli::cli_alert_success("合并 KM 已保存: {.file {basename(comb_path)}}")
      if (exists("pub_mirror_saved", mode = "function")) {
        pub_mirror_saved(ctx, comb_path)
      }
    }, error = function(e) {
      cli::cli_alert_warning("合并 KM 失败: {e$message}")
    })
  }

  if (n_ok == 0L && .kms02_should_pause(bl_cfg, "pause_on_no_figures", TRUE)) {
    .kms02_pause(
      ctx, "km_strata 无有效 KM 图产出。",
      "检查 strata_vars / strata_defs、time/event 列及分层水平数。", NULL
    )
  }

  ctx$results$km_strata <- list(
    n_plots = n_ok,
    strata_vars = plot_vars,
    derived_columns = setdiff(derived_cols, c(time_var, event_var, id_col)),
    logrank_by_strata = logrank_by_strata
  )
  cli::cli_alert_success(
    "km_strata 完成: {n_ok} 张单图；ctx$data$km_strata_derived 已写入（{ncol(ctx$data$km_strata_derived)} 列）。"
  )
  ctx
}

register_block(
  "km_strata", block_km_strata,
  "多水平分层 KM：strata_defs 派生分组 → 批量出图 → km_strata_derived"
)
