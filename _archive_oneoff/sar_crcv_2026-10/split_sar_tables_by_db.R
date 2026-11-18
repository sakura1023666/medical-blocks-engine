#!/usr/bin/env Rscript
# 把 SAR+CrCV 双库叠在一张表里的发表表，拆成 MIMIC-IV / eICU 各一份。
suppressPackageStartupMessages(library(openxlsx))
source("/mnt/e/01block/01Block-new-Final/R/utils.R")

src <- "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/【success】SAR+CrCV/publication_literature_final/Tables"
out <- "/tmp/sar_tables_by_db"
dir.create(out, recursive = TRUE, showWarnings = FALSE)

unescape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  trimws(x)
}
read_raw <- function(fn) {
  d <- openxlsx::read.xlsx(file.path(src, fn), colNames = FALSE,
                           skipEmptyRows = FALSE, skipEmptyCols = FALSE)
  d[] <- lapply(d, unescape)
  d
}
write_one <- function(path, title, df, notes, sheet) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  sci_xlsx_single_header_booktabs(
    path, title = title, df_body = df, sheet = substr(sheet, 1, 28),
    footnotes = notes
  )
  message("wrote ", basename(path), " rows=", nrow(df))
}

# ---- Table 1 ----
t1 <- read_raw("Table 1. Baseline characteristics by 28-day survival (MIMIC-IV, eICU).xlsx")
# col1 panel, col2 characteristic, col3-6 stats
is_panel <- grepl("^Panel [AB]:", t1[[1]])
mimic_rows <- which(t1[[1]] == "Panel A: MIMIC-IV")
eicu_rows <- which(t1[[1]] == "Panel B: eICU")
split_t1 <- function(idx, db_lab, n_note) {
  block <- t1[idx, , drop = FALSE]
  # first row of the block is the N header
  hdr <- as.character(block[1, ])
  body <- block[-1, , drop = FALSE]
  df <- data.frame(
    Characteristic = body[[2]],
    check.names = FALSE, stringsAsFactors = FALSE
  )
  df[[hdr[[3]]]] <- body[[3]]
  df[[hdr[[4]]]] <- body[[4]]
  df[[hdr[[5]]]] <- body[[5]]
  df[["p-value"]] <- body[[6]]
  # drop a repeated header if any slipped in
  df <- df[df$Characteristic != "Characteristic", , drop = FALSE]
  write_one(
    file.path(out, sprintf("Table 1-%s. Baseline characteristics by 28-day survival.xlsx", db_lab)),
    sprintf("Table 1. Baseline characteristics by 28-day survival (%s).", n_note),
    df,
    c(
      "Continuous variables are presented as median (interquartile range); categorical variables as n (%).",
      "Comparison between Survivor and Non-survivor groups used the Wilcoxon rank-sum or Pearson chi-squared test.",
      "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."
    ),
    "Table 1"
  )
}
split_t1(mimic_rows, "MIMIC IV", "MIMIC-IV")
split_t1(eicu_rows, "eICU", "eICU")

# ---- Table 2: HR and P in separate columns, one database per file ----
t2 <- read_raw("Table 2 Joint group Cox.xlsx")
split_hr_p <- function(cell) {
  cell <- unescape(cell)
  if (!nzchar(cell)) return(c(hr = "", p = ""))
  if (grepl("ref", cell, ignore.case = TRUE)) return(c(hr = "1.00 (Reference)", p = ""))
  # "2.207 (2.005, 2.430) <0.001"
  m <- regexec("^(.*\\))\\s+(.+)$", cell)
  g <- regmatches(cell, m)[[1]]
  if (length(g) == 3L) return(c(hr = g[[2]], p = g[[3]]))
  c(hr = cell, p = "")
}
split_t2 <- function(panel_lab, db_file, db_title) {
  hit <- which(t2[[1]] == panel_lab)
  # following rows until blank or next panel
  end <- hit[length(hit)]
  # take consecutive group rows after the panel label: rows with Group in col 3
  rows <- which(t2[[1]] == panel_lab & grepl("^Group", t2[[3]]))
  df <- data.frame(
    Group = t2[rows, 3],
    stringsAsFactors = FALSE, check.names = FALSE
  )
  for (k in 1:3) {
    parsed <- t(vapply(t2[rows, 3L + k], split_hr_p, character(2)))
    df[[sprintf("Model %d HR (95%% CI)", k)]] <- parsed[, 1]
    df[[sprintf("Model %d P", k)]] <- parsed[, 2]
  }
  ncell <- unique(t2[rows, 7])
  write_one(
    file.path(out, sprintf("Table 2-%s. Joint group Cox.xlsx", db_file)),
    sprintf("Table 2. Association of SAR and CrCV joint groups with 28-day all-cause mortality (%s).", db_title),
    df,
    c(
      "Model 1: unadjusted. Model 2: age and sex. Model 3: age, sex, and univariate-significant clinical covariates with VIF < 5.",
      "Group1 is the low/low reference (each index high = upper tertile frozen on the MIMIC-IV development set).",
      sprintf("N (events) = %s.", ncell[[1]]),
      "Outcome: 28-day all-cause mortality."
    ),
    "Table 2"
  )
}
split_t2("Panel A: MIMIC-IV", "MIMIC IV", "MIMIC-IV")
split_t2("Panel B: eICU", "eICU", "eICU")

