###############################################################################
#  dual_db_harmonize.R — 双库发病：闸门 A（插补前列对齐）与闸门 B（VIF 后协变量对齐）
#  依赖 R/utils.R 中的 %||%
###############################################################################

dual_db_harmonization_dir <- function(root, cfg) {
  base <- (cfg$dual_db %||% list())$harmonization_dir %||%
    "checkpoints/D04_Hematocrit_OA_dual/harmonization"
  if (!is_absolute_path(base)) file.path(root, base) else base
}

dual_db_preferred_mediator_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "preferred_mediator.rds")
}

dual_db_save_preferred_mediator <- function(root, cfg, mediator) {
  med <- as.character(mediator %||% "")[1L]
  if (!nzchar(med)) return(invisible(FALSE))
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  saveRDS(list(mediator = med, saved_at = Sys.time()), dual_db_preferred_mediator_path(root, cfg))
  invisible(TRUE)
}

dual_db_load_preferred_mediator <- function(root, cfg) {
  path <- dual_db_preferred_mediator_path(root, cfg)
  if (!file.exists(path)) return(NA_character_)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  as.character(obj$mediator %||% NA_character_)[1L]
}

#' 从 checkpoint 读取中介结果表（预后 mediation_prognosis / 发病 mediation_incidence）
dual_db_load_mediation_result_table <- function(root, cfg, db_name,
                                               result_keys = c(
                                                 "mediation_prognosis",
                                                 "mediation_incidence",
                                                 "mediation_nhanes_weighted"
                                               )) {
  ck_dir <- tryCatch(
    dual_db_checkpoint_dir(root, cfg, db_name),
    error = function(e) NULL
  )
  if (is.null(ck_dir) || !dir.exists(ck_dir)) return(NULL)
  ck_cands <- c(
    file.path(ck_dir, "mediation_prognosis.rds"),
    file.path(ck_dir, "mediation_incidence.rds"),
    file.path(ck_dir, "mediation_nhanes_weighted.rds"),
    list.files(ck_dir, pattern = "mediation.*\\.rds$", full.names = TRUE)
  )
  ck_cands <- unique(ck_cands[file.exists(ck_cands)])
  for (p in ck_cands) {
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    ctx <- obj$ctx %||% obj
    res <- ctx$results %||% list()
    for (k in result_keys) {
      tbl <- res[[k]]
      if (is.data.frame(tbl) && nrow(tbl) > 0L &&
          "Mediator" %in% names(tbl)) {
        return(tbl)
      }
    }
  }
  NULL
}

#' 双库锁定同一路径图中介：
#' 取两库 Mediator 交集，按两库 Prop_Med 均值最大者（优先均值为正）。
#' @return list(best_mediator, mediators, score, detail) 或 NULL
dual_db_lock_shared_best_mediator <- function(root, cfg, db_seq = c("nhanes", "mimic"),
                                              exposure = NULL) {
  bl <- cfg$mediation_prognosis %||% cfg$mediation_incidence %||% list()
  if (!isTRUE(bl$dual_db_lock_best_mediator %||% TRUE)) return(NULL)
  if (length(db_seq) < 2L) return(NULL)

  exposure <- as.character(
    exposure %||% bl$exposure %||%
      (cfg$survival %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% ""
  )[1L]

  .clean_meds <- function(tbl) {
    if (is.null(tbl) || !is.data.frame(tbl) || !nrow(tbl)) return(character(0))
    m <- as.character(tbl$Mediator %||% character(0))
    pm <- suppressWarnings(as.numeric(tbl$Prop_Med_num %||% NA_real_))
    keep <- nzchar(m) & !is.na(m)
    keep <- keep & !grepl("_(quartile|tertile|quintile|binary|Group)$", m, ignore.case = TRUE)
    if (nzchar(exposure)) {
      keep <- keep & !identical(tolower(m), tolower(exposure))
      keep <- keep & !startsWith(tolower(m), paste0(tolower(exposure), "_"))
    }
    # 要求 Prop_Med 有限
    keep <- keep & is.finite(pm)
    unique(m[keep])
  }

  .prop <- function(tbl, med) {
    if (is.null(tbl) || !nrow(tbl)) return(NA_real_)
    hit <- which(as.character(tbl$Mediator) == med)
    if (!length(hit)) return(NA_real_)
    suppressWarnings(as.numeric(tbl$Prop_Med_num[hit[1L]]))
  }

  tbls <- list()
  for (db in db_seq) {
    tbls[[db]] <- dual_db_load_mediation_result_table(root, cfg, db)
  }
  if (any(vapply(tbls, is.null, logical(1)))) return(NULL)

  sets <- lapply(tbls, .clean_meds)
  if (any(!vapply(sets, length, integer(1)))) return(NULL)
  common <- Reduce(intersect, sets)
  if (!length(common)) {
    cli::cli_alert_warning("闸门 E：两库中介结果无交集，无法锁定统一路径图中介")
    return(NULL)
  }

  scores <- vapply(common, function(m) {
    vals <- vapply(db_seq, function(db) .prop(tbls[[db]], m), numeric(1))
    if (any(!is.finite(vals))) return(NA_real_)
    mean(vals)
  }, numeric(1))
  names(scores) <- common
  ok <- names(scores)[is.finite(scores)]
  if (!length(ok)) return(NULL)

  pos <- ok[scores[ok] > 0]
  pool <- if (length(pos)) pos else ok
  best <- pool[which.max(scores[pool])]
  # 展示顺序：按双库平均 Prop_Med 降序
  ord <- order(scores[common], decreasing = TRUE, na.last = TRUE)
  mediators_ord <- common[ord]

  dual_db_save_preferred_mediator(root, cfg, best)
  cli::cli_alert_success(
    "闸门 E：双库统一路径图中介 = {best}（交集 {length(common)} 个；双库均值 Prop_Med={round(scores[[best]], 2)}%）"
  )
  list(
    best_mediator = best,
    mediators = mediators_ord,
    score = unname(scores[[best]]),
    scores = scores,
    detail = lapply(db_seq, function(db) {
      list(db = db, prop_med = .prop(tbls[[db]], best))
    })
  )
}

dual_db_gate_a_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "gate_a_columns.rds")
}

dual_db_gate_b_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "gate_b_covariates.rds")
}

dual_db_gate_d_subgroup_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "gate_d_subgroup_vars.rds")
}

#' 从单库 checkpoint 探测「min_n 后仍可用」的亚组变量
dual_db_probe_subgroup_eligible <- function(root, cfg, db_name) {
  if (!exists("subgroup_probe_eligible_vars", mode = "function")) {
    root_sf <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = root)
    suppressWarnings(source(file.path(root_sf, "R", "subgroup_vars.R"), local = FALSE))
  }
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  if (!dir.exists(ck_dir)) return(character(0))
  candidates <- c(
    "imputation", "trim_index_extreme", "baseline_binary",
    "multicollinearity_final", "dual_db_covariate_harmonize",
    "cox_quartile", "cox_tertile", "cox_binary"
  )
  data <- NULL
  for (blk in candidates) {
    path <- file.path(ck_dir, paste0(blk, ".rds"))
    if (!file.exists(path)) next
    obj <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(obj) || is.null(obj$ctx)) next
    data <- obj$ctx$data$imputed %||% obj$ctx$data$cleaned
    if (is.data.frame(data) && nrow(data) > 0L) break
    data <- NULL
  }
  if (is.null(data)) {
    hits <- list.files(
      ck_dir,
      pattern = "(imputation|baseline_binary|cox_quartile).*\\.rds$",
      full.names = TRUE, ignore.case = TRUE
    )
    for (path in hits) {
      obj <- tryCatch(readRDS(path), error = function(e) NULL)
      if (is.null(obj) || is.null(obj$ctx)) next
      data <- obj$ctx$data$imputed %||% obj$ctx$data$cleaned
      if (is.data.frame(data) && nrow(data) > 0L) break
      data <- NULL
    }
  }
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) return(character(0))
  subgroup_probe_eligible_vars(as.data.frame(data), cfg)
}

#' 闸门 D：两库亚组变量取交集并锁定（保证 Figure 5 名单一致）
dual_db_lock_subgroup_vars <- function(root, cfg, eligible_by_db) {
  elig <- lapply(eligible_by_db, function(x) unique(as.character(x[nzchar(as.character(x))])))
  elig <- elig[vapply(elig, length, integer(1)) > 0L]
  if (!length(elig)) {
    cli::cli_alert_warning("闸门 D：两库均无可用亚组变量")
    return(character(0))
  }
  common <- Reduce(intersect, elig)
  if (exists("subgroup_order_vars_clinical", mode = "function")) {
    common <- subgroup_order_vars_clinical(common)
  } else {
    common <- unique(common)
  }
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  payload <- list(
    vars = common,
    eligible_by_db = elig,
    saved_at = Sys.time()
  )
  saveRDS(payload, dual_db_gate_d_subgroup_cache_path(root, cfg))
  dropped <- lapply(names(elig), function(nm) setdiff(elig[[nm]], common))
  names(dropped) <- names(elig)
  for (nm in names(dropped)) {
    if (length(dropped[[nm]])) {
      cli::cli_alert_info(
        "闸门 D：[{nm}] 为对齐剔除 {paste(dropped[[nm]], collapse=', ')}"
      )
    }
  }
  if (length(common)) {
    cli::cli_alert_success(
      "闸门 D：双库统一亚组变量 {length(common)} 个 — {paste(common, collapse=', ')}"
    )
  } else {
    cli::cli_alert_warning("闸门 D：交集为空，亚组将无法统一绘制")
  }
  invisible(common)
}

dual_db_load_subgroup_lock <- function(root, cfg) {
  path <- dual_db_gate_d_subgroup_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

dual_db_force_gate_d_subgroup_sync <- function(root, cfg) {
  dbs <- c("nhanes", "mimic")
  elig <- list()
  for (db in dbs) {
    elig[[db]] <- dual_db_probe_subgroup_eligible(root, cfg, db)
    cli::cli_alert_info(
      "闸门 D 探测 [{db}]: {length(elig[[db]])} 个 — {paste(elig[[db]], collapse=', ')}"
    )
  }
  dual_db_lock_subgroup_vars(root, cfg, elig)
}

dual_db_logistic_branch_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "logistic_branch.rds")
}

dual_db_save_logistic_branch <- function(root, cfg, branch, scheme = NA_character_, detail = NULL) {
  info <- dual_db_normalize_follower_logistic_branch(
    list(branch = branch, scheme = scheme, detail = detail)
  )
  if (is.null(info)) return(invisible(FALSE))
  branch <- as.character(info$branch %||% "")[1L]
  if (!nzchar(branch) || !grepl("^extend_", branch)) return(invisible(FALSE))
  scheme <- as.character(info$scheme %||% "")[1L]
  if (!nzchar(scheme) && exists("logistic_gate_scheme_from_branch", mode = "function")) {
    scheme <- logistic_gate_scheme_from_branch(branch)
  }
  detail <- info$detail
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  payload <- list(
    branch = branch,
    scheme = scheme,
    detail = detail,
    saved_at = Sys.time(),
    source_db = as.character((cfg$dual_db$primary %||% list())$db_type %||% "nhanes")[1L]
  )
  saveRDS(payload, dual_db_logistic_branch_cache_path(root, cfg))
  invisible(TRUE)
}

dual_db_load_logistic_branch <- function(root, cfg) {
  path <- dual_db_logistic_branch_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

# ── 双库槽位：内部角色 vs 目录名 ─────────────────────────────────────────────
#  内部槽位 slot 仍为 "nhanes"（primary）/ "mimic"（secondary），供逻辑与 current_db 使用。
#  产出/checkpoint 子目录名取自 dual_db$primary$name / secondary$name（如 eICU、MIMIC）。

dual_db_slot_primary <- function() "nhanes"

dual_db_slot_secondary <- function() "mimic"

dual_db_slot_is_primary <- function(slot) {
  identical(as.character(slot)[1L], dual_db_slot_primary())
}

dual_db_normalize_slot <- function(slot) {
  slot <- tolower(trimws(as.character(slot)[1L]))
  # 内部槽位 + 常用库展示名（eICU / MIMIC）→ primary/secondary
  if (slot %in% c("nhanes", "nhance", "primary", "eicu", "e_icu")) {
    return(dual_db_slot_primary())
  }
  if (slot %in% c("mimic", "secondary", "mimiciv", "mimic-iv", "mimic_iv")) {
    return(dual_db_slot_secondary())
  }
  as.character(slot)[1L]
}

dual_db_sanitize_path_name <- function(name) {
  name <- trimws(as.character(name %||% "")[1L])
  if (!nzchar(name)) return("unknown")
  gsub("[^A-Za-z0-9._-]+", "_", name)
}

#' 槽位 → by_index / checkpoint 子目录名（来自 config 库 display name）
dual_db_slot_path_name <- function(cfg, slot) {
  slot <- dual_db_normalize_slot(slot)
  dual <- cfg$dual_db %||% list()
  raw <- if (dual_db_slot_is_primary(slot)) {
    (dual$primary %||% list())$name %||% "NHANES"
  } else {
    (dual$secondary %||% list())$name %||% "MIMIC"
  }
  dual_db_sanitize_path_name(raw)
}

#' 目录名 → 内部槽位（兼容旧 nhanes/mimic 文件夹）
dual_db_path_name_to_slot <- function(cfg, path_name) {
  path_name <- as.character(path_name)[1L]
  if (identical(path_name, dual_db_slot_path_name(cfg, dual_db_slot_primary())) ||
      tolower(path_name) %in% c("nhanes", "nhance", "primary")) {
    return(dual_db_slot_primary())
  }
  if (identical(path_name, dual_db_slot_path_name(cfg, dual_db_slot_secondary())) ||
      tolower(path_name) %in% c("mimic", "secondary")) {
    return(dual_db_slot_secondary())
  }
  NA_character_
}

#' 解析已存在的目录：优先新名（eICU），回退 legacy（nhanes）
dual_db_resolve_slot_dir <- function(parent, cfg, slot) {
  parent <- as.character(parent)[1L]
  slot   <- dual_db_normalize_slot(slot)
  disp <- dual_db_slot_path_name(cfg, slot)
  candidates <- unique(c(
    file.path(parent, disp),
    file.path(parent, tolower(disp)),
    file.path(parent, toupper(disp)),
    file.path(parent, slot),
    # 轨迹预后等课题常用小写 eicu/mimic 子目录
    if (dual_db_slot_is_primary(slot)) {
      c(file.path(parent, "eicu"), file.path(parent, "EICU"))
    } else {
      c(file.path(parent, "mimic"), file.path(parent, "MIMIC"))
    }
  ))
  for (d in candidates) {
    if (dir.exists(d)) return(d)
  }
  candidates[[1L]]
}

# ── 双引擎库支持：角色 → db_type ────────────────────────────────────────────
#  db_name 为角色字符串（"nhanes"=primary 槽 / "mimic"=secondary 槽）。
#  返回该槽位的 db_type；"nhanes" 视为加权库，其余（regular/eICU/MIMIC…）为普通库。
#  这样引擎既能跑「NHANES 加权 + 普通库」，也能跑「双普通库」（eICU + MIMIC）。
dual_db_db_type <- function(cfg, db_name) {
  slot <- if (dual_db_slot_is_primary(db_name)) "primary" else "secondary"
  dt <- (cfg$dual_db %||% list())[[slot]]$db_type
  tolower(as.character(
    dt %||% if (dual_db_slot_is_primary(db_name)) "nhanes" else "regular"
  )[1L])
}

# 该角色是否走复杂抽样加权流水线（US NHANES 或 KNHANES）
dual_db_is_weighted <- function(cfg, db_name) {
  dual_db_db_type(cfg, db_name) %in% c("nhanes", "knhanes")
}

dual_db_resolve_col_alias <- function(wish, cols, aliases = list()) {
  wish <- as.character(wish)[1L]
  cols <- as.character(cols)
  if (wish %in% cols) return(wish)
  al <- aliases[[wish]]
  if (!is.null(al)) {
    hit <- intersect(as.character(al), cols)
    if (length(hit)) return(hit[1L])
  }
  for (nm in names(aliases)) {
    if (wish %in% aliases[[nm]]) {
      hit <- intersect(as.character(aliases[[nm]]), cols)
      if (length(hit)) return(hit[1L])
    }
  }
  NA_character_
}

dual_db_compute_subgroup_alignment <- function(cfg, cols_nhanes, cols_mimic,
                                               common_non_demo = character(0)) {
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  common_clinical <- unique(as.character(common_non_demo[nzchar(common_non_demo)]))
  demo_nhanes <- unique(cols_nhanes[dual_db_is_demo_col(cols_nhanes, demo_kw)])
  demo_mimic <- unique(cols_mimic[dual_db_is_demo_col(cols_mimic, demo_kw)])

  sub_cfg <- cfg$subgroup %||% list()
  wish <- as.character(sub_cfg$required_subgroup_vars %||% character(0))
  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "Hematocrit"
  )[1L]
  if (!index_var %in% wish) wish <- unique(c(wish, index_var))
  aliases <- harm$subgroup_var_aliases %||% list(
    Gender = c("Gender", "Sex"),
    Smoking = c("Smoking", "Smoke"),
    Smoke = c("Smoking", "Smoke")
  )
  common_canon <- character(0)
  nhanes_resolved <- character(0)
  mimic_resolved <- character(0)
  for (w in wish) {
    r1 <- dual_db_resolve_col_alias(w, cols_nhanes, aliases)
    r2 <- dual_db_resolve_col_alias(w, cols_mimic, aliases)
    if (nzchar(r1) && !is.na(r1) && nzchar(r2) && !is.na(r2)) {
      common_canon <- c(common_canon, w)
      nhanes_resolved <- c(nhanes_resolved, r1)
      mimic_resolved <- c(mimic_resolved, r2)
    }
  }
  list(
    common_clinical_subgroup_cols = common_clinical,
    demo_subgroup_cols_nhanes = demo_nhanes,
    demo_subgroup_cols_mimic = demo_mimic,
    common_subgroup_canonical = unique(common_canon),
    harmonized_subgroup_nhanes = unique(nhanes_resolved),
    harmonized_subgroup_mimic = unique(mimic_resolved)
  )
}

