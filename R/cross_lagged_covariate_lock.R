###############################################################################
#  R/cross_lagged_covariate_lock.R
#  交叉滞后：三库协变量锁定
#
#  规则：
#    1) 优先三库 VIF final Model2 交集（去掉 FI/Frailty/Country 等）
#    2) 若 final 交集为空 → 回退三库 VIF screen（UV p<0.1 后 VIF）交集
#    3) 若仍空（或 force_elsa_hrs_common=TRUE）→ ELSA∩HRS UV/screen 共有协变量，强制套到 CHARLS
#    4) Model1 优先 Age；Model2 = 完整锁定集；Pooled 另加 Country
###############################################################################

cross_lagged_phase1_dir <- function(study_root, db) {
  cands <- c(
    file.path(study_root, paste0("phase1_", db, "_allages")),
    file.path(study_root, paste0("phase1_", db))
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) cands[[1L]] else hit[[1L]]
}

cross_lagged_drop_exposure_meta <- function(vars,
                                           drop = c("FI", "Frailty", "ePWV", "Country", "Cohort",
                                                    "ID", "Disease_Group", "Disease")) {
  unique(setdiff(as.character(vars %||% character(0)), drop))
}

#' 从检查点 univar_coef 提取 p < alpha 的变量主干（去 FI）
cross_lagged_read_univar_sig_vars <- function(study_root, db, alpha = 0.05) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  base <- file.path(cross_lagged_phase1_dir(study_root, db), "checkpoints")
  cands <- c(
    file.path(base, "univariate_incidence_binary.rds"),
    file.path(base, "step05_univariate_incidence_binary.rds")
  )
  cands <- cands[file.exists(cands)]
  if (!length(cands)) return(character(0))
  ck <- readRDS(cands[[1L]])
  if (!is.null(ck$ctx)) ck <- ck$ctx
  df <- ck$results$univar_coef
  if (is.null(df) || !is.data.frame(df)) return(character(0))
  pcol <- names(df)[grepl("^p$|p\\.value|P$|P value", names(df), ignore.case = TRUE)][1]
  vcol <- names(df)[grepl("var|Variable|term|Feature", names(df), ignore.case = TRUE)][1]
  if (is.na(pcol) || is.na(vcol)) return(character(0))
  pv <- suppressWarnings(as.numeric(df[[pcol]]))
  vv <- as.character(df[[vcol]])
  hit <- vv[!is.na(pv) & pv < alpha]
  stem <- vapply(hit, function(x) {
    x <- as.character(x)
    for (pref in c("Gender", "Education", "Marital_Status", "Smoking",
                   "Alcohol_drinking", "Hypertension", "T2DM", "Cancer", "Race")) {
      if (startsWith(x, pref)) return(pref)
    }
    x
  }, character(1L), USE.NAMES = FALSE)
  unique(cross_lagged_drop_exposure_meta(stem))
}

#' ELSA∩HRS 共有协变量 → 三库强制同一 Model2（含 CHARLS）
cross_lagged_lock_elsa_hrs_common_force_all <- function(study_root,
                                                        model2_screen_list = NULL,
                                                        drop_vars = c("FI", "Frailty", "Country", "Cohort",
                                                                      "ID", "Disease_Group", "Disease"),
                                                        alpha = 0.05,
                                                        fallback = c("Age", "Gender", "Marital_Status",
                                                                     "Weight", "Height"),
                                                        prefer_age_only_model1 = TRUE) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  clean_one <- function(x) unique(setdiff(as.character(x %||% character(0)), drop_vars))

  elsa_uv <- cross_lagged_read_univar_sig_vars(study_root, "ELSA", alpha = alpha)
  hrs_uv  <- cross_lagged_read_univar_sig_vars(study_root, "HRS", alpha = alpha)
  inter_uv <- intersect(elsa_uv, hrs_uv)

  inter_screen <- character(0)
  if (!is.null(model2_screen_list)) {
    e_sc <- clean_one(model2_screen_list[["ELSA"]])
    h_sc <- clean_one(model2_screen_list[["HRS"]])
    inter_screen <- intersect(e_sc, h_sc)
  }

  source <- "elsa_hrs_uv_intersect"
  locked <- as.character(inter_uv)
  if (!length(locked)) {
    locked <- as.character(inter_screen)
    source <- "elsa_hrs_screen_intersect"
  }
  if (!length(locked)) {
    locked <- unique(as.character(fallback))
    source <- "elsa_hrs_fallback_preset"
  }
  if (!"Age" %in% locked) locked <- c("Age", locked)

  model1 <- if (isTRUE(prefer_age_only_model1) && "Age" %in% locked) {
    "Age"
  } else {
    intersect(locked, c("Age", "Gender", "Education", "Marital_Status"))
  }

  list(
    model1 = unique(as.character(model1)),
    model2 = unique(as.character(locked)),
    source = source,
    intersect_final = character(0),
    intersect_screen = unique(as.character(inter_screen)),
    elsa_uv = elsa_uv,
    hrs_uv = hrs_uv,
    elsa_hrs_uv_intersect = unique(as.character(inter_uv)),
    empty = !length(locked),
    apply_to = c("CHARLS", "ELSA", "HRS"),
    note = "CHARLS 使用 ELSA∩HRS 共有协变量（非 CHARLS 自身 UV 交集）"
  )
}

