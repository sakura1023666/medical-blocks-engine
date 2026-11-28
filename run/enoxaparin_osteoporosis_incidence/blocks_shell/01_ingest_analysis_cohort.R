###############################################################################
# 01_ingest_analysis_cohort.R — 课题壳（非 Blocks 方法族）
# 将 derived/analysis_cohort.csv 规范为引擎约定 RData
#
# 用法（在引擎根或设 MEDICAL_BLOCKS_ROOT）:
#   Rscript run/enoxaparin_osteoporosis_incidence/blocks_shell/01_ingest_analysis_cohort.R \
#     --csv "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/derived/analysis_cohort.csv" \
#     --out "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/Data/Enoxaparin_OP.RData"
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
csv_path <- NULL
out_path <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--csv" && i < length(args)) {
    csv_path <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--out" && i < length(args)) {
    out_path <- args[[i + 1L]]; i <- i + 2L
  } else i <- i + 1L
}
if (is.null(csv_path) || !nzchar(csv_path)) {
  csv_path <- "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/derived/analysis_cohort.csv"
}
if (is.null(out_path) || !nzchar(out_path)) {
  out_path <- "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/AnalysisData/Enoxaparin_OP.RData"
}

csv_path <- normalizePath(csv_path, winslash = "/", mustWork = TRUE)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

df <- utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
n0 <- nrow(df)

# ── 列名规范化 ─────────────────────────────────────────────────────────────
rename_map <- c(
  age = "Age",
  sex = "Gender",
  bmi = "BMI",
  race_cat = "Race",
  dvt = "DVT",
  ckd = "CKD",
  malignancy = "Malignancy",
  glucocorticoid_systemic = "Glucocorticoid",
  subject_id = "ID"
)
for (nm in names(rename_map)) {
  if (nm %in% names(df) && !rename_map[[nm]] %in% names(df)) {
    names(df)[names(df) == nm] <- rename_map[[nm]]
  }
}

# 结局因子（参考组在前）
op <- as.integer(df[["osteoporosis"]])
df$Disease <- factor(
  ifelse(op == 1L, "Osteoporosis", "Non_Osteoporosis"),
  levels = c("Non_Osteoporosis", "Osteoporosis")
)

# 长期暴露标签（参考=非长期）
lt <- as.integer(df[["long_term_ge30"]])
df$long_term_label <- factor(
  ifelse(lt == 1L, "LongTerm", "Non_LongTerm"),
  levels = c("Non_LongTerm", "LongTerm")
)

# 固定四分位有序因子
q_levels <- c("Q1_<15", "Q2_15_30", "Q3_30_90", "Q4_>90")
df$duration_q <- factor(as.character(df$duration_q), levels = q_levels, ordered = TRUE)

# 0/1 临床协变量 → Yes/No 因子（Table1 友好）；数值副本留给回归
to_yn <- function(x) {
  x <- as.integer(x)
  factor(ifelse(x == 1L, "Yes", "No"), levels = c("No", "Yes"))
}
for (v in c("DVT", "CKD", "Malignancy", "Glucocorticoid")) {
  if (v %in% names(df)) {
    df[[paste0(v, "_num")]] <- as.integer(df[[v]] == "Yes" | df[[v]] == 1L | as.character(df[[v]]) == "1")
    if (is.numeric(df[[v]]) || all(as.character(df[[v]]) %in% c("0", "1", "0.0", "1.0"))) {
      df[[v]] <- to_yn(as.integer(df[[v]]))
    }
  }
}
# 若上面把字符 Yes/No 又处理了，保证 *_num 存在
for (v in c("DVT", "CKD", "Malignancy", "Glucocorticoid")) {
  if (v %in% names(df) && !paste0(v, "_num") %in% names(df)) {
    df[[paste0(v, "_num")]] <- as.integer(df[[v]] == "Yes")
  }
}

df$Gender <- factor(as.character(df$Gender), levels = c("Female", "Male"))
df$Race <- factor(as.character(df$Race), levels = c("White", "Black", "Asian", "Latino", "Other"))
df$Age <- as.numeric(df$Age)
df$BMI <- as.numeric(df$BMI)
df$exposure_days <- as.numeric(df$exposure_days)
df$exposure_days_per10 <- as.numeric(df$exposure_days_per10)
df$avg_admin_per_day <- as.numeric(df$avg_admin_per_day)
df$daily_avg_dose <- as.numeric(df$daily_avg_dose)
df$cum_dose_mg <- as.numeric(df$cum_dose_mg)
df$n_admin <- as.numeric(df$n_admin)

# SA 结局
if ("osteoporosis_sa7" %in% names(df)) {
  df$Disease_SA7 <- factor(
    ifelse(as.integer(df$osteoporosis_sa7) == 1L, "Osteoporosis", "Non_Osteoporosis"),
    levels = c("Non_Osteoporosis", "Osteoporosis")
  )
}

# Age_Group for subgroup
df$Age_Group <- factor(
  ifelse(df$Age >= 65, "Age>=65", "Age<65"),
  levels = c("Age<65", "Age>=65")
)
df$BMI_Group <- factor(
  ifelse(is.na(df$BMI), NA_character_,
         ifelse(df$BMI < 25, "BMI<25", "BMI>=25")),
  levels = c("BMI<25", "BMI>=25")
)

Enoxaparin_OP <- df
attr(Enoxaparin_OP, "ingest") <- list(
  source_csv = csv_path,
  n = nrow(Enoxaparin_OP),
  created = as.character(Sys.time())
)
save(Enoxaparin_OP, file = out_path)
message(sprintf(
  "[ingest] %s rows=%d -> %s",
  basename(csv_path), nrow(Enoxaparin_OP), out_path
))

# 列清单供审阅
review_txt <- file.path(dirname(out_path), "_column_review_raw.txt")
writeLines(names(Enoxaparin_OP), review_txt)
message("[ingest] wrote ", review_txt)
