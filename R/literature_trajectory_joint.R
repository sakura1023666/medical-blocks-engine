###############################################################################
# literature_trajectory_joint.R — 双指标联合轨迹发病（GBMTM joint trajectory）
#
# 对标文献：Liu et al. Cardiovasc Diabetol 2026;25:207（ELSA TyG×肥胖联合轨迹）
# 统计内核：R/gbmtm_core.R（Nagin 多轨迹混合模型，EM 全信息，任意缺失波次局部独立）
#
# 设计口径（与 bespoke ELSA 脚本一致，已回写引擎）：
#   1) 轨迹定类在「master 宽表（含真缺失）」上拟合一次，每人得 class 标签；
#      EM 局部独立自动处理缺失波次，暴露本身不插补。
#   2) 协变量推断走引擎 MICE（config$imputation, m>=5）+ Rubin（mi_coxph）。
#      class 列作为操作层固定列，mi_complete_aligned 的 extra 机制每套自动带回。
#   3) 序贯 Cox Model1-4（文献四段式），结局可多组件；分位级联不适用
#      （暴露是 latent class 而非 Q1-Q4），用 class 哑变量，参照组 = 最低风险 T1。
#
# 入口函数：
#   tj_expand_index_waves()     单指标各波列 → 标准 <IDX>_w<k> 命名
#   tj_to_long()                宽表多指标多波 → (id, t, ind, y)
#   tj_rubin_vec()              标准 Rubin（向量 β / 对角 U），退化 Wald 处理
#   tj_class_dummies()          class 标签 → 参考 T1 的因子
#   tj_model_covariates()       从 config$joint_trajectory$model_sets 取协变量集
###############################################################################

#' 把宽表中各波指标列展开为 gbmtm 长表 (id, t, ind, y)
#' @param df 宽表数据框
#' @param inds 指标列表：list(name="tyg", cols=c("tyg_w2","tyg_w4","tyg_w6"), t=c(2,4,6))
#'             或简写：cols 已是 <name>_w<k>，自动按 t 排序
#' @param id_col ID 列名
tj_to_long <- function(df, inds, id_col = "id") {
  rows <- list()
  for (spec in inds) {
    nm <- spec$name
    cols <- spec$cols
    tt <- spec$t
    if (is.null(tt)) {
      tt <- vapply(cols, function(cn) {
        mm <- regmatches(cn, regexpr("w?[0-9]+$", cn))
        as.numeric(gsub("[^0-9]", "", mm))
      }, numeric(1))
    }
    ord <- order(tt)
    cols <- cols[ord]; tt <- tt[ord]
    for (j in seq_along(cols)) {
      if (!cols[j] %in% names(df)) {
        stop(sprintf("tj_to_long: 列 '%s' 不在数据中（指标 %s）", cols[j], nm), call. = FALSE)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        id = as.character(df[[id_col]]),
        t = as.numeric(tt[j]),
        ind = nm,
        y = as.numeric(df[[cols[j]]]),
        stringsAsFactors = FALSE
      )
    }
  }
  d <- do.call(rbind, rows)
  d[!is.na(d$y), , drop = FALSE]
}

