#!/usr/bin/env Rscript
# =============================================================================
# Task 7 — 自杀门诊 CLPM 发表槽位：Fig1 / Table1 / S1 / S2 / Fig2 / README
#
# 用法:
#   Rscript run/cross_lagged/run_suicide_clpm_pub.R
#   CROSS_LAGGED_STUDY_ROOT=/path Rscript run/cross_lagged/run_suicide_clpm_pub.R
#
# 产出（{STUDY}/summary_result/）:
#   figure/Fig1_attrition.{pdf,png,csv}
#   figure/Fig2_CLPM_paths.{pdf,png}
#   figure/pdf|png|tiff|image_information/  (若 PDF 落盘则四目录)
#   table/Table1_baseline.{csv,xlsx}
#   table/TableS1_imputation_note.{csv,xlsx,txt}
#   table/TableS2_node_correlation.{csv,xlsx}
#   README.md
# =============================================================================

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

`%||%` <- function(a, b) if (is.null(a)) b else if (length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) {
  study_root <- file.path(engine_root, ".superpowers/sdd/study_mirror")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

nodes <- c("HAMD_Index", "HAMD_1st", "HAMA_Index", "HAMA_1st", "CSSRS_Index", "CSSRS_1st")
fig_dir <- file.path(study_root, "summary_result/figure")
tab_dir <- file.path(study_root, "summary_result/table")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

message("[Task7] study_root = ", study_root)

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------
.fmt_p <- function(p) {
  p <- as.numeric(p)
  ifelse(is.na(p), NA_character_,
         ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}

.fmt_num <- function(x, d = 2L) {
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_, sprintf(paste0("%.", d, "f"), x))
}

.write_csv_xlsx <- function(df, stem, out_dir = tab_dir) {
  csv_path <- file.path(out_dir, paste0(stem, ".csv"))
  utils::write.csv(df, csv_path, row.names = FALSE, fileEncoding = "UTF-8")
  xlsx_path <- file.path(out_dir, paste0(stem, ".xlsx"))
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(df, xlsx_path, overwrite = TRUE)
  }
  invisible(list(csv = csv_path, xlsx = xlsx_path))
}

.save_ggplot_pdf_png <- function(p, stem, width = 8, height = 6, out_dir = fig_dir) {
  pdf_path <- file.path(out_dir, paste0(stem, ".pdf"))
  png_path <- file.path(out_dir, paste0(stem, ".png"))
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggsave(pdf_path, p, width = width, height = height, device = "pdf")
    ggplot2::ggsave(png_path, p, width = width, height = height, dpi = 300, device = "png")
  } else {
    grDevices::pdf(pdf_path, width = width, height = height)
    print(p)
    grDevices::dev.off()
    grDevices::png(png_path, width = width * 300, height = height * 300, res = 300)
    print(p)
    grDevices::dev.off()
  }
  invisible(c(pdf = pdf_path, png = png_path))
}

# -----------------------------------------------------------------------------
# load data
# -----------------------------------------------------------------------------
imp_path <- file.path(study_root, "data/harmonized/D04_outpatient_clpm_imputed.RData")
raw_path <- file.path(study_root, "data/harmonized/D04_outpatient_clpm.RData")
data_path <- if (file.exists(imp_path)) imp_path else raw_path
if (!file.exists(data_path)) stop("Missing analysis data under ", dirname(raw_path))
message("[Task7] loading ", data_path)
load(data_path)
if (!exists("dabiao")) stop("Expected object 'dabiao' in ", data_path)
stopifnot(nrow(dabiao) == 649L)
leak_miss <- vapply(nodes, function(nm) sum(is.na(dabiao[[nm]])), integer(1))
if (any(leak_miss > 0L)) {
  stop("Six nodes must be complete; missing counts: ",
       paste(names(leak_miss)[leak_miss > 0], leak_miss[leak_miss > 0], sep = "=", collapse = ", "))
}

m2_path <- file.path(study_root, "covariates/Model2Factors.txt")
Model2Factors <- if (file.exists(m2_path)) {
  x <- trimws(readLines(m2_path, warn = FALSE))
  x[nzchar(x)]
} else {
  character(0)
}

