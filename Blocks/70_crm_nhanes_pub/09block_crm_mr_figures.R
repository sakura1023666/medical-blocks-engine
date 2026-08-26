###############################################################################
#  crm_mr_figures — 两样本 MR 补充图（Figure S4–S15）+ Table 5 多方法估计汇总
#
#  依据：Han et al. 2025 JAHA e038723；本仓库设计
#  docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md（§3 产出清单：
#  "Figure S3 + Table 5 | MR 框架 + 多方法估计 | 复用 57 MR 链"、
#  "Figures S4–S15 | scatter/forest/LOO/funnel 等 | 57 + E:/孟德尔 图模板补齐"）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  典型位置: mr worker 末尾（mr_snp_screen → mr_twosample → mr_egger_presso →
#            mr_pleiotropy → mr_sensitivity → crm_mr_figures）；57 chain 只读复用，
#            本块不修改 Blocks/57_dual_incidence_mr_full 任何文件。
#
#  说明（E:/孟德尔 inventory 结果，证据链——Task 5 Step 1）：
#  `ls "E:/孟德尔/0代码"`（WSL 侧 /mnt/e/孟德尔/0代码）列出 14 个**特定疾病**脚本
#  （如 糖尿病.R / 哮喘.R / 肝纤维化.R 等）。逐一核查后发现：这些脚本均为端到端
#  "下载/读取 GWAS → format_MR_data()（clump）→ mr_modified()（harmonise + 全部 MR
#  方法 + 出图）" 的一次性流程脚本（依赖 easyMR 私有包 [Windows-only zip 安装]、
#  OpenGWAS JWT token、在线数据库访问），**不存在**可独立传入任意 harmonised
#  data.frame 调用的通用绘图函数。图形产物本身（`ScatterPlot_<exposure>_*.pdf`、
#  `forest_<exposure>_*.pdf`、`funnel_<exposure>_*.pdf`、`LeaveOne_<exposure>_*.pdf`，
#  实测见 `E:/孟德尔/MR/T2D/Albumin/` 等目录）是 `easyMR::mr_modified()` 内部的副作用，
#  文件名与本仓库 SUA→CVD/CKD/Diabetes 的组合无关联映射——【证据不足：无法确认这些脚本
#  可安全复用于本项目暴露/结局组合而不触发在线下载或产出错配文件】。
#  依据"孟德尔：算法与辅助脚本从 E:/孟德尔 调用，禁止在块内重写一套无关实现"的硬约束，
#  本块**不**在块内驱动/重写这条脏流程去跑 easyMR，而是把 `mendelian_lib_root` 做成
#  **默认关闭的可选** helper 挂载点：仅当 config 显式给出
#  `crm_mr_figures$mendelian_plot_helper$script`（一个真实存在、经 source 后确实定义了
#  对应函数名的 .R 文件）时才调用该外部函数；否则（默认路径，含本次 smoke）一律走
#  ggplot2 回退实现——与 07block_crm_nhanes_rcs_pub.R 同一惯例（theme_classic + 可配置
#  字体，PDF/PNG 双出，mirror_pub_output_to_root）。
#
#  说明（Table 5 heterogeneity 列口径，证据链）：Blocks/57 的 mr_pleiotropy 块只对
#  Table_MR_SNP_Screened.csv（IV 集合，与具体结局无关）算一次 Cochran Q/I2，因此本块
#  把它作为"IV 集合层面"的参考列（IV_Q_heterogeneity / IV_I2 / IV_P_heterogeneity）
#  原样并到每个结局行，不冒充"结局特异的异质性检验"——原文各结局是否有独立异质性检验
#  在本仓库可读证据中未逐字确证，标【证据不足】。
#
#  crm_mr_figures = list(
#    outcomes = NULL,                    # NULL → config$dual_incidence_mr$mr_outcomes %||% c("CVD","CKD","Diabetes")
#    exposure_label = NULL,               # NULL → config$dual_incidence_mr$exposure_var %||% "SUA"
#    ivw_table_filename          = "Table_MR_IVW_Results.csv",              # 57 mr_twosample 产出
#    sensitivity_table_filename  = "Table_MR_Sensitivity.csv",              # 57 mr_sensitivity 产出
#    pleiotropy_table_filename   = "Table_MR_Pleiotropy_Heterogeneity.csv", # 57 mr_pleiotropy 产出
#    egger_presso_table_filename = "Table_MR_Egger_PRESSO.csv",             # 57 mr_egger_presso 产出（Python，可能缺失）
#    figure_subdir     = "MR",           # 落 Figures/MR/
#    fig_start_index   = 4L,             # 编号起点 → Figure_S4...（4 类型 × N 结局，默认 3 → S4–S15）
#    table_filename    = "Table_5_MR_Estimates.csv",  # 固定名，落 Tables/ 根目录（对齐主文 Table 5）
#    min_snps_for_plots = 3L,            # harmonised SNP 数低于此值跳过出图（不臆造不稳定图）
#    plot_width = 7, plot_height = 6,
#    mendelian_plot_helper = list(       # 可选：外部 helper 脚本挂载（默认关闭 → ggplot 回退）
#      script     = NULL,                 # 相对 dual_incidence_mr$mendelian_lib_root 或绝对路径的 .R 文件
#      scatter_fn = "crm_mr_scatter_external",  # function(dat, ...) → ggplot 对象或 NULL
#      forest_fn  = "crm_mr_forest_external",
#      funnel_fn  = "crm_mr_funnel_external",
#      loo_fn     = "crm_mr_loo_external"
#    ),
#    pause_enable        = TRUE,
#    pause_on_no_output  = TRUE
#  )
#
#  config$dual_incidence_mr 新增/沿用键：
#    mendelian_lib_root = "E:/孟德尔"    # Windows 路径；本块在该路径不存在时会尝试
#                                          # 等价 WSL 路径（/mnt/<drive>/...）
#    gwas_exposure = "Data/smoke/GWAS_SUA_full.csv"（沿用 04/06block_mr_* 口径）
#    mr_outcomes   = c("CVD", "CKD", "Diabetes")
#
#  register_block: "crm_mr_figures"
#
#  读: ctx$results$mr_twosample$output_dir（若同一 pipeline 内已跑 57 mr_twosample）
#      或 file.path(config$project$output_dir, "Tables", "MR")（57 chain 固定写出位置）
#      下的 Table_MR_IVW_Results.csv / Table_MR_Sensitivity.csv /
#      Table_MR_Pleiotropy_Heterogeneity.csv / Table_MR_Egger_PRESSO.csv（存在则并入，
#      不存在则跳过不伪造）；Data/smoke/GWAS_SUA*.csv + Data/smoke/GWAS_<outcome>.csv
#      （重建 SNP 级 harmonised 数据用于出图与 IVW 兜底重算，与 57/04block_mr_twosample.R
#      完全一致的按 SNP merge 口径）
#  写: ctx$results$crm_mr_figures（各结局 n_snps_harmonised、IVW/LOO 估计、图路径、
#      skipped_outcomes 及原因、mendelian helper 是否命中）
#
#  产出:
#    - Figures/MR/Figure_S{n}_MR_scatter_<outcome>.pdf/.png
#    - Figures/MR/Figure_S{n}_MR_forest_<outcome>.pdf/.png
#    - Figures/MR/Figure_S{n}_MR_funnel_<outcome>.pdf/.png
#    - Figures/MR/Figure_S{n}_MR_loo_<outcome>.pdf/.png
#    - Tables/Table_5_MR_Estimates.csv（IVW + Egger(_smoke) + PRESSO[若有] + IV 异质性富集表）
#
#  pause: config$crm_mr_figures$pause_enable
###############################################################################

