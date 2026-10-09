###############################################################################
#  incidence_sensitivity_suite.R — 主分析成功后的敏感性分析重跑
#
#  触发：批量主流程跑完后，对每个 success 指标，从两库 Table 1 动态发现
#        Yes/No 场景 + 年龄分层（规格默认）；未插补完整病例仅当
#        sensitivity_suite$complete_case 显式 TRUE 才生成。
#        Yes/No 与年龄在主分析插补后 checkpoint 上删人。
#        只重跑 Table 1 / Table 2；成功须两库最高分位 Crude 均显著
#        （complete_case 不另强制 Model2；其余场景另须两库 Model2 显著）。
#
#  默认：sensitivity_suite$enable 缺省/NULL → TRUE（须显式 FALSE 才关）。
#
#  机制：
#    1. scenarios_for_index：categorical_vars + imputed（Yes/No、年龄）；
#       complete_case 读 mapped/cleaned（sensitivity_suite$complete_case，默认 FALSE）
#    2. 拷主分析 index_ck_base/ix/<db> → 敏感性 ck，滤人，删单水平协变量
#    3. 临时 config 注入 .sensitivity_light（Task 6 worker 挂钩）
#    4. 派发 worker；敏感性表号接主 Tables 最大 S 号顺延（基线=max+1，关联=max+2）；
#       成功闸门：两库最高分位 Crude 均显著；非 complete_case 另要求两库 Model2 主对比显著
#       无主附表时兜底 S12/S13（历史默认）
#
#  依赖：utils.R, incidence_dual_batch_runner.R, incidence_subgroup_fallback.R
###############################################################################

#' 敏感性是否开启：缺省/NULL → TRUE；仅显式 FALSE 关闭
incidence_sensitivity_suite_enabled <- function(config = NULL) {
  sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
  if (!length(sens) || is.null(sens$enable)) {
    sens <- (config$survival_batch %||% list())$sensitivity_suite %||% list()
  }
  if (!length(sens) || is.null(sens$enable)) return(TRUE)
  !isFALSE(sens$enable)
}

#' 单库 NHANES/KNHANES：物化 by_index/【success】<ix> + 敏感性所需轻量 checkpoint
#'
#' 不拷贝整份平铺 ck（可数十 GB）；只镜像 imputation/index 等必需 rds。
incidence_materialize_nhanes_success_index <- function(config, pipeline = NULL,
                                                       study_root = NULL,
                                                       config_path = NULL) {
  ix <- as.character(
    (config$incidence %||% list())$index_var %||%
      (config$index %||% list())$only %||% "INDEX"
  )[1L]
  out_base <- as.character(
    (config$incidence_batch %||% list())$output_base %||%
      study_root %||%
      (config$project %||% list())$output_dir %||%
      (config$project %||% list())$root %||%
      getwd()
  )[1L]
  if (!nzchar(ix) || !nzchar(out_base) || !dir.exists(out_base)) {
    stop("incidence_materialize_nhanes_success_index: 缺 index_var 或 output_base", call. = FALSE)
  }
  ck_flat <- as.character((pipeline$checkpoint %||% list())$dir %||% "")[1L]
  if (!nzchar(ck_flat)) {
    db_tag <- toupper(as.character(
      (config$project %||% list())$database %||%
        (config$project %||% list())$database_type %||% "KNHANES"
    )[1L])
    ck_flat <- file.path(out_base, "checkpoints", paste0(ix, "_", db_tag))
  }
  db_slot <- "nhanes"
  ix_ck <- file.path(out_base, "checkpoints", "_by_index", ix, db_slot)
  dir.create(ix_ck, recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(ck_flat)) {
    want <- c(
      "imputation.rds", "index.rds",
      "step05_imputation.rds", "step03_index.rds"
    )
    for (bn in want) {
      src <- file.path(ck_flat, bn)
      if (file.exists(src)) {
        file.copy(src, file.path(ix_ck, bn), overwrite = TRUE)
      }
    }
    # 兜底：若无 imputation.rds 别名，从 step05 复制
    if (!file.exists(file.path(ix_ck, "imputation.rds"))) {
      alt <- file.path(ck_flat, "step05_imputation.rds")
      if (file.exists(alt)) {
        file.copy(alt, file.path(ix_ck, "imputation.rds"), overwrite = TRUE)
        file.copy(alt, file.path(ix_ck, "index.rds"), overwrite = TRUE)
      }
    }
    if (!file.exists(file.path(ix_ck, "index.rds")) &&
        file.exists(file.path(ix_ck, "imputation.rds"))) {
      file.copy(
        file.path(ix_ck, "imputation.rds"),
        file.path(ix_ck, "index.rds"),
        overwrite = TRUE
      )
    }
  }

  success_dir <- file.path(out_base, "by_index", paste0("\u3010success\u3011", ix))
  dir.create(success_dir, recursive = TRUE, showWarnings = FALSE)
  for (sub in c("Tables", "Figures", "code")) {
    src <- file.path(out_base, sub)
    dst <- file.path(success_dir, sub)
    if (dir.exists(src)) {
      if (dir.exists(dst)) unlink(dst, recursive = TRUE)
      file.copy(src, success_dir, recursive = TRUE)
    }
  }

  db_disp <- "NHANES"
  if (exists("dual_db_slot_path_name", mode = "function")) {
    db_disp <- tryCatch(
      dual_db_slot_path_name(config, "nhanes"),
      error = function(e) {
        as.character((config$project %||% list())$database %||% "NHANES")[1L]
      }
    )
  } else {
    db_disp <- as.character((config$project %||% list())$database %||% "NHANES")[1L]
  }
  nh_dir <- file.path(success_dir, db_disp)
  dir.create(nh_dir, recursive = TRUE, showWarnings = FALSE)
  step_dirs <- list.files(
    out_base, pattern = "^step[0-9]+_baseline_", full.names = TRUE
  )
  for (sd in step_dirs) {
    file.copy(sd, nh_dir, recursive = TRUE, overwrite = TRUE)
  }
  for (fn in c("categorical_vars.txt", "continuous_vars.txt",
               "Model1Factors.txt", "Model2Factors.txt")) {
    hits <- list.files(out_base, pattern = paste0("^", fn, "$"),
                       recursive = TRUE, full.names = TRUE)
    hits <- hits[!grepl("sensitivity|by_index|\\.sensitivity", hits, ignore.case = TRUE)]
    if (!length(hits)) next
    # Model factors：优先 final / logistic 步
    if (grepl("^Model", fn)) {
      prefer <- grepl("multicollinearity_nhanes_final|logistic_quartile", hits)
      if (any(prefer)) hits <- c(hits[prefer], hits[!prefer])
    }
    file.copy(hits[[1L]], file.path(nh_dir, fn), overwrite = TRUE)
    file.copy(hits[[1L]], file.path(success_dir, "Tables", fn), overwrite = TRUE)
  }

  st_path <- file.path(success_dir, "_batch_status.json")
  writeLines(
    sprintf(
      paste0(
        '{"status":"success","index":"%s","database":"%s","db_slot":"%s",',
        '"config_path":"%s"}'
      ),
      ix, db_disp, db_slot,
      gsub("\\\\", "/", as.character(config_path %||% "")[1L])
    ),
    st_path
  )

  # 从 Table2 脚注 / Model*.txt 写锁定协变量，供敏感性 complete_case
  if (exists("incidence_sensitivity_load_main_covariates", mode = "function")) {
    mc <- tryCatch(
      incidence_sensitivity_load_main_covariates(success_dir, ix),
      error = function(e) list(m1 = character(0), m2 = character(0))
    )
    if (!length(mc$m1) && !length(mc$m2)) {
      mc <- tryCatch(
        incidence_sensitivity_load_main_covariates(out_base, ix),
        error = function(e) list(m1 = character(0), m2 = character(0))
      )
    }
    if (length(mc$m1) || length(mc$m2)) {
      utils::write.csv(
        data.frame(
          Model1 = paste(mc$m1, collapse = "|"),
          Model2 = paste(mc$m2, collapse = "|")
        ),
        file.path(success_dir, "Tables", "Model_factors_locked.csv"),
        row.names = FALSE
      )
    }
  }

  cli::cli_alert_success(
    "已物化 by_index/\u3010success\u3011{ix}（Tables/Figures + 轻量 ck）"
  )
  invisible(list(
    index = ix,
    success_dir = success_dir,
    index_ck = ix_ck,
    output_base = out_base
  ))
}

incidence_sensitivity_yes_tokens <- function() {
  c("Yes", "yes", "YES", "1", "TRUE", "True", "true", "Y", "y")
}

incidence_sensitivity_no_tokens <- function() {
  c("No", "no", "NO", "0", "FALSE", "False", "false", "N", "n")
}

incidence_sensitivity_as_yes_no_chr <- function(x) {
  xs <- trimws(as.character(x))
  yes <- incidence_sensitivity_yes_tokens()
  no  <- incidence_sensitivity_no_tokens()
  xs[xs %in% yes] <- "Yes"
  xs[xs %in% no]  <- "No"
  xs
}

incidence_sensitivity_is_yes_no <- function(x) {
  xs <- incidence_sensitivity_as_yes_no_chr(x)
  lv <- unique(xs[!is.na(xs) & nzchar(xs)])
  length(lv) >= 1L && length(lv) <= 2L && all(lv %in% c("Yes", "No"))
}

incidence_sensitivity_yes_n <- function(x) {
  xs <- incidence_sensitivity_as_yes_no_chr(x)
  as.integer(sum(xs == "Yes", na.rm = TRUE))
}

incidence_sensitivity_exclude_yes_expr <- function(var) {
  var <- as.character(var)[1L]
  sprintf(
    'is.na(%1$s) | trimws(as.character(%1$s)) != "Yes"',
    var
  )
}

.incidence_sensitivity_col_for_yesno <- function(df, v) {
  x <- df[[v]]
  if (exists("pipeline_normalize_yes_no_factors", mode = "function")) {
    sub <- df[, v, drop = FALSE]
    sub <- pipeline_normalize_yes_no_factors(sub)
    x <- sub[[v]]
  }
  incidence_sensitivity_as_yes_no_chr(x)
}

incidence_sensitivity_discover_yesno <- function(t1_vars_by_db, data_by_db, min_yes_n = 50L) {
  dbs <- intersect(names(t1_vars_by_db), names(data_by_db))
  # 单库（如仅 NHANES）也允许；双库时仍要求各库同时满足 Yes/No 与 min_yes_n
  if (!length(dbs)) return(list())
  common <- Reduce(intersect, lapply(t1_vars_by_db[dbs], as.character))
  min_yes_n <- as.integer(min_yes_n)[1L]
  out <- list()
  for (v in common) {
    ok <- TRUE
    for (db in dbs) {
      df <- data_by_db[[db]]
      if (!is.data.frame(df) || !v %in% names(df)) {
        ok <- FALSE
        break
      }
      col <- .incidence_sensitivity_col_for_yesno(df, v)
      if (!incidence_sensitivity_is_yes_no(col)) {
        ok <- FALSE
        break
      }
      if (incidence_sensitivity_yes_n(col) <= min_yes_n) {
        ok <- FALSE
        break
      }
    }
    if (!ok) next
    out[[length(out) + 1L]] <- list(
      label = paste0("SA_no_", v),
      expr = incidence_sensitivity_exclude_yes_expr(v),
      var = v,
      required_vars = v
    )
  }
  out
}

incidence_sensitivity_is_complete_case <- function(sg) {
  if (is.null(sg)) return(FALSE)
  if (isTRUE(sg$mode %in% c("complete_case", "unimputed"))) return(TRUE)
  lab <- as.character(sg$label %||% "")[1L]
  lab %in% c("SA_complete_case", "SA_unimputed_cc")
}

incidence_sensitivity_complete_case_vars <- function(config, ix, m1 = character(0),
                                                     m2 = character(0)) {
  st  <- (config %||% list())$survival %||% list()
  inc <- (config %||% list())$incidence %||% list()
  dat <- (config %||% list())$data %||% list()
  unique(as.character(c(
    ix,
    st$index_var, st$time_var, st$event_var,
    inc$index_var, inc$outcome_var,
    dat$outcome_column,
    m1, m2
  )))
}

incidence_sensitivity_complete_case_keep <- function(df, vars) {
  if (!is.data.frame(df) || !nrow(df)) return(logical(0))
  vars <- intersect(unique(as.character(vars %||% character(0))), names(df))
  if (!length(vars)) return(rep(TRUE, nrow(df)))
  sub <- df[, vars, drop = FALSE]
  for (v in vars) {
    if (is.numeric(sub[[v]])) {
      x <- suppressWarnings(as.numeric(sub[[v]]))
      x[!is.finite(x)] <- NA_real_
      sub[[v]] <- x
    } else {
      xs <- trimws(as.character(sub[[v]]))
      xs[!nzchar(xs) | xs %in% c("NA", "NaN")] <- NA_character_
      sub[[v]] <- xs
    }
  }
  stats::complete.cases(sub)
}

incidence_sensitivity_unimputed_df <- function(obj) {
  if (!is.list(obj) || !is.list(obj$ctx) || !is.list(obj$ctx$data)) return(NULL)
  obj$ctx$data$mapped %||% obj$ctx$data$cleaned
}

incidence_sensitivity_load_unimputed <- function(main_ck_base, ix, db_path_name) {
  dir <- file.path(main_ck_base, ix, db_path_name)
  nms <- c(
    "imputation.rds", "step05_imputation.rds",
    "analysis_exclusion.rds", "index.rds"
  )
  hits <- list.files(dir, pattern = "(imputation|analysis_exclusion|index)\\.rds$",
                     full.names = TRUE)
  paths <- unique(c(file.path(dir, nms), hits))
  paths <- paths[file.exists(paths)]
  for (p in paths) {
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    df <- incidence_sensitivity_unimputed_df(obj)
    if (is.data.frame(df) && nrow(df)) return(df)
  }
  NULL
}

