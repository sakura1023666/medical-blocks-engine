#!/usr/bin/env Rscript
# Table 3 — Ma 2026 three-level header:
#   Reference group: C3 | C2
#   Comparison group: C1 | C2 | C1
#   OR | 95% CI | P × 3
# Stub: Category | Level; reference levels marked 0b.

suppressPackageStartupMessages({
  library(openxlsx)
  library(nnet)
})

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b
.na_cell <- "-"
.fmt_p <- function(p) {
  if (!is.finite(p)) return(.na_cell)
  if (p < 0.001) "<0.001" else formatC(p, format = "f", digits = 3)
}
.fmt_est <- function(x, d = 3L) {
  if (!is.finite(x)) return(.na_cell)
  formatC(x, format = "f", digits = d)
}

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}
path <- file.path(proj, "summary_results/Tables/Table 3. Multivariate analysis of LCA membership.xlsx")
dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

ck5 <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck5$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), , drop = FALSE]
d0$Class <- factor(paste0("C", as.integer(d0$LCA_class)), levels = c("C1", "C2", "C3"))
.as_chr <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(trimws(x))] <- NA_character_
  x
}
age <- suppressWarnings(as.numeric(d0$age))
d0$Age_bin <- cut(
  age, breaks = c(-Inf, 30, 45, 60, 80, Inf),
  labels = c("< 30", "30-44", "45-59", "60-79", ">= 80"), right = FALSE
)
mar <- .as_chr(d0$marriage)
mar[mar %in% c("seperated", "separated", "others")] <- "Other"
mar[mar == "single"] <- "Unmarried"
mar[mar == "married"] <- "Married"
mar[mar == "divorced"] <- "Divorced"
mar[mar == "widowed"] <- "Widowed"
d0$Marriage <- factor(mar, levels = c("Unmarried", "Married", "Divorced", "Widowed", "Other"))
edu <- .as_chr(d0$education)
edu[edu == "primary school"] <- "Primary school and below"
edu[edu == "middle school"] <- "Junior high school"
edu[edu == "high school"] <- "Senior high school"
edu[edu == "university or higher"] <- "College degree or above"
d0$Education <- factor(
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
d0$Occupation <- factor(occ, levels = c("Employed", "Housewife", "Retired", "Student", "Unemployed", "Other"))
liv <- .as_chr(d0$livingsite)
liv[liv == "city"] <- "City"
liv[liv == "country"] <- "Rural"
liv[is.na(liv)] <- "Other"
d0$Residence <- factor(liv, levels = c("City", "Rural", "Other"))
ssd <- .as_chr(d0$SSD)
ssd[ssd == "yes"] <- "Yes"
ssd[ssd == "no"] <- "No"
d0$SSD_dx <- factor(ssd, levels = c("No", "Yes"))
d0$Department <- factor(.as_chr(d0$department))

pred_vars <- c("Age_bin", "Marriage", "Education", "Occupation", "Residence", "SSD_dx", "Department")
dd <- d0[, c("Class", pred_vars), drop = FALSE]
dd <- dd[stats::complete.cases(dd), , drop = FALSE]
if (sum(dd$Residence == "Other", na.rm = TRUE) < 5L) {
  dd <- dd[dd$Residence != "Other", , drop = FALSE]
  dd$Residence <- droplevels(dd$Residence)
}

.fit_block <- function(data, ref_level, contrasts) {
  data$Class <- stats::relevel(data$Class, ref = ref_level)
  form <- stats::as.formula(paste("Class ~", paste(pred_vars, collapse = " + ")))
  fit <- nnet::multinom(form, data = data, trace = FALSE, maxit = 300)
  sm <- summary(fit)
  cf <- sm$coefficients
  se <- sm$standard.errors
  out <- list()
  for (cmp in contrasts) {
    if (!cmp %in% rownames(cf)) next
    beta <- cf[cmp, ]
    s <- se[cmp, ]
    z <- beta / s
    p <- 2 * stats::pnorm(-abs(z))
    out[[cmp]] <- data.frame(
      term = names(beta), OR = exp(beta), lo = exp(beta - 1.96 * s),
      hi = exp(beta + 1.96 * s), P = p, stringsAsFactors = FALSE
    )
  }
  out
}
b_c3 <- .fit_block(dd, "C3", c("C1", "C2"))
b_c2 <- .fit_block(dd, "C2", c("C1"))

lab_of <- function(v) {
  switch(
    v,
    Age_bin = "Age (years)", Marriage = "Marriage status", Education = "Educational level",
    Occupation = "Occupation", Residence = "Residence", SSD_dx = "SSD diagnosis",
    Department = "Department", v
  )
}
.cell <- function(block, cmp, term) {
  empty <- c(OR = .na_cell, CI = .na_cell, P = .na_cell)
  if (is.null(block[[cmp]])) return(empty)
  j <- match(term, block[[cmp]]$term)
  if (is.na(j)) return(empty)
  w <- block[[cmp]][j, , drop = FALSE]
  c(
    OR = .fmt_est(w$OR),
    CI = paste0(.fmt_est(w$lo), "-", .fmt_est(w$hi)),
    P = .fmt_p(w$P)
  )
}

rows <- list()
for (v in pred_vars) {
  lab <- lab_of(v)
  lvs <- levels(dd[[v]])
  ref_lv <- lvs[[1]]
  show_lvs <- c(setdiff(lvs, ref_lv), ref_lv)
  for (k in seq_along(show_lvs)) {
    lv <- show_lvs[[k]]
    is_ref <- identical(lv, ref_lv)
    term <- paste0(v, lv)
    if (is_ref) {
      c13 <- c23 <- c12 <- c(OR = "0b", CI = "", P = "")
    } else {
      c13 <- .cell(b_c3, "C1", term)
      c23 <- .cell(b_c3, "C2", term)
      c12 <- .cell(b_c2, "C1", term)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      Category = if (k == 1L) lab else "",
      Level = lv,
      OR1 = c13[["OR"]], CI1 = c13[["CI"]], P1 = c13[["P"]],
      OR2 = c23[["OR"]], CI2 = c23[["CI"]], P2 = c23[["P"]],
      OR3 = c12[["OR"]], CI3 = c12[["CI"]], P3 = c12[["P"]],
      stringsAsFactors = FALSE
    )
  }
}
body <- do.call(rbind, rows)
nc <- 11L

wb <- createWorkbook()
addWorksheet(wb, "Sheet1", gridLines = FALSE)
title <- "Table 3. Results of multivariate analysis."
writeData(wb, 1, title, startRow = 1, startCol = 1)
mergeCells(wb, 1, cols = 1:nc, rows = 1)

r_ref <- 2L
r_cmp <- 3L
r_met <- 4L
body_start <- 5L
hdr <- matrix("", 3L, nc)
hdr[1, 1] <- "Reference group"
hdr[1, 3] <- "C3"
hdr[1, 9] <- "C2"
hdr[2, 1] <- "Comparison group"
hdr[2, 3] <- "C1"
hdr[2, 6] <- "C2"
hdr[2, 9] <- "C1"
hdr[3, 3:11] <- c("OR", "95% CI", "P", "OR", "95% CI", "P", "OR", "95% CI", "P")
writeData(wb, 1, as.data.frame(hdr, stringsAsFactors = FALSE), startRow = r_ref, startCol = 1, colNames = FALSE)
writeData(wb, 1, body, startRow = body_start, startCol = 1, colNames = FALSE)
body_end <- body_start + nrow(body) - 1L

mergeCells(wb, 1, cols = 3:8, rows = r_ref)
mergeCells(wb, 1, cols = 9:11, rows = r_ref)
mergeCells(wb, 1, cols = 3:5, rows = r_cmp)
mergeCells(wb, 1, cols = 6:8, rows = r_cmp)
mergeCells(wb, 1, cols = 9:11, rows = r_cmp)

i <- 1L
while (i <= nrow(body)) {
  if (!nzchar(body$Category[[i]])) {
    i <- i + 1L
    next
  }
  j <- i
  while (j < nrow(body) && !nzchar(body$Category[[j + 1L]])) j <- j + 1L
  if (j > i) mergeCells(wb, 1, cols = 1, rows = (body_start + i - 1L):(body_start + j - 1L))
  i <- j + 1L
}

.font <- "Times New Roman"
sty_title <- createStyle(fontName = .font, fontSize = 12, textDecoration = "bold", halign = "left")
sty_h_top <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "center", valign = "center", border = "top", borderStyle = "thick"
)
sty_h_mid <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "center", valign = "center"
)
sty_h_bot <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "center", valign = "center", border = "bottom", borderStyle = "thin"
)
sty_h_left <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "left", valign = "center", border = "top", borderStyle = "thick"
)
sty_h_left2 <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "left", valign = "center"
)
sty_h_left3 <- createStyle(
  fontName = .font, fontSize = 11, textDecoration = "bold",
  halign = "left", valign = "center", border = "bottom", borderStyle = "thin"
)
sty_body_l <- createStyle(fontName = .font, fontSize = 11, halign = "left", valign = "top")
sty_body_c <- createStyle(fontName = .font, fontSize = 11, halign = "center", valign = "center")
sty_bot_l <- createStyle(
  fontName = .font, fontSize = 11, halign = "left", valign = "top",
  border = "bottom", borderStyle = "thick"
)
sty_bot_c <- createStyle(
  fontName = .font, fontSize = 11, halign = "center",
  border = "bottom", borderStyle = "thick"
)
sty_ft <- createStyle(fontName = .font, fontSize = 10, halign = "left", wrapText = TRUE)

