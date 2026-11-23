#!/usr/bin/env Rscript
# Consolidate S tables (17 -> 7) and beautify S figures (4 -> 3).
# NEVER touch Table 1-6 / Figure 1-4.

suppressPackageStartupMessages({
  library(openxlsx)
  library(ggplot2)
  library(grid)
})

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}

sr <- file.path(proj, "summary_results")
sr_tab <- file.path(sr, "Tables")
sr_pdf <- file.path(sr, "Figures", "pdf")
sr_md <- file.path(sr, "Figures", "image_information")

.protect_tab <- list.files(sr_tab, pattern = "^Table [1-6]\\b")
.protect_fig <- list.files(sr_pdf, pattern = "^Figure [1-4]\\b")
message("protect main tabs: ", paste(.protect_tab, collapse = "; "))
message("protect main figs: ", paste(.protect_fig, collapse = "; "))

.ff <- tryCatch(resolve_plot_font_family("Times New Roman"), error = function(e) "serif")
message("plot font: ", .ff)

.read_s <- function(pattern) {
  f <- list.files(sr_tab, pattern = pattern, full.names = TRUE)
  if (!length(f)) stop("missing table matching: ", pattern)
  # title row then header
  openxlsx::read.xlsx(f[[1]], colNames = TRUE, startRow = 2)
}

.write_sci <- function(path, title, df, footnotes = NULL) {
  bn <- basename(path)
  if (bn %in% .protect_tab) stop("refusing main table: ", bn)
  if (file.exists(path)) unlink(path)
  sci_xlsx_single_header_booktabs(
    filepath = path, title = title, df_body = df,
    sheet = "Sheet1", footnotes = footnotes, blank_na_cells = TRUE
  )
  py <- Sys.which("python3")
  script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
  if (nzchar(py) && file.exists(script)) {
    invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
  }
  message("wrote ", bn)
}

.pdf_out <- function(file, plot, width, height) {
  bn <- basename(file)
  if (bn %in% .protect_fig) stop("refusing main fig: ", bn)
  if (file.exists(file)) unlink(file)
  # prefer cairo for embedded fonts
  ok <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    ok <- tryCatch({
      grDevices::cairo_pdf(file, width = width, height = height, family = .ff)
      print(plot)
      grDevices::dev.off()
      TRUE
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      FALSE
    })
  }
  if (!ok) {
    grDevices::pdf(file, width = width, height = height, useDingbats = FALSE)
    print(plot)
    grDevices::dev.off()
  }
  message("wrote ", bn)
}

.theme_sci <- function(base_size = 11) {
  ggplot2::theme_bw(base_family = .ff, base_size = base_size) %+replace%
    ggplot2::theme(
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "grey90", linewidth = 0.3),
      axis.title = element_text(face = "plain"),
      axis.text = element_text(colour = "black"),
      legend.title = element_blank(),
      legend.background = element_blank(),
      legend.key = element_blank(),
      strip.background = element_rect(fill = "grey95", colour = "grey70"),
      plot.title = element_text(face = "bold", hjust = 0, margin = margin(b = 6)),
      plot.subtitle = element_text(hjust = 0, colour = "grey30", margin = margin(b = 8)),
      plot.margin = margin(8, 10, 8, 8)
    )
}

.pal_class <- c(C1 = "#0072B2", C2 = "#E69F00", C3 = "#D55E00")
.pal_fs <- c(
  "Low global disability" = "#0072B2",
  "Work / mobility-predominant disability" = "#E69F00",
  "Pervasive high disability" = "#D55E00",
  "Social / participation-predominant disability" = "#009E73"
)

# ── load old S bodies ───────────────────────────────────────────────────────
t_contrast <- .read_s("^Table S1\\. Indirect")
t_domain <- .read_s("^Table S2\\. WHO-DAS domain")
t_cfa <- .read_s("^Table S3\\. CFA")
t_sss <- .read_s("^Table S4\\. Mediation with SSS")
t_sens <- .read_s("^Table S5\\. Sensitivity")
t_strat <- .read_s("^Table S6\\. Stratified")
t_roc <- .read_s("^Table S7\\. Clinical ROC")
t_n12 <- .read_s("^Table S8\\. Objective visit")
t_rev <- .read_s("^Table S9\\. Competing")
t_fdr <- .read_s("^Table S10\\. Spearman")
t_inv <- .read_s("^Table S11\\. Measurement")
t_mg <- .read_s("^Table S12\\. Multi-group")
t_imm <- .read_s("^Table S13\\. Formal")
t_fiml <- .read_s("^Table S14\\. FIML")
t_obj <- .read_s("^Table S15\\. Mediation with objective")
t_fs <- .read_s("^Table S16\\. Qualitative functional")
t_gloss <- .read_s("^Table S17\\. Qualitative gloss")