# generic: drop a database column and write two files
split_by_dbcol <- function(fn, db_col, title_fmt, out_fmt, sheet, notes,
                           drop_cols = db_col, db_map = NULL) {
  d <- read_raw(fn)
  hdr <- as.character(d[2, ])
  hdr[hdr == ""] <- paste0("col", seq_along(hdr))[hdr == ""]
  # unique colnames
  hdr <- make.unique(hdr, sep = " ")
  body <- d[3:nrow(d), , drop = FALSE]
  names(body) <- hdr
  # footnotes: rows whose db cell is blank and first cell is long text, or db col empty
  dbv <- body[[db_col]]
  is_note <- !nzchar(dbv) | !grepl("MIMIC|eICU", dbv)
  # keep notes only from trailing rows
  note_rows <- body[is_note, 1]
  note_rows <- note_rows[nzchar(note_rows)]
  data <- body[!is_note, , drop = FALSE]
  if (!is.null(drop_cols)) data <- data[, setdiff(names(data), drop_cols), drop = FALSE]
  labs <- list(
    "MIMIC IV" = grepl("MIMIC", body[[db_col]]),
    "eICU" = grepl("eICU", body[[db_col]]) & !grepl("MIMIC", body[[db_col]])
  )
  # recompute on data after filter: use original body flags aligned
  flags <- data.frame(
    mimic = grepl("MIMIC", body[[db_col]]) & !is_note,
    eicu = grepl("eICU", body[[db_col]]) & !grepl("MIMIC", body[[db_col]]) & !is_note
  )
  pieces <- list("MIMIC IV" = data[flags$mimic[which(!is_note)], , drop = FALSE],
                 "eICU" = data[flags$eicu[which(!is_note)], , drop = FALSE])
  # The which(!is_note) alignment is messy if data rows were subset by !is_note in same order.
  data_idx <- which(!is_note)
  pieces <- list(
    "MIMIC IV" = data[grepl("MIMIC", body[[db_col]][data_idx]), , drop = FALSE],
    "eICU" = data[grepl("^eICU|eICU", body[[db_col]][data_idx]) &
                    !grepl("MIMIC", body[[db_col]][data_idx]), , drop = FALSE]
  )
  for (db in names(pieces)) {
    pretty <- if (db == "MIMIC IV") "MIMIC-IV" else "eICU"
    write_one(
      file.path(out, sprintf(out_fmt, db)),
      sprintf(title_fmt, pretty),
      pieces[[db]],
      c(notes, if (length(note_rows)) note_rows else NULL),
      sheet
    )
  }
}

split_by_dbcol(
  "Table S2. Univariate Cox regression analyses in both databases.xlsx",
  db_col = "Database",
  title_fmt = "Table S2. Univariate Cox regression analyses (%s).",
  out_fmt = "Table S2-%s. Univariate Cox regression analyses.xlsx",
  sheet = "Table S2",
  notes = "Outcome: 28-day all-cause mortality. HR is per unit for continuous variables and for the listed level of categorical variables."
)
split_by_dbcol(
  "Table S4 SAR CrCV Cox.xlsx",
  db_col = "Database",
  title_fmt = "Table S4. Cox associations of SAR and CrCV with 28-day all-cause mortality (%s).",
  out_fmt = "Table S4-%s. SAR CrCV Cox.xlsx",
  sheet = "Table S4",
  notes = "Model 1 unadjusted; Model 2 age and sex; Model 3 age, sex, and the clinical covariate set. Tertile cuts are frozen on the MIMIC-IV development set."
)
split_by_dbcol(
  "Table S5 ROC discrimination DeLong.xlsx",
  db_col = "Database",
  title_fmt = "Table S5. Discrimination and DeLong tests versus SAR (%s, 28-day all-cause mortality).",
  out_fmt = "Table S5-%s. ROC discrimination DeLong.xlsx",
  sheet = "Table S5",
  notes = "AUC and 95% CI from the full analysis cohort. DeLong test compares each predictor with SAR."
)
split_by_dbcol(
  "Table S6 PH overall cohort.xlsx",
  db_col = "Database",
  title_fmt = "Table S6. Proportional-hazards (Schoenfeld) tests, overall cohort (%s).",
  out_fmt = "Table S6-%s. PH overall cohort.xlsx",
  sheet = "Table S6",
  notes = "Unadjusted Cox model for SAR or CrCV. Outcome: 28-day all-cause mortality."
)
split_by_dbcol(
  "Table S9 baseline glucose excluded joint Cox.xlsx",
  db_col = "Database",
  title_fmt = "Table S9. Joint-group Cox after excluding baseline glucose <70 mg/dL (%s).",
  out_fmt = "Table S9-%s. Baseline glucose excluded joint Cox.xlsx",
  sheet = "Table S9",
  notes = "Sensitivity analysis on the overall cohort. Group1 is the low/low reference."
)
split_by_dbcol(
  "Table S10 complete-case joint Cox.xlsx",
  db_col = "Database",
  title_fmt = "Table S10. Joint-group Cox restricted to complete cases (%s).",
  out_fmt = "Table S10-%s. Complete-case joint Cox.xlsx",
  sheet = "Table S10",
  notes = "Sensitivity analysis on the overall cohort. Group1 is the low/low reference."
)

