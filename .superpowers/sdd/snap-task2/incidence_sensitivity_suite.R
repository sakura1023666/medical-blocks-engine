###############################################################################
#  incidence_sensitivity_suite.R — 主分析成功后的敏感性分析重跑
#
#  触发：批量主流程跑完后，对每个 success 指标，按 config$incidence_batch$
#        sensitivity_suite$scenarios 声明的队列过滤，重跑双库发病流程。
#
#  机制（复用 subgroup_fallback 的 worker 过滤与派发）：
#    1. 生成临时 config，注入 .subgroup_fallback_expr（cohort 行过滤）
#    2. 调 run_incidence_dual_batch_worker.R
#    3. 产物平移到 by_index/<ix>/sensitivity/<label>/
#
#  依赖：utils.R, incidence_dual_batch_runner.R, incidence_subgroup_fallback.R
###############################################################################

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
  if (startsWith(label, "SA_no_")) {
    var <- sub("^SA_no_", "", label)
    dn <- as.character((display_names %||% list())[[var]] %||% "")[1L]
    mp <- incidence_sensitivity_zh_var_map()
    zh <- if (nzchar(dn)) dn else (unname(mp[var]) %||% var)
    return(paste0("非", zh))
  }
  label
}

incidence_sensitivity_pub_stem <- function(s_num, db_tag, zh_desc, caption) {
  s_num <- as.integer(s_num)[1L]
  db_tag <- as.character(db_tag %||% "")[1L]
  zh_desc <- as.character(zh_desc)[1L]
  caption <- as.character(caption)[1L]
  db_part <- if (nzchar(db_tag)) paste0("-", db_tag) else ""
  sprintf(
    "Table S%d%s. Sensitivity analysis-%s. %s",
    s_num, db_part, zh_desc, caption
  )
}

incidence_sensitivity_judge_status <- function(ok_t1, ok_t2, p_primary, p_secondary,
                                               sig_cutoff = 0.05) {
  tables_ok <- isTRUE(ok_t1) && isTRUE(ok_t2)
  p1 <- suppressWarnings(as.numeric(p_primary)[1L])
  p2 <- suppressWarnings(as.numeric(p_secondary)[1L])
  sig_ok <- is.finite(p1) && is.finite(p2) &&
    p1 < sig_cutoff && p2 < sig_cutoff
  if (tables_ok && sig_ok) "success" else "failed"
}

# ── 展开 sensitivity_suite$scenarios（Task 2 前暂返回空 list）────────────────
incidence_sensitivity_resolve <- function(config) {
  list()
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

# ── 从主分析父目录读取 Gate B 锁定协变量（供敏感性锁同一套）────────────────
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
  fc_hits <- list.files(parent_dir, pattern = "^FinalCovariates_.*\\.txt$",
                        recursive = TRUE, full.names = TRUE)
  # 优先：带 Gate B locked 注释的 Tables/Summary；排除 sensitivity/staging
  fc_hits <- fc_hits[!grepl("sensitivity|\\.sensitivity_staging", fc_hits)]
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
  if (!length(m2)) {
    m2_hits <- list.files(parent_dir, pattern = "^Model2Factors\\.txt$",
                          recursive = TRUE, full.names = TRUE)
    m2_hits <- m2_hits[!grepl("sensitivity|\\.sensitivity_staging", m2_hits)]
    prefer <- grepl("multicollinearity_final|Tables/Summary|step12", m2_hits)
    if (any(prefer)) m2_hits <- c(m2_hits[prefer], m2_hits[!prefer])
    if (length(m2_hits)) m2 <- .read_cov(m2_hits[[1L]])
  }
  m1_hits <- list.files(parent_dir, pattern = "^Model1Factors\\.txt$",
                        recursive = TRUE, full.names = TRUE)
  m1_hits <- m1_hits[!grepl("sensitivity|\\.sensitivity_staging", m1_hits)]
  if (length(m1_hits)) m1 <- .read_cov(m1_hits[[1L]])
  if (!length(m1) && length(m2)) m1 <- intersect(m2, c("Age", "Gender", "Sex", "Race"))
  if (!length(m1)) m1 <- "Age"
  list(m1 = unique(m1[nzchar(m1)]), m2 = unique(m2[nzchar(m2)]))
}

