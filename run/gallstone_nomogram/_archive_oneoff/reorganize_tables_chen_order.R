#!/usr/bin/env Rscript
# 按 Chen JAD (10.1177/13872877261424471) 主文/补充表顺序重排 summary_results/Tables
# 主文：仅 Table 1、Table 2（多因素/AUC 在原文是 Fig5/Fig7，不是主表）
# 补充：Table S1–S4（对标 Supplemental Table 1–4）
# 其余 Methods/中间表 → Tables/_archive/
#
# Rscript run/gallstone_nomogram/reorganize_tables_chen_order.R \
#   --project /mnt/g/02block_result/45_Gallstone/Nomogram_41815074

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else
    "/mnt/g/02block_result/45_Gallstone/Nomogram_41815074"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else getwd()
}
source(file.path(.root, "R/literature_gallstone_nomogram.R"), local = FALSE)

.sum <- file.path(.proj, "summary_results")
.tab <- file.path(.sum, "Tables")
.arch <- file.path(.tab, "_archive")
.proj_tab <- file.path(.proj, "Tables")
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.arch, recursive = TRUE, showWarnings = FALSE)
dir.create(.proj_tab, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) message(paste0(...))
.safe_copy <- function(from, to) {
  if (!file.exists(from)) return(FALSE)
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  fn <- normalizePath(from, winslash = "/", mustWork = TRUE)
  tn <- normalizePath(to, winslash = "/", mustWork = FALSE)
  if (identical(fn, tn)) return(TRUE)
  file.copy(from, to, overwrite = TRUE)
}
.move_to_archive <- function(path) {
  if (!file.exists(path)) return(invisible(FALSE))
  dest <- file.path(.arch, basename(path))
  if (identical(normalizePath(path, winslash = "/", mustWork = FALSE),
                normalizePath(dest, winslash = "/", mustWork = FALSE)))
    return(invisible(TRUE))
  file.copy(path, dest, overwrite = TRUE)
  unlink(path)
  invisible(TRUE)
}

# ---------- 0) 先把 summary Tables 里非发表主序文件归档 ----------
.message("→ archive non-publication clutter in summary_results/Tables …")
.keep_final <- character(0) # filled later
.cur <- list.files(.tab, full.names = TRUE)
.cur <- .cur[!dir.exists(.cur)]
for (f in .cur) {
  bn <- basename(f)
  # 全部先归档，再按文献顺序写回正规名（避免旧 Table3/4 残留）
  .move_to_archive(f)
}

# 根 Tables 里的中间产物也拷一份进 archive（不删根，保留引擎源）
for (bn in c(
  "Table_UV_covariate_screen.csv",
  "Table_multivariate_logistic.csv",
  "Table_AUC_train_val_boot.csv",
  "Table_prespecified_ridge_coefficients.csv",
  "Table_prespecified_predictors.csv",
  "Batch_summary_all_units.csv",
  "Batch_summary_all_units.xlsx",
  "Indicator_availability.csv",
  "Indicator_availability.xlsx",
  "Methods_assoc_covariate_uv.txt"
)) {
  src <- file.path(.proj_tab, bn)
  if (file.exists(src)) .safe_copy(src, file.path(.arch, bn))
}

# ---------- 1) 主文 Table 1 / Table 2（对标 Chen）----------
.message("→ Table 1 / Table 2 …")
.t1_src <- file.path(.proj_tab, "Table 1. Baseline by Success.csv")
.t2_src <- file.path(.proj_tab, "Table 2. Train vs validation baseline.csv")
.t1_name <- "Table 1. Baseline characteristics of the participants.csv"
.t2_name <- "Table 2. Baseline characteristics between training and validation sets.csv"
if (!file.exists(.t1_src)) stop("missing ", .t1_src)
if (!file.exists(.t2_src)) stop("missing ", .t2_src)
.safe_copy(.t1_src, file.path(.tab, .t1_name))
.safe_copy(.t2_src, file.path(.tab, .t2_name))
.safe_copy(.t1_src, file.path(.proj_tab, .t1_name))
.safe_copy(.t2_src, file.path(.proj_tab, .t2_name))

