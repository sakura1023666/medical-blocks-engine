###############################################################################
#  trajectory_pub_finalize.R — 轨迹预后双库发表收口（全项目复用）
#
#  GPR + AP WPR dual 对话沉淀。新课题走 finalize + config$trajectory_pub，
#  勿再堆 run/trajectory_prognosis/repair_* / fix_*课题*。
#
#  能力：
#    1) Fig1 = attrition_draw_dual_panel_pdf（发病/预后同款 CONSORT）
#    2) dual_db_combine：Trajectory / Dynpred / 轨迹 KM 默认竖拼
#    3) 共享分段 Cox 切点 = min(各库最优) → 单库切点图；可选根目录只留指定库 Table3
#    4) 根目录发表图白名单 + export_pub_figures 四目录
#    5) 双库 Table1/S1/S2/S3/S5 行交集外科对齐（R/trajectory_dual_pub_harmonize.R）
#    6) skip_class_swap 钉死（与表侧原始 JLCM 标签一致）
#
#  入口：
#    trajectory_batch_finalize_index_outputs(index_root, config, index_name)
#    CLI: Rscript run/trajectory_prognosis/finalize_trajectory_pub.R --index-root … --config …
#
#  config$trajectory_pub = list(
#    enable = TRUE,
#    fig1_consort = TRUE,
#    combine_figures = TRUE,
#    shared_piecewise_cut = list(
#      enable = TRUE, mode = "min_best",
#      root_keep_db = NULL   # 如 "mimic"：根 Tables/Figs 只留该库 Table3 / 切点图
#    ),
#    drop_missing_overview = FALSE,  # TRUE 时配合 figure_stems_no_missing
#    align_dual_tables = list(enable = FALSE, keep_vars = NULL,
#                             kinds = c("table1","s1","s2","s3","s5")),
#    enforce_13_figures = TRUE,
#    export_formats = TRUE,
#    fix_tables = TRUE,
#    skip_class_swap = TRUE
#  )
###############################################################################

trajectory_paper_figure_stems <- function(index_name = "Index", config = NULL) {
  ix <- as.character(index_name %||% "Index")[1L]
  # 课题可覆盖发表图白名单（config$trajectory_pub$figure_stems，stem 不含扩展名；
  # 串内 %IX% 占位符会替换成指标名）。单库课题删掉空亚组图/缺失概览图后需重排号。
  override <- tryCatch(
    as.character(config$trajectory_pub$figure_stems %||% character(0)),
    error = function(e) character(0)
  )
  if (length(override)) return(gsub("%IX%", ix, override, fixed = TRUE))
  c(
    "Figure 1. Flowchart of patient selection",
    sprintf("Figure 2. Trajectory of %s latent classes", ix),
    sprintf("Figure 3. Dynamic prediction of %s trajectory", ix),
    "Figure 4. Individual dynamic prediction",
    "Figure S1. Missing value overview",
    "Figure S2. Kaplan Meier survival by trajectory class",
    "Figure S3. Piecewise Cox cut point search",
    "Figure S4. Subgroup analysis by trajectory class",
    "Figure S5. Weibull dynamic model comparison AUC",
    "Figure S6. Weibull dynamic model comparison C index",
    "Figure S7. Weibull dynamic model comparison Accuracy",
    "Figure S8. Weibull dynamic model comparison Sensitivity",
    "Figure S9. Weibull dynamic model comparison Specificity"
  )
}

.trajectory_pub_cfg <- function(config) {
  cfg <- config$trajectory_pub %||% list()
  list(
    enable = if (is.null(cfg$enable)) TRUE else isTRUE(cfg$enable),
    fig1_consort = if (is.null(cfg$fig1_consort)) TRUE else isTRUE(cfg$fig1_consort),
    combine_figures = if (is.null(cfg$combine_figures)) TRUE else isTRUE(cfg$combine_figures),
    shared_piecewise_cut = cfg$shared_piecewise_cut %||% list(enable = TRUE, mode = "min_best"),
    drop_missing_overview = isTRUE(cfg$drop_missing_overview %||% FALSE),
    align_dual_tables = cfg$align_dual_tables %||% list(enable = FALSE),
    skip_class_swap = if (is.null(cfg$skip_class_swap)) TRUE else isTRUE(cfg$skip_class_swap),
    enforce_13_figures = if (is.null(cfg$enforce_13_figures)) TRUE else isTRUE(cfg$enforce_13_figures),
    export_formats = if (is.null(cfg$export_formats)) TRUE else isTRUE(cfg$export_formats),
    fix_tables = if (is.null(cfg$fix_tables)) TRUE else isTRUE(cfg$fix_tables),
    # 课题级：发表图白名单（stem，%IX%=指标名）与旧→新重排对
    figure_stems = cfg$figure_stems,
    figure_renumber = cfg$figure_renumber,
    figure_extra = cfg$figure_extra
  )
}

.trajectory_pub_db_slugs <- function(index_root, config = NULL) {
  kids <- list.dirs(index_root, full.names = FALSE, recursive = FALSE)
  kids <- kids[nzchar(kids) & !grepl("^\\.|Figures|Tables|checkpoints|_archive", kids)]
  # 常见双库
  prefer <- c("eicu", "mimic", "charls", "nhanes")
  hit <- intersect(prefer, tolower(kids))
  if (length(hit) >= 2L) return(hit)
  if (length(kids) >= 2L) return(tolower(kids[seq_len(2L)]))
  hit
}

.trajectory_pub_db_lab <- function(slug) {
  s <- tolower(as.character(slug)[1L])
  if (grepl("mimic", s)) "MIMIC"
  else if (grepl("eicu", s)) "eICU"
  else if (grepl("charls", s)) "CHARLS"
  else toupper(s)
}

#' 读各库 CutScan，解析最优切点
#'
#' mode:
#'   - "min_best"：各库最优切点的最小值（旧默认）
#'   - 库 slug（如 "mimic"/"eicu"）：**主库切点**，两库 Table3 强制同切
trajectory_resolve_shared_piecewise_cut <- function(index_root,
                                                   db_slugs = NULL,
                                                   mode = "min_best") {
  db_slugs <- db_slugs %||% .trajectory_pub_db_slugs(index_root)
  best <- integer(0)
  for (db in db_slugs) {
    hits <- list.files(
      file.path(index_root, db),
      pattern = "Table_Piecewise_Cox_CutScan",
      recursive = TRUE, full.names = TRUE
    )
    # 优先正式 Tables，其次 _archive（curate 可能把 CutScan 挪走）
    hits <- hits[!grepl("archive_messy|_raw", hits)]
    if (!length(hits)) next
    pref <- hits[!grepl("/_archive/", hits)]
    if (!length(pref)) pref <- hits
    d <- utils::read.csv(pref[[1L]], stringsAsFactors = FALSE)
    ok <- d[!is.na(d$loglik), , drop = FALSE]
    if ("stable" %in% names(ok)) {
      st <- ok[ok$stable %in% c(TRUE, "TRUE", "true", 1, "1"), , drop = FALSE]
      if (nrow(st)) ok <- st
    }
    if (!nrow(ok)) next
    best[[db]] <- as.integer(ok$cut[which.max(ok$loglik)])
  }
  if (!length(best)) {
    return(list(cuts = best, shared_cut = NA_integer_, source_db = NA_character_))
  }
  mode <- tolower(as.character(mode %||% "min_best")[1L])
  # 别名：primary / main → 常见主库 mimic
  if (mode %in% c("primary", "main", "secondary")) {
    if (identical(mode, "secondary") && "eicu" %in% names(best)) mode <- "eicu"
    else if ("mimic" %in% names(best)) mode <- "mimic"
  }
  if (identical(mode, "min_best")) {
    shared <- as.integer(min(unlist(best), na.rm = TRUE))
    src <- names(best)[which.min(unlist(best))]
  } else if (mode %in% names(best)) {
    shared <- as.integer(best[[mode]])
    src <- mode
  } else {
    shared <- as.integer(best[[1L]])
    src <- names(best)[1L]
  }
  list(cuts = best, shared_cut = shared, source_db = src, mode = mode)
}

