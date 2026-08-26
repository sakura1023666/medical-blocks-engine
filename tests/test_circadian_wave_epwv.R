# tests/test_circadian_wave_epwv.R
root <- "/mnt/e/01block/01Block-new-Final"
source(file.path(root, "R/cross_lagged_circadian_wave_epwv.R"))

# 公式：固定 Age/SBP/DBP 可复现
ep <- circadian_epwv_from_age_bp(60, 130, 80)
stopifnot(is.finite(ep), ep > 5, ep < 20)

# 药物 NA 不得把 C2 打成全 1
df <- data.frame(
  ID = c("a", "b", "c", "d"),
  rgender = c(1, 1, 2, 2),
  qm002 = c(95, 80, 85, 70),
  qa003 = c(140, 110, 135, 100),
  qa004 = c(90, 70, 88, 60),
  newtg = c(200, 80, NA, 90),
  newhdl = c(30, 55, 45, 60),
  newglu = c(120, 90, 95, 85),
  da049 = c(5, 8, 4, 7),
  CES_D10 = c(12, 3, 2, 1),
  da014s1 = c(NA, NA, NA, NA),
  da010_2_s1 = c(NA, NA, 1, NA),
  da011s1 = c(NA, NA, NA, NA),
  stringsAsFactors = FALSE
)
out <- circadian_rebuild_conditions(df, "CHARLS")
stopifnot(all(out$condition2 %in% c(0, 1, NA)))
stopifnot(any(out$condition2 == 0, na.rm = TRUE))
stopifnot(any(out$condition2 == 1, na.rm = TRUE))
stopifnot(any(out$condition4 == 0, na.rm = TRUE), any(out$condition4 == 1, na.rm = TRUE))

age_map <- c(a = 50, b = 55, c = 60, d = 65)
w1 <- circadian_wave_enrich(df, "CHARLS", 2011, 2011, age_map, age_offset = 0)
w2 <- df
w2$qa003 <- w2$qa003 + 10
w2 <- circadian_wave_enrich(w2, "CHARLS", 2015, 2011, age_map, age_offset = 4)
stopifnot(all(is.finite(w1$ePWV)), all(is.finite(w2$ePWV)))
stopifnot(!isTRUE(all.equal(w1$ePWV, w2$ePWV)))
# T2 年龄 = 基线 + 4
stopifnot(all.equal(w2$Age_wave, w1$Age_wave + 4))
cat("OK circadian_wave_epwv\n")
