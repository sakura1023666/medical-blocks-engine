###############################################################################
#  trajectory_28d_index_utils.R — 28 天纵向复合指标计算工具
#
#  流程：
#    1. 合并实验室 CSV（eICU 多分片 / MIMIC 单文件）
#    2. 映射 lab{d}_labxxx → 标准变量 Var_{d}
#    3. calc_28d_index() 按指标公式逐日计算
#    4. save_28d_index() 筛选 ≥2 天非空后保存 12_{Index}.RData
###############################################################################

# ── 指标公式：从 Blocks/00_index/01block_index.R 动态加载（与发病 batch 一致）────
trajectory_28d_load_index_definitions <- function(root = getwd()) {
  if (!exists(".idx_definitions", mode = "function", inherits = TRUE)) {
    idx_path <- file.path(root, "Blocks/00_index/01block_index.R")
    if (!file.exists(idx_path)) stop("找不到 index block: ", idx_path, call. = FALSE)
    source(idx_path, local = FALSE)
  }
  .idx_definitions()
}

# eICU / MIMIC 原始实验室列后缀（不含 lab{d}_ 前缀与 _uom 后缀）
.trajectory_28d_lab_suffix_map <- function() {
  list(
    Platelet_Count   = c("labplateletcount"),
    Albumin          = c("labalbumin"),
    AST              = c("labast"),
    ALT              = c("labalt"),
    Creatinine       = c("labcreatinine"),
    BUN              = c("labbun", "labureanitrogen"),
    LD               = c("labld", "labldh"),
    WBC              = c("labwbc"),
    Polys            = c("labpolys"),
    Lymphocytes_pct  = c("lablymphocytes"),
    Neutrophil_Count = c("labneutrophilcount"),
    Glucose          = c("labbedglucose", "labglucose"),
    HDL              = c("labhdl"),
    LDL              = c("labldl"),
    Total_Cholesterol = c("labtc", "labcholesteroltotal"),
    Triglycerides    = c("labtg", "labtriglycerides"),
    Potassium        = c("labpotassium"),
    RDW              = c("labrdw"),
    Hemoglobin       = c("labhgb", "labhemoglobin"),
    RBC              = c("labrbc"),
    Hematocrit       = c("labhct", "labhematocrit"),
    TotalProtein     = c("labtotalprotein"),
    Bilirubin_Total  = c("labtotalbilirubin"),
    Uric_Acid        = c("laburicacid"),
    Fibrinogen       = c("labfibrinogen"),
    Sodium           = c("labsodium"),
    eGFR             = c("labegfr", "labegfr_ckdepi"),
    AnionGap         = c("labaniongap"),
    HbA1c            = c("laba1c"),
    Lactate          = c("lablactate"),
    INR              = c("labinr"),
    MCH              = c("labmch"),
    MCV              = c("labmcv"),
    MCHC             = c("labmchc")
  )
}

