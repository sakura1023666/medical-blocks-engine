#!/usr/bin/env Rscript
# scripts/prep_osteo_dxa_qct_personalized.R
# Osteoporosis DXA/QCT personalized study: GBK CSV → harmonized dabiao
#
# Usage:
#   Rscript scripts/prep_osteo_dxa_qct_personalized.R
#   OSTEO_PERSONALIZED_ROOT=/path/to/study Rscript scripts/prep_osteo_dxa_qct_personalized.R

args <- commandArgs(trailingOnly = TRUE)
STUDY <- Sys.getenv(
  "OSTEO_PERSONALIZED_ROOT",
  unset = "/mnt/g/02block_result/10_osteoporosis/personalized"
)
if ("--study-root" %in% args) {
  i <- match("--study-root", args)
  STUDY <- args[[i + 1L]]
}

raw <- file.path(STUDY, "data", "研究数据_完整版(数据整理)(1).csv")
stopifnot(file.exists(raw))

df <- utils::read.csv(
  raw,
  fileEncoding = "GBK",
  check.names = FALSE,
  stringsAsFactors = FALSE
)
raw_n <- nrow(df)
stopifnot(raw_n == 208L)

column_map <- data.frame(
  standard_name = c(
    "SampleID",
    "Age",
    "QCT_vBMD",
    "QCT_cat",
    "DXA_T_min",
    "DXA_cat_min",
    "DXA_T_lumbar",
    "DXA_cat_lumbar",
    "Vertebral_fracture",
    "SBP",
    "DBP",
    "FPG",
    "BMI",
    "TG",
    "CHO",
    "HDL_C",
    "LDL_C",
    "Hb",
    "Ca",
    "P",
    "UA",
    "CCr",
    "VitD_25OH",
    "P1NP",
    "bCTX",
    "PTH",
    "ALP",
    "Calcitonin",
    "Osteocalcin",
    "Nathan",
    "AAC"
  ),
  source_column = c(
    "SampleID",
    "Age",
    "QCT-vBMD(mg/cm3)",
    "QCT category（0正常1骨量减少2骨质疏松）",
    "DXA T-score腰椎或髋部取最低",
    "DXA category腰椎或髋部取最低（0正常1骨量减少2骨质疏松）",
    "腰椎DXA T-score",
    "腰椎DXA category（0正常1骨量减少2骨质疏松）",
    "Vertebral compression fracture（0无压缩性骨折1有压缩性骨折）",
    "SBP（收缩压mmHg）",
    "DBP（舒张压mmHg）",
    "FPG(mmol/L)空腹血糖",
    "BMI(kg/m2)",
    "Triglyceride(TG)（(mmol/L)）",
    "Total cholesterol （ CHO）(mmol/L)",
    "High-density lipoprotein cholesterol （HDL-C）(mmol/L)",
    "Low-density lipoprotein cholesterol （LDL-C）(mmol/L)",
    "Hemoglobin（g/L）",
    "Serum ionized calcium(mmol/L)",
    "Serum phosphorus(mmol/L)",
    "Serum uric acid(umol/L)",
    "Creatinine clearance（ml/min）",
    "25‐hydroxyvitamin D（ng/mL）",
    "P1NP（ng/mL）",
    "β-CTx（ng/mL）",
    "Parathyroid hormone（PTH）（ng/mL）",
    "Alkaline phosphatase（ug/L）",
    "Calcitonin（pg/ml）",
    "Osteocalcin(ng/L)",
    "Nathan Osteophyte Grading（0无改变1微小骨赘2水平骨赘3鸟嘴状骨赘4骨桥形成）",
    "abdominal aortic calcification（AAC）（0无1有）"
  ),
  stringsAsFactors = FALSE
)

missing_src <- setdiff(column_map$source_column, names(df))
if (length(missing_src) > 0L) {
  stop(
    "源 CSV 缺少列: ",
    paste(missing_src, collapse = ", ")
  )
}

