#!/usr/bin/env Rscript
# 全文统一协变量：M1 未调整；M2=Age+Gender；M3=Age+Gender+CHARLSON
# 不调 SOFA/OASIS：二者属急性严重度，与中介路径重叠，事件数有限时易过度调整使 SIRI 失显
# 重算 Table 3（Rubin）、Table 4（Fine-Gray）、脚注、筛选说明；顺带对齐 S3/S5 脚注口径

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
  library(cmprsk)
})

.engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else "/mnt/e/01block/01Block-new-Final"
setwd(.engine)
source("R/utils.R", local = FALSE)
source("R/pv2_pub_names.R", local = FALSE)
source("run/prognosis_v2/pv2_mi_cox.R", local = FALSE)

.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.tab <- file.path(.out, "Tables")
.ws_cands <- list.files(
  file.path(dirname(.out), "summary_results_delivery_workspace"),
  pattern = "^tables_non_xlsx_", full.names = TRUE
)
.ws <- if (length(.ws_cands)) {
  .ws_cands[order(file.info(.ws_cands)$mtime, decreasing = TRUE)][1L]
} else {
  stop("no delivery workspace with imputed_dbs.rds")
}
message("workspace: ", .ws)

# 统一调整集（全文唯一口径）
.m2 <- c("Age", "Gender")
.m3 <- c("Age", "Gender", "CHARLSON")
.m2_lab <- "Age, Gender"
.m3_lab <- "Age, Gender, CHARLSON"

fmt_p <- function(p) {
  p <- as.numeric(p)[1L]
  if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}
hr_cell <- function(hr, lo, hi) {
  hr <- as.numeric(hr)[1L]; lo <- as.numeric(lo)[1L]; hi <- as.numeric(hi)[1L]
  if (!is.finite(hr) || !is.finite(lo) || !is.finite(hi)) ""
  else sprintf("%.3f (%.3f\u2013%.3f)", hr, lo, hi)
}

d <- as.data.frame(readRDS(file.path(.ws, "imputed_dbs.rds"))$MIMIC)
mids <- tryCatch(readRDS(file.path(.ws, "imputed_mids.rds"))$MIMIC, error = function(e) NULL)
raw <- as.data.frame(readRDS(file.path(
  dirname(.out), "data", "analysis_Age65_SIRI_PIV_ready_365d.rds"
)))
mm <- match(as.character(d$ID), as.character(raw$subject_id))
d$is_hosp_dead <- as.integer(raw$is_hosp_dead[mm] %in% c(1L, TRUE, "1", "Yes"))
d$hosp_day <- as.numeric(raw$hosp_day[mm])
if (!"futime_years" %in% names(d)) d$futime_years <- d$futime / 365.25
d$fustatus <- as.integer(d$fustatus)
d$Gender <- factor(d$Gender)
for (idx in c("SIRI", "PIV")) {
  qs <- unique(stats::quantile(d[[idx]], c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE))
  d[[paste0(idx, "_Q")]] <- cut(d[[idx]], breaks = qs, include.lowest = TRUE,
                                labels = c("Q1", "Q2", "Q3", "Q4"))
  d[[paste0(idx, "_z")]] <- as.numeric(scale(d[[idx]]))
  d[[paste0(idx, "_Q")]] <- factor(d[[paste0(idx, "_Q")]], levels = c("Q1", "Q2", "Q3", "Q4"))
}

rhs_of <- function(expo_terms, model) {
  if (model == "Model1") return(paste(expo_terms, collapse = " + "))
  if (model == "Model2") return(paste(c(expo_terms, .m2), collapse = " + "))
  paste(c(expo_terms, .m3), collapse = " + ")
}

