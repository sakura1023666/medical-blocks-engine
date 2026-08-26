###############################################################################
#  cross_lagged_xs_flowchart.R — 横断面 Figure 1（无纵向的库，如 NHANES）
#
#  从 D01 baseline / 昼夜合并 dabiao / AfterMI 还原纳排，画出与通用 attrition
#  相同的框线图。纵向库仍用 phase3_long Figure 1-*. Longitudinal ...。
###############################################################################

cross_lagged_xs_fig1_basename <- function(db) {
  sprintf("Figure 1-%s. Inclusion exclusion flowchart.pdf", db)
}

.cross_lagged_xs_load_n <- function(path, prefer = c("dabiao", "object", "baseline")) {
  if (!file.exists(path)) return(NA_integer_)
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  for (nm in prefer) {
    if (nm %in% ls(e) && is.data.frame(e[[nm]])) return(as.integer(nrow(e[[nm]])))
  }
  dfs <- ls(e)[vapply(ls(e), function(x) is.data.frame(e[[x]]), logical(1))]
  if (length(dfs)) as.integer(nrow(e[[dfs[[1]]]])) else NA_integer_
}

.cross_lagged_xs_aftermi <- function(study_root, db) {
  p1 <- if (exists("cross_lagged_phase1_dir", mode = "function")) {
    cross_lagged_phase1_dir(study_root, db)
  } else {
    cands <- c(
      file.path(study_root, paste0("phase1_", db)),
      file.path(study_root, paste0("phase1_", db, "_allages"))
    )
    hit <- cands[dir.exists(cands)]
    if (length(hit)) hit[[1L]] else cands[[1L]]
  }
  hits <- c(
    file.path(p1, "step05_imputation", "D01_AfterMI_Data.RData"),
    file.path(p1, "step03_imputation", "D01_AfterMI_Data.RData"),
    Sys.glob(file.path(p1, "step*", "D01_AfterMI_Data.RData"))
  )
  hits <- hits[file.exists(hits)]
  if (!length(hits)) return(NULL)
  e <- new.env(parent = emptyenv())
  load(hits[[1L]], envir = e)
  d <- if ("object" %in% ls(e)) e$object else e[[ls(e)[1L]]]
  as.data.frame(d)
}

