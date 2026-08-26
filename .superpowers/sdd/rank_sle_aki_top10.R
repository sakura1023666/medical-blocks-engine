suppressPackageStartupMessages(library(readxl))
root <- "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/by_index"
out_csv <- "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/Tables/Top10_index_ranking.csv"
dirs <- list.dirs(root, full.names = TRUE, recursive = FALSE)
dirs <- dirs[grepl("【success】", basename(dirs))]

parse_p <- function(x) {
  x <- trimws(as.character(x)[1])
  if (!nzchar(x) || is.na(x) || x %in% c("NA", "Ref", "<NA>")) return(NA_real_)
  if (grepl("<", x)) {
    v <- suppressWarnings(as.numeric(gsub("[^0-9.eE-]", "", sub(".*<", "", x))))
    if (is.finite(v)) return(min(v, 0.0005))
    return(0.0005)
  }
  suppressWarnings(as.numeric(gsub("[^0-9.eE-]", "", x)))
}
parse_num <- function(x) suppressWarnings(as.numeric(as.character(x)[1]))

extract_table2 <- function(path, ix) {
  empty <- list(
    label = NA_character_, or_crude = NA_real_, p_crude = NA_real_,
    or_m1 = NA_real_, p_m1 = NA_real_, or_m2 = NA_real_, p_m2 = NA_real_
  )
  if (!nzchar(path) || !file.exists(path)) return(list(cont = empty, high = empty))
  df <- tryCatch(
    as.data.frame(readxl::read_excel(path, sheet = 1, col_names = FALSE), stringsAsFactors = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) < 4 || ncol(df) < 12) return(list(cont = empty, high = empty))
  c1 <- as.character(df[[1]])
  cont_i <- which(grepl(paste0("^", ix, " continuous$"), c1, ignore.case = TRUE))[1]
  grp_i <- which(
    grepl("^(Q[234]|T[23])$", trimws(c1)) |
      grepl("^High", trimws(c1), ignore.case = TRUE)
  )
  grp_i <- grp_i[!grepl("Ref", c1[grp_i], ignore.case = TRUE)]
  hi_i <- if (length(grp_i)) max(grp_i) else NA_integer_
  get_row <- function(i) {
    if (!is.finite(i)) return(empty)
    list(
      label = trimws(c1[i]),
      or_crude = parse_num(df[[4]][i]),
      p_crude = parse_p(df[[6]][i]),
      or_m1 = parse_num(df[[7]][i]),
      p_m1 = parse_p(df[[9]][i]),
      or_m2 = parse_num(df[[10]][i]),
      p_m2 = parse_p(df[[12]][i])
    )
  }
  list(cont = get_row(cont_i), high = get_row(hi_i))
}

rows <- list()
for (d in dirs) {
  ix <- sub("^【success】", "", basename(d))
  st <- tryCatch(jsonlite::fromJSON(file.path(d, "_batch_status.json")), error = function(e) list())
  t2s <- list.files(file.path(d, "Tables"), pattern = "Table 2-MIMIC\\. Logistic", full.names = TRUE)
  t2 <- if (length(t2s)) t2s[[1]] else ""
  ex <- extract_table2(t2, ix)
  cont <- ex$cont
  hi <- ex$high
  p_best <- suppressWarnings(min(c(cont$p_m2, hi$p_m2), na.rm = TRUE))
  if (!is.finite(p_best)) {
    p_best <- suppressWarnings(min(c(cont$p_crude, hi$p_crude), na.rm = TRUE))
  }
  or_best <- NA_real_
  if (is.finite(hi$p_m2) && (!is.finite(cont$p_m2) || hi$p_m2 <= cont$p_m2)) {
    or_best <- hi$or_m2
  } else {
    or_best <- cont$or_m2
  }
  if (!is.finite(or_best)) {
    or_best <- if (is.finite(hi$or_crude)) hi$or_crude else cont$or_crude
  }
  effect <- if (is.finite(or_best) && or_best > 0) abs(log(or_best)) else 0
  sig_m2_cont <- as.integer(is.finite(cont$p_m2) && cont$p_m2 < 0.05)
  sig_m2_hi <- as.integer(is.finite(hi$p_m2) && hi$p_m2 < 0.05)
  sig_m2 <- as.integer(sig_m2_cont == 1L || sig_m2_hi == 1L)
  dual <- as.integer(sig_m2_cont == 1L && sig_m2_hi == 1L)
  n1 <- suppressWarnings(as.numeric(st$n_after)[1])
  n2 <- suppressWarnings(as.numeric(st$n_stage2)[1])
  nev <- suppressWarnings(as.numeric(st$n_event)[1])
  if (!is.finite(n1)) n1 <- NA_real_
  if (!is.finite(n2)) n2 <- NA_real_
  if (!is.finite(nev)) nev <- NA_real_
  n_ok <- as.integer(is.finite(n1) && n1 >= 80)
  score <- dual * 100 + sig_m2_cont * 40 + sig_m2_hi * 30 + sig_m2 * 10 +
    effect * 5 + n_ok * 3 +
    (if (is.finite(p_best) && p_best > 0) -log10(p_best) else 0)
  rows[[length(rows) + 1L]] <- data.frame(
    index = ix,
    n_stage1 = n1, n_stage2 = n2, n_event28 = nev,
    table2 = if (nzchar(t2)) basename(t2) else NA_character_,
    cont_OR_M2 = cont$or_m2, cont_P_M2 = cont$p_m2,
    cont_OR_crude = cont$or_crude, cont_P_crude = cont$p_crude,
    high_label = hi$label,
    high_OR_M2 = hi$or_m2, high_P_M2 = hi$p_m2,
    high_OR_crude = hi$or_crude, high_P_crude = hi$p_crude,
    score = round(score, 3),
    stringsAsFactors = FALSE
  )
}
tab <- do.call(rbind, rows)
tab <- tab[order(-tab$score, tab$cont_P_M2, -tab$n_stage1, na.last = TRUE), ]
rownames(tab) <- NULL
dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
utils::write.csv(tab, out_csv, row.names = FALSE, fileEncoding = "UTF-8")
top <- utils::head(tab, 10)
cat("=== TOP10 (Stage1 AKI logistic Model2 priority) ===\n")
print(
  top[, c(
    "index", "n_stage1", "n_stage2", "n_event28",
    "cont_OR_M2", "cont_P_M2", "high_label", "high_OR_M2", "high_P_M2", "score"
  )],
  row.names = FALSE
)
cat("\nWrote:", out_csv, "\n")