dual_db_logistic_covariates_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "logistic_covariates.rds")
}

dual_db_save_logistic_covariates <- function(
    root, cfg, m1, m2, scheme = NA_character_, branch = NA_character_,
    db_name = NULL) {
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  prev <- dual_db_load_logistic_covariates(root, cfg) %||% list()
  payload <- prev
  payload$scheme <- as.character(scheme)[1L]
  payload$branch <- as.character(branch)[1L]
  payload$saved_at <- Sys.time()
  m1 <- as.character(m1)
  m2 <- as.character(m2)
  slot <- as.character(db_name %||% "")[1L]
  if (nzchar(slot) && slot %in% c("nhanes", "mimic")) {
    payload[[paste0("model1_", slot)]] <- m1
    payload[[paste0("model2_", slot)]] <- m2
  } else {
    payload$model1_nhanes <- m1
    payload$model2_nhanes <- m2
    payload$model1_mimic <- m1
    payload$model2_mimic <- m2
  }
  saveRDS(payload, dual_db_logistic_covariates_cache_path(root, cfg))
  invisible(payload)
}

dual_db_load_logistic_covariates <- function(root, cfg) {
  path <- dual_db_logistic_covariates_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

dual_db_read_logistic_state_from_checkpoint <- function(root, cfg, db_name = "nhanes",
                                                         scheme_hint = NULL) {
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  if (!dir.exists(ck_dir)) return(NULL)
  blocks <- if (dual_db_is_weighted(cfg, db_name)) {
    c(
      "logistic_tertile_nhanes_weighted",
      "logistic_quartile_nhanes_weighted",
      "logistic_binary_nhanes_weighted"
    )
  } else {
    c("logistic_tertile_glm", "logistic_quartile_glm", "logistic_binary_glm")
  }
  candidates <- list()
  for (blk in blocks) {
    alias <- file.path(ck_dir, paste0(blk, ".rds"))
    if (!file.exists(alias)) next
    obj <- tryCatch(readRDS(alias), error = function(e) NULL)
    if (is.null(obj$ctx)) next
    r <- obj$ctx$results
    scheme <- as.character(
      r$nhanes_logistic_selected_scheme %||%
        r$nhanes_logistic_grouping_scheme %||%
        r$logistic_grouping_scheme %||% ""
    )[1L]
    branch <- as.character(r$logistic_branch %||% "")[1L]
    if (!nzchar(scheme) && nzchar(branch) &&
        exists("logistic_gate_scheme_from_branch", mode = "function")) {
      scheme <- logistic_gate_scheme_from_branch(branch)
    }
    is_main <- !is.null(r$nhanes_logistic_table2) ||
      (!is.null(r$logistic_table2) && grepl("^extend_", branch))
    candidates[[length(candidates) + 1L]] <- list(
      block = blk, scheme = scheme, branch = branch,
      m1 = as.character(
        r$logistic_model1_factors %||%
          r$nhanes_logistic_M1 %||%
          r$Model1Factors %||%
          character(0)
      ),
      m2 = as.character(
        r$logistic_model2_factors %||%
          r$nhanes_logistic_M2 %||%
          r$Model2Factors %||%
          character(0)
      ),
      is_main = is_main,
      detail = r$logistic_gate_detail %||% NULL
    )
  }
  if (!length(candidates)) return(NULL)
  scheme_hint <- as.character(scheme_hint %||% "")[1L]
  if (nzchar(scheme_hint)) {
    hit <- Filter(function(x) identical(x$scheme, scheme_hint), candidates)
    if (length(hit)) return(hit[[1L]])
  }
  main <- Filter(function(x) isTRUE(x$is_main) && nzchar(x$scheme), candidates)
  if (length(main)) {
    pref <- main[[which.max(vapply(main, function(x) {
      switch(x$scheme, tertile = 3L, quartile = 2L, binary = 1L, 0L)
    }, integer(1L)))]]
    return(pref)
  }
  candidates[[1L]]
}

dual_db_read_logistic_branch_from_checkpoint <- function(root, cfg, db_name = "nhanes") {
  st <- dual_db_read_logistic_state_from_checkpoint(root, cfg, db_name)
  if (is.null(st)) return(NULL)
  list(branch = st$branch, scheme = st$scheme, detail = st$detail)
}

#' 读取单库 logistic 初筛自然终态（extend_*，级联停止点）
dual_db_read_logistic_natural_branch <- function(root, cfg, db_name = "nhanes") {
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  if (!dir.exists(ck_dir)) return(NULL)
  blocks <- if (dual_db_is_weighted(cfg, db_name)) {
    c(
      "logistic_quartile_nhanes_weighted",
      "logistic_tertile_nhanes_weighted",
      "logistic_binary_nhanes_weighted",
      # ML 发病：logistic 常嵌在 ml_assoc_bundle，无独立 logistic_*.rds
      "ml_assoc_bundle"
    )
  } else {
    c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "ml_assoc_bundle"
    )
  }
  last <- NULL
  for (blk in blocks) {
    alias <- file.path(ck_dir, paste0(blk, ".rds"))
    if (!file.exists(alias)) next
    obj <- tryCatch(readRDS(alias), error = function(e) NULL)
    if (is.null(obj$ctx)) next
    r <- obj$ctx$results
    branch <- as.character(r$logistic_natural_branch %||% r$logistic_branch %||% "")[1L]
    # ML 末档失败时 branch 可能为 NA，但 grouping_scheme / Table2 仍落在 binary
    if (!grepl("^extend_", branch)) {
      scheme_fb <- as.character(
        r$logistic_natural_scheme %||%
          r$nhanes_logistic_selected_scheme %||%
          r$logistic_grouping_scheme %||% ""
      )[1L]
      if (nzchar(scheme_fb) && scheme_fb %in% c("quartile", "tertile", "binary", "quintile")) {
        branch <- paste0("extend_", scheme_fb)
      } else {
        next
      }
    }
    scheme <- as.character(r$logistic_natural_scheme %||% "")[1L]
    if (!nzchar(scheme) && exists("logistic_gate_scheme_from_branch", mode = "function")) {
      scheme <- logistic_gate_scheme_from_branch(branch)
    }
    if (!nzchar(scheme) || is.na(scheme)) {
      scheme <- sub("^extend_", "", branch)
    }
    last <- list(branch = branch, scheme = scheme, detail = r$logistic_gate_detail %||% NULL, block = blk)
  }
  last
}

#' 双库自然终态 → 统一分位（取更深级联层）
dual_db_harmonize_unified_logistic_branch <- function(root, cfg) {
  dual <- cfg$dual_db %||% list()
  # 角色字符串（槽位标识），不再用 db_type——checkpoint 目录与 current_db 一致按角色命名
  primary   <- "nhanes"
  secondary <- "mimic"
  nm1 <- as.character((dual$primary   %||% list())$name %||% "NHANES")[1L]
  nm2 <- as.character((dual$secondary %||% list())$name %||% "MIMIC")[1L]
  n1 <- dual_db_read_logistic_natural_branch(root, cfg, primary)
  n2 <- dual_db_read_logistic_natural_branch(root, cfg, secondary)
  if (is.null(n1) && is.null(n2)) return(invisible(NULL))
  if (is.null(n1)) {
    info <- dual_db_normalize_follower_logistic_branch(n2)
    dual_db_save_logistic_branch(root, cfg, info$branch, info$scheme, info$detail)
    return(invisible(info))
  }
  if (is.null(n2)) {
    info <- dual_db_normalize_follower_logistic_branch(n1)
    dual_db_save_logistic_branch(root, cfg, info$branch, info$scheme, info$detail)
    return(invisible(info))
  }
  unified_scheme <- if (exists("logistic_gate_unify_schemes", mode = "function")) {
    logistic_gate_unify_schemes(n1$scheme, n2$scheme)
  } else {
    NA_character_
  }
  if (is.na(unified_scheme) || !nzchar(unified_scheme)) return(invisible(NULL))
  unified_branch <- paste0("extend_", unified_scheme)
  detail <- list(
    primary_natural = n1,
    secondary_natural = n2,
    unified_scheme = unified_scheme
  )
  dual_db_save_logistic_branch(root, cfg, unified_branch, unified_scheme, detail)
  d1 <- if (exists("logistic_gate_scheme_depth", mode = "function")) {
    logistic_gate_scheme_depth(n1$scheme)
  } else 0L
  d2 <- if (exists("logistic_gate_scheme_depth", mode = "function")) {
    logistic_gate_scheme_depth(n2$scheme)
  } else 0L
  uni_d <- if (exists("logistic_gate_scheme_depth", mode = "function")) {
    logistic_gate_scheme_depth(unified_scheme)
  } else 0L
  if (d1 < uni_d || d2 < uni_d) {
    cli::cli_alert_info(
      "双库分位统一: {nm1}={n1$scheme}, {nm2}={n2$scheme} → 统一 {unified_scheme}"
    )
  } else {
    cli::cli_alert_success(
      "双库分位统一: 两库均为 {unified_scheme}（{nm1}={n1$scheme}, {nm2}={n2$scheme}）"
    )
  }
  invisible(list(branch = unified_branch, scheme = unified_scheme, detail = detail))
}

# ── 预后 Cox 闸门 C：双库四降三降二统一 ─────────────────────────────────────

dual_db_cox_branch_cache_path <- function(root, cfg) {
  file.path(dual_db_harmonization_dir(root, cfg), "cox_branch.rds")
}

dual_db_save_cox_unified_branch <- function(root, cfg, branch, scheme, detail = NULL) {
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  saveRDS(list(
    branch = branch, scheme = scheme, detail = detail,
    saved_at = Sys.time()
  ), dual_db_cox_branch_cache_path(root, cfg))
  invisible(TRUE)
}

