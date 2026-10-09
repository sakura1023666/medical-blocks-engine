# 冒烟：trajectory_parse_uv_hr_cell 优先 p= 单元格，不抓 median(IQR)
source("R/trajectory_dual_pub_harmonize.R", local = FALSE)

tmp <- tempfile(fileext = ".xlsx")
on.exit(unlink(tmp), add = TRUE)

df <- data.frame(
  V1 = c("Table S3. UV", "Variable", "WPR", "Age"),
  V2 = c(NA, "HR", "1.23 (0.9-1.5)", "1.01 (1.00-1.02)"),
  V3 = c(NA, "desc", "0.50 (0.20-0.80)", NA),  # median IQR 诱饵
  V4 = c(NA, "P", "1.50 (1.10-2.00) p=0.012", "0.04"),
  stringsAsFactors = FALSE
)
openxlsx::write.xlsx(df, tmp, colNames = FALSE)

hr <- trajectory_parse_uv_hr_cell(tmp, "WPR")
stopifnot(!is.null(hr))
stopifnot(abs(hr$hr - 1.5) < 1e-9)
stopifnot(grepl("p\\s*=", hr$cell, ignore.case = TRUE))

# 无 p= 时回退到最后一个 a (b-c) 风格单元格
df2 <- df
df2$V4 <- c(NA, "P", NA, "0.04")
tmp2 <- tempfile(fileext = ".xlsx")
on.exit(unlink(tmp2), add = TRUE)
openxlsx::write.xlsx(df2, tmp2, colNames = FALSE)
hr2 <- trajectory_parse_uv_hr_cell(tmp2, "WPR")
stopifnot(!is.null(hr2))
# 同行多个 ( ) 时取最后一个含数字括号的 → 可能是 median；无 p= 时行为有文档约定
# 此处至少应解析出有限 HR
stopifnot(is.finite(hr2$hr), hr2$hr > 0)

cat("OK trajectory_parse_uv_hr_cell\n")