# ---------- 2) Table S1：变量说明（对标 Supplemental Table 1）----------
.message("→ Table S1 variable descriptions …")
.s1 <- data.frame(
  Variable = c(
    "Success",
    "Age",
    "Sex",
    "diameter_cm",
    "volume_cm3",
    "energy_j",
    "shots",
    "shape",
    "color",
    "surface",
    "stone_type",
    "ct_min",
    "ct_max",
    "pct_lt40",
    "pct_40_80",
    "pct_gt80"
  ),
  Label = c(
    "Lithotripsy success (outcome)",
    "Age, years",
    "Sex",
    "Stone diameter, cm",
    "Stone volume, cm3",
    "Lithotripsy energy, J",
    "Number of shocks (shots)",
    "Stone shape",
    "Stone color",
    "Stone surface",
    "Stone type (Favorable / Unfavorable)",
    "Minimum CT attenuation, HU",
    "Maximum CT attenuation, HU",
    "CT pixels <40 HU, %",
    "CT pixels 40–80 HU, %",
    "CT pixels >80 HU, %"
  ),
  Description_and_assessment = c(
    "Binary endpoint: successful stone fragmentation / clearance after lithotripsy (Yes/No).",
    "Age at procedure, continuous (years).",
    "Coded as recorded in source database (levels 1/2).",
    "Maximum stone diameter measured on imaging, continuous (cm).",
    "Estimated stone volume, continuous (cm3).",
    "Total / applied lithotripsy energy, continuous (J).",
    "Number of shock-wave / laser shots, continuous (count).",
    "Morphologic shape category from imaging/chart (levels 1/2).",
    "Color category (levels 1/2/3).",
    "Surface category (levels 1/2).",
    "Collapsed clinical stone-type grouping used for subgroup forests (Favorable vs Unfavorable).",
    "Lowest CT Hounsfield unit within stone ROI.",
    "Highest CT Hounsfield unit within stone ROI.",
    "Percentage of stone voxels with HU < 40.",
    "Percentage of stone voxels with HU 40–80.",
    "Percentage of stone voxels with HU > 80."
  ),
  Role = c(
    "Outcome",
    "Nomogram predictor (prespecified)",
    "Baseline / subgroup",
    "Nomogram predictor (prespecified)",
    "Nomogram predictor (prespecified)",
    "Nomogram predictor (prespecified)",
    "Nomogram predictor (prespecified)",
    "Baseline / subgroup",
    "Baseline / subgroup",
    "Baseline / subgroup",
    "Subgroup (collapsed)",
    "Exploratory CT feature (not in final nomogram)",
    "Exploratory CT feature (not in final nomogram)",
    "Exploratory CT feature (not in final nomogram)",
    "Exploratory CT feature (not in final nomogram)",
    "Exploratory CT feature (not in final nomogram)"
  ),
  stringsAsFactors = FALSE
)
.s1_name <- "Table S1. Descriptions and assessments of the variables.csv"
utils::write.csv(.s1, file.path(.tab, .s1_name), row.names = FALSE)
utils::write.csv(.s1, file.path(.proj_tab, .s1_name), row.names = FALSE)

