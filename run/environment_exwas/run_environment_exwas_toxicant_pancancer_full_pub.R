#!/usr/bin/env Rscript
# 泛癌毒物 ExWAS 全套发表（对齐 Dong 2026 EWAS-new 主文+补充图表清单）
# 前置：已完成 UCR+WTSA full ExWAS 筛查目录（--screen-dir）
# 本脚本：跑下游(B=1000) + 补齐 Table1/Fig1–5/S1–S12（癌种迁移：去口腔三项；结局=泛癌）
#
# 用法:
#   Rscript run_environment_exwas_toxicant_pancancer_full_pub.R \
#     --screen-dir <Output_pancancer_..._UCR_WTSA> \
#     --out <Output_pancancer_..._full_pub> \
#     [--bootstrap 1000] [--wqs-boot 1000] [--skip-downstream]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  screen_dir = NULL, out = NULL,
  bootstrap = 1000L, wqs_boot = 1000L,
  skip_downstream = FALSE, min_age = 20L
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--screen-dir" && i < length(args)) { opt$screen_dir <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--bootstrap" && i < length(args)) { opt$bootstrap <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--wqs-boot" && i < length(args)) { opt$wqs_boot <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--min-age" && i < length(args)) { opt$min_age <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--skip-downstream") { opt$skip_downstream <- TRUE; i <- i + 1L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$screen_dir) || is.null(opt$out)) stop("需要 --screen-dir 与 --out", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))
source(file.path(root, "R/environment_exwas_toxicant.R"))
source(file.path(root, "R/environment_exwas_toxicant_downstream.R"))

to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8)) else p
}
data_dir <- to_host_path("/mnt/g/02block_result/51_gastric cancer/environment_41380607/data")
screen_dir <- to_host_path(opt$screen_dir)
out <- to_host_path(opt$out)
exwas_ensure_dir(out)
fig_dir <- file.path(out, "Figures"); tab_dir <- file.path(out, "Tables")
exwas_ensure_dir(fig_dir); exwas_ensure_dir(tab_dir)
exwas_ensure_dir(file.path(fig_dir, "pdf"))
exwas_ensure_dir(file.path(fig_dir, "image_information"))

.copy_if <- function(src, dest) {
  if (file.exists(src)) {
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(src, dest, overwrite = TRUE)
    TRUE
  } else FALSE
}
.write_md <- function(path, title, face, ctx) {
  writeLines(c(
    paste0("# ", title),
    "",
    "## 图面说明",
    face,
    "",
    "## 分析上下文",
    ctx
  ), path)
}

exwas_log("==== pancancer full pub ====")
exwas_log("screen=", screen_dir)
exwas_log("out=", out)

# ---------- 0) 下游 ERS/WQS/中介（原文 B=1000）----------
down_dir <- file.path(out, "_downstream")
hits_csv <- file.path(screen_dir, "Table_2b_ExWAS_FDR_hits.csv")
if (!file.exists(hits_csv)) stop("缺少命中表: ", hits_csv, call. = FALSE)
if (!isTRUE(opt$skip_downstream)) {
  exwas_ensure_dir(down_dir)
  cmd <- paste(
    "Rscript", shQuote(file.path(root, "run/environment_exwas/run_environment_exwas_toxicant_downstream.R")),
    "--disease pancancer",
    "--min-age", as.integer(opt$min_age),
    "--covars-set full",
    "--no-smoke",
    "--require-urine-creat",
    "--require-weight WTSA2YR",
    "--hits-csv", shQuote(hits_csv),
    "--bootstrap", as.integer(opt$bootstrap),
    "--wqs-boot", as.integer(opt$wqs_boot),
    "--out", shQuote(down_dir)
  )
  exwas_log("启动下游: B=", opt$bootstrap, " WQS b=", opt$wqs_boot)
  st <- system(cmd)
  if (!identical(as.integer(st), 0L)) stop("下游失败 status=", st, call. = FALSE)
} else {
  exwas_log("跳过下游（--skip-downstream），读已有 ", down_dir)
}

# ---------- 1) 重建分析队列（与筛查同口径）----------
built <- exwas_tox_build_cancer_table("pancancer", data_dir, min_age = opt$min_age)
d0 <- built$data
ucr0 <- exwas_to_num(d0$URXUCR)
d0 <- d0[is.finite(ucr0) & ucr0 > 0, , drop = FALSE]
ww0 <- exwas_to_num(d0$WTSA2YR)
d0 <- d0[is.finite(ww0) & ww0 > 0, , drop = FALSE]
tox <- intersect(built$tox_cols, names(d0))
d1 <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")$data
scr <- exwas_tox_screen_transform(d1, tox)
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
df <- exwas_tox_merge_inflam(df, data_dir)
# Platelet for SII if present on baseline merge leftovers
if (!"SII" %in% names(df) || all(is.na(df$SII))) {
  if ("PlateletCount" %in% names(df) || "Platelet" %in% names(df)) {
    neu <- exwas_to_num(df$NEUT); lym <- exwas_to_num(df$Lymphocytes)
    plt <- if ("PlateletCount" %in% names(df)) exwas_to_num(df$PlateletCount) else exwas_to_num(df$Platelet)
    df$SII <- ifelse(is.finite(neu) & is.finite(plt) & is.finite(lym) & lym > 0, neu * plt / lym, NA_real_)
  }
}
df$SDMVSTRA_cyc <- as.integer(
  interaction(as.character(df$cycle), exwas_to_num(df$SDMVSTRA), drop = TRUE, lex.order = TRUE)
)
covars_full <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars_full)
lab_map <- stats::setNames(built$code$Exposure, built$code$Labels)
fam_map <- stats::setNames(built$code$Family, built$code$Labels)
disp_of <- function(raw) {
  ifelse(is.na(lab_map[raw]), raw, unname(lab_map[raw]))
}

# ---------- Table 1 基线（按 DN）----------
exwas_log("Table 1")
t1_vars <- c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat",
             "BMI_cat", "Alcohol_drinking", "Smoke", "eGFR")
