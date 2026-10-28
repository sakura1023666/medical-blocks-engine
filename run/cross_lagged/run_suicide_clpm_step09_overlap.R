#!/usr/bin/env Rscript
# step09 — content-overlap sensitivity for the outpatient suicide CLPM.
# HAMD-16 (Index items without H3 Suicide) and HAMA-13 (Index items without A6
# Depressed mood) replace the totals as exposures for C-SSRS ideation, 1st.
# Same Crude / Model 1 (Sex + Age at onset) / Model 2 (step04 12 covariates) as
# step07, quartile logistic table (OR per 1 point) + ggrcs panels.
# Blank item cells are scored 0, which reproduces the stored totals, so N stays 643.
# Also: VIF of the HAMD-17 and HAMA-14 totals in the joint step05 models, and an
# excerpt of the existing item-level CLPN edges for H3 / A6 vs S1-S5.
# Everything is written ONLY to step09_content_overlap/. No existing folder is
# modified. Does not re-run MICE. Does not touch Table 2 or Figure 2.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step09_overlap.R

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
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)
if (!exists("pipeline_sci_with_model3_header", mode = "function")) {
  source(file.path(engine_root, "R/model3_required.R"), local = FALSE)
}
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(engine_root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"), local = FALSE)
source(file.path(engine_root, "Blocks/11_logistic/01block_logistic_quartile_glm.R"), local = FALSE)
source(file.path(engine_root, "Blocks/15_rcs/02block_rcs_incidence.R"), local = FALSE)

.cfg_env <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_suicide_clpm.R"), envir = .cfg_env)
config <- .cfg_env$config
if (exists("pipeline_apply_pub_digits", mode = "function")) pipeline_apply_pub_digits(config)
options(pipeline.database_name = "Outpatient")

suppressPackageStartupMessages({
  library(rms)
  library(ggplot2)
  library(ggrcs)
  library(patchwork)
})

y_col <- "C-SSRS ideation, 1st"
hamd_i <- "HAMD-17 total, Index"
hama_i <- "HAMA-14 total, Index"
css_i <- "C-SSRS ideation, Index"
hamd_f <- "HAMD-17 total, 1st"
hama_f <- "HAMA-14 total, 1st"
model1 <- c("Sex", "Age at onset")

step_dir <- file.path(study_root, "step09_content_overlap")
tab_dir <- file.path(step_dir, "Tables")
fig_dir <- file.path(step_dir, "Figures")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(study_root, "step02_imputation/dabiao.RData"), envir = e)
df <- e$dabiao
m2 <- trimws(readLines(file.path(study_root, "step04_univariate_vif/Model2Factors.txt"), warn = FALSE))
m2 <- m2[nzchar(m2)]
if (!all(model1 %in% m2)) stop("Model 1 is not nested in Model 2", call = FALSE)

.as01 <- function(x) {
  if (is.factor(x) || is.character(x)) {
    as.integer(trimws(as.character(x)) %in% c("1", "Yes", "yes", "YES", "A", "是"))
  } else as.integer(x)
}
df[[y_col]] <- .as01(df[[y_col]])
df[[css_i]] <- .as01(df[[css_i]])
for (v in m2) if (is.character(df[[v]])) df[[v]] <- factor(df[[v]])

# ---- item-level Index scores from the raw wave-1 files (same join as the CLPN) ----
.load_raw <- function(file) {
  ee <- new.env(parent = emptyenv())
  load(file.path(study_root, "data/RDATA/RDATA/01RawData", file), envir = ee)
  as.data.frame(get(ls(ee)[1L], envir = ee))
}
id <- df$ID
hamd_raw <- .load_raw("D08_HAMD1.RData")
hama_raw <- .load_raw("D07_HAMA1.RData")
hit_h <- match(id, hamd_raw[["新编号"]])
hit_a <- match(id, hama_raw[["新编号"]])
if (anyNA(hit_h) || anyNA(hit_a)) stop("Unmatched ID joining item files", call = FALSE)
hamd_items <- as.data.frame(lapply(hamd_raw[hit_h, paste0("HAMD_index_", 1:17), drop = FALSE],
                                   function(z) suppressWarnings(as.numeric(z))))
hama_items <- as.data.frame(lapply(hama_raw[hit_a, paste0("HAMA_index_", 1:14), drop = FALSE],
                                   function(z) suppressWarnings(as.numeric(z))))
names(hamd_items) <- paste0("H", 1:17)
names(hama_items) <- paste0("A", 1:14)

