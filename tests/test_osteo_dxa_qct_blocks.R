#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

common_path <- file.path(root, "Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R")
stopifnot(file.exists(common_path))
source(common_path, local = FALSE)

# Cohen kappa (known 2x2)
x <- c(1, 1, 1, 0, 0, 0)
y <- c(1, 1, 0, 0, 0, 1)
k <- .osteo75_cohen_kappa(x, y)
stopifnot(is.finite(k$kappa), k$n == 6L)

# Diagnostic metrics
m <- .osteo75_diag_metrics(c(1, 1, 1, 0, 0), c(1, 1, 0, 0, 0))
stopifnot(abs(m$sens - 2 / 3) < 1e-8, abs(m$spec - 1) < 1e-8)

# pick_col
df <- data.frame(QCT_vBMD = 1:3, DXA_T_min = 4:6)
stopifnot(identical(.osteo75_pick_col(df, c("missing", "QCT_vBMD")), "QCT_vBMD"))

# make_strata
mini <- data.frame(
  Nathan = c(1L, 2L, 3L, 4L),
  AAC = c(0L, 1L, 0L, 1L),
  BMI = c(22, 25, 30, 23),
  Age = c(60, 70, 55, 66),
  stringsAsFactors = FALSE
)
st <- .osteo75_make_strata(mini, list())
stopifnot(all(c("Nathan", "AAC", "BMI", "Age") %in% names(st)))
stopifnot(length(st$Nathan) == 4L)

if (requireNamespace("pROC", quietly = TRUE)) {
  set.seed(42)
  truth <- c(rep(1L, 10), rep(0L, 10))
  # controls (0) higher BMD than fracture cases (1); default direction ">"
  score_good <- c(rnorm(10, -2), rnorm(10, 0))
  auc <- .osteo75_auc_continuous(truth, score_good)
  stopifnot(is.finite(auc$auc), auc$auc > 0.5)
} else {
  message("note: pROC not installed; AUC helper not exercised in test")
}

cat("helper OK\n")

# ── dxa_qct_agreement: .dqa75_compute on mini data ───────────────────────────
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
agree_path <- file.path(root, "Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R")
stopifnot(file.exists(agree_path))
source(agree_path, local = FALSE)
stopifnot(exists(".dqa75_compute", mode = "function"))

mini_agree <- data.frame(
  QCT_cat = c(0L, 1L, 2L, 0L, 1L, 2L),
  DXA_cat_min = c(0L, 1L, 2L, 1L, 1L, 2L),
  QCT_vBMD = c(120, 100, 80, 110, 95, 70),
  DXA_T_min = c(-1.0, -1.8, -2.8, -1.2, -2.0, -3.0),
  stringsAsFactors = FALSE
)
cfg_agree <- list(
  enable = TRUE,
  qct_cat = "QCT_cat",
  dxa_cat = "DXA_cat_min",
  qct_continuous = "QCT_vBMD",
  dxa_continuous = "DXA_T_min",
  op_level = 2L,
  bland_zscore = TRUE
)
comp <- .dqa75_compute(mini_agree, cfg_agree)
stopifnot(is.list(comp))
stopifnot(identical(as.integer(comp$n), 6L))
# OP binary (cat==2): QCT 001001 vs DXA 001001 → perfect κ=1
stopifnot(is.finite(comp$kappa_binary), abs(comp$kappa_binary - 1) < 1e-8)
stopifnot(identical(as.integer(comp$n_kappa), 6L))
# 3-class exact agreement: 5/6 (row 4: 0 vs 1)
stopifnot(is.finite(comp$agree_3cat), abs(comp$agree_3cat - 5 / 6) < 1e-8)
stopifnot(is.data.frame(comp$table), nrow(comp$table) >= 1L)
stopifnot(is.data.frame(comp$cross_3cat) || is.matrix(comp$cross_3cat))
stopifnot(is.data.frame(comp$bland) || is.list(comp$bland))

# Block path: mini ctx → results filled (CSV/PDF fallback OK in temp out)
out_tmp <- tempfile("dqa75_")
dir.create(out_tmp, recursive = TRUE, showWarnings = FALSE)
ctx <- list(
  data = list(cleaned = mini_agree, imputed = NULL),
  config = list(
    project = list(output_dir = out_tmp, root = root),
    dxa_qct_agreement = cfg_agree
  ),
  results = list()
)
ctx2 <- block_dxa_qct_agreement(ctx)
stopifnot(!is.null(ctx2$results$dxa_qct_agreement))
stopifnot(identical(as.integer(ctx2$results$dxa_qct_agreement$n), 6L))
stopifnot(is.finite(ctx2$results$dxa_qct_agreement$kappa_binary))

