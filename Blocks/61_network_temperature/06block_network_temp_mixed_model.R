###############################################################################
#  network_temp_mixed_model — 青春期性别分层 mixed model（温度 ~ age*sex）
###############################################################################

block_network_temp_mixed_model <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  out_dir <- (ctx$results$network_temp_compute %||% list())$output_dir
  if (is.null(out_dir) || !dir.exists(out_dir))
    stop("network_temp_mixed_model: 请先运行 network_temp_compute", call. = FALSE)

  ising_path <- file.path(out_dir, "Table_Network_Temperature_Ising_by_Wave.csv")
  wave_path <- file.path(out_dir, "Table_Network_Temperature_by_Wave.csv")
  temp_path <- if (file.exists(ising_path)) ising_path else wave_path
  if (!file.exists(temp_path)) stop("network_temp_mixed_model: 缺少温度表", call. = FALSE)

  temp_df <- utils::read.csv(temp_path, stringsAsFactors = FALSE)
  if ("Subgroup" %in% names(temp_df)) {
    temp_df <- temp_df[is.na(temp_df$Subgroup) | temp_df$Subgroup == "" | temp_df$Subgroup == "All", , drop = FALSE]
  }
  if (!"Age" %in% names(temp_df)) temp_df$Age <- temp_df$Wave + 10

  data <- ctx$data$imputed %||% ctx$data$cleaned
  id_col <- bl$id_col %||% "ID"
  sg_col <- bl$subgroup_col %||% "Sex"
  subj <- data[, intersect(c(id_col, sg_col, "Age"), names(data)), drop = FALSE]
  names(subj)[names(subj) == id_col] <- "ID"
  if (sg_col %in% names(subj)) names(subj)[names(subj) == sg_col] <- "Sex"

  long <- (ctx$results$network_temp_prepare_long %||% list())
  if (!is.null(ctx$data$network_long)) {
    nl <- ctx$data$network_long
    val_col <- if ("Value" %in% names(nl)) "Value" else names(nl)[match("Value", names(nl), nomatch = 0L)]
    if (!nzchar(val_col) || !val_col %in% names(nl)) val_col <- "Value"
    subj_wave <- stats::aggregate(
      nl[[val_col]], by = list(ID = nl$ID, Wave = nl$Wave), FUN = mean, na.rm = TRUE
    )
    names(subj_wave)[3L] <- "mean_sym"
    subj_wave <- merge(subj_wave, subj, by = "ID", all.x = TRUE)
    subj_wave$Age <- subj_wave$Age + (subj_wave$Wave - 1) * 2
  } else {
    subj_wave <- temp_df
    subj_wave$ID <- seq_len(nrow(subj_wave))
    subj_wave$Sex <- "All"
  }

  wave_temp <- temp_df[, intersect(c("Wave", "Cohort", "network_temperature", "Age"), names(temp_df)), drop = FALSE]
  subj_wave <- merge(subj_wave, wave_temp, by = "Wave", all.x = TRUE, suffixes = c("", "_wave"))
  if ("network_temperature_wave" %in% names(subj_wave)) {
    miss <- is.na(subj_wave$network_temperature) | !is.finite(subj_wave$network_temperature)
    subj_wave$network_temperature[miss] <- subj_wave$network_temperature_wave[miss]
  }
  subj_wave <- subj_wave[!is.na(subj_wave$network_temperature) & is.finite(subj_wave$network_temperature), , drop = FALSE]

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

  if (nrow(subj_wave) < 10L) {
    cli::cli_alert_warning("mixed model: 有效样本不足 (n={nrow(subj_wave)})，写入占位系数表")
    coef_df <- data.frame(
      term = c("(Intercept)", "Age", "SexMale", "Age:SexMale"),
      Estimate = NA_real_, `Std. Error` = NA_real_, `t value` = NA_real_, `Pr(>|t|)` = NA_real_,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    utils::write.csv(coef_df, file.path(out_tab, "Table_Network_Temperature_MixedModel.csv"), row.names = FALSE)
    ctx$results$network_temp_mixed_model <- list(coefficients = coef_df, n = nrow(subj_wave), note = "insufficient_data")
    return(ctx)
  }

  fit_rows <- list()
  subj_wave$Sex <- factor(subj_wave$Sex)
  n_sex <- length(levels(subj_wave$Sex))
  if (requireNamespace("lme4", quietly = TRUE) && nrow(subj_wave) >= 30L && n_sex >= 2L) {
    fit <- tryCatch(
      lme4::lmer(network_temperature ~ Age * Sex + (1 | ID), data = subj_wave, REML = TRUE),
      error = function(e) NULL
    )
    if (!is.null(fit)) {
      sm <- summary(fit)
      cf <- as.data.frame(sm$coefficients)
      cf$term <- rownames(cf)
      fit_rows[[1L]] <- cf
    }
  }
  if (!length(fit_rows)) {
    form <- if (n_sex >= 2L) network_temperature ~ Age * Sex else network_temperature ~ Age
    fit_lm <- tryCatch(stats::lm(form, data = subj_wave), error = function(e) NULL)
    if (!is.null(fit_lm)) {
      cf <- as.data.frame(summary(fit_lm)$coefficients)
      cf$term <- rownames(cf)
      fit_rows[[1L]] <- cf
    }
  }
  if (!length(fit_rows)) {
    cli::cli_alert_warning("mixed model 拟合失败，写入占位系数表")
    coef_df <- data.frame(
      term = c("(Intercept)", "Age"), Estimate = NA_real_,
      `Std. Error` = NA_real_, check.names = FALSE, stringsAsFactors = FALSE
    )
  } else {
    coef_df <- fit_rows[[1L]]
  }

  utils::write.csv(coef_df, file.path(out_tab, "Table_Network_Temperature_MixedModel.csv"), row.names = FALSE)

  sex_rows <- list()
  if (nrow(subj_wave) >= 20L && "Sex" %in% names(subj_wave)) {
    for (sx in unique(as.character(subj_wave$Sex))) {
      sw <- subj_wave[subj_wave$Sex == sx, , drop = FALSE]
      if (nrow(sw) < 15L) next
      fit_sx <- tryCatch({
        if (requireNamespace("lme4", quietly = TRUE) && length(unique(sw$ID)) >= 5L)
          lme4::lmer(network_temperature ~ Age + (1 | ID), data = sw, REML = TRUE)
        else stats::lm(network_temperature ~ Age, data = sw)
      }, error = function(e) tryCatch(stats::lm(network_temperature ~ Age, data = sw), error = function(e2) NULL))
      if (is.null(fit_sx)) next
      sm <- summary(fit_sx)
      cf <- as.data.frame(sm$coefficients)
      cf$term <- rownames(cf)
      cf$Sex <- sx
      sex_rows[[length(sex_rows) + 1L]] <- cf
    }
    if (length(sex_rows)) {
      sex_df <- do.call(rbind, sex_rows)
      utils::write.csv(sex_df, file.path(out_tab, "Table_Network_Temperature_MixedModel_by_Sex.csv"), row.names = FALSE)
    }
  }

  ctx$results$network_temp_mixed_model <- list(coefficients = coef_df, n = nrow(subj_wave), sex_stratified = sex_rows)
  cli::cli_alert_success("网络温度 mixed model（age×sex）完成")
  ctx
}

register_block("network_temp_mixed_model", block_network_temp_mixed_model, "温度 mixed model 性别趋势")
