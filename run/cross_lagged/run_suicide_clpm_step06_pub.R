#!/usr/bin/env Rscript
# step06 — remaining outpatient publication slots after the nine paths:
# Figure 1 attrition, Table S2 Spearman correlations, Figure 2 cross-lagged diagram,
# then summary_results (Fig1, Table1, Table2, Fig2, S1, S2).
# Ward exploratory is not rebuilt here.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step06_pub.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  engine_root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  engine_root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(engine_root)

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "R/attrition_log.R"), local = FALSE)
source(file.path(engine_root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)

.cfg_env <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_suicide_clpm.R"), envir = .cfg_env)
config <- .cfg_env$config
if (exists("pipeline_apply_pub_digits", mode = "function")) pipeline_apply_pub_digits(config)
options(pipeline.database_name = "Outpatient")

nodes <- c(
  "HAMD-17 total, Index", "HAMA-14 total, Index", "C-SSRS ideation, Index",
  "HAMD-17 total, 1st", "HAMA-14 total, 1st", "C-SSRS ideation, 1st"
)
short <- c(
  "HAMD-17 total, Index" = "HAMD-17",
  "HAMA-14 total, Index" = "HAMA-14",
  "C-SSRS ideation, Index" = "C-SSRS",
  "HAMD-17 total, 1st" = "HAMD-17",
  "HAMA-14 total, 1st" = "HAMA-14",
  "C-SSRS ideation, 1st" = "C-SSRS"
)

step_dir <- file.path(study_root, "step06_pub")
tab_dir <- file.path(step_dir, "Tables")
fig_dir <- file.path(step_dir, "Figures")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(study_root, "step02_imputation/dabiao.RData"), envir = e)
df <- e$dabiao
miss <- setdiff(nodes, names(df))
if (length(miss)) stop("Missing nodes: ", paste(miss, collapse = ", "), call. = FALSE)
.as01 <- function(x) {
  if (is.factor(x) || is.character(x)) {
    as.integer(trimws(as.character(x)) %in% c("1", "Yes", "yes", "YES", "A", "是"))
  } else as.integer(x)
}
mat <- df[, nodes, drop = FALSE]
mat[["C-SSRS ideation, Index"]] <- .as01(mat[["C-SSRS ideation, Index"]])
mat[["C-SSRS ideation, 1st"]] <- .as01(mat[["C-SSRS ideation, 1st"]])
mat <- as.data.frame(lapply(mat, as.numeric))
stopifnot(nrow(mat) == 643L, all(stats::complete.cases(mat)))

# --- Table S2 Spearman ---
k <- length(nodes)
r_mat <- matrix(NA_real_, k, k)
p_mat <- matrix(NA_real_, k, k)
for (i in seq_len(k)) {
  for (j in seq_len(k)) {
    if (i == j) {
      r_mat[i, j] <- 1
      p_mat[i, j] <- NA_real_
    } else if (j < i) {
      ct <- stats::cor.test(mat[[i]], mat[[j]], method = "spearman", exact = FALSE)
      r_mat[i, j] <- unname(ct$estimate)
      p_mat[i, j] <- ct$p.value
      r_mat[j, i] <- r_mat[i, j]
      p_mat[j, i] <- p_mat[i, j]
    }
  }
}
show <- data.frame(Variable = nodes, stringsAsFactors = FALSE)
for (j in seq_len(k)) {
  cells <- character(k)
  for (i in seq_len(k)) {
    cells[i] <- if (i == j) {
      "1"
    } else if (i > j) {
      pub_format_est(r_mat[i, j])
    } else {
      pub_format_p_cell(p_mat[i, j])
    }
  }
  show[[nodes[j]]] <- cells
}
utils::write.csv(show, file.path(step_dir, "spearman_matrix.csv"), row.names = FALSE, fileEncoding = "UTF-8")
.table_queue_env$items <- list()
export_sci_table(
  show,
  file.path(tab_dir, "Table S2. Spearman correlations among the six nodes.xlsx"),
  title = "Table S2. Spearman correlations among the six nodes",
  table_footnotes = c(
    "Outpatient N = 643. Lower triangle: Spearman r. Upper triangle: P. Diagonal: 1.",
    "C-SSRS ideation is item 2 (active suicidal thoughts), coded No = 0 and Yes = 1.",
    "HAMD-17 and HAMA-14 are wave totals. Nodes were not imputed."
  )
)
suicide_clpm_flush_sci_tables()

