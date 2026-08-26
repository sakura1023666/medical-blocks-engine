###############################################################################
# dual_db_combine_figures.R — 汇总 Figures 成对分库 PDF → A/B 拼图
#
# 挂点：incidence_batch_finalize_index_outputs（mirror_dual_db_aggregate 之后）
# 规格：docs/superpowers/specs/2026-08-12-dual-db-combine-paired-figures-design.md
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

# 本文件所在目录（source 时记录），供定位 dual_db_compose_pair_vector.py
.DUAL_DB_COMBINE_DIR <- tryCatch({
  of <- sys.frame(1)$ofile
  if (!is.null(of) && nzchar(as.character(of)[1L])) {
    dirname(normalizePath(of, winslash = "/", mustWork = FALSE))
  } else {
    NA_character_
  }
}, error = function(e) NA_character_)

.dual_db_combine_cfg <- function(config) {
  dd <- config$dual_db %||% list()
  cfg <- dd$combine_figures %||% list()
  list(
    enable = isTRUE(cfg$enable %||% TRUE),
    remove_singles = isTRUE(cfg$remove_singles %||% TRUE),
    drop_missing_overview = isTRUE(cfg$drop_missing_overview %||% TRUE),
    panel_order = as.character(cfg$panel_order %||% "primary_first")[1L],
    label_format = as.character(cfg$label_format %||% "A. {db}")[1L],
    layout_by_role = cfg$layout_by_role %||% NULL,
    dpi = as.integer(cfg$dpi %||% 200L)[1L],
    label_cex = as.numeric(cfg$label_cex %||% 1.15)[1L],
    primary = as.character((dd$primary %||% list())$name %||% "primary")[1L],
    secondary = as.character((dd$secondary %||% list())$name %||% "secondary")[1L],
    tertiary = as.character((dd$tertiary %||% list())$name %||% "")[1L],
    databases = {
      d <- unique(c(
        as.character((dd$primary %||% list())$name %||% "")[1L],
        as.character((dd$secondary %||% list())$name %||% "")[1L],
        as.character((dd$tertiary %||% list())$name %||% "")[1L],
        as.character(dd$databases %||% character(0))
      ))
      d[nzchar(d)]
    }
  )
}

.dual_db_panel_label <- function(letter, db, fmt = "A. {db}") {
  db <- as.character(db %||% "")[1L]
  out <- gsub("{db}", db, fmt, fixed = TRUE)
  # 允许配置写成 "A. {db}"；B 面板自动换字母
  out <- sub("^[A-Z]\\.", paste0(letter, "."), out)
  if (!grepl(paste0("^", letter, "\\."), out)) {
    out <- paste0(letter, ". ", db)
  }
  out
}

.dual_db_is_missing_overview <- function(bn) {
  grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)
}

#' 从文件名解析库标签与配对键
#' @return NULL 或 list(db=, key=, layout_hint=)
.dual_db_parse_paired_figure_bn <- function(bn, db_names) {
  bn <- as.character(bn %||% "")[1L]
  if (!nzchar(bn) || !grepl("\\.pdf$", bn, ignore.case = TRUE)) return(NULL)
  if (!grepl("^Figure", bn, ignore.case = TRUE)) return(NULL)
  if (.dual_db_is_missing_overview(bn)) return(NULL)

  db_names <- unique(as.character(db_names[nzchar(as.character(db_names))]))
  if (!length(db_names)) return(NULL)
  # 长名优先，避免短前缀误伤
  db_names <- db_names[order(-nchar(db_names))]
  stem <- sub("\\.pdf$", "", bn, ignore.case = TRUE)

  for (db in db_names) {
    # Figure N-DB. Caption  / Figure SN-DB. Caption
    re_dash <- paste0(
      "^(Figure\\s+[0-9S]+)-",
      .dual_db_regex_escape(db),
      "(\\..+)$"
    )
    if (grepl(re_dash, stem, ignore.case = TRUE, perl = TRUE)) {
      key <- paste0(
        sub(re_dash, "\\1\\2", stem, ignore.case = TRUE, perl = TRUE),
        ".pdf"
      )
      return(list(db = db, key = key, mode = "dash"))
    }
    # Figure N. DB. Caption（ML curate）
    re_dot <- paste0(
      "^(Figure\\s+[0-9S]+)\\.\\s*",
      .dual_db_regex_escape(db),
      "\\.\\s*(.+)$"
    )
    if (grepl(re_dot, stem, ignore.case = TRUE, perl = TRUE)) {
      key <- paste0(
        sub(re_dot, "\\1. \\2", stem, ignore.case = TRUE, perl = TRUE),
        ".pdf"
      )
      return(list(db = db, key = key, mode = "dot"))
    }
  }
  NULL
}

.dual_db_regex_escape <- function(x) {
  gsub("([][{}()+*^$|\\\\.?])", "\\\\\\1", as.character(x %||% "")[1L], perl = TRUE)
}