t1_vars <- intersect(t1_vars, names(df))
rows_t1 <- list()
rows_t1[[1]] <- data.frame(
  Variable = "N", Overall = as.character(nrow(df)),
  Cancer = as.character(sum(df$DN == 1, na.rm = TRUE)),
  No_cancer = as.character(sum(df$DN == 0, na.rm = TRUE)),
  P = "", stringsAsFactors = FALSE
)
for (v in t1_vars) {
  x <- df[[v]]
  if (is.numeric(x) || is.integer(x)) {
    x <- exwas_to_num(x)
    ok <- is.finite(x) & is.finite(exwas_to_num(df$DN))
    g1 <- x[ok & df$DN == 1]; g0 <- x[ok & df$DN == 0]
    med_fmt <- function(z) {
      if (!length(z)) return("NA")
      sprintf("%.1f (%.1f, %.1f)", stats::median(z), stats::quantile(z, 0.25), stats::quantile(z, 0.75))
    }
    p <- tryCatch(stats::wilcox.test(g1, g0)$p.value, error = function(e) NA_real_)
    rows_t1[[length(rows_t1) + 1L]] <- data.frame(
      Variable = v,
      Overall = med_fmt(x[ok]), Cancer = med_fmt(g1), No_cancer = med_fmt(g0),
      P = if (is.finite(p)) format.pval(p, digits = 3, eps = 0.001) else "",
      stringsAsFactors = FALSE
    )
  } else {
    xx <- as.character(x)
    xx[is.na(xx) | !nzchar(xx)] <- "(Missing)"
    y01 <- as.integer(exwas_to_num(df$DN) == 1L)
    tab <- table(xx, y01, useNA = "no")
    p <- tryCatch(
      suppressWarnings(stats::chisq.test(tab)$p.value),
      error = function(e) {
        tryCatch(stats::fisher.test(tab)$p.value, error = function(e2) NA_real_)
      }
    )
    levs <- rownames(tab)
    for (lv in levs) {
      n0 <- if ("0" %in% colnames(tab)) as.integer(tab[lv, "0"]) else 0L
      n1 <- if ("1" %in% colnames(tab)) as.integer(tab[lv, "1"]) else 0L
      if (is.na(n0)) n0 <- 0L
      if (is.na(n1)) n1 <- 0L
      nA <- n0 + n1
      pct <- function(n, den) sprintf("%d (%.1f%%)", n, 100 * n / max(den, 1))
      rows_t1[[length(rows_t1) + 1L]] <- data.frame(
        Variable = paste0(v, ": ", lv),
        Overall = pct(nA, nrow(df)),
        Cancer = pct(n1, sum(df$DN == 1, na.rm = TRUE)),
        No_cancer = pct(n0, sum(df$DN == 0, na.rm = TRUE)),
        P = if (identical(lv, levs[1]) && is.finite(p)) format.pval(p, digits = 3, eps = 0.001) else "",
        stringsAsFactors = FALSE
      )
    }
  }
}
t1 <- do.call(rbind, rows_t1)
utils::write.csv(t1, file.path(tab_dir, "Table 1. Baseline characteristics by cancer status.csv"),
                 row.names = FALSE)

# ---------- Table 2 = 主 ExWAS ----------
tab2_src <- file.path(screen_dir, "Table_2_ExWAS_toxicant_screen.csv")
.copy_if(tab2_src, file.path(tab_dir, "Table 2. ExWAS toxicant associations.csv"))
.copy_if(hits_csv, file.path(tab_dir, "Table 2b. ExWAS FDR hits.csv"))
tab2 <- utils::read.csv(tab2_src, stringsAsFactors = FALSE)

# ---------- Figure 1 flowchart ----------
exwas_log("Figure 1")
attr_src <- file.path(screen_dir, "Table_S0_attrition.csv")
att <- if (file.exists(attr_src)) utils::read.csv(attr_src, stringsAsFactors = FALSE) else NULL
n_merge <- nrow(built$data)
n_ucr <- sum(is.finite(exwas_to_num(built$data$URXUCR)) & exwas_to_num(built$data$URXUCR) > 0)
# rebuild counts from log-equivalent steps
steps <- data.frame(
  step = c(
    paste0("Age>=", opt$min_age, " cancer/never-cancer with toxicant join"),
    "URXUCR>0",
    "WTSA2YR>0",
    "Analyte LOD screen pool",
    "Person missing <=1/3 cycle panel"
  ),
  n = c(n_merge, NA, NA, NA, nrow(df)),
  cases = c(sum(built$data$DN == 1, na.rm = TRUE), NA, NA, NA, sum(df$DN == 1, na.rm = TRUE)),
  stringsAsFactors = FALSE
)
# from screen attrition + summary
summ <- utils::read.csv(file.path(screen_dir, "Table_compare_summary.csv"), stringsAsFactors = FALSE)
# parse from screen README / recompute
d_tmp <- built$data
n0 <- nrow(d_tmp); c0 <- sum(d_tmp$DN == 1, na.rm = TRUE)
d_tmp <- d_tmp[is.finite(exwas_to_num(d_tmp$URXUCR)) & exwas_to_num(d_tmp$URXUCR) > 0, ]
n1 <- nrow(d_tmp); c1 <- sum(d_tmp$DN == 1, na.rm = TRUE)
d_tmp <- d_tmp[is.finite(exwas_to_num(d_tmp$WTSA2YR)) & exwas_to_num(d_tmp$WTSA2YR) > 0, ]
n2 <- nrow(d_tmp); c2 <- sum(d_tmp$DN == 1, na.rm = TRUE)
steps$n <- c(n0, n1, n2, n2, nrow(df))
steps$cases <- c(c0, c1, c2, c2, sum(df$DN == 1, na.rm = TRUE))
utils::write.csv(steps, file.path(tab_dir, "Flowchart_attrition.csv"), row.names = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  lab <- sprintf(
    "Age>=%d + toxicant\nn=%s (cases %s)\n\nExclude missing URXUCR\n→ n=%s (cases %s)\n\nExclude WTSA2YR<=0\n→ n=%s (cases %s)\n\nPerson missing>1/3\n→ Analytic n=%s (cases %s)\nCancer %s | Never-cancer %s",
    opt$min_age,
    format(n0, big.mark = ","), format(c0, big.mark = ","),
    format(n1, big.mark = ","), format(c1, big.mark = ","),
    format(n2, big.mark = ","), format(c2, big.mark = ","),
    format(nrow(df), big.mark = ","), format(sum(df$DN == 1), big.mark = ","),
    format(sum(df$DN == 1), big.mark = ","), format(sum(df$DN == 0), big.mark = ",")
  )
  p1 <- ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = lab, size = 3.6, family = "serif") +
    ggplot2::theme_void() +
    ggplot2::labs(title = "Figure 1. Study flowchart (pan-cancer ExWAS, NHANES multi-cycle)")
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 1. Study flowchart.pdf"), p1, width = 7, height = 8)
  .write_md(
    file.path(fig_dir, "image_information", "Figure 1. Study flowchart.md"),
    "Figure 1. Study flowchart",
    paste0("逐步人数：合并 Age>=", opt$min_age, " n=", n0, "（病例", c0, "）→ URXUCR>0 n=", n1,
           " → WTSA2YR>0 n=", n2, " → 人缺失<=1/3 分析集 n=", nrow(df),
           "（病例", sum(df$DN == 1), "；对照", sum(df$DN == 0), "）。"),
    paste0("暴露=环境毒物；结局=泛癌(MCQ220)；库=NHANES 多周期；Grouping=无。")
  )
}

