#!/usr/bin/env Rscript
# 胆结石列线图：按 Chen JAD 文献样式重算并重画 Fig2–9 + 补充图
# 修复点：
#   - Model3 不再塞满其它连续特征（避免分离/RCS失败）
#   - stone_type 塌缩 Favorable/Unfavorable
#   - OR/多因素用 brglm2；Fig2 一页森林；Fig3 每行最多3个 RCS
#   - Fig4 去掉顶部叠字；Fig5 双栏 Event%/OR/P；Fig6 干净 nomogram
#
# "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#   run/gallstone_nomogram/rebuild_all_pub_figures_lit.R \
#   --project "G:/02block_result/45_Gallstone/Nomogram_41815074"

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else
    "G:/02block_result/45_Gallstone/Nomogram_41815074"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
.root <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/literature_gallstone_nomogram.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
message("project: ", .proj)

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(forestploter)
  library(patchwork)
  library(rms)
  library(glmnet)
  library(pROC)
})

.feats <- c("Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
            "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots")
# 临床预指定预测因子（小样本；不含 CT%/近分离分类）
.prespec <- c("Age", "diameter_cm", "volume_cm3", "energy_j", "shots")
# 主文 Fig2/3：预指定连续变量
.feats_fig23 <- .prespec
.cats <- c("Sex", "shape", "color", "surface", "stone_type")
# 发表展示名：引擎字典（R/literature_gallstone_nomogram.R）+ pipeline_display_label
.lab_disp <- gallstone_nomogram_display_labels()
# Fig2/3 条带略短：Age 不写 ", y"；shots 不写 ", n"
.lab_disp[["Age"]] <- "Age"
.lab_disp[["shots"]] <- "Shots"
.disp <- function(x) {
  if (exists("pipeline_display_label", mode = "function")) {
    return(pipeline_display_label(x, label_map = .lab_disp))
  }
  x <- as.character(x)
  out <- unname(.lab_disp[x])
  miss <- is.na(out) | !nzchar(out)
  if (any(miss)) out[miss] <- gsub("_", " ", x[miss], fixed = TRUE)
  out
}
.out <- "Success"
.xlsx <- file.path(.proj, "data", "gallstone_features.xlsx")
.df0 <- gallstone_nomogram_read_xlsx(.xlsx)
.df <- gallstone_collapse_stone_type(.df0, .out)
.cfg <- list(gallstone_nomogram = list(
  continuous_features = .feats,
  categorical_features = .cats,
  assoc_covariate_source = "uv_significant",
  force_model1 = "Age",
  uv_alpha = 0.05,
  uv_demo_pool = c("Age", "Sex"),
  uv_candidate_pool = c("Age", "Sex", "shape", "color", "surface", "stone_type"),
  feature_select_mode = "prespecified",
  prespecified_predictors = .prespec,
  ridge_lambda = "lambda.1se",
  model2 = character(0),
  model3 = character(0),
  seed = 42L, train_ratio = 0.7, bootstrap_B = 200L
))
# 若 shared UV 表已存在则回写 model2/3（Age 强制并入）
.uv_csv <- file.path(.proj, "Tables", "Table_UV_covariate_screen.csv")
if (!file.exists(.uv_csv)) .uv_csv <- file.path(.proj, "_shared", "Tables", "Table_UV_covariate_screen.csv")
.uv <- NULL
if (file.exists(.uv_csv)) {
  .uv_tab <- utils::read.csv(.uv_csv, stringsAsFactors = FALSE)
  .sig <- as.character(.uv_tab$variable[as.logical(.uv_tab$significant) %in% TRUE])
  .uv <- list(table = .uv_tab, sig_all = .sig, sig_demo = intersect(.sig, c("Age", "Sex")),
              demo_pool = c("Age", "Sex"))
  .cfg$gallstone_nomogram$model2 <- unique(c("Age", .uv$sig_demo))
  .cfg$gallstone_nomogram$model3 <- unique(c("Age", .uv$sig_all))
  message("UV force_model1=Age; Model2=", paste(.cfg$gallstone_nomogram$model2, collapse = ","),
          " Model3=", paste(.cfg$gallstone_nomogram$model3, collapse = ","))
}

.set <- file.path(.proj, "summary_results")
.fig <- file.path(.set, "Figures")
.tab <- file.path(.set, "Tables")
.supp_fig <- file.path(.proj, "summary_results", "Figures")
dir.create(file.path(.fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)

.save_pdf_png <- function(plot_or_fun, path_pdf, w, h) {
  # 只写 pdf/ 子目录；禁止 Figures 根平铺
  if (!grepl("/pdf/", path_pdf, fixed = TRUE) && !grepl("\\\\pdf\\\\", path_pdf)) {
    path_pdf <- file.path(dirname(path_pdf), "pdf", basename(path_pdf))
  }
  dir.create(dirname(path_pdf), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(path_pdf, width = w, height = h, useDingbats = FALSE)
  if (is.function(plot_or_fun)) plot_or_fun() else print(plot_or_fun)
  grDevices::dev.off()
  # 镜像只进 */Figures/pdf/（主入口仍是 summary_results）
  for (d in c(
    file.path(.proj, "Figures", "pdf"),
    file.path(.proj, "_shared", "Figures", "pdf"),
    file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "pdf")
  )) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(path_pdf, file.path(d, basename(path_pdf)), overwrite = TRUE)
  }
  invisible(path_pdf)
}

.strip_flat_figure_pdfs <- function(fig_root) {
  if (!dir.exists(fig_root)) return(invisible(FALSE))
  flats <- list.files(fig_root, pattern = "^Figure.*\\.pdf$", full.names = TRUE)
  if (!length(flats)) return(invisible(FALSE))
  pdf_dir <- file.path(fig_root, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in flats) {
    file.copy(f, file.path(pdf_dir, basename(f)), overwrite = TRUE)
    unlink(f)
  }
  invisible(TRUE)
}

.fmt_p <- function(p) {
  p <- as.numeric(p)
  ifelse(!is.finite(p), "—",
         ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
.fmt_or <- function(or, lo, hi) {
  sprintf("%.2f (%.2f, %.2f)", or, lo, hi)
}

# PNG 白边裁剪（Fig2 forestploter 两侧留白）
.trim_png_white <- function(path, pad = 4L, thr = 250L) {
  if (!requireNamespace("png", quietly = TRUE) || !file.exists(path)) return(invisible(FALSE))
  im <- png::readPNG(path)
  if (length(dim(im)) < 2) return(invisible(FALSE))
  if (length(dim(im)) >= 3 && dim(im)[3] >= 3) {
    g <- 0.299 * im[,,1] + 0.587 * im[,,2] + 0.114 * im[,,3]
  } else if (length(dim(im)) >= 3) {
    g <- im[,,1]
  } else {
    g <- im
  }
  mask <- g < (thr / 255)
  rs <- which(apply(mask, 1, any)); cs <- which(apply(mask, 2, any))
  if (!length(rs) || !length(cs)) return(invisible(FALSE))
  r0 <- max(1L, min(rs) - pad); r1 <- min(nrow(g), max(rs) + pad)
  c0 <- max(1L, min(cs) - pad); c1 <- min(ncol(g), max(cs) + pad)
  png::writePNG(im[r0:r1, c0:c1, , drop = FALSE], path)
  invisible(TRUE)
}

# ===================== split =====================
set.seed(42)
yfac <- .df[[.out]]
if (requireNamespace("rsample", quietly = TRUE)) {
  sp <- rsample::initial_split(.df, prop = 0.7, strata = .out)
  .train <- rsample::training(sp); .test <- rsample::testing(sp)
} else {
  idx <- sample.int(nrow(.df))
  ntr <- floor(0.7 * nrow(.df))
  .train <- .df[idx[seq_len(ntr)], ]; .test <- .df[idx[-seq_len(ntr)], ]
}
message("split train=", nrow(.train), " val=", nrow(.test))

# ===================== Fig2 one-page forest =====================
message("→ Fig2 associations forest (nomogram continuous only: ",
        paste(.feats_fig23, collapse = ","), ") …")
.assoc_rows <- list()
for (f in .feats_fig23) {
  ms <- gallstone_nomogram_model_sets(.cfg, .df, expose = f, uv = .uv)
  for (mn in names(ms)) {
    rr <- gallstone_nomogram_fit_or_row(.df, f, .out, ms[[mn]])
    if (!is.null(rr)) {
      rr$model <- mn
      .assoc_rows[[length(.assoc_rows) + 1L]] <- rr
    }
  }
}
.assoc <- do.call(rbind, .assoc_rows)
utils::write.csv(.assoc, file.path(.tab, "Table_assoc_OR_Model123_all.csv"), row.names = FALSE)

# build forest df（ggplot + facet，指标名作条带，避两侧留白与标题裁切）
.rows2 <- list()
for (f in .feats_fig23) {
  for (mn in c("Model1", "Model2", "Model3")) {
    r <- .assoc[.assoc$feature == f & .assoc$model == mn, , drop = FALSE]
    if (!nrow(r)) next
    .rows2[[length(.rows2) + 1L]] <- data.frame(
      feature = f, model = mn,
      OR = r$OR[1], lo = r$CI_low[1], hi = r$CI_high[1],
      p_txt = .fmt_p(r$P[1]),
      stringsAsFactors = FALSE
    )
  }
}
.plot2 <- do.call(rbind, .rows2)
.plot2$feature_lab <- factor(.disp(.plot2$feature), levels = .disp(.feats_fig23))
.plot2$model <- factor(.plot2$model, levels = rev(c("Model1", "Model2", "Model3")))
.xlim_lo <- 0.01; .xlim_hi <- 50
.plot2$lo_d <- pmax(.plot2$lo, .xlim_lo)
.plot2$hi_d <- pmin(.plot2$hi, .xlim_hi)
.plot2$est_d <- pmin(pmax(.plot2$OR, .xlim_lo), .xlim_hi)
.hi_clip <- !is.na(.plot2$hi) & .plot2$hi > .xlim_hi
.plot2$or_txt <- .fmt_or(.plot2$OR, .plot2$lo, .plot2$hi)
.plot2$or_txt[.hi_clip] <- sprintf(
  "%.2f (%.2f, >%.0f)", .plot2$OR[.hi_clip], pmax(.plot2$lo[.hi_clip], 0), .xlim_hi
)
.p2 <- ggplot(.plot2, aes(y = model)) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey50", linewidth = 0.5) +
  geom_errorbar(aes(xmin = lo_d, xmax = hi_d),
                orientation = "y", width = 0.28, color = "#E67E22", linewidth = 0.7) +
  geom_point(aes(x = est_d), shape = 18, size = 3.0, color = "#E67E22") +
  geom_segment(
    data = .plot2[.hi_clip, , drop = FALSE],
    aes(x = .xlim_hi * 0.82, xend = .xlim_hi, y = model, yend = model),
    arrow = arrow(length = unit(0.11, "cm")), color = "#E67E22", linewidth = 0.55
  ) +
  scale_x_log10(
    limits = c(.xlim_lo, .xlim_hi),
    breaks = c(0.01, 0.1, 1, 10, 50),
    labels = c("0.01", "0.1", "1", "10", "50")
  ) +
  facet_grid(feature_lab ~ ., scales = "free_y", space = "free_y", switch = "y") +
  labs(x = "Odds Ratio (95% CI)", y = NULL) +
  theme_classic(base_size = 10) +
  theme(
    strip.placement = "outside",
    strip.text.y.left = element_text(angle = 0, face = "bold", size = 10, hjust = 1),
    strip.background = element_blank(),
    axis.ticks.y = element_blank(),
    plot.margin = margin(4, 2, 4, 2),
    panel.spacing.y = unit(0.35, "lines"),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3)
  )
.p2_tab <- ggplot(.plot2, aes(y = model)) +
  geom_text(aes(x = 1, label = or_txt), hjust = 0, size = 2.8) +
  geom_text(aes(x = 2.25, label = p_txt), hjust = 0, size = 2.8,
            fontface = ifelse(grepl("^<0\\.001$|^0\\.0[0-4]", .plot2$p_txt), "bold", "plain")) +
  scale_x_continuous(limits = c(0.95, 2.95), expand = c(0, 0)) +
  facet_grid(feature_lab ~ ., scales = "free_y", space = "free_y") +
  labs(title = "OR (95%CI)            P value", x = NULL, y = NULL) +
  theme_void(base_size = 10) +
  theme(
    plot.title = element_text(size = 9, face = "bold", hjust = 0, margin = margin(b = 2)),
    strip.text = element_blank(),
    plot.margin = margin(4, 2, 4, 0),
    panel.spacing.y = unit(0.35, "lines")
  )
.fig2_combined <- .p2 + .p2_tab + plot_layout(widths = c(2.6, 1.5))
.w2 <- 6.4; .h2 <- 3.55
message(sprintf("Fig2 ggplot forest: xlim log[%.2f,%.2f] size=%.2fx%.2f in", .xlim_lo, .xlim_hi, .w2, .h2))
writeLines(c(
  "Fig2 footnote (not drawn on figure to avoid axis overlap):",
  "Model1=Age forced; Model2=Age+UV-sig demo; Model3=Age+UV-sig pool (brglm2).",
  "OR per 1 SD; log xlim [0.01,50]; ticks 0.01/0.1/1/10/50; CI >50 shown as >50 with arrow.",
  sprintf("Fig2/3 exposures = nomogram continuous only: %s.",
          paste(.disp(.feats_fig23), collapse = ", "))
), file.path(.tab, "Methods_fig2_footnote.txt"))
.fig2_pdf <- file.path(.fig, "pdf", "Figure 2. Associations of continuous features.pdf")
.save_pdf_png(.fig2_combined, .fig2_pdf, .w2, .h2)
.fig2_png <- file.path(.fig, "png", "Figure 2. Associations of continuous features.png")
tryCatch({
  ggplot2::ggsave(.fig2_png, .fig2_combined, width = .w2, height = .h2, dpi = 200, bg = "white")
  .trim_png_white(.fig2_png, pad = 4L, thr = 250L)
  im <- png::readPNG(.fig2_png)
  wi <- dim(im)[2] / 200; hi <- dim(im)[1] / 200
  grDevices::pdf(.fig2_pdf, width = wi, height = hi, useDingbats = FALSE)
  grid::grid.raster(im, interpolate = TRUE)
  grDevices::dev.off()
  for (d in c(
    file.path(.proj, "Figures", "pdf"),
    file.path(.proj, "_shared", "Figures", "pdf")
  )) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(.fig2_pdf, file.path(d, basename(.fig2_pdf)), overwrite = TRUE)
  }
  message(sprintf("Fig2 cropped PDF: %.2fx%.2f in", wi, hi))
}, error = function(e) message("Fig2 trim/rewrite: ", conditionMessage(e)))

