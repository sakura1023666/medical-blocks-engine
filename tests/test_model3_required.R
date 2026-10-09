root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/model3_required.R"), local = FALSE)

cfg <- list(
  analysis_models = list(
    model3_required_factors = c("Gender", "Race", "Hypertension", "Smoke", "HbA1c")
  ),
  analysis_exclusion = list(disease_vars = c("HbA1c", "Glucose", "T2DM")),
  incidence = list(index_var = "ALT_HDL_C")
)
if (exists("pipeline_index_var_names", mode = "function")) {
  # keep test independent of formula helpers
}

cols <- c("Age", "Gender", "Race", "Hypertension", "Smoke", "Education", "PIR", "LD", "Sodium", "HDL", "HbA1c")
M2 <- c("Education", "PIR", "Age", "LD", "Sodium")
M3 <- pipeline_resolve_model3_factors(M2, cfg, cols, index_var = "ALT_HDL_C")
stopifnot("Gender" %in% M3, "Race" %in% M3, "Hypertension" %in% M3, "Smoke" %in% M3)
stopifnot(!"HbA1c" %in% M3)
stopifnot(identical(M2, M3[seq_along(M2)]))

stopifnot(identical(pipeline_finalize_adjusted_factors(M2, M3, FALSE), M2))
stopifnot(identical(pipeline_finalize_adjusted_factors(M2, M3, TRUE), M3))

tb <- as.data.frame(matrix("", 6L, 15L), stringsAsFactors = FALSE)
tb[1, 5] <- "Crude Model"; tb[1, 14] <- "Model3"
tb[3, 1] <- "Q2"; tb[3, 15] <- "0.12"
tb[4, 1] <- "Q3"; tb[4, 15] <- "0.20"
tb[5, 1] <- "Q4"; tb[5, 15] <- "0.08"
tb[6, 1] <- "p for trend"; tb[6, 15] <- "0.11"
stopifnot(!isTRUE(pipeline_model3_sig_from_table(tb, c("Q1", "Q2", "Q3", "Q4"), threshold = 0.05)))
tb[6, 15] <- "0.01"
stopifnot(isTRUE(pipeline_model3_sig_from_table(tb, c("Q1", "Q2", "Q3", "Q4"), threshold = 0.05)))

fn <- pipeline_model3_table_footnotes(M2[1:2], M2, M3, FALSE)
stopifnot(any(grepl("Model 3 was adjusted", fn)))
stopifnot(any(grepl("not statistically significant", fn)))

# 降级链：全量 M3 不显著时，删临床 extras 后应显著，并回写 M2
ctx0 <- list(results = list())
sig_calls <- 0L
pack_deg <- pipeline_apply_model3_after_m2(
  ctx0, cfg, M2, cols, "ALT_HDL_C",
  sig_fn = function(covs) {
    sig_calls <<- sig_calls + 1L
    # 仅当去掉 LD 后视为显著
    !"LD" %in% covs
  },
  M1 = c("Age", "Education")
)
stopifnot(isTRUE(pack_deg$include_m3), isTRUE(pack_deg$m3_sig))
stopifnot(!"LD" %in% pack_deg$M2)
stopifnot("Gender" %in% pack_deg$M3, "Age" %in% pack_deg$M2)
stopifnot(sig_calls >= 2L)

# 双库默认仍导出 Model3 列（不显著时脚注说明，下游用 Model2）
cfg_dual <- cfg
cfg_dual$dual_db <- list(enable = TRUE)
pack_dual <- pipeline_apply_model3_after_m2(
  list(results = list()), cfg_dual, M2, cols, "ALT_HDL_C",
  sig_fn = function(covs) FALSE,
  M1 = c("Age", "Education")
)
stopifnot(isTRUE(pack_dual$include_m3), isTRUE(pack_dual$model3_insignificant_dual))
stopifnot(identical(sort(pack_dual$M2), sort(M2)))
cfg_dual_off <- cfg_dual
cfg_dual_off$analysis_models$model3_show_when_insignificant <- FALSE
pack_dual_off <- pipeline_apply_model3_after_m2(
  list(results = list()), cfg_dual_off, M2, cols, "ALT_HDL_C",
  sig_fn = function(covs) FALSE,
  M1 = c("Age", "Education")
)
stopifnot(!isTRUE(pack_dual_off$include_m3), isTRUE(pack_dual_off$dual_degrade_skipped))

lay4 <- pipeline_rcs_layout(4)
stopifnot(identical(lay4$nrow, 2L), identical(lay4$ncol, 2L), lay4$width == 12, lay4$height == 10)
lay3 <- pipeline_rcs_layout(3)
stopifnot(identical(lay3$nrow, 1L), lay3$width == 15, lay3$height == 5)
u <- pipeline_union_model3_required(M2, cfg, cols, "ALT_HDL_C")
stopifnot("Gender" %in% u, "Race" %in% u, "Education" %in% u, "LD" %in% u)
stopifnot(!"HbA1c" %in% u)

# HDL 作为 ALT_HDL_C 组分时应剔除：模拟 pipeline_model_factor_exclude_vars
cfg2 <- cfg
cfg2$analysis_models$model3_required_factors <- c("Gender", "HDL")
M3b <- pipeline_resolve_model3_factors(M2, cfg2, cols, "ALT_HDL_C")
# 无 pipeline_model_factor_exclude_vars 的指标组分时 HDL 仍可能留下；有则必须剔除
if (exists("pipeline_model_factor_exclude_vars", mode = "function")) {
  excl <- pipeline_model_factor_exclude_vars(cfg2)
  if ("HDL" %in% excl) stopifnot(!"HDL" %in% M3b)
}

message("test_model3_required: OK")
