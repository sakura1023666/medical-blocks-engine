# tests/test_incidence_table12_export.R
# Table 1：离散数值暴露不得套 median/IQR；加权表失败时不得占主文坑。
# Table 2：dual_db 开启时仍须导出选中档或末档 fallback；闸门 NS 不能吞掉主表。
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/logistic_gate.R"), local = FALSE)
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"), local = FALSE)

# ── Table 1: 0/1/2/3 暴露转成分类，Age 保持连续 ─────────────────────────────
df <- data.frame(
  Age = c(40, 55, 70, 62, 48, 80),
  Periodontitis = c(0, 1, 2, 3, 0, 2),
  Disease_Group = factor(c(0, 1, 0, 1, 0, 1)),
  stringsAsFactors = FALSE
)
co <- pipeline_coerce_discrete_numeric(
  df, vars = c("Age", "Periodontitis"), threshold = 5L, outcome_col = "Disease_Group"
)
stopifnot(is.factor(co$data$Periodontitis))
stopifnot(is.numeric(co$data$Age))
stopifnot("Periodontitis" %in% co$discrete)
stopifnot("Age" %in% co$continuous)
stopifnot(!"Periodontitis" %in% pipeline_median_stat_vars(co$data, c("Age", "Periodontitis")))
stopifnot("Age" %in% pipeline_median_stat_vars(co$data, c("Age", "Periodontitis")))

# 加权 Table 1 失败时，不得靠 baseline_nhanes_done 把不加权表挤成附表
stopifnot(!isTRUE(pipeline_has_weighted_table1(list(baseline_nhanes_done = TRUE))))
stopifnot(isTRUE(pipeline_has_weighted_table1(list(nhanes_baseline_table = TRUE))))
stopifnot(isTRUE(pipeline_has_weighted_table1(list(table_1_nhanes_weighted = data.frame(x = 1)))))

# ── Table 2 skip：双库占位不得吞掉末档 fallback / 已选中主表 ─────────────────
ctx_empty <- list(
  results = list(),
  config = list(dual_db = list(enable = TRUE))
)
stopifnot(isTRUE(.lnw00_should_skip_table2_export(
  ctx_empty, ctx_empty$config, as_main = FALSE,
  caption = "Weighted logistic regression", family = "quartile"
)))
stopifnot(!isTRUE(.lnw00_should_skip_table2_export(
  ctx_empty, ctx_empty$config, as_main = FALSE,
  caption = "Weighted logistic regression", family = "binary"
)))
stopifnot(!isTRUE(.lnw00_should_skip_table2_export(
  ctx_empty, ctx_empty$config, as_main = TRUE,
  caption = "Weighted logistic regression", family = "quartile"
)))

ctx_has_main <- list(
  results = list(nhanes_logistic_exported_main = TRUE, logistic_table2_weighted = TRUE),
  config = list(dual_db = list(enable = TRUE))
)
stopifnot(isTRUE(.lnw00_should_skip_table2_export(
  ctx_has_main, ctx_has_main$config, as_main = FALSE,
  caption = "Weighted logistic regression", family = "tertile"
)))
stopifnot(!isTRUE(.lnw00_should_skip_table2_export(
  ctx_has_main, ctx_has_main$config, as_main = FALSE,
  caption = "Weighted logistic RCS cutoff", family = "tertile"
)))

# 末档 fallback：无 extend_* 时 binary 必须当主文 Table 2
stopifnot(isTRUE(.lnw00_weighted_export_as_main(
  list(results = list(logistic_branch = "degrade_binary")),
  family = "binary", is_rcs = FALSE, gate_enable = TRUE
)))
stopifnot(isTRUE(.lnw00_weighted_export_as_main(
  list(results = list(logistic_branch = NA_character_)),
  family = "binary", is_rcs = FALSE, gate_enable = TRUE
)))
stopifnot(!isTRUE(.lnw00_weighted_export_as_main(
  list(results = list(logistic_branch = "extend_quartile")),
  family = "binary", is_rcs = FALSE, gate_enable = TRUE
)))
stopifnot(isTRUE(.lnw00_weighted_export_as_main(
  list(results = list(logistic_branch = "extend_quartile")),
  family = "quartile", is_rcs = FALSE, gate_enable = TRUE
)))
stopifnot(!isTRUE(.lnw00_weighted_export_as_main(
  list(results = list(logistic_branch = "degrade_tertile")),
  family = "quartile", is_rcs = FALSE, gate_enable = TRUE
)))

# GLM 双库：quartile 降级不导出，binary 末档必须导出主表
ctx_glm <- list(
  results = list(logistic_branch = "degrade_binary"),
  config = list(dual_db = list(enable = TRUE))
)
stopifnot(!isTRUE(logistic_glm_export_as_main(ctx_glm, "quartile")))
stopifnot(isTRUE(logistic_glm_export_as_main(ctx_glm, "binary")))
stopifnot(isTRUE(logistic_glm_should_export(ctx_glm, "binary")))
stopifnot(!isTRUE(logistic_glm_should_export(ctx_glm, "quartile")))

# ── 离散暴露 factor 不得用内部编码 1–4 做分位（否则 Table 2 空壳）─────────────
x_fac <- factor(c(rep(0, 430), rep(1, 31), rep(2, 613), rep(3, 172)))
xn <- pipeline_index_as_numeric(x_fac)
stopifnot(is.numeric(xn), !is.factor(xn))
stopifnot(identical(as.numeric(xn[c(1L, 431L, 462L, 1075L)]), c(0, 1, 2, 3)))
stopifnot(!identical(as.numeric(x_fac)[1L], 0))  # factor 内部码是 1
q_lab <- as.numeric(stats::quantile(xn, 0.5, names = FALSE, na.rm = TRUE))
stopifnot(isTRUE(abs(q_lab - 2) < 1e-8))
grp <- ifelse(xn < q_lab, "Q1", "Q2")
stopifnot(all(grp %in% c("Q1", "Q2")), sum(grp == "Q1") == 461L, sum(grp == "Q2") == 785L)

# survey design：factor 暴露应被还原成 0–3，中位数切点为 2 而非编码 3
if (requireNamespace("survey", quietly = TRUE)) {
  set.seed(1)
  n <- length(x_fac)
  d0 <- data.frame(
    Periodontitis = x_fac,
    wt = 1,
    ids = seq_len(n),
    strata = 1L
  )
  des <- survey::svydesign(ids = ~ids, strata = ~strata, weights = ~wt, data = d0, nest = TRUE)
  des2 <- .lnw00_design_index_as_numeric(des, "Periodontitis")
  stopifnot(is.numeric(des2$variables$Periodontitis), !is.factor(des2$variables$Periodontitis))
  stopifnot(isTRUE(abs(median(des2$variables$Periodontitis) - 2) < 1e-8))
}

message("test_incidence_table12_export: OK")
