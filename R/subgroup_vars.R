###############################################################################
#  subgroup_vars.R — 亚组变量池：Table 1 分类变量 + 双库人口学/临床规则 + min_n
###############################################################################

.subgroup_index_group_cols <- function() {
  c("Index_Group", "Index_Group_Tertile", "Index_Group_Quartile", "MCV_RCS_Group")
}

subgroup_resolve_min_n <- function(sub_cfg, n_rows) {
  sub_cfg <- sub_cfg %||% list()
  raw_min_n <- sub_cfg$min_n %||% 20
  if (!is.numeric(raw_min_n) || length(raw_min_n) != 1L || is.na(raw_min_n)) {
    stop("config$subgroup$min_n 必须是数值（绝对人数，或 0~1 之间比例）。", call. = FALSE)
  }
  if (raw_min_n > 0 && raw_min_n < 1) {
    min_group_size <- max(1L, as.integer(ceiling(n_rows * raw_min_n)))
    cli::cli_alert_info(
      "Subgroup min_n 使用比例模式: {raw_min_n} × {n_rows} = {min_group_size}"
    )
  } else {
    min_group_size <- max(1L, as.integer(raw_min_n))
  }
  min_group_size
}

subgroup_infer_db_name <- function(cfg) {
  harm <- (cfg$dual_db %||% list())
  cur <- tolower(as.character(harm$current_db %||% ""))
  if (nzchar(cur) && cur %in% c("nhanes", "mimic")) return(cur)
  dt <- tolower(as.character((cfg$project %||% list())$database_type %||% ""))
  if (grepl("nhanes", dt)) return("nhanes")
  sec <- harm$secondary %||% list()
  pri <- harm$primary %||% list()
  if (identical(tolower(as.character(sec$db_type %||% "")), "regular")) return("mimic")
  if (identical(tolower(as.character(pri$db_type %||% "")), "nhanes")) return("nhanes")
  "mimic"
}

subgroup_default_forbid <- function(cfg, extra = character(0)) {
  sub_cfg <- cfg$subgroup %||% list()
  idx <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "Index"
  )[1L]
  out_col <- as.character(
    (cfg$incidence %||% list())$outcome_var %||%
      cfg$data$outcome_column %||% "Disease"
  )[1L]
  unique(c(
    as.character(sub_cfg$forbid_subgroup_vars %||% character(0)),
    as.character(sub_cfg$exclude_vars %||% character(0)),
    .subgroup_index_group_cols(),
    idx,
    as.character(cfg$data$id_column %||% character(0)),
    out_col,
    "Disease_Group",
    as.character(extra)
  ))
}

subgroup_table1_categorical <- function(ctx) {
  as.character(ctx$results$categorical_vars %||% character(0))
}

#' 自动分类候选：因子/字符 + 低基数数值（唯一值数 ≤ max_levels）
subgroup_auto_categorical_candidates <- function(data, forbid = character(0),
                                                 max_levels = 5L) {
  data <- as.data.frame(data)
  forbid <- unique(as.character(forbid[nzchar(as.character(forbid))]))
  max_levels <- max(2L, as.integer(max_levels %||% 5L)[1L])
  out <- character(0)
  for (v in names(data)) {
    if (v %in% forbid) next
    x <- data[[v]]
    if (is.factor(x) || is.character(x)) {
      out <- c(out, v)
      next
    }
    if (is.logical(x)) {
      out <- c(out, v)
      next
    }
    if (is.numeric(x) || is.integer(x)) {
      n_u <- length(unique(stats::na.omit(x)))
      if (n_u >= 2L && n_u <= max_levels) out <- c(out, v)
    }
  }
  unique(out)
}

