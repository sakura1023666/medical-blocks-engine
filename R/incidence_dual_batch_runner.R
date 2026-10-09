###############################################################################
#  incidence_dual_batch_runner.R — 发病双库批量多指标编排引擎 v4
#
#  变更日志 v4:
#    - workers 自动推算：共享层结束、指标列表确定后，按 CPU + 内存动态计算并行路数
#    - processx 派发：替代 bash nohup，解决 WSL+Windows R 子进程不落地问题
#    - Phase 3 续跑：自动找实际最后落盘的 logistic checkpoint
#  变更日志 v3:
#    - 共享层跑完后从 checkpoint 读实际算出的指标，不再依赖预定义分组
#    - 路径转换工具函数提升到模块顶层，dispatch 和 resolve 共用
#  变更日志 v2:
#    - 共享层新增 dual_db_column_harmonize
#    - Gate A 在批量启动前预计算一次
#    - per-index worker 开始前过滤 NA 行 + 前后 1% 极端值
###############################################################################

# ── 系统资源探测 & Worker 数自动推算 ─────────────────────────────────────────
#  在共享层结束、指标列表确定后调用，根据 CPU + 可用内存 + 指标数三者取 min。
#
#  参数:
#    n_indices        — 本次要跑的指标数（workers 不超过这个上限）
#    ram_per_worker   — 每路 worker 预估内存占用 GB（默认 2.0）
#    cpu_headroom     — 保留给主进程 + OS 的逻辑 CPU 数（默认 2）
#    ram_headroom_gb  — 保留给主进程的内存 GB（默认 4）
#    max_workers      — 硬上限（NULL = 不限制）
#
#  返回: 推算出的 workers 整数，并在终端打印决策依据。
incidence_batch_auto_workers <- function(n_indices,
                                          ram_per_worker  = 2.0,
                                          cpu_headroom    = 2L,
                                          ram_headroom_gb = 4.0,
                                          max_workers     = NULL) {
  # ── 1. CPU 数 ──
  n_cpu <- tryCatch(parallel::detectCores(logical = TRUE), error = function(e) NA_integer_)
  if (is.na(n_cpu) || n_cpu < 1L) n_cpu <- 1L
  cpu_limit <- max(1L, as.integer(n_cpu) - as.integer(cpu_headroom))

  # ── 2. 可用内存（GB）──
  avail_gb <- NA_real_
  total_gb <- NA_real_

  # 方式 A：Windows wmic（Windows R / WSL 内运行 Windows Rscript.exe 均可用）
  if (is.na(avail_gb) && .Platform$OS.type == "windows") {
    wmic_raw <- tryCatch(
      system("wmic OS get FreePhysicalMemory,TotalVisibleMemorySize /Value",
             intern = TRUE, ignore.stderr = TRUE),
      error = function(e) NULL
    )
    if (!is.null(wmic_raw) && length(wmic_raw) > 0) {
      parse_wmic <- function(key) {
        line <- grep(paste0("^", key, "="), wmic_raw, value = TRUE)
        if (!length(line)) return(NA_real_)
        val <- suppressWarnings(as.numeric(sub(".*=(\\d+).*", "\\1", line[1L])))
        if (is.na(val)) NA_real_ else val / 1024 / 1024   # KB → GB
      }
      avail_gb <- parse_wmic("FreePhysicalMemory")
      total_gb <- parse_wmic("TotalVisibleMemorySize")
    }
  }

  # 方式 B：Linux /proc/meminfo（纯 Linux R）
  if (is.na(avail_gb) && file.exists("/proc/meminfo")) {
    meminfo <- tryCatch(readLines("/proc/meminfo"), error = function(e) NULL)
    if (!is.null(meminfo)) {
      parse_kb <- function(pattern) {
        line <- grep(pattern, meminfo, value = TRUE)
        if (!length(line)) return(NA_real_)
        as.numeric(sub("[^0-9]*(\\d+).*", "\\1", line[1L])) / 1024 / 1024
      }
      total_gb <- parse_kb("^MemTotal:")
      avail_gb <- parse_kb("^MemAvailable:")
    }
  }

  # 方式 C：bash fallback（WSL 终端内直接跑的 Rscript.exe 找不到 /proc/meminfo）
  if (is.na(avail_gb)) {
    bash_raw <- tryCatch(
      system("bash -c 'grep -E \"^MemTotal:|^MemAvailable:\" /proc/meminfo 2>/dev/null'",
             intern = TRUE, ignore.stderr = TRUE),
      error = function(e) NULL
    )
    if (!is.null(bash_raw) && length(bash_raw) >= 1L) {
      nums <- suppressWarnings(as.numeric(gsub("[^0-9]", "", bash_raw))) / 1024 / 1024
      if (length(nums) >= 2L) { total_gb <- nums[1L]; avail_gb <- nums[2L] }
      else if (length(nums) == 1L) avail_gb <- nums[1L]
    }
  }

  # ── 3. 内存限制 ──
  ram_limit <- if (!is.na(avail_gb) && avail_gb > ram_headroom_gb) {
    max(1L, as.integer(floor((avail_gb - ram_headroom_gb) / ram_per_worker)))
  } else {
    Inf   # 内存无法探测时不限制
  }

  # ── 4. 综合取 min ──
  workers <- min(n_indices, cpu_limit, ram_limit)
  if (!is.null(max_workers) && is.finite(as.numeric(max_workers)))
    workers <- min(workers, as.integer(max_workers))
  workers <- max(1L, as.integer(workers))

  # ── 5. 终端输出推算依据 ──
  avail_str <- if (!is.na(avail_gb)) sprintf("%.1f GB", avail_gb) else "未知"
  total_str <- if (!is.na(total_gb)) sprintf("%.1f GB", total_gb) else "未知"
  ram_lim_str <- if (is.finite(ram_limit)) as.character(as.integer(ram_limit)) else "不限"
  cli::cli_h2("Worker 数自动推算")
  cli::cli_inform(c(
    "i" = "CPU 逻辑核心: {n_cpu}  (保留 {cpu_headroom} → 可用上限 {cpu_limit})",
    "i" = "系统内存: 总 {total_str} / 空闲 {avail_str}  (每路估 {ram_per_worker} GB，保留 {ram_headroom_gb} GB)",
    "i" = "内存可并行上限: {ram_lim_str}  |  指标数上限: {n_indices}",
    "v" = "─── 最终并行路数: {.strong {workers}} ───"
  ))
  workers
}

# ── 从 ctx 取主数据框（批量层统一入口）──────────────────────────────────────
incidence_batch_ctx_data <- function(ctx) {
  if (is.null(ctx) || is.null(ctx$data)) return(NULL)
  ctx$data$mapped %||% ctx$data$imputed %||% ctx$data$cleaned
}

# ── Gate A：column_mapping 后两库列名交集（默认不按缺失率预删列）────────────
#  v5：gate_a_missing_threshold=1.0 → 列存在即保留；高缺失列在 per-index imputation 处理。
incidence_batch_gate_a_from_clean <- function(config) {
  bc <- config$incidence_batch %||% list()

  # auto_map_column_names 在 column_mapping block 文件里，确保已加载
  if (!exists("auto_map_column_names", mode = "function")) {
    block_path <- file.path(getwd(), "Blocks/01_column_mappings/01block_column_mapping.R")
    if (file.exists(block_path)) source(block_path, local = FALSE)
  }

  gate_a_thresh <- bc$gate_a_missing_threshold %||% 1.0

  .get_clean_cols <- function(db) {
    db_cfg <- if (db == "nhanes") config$dual_db$primary else config$dual_db$secondary
    thresh <- gate_a_thresh

    env <- new.env(parent = emptyenv())
    raw <- tryCatch({
      path <- db_cfg$rawdata_path
      if (!is_absolute_path(path)) path <- file.path(getwd(), path)
      load(path, envir = env)
      get(db_cfg$rawdata_obj, envir = env)
    }, error = function(e) NULL)
    if (is.null(raw) || !is.data.frame(raw)) return(character(0))

    miss  <- vapply(raw, function(x) mean(is.na(x)), numeric(1))
    kept  <- raw[, miss <= thresh, drop = FALSE]
    skip_rn <- as.character((config$column_mapping %||% list())$skip_rename %||% character(0))
    suppressMessages(mapped <- auto_map_column_names(
      kept, db_cfg$column_mapping_type,
      skip_rename = skip_rn
    ))
    if (exists("pipeline_apply_ventilation_after_map", mode = "function")) {
      mapped <- pipeline_apply_ventilation_after_map(mapped)
    } else if (exists("pipeline_split_ventilation_mapping", mode = "function")) {
      mapped <- pipeline_split_ventilation_mapping(mapped)
    }
    if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
      mapped <- pipeline_ensure_outcome_group_column(mapped, config)
    }
    sort(names(mapped))
  }

  n_cols <- .get_clean_cols("nhanes")
  m_cols <- .get_clean_cols("mimic")
  if (!length(n_cols) || !length(m_cols)) {
    cli::cli_alert_warning("Gate A: 无法加载数据，跳过后清洗 Gate A 计算")
    return(config)
  }

  if (!exists("nhanes_survey_weight_source_cols", mode = "function")) {
    source(file.path(getwd(), "R", "nhanes_survey_weight.R"), local = FALSE)
  }
  outcome_col <- as.character((config$data %||% list())$outcome_column %||% "Disease_Group")[1L]
  skip_rn <- as.character((config$column_mapping %||% list())$skip_rename %||% character(0))
  ix_keep <- unique(c(
    as.character((config$ml_batch %||% list())$index_vars %||% character(0)),
    as.character((config$incidence %||% list())$index_var %||% character(0)),
    as.character((config$prediction %||% list())$index_vars %||% character(0))
  ))
  protected <- unique(c(
    outcome_col, "Disease", "Disease_Group",
    "fustatus", "futime", "ID", "SEQN", "subject_id",
    skip_rn, ix_keep,
    nhanes_survey_weight_source_cols(config)
  ))
  n_clinical  <- setdiff(n_cols, protected)
  m_clinical  <- setdiff(m_cols, protected)
  common_clin <- intersect(n_clinical, m_clinical)
  if (exists("pipeline_gate_a_align_ventilation_cols", mode = "function")) {
    common_clin <- pipeline_gate_a_align_ventilation_cols(n_cols, m_cols, common_clin)
  }
  n_only      <- setdiff(n_clinical, m_clinical)
  m_only      <- setdiff(m_clinical, n_clinical)

  cli::cli_h2("Gate A（列名交集，threshold={gate_a_thresh}）")
  cli::cli_alert_info("NHANES 临床列: {length(n_clinical)} | MIMIC 临床列: {length(m_clinical)}")
  cli::cli_alert_success(
    "共同临床列 {length(common_clin)} 个: {paste(sort(common_clin), collapse=', ')}"
  )
  if (length(n_only)) cli::cli_alert_info("仅 NHANES 有（将被 harmonize 删除）: {length(n_only)} 个: {paste(head(sort(n_only),15),collapse=', ')}")
  if (length(m_only)) cli::cli_alert_info("仅 MIMIC 有（将被 harmonize 删除）: {length(m_only)} 个: {paste(head(sort(m_only),15),collapse=', ')}")

  keep_n <- union(common_clin, intersect(protected, n_cols))
  keep_m <- union(common_clin, intersect(protected, m_cols))
  if (!exists("pipeline_model3_required_raw", mode = "function")) {
    m3_src <- file.path(getwd(), "R", "model3_required.R")
    if (file.exists(m3_src)) source(m3_src, local = FALSE)
  }
  if (exists("pipeline_model3_required_raw", mode = "function")) {
    m3_raw <- pipeline_model3_required_raw(config)
    if (length(m3_raw)) {
      amap <- if (exists("pipeline_model3_alias_map", mode = "function")) {
        pipeline_model3_alias_map(config)
      } else {
        list()
      }
      m3_cands <- unique(unlist(lapply(m3_raw, function(v) {
        unique(c(v, as.character(amap[[v]] %||% character(0))))
      }), use.names = FALSE))
      keep_n <- union(keep_n, intersect(m3_cands, n_cols))
      keep_m <- union(keep_m, intersect(m3_cands, m_cols))
    }
  }
  if (exists("pipeline_ventilation_keep_alias", mode = "function")) {
    keep_n <- pipeline_ventilation_keep_alias(keep_n, n_cols)
    keep_m <- pipeline_ventilation_keep_alias(keep_m, m_cols)
  }

  # 次库 Table 1 独有列：默认丢弃以对齐双库；仅 keep_secondary_only_table1_cols=TRUE 时保留
  if (!exists("dual_db_is_demo_col", mode = "function")) {
    source(file.path(getwd(), "R", "dual_db_harmonize.R"), local = FALSE)
  }
  harm <- config$dual_db$harmonization %||% list()
  .gate_a_sec_t1_drop <- c(
    "Residence", "Hukou", "Familysize", "HR", "Pulse", "CRP", "HSCRP",
    "Family_per_capita_consumption", "Memeory", "Totalcognition", "Executive", "Incometotal"
  )
  if (isTRUE(harm$keep_secondary_only_table1_cols %||% FALSE) &&
      exists(".default_table1_sections", mode = "function")) {
    secs <- .default_table1_sections()
    t1_display <- unique(c(
      as.character(secs[["Demographics"]] %||% character(0)),
      as.character(secs[["Vital Signs"]] %||% character(0)),
      as.character(secs[["Laboratory"]] %||% character(0)),
      "CRP", "HSCRP", "HR", "Pulse", "Residence", "Hukou", "Familysize"
    ))
    extra_mimic <- intersect(m_only, t1_display)
    if (length(extra_mimic)) {
      keep_m <- unique(c(keep_m, extra_mimic))
      cli::cli_alert_info(
        "Gate A：次库 Table 1 独有列保留 {length(extra_mimic)} 个 — {paste(extra_mimic, collapse = ', ')}"
      )
    }
  } else {
    # 与 dual_db_compute_gate_a 一致：仅丢弃「非双库 common」的次库 Table1 独有展示列。
    # 已在 common_clin 中的列（如 CHARLS×ELSA 共有 Memeory）必须保留，否则冻结外验缺列。
    dropped_t1 <- setdiff(intersect(keep_m, .gate_a_sec_t1_drop), common_clin)
    if (length(dropped_t1)) {
      keep_m <- setdiff(keep_m, dropped_t1)
      cli::cli_alert_info(
        "Gate A：次库 Table 1 独有列已丢弃（对齐双库）— {paste(dropped_t1, collapse = ', ')}"
      )
    }
  }
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  demo_n <- unique(n_cols[dual_db_is_demo_col(n_cols, demo_kw)])
  demo_m <- unique(m_cols[dual_db_is_demo_col(m_cols, demo_kw)])
  common_clin_sorted <- sort(common_clin)

  # 注入 config，使 dual_db_column_harmonize / subgroup 能正确读取
  config$dual_db$harmonization$column_keep_nhanes               <- keep_n
  config$dual_db$harmonization$column_keep_mimic                <- keep_m
  config$dual_db$harmonization$common_non_demo_cols             <- common_clin_sorted
  config$dual_db$harmonization$common_clinical_subgroup_cols     <- common_clin_sorted
  config$dual_db$harmonization$demo_cols_nhanes                   <- demo_n
  config$dual_db$harmonization$demo_cols_mimic                    <- demo_m
  config$dual_db$current_db <- NULL   # 清除遗留值

  config
}

incidence_batch_extract_gate_a_from_config <- function(config) {
  harm <- (config$dual_db %||% list())$harmonization %||% list()
  common <- as.character(harm$common_non_demo_cols %||% character(0))
  list(
    common_non_demo_cols          = common,
    common_clinical_subgroup_cols = as.character(
      harm$common_clinical_subgroup_cols %||% common
    ),
    column_keep_nhanes = as.character(harm$column_keep_nhanes %||% character(0)),
    column_keep_mimic  = as.character(harm$column_keep_mimic %||% character(0)),
    demo_cols_nhanes   = as.character(harm$demo_cols_nhanes %||% character(0)),
    demo_cols_mimic    = as.character(harm$demo_cols_mimic %||% character(0))
  )
}

incidence_batch_apply_gate_a_to_config <- function(config, gate_a) {
  if (is.null(gate_a) || !length(gate_a)) return(config)
  config$dual_db$harmonization <- utils::modifyList(
    config$dual_db$harmonization %||% list(),
    gate_a
  )
  config
}

# 主流程与 worker 共用：优先读 harmonization 缓存，缺失则重算并落盘
# force=TRUE（--no-skip）必须重算，否则旧缓存会把 Ventilation_Hour 当共有列
incidence_batch_ensure_gate_a <- function(config, root = getwd(), force = FALSE) {
  if (!isTRUE((config$dual_db %||% list())$enable)) {
    return(list(config = config, gate_a = NULL))
  }
  if (!exists("dual_db_load_gate_a", mode = "function")) {
    source(file.path(root, "R", "dual_db_harmonize.R"), local = FALSE)
  }
  outcome_col <- as.character((config$data %||% list())$outcome_column %||% "Disease_Group")[1L]
  if (isTRUE(force) && exists("dual_db_gate_a_cache_path", mode = "function")) {
    ga_path <- dual_db_gate_a_cache_path(root, config)
    if (file.exists(ga_path)) {
      unlink(ga_path)
      cli::cli_alert_info("Gate A：--no-skip，已删除旧缓存并重算")
    }
  }
  gate_a <- if (isTRUE(force)) NULL else dual_db_load_gate_a(root, config)
  cache_ok <- !is.null(gate_a) && outcome_col %in% unique(c(
    as.character(gate_a$column_keep_nhanes %||% character(0)),
    as.character(gate_a$column_keep_mimic %||% character(0))
  ))
  if (is.null(gate_a) || !cache_ok) {
    if (!is.null(gate_a) && !cache_ok) {
      cli::cli_alert_warning(
        "Gate A 缓存缺少结局列 {.field {outcome_col}}，将重算 harmonization"
      )
    }
    config <- incidence_batch_gate_a_from_clean(config)
    gate_a <- incidence_batch_extract_gate_a_from_config(config)
    if (length(gate_a$common_non_demo_cols)) {
      dual_db_save_gate_a(root, config, gate_a)
      cli::cli_alert_success(
        "Gate A 已缓存（共享非人口学 {length(gate_a$common_non_demo_cols)} 列）"
      )
    }
  } else {
    config <- incidence_batch_apply_gate_a_to_config(config, gate_a)
    cli::cli_alert_info(
      "Gate A 自缓存加载（共享非人口学 {length(gate_a$common_non_demo_cols %||% character(0))} 列）"
    )
  }
  list(config = config, gate_a = gate_a)
}

# ── 模块级路径转换工具（dispatch 和 resolve 共用）─────────────────────────────
# Windows 路径 → WSL 路径：C:/foo → /mnt/c/foo（bash 使用）
.batch_win_to_wsl <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (grepl("^[A-Za-z]:/", p))
    paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
  else p
}

# WSL 路径 → Windows 路径：/mnt/g/foo → G:/foo（Windows R 进程使用）
.batch_wsl_to_win <- function(p) {
  if (grepl("^/mnt/[a-z]/", p))
    paste0(toupper(substr(p, 6L, 6L)), ":", substr(p, 7L, nchar(p)))
  else p
}

# 疾病相关变量衍生的复合指标：不进入批量候选（与 analysis_exclusion 规则一致）
incidence_batch_filter_disease_derived_indices <- function(config, index_vars) {
  index_vars <- unique(as.character(index_vars %||% character(0)))
  index_vars <- index_vars[nzchar(index_vars)]
  ae <- config$analysis_exclusion %||% list()
  disease_vars <- as.character(ae$disease_vars %||% character(0))
  disease_vars <- disease_vars[nzchar(disease_vars)]
  if (!length(index_vars) || !length(disease_vars)) return(index_vars)
  if (!isTRUE(ae$exclude_exposure_if_uses_disease_var %||% TRUE)) return(index_vars)
  if (!exists("pipeline_indices_using_vars", mode = "function")) {
    root <- config$project$root %||% getwd()
    src <- file.path(root, "Blocks/00_index/01block_index.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  if (!exists("pipeline_indices_using_vars", mode = "function")) return(index_vars)
  bad <- pipeline_indices_using_vars(disease_vars, index_vars)
  if (length(bad)) {
    cli::cli_alert_info(
      "跳过疾病相关变量衍生指标 {length(bad)} 个: {paste(head(bad, 12), collapse = ', ')}{if (length(bad) > 12) ' …' else ''}"
    )
  }
  setdiff(index_vars, bad)
}

# ── 1. 初始指标列表（共享层跑完前的候选；可被 resolve_from_ck 缩小）────────
.incidence_batch_ensure_index_canonical <- function() {
  if (exists("index_canonicalize_names", mode = "function")) return(invisible(TRUE))
  ic_path <- file.path(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), "R", "index_canonical.R"
  )
  if (file.exists(ic_path)) source(ic_path, local = FALSE)
  invisible(exists("index_canonicalize_names", mode = "function"))
}

incidence_batch_resolve_index_vars <- function(config) {
  .incidence_batch_ensure_index_canonical()
  bc  <- config$incidence_batch %||% list()
  ivs <- bc$index_vars
  grp <- bc$index_group %||% "all"

  if (!is.null(ivs) && length(ivs)) {
    out <- incidence_batch_filter_disease_derived_indices(config, as.character(ivs))
    if (exists("index_canonicalize_names", mode = "function")) {
      out <- index_canonicalize_names(out)
    }
    return(out)
  }

  # 尝试从已 source 的 composite_index_vars.R 取全量列表
  all_vars <- get0(".composite_index_vars", inherits = TRUE)
  if (!is.null(all_vars) && length(all_vars)) {
    if (identical(grp, "dual_safe"))
      all_vars <- get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% all_vars
    else {
      grp_sym <- switch(grp, A=".idx_group_A", B=".idx_group_B",
                             C=".idx_group_C", D=".idx_group_D", NULL)
      if (!is.null(grp_sym))
        all_vars <- get0(grp_sym, inherits = TRUE) %||% all_vars
    }
    out <- incidence_batch_filter_disease_derived_indices(config, all_vars)
    if (exists("index_canonicalize_names", mode = "function")) {
      out <- index_canonicalize_names(out)
    }
    return(out)
  }
  stop("找不到复合指标名单，请先 source configs/indices/composite_index_vars.R", call.=FALSE)
}

# ── 1b. 从 shared checkpoint 读取实际算出的指标（共享层完成后调用）────────────
#  - db_mode == "both"：两库交集 + 每库 n_valid >= min_valid_per_db
#  - db_mode == "nhanes"/"mimic"：单库可用指标
#  - Worker 若某库不可用，自动降级单库（nhanes_only / mimic_only）
incidence_batch_resolve_from_shared_ck <- function(config, candidate_vars,
                                                    db_mode = "both") {
  .incidence_batch_ensure_index_canonical()
  candidate_vars <- if (exists("index_canonicalize_names", mode = "function")) {
    index_canonicalize_names(candidate_vars)
  } else {
    candidate_vars
  }
  bc   <- config$incidence_batch %||% list()
  min_valid <- as.integer(bc$min_valid_per_db %||% 50L)
  db_seq <- switch(db_mode, nhanes="nhanes", mimic="mimic", c("nhanes","mimic"))

  col_sets_by_db <- list()
  for (db in db_seq) {
    ck_dir <- incidence_batch_shared_ck_dir(config, db)
    alias  <- file.path(ck_dir, "index.rds")
    if (!file.exists(alias)) alias <- .batch_wsl_to_win(alias)
    obj <- tryCatch(readRDS(alias), error = function(e) NULL)
    if (is.null(obj) || is.null(obj$ctx)) {
      cli::cli_alert_warning("  无法读取 [{toupper(db)}] 共享检查点: {.file {alias}}")
      next
    }
    df <- incidence_batch_ctx_data(obj$ctx)
    names_in_data  <- names(df %||% list())
    computed_names <- obj$ctx$results$computed_index_names %||% character(0)
    idx_enable     <- isTRUE((config$index %||% list())$enable %||% TRUE)
    if (!length(computed_names) && !idx_enable) {
      available <- intersect(candidate_vars, names_in_data)
      available <- available[vapply(
        available,
        function(ix) sum(!is.na(df[[ix]])) >= min_valid,
        logical(1L)
      )]
    } else {
      available <- intersect(computed_names, names_in_data)
      summary_df <- obj$ctx$results$computed_indices
      if (is.data.frame(summary_df) &&
          all(c("index", "n_valid") %in% names(summary_df))) {
        ok_ix <- summary_df$index[summary_df$n_valid >= min_valid]
        available <- intersect(available, ok_ix)
      }
      # 显式指定的原始列指标（如 PIR）：在数据中且 n_valid 足够即可
      raw_extra <- intersect(candidate_vars, names_in_data)
      raw_extra <- raw_extra[vapply(
        raw_extra,
        function(ix) sum(!is.na(df[[ix]])) >= min_valid,
        logical(1L)
      )]
      available <- unique(c(available, setdiff(raw_extra, computed_names)))
    }

    if (exists("index_expand_available_canonical", mode = "function")) {
      available <- index_expand_available_canonical(
        available, names_in_data, candidate_vars
      )
    }

    col_sets_by_db[[db]] <- available
    cli::cli_alert_success(
      "  [{toupper(db)}] 可用指标 (n_valid>={min_valid}): {length(available)} 个: {paste(available, collapse=', ')}"
    )
  }

  computed_final <- if (identical(db_mode, "both") && length(col_sets_by_db) >= 2) {
    both <- Reduce(intersect, col_sets_by_db)
    if (length(both) == 0)
      cli::cli_alert_warning(
        "两库指标交集为空；请检查 Gate A / index 是否读 mapped，或降低 min_valid_per_db"
      )
    both
  } else {
    Reduce(union, col_sets_by_db)
  }

  final     <- candidate_vars[candidate_vars %in% computed_final]
  not_avail <- setdiff(candidate_vars, computed_final)
  mode_desc <- if (identical(db_mode, "both")) "双库交集" else paste0(db_mode, " 单库")

  cli::cli_h2(
    "指标筛查（{mode_desc}，min_valid={min_valid}）：候选 {length(candidate_vars)} → 可用 {length(final)}"
  )
  if (length(not_avail)) {
    head20 <- paste(head(not_avail, 20), collapse = ", ")
    tail_n <- if (length(not_avail) > 20) paste0(" … 等 ", length(not_avail), " 个") else ""
    cli::cli_alert_info("  未通过筛查（跳过）: {head20}{tail_n}")
  }

  if (!length(final))
    stop("共享层没有任何指标可用，请检查 Gate A 列交集、index 数据槽或 min_valid_per_db。",
         call. = FALSE)

  if (exists("index_canonicalize_names", mode = "function")) {
    final <- index_canonicalize_names(final)
  }
  final
}

# ── 2. Patch config 为单一指标 ────────────────────────────────────────────────
incidence_batch_patch_config_for_index <- function(config, ix, root = NULL) {
  bc <- config$incidence_batch %||% list()
  root <- root %||% config$project$root %||% Sys.getenv("INCIDENCE_BATCH_ROOT", unset = getwd())
  if (exists("pipeline_ensure_index_formula_helpers", mode = "function")) {
    pipeline_ensure_index_formula_helpers(root)
  }

  disease_vars <- as.character(
    (config$analysis_exclusion %||% list())$disease_vars %||% character(0)
  )
  disease_vars <- disease_vars[nzchar(disease_vars)]

  sub_vars <- unique(as.character(bc$base_subgroup_vars %||%
    c("Gender", "Race", "Smoking", "Hypertension")))
  # 疾病相关变量不得进入亚组分层
  if (length(disease_vars)) {
    sub_vars <- setdiff(sub_vars, disease_vars)
  }

  idx_comps <- if (exists("index_get_formula_components", mode = "function")) {
    index_get_formula_components(ix)
  } else {
    character(0)
  }
  comp_ovr <- as.character((bc$index_component_overrides %||% list())[[ix]] %||% character(0))
  cfg_comps <- setdiff(
    as.character(config$incidence$index_component_vars %||% character(0)),
    ix
  )
  idx_comps <- unique(c(comp_ovr, cfg_comps, idx_comps))
  idx_comps <- setdiff(idx_comps[nzchar(idx_comps)], ix)
  idx_names <- unique(c(ix, idx_comps))
  meta_excl <- pipeline_meta_exclude_cols()

  extra_cov <- unique(c(
    as.character(bc$extra_index_exclude_vars %||% character(0)),
    setdiff(as.character(bc$base_exclude_vars %||% character(0)), c(idx_names, meta_excl)),
    disease_vars
  ))

  config$incidence$index_var            <- ix
  config$incidence$index_component_vars <- idx_names
  config$logistic$index_var             <- ix
  config$survival$index_var             <- ix
  config$cox_binary$index_var           <- ix
  config$km_binary$index_var            <- ix
  config$nhanes$cutoff_index_var        <- ix
  config$prediction$index_vars          <- c(ix)
  config$feature_selection$composite_features <- c(ix)
  config$dual_db$harmonization$index_component_vars <- idx_names
  # 与 study_batch 对齐：按当前指标解析疾病+组成硬排除，尽早写入表级/模型排除
  if (length(config$analysis_exclusion %||% list())) {
    config$analysis_exclusion$index_var <- ix
    if (!exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
      excl_src <- file.path(root, "Blocks/03_imputation/03block_analysis_exclusion.R")
      if (file.exists(excl_src)) source(excl_src, local = FALSE)
    }
    if (exists("pipeline_analysis_exclusion_manifest", mode = "function")) {
      man <- tryCatch(
        pipeline_analysis_exclusion_manifest(config),
        error = function(e) NULL
      )
      if (!is.null(man)) {
        drop_vars <- as.character(man$drop_vars %||% character(0))
        config$imputation$table_s1_exclude_vars <- unique(c(
          as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
          drop_vars
        ))
        if (!is.null(config$baseline_nhanes)) {
          config$baseline_nhanes$exclude_vars <- unique(c(
            as.character(config$baseline_nhanes$exclude_vars %||% character(0)),
            drop_vars
          ))
        }
        if (!is.null(config$baseline_binary)) {
          config$baseline_binary$exclude_vars <- unique(c(
            as.character(config$baseline_binary$exclude_vars %||% character(0)),
            drop_vars
          ))
        }
        if (!is.null(config$logistic_nhanes_weighted)) {
          config$logistic_nhanes_weighted$clinical_factor_names <- setdiff(
            as.character(config$logistic_nhanes_weighted$clinical_factor_names %||% character(0)),
            unique(c(disease_vars, drop_vars))
          )
        }
        config$analysis_exclusion$resolved_drop_vars <- drop_vars
        extra_cov <- unique(c(extra_cov, setdiff(drop_vars, idx_names)))
      }
    }
  }
  config <- pipeline_apply_index_exclude_patch(config, extra_cov)
  if (!is.null(config$boxplot))
    config$boxplot$response_vars <- c(ix)
  if (!is.null(config$subgroup)) {
    # 默认 base_subgroup_vars 含 Gender；全女性队列会把它放进 forbid，须剔除避免冲突
    forbid_sg <- unique(c(
      as.character(config$subgroup$forbid_subgroup_vars %||% character(0)),
      as.character(config$subgroup$exclude_vars %||% character(0))
    ))
    # 铁律：课题显式写了 required_subgroup_vars（var_source=required）时必须尊重，
    # 不得用 base_subgroup_vars 默认名单（常含 Race、无 Age）覆盖，
    # 否则双库亚组森林丢 Age、乱入 Race（CHARLS×ELSA 等无 Race 队列尤甚）。
    study_req <- as.character(config$subgroup$required_subgroup_vars %||% character(0))
    study_req <- study_req[nzchar(study_req) & !tolower(study_req) %in% c("null", "na")]
    if (length(study_req)) {
      config$subgroup$required_subgroup_vars <- setdiff(
        unique(study_req), unique(c(forbid_sg, disease_vars))
      )
    } else {
      config$subgroup$required_subgroup_vars <- setdiff(sub_vars, forbid_sg)
    }
    # 闸门 D：若有双库亚组锁，覆盖 required（保证 Fig3 两库名单一致）
    if (exists("dual_db_load_subgroup_lock", mode = "function")) {
      gd <- tryCatch(dual_db_load_subgroup_lock(root, config), error = function(e) NULL)
      gd_vars <- as.character((gd %||% list())$vars %||% character(0))
      gd_vars <- setdiff(gd_vars[nzchar(gd_vars)], forbid_sg)
      if (length(gd_vars)) {
        config$subgroup$required_subgroup_vars <- gd_vars
        cli::cli_alert_info(
          "闸门 D 亚组锁已注入 required_subgroup_vars: {paste(gd_vars, collapse = ', ')}"
        )
      }
    }
  }
  if (!is.null(config$rcs_nhanes))    config$rcs_nhanes$index_var    <- ix
  if (!is.null(config$rcs_incidence)) config$rcs_incidence$index_var <- ix
  for (blk in c("logistic_quartile_nhanes_weighted",
                 "logistic_tertile_nhanes_weighted",
                 "logistic_binary_nhanes_weighted")) {
    if (!is.null(config[[blk]])) config[[blk]]$index_var <- ix
  }
  for (blk in c("logistic_quartile_glm","logistic_tertile_glm","logistic_binary_glm")) {
    if (!is.null(config[[blk]])) config[[blk]]$index_var <- ix
  }
  if (!is.null(config$mediation_nhanes_weighted))
    config$mediation_nhanes_weighted$exposure <- ix
  if (!is.null(config$mediation_incidence))
    config$mediation_incidence$exposure <- ix
  display <- as.character(bc$index_var_display_name %||% config$incidence$index_var_display_name %||% "")[1L]
  if (nzchar(display)) {
    config$incidence$index_var_display_name <- display
    lbl <- setNames(list(display), ix)
    for (b in c("baseline_nhanes", "baseline_binary")) {
      if (!is.null(config[[b]])) {
        ov <- as.list(config[[b]]$table1_label_overrides %||% list())
        config[[b]]$table1_label_overrides <- utils::modifyList(ov, lbl)
      }
    }
  }

  # 按指标覆盖（仅该 index 生效；其他指标不继承）
  # 例：config$index_overrides$log2LAR$roc_simple$model_covariates <- c("Age", ...)
  ov <- (config$index_overrides %||% list())[[ix]] %||%
    (config$index_var_overrides %||% list())[[ix]] %||% list()
  if (is.list(ov) && length(ov)) {
    for (nm in names(ov)) {
      if (is.null(nm) || !nzchar(nm)) next
      if (identical(nm, "extra_index_exclude_vars")) next
      if (is.list(ov[[nm]])) {
        config[[nm]] <- utils::modifyList(config[[nm]] %||% list(), ov[[nm]])
      } else {
        config[[nm]] <- ov[[nm]]
      }
    }
    # 指标级额外排除：只进 UV/MV/VIF/logistic，不从 Table1/S1 踢（基线表仍展示）
    extra_ov <- unique(as.character(ov$extra_index_exclude_vars %||% character(0)))
    extra_ov <- extra_ov[nzchar(extra_ov)]
    if (length(extra_ov)) {
      config <- pipeline_apply_index_exclude_patch(
        config, unique(c(extra_cov, extra_ov))
      )
      if (!is.null(config$subgroup)) {
        config$subgroup$required_subgroup_vars <- setdiff(
          as.character(config$subgroup$required_subgroup_vars %||% character(0)),
          extra_ov
        )
      }
      if (requireNamespace("cli", quietly = TRUE)) {
        tryCatch(
          cli::cli_alert_info(
            "index_overrides[{ix}] extra_index_exclude_vars: {paste(extra_ov, collapse = ', ')}"
          ),
          error = function(e) NULL
        )
      }
    }
    if (requireNamespace("cli", quietly = TRUE)) {
      tryCatch(
        cli::cli_alert_info("index_overrides[{ix}]: {paste(names(ov), collapse = ', ')}"),
        error = function(e) NULL
      )
    }
  }

  config
}

# ── 2b. 单指标输出镜像：库级 Tables/Figures + 指标级汇总 ─────────────────────
incidence_batch_index_output_subdir <- function(bc = list()) {
  as.character(bc$index_output_subdir %||% "by_index")[1L]
}

incidence_batch_index_output_root <- function(config, ix) {
  .rerun_out <- Sys.getenv("MEDICAL_BLOCKS_RERUN_OUT", unset = "")
  if (nzchar(.rerun_out)) {
    if (!dir.exists(.rerun_out)) {
      dir.create(.rerun_out, recursive = TRUE, showWarnings = FALSE)
    }
    return(normalizePath(.rerun_out, winslash = "/", mustWork = FALSE))
  }
  force <- as.character(
    (config$survival_batch %||% list())$.force_index_output_root %||%
      (config$incidence_batch %||% list())$.force_index_output_root %||%
      ""
  )[1L]
  if (nzchar(force)) {
    if (!dir.exists(force)) dir.create(force, recursive = TRUE, showWarnings = FALSE)
    return(normalizePath(force, winslash = "/", mustWork = FALSE))
  }
  bc <- config$incidence_batch %||% config$ml_batch %||% config$survival_batch %||% list()
  output_base <- bc$output_base %||% config$project$output_dir
  ix_lab <- if (exists("incidence_batch_index_dir_label", mode = "function")) {
    incidence_batch_index_dir_label(ix, config)
  } else {
    ix
  }
  if (exists("incidence_batch_find_index_output_dir", mode = "function")) {
    return(incidence_batch_find_index_output_dir(
      output_base, ix, incidence_batch_index_output_subdir(bc),
      config = config, ix_bare = ix
    ))
  }
  file.path(output_base, incidence_batch_index_output_subdir(bc), ix_lab)
}

incidence_batch_sync_db_pub_outputs <- function(root, config, ix, db) {
  prj <- config$project %||% list()
  if (!isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)) return(invisible(FALSE))
  cfg_db <- incidence_batch_apply_db_overrides(config, db, root, ix)
  db_root <- cfg_db$project$output_dir
  if (is.null(db_root) || !nzchar(db_root) || !dir.exists(db_root)) {
    return(invisible(FALSE))
  }
  ctx <- list(
    config          = cfg_db,
    root_output_dir = db_root,
    output_dir      = db_root
  )
  if (exists("sync_all_block_pub_outputs_to_root", mode = "function")) {
    sync_all_block_pub_outputs_to_root(ctx)
  }
  invisible(TRUE)
}

