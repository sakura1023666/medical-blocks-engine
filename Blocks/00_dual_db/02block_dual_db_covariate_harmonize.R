###############################################################################
#  dual_db_covariate_harmonize — 闸门 B：VIF 后对齐 Model1/Model2 临床协变量
#  covariate_source=vif_screen 时用单因素 VIF screen；否则用多因素 VIF final
###############################################################################

block_dual_db_covariate_harmonize <- function(ctx) {
  cfg <- ctx$config
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(ctx)

  harm <- dual$harmonization %||% list()
  if (!isTRUE(harm$sync_after_vif_final)) return(ctx)

  db_name <- as.character(dual$current_db %||% "")[1L]
  if (!nzchar(db_name)) {
    cli::cli_alert_warning("闸门 B：dual_db$current_db 未设置，跳过。")
    return(ctx)
  }

  # 单库：不拿另一库 pending/preset 覆盖；VIF final + 缺年龄则补进 Model1
  if (exists("locked_mv_n_databases", mode = "function") &&
      locked_mv_n_databases(cfg) < 2L) {
    cols <- if (exists("pipeline_ctx_data_cols", mode = "function")) {
      pipeline_ctx_data_cols(ctx)
    } else {
      character(0)
    }
    m1 <- as.character(ctx$results$Model1Factors %||% character(0))
    m2 <- as.character(ctx$results$Model2Factors %||% character(0))
    if (exists("pipeline_ensure_age_in_model1", mode = "function")) {
      ens <- pipeline_ensure_age_in_model1(m1, m2, cols, cfg)
      m1 <- ens$M1
      m2 <- ens$M2
    }
    gate_b <- list(common_model_factors = setdiff(m2, m1))
    gate_b[[paste0("harmonized_model1_", db_name)]] <- m1
    gate_b[[paste0("harmonized_model2_", db_name)]] <- m2
    ctx <- dual_db_apply_gate_b_to_ctx(ctx, db_name, gate_b)
    cli::cli_alert_info(
      "闸门 B 单库 [{toupper(db_name)}] Model1: {paste(ctx$results$Model1Factors, collapse = ', ')}"
    )
    cli::cli_alert_info(
      "闸门 B 单库 [{toupper(db_name)}] Model2: {paste(ctx$results$Model2Factors, collapse = ', ')}"
    )
    return(ctx)
  }

  cov_src <- dual_db_harmonization_covariate_source(cfg)
  if (identical(cov_src, "vif_screen")) {
    fac <- dual_db_build_model_factors_from_ctx(ctx, cfg, db_name)
    m1 <- fac$Model1Factors
    m2 <- fac$Model2Factors
    if (!length(m2)) {
      cli::cli_alert_warning("闸门 B：vif_screen_pass 为空，跳过。")
      return(ctx)
    }
  } else {
    m1 <- as.character(ctx$results$Model1Factors %||% character(0))
    m2 <- as.character(ctx$results$Model2Factors %||% character(0))
    if (!length(m1) && !length(m2)) {
      cli::cli_alert_warning("闸门 B：Model1/Model2 为空，跳过。")
      return(ctx)
    }
  }

  root <- normalizePath(
    cfg$project$root %||% getwd(),
    winslash = "/",
    mustWork = FALSE
  )

  gate_b <- dual_db_try_sync_gate_b(root, cfg, db_name, m1, m2)
  if (is.null(gate_b)) {
    harm <- dual$harmonization %||% list()
    if (isTRUE(harm$require_same_clinical_cols %||% TRUE) &&
        isTRUE(harm$stop_on_empty_common_clinical %||% TRUE)) {
      other <- if (dual_db_slot_is_primary(db_name)) dual_db_slot_secondary() else dual_db_slot_primary()
      other_src <- dual_db_read_pending_factors(root, cfg, other)
      if (!is.null(other_src)) {
        stop(
          "GATE_B_SYNC_FAIL: 闸门 B 未能对齐双库协变量（", toupper(db_name), "），已停止。",
          call. = FALSE
        )
      }
    }
    return(ctx)
  }

  ctx <- dual_db_apply_gate_b_to_ctx(ctx, db_name, gate_b)
  cli::cli_alert_info(
    "闸门 B [{toupper(db_name)}] Model1: {paste(ctx$results$Model1Factors, collapse = ', ')}"
  )
  cli::cli_alert_info(
    "闸门 B [{toupper(db_name)}] Model2: {paste(ctx$results$Model2Factors, collapse = ', ')}"
  )
  ctx
}

register_block(
  "dual_db_covariate_harmonize",
  block_dual_db_covariate_harmonize,
  "Dual-DB gate B: harmonize Model1/Model2 after VIF (screen or final per config)"
)