# ── 生成敏感性临时 config ────────────────────────────────────────────────────
# 注意：worker 的 --config 指向本临时文件时，study config.R 会用
# dirname(--config) 当 .batch_project_root，误指向 staging，导致 shared_ck /
# Data 全部找不到。source 后必须强制写回真实研究根路径。
incidence_sensitivity_write_config <- function(base_config_path, staging_run,
                                               sensitivity_ck_base, sg, out_path,
                                               main_covariates = NULL) {
  .q <- function(x) deparse(as.character(x)[1L], width.cutoff = 500L)[1L]
  .qv <- function(x) {
    x <- as.character(x %||% character(0))
    x <- x[nzchar(x)]
    if (!length(x)) return("character(0)")
    paste0("c(", paste(vapply(x, .q, character(1)), collapse = ", "), ")")
  }
  base_abs <- normalizePath(base_config_path, winslash = "/", mustWork = FALSE)
  study_root <- dirname(base_abs)
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
  lines <- c(
    "# AUTO-GENERATED by incidence_sensitivity_suite.R",
    paste0(".local_base <- ", base_q),
    "source(.local_base)",
    paste0(".study_root <- ", sr_q),
    "config$project$output_dir <- .study_root",
    paste0("config$dual_db$checkpoint_base <- ", ckroot_q),
    paste0("config$dual_db$harmonization_dir <- ", harm_q),
    paste0("config$incidence_batch$shared_ck_base <- ", shared_q),
    paste0("config$incidence_batch$output_base   <- ", stg_q),
    paste0("config$incidence_batch$index_ck_base <- ", ck_q),
    paste0("config$incidence_batch$.subgroup_fallback_expr  <- ", ex_q),
    paste0("config$incidence_batch$.subgroup_fallback_label <- ", lb_q),
    "if (!is.null(config$dual_db$primary$rawdata_path)) {",
    "  .p <- config$dual_db$primary$rawdata_path",
    "  config$dual_db$primary$rawdata_path <- file.path(.study_root, 'Data', basename(dirname(.p)), basename(.p))",
    "}",
    "if (!is.null(config$dual_db$secondary$rawdata_path)) {",
    "  .p <- config$dual_db$secondary$rawdata_path",
    "  config$dual_db$secondary$rawdata_path <- file.path(.study_root, 'Data', basename(dirname(.p)), basename(.p))",
    "}",
    "if (!is.null(config$survival_batch)) {",
    "  config$survival_batch <- utils::modifyList(config$survival_batch, config$incidence_batch)",
    paste0("  config$survival_batch$shared_ck_base <- ", shared_q),
    paste0("  config$survival_batch$output_base   <- ", stg_q),
    paste0("  config$survival_batch$index_ck_base <- ", ck_q),
    "}",
    "config$feishu$enable <- FALSE",
    "# ── 敏感性：锁主分析 Gate B 协变量（禁止再扩成 VIF screen 长名单导致方向翻转）──",
    paste0(".m1 <- ", .qv(m1)),
    paste0(".m2 <- ", .qv(m2)),
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
    "if (exists('.table1_vars') && length(.table1_vars)) {",
    "  .tv <- as.character(.table1_vars)",
    "  if (!is.null(config$baseline_nhanes)) config$baseline_nhanes$include_vars <- .tv",
    "  if (!is.null(config$baseline_binary)) config$baseline_binary$include_vars <- .tv",
    "  if (!is.null(config$baseline)) config$baseline$include_vars <- .tv",
    "}",
    "if (!is.null(config$column_mapping)) config$column_mapping$enable <- TRUE",
    "# 敏感性子样本：关闭早停与过严 Cox gate（避免 COX_SEARCH_STOP / crude_ns 整场景失败）",
    "if (!is.null(config$baseline_nhanes)) config$baseline_nhanes$early_stop_if_index_ns <- FALSE",
    "if (!is.null(config$baseline_binary)) config$baseline_binary$early_stop_if_index_ns <- FALSE",
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
    "  if (!is.null(config[[.cx]])) {",
    "    config[[.cx]]$stop_if_crude_highest_ns <- FALSE",
    "    config[[.cx]]$stop_if_crude_all_ns <- FALSE",
    "    config[[.cx]]$require_both_models_sig <- FALSE",
    "    if (is.null(config[[.cx]]$covariate_search)) config[[.cx]]$covariate_search <- list()",
    "    config[[.cx]]$covariate_search$enable <- FALSE",
    "    config[[.cx]]$covariate_search$on_search_fail <- 'degrade'",
    "    if (!nzchar(as.character(config[[.cx]]$degrade_branch %||% '')[1L])) {",
    "      if (identical(.cx, 'cox_quartile')) config[[.cx]]$degrade_branch <- 'degrade_tertile'",
    "      if (identical(.cx, 'cox_tertile')) config[[.cx]]$degrade_branch <- 'degrade_binary'",
    "      if (identical(.cx, 'cox_binary')) config[[.cx]]$degrade_branch <- 'degrade_binary'",
    "    }",
    "  }",
    "}",
    "# 排除高血压人群：Hypertension 单水平 → 亚组不去该变量；Model2 去掉 Hypertension",
    paste0(".sg_label <- ", lb_q),
    "if (grepl('no_hypertension', .sg_label, ignore.case = TRUE)) {",
    "  .drop_sg <- function(x) setdiff(as.character(x %||% character(0)), 'Hypertension')",
    "  if (!is.null(config$subgroup_nhanes_weighted)) {",
    "    config$subgroup_nhanes_weighted$required_subgroup_vars <- .drop_sg(config$subgroup_nhanes_weighted$required_subgroup_vars)",
    "    config$subgroup_nhanes_weighted$locked_subgroup_vars   <- .drop_sg(config$subgroup_nhanes_weighted$locked_subgroup_vars)",
    "  }",
    "  if (!is.null(config$subgroup)) {",
    "    config$subgroup$required_subgroup_vars <- .drop_sg(config$subgroup$required_subgroup_vars)",
    "    config$subgroup$locked_subgroup_vars   <- .drop_sg(config$subgroup$locked_subgroup_vars)",
    "  }",
    "  if (!is.null(config$incidence_batch$base_subgroup_vars))",
    "    config$incidence_batch$base_subgroup_vars <- .drop_sg(config$incidence_batch$base_subgroup_vars)",
    "  .m2_sa <- setdiff(as.character(config$dual_db$harmonization$harmonized_model2_nhanes %||% character(0)), 'Hypertension')",
    "  if (!length(.m2_sa)) .m2_sa <- c('Age', 'WBC')",
    "  config$dual_db$harmonization$harmonized_model2_nhanes <- .m2_sa",
    "  config$dual_db$harmonization$harmonized_model2_mimic  <- .m2_sa",
    "  config$dual_db$harmonization$common_model_factors <- setdiff(.m2_sa, as.character(config$dual_db$harmonization$harmonized_model1_nhanes %||% 'Age'))",
    "}",
    "# 年龄分层敏感性：Age_Group 仅剩单水平 → 从亚组必选中移除",
    "if (grepl('age_(ge|lt)_', .sg_label, ignore.case = TRUE)) {",
    "  .drop_age <- function(x) setdiff(as.character(x %||% character(0)), c('Age_Group', 'Age'))",
    "  if (!is.null(config$subgroup_nhanes_weighted)) {",
    "    config$subgroup_nhanes_weighted$required_subgroup_vars <- .drop_age(config$subgroup_nhanes_weighted$required_subgroup_vars)",
    "    config$subgroup_nhanes_weighted$locked_subgroup_vars   <- .drop_age(config$subgroup_nhanes_weighted$locked_subgroup_vars)",
    "  }",
    "  if (!is.null(config$subgroup)) {",
    "    config$subgroup$required_subgroup_vars <- .drop_age(config$subgroup$required_subgroup_vars)",
    "    config$subgroup$locked_subgroup_vars   <- .drop_age(config$subgroup$locked_subgroup_vars)",
    "  }",
    "  if (!is.null(config$incidence_batch$base_subgroup_vars))",
    "    config$incidence_batch$base_subgroup_vars <- .drop_age(config$incidence_batch$base_subgroup_vars)",
    "}"
  )
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, out_path)
  invisible(out_path)
}

