###############################################################################
#  clpn_network_plot.R — 出版 Fig4 CLPN（短码节点 + 图例真名）
#  样式对齐髋部 frailty-item 网 / 参考 DN1–DN8+TyG 网。
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

#' 出版 CLPN 图：节点短码，右侧图例为「短码: 真名」（不重复短码）
#' @param layout NULL=小网 circle / 大网 spring；可显式传 "spring" 或 "circle"
#' @param drop_self_loops NULL=小网保留自环 / 大网去自环；TRUE 强制去自环
#' @param fade_weak_edges NULL=小网不淡化 / 大网去掉最弱 15%% 边；TRUE 强制淡化
clpn_plot_publication <- function(adj, stems, outfile, title = "",
                                  disease_display = NULL, root = NULL,
                                  layout = NULL,
                                  drop_self_loops = NULL,
                                  fade_weak_edges = NULL) {
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
  groups_lab <- if (exists("clpn_node_group", mode = "function")) {
    clpn_node_group(stems, root = root)
  } else {
    rep("Other", k)
  }
  # qgraph 图例会拼成「labels: nodeNames」，此处 nodeNames 只放真名
  node_names <- full

  glev <- c(
    "Outcome", "Circadian", "Depression", "Mood", "Index",
    "Comorbidity", "ADL", "IADL", "Mobility", "Sensory", "Lipid", "Other"
  )
  glev <- glev[glev %in% unique(groups_lab)]
  groups_fac <- factor(groups_lab, levels = glev)
  # 自杀 CLPM 三组必须分色：结局粉 / 抑郁蓝 / 焦虑(心情)绿（对齐参考图 DN/中介/指标分色）
  pal_map <- c(
    Outcome = "#F6B7C6",
    Circadian = "#F6B7C6",
    Depression = "#A8C5E2",
    Mood = "#82B181",
    Index = "#F0A780",
    Comorbidity = "#B8A9C9",
    ADL = "#E6C38C",
    IADL = "#9DD6C5",
    Mobility = "#F0A780",
    Sensory = "#E6C38C",
    Lipid = "#9DD6C5",
    Other = "#CCCCCC"
  )
  color_vec <- unname(pal_map[glev])

  W <- as.matrix(adj)
  storage.mode(W) <- "double"
  small <- k <= 12L
  use_large_style <- identical(layout, "spring") ||
    (is.null(layout) && !isTRUE(small))
  drop_diag <- isTRUE(drop_self_loops) ||
    (is.null(drop_self_loops) && use_large_style)
  fade_edges <- isTRUE(fade_weak_edges) ||
    (is.null(fade_weak_edges) && use_large_style)
  layout_used <- if (!is.null(layout)) {
    layout
  } else if (isTRUE(small)) {
    "circle"
  } else {
    "spring"
  }
  if (drop_diag) diag(W) <- 0
  nz <- W[W != 0]
  if (isTRUE(fade_edges) && length(nz)) {
    thr <- stats::quantile(abs(nz), 0.15, na.rm = TRUE)
    if (is.finite(thr) && thr > 0) W[abs(W) < thr] <- 0
  }
  edge_col <- ifelse(W > 0, "#5B9BD5", ifelse(W < 0, "#E07A72", NA_character_))
  mx <- max(abs(W), na.rm = TRUE)
  if (!is.finite(mx) || mx <= 0) mx <- 1
  vsize <- rep(if (isTRUE(use_large_style)) 5.5 else 7.8, k)
  if (any(groups_lab == "Index")) vsize[groups_lab == "Index"] <- vsize[1] * 1.2

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(outfile, width = 11, height = 9)
  tryCatch({
    qgraph::qgraph(
      W,
      directed = TRUE,
      layout = layout_used,
      labels = short,
      nodeNames = node_names,
      groups = groups_fac,
      color = setNames(color_vec, glev),
      edge.color = edge_col,
      edge.labels = FALSE,
      legend = TRUE,
      legend.cex = 0.42,
      vsize = vsize,
      esize = if (isTRUE(use_large_style)) 4 else 10,
      asize = if (isTRUE(use_large_style)) 1.6 else 2.6,
      curveAll = !isTRUE(use_large_style),
      curve = if (isTRUE(use_large_style)) 0 else 0.18,
      fade = isTRUE(fade_edges),
      maximum = mx,
      minimum = 0,
      cut = 0,
      label.cex = if (isTRUE(use_large_style)) 0.85 else 1.0,
      title = title,
      title.cex = 1.15,
      layout.par = if (identical(layout_used, "spring")) list(repulse.rad = 100) else list()
    )
  }, error = function(e) {
    qgraph::qgraph(W, labels = short, layout = layout_used, directed = TRUE, title = title)
  })
  grDevices::dev.off()
  invisible(outfile)
}