.dual_db_layout_for_key <- function(key, layout_by_role = NULL) {
  key <- as.character(key %||% "")[1L]
  if (is.list(layout_by_role) && length(layout_by_role)) {
    # 精确或关键词匹配
    if (!is.null(layout_by_role[[key]])) {
      v <- tolower(as.character(layout_by_role[[key]])[1L])
      if (v %in% c("stack", "side")) return(v)
    }
    for (nm in names(layout_by_role)) {
      if (nzchar(nm) && grepl(nm, key, ignore.case = TRUE, fixed = TRUE)) {
        v <- tolower(as.character(layout_by_role[[nm]])[1L])
        if (v %in% c("stack", "side")) return(v)
      }
    }
  }
  # 全局默认（后续所有 dual 项目）：
  # - RCS：上下（竖着）
  # - KM / 亚组森林：左右（横着）
  if (grepl("\\bRCS\\b|Restricted\\s*Cubic", key, ignore.case = TRUE)) {
    return("stack")
  }
  if (grepl("Subgroup\\s*Forest|Kaplan-?Meier|\\bKM\\b", key, ignore.case = TRUE)) {
    return("side")
  }
  "side"
}

.dual_db_is_per_db_fig1_flowchart <- function(bn) {
  grepl(
    "^Figure\\s+1-.+\\.\\s*Inclusion\\s+exclusion\\s+flowchart\\.pdf$",
    bn,
    ignore.case = TRUE
  )
}

