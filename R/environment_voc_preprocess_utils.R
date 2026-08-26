###############################################################################
#  environment_voc_preprocess_utils.R — 环境 VOC 对数变换状态 / 暴露标签映射
###############################################################################

environment_legacy_stats_path <- function(cfg, root) {
  cfg <- cfg %||% list()
  ep  <- cfg$environment_process %||% list()
  el  <- cfg$environment_lod %||% list()
  f   <- el$legacy_stats_file %||% ep$legacy_stats_file %||% file.path("Data", "nhanes", "stats.RData")
  if (!is_absolute_path(f)) f <- file.path(root, f)
  if (!file.exists(f)) return(NULL)
  f
}

environment_load_legacy_process_stats <- function(cfg, root) {
  path <- environment_legacy_stats_path(cfg, root)
  if (is.null(path)) return(NULL)
  obj <- (cfg$environment_lod %||% list())$legacy_stats_obj %||%
    (cfg$environment_process %||% list())$legacy_stats_obj %||% "stats"
  e <- new.env()
  load(path, envir = e)
  if (!exists(obj, envir = e, inherits = FALSE)) return(NULL)
  d <- get(obj, envir = e)
  if (!is.data.frame(d)) return(NULL)
  d
}

environment_prelog_voc_columns <- function(cfg, root) {
  d <- environment_load_legacy_process_stats(cfg, root)
  if (is.null(d) || !"Process" %in% names(d)) return(character(0))
  id_col <- if ("environment_feature" %in% names(d)) "environment_feature" else names(d)[1L]
  keep_proc <- c("log(ln)", "binary", "floor_at_lod")
  v <- as.character(d[[id_col]][d$Process %in% keep_proc])
  v <- setdiff(unique(v[nzchar(v)]), c("Group", "DN", "SEQN"))
  v
}

environment_lod_legacy_stats_lod <- function(feature, cfg, root) {
  d <- environment_load_legacy_process_stats(cfg, root)
  if (is.null(d) || !nrow(d)) return(NA_real_)
  id_col <- if ("environment_feature" %in% names(d)) {
    "environment_feature"
  } else if ("Abbreviation" %in% names(d)) {
    "Abbreviation"
  } else {
    names(d)[1L]
  }
  lod_col <- if ("LOD" %in% names(d)) "LOD" else NULL
  if (is.null(lod_col)) return(NA_real_)
  hit <- d[as.character(d[[id_col]]) == as.character(feature)[1L], , drop = FALSE]
  if (!nrow(hit)) return(NA_real_)
  suppressWarnings(as.numeric(hit[[lod_col]][1L]))
}

environment_voc_looks_log_scaled <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) < 10L) return(FALSE)
  stats::median(x) < 3 && stats::quantile(x, 0.95) < 15
}

#' Step00：将上游已 log(x+1) 的 VOC 反变换为 μg/L（供肌酐校正与 LOD 四步）
environment_restore_voc_to_ug_per_l <- function(data, voc_cols, cfg, root) {
  if (is.null(data) || !ncol(data)) return(data)
  voc_cols <- unique(intersect(as.character(voc_cols[nzchar(voc_cols)]), names(data)))
  if (!length(voc_cols)) return(data)
  prelog <- if (isTRUE((cfg$environment_prepare %||% list())$restore_all_voc_to_ugl %||% FALSE)) {
    voc_cols
  } else {
    environment_prelog_voc_columns(cfg, root)
  }
  restored <- character(0)
  for (v in voc_cols) {
    x <- suppressWarnings(as.numeric(data[[v]]))
    if (v %in% prelog || environment_voc_looks_log_scaled(x)) {
      data[[v]] <- exp(x) - 1
      data[[v]][!is.finite(data[[v]]) | data[[v]] < 0] <- NA_real_
      restored <- c(restored, v)
    }
  }
  if (length(restored)) {
    cli::cli_alert_info(
      "VOC 反变换 log(x+1)→μg/L: {length(restored)} 列（{paste(head(restored, 8), collapse = ', ')}{if (length(restored) > 8) ' ...' else ''}）"
    )
  }
  data
}