incidence_sensitivity_complete_case_scenario <- function(config, ix, data_by_db,
                                                         m1, m2, min_n = 50L) {
  min_n <- as.integer(min_n)[1L]
  dbs <- names(data_by_db)
  if (!length(dbs)) return(list())
  cc_vars <- incidence_sensitivity_complete_case_vars(config, ix, m1, m2)
  for (db in dbs) {
    df <- data_by_db[[db]]
    if (!is.data.frame(df)) return(list())
    keep <- incidence_sensitivity_complete_case_keep(df, cc_vars)
    if (sum(keep) < min_n) return(list())
  }
  list(list(
    label = "SA_complete_case",
    expr = "",
    mode = "complete_case",
    required_vars = cc_vars
  ))
}

incidence_sensitivity_apply_complete_case <- function(obj, cc_vars) {
  if (is.null(obj) || is.null(obj$ctx) || is.null(obj$ctx$data)) return(obj)
  ctx <- obj$ctx
  ref <- incidence_sensitivity_unimputed_df(obj)
  if (!is.data.frame(ref) || !nrow(ref)) {
    stop("未插补完整病例：缺少 mapped/cleaned 数据", call. = FALSE)
  }
  keep <- incidence_sensitivity_complete_case_keep(ref, cc_vars)
  n_ref <- nrow(ref)
  for (slot in c("mapped", "cleaned", "raw", "imputed")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df)) next
    if (nrow(df) == n_ref) {
      ctx$data[[slot]] <- df[keep, , drop = FALSE]
    } else if (slot != "imputed") {
      k2 <- incidence_sensitivity_complete_case_keep(df, cc_vars)
      ctx$data[[slot]] <- df[k2, , drop = FALSE]
    }
  }
  # 下游读 imputed：写入未插补 listwise，禁止再用 MI 填补值
  src <- ctx$data$mapped %||% ctx$data$cleaned
  if (is.data.frame(src)) ctx$data$imputed <- src
  if (is.null(ctx$results)) ctx$results <- list()
  ctx$results$sensitivity_complete_case <- TRUE
  ctx$results$sensitivity_complete_case_n <- if (is.data.frame(src)) nrow(src) else NA_integer_
  ctx$results$mice_model <- NULL
  obj$ctx <- ctx
  obj
}

incidence_sensitivity_copy_unimputed_cc_ck <- function(src_dir, dest_dir, cc_vars) {
  src_dir <- as.character(src_dir)[1L]
  dest_dir <- as.character(dest_dir)[1L]
  if (!dir.exists(src_dir)) {
    stop("未插补完整病例需要主分析 checkpoint: ", src_dir, call. = FALSE)
  }
  rds_files <- list.files(src_dir, pattern = "\\.rds$", full.names = TRUE)
  if (!length(rds_files)) {
    stop("未插补完整病例需要主分析 checkpoint: ", src_dir, call. = FALSE)
  }
  block_keys <- vapply(rds_files, function(p) {
    nm <- tools::file_path_sans_ext(basename(p))
    nm <- sub("^step[0-9]+_", "", nm)
    sub("^[0-9]+_", "", nm)
  }, character(1))
  keep_blocks <- c(
    "data_clean", "column_mapping", "dual_db_column_harmonize",
    "index", "analysis_exclusion", "imputation"
  )
  pick <- NULL
  for (want in c("imputation", "analysis_exclusion", "index")) {
    hits <- rds_files[block_keys == want]
    if (!length(hits)) next
    obj <- tryCatch(readRDS(hits[[1L]]), error = function(e) NULL)
    if (is.data.frame(incidence_sensitivity_unimputed_df(obj))) {
      pick <- hits[[1L]]
      break
    }
  }
  if (is.null(pick)) {
    stop("未插补完整病例：主分析 ck 无 mapped/cleaned: ", src_dir, call. = FALSE)
  }
  obj <- incidence_sensitivity_apply_complete_case(readRDS(pick), cc_vars)
  if (dir.exists(dest_dir)) unlink(dest_dir, recursive = TRUE)
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  for (p in rds_files[block_keys %in% setdiff(keep_blocks, "imputation")]) {
    file.copy(p, file.path(dest_dir, basename(p)), overwrite = TRUE)
  }
  saveRDS(obj, file.path(dest_dir, "index.rds"))
  saveRDS(obj, file.path(dest_dir, "imputation.rds"))
  invisible(dest_dir)
}

incidence_sensitivity_age_scenarios <- function(age_cutoff, data_by_db, min_n = 50L,
                                                age_var = "Age") {
  age_cutoff <- as.integer(age_cutoff)[1L]
  min_n <- as.integer(min_n)[1L]
  dbs <- names(data_by_db)
  if (!length(dbs)) return(list())
  n_ge <- n_lt <- integer(0)
  for (db in dbs) {
    df <- data_by_db[[db]]
    if (!is.data.frame(df) || !age_var %in% names(df)) return(list())
    age <- suppressWarnings(as.numeric(df[[age_var]]))
    n_ge <- c(n_ge, sum(is.finite(age) & age >= age_cutoff))
    n_lt <- c(n_lt, sum(is.finite(age) & age < age_cutoff))
  }
  out <- list()
  if (all(n_ge >= min_n)) {
    out[[length(out) + 1L]] <- list(
      label = sprintf("SA_age_ge_%s", age_cutoff),
      expr = sprintf("as.numeric(%s) >= %s", age_var, age_cutoff),
      required_vars = age_var
    )
  }
  if (all(n_lt >= min_n)) {
    out[[length(out) + 1L]] <- list(
      label = sprintf("SA_age_lt_%s", age_cutoff),
      expr = sprintf("as.numeric(%s) < %s", age_var, age_cutoff),
      required_vars = age_var
    )
  }
  out
}

.incidence_sensitivity_table1_search_bases <- function(parent_dir, db_dir_name) {
  parent_dir <- as.character(parent_dir %||% "")[1L]
  db_dir_name <- as.character(db_dir_name %||% "")[1L]
  # 单库 NHANES/KNHANES：step*/categorical_vars 常在课题根，不在 by_index/【success】下
  study_root <- character(0)
  if (nzchar(parent_dir) && grepl("by_index", parent_dir, fixed = TRUE)) {
    up <- dirname(parent_dir)
    if (identical(basename(up), "by_index")) study_root <- dirname(up)
  }
  unique(c(
    if (nzchar(db_dir_name)) file.path(parent_dir, db_dir_name) else character(0),
    if (nzchar(db_dir_name)) file.path(parent_dir, tolower(db_dir_name)) else character(0),
    if (nzchar(db_dir_name)) file.path(parent_dir, toupper(db_dir_name)) else character(0),
    # 单库两阶段：Tables/step* 在指标根下，无 MIMIC 子目录
    parent_dir,
    study_root
  ))
}

.incidence_sensitivity_prefer_stage1_hits <- function(hits) {
  hits <- as.character(hits %||% character(0))
  hits <- hits[nzchar(hits)]
  if (!length(hits)) return(hits)
  hits <- hits[!grepl("sensitivity|\\.sensitivity_staging", hits, ignore.case = TRUE)]
  prefer <- grepl("baseline_binary|step0[0-9]_|step1[0-9]_", hits, ignore.case = TRUE) &
    !grepl("step2[0-9]_", hits, ignore.case = TRUE)
  if (any(prefer)) hits <- c(hits[prefer], hits[!prefer])
  hits
}

incidence_sensitivity_read_table1_vars <- function(parent_dir, db_dir_name) {
  for (base in .incidence_sensitivity_table1_search_bases(parent_dir, db_dir_name)) {
    if (!nzchar(base) || !dir.exists(base)) next
    hits <- list.files(
      base, pattern = "^categorical_vars\\.txt$",
      recursive = TRUE, full.names = TRUE
    )
    hits <- .incidence_sensitivity_prefer_stage1_hits(hits)
    if (length(hits)) {
      return(unique(trimws(readLines(hits[[1L]], warn = FALSE))))
    }
  }
  character(0)
}

incidence_sensitivity_read_table1_analysis_vars <- function(parent_dir, db_dir_name) {
  out <- character(0)
  for (base in .incidence_sensitivity_table1_search_bases(parent_dir, db_dir_name)) {
    if (!nzchar(base) || !dir.exists(base)) next
    for (pat in c("^categorical_vars\\.txt$", "^continuous_vars\\.txt$")) {
      hits <- list.files(base, pattern = pat, recursive = TRUE, full.names = TRUE)
      hits <- .incidence_sensitivity_prefer_stage1_hits(hits)
      if (!length(hits)) next
      ln <- trimws(readLines(hits[[1L]], warn = FALSE))
      out <- c(out, ln[nzchar(ln)])
    }
    if (length(out)) break
  }
  unique(out)
}

incidence_sensitivity_zh_var_map <- function() {
  c(
    Hypertension = "高血压", T2DM = "糖尿病", Diabetes = "糖尿病",
    CKD = "CKD", Heart_Failure = "心衰", COPD = "COPD",
    Cancer = "癌症", Pneumonia = "肺炎", Stroke = "卒中"
  )
}

incidence_sensitivity_zh_desc <- function(label, age_cutoff = 65, display_names = NULL) {
  label <- as.character(label)[1L]
  m <- regexec("^SA_age_ge_([0-9]+)$", label, perl = TRUE)
  mm <- regmatches(label, m)[[1L]]
  if (length(mm)) return(paste0("年龄≥", mm[2L]))
  m <- regexec("^SA_age_lt_([0-9]+)$", label, perl = TRUE)
  mm <- regmatches(label, m)[[1L]]
  if (length(mm)) return(paste0("年龄<", mm[2L]))
  if (identical(label, "SA_complete_case") || identical(label, "SA_unimputed_cc")) {
    return("complete case unimputed")
  }
  if (startsWith(label, "SA_no_")) {
    var <- sub("^SA_no_", "", label)
    dn <- as.character((display_names %||% list())[[var]] %||% "")[1L]
    mp <- incidence_sensitivity_zh_var_map()
    zh <- if (nzchar(dn)) dn else (unname(mp[var]) %||% var)
    return(paste0("非", zh))
  }
  label
}

incidence_sensitivity_strip_existing_sa_caption <- function(cap) {
  cap <- as.character(cap %||% "")[1L]
  cap <- sub("(?i)^Sensitivity analysis-[^.]+\\.\\s*", "", cap, perl = TRUE)
  cap <- sub("(?i)^SA-[^.]+\\.\\s*", "", cap, perl = TRUE)
  repeat {
    nxt <- sub("(?i)^Sensitivity analysis[:\\-.]\\s*", "", cap, perl = TRUE)
    if (identical(nxt, cap)) break
    cap <- nxt
  }
  trimws(cap)
}

#' 敏感性文件名用短标签（去 SA_ 前缀，最长 28）；避免 Windows MAX_PATH
incidence_sensitivity_pub_label_short <- function(zh_desc = NULL, label = NULL) {
  lab <- as.character(label %||% "")[1L]
  if (nzchar(lab)) {
    short <- sub("^SA_", "", lab)
  } else {
    short <- as.character(zh_desc %||% "SA")[1L]
    short <- gsub("[[:space:]]+", "_", short)
  }
  short <- gsub("[\\\\/:*?\"<>|]+", "_", short)
  if (!nzchar(short)) short <- "SA"
  if (nchar(short, type = "chars") > 28L) {
    short <- substr(short, 1L, 28L)
  }
  short
}

#' 敏感性文件名短 caption：Baseline / Association（不带疾病长名）
incidence_sensitivity_pub_cap_short <- function(caption = NULL,
                                                study_type = "incidence",
                                                role = NULL) {
  role <- as.character(role %||% "")[1L]
  if (!nzchar(role)) {
    cap0 <- as.character(caption %||% "")[1L]
    role <- if (grepl("Baseline", cap0, ignore.case = TRUE)) "baseline" else "association"
  }
  if (identical(role, "baseline")) return("Baseline")
  "Association"
}

#' 敏感性发表文件名（短）：Table S{n}-{DB}. SA-{label}. Baseline|Association
incidence_sensitivity_pub_stem <- function(s_num, db_tag, zh_desc, caption,
                                           label = NULL, role = NULL,
                                           study_type = "incidence") {
  s_num <- as.integer(s_num)[1L]
  db_tag <- as.character(db_tag %||% "")[1L]
  db_part <- if (nzchar(db_tag)) paste0("-", db_tag) else ""
  short_lab <- incidence_sensitivity_pub_label_short(zh_desc, label)
  short_cap <- incidence_sensitivity_pub_cap_short(caption, study_type, role)
  sprintf("Table S%d%s. SA-%s. %s", s_num, db_part, short_lab, short_cap)
}

#' 敏感性表内标题（可读长名，不进路径）
incidence_sensitivity_pub_title <- function(s_num, db_tag, zh_desc, caption) {
  s_num <- as.integer(s_num)[1L]
  db_tag <- as.character(db_tag %||% "")[1L]
  zh_desc <- as.character(zh_desc %||% "")[1L]
  caption <- as.character(caption %||% "")[1L]
  db_part <- if (nzchar(db_tag)) paste0("-", db_tag) else ""
  sprintf(
    "Table S%d%s. Sensitivity analysis-%s. %s",
    s_num, db_part, zh_desc, caption
  )
}