.trajectory_28d_resolve_path <- function(p, root = getwd()) {
  if (is.null(p) || !nzchar(p)) return(p)
  if (grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", p)) normalizePath(p, winslash = "/", mustWork = FALSE) else
    file.path(root, p)
}

# eICU 长表 item → lab{d}_* 后缀（与 MIMIC 宽表列名对齐）
.trajectory_28d_eicu_long_item_map <- function() {
  c(
    "WBC x 1000" = "labwbc",
    "RBC" = "labrbc",
    "-polys" = "labpolys",
    "-lymphs" = "lablymphocytes",
    "platelets x 1000" = "labplateletcount",
    "Hgb" = "labhgb",
    "RDW" = "labrdw",
    "Hct" = "labhct",
    "MCH" = "labmch",
    "MCV" = "labmcv",
    "MCHC" = "labmchc",
    "albumin" = "labalbumin",
    "total protein" = "labtotalprotein",
    "sodium" = "labsodium",
    "potassium" = "labpotassium",
    "glucose" = "labglucose",
    "bedside glucose" = "labbedglucose",
    "creatinine" = "labcreatinine",
    "BUN" = "labbun",
    "AST (SGOT)" = "labast",
    "ALT (SGPT)" = "labalt",
    "total bilirubin" = "labtotalbilirubin",
    "triglycerides" = "labtg",
    "HDL" = "labhdl",
    "LDL" = "labldl",
    "total cholesterol" = "labtc",
    "anion gap" = "labaniongap",
    "uric acid" = "laburicacid",
    "fibrinogen" = "labfibrinogen",
    "lactate" = "lablactate",
    "LDH" = "labldh",
    "CRP" = "labcrp",
    "PT - INR" = "labinr"
  )
}

.trajectory_28d_is_long_lab <- function(nms) {
  has_long <- all(c("item", "day") %in% nms) &&
    any(c("median", "mean", "value") %in% nms)
  has_wide <- any(grepl("^lab[0-9]+_", nms))
  isTRUE(has_long) && !isTRUE(has_wide)
}

.trajectory_28d_long_to_wide <- function(long_dt, id_col, days = NULL,
                                         value_prefer = c("median", "mean", "value")) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("eICU 长表 pivot 需要 data.table", call. = FALSE)
  data.table::setDT(long_dt)
  imap <- .trajectory_28d_eicu_long_item_map()
  want <- names(imap)
  long_dt[[id_col]] <- as.character(long_dt[[id_col]])
  long_dt <- long_dt[long_dt$item %in% want]
  if (!nrow(long_dt)) stop("eICU 长表过滤 item 后为空（无匹配映射）", call. = FALSE)
  long_dt$day <- suppressWarnings(as.integer(long_dt$day))
  long_dt <- long_dt[is.finite(long_dt$day) & long_dt$day >= 1L]
  if (!is.null(days) && length(days)) {
    days <- as.integer(days)
    long_dt <- long_dt[long_dt$day %in% days]
  }
  if (!nrow(long_dt)) stop("eICU 长表按天后为空", call. = FALSE)

  val_col <- NULL
  for (cand in value_prefer) {
    if (cand %in% names(long_dt)) {
      val_col <- cand
      break
    }
  }
  if (is.null(val_col))
    stop("eICU 长表缺少 median/mean/value 列", call. = FALSE)

  long_dt$sfx <- unname(imap[as.character(long_dt$item)])
  long_dt <- long_dt[!is.na(long_dt$sfx)]
  long_dt$col <- paste0("lab", as.integer(long_dt$day), "_", long_dt$sfx)
  long_dt$val <- suppressWarnings(as.numeric(long_dt[[val_col]]))

  wide <- data.table::dcast(
    long_dt,
    stats::as.formula(paste(id_col, "~ col")),
    value.var = "val",
    fun.aggregate = function(z) {
      z <- z[is.finite(z)]
      if (!length(z)) NA_real_ else as.numeric(stats::median(z))
    }
  )
  cli::cli_alert_success(
    "eICU 长表 → 宽表：{nrow(wide)} 人 × {ncol(wide)} 列（value={val_col}）"
  )
  wide
}