.clean_names <- function(df) {
  names(df) <- gsub("\\.", " ", names(df))
  names(df) <- gsub("\\s+", " ", names(df))
  names(df) <- trimws(names(df))
  df
}
t_contrast <- .clean_names(t_contrast)
t_domain <- .clean_names(t_domain)
t_cfa <- .clean_names(t_cfa)
t_sss <- .clean_names(t_sss)
t_sens <- .clean_names(t_sens)
t_strat <- .clean_names(t_strat)
t_roc <- .clean_names(t_roc)
t_n12 <- .clean_names(t_n12)
t_rev <- .clean_names(t_rev)
t_fdr <- .clean_names(t_fdr)
t_inv <- .clean_names(t_inv)
t_mg <- .clean_names(t_mg)
t_imm <- .clean_names(t_imm)
t_fiml <- .clean_names(t_fiml)
t_obj <- .clean_names(t_obj)
t_fs <- .clean_names(t_fs)
t_gloss <- .clean_names(t_gloss)

# drop footnote-like trailing rows (NA in first col)
.drop_trail <- function(df) {
  if (!nrow(df)) return(df)
  keep <- !is.na(df[[1]]) & nzchar(as.character(df[[1]]))
  # also drop rows that look like footnotes
  txt <- as.character(df[[1]])
  keep <- keep & !grepl("^Supplementary|^Bootstrap|^Domains follow|^N12AA|^Primary|^Estimator|^Alexithymia|^k-means|^DAS8|^Exposure", txt, ignore.case = TRUE)
  df[keep, , drop = FALSE]
}
for (nm in c("t_contrast","t_domain","t_cfa","t_sss","t_sens","t_strat","t_roc","t_n12",
             "t_rev","t_fdr","t_inv","t_mg","t_imm","t_fiml","t_obj","t_fs","t_gloss")) {
  assign(nm, .drop_trail(get(nm)))
}

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S1 — Extended mediation pathways (merged)
# ═══════════════════════════════════════════════════════════════════════════
rows1 <- list()
# A contrast
for (i in seq_len(nrow(t_contrast))) {
  rows1[[length(rows1) + 1L]] <- data.frame(
    Panel = "A. H3 contrast (PHQ-15 → mediators → WHO-DAS)",
    Model = as.character(t_contrast$Mediator[i]),
    Path = "Indirect (ACME)",
    Estimate = as.character(t_contrast$ACME[i]),
    LLCI = as.character(t_contrast$LLCI[i]),
    ULCI = as.character(t_contrast$ULCI[i]),
    Other = paste0("Prop=", as.character(t_contrast[["Prop mediated"]][i] %||% t_contrast[[5]][i])),
    stringsAsFactors = FALSE
  )
}
# B SSS-8 indirect only
sss_ind <- t_sss[grepl("Indirect", t_sss$Path, ignore.case = TRUE), , drop = FALSE]
for (i in seq_len(nrow(sss_ind))) {
  rows1[[length(rows1) + 1L]] <- data.frame(
    Panel = "B. SSS-8 as exposure",
    Model = as.character(sss_ind$Model[i]),
    Path = "Indirect",
    Estimate = as.character(sss_ind$Effect[i]),
    LLCI = as.character(sss_ind$LLCI[i]),
    ULCI = as.character(sss_ind$ULCI[i]),
    Other = paste0("Effect size=", as.character(sss_ind[["Effect size"]][i] %||% sss_ind[[7]][i])),
    stringsAsFactors = FALSE
  )
}
# C sensitivity indirect
sens_ind <- t_sens[grepl("Indirect", t_sens$Path, ignore.case = TRUE), , drop = FALSE]
for (i in seq_len(nrow(sens_ind))) {
  rows1[[length(rows1) + 1L]] <- data.frame(
    Panel = "C. Sensitivity +/- depression-anxiety covariates",
    Model = as.character(sens_ind$Model[i]),
    Path = "Indirect",
    Estimate = as.character(sens_ind$Effect[i]),
    LLCI = as.character(sens_ind$LLCI[i]),
    ULCI = as.character(sens_ind$ULCI[i]),
    Other = paste0("Effect size=", as.character(sens_ind[["Effect size"]][i] %||% sens_ind[[7]][i])),
    stringsAsFactors = FALSE
  )
}
# D reverse
for (i in seq_len(nrow(t_rev))) {
  rows1[[length(rows1) + 1L]] <- data.frame(
    Panel = "D. Competing / reverse models",
    Model = as.character(t_rev$Model[i]),
    Path = "ACME",
    Estimate = as.character(t_rev$ACME[i]),
    LLCI = as.character(t_rev$LLCI[i]),
    ULCI = as.character(t_rev$ULCI[i]),
    Other = paste0("Sig=", as.character(t_rev$Sig[i])),
    stringsAsFactors = FALSE
  )
}
new_s1 <- do.call(rbind, rows1)

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S2 — WHO-DAS domains + gloss
# ═══════════════════════════════════════════════════════════════════════════
# normalize domain colnames
names(t_domain) <- c("Domain", "Overall", "C1 mean (SD)", "C2 mean (SD)", "C3 mean (SD)", "H (Kruskal)", "P")[seq_len(ncol(t_domain))]
t_domain$Section <- "A. Domain scores by severity LCA"
names(t_gloss) <- c("Severity LCA", "Qualitative gloss", "Primary elevated domains")[seq_len(ncol(t_gloss))]
# bind with aligned columns via long-ish layout
s2a <- data.frame(
  Section = "A. Domain scores by severity LCA",
  Item = t_domain$Domain,
  Col1 = t_domain$Overall,
  Col2 = t_domain[["C1 mean (SD)"]],
  Col3 = t_domain[["C2 mean (SD)"]],
  Col4 = t_domain[["C3 mean (SD)"]],
  Stat = t_domain[["H (Kruskal)"]],
  P = t_domain$P,
  stringsAsFactors = FALSE
)
s2b <- data.frame(
  Section = "B. Qualitative gloss for main-text C1-C3",
  Item = t_gloss[["Severity LCA"]],
  Col1 = t_gloss[["Qualitative gloss"]],
  Col2 = t_gloss[["Primary elevated domains"]],
  Col3 = "", Col4 = "", Stat = "", P = "",
  stringsAsFactors = FALSE
)
new_s2 <- rbind(s2a, s2b)
names(new_s2) <- c("Section", "Item", "Overall / gloss", "C1 / elevated domains", "C2", "C3", "H", "P")

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S3 — Measurement + multi-group SEM
# ═══════════════════════════════════════════════════════════════════════════
cfa_row <- data.frame(
  Block = "A. Overall two-factor CFA",
  Grouping = "All",
  Model = "CFA",
  n = as.character(t_cfa$n[1]),
  CFI = as.character(t_cfa$CFI[1]),
  TLI = as.character(t_cfa$TLI[1]),
  RMSEA = as.character(t_cfa$RMSEA[1]),
  SRMR = as.character(t_cfa$SRMR[1]),
  Extra = sprintf("phi=%s; Fornell-Larcker=%s",
                  as.character(t_cfa[[5]][1]), as.character(t_cfa[[8]][1])),
  stringsAsFactors = FALSE
)
inv <- t_inv
names(inv)[1:10] <- c("Grouping","Model","n","Group n","ChiSq","df","CFI","TLI","RMSEA","SRMR")[seq_len(min(10, ncol(inv)))]
s3b <- data.frame(
  Block = "B. Measurement invariance",
  Grouping = inv$Grouping,
  Model = inv$Model,
  n = as.character(inv$n),
  CFI = as.character(inv$CFI),
  TLI = as.character(inv$TLI),
  RMSEA = as.character(inv$RMSEA),
  SRMR = as.character(inv$SRMR),
  Extra = paste0("ChiSq=", inv$ChiSq, "; df=", inv$df, "; ", inv[["Group n"]]),
  stringsAsFactors = FALSE
)
mg <- t_mg
s3c <- data.frame(
  Block = "C. Multi-group path SEM (indirect effects)",
  Grouping = paste(mg$Grouping, mg$Group, sep = " | "),
  Model = mg$Path,
  n = as.character(mg[["Group n"]]),
  CFI = "", TLI = "", RMSEA = "", SRMR = "",
  Extra = sprintf("Est=%s (%s, %s); P=%s", mg$Estimate, mg$LLCI, mg$ULCI, mg$P),
  stringsAsFactors = FALSE
)
new_s3 <- rbind(cfa_row, s3b, s3c)

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S4 — Moderated mediation (formal + stratified)
# ═══════════════════════════════════════════════════════════════════════════
s4a <- data.frame(
  Block = "A. Index of moderated mediation (first-stage)",
  Moderator = t_imm$Moderator,
  Level_or_path = t_imm$Path,
  n = as.character(t_imm$n),
  Estimate = as.character(t_imm$Estimate),
  LLCI = as.character(t_imm$LLCI),
  ULCI = as.character(t_imm$ULCI),
  Sig = as.character(t_imm$Sig),
  stringsAsFactors = FALSE
)
s4b <- data.frame(
  Block = "B. Stratified ACME (PHQ-15 → SSD-12 → WHO-DAS)",
  Moderator = t_strat$Moderator,
  Level_or_path = t_strat$Level,
  n = as.character(t_strat$n),
  Estimate = as.character(t_strat$ACME),
  LLCI = as.character(t_strat$LLCI),
  ULCI = as.character(t_strat$ULCI),
  Sig = as.character(t_strat$Sig),
  stringsAsFactors = FALSE
)
new_s4 <- rbind(s4a, s4b)

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S5 — Clinical ROC + objective burden
# ═══════════════════════════════════════════════════════════════════════════
s5a <- data.frame(
  Block = "A. ROC for WHO-DAS median-split",
  Item = t_roc$Predictor,
  n = as.character(t_roc$n),
  Metric1 = paste0("AUC=", t_roc$AUC, " (", t_roc[["AUC lo"]], "-", t_roc[["AUC hi"]], ")"),
  Metric2 = paste0("Youden=", t_roc[["Youden cut"]], "; Sens=", t_roc$Sens, "; Spec=", t_roc$Spec),
  stringsAsFactors = FALSE
)
s5b <- data.frame(
  Block = "B. Visit burden (N12AA) by severity LCA",
  Item = paste(t_n12$Class, t_n12[[2]], sep = " | "),
  n = as.character(t_n12$n),
  Metric1 = paste0("% within class=", t_n12[[4]]),
  Metric2 = "",
  stringsAsFactors = FALSE
)
s5c <- data.frame(
  Block = "C. Mediation to objective outcomes",
  Item = paste(t_obj$Outcome, t_obj$Mediator, sep = " | "),
  n = as.character(t_obj$n),
  Metric1 = paste0("ACME=", t_obj$ACME, " (", t_obj$LLCI, ", ", t_obj$ULCI, ")"),
  Metric2 = paste0("Sig=", t_obj$Sig),
  stringsAsFactors = FALSE
)
new_s5 <- rbind(s5a, s5b, s5c)

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S6 — Robustness FIML/MI + FDR (compact)
# ═══════════════════════════════════════════════════════════════════════════
s6a <- data.frame(
  Block = "A. FIML / MI sensitivity (parallel indirect effects)",
  Item = paste(t_fiml$Method, t_fiml$Path, sep = " | "),
  Estimate = as.character(t_fiml$Estimate),
  LLCI = as.character(t_fiml$LLCI),
  ULCI = as.character(t_fiml$ULCI),
  P = as.character(t_fiml$P),
  stringsAsFactors = FALSE
)
# FDR: keep pairs involving SSD-12 / Whiteley / WHO-DAS / PHQ-15
key <- c("PHQ-15", "SSD-12", "Whiteley-8", "WHO-DAS", "SSS-8", "PHQ-9", "GAD-7")
fdr <- t_fdr
# names may be Var1 Var2 rho P P FDR
cn <- names(fdr)
fdr_keep <- fdr
s6b <- data.frame(
  Block = "B. Spearman correlations with BH-FDR",
  Item = paste(fdr_keep[[1]], fdr_keep[[2]], sep = " - "),
  Estimate = as.character(fdr_keep[[3]]),
  LLCI = "",
  ULCI = "",
  P = paste0("P=", fdr_keep[[4]], "; FDR=", fdr_keep[[5]]),
  stringsAsFactors = FALSE
)
new_s6 <- rbind(s6a, s6b)

