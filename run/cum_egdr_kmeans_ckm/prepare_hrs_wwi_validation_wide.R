###############################################################################
# HRS 2012→2016→2018 · WWI 外验宽表（发现=ELSA WWI 固定中心）
# T0=2012 暴露波1，T1=2016 风险起点，T2=2018 新发骨质疏松结局
# WWI = Waist_circumference / sqrt(Weight)；cum ×4 年（2012→2016）
###############################################################################

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !(length(a) == 1L && is.na(a))) a else b

data_dir <- "/mnt/g/02block_result/10_osteoporosis/cum_egdr_kmeans_41654871/data"
out_dir  <- data_dir
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

load_bl <- function(f) {
  e <- new.env(parent = emptyenv())
  load(file.path(data_dir, f), envir = e)
  e$baseline
}

ops <- function(f) {
  d <- utils::read.csv(file.path(data_dir, f), stringsAsFactors = FALSE, check.names = FALSE)
  id <- if ("hhidpn" %in% names(d)) d$hhidpn else if ("idauniq" %in% names(d)) d$idauniq else d[[1L]]
  data.frame(ID = as.character(id), DN = as.integer(d$DN), stringsAsFactors = FALSE)
}

to_htn01 <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  ifelse(xc %in% c("1", "yes", "y", "true"), 1,
    ifelse(xc %in% c("0", "no", "n", "false"), 0, NA_real_))
}

yn_factor <- function(x) {
  v <- to_htn01(x)
  # Smoke: Never→No；Current/Former/Ever→Yes
  xc <- tolower(trimws(as.character(x)))
  if (any(xc %in% c("never", "current", "former", "ever"), na.rm = TRUE)) {
    return(factor(
      ifelse(xc %in% c("never", "no", "n", "0"), "No",
        ifelse(is.na(xc) | xc == "", NA_character_, "Yes")),
      levels = c("No", "Yes")
    ))
  }
  factor(ifelse(v == 1, "Yes", ifelse(v == 0, "No", NA_character_)), levels = c("No", "Yes"))
}

B12 <- load_bl("D01_baseline_HRS_2012_0813.RData"); B12$ID <- as.character(B12$ID)
B16 <- load_bl("D01_baseline_HRS_2016_0813.RData"); B16$ID <- as.character(B16$ID)
op16 <- ops("osteoporosis_HRS_2016.csv")
op18 <- ops("osteoporosis_HRS_2018.csv")

wwi_of <- function(df) {
  WC <- as.numeric(df$Waist_circumference)
  Wt <- as.numeric(df$Weight)
  WC / sqrt(Wt)
}

i12 <- data.frame(ID = B12$ID, WWI_t1 = wwi_of(B12), BMI_t1 = as.numeric(B12$BMI),
                  stringsAsFactors = FALSE)
i16 <- data.frame(ID = B16$ID, WWI_t2 = wwi_of(B16), BMI_t2 = as.numeric(B16$BMI),
                  stringsAsFactors = FALSE)

# 协变量取风险起点 T1=2016
cov_keep <- c(
  "Age", "Gender", "Education", "Marital_Status", "Smoke", "Alcohol_drinking",
  "BMI", "Waist_circumference", "Weight", "Height", "Hypertension", "Diabetes",
  "Malignant_Tumor", "HbA1c", "TC", "HDL", "NBPS", "NBPD"
)
cov_keep <- intersect(cov_keep, names(B16))
cov1 <- B16[, c("ID", cov_keep), drop = FALSE]

# 2012 组分（主暴露波）
comp12 <- B12[, intersect(c("ID", "Waist_circumference", "Weight", "BMI", "Hypertension", "HbA1c", "TC", "HDL"),
                          names(B12)), drop = FALSE]
names(comp12)[-1] <- paste0(names(comp12)[-1], "_w2012")

# N0 = 2012 baseline（年龄过滤在 ingest；此处保留全库便于 attrition）
d <- data.frame(ID = B12$ID, stringsAsFactors = FALSE)
d <- merge(d, i12, by = "ID", all.x = TRUE)
d <- merge(d, i16, by = "ID", all.x = TRUE)
d <- merge(d, cov1, by = "ID", all.x = TRUE)
d <- merge(d, comp12, by = "ID", all.x = TRUE)
d <- merge(d, op16, by = "ID", all.x = TRUE)
names(d)[names(d) == "DN"] <- "DN1"
d <- merge(d, op18, by = "ID", all.x = TRUE)
names(d)[names(d) == "DN"] <- "DN2"

