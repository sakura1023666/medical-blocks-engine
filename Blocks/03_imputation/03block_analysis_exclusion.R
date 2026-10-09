###############################################################################
#  analysis_exclusion — 疾病相关变量 + 当前指标组成变量硬排除
#
#  register_block: "analysis_exclusion"
#  典型位置: competing_index_exposure 之后、trim_index_extreme / 表导出之前
#
#  config$analysis_exclusion$protect_vars（可选，字符向量）:
#    显式保护列名单，优先于 disease_vars / 组成变量 / other_index 的「删列」生效。
#    典型用途：
#      1) 派生暴露/结局列（如 Diabetes_HbA1c）不被同名疾病变量误删；
#      2) 暴露公式成分中需保留作 Table1 / 亚组展示的列（如 FIB4 的 Age、
#         或其它复合指标名 BMI）——这些列仍禁止进入 Model1/2 协变量
#         （由 pipeline_covariate_analysis_exclude_vars / logistic_constrain 排除）。
#    实验室成分（AST/ALT/PLT 等）勿放入 protect_vars，继续从数据中硬删。
###############################################################################

pipeline_analysis_exclusion_resolve_index_var <- function(cfg) {
  ae <- cfg$analysis_exclusion %||% list()
  bl <- cfg$competing_risk %||% list()
  sb <- cfg$study_batch %||% list()
  # 无当前复合指标模式（用药 IPW 单次主链）：不把 active_unit=main 当成指标
  if (isTRUE(ae$allow_no_index %||% FALSE)) {
    return("")
  }
  # 真实指标名优先于目录别名 active_unit（如 GPR[new] → GPR via unit_index_map）
  # 顺序：ae 显式 → competing_risk/incidence/survival → mapped active_unit
  umap <- sb$unit_index_map %||% list()
  active <- as.character(sb$active_unit %||% "")[1L]
  mapped_active <- if (nzchar(active) && !is.null(umap[[active]]) &&
                       nzchar(as.character(umap[[active]])[1L])) {
    as.character(umap[[active]])[1L]
  } else {
    active
  }
  as.character(
    ae$index_var %||%
      bl$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      mapped_active %||% ""
  )[1L]
}

pipeline_analysis_exclusion_keep_vars <- function(cfg) {
  bl <- cfg$competing_risk %||% list()
  ae <- cfg$analysis_exclusion %||% list()
  index_var <- pipeline_analysis_exclusion_resolve_index_var(cfg)
  current_index_vars <- unique(c(
    index_var,
    as.character(ae$current_index_vars %||% character(0))
  ))
  current_index_vars <- current_index_vars[nzchar(current_index_vars)]
  unique(c(
    as.character((cfg$data %||% list())$id_column %||% character(0)),
    "ID", "subject_id", "SEQN",
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0)),
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character(bl$time_var %||% character(0)),
    as.character(bl$event_type_col %||% character(0)),
    "competing_time_28d", "competing_status_28d", "competing_primary_event",
    current_index_vars,
    as.character(bl$exposure_var %||% if (nzchar(index_var)) paste0(index_var, "_quartile") else character(0)),
    as.character(bl$trajectory_var %||% if (nzchar(index_var)) paste0(index_var, "_trajectory") else character(0)),
    if (nzchar(index_var)) paste0(index_var, c("", "_quartile", "_trajectory")) else character(0),
    # config$analysis_exclusion$protect_vars — 显式保护名单（如派生暴露列），
    # 优先于疾病变量/组成变量硬排除；config 驱动，不在块内硬编码具体列名。
    as.character(ae$protect_vars %||% character(0))
  ))
}

pipeline_analysis_exclusion_match_names <- function(candidates, data_names) {
  candidates <- unique(as.character(candidates %||% character(0)))
  candidates <- candidates[nzchar(candidates)]
  if (!length(candidates) || !length(data_names)) return(character(0))
  cand_norm <- pipeline_exclusion_normalize_name(candidates)
  data_norm <- pipeline_exclusion_normalize_name(data_names)
  hit <- data_names[data_norm %in% cand_norm]
  unique(hit[nzchar(hit)])
}

