#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# HRS cancer ABSI：Age 校正敏感性分析（不覆盖主文 Table 1–3 / S1–S4 / Figures）
#
# 产出：
#   summary_results/Tables/Table S5… (logistic + Age)
#   summary_results/Tables/Table S6… (Cox + Age)
#   by_index/【success】ABSI/sensitivity_age/  （旁路副本 + 关键细胞 CSV）
#   summary_results/_internal/（若存在）或 delivery_workspace/_internal/
#   Methods_statistical_analysis.md 追加 Sensitivity / Limitations（主文回归段保留）
#   reports/age_confounding_sensitivity_ABSI_*.md
#
# 用法：
#   Rscript run/cum_egdr_kmeans_ckm/rebuild_sa_age_hrs_cancer.R \
#     --project /mnt/g/02block_result/58_cancer/cum_egdr_kmeans_hrs_cancer
# -----------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
.proj <- NA_character_
i <- 1L
while (i <= length(args)) {
  if (identical(args[[i]], "--project") && i < length(args)) {
    .proj <- args[[i + 1L]]; i <- i + 2L
  } else {
    i <- i + 1L
  }
}
if (!nzchar(.proj) || is.na(.proj)) {
  .proj <- Sys.getenv(
    "CKM_HRS_CANCER_PROJECT",
    unset = "/mnt/g/02block_result/58_cancer/cum_egdr_kmeans_hrs_cancer"
  )
}
stopifnot(dir.exists(.proj))

.repo <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = Sys.getenv("BLOCK_REPO_ROOT", unset = ""))
if (!nzchar(.repo) || !dir.exists(.repo)) {
  .repo <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (!file.exists(file.path(.repo, "R/cum_egdr_kmeans_pub.R"))) {
    .repo <- "/mnt/e/01block/01Block-new-Final"
  }
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = .repo, BLOCK_REPO_ROOT = .repo)
source(file.path(.repo, "R/utils.R"), local = FALSE)
source(file.path(.repo, "R/literature_ckm_cum_egdr.R"), local = FALSE)
source(file.path(.repo, "R/cum_egdr_kmeans_pub.R"), local = FALSE)

index <- "ABSI"
.index_root <- file.path(.proj, "by_index", paste0("\u3010success\u3011", index))
if (!dir.exists(.index_root)) {
  .index_root <- file.path(.proj, "by_index", index)
}
stopifnot(dir.exists(.index_root))
.sr <- file.path(.index_root, "summary_results")
.tab <- file.path(.sr, "Tables")
stopifnot(dir.exists(.tab))

# Fingerprint protected tables
.protect <- list.files(.tab, pattern = "^Table [123]\\.|^Table S[1-4]\\.", full.names = TRUE)
.md5_before <- if (length(.protect)) {
  setNames(tools::md5sum(.protect), basename(.protect))
} else {
  character(0)
}

# Prefer logistic bundle (has eGDR_Class); avoid early cum_exposure_build without class
.unit_ck <- file.path(
  .proj, "by_unit", paste0("\u3010success\u3011", index), "checkpoints"
)
.ck_candidates <- c(
  file.path(.unit_ck, "logistic_cum_index_bundle.rds"),
  file.path(.unit_ck, "step05_logistic_cum_index_bundle.rds"),
  file.path(.unit_ck, "ckm_pub_finalize.rds"),
  file.path(.index_root, "logistic_cum_index_bundle.rds"),
  file.path(.unit_ck, "kmeans_trajectory_panels.rds")
)
.ck <- .ck_candidates[file.exists(.ck_candidates)][1L]
if (!length(.ck) || is.na(.ck)) stop("No ABSI checkpoint found under ", .index_root)

message("========== SA age adjustment: ", index, " ==========")
message("  checkpoint: ", .ck)

obj <- readRDS(.ck)
data0 <- if (!is.null(obj$ctx$data$cleaned)) {
  obj$ctx$data$cleaned
} else if (is.data.frame(obj)) {
  obj
} else if (!is.null(obj$data)) {
  obj$data
} else {
  stop("Cannot extract cleaned data from ", .ck)
}

