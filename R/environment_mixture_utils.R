###############################################################################
#  environment_mixture_utils.R — DKD × 环境 VOC 混合物分析共用工具
#
#  - VOC 列自动识别（index_exclude_vars / 候选暴露）
#  - LASSO/WQS 最少变量数约束
#  - BKMR 总体效应质量判定（单调上升 + 右侧 CI 不跨 0）
#  - WQS 暴露子集自动搜索（优化 BKMR 质量）
#  - BKMR 迭代次数自动选择
###############################################################################

environment_voc_col_pattern <- function(cfg) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  prep <- cfg$environment_prepare %||% list()
  pats <- unique(c(
    as.character(env$voc_col_pattern %||% character(0)),
    as.character(prep$env_voc_pattern %||% character(0)),
    as.character(prep$voc_col_pattern %||% character(0))
  ))
  pats <- pats[nzchar(pats)]
  if (!length(pats)) return("^URX")
  pats[[1L]]
}

#' 尿/血环境暴露列名模式（与 voc_col_pattern / env_voc_pattern 一致）
environment_voc_name_patterns <- function(cfg) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  prep <- cfg$environment_prepare %||% list()
  pats <- unique(c(
    as.character(env$voc_col_pattern %||% character(0)),
    as.character(prep$env_voc_pattern %||% character(0)),
    as.character(prep$voc_col_pattern %||% character(0)),
    environment_voc_col_pattern(cfg)
  ))
  pats[nzchar(pats)]
}

#' 非环境暴露的尿/血化验列（仅元数据，永不进混合物分析池）
environment_voc_meta_exclude_cols <- function(cfg = list()) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  prep <- cfg$environment_prepare %||% list()
  default_meta <- c("URXUCR", "URXUMA", "URXU_SG")
  unique(as.character(c(
    env$voc_meta_exclude %||% character(0),
    prep$voc_meta_exclude %||% character(0),
    default_meta
  )))
}

#' 按列名模式匹配数据中全部环境毒物列（不应用 voc_exclude_fixed / LASSO 剔除）
#'
#' 用于临床单因素、VIF、Table 1 分区：分析池剔除的 URX* 仍不得回流临床路径。
environment_clinical_voc_gate_columns <- function(data, cfg) {
  if (is.null(data) || !ncol(data)) return(character(0))
  pats <- environment_voc_name_patterns(cfg)
  cols <- names(data)
  matched <- character(0)
  for (pat in pats) {
    matched <- c(matched, cols[grepl(pat, cols, ignore.case = TRUE)])
  }
  setdiff(unique(matched), environment_voc_meta_exclude_cols(cfg))
}

#' 数据中所有符合暴露列名模式的列（含 LOD/筛查已剔除但仍留在数据里的 VOC）
environment_pattern_voc_columns <- function(data, cfg) {
  if (is.null(data) || !ncol(data)) return(character(0))
  setdiff(
    environment_clinical_voc_gate_columns(data, cfg),
    environment_voc_exclude_fixed(cfg)
  )
}

environment_voc_exclude_fixed <- function(cfg) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  prep <- cfg$environment_prepare %||% list()
  bc <- cfg$environment_batch %||% list()
  lasso <- cfg$lasso_environment %||% list()
  default_fixed <- c("URXUCR", "URXUMA", "URXU_SG", "URXHEM", "URXPHE")
  unique(as.character(c(
    env$voc_exclude_fixed %||% character(0),
    prep$voc_exclude_fixed %||% character(0),
    bc$rcs_dropped_vocs %||% character(0),
    lasso$exclude_vars %||% character(0),
    if (!length(env$voc_exclude_fixed) &&
        !length(prep$voc_exclude_fixed)) default_fixed else character(0)
  )))
}

#' 从数据列名解析 VOC 暴露列（优先数据中实际存在的 voc_columns / index_exclude_vars）
environment_resolve_voc_columns <- function(data, cfg) {
  cfg <- cfg %||% list()
  declared <- unique(c(
    as.character((cfg$environment %||% list())$voc_columns %||% character(0)),
    as.character((cfg$incidence %||% list())$index_exclude_vars %||% character(0))
  ))
  declared <- declared[nzchar(declared)]
  if (!is.null(data) && ncol(data) && length(declared)) {
    in_data <- intersect(declared, names(data))
    if (length(in_data)) return(unique(in_data))
  }
  if (length(declared)) return(declared)

  if (is.null(data) || !ncol(data)) return(character(0))
  pat <- environment_voc_col_pattern(cfg)
  cols <- names(data)
  matched <- cols[grepl(pat, cols, ignore.case = TRUE)]
  fixed_excl <- environment_voc_exclude_fixed(cfg)
  extra_excl <- as.character((cfg$lasso_environment %||% list())$exclude_vars %||% character(0))
  setdiff(unique(matched), unique(c(fixed_excl, extra_excl)))
}

#' 将 config 中 VOC 排除列表同步为数据里实际存在的环境毒物列名
#'
#' 注意：`voc_columns` 保留分析池（declared / LOD 后子集）；
#' `index_exclude_vars` 用「分析池 ∪ 模式匹配」——避免阶段剔除的 URX*
#'（如 RCS 不显著后的 URXUMO）或模式外漏网列回流到临床 Table S3/VIF。
environment_patch_voc_exclude <- function(cfg, data) {
  cfg <- cfg %||% list()
  if (is.null(data) || !ncol(data)) return(cfg)
  vocs <- environment_resolve_voc_columns(data, cfg)
  # 临床门禁：模式匹配的全部环境毒物（含分析池已剔除的 URX34M 等）
  vocs_excl <- environment_clinical_voc_gate_columns(data, cfg)
  if (!length(vocs_excl)) return(cfg)
  cfg$incidence <- cfg$incidence %||% list()
  cfg$incidence$index_exclude_vars <- vocs_excl
  cfg$environment <- cfg$environment %||% list()
  # 分析池：已有 curated 列表则只裁剪到当前数据，不因模式匹配重新扩池
  prev <- as.character(cfg$environment$voc_columns %||% character(0))
  prev <- unique(prev[nzchar(prev)])
  if (length(prev)) {
    cfg$environment$voc_columns <- intersect(prev, names(data))
  } else if (length(vocs)) {
    cfg$environment$voc_columns <- vocs
  } else {
    cfg$environment$voc_columns <- vocs_excl
  }
  cfg
}

