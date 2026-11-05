###############################################################################
# jin_index_sofa_pub.R — Jin2025 (PMID 41194138) 发表图/表角色
#
# 原文主文图序（用户确认，禁止再改成「Fig1=流程图」的预后默认）：
#   Fig1 RCS | Fig2 Nomogram | Fig3 SHAP | Fig4 Mediation
#   FigS1 Flowchart | FigS2 KM (index×SOFA) | FigS3 Calibration
# 亚组森林 → 补充图 S4（原文亚组为 Table S1–S3，不作主文 Fig）
# Boxplot / 普通 ROC → 丢弃出交付面（或另作更后 S，默认 drop）
###############################################################################

jin_index_sofa_is_pub_scheme <- function(config = NULL) {
  if (is.null(config) || !is.list(config)) return(FALSE)
  scheme <- NA_character_
  if (exists("incidence_batch_pub_figure_scheme", mode = "function")) {
    scheme <- tryCatch(
      incidence_batch_pub_figure_scheme(config),
      error = function(e) NA_character_
    )
  }
  if (is.na(scheme) || !nzchar(as.character(scheme)[1L])) {
    bc <- config$survival_batch %||% config$incidence_batch %||%
      config$ml_batch %||% list()
    scheme <- as.character(bc$pub_figure_scheme %||% "")[1L]
  }
  identical(tolower(as.character(scheme)[1L]), "jin_index_sofa")
}

jin_index_sofa_figure_role <- function(bn) {
  bn <- as.character(bn)[1L]
  if (!nzchar(bn)) return("drop")
  if (grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Cutoff Point|maxstat", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Boxplot", bn, ignore.case = TRUE)) return("drop")
  if (grepl("\\bROC\\b", bn, ignore.case = TRUE) &&
      !grepl("Nomogram|SHAP|Calibration", bn, ignore.case = TRUE)) {
    return("drop")
  }
  # 原文 S1 = flowchart（不是主文 Fig1）
  if (grepl("Flowchart|Inclusion exclusion", bn, ignore.case = TRUE)) {
    return("s1_flowchart")
  }
  # Fig1 = SOFA×多时点 2×3；旧 Crude/Model1/Model2 RCS 降为 drop
  if (grepl("SOFA and mortality horizon|by SOFA|RCS of .+ by SOFA", bn, ignore.case = TRUE)) {
    return("fig1_rcs")
  }
  if (grepl("RCS Analysis|RCS of|RCS plot|\\bRCS\\b|Restricted Cubic", bn, ignore.case = TRUE)) {
    return("drop")
  }
  # Fig2 = 院内/30d/365d × 双库六页全宽（禁止 MIMIC|eICU 左右并排当 A/B）
  if (grepl("Nomogram", bn, ignore.case = TRUE)) return("fig2_nomogram")
  if (grepl("\\bSHAP\\b", bn, ignore.case = TRUE)) {
    # 主文 Fig3 = beeswarm/summary；importance 另作 S5，避免与 Fig3 抢同一角色键被删
    if (grepl("importance|bar", bn, ignore.case = TRUE) &&
        !grepl("beeswarm|summary", bn, ignore.case = TRUE)) {
      return("s5_shap_importance")
    }
    return("fig3_shap")
  }
  if (grepl("Mediation|mediator|path diagram|Path diagram", bn, ignore.case = TRUE)) {
    return("fig4_mediation")
  }
  if (grepl("Kaplan", bn, ignore.case = TRUE)) return("s2_km")
  if (grepl("Calibration", bn, ignore.case = TRUE)) return("s3_calibration")
  if (grepl("Subgroup Forest|Subgroup analyses", bn, ignore.case = TRUE)) {
    return("s4_subgroup")
  }
  "other"
}

jin_index_sofa_figure_clean_cap <- function(src_bn) {
  cap <- as.character(src_bn)[1L]
  cap <- sub("^Figure (?:S)?[0-9]+(?:-[A-Za-z0-9_]+)?\\. ", "", cap, perl = TRUE)
  cap <- sub("^Figure\\.\\s*", "", cap, perl = TRUE)
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  trimws(cap)
}

