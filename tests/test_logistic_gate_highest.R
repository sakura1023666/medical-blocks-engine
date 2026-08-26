# Table2 闸门：仅最高暴露组显著即可锁定；degrade_* 不得锁 scheme
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/logistic_gate.R"), local = FALSE)

stopifnot(is.na(logistic_gate_scheme_from_branch("degrade_tertile")))
stopifnot(is.na(logistic_gate_scheme_from_branch("degrade_binary")))
stopifnot(identical(logistic_gate_scheme_from_branch("extend_quartile"), "quartile"))
stopifnot(identical(logistic_gate_scheme_from_branch("extend_tertile"), "tertile"))

lv <- c("Q1", "Q2", "Q3", "Q4")
# 中间档显著、最高组不显著 → 不得过闸
stopifnot(!isTRUE(logistic_gate_highest_sig(
  c(Q2 = 0.01, Q3 = 0.20, Q4 = 0.06), lv, 0.05
)))
# 仅最高组显著 → 过闸
stopifnot(isTRUE(logistic_gate_highest_sig(
  c(Q2 = 0.40, Q3 = 0.30, Q4 = 0.03), lv, 0.05
)))

# apply_after_table：Crude 最高组显著 + Model2 最高组显著 → extend
tb <- as.data.frame(matrix("", 6L, 12L), stringsAsFactors = FALSE)
tb[3, 1] <- "Q2"; tb[3, 6] <- "0.40"; tb[3, 12] <- "0.50"
tb[4, 1] <- "Q3"; tb[4, 6] <- "0.30"; tb[4, 12] <- "0.40"
tb[5, 1] <- "Q4"; tb[5, 6] <- "0.02"; tb[5, 12] <- "0.01"
ctx <- list(results = list())
bl <- list(
  gate_enable = TRUE, phase = "screen", p_threshold = 0.05,
  extend_branch = "extend_quartile", degrade_branch = "degrade_tertile"
)
ctx2 <- logistic_gate_apply_after_table(ctx, bl, tb, lv, "logistic_quartile_glm")
stopifnot(identical(ctx2$results$logistic_branch, "extend_quartile"))
stopifnot(identical(ctx2$results$nhanes_logistic_selected_scheme, "quartile"))
stopifnot(isTRUE(ctx2$results$logistic_gate_detail$crude_high_sig))

# Crude 最高组 NS → degrade，且不得写入 selected_scheme=quartile
tb[5, 6] <- "0.06"
ctx3 <- logistic_gate_apply_after_table(list(results = list()), bl, tb, lv, "logistic_quartile_glm")
stopifnot(identical(ctx3$results$logistic_branch, "degrade_tertile"))
stopifnot(!nzchar(as.character(ctx3$results$nhanes_logistic_selected_scheme %||% "")[1L]))

cat("test_logistic_gate_highest OK\n")
