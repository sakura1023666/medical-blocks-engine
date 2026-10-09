###############################################################################
#  dual_db_logistic_scheme_harmonize — 闸门 C：双库 logistic 初筛后统一分位方案
#  两库各自级联终态取更深一层（如 NHANES=quartile, MIMIC=tertile → 统一 tertile）
###############################################################################

block_dual_db_logistic_scheme_harmonize <- function(ctx) {
  cfg <- ctx$config
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(ctx)

  root <- normalizePath(
    cfg$project$root %||% getwd(),
    winslash = "/",
    mustWork = FALSE
  )
  db_name <- as.character(dual$current_db %||% "")[1L]

  unified_info <- dual_db_load_logistic_branch(root, cfg)
  if (is.null(unified_info) || !nzchar(unified_info$scheme %||% "")) {
    harmonized <- dual_db_harmonize_unified_logistic_branch(root, cfg)
    unified_info <- if (!is.null(harmonized)) {
      list(branch = harmonized$branch, scheme = harmonized$scheme, detail = harmonized$detail)
    } else {
      dual_db_load_logistic_branch(root, cfg)
    }
  }
  if (is.null(unified_info)) {
    natural <- dual_db_read_logistic_natural_branch(root, cfg, db_name)
    if (!is.null(natural)) {
      unified_info <- dual_db_normalize_follower_logistic_branch(natural)
    }
  }
  if (is.null(unified_info)) {
    cli::cli_alert_warning("闸门 C：尚无可用 logistic 分位方案，跳过后续对齐。")
    return(ctx)
  }

  ctx <- dual_db_seed_logistic_branch_to_ctx(ctx, unified_info)
  ctx$results$dual_db_logistic_unified_scheme <- unified_info$scheme
  ctx$results$dual_db_logistic_unified_locked <- TRUE

  gate_b <- dual_db_resync_gate_b_after_logistic(root, cfg, scheme_hint = unified_info$scheme)
  if (!is.null(gate_b)) {
    uni_scheme <- as.character(unified_info$scheme %||% "")[1L]
    ctx <- dual_db_apply_gate_b_to_ctx(ctx, db_name, gate_b)
    ctx$results$dual_db_logistic_needs_realign <- TRUE
    ctx$results$dual_db_logistic_covariate_resynced <- TRUE
    for (peer in c(dual_db_slot_primary(), dual_db_slot_secondary())) {
      dual_db_rebuild_logistic_table2_for_db(root, cfg, peer, gate_b, uni_scheme)
    }
    cli::cli_alert_success(
      "双库 Model2 已统一（临床 {length(gate_b$common_model_factors)} 个）: {paste(gate_b$common_model_factors, collapse = ', ')}"
    )
  }

  natural <- dual_db_read_logistic_natural_branch(root, cfg, db_name)
  # 自然方案与统一方案不一致时必须重导主表（含降级：quartile→tertile/binary）
  nat_scheme <- as.character(natural$scheme %||% "")[1L]
  uni_scheme <- as.character(unified_info$scheme %||% "")[1L]
  if (!isTRUE(ctx$results$dual_db_logistic_covariate_resynced)) {
    ctx$results$dual_db_logistic_needs_realign <-
      nzchar(uni_scheme) && (!nzchar(nat_scheme) || !identical(nat_scheme, uni_scheme))
  }
  if (isTRUE(ctx$results$dual_db_logistic_needs_realign)) {
    cli::cli_alert_info(
      "闸门 C [{toupper(db_name)}] 自然方案 {nat_scheme} → 双库统一 {uni_scheme}（将重导 Table 2）"
    )
  } else {
    cli::cli_alert_success(
      "闸门 C [{toupper(db_name)}] 双库统一分位: {uni_scheme}"
    )
  }
  ctx
}

register_block(
  "dual_db_logistic_scheme_harmonize",
  block_dual_db_logistic_scheme_harmonize,
  "Dual-DB gate C: unify logistic quantile scheme after per-DB cascade screen"
)
