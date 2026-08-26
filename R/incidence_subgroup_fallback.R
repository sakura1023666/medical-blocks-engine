###############################################################################
#  incidence_subgroup_fallback.R — 失败指标「亚组补救重跑」
#
#  触发：批量主流程跑完后，对每个【failed】指标，按 config$incidence_batch$
#        subgroup_fallback 声明的亚组，把人群剔除一部分后重跑整个双库发病流程。
#
#  机制（复用现有 worker，不重写双库编排）：
#    1. 生成一份「亚组 config」：source 基础 config 后注入
#       - config$incidence_batch$.subgroup_fallback_expr  （亚组行过滤表达式）
#       - config$incidence_batch$output_base / index_ck_base（重定向到亚组专属目录）
#    2. 以子进程调起 run_incidence_dual_batch_worker.R（与 dispatcher 同一入口）。
#       worker 复制 shared ck 后，按 .subgroup_fallback_expr 原地剔除行
#       （incidence_batch_apply_subgroup_filter），再跑 imputation→mediation 全流程。
#    3. 读 worker 的 _batch_status.json 判定 success/failed，
#       把产物平移到 by_index/【failed】<ix>/<Label>/ 下并打 【status】<Label> 标，
#       最后把父目录改名为 【failed_subgr_<succ>_succ】<ix>。
#
#  依赖（调用方须先 source）：utils.R, incidence_dual_batch_runner.R
###############################################################################

# ── 占位符解析：年龄切点 / 肥胖标准 接口 ─────────────────────────────────────
incidence_subgroup_obesity_cut <- function(standard) {
  standard <- tolower(as.character(standard)[1L])
  if (identical(standard, "western")) 30L else 28L  # 缺省/非 western → 中国标准 BMI>=28
}

# 取亚组表达式里引用的列名（all.vars 自动剔除函数名/运算符/字符串常量）
incidence_subgroup_required_vars <- function(expr) {
  tryCatch(all.vars(parse(text = expr)), error = function(e) character(0))
}

# 合并 incidence_batch / survival_batch 配置段（预后 batch 复用同一套补救逻辑）
.incidence_batch_cfg <- function(config) {
  utils::modifyList(
    config$incidence_batch %||% list(),
    config$survival_batch %||% list()
  )
}

# 展开 config 里的亚组列表：替换占位符 {age_cutoff}/{age_mid_lower}/{obesity_cut}
incidence_subgroup_resolve <- function(config) {
  sgfb <- .incidence_batch_cfg(config)$subgroup_fallback %||% list()
  subs <- sgfb$subgroups %||% list()
  if (!length(subs)) return(list())

  vals <- list(
    age_cutoff    = as.character(sgfb$age_cutoff %||% 65),
    age_mid_lower = as.character(sgfb$age_mid_lower %||% 45),
    obesity_cut   = as.character(incidence_subgroup_obesity_cut(sgfb$obesity_standard))
  )
  .sub <- function(t) {
    for (nm in names(vals)) t <- gsub(paste0("\\{", nm, "\\}"), vals[[nm]], t)
    t
  }

  out <- lapply(subs, function(s) {
    label <- .sub(as.character(s$label %||% "")[1L])
    expr  <- .sub(as.character(s$expr %||% "")[1L])
    list(label = label, expr = expr)
  })
  out[nzchar(vapply(out, function(x) x$label, character(1)))]
}

# ── shared ck 读取（用于判列存在性 + 可分析样本量）──────────────────────────
incidence_subgroup_load_shared <- function(config, db) {
  ck_dir <- incidence_batch_shared_ck_dir(config, db)
  path   <- file.path(ck_dir, "index.rds")
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(NULL)
  df <- incidence_batch_ctx_data(obj$ctx)
  if (is.null(df) || !is.data.frame(df)) return(NULL)
  # data_clean 常丢掉 T2DM/Diabetes；从同行序 raw 补回，供亚组/敏感性样本量判定
  raw <- obj$ctx$data$raw
  if (is.data.frame(raw) && nrow(raw) == nrow(df)) {
    prefer <- intersect(
      setdiff(names(raw), names(df)),
      c("T2DM", "Diabetes", "Hypertension", "Age", "Gender", "Sex",
        "BMI", "Smoke", "Smoking", "CKD", "Heart_Failure", "COPD", "Cancer")
    )
    if (length(prefer)) df[prefer] <- raw[prefer]
  }
  if (exists("pipeline_normalize_yes_no_factors", mode = "function")) {
    df <- pipeline_normalize_yes_no_factors(df)
  }
  list(df = df, cols = names(df))
}