#' Fig1：双库 CONSORT（发病/预后同款）
trajectory_ensure_fig1_consort <- function(index_root, config = NULL,
                                           db_slugs = NULL, titles = NULL) {
  if (!exists("attrition_draw_dual_panel_pdf", mode = "function") ||
      !exists("attrition_draw_pdf", mode = "function")) {
    attrition <- file.path(
      config$project$root %||% getwd(), "R/attrition_log.R"
    )
    if (file.exists(attrition)) source(attrition, local = FALSE)
  }
  db_slugs <- db_slugs %||% .trajectory_pub_db_slugs(index_root, config)
  if (length(db_slugs) < 2L) return(FALSE)
  rows_by_db <- list()
  title_vec <- character(0)
  for (db in db_slugs) {
    lab <- .trajectory_pub_db_lab(db)
    csv_cands <- c(
      file.path(index_root, db, "step24_attrition_flowchart/Tables",
                sprintf("Flowchart_attrition_%s.csv", db)),
      file.path(index_root, db, "step24_attrition_flowchart/Tables/Flowchart_attrition.csv"),
      list.files(file.path(index_root, db), pattern = "Flowchart_attrition.*\\.csv$",
                 recursive = TRUE, full.names = TRUE)
    )
    csv_cands <- unique(csv_cands[file.exists(csv_cands)])
    csv_cands <- csv_cands[!grepl("/_raw/", csv_cands)]
    if (!length(csv_cands)) {
      cli::cli_alert_warning("Fig1 CONSORT: 缺 attrition CSV [{lab}]")
      return(FALSE)
    }
    rows <- utils::read.csv(csv_cands[[1L]], stringsAsFactors = FALSE)
    rows_by_db[[lab]] <- rows
    ttl <- if (!is.null(titles) && length(titles) >= length(rows_by_db)) {
      titles[[length(rows_by_db)]]
    } else {
      sprintf("%s — trajectory prognosis", lab)
    }
    title_vec <- c(title_vec, ttl)
    dest_u <- file.path(
      index_root, db, "Figures",
      sprintf("Figure 1-%s. Flowchart of patient selection.pdf", lab)
    )
    dir.create(dirname(dest_u), recursive = TRUE, showWarnings = FALSE)
    attrition_draw_pdf(rows, ttl, dest_u)
  }
  pdf_dir <- file.path(index_root, "Figures/pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(pdf_dir, "Figure 1. Flowchart of patient selection.pdf")
  ok <- attrition_draw_dual_panel_pdf(rows_by_db, dest, titles = title_vec)
  isTRUE(ok)
}

#' 双库 Table3 强制同一切点；Fig S3 只留选型库单图
trajectory_apply_shared_piecewise_cut <- function(index_root, config,
                                                  index_name,
                                                  cut_info = NULL,
                                                  max_followup = 28L) {
  root <- config$project$root %||% getwd()
  for (rel in c(
    "R/trajectory_survival_utils.R",
    "R/trajectory_paper_tables.R",
    "R/study_batch_runner.R",
    "Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R"
  )) {
    fp <- file.path(root, rel)
    if (file.exists(fp)) source(fp, local = FALSE)
  }
  cut_info <- cut_info %||% trajectory_resolve_shared_piecewise_cut(index_root)
  cut_shared <- as.integer(cut_info$shared_cut)
  if (!is.finite(cut_shared)) {
    cli::cli_alert_warning("shared piecewise cut: 无法解析切点，跳过")
    return(invisible(cut_info))
  }
  src_db <- cut_info$source_db
  src_lab <- .trajectory_pub_db_lab(src_db)
  db_slugs <- names(cut_info$cuts)
  if (!length(db_slugs)) db_slugs <- .trajectory_pub_db_slugs(index_root)
  ix <- as.character(index_name)[1L]
  max_followup <- as.integer(max_followup %||% 28L)[1L]

  # 记录
  sum_dir <- file.path(index_root, "Tables/Summary")
  dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      db = names(cut_info$cuts),
      best_cut = as.integer(unlist(cut_info$cuts)),
      shared_cut = cut_shared,
      s3_source_db = src_db,
      stringsAsFactors = FALSE
    ),
    file.path(sum_dir, sprintf("piecewise_shared_cut_%s.csv", ix)),
    row.names = FALSE
  )

  id_col <- config$data$id_column %||% "subject_id"
  time_var <- config$survival$time_var %||% "futime"
  event_var <- config$survival$event_var %||% "Mortality_28d"
  ck_base <- file.path(
    dirname(dirname(index_root)), # by_index -> project
    "checkpoints", "by_index",
    gsub("^【success】|^【failed】", "", basename(index_root))
  )
  # basename 可能是 【success】GPR
  ix_bare <- gsub("^【success】|^【failed】", "", basename(index_root))
  ck_base <- file.path(
    config$trajectory_batch$checkpoint_root %||%
      file.path(config$project$output_dir %||% dirname(dirname(index_root)), "checkpoints"),
    "by_index", ix_bare
  )

  for (db in db_slugs) {
    lab <- .trajectory_pub_db_lab(db)
    unit <- file.path(index_root, db)
    # 优先 checkpoint；否则读分库 Tables 旁无法拟合 — 需要 imputed
    ck <- file.path(ck_base, db)
    ctx <- NULL
    if (dir.exists(ck) && exists("study_batch_load_checkpoint_ctx", mode = "function")) {
      ctx <- tryCatch(
        study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm"),
        error = function(e) NULL
      )
    }
    if (is.null(ctx) || is.null(ctx$data$imputed %||% ctx$data$cleaned)) {
      cli::cli_alert_warning("[{lab}] 无 checkpoint 数据，跳过 Table3@shared_cut（请用 CLI 带 ck）")
      next
    }
    data <- ctx$data$imputed %||% ctx$data$cleaned
    class_col <- paste0("trajectory_class_", ix)
    if (!class_col %in% names(data)) class_col <- "trajectory_class"
    if (!class_col %in% names(data) && "trajectory_class_GPR" %in% names(data))
      class_col <- "trajectory_class_GPR"
    if (!time_var %in% names(data)) {
      for (cand in c("futime", "survival_time_28d", "survival_time", "time_28d")) {
        if (cand %in% names(data)) { time_var <- cand; break }
      }
    }
    if (!event_var %in% names(data)) {
      for (cand in c("Mortality_28d", "survival_28d", "fustatus", "event_28d")) {
        if (cand %in% names(data)) { event_var <- cand; break }
      }
    }
    cfg <- config
    cfg$project$database <- lab
    cfg$project$output_dir <- unit
    cfg$project$root <- root
    cfg$trajectory$skip_class_swap <- TRUE
    ctx$config <- cfg
    bl <- modifyList(
      config$trajectory_piecewise_cox %||% list(),
      list(
        force_cut = cut_shared,
        auto_scan = TRUE, # 保留 scan 供对照
        max_followup = max_followup,
        database_label = if (grepl("mimic", tolower(lab))) "MIMIC-IV" else
          if (grepl("eicu", tolower(lab))) "eICU-CRD" else lab,
        pause_enable = FALSE
      )
    )
    res <- .tpc01_run_one(ctx, data, bl, ix, class_col, time_var, event_var,
                          max_followup, NULL)
    if (is.null(res) || is.null(res$table)) {
      cli::cli_alert_warning("[{lab}] force_cut={cut_shared} 拟合失败")
      next
    }
    out_tab <- file.path(unit, "Tables")
    dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
    fp_t3 <- file.path(
      out_tab,
      paste0("Table 3-", lab, ". Time-dependent HR for trajectory classes.xlsx")
    )
    t3_title <- paste0("Table 3-", lab, ". Time-dependent HR for trajectory classes")
    if (exists("trajectory_export_table3_sci", mode = "function")) {
      trajectory_export_table3_sci(ctx, res$table, cut_shared, fp_t3, t3_title,
                                   end_day = max_followup)
    }
    root_tab <- file.path(index_root, "Tables")
    dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
    file.copy(fp_t3, file.path(root_tab, basename(fp_t3)), overwrite = TRUE)
    cli::cli_alert_success("[{lab}] Table3 @ cut={cut_shared}")
  }

  # 切点搜索单图：选型库；图号随 config$trajectory_pub$figure_stems（无 Missing 时多为 S2）
  scan_hits <- list.files(
    file.path(index_root, src_db),
    pattern = "Table_Piecewise_Cox_CutScan",
    recursive = TRUE, full.names = TRUE
  )
  scan_hits <- scan_hits[!grepl("archive_messy", scan_hits)]
  if (length(scan_hits) && exists(".tpc01_cut_search_plot", mode = "function")) {
    df <- utils::read.csv(scan_hits[[1L]], stringsAsFactors = FALSE)
    p <- .tpc01_cut_search_plot(
      df, cut_shared,
      paste0(ix, " piecewise Cox cut-off search (", src_lab, ")"),
      max_followup, "sans"
    )
    stems <- tryCatch(
      trajectory_paper_figure_stems(ix, config),
      error = function(e) character(0)
    )
    cut_stem <- stems[grepl("Piecewise Cox cut", stems, ignore.case = TRUE)][1L]
    if (is.na(cut_stem) || !nzchar(cut_stem)) {
      cut_stem <- "Figure S3. Piecewise Cox cut point search"
    }
    # "Figure S2. Piecewise ..." → 编号 token 用于分库文件名
    num_tok <- sub("^Figure\\s+([0-9S]+)\\..*$", "\\1", cut_stem)
    s3_unit <- file.path(
      index_root, src_db, "Figures",
      sprintf("Figure %s-%s. Piecewise Cox cut point search.pdf", num_tok, src_lab)
    )
    dir.create(dirname(s3_unit), recursive = TRUE, showWarnings = FALSE)
    ggplot2::ggsave(s3_unit, p, width = 7.2, height = 4.2,
                    device = grDevices::cairo_pdf)
    pdf_dir <- file.path(index_root, "Figures/pdf")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    s3_root <- file.path(pdf_dir, paste0(cut_stem, ".pdf"))
    file.copy(s3_unit, s3_root, overwrite = TRUE)
    # 删除其它库同角色分库残留
    for (odb in setdiff(db_slugs, src_db)) {
      olab <- .trajectory_pub_db_lab(odb)
      unlink(list.files(
        file.path(index_root, odb, "Figures"),
        pattern = sprintf("Piecewise Cox cut point search\\.pdf$", olab),
        full.names = TRUE
      ))
      unlink(file.path(
        index_root, odb, "Figures",
        sprintf("Figure %s-%s. Piecewise Cox cut point search.pdf", num_tok, olab)
      ))
    }
    cli::cli_alert_success("切点搜索图单库={src_lab} cut={cut_shared} → {cut_stem}")
  }
  invisible(cut_info)
}