# ---------- Figure 2 volcano（全暴露）----------
exwas_log("Figure 2")
if (requireNamespace("ggplot2", quietly = TRUE) && nrow(tab2)) {
  ht <- tab2
  ht$logOR <- log(pmax(ht$OR, 1e-12))
  ht$logp <- -log10(pmax(ht$p, 1e-300))
  ht$sig <- is.finite(ht$q) & ht$q < 0.05
  ht$lab <- ifelse(ht$sig, ifelse(!is.na(ht$exposure_name), ht$exposure_name, ht$exposure), "")
  p2 <- ggplot2::ggplot(ht, ggplot2::aes(x = logOR, y = logp, color = sig)) +
    ggplot2::geom_point(alpha = 0.85, size = 2) +
    ggplot2::geom_text(ggplot2::aes(label = lab), size = 2.2, vjust = -0.35, check_overlap = TRUE, show.legend = FALSE) +
    ggplot2::scale_color_manual(values = c(`FALSE` = "grey55", `TRUE` = "#B2182B"), labels = c("q>=0.05", "q<0.05")) +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(
      title = "Figure 2. ExWAS volcano (pan-cancer)",
      subtitle = "Unweighted logistic; BH-FDR; OR per IQR; full covariates without Smoke",
      x = "log(OR per IQR)", y = expression(-log[10](p)), color = NULL
    )
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 2. ExWAS volcano.pdf"), p2, width = 8, height = 6)
  .write_md(
    file.path(fig_dir, "image_information", "Figure 2. ExWAS volcano.md"),
    "Figure 2. ExWAS volcano",
    paste0("点=毒物；红=FDR q<0.05（n=", sum(ht$sig, na.rm = TRUE), "）；横轴 log(OR/IQR)，纵轴 -log10(p)。"),
    paste0("N=", summ$n[1], "；病例=", summ$n_cases[1], "；暴露数=", summ$n_exposures_tested[1], "。")
  )
}

# ---------- 分层 ExWAS：性别 / 年龄 → Fig3 + S3/S4 ----------
exwas_log("分层 ExWAS sex/age")
run_stratum <- function(idx, name) {
  if (length(idx) < 100L) return(NULL)
  sub <- df[idx, , drop = FALSE]
  # 完整病例粗估太慢；用 mice full covars 太重 → 对齐原文分层用同主模协变量、完整病例 glm
  one <- exwas_run_unweighted(sub, "DN", scr$keep, covars_full)
  one$stratum <- name
  one$n_stratum <- nrow(sub)
  one$n_events <- sum(sub$DN == 1, na.rm = TRUE)
  one$exposure_name <- disp_of(sub("_(ln|bin)$", "", one$exposure))
  one$family <- unname(fam_map[sub("_(ln|bin)$", "", one$exposure)])
  one
}
sex_f <- if ("Gender" %in% names(df)) {
  grepl("^[Ff]|Female|女", as.character(df$Gender))
} else {
  exwas_to_num(df$RIAGENDR) == 2
}
age_cut <- 65L
age_lt <- exwas_to_num(df$Age) < age_cut
st_male <- run_stratum(which(!sex_f), "Male")
st_female <- run_stratum(which(sex_f), "Female")
st_lt_age <- run_stratum(which(age_lt), paste0("Age_lt", age_cut))
st_ge_age <- run_stratum(which(!age_lt), paste0("Age_ge", age_cut))
st_all <- rbind(st_male, st_female, st_lt_age, st_ge_age)
if (!is.null(st_all) && nrow(st_all)) {
  utils::write.csv(st_all, file.path(tab_dir, "Table S3. ExWAS stratified by sex.csv"), row.names = FALSE)
  utils::write.csv(
    st_all[st_all$stratum %in% c(paste0("Age_lt", age_cut), paste0("Age_ge", age_cut)), ],
    file.path(tab_dir, "Table S4. ExWAS stratified by age.csv"), row.names = FALSE
  )
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    plot_st <- function(d, title, file) {
      d$sig <- is.finite(d$q) & d$q < 0.05
      d$logOR <- log(pmax(d$OR, 1e-12))
      ggplot2::ggplot(d, ggplot2::aes(x = logOR, y = -log10(pmax(p, 1e-300)), color = sig)) +
        ggplot2::geom_point(alpha = 0.8, size = 1.6) +
        ggplot2::facet_wrap(~stratum, nrow = 1) +
        ggplot2::scale_color_manual(values = c(`FALSE` = "grey60", `TRUE` = "#B2182B")) +
        ggplot2::theme_bw(base_size = 9, base_family = "serif") +
        ggplot2::labs(title = title, x = "log(OR)", y = expression(-log[10](p)), color = "q<0.05")
      ggplot2::ggsave(file, width = 10, height = 4.5)
    }
    plot_st(rbind(st_male, st_female),
            "Figure 3. Stratified ExWAS by sex",
            file.path(fig_dir, "pdf", "Figure 3. Stratified ExWAS by sex and age.pdf"))
    # overwrite with 2x2 if age also available
    if (!is.null(st_lt_age)) {
      p3 <- ggplot2::ggplot(
        st_all,
        ggplot2::aes(x = log(pmax(OR, 1e-12)), y = -log10(pmax(p, 1e-300)),
                     color = is.finite(q) & q < 0.05)
      ) +
        ggplot2::geom_point(alpha = 0.75, size = 1.5) +
        ggplot2::facet_wrap(~stratum, nrow = 2) +
        ggplot2::scale_color_manual(values = c(`FALSE` = "grey60", `TRUE` = "#B2182B")) +
        ggplot2::theme_bw(base_size = 9, base_family = "serif") +
        ggplot2::labs(
          title = "Figure 3. Stratified ExWAS (sex and age)",
          x = "log(OR per IQR)", y = expression(-log[10](p)), color = "q<0.05"
        )
      ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 3. Stratified ExWAS by sex and age.pdf"),
                      p3, width = 9, height = 7)
      .write_md(
        file.path(fig_dir, "image_information", "Figure 3. Stratified ExWAS by sex and age.md"),
        "Figure 3. Stratified ExWAS by sex and age",
        sprintf("四面板：Male / Female / Age<%d / Age>=%d；红点 FDR q<0.05。", age_cut, age_cut),
        paste0("同主分析协变量；分析集 N=", nrow(df), "。")
      )
    }
  }
}