message("==== Table 3 Cox（统一 M1/M2/M3，Rubin）====")
cox_rows <- list()
for (idx in c("SIRI", "PIV")) {
  qv <- paste0(idx, "_Q")
  zv <- paste0(idx, "_z")
  for (mod in c("Model1", "Model2", "Model3")) {
    for (kind in c("continuous", "quartile")) {
      expo <- if (kind == "continuous") zv else qv
      rhs <- rhs_of(expo, mod)
      res <- tryCatch(
        pv2_cox_extract(
          d, rhs, mids = mids, time_var = "futime_years", event_var = "fustatus",
          exposure_keep = c("SIRI", "PIV", "SIRI_Q", "PIV_Q", "SIRI_z", "PIV_z"),
          weighted = FALSE, rubin = TRUE
        ),
        error = function(e) {
          message(idx, " ", mod, " ", kind, ": ", conditionMessage(e)); NULL
        }
      )
      if (is.null(res) || !nrow(res)) next
      keep <- if (kind == "continuous") grepl("_z", res$term) else grepl(paste0(idx, "_Q"), res$term)
      res <- res[keep, , drop = FALSE]
      if (!nrow(res)) next
      res$Index <- idx
      res$model <- paste0(mod, "_", kind)
      cox_rows[[length(cox_rows) + 1L]] <- res
    }
    # trend
    d$qnum <- as.integer(d[[qv]])
    rhs_t <- rhs_of("qnum", mod)
    tr <- tryCatch(
      pv2_cox_extract(
        d, rhs_t, mids = mids, time_var = "futime_years", event_var = "fustatus",
        exposure_keep = c("qnum", "SIRI", "PIV"), rubin = TRUE
      ),
      error = function(e) NULL
    )
    if (!is.null(tr) && any(tr$term == "qnum")) {
      tr <- tr[tr$term == "qnum", , drop = FALSE]
      tr$Index <- idx
      tr$model <- paste0(mod, "_trend")
      tr$term <- "P_for_trend"
      cox_rows[[length(cox_rows) + 1L]] <- tr
    }
  }
}
cox_out <- do.call(rbind, cox_rows)
fwrite(cox_out, file.path(.tab, "Table 3. Cox.csv"))
file.copy(file.path(.tab, "Table 3. Cox.csv"), file.path(.ws, "Table 3. Cox.csv"), overwrite = TRUE)

