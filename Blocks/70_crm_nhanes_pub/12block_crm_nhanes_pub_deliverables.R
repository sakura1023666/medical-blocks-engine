###############################################################################
#  crm_nhanes_pub_deliverables — Batch 尾段：生成 NHANES_pub_deliverables
#  白名单交付物（不多不少）。表构建见 14block_crm_nhanes_table_builders.R。
#
#  config$study_batch$finalize_blocks = c("crm_nhanes_pub_deliverables")
#  config$crm_nhanes_pub_deliverables = list(
#    deliverables_dirname = "NHANES_pub_deliverables",
#    pause_enable = FALSE
#  )
###############################################################################

.crm70fold_allowlist <- function() {
  c(
    "README.md",
    "Tables/Table 1-NHANES. Ordinal logistic OR SUA HU gout.xlsx",
    "Tables/Table 2-NHANES. Weighted Cox HR by CRM.xlsx",
    "Tables/Table 3-NHANES. MR causal estimates SUA.xlsx",
    "Tables/Table S1-NHANES. SNPs of SUA instrumental variable for MR.xlsx",
    "Tables/Table S2-NHANES. GWAS datasets enrolled in MR.xlsx",
    "Tables/Table S3-NHANES. Weighted baseline by hyperuricemia.xlsx",
    "Tables/Table S4-NHANES. Weighted baseline CRM ge1 by hyperuricemia.xlsx",
    "Tables/Table S5-NHANES. Mortality rates by CRM conditions.xlsx",
    "Tables/Table S6-NHANES. Subgroup ordinal OR SUA HUA gout.xlsx",
    "Tables/Table S7-NHANES. Subgroup Cox HR by CRM0 vs ge1.xlsx",
    "Tables/Table S8-NHANES. Univariate Cox screening all-cause mortality.xlsx",
    "Tables/Table S9-NHANES. VIF screen covariates.xlsx",
    "Tables/Table S10-NHANES. Multivariate Cox screening.xlsx",
    "Tables/Table S11-NHANES. VIF final Model2Factors.xlsx",
    "Figures/Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count.pdf",
    "Figures/Figure 2-NHANES-RCS_SUA_all-cause_mortality_by_CRM.pdf",
    "Figures/Figure S1-NHANES-Study_population_flowchart.pdf",
    "Figures/MR/Figure S2-NHANES-MR_scatter_SUA_CVD.pdf",
    "Figures/MR/Figure S3-NHANES-MR_scatter_SUA_CKD.pdf",
    "Figures/MR/Figure S4-NHANES-MR_scatter_SUA_DM.pdf",
    "Figures/MR/Figure S5-NHANES-MR_forest_SUA_CVD.pdf",
    "Figures/MR/Figure S6-NHANES-MR_forest_SUA_CKD.pdf",
    "Figures/MR/Figure S7-NHANES-MR_forest_SUA_DM.pdf",
    "Figures/MR/Figure S8-NHANES-MR_leaveoneout_SUA_CVD.pdf",
    "Figures/MR/Figure S9-NHANES-MR_leaveoneout_SUA_CKD.pdf",
    "Figures/MR/Figure S10-NHANES-MR_leaveoneout_SUA_DM.pdf",
    "Figures/MR/Figure S11-NHANES-MR_funnel_SUA_CVD.pdf",
    "Figures/MR/Figure S12-NHANES-MR_funnel_SUA_CKD.pdf",
    "Figures/MR/Figure S13-NHANES-MR_funnel_SUA_DM.pdf"
  )
}

