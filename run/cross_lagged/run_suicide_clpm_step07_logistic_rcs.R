#!/usr/bin/env Rscript
# step07 — logistic OR and RCS of Index HAMD-17 and HAMA-14 for C-SSRS ideation, 1st.
# Crude, Model 1 (Sex + Age at onset), Model 2 (step04 12 covariates).
# Separate models. Does not adjust for the other scale or for C-SSRS at Index.
# Does not re-run MICE.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step07_logistic_rcs.R

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
exposures <- c("HAMD-17 total, Index", "HAMA-14 total, Index")
model1 <- c("Sex", "Age at onset")

step_dir <- file.path(study_root, "step07_logistic_rcs")
tab_dir <- file.path(step_dir, "Tables")
fig_dir <- file.path(step_dir, "Figures")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(study_root, "step02_imputation/dabiao.RData"), envir = e)
df <- e$dabiao
m2 <- trimws(readLines(file.path(study_root, "step04_univariate_vif/Model2Factors.txt"), warn = FALSE))
m2 <- m2[nzchar(m2)]
if (!all(model1 %in% m2)) stop("Model 1 is not nested in Model 2", call. = FALSE)
need <- unique(c(y_col, exposures, m2))
miss <- setdiff(need, names(df))
if (length(miss)) stop("Missing columns: ", paste(miss, collapse = ", "), call. = FALSE)

.as01 <- function(x) {
  if (is.factor(x) || is.character(x)) {
    as.integer(trimws(as.character(x)) %in% c("1", "Yes", "yes", "YES", "A", "是"))
  } else as.integer(x)
}
df[[y_col]] <- .as01(df[[y_col]])
for (v in m2) if (is.character(df[[v]])) df[[v]] <- factor(df[[v]])
ok <- stats::complete.cases(df[, need, drop = FALSE])
if (!all(ok)) {
  message("[step07] drop incomplete rows: ", sum(!ok))
  df <- df[ok, , drop = FALSE]
}
for (v in m2) if (is.factor(df[[v]])) df[[v]] <- droplevels(df[[v]])
if (nrow(df) != 643L) stop("Expected N=643, got ", nrow(df), call. = FALSE)
if (!all(df[[y_col]] %in% c(0L, 1L))) stop("Outcome is not 0/1", call. = FALSE)

.safe <- function(v) {
  s <- gsub("[^A-Za-z0-9]+", "_", v)
  gsub("^_|_$", "", s)
}
y_safe <- .safe(y_col)
m1_safe <- vapply(model1, .safe, character(1))
m2_safe <- vapply(m2, .safe, character(1))
names(m1_safe) <- model1
names(m2_safe) <- m2

base <- data.frame(Disease = df[[y_col]], stringsAsFactors = FALSE)
for (v in m2) base[[.safe(v)]] <- df[[v]]

bodies <- list()
h1 <- h2 <- NULL
for (x in exposures) {
  d <- base
  d$Index <- as.numeric(df[[x]])
  qg <- .lqg01_assign_quartile_groups(d$Index)
  d$Group <- qg$Group
  d$Num <- qg$Num
  rt <- .lqg01_Tb_ModelGroup3_OR(
    "Disease", "Index", "Group", "Num",
    d, m1_safe, m2_safe, qg$cutoffs, qg$raw_levels,
    include_continuous = TRUE,
    index_label = x
  )
  rt <- data.frame(rt, stringsAsFactors = FALSE)
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
  for (cc in c(4, 5, 7, 8, 10, 11)) rt[[cc]] <- .fix3(rt[[cc]])
  if (is.null(h1)) {
    h1 <- as.character(rt[1, ])
    h2 <- as.character(rt[2, ])
  }
  bodies[[x]] <- rt[-c(1L, 2L), , drop = FALSE]
  message("[step07] quartile table ", x, " rows=", nrow(bodies[[x]]))
}
rt_body <- do.call(rbind, bodies)
rownames(rt_body) <- NULL
colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))
old_tabs <- list.files(tab_dir, pattern = "^Table 3.*\\.(xlsx|tex)$", full.names = TRUE)
if (length(old_tabs)) unlink(old_tabs)
.table_queue_env$items <- list()
export_sci_table(
  rt_body,
  file.path(tab_dir, "Table 3. Logistic regression of Index HAMD-17 and HAMA-14 quartile.xlsx"),
  title = "Table 3. Logistic regression of Index HAMD-17 and HAMA-14 quartile",
  header_row1 = h1,
  header_row2 = h2,
  latex_include_colnames = FALSE,
  table_footnotes = c(
    logistic_glm_table_footnotes(model1, m2),
    paste0("Outpatient N = ", nrow(df), ". Outcome: C-SSRS ideation, 1st (item 2, Yes = 1)."),
    "HAMD-17 total, Index and HAMA-14 total, Index are modeled separately. The other scale and C-SSRS ideation, Index are not covariates.",
    "Continuous rows are OR per 1-point increase. Q1 is the reference. Age was not included."
  )
)
suicide_clpm_flush_sci_tables()

