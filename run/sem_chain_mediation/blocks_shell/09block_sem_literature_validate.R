###############################################################################
#  sem_literature_validate — 与 Zhu 2025 原文 HR / 间接效应对照
###############################################################################

block_sem_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)

  targets <- bl$literature_targets %||% list(
    depression_frailty_HR = 1.371,
    depression_frailty_CI_lo = 1.156,
    depression_frailty_CI_hi = 1.586,
    cognitive_frailty_HR = 1.514,
    cognitive_frailty_CI_lo = 1.203,
    cognitive_frailty_CI_hi = 1.907,
    sarcopenia_frailty_HR = 1.456,
    sarcopenia_frailty_CI_lo = 1.156,
    sarcopenia_frailty_CI_hi = 1.834
  )
  tol <- as.numeric(bl$literature_tol_pct %||% 20)

  cox_tab <- (ctx$results$sem_cox_baseline %||% list())$table
  if (is.null(cox_tab) || !nrow(cox_tab)) {
    p <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Cox_Baseline_Paths.csv")
    if (file.exists(p)) cox_tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  }

  rows <- list()
  if (!is.null(cox_tab) && nrow(cox_tab)) {
    pick_hr <- function(model_kw, term_kw) {
      hit <- cox_tab[grepl(model_kw, cox_tab$model, ignore.case = TRUE) &
                       grepl(term_kw, cox_tab$term, ignore.case = TRUE), , drop = FALSE]
      if (!nrow(hit)) return(list(HR = NA, lo = NA, hi = NA))
      list(HR = hit$HR[1L], lo = hit$lower[1L], hi = hit$upper[1L])
    }
    dep <- pick_hr("Depression", "Depression")
    cog <- pick_hr("Cognitive", "Cognitive")
    sar <- pick_hr("Sarcopenia", "Sarcopenia")
    rows[[length(rows) + 1L]] <- literature_compare_metric(dep$HR, targets$depression_frailty_HR, tol, "Depression->Frailty HR")
    rows[[length(rows) + 1L]] <- literature_compare_metric(cog$HR, targets$cognitive_frailty_HR, tol, "Cognitive->Frailty HR")
    rows[[length(rows) + 1L]] <- literature_compare_metric(sar$HR, targets$sarcopenia_frailty_HR, tol, "Sarcopenia->Frailty HR")
  }

  chain_tab <- (ctx$results$sem_cox_chain_mediation %||% list())$table
  if (is.null(chain_tab)) {
    p <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Cox_Chain_Mediation_Bootstrap.csv")
    if (file.exists(p)) chain_tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  }
  if (!is.null(chain_tab) && nrow(chain_tab)) {
    ich <- chain_tab[chain_tab$effect == "indirect_chain_hr", , drop = FALSE]
    if (nrow(ich)) {
      rows[[length(rows) + 1L]] <- literature_compare_metric(
        ich$point[1L], bl$literature_chain_hr_target %||% NA, tol, "Chain indirect HR (Sarc→Dep→Cog→Frailty)"
      )
    }
  }

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Literature_Validation.csv")
  tab <- literature_write_validation(rows, out, meta = list(paper = "Zhu 2025 J Adv Research", tol_pct = tol))
  n_ok <- sum(tab$within_tol %in% TRUE, na.rm = TRUE)
  n_tot <- sum(!is.na(tab$within_tol))
  ctx$results$sem_literature_validate <- list(table = tab, pass = n_ok, total = n_tot)
  cli::cli_alert_success("SEM 文献对照: {n_ok}/{n_tot} 指标在 ±{tol}% 内")
  ctx
}

register_block("sem_literature_validate", block_sem_literature_validate, "SEM 原文 HR 对照")