# ═══════════════════════════════════════════════════════════════════════════
# NEW Table S7 — Functional subtypes
# ═══════════════════════════════════════════════════════════════════════════
new_s7 <- t_fs
# fix names display
names(new_s7) <- gsub("\\.", " ", names(new_s7))

# ── remove old S tables ─────────────────────────────────────────────────────
old_s <- list.files(sr_tab, pattern = "^Table S", full.names = TRUE)
message("removing ", length(old_s), " old S tables")
unlink(old_s)

.write_sci(
  file.path(sr_tab, "Table S1. Extended mediation pathways.xlsx"),
  "Table S1. Extended mediation pathways (H3 contrast, SSS-8 exposure, sensitivity, competing models).",
  new_s1,
  footnotes = c(
    "Supplementary. Main-text mediation remains Table 6 (PHQ-15 pathways).",
    "Panel A: parallel ACME contrast SSD-12 vs Whiteley-8. Panel B: SSS-8 exposure. Panel C: +/- PHQ-9/GAD-7. Panel D: competing/reverse models.",
    "Bootstrap percentile CI; demographic covariates as in the primary model unless stated."
  )
)
.write_sci(
  file.path(sr_tab, "Table S2. WHO-DAS domains and class gloss.xlsx"),
  "Table S2. WHO-DAS domain scores by severity LCA and qualitative class gloss.",
  new_s2,
  footnotes = c(
    "Supplementary. Section A: domain means (SD); Kruskal-Wallis across C1-C3. Section B: interpretive gloss for main-text classes (does not replace C1-C3 codes).",
    "DAS8/DAS9 absent in file; Getting along uses DAS7; Life activities uses DAS10."
  )
)
.write_sci(
  file.path(sr_tab, "Table S3. Measurement invariance and multi-group SEM.xlsx"),
  "Table S3. CFA discriminant validity, measurement invariance, and multi-group path SEM.",
  new_s3,
  footnotes = c(
    "Supplementary. Block A: overall two-factor CFA. Block B: configural/metric/scalar invariance (MLR). Block C: group-specific indirect effects.",
    "Pain-predominant invariance is exploratory (small Yes cell). Persistent course multi-group SEM omitted (sparse cells)."
  )
)
.write_sci(
  file.path(sr_tab, "Table S4. Moderated mediation.xlsx"),
  "Table S4. Formal moderated mediation and stratified indirect effects.",
  new_s4,
  footnotes = c(
    "Supplementary. Block A: index of moderated mediation (a_XW * b). Block B: stratum-specific ACME.",
    "Alexithymia, catastrophizing, and childhood-trauma scales were unavailable."
  )
)
.write_sci(
  file.path(sr_tab, "Table S5. Clinical thresholds and objective burden.xlsx"),
  "Table S5. Clinical ROC, visit burden, and mediation to objective outcomes.",
  new_s5,
  footnotes = c(
    "Supplementary. Block A: ROC for WHO-DAS median split. Block B: N12AA visit categories by LCA. Block C: PHQ-15 → cognitive mediator → objective Y.",
    "Subjective disability (WHO-DAS) remains the main-text outcome."
  )
)
.write_sci(
  file.path(sr_tab, "Table S6. Robustness FIML MI and FDR.xlsx"),
  "Table S6. Robustness: FIML/multiple imputation sensitivity and FDR-adjusted correlations.",
  new_s6,
  footnotes = c(
    "Supplementary. Block A: path SEM under complete-case, FIML, and MICE m=5 + Rubin. Block B: Spearman rho with Benjamini-Hochberg FDR.",
    "Primary main-text inference remains complete-case bootstrap product-of-coefficients."
  )
)
.write_sci(
  file.path(sr_tab, "Table S7. Qualitative functional subtypes.xlsx"),
  "Table S7. Qualitative functional subtypes from WHO-DAS domain k-means.",
  new_s7,
  footnotes = c(
    "Supplementary. Distinct from main-text severity LCA (Figure 1 / Tables 2-3).",
    "Labels reflect work/mobility vs social/participation profiles and overall disability level."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Beautified figures (3)
# ═══════════════════════════════════════════════════════════════════════════
ck <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), ]
d0$Class <- factor(paste0("C", as.integer(d0$LCA_class)), levels = c("C1", "C2", "C3"))
class_lab <- c(
  C1 = "C1 Low",
  C2 = "C2 Moderate",
  C3 = "C3 High"
)
.domain_mean <- function(dd, items) {
  cols <- intersect(items, names(dd))
  if (!length(cols)) return(rep(NA_real_, nrow(dd)))
  rowMeans(dd[, cols, drop = FALSE], na.rm = TRUE)
}
d0$Cognition <- .domain_mean(d0, c("DAS1", "DAS2"))
d0$Mobility <- .domain_mean(d0, c("DAS3", "DAS4"))
d0$`Self-care` <- .domain_mean(d0, c("DAS5", "DAS6"))
d0$`Getting along` <- .domain_mean(d0, c("DAS7", "DAS8"))
d0$`Life activities` <- .domain_mean(d0, c("DAS9", "DAS10"))
d0$Participation <- .domain_mean(d0, c("DAS11", "DAS12"))
doms <- c("Cognition", "Mobility", "Self-care", "Getting along", "Life activities", "Participation")

