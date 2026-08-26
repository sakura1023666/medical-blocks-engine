###############################################################################
#  trajectory_pub_curate.R — 轨迹预后发表图表整理（白名单顺序）
#
#  以 by_index/*/mimic 根目录 Figures/Tables 为发表交付；其余中间产物归档。
#  缺项跳过（不造假表）；Fig1 为纳排占位 PDF。
#
#  Figures（顺序）:
#    Figure 1-{DB}. Flowchart of patient selection.pdf
#    Figure 2-{DB}. Trajectory of {IX} latent classes.pdf
#    Figure 3-{DB}. Dynamic prediction of {IX} trajectory.pdf
#    Figure 4-{DB}. Individual dynamic prediction.pdf
#    Figure S1-{DB}. Missing value overview.pdf
#    Figure S2-{DB}. Kaplan Meier survival by trajectory class.pdf
#    Figure S3-{DB}. Piecewise Cox cut point search.pdf
#    Figure S4-{DB}. Subgroup analysis by trajectory class.pdf
#    Figure S5-{DB}. Weibull dynamic model comparison AUC.pdf
#    Figure S6-{DB}. Weibull dynamic model comparison C index.pdf
#    Figure S7-{DB}. Weibull dynamic model comparison Accuracy.pdf
#    Figure S8-{DB}. Weibull dynamic model comparison Sensitivity.pdf
#    Figure S9-{DB}. Weibull dynamic model comparison Specificity.pdf
#    _raw/  ← 未入白名单的原始图
#
#  Tables（顺序）:
#    Table 1-{DB}. Baseline characteristics of {disease}.xlsx
#    Table 2-{DB}. Metrics for determining the optimal number of classes.xlsx
#    Table 3-{DB}. Time-dependent HR for trajectory classes.xlsx
#    Table S1-{DB}. Baseline characteristics of patients before and after multiple imputation.xlsx
#    Table S2-{DB}. Normality test results for continuous variables.xlsx
#    Table S3-{DB}. Univariate Regression Analysis.xlsx
#    Table S4-{DB}. Multicollinearity Analysis (VIF, univariate screen).xlsx
#    Table S5-{DB}. Multivariable Regression Analysis.xlsx
#    Table S6-{DB}. Multicollinearity Analysis (VIF, multivariate final).xlsx
#    Table S7-{DB}. Baseline characteristics by trajectory class ({IX}).xlsx
#    Table S8-{DB}. Posterior classification table.xlsx
#    Summary/  ← optimal_ng / FinalCovariates
#    _archive/ ← 中间 CSV、错号表等
###############################################################################

trajectory_read_optimal_ng <- function(root_or_tables, index_name) {
  ix <- as.character(index_name)[1L]
  cands <- c(
    file.path(root_or_tables, "Tables", "Summary", paste0("optimal_ng_", ix, ".txt")),
    file.path(root_or_tables, "Summary", paste0("optimal_ng_", ix, ".txt")),
    file.path(root_or_tables, paste0("optimal_ng_", ix, ".txt"))
  )
  for (p in cands) {
    if (!file.exists(p)) next
    ng <- suppressWarnings(as.integer(trimws(readLines(p, warn = FALSE)[1L])))
    if (is.finite(ng) && ng >= 1L) return(ng)
  }
  NA_integer_
}

trajectory_paper_main_figure_specs <- function(db_lab, index_name = "NLR",
                                               optimal_ng = NA_integer_) {
  db_lab <- as.character(db_lab)[1L]
  ix <- as.character(index_name)[1L]
  ng <- suppressWarnings(as.integer(optimal_ng)[1L])
  prefer_traj <- if (is.finite(ng)) sprintf("Figure Trajectory %s D%d.pdf", ix, ng) else
    sprintf("Figure Trajectory %s D2.pdf", ix)
  prefer_dyn <- if (is.finite(ng)) sprintf("Figure Dynpred %s D%d.pdf", ix, ng) else
    sprintf("Figure Dynpred %s D2.pdf", ix)

  list(
    list(
      key = "fig1_placeholder",
      dest = sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab),
      placeholder = TRUE
    ),
    list(
      key = "trajectory",
      src_pat = sprintf("^Figure Trajectory %s D[0-9]+\\.pdf$", ix),
      dest = sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix),
      prefer = prefer_traj
    ),
    list(
      key = "dynpred",
      src_pat = sprintf("^Figure Dynpred %s D[0-9]+\\.pdf$", ix),
      dest = sprintf("Figure 3-%s. Dynamic prediction of %s trajectory.pdf", db_lab, ix),
      prefer = prefer_dyn
    ),
    list(
      key = "individual",
      src_pat = sprintf("^Figure Dynpred Individual %s\\.pdf$", ix),
      dest = sprintf("Figure 4-%s. Individual dynamic prediction.pdf", db_lab)
    )
  )
}

