#!/usr/bin/env Rscript
# GPR → summary_results，图/表按 fcimb-16-1871653 主文顺序重排
#
# 文献主文（fcimb-16-1871653）：
#   Fig1 轨迹类 | Fig2 landmark KM | Fig3 发现集动态预测 | Fig4 外验动态预测
#   Fig5/6 PAMM 时变关联四面板；动/静 AUC 为补充图（非 Fig4）
# 本课题：Fig3=MIMIC dynpred，Fig4=eICU dynpred，Fig5/6=PAMM 四面板。
#
# Usage:
#   Rscript run/trajectory_prognosis/build_gpr_fcimb_summary_results.R \
#     --index-root "G:/.../by_index/【success】GPR"

args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

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

index_root <- .get(
  "--index-root",
  "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177/by_index/\u3010success\u3011GPR"
)
index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
ix <- "GPR"

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "R/pub_delivery_prune.R"))
if (file.exists(file.path(.root, "R/dual_db_combine_figures.R")))
  source(file.path(.root, "R/dual_db_combine_figures.R"))

.sum <- file.path(index_root, "summary_results")
.fig <- file.path(.sum, "Figures")
.pdf <- file.path(.fig, "pdf")
.md  <- file.path(.fig, "image_information")
.tab <- file.path(.sum, "Tables")
for (d in c(.pdf, .md, .tab)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

.safe_copy <- function(src, dest) {
  if (is.null(src) || !nzchar(src) || !file.exists(src)) return(FALSE)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest, overwrite = TRUE)
}

.find1 <- function(..., prefer = NULL) {
  hits <- unlist(lapply(list(...), function(p) {
    if (is.null(p) || !nzchar(p)) return(character(0))
    if (file.exists(p) && !dir.exists(p)) return(p)
    character(0)
  }), use.names = FALSE)
  if (!length(hits) && !is.null(prefer)) {
    for (pat in prefer) {
      hits <- list.files(index_root, pattern = pat, recursive = TRUE, full.names = TRUE)
      hits <- hits[!grepl("/_raw/|_archive|summary_results", hits)]
      if (length(hits)) break
    }
  }
  if (!length(hits)) return(NA_character_)
  hits[which.max(file.info(hits)$size)]
}

.stack2 <- function(top, bottom, dest, labels = c("a. MIMIC-IV (derivation)", "b. eICU (validation)")) {
  if (!file.exists(top)) return(FALSE)
  if (is.na(bottom) || !file.exists(bottom)) {
    return(isTRUE(.safe_copy(top, dest)))
  }
  ok <- FALSE
  if (requireNamespace("pdftools", quietly = TRUE) &&
      requireNamespace("magick", quietly = TRUE)) {
    tryCatch({
      i1 <- magick::image_read_pdf(top, density = 150)
      i2 <- magick::image_read_pdf(bottom, density = 150)
      w <- max(magick::image_info(i1)$width, magick::image_info(i2)$width)
      i1 <- magick::image_resize(i1, paste0(w, "x"))
      i2 <- magick::image_resize(i2, paste0(w, "x"))
      # 加面板标签
      i1 <- magick::image_annotate(i1, labels[1], size = 28, gravity = "northwest",
                                   color = "black", location = "+20+10")
      i2 <- magick::image_annotate(i2, labels[2], size = 28, gravity = "northwest",
                                   color = "black", location = "+20+10")
      comb <- magick::image_append(c(i1, i2), stack = TRUE)
      magick::image_write(comb, path = dest, format = "pdf")
      ok <- file.exists(dest)
    }, error = function(e) {
      message("stack failed: ", conditionMessage(e))
      ok <<- FALSE
    })
  }
  if (!ok) ok <- isTRUE(.safe_copy(top, dest))
  ok
}

# ── 源文件 ──────────────────────────────────────────────────────────────────
mimic_f <- file.path(index_root, "mimic", "Figures")
eicu_f  <- file.path(index_root, "eicu", "Figures")

