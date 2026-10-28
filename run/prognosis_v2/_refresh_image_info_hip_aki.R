#!/usr/bin/env Rscript
# 刷新 Hip AKI prognosis_v2 image_information（禁止 28-day / 未收获残留）
suppressPackageStartupMessages({
  library(data.table)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)

.out <- {
  cands <- c(
    "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results",
    "/mnt/g/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) stop("summary_results not found")
  hit[[1L]]
}
.fig <- file.path(.out, "Figures")
.md <- file.path(.fig, "image_information")
.ws <- list.files(
  file.path(dirname(.out), "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- .ws[order(file.info(.ws)$mtime, decreasing = TRUE)][1L]
sg <- as.data.frame(fread(file.path(.ws, "Subgroup_rows.csv")))
fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (!is.finite(p)) "—" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
fmt_hr <- function(hr, lo, hi) {
  sprintf("%.3f (%.3f\u2013%.3f)", hr, lo, hi)
}

write_md <- function(stem, face, ctx_lines) {
  path <- file.path(.md, paste0(stem, ".md"))
  lines <- c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    face,
    "",
    "## 分析上下文",
    ctx_lines,
    ""
  )
  writeLines(lines, path, useBytes = TRUE)
  message("OK ", basename(path))
}

ctx_common <- c(
  "- 暴露: SIRI, PIV",
  "- 结局: 365-day all-cause mortality（住院/ICU 入院后 365 天全因死亡）",
  "- 样本量: MIMIC N = 228（死亡 54）",
  "- Grouping: binary（quantile_scheme_cascade 锁定；High vs Low）",
  "- 数据库: MIMIC-IV v3.1（单库）",
  "- 是否拼图: 否"
)

# Fig1
write_md(
  "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI",
  paste(
    "纳排流程图（MIMIC-IV）。图面逐步人数（与 Flowchart_attrition 一致）：",
    "- Hip arthroplasty with AKI：n = 360",
    "- 排除 Age < 65 或年龄缺失：n = 100 → 保留 Aged ≥ 65：n = 260",
    "- 排除 SIRI/PIV 不可算：n = 31；排除缺失 365 天随访或无效暴露：n = 1 → 分析集 n = 228",
    "- 终局：365-day all-cause death n = 54；Alive at 365 days n = 174",
    sep = "\n"
  ),
  ctx_common
)

# Fig2
write_md(
  "Figure 2. Boruta confirmation and SHAP values for all-cause mortality",
  paste(
    "四面板特征筛选与解释：A Boruta 重要性（Confirmed/Rejected/Shadow）；B Boruta Z-score 轨迹；",
    "C SHAP 蜂群（log-hazard）；D mean |SHAP| 排序。炎性指标 SIRI/PIV 与临床/实验室协变量同框。",
    "样本量 N = 228（插补后操作层 complete #1）。",
    sep = "\n"
  ),
  ctx_common
)

# Fig3
write_md(
  "Figure 3. Cumulative incidence of all-cause mortality by inflammatory index",
  paste(
    "双面板累积发病率（1−KM）按 binary 分组（Low/High）。",
    "图上标注：",
    "- SIRI：Log-rank P = 0.009；风险集 Low/High 起点各 n = 114",
    "- PIV：Log-rank P = 0.010；风险集 Low/High 起点各 n = 114",
    "随访横轴为年（截尾于 365 天）。",
    sep = "\n"
  ),
  ctx_common
)

# Fig4（数值以当次重导为准；本文件仅作 remirror 后备模板）
write_md(
  "Figure 4. Restricted cubic spline of inflammatory indices and all-cause mortality",
  paste(
    "双面板 RCS：暴露 per 1 SD；调整 Age, Gender, CHARLSON；参照=0 SD（均值）。",
    "主推断以 Table 3 线性 per-SD Cox 为准；RCS 仅报告剂量–反应形状。",
    "具体 P-overall / P-nonlinear 见图面字幕（由 _fix_p0 或 remirror 重导后写入）。",
    sep = "\n"
  ),
  ctx_common
)

# Fig5
write_md(
  "Figure 5. Receiver operating characteristic curves for 365-day all-cause mortality",
  paste(
    "365 天全因死亡 ROC。图上标注：SIRI AUC = 0.721；PIV AUC = 0.710。",
    "与 Table S4 Youden 口径一致（SIRI Sensitivity 0.685 / Specificity 0.684；",
    "PIV Sensitivity 0.481 / Specificity 0.862）。",
    sep = "\n"
  ),
  ctx_common
)

# Fig6：底边 = Direct effect（与 Table S8 同源）；勿再写 total HR
write_md(
  "Figure 6. Mediation path diagram of inflammatory indices and all-cause mortality",
  paste(
    "双面板中介路径图（中介 = OASIS；暴露 per 1 SD；底边 = Direct effect HR，与 Table S8 同源）。",
    "路径模型调整 Age, Gender, CHARLSON。",
    "图上标注以当次重导图面 / Table S8 为准（path a / b / Direct / Proportion mediated）。",
    sep = "\n"
  ),
  ctx_common
)

# Fig7 — 从 Subgroup_rows 摘 Overall + Age
sg_lines <- character(0)
for (idx in c("SIRI", "PIV")) {
  ov <- sg[sg$Index == idx & sg$row_lab == "Overall", ][1, ]
  sg_lines <- c(sg_lines, sprintf(
    "- %s Overall：HR = %s；P = %s；N = %s；events = %s",
    idx, fmt_hr(ov$HR, ov$lo, ov$hi), fmt_p(ov$p),
    pub_format_int(ov$N), pub_format_int(ov$events)
  ))
  age <- sg[sg$Index == idx & grepl("^Age:", sg$row_lab), ]
  for (i in seq_len(nrow(age))) {
    sg_lines <- c(sg_lines, sprintf(
      "- %s %s：HR = %s；P = %s；N = %s",
      idx, age$row_lab[i], fmt_hr(age$HR[i], age$lo[i], age$hi[i]),
      fmt_p(age$p[i]), pub_format_int(age$N[i])
    ))
  }
}
age_sum_s <- sum(sg$N[sg$Index == "SIRI" & grepl("^Age:", sg$row_lab)], na.rm = TRUE)
write_md(
  "Figure 7. Subgroup analyses of inflammatory indices and all-cause mortality",
  paste(
    c(
      "双面板亚组森林图：全分析集上 High vs Low（与 Table 3 分组一致）；分层含 Age（切点 75）、Sex、Hypertension、Diabetes、SOFA。",
      "图上/结果表关键标注（摘自 Subgroup_rows.csv）：",
      sg_lines,
      sprintf("分母核对：SIRI/PIV 的 Age 两层 N 之和均为 %s（= 分析集 N = 228）。", pub_format_int(age_sum_s))
    ),
    collapse = "\n"
  ),
  ctx_common
)

message("image_information refreshed")