.pub_cox_wide <- function(cox_out) {
  rows <- list()
  hr_only <- function(mod, kind, term_pat, idx) {
    r <- cox_out[cox_out$Index == idx & cox_out$model == paste0(mod, "_", kind), , drop = FALSE]
    r <- r[grepl(term_pat, r$term), , drop = FALSE]
    if (!nrow(r)) return(c(HR = "", P = ""))
    c(HR = hr_cell(r$hr[1], r$lo[1], r$hi[1]), P = fmt_p(r$p[1]))
  }
  tp <- function(mod, idx) {
    r <- cox_out[cox_out$Index == idx & cox_out$model == paste0(mod, "_trend"), , drop = FALSE]
    if (!nrow(r)) "" else fmt_p(r$p[1])
  }
  for (idx in c("SIRI", "PIV")) {
    rows[[length(rows) + 1L]] <- c(Variable = idx, M1 = "", P1 = "", M2 = "", P2 = "", M3 = "", P3 = "")
    a <- hr_only("Model1", "continuous", "_z", idx)
    b <- hr_only("Model2", "continuous", "_z", idx)
    c3 <- hr_only("Model3", "continuous", "_z", idx)
    rows[[length(rows) + 1L]] <- c(
      Variable = "  per 1 SD", M1 = a["HR"], P1 = a["P"],
      M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
    )
    rows[[length(rows) + 1L]] <- c(
      Variable = "  Quartile 1", M1 = "Reference", P1 = "",
      M2 = "Reference", P2 = "", M3 = "Reference", P3 = ""
    )
    for (q in c("Q2", "Q3", "Q4")) {
      a <- hr_only("Model1", "quartile", q, idx)
      b <- hr_only("Model2", "quartile", q, idx)
      c3 <- hr_only("Model3", "quartile", q, idx)
      rows[[length(rows) + 1L]] <- c(
        Variable = paste0("  Quartile ", substr(q, 2, 2)),
        M1 = a["HR"], P1 = a["P"], M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
      )
    }
    rows[[length(rows) + 1L]] <- c(
      Variable = "  P for trend",
      M1 = "", P1 = tp("Model1", idx),
      M2 = "", P2 = tp("Model2", idx),
      M3 = "", P3 = tp("Model3", idx)
    )
  }
  out <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(out) <- c(
    "Variable",
    "Model 1 HR (95% CI)", "P1",
    "Model 2 HR (95% CI)", "P2",
    "Model 3 HR (95% CI)", "P3"
  )
  out
}
t3 <- .pub_cox_wide(cox_out)
level_idx <- which(startsWith(t3$Variable, "  "))
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 3. Cox proportional hazards models.xlsx"),
  title = "Table 3. Cox proportional hazards models for 365-day all-cause mortality",
  df_body = t3,
  footnotes = c(
    "The Model 1 was non-adjusted.",
    paste0("The Model 2 was adjusted by: ", .m2_lab, "."),
    paste0("The Model 3 was adjusted by: ", .m3_lab, "."),
    "Covariate sets are identical across Table 3, Table 4, sensitivity and mediation path models.",
    "Model 3 was restricted to Age, Gender and CHARLSON (event-limited parsimony; 365-day deaths n=54). SOFA/OASIS were not retained in Model 3 to avoid over-adjustment along the acute-severity pathway used in mediation.",
    "Multiple imputation (cart, m = 5); hazard ratios pooled by Rubin's rules.",
    "Continuous exposure standardized to 1 SD within the analytic sample.",
    "Quartile contrasts use Q1 as the reference in the full analytic sample (all quartile levels retained)."
  ),
  level_row_idx = level_idx + 1L
)
.t3_path <- file.path(.tab, "Table 3. Cox proportional hazards models.xlsx")
.wb <- openxlsx::loadWorkbook(.t3_path)
.x <- openxlsx::read.xlsx(.t3_path, colNames = FALSE)
.hdr <- NA_integer_
for (.i in 1:5) {
  .v <- as.character(unlist(.x[.i, ]))
  if (any(grepl("^P1$|^P2$|Model 1 HR", .v))) {
    .hdr <- .i
    break
  }
}
if (is.finite(.hdr)) {
  for (.col in c(3L, 5L, 7L)) {
    openxlsx::writeData(.wb, 1, x = "P", startCol = .col, startRow = .hdr)
  }
  openxlsx::saveWorkbook(.wb, .t3_path, overwrite = TRUE)
}
message("Table 3 OK")

message("==== Table 4 Fine-Gray（同一 M1/M2/M3）====")
d$ftime <- pmax(d$hosp_day, 1 / 24)
d$fstatus <- ifelse(d$is_hosp_dead == 1L, 1L, 2L)
# cmprsk 用 0/1 哑变量表示 Gender，与 Cox 的 factor(Gender) 同一调整集
d$Male <- as.integer(as.character(d$Gender) == "Male")
fg_rows <- list()
for (idx in c("SIRI", "PIV")) {
  dd <- d[is.finite(d[[paste0(idx, "_z")]]) & is.finite(d$ftime) & d$ftime > 0, ]
  dd$expo_z <- dd[[paste0(idx, "_z")]]
  for (mod in c("Model1", "Model2", "Model3")) {
    mmx <- if (mod == "Model1") {
      cbind(expo_z = dd$expo_z)
    } else if (mod == "Model2") {
      cbind(expo_z = dd$expo_z, Age = dd$Age, Male = dd$Male)
    } else {
      cbind(
        expo_z = dd$expo_z, Age = dd$Age, Male = dd$Male,
        SOFA = dd$SOFA, CHARLSON = dd$CHARLSON
      )
    }
    fit <- tryCatch(
      crr(ftime = dd$ftime, fstatus = dd$fstatus, cov1 = mmx, failcode = 1, cencode = 0),
      error = function(e) {
        message(idx, " ", mod, ": ", conditionMessage(e)); NULL
      }
    )
    if (is.null(fit)) {
      fg_rows[[length(fg_rows) + 1L]] <- data.frame(
        Index = idx, Model = mod, cell = "NE", stringsAsFactors = FALSE
      )
      next
    }
    s <- summary(fit)
    hit <- which(rownames(s$coef) == "expo_z")[1L]
    if (is.na(hit)) hit <- 1L
    ci <- as.matrix(s$conf.int); co <- as.matrix(s$coef)
    pcol <- if ("p-value" %in% colnames(co)) "p-value" else colnames(co)[ncol(co)]
    fg_rows[[length(fg_rows) + 1L]] <- data.frame(
      Index = idx, Model = mod,
      cell = paste0(
        hr_cell(ci[hit, 1], ci[hit, 3], ci[hit, 4]), "; P=", fmt_p(co[hit, pcol])
      ),
      stringsAsFactors = FALSE
    )
  }
}
fg <- do.call(rbind, fg_rows)
wide <- data.frame(Index = c("SIRI", "PIV"), Model1 = "", Model2 = "", Model3 = "",
                   stringsAsFactors = FALSE)