dual_db_load_cox_unified_branch <- function(root, cfg) {
  path <- dual_db_cox_branch_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

#' 读取单库 Cox 初筛自然终态（最后完成的 cox_* 块）
dual_db_read_cox_natural_branch <- function(root, cfg, db_name = "nhanes") {
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  if (!dir.exists(ck_dir)) return(NULL)
  blocks <- c("cox_quartile", "cox_tertile", "cox_binary")
  last <- NULL
  for (blk in blocks) {
    alias <- file.path(ck_dir, paste0(blk, ".rds"))
    if (!file.exists(alias)) next
    obj <- tryCatch(readRDS(alias), error = function(e) NULL)
    if (is.null(obj$ctx)) next
    r <- obj$ctx$results
    branch <- as.character(r$cox_branch %||% "")[1L]
    scheme <- if (exists("cox_gate_scheme_from_branch", mode = "function")) {
      cox_gate_scheme_from_branch(branch)
    } else NA_character_
    if (!nzchar(scheme) || is.na(scheme)) {
      scheme <- switch(blk,
        cox_quartile = "quartile",
        cox_tertile  = "tertile",
        cox_binary   = "binary",
        NA_character_
      )
    }
    if (grepl("^extend_", branch)) {
      last <- list(branch = branch, scheme = scheme, detail = r$cox_gate_detail %||% NULL, block = blk)
    } else if (grepl("^degrade_", branch) && !is.null(r$cox_hr)) {
      last <- list(
        branch = paste0("extend_", scheme),
        scheme = scheme,
        detail = r$cox_gate_detail %||% NULL,
        block = blk
      )
    }
  }
  last
}

#' 双库 Cox 自然终态 → 统一分位（取更深级联层，与 logistic 闸门 C 一致）
dual_db_harmonize_unified_cox_branch <- function(root, cfg) {
  primary   <- dual_db_slot_primary()
  secondary <- dual_db_slot_secondary()
  nm1 <- as.character((cfg$dual_db$primary %||% list())$name %||% "eICU")[1L]
  nm2 <- as.character((cfg$dual_db$secondary %||% list())$name %||% "MIMIC")[1L]
  n1 <- dual_db_read_cox_natural_branch(root, cfg, primary)
  n2 <- dual_db_read_cox_natural_branch(root, cfg, secondary)
  if (is.null(n1) && is.null(n2)) return(invisible(NULL))
  if (is.null(n1)) {
    dual_db_save_cox_unified_branch(root, cfg, n2$branch, n2$scheme, list(secondary_natural = n2))
    return(invisible(n2))
  }
  if (is.null(n2)) {
    dual_db_save_cox_unified_branch(root, cfg, n1$branch, n1$scheme, list(primary_natural = n1))
    return(invisible(n1))
  }
  unified_scheme <- if (exists("logistic_gate_unify_schemes", mode = "function")) {
    logistic_gate_unify_schemes(n1$scheme, n2$scheme)
  } else NA_character_
  if (is.na(unified_scheme) || !nzchar(unified_scheme)) return(invisible(NULL))
  unified_branch <- paste0("extend_", unified_scheme)
  detail <- list(primary_natural = n1, secondary_natural = n2, unified_scheme = unified_scheme)
  dual_db_save_cox_unified_branch(root, cfg, unified_branch, unified_scheme, detail)
  d1 <- logistic_gate_scheme_depth(n1$scheme)
  d2 <- logistic_gate_scheme_depth(n2$scheme)
  uni_d <- logistic_gate_scheme_depth(unified_scheme)
  if (d1 < uni_d || d2 < uni_d) {
    cli::cli_alert_info(
      "双库 Cox 分位统一: {nm1}={n1$scheme}, {nm2}={n2$scheme} → 统一 {unified_scheme}"
    )
  } else {
    cli::cli_alert_success(
      "双库 Cox 分位统一: 两库均为 {unified_scheme}（{nm1}={n1$scheme}, {nm2}={n2$scheme}）"
    )
  }
  invisible(list(branch = unified_branch, scheme = unified_scheme, detail = detail))
}

dual_db_patch_ctx_cox_unified <- function(ctx, unified_info) {
  if (is.null(unified_info)) return(ctx)
  scheme <- as.character(unified_info$scheme %||% "")[1L]
  if (!nzchar(scheme)) return(ctx)
  ctx$results$dual_db_cox_unified_locked <- TRUE
  ctx$results$dual_db_cox_unified_scheme <- scheme
  ctx$results$dual_db_cox_unified_branch <- unified_info$branch %||% paste0("extend_", scheme)
  ctx
}

dual_db_apply_cox_unified_from_cache <- function(ctx) {
  cfg <- ctx$config %||% list()
  if (!isTRUE((cfg$dual_db %||% list())$enable %||% FALSE)) return(ctx)
  root <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
  info <- dual_db_load_cox_unified_branch(root, cfg)
  if (is.null(info)) return(ctx)
  dual_db_patch_ctx_cox_unified(ctx, info)
}

#' 将 primary 库闸门状态规范为 follower 可沿用的 extend_{scheme}（degrade_* 为初筛中间态）
dual_db_normalize_follower_logistic_branch <- function(branch_info) {
  if (is.null(branch_info)) return(NULL)
  branch <- as.character(branch_info$branch %||% "")[1L]
  scheme <- as.character(branch_info$scheme %||% "")[1L]
  if (grepl("^extend_", branch)) {
    if (!nzchar(scheme) && exists("logistic_gate_scheme_from_branch", mode = "function")) {
      scheme <- logistic_gate_scheme_from_branch(branch)
    }
    return(list(branch = branch, scheme = scheme, detail = branch_info$detail))
  }
  if (grepl("^degrade_", branch)) {
    target <- switch(branch,
      degrade_tertile = "tertile",
      degrade_binary  = "binary",
      NA_character_
    )
    if (!is.na(target)) {
      return(list(
        branch = paste0("extend_", target),
        scheme = target,
        detail = branch_info$detail
      ))
    }
  }
  if (nzchar(scheme) && scheme %in% c("quartile", "tertile", "binary")) {
    return(list(
      branch = paste0("extend_", scheme),
      scheme = scheme,
      detail = branch_info$detail
    ))
  }
  branch_info
}

#' follower 库闸门 C：优先读 primary checkpoint 终态，再回退 harmonization 缓存
dual_db_resolve_follower_logistic_branch <- function(root, cfg, primary = "nhanes") {
  ck <- dual_db_read_logistic_branch_from_checkpoint(root, cfg, primary)
  if (!is.null(ck)) {
    norm <- dual_db_normalize_follower_logistic_branch(ck)
    if (!is.null(norm) && grepl("^extend_", norm$branch)) return(norm)
  }
  cached <- dual_db_load_logistic_branch(root, cfg)
  if (!is.null(cached)) {
    norm <- dual_db_normalize_follower_logistic_branch(cached)
    if (!is.null(norm)) return(norm)
  }
  dual_db_normalize_follower_logistic_branch(ck)
}

dual_db_persist_logistic_covariates_from_db <- function(root, cfg, db_name = "nhanes") {
  st <- dual_db_read_logistic_state_from_checkpoint(root, cfg, db_name)
  if (is.null(st) || !length(st$m1) || !length(st$m2)) return(invisible(NULL))
  dual_db_save_logistic_covariates(root, cfg, st$m1, st$m2, st$scheme, st$branch)
  cli::cli_alert_info(
    "闸门 D：已缓存 {toupper(db_name)} 调协变量 Model1={paste(st$m1, collapse = ', ')} | Model2={paste(st$m2, collapse = ', ')}"
  )
  invisible(st)
}

dual_db_apply_logistic_covariates_to_cfg <- function(cfg, lc, db_name) {
  if (is.null(lc)) return(cfg)
  m1 <- as.character(lc[[paste0("model1_", db_name)]] %||% lc$model1_nhanes %||% character(0))
  m2 <- as.character(lc[[paste0("model2_", db_name)]] %||% lc$model2_nhanes %||% character(0))
  if (!length(m1) || !length(m2)) return(cfg)
  if (dual_db_is_weighted(cfg, db_name)) {
    cfg$logistic_nhanes_weighted$model1_factors <- m1
    cfg$logistic_nhanes_weighted$model2_factors <- m2
    for (blk in c(
      "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
      "logistic_binary_nhanes_weighted", "rcs_nhanes",
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm"
    )) {
      if (!is.null(cfg[[blk]])) {
        cfg[[blk]]$model1_factors <- m1
        cfg[[blk]]$model2_factors <- m2
      }
    }
  } else {
    for (blk in c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm", "rcs_incidence"
    )) {
      if (!is.null(cfg[[blk]])) {
        cfg[[blk]]$model1_factors <- m1
        cfg[[blk]]$model2_factors <- m2
      }
    }
  }
  cfg
}

dual_db_persist_logistic_branch_from_db <- function(root, cfg, db_name = "nhanes") {
  info <- dual_db_read_logistic_branch_from_checkpoint(root, cfg, db_name)
  if (is.null(info)) return(invisible(NULL))
  info <- dual_db_normalize_follower_logistic_branch(info)
  dual_db_save_logistic_branch(root, cfg, info$branch, info$scheme, info$detail)
  cli::cli_alert_info(
    "闸门 C：已缓存 {toupper(db_name)} logistic_branch={info$branch}（scheme={info$scheme}）"
  )
  invisible(info)
}

dual_db_seed_logistic_branch_to_ctx <- function(ctx, branch_info) {
  if (is.null(branch_info)) return(ctx)
  branch_info <- dual_db_normalize_follower_logistic_branch(branch_info)
  branch <- as.character(branch_info$branch %||% "")[1L]
  if (!nzchar(branch)) return(ctx)
  ctx$results$logistic_branch <- branch
  scheme <- as.character(branch_info$scheme %||% "")[1L]
  if (!nzchar(scheme) && exists("logistic_gate_scheme_from_branch", mode = "function")) {
    scheme <- logistic_gate_scheme_from_branch(branch)
  }
  if (nzchar(scheme) && !is.na(scheme)) {
    ctx$results$nhanes_logistic_selected_scheme <- scheme
    ctx$results$nhanes_logistic_grouping_scheme <- scheme
    ctx$results$logistic_grouping_scheme <- scheme
  }
  if (!is.null(branch_info$detail)) {
    ctx$results$logistic_gate_detail <- branch_info$detail
  }
  ctx$results$dual_db_logistic_branch_seeded <- TRUE
  ctx$results$dual_db_logistic_unified_scheme <- scheme
  ctx
}

dual_db_pending_factors_path <- function(root, cfg, db_name) {
  file.path(dual_db_harmonization_dir(root, cfg), paste0("pending_factors_", db_name, ".rds"))
}

dual_db_is_demo_col <- function(col_names, demo_keywords) {
  col_names <- as.character(col_names)
  demo_keywords <- as.character(demo_keywords)
  vapply(col_names, function(nm) {
    any(vapply(demo_keywords, function(kw) {
      nzchar(kw) && grepl(tolower(kw), tolower(nm), fixed = TRUE)
    }, logical(1L)))
  }, logical(1L))
}

dual_db_reserved_cols <- function(cfg, db_cfg) {
  id_col <- as.character(db_cfg$id_column %||% (cfg$data %||% list())$id_column %||% character(0))
  outcome <- as.character(
    (cfg$data %||% list())$outcome_column %||%
      (cfg$incidence %||% list())$outcome_var %||% "Disease_Group"
  )
  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "Hematocrit"
  )[1L]
  extra <- c("ID", "Group", "Disease", "Disease_Group", "Source_File")
  wt <- character(0)
  db_type <- tolower(as.character(db_cfg$db_type %||% ""))
  if (db_type %in% c("nhanes", "knhanes")) {
    if (identical(db_type, "knhanes")) {
      if (!exists("knhanes_survey_weight_source_cols", mode = "function")) {
        wt_path <- file.path(
          (cfg$project$root %||% getwd()), "R", "knhanes_survey_weight.R"
        )
        if (!file.exists(wt_path)) {
          eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
          if (nzchar(eng)) wt_path <- file.path(eng, "R", "knhanes_survey_weight.R")
        }
        if (file.exists(wt_path)) source(wt_path, local = FALSE)
      }
      wt <- if (exists("knhanes_survey_weight_source_cols", mode = "function")) {
        knhanes_survey_weight_source_cols(cfg)
      } else {
        c("W_pooled", "PSU", "STRATA", "wt_itvex", "wt_tot", "psu", "kstrata", "cycle")
      }
    } else {
      if (!exists("nhanes_survey_weight_source_cols", mode = "function")) {
        wt_path <- file.path(
          (cfg$project$root %||% getwd()), "R", "nhanes_survey_weight.R"
        )
        if (file.exists(wt_path)) source(wt_path, local = FALSE)
      }
      wt <- if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
        nhanes_survey_weight_source_cols(cfg)
      } else {
        c(
          (cfg$nhanes %||% list())$survey_weight %||% "new_Weight",
          (cfg$nhanes %||% list())$survey_cluster %||% "SDMVPSU",
          (cfg$nhanes %||% list())$survey_strata %||% "SDMVSTRA",
          "Source_File", "WTINT2YR", "WTMEC2YR", "WTMEC4YR", "WTSAF2YR", "WTSAF4YR"
        )
      }
    }
  }
  unique(c(id_col, outcome, index_var, extra, wt))
}

dual_db_derive_bmi <- function(data, derive_cfg = list(enable = TRUE)) {
  derive_cfg <- derive_cfg %||% list()
  if (!isTRUE(derive_cfg$enable %||% TRUE)) return(data)
  h <- as.character(derive_cfg$height_var %||% "Height")[1L]
  w <- as.character(derive_cfg$weight_var %||% "Weight")[1L]
  bmi_col <- as.character(derive_cfg$bmi_col %||% "BMI")[1L]
  if (!nzchar(bmi_col)) bmi_col <- "BMI"
  if (bmi_col %in% names(data)) {
    # 已有 BMI：若几乎全缺失且有身高体重，则重算覆盖缺失
    b0 <- suppressWarnings(as.numeric(as.character(data[[bmi_col]])))
    if (mean(is.finite(b0), na.rm = TRUE) >= 0.5 || !h %in% names(data) || !w %in% names(data)) {
      return(data)
    }
  }
  if (!h %in% names(data) || !w %in% names(data)) {
    cli::cli_alert_warning(
      "BMI 衍生跳过：缺少 {h} 或 {w}（当前列数 {ncol(data)}）"
    )
    return(data)
  }
  hx <- suppressWarnings(as.numeric(as.character(data[[h]])))
  wx <- suppressWarnings(as.numeric(as.character(data[[w]])))
  bmi <- wx / (hx / 100)^2
  bmi[!is.finite(bmi) | bmi <= 0 | bmi > 100] <- NA_real_
  data[[bmi_col]] <- round(bmi, 2)
  n_ok <- sum(is.finite(data[[bmi_col]]))
  cli::cli_alert_success(
    "已衍生 {bmi_col} = {w}/({h}/100)^2（有效 {n_ok}/{nrow(data)}）"
  )
  data
}

#' BMI 三分组：<25 / 25–30 / ≥30（WHO：肥胖 BMI≥30；与发病双库亚组一致）
dual_db_make_bmi_group <- function(bmi, levels = c("< 25", "25-30", "\u2265 30")) {
  bmi <- suppressWarnings(as.numeric(as.character(bmi)))
  bg <- ifelse(
    !is.finite(bmi), NA_character_,
    ifelse(bmi < 25, levels[[1L]],
           ifelse(bmi < 30, levels[[2L]], levels[[3L]]))
  )
  factor(bg, levels = levels)
}

dual_db_load_mapped_frame <- function(root, db_cfg, cfg) {
  map_src <- file.path(root, "Blocks/01_column_mappings/01block_column_mapping.R")
  if (!file.exists(map_src)) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (nzchar(eng)) {
      map_src <- file.path(eng, "Blocks/01_column_mappings/01block_column_mapping.R")
    }
  }
  if (file.exists(map_src)) source(map_src, local = FALSE)
  env <- new.env()
  rpath <- as.character(db_cfg$rawdata_path)[1L]
  if (!is_absolute_path(rpath)) rpath <- file.path(root, rpath)
  if (!file.exists(rpath)) {
    stop("双库对齐：数据文件不存在: ", rpath, call. = FALSE)
  }
  load(rpath, envir = env)
  obj <- db_cfg$rawdata_obj
  if (!exists(obj, envir = env)) {
    stop("双库对齐：RData 中无对象 ", obj, " (", rpath, ")", call. = FALSE)
  }
  d <- get(obj, envir = env)
  if (!is.data.frame(d)) stop("双库对齐：", obj, " 不是 data.frame", call. = FALSE)
  if (exists("auto_map_column_names", mode = "function")) {
    skip_rn <- as.character((cfg$column_mapping %||% list())$skip_rename %||% character(0))
    d <- auto_map_column_names(
      d, db_cfg$column_mapping_type %||% "Unknown",
      skip_rename = skip_rn
    )
  }
  if (exists("pipeline_apply_ventilation_after_map", mode = "function")) {
    d <- pipeline_apply_ventilation_after_map(d)
  } else if (exists("pipeline_split_ventilation_mapping", mode = "function")) {
    d <- pipeline_split_ventilation_mapping(d)
  }
  d
}

