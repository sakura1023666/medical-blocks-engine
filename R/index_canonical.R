###############################################################################
#  index_canonical.R — 复合指标规范名 / 别名（全流水线复用）
#
#  同一公式只保留一个 canonical 名参与批量循环；旧名/原始列名作 alias 剔除。
###############################################################################

.index_alias_to_canonical <- function() {
  c(
    UA_CrR  = "UA_CR",  # 旧引擎名；公式 Uric_Acid / Creatinine
    UA_Cr   = "UA_CR",  # 部分原始表列名
    TyGWHtR = "TyG_WHtR" # NHANES 原始列名；引擎规范名 TyG_WHtR
  )
}

#' 单指标规范名；未知名原样返回
index_canonical_name <- function(x) {
  x <- as.character(x)[1L]
  if (!nzchar(x) || is.na(x)) return(x)
  aliases <- .index_alias_to_canonical()
  # R 4.6+：命名原子向量对不存在的名用 [[ 会 subscript out of bounds；改用 %in% + [
  if (!x %in% names(aliases)) return(x)
  canon <- unname(aliases[x])[1L]
  if (!is.na(canon) && nzchar(canon)) return(canon)
  x
}

#' 向量规范名：alias→canonical，去重保序（canonical 优先于 alias）
index_canonicalize_names <- function(x) {
  x <- unique(as.character(x))
  x <- x[nzchar(x)]
  if (!length(x)) return(character(0))
  aliases <- .index_alias_to_canonical()
  canon <- vapply(x, index_canonical_name, character(1L), USE.NAMES = FALSE)
  # 同一 canonical 只保留一次：若 canonical 与 alias 同批出现，只留 canonical
  out <- character(0)
  seen <- character(0)
  for (i in seq_along(canon)) {
    cnm <- canon[[i]]
    if (cnm %in% seen) next
    seen <- c(seen, cnm)
    out <- c(out, cnm)
  }
  out
}

#' canonical 对应全部 alias（不含 canonical 自身）
index_alias_names <- function(canonical) {
  canonical <- index_canonical_name(canonical)
  aliases <- .index_alias_to_canonical()
  names(aliases)[aliases == canonical]
}

#' 数据里存在 alias 列时，视为 canonical 也可用（旧 checkpoint / 原始列）
index_expand_available_canonical <- function(available, names_in_data, candidate_vars) {
  available <- unique(as.character(available))
  names_in_data <- as.character(names_in_data)
  candidate_vars <- unique(as.character(candidate_vars))
  aliases <- .index_alias_to_canonical()
  for (alias in names(aliases)) {
    # 命名向量：用 %in% + [，避免 R 4.6 [[ 对缺失名报错
    if (!alias %in% names(aliases)) next
    canon <- unname(aliases[alias])[1L]
    if (!canon %in% candidate_vars) next
    if (alias %in% names_in_data) available <- c(available, canon)
  }
  unique(available)
}

#' worker 剔除「其它指标」池：canonical 的全部 alias 并入 other_ix
index_expand_alias_exclusions <- function(active_indices, other_indices) {
  active <- unique(as.character(active_indices))
  other  <- unique(as.character(other_indices))
  if (!length(active)) return(other)
  extra <- unlist(lapply(active, index_alias_names), use.names = FALSE)
  unique(c(other, extra))
}

#' 数据列名：canonical 已存在时剔除其 alias（避免 Table 1 暴露重复行）
index_prune_alias_drop_vars <- function(data_names, cfg = list()) {
  data_names <- unique(as.character(data_names))
  data_names <- data_names[nzchar(data_names)]
  if (!length(data_names)) return(character(0))
  idx <- if (exists("pipeline_analysis_exclusion_resolve_index_var", mode = "function")) {
    pipeline_analysis_exclusion_resolve_index_var(cfg)
  } else {
    as.character((cfg$incidence %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "")[1L]
  }
  if (!nzchar(idx)) return(character(0))
  canon <- index_canonical_name(idx)
  aliases <- setdiff(index_alias_names(canon), canon)
  if (!length(aliases)) return(character(0))
  hit <- intersect(aliases, data_names)
  if (canon %in% data_names) hit else character(0)
}