# --- Figure 1 ---
attr <- utils::read.csv(file.path(study_root, "step01_data_clean/attrition.csv"),
                        stringsAsFactors = FALSE, fileEncoding = "UTF-8")
attr <- attr[attr$step != "six_nodes_complete", , drop = FALSE]
step_lab <- c(
  has_ID = "Records with an identifier",
  group_门诊入组 = "Outpatient enrollment",
  require_HAMD_Index = "HAMD-17 total at Index",
  require_HAMD_1st = "HAMD-17 total at 1st",
  require_HAMA_Index = "HAMA-14 total at Index",
  require_HAMA_1st = "HAMA-14 total at 1st",
  require_CSSRS_Index = "C-SSRS ideation at Index",
  require_CSSRS_1st = "C-SSRS ideation at 1st"
)
ex_lab <- c(
  has_ID = "",
  group_门诊入组 = "Not outpatient enrollment",
  require_HAMD_Index = "Missing HAMD-17 total at Index",
  require_HAMD_1st = "Missing HAMD-17 total at 1st",
  require_HAMA_Index = "Missing HAMA-14 total at Index",
  require_HAMA_1st = "Missing HAMA-14 total at 1st",
  require_CSSRS_Index = "Missing C-SSRS ideation at Index",
  require_CSSRS_1st = "Missing C-SSRS ideation at 1st"
)
rows <- data.frame(
  step = unname(step_lab[attr$step]),
  n = as.integer(attr$n_remain),
  exclude_label = unname(ex_lab[attr$step]),
  step_id = attr$step,
  stringsAsFactors = FALSE
)
if (any(!nzchar(rows$step) | is.na(rows$step))) stop("Unmapped attrition step", call. = FALSE)
fig1 <- file.path(fig_dir, "Figure 1. Outpatient inclusion and exclusion flowchart.pdf")
ok1 <- attrition_draw_pdf(
  rows, "Outpatient inclusion and exclusion", fig1,
  footnote = "Analytic cohort: six nodes complete, N = 643. C-SSRS ideation is item 2.",
  fork = list(left_n = NA_real_, right_n = NA_real_)
)
if (!isTRUE(ok1) || !file.exists(fig1)) stop("Figure 1 was not written", call. = FALSE)
flow <- data.frame(
  database = "Outpatient",
  step = rows$step,
  n = rows$n,
  stringsAsFactors = FALSE
)
utils::write.csv(flow, file.path(tab_dir, "Flowchart_attrition_Outpatient.csv"),
                 row.names = FALSE, fileEncoding = "UTF-8")

# --- Figure 2 ---
paths <- utils::read.csv(file.path(study_root, "step05_clpm_paths/paths_results.csv"),
                         stringsAsFactors = FALSE, fileEncoding = "UTF-8")
stopifnot(nrow(paths) == 9L)
paths$sig <- is.finite(paths$p) & paths$p < 0.05
paths$from_short <- unname(short[paths$predictor])
paths$to_short <- unname(short[paths$outcome])
paths$wave_from <- ifelse(grepl("Index$", paths$predictor), "Index", "1st")
paths$wave_to <- ifelse(grepl("1st$", paths$outcome), "1st", "Index")

