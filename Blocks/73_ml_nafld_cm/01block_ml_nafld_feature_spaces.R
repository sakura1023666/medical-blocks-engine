###############################################################################
#  ml_nafld_feature_spaces — C/M/C+M 特征工程（老师方案共识≥2）
#
#  register_block: "ml_nafld_feature_spaces"
#  典型位置: univariate + ml_vif_train_test 之后
#  config$feature_engineering / feature_pools
#  写: ctx$results$nafld_feature_spaces；Tables/Table 3...
###############################################################################

block_ml_nafld_feature_spaces <- function(ctx, ...) {
  cfg <- ctx$config
  common <- file.path(getwd(), "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R")
  if (!file.exists(common)) {
    common <- file.path(
      cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()),
      "Blocks/73_ml_nafld_cm/00ml_nafld_cm_common.R"
    )
  }
  if (file.exists(common)) source(common, local = FALSE)
  .nafld_cm_ensure_dirs(cfg)

  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
  if (is.null(data)) stop("ml_nafld_feature_spaces: 无 imputed/cleaned 数据", call. = FALSE)

  # 合并代谢组
  data <- .nafld_cm_load_metabolome(cfg, data)
  ctx <- .nafld_cm_attrition_record_cohort(ctx, cfg)
  data_fe <- .nafld_cm_training_df(ctx, data)
  cli::cli_alert_info("特征工程用训练集 n={nrow(data_fe)} / 全队列 n={nrow(data)}")

  oc <- cfg$data$outcome_column %||% "Disease"
  pos <- cfg$project$analysis_group %||% "NAFLD"
  c_vars <- .nafld_cm_clinical_pool(cfg, data_fe)
  m_vars <- .nafld_cm_metabolite_pool(cfg, data_fe)
  cli::cli_alert_info("特征池 C={length(c_vars)} M={length(m_vars)} n_fe={nrow(data_fe)}")

  mm_c <- .nafld_cm_model_matrix(data_fe, c_vars, oc, pos)
  mm_m <- .nafld_cm_model_matrix(data_fe, m_vars, oc, pos)

  fe_c <- .nafld_cm_fe_clinical(mm_c$x, mm_c$y, cfg)
  fe_m <- .nafld_cm_fe_metabolite(mm_m$x, mm_m$y, cfg)
  # C+M：两侧入选并集后再可选共识（此处用并集）
  fe_cm_sel <- unique(c(fe_c$selected, fe_m$selected))
  if (!length(fe_c$selected) && length(c_vars)) {
    fe_c$selected <- c_vars[seq_len(min(10L, length(c_vars)))]
    cli::cli_alert_warning("C 共识为空，临时保留前 10 临床候选")
  }
  if (!length(fe_m$selected) && length(m_vars)) {
    # 仅 Wilcoxon 显著作兜底
    fe_m$selected <- fe_m$wilcoxon_fdr
    if (!length(fe_m$selected)) fe_m$selected <- m_vars[seq_len(min(15L, length(m_vars)))]
    cli::cli_alert_warning("M 共识偏空，已用 Wilcoxon/前 15 兜底")
  }
  fe_cm_sel <- unique(c(fe_c$selected, fe_m$selected))

  res <- list(
    C = fe_c, M = fe_m, CM = list(selected = fe_cm_sel),
    pool_C = c_vars, pool_M = m_vars, n_fe = nrow(data_fe)
  )
  ctx$results$nafld_feature_spaces <- res

  # Table 3
  rows <- list(
    data.frame(space = "C", method = "boruta", feature = fe_c$boruta, stringsAsFactors = FALSE),
    data.frame(space = "C", method = "lasso", feature = fe_c$lasso, stringsAsFactors = FALSE),
    data.frame(space = "C", method = "vif", feature = fe_c$vif, stringsAsFactors = FALSE),
    data.frame(space = "C", method = "consensus", feature = fe_c$selected, stringsAsFactors = FALSE),
    data.frame(space = "M", method = "wilcoxon_fdr", feature = fe_m$wilcoxon_fdr, stringsAsFactors = FALSE),
    data.frame(space = "M", method = "boruta", feature = fe_m$boruta, stringsAsFactors = FALSE),
    data.frame(space = "M", method = "rf", feature = fe_m$rf, stringsAsFactors = FALSE),
    data.frame(space = "M", method = "consensus", feature = fe_m$selected, stringsAsFactors = FALSE),
    data.frame(space = "CM", method = "consensus", feature = fe_cm_sel, stringsAsFactors = FALSE)
  )
  tab <- do.call(rbind, lapply(rows, function(d) if (nrow(d) && length(d$feature)) d else NULL))
  out <- .nafld_cm_out_dirs(cfg)
  utils::write.csv(tab, file.path(out$tables, "Table 3. Selected features by space.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  # 摘要计数
  summ <- data.frame(
    space = c("C", "M", "CM"),
    n_selected = c(length(fe_c$selected), length(fe_m$selected), length(fe_cm_sel)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(summ, file.path(out$tables, "Table 3. Feature count summary.csv"),
                   row.names = FALSE, fileEncoding = "UTF-8")
  cli::cli_alert_success(
    "Table 3: C={length(fe_c$selected)} M={length(fe_m$selected)} CM={length(fe_cm_sel)}"
  )
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block(
    "ml_nafld_feature_spaces",
    block_ml_nafld_feature_spaces,
    "NAFLD C/M/C+M 特征工程（共识≥2）"
  )
}