pipeline_analysis_exclusion_manifest <- function(cfg, data_names = character(0)) {
  ae <- cfg$analysis_exclusion %||% list()
  if (!length(ae)) {
    return(list(
      index_var = NA_character_,
      disease_vars = character(0),
      component_vars = character(0),
      other_index_vars = character(0),
      drop_vars = character(0),
      keep_vars = character(0)
    ))
  }

  if (!exists("pipeline_index_definition_map", mode = "function") ||
      !exists("pipeline_index_raw_components", mode = "function")) {
    eng_root <- if (exists("pipeline_engine_root", mode = "function")) {
      pipeline_engine_root(cfg$project$root %||% getwd())
    } else {
      cfg$project$root %||% getwd()
    }
    src <- file.path(eng_root, "Blocks/00_index/01block_index.R")
    if (!file.exists(src)) {
      env_eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
      if (nzchar(env_eng)) {
        src <- file.path(env_eng, "Blocks/00_index/01block_index.R")
      }
    }
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (!exists("pipeline_index_raw_components", mode = "function")) {
    stop("EXCLUSION_COMPONENT_RESOLVE_FAIL: 指标公式解析器不可用", call. = FALSE)
  }

  bl <- cfg$competing_risk %||% list()
  index_var <- pipeline_analysis_exclusion_resolve_index_var(cfg)
  current_index_vars <- unique(c(
    index_var,
    as.character(ae$current_index_vars %||% character(0))
  ))
  current_index_vars <- current_index_vars[nzchar(current_index_vars)]
  definitions <- pipeline_index_definition_map()
  allow_no_index <- isTRUE(ae$allow_no_index %||% FALSE)
  if (!nzchar(index_var) && !allow_no_index) {
    stop("EXCLUSION_COMPONENT_RESOLVE_FAIL: 缺少当前指标 index_var", call. = FALSE)
  }

  if (!nzchar(index_var)) {
    index_var <- "(none)"
    current_index_vars <- character(0)
    component_vars <- character(0)
  } else {
    component_vars <- unique(unlist(lapply(
      current_index_vars,
      pipeline_index_raw_components,
      definitions = definitions
    ), use.names = FALSE))
  }
  disease_cfg <- as.character(ae$disease_vars %||% character(0))
  disease_vars <- pipeline_analysis_exclusion_match_names(disease_cfg, data_names)
  if (!length(disease_vars) && length(disease_cfg)) {
    # 配置名本身也写入审计；真正删除时再与列交集
    disease_vars <- disease_cfg
  }

  all_indices <- as.character(
    ae$composite_index_vars %||%
      names(definitions)
  )
  other_index_vars <- character(0)
  if (isTRUE(ae$exclude_other_composite_indices %||% TRUE)) {
    other_index_vars <- if (identical(index_var, "(none)")) {
      all_indices
    } else {
      setdiff(all_indices, current_index_vars)
    }
  }

  keep_vars <- pipeline_analysis_exclusion_keep_vars(cfg)
  drop_candidates <- unique(c(disease_vars, component_vars, other_index_vars))
  if (length(data_names)) {
    drop_vars <- setdiff(
      pipeline_analysis_exclusion_match_names(drop_candidates, data_names),
      keep_vars
    )
  } else {
    drop_vars <- setdiff(drop_candidates, keep_vars)
  }

  root <- (cfg$project %||% list())$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  ic_fp <- file.path(root, "R/index_canonical.R")
  if (file.exists(ic_fp) && !exists("index_prune_alias_drop_vars", mode = "function")) {
    source(ic_fp, local = FALSE)
  }
  if (exists("index_prune_alias_drop_vars", mode = "function")) {
    alias_drop <- index_prune_alias_drop_vars(data_names, cfg)
    if (length(alias_drop)) {
      drop_vars <- unique(c(drop_vars, alias_drop))
    }
  }

  list(
    index_var = index_var,
    disease_vars = unique(disease_vars),
    component_vars = unique(component_vars),
    other_index_vars = unique(other_index_vars),
    drop_vars = unique(drop_vars),
    keep_vars = unique(keep_vars)
  )
}

block_analysis_exclusion <- function(ctx, ...) {
  cfg <- ctx$config
  ae <- cfg$analysis_exclusion %||% list()
  if (!length(ae)) {
    cli::cli_alert_info("analysis_exclusion: 未配置，跳过")
    return(ctx)
  }

  data_names <- unique(unlist(lapply(
    c("imputed", "cleaned", "raw", "mapped"),
    function(slot) names(ctx$data[[slot]] %||% character(0))
  )))
  resolved <- pipeline_analysis_exclusion_resolve_index_var(cfg)
  cli::cli_alert_info(
    "analysis_exclusion resolve: index_var={resolved}; ae={as.character((cfg$analysis_exclusion %||% list())$index_var %||% NA)}; active_unit={as.character((cfg$study_batch %||% list())$active_unit %||% NA)}; incidence={as.character((cfg$incidence %||% list())$index_var %||% NA)}; survival={as.character((cfg$survival %||% list())$index_var %||% NA)}"
  )
  manifest <- pipeline_analysis_exclusion_manifest(cfg, data_names)
  drop_vars <- as.character(manifest$drop_vars %||% character(0))

  # mapped：发病共享层 index 后、插补前的主数据槽，必须一并硬删
  for (slot in c("imputed", "cleaned", "raw", "mapped")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df)) next
    hit <- intersect(drop_vars, names(df))
    if (length(hit)) {
      df <- df[, setdiff(names(df), hit), drop = FALSE]
      ctx$data[[slot]] <- df
      cli::cli_alert_info(
        "analysis_exclusion [{slot}]: 已删除 {length(hit)} 列"
      )
    }
  }

  # 审计 csv 只落 step 子目录，不进库级/汇总 Tables
  out_dir <- ctx$output_dir_tables %||%
    file.path(ctx$output_dir %||% (cfg$project$output_dir %||% "Output"), "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  vars_audit <- c(
    manifest$disease_vars,
    manifest$component_vars,
    manifest$other_index_vars
  )
  audit <- if (!length(vars_audit)) {
    data.frame(
      index_var = character(0),
      category = character(0),
      variable = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      index_var = manifest$index_var,
      category = c(
        rep("disease", length(manifest$disease_vars)),
        rep("component", length(manifest$component_vars)),
        rep("other_index", length(manifest$other_index_vars))
      ),
      variable = vars_audit,
      stringsAsFactors = FALSE
    )
  }
  utils::write.csv(
    audit,
    file.path(out_dir, paste0("Analysis_exclusion_", gsub("[^A-Za-z0-9_]+", "_", manifest$index_var), ".csv")),
    row.names = FALSE
  )

  ctx$results$analysis_exclusion_manifest <- manifest
  cli::cli_alert_success(
    "analysis_exclusion: 当前指标 {manifest$index_var}；拟删 {length(drop_vars)} 列"
  )
  ctx
}

register_block(
  "analysis_exclusion",
  block_analysis_exclusion,
  "疾病变量与当前复合指标组成变量硬排除"
)