.incidence_batch_index_root_from_slot_dir <- function(slot_root) {
  norm <- normalizePath(as.character(slot_root)[1L], winslash = "/", mustWork = FALSE)
  if (!grepl("/by_index/[^/]+/[^/]+/?$", norm)) return(NULL)
  dirname(norm)
}

#' 双库 mirror 时须汇总两槽（非仅当前续跑库）
incidence_batch_dual_mirror_db_seq <- function(config) {
  dual <- config$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(character(0))
  c(
    if (exists("dual_db_slot_primary", mode = "function")) dual_db_slot_primary() else "nhanes",
    if (exists("dual_db_slot_secondary", mode = "function")) dual_db_slot_secondary() else "mimic"
  )
}

#' 组装发表图 image_information meta（结局展示名 / 分位 / N；finalize 与补刷共用）
#'
#' 结局禁止写数据列名（DN/fustatus）：优先 project$outcome_label / 疾病显示名，
#' 列名以「原字段」括注保留。分位 config 链为空时从 per-index ck 收割主文锁定方案。
incidence_batch_pub_figure_meta <- function(index_root, config, ix, db_seq) {
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  db_disp <- vapply(db_seq, function(db) {
    if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) as.character(db)[1L])
    } else as.character(db)[1L]
  }, character(1L))
  outcome_show <- {
    cand <- as.character(config$project$outcome_label %||% character(0))
    if (exists("pipeline_outcome_case_label", mode = "function")) {
      cand <- c(cand, tryCatch(pipeline_outcome_case_label(config), error = function(e) character(0)))
    }
    cand <- c(cand, as.character(config$survival$outcome_label %||% character(0)),
              as.character(config$mediation_prognosis$outcome_label %||% character(0)))
    hit <- cand[nzchar(cand)][1L]
    if (is.na(hit) || !nzchar(hit)) {
      hit <- as.character(config$survival$event_var %||% config$data$outcome_column %||%
                            config$project$outcome %||% "")[1L]
    }
    if (is.na(hit)) hit <- ""
    hit
  }
  grouping <- as.character(config$cox_gate$grouping %||% config$logistic_gate$grouping %||%
                             config$cox_quartile$grouping %||% config$project$grouping %||% "")[1L]
  if (!nzchar(grouping)) {
    grouping <- tryCatch({
      bc0 <- config$incidence_batch %||% config$survival_batch %||% config$ml_batch %||% list()
      ck0 <- as.character(bc0$index_ck_base %||% "")[1L]
      found <- ""
      if (nzchar(ck0)) for (db in db_seq) {
        db_dir <- if (exists("dual_db_slot_path_name", mode = "function")) {
          dual_db_slot_path_name(config, db)
        } else as.character(db)[1L]
        for (bn in c("dual_db_logistic_main_table_realign.rds",
                     "dual_db_logistic_scheme_harmonize.rds")) {
          fp <- file.path(ck0, ix, db_dir, bn)
          if (!file.exists(fp)) next
          r <- readRDS(fp)$ctx$results
          for (k in c("logistic_grouping_scheme", "nhanes_logistic_selected_scheme",
                      "dual_db_logistic_unified_scheme", "cox_grouping_scheme")) {
            v <- tolower(trimws(as.character(r[[k]] %||% "")[1L]))
            if (v %in% c("quartile", "tertile", "binary")) { found <- v; break }
          }
          if (nzchar(found)) break
        }
        if (nzchar(found)) break
      }
      found
    }, error = function(e) "")
  }
  meta <- list(
    exposure = as.character(config$project$exposure_var %||% config$project$index_var %||% ix)[1L],
    outcome = outcome_show,
    outcome_column = as.character(config$data$outcome_column %||% "")[1L],
    databases = as.character(db_disp),
    combined = length(db_seq) >= 2L,
    grouping = grouping
  )
  meta_n <- tryCatch(
    incidence_batch_pub_figure_meta_n(index_root, config, db_seq),
    error = function(e) list()
  )
  if (length(meta_n)) meta <- utils::modifyList(meta, meta_n)
  meta
}

#' 指标根 Figures：双库拼图 → pdf/png/tiff/image_information（局部续跑 / finalize 共用）
incidence_batch_finalize_index_figures <- function(root, config, ix, db_seq, index_root,
                                                   light_fin = NULL) {
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq) || is.null(index_root) || !dir.exists(index_root)) {
    return(invisible(FALSE))
  }
  if (is.null(light_fin)) {
    light_fin <- isTRUE((config$incidence_batch %||% list())$.sensitivity_light) ||
      isTRUE((config$survival_batch %||% list())$.sensitivity_light)
  }
  agg_figs <- file.path(index_root, "Figures")
  dir.create(agg_figs, recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(agg_figs)) {
    stale_svg <- list.files(agg_figs, pattern = "\\.svg$", full.names = TRUE, ignore.case = TRUE)
    if (length(stale_svg)) {
      unlink(stale_svg)
      cli::cli_alert_info("已清理汇总 Figures 中 {length(stale_svg)} 个 .svg")
    }
  }
  if (incidence_batch_is_prognosis_config(config)) {
    for (db in db_seq) {
      incidence_batch_dedupe_prognosis_figures_dir(
        file.path(index_root, dual_db_slot_path_name(config, db), "Figures"),
        config
      )
    }
    incidence_batch_dedupe_prognosis_figures_dir(agg_figs, config)
  } else if (identical(
    tolower(as.character(config$project$study_type %||% "")[1L]), "incidence"
  )) {
    ## ML 双库：禁止发病默认「亚组=Fig3 / ROC=S2」，否则会把三集 Fig3–6 与亚组撞号
    if (incidence_batch_is_ml_dual_pub_scheme(config)) {
      for (db in db_seq) {
        fig_dir <- file.path(index_root, dual_db_slot_path_name(config, db), "Figures")
        if (dir.exists(fig_dir)) {
          incidence_batch_curate_ml_pub_figures_dir(fig_dir, cfg = config)
        }
      }
    } else {
      for (db in db_seq) {
        fig_dir <- file.path(index_root, dual_db_slot_path_name(config, db), "Figures")
        if (dir.exists(fig_dir)) {
          incidence_batch_dedupe_incidence_figures_dir(fig_dir, config)
        }
      }
      incidence_batch_dedupe_incidence_figures_dir(agg_figs, config)
    }
  }
  if (!exists("dual_db_combine_paired_figures", mode = "function")) {
    combine_src <- file.path(root, "R", "dual_db_combine_figures.R")
    if (!file.exists(combine_src)) {
      eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
      if (nzchar(eng)) combine_src <- file.path(eng, "R", "dual_db_combine_figures.R")
    }
    if (file.exists(combine_src)) source(combine_src, local = FALSE)
  }
  if (length(db_seq) >= 2L && exists("dual_db_combine_paired_figures", mode = "function")) {
    tryCatch(
      dual_db_combine_paired_figures(index_root, config),
      error = function(e) cli::cli_alert_warning("双库拼图跳过: {e$message}")
    )
  }
  if (incidence_batch_is_ml_dual_pub_scheme(config)) {
    tryCatch(
      incidence_batch_ml_collect_fs_figure(index_root, config),
      error = function(e) cli::cli_alert_warning("收集特征选择图跳过: {e$message}")
    )
    tryCatch(
      incidence_batch_curate_ml_pub_figures_dir(agg_figs, cfg = config),
      error = function(e) cli::cli_alert_warning("ML 定稿图整理跳过: {e$message}")
    )
  }
  if (!light_fin) {
    tryCatch(
      incidence_batch_ensure_real_figure1(
        index_root = index_root,
        config = config,
        ix = ix,
        db_seq = db_seq,
        project_root = (config$incidence_batch %||% config$survival_batch %||% list())$output_base %||%
          config$project$output_dir
      ),
      error = function(e) cli::cli_alert_warning("Figure 1 纳排图保障失败: {e$message}")
    )
  }
  if (!exists("export_pub_figures", mode = "function") &&
      !exists("pub_figure_ensure_formats", mode = "function")) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    exp_src <- c(
      if (nzchar(eng)) file.path(eng, "R", "pub_figure_export.R") else character(0),
      file.path(root, "R", "pub_figure_export.R"),
      file.path(getwd(), "R", "pub_figure_export.R")
    )
    exp_src <- exp_src[file.exists(exp_src)]
    if (length(exp_src)) source(exp_src[[1L]], local = FALSE)
  }
  if (!exists("export_pub_figures", mode = "function") &&
      !exists("pub_figure_ensure_formats", mode = "function")) {
    return(invisible(FALSE))
  }
  figs_dir <- agg_figs
  db_disp <- vapply(db_seq, function(db) {
    if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) as.character(db)[1L])
    } else {
      as.character(db)[1L]
    }
  }, character(1L))
  meta <- incidence_batch_pub_figure_meta(index_root, config, ix, db_seq)
  tryCatch(
    export_pub_figures(figs_dir, meta = meta, config = config, purge = TRUE),
    error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
  )
  if (!light_fin && length(db_seq) >= 2L && !incidence_batch_is_prognosis_config(config)) {
    tryCatch({
      ok_f1 <- incidence_batch_ensure_real_figure1(
        index_root = index_root,
        config = config,
        ix = ix,
        db_seq = db_seq,
        project_root = (config$incidence_batch %||% config$survival_batch %||% list())$output_base %||%
          config$project$output_dir
      )
      if (isTRUE(ok_f1) && file.exists(file.path(figs_dir, "pdf", "Figure 1. Flowchart.pdf"))) {
        export_pub_figures(figs_dir, meta = meta, config = config, purge = FALSE)
      }
    }, error = function(e) cli::cli_alert_warning("Figure 1 双库纳排后重导出跳过: {e$message}"))
  }
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(figs_dir, meta = meta, config = config, purge = FALSE),
      error = function(e) cli::cli_alert_warning("发表图四目录校验补齐跳过: {e$message}")
    )
  }
  if (length(db_seq) >= 2L && exists("dual_db_purge_redundant_split_figures", mode = "function")) {
    tryCatch(
      dual_db_purge_redundant_split_figures(figs_dir, db_names = db_disp),
      error = function(e) cli::cli_alert_warning("清除冗余分库图跳过: {e$message}")
    )
  }
  if (exists("pub_figure_formats_status", mode = "function")) {
    st <- tryCatch(pub_figure_formats_status(figs_dir), error = function(e) NULL)
    if (!is.null(st) && !isTRUE(st$ok)) {
      cli::cli_alert_warning(
        "发表图四目录校验未通过: 根残留={length(st$flat_leftovers %||% character(0))}，缺 png={length(st$missing_png %||% character(0))}"
      )
    }
  }
  invisible(TRUE)
}

#' 局部续跑后：step → 分库 Tables → curate → 指标根 Tables/Figures（避免根目录残留旧 S 表）
incidence_batch_mirror_index_aggregate_from_ctx <- function(ctx, root, config) {
  dual <- config$dual_db %||% list()
  if (!isTRUE(dual$mirror_aggregate)) return(invisible(FALSE))
  slot_root <- as.character(ctx$root_output_dir %||% (config$project %||% list())$output_dir)[1L]
  if (!nzchar(slot_root) || !dir.exists(slot_root)) return(invisible(FALSE))
  index_root <- .incidence_batch_index_root_from_slot_dir(slot_root)
  if (is.null(index_root) || !dir.exists(index_root)) return(invisible(FALSE))

  db_path <- basename(normalizePath(slot_root, winslash = "/", mustWork = FALSE))
  db_slot <- if (exists("dual_db_path_name_to_slot", mode = "function")) {
    dual_db_path_name_to_slot(config, db_path)
  } else {
    NA_character_
  }
  if (is.na(db_slot) || !nzchar(db_slot)) {
    db_slot <- if (exists("dual_db_slot_primary", mode = "function")) {
      dual_db_slot_primary()
    } else {
      "nhanes"
    }
  }
  db_seq <- incidence_batch_dual_mirror_db_seq(config)
  if (!length(db_seq)) db_seq <- db_slot

  ix <- as.character((config$prediction %||% list())$index_vars %||%
    (config$ml_batch %||% list())$index_vars %||%
    (config$incidence_batch %||% list())$index_vars %||% "")[1L]
  if (!nzchar(ix)) {
    ix <- sub("^【[^】]+】", "", basename(index_root))
    bc <- config$ml_batch %||% config$incidence_batch %||% list()
    suf <- as.character(bc$index_output_label_suffix %||% "")[1L]
    if (nzchar(suf) && endsWith(ix, suf)) {
      ix <- sub(paste0(suf, "$"), "", ix, fixed = TRUE)
    }
  }

  for (db in db_seq) {
    incidence_batch_sync_db_pub_outputs(root, config, ix, db)
  }

  if (incidence_batch_is_ml_dual_pub_scheme(config)) {
    if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
      cur_src <- file.path(root, "R", "ml_dual_pub_table_curate.R")
      if (file.exists(cur_src)) source(cur_src, local = FALSE)
    }
    db_tables <- file.path(index_root, db_path, "Tables")
    if (dir.exists(db_tables) && exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
      incidence_batch_curate_ml_pub_tables(db_tables, config)
    }
  }

  incidence_batch_purge_aggregate_pub_cache(index_root)
  if (!exists("mirror_dual_db_aggregate", mode = "function")) {
    harm <- file.path(root, "R", "dual_db_harmonize.R")
    if (file.exists(harm)) source(harm, local = FALSE)
  }
  if (!exists("mirror_dual_db_aggregate", mode = "function")) {
    return(invisible(FALSE))
  }
  mirror_dual_db_aggregate(root, config, out_root = index_root, dbs = db_seq)
  incidence_batch_finalize_index_figures(root, config, ix, db_seq, index_root)
  cli::cli_alert_success(
    "指标根 Tables/Figures 已双库汇总刷新（触发库={.file {db_path}}，拼图+四目录已重导）"
  )
  invisible(TRUE)
}

# 双库汇总附表角色分类（用于统一 S 编号）
incidence_batch_classify_dual_supp_table <- function(basename) {
  bn <- as.character(basename)[1L]
  if (grepl("before and after", bn, ignore.case = TRUE) &&
      grepl("imputation", bn, ignore.case = TRUE))
    return("imputation")
  if (grepl("Normality test", bn, ignore.case = TRUE))
    return("normality")
  if (grepl("Univariate Regression", bn, fixed = TRUE)) return("univariate")
  # 锁定终模型（须先于普通 multivariable）
  if (grepl("Final multivariable model", bn, ignore.case = TRUE))
    return("multivariate_harmonized")
  if (grepl("Multivariable Regression", bn, fixed = TRUE) &&
      grepl("harmonized", bn, ignore.case = TRUE))
    return("multivariate_harmonized")
  if (grepl("Multivariable Regression", bn, fixed = TRUE)) return("multivariate")
  # NHANES 加权 VIF：缩短标题后可能只剩 Weighted Multicollinearity；
  # 须识别 screen/final（含括号内 univariate screen / multivariate final）
  if (grepl("Multicollinearity", bn, ignore.case = TRUE) &&
      grepl("VIF screen|univariate p|univariate screen", bn, ignore.case = TRUE)) {
    return("vif_screen")
  }
  if (grepl("Multicollinearity", bn, ignore.case = TRUE) &&
      grepl("VIF final|multivariate p|multivariate final", bn, ignore.case = TRUE)) {
    return("vif_final")
  }
  if (grepl("mediation by laboratory|Mediation analysis", bn, ignore.case = TRUE))
    return("mediation")
  if (grepl("associations between .+ laboratory indicators|Weighted associations (between|of) .+ laboratory|Associations of .+ with laboratory",
            bn, ignore.case = TRUE, perl = TRUE))
    return("lab_assoc")
  if (grepl("Baseline characteristics by .+ (quartile|tertile|binary|median)",
            bn, ignore.case = TRUE, perl = TRUE))
    return("baseline_by_index")
  if (grepl("Segmented Cox", bn, ignore.case = TRUE))
    return("segmented_cox")
  if (grepl("Proportional hazards|Schoenfeld", bn, ignore.case = TRUE))
    return("ph_test")
  # 标题两种语序都认：Unweighted sensitivity… / Sensitivity analysis Unweighted…
  if (grepl("Baseline characteristics", bn, ignore.case = TRUE) &&
      grepl("unweighted", bn, ignore.case = TRUE) &&
      grepl("sensitivity", bn, ignore.case = TRUE))
    return("unweighted_baseline")
  # 不加权 logistic：文件名常无 "unweighted"，靠 Sensitivity analysis + Logistic
  if (grepl("Logistic regression", bn, ignore.case = TRUE) &&
      (grepl("unweighted", bn, ignore.case = TRUE) ||
       grepl("Sensitivity analysis", bn, ignore.case = TRUE)))
    return("unweighted_logistic")
  if (grepl("RCS groups|RCS cutoff", bn, ignore.case = TRUE))
    return("rcs_logistic")
  NA_character_
}

incidence_batch_extract_pub_db_tag <- function(basename, cfg) {
  bn <- as.character(basename)[1L]
  nhanes_nm <- dual_db_slot_path_name(cfg, "nhanes")
  mimic_nm  <- dual_db_slot_path_name(cfg, "mimic")
  if (grepl(paste0("-", nhanes_nm, "\\."), bn, fixed = FALSE)) return(nhanes_nm)
  if (grepl(paste0("-", mimic_nm, "\\."), bn, fixed = FALSE)) return(mimic_nm)
  NA_character_
}

# 同步 xlsx 首行标题中的 Table S# / Table S-XX 前缀，与文件名一致
# new_s: 整数，或字符串 "XX"（字面量，用于 RCS 等暂不定稿附表）
incidence_batch_sync_supp_table_title <- function(path, new_s = NULL) {
  path <- as.character(path)[1L]
  if (!file.exists(path) || !requireNamespace("openxlsx", quietly = TRUE)) {
    return(invisible(FALSE))
  }
  bn <- basename(path)
  m <- regexec(
    "^Table S(?:-?XX|(\\d+))(?:-([A-Za-z][A-Za-z0-9_]*(?:[ _][A-Za-z0-9_]+)*))?\\.(.+)\\.xlsx$",
    bn,
    perl = TRUE
  )
  mm <- regmatches(bn, m)[[1L]]
  if (!length(mm)) return(invisible(FALSE))
  use_xx <- FALSE
  if (!is.null(new_s)) {
    ns <- as.character(new_s)[1L]
    if (identical(toupper(ns), "XX")) {
      use_xx <- TRUE
    } else if (is.finite(suppressWarnings(as.integer(ns)))) {
      s_num <- as.integer(ns)
    } else {
      return(invisible(FALSE))
    }
  } else if (grepl("^Table S-?XX", bn, ignore.case = TRUE, perl = TRUE)) {
    use_xx <- TRUE
  } else {
    s_num <- as.integer(mm[2L])
  }
  db_tag <- if (nzchar(mm[3L] %||% "")) mm[3L] else NA_character_
  # 文件名 "Table S8-NHANES. caption" 中正则捕获的 caption 常带前导空格，须 trim
  # 否则表内标题会变成 "Table S8-NHANES.  caption"（双空格）
  caption <- trimws(mm[4L])
  new_title <- if (use_xx) {
    if (!is.na(db_tag) && nzchar(db_tag)) {
      sprintf("Table S-XX-%s. %s", db_tag, caption)
    } else {
      sprintf("Table S-XX. %s", caption)
    }
  } else if (!is.na(db_tag) && nzchar(db_tag)) {
    sprintf("Table S%d-%s. %s", s_num, db_tag, caption)
  } else {
    sprintf("Table S%d. %s", s_num, caption)
  }
  ok <- tryCatch({
    wb <- openxlsx::loadWorkbook(path)
    sh <- openxlsx::sheets(wb)[1L]
    openxlsx::writeData(wb, sh, new_title, startCol = 1L, startRow = 1L, colNames = FALSE)
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
    TRUE
  }, error = function(e) FALSE)
  invisible(isTRUE(ok))
}

.incidence_batch_purge_realign_temp_tables <- function(tables_dir) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  stale <- list.files(
    tables_dir,
    pattern = "^\\.realign_(trail|tmp)_",
    full.names = TRUE,
    all.files = TRUE
  )
  if (!length(stale)) return(invisible(0L))
  # 中断残留：若临时名里嵌着完整 Table 名且目标不存在，先还原再清
  n_restored <- 0L
  for (f in stale) {
    bn <- basename(f)
    m <- regexec(
      "^\\.realign_(?:trail|tmp)_\\d+_(Table .+\\.xlsx)$",
      bn,
      perl = TRUE,
      ignore.case = TRUE
    )
    mm <- regmatches(bn, m)[[1L]]
    if (!length(mm)) next
    dest <- file.path(tables_dir, mm[2L])
    if (file.exists(dest)) next
    if (isTRUE(file.rename(f, dest))) n_restored <- n_restored + 1L
  }
  if (n_restored > 0L) {
    cli::cli_alert_info(
      "附表重排：已还原中断临时表 {n_restored} 个: {.file {basename(tables_dir)}}"
    )
  }
  stale <- list.files(
    tables_dir,
    pattern = "^\\.realign_(trail|tmp)_",
    full.names = TRUE,
    all.files = TRUE
  )
  if (length(stale)) {
    unlink(stale)
    cli::cli_alert_info(
      "已清理附表重排临时文件 {length(stale)} 个: {.file {basename(tables_dir)}}"
    )
  }
  invisible(length(stale))
}

