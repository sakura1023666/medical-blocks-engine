#!/usr/bin/env Rscript
# apply_teacher_revision_yuhan.R — 落实 Yuhan 老师审稿六条（引擎已改后重跑）
# Usage: Rscript run/pa_mobility_cognitive/apply_teacher_revision_yuhan.R

.root_from <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sd <- dirname(normalizePath(sub("^--file=", "", f[[1]]), winslash = "/"))
    if (basename(sd) == "pa_mobility_cognitive") {
      return(normalizePath(file.path(sd, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(getwd(), winslash = "/")
}
root <- .root_from()
setwd(root)
message("ROOT=", root)

suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
  source("R/pipeline_runner.R")
})

batch <- "/mnt/g/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
cfg_env <- new.env(parent = globalenv())
# Prefer engine config (has nhanes_dsst_age_*), then overlay batch paths
sys.source("configs/config_pa_mobility_cognitive.R", envir = cfg_env)
config <- cfg_env$config
config$project$root <- root
config$project$output_dir <- batch
.g2mnt <- function(p) {
  p <- gsub("\\\\", "/", as.character(p %||% ""))
  sub("^G:", "/mnt/g", p)
}
config$pamob$data_root <- .g2mnt(config$pamob$data_root)
if (!dir.exists(config$pamob$data_root)) {
  config$pamob$data_root <- "/mnt/g/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"
}
message("batch=", batch)
message("data_root=", config$pamob$data_root)

.block_files <- list(
  pamob_assemble_charls = "Blocks/74_pa_mobility_cognitive_full/02block_pamob_assemble_charls.R",
  pamob_cognition_long = "Blocks/74_pa_mobility_cognitive_full/03block_pamob_cognition_long.R",
  pamob_baseline_charls = "Blocks/74_pa_mobility_cognitive_full/04block_pamob_baseline_charls.R",
  pamob_lmm_global = "Blocks/74_pa_mobility_cognitive_full/05block_pamob_lmm_global.R",
  pamob_lmm_episodic = "Blocks/74_pa_mobility_cognitive_full/06block_pamob_lmm_episodic.R",
  pamob_contrast_preset = "Blocks/74_pa_mobility_cognitive_full/07block_pamob_contrast_preset.R",
  pamob_traj_plot = "Blocks/74_pa_mobility_cognitive_full/08block_pamob_traj_plot.R",
  pamob_sensitivity_charls = "Blocks/74_pa_mobility_cognitive_full/09block_pamob_sensitivity_charls.R",
  pamob_flowchart = "Blocks/74_pa_mobility_cognitive_full/10block_pamob_flowchart.R",
  pamob_concept_fig1 = "Blocks/74_pa_mobility_cognitive_full/11block_pamob_concept_fig1.R",
  pamob_assemble_nhanes = "Blocks/74_pa_mobility_cognitive_full/12block_pamob_assemble_nhanes.R",
  pamob_baseline_nhanes = "Blocks/74_pa_mobility_cognitive_full/13block_pamob_baseline_nhanes.R",
  pamob_svy_dsst = "Blocks/74_pa_mobility_cognitive_full/14block_pamob_svy_dsst.R",
  pamob_svy_nfl = "Blocks/74_pa_mobility_cognitive_full/15block_pamob_svy_nfl.R",
  pamob_panel_fig4 = "Blocks/74_pa_mobility_cognitive_full/16block_pamob_panel_fig4.R",
  pamob_sensitivity_nhanes = "Blocks/74_pa_mobility_cognitive_full/17block_pamob_sensitivity_nhanes.R",
  pamob_contextual_inventory = "Blocks/74_pa_mobility_cognitive_full/19block_pamob_contextual_inventory.R",
  pamob_pub_export = "Blocks/74_pa_mobility_cognitive_full/18block_pamob_pub_export.R"
)

.load_blocks <- function(names) {
  for (nm in names) {
    f <- .block_files[[nm]]
    if (is.null(f) || !file.exists(f)) stop("缺 block 文件: ", nm, " -> ", f)
    source(f, local = FALSE)
  }
}

.run_seq <- function(ctx, block_names, unit_label) {
  message("===== ", unit_label, " =====")
  .load_blocks(block_names)
  for (bn in block_names) {
    message(">> ", bn, " @ ", Sys.time())
    fn <- get(paste0("block_", bn))
    ctx <- fn(ctx)
  }
  ctx
}

# ── CHARLS unit ──
charls_dir <- file.path(batch, "by_unit", "【success】CHARLS")
dir.create(file.path(charls_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(charls_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(charls_dir, "checkpoints"), recursive = TRUE, showWarnings = FALSE)

ctx_c <- list(
  config = config,
  data = list(),
  results = list()
)
# point outputs into CHARLS unit via temporary override of pamob_out_root
# by setting project$output_dir to unit root for block writes
config_c <- config
config_c$project$output_dir <- charls_dir
ctx_c$config <- config_c

charls_blocks <- c(
  "pamob_assemble_charls", "pamob_cognition_long", "pamob_baseline_charls",
  "pamob_lmm_global", "pamob_lmm_episodic", "pamob_contrast_preset",
  "pamob_traj_plot", "pamob_sensitivity_charls",
  "pamob_flowchart", "pamob_concept_fig1",
  "pamob_contextual_inventory"
)
ctx_c <- .run_seq(ctx_c, charls_blocks, "CHARLS")
saveRDS(list(ctx = ctx_c), file.path(charls_dir, "checkpoints", "pamob_teacher_revision_charls.rds"))

# ── NHANES unit ──
nhanes_dir <- file.path(batch, "by_unit", "【success】NHANES")
dir.create(file.path(nhanes_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nhanes_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(nhanes_dir, "checkpoints"), recursive = TRUE, showWarnings = FALSE)
config_n <- config
config_n$project$output_dir <- nhanes_dir
ctx_n <- list(config = config_n, data = list(), results = list())
nhanes_blocks <- c(
  "pamob_assemble_nhanes", "pamob_baseline_nhanes",
  "pamob_svy_dsst", "pamob_svy_nfl", "pamob_panel_fig4",
  "pamob_sensitivity_nhanes"
)
ctx_n <- .run_seq(ctx_n, nhanes_blocks, "NHANES")
saveRDS(list(ctx = ctx_n), file.path(nhanes_dir, "checkpoints", "pamob_teacher_revision_nhanes.rds"))

# ── 复制单元图到根 Figures + 刷新文稿/诊断 ──
fig_root <- file.path(batch, "Figures")
dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
for (u in c(charls_dir, nhanes_dir)) {
  pdfs <- list.files(file.path(u, "Figures"), pattern = "\\.pdf$", full.names = TRUE, recursive = TRUE)
  # prefer top-level unit Figures pdfs
  pdfs <- list.files(file.path(u, "Figures"), pattern = "Figure.*\\.pdf$", full.names = TRUE)
  for (p in pdfs) file.copy(p, file.path(fig_root, basename(p)), overwrite = TRUE)
}

# Model diagnostics refresh
ms <- file.path(batch, "Manuscript")
dir.create(ms, recursive = TRUE, showWarnings = FALSE)
diag <- c(
  "# Model diagnostics — teacher revision",
  "",
  "## CHARLS",
  paste0("- Analytic long n_obs / n_ids: see Tables/CHARLS/Table_Pamob_CHARLS_Longitudinal_Diagnostics.csv"),
  paste0("- Table1 missing note: see by_unit CHARLS Tables/Table_Pamob_CHARLS_Table1_Missing_Note.txt"),
  paste0("- Active–limited episodic slope stability: Tables/CHARLS/Table_S_Active_limited_slope_stability.csv"),
  "",
  "## NHANES",
  paste0("- DSST main design info: by_unit NHANES/Tables/NHANES/Table_Pamob_NHANES_Design_Info_DSST.csv"),
  paste0("- sNfL exploratory design info: by_unit NHANES/Tables/NHANES/Table_Pamob_NHANES_Design_Info_NfL.csv"),
  paste0("- DSST analytic n: ", tryCatch(nrow(ctx_n$results$pamob_svy_dsst$data), error = function(e) NA)),
  paste0("- NfL exploratory n: ", tryCatch(nrow(ctx_n$results$pamob_svy_nfl$data), error = function(e) NA))
)
writeLines(diag, file.path(ms, "Model_diagnostics.md"))

# Methods/Results narrative (level + domain; NfL exploratory)
draft <- c(
  "# Methods and Results Draft — PA–Mobility Phenotypes and Cognitive Aging",
  "",
  "## Study design (revised narrative)",
  "Dual-database triangulation:",
  "1. **CHARLS** longitudinal cognition — emphasize between-phenotype differences in cognitive **levels**",
  "   and **domain-specific** trajectories (episodic memory), not uniform differences in global decline slopes.",
  "2. **NHANES** large-sample cross-sectional **DSST** (age \u226560, WTMEC2YR; not restricted to NfL).",
  "3. **sNfL** as an **exploratory** neurodegeneration-related biomarker subsample (WTSSNH2Y).",
  "",
  "## Phenotypes",
  "Four PA\u00d7mobility groups; reference Active\u2013preserved.",
  "Pre-specified pairwise contrasts: Inactive\u2013preserved vs Active\u2013preserved;",
  "Active\u2013limited vs Inactive\u2013limited (level and slope for CHARLS; mean difference for DSST).",
  "",
  "## Key CHARLS finding to foreground",
  "Active\u2013limited: relative preservation on global cognition / DSST triangulation,",
  "but faster **episodic memory** decline (Model 3 phenotype \u00d7 time) — domain-specific vulnerability",
  "within behavior\u2013capacity discordance (not labeled simply as resilient).",
  "",
  "## Global cognition slopes",
  "Model 3 phenotype \u00d7 time and preset global slope contrasts were not significant;",
  "do not frame the main story as distinct global cognitive decline speeds across four groups.",
  "",
  "## Deliverables",
  "- Table 1 CHARLS baseline; Table 2 global LMM; Table 3 episodic LMM;",
  "- Table 4 NHANES DSST-main baseline; Table 5 DSST regressions;",
  "- Table S exploratory sNfL; contextual inventory manuscript note.",
  "",
  paste0("_Updated teacher revision: ", format(Sys.time(), "%Y-%m-%d %H:%M"), "_")
)
writeLines(draft, file.path(ms, "Methods_Results_Draft.md"))

# Fig3 image_information
fig3_md <- file.path(fig_root, "image_information", "Figure 3. CHARLS cognitive trajectories.md")
dir.create(dirname(fig3_md), recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  "# Figure 3. CHARLS cognitive trajectories",
  "",
  "## 图面说明",
  "展示四组 PA\u2013mobility 表型在 CHARLS 中的校正后认知轨迹。",
  "读图重点为组间**水平偏移（parallel level shifts）**与域特异模式；",
  "global cognition 的组间斜率差异在 Model 3 中不显著，不宜解读为四组具有不同的整体下降速度。",
  "Active\u2013limited 的关键异质性见情景记忆结局（Table 3）。",
  "",
  "## 分析上下文",
  "- 暴露：基线 PA\u2013mobility 四组表型（参照 Active\u2013preserved）",
  "- 结局：global cognition（主图）；episodic memory 见对应主表",
  "- 数据库：CHARLS；Grouping：连续时间 LMM（非分位）",
  "- 是否拼图：单库轨迹图"
), fig3_md)

# Fig4 image_information
fig4_md <- file.path(fig_root, "image_information", "Figure 4. NHANES DSST and NfL panel.md")
writeLines(c(
  "# Figure 4. NHANES DSST and NfL panel",
  "",
  "## 图面说明",
  "主面板：完整 cognitive sample 上 Model3 校正后的 DSST 预测均值（WTMEC2YR）。",
  "副面板：sNfL 几何均值，标注 Exploratory（NfL 权重 subsample，非正文主认知分析）。",
  "",
  "## 分析上下文",
  "- 暴露：同一四组 PA\u2013mobility 表型",
  "- 结局：DSST（主）；log(sNfL)（exploratory）",
  "- 数据库：NHANES 2013\u20132014",
  "- DSST 与 NfL 不强制同一 complete-case 样本"
), fig4_md)

# Design spec one-liner
spec <- file.path(root, "docs/superpowers/specs/2026-09-20-pa-mobility-cognitive-charls-nhanes-design.md")
if (file.exists(spec)) {
  txt <- readLines(spec, warn = FALSE)
  note <- "\n\n> **Teacher revision (Yuhan):** Main scientific claim = cognitive **level** + **domain** heterogeneity (esp. Active\u2013limited episodic vulnerability); NHANES main = large-sample DSST; sNfL exploratory.\n"
  if (!any(grepl("Teacher revision \\(Yuhan\\)", txt))) {
    writeLines(c(txt, note), spec)
  }
}

# Rebuild pub xlsx + four formats
message(">> rebuild pub tables")
source("run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R", local = new.env(parent = globalenv()))

message(">> pub_figure_ensure_formats")
source("R/pub_figure_export.R", local = FALSE)
tryCatch(
  pub_figure_ensure_formats(fig_root, config = config),
  error = function(e) message("pub_figure_ensure_formats: ", conditionMessage(e))
)

message("DONE teacher revision @ ", Sys.time())