#' 参与协变量锁定的队列（默认 meta$cohorts_covariate_lock → cohorts_xs）
cross_lagged_covariate_lock_cohorts <- function(meta) {
  as.character(meta$cohorts_covariate_lock %||% meta$cohorts_xs %||% c("CHARLS", "ELSA", "HRS"))
}

#' Pooled 绑库队列（默认 meta$cohorts_pooled → lock cohorts）
cross_lagged_pooled_cohorts <- function(meta) {
  as.character(meta$cohorts_pooled %||% meta$cohorts_covariate_lock %||% meta$cohorts_xs %||%
                 c("CHARLS", "ELSA", "HRS"))
}

#' 正文横断面队列（post_vif / relock；默认 meta$cohorts_main → lock cohorts）
cross_lagged_main_cohorts <- function(meta) {
  as.character(meta$cohorts_main %||% meta$cohorts_covariate_lock %||% meta$cohorts_xs %||%
                 c("CHARLS", "ELSA", "HRS"))
}

#' 外部验证队列（仅敏感性；如 NHANES 横断面）
cross_lagged_validation_cohorts <- function(meta) {
  as.character(meta$cohorts_validation %||% character(0))
}

.cross_lagged_subset_cohort_lists <- function(lst, keep) {
  if (is.null(lst) || !length(lst)) return(lst)
  keep <- as.character(keep)
  lst[intersect(names(lst), keep)]
}

#' 各库多因素显著变量 tb2（P < multivariate sig_cutoff），不是 VIF screen 全名单
cross_lagged_read_mv_sig_lists <- function(study_root, cohorts) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  out <- list()
  for (db in as.character(cohorts)) {
    base <- cross_lagged_phase1_dir(study_root, db)
    v <- character(0)
    ck_dir <- file.path(base, "checkpoints")
    if (dir.exists(ck_dir)) {
      cands <- list.files(ck_dir, pattern = "multivariate_incidence_binary\\.rds$", full.names = TRUE)
      if (length(cands)) {
        cands <- cands[order(file.info(cands)$mtime, decreasing = TRUE)]
        ck <- tryCatch(readRDS(cands[[1L]]), error = function(e) NULL)
        if (!is.null(ck$ctx)) ck <- ck$ctx
        v <- as.character(ck$results$tb2 %||% ck$results$multivar_features %||% character(0))
      }
    }
    if (!length(v)) {
      steps <- list.dirs(base, recursive = FALSE, full.names = TRUE)
      hit <- steps[grepl("multivariate_incidence", basename(steps), ignore.case = TRUE)]
      for (d in hit) {
        p <- file.path(d, "D05_Multivariable_Features.RData")
        if (!file.exists(p)) next
        e <- new.env(parent = emptyenv())
        load(p, envir = e)
        for (nm in ls(e)) {
          obj <- e[[nm]]
          if (is.character(obj) && length(obj)) {
            v <- unique(as.character(obj))
            break
          }
        }
        if (length(v)) break
      }
    }
    out[[db]] <- unique(v[nzchar(v)])
  }
  out
}

