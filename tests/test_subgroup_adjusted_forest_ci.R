# tests/test_subgroup_adjusted_forest_ci.R
# 回归：调整版亚组 res（jstable 同构：标题行 + "  level" 缩进行）
# 经 subgroup_prepare_forest_plot_df 后，OR (95% CI) 文本列必须有数值；
# 扁平行 "Var: level"（旧 bug）会被当标题行 → CI 列全空（白内障 TyG_WWI 踩过）。
root <- normalizePath(".")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}
source(file.path(root, "R/subgroup_forest_plot.R"), local = FALSE)

res <- data.frame(
  Variable = c(
    "Age Group", "  < 65", "  \u2265 65",
    "Gender", "  Female", "  Male"
  ),
  Count = c(NA, 2883, 2690, NA, 2790, 2783),
  Percent = c(NA, 51.7, 48.3, NA, 50.1, 49.9),
  `Point Estimate` = c(NA, 1.97, 1.39, NA, 1.22, 1.56),
  Lower = c(NA, 1.16, 1.08, NA, 0.87, 1.09),
  Upper = c(NA, 3.33, 1.79, NA, 1.71, 2.22),
  `P value` = c("", "0.012", "0.012", "", "0.247", "0.014"),
  `P for interaction` = c("0.185", "", "", "0.557", "", ""),
  check.names = FALSE, stringsAsFactors = FALSE
)

pdf_df <- subgroup_prepare_forest_plot_df(res, effect_sym = "OR")
ci_lab <- "OR (95% CI)"
stopifnot(ci_lab %in% names(pdf_df))
lvl_rows <- grepl("^\\s+", as.character(pdf_df$Variable))
ci_vals <- as.character(pdf_df[[ci_lab]])[lvl_rows]
stopifnot(all(nzchar(ci_vals)), all(grepl("[0-9]\\.[0-9]+ \\(", ci_vals)))
stopifnot(grepl("1\\.97", ci_vals[1]))
# 标题行 CI 必须为空、点估计为 NA
hdr_rows <- !lvl_rows
stopifnot(all(!nzchar(trimws(as.character(pdf_df[[ci_lab]][hdr_rows])))))
stopifnot(all(is.na(pdf_df$"Point Estimate"[hdr_rows])))

# merge_levels_into_variable 不得吃掉缩进
df2 <- data.frame(
  Variable = c("Age Group", "  < 65", "  \u2265 65"),
  Levels = c("", "x=Q1", ""),
  check.names = FALSE, stringsAsFactors = FALSE
)
m <- subgroup_merge_levels_into_variable(df2)
stopifnot(grepl("^  < 65$", m$Variable[2]), grepl("^  \u2265 65$", m$Variable[3]))

cat("test_subgroup_adjusted_forest_ci: OK\n")