src_flow_m <- .find1(file.path(mimic_f, "Figure 1-MIMIC. Flowchart of patient selection.pdf"),
                     file.path(index_root, "Figures/pdf/Figure 1. Flowchart of patient selection.pdf"))
src_flow_e <- .find1(file.path(eicu_f, "Figure 1-eICU. Flowchart of patient selection.pdf"))
src_traj   <- .find1(file.path(mimic_f, "Figure 2-MIMIC. Trajectory of GPR latent classes.pdf"),
                     prefer = "Figure 2-MIMIC\\. Trajectory|Figure Trajectory GPR")
src_km_m   <- .find1(file.path(mimic_f, "Figure S2-MIMIC. Kaplan Meier survival by trajectory class.pdf"),
                     prefer = "Figure S2-MIMIC\\. Kaplan|Figure KM TrajectoryClass GPR")
src_km_e   <- .find1(file.path(eicu_f, "Figure S2-eICU. Kaplan Meier survival by trajectory class.pdf"),
                     prefer = "eicu.*Figure KM TrajectoryClass|Figure S2-eICU")
src_dyn_m  <- .find1(
  file.path(mimic_f, "Figure 3-MIMIC. Dynamic prediction of GPR trajectory.pdf"),
  file.path(mimic_f, "Figure Dynpred GPR D3.pdf"),
  prefer = "mimic.*Figure_Dynpred_GPR|mimic.*Dynamic prediction of GPR"
)
src_dyn_e  <- .find1(
  file.path(eicu_f, "Figure 4-eICU. Dynamic prediction of GPR trajectory.pdf"),
  file.path(eicu_f, "Figure Dynpred GPR D3.pdf"),
  prefer = "eicu.*Figure_Dynpred_GPR|eicu.*Dynamic prediction of GPR|Figure 4-eICU"
)
src_pamm_m <- .find1(
  file.path(mimic_f, "Figure 5-MIMIC. PAMM time-varying association.pdf"),
  file.path(mimic_f, "Figure PAMM GPR fcimb panels.pdf"),
  prefer = "mimic.*Figure PAMM|mimic.*PAMM.*fcimb|Figure_PAMM_GPR"
)
src_pamm_e <- .find1(
  file.path(eicu_f, "Figure 6-eICU. PAMM time-varying association.pdf"),
  file.path(eicu_f, "Figure PAMM GPR fcimb panels.pdf"),
  prefer = "eicu.*Figure PAMM|eicu.*PAMM.*fcimb"
)
src_ind    <- .find1(file.path(mimic_f, "Figure 4-MIMIC. Individual dynamic prediction.pdf"),
                     prefer = "Individual dynamic prediction")
src_auc    <- .find1(file.path(mimic_f, "Figure S5-MIMIC. Weibull dynamic model comparison AUC.pdf"),
                     prefer = "Weibull dynamic model comparison AUC")
src_cut    <- .find1(file.path(index_root, "Figures/pdf/Figure S3. Piecewise Cox cut point search.pdf"),
                     file.path(mimic_f, "Figure S3-MIMIC. Piecewise Cox cut point search.pdf"))
src_sub_m  <- .find1(file.path(mimic_f, "Figure S4-MIMIC. Subgroup analysis by trajectory class.pdf"))
src_sub_e  <- .find1(file.path(eicu_f, "Figure S4-eICU. Subgroup analysis by trajectory class.pdf"))
src_cidx   <- .find1(file.path(mimic_f, "Figure S6-MIMIC. Weibull dynamic model comparison C index.pdf"))
src_acc    <- .find1(file.path(mimic_f, "Figure S7-MIMIC. Weibull dynamic model comparison Accuracy.pdf"))
src_sens   <- .find1(file.path(mimic_f, "Figure S8-MIMIC. Weibull dynamic model comparison Sensitivity.pdf"))
src_spec   <- .find1(file.path(mimic_f, "Figure S9-MIMIC. Weibull dynamic model comparison Specificity.pdf"))
src_miss_m <- .find1(file.path(mimic_f, "Figure S1-MIMIC. Missing value overview.pdf"))
src_miss_e <- .find1(file.path(eicu_f, "Figure S1-eICU. Missing value overview.pdf"))

