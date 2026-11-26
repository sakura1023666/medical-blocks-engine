#!/usr/bin/env Rscript
# Table S5 → 对齐 Dong Supplementary Table 5 三线表：
# Variable | Inclusion frequency | Mean coefficient | Coefficient sd
#
#   Rscript run/environment_exwas/rebuild_pancancer_table_s5_dong_style.R
#
opt <- list(
  root = "/mnt/g/02block_result/58_cancer/environment_41380607",
  data_dir = "/mnt/g/02block_result/58_cancer/environment_41380607/data"
)
ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
repo <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(repo)
source(file.path(repo, "R/utils.R"))
if (file.exists(file.path(repo, "R/pub_xlsx_surgical.R"))) {
  source(file.path(repo, "R/pub_xlsx_surgical.R"))
}

root <- opt$root
src_tab <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "Tables")
out_ds <- file.path(root, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "_downstream")
sum_tab <- file.path(root, "summary_results", "Tables")
exwas_log <- function(...) message("[exwas] ", paste0(..., collapse = ""))

csv <- file.path(out_ds, "Table_S5_ERS_bootstrap_inclusion.csv")
if (!file.exists(csv)) stop("缺少 ", csv)
raw <- utils::read.csv(csv, stringsAsFactors = FALSE, check.names = FALSE)

fam <- utils::read.csv(file.path(opt$data_dir, "toxicant_family_map.csv"), stringsAsFactors = FALSE)
lab_map <- stats::setNames(as.character(fam$Exposure), as.character(fam$Labels))

.disp_tox <- function(code) {
  raw_code <- sub("_(ln|bin)$", "", as.character(code))
  nm <- unname(lab_map[raw_code])
  if (is.na(nm) || !nzchar(nm)) nm <- raw_code
  # Dong 风格：2-Naphthol / o-Toluidine；把下划线展示名收成可读
  nm <- gsub("_", " ", nm, fixed = TRUE)
  # 常见别名贴近原文写法
  nm <- sub("^Aminonaphthalene 1$", "1-Aminonaphthalene", nm)
  nm <- sub("^Aminonaphthalene 2$", "2-Aminonaphthalene", nm)
  nm <- sub("^Aminobiphenyl 4$", "4-Aminobiphenyl", nm)
  nm <- sub("^Anisidine o$", "o-Anisidine", nm)
  nm <- sub("^Toluidine o$", "o-Toluidine", nm)
  nm <- sub("^Napthol 1$", "1-Naphthol", nm)
  nm <- sub("^Napthol 2$", "2-Naphthol", nm)
  nm <- sub("^Total Cotinine$", "Total Cotinine", nm)
  if (exists("pipeline_display_label", mode = "function")) {
    nm <- pipeline_display_label(nm)
  }
  nm
}

.disp_covar <- function(v) {
  v <- as.character(v)
  v <- gsub("^Gender \\(", "Sex (", v)
  v <- gsub("^PIR_cat", "Poverty", v)
  v <- gsub("^PIR cat", "Poverty", v)
  v <- gsub("^Marital_Status", "Marital", v)
  v <- gsub("^Marital Status", "Marital", v)
  v <- gsub("^BMI_cat", "BMI", v)
  v <- gsub("^BMI cat", "BMI", v)
  v <- gsub("^Alcohol_drinking", "Alcohol use", v)
  v <- gsub("^Alcohol drinking", "Alcohol use", v)
  v <- gsub("_", " ", v, fixed = TRUE)
  # 去多余空格；水平标签括号内尾空格
  v <- gsub("\\(\\s+", "(", v)
  v <- gsub("\\s+\\)", ")", v)
  v <- gsub("\\s+", " ", trimws(v))
  v
}

.fmt_freq <- function(x) {
  x <- as.numeric(x)
  vapply(x, function(z) {
    if (!is.finite(z)) return("")
    if (abs(z - 1) < 1e-12) return("1")
    if (abs(z) < 1e-12) return("0")
    sprintf("%.3f", z)
  }, character(1))
}
.fmt_coef <- function(x) {
  x <- as.numeric(x)
  vapply(x, function(z) {
    if (!is.finite(z)) return("")
    sprintf("%.3f", z)
  }, character(1))
}

var_col <- if ("variable" %in% names(raw)) "variable" else "exposure"
type_col <- if ("var_type" %in% names(raw)) raw$var_type else {
  ifelse(grepl("_(ln|bin)$", raw[[var_col]]), "toxicant", "covariate")
}
freq <- as.numeric(raw$inclusion_freq)
mean_c <- as.numeric(raw$mean_coefficient)
sd_c <- as.numeric(raw$coefficient_sd)

