###############################################################################
#  mediation_prognosis — 预后中介效应（Cox → HR）+ Table S9/S10 + 路径三角图 Figure S3
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = ctx$results$Model2Factors
#
#  mediation_prognosis = list(
#    mediators = NULL,
#    bootstrap_iter = 100,
#    covariates = NULL,
#    lm_screen_exclude_vars = NULL,
#    dual_library_lm_screen = TRUE,       # 本库内 Model1∩Model2 筛选
#    dual_db_lock_best_mediator = TRUE,   # 双库 Figure S3 同一中介
#    dual_db_force_rerun_mediation = TRUE,
#    diagram_palette = "matcha",          # 固定色板，避免双库颜色随机不一致
#    diagram_palette_random = FALSE,
#    auto_covariate_search = TRUE,
#    diagram_enable = TRUE,
#    best_mediator = NULL,                # 可强制；双库时优先 preferred / 闸门 E
#  ),
#
#  双库对齐（闸门 E）不在本 block 单独脚本里，而在 survival dual-batch worker
#  Phase 3 结束后由 survival_batch_apply_gate_e_mediation() 自动执行：
#    两库中介表交集 → 双库 Prop_Med 均值最大 → 以 best_mediator 重跑 mediation。
#  关闭：config$mediation_prognosis$dual_db_lock_best_mediator = FALSE
###############################################################################


###############################################################################
#  内部辅助：中介路径三角图
###############################################################################

# 马卡龙色系色组（每次运行 sample 随机抽一组）
.mp01_palettes <- list(
  # 草莓奶油
  sakura   = list(exposure = "#F2A7B8", mediator = "#C47EBE", outcome = "#F0875A"),
  # 薄荷拿铁
  matcha   = list(exposure = "#85C8AC", mediator = "#6AAAC8", outcome = "#E89A7A"),
  # 蓝莓奶酪
  blueberry= list(exposure = "#95B8E0", mediator = "#7A80C8", outcome = "#E08888"),
  # 芒果布丁
  mango    = list(exposure = "#F0C07A", mediator = "#D47A8A", outcome = "#7AB8A8"),
  # 薰衣草
  lavender = list(exposure = "#B8A0D8", mediator = "#D47890", outcome = "#78B8A8"),
  # 蜜桃玫瑰
  rosepeach= list(exposure = "#F0A898", mediator = "#B880C8", outcome = "#88B8D0")
)