# functional subtypes from Table S7 codes if available
if ("Subtype" %in% names(new_s7) && "Code" %in% names(new_s7)) {
  # rebuild kmeans same seed
  mat <- as.matrix(d0[, doms])
  ok <- stats::complete.cases(mat)
  set.seed(42)
  km <- stats::kmeans(scale(mat[ok, , drop = FALSE]), centers = 3L, nstart = 50L)
  d0$FS <- NA_character_
  d0$FS[ok] <- paste0("FS", km$cluster)
  map <- setNames(as.character(new_s7$Subtype), as.character(new_s7$Code))
  d0$FS_lab <- unname(map[d0$FS])
} else {
  d0$FS_lab <- NA_character_
}

.long_mean <- function(dd, group_var, group_lab_map = NULL) {
  long <- do.call(rbind, lapply(doms, function(dm) {
    data.frame(
      Domain = factor(dm, levels = doms),
      Group = dd[[group_var]],
      Score = dd[[dm]],
      stringsAsFactors = FALSE
    )
  }))
  long <- long[is.finite(long$Score) & !is.na(long$Group), ]
  agg <- aggregate(Score ~ Domain + Group, data = long, FUN = function(z) c(mean = mean(z), se = stats::sd(z) / sqrt(length(z))))
  # expand matrix column
  out <- data.frame(
    Domain = agg$Domain,
    Group = agg$Group,
    mean = agg$Score[, "mean"],
    se = agg$Score[, "se"],
    stringsAsFactors = FALSE
  )
  out$Domain <- factor(out$Domain, levels = doms)
  if (!is.null(group_lab_map)) {
    out$Group_lab <- factor(unname(group_lab_map[as.character(out$Group)]), levels = unname(group_lab_map))
  } else {
    out$Group_lab <- factor(out$Group)
  }
  out
}