dual_db_compute_gate_a <- function(root, cfg) {
  p <- cfg$dual_db$primary
  s <- cfg$dual_db$secondary
  harm <- cfg$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% c(
    "Age", "Gender", "Sex", "Race", "Education", "PIR",
    "Smoke", "Marital", "Insurance", "Language", "Income",
    "Residence", "Hukou", "Familysize", "Family"
  ))

  d1 <- dual_db_load_mapped_frame(root, p, cfg)
  d2 <- dual_db_load_mapped_frame(root, s, cfg)

  cols1 <- names(d1)
  cols2 <- names(d2)
  demo1 <- cols1[dual_db_is_demo_col(cols1, demo_kw)]
  demo2 <- cols2[dual_db_is_demo_col(cols2, demo_kw)]
  res1 <- dual_db_reserved_cols(cfg, p)
  res2 <- dual_db_reserved_cols(cfg, s)

  non_demo1 <- setdiff(cols1, unique(c(demo1, res1)))
  non_demo2 <- setdiff(cols2, unique(c(demo2, res2)))
  common <- intersect(non_demo1, non_demo2)
  common <- common[nzchar(common)]
  if (exists("pipeline_gate_a_align_ventilation_cols", mode = "function")) {
    common <- pipeline_gate_a_align_ventilation_cols(cols1, cols2, common)
  }

  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "Hematocrit"
  )[1L]
  index_components <- as.character(
    harm$index_component_vars %||%
      (cfg$incidence %||% list())$index_component_vars %||%
      character(0)
  )
  both_have <- intersect(cols1, cols2)
  if (!length(index_components)) {
    index_components <- as.character(index_var)
  }
  index_components <- unique(index_components[nzchar(index_components)])
  miss_comp <- setdiff(index_components, both_have)
  if (length(miss_comp)) {
    stop(
      "闸门 A：暴露列不在两库映射后数据中: ",
      paste(miss_comp, collapse = ", "),
      "。请检查 column_mapping。",
      call. = FALSE
    )
  }
  cli::cli_alert_info(
    "闸门 A：暴露 {index_var} 两库均已对齐: {paste(index_components, collapse = ', ')}"
  )
  if (!length(common)) {
    stop("闸门 A：两库非人口学列交集为空。", call. = FALSE)
  }

  only_nhanes <- setdiff(non_demo1, common)
  only_mimic <- setdiff(non_demo2, common)
  if (length(only_nhanes)) {
    cli::cli_alert_warning(
      "闸门 A：仅 NHANES 有的非人口学列已丢弃 ({length(only_nhanes)}): ",
      paste(head(only_nhanes, 12), collapse = ", "),
      if (length(only_nhanes) > 12) " ..." else ""
    )
  }
  if (length(only_mimic)) {
    cli::cli_alert_warning(
      "闸门 A：仅 MIMIC 有的非人口学列已丢弃 ({length(only_mimic)}): ",
      paste(head(only_mimic, 12), collapse = ", "),
      if (length(only_mimic) > 12) " ..." else ""
    )
  }

  col_order <- as.character(harm$common_non_demo_cols %||% common)
  col_order <- col_order[col_order %in% common]
  if (!length(col_order)) col_order <- sort(common)

  keep_nhanes <- unique(c(res1, demo1, col_order))
  keep_mimic <- unique(c(res2, demo2, col_order))
  # 默认不对齐次库独有列进 Table 1（双库发病 Table1 须同变量池）。
  # 仅当 keep_secondary_only_table1_cols=TRUE 时才保留 Hukou/Residence/HR/CRP 等。
  if (isTRUE(harm$keep_secondary_only_table1_cols %||% FALSE) &&
      exists(".default_table1_sections", mode = "function")) {
    secs <- .default_table1_sections()
    t1_display <- unique(c(
      as.character(secs[["Demographics"]] %||% character(0)),
      as.character(secs[["Vital Signs"]] %||% character(0)),
      "CRP", "HSCRP", "HR", "Pulse", "Residence", "Hukou", "Familysize"
    ))
    extra_mimic <- intersect(only_mimic, t1_display)
    if (length(extra_mimic)) {
      keep_mimic <- unique(c(keep_mimic, extra_mimic))
      cli::cli_alert_info(
        "闸门 A：次库 Table 1 独有列保留 {length(extra_mimic)} 个 — {paste(extra_mimic, collapse = ', ')}"
      )
    }
  } else {
    # 硬删：NHANES 主库时次库独有展示列（Residence/HR/CRP/认知等）勿进次库 Table1。
    # 若该列已在双库 common（col_order）中——例如 CHARLS×ELSA 共有 Memeory——不得剔除，
    # 否则主库 ML 可用、次库被掏空 → dev_internal_ext 冻结外验缺列失败。
    secondary_only_t1 <- c(
      "Residence", "Hukou", "Familysize", "HR", "Pulse", "CRP", "HSCRP",
      "Family_per_capita_consumption", "Memeory", "Totalcognition",
      "Executive", "Incometotal"
    )
    dropped_t1 <- setdiff(intersect(keep_mimic, secondary_only_t1), col_order)
    if (length(dropped_t1)) {
      keep_mimic <- setdiff(keep_mimic, dropped_t1)
      cli::cli_alert_info(
        "闸门 A：次库 Table 1 独有列已丢弃（对齐双库）— {paste(dropped_t1, collapse = ', ')}"
      )
    }
  }
  if (exists("pipeline_ventilation_keep_alias", mode = "function")) {
    keep_nhanes <- pipeline_ventilation_keep_alias(keep_nhanes, cols1)
    keep_mimic <- pipeline_ventilation_keep_alias(keep_mimic, cols2)
  }

  sub_align <- dual_db_compute_subgroup_alignment(cfg, cols1, cols2, common_non_demo = col_order)
  if (length(sub_align$common_clinical_subgroup_cols)) {
    cli::cli_alert_info(
      "闸门 A：亚组共有临床列 {length(sub_align$common_clinical_subgroup_cols)} 个 — ",
      paste(sub_align$common_clinical_subgroup_cols, collapse = ", ")
    )
  }
  if (length(sub_align$demo_subgroup_cols_nhanes) || length(sub_align$demo_subgroup_cols_mimic)) {
    cli::cli_alert_info(
      "闸门 A：亚组人口学 NHANES {length(sub_align$demo_subgroup_cols_nhanes)} / MIMIC {length(sub_align$demo_subgroup_cols_mimic)}（各库独立）"
    )
  }
  if (length(sub_align$common_subgroup_canonical)) {
    cli::cli_alert_info(
      "闸门 A：亚组两库共有 {length(sub_align$common_subgroup_canonical)} 个 — {paste(sub_align$common_subgroup_canonical, collapse = ', ')}"
    )
  } else if (!length(sub_align$common_clinical_subgroup_cols)) {
    cli::cli_alert_warning("闸门 A：亚组变量两库无交集，下游将使用各库可用列。")
  }

  list(
    common_non_demo_cols = col_order,
    demo_cols_nhanes = demo1,
    demo_cols_mimic = demo2,
    column_keep_nhanes = keep_nhanes,
    column_keep_mimic = keep_mimic,
    dropped_nhanes_only = only_nhanes,
    dropped_mimic_only = only_mimic,
    common_clinical_subgroup_cols = sub_align$common_clinical_subgroup_cols,
    demo_subgroup_cols_nhanes = sub_align$demo_subgroup_cols_nhanes,
    demo_subgroup_cols_mimic = sub_align$demo_subgroup_cols_mimic,
    common_subgroup_canonical = sub_align$common_subgroup_canonical,
    harmonized_subgroup_nhanes = sub_align$harmonized_subgroup_nhanes,
    harmonized_subgroup_mimic = sub_align$harmonized_subgroup_mimic
  )
}

dual_db_save_gate_a <- function(root, cfg, gate_a) {
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  saveRDS(gate_a, dual_db_gate_a_cache_path(root, cfg))
  invisible(gate_a)
}

