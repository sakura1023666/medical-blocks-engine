#!/usr/bin/env Rscript
# Table S11 → 对齐 Dong Supplementary Table 11：
# Variables | Model 1 E-value (Lower limit of 95% CI) | Model 2 E-value (Lower limit of 95% CI)
# 行：ERS (Continuous)；ERS (Categorical) → Low=ref / High
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s11_dong_style.R
#
ROOT <- "/mnt/e/01block/01Block-new-Final"
BASE <- "/mnt/g/02block_result/58_cancer/environment_41380607"
source(file.path(ROOT, "R/utils.R"))
source(file.path(ROOT, "R/environment_exwas_aligned.R"))
if (file.exists(file.path(ROOT, "R/pub_xlsx_surgical.R"))) {
  source(file.path(ROOT, "R/pub_xlsx_surgical.R"))
}

src_tab <- file.path(BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
sum_tab <- file.path(BASE, "summary_results", "Tables")
dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)

ers_csv <- file.path(src_tab, "Table. ERS weighted logistic Model1 Model2.csv")
if (!file.exists(ers_csv)) {
  ers_csv <- file.path(
    BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "_downstream",
    "Table_ERS_logistic_weighted.csv"
  )
}
if (!file.exists(ers_csv)) stop("缺少 ERS logistic 表", call. = FALSE)
ers <- utils::read.csv(ers_csv, stringsAsFactors = FALSE, check.names = FALSE)

# Model2 协变量（脚注）
cov_note_path <- file.path(BASE, "summary_results", "Methods_covariate_and_ERS_alignment.md")
m2_covars <- c("Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR")
if (file.exists(cov_note_path)) {
  lines <- readLines(cov_note_path, warn = FALSE)
  hit <- grep("Model 2 final", lines, value = TRUE)
  if (length(hit)) {
    m <- regmatches(hit[[1]], regexec("Model 2 final\\*?:\\s*(.+)\\.?$", hit[[1]]))[[1]]
    if (length(m) >= 2L) {
      m2_covars <- trimws(unlist(strsplit(sub("\\.$", "", m[[2]]), ",\\s*")))
    }
  }
}
sel_path <- file.path(
  BASE, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "_downstream",
  "Model2_selection_path.txt"
)
if (file.exists(sel_path)) {
  lines <- readLines(sel_path, warn = FALSE)
  sw <- grep("^stepwise=", lines, value = TRUE)
  if (length(sw)) {
    m2_covars <- trimws(unlist(strsplit(sub("^stepwise=", "", sw[[1]]), ",\\s*")))
  }
}

.pick <- function(model_pat) {
  i <- grepl(model_pat, as.character(ers$model), ignore.case = TRUE)
  if (!any(i)) return(NULL)
  ers[which(i)[1], , drop = FALSE]
}
.fmt_ev_cell <- function(or, lo) {
  or <- as.numeric(or); lo <- as.numeric(lo)
  if (!is.finite(or) || !is.finite(lo) || or <= 0) return("")
  ev <- exwas_aligned_evalue_or(or, lo)
  # CI 含无效假设 → CI 侧 E-value = 1（VanderWeele）
  crosses_null <- (or >= 1 && lo <= 1) || (or <= 1 && lo >= 1)
  ci <- if (crosses_null) 1 else as.numeric(ev[["evalue_ci"]])
  sprintf("%.3f (%.3f)", as.numeric(ev[["evalue"]]), ci)
}

m1c <- .pick("Model1_continuous|^Model1$")
m2c <- .pick("Model2_continuous")
m1h <- .pick("Model1_High|High_vs_Low.*Model1|Model1.*High")
m2h <- .pick("Model2_High|Model2.*High")
# 宽松回退
if (is.null(m1c)) m1c <- .pick("Model1")
if (is.null(m2c)) {
  i <- grepl("Model2", ers$model, ignore.case = TRUE) &
    grepl("continuous|ERS_IQR", paste(ers$model, ers$exposure), ignore.case = TRUE)
  if (any(i)) m2c <- ers[which(i)[1], , drop = FALSE]
}
if (is.null(m1h)) {
  i <- grepl("Model1", ers$model, ignore.case = TRUE) &
    grepl("High|group", paste(ers$model, ers$exposure), ignore.case = TRUE)
  if (any(i)) m1h <- ers[which(i)[1], , drop = FALSE]
}
if (is.null(m2h)) {
  i <- grepl("Model2", ers$model, ignore.case = TRUE) &
    grepl("High|group", paste(ers$model, ers$exposure), ignore.case = TRUE)
  if (any(i)) m2h <- ers[which(i)[1], , drop = FALSE]
}

cell_m1c <- if (!is.null(m1c)) .fmt_ev_cell(m1c$OR[1], m1c$lo[1]) else ""
cell_m2c <- if (!is.null(m2c)) .fmt_ev_cell(m2c$OR[1], m2c$lo[1]) else ""
cell_m1h <- if (!is.null(m1h)) .fmt_ev_cell(m1h$OR[1], m1h$lo[1]) else ""
cell_m2h <- if (!is.null(m2h)) .fmt_ev_cell(m2h$OR[1], m2h$lo[1]) else ""