agg_c <- .long_mean(d0, "Class", class_lab)
agg_c$Panel <- "A. Severity LCA (main-text classes)"
agg_f <- .long_mean(d0[!is.na(d0$FS_lab), ], "FS_lab")
agg_f$Panel <- "B. Qualitative functional subtypes"
agg_f$Group_lab <- factor(agg_f$Group, levels = unique(na.omit(d0$FS_lab)))

# unified domain profile figure
p_domain_a <- ggplot(agg_c, aes(Domain, mean, group = Group_lab, colour = Group_lab)) +
  geom_ribbon(aes(ymin = mean - 1.96 * se, ymax = mean + 1.96 * se, fill = Group_lab),
              alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = setNames(.pal_class, class_lab)) +
  scale_fill_manual(values = setNames(.pal_class, class_lab), guide = "none") +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  labs(title = "A", x = NULL, y = "Domain mean (0-4)") +
  .theme_sci(10) +
  theme(axis.text.x = element_text(angle = 28, hjust = 1, vjust = 1),
        legend.position = "bottom")

p_domain_b <- ggplot(agg_f, aes(Domain, mean, group = Group_lab, colour = Group_lab)) +
  geom_ribbon(aes(ymin = mean - 1.96 * se, ymax = mean + 1.96 * se, fill = Group_lab),
              alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = .pal_fs) +
  scale_fill_manual(values = .pal_fs, guide = "none") +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  labs(title = "B", x = NULL, y = "Domain mean (0-4)") +
  .theme_sci(10) +
  theme(axis.text.x = element_text(angle = 28, hjust = 1, vjust = 1),
        legend.position = "bottom",
        legend.text = element_text(size = 7.5))