incidence_sensitivity_db_tag_from_name <- function(bn) {
  bn <- as.character(bn %||% "")[1L]
  m <- regexec("(?i)Table\\s+S?[0-9]+-([A-Za-z][A-Za-z0-9]*)\\.", bn, perl = TRUE)
  mm <- regmatches(bn, m)[[1L]]
  if (length(mm) >= 2L) return(mm[[2L]])
  ""
}

#' 主分析 by_index/<ix>/Tables 中最大附表号 Table S#（找不到返回 NA）
incidence_sensitivity_main_max_supp_num <- function(parent_dir) {
  parent_dir <- as.character(parent_dir %||% "")[1L]
  if (!nzchar(parent_dir) || !dir.exists(parent_dir)) return(NA_integer_)
  td <- file.path(parent_dir, "Tables")
  if (!dir.exists(td)) return(NA_integer_)
  bns <- list.files(td, pattern = "\\.(xlsx|csv|tex)$", ignore.case = TRUE)
  if (!length(bns)) return(NA_integer_)
  nums <- vapply(bns, function(bn) {
    m <- regexec("^Table\\s+S([0-9]+)(?:-|[.]|$)", bn, perl = TRUE, ignore.case = TRUE)
    mm <- regmatches(bn, m)[[1L]]
    if (length(mm) >= 2L) as.integer(mm[2L]) else NA_integer_
  }, integer(1L))
  nums <- nums[is.finite(nums)]
  if (!length(nums)) return(NA_integer_)
  as.integer(max(nums))
}

#' 敏感性发表表号：基线 = 主附表 max+1，关联/Cox = max+2；无主附表时兜底 12/13
incidence_sensitivity_resolve_pub_s_nums <- function(parent_dir = NULL,
                                                     s_baseline = NULL,
                                                     s_association = NULL) {
  sb <- suppressWarnings(as.integer(s_baseline)[1L])
  sa <- suppressWarnings(as.integer(s_association)[1L])
  if (is.finite(sb) && sb >= 1L && is.finite(sa) && sa >= 1L) {
    return(list(baseline = sb, association = sa))
  }
  mx <- suppressWarnings(as.integer(
    incidence_sensitivity_main_max_supp_num(parent_dir)
  )[1L])
  if (!is.finite(mx) || mx < 0L) mx <- 11L
  list(baseline = mx + 1L, association = mx + 2L)
}

incidence_sensitivity_judge_status <- function(ok_t1, ok_t2, p_primary, p_secondary,
                                               sig_cutoff = 0.05,
                                               require_sig = TRUE,
                                               p_crude_primary = NA_real_,
                                               p_crude_secondary = NA_real_,
                                               require_crude_highest_sig = TRUE) {
  tables_ok <- isTRUE(ok_t1) && isTRUE(ok_t2)
  if (!tables_ok) return("failed")
  # 最高分位 Crude：任一库不显著（或缺失）→ failed（含 complete_case）
  if (isTRUE(require_crude_highest_sig)) {
    pc1 <- suppressWarnings(as.numeric(p_crude_primary)[1L])
    pc2 <- suppressWarnings(as.numeric(p_crude_secondary)[1L])
    crude_ok <- is.finite(pc1) && is.finite(pc2) &&
      pc1 < sig_cutoff && pc2 < sig_cutoff
    if (!crude_ok) return("failed")
  }
  p1 <- suppressWarnings(as.numeric(p_primary)[1L])
  p2 <- suppressWarnings(as.numeric(p_secondary)[1L])
  sig_ok <- is.finite(p1) && is.finite(p2) &&
    p1 < sig_cutoff && p2 < sig_cutoff
  if (!isTRUE(require_sig) || sig_ok) "success" else "failed"
}

# ── 展开 sensitivity_suite$scenarios（Task 2 前暂返回空 list）────────────────
incidence_sensitivity_resolve <- function(config) {
  list()
}

# ── 复制主分析 imputed checkpoint，剥掉 baseline 及之后块（Task 3）────────────
.incidence_sensitivity_ck_has_imputed <- function(obj) {
  is.list(obj) && is.list(obj$ctx) && is.list(obj$ctx$data) &&
    !is.null(obj$ctx$data$imputed)
}

.incidence_sensitivity_dir_has_imputed <- function(dir) {
  dir <- as.character(dir %||% "")[1L]
  if (!nzchar(dir) || !dir.exists(dir)) return(FALSE)
  rds <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
  if (!length(rds)) return(FALSE)
  keys <- vapply(rds, function(p) {
    nm <- tools::file_path_sans_ext(basename(p))
    nm <- sub("^step[0-9]+_", "", nm)
    sub("^[0-9]+_", "", nm)
  }, character(1))
  for (want in c("imputation", "index")) {
    hits <- rds[keys == want]
    if (!length(hits)) next
    obj <- tryCatch(readRDS(hits[[1L]]), error = function(e) NULL)
    if (.incidence_sensitivity_ck_has_imputed(obj)) return(TRUE)
  }
  FALSE
}

#' 两阶段等：per-index 在 Stage2 后可能丢掉 imputed；回退到 checkpoints/_shared
.incidence_sensitivity_resolve_imputed_src <- function(main_ck_base, ix, db) {
  db <- as.character(db %||% "")[1L]
  per_cands <- unique(c(
    file.path(main_ck_base, ix, db),
    file.path(main_ck_base, ix, tolower(db)),
    file.path(main_ck_base, ix, toupper(db)),
    # 单库入口常镜像为内部槽位名 nhanes
    file.path(main_ck_base, ix, "nhanes"),
    file.path(main_ck_base, ix, "NHANES"),
    file.path(main_ck_base, ix, "knhanes"),
    file.path(main_ck_base, ix, "KNHANES")
  ))
  for (per in per_cands) {
    if (.incidence_sensitivity_dir_has_imputed(per)) {
      return(list(dir = per, from_shared = FALSE))
    }
  }
  ck_root <- dirname(as.character(main_ck_base)[1L])
  cands <- unique(c(
    file.path(ck_root, "_shared", db),
    file.path(ck_root, "_shared", tolower(db)),
    file.path(ck_root, "_shared", toupper(db)),
    file.path(ck_root, "_shared", "nhanes"),
    file.path(ck_root, "_shared", "NHANES"),
    file.path(ck_root, "_shared", "mimic"),
    file.path(ck_root, "_shared", "MIMIC"),
    file.path(ck_root, "_shared")
  ))
  for (d in cands) {
    if (.incidence_sensitivity_dir_has_imputed(d)) {
      return(list(dir = d, from_shared = TRUE))
    }
  }
  list(dir = per_cands[[1L]], from_shared = FALSE)
}

# 保留旧入口名（config/config_path 可选，忽略）
.incidence_sensitivity_shared_ck_for_db <- function(config, config_path, db) {
  bc <- utils::modifyList(
    config$incidence_batch %||% list(),
    config$ip_two_stage_batch %||% list()
  )
  shared_base <- .incidence_sensitivity_abs_ck(
    bc$shared_ck_base %||% "checkpoints/_shared", config_path
  )
  db <- as.character(db %||% "")[1L]
  cands <- unique(c(
    file.path(shared_base, db),
    file.path(shared_base, tolower(db)),
    file.path(shared_base, toupper(db)),
    file.path(shared_base, "mimic"),
    file.path(shared_base, "MIMIC"),
    shared_base
  ))
  for (d in cands) {
    if (.incidence_sensitivity_dir_has_imputed(d)) return(d)
  }
  NULL
}

incidence_sensitivity_copy_imputed_ck <- function(src_dir, dest_dir) {
  src_dir <- as.character(src_dir)[1L]
  dest_dir <- as.character(dest_dir)[1L]
  keep_blocks <- c(
    "data_clean", "column_mapping", "dual_db_column_harmonize",
    "index", "analysis_exclusion", "imputation"
  )

  if (!dir.exists(src_dir)) {
    stop("敏感性轻量路径需要主分析插补后 checkpoint: ", src_dir, call. = FALSE)
  }

  rds_files <- list.files(src_dir, pattern = "\\.rds$", full.names = TRUE)
  if (!length(rds_files)) {
    stop("敏感性轻量路径需要主分析插补后 checkpoint: ", src_dir, call. = FALSE)
  }

  block_keys <- vapply(rds_files, function(p) {
    nm <- tools::file_path_sans_ext(basename(p))
    nm <- sub("^step[0-9]+_", "", nm)
    sub("^[0-9]+_", "", nm)
  }, character(1))

  imp_hits <- rds_files[block_keys == "imputation"]
  imp_src <- if (length(imp_hits)) imp_hits[[1L]] else NULL
  has_imputed <- FALSE
  if (!is.null(imp_src)) {
    imp_obj <- tryCatch(readRDS(imp_src), error = function(e) NULL)
    has_imputed <- .incidence_sensitivity_ck_has_imputed(imp_obj)
  }
  if (!has_imputed) {
    idx_hits <- rds_files[block_keys == "index"]
    if (length(idx_hits)) {
      idx_obj <- tryCatch(readRDS(idx_hits[[1L]]), error = function(e) NULL)
      has_imputed <- .incidence_sensitivity_ck_has_imputed(idx_obj)
    }
  }
  if (!has_imputed) {
    stop("敏感性轻量路径需要主分析插补后 checkpoint: ", src_dir, call. = FALSE)
  }

  if (dir.exists(dest_dir)) unlink(dest_dir, recursive = TRUE)
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  for (p in rds_files[block_keys %in% keep_blocks]) {
    file.copy(p, file.path(dest_dir, basename(p)), overwrite = TRUE)
  }

  if (!is.null(imp_src) && has_imputed &&
      .incidence_sensitivity_ck_has_imputed(tryCatch(readRDS(imp_src), error = function(e) NULL))) {
    file.copy(imp_src, file.path(dest_dir, "index.rds"), overwrite = TRUE)
  } else {
    idx_hits <- rds_files[block_keys == "index"]
    if (length(idx_hits)) {
      warning(
        "incidence_sensitivity_copy_imputed_ck: 无 imputation.rds，使用 src index.rds",
        call. = FALSE
      )
      file.copy(idx_hits[[1L]], file.path(dest_dir, "index.rds"), overwrite = TRUE)
    }
  }

  invisible(dest_dir)
}

# ── 轻量敏感性 pipeline 块名单（Task 4）────────────────────────────────────
incidence_sensitivity_light_blocks <- function(study_type, weighted, scheme) {
  scheme <- as.character(scheme)[1L]
  if (!scheme %in% c("quartile", "tertile", "binary")) scheme <- "quartile"
  if (identical(as.character(study_type)[1L], "prognosis")) {
    # 必须含 landmark：complete_case / 其它轻量敏感性从 mapped/cleaned（未行政截尾）起步，
    # 若只跑 baseline+cox，Table S13 会按院内死亡/全 LOS 计，与主文 28 天分母错位。
    blocks <- c(
      "prognosis_outcome_landmark",
      "baseline_binary",
      paste0("cox_", scheme)
    )
    incidence_sensitivity_assert_prognosis_light_blocks(blocks)
    return(blocks)
  }
  if (isTRUE(weighted)) {
    return(c(
      "obj", "baseline_nhanes",
      paste0("logistic_", scheme, "_nhanes_weighted"),
      "dual_db_logistic_scheme_harmonize",
      "dual_db_logistic_main_table_realign"
    ))
  }
  c(
    "baseline_binary",
    paste0("logistic_", scheme, "_glm"),
    "dual_db_logistic_scheme_harmonize",
    "dual_db_logistic_main_table_realign"
  )
}