# S1 definitions
s1 <- read_raw("Table S1. AKI cohort and variable definitions with code evidence.xlsx")
hdr <- make.unique(as.character(s1[2, ]))
body <- s1[3:nrow(s1), ]
names(body) <- hdr
dbcol <- names(body)[1]
for (db in c("MIMIC-IV", "eICU")) {
  sub <- body[grepl(db, body[[dbcol]], fixed = TRUE), , drop = FALSE]
  file_db <- if (db == "MIMIC-IV") "MIMIC IV" else "eICU"
  write_one(
    file.path(out, sprintf("Table S1-%s. AKI cohort and variable definitions.xlsx", file_db)),
    sprintf("Table S1. Cohort and variable definitions (%s).", db),
    sub,
    "Definitions describe the analysis cohort actually used. Outcome is 28-day all-cause mortality.",
    "Table S1"
  )
}

# S11: MIMIC keeps train + internal; eICU keeps external
s11 <- read_raw("Table S11. Stratified five-model machine-learning performance.xlsx")
hdr <- make.unique(as.character(s11[2, ]))
# footnotes start where stratum is not Overall
body <- s11[3:nrow(s11), ]
names(body) <- hdr
is_data <- body[[1]] == "Overall"
notes <- body[!is_data, 1]
notes <- notes[nzchar(notes)]
data <- body[is_data, , drop = FALSE]
mimic <- data[data$Database == "MIMIC-IV", setdiff(names(data), "Database"), drop = FALSE]
eicu <- data[grepl("eICU", data$Database), setdiff(names(data), "Database"), drop = FALSE]
s11_notes <- c(
  "Models were trained on the MIMIC-IV development set and frozen.",
  "eICU rows are external validation without refit.",
  "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."
)
write_one(
  file.path(out, "Table S11-MIMIC IV. Five-model performance.xlsx"),
  "Table S11. Five-model performance on the MIMIC-IV training and internal-validation sets.",
  mimic, s11_notes, "Table S11"
)
write_one(
  file.path(out, "Table S11-eICU. Five-model performance.xlsx"),
  "Table S11. Five-model external performance on eICU (frozen MIMIC-IV models, no refit).",
  eicu, s11_notes, "Table S11"
)

# S12: development/internal vs external
s12 <- read_raw("Table S12. Overall machine-learning performance train internal external.xlsx")
hdr <- make.unique(as.character(s12[2, ]))
body <- s12[3:nrow(s12), ]
names(body) <- hdr
ds <- body[[1]]
is_note <- !nzchar(ds) | !grepl("MIMIC|eICU|Train|Internal|External", ds)
data <- body[!is_note, , drop = FALSE]
mimic <- data[grepl("MIMIC-IV development|Internal validation", data[[1]]), , drop = FALSE]
eicu <- data[grepl("eICU", data[[1]]), , drop = FALSE]
s12_notes <- c(
  "These estimates come from an earlier overall relayout and are not the Figure 8 frozen-bundle AUCs.",
  "Outcome: 28-day all-cause mortality."
)
write_one(
  file.path(out, "Table S12-MIMIC IV. Machine-learning performance.xlsx"),
  "Table S12. Machine-learning performance on the MIMIC-IV training and internal-validation sets.",
  mimic, s12_notes, "Table S12"
)
write_one(
  file.path(out, "Table S12-eICU. Machine-learning performance.xlsx"),
  "Table S12. Machine-learning performance on eICU external validation.",
  eicu, s12_notes, "Table S12"
)

message("SPLIT_OK ", length(list.files(out)))