# ---------- 3) Table S2：VIF（对标 Supplemental Table 2）----------
.message("→ Table S2 VIF …")
.prespec <- c("Age", "diameter_cm", "volume_cm3", "energy_j", "shots")
.out <- "Success"
.xlsx <- file.path(.proj, "data", "gallstone_features.xlsx")
.df0 <- gallstone_nomogram_read_xlsx(.xlsx)
.df <- gallstone_collapse_stone_type(.df0, .out)
.y01 <- function(d) {
  y <- d[[.out]]
  if (is.factor(y)) as.integer(y == "Yes" | y == levels(y)[length(levels(y))])
  else as.integer(as.numeric(y) == 1L)
}
.set_seed <- 42L
set.seed(.set_seed)
.n <- nrow(.df)
.tr_n <- if (file.exists(file.path(.proj_tab, "Methods_split_denominator_note.txt"))) {
  ln <- readLines(file.path(.proj_tab, "Methods_split_denominator_note.txt"), warn = FALSE)
  hit <- grep("^train_n=", ln, value = TRUE)
  if (length(hit)) as.integer(sub(".*=", "", hit[[1]])) else floor(0.7 * .n)
} else floor(0.7 * .n)
.idx <- sample.int(.n, size = min(.tr_n, .n))
.train <- .df[.idx, , drop = FALSE]
.use <- .prespec[.prespec %in% names(.train)]
.dtr <- .train[, c(.out, .use), drop = FALSE]
.dtr$.y <- .y01(.dtr)
.fml <- stats::as.formula(paste(".y ~", paste(.use, collapse = "+")))
.fit <- tryCatch(
  stats::glm(.fml, data = .dtr, family = stats::binomial()),
  error = function(e) NULL
)
.s2 <- NULL
if (!is.null(.fit) && requireNamespace("car", quietly = TRUE)) {
  vf <- tryCatch(car::vif(.fit), error = function(e) NULL)
  if (!is.null(vf)) {
    if (is.matrix(vf)) {
      .s2 <- data.frame(
        Variable = rownames(vf),
        GVIF = as.numeric(vf[, "GVIF"]),
        Df = as.numeric(vf[, "Df"]),
        `GVIF^(1/(2*Df))` = as.numeric(vf[, grepl("GVIF", colnames(vf))[length(grep("GVIF", colnames(vf)))]]),
        check.names = FALSE, stringsAsFactors = FALSE
      )
    } else {
      .s2 <- data.frame(
        Variable = names(vf),
        VIF = as.numeric(vf),
        stringsAsFactors = FALSE
      )
    }
  }
}
if (is.null(.s2)) {
  # 简易相关矩阵条件数兜底（无 car 时）
  X <- as.matrix(.dtr[, .use, drop = FALSE])
  storage.mode(X) <- "double"
  X <- scale(X)
  r <- stats::cor(X, use = "pairwise.complete.obs")
  ev <- tryCatch(eigen(r, only.values = TRUE)$values, error = function(e) NA_real_)
  .s2 <- data.frame(
    Variable = .use,
    note = "car::vif unavailable; pairwise correlation with other predictors (abs max)",
    abs_max_cor = sapply(.use, function(v) {
      others <- setdiff(.use, v)
      max(abs(r[v, others]), na.rm = TRUE)
    }),
    stringsAsFactors = FALSE
  )
  attr(.s2, "condition_number") <- max(ev, na.rm = TRUE) / max(min(ev, na.rm = TRUE), 1e-12)
}
.s2_name <- "Table S2. Variance inflation factors between variables.csv"
utils::write.csv(.s2, file.path(.tab, .s2_name), row.names = FALSE)
utils::write.csv(.s2, file.path(.proj_tab, .s2_name), row.names = FALSE)

# ---------- 4) Table S3：Model1–3 关联（对标 Supplemental Table 3）----------
.message("→ Table S3 association Model1–3 …")
.assoc_cands <- c(
  file.path(.arch, "Table_assoc_OR_Model123_all.csv"),
  file.path(.tab, "Table_assoc_OR_Model123_all.csv"),
  file.path(.proj_tab, "Table_assoc_OR_Model123_all.csv")
)
.assoc_src <- .assoc_cands[file.exists(.assoc_cands)][1]
if (is.na(.assoc_src) || !nzchar(.assoc_src %||% "")) {
  warning("Table_assoc_OR_Model123_all.csv not found; skip S3")
  .s3 <- data.frame(note = "SOURCE_MISSING: Table_assoc_OR_Model123_all.csv")
} else {
  a <- utils::read.csv(.assoc_src, stringsAsFactors = FALSE)
  # wide: feature × Model1/2/3 OR(CI) + P
  mk <- function(mod) {
    sub <- a[a$model == mod, , drop = FALSE]
    data.frame(
      feature = sub$feature,
      OR_CI = sub$OR_CI,
      P = ifelse(is.finite(sub$P) & sub$P < 0.001, "<0.001",
                 ifelse(is.finite(sub$P), sprintf("%.3f", sub$P), "—")),
      stringsAsFactors = FALSE
    )
  }
  m1 <- mk("Model1"); names(m1)[2:3] <- c("Model1_OR_CI", "Model1_P")
  m2 <- mk("Model2"); names(m2)[2:3] <- c("Model2_OR_CI", "Model2_P")
  m3 <- mk("Model3"); names(m3)[2:3] <- c("Model3_OR_CI", "Model3_P")
  .s3 <- Reduce(function(x, y) merge(x, y, by = "feature", all = TRUE), list(m1, m2, m3))
  # 临床阅读顺序：预指定连续 → 其余
  .ord <- c(.prespec, setdiff(unique(a$feature), .prespec))
  .s3 <- .s3[match(intersect(.ord, .s3$feature), .s3$feature), , drop = FALSE]
}
.s3_name <- "Table S3. Association of features with lithotripsy success (Model 1-3).csv"
utils::write.csv(.s3, file.path(.tab, .s3_name), row.names = FALSE)
utils::write.csv(.s3, file.path(.proj_tab, .s3_name), row.names = FALSE)