#' Table 1 / 单因素 / 插补表：环境毒物列（白名单顺序）
environment_table1_voc_vars <- function(data, cfg) {
  if (exists("environment_voc_allowlist", mode = "function")) {
    v <- environment_voc_allowlist(data, cfg)
    if (length(v)) return(v)
  }
  environment_resolve_voc_columns(data, cfg)
}

#' 构建 Table 1 分区：临床变量在前，Environmental Toxicants 在最后
environment_build_table1_sections <- function(cfg, data) {
  cfg <- cfg %||% list()
  all_env <- if (!is.null(data) && ncol(data)) {
    environment_clinical_voc_gate_columns(data, cfg)
  } else {
    character(0)
  }
  voc <- environment_table1_voc_vars(data, cfg)
  voc <- unique(c(voc[nzchar(voc)], setdiff(all_env, voc)))
  if (!is.null(data) && ncol(data)) voc <- intersect(voc, names(data))
  bl <- cfg$baseline_nhanes %||% cfg$baseline %||% list()
  if (isTRUE(bl$table1_sections_disable_default) &&
      length(bl$table1_sections %||% list()) > 0L) {
    base_sec <- as.list(bl$table1_sections)
  } else if (exists(".default_table1_sections", mode = "function")) {
    base_sec <- utils::modifyList(
      as.list(.default_table1_sections()),
      as.list(bl$table1_sections %||% list())
    )
  } else {
    base_sec <- as.list(bl$table1_sections %||% list())
  }
  if (length(voc)) {
    for (nm in names(base_sec)) {
      base_sec[[nm]] <- setdiff(
        unique(as.character(unlist(base_sec[[nm]], use.names = FALSE))),
        voc
      )
    }
    base_sec[["Environmental Toxicants"]] <- voc
  }
  base_sec
}

#' 写入 baseline_nhanes$table1_sections（含 Environmental Toxicants 小节）
environment_patch_table1_sections <- function(cfg, data) {
  cfg <- cfg %||% list()
  if (is.null(data) || !ncol(data)) return(cfg)
  cfg <- environment_patch_voc_exclude(cfg, data)
  bl_key <- if (!is.null(cfg$baseline_nhanes)) "baseline_nhanes" else "baseline"
  bl <- cfg[[bl_key]] %||% list()
  bl$table1_sections <- environment_build_table1_sections(cfg, data)
  cfg[[bl_key]] <- bl
  cfg
}

#' 分析变量排序：临床按 Table 1 分区，环境毒物整组置底（voc_columns 顺序）
environment_sort_analysis_vars <- function(vars, cfg, data = NULL) {
  vars <- unique(as.character(vars[nzchar(vars)]))
  if (!length(vars)) return(vars)
  if (!is.null(data) && exists("environment_patch_table1_sections", mode = "function")) {
    cfg <- environment_patch_table1_sections(cfg, data)
  }
  voc <- if (!is.null(data)) intersect(environment_table1_voc_vars(data, cfg), vars) else character(0)
  clinical <- setdiff(vars, voc)
  clinical_sorted <- if (exists("sort_vars_by_table1_sections", mode = "function")) {
    sort_vars_by_table1_sections(clinical, cfg)
  } else {
    clinical
  }
  c(clinical_sorted, voc)
}

#' 返回变量所属 Table 1 小节名（用于插补表插入子标题行）
environment_var_table1_section <- function(v, sections) {
  v <- as.character(v)[1L]
  if (is.null(sections) || !length(sections)) return(NULL)
  for (nm in names(sections)) {
    sv <- unique(as.character(unlist(sections[[nm]], use.names = FALSE)))
    sv <- sv[nzchar(sv)]
    if (v %in% sv) return(nm)
  }
  NULL
}

#' 环境毒物/VOC 白名单（WQS/BKMR/LASSO 混合物成员只能从此列表选）
environment_voc_allowlist <- function(data, cfg) {
  cfg <- cfg %||% list()
  vocs <- as.character((cfg$environment %||% list())$voc_columns %||% character(0))
  vocs <- unique(vocs[nzchar(vocs)])
  if (!length(vocs)) {
    vocs <- as.character((cfg$incidence %||% list())$index_exclude_vars %||% character(0))
    vocs <- unique(vocs[nzchar(vocs)])
  }
  if (!length(vocs) && exists("environment_resolve_voc_columns", mode = "function")) {
    vocs <- environment_resolve_voc_columns(data, cfg)
  }
  if (!is.null(data) && ncol(data)) {
    vocs <- intersect(vocs, names(data))
  }
  excl <- environment_voc_exclude_fixed(cfg)
  if (length(excl)) vocs <- setdiff(vocs, excl)
  unique(vocs[nzchar(vocs)])
}

#' 仅保留环境毒物列（剔除 Age/RBC/Chloride 等临床变量）
environment_intersect_voc_only <- function(candidates, data, cfg) {
  allow <- environment_voc_allowlist(data, cfg)
  if (!length(allow)) return(character(0))
  intersect(unique(as.character(candidates[nzchar(candidates)])), allow)
}

