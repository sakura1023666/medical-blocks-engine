###############################################################################
#  clpn_network_plot.R — 出版 Fig4 CLPN
#
#  画法对齐课题交付脚本 Step07 plot_clpn()：
#    W <- exp(beta); diag=0; OR∈[0.95,1.05]→0
#    qgraph(layout="spring", layout.par=list(repulse.rad=80),
#           vsize=4, esize=3, pdf 18×14)
#    OR>1 红 / OR<1 蓝
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

clpn_plot_short_labels <- function(stems, root = NULL) {
  stems <- as.character(stems)
  sh <- if (exists("clpn_node_short", mode = "function")) {
    clpn_node_short(stems, root = root)
  } else {
    rep("", length(stems))
  }
  grp <- if (exists("clpn_node_group", mode = "function")) {
    clpn_node_group(stems, root = root)
  } else {
    rep("Other", length(stems))
  }
  fi_i <- 0L
  out_i <- 0L
  lip_i <- 0L
  out <- character(length(stems))
  for (i in seq_along(stems)) {
    if (nzchar(sh[[i]])) {
      out[[i]] <- sh[[i]]
    } else if (identical(grp[[i]], "Outcome") ||
               stems[[i]] %in% c("Disease01", "Sarcopenia", "sarcop", "Disease_Group")) {
      out_i <- out_i + 1L
      out[[i]] <- paste0("D", out_i)
    } else if (identical(grp[[i]], "Lipid") ||
               stems[[i]] %in% c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl")) {
      lip_i <- lip_i + 1L
      out[[i]] <- paste0("L", lip_i)
    } else {
      fi_i <- fi_i + 1L
      out[[i]] <- paste0("FI", fi_i)
    }
  }
  if (any(duplicated(out))) out <- make.unique(out, sep = "")
  out
}

# 与 Step07 脚本一致的域分组（用于分色，非彩虹挤叠）
.clpn_stem_domain <- function(stem) {
  if (stem %in% c("Disease01", "Sarcopenia", "sarcop", "Disease_Group"))
    return("Outcome")
  if (stem %in% c("hibpe", "diabe", "cancre", "lunge", "psyche", "memrye", "arthre",
                  "hedimbp", "hedbts", "hedibca", "hedibar", "hediblu", "hedibps", "hedibpd"))
    return("Comorbidity")
  if (stem %in% c("dressa", "batha", "eata", "beda", "toilta", "mealsa", "shopa",
                  "medsa", "moneya", "headldr", "headlba", "headlea", "headlbe",
                  "headlwc", "headlpr", "headlsh", "headlmo", "headlme"))
    return("ADL")
  if (stem %in% c("srh", "armsa", "chaira", "climsa", "dimea", "lifta", "stoopa",
                  "walk100a", "walk10", "hemobwa", "hemobch", "hemobcs", "hemobst",
                  "hemobre", "hemobli", "hemobpi", "hehelf"))
    return("Mobility")
  if (stem %in% c("glass", "hear", "heeye", "hehear"))
    return("Sensory")
  if (stem %in% c("Triglycerides", "HDL_Cholesterol", "newtg", "newhdl"))
    return("Biomarker")
  "Other"
}