prepare_environment_kidney_voc_workflow <- function(cfg) {
  cfg <- cfg %||% list()
  ep <- cfg$environment_prepare %||% list()
  if (!is.null(ep$kidney_disease_voc_workflow)) {
    return(isTRUE(ep$kidney_disease_voc_workflow))
  }
  proj <- cfg$project %||% list()
  dis <- tolower(as.character(proj$disease %||% proj$disease_cn %||% ""))
  study <- tolower(as.character(proj$study_type %||% ""))
  isTRUE(study == "environment") && grepl("dkd|kidney|肾病|糖尿病肾", dis, ignore.case = TRUE)
}

environment_voc_exposure_name_map <- function() {
  c(
    DCVMA_2_2               = "2,2DCVMA",
    DCVMA_1_2               = "1,2DCVMA",
    Total_Hydroxycotinine   = "Total Hydroxycotinine",
    MHA_2                   = "2MHA",
    MHA_3_4                 = "3&4 MHA",
    Total_Cotinine          = "Total Cotinine",
    HPMA_3                  = "3HPMA",
    MHBMA_2                 = "MHBMA2",
    MHBMA_1                 = "MHBMA1",
    AMC                     = "AMCC",
    Napthol_1               = "1-napthol",
    Napthol_2               = "2-napthol",
    Hydroxyfluorene_3       = "3-hydroxyfluorene",
    Hydroxyphenanthrene_2_3 = "2&3-Hydroxyphenanthrene",
    Hydroxypyrene_1         = "1-hydroxypyrene",
    Aminonaphthalene_1      = "1-Aminonaphthalene",
    Aminonaphthalene_2      = "2-Aminonaphthalene",
    Aminobiphenyl_4         = "4-Aminobiphenyl",
    Dimethylaniline_2_6     = "2,6-Dimethylaniline",
    Anisidine_o             = "o-Anisidine",
    Toluidine_o             = "o-Toluidine",
    Monomethylarsonic_Acid  = "Monomethylarsonic Acid",
    Dimethylarsinic_Acid    = "Dimethylarsinic Acid",
    Arsenous_Acid           = "Arsenous Acid",
    Arsenic_acid            = "Arsenic acid",
    NMOR                    = "NMQR",
    HP2MA                   = "2HPMA",
    TTC                     = "TTCA",
    TNE_2                   = "TNE-2",
    ATC                     = "ATCA"
  )
}

#' 暴露代码表是否含真实化学名（Exposure 多数 ≠ Labels 代码）
environment_exposure_code_has_real_names <- function(code) {
  if (is.null(code) || !is.data.frame(code) || !nrow(code)) return(FALSE)
  if (!all(c("Labels", "Exposure") %in% names(code))) return(FALSE)
  lab <- as.character(code$Labels)
  exp <- as.character(code$Exposure)
  ok <- !is.na(lab) & !is.na(exp) & nzchar(lab) & nzchar(exp)
  if (!any(ok)) return(FALSE)
  mean(lab[ok] != exp[ok], na.rm = TRUE) >= 0.3
}