# ---------- 5) Table S4：预测因子在 train vs val（对标 Supplemental Table 4；无外库则内验）----------
.message("→ Table S4 predictors train vs validation …")
.t2 <- utils::read.csv(.t2_src, stringsAsFactors = FALSE)
# Table2 行是 variable / train / validation
.pred_vars <- .prespec
.s4 <- .t2[.t2$variable %in% .pred_vars, , drop = FALSE]
if (!nrow(.s4)) {
  # 若 Table2 用别名，尽量模糊匹配
  .s4 <- .t2[tolower(.t2$variable) %in% tolower(.pred_vars), , drop = FALSE]
}
# 附注：本课题无独立外库，对应原文 external validation → internal validation
.s4_note <- data.frame(
  Characteristic = c(.s4$variable, "NOTE"),
  `Training set` = c(.s4$train, NA_character_),
  `Internal validation set` = c(.s4$validation, NA_character_),
  note = c(rep("", nrow(.s4)),
           "Chen Supplemental Table 4 used external validation; this study reports internal validation (no external cohort)."),
  check.names = FALSE, stringsAsFactors = FALSE
)
.s4_name <- "Table S4. Characteristics of predictors between training and validation sets.csv"
utils::write.csv(.s4_note, file.path(.tab, .s4_name), row.names = FALSE)
utils::write.csv(.s4_note, file.path(.proj_tab, .s4_name), row.names = FALSE)

# ---------- 6) 图源数据进 archive（不算发表表）----------
for (bn in c(
  "Table_Figure_S1_Subgroup_analysis_of_Diameter_and_lithotripsy_success.csv",
  "Table_Figure_S2_Subgroup_analysis_of_Shots_and_lithotripsy_success.csv",
  "Table_S_subgroup_OR.csv",
  "Table_nomogram_ridge_coefficients.csv",
  "Table 3. Multivariate logistic regression.csv",
  "Table 4. Discrimination (AUC) train validation bootstrap.csv",
  "Figure2_panel_index.csv",
  "Figure3_panel_index.csv",
  "Flowchart_attrition.csv"
)) {
  for (d in c(.arch, .proj_tab, .tab)) {
    f <- file.path(d, bn)
    if (file.exists(f) && !grepl("/_archive/", normalizePath(f, winslash = "/", mustWork = FALSE))) {
      if (!identical(dirname(f), .arch)) .safe_copy(f, file.path(.arch, bn))
    }
  }
}
# 多因素 / AUC 作为 Fig5/Fig7 源数据保留在 archive，并写别名说明
.mv_src <- file.path(.arch, "Table_multivariate_logistic.csv")
.auc_src <- file.path(.arch, "Table_AUC_train_val_boot.csv")
if (file.exists(file.path(.arch, "Table 3. Multivariate logistic regression.csv"))) {
  # already archived
} else if (file.exists(file.path(.proj_tab, "Table_multivariate_logistic.csv"))) {
  .safe_copy(file.path(.proj_tab, "Table_multivariate_logistic.csv"),
             file.path(.arch, "Source_Fig5_multivariate_logistic.csv"))
}
if (file.exists(file.path(.proj_tab, "Table_AUC_train_val_boot.csv"))) {
  .safe_copy(file.path(.proj_tab, "Table_AUC_train_val_boot.csv"),
             file.path(.arch, "Source_Fig7_AUC_train_val_boot.csv"))
}