.crm70fold_wipe <- function(deliv) {
  if (dir.exists(deliv)) {
    unlink(deliv, recursive = TRUE, force = TRUE)
  }
  dir.create(file.path(deliv, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(deliv, "Figures", "MR"), recursive = TRUE, showWarnings = FALSE)
}

.crm70fold_find_unit <- function(proj, unit) {
  cands <- c(
    file.path(proj, "by_unit", paste0("\u3010success\u3011", unit)),
    file.path(proj, "by_unit", unit)
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) return(NA_character_)
  hit[[1L]]
}

.crm70fold_aggregate_mr <- function(proj, scratch) {
  dir.create(file.path(scratch, "MR"), recursive = TRUE, showWarnings = FALSE)
  units <- c("mr_cvd", "mr_ckd", "mr_diabetes")
  est <- list(); presso <- list(); pleio <- list()
  for (u in units) {
    ud <- .crm70fold_find_unit(proj, u)
    if (is.na(ud)) next
    mr <- file.path(ud, "Tables", "MR")
    p5 <- file.path(mr, "Table_5_MR_Estimates.csv")
    if (file.exists(p5)) est[[u]] <- utils::read.csv(p5, stringsAsFactors = FALSE, check.names = FALSE)
    pp <- file.path(mr, "Table_MR_Egger_PRESSO.csv")
    if (file.exists(pp)) presso[[u]] <- utils::read.csv(pp, stringsAsFactors = FALSE, check.names = FALSE)
    pl <- file.path(mr, "Table_MR_Pleiotropy_Heterogeneity.csv")
    if (file.exists(pl)) pleio[[u]] <- utils::read.csv(pl, stringsAsFactors = FALSE, check.names = FALSE)
    iv <- file.path(mr, "Table_MR_SNP_Screened.csv")
    if (file.exists(iv)) {
      file.copy(iv, file.path(scratch, "MR", "Table_MR_SNP_Screened.csv"), overwrite = TRUE)
    }
  }
  if (!length(est)) stop("crm_nhanes_pub_deliverables: 未找到任何 MR Table_5 估计表", call. = FALSE)
  est_df <- do.call(rbind, est)
  utils::write.csv(est_df, file.path(scratch, "Table_5_MR_Estimates.csv"), row.names = FALSE)
  if (length(presso)) {
    utils::write.csv(do.call(rbind, presso), file.path(scratch, "MR", "Table_MR_Egger_PRESSO.csv"), row.names = FALSE)
  }
  if (length(pleio)) {
    utils::write.csv(do.call(rbind, pleio), file.path(scratch, "MR", "Table_MR_Pleiotropy_Heterogeneity.csv"), row.names = FALSE)
  }
  invisible(est_df)
}

.crm70fold_build_table3_pub_csv <- function(est_df, presso_path, scratch) {
  `%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(a))) b else a
  .fmt_p <- function(p) {
    ifelse(is.na(p), NA_character_,
           ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
  }
  .fmt_or_ci <- function(b, se, digits = 3L) {
    or <- exp(b); lo <- exp(b - 1.96 * se); hi <- exp(b + 1.96 * se)
    sprintf(paste0("%.", digits, "f (%.", digits, "f–%.", digits, "f)"), or, lo, hi)
  }
  raw5 <- est_df
  method_map <- c(
    "Inverse variance weighted" = "IVW",
    "MR Egger" = "MR-Egger",
    "Weighted median" = "Weighted median"
  )
  raw5$method_short <- ifelse(raw5$method %in% names(method_map),
                              unname(method_map[raw5$method]), raw5$method)
  raw5$outcome_std <- ifelse(raw5$outcome_label %in% c("Diabetes", "DM", "T2D"), "DM",
                             as.character(raw5$outcome_label))
  tab5 <- subset(raw5, method_short %in% c("IVW", "MR-Egger", "Weighted median"))
  tab5$`OR (95% CI)` <- .fmt_or_ci(tab5$b, tab5$se)
  tab5$P <- .fmt_p(tab5$pval)
  tab5$Outcome <- tab5$outcome_std
  tab5$Method <- tab5$method_short
  tab5$N_SNPs <- tab5$nsnp
  tab5$beta <- tab5$b
  if (file.exists(presso_path)) {
    pr <- utils::read.csv(presso_path, stringsAsFactors = FALSE, check.names = FALSE)
    pr$outcome_std <- ifelse(pr$outcome %in% c("Diabetes", "DM", "T2D"), "DM", as.character(pr$outcome))
    pr$method_short <- ifelse(grepl("outlier", pr$method, ignore.case = TRUE),
                              "MR-PRESSO", "MR-PRESSO-raw")
    # prefer outlier-corrected as MR-PRESSO
    pr$`OR (95% CI)` <- .fmt_or_ci(pr$b, pr$se)
    pr$P <- .fmt_p(pr$pval)
    pr$Outcome <- pr$outcome_std
    pr$Method <- pr$method_short
    pr$N_SNPs <- pr$n_snps %||% pr$nsnp
    pr$beta <- pr$b
    keep <- intersect(c("Outcome", "Method", "N_SNPs", "OR (95% CI)", "P", "beta", "se"), names(pr))
    tab5 <- rbind(
      tab5[, c("Outcome", "Method", "N_SNPs", "OR (95% CI)", "P", "beta", "se")],
      pr[, keep]
    )
  }
  utils::write.csv(tab5, file.path(scratch, "Table_5_MR_Estimates_pub.csv"), row.names = FALSE)
  invisible(tab5)
}

.crm70fold_build_s1_s2 <- function(proj, tab_dir, scratch) {
  iv_csv <- file.path(scratch, "MR", "Table_MR_SNP_Screened.csv")
  if (!file.exists(iv_csv)) stop("缺 IV SNP 表: ", iv_csv, call. = FALSE)
  iv <- utils::read.csv(iv_csv, stringsAsFactors = FALSE)
  n_exp <- 343836L
  .r2 <- function(b, se, eaf, n) {
    b <- as.numeric(b); se <- as.numeric(se); eaf <- as.numeric(eaf)
    out <- rep(NA_real_, length(b))
    ok_e <- is.finite(b) & is.finite(eaf) & eaf > 0 & eaf < 1
    out[ok_e] <- 2 * b[ok_e]^2 * eaf[ok_e] * (1 - eaf[ok_e])
    ok_s <- !ok_e & is.finite(b) & is.finite(se) & se > 0
    out[ok_s] <- b[ok_s]^2 / (b[ok_s]^2 + as.numeric(n) * se[ok_s]^2)
    out
  }
  s1 <- data.frame(
    SNP = iv$SNP,
    beta = round(as.numeric(iv$beta), 6),
    SE = round(as.numeric(iv$se), 6),
    `P value` = {
      p <- as.numeric(iv$pval)
      ifelse(is.finite(p) & p == 0, "<1e-300",
             ifelse(is.finite(p), format(p, scientific = TRUE, digits = 3), ""))
    },
    R2 = signif(.r2(iv$beta, iv$se, iv$eaf, n_exp), 4),
    F = round(ifelse(is.finite(as.numeric(iv$F)), as.numeric(iv$F),
                     (as.numeric(iv$beta) / as.numeric(iv$se))^2), 4),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  s1 <- s1[order(-s1$F, s1$SNP), , drop = FALSE]
  export_sci_table(
    s1,
    file.path(tab_dir, "Table S1-NHANES. SNPs of SUA instrumental variable for MR.xlsx"),
    title = paste0(
      "Table S1-NHANES. SNPs of serum uric acid used to construct the instrumental ",
      "variable for the MR analysis"
    ),
    excel_use_prepared = FALSE,
    table_footnotes = c(
      "Instruments from ebi-a-GCST90018977; FinnGen R9 outcomes.",
      paste0("n_IV=", nrow(s1), "; N_exposure=", n_exp, ".")
    )
  )
  s2 <- data.frame(
    Items = c("Serum uric acid", "Cardiovascular disease", "Chronic kidney disease", "Diabetes mellitus"),
    `GWAS ID / file` = c(
      "ebi-a-GCST90018977 (GCST90018977.h.tsv.gz)",
      "Finngen_R9_FG_CVD",
      "finngen_R9_N14_CHRONKIDNEYDIS",
      "finngen_R9_T2D_WIDE"
    ),
    Consortium = c("UKB / GWAS Catalog", "FinnGen R9", "FinnGen R9", "FinnGen R9"),
    `Sample size` = c("343836", "377277", "372250", "348788"),
    Population = rep("Europeans", 4),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  export_sci_table(
    s2,
    file.path(tab_dir, "Table S2-NHANES. GWAS datasets enrolled in MR.xlsx"),
    title = "Table S2-NHANES. Characteristics of GWAS datasets enrolled in the MR study",
    excel_use_prepared = FALSE,
    table_footnotes = c("Aligned with Han et al. 2025 JAHA supplement Table S2.")
  )
  invisible(TRUE)
}

.crm70fold_copy_figures <- function(proj, deliv) {
  fig <- file.path(deliv, "Figures")
  mr_dir <- file.path(fig, "MR")
  dir.create(mr_dir, recursive = TRUE, showWarnings = FALSE)
  obs <- .crm70fold_find_unit(proj, "obs_main")
  # KM / RCS / flowchart — search common locations
  specs_root <- list(
    list(dst = "Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count.pdf",
         pats = c("Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count.pdf",
                  "Figure_1_KM*.pdf")),
    list(dst = "Figure 2-NHANES-RCS_SUA_all-cause_mortality_by_CRM.pdf",
         pats = c("Figure 2-NHANES-RCS_SUA_all-cause_mortality_by_CRM.pdf",
                  "Figure*RCS*.pdf")),
    list(dst = "Figure S1-NHANES-Study_population_flowchart.pdf",
         pats = c("Figure S1-NHANES-Study_population_flowchart.pdf",
                  "Figure*flowchart*.pdf", "Figure_S1*.pdf"))
  )
  search_root <- c(
    file.path(obs, "Figures"),
    file.path(proj, "NHANES_pub_deliverables", "Figures")
  )
  for (sp in specs_root) {
    src <- NA_character_
    for (d in search_root) {
      if (is.na(d) || !dir.exists(d)) next
      for (pat in sp$pats) {
        hits <- Sys.glob(file.path(d, pat))
        if (length(hits)) { src <- hits[[1]]; break }
      }
      if (!is.na(src)) break
    }
    if (!is.na(src) && file.exists(src)) {
      file.copy(src, file.path(fig, sp$dst), overwrite = TRUE)
    } else {
      cli::cli_alert_warning("缺图: {sp$dst}")
    }
  }
  mr_map <- list(
    list(n = 2, name = "MR_scatter_SUA_CVD", pats = c("Figure_S4_MR_scatter_CVD.pdf")),
    list(n = 3, name = "MR_scatter_SUA_CKD", pats = c("Figure_S4_MR_scatter_CKD.pdf")),
    list(n = 4, name = "MR_scatter_SUA_DM", pats = c("Figure_S4_MR_scatter_Diabetes.pdf")),
    list(n = 5, name = "MR_forest_SUA_CVD", pats = c("Figure_S5_MR_forest_CVD.pdf")),
    list(n = 6, name = "MR_forest_SUA_CKD", pats = c("Figure_S5_MR_forest_CKD.pdf")),
    list(n = 7, name = "MR_forest_SUA_DM", pats = c("Figure_S5_MR_forest_Diabetes.pdf")),
    list(n = 8, name = "MR_leaveoneout_SUA_CVD", pats = c("Figure_S7_MR_loo_CVD.pdf")),
    list(n = 9, name = "MR_leaveoneout_SUA_CKD", pats = c("Figure_S7_MR_loo_CKD.pdf")),
    list(n = 10, name = "MR_leaveoneout_SUA_DM", pats = c("Figure_S7_MR_loo_Diabetes.pdf")),
    list(n = 11, name = "MR_funnel_SUA_CVD", pats = c("Figure_S6_MR_funnel_CVD.pdf")),
    list(n = 12, name = "MR_funnel_SUA_CKD", pats = c("Figure_S6_MR_funnel_CKD.pdf")),
    list(n = 13, name = "MR_funnel_SUA_DM", pats = c("Figure_S6_MR_funnel_Diabetes.pdf"))
  )
  mr_search <- c(
    file.path(.crm70fold_find_unit(proj, "mr_cvd"), "Figures/MR"),
    file.path(.crm70fold_find_unit(proj, "mr_ckd"), "Figures/MR"),
    file.path(.crm70fold_find_unit(proj, "mr_diabetes"), "Figures/MR")
  )
  for (sp in mr_map) {
    src <- NA_character_
    for (d in mr_search) {
      if (is.na(d) || !dir.exists(d)) next
      for (pat in sp$pats) {
        fp <- file.path(d, pat)
        if (file.exists(fp)) { src <- fp; break }
      }
      if (!is.na(src)) break
    }
    dst <- file.path(mr_dir, sprintf("Figure S%d-NHANES-%s.pdf", sp$n, sp$name))
    if (!is.na(src)) file.copy(src, dst, overwrite = TRUE)
    else cli::cli_alert_warning("缺 MR 图: {basename(dst)}")
  }
  invisible(TRUE)
}

.crm70fold_prune <- function(deliv) {
  allow <- .crm70fold_allowlist()
  # normalize allow paths
  allow_norm <- gsub("\\\\", "/", allow)
  files <- list.files(deliv, recursive = TRUE, full.names = TRUE)
  files <- files[!dir.exists(files)]
  kept <- character(0)
  for (f in files) {
    rel <- substring(gsub("\\\\", "/", f), nchar(gsub("\\\\", "/", deliv)) + 2L)
    if (rel %in% allow_norm) {
      kept <- c(kept, rel)
    } else {
      unlink(f)
      cli::cli_alert_info("prune: {rel}")
    }
  }
  # remove empty dirs except Figures/MR structure
  invisible(kept)
}

.crm70fold_write_readme <- function(deliv) {
  writeLines(c(
    "# NHANES_pub_deliverables（正式交付物）",
    "",
    "由 batch 尾段 block `crm_nhanes_pub_deliverables` 自动生成。",
    "白名单：正表 1–3、补表 S1–S11、Figure 1/2/S1、MR Figure S2–S13、本 README。",
    "- S1–S7 / Fig1–2 / MR：对齐 Han 2025 JAHA（本地连续编号）",
    "- S8–S11：预后式协变量筛选（非加权）；正表/亚组仍用筛选出的 Model2Factors + 调查加权",
    "不做 SUA cox_quartile/tertile/binary 闸门。",
    "中间产物在 `by_unit/`，不进入本目录。"
  ), file.path(deliv, "README.md"))
}

.crm70fold_first_glob <- function(dirs, patterns) {
  for (d in dirs) {
    if (is.na(d) || !nzchar(d) || !dir.exists(d)) next
    for (pat in patterns) {
      hits <- Sys.glob(file.path(d, pat))
      if (length(hits)) return(hits[[1L]])
    }
  }
  NA_character_
}

.crm70fold_copy_screening_tables <- function(proj, tab_dir) {
  obs <- .crm70fold_find_unit(proj, "obs_main")
  if (is.na(obs)) {
    cli::cli_alert_warning("缺 obs_main，跳过 S8–S11 筛选表拷贝")
    return(invisible(FALSE))
  }
  search <- c(
    file.path(obs, "Tables"),
    file.path(obs),
    list.files(obs, pattern = "^step", full.names = TRUE)
  )
  search <- search[!is.na(search)]

  # S8 univariate
  src8 <- .crm70fold_first_glob(search, c(
    "*Univariate*Regression*.xlsx",
    "*Univariable*.xlsx",
    "*univariate*.xlsx",
    "Table*S2a*.xlsx"
  ))
  dst8 <- file.path(tab_dir, "Table S8-NHANES. Univariate Cox screening all-cause mortality.xlsx")
  if (!is.na(src8) && file.exists(src8)) {
    file.copy(src8, dst8, overwrite = TRUE)
  } else {
    cli::cli_alert_warning("缺 Table S8 源（univariate）")
  }

  # S9 VIF screen
  src9 <- .crm70fold_first_glob(search, c(
    "*VIF*screen*.xlsx",
    "*Multicollinearity*screen*.xlsx",
    "VIF_check_screen.csv"
  ))
  dst9 <- file.path(tab_dir, "Table S9-NHANES. VIF screen covariates.xlsx")
  if (!is.na(src9) && grepl("\\.xlsx$", src9, ignore.case = TRUE)) {
    file.copy(src9, dst9, overwrite = TRUE)
  } else if (!is.na(src9) && grepl("\\.csv$", src9, ignore.case = TRUE)) {
    df <- utils::read.csv(src9, stringsAsFactors = FALSE, check.names = FALSE)
    if (requireNamespace("openxlsx", quietly = TRUE)) {
      openxlsx::write.xlsx(df, dst9, overwrite = TRUE)
    } else {
      utils::write.csv(df, sub("\\.xlsx$", ".csv", dst9), row.names = FALSE)
      cli::cli_alert_warning("无 openxlsx，S9 写为 csv 旁路（随后 prune 可能删）")
    }
  } else {
    cli::cli_alert_warning("缺 Table S9 源（VIF screen）")
  }

  # S10 multivariate
  src10 <- .crm70fold_first_glob(search, c(
    "*Multivariate*Regression*.xlsx",
    "*multivariate*.xlsx",
    "*Multivariable*.xlsx"
  ))
  dst10 <- file.path(tab_dir, "Table S10-NHANES. Multivariate Cox screening.xlsx")
  if (!is.na(src10) && file.exists(src10)) {
    file.copy(src10, dst10, overwrite = TRUE)
  } else {
    cli::cli_alert_warning("缺 Table S10 源（multivariate）")
  }

  # S11 VIF final / Model2Factors
  dst11 <- file.path(tab_dir, "Table S11-NHANES. VIF final Model2Factors.xlsx")
  src11x <- .crm70fold_first_glob(search, c(
    "*VIF*final*.xlsx",
    "*Multicollinearity*final*.xlsx",
    "VIF_check_final.csv"
  ))
  m2_txt <- NA_character_
  m2_hits <- list.files(obs, pattern = "^Model2Factors\\.txt$", recursive = TRUE, full.names = TRUE)
  if (length(m2_hits)) m2_txt <- m2_hits[[1L]]
  if (!is.na(src11x) && grepl("\\.xlsx$", src11x, ignore.case = TRUE)) {
    file.copy(src11x, dst11, overwrite = TRUE)
  } else {
    fac <- character(0)
    if (!is.na(m2_txt) && file.exists(m2_txt)) {
      fac <- readLines(m2_txt, warn = FALSE)
      fac <- fac[nzchar(trimws(fac)) & !startsWith(trimws(fac), "#")]
    }
    if (!length(fac) && !is.na(src11x) && grepl("\\.csv$", src11x, ignore.case = TRUE)) {
      df <- utils::read.csv(src11x, stringsAsFactors = FALSE, check.names = FALSE)
      if (requireNamespace("openxlsx", quietly = TRUE)) {
        openxlsx::write.xlsx(df, dst11, overwrite = TRUE)
      }
    } else if (length(fac)) {
      df <- data.frame(Model2Factors = fac, stringsAsFactors = FALSE)
      if (requireNamespace("openxlsx", quietly = TRUE)) {
        openxlsx::write.xlsx(df, dst11, overwrite = TRUE)
      } else {
        utils::write.csv(df, sub("\\.xlsx$", ".csv", dst11), row.names = FALSE)
      }
    } else {
      cli::cli_alert_warning("缺 Table S11 源（VIF final / Model2Factors）")
    }
  }

  invisible(TRUE)
}

block_crm_nhanes_pub_deliverables <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl <- cfg$crm_nhanes_pub_deliverables %||% list()
  sb <- cfg$study_batch %||% list()
  proj <- sb$output_base %||% cfg$project$output_dir
  if (is.null(proj) || !nzchar(proj)) stop("无法解析 project 根目录", call. = FALSE)
  proj <- normalizePath(proj, winslash = "/", mustWork = FALSE)
  deliv_name <- as.character(bl$deliverables_dirname %||% "NHANES_pub_deliverables")[1L]
  deliv <- file.path(proj, deliv_name)
  tab_dir <- file.path(deliv, "Tables")
  scratch <- file.path(proj, "_scratch_pub_deliverables")
  repo <- sb$project_root %||% cfg$project$root
  if (is.null(repo) || !dir.exists(repo)) {
    repo <- "E:/01block/01Block-new-Final"
    if (!dir.exists(repo)) repo <- "/mnt/e/01block/01Block-new-Final"
  }

  cli::cli_h1("生成交付物 → {deliv}")
  .crm70fold_wipe(deliv)
  unlink(scratch, recursive = TRUE, force = TRUE)
  dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(scratch, "_archive_internal", "MR"), recursive = TRUE, showWarnings = FALSE)

  # options for builders
  options(
    crm70.lib_mode = TRUE,
    crm70.proj = proj,
    crm70.deliv = deliv,
    crm70.tab_dir = tab_dir
  )
  # builders that archive under tab_dir/_archive_internal → redirect via symlink/junction?
  # Instead create tab_dir/_archive_internal pointing to scratch archive
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  # On Windows junction is hard; just let builders write archive then prune.

  # 1) Aggregate MR intermediates into scratch (and into tab_dir/_archive_internal for table3)
  est_df <- .crm70fold_aggregate_mr(proj, file.path(scratch, "_archive_internal"))
  # also place pub csv where table3 expects
  .crm70fold_build_table3_pub_csv(
    est_df,
    file.path(scratch, "_archive_internal", "MR", "Table_MR_Egger_PRESSO.csv"),
    file.path(scratch, "_archive_internal")
  )
  # table3 / s1 builders look under tab_dir/_archive_internal
  file.copy(
    file.path(scratch, "_archive_internal"),
    tab_dir,
    recursive = TRUE, overwrite = TRUE
  )
  # ensure MR subdir copy
  dir.create(file.path(tab_dir, "_archive_internal", "MR"), recursive = TRUE, showWarnings = FALSE)
  file.copy(
    list.files(file.path(scratch, "_archive_internal", "MR"), full.names = TRUE),
    file.path(tab_dir, "_archive_internal", "MR"),
    overwrite = TRUE
  )
  file.copy(
    file.path(scratch, "_archive_internal", "Table_5_MR_Estimates_pub.csv"),
    file.path(tab_dir, "_archive_internal", "Table_5_MR_Estimates_pub.csv"),
    overwrite = TRUE
  )

  # 2) Source builders（已并入 Blocks/70，不再走 run/rerun_table*.R）
  builders_path <- file.path(repo, "Blocks/70_crm_nhanes_pub/14block_crm_nhanes_table_builders.R")
  if (!file.exists(builders_path)) stop("缺 builder: ", builders_path, call. = FALSE)
  cli::cli_alert_info("source 14block_crm_nhanes_table_builders.R")
  sys.source(builders_path, envir = .GlobalEnv)
  funs <- c(
    "crm70_build_table1_ordinal",
    "crm70_build_table2_cox",
    "crm70_build_table3_mr",
    "crm70_build_table_s3_baseline_hu",
    "crm70_build_table_s4_baseline_crm1",
    "crm70_build_table_s5_mortality",
    "crm70_build_table_s6_subgroup_or",
    "crm70_build_table_s7_subgroup_hr"
  )
  for (fn_name in funs) {
    fn <- get(fn_name, envir = .GlobalEnv, inherits = TRUE)
    cli::cli_alert_info("run {fn_name}")
    fn()
  }

  # 3) S1 / S2
  .crm70fold_build_s1_s2(proj, tab_dir, file.path(scratch, "_archive_internal"))
  ctx2 <- list(output_dir = deliv, output_dir_tables = tab_dir)
  if (exists("render_queued_tables", mode = "function")) {
    ctx2 <- render_queued_tables(ctx2)
  }
  unlink(list.files(tab_dir, pattern = "\\.tex$", full.names = TRUE))

  # 3b) Screening tables S8–S11 from obs_main
  .crm70fold_copy_screening_tables(proj, tab_dir)

  # 4) Figures
  .crm70fold_copy_figures(proj, deliv)

  # 5) README + prune
  .crm70fold_write_readme(deliv)
  unlink(file.path(tab_dir, "_archive_internal"), recursive = TRUE, force = TRUE)
  unlink(file.path(deliv, "_tmp_ordinal_rerun"), recursive = TRUE, force = TRUE)
  unlink(file.path(deliv, "_tmp_cox_rerun"), recursive = TRUE, force = TRUE)
  kept <- .crm70fold_prune(deliv)

  ctx$results$crm_nhanes_pub_deliverables <- list(
    deliverables_dir = deliv,
    n_kept = length(kept),
    kept = kept
  )
  cli::cli_alert_success("交付物完成: {length(kept)} 文件 @ {deliv}")
  print(sort(kept))
  ctx
}

register_block(
  "crm_nhanes_pub_deliverables",
  block_crm_nhanes_pub_deliverables,
  "NHANES 正式交付物折叠（白名单 Tables/Figures）"
)
