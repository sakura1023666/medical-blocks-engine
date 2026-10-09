# TST 特征密度闸门：按文献人/变量比决定全收或抽稀
# Spec: docs/superpowers/specs/2026-08-28-tst-feature-density-gate-design.md

#' Assert disease-specific feature_priority_file (anti cross-disease reuse)
#'
#' When whitelist/density_gate: require priority file; PAUSE if basename looks like
#' another disease (aki_/stroke_) while project$disease does not match.
tst_assert_disease_feature_priority <- function(cfg, ts_cfg) {
  mode <- as.character(ts_cfg$feature_select_mode %||% "coverage")[1L]
  if (!mode %in% c("whitelist", "density_gate")) {
    return(invisible(NULL))
  }
  path <- as.character(ts_cfg$feature_priority_file %||% "")[1L]
  if (!nzchar(path)) {
    stop(
      "PAUSE_FOR_USER_DECISION: feature_select_mode=", mode,
      " 但未设置 feature_priority_file。",
      " 请先落盘 configs/tst_feature_priority/<disease>_<db>.R 并写入 config。",
      call. = FALSE
    )
  }
  if (!file.exists(path)) {
    stop(
      "PAUSE_FOR_USER_DECISION: feature_priority_file 不存在: ", path,
      " / 请先查本病白名单并落盘。",
      call. = FALSE
    )
  }
  disease <- tolower(paste(
    as.character(cfg$project$disease %||% ""),
    as.character(cfg$project$name %||% ""),
    as.character(cfg$project$disease_code %||% ""),
    collapse = " "
  ))
  stem <- tolower(basename(path))
  # known foreign tags → required disease token
  checks <- list(
    list(file_pat = "(^|_)aki(_|$)|aki_mimic|aki_eicu", disease_pat = "aki"),
    list(file_pat = "stroke|ischemic", disease_pat = "stroke|ischemic")
  )
  for (ck in checks) {
    if (grepl(ck$file_pat, stem, perl = TRUE) &&
          !grepl(ck$disease_pat, disease, perl = TRUE)) {
      stop(
        "PAUSE_FOR_USER_DECISION: 病种「",
        as.character(cfg$project$disease %||% cfg$project$name %||% "?")[1L],
        "」却使用他病白名单文件「", basename(path), "」。",
        " 请新建 configs/tst_feature_priority/<disease>_<db>.R 并改 config$tst_timeseries$feature_priority_file。",
        call. = FALSE
      )
    }
  }
  if (exists("cli_alert_info", mode = "function")) {
    cli::cli_alert_info(
      "TST 白名单闸门: disease={as.character(cfg$project$disease %||% '?')[1L]}; file={basename(path)}; mode={mode}"
    )
  }
  invisible(NULL)
}

#' Load named priority list (canonical -> character aliases)
tst_load_feature_priority <- function(ts_cfg, project_root = NULL) {
  pr <- ts_cfg$feature_priority
  if (is.list(pr) && length(pr)) {
    return(pr)
  }
  path <- as.character(ts_cfg$feature_priority_file %||% "")[1L]
  if (!nzchar(path)) {
    return(NULL)
  }
  if (!file.exists(path) && !is.null(project_root)) {
    alt <- file.path(project_root, path)
    if (file.exists(alt)) path <- alt
  }
  if (!file.exists(path)) {
    stop("feature_priority_file 不存在: ", path, call. = FALSE)
  }
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)
  # Prefer explicit getter, else first list-returning function, else first list object
  if (exists("tst_feature_priority_aki_eicu", envir = env, inherits = FALSE)) {
    return(env$tst_feature_priority_aki_eicu())
  }
  fns <- ls(envir = env, pattern = "^tst_feature_priority")
  if (length(fns)) {
    return(env[[fns[[1]]]]())
  }
  objs <- ls(envir = env)
  for (nm in objs) {
    val <- env[[nm]]
    if (is.list(val) && length(val) && !is.function(val)) return(val)
  }
  stop("feature_priority_file 未导出优先级 list: ", path, call. = FALSE)
}

.tst_dg_sanitize <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  ifelse(nzchar(x), x, "feat")
}