# ===================== Fig3 RCS（Chen 样式 A|B；纵轴按曲线自适应，禁止线/CI 穿框）=====================
message("→ Fig3 RCS Chen-style overlay hist (A|B, fit-ylim) …")
.rcs_fit_one <- function(data, expose, covars = character(0)) {
  d <- data
  y <- d[[.out]]
  d$.y <- if (is.factor(y)) as.integer(y == "Yes") else as.integer(as.numeric(y) == 1L)
  d$x_raw <- suppressWarnings(as.numeric(d[[expose]]))
  ok <- is.finite(d$x_raw) & is.finite(d$.y)
  d <- d[ok, , drop = FALSE]
  note <- NULL
  if (mean(d$x_raw == 0, na.rm = TRUE) > 0.35) {
    d2 <- d[d$x_raw > 0, , drop = FALSE]
    if (nrow(d2) >= 40L && length(unique(d2$x_raw)) >= 5L) {
      d <- d2
      note <- "among x>0"
    }
  }
  sdv <- stats::sd(d$x_raw, na.rm = TRUE)
  if (!is.finite(sdv) || sdv < 1e-8) return(NULL)
  d$x <- as.numeric(scale(d$x_raw))
  covars <- covars[covars %in% names(d)]
  nk <- if (!is.null(note)) 3L else if (length(unique(d$x_raw)) >= 8) 4L else 3L
  dd <- rms::datadist(d); options(datadist = "dd"); assign("dd", dd, envir = .GlobalEnv)
  fml <- stats::as.formula(paste(
    ".y ~ rcs(x,", nk, ")",
    if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""
  ))
  fit <- tryCatch(suppressWarnings(rms::lrm(fml, data = d, x = TRUE, y = TRUE)),
                  error = function(e) NULL)
  if ((is.null(fit) || isTRUE(fit$fail)) && nk > 3L) {
    nk <- 3L
    fml <- stats::as.formula(paste(
      ".y ~ rcs(x,", nk, ")",
      if (length(covars)) paste("+", paste(covars, collapse = "+")) else ""
    ))
    fit <- tryCatch(suppressWarnings(rms::lrm(fml, data = d, x = TRUE, y = TRUE)),
                    error = function(e) NULL)
  }
  if (is.null(fit) || isTRUE(fit$fail)) { options(datadist = NULL); return(NULL) }
  av <- tryCatch(anova(fit), error = function(e) NULL)
  p_overall <- NA_real_; p_nonlin <- NA_real_
  if (!is.null(av)) {
    pv <- as.data.frame(av); rn <- rownames(pv)
    cn <- intersect(c("P", "Pr(>Chi)"), names(pv))
    if (length(cn)) {
      ix <- which(rn == "x" | startsWith(rn, "x "))
      if (!length(ix)) ix <- 1L
      p_overall <- suppressWarnings(as.numeric(pv[ix[1], cn[1]]))
      i_nl <- grep("Nonlinear", rn, ignore.case = TRUE)
      if (length(i_nl)) p_nonlin <- suppressWarnings(as.numeric(pv[i_nl[1], cn[1]]))
    }
  }
  # 横轴：四分位中段，并尽量含 Z=0
  x_lim <- as.numeric(stats::quantile(d$x, c(0.30, 0.70), na.rm = TRUE))
  if (min(d$x, na.rm = TRUE) < 0 && max(d$x, na.rm = TRUE) > 0) {
    x_lim[1] <- min(x_lim[1], -0.05)
    x_lim[2] <- max(x_lim[2], 0.05)
  }
  if (!(is.finite(x_lim[1]) && x_lim[1] < x_lim[2])) {
    options(datadist = NULL); return(NULL)
  }
  xs <- seq(x_lim[1], x_lim[2], length.out = 160)
  pr <- tryCatch(suppressWarnings(rms::Predict(fit, x = xs, fun = NULL, conf.int = 0.95)),
                 error = function(e) NULL)
  if (is.null(pr)) { options(datadist = NULL); return(NULL) }
  pr0 <- tryCatch(suppressWarnings(rms::Predict(fit, x = 0, fun = NULL)), error = function(e) NULL)
  base <- if (!is.null(pr0)) as.numeric(pr0$yhat[1]) else 0
  pred <- data.frame(
    x = as.numeric(pr$x),
    OR = exp(as.numeric(pr$yhat) - base),
    lo = exp(as.numeric(pr$lower) - base),
    hi = exp(as.numeric(pr$upper) - base)
  )
  pred <- pred[is.finite(pred$OR) & pred$OR > 0, , drop = FALSE]
  if (!nrow(pred)) { options(datadist = NULL); return(NULL) }
  pred$lo[!is.finite(pred$lo) | pred$lo <= 0] <- pred$OR[!is.finite(pred$lo) | pred$lo <= 0]
  pred$hi[!is.finite(pred$hi) | pred$hi <= 0] <- pred$OR[!is.finite(pred$hi) | pred$hi <= 0]
  options(datadist = NULL)

  # 只保留 OR∈[0.2,5] 的最长连续 x 段（优先含 Z=0）；CI=OR×/÷2，纵轴跟 OR
  .cap_lo <- 0.2
  .cap_hi <- 5
  .ok <- which(is.finite(pred$OR) & pred$OR >= .cap_lo & pred$OR <= .cap_hi)
  if (length(.ok) >= 6L) {
    .runs <- split(.ok, cumsum(c(1L, diff(.ok) != 1L)))
    .score <- function(ii) {
      length(ii) + if (min(pred$x[ii]) <= 0 && max(pred$x[ii]) >= 0) 1e4 else 0
    }
    .best <- .runs[[which.max(vapply(.runs, .score, numeric(1)))]]
    pred <- pred[.best, , drop = FALSE]
  } else {
    .ord <- order(abs(log(pmax(pred$OR, 1e-12))))
    pred <- pred[.ord[seq_len(min(50L, nrow(pred)))], , drop = FALSE]
    pred <- pred[order(pred$x), , drop = FALSE]
    pred$OR <- pmin(pmax(pred$OR, .cap_lo), .cap_hi)
  }
  pred$OR_d <- pred$OR
  pred$lo_d <- pred$OR / 2
  pred$hi_d <- pred$OR * 2
  y_min <- min(pred$OR_d, na.rm = TRUE)
  y_max <- max(pred$OR_d, na.rm = TRUE)
  cand <- as.numeric(t(outer(c(1, 2, 5), 10^seq(-3, 2))))
  or_lo <- max(cand[cand <= y_min / 1.5], 0.05)
  or_hi <- min(cand[cand >= y_max * 1.5], 20)
  if (!(is.finite(or_lo) && is.finite(or_hi) && or_lo < or_hi)) {
    or_lo <- max(y_min / 2, 0.05); or_hi <- min(y_max * 2, 20)
  }
  # ribbon 进框，并多留上边距，避免刻度/CI 贴顶
  or_lo <- min(or_lo, min(pred$lo_d, na.rm = TRUE) / 1.15)
  or_hi <- max(or_hi, max(pred$hi_d, na.rm = TRUE) * 1.35)
  or_lo <- max(or_lo, 0.05); or_hi <- min(or_hi, 20)
  if (or_hi / or_lo < 4) or_hi <- min(or_lo * 5, 20)
  pred$lo_d <- pmin(pmax(pred$lo_d, or_lo * 1.05), or_hi / 1.08)
  pred$hi_d <- pmin(pmax(pred$hi_d, or_lo * 1.05), or_hi / 1.08)
  pred$OR_d <- pmin(pmax(pred$OR_d, or_lo * 1.05), or_hi / 1.08)
  x_lim <- range(pred$x, na.rm = TRUE)
  x_pad <- diff(x_lim) * 0.10
  if (!is.finite(x_pad) || x_pad <= 0) x_pad <- 0.05
  x_lim <- c(x_lim[1] - x_pad, x_lim[2] + x_pad)
  list(pred = pred, x_lim = x_lim, d = d, p_overall = p_overall, p_nonlin = p_nonlin,
       note = note, expose = expose, or_lo = or_lo, or_hi = or_hi)
}

.rcs_draw_panel <- function(fit_obj, panel_lab) {
  pred <- fit_obj$pred
  x_lim <- fit_obj$x_lim
  d <- fit_obj$d
  or_lo <- fit_obj$or_lo
  or_hi <- fit_obj$or_hi

  hx <- d$x[d$x >= x_lim[1] & d$x <= x_lim[2]]
  if (!length(hx)) hx <- d$x
  br <- pretty(range(hx, na.rm = TRUE), n = 24)
  h <- hist(hx, breaks = br, plot = FALSE)
  h_df <- data.frame(xmin = head(h$breaks, -1), xmax = tail(h$breaks, -1), count = h$counts)
  h_df$ymin <- or_lo
  h_df$ymax <- or_lo * (or_hi / or_lo)^(0.18 * h_df$count / max(h_df$count, 1))

  lab <- sprintf("P for overall: %s\nP for non-linearity: %s",
                 .fmt_p(fit_obj$p_overall), .fmt_p(fit_obj$p_nonlin))
  xlab <- sprintf("%s Z-score", .disp(fit_obj$expose))
  brks <- c(0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50)
  brks <- brks[brks >= or_lo * 0.999 & brks <= or_hi * 1.001]
  if (length(brks) < 3L) brks <- pretty(c(or_lo, or_hi), n = 5)

  ggplot() +
    geom_rect(data = h_df, aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
              fill = "#9ECAE1", color = NA, alpha = 0.50) +
    geom_ribbon(data = pred, aes(x = x, ymin = lo_d, ymax = hi_d),
                fill = "#FCBBA1", alpha = 0.40) +
    geom_line(data = pred, aes(x = x, y = OR_d),
              color = "#CB181D", linewidth = 0.95) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey45", linewidth = 0.55) +
    geom_vline(xintercept = 0, linetype = 2, color = "grey45", linewidth = 0.55) +
    annotate("text", x = -Inf, y = Inf, label = lab, hjust = -0.04, vjust = 1.25, size = 3.2) +
    scale_y_continuous(trans = "log10", breaks = brks, labels = as.character(brks)) +
    coord_cartesian(xlim = x_lim, ylim = c(or_lo, or_hi), clip = "on") +
    labs(title = panel_lab, x = xlab, y = "Odds Ratio") +
    theme_classic(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 13, hjust = 0, margin = margin(b = 2)),
      axis.title = element_text(size = 11, color = "black"),
      axis.text = element_text(size = 10, color = "black"),
      axis.line = element_line(color = "black", linewidth = 0.45),
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.55),
      plot.margin = margin(4, 8, 4, 4)
    )
}

.cov_fig3 <- c("Age", "Sex")
.fits3 <- list()
for (i in seq_along(.feats_fig23)) {
  f <- .feats_fig23[[i]]
  cov <- setdiff(.cov_fig3, f); cov <- cov[cov %in% names(.df)]
  rr <- tryCatch(.rcs_fit_one(.df, f, cov), error = function(e) {
    message("Fig3 fit fail ", f, ": ", conditionMessage(e)); NULL
  })
  if (is.null(rr)) rr <- tryCatch(.rcs_fit_one(.df, f, character(0)), error = function(e) NULL)
  if (is.null(rr)) { message("Fig3 skip ", f); next }
  .fits3[[f]] <- rr
  message("Fig3 ok ", f,
          " P-overall=", .fmt_p(rr$p_overall),
          " P-nonlin=", .fmt_p(rr$p_nonlin),
          sprintf(" ylim=[%.2g,%.2g]", rr$or_lo, rr$or_hi),
          if (!is.null(rr$note)) paste0(" [", rr$note, "]") else "")
}
if (!length(.fits3)) stop("Fig3: no RCS panels")
.rcs_panels <- lapply(seq_along(.fits3), function(i) {
  .rcs_draw_panel(.fits3[[i]], LETTERS[[i]])
})
.n3 <- length(.rcs_panels)
# 五张：上排 A–C，下排 D–E（右下空位）
if (.n3 == 5L) {
  .fig3 <- wrap_plots(
    .rcs_panels[[1]], .rcs_panels[[2]], .rcs_panels[[3]],
    .rcs_panels[[4]], .rcs_panels[[5]], plot_spacer(),
    ncol = 3, nrow = 2
  )
  .w3 <- 12.6; .h3 <- 7.2
} else if (.n3 <= 3L) {
  .fig3 <- wrap_plots(.rcs_panels, nrow = 1, widths = rep(1, .n3))
  .w3 <- 4.15 * .n3 + 0.3; .h3 <- 3.55
} else {
  .fig3 <- wrap_plots(.rcs_panels, ncol = 3)
  .w3 <- 12.6; .h3 <- 3.55 * ceiling(.n3 / 3)
}
.save_pdf_png(.fig3, file.path(.fig, "pdf", "Figure 3. RCS of continuous features.pdf"),
              .w3, .h3)