attr_path <- file.path(study_root, "data/harmonized/attrition_outpatient.csv")
if (!file.exists(attr_path)) stop("Missing attrition: ", attr_path)
attr_df <- utils::read.csv(attr_path, stringsAsFactors = FALSE)

paths_csv <- file.path(tab_dir, "Table2_CLPM_paths.csv")
if (!file.exists(paths_csv)) stop("Missing Table2_CLPM_paths.csv — run Task6 first")
paths_tab <- utils::read.csv(paths_csv, stringsAsFactors = FALSE)

# =============================================================================
# Step 1 — Fig1 attrition flowchart (stepwise n + excluded)
# =============================================================================
message("[Task7] Step1 Fig1 attrition")

attr_fig <- attr_df
# ASCII display labels (PDF device may lack CJK glyphs)
.step_lab <- c(
  has_ID = "has_ID (baseline ID)",
  `group_门诊入组` = "outpatient enrollment",
  six_nodes_complete = "six-node complete"
)
attr_fig$step_disp <- ifelse(
  attr_fig$step %in% names(.step_lab),
  unname(.step_lab[attr_fig$step]),
  attr_fig$step
)
attr_fig$label <- sprintf(
  "%s\nn = %s\n(excluded %s)",
  attr_fig$step_disp,
  format(attr_fig$n_remain, big.mark = ","),
  format(attr_fig$n_excluded, big.mark = ",")
)
attr_fig$y <- rev(seq_len(nrow(attr_fig)))

# Persist stepwise table next to figure
utils::write.csv(attr_df, file.path(fig_dir, "Fig1_attrition.csv"), row.names = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  p1 <- ggplot2::ggplot(attr_fig, ggplot2::aes(x = 1, y = y)) +
    ggplot2::geom_tile(
      width = 0.72, height = 0.78,
      fill = "#F7F4EF", colour = "#2F3E46", linewidth = 0.6
    ) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      size = 3.2, lineheight = 0.95, colour = "#1B263B", fontface = "plain"
    ) +
    ggplot2::annotate(
      "segment",
      x = 1, xend = 1,
      y = attr_fig$y[-nrow(attr_fig)] - 0.42,
      yend = attr_fig$y[-1L] + 0.42,
      arrow = ggplot2::arrow(length = grid::unit(0.12, "inches"), type = "closed"),
      colour = "#52796F", linewidth = 0.7
    ) +
    ggplot2::scale_y_continuous(NULL, breaks = NULL) +
    ggplot2::scale_x_continuous(NULL, breaks = NULL, limits = c(0.4, 1.6)) +
    ggplot2::labs(
      title = "Figure 1. Outpatient attrition flowchart",
      subtitle = "Main cohort: outpatient; six-node complete n = 649; nodes not imputed",
      caption = paste(
        "Steps from attrition_outpatient.csv.",
        "Excluded = adjacent step difference (n_excluded column)."
      )
    ) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", hjust = 0, margin = ggplot2::margin(b = 4)),
      plot.subtitle = ggplot2::element_text(hjust = 0, colour = "#4A4A4A", margin = ggplot2::margin(b = 8)),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8, colour = "#666666"),
      plot.margin = ggplot2::margin(12, 16, 12, 16)
    )
  .save_ggplot_pdf_png(p1, "Fig1_attrition", width = 6.5, height = 5.5)
  # Alias for pub_figure_ensure_formats (^Figure*)
  file.copy(
    file.path(fig_dir, "Fig1_attrition.pdf"),
    file.path(fig_dir, "Figure 1. Outpatient attrition flowchart.pdf"),
    overwrite = TRUE
  )
} else {
  # Text fallback PDF
  pdf_path <- file.path(fig_dir, "Fig1_attrition.pdf")
  grDevices::pdf(pdf_path, width = 7, height = 5)
  plot.new()
  title("Figure 1. Outpatient attrition (stepwise)")
  txt <- paste(
    sprintf("%s: n_remain=%s, excluded=%s | %s",
            attr_df$step, attr_df$n_remain, attr_df$n_excluded, attr_df$rule),
    collapse = "\n\n"
  )
  text(0.05, 0.85, txt, adj = c(0, 1), cex = 0.85, family = "mono")
  grDevices::dev.off()
  file.copy(pdf_path, file.path(fig_dir, "Figure 1. Outpatient attrition flowchart.pdf"), overwrite = TRUE)
}

