#!/usr/bin/env Rscript
# =============================================================================
#  三库 UHR 发病主结果汇总：从各库 Table 2 抽取 OR → 汇总表 + 森林图
#  用法（项目根）:
#    Rscript run/hearing_loss_uhr/summarize_hearing_uhr_triple.R
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("readxl", quietly = TRUE)) stop("需要 readxl")
  if (!requireNamespace("writexl", quietly = TRUE) && !requireNamespace("openxlsx", quietly = TRUE)) {
    message("未装 writexl/openxlsx：仍写 CSV；建议 install.packages('writexl')")
  }
})

study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
if (!dir.exists(study)) study <- "G:/02block_result/15_hearing_loss/incidence_38341157"
out_dir <- file.path(study, "by_index", "UHR_triple_summary")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

paths <- c(
  NHANES = file.path(
    study, "by_index", "【success】UHR", "Tables",
    "Table 2-NHANES. Weighted logistic regression of UHR and hearing loss (NHANES quartile, svyglm).xlsx"
  ),
  CHARLS = file.path(
    study, "by_index", "【success】UHR", "Tables",
    "Table 2-CHARLS. Logistic regression analysis of UHR and hearing loss - quartile (GLM).xlsx"
  ),
  Single = file.path(
    study, "by_index", "【success】UHR", "Single", "Tables",
    "Table 2-Single. Logistic regression analysis of UHR and hearing loss - quartile (GLM).xlsx"
  )
)
stopifnot(all(file.exists(paths)))

parse_t2 <- function(path, db) {
  raw <- as.data.frame(readxl::read_excel(path, sheet = 1, col_names = FALSE),
                       stringsAsFactors = FALSE)
  out <- list()
  for (i in seq_len(nrow(raw))) {
    lab <- trimws(as.character(raw[i, 1]))
    if (is.na(lab) || !nzchar(lab)) next
    if (grepl("continuous", lab, ignore.case = TRUE)) {
      key <- "continuous"
    } else if (grepl("Q1", lab)) {
      key <- "Q1"
    } else if (grepl("Q2", lab)) {
      key <- "Q2"
    } else if (grepl("Q3", lab)) {
      key <- "Q3"
    } else if (grepl("Q4", lab)) {
      key <- "Q4"
    } else if (grepl("p for trend", lab, ignore.case = TRUE)) {
      key <- "p_trend"
    } else {
      next
    }
    get3 <- function(c0) {
      c(
        or = trimws(as.character(raw[i, c0])),
        ci = trimws(as.character(raw[i, c0 + 1L])),
        p  = trimws(as.character(raw[i, c0 + 2L]))
      )
    }
    crude <- get3(4L); m1 <- get3(7L); m2 <- get3(10L)
    out[[length(out) + 1L]] <- data.frame(
      database = db,
      term = key,
      cutoff = trimws(as.character(raw[i, 2])),
      case_pct = trimws(as.character(raw[i, 3])),
      crude_or = crude[["or"]], crude_ci = crude[["ci"]], crude_p = crude[["p"]],
      m1_or = m1[["or"]], m1_ci = m1[["ci"]], m1_p = m1[["p"]],
      m2_or = m2[["or"]], m2_ci = m2[["ci"]], m2_p = m2[["p"]],
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}

parse_ci <- function(ci) {
  if (is.null(ci) || is.na(ci) || !nzchar(ci) || identical(ci, "Ref") || identical(ci, "NA")) {
    return(c(NA_real_, NA_real_))
  }
  s <- gsub("[()]", "", ci)
  parts <- strsplit(s, ",", fixed = TRUE)[[1L]]
  if (length(parts) < 2L) return(c(NA_real_, NA_real_))
  c(as.numeric(parts[1L]), as.numeric(parts[2L]))
}

parse_or <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x) || identical(x, "Ref")) return(NA_real_)
  as.numeric(x)
}

tab <- do.call(rbind, lapply(names(paths), function(nm) parse_t2(paths[[nm]], nm)))
rownames(tab) <- NULL

# long form for plotting Model2 quartile
plot_df <- subset(tab, term %in% c("Q2", "Q3", "Q4"))
plot_df$or <- vapply(plot_df$m2_or, parse_or, numeric(1))
ci_mat <- t(vapply(plot_df$m2_ci, parse_ci, numeric(2)))
plot_df$lo <- ci_mat[, 1]
plot_df$hi <- ci_mat[, 2]
plot_df$database <- factor(plot_df$database, levels = c("NHANES", "CHARLS", "Single"))
plot_df$term <- factor(plot_df$term, levels = c("Q4", "Q3", "Q2"))