#' 标准 Rubin 合并：B = m×p 系数矩阵，U = m×p 各套方差（对角元）
#' 类间方差为 0（协变量全完整）→ 退化为 Wald 正态；返回 data.frame(est,se,lo,hi,p)
tj_rubin_vec <- function(B, U) {
  B <- as.matrix(B); U <- as.matrix(U)
  m <- nrow(B)
  if (m < 1L) return(NULL)
  if (m == 1L) {
    est <- as.numeric(B[1, , drop = TRUE]); se <- sqrt(as.numeric(U[1, , drop = TRUE]))
    out <- data.frame(est = est, se = se, lo = est - 1.96 * se, hi = est + 1.96 * se,
                      p = 2 * stats::pt(abs(est / pmax(se, 1e-300)), df = Inf, lower.tail = FALSE))
    rownames(out) <- colnames(B)
    return(out)
  }
  Qbar <- colMeans(B); Ubar <- colMeans(U); Bv <- apply(B, 2, stats::var)
  Bv[!is.finite(Bv)] <- 0
  T <- Ubar + (1 + 1 / m) * Bv
  dfold <- ifelse(Bv > 0, (m - 1) * (1 + Ubar / ((1 + 1 / m) * pmax(Bv, 1e-300))^2), 1e6)
  r <- (1 + 1 / m) * pmax(Bv, 1e-300) / T
  dfstar <- (dfold * r) / (r + (dfold + 3) / (dfold + 1))
  dfstar[!is.finite(dfstar) | r < 1e-10] <- Inf   # 无类间方差 → Wald 正态
  se <- sqrt(T)
  p <- 2 * stats::pt(abs(Qbar / pmax(se, 1e-300)), df = pmax(dfstar, 1), lower.tail = FALSE)
  out <- data.frame(est = Qbar, se = se, lo = Qbar - 1.96 * se, hi = Qbar + 1.96 * se, p = p)
  rownames(out) <- colnames(B)
  out
}

#' 区间删失随访窗（cloglog 敏感性用）：由"末次无事件访视列"重建 (L, R]
#' @param df  宽表（含访视月列，相对基线，0=基线）
#' @param visit_cols 访视时间列名向量（如 c("tvisit_w3","tvisit_w5")）
#' @param event 0/1 主事件向量；time 事件/删失时间（月）
#' @return data.frame L, R（type="interval2" 语义：event 行 R 有限，删失行 R=Inf）
tj_interval_windows <- function(df, visit_cols, event, time) {
  event <- as.integer(event); event[is.na(event)] <- 0L
  time  <- as.numeric(time)
  vs <- as.matrix(df[, visit_cols, drop = FALSE])
  vs <- apply(vs, 2, as.numeric)
  L <- numeric(length(event)); R <- numeric(length(event))
  for (i in seq_along(event)) {
    wv <- c(0, vs[i, !is.na(vs[i, ])])
    wv <- sort(unique(wv[wv >= 0]))
    ti <- time[i]
    if (event[i] == 1L && !is.na(ti) && ti > 0) {
      j <- which(wv >= ti)
      if (!length(j)) { L[i] <- ti; R[i] <- ti }        # 末次访视后事件：退化为点
      else {
        jj <- j[1]
        L[i] <- if (jj > 1) wv[jj - 1] else 0
        R[i] <- wv[jj]
        if (R[i] <= L[i]) { L[i] <- ti; R[i] <- ti }    # 与基线同窗：点事件
      }
    } else {
      # 删失（含无事件死亡/存活到底）：L=观测时间，R=Inf
      L[i] <- if (!is.na(ti) && ti > 0) ti else max(0, wv[length(wv)])
      R[i] <- Inf
    }
  }
  data.frame(L = L, R = R)
}

#' cloglog（Weibull PH 参数化）区间删失回归：survreg interval2 + dist=weibull
#' HR = exp(-coef/scale)（与 Cox PH 同向可比）。fit_hr 循环每套插补调用本函数。
tj_cloglog_fit <- function(d, fml_str) {
  f <- stats::as.formula(fml_str)
  fit <- tryCatch(suppressWarnings(survival::survreg(f, data = d, dist = "weibull")),
                  error = function(e) NULL)
  if (is.null(fit) || !length(fit$coef)) return(NULL)
  sc <- as.numeric(fit$scale)
  allcf <- stats::coef(fit)
  # survreg 系数名可能为 (Intercept)/Intercept + log(scale)；vcov 偶尔无 dimnames
  keep <- setdiff(names(allcf), c("(Intercept)", "Intercept", "log(scale)"))
  if (!length(keep)) return(NULL)
  Vfull <- stats::vcov(fit)
  if (is.null(dimnames(Vfull)) || !all(keep %in% rownames(Vfull)))
    dimnames(Vfull) <- list(names(allcf), names(allcf))
  V <- Vfull[keep, keep, drop = FALSE]
  cf <- allcf[keep]
  if (any(!is.finite(V))) return(NULL)
  list(est = -cf / sc, var = as.matrix(V) / sc^2)   # log-HR 尺度近似（delta，忽略 scale 方差）
}