incidence_batch_realign_dual_supp_tables <- function(tables_dir, cfg,
                                                     start_s = 1L) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  .incidence_batch_purge_realign_temp_tables(tables_dir)
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  # 含数字 S# 与字面量 S-XX
  files <- files[grepl("^Table S(\\d+|-XX)", basename(files), ignore.case = TRUE, perl = TRUE)]
  if (!length(files)) return(invisible(0L))

  # 发表顺序（双库 prognosis）：
  # S1 插补 S2 正态 S3 单因素 S4 VIF筛 S5 多因素 S6 VIF终
  # S7 统一协变量后再多因素 S8 相关性 S9 中介 S10 分位基线 S11 分段Cox
  slot_order <- c(
    "imputation", "normality",
    "univariate", "vif_screen", "multivariate", "vif_final",
    "multivariate_harmonized",
    "lab_assoc", "mediation",
    "baseline_by_index", "segmented_cox", "ph_test",
    "unweighted_baseline", "unweighted_logistic"
  )
  rcs_slot <- "rcs_logistic"
  db_order <- c(
    dual_db_slot_path_name(cfg, "nhanes"),
    dual_db_slot_path_name(cfg, "mimic")
  )

  # 同角色+同库若有多份（Gate E 重跑中介等），只保留 mtime 最新，删除多余。
  # 例外：两份无括号的 "Multivariable Regression Analysis"（S6 全池 vs S8 VIF-final）
  # 按当前 S 号较小→multivariate，较大→multivariate_harmonized。
  # 例外2：两份裸名 Weighted Multicollinearity（短标题剥掉 screen/final）
  # 按当前 S 号较小→vif_screen，较大→vif_final。
  fi <- file.info(files)
  ord_keep <- order(fi$mtime, decreasing = TRUE, na.last = TRUE)
  files <- files[ord_keep]
  keyed <- list()
  n_drop_dup <- 0L
  mv_plain <- list()
  vif_plain <- list()
  for (f in files) {
    bn <- basename(f)
    slot <- incidence_batch_classify_dual_supp_table(bn)
    db   <- incidence_batch_extract_pub_db_tag(bn, cfg)
    if (is.na(db)) next
    plain_mv <- identical(slot, "multivariate") &&
      grepl("Multivariable Regression Analysis\\.xlsx$", bn, ignore.case = TRUE) &&
      !grepl("harmonized", bn, ignore.case = TRUE)
    if (isTRUE(plain_mv)) {
      mv_plain[[db]] <- c(mv_plain[[db]], f)
      next
    }
    plain_vif <- is.na(slot) &&
      grepl("Weighted Multicollinearity Analysis\\.xlsx$", bn, ignore.case = TRUE)
    if (isTRUE(plain_vif)) {
      vif_plain[[db]] <- c(vif_plain[[db]], f)
      next
    }
    if (is.na(slot)) next
    k <- paste(slot, db, sep = "\x01")
    if (k %in% names(keyed)) {
      tryCatch(unlink(f), error = function(e) NULL)
      n_drop_dup <- n_drop_dup + 1L
      next
    }
    keyed[[k]] <- f
  }
  for (db in names(vif_plain)) {
    fs <- unique(as.character(vif_plain[[db]]))
    if (!length(fs)) next
    s_now <- vapply(fs, function(p) {
      m <- regexec("^Table S(\\d+)", basename(p))
      mm <- regmatches(basename(p), m)[[1L]]
      if (length(mm)) as.integer(mm[2L]) else NA_integer_
    }, integer(1L))
    # 行数多的通常是 screen 全池；行数少的是 final；再辅以 S 号
    n_rows <- vapply(fs, function(p) {
      tryCatch({
        if (!requireNamespace("readxl", quietly = TRUE)) return(NA_integer_)
        nrow(readxl::read_excel(p, col_names = FALSE))
      }, error = function(e) NA_integer_)
    }, integer(1L))
    ord <- order(-n_rows, s_now, file.info(fs)$mtime, na.last = TRUE)
    fs <- fs[ord]
    k_scr <- paste("vif_screen", db, sep = "\x01")
    k_fin <- paste("vif_final", db, sep = "\x01")
    if (!(k_scr %in% names(keyed))) {
      keyed[[k_scr]] <- fs[[1L]]
      # 落盘时改成可分类的短标题，避免下次再进 trail
      new_bn <- sub(
        "Weighted Multicollinearity Analysis\\.xlsx$",
        "Multicollinearity Analysis VIF screen.xlsx",
        basename(fs[[1L]]),
        ignore.case = TRUE
      )
      if (!identical(new_bn, basename(fs[[1L]]))) {
        new_p <- file.path(dirname(fs[[1L]]), new_bn)
        if (!file.exists(new_p) && isTRUE(file.rename(fs[[1L]], new_p))) {
          keyed[[k_scr]] <- new_p
          incidence_batch_sync_supp_table_title(new_p)
        }
      }
      fs <- fs[-1L]
    }
    if (length(fs) && !(k_fin %in% names(keyed))) {
      keyed[[k_fin]] <- fs[[1L]]
      new_bn <- sub(
        "Weighted Multicollinearity Analysis\\.xlsx$",
        "Multicollinearity Analysis VIF final.xlsx",
        basename(fs[[1L]]),
        ignore.case = TRUE
      )
      if (!identical(new_bn, basename(fs[[1L]]))) {
        new_p <- file.path(dirname(fs[[1L]]), new_bn)
        if (!file.exists(new_p) && isTRUE(file.rename(fs[[1L]], new_p))) {
          keyed[[k_fin]] <- new_p
          incidence_batch_sync_supp_table_title(new_p)
        }
      }
      fs <- fs[-1L]
    }
    if (length(fs)) {
      tryCatch(unlink(fs), error = function(e) NULL)
      n_drop_dup <- n_drop_dup + length(fs)
    }
  }
  for (db in names(mv_plain)) {
    fs <- unique(as.character(mv_plain[[db]]))
    if (!length(fs)) next
    s_now <- vapply(fs, function(p) {
      m <- regexec("^Table S(\\d+)", basename(p))
      mm <- regmatches(basename(p), m)[[1L]]
      if (length(mm)) as.integer(mm[2L]) else NA_integer_
    }, integer(1L))
    ord <- order(s_now, file.info(fs)$mtime, na.last = TRUE)
    fs <- fs[ord]
    k_mv <- paste("multivariate", db, sep = "\x01")
    k_harm <- paste("multivariate_harmonized", db, sep = "\x01")
    # 已有「Final multivariable model」时：全部 plain Multivariable 只保留最早一份作全池 S5，
    # 绝不能把第二份 plain 冒充 S7（否则盖住与 Table 2 同协变量的锁定终模型）。
    if (k_harm %in% names(keyed)) {
      keyed[[k_mv]] <- fs[[1L]]
      extra <- fs[-1L]
      if (length(extra)) {
        tryCatch(unlink(extra), error = function(e) NULL)
        n_drop_dup <- n_drop_dup + length(extra)
      }
      next
    }
    keyed[[k_mv]] <- fs[[1L]]
    # 旧命名兼容：两份均叫 Multivariable Regression Analysis 时，较大 S 号视为锁定终模型
    if (length(fs) >= 2L) {
      keyed[[k_harm]] <- fs[[length(fs)]]
      extra <- fs[-c(1L, length(fs))]
      if (length(extra)) {
        tryCatch(unlink(extra), error = function(e) NULL)
        n_drop_dup <- n_drop_dup + length(extra)
      }
    }
  }
  if (n_drop_dup > 0L) {
    cli::cli_alert_info("附表对齐：删除 {n_drop_dup} 个重复角色表（保留最新）")
  }

  # S6 临床交集空（auto 回退 S4 / 显式 vif_screen / lock 预设）→ 省略 multivariate(S5) 与 vif_final(S6)，编号顺延
  omit_mv_final <- FALSE
  root_gb <- as.character(
    (cfg$project %||% list())$root %||%
      (cfg$incidence_batch %||% list())$output_base %||%
      ""
  )[1L]
  if (exists("dual_db_load_gate_b", mode = "function") && nzchar(root_gb)) {
    gb <- tryCatch(dual_db_load_gate_b(root_gb, cfg), error = function(e) NULL)
    omit_mv_final <- isTRUE(gb$omit_multivariate_and_vif_final_tables) ||
      identical(as.character(gb$covariate_source_used %||% "")[1L], "vif_screen")
  }
  # 显式用单因素 VIF screen（含 lock 后改源）时也不出 S5/S6
  if (!isTRUE(omit_mv_final) && exists("dual_db_harmonization_covariate_source", mode = "function")) {
    if (identical(dual_db_harmonization_covariate_source(cfg), "vif_screen")) {
      omit_mv_final <- TRUE
    }
  }
  # 探测 S6 临床交集：空则省略（含 lock 预设绕过 auto 标记的情况）
  if (!isTRUE(omit_mv_final) && nzchar(root_gb) &&
      exists("dual_db_probe_gate_b_clinical_intersection", mode = "function")) {
    probe_s6 <- tryCatch(
      dual_db_probe_gate_b_clinical_intersection(root_gb, cfg, source = "vif_final"),
      error = function(e) NULL
    )
    if (!is.null(probe_s6) && !isTRUE(probe_s6$ok) &&
        identical(as.character(probe_s6$reason %||% "")[1L], "empty_clinical_intersection")) {
      omit_mv_final <- TRUE
    }
  }
  if (isTRUE(omit_mv_final)) {
    drop_slots <- c("multivariate", "vif_final")
    n_omit <- 0L
    for (slot in drop_slots) {
      for (db in db_order) {
        k <- paste(slot, db, sep = "\x01")
        if (!k %in% names(keyed)) next
        tryCatch(unlink(keyed[[k]]), error = function(e) NULL)
        keyed[[k]] <- NULL
        n_omit <- n_omit + 1L
      }
    }
    # 清掉尚未入 keyed 的同角色残留（含短标题）
    leftovers <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    for (f in leftovers) {
      sl <- incidence_batch_classify_dual_supp_table(basename(f))
      if (!is.na(sl) && sl %in% drop_slots) {
        tryCatch(unlink(f), error = function(e) NULL)
        n_omit <- n_omit + 1L
      }
    }
    slot_order <- setdiff(slot_order, drop_slots)
    if (n_omit > 0L) {
      cli::cli_alert_info(
        "附表对齐：S6 临床交集空已回退 S4 → 已省略多因素/VIF final（原 S5/S6）{n_omit} 张，后续编号顺延"
      )
    }
  }

  if (!length(keyed)) return(invisible(0L))

  .supp_s_prefix_sub <- function(bn, new_prefix) {
    sub("^Table S(?:\\d+|-XX)", new_prefix, bn, perl = TRUE, ignore.case = TRUE)
  }

  renames <- list()
  s <- as.integer(start_s)[1L]
  for (slot in slot_order) {
    slot_had <- FALSE
    for (db in db_order) {
      k <- paste(slot, db, sep = "\x01")
      if (!k %in% names(keyed)) next
      slot_had <- TRUE
      old <- keyed[[k]]
      new_bn <- .supp_s_prefix_sub(basename(old), sprintf("Table S%d", s))
      new_path <- file.path(tables_dir, new_bn)
      if (!identical(normalizePath(old, winslash = "/", mustWork = FALSE),
                     normalizePath(new_path, winslash = "/", mustWork = FALSE))) {
        renames[[old]] <- new_path
      } else {
        incidence_batch_sync_supp_table_title(old, new_s = s)
      }
    }
    # 仅当本角色至少有一张表时占用 S 号（避免预后专用槽空占发病 S10/S11）
    if (isTRUE(slot_had)) s <- s + 1L
  }
  # RCS → Table S-XX-<DB>
  for (db in db_order) {
    k <- paste(rcs_slot, db, sep = "\x01")
    if (!k %in% names(keyed)) next
    old <- keyed[[k]]
    new_bn <- .supp_s_prefix_sub(basename(old), "Table S-XX")
    new_path <- file.path(tables_dir, new_bn)
    if (!identical(normalizePath(old, winslash = "/", mustWork = FALSE),
                   normalizePath(new_path, winslash = "/", mustWork = FALSE))) {
      renames[[old]] <- new_path
    } else {
      incidence_batch_sync_supp_table_title(old, new_s = "XX")
    }
  }

  n_chain <- length(renames)
  if (length(renames)) {
    tmp_map <- list()
    i <- 0L
    for (old in names(renames)) {
      i <- i + 1L
      tmp <- file.path(tables_dir, sprintf(".realign_tmp_%03d_%s", i, basename(old)))
      if (file.exists(tmp)) unlink(tmp)
      file.rename(old, tmp)
      tmp_map[[renames[[old]]]] <- tmp
    }
    for (new in names(tmp_map)) {
      if (file.exists(new)) unlink(new)
      file.rename(tmp_map[[new]], new)
      # 从新文件名解析：S-XX 或数字
      if (grepl("^Table S-XX", basename(new), ignore.case = TRUE)) {
        incidence_batch_sync_supp_table_title(new, new_s = "XX")
      } else {
        incidence_batch_sync_supp_table_title(new)
      }
    }
  }

  # 未归入角色链的其余附表：紧接数字链之后按 S 号重编号（不含 RCS/S-XX）
  next_s <- as.integer(s)[1L]
  if (!is.finite(next_s) || next_s < 1L) {
    next_s <- as.integer(start_s)[1L] + length(slot_order)
  }
  chain_slots <- c(slot_order, rcs_slot)
  trail <- list.files(tables_dir, pattern = "^Table S\\d+.*\\.xlsx$", full.names = TRUE)
  trail_info <- lapply(trail, function(f) {
    bn <- basename(f)
    slot <- incidence_batch_classify_dual_supp_table(bn)
    db <- incidence_batch_extract_pub_db_tag(bn, cfg)
    m <- regexec("^Table S(\\d+)", bn)
    mm <- regmatches(bn, m)[[1L]]
    s_now <- if (length(mm)) as.integer(mm[2L]) else NA_integer_
    list(path = f, bn = bn, slot = slot, db = db, s = s_now)
  })
  trail_info <- Filter(function(x) is.na(x$slot) || !x$slot %in% chain_slots, trail_info)
  trail_info <- Filter(function(x) !grepl("ROC", x$bn, ignore.case = TRUE), trail_info)
  trail_info <- Filter(function(x) !grepl("^Table S-XX", x$bn, ignore.case = TRUE), trail_info)
  if (length(trail_info)) {
    ord <- order(
      vapply(trail_info, function(x) x$s %||% 999L, integer(1)),
      vapply(trail_info, function(x) {
        match(x$db %||% "", db_order, nomatch = 99L)
      }, integer(1)),
      vapply(trail_info, function(x) x$db %||% "", character(1)),
      vapply(trail_info, function(x) x$bn, character(1))
    )
    trail_info <- trail_info[ord]
    role_key <- function(bn) {
      sub("^Table S\\d+(?:-[A-Za-z0-9_]+)?\\.", "Table S.", bn)
    }
    roles <- unique(vapply(trail_info, function(x) role_key(x$bn), character(1)))
    trail_renames <- list()
    s_t <- next_s
    for (rk in roles) {
      members <- Filter(function(x) identical(role_key(x$bn), rk), trail_info)
      members <- members[order(vapply(members, function(x) {
        match(x$db %||% "", db_order, nomatch = 99L)
      }, integer(1)))]
      for (x in members) {
        new_bn <- sub("^Table S\\d+", sprintf("Table S%d", s_t), x$bn, perl = TRUE)
        new_path <- file.path(tables_dir, new_bn)
        if (!identical(x$bn, new_bn)) {
          trail_renames[[x$path]] <- new_path
        } else {
          incidence_batch_sync_supp_table_title(x$path, new_s = s_t)
        }
      }
      s_t <- s_t + 1L
    }
    if (length(trail_renames)) {
      tmp_map <- list()
      i <- 0L
      for (old in names(trail_renames)) {
        i <- i + 1L
        tmp <- file.path(tables_dir, sprintf(".realign_trail_%03d_%s", i, basename(old)))
        if (file.exists(tmp)) unlink(tmp)
        file.rename(old, tmp)
        tmp_map[[trail_renames[[old]]]] <- tmp
      }
      for (new in names(tmp_map)) {
        if (file.exists(new)) unlink(new)
        file.rename(tmp_map[[new]], new)
        incidence_batch_sync_supp_table_title(new)
      }
      n_chain <- n_chain + length(trail_renames)
    }
  }

  if (!n_chain) return(invisible(0L))
  cli::cli_alert_success(
    sprintf(
      "双库附表编号已对齐（S%d…数字链 + RCS→S-XX；表内标题已同步）: %d 个文件",
      as.integer(start_s)[1L],
      n_chain
    )
  )
  invisible(n_chain)
}

# 单库也把 RCS cutoff logistic 从 Table S# 改成 Table S-XX（不重排其余 S 号）
incidence_batch_rename_rcs_tables_to_sxx <- function(tables_dir, cfg = list()) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  n <- 0L
  for (f in files) {
    bn <- basename(f)
    if (!identical(incidence_batch_classify_dual_supp_table(bn), "rcs_logistic")) next
    if (grepl("^Table S-XX", bn, ignore.case = TRUE)) {
      incidence_batch_sync_supp_table_title(f, new_s = "XX")
      next
    }
    new_bn <- sub(
      "^Table S(?:\\d+|-XX)", "Table S-XX", bn,
      perl = TRUE, ignore.case = TRUE
    )
    if (identical(new_bn, bn)) next
    new_path <- file.path(tables_dir, new_bn)
    if (file.exists(new_path) &&
        !identical(
          normalizePath(f, winslash = "/", mustWork = FALSE),
          normalizePath(new_path, winslash = "/", mustWork = FALSE)
        )) {
      unlink(new_path)
    }
    if (file.rename(f, new_path)) {
      incidence_batch_sync_supp_table_title(new_path, new_s = "XX")
      n <- n + 1L
    }
  }
  if (n > 0L) {
    cli::cli_alert_info("RCS 附表已改为 Table S-XX: {n} 个 ({.file {basename(tables_dir)}})")
  }
  invisible(n)
}

# 数字 S 号按「表角色」压成连续 S1…Sn（不改 S-XX / Table 1–2）。
# 双库根目录 Tables：同一角色两库共用一个 S 号（Table S1-eICU + Table S1-MIMIC），
# 禁止一库一号压成 S1…S22。单库目录每个角色仍各占一号。
incidence_batch_compact_supp_s_numbers <- function(tables_dir, cfg = list()) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  files <- list.files(
    tables_dir,
    pattern = "^Table S\\d+.*\\.xlsx$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  files <- files[!grepl("^Table S-XX", basename(files), ignore.case = TRUE)]
  if (!length(files)) return(invisible(0L))
  role_key <- function(bn) {
    slot <- tryCatch(
      incidence_batch_classify_dual_supp_table(bn),
      error = function(e) NA_character_
    )
    if (!is.na(slot) && nzchar(as.character(slot)[1L])) {
      # Weighted associations vs Associations of … 同一 lab_assoc，避免双库拆成两个 S 号
      return(paste0("__slot__", as.character(slot)[1L]))
    }
    sub(
      "^Table S\\d+(?:-[A-Za-z0-9_]+)?\\.",
      "Table S.",
      bn,
      perl = TRUE,
      ignore.case = TRUE
    )
  }
  recs <- lapply(files, function(f) {
    bn <- basename(f)
    m <- regexec("^Table S(\\d+)", bn, ignore.case = TRUE)
    mm <- regmatches(bn, m)[[1L]]
    s <- if (length(mm) >= 2L) as.integer(mm[2L]) else NA_integer_
    db <- tryCatch(
      incidence_batch_extract_pub_db_tag(bn, cfg),
      error = function(e) NA_character_
    )
    if (is.na(db) || !nzchar(db)) {
      mdb <- regexec("^Table S\\d+-([A-Za-z0-9_]+)\\.", bn, perl = TRUE)
      mmb <- regmatches(bn, mdb)[[1L]]
      db <- if (length(mmb) >= 2L) mmb[2L] else ""
    }
    list(path = f, bn = bn, s = s, db = db, role = role_key(bn))
  })
  recs <- Filter(function(x) is.finite(x$s), recs)
  if (!length(recs)) return(invisible(0L))
  # 同库同标题多份（全池 MV vs harmonized MV）按当前 S 号拆成 occ=1,2,…；
  # 跨库用 (role, occ) 配对，两库共用一个 S 号。
  recs <- recs[order(
    vapply(recs, function(x) x$role, character(1)),
    vapply(recs, function(x) x$db, character(1)),
    vapply(recs, function(x) as.integer(x$s), integer(1))
  )]
  occ_seen <- list()
  for (i in seq_along(recs)) {
    k <- paste(recs[[i]]$db, recs[[i]]$role, sep = "\x01")
    occ_seen[[k]] <- as.integer(occ_seen[[k]] %||% 0L) + 1L
    recs[[i]]$occ <- occ_seen[[k]]
    recs[[i]]$slot <- paste(recs[[i]]$role, recs[[i]]$occ, sep = "\x01")
  }
  roles <- unique(vapply(recs, function(x) x$slot, character(1)))
  role_min_s <- vapply(roles, function(rk) {
    min(vapply(
      Filter(function(x) identical(x$slot, rk), recs),
      function(x) as.integer(x$s),
      integer(1)
    ))
  }, integer(1))
  roles <- roles[order(role_min_s, roles)]
  target_s <- seq_along(roles)
  names(target_s) <- roles

  already <- vapply(recs, function(x) {
    identical(as.integer(x$s), as.integer(unname(target_s[[x$slot]])))
  }, logical(1))
  if (all(already)) return(invisible(0L))

  tmp_map <- list()
  n <- 0L
  i <- 0L
  for (x in recs) {
    new_s <- as.integer(unname(target_s[[x$slot]]))
    if (identical(as.integer(x$s), new_s)) {
      incidence_batch_sync_supp_table_title(x$path, new_s = new_s)
      next
    }
    i <- i + 1L
    new_bn <- sub("^Table S\\d+", sprintf("Table S%d", new_s), x$bn, ignore.case = TRUE)
    new_path <- file.path(tables_dir, new_bn)
    tmp <- file.path(tables_dir, sprintf(".compact_tmp_%03d_%s", i, x$bn))
    if (file.exists(tmp)) unlink(tmp)
    if (!isTRUE(file.rename(x$path, tmp))) next
    tmp_map[[new_path]] <- list(tmp = tmp, new_s = new_s)
    n <- n + 1L
  }
  for (new in names(tmp_map)) {
    rec <- tmp_map[[new]]
    if (file.exists(new)) unlink(new)
    file.rename(rec$tmp, new)
    incidence_batch_sync_supp_table_title(new, new_s = rec$new_s)
  }
  if (n > 0L) {
    cli::cli_alert_info(
      "附表 S 号已按角色压成连续编号（双库同号）: {n} 个 ({.file {basename(tables_dir)}})"
    )
  }
  invisible(n)
}

incidence_batch_index_disp_from_bn <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  pats <- c(
    "Associations of ([A-Za-z0-9][A-Za-z0-9 ._-]*?) with",
    "associations of ([A-Za-z0-9][A-Za-z0-9 ._-]*?)(?: and | with |\\.xlsx)",
    "Mediation analysis of ([A-Za-z0-9][A-Za-z0-9 ._-]*?)(?:\\.xlsx|$)",
    "Logistic regression(?: analysis)? of ([A-Za-z0-9][A-Za-z0-9 ._-]*?)(?: and | RCS| quartile| tertile| binary| quintile| unweighted|\\.xlsx)"
  )
  for (p in pats) {
    m <- regexec(p, bn, ignore.case = TRUE, perl = TRUE)
    mm <- regmatches(bn, m)[[1L]]
    if (length(mm) >= 2L && nzchar(trimws(mm[2L]))) {
      return(trimws(gsub("_", " ", mm[2L])))
    }
  }
  ix <- as.character(
    (cfg$study_batch %||% list())$active_unit %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$survival %||% list())$index_var %||%
      ""
  )[1L]
  if (nzchar(ix)) return(gsub("_", " ", ix, fixed = TRUE))
  "index"
}

incidence_batch_short_caption_for_pub_table <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  ix <- incidence_batch_index_disp_from_bn(bn, cfg)
  if (grepl("^Table \\d+", bn) && !grepl("^Table S", bn, ignore.case = TRUE)) {
    if (grepl("Baseline characteristics", bn, ignore.case = TRUE)) {
      cap <- sub(
        "^Table \\d+(?:-[A-Za-z][A-Za-z0-9_]*(?:[ _][A-Za-z0-9_]+)*)?\\.\\s*",
        "",
        tools::file_path_sans_ext(bn)
      )
      return(pub_caption_strip_parentheses(cap))
    }
    if (grepl("Logistic regression", bn, ignore.case = TRUE)) {
      scheme <- if (grepl("quintile", bn, ignore.case = TRUE)) {
        "quintile"
      } else if (grepl("tertile", bn, ignore.case = TRUE)) {
        "tertile"
      } else if (grepl("binary", bn, ignore.case = TRUE)) {
        "binary"
      } else if (grepl("quartile", bn, ignore.case = TRUE)) {
        "quartile"
      } else {
        ""
      }
      if (exists("logistic_glm_pub_caption", mode = "function")) {
        return(logistic_glm_pub_caption(ix, scheme = scheme, is_rcs = FALSE))
      }
      return(trimws(sprintf("Logistic regression of %s %s", ix, scheme)))
    }
  }
  role <- incidence_batch_classify_dual_supp_table(bn)
  out <- switch(
    as.character(role %||% ""),
    imputation = {
      if (grepl("validation", bn, ignore.case = TRUE)) {
        "Baseline characteristics before and after imputation (validation set)"
      } else {
        # 发病/预后全队列：不加 training set（ML 划分才标注）
        "Baseline characteristics before and after imputation"
      }
    },
    normality = "Normality test results for continuous variables",
    univariate = "Univariate Regression Analysis",
    vif_screen = "Multicollinearity Analysis VIF screen",
    multivariate = "Multivariable Regression Analysis",
    vif_final = "Multicollinearity Analysis VIF final",
    multivariate_harmonized = if (
      exists("locked_mv_n_databases", mode = "function") &&
        locked_mv_n_databases(cfg) >= 2L
    ) {
      "Final multivariable model harmonized"
    } else {
      "Final multivariable model"
    },
    lab_assoc = sprintf("Associations of %s with laboratory indicators", ix),
    mediation = sprintf("Mediation analysis of %s", ix),
    rcs_logistic = sprintf("Logistic regression of %s RCS cutoff", ix),
    {
      cap <- sub(
        "^Table (?:S(?:-?XX|\\d+)|\\d+)(?:-[A-Za-z][A-Za-z0-9_]*(?:[ _][A-Za-z0-9_]+)*)?\\.\\s*",
        "",
        tools::file_path_sans_ext(bn)
      )
      pub_caption_strip_parentheses(cap)
    }
  )
  pub_caption_strip_parentheses(out)
}

incidence_batch_write_xlsx_title <- function(path, title) {
  path <- as.character(path)[1L]
  if (!file.exists(path)) return(invisible(FALSE))
  # 已导出的 SCI xlsx 禁止直接 loadWorkbook→saveWorkbook：含历史 drawing/
  # inlineStr 的工作簿可能在该往返中只剩标题行。统一走先 strip、改单格、
  # 再校验的外科式入口（R/pub_xlsx_surgical.R）。
  if (!exists("pub_xlsx_edit_cells", mode = "function")) {
    roots <- unique(c(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
      getwd(), file.path(getwd(), "..")
    ))
    src <- file.path(roots[nzchar(roots)], "R", "pub_xlsx_surgical.R")
    src <- src[file.exists(src)]
    if (length(src)) {
      try(source(src[1L], local = FALSE), silent = TRUE)
    }
  }
  if (!exists("pub_xlsx_edit_cells", mode = "function")) return(invisible(FALSE))
  ok <- tryCatch({
    pub_xlsx_edit_cells(
      path,
      data.frame(row = 1L, col = 1L, value = as.character(title)[1L]),
      root = Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    )
    TRUE
  }, error = function(e) FALSE)
  invisible(isTRUE(ok))
}

# 发表表：去括号、短标题、文件名≤76、表内外标题对齐（不改 S-XX 字面量）
incidence_batch_shorten_pub_table_names <- function(tables_dir, cfg = list()) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  files <- files[grepl("^Table ", basename(files), ignore.case = TRUE)]
  files <- files[!grepl("ROC", basename(files), ignore.case = TRUE)]
  if (!length(files)) return(invisible(0L))
  n <- 0L
  for (old in files) {
    bn <- basename(old)
    m <- regexec(
      "^(Table (?:S(?:-?XX|\\d+)|\\d+))(?:-([A-Za-z][A-Za-z0-9_]*(?:[ _][A-Za-z0-9_]+)*))?\\.\\s*",
      bn,
      perl = TRUE
    )
    mm <- regmatches(bn, m)[[1L]]
    if (!length(mm)) next
    pref <- mm[2L]
    db <- mm[3L]
    cap <- incidence_batch_short_caption_for_pub_table(bn, cfg)
    stem <- if (!is.na(db) && nzchar(db)) {
      sprintf("%s-%s. %s", pref, db, cap)
    } else {
      sprintf("%s. %s", pref, cap)
    }
    stem <- pub_fit_table_stem(stem, "xlsx")
    new_bn <- paste0(stem, ".xlsx")
    new_path <- file.path(tables_dir, new_bn)
    if (!identical(bn, new_bn)) {
      if (file.exists(new_path) &&
          !identical(
            normalizePath(old, winslash = "/", mustWork = FALSE),
            normalizePath(new_path, winslash = "/", mustWork = FALSE)
          )) {
        unlink(new_path)
      }
      if (!isTRUE(file.rename(old, new_path))) next
      n <- n + 1L
    } else {
      new_path <- old
    }
    incidence_batch_write_xlsx_title(new_path, stem)
  }
  if (n > 0L) {
    cli::cli_alert_info(
      "发表表已缩短去括号: {n} 个 ({.file {basename(tables_dir)}})"
    )
  }
  invisible(n)
}

