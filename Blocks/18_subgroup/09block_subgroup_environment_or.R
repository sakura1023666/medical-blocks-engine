###############################################################################
#  subgroup_environment_or — 环境暴露 VOC 亚组分层单因素 OR 横向比较表
#
#  register_block: "subgroup_environment_or"
#  典型流水线: glm_environment_quartile → subgroup_environment_or
#
#  功能：
#    按指定分层变量（Gender/Race/PIR/Smoked 等）将数据分割为若干水平，
#    对每个水平分别运行每个 VOC 的单因素 logistic 回归，
#    提取 OR、95%CI、P 值及均值±SD，
#    将所有分层水平的结果横向 cbind 后导出 SCI 三线表（xlsx）。
#
#  封装来源（4 个脚本统一为 1 个通用 Block）：
#    SubGroup_Gender.R / SubGroup_PIR.R / SubGroup_Race.R / SubGroup_Smoked.R
#
#  # ── Bug 修复说明（相对原脚本）────────────────────────────────────────────
#  Bug 1: pvalue <- fit$coefficients[8] 计算后从未使用（死代码）→ 删除
#  Bug 2: attach(df) / detach(df) 不推荐，易导致环境污染 →
#         改用 glm(formula, data = df_sub) 直接传数据框
#  Bug 3: mean(df[,i][...]) 无 na.rm = TRUE，VOC 含 NA 时返回 NA →
#         改为 mean(x, na.rm = TRUE)
#  Bug 4: glm() 无错误处理，完全分离（perfect separation）时报错中断 →
#         tryCatch 包裹，跳过异常 VOC
#  Bug 5: Excel 导出中 cols = (2+5): 硬编码每分层 5 列 →
#         改为动态计算每分层实际列数
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#                        （需同时含临床变量列 + VOC 列）
#  require_ctx_results = select_vocs_final（或 select_vocs）
#
#  # ── 配置 config$subgroup_environment_or ─────────────────────────────────
#  subgroup_environment_or = list(
#    stratify_col    = NULL,    # 分层列名，如 "Gender" / "Race" / "PIR" / "Smoked"
#                               # 必填，不指定则报错
#    strata_levels   = NULL,    # 分层水平向量；NULL = 自动检测 unique(data[[stratify_col]])
#    strata_labels   = NULL,    # 展示标签向量（长度须与 strata_levels 一致）；
#                               # NULL = 使用 strata_levels 原值作为标题
#    select_vocs     = NULL,    # VOC 列名；NULL = ctx$results$select_vocs_final
#    outcome_col     = NULL,    # 结局列名；NULL = config$data$outcome_column
#    analysis_group  = NULL,    # 病例组标签
#    reference_group = NULL,    # 对照组标签
#    label_mapping   = NULL,    # VOC 展示名映射 c(内部列名 = "展示名")；可选
#    table_filename  = NULL,    # NULL = "Table_Subgroup_{stratify_col}.xlsx"
#    table_title     = NULL     # 表格标题
#  ),
#
#  # ── 快速配置示例 ──────────────────────────────────────────────────────────
#  # Gender:  stratify_col="Gender", strata_levels=c("Male","Female")
#  # PIR:     stratify_col="PIR",    strata_levels=c("> 3.5","1.3-3.5","≤ 1.3")
#  # Race:    stratify_col="Race",   strata_levels=c("Mexican American",
#  #           "Non-Hispanic Black","Non-Hispanic White","Other Hispanic","Other Race")
#  # Smoked:  stratify_col="Smoked", strata_levels=c("nonSmoked","Smoked")
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$subgroup_or_tables  — 命名列表，每个元素为一个分层水平的 OR 表
#      ctx$results$subgroup_or_combined — cbind 后的最终宽表
#  文件: Tables/Table_Subgroup_{stratify_col}.xlsx
###############################################################################

# ── 辅助：二值化结局（0=对照，1=病例）────────────────────────────────────────
.seo09_binarize_outcome <- function(data, outcome_col, analysis_grp, reference_grp) {
  y <- data[[outcome_col]]
  if (is.numeric(y) && all(stats::na.omit(unique(y)) %in% c(0, 1))) {
    data[[outcome_col]] <- as.integer(y)
    return(data)
  }
  yc <- trimws(as.character(y))
  data[[outcome_col]] <- ifelse(
    yc == trimws(analysis_grp), 1L,
    ifelse(yc == trimws(reference_grp), 0L, NA_integer_)
  )
  data
}