# ---------- 7) README：文献顺序对照 ----------
.write_readme <- function(path) {
  writeLines(c(
    "# 发表表 — 对齐 Chen JAD (10.1177/13872877261424471)",
    "",
    "原文主文只有 **Table 1、Table 2**；多因素森林 / ROC·校准 / DCA / CIC 均为 **Figure**，不是主表。",
    "补充材料为 **Supplemental Table 1–4** + **Supplemental Figure 1–3**（本课题 S1/S2）。",
    "",
    "## 主文 Tables（本目录）",
    "",
    "| 顺序 | 本课题文件 | 对标原文 |",
    "|------|------------|----------|",
    paste0("| 1 | `", .t1_name, "` | Table 1. Baseline characteristics of the participants |"),
    paste0("| 2 | `", .t2_name, "` | Table 2. Baseline characteristics between training set and validation set |"),
    "",
    "## Supplemental Tables",
    "",
    "| 顺序 | 本课题文件 | 对标原文 |",
    "|------|------------|----------|",
    paste0("| S1 | `", .s1_name, "` | Supplemental Table 1. Descriptions and assessments of the variables |"),
    paste0("| S2 | `", .s2_name, "` | Supplemental Table 2. Variance inflation factors between variables |"),
    paste0("| S3 | `", .s3_name, "` | Supplemental Table 3. Association … (Model 1–3) |"),
    paste0("| S4 | `", .s4_name, "` | Supplemental Table 4. Predictors train vs validation (原文为外验；本课题为内验) |"),
    "",
    "## Supplemental Figures（见 `../Figures/`）",
    "",
    "| 顺序 | 文件 | 对标原文 |",
    "|------|------|----------|",
    "| S1 | Figure S1. Subgroup analysis of Diameter… | Supplemental Figure 1（单一暴露×亚组森林） |",
    "| S2 | Figure S2. Subgroup analysis of Shots… | Supplemental Figure 2 |",
    "| — | （无 CoI 第三暴露） | 原文 Supplemental Figure 3 未做对等第三暴露主图 |",
    "",
    "## 主文 Figures（提醒：不是表）",
    "",
    "- Figure 1 Flowchart",
    "- Figure 2 Associations",
    "- Figure 3 RCS",
    "- Figure 4 Ridge/LASSO paths",
    "- Figure 5 Multivariate logistic（原误编号 Table 3 的源在 `_archive/`）",
    "- Figure 6 Nomogram",
    "- Figure 7 ROC + calibration（原误编号 Table 4 的源在 `_archive/`）",
    "- Figure 8 DCA",
    "- Figure 9 CIC",
    "",
    "## `_archive/`",
    "",
    "Methods 脚注、旧 Table 3/4、亚组源 CSV、UV/ridge 中间表等，**不作为投稿主序表**。",
    ""
  ), path)
}
.write_readme(file.path(.tab, "README.md"))
.write_readme(file.path(.sum, "README.md"))

# 更新项目目录说明
writeLines(c(
  "# 胆结石碎石成功列线图 — 目录说明（Chen 文献顺序）",
  "",
  "## 主入口",
  "",
  "```",
  "summary_results/",
  "  Figures/pdf|png|tiff|image_information/   Figure 1–9 + S1/S2",
  "  Tables/                                   Table 1–2 + Table S1–S4",
  "  Tables/_archive/                          Methods / 中间表 / 旧误编号",
  "  Tables/README.md                          与原文对照",
  "```",
  "",
  "主文表只有 Table 1、Table 2；多因素与 AUC 对应 Figure 5 / Figure 7，不是主表。",
  ""
), file.path(.proj, "README_目录说明.md"))

# ---------- 8) 发病套路 SCI 三线 xlsx（主序格式）----------
.message("→ export SCI xlsx (incidence-style) …")
tryCatch(
  source(file.path(.root, "run/gallstone_nomogram/export_tables_sci_xlsx.R"), local = FALSE),
  error = function(e) .message("SCI xlsx WARN: ", conditionMessage(e))
)

.message("DONE. Publication tables:")
.message(paste(" -", list.files(.tab, pattern = "^Table")))
.message("Archive: ", .arch)