#' 出版 CLPN — 对齐 Step07 plot_clpn
#' @param or_band 长度 2，OR 落在开区间内则置 0；默认 c(0.95, 1.05)
#' @param repulse_rad qgraph spring 排斥；默认 80（与交付脚本一致）
clpn_plot_publication <- function(adj, stems, outfile, title = "",
                                  disease_display = NULL, root = NULL,
                                  layout = "spring",
                                  drop_self_loops = TRUE,
                                  fade_weak_edges = NULL,
                                  or_band = c(0.95, 1.05),
                                  repulse_rad = 80) {
  if (!requireNamespace("qgraph", quietly = TRUE))
    stop("clpn_plot_publication: 需要 qgraph", call. = FALSE)
  stems <- as.character(stems)
  k <- nrow(adj)
  if (!identical(length(stems), k))
    stop("clpn_plot_publication: adj 与 stems 长度不一致", call. = FALSE)

  if (!exists("clpn_node_display", mode = "function")) {
    dbp <- file.path(root %||% getwd(), "R/clpn_node_label_db.R")
    if (file.exists(dbp)) source(dbp, local = FALSE)
  }

  full <- if (exists("clpn_node_display", mode = "function")) {
    clpn_node_display(stems, root = root, fallback = TRUE)
  } else {
    rownames(adj)
  }
  if (!is.null(disease_display) && nzchar(as.character(disease_display)[1L])) {
    full[stems %in% c("Disease01", "Disease_Group", "Sarcopenia", "sarcop")] <-
      as.character(disease_display)[1L]
  }
  short <- clpn_plot_short_labels(stems, root = root)
  node_names <- full

  # beta → OR（与 Step07: W <- exp(graph) 一致）
  W <- exp(as.matrix(adj))
  storage.mode(W) <- "double"
  if (isTRUE(drop_self_loops %||% TRUE)) diag(W) <- 0

  band <- as.numeric(or_band)
  if (length(band) < 2L || any(!is.finite(band))) band <- c(0.95, 1.05)
  lo_b <- min(band); hi_b <- max(band)
  W[W > lo_b & W < hi_b] <- 0

  # 颜色按 OR 方向；作图用 log(OR) 以便 fade/线宽按效应强弱出深浅
  edge_colors <- ifelse(W > 1, "#e87d72", "#6095ce")
  edge_colors[W == 0] <- NA
  W_plot <- log(pmax(W, 1e-12))
  W_plot[W == 0] <- 0
  mx_abs <- max(abs(W_plot), na.rm = TRUE)
  if (!is.finite(mx_abs) || mx_abs <= 0) mx_abs <- 1
  # 深浅分层，但弱边不能太淡（否则“啥都看不出来”）
  # alpha：弱边 ≈0.55，强边 ≈0.98
  strength <- abs(W_plot) / mx_abs
  alpha_vec <- as.numeric(0.55 + 0.43 * strength)
  w_vec <- as.numeric(W_plot)
  edge_colors <- vapply(seq_along(edge_colors), function(i) {
    col <- edge_colors[[i]]
    if (is.na(col) || !is.finite(w_vec[[i]]) || w_vec[[i]] == 0)
      return(NA_character_)
    grDevices::adjustcolor(col, alpha.f = alpha_vec[[i]])
  }, character(1))
  dim(edge_colors) <- dim(W_plot)

  domains <- vapply(stems, .clpn_stem_domain, character(1))
  group_names <- c(
    "Outcome", "Comorbidity", "ADL", "Mobility", "Sensory", "Biomarker", "Other"
  )
  group_names <- group_names[group_names %in% unique(domains)]
  groups_fac <- factor(domains, levels = group_names)
  color_map <- c(
    Outcome = "#F6B7C6",
    Comorbidity = "#c9d8eb",
    ADL = "#82b181",
    Mobility = "#F0A780",
    Sensory = "#B8A9C9",
    Biomarker = "#FFD700",
    Other = "#E6C38C"
  )
  color_vec <- unname(color_map[group_names])

  layout_used <- if (identical(layout, "circle")) "spring" else (layout %||% "spring")
  if (!is.character(layout_used)) layout_used <- "spring"
  rad <- as.numeric(repulse_rad)[1L]
  if (!is.finite(rad) || rad <= 0) rad <- 80

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(outfile, width = 18, height = 14)
  set.seed(6008L)
  qgraph::qgraph(
    W_plot,
    directed = TRUE,
    layout = layout_used,
    layout.par = list(repulse.rad = rad),
    title = title,
    title.cex = 1.2,
    nodeNames = node_names,
    labels = short,
    label.cex = 0.6,
    groups = groups_fac,
    color = color_vec,
    edge.color = edge_colors,
    legend = TRUE,
    legend.cex = 0.55,
    vsize = 4,
    esize = 6,
    asize = 1.7,
    curveAll = FALSE,
    # 不用 qgraph 再淡一层（已用 alpha）；避免叠淡后看不见
    fade = FALSE,
    maximum = mx_abs,
    minimum = 0,
    cut = 0,
    bg = "white"
  )
  grDevices::dev.off()
  invisible(outfile)
}
