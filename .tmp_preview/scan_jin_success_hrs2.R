suppressPackageStartupMessages({ library(openxlsx); library(data.table) })

root <- "G:/02block_result/36_spesis/prediction_41194138/by_index"
ixs <- sub("^【success】", "", list.dirs(root, full.names = FALSE, recursive = FALSE))
ixs <- ixs[nzchar(ixs) & !grepl("^【", ixs)]
# only success folders
ixs <- sub("^【success】", "", list.dirs(root, full.names = FALSE, recursive = FALSE)[
  grepl("^【success】", list.dirs(root, full.names = FALSE, recursive = FALSE))
])

extract_assoc <- function(path) {
  d <- tryCatch(read.xlsx(path, colNames = FALSE), error = function(e) NULL)
  if (is.null(d) || nrow(d) < 5L) return(NULL)
  mat <- as.matrix(d)
  mat[] <- trimws(as.character(mat))
  # find header row with Model2 HR
  hdr <- which(apply(mat, 1, function(r) any(grepl("^HR$", r)) && any(grepl("Model", paste(r, collapse = " "), ignore.case = TRUE))))[1]
  # Model2 HR column = last column named HR in row 3-ish
  hr_cols <- which(apply(mat, 2, function(c) any(c[1:5] == "HR")))
  if (!length(hr_cols)) return(NULL)
  m2_hr_col <- max(hr_cols)
  ci_col <- m2_hr_col + 1L
  p_col <- m2_hr_col + 2L
  cont_i <- which(grepl("continuous", mat[, 1], ignore.case = TRUE))[1]
  q4_i <- which(grepl("^Q4\\b|^T3\\b", mat[, 1], ignore.case = TRUE))[1]
  # sometimes Q4 is in col1 without Continuous nearby
  if (!is.finite(q4_i)) q4_i <- which(grepl("^Q4", mat[, 1]))[1]
  get <- function(i, j) if (is.finite(i) && is.finite(j) && i <= nrow(mat) && j <= ncol(mat)) mat[i, j] else NA_character_
  cont_hr <- suppressWarnings(as.numeric(get(cont_i, m2_hr_col)))
  cont_ci <- get(cont_i, ci_col)
  cont_p <- get(cont_i, p_col)
  q4_hr <- suppressWarnings(as.numeric(get(q4_i, m2_hr_col)))
  q4_ci <- get(q4_i, ci_col)
  q4_p <- get(q4_i, p_col)
  list(
    cont_hr = cont_hr, cont_ci = cont_ci, cont_p = cont_p,
    q4_hr = q4_hr, q4_ci = q4_ci, q4_p = q4_p,
    cont_i = cont_i, q4_i = q4_i, m2_hr_col = m2_hr_col
  )
}

extract_jin_q <- function(path) {
  d <- tryCatch(read.xlsx(path, colNames = FALSE), error = function(e) NULL)
  if (is.null(d)) return(NULL)
  mat <- as.matrix(d)
  mat[] <- trimws(as.character(mat))
  # Model2 Q2/Q3/Q4 for first horizon block
  out <- list()
  for (q in c("QQ2", "QQ3", "QQ4", "Q2", "Q3", "Q4")) {
    i <- which(mat[, 2] == "Model2" & grepl(paste0("Index SOFA Q", q, "$|Index SOFA QQ", substr(q, 2, 2), "$|QQ", substr(q, nchar(q), nchar(q)), "$"), mat[, 3]))
    if (!length(i)) i <- which(mat[, 2] == "Model2" & grepl(paste0("QQ", substr(q, nchar(q), nchar(q))), mat[, 3]))
    if (length(i)) {
      out[[q]] <- mat[i[1], 4]
      out[[paste0(q, "_p")]] <- mat[i[1], 5]
    }
  }
  # broader: all Model2 Index SOFA rows
  ii <- which(mat[, 2] == "Model2" & grepl("Index SOFA", mat[, 3]))
  out$terms <- paste(paste0(mat[ii, 3], "=", mat[ii, 4], " P", mat[ii, 5]), collapse = " | ")
  out
}