# ---------- 敏感性：家族 FDR / 无插补 / +Smoke / 从不吸烟 ----------
exwas_log("敏感性 S2/S7/S8/S9/S10")
# S2 family-wise FDR on main tab2
if ("family" %in% names(tab2) || length(fam_map)) {
  t2 <- tab2
  if (!"family" %in% names(t2) || all(is.na(t2$family))) {
    t2$family <- unname(fam_map[t2$exposure_raw])
  }
  t2$q_family <- NA_real_
  for (fm in unique(t2$family)) {
    idx <- which(t2$family == fm)
    t2$q_family[idx] <- exwas_fdr(t2$p[idx])
  }
  utils::write.csv(t2, file.path(tab_dir, "Table S2. Familywise FDR ExWAS.csv"), row.names = FALSE)
}

# S7/S5：调查加权 ExWAS（Dong 主 ExWAS 刻意不加权；替代原完整病例无插补）
# 细脚本：run/environment_exwas/rerun_pancancer_s5_survey_weighted.R
if (!all(c("WTSA2YR", "SDMVPSU", "SDMVSTRA_cyc") %in% names(df))) {
  stop("缺调查设计列，无法跑加权 ExWAS 敏感性", call. = FALSE)
}
wmap <- stats::setNames(rep("WTSA2YR", length(scr$keep)), scr$keep)
s7_fit <- exwas_run_survey_mice(
  df, "DN", scr$keep, covars_full, weight_map = wmap,
  families = NULL, energy_col = NULL, diet_impute_cols = NULL,
  m = 5L, maxit = 5L, seed = 123456L,
  psu = "SDMVPSU", strata = "SDMVSTRA_cyc"
)
s7 <- s7_fit$table
s7$exposure_raw <- sub("_(ln|bin)$", "", s7$exposure)
s7$exposure_name <- disp_of(s7$exposure_raw)
s7$family <- unname(fam_map[s7$exposure_raw])
s7$q <- exwas_fdr(s7$p)
utils::write.csv(s7, file.path(tab_dir, "Table S7. ExWAS survey-weighted.csv"), row.names = FALSE)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  s7$sig <- is.finite(s7$q) & s7$q < 0.05
  p5 <- ggplot2::ggplot(s7, ggplot2::aes(x = OR, y = -log10(pmax(p, 1e-300)), color = sig)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, color = "grey55") +
    ggplot2::geom_hline(yintercept = -log10(0.05), linetype = 2, color = "grey55") +
    ggplot2::geom_point(alpha = 0.85) +
    ggplot2::scale_color_manual(values = c(`FALSE` = "grey55", `TRUE` = "#B2182B")) +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(
      title = "Figure S5. ExWAS survey-weighted",
      subtitle = sprintf("WTSA2YR; MICE m=5; FDR hits=%d", sum(s7$sig, na.rm = TRUE)),
      x = "OR per IQR", y = expression(-log[10](p))
    )
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure S5. ExWAS survey-weighted.pdf"), p5, width = 9, height = 6.6)
  .write_md(
    file.path(fig_dir, "image_information", "Figure S5. ExWAS survey-weighted.md"),
    "Figure S5. ExWAS survey-weighted",
    paste0("Dong 主 ExWAS 不加权；本敏感性为调查加权。FDR 命中=", sum(s7$sig, na.rm = TRUE), "。"),
    "替代原完整病例无插补 S5；协变量同主分析。"
  )
}

# S8 + Smoke
cov_smoke <- unique(c(covars_full, if ("Smoke" %in% names(df)) "Smoke"))
if ("Smoke" %in% names(df)) {
  df_sm <- exwas_aligned_as_model_frame(df, cov_smoke)
  s8 <- exwas_run_unweighted(df_sm, "DN", scr$keep, cov_smoke)
  s8$exposure_name <- disp_of(sub("_(ln|bin)$", "", s8$exposure))
  utils::write.csv(s8, file.path(tab_dir, "Table S8. ExWAS additional Smoke adjustment.csv"), row.names = FALSE)
}

# S9 never-smokers
if ("Smoke" %in% names(df)) {
  sm <- as.character(df$Smoke)
  never <- grepl("Never|never|从不", sm, ignore.case = TRUE)
  if (sum(never) >= 200L) {
    s9 <- exwas_run_unweighted(df[never, , drop = FALSE], "DN", scr$keep, covars_full)
    s9$exposure_name <- disp_of(sub("_(ln|bin)$", "", s9$exposure))
    s9$n_stratum <- sum(never)
    s9$n_events <- sum(df$DN[never] == 1, na.rm = TRUE)
    utils::write.csv(s9, file.path(tab_dir, "Table S9. ExWAS among never-smokers.csv"), row.names = FALSE)
  } else {
    writeLines("Never-smoker stratum too small or Smoke coding unmatched.",
               file.path(tab_dir, "Table S9. ExWAS among never-smokers.NOTE.txt"))
  }
}