# =============================================================================
# Step 2 — Table1 baseline + TableS1 imputation note
# =============================================================================
message("[Task7] Step2 Table1 + TableS1")

dabiao$CSSRS_Index_f <- factor(
  dabiao$CSSRS_Index,
  levels = c(0, 1),
  labels = c("CSSRS_Index=0 (No)", "CSSRS_Index=1 (Yes)")
)

# Table1 vars: Model2 + age/sex already in; plus Index node summaries for context
t1_cont <- intersect(
  c("age", "year_education", "Weight", "Height", "BMI", "age_onset",
    "Duringcourse", "No._hopitalization", "No._depressive_episode", "No._manic_episode",
    "Age_medication_intake", "CGI_severiry_index",
    "HAMD_Index", "HAMA_Index"),
  names(dabiao)
)
t1_cat <- intersect(
  c("sex", "education", "marriage", "First_episode", "form", "Attack", "DrugNaive",
    "Familyhistory_3", "Familyhistory_4", "Familyhistory_6",
    "MASS_1", "MASS_2", "MASS_7", "medicine", "Moodstaberlizers",
    "antipsychotics", "antidepressants", "BZDs", "ECT", "Smoke_1", "Alcohol_1",
    "CSSRS_1st"),
  names(dabiao)
)
# Prefer Model2 order for covariates that appear in Table1
t1_cont <- unique(c(intersect(Model2Factors, t1_cont), t1_cont))
t1_cat <- unique(c(intersect(Model2Factors, t1_cat), setdiff(t1_cat, "CSSRS_1st"), "CSSRS_1st"))

.describe_cont <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return("NA")
  sprintf("%s (%s)", .fmt_num(mean(x), 2L), .fmt_num(stats::sd(x), 2L))
}

.describe_cat <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(x)] <- "(Missing)"
  tab <- sort(table(x), decreasing = TRUE)
  paste(sprintf("%s: %d (%.1f%%)", names(tab), as.integer(tab), 100 * as.numeric(tab) / sum(tab)),
        collapse = "; ")
}