rows <- list()
for (ix in ixs) {
  td <- file.path(root, paste0("【success】", ix), "summary_results", "Tables")
  if (!dir.exists(td)) next
  files <- list.files(td, pattern = "\\.xlsx$", full.names = TRUE)
  for (db in c("MIMIC", "eICU")) {
    fa <- files[grepl(paste0("^Table 2-", db, "\\. The Association Between"), basename(files))]
    fj <- files[grepl(paste0("Table 2-", db, "\\. Cox models for mortality"), basename(files))]
    if (length(fa)) {
      ex <- extract_assoc(fa[[1]])
      if (!is.null(ex)) {
        rows[[length(rows) + 1L]] <- data.frame(
          index = ix, db = db, kind = "assoc",
          cont_hr = ex$cont_hr, cont_ci = ex$cont_ci, cont_p = ex$cont_p,
          q4_hr = ex$q4_hr, q4_ci = ex$q4_ci, q4_p = ex$q4_p,
          stringsAsFactors = FALSE
        )
      }
    }
    if (length(fj)) {
      jx <- extract_jin_q(fj[[1]])
      rows[[length(rows) + 1L]] <- data.frame(
        index = ix, db = db, kind = "jin_sofa",
        cont_hr = NA_real_, cont_ci = NA_character_, cont_p = NA_character_,
        q4_hr = NA_real_, q4_ci = NA_character_, q4_p = NA_character_,
        jin_terms = if (!is.null(jx)) jx$terms else NA_character_,
        stringsAsFactors = FALSE
      )
    }
  }
}
out <- rbindlist(rows, fill = TRUE)
fwrite(out, "E:/01block/01Block-new-Final/.tmp_preview/jin_success_hrs2.csv")

a <- out[kind == "assoc"]
cat("Assoc rows:", nrow(a), " indices:", length(unique(a$index)), "\n")
w <- dcast(a, index ~ db, value.var = c("cont_hr", "q4_hr", "cont_p", "q4_p", "cont_ci", "q4_ci"))
# direction: HR>1 risk-increasing; for protective (PNI) HR<1 both sides also "same dir"
w[, cont_same := sign(cont_hr_MIMIC - 1) == sign(cont_hr_eICU - 1)]
w[, q4_same := sign(q4_hr_MIMIC - 1) == sign(q4_hr_eICU - 1)]
# score: both sig Q4 (p <0.05 or <0.001 text), same dir, geometric strength
sig1 <- function(p) {
  p <- as.character(p)[1L]
  if (is.na(p) || !nzchar(p)) return(FALSE)
  if (grepl("^<", p)) return(TRUE)
  isTRUE(suppressWarnings(as.numeric(p) < 0.05))
}
w[, q4_sig_both := vapply(q4_p_MIMIC, sig1, logical(1)) & vapply(q4_p_eICU, sig1, logical(1))]
w[, cont_sig_both := vapply(cont_p_MIMIC, sig1, logical(1)) & vapply(cont_p_eICU, sig1, logical(1))]
w[, q4_geomean := exp((log(pmax(q4_hr_MIMIC, 1e-6)) + log(pmax(q4_hr_eICU, 1e-6))) / 2)]
# effect away from 1
w[, q4_effect := pmax(q4_hr_MIMIC / 1, 1 / q4_hr_MIMIC) * pmax(q4_hr_eICU / 1, 1 / q4_hr_eICU)]
setorder(w, -q4_sig_both, -q4_same, -q4_effect)
cat("\n=== Rank by dual-db Q4 Model2 (same dir + both sig + effect) ===\n")
print(w[, .(
  index, q4_M = round(q4_hr_MIMIC, 3), q4_E = round(q4_hr_eICU, 3),
  q4_same, q4_sig_both,
  cont_M = round(cont_hr_MIMIC, 3), cont_E = round(cont_hr_eICU, 3), cont_same,
  cont_sig_both
)])

cat("\n=== WPR detail ===\n")
print(a[index == "WPR"])
cat("\n=== jin_sofa ===\n")
print(out[kind == "jin_sofa", .(index, db, jin_terms = substr(jin_terms, 1, 200))])
invisible(NULL)
