###############################################################################
#  subgroup_prognosis — 预后亚组森林图（index 高/低 × 分类亚组，jstable Cox HR + forestploter）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_config = config$subgroup, survival$time_var/event_var, logistic$index_var
#
#  读 config$subgroup；暴露/结局见 survival$index_var、time_var、event_var。
###############################################################################

.sgp01_canonical_subgroup_order_vec <- function() {
  c(
    # —— 人口学 ——
    "Age_Group",
    "BMI_Group",
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
    "Insurance",   # 保险属人口学/社会经济，不入共病
    "Micu_Code",
    "Ventilation",
    # —— 共病 / 临床 ——
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

.sgp01_order_subgroup_vars_clinical <- function(v, req_ord) {
  v <- unique(as.character(v))
  canon <- .sgp01_canonical_subgroup_order_vec()
  in_canon <- intersect(canon, v)
  loose <- sort(setdiff(v, canon))
  c(in_canon, loose)
}

.sgp01_pretty_subgroup_label <- function(x) {
  x <- as.character(x %||% "")
  # 仅下划线→空格；勿把区间连字符「30-44」抹成「30 44」（Fig 6 等森林图标签）
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  trimws(x)
}

block_subgroup_prognosis <- function(ctx, ...) {
  cfg <- ctx$config
  surv <- cfg$survival %||% list()
  time_col_early <- as.character(surv$time_var %||% surv$time_column %||% "")[1L]
  if (!nzchar(time_col_early)) {
    cli::cli_alert_info("subgroup_prognosis: 无 survival$time_var，跳过 HR 亚组。")
    return(ctx)
  }

  suppressPackageStartupMessages({
    library(jstable)
    library(forestploter)
    library(grid)
  })
  if (!exists("subgroup_render_forest_figure", mode = "function") ||
      !exists("subgroup_prepare_forest_plot_df", mode = "function")) {
    # worker cwd / project$root 常为课题目录；必须优先 MEDICAL_BLOCKS_ROOT
    candidates <- unique(c(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
      as.character(ctx$config$project$root %||% ""),
      getwd()
    ))
    root_sf <- NA_character_
    for (r in candidates) {
      if (nzchar(r) && file.exists(file.path(r, "R", "subgroup_forest_plot.R"))) {
        root_sf <- r
        break
      }
    }
    if (!nzchar(root_sf %||% "")) {
      stop("subgroup_prognosis: 找不到 R/subgroup_forest_plot.R（请设置 MEDICAL_BLOCKS_ROOT）",
           call. = FALSE)
    }
    suppressWarnings(source(file.path(root_sf, "R", "subgroup_forest_plot.R"), local = FALSE))
  }
  if (!exists("subgroup_build_variable_pool", mode = "function") ||
      !exists("subgroup_coerce_low_card_numeric_to_factor", mode = "function")) {
    candidates <- unique(c(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
      as.character(ctx$config$project$root %||% ""),
      getwd()
    ))
    root_sv <- NA_character_
    for (r in candidates) {
      if (nzchar(r) && file.exists(file.path(r, "R", "subgroup_vars.R"))) {
        root_sv <- r
        break
      }
    }
    if (nzchar(root_sv %||% "")) {
      suppressWarnings(source(file.path(root_sv, "R", "subgroup_vars.R"), local = FALSE))
    }
  }

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  data_imp <- as.data.frame(data_imp)

  log_idx <- cfg$logistic$index_var
  if (is.null(log_idx)) stop("index_var is required in config$logistic")

  study_type <- "prognosis"

  # subgroup_prognosis 覆盖 subgroup（如 continuous_index_mode / forest_*）
  sub_cfg <- utils::modifyList(cfg$subgroup %||% list(), cfg$subgroup_prognosis %||% list())
  inc_cfg <- cfg$incidence %||% list()
  time_col <- surv$time_var %||% surv$time_column %||% "futime"
  status_col <- surv$event_var %||% surv$status_column %||% surv$event_column %||% "fustatus"

  index_var <- as.character(
    cfg$prediction$index_vars %||%
      cfg$ml_batch$index_vars %||%
      surv$index_var %||%
      log_idx
  )
  index_var <- index_var[nzchar(trimws(index_var))]
  if (!length(index_var)) stop("index_var is required", call. = FALSE)
  index_var <- index_var[[1L]]
  disease_col <- cfg$data$outcome_column %||% "fustatus"

  analysis_grp <- cfg$project$analysis_group %||% cfg$project$disease
  ref_grp <- cfg$project$reference_group %||% "Control"
  disease_label <- analysis_grp

  cli::cli_alert_info("Subgroup mode: {study_type} (outcome column: {.field {disease_col}})")
  cli::cli_alert_info("Index variable: {index_var}")
  cli::cli_alert_info("Case / positive label: {disease_label}")

  raw_min_n <- sub_cfg$min_n %||% 20
  if (!is.numeric(raw_min_n) || length(raw_min_n) != 1L || is.na(raw_min_n)) {
    stop("config$subgroup$min_n 必须是数值（绝对人数，或 0~1 之间比例）。", call. = FALSE)
  }
  if (raw_min_n > 0 && raw_min_n < 1) {
    min_group_size <- max(1L, as.integer(ceiling(nrow(data_imp) * raw_min_n)))
    cli::cli_alert_info(
      "Subgroup min_n 使用比例模式: {raw_min_n} × {nrow(data_imp)} = {min_group_size}"
    )
  } else {
    min_group_size <- max(1L, as.integer(raw_min_n))
  }
  age_cut <- sub_cfg$age_cutoff %||% 65
  var_source <- sub_cfg$var_source %||% (cfg$subgroup %||% list())$var_source %||% "table1_categorical"
  forbid <- unique(c(
    sub_cfg$forbid_subgroup_vars %||% character(0),
    sub_cfg$exclude_vars %||% character(0)
  ))
  req <- as.character(
    sub_cfg$required_subgroup_vars %||%
      (cfg$subgroup %||% list())$required_subgroup_vars %||%
      character(0)
  )
  req <- unique(req[nzchar(req)])
  ## var_source=required 时若名单空则回退 vars
  if (identical(var_source, "required") && !length(req)) {
    req <- as.character(sub_cfg$vars %||% character(0))
    req <- unique(req[nzchar(req)])
  }
  if (length(intersect(req, forbid))) {
    stop(
      "config$subgroup: required_subgroup_vars 与 forbid/exclude 冲突: ",
      paste(intersect(req, forbid), collapse = ", ")
    )
  }

  age_lo <- paste0("< ", age_cut)
  age_hi <- paste0("\u2265 ", age_cut)
  if (!"Age" %in% names(data_imp)) {
    cli::cli_alert_warning("Age column not found, skipping Age_Group")
    data_imp$Age_Group <- NA_character_
  } else {
    data_imp$Age_Group <- ifelse(data_imp$Age < age_cut, age_lo, age_hi)
    data_imp$Age_Group <- factor(data_imp$Age_Group, levels = c(age_lo, age_hi))
    agt <- table(data_imp$Age_Group, useNA = "ifany")
    cli::cli_alert_info(
      "Age grouping (cutoff {age_cut}): {paste(paste0(names(agt), '=', as.integer(agt)), collapse=', ')}"
    )
  }

  if ("BMI" %in% names(data_imp)) {
    # 不覆盖原始 BMI（连续值进 Table 1）；派生 BMI_Group 供亚组分层
    bmi_num <- suppressWarnings(as.numeric(as.character(data_imp$BMI)))
    if (sum(is.finite(bmi_num)) > 0L) {
      if (exists("dual_db_make_bmi_group", mode = "function")) {
        data_imp$BMI_Group <- dual_db_make_bmi_group(bmi_num)
      } else {
        bg <- ifelse(
          !is.finite(bmi_num), NA_character_,
          ifelse(bmi_num < 25, "< 25",
                 ifelse(bmi_num < 30, "25-30", "\u2265 30"))
        )
        data_imp$BMI_Group <- factor(bg, levels = c("< 25", "25-30", "\u2265 30"))
      }
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
  # 暴露本身及其分位/二分列不得进亚组分层（否则森林图末尾会出现 Q1/Q4 NE 块）
  ix_extra <- character(0)
  if (grepl("^[A-Za-z0-9_]+$", index_var)) {
    ix_extra <- grep(
      paste0("^", index_var, "(_|\\s)(quartile|tertile|binary|group|cut)"),
      names(data_imp),
      value = TRUE,
      ignore.case = TRUE
    )
  }
  ix_exposure_cols <- unique(c(
    index_var,
    paste0(index_var, c(
      "_quartile", "_tertile", "_binary", "_group", "_index_cut", "_cut"
    )),
    ix_extra
  ))
  non_cat <- unique(c(ix_exposure_cols, disease_col, id_col, time_col, status_col))

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
      if (r %in% c("Age", "Age_Years") && "Age_Group" %in% names(data_imp) &&
          !all(is.na(data_imp$Age_Group))) {
        col <- "Age_Group"
      } else if (identical(r, "BMI") && "BMI_Group" %in% names(data_imp) &&
                 !all(is.na(data_imp$BMI_Group))) {
        col <- "BMI_Group"
      } else if (r %in% cont_vars && paste0(r, suf) %in% names(data_imp)) {
        col <- paste0(r, suf)
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
  } else {
    ## 编码为数字的分期/等级：先转 factor（如 rAFS_Stage）
    force_fac <- unique(c(
      as.character(cfg$force_factor_vars %||% character(0)),
      as.character(sub_cfg$force_factor_vars %||% character(0))
    ))
    force_fac <- intersect(force_fac[nzchar(force_fac)], names(data_imp))
    if (length(force_fac)) {
      for (v in force_fac) {
        if (!is.factor(data_imp[[v]]) && !is.character(data_imp[[v]])) {
          data_imp[[v]] <- factor(data_imp[[v]])
        }
      }
      cli::cli_alert_info(
        "force_factor_vars 已转为分类亚组候选: {paste(force_fac, collapse = ', ')}"
      )
    }

    vs <- as.character(var_source %||% "table1_categorical")[1L]
    if (identical(vs, "auto_categorical") ||
        identical(vs, "auto_categorical_incl_low_card")) {
      if (exists("subgroup_build_variable_pool", mode = "function")) {
        pool_built <- subgroup_build_variable_pool(
          ctx, data_imp,
          utils::modifyList(cfg, list(subgroup = utils::modifyList(
            sub_cfg,
            list(var_source = if (identical(vs, "auto_categorical")) {
              "auto_categorical_incl_low_card"
            } else {
              vs
            })
          )))
        )
        categorical_vars <- pool_built$vars
      } else if (exists("subgroup_auto_categorical_candidates", mode = "function")) {
        max_lv <- as.integer(sub_cfg$auto_categorical_max_levels %||% 5L)[1L]
        categorical_vars <- subgroup_auto_categorical_candidates(
          data_imp, forbid = unique(c(non_cat, forbid)), max_levels = max_lv
        )
      } else {
        categorical_vars <- names(data_imp)[vapply(
          data_imp, function(x) is.factor(x) || is.character(x), logical(1L)
        )]
      }
    } else if (identical(vs, "table1_categorical") &&
               exists("subgroup_build_variable_pool", mode = "function")) {
      pool_built <- subgroup_build_variable_pool(ctx, data_imp, cfg)
      categorical_vars <- pool_built$vars
    } else {
      categorical_vars <- names(data_imp)[vapply(
        data_imp, function(x) is.factor(x) || is.character(x), logical(1L)
      )]
    }
    categorical_vars <- categorical_vars[!categorical_vars %in% non_cat]
    if (length(force_fac)) {
      categorical_vars <- unique(c(categorical_vars, force_fac))
    }
    if (length(new_cont_sub)) {
      categorical_vars <- unique(c(categorical_vars, new_cont_sub))
    }
    if (exists("subgroup_coerce_low_card_numeric_to_factor", mode = "function")) {
      data_imp <- subgroup_coerce_low_card_numeric_to_factor(data_imp, categorical_vars)
    }
  }

  if (length(forbid)) {
    categorical_vars <- setdiff(categorical_vars, forbid)
    cli::cli_alert_info("Forbid subgroup vars (removed from pool): {paste(forbid, collapse=', ')}")
  }
  if (length(req)) {
    miss <- setdiff(req, names(data_imp))
    if (length(miss)) {
      # 双库/跨库：缺列跳过；pause_enable=FALSE 时同样软跳过，避免整指标失败
      soft <- isTRUE(sub_cfg$restrict_to_required %||% FALSE) ||
        isFALSE(sub_cfg$pause_enable %||% TRUE)
      if (soft) {
        cli::cli_alert_warning(
          "required_subgroup_vars 不在数据中（已跳过）: {paste(miss, collapse = ', ')}"
        )
        req <- intersect(req, names(data_imp))
      } else {
        stop("config$subgroup$required_subgroup_vars 不在数据中: ", paste(miss, collapse = ", "))
      }
    }
    for (rv in req) {
      if (!rv %in% names(data_imp)) next
      if (!is.factor(data_imp[[rv]]) && !is.character(data_imp[[rv]])) {
        ## 允许低基数 numeric / force_factor：先转 factor 再进亚组
        data_imp[[rv]] <- factor(data_imp[[rv]])
        cli::cli_alert_info("required_subgroup_vars {.field {rv}} 已转为 factor")
      }
    }
    cli::cli_alert_info("Required subgroup vars: {paste(req, collapse=', ')}")
    if (isTRUE(sub_cfg$restrict_to_required %||% FALSE)) {
      categorical_vars <- intersect(categorical_vars, req)
      cli::cli_alert_info(
        "restrict_to_required=TRUE: 仅保留统一亚组名单 {paste(categorical_vars, collapse=', ')}"
      )
    }
  }
  cli::cli_alert_info("Categorical variables found: {paste(categorical_vars, collapse=', ')}")

  prefix_demo <- c()
  if ("Age_Group" %in% categorical_vars) prefix_demo <- c(prefix_demo, "Age_Group")
  if (isTRUE(has_bmi) && "BMI_Group" %in% names(data_imp)) {
    categorical_vars <- unique(c(categorical_vars, "BMI_Group"))
  }
  if (isTRUE(has_bmi) && "BMI_Group" %in% categorical_vars) prefix_demo <- c(prefix_demo, "BMI_Group")
  # 连续 BMI 不应作为分类亚组（避免与暴露三分位冲突）
  categorical_vars <- setdiff(categorical_vars, "BMI")
  cat_rest <- setdiff(categorical_vars, prefix_demo)
  subgroup_vars <- unique(c(prefix_demo, cat_rest))
  cli::cli_alert_info("Subgroup variables: {paste(subgroup_vars, collapse=', ')}")

  if (exists("subgroup_apply_min_n_filter", mode = "function")) {
    filtered <- subgroup_apply_min_n_filter(data_imp, subgroup_vars, min_group_size, cfg)
    data_imp <- filtered$data
    subgroup_vars <- filtered$vars
  } else {
    vars_to_keep <- c()
    for (v in subgroup_vars) {
      if (v == "Age_Group" && all(is.na(data_imp[[v]]))) next
      if (v %in% names(data_imp)) {
        if (is.factor(data_imp[[v]]) || is.character(data_imp[[v]])) {
          if (is.character(data_imp[[v]])) {
            data_imp[[v]] <- as.factor(data_imp[[v]])
          }
          group_counts <- table(data_imp[[v]])
          valid_levels <- names(group_counts[group_counts >= min_group_size])
          if (length(valid_levels) >= 2L) {
            data_imp[[v]] <- factor(data_imp[[v]], levels = valid_levels)
            data_imp <- data_imp[!is.na(data_imp[[v]]), ]
            vars_to_keep <- c(vars_to_keep, v)
          }
        }
      }
    }
    subgroup_vars <- vars_to_keep
  }
  if (length(req)) {
    dropped_req <- setdiff(req, subgroup_vars)
    if (length(dropped_req)) {
      cli::cli_alert_warning(
        "下列 required_subgroup_vars 在 min_n={min_group_size} 过滤后未能保留（已跳过）: ",
        paste(dropped_req, collapse = ", ")
      )
    }
  }
  # 闸门 D：双库锁定名单优先（两库 Figure 5 亚组变量必须一致）
  locked <- as.character(
    sub_cfg$locked_subgroup_vars %||%
      (cfg$subgroup %||% list())$locked_subgroup_vars %||%
      character(0)
  )
  locked <- locked[nzchar(locked)]
  if (!length(locked) && isTRUE((cfg$dual_db %||% list())$enable) &&
      exists("dual_db_load_subgroup_lock", mode = "function")) {
    root_lk <- cfg$project$root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    lock_obj <- dual_db_load_subgroup_lock(root_lk, cfg)
    if (!is.null(lock_obj)) locked <- as.character(lock_obj$vars %||% character(0))
  }
  if (length(locked)) {
    # Age / Age_Group 别名对齐
    if ("Age" %in% locked && !"Age_Group" %in% locked && "Age_Group" %in% subgroup_vars) {
      locked <- unique(c(setdiff(locked, "Age"), "Age_Group"))
    }
    before <- subgroup_vars
    subgroup_vars <- intersect(locked, subgroup_vars)
    # 锁定名单中本地仍具备 ≥2 水平的变量全部保留；本地刚被 min_n 剔除的不再强行塞入
    extra_drop <- setdiff(before, subgroup_vars)
    if (length(extra_drop)) {
      cli::cli_alert_info(
        "闸门 D 锁定：本地再剔除 {paste(extra_drop, collapse=', ')}（两库统一）"
      )
    }
    miss_lock <- setdiff(locked, before)
    if (length(miss_lock)) {
      cli::cli_alert_info(
        "闸门 D 锁定名单中本地不可用（已跳过）: {paste(miss_lock, collapse=', ')}"
      )
    }
    subgroup_vars <- locked[locked %in% subgroup_vars]
    cli::cli_alert_success(
      "闸门 D：使用双库统一亚组变量 {length(subgroup_vars)} 个 — {paste(subgroup_vars, collapse=', ')}"
    )
  }
  subgroup_vars <- .sgp01_order_subgroup_vars_clinical(subgroup_vars, req)
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

  if (!time_col %in% names(rt)) {
    cli::cli_alert_warning("Time column '{time_col}' not found, skipping subgroup analysis")
    return(ctx)
  }
  if (!status_col %in% names(rt)) {
    cli::cli_alert_warning("Status column '{status_col}' not found, skipping subgroup analysis")
    return(ctx)
  }
  rt[[time_col]] <- as.numeric(rt[[time_col]])
  if (is.character(rt[[status_col]]) || is.factor(rt[[status_col]])) {
    status_values <- unique(rt[[status_col]])
    event_value <- surv$event_value %||% disease_label
    if (!(event_value %in% status_values)) {
      event_value <- status_values[2]
    }
    rt[[status_col]] <- ifelse(rt[[status_col]] == event_value, 1, 0)
    cli::cli_alert_info("Converting {status_col} to numeric: '{event_value}' = 1, others = 0")
  }
  rt[[status_col]] <- as.numeric(rt[[status_col]])

  # 连续暴露：与 Cox/KM 共享分位分组（默认四分位）；分类暴露保持原逻辑
  idx_raw <- rt[[index_var]]
  idx_num <- suppressWarnings(as.numeric(as.character(idx_raw)))
  n_unique_num <- length(unique(stats::na.omit(idx_num)))
  is_cont_idx <- (is.numeric(idx_raw) && n_unique_num > 4L) ||
    ((!is.factor(idx_raw) && !is.character(idx_raw)) &&
       is.numeric(idx_num) && n_unique_num > 4L)
  forest_cap_mode <- "continuous"
  rt_full_for_n <- NULL
  .sgp_fold_end_lv <- NULL
  # 引擎默认（发表铁律）：亚组森林 = 全分析集估计（与主文 Cox Table 同人群同分位），
  # 各层报告「最高 vs 最低」分位对比；N 与 HR 同分母。旧「仅 Q1+Q4 子集」口径
  # 仅在 forest_n_source="model_sample" 时保留。
  .sgp_full_pop_default <- !identical(
    as.character(sub_cfg$forest_n_source %||% "full_stratum")[1L], "model_sample"
  ) && !isTRUE(sub_cfg$exposure_continuous %||% FALSE)
  if (is_cont_idx) {
    grp_method <- subgroup_resolve_main_scheme(
      ctx, cfg,
      default = as.character(
        (cfg$cox_ml_continuous_batch %||% list())$method %||%
          (cfg$km_continuous %||% list())$method %||%
          "quartile"
      )[1L]
    )
    if (identical(grp_method, "binary")) grp_method <- "quartile"
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
      stop("subgroup_prognosis: 缺少 pipeline_quantile_group_factor", call. = FALSE)
    }
    rt[[index_var]] <- pipeline_quantile_group_factor(idx_num, method = grp_method, breaks = br)
    cli::cli_alert_info(
      "连续暴露 {.field {index_var}} 使用{grp_method}: {paste(levels(rt[[index_var]]), collapse=', ')}"
    )
    # 森林图默认只保留最高 vs 最低（Q4 vs Q1 / T3 vs T1），避免每层 3 条 HR 把图拆成多页；
    # 与经典亚组森林图（每层一个效应量）一致。keep_quantile 可改回全分位。
    ci_mode <- as.character(sub_cfg$continuous_index_mode %||% "highest_vs_lowest")[1L]
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
      if (.sgp_full_pop_default &&
          exists("subgroup_collapse_middle_levels", mode = "function")) {
        # 全人群：中间分位并为 Middle（不删行）；Q4 vs Q1 对比系数不变，N 同分母
        rt[[index_var]] <- subgroup_collapse_middle_levels(rt[[index_var]], levels = lv)
        forest_cap_mode <- "highest_vs_lowest"
        .sgp_fold_end_lv <- keep_lv[2L]
        cli::cli_alert_info(
          "亚组森林图：全分析集估计（n={n0}），各层报告 {keep_lv[2]} vs {keep_lv[1]}（中间分位并为 Middle；mode={ci_mode}）"
        )
      } else {
        rt_full_for_n <- rt
        rt <- rt[as.character(rt[[index_var]]) %in% keep_lv, , drop = FALSE]
        rt[[index_var]] <- factor(as.character(rt[[index_var]]), levels = keep_lv)
        forest_cap_mode <- "highest_vs_lowest"
        cli::cli_alert_info(
          "亚组森林图：连续暴露取最高 vs 最低（{keep_lv[2]} vs {keep_lv[1]}），模型 n {n0} → {nrow(rt)}；图上 N 默认用全分层（mode={ci_mode}）"
        )
      }
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
  drop_ix <- intersect(final_subgroup_vars, ix_exposure_cols)
  if (length(drop_ix)) {
    cli::cli_alert_warning(
      "Excluding exposure strata from subgroup forest: {paste(drop_ix, collapse = ', ')}"
    )
    final_subgroup_vars <- setdiff(final_subgroup_vars, drop_ix)
  }
  index_cut_col <- paste0(index_var, "_index_cut")
  if (index_cut_col %in% final_subgroup_vars) {
    cli::cli_alert_warning(
      "Excluding {.field {index_cut_col}}: index 已按同一截断值分为分组水平，与该分层完全共线。"
    )
    final_subgroup_vars <- setdiff(final_subgroup_vars, index_cut_col)
  }
  if (length(final_subgroup_vars) == 0L) {
    cli::cli_alert_warning("No subgroup variables left after exclusions")
    return(ctx)
  }
  final_subgroup_vars <- .sgp01_order_subgroup_vars_clinical(final_subgroup_vars, req)
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

  final_subgroup_vars <- .sgp01_order_subgroup_vars_clinical(final_subgroup_vars, req)
  cli::cli_alert_info("Subgroup table variables (final): {paste(final_subgroup_vars, collapse=', ')}")

  rt <- droplevels(as.data.frame(rt, stringsAsFactors = FALSE))
  for (vv in final_subgroup_vars) {
    if (vv %in% names(rt) && (is.character(rt[[vv]]) || is.factor(rt[[vv]]))) {
      rt[[vv]] <- factor(rt[[vv]])
    }
  }
  rt <- droplevels(rt)

  cox_formula <- as.formula(paste("Surv(", time_col, ", ", status_col, ") ~ ", index_var, sep = ""))
  cli::cli_alert_info("Running TableSubgroupMultiCox...")
  res <- tryCatch(
    TableSubgroupMultiCox(
      formula = cox_formula,
      var_subgroups = final_subgroup_vars,
      data = rt
    ),
    error = function(e) {
      cli::cli_alert_danger("TableSubgroupMultiCox error: {e$message}")
      NULL
    }
  )
  effect_sym <- "HR"
  # 箭头文案宜短，避免左右裁字；可用 forest_arrow_lab 覆盖
  arrow_lab <- if (!is.null(sub_cfg$forest_arrow_lab) && length(sub_cfg$forest_arrow_lab) >= 2L) {
    as.character(sub_cfg$forest_arrow_lab)[1:2]
  } else {
    c("Decreased risk", "Increased risk")
  }

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

  # 全人群折叠：每层只保留「最高 vs 最低」对比行（Count=层全量 n）
  if (!is.null(.sgp_fold_end_lv) &&
      exists("subgroup_fold_quantile_contrast_rows", mode = "function")) {
    res <- subgroup_fold_quantile_contrast_rows(res, index_var, .sgp_fold_end_lv)
    if (!is.data.frame(res) || !nrow(res)) {
      cli::cli_alert_warning("Subgroup table empty after quantile fold")
      return(ctx)
    }
  }

  res <- res[-1, , drop = FALSE]
  if (nrow(res) == 0L) {
    cli::cli_alert_warning("Subgroup table dropped to zero rows after header removal")
    return(ctx)
  }

  # 去掉 Overall / 暴露本身（Q1–Q4）块：亚组森林只保留分层变量
  if (exists("subgroup_drop_exposure_overall_block", mode = "function")) {
    res <- subgroup_drop_exposure_overall_block(res, index_var, final_subgroup_vars)
  } else {
    var0 <- trimws(as.character(res$Variable %||% ""))
    is_hdr0 <- !grepl("^\\s+", as.character(res$Variable %||% ""))
    sg_ok <- unique(c(
      final_subgroup_vars,
      gsub("_", " ", final_subgroup_vars, fixed = TRUE)
    ))
    ix_pat <- paste0(
      "^(", gsub("([\\W])", "\\\\\\1", index_var),
      "|Overall|Total|All)(\\s+(quartile|tertile|group))?$"
    )
    keep0 <- rep(TRUE, nrow(res))
    i0 <- 1L
    while (i0 <= nrow(res)) {
      if (is_hdr0[i0]) {
        v0 <- var0[i0]
        drop_blk <- grepl(ix_pat, v0, ignore.case = TRUE) ||
          !(v0 %in% sg_ok || !nzchar(v0))
        # 空 Variable 标题也丢掉（jstable Overall 残行）
        if (!nzchar(v0) || drop_blk) {
          keep0[i0] <- FALSE
          j0 <- i0 + 1L
          while (j0 <= nrow(res) && !is_hdr0[j0]) {
            keep0[j0] <- FALSE
            j0 <- j0 + 1L
          }
          i0 <- j0
          next
        }
      }
      i0 <- i0 + 1L
    }
    n_drop <- sum(!keep0)
    if (n_drop > 0L) {
      cli::cli_alert_info("subgroup_prognosis: 已去掉 Overall/暴露块 {n_drop} 行")
      res <- res[keep0, , drop = FALSE]
    }
  }
  if (!nrow(res)) {
    cli::cli_alert_warning("Subgroup table empty after dropping Overall/exposure block")
    return(ctx)
  }

  nc_res <- ncol(res)
  cli::cli_alert_info(
    "TableSubgroupMultiCox returned {nc_res} columns: {paste(names(res), collapse=', ')}"
  )

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
    if (!is.null(data_for_n)) {
      pretty_fn <- if (exists(".sgp01_pretty_subgroup_label", mode = "function")) {
        .sgp01_pretty_subgroup_label
      } else if (exists("subgroup_pretty_label", mode = "function")) {
        subgroup_pretty_label
      } else {
        function(x) gsub("_", " ", as.character(x), fixed = TRUE)
      }
      n_map <- subgroup_stratum_n_map(data_for_n, final_subgroup_vars, pretty_fn)
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

  subgroup_render_forest_figure(
    ctx, plot_df, final_subgroup_vars, sub_cfg,
    fig_caption = if (exists("pipeline_subgroup_forest_caption", mode = "function")) {
      pipeline_subgroup_forest_caption(
        index_var,
        mode = forest_cap_mode %||%
          as.character(sub_cfg$continuous_index_mode %||% "highest_vs_lowest")[1L]
      )
    } else {
      paste0("Subgroup Forest analyses of ", index_var)
    },
    effect_sym = effect_sym,
    arrow_lab = arrow_lab
  )

  # ── 导出亚组分析表格（默认关闭：与森林图重复；export_table=TRUE 时导出）──
  if (!isTRUE(sub_cfg$export_table %||% FALSE)) {
    cli::cli_alert_info("subgroup_prognosis: export_table=FALSE，跳过亚组数值表（森林图已覆盖）")
  } else {
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

  tbl_pub <- pub_pair(
    ctx, tbl_dir, "main_table",
    title_caption = paste0(
      "Subgroup Analysis of ", index_var,
      " on ", cfg$project$disease %||% "Outcome",
      " (", effect_sym, ", ", study_type, ")"
    ),
    file_caption = paste0("Subgroup Analysis of ", index_var),
    ext = "xlsx"
  )
  tryCatch(
    export_sci_table(tbl_export, tbl_pub$filepath, title = tbl_pub$title),
    error = function(e) cli::cli_alert_warning("亚组表格导出失败: {e$message}")
  )
  if (exists("render_queued_tables", mode = "function")) {
    ctx <- render_queued_tables(ctx)
  }
  } # end export_table

  ctx$results$subgroup <- res
  ctx$results$subgroup_vars_used <- final_subgroup_vars
  ctx$results$subgroup_study_type <- study_type
  ctx$results$subgroup_effect <- effect_sym
  cli::cli_alert_success("Subgroup analysis completed ({study_type}, {effect_sym})")

  ctx
}

register_block(
  "subgroup_prognosis",
  block_subgroup_prognosis,
  "预后亚组森林图（连续暴露三分位 / 分类暴露 × 分类亚组，Cox HR + forestploter）"
)
