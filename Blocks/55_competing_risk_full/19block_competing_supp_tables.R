###############################################################################
#  competing_supp_tables — 补充材料 1–6（案例多段骨架 + 可区分灵敏度）
#
#  Supp1: 四分位亚组（主事件 + Overall mortality）
#  Supp2≡MOESM2: Cox + Competing Handle + No handle + MI1/2（全队列；充分校正混杂）
#  Supp3≡MOESM3: Competing Handle + No handle + MI1/2（全队列）
#  Supp4≡MOESM4: Standard Cox · Handle extreme values + No handle extreme values
#  （VIF 共线性另有 .competing_supp_vif_table，不占用 Supp4 号）
#  Supp5: 轨迹亚组
#  Supp6: 轨迹 Standard + Competing(Handle/No handle) + MI1/2
###############################################################################

.competing_supp_trim <- function(x) {
  if (is.factor(x)) {
    levels(x) <- trimws(levels(x))
    return(factor(trimws(as.character(x)), levels = unique(trimws(levels(x)))))
  }
  if (is.character(x)) return(trimws(x))
  x
}

.competing_supp_pick_strata <- function(data, bl = list(), exclude = character(),
                                        min_level_n = 40L) {
  # 优先临床二分类（对齐案例 Gender/Age/Hypertension/CKD/Hyperlipidemia…）
  prefer <- unique(c(
    "Gender", "Age", "Hypertension", "CKD", "Hyperlipidemia", "CHD", "Diabetes",
    "Stroke", "COPD", "HF", "Smoking", "Drinking", "Ventilation",
    as.character(bl$supp_strata_vars %||% character(0)),
    as.character(bl$stratify_vars %||% character(0)),
    as.character(bl$baseline_vars %||% character(0)),
    as.character(bl$demographic_vars %||% character(0))
  ))
  # Race 多水平且稀疏，默认不进亚组（可用 config$competing_risk$supp_strata_vars 强制）
  prefer <- setdiff(prefer, c(exclude, "Age_group", "Race"))
  out <- character(0)
  if ("Age" %in% names(data) && is.numeric(data$Age) && !"Age" %in% exclude) {
    ag <- ifelse(data$Age >= 75, ">=75", "<75")
    if (min(table(ag, useNA = "no")) >= min_level_n) out <- c(out, "Age")
  }
  for (v in prefer) {
    if (v %in% out || identical(v, "Age") || !v %in% names(data)) next
    x <- data[[v]]
    if (all(is.na(x))) next
    if (is.numeric(x) && length(unique(stats::na.omit(x))) > 8L) next
    xf <- tryCatch(factor(.competing_supp_trim(x)), error = function(e) NULL)
    if (is.null(xf)) next
    nlev <- nlevels(xf)
    if (nlev < 2L || nlev > 4L) next
    tab <- table(xf, useNA = "no")
    if (!length(tab) || min(as.integer(tab)) < min_level_n) next
    out <- c(out, v)
  }
  unique(out)
}

