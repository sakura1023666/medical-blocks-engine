###############################################################################
#  trajectory_piecewise_cox — 潜类别自动最优 cutpoint 分段 Cox（class vs ref_class HR）
#
#  v2：替换 v1 的空模型实现（原 coxph(Surv(t,e)~1) 不含 class 项，算不出组间 HR）。
#  算法参考文献 Table 3 风格：逐天扫描 cut（默认 1..max_followup-1），两段模型
#  对数似然之和最大者为最优 cutpoint；两段各拟合 coxph(Surv~class)（class 相对
#  ref_class），输出 "cut 前/cut 后" 两列 HR (95% CI)。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#                 需含 trajectory_class（或 trajectory_class_{Index}，由 trajectory_jlcm
#                 的 assign_class_ng 回写）
#
#  trajectory_piecewise_cox = list(
#    index_vars             = NULL,     # NULL → 用裸列 trajectory_class；否则遍历 trajectory_class_{Index}
#    class_col              = NULL,     # 显式指定类别列名，优先级高于 index_vars 推导
#    ref_class              = NULL,     # NULL → 自动取样本量最大的类别作为参照
#    survival_time_var      = NULL,     # NULL → config$survival$time_var
#    survival_event_var     = NULL,     # NULL → config$survival$event_var
#    max_followup           = 28,
#    auto_scan              = TRUE,
#    cut_days               = NULL,     # NULL → 1:(max_followup-1)
#    landmark_times         = NULL,     # auto_scan=FALSE 时使用的固定 cut（取第一个）
#    min_events_each_piece  = 1L,
#    min_n_after            = 1L,
#    pause_enable           = TRUE,
#    pause_on_no_output     = TRUE
#  ),
#
#  register_block: "trajectory_piecewise_cox"
#  写: ctx$results$trajectory_piecewise_cox（含 cut_best 与 HR 表）
#  落盘: Tables/Table_Piecewise_Cox_{Index}.csv / .xlsx
###############################################################################

.tpc01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.tpc01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "trajectory_piecewise_cox", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.tpc01_normalize_class <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  x_num <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(x))))
  lv <- sort(unique(stats::na.omit(x_num)))
  factor(x_num, levels = lv)
}

# 构造某一段（cut 前 / cut 后）的分段生存数据
.tpc01_make_piece_data <- function(dd, cut, which_piece, end_day, ref_class) {
  dd$class <- stats::relevel(dd$class, ref = ref_class)
  if (which_piece == 1L) {
    time1  <- pmin(dd$time, cut)
    event1 <- as.integer(dd$event == 1 & dd$time <= cut)
    dd$t_piece <- time1; dd$e_piece <- event1
    dd
  } else {
    out <- dd[dd$time > cut, , drop = FALSE]
    if (nrow(out) == 0) return(out)
    out$t_piece <- pmin(out$time, end_day) - cut
    out$e_piece <- as.integer(out$event == 1 & out$time <= end_day)
    out
  }
}