writeLines(c(
  "Fig3 = Chen-style; OR display capped [0.05,20] so D/E do not pierce frame.",
  "Layout: 5 panels → row1 A–C, row2 D–E.",
  "x = 20-80% Z-score (+include 0). Adjusted Age+Sex; pre-specified continuous only."
), file.path(.tab, "Methods_fig3_and_nomogram_selection.txt"))

# ===================== 临床预指定 + Ridge Fig4 + Firth MV + Nomogram =====================
message("→ Prespec + Ridge / Firth MV / Nomogram …")
.y01 <- function(d) {
  y <- d[[.out]]
  if (is.factor(y)) as.integer(y == "Yes") else as.integer(as.numeric(y) == 1L)
}
.use <- .prespec[.prespec %in% names(.train)]
message("Nomogram features (clinically pre-specified): ", paste(.use, collapse = ", "))
message("NOTE: CT%/ct_max/shape/stone_type excluded from prediction by pre-specification (near-separation risk).")
.mm <- model.matrix(~ ., data = .train[, .use, drop = FALSE])[, -1, drop = FALSE]
for (j in seq_len(ncol(.mm))) {
  s <- stats::sd(.mm[, j]); if (is.finite(s) && s > 0) .mm[, j] <- as.numeric(scale(.mm[, j]))
}
set.seed(42)
.cv <- glmnet::cv.glmnet(
  .mm, .y01(.train), family = "binomial", alpha = 0,
  nfolds = 10, type.measure = "deviance", standardize = FALSE
)
.fit_ridge <- .cv$glmnet.fit
.coefs <- as.matrix(coef(.cv, s = "lambda.1se"))
.sel <- data.frame(
  feature = setdiff(rownames(.coefs), "(Intercept)"),
  ridge_coef = as.numeric(.coefs[setdiff(rownames(.coefs), "(Intercept)"), 1]),
  stringsAsFactors = FALSE
)
utils::write.csv(.sel, file.path(.tab, "Table_prespecified_ridge_coefficients.csv"), row.names = FALSE)
utils::write.csv(.sel, file.path(.proj, "Tables", "Table_prespecified_ridge_coefficients.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(predictor = .use, stringsAsFactors = FALSE),
  file.path(.tab, "Table_prespecified_predictors.csv"), row.names = FALSE
)
unlink(c(
  file.path(.fig, "pdf", "Figure 4. LASSO regression analysis.pdf"),
  file.path(.tab, "Table_LASSO_selected_lambda1se.csv"),
  file.path(.proj, "Tables", "Table_LASSO_selected_lambda1se.csv")
))

.save_pdf_png(function() {
  op <- par(mfrow = c(1, 2), mar = c(5, 4.5, 4, 1.5), oma = c(0, 0, 1, 0))
  plot(.fit_ridge, xvar = "lambda", label = FALSE)
  abline(v = log(.cv$lambda.1se), lty = 2, col = "firebrick", lwd = 1.5)
  mtext("A. Ridge coefficient paths", side = 3, line = 2.2, cex = 1, font = 2)
  plot(.cv)
  mtext("B. 10-fold CV (ridge, one-SE)", side = 3, line = 2.2, cex = 1, font = 2)
  par(op)
}, file.path(.fig, "pdf", "Figure 4. Ridge shrinkage of pre-specified predictors.pdf"), 11, 5)

# Multivariate Firth / brglm2
.dtr <- .train[, c(.out, .use), drop = FALSE]
.dtr$.y <- .y01(.dtr)
for (cc in intersect(.cats, .use)) .dtr[[cc]] <- factor(.dtr[[cc]])
.fml <- as.formula(paste(".y ~", paste(.use, collapse = "+")))
.mv <- tryCatch({
  if (requireNamespace("brglm2", quietly = TRUE))
    glm(.fml, data = .dtr, family = binomial(), method = brglm2::brglmFit)
  else glm(.fml, data = .dtr, family = binomial())
}, error = function(e) glm(.fml, data = .dtr, family = binomial()))
.sm <- summary(.mv)$coefficients
.tn <- setdiff(rownames(.sm), "(Intercept)")
.or <- exp(.sm[.tn, "Estimate"])
.se <- .sm[.tn, "Std. Error"]
.p <- .sm[.tn, ncol(.sm)]
.lo <- exp(.sm[.tn, "Estimate"] - 1.96 * .se)
.hi <- exp(.sm[.tn, "Estimate"] + 1.96 * .se)
.mv_tab <- data.frame(
  term = .tn, OR = as.numeric(.or), CI_low = as.numeric(.lo), CI_high = as.numeric(.hi),
  P = as.numeric(.p),
  OR_CI = mapply(.fmt_or, .or, .lo, .hi),
  stringsAsFactors = FALSE
)
utils::write.csv(.mv_tab, file.path(.tab, "Table 3. Multivariate logistic regression.csv"), row.names = FALSE)
utils::write.csv(.mv_tab, file.path(.proj, "Tables", "Table_multivariate_logistic.csv"), row.names = FALSE)

# Event(%) per term for forest — approximate from train
.event_lab <- function(term) {
  # continuous: overall; factor levels: stone_typeUnfavorable etc
  for (cc in intersect(.cats, .use)) {
    if (startsWith(term, cc)) {
      lev <- sub(paste0("^", cc), "", term)
      if (!nzchar(lev)) return("—")
      sub <- .dtr[[cc]] == lev
      if (!any(sub, na.rm = TRUE) && paste0(cc, lev) == term) {
        # model.matrix style stone_typeUnfavorable
      }
      # try match level
      lvls <- levels(factor(.dtr[[cc]]))
      hit <- lvls[paste0(cc, lvls) == term | lvls == lev]
      if (length(hit)) {
        sub <- as.character(.dtr[[cc]]) == hit[1]
        n <- sum(sub, na.rm = TRUE); ev <- sum(.dtr$.y[sub] == 1, na.rm = TRUE)
        return(sprintf("%d (%.1f)", ev, 100 * ev / max(1, n)))
      }
    }
  }
  # continuous overall
  sprintf("%d (%.1f)", sum(.dtr$.y), 100 * mean(.dtr$.y))
}
.mv_tab$Event <- vapply(.mv_tab$term, .event_lab, character(1))
.mv_tab$Variable <- .mv_tab$term

# ===================== Fig5：对齐 Chen FreeStatistics 多因素森林 =====================
# 原文：Variable | Event(%) | OR(95%CI) | 橙方块 log 森林 | P；顶底粗线；刻度疏
message("→ Fig5 Chen-style multivariate forest (forestploter) …")
.lbl_map5 <- c(
  Age = "Age, y",
  diameter_cm = "Diameter, cm",
  volume_cm3 = "Volume, cm3",
  energy_j = "Energy, J",
  shots = "Shots, n"
)
# 连续变量按临床单位缩放 OR，避免 energy/diameter 原始单位 OR≈0 把轴拉爆（对标 Chen 观感）
.unit5 <- c(Age = 10, diameter_cm = 0.5, volume_cm3 = 5, energy_j = 0.05, shots = 50)
.ev_overall5 <- sprintf("%d (%.1f)", sum(.dtr$.y == 1L, na.rm = TRUE),
                        100 * mean(.dtr$.y == 1L, na.rm = TRUE))
.mk5 <- function(var, event = "", or_txt = "", p_txt = "",
                 est = NA_real_, lo = NA_real_, hi = NA_real_, is_hdr = FALSE) {
  data.frame(
    Variable = as.character(var)[1L],
    `Event (%)` = as.character(event)[1L],
    `OR (95%CI)` = as.character(or_txt)[1L],
    ` ` = paste(rep(" ", 18L), collapse = ""),
    `P value` = as.character(p_txt)[1L],
    est = as.numeric(est)[1L], lo = as.numeric(lo)[1L], hi = as.numeric(hi)[1L],
    is_hdr = isTRUE(is_hdr),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
.fmt_or5 <- function(or, lo, hi, lo_floor = 0.05) {
  or <- as.numeric(or); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(or)) return("—")
  lo_s <- if (is.finite(lo) && lo < lo_floor) sprintf("<%.2g", lo_floor) else sprintf("%.2f", lo)
  hi_s <- if (is.finite(hi) && hi > 50) ">50" else sprintf("%.2f", hi)
  sprintf("%.2f (%s, %s)", or, lo_s, hi_s)
}
.rows5 <- list()
.sm5 <- summary(.mv)$coefficients
for (term in intersect(.use, rownames(.sm5))) {
  beta <- as.numeric(.sm5[term, "Estimate"])
  se <- as.numeric(.sm5[term, "Std. Error"])
  p <- as.numeric(.sm5[term, ncol(.sm5)])
  u <- if (term %in% names(.unit5)) .unit5[[term]] else 1
  or <- exp(beta * u); lo <- exp((beta - 1.96 * se) * u); hi <- exp((beta + 1.96 * se) * u)
  lab <- if (term %in% names(.lbl_map5)) {
    sprintf("%s (per %s)", .lbl_map5[[term]],
            if (u == 1) "1 unit" else as.character(u))
  } else term
  # 简化显示：Age, y (per 10) 等
  lab <- switch(term,
    Age = "Age, y (per 10)",
    diameter_cm = "Diameter, cm (per 0.5)",
    volume_cm3 = "Volume, cm3 (per 5)",
    energy_j = "Energy, J (per 0.05)",
    shots = "Shots, n (per 50)",
    lab
  )
  .rows5[[length(.rows5) + 1L]] <- .mk5(
    lab, .ev_overall5, .fmt_or5(or, lo, hi), .fmt_p(p), or, lo, hi, FALSE
  )
}
.plot5 <- do.call(rbind, .rows5)
rownames(.plot5) <- NULL
.disp_cols5 <- c("Variable", "Event (%)", "OR (95%CI)", " ", "P value")
.disp5 <- .plot5[, .disp_cols5, drop = FALSE]
.disp5[["P value"]] <- ifelse(
  nzchar(as.character(.disp5[["P value"]])),
  paste0(as.character(.disp5[["P value"]]), "  "),
  paste(rep(" ", 8L), collapse = "")
)
.est5 <- as.numeric(.plot5$est)
.lo5 <- as.numeric(.plot5$lo)
.hi5 <- as.numeric(.plot5$hi)
.bad5 <- !(is.finite(.est5) & is.finite(.lo5) & is.finite(.hi5) & .est5 > 0 & .lo5 > 0 & .hi5 > 0)
.est5[.bad5] <- .lo5[.bad5] <- .hi5[.bad5] <- NA_real_
# 对标原文刻度风格（疏、可读）；xlim 随 per-unit OR 收窄
.xlim5 <- c(0.1, 8)
.ticks5 <- c(0.1, 0.5, 1, 2, 8)
.lo_d5 <- pmax(.lo5, .xlim5[1] * 0.999)
.hi_d5 <- pmin(.hi5, .xlim5[2] * 1.001)
.est_d5 <- pmin(pmax(.est5, .xlim5[1]), .xlim5[2])
.lo_d5[!is.finite(.lo5)] <- NA_real_
.hi_d5[!is.finite(.hi5)] <- NA_real_
.est_d5[!is.finite(.est5)] <- NA_real_

.tm5 <- forestploter::forest_theme(
  base_size = 12,
  refline_gp = grid::gpar(lty = 2, col = "grey60", lwd = 1),
  ci_pch = 15, ci_col = "grey20", ci_fill = "#F39C12", ci_alpha = 1,
  ci_lty = 1, ci_lwd = 1.35, ci_Theight = 0.18,
  core = list(
    fg_params = list(hjust = 0, x = 0.02),
    bg_params = list(fill = c("white", "white")),
    # 行间距加大（上下 padding）
    padding = grid::unit(c(3.6, 1.2), "mm")
  ),
  colhead = list(
    fg_params = list(hjust = 0, x = 0.02, fontface = "bold"),
    padding = grid::unit(c(3.2, 1.2), "mm")
  ),
  xaxis_gp = grid::gpar(fontsize = 10, col = "grey20")
)
.p5 <- forestploter::forest(
  .disp5,
  est = .est_d5, lower = .lo_d5, upper = .hi_d5,
  sizes = 0.50,
  ci_column = which(.disp_cols5 == " ")[1L],
  ref_line = 1,
  xlim = .xlim5,
  ticks_at = .ticks5,
  x_trans = "log",
  xlab = "Odds Ratio (95%CI)",
  theme = .tm5
)
.p5 <- forestploter::edit_plot(.p5, part = "header", gp = grid::gpar(fontface = "bold"))
if (!is.null(.p5$layout) && "clip" %in% names(.p5$layout)) .p5$layout$clip[] <- "off"
# 再拉高表体行，避免行距过紧
try({
  .hh5 <- grid::convertHeight(.p5$heights, "mm", valueOnly = TRUE)
  .n5h <- length(.hh5)
  if (.n5h >= 5L) {
    for (.i5 in 2:(.n5h - 2L)) {
      .p5$heights[.i5] <- grid::unit(.hh5[.i5] * 1.45, "mm")
    }
  }
}, silent = TRUE)

.fig5_pdf <- file.path(.fig, "pdf", "Figure 5. Multivariate logistic regression.pdf")
.fig5_png <- file.path(.fig, "png", "Figure 5. Multivariate logistic regression.png")
dir.create(dirname(.fig5_pdf), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(.fig5_png), recursive = TRUE, showWarnings = FALSE)
# 紧贴 get_wh，去掉额外留白；导出后按内容紧裁再回写 PDF
.wh5 <- tryCatch(forestploter::get_wh(.p5), error = function(e) c(10.5, 3.2))
.w5 <- max(as.numeric(.wh5[1]), 9.5)
.h5 <- max(as.numeric(.wh5[2]) * 1.05, 3.2)
.draw5 <- function() {
  grid::grid.newpage()
  grid::grid.draw(.p5)
}
grDevices::pdf(.fig5_pdf, width = .w5, height = .h5, useDingbats = FALSE)
.draw5()
grDevices::dev.off()
grDevices::png(.fig5_png, width = .w5, height = .h5, units = "in", res = 300, bg = "white")
.draw5()
grDevices::dev.off()
# 紧裁白边（尤其底部），画布贴内容
.trim_png_white(.fig5_png, pad = 4L, thr = 248L)
.im5 <- tryCatch(png::readPNG(.fig5_png), error = function(e) NULL)
if (!is.null(.im5)) {
  .w5 <- dim(.im5)[2] / 300
  .h5 <- dim(.im5)[1] / 300
  grDevices::pdf(.fig5_pdf, width = .w5, height = .h5, useDingbats = FALSE)
  grid::grid.raster(.im5, interpolate = TRUE)
  grDevices::dev.off()
  grDevices::png(.fig5_png, width = .w5, height = .h5, units = "in", res = 300, bg = "white")
  grid::grid.raster(.im5, interpolate = TRUE)
  grDevices::dev.off()
}
message(sprintf("Fig5 Chen forestploter: %.2fx%.2f in, n_rows=%d", .w5, .h5, nrow(.plot5)))
.mirror_fig5 <- function(src, dests) {
  for (d in dests) {
    dest <- file.path(d, basename(src))
    if (!file.exists(src)) next
    if (normalizePath(dirname(src), winslash = "/", mustWork = FALSE) ==
        normalizePath(d, winslash = "/", mustWork = FALSE)) next
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(src, dest, overwrite = TRUE)
  }
}
.mirror_fig5(.fig5_pdf, c(
  file.path(.proj, "Figures", "pdf"),
  file.path(.proj, "_shared", "Figures", "pdf"),
  file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "pdf")
))
.mirror_fig5(.fig5_png, c(
  file.path(.proj, "Figures", "png"),
  file.path(.proj, "_shared", "Figures", "png"),
  file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "png")
))
writeLines(c(
  "Fig5 = Chen FreeStatistics multivariate forest (forestploter).",
  "Columns: Variable | Event(%) | OR(95%CI) | forest | P value; orange squares; log axis.",
  "Continuous OR scaled to clinical units (Age/10, Diameter/0.5, Volume/5, Energy/0.05, Shots/50)",
  "to avoid raw-unit near-separation OR≈0 collapsing the axis (Methods note).",
  "Event(%) = training-set overall events for continuous rows."
), file.path(.tab, "Methods_fig5_layout.txt"))