trajectory_paper_supp_figure_specs <- function(db_lab, index_name = "NLR") {
  db_lab <- as.character(db_lab)[1L]
  ix <- as.character(index_name)[1L]
  list(
    list(src_pat = "^Figure Missing Value Overview\\.pdf$",
         dest = sprintf("Figure S1-%s. Missing value overview.pdf", db_lab)),
    list(src_pat = sprintf("^Figure KM TrajectoryClass %s\\.pdf$", ix),
         dest = sprintf("Figure S2-%s. Kaplan Meier survival by trajectory class.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Piecewise Cox CutSearch %s\\.pdf$", ix),
         dest = sprintf("Figure S3-%s. Piecewise Cox cut point search.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Subgroup TrajectoryClass %s\\.pdf$", ix),
         dest = sprintf("Figure S4-%s. Subgroup analysis by trajectory class.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Weibull Dynamic Compare %s AUC\\.pdf$", ix),
         dest = sprintf("Figure S5-%s. Weibull dynamic model comparison AUC.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Weibull Dynamic Compare %s Cindex\\.pdf$", ix),
         dest = sprintf("Figure S6-%s. Weibull dynamic model comparison C index.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Weibull Dynamic Compare %s Accuracy\\.pdf$", ix),
         dest = sprintf("Figure S7-%s. Weibull dynamic model comparison Accuracy.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Weibull Dynamic Compare %s Sensitivity\\.pdf$", ix),
         dest = sprintf("Figure S8-%s. Weibull dynamic model comparison Sensitivity.pdf", db_lab)),
    list(src_pat = sprintf("^Figure Weibull Dynamic Compare %s Specificity\\.pdf$", ix),
         dest = sprintf("Figure S9-%s. Weibull dynamic model comparison Specificity.pdf", db_lab))
  )
}

