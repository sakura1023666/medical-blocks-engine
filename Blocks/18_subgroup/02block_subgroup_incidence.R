###############################################################################
#  subgroup_incidence — 发病亚组森林图（index 高/低 × 分类亚组，jstable GLM OR + forestploter）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_config = config$subgroup, incidence$outcome_var/index_var, logistic$index_var
#
#  读 config$subgroup；暴露/结局见 incidence 与 logistic$index_var。
###############################################################################

.sgi02_canonical_subgroup_order_vec <- function() {
  c(
    "Age_Group",
    "Gender",
    "BMI",
    "Education",
    "Marital_Status",
    "Income",
    "Smoking",
    "Alcohol_drinking",
    "Race",
    "Weight",
    "Height",
    "Language",
    "Micu_Code",
    "Insurance",
    "Ventilation",
    "Hypertension",
    "Diabetes",
    "T1DM",
    "T2DM",
    "Heart_Failure",
    "Myocardial_Infarction",
    "Atrial_Fibrillation",
    "Stroke",
    "COPD",
    "CKD",
    "Acute_Renal_Failure",
    "Liver_cirrhosis",
    "Hepatitis",
    "Cancer",
    "Hyperlipidemia",
    "Pneumonia",
    "Tuberculosis",
    "Dementia"

  )
}

.sgi02_order_subgroup_vars_clinical <- function(v, req_ord = character(0)) {
  v <- unique(as.character(v))
  req_ord <- as.character(req_ord %||% character(0))
  # required 模式：严格按 required_subgroup_vars 顺序（跨库一致）
  if (length(req_ord)) {
    hit <- req_ord[req_ord %in% v]
    return(unique(c(hit, setdiff(v, hit))))
  }
  if (exists("subgroup_order_vars", mode = "function")) {
    return(subgroup_order_vars(v, req_ord))
  }
  canon <- .sgi02_canonical_subgroup_order_vec()
  c(intersect(canon, v), sort(setdiff(v, canon)))
}

.sgi02_pretty_subgroup_label <- function(x) {
  x <- as.character(x %||% "")
  # 仅下划线→空格；勿把区间连字符「30-44」抹成「30 44」（Fig 6 等森林图标签）
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  trimws(x)
}

