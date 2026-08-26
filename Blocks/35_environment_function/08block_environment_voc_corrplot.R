###############################################################################
#  environment_voc_corrplot — Spearman 相关矩阵可视化（VOC + Baseline 双图）
#
#  register_block: "environment_voc_corrplot"
#  典型流水线: multicollinearity_nhanes_final → environment_voc_corrplot → environment_voc_clinical_gate
#
#  功能：
#    分别对"通过单因素筛选的 VOC 变量"和"通过 VIF 筛选的基线变量"
#    计算 Spearman 相关矩阵并绘制 corrplot PDF；
#    导出两张相关系数表格（Table 2-VOC、Table 2-Baseline），
#    同时向 ctx 写入相关矩阵供下游临床门禁使用。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx  = voc_columns（来自 environment_lod_screen）
#                 tb1 / vif_final_pass（来自 univariate/multicollinearity）
#
#  # ── 配置 config$environment_corrplot ─────────────────────────────────────
#  environment_corrplot = list(
#    enable           = TRUE,
#    method           = "spearman",       # pearson | spearman
#    voc_source       = "tb1_voc",        # "tb1_voc"=单因素VOC, "voc_columns"=全量VOC
#    baseline_source  = "vif_final_pass", # "vif_final_pass" | "tb1"
#    table_prefix     = "Table 2",        # 两张表的公共前缀
#    col_neg          = "#B2182B",
#    col_pos          = "#2166AC",
#    fig_width_voc    = 8.5,
#    fig_width_base   = 11
#  )
#
#  # ── 产出 ─────────────────────────────────────────────────────────────────
#  ctx$results$corrplot_voc_matrix    — VOC Spearman r 矩阵
#  ctx$results$corrplot_base_matrix   — Baseline Spearman r 矩阵
#  Tables/Table 2-VOC.xlsx
#  Tables/Table 2-Baseline.xlsx
#  Figures/Figure Corrplot VOC.pdf
#  Figures/Figure Corrplot Baseline.pdf
###############################################################################

.corrplot_to_num <- function(df, vs) {
  M <- as.data.frame(df[, vs, drop = FALSE], stringsAsFactors = FALSE)
  for (v in vs) {
    x <- M[[v]]
    if (!is.numeric(x)) M[[v]] <- suppressWarnings(as.integer(factor(x)))
  }
  M
}

.corrplot_draw <- function(R, P, title, method, wh, cfg) {
  col_neg <- as.character(cfg$col_neg %||% "#B2182B")
  col_pos <- as.character(cfg$col_pos %||% "#2166AC")
  col_br <- grDevices::colorRampPalette(c(col_neg, "#EF8A62", "#FDDBC7",
    "#FFFFFF", "#D1E5F0", "#67A9CF", col_pos))(200)
  corrplot::corrplot(
    R,
    method = "color",
    type = "upper",
    order = "hclust",
    addCoef.col = "black",
    number.cex = if (ncol(R) > 15) 0.55 else 0.78,
    number.font = 1,
    tl.col = "black",
    tl.cex = if (ncol(R) > 15) 0.8 else 1.0,
    tl.srt = 45,
    col = col_br,
    cl.cex = 1.0,
    cl.align.text = "c",
    mar = c(0, 0, 2, 0),
    title = title
  )
  n_samp <- attr(P, "n") %||% nrow(P)
  graphics::mtext(
    paste0("Spearman correlation (red=negative, blue=positive). ",
           "Categorical variables encoded by level code. n=", n_samp),
    side = 1, cex = 0.65, line = 0
  )
}

