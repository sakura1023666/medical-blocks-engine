## Re-export WPR Table S1–S3 with SCI booktabs style (keep Jin content)
engine_root <- "/mnt/e/01block/01Block-new-Final"
source(file.path(engine_root, "R/utils.R"), local = TRUE)
src <- "/tmp/wpr_table_s123"
dst <- "/tmp/wpr_table_s123_fmt_fresh"
dir.create(dst, showWarnings = FALSE)
files <- list.files(src, pattern = "^S[123]-.*\\.xlsx$", full.names = TRUE)
for (f in files) {
  sheets <- openxlsx::getSheetNames(f)
  df <- openxlsx::read.xlsx(f, sheet = 1L)
  notes <- character(0)
  if ("Notes" %in% sheets) {
    nd <- openxlsx::read.xlsx(f, sheet = "Notes", colNames = FALSE)
    notes <- as.character(nd[[1L]])
    notes <- notes[nzchar(notes)]
  }
  bn <- basename(f)
  sn <- sub("^S([123])-.*", "\\1", bn)
  db <- sub("^S[123]-(MIMIC|eICU)\\..*", "\\1", bn)
  title <- if (length(notes)) notes[[1L]] else paste0("Table S", sn, "-", db)
  out_bn <- sprintf(
    "Table S%s-%s. Subgroup analyses of cox proportional hazard models for %s.xlsx",
    sn, db,
    c("1" = "in-hospital mortality", "2" = "30-day mortality", "3" = "365-day mortality")[[sn]]
  )
  out <- file.path(dst, out_bn)
  foot <- if (length(notes) > 1L) notes[-1L] else character(0)
  sci_xlsx_single_header_booktabs(
    filepath = out,
    title = title,
    df_body = df,
    footnotes = foot,
    level_row_idx = integer(0)
  )
  message("wrote ", out)
}
writeLines(list.files(dst, full.names = TRUE), file.path(dst, "paths.txt"))
message("done")