# ── 单场景 × 单指标 ─────────────────────────────────────────────────────────
incidence_sensitivity_run_one <- function(root, config, config_path, ix, sg,
                                          db_mode, parent_dir,
                                          worker_script = "run/incidence/run_incidence_dual_batch_worker.R") {
  bc <- config$incidence_batch %||% list()
  output_base  <- bc$output_base %||% config$project$output_dir
  staging_root <- file.path(output_base, ".sensitivity_staging")
  staging_run  <- file.path(staging_root, paste0(ix, "__", sg$label))
  if (dir.exists(staging_run)) unlink(staging_run, recursive = TRUE)
  dir.create(staging_run, recursive = TRUE, showWarnings = FALSE)

  ix_ck_base <- bc$index_ck_base %||% "checkpoints/_by_index"
  sens_ck_base <- file.path(dirname(ix_ck_base), "by_index_sensitivity", ix, sg$label)

  temp_config <- file.path(staging_run, "sensitivity_config.R")
  main_cov <- .incidence_sensitivity_load_main_covariates(parent_dir, ix)
  incidence_sensitivity_write_config(
    config_path, staging_run, sens_ck_base, sg, temp_config,
    main_covariates = main_cov
  )

  log_path <- file.path(staging_run, "worker.log")
  # 与主分析一致：未显式开极端值时 p_trim=0（不硬开）
  p_trim <- as.numeric(
    (config$incidence_batch %||% list())$trim_quantile %||%
      (config$survival_batch %||% list())$trim_quantile %||% 0
  )
  if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0
  cli::cli_h2("敏感性 [{ix}/{sg$label}] db_mode={db_mode}")
  cli::cli_alert_info("  过滤表达式: {sg$expr}")
  rc <- incidence_subgroup_spawn_worker(root, temp_config, ix, db_mode, log_path,
                                        worker_script = worker_script,
                                        p_trim = p_trim)

  st     <- incidence_subgroup_read_status(staging_run, ix)
  status <- if (identical(st$status, "success")) "success" else "failed"
  if (status == "success") {
    cli::cli_alert_success("[{ix}/{sg$label}] 敏感性分析成功")
  } else {
    cli::cli_alert_danger("[{ix}/{sg$label}] 敏感性分析失败 (status={st$status}, rc={rc})")
    cli::cli_alert_info("  详见日志: {.file {log_path}}")
  }

  sens_parent <- file.path(parent_dir, "sensitivity")
  dir.create(sens_parent, recursive = TRUE, showWarnings = FALSE)
  src <- file.path(staging_run, "by_index", ix)
  dst <- file.path(sens_parent, sg$label)
  if (dir.exists(src)) {
    if (dir.exists(dst)) unlink(dst, recursive = TRUE)
    ok <- tryCatch(file.rename(src, dst), error = function(e) FALSE)
    if (!ok) {
      tryCatch({
        dir.create(dst, recursive = TRUE, showWarnings = FALSE)
        file.copy(list.files(src, full.names = TRUE), dst, recursive = TRUE)
        unlink(src, recursive = TRUE)
      }, error = function(e) NULL)
    }
  }
  # 失败时保留 worker.log 到 sensitivity/<label>/，便于排查
  if (!identical(status, "success") && file.exists(log_path)) {
    fail_dir <- file.path(sens_parent, sg$label)
    dir.create(fail_dir, recursive = TRUE, showWarnings = FALSE)
    tryCatch(file.copy(log_path, file.path(fail_dir, "worker.log"), overwrite = TRUE),
             error = function(e) NULL)
  }
  unlink(staging_run, recursive = TRUE)

  list(
    index = ix, label = sg$label, status = status, db_mode = db_mode,
    rc = rc, raw_status = st$status, ns = sg$ns,
    nhanes_or = st$nhanes_or %||% NA, mimic_or = st$mimic_or %||% NA,
    n_nhanes_after = st$n_nhanes_after %||% NA, n_mimic_after = st$n_mimic_after %||% NA,
    log_path = log_path
  )
}

