###############################################################################
#  multimorbidity_gee_stratified — 按基线分层重复 GEE（稀疏层跳过）
###############################################################################

block_multimorbidity_gee_stratified <- function(ctx, ...) {
  bl <- ctx$config$multimorbidity_gee %||% list()
  mm <- ctx$config$multimorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_gee_stratified: 无数据", call. = FALSE)
  if (!requireNamespace("geepack", quietly = TRUE)) {
    utils::install.packages("geepack", repos = "https://cloud.r-project.org", quiet = TRUE)
  }
  suppressPackageStartupMessages(library(geepack))

  strata <- as.character(bl$stratify_vars %||% c("Gender", "Age_group"))
  if (!"Age_group" %in% names(data) && "Age" %in% names(data)) {
    data$Age_group <- ifelse(data$Age >= 65, "Age>=65", "Age<65")
  }
  # 优先轨迹组，否则四分类
  cat_col <- if (!is.null(mm$trajectory_cluster_col) &&
                 mm$trajectory_cluster_col %in% names(data) &&
                 any(!is.na(data[[mm$trajectory_cluster_col]]))) {
    as.character(mm$trajectory_cluster_col)[1L]
  } else {
    as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
  }
  out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
  time_col <- as.character(bl$time_col %||% "Followup_wave")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  fam <- if (identical(bl$family %||% "gaussian", "binomial")) stats::binomial() else stats::gaussian()
  min_n <- as.integer(bl$min_stratum_n %||% 30L)[1L]
  adjust <- as.character(bl$covariates_m2 %||% c("Age", "Gender"))
  adjust <- setdiff(adjust, strata)

  all_tabs <- list()
  for (sv in strata) {
    if (!sv %in% names(data)) next
    for (lv in unique(stats::na.omit(as.character(data[[sv]])))) {
      sub <- data[as.character(data[[sv]]) == lv, , drop = FALSE]
      if (nrow(sub) < min_n || length(unique(sub[[id_col]])) < 10L) next
      sub[[cat_col]] <- factor(as.character(sub[[cat_col]]))
      if (nlevels(droplevels(sub[[cat_col]])) < 2L) next
      covs <- unique(c(cat_col, time_col, setdiff(adjust, sv)))
      covs <- covs[covs %in% names(sub)]
      form <- stats::as.formula(paste(out_col, "~", paste(covs, collapse = " + ")))
      fit <- tryCatch(
        geepack::geeglm(form, data = sub, id = sub[[id_col]], family = fam, corstr = "exchangeable"),
        error = function(e) NULL
      )
      if (is.null(fit)) next
      sm <- summary(fit)$coefficients
      tab <- data.frame(
        stratum_var = sv, stratum_level = lv, exposure = cat_col,
        term = rownames(sm), beta = sm[, "Estimate"], p = sm[, "Pr(>|W|)"],
        n = nrow(sub), stringsAsFactors = FALSE
      )
      all_tabs[[paste(sv, lv)]] <- tab
    }
  }
  if (!length(all_tabs)) stop("multimorbidity_gee_stratified: 无有效分层结果", call. = FALSE)
  res <- do.call(rbind, all_tabs)
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res, file.path(out_dir, "Table_GEE_Stratified.csv"), row.names = FALSE)
  ctx$results$multimorbidity_gee_stratified <- list(table = res)
  cli::cli_alert_success("分层 GEE 完成（{length(all_tabs)} 层）")
  ctx
}

register_block(
  "multimorbidity_gee_stratified",
  block_multimorbidity_gee_stratified,
  "多病叠加分层 GEE"
)
