###############################################################################
#  multimorbidity_graphical_abstract — 研究过程摘要图（非正式 Fig）
#
#  版式/配色/图标对齐: 01Block/流程图1配色.ai
#  资源: Blocks/44_multimorbidity/assets/graphical_abstract/
#  输出: Figures/graphical_abstract/  （不进正式 Figure N）
###############################################################################

.mm_ga_ai_palette <- function() {
  list(
    bg           = "#FFF7F4",
    header       = c("#E8B4A2", "#7D9CBA"),
    panel_fill   = "#E9F1F4",
    panel_border = "#C5D8E6",
    process_fill = "#B6D3E3",
    process_head = "#8FB3D4",
    results_bg   = "#8FB3D4",
    arrow_proc   = "#8FB3D4",
    arrow_var    = "#FFFFFF",
    circle       = c("#F5B792", "#F1A07E", "#D96F5D"),
    ink          = "#1A1A1A",
    white        = "#FFFFFF",
    muted        = "#555555"
  )
}

.mm_ga_assets_dir <- function(ctx = NULL) {
  root <- ctx$project_root %||% getwd()
  d <- file.path(root, "Blocks/44_multimorbidity/assets/graphical_abstract")
  if (dir.exists(d)) return(d)
  # Final 镜像或相对路径兜底
  alt <- file.path(root, "assets/graphical_abstract")
  if (dir.exists(alt)) return(alt)
  d
}

.mm_ga_read_png <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(png::readPNG(path), error = function(e) NULL)
}

.mm_ga_raster <- function(img, x, y, w = NULL, h = NULL) {
  # 只给 width 或 height 之一，避免 npc 双约束把图标拉扁
  if (is.null(img)) return(invisible(NULL))
  args <- list(
    image = img,
    x = grid::unit(x, "npc"), y = grid::unit(y, "npc"),
    interpolate = TRUE
  )
  if (!is.null(w) && is.null(h)) {
    args$width <- grid::unit(w, "npc")
  } else if (!is.null(h) && is.null(w)) {
    args$height <- grid::unit(h, "npc")
  } else if (!is.null(w) && !is.null(h)) {
    args$width <- grid::unit(w, "npc")
    args$height <- grid::unit(h, "npc")
  }
  do.call(grid::grid.raster, args)
}

# 给定 width(npc) 时，按页面英寸比估算图像高度(npc)，用于文字锚点
.mm_ga_img_h_npc <- function(img, w_npc, page_w = 11.12, page_h = 5.94) {
  if (is.null(img)) return(w_npc)
  ih <- dim(img)[[1L]]
  iw <- max(dim(img)[[2L]], 1L)
  as.numeric(w_npc) * (ih / iw) * (page_w / page_h)
}

# 图标在上、文字在下；文字顶边相对图标底边固定间距（与行数无关）
.mm_ga_icon_caption <- function(img, label, x, y_icon, w_icon, gap = 0.018,
                                fontsize = 10, pal, lineheight = 1.05) {
  .mm_ga_raster(img, x, y_icon, w = w_icon)
  h <- .mm_ga_img_h_npc(img, w_icon)
  y_txt <- y_icon - h / 2 - gap
  grid::grid.text(
    label, x = x, y = y_txt, just = c("centre", "top"),
    gp = grid::gpar(col = pal$ink, fontsize = fontsize, fontface = "bold",
                    fontfamily = "serif", lineheight = lineheight)
  )
  invisible(list(y_icon = y_icon, y_text = y_txt, h = h))
}