.crm70m_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70m_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 20L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_mr_figures",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_mr_figures halted. See ctx$results$pause_point. / ",
    "MR 补充图/Table 5 未能产出任何结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

#' Windows 路径 → WSL 等价路径兜底（"E:/孟德尔" → "/mnt/e/孟德尔"）；两者皆不存在则 NA
.crm70m_resolve_lib_root <- function(path) {
  p <- as.character(path %||% "")[1L]
  if (!nzchar(p)) return(NA_character_)
  if (dir.exists(p)) return(normalizePath(p, winslash = "/", mustWork = FALSE))
  if (grepl("^[A-Za-z]:[/\\\\]", p)) {
    drive <- tolower(substr(p, 1L, 1L))
    rest <- sub("^[A-Za-z]:[/\\\\]", "", p)
    wsl_path <- file.path(paste0("/mnt/", drive), rest)
    if (dir.exists(wsl_path)) return(normalizePath(wsl_path, winslash = "/", mustWork = FALSE))
  }
  NA_character_
}

#' 可选地 source 一个外部 helper 脚本并取出约定函数名；任何失败均静默回退（返回 NULL）
.crm70m_load_helper_fns <- function(bl_cfg, lib_root) {
  helper_cfg <- bl_cfg$mendelian_plot_helper %||% list()
  script <- helper_cfg$script
  if (is.null(script) || !nzchar(as.character(script)[1L])) return(NULL)
  script <- as.character(script)[1L]
  path <- if (is_absolute_path(script)) {
    script
  } else if (!is.na(lib_root) && nzchar(lib_root)) {
    file.path(lib_root, script)
  } else {
    script
  }
  if (!file.exists(path)) {
    cli::cli_alert_info("crm_mr_figures: 未找到配置的 helper 脚本 {.file {path}}，回退 ggplot2。")
    return(NULL)
  }
  env <- new.env(parent = globalenv())
  ok <- tryCatch({ sys.source(path, envir = env); TRUE }, error = function(e) {
    cli::cli_alert_warning("crm_mr_figures: helper 脚本 source 失败（{e$message}），回退 ggplot2。")
    FALSE
  })
  if (!isTRUE(ok)) return(NULL)
  fn_names <- list(
    scatter = as.character(helper_cfg$scatter_fn %||% "crm_mr_scatter_external")[1L],
    forest  = as.character(helper_cfg$forest_fn  %||% "crm_mr_forest_external")[1L],
    funnel  = as.character(helper_cfg$funnel_fn  %||% "crm_mr_funnel_external")[1L],
    loo     = as.character(helper_cfg$loo_fn     %||% "crm_mr_loo_external")[1L]
  )
  fns <- list()
  for (k in names(fn_names)) {
    nm <- fn_names[[k]]
    if (nzchar(nm) && exists(nm, envir = env, mode = "function", inherits = FALSE)) {
      fns[[k]] <- get(nm, envir = env, mode = "function")
    }
  }
  if (!length(fns)) {
    cli::cli_alert_info("crm_mr_figures: helper 脚本已 source 但未找到约定函数名，回退 ggplot2。")
    return(NULL)
  }
  fns
}