cat("agreement OK\n")

# ── diagnostic_vs_fracture: helpers + .dvf75_compute on mini data ─────────────
diag_path <- file.path(root, "Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R")
stopifnot(file.exists(diag_path))
source(diag_path, local = FALSE)
stopifnot(exists(".dvf75_compute", mode = "function"))
stopifnot(exists("block_diagnostic_vs_fracture", mode = "function"))

# Known sens: fracture 1,1,1,0,0 ; DXA OP 1,1,0,0,0 → sens=2/3
sens_chk <- .osteo75_diag_metrics(c(1, 1, 1, 0, 0), c(1, 1, 0, 0, 0))
stopifnot(abs(sens_chk$sens - 2 / 3) < 1e-8)

if (requireNamespace("pROC", quietly = TRUE)) {
  set.seed(7)
  truth_auc <- c(rep(1L, 10), rep(0L, 10))
  # lower BMD = worse; pROC direction ">" (controls > cases)
  score_bmd <- c(rnorm(10, -2), rnorm(10, 0))
  auc_bmd <- .osteo75_auc_continuous(truth_auc, score_bmd, direction = ">")
  stopifnot(is.finite(auc_bmd$auc), auc_bmd$auc > 0.5)
}

mini_diag <- data.frame(
  Vertebral_fracture = c(1L, 1L, 1L, 1L, 0L, 0L, 0L, 0L),
  QCT_cat = c(2L, 2L, 1L, 0L, 0L, 1L, 2L, 0L),
  DXA_cat_min = c(2L, 1L, 2L, 0L, 0L, 0L, 1L, 0L),
  QCT_vBMD = c(70, 75, 95, 110, 125, 100, 80, 130),
  DXA_T_min = c(-3.0, -2.2, -2.7, -1.0, -0.5, -1.2, -1.9, -0.8),
  Nathan_bin = c("1-2", "1-2", "3-4", "3-4", "1-2", "1-2", "3-4", "3-4"),
  AAC = c(0L, 0L, 1L, 1L, 0L, 1L, 0L, 1L),
  BMI_bin = c("<24", "<24", ">=24", ">=24", "<24", ">=24", "<24", ">=24"),
  Age_bin = c("<65", ">=65", "<65", ">=65", "<65", ">=65", "<65", ">=65"),
  stringsAsFactors = FALSE
)
cfg_diag <- list(
  enable = TRUE,
  fracture = "Vertebral_fracture",
  qct_cat = "QCT_cat",
  dxa_cat = "DXA_cat_min",
  qct_continuous = "QCT_vBMD",
  dxa_continuous = "DXA_T_min",
  op_level = 2L,
  strata = c("Nathan_bin", "AAC", "BMI_bin"),
  strata_supplemental = c("Age_bin"),
  export_roc = TRUE,
  export_sens_bar = TRUE
)
comp_d <- .dvf75_compute(mini_diag, cfg_diag)
stopifnot(is.list(comp_d))
stopifnot(identical(as.integer(comp_d$n), 8L))
stopifnot(identical(as.integer(comp_d$n_frac), 4L))
stopifnot(is.data.frame(comp_d$table3), nrow(comp_d$table3) >= 2L)
stopifnot(is.data.frame(comp_d$table4), nrow(comp_d$table4) >= 1L)
stopifnot(all(c("n", "n_frac", "DXA_sens", "QCT_sens", "delta_sens") %in% names(comp_d$table4)))
# Overall: QCT OP among frac = rows 1,2 → 2/4; DXA OP among frac = rows 1,3 → 2/4
stopifnot(abs(comp_d$overall$QCT$sens - 0.5) < 1e-8)
stopifnot(abs(comp_d$overall$DXA$sens - 0.5) < 1e-8)
if (requireNamespace("pROC", quietly = TRUE)) {
  stopifnot(is.finite(comp_d$overall$QCT$auc), is.finite(comp_d$overall$DXA$auc))
}

out_diag <- tempfile("dvf75_")
dir.create(out_diag, recursive = TRUE, showWarnings = FALSE)
ctx_d <- list(
  data = list(cleaned = mini_diag, imputed = NULL),
  config = list(
    project = list(output_dir = out_diag, root = root),
    diagnostic_vs_fracture = cfg_diag
  ),
  results = list()
)
ctx_d2 <- block_diagnostic_vs_fracture(ctx_d)
stopifnot(!is.null(ctx_d2$results$diagnostic_vs_fracture))
stopifnot(identical(as.integer(ctx_d2$results$diagnostic_vs_fracture$n), 8L))
stopifnot(is.character(ctx_d2$results$diagnostic_vs_fracture$table3_path) ||
            is.character(ctx_d2$results$diagnostic_vs_fracture$csv3_path))

