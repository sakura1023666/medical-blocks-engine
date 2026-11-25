#!/usr/bin/env Rscript
# Table 1：Dong「版式」但用本课题变量与合理顺序
# - 分类：父行「变量, n (%)」+ 子行 Excel 缩进水平名（挂在变量名下）
# - 连续：变量名含 median (Q25 %, Q75 %)
# - 顺序：人口学 → 行为 → 实验室(eGFR 末)，不照搬 Dong 把 eGFR 放第一行
#
#   Rscript run/environment_exwas/rebuild_pancancer_table1_dong_style.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data",
  min_age = 20L
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
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}

root <- opt$root
out_xlsx <- file.path(root, "summary_results", "Tables",
                      "Table 1. Baseline characteristics by cancer status.xlsx")
src_csv <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables",
                     "Table 1. Baseline characteristics by cancer status.csv")
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
covars <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR_cat", "BMI_cat",
    "Alcohol_drinking", "Smoke", "eGFR"),
  names(df)
)
df <- exwas_aligned_as_model_frame(df, covars)
df$DN <- as.integer(exwas_to_num(df$DN) == 1L)
df$Age <- exwas_to_num(df$Age)
df$eGFR <- exwas_to_num(df$eGFR)

sex_chr <- trimws(as.character(df$Gender))
df$Sex_show <- ifelse(
  grepl("Female|\u5973|^2$", sex_chr, ignore.case = TRUE), "Female",
  ifelse(grepl("Male|\u7537|^1$", sex_chr, ignore.case = TRUE), "Male", sex_chr)
)

n_tot <- nrow(df)
n_ca <- sum(df$DN == 1L, na.rm = TRUE)
n_nc <- sum(df$DN == 0L, na.rm = TRUE)
exwas_log("Table1 N=", n_tot, " cancer=", n_ca, " no-cancer=", n_nc)

.fmt_med <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return("")
  sprintf(
    "%.1f (%.1f, %.1f)",
    stats::median(x),
    stats::quantile(x, 0.25, names = FALSE),
    stats::quantile(x, 0.75, names = FALSE)
  )
}
.fmt_n_pct <- function(n, den) {
  sprintf("%s (%.1f)", format(as.integer(n), big.mark = ",", trim = TRUE), 100 * n / max(den, 1))
}
.p_cont <- function(x, g) {
  tryCatch(stats::wilcox.test(x[g == 1], x[g == 0])$p.value, error = function(e) NA_real_)
}
.p_cat <- function(f, g) {
  tab <- table(f, g, useNA = "no")
  if (nrow(tab) < 2L || ncol(tab) < 2L) return(NA_real_)
  tryCatch(
    suppressWarnings(stats::chisq.test(tab)$p.value),
    error = function(e) tryCatch(stats::fisher.test(tab)$p.value, error = function(e2) NA_real_)
  )
}
.fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  s <- if (exists("pub_format_p", mode = "function")) {
    pub_format_p(p)
  } else if (p < 0.001) {
    "<0.001"
  } else {
    sprintf("%.3f", p)
  }
  if (is.finite(p) && p < 0.05) paste0("**", s, "**") else s
}