# notes
notes <- data.frame(
  item = c(
    "NHANES_weight",
    "UHR_formula",
    "Model2_NHANES_CHARLS",
    "Model2_Single",
    "Caveat"
  ),
  detail = c(
    "auto_new_weight: UHR 非空腹 → WTMEC；5 周期；1999-2000/2001-2002 用 WTMEC4YR*(2/5)，其余 WTMEC2YR*(1/5)；svydesign(~SDMVPSU, strata=~SDMVSTRA, weights=~new_Weight, nest=TRUE)",
    "UHR = Uric_Acid / HDL（mg/dL）；李玲尿酸/59.48、HDL<=10 时 *38.67",
    "Age, Gender, BUN, Creatinine, Height, Hematocrit, Hypertension, LDL(部分), Marital_Status, Platelet_Count, TC/TG(部分), WBC, Weight（以各库 Table2 脚注为准）",
    "Age, Marital_Status, WBC, Platelet_Count, Hypertension（VIF 后子集，⊆ lock）",
    "三库非同一调整集；勿做个体水平混合；连续 OR 尺度大，主图用四分位 Q2–Q4 vs Q1"
  ),
  stringsAsFactors = FALSE
)

csv_path <- file.path(out_dir, "Table_triple_UHR_logistic_summary.csv")
write.csv(tab, csv_path, row.names = FALSE, fileEncoding = "UTF-8")
write.csv(notes, file.path(out_dir, "Notes_methods.csv"), row.names = FALSE, fileEncoding = "UTF-8")

xlsx_path <- file.path(out_dir, "Table_triple_UHR_logistic_summary.xlsx")
if (requireNamespace("writexl", quietly = TRUE)) {
  writexl::write_xlsx(list(OR_summary = tab, Notes = notes), xlsx_path)
} else if (requireNamespace("openxlsx", quietly = TRUE)) {
  openxlsx::write.xlsx(list(OR_summary = tab, Notes = notes), xlsx_path)
}

# Forest plot (base R, no extra deps)
pdf_path <- file.path(out_dir, "Figure_triple_UHR_quartile_Model2_forest.pdf")
png_path <- file.path(out_dir, "Figure_triple_UHR_quartile_Model2_forest.png")

draw_forest <- function() {
  dbs <- levels(plot_df$database)
  terms <- c("Q2", "Q3", "Q4")
  n_row <- length(dbs) * length(terms)
  ypos <- seq_len(n_row)
  # order: NHANES Q4,Q3,Q2, CHARLS..., Liling...
  ord <- expand.grid(term = rev(terms), database = dbs, stringsAsFactors = FALSE)
  ord$y <- rev(seq_len(nrow(ord)))
  m <- merge(plot_df, ord, by = c("database", "term"))
  m <- m[order(m$y), ]

  xlim <- c(0.4, max(m$hi, na.rm = TRUE) * 1.15)
  xlim[2] <- max(xlim[2], 4)
  op <- par(mar = c(5, 10, 3, 8))
  on.exit(par(op), add = TRUE)
  plot(NA, xlim = xlim, ylim = c(0.5, n_row + 0.5), log = "x",
       xlab = "Model 2 OR (95% CI), Q vs Q1", ylab = "",
       yaxt = "n", main = "UHR quartile vs hearing loss — three databases")
  abline(v = 1, lty = 2, col = "gray40")
  cols <- c(NHANES = "#1B4F72", CHARLS = "#117A65", Single = "#B9770E")
  for (i in seq_len(nrow(m))) {
    yi <- m$y[i]
    segments(m$lo[i], yi, m$hi[i], yi, col = cols[as.character(m$database[i])], lwd = 2)
    points(m$or[i], yi, pch = 15, cex = 1.2, col = cols[as.character(m$database[i])])
  }
  axis(2, at = m$y, labels = paste(m$database, m$term), las = 1, cex.axis = 0.85)
  # right-side OR text
  labs <- sprintf("%.2f (%.2f–%.2f)", m$or, m$lo, m$hi)
  text(xlim[2], m$y, labels = labs, pos = 2, cex = 0.7, xpd = NA)
  legend("bottomright", legend = names(cols), col = cols, pch = 15, bty = "n", cex = 0.85)
  mtext("Footnote: Model2 covariates differ (Single n=411 vs dual ~12–14). NHANES weighted.",
        side = 1, line = 3.8, cex = 0.7, adj = 0)
}

pdf(pdf_path, width = 8.5, height = 6)
draw_forest()
dev.off()

png(png_path, width = 1100, height = 780, res = 140)
draw_forest()
dev.off()

# cohort snapshot
cohort <- data.frame(
  database = c("NHANES", "CHARLS", "Single"),
  n_analysis = c(6029, 7230, 411),
  events_HL_approx = c(1755, 3330, 228),
  uhr_median = c(0.1057, 0.0892, 0.1001),
  weighted = c(TRUE, FALSE, FALSE),
  stringsAsFactors = FALSE
)
write.csv(cohort, file.path(out_dir, "Table_triple_cohort_snapshot.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

message("Wrote:\n  ", csv_path, "\n  ", xlsx_path, "\n  ", pdf_path, "\n  ", png_path)