#' 将低基数数值列转为因子（不改写原始列名以外的结构）
subgroup_coerce_low_card_numeric_to_factor <- function(data, vars) {
  data <- as.data.frame(data)
  vars <- intersect(as.character(vars), names(data))
  for (v in vars) {
    x <- data[[v]]
    if (is.factor(x) || is.character(x) || is.logical(x)) next
    if (!(is.numeric(x) || is.integer(x))) next
    xv <- as.character(x)
    lv <- sort(unique(xv[!is.na(x)]))
    data[[v]] <- factor(xv, levels = lv)
    cli::cli_alert_info(
      "低基数数值→分类亚组 {.field {v}}: {length(lv)} 水平 ({paste(lv, collapse = ', ')})"
    )
  }
  data
}

subgroup_map_age_group <- function(vars, data, forbid = character(0)) {
  vars <- unique(as.character(vars[nzchar(vars)]))
  forbid <- unique(as.character(forbid[nzchar(forbid)]))
  if ("Age_Group" %in% forbid || "Age" %in% forbid) {
    return(setdiff(vars, c("Age", "Age_Years", "Age_Group")))
  }
  if ("Age_Group" %in% names(data) && !all(is.na(data[["Age_Group"]]))) {
    vars <- unique(c("Age_Group", setdiff(vars, c("Age", "Age_Years"))))
  }
  vars
}

subgroup_default_level_order <- function() {
  list(
    Marital_Status = c("Unmarried", "Non-married", "Married"),
    Gender = c("Female", "Male"),
    Smoking = c("Never", "Former", "Current", "No", "Yes"),
    Smoke = c("Never", "Former", "Current", "No", "Yes"),
    Diabetes = c("No", "Borderline", "Yes"),
    T2DM = c("No", "Yes"),
    Hypertension = c("No", "Yes"),
    Alcohol_drinking = c("No", "Yes"),
    Antihypertensive_agents = c("No", "Yes"),
    Lipid_lowering_agents = c("No", "Yes"),
    Antidiabetic_agents = c("No", "Yes"),
    Age_Group = c(
      "<30", "30-44", "45-59", "\u226560", "< 30", "30-44", "45-59", ">=60",
      "< 45", "\u2265 45", "<45", ">=45", "< 65", "\u2265 65", "<65", ">=65",
      "< 70", "\u2265 70", "<70", ">=70", "< 75", "\u2265 75", "<75", ">=75"
    ),
    PIR = c("< 1.3", "<1.3", "1.3-3.5", "> 3.5", ">3.5"),
    Race = c(
      "Mexican American", "Other Hispanic", "Non-Hispanic White",
      "Non-Hispanic Black", "Other Race", "White", "Black", "Other"
    )
  )
}

subgroup_resolve_level_order <- function(cfg) {
  sub_cfg <- cfg$subgroup %||% list()
  utils::modifyList(subgroup_default_level_order(), sub_cfg$level_order %||% list())
}

subgroup_order_present_levels <- function(var, present, cfg) {
  present <- unique(trimws(as.character(present[nzchar(as.character(present))])))
  canon <- subgroup_resolve_level_order(cfg)[[var]]
  if (is.null(canon) || !length(canon)) return(present)
  canon <- trimws(as.character(canon))
  c(intersect(canon, present), setdiff(present, canon))
}

subgroup_apply_level_order <- function(data, vars, cfg) {
  data <- as.data.frame(data)
  vars <- intersect(as.character(vars), names(data))
  for (v in vars) {
    x <- data[[v]]
    if (is.factor(x)) x <- as.character(x)
    x <- trimws(x)
    present <- unique(x[!is.na(x) & nzchar(x)])
    if (!length(present)) next
    lv <- subgroup_order_present_levels(v, present, cfg)
    data[[v]] <- factor(x, levels = lv)
    cli::cli_alert_info(
      "Subgroup level order {v}: {paste(lv, collapse = ' | ')}"
    )
  }
  data
}

subgroup_classify_demo_clinical <- function(vars, cfg) {
  vars <- unique(as.character(vars[nzchar(vars)]))
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  common_clinical <- as.character(
    harm$common_clinical_subgroup_cols %||% harm$common_non_demo_cols %||% character(0)
  )
  is_demo <- if (length(demo_kw) && exists("dual_db_is_demo_col", mode = "function")) {
    dual_db_is_demo_col(vars, demo_kw)
  } else {
    rep(FALSE, length(vars))
  }
  demo <- vars[is_demo]
  clinical <- intersect(vars, common_clinical)
  other <- setdiff(vars, c(demo, clinical))
  list(demo = demo, clinical = clinical, other = other)
}