# patchwork if available else grid
has_pw <- requireNamespace("patchwork", quietly = TRUE)
if (has_pw) {
  pS1 <- p_domain_a / p_domain_b +
    patchwork::plot_annotation(
      title = "Figure S1. WHO-DAS domain profiles",
      theme = theme(
        plot.title = element_text(family = .ff, face = "bold", size = 12)
      )
    )
} else {
  pS1 <- p_domain_a # fallback single; will print both via arrange
}

# remove old S figs
old_figs <- list.files(sr_pdf, pattern = "^Figure S", full.names = TRUE)
old_mds <- list.files(sr_md, pattern = "^Figure S", full.names = TRUE)
unlink(old_figs); unlink(old_mds)

if (has_pw) {
  .pdf_out(file.path(sr_pdf, "Figure S1. WHO-DAS domain profiles.pdf"), pS1, 8.2, 8.0)
} else {
  file_s1 <- file.path(sr_pdf, "Figure S1. WHO-DAS domain profiles.pdf")
  if (isTRUE(capabilities("cairo"))) {
    grDevices::cairo_pdf(file_s1, width = 8.2, height = 8.0, family = .ff)
  } else {
    grDevices::pdf(file_s1, width = 8.2, height = 8.0, useDingbats = FALSE)
  }
  gridExtra <- requireNamespace("gridExtra", quietly = TRUE)
  if (gridExtra) {
    gridExtra::grid.arrange(p_domain_a, p_domain_b, ncol = 1)
  } else {
    print(p_domain_a)
  }
  grDevices::dev.off()
  message("wrote Figure S1. WHO-DAS domain profiles.pdf")
}
writeLines(c(
  "# Figure S1. WHO-DAS domain profiles",
  "",
  "## 图面说明",
  "双面板折线：A 为正文严重度 LCA（C1-C3）六维均分及 95% CI 带；B 为定性功能亚型（k-means）剖面。",
  "",
  "## 分析上下文",
  "补充图；对应 Table S2 / Table S7。正文 Figure 1 仍为条目 LCA 剖面。"
), file.path(sr_md, "Figure S1. WHO-DAS domain profiles.md"))