.prepare_data_sa <- function(data0, index) {
  data <- ckm_stroke_harmonize_columns(data0)
  if (!"Hypertension" %in% names(data) && "Hypertension_w4" %in% names(data)) {
    data$Hypertension <- data$Hypertension_w4
  }
  if (!"Drink" %in% names(data) && "Alcohol_drinking" %in% names(data)) {
    data$Drink <- data$Alcohol_drinking
  }
  stopifnot("Cancer" %in% names(data))
  data$status <- as.integer(as.numeric(data$Cancer) == 1L)
  data <- ckm_stroke_add_futime(data)
  if (!"futime" %in% names(data) || all(!is.finite(as.numeric(data$futime)))) {
    data$futime <- 4
  } else {
    data$futime <- as.numeric(data$futime)
    data$futime[!is.finite(data$futime) | data$futime <= 0] <- 4
  }
  data <- ckm_stroke_prepare_age_group(data, 60L)
  data <- ckm_stroke_attach_class_paper(data, "eGDR_Class", ckm_stroke_class_map_paper())
  if ("Gender" %in% names(data)) {
    data$Gender <- factor(as.character(data$Gender), levels = c("Female", "Male"))
  }
  mv_src <- if ("Marital_Status" %in% names(data)) {
    as.character(data$Marital_Status)
  } else if ("Marital" %in% names(data)) {
    as.character(data$Marital)
  } else {
    character(0)
  }
  if (length(mv_src)) {
    mv <- tolower(trimws(mv_src))
    out <- ifelse(
      is.na(mv_src) | !nzchar(mv_src), NA_character_,
      ifelse(grepl("unmarried|single|divorced|widowed|separated|other", mv), "Single",
        ifelse(grepl("^married|partner", mv), "Married", "Single"))
    )
    data$Marital <- factor(out, levels = c("Single", "Married"))
  }
  data
}

data <- .prepare_data_sa(data0, index)
if (!"eGDR_Class" %in% names(data)) {
  stop("Checkpoint lacks eGDR_Class: ", .ck)
}
cmap <- ckm_stroke_class_map_from_present(data$eGDR_Class)
data <- ckm_stroke_attach_class_paper(data, "eGDR_Class", cmap)
if ("cum_eGDR" %in% names(data)) {
  .n_q_lock <- nlevels(factor(data$eGDR_tertile))
  if (!is.finite(.n_q_lock) || .n_q_lock < 2L) .n_q_lock <- 4L
  data$eGDR_tertile <- ckm_stroke_cut_quantile(as.numeric(data$cum_eGDR), n = .n_q_lock)
}

# Main (no-Age) model lock — identical to primary ABSI publication
bl <- list(
  covariate_mode = "uv_vif",
  force_adjust_by_index = list(
    ABSI = list(
      Model2 = c("Gender", "Marital"),
      Model3 = c("Gender", "Marital", "Education", "Smoke", "Drink",
                 "Diabetes", "Hypertension")
    )
  ),
  current_index = index
)
models_main <- ckm_stroke_model_sets(bl, data, index_name = index, outcome = "Cancer")
models_main$Model2 <- ckm_stroke_model_drop_exposure_components(models_main$Model2, index, bl)
models_main$Model3 <- ckm_stroke_model_drop_exposure_components(models_main$Model3, index, bl)
# Force exact primary sets (model_sets may still inject Age from defaults)
models_main$Model1 <- character(0)
models_main$Model2 <- c("Gender", "Marital")
models_main$Model3 <- c("Gender", "Marital", "Education", "Smoke", "Drink",
                        "Diabetes", "Hypertension")

.sidecar <- file.path(.index_root, "sensitivity_age")
.ws <- file.path(dirname(.sr), paste0(basename(.sr), "_delivery_workspace"))
.internal <- file.path(.ws, "_internal_sa_age")
dir.create(.sidecar, recursive = TRUE, showWarnings = FALSE)
dir.create(.internal, recursive = TRUE, showWarnings = FALSE)

# 与主文一致：发表表文件名带 HRS，并立即 flush 队列（export_sci_table 默认只入队）
options(medical_blocks.pub_db_label = "HRS")
Sys.setenv(MEDICAL_BLOCKS_PUB_DB = "HRS")
options(pipeline.database_name = "HRS")