subgroup_build_variable_pool <- function(ctx, data, cfg, db_name = NULL) {
  sub_cfg <- cfg$subgroup %||% list()
  var_source <- sub_cfg$var_source %||% "table1_categorical"
  if (is.null(db_name)) db_name <- subgroup_infer_db_name(cfg)
  forbid <- subgroup_default_forbid(cfg)

  max_levels <- as.integer(sub_cfg$auto_categorical_max_levels %||% 5L)[1L]
  if (!is.finite(max_levels) || max_levels < 2L) max_levels <- 5L

  if (identical(var_source, "required")) {
    pool <- as.character(sub_cfg$required_subgroup_vars %||% sub_cfg$vars %||% character(0))
  } else if (identical(var_source, "auto_categorical") ||
             identical(var_source, "auto_categorical_incl_low_card")) {
    # 因子/字符 + 唯一值≤max_levels 的数值列
    pool <- subgroup_auto_categorical_candidates(data, forbid = forbid, max_levels = max_levels)
  } else {
    pool <- subgroup_table1_categorical(ctx)
    if (!length(pool)) {
      cli::cli_alert_warning(
        "subgroup: ctx$results$categorical_vars 为空，回退为自动分类候选（含低基数数值）"
      )
      pool <- subgroup_auto_categorical_candidates(data, forbid = forbid, max_levels = max_levels)
    }
  }

  pool <- subgroup_map_age_group(pool, data, forbid)
  pool <- setdiff(unique(pool), forbid)
  pool <- pool[pool %in% names(data)]

  dual_on <- isTRUE((cfg$dual_db %||% list())$enable)
  if (dual_on && !identical(var_source, "required")) {
    split <- subgroup_classify_demo_clinical(pool, cfg)
    demo_vars <- split$demo
    clinical_vars <- split$clinical
    if (length(split$other)) {
      cli::cli_alert_warning(
        "subgroup ({db_name}): 忽略非人口学/非共有临床变量: {paste(split$other, collapse = ', ')}"
      )
    }
    pool <- unique(c(demo_vars, clinical_vars))
    cli::cli_alert_info(
      "subgroup 变量池 ({db_name}): demo={length(demo_vars)}, clinical={length(clinical_vars)} — ",
      paste(pool, collapse = ", ")
    )
  } else {
    cli::cli_alert_info(
      "subgroup 变量池 ({db_name}): {length(pool)} 个 — {paste(pool, collapse = ', ')}"
    )
  }

  list(vars = unique(pool), forbid = forbid, var_source = var_source)
}

subgroup_apply_min_n_filter <- function(data, vars, min_group_size, cfg = NULL) {
  data <- as.data.frame(data)
  vars_to_keep <- character(0)
  # 按变量独立筛水平：稀有水平置 NA，不删除整行，避免后续变量共同丢样本
  for (v in vars) {
    if (!v %in% names(data)) next
    if (v == "Age_Group" && all(is.na(data[[v]]))) next
    x <- data[[v]]
    if (is.logical(x)) {
      x <- factor(ifelse(x, "Yes", "No"), levels = c("No", "Yes"))
      data[[v]] <- x
    }
    if (is.character(x)) {
      x <- trimws(x)
      data[[v]] <- x <- as.factor(x)
    }
    if (is.numeric(x) || is.integer(x)) {
      xv <- as.character(x)
      lv <- sort(unique(xv[!is.na(x)]))
      data[[v]] <- x <- factor(xv, levels = lv)
    }
    if (!is.factor(x)) next
    group_counts <- table(x, useNA = "no")
    valid_levels <- names(group_counts[group_counts >= min_group_size])
    if (!is.null(cfg)) {
      valid_levels <- subgroup_order_present_levels(v, valid_levels, cfg)
    }
    if (length(valid_levels) >= 2L) {
      # 仅将该列稀有水平置 NA；保留全部行供其他亚组变量使用
      xc <- trimws(as.character(data[[v]]))
      xc[!xc %in% valid_levels] <- NA_character_
      data[[v]] <- factor(xc, levels = valid_levels)
      vars_to_keep <- c(vars_to_keep, v)
      cli::cli_alert_info(
        "Variable {v}: keeping levels {paste(valid_levels, collapse=', ')} (min_n>={min_group_size}; rare levels → NA, no row drop)"
      )
    } else if (length(valid_levels) == 1L) {
      cli::cli_alert_warning(
        "Variable {v}: 仅 1 个水平满足 min_n={min_group_size}，已剔除"
      )
    } else {
      cli::cli_alert_warning(
        "Variable {v}: 所有水平样本量 < {min_group_size}，已剔除"
      )
    }
  }
  list(vars = vars_to_keep, data = data)
}