dual_db_load_gate_a <- function(root, cfg) {
  path <- dual_db_gate_a_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

dual_db_filter_data_columns <- function(data, keep_cols, label = "dual_db") {
  keep_cols <- unique(as.character(keep_cols[nzchar(keep_cols)]))
  keep <- intersect(keep_cols, names(data))
  miss_required <- setdiff(keep_cols, keep)
  if (length(miss_required)) {
    cli::cli_alert_warning(
      "{label}: {length(miss_required)} 个保留列在数据中不存在（已忽略）"
    )
  }
  if (!length(keep)) {
    stop(label, ": 列过滤后无可用列。", call. = FALSE)
  }
  data[, keep, drop = FALSE]
}

dual_db_column_keep_for_db <- function(cfg, db_name, gate_a = NULL) {
  gate_a <- gate_a %||% (cfg$dual_db$harmonization %||% list())
  db_name <- as.character(db_name %||% "")[1L]
  keys <- unique(c(
    paste0("column_keep_", db_name),
    paste0("column_keep_", tolower(db_name)),
    if (tolower(db_name) %in% c("mimic", "eicu", "icu")) "column_keep_mimic",
    if (identical(tolower(db_name), "nhanes")) "column_keep_nhanes"
  ))
  for (key in keys) {
    keep <- as.character(gate_a[[key]] %||% character(0))
    keep <- keep[nzchar(keep)]
    if (length(keep)) return(keep)
  }
  character(0)
}

dual_db_split_demo_clinical <- function(factors, demo_keywords) {
  factors <- unique(as.character(factors[nzchar(factors)]))
  if (!length(factors)) return(list(demo = character(0), clinical = character(0)))
  is_demo <- dual_db_is_demo_col(factors, demo_keywords)
  list(demo = factors[is_demo], clinical = factors[!is_demo])
}

#' 保证 Model2 严格包含 Model1；若 M2 无增量则尝试 clinical_fallback
dual_db_ensure_m2_gt_m1 <- function(m1, m2, clinical_fallback = character(0)) {
  m1 <- unique(as.character(m1[nzchar(as.character(m1))]))
  m2 <- unique(as.character(m2[nzchar(as.character(m2))]))
  extra <- setdiff(m2, m1)
  if (!length(extra)) {
    extra <- setdiff(as.character(clinical_fallback[nzchar(as.character(clinical_fallback))]), m1)
  }
  list(m1 = m1, m2 = unique(c(m1, extra)))
}

dual_db_compute_gate_b <- function(m1_nhanes, m2_nhanes, m1_mimic, m2_mimic,
                                   demo_keywords, common_col_order = NULL,
                                   require_same = TRUE,
                                   require_same_demo = TRUE,
                                   index_exclude = character(0)) {
  strip_index <- function(x) setdiff(as.character(x), index_exclude)
  s1 <- dual_db_split_demo_clinical(m1_nhanes, demo_keywords)
  s2 <- dual_db_split_demo_clinical(m2_nhanes, demo_keywords)
  s3 <- dual_db_split_demo_clinical(m1_mimic, demo_keywords)
  s4 <- dual_db_split_demo_clinical(m2_mimic, demo_keywords)
  # 每库临床池取 Model1∪Model2 的非人口学变量（Model1 通常仅人口学，不能与 M2 做四路交集）
  clinical_nhanes <- strip_index(unique(c(s1$clinical, s2$clinical)))
  clinical_mimic <- strip_index(unique(c(s3$clinical, s4$clinical)))
  common_clinical <- intersect(clinical_nhanes, clinical_mimic)
  common_col_order <- setdiff(as.character(common_col_order %||% character(0)), index_exclude)
  if (length(common_col_order)) {
    common_clinical <- common_col_order[common_col_order %in% common_clinical]
  } else {
    common_clinical <- sort(common_clinical)
  }

  demo_nhanes <- unique(c(s1$demo, s2$demo))
  demo_mimic <- unique(c(s3$demo, s4$demo))
  # 双库发表表 Model1/Model2 须一致：人口学也取交集（默认开启）
  if (isTRUE(require_same_demo)) {
    common_demo <- intersect(demo_nhanes, demo_mimic)
    drop_n <- setdiff(demo_nhanes, common_demo)
    drop_m <- setdiff(demo_mimic, common_demo)
    if (length(common_demo)) {
      if (length(drop_n) || length(drop_m)) {
        cli::cli_alert_info(
          paste0(
            "闸门 B：人口学已对齐为两库交集: ", paste(common_demo, collapse = ", "),
            if (length(drop_n)) paste0("；eICU 剔除 ", paste(drop_n, collapse = ", ")) else "",
            if (length(drop_m)) paste0("；MIMIC 剔除 ", paste(drop_m, collapse = ", ")) else ""
          )
        )
      }
      demo_nhanes <- common_demo
      demo_mimic <- common_demo
    } else if (length(demo_nhanes) || length(demo_mimic)) {
      cli::cli_alert_warning(
        "闸门 B：人口学交集为空，各库保留原人口学（eICU: {paste(demo_nhanes, collapse = ', ')}; MIMIC: {paste(demo_mimic, collapse = ', ')}）"
      )
    }
  }

  if (!length(common_clinical)) {
    if (isTRUE(require_same)) {
      stop(
        paste0(
          "GATE_B_EMPTY_COMMON: 两库临床协变量交集为空，无法对齐 Model2，已停止。",
          " eICU(", length(clinical_nhanes), "): ",
          if (length(clinical_nhanes)) paste(clinical_nhanes, collapse = ", ") else "(无)",
          "; MIMIC(", length(clinical_mimic), "): ",
          if (length(clinical_mimic)) paste(clinical_mimic, collapse = ", ") else "(无)"
        ),
        call. = FALSE
      )
    }
    cli::cli_alert_warning(
      "闸门 B：两库临床协变量交集为空，各库保留 VIF 拆分后的 Model1/Model2（require_same_clinical_cols=FALSE）。"
    )
    # 临床无法对齐时，人口学若已取交集仍写入两侧 Model1，保证脚注尽量一致
    m1_n <- if (length(demo_nhanes)) demo_nhanes else unique(as.character(m1_nhanes))
    m1_m <- if (length(demo_mimic)) demo_mimic else unique(as.character(m1_mimic))
    extra_n <- strip_index(setdiff(m2_nhanes, m1_n))
    extra_m <- strip_index(setdiff(m2_mimic, m1_m))
    fb_n <- dual_db_ensure_m2_gt_m1(unique(m1_n), unique(c(m1_n, m2_nhanes)), extra_n)
    fb_m <- dual_db_ensure_m2_gt_m1(unique(m1_m), unique(c(m1_m, m2_mimic)), extra_m)

    return(list(
      common_model_factors = character(0),
      harmonized_model1_nhanes = fb_n$m1,
      harmonized_model2_nhanes = fb_n$m2,
      harmonized_model1_mimic = fb_m$m1,
      harmonized_model2_mimic = fb_m$m2,
      gate_b_per_db_fallback = TRUE
    ))
  }

  # Model 1 = 人口学；Model 2 = 人口学 + 两库共有临床协变量
  # 若某库 VIF 三级回退导致 Model1 全是非人口学（如 SBP/DBP），demo_* 会为空；
  # 此时保留原 Model1，避免 Cox 因 Model1Factors 为空而 pause。
  hm1_n <- demo_nhanes
  if (!length(hm1_n)) {
    hm1_n <- unique(as.character(m1_nhanes[nzchar(as.character(m1_nhanes))]))
    cli::cli_alert_warning(
      "闸门 B [NHANES/eICU]: 无人口学变量，Model1 回退为原 VIF Model1: {paste(hm1_n, collapse = ', ')}"
    )
  }
  hm2_n <- unique(c(hm1_n, common_clinical))
  hm1_m <- demo_mimic
  if (!length(hm1_m)) {
    hm1_m <- unique(as.character(m1_mimic[nzchar(as.character(m1_mimic))]))
    cli::cli_alert_warning(
      "闸门 B [MIMIC]: 无人口学变量，Model1 回退为原 VIF Model1: {paste(hm1_m, collapse = ', ')}"
    )
  }
  hm2_m <- unique(c(hm1_m, common_clinical))

  list(
    common_model_factors = common_clinical,
    harmonized_model1_nhanes = hm1_n,
    harmonized_model2_nhanes = hm2_n,
    harmonized_model1_mimic = hm1_m,
    harmonized_model2_mimic = hm2_m
  )
}

dual_db_constrain_gate_b_models <- function(gate_b, cfg) {
  if (!exists("logistic_constrain_model_factors", mode = "function")) return(gate_b)
  # 两库先并成同一套 Model1 / 临床池，再统一截断，避免分库 head() 截出不同子集
  m1 <- unique(c(
    as.character(gate_b$harmonized_model1_nhanes %||% character(0)),
    as.character(gate_b$harmonized_model1_mimic %||% character(0))
  ))
  clinical <- unique(c(
    as.character(gate_b$common_model_factors %||% character(0)),
    setdiff(as.character(gate_b$harmonized_model2_nhanes %||% character(0)), m1),
    setdiff(as.character(gate_b$harmonized_model2_mimic %||% character(0)), m1)
  ))
  # 若人口学已对齐，优先用交集人口学（与 compute 一致）
  m1_n <- as.character(gate_b$harmonized_model1_nhanes %||% character(0))
  m1_m <- as.character(gate_b$harmonized_model1_mimic %||% character(0))
  if (length(m1_n) && length(m1_m)) {
    m1_common <- intersect(m1_n, m1_m)
    if (length(m1_common)) m1 <- m1_common
  }
  clinical <- as.character(gate_b$common_model_factors %||% clinical)
  out <- logistic_constrain_model_factors(m1, unique(c(m1, clinical)), cfg)
  gate_b$harmonized_model1_nhanes <- out$M1
  gate_b$harmonized_model1_mimic <- out$M1
  gate_b$harmonized_model2_nhanes <- out$M2
  gate_b$harmonized_model2_mimic <- out$M2
  gate_b$common_model_factors <- setdiff(out$M2, out$M1)
  gate_b
}

dual_db_write_pending_factors <- function(root, cfg, db_name, m1, m2) {
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  saveRDS(
    list(Model1Factors = m1, Model2Factors = m2, saved_at = Sys.time()),
    dual_db_pending_factors_path(root, cfg, db_name)
  )
  invisible(TRUE)
}

dual_db_read_pending_factors <- function(root, cfg, db_name) {
  path <- dual_db_pending_factors_path(root, cfg, db_name)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

dual_db_vif_final_block <- function(cfg, db_name) {
  if (dual_db_is_weighted(cfg, db_name)) "multicollinearity_nhanes_final" else "multicollinearity_final"
}

dual_db_vif_screen_block <- function(cfg, db_name) {
  if (dual_db_is_weighted(cfg, db_name)) "multicollinearity_nhanes_screen" else "multicollinearity_screen"
}

dual_db_harmonization_covariate_source <- function(cfg) {
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  src <- as.character(harm$covariate_source %||% "auto")[1L]
  src <- tolower(trimws(src))
  if (src %in% c("vif_screen", "screen", "vif_screen_pass")) return("vif_screen")
  if (src %in% c("vif_final", "final", "vif_final_pass", "multivar", "multivariate"))
    return("vif_final")
  if (src %in% c(
    "auto", "vif_final_then_screen", "final_then_screen",
    "vif_screen_if_both_multivar_sig", "both_multivar_screen"
  )) {
    return("auto")
  }
  "auto"
}

#' 闸门 B 协变量来源（硬约束：两库必须同一来源）
#'
#' 规则：
#' - `vif_final`：仅用两库多因素 VIF final 的交集
#' - `vif_screen`：仅用两库单因素 VIF screen 的交集
#' - `auto`（默认）：先试两库多因素-VIF 交集；临床交集为空则**两边一起**退回单因素-VIF
#'   （禁止一库单因素、一库多因素）
dual_db_resolve_gate_b_covariate_source <- function(root, cfg) {
  src <- dual_db_harmonization_covariate_source(cfg)
  if (!identical(src, "auto")) return(src)

  # auto：探测 final 临床交集是否可用；不可用则统一退 screen
  probe <- dual_db_probe_gate_b_clinical_intersection(root, cfg, source = "vif_final")
  if (isTRUE(probe$ok)) {
    cli::cli_alert_success(
      "闸门 B(auto)：两库多因素 VIF final 临床交集可用（n={probe$n_clinical}）→ 统一用 vif_final"
    )
    return("vif_final")
  }
  cli::cli_alert_info(
    "闸门 B(auto)：两库多因素 VIF final 临床交集为空/不可用 → 两边一起退回单因素 VIF screen（禁止混用）"
  )
  # 属性：发表表对齐时省略 S5（多因素全池）与 S6（VIF final），后续附表顺延
  out <- "vif_screen"
  attr(out, "omit_multivariate_and_vif_final_tables") <- TRUE
  out
}

#' 探测指定来源下两库临床协变量交集是否非空（不写盘）
dual_db_probe_gate_b_clinical_intersection <- function(root, cfg, source = "vif_final") {
  cfg_read <- cfg
  cfg_read$dual_db <- cfg_read$dual_db %||% list()
  cfg_read$dual_db$harmonization <- cfg_read$dual_db$harmonization %||% list()
  cfg_read$dual_db$harmonization$covariate_source <- source
  fn <- tryCatch(
    dual_db_read_factors_for_gate_b(root, cfg_read, "nhanes", apply_max = FALSE),
    error = function(e) NULL
  )
  fm <- tryCatch(
    dual_db_read_factors_for_gate_b(root, cfg_read, "mimic", apply_max = FALSE),
    error = function(e) NULL
  )
  if (is.null(fn) || is.null(fm)) {
    return(list(ok = FALSE, n_clinical = 0L, reason = "checkpoint_missing", fn = fn, fm = fm))
  }
  harm <- cfg$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    character(0)
  }
  gb <- tryCatch(
    dual_db_compute_gate_b(
      m1_nhanes = fn$Model1Factors, m2_nhanes = fn$Model2Factors,
      m1_mimic = fm$Model1Factors, m2_mimic = fm$Model2Factors,
      demo_keywords = demo_kw,
      common_col_order = harm$common_non_demo_cols,
      require_same = FALSE,  # 探测时不要 stop
      require_same_demo = isTRUE(harm$require_same_demo_cols %||% TRUE),
      index_exclude = index_excl
    ),
    error = function(e) NULL
  )
  n_clin <- length(as.character(gb$common_model_factors %||% character(0)))
  list(
    ok = n_clin > 0L && !isTRUE(gb$gate_b_per_db_fallback),
    n_clinical = n_clin,
    reason = if (n_clin > 0L) "ok" else "empty_clinical_intersection",
    fn = fn,
    fm = fm,
    gate_b = gb
  )
}

dual_db_build_model_factors_from_ctx <- function(ctx, cfg, db_name = NULL,
                                                 apply_max = TRUE) {
  harm <- (cfg$dual_db %||% list())$harmonization %||% list()
  index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    character(0)
  }

  pool_final <- as.character(ctx$results$vif_final_pass %||% character(0))
  pool_screen <- as.character(
    ctx$results$vif_screen_pass %||%
      ctx$results$vif_screen_pass_weighted %||%
      character(0)
  )
  # 尊重 dual_db$harmonization$covariate_source：多因素显著后仍可用单因素 VIF screen
  src <- dual_db_harmonization_covariate_source(cfg)
  if (identical(src, "vif_screen")) {
    selected <- if (length(pool_screen)) pool_screen else pool_final
  } else {
    selected <- if (length(pool_final)) pool_final else pool_screen
  }
  selected <- unique(selected[nzchar(selected)])
  selected <- setdiff(selected, index_excl)
  if (!length(selected)) {
    return(list(Model1Factors = character(0), Model2Factors = character(0)))
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
  if (exists(".mcol_apply_vif_final_covariate_split", mode = "function") &&
      is.data.frame(data) && ncol(data)) {
    # Gate B 取交集前禁止按库截断，否则先截断会丢掉对库仍保留的共有变量（如 Lactate）
    cfg_split <- cfg
    if (!isTRUE(apply_max)) {
      cfg_split$logistic <- cfg_split$logistic %||% list()
      cfg_split$logistic$model2_max_covariates <- 9999L
      cfg_split$incidence <- cfg_split$incidence %||% list()
      cfg_split$incidence$model2_max_covariates <- 9999L
    }
    split_res <- .mcol_apply_vif_final_covariate_split(ctx, cfg_split, selected, data)
    m1 <- unique(split_res$Model1Factors)
    m2 <- unique(split_res$Model2Factors)
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      cols <- if (is.data.frame(data)) names(data) else character(0)
      merged <- pipeline_merge_force_covariates(m1, m2, cols, cfg)
      m1 <- merged$M1
      m2 <- merged$M2
    }
    return(list(
      Model1Factors = m1,
      Model2Factors = m2
    ))
  }

  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  if (!length(demo_kw) && !is.null(db_name)) {
    if (dual_db_slot_is_primary(db_name)) {
      demo_kw <- as.character((cfg$multivariate_nhanes %||% list())$demo_keywords %||% character(0))
    } else {
      demo_kw <- as.character((cfg$multivariate_incidence_binary %||% list())$demo_keywords %||% character(0))
    }
  }
  demo_pattern <- paste(demo_kw, collapse = "|")
  Model2Factors <- selected
  Model1Factors <- Model2Factors[grepl(demo_pattern, Model2Factors, ignore.case = TRUE)]
  if (exists("pipeline_merge_force_covariates", mode = "function")) {
    cols <- if (is.data.frame(data)) names(data) else selected
    merged <- pipeline_merge_force_covariates(Model1Factors, Model2Factors, cols, cfg)
    Model1Factors <- merged$M1
    Model2Factors <- merged$M2
  }
  list(
    Model1Factors = unique(Model1Factors),
    Model2Factors = unique(Model2Factors)
  )
}

dual_db_read_factors_for_gate_b <- function(root, cfg, db_name, apply_max = FALSE) {
  src <- dual_db_harmonization_covariate_source(cfg)
  # 一律从对应 VIF 检查点的 pass 池重建 Model1/2；
  # 禁止直接读 Model2Factors（可能已被闸门 B 覆写成另一来源的对齐结果）。
  blk <- if (identical(src, "vif_screen")) {
    dual_db_vif_screen_block(cfg, db_name)
  } else {
    dual_db_vif_final_block(cfg, db_name)
  }
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  alias <- file.path(ck_dir, paste0(blk, ".rds"))
  if (!file.exists(alias) && identical(blk, "multicollinearity_screen")) {
    alt <- file.path(ck_dir, "ml_vif_train_test.rds")
    if (file.exists(alt)) alias <- alt
  }
  if (!file.exists(alias)) return(NULL)
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(NULL)
  cfg_src <- cfg
  cfg_src$dual_db <- cfg_src$dual_db %||% list()
  cfg_src$dual_db$harmonization <- cfg_src$dual_db$harmonization %||% list()
  cfg_src$dual_db$harmonization$covariate_source <- if (identical(src, "vif_screen")) {
    "vif_screen"
  } else {
    "vif_final"
  }
  dual_db_build_model_factors_from_ctx(obj$ctx, cfg_src, db_name, apply_max = apply_max)
}

dual_db_checkpoint_dir <- function(root, cfg, db_name) {
  base <- (cfg$dual_db %||% list())$checkpoint_base %||% "checkpoints/D04_Hematocrit_OA_dual"
  if (!is_absolute_path(base)) base <- file.path(root, base)
  dual_db_resolve_slot_dir(base, cfg, db_name)
}

#' 指标根下的分库输出目录（禁止嵌套在当前库 output_dir 下）
dual_db_index_db_output_dir <- function(root, cfg, db_name) {
  slot <- dual_db_slot_path_name(cfg, db_name)
  out <- as.character(cfg$project$output_dir %||% "")[1L]
  slot_names <- unique(c(
    dual_db_slot_path_name(cfg, "nhanes"),
    dual_db_slot_path_name(cfg, "mimic"),
    "NHANES", "CHARLS", "MIMIC", "eICU", "ELSA", "Hosp"
  ))
  slot_names <- slot_names[nzchar(as.character(slot_names))]
  ix_root <- out
  if (nzchar(out) && basename(out) %in% slot_names) {
    ix_root <- dirname(out)
  } else if (exists("incidence_batch_index_output_root", mode = "function")) {
    ix <- as.character(
      (cfg$incidence %||% list())$index_var %||%
        cfg$project$exposure_var %||%
        cfg$project$index_var %||%
        basename(out)
    )[1L]
    if (nzchar(ix) && !identical(ix, ".") && !identical(ix, "by_index")) {
      cand <- tryCatch(
        incidence_batch_index_output_root(cfg, ix),
        error = function(e) NULL
      )
      if (!is.null(cand) && nzchar(as.character(cand)[1L])) {
        cand <- as.character(cand)[1L]
        if (!is_absolute_path(cand)) cand <- file.path(root, cand)
        ix_root <- cand
      }
    }
  }
  if (!nzchar(ix_root)) ix_root <- file.path(root, "by_index")
  file.path(ix_root, slot)
}

dual_db_read_factors_from_checkpoint <- function(root, cfg, db_name, vif_block) {
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  alias <- file.path(ck_dir, paste0(vif_block, ".rds"))
  if (!file.exists(alias)) return(NULL)
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(NULL)
  list(
    Model1Factors = as.character(obj$ctx$results$Model1Factors %||% character(0)),
    Model2Factors = as.character(obj$ctx$results$Model2Factors %||% character(0))
  )
}

dual_db_patch_vif_checkpoint_factors <- function(root, cfg, db_name, vif_block, m1, m2) {
  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  alias <- file.path(ck_dir, paste0(vif_block, ".rds"))
  if (!file.exists(alias)) return(invisible(FALSE))
  obj <- readRDS(alias)
  if (is.null(obj$ctx)) return(invisible(FALSE))
  obj$ctx$results$Model1Factors <- m1
  obj$ctx$results$Model2Factors <- m2
  obj$ctx$results$dual_db_covariate_harmonized <- TRUE
  saveRDS(obj, alias)
  step_files <- list.files(ck_dir, pattern = paste0("_", vif_block, "\\.rds$"), full.names = TRUE)
  for (sf in step_files) {
    tryCatch({
      o2 <- readRDS(sf)
      if (!is.null(o2$ctx)) {
        o2$ctx$results$Model1Factors <- m1
        o2$ctx$results$Model2Factors <- m2
        o2$ctx$results$dual_db_covariate_harmonized <- TRUE
        saveRDS(o2, sf)
      }
    }, error = function(e) NULL)
  }
  invisible(TRUE)
}