#' Model2 = 各库 tb2 交集。空集不回退 VIF screen / ELSA∩HRS。
cross_lagged_lock_mv_sig_intersect <- function(mv_list,
                                              drop_vars = c("FI", "Frailty", "ePWV", "Leisure_score",
                                                            "Country", "Cohort", "ID",
                                                            "Disease_Group", "Disease"),
                                              index_var = "",
                                              demo_for_model1 = c("Age", "Gender", "Sex",
                                                                  "Education", "Marital_Status"),
                                              prefer_age_only_model1 = TRUE,
                                              study_root = NULL,
                                              lock_cohorts = NULL) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  drop_vars <- unique(c(drop_vars, as.character(index_var)[nzchar(as.character(index_var))]))
  if (!is.null(lock_cohorts) && length(lock_cohorts)) {
    mv_list <- .cross_lagged_subset_cohort_lists(mv_list, lock_cohorts)
  }
  if (is.null(mv_list) || !length(mv_list)) {
    stop("mv_sig_intersect: 没有读到任何库的多因素显著变量（tb2）", call. = FALSE)
  }
  clean <- lapply(mv_list, function(x) {
    unique(setdiff(as.character(x %||% character(0)), drop_vars))
  })
  locked <- Reduce(intersect, clean)
  if (is.null(locked)) locked <- character(0)
  locked <- unique(as.character(locked))
  model1 <- intersect(locked, demo_for_model1)
  if (isTRUE(prefer_age_only_model1) && "Age" %in% locked) {
    model1 <- "Age"
  }
  list(
    model1 = unique(as.character(model1)),
    model2 = locked,
    source = "mv_sig_intersect",
    lock_cohort_n = length(clean),
    intersect_final = locked,
    intersect_screen = character(0),
    empty = !length(locked),
    by_db_final = clean,
    by_db_screen = list(),
    by_db_mv_sig = clean
  )
}

#' 读取锁定协变量（按 meta$cohorts_covariate_lock；可选 meta$model1_locked 覆盖 Model1）
cross_lagged_resolve_covariate_lock <- function(study_root, meta = NULL) {
  if (is.null(meta)) {
    if (!exists("cross_lagged_study_meta", mode = "function"))
      stop("cross_lagged_resolve_covariate_lock: 需要 cross_lagged_study_meta", call. = FALSE)
    meta <- cross_lagged_study_meta(study_root)
  }
  cohorts <- cross_lagged_covariate_lock_cohorts(meta)
  rule <- as.character(meta$covariate_lock_rule %||% "vif_screen")[1L]
  if (identical(rule, "mv_sig_intersect")) {
    mv_list <- cross_lagged_read_mv_sig_lists(study_root, cohorts)
    lock <- cross_lagged_lock_mv_sig_intersect(
      mv_list,
      study_root = study_root,
      lock_cohorts = cohorts,
      index_var = as.character(meta$index_var %||% "")[1L]
    )
    lock$lock_cohorts <- cohorts
    lock$pooled_cohorts <- cross_lagged_pooled_cohorts(meta)
    lock$validation_cohorts <- cross_lagged_validation_cohorts(meta)
    lock$main_cohorts <- cross_lagged_main_cohorts(meta)
    return(lock)
  }
  m2_pack <- cross_lagged_read_cohort_model2_lists(study_root, cohorts)
  lock <- cross_lagged_lock_covariates_across_dbs(
    m2_pack$final, m2_pack$screen,
    study_root = study_root,
    lock_cohorts = cohorts,
    force_elsa_hrs_common = FALSE
  )
  m1_override <- as.character(meta$model1_locked %||% character(0))
  m1_override <- m1_override[nzchar(m1_override)]
  if (length(m1_override)) lock$model1 <- unique(m1_override)
  lock$lock_cohorts <- cohorts
  lock$pooled_cohorts <- cross_lagged_pooled_cohorts(meta)
  lock$validation_cohorts <- cross_lagged_validation_cohorts(meta)
  lock$main_cohorts <- cross_lagged_main_cohorts(meta)
  lock
}