.mp01_draw_mediation_path_diagram <- function(
    exposure_label, mediator_label, outcome_label,
    coef_a,       p_a,          # path a: X → M (lm beta)
    coef_b,       p_b,          # path b: M → Y (Cox/logistic beta)
    effect_total, p_total,      # total path: HR 或 OR（与下述 CI 同尺度）
    prop_pct,  prop_lo_pct,  prop_hi_pct,   # proportion mediated (%)
    colors,
    ci_a_lo = NA_real_, ci_a_hi = NA_real_,
    ci_b_lo = NA_real_, ci_b_hi = NA_real_,
    ci_tot_lo = NA_real_, ci_tot_hi = NA_real_,
    font_family  = "Times New Roman",
    output_path  = NULL,
    width = NULL, height = NULL) {

  suppressPackageStartupMessages(library(ggplot2))

  if (exists("resolve_plot_font_family", mode = "function")) {
    font_family <- resolve_plot_font_family(font_family)
  }

  .pretty <- function(x) gsub("_", " ", as.character(x %||% ""), fixed = TRUE)
  exposure_label <- .pretty(exposure_label)
  mediator_label <- .pretty(mediator_label)
  outcome_label  <- .pretty(outcome_label)

  .fp <- function(p) {
    if (is.null(p) || length(p) == 0L || is.na(p) || !is.finite(p)) return("p=NA")
    if (p < 0.001) "p<0.001" else paste0("p=", formatC(round(p, 3), format = "f", digits = 3))
  }
  .fc <- function(x, d = 3) {
    if (is.null(x) || length(x) == 0L || is.na(x) || !is.finite(x)) return("NA")
    formatC(round(x, d), format = "f", digits = d)
  }
  # 多行块内各行补空格到等宽，配合 hjust=0.5 使两行相对居中
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
  # 两行：第 1 行 效应 + (p…)；第 2 行 (lo, hi)
  .path_lbl_p_below_ci <- function(est, p, lo, hi,
                                     d_est = as.integer(.pipeline_pub_digits()$est)[1L]) {
    L1 <- paste0(.fc(est, d_est), " (", .fp(p), ")")
    lines <- if (is.finite(lo) && is.finite(hi)) {
      c(L1, paste0("(", .fc(lo, d_est), ", ", .fc(hi, d_est), ")"))
    } else {
      L1
    }
    if (length(lines) == 1L) lines else .lines_equal_width(lines)
  }

  .d_est <- as.integer(.pipeline_pub_digits()$est)[1L]
  if (!is.finite(.d_est) || .d_est < 0L) .d_est <- 3L
  lbl_a  <- .path_lbl_p_below_ci(coef_a, p_a, ci_a_lo, ci_a_hi, .d_est)
  lbl_b  <- .path_lbl_p_below_ci(coef_b, p_b, ci_b_lo, ci_b_hi, .d_est)
  lbl_d  <- .path_lbl_p_below_ci(effect_total, p_total, ci_tot_lo, ci_tot_hi, .d_est)
  # 与 Table S9 Prop_Med 同一位数（勿再硬编码 2 位导致图/表错位）
  pm_c   <- if (!is.na(prop_pct) && is.finite(prop_pct)) .fc(prop_pct, .d_est) else "?"
  lbl_pm <- paste0("Proportion mediated\n", pm_c, "%")

  # 三框等宽：变量名按最长字符数两侧补空格，ggplot label 外框一致（参考示意缩略图）
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
  lab_ex <- lab3[1L]
  lab_me <- lab3[2L]
  lab_ou <- lab3[3L]

  # ── 布局：上下扁、底边两框间距大；路径标签法向偏移适中，贴近箭身又少压线
  tri_cx  <- 5.0
  tri_by  <- 1.48
  base_hw <- 2.45
  apex_h  <- 2.38
  ex <- tri_cx - base_hw
  ox <- tri_cx + base_hw
  ey <- tri_by
  oy <- tri_by
  mx <- tri_cx
  my <- tri_by + apex_h

  # 方框在数据坐标中的半宽/半高（与 annotate label 外缘对齐；略小于真实圆角外沿，配合 tip_eps 加长箭身）
  bw_half <- 1.42
  bh_half <- 0.56

  # 从 (cx,cy) 沿指向 (tx,ty) 的射线，与轴对齐矩形框的交点（框心即变量位置）→ 箭贴在框边“朝向对方”的一侧
  .box_edge <- function(cx, cy, tx, ty) {
    dx <- tx - cx
    dy <- ty - cy
    if (abs(dx) < 1e-9 && abs(dy) < 1e-9) return(c(cx, cy))
    len <- sqrt(dx^2 + dy^2)
    ux <- dx / len
    uy <- dy / len
    t <- min(
      if (abs(ux) > 1e-9) bw_half / abs(ux) else Inf,
      if (abs(uy) > 1e-9) bh_half / abs(uy) else Inf
    )
    c(cx + t * ux, cy + t * uy)
  }

  # 箭尾：从起点框外沿出发；箭头：收到终点框边界内侧少许，避免三角箭头画进填充里
  .shorten_to <- function(xs, ys, xe, ye, eps) {
    dx <- xe - xs
    dy <- ye - ys
    len <- sqrt(dx^2 + dy^2)
    if (len < 1e-9) return(c(xe, ye))
    ux <- dx / len
    uy <- dy / len
    c(xe - eps * ux, ye - eps * uy)
  }
  tip_eps <- 0.028

  as1 <- .box_edge(ex, ey, mx, my)
  be1 <- .box_edge(mx, my, ex, ey)
  ae1 <- .shorten_to(as1[1], as1[2], be1[1], be1[2], tip_eps)
  as2 <- .box_edge(mx, my, ox, oy)
  be2 <- .box_edge(ox, oy, mx, my)
  ae2 <- .shorten_to(as2[1], as2[2], be2[1], be2[2], tip_eps)
  as3 <- .box_edge(ex, ey, ox, oy)
  be3 <- .box_edge(ox, oy, ex, ey)
  ae3 <- .shorten_to(as3[1], as3[2], be3[1], be3[2], tip_eps)

  am1 <- (as1 + ae1) / 2
  am2 <- (as2 + ae2) / 2
  am3 <- (as3 + ae3) / 2

  # lft_off：垂直于箭头的偏移；d 符号控制在内/外侧
  lft_off <- function(dx, dy, d) {
    len <- sqrt(dx^2 + dy^2)
    c(-dy / len * d, dx / len * d)
  }
  off_a <- lft_off(mx - ex, my - ey,  0.58)
  off_b <- lft_off(ox - mx, oy - my,  0.58)
  off_d_base <- lft_off(ox - ex, oy - ey, -0.42)

  cent_x <- (ex + mx + ox) / 3
  cent_y <- (ey + my + oy) / 3 - 0.28

  # ── 自适应该：坐标范围贴内容（旧 x∈[-1,11] y∈[-0.65,8.45] 导致半页空白）
  # 多行路径标签额外留白（宁紧勿空）
  pad_x <- 0.42
  pad_y <- 0.38
  # 框半宽/高估算略小于布局用值，避免短标签时外扩过多白边
  bw_lim <- bw_half * 0.78
  bh_lim <- bh_half * 0.85
  xs_all <- c(
    ex - bw_lim, ex + bw_lim, mx - bw_lim, mx + bw_lim,
    ox - bw_lim, ox + bw_lim,
    as1[1], ae1[1], as2[1], ae2[1], as3[1], ae3[1],
    am1[1] + off_a[1], am2[1] + off_b[1], am3[1] + off_d_base[1],
    cent_x
  )
  ys_all <- c(
    ey - bh_lim, ey + bh_lim, my - bh_lim, my + bh_lim,
    oy - bh_lim, oy + bh_lim,
    as1[2], ae1[2], as2[2], ae2[2], as3[2], ae3[2],
    am1[2] + off_a[2], am2[2] + off_b[2], am3[2] + off_d_base[2],
    cent_y
  )
  x_lim <- c(min(xs_all, na.rm = TRUE) - pad_x, max(xs_all, na.rm = TRUE) + pad_x)
  y_lim <- c(min(ys_all, na.rm = TRUE) - pad_y, max(ys_all, na.rm = TRUE) + pad_y)
  x_rng <- max(diff(x_lim), 1e-6)
  y_rng <- max(diff(y_lim), 1e-6)
  ar <- x_rng / y_rng
  # 画布按内容纵横比自适应（英寸）；可显式传入 width/height 覆盖
  if (is.null(width) || !is.finite(as.numeric(width)[1L])) {
    # 目标：长边约 6–6.5 in，尽量填满
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
  xsf <- width  / x_rng
  ysf <- height / y_rng
  vangle <- function(dx, dy) atan2(dy * ysf, dx * xsf) * 180 / pi
  ang_a <- vangle(mx - ex, my - ey)
  ang_b <- vangle(ox - mx, oy - my)
  ang_d <- vangle(ox - ex, oy - ey)

  arw <- arrow(length = unit(0.24, "cm"), type = "closed")
  lbl_box_sz <- 4.55
  lbl_pad_ln <- 0.62
  lbl_r_ln   <- 0.45

  plt <- ggplot() +
    coord_cartesian(xlim = x_lim, ylim = y_lim, expand = FALSE, clip = "off") +
    theme_void(base_family = font_family) +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin     = margin(2, 2, 2, 2, "mm")
    ) +
    annotate("text",
             x = am1[1] + off_a[1], y = am1[2] + off_a[2],
             label = lbl_a, angle = ang_a,
             hjust = 0.5, vjust = 0.5, size = 2.85, lineheight = 0.98,
             family = font_family, fontface = "bold", color = "gray30") +
    annotate("text",
             x = am2[1] + off_b[1], y = am2[2] + off_b[2],
             label = lbl_b, angle = ang_b,
             hjust = 0.5, vjust = 0.5, size = 2.85, lineheight = 0.98,
             family = font_family, fontface = "bold", color = "gray30") +
    annotate("text",
             x = am3[1] + off_d_base[1], y = am3[2] + off_d_base[2],
             label = lbl_d, angle = ang_d,
             hjust = 0.5, vjust = 0.5, size = 2.85, lineheight = 0.98,
             family = font_family, fontface = "bold", color = "gray30") +
    annotate("text",
             x = cent_x, y = cent_y, label = lbl_pm,
             hjust = 0.5, vjust = 0.5, size = 3.75, lineheight = 1.35,
             family = font_family, fontface = "bold", color = "gray25") +
    # 三框：等宽字符串 + 相同参数；马卡龙底 + 白字、无边框
    annotate("label",
             x = ex, y = ey, label = lab_ex,
             fill = colors$exposure, colour = "white",
             family = font_family, fontface = "bold", size = lbl_box_sz,
             linewidth = 0,
             label.r       = grid::unit(lbl_r_ln, "lines"),
             label.padding = grid::unit(lbl_pad_ln, "lines")) +
    annotate("label",
             x = mx, y = my, label = lab_me,
             fill = colors$mediator, colour = "white",
             family = font_family, fontface = "bold", size = lbl_box_sz,
             linewidth = 0,
             label.r       = grid::unit(lbl_r_ln, "lines"),
             label.padding = grid::unit(lbl_pad_ln, "lines")) +
    annotate("label",
             x = ox, y = oy, label = lab_ou,
             fill = colors$outcome, colour = "white",
             family = font_family, fontface = "bold", size = lbl_box_sz,
             linewidth = 0,
             label.r       = grid::unit(lbl_r_ln, "lines"),
             label.padding = grid::unit(lbl_pad_ln, "lines")) +
    # 箭头最后画，避免底边被 label 盖住
    annotate("segment",
             x = as1[1], y = as1[2], xend = ae1[1], yend = ae1[2],
             arrow = arw, linewidth = 0.95, color = "gray32") +
    annotate("segment",
             x = as2[1], y = as2[2], xend = ae2[1], yend = ae2[2],
             arrow = arw, linewidth = 0.95, color = "gray32") +
    annotate("segment",
             x = as3[1], y = as3[2], xend = ae3[1], yend = ae3[2],
             arrow = arw, linewidth = 0.95, color = "gray32")

  if (!is.null(output_path)) {
    tryCatch({
      ff <- if (isTRUE(capabilities("cairo"))) {
        "Times New Roman"
      } else {
        as.character(font_family %||% "Times New Roman")[1L]
      }
      # 再刷一遍主题，避免上游传入 Nimbus/serif
      plt <- plt + ggplot2::theme(
        text = ggplot2::element_text(family = ff),
        plot.title = ggplot2::element_text(family = ff)
      )
      if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(output_path, width = width, height = height, family = ff)
        print(plt)
        grDevices::dev.off()
      } else {
        ggplot2::ggsave(output_path, plt, device = grDevices::pdf,
                        width = width, height = height, bg = "white")
      }
      cli::cli_alert_success("中介路径图已保存: {.file {basename(output_path)}}")
    }, error = function(e) {
      cli::cli_alert_warning("中介路径图保存失败: {e$message}")
    })
  }
  invisible(plt)
}