#' 画横断面 Figure 1；成功返回 pdf 路径，否则 NULL
cross_lagged_draw_xs_fig1 <- function(study_root, db,
                                      disease_event = "Circadian disorder",
                                      disease_ref = "No disorder") {
  db <- as.character(db)[1L]
  study_root <- as.character(study_root)[1L]
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

  if (!exists("attrition_draw_pdf", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(root)) root <- getwd()
    al <- file.path(root, "R/attrition_log.R")
    if (file.exists(al)) source(al, local = FALSE)
  }

  p1 <- if (exists("cross_lagged_phase1_dir", mode = "function")) {
    cross_lagged_phase1_dir(study_root, db)
  } else {
    file.path(study_root, paste0("phase1_", db))
  }
  fig_dir <- file.path(p1, "Figures")
  tab_dir <- file.path(p1, "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  id_rep <- file.path(study_root, "data/harmonized/id_align_report.csv")
  n_bl <- NA_integer_
  n_circ <- NA_integer_
  n_merge <- NA_integer_
  if (file.exists(id_rep)) {
    ir <- utils::read.csv(id_rep, stringsAsFactors = FALSE)
    ir <- ir[toupper(as.character(ir$cohort)) == toupper(db), , drop = FALSE]
    if (nrow(ir)) {
      # 取该库最后一行 overlap（NHANES: circ_SEQN_vs_bl）
      last <- ir[nrow(ir), ]
      n_circ <- as.integer(last$n_left)[1L]
      n_bl <- as.integer(last$n_right)[1L]
      n_merge <- as.integer(last$n_overlap)[1L]
    }
  }

  dab_n <- .cross_lagged_xs_load_n(
    file.path(study_root, "data/harmonized", paste0("D04_", db, "_circadian_baseline.RData"))
  )
  if (!is.finite(n_merge) && is.finite(dab_n)) n_merge <- dab_n

  after <- .cross_lagged_xs_aftermi(study_root, db)
  n_final <- if (!is.null(after)) nrow(after) else n_merge
  n_event <- n_ref <- NA_integer_
  if (!is.null(after) && "Disease_Group" %in% names(after)) {
    x <- as.character(after$Disease_Group)
    n_event <- sum(grepl("Disorder|disorder|Fracture|Dementia", x) &
                     !grepl("^No_|Normal", x), na.rm = TRUE)
    # 更稳：用众数以外的病例标签
    if ("Circadian_Disorder" %in% x) {
      n_event <- sum(x == "Circadian_Disorder", na.rm = TRUE)
      n_ref <- sum(x == "No_Disorder", na.rm = TRUE)
    } else {
      n_ref <- n_final - n_event
    }
  }

  n_epwv <- NA_integer_
  ck_ix <- file.path(p1, "checkpoints", "index.rds")
  if (file.exists(ck_ix)) {
    ck <- readRDS(ck_ix)
    if (!is.null(ck$ctx)) ck <- ck$ctx
    d0 <- ck$data$cleaned %||% ck$data$mapped
    if (is.data.frame(d0) && "ePWV" %in% names(d0)) {
      n_epwv <- as.integer(sum(!is.na(d0$ePWV)))
    }
  }

  steps <- list()
  add <- function(lab, n) {
    if (!is.finite(n) || n < 0L) return()
    steps[[length(steps) + 1L]] <<- data.frame(
      step = as.character(lab)[1L], n = as.integer(n)[1L], stringsAsFactors = FALSE
    )
  }
  add(sprintf("%s examined (baseline file)", db), n_bl)

  mi_note <- ""
  if (is.finite(n_epwv) && is.finite(n_final) && n_epwv < n_final) {
    mi_note <- sprintf(
      "\n(ePWV missing before MI n=%s; imputed, not excluded)",
      format(n_final - n_epwv, big.mark = ",")
    )
  }
  outcome_note <- sprintf(
    "\n%s n=%s; %s n=%s",
    disease_event,
    if (is.finite(n_event)) format(n_event, big.mark = ",") else "NA",
    disease_ref,
    if (is.finite(n_ref)) format(n_ref, big.mark = ",") else "NA"
  )
  if (is.finite(n_merge) && is.finite(n_final) && n_merge != n_final) {
    add("Linked circadian / DN assessment", n_merge)
    add(paste0("Final analytic sample after multiple imputation", mi_note, outcome_note), n_final)
  } else {
    add(paste0(
      "Linked circadian / DN assessment (analytic sample after MI)",
      mi_note, outcome_note
    ), n_final %||% n_merge)
  }

  rows <- do.call(rbind, steps)
  if (is.null(rows) || !nrow(rows)) return(invisible(NULL))

  csv_path <- file.path(tab_dir, paste0("Flowchart_attrition_", db, "_xs.csv"))
  utils::write.csv(rows, csv_path, row.names = FALSE)

  pdf_name <- cross_lagged_xs_fig1_basename(db)
  pdf_path <- file.path(fig_dir, pdf_name)
  title <- sprintf("Figure 1. %s — Inclusion / Exclusion (cross-section)", db)
  ok <- FALSE
  if (exists("attrition_draw_pdf", mode = "function")) {
    ok <- isTRUE(attrition_draw_pdf(rows, title, pdf_path))
  }
  if (!ok) {
    grDevices::pdf(pdf_path, width = 8.5, height = 10)
    graphics::par(mar = c(1, 1, 2, 1))
    graphics::plot.new()
    graphics::title(main = title, cex.main = 1.15)
    txt <- sprintf("%s  N = %s", rows$step, format(rows$n, big.mark = ","))
    graphics::text(0.08, seq(0.9, 0.15, length.out = length(txt)), txt, adj = 0, cex = 1.05)
    grDevices::dev.off()
  }
  pdf_path
}