# 该亚组在某库的可分析样本量：落入亚组 且 指标 ix 非 NA 的行数；不可算返回 NA
incidence_subgroup_eval_n <- function(df, expr, ix) {
  if (is.null(df) || !is.data.frame(df)) return(NA_integer_)
  if (!ix %in% names(df)) return(NA_integer_)
  need <- incidence_subgroup_required_vars(expr)
  if (!all(need %in% names(df))) return(NA_integer_)
  keep <- tryCatch(eval(parse(text = expr), envir = df), error = function(e) NA)
  if (is.null(keep) || length(keep) != nrow(df)) return(NA_integer_)
  keep <- as.logical(keep); keep[is.na(keep)] <- FALSE
  as.integer(sum(keep & !is.na(df[[ix]])))
}

# 决定该亚组可跑哪些库（列齐全 且 样本 >= min_n）
incidence_subgroup_decide_dbs <- function(shared, expr, ix, min_n) {
  ns <- list(); dbs <- character(0)
  for (db in names(shared)) {
    n  <- incidence_subgroup_eval_n(shared[[db]]$df, expr, ix)
    ns[[db]] <- n
    if (!is.na(n) && n >= min_n) dbs <- c(dbs, db)
  }
  db_mode <- if (all(c("nhanes", "mimic") %in% dbs)) "both"
             else if ("nhanes" %in% dbs) "nhanes"
             else if ("mimic"  %in% dbs) "mimic"
             else NA_character_
  list(dbs = dbs, ns = ns, db_mode = db_mode)
}

# ── 生成亚组临时 config（source 基础 config + 注入覆盖）──────────────────────
# 同敏感性：worker --config 指向临时文件时会把研究根误解析为 staging，
# source 后强制写回真实研究根的 shared_ck / Data / checkpoint 路径。
incidence_subgroup_write_config <- function(base_config_path, staging_run,
                                            subgroup_ck_base, sg, out_path) {
  .q <- function(x) deparse(as.character(x)[1L], width.cutoff = 500L)[1L]
  base_abs <- normalizePath(base_config_path, winslash = "/", mustWork = FALSE)
  study_root <- dirname(base_abs)
  study_ck <- file.path(study_root, "checkpoints")
  shared_ck <- file.path(study_ck, "_shared")
  ck_abs <- subgroup_ck_base
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
  lines <- c(
    "# AUTO-GENERATED by incidence_subgroup_fallback.R (subgroup rescue config)",
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
    "# 亚组补救不向飞书主结果表推送（避免污染主结果）",
    "config$feishu$enable <- FALSE"
  )
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, out_path)
  invisible(out_path)
}

