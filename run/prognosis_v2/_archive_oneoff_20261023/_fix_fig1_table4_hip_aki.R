#!/usr/bin/env Rscript
# 一次性：Fig1 标注 365 天全因死亡；Table 4 改为院内死亡 + 存活出院竞争
suppressPackageStartupMessages({
  library(survival)
  library(cmprsk)
})
.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pv2_pub_names.R", local = FALSE)
source("R/attrition_log.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)

.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.tab <- file.path(.out, "Tables")
.fig <- file.path(.out, "Figures", "pdf")
.ws <- file.path(
  dirname(.out), "summary_results_delivery_workspace",
  "tables_non_xlsx_20261022_163923"
)
d0 <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
raw <- as.data.frame(readRDS(file.path(
  dirname(.out), "data", "analysis_Age65_SIRI_PIV_ready_365d.rds"
)))
id_d <- as.character(d0$ID)
id_r <- as.character(raw$subject_id)
m <- match(id_d, id_r)
d0$is_hosp_dead <- as.integer(raw$is_hosp_dead[m] %in% c(1L, TRUE, "1", "Yes"))
d0$hosp_day <- as.numeric(raw$hosp_day[m])
d0$futime_years <- if ("futime_years" %in% names(d0)) d0$futime_years else d0$futime / 365.25
d0$event <- as.integer(d0$fustatus)
n_death <- sum(d0$event == 1)
n_alive <- sum(d0$event == 0)
n_inc <- nrow(d0)

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi) {
  hr <- as.numeric(hr)[1L]; lo <- as.numeric(lo)[1L]; hi <- as.numeric(hi)[1L]
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) ""
  else sprintf("%.3f (%.3f-%.3f)", hr, lo, hi)
}

panel <- list(
  letter = "A  MIMIC",
  top = "Hip arthroplasty with AKI\nin MIMIC-IV\n(n = 360)",
  mid = "Aged >= 65 years\n(n = 260)",
  inc = sprintf("Participants included\n(n = %s)", format(n_inc, big.mark = ",")),
  side1 = "Age < 65 years or\nmissing age (n = 100)",
  side2 = paste0(
    "1. SIRI or PIV not\ncomputable (n = 31)\n",
    "2. Missing 365-day follow-up\nor invalid exposure (n = 1)"
  ),
  death = sprintf("365-day all-cause death\n(n = %s)", format(n_death, big.mark = ",")),
  alive = sprintf("Alive at 365 days\n(n = %s)", format(n_alive, big.mark = ","))
)
fig1 <- file.path(
  .fig,
  "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI.pdf"
)
attrition_draw_outcome_figure(
  fig1, list(panel), width = 5.4, height = 6.35, family = "Times",
  csv_path = file.path(.tab, "Flowchart_attrition.csv")
)
message("Fig1 redrawn")

d4 <- d0
d4$ftime <- pmax(d4$hosp_day, 1 / 24)
d4$fstatus <- ifelse(d4$is_hosp_dead == 1L, 1L, 2L)
message("FG: hosp_death=", sum(d4$fstatus == 1), " discharged=", sum(d4$fstatus == 2))

for (idx in c("SIRI", "PIV")) {
  d4[[paste0(idx, "_z")]] <- as.numeric(scale(d4[[idx]]))
}

