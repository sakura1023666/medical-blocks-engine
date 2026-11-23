#!/usr/bin/env Rscript
# Table 4 — paper header: Variable | full class name × 3 (no Overall/C1 shorthand)

suppressPackageStartupMessages(library(openxlsx))
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)

.na_cell <- "-"
.fmt_est <- function(x, d = 3L) {
  if (!is.finite(x)) return(.na_cell)
  formatC(x, format = "f", digits = d)
}
.fmt_vec <- function(x, d = 3L) vapply(x, function(v) .fmt_est(v, d), character(1))

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}

sr_tab <- file.path(proj, "summary_results/Tables")
net_dir <- file.path(proj, "step08_complex_network_profile_batch/Tables/Network")
path <- file.path(sr_tab, "Table 4. Comparison of node centrality (Strength).xlsx")
dir.create(sr_tab, recursive = TRUE, showWarnings = FALSE)

.read_cent <- function(tag) {
  x <- utils::read.csv(file.path(net_dir, paste0("Centrality_", tag, ".csv")), stringsAsFactors = FALSE)
  z <- as.numeric(scale(as.numeric(x$Strength)))
  data.frame(node = x$node, Strength_z = z, stringsAsFactors = FALSE)
}
c1 <- .read_cent("C1")
c2 <- .read_cent("C2")
c3 <- .read_cent("C3")
lab_map <- c(
  PHQ15 = "PHQ-15", SSS8 = "SSS-8", SSD12 = "SSD-12", Whiteley8 = "Whiteley-8",
  WHODAS = "WHO-DAS", PHQ9 = "PHQ-9", GAD7 = "GAD-7"
)
nodes <- c1$node
h_c1 <- "Low symptom–Low disability Group"
h_c2 <- "Moderate symptom–Moderate disability Group"
h_c3 <- "High symptom–High disability Group"

body <- data.frame(
  Variable = unname(lab_map[nodes]),
  check.names = FALSE, stringsAsFactors = FALSE
)
body[[h_c1]] <- .fmt_vec(c1$Strength_z[match(nodes, c1$node)])
body[[h_c2]] <- .fmt_vec(c2$Strength_z[match(nodes, c2$node)])
body[[h_c3]] <- .fmt_vec(c3$Strength_z[match(nodes, c3$node)])

title <- "Table 4. Comparison of Node Centrality Index (Strength) in Networks in overall and subgroups."
fts <- c(
  "Values are within-network z-scores of Strength (EBICglasso; scale-total nodes).",
  paste0(
    "Class labels from WHO-DAS LCA mean profiles: ",
    h_c1, " (C1, n = 375); ",
    h_c2, " (C2, n = 219); ",
    h_c3, " (C3, n = 104)."
  )
)

wb <- createWorkbook()
addWorksheet(wb, "Sheet1", gridLines = FALSE)
nc <- ncol(body)
writeData(wb, 1, title, startRow = 1, startCol = 1)
mergeCells(wb, 1, cols = 1:nc, rows = 1)
hdr <- names(body)
for (j in seq_along(hdr)) writeData(wb, 1, hdr[[j]], startRow = 2, startCol = j, colNames = FALSE)
writeData(wb, 1, body, startRow = 3, startCol = 1, colNames = FALSE)
body_end <- 2L + nrow(body)

.font <- "Times New Roman"
sty_title <- createStyle(fontName = .font, fontSize = 12, textDecoration = "bold", halign = "left")
sty_hdr <- createStyle(
  fontName = .font, fontSize = 10, textDecoration = "bold",
  halign = "center", valign = "center", wrapText = TRUE,
  border = c("top", "bottom"), borderStyle = c("thick", "thin")
)
sty_body_l <- createStyle(fontName = .font, fontSize = 11, halign = "left")
sty_body_c <- createStyle(fontName = .font, fontSize = 11, halign = "center")
sty_bot_l <- createStyle(fontName = .font, fontSize = 11, halign = "left", border = "bottom", borderStyle = "thick")
sty_bot_c <- createStyle(fontName = .font, fontSize = 11, halign = "center", border = "bottom", borderStyle = "thick")
sty_ft <- createStyle(fontName = .font, fontSize = 10, halign = "left", wrapText = TRUE)

addStyle(wb, 1, sty_title, rows = 1, cols = 1:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_hdr, rows = 2, cols = 1:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_body_l, rows = 3:body_end, cols = 1, gridExpand = TRUE)
addStyle(wb, 1, sty_body_c, rows = 3:body_end, cols = 2:nc, gridExpand = TRUE)
addStyle(wb, 1, sty_bot_l, rows = body_end, cols = 1, stack = TRUE)
addStyle(wb, 1, sty_bot_c, rows = body_end, cols = 2:nc, gridExpand = TRUE, stack = TRUE)
for (k in seq_along(fts)) {
  rr <- body_end + k
  writeData(wb, 1, fts[[k]], startRow = rr, startCol = 1)
  mergeCells(wb, 1, cols = 1:nc, rows = rr)
  addStyle(wb, 1, sty_ft, rows = rr, cols = 1:nc, gridExpand = TRUE)
}
setColWidths(wb, 1, cols = 1, widths = 14)
setColWidths(wb, 1, cols = 2:4, widths = 28)
setRowHeights(wb, 1, rows = 2, heights = 48)
saveWorkbook(wb, path, overwrite = TRUE)

py <- Sys.which("python3")
script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
if (nzchar(py) && file.exists(script)) {
  invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
}
message("wrote ", path)