environment_min_mixture_n <- function(cfg, key, default = 4L) {
  blk <- cfg[[key]] %||% list()
  as.integer(blk$min_select_vocs %||% blk$min_select_n %||% default)[1L]
}

environment_enforce_min_selection <- function(selected, ranked_pool, min_n = 4L,
                                              max_n = NULL) {
  selected <- unique(as.character(selected[nzchar(selected)]))
  ranked_pool <- unique(as.character(ranked_pool[nzchar(ranked_pool)]))
  min_n <- max(1L, as.integer(min_n)[1L])
  if (length(selected) >= min_n) {
    out <- selected
  } else {
    fill <- setdiff(ranked_pool, selected)
    need <- min_n - length(selected)
    out <- if (need <= 0L) {
      selected
    } else if (length(fill) >= need) {
      c(selected, fill[seq_len(need)])
    } else {
      c(selected, fill)
    }
  }
  if (!is.null(max_n)) {
    max_n <- as.integer(max_n)[1L]
    if (is.finite(max_n) && max_n >= min_n && length(out) > max_n) {
      out <- out[seq_len(max_n)]
    }
  }
  out
}

#' 构建纯 VOC 排序候选池（LASSO 单因素 → GLM → LASSO 最终；禁止 allowlist 越界扩充）
environment_build_voc_ranked_pool <- function(ctx, data, cfg, seeds = character(0)) {
  seeds <- unique(as.character(seeds[nzchar(seeds)]))
  extra <- c(
    as.character(ctx$results$select_vocs_glm %||% character(0)),
    as.character(ctx$results$select_vocs_lasso %||% character(0)),
    as.character(ctx$results$select_vocs_univar %||% character(0)),
    as.character(ctx$results$select_vocs %||% character(0))
  )
  pool <- unique(c(seeds, extra))
  if (exists("environment_intersect_voc_only", mode = "function")) {
    pool <- environment_intersect_voc_only(pool, data, cfg)
  }
  if (exists("environment_rank_vocs_by_glm_p", mode = "function") &&
      !is.null(ctx$results$glm_environment_table) &&
      nrow(ctx$results$glm_environment_table)) {
    ranked <- environment_rank_vocs_by_glm_p(ctx, pool)
    pool <- unique(c(ranked, setdiff(pool, ranked)))
  }
  lasso_pool <- unique(as.character(ctx$results$select_vocs_lasso %||% character(0)))
  lasso_pool <- lasso_pool[nzchar(lasso_pool)]
  if (length(lasso_pool)) {
    pool <- unique(c(lasso_pool, intersect(pool, lasso_pool), setdiff(pool, lasso_pool)))
  }
  pool
}