#' 亚组水平显式剔除（课题 config 用）：把指定水平置 NA 使其不进森林图/亚组表。
#' 与 min_n 过滤互补：min_n 按样本量，exclude_levels 按研究决定（如 OR 不可估/NE 行）。
#' config$subgroup$exclude_levels = list(Race = c("Asian", "Hispanic"), ...)
#' 水平名匹配大小写不敏感、忽略首尾空格；剔除后若该变量仅剩 1 水平则整变量返回剔除。
subgroup_apply_exclude_levels <- function(data, vars, cfg) {
  sub_cfg <- cfg$subgroup %||% list()
  excl_map <- sub_cfg$exclude_levels %||% list()
  if (!length(excl_map)) return(list(vars = vars, data = data, dropped_vars = character(0)))
  data <- as.data.frame(data)
  vars <- as.character(vars)
  dropped_vars <- character(0)
  keep_vars <- character(0)
  for (v in vars) {
    if (!v %in% names(data)) next
    drop_lv <- tolower(trimws(as.character(excl_map[[v]] %||% character(0))))
    drop_lv <- drop_lv[nzchar(drop_lv)]
    if (!length(drop_lv)) {
      keep_vars <- c(keep_vars, v)
      next
    }
    x <- data[[v]]
    x_chr <- trimws(as.character(x))
    hit <- tolower(x_chr) %in% drop_lv
    if (any(hit, na.rm = TRUE)) {
      x_chr[hit] <- NA_character_
      cli::cli_alert_info(
        "exclude_levels: {v} 剔除水平 {paste(unique(trimws(as.character(x[hit]))), collapse=', ')}（置 NA，{sum(hit)} 行）"
      )
    }
    lv_left <- unique(x_chr[!is.na(x_chr) & nzchar(x_chr)])
    if (length(lv_left) >= 2L) {
      data[[v]] <- factor(x_chr, levels = lv_left)
      keep_vars <- c(keep_vars, v)
    } else if (length(lv_left) == 1L) {
      dropped_vars <- c(dropped_vars, v)
      cli::cli_alert_warning(
        "exclude_levels: {v} 剔除后仅剩 1 个水平（{lv_left}），整变量不进亚组"
      )
    } else {
      dropped_vars <- c(dropped_vars, v)
      cli::cli_alert_warning("exclude_levels: {v} 剔除后无水平剩余，整变量不进亚组")
    }
  }
  list(vars = unique(keep_vars), data = data, dropped_vars = unique(dropped_vars))
}

subgroup_vars_pass_min_n <- function(data, vars, min_group_size) {
  data <- as.data.frame(data)
  kept <- character(0)
  for (v in vars) {
    if (!v %in% names(data)) next
    if (v == "Age_Group" && all(is.na(data[[v]]))) next
    x <- data[[v]]
    if (is.character(x)) x <- as.factor(x)
    if (!is.factor(x)) next
    group_counts <- table(x, useNA = "no")
    valid_levels <- names(group_counts[group_counts >= min_group_size])
    if (length(valid_levels) >= 2L) kept <- c(kept, v)
  }
  unique(kept)
}