# ── 同步调起 worker 子进程（前台等待）────────────────────────────────────────
# 注意：研究路径常含空格（如 "ischemic stroke"）。R 的 system2 在 Unix 上常走
# sh 重定向，空格会截断 --config / stdout 路径 → 瞬时 rc≠0、status=unknown。
# 与批量派发一致：优先 processx（argv 不经 shell）。
incidence_subgroup_spawn_worker <- function(root, temp_config, ix, db_mode, log_path,
                                            worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                            p_trim = 0) {
  worker_path <- file.path(root, worker_script)
  if (!file.exists(worker_path))
    stop("Worker 脚本不存在: ", worker_path, call. = FALSE)
  rscript <- file.path(R.home("bin"),
                       if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  p_trim <- suppressWarnings(as.numeric(p_trim %||% 0))
  if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0
  args <- c(
    normalizePath(worker_path,  winslash = "/", mustWork = TRUE),
    "--index", ix,
    "--db",    db_mode,
    "--ptrim", as.character(p_trim),
    "--config", normalizePath(temp_config, winslash = "/", mustWork = TRUE),
    normalizePath(root, winslash = "/", mustWork = TRUE)
  )
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)
  # 清空旧日志，避免追加混淆
  tryCatch(writeLines(character(0), log_path), error = function(e) NULL)

  if (requireNamespace("processx", quietly = TRUE)) {
    rc <- tryCatch({
      p <- processx::process$new(
        command = normalizePath(rscript, winslash = "/", mustWork = FALSE),
        args = args,
        stdout = log_path,
        stderr = "2>&1",
        supervise = TRUE
      )
      p$wait()
      as.integer(p$get_exit_status() %||% NA_integer_)
    }, error = function(e) {
      cli::cli_alert_warning("processx 派发失败，回退 system2: {e$message}")
      NA_integer_
    })
    if (is.finite(rc)) return(as.integer(rc))
  }

  # 回退：把 stdout 指到无空格临时文件，再拷回（避免 sh 截断路径）
  tmp_log <- tempfile(pattern = "worker_", fileext = ".log")
  on.exit({
    if (file.exists(tmp_log)) {
      tryCatch(file.copy(tmp_log, log_path, overwrite = TRUE), error = function(e) NULL)
      unlink(tmp_log)
    }
  }, add = TRUE)
  rc <- tryCatch(
    system2(normalizePath(rscript, winslash = "/", mustWork = FALSE),
            args = args, stdout = tmp_log, stderr = tmp_log, wait = TRUE),
    error = function(e) NA_integer_
  )
  as.integer(rc)
}

incidence_subgroup_read_status <- function(staging_run, ix) {
  p <- file.path(staging_run, "by_index", ix, "_batch_status.json")
  if (!file.exists(p)) return(list(status = "unknown"))
  st <- tryCatch(jsonlite::fromJSON(p), error = function(e) list(status = "parse_error"))
  as.list(st)
}

# ── 单个亚组 × 单个指标：跑、判定、平移产物 ─────────────────────────────────
incidence_subgroup_run_one <- function(root, config, config_path, ix, sg, db_mode, parent_dir,
                                       worker_script = "run/incidence/run_incidence_dual_batch_worker.R") {
  bc <- .incidence_batch_cfg(config)
  output_base   <- bc$output_base %||% config$project$output_dir
  staging_root  <- file.path(output_base, ".subgroup_staging")
  staging_run   <- file.path(staging_root, paste0(ix, "__", sg$label))
  if (dir.exists(staging_run)) unlink(staging_run, recursive = TRUE)
  dir.create(staging_run, recursive = TRUE, showWarnings = FALSE)

  ix_ck_base      <- bc$index_ck_base %||% "checkpoints/_by_index"
  subgroup_ck_base <- file.path(dirname(ix_ck_base), "by_index_subgroup", ix, sg$label)

  temp_config <- file.path(staging_run, "subgroup_config.R")
  incidence_subgroup_write_config(config_path, staging_run, subgroup_ck_base, sg, temp_config)

  log_path <- file.path(staging_run, "worker.log")
  p_trim <- as.numeric(
    (config$incidence_batch %||% list())$trim_quantile %||%
      (config$survival_batch %||% list())$trim_quantile %||% 0
  )
  if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0
  cli::cli_h2("亚组补救 [{ix}/{sg$label}] db_mode={db_mode}")
  cli::cli_alert_info("  过滤表达式: {sg$expr}")
  rc <- incidence_subgroup_spawn_worker(root, temp_config, ix, db_mode, log_path,
                                        worker_script = worker_script,
                                        p_trim = p_trim)

  st     <- incidence_subgroup_read_status(staging_run, ix)
  status <- if (identical(st$status, "success")) "success" else "failed"
  if (status == "success") {
    cli::cli_alert_success("[{ix}/{sg$label}] 补救成功")
  } else {
    cli::cli_alert_danger("[{ix}/{sg$label}] 补救失败 (worker status={st$status}, rc={rc})")
    cli::cli_alert_info("  详见日志: {.file {log_path}}")
  }

  # 平移 staging/by_index/<ix> → 父目录/<label>
  src <- file.path(staging_run, "by_index", ix)
  dst <- file.path(parent_dir, sg$label)
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
  unlink(staging_run, recursive = TRUE)

  list(ix = ix, label = sg$label, status = status, db_mode = db_mode,
       rc = rc, raw_status = st$status, ns = sg$ns)
}