#' 尝试调用外部 helper（若存在且成功返回 ggplot 对象），否则返回 NULL 交给调用方回退
.crm70m_call_helper <- function(helper_fns, kind, ...) {
  if (is.null(helper_fns) || is.null(helper_fns[[kind]])) return(NULL)
  res <- tryCatch(helper_fns[[kind]](...), error = function(e) {
    cli::cli_alert_warning("crm_mr_figures: helper[{kind}] 调用失败（{e$message}），回退 ggplot2。")
    NULL
  })
  if (!is.null(res) && inherits(res, "ggplot")) res else NULL
}

.crm70m_read_csv_safe <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
}

#' 与 04block_mr_twosample.R 完全一致的 merge-by-SNP 口径，重建 SNP 级 harmonised 数据
.crm70m_merge_snp_data <- function(exp_path, out_path) {
  if (!file.exists(exp_path) || !file.exists(out_path)) return(NULL)
  exp <- .crm70m_read_csv_safe(exp_path)
  outg <- .crm70m_read_csv_safe(out_path)
  if (is.null(exp) || is.null(outg) || !"SNP" %in% names(exp) || !"SNP" %in% names(outg)) return(NULL)
  merged <- merge(exp, outg, by = "SNP", suffixes = c("_exp", "_out"))
  need <- c("beta_exp", "se_exp", "beta_out", "se_out")
  if (!nrow(merged) || !all(need %in% names(merged))) return(NULL)
  keep <- is.finite(merged$beta_exp) & is.finite(merged$se_exp) &
    is.finite(merged$beta_out) & is.finite(merged$se_out) &
    merged$se_exp > 0 & merged$se_out > 0
  merged <- merged[keep, , drop = FALSE]
  if (!nrow(merged)) return(NULL)
  merged
}