# S10 per IQR (main) + per unit (refit without IQR scaling) for FDR hits
hits <- utils::read.csv(hits_csv, stringsAsFactors = FALSE)
hit_cols <- intersect(hits$exposure, scr$keep)
s10_rows <- list()
for (x in hit_cols) {
  raw <- sub("_(ln|bin)$", "", x)
  # IQR from main table
  row_iqr <- tab2[tab2$exposure == x, , drop = FALSE]
  # per-unit: glm without IQR divide
  cols <- unique(c("DN", x, covars_full))
  dd <- df[, cols[cols %in% names(df)], drop = FALSE]
  dd[[x]] <- exwas_to_num(dd[[x]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L) next
  fml <- stats::as.formula(paste("DN ~", paste(c(x, intersect(covars_full, names(dd))), collapse = "+")))
  fit <- tryCatch(stats::glm(fml, data = dd, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) next
  cf <- summary(fit)$coefficients
  hit <- rownames(cf)[rownames(cf) == x | startsWith(rownames(cf), x)]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) next
  b <- cf[hit[1], 1]; se <- cf[hit[1], 2]
  s10_rows[[x]] <- data.frame(
    exposure = x, exposure_name = disp_of(raw),
    OR_per_IQR = if (nrow(row_iqr)) row_iqr$OR[1] else NA_real_,
    p_IQR = if (nrow(row_iqr)) row_iqr$p[1] else NA_real_,
    q_IQR = if (nrow(row_iqr)) row_iqr$q[1] else NA_real_,
    OR_per_unit = exp(b), lo_unit = exp(b - 1.96 * se), hi_unit = exp(b + 1.96 * se),
    p_unit = cf[hit[1], 4],
    n = nrow(dd), stringsAsFactors = FALSE
  )
}
if (length(s10_rows)) {
  utils::write.csv(do.call(rbind, s10_rows),
                   file.path(tab_dir, "Table S10. Per IQR and per unit associations for FDR hits.csv"),
                   row.names = FALSE)
}

# ---------- S1 分析物特征 ----------
s1_src <- file.path(screen_dir, "Table_S1_analyte_LOD_screen.csv")
if (file.exists(s1_src)) {
  s1 <- utils::read.csv(s1_src, stringsAsFactors = FALSE)
  if ("analyte" %in% names(s1) || "Labels" %in% names(s1) || "exposure" %in% names(s1)) {
    key <- if ("analyte" %in% names(s1)) "analyte" else if ("Labels" %in% names(s1)) "Labels" else names(s1)[1]
    s1$exposure_name <- disp_of(as.character(s1[[key]]))
    s1$family <- unname(fam_map[as.character(s1[[key]])])
  }
  utils::write.csv(s1, file.path(tab_dir, "Table S1. Toxicant analyte characteristics and LOD screen.csv"),
                   row.names = FALSE)
}

# ---------- 相关图 Fig4A / FigS2 / FigS6 ----------
exwas_log("相关矩阵图")
plot_cor <- function(cols, title, file, max_n = 80L) {
  cols <- intersect(cols, names(df))
  if (length(cols) < 2L || !requireNamespace("ggplot2", quietly = TRUE)) return(invisible(FALSE))
  if (length(cols) > max_n) cols <- cols[seq_len(max_n)]
  Xm <- df[, cols, drop = FALSE]
  for (nm in names(Xm)) Xm[[nm]] <- exwas_to_num(Xm[[nm]])
  # 多周期跨面板：用 pairwise，不要求全列完整病例
  n_any <- sum(rowSums(is.finite(as.matrix(Xm))) > 0)
  if (n_any < 50L) return(invisible(FALSE))
  R <- suppressWarnings(stats::cor(Xm, use = "pairwise.complete.obs"))
  if (!is.matrix(R) || all(!is.finite(R))) return(invisible(FALSE))
  raw <- sub("_(ln|bin)$", "", colnames(R))
  colnames(R) <- rownames(R) <- disp_of(raw)
  rdf <- as.data.frame(as.table(R), stringsAsFactors = FALSE)
  names(rdf) <- c("x", "y", "r")
  rdf$r[!is.finite(rdf$r)] <- NA_real_
  p <- ggplot2::ggplot(rdf, ggplot2::aes(x = x, y = y, fill = r)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(limits = c(-1, 1), midpoint = 0, na.value = "grey90") +
    ggplot2::theme_bw(base_size = 7, base_family = "serif") +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, hjust = 1, vjust = 0.5)) +
    ggplot2::labs(title = title, x = NULL, y = NULL)
  ggplot2::ggsave(file, p, width = 9, height = 8)
  invisible(TRUE)
}
plot_cor(hit_cols, "Figure 4A. Correlation among FDR-hit toxicants",
         file.path(fig_dir, "pdf", "Figure 4A. Toxicant correlation FDR hits.pdf"))
plot_cor(scr$keep, "Figure S2. Correlation among screened toxicants",
         file.path(fig_dir, "pdf", "Figure S2. Toxicant correlation all screened.pdf"), max_n = 63L)
.write_md(
  file.path(fig_dir, "image_information", "Figure S2. Toxicant correlation all screened.md"),
  "Figure S2. Toxicant correlation",
  "热图为分析物两两 Pearson 相关（完整病例）。",
  paste0("分析集 N=", nrow(df), "；暴露=", length(scr$keep), "。")
)
# S6：Dong linkET 风格（毒物三角热图 + Smoke 连线）；专用脚本，避免条形图
exwas_log("Figure S6 → redraw_pancancer_fig_s6_linket.R")
st6 <- system2(
  "Rscript",
  c(file.path(root, "run/environment_exwas/redraw_pancancer_fig_s6_linket.R")),
  stdout = TRUE, stderr = TRUE
)
exwas_log(paste(utils::tail(st6, 5), collapse = " | "))

# ---------- Figure S1 DAG（示意）----------
if (requireNamespace("ggplot2", quietly = TRUE)) {
  dag <- data.frame(
    label = c(
      "Age / Gender / Race / Education\nMarital / PIR / BMI / Alcohol / eGFR",
      "Environmental\ntoxicants",
      "Pan-cancer\n(MCQ220)",
      "Inflammation\n(WBC/NEUT/MONO/NLR/SII/SIRI)"
    ),
    x = c(0.2, 0.5, 0.8, 0.5),
    y = c(0.7, 0.7, 0.7, 0.25),
    stringsAsFactors = FALSE
  )
  p_dag <- ggplot2::ggplot(dag, ggplot2::aes(x, y, label = label)) +
    ggplot2::geom_label(size = 3, family = "serif") +
    ggplot2::annotate("segment", x = 0.32, xend = 0.42, y = 0.7, yend = 0.7,
                      arrow = ggplot2::arrow(length = grid::unit(0.15, "cm"))) +
    ggplot2::annotate("segment", x = 0.58, xend = 0.68, y = 0.7, yend = 0.7,
                      arrow = ggplot2::arrow(length = grid::unit(0.15, "cm"))) +
    ggplot2::annotate("segment", x = 0.5, xend = 0.5, y = 0.58, yend = 0.38,
                      arrow = ggplot2::arrow(length = grid::unit(0.15, "cm"))) +
    ggplot2::annotate("segment", x = 0.58, xend = 0.72, y = 0.32, yend = 0.58,
                      arrow = ggplot2::arrow(length = grid::unit(0.15, "cm"))) +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void() +
    ggplot2::labs(title = "Figure S1. Directed acyclic graph (cancer-adapted covariates)")
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure S1. DAG covariates.pdf"), p_dag, width = 9, height = 5)
  .write_md(
    file.path(fig_dir, "image_information", "Figure S1. DAG covariates.md"),
    "Figure S1. DAG covariates",
    "示意：人口学/社会经济/行为/eGFR → 毒物与结局；炎症为 ERS→癌 探索中介。癌症迁移去掉口腔三项；主 ExWAS 不含 Smoke。",
    "对齐 Dong 2026 补充 Figure 1 逻辑，结局改为泛癌。"
  )
}