# Fig6：对标 Chen FreeStatistics 列线图
# Firth 近分离使 energy 轴畸形；列线图改用 ridge(λ.1se) 系数（与 Fig4 一致）+ 自绘 Chen 版式
message("→ Fig6 Chen-style nomogram (vars=", paste(.use, collapse = ", "), ") …")
.dn <- .dtr
.use6 <- .use
.lab6 <- c(
  Age = "Age",
  diameter_cm = "Diameter (cm)",
  volume_cm3 = "Volume (cm\u00b3)",
  energy_j = "Energy (J)",
  shots = "Shots"
)
.fig6_pdf <- file.path(.fig, "pdf", "Figure 6. Nomogram prediction model.pdf")
.fig6_png <- file.path(.fig, "png", "Figure 6. Nomogram prediction model.png")
dir.create(dirname(.fig6_pdf), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(.fig6_png), recursive = TRUE, showWarnings = FALSE)

# ---- ridge λ.1se 系数（原始尺度）----
.X6 <- as.matrix(.dn[, .use6, drop = FALSE])
storage.mode(.X6) <- "double"
.y6 <- as.integer(.dn$.y)
.set_seed6 <- tryCatch(as.integer(.cfg$gallstone_nomogram$seed %||% 42L), error = function(e) 42L)
set.seed(.set_seed6)
.cv6 <- glmnet::cv.glmnet(.X6, .y6, family = "binomial", alpha = 0, standardize = TRUE, nfolds = 10L)
.b6 <- as.numeric(coef(.cv6, s = "lambda.1se"))
names(.b6) <- rownames(coef(.cv6, s = "lambda.1se"))
.b0 <- as.numeric(.b6[["(Intercept)"]])
.beta <- setNames(as.numeric(.b6[.use6]), .use6)

# ---- Harrell Points：每变量独立平移，使轴从 0 起向右（对标 Chen 分类轴）----
.ref6 <- sapply(.use6, function(v) min(as.numeric(.dn[[v]]), na.rm = TRUE))
.rng6 <- sapply(.use6, function(v) diff(range(as.numeric(.dn[[v]]), na.rm = TRUE)))
.span_lp <- abs(.beta) * .rng6
.scale6 <- max(.span_lp, na.rm = TRUE) / 100
if (!is.finite(.scale6) || .scale6 <= 0) .scale6 <- 1
.points_raw <- function(v, x) .beta[[v]] * (x - .ref6[[v]]) / .scale6
.pt_shift_v <- sapply(.use6, function(v) {
  xr <- range(as.numeric(.dn[[v]]), na.rm = TRUE)
  -min(.points_raw(v, xr[1]), .points_raw(v, xr[2]))
})
.points_at0 <- function(v, x) .points_raw(v, x) + .pt_shift_v[[v]]

.tick6 <- list()
for (v in .use6) {
  xr <- range(as.numeric(.dn[[v]]), na.rm = TRUE)
  dig <- if (diff(xr) <= 2) 2L else if (diff(xr) <= 30) 1L else 0L
  n_keep <- if (.span_lp[[v]] / max(.span_lp) < 0.12) 4L else 6L
  .tick6[[v]] <- unique(round(seq(xr[1], xr[2], length.out = n_keep), dig))
}

.nshift <- sum(.pt_shift_v)
.lp_from_tp <- function(tp) {
  .b0 + sum(.beta * .ref6) + .scale6 * (tp - .nshift)
}
.risk_from_tp <- function(tp) stats::plogis(.lp_from_tp(tp))
.fun_at6 <- c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)
.tp_at_risk <- sapply(.fun_at6, function(r) {
  f <- function(tp) .risk_from_tp(tp) - r
  tryCatch(stats::uniroot(f, c(-50, 400))$root, error = function(e) NA_real_)
})
.tp_pat <- rowSums(vapply(.use6, function(v) .points_at0(v, as.numeric(.dn[[v]])), numeric(nrow(.dn))))
.tp_max_disp <- max(100, ceiling(max(c(.tp_at_risk, .tp_pat), na.rm = TRUE) / 50) * 50)
.pt_max_var <- sapply(.use6, function(v) {
  xr <- range(as.numeric(.dn[[v]]), na.rm = TRUE)
  max(.points_at0(v, xr[1]), .points_at0(v, xr[2]))
})

.draw6_chen <- function() {
  # Chen FreeStatistics：黑字变量名 + 蓝字刻度 + 密竖网(橙主/蓝细) + 紧凑行距 + 无 LP
  n_var <- length(.use6)
  row_gap <- 0.88
  y_pts <- n_var * row_gap + 1.85
  y_var <- setNames(seq(n_var, 1) * row_gap + 0.95, .use6)
  y_tp <- 0.48
  y_risk <- -0.32
  ylim <- c(-0.85, y_pts + 0.48)
  col_lab <- "black"
  col_tick <- "#1A5276"
  col_grid_minor <- "#D6EAF8"   # 每 2 分
  col_grid_major <- "#F5B7B1"   # 每 10 分（对标 Chen 粉橙主网）
  op <- graphics::par(
    mar = c(1.35, 6.0, 0.28, 0.40), oma = c(0.02, 0.02, 0.02, 0.02),
    xpd = NA, family = "sans", mgp = c(1.0, 0.20, 0)
  )
  on.exit(graphics::par(op), add = TRUE)
  graphics::plot(NA, xlim = c(-32, 100), ylim = ylim, axes = FALSE, xlab = "", ylab = "")
  # 密竖网贯穿 Points → Risk（Chen：蓝细分 + 粉橙主线）
  for (g in seq(0, 100, by = 2)) {
    is_maj <- (g %% 10L == 0L)
    graphics::segments(
      g, y_risk - 0.30, g, y_pts + 0.10,
      col = if (is_maj) col_grid_major else col_grid_minor,
      lwd = if (is_maj) 0.85 else 0.45
    )
  }

  # Points
  graphics::segments(0, y_pts, 100, y_pts, lwd = 1.35, col = "black")
  for (g in seq(0, 100, by = 2)) {
    graphics::segments(g, y_pts, g, y_pts + if (g %% 10 == 0) 0.14 else 0.07, lwd = 0.75)
  }
  graphics::text(seq(0, 100, by = 10), y_pts + 0.30, labels = seq(0, 100, by = 10),
                 cex = 0.70, col = col_tick, font = 2)
  graphics::text(-30.5, y_pts, "Points", adj = 0, cex = 0.93, font = 2, col = col_lab)

  for (v in .use6) {
    y <- y_var[[v]]
    graphics::text(-30.5, y, .lab6[[v]] %||% v, adj = 0, cex = 0.90, font = 2, col = col_lab)
    tk <- .tick6[[v]]
    pts <- .points_at0(v, tk)
    graphics::segments(0, y, max(pts, 0.5), y, lwd = 1.05, col = "black")
    for (i in seq_along(tk)) {
      graphics::segments(pts[i], y - 0.08, pts[i], y + 0.08, lwd = 0.80)
      side <- if (i %% 2L == 1L) -1 else 1
      graphics::text(pts[i], y + side * 0.22, labels = format(tk[i], trim = TRUE),
                     cex = 0.68, col = col_tick, font = 2)
    }
  }

  graphics::text(-30.5, y_tp, "Total Points", adj = 0, cex = 0.90, font = 2, col = col_lab)
  .map_tp <- function(tp) 100 * as.numeric(tp) / .tp_max_disp
  graphics::segments(0, y_tp, 100, y_tp, lwd = 1.35, col = "black")
  .tp_step <- if (.tp_max_disp <= 150) 20 else if (.tp_max_disp <= 250) 25 else 50
  .tp_major <- seq(0, .tp_max_disp, by = .tp_step)
  .tp_minor <- seq(0, .tp_max_disp, by = max(5, .tp_step / 5))
  for (g in .tp_minor) {
    xg <- .map_tp(g)
    graphics::segments(xg, y_tp, xg, y_tp + if (g %in% .tp_major) 0.12 else 0.055, lwd = 0.7)
  }
  graphics::text(.map_tp(.tp_major), y_tp + 0.28, labels = .tp_major, cex = 0.66, col = col_tick, font = 2)

  graphics::text(-30.5, y_risk, "Risk of lithotripsy success", adj = 0, cex = 0.86, font = 2, col = col_lab)
  ok <- is.finite(.tp_at_risk)
  if (sum(ok) >= 2L) {
    xr <- .map_tp(range(.tp_at_risk[ok]))
    graphics::segments(xr[1], y_risk, xr[2], y_risk, lwd = 1.35, col = "black")
    for (i in which(ok)) {
      xg <- .map_tp(.tp_at_risk[i])
      graphics::segments(xg, y_risk - 0.08, xg, y_risk + 0.08, lwd = 0.80)
      side <- if (i %% 2L == 1L) -1 else 1
      graphics::text(xg, y_risk + side * 0.24, labels = .fun_at6[i],
                     cex = 0.68, col = col_tick, font = 2)
    }
  }
  graphics::box(lwd = 1.15, col = "black")
}

