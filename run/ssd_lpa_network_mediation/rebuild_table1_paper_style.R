#!/usr/bin/env Rscript
# Table 1 paper layout:
#   Col1 Category | Col2 level | All | C1 | C2 | C3 | χ²/H | P
# Category only on first level row (top-aligned / merged), χ²/H+P on that row.

suppressPackageStartupMessages({
  library(openxlsx)
})

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)

`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}

ck <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), , drop = FALSE]
d0$Class <- factor(paste0("C", as.integer(d0$LCA_class)), levels = c("C1", "C2", "C3"))
n_all <- nrow(d0)
message("n=", n_all)

.as_chr <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(trimws(x))] <- NA_character_
  x
}

d <- data.frame(Class = d0$Class, stringsAsFactors = FALSE)
age <- suppressWarnings(as.numeric(d0$age))
d$`Age (years)` <- cut(
  age, breaks = c(-Inf, 30, 45, 60, 80, Inf),
  labels = c("< 30", "30–44", "45–59", "60–79", "\u2265 80"), right = FALSE
)
d$Sex <- factor(.as_chr(d0$sex), levels = c("male", "female"), labels = c("Male", "Female"))

mar <- .as_chr(d0$marriage)
mar[mar %in% c("seperated", "separated", "others")] <- "Other"
mar[mar == "single"] <- "Unmarried"
mar[mar == "married"] <- "Married"
mar[mar == "divorced"] <- "Divorced"
mar[mar == "widowed"] <- "Widowed"
d$`Marriage status` <- factor(mar, levels = c("Unmarried", "Married", "Divorced", "Widowed", "Other"))

edu <- .as_chr(d0$education)
edu[edu == "primary school"] <- "Primary school and below"
edu[edu == "middle school"] <- "Junior high school"
edu[edu == "high school"] <- "Senior high school"
edu[edu == "university or higher"] <- "College degree or above"
d$`Educational level` <- factor(
  edu,
  levels = c("Primary school and below", "Junior high school", "Senior high school", "College degree or above")
)

occ <- .as_chr(d0$occupation)
occ[occ == "employed"] <- "Employed"
occ[occ == "housewife"] <- "Housewife"
occ[occ == "retire"] <- "Retired"
occ[occ == "student"] <- "Student"
occ[occ == "unemployed"] <- "Unemployed"
occ[occ == "others"] <- "Other"
d$Occupation <- factor(occ, levels = c("Employed", "Housewife", "Retired", "Student", "Unemployed", "Other"))

liv <- .as_chr(d0$livingsite)
liv[liv == "city"] <- "City"
liv[liv == "country"] <- "Rural"
liv[is.na(liv)] <- "Other"
d$Residence <- factor(liv, levels = c("City", "Rural", "Other"))

inc <- .as_chr(d0$income)
inc[!nzchar(inc) | is.na(inc)] <- NA_character_
inc[inc == "lower than 4000"] <- "< 4000"
inc[inc == "4000-8000"] <- "4000–8000"
inc[inc == "higher than 8000"] <- "> 8000"
d$`Family monthly income` <- factor(inc, levels = c("< 4000", "4000–8000", "> 8000"))

d$Center <- factor(.as_chr(d0$center))
d$Department <- factor(.as_chr(d0$department))
ssd <- .as_chr(d0$SSD)
ssd[ssd == "yes"] <- "Yes"; ssd[ssd == "no"] <- "No"
d$`SSD diagnosis` <- factor(ssd, levels = c("No", "Yes"))

.cut_score <- function(x, breaks, labels) {
  cut(suppressWarnings(as.numeric(x)), breaks = breaks, labels = labels, right = TRUE, include.lowest = TRUE)
}
d$`PHQ-15` <- .cut_score(d0$PHQ15, c(0, 4, 9, 14, Inf), c("0–4", "5–9", "10–14", "\u2265 15"))
d$`SSS-8` <- .cut_score(d0$SSS8, c(0, 3, 7, 11, Inf), c("0–3", "4–7", "8–11", "\u2265 12"))
d$`SSD-12` <- .cut_score(d0$SSD12, c(0, 11, 23, 35, Inf), c("0–11", "12–23", "24–35", "\u2265 36"))
d$`Whiteley-8` <- .cut_score(d0$Whiteley8, c(0, 7, 15, 23, Inf), c("0–7", "8–15", "16–23", "\u2265 24"))
d$`WHO-DAS` <- .cut_score(d0$WHODAS, c(0, 4, 9, 19, Inf), c("0–4", "5–9", "10–19", "\u2265 20"))
d$`PHQ-9` <- .cut_score(d0$PHQ9, c(0, 4, 9, 14, 19, Inf), c("0–4", "5–9", "10–14", "15–19", "\u2265 20"))
d$`GAD-7` <- .cut_score(d0$GAD7, c(0, 4, 9, 14, Inf), c("0–4", "5–9", "10–14", "\u2265 15"))

var_order <- c(
  "Age (years)", "Sex", "Marriage status", "Educational level", "Occupation",
  "Residence", "Family monthly income", "Center", "Department", "SSD diagnosis",
  "PHQ-15", "SSS-8", "SSD-12", "Whiteley-8", "WHO-DAS", "PHQ-9", "GAD-7"
)
var_order <- var_order[var_order %in% names(d)]

.fmt_n_pct <- function(n, denom) {
  sprintf("%s (%s)", format(as.integer(n), big.mark = ","),
          formatC(100 * n / max(denom, 1L), format = "f", digits = 2))
}
.fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) "<0.001" else formatC(p, format = "f", digits = 3)
}
.fmt_stat <- function(s) {
  if (!is.finite(s)) return("")
  formatC(s, format = "f", digits = 3)
}

.chi_p <- function(tab) {
  tab <- tab[rowSums(tab) > 0, colSums(tab) > 0, drop = FALSE]
  if (nrow(tab) < 2L || ncol(tab) < 2L) return(list(stat = NA_real_, p = NA_real_))
  chi <- suppressWarnings(tryCatch(stats::chisq.test(tab, correct = FALSE), error = function(e) NULL))
  stat <- if (!is.null(chi)) unname(chi$statistic) else NA_real_
  p <- NA_real_
  sparse <- !is.null(chi) && any(chi$expected < 5, na.rm = TRUE)
  if (isTRUE(sparse) || any(tab < 5L)) {
    ft <- tryCatch(
      stats::fisher.test(tab, simulate.p.value = TRUE, B = 5000, workspace = 2e8),
      error = function(e) NULL
    )
    if (!is.null(ft)) p <- ft$p.value else if (!is.null(chi)) p <- chi$p.value
  } else if (!is.null(chi)) p <- chi$p.value
  list(stat = as.numeric(stat), p = as.numeric(p))
}

rows <- list()
merge_spans <- list() # list of c(start_row, end_row) in data body (1-based within out)

for (v in var_order) {
  x <- d[[v]]
  keep <- !is.na(x) & !is.na(d$Class)
  x <- droplevels(factor(x[keep]))
  g <- droplevels(d$Class[keep])
  tab <- table(x, g)
  for (lv in levels(d$Class)) if (!lv %in% colnames(tab)) {
    tab <- cbind(tab, stats::setNames(0L, lv))
  }
  tab <- tab[, levels(d$Class), drop = FALSE]
  cp <- .chi_p(tab)
  n_v <- as.integer(sum(tab))
  levels_v <- rownames(tab)
  start_i <- length(rows) + 1L
  for (j in seq_along(levels_v)) {
    lv <- levels_v[[j]]
    first <- j == 1L
    rows[[length(rows) + 1L]] <- data.frame(
      Category = if (first) v else "",
      Level = lv,
      All = .fmt_n_pct(sum(tab[lv, ]), n_v),
      C1 = .fmt_n_pct(tab[lv, "C1"], sum(tab[, "C1"])),
      C2 = .fmt_n_pct(tab[lv, "C2"], sum(tab[, "C2"])),
      C3 = .fmt_n_pct(tab[lv, "C3"], sum(tab[, "C3"])),
      `χ²/H` = if (first) .fmt_stat(cp$stat) else "",
      P = if (first) .fmt_p(cp$p) else "",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  end_i <- length(rows)
  if (end_i > start_i) merge_spans[[length(merge_spans) + 1L]] <- c(start_i, end_i)
  message(v, " levels=", length(levels_v), " χ²=", .fmt_stat(cp$stat), " P=", .fmt_p(cp$p))
}

out <- do.call(rbind, rows)
# Display colnames = SCI header row (col2 blank under Category, paper stub)
colnames(out) <- c(
  "Category", " ",
  "All [Case (Percentage, %)]",
  "C1 [Case (Percentage, %)]",
  "C2 [Case (Percentage, %)]",
  "C3 [Case (Percentage, %)]",
  "χ²/H", "P"
)

title <- "Table 1. Sociodemographic and clinical characteristics of the participants"
ft <- c(
  paste0("N = ", format(n_all, big.mark = ","), " (LCA complete cases)."),
  "All variables are categorical (age and scale totals binned). Cells are n (%).",
  "χ²/H: chi-square on the first level row of each category; P from chi-square or Fisher (simulated) if sparse.",
  "Stub: Category | level (paper two-column layout)."
)

.enforce_three_line <- function(path) {
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
  if (!nzchar(py) || !file.exists(script) || !file.exists(path)) return(invisible(FALSE))
  st <- system2(py, c(script, path), stdout = TRUE, stderr = TRUE)
  message(paste(utils::tail(st, 2), collapse = " | "))
  invisible(TRUE)
}

.write_paper_t1 <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # Engine SCI three-line: thick/medium top + thin under header + thick/medium bottom; no verticals
  sci_xlsx_single_header_booktabs(
    filepath = path,
    title = title,
    df_body = out,
    sheet = "Sheet1",
    footnotes = ft,
    blank_na_cells = TRUE
  )

  # Merge Category cells (top-aligned) after booktabs write
  wb <- loadWorkbook(path)
  sh <- names(wb)[[1L]]
  # Layout from sci_xlsx: row1=title, row2=header, body starts row3
  body_start <- 3L
  sty_top <- createStyle(fontName = "Times New Roman", fontSize = 12, valign = "top", wrapText = TRUE)
  for (sp in merge_spans) {
    r1 <- body_start + sp[1] - 1L
    r2 <- body_start + sp[2] - 1L
    if (r2 > r1) {
      tryCatch(mergeCells(wb, sh, cols = 1, rows = r1:r2), error = function(e) NULL)
      addStyle(wb, sh, sty_top, rows = r1, cols = 1, stack = TRUE)
    }
  }
  setColWidths(wb, sh, cols = 1, widths = 24)
  setColWidths(wb, sh, cols = 2, widths = 28)
  setColWidths(wb, sh, cols = 3:6, widths = 22)
  setColWidths(wb, sh, cols = 7:8, widths = 10)
  setRowHeights(wb, sh, rows = 2L, heights = 36)
  saveWorkbook(wb, path, overwrite = TRUE)
  .enforce_three_line(path)
  message("wrote ", path)
}

out_name <- "Table 1-Hospital outpatient. Baseline characteristics of Somatic Symptom Disorder.xlsx"
paths <- c(
  file.path(proj, "summary_results/Tables", out_name),
  file.path(proj, "Tables", out_name),
  file.path(proj, "step05_baseline_multiclass/Tables", out_name)
)
for (fp in paths) .write_paper_t1(fp)

ws <- file.path(proj, "summary_results_delivery_workspace")
dir.create(ws, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(out, file.path(ws, "Table1_paper_two_col_stub.csv"), row.names = FALSE)

print(utils::head(out, 15))
message("DONE two-column Category | level layout")