.tpc01_fit_piece <- function(dat_piece) {
  if (is.null(dat_piece) || nrow(dat_piece) == 0) return(NULL)
  if (sum(dat_piece$e_piece == 1, na.rm = TRUE) == 0) return(NULL)
  if (nlevels(droplevels(dat_piece$class)) < 2) return(NULL)
  fit <- tryCatch(
    survival::coxph(survival::Surv(t_piece, e_piece) ~ class, data = dat_piece, ties = "efron"),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  if (any(!is.finite(stats::coef(fit))) || anyNA(stats::coef(fit))) return(NULL)
  fit
}

.tpc01_fit_piece_hr_table <- function(fit) {
  if (is.null(fit)) return(NULL)
  ci <- as.data.frame(summary(fit)$conf.int)
  ci$term <- rownames(ci)
  ci$class_num <- suppressWarnings(as.integer(gsub("\\D+", "", ci$term)))
  ci <- ci[!is.na(ci$class_num), , drop = FALSE]
  if (!nrow(ci)) return(NULL)
  data.frame(
    class = as.character(ci$class_num),
    HR_CI = sprintf("%.2f (%.2f, %.2f)", ci[["exp(coef)"]], ci[["lower .95"]], ci[["upper .95"]]),
    stringsAsFactors = FALSE
  )
}

.tpc01_scan_best_cut <- function(dd, cut_days, end_day, ref_class,
                                  min_events_each_piece, min_n_after) {
  rows <- lapply(cut_days, function(cut) {
    d1 <- .tpc01_make_piece_data(dd, cut, 1L, end_day, ref_class)
    d2 <- .tpc01_make_piece_data(dd, cut, 2L, end_day, ref_class)
    ev1 <- if (nrow(d1)) sum(d1$e_piece == 1, na.rm = TRUE) else 0L
    ev2 <- if (nrow(d2)) sum(d2$e_piece == 1, na.rm = TRUE) else 0L
    n2  <- nrow(d2)
    stable <- (ev1 >= min_events_each_piece) && (ev2 >= min_events_each_piece) && (n2 >= min_n_after)
    ll <- NA_real_
    if (stable) {
      f1 <- .tpc01_fit_piece(d1)
      f2 <- .tpc01_fit_piece(d2)
      if (!is.null(f1) && !is.null(f2)) ll <- as.numeric(stats::logLik(f1) + stats::logLik(f2))
    }
    data.frame(cut = cut, n_after = n2, ev1 = ev1, ev2 = ev2, stable = stable, loglik = ll)
  })
  do.call(rbind, rows)
}

# 与 run_FigS2_APRI.R 一致：cut-off 搜索的偏似然曲线（best cut 处竖线）
.tpc01_cut_search_plot <- function(scan_res, cut_best, title, max_followup, font_family = "sans") {
  suppressPackageStartupMessages(library(ggplot2))
  df <- scan_res[!is.na(scan_res$loglik), , drop = FALSE]
  if (!nrow(df)) return(NULL)
  x_lo <- max(1, min(df$cut, na.rm = TRUE))
  ggplot2::ggplot(df, ggplot2::aes(x = cut, y = loglik)) +
    ggplot2::geom_line(color = "grey30", linewidth = 0.6) +
    ggplot2::geom_point(color = "#D55E00", size = 2) +
    ggplot2::geom_vline(xintercept = cut_best, linewidth = 0.6) +
    ggplot2::scale_x_continuous(breaks = seq(x_lo, max_followup, by = 2), limits = c(x_lo, max_followup)) +
    ggplot2::labs(title = title, x = "Days after ICU entry", y = "Partial log-Likelihood") +
    ggplot2::theme_bw(base_size = 14) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", hjust = 0.5),
                   text = ggplot2::element_text(family = font_family))
}

.tpc01_run_one <- function(ctx, data, bl_cfg, Index, class_col,
                            time_var, event_var, max_followup, ref_class_cfg) {
  if (!class_col %in% names(data)) {
    cli::cli_alert_warning("trajectory_piecewise_cox: 缺少类别列 {class_col}，跳过 {Index %||% ''}")
    return(NULL)
  }
  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("trajectory_piecewise_cox: 缺少生存列 (", time_var, "/", event_var, ")", call. = FALSE)
  }

  # 与 run_FigS2_APRI.R 一致：ng==2 时交换 Class1/2（Class2=多数/低风险类，默认作参照）
  class_num0 <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(data[[class_col]]))))
  class_num  <- if (exists("trajectory_apply_class_swap", mode = "function"))
    trajectory_apply_class_swap(class_num0, trajectory_class_swap_map(class_num0)) else class_num0
  dd <- data.frame(
    time  = suppressWarnings(as.numeric(as.character(data[[time_var]]))),
    event = if (exists("trajectory_coerce_event01", mode = "function")) {
      trajectory_coerce_event01(data[[event_var]])
    } else {
      suppressWarnings(as.integer(as.character(data[[event_var]])))
    },
    class = factor(class_num, levels = sort(unique(stats::na.omit(class_num))))
  )
  dd <- dd[is.finite(dd$time) & !is.na(dd$event) & !is.na(dd$class), , drop = FALSE]
  dd$time <- pmin(dd$time, max_followup)
  dd <- dd[dd$time > 0, , drop = FALSE]

  if (!nrow(dd) || nlevels(droplevels(dd$class)) < 2) {
    cli::cli_alert_warning("trajectory_piecewise_cox: {Index %||% ''} 有效数据不足或类别数<2，跳过")
    return(NULL)
  }

  ref_class <- as.character(ref_class_cfg %||% names(sort(table(dd$class), decreasing = TRUE))[1])
  if (!ref_class %in% levels(dd$class)) ref_class <- levels(dd$class)[1]

  auto_scan <- if (is.null(bl_cfg$auto_scan)) TRUE else isTRUE(bl_cfg$auto_scan)
  min_ev    <- as.integer(bl_cfg$min_events_each_piece %||% 1L)
  min_n     <- as.integer(bl_cfg$min_n_after %||% 1L)

  if (auto_scan) {
    cut_days <- as.integer(bl_cfg$cut_days %||% seq_len(max_followup - 1L))
    scan_res <- .tpc01_scan_best_cut(dd, cut_days, max_followup, ref_class, min_ev, min_n)
    valid <- scan_res[!is.na(scan_res$loglik), , drop = FALSE]
    if (!nrow(valid)) {
      cli::cli_alert_warning("trajectory_piecewise_cox: {Index %||% ''} 扫描未找到稳定 cutpoint")
      return(list(scan = scan_res, cut = NA_integer_, table = NULL, ref_class = ref_class))
    }
    cut_best <- valid$cut[which.max(valid$loglik)]
  } else {
    lmk <- as.numeric(bl_cfg$landmark_times %||% c(round(max_followup / 2)))
    cut_best <- as.integer(lmk[1])
    scan_res <- data.frame(cut = cut_best, n_after = NA, ev1 = NA, ev2 = NA, stable = NA, loglik = NA)
  }

  d1 <- .tpc01_make_piece_data(dd, cut_best, 1L, max_followup, ref_class)
  d2 <- .tpc01_make_piece_data(dd, cut_best, 2L, max_followup, ref_class)
  f1 <- .tpc01_fit_piece(d1)
  f2 <- .tpc01_fit_piece(d2)
  t1 <- .tpc01_fit_piece_hr_table(f1)
  t2 <- .tpc01_fit_piece_hr_table(f2)

  left_col  <- paste0("(0,", cut_best, "]")
  right_col <- paste0("(", cut_best, ",", max_followup, "]")

  comp_classes <- setdiff(levels(dd$class), ref_class)
  tab <- data.frame(class = comp_classes, stringsAsFactors = FALSE)
  tab[[left_col]]  <- if (!is.null(t1)) t1$HR_CI[match(tab$class, t1$class)] else NA_character_
  tab[[right_col]] <- if (!is.null(t2)) t2$HR_CI[match(tab$class, t2$class)] else NA_character_
  tab$class_label <- paste0("Class ", tab$class, " (ref = Class ", ref_class, ")")
  db_label <- bl_cfg$database_label %||% NULL
  if (is.null(db_label)) {
    dbn <- tolower(trimws(as.character(ctx$config$project$database %||% "")))
    db_label <- if (grepl("mimic", dbn)) "MIMIC-IV" else if (grepl("eicu", dbn)) "eICU-CRD" else dbn
  }
  tab$dataset <- db_label
  tab$cut <- cut_best
  tab$ref_class <- ref_class
  if (!is.null(Index)) tab <- cbind(Index = Index, tab)
  tab <- tab[, c(setdiff(names(tab), c(left_col, right_col)), left_col, right_col)]

  list(scan = scan_res, cut = cut_best, table = tab, ref_class = ref_class, database = db_label)
}