#' 开发队列 Model2 锁定（默认三库；可传 lock_cohorts 仅 CHARLS+ELSA 等）
cross_lagged_lock_covariates_across_dbs <- function(model2_final_list,
                                                   model2_screen_list = NULL,
                                                   drop_vars = c("FI", "Frailty", "Country", "Cohort",
                                                                "ID", "Disease_Group", "Disease"),
                                                   demo_for_model1 = c("Age", "Gender", "Sex",
                                                                      "Education", "Marital_Status"),
                                                   prefer_age_only_model1 = TRUE,
                                                   study_root = NULL,
                                                   force_elsa_hrs_common = FALSE,
                                                   lock_cohorts = NULL) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  if (isTRUE(force_elsa_hrs_common) && !is.null(study_root) && nzchar(study_root)) {
    return(cross_lagged_lock_elsa_hrs_common_force_all(
      study_root = study_root,
      model2_screen_list = model2_screen_list,
      drop_vars = drop_vars,
      prefer_age_only_model1 = prefer_age_only_model1
    ))
  }

  clean_one <- function(x) unique(setdiff(as.character(x %||% character(0)), drop_vars))

  if (!is.null(lock_cohorts) && length(lock_cohorts)) {
    keep <- as.character(lock_cohorts)
    model2_final_list <- .cross_lagged_subset_cohort_lists(model2_final_list, keep)
    model2_screen_list <- .cross_lagged_subset_cohort_lists(model2_screen_list, keep)
  }

  if (is.null(model2_final_list) || !length(model2_final_list)) {
    stop("cross_lagged_lock_covariates_across_dbs: model2_final_list 为空", call. = FALSE)
  }
  final_clean <- lapply(model2_final_list, clean_one)
  inter_final <- Reduce(intersect, final_clean)
  if (is.null(inter_final)) inter_final <- character(0)

  inter_screen <- character(0)
  if (!is.null(model2_screen_list) && length(model2_screen_list)) {
    screen_clean <- lapply(model2_screen_list, clean_one)
    inter_screen <- Reduce(intersect, screen_clean)
    if (is.null(inter_screen)) inter_screen <- character(0)
  } else {
    screen_clean <- list()
  }

  # 以 VIF screen（Table S4 / VIF_screen_pass）交集为主锁定；
  # final 仅在 screen 交集为空时回退。
  n_lock <- length(final_clean)
  source <- "vif_screen"
  locked <- as.character(inter_screen)
  if (!length(locked)) {
    locked <- as.character(inter_final)
    source <- "vif_final_fallback"
  }

  empty <- !length(locked)
  if (empty && !is.null(study_root) && nzchar(as.character(study_root)[1L])) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "开发队列 VIF 交集为空 → 启用 ELSA∩HRS 共有协变量强制套库（含 CHARLS）"
      )
    }
    return(cross_lagged_lock_elsa_hrs_common_force_all(
      study_root = study_root,
      model2_screen_list = model2_screen_list,
      drop_vars = drop_vars,
      prefer_age_only_model1 = prefer_age_only_model1
    ))
  }

  if (empty) {
    warning(
      "cross_lagged_lock: VIF screen 与 VIF final 开发队列交集均为空；无法自动锁定协变量。",
      call. = FALSE
    )
    source <- "empty"
  }

  model1 <- intersect(locked, demo_for_model1)
  if (isTRUE(prefer_age_only_model1) && "Age" %in% locked) {
    model1 <- "Age"
  } else if (!length(model1) && "Gender" %in% locked) {
    model1 <- intersect(c("Gender", "Education"), locked)
  }

  list(
    model1 = unique(as.character(model1)),
    model2 = unique(as.character(locked)),
    source = source,
    lock_cohort_n = n_lock,
    intersect_final = unique(as.character(inter_final)),
    intersect_screen = unique(as.character(inter_screen)),
    empty = empty,
    by_db_final = final_clean,
    by_db_screen = if (length(screen_clean)) screen_clean else list()
  )
}