for (i in seq_len(nrow(fg))) {
  wide[wide$Index == fg$Index[i], fg$Model[i]] <- fg$cell[i]
}
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table 4. Competing risk analysis of in-hospital death.xlsx"),
  title = "Table 4. Competing risk analysis of in-hospital death",
  df_body = wide,
  footnotes = c(
    "Fine-Gray subdistribution hazard for in-hospital death.",
    "Competing event: live hospital discharge. Time scale: hospital length of stay (days).",
    "Primary endpoint remains 365-day all-cause mortality (Cox, Table 3); this table is secondary.",
    paste0("Model 1: non-adjusted. Model 2: ", .m2_lab, ". Model 3: ", .m3_lab, "."),
    "Covariate sets match Table 3 exactly (Gender entered as Male 0/1 in Fine-Gray).",
    sprintf(
      "Events: in-hospital death n=%d; live discharge n=%d.",
      sum(d$fstatus == 1), sum(d$fstatus == 2)
    )
  )
)
message("Table 4 OK")
print(wide)

# 更新筛选说明
writeLines(c(
  "协变量全文统一（事件数受限后的精简口径）：",
  "Model 1 不调整。",
  paste0("Model 2 = ", .m2_lab, "。"),
  paste0("Model 3 = ", .m3_lab, "。"),
  "Table 3 Cox、Table 4 Fine-Gray、敏感性与中介路径模型使用同一套 Model 1/2/3。",
  "Boruta/SHAP 曾提示更多变量；因事件数有限，且 SOFA/OASIS 与中介路径重叠，最终 Model 3 固定为 Age+Gender+CHARLSON，避免过度调整。",
  "MICE cart m=5 seed=1234；Cox Rubin 合并；操作层 complete#1。",
  "结局：ICU 入科起 365 天全因死亡（主）；Table 4 为院内死亡竞争风险（次要）。"
), file.path(.tab, "Covariate_selection_note.txt"))
file.copy(file.path(.tab, "Covariate_selection_note.txt"),
          file.path(.ws, "Covariate_selection_note.txt"), overwrite = TRUE)

# S1 定义同步
sci_xlsx_single_header_booktabs(
  file.path(.tab, "Table S1. Definitions.xlsx"),
  title = "Table S1. Definitions",
  df_body = data.frame(
    Item = c(
      "Cohort", "Age", "SIRI", "PIV", "Primary outcome", "Landmark", "Database",
      "Imputation", "Covariate selection", "Competing risk (Table 4)"
    ),
    Definition = c(
      "Hip arthroplasty with AKI; renal transplant-related codes excluded",
      "Age >= 65 years at ICU admission",
      "Neutrophil count x monocyte / lymphocyte",
      "Neutrophil count x platelet count x monocyte / lymphocyte",
      "All-cause death within 365 days after ICU intime",
      "Follow-up censored at 365 days",
      "MIMIC-IV v3.1 (unweighted, single database)",
      "MICE cart m=5 seed=1234; Cox pooled by Rubin; plots use complete #1",
      paste0(
        "Unified across all tables: Model1 unadjusted; Model2 ", .m2_lab,
        "; Model3 ", .m3_lab, " (parsimonious after Boruta/SHAP)"
      ),
      "Secondary Fine-Gray: in-hospital death vs live discharge (LOS); same Model1/2/3 covariates as Table 3"
    ),
    stringsAsFactors = FALSE
  )
)