jin_index_sofa_figure_target_bn <- function(role, src_bn, db = NA_character_) {
  db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
  cap <- jin_index_sofa_figure_clean_cap(src_bn)
  switch(
    role,
    fig1_rcs = sprintf("Figure 1%s. %s.pdf", db_sfx, cap),
    fig2_nomogram = {
      if (grepl("in-hospital,\\s*30-day|three horizon|30-day and 365", cap, ignore.case = TRUE)) {
        sprintf("Figure 2%s. Nomogram for in-hospital, 30-day and 365-day mortality.pdf", db_sfx)
      } else if (grepl("Nomogram", cap, ignore.case = TRUE)) {
        sprintf("Figure 2%s. Nomogram for in-hospital, 30-day and 365-day mortality.pdf", db_sfx)
      } else {
        sprintf("Figure 2%s. %s.pdf", db_sfx, cap)
      }
    },
    fig3_shap = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    fig4_mediation = sprintf("Figure 4%s. %s.pdf", db_sfx, cap),
    s1_flowchart = {
      if (grepl("Inclusion exclusion|flowchart", cap, ignore.case = TRUE)) {
        sprintf("Figure S1%s. Inclusion exclusion flowchart.pdf", db_sfx)
      } else {
        sprintf("Figure S1%s. %s.pdf", db_sfx, cap)
      }
    },
    s2_km = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    s3_calibration = sprintf("Figure S3%s. %s.pdf", db_sfx, cap),
    s4_subgroup = sprintf("Figure S4%s. %s.pdf", db_sfx, cap),
    s5_shap_importance = sprintf("Figure S5%s. %s.pdf", db_sfx, cap),
    NULL
  )
}

jin_index_sofa_curate_figures_dir <- function(figures_dir, config = NULL) {
  if (!exists("incidence_batch_dedupe_pub_figures_by_role", mode = "function")) {
    stop("jin_index_sofa_curate_figures_dir: 缺少 incidence_batch_dedupe_pub_figures_by_role",
         call. = FALSE)
  }
  incidence_batch_dedupe_pub_figures_by_role(
    figures_dir,
    config,
    role_fn = jin_index_sofa_figure_role,
    target_fn = jin_index_sofa_figure_target_bn
  )
}

#' 把多时点 Index×SOFA Cox 升为 Table 2；原 quartile 关联表降为 Table S（或归档）
jin_index_sofa_curate_tables_dir <- function(tables_dir, index_lab = NULL) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  n <- 0L
  ix <- as.character(index_lab %||% "")[1L]
  if (!nzchar(ix)) ix <- "Index"

  # multi-horizon → Table 2
  mh <- files[grepl("Multi-horizon|multi.horizon|Index_SOFA_Q", basename(files), ignore.case = TRUE)]
  for (f in mh) {
    bn <- basename(f)
    db <- NA_character_
    for (d in c("MIMIC", "eICU", "NHANES")) {
      if (grepl(paste0("-", d, "\\."), bn, fixed = FALSE) ||
          grepl(paste0("-", d, "\\s"), bn)) {
        db <- d; break
      }
    }
    # also try from parent path context via filename tokens
    if (is.na(db)) {
      m <- regmatches(bn, regexpr("-(MIMIC|eICU|NHANES)\\.", bn, perl = TRUE))
      if (length(m) && nzchar(m)) db <- gsub("[-.]", "", m)
    }
    db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
    tgt <- file.path(
      tables_dir,
      sprintf(
        "Table 2%s. Cox models for mortality by %s and SOFA strata.xlsx",
        db_sfx, ix
      )
    )
    if (!identical(normalizePath(f, winslash = "/", mustWork = FALSE),
                   normalizePath(tgt, winslash = "/", mustWork = FALSE))) {
      if (file.exists(tgt)) unlink(tgt)
      ok <- file.rename(f, tgt)
      if (!isTRUE(ok)) file.copy(f, tgt, overwrite = TRUE)
      if (!identical(f, tgt) && file.exists(f)) unlink(f)
      n <- n + 1L
    }
  }

  # 原「Association Between index」quartile 表：若仍叫 Table 2 且无 SOFA，降为 Table Sx
  assoc <- list.files(
    tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE
  )
  assoc <- assoc[grepl("^Table 2", basename(assoc), ignore.case = TRUE)]
  assoc <- assoc[grepl("Association Between", basename(assoc), ignore.case = TRUE)]
  for (f in assoc) {
    bn <- basename(f)
    db_sfx <- ""
    m <- regmatches(bn, regexpr("-(MIMIC|eICU|NHANES)", bn, perl = TRUE))
    if (length(m) && nzchar(m[[1L]])) db_sfx <- m[[1L]]
    tgt <- file.path(
      tables_dir,
      sprintf("Table S8%s. Quartile Cox association of %s (engine supplement).xlsx", db_sfx, ix)
    )
    if (file.exists(tgt)) {
      # keep existing S8; archive
      arch <- file.path(tables_dir, "_archive_identical")
      dir.create(arch, showWarnings = FALSE, recursive = TRUE)
      file.rename(f, file.path(arch, bn))
    } else {
      file.rename(f, tgt)
    }
    n <- n + 1L
  }
  invisible(n)
}