#' 预后轻量敏感性硬门：含 cox_* 的截断管线必须先跑 prognosis_outcome_landmark
#' （发病 logistic 轻量不含 cox_，本函数直接放行）
incidence_sensitivity_assert_prognosis_light_blocks <- function(blocks) {
  blocks <- as.character(blocks %||% character(0))
  if (!any(startsWith(blocks, "cox_"))) return(invisible(TRUE))
  if (!length(blocks)) {
    stop("预后敏感性轻量路径：pipeline$blocks 为空", call. = FALSE)
  }
  if (!("prognosis_outcome_landmark" %in% blocks)) {
    stop(
      "预后敏感性轻量路径禁止省略 prognosis_outcome_landmark：",
      "否则 complete_case 等场景会按院内死亡/全 LOS 出表，与主文 28 天 landmark 分母错位。",
      " blocks=", paste(blocks, collapse = ","),
      call. = FALSE
    )
  }
  i_lm <- match("prognosis_outcome_landmark", blocks)
  i_base <- match("baseline_binary", blocks)
  i_cox <- which(startsWith(blocks, "cox_"))
  if (!is.na(i_base) && i_lm > i_base) {
    stop(
      "prognosis_outcome_landmark 必须在 baseline_binary 之前（现顺序: ",
      paste(blocks, collapse = " → "), "）",
      call. = FALSE
    )
  }
  if (length(i_cox) && i_lm > min(i_cox)) {
    stop(
      "prognosis_outcome_landmark 必须在 cox_* 之前（现顺序: ",
      paste(blocks, collapse = " → "), "）",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' 出表后抽检：futime 不得超过 landmark_days（默认 28）；超限视为未跑 landmark
incidence_sensitivity_assert_landmark_futime <- function(df, config = NULL,
                                                          landmark_days = NULL) {
  if (!is.data.frame(df) || !nrow(df)) return(invisible(TRUE))
  if (!("futime" %in% names(df))) return(invisible(TRUE))
  po <- (config %||% list())$prognosis_outcome %||% list()
  lm <- as.integer(landmark_days %||% po$landmark_days %||% 28L)[1L]
  if (!is.finite(lm) || lm <= 0L) lm <- 28L
  ft <- suppressWarnings(as.numeric(df$futime))
  ft <- ft[is.finite(ft)]
  if (!length(ft)) return(invisible(TRUE))
  mx <- max(ft)
  if (is.finite(mx) && mx > lm + 1e-6) {
    stop(
      "敏感性预后数据 futime 最大值=", round(mx, 3),
      " > landmark_days=", lm,
      "：疑似未跑 prognosis_outcome_landmark（院内全 LOS 口径）。禁止出表。",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

incidence_sensitivity_trim_pipeline <- function(pipeline, keep_blocks) {
  keep <- as.character(keep_blocks)
  pipeline$blocks <- intersect(as.character(pipeline$blocks %||% character(0)), keep)
  incidence_sensitivity_assert_prognosis_light_blocks(pipeline$blocks)
  if (!is.null(pipeline$render_tables_after)) {
    pipeline$render_tables_after <- intersect(pipeline$render_tables_after, pipeline$blocks)
  }
  if (!is.null(pipeline$render_figures_after)) {
    pipeline$render_figures_after <- intersect(pipeline$render_figures_after, pipeline$blocks)
  }
  pipeline
}

incidence_sensitivity_constant_vars <- function(df, vars) {
  vars <- as.character(vars %||% character(0))
  drop <- character(0)
  for (v in vars) {
    if (!v %in% names(df)) next
    u <- unique(df[[v]][!is.na(df[[v]])])
    if (length(u) < 2L) drop <- c(drop, v)
  }
  unique(drop)
}

incidence_sensitivity_drop_constant_from_config <- function(config, df) {
  harm <- config$dual_db$harmonization %||% list()
  m_keys <- c(
    "harmonized_model1_nhanes", "harmonized_model1_mimic",
    "harmonized_model2_nhanes", "harmonized_model2_mimic"
  )
  all_vars <- character(0)
  for (k in m_keys) {
    all_vars <- c(all_vars, as.character(harm[[k]] %||% character(0)))
  }
  for (bl in c("baseline_nhanes", "baseline_binary", "baseline")) {
    if (!is.null(config[[bl]])) {
      all_vars <- c(all_vars, as.character(config[[bl]]$include_vars %||% character(0)))
    }
  }
  drop <- incidence_sensitivity_constant_vars(df, unique(all_vars[nzchar(all_vars)]))

  .sync_common_model_factors <- function(config) {
    if (is.null(config$dual_db$harmonization)) return(config)
    m1 <- as.character(
      config$dual_db$harmonization$harmonized_model1_nhanes %||%
        config$dual_db$harmonization$harmonized_model1_mimic %||% character(0)
    )
    m2 <- as.character(
      config$dual_db$harmonization$harmonized_model2_nhanes %||%
        config$dual_db$harmonization$harmonized_model2_mimic %||% character(0)
    )
    config$dual_db$harmonization$common_model_factors <- setdiff(m2, m1)
    config
  }

  if (!length(drop)) return(.sync_common_model_factors(config))

  .minus <- function(x) setdiff(as.character(x %||% character(0)), drop)

  if (!is.null(config$dual_db$harmonization)) {
    for (k in m_keys) {
      if (!is.null(config$dual_db$harmonization[[k]])) {
        config$dual_db$harmonization[[k]] <- .minus(config$dual_db$harmonization[[k]])
      }
    }
  }
  for (bl in c("baseline_nhanes", "baseline_binary", "baseline")) {
    if (!is.null(config[[bl]]$include_vars)) {
      config[[bl]]$include_vars <- .minus(config[[bl]]$include_vars)
    }
  }
  .sync_common_model_factors(config)
}

# ── 主分析插补后数据（场景发现用，禁止 shared 未插补表）──────────────────
incidence_sensitivity_load_imputed <- function(main_ck_base, ix, db_path_name,
                                               config = NULL, config_path = NULL) {
  resolved <- .incidence_sensitivity_resolve_imputed_src(main_ck_base, ix, db_path_name)
  src_dir <- resolved$dir
  p <- file.path(src_dir, "imputation.rds")
  if (!file.exists(p)) p <- file.path(src_dir, "index.rds")
  if (!file.exists(p)) {
    hits <- list.files(src_dir, pattern = "imputation\\.rds$", full.names = TRUE)
    if (length(hits)) p <- hits[[1L]]
  }
  obj <- readRDS(p)
  df <- obj$ctx$data$imputed %||% incidence_batch_ctx_data(obj$ctx)
  if (exists("pipeline_normalize_yes_no_factors", mode = "function"))
    df <- pipeline_normalize_yes_no_factors(df)
  # 共享层全指标：剔掉当前指标 NA（与主分析 per-index 一致）
  if (isTRUE(resolved$from_shared) && is.data.frame(df) && ix %in% names(df)) {
    df <- df[!is.na(df[[ix]]), , drop = FALSE]
  }
  df
}

incidence_sensitivity_scenarios_for_index <- function(config, parent_dir, main_ck_base,
                                                      ix, db_names) {
  db_names <- as.character(db_names %||% character(0))
  db_names <- db_names[nzchar(db_names)]
  sens <- utils::modifyList(
    (config$incidence_batch %||% list())$sensitivity_suite %||% list(),
    (config$survival_batch %||% list())$sensitivity_suite %||% list()
  )
  min_yes_n <- as.integer(sens$min_yes_n %||% 50L)[1L]
  min_n <- as.integer(sens$min_n_per_db %||% 50L)[1L]
  age_cutoff <- as.integer(sens$age_cutoff %||% 65L)[1L]
  t1_vars_by_db <- list()
  data_by_db <- list()
  for (db in db_names) {
    t1_vars_by_db[[db]] <- incidence_sensitivity_read_table1_vars(parent_dir, db)
    data_by_db[[db]] <- tryCatch(
      incidence_sensitivity_load_imputed(main_ck_base, ix, db),
      error = function(e) NULL
    )
  }
  yesno <- incidence_sensitivity_discover_yesno(t1_vars_by_db, data_by_db, min_yes_n)
  age <- incidence_sensitivity_age_scenarios(age_cutoff, data_by_db, min_n)
  cc <- list()
  if (!isFALSE(sens$complete_case %||% TRUE)) {
    main_cov <- incidence_sensitivity_load_main_covariates(parent_dir, ix)
    unimp_by_db <- list()
    for (db in db_names) {
      unimp_by_db[[db]] <- tryCatch(
        incidence_sensitivity_load_unimputed(main_ck_base, ix, db),
        error = function(e) NULL
      )
    }
    cc <- incidence_sensitivity_complete_case_scenario(
      config, ix, unimp_by_db, main_cov$m1, main_cov$m2, min_n
    )
  }
  c(cc, yesno, age)
}

.incidence_sensitivity_parse_p <- function(x) {
  s <- trimws(as.character(x %||% "")[1L])
  if (!nzchar(s) || grepl("^(Ref|ref|NA|P|P value|P-value)$", s, ignore.case = TRUE)) {
    return(NA_real_)
  }
  if (grepl("<\\s*0\\.001", s)) return(0.0005)
  suppressWarnings(as.numeric(s))
}

# Skip p-for-trend / Ref / header rows; primary contrast is last remaining group row.
.incidence_sensitivity_is_skip_contrast_row <- function(row) {
  cells <- trimws(as.character(unlist(row, use.names = FALSE)))
  cells[is.na(cells)] <- ""
  if (!length(cells) || !any(nzchar(cells))) return(TRUE)
  skip_re <- paste(
    "p\\s*for\\s*trend",
    "\\bRef\\b",
    "Characteristic",
    "P[- ]?value",
    "Crude\\s*Model",
    "^Model\\s*[123]$",
    "^OR$",
    "^HR$",
    "95%\\s*CI",
    "Exposure\\s*cutoff",
    sep = "|"
  )
  any(grepl(skip_re, cells, ignore.case = TRUE, perl = TRUE))
}

.incidence_sensitivity_table2_highest_p <- function(ctx, which = c("model2", "crude")) {
  which <- match.arg(which)
  if (is.null(ctx) || !is.list(ctx)) return(NA_real_)
  r <- ctx$results %||% list()
  tbl <- r$logistic_table2 %||% r$nhanes_logistic_table2 %||%
    r$logistic_table2_weighted %||% r$logistic_table2_nhanes %||%
    r$cox_hr %||% r$cox_table2 %||% NULL
  if (is.null(tbl)) return(NA_real_)
  tbl <- as.data.frame(tbl, stringsAsFactors = FALSE)
  if (!nrow(tbl) || !ncol(tbl)) return(NA_real_)
  # SCI 三线表：Crude P=第6列，Model2 P=第12列；主对比=最高分位（末行非 skip）
  p_col <- if (identical(which, "crude")) {
    if (ncol(tbl) >= 6L) 6L else return(NA_real_)
  } else {
    if (ncol(tbl) >= 12L) 12L else ncol(tbl)
  }
  keep <- vapply(seq_len(nrow(tbl)), function(i) {
    !isTRUE(.incidence_sensitivity_is_skip_contrast_row(tbl[i, , drop = TRUE]))
  }, logical(1L))
  if (!any(keep)) return(NA_real_)
  i <- max(which(keep))
  .incidence_sensitivity_parse_p(tbl[[p_col]][i])
}

incidence_sensitivity_model2_primary_p <- function(ctx) {
  .incidence_sensitivity_table2_highest_p(ctx, "model2")
}

incidence_sensitivity_crude_highest_p <- function(ctx) {
  .incidence_sensitivity_table2_highest_p(ctx, "crude")
}

incidence_sensitivity_rename_pub_tables <- function(tables_dir, db_tag, zh_desc,
                                                    study_type = "incidence",
                                                    parent_dir = NULL,
                                                    s_baseline = NULL,
                                                    s_association = NULL,
                                                    label = NULL) {
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) return(invisible(character(0)))
  db_tag <- as.character(db_tag %||% "")[1L]
  zh_desc <- as.character(zh_desc %||% "")[1L]
  label <- as.character(label %||% "")[1L]
  s_nums <- incidence_sensitivity_resolve_pub_s_nums(
    parent_dir = parent_dir,
    s_baseline = s_baseline,
    s_association = s_association
  )
  s_base <- s_nums$baseline
  s_assoc <- s_nums$association
  files <- list.files(tables_dir, full.names = TRUE)
  out <- character(0)
  for (f in files) {
    if (!file.exists(f) || dir.exists(f)) next
    bn <- basename(f)
    use_tag <- as.character(db_tag)[1L]
    if (!nzchar(use_tag)) use_tag <- incidence_sensitivity_db_tag_from_name(bn)
    s_num <- NA_integer_
    # 分位基线 / 正态性不是敏感性发表表，禁止改名进 SA 号段
    if (grepl("Baseline characteristics by .+ (quartile|tertile|binary|median)",
              bn, ignore.case = TRUE, perl = TRUE)) {
      next
    }
    if (grepl("Normality test", bn, ignore.case = TRUE)) {
      next
    }
    is_base <- grepl("Baseline characteristics", bn, ignore.case = TRUE) ||
      grepl("\\. SA-[^.]+\\. Baseline\\.", bn, ignore.case = TRUE) ||
      grepl("\\. Baseline\\.(xlsx|csv|tex)$", bn, ignore.case = TRUE)
    is_assoc <- grepl(
      "Logistic regression|\\bCox\\b|The Association Between",
      bn, ignore.case = TRUE, perl = TRUE
    ) || grepl("\\. SA-[^.]+\\. Association\\.", bn, ignore.case = TRUE) ||
      grepl("\\. Association\\.(xlsx|csv|tex)$", bn, ignore.case = TRUE)
    if (is_base && !grepl("Association|Logistic|\\bCox\\b", bn, ignore.case = TRUE, perl = TRUE)) {
      s_num <- s_base
    } else if (is_assoc) {
      s_num <- s_assoc
    } else if (is_base) {
      s_num <- s_base
    } else {
      next
    }
    if (!nzchar(use_tag)) next
    role <- if (identical(s_num, s_base)) "baseline" else "association"
    cap <- sub("^Table\\s+S?[0-9]+(?:-[^.]+)?\\.\\s*", "", tools::file_path_sans_ext(bn))
    cap <- incidence_sensitivity_strip_existing_sa_caption(cap)
    if (!nzchar(trimws(cap)) ||
        grepl("^(Baseline|Association)$", trimws(cap), ignore.case = TRUE)) {
      cap <- if (identical(role, "baseline")) "Baseline characteristics" else {
        if (identical(as.character(study_type)[1L], "prognosis"))
          "Cox regression" else "Logistic regression"
      }
    }
    ext <- tools::file_ext(bn)
    stem <- incidence_sensitivity_pub_stem(
      s_num, use_tag, zh_desc, cap,
      label = label, role = role, study_type = study_type
    )
    title <- incidence_sensitivity_pub_title(s_num, use_tag, zh_desc, cap)
    new_bn <- if (nzchar(ext)) paste0(stem, ".", ext) else stem
    if (identical(bn, new_bn)) {
      out <- c(out, new_bn)
      next
    }
    new_path <- file.path(tables_dir, new_bn)
    if (!identical(
      normalizePath(f, winslash = "/", mustWork = FALSE),
      normalizePath(new_path, winslash = "/", mustWork = FALSE)
    )) {
      if (file.exists(new_path)) unlink(new_path)
      ok <- tryCatch(file.rename(f, new_path), error = function(e) FALSE)
      if (!isTRUE(ok)) {
        file.copy(f, new_path, overwrite = TRUE)
        unlink(f)
      }
    }
    if (requireNamespace("openxlsx", quietly = TRUE) &&
        grepl("xlsx$", new_path, ignore.case = TRUE) &&
        isTRUE((file.info(new_path)$size %||% 0) > 22)) {
      tryCatch({
        wb <- openxlsx::loadWorkbook(new_path)
        sh <- openxlsx::sheets(wb)[1L]
        v <- tryCatch(
          openxlsx::read.xlsx(new_path, sheet = 1L, colNames = FALSE, rows = 1, cols = 1),
          error = function(e) NULL
        )
        first <- if (!is.null(v) && nrow(v) && ncol(v)) as.character(v[1, 1])[1L] else ""
        if (nzchar(first) && grepl("^Table ", first)) {
          openxlsx::writeData(wb, sh, title, startCol = 1, startRow = 1, colNames = FALSE)
          openxlsx::saveWorkbook(wb, new_path, overwrite = TRUE)
        }
      }, error = function(e) NULL)
    }
    out <- c(out, new_bn)
  }
  invisible(out)
}

incidence_sensitivity_is_keep_pub_table <- function(bn) {
  bn <- basename(as.character(bn %||% character(0)))
  if (!length(bn)) return(logical(0))
  ok <- grepl("^Table S[0-9]+-", bn) & (
    grepl("Sensitivity analysis", bn, fixed = TRUE) |
      grepl(". SA-", bn, fixed = TRUE)
  )
  ok <- ok & !grepl(
    "Baseline characteristics by .+ (quartile|tertile|binary|median)",
    bn, ignore.case = TRUE, perl = TRUE
  )
  ok & !grepl("Normality test", bn, ignore.case = TRUE)
}

incidence_sensitivity_keep_pub_tables <- function(tables_dir) {
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) return(invisible(character(0)))
  files <- list.files(tables_dir, full.names = TRUE)
  dropped <- character(0)
  for (f in files) {
    if (!file.exists(f) || dir.exists(f)) next
    if (incidence_sensitivity_is_keep_pub_table(basename(f))) next
    unlink(f)
    dropped <- c(dropped, basename(f))
  }
  invisible(dropped)
}

incidence_sensitivity_sync_combined_tables <- function(src_ix_dir, db_names) {
  src_ix_dir <- as.character(src_ix_dir %||% "")[1L]
  dest <- file.path(src_ix_dir, "Tables")
  if (!nzchar(src_ix_dir) || !dir.exists(src_ix_dir)) return(invisible(character(0)))
  db_names <- as.character(db_names %||% character(0))
  any_db_tables <- any(vapply(db_names, function(db) {
    dir.exists(file.path(src_ix_dir, db, "Tables"))
  }, logical(1L)))
  # 单库扁平布局：表已在 src/Tables 完成 rename，禁止清空后从空的 db/Tables 回拷
  if (!any_db_tables) return(invisible(character(0)))

  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(dest, full.names = TRUE)
  old <- old[!dir.exists(old)]
  if (length(old)) unlink(old)
  copied <- character(0)
  for (db in db_names) {
    td <- file.path(src_ix_dir, db, "Tables")
    if (!dir.exists(td)) next
    hits <- list.files(td, full.names = TRUE)
    hits <- hits[incidence_sensitivity_is_keep_pub_table(basename(hits))]
    for (f in hits) {
      file.copy(f, file.path(dest, basename(f)), overwrite = TRUE)
      copied <- c(copied, basename(f))
    }
  }
  invisible(copied)
}

.incidence_sensitivity_scheme_from_status <- function(parent_dir) {
  p <- file.path(parent_dir, "_batch_status.json")
  if (file.exists(p)) {
    st <- tryCatch(jsonlite::fromJSON(p), error = function(e) NULL)
    if (!is.null(st)) {
      br <- as.character(
        st$nhanes_branch %||% st$mimic_branch %||% st$cox_branch %||%
          st$logistic_branch %||% st$gate_branch %||% ""
      )[1L]
      if (nzchar(br) && !br %in% c("NA", "NULL")) {
        for (sch in c("quartile", "tertile", "binary")) {
          if (grepl(sch, br, ignore.case = TRUE)) return(sch)
        }
      }
    }
  }
  # 两阶段等无 branch 字段：从主文 Table 2 文件名推断
  td <- file.path(parent_dir, "Tables")
  if (dir.exists(td)) {
    bns <- list.files(td, pattern = "Table\\s*2", ignore.case = TRUE)
    for (sch in c("quartile", "tertile", "binary", "quintile")) {
      if (any(grepl(sch, bns, ignore.case = TRUE))) {
        if (identical(sch, "quintile")) return("quartile")
        return(sch)
      }
    }
  }
  "quartile"
}

.incidence_sensitivity_latest_ctx <- function(ck_dir) {
  if (is.null(ck_dir) || !dir.exists(ck_dir)) return(NULL)
  rds <- list.files(ck_dir, pattern = "\\.rds$", full.names = TRUE)
  if (!length(rds)) return(NULL)
  info <- file.info(rds)
  rds <- rds[order(info$mtime, decreasing = TRUE)]
  pick <- NULL
  for (p in rds) {
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(obj) || is.null(obj$ctx)) next
    if (is.null(pick)) pick <- obj$ctx
    r <- obj$ctx$results %||% list()
    if (!is.null(r$logistic_table2) || !is.null(r$nhanes_logistic_table2) ||
        !is.null(r$cox_hr) || !is.null(r$cox_table2)) {
      return(obj$ctx)
    }
  }
  pick
}

.incidence_sensitivity_abs_ck <- function(ck_base, config_path) {
  ck_base <- as.character(ck_base %||% "")[1L]
  if (!nzchar(ck_base)) return(ck_base)
  if (exists("is_absolute_path", mode = "function") && is_absolute_path(ck_base)) {
    return(ck_base)
  }
  if (grepl("^(?:[A-Za-z]:)?[/\\\\]", ck_base)) return(ck_base)
  study_root <- dirname(normalizePath(config_path, winslash = "/", mustWork = FALSE))
  file.path(study_root, ck_base)
}

# ── 定位指标 by_index 父目录（裸名 / 【success】<ix> / 【failed】<ix>）──────
.incidence_sensitivity_find_index_parent <- function(by_index_dir, ix) {
  if (!dir.exists(by_index_dir)) return(NULL)
  dirs <- list.dirs(by_index_dir, recursive = FALSE, full.names = TRUE)
  bns  <- basename(dirs)
  hit  <- dirs[endsWith(bns, paste0("\u3011", ix))]   # 】<ix>
  if (!length(hit)) hit <- dirs[bns == ix]
  if (length(hit)) hit[1L] else NULL
}

# ── 主分析 Table 2 脚注 → Model1/Model2（敏感性必须与发表表一致）──────────
.incidence_sensitivity_split_cov_list <- function(s) {
  s <- trimws(as.character(s %||% "")[1L])
  s <- gsub("\\\\[a-zA-Z]+\\*?", " ", s)
  s <- gsub("[{}]", "", s)
  s <- sub("[.;]+$", "", s)
  s <- trimws(s)
  if (!nzchar(s) || grepl("^(none|non-adjusted|unadjusted)$", s, ignore.case = TRUE)) {
    return(character(0))
  }
  parts <- trimws(unlist(strsplit(s, ",", fixed = TRUE), use.names = FALSE))
  parts[nzchar(parts)]
}

.incidence_sensitivity_map_footnote_vars <- function(tokens, known = character(0)) {
  tokens <- trimws(as.character(tokens %||% character(0)))
  tokens <- tokens[nzchar(tokens)]
  known <- unique(as.character(known %||% character(0)))
  known <- known[nzchar(known)]
  disp <- if (exists("pipeline_builtin_var_display_names", mode = "function")) {
    tryCatch(pipeline_builtin_var_display_names(), error = function(e) NULL)
  } else {
    NULL
  }
  out <- character(0)
  for (t0 in tokens) {
    us <- gsub(" ", "_", t0, fixed = TRUE)
    if (t0 %in% known) {
      out <- c(out, t0)
      next
    }
    if (us %in% known) {
      out <- c(out, us)
      next
    }
    hit_ci <- known[tolower(known) %in% c(tolower(t0), tolower(us))]
    if (length(hit_ci)) {
      out <- c(out, hit_ci[[1L]])
      next
    }
    if (is.list(disp) && length(disp)) {
      dn <- unname(as.character(disp))
      hit_d <- names(disp)[tolower(dn) == tolower(t0)]
      if (length(hit_d)) {
        out <- c(out, hit_d[[1L]])
        next
      }
    }
    out <- c(out, us)
  }
  unique(out[nzchar(out)])
}

incidence_sensitivity_parse_table2_footnotes <- function(text) {
  raw <- paste(as.character(text %||% ""), collapse = "\n")
  raw <- gsub("\\\\par\\\\noindent", "\n", raw)
  raw <- gsub("\\\\noindent", "\n", raw)
  raw <- gsub("\\\\par", "\n", raw)
  .cap <- function(n) {
    re <- sprintf(
      "(?i)(?:The\\s+)?Model\\s*%d\\s+was\\s+adjusted\\s+by\\s*:\\s*([^\\n\\r]+)",
      as.integer(n)[1L]
    )
    m <- regexec(re, raw, perl = TRUE)
    if (!length(m) || m[[1L]][1L] < 0L) return(character(0))
    cap <- regmatches(raw, m)[[1L]]
    if (length(cap) < 2L) return(character(0))
    .incidence_sensitivity_split_cov_list(cap[[2L]])
  }
  list(m1 = .cap(1L), m2 = .cap(2L))
}

.incidence_sensitivity_intersect_cov <- function(xs) {
  xs <- xs[lengths(xs) > 0L]
  if (!length(xs)) return(character(0))
  if (length(xs) == 1L) return(unique(xs[[1L]]))
  out <- Reduce(intersect, xs)
  if (!length(out)) unique(xs[[1L]]) else unique(out)
}

.incidence_sensitivity_is_assoc_table2 <- function(path) {
  bn <- basename(path)
  !grepl("Baseline characteristics", bn, ignore.case = TRUE) &
    grepl(
      "Association|Logistic|Cox|quartile|tertile|binary|regression",
      bn, ignore.case = TRUE
    )
}

.incidence_sensitivity_read_table2_file_text <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "tex")) {
    return(tryCatch(readLines(path, warn = FALSE), error = function(e) character(0)))
  }
  if (identical(ext, "xlsx") && requireNamespace("openxlsx", quietly = TRUE)) {
    sheets <- tryCatch(openxlsx::getSheetNames(path), error = function(e) character(0))
    out <- character(0)
    for (sh in sheets) {
      df <- tryCatch(
        openxlsx::read.xlsx(path, sheet = sh, colNames = FALSE),
        error = function(e) NULL
      )
      if (is.null(df)) next
      out <- c(out, as.character(unlist(df, use.names = FALSE)))
    }
    return(out[!is.na(out) & nzchar(trimws(out))])
  }
  character(0)
}