#' Build item(raw) -> canonical map from priority list (first alias wins on collision)
tst_priority_item_map <- function(priority) {
  if (!is.list(priority) || !length(priority)) {
    return(list(canon_order = character(0), item_to_canon = character(0)))
  }
  canon_order <- names(priority)
  if (is.null(canon_order) || !any(nzchar(canon_order))) {
    stop("feature_priority 必须是 named list（canonical = aliases）", call. = FALSE)
  }
  item_to_canon <- character(0)
  for (cn in canon_order) {
    als <- unique(as.character(priority[[cn]]))
    als <- als[nzchar(als)]
    for (a in als) {
      if (!a %in% names(item_to_canon)) item_to_canon[[a]] <- cn
      san <- .tst_dg_sanitize(a)
      if (!san %in% names(item_to_canon)) item_to_canon[[san]] <- cn
    }
    if (!cn %in% names(item_to_canon)) item_to_canon[[cn]] <- cn
  }
  list(canon_order = canon_order, item_to_canon = item_to_canon)
}

#' Density gate（临床名单优先）
#'
#' - F* = floor(N / (N_lit/F_lit)) 为原文密度参考维数
#' - 临床名单 ∩ 数据 = F_cand
#' - 若 F_cand >= F*：全收临床名单（可多于比例，如 44）
#' - 若 F_cand <  F*：名单不够 → 用 pad_candidates（通常按覆盖率排序的其它 item）补到 F*
#'
#' @param n_cohort cohort 出组 N
#' @param available_canon 临床优先级中、数据里存在的 canonical（已按优先级排序）
#' @param canon_order 完整优先级顺序（用于排序 available）
#' @param pad_candidates 补齐候选（不含已在 available_canon 中的），已按优先/覆盖率排序
#' @param lit_n, lit_f 文献锚点
#' @param f_star_cap 可选上限（如目标 100–200 维时封顶，避免按全队列 N 算出过大 F*）
tst_density_gate_select <- function(n_cohort, available_canon, canon_order,
                                    pad_candidates = character(0),
                                    lit_n = 13610L, lit_f = 226L,
                                    f_star_cap = NULL) {
  n_cohort <- as.integer(n_cohort)[1L]
  lit_n <- as.numeric(lit_n)[1L]
  lit_f <- as.numeric(lit_f)[1L]
  if (!is.finite(n_cohort) || n_cohort < 1L) {
    stop("density_gate: n_cohort 无效", call. = FALSE)
  }
  if (!is.finite(lit_n) || !is.finite(lit_f) || lit_f <= 0) {
    stop("density_gate: literature_n_patients / literature_n_features 无效", call. = FALSE)
  }
  lit_ratio <- lit_n / lit_f
  f_star <- max(1L, as.integer(floor(n_cohort / lit_ratio)))
  if (!is.null(f_star_cap) && length(f_star_cap) >= 1L) {
    cap <- as.integer(f_star_cap)[1L]
    if (is.finite(cap) && cap >= 1L) {
      f_star <- min(f_star, cap)
    }
  }

  available_canon <- unique(as.character(available_canon))
  available_canon <- available_canon[nzchar(available_canon)]
  available_ordered <- intersect(as.character(canon_order), available_canon)
  extra_in_list <- setdiff(available_canon, available_ordered)
  available_ordered <- c(available_ordered, extra_in_list)
  f_cand <- length(available_ordered)
  if (f_cand < 1L) {
    stop("density_gate: feature_priority 与数据 item 无交集", call. = FALSE)
  }

  pad_candidates <- unique(as.character(pad_candidates))
  pad_candidates <- setdiff(pad_candidates[nzchar(pad_candidates)], available_ordered)

  ratio_if_all_clinical <- n_cohort / f_cand

  if (f_cand >= f_star) {
    list(
      decision = "keep_clinical_all",
      keep_canon = available_ordered,
      f_cand = f_cand,
      f_star = f_star,
      n_kept = f_cand,
      n_cohort = n_cohort,
      ratio = ratio_if_all_clinical,
      lit_ratio = lit_ratio,
      literature_n_patients = lit_n,
      literature_n_features = lit_f,
      n_padded = 0L
    )
  } else {
    n_need <- f_star - f_cand
    pad_take <- pad_candidates[seq_len(min(n_need, length(pad_candidates)))]
    keep <- c(available_ordered, pad_take)
    list(
      decision = "pad_to_ratio",
      keep_canon = keep,
      f_cand = f_cand,
      f_star = f_star,
      n_kept = length(keep),
      n_cohort = n_cohort,
      ratio = n_cohort / max(length(keep), 1L),
      lit_ratio = lit_ratio,
      literature_n_patients = lit_n,
      literature_n_features = lit_f,
      n_padded = length(pad_take)
    )
  }
}