# ── 合并实验室 CSV ────────────────────────────────────────────────────────────
# 支持 MIMIC 宽表（lab{d}_*）与 eICU 长表（item/day/median）自动检测并 pivot。
trajectory_28d_merge_lab_csvs <- function(files, id_col = "subject_id",
                                          restrict_ids = NULL, days = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("trajectory_28d_merge_lab_csvs 需要 data.table 包", call. = FALSE)
  files <- unique(as.character(files))
  files <- files[file.exists(files)]
  if (!length(files)) stop("未找到任何实验室 CSV 文件", call. = FALSE)

  restrict_ids <- if (!is.null(restrict_ids) && length(restrict_ids))
    unique(as.character(restrict_ids)) else NULL

  dt <- NULL
  long_chunks <- list()
  for (f in files) {
    chunk <- data.table::fread(f, showProgress = FALSE)
    if (!id_col %in% names(chunk)) {
      cli::cli_alert_warning("跳过 {basename(f)}：缺少 ID 列 {id_col}")
      next
    }
    chunk[[id_col]] <- as.character(chunk[[id_col]])
    if (!is.null(restrict_ids)) {
      chunk <- chunk[chunk[[id_col]] %in% restrict_ids]
    }
    if (!nrow(chunk)) {
      cli::cli_alert_warning("跳过 {basename(f)}：ID 过滤后为空")
      next
    }

    if (.trajectory_28d_is_long_lab(names(chunk))) {
      cli::cli_alert_info("检测到长表实验室：{basename(f)}（{nrow(chunk)} 行）")
      long_chunks[[length(long_chunks) + 1L]] <- chunk
      next
    }

    # 宽表路径：去掉单位列后按列并入
    uom_cols <- grep("_uom$", names(chunk), value = TRUE)
    if (length(uom_cols)) chunk <- chunk[, !uom_cols, with = FALSE]
    data.table::setDT(chunk)
    if (is.null(dt)) {
      dt <- chunk
    } else {
      new_cols <- setdiff(names(chunk), c(id_col, names(dt)))
      if (length(new_cols)) {
        dt <- merge(dt, chunk[, c(id_col, new_cols), with = FALSE],
                    by = id_col, all = TRUE)
      }
    }
  }

  if (length(long_chunks)) {
    long_all <- data.table::rbindlist(long_chunks, use.names = TRUE, fill = TRUE)
    wide_long <- .trajectory_28d_long_to_wide(long_all, id_col = id_col, days = days)
    if (is.null(dt)) {
      dt <- wide_long
    } else {
      # 同 ID 宽表列合并（极少见：混用长/宽源）
      extra <- setdiff(names(wide_long), names(dt))
      if (length(extra)) {
        dt <- merge(dt, wide_long[, c(id_col, extra), with = FALSE],
                    by = id_col, all = TRUE)
      }
    }
  }

  if (is.null(dt) || !nrow(dt)) stop("实验室 CSV 合并后为空", call. = FALSE)
  if (anyDuplicated(dt[[id_col]])) {
    n_dup <- sum(duplicated(dt[[id_col]]))
    # 长表 pivot 后不应再有重复；宽表残留重复仍保留首行
    cli::cli_alert_warning("实验室宽表 {id_col} 存在重复行 {n_dup} 条，保留首行")
    dt <- dt[!duplicated(dt[[id_col]]), ]
  }
  as.data.frame(dt)
}

# ── 从合并后的宽表提取标准日列 Var_{day} ─────────────────────────────────────
.trajectory_28d_pick_lab_col <- function(dt_names, day, suffixes) {
  for (sfx in suffixes) {
    cand <- paste0("lab", day, "_", sfx)
    if (cand %in% dt_names) return(cand)
  }
  NULL
}