.w6 <- 11.0
.h6 <- max(4.8, 0.70 * length(.use6) + 2.35)
grDevices::pdf(.fig6_pdf, width = .w6, height = .h6, useDingbats = FALSE)
.draw6_chen()
grDevices::dev.off()
grDevices::png(.fig6_png, width = .w6, height = .h6, units = "in", res = 300, bg = "white")
.draw6_chen()
grDevices::dev.off()
.trim_png_white(.fig6_png, pad = 4L, thr = 248L)
.im6 <- tryCatch(png::readPNG(.fig6_png), error = function(e) NULL)
if (!is.null(.im6)) {
  .w6 <- dim(.im6)[2] / 300
  .h6 <- dim(.im6)[1] / 300
  grDevices::pdf(.fig6_pdf, width = .w6, height = .h6, useDingbats = FALSE)
  grid::grid.raster(.im6, interpolate = TRUE)
  grDevices::dev.off()
  grDevices::png(.fig6_png, width = .w6, height = .h6, units = "in", res = 300, bg = "white")
  grid::grid.raster(.im6, interpolate = TRUE)
  grDevices::dev.off()
}
message(sprintf(
  "Fig6 Chen nomogram (ridge): %.2fx%.2f in; risk TP [%.0f,%.0f]; TotalPoints 0-%d; lambda.1se=%.4g",
  .w6, .h6, min(.tp_at_risk, na.rm = TRUE), max(.tp_at_risk, na.rm = TRUE),
  as.integer(.tp_max_disp), .cv6$lambda.1se
))
utils::write.csv(
  data.frame(
    term = c("Intercept", .use6),
    coef = c(.b0, as.numeric(.beta)),
    points_span = c(NA_real_, as.numeric(.pt_max_var)),
    pt_shift = c(NA_real_, as.numeric(.pt_shift_v))
  ),
  file.path(.tab, "Table_nomogram_ridge_coefficients.csv"),
  row.names = FALSE
)
for (d in c(
  file.path(.proj, "Figures", "pdf"),
  file.path(.proj, "_shared", "Figures", "pdf"),
  file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "pdf")
)) {
  dest <- file.path(d, basename(.fig6_pdf))
  if (normalizePath(dirname(.fig6_pdf), winslash = "/", mustWork = FALSE) ==
      normalizePath(d, winslash = "/", mustWork = FALSE)) next
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.copy(.fig6_pdf, dest, overwrite = TRUE)
}
for (d in c(
  file.path(.proj, "Figures", "png"),
  file.path(.proj, "_shared", "Figures", "png"),
  file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures", "png")
)) {
  if (!file.exists(.fig6_png)) next
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.copy(.fig6_png, file.path(d, basename(.fig6_png)), overwrite = TRUE)
}
writeLines(c(
  "Fig6 = Chen FreeStatistics-style nomogram (custom drawer).",
  "Coefficients = ridge logistic lambda.1se (aligned with Fig4), NOT Firth MV:",
  "Firth near-separation collapses energy and squeezes Risk; ridge restores",
  "balanced predictor axes and Risk 0.1-0.9 spanning Total Points like Chen.",
  "Points mapping: per-variable shift so each axis starts at 0 (Chen categorical look).",
  "Aesthetics: black var names, blue tick labels, blue/peach vertical grid, compact rows, no LP.",
  paste0("Vars: ", paste(.use6, collapse = ", "), ".")
), file.path(.tab, "Methods_fig6_layout.txt"))
options(datadist = NULL)


# ===================== Fig7–9 =====================
message("→ Fig7 ROC+校准 | Fig8 DCA of nomogram… | Fig9 CIC of nomogram… …")
.align <- function(d, ref) {
  out <- d
  for (cc in intersect(.cats, names(out))) {
    if (cc %in% names(ref)) out[[cc]] <- factor(as.character(out[[cc]]), levels = levels(factor(ref[[cc]])))
  }
  out
}
.pred <- function(model, d, ref) {
  dd <- .align(d, ref)
  tryCatch(as.numeric(predict(model, newdata = dd, type = "response")),
           error = function(e) rep(NA_real_, nrow(dd)))
}
.auc <- function(y, p) {
  ok <- is.finite(y) & is.finite(p); y <- y[ok]; p <- p[ok]
  if (length(unique(y)) < 2) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE)))
}
.p_tr <- .pred(.mv, .train, .train); .y_tr <- .y01(.train)
.p_va <- .pred(.mv, .test, .train);  .y_va <- .y01(.test)
.full <- rbind(.train, .test)
set.seed(42)
.B <- 200L
.auc_b <- rep(NA_real_, .B)
.p_boot_mat <- matrix(NA_real_, nrow(.full), 40)
for (b in seq_len(.B)) {
  ii <- sample.int(nrow(.full), replace = TRUE)
  db <- .align(.full[ii, ], .train); db$.y <- .y01(db)
  fb <- tryCatch(glm(.fml, data = transform(db, .y = .y01(db)), family = binomial(), method = "brglmFit"),
                 error = function(e) tryCatch(glm(.fml, data = transform(db, .y = .y01(db)), family = binomial()), error = function(e2) NULL))
  if (is.null(fb)) next
  pb <- .pred(fb, .full, .train)
  .auc_b[b] <- .auc(.y01(.full), pb)
  if (b <= 40) .p_boot_mat[, b] <- pb
}
.p_boot <- rowMeans(.p_boot_mat, na.rm = TRUE)
.metrics <- data.frame(
  set = c("train", "internal_val", "bootstrap"),
  AUC = c(.auc(.y_tr, .p_tr), .auc(.y_va, .p_va), mean(.auc_b, na.rm = TRUE)),
  AUC_boot_lo = c(NA, NA, quantile(.auc_b, 0.025, na.rm = TRUE)),
  AUC_boot_hi = c(NA, NA, quantile(.auc_b, 0.975, na.rm = TRUE))
)
utils::write.csv(.metrics, file.path(.tab, "Table 4. Discrimination (AUC) train validation bootstrap.csv"), row.names = FALSE)
utils::write.csv(.metrics, file.path(.proj, "Tables", "Table_AUC_train_val_boot.csv"), row.names = FALSE)
message("AUC train/val/boot: ", paste(round(.metrics$AUC, 3), collapse = " / "))

# ---------- Fig7：对齐 Chen 2×3（A–C 橙 ROC+AUC CI；D–F 红 Loess 校准+intercept/slope/c）----------
# 无外验库时 C/F = Bootstrap（Methods 已锁定）；版式仍按原文六联
message("→ Fig7 Chen-style ROC + calibration (2×3) …")
.theme7 <- theme_bw(base_size = 10) +
  theme(
    panel.grid.major = element_line(color = "white", linewidth = 0.4),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "#F0F0F0", color = NA),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.55),
    plot.title = element_text(face = "bold", size = 10.5, hjust = 0.5),
    axis.title = element_text(size = 9.5),
    axis.text = element_text(size = 8.5, color = "black"),
    legend.position = "bottom",
    legend.background = element_rect(fill = "white", color = NA),
    legend.key = element_rect(fill = "white"),
    legend.text = element_text(size = 8),
    plot.margin = margin(4, 6, 4, 6)
  )
.auc_ci <- function(y, p, boot_auc = NULL) {
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  if (length(unique(y)) < 2L || length(y) < 5L) {
    return(list(auc = NA_real_, lo = NA_real_, hi = NA_real_,
                txt = "AUC: NA", roc = NULL))
  }
  r <- pROC::roc(y, p, quiet = TRUE)
  a <- as.numeric(pROC::auc(r))
  if (!is.null(boot_auc)) {
    a <- mean(as.numeric(boot_auc), na.rm = TRUE)
    lo <- as.numeric(stats::quantile(boot_auc, 0.025, na.rm = TRUE))
    hi <- as.numeric(stats::quantile(boot_auc, 0.975, na.rm = TRUE))
  } else {
    ci <- tryCatch(as.numeric(pROC::ci.auc(r, conf.level = 0.95, method = "delong")),
                   error = function(e) c(NA, a, NA))
    lo <- ci[1]; hi <- ci[3]
  }
  list(
    auc = a, lo = lo, hi = hi,
    txt = sprintf("AUC: %.3f (%.3f, %.3f)", a, lo, hi),
    roc = r
  )
}
.cal_stats <- function(y, p) {
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  p <- pmin(pmax(p, 1e-4), 1 - 1e-4)
  out <- list(intercept = NA, slope = NA, ilo = NA, ihi = NA, slo = NA, shi = NA,
              c = NA, clo = NA, chi = NA, txt = "Calibration\nNA")
  if (length(unique(y)) < 2L || length(y) < 8L) return(out)
  lp <- stats::qlogis(p)
  fit <- tryCatch(stats::glm(y ~ lp, family = stats::binomial()), error = function(e) NULL)
  if (!is.null(fit)) {
    cf <- stats::coef(fit)
    ci <- tryCatch(stats::confint.default(fit), error = function(e) NULL)
    out$intercept <- unname(cf[1]); out$slope <- unname(cf[2])
    if (!is.null(ci)) {
      out$ilo <- ci[1, 1]; out$ihi <- ci[1, 2]
      out$slo <- ci[2, 1]; out$shi <- ci[2, 2]
    }
  }
  ac <- .auc_ci(y, p)
  out$c <- ac$auc; out$clo <- ac$lo; out$chi <- ac$hi
  out$txt <- paste0(
    "Calibration\n",
    sprintf("intercept: %.2f (%.2f to %.2f)\n", out$intercept %||% NA, out$ilo %||% NA, out$ihi %||% NA),
    sprintf("slope: %.2f (%.2f to %.2f)\n", out$slope %||% NA, out$slo %||% NA, out$shi %||% NA),
    "Discrimination\n",
    sprintf("c-statistic: %.2f (%.2f to %.2f)", out$c %||% NA, out$clo %||% NA, out$chi %||% NA)
  )
  out
}
.roc_panel <- function(y, p, letter, title, boot_auc = NULL) {
  ac <- .auc_ci(y, p, boot_auc = boot_auc)
  if (is.null(ac$roc)) {
    return(ggplot() + theme_void() + labs(title = paste0(letter, ". ", title)))
  }
  rd <- data.frame(
    fpr = 1 - rev(ac$roc$specificities),
    sens = rev(ac$roc$sensitivities)
  )
  # 闭合填充到对角下沿
  poly <- rbind(
    data.frame(fpr = 0, sens = 0),
    rd,
    data.frame(fpr = 1, sens = 0)
  )
  ggplot() +
    geom_polygon(data = poly, aes(fpr, sens), fill = "#F5CBA7", alpha = 0.28, color = NA) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey55", linewidth = 0.55) +
    geom_step(data = rd, aes(fpr, sens), color = "#E67E22", linewidth = 0.85, direction = "hv") +
    annotate("text", x = 0.50, y = 0.38, label = ac$txt, fontface = "bold", size = 3.15, hjust = 0.5) +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    labs(title = title, x = "1 - Specificity", y = "Sensitivity") +
    .theme7 +
    theme(plot.title = element_text(face = "plain", size = 10, hjust = 0.5))
}
.cal_panel <- function(y, p, letter, title) {
  ok <- is.finite(y) & is.finite(p)
  d <- data.frame(pred = p[ok], obs = as.integer(y[ok]))
  d$pred_c <- pmin(pmax(d$pred, 1e-3), 1 - 1e-3)
  st <- .cal_stats(d$obs, d$pred)
  d0 <- d[d$obs == 0, , drop = FALSE]
  d1 <- d[d$obs == 1, , drop = FALSE]
  .ideal <- data.frame(pred_c = c(0, 1), obs = c(0, 1), typ = "Ideal")
  ggplot(d, aes(pred_c, obs)) +
    geom_line(
      data = .ideal, aes(pred_c, obs, color = typ, linetype = typ),
      linewidth = 0.55, inherit.aes = FALSE
    ) +
    geom_smooth(
      aes(color = "Flexible calibration (Loess)", linetype = "Flexible calibration (Loess)"),
      method = "loess", formula = y ~ x, se = TRUE, span = 0.85,
      fill = "#F5B7B1", linewidth = 0.85, alpha = 0.35
    ) +
    geom_rug(data = d0, aes(x = pred_c), inherit.aes = FALSE,
             sides = "b", color = "grey35", alpha = 0.45, linewidth = 0.25,
             length = unit(0.035, "npc")) +
    geom_rug(data = d1, aes(x = pred_c), inherit.aes = FALSE,
             sides = "b", color = "grey35", alpha = 0.45, linewidth = 0.25,
             length = unit(0.020, "npc"),
             position = position_nudge(y = 0.045)) +
    annotate("text", x = 0.02, y = 0.98, label = st$txt, hjust = 0, vjust = 1,
             size = 2.55, lineheight = 0.95) +
    scale_color_manual(
      name = NULL,
      values = c("Ideal" = "grey40", "Flexible calibration (Loess)" = "#C0392B"),
      breaks = c("Ideal", "Flexible calibration (Loess)")
    ) +
    scale_linetype_manual(
      name = NULL,
      values = c("Ideal" = "dashed", "Flexible calibration (Loess)" = "solid"),
      breaks = c("Ideal", "Flexible calibration (Loess)")
    ) +
    guides(color = guide_legend(override.aes = list(fill = NA, linewidth = 0.8)),
           linetype = guide_legend(override.aes = list(fill = NA))) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
    labs(title = title, x = "Predicted probability", y = "Observed proportion") +
    .theme7 +
    theme(
      plot.title = element_text(face = "plain", size = 10, hjust = 0.5),
      legend.position = c(0.98, 0.08),
      legend.justification = c(1, 0),
      legend.margin = margin(0, 0, 0, 0),
      legend.key.size = unit(0.32, "cm"),
      legend.background = element_rect(fill = "#FFFFFFCC", color = NA)
    )
}
.p7A <- .roc_panel(.y_tr, .p_tr, "A", "Train ROC")
.p7B <- .roc_panel(.y_va, .p_va, "B", "Validation ROC")
.p7C <- .roc_panel(.y01(.full), .p_boot, "C", "Bootstrap ROC", boot_auc = .auc_b)
.p7D <- .cal_panel(.y_tr, .p_tr, "D", "Training")
.p7E <- .cal_panel(.y_va, .p_va, "E", "Validation")
.p7F <- .cal_panel(.y01(.full), .p_boot, "F", "Bootstrap")
.fig7 <- (.p7A | .p7B | .p7C) / (.p7D | .p7E | .p7F) +
  plot_annotation(
    tag_levels = "A",
    theme = theme(
      plot.margin = margin(2, 2, 2, 2),
      plot.tag = element_text(face = "bold", size = 12)
    )
  ) &
  theme(plot.tag.position = c(0.01, 0.98))
