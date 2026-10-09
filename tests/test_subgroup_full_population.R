# tests/test_subgroup_full_population.R
# 亚组森林图「全部人群」铁律：
#   1) 分位跟随主文锁定方案（subgroup_resolve_main_scheme）
#   2) 中间分位并为 Middle（subgroup_collapse_middle_levels）——不删任何行
#   3) jstable 多水平输出折叠成每层一行「最高 vs 最低」（subgroup_fold_quantile_contrast_rows）
#      且该行的 OR/HR 等于全分位模型最高层系数、Count = 该层全量 n
root <- normalizePath(".")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}
source(file.path(root, "R/subgroup_forest_plot.R"), local = FALSE)

# ── scheme resolver ─────────────────────────────────────────────────────────
stopifnot(identical(
  subgroup_resolve_main_scheme(list(results = list(logistic_grouping_scheme = "tertile")), list()),
  "tertile"
))
stopifnot(identical(
  subgroup_resolve_main_scheme(list(results = list(dual_db_logistic_unified_scheme = "quartile")), list()),
  "quartile"
))
stopifnot(identical(
  subgroup_resolve_main_scheme(list(results = list()), list(logistic_tertile_glm = list(enable = TRUE))),
  "tertile"
))
stopifnot(identical(
  subgroup_resolve_main_scheme(list(results = list()), list(), default = "tertile"),
  "tertile"
))

# ── collapse middle ─────────────────────────────────────────────────────────
x <- factor(c("Q1","Q2","Q3","Q4","Q2","Q4"), levels = c("Q1","Q2","Q3","Q4"))
y <- subgroup_collapse_middle_levels(x)
stopifnot(identical(levels(y), c("Q1","Middle","Q4")))
stopifnot(identical(as.character(y), c("Q1","Middle","Middle","Q4","Middle","Q4")))
stopifnot(length(y) == length(x))  # 不删行
# 二水平原样返回
x2 <- factor(c("T1","T3","T1"), levels = c("T1","T3"))
stopifnot(identical(levels(subgroup_collapse_middle_levels(x2)), c("T1","T3")))

# ── fold quantile contrast rows (GLM) ─────────────────────────────────────────
if (requireNamespace("jstable", quietly = TRUE)) {
  suppressPackageStartupMessages(library(jstable))
  set.seed(11); n <- 3000
  d <- data.frame(
    x = factor(sample(c("Q1","Middle","Q4"), n, TRUE), levels = c("Q1","Middle","Q4")),
    ageg = factor(sample(c("< 45","g45"), n, TRUE)),
    race = factor(sample(c("W","B","O"), n, TRUE))
  )
  d$y <- rbinom(n, 1, plogis(-1.5 + 0.4 * as.numeric(d$x) + 0.3 * (d$ageg == "< 45")))
  r <- TableSubgroupMultiGLM(y ~ x, var_subgroups = c("ageg", "race"),
                             data = d, family = "binomial")
  io <- which(names(r) == "OR"); names(r)[io] <- "Point Estimate"
  r[["Point Estimate"]] <- suppressWarnings(as.numeric(as.character(r[["Point Estimate"]])))
  folded <- subgroup_fold_quantile_contrast_rows(r, "x", "Q4")
  # 折叠后无 Levels 列（保缩进）、行数 = 1 Overall + (1 标题 + 层数)×变量
  stopifnot(!("Levels" %in% names(folded)))
  v <- trimws(as.character(folded$Variable))
  # 每层恰好一行、Count = 该层全量 n
  n_lt45 <- sum(d$ageg == "< 45")
  fv <- trimws(as.character(folded$Variable))
  row_lt <- folded[fv == "< 45", , drop = FALSE]
  stopifnot(nrow(row_lt) == 1L)
  stopifnot(identical(as.integer(row_lt$Count[1L]), as.integer(n_lt45)))

  # 折叠的 Q4-vs-Q1 OR 必须等于全人群 4 层模型里 Q4 的 OR（哑变量嵌套性质）。
  # 用 stateful scan 定位「当前 stratum」，避免依赖 jstable 前导空格数。
  d4 <- d
  mid <- which(d4$x == "Middle")
  d4$x4 <- factor(ifelse(seq_len(nrow(d4)) %in% mid,
                         sample(c("Q2","Q3"), length(mid), TRUE),
                         as.character(d4$x)),
                 levels = c("Q1","Q2","Q3","Q4"))
  r4 <- TableSubgroupMultiGLM(y ~ x4, var_subgroups = "ageg", data = d4, family = "binomial")
  cur_blk <- NA_character_
  q4_or <- NA_real_
  for (i in seq_len(nrow(r4))) {
    vv <- trimws(as.character(r4$Variable[i]))
    if (nzchar(vv)) cur_blk <- vv
    if (!is.na(r4$Levels[i]) && trimws(as.character(r4$Levels[i])) == "x4=Q4" &&
        identical(cur_blk, "< 45")) {
      q4_or <- suppressWarnings(as.numeric(as.character(r4$OR[i]))[1L])
      break
    }
  }
  fold_or <- suppressWarnings(as.numeric(row_lt$`Point Estimate`[1L]))
  stopifnot(is.finite(q4_or), is.finite(fold_or))
  stopifnot(abs(log(q4_or) - log(fold_or)) < 0.02)  # 同值（允许格式化舍入）

  cat("test_subgroup_full_population.R: OK\n")
} else {
  cat("test_subgroup_full_population.R: SKIPPED (no jstable)\n")
}