# ── 单指标：遍历所有敏感性场景 ───────────────────────────────────────────────
incidence_sensitivity_for_index <- function(root, config, config_path, ix,
                                            worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                            force = FALSE) {
  sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
  if (!isTRUE(sens$enable)) return(invisible(NULL))

  min_n <- sens$min_n_per_db %||% (config$incidence_batch$min_valid_per_db %||% 50L)
  output_base  <- (config$incidence_batch %||% list())$output_base %||% config$project$output_dir
  by_index_dir <- file.path(output_base, "by_index")
  parent <- .incidence_sensitivity_find_index_parent(by_index_dir, ix)
  if (is.null(parent)) {
    cli::cli_alert_warning("[{ix}] 找不到 by_index 父目录，跳过敏感性分析")
    return(invisible(NULL))
  }

  scenarios <- incidence_sensitivity_resolve(config)
  if (!length(scenarios)) {
    cli::cli_alert_info("[{ix}] 未配置 sensitivity_suite$scenarios，跳过")
    return(invisible(NULL))
  }

  shared <- list()
  for (db in c("nhanes", "mimic"))
    shared[[db]] <- incidence_subgroup_load_shared(config, db)

  results <- list()
  for (sg in scenarios) {
    dst <- file.path(parent, "sensitivity", sg$label)
    if (dir.exists(dst) && file.exists(file.path(dst, "_batch_status.json"))) {
      existing <- tryCatch(
        jsonlite::fromJSON(file.path(dst, "_batch_status.json")),
        error = function(e) NULL
      )
      if (!isTRUE(force) && !is.null(existing) && identical(existing$status, "success")) {
        cli::cli_alert_info("[{ix}/{sg$label}] 已成功，跳过")
        next
      }
      if (isTRUE(force) && !is.null(existing) && identical(existing$status, "success")) {
        cli::cli_alert_info("[{ix}/{sg$label}] --no-skip，重跑已成功敏感性")
      }
    }
    dec <- incidence_subgroup_decide_dbs(shared, sg$expr, ix, min_n)
    if (is.na(dec$db_mode) || !length(dec$dbs)) {
      ns_txt <- paste(
        names(dec$ns), "=",
        vapply(dec$ns, function(x) if (is.na(x)) "NA" else as.character(x), character(1)),
        collapse = ", "
      )
      cli::cli_alert_info("[{ix}/{sg$label}] 无可用库（缺列或样本<{min_n}：{ns_txt}），跳过")
      next
    }
    sg$ns <- dec$ns
    res <- incidence_sensitivity_run_one(root, config, config_path, ix, sg, dec$db_mode, parent,
                                         worker_script = worker_script)
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
.incidence_sensitivity_print_summary <- function(all_results, output_base) {
  rows <- list()
  for (ix in names(all_results)) {
    rs <- all_results[[ix]]
    if (!length(rs)) next
    for (r in rs) {
      .ns1 <- function(ns, key) {
        v <- if (is.null(ns)) NA else ns[[key]]
        if (is.null(v) || length(v) < 1L) NA else v[[1L]]
      }
      rows[[length(rows) + 1L]] <- data.frame(
        index = ix, scenario = r$label, status = r$status,
        db_mode = as.character(r$db_mode %||% "")[1L],
        n_eicu = .ns1(r$ns, "nhanes"),
        n_mimic = .ns1(r$ns, "mimic"),
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
                                       force = FALSE) {
  sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
  if (!isTRUE(sens$enable)) {
    cli::cli_alert_info("sensitivity_suite$enable 未开启，跳过敏感性分析")
    return(invisible(NULL))
  }
  if (is.null(config_path) || !nzchar(config_path)) {
    config_path <- file.path(root, "configs/config_incidence_dual_batch.R")
  }

  output_base <- (config$incidence_batch %||% list())$output_base %||% config$project$output_dir
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
      worker_script = worker_script, force = force
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