.fig7_pdf <- file.path(.fig, "pdf", "Figure 7. ROC and calibration.pdf")
.fig7_png <- file.path(.fig, "png", "Figure 7. ROC and calibration.png")
.save_pdf_png(.fig7, .fig7_pdf, 12.2, 8.4)
tryCatch({
  ggplot2::ggsave(.fig7_png, .fig7, width = 12.2, height = 8.4, dpi = 200, bg = "white")
  .trim_png_white(.fig7_png, pad = 6L, thr = 250L)
}, error = function(e) message("Fig7 png: ", conditionMessage(e)))
writeLines(c(
  "Fig7 = Chen-style 2x3: A–C orange ROC + AUC(CI); D–F red Loess calibration + intercept/slope/c.",
  "Panel C/F = Bootstrap (no external cohort; locked). Grey panel + white grid like Chen FreeStatistics.",
  "AUC CI: DeLong (train/val); bootstrap percentile (panel C)."
), file.path(.tab, "Methods_fig7_layout.txt"))
message("Fig7 Chen-style 2x3 done")

# ---------- Fig8：对齐 Chen FreeStatistics DCA（Standardized NB + Cost:Benefit + CI）----------
message("→ Fig8 Chen-style DCA …")
.nb_raw <- function(y, p, thr) {
  y <- as.integer(y); p <- as.numeric(p)
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  if (!length(y) || !any(y == 1L)) return(c(model = NA_real_, all = NA_real_, none = 0))
  prev <- mean(y == 1L)
  thr <- min(max(as.numeric(thr), 1e-6), 1 - 1e-6)
  tp <- mean(p > thr & y == 1L)
  fp <- mean(p > thr & y == 0L)
  c(
    model = tp - fp * thr / (1 - thr),
    all = prev - (1 - prev) * thr / (1 - thr),
    none = 0
  )
}
.dca_chen_one <- function(y, p, panel, n_boot = 200L, seed = 42L) {
  y <- as.integer(y); p <- as.numeric(p)
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  prev <- mean(y == 1L)
  if (!is.finite(prev) || prev <= 0) prev <- 1
  th <- seq(0.01, 0.99, by = 0.01)
  nb_m <- vapply(th, function(t) .nb_raw(y, p, t)[["model"]], numeric(1))
  nb_a <- vapply(th, function(t) .nb_raw(y, p, t)[["all"]], numeric(1))
  set.seed(seed)
  boot_mat <- matrix(NA_real_, n_boot, length(th))
  n <- length(y)
  for (b in seq_len(n_boot)) {
    ii <- sample.int(n, replace = TRUE)
    yb <- y[ii]; pb <- p[ii]
    boot_mat[b, ] <- vapply(th, function(t) .nb_raw(yb, pb, t)[["model"]], numeric(1))
  }
  lo <- apply(boot_mat, 2, stats::quantile, probs = 0.025, na.rm = TRUE)
  hi <- apply(boot_mat, 2, stats::quantile, probs = 0.975, na.rm = TRUE)
  # 轻平滑 CI，贴近 FreeStatistics 细线观感（避免锯齿色带）
  lo_s <- tryCatch(stats::lowess(th, lo, f = 0.18)$y, error = function(e) lo)
  hi_s <- tryCatch(stats::lowess(th, hi, f = 0.18)$y, error = function(e) hi)
  # 主曲线轻平滑（显示层）：贴近 FreeStatistics 观感，避免逐步跳齿
  m_s <- tryCatch(stats::lowess(th, nb_m, f = 0.10)$y, error = function(e) nb_m)
  a_s <- nb_a  # treat-all 为光滑解析式，不需平滑
  std_m <- pmin(pmax(m_s / prev, -0.05), 1.05)
  std_lo <- pmin(pmax(lo_s / prev, -0.05), 1.05)
  std_hi <- pmin(pmax(hi_s / prev, -0.05), 1.05)
  # 保证 lo <= model <= hi
  std_lo <- pmin(std_lo, std_m)
  std_hi <- pmax(std_hi, std_m)
  data.frame(
    thr = th,
    std_model = std_m,
    std_lo = std_lo,
    std_hi = std_hi,
    std_all = a_s / prev,
    std_none = 0,
    panel = panel,
    stringsAsFactors = FALSE
  )
}
.dd8 <- rbind(
  .dca_chen_one(.y_tr, .p_tr, "Train set", n_boot = 200L, seed = 42L),
  .dca_chen_one(.y_va, .p_va, "Internal validation set", n_boot = 200L, seed = 43L),
  .dca_chen_one(.y01(.full), .p_boot, "Bootstrap", n_boot = 200L, seed = 44L)
)
.dd8$panel <- factor(
  .dd8$panel,
  levels = c("Train set", "Internal validation set", "Bootstrap")
)
# Chen FreeStatistics：Cost:Benefit 标签对齐在 0/0.2/…/1 主刻度下（非 1/101 精确点）
.cb_breaks <- c(0, 0.2, 0.4, 0.6, 0.8, 1.0)
.cb_labs <- c("1:100", "1:4", "2:3", "3:2", "4:1", "100:1")




.theme8 <- theme_bw(base_size = 11) +
  theme(
    panel.grid.major = element_line(color = "grey88", linewidth = 0.30),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "white", color = NA),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.55),
    plot.title = element_text(face = "bold", size = 13, hjust = 0, margin = margin(b = 1)),
    axis.title = element_text(size = 9.5),
    axis.title.x.top = element_text(size = 9.5, margin = margin(b = 2)),
    axis.title.x.bottom = element_text(size = 9.5, margin = margin(t = 3)),
    axis.text = element_text(size = 8, color = "black"),
    axis.text.x.bottom = element_text(size = 7.2),
    axis.text.x.top = element_text(size = 8),
    legend.position = "none",
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.35),
    legend.key = element_rect(fill = "white", color = NA),
    legend.key.width = unit(1.15, "cm"),
    legend.key.height = unit(0.28, "cm"),
    legend.text = element_text(size = 8.5),
    legend.title = element_blank(),
    plot.margin = margin(4, 6, 4, 4),
    plot.background = element_rect(fill = "white", color = NA)
  )
.dca_panel_plot <- function(df, letter) {
  # 裁进 [0,1]，避免 All 负值穿出图框（对标 Chen）
  df <- df
  df$std_model <- pmin(pmax(df$std_model, 0), 1)
  df$std_lo <- pmin(pmax(df$std_lo, 0), 1)
  df$std_hi <- pmin(pmax(df$std_hi, 0), 1)
  df$std_all <- pmin(pmax(df$std_all, 0), 1)
  dlong <- rbind(
    data.frame(thr = df$thr, y = df$std_model, curve = "Prediction nomogram", stringsAsFactors = FALSE),
    data.frame(thr = df$thr, y = df$std_all, curve = "All", stringsAsFactors = FALSE),
    # None 略抬到 0.012，避免被底轴黑线完全盖住（视觉仍≈0）
    data.frame(thr = df$thr, y = rep(0.012, nrow(df)), curve = "None", stringsAsFactors = FALSE)
  )
  dlong$curve <- factor(dlong$curve, levels = c("Prediction nomogram", "All", "None"))
  ggplot() +
    geom_line(data = df, aes(thr, std_lo), color = "#7FB3D5", linewidth = 0.45, inherit.aes = FALSE) +
    geom_line(data = df, aes(thr, std_hi), color = "#7FB3D5", linewidth = 0.45, inherit.aes = FALSE) +
    geom_line(data = subset(dlong, curve == "All"), aes(thr, y, color = curve), linewidth = 0.55) +
    geom_line(data = subset(dlong, curve == "None"), aes(thr, y, color = curve), linewidth = 0.90) +
    geom_line(data = subset(dlong, curve == "Prediction nomogram"), aes(thr, y, color = curve), linewidth = 1.15) +
    scale_color_manual(
      values = c("Prediction nomogram" = "#1A5276", "All" = "grey40", "None" = "#E74C3C"),
      breaks = c("Prediction nomogram", "All", "None")
    ) +
    # 对标 Chen：上轴 High Risk Threshold，下轴 Cost:Benefit Ratio
    scale_x_continuous(
      name = "Cost:Benefit Ratio",
      limits = c(0, 1),
      breaks = .cb_breaks,
      labels = .cb_labs,
      expand = c(0, 0),
      sec.axis = dup_axis(
        name = "High Risk Threshold",
        breaks = seq(0, 1, by = 0.2),
        labels = sprintf("%.1f", seq(0, 1, by = 0.2))
      )
    ) +
    scale_y_continuous(
      name = "Standardized Net Benefit",
      breaks = seq(0, 1, by = 0.2),
      labels = sprintf("%.1f", seq(0, 1, by = 0.2)),
      expand = c(0, 0)
    ) +
    # clip=on：线不出界（此前 clip=off 为画底轴导致 All 穿框）
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), clip = "on") +
    labs(title = paste0(letter, ".")) +
    guides(color = guide_legend(override.aes = list(linewidth = c(1.15, 0.55, 0.90)))) +
    .theme8
}
.p8A <- .dca_panel_plot(subset(.dd8, panel == "Train set"), "A")
.p8B <- .dca_panel_plot(subset(.dd8, panel == "Internal validation set"), "B")
.p8C <- .dca_panel_plot(subset(.dd8, panel == "Bootstrap"), "C")
# 共享底图例，避开图内挡线；三栏等宽方形感
.fig8 <- (.p8A | .p8B | .p8C) +
  plot_layout(widths = c(1, 1, 1), guides = "collect") &
  theme(
    legend.position = "bottom",
    legend.direction = "horizontal",
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.35),
    legend.box.margin = margin(6, 4, 2, 4),
    legend.spacing.x = unit(0.65, "cm")
  )

.fig8_stem <- "Figure 8. DCA of nomogram prediction model for lithotripsy success"
.fig8_pdf <- file.path(.fig, "pdf", paste0(.fig8_stem, ".pdf"))
.fig8_png <- file.path(.fig, "png", paste0(.fig8_stem, ".png"))
# 清掉旧短标题残留
unlink(list.files(file.path(.fig, "pdf"), pattern = "^Figure 8\\. DCA", full.names = TRUE))
unlink(list.files(file.path(.fig, "png"), pattern = "^Figure 8\\. DCA", full.names = TRUE))
unlink(list.files(file.path(.fig, "tiff"), pattern = "^Figure 8\\. DCA", full.names = TRUE))
unlink(list.files(file.path(.fig, "image_information"), pattern = "^Figure 8\\. DCA", full.names = TRUE))
.save_pdf_png(.fig8, .fig8_pdf, 11.6, 4.55)
tryCatch({
  ggplot2::ggsave(.fig8_png, .fig8, width = 11.6, height = 4.55, dpi = 300, bg = "white")
  .trim_png_white(.fig8_png, pad = 4L, thr = 250L)
}, error = function(e) message("Fig8 png: ", conditionMessage(e)))
writeLines(c(
  "Fig8 = Chen FreeStatistics-style DCA (3 panels).",
  "Y = Standardized Net Benefit [0,1] clipped; X top=High Risk Threshold, bottom=Cost:Benefit Ratio (Chen);",
  "None = red near y=0 (visible); All/model clipped inside panel; shared bottom legend;",
  " curves = Prediction nomogram (blue + thin bootstrap 95% CI lines, no ribbon), All (grey), None (red).",
  "Panels: A Train set | B Internal validation set | C Bootstrap (no external cohort).",
  "Caption style: DCA of nomogram prediction model for lithotripsy success."
), file.path(.tab, "Methods_fig8_layout.txt"))
message("Fig8 Chen-style DCA done: ", .fig8_stem)


# ---------- Fig9：对标 Chen FreeStatistics CIC ----------
message("→ Fig9 Chen-style CIC …")
.cic_chen_one <- function(y, p, panel, n_boot = 200L, seed = 42L, N = 100) {
  y <- as.integer(y); p <- as.numeric(p)
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]; p <- p[ok]
  n <- length(y)
  th <- seq(0.00, 1.00, by = 0.01)
  .counts <- function(yy, pp) {
    vapply(th, function(t) {
      hi <- pp >= t
      c(
        high = sum(hi) / length(pp) * N,
        event = sum(hi & yy == 1L) / length(pp) * N
      )
    }, numeric(2))
  }
  base <- .counts(y, p)
  high <- base[1, ]; event <- base[2, ]
  set.seed(seed)
  boot_h <- matrix(NA_real_, n_boot, length(th))
  boot_e <- matrix(NA_real_, n_boot, length(th))
  for (b in seq_len(n_boot)) {
    ii <- sample.int(n, replace = TRUE)
    bb <- .counts(y[ii], p[ii])
    boot_h[b, ] <- bb[1, ]
    boot_e[b, ] <- bb[2, ]
  }
  h_lo <- apply(boot_h, 2, stats::quantile, probs = 0.025, na.rm = TRUE)
  h_hi <- apply(boot_h, 2, stats::quantile, probs = 0.975, na.rm = TRUE)
  e_lo <- apply(boot_e, 2, stats::quantile, probs = 0.025, na.rm = TRUE)
  e_hi <- apply(boot_e, 2, stats::quantile, probs = 0.975, na.rm = TRUE)
  # 轻平滑但锁两端，避免 thr=1 被 lowess 抬高
  sm <- function(x) {
    ys <- tryCatch(stats::lowess(th, x, f = 0.08)$y, error = function(e) x)
    ys[1] <- x[1]
    ys[length(ys)] <- x[length(x)]
    ys
  }
  data.frame(
    thr = th,
    high = pmin(pmax(sm(high), 0), N),
    high_lo = pmin(pmax(sm(h_lo), 0), N),
    high_hi = pmin(pmax(sm(h_hi), 0), N),
    event = pmin(pmax(sm(event), 0), N),
    event_lo = pmin(pmax(sm(e_lo), 0), N),
    event_hi = pmin(pmax(sm(e_hi), 0), N),
    panel = panel,
    stringsAsFactors = FALSE
  )
}
.dd9 <- rbind(
  .cic_chen_one(.y_tr, .p_tr, "Train set", n_boot = 200L, seed = 52L),
  .cic_chen_one(.y_va, .p_va, "Internal validation set", n_boot = 200L, seed = 53L),
  .cic_chen_one(.y01(.full), .p_boot, "Bootstrap", n_boot = 200L, seed = 54L)
)
.dd9$panel <- factor(.dd9$panel, levels = c("Train set", "Internal validation set", "Bootstrap"))