trajectory_write_figure1_placeholder <- function(file_out, db_lab = "MIMIC",
                                                 disease = "ischemic stroke") {
  dir.create(dirname(file_out), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(file_out, width = 8, height = 10, useDingbats = FALSE)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::plot.new()
  graphics::text(0.5, 0.62, sprintf("Figure 1. Flowchart of patient selection (%s)", db_lab),
                 cex = 1.3, font = 2)
  graphics::text(0.5, 0.48, "【PLACEHOLDER】请在此处插入纳排流程图（CONSORT）",
                 cex = 1.05, col = "gray30")
  graphics::text(0.5, 0.36, disease, cex = 1)
  graphics::rect(0.15, 0.2, 0.85, 0.75, border = "gray60", lty = 2)
  invisible(file_out)
}

.pick_figure_src <- function(files, spec) {
  if (isTRUE(spec$placeholder)) return(NA_character_)
  if (!is.null(spec$prefer)) {
    hit <- files[basename(files) == spec$prefer]
    if (length(hit)) return(hit[1L])
  }
  pat <- spec$src_pat
  hits <- files[grepl(pat, basename(files), perl = TRUE)]
  if (!length(hits)) return(NA_character_)
  hits[which.max(file.info(hits)$mtime)]
}

trajectory_curate_figures_dir <- function(fig_dir, db_lab, index_name = "NLR",
                                          disease = "ischemic stroke",
                                          optimal_ng = NA_integer_) {
  if (!dir.exists(fig_dir)) return(invisible(list(curated = character(0), archived = character(0))))
  raw_dir <- file.path(fig_dir, "_raw")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

  all_pdf <- list.files(fig_dir, pattern = "\\.pdf$", full.names = TRUE,
                        ignore.case = TRUE, recursive = TRUE)
  all_pdf <- all_pdf[!grepl("/_raw/", all_pdf, fixed = TRUE)]
  raw_pdf <- list.files(raw_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  pool_pdf <- unique(c(all_pdf, raw_pdf))

  curated <- character(0)
  used_src <- character(0)

  for (spec in trajectory_paper_main_figure_specs(db_lab, index_name, optimal_ng)) {
    dest <- file.path(fig_dir, spec$dest)
    if (isTRUE(spec$placeholder)) {
      trajectory_write_figure1_placeholder(dest, db_lab, disease)
      curated <- c(curated, dest)
      next
    }
    src <- .pick_figure_src(pool_pdf, spec)
    if (is.na(src)) next
    file.copy(src, dest, overwrite = TRUE)
    curated <- c(curated, dest)
    used_src <- c(used_src, src)
  }

  for (spec in trajectory_paper_supp_figure_specs(db_lab, index_name)) {
    src <- .pick_figure_src(pool_pdf, spec)
    if (is.na(src)) next
    dest <- file.path(fig_dir, spec$dest)
    file.copy(src, dest, overwrite = TRUE)
    curated <- c(curated, dest)
    used_src <- c(used_src, src)
  }

  curated_base <- basename(curated)
  archived <- character(0)
  for (f in unique(c(all_pdf, used_src))) {
    if (!file.exists(f)) next
    if (basename(f) %in% curated_base) next
    dest <- file.path(raw_dir, basename(f))
    if (identical(normalizePath(f, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) next
    if (file.exists(dest)) unlink(dest)
    file.rename(f, dest)
    archived <- c(archived, dest)
  }

  invisible(list(curated = curated, archived = archived, raw_dir = raw_dir,
               optimal_ng = optimal_ng))
}

trajectory_pick_canonical_tables <- function(tab_dir, db_lab, index_name = "NLR",
                                             disease = "ischemic stroke") {
  arch_dir <- file.path(tab_dir, "_archive")
  files_main <- list.files(tab_dir, full.names = TRUE)
  # 排除子目录本身及其内容路径
  files_main <- files_main[
    !basename(files_main) %in% c("_archive", "Summary") &
      !grepl("/_archive(/|$)", files_main) &
      !grepl("/Summary(/|$)", files_main)
  ]
  files_arch <- if (dir.exists(arch_dir)) {
    fa <- list.files(arch_dir, full.names = TRUE)
    fa[!dir.exists(fa)]
  } else character(0)

  pick_newest <- function(pat, pool) {
    if (!length(pool)) return(NA_character_)
    bn <- basename(pool)
    hits <- pool[grepl(pat, bn, ignore.case = TRUE, perl = TRUE)]
    if (!length(hits)) return(NA_character_)
    mt <- file.info(hits)$mtime
    if (all(is.na(mt))) return(hits[1L])
    hits[which.max(mt)]
  }
  # 根目录优先；仅当根目录无匹配时才回退 _archive（避免旧错号表盖掉新表）
  pick_prefer_main <- function(pat) {
    src <- pick_newest(pat, files_main)
    if (!is.na(src)) return(src)
    pick_newest(pat, files_arch)
  }
  pick_exact_dest <- function(dest_bn) {
    hit <- files_main[basename(files_main) == dest_bn]
    if (length(hit)) return(hit[1L])
    hit <- files_arch[basename(files_arch) == dest_bn]
    if (length(hit)) return(hit[1L])
    NA_character_
  }

  db_esc <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", db_lab, perl = TRUE)
  dis_esc <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", disease, perl = TRUE)

  specs <- list(
    list(dest = sprintf("Table 1-%s. Baseline characteristics of %s.xlsx", db_lab, disease),
         src_pats = c(sprintf("^Table 1-%s\\..*Baseline characteristics of %s", db_esc, dis_esc),
                      sprintf("^Table [0-9]+-%s\\..*Baseline characteristics of %s", db_esc, dis_esc))),
    list(dest = sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab),
         src_pats = c(sprintf("^Table 2-%s\\..*optimal number of classes", db_esc),
                      sprintf("^Table 2-%s\\..*Metrics for determining", db_esc),
                      sprintf("^Table 2-%s-UnknownDB\\..*optimal number of classes", db_esc),
                      "^Table 2-.*UnknownDB\\..*optimal number of classes",
                      "^Table_Trajectory_IC_JLCM",
                      sprintf("^Table2_%s_model_comparison", index_name))),
    list(dest = sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
         src_pats = c(sprintf("^Table 3-%s\\..*Time-dependent HR", db_esc),
                      sprintf("^Table 3-%s\\..*trajectory classes", db_esc))),
    list(dest = sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab),
         src_pats = c(sprintf("^Table S1-%s\\..*before and after multiple imputation", db_esc))),
    list(dest = sprintf("Table S2-%s. Normality test results for continuous variables.xlsx", db_lab),
         src_pats = c(sprintf("^Table S2-%s\\. Normality test results for continuous variables\\.xlsx$", db_esc),
                      sprintf("^Table S8-%s\\. Normality test results for continuous variables \\(n=", db_esc),
                      sprintf("^Table S[0-9]+-%s\\..*Normality test results", db_esc))),
    list(dest = sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
         src_pats = c(sprintf("^Table S[0-9]+-%s\\..*Univariate Regression", db_esc))),
    list(dest = sprintf("Table S4-%s. Multicollinearity Analysis (VIF, univariate screen).xlsx", db_lab),
         src_pats = c(sprintf("^Table S[0-9]+-%s\\..*univariate screen", db_esc))),
    list(dest = sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db_lab),
         src_pats = c(sprintf("^Table S[0-9]+-%s\\..*Multivariable Regression", db_esc))),
    list(dest = sprintf("Table S6-%s. Multicollinearity Analysis (VIF, multivariate final).xlsx", db_lab),
         src_pats = c(sprintf("^Table S[0-9]+-%s\\..*multivariate final", db_esc))),
    list(dest = sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, index_name),
         src_pats = c("^Table_S5_Baseline_By_Class_",
                      sprintf("^Table S7-%s\\..*Baseline characteristics by trajectory class", db_esc),
                      sprintf("^Table S5\\..*latent classes of %s", index_name))),
    list(dest = sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab),
         src_pats = c(sprintf("^Table S8-%s\\..*Posterior classification", db_esc)))
  )

  xlsx_all <- c(files_main, files_arch)
  xlsx_all <- xlsx_all[grepl("\\.xlsx$", xlsx_all, ignore.case = TRUE)]
  csv_all  <- c(files_main, files_arch)
  csv_all  <- csv_all[grepl("\\.csv$", csv_all, ignore.case = TRUE)]

  keep <- character(0)
  whitelist_bn <- vapply(specs, function(sp) sp$dest, character(1L))
  for (sp in specs) {
    src <- pick_exact_dest(sp$dest)
    if (is.na(src)) {
      for (pat in sp$src_pats) {
        src <- pick_prefer_main(pat)
        if (!is.na(src)) break
      }
    }
    if (is.na(src)) next
    dest <- file.path(tab_dir, sp$dest)
    if (grepl("\\.xlsx$", src, ignore.case = TRUE)) {
      if (!identical(normalizePath(src, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) {
        file.copy(src, dest, overwrite = TRUE)
      }
      keep <- c(keep, dest)
    } else if (grepl("\\.csv$", src, ignore.case = TRUE) && grepl("Table 2", sp$dest)) {
      keep <- c(keep, src)
    }
  }

  keep <- unique(keep[!is.na(keep) & file.exists(keep)])
  # 白名单文件名一律保留（按 basename，避免路径字符串不一致导致误归档）
  keep_bn <- unique(c(basename(keep), whitelist_bn))
  pool_all <- c(xlsx_all, csv_all)
  archive <- pool_all[!basename(pool_all) %in% keep_bn]
  # 若白名单文件仅在 _archive，拷回根目录
  for (bn in whitelist_bn) {
    dest <- file.path(tab_dir, bn)
    if (file.exists(dest)) {
      keep <- c(keep, dest)
      next
    }
    src <- files_arch[basename(files_arch) == bn]
    if (length(src) && file.exists(src[1L])) {
      file.copy(src[1L], dest, overwrite = TRUE)
      keep <- c(keep, dest)
    }
  }
  keep <- unique(keep[file.exists(keep)])
  invisible(list(keep = keep, archive = archive, whitelist = whitelist_bn))
}

trajectory_curate_tables_dir <- function(tab_dir, db_lab, index_name = "NLR",
                                         disease = "ischemic stroke") {
  if (!dir.exists(tab_dir)) return(invisible(list(keep = character(0), archived = character(0))))
  arch_dir <- file.path(tab_dir, "_archive")
  dir.create(arch_dir, recursive = TRUE, showWarnings = FALSE)

  picked <- trajectory_pick_canonical_tables(tab_dir, db_lab, index_name, disease)
  archived <- character(0)
  keep_bn <- unique(c(basename(picked$keep), picked$whitelist %||% character(0)))
  for (f in picked$archive) {
    if (!file.exists(f)) next
    # 保留 Summary/optimal_ng / 白名单正式表
    if (grepl("/Summary/", f, fixed = TRUE) || grepl("optimal_ng_", basename(f))) next
    if (basename(f) %in% keep_bn) next
    # 已在根目录的白名单正式名不要从 _archive 再搬一次
    if (grepl("/_archive/", f, fixed = TRUE) && basename(f) %in% keep_bn) next
    dest <- file.path(arch_dir, basename(f))
    if (identical(normalizePath(f, mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) next
    if (file.exists(dest)) unlink(dest)
    file.rename(f, dest)
    archived <- c(archived, dest)
  }

  junk_pats <- c(
    "UnknownDB",
    "^Table3_", "^Table2_",
    "^Table_Piecewise_", "^Table_KM_", "^Table_Weibull_",
    "^Table Index Summary", "^Table_Trajectory_Chisq",
    "^Table_Trajectory_IC_JLCM",
    "^Table_Subgroup_TrajectoryClass",
    "^Table_S5_Baseline_By_Class_",
    "^Table S9-", "^Table S10-", "^Table S11-", "^Table S12-",
    "Normality test results for continuous variables \\(n=",
    "^Table 2-.*Baseline characteristics",  # 与 Table1 重复的错号基线表
    "^Table S3-.*before and after multiple imputation",  # 错号插补表
    "^Table S7-.*multivariate final",  # 与正式 S6 重复
    "^Table S5-.*univariate screen",   # 与正式 S4 重复
    "^Table S4-.*Univariate Regression", # 与正式 S3 重复
    "^Table S6-.*Multivariable Regression", # 与正式 S5 重复
    "^Table S8-.*Normality test",  # 错号正态性表
    "\\.(csv|CSV|tex|TEX)$"  # 根目录中间 CSV/TeX 一律归档（白名单仅 xlsx）
  )
  for (pat in junk_pats) {
    extra <- list.files(tab_dir, pattern = pat, full.names = TRUE, ignore.case = TRUE)
    extra <- extra[!grepl("/_archive/", extra, fixed = TRUE)]
    extra <- extra[!basename(extra) %in% keep_bn]
    extra <- setdiff(extra, picked$keep)
    for (f in extra) {
      dest <- file.path(arch_dir, basename(f))
      if (file.exists(dest)) unlink(dest)
      file.rename(f, dest)
      archived <- c(archived, dest)
    }
  }

  invisible(list(keep = picked$keep, archived = archived, archive_dir = arch_dir))
}

trajectory_curate_pub_outputs <- function(base_dir, index_name = "NLR",
                                          dbs = c("mimic"),
                                          db_labels = NULL,
                                          disease = NULL) {
  if (is.null(db_labels)) db_labels <- list(eicu = "eICU", mimic = "MIMIC")
  if (is.null(disease) || !nzchar(as.character(disease)[1L])) {
    disease <- "ischemic stroke"
  }
  out <- list()
  for (db in dbs) {
    db_lab <- db_labels[[db]] %||% toupper(db)
    root <- if (dir.exists(file.path(base_dir, db))) file.path(base_dir, db) else base_dir
    opt_ng <- trajectory_read_optimal_ng(root, index_name)
    if (is.finite(opt_ng)) {
      cli::cli_alert_info("[{toupper(db)}] 发表整理使用最优 ng={opt_ng}")
    }
    fig_res <- trajectory_curate_figures_dir(
      file.path(root, "Figures"), db_lab, index_name, disease, optimal_ng = opt_ng
    )
    tab_res <- trajectory_curate_tables_dir(
      file.path(root, "Tables"), db_lab, index_name, disease
    )
    out[[db]] <- list(figures = fig_res, tables = tab_res, optimal_ng = opt_ng)
    cli::cli_alert_success(
      "[{toupper(db)}] Figures 主图/附图 {length(fig_res$curated)} 张；Tables 保留 {length(tab_res$keep)} 个，归档 {length(tab_res$archived)} 个"
    )
  }
  invisible(out)
}
