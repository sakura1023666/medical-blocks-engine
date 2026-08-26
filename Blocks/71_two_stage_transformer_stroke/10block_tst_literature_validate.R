###############################################################################
#  tst_literature_validate — Yang 2025 PCM 原文指标对照（Table_Literature_Validation）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §7–8
#        Decisiontree/decision_tree_two_stage_transformer_stroke.md §原文对照
#
#  config$literature_targets（可选）:
#    list(
#      tol_pct = 15,
#      rows = data.frame(target, literature, default_status, key)  # 或 list of list
#    )
#  缺省时使用 Yang 2025 硬编码目标；卒中 MIMIC vs eICU 脓毒症 → migrate/skip。
#
#  产出: Tables/Table_Literature_Validation.csv
#        columns: target, observed, status ∈ {match, migrate, skip, synthetic}
#
#  规则:
#    - 合成外推指标 observed 可填，但 status 恒为 synthetic，不得 match
#    - 外推 1（中国三甲）无第二中心 → skip
#    - 内部 Day5 AUC：容差内 match，否则 migrate
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(a))) b else a

.tst71_root <- function(ctx) ctx$config$project$root %||% getwd()

.tst71_table_search_dirs <- function(ctx) {
  dirs <- character(0)
  bod <- ctx$log$block_output_dirs %||% list()
  for (d in bod) {
    if (is.character(d) && nzchar(d)) dirs <- c(dirs, file.path(d, "Tables"))
  }
  out_tbl <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  dirs <- c(dirs, out_tbl)
  root <- .tst71_root(ctx)
  smoke_glob <- Sys.glob(file.path(root, "Output", "_smoke*", "*", "Tables"))
  dirs <- c(dirs, smoke_glob)
  smoke_glob2 <- Sys.glob(file.path(root, "Output", "TwoStage_Transformer_Stroke", "*", "Tables"))
  dirs <- c(dirs, smoke_glob2)
  unique(dirs[dir.exists(dirs)])
}