# 汇总/单库 Tables：双库统一后删非 unified 旧 Table 2；主文只留闸门最终分位
incidence_batch_purge_stale_main_logistic_and_subgroup_tables <- function(
    tables_dir, cfg = list(), purge_sensitivity = TRUE) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  hits <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  bn <- basename(hits)
  has_unified <- grepl("^Table 2-.*dual-DB unified", bn, ignore.case = TRUE)
  drop <- logical(length(hits))
  # 若存在 dual-DB unified Table 2，删除同库非 unified 的 Table 2
  if (any(has_unified)) {
    for (i in which(has_unified)) {
      db_tag <- sub("^Table 2-([A-Za-z0-9]+)\\..*$", "\\1", bn[i])
      drop <- drop | (
        grepl(paste0("^Table 2-", db_tag, "\\."), bn, ignore.case = TRUE) &
          !grepl("dual-DB unified", bn, ignore.case = TRUE)
      )
    }
  }
  # 亚组已有森林图，汇总目录不留 Table_Subgroup_Analysis_*
  drop <- drop | grepl("^Table_Subgroup_Analysis_", bn, ignore.case = TRUE)
  # 闸门筛查残留：Table 3+（含 Table 7/8 误编号）一律不进主文
  drop <- drop | grepl("^Table ([3-9]|[1-9][0-9])-", bn, ignore.case = TRUE)
  # 只留闸门选定分位的 Table 2；其它分位主表删除
  scheme <- as.character(
    (cfg$logistic_gate %||% list())$grouping %||%
      (cfg$cox_gate %||% list())$grouping %||%
      ((cfg$dual_db %||% list())$harmonization %||% list())$grouping %||%
      (cfg$study_batch %||% list())$selected_grouping %||%
      ""
  )[1L]
  scheme <- tolower(trimws(scheme))
  all_schemes <- c("quartile", "tertile", "binary", "quintile", "median")
  # 双库时各库 logistic gate 的 grouping 可能不同（如 NHANES degrade 到 binary、
  # CHARLS 仍为 quartile）。此时不能用单一 scheme 删所有库的 Table 2，否则会误删
  # 另一库成功分位的 Table 2。双库统一表由 unified 机制（has_unified）处理。
  is_dual <- isTRUE((cfg$dual_db %||% list())$enable) &&
    length((cfg$dual_db %||% list())$databases %||%
           c((cfg$dual_db %||% list())$primary$name,
             (cfg$dual_db %||% list())$secondary$name)) >= 2L
  if (!is_dual && nzchar(scheme) && scheme %in% all_schemes) {
    for (o in setdiff(all_schemes, scheme)) {
      drop <- drop | grepl(
        paste0("^Table 2-.*\\b", o, "\\b"), bn, ignore.case = TRUE
      )
      # 未选中分位的 logistic 附表（如选了 tertile 却留 binary）不进汇总
      drop <- drop | (
        grepl("Logistic regression", bn, ignore.case = TRUE) &
          grepl(paste0("\\b", o, "\\b"), bn, ignore.case = TRUE) &
          !grepl("RCS cutoff|Sensitivity analysis", bn, ignore.case = TRUE)
      )
    }
  } else if (!is_dual) {
    drop <- drop | grepl("^Table 2-.*\\b(quartile|binary|quintile)\\b", bn, ignore.case = TRUE)
    drop <- drop | (
      grepl("Logistic regression", bn, ignore.case = TRUE) &
        grepl("\\b(quartile|binary|quintile)\\b", bn, ignore.case = TRUE) &
        !grepl("RCS cutoff|Sensitivity analysis", bn, ignore.case = TRUE) &
        grepl("^Table S", bn, ignore.case = TRUE)
    )
  }
  # 主文汇总目录不混放敏感性 SA 表（单库 Tables 可保留）
  if (isTRUE(purge_sensitivity)) {
    drop <- drop | grepl("Sensitivity analysis", bn, ignore.case = TRUE)
  }
  hits <- hits[drop]
  if (!length(hits)) return(invisible(0L))
  unlink(hits)
  cli::cli_alert_info("已移除汇总目录陈旧 Table2/亚组表 {length(hits)} 个")
  invisible(length(hits))
}

#' mirror 前清空指标根汇总 Tables/Figures 缓存，避免旧命名/旧拼图残留
incidence_batch_purge_aggregate_pub_cache <- function(index_root) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(0L))
  }
  n <- 0L
  agg_tables <- file.path(index_root, "Tables")
  if (dir.exists(agg_tables)) {
    stale <- list.files(agg_tables, pattern = "\\.(xlsx|csv|tex)$", full.names = TRUE, ignore.case = TRUE)
    stale <- stale[!grepl("^(Analysis_exclusion_|Flowchart_attrition)", basename(stale), ignore.case = TRUE)]
    if (length(stale)) {
      unlink(stale)
      n <- n + length(stale)
    }
  }
  agg_figs <- file.path(index_root, "Figures")
  if (dir.exists(agg_figs)) {
    root_pdfs <- list.files(agg_figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
    root_pdfs <- root_pdfs[!file.info(root_pdfs)$isdir]
    if (length(root_pdfs)) {
      unlink(root_pdfs)
      n <- n + length(root_pdfs)
    }
    if (exists("pub_figure_purge_format_subdirs", mode = "function")) {
      n <- n + (pub_figure_purge_format_subdirs(agg_figs) %||% 0L)
    } else {
      for (sub in c("pdf", "png", "tiff", "image_information")) {
        d <- file.path(agg_figs, sub)
        if (!dir.exists(d)) next
        files <- list.files(d, full.names = TRUE, recursive = FALSE)
        if (length(files)) {
          unlink(files)
          n <- n + length(files)
        }
      }
    }
  }
  if (n > 0L) {
    cli::cli_alert_info("已清空指标汇总发表缓存 {n} 个: {.file {basename(index_root)}}")
  }
  invisible(n)
}

# 汇总目录移除非发表临时表（特征选择中间表、TabPFN 导出、train/val 拆分表等）
incidence_batch_purge_aggregate_scratch_tables <- function(tables_dir) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  hits <- list.files(
    tables_dir,
    pattern = "\\.(xlsx|csv|tex)$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  bn <- basename(hits)
  drop <- grepl(
    "^(Table_FeatureSelection_|Table_ML_ModelPerformance|Table_1_Baseline_characteristics_train_val_split|.*_reticulate_export|Analysis_exclusion_)",
    bn,
    ignore.case = TRUE
  ) | grepl("\\.tex$", bn, ignore.case = TRUE) |
    grepl("^Flowchart_attrition", bn, ignore.case = TRUE)
  hits <- hits[drop]
  if (!length(hits)) return(invisible(0L))
  unlink(hits)
  cli::cli_alert_info("已移除汇总目录非发表表 {length(hits)} 个")
  invisible(length(hits))
}

# 汇总目录不保留 ROC 附表（避免占用 S3 等编号、干扰双库分析表排序）
incidence_batch_purge_aggregate_roc_tables <- function(tables_dir) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  hits <- list.files(
    tables_dir,
    pattern = "\\.xlsx$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  hits <- hits[grepl("ROC", basename(hits), ignore.case = TRUE)]
  if (!length(hits)) return(invisible(0L))
  unlink(hits)
  cli::cli_alert_info("已移除发表目录 ROC 附表 {length(hits)} 个（不参与 S 编号）")
  invisible(length(hits))
}

# 发表图排序键（对齐 Output_旋旋：S1 缺失/ROC → S3 韦恩 → ML 拼图 → 加权 SHAP → 最优 SHAP combined）
incidence_batch_pub_figure_sort_key <- function(basename) {
  bn <- as.character(basename)[1L]
  if (grepl("Missing Value|S1.*Missing", bn, ignore.case = TRUE)) return(110L)
  if (grepl("Figure S1.*ROC|ROC curve for", bn, ignore.case = TRUE)) return(120L)
  if (grepl("Figure S3.*Venn|Figure S3\\.Venn", bn, ignore.case = TRUE)) return(210L)
  if (grepl("ML performance combined 2x4|combined 2x4", bn, ignore.case = TRUE)) return(310L)
  if (grepl("Weighted SHAP", bn, ignore.case = TRUE)) return(410L)
  if (grepl("SHAP.*combined|SHAP \\(best|SHAP [—\\-–]", bn, ignore.case = TRUE)) return(420L)
  if (grepl("^Figure S2[A-G]", bn)) return(9000L)
  if (grepl("Figure SHAP .+ (bee|waterfall|importance|dependence)(\\.| )", bn, perl = TRUE)) return(9100L)
  if (grepl("Figure S-.*ML (performance|internal validation)", bn, ignore.case = TRUE)) return(9200L)
  m <- regexec("Figure ([0-9]+)", bn, perl = TRUE)[[1L]]
  if (length(m) >= 2L && m[1L] > 0L) {
    g <- regmatches(bn, list(m))[[1L]]
    if (length(g) >= 2L) return(500L + as.integer(g[2L]))
  }
  if (grepl("^Figure S", bn)) return(800L)
  9999L
}

incidence_batch_should_purge_pub_figure <- function(basename, all_basenames) {
  bn <- as.character(basename)[1L]
  all_bn <- as.character(all_basenames)
  if (grepl("^Figure S2[A-G]", bn)) return(TRUE)
  has_ml_combined <- any(grepl("ML performance combined 2x4|combined 2x4", all_bn, ignore.case = TRUE))
  if (has_ml_combined && grepl("Figure S-.*ML (performance|internal validation)", bn, ignore.case = TRUE)) {
    return(TRUE)
  }
  has_shap_combined <- any(grepl("SHAP.*combined|Weighted SHAP|SHAP [—\\-–]", all_bn, ignore.case = TRUE))
  if (has_shap_combined &&
      grepl("SHAP .+ (bee|waterfall|importance|dependence)(\\.| |$)", bn, ignore.case = TRUE, perl = TRUE)) {
    return(TRUE)
  }
  if (has_shap_combined &&
      grepl("Figure SHAP .+ (bee|waterfall|importance|dependence)(\\.| )", bn, perl = TRUE)) {
    return(TRUE)
  }
  FALSE
}

incidence_batch_pub_figure_scheme <- function(config) {
  bc <- config$incidence_batch %||% config$ml_batch %||% list()
  as.character(bc$pub_figure_scheme %||% "default")[1L]
}

incidence_batch_is_ml_dual_pub_scheme <- function(config) {
  incidence_batch_pub_figure_scheme(config) %in% c("ml_dual_standard", "ml_dual_dev_ext")
}

incidence_batch_ml_normalize_pub_bn <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  if (exists(".ml_ptc_normalize_bn", mode = "function")) {
    return(.ml_ptc_normalize_bn(bn, cfg))
  }
  bn <- sub("^[A-Za-z0-9._-]+_", "", bn)
  bn
}

incidence_batch_ml_extract_db_tag <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  tags <- character(0)
  if (exists(".ml_ptc_db_tags", mode = "function")) {
    tags <- as.character(.ml_ptc_db_tags(cfg))
  }
  if (exists("dual_db_slot_path_name", mode = "function")) {
    tags <- unique(c(
      tags,
      dual_db_slot_path_name(cfg, "nhanes"),
      dual_db_slot_path_name(cfg, "mimic")
    ))
  }
  tags <- unique(tags[nzchar(tags)])
  tags <- unique(unlist(lapply(tags[nzchar(tags)], function(t) {
    if (exists(".ml_ptc_tag_aliases", mode = "function")) .ml_ptc_tag_aliases(t) else t
  }), use.names = FALSE))
  tags <- tags[order(-nchar(tags), tags)]
  for (tag in tags) {
    flex <- if (exists(".ml_ptc_tag_flex_re", mode = "function")) {
      .ml_ptc_tag_flex_re(tag)
    } else {
      gsub(" ", "[ _]", tag, fixed = TRUE)
    }
    if (!nzchar(flex)) next
    if (grepl(paste0("-", flex, "\\."), bn, ignore.case = TRUE, perl = TRUE)) {
      return(if (exists(".ml_ptc_canonical_db_tag", mode = "function")) {
        .ml_ptc_canonical_db_tag(tag, cfg)
      } else tag)
    }
    if (grepl(paste0("^", flex, "[ _]"), bn, ignore.case = TRUE, perl = TRUE)) {
      return(if (exists(".ml_ptc_canonical_db_tag", mode = "function")) {
        .ml_ptc_canonical_db_tag(tag, cfg)
      } else tag)
    }
  }
  if (exists(".ml_ptc_extract_db_label", mode = "function")) {
    tag <- .ml_ptc_extract_db_label(bn, cfg)
    if (!identical(tag, "Combined")) return(tag)
  }
  if (grepl("-NHANES\\.", bn, ignore.case = TRUE)) return("NHANES")
  if (grepl("-MIMIC\\.", bn, ignore.case = TRUE)) return("MIMIC")
  if (grepl("-CHARLS\\.", bn, ignore.case = TRUE)) return("CHARLS")
  if (grepl("-ELSA\\.", bn, ignore.case = TRUE)) return("ELSA")
  if (grepl("-Hosp\\.", bn, ignore.case = TRUE)) return("Hosp")
  ## 双库拼图「Figure N. Caption」无库标签：不要回填主库名，否则 Fig8 会变成 Figure 8-MIMIC IV
  n_slot <- 0L
  if (exists("dual_db_slot_path_name", mode = "function")) {
    n_slot <- sum(nzchar(c(
      tryCatch(dual_db_slot_path_name(cfg, "nhanes"), error = function(e) ""),
      tryCatch(dual_db_slot_path_name(cfg, "mimic"), error = function(e) "")
    )))
  }
  if (n_slot < 2L && length(tags) >= 1L) {
    primary <- tags[[1L]]
    if (nzchar(primary) && !identical(tolower(primary), "unused")) return(primary)
  }
  NA_character_
}

incidence_batch_ml_pub_figure_role <- function(basename, cfg = list()) {
  bn <- as.character(basename)[1L]
  norm <- incidence_batch_ml_normalize_pub_bn(bn, cfg)
  scheme <- incidence_batch_pub_figure_scheme(cfg)
  with_cor <- identical(scheme, "ml_with_correlation")
  if (grepl("Flowchart", norm, ignore.case = TRUE)) return("fig1")
  if (grepl("RCS plot between|Weighted RCS|RCS of|RCS Analysis", norm, ignore.case = TRUE)) {
    ## AF 金标准（dev_ext）：Fig2=LASSO，Fig3–6=三集 ML；连续指标 RCS 不进主文图号
    if (identical(scheme, "ml_dual_dev_ext")) return("drop")
    return("fig2_rcs")
  }
  if (grepl("Feature selection", norm, ignore.case = TRUE)) {
    if (identical(scheme, "ml_dual_dev_ext")) return("fig2_fs")
    if (grepl("^Figure\\s*2", bn, ignore.case = TRUE)) return("fig2_fs")
    return("s1_fs")
  }
  ## 仅课题显式开启 pub_figure_scheme=ml_with_correlation 时纳入相关热图为 Figure 3
  ## 优先用 Filtered（已去高相关），未过滤全矩阵不进定稿 Figure 3
  if (grepl("Correlation Heatmap Filtered", norm, ignore.case = TRUE)) {
    if (with_cor) return("fig3_cor")
    return("drop")
  }
  if (grepl("Correlation Heatmap|Correlation Matrix|Spearman Correlation", norm, ignore.case = TRUE)) {
    if (with_cor) return("drop")
    return("drop")
  }
  if (grepl("Kaplan", norm, ignore.case = TRUE)) {
    if (identical(scheme, "ml_dual_dev_ext") &&
        grepl("joint", norm, ignore.case = TRUE)) {
      return("fig2_joint_km")
    }
    ## 含相关热图方案时 KM 不占主图号（本课题为发病 ML）
    if (with_cor) return("drop")
    return("fig3_km")
  }
  if (grepl("ML ROC training internal and external", norm, ignore.case = TRUE)) {
    return("fig3_ml_roc3")
  }
  if (grepl("ML calibration training internal and external", norm, ignore.case = TRUE)) {
    return("fig4_ml_cal3")
  }
  if (grepl("ML metrics training internal and external", norm, ignore.case = TRUE)) {
    return("fig5_ml_met3")
  }
  if (grepl("ML DCA training internal and external", norm, ignore.case = TRUE)) {
    return("fig6_ml_dca3")
  }
  if (grepl("ROC comparison of joint indices", norm, ignore.case = TRUE)) {
    return("s2_comparator")
  }
  if (grepl("landmark analysis", norm, ignore.case = TRUE)) {
    return("s3_landmark")
  }
  if (grepl("ML performance combined 2x4|combined 2x4", norm, ignore.case = TRUE)) {
    if (identical(scheme, "ml_dual_dev_ext")) return("drop")
    ## 无 KM/相关热图时 ML 占 Figure 3（连续编号）；有 cor/km 时仍为 fig4 槽由 target 压缩
    if (with_cor) return("fig4_ml")
    return("fig3_ml")
  }
  # 仅保留 SHAP 大拼图；单张 importance/bee/waterfall/dependence 不进汇总
  if (grepl("SHAP .+ (bee|waterfall|importance|dependence)(\\.| |$)", norm, ignore.case = TRUE, perl = TRUE)) {
    return("drop")
  }
  if (grepl("^Figure SHAP ", norm, ignore.case = TRUE)) return("drop")
  if (grepl("Weighted SHAP", norm, ignore.case = TRUE) ||
      grepl("SHAP.*combined|\\(logistic, incidence, combined\\)|\\([a-z0-9_]+, incidence, combined\\)|SHAP [—\\-–]",
            norm, ignore.case = TRUE, perl = TRUE) ||
      (grepl("SHAP", norm, ignore.case = TRUE) &&
         !grepl("bee|waterfall|importance|dependence", norm, ignore.case = TRUE))) {
    if (with_cor) return("fig5_shap")
    if (identical(scheme, "ml_dual_dev_ext")) return("fig7_shap")
    return("fig4_shap")
  }
  if (grepl("Subgroup Forest|Subgroup analyses|Subgroup of", norm, ignore.case = TRUE)) {
    if (grepl("Figure 7|prognosis|\\(Cox\\)", norm, ignore.case = TRUE)) {
      return("fig7_subgroup_cox")
    }
    if (with_cor) return("fig6_subgroup")
    if (identical(scheme, "ml_dual_dev_ext")) return("fig8_subgroup")
    return("fig5_subgroup")
  }
  if (grepl("Figure S1.*(Venn|Upset|Lasso|Boruta|Random|Bayesian|Bagged|LVQ|Feature selection)",
            norm, ignore.case = TRUE)) {
    ## 多方法韦恩/Upset，或单方法升格的 S1（含 LASSO 拼图）
    return("s1_fs")
  }
  if (grepl("^Figure S3.*(Venn|Upset)", norm, ignore.case = TRUE)) return("s1_fs")
  "drop"
}

incidence_batch_ml_pub_figure_clean_cap <- function(cap) {
  cap <- as.character(cap %||% "")[1L]
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  ## 反复剥掉 Figure N. / Figure N-库名. / 误套的 Figure N. Figure …
  for (i in seq_len(6L)) {
    nxt <- sub("^Figure\\s+[0-9]+([.-][^.]*)?\\.\\s*", "", cap, ignore.case = TRUE, perl = TRUE)
    nxt <- sub("^Figure\\s+S[0-9]+([.-][^.]*)?\\.\\s*", "", nxt, ignore.case = TRUE, perl = TRUE)
    nxt <- sub("^Figure\\s+", "", nxt, ignore.case = TRUE)
    if (identical(nxt, cap)) break
    cap <- nxt
  }
  cap <- sub("[- ]*(MIMIC(\\s*IV)?|NHANES|CHARLS|ELSA)\\s*$", "", cap, ignore.case = TRUE)
  cap <- trimws(gsub("\\s+", " ", cap))
  cap
}

incidence_batch_ml_pub_figure_target_bn <- function(role, src_bn, cfg = list()) {
  db_tag <- incidence_batch_ml_extract_db_tag(src_bn, cfg)
  ## 本课题含相关热图方案：主图不加库名；否则 Figure N-DB. …（与单库 step 一致）
  with_cor <- identical(incidence_batch_pub_figure_scheme(cfg), "ml_with_correlation")
  dev_ext <- identical(incidence_batch_pub_figure_scheme(cfg), "ml_dual_dev_ext")
  ## AF 口径：Fig2 LASSO / Fig3–6 三集图不加库名；SHAP/亚组仍可带主库标签
  db_inf <- if ((!with_cor && !dev_ext) && !is.na(db_tag) && nzchar(db_tag)) {
    paste0("-", db_tag)
  } else if (dev_ext && !is.na(db_tag) && nzchar(db_tag)) {
    paste0("-", db_tag)
  } else {
    ""
  }
  cap <- incidence_batch_ml_normalize_pub_bn(src_bn, cfg)
  cap <- incidence_batch_ml_pub_figure_clean_cap(cap)
  switch(role,
    fig1 = "Figure 1. Flowchart.pdf",
    fig2_rcs = {
      if (!nzchar(cap) || grepl("^Figure", cap, ignore.case = TRUE)) {
        cap <- "RCS plot"
      }
      paste0("Figure 2", db_inf, ". ", cap, ".pdf")
    },
    fig2_fs = if (isTRUE(dev_ext)) {
      "Figure 2. Feature selection LASSO.pdf"
    } else {
      paste0("Figure 2", db_inf, ". Feature selection LASSO.pdf")
    },
    fig2_joint_km = paste0(
      "Figure 2", db_inf, ". ",
      if (nzchar(cap)) cap else "Kaplan-Meier curves of joint groups",
      ".pdf"
    ),
    fig3_cor = paste0("Figure 3", db_inf, ". Correlation Heatmap.pdf"),
    fig3_km = paste0("Figure 3", db_inf, ". ", if (nzchar(cap)) cap else "Kaplan-Meier", ".pdf"),
    fig3_ml = paste0("Figure 3", db_inf, ". ML performance combined 2x4.pdf"),
    fig3_ml_roc3 = "Figure 3. ML ROC training internal and external.pdf",
    fig4_ml_cal3 = "Figure 4. ML calibration training internal and external.pdf",
    fig5_ml_met3 = "Figure 5. ML metrics training internal and external.pdf",
    fig6_ml_dca3 = "Figure 6. ML DCA training internal and external.pdf",
    fig4_ml = paste0("Figure 4", db_inf, ". ML performance combined 2x4.pdf"),
    fig4_shap = {
      m <- sub("^SHAP\\s*[—\\-–]\\s*(.+)$", "\\1", cap, perl = TRUE)
      if (!identical(m, cap) && nzchar(trimws(m))) {
        paste0("Figure 4", db_inf, ". SHAP (", trimws(m), ").pdf")
      } else {
        paste0("Figure 4", db_inf, ". SHAP.pdf")
      }
    },
    fig5_shap = {
      m <- sub("^SHAP\\s*[—\\-–]\\s*(.+)$", "\\1", cap, perl = TRUE)
      if (!identical(m, cap) && nzchar(trimws(m))) {
        paste0("Figure 5", db_inf, ". SHAP (", trimws(m), ").pdf")
      } else {
        paste0("Figure 5", db_inf, ". SHAP.pdf")
      }
    },
    fig5_subgroup = {
      if (!grepl("Subgroup", cap, ignore.case = TRUE)) {
        cap <- "Subgroup Forest"
      }
      paste0("Figure 5", db_inf, ". ", cap, ".pdf")
    },
    fig6_subgroup = {
      if (!grepl("Subgroup", cap, ignore.case = TRUE)) {
        cap <- "Subgroup Forest"
      }
      paste0("Figure 6", db_inf, ". ", cap, ".pdf")
    },
    fig7_shap = {
      m <- sub("^SHAP\\s*[—\\-–]\\s*(.+)$", "\\1", cap, perl = TRUE)
      if (!identical(m, cap) && nzchar(trimws(m))) {
        paste0("Figure 7", db_inf, ". SHAP (", trimws(m), ").pdf")
      } else {
        paste0("Figure 7", db_inf, ". SHAP.pdf")
      }
    },
    fig8_subgroup = {
      if (!grepl("Subgroup", cap, ignore.case = TRUE)) {
        cap <- "Subgroup analyses"
      }
      paste0("Figure 8", db_inf, ". ", cap, ".pdf")
    },
    fig7_subgroup_cox = paste0("Figure 7", db_inf, ". ", if (nzchar(cap)) cap else "Subgroup Forest (Cox)", ".pdf"),
    s1_fs = {
      if (grepl("Venn|Upset", cap, ignore.case = TRUE)) {
        paste0("Figure S1", db_inf, ". ", if (grepl("Upset", cap, ignore.case = TRUE)) "Upset" else "Venn", ".pdf")
      } else if (grepl("Lasso", cap, ignore.case = TRUE)) {
        paste0("Figure S1", db_inf, ". Lasso.pdf")
      } else {
        paste0("Figure S1", db_inf, ". ", if (nzchar(cap)) cap else "Feature selection", ".pdf")
      }
    },
    s2_comparator = paste0(
      "Figure S2", db_inf, ". ",
      if (nzchar(cap)) cap else "ROC comparison with clinical score",
      ".pdf"
    ),
    s3_landmark = paste0(
      "Figure S3", db_inf, ". ",
      if (nzchar(cap)) cap else "Landmark analysis",
      ".pdf"
    ),
    src_bn
  )
}

incidence_batch_ml_same_path <- function(a, b) {
  identical(
    tolower(gsub("\\\\", "/", as.character(a)[1L])),
    tolower(gsub("\\\\", "/", as.character(b)[1L]))
  )
}

incidence_batch_ml_safe_rename <- function(src, dest) {
  if (incidence_batch_ml_same_path(src, dest)) return(invisible(TRUE))
  if (file.exists(dest)) unlink(dest)
  ok <- file.rename(src, dest)
  if (isTRUE(ok)) return(invisible(TRUE))
  ok2 <- file.copy(src, dest, overwrite = TRUE)
  if (isTRUE(ok2)) {
    unlink(src)
    return(invisible(TRUE))
  }
  invisible(FALSE)
}

#' 把主库 LASSO S2A+S2B / S1 收到指标根 Figures，供定稿升为 Figure 2 或 S1
incidence_batch_ml_collect_fs_figure <- function(index_root, config = list()) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(FALSE))
  }
  agg <- file.path(index_root, "Figures")
  dir.create(agg, recursive = TRUE, showWarnings = FALSE)
  already <- list.files(
    agg,
    pattern = "(?i)(Figure S1.*Lasso|Feature selection LASSO)\\.pdf$",
    full.names = TRUE
  )
  already <- already[!grepl("/Figures/pdf/", already, ignore.case = TRUE)]
  s1_ok <- FALSE
  if (length(already) && requireNamespace("pdftools", quietly = TRUE)) {
    np <- tryCatch(pdftools::pdf_info(already[[1L]])$pages, error = function(e) NA_integer_)
    s1_ok <- is.finite(np) && identical(as.integer(np), 1L)
  }
  pri <- if (exists("dual_db_slot_path_name", mode = "function")) {
    tryCatch(dual_db_slot_path_name(config, "nhanes"), error = function(e) NA_character_)
  } else {
    NA_character_
  }
  search_roots <- unique(c(
    if (!is.na(pri) && nzchar(pri)) file.path(index_root, pri) else NA_character_,
    index_root
  ))
  search_roots <- search_roots[!is.na(search_roots) & dir.exists(search_roots)]
  find_one <- function(pat) {
    hits <- unlist(lapply(search_roots, function(rr) {
      list.files(rr, pattern = pat, recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    }), use.names = FALSE)
    hits <- hits[!grepl("/Figures/pdf/", hits, ignore.case = TRUE)]
    if (length(hits)) hits[[1L]] else NA_character_
  }
  # dev_ext（AF 金标准）：LASSO A/B 合成图直接当 Figure 2，不再另出重复的 Figure S1
  is_dev_ext <- identical(incidence_batch_pub_figure_scheme(config), "ml_dual_dev_ext")
  if (isTRUE(is_dev_ext)) {
    dup_s1 <- list.files(
      agg, pattern = "(?i)^Figure\\s*S1.*Lasso.*\\.pdf$",
      full.names = TRUE, ignore.case = TRUE
    )
    dup_s1 <- dup_s1[!grepl("/Figures/pdf/", dup_s1, ignore.case = TRUE)]
    if (length(dup_s1)) {
      unlink(dup_s1)
      cli::cli_alert_info("dev_ext: 已删除与 Figure 2 重复的 Figure S1 LASSO（{length(dup_s1)} 份）")
    }
  }
  dest <- if (isTRUE(is_dev_ext)) {
    file.path(agg, "Figure 2. Feature selection LASSO.pdf")
  } else {
    file.path(agg, "Figure S1. Lasso.pdf")
  }
  s2a <- find_one("(?i)Figure\\s*S2A.*LassoGenes.*\\.pdf$")
  s2b <- find_one("(?i)Figure\\s*S2B.*LassoModel.*\\.pdf$")
  if (isTRUE(s1_ok) && (is.na(s2a) || is.na(s2b))) {
    return(invisible(TRUE))
  }
  if (!is.na(s2a) && !is.na(s2b) && file.exists(s2a) && file.exists(s2b) &&
      exists("pub_figure_combine_ab_pdfs", mode = "function")) {
    ok <- isTRUE(tryCatch(
      pub_figure_combine_ab_pdfs(s2a, s2b, dest),
      error = function(e) FALSE
    ))
    if (isTRUE(ok) && file.exists(dest)) {
      cli::cli_alert_success("已上下拼接 LASSO A/B 矢量图（S2A+S2B）→ {basename(dest)}")
      return(invisible(TRUE))
    }
  }
  s1 <- find_one("(?i)Figure\\s*S1.*Lasso.*\\.pdf$")
  if (!is.na(s1) && file.exists(s1)) {
    file.copy(s1, dest, overwrite = TRUE)
    cli::cli_alert_success("已收集特征选择图 → {basename(dest)}")
    return(invisible(TRUE))
  }
  if (!is.na(s2a) && !is.na(s2b) && file.exists(s2a) && file.exists(s2b) &&
      requireNamespace("pdftools", quietly = TRUE)) {
    ok <- tryCatch({
      pdftools::pdf_combine(c(s2a, s2b), output = dest)
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok) && file.exists(dest)) {
      cli::cli_alert_warning("LASSO A|B 横排失败，回退多页拼接 → {basename(dest)}")
      return(invisible(TRUE))
    }
  }
  src <- if (!is.na(s2b) && file.exists(s2b)) s2b else if (!is.na(s2a) && file.exists(s2a)) s2a else NA_character_
  if (!is.na(src)) {
    file.copy(src, dest, overwrite = TRUE)
    cli::cli_alert_warning("特征选择图仅单张 {basename(src)} → {basename(dest)}")
    return(invisible(TRUE))
  }
  invisible(FALSE)
}