d$Osteoporosis <- as.integer(d$DN2 == 1L)
d$in_2016 <- as.integer(d$ID %in% B16$ID)
d$free_t1 <- !is.na(d$DN1) & d$DN1 == 0L
d$fu_ok <- d$in_2016 == 1L & d$free_t1 & !is.na(d$DN2)

# 标准协变量名
d$Marital <- d$Marital_Status
d$Drink <- d$Alcohol_drinking
g <- tolower(as.character(d$Gender))
d$Gender <- factor(
  ifelse(g %in% c("male", "m", "1"), "Male",
    ifelse(g %in% c("female", "f", "2"), "Female", NA_character_)),
  levels = c("Male", "Female")
)
for (bc in c("Smoke", "Drink", "Diabetes", "Hypertension", "Malignant_Tumor")) {
  if (bc %in% names(d)) d[[bc]] <- yn_factor(d[[bc]])
}
if ("Marital" %in% names(d)) {
  m <- tolower(as.character(d$Marital))
  d$Marital <- factor(
    ifelse(grepl("married|partner", m), "Married",
      ifelse(is.na(m) | m == "", NA_character_, "Other")),
    levels = c("Married", "Other")
  )
}
# Education 对齐 ELSA：Below High school / High school and above
if ("Education" %in% names(d)) {
  ed <- as.character(d$Education)
  d$Education <- factor(
    ifelse(grepl("below", ed, ignore.case = TRUE), "Below High school",
      ifelse(is.na(ed) | ed == "", NA_character_, "High school and above")),
    levels = c("Below High school", "High school and above")
  )
}
# HRS 无 TG：Dyslipidemia = HDL<40 或 TC≥240
hdl <- as.numeric(d$HDL); tc <- as.numeric(d$TC)
d$Dyslipidemia <- factor(
  ifelse(is.na(hdl) & is.na(tc), NA_character_,
    ifelse((!is.na(hdl) & hdl < 40) | (!is.na(tc) & tc >= 240), "Yes", "No")),
  levels = c("No", "Yes")
)

mult <- 4
d$cum_WWI <- (as.numeric(d$WWI_t1) + as.numeric(d$WWI_t2)) / 2 * mult
d$cum_BMI <- (as.numeric(d$BMI_t1) + as.numeric(d$BMI_t2)) / 2 * mult
d$Hypertension_w4 <- d$Hypertension  # ingest 别名兼容
d$futime <- 4
d$status <- d$Osteoporosis
d$iwy1 <- 2012L
d$iwy4 <- 2018L
d$Stroke <- d$Osteoporosis

# attrition：E1=缺 2016；E2=2016 已有/缺失 OP；E3=缺 2018 OP；E4=双波 WWI 不全
# Age≥50 在 ingest 落实，不进 E 标志（与 ELSA 一致：N0 标签写 Age≥50）
d$ex_E1 <- as.integer(d$in_2016 != 1L)
d$ex_E2 <- as.integer(d$in_2016 == 1L & (is.na(d$DN1) | d$DN1 == 1L))
d$ex_E3 <- as.integer(d$free_t1 & d$in_2016 == 1L & is.na(d$DN2))
d$ex_E4 <- as.integer(
  d$fu_ok & !(is.finite(d$WWI_t1) & is.finite(d$WWI_t2))
)
d$cohort_final <- as.integer(
  d$fu_ok & is.finite(d$WWI_t1) & is.finite(d$WWI_t2)
)

wide_path <- file.path(out_dir, "hrs_cum_kmeans_wwi_analysis_wide.csv")
utils::write.csv(d, wide_path, row.names = FALSE, fileEncoding = "UTF-8")

# attrition：N0 = 2012 Age≥50（不用 2016 Age，否则缺访被提前踢出 N0）
age12 <- as.numeric(B12$Age[match(d$ID, B12$ID)])
d$Age_2012 <- age12
# ingest 的 Age 仍为风险起点 2016；另存 Age_2012 仅供 attrition
att <- data.frame(
  ID = d$ID,
  ex_E1 = d$ex_E1, ex_E2 = d$ex_E2, ex_E3 = d$ex_E3, ex_E4 = d$ex_E4,
  cohort_final = d$cohort_final,
  Age_2012 = age12,
  stringsAsFactors = FALSE
)
att50 <- att[!is.na(att$Age_2012) & att$Age_2012 >= 50, , drop = FALSE]
att_path <- file.path(out_dir, "hrs_wwi_attrition_pool.csv")
utils::write.csv(att50[, setdiff(names(att50), "Age_2012"), drop = FALSE],
                 att_path, row.names = FALSE, fileEncoding = "UTF-8")