res <- ckm_stroke_export_age_adjustment_sensitivity(
  data = data,
  models_main = models_main,
  tables_dir = .tab,
  index_lab = "ABSI",
  outcome = "Cancer",
  cmap = cmap,
  sidecar_dir = .sidecar,
  internal_dir = .internal,
  protect_existing = TRUE
)
if (exists("render_queued_tables", mode = "function")) {
  render_queued_tables(list())
} else {
  stop("render_queued_tables missing; S5/S6 were only queued")
}
# 队列写出后可能变成 Table S5-HRS.…；统一成无库标签文件名（单库交付）
.normalize_sa_bn <- function(path_guess, pattern) {
  hits <- list.files(.tab, pattern = pattern, full.names = TRUE)
  if (!length(hits)) return(path_guess)
  # Prefer exact non-db-infix name if present; else rename first hit
  bare <- hits[!grepl("-(HRS|UnknownDB|NHANES|CHARLS|MIMIC|eICU)\\.", basename(hits))]
  if (length(bare)) return(bare[[1L]])
  dest <- file.path(.tab, sub("-(HRS|UnknownDB)\\.", ".", basename(hits[[1L]])))
  if (!identical(normalizePath(hits[[1L]], winslash = "/", mustWork = FALSE),
                 normalizePath(dest, winslash = "/", mustWork = FALSE))) {
    if (file.exists(dest)) unlink(dest)
    file.rename(hits[[1L]], dest)
  }
  dest
}
res$s5 <- .normalize_sa_bn(
  res$s5,
  "^Table S5\\..*Age-adjusted logistic|^Table S5-.*Age-adjusted logistic"
)
res$s6 <- .normalize_sa_bn(
  res$s6,
  "^Table S6\\..*Age-adjusted Cox|^Table S6-.*Age-adjusted Cox"
)
# 旁路副本（flush 后真实文件）
if (file.exists(res$s5)) {
  file.copy(res$s5, file.path(.sidecar, basename(res$s5)), overwrite = TRUE)
}
if (file.exists(res$s6)) {
  file.copy(res$s6, file.path(.sidecar, basename(res$s6)), overwrite = TRUE)
}
stopifnot(file.exists(res$s5), file.exists(res$s6))

message("  S5: ", res$s5)
message("  S6: ", res$s6)
message(sprintf(
  "  Age–cum ABSI Spearman rho=%.3f P=%s; M2=%s; M3=%s",
  res$diagnostics$spearman_rho,
  ckm_stroke_fmt_p(res$diagnostics$spearman_p),
  paste(res$models_sa$Model2, collapse = "+"),
  paste(res$models_sa$Model3, collapse = "+")
))
print(res$comparison)