incidence_batch_curate_ml_pub_figures_dir <- function(figures_dir, cfg = list()) {
  if (!dir.exists(figures_dir)) return(invisible(0L))
  s1_files <- list.files(
    figures_dir, pattern = "Figure S1.*\\.pdf$",
    full.names = TRUE, ignore.case = TRUE
  )
  if (length(s1_files) > 1L) {
    lasso_s1 <- s1_files[grepl("Lasso", basename(s1_files), ignore.case = TRUE)]
    venn_s1 <- s1_files[grepl("Venn|Upset", basename(s1_files), ignore.case = TRUE)]
    if (length(lasso_s1) && length(venn_s1)) {
      unlink(venn_s1)
      cli::cli_alert_info(
        "Figure S1: 单方法特征选择，已删除韦恩/Upset 保留 LASSO（{length(lasso_s1)} 张）"
      )
    }
  }
  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  roles <- vapply(
    basename(files),
    function(bn) incidence_batch_ml_pub_figure_role(bn, cfg),
    character(1L)
  )
  keep_idx <- roles != "drop"
  n_purge <- sum(!keep_idx)
  if (n_purge > 0L) {
    unlink(files[!keep_idx])
    cli::cli_alert_info("ML 汇总图清理 {n_purge} 个非发表图: {.file {basename(figures_dir)}}")
  }
  files <- files[keep_idx]
  roles <- roles[keep_idx]
  if (!length(files)) return(invisible(n_purge))

  ## 有 KM 时：ML/SHAP/亚组顺延，避免多张图同叫 Figure 3
  ## 定稿序：Fig3=KM → Fig4=ML → Fig5=SHAP → Fig6=亚组
  if (any(roles == "fig3_km") && any(roles == "fig3_ml")) {
    roles[roles == "fig3_ml"] <- "fig4_ml"
    roles[roles == "fig4_shap"] <- "fig5_shap"
    roles[roles == "fig5_subgroup"] <- "fig6_subgroup"
    cli::cli_alert_info(
      "ML 图定稿: 已有 KM → ML/SHAP/亚组顺延为 Figure 4/5/6"
    )
  }

  ## 分类暴露无 RCS 时：特征选择图升为 Figure 2，避免定稿缺 Fig2、LASSO 只留在 step 里
  if (!any(roles %in% c("fig2_rcs", "fig2_fs")) && any(roles == "s1_fs")) {
    roles[roles == "s1_fs"] <- "fig2_fs"
    cli::cli_alert_info("ML 图定稿: 无 RCS，特征选择图升为 Figure 2")
  }

  ## 同 role+库 多份时保留体积最大（完整亚组森林优先于旧截断版）
  targets <- vapply(seq_along(files), function(i) {
    incidence_batch_ml_pub_figure_target_bn(roles[[i]], basename(files[[i]]), cfg)
  }, character(1L))
  keep_one <- rep(TRUE, length(files))
  for (tg in unique(targets)) {
    ii <- which(targets == tg)
    if (length(ii) <= 1L) next
    sz <- file.info(files[ii])$size
    sz[!is.finite(sz)] <- 0
    win <- ii[which.max(sz)]
    drop_i <- setdiff(ii, win)
    keep_one[drop_i] <- FALSE
    unlink(files[drop_i])
    cli::cli_alert_info(
      "ML 图定稿: 同目标 {tg} 保留最大文件（{basename(files[win])}），丢弃 {length(drop_i)} 份"
    )
  }
  files <- files[keep_one]
  roles <- roles[keep_one]
  if (!length(files)) return(invisible(n_purge))

  for (i in seq_along(files)) {
    tgt <- file.path(
      figures_dir,
      incidence_batch_ml_pub_figure_target_bn(roles[[i]], basename(files[[i]]), cfg)
    )
    incidence_batch_ml_safe_rename(files[[i]], tgt)
  }

  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  all_bn <- basename(files)
  ord <- order(vapply(all_bn, function(bn) {
    r <- incidence_batch_ml_pub_figure_role(bn, cfg)
    ## 与上方顺延一致：文件名已是 Figure 4 ML / Figure 5 SHAP / Figure 6 亚组
    if (identical(r, "fig3_ml") && any(grepl("Kaplan", all_bn, ignore.case = TRUE))) {
      r <- "fig4_ml"
    }
    if (identical(r, "fig4_shap") && any(grepl("Kaplan", all_bn, ignore.case = TRUE)) &&
        any(grepl("ML performance combined", all_bn, ignore.case = TRUE))) {
      r <- "fig5_shap"
    }
    if (identical(r, "fig5_subgroup") && any(grepl("Kaplan", all_bn, ignore.case = TRUE))) {
      r <- "fig6_subgroup"
    }
    db <- incidence_batch_ml_extract_db_tag(bn, cfg)
    db_tags <- if (exists(".ml_ptc_db_tags", mode = "function")) {
      .ml_ptc_db_tags(cfg)
    } else {
      c(
        if (exists("dual_db_slot_path_name", mode = "function")) dual_db_slot_path_name(cfg, "nhanes") else "NHANES",
        if (exists("dual_db_slot_path_name", mode = "function")) dual_db_slot_path_name(cfg, "mimic") else "MIMIC"
      )
    }
    db_ord <- if (!is.na(db) && nzchar(db)) match(tolower(db), tolower(db_tags)) else 0L
    if (is.na(db_ord)) db_ord <- 99L
    base <- c(
      fig1 = 10L, fig2_rcs = 20L, fig2_fs = 21L, fig3_cor = 25L, fig3_km = 28L,
      fig3_ml = 30L, fig3_ml_roc3 = 30L, fig4_ml_cal3 = 31L, fig5_ml_met3 = 32L,
      fig6_ml_dca3 = 33L,
      fig4_ml = 34L, fig4_shap = 40L, fig5_shap = 42L, fig5_subgroup = 50L,
      fig6_subgroup = 52L, fig7_shap = 54L, fig8_subgroup = 56L,
      fig7_subgroup_cox = 58L, s1_fs = 60L,
      s2_comparator = 61L, s3_landmark = 62L
    )[r] %||% 999L
    base + db_ord * 0.01
  }, numeric(1L)), all_bn)
  if (length(ord) > 1L) {
    tmp <- character(length(files))
    for (i in seq_along(files)) {
      tmp[i] <- file.path(figures_dir, sprintf(".ml_curate_%03d.pdf", i))
      if (file.exists(tmp[i])) unlink(tmp[i])
      file.rename(files[ord][[i]], tmp[i])
    }
    for (i in seq_along(tmp)) file.rename(tmp[i], files[ord][[i]])
  }
  invisible(n_purge)
}

incidence_batch_curate_purge_enabled <- function(config) {
  bc <- config$incidence_batch %||% config$ml_batch %||% list()
  isTRUE(bc$curate_purge_pub_figures %||% FALSE)
}

incidence_batch_ensure_figure1_placeholder <- function(figures_dir) {
  if (is.null(figures_dir) || !nzchar(figures_dir)) return(invisible(FALSE))
  dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(figures_dir, "Figure 1. Flowchart.pdf")
  if (exists("attrition_promote_figure1", mode = "function") &&
      isTRUE(attrition_promote_figure1(figures_dir)) && file.exists(dest) &&
      !incidence_batch_is_figure1_placeholder(dest)) {
    return(invisible(FALSE))
  }
  # 已有非占位真实 Figure 1：勿覆盖
  if (file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
    return(invisible(FALSE))
  }
  # 不再写 “flowchart to be added” 空图作为发表终稿；留给 ensure_real_figure1
  invisible(FALSE)
}

#' 判断 Figure 1 是否为占位空图
incidence_batch_is_figure1_placeholder <- function(path) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) return(TRUE)
  sz <- suppressWarnings(as.numeric(file.info(path)$size))
  if (!is.finite(sz) || sz < 1500) return(TRUE)
  txt <- ""
  # 路径含中文时 pdftotext 可能失败：拷到临时 ASCII 路径再读
  if (nzchar(Sys.which("pdftotext"))) {
    tmp <- tempfile(fileext = ".pdf")
    ok_cp <- tryCatch(file.copy(path, tmp, overwrite = TRUE), error = function(e) FALSE)
    if (isTRUE(ok_cp)) {
      txt <- paste(tryCatch(
        system2("pdftotext", c("-layout", tmp, "-"), stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      ), collapse = " ")
    }
    unlink(tmp)
  }
  if (!nzchar(txt)) {
    raw <- tryCatch(readBin(path, "raw", n = min(as.integer(sz), 50000L)), error = function(e) raw(0))
    if (length(raw)) {
      txt <- paste(rawToChar(raw[raw >= 32 & raw < 127], multiple = TRUE), collapse = "")
    }
  }
  if (grepl("placeholder|flowchart to be added", txt, ignore.case = TRUE)) return(TRUE)
  # 经典占位 PDF ~4KB；真实双栏纳排通常更大且含 N=
  if (sz < 6000L && !grepl("N\\s*=", txt, ignore.case = TRUE)) return(TRUE)
  FALSE
}

#' 从 _batch_status.json 组装 survival filter_stats
incidence_batch_filter_stats_from_status <- function(index_root) {
  st_path <- file.path(index_root, "_batch_status.json")
  if (!file.exists(st_path) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  st <- tryCatch(jsonlite::fromJSON(st_path), error = function(e) NULL)
  if (is.null(st)) return(list())
  list(
    nhanes = list(imputed = list(
      n_before = st$n_nhanes_before %||% NA,
      n_after  = st$n_nhanes_after %||% NA,
      n_na     = st$n_nhanes_na %||% NA,
      n_trim   = st$n_nhanes_trim %||% NA
    )),
    mimic = list(imputed = list(
      n_before = st$n_mimic_before %||% NA,
      n_after  = st$n_mimic_after %||% NA,
      n_na     = st$n_mimic_na %||% NA,
      n_trim   = st$n_mimic_trim %||% NA
    ))
  )
}

#' 从指标根 _batch_status.json 读取各库最终 N（供 image_information meta）
#' 无 status 文件或字段缺失时返回空 list；调用方 meta$n_by_db 仍为可选，常显示「未记录」。
incidence_batch_pub_figure_meta_n <- function(index_root, config, db_seq) {
  st_path <- file.path(index_root, "_batch_status.json")
  if (!file.exists(st_path) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(list())
  }
  st <- tryCatch(jsonlite::fromJSON(st_path), error = function(e) NULL)
  if (is.null(st)) return(list())

  slot_n <- function(slot) {
    norm <- if (exists("dual_db_normalize_slot", mode = "function")) {
      dual_db_normalize_slot(slot)
    } else {
      tolower(as.character(slot)[1L])
    }
    key <- switch(
      norm,
      nhanes = "n_nhanes_after",
      mimic = "n_mimic_after",
      NA_character_
    )
    if (is.na(key)) return(NA_integer_)
    raw <- st[[key]]
    if (is.null(raw) || length(raw) < 1L) return(NA_integer_)
    n <- suppressWarnings(as.integer(raw))[1L]
    if (length(n) < 1L || is.na(n) || !is.finite(n)) return(NA_integer_)
    n
  }

  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq)) return(list())

  checkpoint_n <- function(db) {
    bc <- config$ml_batch %||% config$incidence_batch %||% list()
    ck_base <- as.character(bc$index_ck_base %||% "")[1L]
    if (!nzchar(ck_base)) return(NA_integer_)
    ix <- sub("^【[^】]+】", "", basename(index_root))
    db_dir <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(config, db)
    } else {
      as.character(db)[1L]
    }
    fp <- file.path(ck_base, ix, db_dir, "imputation.rds")
    if (!file.exists(fp)) return(NA_integer_)
    obj <- tryCatch(readRDS(fp), error = function(e) NULL)
    dat <- obj$ctx$data$imputed %||% obj$ctx$data$cleaned %||% NULL
    if (!is.data.frame(dat)) return(NA_integer_)
    as.integer(nrow(dat))
  }

  n_by_db <- integer(0)
  for (db in db_seq) {
    n <- slot_n(db)
    if (is.na(n)) n <- checkpoint_n(db)
    if (is.na(n)) next
    lbl <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(config, db)
    } else {
      as.character(db)[1L]
    }
    n_by_db[[lbl]] <- n
  }
  if (!length(n_by_db)) return(list())

  list(
    n_by_db = n_by_db,
    n_total = sum(as.integer(n_by_db), na.rm = TRUE)
  )
}

#' 从各库 step*/Tables/Flowchart_attrition*.csv 拼双栏 Figure 1（发病/ML 双库）
#'
#' 根因修复：mirror 常把单库 Figure 1. Flowchart.pdf 拷进汇总，旧逻辑见「非占位」就提前
#' 返回，导致双库 ML 发病终稿只剩 NHANES/CHARLS 单栏。双库（length(db_seq)>=2）必须
#' 优先用分库纳排 CSV 强制覆盖为左右拼图。
incidence_batch_write_dual_flowchart_from_db_attrition <- function(
    index_root, config, db_seq, ix = NULL, font_family = "Times New Roman"
) {
  if (is.null(index_root) || !dir.exists(index_root)) return(invisible(FALSE))
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (length(db_seq) < 2L) return(invisible(FALSE))

  fig_dir <- file.path(index_root, "Figures")
  tab_dir <- file.path(index_root, "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(fig_dir, "Figure 1. Flowchart.pdf")
  ix <- as.character(ix %||% basename(index_root))[1L]
  ix <- sub("^【[^】]+】", "", ix)
  font_family <- as.character(font_family %||% "Times New Roman")[1L]

  all_rows <- list()
  for (db in db_seq) {
    db_disp <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) NA_character_)
    } else {
      NA_character_
    }
    if (is.na(db_disp) || !nzchar(db_disp)) db_disp <- as.character(db)[1L]
    db_root <- file.path(index_root, db_disp)
    if (!dir.exists(db_root)) next

    csvs <- list.files(
      db_root,
      pattern = "^Flowchart_attrition.*\\.csv$",
      full.names = TRUE,
      recursive = TRUE,
      ignore.case = TRUE
    )
    # 优先 step*_attrition_flowchart/Tables，避免误收其它副本
    prefer <- csvs[grepl("attrition_flowchart", csvs, ignore.case = TRUE)]
    if (length(prefer)) csvs <- prefer
    if (!length(csvs)) next
    csv <- csvs[[which.max(file.info(csvs)$mtime)]]
    dt <- tryCatch(utils::read.csv(csv, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.null(dt) || !nrow(dt) || !all(c("step", "n") %in% names(dt))) next
    rows <- dt
    rows$step <- as.character(rows$step)
    rows$n <- suppressWarnings(as.integer(rows$n))
    rows$database <- db_disp
    rows <- rows[is.finite(rows$n), , drop = FALSE]
    if (!nrow(rows)) next
    all_rows[[db_disp]] <- rows
  }
  if (length(all_rows) < 2L) return(invisible(FALSE))

  want_cols <- c(
    "step", "n", "database", "exclude_label",
    "fork_left_label", "fork_left_n", "fork_right_label", "fork_right_n"
  )
  comb <- do.call(rbind, lapply(all_rows, function(x) {
    for (nm in want_cols) {
      if (!nm %in% names(x)) x[[nm]] <- NA
    }
    x[, want_cols, drop = FALSE]
  }))
  # 汇总 Tables 只留带 database 列的 dual CSV，避免无库名片被收成「未知库」
  stale_attr <- list.files(
    tab_dir,
    pattern = "^Flowchart_attrition.*\\.csv$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  if (length(stale_attr)) unlink(stale_attr)
  utils::write.csv(
    comb,
    file.path(tab_dir, sprintf("Flowchart_attrition_%s_dual.csv", ix)),
    row.names = FALSE
  )

  # 标题只用库名（对齐 12_AKI/AF）：勿把指标名（如 sdLDL_C）当「文件名」写进纳排图
  titles <- as.character(names(all_rows))
  # NHANES 侧从权重 Exclude 标签重建脚注（标明权重名与剔除人数）
  footnotes_by_db <- lapply(all_rows, function(rows) {
    if (is.null(rows) || !nrow(rows)) return(character(0))
    el <- if ("exclude_label" %in% names(rows)) {
      as.character(rows$exclude_label)
    } else {
      character(0)
    }
    hit <- which(grepl("survey weight", el, ignore.case = TRUE))
    if (!length(hit)) {
      hit <- which(grepl("Eligible survey-weighted", as.character(rows$step), ignore.case = TRUE))
    }
    if (!length(hit)) return(character(0))
    i <- hit[[1L]]
    lab <- if (length(el) >= i && nzchar(el[[i]] %||% "")) el[[i]] else "survey weights"
    n_prev <- if (i > 1L) suppressWarnings(as.integer(rows$n[i - 1L])[1L]) else NA_integer_
    n_cur <- suppressWarnings(as.integer(rows$n[i])[1L])
    n_drop <- if (is.finite(n_prev) && is.finite(n_cur)) max(0L, n_prev - n_cur) else 0L
    c(
      paste0("Survey weights: ", lab),
      sprintf(
        "%s participant(s) were excluded due to missing or non-positive survey weights.",
        format(n_drop, big.mark = ",")
      )
    )
  })
  ok_draw <- FALSE
  if (exists("attrition_draw_dual_panel_pdf", mode = "function")) {
    ok_draw <- isTRUE(tryCatch(
      attrition_draw_dual_panel_pdf(
        all_rows, dest, titles = titles, font_family = font_family,
        footnotes_by_db = footnotes_by_db
      ),
      error = function(e) FALSE
    ))
  }
  if (!isTRUE(ok_draw) || !file.exists(dest)) {
    cli::cli_alert_warning("Figure 1 双库 CONSORT 拼图失败")
    return(invisible(FALSE))
  }
  # 汇总目录不留分库 Figure 1 单图
  stale <- list.files(
    fig_dir,
    pattern = "^Figure 1-.+\\. Inclusion exclusion flowchart\\.pdf$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  if (length(stale)) unlink(stale)
  ok <- file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)
  if (isTRUE(ok)) {
    cli::cli_alert_success(
      "Figure 1 双库纳排已由分库 attrition CSV 重建（{paste(names(all_rows), collapse = ' + ')}）"
    )
  }
  invisible(isTRUE(ok))
}

#' 课题根 / 指标根：尽量写出真实 Figure 1（双库纳排），禁止占位空图终稿
incidence_batch_ensure_real_figure1 <- function(index_root, config, ix = NULL,
                                                 db_seq = c("nhanes", "mimic"),
                                                 project_root = NULL) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(FALSE))
  }
  fig_dir <- file.path(index_root, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(fig_dir, "Figure 1. Flowchart.pdf")
  bc <- config$incidence_batch %||% config$ml_batch %||% config$survival_batch %||% list()
  project_root <- as.character(
    project_root %||% bc$output_base %||% config$project$output_dir %||% dirname(dirname(index_root))
  )[1L]
  ix <- as.character(ix %||% basename(index_root))[1L]
  ix <- sub("^【[^】]+】", "", ix)
  font_family <- (config$plot %||% list())$font_family %||% "Times New Roman"
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))

  # 1) 预后指标目录（by_index/...）：用纳排 CSV + 指标缺失人数画双库图
  #    禁止把课题根当 index_root 调用（会误建 eICU/MIMIC 子目录）
  is_index_dir <- grepl("(^|/)by_index(/|$)", normalizePath(index_root, winslash = "/", mustWork = FALSE))
  if (is_index_dir && incidence_batch_is_prognosis_config(config) &&
      exists("survival_batch_write_index_flowcharts", mode = "function")) {
    tryCatch(
      survival_batch_write_index_flowcharts(
        project_root = project_root,
        index_root   = index_root,
        ix           = ix,
        filter_stats = incidence_batch_filter_stats_from_status(index_root),
        db_seq       = db_seq,
        font_family  = font_family,
        config       = config
      ),
      error = function(e) {
        cli::cli_alert_warning("ensure_real_figure1 预后绘图失败: {e$message}")
      }
    )
    if (file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
      return(invisible(TRUE))
    }
  }

  # 1b) 发病 / ML 双库：分库 attrition CSV → 强制双栏 Figure 1（覆盖单库 mirror）
  if (is_index_dir && length(db_seq) >= 2L &&
      !incidence_batch_is_prognosis_config(config)) {
    ok_dual <- tryCatch(
      incidence_batch_write_dual_flowchart_from_db_attrition(
        index_root = index_root,
        config = config,
        db_seq = db_seq,
        ix = ix,
        font_family = font_family
      ),
      error = function(e) {
        cli::cli_alert_warning("ensure_real_figure1 发病双库纳排失败: {e$message}")
        FALSE
      }
    )
    if (isTRUE(ok_dual)) return(invisible(TRUE))
  }

  # 2) 提升本目录已有 Inclusion exclusion / Dual 纳排 PDF
  #    双库时不得因「已有单库 Figure 1」提前返回（上面 1b 失败才落到此处兜底）
  if (exists("attrition_promote_figure1", mode = "function")) {
    attrition_promote_figure1(fig_dir)
  }
  dual_cands <- list.files(
    fig_dir,
    pattern = "(?i)Figure 1.*Dual.*Inclusion|Figure 1-Dual",
    full.names = TRUE
  )
  if (length(dual_cands) && (incidence_batch_is_figure1_placeholder(dest) || !file.exists(dest))) {
    file.copy(dual_cands[[which.max(file.info(dual_cands)$size)]], dest, overwrite = TRUE)
  }
  # 单库课题：已有真实 Fig1 即可返回；双库仍继续尝试课题根 / dual CSV
  if (length(db_seq) < 2L &&
      file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
    return(invisible(TRUE))
  }
  if (length(db_seq) >= 2L &&
      file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
    # 若当前 Fig1 文本只含一个库名单，继续尝试重建；含两库名则接受
    txt <- ""
    if (nzchar(Sys.which("pdftotext"))) {
      tmp <- tempfile(fileext = ".pdf")
      if (isTRUE(tryCatch(file.copy(dest, tmp, overwrite = TRUE), error = function(e) FALSE))) {
        txt <- paste(tryCatch(
          system2("pdftotext", c("-layout", tmp, "-"), stdout = TRUE, stderr = FALSE),
          error = function(e) character(0)
        ), collapse = " ")
      }
      unlink(tmp)
    }
    db_labels <- vapply(db_seq, function(db) {
      if (exists("dual_db_slot_path_name", mode = "function")) {
        tryCatch(dual_db_slot_path_name(config, db), error = function(e) as.character(db)[1L])
      } else {
        as.character(db)[1L]
      }
    }, character(1L))
    n_hit <- sum(vapply(db_labels, function(lb) {
      grepl(lb, txt, ignore.case = TRUE)
    }, logical(1L)))
    if (n_hit >= 2L) return(invisible(TRUE))
  }

  # 3) 从课题根拷贝真实 Figure 1 / Dual
  if (nzchar(project_root) && dir.exists(file.path(project_root, "Figures"))) {
    proj_figs <- file.path(project_root, "Figures")
    for (bn in c(
      "Figure 1. Flowchart.pdf",
      "Figure 1-Dual. Inclusion exclusion flowchart.pdf"
    )) {
      src <- file.path(proj_figs, bn)
      if (file.exists(src) && !incidence_batch_is_figure1_placeholder(src)) {
        file.copy(src, dest, overwrite = TRUE)
        if (file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
          cli::cli_alert_success("Figure 1 已从课题根复制: {.file {bn}}")
          return(invisible(TRUE))
        }
      }
    }
  }

  # 4) 用课题 Tables/Flowchart_attrition_dual.csv 画双栏（无指标缺失框）
  csv <- file.path(project_root, "Tables", "Flowchart_attrition_dual.csv")
  if (file.exists(csv) && exists("attrition_draw_pdf", mode = "function")) {
    dt <- tryCatch(utils::read.csv(csv, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(dt) && nrow(dt) && "database" %in% names(dt)) {
      dbs <- unique(as.character(dt$database))
      if (length(dbs) >= 1L) {
        ok <- tryCatch({
          rows_by_db <- lapply(dbs, function(db) {
            dt[tolower(dt$database) == tolower(db), , drop = FALSE]
          })
          names(rows_by_db) <- dbs
          rows_by_db <- rows_by_db[vapply(rows_by_db, nrow, integer(1)) > 0L]
          if (!length(rows_by_db)) {
            FALSE
          } else if (exists("attrition_draw_dual_panel_pdf", mode = "function") &&
                     length(rows_by_db) >= 2L) {
            isTRUE(attrition_draw_dual_panel_pdf(
              rows_by_db, dest, titles = names(rows_by_db), font_family = font_family
            ))
          } else if (length(rows_by_db) >= 1L) {
            isTRUE(attrition_draw_pdf(
              rows_by_db[[1L]], names(rows_by_db)[[1L]], dest, font_family = font_family
            ))
          } else {
            FALSE
          }
        }, error = function(e) {
          cli::cli_alert_warning("从 Flowchart_attrition_dual.csv 绘图失败: {e$message}")
          FALSE
        })
        if (isTRUE(ok) && file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest)) {
          cli::cli_alert_success("Figure 1 已由纳排 CSV 重建")
          return(invisible(TRUE))
        }
      }
    }
  }

  if (file.exists(dest) && incidence_batch_is_figure1_placeholder(dest)) {
    unlink(dest)
    cli::cli_alert_warning(
      "已删除 Figure 1 占位空图（未找到可用纳排数据）。请先跑课题 prepare_cohort / attrition，或保证 _batch_status.json 有人数。"
    )
  } else if (!file.exists(dest)) {
    cli::cli_alert_warning("未能写出真实 Figure 1 纳排图: {.file {fig_dir}}")
  }
  invisible(file.exists(dest) && !incidence_batch_is_figure1_placeholder(dest))
}

incidence_batch_is_prognosis_config <- function(config) {
  if (is.null(config) || !is.list(config)) return(FALSE)
  kind <- tolower(as.character(
    config$project$study_type %||% config$project$kind %||% config$project$type %||% ""
  )[1L])
  if (identical(kind, "incidence")) return(FALSE)
  if (identical(kind, "prognosis") || identical(kind, "survival")) return(TRUE)
  if (!is.null(config$survival_batch)) return(TRUE)
  if (!is.null(config$survival) && is.null(config$incidence_batch)) return(TRUE)
  FALSE
}

incidence_batch_prognosis_figure_role <- function(bn) {
  bn <- as.character(bn)[1L]
  if (grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)) return("drop")
  # 已停产 maxstat Cutoff 图：遗留文件去重时直接丢弃
  if (grepl("Cutoff Point|maxstat", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Flowchart|Inclusion exclusion", bn, ignore.case = TRUE)) return("fig1")
  if (grepl("RCS Analysis|RCS of|RCS plot|\\bRCS\\b|Restricted Cubic", bn, ignore.case = TRUE)) {
    return("fig2_rcs")
  }
  if (grepl("ROC comparison of joint indices", bn, ignore.case = TRUE)) {
    return("s2_comparator")
  }
  if (grepl("landmark analysis", bn, ignore.case = TRUE)) return("s3_landmark")
  if (grepl("Kaplan", bn, ignore.case = TRUE) &&
      grepl("joint", bn, ignore.case = TRUE)) return("fig2_joint_km")
  if (grepl("Kaplan", bn, ignore.case = TRUE)) return("fig3_km")
  if (grepl("Subgroup Forest", bn, ignore.case = TRUE)) return("fig4_subgroup")
  if (grepl("Boxplot", bn, ignore.case = TRUE)) return("s1_boxplot")
  if (grepl("Mediation|mediator|path diagram", bn, ignore.case = TRUE)) return("s2_mediation")
  if (grepl("\\bROC\\b", bn, ignore.case = TRUE)) return("s3_roc")
  "other"
}

incidence_batch_prognosis_figure_target_bn <- function(role, src_bn, db = NA_character_) {
  db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
  cap <- sub("^Figure (?:S)?[0-9]+(?:-[A-Za-z0-9_]+)?\\. ", "", src_bn, perl = TRUE)
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  switch(role,
    fig1 = sprintf("Figure 1%s. %s.pdf", db_sfx, cap),
    fig2_rcs = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig2_joint_km = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig3_km = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    fig4_subgroup = sprintf("Figure 4%s. %s.pdf", db_sfx, cap),
    s1_boxplot = sprintf("Figure S1%s. %s.pdf", db_sfx, cap),
    s2_mediation = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    s2_comparator = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    s3_landmark = sprintf("Figure S3%s. %s.pdf", db_sfx, cap),
    s3_roc = sprintf("Figure S3%s. %s.pdf", db_sfx, cap),
    NULL
  )
}

incidence_batch_incidence_figure_role <- function(bn) {
  bn <- as.character(bn)[1L]
  if (grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Cutoff Point|maxstat", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Flowchart|Inclusion exclusion", bn, ignore.case = TRUE)) return("fig1")
  if (grepl("RCS Analysis|RCS of|RCS plot|\\bRCS\\b|Restricted Cubic|Weighted RCS", bn, ignore.case = TRUE)) {
    return("fig2_rcs")
  }
  if (grepl("Subgroup", bn, ignore.case = TRUE)) return("fig3_subgroup")
  if (grepl("Boxplot", bn, ignore.case = TRUE)) return("s1_boxplot")
  if (grepl("Mediation|mediator|path diagram", bn, ignore.case = TRUE)) return("s2_mediation")
  if (grepl("\\bROC\\b", bn, ignore.case = TRUE)) return("s3_roc")
  "other"
}

incidence_batch_incidence_figure_target_bn <- function(role, src_bn, db = NA_character_) {
  db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
  cap <- as.character(src_bn)[1L]
  if (exists("incidence_batch_ml_pub_figure_clean_cap", mode = "function")) {
    cap <- incidence_batch_ml_pub_figure_clean_cap(cap)
  } else {
    cap <- sub("^Figure (?:S)?[0-9]+(?:-[A-Za-z0-9_]+)?\\. ", "", cap, perl = TRUE)
    cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  }
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  switch(role,
    fig1 = sprintf("Figure 1%s. %s.pdf", db_sfx, cap),
    fig2_rcs = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig3_subgroup = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    s1_boxplot = sprintf("Figure S1%s. %s.pdf", db_sfx, cap),
    s2_mediation = sprintf("Figure S3%s. %s.pdf", db_sfx, cap),
    s3_roc = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    NULL
  )
}