cat("Wrote", wide_path, "n=", nrow(d),
    " cohort_final=", sum(d$cohort_final, na.rm = TRUE),
    " events=", sum(d$Osteoporosis[d$cohort_final == 1L] == 1L, na.rm = TRUE), "\n")
cat("Attrition Age2012>=50 N0=", nrow(att50),
    " final=", sum(att50$cohort_final, na.rm = TRUE), "\n")
cat("After E stepwise (Age2012>=50):\n")
keep <- rep(TRUE, nrow(att50))
n0 <- sum(keep)
e1 <- att50$ex_E1 == 1L; n1 <- sum(keep & !e1); keep[e1] <- FALSE
e2 <- att50$ex_E2 == 1L; n2 <- sum(keep & !e2); keep[e2] <- FALSE
e3 <- att50$ex_E3 == 1L; n3 <- sum(keep & !e3); keep[e3] <- FALSE
e4 <- att50$ex_E4 == 1L; n4 <- sum(keep & !e4)
cat("  N0=", n0, " afterE1=", n1, " afterE2=", n2, " afterE3=", n3, " afterE4=", n4, "\n")

# ---- 从 ELSA 发现队列导出 WWI 语义类中心（固定外验） ----
source("/mnt/e/01block/01Block-new-Final/R/literature_ckm_cum_egdr.R")
ck_path <- file.path(
  "/mnt/g/02block_result/10_osteoporosis/cum_egdr_kmeans_41654871/by_unit",
  "\u3010success\u3011WWI", "checkpoints", "table1_by_class_ckm.rds"
)
if (!file.exists(ck_path)) {
  # fallback: 从宽表 + 同 seed 重拟
  ew <- utils::read.csv(file.path(data_dir, "elsa_cum_kmeans_analysis_wide.csv"),
                        stringsAsFactors = FALSE, check.names = FALSE)
  ew <- ew[is.finite(ew$WWI_t1) & is.finite(ew$WWI_t2) &
             as.integer(ew$cohort_final %||% 1L) == 1L, , drop = FALSE]
  # ELSA 纳排 ID
  ew <- ew[as.character(ew$ID) != "119705", , drop = FALSE]
  mat <- cbind(as.numeric(ew$WWI_t1), as.numeric(ew$WWI_t2))
  fit <- ckm_stroke_kmeans_fit(mat, k = 4L, seed = 2026L, nstart = 25L)
  cls <- ckm_stroke_anchor_classes(fit$cluster, mat[, 1], mat[, 2])
  cen <- ckm_stroke_centers_by_semantic(fit$centers, fit$cluster, cls)
} else {
  ck <- readRDS(ck_path)
  dd <- ck$ctx$data$cleaned
  mat <- cbind(as.numeric(dd$eGDR_t1), as.numeric(dd$eGDR_t2))
  fit <- ckm_stroke_kmeans_fit(mat, k = 4L, seed = 2026L, nstart = 25L)
  cls <- ckm_stroke_anchor_classes(fit$cluster, mat[, 1], mat[, 2])
  # 优先用 checkpoint 已有语义（应与重拟一致或极近）
  if ("eGDR_Class" %in% names(dd)) {
    # 用重拟 centers，但按与 checkpoint 类的多数票映射；否则直接用重拟锚定
    cen <- ckm_stroke_centers_by_semantic(fit$centers, fit$cluster, cls)
  } else {
    cen <- ckm_stroke_centers_by_semantic(fit$centers, fit$cluster, cls)
  }
  cat("ELSA checkpoint n=", nrow(dd), " refit nclass=",
      paste(names(table(cls)), as.integer(table(cls)), collapse = ", "), "\n")
  if ("eGDR_Class" %in% names(dd)) {
    cat("ELSA checkpoint nclass=",
        paste(names(table(dd$eGDR_Class)), as.integer(table(dd$eGDR_Class)), collapse = ", "), "\n")
  }
}

cen_path <- file.path(out_dir, "elsa_wwi_kmeans_semantic_centers.csv")
utils::write.csv(
  data.frame(class = rownames(cen), t1 = cen[, 1], t2 = cen[, 2], stringsAsFactors = FALSE),
  cen_path, row.names = FALSE, fileEncoding = "UTF-8"
)
cat("Wrote centers", cen_path, "\n")
print(cen)