#' 校验 LASSO 入选数不少于混合物（WQS/BKMR）成员数
environment_assert_lasso_superset <- function(ctx, mixture_vocs, label = "mixture") {
  lasso <- unique(as.character(ctx$results$select_vocs_lasso %||% character(0)))
  mix   <- unique(as.character(mixture_vocs[nzchar(mixture_vocs)]))
  if (!length(mix)) return(invisible(TRUE))
  if (length(lasso) < length(mix)) {
    cli::cli_alert_warning(
      "LASSO 入选 {length(lasso)} 个 < {label} {length(mix)} 个；请提高 lasso_environment$min_select_vocs 或放宽 LASSO 阈值。"
    )
    return(invisible(FALSE))
  }
  missing <- setdiff(mix, lasso)
  if (length(missing)) {
    cli::cli_alert_warning(
      "{label} 成员 {paste(missing, collapse = ', ')} 不在 LASSO 池中。"
    )
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

environment_strict_glm_vocs_enabled <- function(cfg, cfg_key = NULL) {
  cfg <- cfg %||% list()
  bc  <- cfg$environment_batch %||% list()
  if (!is.null(bc$strict_glm_vocs)) {
    return(isTRUE(bc$strict_glm_vocs))
  }
  if (!is.null(cfg_key) && !is.null(cfg[[cfg_key]]$strict_glm_vocs)) {
    return(isTRUE(cfg[[cfg_key]]$strict_glm_vocs))
  }
  TRUE
}

#' GLM 通过后 VOC 列表（WQS/BKMR/RCS/尾段优先来源）
environment_glm_passed_vocs <- function(ctx) {
  v <- as.character(
    ctx$results$select_vocs_glm %||%
      ctx$results$select_vocs_final %||%
      character(0)
  )
  unique(v[nzchar(v)])
}

#' WQS/BKMR 混合物成员：strict_glm_vocs=TRUE 时仅用 GLM 通过者，不补足 LASSO 池
environment_resolve_mixture_vocs <- function(ctx, data, cfg, cfg_key,
                                             bl_select = character(0)) {
  blk <- cfg[[cfg_key]] %||% list()
  strict_glm <- environment_strict_glm_vocs_enabled(cfg, cfg_key)

  select_vocs <- as.character(bl_select)
  if (!length(select_vocs)) {
    select_vocs <- if (strict_glm) {
      environment_glm_passed_vocs(ctx)
    } else {
      as.character(
        ctx$results$select_vocs_final %||%
          ctx$results$select_vocs %||%
          character(0)
      )
    }
  }
  if (exists("environment_intersect_voc_only", mode = "function")) {
    select_vocs <- environment_intersect_voc_only(select_vocs, data, cfg)
  }
  select_vocs <- intersect(select_vocs, names(data))
  default_min <- if (strict_glm) 1L else 4L
  min_n <- environment_min_mixture_n(cfg, cfg_key, default_min)
  ranked_pool <- environment_build_voc_ranked_pool(ctx, data, cfg, select_vocs)
  if (!strict_glm) {
    select_vocs <- environment_enforce_min_selection(select_vocs, ranked_pool, min_n)
  } else {
    select_vocs <- unique(select_vocs[nzchar(select_vocs)])
  }
  list(vocs = select_vocs, min_n = min_n, ranked_pool = ranked_pool, strict_glm = strict_glm)
}

environment_is_p_significant <- function(p_raw, threshold = 0.05) {
  p_raw <- as.character(p_raw)
  if (!nzchar(p_raw)) return(FALSE)
  if (grepl("^P\\s*<", p_raw, ignore.case = TRUE)) return(TRUE)
  if (grepl("e", p_raw, ignore.case = TRUE)) return(TRUE)
  p_num <- suppressWarnings(as.numeric(p_raw))
  !is.na(p_num) && p_num < threshold
}

#' 从 GLM 四分位表指定行提取三模型 P 值（X6/X9/X12）
environment_glm_row_pvals <- function(rt, row_label) {
  if (is.null(rt) || !nrow(rt)) {
    return(list(crude = NA_character_, model1 = NA_character_, model2 = NA_character_))
  }
  x1  <- trimws(as.character(rt$X1))
  idx <- which(x1 == row_label)
  if (!length(idx)) {
    return(list(crude = NA_character_, model1 = NA_character_, model2 = NA_character_))
  }
  i <- idx[1L]
  list(
    crude  = as.character(rt$X6[i]),
    model1 = as.character(rt$X9[i]),
    model2 = as.character(rt$X12[i])
  )
}

#' 从 GLM 四分位表 continuous 行提取三模型 P 值（X6/X9/X12）
environment_glm_continuous_pvals <- function(rt) {
  if (is.null(rt) || !nrow(rt)) {
    return(list(crude = NA_character_, model1 = NA_character_, model2 = NA_character_))
  }
  x1  <- trimws(as.character(rt$X1))
  idx <- grep(" continuous$", x1)
  if (!length(idx)) {
    return(list(crude = NA_character_, model1 = NA_character_, model2 = NA_character_))
  }
  environment_glm_row_pvals(rt, x1[idx[1L]])
}

environment_glm_pvals_significant <- function(pvals, models, p_threshold) {
  models <- intersect(as.character(models), c("crude", "model1", "model2"))
  if (!length(models)) return(TRUE)
  all(vapply(models, function(m) {
    environment_is_p_significant(pvals[[m]], p_threshold)
  }, logical(1L)))
}

#' GLM 完整筛选：continuous + Q2/Q3/Q4 至少一个 + p for trend
environment_glm_screen_pass <- function(
    rt,
    p_threshold = 0.05,
    require_quartile_any = TRUE,
    require_trend = TRUE,
    quartile_models = c("model2"),
    trend_models = c("crude", "model1", "model2"),
    continuous_models = c("crude", "model1", "model2"),
    non_ref_groups = c("Q2", "Q3", "Q4")
) {
  pv_cont <- environment_glm_continuous_pvals(rt)
  if (!environment_is_p_significant(pv_cont$crude, p_threshold)) {
    return(list(pass = FALSE, reason = "crude_not_significant", pvals = pv_cont))
  }
  if (!environment_glm_pvals_significant(pv_cont, continuous_models, p_threshold)) {
    miss <- setdiff(continuous_models, c("crude"))
    miss <- miss[!vapply(miss, function(m) {
      environment_is_p_significant(pv_cont[[m]], p_threshold)
    }, logical(1L))]
    return(list(
      pass = FALSE,
      reason = paste0("continuous_not_significant:", paste(miss, collapse = ",")),
      pvals = pv_cont
    ))
  }

  if (isTRUE(require_quartile_any)) {
    q_labels <- as.character(non_ref_groups %||% c("Q2", "Q3", "Q4"))
    q_labels <- q_labels[nzchar(q_labels)]
    if (!length(q_labels)) q_labels <- c("Q2", "Q3", "Q4")
    q_ok <- any(vapply(q_labels, function(q) {
      pv_q <- environment_glm_row_pvals(rt, q)
      environment_glm_pvals_significant(pv_q, quartile_models, p_threshold)
    }, logical(1L)))
    if (!q_ok) {
      return(list(pass = FALSE, reason = "quartile_none_significant", pvals = pv_cont))
    }
  }

  if (isTRUE(require_trend)) {
    pv_trend <- environment_glm_row_pvals(rt, "p for trend")
    if (!environment_glm_pvals_significant(pv_trend, trend_models, p_threshold)) {
      return(list(pass = FALSE, reason = "trend_not_significant", pvals = pv_cont))
    }
  }

  list(pass = TRUE, reason = "ok", pvals = pv_cont)
}

#' continuous 行：crude 不显著则剔除；crude 显著则要求 Model1/Model2 均显著
environment_glm_continuous_pass <- function(rt, p_threshold = 0.05, ...) {
  environment_glm_screen_pass(
    rt,
    p_threshold = p_threshold,
    require_quartile_any = FALSE,
    require_trend = FALSE,
    ...
  )
}

#' 将堆叠 GLM 表按 VOC 分块（每块含 continuous / Q1–Q4 / p for trend）
environment_glm_split_voc_blocks <- function(tab) {
  if (is.null(tab) || !nrow(tab)) return(list())
  x1 <- trimws(as.character(tab$X1))
  cont_idx <- grep(" continuous$", x1)
  if (!length(cont_idx)) return(list())
  lapply(seq_along(cont_idx), function(j) {
    start <- cont_idx[j]
    end <- if (j < length(cont_idx)) cont_idx[j + 1L] - 1L else nrow(tab)
    tab[start:end, , drop = FALSE]
  })
}

environment_screen_glm_continuous_table <- function(
    tab,
    p_threshold = 0.05,
    require_quartile_any = TRUE,
    require_trend = TRUE,
    ...
) {
  blocks <- environment_glm_split_voc_blocks(tab)
  if (!length(blocks)) return(character(0))

  keep <- character(0)
  for (blk in blocks) {
    chk <- environment_glm_screen_pass(
      blk,
      p_threshold = p_threshold,
      require_quartile_any = require_quartile_any,
      require_trend = require_trend,
      ...
    )
    if (!isTRUE(chk$pass)) next
    x1 <- trimws(as.character(blk$X1))
    voc <- gsub(" continuous$", "", x1[grep(" continuous$", x1)][1L])
    keep <- c(keep, voc)
  }
  unique(keep[nzchar(keep)])
}

environment_rank_vocs_by_glm_p <- function(ctx, candidates) {
  candidates <- unique(as.character(candidates[nzchar(candidates)]))
  tab <- ctx$results$glm_environment_table
  if (is.null(tab) || !nrow(tab)) {
    return(candidates)
  }
  x1 <- as.character(tab$X1)
  cont_idx <- grepl(" continuous", x1, fixed = TRUE)
  if (!any(cont_idx)) return(candidates)
  p_raw <- as.character(tab$X12[cont_idx])
  voc <- gsub(" continuous", "", x1[cont_idx], fixed = TRUE)
  ord <- order(suppressWarnings(as.numeric(p_raw)), na.last = TRUE)
  ranked <- voc[ord]
  ranked <- ranked[ranked %in% candidates]
  c(ranked, setdiff(candidates, ranked))
}

environment_bkmr_iter_candidates <- function(bl_cfg) {
  bl_cfg <- bl_cfg %||% list()
  explicit <- bl_cfg$iter_candidates
  if (!is.null(explicit) && length(explicit)) {
    cands <- unique(as.integer(explicit))
  } else {
    min_iter <- as.integer(bl_cfg$min_iter_candidate %||% 100L)[1L]
    max_iter <- as.integer(bl_cfg$max_iter_candidate %||% 10000L)[1L]
    step     <- as.integer(bl_cfg$iter_candidate_step %||% 500L)[1L]
    min_iter <- max(100L, min_iter)
    max_iter <- max(min_iter, max_iter)
    step     <- max(50L, step)
    grid_start <- max(min_iter, 500L)
    cands <- unique(c(
      min_iter,
      seq(grid_start, max_iter, by = step)
    ))
    if (!max_iter %in% cands) cands <- c(cands, max_iter)
  }
  unique(cands[cands >= max(100L, as.integer(bl_cfg$min_iter_candidate %||% 100L)[1L])])
}

#' 环境流水线协变量 fallback（单因素/VIF 无结果时使用预设 Model1/2）
environment_covariate_fallback_cfg <- function(cfg) {
  cfg <- cfg %||% list()
  eb  <- cfg$environment_batch %||% list()
  fb  <- eb$covariate_fallback %||% list()
  if (!isTRUE(fb$enable)) return(NULL)
  m1 <- as.character(fb$model1 %||% (cfg$multivariate_nhanes %||% list())$model1_candidate_names %||% character(0))
  m2 <- as.character(fb$model2 %||% character(0))
  if (!length(m2) && length(m1)) {
    m2 <- c(m1, "Smoking", "BMI", "NBPS", "NBPD", "Diabetes", "Hypertension")
  }
  if (!length(m2)) return(NULL)
  if (!length(m1)) m1 <- intersect(m2, c("Age", "Gender", "Race", "PIR", "Education"))
  list(model1 = unique(m1[nzchar(m1)]), model2 = unique(m2[nzchar(m2)]))
}

#' 跳过临床多因素时：用 VIF screen 结果写入 Model2 / vif_final_pass（供 GLM 协变量池）
environment_finalize_clinical_covariates_without_multivariate <- function(ctx) {
  cfg <- ctx$config %||% list()
  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !ncol(data)) return(ctx)

  m2 <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
  m2 <- intersect(m2[nzchar(m2)], names(data))
  vocs <- if (exists("environment_resolve_voc_columns", mode = "function")) {
    environment_resolve_voc_columns(data, cfg)
  } else {
    character(0)
  }
  m2 <- setdiff(m2, vocs)

  if (!length(m2)) {
    if (exists("environment_inject_covariate_fallback", mode = "function")) {
      return(environment_inject_covariate_fallback(ctx))
    }
    return(ctx)
  }

  mv_cfg <- cfg$multivariate_nhanes %||% list()
  demo_keywords <- as.character(mv_cfg$demo_keywords %||% c(
    "Age", "Gender", "Sex", "Race", "Ethnic", "PIR", "Education"
  ))
  demo_pattern <- paste(demo_keywords, collapse = "|")
  m1 <- m2[grepl(demo_pattern, m2, ignore.case = TRUE)]
  if (!length(m1)) {
    fb <- (cfg$environment_batch %||% list())$covariate_fallback %||% list()
    m1 <- intersect(as.character(fb$model1 %||% character(0)), names(data))
  }
  if (!length(m1)) m1 <- m2

  ctx$results$Model1Factors <- m1
  ctx$results$Model2Factors <- m2
  ctx$results$vif_final_pass <- m2
  ctx$results$final_features <- m2
  ctx$results$nhanes_logistic_M1 <- m1
  ctx$results$nhanes_logistic_M2 <- m2
  cli::cli_alert_info(
    "跳过临床多因素：协变量 Model2 由单因素+VIF screen 确定（{length(m2)} 个，已排除 VOC）"
  )
  ctx
}

environment_inject_covariate_fallback <- function(ctx) {
  cfg <- ctx$config %||% list()
  fb  <- environment_covariate_fallback_cfg(cfg)
  if (is.null(fb)) return(ctx)
  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data)) return(ctx)

  vif_pass <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
  vif_pass <- vif_pass[nzchar(vif_pass)]
  tb1 <- unique(as.character(
    ctx$results$tb1 %||% ctx$results$univar_features %||% character(0)
  ))
  tb1 <- tb1[nzchar(tb1)]
  hardcoded <- FALSE

  if (length(vif_pass)) {
    m2 <- intersect(vif_pass, names(data))
    m1 <- intersect(tb1, names(data))
    if (!length(m1)) m1 <- intersect(intersect(vif_pass, fb$model1), names(data))
    if (!length(m1)) m1 <- intersect(fb$model1, names(data))
    cli::cli_alert_warning(
      "协变量多因素无结果，回退单因素+VIF 筛后变量（Model2: {paste(m2, collapse = ', ')}）"
    )
  } else if (length(tb1)) {
    m2 <- intersect(tb1, names(data))
    m1 <- intersect(intersect(tb1, fb$model1), names(data))
    if (!length(m1)) m1 <- intersect(fb$model1, names(data))
    cli::cli_alert_warning(
      "协变量 VIF 无结果，回退单因素显著变量（Model2: {paste(m2, collapse = ', ')}）"
    )
  } else {
    m2 <- intersect(fb$model2, names(data))
    m1 <- intersect(fb$model1, names(data))
    hardcoded <- TRUE
    cli::cli_alert_warning(
      "协变量筛选无结果，使用 environment_batch$covariate_fallback 预设（Model1: {paste(m1, collapse = ', ')}；Model2: {paste(m2, collapse = ', ')}）"
    )
  }
  if (!length(m2)) return(ctx)
  if (!length(m1)) m1 <- m2
  ctx$results$tb_screen         <- m2
  ctx$results$tb1               <- if (length(m1)) m1 else m2
  ctx$results$vif_screen_pass   <- m2
  ctx$results$Model1Factors     <- m1
  ctx$results$Model2Factors     <- m2
  ctx$results$vif_final_pass    <- m2
  ctx$results$final_features    <- m2
  ctx$results$univar_features   <- m2
  ctx$results$tb2               <- m2
  ctx$results$multivar_features <- m2
  ctx$results$nhanes_logistic_M1 <- m1
  ctx$results$nhanes_logistic_M2 <- m2
  if (is.null(ctx$results$univar_coef) || !is.data.frame(ctx$results$univar_coef) || !nrow(ctx$results$univar_coef)) {
    ctx$results$univar_coef <- data.frame(
      term = m2, estimate = 0, p.value = 0.05, stringsAsFactors = FALSE
    )
  }
  ctx$results$environment_covariate_fallback_used <- TRUE
  ctx$results$environment_covariate_hardcoded_fallback <- hardcoded
  ctx
}