.tst71_find_metrics_csv <- function(ctx, pattern) {
  for (d in .tst71_table_search_dirs(ctx)) {
    hits <- list.files(d, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
    if (length(hits)) return(hits[[length(hits)]])
  }
  NA_character_
}

.tst71_read_metrics <- function(ctx) {
  mp <- ctx$results$tst_train_eval$metrics_path %||% ""
  if (nzchar(mp) && file.exists(mp)) {
    return(utils::read.csv(mp, stringsAsFactors = FALSE))
  }
  path <- .tst71_find_metrics_csv(ctx, "^Table_TST_Metrics_.*\\.csv$")
  if (!is.na(path)) return(utils::read.csv(path, stringsAsFactors = FALSE))
  data.frame()
}

.tst71_read_external_metrics <- function(ctx) {
  mp <- ctx$results$tst_external$metrics_path %||% ""
  if (nzchar(mp) && file.exists(mp)) {
    return(utils::read.csv(mp, stringsAsFactors = FALSE))
  }
  for (pat in c("^Table_External_Synthetic_Metrics\\.csv$", "^Table_External_Real_Metrics\\.csv$")) {
    path <- .tst71_find_metrics_csv(ctx, pat)
    if (!is.na(path)) return(utils::read.csv(path, stringsAsFactors = FALSE))
  }
  data.frame()
}

.tst71_pick_day5_auc <- function(df, split_pref = c("test", "val", "internal")) {
  if (!nrow(df) || !"auc" %in% names(df)) return(NA_real_)
  sub <- df
  if ("day" %in% names(sub)) sub <- sub[as.integer(sub$day) == 5L, , drop = FALSE]
  if (!nrow(sub)) return(NA_real_)
  if ("split" %in% names(sub)) {
    for (sp in split_pref) {
      hit <- sub[grepl(sp, sub$split, ignore.case = TRUE), , drop = FALSE]
      if (nrow(hit)) sub <- hit
    }
  }
  if ("is_synthetic" %in% names(sub)) {
    syn <- toupper(as.character(sub$is_synthetic)) %in% c("TRUE", "T", "1")
    if (any(syn)) sub <- sub[syn, , drop = FALSE]
  }
  suppressWarnings(as.numeric(mean(sub$auc, na.rm = TRUE)))
}

.tst71_external_is_synthetic <- function(ctx, ext_df) {
  if (isTRUE(ctx$results$tst_external$is_synthetic)) return(TRUE)
  if (nrow(ext_df) && "is_synthetic" %in% names(ext_df)) {
    return(all(toupper(as.character(ext_df$is_synthetic)) %in% c("TRUE", "T", "1")))
  }
  mp <- ctx$results$tst_external$metrics_path %||% ""
  if (nzchar(mp) && grepl("Synthetic", mp, ignore.case = TRUE)) return(TRUE)
  path <- .tst71_find_metrics_csv(ctx, "^Table_External_Synthetic_Metrics\\.csv$")
  !is.na(path)
}

.tst71_default_literature_targets <- function() {
  data.frame(
    target = c(
      "Internal validation Day5 AUC (Yang 2025, eICU sepsis development cohort)",
      "External validation 1: China tertiary ICU sepsis AUC (Results, n=417)",
      "External validation 2: MIMIC-IV sepsis ICD AUC (Results)"
    ),
    literature = c(0.92, 0.73, 0.84),
    default_status = c("migrate", "skip", "migrate"),
    key = c("internal_day5_auc", "external_china_auc", "external_mimic_sepsis_auc"),
    stringsAsFactors = FALSE
  )
}

.tst71_normalize_targets <- function(lt_cfg) {
  if (is.null(lt_cfg) || !length(lt_cfg)) return(.tst71_default_literature_targets())
  rows <- lt_cfg$rows %||% lt_cfg$targets %||% lt_cfg
  if (is.data.frame(rows) && nrow(rows)) {
    out <- rows
    if (!"literature" %in% names(out) && "value" %in% names(out)) out$literature <- out$value
    if (!"default_status" %in% names(out) && "status" %in% names(out)) out$default_status <- out$status
    if (!"key" %in% names(out)) out$key <- paste0("target_", seq_len(nrow(out)))
    return(out[, intersect(c("target", "literature", "default_status", "key"), names(out)), drop = FALSE])
  }
  if (is.list(rows) && length(rows) && !is.data.frame(rows)) {
    df <- do.call(rbind, lapply(rows, function(r) {
      data.frame(
        target = as.character(r$target %||% r$label %||% ""),
        literature = as.numeric(r$literature %||% r$value %||% NA_real_),
        default_status = as.character(r$default_status %||% r$status %||% "migrate"),
        key = as.character(r$key %||% r$id %||% ""),
        stringsAsFactors = FALSE
      )
    }))
    if (nrow(df)) return(df)
  }
  .tst71_default_literature_targets()
}

.tst71_assign_status <- function(key, observed, literature, default_status,
                                 ext_synthetic, tol_pct) {
  ds <- tolower(as.character(default_status %||% "migrate")[1L])
  if (ds == "skip") return("skip")
  if (key == "external_mimic_sepsis_auc" && isTRUE(ext_synthetic)) return("synthetic")
  if (is.na(observed) || !is.finite(observed)) return(ds)
  if (ds == "synthetic") return("synthetic")
  if (key == "internal_day5_auc" && is.finite(literature) && literature != 0) {
    pct <- abs(observed - literature) / abs(literature) * 100
    if (pct <= tol_pct) return("match")
    return("migrate")
  }
  if (key == "external_mimic_sepsis_auc") return("migrate")
  ds
}

block_tst_literature_validate <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  lt_cfg <- cfg$literature_targets %||% list()
  tol <- as.numeric(lt_cfg$tol_pct %||% lt_cfg$literature_tol_pct %||% 15)[1L]
  targets <- .tst71_normalize_targets(lt_cfg)

  int_met <- .tst71_read_metrics(ctx)
  ext_met <- .tst71_read_external_metrics(ctx)
  ext_syn <- .tst71_external_is_synthetic(ctx, ext_met)

  observed_map <- list(
    internal_day5_auc = .tst71_pick_day5_auc(int_met),
    external_china_auc = NA_real_,
    external_mimic_sepsis_auc = .tst71_pick_day5_auc(ext_met)
  )

  rows <- lapply(seq_len(nrow(targets)), function(i) {
    key <- as.character(targets$key[i])
    lit <- suppressWarnings(as.numeric(targets$literature[i]))
    obs <- observed_map[[key]] %||% NA_real_
    ds <- as.character(targets$default_status[i])
    st <- .tst71_assign_status(key, obs, lit, ds, ext_syn, tol)
    data.frame(
      target = as.character(targets$target[i]),
      observed = if (is.finite(obs)) round(obs, 4) else NA_real_,
      status = st,
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)

  out_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(out_dir, "Table_Literature_Validation.csv")
  utils::write.csv(tab, out_path, row.names = FALSE)

  n_match <- sum(tab$status == "match", na.rm = TRUE)
  n_syn <- sum(tab$status == "synthetic", na.rm = TRUE)
  ctx$results$tst_literature_validate <- list(
    table = tab,
    path = out_path,
    tol_pct = tol,
    n_match = n_match,
    n_synthetic = n_syn,
    ext_synthetic = ext_syn
  )
  cli::cli_alert_success(
    "tst_literature_validate: {nrow(tab)} 行 (match={n_match}, synthetic={n_syn}) → {basename(out_path)}"
  )
  ctx
}

register_block(
  "tst_literature_validate",
  block_tst_literature_validate,
  "两阶段 Transformer 卒中：Yang 2025 文献指标对照"
)
