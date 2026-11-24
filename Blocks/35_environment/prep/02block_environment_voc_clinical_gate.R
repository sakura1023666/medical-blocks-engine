###############################################################################
#  environment_voc_clinical_gate — 环境毒物临床门禁（通过后进 LASSO）
#
#  默认: 不要求 Table1；环境毒物多因素显著数 ≥ multivariate_min_for_full_gate 时
#        要求 单因素+多因素+VIF，否则仅单因素（tb1）。
#
#  register_block: "environment_voc_clinical_gate"
#  位置: multicollinearity_nhanes_final 之后、process_environment_data 之前
###############################################################################

environment_voc_name_variants <- function(v, label_map = NULL) {
  v <- as.character(v)[1L]
  if (!nzchar(v)) return(character(0))
  out <- unique(c(
    v,
    gsub("_", " ", v, fixed = TRUE),
    gsub(" ", "_", v, fixed = TRUE)
  ))
  if (!is.null(label_map) && length(label_map) && v %in% names(label_map)) {
    lbl <- as.character(label_map[[v]])
    out <- unique(c(out, lbl, gsub("_", " ", lbl, fixed = TRUE)))
  }
  if (exists("environment_display_label", mode = "function")) {
    lbl2 <- environment_display_label(v, label_map)
    out <- unique(c(out, lbl2, gsub("_", " ", lbl2, fixed = TRUE)))
  }
  out[nzchar(out)]
}

environment_voc_match_table1_sig <- function(vocs, sig_vars, label_map = NULL) {
  vocs <- unique(as.character(vocs[nzchar(vocs)]))
  sig_vars <- unique(as.character(sig_vars[nzchar(sig_vars)]))
  if (!length(vocs) || !length(sig_vars)) return(character(0))
  sig_norm <- unique(c(
    sig_vars,
    gsub(" ", "_", sig_vars, fixed = TRUE),
    gsub("_", " ", sig_vars, fixed = TRUE)
  ))
  vocs[vapply(vocs, function(v) {
    any(environment_voc_name_variants(v, label_map) %in% sig_norm)
  }, logical(1L))]
}

environment_voc_clinical_gate_detail <- function(
    voc_pool,
    table1_pass,
    uni_pass,
    mv_pass,
    vif_pass,
    cor_pass,
    passed,
    gate_mode = "univariate_only",
    vif_after = character(0),
    cor_after = character(0),
    vif_values = NULL
) {
  vif_num <- vapply(voc_pool, function(v) {
    if (is.null(vif_values) || !length(vif_values)) return(NA_real_)
    if (v %in% names(vif_values)) as.numeric(vif_values[[v]]) else NA_real_
  }, numeric(1L))
  data.frame(
    VOC = voc_pool,
    Gate_mode = rep(as.character(gate_mode)[1L], length(voc_pool)),
    Table1 = voc_pool %in% table1_pass,
    Univariate = voc_pool %in% uni_pass,
    Multivariate = voc_pool %in% mv_pass,
    VIF_after = voc_pool %in% vif_after,
    Cor_after = voc_pool %in% cor_after,
    VIF_final = voc_pool %in% vif_pass,
    Cor_final = voc_pool %in% cor_pass,
    VIF = round(vif_num, 3),
    Passed = voc_pool %in% passed,
    stringsAsFactors = FALSE
  )
}

environment_strip_vocs_from_clinical_ctx <- function(ctx, vocs) {
  vocs <- unique(as.character(vocs[nzchar(vocs)]))
  if (!length(vocs)) return(ctx)
  # 仅从临床协变量模型列表剔除 VOC；保留 tb1/tb_screen/vif_* 供 Table S2/S3/VIF/插补表展示
  keys <- c("Model1Factors", "Model2Factors", "final_features")
  for (key in keys) {
    val <- ctx$results[[key]]
    if (is.null(val)) next
    ctx$results[[key]] <- setdiff(as.character(val), vocs)
  }
  ctx$results$final_features <- ctx$results$Model2Factors
  ctx$results$nhanes_logistic_M1 <- ctx$results$Model1Factors
  ctx$results$nhanes_logistic_M2 <- ctx$results$Model2Factors
  ctx
}

