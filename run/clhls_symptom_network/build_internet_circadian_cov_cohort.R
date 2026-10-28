# Formal entry: rebuild covariate-complete network cohort (N=8061).
# One-off root tmp_build_cov_cohort.R archived into this path 2026-10-21.

# ── 协变量版队列构建 ──────────────────────────────────────────────────────
# 网络队列(9,504, 仅 ID/sex/age/dev*/circ*) + CHARLS2015 baseline 人口学
# 协变量口径（用户 2026-10-16 定）：Age + Education + Marital_Status，完整病例。
# 泄漏铁律：BMI/腰围/血压/血糖/TG/HDL/CESD/睡眠/疾病flag 均为结局组分原料，禁入。
# 输出直接写正式 data/；若 SMB 卡顿可先写本地再 cp。

net_csv  <- "G:/02block_result/23_circadian rhythm/Complex_network/Internet diversity/data/CHARLS_2015_internet_circadian_network.csv"
base_rda <- "G:/02block_result/23_circadian rhythm/cross_laged_shehui/data/charls/D01_baseline_CHARLS_2015_0813.RData"

nodes <- c("dev1","dev2","dev3","dev4","circ1","circ2","circ3","circ4","circ5","circ6","circ7")

x <- read.csv(net_csv, stringsAsFactors = FALSE, colClasses = c(ID = "character"))
cat("网络队列行:", nrow(x), "\n")

e <- new.env(); load(base_rda, envir = e)
b <- get(ls(e)[1], envir = e)
norm <- function(s) sprintf("%012.0f", suppressWarnings(as.numeric(s)))
b$IDn <- norm(b$ID); x$IDn <- norm(x$ID)

want <- c("Education", "Marital_Status")
want <- intersect(want, names(b))
bt  <- unique(b[, c("IDn", want), drop = FALSE])
# 只取每个 ID 一行（unique 已按 IDn+值去重；若同 ID 多行取首个）
bt  <- bt[!duplicated(bt$IDn), ]

m <- merge(x, bt, by = "IDn", all.x = TRUE)
cat("匹配到协变量:", sum(!is.na(m$Education)), "/", nrow(m), "\n")

# 统一编码：Education -> edu (0/1), Marital -> marr (0/1)，保留数值 age/sex
m$edu   <- ifelse(m$Education == "Above High school", 1, ifelse(m$Education == "Below High school", 0, NA_real_))
m$marr  <- ifelse(m$Marital_Status == "Married", 1, ifelse(m$Marital_Status == "Unmarried", 0, NA_real_))
m$age_n <- suppressWarnings(as.numeric(m$age))
m$sex_n <- suppressWarnings(as.numeric(m$sex))

cc <- stats::complete.cases(m[, c("age_n","sex_n","edu","marr")],
                            m[, nodes])
cat("完整病例 N =", sum(cc), "\n")
cat("  男:", sum(m$sex_n[cc] == 1), " 女:", sum(m$sex_n[cc] == 2), "\n")
cat("  教育 Above HS:", sum(m$edu[cc] == 1), " 已婚:", sum(m$marr[cc] == 1), "\n")

out <- m[cc, c("ID","sex","age", nodes, "edu","marr"), drop = FALSE]
out$dev5 <- NULL  # 若存在（本次 nodes 已不含 dev5）
local_csv <- "G:/02block_result/23_circadian rhythm/Complex_network/Internet diversity cov/data/CHARLS_2015_internet_circadian_network_cov8061.csv"
utils::write.csv(out, local_csv, row.names = FALSE)
cat("已写本地:", local_csv, " rows:", nrow(out), "\n")