# ── 辅助：对单个分层水平运行所有 VOC 的单因素 GLM ──────────────────────────
.seo09_run_stratum_glm <- function(data_sub, select_vocs, outcome_col,
                                    analysis_grp, reference_grp) {
  data_sub <- .seo09_binarize_outcome(data_sub, outcome_col, analysis_grp, reference_grp)
  data_sub <- data_sub[!is.na(data_sub[[outcome_col]]), , drop = FALSE]
  if (!nrow(data_sub)) return(data.frame())

  rows <- list()
  for (voc in select_vocs) {
    if (!voc %in% names(data_sub)) next

    x <- data_sub[[voc]]
    if (all(is.na(x)) || stats::var(x, na.rm = TRUE) == 0) {
      cli::cli_alert_warning("  [{voc}] 方差为 0 或全 NA，跳过")
      next
    }

    fml <- stats::as.formula(paste0(outcome_col, " ~ `", voc, "`"))

    fit <- tryCatch(
      stats::glm(fml, data = data_sub, family = stats::binomial(link = "logit")),
      error   = function(e) { cli::cli_alert_warning("  [{voc}] glm 失败: {e$message}"); NULL },
      warning = function(w) {
        suppressWarnings(
          stats::glm(fml, data = data_sub, family = stats::binomial(link = "logit"))
        )
      }
    )
    if (is.null(fit)) next

    sm  <- summary(fit)$coefficients
    if (nrow(sm) < 2L) next

    OR   <- round(exp(stats::coef(fit)), 2L)
    SE   <- sm[, 2L]
    CI_l <- round(exp(stats::coef(fit) - 1.96 * SE), 2L)
    CI_u <- round(exp(stats::coef(fit) + 1.96 * SE), 2L)
    CI   <- paste0(CI_l, "-", CI_u)
    P    <- round(sm[, 4L], 3L)

    res  <- data.frame(OR = OR, CI = CI, P = P, stringsAsFactors = FALSE)[-1L, ]
    res$Environmental_Toxicants <- voc

    y_bin <- data_sub[[outcome_col]]
    x_ref  <- x[y_bin == 0L]
    x_case <- x[y_bin == 1L]
    mean_ref  <- round(mean(x_ref,  na.rm = TRUE), 4L)
    sd_ref    <- round(sd(x_ref,    na.rm = TRUE), 4L)
    mean_case <- round(mean(x_case, na.rm = TRUE), 4L)
    sd_case   <- round(sd(x_case,   na.rm = TRUE), 4L)

    res[[reference_grp]] <- paste0(mean_ref,  "\u00b1", sd_ref)
    res[[analysis_grp]]  <- paste0(mean_case, "\u00b1", sd_case)

    res <- res[, c("Environmental_Toxicants", analysis_grp, reference_grp, "OR", "CI", "P")]
    names(res)[names(res) == "P"] <- "P value"
    rownames(res) <- NULL
    rows[[length(rows) + 1L]] <- res
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

# ── 辅助：openxlsx SCI 三线表（支持双级表头）─────────────────────────────────
.seo09_export_xlsx <- function(df, filepath, table_title,
                                strata_labels, n_cols_per_strata, n_id_cols = 1L) {
  library(openxlsx)
  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")

  # 数据写入从第 3 行开始（第 1 行: 标题, 第 2 行: 分层标签）
  writeData(wb, "Sheet1", df,
            startRow = 3L, startCol = 1L, rowNames = FALSE)
  writeData(wb, "Sheet1", table_title, startRow = 1L, startCol = 1L)
  mergeCells(wb, "Sheet1", cols = 1:ncol(df), rows = 1L)

  # 写入分层标签（第 2 行，跳过第 1 个 ID 列）
  col_start <- n_id_cols + 1L
  for (i in seq_along(strata_labels)) {
    col_end <- col_start + n_cols_per_strata - 1L
    writeData(wb, "Sheet1", strata_labels[i], startRow = 2L, startCol = col_start)
    mergeCells(wb, "Sheet1", cols = col_start:col_end, rows = 2L)
    col_start <- col_end + 1L
  }

  n_col <- ncol(df)
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", halign = "center")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               halign = "center", valign = "center")
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  addStyle(wb, "Sheet1", title_style,  rows = 1L, cols = 1:n_col, gridExpand = TRUE)

  # 第 2 行分层标签
  col_s2 <- n_id_cols + 1L
  for (i in seq_along(strata_labels)) {
    col_e2 <- col_s2 + n_cols_per_strata - 1L
    addStyle(wb, "Sheet1", header_style, rows = 2L, cols = col_s2:col_e2, gridExpand = TRUE)
    col_s2 <- col_e2 + 1L
  }

  addStyle(wb, "Sheet1", title_style, rows = 3L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,
           rows = 4L:(nrow(df) + 3L), cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = nrow(df) + 4L, cols = 1:(n_col + 1L), gridExpand = FALSE)

  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:(n_col + 1L), widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 30)
  if (n_col >= 2L) setColWidths(wb, "Sheet1", cols = 2L, widths = 20)
  if (n_col >= 3L) setColWidths(wb, "Sheet1", cols = 3L, widths = 20)

  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_subgroup_environment_or <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$subgroup_environment_or %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("subgroup_environment_or: \u672a\u627e\u5230\u6570\u636e\uff0c\u8bf7\u5148\u8fd0\u884c\u4e0a\u6e38\u6570\u636e\u51c6\u5907 block\u3002")
  }

  # ── 分层变量 ─────────────────────────────────────────────────────────────
  stratify_col <- as.character(bl_cfg$stratify_col %||% "")
  if (!nzchar(stratify_col)) {
    stop("subgroup_environment_or: \u8bf7\u5728 config$subgroup_environment_or$stratify_col \u4e2d\u6307\u5b9a\u5206\u5c42\u53d8\u91cf\u5217\u540d\u3002")
  }
  if (!stratify_col %in% names(data)) {
    stop("subgroup_environment_or: \u5206\u5c42\u5217 '", stratify_col, "' \u4e0d\u5728\u6570\u636e\u4e2d\u3002")
  }

  # 自动检测分层水平
  strata_levels <- bl_cfg$strata_levels
  if (is.null(strata_levels) || !length(strata_levels)) {
    strata_levels <- as.character(unique(stats::na.omit(data[[stratify_col]])))
    strata_levels <- sort(strata_levels)
    cli::cli_alert_info(
      "subgroup_environment_or: \u81ea\u52a8\u68c0\u6d4b\u5230 {stratify_col} \u7684 {length(strata_levels)} \u4e2a\u6c34\u5e73: {paste(strata_levels, collapse=', ')}"
    )
  } else {
    strata_levels <- as.character(strata_levels)
  }

  strata_labels <- bl_cfg$strata_labels
  if (is.null(strata_labels) || length(strata_labels) != length(strata_levels)) {
    strata_labels <- strata_levels
  } else {
    strata_labels <- as.character(strata_labels)
  }

  # ── 结局和分组 ───────────────────────────────────────────────────────────
  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")
  if (!outcome_col %in% names(data)) {
    stop("subgroup_environment_or: \u7ed3\u5c40\u5217 '", outcome_col, "' \u4e0d\u5728\u6570\u636e\u4e2d\u3002")
  }

  # ── VOC 列表（仅环境毒物）────────────────────────────────────────────────
  select_vocs <- as.character(
    bl_cfg$select_vocs %||%
    ctx$results$select_vocs_wqs %||%
    ctx$results$select_vocs_final %||%
    ctx$results$select_vocs %||%
    character(0)
  )
  if (exists("environment_intersect_voc_only", mode = "function")) {
    select_vocs <- environment_intersect_voc_only(select_vocs, data, cfg)
  }
  if (exists("environment_resolve_mixture_vocs", mode = "function")) {
    select_vocs <- environment_resolve_mixture_vocs(
      ctx, data, cfg, "glm_environment_quartile", bl_select = select_vocs
    )$vocs
  }
  select_vocs <- unique(select_vocs[nzchar(select_vocs)])
  select_vocs <- intersect(select_vocs, names(data))
  if (!length(select_vocs)) {
    stop("subgroup_environment_or: select_vocs \u4e3a\u7a7a\u3002")
  }

  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$label_mapping)
  } else {
    bl_cfg$label_mapping
  }

  cli::cli_h2(
    "subgroup_environment_or: {stratify_col} ({length(strata_levels)} \u4e2a\u6c34\u5e73) × {length(select_vocs)} \u4e2a VOC"
  )

  # ── 逐分层运行 GLM ────────────────────────────────────────────────────────
  strata_tables <- list()

  for (lvl in strata_levels) {
    cli::cli_alert_info("  \u5206\u5c42: {stratify_col} == '{lvl}'")
    data_sub <- data[!is.na(data[[stratify_col]]) &
                     trimws(as.character(data[[stratify_col]])) == trimws(lvl), ,
                     drop = FALSE]

    if (nrow(data_sub) < 10L) {
      cli::cli_alert_warning("  [{lvl}] \u6837\u672c\u91cf\u4e0d\u8db3 10\uff0c\u8df3\u8fc7\u3002")
      next
    }
    cli::cli_alert_info("  [{lvl}] n = {nrow(data_sub)}")

    res_lvl <- .seo09_run_stratum_glm(
      data_sub, select_vocs, outcome_col, analysis_grp, reference_grp
    )
    if (!nrow(res_lvl)) {
      cli::cli_alert_warning("  [{lvl}] \u65e0\u6709\u6548\u7ed3\u679c\u3002")
      next
    }

    # 应用标签映射
    if (!is.null(label_map) && length(label_map)) {
      res_lvl$Environmental_Toxicants <- vapply(
        res_lvl$Environmental_Toxicants, function(x) {
          if (x %in% names(label_map)) as.character(label_map[[x]]) else x
        }, character(1L)
      )
    }

    strata_tables[[lvl]] <- res_lvl
    cli::cli_alert_success("  [{lvl}] \u5b8c\u6210\uff0c{nrow(res_lvl)} \u884c")
  }

  if (!length(strata_tables)) {
    if (isTRUE(bl_cfg$allow_empty_strata %||% FALSE)) {
      cli::cli_alert_warning(
        "subgroup_environment_or: 所有分层均未产生有效结果，已跳过（allow_empty_strata=TRUE）。"
      )
      ctx$results$subgroup_or_tables <- list()
      ctx$results$subgroup_or_combined <- NULL
      return(ctx)
    }
    stop("subgroup_environment_or: \u6240\u6709\u5206\u5c42\u5747\u672a\u4ea7\u751f\u6709\u6548\u7ed3\u679c\u3002")
  }

  ctx$results$subgroup_or_tables <- strata_tables

  # ── cbind 所有分层结果 ───────────────────────────────────────────────────
  valid_levels  <- names(strata_tables)
  first_lvl     <- valid_levels[1L]
  first_tbl     <- strata_tables[[first_lvl]]

  # 第一个分层保留 Environmental_Toxicants 列，其余去掉
  combined <- first_tbl
  n_id_cols <- 1L  # Environmental_Toxicants
  n_data_cols <- ncol(first_tbl) - n_id_cols  # OR/CI/P/Analysis/Reference = 5

  for (lvl in valid_levels[-1L]) {
    tbl_i <- strata_tables[[lvl]]
    combined <- cbind(combined,
                      tbl_i[, -1L, drop = FALSE])
  }

  ctx$results$subgroup_or_combined <- combined

  # ── 导出 Excel ────────────────────────────────────────────────────────────
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_fn  <- as.character(
    bl_cfg$table_filename %||%
    paste0("Table_Subgroup_", stratify_col, ".xlsx")
  )
  tbl_path <- file.path(tbl_dir, tbl_fn)
  disease_name <- as.character(
    cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  )
  tbl_title <- as.character(
    bl_cfg$table_title %||%
    paste0("Table. Subgroup analysis by ", stratify_col,
           " of environmental toxicants association with ", disease_name)
  )

  tryCatch({
    # 修复 Bug 5：动态计算每分层列数，不硬编码 5
    .seo09_export_xlsx(
      df               = combined,
      filepath         = tbl_path,
      table_title      = tbl_title,
      strata_labels    = valid_levels,  # 使用实际跑出的分层水平
      n_cols_per_strata = n_data_cols,
      n_id_cols        = n_id_cols
    )
    cli::cli_alert_success("{tbl_fn} \u5df2\u5c55\u5b58")
  }, error = function(e) {
    cli::cli_alert_warning("subgroup_environment_or: Excel \u5c55\u5b58\u5931\u8d25: {e$message}")
  })

  cli::cli_alert_success(
    "subgroup_environment_or \u5b8c\u6210: {length(valid_levels)} \u4e2a\u5206\u5c42\uff0c{nrow(combined)} \u884c VOC\u3002"
  )
  ctx
}

register_block(
  "subgroup_environment_or",
  block_subgroup_environment_or,
  "\u73af\u5883 VOC \u4e9a\u7ec4\u5206\u5c42\u5355\u56e0\u7d20 OR \u8868\uff08\u53ef\u914d\u7f6eGender/Race/PIR/Smoked\u7b49\u4efb\u610f\u5206\u5c42\u53d8\u91cf\uff09"
)