.dual_db_pdf_to_png <- function(pdf_path, dpi = 200L) {
  pdf_path <- normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
  dpi <- max(72L, as.integer(dpi)[1L])
  tmp_dir <- tempfile("dual_fig_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  # 注意：不在此 on.exit 删除；由调用方清理 unlink_dir

  # 1) magick
  if (requireNamespace("magick", quietly = TRUE)) {
    img <- tryCatch(
      magick::image_read_pdf(pdf_path, density = dpi),
      error = function(e) NULL
    )
    if (!is.null(img) && length(img) >= 1L) {
      png <- file.path(tmp_dir, "page.png")
      magick::image_write(img[1L], path = png, format = "png")
      return(list(path = png, unlink_dir = tmp_dir))
    }
  }

  # 2) pdftools
  if (requireNamespace("pdftools", quietly = TRUE) &&
      requireNamespace("png", quietly = TRUE)) {
    bm <- tryCatch(
      pdftools::pdf_render_page(pdf_path, page = 1L, dpi = dpi),
      error = function(e) NULL
    )
    if (!is.null(bm)) {
      png <- file.path(tmp_dir, "page.png")
      tryCatch(png::writePNG(bm, png), error = function(e) NULL)
      if (file.exists(png)) {
        return(list(path = png, unlink_dir = tmp_dir))
      }
    }
  }

  # 3) pdftoppm / ghostscript（路径含空格或 【】 时先拷到纯 ASCII 临时文件）
  pdf_safe <- file.path(tmp_dir, "input.pdf")
  if (!isTRUE(file.copy(pdf_path, pdf_safe, overwrite = TRUE))) {
    unlink(tmp_dir, recursive = TRUE, force = TRUE)
    stop("无法复制 PDF 到临时目录: ", pdf_path, call. = FALSE)
  }

  pdftoppm <- Sys.which("pdftoppm")
  if (nzchar(pdftoppm)) {
    prefix <- file.path(tmp_dir, "page")
    st <- system2(
      pdftoppm,
      c("-png", "-r", as.character(dpi), "-f", "1", "-l", "1", "-singlefile",
        pdf_safe, prefix),
      stdout = TRUE, stderr = TRUE
    )
    hits <- Sys.glob(paste0(prefix, "*.png"))
    if (length(hits) && file.exists(hits[[1L]])) {
      return(list(path = hits[[1L]], unlink_dir = tmp_dir))
    }
  }

  gs <- Sys.which("gs")
  if (nzchar(gs)) {
    out_png <- file.path(tmp_dir, "page.png")
    st <- system2(
      gs,
      c(
        "-dSAFER", "-dBATCH", "-dNOPAUSE",
        "-sDEVICE=png16m",
        paste0("-r", dpi),
        "-dFirstPage=1", "-dLastPage=1",
        paste0("-sOutputFile=", out_png),
        pdf_safe
      ),
      stdout = TRUE, stderr = TRUE
    )
    if (file.exists(out_png)) {
      return(list(path = out_png, unlink_dir = tmp_dir))
    }
    unlink(tmp_dir, recursive = TRUE, force = TRUE)
    stop(
      "ghostscript 渲染失败: ", pdf_path, " — ",
      paste(st, collapse = " "),
      call. = FALSE
    )
  }

  unlink(tmp_dir, recursive = TRUE, force = TRUE)
  stop("无法渲染 PDF：缺少 magick/pdftools/pdftoppm/gs", call. = FALSE)
}

.dual_db_png_info <- function(png_path) {
  if (requireNamespace("png", quietly = TRUE)) {
    img <- png::readPNG(png_path)
    list(w = dim(img)[2L], h = dim(img)[1L], raster = grDevices::as.raster(img))
  } else if (requireNamespace("magick", quietly = TRUE)) {
    img <- magick::image_read(png_path)
    info <- magick::image_info(img)
    list(
      w = as.integer(info$width[1L]),
      h = as.integer(info$height[1L]),
      raster = as.raster(img)
    )
  } else {
    # 无 png/magick：用 pdftoppm 已出图，尺寸用 file + 假定；grid 用 nativeRaster via jpeg? 
    # 强制需要 png 包读图——若无则装不了时用 readBitmap 不行。退回 stop。
    stop("拼图需要 R 包 png 或 magick 以读取渲染结果", call. = FALSE)
  }
}

.dual_db_compose_pair_pdf_vector <- function(path_a, path_b, out_path, layout = "side",
                                             label_a = "A.", label_b = "B.",
                                             label_cex = 1.15) {
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) stop("python3 不可用，无法矢量拼图", call. = FALSE)

  script <- NULL
  cand <- c(
    if (!is.na(.DUAL_DB_COMBINE_DIR) && nzchar(.DUAL_DB_COMBINE_DIR)) {
      file.path(.DUAL_DB_COMBINE_DIR, "dual_db_compose_pair_vector.py")
    } else {
      character(0)
    },
    file.path(getwd(), "R", "dual_db_compose_pair_vector.py")
  )
  eng <- Sys.getenv("BLOCK_ENGINE_ROOT", unset = "")
  if (!nzchar(eng)) eng <- Sys.getenv("ENGINE_ROOT", unset = "")
  if (nzchar(eng)) cand <- c(cand, file.path(eng, "R", "dual_db_compose_pair_vector.py"))
  cand <- c(cand, "/mnt/e/01block/01Block-new-Final/R/dual_db_compose_pair_vector.py")
  for (p in unique(cand[nzchar(as.character(cand))])) {
    if (file.exists(p)) {
      script <- p
      break
    }
  }
  if (is.null(script) || !file.exists(script)) {
    stop("找不到 dual_db_compose_pair_vector.py", call. = FALSE)
  }

  tmp_dir <- tempfile("dual_vec_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
  # ASCII-safe copies (paths with 【】/spaces break some tools)
  a_safe <- file.path(tmp_dir, "a.pdf")
  b_safe <- file.path(tmp_dir, "b.pdf")
  out_safe <- file.path(tmp_dir, "out.pdf")
  if (!file.copy(path_a, a_safe, overwrite = TRUE) ||
      !file.copy(path_b, b_safe, overwrite = TRUE)) {
    stop("无法复制源 PDF 到临时目录", call. = FALSE)
  }

  font_size <- max(10, round(12 * as.numeric(label_cex %||% 1.15)[1L], 1))
  args <- c(
    script,
    "--a", a_safe,
    "--b", b_safe,
    "--out", out_safe,
    "--layout", as.character(layout %||% "side")[1L],
    "--label-a", as.character(label_a %||% "A.")[1L],
    "--label-b", as.character(label_b %||% "B.")[1L],
    "--font-size", as.character(font_size)
  )
  # Forest: 标签带加高，避免 A/B 压到表头；四周等边距居中
  if (grepl("Subgroup\\s*Forest", basename(out_path), ignore.case = TRUE)) {
    args <- c(
      args,
      "--margin-pt", "28",
      "--gap-pt", "16",
      "--label-h-pt", "32",
      "--font-size", "13"
    )
  }

  # 本机 R 的 system2 在重定向 stdout/stderr 时会走 shell，且不给含空格参数加引号
  cmd <- paste(shQuote(c(py, args), type = "cmd"), collapse = " ")
  # Unix: shQuote type=cmd is wrong; use type=sh
  if (.Platform$OS.type != "windows") {
    cmd <- paste(shQuote(c(py, args), type = "sh"), collapse = " ")
  }
  st <- tryCatch(
    system(cmd, intern = TRUE),
    error = function(e) conditionMessage(e)
  )
  status <- attr(st, "status")
  if (!file.exists(out_safe) || isTRUE((file.info(out_safe)$size %||% 0) < 500)) {
    stop(
      "矢量拼图失败: ", paste(st, collapse = " "),
      if (!is.null(status)) paste0(" [status=", status, "]") else "",
      call. = FALSE
    )
  }
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(out_path)) unlink(out_path, force = TRUE)
  if (!file.copy(out_safe, out_path, overwrite = TRUE)) {
    stop("无法写出拼图: ", out_path, call. = FALSE)
  }
  # 森林拼图：不再二次 bbox 裁切（会切掉轴端 0.2 的「0」与右侧末列）
  invisible(out_path)
}