dabiao <- setNames(
  lapply(column_map$source_column, function(col) df[[col]]),
  column_map$standard_name
)
dabiao <- as.data.frame(dabiao, stringsAsFactors = FALSE)

dabiao$SampleID <- as.character(dabiao$SampleID)
dabiao$Age <- as.numeric(dabiao$Age)
dabiao$BMI <- as.numeric(dabiao$BMI)
dabiao$QCT_vBMD <- as.numeric(dabiao$QCT_vBMD)
dabiao$DXA_T_min <- as.numeric(dabiao$DXA_T_min)
dabiao$DXA_T_lumbar <- as.numeric(dabiao$DXA_T_lumbar)

int_cols <- c(
  "QCT_cat",
  "DXA_cat_min",
  "DXA_cat_lumbar",
  "Vertebral_fracture",
  "Nathan",
  "AAC"
)
for (col in int_cols) {
  dabiao[[col]] <- as.integer(dabiao[[col]])
}

num_cols <- c(
  "SBP", "DBP", "FPG", "TG", "CHO", "HDL_C", "LDL_C", "Hb", "Ca", "P",
  "UA", "CCr", "VitD_25OH", "P1NP", "bCTX", "PTH", "ALP", "Calcitonin",
  "Osteocalcin"
)
for (col in num_cols) {
  dabiao[[col]] <- as.numeric(dabiao[[col]])
}

dabiao$QCT_OP <- as.integer(dabiao$QCT_cat == 2L)
dabiao$DXA_OP <- as.integer(dabiao$DXA_cat_min == 2L)
dabiao$need_QCT <- as.integer(dabiao$QCT_OP == 1L & dabiao$DXA_OP == 0L)
dabiao$discordance_group <- ifelse(
  dabiao$QCT_OP == 1L & dabiao$DXA_OP == 1L,
  "Both_OP",
  ifelse(
    dabiao$QCT_OP == 1L & dabiao$DXA_OP == 0L,
    "QCT_only_OP",
    ifelse(
      dabiao$QCT_OP == 0L & dabiao$DXA_OP == 1L,
      "DXA_only_OP",
      "Neither_OP"
    )
  )
)
dabiao$Nathan_bin <- ifelse(dabiao$Nathan %in% c(3L, 4L), "3-4", "1-2")
dabiao$BMI_bin <- ifelse(dabiao$BMI >= 24, ">=24", "<24")
dabiao$Age_bin <- ifelse(dabiao$Age >= 65, ">=65", "<65")
dabiao$Fracture_f <- factor(
  ifelse(dabiao$Vertebral_fracture == 1L, "Fracture", "No_Fracture"),
  levels = c("No_Fracture", "Fracture")
)
dabiao$Disease <- factor(
  ifelse(dabiao$Vertebral_fracture == 1L, "Fracture", "No_Fracture"),
  levels = c("No_Fracture", "Fracture")
)

stopifnot(nrow(dabiao) == 208L)
stopifnot(sum(dabiao$need_QCT) == 40L)
stopifnot(sum(dabiao$Vertebral_fracture) == 85L)

out_dir <- file.path(STUDY, "data", "harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

utils::write.csv(column_map, file.path(out_dir, "column_map.csv"), row.names = FALSE)

attrition <- data.frame(
  step = "raw_csv → analytic",
  n_in = raw_n,
  n_out = nrow(dabiao),
  n_excluded = 0L,
  note = "analytic_n=208; no row exclusions in prep",
  stringsAsFactors = FALSE
)
utils::write.csv(attrition, file.path(out_dir, "attrition_prep.csv"), row.names = FALSE)

save(dabiao, file = file.path(out_dir, "D01_osteo_personalized.RData"))

message(sprintf(
  "n=%d, fracture=%d, need_QCT=%d",
  nrow(dabiao),
  sum(dabiao$Vertebral_fracture),
  sum(dabiao$need_QCT)
))
message("Wrote: ", file.path(out_dir, "D01_osteo_personalized.RData"))
