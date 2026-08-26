###############################################################################
#  baseline_dictionary_labels.R — 从 Baseline数据字典.csv 为 Table 1 追加单位
#
#  展示格式与论文习惯一致：PrettyName,unit（逗号前后无空格）
#  例：Hemoglobin,g/dL ；BMI,kg/m² ；Waist circumference,cm
###############################################################################

baseline_dictionary_path <- function(root = NULL) {
  roots <- c(
    if (!is.null(root) && length(root) && nzchar(as.character(root)[1L]))
      as.character(root)[1L],
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    getwd()
  )
  roots <- unique(roots[nzchar(as.character(roots))])
  cands <- c(
    file.path(roots, "Baseline数据字典.csv"),
    file.path(roots, "R", "Baseline数据字典.csv")
  )
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[[1L]] else NA_character_
}

#' 字典单位 → Table 1 英文展示单位（避免中文单位出现在英文表）
baseline_dictionary_unit_for_table1 <- function(unit) {
  u <- trimws(as.character(unit %||% "")[1L])
  if (!nzchar(u)) return(NA_character_)
  map <- c(
    "岁" = "years",
    "小时" = "hours",
    "天" = "days",
    "分" = "points",
    "元" = "CNY",
    "是/否" = NA_character_  # 已在 measurable 中跳过；兜底
  )
  if (u %in% names(map)) {
    mapped <- unname(map[[u]])
    if (is.na(mapped) || !nzchar(mapped)) return(NA_character_)
    return(mapped)
  }
  u
}

#' 单位是否为可计量物理/化学单位（否则不追加到 Table 1 标签）
baseline_dictionary_unit_is_measurable <- function(unit) {
  u <- trimws(as.character(unit %||% "")[1L])
  if (!nzchar(u)) return(FALSE)
  skip <- c(
    "\u2014", "-", "\u2013",
    "分类", "Male/Female", "Yes / No", "Yes/No", "是/否",
    "English/Other", "ratio", "文本", "1-6", "units"
  )
  if (u %in% skip) return(FALSE)
  # 纯水平说明（含 / 且无数字与常见计量符号）视作分类
  if (grepl("^[A-Za-z]+/[A-Za-z]+$", u) && !grepl("(dL|mL|L|kg|mg|ug|μg|ng|pg|mm|cm|mEq|mmol|IU)", u)) {
    return(FALSE)
  }
  TRUE
}

#' 数据列名 → 字典「处理后指标名」别名（列映射后的标准名）
baseline_dictionary_data_to_dict_aliases <- function() {
  c(
    Platelet_Count     = "PlateletCount",
    Neutrophil_Count   = "NeutrophilCount",
    Lymphocyte_Count   = "Lymphocytes",
    Uric_Acid          = "UricAcid",
    BUN                = "UreaNitrogen",
    Total_Cholesterol  = "TC",
    Triglycerides      = "TG",
    SBP                = "NBPS",
    DBP                = "NBPD",
    MAP                = "NBPM",
    Smoking            = "Smoke",
    Smoke              = "Smoke",
    Total_Protein      = "TotalProtein",
    TotalProtein       = "TotalProtein",
    Bilirubin_Total    = "BilirubinTotal",
    Calcium_Total      = "CalciumTotal",
    Free_Calcium       = "FreeCalcium",
    Urine_Protein      = "UrineProtein",
    Albumin_Urine      = "AlbuminUrine"
  )
}