.corrplot_export_table <- function(R, P, vars, domain_label, tbl_dir, cfg) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    out_csv <- file.path(tbl_dir, paste0(domain_label, ".csv"))
    utils::write.csv(round(R, 4), out_csv)
    return(invisible(out_csv))
  }
  prefix <- as.character(cfg$table_prefix %||% "Table 2")
  filename <- paste0(prefix, "-", domain_label, ".xlsx")
  path <- file.path(tbl_dir, filename)

  r_df <- as.data.frame(round(R, 4))
  r_df <- cbind(Variable = rownames(r_df), r_df)

  p_df <- as.data.frame(round(P, 4))
  p_df <- cbind(Variable = rownames(p_df), p_df)

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Correlation_r")
  openxlsx::addWorksheet(wb, "P_value")
  title_r <- paste0(prefix, ". ", domain_label, " — Spearman Correlation Coefficient (r)")
  title_p <- paste0(prefix, ". ", domain_label, " — Spearman Correlation P-value")
  openxlsx::writeData(wb, "Correlation_r", title_r,    startRow = 1L)
  openxlsx::writeData(wb, "Correlation_r", r_df,       startRow = 2L)
  openxlsx::writeData(wb, "P_value",       title_p,    startRow = 1L)
  openxlsx::writeData(wb, "P_value",       p_df,       startRow = 2L)

  tbl_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, halign = "center", valign = "center"
  )
  hdr_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    halign = "center", valign = "center"
  )
  title_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    border = "bottom", halign = "left"
  )
  for (ws in c("Correlation_r", "P_value")) {
    n_rows <- nrow(r_df) + 2L
    n_cols <- ncol(r_df)
    openxlsx::addStyle(wb, ws, tbl_style, rows = 1:n_rows, cols = 1:n_cols, gridExpand = TRUE)
    openxlsx::addStyle(wb, ws, hdr_style, rows = 2L, cols = 1:n_cols)
    openxlsx::addStyle(wb, ws, title_style, rows = 1L, cols = 1L)
    openxlsx::setColWidths(wb, ws, cols = 1:n_cols, widths = "auto")
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  cli::cli_alert_success("corrplot 表格: {basename(path)}")
  invisible(path)
}