pos <- data.frame(
  node = c("HAMD-17", "HAMA-14", "C-SSRS"),
  y = c(3, 2, 1),
  stringsAsFactors = FALSE
)
x_of <- c(Index = 1, "1st" = 3)
edges <- paths
edges$x <- unname(x_of[edges$wave_from])
edges$xend <- unname(x_of[edges$wave_to])
edges$y <- pos$y[match(edges$from_short, pos$node)]
edges$yend <- pos$y[match(edges$to_short, pos$node)]
edges$curvature <- ifelse(edges$y == edges$yend, 0.18, ifelse(edges$y > edges$yend, 0.22, -0.22))
# Pull cross-lag curves apart when two edges share the same endpoints in reverse.
edges$curvature <- ifelse(grepl("to HAMD-17$", edges$path) & edges$role == "Cross-lag" & edges$from_short == "HAMA-14", 0.35, edges$curvature)
edges$curvature <- ifelse(grepl("to HAMA-14$", edges$path) & edges$role == "Cross-lag" & edges$from_short == "HAMD-17", -0.35, edges$curvature)
.star <- function(p) {
  if (!is.finite(p) || p >= 0.05) return("")
  if (p < 0.001) return("***")
  if (p < 0.01) return("**")
  "*"
}
edges$kind <- ifelse(edges$role == "Autoregression", "AR", "CL")
var_col <- c("HAMD-17" = "#C0392B", "HAMA-14" = "#1A5276", "C-SSRS" = "#1E8449")
var_fill <- c("HAMD-17" = "#FADBD8", "HAMA-14" = "#D6EAF8", "C-SSRS" = "#D5F5E3")
edges$draw_col <- unname(var_col[edges$from_short])
edges$draw_lty <- ifelse(edges$sig, "solid", "dashed")
edges$draw_lw <- ifelse(edges$sig, 0.75, 0.55)
edges$on_arrow <- paste0(
  ifelse(edges$effect == "OR", "OR = ", "\u03b2 = "),
  formatC(edges$estimate, format = "f", digits = 3),
  vapply(edges$p, .star, character(1))
)
# One self-loop per autoregression, on the Index box only. 1st has no separate autoregression.
xl <- 2.85
xr <- 6.45
hw <- 0.48
ys <- c("HAMD-17" = 3, "HAMA-14" = 2, "C-SSRS" = 1)
edges$x <- xl + hw
edges$xend <- xr - hw
edges$y <- unname(ys[edges$from_short])
edges$yend <- unname(ys[edges$to_short])
edges$curvature <- 0
for (i in seq_len(nrow(edges))) {
  if (edges$kind[i] == "AR") {
    edges$x[i] <- xl - 0.38
    edges$xend[i] <- xl - 0.38
    edges$y[i] <- edges$y[i] + 0.11
    edges$yend[i] <- edges$yend[i] - 0.11
    edges$curvature[i] <- 1.15
  } else if (edges$from_short[i] == "HAMD-17" && edges$to_short[i] == "HAMA-14") {
    edges$y[i] <- edges$y[i] - 0.14
    edges$yend[i] <- edges$yend[i] + 0.14
    edges$curvature[i] <- -0.18
  } else if (edges$from_short[i] == "HAMA-14" && edges$to_short[i] == "HAMD-17") {
    edges$y[i] <- edges$y[i] + 0.14
    edges$yend[i] <- edges$yend[i] - 0.14
    edges$curvature[i] <- 0.22
  } else if (edges$from_short[i] == "HAMD-17" && edges$to_short[i] == "C-SSRS") {
    edges$y[i] <- edges$y[i] - 0.14
    edges$yend[i] <- edges$yend[i] + 0.14
    edges$curvature[i] <- -0.10
  } else if (edges$from_short[i] == "C-SSRS" && edges$to_short[i] == "HAMD-17") {
    edges$y[i] <- edges$y[i] + 0.14
    edges$yend[i] <- edges$yend[i] - 0.14
    edges$curvature[i] <- 0.16
  } else if (edges$from_short[i] == "HAMA-14" && edges$to_short[i] == "C-SSRS") {
    edges$y[i] <- edges$y[i] - 0.14
    edges$yend[i] <- edges$yend[i] + 0.14
    edges$curvature[i] <- -0.20
  } else if (edges$from_short[i] == "C-SSRS" && edges$to_short[i] == "HAMA-14") {
    edges$y[i] <- edges$y[i] + 0.14
    edges$yend[i] <- edges$yend[i] - 0.14
    edges$curvature[i] <- 0.24
  }
}
lab_xy <- data.frame(
  path = c(
    "HAMD-17 autoregression", "HAMA-14 autoregression", "C-SSRS ideation autoregression",
    "HAMD-17 to HAMA-14", "HAMA-14 to HAMD-17",
    "HAMD-17 to C-SSRS ideation", "HAMA-14 to C-SSRS ideation",
    "C-SSRS ideation to HAMD-17", "C-SSRS ideation to HAMA-14"
  ),
  lx = c(1.62, 1.62, 1.48, 4.35, 5.15, 4.05, 4.20, 4.70, 4.85),
  ly = c(3.00, 2.00, 1.00, 2.74, 2.72, 2.22, 1.80, 1.68, 1.22),
  stringsAsFactors = FALSE
)
edges <- merge(edges, lab_xy, by = "path", all.x = TRUE, sort = FALSE)
edges_lab <- edges