incidence_batch_dedupe_pub_figures_by_role <- function(
    figures_dir,
    config = NULL,
    role_fn = incidence_batch_prognosis_figure_role,
    target_fn = incidence_batch_prognosis_figure_target_bn
) {
  if (!dir.exists(figures_dir)) return(invisible(0L))
  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  db_names <- character(0)
  if (!is.null(config) && exists("dual_db_slot_path_name", mode = "function")) {
    db_names <- unique(c(
      dual_db_slot_path_name(config, "nhanes"),
      dual_db_slot_path_name(config, "mimic")
    ))
  }
  db_names <- unique(c(db_names, "eICU", "MIMIC", "NHANES"))
  fi <- file.info(files)
  files <- files[order(fi$mtime, decreasing = TRUE, na.last = TRUE)]
  keep <- list()
  n_drop <- 0L
  for (f in files) {
    bn <- basename(f)
    role <- role_fn(bn)
    if (identical(role, "drop")) {
      if (file.exists(f) && !isTRUE(file.remove(f))) unlink(f, force = TRUE)
      if (!file.exists(f)) n_drop <- n_drop + 1L
      next
    }
    if (identical(role, "other")) next
    db <- NA_character_
    for (d in db_names) {
      if (grepl(paste0("-", d, "\\."), bn, fixed = FALSE)) {
        db <- d
        break
      }
    }
    db_key <- if (is.na(db) || !nzchar(db)) "" else db
    key <- paste(role, db_key, sep = "\x01")
    if (key %in% names(keep)) {
      if (file.exists(f) && !isTRUE(file.remove(f))) unlink(f, force = TRUE)
      if (!file.exists(f)) n_drop <- n_drop + 1L
      next
    }
    keep[[key]] <- f
  }
  n_ren <- 0L
  for (key in names(keep)) {
    parts <- strsplit(key, "\x01", fixed = TRUE)[[1L]]
    role <- parts[[1L]]
    db <- if (length(parts) >= 2L && nzchar(parts[[2L]]) && !identical(parts[[2L]], "NA")) {
      parts[[2L]]
    } else {
      NA_character_
    }
    src <- keep[[key]]
    tgt_bn <- target_fn(role, basename(src), db)
    if (is.null(tgt_bn)) next
    tgt <- file.path(figures_dir, tgt_bn)
    if (!identical(normalizePath(src, winslash = "/", mustWork = FALSE),
                   normalizePath(tgt, winslash = "/", mustWork = FALSE))) {
      if (file.exists(tgt)) unlink(tgt)
      ok <- file.rename(src, tgt)
      if (!isTRUE(ok)) file.copy(src, tgt, overwrite = TRUE)
      if (!identical(src, tgt) && file.exists(src)) unlink(src)
      n_ren <- n_ren + 1L
    }
  }
  if (n_drop > 0L || n_ren > 0L) {
    cli::cli_alert_info(
      "发表图按角色去重: 删 {n_drop}，重命名 {n_ren}: {.file {basename(figures_dir)}}"
    )
  }
  invisible(n_drop)
}

incidence_batch_dedupe_prognosis_figures_dir <- function(figures_dir, config = NULL) {
  incidence_batch_dedupe_pub_figures_by_role(
    figures_dir, config,
    role_fn = incidence_batch_prognosis_figure_role,
    target_fn = incidence_batch_prognosis_figure_target_bn
  )
}

incidence_batch_dedupe_incidence_figures_dir <- function(figures_dir, config = NULL) {
  incidence_batch_dedupe_pub_figures_by_role(
    figures_dir, config,
    role_fn = incidence_batch_incidence_figure_role,
    target_fn = incidence_batch_incidence_figure_target_bn
  )
}

incidence_batch_curate_pub_figures_dir <- function(figures_dir, purge = FALSE, config = NULL) {
  if (!dir.exists(figures_dir)) return(invisible(0L))
  scheme <- if (!is.null(config)) incidence_batch_pub_figure_scheme(config) else "default"
  ## ml_dual_standard：默认 ML 定稿序；ml_with_correlation：仅课题开启时纳入相关热图为 Fig3
  if (scheme %in% c("ml_dual_standard", "ml_dual_dev_ext", "ml_with_correlation")) {
    return(incidence_batch_curate_ml_pub_figures_dir(figures_dir, cfg = config %||% list()))
  }
  if (incidence_batch_is_prognosis_config(config)) {
    incidence_batch_dedupe_prognosis_figures_dir(figures_dir, config)
  } else if (identical(tolower(as.character(config$project$study_type %||% "")[1L]), "incidence")) {
    incidence_batch_dedupe_incidence_figures_dir(figures_dir, config)
  }
  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  all_bn <- basename(files)
  n_purge <- 0L
  if (isTRUE(purge)) {
    purge_idx <- vapply(all_bn, function(bn) {
      incidence_batch_should_purge_pub_figure(bn, all_bn)
    }, logical(1L))
    n_purge <- sum(purge_idx)
    if (n_purge > 0L) {
      unlink(files[purge_idx])
      cli::cli_alert_info("已清理冗余发表图 {n_purge} 个: {.file {basename(figures_dir)}}")
      files <- files[!purge_idx]
      all_bn <- basename(files)
    }
  }
  if (length(files) <= 1L) return(invisible(n_purge))
  ord <- order(vapply(all_bn, incidence_batch_pub_figure_sort_key, numeric(1L)), all_bn)
  files <- files[ord]
  tmp <- character(length(files))
  for (i in seq_along(files)) {
    tmp[i] <- file.path(figures_dir, sprintf(".curate_tmp_%03d.pdf", i))
    if (file.exists(tmp[i])) unlink(tmp[i])
    file.rename(files[i], tmp[i])
  }
  for (i in seq_along(tmp)) {
    file.rename(tmp[i], files[i])
  }
  invisible(n_purge)
}

incidence_batch_curate_index_pub_outputs <- function(index_root, config, db_seq = character(0)) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(NULL))
  }
  if (incidence_batch_is_ml_dual_pub_scheme(config)) {
    if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
      source(file.path(getwd(), "R", "ml_dual_pub_table_curate.R"), local = FALSE)
    }
    tryCatch(
      incidence_batch_ml_collect_fs_figure(index_root, config),
      error = function(e) cli::cli_alert_warning("收集特征选择图跳过: {e$message}")
    )
  }
  purge <- incidence_batch_curate_purge_enabled(config)
  dirs <- c(file.path(index_root, "Figures"))
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  for (db in db_seq) {
    db_dir <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(config, db)
    } else {
      db
    }
    dirs <- c(dirs, file.path(index_root, db_dir, "Figures"))
  }
  n <- 0L
  for (d in unique(dirs)) {
    n <- n + (incidence_batch_curate_pub_figures_dir(d, purge = purge, config = config) %||% 0L)
  }
  light <- isTRUE((config$incidence_batch %||% list())$.sensitivity_light) ||
    isTRUE((config$survival_batch %||% list())$.sensitivity_light)
  if (!light) {
    # 强制真实纳排图；不再写 placeholder 空图
    ix_guess <- sub("^【[^】]+】", "", basename(index_root))
    incidence_batch_ensure_real_figure1(
      index_root = index_root,
      config = config,
      ix = ix_guess,
      db_seq = db_seq
    )
  }
  if (incidence_batch_is_ml_dual_pub_scheme(config)) {
    cli::cli_alert_success("指标汇总图已整理（Fig2 RCS / Fig3 ML / Fig4 SHAP / Fig5 亚组 / FigS1 韦恩）")
  } else if (identical(incidence_batch_pub_figure_scheme(config), "ml_with_correlation")) {
    cli::cli_alert_success("指标汇总图已整理（Fig2 RCS / Fig3 相关热图 / Fig4 ML / Fig5 SHAP / Fig6 亚组）")
  } else if (isTRUE(purge) && n > 0L) {
    cli::cli_alert_success("指标汇总图已整理（保留拼图/韦恩，移除 S2A–G 与 SHAP/ML 单图）: {n} 个")
  } else if (!isTRUE(purge)) {
    cli::cli_alert_success("指标汇总图已排序（保留 Output_旋旋 全套，未删除 S2/SHAP/ML 单图）")
  }
  invisible(n)
}

#' 单库/非聚合：把 db 槽发表 Tables 汇总到指标根 Tables（发表 xlsx；同名取 mtime 最新）
#' 与 mirror_dual_db_aggregate 同口径：不收 .tex/.csv/ROC/Analysis_exclusion
incidence_batch_ensure_index_root_tables <- function(index_root, config, db_seq) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(FALSE))
  }
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq)) return(invisible(FALSE))
  root_tables <- file.path(index_root, "Tables")
  dir.create(root_tables, recursive = TRUE, showWarnings = FALSE)
  n <- 0L
  for (db in db_seq) {
    slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) as.character(db)[1L])
    } else {
      as.character(db)[1L]
    }
    src <- file.path(index_root, slot, "Tables")
    if (!dir.exists(src)) next
    files <- list.files(src, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
    files <- files[!grepl("ROC", basename(files), ignore.case = TRUE)]
    files <- files[!grepl("^Analysis_exclusion_", basename(files), ignore.case = TRUE)]
    for (f in files) {
      dp <- file.path(root_tables, basename(f))
      if (file.exists(dp) && file.info(dp)$mtime >= file.info(f)$mtime) next
      if (file.copy(f, dp, overwrite = TRUE)) n <- n + 1L
    }
  }
  # 根 Tables 不留 .tex/.csv（与聚合批同口径）
  for (pat in c("\\.tex$", "\\.csv$")) {
    stale <- list.files(root_tables, pattern = pat, full.names = TRUE, ignore.case = TRUE)
    if (length(stale)) unlink(stale)
  }
  if (n > 0L) {
    cli::cli_alert_success("指标根 Tables 已汇总 {n} 张发表表（单库/非聚合）")
  }
  invisible(TRUE)
}

#' 指标根 Figures 强制四目录（pdf/png/tiff + image_information）
#' 单库 mirror_aggregate=FALSE / 续跑漏网时也会调用，避免只剩平铺 PDF。
incidence_batch_ensure_index_pub_figure_formats <- function(index_root, config, db_seq,
                                                           meta = NULL) {
  if (!exists("export_pub_figures", mode = "function") &&
      !exists("pub_figure_ensure_formats", mode = "function")) {
    exp_src <- file.path(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), "R", "pub_figure_export.R"
    )
    if (!file.exists(exp_src)) exp_src <- file.path(getwd(), "R", "pub_figure_export.R")
    if (file.exists(exp_src)) source(exp_src, local = FALSE)
  }
  if (!exists("pub_figure_ensure_formats", mode = "function") &&
      !exists("export_pub_figures", mode = "function")) {
    cli::cli_alert_warning("发表图四目录：找不到 export_pub_figures / pub_figure_ensure_formats")
    return(invisible(FALSE))
  }
  figs_dir <- file.path(index_root, "Figures")
  dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  for (db in db_seq) {
    slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) as.character(db)[1L])
    } else {
      as.character(db)[1L]
    }
    src_roots <- c(
      file.path(index_root, slot, "Figures"),
      file.path(index_root, slot, "Figures", "pdf")
    )
    for (src in src_roots) {
      if (!dir.exists(src)) next
      pdfs <- list.files(src, pattern = "^Figure.*\\.pdf$", full.names = TRUE, ignore.case = TRUE)
      pdfs <- pdfs[file.info(pdfs)$isdir %in% FALSE]
      for (f in pdfs) {
        bn <- basename(f)
        dest_flat <- file.path(figs_dir, bn)
        dest_pdf <- file.path(figs_dir, "pdf", bn)
        if (file.exists(dest_pdf) && file.info(dest_pdf)$mtime >= file.info(f)$mtime) next
        if (file.exists(dest_flat) && file.info(dest_flat)$mtime >= file.info(f)$mtime) next
        file.copy(f, dest_flat, overwrite = TRUE)
      }
    }
  }
  if (is.null(meta)) {
    meta <- incidence_batch_pub_figure_meta(
      index_root, config,
      sub("^【[^】]+】", "", basename(index_root)), db_seq
    )
  }
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    out <- pub_figure_ensure_formats(figs_dir, meta = meta, config = config, purge = TRUE)
    return(invisible(isTRUE(out$ok)))
  }
  tryCatch({
    export_pub_figures(figs_dir, meta = meta, config = config, purge = TRUE)
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
    FALSE
  })
}

incidence_batch_finalize_index_outputs <- function(root, config, ix, db_seq) {
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq)) return(invisible(NULL))

  index_root <- incidence_batch_index_output_root(config, ix)
  if (!is_absolute_path(index_root)) index_root <- file.path(root, index_root)

  # 全项目铁律：无论是否 mirror_aggregate，成功收尾都必须写 code/ + blocks/ 源码镜像
  on.exit({
    if (exists("index_code_bundle_finalize", mode = "function")) {
      index_code_bundle_finalize(root, config, ix, db_seq, index_root)
    } else {
      cb_src <- file.path(
        Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = root), "R", "index_code_bundle.R"
      )
      if (!file.exists(cb_src)) cb_src <- file.path(root, "R", "index_code_bundle.R")
      if (file.exists(cb_src)) {
        tryCatch({
          source(cb_src, local = FALSE)
          index_code_bundle_finalize(root, config, ix, db_seq, index_root)
        }, error = function(e) {
          cli::cli_alert_warning("指标 code 包生成跳过: {e$message}")
        })
      }
    }
  }, add = TRUE)

  for (db in db_seq) {
    incidence_batch_sync_db_pub_outputs(root, config, ix, db)
    db_slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(config, db)
    } else {
      db
    }
    fig_dir <- file.path(index_root, db_slot, "Figures")
    if (dir.exists(fig_dir)) {
      if (incidence_batch_is_prognosis_config(config)) {
        incidence_batch_dedupe_prognosis_figures_dir(fig_dir, config)
      } else if (identical(
        tolower(as.character(config$project$study_type %||% "")[1L]), "incidence"
      )) {
        incidence_batch_dedupe_incidence_figures_dir(fig_dir, config)
      }
    }
  }

  # !mirror_aggregate：不做双库汇总拼图，但仍须导出指标根 Figures 四目录（pdf/png/tiff）
  if (!isTRUE((config$dual_db %||% list())$mirror_aggregate)) {
    if (!exists("export_pub_figures", mode = "function")) {
      eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
      exp_src <- c(
        if (nzchar(eng)) file.path(eng, "R", "pub_figure_export.R") else character(0),
        file.path(root, "R", "pub_figure_export.R"),
        file.path(getwd(), "R", "pub_figure_export.R")
      )
      exp_src <- exp_src[file.exists(exp_src)]
      if (length(exp_src)) source(exp_src[[1L]], local = FALSE)
    }
    # 单库/非聚合：db 槽发表 Tables 仍须汇总到指标根 Tables（全项目铁律；
    # 与 mirror_dual_db_aggregate 同口径：只收发表 xlsx，不收 tex/csv/ROC）
    tryCatch(
      incidence_batch_ensure_index_root_tables(index_root, config, db_seq),
      error = function(e) cli::cli_alert_warning("指标根 Tables 汇总跳过: {e$message}")
    )
    tryCatch(
      incidence_batch_ensure_index_pub_figure_formats(index_root, config, db_seq),
      error = function(e) cli::cli_alert_warning("发表图四目录导出跳过: {e$message}")
    )
    tryCatch(
      incidence_batch_write_software_versions(root, config, index_root),
      error = function(e) cli::cli_alert_warning("Software versions 跳过: {e$message}")
    )
    return(invisible(NULL))
  }
  incidence_batch_purge_aggregate_pub_cache(index_root)
  # ML 双库：mirror 前先 curate 各库 Tables/Figures，统一序号后再汇总
  if (incidence_batch_is_ml_dual_pub_scheme(config)) {
    if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
      source(file.path(getwd(), "R", "ml_dual_pub_table_curate.R"), local = FALSE)
    }
    for (db in db_seq) {
      db_slot <- dual_db_slot_path_name(config, db)
      db_tables <- file.path(index_root, db_slot, "Tables")
      if (dir.exists(db_tables)) {
        incidence_batch_curate_ml_pub_tables(db_tables, config)
      }
      db_fig <- file.path(index_root, db_slot, "Figures")
      if (dir.exists(db_fig)) {
        incidence_batch_curate_ml_pub_figures_dir(db_fig, cfg = config)
      }
    }
  }
  if (!exists("mirror_dual_db_aggregate", mode = "function")) {
    source(file.path(root, "R", "dual_db_harmonize.R"), local = FALSE)
  }
  mirror_dual_db_aggregate(root, config, out_root = index_root, dbs = db_seq)
  # 指标根 + 各库级 Tables 均为发表汇总：禁止残留 .tex（LaTeX 只留 step*/Tables）
  agg_table_dirs <- unique(c(
    file.path(index_root, "Tables"),
    vapply(db_seq, function(db) {
      file.path(index_root, dual_db_slot_path_name(config, db), "Tables")
    }, character(1L))
  ))
  for (td in agg_table_dirs) {
    if (exists("pipeline_purge_aggregate_tex", mode = "function")) {
      pipeline_purge_aggregate_tex(td, label = paste0("汇总 ", basename(dirname(td)), "/Tables"))
    } else if (dir.exists(td)) {
      stale_tex <- list.files(td, pattern = "\\.tex$", full.names = TRUE, ignore.case = TRUE)
      if (length(stale_tex)) unlink(stale_tex)
    }
  }
  agg_tables_tex <- file.path(index_root, "Tables")
  if (dir.exists(agg_tables_tex)) {
    stale_csv <- list.files(
      agg_tables_tex,
      pattern = "\\.csv$",
      full.names = TRUE,
      ignore.case = TRUE
    )
    stale_excl <- stale_csv[grepl(
      "^(Analysis_exclusion_|Flowchart_attrition)",
      basename(stale_csv),
      ignore.case = TRUE
    )]
    if (length(stale_excl)) {
      unlink(stale_excl)
      cli::cli_alert_info("已清理汇总 Tables 中 {length(stale_excl)} 个非发表 csv")
    }
  }
  incidence_batch_curate_index_pub_outputs(index_root, config, db_seq)
  light_fin <- isTRUE((config$incidence_batch %||% list())$.sensitivity_light) ||
    isTRUE((config$survival_batch %||% list())$.sensitivity_light)
  # 单库不走双库 S 链重排，但仍把 RCS cutoff logistic 定为 S-XX
  rcs_dirs <- unique(c(
    file.path(index_root, "Tables"),
    vapply(db_seq, function(db) {
      file.path(index_root, dual_db_slot_path_name(config, db), "Tables")
    }, character(1L))
  ))
  for (td in rcs_dirs) {
    incidence_batch_purge_aggregate_roc_tables(td)
  }
  agg_tables <- file.path(index_root, "Tables")
  if (length(db_seq) >= 2L && exists("survival_batch_clear_stale_cox_tables", mode = "function")) {
    for (db in db_seq) {
      survival_batch_clear_stale_cox_tables(
        file.path(index_root, dual_db_slot_path_name(config, db))
      )
    }
    survival_batch_clear_stale_cox_tables(index_root)
  }
  incidence_batch_purge_aggregate_scratch_tables(agg_tables)
  incidence_batch_purge_stale_main_logistic_and_subgroup_tables(agg_tables, config)
  for (db in db_seq) {
    incidence_batch_purge_stale_main_logistic_and_subgroup_tables(
      file.path(index_root, dual_db_slot_path_name(config, db), "Tables"),
      config,
      purge_sensitivity = FALSE
    )
  }
  scheme <- incidence_batch_pub_figure_scheme(config)
  if (identical(scheme, "ml_dual_dev_ext")) {
    de_src <- file.path(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = root), "R", "ml_dual_dev_ext.R"
    )
    if (!file.exists(de_src)) de_src <- file.path(root, "R", "ml_dual_dev_ext.R")
    if (file.exists(de_src) && !exists("ml_dual_dev_ext_compose_pub", mode = "function")) {
      source(de_src, local = FALSE)
    }
    tryCatch(
      ml_dual_dev_ext_compose_pub(index_root, config),
      error = function(e) cli::cli_alert_warning("dev_internal_ext 三集图/表跳过: {e$message}")
    )
  }
  if (scheme %in% c("ml_dual_standard", "ml_dual_dev_ext")) {
    if (!exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
      source(file.path(root, "R", "ml_dual_pub_table_curate.R"), local = FALSE)
    }
    incidence_batch_curate_ml_pub_tables(agg_tables, config)
    incidence_batch_collect_index_shiny_outputs(index_root, config, db_seq)
    for (td in rcs_dirs) {
      incidence_batch_shorten_pub_table_names(td, config)
    }
  } else {
    incidence_batch_realign_dual_supp_tables(agg_tables, config)
    for (db in db_seq) {
      db_tables <- file.path(
        index_root, dual_db_slot_path_name(config, db), "Tables"
      )
      incidence_batch_realign_dual_supp_tables(db_tables, config)
    }
    for (td in rcs_dirs) {
      incidence_batch_rename_rcs_tables_to_sxx(td, config)
      incidence_batch_compact_supp_s_numbers(td, config)
      incidence_batch_shorten_pub_table_names(td, config)
    }
  }

  incidence_batch_finalize_index_figures(
    root, config, ix, db_seq, index_root, light_fin = light_fin
  )

  tryCatch(
    incidence_batch_write_software_versions(root, config, index_root),
    error = function(e) cli::cli_alert_warning("Software versions 跳过: {e$message}")
  )

  # Phase 6：指标发表收口后自动结构 QC（Agent 再填 nature Layer D）
  tryCatch({
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    qc_src <- c(
      if (nzchar(eng)) file.path(eng, "R/pub_qc_after_finalize.R") else character(0),
      file.path(getwd(), "R/pub_qc_after_finalize.R")
    )
    qc_src <- qc_src[file.exists(qc_src)]
    if (length(qc_src)) source(qc_src[[1L]], local = FALSE)
    if (exists("pub_qc_run_after_project", mode = "function")) {
      pub_qc_run_after_project(root, config = config)
    }
  }, error = function(e) cli::cli_alert_warning("pub-qc 跳过: {e$message}"))

  # code 包由函数开头 on.exit 统一写入（全项目铁律）
}

incidence_batch_write_software_versions <- function(root, config, index_root) {
  if (!exists("pub_write_software_versions", mode = "function")) {
    eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    srcs <- c(
      if (nzchar(eng)) file.path(eng, "R", "pub_software_versions.R") else character(0),
      file.path(root, "R", "pub_software_versions.R"),
      file.path(getwd(), "R", "pub_software_versions.R")
    )
    srcs <- srcs[file.exists(srcs)]
    if (!length(srcs)) return(invisible(NULL))
    source(srcs[[1L]], local = FALSE)
  }
  pub_write_software_versions(
    index_root = index_root,
    project_root = root,
    config = config
  )
}

# ── 3. 叠加单库数据路径 ────────────────────────────────────────────────────────
incidence_batch_apply_db_overrides <- function(config, db, root, ix) {
  # 统一槽位：eicu/nhanes/primary → primary；mimic/secondary → secondary
  slot <- if (exists("dual_db_normalize_slot", mode = "function")) {
    dual_db_normalize_slot(db)
  } else {
    db0 <- tolower(as.character(db)[1L])
    if (db0 %in% c("nhanes", "nhance", "eicu", "e_icu", "primary")) "nhanes" else "mimic"
  }
  is_pri <- identical(slot, "nhanes") ||
    (exists("dual_db_slot_is_primary", mode = "function") &&
       isTRUE(dual_db_slot_is_primary(slot)))
  db_cfg <- if (is_pri) config$dual_db$primary else config$dual_db$secondary
  db_cfg <- db_cfg %||% list()
  # 单库课题可能未写 dual_db$primary：保留 config$project / data 已有字段
  if (!is.null(db_cfg$rawdata_path) && nzchar(as.character(db_cfg$rawdata_path)[1L])) {
    config$data$rawdata_path <- db_cfg$rawdata_path
  }
  if (!is.null(db_cfg$rawdata_obj) && nzchar(as.character(db_cfg$rawdata_obj)[1L])) {
    config$data$rawdata_obj <- db_cfg$rawdata_obj
  }
  if (!is.null(db_cfg$id_column) && nzchar(as.character(db_cfg$id_column)[1L])) {
    config$data$id_column <- db_cfg$id_column
  }
  config$data$outcome_column      <- config$data$outcome_column %||% "Disease_Group"
  if (!is.null(db_cfg$column_mapping_type) && nzchar(as.character(db_cfg$column_mapping_type)[1L])) {
    config$column_mapping$database_type <- db_cfg$column_mapping_type
  } else if (is.null(config$column_mapping$database_type) ||
             !nzchar(as.character(config$column_mapping$database_type)[1L])) {
    config$column_mapping$database_type <- config$project$database_type %||% "nhanes"
  }
  if (!is.null(db_cfg$name) && nzchar(as.character(db_cfg$name)[1L])) {
    config$project$database <- db_cfg$name
  }
  if (!is.null(db_cfg$db_type) && nzchar(as.character(db_cfg$db_type)[1L])) {
    config$project$database_type <- db_cfg$db_type
  } else if (is.null(config$project$database_type) ||
             !nzchar(as.character(config$project$database_type)[1L])) {
    config$project$database_type <- "nhanes"
  }
  config$project$root             <- root
  config$dual_db$current_db       <- slot

  bc <- config$incidence_batch %||% config$ml_batch %||% list()
  ix_lab <- if (exists("incidence_batch_index_dir_label", mode = "function")) {
    incidence_batch_index_dir_label(ix, config)
  } else {
    as.character(ix)[1L]
  }
  ix_root <- if (exists("incidence_batch_find_index_output_dir", mode = "function")) {
    incidence_batch_find_index_output_dir(
      bc$output_base %||% config$project$output_dir,
      ix_lab,
      incidence_batch_index_output_subdir(bc),
      config = config,
      ix_bare = ix
    )
  } else {
    file.path(
      bc$output_base %||% config$project$output_dir,
      incidence_batch_index_output_subdir(bc),
      ix_lab
    )
  }
  config$project$output_dir <- file.path(ix_root, dual_db_slot_path_name(config, slot))

  # Per-index imputation 阈值：非指标公共列缺失 > 阈值 则删除
  db_im_key <- if (is_pri) "nhanes_imputation_threshold" else "mimic_imputation_threshold"
  db_im <- bc[[db_im_key]] %||% 0.40
  config$imputation$missing_col_threshold <- db_im
  if (!exists("ml_dual_apply_dev_ext_db_overrides", mode = "function")) {
    de_src <- file.path(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), "R", "ml_dual_dev_ext.R"
    )
    if (file.exists(de_src)) source(de_src, local = FALSE)
  }
  if (exists("ml_dual_apply_dev_ext_db_overrides", mode = "function")) {
    config <- ml_dual_apply_dev_ext_db_overrides(config, is_pri)
  }
  # 插补表/图由 config$imputation$export_* 控制（共享层无 imputation 步，此处为 per-index worker）

  if (!dual_db_is_weighted(config, slot)) {
    config$multicollinearity$screen$table_title <-
      "Multicollinearity Analysis VIF screen"
    config$multicollinearity$final$table_title <-
      "Multicollinearity Analysis VIF final"
    config$multicollinearity$screen$csv_name <- "VIF_check_screen.csv"
    config$multicollinearity$final$csv_name  <- "VIF_check_final.csv"
  }

  # 按库覆盖 RCS / RCS-logistic 协变量（Table 3 可与 Table 2 不同）
  # vif_final 锁定后 RCS 必须与 Gate B / Table 2 同套，不再套用 db_rcs 预设
  cov_src <- if (exists("dual_db_harmonization_covariate_source", mode = "function")) {
    dual_db_harmonization_covariate_source(config)
  } else {
    as.character((config$dual_db$harmonization %||% list())$covariate_source %||% "")[1L]
  }
  skip_rcs_preset <- identical(tolower(trimws(as.character(cov_src)[1L])), "vif_final")
  patch <- (bc$db_rcs_logistic_models %||% list())[[slot]]
  if (is.null(patch) || !length(patch)) {
    patch <- (bc$db_rcs_logistic_models %||% list())[[as.character(db)[1L]]]
  }
  if (!skip_rcs_preset && !is.null(patch) && length(patch)) {
    for (blk in names(patch)) {
      pf <- patch[[blk]]
      if (is.null(config[[blk]])) config[[blk]] <- list()
      if (length(pf$m1 %||% pf$model1_factors)) {
        config[[blk]]$model1_factors <- as.character(pf$m1 %||% pf$model1_factors)
      }
      if (length(pf$m2 %||% pf$model2_factors)) {
        config[[blk]]$model2_factors <- as.character(pf$m2 %||% pf$model2_factors)
      }
    }
  }

  config
}

# ── 4. 设置 pipeline 检查点目录 ───────────────────────────────────────────────
incidence_batch_set_pipeline_ck <- function(pipeline, dir) {
  pipeline$checkpoint$enable <- TRUE
  pipeline$checkpoint$dir    <- dir
  pipeline
}

# logistic_gate 可能跳过 binary/tertile，Phase 3 须从实际落盘的最后一个 Phase-2 logistic 步续跑
# （仅 rcs_* 之前的 quartile/tertile/binary，排除 _rcs 与 NHANES 流水线末尾的 mimic 尾块）
incidence_batch_last_logistic_ck_token <- function(ck_dir, pipeline) {
  blocks <- as.character(pipeline$blocks %||% character(0))
  rcs_pos <- match(c("rcs_nhanes", "rcs_incidence"), blocks)
  rcs_pos <- rcs_pos[!is.na(rcs_pos)]
  end_idx <- if (length(rcs_pos)) min(rcs_pos) - 1L else length(blocks)
  if (end_idx < 1L) return(NULL)
  pre_rcs <- blocks[seq_len(end_idx)]
  logistic_blocks <- pre_rcs[
    grepl("^logistic_(binary|tertile|quartile)", pre_rcs) & !grepl("_rcs", pre_rcs)
  ]
  if (!length(logistic_blocks)) return(NULL)
  for (b in rev(logistic_blocks)) {
    idx   <- match(b, blocks)
    ck_id <- pipeline_checkpoint_id(idx, b)
    path  <- file.path(ck_dir, paste0(ck_id, ".rds"))
    alias <- file.path(ck_dir, paste0(b, ".rds"))
    if (file.exists(path) || file.exists(alias)) return(b)
  }
  NULL
}