# is_level=TRUE → 子行（Excel 缩进）
empty_row <- function(var, tot = "", nc = "", ca = "", p = "", is_level = FALSE) {
  data.frame(
    Variables = var, Total = tot, `No cancer` = nc, Cancer = ca, P = p,
    .is_level = is_level,
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

rows <- list()

# —— 本课题合理顺序：Age → Sex → 社会人口 → 行为 → eGFR ——
rows[[length(rows) + 1L]] <- empty_row(
  "Age (years), median (Q25 %, Q75 %)",
  .fmt_med(df$Age),
  .fmt_med(df$Age[df$DN == 0]),
  .fmt_med(df$Age[df$DN == 1]),
  .fmt_p(.p_cont(df$Age, df$DN))
)

sex_order <- c("Female", "Male")
sex_order <- sex_order[sex_order %in% unique(df$Sex_show)]
p_sex <- .p_cat(factor(df$Sex_show, levels = sex_order), df$DN)
rows[[length(rows) + 1L]] <- empty_row("Sex, n (%)", "", "", "", .fmt_p(p_sex))
for (lv in sex_order) {
  hit <- df$Sex_show == lv
  rows[[length(rows) + 1L]] <- empty_row(
    lv,
    .fmt_n_pct(sum(hit), n_tot),
    .fmt_n_pct(sum(hit & df$DN == 0), n_nc),
    .fmt_n_pct(sum(hit & df$DN == 1), n_ca),
    "",
    is_level = TRUE
  )
}

.add_cat <- function(varname, label, order_levels = NULL, rename = NULL) {
  x <- trimws(as.character(df[[varname]]))
  x[is.na(x) | !nzchar(x)] <- "(Missing)"
  if (!is.null(rename) && length(rename)) {
    for (nm in names(rename)) x[x == nm] <- rename[[nm]]
  }
  lev <- if (!is.null(order_levels)) {
    want <- vapply(order_levels, function(z) {
      if (!is.null(rename) && z %in% names(rename)) rename[[z]] else z
    }, character(1))
    intersect(unname(want), unique(x))
  } else {
    setdiff(unique(x), "(Missing)")
  }
  lev <- setdiff(lev, "(Missing)")
  if (!length(lev)) return(invisible(NULL))
  p <- .p_cat(factor(x, levels = lev), df$DN)
  rows[[length(rows) + 1L]] <<- empty_row(paste0(label, ", n (%)"), "", "", "", .fmt_p(p))
  for (lv in lev) {
    hit <- x == lv
    rows[[length(rows) + 1L]] <<- empty_row(
      lv,
      .fmt_n_pct(sum(hit), n_tot),
      .fmt_n_pct(sum(hit & df$DN == 0), n_nc),
      .fmt_n_pct(sum(hit & df$DN == 1), n_ca),
      "",
      is_level = TRUE
    )
  }
  invisible(NULL)
}

.add_cat(
  "Race", "Race/ethnicity",
  order_levels = c(
    "Mexican American", "Other Hispanic", "Non-Hispanic White",
    "Non-Hispanic Black", "Other Race"
  )
)
.add_cat(
  "Education", "Education",
  order_levels = c("Non-higher education", "Higher education")
)
.add_cat("Marital_Status", "Marital status", order_levels = c("Married", "Unmarried"))
.add_cat("PIR_cat", "Poverty income ratio", order_levels = c("< 1.3", "1.3-3.5", "> 3.5"))
.add_cat(
  "BMI_cat", "BMI",
  order_levels = c("Normal", "Overweight_or_Obese"),
  rename = c(Overweight_or_Obese = "Overweight or obese")
)
.add_cat("Alcohol_drinking", "Alcohol drinking", order_levels = c("No", "Yes"))
.add_cat("Smoke", "Smoking status", order_levels = c("Never", "Former", "Current"))

# eGFR 放实验室末行（不照搬 Dong 首行）
rows[[length(rows) + 1L]] <- empty_row(
  "eGFR (mL/min/1.73 m\u00b2), median (Q25 %, Q75 %)",
  .fmt_med(df$eGFR),
  .fmt_med(df$eGFR[df$DN == 0]),
  .fmt_med(df$eGFR[df$DN == 1]),
  .fmt_p(.p_cont(df$eGFR, df$DN))
)

raw <- do.call(rbind, rows)
is_level <- as.logical(raw$.is_level)
body <- raw[, setdiff(names(raw), ".is_level"), drop = FALSE]
colnames(body) <- c(
  "Variables",
  sprintf("Total (n = %s)", format(n_tot, big.mark = ",", trim = TRUE)),
  sprintf("No cancer (n = %s)", format(n_nc, big.mark = ",", trim = TRUE)),
  sprintf("Cancer (n = %s)", format(n_ca, big.mark = ",", trim = TRUE)),
  "P"
)

# 展示层：子行前加可见缩进空格（CSV）；xlsx 再用 alignment indent
body_disp <- body
body_disp$Variables[is_level] <- paste0("    ", body_disp$Variables[is_level])

hdr <- as.data.frame(as.list(colnames(body_disp)), stringsAsFactors = FALSE)
names(hdr) <- colnames(body_disp)
tbl_df_new <- rbind(hdr, body_disp)

title <- "Table 1. Baseline characteristics of the study population by cancer status"
footnotes <- c(
  "Values are median (Q25 %, Q75 %) for continuous variables and n (%) for categorical variables.",
  "P values compare cancer vs no cancer (Wilcoxon rank-sum or chi-square / Fisher exact tests). Bold indicates P < 0.05.",
  "Unweighted counts in the analytic sample after urinary creatinine and WTSA2YR filters.",
  "Missing categories are omitted from percentage denominators within each variable."
)

write_table1_xlsx_guan_style(
  tbl_df = body_disp,
  filepath = out_xlsx,
  title = title,
  footnotes = footnotes,
  prebuilt = list(
    df = tbl_df_new,
    insert_map = NULL,
    level_row_idx = integer(0), # 勿居中；子行用左对齐 + indent
    ncol = ncol(tbl_df_new)
  )
)

if (exists("pub_xlsx_strip", mode = "function")) {
  try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  # 子行：Excel 缩进（indent=2）+ 左对齐，挂在「Sex, n (%)」这类变量名下
  level_style <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "left", indent = 2L
  )
  bold_p <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "center", textDecoration = "bold"
  )
  italic_p_hdr <- openxlsx::createStyle(
    fontSize = 12, fontName = "Times New Roman",
    halign = "center", textDecoration = c("bold", "italic"),
    border = c("top", "bottom"), borderStyle = c("thick", "thin")
  )
  openxlsx::addStyle(wb, sh, style = italic_p_hdr, rows = 2L, cols = 5L, gridExpand = FALSE)

  for (i in seq_len(nrow(body_disp))) {
    excel_row <- 2L + i
    if (isTRUE(is_level[[i]])) {
      # 写入无前导空格的水平名，靠 indent 缩进（避免空格被吃掉仍看不见）
      openxlsx::writeData(
        wb, sh, x = as.character(body$Variables[[i]]),
        startRow = excel_row, startCol = 1L, colNames = FALSE
      )
      openxlsx::addStyle(wb, sh, style = level_style, rows = excel_row, cols = 1L, gridExpand = FALSE)
    }
    pv <- as.character(body_disp$P[[i]])
    if (grepl("^\\*\\*", pv)) {
      clean <- gsub("^\\*\\*|\\*\\*$", "", pv)
      openxlsx::writeData(wb, sh, x = clean, startRow = excel_row, startCol = 5L, colNames = FALSE)
      openxlsx::addStyle(wb, sh, style = bold_p, rows = excel_row, cols = 5L, gridExpand = FALSE)
    }
  }
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) {
    try(pub_xlsx_strip(out_xlsx), silent = TRUE)
  }
}

body_csv <- body_disp
body_csv$P <- gsub("^\\*\\*|\\*\\*$", "", body_csv$P)
utils::write.csv(body_csv, src_csv, row.names = FALSE)
exwas_log("写完 ", out_xlsx)
exwas_log("行序: Age → Sex → Race → Education → Marital → PIR → BMI → Alcohol → Smoke → eGFR")
exwas_log("分类子行数=", sum(is_level))
exwas_log("DONE")