.competing_supp_subgroup <- function(data, time_var, event_col, exp_var, causes, strata_vars,
                                     min_n = 30L) {
  if (!requireNamespace("survival", quietly = TRUE)) return(data.frame(note = "no survival"))
  if (!exp_var %in% names(data)) return(data.frame(note = "no exposure"))
  data[[exp_var]] <- .competing_supp_trim(factor(data[[exp_var]]))
  rows <- list()
  n_total <- nrow(data)
  primary_nm <- names(causes)[1L]

  for (sg in strata_vars) {
    if (identical(sg, "Age") && "Age" %in% names(data) && is.numeric(data$Age)) {
      data$Age_group <- ifelse(data$Age >= 75, ">=75", "<75")
      sg_use <- "Age_group"
      sg_name <- "Age"
    } else {
      if (!sg %in% names(data)) next
      sg_use <- sg
      sg_name <- sg
      data[[sg_use]] <- .competing_supp_trim(data[[sg_use]])
    }
    lvls <- levels(factor(data[[sg_use]]))
    pint <- setNames(rep(NA_real_, length(causes)), names(causes))
    for (cause_nm in names(causes)) {
      cause <- causes[[cause_nm]]
      data$evt <- as.integer(data[[event_col]] == cause)
      ok <- !is.na(data[[exp_var]]) & !is.na(data[[sg_use]]) & !is.na(data[[time_var]])
      if (sum(ok) < 40L) next
      f0 <- tryCatch(
        survival::coxph(stats::as.formula(paste0("Surv(", time_var, ", evt)~", exp_var, "+", sg_use)),
                        data = data[ok, , drop = FALSE]),
        error = function(e) NULL
      )
      f1 <- tryCatch(
        survival::coxph(stats::as.formula(paste0("Surv(", time_var, ", evt)~", exp_var, "*", sg_use)),
                        data = data[ok, , drop = FALSE]),
        error = function(e) NULL
      )
      if (!is.null(f0) && !is.null(f1)) {
        pint[[cause_nm]] <- tryCatch({
          an <- anova(f0, f1, test = "Chisq")
          as.numeric(an$`Pr(>|Chi|)`[2])
        }, error = function(e) NA_real_)
      }
    }

    exp_lvls <- levels(factor(data[[exp_var]]))
    pint_primary <- if (!is.null(primary_nm)) pint[[primary_nm]] else NA_real_
    for (lv in lvls) {
      sub <- data[as.character(data[[sg_use]]) == as.character(lv) & !is.na(data[[exp_var]]), , drop = FALSE]
      if (nrow(sub) < min_n) next
      n_lab <- sprintf("%d(%.1f)", nrow(sub), 100 * nrow(sub) / max(1, n_total))
      for (cause_nm in names(causes)) {
        cause <- causes[[cause_nm]]
        sub$evt <- as.integer(sub[[event_col]] == cause)
        n_evt <- sum(sub$evt, na.rm = TRUE)
        ref <- exp_lvls[1]
        # 参考组 0 事件 → 相对 Q1/T1 的 HR 不可估（写 NE，避免空白被误认为漏算）
        evt_by_exp <- tapply(sub$evt, as.character(sub[[exp_var]]), sum)
        ref_evt <- suppressWarnings(as.integer(evt_by_exp[[as.character(ref)]]))
        if (length(ref_evt) != 1L || is.na(ref_evt)) ref_evt <- 0L
        pint_m <- pint[["Overall mortality"]]
        if (is.null(pint_m) || (length(pint_m) == 1L && is.na(pint_m))) {
          pint_m <- pint[["Mortality"]]
        }
        rows[[length(rows) + 1L]] <- data.frame(
          Subgroup = sg_name, Level = as.character(lv), n = nrow(sub),
          n_lab = n_lab, Quartile = paste0(exp_var, ref), Outcome = cause_nm,
          HR_CI = "", P = "",
          P_int_Primary = pint_primary,
          P_int_Mortality = pint_m,
          stringsAsFactors = FALSE
        )
        if (n_evt < 3L) {
          # 事件过少：非参考水平标 NE
          for (el in setdiff(exp_lvls, ref)) {
            rows[[length(rows) + 1L]] <- data.frame(
              Subgroup = sg_name, Level = as.character(lv), n = nrow(sub),
              n_lab = n_lab, Quartile = paste0(exp_var, el), Outcome = cause_nm,
              HR_CI = "NE", P = "NE",
              P_int_Primary = pint_primary, P_int_Mortality = pint_m,
              stringsAsFactors = FALSE
            )
          }
          next
        }
        fit <- tryCatch(
          survival::coxph(stats::as.formula(paste0("Surv(", time_var, ", evt)~", exp_var)), data = sub),
          error = function(e) NULL
        )
        if (is.null(fit) || identical(as.integer(ref_evt), 0L)) {
          for (el in setdiff(exp_lvls, ref)) {
            rows[[length(rows) + 1L]] <- data.frame(
              Subgroup = sg_name, Level = as.character(lv), n = nrow(sub),
              n_lab = n_lab, Quartile = paste0(exp_var, el), Outcome = cause_nm,
              HR_CI = "NE", P = "NE",
              P_int_Primary = pint_primary, P_int_Mortality = pint_m,
              stringsAsFactors = FALSE
            )
          }
          next
        }
        s <- summary(fit)
        for (i in seq_len(nrow(s$coefficients))) {
          hr <- as.numeric(s$conf.int[i, "exp(coef)"])
          lo <- as.numeric(s$conf.int[i, "lower .95"])
          hi <- as.numeric(s$conf.int[i, "upper .95"])
          ne <- !is.finite(hr) || !is.finite(hi) || abs(hr) > 1e4 || abs(hi) > 1e4
          hr_ci <- if (ne) "NE" else sprintf("%.2f(%.2f-%.2f)", hr, lo, hi)
          p_lab <- if (ne) "NE" else signif(s$coefficients[i, "Pr(>|z|)"], 3)
          rows[[length(rows) + 1L]] <- data.frame(
            Subgroup = sg_name, Level = as.character(lv), n = nrow(sub),
            n_lab = n_lab,
            Quartile = rownames(s$coefficients)[i],
            Outcome = cause_nm,
            HR_CI = hr_ci,
            P = p_lab,
            P_int_Primary = pint_primary,
            P_int_Mortality = pint_m,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  if (!length(rows)) data.frame(note = "no subgroup") else do.call(rbind, rows)
}

block_competing_supp_tables <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  cfg <- ctx$config
  root <- cfg$project$root %||% getwd()
  source(file.path(root, "R/competing_supp_fit.R"), local = FALSE)
  source(file.path(root, "R/competing_supp_xlsx.R"), local = FALSE)
  if (!exists(".competing_fit_one_cox", mode = "function")) {
    source(file.path(root, "Blocks/55_competing_risk_full/09block_competing_models_123.R"), local = FALSE)
  }

  data_h <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data_h)) stop("competing_supp_tables: 无数据", call. = FALSE)

  index_var <- bl$index_var %||% {
    (cfg$incidence %||% list())$index_var %||% "TyG"
  }
  time_var <- bl$time_var %||% "competing_time_28d"
  event_col <- bl$event_type_col %||% "competing_status_28d"
  exp_q <- bl$exposure_var %||% paste0(index_var, "_quartile")
  exp_t <- bl$trajectory_var %||% paste0(index_var, "_trajectory")
  primary <- as.integer(bl$primary_cause %||% 1L)[1L]
  death <- as.integer(bl$death_cause %||% 2L)[1L]
  horizons <- as.integer(bl$model_horizons %||% c(7L, 14L, 28L))
  db <- as.character(cfg$project$database %||% "MIMIC")[1L]
  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  primary_lbl <- as.character(bl$primary_event_label %||% "AKI")[1L]
  if (!nzchar(primary_lbl)) primary_lbl <- "AKI"
  death_lbl <- as.character(bl$death_event_label %||% "Overall mortality")[1L]
  causes <- list()
  causes[[primary_lbl]] <- primary
  causes[[death_lbl]] <- death

  # 未处理极端值队列
  data_u <- .competing_supp_resolve_untrimmed(ctx, data_h, index_var)
  # 轨迹列可能仅在 trim 后由 cluster 写入：尽量合并
  if (exp_t %in% names(data_h) && !exp_t %in% names(data_u)) {
    id_col <- as.character((cfg$data %||% list())$id_column %||% "ID")[1L]
    if (id_col %in% names(data_u) && id_col %in% names(data_h)) {
      data_u[[exp_t]] <- data_h[[exp_t]][match(data_u[[id_col]], data_h[[id_col]])]
    }
  }

  cov_h <- .competing_supp_cov_pools(data_h, bl, ctx)
  cov_u <- .competing_supp_cov_pools(data_u, bl, ctx)
  skeleton <- unique(c(cov_h$all, cov_u$all))
  cov_src <- as.character(cov_h$source %||% "unknown")[1L]
  footnote <- sprintf(
    "Model 1: unadjusted; Model 2: %s; Model 3: %s",
    if (length(cov_h$m2)) paste(.competing_supp_display_label(cov_h$m2), collapse = ", ") else "none",
    if (length(cov_h$m3)) paste(.competing_supp_display_label(cov_h$m3), collapse = ", ") else "none"
  )
  cli::cli_alert_info(
    "补充表协变量来源={cov_src}; m2={paste(cov_h$m2, collapse=', ')}; m3={paste(cov_h$m3, collapse=', ')}"
  )

  excl <- unique(c(
    as.character((cfg$data %||% list())$id_column %||% "ID"),
    "ID", "subject_id", "SEQN",
    time_var, event_col, index_var, exp_q, exp_t,
    paste0(index_var, c("_quartile", "_trajectory")),
    "hosp_day", "is_hosp_dead", "competing_time_28d", "competing_status_28d",
    "Acute_Renal_Failure", "AKI"
  ))
  strata_vars <- .competing_supp_pick_strata(data_h, bl = bl, exclude = excl, min_level_n = 40L)
  if (!length(strata_vars)) {
    strata_vars <- intersect(c("Gender", "Age", "Hypertension", "CKD"), names(data_h))
  }
  cli::cli_alert_info(
    "补充表亚组={paste(strata_vars, collapse=', ')}; 骨架协变量={paste(skeleton, collapse=', ')}; 主事件={primary_lbl}"
  )

  # ---- Supp1 / Supp5 亚组 ----
  s1 <- .competing_supp_subgroup(data_h, time_var, event_col, exp_q, causes, strata_vars)
  .competing_write_supp_subgroup_xlsx(
    file.path(out_dir, sprintf("Supplementary Material 1-%s. Subgroup analysis by quartile.xlsx", db)),
    s1, db = db, exposure_lab = "Quartile",
    outcome1 = primary_lbl, outcome2 = death_lbl
  )

  s5 <- if (exp_t %in% names(data_h)) {
    .competing_supp_subgroup(data_h, time_var, event_col, exp_t, causes, strata_vars)
  } else data.frame(note = "no trajectory")
  .competing_write_supp_subgroup_xlsx(
    file.path(out_dir, sprintf("Supplementary Material 5-%s. Subgroup analysis by trajectory.xlsx", db)),
    s5, db = db, exposure_lab = "Trajectory",
    outcome1 = primary_lbl, outcome2 = death_lbl
  )

  # ---- 四分位：重拟合展示模型 ----
  cli::cli_alert_info("补充表重拟合四分位 Model1–3（handled / unhandled）…")
  tab_q_h <- .competing_supp_fit_models(
    data_h, time_var, event_col, exp_q, primary, horizons = horizons,
    cov_pools = cov_h, methods = c("standard", "competing"), bl = bl, ctx = ctx
  )
  tab_q_u <- .competing_supp_fit_models(
    data_u, time_var, event_col, exp_q, primary, horizons = horizons,
    cov_pools = cov_u, methods = c("standard", "competing"), bl = bl, ctx = ctx
  )

  # Supp2 ≡ MOESM2：Cox + Competing Handle + No handle + MI1/2（全队列充分校正）
  mi_secs_q <- .competing_supp_fit_mi_sections(
    ctx, data_h, time_var, event_col, exp_q, primary,
    horizons, cov_h, skeleton, bl, n_mi = 2L, method = "competing"
  )
  .competing_write_supp_models_xlsx(
    file.path(out_dir, sprintf(
      "Supplementary Material 2-%s. Standard Cox by quartile (sensitivity).xlsx", db
    )),
    sections = c(
      list(
        list(
          tab = tab_q_h, method = "standard",
          skeleton_vars = skeleton,
          section_title = "Cox proportional hazards model",
          extra_note = "Multivariable adjustment (Model 1–3)"
        ),
        list(
          tab = tab_q_h, method = "competing",
          skeleton_vars = skeleton,
          section_title = "Competing Risk Cox regression",
          extra_note = "Handle extreme values"
        ),
        list(
          tab = tab_q_u, method = "competing",
          skeleton_vars = skeleton,
          section_title = NULL,
          extra_note = "No handle extreme values"
        )
      ),
      mi_secs_q
    ),
    horizons = horizons, model_ids = 1:3, covs_footnote = footnote
  )

  # Supp3/4：Handle / No-handle extremes（对齐原文 MOESM3–4）；可用 export_extremes_supp_tables=FALSE 关闭
  export_extremes_supp <- !isFALSE((bl$export_extremes_supp_tables %||% TRUE))
  if (isTRUE(export_extremes_supp)) {
    .competing_write_supp_models_xlsx(
      file.path(out_dir, sprintf(
        "Supplementary Material 3-%s. Competing-risk Cox sensitivity (extremes handled).xlsx", db
      )),
      sections = c(
        list(
          list(
            tab = tab_q_h, method = "competing",
            skeleton_vars = skeleton,
            section_title = "Competing Risk Cox regression",
            extra_note = "Handle extreme values"
          ),
          list(
            tab = tab_q_u, method = "competing",
            skeleton_vars = skeleton,
            section_title = NULL,
            extra_note = "No handle extreme values"
          )
        ),
        mi_secs_q
      ),
      horizons = horizons, model_ids = 1:3, covs_footnote = footnote
    )

    old4 <- list.files(
      out_dir,
      pattern = sprintf("^Supplementary Material 4-%s\\.", db),
      full.names = TRUE
    )
    if (length(old4)) unlink(old4)
    .competing_write_supp_models_xlsx(
      file.path(out_dir, sprintf(
        "Supplementary Material 4-%s. Standard Cox sensitivity (extremes handled).xlsx", db
      )),
      sections = list(
        list(
          tab = tab_q_h, method = "standard",
          skeleton_vars = skeleton,
          section_title = "Cox proportional hazards regression",
          extra_note = "Handle extreme values"
        ),
        list(
          tab = tab_q_u, method = "standard",
          skeleton_vars = skeleton,
          section_title = NULL,
          extra_note = "No handle extreme values"
        )
      ),
      horizons = horizons, model_ids = 1:3, covs_footnote = footnote
    )
  } else {
    old34 <- list.files(
      out_dir,
      pattern = sprintf("^Supplementary Material [34]-%s\\.", db),
      full.names = TRUE
    )
    if (length(old34)) {
      unlink(old34)
      cli::cli_alert_info(
        "已跳过 Supp Mat 3/4（与 Supp2 Handle/No-handle 重复）；删除旧文件 {length(old34)} 个"
      )
    }
  }

  # 额外：VIF 共线性诊断（不占用案例 Supp4 编号；单独文件）
  vif_tab <- .competing_supp_vif_table(
    data_h, vars = cov_h$m3 %||% skeleton, bl = bl, ctx = ctx, include_exposure = TRUE
  )
  cli::cli_alert_info(
    "补充表 VIF（另存）：n_var={nrow(vif_tab)}; strict={attr(vif_tab,'vif_threshold_strict') %||% 4}"
  )
  .competing_write_supp_vif_xlsx(
    file.path(out_dir, sprintf(
      "Supplementary Material-%s. Multicollinearity Analysis (VIF).xlsx", db
    )),
    vif_df = vif_tab,
    db = db
  )

  # ---- Supp6 轨迹：三段堆叠（对齐案例 MOESM6）----
  if (exp_t %in% names(data_h)) {
    cli::cli_alert_info("补充表重拟合轨迹 Model1–3…")
    tab_t_h <- .competing_supp_fit_models(
      data_h, time_var, event_col, exp_t, primary, horizons = horizons,
      cov_pools = cov_h, methods = c("standard", "competing"), bl = bl, ctx = ctx
    )
    tab_t_u <- if (exp_t %in% names(data_u) && any(!is.na(data_u[[exp_t]]))) {
      .competing_supp_fit_models(
        data_u[!is.na(data_u[[exp_t]]), , drop = FALSE],
        time_var, event_col, exp_t, primary, horizons = horizons,
        cov_pools = cov_u, methods = c("competing"), bl = bl, ctx = ctx
      )
    } else tab_t_h

    mi_secs_t <- .competing_supp_fit_mi_sections(
      ctx, data_h, time_var, event_col, exp_t, primary,
      horizons, cov_h, skeleton, bl, n_mi = 2L, method = "competing"
    )
    .competing_write_supp_models_xlsx(
      file.path(out_dir, sprintf("Supplementary Material 6-%s. Standard Cox by trajectory.xlsx", db)),
      sections = c(
        list(
          list(
            tab = tab_t_h, method = "standard", skeleton_vars = skeleton,
            section_title = "Cox proportional hazards model",
            extra_note = NULL
          ),
          list(
            tab = tab_t_h, method = "competing", skeleton_vars = skeleton,
            section_title = "Competing Risk Model",
            extra_note = "Handle extreme values"
          ),
          list(
            tab = tab_t_u, method = "competing", skeleton_vars = skeleton,
            section_title = NULL,
            extra_note = "No handle extreme values"
          )
        ),
        mi_secs_t
      ),
      horizons = horizons, model_ids = 1:3, covs_footnote = footnote
    )
  } else {
    cli::cli_alert_warning("无轨迹变量 {exp_t}，跳过 Supplementary Material 6")
  }

  # 中间拟合结果只留在 ctx$results，不往 Tables/ 落 csv
  ctx$results$competing_supp_tables <- list(
    ok = TRUE,
    n_supp1 = NROW(s1), n_supp5 = NROW(s5),
    strata_vars = strata_vars,
    skeleton_vars = skeleton,
    cov_source = cov_src,
    primary_event_label = primary_lbl,
    death_event_label = death_lbl,
    footnote = footnote,
    early_lag_days = NULL,
    early_n_excluded = NULL,
    n_handled = nrow(data_h),
    n_unhandled = nrow(data_u),
    models_quartile_handled = tab_q_h,
    models_quartile_unhandled = tab_q_u,
    models_quartile_early_excl = NULL,
    vif_table = vif_tab
  )
  cli::cli_alert_success(
    "补充材料 1–6 已导出（可复用案例格式）; handled n={nrow(data_h)}; unhandled n={nrow(data_u)}"
  )
  ctx
}

if (exists("register_block", mode = "function")) {
  register_block("competing_supp_tables", block_competing_supp_tables, "补充材料 1–6")
}