# Figure S2 DCA
dca <- utils::read.csv(
  file.path(proj, "step09_clinical_threshold_dca/Tables/Table_clinical_DCA.csv"),
  stringsAsFactors = FALSE
)
names(dca) <- tolower(names(dca))
# add treat-all / none baselines if absent
if (!"all" %in% tolower(dca$predictor)) {
  # approximate treat-all from prevalence ~0.5 for median split; use first threshold grid
  thr <- sort(unique(dca$threshold))
  prev <- 0.5
  dca <- rbind(
    dca,
    data.frame(predictor = "Treat all", threshold = thr, net_benefit = prev - (1 - prev) * thr / pmax(1 - thr, 1e-6)),
    data.frame(predictor = "Treat none", threshold = thr, net_benefit = 0)
  )
}
dca$predictor <- factor(dca$predictor, levels = unique(dca$predictor))
pal_dca <- c(
  SSD12 = "#D55E00", Whiteley8 = "#0072B2", PHQ15 = "#009E73", SSS8 = "#CC79A7",
  `Treat all` = "grey50", `Treat none` = "grey30"
)
pS2 <- ggplot(dca, aes(threshold, net_benefit, colour = predictor, linetype = predictor)) +
  geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.3) +
  geom_line(linewidth = 0.85) +
  scale_colour_manual(values = pal_dca, drop = FALSE) +
  scale_linetype_manual(values = c(
    SSD12 = "solid", Whiteley8 = "solid", PHQ15 = "solid", SSS8 = "solid",
    `Treat all` = "dashed", `Treat none` = "dotted"
  ), guide = "none") +
  coord_cartesian(xlim = c(0.05, 0.8), ylim = c(-0.05, NA)) +
  labs(
    title = "Figure S2. Decision-curve analysis",
    subtitle = "Outcome: WHO-DAS median-split high disability",
    x = "Threshold probability", y = "Net benefit", colour = NULL
  ) +
  .theme_sci(11) +
  theme(legend.position = "bottom")
