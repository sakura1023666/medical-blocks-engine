suppressPackageStartupMessages({ library(openxlsx); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

root <- "G:/02block_result/36_spesis/prediction_41194138/by_index"
ixs <- list.dirs(root, full.names = FALSE, recursive = FALSE)
ixs <- sub("^【success】", "", ixs[grepl("^【success】", ixs)])

parse_hr <- function(x) {
  x <- as.character(x)[1L]
  if (is.na(x) || !nzchar(x)) return(c(hr = NA_real_, lo = NA_real_, hi = NA_real_))
  m <- regmatches(x, regexec("([0-9]+\\.?[0-9]*)\\s*\\(\\s*([^,]+)\\s*,\\s*([^)]+)\\)", x))[[1]]
  if (length(m) < 4L) return(c(hr = NA_real_, lo = NA_real_, hi = NA_real_))
  c(hr = as.numeric(m[2]), lo = as.numeric(m[3]), hi = as.numeric(m[4]))
}

rows <- list()
for (ix in ixs) {
  td <- file.path(root, paste0("【success】", ix), "summary_results", "Tables")
  if (!dir.exists(td)) {
    rows[[length(rows) + 1L]] <- data.frame(index = ix, db = NA, kind = "no_summary", stringsAsFactors = FALSE)
    next
  }
  files <- list.files(td, pattern = "\\.xlsx$", full.names = TRUE)
  jin <- files[grepl("Cox models for mortality by .+ and SOFA", basename(files))]
  assoc <- files[grepl("^Table 2-.*The Association Between", basename(files))]
  for (db in c("MIMIC", "eICU")) {
    fj <- jin[grepl(paste0("-", db, "\\."), basename(jin))]
    fa <- assoc[grepl(paste0("-", db, "\\."), basename(assoc))]
    path <- if (length(fj)) fj[[1]] else if (length(fa)) fa[[1]] else NA_character_
    kind <- if (length(fj)) "jin_sofa" else if (length(fa)) "assoc" else "missing"
    if (is.na(path)) {
      rows[[length(rows) + 1L]] <- data.frame(
        index = ix, db = db, kind = kind, file = NA_character_,
        cont_m2 = NA_character_, t3_m2 = NA_character_,
        cont_hr = NA_real_, t3_hr = NA_real_, stringsAsFactors = FALSE
      )
      next
    }
    d <- tryCatch(read.xlsx(path, colNames = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    mat <- as.matrix(d)
    mat[] <- trimws(as.character(mat))
    cont_i <- which(grepl("^Continuous|Continuous \\(|per 1|per SD|per-SD", mat[, 1], ignore.case = TRUE))[1]
    t3_i <- which(
      grepl("T3|Q4|Tertile 3|Quartile 4", mat[, 1], ignore.case = TRUE) &
        !grepl("SOFA", mat[, 1], ignore.case = TRUE)
    )[1]
    # first HR-like cell on row
    pick_hr <- function(i) {
      if (!is.finite(i)) return(NA_character_)
      for (j in seq_len(ncol(mat))) {
        v <- mat[i, j]
        if (grepl("[0-9]+\\.[0-9].*\\(", v)) return(v)
      }
      NA_character_
    }
    # Prefer Model2: scan header for Model 2 cols, take last Model2-ish among first matches
    m2cols <- integer(0)
    for (j in seq_len(ncol(mat))) {
      if (any(grepl("Model\\s*2", mat[1:min(6, nrow(mat)), j], ignore.case = TRUE))) m2cols <- c(m2cols, j)
    }
    pick_hr_m2 <- function(i) {
      if (!is.finite(i)) return(NA_character_)
      cols <- if (length(m2cols)) m2cols else seq_len(ncol(mat))
      for (j in cols) {
        v <- mat[i, j]
        if (grepl("[0-9]+\\.[0-9].*\\(", v)) return(v)
      }
      pick_hr(i)
    }
    cont_m2 <- pick_hr_m2(cont_i)
    t3_m2 <- pick_hr_m2(t3_i)
    # Jin sofa high-high / continuous per horizon: grab all HR-like from cont row
    cont_all <- if (is.finite(cont_i)) {
      vs <- mat[cont_i, ]
      paste(vs[grepl("[0-9]+\\.[0-9].*\\(", vs)], collapse = " ; ")
    } else NA_character_
    ph <- parse_hr(cont_m2)
    pt <- parse_hr(t3_m2)
    rows[[length(rows) + 1L]] <- data.frame(
      index = ix, db = db, kind = kind, file = basename(path),
      cont_label = if (is.finite(cont_i)) mat[cont_i, 1] else NA_character_,
      cont_m2 = substr(as.character(cont_m2), 1, 90),
      t3_label = if (is.finite(t3_i)) mat[t3_i, 1] else NA_character_,
      t3_m2 = substr(as.character(t3_m2), 1, 90),
      cont_all = substr(as.character(cont_all), 1, 200),
      cont_hr = unname(ph["hr"]), t3_hr = unname(pt["hr"]),
      stringsAsFactors = FALSE
    )
  }
}
out <- rbindlist(rows, fill = TRUE)
fwrite(out, "E:/01block/01Block-new-Final/.tmp_preview/jin_success_table2_scan.csv")
cat("kinds:\n"); print(table(out$kind, useNA = "ifany"))
cat("\n=== jin_sofa ===\n")
print(out[kind == "jin_sofa", .(index, db, cont_m2, cont_all)])
cat("\n=== assoc both-db with cont_hr ===\n")
a <- out[kind == "assoc" & is.finite(cont_hr)]
# wide compare
w <- dcast(a, index ~ db, value.var = "cont_hr")
if (all(c("MIMIC", "eICU") %in% names(w))) {
  w[, same_dir := sign(MIMIC - 1) == sign(eICU - 1)]
  w[, min_hr := pmin(MIMIC, eICU, na.rm = TRUE)]
  w[, max_hr := pmax(MIMIC, eICU, na.rm = TRUE)]
  setorder(w, -MIMIC)
  print(w)
}
cat("\n=== assoc T3 both-db ===\n")
a2 <- out[kind == "assoc" & is.finite(t3_hr)]
w2 <- dcast(a2, index ~ db, value.var = "t3_hr")
if (all(c("MIMIC", "eICU") %in% names(w2))) {
  w2[, same_dir := sign(MIMIC - 1) == sign(eICU - 1)]
  setorder(w2, -MIMIC)
  print(w2)
}
invisible(NULL)