# 交付表：协变量全保留；毒物只留 inclusion_freq>0（零入选行不进发表表）
keep <- (type_col == "covariate") | (is.finite(freq) & freq > 0)
n_drop <- sum(!keep, na.rm = TRUE)
raw <- raw[keep, , drop = FALSE]
type_col <- type_col[keep]
freq <- freq[keep]
mean_c <- mean_c[keep]
sd_c <- sd_c[keep]
exwas_log("S5 Dong：保留 ", nrow(raw), " 行（去掉零入选毒物 ", n_drop, "）")

lab <- character(nrow(raw))
for (i in seq_len(nrow(raw))) {
  if (identical(type_col[[i]], "toxicant") || grepl("_(ln|bin)$", raw[[var_col]][i])) {
    lab[i] <- .disp_tox(raw[[var_col]][i])
  } else {
    lab[i] <- .disp_covar(raw[[var_col]][i])
  }
}

body <- data.frame(
  Variable = lab,
  `Inclusion frequency` = .fmt_freq(freq),
  `Mean coefficient` = .fmt_coef(mean_c),
  `Coefficient sd` = .fmt_coef(sd_c),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
# 纳入频率降序；同频时协变量在前（对齐原文 Sex/Age/Poverty 置顶）
type_rank <- ifelse(type_col == "covariate", 0L, 1L)
ord <- order(-freq, type_rank, lab)
body <- body[ord, , drop = FALSE]
freq <- freq[ord]
type_ord <- type_col[ord]

n_tot <- nrow(body)
n_cov <- sum(type_ord == "covariate", na.rm = TRUE)
n_tox <- sum(type_ord == "toxicant", na.rm = TRUE)
n_ers <- if ("selected_in_ERS" %in% names(raw)) {
  sum(as.logical(raw$selected_in_ERS[ord]), na.rm = TRUE)
} else NA_integer_

title <- "Table S5. Bootstrap Inclusion Frequencies and Coefficient Distributions of Variables."
footnotes <- c(
  "Adaptive elastic-net (gcdnet) with toxicants and locked Model 2 covariates entered jointly; α fixed at 0.9; B = 1000 bootstrap resamples.",
  "Model 2 covariates entered with light penalty (penalty factor = 0.01): Gender, Race, PIR category, Alcohol drinking, eGFR (Age and dental variables not included, per pan-cancer protocol).",
  "Inclusion frequency = proportion of bootstrap fits with non-zero coefficient at the selected penalty; mean/sd of coefficients across bootstraps.",
  sprintf(
    "Rows with inclusion frequency > 0 are shown (zero-frequency toxicants omitted). Rows = %d (%d covariate + %d toxicant). ERS is scored from toxicant coefficients only (n selected = %s).",
    n_tot, n_cov, n_tox, if (is.finite(n_ers)) as.character(n_ers) else "NA"
  )
)

dir.create(sum_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(src_tab, recursive = TRUE, showWarnings = FALSE)
out_xlsx <- file.path(sum_tab, "Table S5. ERS bootstrap inclusion and selection.xlsx")
# 交付面：单表三线；内部仍可留 flat csv
utils::write.csv(body, file.path(src_tab, "Table S5. ERS bootstrap inclusion Dong layout.csv"),
                 row.names = FALSE)

sci_xlsx_single_header_booktabs(
  filepath = out_xlsx,
  title = title,
  df_body = body,
  sheet = "Table S5",
  footnotes = footnotes
)
if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)

# 列宽
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::loadWorkbook(out_xlsx)
  sh <- openxlsx::sheets(wb)[[1]]
  openxlsx::setColWidths(wb, sh, cols = 1:4, widths = c(42, 18, 16, 14))
  # 数值列居中
  center <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "center"
  )
  left <- openxlsx::createStyle(
    fontSize = 11, fontName = "Times New Roman", halign = "left", wrapText = TRUE
  )
  # row1 title, row2 header, body from 3
  nr <- 2L + nrow(body)
  openxlsx::addStyle(wb, sh, left, rows = 3:nr, cols = 1, gridExpand = TRUE, stack = TRUE)
  openxlsx::addStyle(wb, sh, center, rows = 3:nr, cols = 2:4, gridExpand = TRUE, stack = TRUE)
  openxlsx::saveWorkbook(wb, out_xlsx, overwrite = TRUE)
  if (exists("pub_xlsx_strip", mode = "function")) try(pub_xlsx_strip(out_xlsx), silent = TRUE)
}

exwas_log("写完 ", out_xlsx)
exwas_log("行数=", n_tot, " 协变量列=", n_cov, " 毒物=", n_tox, " ERS入选=", n_ers)
exwas_log("DONE")