node_df <- rbind(
  data.frame(node = c("HAMD-17 total", "HAMA-14 total", "C-SSRS ideation"),
             x = xl, y = unname(ys),
             col = unname(var_col), fill = unname(var_fill), stringsAsFactors = FALSE),
  data.frame(node = c("HAMD-17 total", "HAMA-14 total", "C-SSRS ideation"),
             x = xr, y = unname(ys),
             col = unname(var_col), fill = unname(var_fill), stringsAsFactors = FALSE)
)
p2 <- ggplot2::ggplot()
ord <- order(edges$kind == "AR", edges$sig)
for (i in ord) {
  p2 <- p2 + ggplot2::geom_curve(
    data = edges[i, , drop = FALSE],
    ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
    curvature = edges$curvature[i],
    colour = edges$draw_col[i],
    linetype = edges$draw_lty[i],
    linewidth = edges$draw_lw[i],
    arrow = ggplot2::arrow(
      length = grid::unit(if (edges$kind[i] == "AR") 0.09 else 0.12, "inches"),
      type = "closed"
    ),
    lineend = "round"
  )
}
p2 <- p2 +
  ggplot2::geom_label(
    data = node_df,
    ggplot2::aes(x = x, y = y, label = node, colour = col, fill = fill),
    size = 3.5, linewidth = 0.45,
    label.r = grid::unit(0.45, "lines"),
    label.padding = ggplot2::unit(0.35, "lines")
  ) +
  ggplot2::geom_label(
    data = edges_lab,
    ggplot2::aes(x = lx, y = ly, label = on_arrow, colour = draw_col),
    size = 3.05, linewidth = 0, fill = "white",
    fontface = "bold", label.padding = ggplot2::unit(0.04, "lines"),
    label.r = grid::unit(0, "lines")
  ) +
  ggplot2::scale_colour_identity() +
  ggplot2::scale_fill_identity() +
  ggplot2::annotate("text", x = xl, y = 3.55, label = "Index (T0)", fontface = "bold", size = 4.3, colour = "black") +
  ggplot2::annotate("text", x = xr, y = 3.55, label = "1st about 1 month (T1)", fontface = "bold", size = 4.3, colour = "black") +
  ggplot2::annotate(
    "text", x = 0.2, y = 0.28, hjust = 0, size = 2.6, colour = "grey20",
    label = paste0(
      "* P < 0.05,  *** P < 0.001.  Dashed arrows are P \u2265 0.05.  Self-loops are autoregression at Index.\n",
      "Colour follows the Index predictor: HAMD-17 red, HAMA-14 blue, C-SSRS green.\n",
      "All estimates are adjusted for the 12 baseline covariates. N = 643."
    )
  ) +
  ggplot2::labs(title = "Cross-lagged panel analysis for Outpatients (N = 643)") +
  ggplot2::coord_cartesian(xlim = c(0.05, 7.6), ylim = c(0.08, 3.85)) +
  ggplot2::theme_void(base_size = 11) +
  ggplot2::theme(
    plot.margin = ggplot2::margin(8, 10, 8, 10),
    plot.title = ggplot2::element_text(face = "bold", hjust = 0.5, size = 13, colour = "black")
  )
fig2 <- file.path(fig_dir, "Figure 2. Cross-lagged associations from Index to 1st.pdf")
grDevices::cairo_pdf(fig2, width = 10.2, height = 6.4, family = "sans")
print(p2)
grDevices::dev.off()
if (!file.exists(fig2) || file.info(fig2)$size < 1000) stop("Figure 2 was not written", call. = FALSE)
utils::write.csv(edges[, c("path", "predictor", "outcome", "effect", "estimate", "p", "on_arrow")],
                 file.path(step_dir, "figure2_edges.csv"), row.names = FALSE, fileEncoding = "UTF-8")