# Blank cells are scored 0. Across all 643 rows this reproduces the stored totals.
n_blank_h <- sum(rowSums(is.na(hamd_items)) > 0)
n_blank_a <- sum(rowSums(is.na(hama_items)) > 0)
hamd_items[] <- lapply(hamd_items, function(z) { z[is.na(z)] <- 0; z })
hama_items[] <- lapply(hama_items, function(z) { z[is.na(z)] <- 0; z })
chk_h <- rowSums(hamd_items) - as.numeric(df[[hamd_i]])
chk_a <- rowSums(hama_items) - as.numeric(df[[hama_i]])
message("[step09] sum-check HAMD (NA as 0): max |diff| = ", format(max(abs(chk_h), na.rm = TRUE)),
        "; HAMA: max |diff| = ", format(max(abs(chk_a), na.rm = TRUE)))
if (max(abs(chk_h), na.rm = TRUE) > 1e-6 || max(abs(chk_a), na.rm = TRUE) > 1e-6) {
  stop("NA-as-0 item sums do not match the stored totals", call. = FALSE)
}

hamd16 <- rowSums(hamd_items[, setdiff(names(hamd_items), "H3"), drop = FALSE])
hama13 <- rowSums(hama_items[, setdiff(names(hama_items), "A6"), drop = FALSE])

safe_exposures <- list(
  list(
    col = "HAMD16_Index",
    label = "HAMD-16 total, Index (H3 Suicide excluded)",
    short = "HAMD-16",
    values = unname(hamd16),
    n_missing_item = n_blank_h
  ),
  list(
    col = "HAMA13_Index",
    label = "HAMA-13 total, Index (A6 Depressed mood excluded)",
    short = "HAMA-13",
    values = unname(hama13),
    n_missing_item = n_blank_a
  )
)
for (ex in safe_exposures) df[[ex$col]] <- ex$values

.safe <- function(v) {
  s <- gsub("[^A-Za-z0-9]+", "_", v)
  gsub("^_|_$", "", s)
}
m1_safe <- vapply(model1, .safe, character(1))
m2_safe <- vapply(m2, .safe, character(1))
names(m1_safe) <- model1
names(m2_safe) <- m2

# =========================== Table S3: quartile logistic ======================
base <- data.frame(Disease = df[[y_col]], stringsAsFactors = FALSE)
for (v in m2) base[[.safe(v)]] <- df[[v]]

.fix3 <- function(x) {
  x <- as.character(x)
  out <- x
  for (i in seq_along(x)) {
    num <- suppressWarnings(as.numeric(x[i]))
    if (is.finite(num)) {
      out[i] <- formatC(num, format = "f", digits = 3)
    } else if (grepl("^\\(", x[i])) {
      parts <- strsplit(gsub("[()]", "", x[i]), ",", fixed = TRUE)[[1]]
      nums <- suppressWarnings(as.numeric(parts))
      if (length(nums) == 2L && all(is.finite(nums))) {
        out[i] <- paste0(
          "(", formatC(nums[1], format = "f", digits = 3), ",",
          formatC(nums[2], format = "f", digits = 3), ")"
        )
      }
    }
  }
  out
}