# ---------- 从下游搬运 / 画 Fig4 B–F、Fig5、S3、S5、S6、S7、S11 ----------
exwas_log("组装下游图表")
.map_down <- c(
  "Table_S5_ERS_bootstrap_inclusion.csv" = "Table S5. ERS bootstrap inclusion frequencies.csv",
  "Table_S5_ERS_selected.csv" = "Table S5b. ERS selected toxicants.csv",
  "Table_S5_ERS_tuning.csv" = "Table S5c. ERS elastic-net tuning.csv",
  "Table_ERS_logistic_weighted.csv" = "Table. ERS weighted logistic Model1 Model2.csv",
  "Table_S6_mediation_exploratory.csv" = "Table S6. Mediation exploratory.csv",
  "Table_S11_Evalue_ERS.csv" = "Table S11. E-values for ERS association.csv",
  "Table_WQS_weights.csv" = "Table. WQS mixture weights.csv",
  "Table_WQS_coefficients.csv" = "Table. WQS coefficients.csv",
  "Table_S0_hit_pool.csv" = "Table S0. FDR hit pool for ERS WQS.csv"
)
for (nm in names(.map_down)) {
  .copy_if(file.path(down_dir, nm), file.path(tab_dir, .map_down[[nm]]))
}

# Fig4B/C alpha-lambda from tuning + inclusion
tune <- file.path(down_dir, "Table_S5_ERS_tuning.csv")
incl <- file.path(down_dir, "Table_S5_ERS_bootstrap_inclusion.csv")
sel <- file.path(down_dir, "Table_S5_ERS_selected.csv")
ers_tab <- file.path(down_dir, "Table_ERS_logistic_weighted.csv")
if (requireNamespace("ggplot2", quietly = TRUE) && file.exists(incl)) {
  inc <- utils::read.csv(incl, stringsAsFactors = FALSE)
  # expected columns: exposure, freq / inclusion
  fcol <- if ("inclusion_freq" %in% names(inc)) "inclusion_freq" else if ("freq" %in% names(inc)) "freq" else names(inc)[2]
  ecol <- if ("exposure" %in% names(inc)) "exposure" else names(inc)[1]
  inc$exposure_name <- disp_of(sub("_(ln|bin)$", "", as.character(inc[[ecol]])))
  pB <- ggplot2::ggplot(inc, ggplot2::aes(x = reorder(exposure_name, .data[[fcol]]), y = .data[[fcol]])) +
    ggplot2::geom_col(fill = "#4393C3") + ggplot2::coord_flip() +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(title = "Figure 4B-C. ERS bootstrap inclusion / selection",
                  x = NULL, y = "Bootstrap inclusion frequency")
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 4BC. ERS inclusion.pdf"), pB, width = 8, height = 6)
}

if (requireNamespace("ggplot2", quietly = TRUE) && file.exists(ers_tab)) {
  et <- utils::read.csv(ers_tab, stringsAsFactors = FALSE)
  et$lab <- sprintf("%.3f (%.3f-%.3f)", et$OR, et$lo, et$hi)
  pD <- ggplot2::ggplot(et, ggplot2::aes(x = OR, y = model, xmin = lo, xmax = hi)) +
    ggplot2::geom_point(size = 2.5, color = "#B2182B") +
    ggplot2::geom_errorbarh(height = 0.2, color = "#B2182B") +
    ggplot2::geom_vline(xintercept = 1, linetype = 2) +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(title = "Figure 4D. ERS association forest (survey-weighted)",
                  x = "OR", y = NULL)
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 4D. ERS forest.pdf"), pD, width = 8, height = 4)
  .write_md(
    file.path(fig_dir, "image_information", "Figure 4D. ERS forest.md"),
    "Figure 4D. ERS forest",
    paste(capture.output(print(et[, c("model", "OR", "lo", "hi", "p")])), collapse = "\n"),
    "WTSA2YR 加权；Model1 未调整；Model2 全协变量（无 Smoke）。"
  )
}

# Fig4E RCS curve
if (requireNamespace("ggplot2", quietly = TRUE) && file.exists(file.path(down_dir, "Table_ERS_logistic_weighted.csv"))) {
  # rebuild ERS on df if selected available
  if (file.exists(sel)) {
    ss <- utils::read.csv(sel, stringsAsFactors = FALSE)
    if (all(c("exposure", "coef") %in% names(ss)) && nrow(ss)) {
      beta <- stats::setNames(ss$coef, ss$exposure)
      df$ERS <- exwas_tox_score_ers(df, beta)
      use <- df[is.finite(df$ERS) & is.finite(exwas_to_num(df$WTSA2YR)) & exwas_to_num(df$WTSA2YR) > 0, ]
      iqr <- stats::IQR(use$ERS, na.rm = TRUE)
      if (!is.finite(iqr) || iqr == 0) iqr <- 1
      use$ERS_IQR <- use$ERS / iqr
      # predict grid with unweighted glm for curve shape + note survey p_nl from file
      fit <- tryCatch(
        stats::glm(
          stats::as.formula(paste("DN ~ splines::ns(ERS_IQR, df=2)",
                                  if (length(covars_full)) paste("+", paste(covars_full, collapse = "+")) else "")),
          data = use, family = stats::binomial(), weights = exwas_to_num(use$WTSA2YR)
        ),
        error = function(e) NULL
      )
      if (!is.null(fit)) {
        grid <- data.frame(ERS_IQR = seq(stats::quantile(use$ERS_IQR, 0.05, na.rm = TRUE),
                                         stats::quantile(use$ERS_IQR, 0.95, na.rm = TRUE), length.out = 80))
        for (cv in covars_full) {
          if (!cv %in% names(use)) next
          if (is.factor(use[[cv]]) || is.character(use[[cv]])) {
            grid[[cv]] <- levels(factor(use[[cv]]))[1]
          } else {
            grid[[cv]] <- stats::median(exwas_to_num(use[[cv]]), na.rm = TRUE)
          }
        }
        grid$pred <- as.numeric(stats::predict(fit, newdata = grid, type = "response"))
        note <- file.path(down_dir, "Figure_4_RCS_note.txt")
        sub <- if (file.exists(note)) paste(readLines(note), collapse = " | ") else ""
        pE <- ggplot2::ggplot(grid, ggplot2::aes(ERS_IQR, pred)) +
          ggplot2::geom_line(color = "#B2182B", linewidth = 1) +
          ggplot2::theme_bw(base_family = "serif") +
          ggplot2::labs(title = "Figure 4E. RCS of ERS vs pan-cancer",
                        subtitle = sub, x = "ERS (per IQR)", y = "Predicted probability")
        ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 4E. ERS RCS.pdf"), pE, width = 7, height = 5)
        .write_md(
          file.path(fig_dir, "image_information", "Figure 4E. ERS RCS.md"),
          "Figure 4E. ERS RCS",
          paste0("RCS(ns df=2≈3 knots)；", sub),
          paste0("加权展示曲线；分析 n≈", nrow(use), "。")
        )
      }
    }
  }
}