# ── 目录命名工具 ────────────────────────────────────────────────────────────
# 定位某指标的 by_index 父目录（已重命名为【failed】<ix> / 已 retag / 裸 <ix>）
.incidence_subgroup_find_index_parent <- function(by_index_dir, ix) {
  if (!dir.exists(by_index_dir)) return(NULL)
  dirs <- list.dirs(by_index_dir, recursive = FALSE, full.names = TRUE)
  bns  <- basename(dirs)
  hit  <- dirs[endsWith(bns, paste0("】", ix))]   # 】<ix>
  if (!length(hit)) hit <- dirs[bns == ix]
  if (length(hit)) hit[1L] else NULL
}

# 把亚组目录 <label> 重命名为 【status】<label>
.incidence_subgroup_tag_subgroup <- function(parent_dir, label, status) {
  src <- file.path(parent_dir, label)
  dst <- file.path(parent_dir, incidence_batch_output_dir_name(label, status))
  if (!dir.exists(src)) return(invisible(FALSE))
  if (normalizePath(src, winslash = "/", mustWork = FALSE) ==
      normalizePath(dst, winslash = "/", mustWork = FALSE)) return(invisible(TRUE))
  if (dir.exists(dst)) unlink(dst, recursive = TRUE)
  tryCatch(file.rename(src, dst), error = function(e) {
    cli::cli_alert_warning("亚组目录打标失败 {label}: {e$message}")
    FALSE
  })
  invisible(TRUE)
}

# 汇总父目录名：扫描已打标的亚组目录，按成功集合命名（全部尝试分别报告）
.incidence_subgroup_retag_parent <- function(by_index_dir, ix, sep) {
  parent <- .incidence_subgroup_find_index_parent(by_index_dir, ix)
  if (is.null(parent)) return(invisible(NULL))

  sub_bns <- basename(list.dirs(parent, recursive = FALSE, full.names = FALSE))
  succ_prefix <- paste0("【", "success", "】")   # 【success】
  succ_labels <- sub(succ_prefix, "", sub_bns[startsWith(sub_bns, succ_prefix)], fixed = TRUE)
  ran_any     <- length(sub_bns) > 0L

  if (length(succ_labels) >= 1L) {
    new_leaf <- paste0("【failed_subgr_",
                       paste(succ_labels, collapse = sep),
                       "_succ】", ix)
  } else if (ran_any) {
    new_leaf <- paste0("【failed_subgr_allfail】", ix)
  } else {
    return(invisible(parent))   # 没跑出任何亚组目录，保持现状
  }

  new_path <- file.path(by_index_dir, new_leaf)
  if (normalizePath(parent,  winslash = "/", mustWork = FALSE) ==
      normalizePath(new_path, winslash = "/", mustWork = FALSE))
    return(invisible(parent))
  if (dir.exists(new_path)) unlink(new_path, recursive = TRUE)
  tryCatch({
    file.rename(parent, new_path)
    cli::cli_alert_info("  \U0001f4c1 {basename(parent)} → {new_leaf}")
  }, error = function(e) cli::cli_alert_warning("父目录重命名失败: {e$message}"))
  invisible(new_path)
}

