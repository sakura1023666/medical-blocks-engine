# dbpool_batch_finalize — batch 汇总、发表收口（Methods/软件版本/四目录/白名单）、QC 队列
# 交付根只留 Figures/ Tables/ Methods_*.md|txt / *中期*.pdf（中期 PDF 由 Agent Phase 7 写入后再 prune）

block_dbpool_batch_finalize <- function(ctx) {
  pub_root <- ctx$results$dbpool_pub_root %||% file.path(ctx$root_output_dir %||% "Output", "summary_results")
  dir.create(pub_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(pub_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(pub_root, "Figures"), recursive = TRUE, showWarnings = FALSE)

  status <- list(
    timestamp = as.character(Sys.time()),
    data_root = ctx$results$dbpool_data_root %||% NA_character_,
    blended_out = ctx$results$dbpool_blended_out %||% NA_character_,
    last_unit = ctx$results$dbpool_last_unit %||% NA_character_,
    tables_dir = file.path(pub_root, "Tables"),
    figures_dir = file.path(pub_root, "Figures")
  )
  # 状态写入同级 workspace，不进客户交付根（finalize prune 也会移走根级 json）
  ws <- file.path(dirname(pub_root), paste0(basename(pub_root), "_delivery_workspace"))
  dir.create(ws, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(status, file.path(ws, "_batch_status.json"), auto_unbox = TRUE, pretty = TRUE)

  required <- c(
    "Table 1", "Table 2", "Table 3", "Table 4", "Table S1", "Table S2",
    "Figure 1", "Figure 2"
  )
  inv <- data.frame(
    item = required,
    present = NA,
    note = "filled after full training/table rebuild",
    stringsAsFactors = FALSE
  )
  utils::write.csv(inv, file.path(ws, "Publication_Inventory.csv"), row.names = FALSE)

  # Engine-level：Methods md + 软件版本 txt + 图四目录 + 交付白名单 prune
  engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
    engine <- normalizePath(file.path(getwd()), winslash = "/", mustWork = FALSE)
    if (!dir.exists(file.path(engine, "R"))) {
      engine <- "/mnt/e/01block/01Block-new-Final"
    }
  }
  cohort <- ctx$config$project$cohort %||%
    ctx$config$dbpool$cohort %||%
    "ACG-style enzyme elevation (ALT/AST ≥2×ULN)"
  drop_feat <- ctx$config$dbpool$drop_features %||% "ALT and AST"
  Sys.setenv(
    MEDICAL_BLOCKS_ROOT = engine,
    DBPOOL_COHORT = as.character(cohort)[1L],
    DBPOOL_DROP_FEATURES = as.character(drop_feat)[1L]
  )
  cli_fin <- file.path(engine, "run/pub/finalize_delivery_root.R")
  if (file.exists(cli_fin)) {
    tryCatch(
      {
        out <- system2(
          "Rscript",
          c(
            cli_fin,
            "--dir", normalizePath(pub_root, winslash = "/", mustWork = FALSE),
            "--study-type", "dbpool",
            "--outcome", "ICU mortality and remaining length of stay",
            "--exposure", "Multi-database pooling / transfer learning (TPC)",
            "--databases", "AmsterdamUMC,MIMIC-IV,eICU,HiRID"
          ),
          stdout = TRUE, stderr = TRUE
        )
        cli::cli_alert_info("dbpool finalize_delivery_root: {paste(tail(out, 3), collapse = ' | ')}")
      },
      error = function(e) cli::cli_alert_warning("finalize_delivery_root failed: {e$message}")
    )
  } else {
    cli::cli_alert_warning("missing {cli_fin}")
  }

  # 结构 QC + Nature stub + Phase7 midterm 队列（叙述仍由 Agent 写）
  qc_cli <- file.path(engine, "run/pub/run_pub_qc_after_project.R")
  if (file.exists(qc_cli) && !identical(Sys.getenv("MEDICAL_BLOCKS_AUTO_PUB_QC", "1"), "0")) {
    tryCatch(
      system2("Rscript", c(qc_cli, "--project", normalizePath(pub_root, winslash = "/", mustWork = FALSE)),
              stdout = TRUE, stderr = TRUE),
      error = function(e) cli::cli_alert_warning("pub QC CLI failed: {e$message}")
    )
  }

  if (isTRUE(ctx$config$feishu$enable %||% FALSE) && exists("feishu_sync_project_summary", mode = "function")) {
    try(feishu_sync_project_summary(ctx), silent = TRUE)
  }
  cli::cli_alert_success("dbpool_batch_finalize: {pub_root}")
  ctx
}

register_block(
  "dbpool_batch_finalize", block_dbpool_batch_finalize,
  "数据库池化：batch 收口、发表清单与飞书钩子"
)