#' class 整数标签 → 因子，参照组为升序风险最低类（T1）
#' @param lbl 字符标签向量（gbmtm_label 的 label 列，形如 T1/T2/...）
tj_class_factor <- function(lbl) {
  levs <- sort(unique(lbl))
  ref <- levs[1]
  factor(lbl, levels = levs)
}

#' 取文献四段式协变量集（config$joint_trajectory$model_sets）
#' 默认对齐 Liu 2026：M1 人口学 / M2 +生活方式 / M3 +共病 / M4 +药物+肺功能
tj_model_covariates <- function(bl) {
  ms <- bl$model_sets
  if (is.list(ms) && length(ms)) return(ms)
  list(
    model1 = bl$model1 %||% c("age", "sex", "race_white", "edu"),
    model2 = bl$model2 %||% c("age", "sex", "race_white", "edu", "smoke", "drink"),
    model3 = bl$model3 %||% c("age", "sex", "race_white", "edu", "smoke", "drink",
                              "hbp_d", "dm_d", "chol_d"),
    model4 = bl$model4 %||% c("age", "sex", "race_white", "edu", "smoke", "drink",
                              "hbp_d", "dm_d", "chol_d", "bpmed", "dmmed")
  )
}

#' 指标列名解析：把 config 指定的原始成分列按波展开，调用 00_index 公式重算指标
#' @param df 宽表
#' @param index_name 复合指标名（在 .idx_definitions 内）
#' @param waves 波次号向量
#' @param wave_suffix 默认 "_w"
#' @param root 引擎根（source 00_index 用）
#' @return 新增各波指标列 <index_name>_w<k> 的 data.frame；缺成分则返回 NULL
tj_calc_index_waves <- function(df, index_name, waves, wave_suffix = "_w", root = getwd()) {
  idx_path <- file.path(root, "Blocks/00_index/01block_index.R")
  if (file.exists(idx_path)) source(idx_path, local = FALSE)
  if (!exists("pipeline_index_definition_map", mode = "function")) {
    cli::cli_alert_warning("tj_calc_index_waves: 00_index 公式表不可用，按现有列名回退")
    return(df)
  }
  dmap <- pipeline_index_definition_map()
  expr <- dmap[[index_name]]
  if (is.null(expr)) {
    cli::cli_alert_danger("tj_calc_index_waves: '{index_name}' 不在复合指标定义表")
    return(NULL)
  }
  comp <- all.vars(stats::as.formula(paste0("~", expr)))
  for (w in waves) {
    suffixed <- paste0(comp, wave_suffix, w)
    miss <- setdiff(suffixed, names(df))
    if (length(miss)) {
      cli::cli_alert_danger("指标 {index_name} 波 {w} 缺成分列: {paste(miss, collapse=', ')}")
      next
    }
    env <- .tj_comp_env(df, comp, suffixed)
    val <- tryCatch(eval(parse(text = expr), envir = env),
                    error = function(e) NULL)
    if (is.null(val) || length(val) != nrow(df)) {
      cli::cli_alert_danger("指标 {index_name} 波 {w} 公式求值失败")
      next
    }
    df[[paste0(index_name, wave_suffix, w)]] <- as.numeric(val)
  }
  df
}

# 把公式裸成分名 comp 映射到本波已加后缀的成分列 suffixed（同序），返回求值环境
.tj_comp_env <- function(df, comp, suffixed) {
  stopifnot(length(comp) == length(suffixed))
  e <- new.env(parent = globalenv())
  for (i in seq_along(comp)) assign(comp[i], as.numeric(df[[suffixed[i]]]), envir = e)
  e
}

###############################################################################
# ---- 发表层 helper（Block 06 用）：Times 字体 / KM / 森林 / 轨迹面板 / 表 ----
###############################################################################