.incidence_sensitivity_read_table2_covariates <- function(parent_dir, known = character(0)) {
  if (is.null(parent_dir) || !dir.exists(parent_dir)) {
    return(list(m1 = character(0), m2 = character(0)))
  }
  hits <- list.files(
    parent_dir,
    pattern = "^Table 2[- ].*\\.(tex|xlsx)$",
    recursive = TRUE, full.names = TRUE, ignore.case = TRUE
  )
  # 排除敏感性/归档，以及指标目录内嵌套的旧亚组 fallback
  # （…/【success】ANLR/【success】Age_65/…），勿误伤父级 【success】ANLR 自身。
  hits <- hits[!grepl(
    "sensitivity|\\.sensitivity_staging|archived|【archived】|/【success】[^/]+/【(success|failed)】|/【failed】[^/]+/",
    hits
  )]
  hits <- hits[file.exists(hits)]
  if (!length(hits)) return(list(m1 = character(0), m2 = character(0)))
  assoc <- hits[.incidence_sensitivity_is_assoc_table2(hits)]
  if (length(assoc)) hits <- assoc
  score <- function(p) {
    s <- 0L
    bn <- basename(p)
    if (grepl("Association", bn, ignore.case = TRUE)) s <- s + 100L
    if (grepl("Cox|Logistic", bn, ignore.case = TRUE)) s <- s + 40L
    if (grepl("\\.tex$", p, ignore.case = TRUE)) s <- s + 20L
    if (grepl("cox_quartile|logistic_quartile", p, ignore.case = TRUE)) s <- s + 10L
    # 优先指标根 / 分库 Tables，弱化 step*_cox 副本
    if (grepl("/Tables/Table 2", p, fixed = TRUE) &&
        !grepl("step[0-9]+_", p)) s <- s + 30L
    s
  }
  hits <- hits[order(vapply(hits, score, integer(1L)), decreasing = TRUE)]
  parsed <- lapply(hits, function(p) {
    incidence_sensitivity_parse_table2_footnotes(
      .incidence_sensitivity_read_table2_file_text(p)
    )
  })
  m1 <- .incidence_sensitivity_map_footnote_vars(
    .incidence_sensitivity_intersect_cov(lapply(parsed, `[[`, "m1")),
    known
  )
  m2 <- .incidence_sensitivity_map_footnote_vars(
    .incidence_sensitivity_intersect_cov(lapply(parsed, `[[`, "m2")),
    known
  )
  list(m1 = m1, m2 = m2)
}