.pdf_out(file.path(sr_pdf, "Figure S2. Decision curve analysis.pdf"), pS2, 7.5, 5.2)
writeLines(c(
  "# Figure S2. Decision curve analysis",
  "",
  "## 图面说明",
  "SSD-12、Whiteley-8、PHQ-15、SSS-8 预测 WHO-DAS 中位高残疾的净获益曲线；含 Treat-all / Treat-none 参照。",
  "",
  "## 分析上下文",
  "补充图；对应 Table S5 Block A。"
), file.path(sr_md, "Figure S2. Decision curve analysis.md"))

# Figure S3 forest from stratified table
forest <- data.frame(
  label = paste0(t_strat$Moderator, ": ", t_strat$Level, " (n=", t_strat$n, ")"),
  est = as.numeric(t_strat$ACME),
  lo = as.numeric(t_strat$LLCI),
  hi = as.numeric(t_strat$ULCI),
  sig = t_strat$Sig == "Yes",
  stringsAsFactors = FALSE
)
forest <- forest[is.finite(forest$est), ]
forest$label <- factor(forest$label, levels = rev(forest$label))
pS3 <- ggplot(forest, aes(est, label)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40", linewidth = 0.4) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.22, linewidth = 0.55, colour = "grey25") +
  geom_point(aes(fill = sig), shape = 21, size = 2.6, stroke = 0.4, colour = "grey20") +
  scale_fill_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "white"), guide = "none") +
  labs(
    title = "Figure S3. Stratified indirect effects",
    subtitle = "PHQ-15 → SSD-12 → WHO-DAS (bootstrap ACME, 95% CI)",
    x = "ACME", y = NULL
  ) +
  .theme_sci(10) +
  theme(panel.grid.major.y = element_blank())
.pdf_out(
  file.path(sr_pdf, "Figure S3. Stratified mediation ACME forest.pdf"),
  pS3, 7.8, max(4.2, 0.42 * nrow(forest) + 1.8)
)
writeLines(c(
  "# Figure S3. Stratified mediation ACME forest",
  "",
  "## 图面说明",
  "各可用调节分层的间接效应点估计与 95% CI；实心点表示 CI 不含 0。",
  "",
  "## 分析上下文",
  "补充图；对应 Table S4 Block B。"
), file.path(sr_md, "Figure S3. Stratified mediation ACME forest.md"))

# Methods update
methods_path <- file.path(sr, "Methods_statistical_analysis.md")
if (file.exists(methods_path)) {
  old <- readLines(methods_path, warn = FALSE)
  cut <- grep("^## Supplementary materials numbering|^## Extensions aligned|^## Proposed manuscript framing", old)
  if (length(cut)) old <- old[seq_len(min(cut) - 1L)]
  extra <- c(
    "",
    "## Supplementary materials numbering",
    "",
    "Main-text deliverables are **Tables 1–6** and **Figures 1–4** only.",
    "",
    "### Proposed title (Common-Sense Model)",
    "Predictors and mediating mechanisms of disability and social functioning impairment (WHO-DAS 12) among outpatients with somatic symptom disorder in a general hospital: a Common-Sense Model analysis of cognitive-path dominance and heterogeneity.",
    "",
    "### Consolidated supplementary tables",
    "- Table S1: extended mediation pathways (H3 contrast; SSS-8 exposure; ±depression/anxiety; competing/reverse).",
    "- Table S2: WHO-DAS domain scores by severity LCA and qualitative class gloss.",
    "- Table S3: CFA, measurement invariance, and multi-group path SEM.",
    "- Table S4: formal moderated mediation and stratified ACME.",
    "- Table S5: clinical ROC, visit burden, and objective-outcome mediation.",
    "- Table S6: FIML/MI sensitivity and FDR-adjusted correlations.",
    "- Table S7: qualitative functional subtypes (domain k-means).",
    "",
    "### Supplementary figures",
    "- Figure S1: WHO-DAS domain profiles (A severity LCA; B functional subtypes).",
    "- Figure S2: decision-curve analysis.",
    "- Figure S3: stratified mediation ACME forest.",
    ""
  )
  writeLines(c(old, extra), methods_path)
  message("Methods updated")
}

message("DONE consolidate.")
message("S tables: "); print(list.files(sr_tab, pattern = "^Table S"))
message("S figs: "); print(list.files(sr_pdf, pattern = "^Figure S"))
message("Main intact: "); print(list.files(sr_tab, pattern = "^Table [1-6]\\b"))
print(list.files(sr_pdf, pattern = "^Figure [1-4]\\b"))