#' 临床优先的亚组变量排序（闸门 D / 双库对齐共用）
subgroup_order_vars_clinical <- function(v) {
  v <- unique(as.character(v[nzchar(as.character(v))]))
  canon <- c(
    # 人口学（含 Insurance）
    "Age_Group", "BMI_Group", "Gender", "Education", "Marital_Status",
    "Income", "Smoking", "Alcohol_drinking", "Race", "Language", "Insurance",
    # 共病 / 临床
    "Hypertension", "Diabetes", "T1DM", "T2DM",
    "Heart_Failure", "Myocardial_Infarction", "Atrial_Fibrillation",
    "Stroke", "COPD", "CKD", "Acute_Renal_Failure",
    "Liver_cirrhosis", "Hepatitis", "Cancer", "Hyperlipidemia",
    "Pneumonia", "Tuberculosis", "Dementia"
  )
  c(intersect(canon, v), setdiff(v, canon))
}

#' 探测某库在 min_n 过滤后仍可用于亚组交互的变量（与 subgroup_prognosis 规则对齐）
subgroup_probe_eligible_vars <- function(data, cfg) {
  data <- as.data.frame(data)
  sub_cfg <- utils::modifyList(cfg$subgroup %||% list(), cfg$subgroup_prognosis %||% list())
  age_cut <- as.numeric(sub_cfg$age_cutoff %||% 65)[1L]
  if (!is.finite(age_cut)) age_cut <- 65
  min_n <- subgroup_resolve_min_n(sub_cfg, nrow(data))

  age_lo <- paste0("< ", age_cut)
  age_hi <- paste0("\u2265 ", age_cut)
  if ("Age" %in% names(data)) {
    data$Age_Group <- ifelse(data$Age < age_cut, age_lo, age_hi)
    data$Age_Group <- factor(data$Age_Group, levels = c(age_lo, age_hi))
  }
  if ("BMI" %in% names(data)) {
    if (exists("dual_db_make_bmi_group", mode = "function")) {
      data$BMI_Group <- dual_db_make_bmi_group(data$BMI)
    } else {
      bmi_num <- suppressWarnings(as.numeric(as.character(data$BMI)))
      bg <- ifelse(
        !is.finite(bmi_num), NA_character_,
        ifelse(bmi_num < 25, "< 25",
               ifelse(bmi_num < 30, "25-30", "\u2265 30"))
      )
      data$BMI_Group <- factor(bg, levels = c("< 25", "25-30", "\u2265 30"))
    }
  }

  req <- as.character(sub_cfg$required_subgroup_vars %||% sub_cfg$vars %||% character(0))
  forbid <- unique(c(
    as.character(sub_cfg$forbid_subgroup_vars %||% character(0)),
    as.character(sub_cfg$exclude_vars %||% character(0))
  ))
  if (length(req)) {
    mapped <- character(0)
    for (r in req) {
      if (r %in% c("Age", "Age_Years") && "Age_Group" %in% names(data) &&
          !all(is.na(data$Age_Group))) {
        mapped <- c(mapped, "Age_Group")
      } else if (identical(r, "BMI") && "BMI_Group" %in% names(data) &&
                 !all(is.na(data$BMI_Group))) {
        mapped <- c(mapped, "BMI_Group")
      } else {
        mapped <- c(mapped, r)
      }
    }
    req <- unique(mapped)
  }
  pool <- if (isTRUE(sub_cfg$restrict_to_required %||% FALSE) && length(req)) {
    intersect(req, names(data))
  } else if (length(req)) {
    unique(c(intersect(req, names(data)), character(0)))
  } else {
    names(data)[vapply(data, function(x) is.factor(x) || is.character(x), logical(1))]
  }
  pool <- setdiff(pool, forbid)
  pool <- setdiff(pool, "BMI")
  kept <- subgroup_vars_pass_min_n(data, pool, min_n)
  subgroup_order_vars_clinical(kept)
}