block_environment_voc_clinical_gate <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$environment_voc_clinical_gate %||% list()
  if (!isTRUE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("environment_voc_clinical_gate: enable=FALSE，跳过。")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !ncol(data)) {
    stop("environment_voc_clinical_gate: 无可用数据。", call. = FALSE)
  }

  voc_pool <- if (exists("environment_voc_allowlist", mode = "function")) {
    environment_voc_allowlist(data, cfg)
  } else if (exists("environment_resolve_voc_columns", mode = "function")) {
    environment_resolve_voc_columns(data, cfg)
  } else {
    character(0)
  }
  voc_pool <- intersect(voc_pool, names(data))
  if (!length(voc_pool)) {
    stop("environment_voc_clinical_gate: VOC 候选池为空。", call. = FALSE)
  }

  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl$label_mapping)
  } else {
    bl$label_mapping
  }

  require_t1 <- isTRUE(bl$require_table1 %||% FALSE)
  require_uv <- isTRUE(bl$require_univariate %||% TRUE)
  min_n <- as.integer(bl$min_pass_vocs %||% 2L)[1L]
  voc_gate_mode <- tolower(as.character(bl$voc_gate_mode %||% "univariate_vif")[1L])
  vif_thr <- as.numeric(bl$voc_vif_threshold %||% (cfg$multicollinearity %||% list())$vif_threshold_strict %||% 4)[1L]
  vif_min_keep <- as.integer(bl$voc_vif_min_keep %||% 2L)[1L]
  cor_enable <- isTRUE(bl$voc_cor_enable %||% FALSE)
  cor_thr <- as.numeric(bl$voc_cor_threshold %||% 0.70)[1L]
  cor_method <- as.character(bl$voc_cor_method %||% "pearson")[1L]
  cor_min_keep <- as.integer(bl$voc_cor_min_keep %||% vif_min_keep)[1L]

  sig_vars <- as.character(ctx$results$sig_vars %||% character(0))
  tb1 <- unique(as.character(ctx$results$tb1 %||% character(0)))
  tb2 <- unique(as.character(ctx$results$tb2 %||% character(0)))
  vif_final <- unique(as.character(ctx$results$vif_final_pass %||% character(0)))

  if (identical(voc_gate_mode, "univariate_vif") || identical(voc_gate_mode, "legacy_auto")) {
    uni_candidates <- if (require_uv) {
      environment_voc_univariate_candidates(ctx, voc_pool, bl)
    } else {
      voc_pool
    }
    vif_after <- uni_candidates
    cor_after <- uni_candidates
    cor_pairs_log <- data.frame(
      Var1 = character(0), Var2 = character(0),
      Abs_r = numeric(0), Dropped = character(0), Kept = character(0),
      stringsAsFactors = FALSE
    )
    vif_removed_log <- data.frame(Variable = character(0), VIF = numeric(0), stringsAsFactors = FALSE)

    # ── Step 1: 单因素 → VIF1 ────────────────────────────────────────────────
    if (isTRUE(bl$voc_vif_enable %||% TRUE) && length(uni_candidates) > 1L) {
      vif_prune1 <- environment_vif_prune_vars(uni_candidates, data, vif_thr, vif_min_keep)
      vif_after <- vif_prune1$vars
      vif_removed_log <- vif_prune1$log
      gate_mode <- sprintf("univariate_vif1(thr=%s)", vif_thr)
      if (nrow(vif_removed_log)) {
        apply(vif_removed_log, 1L, function(r) {
          cli::cli_alert_warning(
            "  VIF1 剔除 VIF={r[['VIF']]} 最高变量：{r[['Variable']]}"
          )
        })
      }
    } else if (length(uni_candidates) < 1L) {
      gate_mode <- "univariate_only"
      cli::cli_alert_warning(
        "environment_voc_clinical_gate: 单因素候选为空，跳过 VIF/相关性；请检查 voc_univariate_source。"
      )
    } else {
      gate_mode <- "univariate_only"
    }

    # ── Step 2: 多因素筛选（可选；若多因素结果 >5 则执行，否则 fallback 跳过）────
    mv_min_for_step2 <- as.integer(bl$voc_mv_min_for_step2 %||% 5L)
    mv_voc_in_tb2 <- unique(intersect(vif_after, tb2))
    mv_pass_candidates <- mv_voc_in_tb2
    use_mv_step <- length(mv_voc_in_tb2) > mv_min_for_step2
    if (use_mv_step) {
      cli::cli_alert_info(
        "临床门禁: 多因素 VOC {length(mv_voc_in_tb2)} > {mv_min_for_step2}，执行 univariate→VIF1→multivariate→VIF2→correlation"
      )
      vif_after2 <- mv_voc_in_tb2
      if (isTRUE(bl$voc_vif_enable %||% TRUE) && length(mv_voc_in_tb2) > 1L) {
        vif_prune2 <- environment_vif_prune_vars(mv_voc_in_tb2, data, vif_thr, vif_min_keep)
        vif_after2 <- vif_prune2$vars
        if (nrow(vif_prune2$log)) {
          vif_removed_log <- rbind(vif_removed_log, vif_prune2$log)
          apply(vif_prune2$log, 1L, function(r) {
            cli::cli_alert_warning(
              "  VIF2 剔除 VIF={r[['VIF']]} 最高变量：{r[['Variable']]}"
            )
          })
        }
      }
      gate_mode <- sprintf("uni_vif1_mv_vif2(thr=%s)", vif_thr)
      vif_after <- vif_after2
    } else {
      cli::cli_alert_info(
        "临床门禁: 多因素 VOC {length(mv_voc_in_tb2)} <= {mv_min_for_step2}，fallback 至 univariate→VIF→correlation"
      )
      mv_pass_candidates <- character(0)
    }

    # ── Step 3: 相关性筛选（|r|>阈值 逐一排除，直到全部 ≤阈值 或 剩余 == cor_min_keep）──
    #   规则：相关性 >阈值 的 VOC 必须删除，不得进入 LASSO；唯一例外是删到只剩
    #   cor_min_keep(默认 5) 个时停止（此时即使仍有 >阈值 的对也保留）。
    #   iterative 模式的 environment_cor_prune_vars 已在 length<=min_keep 时停止，
    #   因此这里直接采用其剪枝结果，不再回退到未剪枝的 vif_after。
    vif_res <- environment_calculate_vif_from_vars(vif_after, data)
    vif_vals <- if (!is.null(vif_res$vif_values)) vif_res$vif_values else NULL
    passed <- vif_after

    if (cor_enable && length(vif_after) > 1L) {
      cor_res_tmp <- environment_cor_prune_vars(
        vif_after, data, cor_thr, cor_min_keep, cor_method, vif_vals,
        mode = bl$voc_cor_mode %||% "iterative"
      )
      cor_after_tmp <- cor_res_tmp$vars
      if (length(cor_after_tmp) >= 1L) {
        cor_after <- cor_after_tmp
        passed <- cor_after
        cor_pairs_log <- cor_res_tmp$pairs_log
        gate_mode <- paste0(gate_mode, sprintf(",cor(thr=%s,%s)", cor_thr, cor_method))
        n_removed <- length(vif_after) - length(cor_after)
        if (length(cor_after) <= cor_min_keep) {
          cli::cli_alert_info(
            "临床门禁: 相关性剔除后剩余 {length(cor_after)} 个（已达下限 {cor_min_keep}），停止剔除；剔除 {n_removed} 个高相关 VOC"
          )
        } else {
          cli::cli_alert_info(
            "临床门禁: 相关性 |r|>{cor_thr} 逐一剔除 {n_removed} 个 VOC，剩余 {length(cor_after)} 个进入 LASSO"
          )
        }
        if (nrow(cor_pairs_log)) {
          apply(cor_pairs_log, 1L, function(r) {
            cli::cli_alert_warning(
              "  相关 |r|={r[['Abs_r']]} 剔除 {r[['Dropped']]}（保留 {r[['Kept']]}）"
            )
          })
        }
      } else {
        cor_after <- vif_after
      }
    } else if (cor_enable) {
      cor_after <- vif_after
    }

    table1_pass <- character(0)
    uni_pass <- uni_candidates
    mv_pass <- mv_pass_candidates
    vif_pass <- vif_after
    cor_pass <- cor_after
  } else {
    mv_env_n <- length(intersect(tb2, voc_pool))
    mv_min <- as.integer(bl$multivariate_min_for_full_gate %||% 5L)[1L]
    use_full_gate <- mv_env_n >= mv_min
    gate_mode <- if (use_full_gate) "univariate+multivariate+vif" else "univariate_only"
    require_mv <- use_full_gate && isTRUE(bl$require_multivariate %||% TRUE)
    require_vif <- use_full_gate && isTRUE(bl$require_vif_final %||% TRUE)

    table1_pass <- if (require_t1) {
      environment_voc_match_table1_sig(voc_pool, sig_vars, label_map)
    } else {
      character(0)
    }
    uni_pass <- if (require_uv) intersect(voc_pool, tb1) else voc_pool
    mv_pass  <- if (require_mv) intersect(voc_pool, tb2) else character(0)
    vif_pass <- if (require_vif) intersect(voc_pool, vif_final) else character(0)

    passed <- voc_pool
    if (require_t1) passed <- intersect(passed, table1_pass)
    if (require_uv) passed <- intersect(passed, uni_pass)
    if (require_mv) passed <- intersect(passed, mv_pass)
    if (require_vif) passed <- intersect(passed, vif_pass)
    passed <- unique(passed[nzchar(passed)])
    vif_after <- vif_pass
    cor_pass <- passed
    cor_after <- passed
    vif_vals <- NULL
    cor_pairs_log <- data.frame(
      Var1 = character(0), Var2 = character(0),
      Abs_r = numeric(0), Dropped = character(0),
      stringsAsFactors = FALSE
    )
    vif_removed_log <- data.frame(Variable = character(0), VIF = numeric(0), stringsAsFactors = FALSE)
  }

  ctx$results$tb1_voc_univariate <- unique(intersect(voc_pool, tb1))
  # 通过单因素(P<0.05 且 OR>1)的 VOC —— 供临床 VIF 表(S4)展示环境毒物 VIF 用
  ctx$results$voc_univariate_pass <- unique(as.character(uni_pass))

  detail <- environment_voc_clinical_gate_detail(
    voc_pool, table1_pass, uni_pass, mv_pass, vif_pass, cor_pass, passed, gate_mode,
    vif_after = vif_after, cor_after = cor_after, vif_values = vif_vals
  )
  ctx$results$environment_voc_clinical_gate_detail <- detail
  ctx$results$environment_voc_clinical_gate_mode <- gate_mode
  ctx$results$environment_voc_cor_removed_pairs <- cor_pairs_log
  ctx$results$environment_voc_vif_removed_log <- vif_removed_log
  ctx$results$select_vocs_clinical_gate <- passed

  cli::cli_h2(
    "environment_voc_clinical_gate ({gate_mode}): {length(passed)}/{length(voc_pool)} 个 VOC 通过"
  )
  cli::cli_alert_info(
    "单因素候选 VOC={length(uni_pass)}，VIF 后={length(vif_pass)}，相关性后={length(passed)}（来源={bl$voc_univariate_source %||% 'tb1'}）"
  )
  if (identical(voc_gate_mode, "legacy_auto")) {
    cli::cli_alert_info(
      "环境毒物多因素显著={length(intersect(tb2, voc_pool))}；legacy 模式 gate={gate_mode}"
    )
  }
  if (length(passed)) {
    cli::cli_alert_success("通过: {paste(passed, collapse = ', ')}")
  }
  failed <- setdiff(voc_pool, passed)
  if (length(failed)) {
    cli::cli_alert_info("未通过: {paste(failed, collapse = ', ')}")
  }

  ctx <- environment_strip_vocs_from_clinical_ctx(ctx, voc_pool)
  cli::cli_alert_info(
    "临床协变量已剔除环境毒物；Model2={length(ctx$results$Model2Factors %||% character(0))} 个"
  )

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_path <- file.path(
    tbl_dir,
    as.character(bl$table_filename %||% "Table_Environment_VOC_Clinical_Gate.csv")
  )
  tryCatch(
    utils::write.csv(detail, tbl_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("门禁明细表导出失败: {e$message}")
  )

  summary_path <- file.path(
    tbl_dir,
    as.character(bl$summary_table_filename %||% "Table_Environment_VOC_Screen_Summary.csv")
  )
  screen_summary <- data.frame(
    Step = c("Univariate", "VIF", "Correlation", "Into_LASSO"),
    Threshold = c(
      sprintf("source=%s", bl$voc_univariate_source %||% "tb1"),
      sprintf("VIF<%.2f", vif_thr),
      if (cor_enable) sprintf("|r|<=%.2f (%s)", cor_thr, cor_method) else "disabled",
      "passed=TRUE"
    ),
    N_VOCs = c(
      length(uni_pass),
      length(vif_pass),
      if (cor_enable) length(cor_pass) else length(vif_pass),
      length(passed)
    ),
    VOC_list = c(
      paste(uni_pass, collapse = ", "),
      paste(vif_pass, collapse = ", "),
      paste(if (cor_enable) cor_pass else vif_pass, collapse = ", "),
      paste(passed, collapse = ", ")
    ),
    stringsAsFactors = FALSE
  )
  tryCatch(
    utils::write.csv(screen_summary, summary_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("筛选汇总表导出失败: {e$message}")
  )
  if (nrow(vif_removed_log)) {
    vif_log_path <- file.path(
      tbl_dir,
      as.character(bl$vif_log_table_filename %||% "Table_Environment_VOC_VIF_Removed_Log.csv")
    )
    tryCatch(
      utils::write.csv(vif_removed_log, vif_log_path, row.names = FALSE, fileEncoding = "UTF-8"),
      error = function(e) cli::cli_alert_warning("VIF 剔除日志导出失败: {e$message}")
    )
  }
  if (nrow(cor_pairs_log)) {
    pairs_path <- file.path(
      tbl_dir,
      as.character(bl$cor_pairs_table_filename %||% "Table_Environment_VOC_Cor_Removed_Pairs.csv")
    )
    tryCatch(
      utils::write.csv(cor_pairs_log, pairs_path, row.names = FALSE, fileEncoding = "UTF-8"),
      error = function(e) cli::cli_alert_warning("相关剔除对明细导出失败: {e$message}")
    )
  }

  if (length(passed) < min_n) {
    cli::cli_alert_warning(
      "environment_voc_clinical_gate: 仅 {length(passed)} 个 VOC 进入 LASSO 候选（<{min_n}），继续下游；亚组/极端值 recovery 在 GLM 后触发。"
    )
  }

  helper <- file.path(cfg$project$root %||% getwd(), "R", "environment_voc_recovery_utils.R")
  if (file.exists(helper)) {
    source(helper, local = FALSE)
    ctx <- environment_ensure_raw_snapshot(ctx)
  }

  # 与临床 S3/S4 同阶段导出环境毒物单因素 / VIF 发表表（单因素→VIF 门禁完成后立即落盘）
  bc <- cfg$environment_batch %||% list()
  if (isFALSE(bc$include_vocs_in_clinical_screen %||% TRUE) &&
      !isFALSE(bl$export_voc_pub_tables %||% TRUE)) {
    pub_helper <- file.path(cfg$project$root %||% getwd(), "R", "environment_voc_pub_tables.R")
    if (file.exists(pub_helper) &&
        !exists("environment_export_voc_univariate_vif_tables", mode = "function")) {
      source(pub_helper, local = FALSE)
    }
    if (exists("environment_export_voc_univariate_vif_tables", mode = "function")) {
      out_dirs <- unique(c(
        tbl_dir,
        file.path(
          bc$output_base %||% cfg$project$output_dir %||% dirname(tbl_dir),
          "_shared", "Tables"
        )
      ))
      for (od in out_dirs) {
        if (!dir.exists(od)) dir.create(od, recursive = TRUE, showWarnings = FALSE)
      }
      tryCatch(
        {
          old_db <- getOption("pipeline.database_name", NULL)
          on.exit(options(pipeline.database_name = old_db), add = TRUE)
          options(pipeline.database_name = "NHANES-VOC")
          environment_export_voc_univariate_vif_tables(
            ctx,
            output_dir = out_dirs[[1L]],
            mirror_root_tables = TRUE
          )
        },
        error = function(e) {
          cli::cli_alert_warning("VOC S3/S4 发表表导出失败: {e$message}")
        }
      )
    }
  }

  ctx
}

register_block(
  "environment_voc_clinical_gate",
  block_environment_voc_clinical_gate,
  "环境毒物临床门禁（Table1 可选；多因素不足时仅单因素）"
)
