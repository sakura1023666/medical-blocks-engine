#!/usr/bin/env Rscript
# 落实 yuhan_老师.docx 第二轮：样本量桥接、叙事、DSST contrast 附表、
# contextual 主比较、Figure3 双面板 episodic。
# Usage: Rscript run/pa_mobility_cognitive/apply_teacher_revision_round2.R

root <- normalizePath(getwd(), winslash = "/")
if (basename(root) == "pa_mobility_cognitive") {
  root <- normalizePath(file.path(root, "..", ".."), winslash = "/")
}
setwd(root)
message("ROOT=", root)

suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
})

batch <- "/mnt/g/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
data_root <- "/mnt/g/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"

# 载入最新 CHARLS / NHANES checkpoint
charls_ck <- file.path(batch, "by_unit", "【success】CHARLS", "checkpoints", "pamob_teacher_revision_charls.rds")
if (!file.exists(charls_ck)) {
  charls_ck <- file.path(batch, "by_unit", "【success】CHARLS", "checkpoints", "pamob_assemble_charls.rds")
}
nhanes_ck <- file.path(batch, "by_unit", "【success】NHANES", "checkpoints", "pamob_teacher_revision_nhanes.rds")
if (!file.exists(nhanes_ck)) {
  nhanes_ck <- file.path(batch, "by_unit", "【success】NHANES", "checkpoints", "pamob_assemble_nhanes.rds")
}
stopifnot(file.exists(charls_ck), file.exists(nhanes_ck))

ctx_c <- readRDS(charls_ck)$ctx
ctx_n <- readRDS(nhanes_ck)$ctx
config <- ctx_c$config
config$project$root <- root
config$pamob$data_root <- data_root

# CHARLS unit 重跑：baseline → traj → flowchart（LMM 结果沿用 checkpoint）
source("Blocks/74_pa_mobility_cognitive_full/04block_pamob_baseline_charls.R", local = FALSE)
source("Blocks/74_pa_mobility_cognitive_full/08block_pamob_traj_plot.R", local = FALSE)
source("Blocks/74_pa_mobility_cognitive_full/10block_pamob_flowchart.R", local = FALSE)
source("Blocks/74_pa_mobility_cognitive_full/19block_pamob_contextual_inventory.R", local = FALSE)

charls_dir <- file.path(batch, "by_unit", "【success】CHARLS")
config_c <- config
config_c$project$output_dir <- charls_dir
ctx <- list(
  config = config_c,
  data = ctx_c$data,
  results = ctx_c$results %||% list()
)
# 保证 long / baseline 在
stopifnot(!is.null(ctx$data$pamob_charls_long))

message(">> baseline_charls")
ctx <- block_pamob_baseline_charls(ctx)
message(">> traj_plot dual")
ctx <- block_pamob_traj_plot(ctx)
message(">> flowchart")
ctx <- block_pamob_flowchart(ctx)

# contextual：双库
config_b <- config
config_b$project$output_dir <- batch
ctx_b <- list(
  config = config_b,
  data = list(
    pamob_charls_long = ctx$data$pamob_charls_long,
    pamob_charls_baseline = ctx$data$pamob_charls_baseline %||% ctx_c$data$pamob_charls_baseline,
    pamob_nhanes_dsst = ctx_n$data$pamob_nhanes_dsst %||% ctx_n$results$pamob_svy_dsst$data
  ),
  results = list()
)
message(">> contextual_inventory")
ctx_b <- block_pamob_contextual_inventory(ctx_b)

# 保存 CHARLS checkpoint 增量
saveRDS(list(ctx = ctx, time = Sys.time(), tag = "teacher_round2"),
        file.path(charls_dir, "checkpoints", "pamob_teacher_revision_charls.rds"))

# 叙事草稿
ms <- file.path(batch, "Manuscript")
dir.create(ms, recursive = TRUE, showWarnings = FALSE)
bridge <- ctx$results$pamob_baseline_charls$n_bridge
n_lmm <- ctx$results$pamob_baseline_charls$n_lmm
n_obs <- ctx$results$pamob_baseline_charls$n_obs
n_ge2 <- ctx$results$pamob_baseline_charls$n_ge2
n_t1 <- ctx$results$pamob_baseline_charls$n

md <- c(
  "# Methods/Results notes — teacher revision round 2 (yuhan_老师.docx)",
  "",
  "## 1. Sample size bridge (CHARLS)",
  sprintf("- **LMM unique N** = %s", n_lmm),
  sprintf("- **LMM person–wave observations** = %s", n_obs),
  sprintf("- **IDs with ≥2 cognition waves** = %s (sensitivity subset; not Table 1 filter)", n_ge2),
  sprintf("- **Table 1 N** = %s (**same unique IDs as LMM**, baseline covariates)", n_t1),
  "- Important: ≥2-wave N is **not** filtered down to Table 1. Table 1 matches the LMM ID set.",
  "- Some LMM IDs lack a cognition row at wave 2011 in the long file (first cognition later); Table 1 still includes them via baseline covariate merge.",
  "",
  "## 2. Episodic memory interpretation (Active–limited)",
  "- Do **not** claim faster episodic-memory decline is unique to Active–limited.",
  "- Model 3: both mobility-limited groups (Active–limited and Inactive–limited) show faster episodic decline vs Active–preserved;",
  "  Active–limited vs Inactive–limited slope contrast ≈ 0 (not significant).",
  "- Accurate framing: **mobility-limited phenotypes share faster episodic-memory decline**;",
  "  Active–limited is notable for **relative preservation on global cognition / DSST** while memory still declines faster.",
  "",
  "## 3. NHANES DSST direct contrasts",
  "- Formal supplementary **Table S10** lists preset pairwise DSST contrasts",
  "  (Inactive–preserved vs Active–preserved; Active–limited vs Inactive–limited).",
  "",
  "## 4. Contextual primary comparisons",
  "- Primary: Inactive–preserved vs Active–preserved; Active–limited vs Inactive–limited.",
  "- Secondary only: Active–limited vs Inactive–preserved (crosses both dimensions).",
  "",
  "## 5. Figure 3 (manuscript trajectory figure)",
  "- Dual panel with 95% CI: **A** global cognition; **B** episodic memory.",
  "- (Engine filename remains Figure 3; manuscript section numbering may call this Figure 4.)",
  ""
)
writeLines(md, file.path(ms, "Teacher_revision_round2_notes.md"))