block_trajectory_piecewise_cox <- function(ctx, ...) {
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)
  paper_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_paper_tables.R")
  if (file.exists(paper_util)) source(paper_util, local = FALSE)
  bl <- ctx$config$trajectory_piecewise_cox %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

  if (is.null(data)) stop("trajectory_piecewise_cox: 无数据", call. = FALSE)

  time_var  <- bl$survival_time_var  %||% ctx$config$survival$time_var  %||% "futime"
  event_var <- bl$survival_event_var %||% ctx$config$survival$event_var %||% "Mortality_28d"
  max_followup <- as.numeric(bl$max_followup %||% 28)
  ref_class_cfg <- bl$ref_class %||% NULL

  index_vars <- bl$index_vars %||% NULL
  explicit_col <- bl$class_col %||% NULL

  results_all <- list()
  tables_all  <- list()

  if (!is.null(explicit_col)) {
    res <- .tpc01_run_one(ctx, data, bl, NULL, explicit_col, time_var, event_var, max_followup, ref_class_cfg)
    if (!is.null(res)) { results_all[["_"]] <- res; if (!is.null(res$table)) tables_all[["_"]] <- res$table }
  } else if (!is.null(index_vars) && length(index_vars)) {
    for (Index in index_vars) {
      col <- paste0("trajectory_class_", Index)
      if (!col %in% names(data)) col <- "trajectory_class"
      res <- .tpc01_run_one(ctx, data, bl, Index, col, time_var, event_var, max_followup, ref_class_cfg)
      if (!is.null(res)) { results_all[[Index]] <- res; if (!is.null(res$table)) tables_all[[Index]] <- res$table }
    }
  } else {
    res <- .tpc01_run_one(ctx, data, bl, NULL, "trajectory_class", time_var, event_var, max_followup, ref_class_cfg)
    if (!is.null(res)) { results_all[["_"]] <- res; if (!is.null(res$table)) tables_all[["_"]] <- res$table }
  }

  if (!length(tables_all)) {
    tab <- data.frame(note = "no trajectory_class available or no stable cutpoint found")
    utils::write.csv(tab, file.path(out_tab, "Table_Piecewise_Cox_By_Class.csv"), row.names = FALSE)
    ctx$results$trajectory_piecewise_cox <- list(scan = NULL, tables = list(), note = "empty")
    if (.tpc01_should_pause(bl, "pause_on_no_output", TRUE)) {
      .tpc01_pause(
        ctx,
        "trajectory_piecewise_cox: 未产出任何分段 Cox 结果。",
        "请确认 trajectory_jlcm 已配置 assign_class_ng 回写 trajectory_class，且各类别样本量/事件数足够扫描 cutpoint。",
        NULL
      )
    }
    cli::cli_alert_warning("trajectory_piecewise_cox: 无有效输出")
    return(ctx)
  }

  combined <- do.call(rbind, lapply(tables_all, function(x) x))
  rownames(combined) <- NULL
  db_slug <- tolower(trimws(as.character(ctx$config$project$database %||% "db")))
  out_csv <- file.path(out_tab, "Table_Piecewise_Cox_By_Class.csv")
  utils::write.csv(combined, out_csv, row.names = FALSE)

  cut_best <- results_all[[names(results_all)[1]]]$cut %||% NA
  if (!is.na(cut_best)) {
    scan_nm <- results_all[[names(results_all)[1]]]$scan
    if (!is.null(scan_nm)) {
      utils::write.csv(
        scan_nm,
        file.path(out_tab, paste0("Table_Piecewise_Cox_CutScan_", db_slug, ".csv")),
        row.names = FALSE
      )
    }
  }

  ix_name <- if (length(index_vars)) as.character(index_vars[1L]) else
    as.character(ctx$config$survival$index_var %||% "Index")[1L]
  db_lab <- ctx$config$project$database %||% toupper(db_slug)
  fp_t3 <- file.path(
    out_tab,
    paste0("Table 3-", db_lab, ". Time-dependent HR for trajectory classes.xlsx")
  )
  paper_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_paper_tables.R")
  if (file.exists(paper_util)) source(paper_util, local = FALSE)
  t3_title <- paste0("Table 3. Time-dependent HR for trajectory classes of ", ix_name)
  if (exists("trajectory_export_table3_sci", mode = "function") && !is.na(cut_best)) {
    trajectory_export_table3_sci(ctx, combined, cut_best, fp_t3, t3_title, end_day = max_followup)
    trajectory_export_table3_sci(
      ctx, combined, cut_best,
      file.path(out_tab, paste0("Table3_", ix_name, "_", db_slug, ".xlsx")),
      t3_title, end_day = max_followup
    )
    cli::cli_alert_success("Table 3 已输出: {.file {basename(fp_t3)}}")
  } else if (exists("export_sci_table", mode = "function")) {
    export_sci_table(
      combined, file.path(out_tab, "Table_Piecewise_Cox_By_Class.xlsx"),
      title = "Table 3. Time-dependent HR for trajectory classes (auto cutpoint)",
      sheet = "Table3"
    )
  }

  # 与 run_FigS2_APRI.R 一致：为每组输出 cut-off 搜索偏似然曲线图
  font_family <- ctx$config$plot$font_family %||% ctx$config$figure$font_family %||% "sans"
  if (exists("save_figure", mode = "function")) {
    for (nm in names(results_all)) {
      r <- results_all[[nm]]
      if (is.null(r$scan) || is.na(r$cut)) next
      ttl <- if (identical(nm, "_")) "Piecewise Cox cut-off search" else paste0(nm, " piecewise Cox cut-off search")
      p_ll <- tryCatch(.tpc01_cut_search_plot(r$scan, r$cut, ttl, max_followup, font_family),
                       error = function(e) NULL)
      if (is.null(p_ll)) next
      suffix <- if (identical(nm, "_")) "" else paste0("_", nm)
      fn <- paste0("Figure_Piecewise_Cox_CutSearch", suffix, ".pdf")
      ctx <- save_figure(ctx, fn, (function(pp) function() print(pp))(p_ll), width = 7, height = 5)
    }
  }

  ctx$results$trajectory_piecewise_cox <- list(
    scans  = lapply(results_all, function(x) x$scan),
    cuts   = lapply(results_all, function(x) x$cut),
    tables = tables_all,
    combined_table = combined
  )
  cli::cli_alert_success(
    "trajectory_piecewise_cox 完成：{length(tables_all)} 组结果，最优 cutpoint = {paste(unlist(lapply(results_all, function(x) x$cut)), collapse=', ')}"
  )
  ctx
}

register_block(
  "trajectory_piecewise_cox", block_trajectory_piecewise_cox,
  "潜类别自动最优 cutpoint 分段 Cox：两段 class-vs-ref HR (95% CI) 表"
)