# ── 按文献主文顺序落盘图 ────────────────────────────────────────────────────
# Fig1 = fcimb a/b 叠线（redraw_gpr_fig1_fcimb_style.R）；勿用分面灰线 plot 覆盖
fig1_dest <- file.path(.pdf, "Figure 1. Trajectory of GPR latent classes.pdf")
redraw_script <- file.path(.root, "run/trajectory_prognosis/redraw_gpr_fig1_fcimb_style.R")
fig1_ok <- FALSE
if (file.exists(redraw_script)) {
  cli::cli_alert_info("Fig1: 调用 redraw_gpr_fig1_fcimb_style.R（ng=3 a/b 叠线）")
  rbin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  st <- tryCatch(
    system2(rbin, args = c("--vanilla", shQuote(redraw_script)), stdout = TRUE, stderr = TRUE),
    error = function(e) conditionMessage(e)
  )
  fig1_ok <- file.exists(fig1_dest) && isTRUE(file.info(fig1_dest)$size > 5000)
  if (!fig1_ok) {
    cli::cli_alert_warning("redraw Fig1 未写出，回退 MIMIC plot 单图")
    if (length(st)) cli::cli_alert_warning("{paste(utils::head(st, 8), collapse = ' | ')}")
  }
}
if (!fig1_ok) .safe_copy(src_traj, fig1_dest)
# Fig2 = KM 双库竖拼
# Fig2 = landmark 分段 KM（redraw_gpr_fig2_fcimb_landmark_km.R）；勿竖拼普通全随访 KM
fig2_dest <- file.path(.pdf, "Figure 2. Kaplan Meier survival by trajectory class.pdf")
redraw_km <- file.path(.root, "run/trajectory_prognosis/redraw_gpr_fig2_fcimb_landmark_km.R")
fig2_ok <- FALSE
if (file.exists(redraw_km)) {
  cli::cli_alert_info("Fig2: 调用 redraw_gpr_fig2_fcimb_landmark_km.R（day-cut landmark a/b）")
  rbin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  tryCatch(
    system2(rbin, args = c("--vanilla", shQuote(redraw_km)), stdout = TRUE, stderr = TRUE),
    error = function(e) conditionMessage(e)
  )
  fig2_ok <- file.exists(fig2_dest) && isTRUE(file.info(fig2_dest)$size > 5000)
}
if (!fig2_ok) {
  cli::cli_alert_warning("landmark Fig2 未写出，回退双库普通 KM 竖拼")
  .stack2(src_km_m, src_km_e, fig2_dest)
}
# Fig3 = 发现集动态预测（MIMIC）；Fig4 = 外验同构（eICU）——对齐文献，非 AUC
.safe_copy(src_dyn_m, file.path(.pdf, "Figure 3. Dynamic prediction of GPR trajectory.pdf"))
.safe_copy(src_dyn_e, file.path(.pdf, "Figure 4. Dynamic prediction of GPR trajectory.pdf"))
# Fig5/6 = PAMM 时变关联四面板（发现/外验）；缺图时回退个体预测/亚组并记 MANIFEST
fig5_ok <- .safe_copy(src_pamm_m, file.path(.pdf, "Figure 5. PAMM time-varying association.pdf"))
fig6_ok <- .safe_copy(src_pamm_e, file.path(.pdf, "Figure 6. PAMM time-varying association.pdf"))
if (!isTRUE(fig5_ok)) {
  cli::cli_alert_warning("Fig5 PAMM 缺失，回退个体动态预测")
  .safe_copy(src_ind, file.path(.pdf, "Figure 5. Individual dynamic prediction.pdf"))
}
if (!isTRUE(fig6_ok)) {
  cli::cli_alert_warning("Fig6 PAMM 缺失，回退亚组森林")
  .stack2(src_sub_m, src_sub_e, file.path(.pdf, "Figure 6. Subgroup analysis by trajectory class.pdf"))
}
# 个体预测 / 亚组改附图
.safe_copy(src_ind, file.path(.pdf, "Figure S9. Individual dynamic prediction.pdf"))
.stack2(src_sub_m, src_sub_e, file.path(.pdf, "Figure S10. Subgroup analysis by trajectory class.pdf"))