# 刷 Figure image_information + 四目录
fig_root <- file.path(batch, "Figures")
# 从 unit 镜像 Fig2/Fig3 到根
for (stem in c(
  "Figure 2. CHARLS flowchart",
  "Figure 3. CHARLS cognitive trajectories"
)) {
  for (sub in c("pdf")) {
    src <- file.path(charls_dir, "Figures", paste0(stem, ".", sub))
    # blocks may write flat or under pdf/
    if (!file.exists(src)) src <- file.path(charls_dir, "Figures", "pdf", paste0(stem, ".", sub))
    if (!file.exists(src)) {
      # pamob may write directly to Figures/
      alt <- list.files(file.path(charls_dir, "Figures"), pattern = gsub("([.\\(\\)])", "\\\\\\1", stem),
                        recursive = TRUE, full.names = TRUE)
      alt <- alt[grepl("\\.pdf$", alt)]
      if (length(alt)) src <- alt[[1L]]
    }
    if (file.exists(src)) {
      dir.create(file.path(fig_root, "pdf"), recursive = TRUE, showWarnings = FALSE)
      file.copy(src, file.path(fig_root, "pdf", paste0(stem, ".pdf")), overwrite = TRUE)
      message("mirrored ", basename(src))
    } else {
      message("WARN missing ", stem)
    }
  }
}

# Fig2/3 image md
img <- file.path(fig_root, "image_information")
dir.create(img, recursive = TRUE, showWarnings = FALSE)
writeLines(c(
  "# Figure 2. CHARLS flowchart",
  "",
  "## 图面说明",
  "CONSORT 纳排。终步 Table 1 与 LMM unique IDs 同口径（非从 ≥2-wave 子集再筛）。",
  sprintf("LMM unique N = %s；person–wave obs = %s；≥2-wave IDs = %s；Table 1 N = %s。",
          n_lmm, n_obs, n_ge2, n_t1),
  "",
  "## 分析上下文",
  "- 暴露：PA–mobility 四组表型",
  "- 结局：纵向认知 LMM / 基线 Table 1",
  sprintf("- 样本量：LMM n=%s；obs=%s", n_lmm, n_obs),
  "- 数据库：CHARLS",
  "- 是否拼图：否"
), file.path(img, "Figure 2. CHARLS flowchart.md"))

writeLines(c(
  "# Figure 3. CHARLS cognitive trajectories",
  "",
  "## 图面说明",
  "双面板校正预测轨迹（Model 3 协变量均值；固定效应 95% CI ribbon）：",
  "- **A**：Global cognition — 组间以水平差异为主，斜率差异不显著。",
  "- **B**：Episodic memory — mobility-limited 两组（Active–limited 与 Inactive–limited）下降更快；",
  "  Active–limited vs Inactive–limited 的 slope contrast 不显著，故不宜写成 Active–limited 特有。",
  "",
  "## 分析上下文",
  "- 暴露：基线 PA–mobility 四组",
  "- 结局：Global cognition；Episodic memory",
  sprintf("- 样本量：LMM unique N=%s；obs=%s", n_lmm, n_obs),
  "- Grouping：连续时间 LMM",
  "- 数据库：CHARLS",
  "- 是否拼图：双面板（同库两结局）"
), file.path(img, "Figure 3. CHARLS cognitive trajectories.md"))

source("R/pub_figure_export.R")
pub_figure_ensure_formats(fig_root, config = config)

# 重建根 Tables
message(">> rebuild_pamob_pub_tables")
system2("Rscript", c("run/pa_mobility_cognitive/rebuild_pamob_pub_tables.R"), stdout = TRUE, stderr = TRUE)

# 同步汇总包
sumd <- file.path(batch, "老师审稿修订汇总_2026-09-29")
if (dir.exists(sumd)) {
  file.copy(list.files(file.path(batch, "Tables"), pattern = "\\.xlsx$", full.names = TRUE),
            file.path(sumd, "Tables"), overwrite = TRUE)
  unlink(file.path(sumd, "Figures"), recursive = TRUE)
  dir.create(file.path(sumd, "Figures"), recursive = TRUE, showWarnings = FALSE)
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    if (dir.exists(file.path(fig_root, sub))) {
      file.copy(file.path(fig_root, sub), file.path(sumd, "Figures"), recursive = TRUE, overwrite = TRUE)
    }
  }
  file.copy(file.path(ms, "Teacher_revision_round2_notes.md"),
            file.path(sumd, "Manuscript"), overwrite = TRUE)
}

message("DONE teacher round2")
message("Table1 N=", n_t1, " LMM=", n_lmm, " obs=", n_obs, " ge2=", n_ge2)