# ── 单指标：遍历所有启用亚组 ─────────────────────────────────────────────────
incidence_subgroup_fallback_for_index <- function(root, config, config_path, ix,
                                                  worker_script = "run/incidence/run_incidence_dual_batch_worker.R") {
  bc   <- .incidence_batch_cfg(config)
  sgfb <- bc$subgroup_fallback %||% list()
  if (!isTRUE(sgfb$enable)) return(invisible(NULL))

  min_n <- sgfb$min_n_per_subgroup %||% 30
  sep   <- sgfb$sep %||% "|"

  output_base  <- bc$output_base %||% config$project$output_dir
  by_index_dir <- file.path(output_base, "by_index")
  parent <- .incidence_subgroup_find_index_parent(by_index_dir, ix)
  if (is.null(parent)) {
    cli::cli_alert_warning("[{ix}] 找不到 by_index 父目录，跳过亚组补救")
    return(invisible(NULL))
  }

  # 幂等：父目录已 retag（failed_subgr）→ 跳过
  if (grepl("failed_subgr", basename(parent), fixed = TRUE)) {
    cli::cli_alert_info("[{ix}] 已做过亚组补救（{basename(parent)}），跳过；如需重跑请先改名")
    return(invisible(NULL))
  }

  subgroups <- incidence_subgroup_resolve(config)
  if (!length(subgroups)) {
    cli::cli_alert_info("[{ix}] 未配置 subgroup_fallback$subgroups，跳过")
    return(invisible(NULL))
  }

  # 每库加载一次 shared ck，跨亚组复用
  shared <- list()
  for (db in c("nhanes", "mimic")) shared[[db]] <- incidence_subgroup_load_shared(config, db)

  results <- list()
  for (sg in subgroups) {
    # 幂等：该亚组已打标 → 跳过
    if (dir.exists(file.path(parent, incidence_batch_output_dir_name(sg$label, "success"))) ||
        dir.exists(file.path(parent, incidence_batch_output_dir_name(sg$label, "failed")))) {
      cli::cli_alert_info("[{ix}/{sg$label}] 已存在，跳过")
      next
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
    res <- incidence_subgroup_run_one(root, config, config_path, ix, sg, dec$db_mode, parent,
                                      worker_script = worker_script)
    .incidence_subgroup_tag_subgroup(parent, sg$label, res$status)
    results[[length(results) + 1L]] <- res
    if (!isTRUE(sgfb$try_all) && res$status == "success") break
  }

  .incidence_subgroup_retag_parent(by_index_dir, ix, sep)
  invisible(results)
}

# ── 打印补救汇总 ────────────────────────────────────────────────────────────
.incidence_subgroup_print_summary <- function(all_results) {
  rows <- list()
  for (ix in names(all_results)) {
    rs <- all_results[[ix]]
    if (!length(rs)) next
    for (r in rs) {
      rows[[length(rows) + 1L]] <- data.frame(
        index = ix, subgroup = r$label, status = r$status,
        db_mode = r$db_mode %||% "", stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    cli::cli_alert_info("亚组补救：无亚组实际执行")
    return(invisible(NULL))
  }
  df <- do.call(rbind, rows)
  cli::cli_h2("亚组补救汇总")
  n_succ <- sum(df$status == "success")
  cli::cli_alert_success("成功: {n_succ} / {nrow(df)}")
  print(df, row.names = FALSE)
  invisible(df)
}

# 扫描 by_index，返回所有「主流程失败、尚未补救」的指标名（【failed】<ix>，排除 failed_subgr 变体）
incidence_subgroup_find_failed_indices <- function(output_base) {
  by_index_dir <- file.path(output_base, "by_index")
  if (!dir.exists(by_index_dir)) return(character(0))
  bns <- basename(list.dirs(by_index_dir, recursive = FALSE, full.names = FALSE))
  failed <- bns[startsWith(bns, "【failed】")]   # 【failed】
  sub("【failed】", "", failed)                  # 去前缀得 ix
}

# ── 顶层：对一批失败指标跑补救 ───────────────────────────────────────────────
incidence_subgroup_fallback_pass <- function(root, config, failed_ix, config_path = NULL,
                                             worker_script = "run/incidence/run_incidence_dual_batch_worker.R") {
  bc   <- .incidence_batch_cfg(config)
  sgfb <- bc$subgroup_fallback %||% list()
  if (!isTRUE(sgfb$enable)) {
    cli::cli_alert_info("subgroup_fallback$enable 未开启，跳过亚组补救")
    return(invisible(NULL))
  }
  failed_ix <- unique(as.character(failed_ix)[nzchar(as.character(failed_ix))])
  if (!length(failed_ix)) {
    cli::cli_alert_info("无失败指标，跳过亚组补救")
    return(invisible(NULL))
  }

  cli::cli_h1("亚组补救重跑（失败指标: {paste(failed_ix, collapse=', ')}）")
  all_results <- list()
  for (ix in failed_ix) {
    all_results[[ix]] <- incidence_subgroup_fallback_for_index(root, config, config_path, ix,
                                                               worker_script = worker_script)
  }
  .incidence_subgroup_print_summary(all_results)
  invisible(all_results)
}
