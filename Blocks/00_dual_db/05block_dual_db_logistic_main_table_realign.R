###############################################################################
#  dual_db_logistic_main_table_realign — 统一分位后重导主表（浅层库降级）
###############################################################################

.dual_db_ckpt_results <- function(root, cfg, db_name, block) {
  alias <- file.path(dual_db_checkpoint_dir(root, cfg, db_name), paste0(block, ".rds"))
  if (!file.exists(alias)) return(NULL)
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj$ctx)) return(NULL)
  obj$ctx$results
}

block_dual_db_logistic_main_table_realign <- function(ctx) {
  if (!isTRUE(ctx$results$dual_db_logistic_needs_realign)) return(ctx)

  cfg <- ctx$config
  dual <- cfg$dual_db %||% list()
  db_name <- as.character(dual$current_db %||% "")[1L]
  unified <- as.character(ctx$results$dual_db_logistic_unified_scheme %||% "")[1L]
  if (!nzchar(unified)) return(ctx)

  root <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
  cov_resync <- isTRUE(ctx$results$dual_db_logistic_covariate_resynced)
  if (cov_resync && exists("dual_db_load_gate_b", mode = "function")) {
    gate_b <- dual_db_load_gate_b(root, cfg)
    if (!is.null(gate_b) && exists("dual_db_apply_gate_b_to_ctx", mode = "function")) {
      ctx <- dual_db_apply_gate_b_to_ctx(ctx, db_name, gate_b)
    }
  }
  .purge_old_main_logistic <- function(dir) {
    if (!dir.exists(dir)) return(invisible(NULL))
    hits <- list.files(dir, pattern = "^Table [0-9]+.*Logistic", full.names = TRUE, ignore.case = TRUE)
    hits <- hits[grepl("\\.(xlsx|tex)$", hits, ignore.case = TRUE)]
    # 保留含 dual-DB unified 且匹配统一方案的；其余主文 logistic 先删
    keep <- grepl("\\[dual-DB unified\\]", basename(hits), ignore.case = TRUE) &
      grepl(unified, basename(hits), ignore.case = TRUE)
    del <- hits[!keep]
    if (length(del)) unlink(del)
    invisible(length(del))
  }
  .purge_old_main_logistic(ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables"))

  index_var <- as.character(
    (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% "Hematocrit"
  )[1L]
  disease <- cfg$project$disease %||% cfg$project$analysis_group %||% "Outcome"

  .realign_footnotes <- function(ctx_local, r_ckpt = NULL) {
    M1 <- as.character(
      ctx_local$results$Model1Factors %||%
        ctx_local$results$logistic_model1_factors %||%
        r_ckpt$Model1Factors %||%
        r_ckpt$logistic_model1_factors %||%
        character(0)
    )
    M2 <- as.character(
      ctx_local$results$Model2Factors %||%
        ctx_local$results$logistic_model2_factors %||%
        r_ckpt$Model2Factors %||%
        r_ckpt$logistic_model2_factors %||%
        character(0)
    )
    M1 <- unique(M1[nzchar(M1)])
    M2 <- unique(M2[nzchar(M2)])
    M3 <- unique(as.character(
      ctx_local$results$Model3Factors %||%
        ctx_local$results$logistic_model3_factors %||%
        r_ckpt$Model3Factors %||%
        character(0)
    ))
    m3_sig <- isTRUE(ctx_local$results$model3_significant %||% r_ckpt$model3_significant)
    if (exists(".lnw00_table_footnotes", mode = "function")) {
      return(.lnw00_table_footnotes(M1, M2, M3, m3_sig))
    }
    if (exists("logistic_glm_table_footnotes", mode = "function")) {
      return(logistic_glm_table_footnotes(M1, M2, M3, m3_sig))
    }
    NULL
  }

  if (dual_db_is_weighted(cfg, db_name)) {
    tbl_map <- list(
      quartile = "logistic_table2_quartile_nhanes",
      tertile  = "logistic_table2_tertile_nhanes",
      binary   = "logistic_table2_binary_nhanes"
    )
    blk_map <- list(
      quartile = "logistic_quartile_nhanes_weighted",
      tertile  = "logistic_tertile_nhanes_weighted",
      binary   = "logistic_binary_nhanes_weighted"
    )
    bl_map <- list(
      quartile = cfg$logistic_quartile_nhanes_weighted %||% list(),
      tertile  = cfg$logistic_tertile_nhanes_weighted %||% list(),
      binary   = cfg$logistic_binary_nhanes_weighted %||% list()
    )
    cap_map <- list(
      quartile = paste0("Weighted logistic regression of ", index_var, " and ", disease,
                        " (NHANES quartile, svyglm) [dual-DB unified]"),
      tertile  = paste0("Weighted logistic regression of ", index_var, " and ", disease,
                        " (NHANES tertile, svyglm) [dual-DB unified]"),
      binary   = paste0("Weighted logistic regression of ", index_var, " and ", disease,
                        " (NHANES binary, svyglm) [dual-DB unified]")
    )
    if (cov_resync && exists("dual_db_ensure_logistic_table2_helpers", mode = "function")) {
      dual_db_ensure_logistic_table2_helpers(cfg, db_name, unified)
    }
    for (fam in names(tbl_map)) {
      tb <- ctx$results[[tbl_map[[fam]]]]
      if (is.null(tb) && cov_resync) {
        r_ck <- .dual_db_ckpt_results(root, cfg, db_name, blk_map[[fam]])
        tb <- r_ck[[tbl_map[[fam]]]] %||% r_ck$logistic_table2 %||% r_ck$nhanes_logistic_table2
      }
      if (is.null(tb)) next
      as_main <- identical(fam, unified)
      # 非选中方案不再导出附表（只保留统一主表 + 后续 RCS）
      if (!isTRUE(as_main)) next
      ft <- .realign_footnotes(ctx)
      if (exists(".lnw00_export_table2", mode = "function")) {
        if (exists(".pub_state", inherits = TRUE)) {
          old_mt <- as.integer(get("main_table", envir = .pub_state, inherits = FALSE) %||% 0L)
          assign("main_table", 1L, envir = .pub_state)
          .lnw00_export_table2(ctx, cfg, bl_map[[fam]], tb, cap_map[[fam]],
                               as_main = TRUE, table_footnotes = ft)
          assign("main_table", max(old_mt, 2L), envir = .pub_state)
        } else {
          .lnw00_export_table2(ctx, cfg, bl_map[[fam]], tb, cap_map[[fam]],
                               as_main = TRUE, table_footnotes = ft)
        }
      }
      ctx$results$nhanes_logistic_selected_scheme <- fam
      ctx$results$nhanes_logistic_grouping_scheme <- fam
      ctx$results$logistic_grouping_scheme <- fam
      ctx$results$nhanes_logistic_table2 <- tb
      ctx$results$logistic_table2_weighted <- tb
      ctx$results$logistic_table2_nhanes <- tb
    }
  } else {
    outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
    blk_map <- list(
      quartile = "logistic_quartile_glm",
      tertile  = "logistic_tertile_glm",
      binary   = "logistic_binary_glm"
    )
    if (cov_resync && exists("dual_db_ensure_logistic_table2_helpers", mode = "function")) {
      dual_db_ensure_logistic_table2_helpers(cfg, db_name, unified)
    }
    tb_main <- NULL
    for (fam in names(blk_map)) {
      r <- .dual_db_ckpt_results(root, cfg, db_name, blk_map[[fam]])
      tb <- r$logistic_table2 %||% NULL
      if (is.null(tb)) next
      as_main <- identical(fam, unified)
      # 只重导统一主表；非选中分位不再占 S 号
      if (!isTRUE(as_main)) next
      cap <- paste0(
        "Logistic regression analysis of ", index_var, " and ", outcome_col,
        " - ", fam, " (GLM) [dual-DB unified]"
      )
      bl_cfg <- cfg[[blk_map[[fam]]]] %||% list()
      ft <- .realign_footnotes(ctx, r)
      if (exists(".lnw00_export_table2", mode = "function")) {
        if (exists(".pub_state", inherits = TRUE)) {
          old_mt <- as.integer(get("main_table", envir = .pub_state, inherits = FALSE) %||% 0L)
          assign("main_table", 1L, envir = .pub_state)
          .lnw00_export_table2(ctx, cfg, bl_cfg, tb, cap, as_main = TRUE, table_footnotes = ft)
          assign("main_table", max(old_mt, 2L), envir = .pub_state)
        } else {
          .lnw00_export_table2(ctx, cfg, bl_cfg, tb, cap, as_main = TRUE, table_footnotes = ft)
        }
      } else if (exists("pub_paths", mode = "function")) {
        rt <- if (exists("format_logistic_table2_pvalues", mode = "function")) {
          format_logistic_table2_pvalues(tb)
        } else tb
        h1 <- as.character(rt[1, ]); h2 <- as.character(rt[2, ])
        body <- rt[-c(1L, 2L), , drop = FALSE]
        colnames(body) <- paste0("V", seq_len(ncol(body)))
        if (exists(".pub_state", inherits = TRUE)) {
          old_mt <- as.integer(get("main_table", envir = .pub_state, inherits = FALSE) %||% 0L)
          assign("main_table", 1L, envir = .pub_state)
          pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", cap, "xlsx")
          assign("main_table", max(old_mt, 2L), envir = .pub_state)
        } else {
          pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", cap, "xlsx")
        }
        tryCatch(
          export_sci_table(body, pub$filepath, title = pub$title,
                           header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE,
                           table_footnotes = ft),
          error = function(e) NULL
        )
      }
      tb_main <- tb
    }
    ctx$results$logistic_grouping_scheme <- unified
    ctx$results$nhanes_logistic_selected_scheme <- unified
    if (!is.null(tb_main)) ctx$results$logistic_table2 <- tb_main
  }

  ctx$results$dual_db_logistic_needs_realign <- FALSE
  cli::cli_alert_success("主表已按双库统一方案 {unified} 重新导出")
  ctx
}

register_block(
  "dual_db_logistic_main_table_realign",
  block_dual_db_logistic_main_table_realign,
  "Dual-DB: re-export main logistic table after unified scheme downgrade"
)