tj_pub_font <- function(config = NULL) {
  pref <- "Times New Roman"
  if (is.list(config)) {
    p1 <- config$pub_figures$font %||% config$pub$font %||% NULL
    if (!is.null(p1) && is.character(p1) && nzchar(p1)) pref <- p1
  } else if (is.character(config) && nzchar(config)) pref <- config
  if (exists("resolve_plot_font_family", mode = "function")) {
    fam <- tryCatch(resolve_plot_font_family(pref), error = function(e) NULL)
    if (is.character(fam) && nzchar(fam)) return(fam[1L])
  }
  "serif"
}

tj_theme <- function(fam = "serif", base = 11) {
  ggplot2::theme_classic(base_size = base, base_family = fam) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", family = fam),
                   legend.text = ggplot2::element_text(family = fam),
                   legend.title = ggplot2::element_blank())
}

#' 轨迹类别 × 结局 KM 曲线（survminer ggsurvplot 兼容旧版参数 + log-rank P）
tj_km_pdf <- function(df, gv, ev, tm, out_pdf, title, fam, time_unit_lab = "Follow-up (months)",
                      breaks = NULL) {
  suppressMessages(library(survival))
  d <- df[!is.na(df[[gv]]), , drop = FALSE]
  d$.ev <- as.integer(ev[match(rownames(d), rownames(df))])
  d$.tm <- as.numeric(tm[match(rownames(d), rownames(df))])
  d <- d[!is.na(d$.tm) & d$.tm > 0, , drop = FALSE]
  d[[gv]] <- factor(d[[gv]])
  if (nlevels(d[[gv]]) < 2) return(invisible(FALSE))
  # 预构造 formula 对象并用 bquote 内联进调用（勿直接 survfit(km_fml)）：
  # survfit 会在 sfit$call 保存未求值表达式；若 call 里只是变量名（symbol），
  # ggsurvplot 内部对 call$formula 再取 [[2]] 会报
  # "object of type 'symbol' is not subsettable"，被 tryCatch 吞掉后
  # 跌回无风险表回退分支（旧 KM 图 P0：缺 Number at risk + 图上 NA）。
  km_fml <- stats::as.formula(paste0("survival::Surv(.tm, .ev) ~ ", gv))
  sfit <- eval(bquote(survival::survfit(.(km_fml), data = d)))
  lr <- survival::survdiff(km_fml, data = d)
  pval <- stats::pchisq(lr$chisq, df = length(lr$n) - 1, lower.tail = FALSE)
  cols <- scales::hue_pal()(nlevels(d[[gv]]))
  # 展示名：图例与风险表行名去掉 "grp_NLR=" 编程前缀（禁下划线、禁列名上图）
  .sfit_strata_lab <- function(sf) {
    nm <- names(sf$strata)
    if (is.null(nm) || !length(nm)) return(nm)
    cleaned <- sub("^[^=]*=", "", nm)
    if (exists("pipeline_display_label", mode = "function")) {
      cleaned <- tryCatch(pipeline_display_label(cleaned), error = function(e) cleaned)
    }
    cleaned
  }
  sl <- .sfit_strata_lab(sfit)
  if (!is.null(sl) && length(sl) == length(sfit$strata)) {
    names(sfit$strata) <- sl
  }
  if (requireNamespace("survminer", quietly = TRUE)) {
    p <- tryCatch(survminer::ggsurvplot(
      sfit, data = d, risk.table = TRUE, palette = cols,
      xlab = time_unit_lab, ylab = "Survival probability",
      legend.title = "", ggtheme = tj_theme(fam)),
      error = function(e) {message("tj_km_pdf survminer ERR: ", conditionMessage(e)); NULL})
    if (!is.null(p)) {
      if (exists("pipeline_pdf_device", mode = "function")) {
        pipeline_pdf_device(out_pdf, 6.4, 5.4, family = fam)
      } else {
        grDevices::cairo_pdf(out_pdf, width = 6.4, height = 5.4, family = fam)
      }
      on.exit(grDevices::dev.off(), add = TRUE)
      p$plot <- p$plot + ggplot2::labs(
        title = title,
        subtitle = sprintf("Log-rank P %s",
          if (is.finite(pval) && pval < 0.001) "< 0.001" else sprintf("= %.3f", pval)))
      print(p, newpage = FALSE)
      return(invisible(TRUE))
    }
  }
  # survminer 不可用/失败 → 纯 ggplot 阶梯曲线（无 risk table）
  snames <- as.character(sfit$strata)
  g_lab <- sub("^[^=]*=", "", snames)
  curve <- data.frame(
    t = as.numeric(sfit$time), s = as.numeric(sfit$surv),
    lo = as.numeric(sfit$lower), hi = as.numeric(sfit$upper),
    class = rep(g_lab, as.integer(sfit$strata)))
  curve <- curve[is.finite(curve$s), ]
  curve$class <- factor(curve$class, levels = levels(d[[gv]]))
  gg <- ggplot2::ggplot(curve, ggplot2::aes(x = t, y = s, color = class)) +
    ggplot2::geom_step(direction = "vh", linewidth = 0.9) +
    ggplot2::scale_color_manual(values = cols, name = "") +
    ggplot2::coord_cartesian(ylim = c(0, 1)) +
    ggplot2::labs(title = title,
      subtitle = sprintf("Log-rank P %s",
        if (is.finite(pval) && pval < 0.001) "< 0.001" else sprintf("= %.3f", pval)),
      x = time_unit_lab, y = "Survival probability") +
    tj_theme(fam) + ggplot2::theme(legend.position = "top")
  ggplot2::ggsave(out_pdf, gg, width = 6.2, height = 4.6, device = grDevices::cairo_pdf)
  invisible(TRUE)
}