rcs_meta <- list()
colors3 <- .rci01_default_color3()
plot_ff <- plot_font_from_config(config)
old_figs <- list.files(fig_dir, pattern = "^Figure.*\\.pdf$", full.names = TRUE)
if (length(old_figs)) unlink(old_figs)

for (x in exposures) {
  d <- base
  xname <- "Index"
  d[[xname]] <- as.numeric(df[[x]])
  dd <- rms::datadist(d)
  dd$limits["Adjust to", xname] <- stats::median(d[[xname]], na.rm = TRUE)
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
  message("[step07] ", x, " knots = ", best_nk)
  resA <- .rci01_fit_panel(d, xname, best_nk, covar_rhs = NULL)
  resB <- .rci01_fit_panel(d, xname, best_nk, covar_rhs = paste(m1_safe, collapse = "+"))
  resC <- .rci01_fit_panel(d, xname, best_nk, covar_rhs = paste(m2_safe, collapse = "+"))
  x_range <- range(d[[xname]], na.rm = TRUE)
  plot_A <- .rci01_ggrcs_panel(
    d, resA$fit, xname, colors3, resA$an, resA$out,
    "A.Crude Model", resA$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = FALSE, xlab_display = x, config = config, x_range = x_range
  )
  plot_B <- .rci01_ggrcs_panel(
    d, resB$fit, xname, colors3, resB$an, resB$out,
    "B.Model 1", resB$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = FALSE, xlab_display = x, config = config, x_range = x_range
  )
  plot_C <- .rci01_ggrcs_panel(
    d, resC$fit, xname, colors3, resC$an, resC$out,
    "C.Model 2", resC$cutoffs, histbin = 0.01, plot_ff = plot_ff,
    show_cutoff_lines = TRUE, cutoff_vline_mode = "primary",
    xlab_display = x, config = config, x_range = x_range
  )
  fig <- plot_A + plot_B + plot_C + patchwork::plot_layout(nrow = 1)
  short <- if (grepl("^HAMD", x)) "HAMD-17" else "HAMA-14"
  fname <- paste0("Figure. RCS of ", short, " total, Index and C-SSRS ideation, 1st.pdf")
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
  rcs_meta[[x]] <- list(
    pe(resA, paste(short, "Crude")),
    pe(resB, paste(short, "Model 1")),
    pe(resC, paste(short, "Model 2"))
  )
  rcs_meta[[x]][[1L]]$cutoffs <- numeric(0)
  rcs_meta[[x]][[2L]]$cutoffs <- numeric(0)
  message("[step07] wrote ", path)
}
utils::write.csv(
  do.call(rbind, lapply(exposures, function(x) {
    do.call(rbind, lapply(rcs_meta[[x]], function(p) {
      data.frame(exposure = x, model = p$name, nk = p$nk,
                 p_overall = p$p_overall, p_nonlinear = p$p_nonlinear,
                 stringsAsFactors = FALSE)
    }))
  })),
  file.path(step_dir, "rcs_p.csv"),
  row.names = FALSE
)

panels_flat <- unlist(rcs_meta, recursive = FALSE)
meta <- list(
  exposure = "HAMD-17 total, Index and HAMA-14 total, Index",
  outcome = "C-SSRS ideation at 1st",
  outcome_column = y_col,
  grouping = "restricted cubic spline, reference at the median",
  n_by_db = c(Outpatient = nrow(df)),
  n_total = nrow(df),
  combined = FALSE,
  databases = "Outpatient",
  tables_dir = tab_dir,
  findings = list(
    rcs = list(list(
      db = "Outpatient",
      panels = panels_flat
    ))
  )
)
export_pub_figures(fig_dir, meta = meta, config = config, purge = TRUE)
for (x in exposures) {
  short <- if (grepl("^HAMD", x)) "HAMD-17" else "HAMA-14"
  stem <- paste0("Figure. RCS of ", short, " total, Index and C-SSRS ideation, 1st")
  one <- meta
  one$exposure <- x
  one$findings <- list(rcs = list(list(db = "Outpatient", panels = rcs_meta[[x]])))
  pub_figure_write_image_md(
    file.path(fig_dir, "image_information", paste0(stem, ".md")),
    stem, meta = one, raster_ok = TRUE
  )
}
st <- pub_figure_formats_status(fig_dir)
if (length(st$bad_dpi)) stop("DPI below 600: ", paste(st$bad_dpi, collapse = ", "), call. = FALSE)

utils::write.csv(data.frame(
  step = "step07_logistic_rcs", n = nrow(df),
  events = sum(df[[y_col]] == 1L),
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
), file.path(step_dir, "step_meta.csv"), row.names = FALSE)
message("[step07] DONE ", step_dir)
