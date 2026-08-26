###############################################################################
#  mediation_incidence — 发病中介效应（Logistic → OR）+ Table S5/S6 + 路径三角图
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = ctx$results$Model2Factors
#
#  mediation_incidence = list(
#    mediators = NULL,
#    outcome = NULL,
#    bootstrap_iter = 100,
#    covariates = NULL,
#    lm_screen_exclude_vars = NULL,
#    dual_library_lm_screen = TRUE,
#    auto_covariate_search = TRUE,
#    diagram_enable = TRUE,
#    best_mediator = NULL,
#  ),
###############################################################################

block_mediation_incidence <- function(ctx, exposure = NULL, mediators = NULL,
                                 outcome = NULL,
                                 covariates = NULL, bootstrap_iter = 100,
                                 standardize_mediator = FALSE, seed = 1234, ...) {
  common_path <- file.path(getwd(), "Blocks/20_mediation/00mediation_common.R")
  if (file.exists(common_path)) source(common_path, local = FALSE)

  suppressPackageStartupMessages({
    library(survival)
    library(dplyr)
  })

  cfg <- ctx$config
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("No data found. Run 'data_clean' or 'imputation' first.")

  bl_cfg <- cfg$mediation_incidence %||% list()
  surv_cfg <- cfg$survival %||% list()

  exposure <- exposure %||% bl_cfg$exposure %||% surv_cfg$index_var %||% cfg$logistic$index_var
  mediators <- mediators %||% bl_cfg$mediators
  # 路径默认 crude（全项目）；显式 path_use_covariates=TRUE 才用 covariates
  covariates <- if (exists("pipeline_mediation_resolve_path_covariates", mode = "function")) {
    pipeline_mediation_resolve_path_covariates(cfg, bl_cfg, names(data), ctx = ctx)
  } else {
    character(0)
  }
  bootstrap_iter <- bootstrap_iter %||% bl_cfg$bootstrap_iter %||% 100
  standardize_mediator <- isTRUE(bl_cfg$standardize_mediator %||% TRUE)
  seed <- seed %||% bl_cfg$seed %||% cfg$splitting$seed %||% 1234

  if (is.null(mediators) || length(mediators) == 0) {
    a <- colnames(data)
    Index <- exposure
    b <- bl_cfg$lm_screen_exclude_vars
    if (is.null(b) || length(b) == 0L) {
      b <- c(
        "Disease", "Age", "Gender", "Race", "Language", "Marital_Status","Weight","Height","BMI","Smoke","Alcohol","Hyperlipidemia",
        "Micu_Code", "Insurance", "Hypertension", "Heart_Failure", "Myocardial_Infarction",
        "Malignant_Tumor", "T1DM", "T2DM", "CKD", "Acute_Renal_Failure", "Cirrhosis",
        "Hepatitis", "Tuberculosis", "Pneumonia", "Hyperlipidemia", "COPD", "SOFA",
        "APSIII", "SIRS", "SAPSII", "OASIS", "GCS", "CHARLSON", "Ventilation",
        Index, paste0(Index, "_index_cut")
      )
    }
    if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
      b <- unique(c(as.character(b), pipeline_mediation_lab_exclude_vars(cfg, data_cols = a)))
    }

    # 变量名按不区分大小写做差集；剔除时间/结局/ID
    surv_cfg_early <- cfg$survival %||% list()
    b <- unique(c(
      as.character(b),
      as.character(surv_cfg_early$time_var %||% character(0)),
      as.character(surv_cfg_early$event_var %||% character(0)),
      as.character(cfg$data$outcome_column %||% character(0)),
      "RFS_Months", "futime", "fustatus", "Is_Recurrence_factor",
      "Pt_ID", "ID", "SEQN", "Patient_ID"
    ))
    b_lc <- unique(tolower(trimws(as.character(b))))
    var_input <- a[!(tolower(a) %in% b_lc)]
    if (exists("pipeline_mediation_filter_mediators", mode = "function")) {
      var_input <- pipeline_mediation_filter_mediators(
        var_input, cfg, data_cols = a, label = "LM关联筛"
      )
    }

    Model2 <- ctx$results$Model2Factors %||% character(0)
    Model2 <- as.character(Model2)
    if (length(Model2) > 0L) Model2 <- Model2[nzchar(Model2)]
    Model2 <- unique(intersect(Model2, names(data)))
    adj <- if (exists("pipeline_mediation_lm_adjustors", mode = "function")) {
      pipeline_mediation_lm_adjustors(ctx, data_names = names(data))
    } else {
      list(m1 = if (length(Model2)) Model2[1L] else character(0), m2 = Model2)
    }
    Model1Factors <- adj$m1
    Model2Factors <- adj$m2
    if (!length(Model2Factors)) Model2Factors <- Model2
    if (!length(Model1Factors) && length(Model2Factors)) {
      Model1Factors <- Model2Factors[1L]
    }

    .mi02_prepare_cor_numeric <- function(Data, CorName) {
      if (!CorName %in% names(Data)) return(Data)
      x <- Data[[CorName]]
      if (is.numeric(x) && !is.factor(x)) return(Data)
      xf <- if (is.factor(x)) droplevels(x) else factor(x)
      nl <- nlevels(xf)
      if (nl <= 1L) return(Data)
      if (nl == 2L) {
        Data[[CorName]] <- as.numeric(xf) - 1
      } else {
        Data[[CorName]] <- as.numeric(xf)
      }
      Data
    }

    Tb_ModelGroup3_Corlm <- function(ResultName, CorName, Model1Factors, Model2Factors, Data) {
      pick_beta_ci_p <- function(fit, var) {
        if (is.null(fit)) return(c(NA_real_, NA_character_, NA_real_))
        sm <- summary(fit)
        cf <- sm$coefficients
        rn <- rownames(cf)
        if (is.null(rn) || !length(rn)) return(c(NA_real_, NA_character_, NA_real_))
        hits <- if (var %in% rn) var else rn[rn != "(Intercept)" & startsWith(rn, var)]
        if (!length(hits)) return(c(NA_real_, NA_character_, NA_real_))
        conf <- tryCatch(confint(fit), error = function(e) NULL)
        use <- hits[1L]
        if (length(hits) > 1L) {
          betas <- suppressWarnings(as.numeric(cf[hits, 1]))
          use <- hits[which.max(abs(betas))]
        }
        if (is.null(conf) || !(use %in% rownames(conf))) {
          ci <- NA_character_
        } else {
          ci <- paste0("(", round(conf[use, 1], 3), ",", round(conf[use, 2], 3), ")")
        }
        c(
          round(as.numeric(cf[use, 1]), 3),
          ci,
          round(as.numeric(cf[use, 4]), 3)
        )
      }

      Data <- .mi02_prepare_cor_numeric(Data, CorName)
      if (CorName %in% names(Data) && is.numeric(Data[[CorName]])) {
        Data[[CorName]] <- as.numeric(scale(Data[[CorName]]))
      }
      if (ResultName %in% names(Data)) {
        y <- Data[[ResultName]]
        if (is.character(y) || is.factor(y)) {
          Data[[ResultName]] <- as.numeric(factor(y))
        }
      }

      fml_c01 <- as.formula(paste0(ResultName, "~", CorName))
      rhs2 <- unique(c(CorName, Model1Factors))
      rhs2 <- rhs2[rhs2 != ResultName]
      fml_c02 <- as.formula(paste0(ResultName, "~", paste(rhs2, collapse = "+")))
      rhs3 <- unique(c(CorName, Model2Factors))
      rhs3 <- rhs3[rhs3 != ResultName]
      fml_c03 <- as.formula(paste0(ResultName, "~", paste(rhs3, collapse = "+")))

      crude_model <- tryCatch(lm(fml_c01, data = Data), error = function(e) NULL)
      model1 <- tryCatch(lm(fml_c02, data = Data), error = function(e) NULL)
      model2 <- tryCatch(lm(fml_c03, data = Data), error = function(e) NULL)

      r1 <- pick_beta_ci_p(crude_model, CorName)
      r2 <- pick_beta_ci_p(model1, CorName)
      r3 <- pick_beta_ci_p(model2, CorName)

      colum1 <- c(CorName, "Crude Model", "Model1", "Model2")
      colum2 <- c("", as.character(r1[1]), as.character(r2[1]), as.character(r3[1]))
      colum3 <- c("", as.character(r1[2]), as.character(r2[2]), as.character(r3[2]))
      colum4 <- c("", as.character(r1[3]), as.character(r2[3]), as.character(r3[3]))
      cbind(colum1, colum2, colum3, colum4)
    }

    var_input <- var_input[var_input %in% names(data)]
    var_input <- var_input[var_input != exposure]
    rt_list <- lapply(var_input, function(x) {
      Tb_ModelGroup3_Corlm(
        ResultName = exposure,
        CorName = x,
        Data = data,
        Model1Factors = Model1Factors,
        Model2Factors = Model2Factors
      )
    })

    dual_lm <- isTRUE(bl_cfg$dual_library_lm_screen %||% TRUE)
    lm_alpha <- as.numeric(bl_cfg$lm_screen_alpha %||% 0.05)
    lm_nonneg <- isTRUE(bl_cfg$lm_screen_require_nonneg_beta %||% TRUE)
    fallback_m2 <- isTRUE(bl_cfg$fallback_single_library_model2 %||% TRUE)

    .lm_row_ok <- function(beta, p) {
      if (!is.finite(beta) || !is.finite(p)) return(FALSE)
      if (p >= lm_alpha) return(FALSE)
      if (lm_nonneg && beta < 0) return(FALSE)
      TRUE
    }

    sig_m1 <- character(0)
    sig_m2 <- character(0)
    sig_from_lm <- character(0)
    if (length(rt_list) > 0L) {
      for (i in seq_along(rt_list)) {
        list_value <- rt_list[[i]]
        rn <- list_value[, 1]
        vn <- as.character(list_value[1, 1])
        i_m1 <- match("Model1", rn)
        i_m2 <- match("Model2", rn)
        if (is.na(i_m2)) i_m2 <- nrow(list_value)
        beta2 <- suppressWarnings(as.numeric(list_value[i_m2, 2]))
        p2 <- suppressWarnings(as.numeric(list_value[i_m2, 4]))
        ok2 <- .lm_row_ok(beta2, p2)
        ok1 <- FALSE
        if (!is.na(i_m1) && i_m1 >= 1L && i_m1 <= nrow(list_value)) {
          beta1 <- suppressWarnings(as.numeric(list_value[i_m1, 2]))
          p1 <- suppressWarnings(as.numeric(list_value[i_m1, 4]))
          ok1 <- .lm_row_ok(beta1, p1)
        }
        if (ok1) sig_m1 <- c(sig_m1, vn)
        if (ok2) sig_m2 <- c(sig_m2, vn)
        if (dual_lm) {
          if (ok1 && ok2) sig_from_lm <- c(sig_from_lm, vn)
        } else if (ok2) {
          sig_from_lm <- c(sig_from_lm, vn)
        }
      }

      rt <- do.call(rbind, rt_list)
      rt <- data.frame(rt, stringsAsFactors = FALSE)
      colnames(rt) <- c("variable", "β per 1-SD", "95% CI", "P value")
      beta_col <- "β per 1-SD"
      beta_num <- suppressWarnings(as.numeric(rt[[beta_col]]))
      rt[[beta_col]] <- ifelse(
        is.na(beta_num) | !nzchar(as.character(rt[[beta_col]])),
        as.character(rt[[beta_col]]),
        formatC(round(beta_num, 3), format = "f", digits = 3)
      )
      p_chr <- as.character(rt[["P value"]])
      p_num <- suppressWarnings(as.numeric(p_chr))
      rt[["P value"]] <- ifelse(
        !nzchar(p_chr) | is.na(p_num),
        p_chr,
        ifelse(p_num < 0.001, "< 0.001", formatC(round(p_num, 3), format = "f", digits = 3))
      )
      # 仅暂存；中介门控通过后再导出（门控失败则关联表也不要）
      ctx$results$mediation_incidence_correlation_lm_rt <- rt
    }

    if (dual_lm) {
      ctx$results$mediation_incidence_lm_sig_model1_only <- unique(intersect(sig_m1, names(data)))
      ctx$results$mediation_incidence_lm_sig_model2_only <- unique(intersect(sig_m2, names(data)))
      mediators <- unique(intersect(sig_from_lm, names(data)))
      if (length(mediators) == 0L && fallback_m2) {
        mediators <- unique(intersect(sig_m2, names(data)))
        cli::cli_alert_warning(
          "双库 LM 无交集（Model1∩Model2），已回退为仅 Model2 显著集（{length(mediators)} 个）"
        )
      } else {
        beta_rule_txt <- if (lm_nonneg) ">=0" else "任意"
        cli::cli_alert_info(
          "双库 LM 交集（Model1 与 Model2 均 beta{beta_rule_txt} 且 P<{lm_alpha}）: {length(mediators)} 个中介候选"
        )
      }
    } else {
      mediators <- unique(intersect(sig_from_lm, names(data)))
      cli::cli_alert_info("Auto-selected {length(mediators)} mediators from lm screening (Model2 only)")
    }

    if (length(mediators) > 0L) {
      list_path <- file.path(ctx$output_dir, "list_value.txt")
      writeLines(mediators, list_path)
    }
  }

  if (is.null(exposure))
  if (is.null(exposure)) stop("Please specify 'exposure' (independent variable)")
  if (is.null(mediators) || length(mediators) == 0) {
    cli::cli_alert_warning("No mediators available. Skipping mediation analysis.")
    .mi02_unlink_mediation_exports(ctx)
    return(ctx)
  }


  outcome <- outcome %||% bl_cfg$outcome %||% cfg$incidence$outcome_var %||% cfg$data$outcome_column %||% "Disease"

  for (v in c(exposure, outcome)) {
    if (!v %in% names(data)) {
      stop(paste0("Variable '", v, "' not found in data."))
    }
  }

  cli::cli_h2("Mediation Analysis for Incidence Outcome (Logistic → OR)")
  cli::cli_alert_info("Outcome (Y): {outcome}")

  mediators <- intersect(mediators, names(data))
  mediators <- mediators[sapply(mediators, function(m) is.numeric(data[[m]]) && !is.factor(data[[m]]))]
  if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
    drop_comp <- intersect(mediators, pipeline_mediation_lab_exclude_vars(cfg, names(data)))
    if (length(drop_comp)) {
      cli::cli_alert_info("中介候选已剔除指标组分/复合指标: {paste(drop_comp, collapse = ', ')}")
      mediators <- setdiff(mediators, drop_comp)
    }
  }
  if (exists("pipeline_mediation_filter_mediators", mode = "function")) {
    mediators <- pipeline_mediation_filter_mediators(
      mediators, cfg, data_cols = names(data), label = "中介"
    )
  }
  if (length(mediators) == 0) {
    # 该指标数据筛后无可用数值中介（组分/复合指标已剔除、或池中候选全被排除）。
    # 中介为下游可选分析，直接中断会把整指标打成 failed；此处降级为跳过并告警。
    cli::cli_alert_warning(
      "mediation_incidence: 筛选后无有效数值中介变量，跳过该指标中介分析（不阻断主分析）。"
    )
    return(ctx)
  }

  covariates <- intersect(covariates, names(data))
  if (exists("pipeline_mediation_drop_mediators_from_covariates", mode = "function")) {
    covariates <- pipeline_mediation_drop_mediators_from_covariates(
      covariates, mediators, label = "mediation_incidence"
    )
  } else {
    covariates <- setdiff(covariates, mediators)
  }

  cli::cli_alert_info("Exposure (X): {exposure}")
  cli::cli_alert_info("Mediators (M): {length(mediators)} variables")
  if (length(covariates) > 0) {
    cli::cli_alert_info("Covariates: {paste(covariates, collapse = ', ')}")
  }
  cli::cli_alert_info("Bootstrap iterations: {bootstrap_iter}")
  cli::cli_alert_info("Standardize mediator: {standardize_mediator}")

  run_single_mediation_incidence <- function(med_var, dat, B = 100, adj = NULL, use_z = FALSE) {
    needed_vars <- unique(c(outcome, exposure, med_var, adj))
    needed_vars <- needed_vars[nzchar(as.character(needed_vars))]
    model_data <- as.data.frame(dat)[, needed_vars, drop = FALSE]
    model_data <- stats::na.omit(model_data)

    if (nrow(model_data) < 20) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_OR = NA_character_,
        Mediator_outcome_OR = NA_character_,
        DirectEffect_OR = NA_character_,
        IndirectEffect_OR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }

    # 必须在 na.omit 之后算 z，并写入 model_data（勿只写在全表 dat 上再丢列）
    if (isTRUE(use_z)) {
      model_data$.M_z <- as.numeric(scale(model_data[[med_var]]))
      med_in_model <- ".M_z"
    } else {
      med_in_model <- med_var
    }
    formula_a <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste(med_in_model, "~", exposure))
    } else {
      as.formula(paste(med_in_model, "~", exposure, "+", paste(adj, collapse = " + ")))
    }
    
    model_a <- tryCatch(lm(formula_a, data = model_data), error = function(e) NULL)
    if (is.null(model_a)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_OR = NA_character_,
        Mediator_outcome_OR = NA_character_,
        DirectEffect_OR = NA_character_,
        IndirectEffect_OR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_a <- summary(model_a)
    coef_a <- sum_a$coefficients[exposure, "Estimate"]
    se_a <- sum_a$coefficients[exposure, "Std. Error"]
    p_a <- sum_a$coefficients[exposure, "Pr(>|t|)"]
    
    formula_full <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste(outcome, "~", exposure, "+", med_in_model))
    } else {
      as.formula(paste(outcome, "~", exposure, "+", med_in_model, "+", paste(adj, collapse = " + ")))
    }
    
    model_full <- tryCatch(glm(formula_full, data = model_data, family = binomial()), error = function(e) NULL)
    if (is.null(model_full)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_OR = NA_character_,
        Mediator_outcome_OR = NA_character_,
        DirectEffect_OR = NA_character_,
        IndirectEffect_OR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_full <- summary(model_full)
    coef_c_prime <- sum_full$coefficients[exposure, "Estimate"]
    se_c_prime <- sum_full$coefficients[exposure, "Std. Error"]
    p_c_prime <- sum_full$coefficients[exposure, "Pr(>|z|)"]
    coef_b <- sum_full$coefficients[med_in_model, "Estimate"]
    se_b <- sum_full$coefficients[med_in_model, "Std. Error"]
    p_b <- sum_full$coefficients[med_in_model, "Pr(>|z|)"]
    
    formula_total <- if (is.null(adj) || length(adj) == 0) {
      as.formula(paste(outcome, "~", exposure))
    } else {
      as.formula(paste(outcome, "~", exposure, "+", paste(adj, collapse = " + ")))
    }
    
    model_total <- tryCatch(glm(formula_total, data = model_data, family = binomial()), error = function(e) NULL)
    if (is.null(model_total)) {
      return(data.frame(
        Mediator = med_var,
        TotalEffect_OR = NA_character_,
        Mediator_outcome_OR = NA_character_,
        DirectEffect_OR = NA_character_,
        IndirectEffect_OR = NA_character_,
        Path_a_Beta = NA_character_,
        Path_b_Beta = NA_character_,
        Prop_Med_Pct = NA_character_,
        Prop_Med_num = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    
    sum_total <- summary(model_total)
    coef_c <- sum_total$coefficients[exposure, "Estimate"]
    se_c <- sum_total$coefficients[exposure, "Std. Error"]
    p_c <- sum_total$coefficients[exposure, "Pr(>|z|)"]
    
    dat_temp <- model_data
    dat_temp$.M_z <- as.numeric(scale(dat_temp[[med_var]]))
    model_med_total <- tryCatch(glm(as.formula(paste(outcome, "~ .M_z")), data = dat_temp, family = binomial()), error = function(e) NULL)
    
    if (is.null(model_med_total)) {
      coef_med_total <- NA
      se_med_total <- NA
      p_med_total <- NA
    } else {
      sum_med_total <- summary(model_med_total)
      coef_med_total <- sum_med_total$coefficients[2, "Estimate"]
      se_med_total <- sum_med_total$coefficients[2, "Std. Error"]
      p_med_total <- sum_med_total$coefficients[2, "Pr(>|z|)"]
    }
    
    if (!is.null(seed)) set.seed(seed)
    
    pm_boot <- tryCatch({
      replicate(B, {
        idx <- sample(nrow(model_data), replace = TRUE)
        db <- model_data[idx, ]
        if (use_z) db$.M_z <- as.numeric(scale(db[[med_var]]))
        ca <- tryCatch(coef(lm(formula_a, data = db))[exposure], error = function(e) NA)
        mf <- tryCatch(glm(formula_full, data = db, family = binomial()), error = function(e) NULL)
        cb <- if (!is.null(mf)) tryCatch(coef(mf)[med_in_model], error = function(e) NA) else NA
        cc <- tryCatch(coef(glm(formula_total, data = db, family = binomial()))[exposure], error = function(e) NA)
        if (any(is.na(c(ca, cb, cc))) || abs(cc) < 1e-10) return(NA)
        (ca * cb) / cc
      })
    }, error = function(e) rep(NA, B))
    
    pm_ci <- tryCatch(quantile(pm_boot, c(0.025, 0.975), na.rm = TRUE), error = function(e) c(NA, NA))
    
    se_ab <- sqrt(coef_a^2 * se_b^2 + coef_b^2 * se_a^2)
    p_ab <- 2 * (1 - pnorm(abs((coef_a * coef_b) / se_ab)))
    
    prop_med_num <- if (!is.na(coef_c) && abs(coef_c) > 1e-10) {
      round(((coef_a * coef_b) / coef_c) * 100, 2)
    } else {
      NA_real_
    }
    
    .mi02_fmt_p <- function(p) {
      if (exists("pub_format_p", mode = "function")) return(pub_format_p(p))
      pn <- suppressWarnings(as.numeric(p)[1L])
      if (!is.finite(pn)) return("")
      if (pn < 0.001) return("< 0.001")
      formatC(round(pn, 3), format = "f", digits = 3)
    }

    total_or <- paste0(
      round(exp(coef_c), 3),
      " [", round(exp(coef_c - 1.96 * se_c), 3),
      "-", round(exp(coef_c + 1.96 * se_c), 3), "] ",
      .mi02_fmt_p(p_c)
    )
    
    med_outcome_or <- if (!is.na(coef_med_total)) {
      paste0(
        round(exp(coef_med_total), 3),
        " [", round(exp(coef_med_total - 1.96 * se_med_total), 3),
        "-", round(exp(coef_med_total + 1.96 * se_med_total), 3), "] ",
        .mi02_fmt_p(p_med_total)
      )
    } else {
      NA_character_
    }
    
    direct_or <- paste0(
      round(exp(coef_c_prime), 3),
      " [", round(exp(coef_c_prime - 1.96 * se_c_prime), 3),
      "-", round(exp(coef_c_prime + 1.96 * se_c_prime), 3), "] ",
      .mi02_fmt_p(p_c_prime)
    )
    
    indirect_or <- paste0(
      round(exp(coef_a * coef_b), 3),
      " [", round(exp((coef_a * coef_b) - 1.96 * se_ab), 3),
      "-", round(exp((coef_a * coef_b) + 1.96 * se_ab), 3), "] ",
      .mi02_fmt_p(p_ab)
    )
    
    path_a_str <- paste0(
      round(coef_a, 3),
      " [", round(coef_a - 1.96 * se_a, 3),
      ", ", round(coef_a + 1.96 * se_a, 3), "] ",
      .mi02_fmt_p(p_a)
    )
    
    path_b_str <- paste0(
      round(coef_b, 3),
      " [", round(coef_b - 1.96 * se_b, 3),
      ", ", round(coef_b + 1.96 * se_b, 3), "] ",
      .mi02_fmt_p(p_b),
      if (use_z) " (per 1-SD M)" else ""
    )
    
    prop_med <- .mediation_format_prop_med_table(prop_med_num)
    
    data.frame(
      Mediator            = med_var,
      TotalEffect_OR      = total_or,
      Mediator_outcome_OR = med_outcome_or,
      DirectEffect_OR     = direct_or,
      IndirectEffect_OR   = indirect_or,
      Path_a_Beta         = path_a_str,
      Path_b_Beta         = path_b_str,
      Prop_Med_Pct        = prop_med,
      Prop_Med_num        = prop_med_num,
      # 绘图用原始数值列（以 .raw_ 开头，导出表时自动剥离）
      .raw_coef_a    = coef_a,
      .raw_p_a       = p_a,
      .raw_coef_b    = coef_b,
      .raw_p_b       = p_b,
      .raw_eff_total = exp(coef_c),    # total OR
      .raw_p_total   = p_c,
      .raw_eff_direct = exp(coef_c_prime),  # direct OR (c') — 路径图底边用此值
      .raw_p_direct   = p_c_prime,
      .raw_prop_lo   = if (length(pm_ci) == 2L && !any(is.na(pm_ci))) pm_ci[1L] else NA_real_,
      .raw_prop_hi   = if (length(pm_ci) == 2L && !any(is.na(pm_ci))) pm_ci[2L] else NA_real_,
      .raw_ci_a_lo   = coef_a - 1.96 * se_a,
      .raw_ci_a_hi   = coef_a + 1.96 * se_a,
      .raw_ci_b_lo   = coef_b - 1.96 * se_b,
      .raw_ci_b_hi   = coef_b + 1.96 * se_b,
      .raw_ci_tot_lo = exp(coef_c - 1.96 * se_c),
      .raw_ci_tot_hi = exp(coef_c + 1.96 * se_c),
      .raw_ci_dir_lo = exp(coef_c_prime - 1.96 * se_c_prime),
      .raw_ci_dir_hi = exp(coef_c_prime + 1.96 * se_c_prime),
      .raw_p_indirect = p_ab,
      stringsAsFactors = FALSE
    )
  }

  .mi02_mediation_paths_significant <- function(one_row, alpha) {
    if (is.null(one_row) || nrow(one_row) != 1L) return(FALSE)
    pa <- suppressWarnings(as.numeric(one_row$.raw_p_a[1L]))
    pb <- suppressWarnings(as.numeric(one_row$.raw_p_b[1L]))
    pi <- if (".raw_p_indirect" %in% names(one_row)) {
      suppressWarnings(as.numeric(one_row$.raw_p_indirect[1L]))
    } else {
      NA_real_
    }
    ok <- is.finite(pa) && is.finite(pb) && is.finite(pi)
    if (!ok) return(FALSE)
    pa < alpha && pb < alpha && pi < alpha
  }

  auto_cov_search <- if (exists("pipeline_mediation_auto_covariate_search", mode = "function")) {
    pipeline_mediation_auto_covariate_search(cfg, bl_cfg)
  } else {
    FALSE
  }
  path_alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  search_b <- as.integer(bl_cfg$covariate_search_bootstrap_iter %||% min(100L, bootstrap_iter))
  max_k <- as.integer(bl_cfg$covariate_search_max_size %||% 5L)
  max_comb <- as.integer(bl_cfg$covariate_search_max_combinations %||% 300L)

  if (auto_cov_search && length(mediators) > 0L) {
    pool_search <- bl_cfg$covariate_search_pool %||% ctx$results$Model2Factors %||% character(0)
    pool_search <- unique(as.character(pool_search))
    pool_search <- intersect(pool_search, names(data))
    excl <- unique(c(exposure, outcome, mediators))
    pool_search <- setdiff(pool_search, excl)
    pool_search <- pool_search[vapply(pool_search, function(v) {
      xv <- data[[v]]
      is.numeric(xv) || is.logical(xv) || is.factor(xv)
    }, logical(1L))]

    .try_adj <- function(adj_vec) {
      adj_vec <- unique(as.character(adj_vec))
      adj_vec <- adj_vec[nzchar(adj_vec)]
      adj_vec <- intersect(adj_vec, names(data))
      for (m in mediators) {
        adj_m <- setdiff(adj_vec, m)
        row1 <- run_single_mediation_incidence(m, data, B = search_b, adj = adj_m, use_z = standardize_mediator)
        if (.mi02_mediation_paths_significant(row1, path_alpha)) {
          return(list(ok = TRUE, adj = adj_m, hit = m))
        }
      }
      list(ok = FALSE, adj = NULL, hit = NA_character_)
    }

    tries <- 0L
    found <- NULL
    nk <- min(max_k, length(pool_search))
    cand0 <- intersect(covariates, names(data))

    tries <- tries + 1L
    r_none <- .try_adj(character(0))
    if (isTRUE(r_none$ok)) {
      found <- r_none
      cli::cli_alert_success(
        "自动协变量搜索：无协变量调整时已有中介 [{r_none$hit}] 满足 path a / b / indirect 均 p < {path_alpha}"
      )
    }
    if (is.null(found) && length(cand0) > 0L) {
      tries <- tries + 1L
      r0 <- .try_adj(cand0)
      if (isTRUE(r0$ok)) {
        found <- r0
        cli::cli_alert_success(
          "自动协变量搜索：沿用 config 中 covariates 已有中介 [{r0$hit}] 满足 path a / b / indirect 均 p < {path_alpha}"
        )
      }
    }
    if (is.null(found) && length(pool_search) > 0L) {
      for (k in seq.int(1L, nk)) {
        if (k > length(pool_search)) break
        combs <- if (k == 1L) {
          lapply(pool_search, function(x) x)
        } else {
          utils::combn(pool_search, k, simplify = FALSE)
        }
        for (adj in combs) {
          tries <- tries + 1L
          if (tries > max_comb) break
          r <- .try_adj(unlist(adj, use.names = FALSE))
          if (isTRUE(r$ok)) {
            found <- r
            cli::cli_alert_success(
              "自动协变量搜索：已选 {length(r$adj)} 个协变量，中介 [{r$hit}] path a/b/indirect 均 p < {path_alpha}（累计尝试 {tries}）"
            )
            cli::cli_alert_info("选用调整项: {paste(r$adj, collapse = ', ')}")
            break
          }
        }
        if (!is.null(found)) break
        if (tries > max_comb) break
      }
    }
    if (!is.null(found)) {
      covariates <- found$adj
      if (exists("pipeline_mediation_drop_mediators_from_covariates", mode = "function")) {
        covariates <- pipeline_mediation_drop_mediators_from_covariates(
          covariates, mediators, label = "mediation_incidence"
        )
      } else {
        covariates <- setdiff(covariates, mediators)
      }
      ctx$results$mediation_incidence_auto_covariates <- found$adj
      ctx$results$mediation_incidence_auto_covariate_hit_mediator <- found$hit
      ctx$results$mediation_incidence_auto_covariate_search_tries <- tries
    } else {
      cli::cli_alert_warning(
        "自动协变量搜索：在至多 {max_k} 个协变量、{max_comb} 次尝试内未找到使交集中任一中介 path a/b/indirect 均 p<{path_alpha} 的调整集；沿用原 covariates"
      )
      ctx$results$mediation_incidence_auto_covariates <- NULL
    }
  }

  cli::cli_alert_info("Running mediation analysis for {length(mediators)} mediator(s)...")

  results_list <- lapply(seq_along(mediators), function(i) {
    med_var <- mediators[i]
    cli::cli_alert_info("Processing {i}/{length(mediators)}: {med_var}")
    adj_i <- setdiff(covariates, med_var)
    run_single_mediation_incidence(med_var, data, B = bootstrap_iter, adj = adj_i, use_z = standardize_mediator)
  })

  final_table <- dplyr::bind_rows(results_list)
  final_table <- final_table[order(-final_table$Prop_Med_num, na.last = TRUE), ]

  index_name <- cfg$logistic$index_var %||% exposure

  # 路径图指定中介置顶，保证表首行与 Figure S3 同一中介
  pin_med <- as.character((cfg$mediation_incidence %||% list())$best_mediator %||% "")[1L]
  if (nzchar(pin_med) && pin_med %in% final_table$Mediator) {
    final_table <- rbind(
      final_table[final_table$Mediator == pin_med, , drop = FALSE],
      final_table[final_table$Mediator != pin_med, , drop = FALSE]
    )
  }

  raw_cols  <- grep("^\\.raw_", names(final_table), value = TRUE)
  disp_cols <- setdiff(names(final_table), c("Prop_Med_num", raw_cols))
  display_table <- final_table[, disp_cols, drop = FALSE]
  colnames(display_table) <- c(
    "Mediator", "Total Effect (Index)", "Mediator-outcome OR(1-SD)", "Direct Effect",
    "Indirect Effect", "Path a (Beta)", "Path b (Beta)", "Proportion mediated"
  )
  # 未标准化时表头不写 (1-SD)
  if (!isTRUE(standardize_mediator)) {
    colnames(display_table)[colnames(display_table) == "Mediator-outcome OR(1-SD)"] <-
      "Mediator-outcome OR"
  }

  # 规则：最佳中介 Proportion mediated + Direct Effect 均显著才导出；否则不出表/图
  path_alpha_inc <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  if (!.mi02_mediation_should_export(final_table, cfg, bl_cfg)) {
    ctx$results$mediation_incidence <- final_table
    ctx$results$mediation_incidence_ns_skipped <- TRUE
    reason <- .mi02_mediation_skip_reason(final_table, cfg, bl_cfg)
    cli::cli_alert_warning(
      "mediation_incidence: {reason}，按规则不导出中介表、路径图与实验室关联表。"
    )
    .mi02_unlink_mediation_exports(ctx)
    return(ctx)
  }

  .mi02_export_lab_association_table(
    ctx, ctx$results$mediation_incidence_correlation_lm_rt, exposure
  )

  med_pub <- pub_paths(
    ctx, ctx$output_dir_tables, "supp_table",
    paste0("Mediation analysis of ", gsub("_", " ", index_name)),
    "xlsx"
  )

  ctx$results$mediation_incidence <- final_table

  tryCatch({
    fn_med <- if (exists("pipeline_mediation_table_footnotes", mode = "function")) {
      pipeline_mediation_table_footnotes(standardize_mediator)
    } else {
      "A negative proportion mediated indicates a suppression (masking) effect, not a mediated fraction."
    }
    export_sci_table(
      display_table, med_pub$filepath, title = med_pub$title,
      table_footnotes = fn_med
    )
    cli::cli_alert_success("Table saved: {.file {basename(med_pub$filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("Excel export failed: {e$message}")
  })

  cli::cli_alert_success("Mediation analysis completed: {length(mediators)} mediator(s) analyzed")

  diagram_enable <- isTRUE(bl_cfg$diagram_enable %||% TRUE)
  if (diagram_enable && nrow(final_table) > 0L) {
    best_row <- .mi02_mediation_pick_best_row(final_table, cfg, bl_cfg)
    cli::cli_alert_info("中介路径图：最佳中介 {best_row$Mediator[1L]}")
    if (isTRUE((cfg$dual_db %||% list())$enable) &&
        exists("dual_db_save_preferred_mediator", mode = "function")) {
      root_m <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
      dual_db_save_preferred_mediator(root_m, cfg, best_row$Mediator[1L])
    }

    sel_colors <- .mi02_palettes[[sample(names(.mi02_palettes), 1L)]]
    outcome_diag_label <- .mediation_outcome_diag_label(cfg)
    fig_caption <- paste0(
      "Mediation path diagram of ", exposure, " and ", outcome_diag_label
    )
    # 发病双库发表规范：中介路径图 = Figure S3（两库统一）
    fig_kind <- as.character((cfg$mediation_incidence %||% list())$figure_kind %||% "supp_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "supp_figure"
    fig_name <- pub_figure_file(ctx, fig_kind, fig_caption)
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
    diag_path <- file.path(fig_dir, fig_name)

    p_diag <- tryCatch(
      .mi02_draw_mediation_path_diagram(
        exposure_label  = exposure,
        mediator_label  = best_row$Mediator[1L],
        outcome_label   = outcome_diag_label,
        coef_a          = if (".raw_coef_a"    %in% names(best_row)) best_row$.raw_coef_a[1L]    else NA_real_,
        p_a             = if (".raw_p_a"        %in% names(best_row)) best_row$.raw_p_a[1L]        else NA_real_,
        coef_b          = if (".raw_coef_b"    %in% names(best_row)) best_row$.raw_coef_b[1L]    else NA_real_,
        p_b             = if (".raw_p_b"        %in% names(best_row)) best_row$.raw_p_b[1L]        else NA_real_,
        # 底边 = Direct Effect (c')，与表「Direct Effect」列一致（勿用 Total Effect）
        effect_total    = if (".raw_eff_direct" %in% names(best_row)) best_row$.raw_eff_direct[1L] else if (".raw_eff_total" %in% names(best_row)) best_row$.raw_eff_total[1L] else NA_real_,
        p_total         = if (".raw_p_direct"   %in% names(best_row)) best_row$.raw_p_direct[1L]   else if (".raw_p_total" %in% names(best_row)) best_row$.raw_p_total[1L] else NA_real_,
        prop_pct        = best_row$Prop_Med_num[1L] %||% NA_real_,
        prop_lo_pct     = NA_real_,
        prop_hi_pct     = NA_real_,
        colors          = sel_colors,
        ci_a_lo         = if (".raw_ci_a_lo"    %in% names(best_row)) best_row$.raw_ci_a_lo[1L]    else NA_real_,
        ci_a_hi         = if (".raw_ci_a_hi"    %in% names(best_row)) best_row$.raw_ci_a_hi[1L]    else NA_real_,
        ci_b_lo         = if (".raw_ci_b_lo"    %in% names(best_row)) best_row$.raw_ci_b_lo[1L]    else NA_real_,
        ci_b_hi         = if (".raw_ci_b_hi"    %in% names(best_row)) best_row$.raw_ci_b_hi[1L]    else NA_real_,
        ci_tot_lo       = if (".raw_ci_dir_lo"  %in% names(best_row)) best_row$.raw_ci_dir_lo[1L]  else if (".raw_ci_tot_lo" %in% names(best_row)) best_row$.raw_ci_tot_lo[1L] else NA_real_,
        ci_tot_hi       = if (".raw_ci_dir_hi"  %in% names(best_row)) best_row$.raw_ci_dir_hi[1L]  else if (".raw_ci_tot_hi" %in% names(best_row)) best_row$.raw_ci_tot_hi[1L] else NA_real_,
        font_family     = plot_font_from_config(cfg),
        output_path     = diag_path
      ),
      error = function(e) {
        cli::cli_alert_warning("中介路径图绘制失败: {e$message}")
        NULL
      }
    )

    if (!is.null(p_diag) && file.exists(diag_path)) {
      mirror_pub_output_to_root(ctx, diag_path)
      ctx$results$mediation_incidence_diagram      <- p_diag
      ctx$results$mediation_incidence_diagram_path <- diag_path
    }
  }

  ctx
}

register_block("mediation_incidence", block_mediation_incidence,
               "Mediation analysis (incidence): exposure -> mediators -> disease (Logistic OR)")