body <- data.frame(
  Variables = c(
    "ERS (Continuous)",
    "ERS (Categorical)",
    "Low",
    "High"
  ),
  c2 = c(cell_m1c, "", "ref", cell_m1h),
  c3 = c(cell_m2c, "", "ref", cell_m2h),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
names(body) <- c("Variables", "Model1", "Model2")

h1 <- c("Variables", "Model 1", "Model 2")
h2 <- c(
  "",
  "E-value (Lower limit of 95% CI)",
  "E-value (Lower limit of 95% CI)"
)

title <- paste0(
  "Table S11. E-values for the association between environmental risk score (ERS) and pan-cancer."
)
.disp_cov <- function(x) {
  x <- as.character(x)
  map <- c(
    Gender = "sex", Race = "race/ethnicity", PIR_cat = "poverty income ratio",
    Alcohol_drinking = "alcohol use", eGFR = "eGFR", Age = "age",
    Education = "education", Marital_Status = "marital status",
    BMI_cat = "BMI"
  )
  out <- ifelse(x %in% names(map), unname(map[x]), gsub("_", " ", x, fixed = TRUE))
  out
}
footnotes <- c(
  "Abbreviation: ERS, environmental risk score.",
  paste0(
    "Model 1 was unadjusted. Model 2 adjusted for ",
    paste(.disp_cov(m2_covars), collapse = ", "), "."
  ),
  "E-value = OR + sqrt(OR\u00d7(OR\u22121)) after converting OR<1 to 1/OR; parenthetical value is the E-value for the lower 95% CI limit (set to 1 if the CI includes the null).",
  "Continuous ERS uses per-IQR OR; categorical ERS compares High vs Low."
)

out_xlsx <- file.path(sum_tab, "Table S11. E-values for ERS association.xlsx")
# 数值备份（宽表）
num_out <- data.frame(
  Variables = c("ERS_Continuous", "ERS_High_vs_Low"),
  Model1_Evalue = c(
    if (!is.null(m1c)) exwas_aligned_evalue_or(m1c$OR[1], m1c$lo[1])[["evalue"]] else NA,
    if (!is.null(m1h)) exwas_aligned_evalue_or(m1h$OR[1], m1h$lo[1])[["evalue"]] else NA
  ),
  Model1_Evalue_CI = c(
    if (!is.null(m1c)) {
      ev <- exwas_aligned_evalue_or(m1c$OR[1], m1c$lo[1])
      if (m1c$OR[1] >= 1 && m1c$lo[1] <= 1) 1 else ev[["evalue_ci"]]
    } else NA,
    if (!is.null(m1h)) {
      ev <- exwas_aligned_evalue_or(m1h$OR[1], m1h$lo[1])
      if (m1h$OR[1] >= 1 && m1h$lo[1] <= 1) 1 else ev[["evalue_ci"]]
    } else NA
  ),
  Model2_Evalue = c(
    if (!is.null(m2c)) exwas_aligned_evalue_or(m2c$OR[1], m2c$lo[1])[["evalue"]] else NA,
    if (!is.null(m2h)) exwas_aligned_evalue_or(m2h$OR[1], m2h$lo[1])[["evalue"]] else NA
  ),
  Model2_Evalue_CI = c(
    if (!is.null(m2c)) {
      ev <- exwas_aligned_evalue_or(m2c$OR[1], m2c$lo[1])
      if (m2c$OR[1] >= 1 && m2c$lo[1] <= 1) 1 else ev[["evalue_ci"]]
    } else NA,
    if (!is.null(m2h)) {
      ev <- exwas_aligned_evalue_or(m2h$OR[1], m2h$lo[1])
      if (m2h$OR[1] >= 1 && m2h$lo[1] <= 1) 1 else ev[["evalue_ci"]]
    } else NA
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(num_out, file.path(src_tab, "Table S11. E-values for ERS association.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(Variables = body$Variables, Model1 = body$Model1, Model2 = body$Model2),
  file.path(src_tab, "Table S11. E-values Dong layout.csv"),
  row.names = FALSE
)

.sci_xlsx_double_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  h1 = h1,
  h2 = h2,
  sheet = "Table S11",
  footnotes = footnotes,
  col_widths = c(28, 32, 32),
  body_center_all = FALSE
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

# 缩进 Low/High
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  # title=1, h1=2, h2=3, body from 4: Continuous, Categorical, Low, High
  indent_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left", indent = 1L
  )
  cat_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left", textDecoration = "bold"
  )
  center <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman", halign = "center"
  )
  openxlsx::addStyle(wb, sh, cat_style, rows = 5, cols = 1, stack = TRUE) # Categorical header
  openxlsx::addStyle(wb, sh, indent_style, rows = 6:7, cols = 1, stack = TRUE)
  openxlsx::addStyle(wb, sh, center, rows = 4:7, cols = 2:3, gridExpand = TRUE, stack = TRUE)
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

message("[s11] M1 cont=", cell_m1c, " | M2 cont=", cell_m2c)
message("[s11] M1 high=", cell_m1h, " | M2 high=", cell_m2h)
message("[s11] wrote ", out_xlsx)
message("[s11] DONE")