bodies <- list()
h1 <- h2 <- NULL
sd_scales <- c()
for (ex in safe_exposures) {
  d <- base
  d$Index <- as.numeric(df[[ex$col]])
  if (anyNA(d$Index)) stop(ex$short, " still has missing scores", call. = FALSE)
  d <- d[stats::complete.cases(d[, c("Disease", "Index", m1_safe, m2_safe)]), , drop = FALSE]
  qg <- .lqg01_assign_quartile_groups(d$Index)
  d$Group <- qg$Group
  d$Num <- qg$Num
  rt <- .lqg01_Tb_ModelGroup3_OR(
    "Disease", "Index", "Group", "Num",
    d, m1_safe, m2_safe, qg$cutoffs, qg$raw_levels,
    include_continuous = TRUE,
    index_label = ex$label
  )
  rt <- data.frame(rt, stringsAsFactors = FALSE)
  for (cc in c(4, 5, 7, 8, 10, 11)) rt[[cc]] <- .fix3(rt[[cc]])
  sd_scales <- c(sd_scales, stats::sd(d$Index, na.rm = TRUE))
  body <- rt[-c(1L, 2L), , drop = FALSE]
  colnames(body) <- paste0("V", seq_len(ncol(body)))
  if (is.null(h1)) {
    h1 <- as.character(rt[1, ])
    h2 <- as.character(rt[2, ])
  }
  bodies[[ex$col]] <- body
  message("[step09] quartile table ", ex$label, " n=", nrow(d),
          " events=", sum(d$Disease))
}
rt_body <- do.call(rbind, bodies)
rownames(rt_body) <- NULL
.table_queue_env$items <- list()
export_sci_table(
  rt_body,
  file.path(tab_dir, "Table S3. Logistic quartile of HAMD-16 excluding H3 and HAMA-13 excluding A6.xlsx"),
  title = "Table S3. Logistic quartile of HAMD-16 excluding H3 and HAMA-13 excluding A6",
  header_row1 = h1,
  header_row2 = h2,
  latex_include_colnames = FALSE,
  table_footnotes = c(
    logistic_glm_table_footnotes(model1, m2),
    "Sensitivity analysis for content overlap. HAMD-16 is the Index HAMD-17 sum without item H3 (Suicide), which directly overlaps the C-SSRS ideation items. HAMA-13 is the Index HAMA-14 sum without item A6 (Depressed mood); A6 is a correlated depression item, not suicide content.",
    "Outcome: C-SSRS ideation, 1st (item 2, Yes = 1). The continuous row is the OR per 1 point, the same scale as the main HAMD-17 and HAMA-14 models. Q1 is the reference. The two scales are modeled separately.",
    paste0(
      "Outpatient N = ", nrow(df), " for both exposures, the same cohort as the main analysis. ",
      "Blank item cells (4 HAMD rows, 3 HAMA rows) were scored 0; this reproduces the stored totals. ",
      "HAMD-16 is the HAMD-17 total minus H3. HAMA-13 is the HAMA-14 total minus A6. No one was excluded for a blank item."
    ),
    "Age was not included."
  )
)
suicide_clpm_flush_sci_tables()
if (identical(Sys.getenv("STEP09_STOP_AFTER"), "s3")) {
  message("[step09] stop after Table S3")
  quit(save = "no", status = 0)
}

# =============================== RCS figures ==================================
rcs_meta <- list()
colors3 <- .rci01_default_color3()
plot_ff <- plot_font_from_config(config)
rcs_rows <- list()
dir.create(file.path(fig_dir, "image_information"), recursive = TRUE, showWarnings = FALSE)
for (k in seq_along(safe_exposures)) {
  ex <- safe_exposures[[k]]
  d <- base
  d$Index <- as.numeric(df[[ex$col]])
  d <- d[stats::complete.cases(d), , drop = FALSE]
  dd <- rms::datadist(d)
  dd$limits["Adjust to", "Index"] <- stats::median(d$Index, na.rm = TRUE)
  assign("dd", dd, envir = .GlobalEnv)
  options(datadist = "dd")
  best_nk <- 3L
  best_aic <- Inf
  for (nk in 3:5) {
    fit_nk <- rms::ols(stats::as.formula(paste0("Disease ~ rcs(Index, ", nk, ")")), data = d)
    aic <- stats::AIC(fit_nk)
    if (aic < best_aic) {
      best_aic <- aic
      best_nk <- nk
    }
  }
  message("[step09] ", ex$short, " knots = ", best_nk)
  resA <- .rci01_fit_panel(d, "Index", best_nk, covar_rhs = NULL)
  resB <- .rci01_fit_panel(d, "Index", best_nk, covar_rhs = paste(m1_safe, collapse = "+"))
  resC <- .rci01_fit_panel(d, "Index", best_nk, covar_rhs = paste(m2_safe, collapse = "+"))
  x_range <- range(d$Index, na.rm = TRUE)
  plot_A <- .rci01_ggrcs_panel(
    d, resA$fit, "Index", colors3, resA$an, resA$out,
    "A.Crude Model", resA$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = FALSE, xlab_display = ex$label, config = config, x_range = x_range
  )
  plot_B <- .rci01_ggrcs_panel(
    d, resB$fit, "Index", colors3, resB$an, resB$out,
    "B.Model 1", resB$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = FALSE, xlab_display = ex$label, config = config, x_range = x_range
  )
  plot_C <- .rci01_ggrcs_panel(
    d, resC$fit, "Index", colors3, resC$an, resC$out,
    "C.Model 2", resC$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = TRUE, cutoff_vline_mode = "primary",
    xlab_display = ex$label, config = config, x_range = x_range
  )
  fig <- plot_A + plot_B + plot_C + patchwork::plot_layout(nrow = 1)
  fname <- paste0("Figure S", 3L + k - 1L, ". RCS of ", ex$short,
                  " at Index for C-SSRS ideation at 1st.pdf")
  path <- file.path(fig_dir, fname)
  ggplot2::ggsave(
    path, fig, width = 15, height = 5,
    device = function(filename, width, height, ...) {
      grDevices::cairo_pdf(filename, width = width, height = height, family = plot_ff)
    }
  )
  pe <- function(res, nm) {
    an_m <- as.matrix(res$an)
    list(
      name = nm,
      p_overall = as.numeric(an_m[nrow(an_m), 3L]),
      p_nonlinear = as.numeric(an_m[min(2L, nrow(an_m)), 3L]),
      cutoffs = .rci01_primary_cutoff(res$cutoffs),
      nk = best_nk
    )
  }
  panels <- list(
    pe(resA, paste(ex$short, "Crude")),
    pe(resB, paste(ex$short, "Model 1")),
    pe(resC, paste(ex$short, "Model 2"))
  )
  panels[[1L]]$cutoffs <- numeric(0)
  panels[[2L]]$cutoffs <- numeric(0)
  rcs_rows <- c(rcs_rows, list(data.frame(
    exposure = ex$label, model = vapply(panels, `[[`, character(1), "name"),
    nk = best_nk,
    p_overall = vapply(panels, `[[`, numeric(1), "p_overall"),
    p_nonlinear = vapply(panels, `[[`, numeric(1), "p_nonlinear"),
    stringsAsFactors = FALSE
  )))
  # image md per figure
  meta_one <- list(
    exposure = ex$label,
    outcome = "C-SSRS ideation at 1st",
    outcome_column = y_col,
    grouping = "restricted cubic spline, reference at the median",
    n_by_db = c(Outpatient = nrow(d)),
    n_total = nrow(d),
    combined = FALSE,
    databases = "Outpatient",
    tables_dir = tab_dir,
    findings = list(rcs = list(list(db = "Outpatient", panels = panels)))
  )
  stem <- sub("\\.pdf$", "", fname)
  pub_figure_write_image_md(
    file.path(fig_dir, "image_information", paste0(stem, ".md")),
    stem, meta = meta_one, raster_ok = TRUE
  )
  message("[step09] wrote ", path)
}
utils::write.csv(do.call(rbind, rcs_rows),
                 file.path(step_dir, "rcs_p.csv"), row.names = FALSE)