# Gate B 锁定后回写磁盘摘要，避免 FinalCovariates / Model2Factors.txt 仍停留在单库 VIF final
dual_db_rewrite_locked_covariate_artifacts <- function(ctx, m1, m2) {
  cfg <- ctx$config %||% list()
  m1 <- unique(as.character(m1 %||% character(0)))
  m2 <- unique(as.character(m2 %||% character(0)))
  m1 <- m1[nzchar(m1)]
  m2 <- m2[nzchar(m2)]
  if (!length(m2) && !length(m1)) return(invisible(FALSE))

  ix_lab <- as.character(
    (cfg$survival %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      "Index"
  )[1L]
  db_lab <- tolower(trimws(as.character((cfg$project %||% list())$database %||% "db")))[1L]
  root <- ctx$root_output_dir %||% dirname(ctx$output_dir %||% ".")
  root <- tryCatch(normalizePath(root, winslash = "/", mustWork = FALSE), error = function(e) root)

  # Tables/Summary/FinalCovariates_*
  summary_dirs <- unique(c(
    file.path(root, "Tables", "Summary"),
    file.path(ctx$output_dir_tables %||% "", "Summary")
  ))
  summary_dirs <- summary_dirs[nzchar(summary_dirs)]
  cov_fname <- paste0("FinalCovariates_", ix_lab, "_", db_lab, ".txt")
  cov_lines <- c(
    paste0("# Final covariates (Model2Factors, Gate B locked) — ", ix_lab, " / ", toupper(db_lab)),
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("# Note: aligned with Table 2 Model 2 after dual_db_covariate_harmonize"),
    "",
    m2
  )
  for (d in summary_dirs) {
    tryCatch({
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      writeLines(cov_lines, file.path(d, cov_fname))
    }, error = function(e) NULL)
  }

  # 覆盖已有的 Model1/Model2Factors.txt（含 multicollinearity_final 落盘）
  cand_dirs <- unique(c(
    root,
    ctx$output_dir %||% character(0),
    list.dirs(root, recursive = FALSE, full.names = TRUE)
  ))
  cand_dirs <- cand_dirs[nzchar(as.character(cand_dirs))]
  for (d in cand_dirs) {
    m2p <- file.path(d, "Model2Factors.txt")
    m1p <- file.path(d, "Model1Factors.txt")
    if (file.exists(m2p)) {
      tryCatch(writeLines(m2, m2p), error = function(e) NULL)
      rda2 <- file.path(d, "Model2Factors.RData")
      if (file.exists(rda2)) {
        tryCatch({
          object <- m2
          save(object, file = rda2)
        }, error = function(e) NULL)
      }
    }
    if (file.exists(m1p) && length(m1)) {
      tryCatch(writeLines(m1, m1p), error = function(e) NULL)
      rda1 <- file.path(d, "Model1Factors.RData")
      if (file.exists(rda1)) {
        tryCatch({
          object <- m1
          save(object, file = rda1)
        }, error = function(e) NULL)
      }
    }
  }
  invisible(TRUE)
}

dual_db_apply_gate_b_to_ctx <- function(ctx, db_name, gate_b) {
  m1 <- as.character(gate_b[[paste0("harmonized_model1_", db_name)]] %||% character(0))
  m2 <- as.character(gate_b[[paste0("harmonized_model2_", db_name)]] %||% character(0))
  if (exists("pipeline_ensure_age_in_model1", mode = "function")) {
    cols <- if (exists("pipeline_ctx_data_cols", mode = "function")) {
      pipeline_ctx_data_cols(ctx)
    } else {
      character(0)
    }
    ens <- pipeline_ensure_age_in_model1(m1, m2, cols, ctx$config)
    m1 <- ens$M1
    m2 <- ens$M2
  }
  ctx$results$Model1Factors <- m1
  ctx$results$Model2Factors <- m2
  ctx$results$dual_db_covariate_harmonized <- TRUE
  ctx$results$dual_db_common_model_factors <- gate_b$common_model_factors
  # 同步 assoc 键，防止后续 ml_assoc_covariate_resolve 用 UV 铁律盖掉 Gate B
  ctx$results$assoc_model1_factors <- m1
  ctx$results$assoc_model2_factors <- m2
  ctx$results$assoc_model2_extras <- setdiff(m2, m1)
  ctx$results$assoc_covariate_note <- sprintf(
    "Gate B 写入 Model1=%s; Model2=%s",
    paste(m1, collapse = "+"), paste(m2, collapse = "+")
  )
  tryCatch(
    dual_db_rewrite_locked_covariate_artifacts(ctx, m1, m2),
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("Gate B 回写 FinalCovariates/Model2Factors 失败: {e$message}")
      }
      NULL
    }
  )

  if (dual_db_is_weighted(ctx$config, db_name)) {
    ctx$config$logistic_nhanes_weighted$model1_factors <- m1
    ctx$config$logistic_nhanes_weighted$model2_factors <- m2
    # RCS / 各档加权 logistic 与 Table 2 共用闸门 B 协变量
    for (blk in c(
      "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
      "logistic_binary_nhanes_weighted", "rcs_nhanes",
      "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
      "logistic_binary_nhanes_weighted_rcs",
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm"
    )) {
      if (!is.null(ctx$config[[blk]])) {
        ctx$config[[blk]]$model1_factors <- m1
        ctx$config[[blk]]$model2_factors <- m2
      }
    }
    ctx$results$nhanes_logistic_M1 <- m1
    ctx$results$nhanes_logistic_M2 <- m2
    ctx$results$logistic_model1_factors <- m1
    ctx$results$logistic_model2_factors <- m2
  } else {
    lock_cox <- isTRUE((ctx$config$dual_db$harmonization %||% list())$lock_cox_to_gate_b %||% TRUE)
    for (blk in c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "rcs_incidence",
      "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
      # 预后：Gate B 锁定后 Cox / RCS / 分段 Cox 共用 Gate B 池
      "cox_quartile", "cox_tertile", "cox_binary",
      "rcs_prognosis",
      "segmented_cox_quartile", "segmented_cox_tertile", "segmented_cox_binary"
    )) {
      if (!is.null(ctx$config[[blk]])) {
        ctx$config[[blk]]$model1_factors <- m1
        ctx$config[[blk]]$model2_factors <- m2
        # 搜索仍可开，但禁止 prefer_full 外再扩池；池=Gate B 集合
        # 双库 Table 2 一致由 worker Gate C 后的 cox 协变量再对齐完成
        if (lock_cox && grepl("^cox_", blk)) {
          sc <- ctx$config[[blk]]$covariate_search %||% list()
          # 允许搜索子集以求最高档显著，但池固定为 Gate B
          if (is.null(sc$enable)) sc$enable <- TRUE
          sc$prefer_full_first <- TRUE
          sc$pool_locked_to_gate_b <- TRUE
          ctx$config[[blk]]$covariate_search <- sc
        }
      }
    }
    ctx$results$logistic_model1_factors <- m1
    ctx$results$logistic_model2_factors <- m2
  }
  ctx
}

dual_db_save_gate_b <- function(root, cfg, gate_b) {
  dir <- dual_db_harmonization_dir(root, cfg)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  saveRDS(gate_b, dual_db_gate_b_cache_path(root, cfg))
  invisible(gate_b)
}

