###############################################################################
#  mediation_nhanes_weighted — NHANES 加权发病中介：
#    ① 加权 LM 相关性（暴露 ~ 血检指标，Crude/Model1/Model2）
#    ② 从显著血检指标中做加权中介（svyglm + PSU cluster bootstrap）
#
#  register_block: "mediation_nhanes_weighted"
#  前置: obj（nhanes_design）；multicollinearity_nhanes_final（Model1/2Factors）
#
#  config$mediation_nhanes_weighted:
#    exposure, lab_indicator_vars, mediators, covariates,
#    bootstrap_iter, dual_library_lm_screen, lm_screen_alpha,
#    lm_screen_require_nonneg_beta, auto_covariate_search, diagram_enable
###############################################################################

block_mediation_nhanes_weighted <- function(ctx, ...) {
  if (!.is_nhanes_db(ctx$config)) {
    cli::cli_alert_info("mediation_nhanes_weighted: 非 NHANES 数据库，跳过。")
    return(ctx)
  }

  common_path <- file.path(getwd(), "Blocks/20_mediation/00mediation_common.R")
  if (file.exists(common_path)) source(common_path, local = FALSE)

  lcfg_path <- file.path(getwd(), "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")
  if (file.exists(lcfg_path) && !exists(".lnw00_resolve_models", mode = "function")) {
    source(lcfg_path, local = FALSE)
  }

  for (pkg in c("survey", "dplyr")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      cli::cli_alert_warning("mediation_nhanes_weighted: 需要 {pkg}，跳过。")
      return(ctx)
    }
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(dplyr, warn.conflicts = FALSE)
  })
  options(survey.lonely.psu = "adjust")

  cfg <- ctx$config
  bl_cfg <- cfg$mediation_nhanes_weighted %||% list()
  proj_cfg <- cfg$project %||% list()
  nhanes_cfg <- cfg$nhanes %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  cluster_col <- nhanes_cfg$survey_cluster %||% "SDMVPSU"

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    cli::cli_alert_warning("mediation_nhanes_weighted: nhanes_design 为空，请先运行 obj。")
    return(ctx)
  }

  exposure <- bl_cfg$exposure %||%
    (cfg$incidence %||% list())$index_var %||%
    (cfg$logistic %||% list())$index_var %||% "BMI"
  index_var <- exposure

  if (!exposure %in% names(design$variables)) {
    cli::cli_alert_warning("mediation_nhanes_weighted: 暴露 '{exposure}' 不在 design 中，跳过。")
    return(ctx)
  }

  # 分类暴露（如 Periodontitis 0–3 factor）：LM/路径按数值等级跑，勿用 as.numeric(factor) 变成 1..k
  xv_exp <- design$variables[[exposure]]
  if (is.factor(xv_exp) || is.character(xv_exp)) {
    xn_exp <- suppressWarnings(as.numeric(as.character(xv_exp)))
    if (any(is.finite(xn_exp))) {
      design$variables[[exposure]] <- xn_exp
      cli::cli_alert_info("mediation_nhanes_weighted: 暴露 {exposure} 由分类转为数值等级用于中介路径")
    }
  }

  design <- stats::update(design,
    Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], case_label = disease_lbl)
  )
  outcome <- bl_cfg$outcome %||% "Disease_Group"

  models <- .lnw00_resolve_models(ctx, cfg, bl_cfg, design, index_var)
  M1_vars <- models$M1
  M2_vars <- models$M2
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    merged <- pipeline_merge_force_covariates(M1_vars, M2_vars, names(design$variables), cfg)
    M1_vars <- merged$M1
    M2_vars <- merged$M2
  }
  # Model1 可空：中介路径允许无协变量（crude）；LM 表 Model1 列将为空或仅 Age
  if (!length(M1_vars)) {
    cli::cli_alert_info("mediation_nhanes_weighted: Model1 为空，LM/中介按无（或极少）协变量运行。")
  }

  mediators <- bl_cfg$mediators
  # 路径默认 crude；path_use_covariates=TRUE 时用锁定 Model2 / 配置 covariates
  covariates <- if (exists("pipeline_mediation_resolve_path_covariates", mode = "function")) {
    pipeline_mediation_resolve_path_covariates(cfg, bl_cfg, names(design$variables), ctx = ctx)
  } else {
    character(0)
  }
  if (length(covariates)) {
    src <- if (exists("pipeline_mediation_covariate_source", mode = "function")) {
      pipeline_mediation_covariate_source(cfg, bl_cfg)
    } else {
      "table2"
    }
    cli::cli_alert_info(
      "mediation_nhanes_weighted path covariates ({length(covariates)}, source={src}): {paste(covariates, collapse = ', ')}"
    )
  } else {
    cli::cli_alert_info("mediation_nhanes_weighted: path_use_covariates 未开或协变量为空 → crude 总效应")
  }
  bootstrap_iter <- as.integer(bl_cfg$bootstrap_iter %||% 100L)[1L]
  standardize_mediator <- isTRUE(bl_cfg$standardize_mediator %||% TRUE)
  seed <- bl_cfg$seed %||% cfg$splitting$seed %||% 1234

  .mnw01_svy_pick <- function(fit, var) {
    if (is.null(fit)) return(list(beta = NA_real_, ci = NA_character_, p = NA_real_, se = NA_real_))
    sm <- summary(fit)
    cf <- sm$coefficients
    rn <- rownames(cf)
    if (is.null(rn)) return(list(beta = NA_real_, ci = NA_character_, p = NA_real_, se = NA_real_))
    hit <- which(rn == var)
    if (!length(hit)) hit <- grep(paste0("^", var, "$"), gsub("`", "", rn))
    if (!length(hit)) return(list(beta = NA_real_, ci = NA_character_, p = NA_real_, se = NA_real_))
    i <- hit[1L]
    beta <- as.numeric(cf[i, 1])
    se <- as.numeric(cf[i, 2])
    pcol <- if (ncol(cf) >= 4L) 4L else ncol(cf)
    pval <- as.numeric(cf[i, pcol])
    lo <- beta - 1.96 * se
    hi <- beta + 1.96 * se
    ci <- paste0("(", round(lo, 3), ",", round(hi, 3), ")")
    list(beta = beta, ci = ci, p = pval, se = se)
  }

  .mnw01_cor_row <- function(lab_var, M1, M2) {
    rhs_crude <- lab_var
    rhs_m1 <- paste(unique(c(lab_var, setdiff(M1, lab_var))), collapse = "+")
    rhs_m2 <- paste(unique(c(lab_var, setdiff(M2, lab_var))), collapse = "+")
    f_crude <- stats::as.formula(paste(exposure, "~", rhs_crude))
    f_m1 <- stats::as.formula(paste(exposure, "~", rhs_m1))
    f_m2 <- stats::as.formula(paste(exposure, "~", rhs_m2))
    fit_crude <- tryCatch(survey::svyglm(f_crude, design = design, family = gaussian()), error = function(e) NULL)
    fit_m1 <- tryCatch(survey::svyglm(f_m1, design = design, family = gaussian()), error = function(e) NULL)
    fit_m2 <- tryCatch(survey::svyglm(f_m2, design = design, family = gaussian()), error = function(e) NULL)
    r1 <- .mnw01_svy_pick(fit_crude, lab_var)
    r2 <- .mnw01_svy_pick(fit_m1, lab_var)
    r3 <- .mnw01_svy_pick(fit_m2, lab_var)
    # P/β 先存原始数值字符串，供下游筛选用 as.numeric；发表格式在导出前再统一美化
    # （若此处先写成 "< 0.001"，筛选用 as.numeric 会变 NA，导致中介被误跳过）
    .fmt_beta_raw <- function(b) {
      if (!is.finite(b)) return("")
      formatC(b, format = "f", digits = 8, drop0trailing = TRUE)
    }
    .fmt_p_raw <- function(p) {
      if (!is.finite(p)) return("")
      formatC(p, format = "f", digits = 10, drop0trailing = TRUE)
    }
    mat <- cbind(
      c(lab_var, "Crude Model", "Model1", "Model2"),
      c("", .fmt_beta_raw(r1$beta), .fmt_beta_raw(r2$beta), .fmt_beta_raw(r3$beta)),
      c("", r1$ci, r2$ci, r3$ci),
      c("", .fmt_p_raw(r1$p), .fmt_p_raw(r2$p), .fmt_p_raw(r3$p))
    )
    attr(mat, "raw") <- list(crude = r1, m1 = r2, m2 = r3)
    mat
  }

  if (is.null(mediators) || !length(mediators)) {
    lab_pool <- bl_cfg$lab_indicator_vars
    if (is.null(lab_pool) || !length(lab_pool)) {
      lab_pool <- .default_laboratory_test_vars()
    }
    # 共病 / 人体测量等非血检中介候选（课题可配 mediator_extra_vars）
    extra_med <- as.character(bl_cfg$mediator_extra_vars %||% character(0))
    extra_med <- extra_med[nzchar(extra_med)]
    lab_pool <- unique(c(as.character(lab_pool), extra_med))
    lab_pool <- unique(as.character(lab_pool))
    lab_pool <- intersect(lab_pool, names(design$variables))
    lab_pool <- setdiff(lab_pool, exposure)
    # 相关性仅筛候选：排除 Model1/Model2 协变量（如 HDL 已在调整集中则不再作候选）
    cov_excl <- unique(c(M1_vars, M2_vars, exposure, outcome_col, outcome, "Disease_Group"))
    # 排除复合指标公式组分（LCI→TC/TG/LDL/HDL 等），避免中介与暴露定义重叠
    if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
      cov_excl <- unique(c(cov_excl, pipeline_mediation_lab_exclude_vars(cfg)))
    }
    # 疾病泄漏变量不作中介（与 analysis_exclusion$disease_vars 对齐）
    dis_excl <- as.character((cfg$analysis_exclusion %||% list())$disease_vars %||% character(0))
    if (length(dis_excl)) cov_excl <- unique(c(cov_excl, dis_excl))
    lab_pool <- setdiff(lab_pool, cov_excl)

    # 二分共病（factor/character/logical）转 0/1 数值，便于 svyglm 路径
    .mnw01_coerce_binary_num <- function(des, vars) {
      for (vn in vars) {
        if (!vn %in% names(des$variables)) next
        x <- des$variables[[vn]]
        if (is.numeric(x)) next
        if (is.logical(x)) {
          des$variables[[vn]] <- as.numeric(x)
          next
        }
        xc <- as.character(x)
        ux <- unique(xc[!is.na(xc) & nzchar(xc)])
        if (length(ux) != 2L) next
        pos <- ux[tolower(ux) %in% c("yes", "y", "1", "true", "positive", "present")]
        if (!length(pos)) pos <- ux[2L]
        des$variables[[vn]] <- as.numeric(xc == pos[1L])
        cli::cli_alert_info("mediation_nhanes_weighted: 二分变量 {vn} → 0/1（1={pos[1L]}）")
      }
      des
    }
    design <- .mnw01_coerce_binary_num(design, lab_pool)

    lab_pool <- lab_pool[vapply(lab_pool, function(v) {
      is.numeric(design$variables[[v]])
    }, logical(1L))]

    if (!length(lab_pool)) {
      cli::cli_alert_warning("mediation_nhanes_weighted: 排除协变量后无可用中介候选，跳过。")
      return(ctx)
    }
    cli::cli_alert_info(
      "mediation_nhanes_weighted: 中介候选池 {length(lab_pool)} 个（血检+共病等，已排除协变量）— {paste(head(lab_pool, 8), collapse = ', ')}{if (length(lab_pool) > 8) '...' else ''}"
    )

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

    rt_list <- lapply(lab_pool, function(v) .mnw01_cor_row(v, M1_vars, M2_vars))
    sig_m1 <- character(0)
    sig_m2 <- character(0)
    sig_from_lm <- character(0)
    for (i in seq_along(rt_list)) {
      mat <- rt_list[[i]]
      vn <- as.character(mat[1, 1])
      raw <- attr(mat, "raw")
      if (is.list(raw) && length(raw)) {
        beta1 <- suppressWarnings(as.numeric(raw$m1$beta))
        p1 <- suppressWarnings(as.numeric(raw$m1$p))
        beta2 <- suppressWarnings(as.numeric(raw$m2$beta))
        p2 <- suppressWarnings(as.numeric(raw$m2$p))
      } else {
        i_m1 <- match("Model1", mat[, 1])
        i_m2 <- match("Model2", mat[, 1])
        if (is.na(i_m2)) i_m2 <- nrow(mat)
        beta2 <- suppressWarnings(as.numeric(mat[i_m2, 2]))
        p2 <- suppressWarnings(as.numeric(mat[i_m2, 4]))
        beta1 <- NA_real_
        p1 <- NA_real_
        if (!is.na(i_m1)) {
          beta1 <- suppressWarnings(as.numeric(mat[i_m1, 2]))
          p1 <- suppressWarnings(as.numeric(mat[i_m1, 4]))
        }
      }
      ok2 <- .lm_row_ok(beta2, p2)
      ok1 <- .lm_row_ok(beta1, p1)
      if (ok1) sig_m1 <- c(sig_m1, vn)
      if (ok2) sig_m2 <- c(sig_m2, vn)
      if (dual_lm) {
        if (ok1 && ok2) sig_from_lm <- c(sig_from_lm, vn)
      } else if (ok2) {
        sig_from_lm <- c(sig_from_lm, vn)
      }
    }

    if (length(rt_list)) {
      rt <- do.call(rbind, rt_list)
      rt <- data.frame(rt, stringsAsFactors = FALSE)
      colnames(rt) <- c("variable", "β value", "95% CI", "P value")
      # 统一：β 3 位小数；P 3 位，<0.001 显示为 < 0.001
      beta_num <- suppressWarnings(as.numeric(rt[["β value"]]))
      rt[["β value"]] <- ifelse(
        is.na(beta_num) | !nzchar(as.character(rt[["β value"]])),
        as.character(rt[["β value"]]),
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
      ctx$results$mediation_nhanes_correlation_lm_rt <- rt
    }

    if (dual_lm) {
      mediators <- unique(intersect(sig_from_lm, names(design$variables)))
      if (!length(mediators) && fallback_m2) {
        mediators <- unique(intersect(sig_m2, names(design$variables)))
        cli::cli_alert_warning(
          "加权 LM 无 Model1∩Model2 交集，回退 Model2 显著血检（{length(mediators)} 个）"
        )
      } else {
        beta_rule <- if (lm_nonneg) ">=0" else "任意"
        cli::cli_alert_info(
          "加权 LM 交集（Model1 与 Model2 均 beta{beta_rule} 且 P<{lm_alpha}）: {length(mediators)} 个中介候选"
        )
      }
    } else {
      mediators <- unique(intersect(sig_from_lm, names(design$variables)))
      cli::cli_alert_info("加权 LM Model2 筛选: {length(mediators)} 个中介候选")
    }
  }

  mediators <- as.character(mediators %||% character(0))
  mediators <- mediators[nzchar(mediators)]
  mediators <- intersect(mediators, names(design$variables))
  mediators <- mediators[vapply(mediators, function(m) is.numeric(design$variables[[m]]), logical(1L))]
  if (exists("pipeline_mediation_lab_exclude_vars", mode = "function")) {
    drop_comp <- intersect(mediators, pipeline_mediation_lab_exclude_vars(cfg, names(design$variables)))
    if (length(drop_comp)) {
      cli::cli_alert_info("中介候选已剔除指标组分/复合指标: {paste(drop_comp, collapse = ', ')}")
      mediators <- setdiff(mediators, drop_comp)
    }
  }
  if (exists("pipeline_mediation_filter_mediators", mode = "function")) {
    mediators <- pipeline_mediation_filter_mediators(
      mediators, cfg, data_cols = names(design$variables), label = "中介"
    )
  }

  # 配置锁定 best_mediator 时：LM 筛空也不跳过，强制纳入
  pin_med0 <- as.character(bl_cfg$best_mediator %||% "")[1L]
  if (!length(mediators) && nzchar(pin_med0) &&
      pin_med0 %in% names(design$variables) &&
      is.numeric(design$variables[[pin_med0]])) {
    mediators <- pin_med0
    cli::cli_alert_info(
      "mediation_nhanes_weighted: LM 未筛出中介，改用配置 best_mediator={pin_med0}"
    )
  }

  if (!length(mediators)) {
    cli::cli_alert_warning("mediation_nhanes_weighted: 无可用中介变量，跳过。")
    return(ctx)
  }

  covariates <- intersect(covariates, names(design$variables))

  cli::cli_h2("mediation_nhanes_weighted: 加权发病中介 (svyglm)")
  cli::cli_alert_info("Exposure: {exposure}; Outcome: {outcome}; Mediators: {length(mediators)}")

  .mnw01_cluster_boot_idx <- function(des, cl_col) {
    psu <- as.vector(des$variables[[cl_col]])
    cls <- unique(psu)
    sampled <- sample(cls, length(cls), replace = TRUE)
    unlist(lapply(sampled, function(c) which(psu == c)), use.names = FALSE)
  }

  .mnw01_run_single <- function(med_var, des, B, adj, use_z) {
    med_in_model <- med_var
    if (use_z) {
      des <- stats::update(des, .M_z = as.numeric(scale(des$variables[[med_var]])))
      med_in_model <- ".M_z"
    }

    adj <- as.character(adj %||% character(0))
    adj <- adj[nzchar(adj)]
    adj <- setdiff(intersect(adj, names(des$variables)), c(exposure, outcome, med_var))

    f_a <- if (!length(adj)) {
      stats::as.formula(paste(med_in_model, "~", exposure))
    } else {
      stats::as.formula(paste(med_in_model, "~", exposure, "+", paste(adj, collapse = " + ")))
    }
    f_full <- if (!length(adj)) {
      stats::as.formula(paste(outcome, "~", exposure, "+", med_in_model))
    } else {
      stats::as.formula(paste(outcome, "~", exposure, "+", med_in_model, "+", paste(adj, collapse = " + ")))
    }
    f_total <- if (!length(adj)) {
      stats::as.formula(paste(outcome, "~", exposure))
    } else {
      stats::as.formula(paste(outcome, "~", exposure, "+", paste(adj, collapse = " + ")))
    }

    fit_a <- tryCatch(survey::svyglm(f_a, design = des, family = gaussian()), error = function(e) NULL)
    fit_full <- tryCatch(survey::svyglm(f_full, design = des, family = quasibinomial()), error = function(e) NULL)
    fit_total <- tryCatch(survey::svyglm(f_total, design = des, family = quasibinomial()), error = function(e) NULL)
    if (is.null(fit_a) || is.null(fit_full) || is.null(fit_total)) {
      return(.mnw01_empty_row(med_var))
    }

    ra <- .mnw01_svy_pick(fit_a, exposure)
    rf <- .mnw01_svy_pick(fit_full, exposure)
    rb <- .mnw01_svy_pick(fit_full, med_in_model)
    rt <- .mnw01_svy_pick(fit_total, exposure)

    coef_a <- ra$beta; se_a <- ra$se
    coef_b <- rb$beta; se_b <- rb$se
    coef_c <- rt$beta; se_c <- rt$se
    coef_c_prime <- rf$beta; se_c_prime <- rf$se
    p_a <- ra$p; p_b <- rb$p; p_c <- rt$p; p_c_prime <- rf$p

    se_ab <- sqrt(coef_a^2 * se_b^2 + coef_b^2 * se_a^2)
    p_ab <- 2 * stats::pnorm(-abs((coef_a * coef_b) / se_ab))

    fmt_or <- function(est, se, p) {
      p_txt <- if (exists("pub_format_p", mode = "function")) {
        pub_format_p(p)
      } else {
        pn <- suppressWarnings(as.numeric(p)[1L])
        if (!is.finite(pn)) "" else if (pn < 0.001) "< 0.001" else formatC(round(pn, 3), format = "f", digits = 3)
      }
      paste0(
        round(exp(est), 3), " [",
        round(exp(est - 1.96 * se), 3), "-",
        round(exp(est + 1.96 * se), 3), "] ",
        p_txt
      )
    }
    fmt_beta <- function(est, se, p, extra = "") {
      p_txt <- if (exists("pub_format_p", mode = "function")) {
        pub_format_p(p)
      } else {
        pn <- suppressWarnings(as.numeric(p)[1L])
        if (!is.finite(pn)) "" else if (pn < 0.001) "< 0.001" else formatC(round(pn, 3), format = "f", digits = 3)
      }
      paste0(
        round(est, 3), " [", round(est - 1.96 * se, 3), ", ",
        round(est + 1.96 * se, 3), "] ",
        p_txt, extra
      )
    }

    # Mediator-outcome OR(1-SD)：结局 ~ 标准化中介（与 mediation_incidence 一致）
    des_med <- stats::update(des, .M_z = as.numeric(scale(des$variables[[med_var]])))
    fit_med_total <- tryCatch(
      survey::svyglm(stats::as.formula(paste(outcome, "~ .M_z")),
                     design = des_med, family = quasibinomial()),
      error = function(e) NULL
    )
    rm <- .mnw01_svy_pick(fit_med_total, ".M_z")
    med_outcome_or <- if (is.finite(rm$beta) && is.finite(rm$se)) {
      fmt_or(rm$beta, rm$se, rm$p)
    } else {
      NA_character_
    }

    if (!is.null(seed)) set.seed(seed)
    pm_boot <- tryCatch({
      if (!cluster_col %in% names(des$variables)) {
        rep(NA_real_, B)
      } else {
        replicate(B, {
          idx <- .mnw01_cluster_boot_idx(des, cluster_col)
          d_b <- des[idx, ]
          if (use_z) d_b <- stats::update(d_b, .M_z = as.numeric(scale(d_b$variables[[med_var]])))
          ca <- tryCatch(as.numeric(stats::coef(survey::svyglm(f_a, d_b, family = gaussian()))[exposure]), error = function(e) NA)
          mf <- tryCatch(survey::svyglm(f_full, d_b, family = quasibinomial()), error = function(e) NULL)
          cb <- if (!is.null(mf)) tryCatch(as.numeric(stats::coef(mf)[med_in_model]), error = function(e) NA) else NA
          cc <- tryCatch(as.numeric(stats::coef(survey::svyglm(f_total, d_b, family = quasibinomial()))[exposure]), error = function(e) NA)
          if (any(is.na(c(ca, cb, cc))) || abs(cc) < 1e-10) return(NA)
          (ca * cb) / cc
        })
      }
    }, error = function(e) rep(NA_real_, B))
    pm_ci <- tryCatch(stats::quantile(pm_boot, c(0.025, 0.975), na.rm = TRUE), error = function(e) c(NA, NA))

    prop_med_num <- if (is.finite(coef_c) && abs(coef_c) > 1e-10) {
      round(((coef_a * coef_b) / coef_c) * 100, 2)
    } else {
      NA_real_
    }

    prop_med <- .mediation_format_prop_med_table(prop_med_num)

    data.frame(
      Mediator = med_var,
      TotalEffect_OR = fmt_or(coef_c, se_c, p_c),
      Mediator_outcome_OR = med_outcome_or,
      DirectEffect_OR = fmt_or(coef_c_prime, se_c_prime, p_c_prime),
      IndirectEffect_OR = fmt_or(coef_a * coef_b, se_ab, p_ab),
      Path_a_Beta = fmt_beta(coef_a, se_a, p_a),
      Path_b_Beta = fmt_beta(coef_b, se_b, p_b, if (use_z) " (per 1-SD M)" else ""),
      Prop_Med_Pct = prop_med,
      Prop_Med_num = prop_med_num,
      .raw_coef_a = coef_a, .raw_p_a = as.numeric(p_a),
      .raw_coef_b = coef_b, .raw_p_b = as.numeric(p_b),
      .raw_eff_total = exp(coef_c), .raw_p_total = as.numeric(p_c),
      .raw_eff_direct = exp(coef_c_prime), .raw_p_direct = as.numeric(p_c_prime),
      .raw_prop_lo = if (length(pm_ci) == 2L) pm_ci[1L] else NA_real_,
      .raw_prop_hi = if (length(pm_ci) == 2L) pm_ci[2L] else NA_real_,
      .raw_ci_a_lo = coef_a - 1.96 * se_a, .raw_ci_a_hi = coef_a + 1.96 * se_a,
      .raw_ci_b_lo = coef_b - 1.96 * se_b, .raw_ci_b_hi = coef_b + 1.96 * se_b,
      .raw_ci_tot_lo = exp(coef_c - 1.96 * se_c), .raw_ci_tot_hi = exp(coef_c + 1.96 * se_c),
      .raw_ci_dir_lo = exp(coef_c_prime - 1.96 * se_c_prime),
      .raw_ci_dir_hi = exp(coef_c_prime + 1.96 * se_c_prime),
      .raw_p_indirect = p_ab,
      stringsAsFactors = FALSE
    )
  }

  .mnw01_empty_row <- function(med_var) {
    data.frame(
      Mediator = med_var,
      TotalEffect_OR = NA_character_, Mediator_outcome_OR = NA_character_,
      DirectEffect_OR = NA_character_, IndirectEffect_OR = NA_character_,
      Path_a_Beta = NA_character_, Path_b_Beta = NA_character_,
      Prop_Med_Pct = NA_character_, Prop_Med_num = NA_real_,
      .raw_coef_a = NA, .raw_p_a = NA, .raw_coef_b = NA, .raw_p_b = NA,
      .raw_eff_total = NA, .raw_p_total = NA,
      .raw_prop_lo = NA, .raw_prop_hi = NA,
      .raw_ci_a_lo = NA, .raw_ci_a_hi = NA,
      .raw_ci_b_lo = NA, .raw_ci_b_hi = NA,
      .raw_ci_tot_lo = NA, .raw_ci_tot_hi = NA,
      .raw_p_indirect = NA,
      stringsAsFactors = FALSE
    )
  }

  auto_cov_search <- if (exists("pipeline_mediation_auto_covariate_search", mode = "function")) {
    pipeline_mediation_auto_covariate_search(cfg, bl_cfg)
  } else {
    FALSE
  }
  path_alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% 0.05)
  search_b <- as.integer(bl_cfg$covariate_search_bootstrap_iter %||% min(50L, bootstrap_iter))[1L]

  if (auto_cov_search && length(mediators) > 0L) {
    pool_search <- bl_cfg$covariate_search_pool %||% M2_vars
    pool_search <- setdiff(unique(as.character(pool_search)), c(exposure, outcome, mediators))
    pool_search <- intersect(pool_search, names(design$variables))
    # 路径协变量里的二分因子也转 0/1，避免 svyglm 哑变量名对不上
    design <- {
      .coerce <- function(des, vars) {
        for (vn in vars) {
          if (!vn %in% names(des$variables)) next
          x <- des$variables[[vn]]
          if (is.numeric(x)) next
          if (is.logical(x)) { des$variables[[vn]] <- as.numeric(x); next }
          xc <- as.character(x)
          ux <- unique(xc[!is.na(xc) & nzchar(xc)])
          if (length(ux) != 2L) next
          pos <- ux[tolower(ux) %in% c("yes", "y", "1", "true", "positive", "present")]
          if (!length(pos)) pos <- ux[2L]
          des$variables[[vn]] <- as.numeric(xc == pos[1L])
        }
        des
      }
      .coerce(design, unique(c(pool_search, covariates, mediators)))
    }
    max_k <- as.integer(bl_cfg$covariate_search_max_size %||% 3L)[1L]
    if (!is.finite(max_k) || max_k < 1L) max_k <- 3L
    max_k <- min(max_k, length(pool_search))

    .try_adj <- function(adj_vec) {
      adj_vec <- setdiff(unique(as.character(adj_vec)), c(exposure, outcome, mediators))
      for (m in mediators) {
        row1 <- .mnw01_run_single(m, design, search_b, setdiff(adj_vec, m), standardize_mediator)
        # 三条路：Path a / Path b / Indirect 均显著（与用户“三路径显著”一致）
        if (.mi02_mediation_paths_significant(row1, path_alpha)) {
          return(list(ok = TRUE, adj = setdiff(adj_vec, m), hit = m))
        }
      }
      list(ok = FALSE, adj = NULL, hit = NA_character_)
    }

    found <- NULL
    # 先试 crude，再试配置全套，再按 k=1..max_k 搜子集
    for (adj0 in list(character(0), covariates)) {
      r <- .try_adj(adj0)
      if (isTRUE(r$ok)) { found <- r; break }
    }
    if (is.null(found) && length(pool_search) && max_k >= 1L) {
      tries <- 0L
      max_comb <- as.integer(bl_cfg$covariate_search_max_combinations %||% 400L)[1L]
      for (k in seq_len(max_k)) {
        cand <- utils::combn(pool_search, k, simplify = FALSE)
        for (adj_try in cand) {
          tries <- tries + 1L
          if (tries > max_comb) break
          r <- .try_adj(adj_try)
          if (isTRUE(r$ok)) {
            found <- r
            break
          }
        }
        if (!is.null(found) || tries > max_comb) break
      }
    }
    if (!is.null(found)) {
      covariates <- found$adj
      cli::cli_alert_success(
        "自动协变量搜索：中介 [{found$hit}] Path a/b/Indirect 均 p<{path_alpha}，调整集 {length(covariates)} 个: {paste(covariates, collapse = ', ')}"
      )
      ctx$results$mediation_nhanes_auto_covariates <- covariates
      ctx$results$mediation_nhanes_auto_covariate_hit_mediator <- found$hit
      # 门控/路径图优先用搜到的命中中介，避免被 Prop% 更高但路径不稳的候选抢走
      if (is.null(cfg$mediation_nhanes_weighted)) cfg$mediation_nhanes_weighted <- list()
      cfg$mediation_nhanes_weighted$best_mediator <- found$hit
      bl_cfg$best_mediator <- found$hit
      # 命中中介置前，减少后续全量 bootstrap 时被 Prop% 更高者覆盖
      mediators <- unique(c(found$hit, mediators))
      ctx$config <- cfg
    } else {
      cli::cli_alert_warning(
        "自动协变量搜索：在至多 {max_k} 个协变量内未找到 a/b/Indirect 均显著的调整集；沿用 config 协变量"
      )
    }
  }

  if (exists("pipeline_mediation_drop_mediators_from_covariates", mode = "function")) {
    covariates <- pipeline_mediation_drop_mediators_from_covariates(
      covariates, mediators, label = "mediation_nhanes_weighted"
    )
  } else {
    covariates <- setdiff(as.character(covariates %||% character(0)), mediators)
  }

  results_list <- lapply(mediators, function(m) {
    adj_i <- setdiff(covariates, m)
    .mnw01_run_single(m, design, bootstrap_iter, adj_i, standardize_mediator)
  })
  final_table <- dplyr::bind_rows(results_list)
  final_table <- final_table[order(-final_table$Prop_Med_num, na.last = TRUE), ]

  # 路径图指定中介置顶，保证表首行与 Figure S3 同一中介
  pin_med <- as.character((cfg$mediation_nhanes_weighted %||% list())$best_mediator %||% "")[1L]
  if (nzchar(pin_med) && pin_med %in% final_table$Mediator) {
    final_table <- rbind(
      final_table[final_table$Mediator == pin_med, , drop = FALSE],
      final_table[final_table$Mediator != pin_med, , drop = FALSE]
    )
  }

  raw_cols <- grep("^\\.raw_", names(final_table), value = TRUE)
  disp_cols <- setdiff(names(final_table), c("Prop_Med_num", raw_cols))
  disp_df <- final_table[, disp_cols, drop = FALSE]
  names(disp_df) <- c(
    "Mediator", "Total Effect (Index)", "Mediator-outcome OR(1-SD)",
    "Direct Effect", "Indirect Effect", "Path a (Beta)", "Path b (Beta)",
    "Proportion mediated"
  )

  # 规则：最佳中介 Proportion mediated + Direct Effect 均显著才导出；否则不出表/图/关联表
  med_export_ok <- .mi02_mediation_should_export(final_table, cfg, bl_cfg)
  if (!med_export_ok) {
    ctx$results$mediation_nhanes_weighted <- final_table
    ctx$results$mediation_nhanes_ns_skipped <- TRUE
    reason <- .mi02_mediation_skip_reason(final_table, cfg, bl_cfg)
    cli::cli_alert_warning(
      "mediation_nhanes_weighted: {reason}，按规则不导出中介表、路径图与实验室关联表。"
    )
    .mi02_unlink_mediation_exports(ctx)
    return(ctx)
  }

  .mi02_export_lab_association_table(
    ctx, ctx$results$mediation_nhanes_correlation_lm_rt, exposure, weighted = TRUE
  )

  med_pub <- pub_paths(
    ctx, ctx$output_dir_tables, "supp_table",
    paste0("Weighted mediation analysis of ", gsub("_", " ", exposure)),
    "xlsx"
  )
  ctx$results$mediation_nhanes_weighted <- final_table
  tryCatch({
    fn_med <- if (exists("pipeline_mediation_table_footnotes", mode = "function")) {
      pipeline_mediation_table_footnotes(standardize_mediator)
    } else {
      "A negative proportion mediated indicates a suppression (masking) effect, not a mediated fraction."
    }
    export_sci_table(
      disp_df, med_pub$filepath, title = med_pub$title,
      table_footnotes = fn_med
    )
    cli::cli_alert_success("Table saved: {.file {basename(med_pub$filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("mediation 表导出失败: {e$message}")
  })

  if (isTRUE(bl_cfg$diagram_enable %||% TRUE) && nrow(final_table) > 0L) {
    best_row <- .mi02_mediation_pick_best_row(final_table, cfg, bl_cfg)
    if (isTRUE((cfg$dual_db %||% list())$enable) &&
        exists("dual_db_save_preferred_mediator", mode = "function")) {
      root_m <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
      dual_db_save_preferred_mediator(root_m, cfg, best_row$Mediator[1L])
    }
    sel_colors <- .mi02_palettes[[sample(names(.mi02_palettes), 1L)]]
    outcome_diag_label <- .mediation_outcome_diag_label(cfg)
    fig_caption <- paste0(
      "Weighted mediation path diagram of ", exposure, " and ", outcome_diag_label
    )
    # 发病双库发表规范：中介路径图 = Figure S3（与 CHARLS 统一）
    fig_kind <- as.character((cfg$mediation_nhanes_weighted %||% list())$figure_kind %||% "supp_figure")[1L]
    if (!nzchar(fig_kind)) fig_kind <- "supp_figure"
    fig_name <- pub_figure_file(ctx, fig_kind, fig_caption)
    fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
    if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
    diag_path <- file.path(fig_dir, fig_name)
    p_diag <- tryCatch(
      .mi02_draw_mediation_path_diagram(
        exposure_label = exposure,
        mediator_label = best_row$Mediator[1L],
        outcome_label = outcome_diag_label,
        coef_a = best_row$.raw_coef_a[1L], p_a = best_row$.raw_p_a[1L],
        coef_b = best_row$.raw_coef_b[1L], p_b = best_row$.raw_p_b[1L],
        # 底边 = Direct Effect (c')，与表「Direct Effect」列一致
        effect_total = if (".raw_eff_direct" %in% names(best_row)) best_row$.raw_eff_direct[1L] else best_row$.raw_eff_total[1L],
        p_total = if (".raw_p_direct" %in% names(best_row)) best_row$.raw_p_direct[1L] else best_row$.raw_p_total[1L],
        prop_pct = best_row$Prop_Med_num[1L],
        prop_lo_pct = NA_real_,
        prop_hi_pct = NA_real_,
        colors = sel_colors,
        ci_a_lo = best_row$.raw_ci_a_lo[1L], ci_a_hi = best_row$.raw_ci_a_hi[1L],
        ci_b_lo = best_row$.raw_ci_b_lo[1L], ci_b_hi = best_row$.raw_ci_b_hi[1L],
        ci_tot_lo = if (".raw_ci_dir_lo" %in% names(best_row)) best_row$.raw_ci_dir_lo[1L] else best_row$.raw_ci_tot_lo[1L],
        ci_tot_hi = if (".raw_ci_dir_hi" %in% names(best_row)) best_row$.raw_ci_dir_hi[1L] else best_row$.raw_ci_tot_hi[1L],
        font_family = plot_font_from_config(cfg),
        output_path = diag_path
      ),
      error = function(e) {
        cli::cli_alert_warning("中介路径图失败: {e$message}")
        NULL
      }
    )
    if (!is.null(p_diag) && file.exists(diag_path)) {
      mirror_pub_output_to_root(ctx, diag_path)
      ctx$results$mediation_nhanes_diagram_path <- diag_path
    }
  }

  cli::cli_alert_success("mediation_nhanes_weighted 完成（{length(mediators)} 个血检中介）。")
  ctx
}

register_block(
  "mediation_nhanes_weighted",
  block_mediation_nhanes_weighted,
  "NHANES 加权发病中介：血检 LM 筛选 + svyglm 加权中介 + 路径图"
)