# ── 5. Shared checkpoint 目录 ─────────────────────────────────────────────────
incidence_batch_cfg <- function(config) {
  utils::modifyList(
    config$incidence_batch %||% list(),
    config$survival_batch %||% list()
  )
}

incidence_batch_shared_ck_parent <- function(config) {
  bc <- incidence_batch_cfg(config)
  bc$shared_ck_base %||% "checkpoints/_shared"
}

#' 读取用：优先 config 库名目录，回退 legacy nhanes/mimic
incidence_batch_shared_ck_dir <- function(config, db) {
  dual_db_resolve_slot_dir(incidence_batch_shared_ck_parent(config), config, db)
}

#' 写入用：始终使用 dual_db$name（如 eICU、MIMIC）
incidence_batch_shared_ck_canonical_dir <- function(config, db) {
  file.path(
    incidence_batch_shared_ck_parent(config),
    dual_db_slot_path_name(config, db)
  )
}

# ── 6. 跑共享层（单库）─────────────────────────────────────────────────────────
#  顺序：data_clean(1.0) → column_mapping → dual_db_column_harmonize → index
#  Gate A 列名交集由 incidence_batch_gate_a_from_clean 在主流程注入 config
incidence_batch_run_shared_layer <- function(root, config, db,
                                              pipeline_shared, ck_dir) {
  cfg <- config
  db_cfg <- if (db == "nhanes") config$dual_db$primary else config$dual_db$secondary
  cfg$data$rawdata_path        <- db_cfg$rawdata_path
  cfg$data$rawdata_obj         <- db_cfg$rawdata_obj
  cfg$data$id_column           <- db_cfg$id_column
  cfg$column_mapping$database_type <- db_cfg$column_mapping_type
  cfg$project$database         <- db_cfg$name
  cfg$project$database_type    <- db_cfg$db_type
  cfg$project$root             <- root
  cfg$dual_db$current_db       <- db

  bc <- config$incidence_batch %||% list()
  cfg$project$output_dir <- file.path(
    bc$output_base %||% config$project$output_dir,
    "_shared", dual_db_slot_path_name(config, db)
  )
  # 共享层：不插补，不生成 Table S1/缺失图（插补移至 per-index worker）
  cfg$imputation$export_missing_fig <- FALSE
  cfg$imputation$export_table_s1   <- FALSE

  # dual_db enable 必须为 TRUE，否则 dual_db_column_harmonize 会直接跳过
  cfg$dual_db$enable <- TRUE

  # 共享层 data_clean 不删任何列（阈值 = 1.0），仅做数据加载 + 结局过滤
  # 列限制由后续 dual_db_column_harmonize（Gate A 交集）来做
  # 行缺失删人（row_missing_threshold）仍按课题 config 执行，不在此清掉
  cfg$data_clean$missing_threshold <- 1.0
  .row_miss <- suppressWarnings(as.numeric(cfg$data_clean$row_missing_threshold %||% NA_real_)[1L])
  cli::cli_alert_info(
    "  [{toupper(db)}] 共享层 data_clean: 不删列（threshold=1.0），列限制由 harmonize 完成{if (is.finite(.row_miss)) paste0('；行缺失删人 threshold=', .row_miss) else ''}"
  )
  rm(.row_miss)

  pl <- pipeline_shared
  pl$checkpoint$dir    <- ck_dir
  pl$dual_db           <- list(enable = TRUE)  # 共享层启用双库以支持 column_harmonize

  # 共享层必须带着 Gate A keep；空 keep + Ventilation 别名曾把 105 列削成 1 列
  if (isTRUE(cfg$dual_db$enable)) {
    keep_chk <- if (exists("dual_db_column_keep_for_db", mode = "function")) {
      dual_db_column_keep_for_db(cfg, db, cfg$dual_db$harmonization)
    } else {
      character(0)
    }
    if (!length(keep_chk)) {
      cli::cli_alert_warning(
        "共享层 [{toupper(db)}] Gate A keep 为空：harmonize 将跳过列过滤（假双库/单库可接受；真双库请先跑 Gate A）"
      )
    } else {
      cli::cli_alert_info(
        "共享层 [{toupper(db)}] Gate A keep={length(keep_chk)} 列"
      )
    }
  }

  cli::cli_h2("共享层 [{dual_db_slot_path_name(config, db)}] — {paste(pl$blocks, collapse=' → ')}")
  run_pipeline(root, config = cfg, pipeline = pl)
  alias_ck <- file.path(ck_dir, "index.rds")
  if (file.exists(alias_ck) && exists("pipeline_patch_checkpoint_outcome_group", mode = "function")) {
    pipeline_patch_checkpoint_outcome_group(alias_ck, cfg)
    cli::cli_alert_info("共享层 checkpoint 已补全 Disease_Group（由 Disease 复制）")
  }
  # 硬断言：共享层 mapped 不得被削成仅通气/结局列
  if (file.exists(alias_ck)) {
    obj_ck <- tryCatch(readRDS(alias_ck), error = function(e) NULL)
    df_ck <- if (!is.null(obj_ck)) incidence_batch_ctx_data(obj_ck$ctx) else NULL
    n_ck <- if (is.data.frame(df_ck)) ncol(df_ck) else 0L
    if (!is.data.frame(df_ck) || n_ck < 10L) {
      stop(
        sprintf(
          "共享层 [%s] mapped 仅 %s 列（期望≥10）。Gate A keep 可能未注入或被 Ventilation 别名掏空；请 --no-skip 重跑共享层。",
          toupper(db), as.character(n_ck)
        ),
        call. = FALSE
      )
    }
  }
  invisible(NULL)
}

# ── 7. 检查指标在 shared checkpoint 中是否可用 ────────────────────────────────
incidence_batch_index_available <- function(shared_ck_dir, ix) {
  alias <- file.path(shared_ck_dir, "index.rds")
  if (!file.exists(alias)) return(NA)
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(NA)
  data <- incidence_batch_ctx_data(obj$ctx)
  if (is.null(data) || !is.data.frame(data)) return(NA)
  if (!ix %in% names(data)) return(FALSE)
  sum(!is.na(data[[ix]])) > 0
}

# ── 8. 过滤该指标的 NA 行 + 前后 p_trim 极端值（原地修改检查点文件）──────────
incidence_batch_apply_filter_and_trim <- function(ck_path, ix, p_trim = 0.01) {
  if (!file.exists(ck_path)) {
    cli::cli_alert_warning("  检查点不存在，跳过过滤: {.file {basename(ck_path)}}")
    return(invisible(list(n_before = NA, n_after = NA, n_na = NA, n_trim = NA)))
  }
  obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    cli::cli_alert_warning("  检查点无效，跳过过滤")
    return(invisible(list(n_before = NA, n_after = NA, n_na = NA, n_trim = NA)))
  }

  ctx    <- obj$ctx
  result <- list()

  for (slot in c("mapped", "imputed", "cleaned")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df) || !ix %in% names(df)) next

    n_before <- nrow(df)
    vals     <- suppressWarnings(as.numeric(df[[ix]]))

    # 步骤 1：删除 ix 为 NA 的行
    keep     <- !is.na(vals)
    n_na     <- sum(!keep)
    df       <- df[keep, , drop = FALSE]
    vals     <- vals[keep]

    # 步骤 2：删除前后极端值（>10000 人各 5%，否则用 p_trim）
    n_trim <- 0L
    p_use  <- trim_index_quantile_for_n(length(vals), base_trim = p_trim)
    if (length(vals) >= 20 && p_use > 0) {
      q_lo   <- quantile(vals, probs = p_use,     na.rm = TRUE)
      q_hi   <- quantile(vals, probs = 1 - p_use, na.rm = TRUE)
      keep_t <- vals >= q_lo & vals <= q_hi
      n_trim <- sum(!keep_t)
      df     <- df[keep_t, , drop = FALSE]
    }

    n_after            <- nrow(df)
    ctx$data[[slot]]   <- df
    result[[slot]]     <- list(
      n_before = n_before, n_na = n_na, n_trim = n_trim, n_after = n_after
    )
    cli::cli_alert_success(
      "  [{slot}] {ix}: {n_before} 行 → 删 NA {n_na} 行, 删极端值 {n_trim} 行 → 剩余 {n_after} 行"
    )
    if (exists("attrition_record", mode = "function") && exists("ctx", inherits = FALSE)) {
      ctx <- attrition_record(
        ctx,
        step_id = paste0("after_index_filter_", ix),
        label = sprintf("After excluding missing/extreme %s", ix),
        n = as.integer(n_after),
        meta = list(block = "index_filter", index = ix, n_na = n_na, n_trim = n_trim)
      )
    }
  }

  obj$ctx <- ctx
  saveRDS(obj, ck_path)
  invisible(result)
}

# ── 8b. 亚组补救重跑：在 per-index ck 上原地按亚组表达式剔除行 ───────────────
#  与 incidence_batch_apply_filter_and_trim 同构，但谓词是任意亚组表达式
#  （如 "Age >= 65"、"Hypertension == \"Yes\""、"BMI >= 28"）。
#  在 worker 复制 shared ck 之后、跑分析阶段之前调用，使 imputation 及所有
#  下游块（baseline/univariate/VIF/logistic/RCS/subgroup/mediation）都在亚组人群上重跑。
incidence_batch_apply_subgroup_filter <- function(ck_path, expr, ix = NULL) {
  if (!file.exists(ck_path)) {
    cli::cli_alert_warning("  亚组过滤：检查点不存在，跳过: {.file {basename(ck_path)}}")
    return(invisible(list()))
  }
  obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    cli::cli_alert_warning("  亚组过滤：检查点无效，跳过")
    return(invisible(list()))
  }

  ctx    <- obj$ctx
  result <- list()
  need   <- tryCatch(all.vars(parse(text = expr)), error = function(e) character(0))

  # 先清洗 No /Yes 尾随空格，否则 Hypertension != "Yes" 对 "Yes " 恒为 TRUE
  if (exists("pipeline_normalize_yes_no_factors", mode = "function")) {
    for (slot_fix in c("raw", "cleaned", "mapped", "imputed")) {
      df_fix <- ctx$data[[slot_fix]]
      if (is.null(df_fix) || !is.data.frame(df_fix)) next
      ctx$data[[slot_fix]] <- pipeline_normalize_yes_no_factors(df_fix)
    }
  }

  # 优先在含齐所需列的 slot 上求 keep；data_clean 常丢掉 T2DM/Diabetes，
  # 但 raw 仍保留 → 用 raw 的行掩码同步裁剪 mapped/cleaned/imputed（同行序）。
  keep_ref <- NULL
  n_ref <- NA_integer_
  for (slot_try in c("raw", "cleaned", "mapped", "imputed")) {
    df0 <- ctx$data[[slot_try]]
    if (is.null(df0) || !is.data.frame(df0)) next
    if (length(need) && !all(need %in% names(df0))) next
    keep0 <- tryCatch(eval(parse(text = expr), envir = df0),
                      error = function(e) NULL)
    if (is.null(keep0) || length(keep0) != nrow(df0)) next
    keep0 <- as.logical(keep0); keep0[is.na(keep0)] <- FALSE
    keep_ref <- keep0
    n_ref <- nrow(df0)
    cli::cli_alert_info("  亚组掩码取自 [{slot_try}]：保留 {sum(keep_ref)}/{n_ref} 行")
    break
  }
  if (is.null(keep_ref)) {
    cli::cli_alert_warning("  亚组过滤：各 slot 均缺所需列或求值失败，跳过: {expr}")
    return(invisible(list()))
  }

  for (slot in c("mapped", "imputed", "cleaned", "raw")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df)) next
    n_before <- nrow(df)
    if (n_before == n_ref) {
      keep <- keep_ref
    } else if (length(need) && all(need %in% names(df))) {
      keep <- tryCatch(eval(parse(text = expr), envir = df),
                       error = function(e) {
                         cli::cli_alert_warning("  [{slot}] 亚组表达式求值失败，保留全部行: {e$message}")
                         rep(TRUE, nrow(df))
                       })
      if (is.null(keep) || length(keep) != nrow(df)) keep <- rep(TRUE, n_before)
      keep <- as.logical(keep); keep[is.na(keep)] <- FALSE
    } else {
      cli::cli_alert_warning(
        "  [{slot}] 行数与掩码源不一致且缺列（n={n_before} vs {n_ref}），跳过该 slot"
      )
      next
    }
    df <- df[keep, , drop = FALSE]
    n_after <- nrow(df)

    ctx$data[[slot]] <- df
    result[[slot]]   <- list(n_before = n_before, n_after = n_after)
    cli::cli_alert_success(
      "  [{slot}] 亚组过滤 '{expr}': {n_before} 行 → 剩余 {n_after} 行"
    )
  }

  obj$ctx <- ctx
  saveRDS(obj, ck_path)
  invisible(result)
}

# ── 9. 复制 shared checkpoint → per-index 目录 ────────────────────────────────
incidence_batch_copy_shared_ck <- function(shared_ck_dir, per_index_ck_dir,
                                            ix, p_trim = 0.01, config = NULL) {
  if (!dir.exists(per_index_ck_dir))
    dir.create(per_index_ck_dir, recursive = TRUE)

  alias_src <- file.path(shared_ck_dir, "index.rds")
  alias_dst <- file.path(per_index_ck_dir, "index.rds")

  if (!file.exists(alias_src)) {
    cli::cli_alert_warning("  共享检查点 {.file {alias_src}} 不存在，跳过")
    return(FALSE)
  }
  file.copy(alias_src, alias_dst, overwrite = TRUE)
  cli::cli_alert_info("  复制共享检查点 → {.file {alias_dst}}")

  # per-index：再次剔除 config 指定 drop_columns（共享 raw 槽可能仍带问卷 Diabetes）
  drop_cols <- if (!is.null(config)) {
    as.character((config$data_clean %||% list())$drop_columns %||% character(0))
  } else {
    character(0)
  }
  drop_cols <- unique(drop_cols[nzchar(drop_cols)])
  if (length(drop_cols)) {
    obj <- tryCatch(readRDS(alias_dst), error = function(e) NULL)
    if (!is.null(obj) && !is.null(obj$ctx$data)) {
      n_drop <- 0L
      for (slot in c("raw", "cleaned", "mapped", "imputed")) {
        df <- obj$ctx$data[[slot]]
        if (!is.data.frame(df)) next
        hit <- intersect(drop_cols, names(df))
        if (length(hit)) {
          obj$ctx$data[[slot]] <- df[, setdiff(names(df), hit), drop = FALSE]
          n_drop <- n_drop + length(hit)
        }
      }
      if (n_drop > 0L) {
        saveRDS(obj, alias_dst)
        cli::cli_alert_info("  已从 per-index ck 剔除列: {paste(drop_cols, collapse = ', ')}")
      }
    }
  }

  # 原地过滤：删除 ix 的 NA 行 + 极端值（p_trim=0 时只删 NA）
  stats <- incidence_batch_apply_filter_and_trim(alias_dst, ix, p_trim)
  invisible(structure(TRUE, filter_stats = stats))
}

# ── 10. 文件夹重命名（【success】<ix> / 【failed】<ix>）──────────────────────
# SMB/WSL 上目录 rename 常因句柄未释放报 Permission denied。
# 策略：短暂等待 → 多次重试 file.rename/mv → Windows Rename-Item → cp -a + rm 回退。
incidence_batch_rename_output_folder <- function(output_base, ix, status,
                                                  max_tries = 8L,
                                                  settle_sec = 2,
                                                  overwrite = FALSE,
                                                  index_subdir = "by_index",
                                                  config = NULL) {
  ix_dir <- if (!is.null(config) && exists("incidence_batch_index_dir_label", mode = "function")) {
    incidence_batch_index_dir_label(ix, config)
  } else {
    as.character(ix)[1L]
  }
  old_path <- file.path(output_base, index_subdir, ix_dir)
  if (!dir.exists(old_path)) return(invisible(NULL))

  new_name <- incidence_batch_output_dir_name(ix_dir, status)
  new_path <- file.path(output_base, index_subdir, new_name)

  if (dir.exists(new_path)) {
    same <- identical(
      normalizePath(old_path, winslash = "/", mustWork = FALSE),
      normalizePath(new_path, winslash = "/", mustWork = FALSE)
    )
    if (same) return(invisible(new_path))
    ## 防误删：若目标目录文件明显多于源目录，说明 worker 已写在【success】里，勿用空/残缺裸名覆盖
    n_old <- length(list.files(old_path, recursive = TRUE, all.files = TRUE))
    n_new <- length(list.files(new_path, recursive = TRUE, all.files = TRUE))
    if (isTRUE(overwrite) && n_new > n_old + 5L) {
      cli::cli_alert_warning(
        "  {ix} 跳过覆盖 {new_name}：目标已有 {n_new} 个文件，源仅 {n_old}（避免清空已写结果）"
      )
      ## 清理空/残缺裸名，保留已写好的【success】
      if (n_old <= 5L && exists("pipeline_remove_dir", mode = "function")) {
        pipeline_remove_dir(old_path)
      }
      return(invisible(new_path))
    }
    if (isTRUE(overwrite) && exists("pipeline_remove_dir", mode = "function") &&
        pipeline_remove_dir(new_path)) {
      cli::cli_alert_info("  \U0001f4c1 {ix} 已覆盖旧目录: {new_name}")
    } else if (isTRUE(overwrite)) {
      cli::cli_alert_warning("  {ix} 无法删除旧 {new_name}，放弃覆盖")
      return(invisible(new_path))
    } else {
      cli::cli_alert_info("  \U0001f4c1 {ix} 目标已存在: {new_name}")
      return(invisible(new_path))
    }
  }

  if (is.finite(as.numeric(settle_sec)[1L]) && as.numeric(settle_sec)[1L] > 0) {
    Sys.sleep(as.numeric(settle_sec)[1L])
  }

  .try_file_rename <- function() {
    msg <- NULL
    ok <- FALSE
    withCallingHandlers(
      {
        ok <- isTRUE(file.rename(old_path, new_path))
      },
      warning = function(w) {
        msg <<- conditionMessage(w)
        invokeRestart("muffleWarning")
      }
    )
    list(ok = isTRUE(ok) && dir.exists(new_path) && !dir.exists(old_path), msg = msg)
  }

  .try_system_mv <- function() {
    mv <- Sys.which("mv")
    if (!nzchar(mv)) return(list(ok = FALSE, msg = "mv not found"))
    st <- system2(mv, c("-f", old_path, new_path), stdout = TRUE, stderr = TRUE)
    list(
      ok = dir.exists(new_path) && !dir.exists(old_path),
      msg = if (length(st)) paste(st, collapse = "\n") else NULL
    )
  }

  .try_powershell_rename <- function() {
    if (!grepl("^/mnt/[a-zA-Z]/", old_path)) return(list(ok = FALSE, msg = NULL))
    ps <- Sys.which("powershell.exe")
    if (!nzchar(ps)) ps <- Sys.which("powershell")
    if (!nzchar(ps)) return(list(ok = FALSE, msg = NULL))
    wslpath <- Sys.which("wslpath")
    if (!nzchar(wslpath)) return(list(ok = FALSE, msg = NULL))
    win_old <- tryCatch(
      system2(wslpath, c("-w", old_path), stdout = TRUE, stderr = FALSE),
      error = function(e) character(0)
    )
    if (!length(win_old) || !nzchar(win_old[1L])) return(list(ok = FALSE, msg = NULL))
    cmd <- sprintf(
      "Rename-Item -LiteralPath '%s' -NewName '%s' -ErrorAction Stop",
      gsub("'", "''", win_old[1L], fixed = TRUE),
      gsub("'", "''", new_name, fixed = TRUE)
    )
    st <- system2(ps, c("-NoProfile", "-Command", cmd), stdout = TRUE, stderr = TRUE)
    list(
      ok = dir.exists(new_path) && !dir.exists(old_path),
      msg = if (length(st)) paste(st, collapse = "\n") else NULL
    )
  }

  .try_copy_then_remove <- function() {
    msgs <- character(0)
    if (dir.exists(new_path)) {
      return(list(ok = FALSE, msg = "destination already exists"))
    }
    cp <- Sys.which("cp")
    if (nzchar(cp)) {
      st <- system2(cp, c("-a", old_path, new_path), stdout = TRUE, stderr = TRUE)
      if (length(st)) msgs <- c(msgs, paste(st, collapse = "\n"))
    } else {
      ok_copy <- FALSE
      tryCatch({
        dir.create(dirname(new_path), recursive = TRUE, showWarnings = FALSE)
        file.copy(old_path, dirname(new_path), recursive = TRUE, copy.date = TRUE)
        staged <- file.path(dirname(new_path), basename(old_path))
        if (dir.exists(staged) && !identical(staged, new_path)) {
          file.rename(staged, new_path)
        }
        ok_copy <- dir.exists(new_path)
      }, error = function(e) msgs <<- c(msgs, conditionMessage(e)))
      if (!ok_copy) return(list(ok = FALSE, msg = paste(msgs, collapse = "; ")))
    }
    if (!dir.exists(new_path)) {
      return(list(ok = FALSE, msg = paste(c("copy failed", msgs), collapse = "; ")))
    }
    unlink(old_path, recursive = TRUE, force = TRUE)
    if (dir.exists(old_path)) {
      system2("rm", c("-rf", old_path), stdout = TRUE, stderr = TRUE)
    }
    list(
      ok = dir.exists(new_path) && !dir.exists(old_path),
      msg = if (dir.exists(old_path)) "copied but old dir remains" else paste(msgs, collapse = "; ")
    )
  }

  rename_msg <- NULL
  ok <- FALSE
  max_tries <- max(1L, as.integer(max_tries)[1L])
  for (i in seq_len(max_tries)) {
    for (fn in list(.try_file_rename, .try_system_mv, .try_powershell_rename)) {
      res <- fn()
      if (isTRUE(res$ok)) {
        ok <- TRUE
        break
      }
      if (!is.null(res$msg) && nzchar(res$msg)) {
        rename_msg <- paste(c(rename_msg, res$msg), collapse = "; ")
      }
    }
    if (ok) break
    Sys.sleep(min(16, 2^(i - 1L)))
  }

  if (!ok) {
    res <- .try_copy_then_remove()
    ok <- isTRUE(res$ok)
    if (!is.null(res$msg) && nzchar(res$msg)) {
      rename_msg <- paste(c(rename_msg, res$msg), collapse = "; ")
    }
  }

  if (ok && dir.exists(new_path)) {
    cli::cli_alert_info("  \U0001f4c1 {ix} \u2192 {new_name}")
  } else {
    cli::cli_alert_warning(
      "重命名失败 {ix} \u2192 {new_name}: {rename_msg %||% 'unknown'}（目录可能仍为裸名）"
    )
  }
  invisible(if (dir.exists(new_path)) new_path else old_path)
}

# ── 11. 写 _batch_status.json + _index_summary.csv ────────────────────────────
incidence_batch_write_status <- function(output_ix_dir, fields) {
  if (!dir.exists(output_ix_dir)) dir.create(output_ix_dir, recursive = TRUE)

  fields$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  # JSON 状态文件
  json_path <- file.path(output_ix_dir, "_batch_status.json")
  tryCatch(
    writeLines(jsonlite::toJSON(fields, auto_unbox = TRUE, pretty = TRUE), json_path),
    error = function(e) message("无法写入 _batch_status.json: ", e$message)
  )

  # 人类可读摘要 CSV
  summary_df <- data.frame(
    字段  = names(fields),
    值    = sapply(fields, function(v) paste(as.character(v), collapse = "; ")),
    stringsAsFactors = FALSE
  )
  csv_path <- file.path(output_ix_dir, "_index_summary.csv")
  tryCatch(
    utils::write.csv(summary_df, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) NULL
  )

  invisible(json_path)
}

# ── 12. 状态文件路径（支持已重命名的文件夹）──────────────────────────────────
incidence_batch_status_path <- function(output_base, ix, index_subdir = "by_index", config = NULL) {
  ix_names <- unique(c(
    ix,
    if (!is.null(config) && exists("incidence_batch_index_dir_label", mode = "function")) {
      incidence_batch_index_dir_label(ix, config)
    } else {
      character(0)
    }
  ))
  candidates <- unlist(lapply(ix_names, function(nm) {
    c(
      file.path(output_base, index_subdir, nm, "_batch_status.json"),
      file.path(output_base, index_subdir, incidence_batch_output_dir_name(nm, "success"),
                "_batch_status.json"),
      file.path(output_base, index_subdir, incidence_batch_output_dir_name(nm, "failed"),
                "_batch_status.json")
    )
  }), use.names = FALSE)
  for (sfx in c("\u300c\u6210\u529f\u300d", "\u300c\u5931\u8d25\u300d")) {
    candidates <- c(
      candidates,
      unlist(lapply(ix_names, function(nm) {
        file.path(output_base, index_subdir, paste0(nm, sfx), "_batch_status.json")
      }), use.names = FALSE)
    )
  }
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1L] else candidates[1L]
}

# ── 13. 派发 Worker 子进程（含文件夹重命名监控）─────────────────────────────
#' 阶段别名 → 各库真实 block 名（供 --from/--to 短名）
incidence_batch_stage_alias_map <- function() {
  list(
    subgroup  = c(nhanes = "subgroup_nhanes_weighted",
                  mimic  = "subgroup_incidence"),
    mediation = c(nhanes = "mediation_nhanes_weighted",
                  mimic  = "mediation_incidence"),
    rcs       = c(nhanes = "rcs_nhanes",
                  mimic  = "rcs_incidence"),
    logistic  = c(nhanes = "dual_db_logistic_main_table_realign",
                  mimic  = "dual_db_logistic_main_table_realign"),
    # 含 dual_db_logistic_scheme_harmonize（闸门 C + 救援后 Gate B 重同步）
    gate_c    = c(nhanes = "dual_db_logistic_scheme_harmonize",
                  mimic  = "dual_db_logistic_scheme_harmonize")
  )
}

incidence_batch_is_sensitivity_token <- function(x) {
  tolower(trimws(as.character(x %||% "")[1L])) %in%
    c("sensitivity", "sens", "sa")
}

#' 解析 --from/--to。
#' 阶段别名的 --from 为「含该步」：返回该步的前一块，供 run_pipeline(from=) 续跑语义。
#' 完整 block 名保持 pipeline 原义（from=该块之后）。
#' --to sensitivity 返回 pipeline_to=NULL + want_sensitivity=TRUE。
incidence_batch_resolve_from_to <- function(config, db, from_token = NULL, to_token = NULL) {
  pipe <- if (dual_db_is_weighted(config, db)) {
    if (exists("pipeline_nhanes_batch", inherits = TRUE)) pipeline_nhanes_batch else NULL
  } else {
    if (exists("pipeline_regular_batch", inherits = TRUE)) pipeline_regular_batch else NULL
  }
  blocks <- as.character((pipe %||% list())$blocks %||% character(0))
  aliases <- incidence_batch_stage_alias_map()
  alias_names <- names(aliases)

  .resolve_one <- function(tok, role) {
    if (is.null(tok)) return(list(block = NULL, sensitivity = FALSE, alias = FALSE))
    raw <- trimws(as.character(tok)[1L])
    if (!nzchar(raw)) return(list(block = NULL, sensitivity = FALSE, alias = FALSE))
    if (incidence_batch_is_sensitivity_token(raw)) {
      if (!identical(role, "to")) {
        stop("--from 不能是 sensitivity；请用 --to sensitivity", call. = FALSE)
      }
      return(list(block = NULL, sensitivity = TRUE, alias = TRUE))
    }
    key <- tolower(raw)
    if (key %in% alias_names) {
      b <- unname(aliases[[key]][[db]])
      if (is.null(b) || !nzchar(b)) {
        stop("别名 '", raw, "' 在库 ", db, " 无对应 block", call. = FALSE)
      }
      return(list(block = b, sensitivity = FALSE, alias = TRUE))
    }
    list(block = raw, sensitivity = FALSE, alias = FALSE)
  }

  fr <- .resolve_one(from_token, "from")
  to <- .resolve_one(to_token, "to")

  from_pipe <- fr$block
  if (isTRUE(fr$alias) && !is.null(fr$block) && length(blocks)) {
    idx <- match(fr$block, blocks)
    if (is.na(idx)) {
      stop("别名解析出的 block '", fr$block, "' 不在流水线中", call. = FALSE)
    }
    # 含该步：from = 前一块（run_pipeline 从其后继续）
    from_pipe <- if (idx <= 1L) NULL else blocks[[idx - 1L]]
  }

  list(
    from = from_pipe,
    to = to$block,
    want_sensitivity = isTRUE(to$sensitivity)
  )
}

#' 续跑时定位 by_index 下已有目录（【success】ix / 裸名 / 【failed】）
incidence_batch_find_index_output_dir <- function(output_base, ix, index_subdir = "by_index",
                                                  config = NULL, ix_bare = NULL) {
  # code 包 / 定向重跑：指定独立输出根，不覆盖【success】主结果
  .rerun_out <- Sys.getenv("MEDICAL_BLOCKS_RERUN_OUT", unset = "")
  if (nzchar(.rerun_out)) {
    if (!dir.exists(.rerun_out)) {
      dir.create(.rerun_out, recursive = TRUE, showWarnings = FALSE)
    }
    return(normalizePath(.rerun_out, winslash = "/", mustWork = FALSE))
  }
  ix_bare <- as.character(if (!is.null(ix_bare)) ix_bare else ix)[1L]
  ix_lab <- as.character(ix)[1L]
  if (!is.null(config) && exists("incidence_batch_index_dir_label", mode = "function")) {
    ix_lab <- incidence_batch_index_dir_label(ix_bare, config)
  }
  use_labeled_only <- nzchar(ix_lab) && !identical(ix_lab, ix_bare)
  name_variants <- if (isTRUE(use_labeled_only)) ix_lab else unique(c(ix_lab, ix_bare))
  cands <- unlist(lapply(name_variants, function(nm) {
    c(
      file.path(output_base, index_subdir, paste0("【success】", nm)),
      file.path(output_base, index_subdir, nm),
      file.path(output_base, index_subdir, paste0("【failed】", nm)),
      file.path(output_base, index_subdir, paste0("【failed】 ", nm))
    )
  }), use.names = FALSE)
  for (d in cands) if (dir.exists(d)) return(d)
  # 回退：新建带标签目录
  bare <- file.path(output_base, index_subdir, ix_lab)
  if (!dir.exists(bare)) dir.create(bare, recursive = TRUE)
  bare
}

