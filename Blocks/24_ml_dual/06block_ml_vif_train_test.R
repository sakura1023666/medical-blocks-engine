###############################################################################
#  ml_vif_train_test — VIF screen on train + test (or imputed once)
#
#  register_block: "ml_vif_train_test"
#  依赖: R/ml_assoc_data_slots.R（ml_vif_resolve_slots, ml_assoc_run_on_slot）
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

.ml_vif_ensure_helpers <- function(ctx) {
  if (exists("ml_vif_resolve_slots", mode = "function")) return(invisible(NULL))
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  helper <- file.path(root, "R/ml_assoc_data_slots.R")
  if (file.exists(helper)) source(helper, local = FALSE)
}

.ml_vif_ensure_suffix <- function(ctx) {
  if (exists("ml_assoc_suffix_recent_outputs", mode = "function")) return(invisible(NULL))
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  assoc <- file.path(root, "Blocks/24_ml_dual/05block_ml_assoc_bundle.R")
  if (file.exists(assoc)) source(assoc, local = FALSE)
}

block_ml_vif_train_test <- function(ctx, ...) {
  .ml_vif_ensure_helpers(ctx)
  .ml_vif_ensure_suffix(ctx)
  mc <- ctx$config$multicollinearity %||% list()
  ## 默认：只在训练集上做 VIF 筛选；验证集不再重筛（避免两套变量）
  ## config$multicollinearity$selection_on = "train" | "train_and_test" | "imputed"
  selection_on <- tolower(as.character(
    mc$selection_on %||% mc$vif_selection_on %||% "train"
  )[1L])
  slots <- ml_vif_resolve_slots(ctx)
  if (identical(selection_on, "train") && any(slots$slot == "train")) {
    slots <- slots[slots$slot == "train", , drop = FALSE]
    cli::cli_alert_info(
      "ml_vif_train_test: VIF 筛选仅用训练集（selection_on=train）；下游 ML/表统一用训练集通过变量。"
    )
  } else if (identical(selection_on, "imputed")) {
    slots <- data.frame(slot = "imputed", label = "", stringsAsFactors = FALSE)
  }
  preserve <- ml_vif_preserve_downstream_keys()
  primary_slot <- if (nrow(slots) >= 1L && any(slots$slot == "train")) "train" else slots$slot[[1L]]
  for (i in seq_len(nrow(slots))) {
    slot <- slots$slot[[i]]
    label <- slots$label[[i]]
    snap <- if (!identical(slot, primary_slot) && length(preserve)) {
      ctx$results[preserve]
    } else {
      NULL
    }
    t0 <- Sys.time()
    ctx <- ml_assoc_run_on_slot(ctx, slot, label, "multicollinearity_screen")
    if (exists("ml_assoc_suffix_recent_outputs", mode = "function")) {
      ml_assoc_suffix_recent_outputs(ctx, label, since = t0)
    }
    if (!is.null(snap)) {
      for (k in names(snap)) ctx$results[[k]] <- snap[[k]]
    }
  }
  ## 筛选只在训练集；holdout 用同一变量集出报告表（不再重筛）
  if (exists("ml_vif_export_fixed_set", mode = "function")) {
    report_slots <- unique(as.character(mc$report_slots %||% character(0)))
    if (!length(report_slots) && identical(selection_on, "train") &&
        is.data.frame(ctx$data$test) && nrow(ctx$data$test) > 0L) {
      report_slots <- "test"
    }
    vars <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
    vars <- vars[nzchar(vars)]
    for (rs in report_slots) {
      dat <- ctx$data[[rs]]
      if (!is.data.frame(dat) || !nrow(dat) || !length(vars)) next
      cap <- if (exists("ml_vif_holdout_caption", mode = "function")) {
        ml_vif_holdout_caption(rs, ctx$config)
      } else {
        "Multicollinearity Analysis VIF screen (validation set)"
      }
      ml_vif_export_fixed_set(ctx, dat, vars, cap)
    }
  }
  ctx
}

register_block(
  "ml_vif_train_test",
  block_ml_vif_train_test,
  "VIF screen：train/test 各一份（无 test 则 imputed 一次）"
)