# Fig4F / FigS3 ERS subgroup forest
if (requireNamespace("ggplot2", quietly = TRUE) && exists("use") && is.data.frame(use) && "ERS_IQR" %in% names(use)) {
  age_cut <- 65L
  use$age_band <- ifelse(
    exwas_to_num(use$Age) < age_cut,
    paste0("<", age_cut),
    paste0(">=", age_cut)
  )
  use$sex <- if ("Gender" %in% names(use)) as.character(use$Gender) else NA_character_
  strata_list <- list(
    Overall = rep(TRUE, nrow(use)),
    Male = grepl("Male|^M", use$sex),
    Female = grepl("Female|^F", use$sex)
  )
  strata_list[[paste0("Age_lt", age_cut)]] <- use$age_band == paste0("<", age_cut)
  strata_list[[paste0("Age_ge", age_cut)]] <- use$age_band == paste0(">=", age_cut)
  if ("Alcohol_drinking" %in% names(use)) {
    al <- as.character(use$Alcohol_drinking)
    strata_list$Alcohol_yes <- grepl("Yes|yes|饮", al)
    strata_list$Alcohol_no <- grepl("No|no|不", al)
  }
  sg_rows <- list()
  for (nm in names(strata_list)) {
    idx <- which(isTRUE(strata_list[[nm]]) | strata_list[[nm]] == TRUE)
    # fix logical
    idx <- which(strata_list[[nm]])
    if (length(idx) < 80L) next
    sub <- use[idx, , drop = FALSE]
    est <- exwas_fit_one(sub, "DN", "ERS_IQR", character(0))
    sg_rows[[nm]] <- data.frame(stratum = nm, OR = est$OR, lo = est$lo, hi = est$hi, p = est$p,
                                n = nrow(sub), n_events = sum(sub$DN == 1), stringsAsFactors = FALSE)
  }
  if (length(sg_rows)) {
    sg <- do.call(rbind, sg_rows)
    utils::write.csv(sg, file.path(tab_dir, "Table. ERS subgroup associations.csv"), row.names = FALSE)
    pF <- ggplot2::ggplot(sg, ggplot2::aes(x = OR, y = stratum, xmin = lo, xmax = hi)) +
      ggplot2::geom_point(color = "#B2182B") +
      ggplot2::geom_errorbarh(height = 0.2, color = "#B2182B") +
      ggplot2::geom_vline(xintercept = 1, linetype = 2) +
      ggplot2::theme_bw(base_family = "serif") +
      ggplot2::labs(title = "Figure 4F / Figure S3. ERS subgroup forest", x = "OR per IQR", y = NULL)
    ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 4F. ERS subgroup forest.pdf"), pF, width = 8, height = 5)
    file.copy(file.path(fig_dir, "pdf", "Figure 4F. ERS subgroup forest.pdf"),
              file.path(fig_dir, "pdf", "Figure S3. ERS subgroup forest.pdf"), overwrite = TRUE)
    .write_md(
      file.path(fig_dir, "image_information", "Figure S3. ERS subgroup forest.md"),
      "Figure S3. ERS subgroup forest",
      paste(capture.output(print(sg)), collapse = "\n"),
      "Model1 未调整分层；ERS per IQR。"
    )
  }
}

# Fig5 + S6 mediation plot
medf <- file.path(down_dir, "Table_S6_mediation_exploratory.csv")
if (file.exists(medf) && requireNamespace("ggplot2", quietly = TRUE)) {
  md <- utils::read.csv(medf, stringsAsFactors = FALSE)
  if (nrow(md)) {
    md$prop <- ifelse(is.finite(md$direct + md$indirect) & (md$direct + md$indirect) != 0,
                      100 * md$indirect / (md$direct + md$indirect), NA_real_)
    p5m <- ggplot2::ggplot(md, ggplot2::aes(x = reorder(mediator, abs(indirect)), y = indirect)) +
      ggplot2::geom_col(fill = "#D6604D") + ggplot2::coord_flip() +
      ggplot2::theme_bw(base_family = "serif") +
      ggplot2::labs(title = "Figure 5. Exploratory mediation (product method)",
                    subtitle = "Indirect effect of ERS via inflammatory biomarkers",
                    x = NULL, y = "Indirect effect (a*b)")
    ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure 5. Mediation inflammatory biomarkers.pdf"),
                    p5m, width = 7, height = 5)
    .write_md(
      file.path(fig_dir, "image_information", "Figure 5. Mediation inflammatory biomarkers.md"),
      "Figure 5. Mediation",
      paste(capture.output(print(md)), collapse = "\n"),
      "探索性；product method；有权重则 survey 拟合。"
    )
    # S4 sensitivity note
    writeLines(c(
      "Figure S4. Mediation sensitivity (cancer-adapted)",
      "Paper used formal mediation sensitivity (R2̃_M / R2̃_Y) for unmeasured confounding.",
      "This delivery reports exploratory product-method indirect effects in Table S6 / Figure 5.",
      "Cross-sectional NHANES: temporal order Exposure→Mediator→Outcome is assumed, not observed.",
      paste0("Mediators available: ", paste(md$mediator, collapse = ", "))
    ), file.path(fig_dir, "pdf", "Figure S4. Mediation sensitivity.NOTE.txt"))
    .write_md(
      file.path(fig_dir, "image_information", "Figure S4. Mediation sensitivity.md"),
      "Figure S4. Mediation sensitivity",
      "原文为未测混杂敏感性曲面；本交付以 Table S6 探索性间接效应 + 本说明代替完整 24 面板敏感性图（横断面局限已写明）。",
      "若需完整 mediation::mediate B=1000 曲面可再加跑。"
    )
  }
}

# Fig S7 WQS weights
wqs_w <- file.path(down_dir, "Table_WQS_weights.csv")
if (file.exists(wqs_w) && requireNamespace("ggplot2", quietly = TRUE)) {
  ww <- utils::read.csv(wqs_w, stringsAsFactors = FALSE)
  # gWQS final_weights usually mix_name, mean_weight
  nm_col <- if ("mix_name" %in% names(ww)) "mix_name" else names(ww)[1]
  w_col <- if ("mean_weight" %in% names(ww)) "mean_weight" else if ("Estimate" %in% names(ww)) "Estimate" else names(ww)[2]
  ww$exposure_name <- disp_of(sub("_(ln|bin)$", "", as.character(ww[[nm_col]])))
  p7 <- ggplot2::ggplot(ww, ggplot2::aes(x = reorder(exposure_name, .data[[w_col]]), y = .data[[w_col]])) +
    ggplot2::geom_col(fill = "#1B7837") + ggplot2::coord_flip() +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(title = "Figure S7. WQS relative weights", x = NULL, y = "Weight")
  ggplot2::ggsave(file.path(fig_dir, "pdf", "Figure S7. WQS weights.pdf"), p7, width = 8, height = 6)
  .write_md(
    file.path(fig_dir, "image_information", "Figure S7. WQS weights.md"),
    "Figure S7. WQS weights",
    "条形= gWQS 混合物各组分相对权重。",
    paste0("q=4; b=", opt$wqs_boot, "; 候选=ExWAS FDR 命中。")
  )
}

