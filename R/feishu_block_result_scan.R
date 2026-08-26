###############################################################################
#  feishu_block_result_scan.R — 扫描 02block_result 目录树
#  疾病编号（01/02/…）从文件夹名解析，不可改写
###############################################################################

.feishu_block_result_skip_dirs <- function() {
  c("新建文件夹", "10_osteoporosis - 副本")
}

.feishu_parse_disease_dir <- function(dir_name) {
  dir_name <- trimws(as.character(dir_name))
  m <- regexec("^(\\d{2})_(.+)$", dir_name, perl = TRUE)
  hit <- regmatches(dir_name, m)[[1L]]
  if (length(hit) >= 3L) {
    return(list(
      disease_id   = hit[2L],
      disease_name = hit[3L],
      disease_dir  = dir_name,
      valid        = TRUE
    ))
  }
  list(
    disease_id   = NA_character_,
    disease_name = dir_name,
    disease_dir  = dir_name,
    valid        = FALSE
  )
}

.feishu_read_batch_summary <- function(routine_path) {
  csv <- file.path(routine_path, "Tables", "Batch_summary_all_indices.csv")
  if (!file.exists(csv)) return(NULL)
  df <- tryCatch(
    utils::read.csv(csv, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || !nrow(df)) return(NULL)
  if (!"index" %in% names(df) && "voc" %in% names(df)) df$index <- df$voc
  df
}

.feishu_collect_status_json_rows <- function(routine_path) {
  patterns <- c(
    file.path(routine_path, "by_index", "*", "_batch_status.json"),
    file.path(routine_path, "by_voc", "*", "_batch_status.json")
  )
  files <- unique(unlist(lapply(patterns, Sys.glob), use.names = FALSE))
  if (!length(files)) return(NULL)

  rows <- lapply(files, function(path) {
    st <- tryCatch(jsonlite::fromJSON(path), error = function(e) list())
    .sc <- function(x, default = NA_character_) {
      if (is.null(x) || length(x) == 0) return(default)
      as.character(x[[1L]])
    }
    .sn <- function(x, default = NA_real_) {
      if (is.null(x) || length(x) == 0) return(default)
      suppressWarnings(as.numeric(x[[1L]]))
    }
    ix <- .sc(st$index %||% st$voc %||% basename(dirname(path)))
    data.frame(
      index           = ix,
      status          = .sc(st$status, "not_run"),
      db_mode         = .sc(st$db_mode),
      nhanes_branch   = .sc(st$nhanes_branch),
      mimic_branch    = .sc(st$mimic_branch),
      nhanes_or       = .sn(st$nhanes_or),
      mimic_or        = .sn(st$mimic_or),
      n_nhanes_after  = .sn(st$n_nhanes_after),
      n_mimic_after   = .sn(st$n_mimic_after),
      error_message   = .sc(st$error_message),
      elapsed_sec     = .sn(st$elapsed_sec),
      finished_at     = .sc(st$finished_at),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.feishu_routine_status_summary <- function(routine_path) {
  has_shared <- dir.exists(file.path(routine_path, "_shared"))
  df <- .feishu_read_batch_summary(routine_path)
  if (is.null(df)) df <- .feishu_collect_status_json_rows(routine_path)

  if (is.null(df) || !nrow(df)) {
    cell <- if (has_shared) "共享层完成" else "未跑"
    return(list(
      routine          = basename(routine_path),
      routine_path     = routine_path,
      has_shared       = has_shared,
      total            = 0L,
      success          = 0L,
      failure          = 0L,
      not_run          = 0L,
      cell_status      = cell,
      summary_text     = cell,
      rows             = NULL
    ))
  }

  st <- tolower(as.character(df$status %||% ""))
  n_total   <- nrow(df)
  n_success <- sum(st == "success", na.rm = TRUE)
  n_failure <- sum(st %in% c("error", "failed", "parse_error"), na.rm = TRUE)
  n_not_run <- n_total - n_success - n_failure

  cell <- if (n_total == 0L) {
    if (has_shared) "共享层完成" else "未跑"
  } else if (n_success == n_total) {
    "全部成功"
  } else if (n_failure == n_total) {
    "全部失败"
  } else if (n_success > 0L || n_failure > 0L) {
    "部分完成"
  } else if (has_shared) {
    "共享层完成"
  } else {
    "未跑"
  }

  summary_text <- sprintf("%s（%d/%d）", cell, n_success, n_total)

  list(
    routine          = basename(routine_path),
    routine_path     = routine_path,
    has_shared       = has_shared,
    total            = as.integer(n_total),
    success          = as.integer(n_success),
    failure          = as.integer(n_failure),
    not_run          = as.integer(n_not_run),
    cell_status      = cell,
    summary_text     = summary_text,
    rows             = df
  )
}

#' 扫描 block_result 根目录，返回疾病×套路结构
feishu_scan_block_result <- function(result_root,
                                      skip_dirs = .feishu_block_result_skip_dirs()) {
  result_root <- normalizePath(result_root, winslash = "/", mustWork = FALSE)
  if (!dir.exists(result_root))
    stop("找不到结果目录: ", result_root, call. = FALSE)

  disease_dirs <- list.dirs(result_root, full.names = FALSE, recursive = FALSE)
  disease_dirs <- disease_dirs[!disease_dirs %in% skip_dirs]

  diseases <- list()
  all_routines <- character(0)

  for (d in sort(disease_dirs)) {
    meta <- .feishu_parse_disease_dir(d)
    if (!isTRUE(meta$valid)) {
      cli::cli_alert_warning("跳过非标准疾病目录（需 01_疾病名）: {d}")
      next
    }
    dpath <- file.path(result_root, d)
    routine_dirs <- list.dirs(dpath, full.names = FALSE, recursive = FALSE)
    routine_dirs <- routine_dirs[!routine_dirs %in% c("01Block-new-Final")]

    routines <- list()
    for (r in sort(routine_dirs)) {
      rpath <- file.path(dpath, r)
      if (!dir.exists(rpath)) next
      st <- .feishu_routine_status_summary(rpath)
      routines[[r]] <- st
      all_routines <- unique(c(all_routines, r))
    }

    diseases[[d]] <- list(
      disease_id   = meta$disease_id,
      disease_name = meta$disease_name,
      disease_dir  = meta$disease_dir,
      routines     = routines
    )
  }

  list(
    result_root  = result_root,
    diseases     = diseases,
    all_routines = sort(unique(all_routines))
  )
}

.feishu_disease_overall_status <- function(disease_info) {
  routines <- disease_info$routines %||% list()
  if (!length(routines)) return("待开始")
  cells <- vapply(routines, function(x) x$cell_status %||% "未跑", character(1L))
  n_succ_r <- sum(cells == "全部成功", na.rm = TRUE)
  n_part   <- sum(cells == "部分完成", na.rm = TRUE)
  n_fail   <- sum(cells == "全部失败", na.rm = TRUE)
  n_shared <- sum(cells == "共享层完成", na.rm = TRUE)
  n_none   <- sum(cells == "未跑", na.rm = TRUE)
  if (n_none == length(cells)) return("待开始")
  if (n_succ_r == length(cells)) return("全部成功")
  if (n_fail > 0L && n_succ_r == 0L && n_part == 0L) return("运行中")
  if (n_succ_r > 0L || n_part > 0L || n_shared > 0L) return("部分完成")
  "运行中"
}