.environment_read_exposure_code_file <- function(f, obj = "Envrioment_code") {
  if (!nzchar(f %||% "") || !file.exists(f)) return(NULL)
  if (grepl("\\.csv$", f, ignore.case = TRUE)) {
    code <- tryCatch(
      utils::read.csv(f, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    return(code)
  }
  e <- new.env(parent = emptyenv())
  ok <- tryCatch({
    load(f, envir = e)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) return(NULL)
  obj <- as.character(obj %||% "Envrioment_code")[1L]
  if (!exists(obj, envir = e, inherits = FALSE)) {
    nms <- ls(envir = e)
    if (!length(nms)) return(NULL)
    obj <- nms[1L]
  }
  get(obj, envir = e, inherits = FALSE)
}

#' 加载暴露代码→真实名表；项目表若仅为代码镜像则回退仓库 Data 真实名表
environment_load_exposure_code_df <- function(cfg, root) {
  cfg <- cfg %||% list()
  env <- cfg$environment %||% list()
  root <- root %||% (cfg$project %||% list())$root %||% getwd()
  obj <- env$exposure_code_obj %||% "Envrioment_code"

  candidates <- character(0)
  primary <- env$exposure_code_file %||% NULL
  if (nzchar(primary %||% "")) {
    if (!is_absolute_path(primary)) primary <- file.path(root, primary)
    candidates <- c(candidates, primary)
    # 同目录 realname 变体
    candidates <- c(
      candidates,
      sub("\\.RData$", "_realname.csv", primary, ignore.case = TRUE),
      sub("\\.RData$", "_realname.RData", primary, ignore.case = TRUE),
      file.path(dirname(primary), "Envrioment_code_realname.csv")
    )
  }
  # 仓库级默认（所有环境项目共用）
  candidates <- c(
    candidates,
    env$exposure_code_fallback_file %||% character(0),
    file.path(root, "Data", "Envrioment_code.RData"),
    file.path(root, "Data", "Envrioment_code_realname.csv"),
    file.path(root, "Data", "nhanes", "Envrioment_code.RData")
  )
  candidates <- unique(candidates[nzchar(candidates)])

  best_identity <- NULL
  for (f in candidates) {
    if (!is_absolute_path(f) && !grepl("^[A-Za-z]:/", f)) {
      f_try <- file.path(root, f)
    } else {
      f_try <- f
    }
    code <- .environment_read_exposure_code_file(f_try, obj)
    if (is.null(code) || !is.data.frame(code) || !nrow(code)) next
    if (environment_exposure_code_has_real_names(code)) {
      cli::cli_alert_info(
        "暴露真实名映射: {basename(f_try)}（{nrow(code)} 行）"
      )
      return(code)
    }
    if (is.null(best_identity)) best_identity <- code
  }
  if (!is.null(best_identity)) {
    cli::cli_alert_warning(
      "暴露代码表未含真实化学名（Exposure≈Labels）；表/图将仍显示 URX* 代码。请提供 Envrioment_code_realname.csv 或 Data/Envrioment_code.RData"
    )
  }
  best_identity
}

environment_build_env_label_df <- function(voc_cols, cfg, root) {
  voc_cols <- unique(as.character(voc_cols[nzchar(voc_cols)]))
  if (!length(voc_cols)) return(NULL)
  code <- environment_load_exposure_code_df(cfg, root)
  alias <- environment_voc_exposure_name_map()
  rows <- lapply(voc_cols, function(v) {
    exp_name <- if (v %in% names(alias)) alias[[v]] else v
    fam <- NA_character_
    labels <- NA_character_
    exposure <- exp_name
    if (!is.null(code) && nrow(code)) {
      # 先按 Labels(代码列)命中 —— 字典 Exposure 列现存真实名，需用代码列定位行
      hit <- if ("Labels" %in% names(code)) {
        code[!is.na(code$Labels) & code$Labels == v, , drop = FALSE]
      } else code[0L, , drop = FALSE]
      # 兼容旧结构(Exposure 存代码)：再按 Exposure 命中
      if (!nrow(hit) && "Exposure" %in% names(code)) {
        hit <- code[code$Exposure == exp_name | code$Exposure == v, , drop = FALSE]
      }
      if (nrow(hit)) {
        fam <- as.character(hit$Family[1L])
        labels <- as.character(hit$Labels[1L])
        exposure <- as.character(hit$Exposure[1L])
      }
    }
    if (is.na(fam) || !nzchar(fam)) fam <- "Unmapped"
    data.frame(
      Abbreviation = v,
      Exposure = exposure,
      Family = fam,
      Labels = labels,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' 对尚未 log 的 VOC 列执行 log(x+1)（Step01 已处理列跳过）
environment_apply_voc_log_transform <- function(data, cfg, root,
                                                prelog_extra = character(0)) {
  if (is.null(data) || !is.data.frame(data) || !ncol(data)) {
    return(list(data = data, prelog_vocs = character(0), newly_logged = character(0)))
  }
  cfg <- cfg %||% list()
  root <- root %||% getwd()
  if (exists("environment_resolve_voc_columns", mode = "function")) {
    voc <- environment_resolve_voc_columns(data, cfg)
  } else {
    voc <- character(0)
  }
  voc <- intersect(unique(as.character(voc[nzchar(voc)])), names(data))
  ep <- cfg$environment_voc_log_transform %||% list()
  force_all <- isTRUE(ep$force_all_vocs %||% FALSE) ||
    prepare_environment_kidney_voc_workflow(cfg)
  prelog <- if (force_all) {
    character(0)
  } else {
    unique(c(
      environment_prelog_voc_columns(cfg, root),
      as.character(prelog_extra[nzchar(prelog_extra)])
    ))
  }
  need <- setdiff(voc, prelog)
  logged <- character(0)
  for (col in need) {
    x <- data[[col]]
    if (!is.numeric(x)) x <- suppressWarnings(as.numeric(as.character(x)))
    if (!is.numeric(x) || !any(is.finite(x))) next
    data[[col]] <- log(x + 1)
    logged <- c(logged, col)
  }
  list(
    data          = data,
    prelog_vocs   = prelog,
    newly_logged  = unique(logged)
  )
}

#' 将暴露代码表标签写入 baseline Table 1 展示名
environment_patch_baseline_table1_labels <- function(cfg, data, root) {
  cfg <- cfg %||% list()
  if (is.null(data) || !is.data.frame(data) || !ncol(data)) return(cfg)
  if (!exists("environment_resolve_voc_columns", mode = "function")) return(cfg)
  voc <- intersect(environment_resolve_voc_columns(data, cfg), names(data))
  if (!length(voc)) return(cfg)
  lbl_df <- environment_build_env_label_df(voc, cfg, root)
  if (is.null(lbl_df) || !nrow(lbl_df)) return(cfg)
  ov <- stats::setNames(as.list(lbl_df$Exposure), lbl_df$Abbreviation)
  bl_key <- if (!is.null(cfg$baseline_nhanes)) "baseline_nhanes" else "baseline"
  bl <- cfg[[bl_key]] %||% list()
  existing <- as.list(bl$table1_label_overrides %||% list())
  bl$table1_label_overrides <- utils::modifyList(existing, ov)
  cfg[[bl_key]] <- bl
  cfg
}

#' 构建 VOC log/ln 状态表（不做任何变换，仅审计）
environment_build_voc_log_status_df <- function(data, cfg, root) {
  cfg <- cfg %||% list()
  root <- root %||% getwd()
  if (exists("environment_resolve_voc_columns", mode = "function")) {
    voc_all <- environment_resolve_voc_columns(data, cfg)
  } else {
    voc_all <- character(0)
  }
  voc_all <- unique(as.character(voc_all[nzchar(voc_all)]))
  prelog <- environment_prelog_voc_columns(cfg, root)
  in_data <- if (!is.null(data) && ncol(data)) intersect(voc_all, names(data)) else character(0)
  dropped <- setdiff(voc_all, in_data)
  lbl_df <- if (length(in_data)) environment_build_env_label_df(in_data, cfg, root) else NULL
  display <- function(v) {
    if (!is.null(lbl_df) && v %in% lbl_df$Abbreviation) {
      as.character(lbl_df$Exposure[lbl_df$Abbreviation == v][1L])
    } else {
      v
    }
  }
  rows <- lapply(voc_all, function(v) {
    status <- if (v %in% prelog) {
      "已在 Step01 完成 log/ln（stats.RData）"
    } else if (v %in% in_data) {
      "未 log/ln（原始尺度）"
    } else {
      "未进入当前分析数据（如 data_clean 剔除）"
    }
    in_table1 <- v %in% in_data
    data.frame(
      Abbreviation = v,
      Exposure = display(v),
      Log_Status = status,
      In_Table1 = ifelse(in_table1, "是", "否"),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  attr(out, "prelog") <- intersect(prelog, in_data)
  attr(out, "raw") <- setdiff(in_data, prelog)
  attr(out, "dropped") <- dropped
  out
}

#' 导出 TXT：哪些指标已 log/ln、哪些未做（流水线本身不变换）
environment_export_voc_log_status_txt <- function(data, cfg, root, out_dir) {
  df <- environment_build_voc_log_status_df(data, cfg, root)
  prelog <- attr(df, "prelog") %||% character(0)
  raw    <- attr(df, "raw") %||% character(0)
  dropped <- attr(df, "dropped") %||% character(0)
  tbl <- df[df$In_Table1 == "是", , drop = FALSE]

  lines <- c(
    "环境毒物 log/ln 状态清单",
    paste0("生成时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "说明:",
    "  1. 本文件仅记录各指标在数据准备阶段是否已做 log/ln，流水线本次不对数据追加 log/ln。",
    "  2. 「已在 Step01 完成 log/ln」来自 Data/nhanes/stats.RData（Process = log(ln) 等）。",
    "  3. 「未 log/ln」仍为原始浓度尺度；Table 1 中会与已 log 指标混排，数值大小不可直接比较。",
    "  4. 若某指标 In_Table1=否，通常因缺失率过高在 data_clean 阶段剔除。",
    "",
    paste0("Table 1 纳入指标数: ", nrow(tbl)),
    paste0("  其中已 log/ln: ", sum(tbl$Abbreviation %in% prelog)),
    paste0("  其中未 log/ln: ", sum(tbl$Abbreviation %in% raw)),
    "",
    "========== Table 1 环境毒物明细 ==========",
    sprintf("%-28s | %-32s | %s",
            "Abbreviation", "Exposure", "Log_Status")
  )
  if (nrow(tbl)) {
    lines <- c(lines, apply(tbl, 1L, function(r) {
      sprintf("%-28s | %-32s | %s", r[["Abbreviation"]], r[["Exposure"]], r[["Log_Status"]])
    }))
  }
  lines <- c(
    lines,
    "",
    "========== 已在 Step01 完成 log/ln ==========",
    if (length(prelog)) paste(prelog, collapse = ", ") else "（无）",
    "",
    "========== 未 log/ln（原始尺度，当前数据中存在）==========",
    if (length(raw)) paste(raw, collapse = ", ") else "（无）",
    "",
    "========== 配置 VOC 但未进入当前数据 ==========",
    if (length(dropped)) paste(dropped, collapse = ", ") else "（无）",
    ""
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(out_dir, "Environment_VOC_Log_Status.txt")
  writeLines(lines, path, useBytes = TRUE)
  cli::cli_alert_success("VOC log/ln 状态清单: {basename(path)}")
  invisible(path)
}

environment_export_log_transform_summary <- function(stats_df, prelog_vocs, tbl_dir) {
  if (is.null(stats_df) || !nrow(stats_df)) return(invisible(NULL))
  id_col <- if ("environment_feature" %in% names(stats_df)) "environment_feature" else names(stats_df)[1L]
  proc_col <- if ("Process" %in% names(stats_df)) "Process" else "process"
  summary <- data.frame(
    Variable = as.character(stats_df[[id_col]]),
    Process = as.character(stats_df[[proc_col]]),
    Transform_Action = ifelse(
      stats_df[[proc_col]] == "already_log(ln)", "跳过（Step01 已 log/ln）",
      ifelse(stats_df[[proc_col]] == "log(ln)", "本次 log(x+1)",
             ifelse(stats_df[[proc_col]] == "floor_at_lod", "本次 floor@LOD",
                    ifelse(stats_df[[proc_col]] %in% c("removed", "no_valid_samples_removed"),
                           "删除", as.character(stats_df[[proc_col]]))))
    ),
    Source = ifelse(as.character(stats_df[[id_col]]) %in% prelog_vocs,
                    "Data/nhanes/stats.RData",
                    "process_environment_data"),
    stringsAsFactors = FALSE
  )
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(tbl_dir, "Table_Environment_Log_Transform_Summary.csv")
  utils::write.csv(summary, path, row.names = FALSE, fileEncoding = "UTF-8")
  cli::cli_alert_success("对数变换摘要: {basename(path)}")
  invisible(path)
}