# ================================ VIF =========================================
.vif_pair <- function(d, preds, pair) {
  out <- vapply(pair, function(p0) {
    others <- setdiff(preds, p0)
    f <- stats::as.formula(paste0("`", p0, "` ~ ",
                                  paste(.btick_safe(others), collapse = " + ")))
    m <- suppressWarnings(stats::lm(f, data = d))
    1 / (1 - max(summary(m)$r.squared, 0))
  }, numeric(1))
  names(out) <- pair
  out
}
.btick_safe <- function(v) paste0("`", v, "`")

vif_models <- list()
{
  dv <- df[, c(y_col, hamd_i, hama_i, css_i, m2), drop = FALSE]
  names(dv)[names(dv) == y_col] <- "Disease"
  for (v in m2) if (is.character(dv[[v]])) dv[[v]] <- factor(dv[[v]])
  dv <- dv[stats::complete.cases(dv), , drop = FALSE]
  preds <- c(hamd_i, hama_i, css_i, m2)
  v <- .vif_pair(dv, preds, pair = c(hamd_i, hama_i))
  vif_models[[1L]] <- data.frame(
    model = "CSSRS-1st logistic ~ HAMD-index + HAMA-index + CSSRS-index + Model 2",
    predictor = "HAMD-index", vif = v[[hamd_i]], stringsAsFactors = FALSE)
  vif_models[[2L]] <- data.frame(
    model = "CSSRS-1st logistic ~ HAMD-index + HAMA-index + CSSRS-index + Model 2",
    predictor = "HAMA-index", vif = v[[hama_i]], stringsAsFactors = FALSE)
}
lin_cases <- list(
  list(y = hamd_f, extra = c(css_i, hamd_i, hama_i),
       note = "HAMD-1st linear ~ HAMD-index + HAMA-index + CSSRS-index + Model 2"),
  list(y = hama_f, extra = c(css_i, hama_i, hamd_i),
       note = "HAMA-1st linear ~ HAMD-index + HAMA-index + CSSRS-index + Model 2"),
  list(y = hama_f, extra = c(hamd_i, hama_i),
       note = "HAMA-1st linear ~ HAMD-index + HAMA-index + Model 2"),
  list(y = hamd_f, extra = c(hama_i, hamd_i),
       note = "HAMD-1st linear ~ HAMA-index + HAMD-index + Model 2")
)
for (lc in lin_cases) {
  dv <- df[, unique(c(lc$y, lc$extra, m2)), drop = FALSE]
  for (v in m2) if (is.character(dv[[v]])) dv[[v]] <- factor(dv[[v]])
  dv <- dv[stats::complete.cases(dv), , drop = FALSE]
  preds <- c(lc$extra, m2)
  v <- .vif_pair(dv, preds, pair = c(hamd_i, hama_i))
  vif_models <- c(vif_models, list(
    data.frame(model = lc$note, predictor = "HAMD-index", vif = v[[hamd_i]], stringsAsFactors = FALSE),
    data.frame(model = lc$note, predictor = "HAMA-index", vif = v[[hama_i]], stringsAsFactors = FALSE)
  ))
}
vif_tab <- do.call(rbind, vif_models)
rownames(vif_tab) <- NULL
vif_tab$vif <- round(vif_tab$vif, 2)
utils::write.csv(vif_tab, file.path(step_dir, "vif_hamd_hama.csv"), row.names = FALSE)
.table_queue_env$items <- list()
export_sci_table(
  data.frame(
    Model = vif_tab$model,
    Predictor = vif_tab$predictor,
    VIF = formatC(vif_tab$vif, format = "f", digits = 2),
    stringsAsFactors = FALSE
  ),
  file.path(tab_dir, "Table S4. VIF of HAMD-17 and HAMA-14 totals in joint models.xlsx"),
  title = "Table S4. VIF of HAMD-17 and HAMA-14 totals in joint models",
  table_footnotes = c(
    "VIF = 1/(1-R2) from regressing each scale total on all other predictors in the model (linear auxiliary regression, standard practice for logistic models as well).",
    "HAMD-index and HAMA-index are the scale totals at Index (about 3 days before discharge). CSSRS-index is C-SSRS ideation item 2 at Index. HAMD-1st, HAMA-1st and CSSRS-1st are the same measures at about 1 month. Model 2 is the 12 baseline covariates.",
    "Outpatient N = 643. These values are reported for transparency; the main models were not changed."
  )
)
suicide_clpm_flush_sci_tables()