.dual_db_compose_pair_pdf_raster <- function(path_a, path_b, out_path, layout = "side",
                                             label_a = "A.", label_b = "B.",
                                             dpi = 200L, label_cex = 1.15) {
  ra <- .dual_db_pdf_to_png(path_a, dpi = dpi)
  rb <- .dual_db_pdf_to_png(path_b, dpi = dpi)
  on.exit({
    unlink(ra$unlink_dir, recursive = TRUE, force = TRUE)
    unlink(rb$unlink_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  ia <- .dual_db_png_info(ra$path)
  ib <- .dual_db_png_info(rb$path)

  label_h_in <- 0.45
  margin_in <- 0.35
  a_w_in <- ia$w / dpi
  a_h_in <- ia$h / dpi
  b_w_in <- ib$w / dpi
  b_h_in <- ib$h / dpi

  layout <- tolower(as.character(layout %||% "side")[1L])
  open_pdf <- function(w, h) {
    ok <- FALSE
    if (isTRUE(capabilities("cairo"))) {
      ok <- tryCatch({
        grDevices::cairo_pdf(out_path, width = w, height = h, family = "Times New Roman")
        TRUE
      }, error = function(e) FALSE)
    }
    if (!ok) {
      grDevices::pdf(out_path, width = w, height = h, useDingbats = FALSE, family = "Times")
    }
  }

  label_gp <- grid::gpar(
    fontsize = 12 * label_cex, fontface = "bold",
    fontfamily = "Times New Roman"
  )

  if (identical(layout, "stack")) {
    panel_w <- max(a_w_in, b_w_in)
    a_h_s <- a_h_in * (panel_w / a_w_in)
    b_h_s <- b_h_in * (panel_w / b_w_in)
    total_w <- max(panel_w + 2 * margin_in, 4)
    total_h <- label_h_in + a_h_s + label_h_in + b_h_s + 3 * margin_in
    open_pdf(total_w, total_h)
    grid::grid.newpage()
    grid::grid.text(
      label_a,
      x = grid::unit(margin_in / total_w, "npc"),
      y = grid::unit(1 - margin_in / total_h, "npc"),
      just = c("left", "top"),
      gp = label_gp
    )
    y_a_top <- 1 - (margin_in + label_h_in) / total_h
    grid::grid.raster(
      ia$raster,
      x = grid::unit(0.5, "npc"),
      y = grid::unit(y_a_top, "npc"),
      width = grid::unit(panel_w / total_w, "npc"),
      height = grid::unit(a_h_s / total_h, "npc"),
      just = c("centre", "top")
    )
    y_b_lab <- y_a_top - a_h_s / total_h - margin_in / total_h
    grid::grid.text(
      label_b,
      x = grid::unit(margin_in / total_w, "npc"),
      y = grid::unit(y_b_lab, "npc"),
      just = c("left", "top"),
      gp = label_gp
    )
    y_b_top <- y_b_lab - label_h_in / total_h
    grid::grid.raster(
      ib$raster,
      x = grid::unit(0.5, "npc"),
      y = grid::unit(y_b_top, "npc"),
      width = grid::unit(panel_w / total_w, "npc"),
      height = grid::unit(b_h_s / total_h, "npc"),
      just = c("centre", "top")
    )
    grDevices::dev.off()
  } else {
    panel_h <- max(a_h_in, b_h_in)
    a_w_s <- a_w_in * (panel_h / a_h_in)
    b_w_s <- b_w_in * (panel_h / b_h_in)
    gap <- 0.25
    side_extra <- 0.1
    total_w <- a_w_s + b_w_s + gap + 2 * (margin_in + side_extra)
    total_h <- label_h_in + panel_h + 2 * margin_in
    max_w_in <- 22
    if (total_w > max_w_in) {
      sc <- max_w_in / total_w
      a_w_s <- a_w_s * sc
      b_w_s <- b_w_s * sc
      gap <- gap * sc
      panel_h <- panel_h * sc
      total_w <- max_w_in
      total_h <- label_h_in + panel_h + 2 * margin_in
    }
    open_pdf(total_w, total_h)
    grid::grid.newpage()
    x_a <- (margin_in + side_extra + a_w_s / 2) / total_w
    x_b <- (margin_in + side_extra + a_w_s + gap + b_w_s / 2) / total_w
    grid::grid.text(
      label_a,
      x = grid::unit(x_a, "npc"),
      y = grid::unit(1 - margin_in / total_h, "npc"),
      just = c("centre", "top"),
      gp = label_gp
    )
    grid::grid.text(
      label_b,
      x = grid::unit(x_b, "npc"),
      y = grid::unit(1 - margin_in / total_h, "npc"),
      just = c("centre", "top"),
      gp = label_gp
    )
    y_img <- 1 - (margin_in + label_h_in) / total_h
    grid::grid.raster(
      ia$raster,
      x = grid::unit(x_a, "npc"),
      y = grid::unit(y_img, "npc"),
      width = grid::unit(a_w_s / total_w, "npc"),
      height = grid::unit(panel_h / total_h, "npc"),
      just = c("centre", "top")
    )
    grid::grid.raster(
      ib$raster,
      x = grid::unit(x_b, "npc"),
      y = grid::unit(y_img, "npc"),
      width = grid::unit(b_w_s / total_w, "npc"),
      height = grid::unit(panel_h / total_h, "npc"),
      just = c("centre", "top")
    )
    grDevices::dev.off()
  }
  invisible(out_path)
}

.dual_db_compose_pair_pdf <- function(path_a, path_b, out_path, layout = "side",
                                      label_a = "A.", label_b = "B.",
                                      dpi = 200L, label_cex = 1.15) {
  # 优先矢量拼图（可编辑文字）；失败再栅格回退
  ok_vec <- tryCatch({
    .dual_db_compose_pair_pdf_vector(
      path_a, path_b, out_path,
      layout = layout, label_a = label_a, label_b = label_b,
      label_cex = label_cex
    )
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("矢量拼图不可用，回退栅格: {conditionMessage(e)}")
    FALSE
  })
  if (isTRUE(ok_vec) && file.exists(out_path) &&
      isTRUE((file.info(out_path)$size %||% 0) > 500)) {
    return(invisible(out_path))
  }
  .dual_db_compose_pair_pdf_raster(
    path_a, path_b, out_path,
    layout = layout, label_a = label_a, label_b = label_b,
    dpi = dpi, label_cex = label_cex
  )
}

.dual_db_find_compose_script <- function(script_name) {
  cand <- c(
    if (!is.na(.DUAL_DB_COMBINE_DIR) && nzchar(.DUAL_DB_COMBINE_DIR)) {
      file.path(.DUAL_DB_COMBINE_DIR, script_name)
    } else {
      character(0)
    },
    file.path(getwd(), "R", script_name)
  )
  eng <- Sys.getenv("BLOCK_ENGINE_ROOT", unset = "")
  if (!nzchar(eng)) eng <- Sys.getenv("ENGINE_ROOT", unset = "")
  if (nzchar(eng)) cand <- c(cand, file.path(eng, "R", script_name))
  cand <- c(cand, file.path("/mnt/e/01block/01Block-new-Final/R", script_name))
  for (p in unique(cand[nzchar(as.character(cand))])) {
    if (file.exists(p)) return(p)
  }
  NULL
}

.dual_db_per_db_tag_pattern <- function(db_names) {
  tags <- unique(as.character(db_names))
  tags <- tags[nzchar(tags)]
  if (!length(tags)) return("(?!)")
  alt <- paste(vapply(tags, .dual_db_regex_escape, character(1L)), collapse = "|")
  paste0("-(", alt, ")\\.")
}

.dual_db_compose_n_pdf_vector <- function(paths, labels, out_path, layout = "side",
                                          label_cex = 1.15) {
  paths <- as.character(paths)
  labels <- as.character(labels)
  if (length(paths) < 2L) stop("n-panel 拼图至少需要 2 个 PDF", call. = FALSE)
  if (length(labels) != length(paths)) {
    stop("labels 数量须与 paths 一致", call. = FALSE)
  }
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) stop("python3 不可用，无法矢量拼图", call. = FALSE)

  script <- .dual_db_find_compose_script("dual_db_compose_n_panel.py")
  if (is.null(script)) stop("找不到 dual_db_compose_n_panel.py", call. = FALSE)

  tmp_dir <- tempfile("dual_nvec_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)
  safe_paths <- vapply(seq_along(paths), function(i) {
    dst <- file.path(tmp_dir, sprintf("in_%03d.pdf", i))
    if (!file.copy(paths[[i]], dst, overwrite = TRUE)) {
      stop("无法复制源 PDF 到临时目录", call. = FALSE)
    }
    dst
  }, character(1))
  out_safe <- file.path(tmp_dir, "out.pdf")

  font_size <- max(10, round(12 * as.numeric(label_cex %||% 1.15)[1L], 1))
  n_layout <- if (length(paths) == 4L) "grid" else "side"
  args <- c(
    script,
    "--out", out_safe,
    "--inputs", safe_paths,
    "--labels", labels,
    "--layout", n_layout,
    "--font-size", as.character(font_size)
  )
  if (grepl("Subgroup\\s*Forest", basename(out_path), ignore.case = TRUE)) {
    args <- c(args, "--margin-pt", "28", "--gap-pt", "16", "--label-h-pt", "32", "--font-size", "13")
  }
  cmd <- if (.Platform$OS.type == "windows") {
    paste(shQuote(c(py, args), type = "cmd"), collapse = " ")
  } else {
    paste(shQuote(c(py, args), type = "sh"), collapse = " ")
  }
  st <- tryCatch(system(cmd, intern = TRUE), error = function(e) conditionMessage(e))
  status <- attr(st, "status")
  if (!file.exists(out_safe) || isTRUE((file.info(out_safe)$size %||% 0) < 500)) {
    stop(
      "n-panel 矢量拼图失败: ", paste(st, collapse = " "),
      if (!is.null(status)) paste0(" [status=", status, "]") else "",
      call. = FALSE
    )
  }
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(out_path)) unlink(out_path, force = TRUE)
  if (!file.copy(out_safe, out_path, overwrite = TRUE)) {
    stop("无法写出拼图: ", out_path, call. = FALSE)
  }
  invisible(out_path)
}

.dual_db_compose_n_pdf_raster <- function(paths, labels, out_path, layout = "side",
                                          dpi = 200L, label_cex = 1.15) {
  paths <- as.character(paths)
  labels <- as.character(labels)
  n <- length(paths)
  if (n < 2L) stop("n-panel 栅格拼图至少需要 2 个 PDF", call. = FALSE)
  imgs <- lapply(paths, function(p) .dual_db_pdf_to_png(p, dpi = dpi))
  on.exit({
    for (im in imgs) unlink(im$unlink_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  infos <- lapply(imgs, function(im) .dual_db_png_info(im$path))

  dpi <- max(72L, as.integer(dpi)[1L])
  label_h_in <- 0.45
  margin_in <- 0.35
  gap_in <- 0.25

  cols <- if (n == 4L) 2L else n
  rows <- if (n == 4L) 2L else 1L
  grid <- vector("list", n)
  idx <- 1L
  for (r in seq_len(rows)) {
    row_idx <- idx:min(idx + cols - 1L, n)
    panel_h <- max(vapply(infos[row_idx], function(x) x$h / dpi, numeric(1)))
    row_w <- 0
    for (i in row_idx) {
      w_in <- infos[[i]]$w / dpi
      h_in <- infos[[i]]$h / dpi
      sc <- panel_h / h_in
      grid[[i]] <- list(w = w_in * sc, h = panel_h, raster = infos[[i]]$raster)
      row_w <- row_w + w_in * sc
    }
    row_w <- row_w + gap_in * max(0L, length(row_idx) - 1L)
    for (i in row_idx) grid[[i]]$row_w <- row_w
    idx <- idx + cols
  }

  content_w <- max(vapply(grid, function(g) g$row_w %||% g$w, numeric(1)))
  content_h <- rows * (label_h_in + max(vapply(grid, function(g) g$h, numeric(1)))) +
    gap_in * max(0L, rows - 1L)
  total_w <- max(content_w + 2 * margin_in, 4)
  total_h <- content_h + 2 * margin_in

  open_pdf <- function(w, h) {
    ok <- FALSE
    if (isTRUE(capabilities("cairo"))) {
      ok <- tryCatch({
        grDevices::cairo_pdf(out_path, width = w, height = h, family = "Times New Roman")
        TRUE
      }, error = function(e) FALSE)
    }
    if (!ok) {
      grDevices::pdf(out_path, width = w, height = h, useDingbats = FALSE, family = "Times")
    }
  }
  label_gp <- grid::gpar(
    fontsize = 12 * label_cex, fontface = "bold",
    fontfamily = "Times New Roman"
  )
  open_pdf(total_w, total_h)
  grid::grid.newpage()
  y_top <- 1 - margin_in / total_h
  idx <- 1L
  for (r in seq_len(rows)) {
    row_idx <- idx:min(idx + cols - 1L, n)
    panel_h <- max(vapply(grid[row_idx], function(g) g$h, numeric(1)))
    row_w <- grid[[row_idx[[1L]]]]$row_w
    x_row <- (total_w - row_w) / 2 / total_w
    x_cur <- x_row
    for (i in row_idx) {
      g <- grid[[i]]
      grid::grid.text(
        labels[[i]],
        x = grid::unit(x_cur + (g$w / 2) / total_w, "npc"),
        y = grid::unit(y_top, "npc"),
        just = c("centre", "top"),
        gp = label_gp
      )
      y_img <- y_top - label_h_in / total_h
      grid::grid.raster(
        g$raster,
        x = grid::unit(x_cur + (g$w / 2) / total_w, "npc"),
        y = grid::unit(y_img, "npc"),
        width = grid::unit(g$w / total_w, "npc"),
        height = grid::unit(panel_h / total_h, "npc"),
        just = c("centre", "top")
      )
      x_cur <- x_cur + (g$w + gap_in) / total_w
    }
    y_top <- y_top - (label_h_in + panel_h + gap_in) / total_h
    idx <- idx + cols
  }
  grDevices::dev.off()
  invisible(out_path)
}

.dual_db_compose_n_pdf <- function(paths, labels, out_path, layout = "side",
                                     dpi = 200L, label_cex = 1.15) {
  ok_vec <- tryCatch({
    .dual_db_compose_n_pdf_vector(
      paths, labels, out_path,
      layout = layout, label_cex = label_cex
    )
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("n-panel 矢量拼图不可用，回退栅格: {conditionMessage(e)}")
    FALSE
  })
  if (isTRUE(ok_vec) && file.exists(out_path) &&
      isTRUE((file.info(out_path)$size %||% 0) > 500)) {
    return(invisible(out_path))
  }
  .dual_db_compose_n_pdf_raster(
    paths, labels, out_path,
    layout = layout, dpi = dpi, label_cex = label_cex
  )
}

#' 汇总目录双库成对发表图拼图
#'
#' @param index_root by_index/<ix> 根目录
#' @param config 完整 config（读 dual_db$combine_figures / primary/secondary$name）
#' @param figures_dir 可选；默认 `file.path(index_root, "Figures")`，交叉滞后可传 `summary_result/figure`
#' @return invisible list(combined=, deleted=, skipped=)
dual_db_combine_paired_figures <- function(index_root, config, figures_dir = NULL) {
  cfg <- .dual_db_combine_cfg(config)
  if (!isTRUE(cfg$enable)) return(invisible(list(combined = character(), deleted = character(), skipped = character())))

  figs <- if (!is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])) {
    as.character(figures_dir)[1L]
  } else {
    file.path(index_root, "Figures")
  }
  if (!dir.exists(figs)) {
    return(invisible(list(combined = character(), deleted = character(), skipped = character())))
  }

  pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  deleted <- character(0)
  if (isTRUE(cfg$drop_missing_overview)) {
    miss <- pdfs[.dual_db_is_missing_overview(basename(pdfs))]
    if (length(miss)) {
      unlink(miss)
      deleted <- c(deleted, basename(miss))
      cli::cli_alert_info("已删除缺失概览图 {length(miss)} 个")
      pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
    }
  }
  # 汇总目录只要 Figure 1. Flowchart.pdf；分库 Inclusion exclusion 底稿仅留在各库子目录
  fig1_singles <- pdfs[.dual_db_is_per_db_fig1_flowchart(basename(pdfs))]
  if (length(fig1_singles)) {
    unlink(fig1_singles)
    deleted <- c(deleted, basename(fig1_singles))
    cli::cli_alert_info("已删除汇总目录分库 Figure 1 纳排图 {length(fig1_singles)} 个")
    pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  }

  db_names <- if (length(cfg$databases)) cfg$databases else unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
  db_names <- db_names[nzchar(db_names)]
  # 也收集文件名中出现的库标签（防配置名与文件不完全一致）
  per_db_pat <- .dual_db_per_db_tag_pattern(db_names)
  for (bn in basename(pdfs)) {
    m <- regmatches(bn, regexpr(per_db_pat, bn, ignore.case = TRUE, perl = TRUE))
    if (length(m) && nzchar(m)) {
      db_names <- unique(c(db_names, sub("^-", "", sub("\\.$", "", m))))
    }
  }

  buckets <- list()
  for (fp in pdfs) {
    parsed <- .dual_db_parse_paired_figure_bn(basename(fp), db_names)
    if (is.null(parsed)) next
    key <- parsed$key
    if (is.null(buckets[[key]])) buckets[[key]] <- list()
    buckets[[key]][[parsed$db]] <- fp
  }

  order_dbs <- cfg$databases
  if (!length(order_dbs)) order_dbs <- unique(c(cfg$primary, cfg$secondary, cfg$tertiary))
  order_dbs <- order_dbs[nzchar(order_dbs)]
  if (identical(cfg$panel_order, "secondary_first") && length(order_dbs) >= 2L) {
    order_dbs <- c(order_dbs[2L], order_dbs[1L], order_dbs[-c(1L, 2L)])
  }

  combined <- character(0)
  skipped <- character(0)

  for (key in names(buckets)) {
    pair <- buckets[[key]]
    dbs_have <- names(pair)
    if (length(dbs_have) < 2L) {
      skipped <- c(skipped, key)
      cli::cli_alert_warning("多库拼图缺配对，保留单图: {key}（仅有 {paste(dbs_have, collapse = ', ')}）")
      next
    }
    # 若汇总目录已有同角色无库标签拼图，跳过（按角色而非图号，避免 KM 占住 Fig2 后 RCS 被跳过）
    role_fn <- if (exists("incidence_batch_prognosis_figure_role", mode = "function")) {
      incidence_batch_prognosis_figure_role
    } else {
      NULL
    }
    role <- if (is.function(role_fn)) role_fn(key) else NA_character_
    if (!is.na(role) && nzchar(role) && !role %in% c("other", "drop")) {
      agg_pdfs <- list.files(figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
      agg_pdfs <- agg_pdfs[!grepl(.dual_db_per_db_tag_pattern(db_names), basename(agg_pdfs), ignore.case = TRUE, perl = TRUE)]
      same_role <- agg_pdfs[vapply(basename(agg_pdfs), function(bn) {
        identical(role_fn(bn), role)
      }, logical(1L))]
      same_role <- same_role[basename(same_role) != key]
      if (length(same_role)) {
        cli::cli_alert_info("已有多库合成图 {basename(same_role[[1L]])}，跳过再拼 {key}")
        if (isTRUE(cfg$remove_singles)) {
          victims <- unlist(pair, use.names = FALSE)
          unlink(victims)
          deleted <- c(deleted, basename(victims))
        }
        skipped <- c(skipped, key)
        next
      }
    }
    # 若配置名与文件标签大小写不同，做模糊匹配
    resolve <- function(want) {
      if (!is.null(pair[[want]])) return(list(db = want, path = pair[[want]]))
      hit <- dbs_have[tolower(dbs_have) == tolower(want)]
      if (length(hit)) return(list(db = hit[[1L]], path = pair[[hit[[1L]]]]))
      NULL
    }
    paths <- lapply(order_dbs, resolve)
    paths <- Filter(Negate(is.null), paths)
    if (length(paths) < 2L) {
      # 配置顺序未命中时，按 pair 内现有顺序拼
      paths <- lapply(dbs_have, function(db) list(db = db, path = pair[[db]]))
    }
    if (length(paths) < 2L) {
      skipped <- c(skipped, key)
      next
    }
    layout <- .dual_db_layout_for_key(key, cfg$layout_by_role)
    out_path <- file.path(figs, key)
    labels <- vapply(seq_along(paths), function(i) {
      .dual_db_panel_label(LETTERS[[i]], paths[[i]]$db, cfg$label_format)
    }, character(1))
    pdf_paths <- vapply(paths, function(x) x$path, character(1))
    ok <- tryCatch({
      if (length(pdf_paths) == 2L) {
        .dual_db_compose_pair_pdf(
          pdf_paths[[1L]], pdf_paths[[2L]], out_path,
          layout = layout,
          label_a = labels[[1L]], label_b = labels[[2L]],
          dpi = cfg$dpi, label_cex = cfg$label_cex
        )
      } else {
        .dual_db_compose_n_pdf(
          pdf_paths, labels, out_path,
          layout = layout, dpi = cfg$dpi, label_cex = cfg$label_cex
        )
      }
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("拼图失败 [{key}]: {e$message}")
      FALSE
    })
    if (!isTRUE(ok) || !file.exists(out_path)) {
      skipped <- c(skipped, key)
      next
    }
    combined <- c(combined, key)
    if (isTRUE(cfg$remove_singles)) {
      victims <- unique(pdf_paths)
      victims <- victims[normalizePath(victims, winslash = "/", mustWork = FALSE) !=
        normalizePath(out_path, winslash = "/", mustWork = FALSE)]
      if (length(victims)) {
        unlink(victims)
        deleted <- c(deleted, basename(victims))
      }
    }
  }

  if (length(combined)) {
    db_msg <- paste(order_dbs, collapse = ", ")
    cli::cli_alert_success(
      "多库拼图完成: {length(combined)} 张（layout=auto; order={db_msg}）"
    )
  }
  # 仅当真的拼出了多库图，才清汇总目录里的分库底稿。
  if (isTRUE(cfg$remove_singles) && length(combined) > 0L) {
    purged <- dual_db_purge_single_db_figures(figs, tags = db_names)
    if (length(purged)) deleted <- unique(c(deleted, purged))
  } else if (isTRUE(cfg$remove_singles) && !length(combined)) {
    cli::cli_alert_info("未拼成多库图，汇总 Figures 保留分库单图")
  }
  invisible(list(combined = combined, deleted = deleted, skipped = skipped))
}

#' 汇总 Figures 目录：删除带库标签的单库 PDF（保留无标签拼图）
#' @param figs_dir by_index/<ix>/Figures
#' @param tags 库标签；默认常见双库名
#' @return 已删文件 basename 向量
dual_db_purge_single_db_figures <- function(figs_dir,
                                            tags = c("eICU", "MIMIC", "NHANES", "eicu", "mimic", "nhanes")) {
  if (!dir.exists(figs_dir)) return(character(0))
  tags <- unique(as.character(tags))
  tags <- tags[nzchar(tags)]
  if (!length(tags)) return(character(0))
  alt <- paste(vapply(tags, .dual_db_regex_escape, character(1L)), collapse = "|")
  # Figure 4-eICU. ... / Figure S3-MIMIC. ...
  pat <- paste0("^Figure .+-(", alt, ")\\.")
  victims <- list.files(figs_dir, pattern = pat, full.names = TRUE, ignore.case = TRUE)
  if (!length(victims)) return(character(0))
  unlink(victims)
  cli::cli_alert_info("汇总 Figures 已清除分库单图 {length(victims)} 个")
  basename(victims)
}