.strata_levels <- levels(dabiao$CSSRS_Index_f)
.build_t1_row <- function(var, kind) {
  overall <- if (kind == "cont") .describe_cont(dabiao[[var]]) else .describe_cat(dabiao[[var]])
  by_s <- vapply(.strata_levels, function(lv) {
    idx <- dabiao$CSSRS_Index_f == lv
    if (kind == "cont") .describe_cont(dabiao[[var]][idx]) else .describe_cat(dabiao[[var]][idx])
  }, character(1))
  # simple group test
  p <- NA_real_
  if (kind == "cont") {
    g0 <- as.numeric(dabiao[[var]][dabiao$CSSRS_Index == 0])
    g1 <- as.numeric(dabiao[[var]][dabiao$CSSRS_Index == 1])
    if (sum(is.finite(g0)) > 1L && sum(is.finite(g1)) > 1L) {
      p <- tryCatch(stats::wilcox.test(g0, g1)$p.value, error = function(e) NA_real_)
    }
  } else {
    xx <- as.character(dabiao[[var]])
    xx[is.na(xx) | !nzchar(xx)] <- "(Missing)"
    ct <- table(xx, dabiao$CSSRS_Index)
    if (nrow(ct) >= 1L && ncol(ct) == 2L && all(dim(ct) > 0)) {
      p <- tryCatch({
        if (any(ct < 5)) stats::fisher.test(ct, simulate.p.value = TRUE, B = 2000)$p.value
        else stats::chisq.test(ct)$p.value
      }, error = function(e) NA_real_)
    }
  }
  data.frame(
    Variable = var,
    Type = kind,
    Overall = overall,
    `CSSRS_Index=0 (No)` = unname(by_s[1L]),
    `CSSRS_Index=1 (Yes)` = unname(by_s[2L]),
    P = .fmt_p(p),
    N_overall = nrow(dabiao),
    N_CSSRS0 = sum(dabiao$CSSRS_Index == 0, na.rm = TRUE),
    N_CSSRS1 = sum(dabiao$CSSRS_Index == 1, na.rm = TRUE),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

t1_rows <- c(
  lapply(t1_cont, function(v) .build_t1_row(v, "cont")),
  lapply(t1_cat, function(v) .build_t1_row(v, "cat"))
)
table1 <- do.call(rbind, t1_rows)
rownames(table1) <- NULL
# Footer note as last comment row (Methods: nodes not MICE; Table1 is baseline descriptors)
attr(table1, "footnote") <- paste(
  "Stratified by Index C-SSRS item1 (Yes=1/No=0).",
  "Continuous: mean (SD); categorical: n (%).",
  "P: Wilcoxon / chi-square (Fisher if sparse).",
  "Analysis N=649 six-node complete outpatient cases.",
  "Six CLPM nodes were listwise-complete and excluded from MICE (see Table S1)."
)
.write_csv_xlsx(table1, "Table1_baseline")
writeLines(
  attr(table1, "footnote"),
  file.path(tab_dir, "Table1_baseline_footnote.txt")
)

# --- Table S1 imputation note ---
note_path <- file.path(study_root, "covariates/imputation_note.txt")
note_lines <- if (file.exists(note_path)) readLines(note_path, warn = FALSE) else character(0)
parse_kv <- function(key) {
  hit <- grep(paste0("^", key, "="), note_lines, value = TRUE)
  if (!length(hit)) return(NA_character_)
  sub(paste0("^", key, "="), "", hit[1L])
}
nodes_excl <- parse_kv("NODES_EXCLUDED_FROM_MICE")
mice_vars <- parse_kv("MICE_VARS")
dropped <- parse_kv("DROPPED_HI_MISS")
imp_meta <- parse_kv("IMPUTATION")

s1 <- rbind(
  data.frame(
    item = "IMPUTATION",
    detail = as.character(imp_meta %||% "mice_covars_only"),
    stringsAsFactors = FALSE
  ),
  data.frame(
    item = "NODES_EXCLUDED_FROM_MICE",
    detail = as.character(nodes_excl %||% paste(nodes, collapse = ",")),
    stringsAsFactors = FALSE
  ),
  data.frame(
    item = "MICE_VARS",
    detail = as.character(mice_vars %||% NA_character_),
    stringsAsFactors = FALSE
  ),
  data.frame(
    item = "DROPPED_HI_MISS",
    detail = as.character(dropped %||% NA_character_),
    stringsAsFactors = FALSE
  ),
  data.frame(
    item = "COMPLETE_N_OUTPATIENT",
    detail = "649",
    stringsAsFactors = FALSE
  ),
  data.frame(
    item = "NOTE",
    detail = "Six CLPM nodes (HAMD/HAMA/CSSRS Index+1st) never entered MICE; only covariates imputed (m=5, complete_action=1).",
    stringsAsFactors = FALSE
  )
)
.write_csv_xlsx(s1, "TableS1_imputation_note")
file.copy(note_path, file.path(tab_dir, "TableS1_imputation_note.txt"), overwrite = TRUE)

# =============================================================================
# Step 3 — Table S2 node correlations
# =============================================================================
message("[Task7] Step3 TableS2 correlations")

node_mat <- as.data.frame(lapply(dabiao[nodes], function(z) as.numeric(z)))
# Spearman (preferred for mixed continuous/binary) + Pearson companion
sp <- stats::cor(node_mat, use = "pairwise.complete.obs", method = "spearman")
pe <- stats::cor(node_mat, use = "pairwise.complete.obs", method = "pearson")

.cor_long <- function(M, method) {
  rn <- rownames(M)
  out <- list()
  for (i in seq_along(rn)) {
    for (j in seq_along(rn)) {
      if (j < i) next
      out[[length(out) + 1L]] <- data.frame(
        var1 = rn[i], var2 = rn[j],
        r = as.numeric(M[i, j]),
        method = method,
        n = nrow(node_mat),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, out)
}
s2_long <- rbind(.cor_long(sp, "spearman"), .cor_long(pe, "pearson"))
s2_long$r_fmt <- .fmt_num(s2_long$r, 3L)
.write_csv_xlsx(s2_long, "TableS2_node_correlation")

# Wide Spearman matrix for readability
sp_df <- as.data.frame(sp, stringsAsFactors = FALSE)
sp_df <- cbind(Variable = rownames(sp), sp_df, stringsAsFactors = FALSE)
rownames(sp_df) <- NULL
.write_csv_xlsx(sp_df, "TableS2_node_correlation_spearman_wide")

# =============================================================================
# Step 4 — Fig2 path diagram (emphasize significant cross-lags)
# =============================================================================
message("[Task7] Step4 Fig2 path diagram")

# Edge map from Table2
.path_edges <- data.frame(
  path = c(
    "HAMD_AR", "HAMA_AR", "CSSRS_AR",
    "HAMD_to_CSSRS", "HAMA_to_CSSRS",
    "CSSRS_to_HAMD", "CSSRS_to_HAMA",
    "HAMD_to_HAMA", "HAMA_to_HAMD"
  ),
  from = c(
    "HAMD_Index", "HAMA_Index", "CSSRS_Index",
    "HAMD_Index", "HAMA_Index",
    "CSSRS_Index", "CSSRS_Index",
    "HAMD_Index", "HAMA_Index"
  ),
  to = c(
    "HAMD_1st", "HAMA_1st", "CSSRS_1st",
    "CSSRS_1st", "CSSRS_1st",
    "HAMD_1st", "HAMA_1st",
    "HAMA_1st", "HAMD_1st"
  ),
  kind = c(
    "AR", "AR", "AR",
    "CL", "CL", "CL", "CL", "CL", "CL"
  ),
  stringsAsFactors = FALSE
)
edges <- merge(paths_tab[, c("path", "estimate", "ci_low", "ci_high", "p", "effect_type")],
               .path_edges, by = "path", all.y = TRUE)
edges$sig <- !is.na(edges$p) & edges$p < 0.05
edges$label <- ifelse(
  edges$effect_type == "OR",
  sprintf("OR=%.2f%s", edges$estimate, ifelse(edges$sig, "*", "")),
  sprintf("beta=%.2f%s", edges$estimate, ifelse(edges$sig, "*", ""))
)
# Emphasize: all AR + significant cross-lags drawn bold; non-sig CL dashed thin
edges$draw_weight <- ifelse(edges$kind == "AR" | edges$sig, 1.35, 0.55)
edges$draw_lty <- ifelse(edges$kind == "CL" & !edges$sig, "dashed", "solid")
edges$draw_col <- ifelse(
  edges$kind == "AR", "#1B4332",
  ifelse(edges$sig, "#9B2226", "#8899A6")
)

# Node layout: Index left, 1st right
node_pos <- data.frame(
  name = c("HAMD_Index", "HAMA_Index", "CSSRS_Index",
           "HAMD_1st", "HAMA_1st", "CSSRS_1st"),
  x = c(1, 1, 1, 3, 3, 3),
  y = c(3, 2, 1, 3, 2, 1),
  wave = c(rep("Index", 3), rep("1st (~1 mo)", 3)),
  stringsAsFactors = FALSE
)
edges <- merge(edges, node_pos[, c("name", "x", "y")], by.x = "from", by.y = "name")
names(edges)[names(edges) %in% c("x", "y")] <- c("x_from", "y_from")
edges <- merge(edges, node_pos[, c("name", "x", "y")], by.x = "to", by.y = "name")
names(edges)[names(edges) %in% c("x", "y")] <- c("x_to", "y_to")
# Slight curve offsets to reduce overlap
edges$curvature <- ifelse(edges$from == edges$to, 0,
                          ifelse(edges$y_from == edges$y_to, 0.25,
                                 ifelse(edges$y_from > edges$y_to, 0.18, -0.18)))
# Mid labels
edges$x_mid <- (edges$x_from + edges$x_to) / 2
edges$y_mid <- (edges$y_from + edges$y_to) / 2 + edges$curvature * 0.55

# Draw significant CL + all AR with labels; non-sig CL faint no label clutter
edges_lab <- edges[edges$kind == "AR" | edges$sig, , drop = FALSE]

if (requireNamespace("ggplot2", quietly = TRUE)) {
  p2 <- ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = edges,
      ggplot2::aes(
        x = x_from, y = y_from, xend = x_to, yend = y_to,
        colour = draw_col, linewidth = draw_weight, linetype = draw_lty
      ),
      arrow = ggplot2::arrow(length = grid::unit(0.12, "inches"), type = "closed"),
      lineend = "round"
    ) +
    ggplot2::geom_label(
      data = node_pos,
      ggplot2::aes(x = x, y = y, label = name),
      size = 3.1, label.size = 0.4, fill = "#FFFCF7", colour = "#1B263B",
      label.padding = ggplot2::unit(0.18, "lines")
    ) +
    ggplot2::geom_text(
      data = edges_lab,
      ggplot2::aes(x = x_mid, y = y_mid, label = label, colour = draw_col),
      size = 2.7, fontface = "bold", show.legend = FALSE
    ) +
    ggplot2::annotate("text", x = 1, y = 3.55, label = "Index", fontface = "bold", size = 4) +
    ggplot2::annotate("text", x = 3, y = 3.55, label = "1st (~1 month)", fontface = "bold", size = 4) +
    ggplot2::scale_colour_identity() +
    ggplot2::scale_linetype_identity() +
    ggplot2::scale_linewidth_identity() +
    ggplot2::coord_cartesian(xlim = c(0.55, 3.45), ylim = c(0.55, 3.75)) +
    ggplot2::labs(
      title = "Figure 2. Cross-lagged path diagram (outpatient CLPM)",
      subtitle = "Bold = autoregressive or significant cross-lag (p<0.05); dashed grey = non-significant cross-lag",
      caption = paste(
        "N=649; Model2 covariates controlled.",
        "Continuous outcomes: standardized beta; CSSRS_1st: OR (item1).",
        "Significant CL: CSSRS->HAMD, CSSRS->HAMA, HAMA->HAMD."
      )
    ) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", hjust = 0),
      plot.subtitle = ggplot2::element_text(hjust = 0, colour = "#4A4A4A", size = 9),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8, colour = "#666666"),
      plot.margin = ggplot2::margin(10, 14, 10, 14)
    )
  .save_ggplot_pdf_png(p2, "Fig2_CLPM_paths", width = 8.5, height = 6.2)
  file.copy(
    file.path(fig_dir, "Fig2_CLPM_paths.pdf"),
    file.path(fig_dir, "Figure 2. CLPM path diagram.pdf"),
    overwrite = TRUE
  )
} else {
  warning("ggplot2 unavailable; Fig2 skipped")
}

# Edge export for reproducibility
utils::write.csv(edges[, c("path", "from", "to", "kind", "estimate", "effect_type", "p", "sig", "label")],
                 file.path(fig_dir, "Fig2_CLPM_paths_edges.csv"), row.names = FALSE)

# =============================================================================
# Step 5 — pub_figure_ensure_formats (四目录)
# =============================================================================
message("[Task7] Step5 pub_figure_ensure_formats")
pub_src <- file.path(engine_root, "R/pub_figure_export.R")
if (file.exists(pub_src)) {
  sys.source(pub_src, envir = environment())
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    ens <- tryCatch(
      pub_figure_ensure_formats(
        fig_dir,
        meta = list(
          study = "Suicide_CSSRS_CLPM",
          cohort = "outpatient",
          n = 649L,
          exposure = "HAMD/HAMA/CSSRS Index\to1st CLPM",
          outcome = "cross-lagged paths",
          grouping = "binary (CSSRS item1)",
          database = "outpatient single-center"
        ),
        config = list(pub_figure = list(enable = TRUE)),
        purge = TRUE
      ),
      error = function(e) {
        message("[Task7] pub_figure_ensure_formats error: ", e$message)
        list(ok = FALSE)
      }
    )
    message("[Task7] pub_figure_ensure_formats ok=", isTRUE(ens$ok))
  }
} else {
  message("[Task7] R/pub_figure_export.R not found; skip four-format export")
}