#' db 级 Fig1 修复：curate 的拷贝在网络盘上可能静默失败，留下 PLACEHOLDER。
#' 只要 step*_attrition_flowchart 的真实纳排图更大，就强制覆盖 db 级 Fig1。
trajectory_fix_db_fig1_flowchart <- function(index_root, dbs) {
  fixed <- 0L
  for (db in dbs) {
    db_lab <- .trajectory_pub_db_lab(db)
    root <- file.path(index_root, db)
    if (!dir.exists(root)) next
    cand <- list.files(root, pattern = "Figure 1\\..*\\.(pdf|PDF)$",
                       recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    cand <- cand[grepl("attrition_flowchart", cand, fixed = TRUE)]
    cand <- cand[!grepl("/_raw/", cand)]
    if (!length(cand)) next
    src <- cand[which.max(file.info(cand)$size)]
    if (is.na(file.info(src)$size) || file.info(src)$size < 10000) next
    dests <- c(
      list.files(file.path(root, "Figures"), pattern = "^Figure 1-.*\\.pdf$",
                 full.names = TRUE, ignore.case = TRUE),
      file.path(root, "Figures", sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
    )
    dests <- unique(dests[nzchar(dests)])
    if (!length(dests)) next
    dest <- dests[1L]
    dsz <- if (file.exists(dest)) file.info(dest)$size else -1
    if (is.na(dsz)) dsz <- -1
    if (dsz < file.info(src)$size) {
      ok <- file.copy(src, dest, overwrite = TRUE)
      if (isTRUE(ok)) fixed <- fixed + 1L
    }
  }
  if (fixed > 0L && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("Fig1 纳排图已从 step24 修复 {fixed} 处")
  }
  invisible(fixed)
}

#' 单库发表图重排：按 config$trajectory_pub$figure_renumber 的 (old→new) 标题对，
#' 把分库 "Figure <old#>-<DB>. <title>.pdf" 重命名/下架（new="" → 移入 _raw）。
trajectory_apply_figure_renumber <- function(index_root, dbs, index_name, renumber) {
  ix <- as.character(index_name)[1L]
  olds <- as.character(renumber$old %||% character(0))
  news <- as.character(renumber$new %||% character(0))
  if (!length(olds) || length(olds) != length(news)) return(invisible(0L))
  olds <- gsub("%IX%", ix, olds, fixed = TRUE)
  news <- gsub("%IX%", ix, news, fixed = TRUE)
  tag_db <- function(stem, db_lab) {
    sub("^(Figure [A-Za-z]?[0-9]+)\\.", paste0("\\1-", db_lab, "."), stem, perl = TRUE)
  }
  strip_db <- function(bn, db_lab) {
    sub(sprintf("^(Figure [A-Za-z]?[0-9]+)-%s\\.", db_lab), "\\1.", bn,
        perl = TRUE, ignore.case = TRUE)
  }
  n <- 0L
  for (db in dbs) {
    db_lab <- .trajectory_pub_db_lab(db)
    fig_dir <- file.path(index_root, db, "Figures")
    if (!dir.exists(fig_dir)) next
    have <- list.files(fig_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
    have <- have[!grepl("/_raw/", have)]
    # 去掉 "-DB" 标签还原成 stem 以便按标题配对
    virt <- strip_db(basename(have), db_lab)
    virt <- sub("\\.pdf$", "", virt, ignore.case = TRUE)
    for (i in seq_along(olds)) {
      hit <- which(virt == olds[[i]])
      if (!length(hit)) next
      fp <- have[hit[1L]]
      if (nzchar(news[[i]])) {
        dest_nm <- sprintf("%s.pdf", tag_db(news[[i]], db_lab))
        dest <- file.path(fig_dir, dest_nm)
        if (!identical(normalizePath(fp, mustWork = FALSE),
                       normalizePath(dest, mustWork = FALSE))) {
          file.rename(fp, dest)
          n <- n + 1L
        }
      } else {
        raw <- file.path(fig_dir, "_raw")
        dir.create(raw, recursive = TRUE, showWarnings = FALSE)
        file.rename(fp, file.path(raw, basename(fp)))
        n <- n + 1L
      }
    }
  }
  if (n > 0L && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info("按课题白名单重排发表图编号：处理 {n} 个文件")
  }
  invisible(n)
}

#' 单库发表收口：分库 "Figure N-<DB>. …" 镜像为根级无标签名（进 Figures/pdf）
trajectory_mirror_single_db_figures <- function(index_root, index_name, db, config = NULL) {
  ix <- as.character(index_name)[1L]
  db_lab <- .trajectory_pub_db_lab(db)
  src_dir <- file.path(index_root, db, "Figures")
  if (!dir.exists(src_dir)) return(invisible(FALSE))
  pdf_dir <- file.path(index_root, "Figures", "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  stems <- trajectory_paper_figure_stems(ix, config)
  srcs <- list.files(src_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  srcs <- srcs[!grepl("/_raw/", srcs)]
  # 目标名 = 源名去掉 "-<DB>" 标签（"Figure 2-MIMIC. x.pdf" → "Figure 2. x.pdf"）
  target_names <- sub(
    sprintf("^(Figure [A-Za-z]?[0-9]+)-%s(\\.)", db_lab),
    "\\1\\2", basename(srcs), perl = TRUE, ignore.case = TRUE
  )
  ok <- 0L
  for (i in seq_along(srcs)) {
    tn <- target_names[[i]]
    if (!sub("\\.pdf$", "", tn, ignore.case = TRUE) %in% stems) next
    file.copy(srcs[[i]], file.path(pdf_dir, tn), overwrite = TRUE)
    ok <- ok + 1L
  }
  cli::cli_alert_success("[{toupper(db)}] 单库镜像根级发表图 {ok} 张")
  invisible(ok > 0L)
}

#' 根目录 pdf 白名单校验 / 清理非论文图
trajectory_enforce_paper_figures <- function(index_root, index_name,
                                             delete_extra = TRUE, config = NULL) {
  stems <- trajectory_paper_figure_stems(index_name, config)
  pdf_dir <- file.path(index_root, "Figures/pdf")
  if (!dir.exists(pdf_dir)) dir.create(pdf_dir, recursive = TRUE)
  # 把根 Figures 平铺 PDF 挪进 pdf/
  flat <- list.files(file.path(index_root, "Figures"), pattern = "\\.pdf$",
                     full.names = TRUE)
  for (fp in flat) {
    file.copy(fp, file.path(pdf_dir, basename(fp)), overwrite = TRUE)
    unlink(fp)
  }
  have <- list.files(pdf_dir, pattern = "\\.pdf$")
  need <- paste0(stems, ".pdf")
  miss <- setdiff(need, have)
  extra <- setdiff(have, need)
  if (length(extra) && isTRUE(delete_extra)) {
    unlink(file.path(pdf_dir, extra))
    for (subdir in c("png", "tiff", "image_information")) {
      dd <- file.path(index_root, "Figures", subdir)
      if (!dir.exists(dd)) next
      for (ex in extra) {
        stem <- sub("\\.pdf$", "", ex, ignore.case = TRUE)
        unlink(list.files(dd, pattern = paste0("^", gsub("([.|()\\])", "\\\\\\1", stem)),
                          full.names = TRUE))
      }
    }
  }
  list(missing = miss, extra = extra, have = intersect(need, list.files(pdf_dir)))
}

#' 轨迹双库指标发表收口（对照 incidence_batch_finalize_index_outputs）
trajectory_batch_finalize_index_outputs <- function(index_root, config,
                                                   index_name = NULL,
                                                   dbs = NULL) {
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  ix <- as.character(
    index_name %||%
      gsub("^【success】|^【failed】", "", basename(index_root))
  )[1L]
  pub <- .trajectory_pub_cfg(config)
  if (!isTRUE(pub$enable)) {
    cli::cli_alert_info("trajectory_pub$enable=FALSE，跳过 finalize")
    return(invisible(FALSE))
  }
  root <- config$project$root %||% getwd()
  for (rel in c(
    "R/attrition_log.R",
    "R/pub_figure_export.R",
    "R/pub_xlsx_surgical.R",
    "R/dual_db_combine_figures.R",
    "R/trajectory_pub_curate.R",
    "R/trajectory_dual_pub_harmonize.R",
    "R/trajectory_survival_utils.R"
  )) {
    fp <- file.path(root, rel)
    if (file.exists(fp)) source(fp, local = FALSE)
  }
  dbs <- dbs %||% .trajectory_pub_db_slugs(index_root, config)
  cli::cli_h1("trajectory finalize [{ix}] dbs={paste(dbs, collapse=',')}")

  # 钉死类别标签：与 Table S5/S6/KM/Table3 同一原始 JLCM 编号（禁止 majority-swap）
  if (isTRUE(pub$skip_class_swap)) {
    config$trajectory <- config$trajectory %||% list()
    config$trajectory$skip_class_swap <- TRUE
    config$trajectory_plot_jlcm <- config$trajectory_plot_jlcm %||% list()
    config$trajectory_plot_jlcm$skip_class_swap <- TRUE
    config$trajectory_km_class <- config$trajectory_km_class %||% list()
    config$trajectory_km_class$skip_class_swap <- TRUE
  }

  # 0a) 无 Missing overview：注入默认 figure_stems（课题未覆盖时）
  if (isTRUE(pub$drop_missing_overview) &&
      (is.null(pub$figure_stems) || !length(pub$figure_stems)) &&
      exists("trajectory_paper_figure_stems_no_missing", mode = "function")) {
    config$trajectory_pub$figure_stems <- trajectory_paper_figure_stems_no_missing(
      ix, extra = pub$figure_extra %||% character(0)
    )
    pub <- .trajectory_pub_cfg(config)
    cli::cli_alert_info("已启用无 Missing overview 的发表图白名单（{length(pub$figure_stems)} 张）")
  }

  # 0) 分库 curate（若尚未）
  if (exists("trajectory_curate_pub_outputs", mode = "function")) {
    disease <- config$project$disease %||% "disease"
    disease <- gsub("_", " ", gsub("^\\d+_", "", as.character(disease)[1L]))
    tryCatch(
      trajectory_curate_pub_outputs(
        base_dir = index_root, index_name = ix, dbs = dbs, disease = disease
      ),
      error = function(e) cli::cli_alert_warning("curate: {conditionMessage(e)}")
    )
  }

  # 1) Fig1 CONSORT
  if (isTRUE(pub$fig1_consort)) {
    ok1 <- tryCatch(
      trajectory_ensure_fig1_consort(index_root, config, dbs),
      error = function(e) {
        cli::cli_alert_warning("Fig1 CONSORT: {conditionMessage(e)}")
        FALSE
      }
    )
    if (isTRUE(ok1)) cli::cli_alert_success("Fig1 CONSORT 已写入")
  }

  # 1b) 单库/网络盘兜底：db 级 Fig1 若仍是 PLACEHOLDER → 用 step24 真纳排图强制覆盖
  tryCatch(
    trajectory_fix_db_fig1_flowchart(index_root, dbs),
    error = function(e) cli::cli_alert_warning("fig1 fix: {conditionMessage(e)}")
  )

  # 1c) 课题自定义图号重排（config$trajectory_pub$figure_renumber）
  if (!is.null(pub$figure_renumber)) {
    tryCatch(
      trajectory_apply_figure_renumber(index_root, dbs, ix, pub$figure_renumber),
      error = function(e) cli::cli_alert_warning("renumber: {conditionMessage(e)}")
    )
  }

  # 2) 双库拼图（竖拼策略在 dual_db_combine_figures）
  if (isTRUE(pub$combine_figures) &&
      exists("dual_db_combine_paired_figures", mode = "function")) {
    cfg2 <- config
    cfg2$dual_db <- cfg2$dual_db %||% list()
    cfg2$dual_db$combine_figures <- modifyList(
      cfg2$dual_db$combine_figures %||% list(),
      list(
        layout_by_role = cfg2$dual_db$combine_figures$layout_by_role %||% list(
          Trajectory = "stack",
          Dynpred = "stack",
          "Dynamic prediction" = "stack",
          "Kaplan Meier" = "stack",
          "latent classes" = "stack"
        )
      )
    )
    tryCatch(
      dual_db_combine_paired_figures(index_root, cfg2),
      error = function(e) cli::cli_alert_warning("combine: {conditionMessage(e)}")
    )
  }

  # 2b) 单库：无配对可拼 → 把分库 Figure X-<DB>. 正式图镜像为根级无标签名
  #     （否则根 Figures 在 combine 关闭时永远为空，13 图闸门必报缺）
  if (length(dbs) == 1L) {
    tryCatch(
      trajectory_mirror_single_db_figures(index_root, ix, dbs[[1L]], config),
      error = function(e) cli::cli_alert_warning("single-db mirror: {conditionMessage(e)}")
    )
  }

  # 3) 共享切点 → 两库 Table3（同切点）+ 主库切点搜索单图
  #    mode="mimic"/主库 slug → 切点取主库最优；根 Tables 保留各库 Table3
  #    cut_search_fig_db → 仅切点搜索图留该库（默认=source_db）；勿删次库 Table3
  spc <- pub$shared_piecewise_cut
  if (isTRUE(spc$enable %||% TRUE)) {
    cut_mode <- spc$mode %||% "min_best"
    fig_db <- tolower(as.character(
      spc$cut_search_fig_db %||% spc$root_keep_db %||% ""
    )[1L])
    tryCatch({
      cut_info <- trajectory_resolve_shared_piecewise_cut(
        index_root, dbs, mode = cut_mode
      )
      if (nzchar(fig_db) && fig_db %in% names(cut_info$cuts)) {
        cut_info$source_db <- fig_db
        # 若 mode 已是某库，shared_cut 已是该库切点；仅当 mode=min_best 且
        # 指定 cut_search_fig_db 时，仍用 min_best 切点画该库的搜索图
      }
      trajectory_apply_shared_piecewise_cut(
        index_root, config, ix,
        cut_info = cut_info,
        max_followup = as.integer(
          config$trajectory_piecewise_cox$max_followup %||% 28L
        )
      )
      # 仅清理根 Figures 上非选型库的「分段 Cox 切点搜索」单图残留；保留双库 Table3
      if (nzchar(fig_db)) {
        fig_pdf <- file.path(index_root, "Figures/pdf")
        if (dir.exists(fig_pdf)) {
          keep_lab <- .trajectory_pub_db_lab(fig_db)
          for (f in list.files(fig_pdf, pattern = "Piecewise Cox cut", full.names = TRUE)) {
            bn <- basename(f)
            if (grepl(paste0("-", keep_lab, "\\."), bn)) next
            if (grepl("-(MIMIC|eICU|CHARLS)\\.", bn)) unlink(f)
          }
        }
      }
    }, error = function(e) cli::cli_alert_warning("shared_cut: {conditionMessage(e)}"))
  }

  # 4) 发表图白名单闸门
  if (isTRUE(pub$enforce_13_figures)) {
    chk <- trajectory_enforce_paper_figures(index_root, ix, delete_extra = TRUE,
                                            config = config)
    n_need <- length(trajectory_paper_figure_stems(ix, config))
    if (length(chk$missing)) {
      cli::cli_alert_warning("仍缺发表图: {paste(chk$missing, collapse=', ')}")
    } else {
      cli::cli_alert_success("发表图白名单齐 {n_need} 张")
    }
  }

  # 5) 四目录：用带 pdf/→平铺抢救的 ensure_formats（export_pub_figures 会先
  #    purge 再只扫平铺；单库镜像/拼图落在 pdf/ 会被误清空 → 判 0 张）
  if (isTRUE(pub$export_formats)) {
    fig_root <- file.path(index_root, "Figures")
    tryCatch(
      if (exists("pub_figure_ensure_formats", mode = "function")) {
        pub_figure_ensure_formats(fig_root, config = config)
      } else if (exists("export_pub_figures", mode = "function")) {
        export_pub_figures(fig_root, config = config)
      },
      error = function(e) cli::cli_alert_warning("pub_figure_ensure_formats: {conditionMessage(e)}")
    )
  }

  # 6) 表：去重 Platelet/BUN 双行、Table2 类占比按 class_align、根 Tables 重编
  if (isTRUE(pub$fix_tables %||% TRUE)) {
    tryCatch(
      trajectory_fix_and_sync_pub_tables(index_root, config, ix, dbs = dbs),
      error = function(e) cli::cli_alert_warning("fix_tables: {conditionMessage(e)}")
    )
  }

  # 7) 双库 Table1/S1/S2/S3/S5 行对齐（交集或 keep_vars；外科删行保样式）
  adt <- pub$align_dual_tables %||% list()
  if (isTRUE(adt$enable %||% FALSE) &&
      exists("trajectory_align_dual_root_tables", mode = "function") &&
      length(dbs) >= 2L) {
    tryCatch({
      db_labs <- vapply(dbs, .trajectory_pub_db_lab, character(1L))
      trajectory_align_dual_root_tables(
        index_root,
        db_labs = db_labs,
        kinds = as.character(
          adt$kinds %||% c("table1", "s1", "s2", "s3", "s5")
        ),
        keep_vars = adt$keep_vars,
        engine_root = root
      )
      cli::cli_alert_success("双库表行对齐完成（align_dual_tables）")
    }, error = function(e) {
      cli::cli_alert_warning("align_dual_tables: {conditionMessage(e)}")
    })
  }
  invisible(TRUE)
}

#' 若目标 xlsx 已无 SCI 样式（styleObjects 空），从候选原件恢复
.trajectory_restore_styled_xlsx_if_needed <- function(dest, candidates = character(0)) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  need <- TRUE
  if (file.exists(dest)) {
    n_st <- tryCatch(
      length(openxlsx::loadWorkbook(dest)$styleObjects),
      error = function(e) 0L
    )
    need <- !is.finite(n_st) || n_st < 1L
  }
  if (!isTRUE(need)) return(invisible(FALSE))
  cands <- unique(as.character(candidates))
  cands <- cands[file.exists(cands)]
  if (!length(cands)) return(invisible(FALSE))
  # 选样式最多的候选
  n_styles <- vapply(cands, function(f) {
    tryCatch(length(openxlsx::loadWorkbook(f)$styleObjects), error = function(e) 0L)
  }, integer(1L))
  if (!any(n_styles > 0L)) return(invisible(FALSE))
  src <- cands[[which.max(n_styles)]]
  ok <- file.copy(src, dest, overwrite = TRUE)
  if (isTRUE(ok)) {
    cli::cli_alert_info("已恢复 SCI 样式原件: {basename(dest)} ← {basename(src)}")
  }
  invisible(isTRUE(ok))
}

#' 从已有 SCI xlsx 删除指定行，保留边框/合并/列宽（禁止 createWorkbook 重写）
.trajectory_openxlsx_delete_rows <- function(wb, sheet = 1L, rows_delete) {
  rows_delete <- sort(unique(as.integer(rows_delete)))
  rows_delete <- rows_delete[is.finite(rows_delete) & rows_delete >= 1L]
  if (!length(rows_delete)) return(wb)
  sheet_names <- names(wb)
  sh_name <- if (is.character(sheet)) sheet else sheet_names[[as.integer(sheet)[1L]]]
  sh_i <- match(sh_name, sheet_names)
  if (is.na(sh_i)) return(wb)
  ws <- wb$worksheets[[sh_i]]
  sd <- ws$sheet_data
  if (is.null(sd) || !length(sd$rows)) return(wb)

  shift <- function(r) {
    r <- as.integer(r)
    r - sum(rows_delete < r)
  }
  keep <- !(as.integer(sd$rows) %in% rows_delete)
  n_old <- length(sd$rows)
  for (nm in c("rows", "cols", "t", "v", "f", "style_id")) {
    if (is.null(sd[[nm]]) || !length(sd[[nm]])) next
    if (length(sd[[nm]]) != n_old) next
    sd[[nm]] <- sd[[nm]][keep]
  }
  sd$rows <- as.integer(vapply(as.integer(sd$rows), shift, integer(1L)))
  if (!is.null(sd$n_elements)) sd$n_elements <- length(sd$rows)
  if (!is.null(sd$data_count)) sd$data_count <- length(unique(sd$rows))
  ws$sheet_data <- sd

  # mergeCells: <mergeCell ref="A97:E98"/>
  mc <- ws$mergeCells
  if (length(mc)) {
    .shift_ref <- function(ref) {
      # ref like A97:E98 or A1:E1
      m <- regmatches(ref, regexec("([A-Z]+)([0-9]+):([A-Z]+)([0-9]+)", ref, perl = TRUE))[[1]]
      if (length(m) < 5L) return(ref)
      r1 <- as.integer(m[3]); r2 <- as.integer(m[5])
      if (r1 %in% rows_delete || r2 %in% rows_delete) return(NA_character_)
      sprintf("%s%d:%s%d", m[2], shift(r1), m[4], shift(r2))
    }
    new_mc <- vapply(mc, function(x) {
      # x may be full XML tag
      if (grepl("ref=\"", x, fixed = TRUE)) {
        ref <- sub('.*ref="([^"]+)".*', "\\1", x)
        nr <- .shift_ref(ref)
        if (is.na(nr)) return(NA_character_)
        sub('ref="[^"]+"', paste0('ref="', nr, '"'), x)
      } else {
        .shift_ref(x)
      }
    }, character(1L))
    ws$mergeCells <- new_mc[!is.na(new_mc)]
  }

  # styleObjects row indices
  if (length(wb$styleObjects)) {
    for (i in seq_along(wb$styleObjects)) {
      so <- wb$styleObjects[[i]]
      if (!identical(so$sheet, sh_name)) next
      keep_s <- !(as.integer(so$rows) %in% rows_delete)
      so$rows <- as.integer(so$rows)[keep_s]
      so$cols <- as.integer(so$cols)[keep_s]
      if (length(so$rows)) so$rows <- as.integer(vapply(so$rows, shift, integer(1L)))
      wb$styleObjects[[i]] <- so
    }
    # drop empty style objs
    wb$styleObjects <- Filter(function(so) length(so$rows) > 0L, wb$styleObjects)
  }

  # dimension
  if (length(sd$rows) && length(sd$cols)) {
    ws$dimension <- sprintf(
      "A1:%s%d",
      openxlsx::int2col(max(as.integer(sd$cols), na.rm = TRUE)),
      max(as.integer(sd$rows), na.rm = TRUE)
    )
  }
  wb$worksheets[[sh_i]] <- ws
  wb
}

#' 就地改若干单元格值（不重建 workbook，保留 SCI 样式）
.trajectory_openxlsx_set_cell_values <- function(wb, sheet = 1L, row, cols, values) {
  row <- as.integer(row)[1L]
  cols <- as.integer(cols)
  values <- as.character(values)
  stopifnot(length(cols) == length(values))
  sh_name <- if (is.character(sheet)) sheet else names(wb)[[as.integer(sheet)[1L]]]
  # writeData 按列写入可保留其余样式
  for (j in seq_along(cols)) {
    openxlsx::writeData(
      wb, sheet = sh_name, x = values[[j]],
      startRow = row, startCol = cols[[j]], colNames = FALSE
    )
  }
  wb
}

#' 基线/按类表：删 PlateletCount（无空格）与 UreaNitrogen 重复行，保留 Platelet Count / BUN
#' 必须保留 SCI 三线表样式；禁止 createWorkbook 重写。
#' 注意：openxlsx::read.xlsx 的行号可能与 sheet_data 的 Excel 行号不一致，
#' 删除必须按 sharedStrings/单元格内容定位。
trajectory_xlsx_drop_lab_duplicate_rows <- function(path) {
  if (!file.exists(path)) return(invisible(FALSE))
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  wb <- tryCatch(openxlsx::loadWorkbook(path), error = function(e) NULL)
  if (is.null(wb)) return(invisible(FALSE))
  sh_name <- names(wb)[[1L]]
  ws <- wb$worksheets[[1L]]
  sd <- ws$sheet_data
  ss <- wb$sharedStrings
  if (is.null(sd) || !length(sd$rows)) return(invisible(FALSE))

  .cell_text <- function(v, t) {
    v <- as.character(v)[1L]
    t <- suppressWarnings(as.integer(t)[1L])
    # t==1 → shared string index
    if (is.finite(t) && identical(t, 1L)) {
      vi <- suppressWarnings(as.integer(v)[1L])
      if (!is.finite(vi) || vi < 0L || (vi + 1L) > length(ss)) return(NA_character_)
      raw <- ss[[vi + 1L]]
      # strip XML wrapper
      txt <- gsub("<[^>]+>", "", as.character(raw))
      return(trimws(txt))
    }
    trimws(v)
  }

  # 仅扫第 1 列标签
  rows_del <- integer(0)
  idx1 <- which(as.integer(sd$cols) == 1L)
  for (j in idx1) {
    lab <- .cell_text(sd$v[[j]], sd$t[[j]])
    if (!nzchar(lab) || is.na(lab)) next
    if (grepl("^PlateletCount(\\b|,|$)", lab) || grepl("^UreaNitrogen(\\b|,|$)", lab)) {
      rows_del <- c(rows_del, as.integer(sd$rows[[j]]))
    }
  }
  rows_del <- sort(unique(rows_del[is.finite(rows_del)]))
  if (!length(rows_del)) return(invisible(FALSE))

  wb <- .trajectory_openxlsx_delete_rows(wb, sheet = sh_name, rows_delete = rows_del)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  cli::cli_alert_info(
    "已去重实验室双行(保留样式): {basename(path)} (−{length(rows_del)} 行, excel_row={paste(rows_del, collapse=',')})"
  )
  invisible(TRUE)
}

#' 就地交换 Table2 指定 ng 行的 Class 占比列（按 class_map；保留 SCI 样式）
trajectory_xlsx_align_table2_class_props <- function(path, class_map, ng = 2L) {
  if (!file.exists(path) || is.null(class_map) || !length(class_map))
    return(invisible(FALSE))
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  if (all(as.character(names(class_map)) == as.character(unname(class_map))))
    return(invisible(FALSE))
  wb <- tryCatch(openxlsx::loadWorkbook(path), error = function(e) NULL)
  if (is.null(wb)) return(invisible(FALSE))
  d <- tryCatch(
    openxlsx::read.xlsx(path, sheet = 1, colNames = FALSE),
    error = function(e) NULL
  )
  if (is.null(d) || nrow(d) < 3L) return(invisible(FALSE))
  hdr_i <- which(apply(d, 1L, function(r) any(grepl("^Class\\s*1$", as.character(r)))))
  if (!length(hdr_i)) return(invisible(FALSE))
  hdr_i <- hdr_i[[1L]]
  hdr <- as.character(unlist(d[hdr_i, , drop = TRUE]))
  cls_cols <- which(grepl("^Class\\s*[0-9]+$", hdr))
  if (length(cls_cols) < 2L) return(invisible(FALSE))
  ng <- as.integer(ng)[1L]
  body_i <- which(suppressWarnings(as.integer(as.character(d[[1]]))) == ng)
  body_i <- body_i[body_i > hdr_i]
  if (!length(body_i)) return(invisible(FALSE))
  ri <- body_i[[1L]]
  old_props <- as.character(unlist(d[ri, cls_cols, drop = TRUE]))
  tmp <- old_props
  for (k in seq_along(cls_cols)) {
    old_k <- as.character(k)
    if (!old_k %in% names(class_map)) next
    new_k <- as.integer(unname(class_map[old_k]))
    if (is.finite(new_k) && new_k >= 1L && new_k <= length(tmp))
      tmp[new_k] <- old_props[k]
  }
  if (identical(tmp, old_props)) return(invisible(FALSE))
  wb <- .trajectory_openxlsx_set_cell_values(wb, sheet = 1L, row = ri, cols = cls_cols, values = tmp)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  cli::cli_alert_info(
    "Table2 Class占比已就地重排(保留样式) ng={ng}: {basename(path)} → {paste(tmp[seq_len(min(2L,length(tmp)))], collapse=' / ')}"
  )
  invisible(TRUE)
}

#' 分库 curate 后：去重、对齐 Table2、把正式表镜像到指标根 Tables/
trajectory_fix_and_sync_pub_tables <- function(index_root, config = NULL,
                                                 index_name = NULL,
                                                 dbs = NULL,
                                                 disease = NULL) {
  ix <- as.character(index_name %||% gsub("^【success】|^【failed】", "", basename(index_root)))[1L]
  dbs <- dbs %||% .trajectory_pub_db_slugs(index_root, config)
  if (is.null(disease) || !nzchar(as.character(disease)[1L])) {
    disease <- config$project$disease %||% "disease"
    disease <- gsub("_", " ", gsub("^\\d+_", "", as.character(disease)[1L]))
  }
  root <- config$project$root %||% getwd()
  for (rel in c("R/trajectory_pub_curate.R", "R/trajectory_paper_tables.R",
                "R/trajectory_survival_utils.R")) {
    fp <- file.path(root, rel)
    if (file.exists(fp)) source(fp, local = FALSE)
  }

  # 分库整理 + 内容修补（禁止 force 重导 Table2/S8 冲掉 SCI 样式；只就地改单元格）
  for (db in dbs) {
    db_lab <- .trajectory_pub_db_lab(db)
    unit <- file.path(index_root, db)
    tab <- file.path(unit, "Tables")
    if (!dir.exists(tab)) next
    if (exists("trajectory_curate_tables_dir", mode = "function")) {
      tryCatch(
        trajectory_curate_tables_dir(tab, db_lab, ix, disease = disease),
        error = function(e) cli::cli_alert_warning("curate {db}: {conditionMessage(e)}")
      )
    }
    cmap <- NULL
    if (exists("trajectory_read_class_align_map", mode = "function")) {
      cmap <- trajectory_read_class_align_map(index_root, ix, db_lab = db_lab, db_slug = db)
    }
    # Table2：必须先恢复「未对齐」原件，再就地改 Class 占比（避免二次对调）
    t2 <- file.path(tab, sprintf(
      "Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab
    ))
    if (file.exists(t2) && !is.null(cmap) && length(cmap)) {
      cands_t2 <- c(
        file.path(index_root, "Tables/_archive_messy", basename(t2)),
        file.path(tab, "_archive", basename(t2))
      )
      # 恒等 map 无需动；非恒等则强制用归档原件覆盖后再对齐一次
      is_identity <- all(as.character(names(cmap)) == as.character(unname(cmap)))
      if (!is_identity) {
        srcs <- cands_t2[file.exists(cands_t2)]
        if (length(srcs)) {
          # 选样式最多且 Class1 占比仍为「原始」的（通常归档未对齐）
          file.copy(srcs[[1L]], t2, overwrite = TRUE)
          cli::cli_alert_info("Table2 已从归档原件重置: {basename(t2)}")
        }
      } else {
        .trajectory_restore_styled_xlsx_if_needed(t2, candidates = cands_t2)
      }
      trajectory_xlsx_align_table2_class_props(t2, cmap, ng = length(cmap))
    }
    # 去重：Table1 / S1 插补 / S7 按类（先恢复样式原件再删行）
    restore_map <- list(
      list(
        pat = sprintf("^Table 1-%s\\..*Baseline", db_lab),
        arch = c(
          sprintf("Table 1-%s. Baseline characteristics of %s.xlsx", db_lab, disease),
          sprintf("Table 1-%s. Baseline characteristics", db_lab)
        )
      ),
      list(
        pat = sprintf("^Table S1-%s\\..*imputation", db_lab),
        arch = c(
          sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab),
          sprintf("Table S3-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab)
        )
      ),
      list(
        pat = sprintf("^Table S7-%s\\..*trajectory class", db_lab),
        arch = c(
          sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix),
          sprintf("Table S16-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix)
        )
      )
    )
    for (rm in restore_map) {
      hits <- list.files(tab, pattern = rm$pat, full.names = TRUE)
      hits <- hits[!grepl("/_archive/", hits)]
      for (h in hits) {
        cands <- unique(c(
          file.path(index_root, "Tables/_archive_messy", basename(h)),
          file.path(tab, "_archive", basename(h)),
          file.path(index_root, "Tables/_archive_messy", rm$arch),
          file.path(tab, "_archive", rm$arch)
        ))
        .trajectory_restore_styled_xlsx_if_needed(h, candidates = cands)
        trajectory_xlsx_drop_lab_duplicate_rows(h)
      }
    }
  }

  # 根 Tables：归档乱号 → 从分库拷正式白名单
  root_tab <- file.path(index_root, "Tables")
  dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
  arch <- file.path(root_tab, "_archive_messy")
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  keep_summary <- file.path(root_tab, "Summary")
  for (f in list.files(root_tab, full.names = TRUE)) {
    bn <- basename(f)
    if (identical(bn, "_archive_messy") || identical(bn, "Summary") ||
        identical(bn, "README.md")) next
    if (dir.exists(f)) next
    dest <- file.path(arch, bn)
    if (file.exists(dest)) {
      # 勿用无样式新文件覆盖带 SCI 样式的归档原件
      n_old <- tryCatch(length(openxlsx::loadWorkbook(dest)$styleObjects), error = function(e) 0L)
      n_new <- tryCatch(length(openxlsx::loadWorkbook(f)$styleObjects), error = function(e) 0L)
      if (isTRUE(n_old > n_new)) {
        unlink(f)
        next
      }
      unlink(dest)
    }
    file.rename(f, dest)
  }

  canon_one <- function(db_lab) {
    c(
      sprintf("Table 1-%s. Baseline characteristics of %s.xlsx", db_lab, disease),
      sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab),
      sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
      sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab),
      sprintf("Table S2-%s. Normality test results for continuous variables.xlsx", db_lab),
      sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
      sprintf("Table S4-%s. Multicollinearity Analysis (VIF, univariate screen).xlsx", db_lab),
      sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db_lab),
      sprintf("Table S6-%s. Multicollinearity Analysis (VIF, multivariate final).xlsx", db_lab),
      sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix),
      sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab)
    )
  }
  # Table1 实际文件名可能与 disease 字符串不完全一致 → 宽松匹配拷贝
  n_copy <- 0L
  for (db in dbs) {
    db_lab <- .trajectory_pub_db_lab(db)
    tab <- file.path(index_root, db, "Tables")
    for (nm in canon_one(db_lab)) {
      src <- file.path(tab, nm)
      if (!file.exists(src)) {
        # 宽松：同角色前缀
        pref <- sub("\\.xlsx$", "", nm)
        # Table 1 特殊：Baseline characteristics*
        if (grepl("^Table 1-", nm)) {
          alt <- list.files(tab, pattern = sprintf("^Table 1-%s\\..*Baseline characteristics", db_lab),
                            full.names = TRUE)
          alt <- alt[!grepl("/_archive/", alt)]
          if (length(alt)) src <- alt[[1L]]
        } else if (grepl("^Table S1-", nm)) {
          alt <- list.files(tab, pattern = sprintf("^Table S1-%s\\..*imputation", db_lab),
                            full.names = TRUE)
          if (length(alt)) src <- alt[[1L]]
        } else if (grepl("^Table S7-", nm)) {
          alt <- list.files(tab, pattern = sprintf("^Table S7-%s\\..*trajectory class", db_lab),
                            full.names = TRUE)
          if (length(alt)) src <- alt[[1L]]
        }
      }
      if (!file.exists(src)) {
        cli::cli_alert_warning("缺表未镜像: {nm}")
        next
      }
      # 根目录用正式白名单文件名
      dest <- file.path(root_tab, nm)
      # 若源名不同，仍写入白名单名
      if (grepl("^Table 1-", nm) && !identical(basename(src), nm)) {
        dest <- file.path(root_tab, basename(src))
      }
      file.copy(src, dest, overwrite = TRUE)
      n_copy <- n_copy + 1L
    }
  }
  readme <- file.path(root_tab, "README.md")
  writeLines(c(
    sprintf("# Tables（%s 发表用）", ix),
    "",
    "根目录表与分库 `eicu/Tables`、`mimic/Tables` 同号同角色。",
    "",
    "| 编号 | 内容 |",
    "|---|---|",
    "| Table 1 | 基线特征 |",
    "| Table 2 | 选类指标（m1–m6）；Class 占比已按 class_align 与 Fig2 对齐 |",
    "| Table 3 | 分段/时变 HR |",
    "| Table S1 | 插补前后基线 |",
    "| Table S2 | 正态性 |",
    "| Table S3 | 单因素 |",
    "| Table S4 | VIF（单因素筛） |",
    "| Table S5 | 多因素 |",
    "| Table S6 | VIF（多因素终） |",
    "| Table S7 | 按轨迹类基线 |",
    "| Table S8 | 后验分类表 |",
    "",
    "旧乱号表已移至 `_archive_messy/`。",
    sprintf("整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ), readme)
  cli::cli_alert_success("根 Tables 已同步 {n_copy} 个正式表（S1–S8）")
  invisible(list(n_copy = n_copy, root_tab = root_tab))
}