.mm_ga_pick_colors <- function(ga, cfg = NULL, n = 4L) {
  n <- as.integer(n)[1L]
  pal <- .mm_ga_ai_palette()
  if (!isTRUE(ga$random_colors %||% FALSE)) {
    return(c(pal$header[[1L]], pal$header[[2L]], pal$process_fill, pal$circle[[2L]]))
  }
  if (!exists("block_colors", mode = "function") &&
      !exists("block_colors_from_config", mode = "function")) {
    return(rep(c("#CE4844", "#2A73BA", "#63C6A1", "#EFB47A"), length.out = n))
  }
  pool_n <- max(n, 8L)
  base <- if (exists("block_colors_from_config", mode = "function")) {
    block_colors_from_config(cfg, n = pool_n, group = 2L)
  } else {
    block_colors(pool_n, group = 2L)
  }
  seed <- suppressWarnings(as.integer(ga$color_seed %||% NA_integer_)[1L])
  if (!is.finite(seed)) seed <- as.integer(as.numeric(Sys.time()) %% 1e9)
  had_rng <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  rng <- if (had_rng) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE) else NULL
  on.exit({
    if (had_rng && !is.null(rng)) {
      assign(".Random.seed", rng, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  pool <- unique(as.character(base))
  if (length(pool) < n) pool <- rep(pool, length.out = n)
  sample(pool, size = n, replace = FALSE)
}

.mm_ga_grad <- function(cols, vertical = FALSE) {
  if (isTRUE(vertical)) {
    grid::linearGradient(colours = cols, x1 = 0.5, x2 = 0.5, y1 = 1, y2 = 0, group = FALSE)
  } else {
    grid::linearGradient(colours = cols, x1 = 0, x2 = 1, y1 = 0.5, y2 = 0.5, group = FALSE)
  }
}

.mm_ga_header_pill <- function(label, x, y, w = 0.14, h = 0.065, pal) {
  grid::grid.roundrect(
    x = grid::unit(x, "npc"), y = grid::unit(y, "npc"),
    width = grid::unit(w, "npc"), height = grid::unit(h, "npc"),
    r = grid::unit(0.4, "snpc"),
    gp = grid::gpar(fill = .mm_ga_grad(pal$header), col = NA)
  )
  grid::grid.text(
    label, x = x, y = y,
    gp = grid::gpar(col = pal$white, fontface = "bold", fontsize = 13,
                    fontfamily = "serif")
  )
}

.mm_ga_panel <- function(x, y, w, h, pal, fill = NULL) {
  grid::grid.roundrect(
    x = grid::unit(x, "npc"), y = grid::unit(y, "npc"),
    width = grid::unit(w, "npc"), height = grid::unit(h, "npc"),
    r = grid::unit(0.035, "npc"),
    gp = grid::gpar(
      fill = fill %||% .mm_ga_grad(c("#F4F8FB", pal$panel_fill), vertical = TRUE),
      col = pal$panel_border, lwd = 1.2
    )
  )
}

.mm_ga_arrow_down_thick <- function(x, y0, y1, col, stem = 0.028) {
  # 粗向下箭头（过程栏，贴近 .ai）
  head <- 0.032
  grid::grid.polygon(
    x = grid::unit(c(x - stem / 2, x + stem / 2, x + stem / 2,
                     x + stem * 1.35, x, x - stem * 1.35,
                     x - stem / 2), "npc"),
    y = grid::unit(c(y0, y0, y1 + head,
                     y1 + head, y1, y1 + head,
                     y1 + head), "npc"),
    gp = grid::gpar(fill = col, col = NA)
  )
}

.mm_ga_arrow_down_white <- function(x, y, pal) {
  # Variables 栏白色粗箭头
  grid::grid.polygon(
    x = grid::unit(c(x - 0.016, x + 0.016, x + 0.016, x + 0.034, x, x - 0.034, x - 0.016), "npc"),
    y = grid::unit(c(y + 0.028, y + 0.028, y + 0.002, y + 0.002, y - 0.028, y + 0.002, y + 0.002), "npc"),
    gp = grid::gpar(fill = pal$arrow_var, col = NA)
  )
}

.mm_ga_process_box <- function(title, body, x, y, w, h, pal) {
  grid::grid.roundrect(
    x = grid::unit(x, "npc"), y = grid::unit(y, "npc"),
    width = grid::unit(w, "npc"), height = grid::unit(h, "npc"),
    r = grid::unit(0.018, "npc"),
    gp = grid::gpar(fill = pal$process_fill, col = NA)
  )
  y_top <- y + h / 2
  grid::grid.text(
    title, x = x, y = y_top - 0.022,
    gp = grid::gpar(col = pal$ink, fontface = "bold", fontsize = 10,
                    fontfamily = "serif")
  )
  grid::grid.lines(
    x = grid::unit(c(x - w * 0.40, x + w * 0.40), "npc"),
    y = grid::unit(c(y_top - 0.040, y_top - 0.040), "npc"),
    gp = grid::gpar(col = pal$white, lwd = 2)
  )
  grid::grid.text(
    body, x = x, y = y - 0.012,
    gp = grid::gpar(col = pal$ink, fontsize = 8, fontfamily = "serif",
                    lineheight = 1.12)
  )
}

.mm_ga_result_inner <- function(top, bottom, x, y, w, h, pal) {
  # 白底圆角卡 + 虚线分隔（落在蓝色 Results 大面板内）
  grid::grid.roundrect(
    x = grid::unit(x, "npc"), y = grid::unit(y, "npc"),
    width = grid::unit(w, "npc"), height = grid::unit(h, "npc"),
    r = grid::unit(0.018, "npc"),
    gp = grid::gpar(fill = pal$white, col = NA)
  )
  grid::grid.text(
    top, x = x, y = y + h * 0.28,
    gp = grid::gpar(col = pal$ink, fontface = "bold", fontsize = 8.5,
                    fontfamily = "serif", lineheight = 1.08)
  )
  grid::grid.lines(
    x = grid::unit(c(x - w * 0.36, x + w * 0.36), "npc"),
    y = grid::unit(c(y + h * 0.02, y + h * 0.02), "npc"),
    gp = grid::gpar(col = "#C5D8E6", lwd = 1.6, lty = 2)
  )
  grid::grid.text(
    bottom, x = x, y = y - h * 0.22,
    gp = grid::gpar(col = pal$ink, fontsize = 7.5, fontfamily = "serif",
                    lineheight = 1.08)
  )
}

.mm_ga_parse_cohorts <- function(cohorts) {
  if (is.null(cohorts) || !length(cohorts)) return(list(list(name = "Cohort", country = "")))
  if (length(cohorts) == 1L && grepl("\\+", cohorts)) {
    cohorts <- trimws(strsplit(as.character(cohorts), "\\+")[[1L]])
  }
  lapply(as.character(cohorts), function(s) {
    m <- regexec("^\\s*(.+?)\\s*\\(([^)]+)\\)\\s*$", s)
    g <- regmatches(s, m)[[1L]]
    if (length(g) >= 3L) list(name = g[[2L]], country = g[[3L]])
    else list(name = trimws(s), country = "")
  })
}

.mm_ga_split_result <- function(txt) {
  # "A\nB" → top/bottom；否则按 & 或首行切
  parts <- strsplit(as.character(txt)[1L], "\n", fixed = TRUE)[[1L]]
  parts <- parts[nzchar(trimws(parts))]
  if (length(parts) >= 2L) {
    return(list(top = parts[[1L]], bottom = paste(parts[-1L], collapse = "\n")))
  }
  list(top = as.character(txt)[1L], bottom = "")
}

.mm_ga_draw <- function(ga, cols, pal, assets) {
  cohorts <- .mm_ga_parse_cohorts(ga$cohorts %||% "Cohort")
  exp_a <- as.character(ga$exposure_a %||% "Obesity")[1L]
  exp_b <- as.character(ga$exposure_b %||% "Diabetes")[1L]
  outcome <- as.character(ga$outcome %||% "Stroke")[1L]
  joint_lab <- as.character(ga$joint_label %||% "Joint trajectories")[1L]
  methods <- as.character(ga$methods %||% c(
    "Data cleaning",
    "Kml3D clustering\nalgorithm",
    "Generalized\nEstimating\nEquations"
  ))
  if (length(methods) < 3L) methods <- c(methods, rep("", 3L - length(methods)))

  process_titles <- as.character(ga$process_titles %||% c(
    "Main analysis:", "Secondary analysis:", "Sensitive analysis:"
  ))
  process_bodies <- as.character(ga$process %||% c(
    "Grouping based on a clustering algorithm:\nBMI & Diabetes",
    "Grouping based on Age Group:\nAge < 65 / Age >= 65\nGrouping based on a clustering algorithm:\nBMI & Diabetes",
    "Repeated the main analysis:\nExcluded underweight participants\nRandomly excluded 20% of the participants"
  ))
  # 若 process 行自带 "Main analysis:" 标题，拆开
  for (i in seq_along(process_bodies)) {
    ln <- strsplit(process_bodies[[i]], "\n", fixed = TRUE)[[1L]]
    if (length(ln) >= 2L && grepl("analysis\\s*:", ln[[1L]], ignore.case = TRUE)) {
      process_titles[[i]] <- ln[[1L]]
      process_bodies[[i]] <- paste(ln[-1L], collapse = "\n")
    }
  }
  if (length(process_titles) < 3L) process_titles <- c(process_titles, rep("", 3L - length(process_titles)))
  if (length(process_bodies) < 3L) process_bodies <- c(process_bodies, rep("", 3L - length(process_bodies)))

  results <- as.character(ga$results %||% c(
    "Obesity (BMI) & Diabetes (HbA1c)\nHeterogeneous results in four cohorts",
    "Obesity (BMI) & Diabetes (HbA1c)\nParticipants in obesity & Diabetes group had Stroke (OR>1; P<0.05)"
  ))
  if (length(results) < 2L) results <- c(results, "")

  if (length(cols) >= 2L && isTRUE(ga$random_colors %||% FALSE)) {
    pal$header <- cols[1:2]
    if (length(cols) >= 3L) pal$process_fill <- cols[[3L]]
    if (length(cols) >= 4L) pal$circle <- c(cols[[4L]], cols[[1L]], cols[[2L]])
  }

  grid::grid.newpage()
  grid::grid.rect(gp = grid::gpar(fill = pal$bg, col = NA))

  # ---- 四栏标题 ----
  .mm_ga_header_pill("Cohorts",          0.10, 0.935, w = 0.13, pal = pal)
  .mm_ga_header_pill("Variables",        0.30, 0.935, w = 0.14, pal = pal)
  .mm_ga_header_pill("Research process", 0.58, 0.935, w = 0.22, pal = pal)
  .mm_ga_header_pill("Results",          0.86, 0.935, w = 0.13, pal = pal)

  # ---- Col1 Cohorts：图标+文字整组相对面板水平居中 ----
  coh_x <- 0.10
  coh_w <- 0.15
  .mm_ga_panel(coh_x, 0.48, coh_w, 0.78, pal)
  n_coh <- length(cohorts)
  ys_coh <- if (n_coh <= 1L) 0.48 else seq(0.64, 0.34, length.out = n_coh)
  for (i in seq_len(n_coh)) {
    yi <- ys_coh[[i]]
    ic <- if (i %% 2L == 1L) assets$cohort1 else assets$cohort2
    lab <- cohorts[[i]]$name
    if (nzchar(cohorts[[i]]$country)) {
      lab <- paste0(cohorts[[i]]$name, "\n(", cohorts[[i]]$country, ")")
    }
    # 组中心对齐面板；图标完整落在面板内（勿贴左边线）
    .mm_ga_raster(ic, coh_x + 0.002, yi, w = 0.034)
    grid::grid.text(
      lab, x = coh_x + 0.030, y = yi, just = "left",
      gp = grid::gpar(col = pal$ink, fontsize = 11, fontface = "bold",
                      fontfamily = "serif", lineheight = 1.05)
    )
  }

  # ---- Col2 Variables：与 var_x 共轴居中，图文间距统一 ----
  var_x <- 0.30
  .mm_ga_panel(var_x, 0.48, 0.18, 0.78, pal)
  card_w <- 0.15
  gap_il <- 0.012
  icon_w_ab <- 0.042
  txt_h <- 0.024

  # 上卡：A + B（内容必须落在白卡内，避免 Diabetes 被裁切）
  card1_y <- 0.70
  card1_h <- 0.34
  grid::grid.roundrect(
    x = grid::unit(var_x, "npc"), y = grid::unit(card1_y, "npc"),
    width = grid::unit(card_w, "npc"), height = grid::unit(card1_h, "npc"),
    r = grid::unit(0.015, "npc"),
    gp = grid::gpar(fill = pal$white, col = NA)
  )
  y_cursor <- card1_y + card1_h / 2 - 0.012
  h_ob <- .mm_ga_img_h_npc(assets$obesity, icon_w_ab)
  .mm_ga_raster(assets$obesity, var_x, y_cursor - h_ob / 2, w = icon_w_ab)
  y_cursor <- y_cursor - h_ob - gap_il
  grid::grid.text(exp_a, x = var_x, y = y_cursor, just = c("centre", "top"),
                  gp = grid::gpar(col = pal$ink, fontsize = 10, fontface = "bold",
                                  fontfamily = "serif"))
  y_cursor <- y_cursor - txt_h - 0.008
  .mm_ga_raster(assets$plus, var_x, y_cursor - 0.008, w = 0.016)
  y_cursor <- y_cursor - 0.022
  h_db <- .mm_ga_img_h_npc(assets$diabetes, icon_w_ab)
  .mm_ga_raster(assets$diabetes, var_x, y_cursor - h_db / 2, w = icon_w_ab)
  y_cursor <- y_cursor - h_db - gap_il
  grid::grid.text(exp_b, x = var_x, y = y_cursor, just = c("centre", "top"),
                  gp = grid::gpar(col = pal$ink, fontsize = 10, fontface = "bold",
                                  fontfamily = "serif"))
  .mm_ga_arrow_down_white(var_x, 0.495, pal)

  # 中卡：Joint trajectories
  grid::grid.roundrect(
    x = grid::unit(var_x, "npc"), y = grid::unit(0.355, "npc"),
    width = grid::unit(card_w, "npc"), height = grid::unit(0.14, "npc"),
    r = grid::unit(0.015, "npc"),
    gp = grid::gpar(fill = pal$white, col = NA)
  )
  w_tr <- 0.110
  h_tr <- .mm_ga_img_h_npc(assets$traj, w_tr)
  y_tr_top <- 0.410
  .mm_ga_raster(assets$traj, var_x, y_tr_top - h_tr / 2, w = w_tr)
  grid::grid.text(joint_lab, x = var_x, y = y_tr_top - h_tr - gap_il,
                  just = c("centre", "top"),
                  gp = grid::gpar(col = pal$ink, fontsize = 9, fontface = "bold",
                                  fontfamily = "serif"))
  .mm_ga_arrow_down_white(var_x, 0.255, pal)

  # 下卡：Outcome（同一 gap_il）
  grid::grid.roundrect(
    x = grid::unit(var_x, "npc"), y = grid::unit(0.140, "npc"),
    width = grid::unit(card_w, "npc"), height = grid::unit(0.14, "npc"),
    r = grid::unit(0.015, "npc"),
    gp = grid::gpar(fill = pal$white, col = NA)
  )
  h_out <- .mm_ga_img_h_npc(assets$outcome, icon_w_ab)
  y_out_top <- 0.190
  .mm_ga_raster(assets$outcome, var_x, y_out_top - h_out / 2, w = icon_w_ab)
  grid::grid.text(outcome, x = var_x, y = y_out_top - h_out - gap_il,
                  just = c("centre", "top"),
                  gp = grid::gpar(col = pal$ink, fontsize = 10, fontface = "bold",
                                  fontfamily = "serif"))

  # ---- 方法方标：强制正方形；底边→文字顶边间距统一 ----
  circ_y <- c(0.745, 0.505, 0.250)
  circ_x <- 0.435
  method_imgs <- list(assets$method1, assets$method2, assets$method3)
  method_w <- 0.055
  method_h <- method_w * 11.12 / 5.94
  method_gap <- 0.018
  for (i in 1:3) {
    yi <- circ_y[[i]]
    .mm_ga_raster(method_imgs[[i]], circ_x, yi, w = method_w, h = method_h)
    grid::grid.text(
      methods[[i]], x = circ_x, y = yi - method_h / 2 - method_gap,
      just = c("centre", "top"),
      gp = grid::gpar(col = pal$ink, fontsize = 7.5, fontface = "bold",
                      fontfamily = "serif", lineheight = 0.98)
    )
  }

  # ---- Col3 Research process ----
  proc_x <- 0.625
  proc_w <- 0.255
  proc_h <- c(0.18, 0.23, 0.18)
  proc_y <- c(0.72, 0.48, 0.22)
  for (i in 1:3) {
    .mm_ga_process_box(process_titles[[i]], process_bodies[[i]],
                       proc_x, proc_y[[i]], proc_w, proc_h[[i]], pal)
  }
  .mm_ga_arrow_down_thick(proc_x, 0.72 - proc_h[[1]] / 2 - 0.002,
                          0.48 + proc_h[[2]] / 2 + 0.002, pal$arrow_proc, stem = 0.030)
  .mm_ga_arrow_down_thick(proc_x, 0.48 - proc_h[[2]] / 2 - 0.002,
                          0.22 + proc_h[[3]] / 2 + 0.002, pal$arrow_proc, stem = 0.030)

  # ---- Col4 Results（蓝色大面板 + 两张白卡）----
  grid::grid.roundrect(
    x = grid::unit(0.875, "npc"), y = grid::unit(0.48, "npc"),
    width = grid::unit(0.185, "npc"), height = grid::unit(0.78, "npc"),
    r = grid::unit(0.04, "npc"),
    gp = grid::gpar(fill = pal$results_bg, col = NA)
  )
  r1 <- .mm_ga_split_result(results[[1L]])
  r2 <- .mm_ga_split_result(results[[2L]])
  .mm_ga_result_inner(r1$top, r1$bottom, 0.875, 0.64, 0.16, 0.32, pal)
  .mm_ga_result_inner(r2$top, r2$bottom, 0.875, 0.24, 0.16, 0.26, pal)

  grid::grid.text(
    "Graphical abstract (non-formal)",
    x = 0.5, y = 0.025,
    gp = grid::gpar(col = "#999999", fontsize = 7, fontfamily = "sans")
  )
}

block_multimorbidity_graphical_abstract <- function(ctx, ...) {
  mm <- ctx$config$multimorbidity %||% list()
  ga <- mm$graphical_abstract %||% list()
  root_out <- ctx$config$project$output_dir %||% "Output"
  out_dir <- file.path(root_out, "Figures", "graphical_abstract")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (is.null(ga$cohorts)) {
    ga$cohorts <- ctx$config$project$database %||% "Cohort"
  }

  if (!exists("block_colors", mode = "function")) {
    root <- ctx$project_root %||% getwd()
    cp <- file.path(root, "R/color_palettes.R")
    if (file.exists(cp)) source(cp, local = FALSE)
  }
  # png 包
  if (!requireNamespace("png", quietly = TRUE)) {
    cli::cli_abort("需要 png 包以嵌入流程图1配色.ai 图标资源")
  }

  pal <- .mm_ga_ai_palette()
  cols <- .mm_ga_pick_colors(ga, ctx$config, n = 4L)
  used_seed <- suppressWarnings(as.integer(ga$color_seed %||% NA_integer_)[1L])

  adir <- .mm_ga_assets_dir(ctx)
  assets <- list(
    cohort1  = .mm_ga_read_png(file.path(adir, "cohort_icon_1.png")),
    cohort2  = .mm_ga_read_png(file.path(adir, "cohort_icon_2.png")),
    obesity  = .mm_ga_read_png(file.path(adir, "icon_obesity.png")),
    diabetes = .mm_ga_read_png(file.path(adir, "icon_diabetes.png")),
    plus     = .mm_ga_read_png(file.path(adir, "icon_plus.png")),
    traj     = .mm_ga_read_png(file.path(adir, "icon_traj.png")),
    outcome  = .mm_ga_read_png(file.path(adir, "icon_outcome.png")),
    method1  = .mm_ga_read_png(file.path(adir, "method_icon_1.png")),
    method2  = .mm_ga_read_png(file.path(adir, "method_icon_2.png")),
    method3  = .mm_ga_read_png(file.path(adir, "method_icon_3.png"))
  )
  n_miss <- sum(vapply(assets, is.null, logical(1)))
  if (n_miss > 0L) {
    cli::cli_alert_warning("缺少 {n_miss} 个摘要图图标资源（{adir}），将以空白占位")
  }

  pdf_path <- file.path(out_dir, "Graphical_abstract_research_process.pdf")
  # 页面比例贴近 .ai：800.889 × 428 pt
  grDevices::pdf(pdf_path, width = 11.12, height = 5.94, useDingbats = FALSE)
  on.exit({
    if (grDevices::dev.cur() > 1) grDevices::dev.off()
  }, add = TRUE)
  .mm_ga_draw(ga, cols, pal, assets)

  meta <- file.path(out_dir, "README_non_formal.txt")
  writeLines(c(
    "This folder holds NON-FORMAL graphical abstract only.",
    "Do not renumber as Figure 1-N in summary_results.",
    "Layout locked to 流程图1配色.ai (icons + flowchart1 palette).",
    paste0("assets_dir=", adir),
    paste0("colors=", paste(cols, collapse = ",")),
    paste0("random_colors=", isTRUE(ga$random_colors %||% FALSE)),
    paste0("color_seed=", if (is.finite(used_seed)) used_seed else "ai-default")
  ), meta)

  ctx$results$multimorbidity_graphical_abstract <- list(
    pdf = pdf_path, formal = FALSE, colors = cols,
    random_colors = isTRUE(ga$random_colors %||% FALSE),
    color_seed = used_seed, palette = "flowchart1",
    assets_dir = adir
  )
  cli::cli_alert_success(
    "非正式研究过程图 → {pdf_path}（palette=flowchart1 / .ai icons）"
  )
  ctx
}

register_block(
  "multimorbidity_graphical_abstract",
  block_multimorbidity_graphical_abstract,
  "多病叠加研究过程摘要图（非正式；对齐流程图1配色.ai）"
)