# ── 从主分析父目录读取 Table 2 实际协变量（禁止用 VIF 长名单过度调整）──────
.incidence_sensitivity_load_main_covariates <- function(parent_dir, ix = NULL) {
  m1 <- character(0); m2 <- character(0)
  if (is.null(parent_dir) || !dir.exists(parent_dir)) {
    return(list(m1 = m1, m2 = m2))
  }
  .read_cov <- function(path) {
    if (!file.exists(path)) return(character(0))
    ln <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
    ln <- trimws(ln)
    ln <- ln[nzchar(ln) & !startsWith(ln, "#")]
    unique(ln)
  }
  .exclude_sa <- function(paths) {
    paths[!grepl(
      "sensitivity|\\.sensitivity_staging|archived|【archived】|/【success】[^/]+/【(success|failed)】|/【failed】[^/]+/",
      paths
    )]
  }
  fc_hits <- .exclude_sa(list.files(
    parent_dir, pattern = "^FinalCovariates_.*\\.txt$",
    recursive = TRUE, full.names = TRUE
  ))
  m2_hits <- .exclude_sa(list.files(
    parent_dir, pattern = "^Model2Factors\\.txt$",
    recursive = TRUE, full.names = TRUE
  ))
  m1_hits <- .exclude_sa(list.files(
    parent_dir, pattern = "^Model1Factors\\.txt$",
    recursive = TRUE, full.names = TRUE
  ))
  known <- character(0)
  for (p in c(fc_hits, m2_hits, m1_hits)) known <- c(known, .read_cov(p))
  known <- unique(known[nzchar(known)])

  t2 <- .incidence_sensitivity_read_table2_covariates(parent_dir, known)
  m1 <- t2$m1
  m2 <- t2$m2

  if (!length(m2)) {
    score <- function(p) {
      s <- 0L
      if (grepl("Tables/Summary", p, fixed = TRUE)) s <- s + 100L
      hd <- tryCatch(readLines(p, n = 5L, warn = FALSE), error = function(e) character(0))
      if (any(grepl("Gate B locked", hd, fixed = TRUE))) s <- s + 50L
      if (grepl("step12_multicollinearity_final", p, fixed = TRUE)) s <- s + 20L
      s
    }
    if (length(fc_hits)) {
      sc <- vapply(fc_hits, score, integer(1))
      fc_hits <- fc_hits[order(sc, decreasing = TRUE)]
      m2 <- .read_cov(fc_hits[[1L]])
    }
    if (!length(m2) && length(m2_hits)) {
      prefer <- grepl("multicollinearity_final|Tables/Summary|step12", m2_hits)
      if (any(prefer)) m2_hits <- c(m2_hits[prefer], m2_hits[!prefer])
      m2 <- .read_cov(m2_hits[[1L]])
    }
  }
  if (!length(m1) && length(m1_hits)) m1 <- .read_cov(m1_hits[[1L]])
  if (!length(m1) && length(m2)) m1 <- intersect(m2, c("Age", "Gender", "Sex", "Race"))
  if (!length(m1)) m1 <- "Age"
  m1 <- unique(m1[nzchar(m1)])
  m2 <- unique(c(m1, setdiff(m2[nzchar(m2)], m1)))
  list(m1 = m1, m2 = m2)
}

incidence_sensitivity_load_main_covariates <- .incidence_sensitivity_load_main_covariates

.incidence_sensitivity_db_names <- function(config) {
  db_mode <- tolower(as.character(
    (config$incidence_batch %||% list())$db_mode %||%
      (config$survival_batch %||% list())$db_mode %||% ""
  )[1L])
  # 单库课题（dual_db 关 / 无 secondary 路径）默认 nhanes_only，避免去拷不存在的 MIMIC。
  # 禁止用 project$database_type=="nhanes" 判定：双库课题主库也常标 nhanes。
  if (!nzchar(db_mode) || identical(db_mode, "both")) {
    dual <- config$dual_db %||% list()
    dual_off <- isFALSE(dual$enable %||% TRUE)
    sec <- dual$secondary %||% list()
    has_sec <- nzchar(as.character(sec$rawdata_path %||% "")[1L]) ||
      nzchar(as.character(sec$path %||% "")[1L]) ||
      nzchar(as.character(sec$database %||% "")[1L]) ||
      nzchar(as.character(sec$name %||% "")[1L])
    if (dual_off || !isTRUE(has_sec)) db_mode <- "nhanes_only"
    else db_mode <- "both"
  }
  if (exists("dual_db_slot_path_name", mode = "function")) {
    if (db_mode %in% c("nhanes", "nhanes_only", "primary")) {
      return(dual_db_slot_path_name(config, "nhanes"))
    }
    if (db_mode %in% c("mimic", "mimic_only", "regular", "secondary")) {
      return(dual_db_slot_path_name(config, "mimic"))
    }
    return(unique(c(
      dual_db_slot_path_name(config, "nhanes"),
      dual_db_slot_path_name(config, "mimic")
    )))
  }
  if (db_mode %in% c("nhanes", "nhanes_only", "primary")) return("NHANES")
  if (db_mode %in% c("mimic", "mimic_only", "regular", "secondary")) return("MIMIC")
  c("NHANES", "MIMIC")
}

.incidence_sensitivity_move_dir <- function(src, dst) {
  if (!dir.exists(src)) return(FALSE)
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(dst)) unlink(dst, recursive = TRUE)
  ok <- tryCatch(file.rename(src, dst), error = function(e) FALSE)
  if (isTRUE(ok)) return(TRUE)
  tryCatch({
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    file.copy(list.files(src, full.names = TRUE), dst, recursive = TRUE)
    unlink(src, recursive = TRUE)
    TRUE
  }, error = function(e) FALSE)
}