# Supp
.stack2(src_flow_m, src_flow_e,
        file.path(.pdf, "Figure S1. Flowchart of patient selection.pdf"),
        labels = c("a. MIMIC-IV (derivation)", "b. eICU (external validation)"))
# 若根已有 CONSORT 双栏，优先用
root_flow <- file.path(index_root, "Figures/pdf/Figure 1. Flowchart of patient selection.pdf")
if (file.exists(root_flow) && file.info(root_flow)$size > 20000) {
  .safe_copy(root_flow, file.path(.pdf, "Figure S1. Flowchart of patient selection.pdf"))
}
.safe_copy(src_cut, file.path(.pdf, "Figure S2. Piecewise Cox cut point search.pdf"))
.stack2(src_miss_m, src_miss_e, file.path(.pdf, "Figure S3. Missing value overview.pdf"))
# 动/静 AUC 降为附图（文献 Fig4 是外验 dynpred，不是 AUC）
.safe_copy(src_auc,  file.path(.pdf, "Figure S4. Weibull dynamic model comparison AUC.pdf"))
.safe_copy(src_cidx, file.path(.pdf, "Figure S5. Weibull dynamic model comparison C index.pdf"))
.safe_copy(src_acc,  file.path(.pdf, "Figure S6. Weibull dynamic model comparison Accuracy.pdf"))
.safe_copy(src_sens, file.path(.pdf, "Figure S7. Weibull dynamic model comparison Sensitivity.pdf"))
.safe_copy(src_spec, file.path(.pdf, "Figure S8. Weibull dynamic model comparison Specificity.pdf"))