fg_rows <- list()
for (idx in c("SIRI", "PIV")) {
  zv <- paste0(idx, "_z")
  dd <- d4[is.finite(d4[[zv]]) & is.finite(d4$ftime) & d4$ftime > 0 & !is.na(d4$fstatus), ]
  dd$expo_z <- dd[[zv]]
  dd$Gender <- factor(dd$Gender)
  for (mod in c("Model1", "Model2", "Model3")) {
    mm <- if (mod == "Model1") {
      model.matrix(~ expo_z - 1, data = dd)
    } else if (mod == "Model2") {
      model.matrix(~ expo_z + Age + Gender - 1, data = dd)
    } else {
      model.matrix(~ expo_z + Age + Gender + Sodium + Potassium + CHARLSON + SOFA - 1, data = dd)
    }
    fit <- tryCatch(
      crr(ftime = dd$ftime, fstatus = dd$fstatus, cov1 = mm, failcode = 1, cencode = 0),
      error = function(e) {
        message(conditionMessage(e)); NULL
      }
    )
    if (is.null(fit)) next
    s <- summary(fit)
    hit <- which(rownames(s$coef) == "expo_z")[1L]
    if (is.na(hit)) hit <- 1L
    ci <- as.matrix(s$conf.int)
    co <- as.matrix(s$coef)
    pcol <- if ("p-value" %in% colnames(co)) "p-value" else colnames(co)[ncol(co)]
    fg_rows[[length(fg_rows) + 1L]] <- data.frame(
      Index = idx, Model = mod,
      SHR = as.numeric(ci[hit, 1]), lo = as.numeric(ci[hit, 3]),
      hi = as.numeric(ci[hit, 4]), p = as.numeric(co[hit, pcol]),
      stringsAsFactors = FALSE
    )
  }
}
fg <- do.call(rbind, fg_rows)
print(fg)
wide <- data.frame(Index = c("SIRI", "PIV"), Model1 = "", Model2 = "", Model3 = "",
                   stringsAsFactors = FALSE)
for (i in seq_len(nrow(fg))) {
  wide[wide$Index == fg$Index[i], fg$Model[i]] <-
    paste0(hr_cell(fg$SHR[i], fg$lo[i], fg$hi[i]), "; P=", fmt_p(fg$p[i]))
}
print(wide)

sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 4. Competing risk analysis of in-hospital death.xlsx"),
  title = "Table 4. Competing risk analysis of in-hospital death",
  df_body = wide,
  footnotes = c(
    "Fine-Gray subdistribution hazard model for in-hospital death.",
    "Competing event: live hospital discharge. Time scale: hospital length of stay (days).",
    "Primary endpoint remains 365-day all-cause mortality (Cox, Table 3); this table is secondary.",
    "Cause-specific cardiovascular death codes were unavailable in this MIMIC extract.",
    "Model 1 unadjusted (per 1-SD). Model 2: Age + Gender. Model 3: Age, Gender, Sodium, Potassium, CHARLSON, SOFA.",
    sprintf(
      "Events: in-hospital death n=%d; live discharge n=%d.",
      sum(d4$fstatus == 1), sum(d4$fstatus == 2)
    )
  )
)
message("Table 4 OK")

writeLines(c(
  "# Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI",
  "",
  "## 图面说明",
  "单库 MIMIC 纳排图，版式同预后 v2 参考项目。底部终点为 365 天全因死亡。",
  "",
  "图上标注：",
  "- 顶框：Hip arthroplasty with AKI in MIMIC-IV（n = 360）",
  "- 排除：Age < 65 or missing age（n = 100）",
  "- 中框：Aged >= 65 years（n = 260）",
  "- 排除：1. SIRI/PIV not computable（n = 31）；2. Missing 365-day follow-up or invalid exposure（n = 1）",
  "- 纳入：Participants included（n = 228）",
  "- 底部分叉：365-day all-cause death（n = 54）| Alive at 365 days（n = 174）",
  "",
  "## 分析上下文",
  "- 暴露: SIRI、PIV",
  "- 结局: 主分析=365 天全因死亡；Table 4=院内死亡（存活出院为竞争事件）",
  "- 样本量: N=228（365 天死亡 54，存活 174）",
  "- 数据库: MIMIC-IV（单库）",
  "- 是否拼图: 否"
), file.path(
  .out, "Figures/image_information",
  "Figure 1. Flow diagram of adults aged 65 years or older with hip arthroplasty and AKI.md"
))

pub_figure_ensure_formats(file.path(.out, "Figures"))
message("DONE")