# =============================================================================
# README
# =============================================================================
readme <- c(
  "# Suicide CSSRS \u00d7 HAMA/HAMD CLPM — publication slot summary",
  "",
  "## Analysis scope",
  "",
  "- **Main cohort**: outpatient enrollment only (`患者类别 = 门诊入组`).",
  "- **Ward**: Exploratory only (Task 8); not mixed into main tables/figures.",
  "- **C-SSRS node**: **item1** ideation only (Yes=1 / No=0); items 2–5 and behavior not used.",
  "- **Six-node complete-case**: HAMD/HAMA/CSSRS at Index and 1st — any missing deleted.",
  "- **Analytic N**: **649** (outpatient six-node complete).",
  "- **Nodes not in MICE**: all six nodes excluded from imputation; covariates only (see Table S1).",
  "",
  "## Wave definition",
  "",
  "- Index: pre-discharge (~3 days).",
  "- 1st: post-discharge (~1 month).",
  "- Baseline scales are not CLPM nodes.",
  "",
  "## Publication slots (this Task 7)",
  "",
  "| Slot | File |",
  "| ---- | ---- |",
  "| Fig1 | `figure/Fig1_attrition.*` |",
  "| Table1 | `table/Table1_baseline.*` (stratified by CSSRS_Index) |",
  "| Table S1 | `table/TableS1_imputation_note.*` |",
  "| Table S2 | `table/TableS2_node_correlation.*` |",
  "| Fig2 | `figure/Fig2_CLPM_paths.*` (AR + significant cross-lags bold) |",
  "| Table2 | `table/Table2_CLPM_paths.*` (Task 6) |",
  "",
  "## Not done (by design)",
  "",
  "- Tri-database Pooled / Country frailty batch",
  "- FI quantile logistic gate / community S9–S17.1",
  "- CLPN 1000-bootstrap default",
  "",
  "## Reproduce",
  "",
  "```bash",
  "CROSS_LAGGED_STUDY_ROOT=<study_root> Rscript run/cross_lagged/run_suicide_clpm_pub.R",
  "```",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
)
readme_path <- file.path(study_root, "summary_result/README.md")
writeLines(readme, readme_path)
message("[Task7] wrote ", readme_path)