#' 逆方差加权 IVW（与 04block_mr_twosample.R 公式一致）
.crm70m_ivw_from_merged <- function(merged) {
  b <- merged$beta_exp; bout <- merged$beta_out; sout <- merged$se_out
  w <- 1 / sout^2
  beta <- sum(b * bout * w) / sum(b^2 * w)
  se <- sqrt(1 / sum(b^2 * w))
  list(
    beta = beta, se = se,
    p = 2 * stats::pnorm(-abs(beta / se)),
    n_snps = nrow(merged)
  )
}

#' 单 SNP Wald 比值估计（TwoSampleMR::mr_singlesnp 同口径近似：se = |se_out / beta_exp|）
.crm70m_single_snp_wald <- function(merged) {
  beta <- merged$beta_out / merged$beta_exp
  se <- abs(merged$se_out / merged$beta_exp)
  data.frame(
    SNP = merged$SNP, beta = beta, se = se,
    p = 2 * stats::pnorm(-abs(beta / se)),
    stringsAsFactors = FALSE
  )
}

#' Leave-one-out IVW：逐个剔除单 SNP 重算 IVW；末行 "All" = 全量 IVW
.crm70m_loo_ivw <- function(merged) {
  n <- nrow(merged)
  rows <- vector("list", n)
  for (i in seq_len(n)) {
    sub <- merged[-i, , drop = FALSE]
    if (nrow(sub) < 2L) { rows[[i]] <- NULL; next }
    fit <- .crm70m_ivw_from_merged(sub)
    rows[[i]] <- data.frame(SNP = merged$SNP[i], beta = fit$beta, se = fit$se, p = fit$p,
                             stringsAsFactors = FALSE)
  }
  rows <- Filter(Negate(is.null), rows)
  loo <- if (length(rows)) do.call(rbind, rows) else {
    data.frame(SNP = character(0), beta = numeric(0), se = numeric(0), p = numeric(0))
  }
  overall <- .crm70m_ivw_from_merged(merged)
  rbind(loo, data.frame(SNP = "All", beta = overall$beta, se = overall$se, p = overall$p,
                         stringsAsFactors = FALSE))
}

.crm70m_plot_scatter <- function(merged, ivw, title_txt, font_family) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || is.null(merged) || !nrow(merged)) return(NULL)
  p_txt <- if (exists("pub_format_p", mode = "function")) pub_format_p(ivw$p) else format(ivw$p, digits = 3)
  ggplot2::ggplot(merged, ggplot2::aes(x = .data$beta_exp, y = .data$beta_out)) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$beta_out - 1.96 * .data$se_out, ymax = .data$beta_out + 1.96 * .data$se_out),
      color = "grey70", width = 0
    ) +
    ggplot2::geom_errorbarh(
      ggplot2::aes(xmin = .data$beta_exp - 1.96 * .data$se_exp, xmax = .data$beta_exp + 1.96 * .data$se_exp),
      color = "grey70", height = 0
    ) +
    ggplot2::geom_point(color = "#377EB8", size = 1.8) +
    ggplot2::geom_abline(slope = ivw$beta, intercept = 0, color = "#E41A1C", linewidth = 0.9) +
    ggplot2::labs(
      title = title_txt, x = "SNP effect on exposure", y = "SNP effect on outcome",
      subtitle = paste0("IVW beta=", round(ivw$beta, 4), ", P=", p_txt, ", n SNP=", ivw$n_snps)
    ) +
    ggplot2::theme_classic(base_size = 12) +
    ggplot2::theme(text = ggplot2::element_text(family = font_family))
}

.crm70m_plot_forest <- function(snp_est, overall, title_txt, font_family) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || is.null(snp_est) || !nrow(snp_est)) return(NULL)
  df <- snp_est[order(snp_est$beta), , drop = FALSE]
  df$Lower <- df$beta - 1.96 * df$se
  df$Upper <- df$beta + 1.96 * df$se
  overall_row <- data.frame(
    SNP = "IVW (overall)", beta = overall$beta,
    Lower = overall$beta - 1.96 * overall$se, Upper = overall$beta + 1.96 * overall$se,
    stringsAsFactors = FALSE
  )
  lvls <- c(as.character(df$SNP), "IVW (overall)")
  all_df <- rbind(df[, c("SNP", "beta", "Lower", "Upper")], overall_row)
  all_df$SNP <- factor(all_df$SNP, levels = lvls)
  all_df$is_overall <- all_df$SNP == "IVW (overall)"
  ggplot2::ggplot(all_df, ggplot2::aes(x = .data$beta, y = .data$SNP)) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = .data$Lower, xmax = .data$Upper),
      orientation = "y", width = 0.2, color = "#377EB8"
    ) +
    ggplot2::geom_point(ggplot2::aes(color = .data$is_overall), show.legend = FALSE, size = 2) +
    ggplot2::scale_color_manual(values = c(`TRUE` = "#E41A1C", `FALSE` = "#377EB8")) +
    ggplot2::labs(title = title_txt, x = "Single-SNP Wald ratio (95% CI)", y = NULL) +
    ggplot2::theme_classic(base_size = 10) +
    ggplot2::theme(text = ggplot2::element_text(family = font_family))
}