## 调整版亚组（P0-6②）：逐层 glm(.y01 ~ <index> + covs)，拼 jstable 同构 8 列 res。
## <index> 因子在调用前已按 Q1..Q4 分好并二分为最高 vs 最低（highest_vs_lowest）。
## 返回列：Variable / Count / Percent / Point Estimate / Lower / Upper / P value / P for interaction
## 行结构必须与 jstable 一致：变量标题行（无缩进，仅 P for interaction）+
## 水平缩进行（"  level"，含 OR/CI/P）。若写成 "Var: level" 扁平行，
## subgroup_prepare_forest_plot_df 会把全部当标题行 → OR 文本列空白、图面不像发病套路。
.sgi02_adjusted_subgroup_glm <- function(rt, index_var, var_subgroups, covs,
                                         total_n = nrow(rt)) {
  fmt_p <- function(p) {
    p <- suppressWarnings(as.numeric(p))
    if (is.na(p)) return("")
    if (p < 0.001) return("<0.001")
    formatC(round(p, 3), format = "f", digits = 3)
  }
  .empty_row <- function(variable, count = NA_real_, percent = NA_real_,
                         or = NA_real_, lo = NA_real_, hi = NA_real_,
                         pv = "", pint = "") {
    data.frame(
      Variable = variable, Count = count, Percent = percent,
      `Point Estimate` = or, Lower = lo, Upper = hi,
      `P value` = pv, `P for interaction` = pint,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  iv <- paste0("`", index_var, "`")
  rows <- list()
  rows[[length(rows) + 1L]] <- .empty_row("Overall")
  for (sv in var_subgroups) {
    lv <- levels(droplevels(factor(as.character(rt[[sv]]))))
    lv <- lv[lv %in% unique(as.character(stats::na.omit(rt[[sv]])))]
    pint <- tryCatch({
      m <- stats::glm(
        stats::as.formula(paste0(".y01 ~ ", iv, " + `", sv, "` + ", iv, ":`", sv, "`")),
        data = rt, family = stats::binomial()
      )
      an <- stats::anova(m, test = "LRT")
      fmt_p(an$`Pr(>Chi)`[nrow(an)])
    }, error = function(e) "")
    rows[[length(rows) + 1L]] <- .empty_row(
      .sgi02_pretty_subgroup_label(sv), pint = pint
    )
    # 层内调整：剔除分层变量本身；Age_Group 层同时剔除 Age，避免同信息共线
    covs_l <- setdiff(covs, sv)
    if (identical(sv, "Age_Group") || identical(sv, "Age")) {
      covs_l <- setdiff(covs_l, "Age")
    }
    if (sv %in% c("Smoke", "Smoking")) {
      covs_l <- setdiff(covs_l, c("Smoke", "Smoking"))
    }
    if (sv %in% c("Gender", "Sex")) {
      covs_l <- setdiff(covs_l, c("Gender", "Sex"))
    }
    for (l in lv) {
      sub <- rt[as.character(rt[[sv]]) == l & !is.na(rt[[sv]]), , drop = FALSE]
      n_l <- nrow(sub)
      or <- lo <- hi <- NA_real_; pv <- ""
      tryCatch({
        fo <- paste0(
          ".y01 ~ ", iv,
          if (length(covs_l)) paste0(" + ", paste0("`", covs_l, "`", collapse = " + ")) else ""
        )
        m <- stats::glm(stats::as.formula(fo), data = sub, family = stats::binomial())
        co <- summary(m)$coefficients
        hit <- grep(paste0("^", index_var), rownames(co), value = TRUE)
        if (length(hit)) {
          or <- exp(co[hit[1], 1]); lo <- exp(co[hit[1], 1] - 1.959963985 * co[hit[1], 2])
          hi <- exp(co[hit[1], 1] + 1.959963985 * co[hit[1], 2])
          pv <- fmt_p(co[hit[1], 4])
        }
      }, error = function(e) NULL)
      rows[[length(rows) + 1L]] <- .empty_row(
        paste0("  ", .sgi02_pretty_subgroup_label(l)),
        count = n_l, percent = round(100 * n_l / total_n, 2),
        or = or, lo = lo, hi = hi, pv = pv, pint = ""
      )
    }
  }
  do.call(rbind, rows)
}


block_subgroup_incidence <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(jstable)
    library(forestploter)
    library(grid)
  })
  .sgi02_engine_root <- function() {
    candidates <- unique(c(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
      as.character(ctx$config$project$engine_root %||% ""),
      as.character(ctx$config$project$root %||% ""),
      getwd()
    ))
    for (r in candidates) {
      if (nzchar(r) && file.exists(file.path(r, "R", "subgroup_vars.R"))) return(r)
    }
    getwd()
  }
  if (!exists("subgroup_render_forest_figure", mode = "function")) {
    root_sf <- .sgi02_engine_root()
    if (!file.exists(file.path(root_sf, "R", "subgroup_forest_plot.R"))) {
      for (r in unique(c(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), getwd()))) {
        if (nzchar(r) && file.exists(file.path(r, "R", "subgroup_forest_plot.R"))) {
          root_sf <- r
          break
        }
      }
    }
    suppressWarnings(source(file.path(root_sf, "R", "subgroup_forest_plot.R"), local = FALSE))
  }
  if (!exists("subgroup_resolve_min_n", mode = "function") ||
      !exists("subgroup_build_variable_pool", mode = "function") ||
      !exists("subgroup_coerce_low_card_numeric_to_factor", mode = "function")) {
    root_sv <- .sgi02_engine_root()
    if (nzchar(root_sv %||% "") && file.exists(file.path(root_sv, "R", "subgroup_vars.R"))) {
      suppressWarnings(source(file.path(root_sv, "R", "subgroup_vars.R"), local = FALSE))
    }
  }

  cfg <- ctx$config
  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  data_imp <- as.data.frame(data_imp)

  log_idx <- cfg$logistic$index_var
  if (is.null(log_idx)) stop("index_var is required in config$logistic")

  study_type <- "incidence"

  sub_cfg <- cfg$subgroup %||% list()
  surv <- cfg$survival %||% list()
  inc_cfg <- cfg$incidence %||% list()
  time_col <- surv$time_var %||% surv$time_column %||% "futime"
  status_col <- surv$event_var %||% surv$status_column %||% surv$event_column %||% "fustatus"

  index_var <- as.character(
    cfg$prediction$index_vars %||%
      cfg$ml_batch$index_vars %||%
      inc_cfg$index_var %||%
      log_idx
  )
  index_var <- index_var[nzchar(trimws(index_var))]
  if (!length(index_var)) stop("index_var is required", call. = FALSE)
  index_var <- index_var[[1L]]
  disease_col <- inc_cfg$outcome_var %||% sub_cfg$incidence_outcome_column %||%
    cfg$data$outcome_column %||% "Disease"

  analysis_grp <- cfg$project$analysis_group %||% cfg$project$disease
  ref_grp <- cfg$project$reference_group %||% "Control"
  disease_label <- analysis_grp

  cli::cli_alert_info("Subgroup mode: {study_type} (outcome column: {.field {disease_col}})")
  cli::cli_alert_info("Index variable: {index_var}")
  cli::cli_alert_info("Case / positive label: {disease_label}")

  if (!exists("subgroup_resolve_min_n", mode = "function")) {
    stop("subgroup_resolve_min_n 未加载（检查 MEDICAL_BLOCKS_ROOT/R/subgroup_vars.R）", call. = FALSE)
  }
  min_group_size <- subgroup_resolve_min_n(sub_cfg, nrow(data_imp))
  age_cut <- sub_cfg$age_cutoff %||% 65
  var_source <- sub_cfg$var_source %||% "table1_categorical"
  req <- if (identical(var_source, "required")) {
    as.character(sub_cfg$required_subgroup_vars %||% sub_cfg$vars %||% character(0))
  } else {
    character(0)
  }
  forbid <- subgroup_default_forbid(cfg)
  skip_age <- subgroup_age_forbidden(cfg)
  if (length(intersect(req, forbid))) {
    stop(
      "config$subgroup: required_subgroup_vars 与 forbid/exclude 冲突: ",
      paste(intersect(req, forbid), collapse = ", ")
    )
  }

  age_lo <- paste0("< ", age_cut)
  age_hi <- paste0("\u2265 ", age_cut)
  age_col <- if ("Age" %in% names(data_imp)) {
    "Age"
  } else if ("Age_Years" %in% names(data_imp)) {
    "Age_Years"
  } else {
    NULL
  }
  if (!skip_age && !is.null(age_col)) {
    data_imp$Age_Group <- ifelse(data_imp[[age_col]] < age_cut, age_lo, age_hi)
    data_imp$Age_Group <- factor(data_imp$Age_Group, levels = c(age_lo, age_hi))
    agt <- table(data_imp$Age_Group, useNA = "ifany")
    cli::cli_alert_info(
      "Age grouping from {age_col} (cutoff {age_cut}): {paste(paste0(names(agt), '=', as.integer(agt)), collapse=', ')}"
    )
  } else if (!skip_age && "Age_Group" %in% names(data_imp) && !all(is.na(data_imp$Age_Group))) {
    if (!is.factor(data_imp$Age_Group)) {
      data_imp$Age_Group <- factor(as.character(data_imp$Age_Group))
    }
    cli::cli_alert_info("Using existing Age_Group: {paste(levels(data_imp$Age_Group), collapse=', ')}")
  } else {
    if (!skip_age) {
      cli::cli_alert_warning("Age column not found, skipping Age_Group")
    }
    data_imp$Age_Group <- NA_character_
  }

  if ("BMI" %in% names(data_imp)) {
    # 不覆盖原始 BMI（可能是暴露变量）；派生 BMI_Group 供亚组
    bmi_num <- suppressWarnings(as.numeric(as.character(data_imp$BMI)))
    if (sum(is.finite(bmi_num)) > 0L) {
      bg <- ifelse(bmi_num < 25, "< 25",
                   ifelse(bmi_num >= 25 & bmi_num < 30, "25-30",
                          ifelse(bmi_num >= 30, "\u2265 30", NA_character_)))
      data_imp$BMI_Group <- factor(bg, levels = c("< 25", "25-30", "\u2265 30"))
      cli::cli_alert_info("BMI_Group: {table(data_imp$BMI_Group)}")
      has_bmi <- TRUE
    } else {
      has_bmi <- FALSE
    }
  } else {
    cli::cli_alert_warning("BMI column not found in data, skipping BMI grouping")
    has_bmi <- FALSE
  }

  id_col <- cfg$data$id_column %||% character(0)
  non_cat <- unique(c(index_var, disease_col, id_col, forbid))

  suf <- sub_cfg$continuous_subgroup_suffix %||% "_subg"
  cont_vars <- sub_cfg$continuous_subgroup_vars %||% character(0)
  cont_only <- isTRUE(sub_cfg$continuous_subgroup_only)
  cont_cuts <- sub_cfg$continuous_subgroup_cutoffs %||% list()
  keep_ab <- !isFALSE(sub_cfg$continuous_subgroup_keep_age_bmi)

  new_cont_sub <- character(0)
  if (length(cont_vars)) {
    for (v in cont_vars) {
      if (!nzchar(v)) next
      if (!v %in% names(data_imp)) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} not in data, skip")
        next
      }
      if (v %in% non_cat) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} is index/outcome/id/time/status, skip")
        next
      }
      xv <- suppressWarnings(as.numeric(data_imp[[v]]))
      if (all(is.na(xv))) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} has no usable numeric values, skip")
        next
      }
      cu <- cont_cuts[[v]]
      if (is.null(cu)) {
        cu <- stats::median(xv, na.rm = TRUE)
      } else {
        cu <- suppressWarnings(as.numeric(cu))
        if (length(cu) < 1L || !is.finite(cu[[1L]])) {
          cu <- stats::median(xv, na.rm = TRUE)
        } else {
          cu <- cu[[1L]]
        }
      }
      newnm <- paste0(v, suf)
      if (newnm %in% names(data_imp)) {
        cli::cli_alert_warning("Column {.field {newnm}} already exists, reuse if categorical")
        if (is.factor(data_imp[[newnm]]) || is.character(data_imp[[newnm]])) {
          new_cont_sub <- c(new_cont_sub, newnm)
        }
        next
      }
      hi <- paste0("\u2265 ", cu)
      lo <- paste0("< ", cu)
      gv <- ifelse(is.na(xv), NA_character_, ifelse(xv >= cu, hi, lo))
      data_imp[[newnm]] <- factor(gv, levels = c(lo, hi))
      new_cont_sub <- c(new_cont_sub, newnm)
      cli::cli_alert_info("Continuous→subgroup {.field {newnm}} (cutoff={round(cu, 4)}) from {.field {v}}")
    }
  }

  if (cont_only && length(new_cont_sub) == 0L) {
    cli::cli_alert_warning(
      "continuous_subgroup_only=TRUE but no valid continuous_subgroup_vars; fallback to auto categorical pool"
    )
    cont_only <- FALSE
  }

  if (length(req)) {
    req_mapped <- character(0)
    for (r in req) {
      col <- r
      if (!skip_age && r %in% c("Age", "Age_Years") && "Age_Group" %in% names(data_imp) &&
          !all(is.na(data_imp$Age_Group))) {
        col <- "Age_Group"
      } else if (r == "Smoke" && !"Smoke" %in% names(data_imp) && "Smoking" %in% names(data_imp)) {
        col <- "Smoking"
      } else if (r == "Smoking" && !"Smoking" %in% names(data_imp) && "Smoke" %in% names(data_imp)) {
        col <- "Smoke"
      } else if (r %in% cont_vars && paste0(r, suf) %in% names(data_imp)) {
        col <- paste0(r, suf)
      } else if (r %in% names(data_imp) &&
                 !(is.factor(data_imp[[r]]) || is.character(data_imp[[r]]))) {
        xv_num <- suppressWarnings(as.numeric(data_imp[[r]]))
        n_u <- length(unique(xv_num[is.finite(xv_num)]))
        if (n_u > 0L && n_u <= 2L) {
          lv <- sort(unique(as.character(data_imp[[r]][!is.na(data_imp[[r]])])))
          data_imp[[r]] <- factor(as.character(data_imp[[r]]), levels = lv)
          cli::cli_alert_info(
            "Required binary\u2192factor {.field {r}}: {paste(lv, collapse = ', ')}"
          )
          col <- r
        } else {
        subnm <- paste0(r, suf)
        if (!subnm %in% names(data_imp)) {
          xv <- xv_num
          if (sum(is.finite(xv)) > 0L) {
            cu <- if (identical(r, index_var)) {
              ctx$results$cutoff_value %||% stats::median(xv, na.rm = TRUE)
            } else {
              stats::median(xv, na.rm = TRUE)
            }
            hi <- paste0("\u2265 ", round(cu, 2))
            lo <- paste0("< ", round(cu, 2))
            gv <- ifelse(is.na(xv), NA_character_, ifelse(xv >= cu, hi, lo))
            data_imp[[subnm]] <- factor(gv, levels = c(lo, hi))
            cli::cli_alert_info(
              "Required numeric\u2192subgroup {.field {subnm}} from {.field {r}} (cutoff={round(cu, 2)})"
            )
          }
        }
        if (subnm %in% names(data_imp)) col <- subnm
        }
      }
      req_mapped <- c(req_mapped, col)
    }
    req <- unique(req_mapped)
  }

  if (isTRUE(cont_only)) {
    prefix_ab <- c()
    if (isTRUE(keep_ab)) {
      if ("Age_Group" %in% names(data_imp) && !all(is.na(data_imp$Age_Group))) prefix_ab <- c(prefix_ab, "Age_Group")
      if (isTRUE(has_bmi) && "BMI_Group" %in% names(data_imp)) prefix_ab <- c(prefix_ab, "BMI_Group")
    }
    categorical_vars <- unique(c(prefix_ab, new_cont_sub))
    cli::cli_alert_info("continuous_subgroup_only=TRUE: subgroup pool = {paste(categorical_vars, collapse=', ')}")
  } else if (identical(var_source, "table1_categorical")) {
    pool_built <- subgroup_build_variable_pool(ctx, data_imp, cfg)
    categorical_vars <- pool_built$vars
    if (length(new_cont_sub)) {
      categorical_vars <- unique(c(categorical_vars, new_cont_sub))
    }
  } else if (identical(var_source, "required") && length(req)) {
    categorical_vars <- req
    if (length(new_cont_sub)) {
      categorical_vars <- unique(c(categorical_vars, new_cont_sub))
    }
  } else {
    # auto_categorical / auto_categorical_incl_low_card / 其它：含低基数数值
    pool_built <- subgroup_build_variable_pool(
      ctx,
      data_imp,
      utils::modifyList(cfg, list(subgroup = utils::modifyList(
        sub_cfg, list(var_source = if (identical(var_source, "auto_categorical")) {
          "auto_categorical_incl_low_card"
        } else {
          var_source
        })
      )))
    )
    categorical_vars <- pool_built$vars
    if (isTRUE(has_bmi) && "BMI_Group" %in% names(data_imp)) {
      categorical_vars <- unique(c(categorical_vars, "BMI_Group"))
      categorical_vars <- setdiff(categorical_vars, "BMI")
    }
    if (length(new_cont_sub)) {
      categorical_vars <- unique(c(categorical_vars, new_cont_sub))
    }
  }

  categorical_vars <- setdiff(unique(categorical_vars), forbid)
  # 低基数数值列转为因子，供后续 min_n 过滤
  if (exists("subgroup_coerce_low_card_numeric_to_factor", mode = "function")) {
    data_imp <- subgroup_coerce_low_card_numeric_to_factor(data_imp, categorical_vars)
  }
  if (length(req) && identical(var_source, "required")) {
    miss <- setdiff(req, names(data_imp))
    if (length(miss)) {
      cli::cli_alert_warning(
        "required_subgroup_vars 不在数据中（已跳过）: {paste(miss, collapse = ', ')}"
      )
      req <- intersect(req, names(data_imp))
      categorical_vars <- intersect(categorical_vars, names(data_imp))
    }
    if (!length(req)) {
      cli::cli_alert_warning("required_subgroup_vars 均不可用，跳过亚组分析")
      return(ctx)
    }
    for (rv in req) {
      if (!is.factor(data_imp[[rv]]) && !is.character(data_imp[[rv]])) {
        stop("config$subgroup$required_subgroup_vars 须为因子或字符型列: ", rv)
      }
    }
    cli::cli_alert_info("Required subgroup vars: {paste(req, collapse=', ')}")
  }
  cli::cli_alert_info("Categorical variables found: {paste(categorical_vars, collapse=', ')}")

  prefix_demo <- c()
  if (!skip_age && "Age_Group" %in% categorical_vars) prefix_demo <- c(prefix_demo, "Age_Group")
  if (isTRUE(has_bmi) && "BMI_Group" %in% categorical_vars) prefix_demo <- c(prefix_demo, "BMI_Group")
  cat_rest <- setdiff(categorical_vars, prefix_demo)
  subgroup_vars <- unique(c(prefix_demo, cat_rest))
  # 暴露变量本身不进亚组分层
  subgroup_vars <- setdiff(subgroup_vars, index_var)
  cli::cli_alert_info("Subgroup variables: {paste(subgroup_vars, collapse=', ')}")

  filtered <- subgroup_apply_min_n_filter(data_imp, subgroup_vars, min_group_size, cfg)
  data_imp <- filtered$data
  subgroup_vars <- filtered$vars
  # 课题显式剔除指定水平（config$subgroup$exclude_levels；如 OR 不可估/NE 行不进森林图）
  if (exists("subgroup_apply_exclude_levels", mode = "function")) {
    excl_res <- subgroup_apply_exclude_levels(data_imp, subgroup_vars, cfg)
    data_imp <- excl_res$data
    subgroup_vars <- excl_res$vars
    if (length(excl_res$dropped_vars)) {
      cli::cli_alert_warning(
        "exclude_levels 后整变量剔除: {paste(excl_res$dropped_vars, collapse=', ')}"
      )
    }
  }
  if (length(req) && identical(var_source, "required")) {
    dropped_req <- setdiff(req, subgroup_vars)
    if (length(dropped_req)) {
      cli::cli_alert_warning(
        "下列 required_subgroup_vars 在 min_n={min_group_size} 过滤后未能保留（已跳过）: ",
        paste(dropped_req, collapse = ", ")
      )
    }
  }
  subgroup_vars <- .sgi02_order_subgroup_vars_clinical(subgroup_vars, req)
  if (length(subgroup_vars) == 0) {
    cli::cli_alert_warning("No valid subgroup variables after filtering")
    return(ctx)
  }
  cli::cli_alert_info("Final subgroup variables: {paste(subgroup_vars, collapse=', ')}")

  if (!index_var %in% names(data_imp)) {
    cli::cli_alert_warning("Index variable '{index_var}' not found in data")
    return(ctx)
  }

  rt <- data_imp

  if (!disease_col %in% names(rt)) {
    cli::cli_alert_warning("Outcome column '{disease_col}' not found (incidence 模式需要 Disease/结局列)")
    return(ctx)
  }
  if (is.character(rt[[disease_col]]) || is.factor(rt[[disease_col]])) {
    rt[[disease_col]] <- ifelse(rt[[disease_col]] == analysis_grp, 1L, 0L)
    cli::cli_alert_info(
      "Converting {.field {disease_col}} to 0/1: '{analysis_grp}' = 1 (case), others = 0"
    )
  }
  rt[[disease_col]] <- as.numeric(rt[[disease_col]])
  rt <- rt[!is.na(rt[[disease_col]]) & rt[[disease_col]] %in% c(0, 1), , drop = FALSE]

  # 连续暴露：与主文 logistic/KM 同分位（默认四分位 Q4 vs Q1）；分类暴露：保留原水平（须 ≥2）
  idx_raw <- rt[[index_var]]
  idx_num <- suppressWarnings(as.numeric(as.character(idx_raw)))
  n_unique_num <- length(unique(stats::na.omit(idx_num)))
  is_cont_idx <- sum(is.finite(idx_num)) >= max(20L, floor(0.5 * nrow(rt))) &&
    n_unique_num > 5L
  forest_cap_mode <- "continuous"
  rt_full_for_n <- NULL
  if (is_cont_idx) {
    grp_method <- as.character(
      (cfg$logistic_quartile_glm %||% list())$scheme %||%
        (cfg$cox_ml_continuous_batch %||% list())$method %||%
        (cfg$km_continuous %||% list())$method %||%
        "quartile"
    )[1L]
    if (!grp_method %in% c("quartile", "tertile")) grp_method <- "quartile"
    store <- ctx$results$continuous_km_cutpoints[[index_var]]
    br <- store$breaks %||% NULL
    store_method <- as.character(store$method %||% "")[1L]
    if ((is.null(br) || !length(br) || !identical(store_method, grp_method)) &&
        exists("pipeline_quantile_breaks", mode = "function")) {
      br <- pipeline_quantile_breaks(idx_num, method = grp_method)
      if (!is.null(br) && exists("pipeline_store_continuous_km_cutpoints", mode = "function")) {
        ctx <- pipeline_store_continuous_km_cutpoints(ctx, index_var, br, method = grp_method)
      }
    }
    if (!exists("pipeline_quantile_group_factor", mode = "function")) {
      stop("subgroup_incidence: 缺少 pipeline_quantile_group_factor", call. = FALSE)
    }
    rt[[index_var]] <- pipeline_quantile_group_factor(idx_num, method = grp_method, breaks = br)
    cli::cli_alert_info(
      "连续暴露 {.field {index_var}} 使用{grp_method}: {paste(levels(rt[[index_var]]), collapse=', ')}"
    )
    ci_mode <- as.character(sub_cfg$continuous_index_mode %||% "highest_vs_lowest")[1L]
    .sgi_full_pop <- !identical(
      as.character(sub_cfg$forest_n_source %||% "full_stratum")[1L], "model_sample"
    )
    if (identical(ci_mode, "median_split")) {
      med <- stats::median(idx_num, na.rm = TRUE)
      rt[[index_var]] <- factor(
        ifelse(idx_num <= med, "Low", "High"),
        levels = c("Low", "High")
      )
      forest_cap_mode <- "median_split"
      cli::cli_alert_info(
        "亚组森林图：连续暴露按中位数二分（High vs Low, median={round(med, 4)}）"
      )
    } else if (!identical(ci_mode, "keep_quantile") && nlevels(rt[[index_var]]) > 2L) {
      lv <- levels(rt[[index_var]])
      keep_lv <- c(lv[1L], lv[length(lv)])
      n0 <- nrow(rt)
      # 保留全分析集用于森林图 N（展示分层样本量，如全部女性）；模型仍只用 Q1+Q4
      rt_full_for_n <- rt
      rt <- rt[as.character(rt[[index_var]]) %in% keep_lv, , drop = FALSE]
      rt[[index_var]] <- factor(as.character(rt[[index_var]]), levels = keep_lv)
      forest_cap_mode <- "highest_vs_lowest"
      cli::cli_alert_info(
        "亚组森林图：连续暴露取最高 vs 最低（{keep_lv[2]} vs {keep_lv[1]}），模型 n {n0} → {nrow(rt)}；图上 N 默认用全分层（mode={ci_mode}）"
      )
    }
  } else {
    if (is.factor(idx_raw) || is.character(idx_raw)) {
      rt[[index_var]] <- factor(trimws(as.character(idx_raw)))
    } else {
      rt[[index_var]] <- factor(as.character(idx_raw))
    }
    rt[[index_var]] <- droplevels(rt[[index_var]])
    n_lv <- nlevels(rt[[index_var]])
    if (n_lv < 2L) {
      cli::cli_alert_warning("分类暴露 {.field {index_var}} 有效水平 <2，跳过亚组")
      return(ctx)
    }
    # 多水平分类暴露：默认「最大类 vs Other」二分，避免 jstable Levels 行爆炸
    # （保持 keep_levels 可改回全水平对比）
    ml_mode <- as.character(sub_cfg$multi_level_index_mode %||% "dichotomize_majority")[1L]
    if (n_lv > 2L && !identical(ml_mode, "keep_levels")) {
      tab <- sort(table(rt[[index_var]]), decreasing = TRUE)
      ref_lv <- names(tab)[1L]
      rt[[index_var]] <- factor(
        ifelse(as.character(rt[[index_var]]) == ref_lv, ref_lv, "Other"),
        levels = c(ref_lv, "Other")
      )
      cli::cli_alert_info(
        "分类暴露 {.field {index_var}} 原 {n_lv} 水平 → 二分（ref={ref_lv} vs Other; mode={ml_mode}）"
      )
    } else {
      cli::cli_alert_info(
        "分类暴露 {.field {index_var}} 按原水平进入亚组: {paste(levels(rt[[index_var]]), collapse=', ')}"
      )
    }
  }
  rt <- rt[!is.na(rt[[index_var]]), , drop = FALSE]

  final_subgroup_vars <- subgroup_vars
  index_cut_col <- paste0(index_var, "_index_cut")
  if (index_cut_col %in% final_subgroup_vars) {
    cli::cli_alert_warning(
      "Excluding {.field {index_cut_col}}: index 已按同一截断值分为 high/low，与该分层完全共线。"
    )
    final_subgroup_vars <- setdiff(final_subgroup_vars, index_cut_col)
  }
  if (length(final_subgroup_vars) == 0L) {
    cli::cli_alert_warning("No subgroup variables left after exclusions")
    return(ctx)
  }
  final_subgroup_vars <- .sgi02_order_subgroup_vars_clinical(final_subgroup_vars, req)
  cli::cli_alert_info("Subgroup table variables: {paste(final_subgroup_vars, collapse=', ')}")

  # 再次剔除调用 jstable 前仍只有 1 个水平的因子（如上游步骤改过 rt）
  ok_lvl <- vapply(final_subgroup_vars, function(v) {
    if (!v %in% names(rt)) return(FALSE)
    x <- rt[[v]]
    if (is.factor(x)) nlevels(droplevels(x)) >= 2L
    else if (is.character(x)) length(unique(stats::na.omit(x))) >= 2L
    else FALSE
  }, logical(1))
  dropped_1lev <- final_subgroup_vars[!ok_lvl]
  if (length(dropped_1lev)) {
    cli::cli_alert_warning(
      "剔除亚组变量（当前数据上有效水平 <2）: {paste(dropped_1lev, collapse=', ')}"
    )
  }
  final_subgroup_vars <- final_subgroup_vars[ok_lvl]
  if (length(final_subgroup_vars) == 0L) {
    cli::cli_alert_warning("无可用亚组变量（均需至少 2 水平），跳过亚组表与森林图")
    return(ctx)
  }

  final_subgroup_vars <- .sgi02_order_subgroup_vars_clinical(final_subgroup_vars, req)
  cli::cli_alert_info("Subgroup table variables (final): {paste(final_subgroup_vars, collapse=', ')}")

  rt <- droplevels(as.data.frame(rt, stringsAsFactors = FALSE))
  rt <- subgroup_apply_level_order(rt, final_subgroup_vars, cfg)

  glm_fam <- sub_cfg$glm_family %||% "binomial"
  ## 调整版亚组（P0-6②）：config$subgroup$adjust_covariates = c("Age", ...) 时
  ## 森林点估计 = 分层内 Q4 vs Q1 + 协变量调整；NULL/空 = 默认 Crude（不变）。
  ## jstable::TableSubgroupMultiGLM 只接受单自变量 formula（多协变量会报
  ## "Formula must contain only 1 independent variable"），故调整版改为
  ## 手动逐层 glm(y ~ Group + covs) 并拼装与 jstable 同构的 res（8 列），
  ## 下游 forest/表格渲染零改动。
  adj_covs <- as.character(sub_cfg$adjust_covariates %||% character(0))
  adj_covs <- adj_covs[nzchar(trimws(adj_covs))]
  adj_covs <- setdiff(adj_covs, c(index_var, disease_col, final_subgroup_vars))
  adj_covs <- intersect(adj_covs, names(rt))
  if (length(adj_covs)) {
    cli::cli_alert_info(
      "亚组森林图（调整版）: Q4 vs Q1 + adjust for {paste(adj_covs, collapse = ', ')}"
    )
    rt$.y01 <- if (is.numeric(rt[[disease_col]]) && all(na.omit(rt[[disease_col]]) %in% c(0, 1))) {
      as.integer(rt[[disease_col]])
    } else if (exists("pipeline_outcome_as_01", mode = "function")) {
      as.integer(pipeline_outcome_as_01(rt[[disease_col]], cfg))
    } else {
      as.integer(as.character(rt[[disease_col]]) == disease_label)
    }
    res <- .sgi02_adjusted_subgroup_glm(
      rt, index_var, final_subgroup_vars, adj_covs, total_n = nrow(rt)
    )
  } else {
    glm_formula <- stats::reformulate(termlabels = index_var, response = disease_col)
    cli::cli_alert_info("Running TableSubgroupMultiGLM (family = {glm_fam})...")
    res <- tryCatch(
      TableSubgroupMultiGLM(
        formula = glm_formula,
        var_subgroups = final_subgroup_vars,
        data = rt,
        family = glm_fam
      ),
      error = function(e) {
        cli::cli_alert_danger("TableSubgroupMultiGLM error: {e$message}")
        NULL
      }
    )
  }
  effect_sym <- "OR"
  arrow_lab <- subgroup_forest_arrow_lab(ref_grp, disease_label)
  # config$subgroup$forest_arrow_lab 可整体覆盖左右箭头标签（课题自定措辞）
  arrow_ov <- as.character(sub_cfg$forest_arrow_lab %||% character(0))
  arrow_ov <- arrow_ov[nzchar(trimws(arrow_ov))]
  if (length(arrow_ov) >= 2L) arrow_lab <- arrow_ov[1:2]

  if (!is.null(res) && is.data.frame(res) && !"Point Estimate" %in% names(res) && "OR" %in% names(res)) {
    io <- which(names(res) == "OR")[[1L]]
    names(res)[io] <- "Point Estimate"
    res[[io]] <- suppressWarnings(as.numeric(as.character(res[[io]])))
  }

  need_cols <- c("Lower", "Upper", "Variable", "Point Estimate")
  res_ok <- !is.null(res) && is.data.frame(res) && nrow(res) > 1L && all(need_cols %in% names(res))
  if (!isTRUE(res_ok)) {
    cli::cli_alert_warning("No valid subgroup table (empty, wrong shape, or error above)")
    return(ctx)
  }

  res <- res[-1, , drop = FALSE]
  if (nrow(res) == 0L) {
    cli::cli_alert_warning("Subgroup table dropped to zero rows after header removal")
    return(ctx)
  }

  # ── 适配 jstable 不同版本列数 ────────────────────────────────────────────
  #  jstable >= 0.x 某版起 GLM 亚组表仅返回 8 列：
  #    Variable, Count, Percent, OR(Point Estimate), Lower, Upper, P value, P for interaction
  #  旧版返回 >= 10 列（含 Crude / Adjusted 分栏等）
  #  统一按「列名定位」代替硬编码下标
  nc_res <- ncol(res)
  cli::cli_alert_info("TableSubgroupMultiGLM returned {nc_res} columns: {paste(names(res), collapse=', ')}")

  plot_df <- subgroup_prepare_forest_plot_df(res, effect_sym)
  if (is.null(plot_df)) {
    cli::cli_alert_warning("No valid subgroup forest table after formatting")
    return(ctx)
  }

  # 图上 N = 该亚组水平在全分析集中的人数（非仅 Q1+Q4）
  n_src <- as.character(sub_cfg$forest_n_source %||% "full_stratum")[1L]
  if (identical(n_src, "full_stratum") &&
      exists("subgroup_stratum_n_map", mode = "function") &&
      exists("subgroup_overlay_forest_count", mode = "function")) {
    data_for_n <- if (!is.null(rt_full_for_n) && is.data.frame(rt_full_for_n)) {
      rt_full_for_n
    } else {
      NULL
    }
    # rt_full_for_n 仅在连续暴露 highest_vs_lowest 时有；否则无需覆盖
    if (!is.null(data_for_n)) {
      n_map <- subgroup_stratum_n_map(data_for_n, final_subgroup_vars, .sgi02_pretty_subgroup_label)
      plot_df <- subgroup_overlay_forest_count(
        plot_df, n_map, total_n = nrow(data_for_n), n_source = n_src
      )
      if ("Count" %in% names(res)) {
        res <- subgroup_overlay_forest_count(
          res, n_map, total_n = nrow(data_for_n), n_source = n_src
        )
      }
    }
  }

  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
    ov <- if (exists("pub_figure_profile_forest_overrides", mode = "function")) {
      pub_figure_profile_forest_overrides(ctx$config)
    } else {
      list(ci_col = "#1B4F72", highlight_interaction_sig = TRUE)
    }
    if (!is.null(ov$ci_col)) sub_cfg$forest_ci_col <- ov$ci_col
    if (isTRUE(ov$highlight_interaction_sig)) {
      sub_cfg$forest_highlight_interaction_sig <- TRUE
    }
  }

  fig_cap <- if (exists("pipeline_subgroup_forest_caption", mode = "function")) {
    pipeline_subgroup_forest_caption(index_var, mode = forest_cap_mode %||% "highest_vs_lowest")
  } else {
    paste0("Subgroup Forest analyses of ", index_var)
  }
  subgroup_render_forest_figure(
    ctx, plot_df, final_subgroup_vars, sub_cfg,
    fig_caption = fig_cap,
    effect_sym = effect_sym,
    arrow_lab = arrow_lab
  )

  # ── 导出亚组分析表格 ──────────────────────────────────────────────────────
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  tbl_export <- res
  # 将下划线替换为空格，与森林图标签保持一致
  if ("Variable" %in% names(tbl_export)) {
    tbl_export$Variable <- gsub("_", " ", as.character(tbl_export$Variable), fixed = TRUE)
  }
  # 格式化数值列（Point Estimate / Lower / Upper / P）
  fmt_tbl_num <- function(x) ifelse(is.na(suppressWarnings(as.numeric(x))), as.character(x),
                                    fmt_num(as.numeric(x)))
  for (cn in c("Point Estimate", "Lower", "Upper")) {
    if (cn %in% names(tbl_export)) {
      tbl_export[[cn]] <- fmt_tbl_num(tbl_export[[cn]])
    }
  }
  # P 值格式化
  for (cn in grep("^[Pp]", names(tbl_export), value = TRUE)) {
    pv <- suppressWarnings(as.numeric(tbl_export[[cn]]))
    tbl_export[[cn]] <- ifelse(is.na(pv), as.character(tbl_export[[cn]]),
                               ifelse(pv < 0.001, "<0.001",
                                      formatC(round(pv, 3), format = "f", digits = 3)))
  }
  # 添加 HR/OR (95% CI) 合并列（若原始结果包含置信区间列）
  if (all(c("Point Estimate", "Lower", "Upper") %in% names(tbl_export))) {
    tbl_export[[paste0(effect_sym, " (95% CI)")]] <- ifelse(
      is.na(suppressWarnings(as.numeric(res$`Point Estimate`))), "",
      sprintf("%s (%s\u2013%s)",
              fmt_num(as.numeric(res$`Point Estimate`)),
              fmt_num(as.numeric(res$Lower)),
              fmt_num(as.numeric(res$Upper)))
    )
  }

  # 亚组已有森林图，默认不再导出 Table_Subgroup_Analysis_*（可用 export_table=TRUE）
  if (isTRUE(sub_cfg$export_table %||% FALSE)) {
    index_stub <- gsub("[^A-Za-z0-9_]+", "_", as.character(index_var)[1L])
    tbl_fn <- sub_cfg$table_filename %||% paste0("Table_Subgroup_Analysis_", index_stub, ".xlsx")
    tbl_fp <- if (exists(".inject_db_into_pub_filepath", mode = "function")) {
      .inject_db_into_pub_filepath(file.path(tbl_dir, tbl_fn))
    } else {
      file.path(tbl_dir, tbl_fn)
    }
    tbl_title <- sub_cfg$table_title %||% paste0(
      "Subgroup Analysis of ", index_var,
      " on ", cfg$project$disease %||% "Outcome",
      " (", effect_sym, ", ", study_type, ")"
    )
    tryCatch(
      {
        export_sci_table(tbl_export, tbl_fp, title = tbl_title)
        cli::cli_alert_success("Subgroup table saved: {.file {basename(tbl_fp)}}")
      },
      error = function(e) cli::cli_alert_warning("亚组表格导出失败: {e$message}")
    )
  }

  ctx$results$subgroup <- res
  ctx$results$subgroup_vars_used <- final_subgroup_vars
  ctx$results$subgroup_study_type <- study_type
  ctx$results$subgroup_effect <- effect_sym
  cli::cli_alert_success("Subgroup analysis completed ({study_type}, {effect_sym})")

  ctx
}

register_block(
  "subgroup_incidence",
  block_subgroup_incidence,
  "subgroup_incidence（发病亚组森林图，Logistic OR）"
)
