#!/usr/bin/env Rscript
# 将全部【success】指标收口为与 GPR 相同的 fcimb 图序/版式
# Fig1 叠线 → Fig2 landmark KM → Fig3/4 dynpred(mortality) → Fig5/6 PAMM → summary
#
#   Rscript run/trajectory_prognosis/batch_rebuild_all_success_fcimb.R
#   Rscript run/trajectory_prognosis/batch_rebuild_all_success_fcimb.R --only BAR,AGR
#   Rscript run/trajectory_prognosis/batch_rebuild_all_success_fcimb.R --skip GPR
#   Rscript run/trajectory_prognosis/batch_rebuild_all_success_fcimb.R --skip-dynpred  # 仅图1/2/PAMM/build（调试）

suppressPackageStartupMessages({ options(warn = 1) })

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}
.has <- function(flag) !is.na(match(flag, .args))

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
log_dir <- file.path(proj, "reports/fcimb_rebuild_batch")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

success_dirs <- list.dirs(file.path(proj, "by_index"), recursive = FALSE, full.names = TRUE)
success_dirs <- success_dirs[grepl("\u3010success\u3011", basename(success_dirs))]
indices <- sub("^\u3010success\u3011", "", basename(success_dirs))
indices <- sort(unique(indices[nzchar(indices)]))

only <- .get("--only", "")
skip <- .get("--skip", "")
if (nzchar(only)) {
  keep <- trimws(unlist(strsplit(only, "[,;\\s]+")))
  indices <- intersect(indices, keep)
}
if (nzchar(skip)) {
  drop <- trimws(unlist(strsplit(skip, "[,;\\s]+")))
  indices <- setdiff(indices, drop)
}

skip_dyn <- .has("--skip-dynpred")
skip_pamm <- .has("--skip-pamm")
skip_fig12 <- .has("--skip-fig12")

.pick_rbin <- function() {
  cands <- c(
    file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"),
    "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe",
    "C:/Program Files/R/R-4.5.1/bin/Rscript.exe"
  )
  for (p in cands) if (nzchar(p) && file.exists(p)) return(p)
  "Rscript"
}
rbin <- .pick_rbin()
cli::cli_alert_info("Rscript = {rbin}")
.run <- function(script, ix, label) {
  sp <- normalizePath(file.path(.root, "run/trajectory_prognosis", script), winslash = "/", mustWork = TRUE)
  logf <- file.path(log_dir, sprintf("%s_%s.log", ix, label))
  message(sprintf("[%s] %s → %s", ix, label, basename(logf)))
  st <- system2(
    rbin,
    args = c("--vanilla", sp, "--index", ix, "--proj", proj),
    stdout = logf, stderr = logf
  )
  if (!identical(as.integer(st), 0L)) {
    message(sprintf("[%s] %s FAILED exit=%s", ix, label, as.character(st)))
    return(FALSE)
  }
  TRUE
}

# dynpred 入队后可能未落盘：从 checkpoint flush
.flush_dynpred_pdf <- function(ix) {
  source(file.path(.root, "R/utils.R"), local = TRUE)
  for (db in c("mimic", "eicu")) {
    ck <- file.path(proj, "checkpoints/by_index", ix, db, "trajectory_dynpred.rds")
    if (!file.exists(ck)) next
    packed <- tryCatch(readRDS(ck), error = function(e) NULL)
    if (is.null(packed)) next
    ctx <- packed$ctx %||% packed
    qn <- length(ctx$results$figure_queue %||% list())
    if (!qn) next
    db_out <- file.path(proj, paste0("by_index/\u3010success\u3011", ix), db)
    step_out <- file.path(db_out, "step18_trajectory_dynpred")
    dir.create(file.path(step_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
    ctx$output_dir <- step_out
    ctx$output_dir_figures <- file.path(step_out, "Figures")
    ctx$root_output_dir <- db_out
    ctx$config$project$mirror_pub_outputs_to_root <- TRUE
    ctx$config$project$output_dir <- db_out
    try(render_queued_figures(ctx), silent = TRUE)
    src <- list.files(file.path(step_out, "Figures"), pattern = "Dynpred", full.names = TRUE)
    if (!length(src)) next
    dest <- file.path(
      db_out, "Figures",
      if (identical(db, "mimic"))
        sprintf("Figure 3-MIMIC. Dynamic prediction of %s trajectory.pdf", ix)
      else
        sprintf("Figure 4-eICU. Dynamic prediction of %s trajectory.pdf", ix)
    )
    file.copy(src[which.max(file.info(src)$mtime)], dest, overwrite = TRUE)
    cli::cli_alert_success("{ix}/{db}: flush dynpred → {basename(dest)}")
  }
  invisible(TRUE)
}

cli::cli_h1("fcimb 收口批跑：{length(indices)} 个指标")
cli::cli_alert_info("{paste(indices, collapse = ', ')}")

status <- data.frame(
  index = indices,
  fig12 = NA, dynpred = NA, pamm = NA, build = NA,
  ok = FALSE, stringsAsFactors = FALSE
)

for (i in seq_along(indices)) {
  ix <- indices[[i]]
  cli::cli_h2("[{i}/{length(indices)}] {ix}")
  ok12 <- TRUE
  if (!skip_fig12) {
    ok12 <- isTRUE(.run("redraw_fcimb_fig1_trajectory.R", ix, "fig1")) &&
      isTRUE(.run("redraw_fcimb_fig2_landmark_km.R", ix, "fig2"))
  }
  status$fig12[i] <- ok12

  ok_dyn <- TRUE
  if (!skip_dyn) {
    ok_dyn <- isTRUE(.run("rerun_index_dynpred_fcimb.R", ix, "dynpred"))
    try(.flush_dynpred_pdf(ix), silent = TRUE)
  }
  status$dynpred[i] <- ok_dyn

  ok_pamm <- TRUE
  if (!skip_pamm) {
    ok_pamm <- isTRUE(.run("rerun_index_pamm_fcimb.R", ix, "pamm"))
  }
  status$pamm[i] <- ok_pamm

  ok_build <- isTRUE(.run("build_fcimb_summary_results.R", ix, "build"))
  status$build[i] <- ok_build
  status$ok[i] <- isTRUE(ok12) && isTRUE(ok_dyn) && isTRUE(ok_pamm) && isTRUE(ok_build)
}

out_csv <- file.path(log_dir, "batch_status.csv")
utils::write.csv(status, out_csv, row.names = FALSE)
cli::cli_alert_success("批跑结束：成功 {sum(status$ok)}/{nrow(status)} → {out_csv}")
print(status)