block_environment_voc_corrplot <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$environment_corrplot %||% list()
  if (!isTRUE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("environment_voc_corrplot: enable=FALSE，跳过。")
    return(ctx)
  }
  if (!requireNamespace("corrplot", quietly = TRUE)) {
    cli::cli_alert_warning("environment_voc_corrplot: 需要 corrplot 包（install.packages('corrplot')）。跳过。")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    cli::cli_alert_warning("environment_voc_corrplot: 无数据，跳过。")
    return(ctx)
  }

  method   <- as.character(bl$method %||% "spearman")
  tbl_dir  <- ctx$output_dir_tables  %||% file.path(ctx$output_dir %||% ".", "Tables")
  fig_dir  <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. 确定 VOC 变量集 ──────────────────────────────────────────────────
  voc_source <- as.character(bl$voc_source %||% "tb1_voc")
  voc_vars <- switch(voc_source,
    tb1_voc = {
      v <- as.character(ctx$results$tb1_voc_univariate %||%
             ctx$results$select_vocs_lod %||%
             ctx$results$voc_columns %||% character(0))
      intersect(v, names(data))
    },
    voc_columns = intersect(
      as.character(ctx$results$voc_columns %||% character(0)),
      names(data)
    ),
    clinical_gate = intersect(
      as.character(ctx$results$select_vocs_clinical_gate %||% character(0)),
      names(data)
    ),
    intersect(
      as.character(ctx$results$select_vocs_clinical_gate %||%
                   ctx$results$voc_columns %||% character(0)),
      names(data)
    )
  )
  voc_vars <- voc_vars[vapply(voc_vars, function(v) {
    x <- data[[v]]
    is.numeric(x) && sum(is.finite(x)) >= 10L
  }, logical(1L))]

  # ── 2. 确定 Baseline 变量集 ─────────────────────────────────────────────
  base_source <- as.character(bl$baseline_source %||% "vif_final_pass")
  base_vars <- switch(base_source,
    vif_final_pass = as.character(ctx$results$vif_final_pass %||% character(0)),
    tb1            = as.character(ctx$results$tb1            %||% character(0)),
    as.character(ctx$results$vif_final_pass %||% ctx$results$tb1 %||% character(0))
  )
  # 剔除 VOC、outcome、权重元数据（cycle/Source_File 仅用于权重计算，不作协变量、不出图）
  excl_pat <- "^(new_Weight|SEQN|ID|SDMVPSU|SDMVSTRA|Source_File|SDDSRVYR|cycle|Group|DN|WTMEC|WTSA|WTINT|WTSAF|SDDS)$"
  base_vars <- setdiff(base_vars, voc_vars)
  base_vars <- base_vars[!grepl(excl_pat, base_vars, ignore.case = TRUE)]
  base_vars <- intersect(base_vars, names(data))
  if (!length(base_vars)) {
    base_vars <- intersect(
      as.character(ctx$results$tb1 %||% character(0)),
      names(data)
    )
    base_vars <- setdiff(base_vars, c(voc_vars, grep(excl_pat, base_vars, value = TRUE)))
    base_vars <- base_vars[seq_len(min(length(base_vars), 25L))]
  }

  # ── 3. 计算并绘图（辅助函数）──────────────────────────────────────────────
  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl$label_mapping)
  } else {
    bl$label_mapping
  }

  # VOC + Baseline 使用同一批完整样本，避免两图 n 不一致
  align_vars <- unique(c(voc_vars, base_vars))
  align_vars <- intersect(align_vars, names(data))
  data_plot <- data
  if (length(align_vars) >= 2L) {
    sub_align <- .corrplot_to_num(data, align_vars)
    ok_ix <- stats::complete.cases(sub_align)
    n_align <- sum(ok_ix)
    if (n_align >= 10L) {
      data_plot <- data[ok_ix, , drop = FALSE]
      cli::cli_alert_info("corrplot: VOC+Baseline 对齐样本 n={n_align}")
    }
  }

  .run_domain <- function(vars, domain_label, fig_w, plot_data = data_plot) {
    if (!length(vars)) {
      cli::cli_alert_info("corrplot [{domain_label}]: 无变量，跳过。")
      return(NULL)
    }
    vars <- unique(vars[nzchar(vars)])
    sub_df <- .corrplot_to_num(plot_data, vars)
    if (exists("environment_display_label", mode = "function") && length(label_map)) {
      colnames(sub_df) <- environment_display_label(colnames(sub_df), label_map)
    } else if (exists("environment_display_label", mode = "function")) {
      colnames(sub_df) <- environment_display_label(colnames(sub_df), NULL)
    }
    complete_rows <- stats::complete.cases(sub_df)
    n_comp <- sum(complete_rows)
    if (n_comp < 10L) {
      cli::cli_alert_warning("corrplot [{domain_label}]: 完整行 {n_comp} < 10，跳过。")
      return(NULL)
    }
    sub_df <- sub_df[complete_rows, , drop = FALSE]

    ct <- tryCatch(
      psych::corr.test(sub_df, method = method, adjust = "none"),
      error = function(e) {
        cli::cli_alert_warning("corrplot [{domain_label}]: psych::corr.test 失败: {e$message}")
        NULL
      }
    )
    if (is.null(ct)) return(NULL)
    R <- ct$r
    P <- ct$p
    attr(P, "n") <- n_comp

    title <- paste0(domain_label, " — Spearman (P<0.05, n=", n_comp, ")")
    fig_path <- file.path(fig_dir, paste0("Figure Corrplot ", domain_label, ".pdf"))
    tryCatch({
      grDevices::pdf(fig_path, width = fig_w, height = fig_w)
      .corrplot_draw(R, P, title, method, fig_w, bl)
      grDevices::dev.off()
      cli::cli_alert_success("corrplot PDF: {basename(fig_path)}")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("corrplot [{domain_label}] PDF 失败: {e$message}")
    })

    tryCatch(
      .corrplot_export_table(R, P, vars, domain_label, tbl_dir, bl),
      error = function(e) cli::cli_alert_warning("corrplot 表格失败: {e$message}")
    )
    list(r = R, p = P, vars = vars, n = n_comp)
  }

  # ── VOC 图 ────────────────────────────────────────────────────────────────
  fig_w_voc  <- as.numeric(bl$fig_width_voc  %||% 8.5)
  fig_w_base <- as.numeric(bl$fig_width_base %||% 11)

  voc_res  <- NULL
  base_res <- NULL

  if (length(voc_vars) >= 2L) {
    voc_res <- .run_domain(voc_vars,  "VOC",      fig_w_voc)
  } else {
    cli::cli_alert_info("corrplot: VOC 变量 < 2，跳过 VOC 图。")
  }
  if (length(base_vars) >= 2L) {
    base_res <- .run_domain(base_vars, "Baseline", fig_w_base)
  } else {
    cli::cli_alert_info("corrplot: Baseline 变量 < 2，跳过 Baseline 图。")
  }

  if (!is.null(voc_res))  ctx$results$corrplot_voc_matrix  <- voc_res$r
  if (!is.null(base_res)) ctx$results$corrplot_base_matrix <- base_res$r
  ctx$results$corrplot_voc_vars  <- if (!is.null(voc_res)) voc_res$vars else character(0)
  ctx$results$corrplot_base_vars <- if (!is.null(base_res)) base_res$vars else character(0)

  cli::cli_alert_success(
    "environment_voc_corrplot: VOC={length(voc_vars)} vars, Baseline={length(base_vars)} vars"
  )
  ctx
}

register_block(
  "environment_voc_corrplot",
  block_environment_voc_corrplot,
  "Spearman 相关矩阵可视化（VOC/Baseline 双图）+ Table 2-VOC / Table 2-Baseline"
)