###############################################################################
block_mediation_prognosis <- function(ctx, exposure = NULL, mediators = NULL,
                                 time_var = NULL, event_var = NULL,
                                 covariates = NULL, bootstrap_iter = 100,
                                 standardize_mediator = FALSE, seed = 1234, ...) {
  # dual-batch worker 的 getwd()/project$root 是课题目录，不含 Blocks/；优先 MEDICAL_BLOCKS_ROOT
  .engine_root <- function() {
    candidates <- unique(c(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
      as.character(ctx$config$project$root %||% ""),
      getwd()
    ))
    for (r in candidates) {
      if (nzchar(r) && file.exists(file.path(r, "Blocks/20_mediation/00mediation_common.R")))
        return(r)
    }
    getwd()
  }
  common_path <- file.path(.engine_root(), "Blocks/20_mediation/00mediation_common.R")
  if (file.exists(common_path)) source(common_path, local = FALSE)
  if (!exists(".mi02_mediation_should_export", mode = "function")) {
    stop("mediation_prognosis: 未加载 00mediation_common.R（.mi02_*）；检查 MEDICAL_BLOCKS_ROOT=",
         Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "<unset>"), " path=", common_path)
  }

  suppressPackageStartupMessages({
    library(survival)
    library(dplyr)
  })

  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'data_clean' or 'imputation' first.")

  bl_cfg <- cfg$mediation_prognosis %||% list()
  surv_cfg <- cfg$survival %||% list()

  exposure <- exposure %||% bl_cfg$exposure %||% surv_cfg$index_var %||% cfg$logistic$index_var
  mediators <- mediators %||% bl_cfg$mediators
  covariates <- if (exists("pipeline_mediation_resolve_path_covariates", mode = "function")) {
    pipeline_mediation_resolve_path_covariates(cfg, bl_cfg, names(data), ctx = ctx)
  } else {
    character(0)
  }
  bootstrap_iter <- bootstrap_iter %||% bl_cfg$bootstrap_iter %||% 100
  standardize_mediator <- isTRUE(bl_cfg$standardize_mediator %||% TRUE)
  seed <- seed %||% bl_cfg$seed %||% cfg$splitting$seed %||% 1234

  if (is.null(mediators) || length(mediators) == 0) {
    a <- colnames(data)
    Index <- exposure
    # 与发病 / NHANES 同一实验室池：禁止把饮酒/婚姻/身高/血压等扫进关联表
    var_input <- .mi02_resolve_lab_indicator_pool(cfg, bl_cfg, a, exposure)
    b <- bl_cfg$lm_screen_exclude_vars
    if (is.null(b) || length(b) == 0L) {
      b <- character(0)
    }

    # 变量名按不区分大小写做差集；额外剔除时间/结局/ID / 疾病泄漏
    surv_cfg_early <- cfg$survival %||% list()
    dis_excl <- as.character((cfg$analysis_exclusion %||% list())$disease_vars %||% character(0))
    b <- unique(c(
      as.character(b),
      dis_excl,
      as.character(surv_cfg_early$time_var %||% character(0)),
      as.character(surv_cfg_early$event_var %||% character(0)),
      as.character(cfg$data$outcome_column %||% character(0)),
      "RFS_Months", "futime", "fustatus", "Is_Recurrence_factor",
      "Pt_ID", "ID", "SEQN", "Patient_ID",
      Index, paste0(Index, "_index_cut")
    ))
    # 全局规则：暴露组分/其它复合指标绝不可作中介候选（BAR→BUN/Albumin 等）
    if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
      b <- unique(c(b, pipeline_mediation_lab_exclude_vars(cfg, data_cols = a)))
    }
    b_lc <- unique(tolower(trimws(as.character(b))))
    var_input <- var_input[!(tolower(var_input) %in% b_lc)]
    if (exists("pipeline_mediation_filter_mediators", mode = "function")) {
      var_input <- pipeline_mediation_filter_mediators(
        var_input, cfg, data_cols = a, label = "LM关联筛"
      )
    }
    pin_lm <- .mi02_resolve_best_mediator_name(cfg, bl_cfg)
    if (nzchar(pin_lm) && pin_lm %in% names(data) && !pin_lm %in% var_input) {
      var_input <- unique(c(pin_lm, var_input))
      cli::cli_alert_info("LM 关联表强制纳入 best_mediator={pin_lm}")
    }
    cli::cli_alert_info(
      "mediation_prognosis: LM 关联筛候选 {length(var_input)} 个（实验室指标+锁定中介）— {paste(head(var_input, 8), collapse = ', ')}{if (length(var_input) > 8) '...' else ''}"
    )
    Model2 <- ctx$results$Model2Factors %||% character(0)
    Model2 <- as.character(Model2)
    if (length(Model2) > 0L) Model2 <- Model2[nzchar(Model2)]
    Model2 <- unique(intersect(Model2, names(data)))
    adj <- if (exists("pipeline_mediation_lm_adjustors", mode = "function")) {
      pipeline_mediation_lm_adjustors(ctx, data_names = names(data))
    } else {
      list(m1 = if (length(Model2)) Model2[1L] else character(0), m2 = Model2)
    }
    Model1Factors <- adj$m1
    Model2Factors <- adj$m2
    if (!length(Model2Factors)) Model2Factors <- Model2
    if (!length(Model1Factors) && length(Model2Factors)) {
      Model1Factors <- Model2Factors[1L]
    }

    # 分类协变量 → 可估计的单一系数（二分类 0/1；多分类按水平序评分，供筛选用）
    .mp01_prepare_cor_numeric <- function(Data, CorName) {
      if (!CorName %in% names(Data)) return(Data)
      x <- Data[[CorName]]
      if (is.numeric(x) && !is.factor(x)) return(Data)
      xf <- if (is.factor(x)) droplevels(x) else factor(x)
      nl <- nlevels(xf)
      if (nl <= 1L) return(Data)
      if (nl == 2L) {
        Data[[CorName]] <- as.numeric(xf) - 1
      } else {
        Data[[CorName]] <- as.numeric(xf)
      }
      Data
    }

    Tb_ModelGroup3_Corlm <- function(ResultName, CorName, Model1Factors, Model2Factors, Data) {
      pick_beta_ci_p <- function(fit, var) {
        if (is.null(fit)) return(c(NA_real_, NA_character_, NA_real_))
        sm <- summary(fit)
        cf <- sm$coefficients
        rn <- rownames(cf)
        if (is.null(rn) || !length(rn)) return(c(NA_real_, NA_character_, NA_real_))

        hits <- character(0)
        if (var %in% rn) {
          hits <- var
        } else {
          hits <- rn[rn != "(Intercept)" & startsWith(rn, var)]
          # 避免 Age 误匹配 Age_Group：后缀需为水平标签（非 _ 续写变量名时仍可能命中，再过滤）
          if (length(hits) > 1L) {
            hits <- hits[nchar(hits) > nchar(var)]
          }
        }
        if (!length(hits)) return(c(NA_real_, NA_character_, NA_real_))

        conf <- tryCatch(confint(fit), error = function(e) NULL)
        use <- hits[1L]
        if (length(hits) > 1L) {
          # 多水平：报告 |β| 最大的水平；P 用该水平（筛选用）
          betas <- suppressWarnings(as.numeric(cf[hits, 1]))
          use <- hits[which.max(abs(betas))]
        }
        if (is.null(conf) || !(use %in% rownames(conf))) {
          ci <- NA_character_
        } else {
          ci <- paste0("(", round(conf[use, 1], 3), ",", round(conf[use, 2], 3), ")")
        }
        c(
          round(as.numeric(cf[use, 1]), 3),
          ci,
          round(as.numeric(cf[use, 4]), 3)
        )
      }

      Data <- .mp01_prepare_cor_numeric(Data, CorName)
      if (CorName %in% names(Data) && is.numeric(Data[[CorName]])) {
        Data[[CorName]] <- as.numeric(scale(Data[[CorName]]))
        # 防御：scale 失败时不得静默回退到原始量纲（否则 PH 等会出现 |β|>10）
        if (!all(is.finite(Data[[CorName]]) | is.na(Data[[CorName]]))) {
          stop("mediation LM: scale(", CorName, ") produced non-finite values", call. = FALSE)
        }
      }
      # 结局若为多分类因子，按水平序转为数值以便 lm
      if (ResultName %in% names(Data)) {
        y <- Data[[ResultName]]
        if (is.character(y) || is.factor(y)) {
          Data[[ResultName]] <- as.numeric(factor(y))
        }
      }

      fml_c01 <- as.formula(paste0(ResultName, "~", CorName))
      rhs2 <- unique(c(CorName, Model1Factors))
      rhs2 <- rhs2[rhs2 != ResultName]
      fml_c02 <- as.formula(paste0(ResultName, "~", paste(rhs2, collapse = "+")))
      rhs3 <- unique(c(CorName, Model2Factors))
      rhs3 <- rhs3[rhs3 != ResultName]
      fml_c03 <- as.formula(paste0(ResultName, "~", paste(rhs3, collapse = "+")))

      crude_model <- tryCatch(lm(fml_c01, data = Data), error = function(e) NULL)
      model1 <- tryCatch(lm(fml_c02, data = Data), error = function(e) NULL)
      model2 <- tryCatch(lm(fml_c03, data = Data), error = function(e) NULL)

      r1 <- pick_beta_ci_p(crude_model, CorName)
      r2 <- pick_beta_ci_p(model1, CorName)
      r3 <- pick_beta_ci_p(model2, CorName)

      colum1 <- c(CorName, "Crude Model", "Model1", "Model2")
      colum2 <- c("", as.character(r1[1]), as.character(r2[1]), as.character(r3[1]))
      colum3 <- c("", as.character(r1[2]), as.character(r2[2]), as.character(r3[2]))
      colum4 <- c("", as.character(r1[3]), as.character(r2[3]), as.character(r3[3]))
      cbind(colum1, colum2, colum3, colum4)
    }

    var_input <- var_input[var_input %in% names(data)]
    var_input <- var_input[var_input != exposure]
    rt_list <- lapply(var_input, function(x) {
      Tb_ModelGroup3_Corlm(
        ResultName = exposure,
        CorName = x,
        Data = data,
        Model1Factors = Model1Factors,
        Model2Factors = Model2Factors
      )
    })

    dual_lm <- isTRUE(bl_cfg$dual_library_lm_screen %||% TRUE)
    lm_alpha <- as.numeric(bl_cfg$lm_screen_alpha %||% 0.05)
    lm_nonneg <- isTRUE(bl_cfg$lm_screen_require_nonneg_beta %||% TRUE)
    fallback_m2 <- isTRUE(bl_cfg$fallback_single_library_model2 %||% TRUE)

    .lm_row_ok <- function(beta, p) {
      if (!is.finite(beta) || !is.finite(p)) return(FALSE)
      if (p >= lm_alpha) return(FALSE)
      if (lm_nonneg && beta < 0) return(FALSE)
      TRUE
    }

    sig_m1 <- character(0)
    sig_m2 <- character(0)
    sig_from_lm <- character(0)
    if (length(rt_list) > 0L) {
      for (i in seq_along(rt_list)) {
        list_value <- rt_list[[i]]
        rn <- list_value[, 1]
        vn <- as.character(list_value[1, 1])
        i_m1 <- match("Model1", rn)
        i_m2 <- match("Model2", rn)
        if (is.na(i_m2)) i_m2 <- nrow(list_value)
        beta2 <- suppressWarnings(as.numeric(list_value[i_m2, 2]))
        p2 <- suppressWarnings(as.numeric(list_value[i_m2, 4]))
        ok2 <- .lm_row_ok(beta2, p2)
        ok1 <- FALSE
        if (!is.na(i_m1) && i_m1 >= 1L && i_m1 <= nrow(list_value)) {
          beta1 <- suppressWarnings(as.numeric(list_value[i_m1, 2]))
          p1 <- suppressWarnings(as.numeric(list_value[i_m1, 4]))
          ok1 <- .lm_row_ok(beta1, p1)
        }
        if (ok1) sig_m1 <- c(sig_m1, vn)
        if (ok2) sig_m2 <- c(sig_m2, vn)
        if (dual_lm) {
          if (ok1 && ok2) sig_from_lm <- c(sig_from_lm, vn)
        } else if (ok2) {
          sig_from_lm <- c(sig_from_lm, vn)
        }
      }

      rt <- do.call(rbind, rt_list)
      rt <- data.frame(rt, stringsAsFactors = FALSE)
      colnames(rt) <- c("variable", "β per 1-SD", "95% CI", "P value")
      rt[["P value"]][which(rt[["P value"]] == "0")] <- "< 0.001"
      # 仅暂存；中介门控通过后再导出（门控失败则关联表也不要）
      ctx$results$mediation_prognosis_correlation_lm_rt <- rt
    }

    if (dual_lm) {
      ctx$results$mediation_prognosis_lm_sig_model1_only <- unique(intersect(sig_m1, names(data)))
      ctx$results$mediation_prognosis_lm_sig_model2_only <- unique(intersect(sig_m2, names(data)))
      mediators <- unique(intersect(sig_from_lm, names(data)))
      if (length(mediators) == 0L && fallback_m2) {
        mediators <- unique(intersect(sig_m2, names(data)))
        cli::cli_alert_warning(
          "双库 LM 无交集（Model1∩Model2），已回退为仅 Model2 显著集（{length(mediators)} 个）"
        )
      } else {
        beta_rule_txt <- if (lm_nonneg) ">=0" else "任意"
        cli::cli_alert_info(
          "双库 LM 交集（Model1 与 Model2 均 beta{beta_rule_txt} 且 P<{lm_alpha}）: {length(mediators)} 个中介候选"
        )
      }
    } else {
      mediators <- unique(intersect(sig_from_lm, names(data)))
      cli::cli_alert_info("Auto-selected {length(mediators)} mediators from lm screening (Model2 only)")
    }

    if (length(mediators) > 0L) {
      list_path <- file.path(ctx$output_dir, "list_value.txt")
      writeLines(mediators, list_path)
    }
  }

  if (is.null(exposure))
  if (is.null(exposure)) stop("Please specify 'exposure' (independent variable)")
  if (is.null(mediators) || length(mediators) == 0) {
    cli::cli_alert_warning("No mediators available. Skipping mediation analysis.")
    .mi02_unlink_mediation_exports(ctx)
    return(ctx)
  }


  disease_label <- cfg$project$analysis_group %||% cfg$project$disease %||% "Stroke"

  time_var <- time_var %||% bl_cfg$time_var %||% surv_cfg$time_var %||% "futime"
  event_var <- event_var %||% bl_cfg$event_var %||% surv_cfg$event_var %||% "fustatus"

  for (v in c(exposure, time_var, event_var)) {
    if (!v %in% names(data)) {
      stop(paste0("Variable '", v, "' not found in data."))
    }
  }

  if (is.character(data[[event_var]]) || is.factor(data[[event_var]])) {
    ev_chr <- as.character(data[[event_var]])
    # 优先 analysis_group（如 Recurrence）；若零事件则回退 disease 名
    hit <- ev_chr == as.character(disease_label)[1L]
    if (!any(hit, na.rm = TRUE)) {
      alt <- as.character(cfg$project$disease %||% "")[1L]
      if (nzchar(alt) && any(ev_chr == alt, na.rm = TRUE)) {
        disease_label <- alt
        hit <- ev_chr == alt
      }
    }
    if (!any(hit, na.rm = TRUE)) {
      stop(
        sprintf(
          "mediation_prognosis: 事件列 '%s' 中找不到阳性标签 '%s'（请检查 project$analysis_group）",
          event_var, disease_label
        ),
        call. = FALSE
      )
    }
    data[[event_var]] <- ifelse(hit, 1, 0)
    cli::cli_alert_info(
      "事件编码: {event_var} == '{disease_label}' → 1（n_event={sum(hit, na.rm=TRUE)}）"
    )
  }
  data[[event_var]] <- as.numeric(data[[event_var]])
  if (!any(data[[event_var]] == 1, na.rm = TRUE)) {
    stop("mediation_prognosis: 事件数全为 0，无法拟合 Cox 中介模型。", call. = FALSE)
  }

  cli::cli_h2("Mediation Analysis for Prognosis Outcome (Cox → HR)")
  cli::cli_alert_info("Survival: Surv({time_var}, {event_var})")

  mediators <- intersect(mediators, names(data))
  mediators <- mediators[sapply(mediators, function(m) is.numeric(data[[m]]) && !is.factor(data[[m]]))]
  # 严禁把生存时间/结局当作中介
  mediators <- setdiff(mediators, c(time_var, event_var, exposure, "RFS_Months", "futime", "fustatus"))
  # 全项目：剔除暴露公式组分 + 其它复合指标（如 BAR 的 BUN/Albumin）
  if (exists("pipeline_mediation_filter_mediators", mode = "function")) {
    mediators <- pipeline_mediation_filter_mediators(
      mediators, cfg, data_cols = names(data), label = "中介"
    )
  } else if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
    drop_comp <- intersect(mediators, pipeline_mediation_lab_exclude_vars(cfg, names(data)))
    if (length(drop_comp)) {
      cli::cli_alert_info("中介候选已剔除指标组分/复合指标: {paste(drop_comp, collapse = ', ')}")
      mediators <- setdiff(mediators, drop_comp)
    }
  }
  if (length(mediators) == 0) {
    # 该指标数据筛后无可用数值中介（组分/复合指标已剔除、或池中候选全被排除）。
    # 中介为下游可选分析，直接中断会把整指标打成 failed；此处降级为跳过并告警。
    cli::cli_alert_warning(
      "mediation_prognosis: 筛选后无有效数值中介变量，跳过该指标中介分析（不阻断主分析）。"
    )
    return(ctx)
  }

  covariates <- intersect(covariates, names(data))
  if (exists("pipeline_mediation_drop_mediators_from_covariates", mode = "function")) {
    covariates <- pipeline_mediation_drop_mediators_from_covariates(
      covariates, mediators, label = "mediation_prognosis"
    )
  } else {
    covariates <- setdiff(covariates, mediators)
  }

  cli::cli_alert_info("Exposure (X): {exposure}")
  cli::cli_alert_info("Mediators (M): {length(mediators)} variables")
  if (length(covariates) > 0) {
    cli::cli_alert_info("Covariates: {paste(covariates, collapse = ', ')}")
  }
  cli::cli_alert_info("Bootstrap iterations: {bootstrap_iter}")
  cli::cli_alert_info("Standardize mediator: {standardize_mediator}")

  run_single_mediation_prognosis <- function(med_var, dat, B = 100, adj = NULL, use_z = FALSE) {
    needed_vars <- unique(c(time_var, event_var, exposure, med_var, adj))
    needed_vars <- needed_vars[nzchar(as.character(needed_vars))]
    model_data <- as.data.frame(dat)[, needed_vars, drop = FALSE]
    model_data <- stats::na.omit(model_data)

    if (nrow(model_data) < 20) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_HR = NA_character_,
        DirectEffect_HR = NA_character_,
        IndirectEffect_HR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }

    # 必须在 na.omit 之后算 z，并写入 model_data
    if (isTRUE(use_z)) {
      model_data$.M_z <- as.numeric(scale(model_data[[med_var]]))
      med_in_model <- ".M_z"
    } else {
      med_in_model <- med_var
    }
    
    formula_a <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste(med_in_model, "~", exposure))
    } else {
      as.formula(paste(med_in_model, "~", exposure, "+", paste(adj, collapse = " + ")))
    }
    
    model_a <- tryCatch(lm(formula_a, data = model_data), error = function(e) NULL)
    if (is.null(model_a)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_HR = NA_character_,
        DirectEffect_HR = NA_character_,
        IndirectEffect_HR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_a <- summary(model_a)
    coef_a <- sum_a$coefficients[exposure, "Estimate"]
    se_a <- sum_a$coefficients[exposure, "Std. Error"]
    p_a <- sum_a$coefficients[exposure, "Pr(>|t|)"]
    
    formula_full <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", exposure, " + ", med_in_model))
    } else {
      as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", exposure, " + ", med_in_model, " + ", paste(adj, collapse = " + ")))
    }
    
    model_full <- tryCatch(coxph(formula_full, data = model_data), error = function(e) NULL)
    if (is.null(model_full)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_HR = NA_character_,
        DirectEffect_HR = NA_character_,
        IndirectEffect_HR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_full <- summary(model_full)
    coef_c_prime <- sum_full$coefficients[exposure, "coef"]
    se_c_prime <- sum_full$coefficients[exposure, "se(coef)"]
    p_c_prime <- sum_full$coefficients[exposure, "Pr(>|z|)"]
    coef_b <- sum_full$coefficients[med_in_model, "coef"]
    se_b <- sum_full$coefficients[med_in_model, "se(coef)"]
    p_b <- sum_full$coefficients[med_in_model, "Pr(>|z|)"]
    
    formula_total <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", exposure))
    } else {
      as.formula(paste0("Surv(", time_var, ", ", event_var, ") ~ ", exposure, " + ", paste(adj, collapse = " + ")))
    }
    
    model_total <- tryCatch(coxph(formula_total, data = model_data), error = function(e) NULL)
    if (is.null(model_total)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_HR = NA_character_,
        DirectEffect_HR = NA_character_,
        IndirectEffect_HR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_total <- summary(model_total)
    coef_c <- sum_total$coefficients[exposure, "coef"]
    se_c <- sum_total$coefficients[exposure, "se(coef)"]
    p_c <- sum_total$coefficients[exposure, "Pr(>|z|)"]
    
    if (!is.null(seed)) set.seed(seed)
    
    pm_boot <- tryCatch({
      replicate(B, {
        idx <- sample(nrow(model_data), replace = TRUE)
        db <- model_data[idx, ]
        if (use_z) db$.M_z <- as.numeric(scale(db[[med_var]]))
        ca <- tryCatch(coef(lm(formula_a, data = db))[exposure], error = function(e) NA)
        mf <- tryCatch(coxph(formula_full, data = db), error = function(e) NULL)
        cb <- if (!is.null(mf)) tryCatch(coef(mf)[med_in_model], error = function(e) NA) else NA
        mt <- tryCatch(coxph(formula_total, data = db), error = function(e) NULL)
        cc <- if (!is.null(mt)) tryCatch(coef(mt)[exposure], error = function(e) NA) else NA
        if (any(is.na(c(ca, cb, cc))) || abs(cc) < 1e-10) return(NA)
        (ca * cb) / cc
      })
    }, error = function(e) rep(NA, B))
    
    pm_ci <- tryCatch(quantile(pm_boot, c(0.025, 0.975), na.rm = TRUE), error = function(e) c(NA, NA))
    
    se_ab <- sqrt(coef_a^2 * se_b^2 + coef_b^2 * se_a^2)
    p_ab <- 2 * (1 - pnorm(abs((coef_a * coef_b) / se_ab)))
    
    .d_est <- as.integer(.pipeline_pub_digits()$est)[1L]
    if (!is.finite(.d_est) || .d_est < 0L) .d_est <- 3L
    .fc_est <- function(x) formatC(round(as.numeric(x), .d_est), format = "f", digits = .d_est)

    prop_med_num <- if (!is.na(coef_c) && abs(coef_c) > 1e-10) {
      round(((coef_a * coef_b) / coef_c) * 100, .d_est)
    } else {
      NA_real_
    }
    
    .med_p <- function(p) {
      if (exists("pub_format_p_cell", mode = "function")) pub_format_p_cell(p) else fmt_pval(p)
    }
    total_hr <- paste0(
      .fc_est(exp(coef_c)),
      " [", .fc_est(exp(coef_c - 1.96 * se_c)),
      "-", .fc_est(exp(coef_c + 1.96 * se_c)), "] ",
      .med_p(p_c)
    )
    
    direct_hr <- paste0(
      .fc_est(exp(coef_c_prime)),
      " [", .fc_est(exp(coef_c_prime - 1.96 * se_c_prime)),
      "-", .fc_est(exp(coef_c_prime + 1.96 * se_c_prime)), "] ",
      .med_p(p_c_prime)
    )
    
    indirect_hr <- paste0(
      .fc_est(exp(coef_a * coef_b)),
      " [", .fc_est(exp((coef_a * coef_b) - 1.96 * se_ab)),
      "-", .fc_est(exp((coef_a * coef_b) + 1.96 * se_ab)), "] ",
      .med_p(p_ab)
    )
    
    path_a_str <- paste0(
      .fc_est(coef_a),
      " [", .fc_est(coef_a - 1.96 * se_a),
      ", ", .fc_est(coef_a + 1.96 * se_a), "] ",
      .med_p(p_a)
    )
    
    path_b_str <- paste0(
      .fc_est(coef_b),
      " [", .fc_est(coef_b - 1.96 * se_b),
      ", ", .fc_est(coef_b + 1.96 * se_b), "] ",
      .med_p(p_b),
      if (use_z) " (per 1-SD M)" else ""
    )
    
    prop_med <- if (is.finite(prop_med_num)) {
      paste0(formatC(prop_med_num, format = "f", digits = .d_est), "%")
    } else {
      NA_character_
    }
    
    data.frame(
      Mediator          = med_var,
      TotalEffect_HR    = total_hr,
      DirectEffect_HR   = direct_hr,
      IndirectEffect_HR = indirect_hr,
      Path_a_Beta       = path_a_str,
      Path_b_Beta       = path_b_str,
      Prop_Med_Pct      = prop_med,
      Prop_Med_num      = prop_med_num,
      # 绘图用原始数值列（以 .raw_ 开头，导出表时自动剥离）
      .raw_coef_a    = coef_a,
      .raw_p_a       = p_a,
      .raw_coef_b    = coef_b,
      .raw_p_b       = p_b,
      .raw_eff_total = exp(coef_c),    # total HR
      .raw_p_total   = p_c,
      .raw_eff_direct = exp(coef_c_prime),
      .raw_p_direct   = p_c_prime,
      .raw_prop_lo   = if (length(pm_ci) == 2L && !any(is.na(pm_ci))) pm_ci[1L] else NA_real_,
      .raw_prop_hi   = if (length(pm_ci) == 2L && !any(is.na(pm_ci))) pm_ci[2L] else NA_real_,
      .raw_ci_a_lo   = coef_a - 1.96 * se_a,
      .raw_ci_a_hi   = coef_a + 1.96 * se_a,
      .raw_ci_b_lo   = coef_b - 1.96 * se_b,
      .raw_ci_b_hi   = coef_b + 1.96 * se_b,
      .raw_ci_tot_lo = exp(coef_c - 1.96 * se_c),
      .raw_ci_tot_hi = exp(coef_c + 1.96 * se_c),
      .raw_ci_dir_lo = exp(coef_c_prime - 1.96 * se_c_prime),
      .raw_ci_dir_hi = exp(coef_c_prime + 1.96 * se_c_prime),
      .raw_p_indirect = p_ab,
      stringsAsFactors = FALSE
    )
  }

  .mp01_mediation_paths_significant <- function(one_row, alpha) {
    if (is.null(one_row) || nrow(one_row) != 1L) return(FALSE)
    pa <- suppressWarnings(as.numeric(one_row$.raw_p_a[1L]))
    pb <- suppressWarnings(as.numeric(one_row$.raw_p_b[1L]))
    pi <- if (".raw_p_indirect" %in% names(one_row)) {
      suppressWarnings(as.numeric(one_row$.raw_p_indirect[1L]))
    } else {
      NA_real_
    }
    ok <- is.finite(pa) && is.finite(pb) && is.finite(pi)
    if (!ok) return(FALSE)
    pa < alpha && pb < alpha && pi < alpha
  }

  auto_cov_search <- if (exists("pipeline_mediation_auto_covariate_search", mode = "function")) {
    pipeline_mediation_auto_covariate_search(cfg, bl_cfg)
  } else {
    FALSE
  }
  path_alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  search_b <- as.integer(bl_cfg$covariate_search_bootstrap_iter %||% min(100L, bootstrap_iter))
  max_k <- as.integer(bl_cfg$covariate_search_max_size %||% 5L)
  max_comb <- as.integer(bl_cfg$covariate_search_max_combinations %||% 300L)

  if (auto_cov_search && length(mediators) > 0L) {
    pool_search <- bl_cfg$covariate_search_pool %||% ctx$results$Model2Factors %||% character(0)
    pool_search <- unique(as.character(pool_search))
    pool_search <- intersect(pool_search, names(data))
    excl <- unique(c(exposure, time_var, event_var, mediators))
    pool_search <- setdiff(pool_search, excl)
    pool_search <- pool_search[vapply(pool_search, function(v) {
      xv <- data[[v]]
      is.numeric(xv) || is.logical(xv) || is.factor(xv)
    }, logical(1L))]

    .try_adj <- function(adj_vec) {
      adj_vec <- unique(as.character(adj_vec))
      adj_vec <- adj_vec[nzchar(adj_vec)]
      adj_vec <- intersect(adj_vec, names(data))
      for (m in mediators) {
        adj_m <- setdiff(adj_vec, m)
        row1 <- run_single_mediation_prognosis(m, data, B = search_b, adj = adj_m, use_z = standardize_mediator)
        if (.mp01_mediation_paths_significant(row1, path_alpha)) {
          return(list(ok = TRUE, adj = adj_m, hit = m))
        }
      }
      list(ok = FALSE, adj = NULL, hit = NA_character_)
    }

    tries <- 0L
    found <- NULL
    nk <- min(max_k, length(pool_search))
    cand0 <- intersect(covariates, names(data))

    tries <- tries + 1L
    r_none <- .try_adj(character(0))
    if (isTRUE(r_none$ok)) {
      found <- r_none
      cli::cli_alert_success(
        "自动协变量搜索：无协变量调整时已有中介 [{r_none$hit}] 满足 path a / b / indirect 均 p < {path_alpha}"
      )
    }
    if (is.null(found) && length(cand0) > 0L) {
      tries <- tries + 1L
      r0 <- .try_adj(cand0)
      if (isTRUE(r0$ok)) {
        found <- r0
        cli::cli_alert_success(
          "自动协变量搜索：沿用 config 中 covariates 已有中介 [{r0$hit}] 满足 path a / b / indirect 均 p < {path_alpha}"
        )
      }
    }
    if (is.null(found) && length(pool_search) > 0L) {
      for (k in seq.int(1L, nk)) {
        if (k > length(pool_search)) break
        combs <- if (k == 1L) {
          lapply(pool_search, function(x) x)
        } else {
          utils::combn(pool_search, k, simplify = FALSE)
        }
        for (adj in combs) {
          tries <- tries + 1L
          if (tries > max_comb) break
          r <- .try_adj(unlist(adj, use.names = FALSE))
          if (isTRUE(r$ok)) {
            found <- r
            cli::cli_alert_success(
              "自动协变量搜索：已选 {length(r$adj)} 个协变量，中介 [{r$hit}] path a/b/indirect 均 p < {path_alpha}（累计尝试 {tries}）"
            )
            cli::cli_alert_info("选用调整项: {paste(r$adj, collapse = ', ')}")
            break
          }
        }
        if (!is.null(found)) break
        if (tries > max_comb) break
      }
    }
    if (!is.null(found)) {
      covariates <- found$adj
      if (exists("pipeline_mediation_drop_mediators_from_covariates", mode = "function")) {
        covariates <- pipeline_mediation_drop_mediators_from_covariates(
          covariates, mediators, label = "mediation_prognosis"
        )
      } else {
        covariates <- setdiff(covariates, mediators)
      }
      ctx$results$mediation_prognosis_auto_covariates <- found$adj
      ctx$results$mediation_prognosis_auto_covariate_hit_mediator <- found$hit
      ctx$results$mediation_prognosis_auto_covariate_search_tries <- tries
    } else {
      cli::cli_alert_warning(
        "自动协变量搜索：在至多 {max_k} 个协变量、{max_comb} 次尝试内未找到使交集中任一中介 path a/b/indirect 均 p<{path_alpha} 的调整集；沿用原 covariates"
      )
      ctx$results$mediation_prognosis_auto_covariates <- NULL
    }
  }

  cli::cli_alert_info("Running mediation analysis for {length(mediators)} mediator(s)...")

  results_list <- lapply(seq_along(mediators), function(i) {
    med_var <- mediators[i]
    cli::cli_alert_info("Processing {i}/{length(mediators)}: {med_var}")
    adj_i <- setdiff(covariates, med_var)
    run_single_mediation_prognosis(med_var, data, B = bootstrap_iter, adj = adj_i, use_z = standardize_mediator)
  })

  final_table <- dplyr::bind_rows(results_list)
  final_table <- final_table[order(-final_table$Prop_Med_num, na.last = TRUE), ]

  index_name <- cfg$logistic$index_var %||% exposure

  # 路径图指定中介置顶，保证表首行与 Figure S3 同一中介
  pin_med <- as.character(bl_cfg$best_mediator %||% "")[1L]
  if (!nzchar(pin_med) && isTRUE((cfg$dual_db %||% list())$enable) &&
      exists("dual_db_load_preferred_mediator", mode = "function")) {
    root_pin <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
    pin_med <- as.character(dual_db_load_preferred_mediator(root_pin, cfg) %||% "")[1L]
  }
  if (nzchar(pin_med) && pin_med %in% final_table$Mediator) {
    final_table <- rbind(
      final_table[final_table$Mediator == pin_med, , drop = FALSE],
      final_table[final_table$Mediator != pin_med, , drop = FALSE]
    )
  }

  raw_cols  <- grep("^\\.raw_", names(final_table), value = TRUE)
  disp_cols <- setdiff(names(final_table), c("Prop_Med_num", raw_cols))
  display_table <- final_table[, disp_cols, drop = FALSE]
  colnames(display_table) <- c(
    "Mediator", "Total Effect", "Direct Effect", "Indirect Effect",
    "Path a (Beta)", "Path b (Beta)", "Proportion mediated"
  )

  # 规则：最佳中介 Proportion mediated + Direct Effect 均显著才导出；否则不出表/图
  path_alpha_prog <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  if (!.mi02_mediation_should_export(final_table, cfg, bl_cfg)) {
    ctx$results$mediation_prognosis <- final_table
    ctx$results$mediation_prognosis_ns_skipped <- TRUE
    reason <- .mi02_mediation_skip_reason(final_table, cfg, bl_cfg)
    cli::cli_alert_warning(
      "mediation_prognosis: {reason}，按规则不导出中介表、路径图与实验室关联表。"
    )
    .mi02_unlink_mediation_exports(ctx)
    return(ctx)
  }

  .mi02_export_lab_association_table(
    ctx, ctx$results$mediation_prognosis_correlation_lm_rt, exposure
  )

  med_pub <- pub_paths(
    ctx, ctx$output_dir_tables, "supp_table",
    paste0("Mediation analysis of ", gsub("_", " ", index_name)),
    "xlsx"
  )

  ctx$results$mediation_prognosis <- final_table

  tryCatch({
    fn_med <- if (exists("pipeline_mediation_table_footnotes", mode = "function")) {
      pipeline_mediation_table_footnotes(standardize_mediator)
    } else {
      "A negative proportion mediated indicates a suppression (masking) effect, not a mediated fraction."
    }
    export_sci_table(
      display_table, med_pub$filepath, title = med_pub$title,
      table_footnotes = fn_med
    )
    cli::cli_alert_success("Table saved: {.file {basename(med_pub$filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("Excel export failed: {e$message}")
  })

  cli::cli_alert_success("Mediation analysis completed: {length(mediators)} mediator(s) analyzed")

  diagram_enable <- isTRUE(bl_cfg$diagram_enable %||% TRUE)
  if (diagram_enable && nrow(final_table) > 0L) {
    best_med_cfg <- as.character(bl_cfg$best_mediator %||% "")[1L]
    # 双库对齐：共享 preferred → config best_mediator → 本库 Prop_Med 最大
    pref_shared <- NA_character_
    if (isTRUE((cfg$dual_db %||% list())$enable) &&
        isTRUE(bl_cfg$dual_db_lock_best_mediator %||% TRUE) &&
        exists("dual_db_load_preferred_mediator", mode = "function")) {
      root_m <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
      pref_shared <- dual_db_load_preferred_mediator(root_m, cfg)
    }
    if (nzchar(as.character(pref_shared %||% "")[1L]) &&
        pref_shared %in% final_table$Mediator) {
      best_row <- final_table[final_table$Mediator == pref_shared, , drop = FALSE][1L, ]
      cli::cli_alert_info("中介路径图：双库对齐中介 {pref_shared}")
    } else if (nzchar(best_med_cfg) && best_med_cfg %in% final_table$Mediator) {
      best_row <- final_table[final_table$Mediator == best_med_cfg, , drop = FALSE][1L, ]
      cli::cli_alert_info("中介路径图：使用指定中介 {best_med_cfg}")
    } else {
      valid_rows <- final_table[!is.na(final_table$Prop_Med_num), , drop = FALSE]
      best_row   <- if (nrow(valid_rows) > 0L) {
        valid_rows[which.max(valid_rows$Prop_Med_num), , drop = FALSE]
      } else {
        final_table[1L, , drop = FALSE]
      }
      cli::cli_alert_info(
        "中介路径图：自动选取 Prop_Med 最高中介 {best_row$Mediator[1L]}"
      )
    }
    if (isTRUE((cfg$dual_db %||% list())$enable) &&
        isTRUE(bl_cfg$dual_db_lock_best_mediator %||% TRUE) &&
        exists("dual_db_save_preferred_mediator", mode = "function")) {
      root_m <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
      dual_db_save_preferred_mediator(root_m, cfg, best_row$Mediator[1L])
    }

    # 默认固定色板，避免双库 Figure S3 色系随机不一致
    pal_name <- as.character(bl_cfg$diagram_palette %||% "matcha")[1L]
    if (isTRUE(bl_cfg$diagram_palette_random %||% FALSE)) {
      pal_name <- sample(names(.mp01_palettes), 1L)
    } else if (!nzchar(pal_name) || !(pal_name %in% names(.mp01_palettes))) {
      pal_name <- "matcha"
    }
    sel_colors <- .mp01_palettes[[pal_name]]
    proj_cfg <- cfg$project %||% list()
    # 预后中介结局是存活状态/院内死亡（fustatus），不是疾病名
    outcome_diag_label <- as.character(
      bl_cfg$outcome_label %||%
        bl_cfg$diagram_outcome_label %||%
        proj_cfg$analysis_group %||%
        "In-hospital mortality"
    )[1L]
    if (!nzchar(outcome_diag_label) ||
        identical(tolower(gsub("[ _]+", "", outcome_diag_label)),
                  tolower(gsub("[ _]+", "", as.character(proj_cfg$disease %||% "")[1L])))) {
      outcome_diag_label <- "In-hospital mortality"
    }
    outcome_diag_label <- gsub("_", " ", outcome_diag_label, fixed = TRUE)
    fig_caption <- paste0(
      "Mediation path diagram of ", exposure, " and ", outcome_diag_label
    )
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
    fig_kind <- as.character(bl_cfg$figure_kind %||% "supp_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "supp_figure"
    fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% NA_integer_)[1L])
    diag_path <- if (is.finite(fig_no) && fig_no >= 1L &&
                     exists("pub_figure_filepath_at", mode = "function")) {
      pub_figure_filepath_at(
        fig_dir, fig_no, fig_caption, ext = "pdf",
        bump_counter = isTRUE(bl_cfg$bump_counter %||% TRUE),
        kind = fig_kind
      )
    } else {
      file.path(fig_dir, pub_figure_file(ctx, fig_kind, fig_caption))
    }

    p_diag <- tryCatch(
      .mp01_draw_mediation_path_diagram(
        exposure_label  = exposure,
        mediator_label  = best_row$Mediator[1L],
        outcome_label   = outcome_diag_label,
        coef_a          = if (".raw_coef_a"    %in% names(best_row)) best_row$.raw_coef_a[1L]    else NA_real_,
        p_a             = if (".raw_p_a"        %in% names(best_row)) best_row$.raw_p_a[1L]        else NA_real_,
        coef_b          = if (".raw_coef_b"    %in% names(best_row)) best_row$.raw_coef_b[1L]    else NA_real_,
        p_b             = if (".raw_p_b"        %in% names(best_row)) best_row$.raw_p_b[1L]        else NA_real_,
        effect_total    = if (".raw_eff_direct" %in% names(best_row)) {
          best_row$.raw_eff_direct[1L]
        } else if (".raw_eff_total" %in% names(best_row)) {
          best_row$.raw_eff_total[1L]
        } else {
          NA_real_
        },
        # 底边箭头为 Direct Effect (c')；命名沿用绘图函数参数
        p_total         = if (".raw_p_direct" %in% names(best_row)) {
          best_row$.raw_p_direct[1L]
        } else if (".raw_p_total" %in% names(best_row)) {
          best_row$.raw_p_total[1L]
        } else {
          NA_real_
        },
        prop_pct        = best_row$Prop_Med_num[1L] %||% NA_real_,
        prop_lo_pct     = if (".raw_prop_lo" %in% names(best_row)) best_row$.raw_prop_lo[1L] * 100 else NA_real_,
        prop_hi_pct     = if (".raw_prop_hi" %in% names(best_row)) best_row$.raw_prop_hi[1L] * 100 else NA_real_,
        colors          = sel_colors,
        ci_a_lo         = if (".raw_ci_a_lo"    %in% names(best_row)) best_row$.raw_ci_a_lo[1L]    else NA_real_,
        ci_a_hi         = if (".raw_ci_a_hi"    %in% names(best_row)) best_row$.raw_ci_a_hi[1L]    else NA_real_,
        ci_b_lo         = if (".raw_ci_b_lo"    %in% names(best_row)) best_row$.raw_ci_b_lo[1L]    else NA_real_,
        ci_b_hi         = if (".raw_ci_b_hi"    %in% names(best_row)) best_row$.raw_ci_b_hi[1L]    else NA_real_,
        ci_tot_lo       = if (".raw_ci_dir_lo"  %in% names(best_row)) {
          best_row$.raw_ci_dir_lo[1L]
        } else if (".raw_ci_tot_lo" %in% names(best_row)) {
          best_row$.raw_ci_tot_lo[1L]
        } else {
          NA_real_
        },
        ci_tot_hi       = if (".raw_ci_dir_hi"  %in% names(best_row)) {
          best_row$.raw_ci_dir_hi[1L]
        } else if (".raw_ci_tot_hi" %in% names(best_row)) {
          best_row$.raw_ci_tot_hi[1L]
        } else {
          NA_real_
        },
        font_family     = plot_font_from_config(cfg),
        output_path     = diag_path
      ),
      error = function(e) {
        cli::cli_alert_warning("中介路径图绘制失败: {e$message}")
        NULL
      }
    )

    if (!is.null(p_diag) && file.exists(diag_path)) {
      mirror_pub_output_to_root(ctx, diag_path)
      ctx$results$mediation_prognosis_diagram      <- p_diag
      ctx$results$mediation_prognosis_diagram_path <- diag_path
    }
  }

  ctx
}

register_block("mediation_prognosis", block_mediation_prognosis,
               "Mediation analysis (prognosis): exposure -> mediators -> survival (Cox HR)")