# One row per predictor within each distinct predictor set (S4 lists every outcome).
.rhs <- sub("^[^~]+~ ", "", vif_tab$model)
s6_key <- paste(.rhs, vif_tab$predictor, sep = "\t")
s6_raw <- vif_tab[!duplicated(s6_key), , drop = FALSE]
s6 <- data.frame(
  `Predictors in the model` = sub("^[^~]+~ ", "", s6_raw$model),
  Predictor = s6_raw$predictor,
  VIF = formatC(s6_raw$vif, format = "f", digits = 2),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
.table_queue_env$items <- list()
export_sci_table(
  s6,
  file.path(tab_dir, "Table S6. VIF by predictor set.xlsx"),
  title = "Table S6. VIF by predictor set",
  table_footnotes = c(
    "VIF = 1/(1-R2) from regressing the named predictor on the other predictors in the same set. It does not depend on the outcome.",
    "The first set is shared by CSSRS-1st logistic, HAMD-1st linear, and HAMA-1st linear. The second set is shared by the HAMD-1st and HAMA-1st linear models that omit CSSRS-index.",
    "HAMD-index and HAMA-index are the scale totals at Index. CSSRS-index is C-SSRS ideation item 2 at Index. Model 2 is the 12 baseline covariates. Outpatient N = 643. Main models were not changed."
  )
)
suicide_clpm_flush_sci_tables()

# ========================= Network edge excerpt ===============================
ew_path <- file.path(study_root, "C01_network_out_Outpatient_items/edgeWeight_Outpatient.csv")
ew <- utils::read.csv(ew_path, check.names = FALSE, stringsAsFactors = FALSE)
rownames(ew) <- ew[[1L]]
ew <- as.matrix(ew[, -1L, drop = FALSE])
dict <- utils::read.csv(
  file.path(study_root, "C01_network_out_Outpatient_items/item_dictionary.csv"),
  stringsAsFactors = FALSE)
iname <- stats::setNames(dict$item, dict$node)
froms <- c("H3", "A6", paste0("S", 1:5))
tos <- c(paste0("S", 1:5), "H3", "A6")
rows <- list()
for (f in froms) for (t in tos) {
  if (f == t) next
  pair_overlap <- (f %in% c("H3", "A6")) == (t %in% c("H3", "A6"))
  if (pair_overlap && !(f == "H3" && t == "A6") && !(f == "A6" && t == "H3")) next
  rows[[length(rows) + 1L]] <- data.frame(
    From_Index_item = f, From_item = iname[[f]],
    To_1st_item = t, To_item = iname[[t]],
    weight = round(as.numeric(ew[f, t]), 3),
    stringsAsFactors = FALSE
  )
}
edge_tab <- do.call(rbind, rows)
rownames(edge_tab) <- NULL
utils::write.csv(edge_tab, file.path(step_dir, "clpn_overlap_edges.csv"), row.names = FALSE)
.table_queue_env$items <- list()
export_sci_table(
  edge_tab,
  file.path(tab_dir, "Table S5. Item-level CLPN edges for overlapping items.xlsx"),
  title = "Table S5. Item-level CLPN edges for overlapping items",
  table_footnotes = c(
    "Excerpt from the existing item-level LASSO cross-lagged partial network (C01_network_out_Outpatient_items, N = 613). Row = Index item, column = 1st item; weight is the regularized partial correlation.",
    "H3 (Suicide) directly overlaps the C-SSRS ideation items; A6 (Depressed mood) is a correlated depression item, not suicide content.",
    "The network is item to item. Figure 2 and Table 2 are total-score paths (N = 643). One network edge is not a substitute for a total-score coefficient."
  )
)
suicide_clpm_flush_sci_tables()

# ============================ four-dir export =================================
meta <- list(
  exposure = "HAMD-16 total (H3 excluded) and HAMA-13 total (A6 excluded) at Index",
  outcome = "C-SSRS ideation at 1st",
  outcome_column = y_col,
  grouping = "restricted cubic spline, reference at the median",
  n_by_db = c(Outpatient = nrow(df)),
  n_total = nrow(df),
  combined = FALSE,
  databases = "Outpatient",
  tables_dir = tab_dir
)
export_pub_figures(fig_dir, meta = meta, config = config, purge = FALSE)
st <- pub_figure_formats_status(fig_dir)
if (length(st$bad_dpi)) stop("DPI below 600: ", paste(st$bad_dpi, collapse = ", "), call = FALSE)

# strip xlsx after openxlsx round trips
strip_py <- file.path(engine_root, "R/pub_xlsx_tools/xlsx_strip.py")
if (file.exists(strip_py)) {
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  for (xf in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
    system2(py, args = c(shQuote(strip_py), shQuote(xf)))
  }
}

writeLines(c(
  "step09_content_overlap — content-overlap sensitivity (new folder; no existing results were modified).",
  "H3 (Suicide) in HAMD-17 directly overlaps the C-SSRS ideation items; A6 (Depressed mood) in HAMA-14 is a correlated depression item, not suicide content.",
  "Table S3: quartile logistic of HAMD-16 (HAMD-17 total minus H3) and HAMA-13 (HAMA-14 total minus A6) for C-SSRS ideation, 1st; Crude / Model 1 / Model 2; OR per 1 point. Blank item cells were scored 0, so N stays 643.",
  "Figure S3/S4: RCS (A.Crude / B.Model 1 / C.Model 2), same engine style as step07. rcs_p.csv holds P-overall and P-nonlinear.",
  "Table S4: VIF of the HAMD-17 and HAMA-14 totals in the joint step05 models. Main models unchanged.",
  "Table S5: excerpt of the existing item-level CLPN edges (N = 613) for H3/A6 vs S1-S5. The network itself was not re-run.",
  "Items were joined from data/RDATA/RDATA/01RawData wave-1 files by ID. Blank item cells were scored 0, matching the stored totals. Rows were not dropped.",
  "Main Table 2, Figure 2, step05-step08 and summary_results were NOT touched."
), file.path(step_dir, "README.txt"))

utils::write.csv(data.frame(
  step = "step09_content_overlap",
  n_cohort = nrow(df),
  events = sum(df[[y_col]] == 1L),
  hamd16_item_missing_rows = safe_exposures[[1]]$n_missing_item,
  hama13_item_missing_rows = safe_exposures[[2]]$n_missing_item,
  sd_hamd16 = round(sd_scales[1], 3),
  sd_hama13 = round(sd_scales[2], 3),
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
), file.path(step_dir, "step_meta.csv"), row.names = FALSE)
message("[step09] DONE ", step_dir)