environment_bkmr_overall_quality <- function(risks_overall) {
  if (is.null(risks_overall) || !nrow(risks_overall)) {
    return(list(ok = FALSE, score = -Inf, mono = FALSE, right_no_cross = FALSE))
  }
  o <- risks_overall[order(risks_overall$quantile), , drop = FALSE]
  est <- as.numeric(o$est)
  sd  <- as.numeric(o$sd)
  if (any(!is.finite(est))) {
    return(list(ok = FALSE, score = -Inf, mono = FALSE, right_no_cross = FALSE))
  }
  diffs <- diff(est)
  mono <- length(diffs) > 0L && all(diffs > 0, na.rm = TRUE)
  last <- length(est)
  right_lo <- est[last] - 1.96 * sd[last]
  right_no_cross <- is.finite(right_lo) && right_lo > 0
  score <- if (right_no_cross) est[last] else est[last] - abs(min(0, right_lo))
  list(ok = mono && right_no_cross, score = score, mono = mono, right_no_cross = right_no_cross)
}

environment_bkmr_quick_fit <- function(y, Z, X = NULL, iter = 300L, nchains = 2L,
                                       family = "binomial", seed = 123L, varsel = TRUE) {
  if (!requireNamespace("bkmrhat", quietly = TRUE) ||
      !requireNamespace("bkmr", quietly = TRUE)) {
    return(NULL)
  }
  nchains <- max(2L, min(as.integer(nchains)[1L], parallel::detectCores(logical = FALSE)))
  iter <- max(100L, as.integer(iter)[1L])
  old_plan <- future::plan(future::sequential)
  on.exit(try(future::plan(old_plan), silent = TRUE), add = TRUE)
  future::plan(future::multisession, workers = nchains)
  set.seed(seed)
  fit_args <- list(
    nchains = nchains, y = y, Z = Z, est.h = TRUE,
    family = family, iter = iter, verbose = FALSE, varsel = varsel
  )
  if (!is.null(X)) fit_args$X <- X
  fit <- tryCatch(do.call(bkmrhat::kmbayes_parallel, fit_args), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  comb <- tryCatch(bkmrhat::kmbayes_combine(fit), error = function(e) NULL)
  if (is.null(comb)) return(NULL)
  risks <- tryCatch(
    bkmr::OverallRiskSummaries(
      fit = comb, X = X, y = y, Z = Z,
      qs = seq(0.4, 0.6, by = 0.02), method = "exact"
    ),
    error = function(e) NULL
  )
  list(fit = fit, combined = comb, risks = risks,
         quality = environment_bkmr_overall_quality(risks))
}

environment_prepare_bkmr_inputs <- function(data, outcome_col, analysis_grp, reference_grp,
                                           select_vocs, covariates) {
  keep_cols <- unique(c(outcome_col, covariates, select_vocs))
  d <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L) return(NULL)

  yraw <- d[[outcome_col]]
  if (is.numeric(yraw) && all(stats::na.omit(unique(yraw)) %in% c(0, 1))) {
    y <- as.integer(yraw)
  } else {
    yc <- trimws(as.character(yraw))
    y  <- ifelse(yc == trimws(analysis_grp), 1L,
                 ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
  }
  ok <- !is.na(y)
  y <- y[ok]; d <- d[ok, , drop = FALSE]
  Z <- scale(as.matrix(d[, select_vocs, drop = FALSE]))
  if (any(is.nan(Z))) Z[is.nan(Z)] <- 0
  X <- NULL
  if (length(covariates)) {
    cov <- d[, covariates, drop = FALSE]
    for (col in names(cov)) {
      if (!is.numeric(cov[[col]])) {
        cov[[col]] <- as.numeric(as.factor(trimws(as.character(cov[[col]]))))
      }
      cov[[col]][is.na(cov[[col]])] <- 0
    }
    X <- cov
  }
  list(y = y, Z = Z, X = X, n = length(y))
}

environment_wqs_subset_score <- function(vocs, data_wqs, outcome_col, covariates,
                                         y, Z, X, wqs_cfg, bkmr_search_cfg) {
  vocs <- as.character(vocs)
  if (length(vocs) < 2L) return(list(score = -Inf, wqs_p = NA_real_, quality = NULL))

  fml <- if (length(covariates)) {
    stats::as.formula(paste0(outcome_col, " ~ wqs + ", paste(covariates, collapse = "+")))
  } else {
    stats::as.formula(paste0(outcome_col, " ~ wqs"))
  }

  fit <- tryCatch(
    gWQS::gwqs(
      formula = fml, mix_name = vocs, data = data_wqs,
      q = wqs_cfg$q %||% 4L,
      validation = wqs_cfg$validation %||% 0.7,
      b = wqs_cfg$b %||% 200L,
      b1_pos = isTRUE(wqs_cfg$b1_pos %||% TRUE),
      b1_constr = isTRUE(wqs_cfg$b1_constr %||% FALSE),
      family = wqs_cfg$family %||% "binomial",
      seed = wqs_cfg$seed %||% 2025L
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(score = -Inf, wqs_p = NA_real_, quality = NULL))

  sm <- tryCatch(summary(fit), error = function(e) NULL)
  wqs_p <- NA_real_
  if (!is.null(sm) && "wqs" %in% rownames(sm$coefficients)) {
    p_col <- grep("Pr\\(>", colnames(sm$coefficients), value = TRUE)[1L]
    if (!is.na(p_col)) wqs_p <- sm$coefficients["wqs", p_col]
  }

  voc_in_z <- intersect(colnames(Z), vocs)
  if (length(voc_in_z) < 2L) return(list(score = -Inf, wqs_p = wqs_p, quality = NULL))
  Z_sub <- Z[, voc_in_z, drop = FALSE]

  quick <- environment_bkmr_quick_fit(
    y = y, Z = Z_sub, X = X,
    iter = bkmr_search_cfg$iter %||% 300L,
    nchains = bkmr_search_cfg$nchains %||% 2L,
    seed = bkmr_search_cfg$seed %||% 123L
  )
  q <- quick$quality %||% list(ok = FALSE, score = -Inf)
  wqs_bonus <- if (!is.na(wqs_p) && wqs_p < 0.05) 1 else 0
  score <- (q$score %||% -Inf) + wqs_bonus + if (isTRUE(q$ok)) 10 else 0
  list(score = score, wqs_p = wqs_p, quality = q, fit = fit)
}

environment_auto_select_wqs_vocs <- function(ctx, candidates, data, outcome_col,
                                            analysis_grp, reference_grp,
                                            covariates, bl_cfg) {
  cfg <- ctx$config %||% list()
  if (exists("environment_intersect_voc_only", mode = "function")) {
    candidates <- environment_intersect_voc_only(candidates, data, cfg)
  }
  candidates <- unique(as.character(candidates[nzchar(candidates)]))
  min_n <- environment_min_mixture_n(ctx$config, "wqs_environment", 4L)
  if (length(candidates) <= min_n) {
    return(environment_enforce_min_selection(candidates, candidates, min_n))
  }

  ranked <- environment_rank_vocs_by_glm_p(ctx, candidates)
  prep <- environment_prepare_bkmr_inputs(
    data, outcome_col, analysis_grp, reference_grp, ranked, covariates
  )
  if (is.null(prep)) {
    return(environment_enforce_min_selection(ranked, ranked, min_n))
  }

  keep_cols <- unique(c(outcome_col, covariates, ranked))
  data_wqs <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  data_wqs <- data_wqs[stats::complete.cases(data_wqs), , drop = FALSE]

  search_cfg <- bl_cfg$auto_select %||% list()
  max_size <- min(
    length(ranked),
    as.integer(search_cfg$max_subset_size %||% length(ranked))[1L]
  )
  max_size <- max(min_n, max_size)
  max_trials <- as.integer(search_cfg$max_trials %||% 40L)[1L]

  wqs_search <- list(
    q = bl_cfg$q_values[1L] %||% 4L,
    validation = bl_cfg$validation_values[1L] %||% 0.7,
    b = as.integer(search_cfg$quick_b %||% 200L),
    b1_pos = bl_cfg$b1_pos,
    b1_constr = bl_cfg$b1_constr,
    family = bl_cfg$family,
    seed = bl_cfg$seed
  )
  bkmr_search <- list(
    iter = as.integer(search_cfg$bkmr_quick_iter %||% 300L),
    nchains = as.integer(search_cfg$bkmr_quick_nchains %||% 2L),
    seed = bl_cfg$seed %||% 123L
  )

  best_vocs <- ranked[seq_len(min_n)]
  best_score <- -Inf
  trials <- 0L

  for (sz in min_n:max_size) {
    if (sz <= length(ranked)) {
      trial_sets <- list(ranked[seq_len(sz)])
    } else {
      trial_sets <- list()
    }
    if (sz == min_n && length(ranked) > min_n) {
      trial_sets <- c(trial_sets, list(ranked[seq_len(min_n)]))
    }
    if (sz > min_n) {
      extra_pool <- ranked[(min_n + 1L):min(length(ranked), min_n + 3L)]
      for (v in extra_pool) {
        trial_sets <- c(trial_sets, list(unique(c(best_vocs, v))))
      }
    }

    for (vocs_try in trial_sets) {
      trials <- trials + 1L
      if (trials > max_trials) break
      sc <- environment_wqs_subset_score(
        vocs_try, data_wqs, outcome_col, covariates,
        prep$y, prep$Z, prep$X, wqs_search, bkmr_search
      )
      if (is.finite(sc$score) && sc$score > best_score) {
        best_score <- sc$score
        best_vocs <- vocs_try
      }
      if (!is.null(sc$quality) && isTRUE(sc$quality$ok)) {
        cli::cli_alert_success(
          "WQS 自动选变量: {paste(vocs_try, collapse = ', ')}（BKMR 质量达标）"
        )
        return(vocs_try)
      }
    }
    if (trials > max_trials) break
  }

  out <- environment_enforce_min_selection(best_vocs, ranked, min_n)
  cli::cli_alert_info(
    "WQS 自动选变量: {paste(out, collapse = ', ')}（score={round(best_score, 3)}）"
  )
  out
}

environment_auto_select_bkmr_iter <- function(y, Z, X, bl_cfg) {
  auto <- isTRUE(bl_cfg$auto_iter %||% TRUE)
  if (!auto) {
    return(list(
      iter = as.integer(bl_cfg$iter %||% 1000L),
      fit = NULL, combined = NULL, risks = NULL, quality = NULL
    ))
  }

  cands <- environment_bkmr_iter_candidates(bl_cfg)
  nchains <- as.integer(bl_cfg$nchains %||% max(2L, floor(parallel::detectCores(logical = FALSE) / 2L)))
  family <- as.character(bl_cfg$family %||% "binomial")
  base_seed <- as.integer(bl_cfg$seed %||% 123L)
  seed_retries <- as.integer(bl_cfg$seed_retries %||% 3L)[1L]
  seeds <- unique(c(base_seed, base_seed + seq_len(max(0L, seed_retries - 1L)) * 97L))
  varsel <- isTRUE(bl_cfg$varsel %||% TRUE)
  est_h <- isTRUE(bl_cfg$est_h %||% TRUE)
  accept_relaxed <- isTRUE(bl_cfg$accept_relaxed %||% TRUE)
  min_relaxed_score <- as.numeric(bl_cfg$min_relaxed_score %||% 0)[1L]

  best <- list(iter = cands[1L], quality = list(ok = FALSE, score = -Inf))

  for (seed in seeds) {
    for (iter in cands) {
      cli::cli_alert_info("bkmr_fit: 试探 seed={seed}, iter={iter}")
      future::plan(future::multisession, workers = nchains)
      set.seed(seed)
      fit_args <- list(
        nchains = nchains, y = y, Z = Z, est.h = est_h,
        family = family, iter = iter, verbose = FALSE, varsel = varsel
      )
      if (!is.null(X)) fit_args$X <- X
      fit <- tryCatch(do.call(bkmrhat::kmbayes_parallel, fit_args), error = function(e) NULL)
      if (is.null(fit)) next
      comb <- tryCatch(bkmrhat::kmbayes_combine(fit), error = function(e) NULL)
      if (is.null(comb)) next
      risks <- tryCatch(
        bkmr::OverallRiskSummaries(
          fit = comb, X = X, y = y, Z = Z,
          qs = bl_cfg$qs_overall %||% seq(0.4, 0.6, by = 0.02),
          method = "exact"
        ),
        error = function(e) NULL
      )
      q <- environment_bkmr_overall_quality(risks)
      cli::cli_alert_info(
        "  seed={seed}, iter={iter}: mono={q$mono}, right_no_cross={q$right_no_cross}, score={round(q$score, 4)}"
      )
      if (isTRUE(q$ok)) {
        future::plan(future::sequential)
        return(list(iter = iter, fit = fit, combined = comb, risks = risks, quality = q, seed = seed))
      }
      if (is.finite(q$score) && q$score > (best$quality$score %||% -Inf)) {
        best <- list(iter = iter, fit = fit, combined = comb, risks = risks, quality = q, seed = seed)
      }
      if (accept_relaxed && isTRUE(q$right_no_cross) && is.finite(q$score) && q$score >= min_relaxed_score) {
        future::plan(future::sequential)
        cli::cli_alert_info(
          "bkmr_fit: 放宽标准接受 seed={seed}, iter={iter}（mono={q$mono}, score={round(q$score, 4)}）"
        )
        return(list(iter = iter, fit = fit, combined = comb, risks = risks, quality = q, seed = seed))
      }
    }
  }

  if (!is.null(best$fit)) {
    future::plan(future::sequential)
    cli::cli_alert_warning(
      "bkmr_fit: 未找到完全达标 iter，使用 seed={best$seed}, iter={best$iter}（score={round(best$quality$score, 4)}）"
    )
    return(best)
  }

  list(iter = as.integer(bl_cfg$iter %||% 1000L), fit = NULL, combined = NULL,
       risks = NULL, quality = NULL, seed = base_seed)
}