# =============================================================================
# Sync UNC
# =============================================================================
unc_candidates <- c(
  Sys.getenv("CROSS_LAGGED_SYNC_ROOT", unset = ""),
  "/mnt/g/02block_result/43_Suicide/cross-laged_40595747",
  "/mnt/e/02block_result/43_Suicide/cross-laged_40595747"
)
unc_root <- ""
for (p in unc_candidates) {
  if (nzchar(p) && dir.exists(p)) {
    unc_root <- p
    break
  }
}
if (nzchar(unc_root)) {
  for (sub in c("summary_result/figure", "summary_result/table")) {
    src <- file.path(study_root, sub)
    dst <- file.path(unc_root, sub)
    if (!dir.exists(src)) next
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    # recursive copy of files
    files <- list.files(src, recursive = TRUE, full.names = TRUE)
    files <- files[!file.info(files)$isdir]
    for (fp in files) {
      rel <- substring(fp, nchar(src) + 2L)
      dest_fp <- file.path(dst, rel)
      dir.create(dirname(dest_fp), recursive = TRUE, showWarnings = FALSE)
      file.copy(fp, dest_fp, overwrite = TRUE)
    }
  }
  file.copy(readme_path, file.path(unc_root, "summary_result/README.md"), overwrite = TRUE)
  message("[Task7] synced summary_result → ", file.path(unc_root, "summary_result"))
} else {
  message("[Task7] UNC study root not found; skip sync")
}

message("[Task7] DONE")
invisible(TRUE)