addStyle(wb, 1, sty_title, rows = 1, cols = 1:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_h_left, rows = r_ref, cols = 1:2, gridExpand = TRUE)
addStyle(wb, 1, sty_h_top, rows = r_ref, cols = 3:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_h_left2, rows = r_cmp, cols = 1:2, gridExpand = TRUE)
addStyle(wb, 1, sty_h_mid, rows = r_cmp, cols = 3:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_h_left3, rows = r_met, cols = 1:2, gridExpand = TRUE)
addStyle(wb, 1, sty_h_bot, rows = r_met, cols = 3:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_body_l, rows = body_start:body_end, cols = 1:2, gridExpand = TRUE)
addStyle(wb, 1, sty_body_c, rows = body_start:body_end, cols = 3:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_bot_l, rows = body_end, cols = 1:2, gridExpand = TRUE, stack = TRUE)
addStyle(wb, 1, sty_bot_c, rows = body_end, cols = 3:nc, gridExpand = TRUE, stack = TRUE)

fts <- c(
  "C1 / C2 / C3 = LCA classes from WHO-DAS items. b Reference level (OR = 1).",
  sprintf("Analytic n = %s. Multinomial logistic regression (nnet::multinom).", format(nrow(dd), big.mark = ","))
)
for (k in seq_along(fts)) {
  rr <- body_end + k
  writeData(wb, 1, fts[[k]], startRow = rr, startCol = 1)
  mergeCells(wb, 1, cols = 1:nc, rows = rr)
  addStyle(wb, 1, sty_ft, rows = rr, cols = 1:nc, gridExpand = TRUE)
}

setColWidths(wb, 1, cols = 1, widths = 22)
setColWidths(wb, 1, cols = 2, widths = 26)
setColWidths(wb, 1, cols = 3:11, widths = 11)
setRowHeights(wb, 1, rows = r_ref:r_met, heights = 18)
saveWorkbook(wb, path, overwrite = TRUE)

py <- Sys.which("python3")
script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
if (nzchar(py) && file.exists(script)) {
  invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
}
message("wrote ", path)