# 与全局 R/hematology_units.R 对齐（Platelet med>50 禁止误 ÷1000）
.trajectory_28d_scale_hematology <- function(x, var_name = NULL) {
  if (!exists("scale_hematology_vector", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    hu <- if (nzchar(root)) file.path(root, "R", "hematology_units.R") else "R/hematology_units.R"
    if (file.exists(hu)) source(hu, local = FALSE)
  }
  if (exists("scale_hematology_vector", mode = "function")) {
    y <- scale_hematology_vector(x, var_name = var_name)
    attr(y, "scaled") <- NULL
    return(y)
  }
  # 兜底：血小板阈 1000，其余 50
  x <- suppressWarnings(as.numeric(x))
  med <- stats::median(x, na.rm = TRUE)
  thr <- if (!is.null(var_name) && grepl("platelet", var_name, ignore.case = TRUE)) 1000 else 50
  if (is.finite(med) && med > thr) x <- x / 1000
  x
}

trajectory_28d_build_daily_components <- function(lab_df, days = 1:28, db_type = c("eicu", "mimic"),
                                                  id_col = "subject_id", lab_id_col = NULL,
                                                  day_sep = "_") {
  db_type <- match.arg(db_type)
  lab_id_col <- lab_id_col %||% id_col
  if (!id_col %in% names(lab_df) && lab_id_col %in% names(lab_df))
    lab_df[[id_col]] <- as.character(lab_df[[lab_id_col]])
  n <- nrow(lab_df)
  if (!n) return(data.frame())

  suffix_map <- .trajectory_28d_lab_suffix_map()
  nms <- names(lab_df)
  out <- data.frame(matrix(nrow = n, ncol = 0), stringsAsFactors = FALSE)
  out[[id_col]] <- as.character(lab_df[[id_col]])

  hema_vars <- c("Neutrophil_Count", "Lymphocytes", "Platelet_Count", "WBC", "RBC")

  direct_vars <- setdiff(names(suffix_map), c("Polys", "Lymphocytes_pct", "Neutrophil_Count"))

  for (day in days) {
    for (std_name in direct_vars) {
      raw <- .trajectory_28d_pick_lab_col(nms, day, suffix_map[[std_name]])
      col_out <- paste0(std_name, day_sep, day)
      out[[col_out]] <- if (!is.null(raw)) suppressWarnings(as.numeric(lab_df[[raw]])) else NA_real_
      if (std_name %in% hema_vars)
        out[[col_out]] <- .trajectory_28d_scale_hematology(out[[col_out]], var_name = std_name)
    }

    wbc_col <- .trajectory_28d_pick_lab_col(nms, day, suffix_map$WBC)
    wbc <- if (!is.null(wbc_col))
      .trajectory_28d_scale_hematology(lab_df[[wbc_col]], var_name = "WBC")
    else rep(NA_real_, nrow(lab_df))

    if (identical(db_type, "mimic")) {
      neut_raw <- .trajectory_28d_pick_lab_col(nms, day, suffix_map$Neutrophil_Count)
      lym_raw  <- .trajectory_28d_pick_lab_col(nms, day, suffix_map$Lymphocytes_pct)
      out[[paste0("Neutrophil_Count", day_sep, day)]] <-
        if (!is.null(neut_raw))
          .trajectory_28d_scale_hematology(lab_df[[neut_raw]], var_name = "Neutrophil_Count")
        else NA_real_
      out[[paste0("Lymphocytes", day_sep, day)]] <-
        if (!is.null(lym_raw))
          .trajectory_28d_scale_hematology(lab_df[[lym_raw]], var_name = "Lymphocytes")
        else NA_real_
    } else {
      pol_raw <- .trajectory_28d_pick_lab_col(nms, day, suffix_map$Polys)
      lym_raw <- .trajectory_28d_pick_lab_col(nms, day, suffix_map$Lymphocytes_pct)
      pol <- if (!is.null(pol_raw)) suppressWarnings(as.numeric(lab_df[[pol_raw]])) else NA_real_
      lym <- if (!is.null(lym_raw)) suppressWarnings(as.numeric(lab_df[[lym_raw]])) else NA_real_
      out[[paste0("Neutrophil_Count", day_sep, day)]] <- pol * wbc / 100
      out[[paste0("Lymphocytes", day_sep, day)]]      <- lym * wbc / 100
    }

    # Globulin = TotalProtein - Albumin（若两列均有）
    tp <- paste0("TotalProtein", day_sep, day)
    alb <- paste0("Albumin", day_sep, day)
    if (tp %in% names(out) && alb %in% names(out))
      out[[paste0("Globulin", day_sep, day)]] <- out[[tp]] - out[[alb]]
  }
  out
}

# 合并基线协变量（Age/BMI/Gender 等）供含人口学/合并症的指标公式使用
trajectory_28d_merge_baseline <- function(comp_df, baseline_df, id_col = "subject_id") {
  if (is.null(baseline_df) || !nrow(baseline_df) || !id_col %in% names(baseline_df)) return(comp_df)
  baseline_df <- as.data.frame(baseline_df)
  day_cols <- grep("_[0-9]+$", names(comp_df), value = TRUE)
  day_prefixes <- unique(sub("_[0-9]+$", "", day_cols))
  keep <- setdiff(names(baseline_df), c(day_prefixes, paste0(day_prefixes, "_1")))
  keep <- unique(c(id_col, keep))
  keep <- intersect(keep, names(baseline_df))
  bsub <- baseline_df[, keep, drop = FALSE]
  bsub[[id_col]] <- as.character(bsub[[id_col]])
  comp_df[[id_col]] <- as.character(comp_df[[id_col]])
  merge(comp_df, bsub, by = id_col, all.y = TRUE, suffixes = c("", ".base"))
}

# ── 函数1：计算单指标的 28 天值（用户原始逻辑）────────────────────────────────
calc_28d_index <- function(calc_data, index_name, formula_func) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("calc_28d_index 需要 data.table 包", call. = FALSE)
  calc_data <- data.table::as.data.table(calc_data)
  for (day in 1:28) {
    col_name <- paste0(index_name, "_", day)
    calc_data[[col_name]] <- formula_func(day, calc_data)
    vals <- calc_data[[col_name]]
    vals[!is.finite(vals)] <- NA_real_
    calc_data[[col_name]] <- vals
  }
  as.data.frame(calc_data)
}