.theme9 <- theme_bw(base_size = 11) +
  theme(
    panel.grid.major = element_line(color = "grey88", linewidth = 0.30),
    panel.grid.minor = element_blank(),
    panel.background = element_rect(fill = "white", color = NA),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.55),
    plot.title = element_text(face = "bold", size = 13, hjust = 0, margin = margin(b = 1)),
    axis.title = element_text(size = 9.5),
    axis.title.x.top = element_text(size = 9.5, margin = margin(b = 2)),
    axis.title.x.bottom = element_text(size = 9.5, margin = margin(t = 3)),
    axis.text = element_text(size = 8, color = "black"),
    axis.text.x.bottom = element_text(size = 7.2),
    legend.position = c(0.98, 0.98),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "white", color = "black", linewidth = 0.35),
    legend.key = element_rect(fill = "white", color = NA),
    legend.key.width = unit(1.2, "cm"),
    legend.key.height = unit(0.28, "cm"),
    legend.text = element_text(size = 8),
    legend.title = element_blank(),
    legend.margin = margin(2, 4, 2, 4),
    plot.margin = margin(4, 6, 4, 4),
    plot.background = element_rect(fill = "white", color = NA)
  )

.cic_panel_plot <- function(df, letter) {
  dlong <- rbind(
    data.frame(thr = df$thr, y = df$high, curve = "Number high risk",
               lty = "solid", stringsAsFactors = FALSE),
    data.frame(thr = df$thr, y = df$event, curve = "Number high risk with event",
               lty = "dashed", stringsAsFactors = FALSE)
  )
  dlong$curve <- factor(
    dlong$curve,
    levels = c("Number high risk", "Number high risk with event")
  )
  ggplot() +
    # CI：红实线细线 / 蓝虚线细线（对标 Chen，无色带）
    geom_line(data = df, aes(thr, high_lo), color = "#F1948A", linewidth = 0.40, linetype = "solid") +
    geom_line(data = df, aes(thr, high_hi), color = "#F1948A", linewidth = 0.40, linetype = "solid") +
    geom_line(data = df, aes(thr, event_lo), color = "#85C1E9", linewidth = 0.40, linetype = "dotted") +
    geom_line(data = df, aes(thr, event_hi), color = "#85C1E9", linewidth = 0.40, linetype = "dotted") +
    geom_line(
      data = subset(dlong, curve == "Number high risk"),
      aes(thr, y, color = curve, linetype = curve),
      linewidth = 1.05
    ) +
    geom_line(
      data = subset(dlong, curve == "Number high risk with event"),
      aes(thr, y, color = curve, linetype = curve),
      linewidth = 1.00
    ) +
    scale_color_manual(
      values = c(
        "Number high risk" = "#C0392B",
        "Number high risk with event" = "#1F618D"
      )
    ) +
    scale_linetype_manual(
      values = c(
        "Number high risk" = "solid",
        "Number high risk with event" = "dashed"
      )
    ) +
    scale_x_continuous(
      name = "Cost:Benefit Ratio",
      limits = c(0, 1),
      breaks = .cb_breaks,
      labels = .cb_labs,
      expand = c(0, 0),
      sec.axis = dup_axis(
        name = "High Risk Threshold",
        breaks = seq(0, 1, by = 0.2),
        labels = sprintf("%.1f", seq(0, 1, by = 0.2))
      )
    ) +
    scale_y_continuous(
      name = "Number high risk (out of 100)",
      limits = c(0, 100),
      breaks = seq(0, 100, by = 20),
      expand = c(0, 0)
    ) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 100), clip = "on") +
    labs(title = paste0(letter, ".")) +
    guides(
      color = guide_legend(override.aes = list(
        linewidth = c(1.05, 1.0),
        linetype = c("solid", "dashed")
      )),
      linetype = "none"
    ) +
    .theme9
}
.p9A <- .cic_panel_plot(subset(.dd9, panel == "Train set"), "A")
.p9B <- .cic_panel_plot(subset(.dd9, panel == "Internal validation set"), "B")
.p9C <- .cic_panel_plot(subset(.dd9, panel == "Bootstrap"), "C")
.fig9 <- (.p9A | .p9B | .p9C) + plot_layout(widths = c(1, 1, 1))

.fig9_stem <- "Figure 9. CIC of nomogram prediction model for lithotripsy success"
.fig9_pdf <- file.path(.fig, "pdf", paste0(.fig9_stem, ".pdf"))
.fig9_png <- file.path(.fig, "png", paste0(.fig9_stem, ".png"))
unlink(list.files(file.path(.fig, "pdf"), pattern = "^Figure 9\\. CIC", full.names = TRUE))
unlink(list.files(file.path(.fig, "png"), pattern = "^Figure 9\\. CIC", full.names = TRUE))
unlink(list.files(file.path(.fig, "tiff"), pattern = "^Figure 9\\. CIC", full.names = TRUE))
unlink(list.files(file.path(.fig, "image_information"), pattern = "^Figure 9\\. CIC", full.names = TRUE))
.save_pdf_png(.fig9, .fig9_pdf, 11.6, 4.55)
tryCatch({
  ggplot2::ggsave(.fig9_png, .fig9, width = 11.6, height = 4.55, dpi = 300, bg = "white")
  .trim_png_white(.fig9_png, pad = 4L, thr = 250L)
}, error = function(e) message("Fig9 png: ", conditionMessage(e)))
writeLines(c(
  "Fig9 = Chen FreeStatistics-style Clinical Impact Curve (3 panels).",
  "Y = Number high risk (out of 100); X top = High Risk Threshold; X bottom = Cost:Benefit Ratio.",
  "Red solid (+ thin CI) = Number high risk; Blue dashed (+ thin dotted CI) = Number high risk with event.",
  "Panels: A Train | B Internal validation | C Bootstrap.",
  "Caption: CIC of nomogram prediction model for lithotripsy success."
), file.path(.tab, "Methods_fig9_layout.txt"))
message("Fig9 Chen-style CIC done: ", .fig9_stem)

# ===================== Supplementary =====================
message("→ Supplementary figures (Chen-style subgroup forests) …")
# 原文 Supplemental Figure 1/2 = 单一暴露 × 多亚组森林（Overall crude/adjusted + P for interaction）
# 本课题：S1 = diameter_cm；S2 = shots
# （energy_j 近分离不进补充主图；stone_type 塌缩仅写 Methods，不再冒充 Figure S2）

.y01_df <- function(d) {
  y <- d[[.out]]
  if (is.factor(y)) as.integer(y == "Yes" | y == levels(y)[length(levels(y))])
  else as.integer(as.numeric(y) == 1L)
}
.event_lab <- function(d) {
  # 对标 Chen 原文：Event (%) = 事件数 (事件率%)，非样本量
  y <- .y01_df(d)
  sprintf("%d (%.1f)", sum(y == 1L, na.rm = TRUE), 100 * mean(y == 1L, na.rm = TRUE))
}
.pint <- function(d, expose, strat) {
  dd <- d
  dd$.y <- .y01_df(dd)
  dd$.x <- as.numeric(scale(as.numeric(dd[[expose]])))
  dd$.g <- factor(dd[[strat]])
  if (nlevels(droplevels(dd$.g)) < 2L) return(NA_real_)
  m0 <- tryCatch(stats::glm(.y ~ .x + .g, data = dd, family = stats::binomial()), error = function(e) NULL)
  m1 <- tryCatch(stats::glm(.y ~ .x * .g, data = dd, family = stats::binomial()), error = function(e) NULL)
  if (is.null(m0) || is.null(m1)) return(NA_real_)
  as.numeric(stats::anova(m0, m1, test = "LRT")$`Pr(>Chi)`[2])
}
.expose_lab_fn <- function(ex) {
  switch(ex,
    diameter_cm = "Diameter (cm)",
    shots = "Shots",
    volume_cm3 = "Volume (cm3)",
    Age = "Age",
    energy_j = "Energy (J)",
    ex
  )
}
.subgroups_chen <- list(
  list(var = "Age_Group", lab = "Age, y", level_order = c("< 65", ">= 65")),
  list(var = "Sex", lab = "Sex", level_order = c("1", "2")),
  list(var = "shape", lab = "Shape", level_order = c("1", "2")),
  list(var = "color", lab = "Color", level_order = c("1", "2", "3")),
  list(var = "surface", lab = "Surface", level_order = c("1", "2")),
  list(var = "stone_type", lab = "Stone type",
       level_order = c("Favorable", "Unfavorable"))
)