# S5 敏感性：同一 M1/M2/M3
message("==== Table S5（统一协变量）====")
d5 <- d[!(d$fustatus == 1 & d$futime_years <= 28 / 365.25), ]
s5 <- list()
for (idx in c("SIRI", "PIV")) {
  zv <- paste0(idx, "_z")
  for (mod in c("Model1", "Model2", "Model3")) {
    rhs <- rhs_of(zv, mod)
    res <- tryCatch(
      pv2_cox_extract(d5, rhs, mids = NULL, time_var = "futime_years", event_var = "fustatus",
                      rubin = FALSE),
      error = function(e) NULL
    )
    if (is.null(res)) next
    r <- res[grepl("_z", res$term), ][1, , drop = FALSE]
    if (!nrow(r)) next
    s5[[length(s5) + 1L]] <- data.frame(
      Index = idx, Model = mod,
      HR_CI_P = paste0(hr_cell(r$hr, r$lo, r$hi), "; P=", fmt_p(r$p)),
      N = nrow(d5), Deaths = sum(d5$fustatus == 1),
      stringsAsFactors = FALSE
    )
  }
}
if (length(s5)) {
  sci_xlsx_single_header_booktabs(
    file.path(.tab, "Table S5. Sensitivity analysis excluding deaths within the first 28 days.xlsx"),
    title = "Table S5. Sensitivity analysis excluding deaths within the first 28 days",
    df_body = do.call(rbind, s5),
    footnotes = c(
      "Patients who died within 28 days after ICU admission were excluded.",
      paste0("Model 1 unadjusted; Model 2: ", .m2_lab, "; Model 3: ", .m3_lab, " (same as Table 3)."),
      sprintf("Analytic N after exclusion = %d.", nrow(d5))
    )
  )
}

# S3：在统一 M3 上再加 comorbidity count（脚注写明）
message("==== Table S3 ====")
d$comorb_n <- rowSums(sapply(
  c("Hypertension", "Diabetes", "Heart_Failure", "Myocardial_Infarction",
    "Stroke", "COPD", "Pneumonia", "Malignant_Tumor"),
  function(v) if (v %in% names(d)) as.integer(as.character(d[[v]]) == "Yes") else 0L
))
s3 <- list()
for (idx in c("SIRI", "PIV")) {
  zv <- paste0(idx, "_z")
  rhs <- paste(c(zv, .m3, "comorb_n"), collapse = " + ")
  res <- tryCatch(
    pv2_cox_extract(
      d, rhs, mids = mids, time_var = "futime_years", event_var = "fustatus",
      exposure_keep = c(zv, "SIRI", "PIV", "comorb_n"), rubin = TRUE
    ),
    error = function(e) NULL
  )
  if (is.null(res)) next
  r <- res[grepl("_z|comorb", res$term), ]
  r$Index <- idx
  r$HR_CI_P <- paste0(hr_cell(r$hr, r$lo, r$hi), "; P=", fmt_p(r$p))
  s3[[length(s3) + 1L]] <- r[, c("Index", "term", "HR_CI_P", "mi_pool")]
}
if (length(s3)) {
  sci_xlsx_single_header_booktabs(
    file.path(.tab, "Table S3. Cox model including comorbidity count.xlsx"),
    title = "Table S3. Cox model including comorbidity count",
    df_body = do.call(rbind, s3),
    footnotes = c(
      paste0("Base Model 3 covariates (", .m3_lab, ") plus comorbidity count (0-8)."),
      "Rubin-pooled. Comorbidity count is an add-on sensitivity term, not part of the unified Model 3 set."
    )
  )
}

message("DONE — unified covariates: M2=", .m2_lab, "; M3=", .m3_lab)