incidence_batch_dispatch_workers <- function(root, config, index_vars,
                                              workers      = 4L,
                                              log_dir      = NULL,
                                              db_mode      = "both",
                                              only         = NULL,
                                              skip_existing = TRUE,
                                              p_trim       = 0.01,
                                              config_path  = NULL,   # 外部 config 路径，透传给 worker
                                              worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
                                              rscript_bin  = NULL,
                                              from_token   = NULL,
                                              to_token     = NULL) {
  bc          <- config$incidence_batch %||% config$ml_batch %||% list()
  output_base <- bc$output_base %||% config$project$output_dir
  ix_subdir   <- incidence_batch_index_output_subdir(bc)
  workers     <- as.integer(workers)
  warn_sec    <- as.numeric(bc$worker_warn_sec %||% 3600)
  wait_sec    <- as.numeric(bc$worker_wait_sec %||% 7200)

  if (!is.null(only) && length(only))
    index_vars <- index_vars[index_vars %in% only]

  if (is.null(log_dir))
    log_dir <- file.path(output_base, "logs")
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  worker_path <- file.path(root, worker_script)
  if (!file.exists(worker_path))
    stop("Worker 脚本不存在: ", worker_path, call. = FALSE)

  # ── 环境检测 ─────────────────────────────────────────────────────────────
  # 路径转换使用模块顶层 .batch_win_to_wsl / .batch_wsl_to_win

  is_windows_r <- .Platform$OS.type == "windows"
  # wait=FALSE 的 system2 在 Unix 上会走 shell，路径含空格时参数会被截断；优先 processx
  use_processx <- is_windows_r || requireNamespace("processx", quietly = TRUE)

  rscript_bin <- if (!is.null(rscript_bin) && nzchar(as.character(rscript_bin)[1L])) {
    as.character(rscript_bin)[1L]
  } else {
    file.path(R.home("bin"), if (is_windows_r) "Rscript.exe" else "Rscript")
  }

  mode_label <- if (use_processx) "processx"
                else "Linux system2 后台（路径勿含空格）"
  cli::cli_alert_info("Worker 启动模式: {mode_label}")
  cli::cli_alert_info("Rscript: {.file {normalizePath(rscript_bin, winslash='/', mustWork=FALSE)}}")

  .status_exists_success <- function(ix) {
    p <- incidence_batch_status_path(output_base, ix, index_subdir = ix_subdir)
    if (!file.exists(p)) return(FALSE)
    st <- tryCatch(jsonlite::fromJSON(p), error = function(e) NULL)
    identical(st$status, "success")
  }

  .worker_child_env <- function(config_path, root) {
    cfg <- normalizePath(as.character(config_path), winslash = "/", mustWork = FALSE)
    # 必须透传引擎根目录；否则 worker 会回退读 engine.env 里的 Windows 盘符路径，
    # 在 Linux/WSL R 下变成 E:/... 找不到。
    engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(engine_root)) {
      engine_root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    }
    # Windows 盘符 → WSL 挂载点（仅当当前本就是 Unix R 时）
    if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", engine_root)) {
      drive <- tolower(substr(engine_root, 1L, 1L))
      engine_root <- paste0("/mnt/", drive, substring(engine_root, 3L))
    }
    # 透传 TabPFN/HF 离线开关（研究 config 里 Sys.setenv 后父进程可见；worker 环境被替换时需显式带上）
    .pass_env <- function(keys) {
      vals <- vapply(keys, function(k) Sys.getenv(k, unset = ""), character(1))
      vals[nzchar(vals)]
    }
    # Windows worker: System32 在前 + Anaconda（无 condabin/usr/bin/mingw）。
    # 严禁 rtools/cygwin/Anaconda Library/usr/bin（MSYS sh 会把 C:/ 收成 /c/ → "'/c' not found"）
    .worker_path <- {
      if (.Platform$OS.type == "windows") {
        sysroot <- Sys.getenv("SystemRoot", unset = "C:\\Windows")
        paste(
          file.path(sysroot, "System32", fsep = "\\"),
          sysroot,
          file.path(sysroot, "System32", "WindowsPowerShell", "v1.0", fsep = "\\"),
          file.path(sysroot, "System32", "Wbem", fsep = "\\"),
          "C:\\ProgramData\\anaconda3",
          "C:\\ProgramData\\anaconda3\\Scripts",
          "C:\\ProgramData\\anaconda3\\Library\\bin",
          sep = ";"
        )
      } else {
        p <- Sys.getenv("PATH", unset = "/usr/bin:/bin")
        if (!nzchar(p)) p <- "/usr/bin:/bin"
        p
      }
    }
    .worker_home <- if (.Platform$OS.type == "windows") {
      Sys.getenv("USERPROFILE", unset = Sys.getenv("HOME", unset = "C:/Users/Administrator"))
    } else {
      Sys.getenv("HOME", unset = "/root")
    }
    # TabPFN 权重在 %APPDATA%/tabpfn；缺 APPDATA 会落到项目目录并尝试 HF 下载
    .worker_appdata <- {
      a <- Sys.getenv("APPDATA", unset = "")
      if (nzchar(a)) a else file.path(.worker_home, "AppData", "Roaming", fsep = "\\")
    }
    .worker_localappdata <- {
      a <- Sys.getenv("LOCALAPPDATA", unset = "")
      if (nzchar(a)) a else file.path(.worker_home, "AppData", "Local", fsep = "\\")
    }
    .sysroot <- if (.Platform$OS.type == "windows") {
      Sys.getenv("SystemRoot", unset = "C:\\Windows")
    } else {
      ""
    }
    .worker_temp <- {
      t <- Sys.getenv("TEMP", unset = Sys.getenv("TMP", unset = ""))
      if (nzchar(t)) t else file.path(.worker_home, "AppData", "Local", "Temp", fsep = "\\")
    }
    c(
      # System32 必须靠前：保证 cmd.exe 优先于任何 MSYS sh，避免 "'/c' not found"
      PATH   = .worker_path,
      HOME   = .worker_home,
      USERPROFILE = if (.Platform$OS.type == "windows") .worker_home else Sys.getenv("USERPROFILE", ""),
      USERNAME = if (.Platform$OS.type == "windows") {
        u <- Sys.getenv("USERNAME", unset = "")
        if (nzchar(u)) u else basename(.worker_home)
      } else {
        Sys.getenv("USER", unset = "root")
      },
      APPDATA = if (.Platform$OS.type == "windows") .worker_appdata else Sys.getenv("APPDATA", ""),
      LOCALAPPDATA = if (.Platform$OS.type == "windows") .worker_localappdata else Sys.getenv("LOCALAPPDATA", ""),
      # processx 替换整份环境时若缺 COMSPEC，R system() 会误用 sh 并把 cmd 的 /c 收成 "'/c' not found"
      COMSPEC = if (.Platform$OS.type == "windows") {
        file.path(.sysroot, "System32", "cmd.exe", fsep = "\\")
      } else {
        Sys.getenv("COMSPEC", "")
      },
      ComSpec = if (.Platform$OS.type == "windows") {
        file.path(.sysroot, "System32", "cmd.exe", fsep = "\\")
      } else {
        Sys.getenv("ComSpec", "")
      },
      SystemRoot = .sysroot,
      windir = .sysroot,
      TEMP = .worker_temp,
      TMP = .worker_temp,
      TMPDIR = .worker_temp,
      PATHEXT = Sys.getenv("PATHEXT", unset = ".COM;.EXE;.BAT;.CMD;.VBS;.JS;.WS;.MSC"),
      R_HOME = Sys.getenv("R_HOME", R.home()),
      LANG   = Sys.getenv("LANG", "C.UTF-8"),
      MEDICAL_BLOCKS_ROOT = engine_root,
      # 研究根：优先父进程 INCIDENCE_BATCH_ROOT / config output_base，禁止回落引擎 root
      INCIDENCE_BATCH_ROOT = {
        study <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
        if (!nzchar(study) || !dir.exists(study)) {
          study <- as.character(output_base %||% "")[1L]
        }
        if (!nzchar(study) || !dir.exists(study)) {
          study <- as.character(root)[1L]
        }
        if (!nzchar(study)) stop("INCIDENCE_BATCH_ROOT / output_base 未设置", call. = FALSE)
        normalizePath(study, winslash = "/", mustWork = FALSE)
      },
      INCIDENCE_BATCH_CONFIG = cfg,
      STUDY_CONFIG_DIR = dirname(cfg),
      .pass_env(c(
        "HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE", "HF_DATASETS_OFFLINE",
        "TABPFN_TOKEN", "TABPFN_API_KEY", "TABPFN_TOKEN_FILE",
        "TABPFN_ALLOW_CPU_LARGE_DATASET",
        "RETICULATE_PYTHON", "KMP_DUPLICATE_LIB_OK"
      ))
    )
  }

  .status_is_fresh <- function(sp, started_at) {
    if (!file.exists(sp)) return(FALSE)
    info <- file.info(sp)
    mtime <- info$mtime
    if (is.null(mtime) || is.na(mtime[1L])) return(FALSE)
    if (!isTRUE(mtime[1L] >= (as.POSIXct(started_at) - 2))) return(FALSE)
    st <- tryCatch(jsonlite::fromJSON(sp), error = function(e) NULL)
    if (is.null(st)) return(FALSE)
    stt <- tolower(trimws(as.character(st$status %||% "")[1L]))
    stt %in% c("success", "failed", "error")
  }

  .launch_worker <- function(ix) {
    if (skip_existing && .status_exists_success(ix)) {
      cli::cli_alert_info("跳过 {.field {ix}}（已完成）")
      return(NULL)
    }
    log_path <- file.path(log_dir, paste0(ix, ".log"))
    log_abs  <- normalizePath(log_path, winslash = "/", mustWork = FALSE)
    if (!dir.exists(dirname(log_abs))) dir.create(dirname(log_abs), recursive = TRUE)

    # --config 参数：若主进程使用外部 config，worker 继承同一路径
    config_args <- if (!is.null(config_path) && nzchar(as.character(config_path))) {
      c("--config", normalizePath(as.character(config_path), winslash = "/", mustWork = FALSE))
    } else character(0)
    from_to_args <- character(0)
    if (!is.null(from_token) && nzchar(as.character(from_token)[1L])) {
      from_to_args <- c(from_to_args, "--from", as.character(from_token)[1L])
    }
    if (!is.null(to_token) && nzchar(as.character(to_token)[1L])) {
      from_to_args <- c(from_to_args, "--to", as.character(to_token)[1L])
    }

    # 末参与 env 均须为课题 root（output_base），不是引擎 MEDICAL_BLOCKS_ROOT
    .study_root_for_worker <- {
      study <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
      if (!nzchar(study) || !dir.exists(study)) {
        study <- as.character(output_base %||% "")[1L]
      }
      if (!nzchar(study) || !dir.exists(study)) {
        study <- as.character(root)[1L]
      }
      normalizePath(study, winslash = "/", mustWork = TRUE)
    }
    worker_args <- c(
      normalizePath(worker_path, winslash = "/", mustWork = TRUE),
      "--index", ix,
      "--db",    db_mode,
      "--ptrim", as.character(p_trim),
      config_args,
      from_to_args,
      .study_root_for_worker
    )

    px <- NULL
    if (use_processx) {
      # ── Windows R（含 WSL 终端内调用 Rscript.exe）────────────────────────
      # bash/wsl nohup 在此环境下 system() 返回 0 但子进程不落地；processx 可靠。
      if (!requireNamespace("processx", quietly = TRUE))
        stop("Windows 批量派发需要 processx 包: install.packages('processx')", call. = FALSE)
      px <- processx::process$new(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        worker_args,
        stdout = log_abs,
        stderr = log_abs,
        cleanup = FALSE,
        env = .worker_child_env(config_path, .study_root_for_worker)
      )

    } else {
      # ── Linux / WSL（system2 后台，避免 sh -c "... &" 在 dash 下语法错误）──
      system2(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args   = worker_args,
        stdout = log_abs,
        stderr = log_abs,
        wait   = FALSE,
        env    = .worker_child_env(config_path, .study_root_for_worker)
      )
    }

    cli::cli_alert_success("启动 worker [{.field {ix}}] → {.file {basename(log_path)}}")
    list(ix = ix, log = log_path, started_at = Sys.time(), proc = px)
  }

  # worker 已退出但未写出 status（写错目录/崩溃）时，补写 failed 并释放槽位，避免堵死后续指标
  .ensure_status_or_mark_dead <- function(p) {
    sp <- incidence_batch_status_path(output_base, p$ix, index_subdir = ix_subdir, config = config)
    if (.status_is_fresh(sp, p$started_at)) return(TRUE)
    alive <- tryCatch({
      !is.null(p$proc) && isTRUE(p$proc$is_alive())
    }, error = function(e) FALSE)
    if (alive) return(FALSE)
    # 给 SMB 落盘一点时间；仍无 status 则合成
    Sys.sleep(2)
    sp2 <- incidence_batch_status_path(output_base, p$ix, index_subdir = ix_subdir, config = config)
    if (.status_is_fresh(sp2, p$started_at)) return(TRUE)
    out_dir <- file.path(output_base, ix_subdir, p$ix)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    incidence_batch_write_status(out_dir, list(
      index = p$ix,
      status = "failed",
      db_mode = db_mode,
      error_message = "worker exited without status json (slot released by parent)",
      elapsed_sec = round(as.numeric(difftime(Sys.time(), p$started_at, units = "secs")), 1)
    ))
    cli::cli_alert_warning(
      "{p$ix} 进程已退出但无 _batch_status.json，已标记 failed 并释放槽位"
    )
    TRUE
  }

  total  <- length(index_vars)
  done   <- 0L
  active <- list()

  for (ix in index_vars) {
    # 等待空位
    while (length(active) >= workers) {
      Sys.sleep(8)
      still <- list()
      for (p in active) {
        if (.ensure_status_or_mark_dead(p)) {
          done <- done + 1L
          sp   <- incidence_batch_status_path(output_base, p$ix, index_subdir = ix_subdir, config = config)
          st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status="unknown"))
          cli::cli_alert_success("[{done}/{total}] {.field {p$ix}} 完成 (status={st$status})")
          incidence_batch_rename_output_folder(
            output_base, p$ix, st$status %||% "unknown",
            overwrite = !isTRUE(skip_existing),
            index_subdir = ix_subdir,
            config = config
          )
        } else {
          # 超时检测（默认 1h 仅告警；ML 批量可在 config 提高 worker_warn_sec）
          if (as.numeric(difftime(Sys.time(), p$started_at, units = "secs")) > warn_sec)
            cli::cli_alert_warning("{p$ix} 已运行 >{round(warn_sec/3600, 1)}h，仍在等待（非强制终止）")
          still[[length(still)+1]] <- p
        }
      }
      active <- still
    }
    proc <- .launch_worker(ix)
    if (!is.null(proc)) active[[length(active)+1]] <- proc
  }

  # 等待最后一批
  cli::cli_alert_info("等待最后 {length(active)} 个 worker…")
  t0 <- Sys.time()
  while (length(active) > 0 &&
         as.numeric(difftime(Sys.time(), t0, units = "secs")) < wait_sec) {
    Sys.sleep(15)
    still <- list()
    for (p in active) {
      if (.ensure_status_or_mark_dead(p)) {
        done <- done + 1L
        sp   <- incidence_batch_status_path(output_base, p$ix, index_subdir = ix_subdir, config = config)
        st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status="unknown"))
        cli::cli_alert_success("[{done}/{total}] {.field {p$ix}} 完成 (status={st$status})")
        incidence_batch_rename_output_folder(
          output_base, p$ix, st$status %||% "unknown",
          overwrite = !isTRUE(skip_existing),
          index_subdir = ix_subdir,
          config = config
        )
      } else {
        still[[length(still)+1]] <- p
      }
    }
    active <- still
  }
  if (length(active) > 0) {
    timed_out <- paste(sapply(active, `[[`, "ix"), collapse = ", ")
    cli::cli_alert_warning("以下指标超时未完成: {timed_out}")
  }
  invisible(done)
}

# ── 14. 汇总所有指标状态 ─────────────────────────────────────────────────────
incidence_batch_read_all_status <- function(output_base, index_vars, index_subdir = "by_index") {
  # JSON 中 null 或 {} 空对象 → NA；list 或向量取第一个元素
  .sc <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0) return(default)
    as.character(x[[1L]])
  }
  .sn <- function(x, default = NA_real_) {
    if (is.null(x) || length(x) == 0) return(default)
    suppressWarnings(as.numeric(x[[1L]]))
  }

  rows <- lapply(index_vars, function(ix) {
    path <- incidence_batch_status_path(output_base, ix, index_subdir = index_subdir)
    if (!file.exists(path)) {
      return(data.frame(
        index=ix, status="not_run", db_mode=NA_character_,
        nhanes_branch=NA_character_, mimic_branch=NA_character_,
        nhanes_or=NA_real_, mimic_or=NA_real_,
        n_nhanes_before=NA_real_, n_nhanes_after=NA_real_,
        n_mimic_before=NA_real_,  n_mimic_after=NA_real_,
        nhanes_auc=NA_real_, mimic_auc=NA_real_,
        error_message=NA_character_, elapsed_sec=NA_real_,
        finished_at=NA_character_, stringsAsFactors=FALSE
      ))
    }
    st <- tryCatch(jsonlite::fromJSON(path), error = function(e) list(index=ix, status="parse_error"))
    data.frame(
      index           = ix,
      status          = .sc(st$status),
      db_mode         = .sc(st$db_mode),
      nhanes_branch   = .sc(st$nhanes_branch),
      mimic_branch    = .sc(st$mimic_branch),
      nhanes_or       = .sn(st$nhanes_or),
      mimic_or        = .sn(st$mimic_or),
      n_nhanes_before = .sn(st$n_nhanes_before),
      n_nhanes_after  = .sn(st$n_nhanes_after),
      n_mimic_before  = .sn(st$n_mimic_before),
      n_mimic_after   = .sn(st$n_mimic_after),
      nhanes_auc      = .sn(st$nhanes_auc),
      mimic_auc       = .sn(st$mimic_auc),
      error_message   = .sc(st$error_message),
      elapsed_sec     = .sn(st$elapsed_sec),
      finished_at     = .sc(st$finished_at),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# ── 15. 打印批量汇总 ──────────────────────────────────────────────────────────
incidence_batch_print_summary <- function(statuses) {
  if (is.null(statuses) || !nrow(statuses)) {
    cli::cli_alert_warning("无状态记录。"); return(invisible(NULL))
  }
  n <- nrow(statuses)
  cli::cli_h2("Batch 汇总（共 {n} 个指标）")
  cli::cli_alert_success("成功: {sum(statuses$status == 'success', na.rm=TRUE)}")
  cli::cli_alert_info(
    "仅 NHANES: {sum(statuses$db_mode == 'nhanes_only', na.rm=TRUE)}")
  cli::cli_alert_info(
    "未运行: {sum(statuses$status %in% c('not_run', NA), na.rm=TRUE)}")
  cli::cli_alert_danger(
    "失败: {sum(statuses$status %in% c('error','failed'), na.rm=TRUE)}")
  invisible(statuses)
}

# ── 16. 主函数 ────────────────────────────────────────────────────────────────
run_incidence_dual_batch <- function(root, config,
                                      pipeline_nhanes_batch,
                                      pipeline_regular_batch,
                                      pipeline_shared_nhanes,
                                      pipeline_shared_regular,
                                      run_opts = list(),
                                      config_path = NULL) {  # 外部 config 路径，透传给 worker
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  bc   <- config$incidence_batch %||% list()

  shared_only    <- isTRUE(run_opts$shared_only)
  only_index     <- run_opts$only_index %||% NULL
  # workers = NULL / "auto" → 指标列表确定后自动推算；数字 → 直接使用
  # workers 解析：命令行 > config > 默认 auto
  # NULL 或 "auto" → 指标确定后自动推算；数字 → 直接用
  workers_raw   <- run_opts$workers %||% bc$parallel_workers  # 两者都 NULL 则为 NULL
  auto_workers  <- is.null(workers_raw) ||
                   identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers       <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_
  db_mode        <- run_opts$db_mode       %||% bc$db_mode      %||% "both"
  skip_exist   <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)
  p_trim       <- as.numeric(run_opts$p_trim     %||% bc$trim_quantile %||% 0.01)
  from_token   <- run_opts$from %||% NULL
  to_token     <- run_opts$to   %||% NULL
  if ((!is.null(from_token) && nzchar(as.character(from_token)[1L])) ||
      (!is.null(to_token) && nzchar(as.character(to_token)[1L]))) {
    # 局部续跑必须强制重跑，否则 success 指标会被跳过
    skip_exist <- FALSE
    cli::cli_alert_info(
      "续跑范围: from={from_token %||% '(start)'} → to={to_token %||% '(end)'}"
    )
  }
  want_sensitivity_after <- incidence_batch_is_sensitivity_token(to_token)
  worker_to_token <- to_token
  if (want_sensitivity_after) {
    # sensitivity 不是 pipeline block：主段停在 --from 的阶段别名（含该步），再跑 SA
    # 例：--from mediation --to sensitivity → 只重跑中介，再敏感性
    alias_names <- names(incidence_batch_stage_alias_map())
    fr <- tolower(trimws(as.character(from_token %||% "")[1L]))
    worker_to_token <- if (nzchar(fr) && fr %in% alias_names) fr else NULL
  }

  # 候选指标（全量，后续从 checkpoint 缩小）
  candidate_vars <- incidence_batch_resolve_index_vars(config)
  cli::cli_h1("Incidence Dual Batch — 候选 {length(candidate_vars)} 个指标")
  cli::cli_alert_info("db_mode={db_mode}, workers={workers}, skip_existing={skip_exist}, trim={p_trim*100}%")

  db_seq <- switch(db_mode, nhanes = "nhanes", mimic = "mimic", c("nhanes","mimic"))

  # ── Gate A：column_mapping 后列名交集（gate_a_missing_threshold，默认 1.0）──
  #  高缺失基础列保留在 harmonize；per-index imputation 再按 0.4 删差协变量。
  #  结果写入 harmonization_dir/gate_a_columns.rds，供 worker 亚组/列对齐复用。
  # 单库 --db mimic 也要注入 Gate A keep；否则 shared harmonize 可能只剩结局列
  if (isTRUE(config$dual_db$enable)) {
    config <- tryCatch(
      incidence_batch_ensure_gate_a(config, root, force = !skip_exist)$config,
      error = function(e) {
        cli::cli_alert_warning("后清洗 Gate A 失败: {e$message}，shared 层将跳过列限制")
        config
      }
    )
  }

  # ── 共享层 ──
  for (db in db_seq) {
    shared_read  <- incidence_batch_shared_ck_dir(config, db)
    shared_write <- incidence_batch_shared_ck_canonical_dir(config, db)
    pl_shared    <- if (dual_db_is_weighted(config, db)) pipeline_shared_nhanes else pipeline_shared_regular
    alias_path   <- file.path(shared_read, "index.rds")

    if (file.exists(alias_path) && isTRUE(skip_exist)) {
      db_lbl <- dual_db_slot_path_name(config, db)
      cli::cli_alert_info("共享层 [{db_lbl}] 已存在，跳过")
    } else {
      cli::cli_h2("运行共享层 [{dual_db_slot_path_name(config, db)}]")
      incidence_batch_run_shared_layer(root, config, db, pl_shared, shared_write)
    }
  }

  if (shared_only) {
    # 即使 shared-only 也输出实际可用指标数，方便用户确认
    avail <- tryCatch(
      incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
      error = function(e) { cli::cli_alert_warning(e$message); candidate_vars }
    )
    cli::cli_alert_success("--shared-only 完成，实际可用指标: {length(avail)} 个")
    return(invisible(avail))
  }

  # ── 验证共享检查点 ──
  for (db in db_seq) {
    p <- file.path(incidence_batch_shared_ck_dir(config, db), "index.rds")
    # 兼容 Windows R 下的路径格式
    if (!file.exists(p)) p <- .batch_wsl_to_win(p)
    if (!file.exists(p))
      stop("共享层检查点缺失: ", p,
           "\n请先运行 --shared-only 或检查共享层是否完成", call. = FALSE)
  }

  # ── 从共享检查点读取实际可用指标（缩小候选列表）──
  cli::cli_h2("从共享层 checkpoint 筛查实际可用指标")
  index_vars <- tryCatch(
    incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
    error = function(e) {
      cli::cli_alert_warning("读取 checkpoint 失败: {e$message}，使用候选全量")
      candidate_vars
    }
  )
  index_vars <- incidence_batch_filter_disease_derived_indices(config, index_vars)
  cli::cli_alert_success("最终批量指标: {length(index_vars)} 个")

  # ── 自动推算 / 确认并行路数（在指标数确定后）──
  effective_n <- if (!is.null(only_index)) length(intersect(index_vars, only_index))
                 else length(index_vars)
  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = bc$ram_per_worker_gb  %||% 2.0,
      cpu_headroom    = bc$cpu_headroom       %||% 2L,
      ram_headroom_gb = bc$ram_headroom_gb    %||% 4.0,
      max_workers     = bc$max_workers        %||% NULL
    )
  } else {
    cli::cli_alert_info(
      "Worker 数: {workers}（手动指定）| 指标数: {effective_n} | CPU: {parallel::detectCores(logical=TRUE)}"
    )
  }

  # ── 派发 Worker ──
  # log_dir：config$incidence_batch$log_dir 优先（便于 by_index(人) / logs(人) 目录隔离）
  .batch_log_dir <- {
    custom <- as.character(bc$log_dir %||% "")[1L]
    if (nzchar(custom)) custom else file.path(bc$output_base %||% config$project$output_dir, "logs")
  }
  incidence_batch_dispatch_workers(
    root          = root,
    config        = config,
    index_vars    = index_vars,
    workers       = workers,
    log_dir       = .batch_log_dir,
    db_mode       = db_mode,
    only          = only_index,
    skip_existing = skip_exist,
    p_trim        = p_trim,
    config_path   = config_path,
    from_token    = from_token,
    to_token      = worker_to_token
  )

  # ── 汇总 ──
  output_base <- bc$output_base %||% config$project$output_dir
  ix_subdir   <- incidence_batch_index_output_subdir(bc)
  statuses    <- incidence_batch_read_all_status(
    output_base, index_vars, index_subdir = ix_subdir
  )
  incidence_batch_print_summary(statuses)

  # Tables(cindychen) 等：config$incidence_batch$tables_subdir 优先
  .tables_name <- as.character(bc$tables_subdir %||% "Tables")[1L]
  if (!nzchar(.tables_name)) .tables_name <- "Tables"
  out_dir  <- file.path(output_base, .tables_name)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_indices.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")

  fs <- config$feishu %||% list()
  if (isTRUE(fs$push_on_batch_summary)) {
    # 更新 Sheet 1 汇总行
    if (exists("incidence_batch_feishu_update_summary", mode = "function")) {
      tryCatch(
        incidence_batch_feishu_update_summary(config, statuses),
        error = function(e) cli::cli_alert_warning("飞书汇总行更新失败: {e$message}")
      )
    }
  }

  # ── 亚组补救重跑（失败指标按亚组剔除人群后重跑整个发病流程）──────────────────
  #  仅对主批量流程产出的 failed/error 指标触发；由 config$incidence_batch$
  #  subgroup_fallback$enable 控制。详见 R/incidence_subgroup_fallback.R
  if (!shared_only) {
    sgfb <- (config$incidence_batch %||% list())$subgroup_fallback %||% list()
    if (isTRUE(sgfb$enable) && exists("incidence_subgroup_fallback_pass", mode = "function")) {
      failed_ix <- as.character(statuses$index[statuses$status %in% c("error", "failed")])
      failed_ix <- failed_ix[nzchar(failed_ix)]
      if (length(failed_ix)) {
        tryCatch(
          incidence_subgroup_fallback_pass(root, config, failed_ix, config_path),
          error = function(e) cli::cli_alert_warning("亚组补救阶段出错: {e$message}")
        )
      }
    }
  }

  # ── 敏感性分析（success 指标按场景过滤队列后重跑）──────────────────────────
  #  默认开启（缺省 enable → TRUE）；显式 FALSE 关闭；
  #  或命令行 --to sensitivity 显式要求（续跑尾段后跟敏感性）。
  #  详见 R/incidence_sensitivity_suite.R
  if (!shared_only) {
    run_sens <- isTRUE(want_sensitivity_after) ||
      (exists("incidence_sensitivity_suite_enabled", mode = "function") &&
         incidence_sensitivity_suite_enabled(config)) ||
      isTRUE(((config$incidence_batch %||% list())$sensitivity_suite %||% list())$enable)
    if (run_sens && exists("incidence_sensitivity_pass", mode = "function")) {
      success_ix <- as.character(statuses$index[statuses$status == "success"])
      success_ix <- success_ix[nzchar(success_ix)]
      if (!is.null(only_index) && length(only_index))
        success_ix <- intersect(success_ix, only_index)
      if (length(success_ix)) {
        tryCatch(
          incidence_sensitivity_pass(
            root, config, success_ix, config_path,
            force = !skip_exist
          ),
          error = function(e) cli::cli_alert_warning("敏感性分析阶段出错: {e$message}")
        )
      }
    }
  }

  invisible(statuses)
}