.crm70m_plot_funnel <- function(snp_est, overall, title_txt, font_family) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || is.null(snp_est) || !nrow(snp_est)) return(NULL)
  df <- snp_est
  df$precision <- 1 / df$se
  ggplot2::ggplot(df, ggplot2::aes(x = .data$beta, y = .data$precision)) +
    ggplot2::geom_point(color = "#377EB8", size = 1.8) +
    ggplot2::geom_vline(xintercept = overall$beta, linetype = "dashed", color = "#E41A1C") +
    ggplot2::labs(title = title_txt, x = "Single-SNP Wald ratio", y = "1 / SE (precision)") +
    ggplot2::theme_classic(base_size = 12) +
    ggplot2::theme(text = ggplot2::element_text(family = font_family))
}

.crm70m_plot_loo <- function(loo_tab, title_txt, font_family) {
  if (!requireNamespace("ggplot2", quietly = TRUE) || is.null(loo_tab) || !nrow(loo_tab)) return(NULL)
  df <- loo_tab
  df$Lower <- df$beta - 1.96 * df$se
  df$Upper <- df$beta + 1.96 * df$se
  ord <- setdiff(df$SNP[order(df$beta)], "All")
  df$SNP <- factor(df$SNP, levels = c(ord, "All"))
  df$is_all <- as.character(df$SNP) == "All"
  ggplot2::ggplot(df, ggplot2::aes(x = .data$beta, y = .data$SNP)) +
    ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = .data$Lower, xmax = .data$Upper),
      orientation = "y", width = 0.2, color = "#377EB8"
    ) +
    ggplot2::geom_point(ggplot2::aes(color = .data$is_all), show.legend = FALSE, size = 2) +
    ggplot2::scale_color_manual(values = c(`TRUE` = "#E41A1C", `FALSE` = "#377EB8")) +
    ggplot2::labs(title = title_txt, x = "IVW estimate leaving one SNP out (95% CI)", y = NULL) +
    ggplot2::theme_classic(base_size = 10) +
    ggplot2::theme(text = ggplot2::element_text(family = font_family))
}

.crm70m_save_plot <- function(plot_obj, pdf_path, png_path, width, height) {
  if (is.null(plot_obj)) return(c(pdf = FALSE, png = FALSE))
  saved_pdf <- tryCatch({
    grDevices::cairo_pdf(pdf_path, width = width, height = height)
    print(plot_obj)
    grDevices::dev.off()
    TRUE
  }, error = function(e) { try(grDevices::dev.off(), silent = TRUE); FALSE })
  saved_png <- tryCatch({
    grDevices::png(png_path, width = width * 100, height = height * 100, res = 100)
    print(plot_obj)
    grDevices::dev.off()
    TRUE
  }, error = function(e) { try(grDevices::dev.off(), silent = TRUE); FALSE })
  c(pdf = saved_pdf, png = saved_png)
}

#' 57 chain 的 MR Tables 目录：优先复用同一 ctx 内 mr_twosample 记录的实际写出路径，
#' 否则回退到 04/06/07/08block_mr_* 固定使用的 project$output_dir/Tables/MR
.crm70m_resolve_mr_tables_dir <- function(ctx) {
  from_ctx <- ctx$results$mr_twosample$output_dir
  if (!is.null(from_ctx) && nzchar(as.character(from_ctx)[1L])) return(as.character(from_ctx)[1L])
  root <- ctx$config$project$output_dir %||% ctx$root_output_dir %||% ctx$output_dir %||% "Output"
  file.path(root, "Tables", "MR")
}