dual_db_load_gate_b <- function(root, cfg) {
  path <- dual_db_gate_b_cache_path(root, cfg)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

# 仅当程序员显式锁定协变量（lock_covariates_preset）或提供 common_model_factors 时跳过 VIF 闸门 B
dual_db_preset_gate_b <- function(cfg) {
  harm <- cfg$dual_db$harmonization %||% list()
  if (!isTRUE(harm$lock_covariates_preset)) {
    cmf_explicit <- as.character(harm$common_model_factors %||% character(0))
    if (!length(cmf_explicit)) return(NULL)
  }
  m1n <- as.character(harm$harmonized_model1_nhanes %||% character(0))
  m2n <- as.character(harm$harmonized_model2_nhanes %||% character(0))
  m1m <- as.character(harm$harmonized_model1_mimic %||% character(0))
  m2m <- as.character(harm$harmonized_model2_mimic %||% character(0))
  if (!length(m1n) || !length(m2n) || !length(m1m) || !length(m2m)) return(NULL)
  # lock_covariates_preset 显式锁定时允许 M2=M1（如严规则下双库 VIF 交集为空）
  if (!isTRUE(harm$lock_covariates_preset) &&
      (!length(setdiff(m2n, m1n)) || !length(setdiff(m2m, m1m)))) {
    cli::cli_alert_warning(
      "闸门 B 预设跳过：harmonized Model2 与 Model1 相同，请走 VIF 决策树对齐。"
    )
    return(NULL)
  }
  if (isTRUE(harm$lock_covariates_preset) &&
      (!length(setdiff(m2n, m1n)) || !length(setdiff(m2m, m1m)))) {
    cli::cli_alert_info(
      "闸门 B 预设锁：Model2=Model1（{paste(unique(c(m2n, m2m)), collapse = '+')}），允许 M2=M1"
    )
  }
  cmf <- as.character(harm$common_model_factors %||% character(0))
  if (!length(cmf)) {
    cmf <- setdiff(intersect(m2n, m2m), unique(c(m1n, m1m)))
  }
  list(
    common_model_factors     = cmf,
    harmonized_model1_nhanes = m1n,
    harmonized_model2_nhanes = m2n,
    harmonized_model1_mimic  = m1m,
    harmonized_model2_mimic  = m2m
  )
}

dual_db_repair_gate_b_m2_gt_m1 <- function(gate_b, cfg, root = NULL) {
  harm <- cfg$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  for (db in c("nhanes", "mimic")) {
    m1k <- paste0("harmonized_model1_", db)
    m2k <- paste0("harmonized_model2_", db)
    m1 <- as.character(gate_b[[m1k]] %||% character(0))
    m2 <- as.character(gate_b[[m2k]] %||% character(0))
    if (length(setdiff(m2, m1))) next

    pending <- if (!is.null(root) && nzchar(root)) {
      dual_db_read_pending_factors(root, cfg, db)
    } else {
      NULL
    }
    fb_m1 <- as.character(pending$Model1Factors %||% m1)
    fb_m2 <- as.character(pending$Model2Factors %||% m2)
    extra <- setdiff(fb_m2, m1)
    if (!length(extra)) {
      split_fb <- dual_db_split_demo_clinical(fb_m2, demo_kw)
      extra <- split_fb$clinical
    }
    if (!length(extra)) next

    ens <- dual_db_ensure_m2_gt_m1(m1, m2, extra)
    gate_b[[m1k]] <- ens$m1
    gate_b[[m2k]] <- ens$m2
    cli::cli_alert_warning(
      "闸门 B [{toupper(db)}]: Model2 与 Model1 相同，已回退 VIF 临床协变量: {paste(setdiff(ens$m2, ens$m1), collapse = ', ')}"
    )
  }
  clinical_n <- setdiff(
    gate_b$harmonized_model2_nhanes,
    gate_b$harmonized_model1_nhanes
  )
  clinical_m <- setdiff(
    gate_b$harmonized_model2_mimic,
    gate_b$harmonized_model1_mimic
  )
  gate_b$common_model_factors <- intersect(clinical_n, clinical_m)
  gate_b
}

dual_db_gate_b_assert_aligned <- function(gate_b, cfg) {
  harm <- cfg$dual_db$harmonization %||% list()
  require_clinical <- isTRUE(harm$require_same_clinical_cols %||% TRUE)
  lock_preset <- isTRUE(harm$lock_covariates_preset)
  if (require_clinical) {
    cmf <- as.character(gate_b$common_model_factors %||% character(0))
    if (!length(cmf) && isTRUE(harm$stop_on_empty_common_clinical %||% TRUE) &&
        !isTRUE(lock_preset)) {
      stop(
        "GATE_B_EMPTY_COMMON: 对齐后 common_model_factors 为空，已停止。",
        call. = FALSE
      )
    }
    for (db in c("nhanes", "mimic")) {
      m1 <- as.character(gate_b[[paste0("harmonized_model1_", db)]] %||% character(0))
      m2 <- as.character(gate_b[[paste0("harmonized_model2_", db)]] %||% character(0))
      if (!length(setdiff(m2, m1))) {
        if (isTRUE(lock_preset)) {
          cli::cli_alert_info(
            "闸门 B 预设锁允许 {toupper(db)} Model2=Model1: {paste(m1, collapse = ', ')}"
          )
          next
        }
        stop(
          "GATE_B_M2_EQ_M1: ", toupper(db),
          " Model2 与 Model1 相同（", paste(m1, collapse = ", "), "），已停止。",
          call. = FALSE
        )
      }
    }
  }
  # 人口学要求对齐时，两库 Model1/Model2 集合必须一致（顺序无关）
  if (isTRUE(harm$require_same_demo_cols %||% TRUE) &&
      !isTRUE(gate_b$gate_b_per_db_fallback %||% FALSE) &&
      length(as.character(gate_b$common_model_factors %||% character(0)))) {
    m1n <- sort(unique(as.character(gate_b$harmonized_model1_nhanes %||% character(0))))
    m1m <- sort(unique(as.character(gate_b$harmonized_model1_mimic %||% character(0))))
    m2n <- sort(unique(as.character(gate_b$harmonized_model2_nhanes %||% character(0))))
    m2m <- sort(unique(as.character(gate_b$harmonized_model2_mimic %||% character(0))))
    if (!identical(m1n, m1m) || !identical(m2n, m2m)) {
      stop(
        paste0(
          "GATE_B_MODEL_MISMATCH: 两库 Model1/Model2 未完全统一。",
          " eICU Model1=", paste(m1n, collapse = ","),
          " Model2=", paste(m2n, collapse = ","),
          "; MIMIC Model1=", paste(m1m, collapse = ","),
          " Model2=", paste(m2m, collapse = ",")
        ),
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

dual_db_finalize_gate_b <- function(root, cfg, gate_b, src_label = "闸门 B") {
  harm <- cfg$dual_db$harmonization %||% list()
  gate_b <- dual_db_constrain_gate_b_models(gate_b, cfg)
  if (!isTRUE(harm$require_same_clinical_cols %||% TRUE)) {
    gate_b <- dual_db_repair_gate_b_m2_gt_m1(gate_b, cfg, root = root)
  }
  dual_db_gate_b_assert_aligned(gate_b, cfg)
  dual_db_save_gate_b(root, cfg, gate_b)
  dual_db_patch_vif_checkpoint_factors(
    root, cfg, "nhanes", dual_db_vif_final_block(cfg, "nhanes"),
    gate_b$harmonized_model1_nhanes, gate_b$harmonized_model2_nhanes
  )
  dual_db_patch_vif_checkpoint_factors(
    root, cfg, "mimic", dual_db_vif_final_block(cfg, "mimic"),
    gate_b$harmonized_model1_mimic, gate_b$harmonized_model2_mimic
  )
  cli::cli_alert_success(
    "{src_label}：临床协变量 {length(gate_b$common_model_factors)} 个已对齐"
  )
  gate_b
}

dual_db_try_sync_gate_b <- function(root, cfg, db_name, m1, m2) {
  preset <- dual_db_preset_gate_b(cfg)
  if (!is.null(preset)) {
    # lock 预设时仍探测 S6 临床交集：空则发表表省略 S5/S6（与 auto 回退 S4 同口径）
    omit_s56 <- FALSE
    if (exists("dual_db_probe_gate_b_clinical_intersection", mode = "function")) {
      probe_lock <- tryCatch(
        dual_db_probe_gate_b_clinical_intersection(root, cfg, source = "vif_final"),
        error = function(e) NULL
      )
      if (!is.null(probe_lock) && !isTRUE(probe_lock$ok)) {
        omit_s56 <- identical(
          as.character(probe_lock$reason %||% "")[1L], "empty_clinical_intersection"
        ) || identical(dual_db_harmonization_covariate_source(cfg), "vif_screen")
      } else if (identical(dual_db_harmonization_covariate_source(cfg), "vif_screen")) {
        omit_s56 <- TRUE
      }
    } else if (identical(dual_db_harmonization_covariate_source(cfg), "vif_screen")) {
      omit_s56 <- TRUE
    }
    preset$omit_multivariate_and_vif_final_tables <- isTRUE(omit_s56)
    if (isTRUE(omit_s56)) {
      cli::cli_alert_info(
        "闸门 B（config 预设）：S6 临床交集空/已用 vif_screen → 发表表将省略多因素(S5)与 VIF final(S6)"
      )
    }
    return(dual_db_finalize_gate_b(root, cfg, preset, "闸门 B（config 预设）"))
  }

  harm <- cfg$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  cov_src_raw <- dual_db_resolve_gate_b_covariate_source(root, cfg)
  omit_mv_final <- isTRUE(attr(cov_src_raw, "omit_multivariate_and_vif_final_tables"))
  cov_src <- as.character(cov_src_raw)[1L]

  # vif_screen：始终从两库 screen 检查点读全量池再交集（忽略 pending / 传入的已截断 Model2）
  if (identical(cov_src, "vif_screen")) {
    cfg_screen <- cfg
    cfg_screen$dual_db$harmonization$covariate_source <- "vif_screen"
    fn <- dual_db_read_factors_for_gate_b(root, cfg_screen, "nhanes", apply_max = FALSE)
    fm <- dual_db_read_factors_for_gate_b(root, cfg_screen, "mimic", apply_max = FALSE)
    if (is.null(fn) || is.null(fm)) {
      cli::cli_alert_warning(
        "闸门 B：单因素 VIF screen 检查点不齐，跳过协变量对齐（待两库均完成后重跑本步）"
      )
      return(NULL)
    }
    dual_db_write_pending_factors(root, cfg, "nhanes", fn$Model1Factors, fn$Model2Factors)
    dual_db_write_pending_factors(root, cfg, "mimic", fm$Model1Factors, fm$Model2Factors)
    index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
      pipeline_index_exclude_vars(cfg)
    } else {
      character(0)
    }
    gate_b <- dual_db_compute_gate_b(
      m1_nhanes = fn$Model1Factors, m2_nhanes = fn$Model2Factors,
      m1_mimic = fm$Model1Factors, m2_mimic = fm$Model2Factors,
      demo_keywords = demo_kw,
      common_col_order = harm$common_non_demo_cols,
      require_same = isTRUE(harm$require_same_clinical_cols),
      require_same_demo = isTRUE(harm$require_same_demo_cols %||% TRUE),
      index_exclude = index_excl
    )
    gate_b$covariate_source_used <- "vif_screen"
    gate_b$omit_multivariate_and_vif_final_tables <- omit_mv_final
    if (isTRUE(omit_mv_final)) {
      cli::cli_alert_info(
        "闸门 B：S6 临床交集空已回退 S4 → 发表表将省略多因素(S5)与 VIF final(S6)，后续附表顺延编号"
      )
    }
    return(dual_db_finalize_gate_b(root, cfg, gate_b, "闸门 B（单因素 VIF screen）"))
  }

  dual_db_write_pending_factors(root, cfg, db_name, m1, m2)

  other <- if (dual_db_slot_is_primary(db_name)) dual_db_slot_secondary() else dual_db_slot_primary()
  other_src <- dual_db_read_pending_factors(root, cfg, other)
  if (is.null(other_src)) {
    cfg_final <- cfg
    cfg_final$dual_db$harmonization$covariate_source <- "vif_final"
    other_src <- dual_db_read_factors_for_gate_b(root, cfg_final, other, apply_max = FALSE)
  }
  if (is.null(other_src)) {
    cli::cli_alert_warning(
      "闸门 B：对库 {.field {other}} 尚无 VIF final 结果，跳过协变量对齐（待两库均完成后重跑本步）"
    )
    return(NULL)
  }

  index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    character(0)
  }
  same_demo <- isTRUE(harm$require_same_demo_cols %||% TRUE)
  if (dual_db_slot_is_primary(db_name)) {
    gate_b <- dual_db_compute_gate_b(
      m1_nhanes = m1, m2_nhanes = m2,
      m1_mimic = other_src$Model1Factors, m2_mimic = other_src$Model2Factors,
      demo_keywords = demo_kw,
      common_col_order = harm$common_non_demo_cols,
      require_same = isTRUE(harm$require_same_clinical_cols),
      require_same_demo = same_demo,
      index_exclude = index_excl
    )
  } else {
    gate_b <- dual_db_compute_gate_b(
      m1_nhanes = other_src$Model1Factors, m2_nhanes = other_src$Model2Factors,
      m1_mimic = m1, m2_mimic = m2,
      demo_keywords = demo_kw,
      common_col_order = harm$common_non_demo_cols,
      require_same = isTRUE(harm$require_same_clinical_cols),
      require_same_demo = same_demo,
      index_exclude = index_excl
    )
  }

  gate_b$covariate_source_used <- cov_src
  gate_b$omit_multivariate_and_vif_final_tables <- FALSE
  dual_db_finalize_gate_b(
    root, cfg, gate_b,
    if (identical(cov_src, "vif_screen")) "闸门 B（单因素 VIF screen）"
    else "闸门 B（多因素 VIF final）"
  )
}

#' logistic 初筛（含闸门救援）后读取各库 Model1/2
dual_db_read_logistic_screen_covariates <- function(root, cfg, db_name, scheme_hint = NULL) {
  st <- dual_db_read_logistic_state_from_checkpoint(root, cfg, db_name, scheme_hint = scheme_hint)
  if (is.null(st)) return(NULL)
  m1 <- unique(as.character(st$m1[nzchar(st$m1)]))
  m2 <- unique(as.character(st$m2[nzchar(st$m2)]))
  if (!length(m1) || !length(m2)) return(NULL)
  list(m1 = m1, m2 = m2, scheme = st$scheme, branch = st$branch)
}

#' 两库 logistic 救援/初筛完成后，用各库 Model1/2 重算 Gate B（临床取交集）
dual_db_resync_gate_b_after_logistic <- function(root, cfg, scheme_hint = NULL) {
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(NULL)
  if (exists("locked_mv_n_databases", mode = "function") &&
      locked_mv_n_databases(cfg) < 2L) {
    return(NULL)
  }
  if (!is.null(dual_db_preset_gate_b(cfg))) return(NULL)

  primary <- dual_db_slot_primary()
  secondary <- dual_db_slot_secondary()
  uni <- dual_db_load_logistic_branch(root, cfg)
  scheme_hint <- as.character(scheme_hint %||% uni$scheme %||% "")[1L]
  st_n <- dual_db_read_logistic_screen_covariates(root, cfg, primary, scheme_hint = scheme_hint)
  st_m <- dual_db_read_logistic_screen_covariates(root, cfg, secondary, scheme_hint = scheme_hint)
  if (is.null(st_n) || is.null(st_m)) return(NULL)

  harm <- dual$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    character(0)
  }
  gate_b <- dual_db_compute_gate_b(
    m1_nhanes = st_n$m1, m2_nhanes = st_n$m2,
    m1_mimic = st_m$m1, m2_mimic = st_m$m2,
    demo_keywords = demo_kw,
    common_col_order = harm$common_non_demo_cols,
    require_same = isTRUE(harm$require_same_clinical_cols),
    require_same_demo = isTRUE(harm$require_same_demo_cols %||% TRUE),
    index_exclude = index_excl
  )
  gate_b$covariate_source_used <- "logistic_screen"
  gate_b$gate_b_after_logistic_rescue <- TRUE
  dual_db_finalize_gate_b(
    root, cfg, gate_b,
    "闸门 B（logistic 救援后双库协变量对齐）"
  )
}

dual_db_ensure_logistic_table2_helpers <- function(cfg, db_name, scheme) {
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng)) eng <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  scheme <- as.character(scheme)[1L]
  common <- file.path(eng, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R")
  if (file.exists(common)) suppressWarnings(source(common, local = FALSE))
  if (dual_db_is_weighted(cfg, db_name)) {
    nhanes_blk <- switch(scheme,
      quartile = "13block_logistic_quartile_nhanes_weighted.R",
      tertile  = "14block_logistic_tertile_nhanes_weighted.R",
      binary   = "15block_logistic_binary_nhanes_weighted.R",
      NULL
    )
    if (!is.null(nhanes_blk)) {
      p <- file.path(eng, "Blocks/11_logistic", nhanes_blk)
      if (file.exists(p)) suppressWarnings(source(p, local = FALSE))
    }
    return(invisible(TRUE))
  }
  glm_blk <- switch(scheme,
    quartile = "01block_logistic_quartile_glm.R",
    tertile  = "05block_logistic_tertile_glm.R",
    binary   = "04block_logistic_binary_glm.R",
    NULL
  )
  if (!is.null(glm_blk)) {
    p <- file.path(eng, "Blocks/11_logistic", glm_blk)
    if (file.exists(p)) suppressWarnings(source(p, local = FALSE))
  }
  # tertile block 用 .lqg05_*；rebuild 统一走 .lqg01_* 接口 → 补别名
  # 同时 source 四分位块以复用 .lqg01_Tb_ModelGroup3_OR（若尚未加载）
  if (identical(scheme, "tertile")) {
    q_p <- file.path(eng, "Blocks/11_logistic/01block_logistic_quartile_glm.R")
    if (file.exists(q_p) && !exists(".lqg01_Tb_ModelGroup3_OR", mode = "function")) {
      suppressWarnings(source(q_p, local = FALSE))
    }
    if (!exists(".lqg01_assign_tertile_groups", mode = "function") &&
        exists(".lqg05_tertile_from_cfg", mode = "function")) {
      .lqg01_assign_tertile_groups <<- function(x, bl_cfg = list()) {
        r <- .lqg05_tertile_from_cfg(x, bl_cfg = bl_cfg)
        list(
          Group = r$group,
          Num = as.numeric(r$group),
          raw_levels = as.character(r$levels),
          cutoffs = r$cutoffs
        )
      }
    }
  }
  invisible(TRUE)
}

dual_db_logistic_block_for_scheme <- function(cfg, db_name, scheme) {
  scheme <- as.character(scheme)[1L]
  if (dual_db_is_weighted(cfg, db_name)) {
    switch(scheme,
      quartile = "logistic_quartile_nhanes_weighted",
      tertile  = "logistic_tertile_nhanes_weighted",
      binary   = "logistic_binary_nhanes_weighted",
      NULL
    )
  } else {
    switch(scheme,
      quartile = "logistic_quartile_glm",
      tertile  = "logistic_tertile_glm",
      binary   = "logistic_binary_glm",
      NULL
    )
  }
}

#' Gate B 对齐后按统一分位重算 Table 2（不重新搜协变量）
dual_db_rebuild_logistic_table2_for_db <- function(root, cfg, db_name, gate_b, scheme) {
  scheme <- as.character(scheme)[1L]
  dual_db_ensure_logistic_table2_helpers(cfg, db_name, scheme)
  blk <- dual_db_logistic_block_for_scheme(cfg, db_name, scheme)
  if (is.null(blk)) return(invisible(FALSE))

  ck_dir <- dual_db_checkpoint_dir(root, cfg, db_name)
  alias <- file.path(ck_dir, paste0(blk, ".rds"))
  if (!file.exists(alias)) return(invisible(FALSE))
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(invisible(FALSE))

  ctx <- obj$ctx
  ctx <- dual_db_apply_gate_b_to_ctx(ctx, db_name, gate_b)
  out_db <- dual_db_index_db_output_dir(root, cfg, db_name)
  # 导出库标签必须与 peer 一致，避免当前 worker 的 database=CHARLS 污染 NHANES 文件名/内容镜像
  if (is.null(ctx$config$project)) ctx$config$project <- list()
  ctx$config$project$database <- dual_db_slot_path_name(cfg, db_name)
  ctx$config$project$output_dir <- out_db
  ctx$output_dir <- out_db
  ctx$output_dir_tables <- file.path(out_db, "Tables")
  ctx$output_dir_figures <- file.path(out_db, "Figures")
  if (!dir.exists(ctx$output_dir_tables)) dir.create(ctx$output_dir_tables, recursive = TRUE)
  M1 <- as.character(ctx$results$Model1Factors)
  M2 <- as.character(ctx$results$Model2Factors)
  bl_cfg <- ctx$config[[blk]] %||% list()
  cfg_local <- ctx$config
  index_var <- as.character(
    bl_cfg$index_var %||% (cfg_local$incidence %||% list())$index_var %||% "BMI"
  )[1L]
  outcome_col <- cfg_local$data$outcome_column %||% "Disease_Group"
  disease_lbl <- (cfg_local$project %||% list())$analysis_group %||%
    (cfg_local$project %||% list())$disease %||% "Case"
  ix_label <- if (exists("pipeline_index_display_name", mode = "function")) {
    pipeline_index_display_name(cfg_local, index_var)
  } else {
    index_var
  }
  include_cont <- isTRUE(bl_cfg$include_continuous_row %||% TRUE)

  tb <- NULL
  if (dual_db_is_weighted(cfg, db_name)) {
    design <- ctx$results$nhanes_design
    if (is.null(design)) return(invisible(FALSE))
    grp <- NULL
    if (identical(scheme, "quartile") && exists(".lqq09_apply_quartile", mode = "function")) {
      grp <- .lqq09_apply_quartile(design, index_var)
      if (exists(".lqq09_build_table", mode = "function")) {
        tb <- .lqq09_build_table(
          grp$design, outcome_col, disease_lbl, index_var, M1, M2,
          grp$cutoffs, grp$raw_levels, include_cont, ix_label
        )
      }
    } else if (identical(scheme, "tertile") &&
               exists(".lqt09_apply_tertile", mode = "function") &&
               exists(".lqt09_build_table", mode = "function")) {
      grp <- .lqt09_apply_tertile(design, index_var)
      tb <- .lqt09_build_table(
        grp$design, outcome_col, disease_lbl, index_var, M1, M2,
        grp$cutoffs, grp$raw_levels, include_cont
      )
    } else if (identical(scheme, "binary") &&
               exists(".lqb09_apply_binary", mode = "function") &&
               exists(".lqb09_build_table", mode = "function")) {
      grp <- .lqb09_apply_binary(design, index_var)
      tb <- .lqb09_build_table(
        grp$design, outcome_col, disease_lbl, index_var, M1, M2,
        grp$cutoffs, grp$raw_levels, include_cont
      )
    }
  } else {
    data <- ctx$data$imputed %||% ctx$data$cleaned
    if (is.null(data) || !is.data.frame(data)) return(invisible(FALSE))
    data2 <- data
    if (exists("pipeline_index_as_numeric", mode = "function")) {
      data2[[index_var]] <- pipeline_index_as_numeric(data2[[index_var]])
    }
    group_var_name <- bl_cfg$group_var
    predefined <- !is.null(group_var_name) && nzchar(group_var_name) &&
      group_var_name %in% names(data2)
    if (predefined) {
      raw_levels <- bl_cfg$group_levels %||% sort(unique(as.character(data2[[group_var_name]])))
      raw_levels <- as.character(raw_levels[nzchar(raw_levels)])
      data2$Group <- factor(as.character(data2[[group_var_name]]), levels = raw_levels)
      data2$Num <- as.numeric(data2$Group)
      cutoffs <- setNames(rep("", length(raw_levels)), raw_levels)
    } else if (identical(scheme, "quartile") && exists(".lqg01_assign_quartile_groups", mode = "function")) {
      qg <- .lqg01_assign_quartile_groups(data2[[index_var]])
      data2$Group <- qg$Group
      data2$Num <- qg$Num
      raw_levels <- qg$raw_levels
      cutoffs <- qg$cutoffs
    } else if (identical(scheme, "tertile") && exists(".lqg01_assign_tertile_groups", mode = "function")) {
      qg <- .lqg01_assign_tertile_groups(data2[[index_var]])
      data2$Group <- qg$Group
      data2$Num <- qg$Num
      raw_levels <- qg$raw_levels
      cutoffs <- qg$cutoffs
    } else if (identical(scheme, "binary") && exists(".lqg01_assign_binary_groups", mode = "function")) {
      qg <- .lqg01_assign_binary_groups(data2[[index_var]])
      data2$Group <- qg$Group
      data2$Num <- qg$Num
      raw_levels <- qg$raw_levels
      cutoffs <- qg$cutoffs
    } else {
      return(invisible(FALSE))
    }
    data2[[outcome_col]] <- as.character(data2[[outcome_col]])
    data2[[outcome_col]] <- ifelse(data2[[outcome_col]] == disease_lbl, 1L, 0L)
    excl <- c(outcome_col, index_var, "Group", "Num", if (predefined) group_var_name)
    CrudeFactors <- intersect(
      as.character(bl_cfg$crude_factors %||% cfg_local$logistic_covariates$crude_factors %||% character(0)),
      names(data2)
    )
    if (exists(".lqg01_Tb_ModelGroup3_OR", mode = "function")) {
      tb <- .lqg01_Tb_ModelGroup3_OR(
        outcome_col, index_var, "Group", "Num",
        data2, M1, M2, cutoffs, raw_levels, include_cont,
        index_label = ix_label, CrudeFactors = CrudeFactors
      )
    }
  }

  if (is.null(tb)) {
    cli::cli_alert_warning(
      "双库协变量对齐后重导 Table 2 [{toupper(db_name)}] 失败（未生成表体）"
    )
    return(invisible(FALSE))
  }

  ctx$results$logistic_table2 <- tb
  ctx$results$logistic_model1_factors <- M1
  ctx$results$logistic_model2_factors <- M2
  ctx$results$nhanes_logistic_M1 <- M1
  ctx$results$nhanes_logistic_M2 <- M2
  ctx$results$logistic_grouping_scheme <- scheme
  ctx$results$nhanes_logistic_selected_scheme <- scheme
  ctx$results$nhanes_logistic_grouping_scheme <- scheme
  if (dual_db_is_weighted(cfg, db_name)) {
    ctx$results[[paste0("logistic_table2_", scheme, "_nhanes")]] <- tb
    ctx$results$logistic_table2_weighted <- tb
    ctx$results$logistic_table2_nhanes <- tb
    ctx$results$nhanes_logistic_table2 <- tb
  }

  obj$ctx <- ctx
  saveRDS(obj, alias)
  step_alias <- list.files(ck_dir, pattern = paste0("_", blk, "\\.rds$"), full.names = TRUE)
  for (sf in step_alias) {
    tryCatch({
      o2 <- readRDS(sf)
      if (!is.null(o2$ctx)) {
        o2$ctx <- ctx
        saveRDS(o2, sf)
      }
    }, error = function(e) NULL)
  }

  cap <- if (dual_db_is_weighted(cfg, db_name)) {
    paste0(
      "Weighted logistic regression of ", index_var, " and ", disease_lbl,
      " (NHANES ", scheme, ", svyglm) [dual-DB unified]"
    )
  } else {
    # 标题必须用疾病显示名（disease_lbl），禁止写原始 outcome 列名（如 DN）
    paste0(
      "Logistic regression analysis of ", index_var, " and ", disease_lbl,
      " - ", scheme, " (GLM) [dual-DB unified]"
    )
  }
  ft <- NULL
  if (exists(".lnw00_table_footnotes", mode = "function")) {
    ft <- .lnw00_table_footnotes(M1, M2, character(0), FALSE)
  } else if (exists("logistic_glm_table_footnotes", mode = "function")) {
    ft <- logistic_glm_table_footnotes(M1, M2, character(0), FALSE)
  }
  if (exists(".lnw00_export_table2", mode = "function")) {
    if (exists(".pub_state", inherits = TRUE)) {
      # get() 在对象不存在时会直接报错，不能靠 %||% 兜底
      old_mt <- as.integer(get0("main_table", envir = .pub_state, inherits = FALSE, ifnotfound = 0L))
      on.exit(assign("main_table", old_mt, envir = .pub_state), add = TRUE)
      assign("main_table", 1L, envir = .pub_state)
    }
    db_disp <- dual_db_slot_path_name(cfg, db_name)
    old_opt <- getOption("pipeline.database_name")
    on.exit(options(pipeline.database_name = old_opt), add = TRUE)
    options(pipeline.database_name = db_disp)
    .lnw00_export_table2(ctx, cfg_local, bl_cfg, tb, cap, as_main = TRUE, table_footnotes = ft)
    # 离线重导须立刻 flush，否则队列项随进程结束丢失
    if (exists("render_queued_tables", mode = "function")) {
      tryCatch(
        render_queued_tables(list(
          output_dir = ctx$output_dir,
          output_dir_tables = ctx$output_dir_tables,
          config = ctx$config
        )),
        error = function(e) cli::cli_alert_warning("重导 Table2 flush 失败: {e$message}")
      )
    }
  }

  cli::cli_alert_success(
    "双库协变量对齐后重导 Table 2 [{toupper(db_name)}]: Model2={paste(M2, collapse = ', ')}"
  )
  invisible(TRUE)
}

dual_db_force_gate_b_sync <- function(root, cfg) {
  # 程序员显式锁定协变量时优先走 preset，避免 VIF screen/final 覆盖 lock
  preset <- dual_db_preset_gate_b(cfg)
  if (!is.null(preset)) {
    return(dual_db_finalize_gate_b(root, cfg, preset, "闸门 B（强制同步·config 预设锁）"))
  }

  harm <- cfg$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  cov_src <- dual_db_resolve_gate_b_covariate_source(root, cfg)

  cfg_read <- cfg
  cfg_read$dual_db <- cfg_read$dual_db %||% list()
  cfg_read$dual_db$harmonization <- cfg_read$dual_db$harmonization %||% list()
  cfg_read$dual_db$harmonization$covariate_source <- cov_src
  fn <- dual_db_read_factors_for_gate_b(root, cfg_read, "nhanes", apply_max = FALSE)
  fm <- dual_db_read_factors_for_gate_b(root, cfg_read, "mimic", apply_max = FALSE)

  # auto 已在 resolve 里选好统一来源；若仍缺检查点则硬失败（禁止一库 screen 一库 final 拼凑）
  if (is.null(fn) || is.null(fm)) {
    stage_label <- if (identical(cov_src, "vif_screen")) "VIF screen" else "VIF final"
    stop(
      "GATE_B_SYNC_FAIL: 闸门 B 强制同步缺少 ", stage_label,
      " 检查点（两库必须同一来源），已停止。",
      call. = FALSE
    )
  }

  # 记录统一来源，便于审计
  dual_db_write_pending_factors(root, cfg, "nhanes", fn$Model1Factors, fn$Model2Factors)
  dual_db_write_pending_factors(root, cfg, "mimic", fm$Model1Factors, fm$Model2Factors)

  index_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    character(0)
  }
  gate_b <- dual_db_compute_gate_b(
    m1_nhanes = fn$Model1Factors, m2_nhanes = fn$Model2Factors,
    m1_mimic = fm$Model1Factors, m2_mimic = fm$Model2Factors,
    demo_keywords = demo_kw,
    common_col_order = harm$common_non_demo_cols,
    require_same = isTRUE(harm$require_same_clinical_cols),
    require_same_demo = isTRUE(harm$require_same_demo_cols %||% TRUE),
    index_exclude = index_excl
  )
  gate_b$covariate_source_used <- cov_src
  lbl <- if (identical(cov_src, "vif_screen")) {
    "闸门 B（强制同步·单因素 VIF screen，两库统一）"
  } else {
    "闸门 B（强制同步·多因素 VIF final，两库统一）"
  }
  dual_db_finalize_gate_b(root, cfg, gate_b, lbl)
}