cat("diagnostic OK\n")

# ── modality_discordance_profile: Table S5 by discordance_group ───────────────
disc_path <- file.path(root, "Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R")
stopifnot(file.exists(disc_path))
source(disc_path, local = FALSE)
stopifnot(exists(".mdp75_compute", mode = "function"))
stopifnot(exists("block_modality_discordance_profile", mode = "function"))

# Real dabiao (if present): four levels sum to 208; QCT_only_OP == 40
dabiao_path <- "/mnt/g/02block_result/10_osteoporosis/personalized/data/harmonized/D01_osteo_personalized.RData"
if (file.exists(dabiao_path)) {
  e_d <- new.env(parent = emptyenv())
  load(dabiao_path, envir = e_d)
  dabiao <- e_d$dabiao
  stopifnot(is.data.frame(dabiao))
  stopifnot(all(c("Both_OP", "QCT_only_OP", "DXA_only_OP", "Neither_OP") %in% dabiao$discordance_group))
  stopifnot(sum(dabiao$discordance_group == "QCT_only_OP") == 40L)
  stopifnot(identical(as.integer(nrow(dabiao)), 208L))
  stopifnot(identical(as.integer(sum(table(dabiao$discordance_group))), 208L))

  cfg_disc <- list(
    enable = TRUE,
    group_var = "discordance_group",
    exclude_vars = c("SampleID"),
    fracture = "Vertebral_fracture"
  )
  comp_r <- .mdp75_compute(dabiao, cfg_disc)
  stopifnot(is.list(comp_r))
  stopifnot(identical(as.integer(comp_r$n), 208L))
  stopifnot(identical(as.integer(comp_r$n_qct_only), 40L))
  stopifnot(identical(as.integer(sum(comp_r$n_by_group)), 208L))
  stopifnot(is.data.frame(comp_r$table), nrow(comp_r$table) >= 1L)
  stopifnot(is.character(comp_r$footnote), grepl("QCT_only", comp_r$footnote, fixed = TRUE))
  stopifnot(identical(
    as.integer(comp_r$n_qct_only_fracture),
    as.integer(sum(dabiao$Vertebral_fracture[dabiao$discordance_group == "QCT_only_OP"] == 1L, na.rm = TRUE))
  ))

  out_disc <- tempfile("mdp75_")
  dir.create(out_disc, recursive = TRUE, showWarnings = FALSE)
  ctx_disc <- list(
    data = list(cleaned = dabiao, imputed = NULL),
    config = list(
      project = list(output_dir = out_disc, root = root),
      modality_discordance_profile = cfg_disc
    ),
    results = list()
  )
  ctx_disc2 <- block_modality_discordance_profile(ctx_disc)
  stopifnot(!is.null(ctx_disc2$results$modality_discordance_profile))
  stopifnot(identical(as.integer(ctx_disc2$results$modality_discordance_profile$n), 208L))
  stopifnot(
    is.character(ctx_disc2$results$modality_discordance_profile$table_path) ||
      is.character(ctx_disc2$results$modality_discordance_profile$csv_path)
  )
} else {
  message("note: real dabiao missing; exercising mini discordance table only")
  mini_disc <- data.frame(
    SampleID = paste0("S", 1:8),
    Age = c(60, 70, 55, 66, 72, 58, 61, 68),
    BMI = c(22, 25, 30, 23, 27, 24, 21, 26),
    Vertebral_fracture = c(1L, 1L, 0L, 1L, 0L, 0L, 1L, 0L),
    discordance_group = c(
      "Both_OP", "Both_OP", "QCT_only_OP", "QCT_only_OP",
      "DXA_only_OP", "Neither_OP", "Neither_OP", "DXA_only_OP"
    ),
    stringsAsFactors = FALSE
  )
  cfg_disc <- list(
    enable = TRUE,
    group_var = "discordance_group",
    exclude_vars = c("SampleID"),
    fracture = "Vertebral_fracture"
  )
  comp_m <- .mdp75_compute(mini_disc, cfg_disc)
  stopifnot(identical(as.integer(comp_m$n), 8L))
  stopifnot(identical(as.integer(sum(comp_m$n_by_group)), 8L))
  stopifnot(identical(as.integer(comp_m$n_qct_only), 2L))
  stopifnot(identical(as.integer(comp_m$n_qct_only_fracture), 1L))
}

cat("discordance OK\n")