# ── 生成敏感性临时 config ────────────────────────────────────────────────────
# 注意：worker 的 --config 指向本临时文件时，study config.R 会用
# dirname(--config) 当 .batch_project_root，误指向 staging，导致 shared_ck /
# Data 全部找不到。source 后必须强制写回真实研究根路径。
incidence_sensitivity_write_config <- function(base_config_path, staging_run,
                                               sensitivity_ck_base, sg, out_path,
                                               main_covariates = NULL,
                                               scheme = "quartile",
                                               zh_desc = NULL) {
  .q <- function(x) deparse(as.character(x)[1L], width.cutoff = 500L)[1L]
  .qv <- function(x) {
    x <- as.character(x %||% character(0))
    x <- x[nzchar(x)]
    if (!length(x)) return("character(0)")
    paste0("c(", paste(vapply(x, .q, character(1)), collapse = ", "), ")")
  }
  base_abs <- normalizePath(base_config_path, winslash = "/", mustWork = FALSE)
  # study_root：优先用已 source 的 output 路径；生成临时 config 时 dirname(base) 可能是 /tmp
  study_root <- dirname(base_abs)
  # 若 base 在课题根外（如 /tmp overlay），从文件正文猜 .batch_project_root / output
  if (!dir.exists(file.path(study_root, "by_index")) &&
      !dir.exists(file.path(study_root, "checkpoints"))) {
    raw <- tryCatch(readLines(base_abs, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
    m <- regexec('\\.batch_project_root\\s*<-\\s*["\']([^"\']+)["\']', raw, perl = TRUE)
    mm <- Filter(function(x) length(x) >= 2L, regmatches(raw, m))
    if (length(mm)) {
      cand <- mm[[1L]][2L]
      if (dir.exists(cand)) study_root <- cand
    }
  }
  study_ck <- file.path(study_root, "checkpoints")
  shared_ck <- file.path(study_ck, "_shared")
  # 相对 ck 路径按研究根绝对化（避免 worker cwd=引擎根时落错盘）
  ck_abs <- sensitivity_ck_base
  if (!grepl("^(?:[A-Za-z]:)?[/\\\\]", ck_abs)) {
    ck_abs <- file.path(study_root, ck_abs)
  }
  base_q <- .q(base_abs)
  stg_q  <- .q(normalizePath(staging_run, winslash = "/", mustWork = FALSE))
  ck_q   <- .q(normalizePath(ck_abs, winslash = "/", mustWork = FALSE))
  sr_q   <- .q(study_root)
  shared_q <- .q(shared_ck)
  ckroot_q <- .q(study_ck)
  harm_q <- .q(file.path(study_ck, "_global_harmonization"))
  ex_q   <- .q(sg$expr)
  lb_q   <- .q(sg$label)
  m1 <- as.character((main_covariates %||% list())$m1 %||% character(0))
  m2 <- as.character((main_covariates %||% list())$m2 %||% character(0))
  if (!length(m1)) m1 <- "Age"
  table1_vars <- as.character((main_covariates %||% list())$table1_vars %||% character(0))
  scheme <- as.character(scheme %||% "quartile")[1L]
  if (!scheme %in% c("quartile", "tertile", "binary")) scheme <- "quartile"
  zh_desc <- as.character(
    zh_desc %||% incidence_sensitivity_zh_desc(sg$label %||% "")
  )[1L]
  lines <- c(
    "# AUTO-GENERATED by incidence_sensitivity_suite.R",
    paste0(".local_base <- ", base_q),
    "source(.local_base)",
    paste0(".study_root <- ", sr_q),
    # 单库课题常只有 pipeline：给 dual-batch worker 挂上加权流水线别名
    "if (!exists('pipeline_nhanes_batch', inherits = FALSE) && exists('pipeline', inherits = FALSE))",
    "  pipeline_nhanes_batch <- pipeline",
    "if (!exists('pipeline_regular_batch', inherits = FALSE) && exists('pipeline', inherits = FALSE))",
    "  pipeline_regular_batch <- pipeline",
    "config$project$output_dir <- .study_root",
    paste0("config$dual_db$checkpoint_base <- ", ckroot_q),
    paste0("config$dual_db$harmonization_dir <- ", harm_q),
    paste0("config$incidence_batch$shared_ck_base <- ", shared_q),
    paste0("config$incidence_batch$output_base   <- ", stg_q),
    paste0("config$incidence_batch$index_ck_base <- ", ck_q),
    paste0("config$incidence_batch$.subgroup_fallback_expr  <- ", ex_q),
    paste0("config$incidence_batch$.subgroup_fallback_label <- ", lb_q),
    "config$incidence_batch$.sensitivity_light <- TRUE",
    paste0("config$incidence_batch$.sensitivity_scheme <- ", .q(scheme)),
    paste0("config$incidence_batch$.sensitivity_zh_desc <- ", .q(zh_desc)),
    paste0(
      "config$incidence_batch$.sensitivity_complete_case <- ",
      if (isTRUE(incidence_sensitivity_is_complete_case(sg))) "TRUE" else "FALSE"
    ),
    "if (!is.null(config$ip_two_stage_batch) || exists('pipeline_stage1', inherits = TRUE)) {",
    "  if (is.null(config$ip_two_stage_batch)) config$ip_two_stage_batch <- list()",
    paste0("  config$ip_two_stage_batch$shared_ck_base <- ", shared_q),
    paste0("  config$ip_two_stage_batch$output_base   <- ", stg_q),
    paste0("  config$ip_two_stage_batch$index_ck_base <- ", ck_q),
    "  config$ip_two_stage_batch$.sensitivity_light <- TRUE",
    paste0("  config$ip_two_stage_batch$.sensitivity_scheme <- ", .q(scheme)),
    paste0("  config$ip_two_stage_batch$.sensitivity_zh_desc <- ", .q(zh_desc)),
    paste0(
      "  config$ip_two_stage_batch$.sensitivity_complete_case <- ",
      if (isTRUE(incidence_sensitivity_is_complete_case(sg))) "TRUE" else "FALSE"
    ),
    paste0("  config$ip_two_stage_batch$.subgroup_fallback_expr  <- ", ex_q),
    paste0("  config$ip_two_stage_batch$.subgroup_fallback_label <- ", lb_q),
    "}",
    "if (!is.null(config$dual_db$primary$rawdata_path)) {",
    "  .p <- config$dual_db$primary$rawdata_path",
    "  if (!isTRUE(file.exists(.p))) {",
    "    .cand <- file.path(.study_root, 'data', basename(dirname(.p)), basename(.p))",
    "    .cand2 <- file.path(.study_root, 'Data', basename(dirname(.p)), basename(.p))",
    "    if (isTRUE(file.exists(.cand))) config$dual_db$primary$rawdata_path <- .cand",
    "    else if (isTRUE(file.exists(.cand2))) config$dual_db$primary$rawdata_path <- .cand2",
    "  }",
    "}",
    "if (!is.null(config$dual_db$secondary$rawdata_path)) {",
    "  .p <- config$dual_db$secondary$rawdata_path",
    "  if (!isTRUE(file.exists(.p))) {",
    "    .cand <- file.path(.study_root, 'data', basename(dirname(.p)), basename(.p))",
    "    .cand2 <- file.path(.study_root, 'Data', basename(dirname(.p)), basename(.p))",
    "    if (isTRUE(file.exists(.cand))) config$dual_db$secondary$rawdata_path <- .cand",
    "    else if (isTRUE(file.exists(.cand2))) config$dual_db$secondary$rawdata_path <- .cand2",
    "  }",
    "}",
    "if (!is.null(config$survival_batch)) {",
    "  config$survival_batch <- utils::modifyList(config$survival_batch, config$incidence_batch)",
    paste0("  config$survival_batch$shared_ck_base <- ", shared_q),
    paste0("  config$survival_batch$output_base   <- ", stg_q),
    paste0("  config$survival_batch$index_ck_base <- ", ck_q),
    "  config$survival_batch$.sensitivity_light <- TRUE",
    paste0("  config$survival_batch$.sensitivity_scheme <- ", .q(scheme)),
    paste0("  config$survival_batch$.sensitivity_zh_desc <- ", .q(zh_desc)),
    paste0(
      "  config$survival_batch$.sensitivity_complete_case <- ",
      if (isTRUE(incidence_sensitivity_is_complete_case(sg))) "TRUE" else "FALSE"
    ),
    "}",
    "config$feishu$enable <- FALSE",
    "# ── 敏感性：锁主分析 Table 2 脚注协变量（禁止用 VIF Model2Factors 长名单过度调整）──",
    paste0(".m1 <- ", .qv(m1)),
    paste0(".m2 <- ", .qv(m2)),
    "if (is.null(config$dual_db) || !is.list(config$dual_db)) config$dual_db <- list()",
    "if (is.null(config$dual_db$harmonization) || !is.list(config$dual_db$harmonization))",
    "  config$dual_db$harmonization <- list()",
    "config$dual_db$harmonization$lock_covariates_preset <- TRUE",
    "config$dual_db$harmonization$covariate_source <- 'vif_final'",
    "config$dual_db$harmonization$sync_after_vif_final <- FALSE",
    "config$dual_db$harmonization$sync_logistic_branch <- TRUE",
    "config$dual_db$harmonization$harmonized_model1_nhanes <- as.character(.m1)",
    "config$dual_db$harmonization$harmonized_model1_mimic  <- as.character(.m1)",
    "if (length(.m2)) {",
    "  config$dual_db$harmonization$harmonized_model2_nhanes <- as.character(.m2)",
    "  config$dual_db$harmonization$harmonized_model2_mimic  <- as.character(.m2)",
    "  config$dual_db$harmonization$common_model_factors <- setdiff(as.character(.m2), as.character(.m1))",
    "}",
    paste0(".table1_vars <- ", .qv(table1_vars)),
    "if (exists('.table1_vars') && length(.table1_vars)) {",
    "  .tv <- as.character(.table1_vars)",
    "  if (!is.null(config$baseline_nhanes)) config$baseline_nhanes$include_vars <- .tv",
    "  if (!is.null(config$baseline_binary)) config$baseline_binary$include_vars <- .tv",
    "  if (!is.null(config$baseline)) config$baseline$include_vars <- .tv",
    "}",
    "if (!is.null(config$column_mapping)) config$column_mapping$enable <- TRUE",
    "# 敏感性子样本：关闭早停与过严 Cox gate（避免 COX_SEARCH_STOP / crude_ns 整场景失败）",
    "if (!is.null(config$baseline_nhanes)) {",
    "  config$baseline_nhanes$early_stop_if_index_ns <- FALSE",
    "  config$baseline_nhanes$skip_normality_export <- TRUE",
    "}",
    "if (!is.null(config$baseline_binary)) {",
    "  config$baseline_binary$early_stop_if_index_ns <- FALSE",
    "  config$baseline_binary$skip_normality_export <- TRUE",
    "}",
    "if (!is.null(config$baseline)) config$baseline$skip_normality_export <- TRUE",
    "for (.lg in c('logistic_quartile_nhanes_weighted','logistic_tertile_nhanes_weighted','logistic_binary_nhanes_weighted',",
    "              'logistic_quartile_glm','logistic_tertile_glm','logistic_binary_glm',",
    "              'logistic_quartile','logistic_tertile','logistic_binary')) {",
    "  if (!is.null(config[[.lg]])) {",
    "    config[[.lg]]$gate_enable <- FALSE",
    "    config[[.lg]]$stop_if_crude_all_ns <- FALSE",
    "    config[[.lg]]$stop_if_crude_highest_ns <- FALSE",
    "  }",
    "}",
    "for (.cx in c('cox_quartile','cox_tertile','cox_binary')) {",
    "  if (is.null(config[[.cx]])) config[[.cx]] <- list()",
    "  config[[.cx]]$stop_if_crude_highest_ns <- FALSE",
    "  config[[.cx]]$stop_if_crude_all_ns <- FALSE",
    "  config[[.cx]]$require_both_models_sig <- FALSE",
    "  config[[.cx]]$model1_factors <- as.character(.m1)",
    "  if (length(.m2)) config[[.cx]]$model2_factors <- as.character(.m2)",
    "  config[[.cx]]$covariate_search <- list(enable = FALSE, prefer_full_first = FALSE)",
    "  config[[.cx]]$export_baseline_by_group <- FALSE",
    "}",
    "for (.lg in c('logistic_quartile_nhanes_weighted','logistic_tertile_nhanes_weighted','logistic_binary_nhanes_weighted',",
    "              'logistic_quartile_glm','logistic_tertile_glm','logistic_binary_glm',",
    "              'logistic_quartile','logistic_tertile','logistic_binary')) {",
    "  if (is.null(config[[.lg]])) next",
    "  config[[.lg]]$model1_factors <- as.character(.m1)",
    "  if (length(.m2)) config[[.lg]]$model2_factors <- as.character(.m2)",
    "}"
  )
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, out_path)
  invisible(out_path)
}

# ── 单场景 × 单指标 ─────────────────────────────────────────────────────────
incidence_sensitivity_run_one <- function(root, config, config_path, ix, sg,
                                          db_mode, parent_dir,
                                          worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                          scheme = "quartile") {
  bc <- utils::modifyList(
    config$incidence_batch %||% list(),
    config$survival_batch %||% list()
  )
  output_base  <- bc$output_base %||% config$project$output_dir
  staging_root <- file.path(output_base, ".sensitivity_staging")
  staging_run  <- file.path(staging_root, paste0(ix, "__", sg$label))
  if (dir.exists(staging_run)) unlink(staging_run, recursive = TRUE)
  dir.create(staging_run, recursive = TRUE, showWarnings = FALSE)

  ix_ck_base <- .incidence_sensitivity_abs_ck(
    bc$index_ck_base %||% "checkpoints/_by_index", config_path
  )
  sens_ck_base <- file.path(dirname(ix_ck_base), "by_index_sensitivity", ix, sg$label)
  db_names <- .incidence_sensitivity_db_names(config)
  if (db_mode %in% c("nhanes", "nhanes_only") && length(db_names)) {
    db_names <- db_names[1L]
  } else if (db_mode %in% c("mimic", "mimic_only") && length(db_names)) {
    db_names <- db_names[length(db_names)]
  }
  study_type <- if (grepl("survival", worker_script, ignore.case = TRUE)) {
    "prognosis"
  } else {
    "incidence"
  }
  zh_desc <- incidence_sensitivity_zh_desc(sg$label)
  scheme <- as.character(scheme %||% "quartile")[1L]

  copy_ok <- TRUE
  cc_mode <- incidence_sensitivity_is_complete_case(sg)
  cc_vars <- as.character(sg$required_vars %||% character(0))
  if (cc_mode && !length(cc_vars)) {
    mc0 <- incidence_sensitivity_load_main_covariates(parent_dir, ix)
    cc_vars <- incidence_sensitivity_complete_case_vars(config, ix, mc0$m1, mc0$m2)
  }
  for (db in db_names) {
    resolved <- .incidence_sensitivity_resolve_imputed_src(ix_ck_base, ix, db)
    src_ck <- resolved$dir
    dest_ck <- file.path(sens_ck_base, ix, db)
    ok <- tryCatch({
      if (cc_mode) {
        incidence_sensitivity_copy_unimputed_cc_ck(src_ck, dest_ck, cc_vars)
      } else {
        incidence_sensitivity_copy_imputed_ck(src_ck, dest_ck)
      }
      # 从共享层拷贝时按指标剔 NA
      if (isTRUE(resolved$from_shared) &&
          exists("incidence_batch_apply_filter_and_trim", mode = "function")) {
        idx_p0 <- file.path(dest_ck, "index.rds")
        if (file.exists(idx_p0)) {
          incidence_batch_apply_filter_and_trim(idx_p0, ix, 0)
        }
      }
      TRUE
    }, error = function(e) {
      cli::cli_alert_danger("[{ix}/{sg$label}] 拷贝主分析 ck 失败 [{db}]: {e$message}")
      FALSE
    })
    if (!isTRUE(ok)) {
      copy_ok <- FALSE
      next
    }
    idx_p <- file.path(dest_ck, "index.rds")
    if (!cc_mode && file.exists(idx_p) && nzchar(as.character(sg$expr %||% "")[1L]) &&
        exists("incidence_batch_apply_subgroup_filter", mode = "function")) {
      incidence_batch_apply_subgroup_filter(idx_p, sg$expr, ix)
    }
    leftover_imp <- list.files(dest_ck, pattern = "imputation\\.rds$", full.names = TRUE)
    if (length(leftover_imp) && file.exists(idx_p)) {
      idx_obj <- tryCatch(readRDS(idx_p), error = function(e) NULL)
      if (!is.null(idx_obj)) {
        for (lp in leftover_imp) saveRDS(idx_obj, lp)
      }
    }
  }

  main_cov <- incidence_sensitivity_load_main_covariates(parent_dir, ix)
  cli::cli_alert_info(
    "  锁定主分析 Table 2 协变量 Model1={paste(main_cov$m1, collapse=', ')} | Model2={paste(main_cov$m2, collapse=', ')}"
  )
  t1_union <- character(0)
  for (db in db_names) {
    t1_union <- union(
      t1_union,
      incidence_sensitivity_read_table1_analysis_vars(parent_dir, db)
    )
  }
  mini <- list(
    dual_db = list(harmonization = list(
      harmonized_model1_nhanes = main_cov$m1,
      harmonized_model1_mimic  = main_cov$m1,
      harmonized_model2_nhanes = main_cov$m2,
      harmonized_model2_mimic  = main_cov$m2
    )),
    baseline_binary = list(include_vars = t1_union),
    baseline_nhanes = list(include_vars = t1_union)
  )
  for (db in db_names) {
    idx_p <- file.path(sens_ck_base, ix, db, "index.rds")
    df <- tryCatch({
      obj <- readRDS(idx_p)
      if (cc_mode) {
        incidence_sensitivity_unimputed_df(obj) %||% obj$ctx$data$imputed
      } else {
        obj$ctx$data$imputed %||% {
          if (exists("incidence_batch_ctx_data", mode = "function")) {
            incidence_batch_ctx_data(obj$ctx)
          } else {
            NULL
          }
        }
      }
    }, error = function(e) NULL)
    if (is.data.frame(df)) {
      mini <- incidence_sensitivity_drop_constant_from_config(mini, df)
    }
  }
  main_cov$m1 <- as.character(
    mini$dual_db$harmonization$harmonized_model1_nhanes %||% main_cov$m1
  )
  main_cov$m2 <- as.character(
    mini$dual_db$harmonization$harmonized_model2_nhanes %||% main_cov$m2
  )
  main_cov$table1_vars <- as.character(
    mini$baseline_binary$include_vars %||% t1_union
  )

  temp_config <- file.path(staging_run, "sensitivity_config.R")
  incidence_sensitivity_write_config(
    config_path, staging_run, sens_ck_base, sg, temp_config,
    main_covariates = main_cov, scheme = scheme, zh_desc = zh_desc
  )

  log_path <- file.path(staging_run, "worker.log")
  p_trim <- as.numeric(
    (config$incidence_batch %||% list())$trim_quantile %||%
      (config$survival_batch %||% list())$trim_quantile %||% 0
  )
  if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0
  cli::cli_h2("敏感性 [{ix}/{sg$label}] db_mode={db_mode}")
  cli::cli_alert_info("  过滤表达式: {sg$expr}")

  rc <- NA_integer_
  if (isTRUE(copy_ok)) {
    rc <- incidence_subgroup_spawn_worker(root, temp_config, ix, db_mode, log_path,
                                          worker_script = worker_script,
                                          p_trim = p_trim)
  } else {
    writeLines(
      if (cc_mode) {
        "敏感性轻量路径：未插补完整病例 checkpoint 缺失，未派发 worker"
      } else {
        "敏感性轻量路径：主分析插补后 checkpoint 缺失，未派发 worker"
      },
      log_path
    )
  }

  st <- if (exists("incidence_subgroup_read_status", mode = "function")) {
    incidence_subgroup_read_status(staging_run, ix)
  } else {
    list(status = "unknown")
  }

  src <- file.path(staging_run, "by_index", ix)
  s_nums <- incidence_sensitivity_resolve_pub_s_nums(parent_dir = parent_dir)
  cli::cli_alert_info(
    "[{ix}/{sg$label}] 敏感性表号顺延自主 Tables：基线 S{s_nums$baseline} / 关联 S{s_nums$association}"
  )
  for (db in db_names) {
    td <- file.path(src, db, "Tables")
    # 单库两阶段：表在 by_index/<ix>/Tables，无库子目录
    if (!dir.exists(td)) td <- file.path(src, "Tables")
    incidence_sensitivity_rename_pub_tables(
      td, db, zh_desc, study_type,
      parent_dir = parent_dir,
      s_baseline = s_nums$baseline,
      s_association = s_nums$association,
      label = sg$label
    )
    incidence_sensitivity_keep_pub_tables(td)
  }
  incidence_sensitivity_sync_combined_tables(src, db_names)
  incidence_sensitivity_keep_pub_tables(file.path(src, "Tables"))

  .ctx_for_db <- function(db) {
    ctx <- .incidence_sensitivity_latest_ctx(file.path(sens_ck_base, ix, db))
    if (is.null(ctx)) ctx <- .incidence_sensitivity_latest_ctx(file.path(src, db))
    ctx %||% list()
  }
  .p_for_db <- function(db) {
    incidence_sensitivity_model2_primary_p(.ctx_for_db(db))
  }
  .p_crude_for_db <- function(db) {
    incidence_sensitivity_crude_highest_p(.ctx_for_db(db))
  }
  p_primary <- if (length(db_names)) .p_for_db(db_names[[1L]]) else NA_real_
  p_secondary <- if (length(db_names) >= 2L) .p_for_db(db_names[[2L]]) else p_primary
  p_crude_primary <- if (length(db_names)) .p_crude_for_db(db_names[[1L]]) else NA_real_
  p_crude_secondary <- if (length(db_names) >= 2L) {
    .p_crude_for_db(db_names[[2L]])
  } else {
    p_crude_primary
  }

  .has_s <- function(root_dir, s_num) {
    pat <- sprintf("Table S%d", as.integer(s_num)[1L])
    if (!length(db_names)) {
      return(length(list.files(file.path(root_dir, "Tables"), pattern = pat)) > 0L)
    }
    all(vapply(db_names, function(db) {
      td <- file.path(root_dir, db, "Tables")
      n <- if (dir.exists(td)) length(list.files(td, pattern = pat)) else 0L
      if (!n) {
        n <- length(list.files(file.path(root_dir, "Tables"),
                               pattern = paste0(pat, "-", db), ignore.case = TRUE))
      }
      n > 0L
    }, logical(1)))
  }
  ok_t1 <- isTRUE(dir.exists(src)) && .has_s(src, s_nums$baseline)
  ok_t2 <- isTRUE(dir.exists(src)) && .has_s(src, s_nums$association)
  # 完整病例：不强制 Model2；所有场景均要求两库最高分位 Crude 显著
  require_sig <- !isTRUE(incidence_sensitivity_is_complete_case(sg))
  status <- incidence_sensitivity_judge_status(
    ok_t1, ok_t2, p_primary, p_secondary, require_sig = require_sig,
    p_crude_primary = p_crude_primary, p_crude_secondary = p_crude_secondary,
    require_crude_highest_sig = TRUE
  )
  if (status == "success") {
    cli::cli_alert_success("[{ix}/{sg$label}] 敏感性分析成功")
  } else {
    cli::cli_alert_danger(
      "[{ix}/{sg$label}] 敏感性分析失败 (t1={ok_t1}, t2={ok_t2}, p1={p_primary}, p2={p_secondary}, crude1={p_crude_primary}, crude2={p_crude_secondary}, rc={rc})"
    )
    cli::cli_alert_info("  详见日志: {.file {log_path}}")
  }

  sens_parent <- file.path(parent_dir, "sensitivity")
  dir.create(sens_parent, recursive = TRUE, showWarnings = FALSE)
  for (old_st in c("success", "failed")) {
    old <- file.path(sens_parent, incidence_batch_output_dir_name(sg$label, old_st))
    if (dir.exists(old)) unlink(old, recursive = TRUE)
  }
  bare <- file.path(sens_parent, sg$label)
  if (dir.exists(bare)) unlink(bare, recursive = TRUE)
  dst <- file.path(sens_parent, incidence_batch_output_dir_name(sg$label, status))
  if (dir.exists(src)) {
    .incidence_sensitivity_move_dir(src, dst)
  } else {
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
  }
  if (!identical(status, "success") && file.exists(log_path)) {
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    tryCatch(file.copy(log_path, file.path(dst, "worker.log"), overwrite = TRUE),
             error = function(e) NULL)
  }
  unlink(staging_run, recursive = TRUE)

  list(
    index = ix, label = sg$label, status = status, db_mode = db_mode,
    rc = rc, raw_status = st$status, ns = sg$ns,
    p_primary = p_primary, p_secondary = p_secondary,
    nhanes_or = st$nhanes_or %||% NA, mimic_or = st$mimic_or %||% NA,
    n_nhanes_after = st$n_nhanes_after %||% NA, n_mimic_after = st$n_mimic_after %||% NA,
    log_path = log_path
  )
}

# ── 单指标：遍历所有敏感性场景 ───────────────────────────────────────────────
incidence_sensitivity_for_index <- function(root, config, config_path, ix,
                                            worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                            force = FALSE, only_labels = NULL) {
  sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
  if (!isTRUE(sens$enable)) {
    sens <- (config$survival_batch %||% list())$sensitivity_suite %||% list()
    if (!isTRUE(sens$enable)) return(invisible(NULL))
  }

  bc <- utils::modifyList(
    config$incidence_batch %||% list(),
    config$survival_batch %||% list()
  )
  output_base  <- bc$output_base %||% config$project$output_dir
  by_index_dir <- file.path(output_base, "by_index")
  parent <- .incidence_sensitivity_find_index_parent(by_index_dir, ix)
  if (is.null(parent)) {
    cli::cli_alert_warning("[{ix}] 找不到 by_index 父目录，跳过敏感性分析")
    return(invisible(NULL))
  }

  main_ck_base <- .incidence_sensitivity_abs_ck(
    bc$index_ck_base %||% "checkpoints/_by_index", config_path
  )
  db_names <- .incidence_sensitivity_db_names(config)
  scenarios <- incidence_sensitivity_scenarios_for_index(
    config, parent, main_ck_base, ix, db_names
  )
  only_labels <- unique(as.character(
    c(only_labels %||% character(0), sens$only_labels %||% character(0))
  ))
  only_labels <- only_labels[nzchar(only_labels)]
  if (length(only_labels)) {
    keep <- vapply(scenarios, function(s) {
      as.character(s$label %||% "")[1L] %in% only_labels
    }, logical(1L))
    scenarios <- scenarios[keep]
  }
  if (!length(scenarios)) {
    cli::cli_alert_info("[{ix}] 未发现可跑的敏感性场景，跳过")
    return(invisible(NULL))
  }
  cli::cli_alert_info(
    "[{ix}] 敏感性场景: {paste(vapply(scenarios, function(s) s$label, character(1)), collapse = ', ')}"
  )

  scheme <- .incidence_sensitivity_scheme_from_status(parent)
  results <- list()
  for (sg in scenarios) {
    succ_dir <- file.path(
      parent, "sensitivity",
      incidence_batch_output_dir_name(sg$label, "success")
    )
    if (dir.exists(succ_dir) && !isTRUE(force)) {
      cli::cli_alert_info("[{ix}/{sg$label}] 已成功，跳过")
      next
    }
    if (isTRUE(force) && dir.exists(succ_dir)) {
      cli::cli_alert_info("[{ix}/{sg$label}] --no-skip，重跑已成功敏感性")
    }
    ns <- list()
    cc_one <- incidence_sensitivity_is_complete_case(sg)
    for (db in db_names) {
      df <- tryCatch({
        if (cc_one) {
          incidence_sensitivity_load_unimputed(main_ck_base, ix, db)
        } else {
          incidence_sensitivity_load_imputed(main_ck_base, ix, db)
        }
      }, error = function(e) NULL)
      if (cc_one && is.data.frame(df)) {
        cc_vars <- as.character(sg$required_vars %||% character(0))
        keep <- incidence_sensitivity_complete_case_keep(df, cc_vars)
        ns[[db]] <- sum(keep)
      } else {
        ns[[db]] <- if (is.data.frame(df)) nrow(df) else NA_integer_
      }
    }
    if (length(ns) >= 1L) ns$nhanes <- ns[[1L]]
    if (length(ns) >= 2L) ns$mimic <- ns[[2L]]
    sg$ns <- ns
    db_mode_run <- tolower(as.character(
      (config$incidence_batch %||% list())$db_mode %||%
        (config$survival_batch %||% list())$db_mode %||% ""
    )[1L])
    if (!nzchar(db_mode_run) || identical(db_mode_run, "both")) {
      # 与 .incidence_sensitivity_db_names 对齐：单库勿派 both
      if (length(db_names) <= 1L) db_mode_run <- "nhanes"
      else db_mode_run <- "both"
    }
    if (db_mode_run %in% c("nhanes", "nhanes_only", "primary")) {
      db_mode_run <- "nhanes"
    } else if (db_mode_run %in% c("mimic", "mimic_only", "regular", "secondary")) {
      db_mode_run <- "mimic"
    } else {
      db_mode_run <- "both"
    }
    res <- incidence_sensitivity_run_one(
      root, config, config_path, ix, sg, db_mode_run, parent,
      worker_script = worker_script, scheme = scheme
    )
    results[[length(results) + 1L]] <- res
  }
  invisible(results)
}

# ── 扫描 by_index，返回主分析 success 的指标名 ───────────────────────────────
incidence_sensitivity_find_success_indices <- function(output_base, only_index = NULL) {
  by_index_dir <- file.path(output_base, "by_index")
  if (!dir.exists(by_index_dir)) return(character(0))

  dirs <- list.dirs(by_index_dir, recursive = FALSE, full.names = TRUE)
  ix <- character(0)
  for (d in dirs) {
  status_path <- file.path(d, "_batch_status.json")
    if (!file.exists(status_path)) next
    st <- tryCatch(jsonlite::fromJSON(status_path), error = function(e) NULL)
    if (is.null(st) || !identical(st$status, "success")) next
    ix <- c(ix, as.character(st$index %||% basename(d)))
  }
  ix <- unique(ix[nzchar(ix)])
  if (!is.null(only_index) && length(only_index)) {
    only_index <- trimws(as.character(only_index))
    ix <- intersect(ix, only_index)
  }
  ix
}

# ── 打印敏感性汇总 ───────────────────────────────────────────────────────────
incidence_sensitivity_summary_n <- function(r, db = c("nhanes", "mimic")) {
  db <- match.arg(db)
  key <- if (identical(db, "nhanes")) "n_nhanes_after" else "n_mimic_after"
  v <- if (is.list(r)) r[[key]] else NULL
  if (is.null(v) || length(v) < 1L) return(NA)
  v[[1L]]
}

.incidence_sensitivity_print_summary <- function(all_results, output_base) {
  rows <- list()
  for (ix in names(all_results)) {
    rs <- all_results[[ix]]
    if (!length(rs)) next
    for (r in rs) {
      rows[[length(rows) + 1L]] <- data.frame(
        index = ix, scenario = r$label, status = r$status,
        db_mode = as.character(r$db_mode %||% "")[1L],
        n_eicu = incidence_sensitivity_summary_n(r, "nhanes"),
        n_mimic = incidence_sensitivity_summary_n(r, "mimic"),
        p_primary = {
          v <- r$p_primary %||% NA
          if (length(v) < 1L) NA else v[[1L]]
        },
        p_secondary = {
          v <- r$p_secondary %||% NA
          if (length(v) < 1L) NA else v[[1L]]
        },
        nhanes_or = {
          v <- r$nhanes_or %||% NA
          if (length(v) < 1L) NA else v[[1L]]
        },
        mimic_or = {
          v <- r$mimic_or %||% NA
          if (length(v) < 1L) NA else v[[1L]]
        },
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    cli::cli_alert_info("敏感性分析：无场景实际执行")
    return(invisible(NULL))
  }
  df <- do.call(rbind, rows)
  cli::cli_h2("敏感性分析汇总")
  n_succ <- sum(df$status == "success", na.rm = TRUE)
  cli::cli_alert_success("成功: {n_succ} / {nrow(df)}")
  print(df, row.names = FALSE)

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Sensitivity_summary.csv")
  if (file.exists(csv_path)) {
    old <- tryCatch(
      utils::read.csv(csv_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
      error = function(e) NULL
    )
    if (is.data.frame(old) && nrow(old) && all(c("index", "scenario") %in% names(old))) {
      key_new <- paste(df$index, df$scenario, sep = "\t")
      key_old <- paste(old$index, old$scenario, sep = "\t")
      keep <- !key_old %in% key_new
      df <- rbind(old[keep, intersect(names(old), names(df)), drop = FALSE], df)
    }
  }
  tryCatch(
    utils::write.csv(df, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("敏感性汇总 CSV 写入失败: {e$message}")
  )
  if (file.exists(csv_path)) cli::cli_alert_success("敏感性汇总表: {.file {csv_path}}")
  invisible(df)
}

# ── 顶层：对一批 success 指标跑敏感性 ────────────────────────────────────────
incidence_sensitivity_pass <- function(root, config, indices = NULL,
                                       config_path = NULL, only_index = NULL,
                                       worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                       force = FALSE, only_labels = NULL) {
  if (!incidence_sensitivity_suite_enabled(config)) {
    cli::cli_alert_info("sensitivity_suite$enable=FALSE，跳过敏感性分析")
    return(invisible(NULL))
  }
  if (is.null(config_path) || !nzchar(config_path)) {
    config_path <- file.path(root, "configs/config_incidence_dual_batch.R")
  }

  bc <- utils::modifyList(
    config$incidence_batch %||% list(),
    config$survival_batch %||% list()
  )
  output_base <- bc$output_base %||% config$project$output_dir
  if (is.null(indices) || !length(indices)) {
    indices <- incidence_sensitivity_find_success_indices(output_base, only_index)
  } else {
    indices <- unique(as.character(indices)[nzchar(as.character(indices))])
    if (!is.null(only_index) && length(only_index))
      indices <- intersect(indices, trimws(as.character(only_index)))
  }
  if (!length(indices)) {
    cli::cli_alert_info("无 success 指标，跳过敏感性分析")
    return(invisible(NULL))
  }

  cli::cli_h1("敏感性分析（指标: {paste(indices, collapse=', ')}）")
  all_results <- list()
  for (ix in indices) {
    all_results[[ix]] <- incidence_sensitivity_for_index(
      root, config, config_path, ix,
      worker_script = worker_script, force = force,
      only_labels = only_labels
    )
    # 敏感性跑完后刷新主目录步骤说明（补全「五、敏感性分析」场景列表）
    if (exists("incidence_write_pipeline_brief", mode = "function")) {
      ix_dir <- .incidence_sensitivity_find_index_parent(
        file.path(output_base, "by_index"), ix
      )
      if (!is.null(ix_dir) && dir.exists(ix_dir)) {
        tryCatch(
          incidence_write_pipeline_brief(ix_dir, config = config, ix = ix),
          error = function(e) cli::cli_alert_warning("刷新 Pipeline_steps_brief 失败: {e$message}")
        )
      }
    }
  }
  .incidence_sensitivity_print_summary(all_results, output_base)
  invisible(all_results)
}