#' 从 phase1_* 检查点/step 目录读取各库 final / screen Model2
#' 关键：screen 优先读 VIF_screen_pass（与 Table S4 一致），勿用强制掺入 Gender 的 Model2Factors。
cross_lagged_read_cohort_model2_lists <- function(study_root,
                                                 cohorts = c("CHARLS", "ELSA", "HRS")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  load_chars <- function(path) {
    if (!file.exists(path)) return(character(0))
    if (grepl("\\.txt$", path, ignore.case = TRUE)) {
      v <- trimws(readLines(path, warn = FALSE))
      v <- v[nzchar(v) & !grepl("^#", v)]
      return(unique(as.character(v)))
    }
    if (grepl("\\.csv$", path, ignore.case = TRUE)) {
      d <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(d) || !nrow(d)) return(character(0))
      vcol <- names(d)[grepl("Variable|var|term", names(d), ignore.case = TRUE)][1]
      if (is.na(vcol)) vcol <- names(d)[[1]]
      map_one <- function(x) {
        x0 <- trimws(as.character(x))
        if (!nzchar(x0) || grepl("^Variable", x0, ignore.case = TRUE)) return(NA_character_)
        if (grepl("^FI$|Frailty", x0, ignore.case = TRUE)) return("FI")
        if (grepl("^Age$", x0, ignore.case = TRUE)) return("Age")
        if (grepl("^Gender|^Sex$", x0, ignore.case = TRUE)) return("Gender")
        if (grepl("Alcohol", x0, ignore.case = TRUE)) return("Alcohol_drinking")
        if (grepl("Marital", x0, ignore.case = TRUE)) return("Marital_Status")
        if (grepl("Educat", x0, ignore.case = TRUE)) return("Education")
        if (grepl("^BMI", x0, ignore.case = TRUE)) return("BMI")
        if (grepl("^Weight", x0, ignore.case = TRUE)) return("Weight")
        if (grepl("^Height", x0, ignore.case = TRUE)) return("Height")
        if (grepl("HbA1c|Glycated", x0, ignore.case = TRUE)) return("HbA1c")
        if (grepl("Smok", x0, ignore.case = TRUE)) return("Smoking")
        gsub(" ", "_", x0, fixed = TRUE)
      }
      out <- unique(stats::na.omit(vapply(d[[vcol]], map_one, character(1L))))
      return(as.character(out))
    }
    e <- new.env(parent = emptyenv())
    load(path, envir = e)
    for (nm in ls(e)) {
      obj <- e[[nm]]
      if (is.character(obj)) return(unique(obj[nzchar(obj)]))
    }
    character(0)
  }
  find_in_step <- function(db, step_pat, file_names) {
    base <- cross_lagged_phase1_dir(study_root, db)
    steps <- list.dirs(base, recursive = FALSE, full.names = TRUE)
    hit <- steps[grepl(step_pat, basename(steps), ignore.case = TRUE)]
    for (d in hit) {
      for (fn in file_names) {
        p <- file.path(d, fn)
        v <- load_chars(p)
        if (length(v)) return(v)
      }
    }
    ck_dir <- file.path(base, "checkpoints")
    cands <- list.files(ck_dir, pattern = paste0(step_pat, "\\.rds$"), full.names = TRUE)
    if (!length(cands)) cands <- list.files(ck_dir, pattern = "\\.rds$", full.names = TRUE)
    cands <- cands[grepl(step_pat, basename(cands), ignore.case = TRUE)]
    if (length(cands)) {
      ck <- readRDS(cands[[1]])
      if (!is.null(ck$ctx)) ck <- ck$ctx
      # screen 优先 VIF pass 结果
      v <- ck$results$vif_screen_pass %||% ck$results$VIF_screen_pass %||%
        ck$results$Model2Factors %||% character(0)
      if (length(v)) return(as.character(v))
    }
    character(0)
  }

  final_list <- list()
  screen_list <- list()
  for (db in cohorts) {
    # screen：与 Table S4 对齐（VIF_screen_pass / VIF csv），严禁优先 Model2Factors（可能 force 进 Gender）
    screen_list[[db]] <- find_in_step(
      db, "multicollinearity_screen",
      c("VIF_screen_pass.txt", "VIF_screen_pass.RData",
        "VIF_check_screen.csv", "Model2Factors.RData", "Model2Factors.txt")
    )
    # final：Model2 输出；若 VIF_final csv 更完整可补充
    final_list[[db]] <- find_in_step(
      db, "multicollinearity_final",
      c("Model2Factors.RData", "Model2Factors.txt",
        "VIF_check_final.csv")
    )
    if (!length(screen_list[[db]])) {
      uv <- file.path(cross_lagged_phase1_dir(study_root, db),
                      "step06_univariate_incidence_binary",
                      "D06b_Univariable_Screen_Features.RData")
      screen_list[[db]] <- load_chars(uv)
    }
  }
  list(final = final_list, screen = screen_list)
}

cross_lagged_format_lock_report <- function(lock) {
  c(
    paste0("lock_cohorts=", paste(lock$lock_cohorts %||% character(0), collapse = ", ")),
    paste0("lock_source=", lock$source %||% "unknown"),
    paste0("intersect_final=", paste(lock$intersect_final %||% character(0), collapse = ", ")),
    paste0("intersect_screen=", paste(lock$intersect_screen %||% character(0), collapse = ", ")),
    paste0("elsa_hrs_uv_intersect=", paste(lock$elsa_hrs_uv_intersect %||% character(0), collapse = ", ")),
    paste0("Model1=", paste(lock$model1 %||% character(0), collapse = ", ")),
    paste0("Model2=", paste(lock$model2 %||% character(0), collapse = ", ")),
    if (identical(as.character(lock$source %||% "")[1L], "mv_sig_intersect")) {
      "rule=开发队列多因素显著变量交集（tb2）；不回退 VIF screen；验证队列不参与锁定、直接套用"
    } else {
      "rule=开发队列 TableS4/VIF_screen 交集；若空再 final 交集；验证队列不参与锁定、直接套用"
    }
  )
}