mirror_dual_db_aggregate <- function(root, cfg, out_root = NULL,
                                     dbs = c("nhanes", "mimic")) {
  if (!isTRUE((cfg$dual_db %||% list())$mirror_aggregate)) return(invisible(NULL))
  if (is.null(out_root) || !nzchar(as.character(out_root)[1L])) {
    out_root <- (cfg$project %||% list())$output_dir %||% "Output/D04_Hematocrit_OA_dual"
  }
  if (!is_absolute_path(out_root)) out_root <- file.path(root, out_root)
  parent_tables <- file.path(out_root, "Tables")
  parent_figures <- file.path(out_root, "Figures")
  dir.create(parent_tables, recursive = TRUE, showWarnings = FALSE)
  dir.create(parent_figures, recursive = TRUE, showWarnings = FALSE)

  dbs <- unique(as.character(dbs[nzchar(as.character(dbs))]))
  n_copied <- 0L
  prefix_db <- isTRUE((cfg$dual_db %||% list())$mirror_aggregate_prefix_db)
  .agg_known_db_tags <- unique(toupper(c(
    vapply(dbs, function(d) dual_db_slot_path_name(cfg, d), character(1)),
    "NHANES", "CHARLS", "MIMIC", "EICU", "ELSA", "HOSP"
  )))
  .agg_copy_one <- function(f, kind, db) {
    if (file.info(f)$isdir) return(invisible(FALSE))
    bn <- basename(f)
    # 汇总 Tables 不收 .tex（LaTeX 仅留在各 step 子目录）
    if (kind == "Tables" && grepl("\\.tex$", bn, ignore.case = TRUE)) return(invisible(FALSE))
    # 汇总 Tables 不收诊断/中间 csv（如 Analysis_exclusion_*.csv、Flowchart_attrition*.csv）
    if (kind == "Tables" && grepl("\\.csv$", bn, ignore.case = TRUE)) return(invisible(FALSE))
    if (kind == "Tables" && grepl("^Analysis_exclusion_", bn, ignore.case = TRUE)) {
      return(invisible(FALSE))
    }
    # ROC 数值表留在 step 子目录，不进发表 Tables
    if (kind == "Tables" && grepl("ROC", bn, ignore.case = TRUE)) {
      return(invisible(FALSE))
    }
    # 文件名库标签须与源库一致，防止 CHARLS 内容进 NHANES 表（或反向）后污染汇总
    if (kind == "Tables" && grepl("^Table\\s+", bn, ignore.case = TRUE)) {
      slot <- toupper(dual_db_slot_path_name(cfg, db))
      m <- regexec("^Table\\s+[A-Za-z0-9.-]+-([A-Za-z0-9]+)\\.", bn, perl = TRUE)
      hit <- regmatches(bn, m)[[1L]]
      if (length(hit) >= 2L) {
        tag <- toupper(hit[[2L]])
        if (tag %in% .agg_known_db_tags && !identical(tag, slot)) {
          cli::cli_alert_warning(
            "跳过串库表（源={slot} 文件标签={tag}）: {bn}"
          )
          return(invisible(FALSE))
        }
      }
    }
    dest <- if (kind == "Tables") parent_tables else parent_figures
    dest_name <- if (prefix_db) paste0(dual_db_slot_path_name(cfg, db), "_", bn) else bn
    dp <- file.path(dest, dest_name)
    # 同名已存在时取 mtime 最新，避免旧图覆盖新图
    if (file.exists(dp) && file.info(dp)$mtime >= file.info(f)$mtime) return(invisible(FALSE))
    if (file.copy(f, dp, overwrite = TRUE)) { n_copied <<- n_copied + 1L; invisible(TRUE) } else invisible(FALSE)
  }
  # 清理历史误拷入汇总的 .tex
  if (dir.exists(parent_tables)) {
    stale_tex <- list.files(parent_tables, pattern = "\\.tex$", full.names = TRUE, ignore.case = TRUE)
    if (length(stale_tex)) {
      unlink(stale_tex)
      cli::cli_alert_info("已清理汇总 Tables 中 {length(stale_tex)} 个 .tex")
    }
  }
  for (db in dbs) {
    db_out <- dual_db_resolve_slot_dir(out_root, cfg, db)
    for (kind in c("Tables", "Figures")) {
      src <- file.path(db_out, kind)
      if (!dir.exists(src)) next
      for (f in list.files(src, full.names = TRUE, recursive = FALSE)) {
        # 汇总 Figures 不收 SVG（仅保留 pdf/png/jpg）
        if (identical(kind, "Figures") &&
            grepl("\\.svg$", basename(f), ignore.case = TRUE)) next
        # 库级 Tables 也不留 .tex（与根汇总一致；tex 仅 step 子目录）
        if (identical(kind, "Tables") &&
            grepl("\\.tex$", basename(f), ignore.case = TRUE)) {
          unlink(f)
          next
        }
        .agg_copy_one(f, kind, db)
      }
    }
    # KM / cutoff / ROC / boxplot / mediation 等图可能仅落在 step*_*/Figures；
    # db 级 Figures 若被后续步骤覆盖会丢失，直接从相关 step 子目录兜底汇总。
    if (dir.exists(db_out)) {
      step_dirs <- list.dirs(db_out, recursive = FALSE, full.names = TRUE)
      fig_steps <- step_dirs[grepl(
        "step[0-9]+_(km|plot_cutoff|simple_ROC|boxplot|mediation)",
        basename(step_dirs), ignore.case = TRUE
      )]
      for (sd in fig_steps) {
        fd <- file.path(sd, "Figures")
        if (!dir.exists(fd)) next
        for (f in list.files(fd, pattern = "\\.(pdf|png|jpg|jpeg)$",
                             full.names = TRUE, ignore.case = TRUE)) {
          .agg_copy_one(f, "Figures", db)
        }
      }
    }
  }
  cli::cli_alert_info(
    "双库汇总镜像 ({n_copied} 个文件): {.file {parent_tables}} / {.file {parent_figures}}"
  )
  invisible(TRUE)
}