#' 把若干候选表按公共核心列对齐后 rbind；缺列补 NA，不强行假造数值
.crm70m_bind_estimate_tables <- function(tabs) {
  core <- c("exposure", "outcome", "method", "beta", "se", "p", "n_snps", "source")
  tabs <- Filter(function(x) is.data.frame(x) && nrow(x) > 0, tabs)
  if (!length(tabs)) return(NULL)
  rows <- lapply(tabs, function(tb) {
    for (cc in core) if (!cc %in% names(tb)) tb[[cc]] <- NA
    tb[, core, drop = FALSE]
  })
  do.call(rbind, rows)
}

block_crm_mr_figures <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_mr_figures %||% list()
  mr_cfg <- cfg$dual_incidence_mr %||% list()
  root <- mr_cfg$project_root %||% cfg$project$root %||% getwd()

  outcomes <- as.character(bl_cfg$outcomes %||% mr_cfg$mr_outcomes %||% c("CVD", "CKD", "Diabetes"))
  exposure_label <- as.character(bl_cfg$exposure_label %||% mr_cfg$exposure_var %||% "SUA")[1L]

  fig_dir_root <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  fig_dir <- file.path(fig_dir_root, as.character(bl_cfg$figure_subdir %||% "MR")[1L])
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)

  lib_root_cfg <- as.character(mr_cfg$mendelian_lib_root %||% "E:/\u5b5f\u5fb7\u5c14")[1L]
  lib_root <- .crm70m_resolve_lib_root(lib_root_cfg)
  helper_fns <- .crm70m_load_helper_fns(bl_cfg, lib_root)
  cli::cli_alert_info(
    "crm_mr_figures: mendelian_lib_root={lib_root_cfg} (resolved={if (is.na(lib_root)) '未命中' else lib_root}), helper={if (is.null(helper_fns)) 'ggplot2 回退' else paste(names(helper_fns), collapse=',')}"
  )

  font_family <- if (exists("plot_font_from_config", mode = "function")) plot_font_from_config(cfg) else "sans"
  plot_w <- as.numeric(bl_cfg$plot_width %||% 7)[1L]
  plot_h <- as.numeric(bl_cfg$plot_height %||% 6)[1L]
  min_snps <- as.integer(bl_cfg$min_snps_for_plots %||% 3L)[1L]

  exp_path <- file.path(root, mr_cfg$gwas_exposure %||% "Data/smoke/GWAS_SUA_full.csv")
  if (!file.exists(exp_path)) exp_path <- file.path(root, "Data/smoke/GWAS_SUA.csv")

  mr_tables_dir <- .crm70m_resolve_mr_tables_dir(ctx)
  ivw_tab <- .crm70m_read_csv_safe(file.path(mr_tables_dir, bl_cfg$ivw_table_filename %||% "Table_MR_IVW_Results.csv"))
  sens_tab <- .crm70m_read_csv_safe(file.path(mr_tables_dir, bl_cfg$sensitivity_table_filename %||% "Table_MR_Sensitivity.csv"))
  pleio_tab <- .crm70m_read_csv_safe(file.path(mr_tables_dir, bl_cfg$pleiotropy_table_filename %||% "Table_MR_Pleiotropy_Heterogeneity.csv"))
  egger_presso_tab <- .crm70m_read_csv_safe(file.path(mr_tables_dir, bl_cfg$egger_presso_table_filename %||% "Table_MR_Egger_PRESSO.csv"))
  if (!is.null(ivw_tab) && !all(c("outcome", "method") %in% names(ivw_tab))) ivw_tab <- NULL
  if (!is.null(sens_tab) && !all(c("outcome", "method") %in% names(sens_tab))) sens_tab <- NULL
  if (!is.null(egger_presso_tab) && !all(c("outcome", "method", "beta", "se", "p") %in% names(egger_presso_tab))) {
    cli::cli_alert_info("crm_mr_figures: Table_MR_Egger_PRESSO.csv \u5217\u4e0d\u9f50\uff0c\u672c\u6b21\u4e0d\u5e76\u5165 Table 5\uff08\u4fdd\u7559\u539f\u6587\u4ef6\uff0c\u4e0d\u4f2a\u9020\uff09\u3002")
    egger_presso_tab <- NULL
  }
  if (!is.null(ivw_tab)) ivw_tab$source <- "57_chain"
  if (!is.null(sens_tab)) sens_tab$source <- "57_chain"
  if (!is.null(egger_presso_tab)) egger_presso_tab$source <- "57_chain"

  het_cols <- NULL
  if (!is.null(pleio_tab) && nrow(pleio_tab) &&
      all(c("Q", "p_heterogeneity", "I2") %in% names(pleio_tab))) {
    het_cols <- pleio_tab[1L, c("Q", "p_heterogeneity", "I2")]
    names(het_cols) <- c("IV_Q_heterogeneity", "IV_P_heterogeneity", "IV_I2")
  }

  plot_types <- c("scatter", "forest", "funnel", "loo")
  start_idx <- as.integer(bl_cfg$fig_start_index %||% 4L)[1L]
  fig_index_map <- list()
  idx <- start_idx
  for (pt in plot_types) for (oc in outcomes) {
    fig_index_map[[paste0(pt, "::", oc)]] <- idx
    idx <- idx + 1L
  }

  recomputed_rows <- list()
  fig_paths <- list()
  skipped_outcomes <- list()
  n_saved_total <- 0L

  for (oc in outcomes) {
    out_path <- file.path(root, sprintf("Data/smoke/GWAS_%s.csv", oc))
    merged <- .crm70m_merge_snp_data(exp_path, out_path)
    if (is.null(merged)) {
      skipped_outcomes[[oc]] <- "exposure/outcome GWAS \u6587\u4ef6\u7f3a\u5931\u6216\u65e0\u5171\u4eab SNP"
      cli::cli_alert_warning("crm_mr_figures: {oc} \u65e0\u53ef\u7528 harmonised SNP \u6570\u636e\uff0c\u8df3\u8fc7\u3002")
      next
    }
    ivw <- .crm70m_ivw_from_merged(merged)
    recomputed_rows[[oc]] <- data.frame(
      exposure = exposure_label, outcome = oc, method = "IVW",
      beta = round(ivw$beta, 4), se = round(ivw$se, 4), p = signif(ivw$p, 3),
      n_snps = ivw$n_snps, source = "block_recomputed", stringsAsFactors = FALSE
    )

    if (nrow(merged) < min_snps) {
      skipped_outcomes[[oc]] <- sprintf("harmonised SNP \u6570 (%d) < min_snps_for_plots (%d)\uff0c\u8df3\u8fc7\u51fa\u56fe", nrow(merged), min_snps)
      cli::cli_alert_warning("crm_mr_figures: {oc} {skipped_outcomes[[oc]]}\u3002")
      next
    }

    snp_est <- .crm70m_single_snp_wald(merged)
    loo_tab <- .crm70m_loo_ivw(merged)

    for (pt in plot_types) {
      fig_no <- fig_index_map[[paste0(pt, "::", oc)]]
      fbase <- sprintf("Figure_S%d_MR_%s_%s", fig_no, pt, oc)
      pdf_path <- file.path(fig_dir, paste0(fbase, ".pdf"))
      png_path <- file.path(fig_dir, paste0(fbase, ".png"))
      title_txt <- sprintf("%s: %s \u2192 %s (%s)", fbase, exposure_label, oc, pt)

      plot_obj <- switch(pt,
        scatter = .crm70m_call_helper(helper_fns, "scatter", dat = merged, ivw = ivw, title = title_txt),
        forest  = .crm70m_call_helper(helper_fns, "forest",  dat = snp_est, overall = ivw, title = title_txt),
        funnel  = .crm70m_call_helper(helper_fns, "funnel",  dat = snp_est, overall = ivw, title = title_txt),
        loo     = .crm70m_call_helper(helper_fns, "loo",     dat = loo_tab, title = title_txt)
      )
      if (is.null(plot_obj)) {
        plot_obj <- switch(pt,
          scatter = .crm70m_plot_scatter(merged, ivw, title_txt, font_family),
          forest  = .crm70m_plot_forest(snp_est, ivw, title_txt, font_family),
          funnel  = .crm70m_plot_funnel(snp_est, ivw, title_txt, font_family),
          loo     = .crm70m_plot_loo(loo_tab, title_txt, font_family)
        )
      }
      h_use <- plot_h
      if (pt %in% c("forest", "loo")) {
        n_lab <- if (pt == "forest") nrow(snp_est) + 1L else nrow(loo_tab)
        h_use <- min(40, max(plot_h, 1.0 + 0.085 * max(1L, as.integer(n_lab)[1L])))
        if (inherits(plot_obj, "ggplot")) {
          plot_obj <- plot_obj + ggplot2::theme(
            axis.text.y = ggplot2::element_text(size = 3.2)
          )
        }
      }
      saved <- .crm70m_save_plot(plot_obj, pdf_path, png_path, plot_w, h_use)
      if (isTRUE(saved["pdf"]) || isTRUE(saved["png"])) {
        n_saved_total <- n_saved_total + 1L
        fig_paths[[fbase]] <- list(
          pdf = if (isTRUE(saved["pdf"])) pdf_path else NA_character_,
          png = if (isTRUE(saved["png"])) png_path else NA_character_
        )
        if (isTRUE(saved["pdf"]) && exists("mirror_pub_output_to_root", mode = "function")) {
          mirror_pub_output_to_root(ctx, pdf_path)
        }
        if (isTRUE(saved["png"]) && exists("mirror_pub_output_to_root", mode = "function")) {
          mirror_pub_output_to_root(ctx, png_path)
        }
      } else {
        cli::cli_alert_warning("crm_mr_figures: {fbase} \u672a\u80fd\u4fdd\u5b58 PDF/PNG\u3002")
      }
    }
  }

  combined <- .crm70m_bind_estimate_tables(list(ivw_tab, sens_tab, egger_presso_tab))
  if (!is.null(combined)) combined <- combined[combined$outcome %in% outcomes, , drop = FALSE]
  present_outcomes <- if (!is.null(combined)) unique(combined$outcome[combined$method == "IVW"]) else character(0)
  missing_ivw <- setdiff(names(recomputed_rows), present_outcomes)
  if (length(missing_ivw)) {
    recomputed_tab <- do.call(rbind, recomputed_rows[missing_ivw])
    combined <- if (is.null(combined)) recomputed_tab else rbind(combined, recomputed_tab)
  }

  if (is.null(combined) || !nrow(combined)) {
    combined <- data.frame(
      exposure = exposure_label, outcome = NA_character_, method = NA_character_,
      beta = NA_real_, se = NA_real_, p = NA_real_, n_snps = NA_integer_,
      source = NA_character_, note = "no MR data", stringsAsFactors = FALSE
    )
  } else if (!is.null(het_cols)) {
    for (cc in names(het_cols)) combined[[cc]] <- het_cols[[cc]]
  }

  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_5_MR_Estimates.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(combined, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_mr_figures: Table 5 \u5199\u51fa\u5931\u8d25: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  if (n_saved_total == 0L && .crm70m_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .crm70m_pause(
      ctx,
      "crm_mr_figures \u672a\u80fd\u4ea7\u51fa\u4efb\u4f55 MR \u56fe\u5f62\uff08\u6240\u6709\u7ed3\u5c40\u5747\u88ab\u8df3\u8fc7\uff09\u3002",
      "\u68c0\u67e5 Data/smoke/GWAS_*.csv \u6216 57 chain \u4ea7\u51fa\u662f\u5426\u5b58\u5728\u3002",
      combined
    )
  }

  ctx$results$crm_mr_figures <- list(
    outcomes = outcomes,
    table = combined,
    table_path = tbl_path,
    figures = fig_paths,
    n_figures_saved = n_saved_total,
    skipped_outcomes = skipped_outcomes,
    mendelian_lib_root_cfg = lib_root_cfg,
    mendelian_lib_root_resolved = lib_root,
    mendelian_helper_used = !is.null(helper_fns)
  )
  cli::cli_alert_success(
    "crm_mr_figures \u5b8c\u6210\uff08\u56fe {n_saved_total} \u5f20\uff0cskipped={paste(names(skipped_outcomes), collapse=',')}\uff09"
  )
  ctx
}

register_block(
  "crm_mr_figures",
  block_crm_mr_figures,
  "MR \u8865\u5145\u56fe\uff08Figure S4\u2013S15\uff1ascatter/forest/funnel/LOO\uff09+ Table 5 \u4f30\u8ba1\u6c47\u603b"
)