.build_chen_subgroup_forest <- function(expose, fig_stem, footnote_tag) {
  expose_lab <- .expose_lab_fn(expose)
  rows <- list()
  add_row <- function(...) {
    rows[[length(rows) + 1L]] <<- list(...)
  }
  add_row(
    Subgroup = "Overall", Event = "", ORCI = "",
    est = NA_real_, lo = NA_real_, hi = NA_real_, pint = "", summary = TRUE
  )
  for (mod in c("Crude", "Adjusted")) {
    cov <- if (identical(mod, "Crude")) character(0) else setdiff(c("Age", "Sex"), expose)
    rr <- gallstone_nomogram_fit_or_row(.df, expose, .out, cov)
    if (is.null(rr) || !is.finite(rr$OR)) next
    add_row(
      Subgroup = paste0("  ", mod), Event = .event_lab(.df),
      ORCI = .fmt_or(rr$OR, rr$CI_low, rr$CI_high),
      est = pmin(pmax(rr$OR, 0.05), 20), lo = pmax(rr$CI_low, 0.05),
      hi = pmin(rr$CI_high, 20), pint = "", summary = TRUE
    )
  }
  for (sg in .subgroups_chen) {
    var <- sg$var
    if (identical(var, "Age_Group")) {
      g <- ifelse(as.numeric(.df$Age) >= 65, ">= 65", "< 65")
      dd_pi <- .df
      dd_pi$Age_Group <- ifelse(as.numeric(.df$Age) >= 65, "ge65", "lt65")
      pi <- .pint(dd_pi, expose, "Age_Group")
    } else {
      if (!var %in% names(.df)) next
      g <- as.character(.df[[var]])
      pi <- .pint(.df, expose, var)
    }
    add_row(
      Subgroup = sg$lab, Event = "", ORCI = "",
      est = NA_real_, lo = NA_real_, hi = NA_real_,
      pint = if (is.finite(pi)) .fmt_p(pi) else "\u2014", summary = TRUE
    )
    for (lv in sg$level_order) {
      dsub <- .df[!is.na(g) & g == lv, , drop = FALSE]
      if (nrow(dsub) < 8L || length(unique(.y01_df(dsub))) < 2L) {
        add_row(
          Subgroup = paste0("  ", lv), Event = .event_lab(dsub), ORCI = "NE",
          est = NA_real_, lo = NA_real_, hi = NA_real_, pint = "", summary = FALSE
        )
        next
      }
      cov <- setdiff(
        c("Age", "Sex"),
        c(
          expose,
          if (identical(var, "Age_Group") || identical(var, "Age")) "Age" else character(0),
          if (identical(var, "Sex")) "Sex" else character(0)
        )
      )
      rr <- gallstone_nomogram_fit_or_row(dsub, expose, .out, cov)
      bad <- is.null(rr) || !is.finite(rr$OR) || !is.finite(rr$CI_low) || !is.finite(rr$CI_high) ||
        rr$OR < 1e-6 || rr$CI_high > 1e5
      if (bad) {
        add_row(
          Subgroup = paste0("  ", lv), Event = .event_lab(dsub), ORCI = "NE",
          est = NA_real_, lo = NA_real_, hi = NA_real_, pint = "", summary = FALSE
        )
        next
      }
      add_row(
        Subgroup = paste0("  ", lv), Event = .event_lab(dsub),
        ORCI = .fmt_or(rr$OR, rr$CI_low, rr$CI_high),
        est = pmin(pmax(rr$OR, 0.05), 20), lo = pmax(rr$CI_low, 0.05),
        hi = pmin(rr$CI_high, 20), pint = "", summary = FALSE
      )
    }
  }
  tab <- do.call(rbind, lapply(rows, function(z) {
    data.frame(
      Subgroup = z$Subgroup, Event = z$Event, ORCI = z$ORCI,
      est = z$est, lo = z$lo, hi = z$hi, pint = z$pint,
      summary = z$summary, stringsAsFactors = FALSE
    )
  }))
  # 对标 Chen 原文：白底、表头双线、橙菱形+黑 CI、蓝 summary 菱形、P for interaction
  dt <- data.frame(
    Subgroup = as.character(tab$Subgroup),
    `Event (%)` = as.character(tab$Event),
    `OR (95%CI)` = as.character(tab$ORCI),
    ` ` = paste(rep(" ", 22L), collapse = ""),
    `P for interaction` = as.character(tab$pint),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  is_sum <- as.logical(tab$summary)
  # 仅 Overall Crude/Adjusted 用蓝菱形；分组标题行不当 summary
  is_sum_plot <- is_sum & is.finite(as.numeric(tab$est))
  xlim <- c(0.25, 4)
  ticks_at <- c(0.5, 1, 2)
  est_d <- as.numeric(tab$est)
  lo_d <- as.numeric(tab$lo)
  hi_d <- as.numeric(tab$hi)
  lo_d <- pmax(lo_d, xlim[1] * 0.999)
  hi_d <- pmin(hi_d, xlim[2] * 1.001)
  est_d <- pmin(pmax(est_d, xlim[1]), xlim[2])
  bad <- !(is.finite(as.numeric(tab$est)) & is.finite(as.numeric(tab$lo)) &
             is.finite(as.numeric(tab$hi)))
  est_d[bad] <- lo_d[bad] <- hi_d[bad] <- NA_real_
  tm <- forestploter::forest_theme(
    base_size = 10,
    refline_gp = grid::gpar(lty = 1, col = "grey75", lwd = 0.7),
    # 原文：橙点 + 黑色细 CI + 端帽（非橙色粗条/斑马纹）
    ci_pch = 18, ci_col = "black", ci_fill = "#F39C12", ci_alpha = 1,
    ci_lwd = 0.85, ci_Theight = 0.16,
    summary_fill = "#5DADE2", summary_col = "#5DADE2",
    arrow_type = "closed",
    arrow_gp = grid::gpar(fill = "black", col = "black", lwd = 0.7),
    core = list(
      fg_params = list(hjust = 0, x = 0.02),
      bg_params = list(fill = c("white", "white")),
      # 行间距加大
      padding = grid::unit(c(3.2, 0.9), "mm")
    ),
    colhead = list(
      fg_params = list(hjust = 0, x = 0.02, fontface = "bold"),
      bg_params = list(fill = "white"),
      padding = grid::unit(c(2.8, 0.9), "mm")
    ),
    xaxis_gp = grid::gpar(fontsize = 8.5, col = "black", lwd = 0.55),
    xlab_gp = grid::gpar(fontsize = 9, col = "black")
  )
  pobj <- forestploter::forest(
    data = dt,
    est = est_d,
    lower = lo_d,
    upper = hi_d,
    sizes = ifelse(is_sum_plot, 0.48, 0.30),
    ci_column = 4L, ref_line = 1,
    xlim = xlim, ticks_at = ticks_at,
    x_trans = "log",
    xlab = "Odds Ratio (95%CI)",
    is_summary = is_sum_plot,
    theme = tm
  )
  pobj <- forestploter::edit_plot(pobj, part = "header", gp = grid::gpar(fontface = "bold"))
  # 分组标题行 + P for interaction 加粗（与原文一致）
  hdr_rows <- which(is_sum & !nzchar(as.character(tab$Event)))
  for (ri in hdr_rows) {
    pobj <- tryCatch(
      forestploter::edit_plot(pobj, row = ri, gp = grid::gpar(fontface = "bold")),
      error = function(e) pobj
    )
  }
  # 再拉高表体行
  try({
    hh_body <- grid::convertHeight(pobj$heights, "mm", valueOnly = TRUE)
    nh <- length(hh_body)
    if (nh >= 5L) {
      for (ii in 2:(nh - 2L)) {
        pobj$heights[ii] <- grid::unit(hh_body[ii] * 1.32, "mm")
      }
    }
  }, silent = TRUE)
  # 原文表头上下双横线（顶线需留足上边距，避免 trim 裁掉）
  pobj <- forestploter::add_border(
    pobj, part = "header", where = "top",
    gp = grid::gpar(lwd = 1.15, col = "black")
  )
  pobj <- forestploter::add_border(
    pobj, part = "header", where = "bottom",
    gp = grid::gpar(lwd = 1.15, col = "black")
  )
  # 压紧默认外边距，但顶部至少留 3mm 保住顶线
  try({
    hh <- grid::convertHeight(pobj$heights, "mm", valueOnly = TRUE)
    ww <- grid::convertWidth(pobj$widths, "mm", valueOnly = TRUE)
    if (length(hh) >= 2L) {
      if (is.finite(hh[1]) && hh[1] > 3.2) pobj$heights[1] <- grid::unit(3.0, "mm")
      if (is.finite(hh[length(hh)]) && hh[length(hh)] > 2) {
        pobj$heights[length(hh)] <- grid::unit(1.5, "mm")
      }
      ia <- length(hh) - 1L
      if (ia >= 1L && is.finite(hh[ia]) && hh[ia] > 9.5) {
        pobj$heights[ia] <- grid::unit(8.5, "mm")
      }
    }
    if (length(ww) >= 2L) {
      if (is.finite(ww[1]) && ww[1] > 2) pobj$widths[1] <- grid::unit(1.5, "mm")
      if (is.finite(ww[length(ww)]) && ww[length(ww)] > 2) {
        pobj$widths[length(ww)] <- grid::unit(1.5, "mm")
      }
    }
  }, silent = TRUE)

  pdf_path <- file.path(.fig, "pdf", paste0(fig_stem, ".pdf"))
  png_path <- file.path(.fig, "png", paste0(fig_stem, ".png"))
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(png_path), recursive = TRUE, showWarnings = FALSE)
  wh <- tryCatch(forestploter::get_wh(pobj, unit = "in"),
                 error = function(e) c(width = 8.2, height = 5.0))
  w <- as.numeric(wh["width"]) %||% as.numeric(wh[1])
  h <- as.numeric(wh["height"]) %||% as.numeric(wh[2])
  if (!is.finite(w) || w < 6) w <- 8.0
  if (!is.finite(h) || h < 3.5) h <- 4.8
  w <- w * 1.01
  h <- h * 1.01
  .draw <- function() {
    grid::grid.newpage()
    grid::grid.draw(pobj)
  }
  grDevices::pdf(pdf_path, width = w, height = h, useDingbats = FALSE)
  .draw()
  grDevices::dev.off()
  grDevices::png(png_path, width = w, height = h, units = "in", res = 300, bg = "white")
  .draw()
  grDevices::dev.off()
  # pad 稍大，避免裁掉表头顶横线
  .trim_png_white(png_path, pad = 8L, thr = 250L)
  .im <- tryCatch(png::readPNG(png_path), error = function(e) NULL)
  if (!is.null(.im)) {
    w <- dim(.im)[2] / 300
    h <- dim(.im)[1] / 300
    grDevices::pdf(pdf_path, width = w, height = h, useDingbats = FALSE)
    grid::grid.raster(.im, interpolate = TRUE)
    grDevices::dev.off()
    grDevices::png(png_path, width = w, height = h, units = "in", res = 300, bg = "white")
    grid::grid.raster(.im, interpolate = TRUE)
    grDevices::dev.off()
  }
  for (d in c(
    file.path(.proj, "Figures", "pdf"),
    file.path(.proj, "_shared", "Figures", "pdf")
  )) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(pdf_path, file.path(d, basename(pdf_path)), overwrite = TRUE)
  }
  for (d in c(
    file.path(.proj, "Figures", "png"),
    file.path(.proj, "_shared", "Figures", "png")
  )) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    file.copy(png_path, file.path(d, basename(png_path)), overwrite = TRUE)
  }
  utils::write.csv(
    data.frame(
      Subgroup = tab$Subgroup, Event = tab$Event, ORCI = tab$ORCI,
      P_interaction = tab$pint, OR = tab$est, lo = tab$lo, hi = tab$hi
    ),
    file.path(.tab, paste0("Table_", gsub("[^A-Za-z0-9]+", "_", fig_stem), ".csv")),
    row.names = FALSE
  )
  writeLines(c(
    paste0(footnote_tag, " Subgroup analysis of the association between ",
           expose_lab, " and lithotripsy success."),
    "OR per 1-SD increase; Adjusted = Age + Sex (excluding the stratifier).",
    "NE = not estimable (near-separation / sparse stratum).",
    "Event (%) = n events (event rate %); OR per 1-SD increase.",
    "P for interaction = likelihood-ratio test.",
    "Style aligned to Chen FreeStatistics: white bg, header rules, orange diamond + black CI.",
    "Footnote kept off-figure to avoid axis label overlap (same as Fig2/Fig5)."
  ), file.path(.tab, paste0("Methods_", gsub("[^A-Za-z0-9]+", "_", fig_stem), "_footnote.txt")))
  message("Saved ", fig_stem, " (", round(w, 2), "x", round(h, 2), " in)")
  invisible(TRUE)
}

unlink(list.files(file.path(.fig, "pdf"), pattern = "^Figure S1\\.|^Figure S2\\.", full.names = TRUE))
unlink(list.files(file.path(.fig, "png"), pattern = "^Figure S1\\.|^Figure S2\\.", full.names = TRUE))
unlink(list.files(file.path(.fig, "tiff"), pattern = "^Figure S1\\.|^Figure S2\\.", full.names = TRUE))
unlink(list.files(file.path(.fig, "image_information"), pattern = "^Figure S1\\.|^Figure S2\\.", full.names = TRUE))

.build_chen_subgroup_forest(
  "diameter_cm",
  "Figure S1. Subgroup analysis of Diameter and lithotripsy success",
  "Figure S1."
)
.build_chen_subgroup_forest(
  "shots",
  "Figure S2. Subgroup analysis of Shots and lithotripsy success",
  "Figure S2."
)

writeLines(c(
  "WARNINGS / FIXES (rebuild_all_pub_figures_lit.R)",
  "1. Raw stone_type had complete separation → collapsed Favorable/Unfavorable (Methods text; not a figure).",
  "2. Fig S1/S2 aligned to Chen Supplemental Figures: single exposure × multi-subgroup forest",
  "   with Overall Crude/Adjusted + P for interaction (NOT feature-within-Sex inverted layout).",
  "3. S1 = diameter_cm; S2 = shots. energy_j excluded (near-separation).",
  "4. Association/MV OR estimated with brglm2 when available.",
  sprintf("5. AUC: train=%.3f val=%.3f boot=%.3f", .metrics$AUC[1], .metrics$AUC[2], .metrics$AUC[3])
), file.path(.tab, "Methods_rebuild_notes.txt"))
writeLines(c(
  "Fig S1/S2 = Chen FreeStatistics-style subgroup forests (one continuous exposure each).",
  "S1 exposure = diameter_cm; S2 exposure = shots.",
  "Layout: Overall Crude/Adjusted + Age/Sex/shape/color/surface/stone_type",
  "with Event(%), OR(95%CI), forest, P for interaction.",
  "stone_type collapse → Methods_rebuild_notes.txt (not Figure S2)."
), file.path(.tab, "Methods_figS1_S2_layout.txt"))

tryCatch(
  pub_figure_ensure_formats(.fig, config = list(pub = list(renumber = FALSE))),
  error = function(e) message("formats: ", conditionMessage(e))
)
tryCatch({
  .f2n <- "Figure 2. Associations of continuous features"
  .trim_png_white(file.path(.fig, "png", paste0(.f2n, ".png")), pad = 3L, thr = 250L)
  .png2 <- file.path(.fig, "png", paste0(.f2n, ".png"))
  .tiff2 <- file.path(.fig, "tiff", paste0(.f2n, ".tiff"))
  if (file.exists(.png2) && requireNamespace("tiff", quietly = TRUE)) {
    tiff::writeTIFF(png::readPNG(.png2), .tiff2, compression = "LZW")
  }
  for (d in c(file.path(.proj, "Figures", "png"),
              file.path(.proj, "_shared", "Figures", "png"))) {
    if (dir.exists(dirname(d))) {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      file.copy(.png2, file.path(d, basename(.png2)), overwrite = TRUE)
    }
  }
}, error = function(e) message("Fig2 final trim: ", conditionMessage(e)))
.strip_flat_figure_pdfs(.fig)
for (fr in c(file.path(.proj, "Figures"), file.path(.proj, "_shared", "Figures"),
             file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results", "Figures"))) {
  .strip_flat_figure_pdfs(fr)
}


writeLines(c(
  "# summary_results — 文献对齐重画版",
  "",
  "主入口：`Figures/pdf/`（Figure 1–9 + S1/S2），禁止根目录平铺 PDF。",
  "Fig1 CONSORT | Fig2 一页森林（预指定连续）| Fig3 RCS（同上）| Fig4 Ridge 预指定 | Fig5 Firth 多因素 | Fig6 列线图 | Fig7 ROC+校准 | Fig8 DCA of nomogram… | Fig9 CIC of nomogram…",
  "补充: Figure S1 Diameter 亚组森林; Figure S2 Shots 亚组森林（对标 Chen Supplemental Fig1/2）",
  "详见 Tables/Methods_rebuild_notes.txt"
), file.path(.set, "README.md"))

# 四目录导出后重刷 image_information（无下划线展示名）
tryCatch({
  .imd_scr <- file.path(.root, "run/gallstone_nomogram/refresh_image_information_lit.R")
  if (file.exists(.imd_scr)) {
    message("→ refresh image_information (no underscores) …")
    system2("Rscript", c("--vanilla", .imd_scr), stdout = TRUE, stderr = TRUE)
  }
}, error = function(e) message("image_information WARN: ", conditionMessage(e)))

# Phase 6：发表质控骨架（Agent 须继续 nature-statistics / nature-figure 修 P0）
tryCatch({
  .qc <- file.path(.root, "run/pub/run_pub_qc_after_project.R")
  if (file.exists(.qc)) {
    message("→ pub-qc-after-project …")
    system2("Rscript", c("--vanilla", .qc, "--project", .proj), stdout = TRUE, stderr = TRUE)
  }
}, error = function(e) message("pub-qc WARN: ", conditionMessage(e)))

message("DONE rebuild all lit figures → ", .fig)