# ── 表：对齐文献 Table1 + data sheet S 角色（能映射的尽量同号）──────────────
.root_tab <- file.path(index_root, "Tables")
.tab_map <- list(
  # 文献 Table1 = 双库基线；本课题缺正式 Table1，用插补前后基线作主表代理并标 S1
  # 正式：Metrics→S3/S5；Posterior→S4/S6；HR→S7/S8；PAMM burden→S9/S10
  c("Table 2-MIMIC. Metrics for determining the optimal number of classes.xlsx",
    "Table S3-MIMIC. Model fit metrics for optimal number of classes.xlsx"),
  c("Table S8-MIMIC. Posterior classification table.xlsx",
    "Table S4-MIMIC. Mean posterior probabilities.xlsx"),
  c("Table 3-MIMIC. Time-dependent HR for trajectory classes.xlsx",
    "Table S7-MIMIC. Time-dependent HR for trajectory classes.xlsx"),
  c("Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx",
    "Table S1-MIMIC. Baseline characteristics before and after multiple imputation.xlsx"),
  c("Table S1-eICU. Baseline characteristics of patients before and after multiple imputation.xlsx",
    "Table S1-eICU. Baseline characteristics before and after multiple imputation.xlsx"),
  c("Table S2-MIMIC. Normality test results for continuous variables.xlsx",
    "Table S2-MIMIC. Normality test results for continuous variables.xlsx"),
  c("Table S2-eICU. Normality test results for continuous variables.xlsx",
    "Table S2-eICU. Normality test results for continuous variables.xlsx"),
  c("Table S3-MIMIC. Univariate Regression Analysis.xlsx",
    "Table S11-MIMIC. Univariate Regression Analysis.xlsx"),
  c("Table S3-eICU. Univariate Regression Analysis.xlsx",
    "Table S11-eICU. Univariate Regression Analysis.xlsx"),
  c("Table S4-MIMIC. Multicollinearity Analysis (VIF, univariate screen).xlsx",
    "Table S12-MIMIC. Multicollinearity Analysis VIF screen.xlsx"),
  c("Table S4-eICU. Multicollinearity Analysis (VIF, univariate screen).xlsx",
    "Table S12-eICU. Multicollinearity Analysis VIF screen.xlsx"),
  c("Table S5-MIMIC. Multivariable Regression Analysis.xlsx",
    "Table S13-MIMIC. Multivariable Regression Analysis.xlsx"),
  c("Table S5-eICU. Multivariable Regression Analysis.xlsx",
    "Table S13-eICU. Multivariable Regression Analysis.xlsx"),
  c("Table S6-MIMIC. Multicollinearity Analysis (VIF, multivariate final).xlsx",
    "Table S14-MIMIC. Multicollinearity Analysis VIF final.xlsx"),
  c("Table S6-eICU. Multicollinearity Analysis (VIF, multivariate final).xlsx",
    "Table S14-eICU. Multicollinearity Analysis VIF final.xlsx"),
  c("Table S7-MIMIC. Baseline characteristics by trajectory class (GPR).xlsx",
    "Table S15-MIMIC. Baseline characteristics by trajectory class.xlsx"),
  c("Table S7-eICU. Baseline characteristics by trajectory class (GPR).xlsx",
    "Table S15-eICU. Baseline characteristics by trajectory class.xlsx")
)

# 保持引擎根 Tables 原名同步一份（便于对照），再按文献角色复制改名
for (f in list.files(.root_tab, pattern = "\\.xlsx$", full.names = TRUE)) {
  if (grepl("^~\\$|_archive", basename(f))) next
  .safe_copy(f, file.path(.tab, basename(f)))
}
for (pair in .tab_map) {
  src <- file.path(.root_tab, pair[[1]])
  if (!file.exists(src)) src <- file.path(.tab, pair[[1]])
  if (file.exists(src)) .safe_copy(src, file.path(.tab, pair[[2]]))
}

# PAMM burden → S9/S10
pamm_m <- .find1(prefer = "Table_PAMM_burden_HR_GPR\\.csv")
pamm_e <- list.files(file.path(index_root, "eicu"), pattern = "Table_PAMM_burden_HR_GPR\\.csv$",
                     recursive = TRUE, full.names = TRUE)
pamm_e <- pamm_e[1]
if (!is.na(pamm_m) && file.exists(pamm_m) && requireNamespace("openxlsx", quietly = TRUE)) {
  d <- utils::read.csv(pamm_m, stringsAsFactors = FALSE)
  openxlsx::write.xlsx(d, file.path(.tab, "Table S9-MIMIC. PAMM exposure burden and mortality.xlsx"))
}
if (!is.na(pamm_e) && length(pamm_e) && file.exists(pamm_e) && requireNamespace("openxlsx", quietly = TRUE)) {
  d <- utils::read.csv(pamm_e, stringsAsFactors = FALSE)
  openxlsx::write.xlsx(d, file.path(.tab, "Table S10-eICU. PAMM exposure burden and mortality.xlsx"))
}

# eICU Table1 HR if present under wrong name
eicu_hr <- .find1(file.path(index_root, "eicu/Tables/Table 1-eICU. Time-dependent HR for trajectory classes.xlsx"))
if (!is.na(eicu_hr)) {
  .safe_copy(eicu_hr, file.path(.tab, "Table S8-eICU. Time-dependent HR for trajectory classes.xlsx"))
}