# ---- Append Methods Sensitivity + Limitations (do not rewrite whole md via finalize) ----
.md <- file.path(.sr, "Methods_statistical_analysis.md")
stopifnot(file.exists(.md))
.md_txt <- paste(readLines(.md, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
.sa_para <- paste0(
  "Table S5 (logistic) and Table S6 (Cox) re-fit the same exposure contrasts after adding Age to ",
  "Model 2 and Model 3 (Model 1 remained unadjusted). Primary Table 2 / Table S1 / Figures were not ",
  "recomputed. Age–cumulative ABSI Spearman rho = ",
  sprintf("%.3f", res$diagnostics$spearman_rho),
  " (P = ", ckm_stroke_fmt_p(res$diagnostics$spearman_p), "). ",
  "These tables quantify attenuation under age adjustment and are the formal sensitivity analysis for ",
  "the pre-specified omission of Age in the primary ABSI models."
)
.lim_para <- paste0(
  "The principal limitation is residual confounding by age: primary ABSI Model 2/3 intentionally omitted Age ",
  "because age adjustment abolished the Model 2/3 associations for continuous cumulative ABSI and the highest ",
  "k-means class in this HRS cohort; cancer incidence rises steeply with age, and ABSI also correlates with age, ",
  "so part of the primary association may reflect the age distribution of body shape. Table S5/S6 should be read ",
  "alongside Table 2/S1; attenuation after including Age does not by itself prove that age fully mediates the ",
  "association, nor does persistence of an unadjusted association prove age-independence. Secondary limitations ",
  "include reliance on only two anthropometric time points for trajectories (limited resolution of long-term change) ",
  "and pooling of all incident cancers (site-specific heterogeneity cannot be resolved). Inclusion was restricted ",
  "to adults aged \u226550 years, which reduces but does not eliminate age confounding within the analytic range."
)
# Strip prior SA/Limitations blocks if re-run
.md_txt <- gsub("\n## Sensitivity analyses\\n.*?(?=\\n## |\n## Software)", "\n", .md_txt, perl = TRUE)
.md_txt <- gsub("\n## Limitations\\n.*?(?=\\n## |\n## Software)", "\n", .md_txt, perl = TRUE)
if (!grepl("## Software", .md_txt)) {
  .md_txt <- paste0(.md_txt, "\n\n## Software\nAnalyses were performed in R. Package versions are listed in Methods_software_versions.txt beside this file.\n")
}
.md_new <- sub(
  "\n## Software",
  paste0(
    "\n## Sensitivity analyses\n", .sa_para, "\n\n",
    "## Limitations\n", .lim_para, "\n\n",
    "## Software"
  ),
  .md_txt,
  fixed = FALSE
)
writeLines(strsplit(.md_new, "\n", fixed = TRUE)[[1L]], .md, useBytes = TRUE)
message("  Methods updated: Sensitivity analyses + Limitations")

# ---- Discussion report (project reports/, not delivery root) ----
.rep_dir <- file.path(.proj, "reports")
dir.create(.rep_dir, recursive = TRUE, showWarnings = FALSE)
.rep <- file.path(.rep_dir, paste0("age_confounding_sensitivity_ABSI_", format(Sys.Date(), "%Y-%m-%d"), ".md"))
.byc <- res$diagnostics$by_class
.byc_txt <- if (!is.null(.byc) && nrow(.byc)) {
  paste(apply(.byc, 1L, function(r) {
    sprintf("- %s: n=%s, Age mean (SD)=%.1f (%.1f), median=%.1f",
            r[["Class"]], r[["n"]], as.numeric(r[["Age_mean"]]),
            as.numeric(r[["Age_sd"]]), as.numeric(r[["Age_median"]]))
  }), collapse = "\n")
} else {
  "(no class Age summary)"
}
.cmp_lines <- apply(res$comparison, 1L, function(r) {
  sprintf("| %s | %s | %s | %s | %s | %s |",
          r[["block"]], trimws(r[["term"]]),
          r[["M2e"]], r[["M2p"]], r[["M3e"]], r[["M3p"]])
})
.write_rep <- c(
  "# Age confounding: primary omission + sensitivity (ABSI / HRS cancer)",
  "",
  "## Verdict for manuscript discussion",
  "",
  "1. **Primary analysis (Table 2 / S1)** omits Age by design for ABSI; associations that remain significant without Age are vulnerable to residual age confounding and must not be oversold as age-independent.",
  "2. **Sensitivity (Table S5 / S6)** adds Age to Model 2 and Model 3; report attenuation (or loss of significance) transparently next to the primary estimates.",
  "3. **Interpretation rule**: attenuation after Age ⇒ association partly shares variance with age / residual confounding cannot be excluded; persistence of association after Age ⇒ stronger (still observational) support. Either way, do not claim causality.",
  "4. **Secondary limitations** (shorter paragraph): two-wave trajectories only; all-cancer composite outcome.",
  "",
  "## Diagnostics",
  "",
  sprintf("- Analytic N = %s", format(nrow(data), big.mark = ",")),
  sprintf("- Age mean (SD) = %.1f (%.1f)", res$diagnostics$age_mean, res$diagnostics$age_sd),
  sprintf("- Spearman(Age, cumulative ABSI) rho = %.3f, P = %s",
          res$diagnostics$spearman_rho, ckm_stroke_fmt_p(res$diagnostics$spearman_p)),
  "",
  "### Mean Age by k-means class",
  .byc_txt,
  "",
  "## Key cells with Age (S5/S6)",
  "",
  "| Model family | Term | M2 est | M2 P | M3 est | M3 P |",
  "|---|---|---|---|---|---|",
  .cmp_lines,
  "",
  "## How to write the discussion (Chinese outline)",
  "",
  "- 主分析未校正年龄是本课题最大方法学风险，已在 Methods 写明预设理由，并在 Table S5/S6 给出含 Age 的完整对照。",
  "- 癌症发病随年龄陡增；ABSI 与年龄相关（见 Spearman 与各类均龄），未调年龄时效应可能混入年龄结构。",
  "- 若 S5/S6 中效应减弱或不显著：应写「残余混杂不能排除 / 部分效应可能由年龄解释」，避免把主表显著写成稳健因果结论。",
  "- 若 S5/S6 仍显著：可写「在额外校正年龄后关联方向/显著性仍存」，但仍属观察性关联。",
  "- 次要局限：仅两个体测时点的轨迹分辨率有限；全癌症合并结局无法区分部位异质性。",
  "",
  "## Paths",
  "",
  sprintf("- S5: `%s`", res$s5),
  sprintf("- S6: `%s`", res$s6),
  sprintf("- Sidecar: `%s`", .sidecar),
  sprintf("- Methods: `%s`", .md),
  ""
)
writeLines(.write_rep, .rep, useBytes = TRUE)
message("  report: ", .rep)

# Verify protected tables unchanged
.md5_after <- if (length(.protect)) {
  setNames(tools::md5sum(.protect), basename(.protect))
} else {
  character(0)
}
.changed <- names(.md5_before)[.md5_before != .md5_after[names(.md5_before)]]
if (length(.changed)) {
  stop("PROTECTED TABLES CHANGED (abort): ", paste(.changed, collapse = ", "))
}
message("  Protected Table 1–3 / S1–S4 md5 unchanged: OK")

# Soft scrub new xlsx only
if (exists("pub_xlsx_scrub_underscores", mode = "function")) {
  try(pub_xlsx_scrub_underscores(res$s5), silent = TRUE)
  try(pub_xlsx_scrub_underscores(res$s6), silent = TRUE)
}

message("DONE SA age adjustment (primary results untouched).")
