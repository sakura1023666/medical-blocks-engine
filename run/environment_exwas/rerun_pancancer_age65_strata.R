#!/usr/bin/env Rscript
# 年龄分层切点 60 → 65：重跑 ExWAS 年龄分层 → Table S4 long + Fig3 年龄面板口径
# 随后请再跑：
#   Rscript run/environment_exwas/rebuild_pancancer_table_s4_dong_style.R
#   Rscript run/environment_exwas/redraw_pancancer_fig_s3_subgroup.R
#   （ERS 亚组）rebuild_pancancer_fig4_gcdnet.R 中年龄段部分，或本脚本末尾轻量重算 S15 年龄行
#
#   Rscript run/environment_exwas/rerun_pancancer_age65_strata.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L,
  age_cut = 65L
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
source(file.path(repo, "R/environment_exwas_core.R"))
source(file.path(repo, "R/environment_exwas_aligned.R"))
source(file.path(repo, "R/environment_exwas_toxicant.R"))

root <- opt$root
age_cut <- as.integer(opt$age_cut)
tab_dir <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
fig_dir <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Figures")
sum_fig <- file.path(root, "summary_results", "Figures")
exwas_log <- function(...) message("[exwas] ", paste0(..., collapse = ""))

built <- exwas_tox_build_cancer_table("pancancer", opt$data_dir, min_age = opt$min_age)
d0 <- built$data
d0 <- d0[is.finite(exwas_to_num(d0$URXUCR)) & exwas_to_num(d0$URXUCR) > 0, , drop = FALSE]
d0 <- d0[is.finite(exwas_to_num(d0$WTSA2YR)) & exwas_to_num(d0$WTSA2YR) > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
covars_full <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars_full)
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
df$Age_num <- exwas_to_num(df$Age)

fam_df <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(fam_df$Exposure, fam_df$Labels)
fam_map <- stats::setNames(fam_df$Family, fam_df$Labels)
disp_of <- function(raw) {
  x <- unname(lab_map[raw])
  ifelse(is.na(x) | !nzchar(x), raw, x)
}

lab_lt <- paste0("Age_lt", age_cut)
lab_ge <- paste0("Age_ge", age_cut)
idx_lt <- which(is.finite(df$Age_num) & df$Age_num < age_cut)
idx_ge <- which(is.finite(df$Age_num) & df$Age_num >= age_cut)
exwas_log(
  "age_cut=", age_cut,
  " <", age_cut, " N=", length(idx_lt), " events=", sum(df$DN[idx_lt] == 1, na.rm = TRUE),
  " | >=", age_cut, " N=", length(idx_ge), " events=", sum(df$DN[idx_ge] == 1, na.rm = TRUE)
)

run_stratum <- function(idx, name) {
  if (length(idx) < 100L) return(NULL)
  sub <- df[idx, , drop = FALSE]
  # 年龄层内仍保留连续 Age（与原 full_pub 口径一致）
  one <- exwas_run_unweighted(sub, "DN", scr$keep, covars_full)
  one$stratum <- name
  one$n_stratum <- nrow(sub)
  one$n_events <- sum(sub$DN == 1, na.rm = TRUE)
  one$exposure_name <- disp_of(sub("_(ln|bin)$", "", one$exposure))
  one$family <- unname(fam_map[sub("_(ln|bin)$", "", one$exposure)])
  one
}

exwas_log("跑 ", lab_lt, " …")
st_lt <- run_stratum(idx_lt, lab_lt)
exwas_log("跑 ", lab_ge, " …")
st_ge <- run_stratum(idx_ge, lab_ge)
st_age <- rbind(st_lt, st_ge)
if (is.null(st_age) || !nrow(st_age)) stop("年龄分层 ExWAS 失败")

dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
# 覆盖 S4 long；保留 60 版备份
bak60 <- file.path(tab_dir, "Table S4. ExWAS stratified by age_cut60.bak.csv")
old <- file.path(tab_dir, "Table S4. ExWAS stratified by age_long.bak.csv")
if (file.exists(old) && !file.exists(bak60)) file.copy(old, bak60)
utils::write.csv(st_age, file.path(tab_dir, "Table S4. ExWAS stratified by age_long.bak.csv"), row.names = FALSE)
utils::write.csv(st_age, file.path(tab_dir, "Table S4. ExWAS stratified by age.csv"), row.names = FALSE)
exwas_log("写 S4 long: ", nrow(st_age), " 行")