# ── image_information + MANIFEST ────────────────────────────────────────────
.write_md <- function(stem, body) {
  writeLines(c(paste0("# ", stem), "", body), file.path(.md, paste0(stem, ".md")))
}
fig_notes <- list(
  "Figure 1. Trajectory of GPR latent classes" = c(
    "## 图面说明",
    "对齐文献 Figure 1：JLCM 潜类别 GPR 轨迹（发现集 MIMIC）。",
    "外验 eICU 用发现集固定参数分类，未单独重估轨迹均值曲线。",
    "",
    "## 分析上下文",
    "暴露 GPR；结局 28 天院内死亡；数据库 MIMIC-IV（derivation）。"
  ),
  "Figure 2. Kaplan Meier survival by trajectory class" = c(
    "## 图面说明",
    "对齐文献 Figure 2：landmark 分段 KM（最优 cut 断开；左 0–cut、右 cut–28 条件生存重启；a MIMIC / b eICU）。",
    "",
    "## 分析上下文",
    "结局 28 天院内死亡；分组 = JLCM 潜类；分段点 = piecewise Cox 最优 cut。"
  ),
  "Figure 3. Dynamic prediction of GPR trajectory" = c(
    "## 图面说明",
    "对齐文献 Figure 3：发现集多 landmark 动态预测（历史轨迹 + 预测死亡风险副轴）。",
    "面板 Landmark 3/5/7/12 d（ICU 日索引从 day1 起时 day2 对 ns(df=2) 不可估，故最早为 day3）。",
    "",
    "## 分析上下文",
    "发现集 MIMIC-IV；暴露 GPR；结局 28 天院内死亡；副轴 = Predicted mortality risk。"
  ),
  "Figure 4. Dynamic prediction of GPR trajectory" = c(
    "## 图面说明",
    "对齐文献 Figure 4：外验集同构动态预测（发现集 JLCM 固定参数 + eICU newdata）。",
    "面板与 Figure 3 相同 landmark；副轴 Predicted mortality risk。",
    "",
    "## 分析上下文",
    "外验 eICU；类别来自外部 assignment；非动/静 AUC（AUC 见 Figure S4）。"
  ),
  "Figure 5. PAMM time-varying association" = c(
    "## 图面说明",
    "对齐文献 Figure 5：发现集 PAMM 四面板。",
    "(a) 时变暴露–死亡 HR；(b) 按 landmark 分层；(c) 暴露时间效应；(d) 按暴露水平分层。",
    "",
    "## 分析上下文",
    "发现集 MIMIC；暴露 GPR；结局 28 天院内死亡；PAMM（pammtools + mgcv）。"
  ),
  "Figure 6. PAMM time-varying association" = c(
    "## 图面说明",
    "对齐文献 Figure 6：外验集 PAMM 同构四面板（发现集锁定异常阈值）。",
    "",
    "## 分析上下文",
    "外验 eICU；暴露 GPR；与 Figure 5 同一模型规格。"
  ),
  "Figure S1. Flowchart of patient selection" = c(
    "## 图面说明",
    "对齐文献 Supplementary Figure 1：纳排流程图（双库）。",
    "",
    "## 分析上下文",
    "COPD ICU；MIMIC 发现 / eICU 外验。"
  )
)
for (nm in names(fig_notes)) {
  fp <- file.path(.pdf, paste0(nm, ".pdf"))
  if (file.exists(fp)) .write_md(nm, fig_notes[[nm]])
}