#' HR 森林图（多 class × 多 model 行；log 刻度）
tj_forest_pdf <- function(rows_df, out_pdf, title, fam, ref_lab = "Reference (T1)",
                          xlim = NULL) {
  rows_df <- rows_df[!is.na(rows_df$HR), , drop = FALSE]
  if (!nrow(rows_df)) return(invisible(FALSE))
  rows_df$lab <- factor(rows_df$lab, levels = rev(rows_df$lab))
  lim <- xlim %||% c(max(0.05, min(rows_df$lo) * 0.8), max(rows_df$hi) * 1.25)
  gg <- ggplot2::ggplot(rows_df, ggplot2::aes(x = HR, y = lab)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, color = "grey40") +
    ggplot2::geom_errorbarh(ggplot2::aes(xmin = lo, xmax = hi), height = 0.18,
                            color = "#2C5F8A") +
    ggplot2::geom_point(size = 2.6, color = "#C0392B") +
    ggplot2::scale_x_log10(limits = lim) +
    ggplot2::annotation_logticks(sides = "b", short = ggplot2::unit(0.8, "mm"),
                                 mid = ggplot2::unit(1.2, "mm")) +
    ggplot2::labs(title = title, x = "Hazard ratio (95% CI, log scale)", y = NULL) +
    tj_theme(fam) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(family = fam))
  ggplot2::ggsave(out_pdf, gg, width = 6.6, height = max(2.2, 0.34 * nrow(rows_df) + 1.3),
                  device = grDevices::cairo_pdf)
  invisible(TRUE)
}

#' GBMTM 类别均值曲线面板（z 分数 × 波次；每指标一面板）
tj_traj_panel <- function(fitobj, ind, out_pdf, fam, panel_title) {
  lab <- fitobj$label_tab
  cm <- fitobj$fit$class_map
  d <- fitobj$long
  d$class <- as.integer(cm[match(d$id, names(cm))])
  agg <- stats::aggregate(list(z = d$z), list(ind = d$ind, t = d$t, class = d$class), mean)
  agg <- agg[agg$ind == ind, , drop = FALSE]
  if (!nrow(agg)) return(invisible(FALSE))
  agg$cls <- factor(paste0("T", agg$class), levels = sort(unique(paste0("T", agg$class))))
  gg <- ggplot2::ggplot(agg, ggplot2::aes(x = t, y = z, group = cls, color = cls)) +
    ggplot2::geom_line(linewidth = 1) + ggplot2::geom_point(size = 2.4) +
    ggplot2::scale_y_continuous(name = NULL) +
    ggplot2::labs(title = panel_title, x = "Examination wave", y = "Standardized value (z)") +
    ggplot2::scale_color_brewer(palette = "Dark2", name = "") +
    tj_theme(fam)
  ggplot2::ggsave(out_pdf, gg, width = 4.3, height = 3.6, device = grDevices::cairo_pdf)
  invisible(TRUE)
}