# 从基线表提取 ID 集合（实验室过滤用 lab_id_col，保存宽表用 id_col）
trajectory_28d_baseline_id_sets <- function(baseline_df, id_col = "subject_id", lab_id_col = NULL) {
  empty <- list(baseline_ids = character(0), lab_ids = character(0))
  if (is.null(baseline_df) || !nrow(baseline_df)) return(empty)
  baseline_df <- as.data.frame(baseline_df)
  lab_id_col <- lab_id_col %||% id_col
  baseline_ids <- if (id_col %in% names(baseline_df)) {
    unique(as.character(baseline_df[[id_col]]))
  } else character(0)
  baseline_ids <- baseline_ids[nzchar(baseline_ids)]
  lab_ids <- if (lab_id_col %in% names(baseline_df)) {
    unique(as.character(baseline_df[[lab_id_col]]))
  } else baseline_ids
  lab_ids <- lab_ids[nzchar(lab_ids)]
  list(baseline_ids = baseline_ids, lab_ids = lab_ids)
}

# ── 函数2：提取指标并保存为 RData（用户原始逻辑，增强输出路径）────────────────
save_28d_index <- function(calc_data, index_name, out_path = NULL, id_col = "subject_id",
                           min_non_na_days = 2L, rdata_obj = "index_df",
                           baseline_ids = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("save_28d_index 需要 data.table 包", call. = FALSE)
  calc_data <- data.table::as.data.table(calc_data)
  cols <- c(id_col, paste0(index_name, "_", 1:28))
  existing_cols <- intersect(cols, names(calc_data))
  index_df <- calc_data[, ..existing_cols]
  day_cols <- grep(paste0("^", index_name, "_"), names(index_df), value = TRUE)
  non_na_count <- rowSums(!is.na(as.matrix(index_df[, ..day_cols])))
  index_df <- index_df[non_na_count >= min_non_na_days]
  index_df[[id_col]] <- as.character(index_df[[id_col]])

  if (!is.null(baseline_ids) && length(baseline_ids)) {
    baseline_ids <- unique(as.character(baseline_ids))
    n_before <- nrow(index_df)
    index_df <- index_df[index_df[[id_col]] %in% baseline_ids]
    n_drop <- n_before - nrow(index_df)
    if (n_drop > 0L) {
      cli::cli_alert_info(
        "{index_name}: 与基线对齐，剔除无基线 {id_col} 的纵向行 {n_drop} 条（保留 {nrow(index_df)}）"
      )
    }
  }

  if (is.null(out_path) || !nzchar(out_path)) out_path <- paste0("12_", index_name, ".RData")
  out_dir <- dirname(out_path)
  if (nzchar(out_dir) && !dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  assign(rdata_obj, as.data.frame(index_df), envir = environment())
  save(list = rdata_obj, file = out_path)
  cli::cli_alert_success("{index_name} 已保存 {.file {basename(out_path)}}，样本量 {nrow(index_df)}")
  invisible(list(path = out_path, n = nrow(index_df), data = as.data.frame(index_df)))
}

# ── 由指标表达式构建 formula_func（日列优先，回退基线列）────────────────────
trajectory_28d_make_formula_func <- function(expr, day_sep = "_") {
  reserved <- c(
    "ifelse", "dplyr", "case_when", "TRUE", "FALSE", "NA", "NA_real_",
    "log", "log10", "log2", "sqrt", "abs", "exp", "pi"
  )
  function(day, calc_data) {
    n <- nrow(calc_data)
    tokens <- unique(regmatches(expr, gregexpr("[A-Za-z][A-Za-z0-9_]*", expr, perl = TRUE))[[1]])
    tokens <- setdiff(tokens, reserved)
    sub <- data.frame(matrix(NA_real_, nrow = n, ncol = 0), stringsAsFactors = FALSE)
    for (v in tokens) {
      dcol <- paste0(v, day_sep, day)
      if (dcol %in% names(calc_data)) {
        sub[[v]] <- calc_data[[dcol]]
      } else if (v %in% names(calc_data)) {
        val <- calc_data[[v]]
        if (is.factor(val)) val <- as.character(val)
        sub[[v]] <- val
      } else {
        sub[[v]] <- rep(NA_real_, n)
      }
    }
    tryCatch(
      as.numeric(with(sub, eval(parse(text = expr)))),
      error = function(e) rep(NA_real_, n)
    )
  }
}

# ── 一站式：合并实验室 → 计算全部指标 → 保存 ─────────────────────────────────
trajectory_28d_compute_all <- function(lab_sources, index_vars, output_dir,
                                         id_col = "subject_id", lab_id_col = NULL,
                                         db_type = c("eicu", "mimic"), days = 1:28,
                                         min_non_na_days = 2L, rdata_obj = "index_df",
                                         restrict_ids = NULL, baseline_df = NULL,
                                         root = getwd()) {
  db_type <- match.arg(db_type)
  lab_id_col <- lab_id_col %||% id_col
  output_dir <- .trajectory_28d_resolve_path(output_dir, root)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  files <- if (is.list(lab_sources) && !is.null(lab_sources$files)) {
    vapply(lab_sources$files, .trajectory_28d_resolve_path, character(1L), root = root)
  } else if (is.character(lab_sources)) {
    vapply(lab_sources, .trajectory_28d_resolve_path, character(1L), root = root)
  } else if (!is.null(lab_sources$path)) {
    .trajectory_28d_resolve_path(lab_sources$path, root)
  } else {
    stop("lab_sources 需为文件路径字符向量或 list(files=...) / list(path=...)", call. = FALSE)
  }

  cli::cli_h2("合并实验室数据（{toupper(db_type)}，{length(files)} 个文件）")
  id_sets <- trajectory_28d_baseline_id_sets(baseline_df, id_col = id_col, lab_id_col = lab_id_col)
  baseline_ids <- id_sets$baseline_ids
  if (!length(baseline_ids) && !is.null(restrict_ids) && length(restrict_ids)) {
    baseline_ids <- unique(as.character(restrict_ids))
  }
  lab_restrict_ids <- id_sets$lab_ids
  if (!length(lab_restrict_ids)) lab_restrict_ids <- baseline_ids

  # 长表在 merge 内按 ID/day pivot；宽表仍可在合并后再滤一次
  lab_df <- trajectory_28d_merge_lab_csvs(
    files,
    id_col = lab_id_col,
    restrict_ids = if (length(lab_restrict_ids)) lab_restrict_ids else NULL,
    days = days
  )
  lab_df[[lab_id_col]] <- as.character(lab_df[[lab_id_col]])
  if (length(lab_restrict_ids)) {
    lab_df <- lab_df[lab_df[[lab_id_col]] %in% lab_restrict_ids, , drop = FALSE]
    cli::cli_alert_info(
      "实验室数据限制至基线 cohort：{length(lab_restrict_ids)} 个 {lab_id_col}，保留 {nrow(lab_df)} 行"
    )
  }
  if (lab_id_col != id_col) lab_df[[id_col]] <- lab_df[[lab_id_col]]
  else lab_df[[id_col]] <- as.character(lab_df[[id_col]])

  if (!nrow(lab_df)) stop("实验室数据在 ID 过滤后为空", call. = FALSE)

  if (length(baseline_ids) && id_col %in% names(lab_df)) {
    n_lab_before <- nrow(lab_df)
    lab_df <- lab_df[lab_df[[id_col]] %in% baseline_ids, , drop = FALSE]
    if (nrow(lab_df) < n_lab_before) {
      cli::cli_alert_info(
        "实验室数据与基线 {id_col} 对齐: {n_lab_before} → {nrow(lab_df)} 行（剔除无基线 ID）"
      )
    }
  }

  cli::cli_alert_info("实验室宽表 {nrow(lab_df)} 行 × {ncol(lab_df)} 列")
  comp_df <- trajectory_28d_build_daily_components(
    lab_df, days = days, db_type = db_type, id_col = id_col, lab_id_col = lab_id_col
  )
  if (length(baseline_ids) && id_col %in% names(comp_df)) {
    n_comp_before <- nrow(comp_df)
    comp_df <- comp_df[comp_df[[id_col]] %in% baseline_ids, , drop = FALSE]
    if (nrow(comp_df) < n_comp_before) {
      cli::cli_alert_info(
        "日度组分表与基线对齐: {n_comp_before} → {nrow(comp_df)} 行"
      )
    }
  }
  if (!is.null(baseline_df)) {
    comp_df <- trajectory_28d_merge_baseline(comp_df, baseline_df, id_col = id_col)
    cli::cli_alert_info("已合并基线协变量（供含 Age/BMI/Gender 等公式使用）")
  }

  index_vars <- as.character(index_vars)
  all_defs <- trajectory_28d_load_index_definitions(root)
  def_names <- vapply(all_defs, function(d) d$name, character(1L))
  index_vars <- intersect(index_vars, def_names)
  if (!length(index_vars)) stop("index_vars 在 index 定义中无匹配项", call. = FALSE)

  calc_data <- comp_df
  for (def in all_defs) {
    ix_name <- def$name
    if (any(grepl(paste0("^", ix_name, "_[0-9]+$"), names(calc_data)))) next
    ffunc <- trajectory_28d_make_formula_func(def$expr)
    calc_data <- tryCatch(
      calc_28d_index(calc_data, ix_name, ffunc),
      error = function(e) {
        cli::cli_alert_warning("跳过日度计算 {ix_name}: {conditionMessage(e)}")
        calc_data
      }
    )
  }

  results <- list()
  for (ix in index_vars) {
    day_pat <- paste0("^", ix, "_[0-9]+$")
    if (!any(grepl(day_pat, names(calc_data)))) {
      cli::cli_alert_warning("跳过保存 {ix}：28 天列未生成")
      next
    }
    cli::cli_h3("保存 28 天纵向指标: {ix}")
    out_path <- file.path(output_dir, paste0("12_", ix, ".RData"))
    saved <- save_28d_index(calc_data, ix, out_path = out_path, id_col = id_col,
                           min_non_na_days = min_non_na_days, rdata_obj = rdata_obj,
                           baseline_ids = baseline_ids)
    if (saved$n > 0L) results[[ix]] <- saved else
      cli::cli_alert_warning("{ix}: 无 ≥{min_non_na_days} 天非空样本，未产出有效宽表")
  }
  invisible(results)
}