manifest <- c(
  "# GPR summary_results — fcimb-16-1871653 顺序映射",
  "",
  "| 交付文件 | 文献角色 | 来源 |",
  "|---|---|---|",
  "| Figure 1. Trajectory… | Fig1 轨迹类 | MIMIC JLCM plot |",
  "| Figure 2. Kaplan Meier… | Fig2 KM | MIMIC+eICU 竖拼 |",
  "| Figure 3. Dynamic prediction… | Fig3 发现集动态预测 | MIMIC dynpred mortality |",
  "| Figure 4. Dynamic prediction… | Fig4 外验动态预测 | eICU dynpred（发现模型） |",
  "| Figure 5. PAMM… | Fig5 发现集 PAMM 四面板 | MIMIC PAMM |",
  "| Figure 6. PAMM… | Fig6 外验 PAMM 四面板 | eICU PAMM |",
  "| Figure S1. Flowchart… | Supp Fig1 纳排 | CONSORT 双栏 |",
  "| Figure S2. Piecewise Cox… | 分段切点（课题补充） | MIMIC cutsearch |",
  "| Figure S4. …AUC | 动/静 AUC（非主文 Fig4） | Weibull AUC |",
  "| Table S3-MIMIC Metrics | Supp Table3 选类 | Table2 Metrics |",
  "| Table S4-MIMIC Posterior | Supp Table4 后验 | Table S8 Posterior |",
  "| Table S7-MIMIC HR | Supp Table7 时依 HR | Table3 HR |",
  "| Table S8-eICU HR | Supp Table8 | eICU HR（若有） |",
  "| Table S9/S10 PAMM burden | Supp Table9/10 暴露负担 | PAMM CSV |",
  "",
  "生成时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
.rep <- file.path(dirname(dirname(index_root)), "reports")
dir.create(.rep, recursive = TRUE, showWarnings = FALSE)
writeLines(manifest, file.path(.rep, "GPR_FIGURE_TABLE_MANIFEST_fcimb.md"))
# 映射说明并入 Methods，避免交付根非白名单文件
meth <- c(
  "# Statistical analysis (GPR trajectory — COPD)",
  "",
  "Joint latent class mixed models (JLCM) identified longitudinal GPR trajectories in the MIMIC-IV derivation cohort; class membership was applied to eICU with fixed parameters. Associations with 28-day in-hospital mortality used piecewise Cox models and dynamic prediction. Piece-wise exponential additive mixed models (PAMM) summarized continuous GPR–mortality associations (burden tables).",
  "",
  "Figure/table order follows Frontiers CIMB fcimb-16-1871653 where counterparts exist:",
  "",
  "- Figure 1: trajectory classes (derivation)",
  "- Figure 2: Kaplan–Meier by class (derivation + validation)",
  "- Figure 3: dynamic prediction (MIMIC derivation; mortality secondary axis; landmarks 3/5/7/12 d)",
  "- Figure 4: dynamic prediction (eICU external; same landmarks; discovery JLCM fixed)",
  "- Figure 5–6: PAMM time-varying association panels (derivation / external)",
  "- Figure S1: flowchart (literature Supplementary Figure 1)",
  "- Figure S4: dynamic vs static AUC (supplement; not main-text Figure 4)",
  "",
  "Full mapping: reports/GPR_FIGURE_TABLE_MANIFEST_fcimb.md",
  "",
  "## Software",
  paste0("- R ", R.version$version.string)
)
writeLines(meth, file.path(.sum, "Methods_statistical_analysis.md"))
writeLines(c(R.version$version.string, paste("Date", Sys.Date())),
           file.path(.sum, "Methods_software_versions.txt"))

# 四目录 / 白名单
if (exists("pub_figure_ensure_formats", mode = "function")) {
  tryCatch(
    pub_figure_ensure_formats(.fig, config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))),
    error = function(e) message("ensure_formats: ", conditionMessage(e))
  )
}
if (exists("pub_prune_delivery_root", mode = "function")) {
  tryCatch(
    pub_prune_delivery_root(.sum),
    error = function(e) message("prune: ", conditionMessage(e))
  )
}

cli::cli_alert_success("summary_results → {.path {(.sum)}}")
cli::cli_alert_info("Figures: {length(list.files(.pdf, pattern='\\\\.pdf$'))} | Tables: {length(list.files(.tab, pattern='\\\\.xlsx$'))}")