# ---------- Table S12 methods note ----------
writeLines(c(
  "# Table S12. Methodological comparison (paper vs this pan-cancer delivery)",
  "",
  "| Item | Dong 2026 periodontitis | This pan-cancer delivery |",
  "|---|---|---|",
  "| Outcome | Periodontitis (CDC/AAP) | Ever any cancer (MCQ220) |",
  "| Cycle | NHANES 2013-2014 | Multi-cycle NHANES with toxicant coverage |",
  paste0("| Age | >=20 | >=", opt$min_age, " |"),
  "| Urine creatinine | Adjust urine toxicants | Same (/URXUCR*100); require URXUCR>0 |",
  "| Weight | wtsa2yr for survey parts; ExWAS unweighted | Require WTSA2YR>0; ExWAS unweighted; ERS weighted |",
  "| ExWAS | Unweighted + BH-FDR; full covariates | Same; Smoke excluded from main ExWAS |",
  "| Dental covariates | Last dental visit, mouthwash, floss | Dropped (N/A for cancer) |",
  "| Gender | Included | Included (both sexes) |",
  "| ERS | Adaptive elastic-net; B=1000 | Same; glmnet adaptive (gcdnet optional) |",
  "| WQS | gWQS q=4 | Same |",
  "| Mediation | mediation package exploratory | Product-method exploratory on available CBC indices |",
  "",
  "Software seeds: mice/ExWAS 123456; WQS 123456; ERS bootstrap 123456 (paper also lists 2024 for some elastic-net)."
), file.path(tab_dir, "Table S12. Methodological comparison.md"))

# Methods stub
writeLines(c(
  "# Methods_statistical_analysis (pan-cancer toxicant ExWAS)",
  "",
  "Aligned to Dong et al. Ecotoxicology and Environmental Safety 2026 (EWAS-new), adapted to pan-cancer.",
  paste0("- Population: NHANES multi-cycle; Age>=", opt$min_age, "; cases=MCQ220=1; controls=MCQ220=2."),
  "- Exclusions: missing urinary creatinine; non-positive WTSA2YR; person-level missing >1/3 of cycle toxicant panel.",
  "- Toxicants: LOD screen (drop if missing>40% or underLOD>90%; binary if underLOD>30%; else ln); urine creatinine adjustment.",
  "- ExWAS: unweighted logistic; OR per IQR; mice m=5 maxit=5 seed=123456 on covariates; Rubin; BH-FDR.",
  "- Covariates: Age, Gender, Race, Education, Marital_Status, PIR, BMI, Alcohol_drinking, eGFR (no Smoke in main; no dental vars).",
  "- ERS: adaptive elastic-net on FDR hits; bootstrap inclusion; survey-weighted logistic Model1/Model2.",
  "- RCS: ns(df=2); WQS: gWQS q=4; Mediation: exploratory.",
  "",
  "## Software",
  "R; packages: mice, glmnet, survey, gWQS, ggplot2, haven, splines."
), file.path(out, "Methods_statistical_analysis.md"))

# ---------- 清单校验 ----------
need_tabs <- c(
  "Table 1. Baseline characteristics by cancer status.csv",
  "Table 2. ExWAS toxicant associations.csv",
  "Table S1. Toxicant analyte characteristics and LOD screen.csv",
  "Table S2. Familywise FDR ExWAS.csv",
  "Table S3. ExWAS stratified by sex.csv",
  "Table S4. ExWAS stratified by age.csv",
  "Table S5. ERS bootstrap inclusion frequencies.csv",
  "Table S6. Mediation exploratory.csv",
  "Table S7. ExWAS without imputation.csv",
  "Table S8. ExWAS additional Smoke adjustment.csv",
  "Table S10. Per IQR and per unit associations for FDR hits.csv",
  "Table S11. E-values for ERS association.csv",
  "Table S12. Methodological comparison.md"
)
need_figs <- c(
  "Figure 1. Study flowchart.pdf",
  "Figure 2. ExWAS volcano.pdf",
  "Figure 3. Stratified ExWAS by sex and age.pdf",
  "Figure 4A. Toxicant correlation FDR hits.pdf",
  "Figure 4BC. ERS inclusion.pdf",
  "Figure 4D. ERS forest.pdf",
  "Figure 4E. ERS RCS.pdf",
  "Figure 4F. ERS subgroup forest.pdf",
  "Figure 5. Mediation inflammatory biomarkers.pdf",
  "Figure S1. DAG covariates.pdf",
  "Figure S2. Toxicant correlation all screened.pdf",
  "Figure S3. ERS subgroup forest.pdf",
  "Figure S5. ExWAS without imputation.pdf",
  "Figure S6. Smoke toxicant correlation.pdf",
  "Figure S7. WQS weights.pdf"
)
chk <- data.frame(
  artifact = c(paste0("Tables/", need_tabs), paste0("Figures/pdf/", need_figs)),
  present = c(
    file.exists(file.path(tab_dir, need_tabs)),
    file.exists(file.path(fig_dir, "pdf", need_figs))
  ),
  stringsAsFactors = FALSE
)
# S9 optional note
chk <- rbind(chk, data.frame(
  artifact = "Tables/Table S9 (csv or NOTE)",
  present = file.exists(file.path(tab_dir, "Table S9. ExWAS among never-smokers.csv")) ||
    file.exists(file.path(tab_dir, "Table S9. ExWAS among never-smokers.NOTE.txt")),
  stringsAsFactors = FALSE
))
chk <- rbind(chk, data.frame(
  artifact = "Figures/pdf/Figure S4 (NOTE)",
  present = file.exists(file.path(fig_dir, "pdf", "Figure S4. Mediation sensitivity.NOTE.txt")),
  stringsAsFactors = FALSE
))
utils::write.csv(chk, file.path(out, "PUB_ARTIFACT_CHECKLIST.csv"), row.names = FALSE)
exwas_log("清单缺失数=", sum(!chk$present))
print(chk[!chk$present, , drop = FALSE])
exwas_log("写完 ", out)
)