ann <- vapply(seq_len(nrow(edges)), function(i) {
  sprintf(
    "- %s: %s = %s (95%% CI %s, %s), P %s%s",
    edges$path[i],
    if (edges$effect[i] == "OR") "OR" else "standardized beta",
    pub_format_est(edges$estimate[i]),
    pub_format_est(edges$ci_low[i]),
    pub_format_est(edges$ci_high[i]),
    pub_format_p_cell(edges$p[i]),
    if (isTRUE(edges$sig[i])) "" else "；虚线，系数仍标在箭头旁"
  )
}, character(1))

# --- summary_results ---
sum_root <- file.path(study_root, "summary_results")
sum_tab <- file.path(sum_root, "Tables")
sum_fig <- file.path(sum_root, "Figures")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
file.copy(fig1, file.path(sum_fig, basename(fig1)), overwrite = TRUE)
file.copy(fig2, file.path(sum_fig, basename(fig2)), overwrite = TRUE)
file.copy(file.path(tab_dir, "Flowchart_attrition_Outpatient.csv"),
          file.path(sum_tab, "Flowchart_attrition_Outpatient.csv"), overwrite = TRUE)

copy_one <- function(src, dest_name) {
  if (!file.exists(src)) stop("Missing source table: ", src, call. = FALSE)
  ok <- file.copy(src, file.path(sum_tab, dest_name), overwrite = TRUE)
  if (!isTRUE(ok)) stop("Copy failed: ", src, call. = FALSE)
}
copy_one(
  file.path(study_root, "step03_baseline_binary/Tables/Table 1-Outpatient. Baseline characteristics by Index C-SSRS ideation item2.xlsx"),
  "Table 1-Outpatient. Baseline characteristics by Index C-SSRS ideation item2.xlsx"
)
copy_one(
  file.path(study_root, "step05_clpm_paths/Tables/Table 2-Outpatient. Cross-lagged paths from Index to 1st.xlsx"),
  "Table 2-Outpatient. Cross-lagged paths from Index to 1st.xlsx"
)
s1_src <- file.path(study_root, "step02_imputation/Tables/Table S1-Outpatient. Baseline characteristics before and after imputation.updated.xlsx")
if (!file.exists(s1_src)) {
  s1_src <- file.path(study_root, "step02_imputation/Tables/Table S1-Outpatient. Baseline characteristics before and after imputation.xlsx")
}
copy_one(s1_src, "Table S1-Outpatient. Baseline characteristics before and after imputation.xlsx")
s2_files <- list.files(tab_dir, pattern = "^Table S2.*\\.xlsx$", full.names = TRUE)
if (!length(s2_files)) stop("Missing Table S2 xlsx", call. = FALSE)
copy_one(s2_files[1L], basename(s2_files[1L]))

meta <- list(
  exposure = "HAMD-17 total, HAMA-14 total, and C-SSRS ideation at Index",
  outcome = "the same measures at 1st, about 1 month after discharge",
  outcome_column = "C-SSRS ideation, 1st",
  grouping = "two-wave cross-lag; continuous outcomes use standardized beta, C-SSRS ideation at 1st uses OR",
  n_by_db = c(Outpatient = 643L),
  n_total = 643L,
  combined = FALSE,
  databases = "Outpatient",
  cross_lag_lines = ann,
  tables_dir = sum_tab
)
export_pub_figures(sum_fig, meta = meta, config = config, purge = TRUE)
st <- pub_figure_formats_status(sum_fig)
if (length(st$bad_dpi)) stop("DPI below 600: ", paste(st$bad_dpi, collapse = ", "), call. = FALSE)

writeLines(c(
  "Outpatient main analysis. C-SSRS ideation is item 2. Analytic N = 643.",
  "Figure 1: inclusion flowchart.",
  "Table 1: baseline characteristics by C-SSRS ideation at Index.",
  "Table 2: nine pre-registered Index to 1st paths, adjusted for the 12 Model2 covariates.",
  "Figure 2: cross-lagged diagram. Colour follows the Index predictor (HAMD-17 red, HAMA-14 blue, C-SSRS green). Autoregression is a self-loop on the Index box only. Every coefficient sits on its arrow. Dashed arrows are P >= 0.05.",
  "Table S1: covariates before and after multiple imputation. The six nodes were not imputed.",
  "Table S2: Spearman correlations among the six nodes.",
  "Ward exploratory cohort was not rebuilt on this item-2 pipeline and is not in this folder."
), file.path(sum_root, "README.txt"))
message("[step06] DONE ", sum_root)