baseline_dictionary_load <- function(root = NULL) {
  path <- baseline_dictionary_path(root)
  if (is.na(path) || !file.exists(path)) return(NULL)
  df <- tryCatch(
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) {
      tryCatch(
        utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8"),
        error = function(e2) NULL
      )
    }
  )
  if (is.null(df) || !nrow(df)) return(NULL)
  name_col <- names(df)[1L]
  unit_col <- if ("单位" %in% names(df)) "单位" else names(df)[min(3L, ncol(df))]
  out <- data.frame(
    dict_name = trimws(as.character(df[[name_col]])),
    unit      = trimws(as.character(df[[unit_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[nzchar(out$dict_name), , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "path") <- path
  out
}

baseline_dictionary_pretty_name <- function(var) {
  gsub("_", " ", as.character(var)[1L], fixed = TRUE)
}

#' 为给定数据列名生成 Table 1 label overrides：list(Col = "Pretty,unit")
baseline_dictionary_unit_label_map <- function(root = NULL, vars = character(0)) {
  vars <- unique(as.character(vars[nzchar(as.character(vars))]))
  if (!length(vars)) return(list())
  dict <- baseline_dictionary_load(root)
  if (is.null(dict) || !nrow(dict)) return(list())

  aliases <- baseline_dictionary_data_to_dict_aliases()
  dict_by <- stats::setNames(dict$unit, dict$dict_name)
  # 小写索引便于容错
  dict_by_low <- stats::setNames(dict$unit, tolower(dict$dict_name))

  out <- list()
  for (v in vars) {
    candidates <- unique(c(
      v,
      unname(aliases[v]),
      gsub("_", "", v, fixed = TRUE)
    ))
    candidates <- candidates[nzchar(as.character(candidates))]
    unit <- NA_character_
    for (cand in candidates) {
      if (cand %in% names(dict_by)) {
        unit <- dict_by[[cand]]
        break
      }
      low <- tolower(cand)
      if (low %in% names(dict_by_low)) {
        unit <- dict_by_low[[low]]
        break
      }
    }
    if (is.na(unit) || !baseline_dictionary_unit_is_measurable(unit)) next
    unit_disp <- baseline_dictionary_unit_for_table1(unit)
    if (is.na(unit_disp) || !nzchar(unit_disp)) next
    pretty <- baseline_dictionary_pretty_name(v)
    # 已带单位则不重复追加
    if (grepl(",\\s*\\S+$", pretty)) next
    out[[v]] <- paste0(pretty, ",", unit_disp)
  }
  out
}

#' 是否启用字典单位标签（默认 TRUE）
baseline_table1_units_enabled <- function(cfg, bl_cfg = NULL) {
  bl_cfg <- bl_cfg %||% list()
  if (!is.null(bl_cfg$table1_append_units_from_dictionary)) {
    return(isTRUE(bl_cfg$table1_append_units_from_dictionary))
  }
  bl_root <- (cfg$baseline %||% list())$table1_append_units_from_dictionary
  if (!is.null(bl_root)) return(isTRUE(bl_root))
  TRUE
}

#' 合并字典单位到 baseline* 的 table1_label_overrides
#' 内置展示名（如 FI→Frailty Index）始终合并；字典单位按开关；config overrides 最后覆盖
baseline_merge_table1_unit_label_overrides <- function(cfg, bl_cfg, vars, root = NULL) {
  bl_cfg <- bl_cfg %||% list()
  existing <- as.list(bl_cfg$table1_label_overrides %||% list())
  builtin_ov <- list()
  if (exists("pipeline_builtin_var_display_names", mode = "function")) {
    bn <- pipeline_builtin_var_display_names()
    # 仅对本次 Table 1 变量（或全部内置键）写展示名
    keys <- if (length(vars)) intersect(names(bn), as.character(vars)) else names(bn)
    if (length(keys)) builtin_ov <- as.list(bn[keys])
  }
  merged <- utils::modifyList(builtin_ov, existing)

  if (isTRUE(baseline_table1_units_enabled(cfg, bl_cfg))) {
    root <- root %||% (cfg$project %||% list())$root %||%
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "") %||% getwd()
    unit_ov <- baseline_dictionary_unit_label_map(root, vars)
    # 单位字典在前，builtin/config 覆盖在后（避免把 Frailty Index 盖成带奇怪单位）
    if (length(unit_ov)) merged <- utils::modifyList(unit_ov, merged)
  }
  bl_cfg$table1_label_overrides <- merged
  bl_cfg
}