#' 基线按轨迹类别 Table1（连续 mean(SD)/中位 IQR + 分类 n(%) + P）
tj_table1_by_class <- function(df, gv, cont_vars, cat_vars, class_order = NULL,
                               var_labels = NULL) {
  lv <- class_order %||% sort(unique(as.character(df[[gv]])))
  df[[gv]] <- factor(df[[gv]], levels = lv)
  one <- function(i) {
    sub <- if (i == 0) df else df[df[[gv]] == lv[i], , drop = FALSE]
    out <- list()
    for (v in cont_vars) if (v %in% names(df)) {
      x <- suppressWarnings(as.numeric(sub[[v]]))
      out[[v]] <- if (all(is.na(x))) "" else
        sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE))
    }
    for (v in cat_vars) if (v %in% names(df)) {
      x <- sub[[v]]
      out[[v]] <- sprintf("%d (%.1f%%)", sum(x == 1, na.rm = TRUE),
                          100 * mean(x == 1, na.rm = TRUE))
    }
    out
  }
  cols <- lapply(seq_along(lv), one); allc <- one(0)
  vars <- unique(unlist(lapply(c(list(allc), cols), names)))
  pvals <- vapply(vars, function(v) {
    x <- suppressWarnings(as.numeric(df[[v]]))
    g <- df[[gv]]
    if (all(is.na(x))) return(NA_real_)
    if (length(unique(na.omit(x))) <= 2) {
      suppressWarnings(tryCatch(stats::pchisq(stats::chisq.test(table(factor(x), g))$statistic,
        df = length(lv) - 1, lower.tail = FALSE), error = function(e) NA_real_))
    } else {
      suppressWarnings(tryCatch(stats::kruskal.test(x ~ g)$p.value, error = function(e) NA_real_))
    }
  }, numeric(1))
  .vlab <- function(v) {
    if (!is.null(var_labels) && v %in% names(var_labels)) return(var_labels[[v]])
    if (exists("pipeline_display_label", mode = "function")) pipeline_display_label(v)
    else gsub("[_.]", " ", v)
  }
  df_out <- data.frame(
    Variable = vapply(vars, .vlab, character(1)),
    check.names = FALSE)
  df_out[[paste0("Overall (n=", nrow(df), ")")]] <- vapply(vars, function(v)
    if (v %in% names(allc)) allc[[v]] else "", character(1))
  for (i in seq_along(lv)) df_out[[paste0(lv[i], " (n=", sum(df[[gv]] == lv[i]), ")")]] <-
    vapply(vars, function(v) if (v %in% names(cols[[i]])) cols[[i]][[v]] else "", character(1))
  df_out$P <- vapply(pvals, function(p) if (is.na(p)) "" else
    if (p < 0.001) "<0.001" else sprintf("%.3f", p), character(1))
  df_out
}

#' 软件版本 txt（联合轨迹发病口径；含 R + mice/survival/gbmtm 内核说明）
tj_write_software_versions <- function(out_dir, extra = character(0)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  pkgs <- c("mice", "survival", "survminer", "ggplot2", "scales", "openxlsx")
  lines <- c("Statistical software and package versions",
             sprintf("R version: %s", paste(R.version$major, R.version$minor, sep = ".")),
             sprintf("Platform: %s", R.version$platform),
             "", "GBMTM: native engine implementation (R/gbmtm_core.R, EM full-information)")
  for (p in pkgs) lines <- c(lines, sprintf("%s: %s", p,
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed")))
  if (length(extra)) lines <- c(lines, "", extra)
  writeLines(lines, file.path(out_dir, "Methods_software_versions.txt"))
}