# 合并已有性别分层，重画 Fig3（若有）
s3_long <- file.path(tab_dir, "Table S3. ExWAS stratified by sex_long.bak.csv")
st_sex <- NULL
if (file.exists(s3_long)) {
  s3 <- utils::read.csv(s3_long, stringsAsFactors = FALSE, check.names = FALSE)
  st_sex <- s3[s3$stratum %in% c("Male", "Female"), , drop = FALSE]
}
st_all <- if (!is.null(st_sex) && nrow(st_sex)) rbind(st_sex, st_age) else st_age

# 展示层标签
st_all$stratum_lab <- as.character(st_all$stratum)
st_all$stratum_lab[st_all$stratum == lab_lt] <- paste0("<", age_cut)
st_all$stratum_lab[st_all$stratum == lab_ge] <- paste0("\u2265", age_cut)
st_all$stratum_lab <- factor(
  st_all$stratum_lab,
  levels = c("Male", "Female", paste0("<", age_cut), paste0("\u2265", age_cut))
)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  dir.create(file.path(fig_dir, "pdf"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(fig_dir, "image_information"), recursive = TRUE, showWarnings = FALSE)
  p3 <- ggplot2::ggplot(
    st_all,
    ggplot2::aes(
      x = log(pmax(OR, 1e-12)),
      y = -log10(pmax(p, 1e-300)),
      color = is.finite(q) & q < 0.05
    )
  ) +
    ggplot2::geom_point(alpha = 0.75, size = 1.5) +
    ggplot2::facet_wrap(~stratum_lab, nrow = 2) +
    ggplot2::scale_color_manual(values = c(`FALSE` = "grey60", `TRUE` = "#B2182B")) +
    ggplot2::theme_bw(base_size = 9, base_family = "serif") +
    ggplot2::labs(
      title = "Figure 3. Stratified ExWAS (sex and age)",
      subtitle = paste0("Age strata: <", age_cut, " / \u2265", age_cut, " years"),
      x = "log(OR per IQR)", y = expression(-log[10](p)), color = "q<0.05"
    )
  out_pdf <- file.path(fig_dir, "pdf", "Figure 3. Stratified ExWAS by sex and age.pdf")
  ggplot2::ggsave(out_pdf, p3, width = 9, height = 7)
  # sync summary_results if present
  sum_pdf_dir <- file.path(sum_fig, "pdf")
  if (dir.exists(sum_pdf_dir)) {
    file.copy(out_pdf, file.path(sum_pdf_dir, basename(out_pdf)), overwrite = TRUE)
  }
  md <- c(
    "# Figure 3. Stratified ExWAS by sex and age",
    "",
    "## 图面说明",
    paste0(
      "四面板：Male / Female / Age<", age_cut, " / Age\u2265", age_cut,
      "；红点表示层内 BH-FDR q<0.05。"
    ),
    "",
    "## 分析上下文",
    paste0(
      "年龄切点=", age_cut, "（癌症常用老年界值）；",
      " <", age_cut, " N=", length(idx_lt),
      "（事件 ", sum(df$DN[idx_lt] == 1, na.rm = TRUE), "）；",
      " \u2265", age_cut, " N=", length(idx_ge),
      "（事件 ", sum(df$DN[idx_ge] == 1, na.rm = TRUE), "）。"
    )
  )
  writeLines(md, file.path(fig_dir, "image_information", "Figure 3. Stratified ExWAS by sex and age.md"))
  if (dir.exists(file.path(sum_fig, "image_information"))) {
    writeLines(md, file.path(sum_fig, "image_information", "Figure 3. Stratified ExWAS by sex and age.md"))
  }
  exwas_log("Figure 3 已更新（年龄=", age_cut, "）")
}

exwas_log("DONE age", age_cut, " strata ExWAS")
