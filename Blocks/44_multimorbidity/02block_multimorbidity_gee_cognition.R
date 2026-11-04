###############################################################################
#  multimorbidity_gee_cognition — 基线四分类 × 纵向结局 GEE（阶梯调整）
#
#  register_block: "multimorbidity_gee_cognition"
###############################################################################

.mm_gee_fit_models <- function(data, outcome, exposure, time_col, id_col, cov_lists, family) {
  fam <- if (identical(family, "binomial")) stats::binomial() else stats::gaussian()
  rows <- list()
  for (nm in names(cov_lists)) {
    covs <- unique(c(exposure, time_col, cov_lists[[nm]]))
    covs <- covs[covs %in% names(data)]
    form <- stats::as.formula(paste(outcome, "~", paste(covs, collapse = " + ")))
    fit <- tryCatch(
      geepack::geeglm(form, data = data, id = data[[id_col]], family = fam, corstr = "exchangeable"),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    sm <- summary(fit)$coefficients
    ci <- tryCatch({
      se <- sm[, "Std.err"]
      cbind(lo = sm[, "Estimate"] - 1.96 * se, hi = sm[, "Estimate"] + 1.96 * se)
    }, error = function(e) cbind(lo = NA, hi = NA))
    tab <- data.frame(
      model = nm,
      term = rownames(sm),
      beta = sm[, "Estimate"],
      se = sm[, "Std.err"],
      lo95 = ci[, "lo"],
      hi95 = ci[, "hi"],
      p = sm[, "Pr(>|W|)"],
      stringsAsFactors = FALSE
    )
    rows[[nm]] <- tab
  }
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

block_multimorbidity_gee_cognition <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_cognition: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  cat_col <- as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
  out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
  time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  fam <- as.character(bl$family %||% "gaussian")[1L]
  ref <- as.character(bl$ref_category %||% "Neither")[1L]

  need <- c(cat_col, out_col, time_col, id_col)
  miss <- need[!need %in% names(data)]
  if (length(miss)) stop("multimorbidity_gee_cognition: 缺列 ", paste(miss, collapse = ", "), call. = FALSE)

  data[[cat_col]] <- stats::relevel(factor(as.character(data[[cat_col]])), ref = ref)
  data[[id_col]] <- as.integer(factor(as.character(data[[id_col]])))
  cov_m1 <- as.character(bl$covariates_m1 %||% character(0))
  cov_m2 <- as.character(bl$covariates_m2 %||% c("Age", "Gender"))
  cov_m3 <- as.character(bl$covariates_m3 %||% c("Age", "Gender", "Education", "Hypertension", "Diabetes"))
  cov_lists <- list(Model1 = cov_m1, Model2 = unique(c(cov_m1, cov_m2)), Model3 = unique(c(cov_m1, cov_m2, cov_m3)))

  tab <- .mm_gee_fit_models(data, out_col, cat_col, time_col, id_col, cov_lists, fam)
  if (is.null(tab)) stop("multimorbidity_gee_cognition: GEE 失败", call. = FALSE)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_GEE_Cognition_Multimorbidity.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee <- list(table = tab)
  cli::cli_alert_success("四分类 GEE 完成（n={nrow(data)}; models={length(unique(tab$model))}）")
  ctx
}

register_block(
  "multimorbidity_gee_cognition",
  block_multimorbidity_gee_cognition,
  "多病四分类 GEE"
)
