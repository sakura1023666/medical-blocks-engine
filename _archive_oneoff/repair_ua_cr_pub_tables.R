#!/usr/bin/env Rscript
# One-off: UA_CR delivery scrub (Smoking 0/1, alias dups, Flowchart CSV, LASSO→S1)
suppressPackageStartupMessages({
  root <- "/mnt/e/01block/01Block-new-Final"
  setwd(root)
  source("R/utils.R")
  source("R/pub_xlsx_surgical.R")
  source("R/pub_figure_export.R")
})

idx <- file.path(
  "/mnt/g/02block_result/46_CKM/ml_dn_age45_5idx_charls/by_index",
  "\u3010success\u3011UA_CR"
)
tab_dirs <- c(
  file.path(idx, "summary_results", "Tables"),
  file.path(idx, "Tables")
)
fig_dirs <- c(
  file.path(idx, "summary_results", "Figures"),
  file.path(idx, "Figures"),
  file.path(idx, "CHARLS", "Figures")
)

drop_exact <- c(
  "waist", "hba1c", "hdl", "TG", "TG,mg/dL", "PLT", "TC", "TC,mg/dL"
)

read_col1 <- function(path) {
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  as.character(d[[1L]])
}

find_drop_rows <- function(path, kind = c("baseline", "s1mi", "uv", "vif", "norm", "s4")) {
  kind <- match.arg(kind)
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  lab <- as.character(d[[1L]])
  n <- length(lab)
  drop <- integer(0)

  for (i in seq_len(n)) {
    x <- trimws(lab[[i]] %||% "")
    if (!nzchar(x) || is.na(x)) next
    if (identical(x, "Smoking")) {
      drop <- c(drop, i)
      j <- i + 1L
      while (j <= n) {
        y <- trimws(lab[[j]] %||% "")
        if (y %in% c("0", "1", "Missing (%)")) {
          drop <- c(drop, j)
          j <- j + 1L
        } else {
          break
        }
      }
      if (kind == "uv" && i < n) {
        a2 <- trimws(as.character(d[i + 1L, 1] %||% ""))
        b2 <- trimws(as.character(d[i + 1L, 2] %||% ""))
        if (!nzchar(a2) && b2 %in% c("0", "1")) drop <- c(drop, i + 1L)
      }
      next
    }
    if (x %in% drop_exact) {
      drop <- c(drop, i)
      if (kind == "s1mi" && i < n &&
          identical(trimws(lab[[i + 1L]] %||% ""), "Missing (%)")) {
        drop <- c(drop, i + 1L)
      }
    }
  }

  for (dup_lab in c("HbA1c,%", "HDL,mg/dL", "HbA1c", "HDL")) {
    hits <- which(trimws(lab) == dup_lab)
    if (length(hits) > 1L) drop <- c(drop, hits[-1L])
  }

  if (kind %in% c("baseline", "s4")) {
    g <- which(trimws(lab) == "Group")
    for (gi in g) {
      drop <- c(drop, gi)
      j <- gi + 1L
      while (j <= n) {
        y <- trimws(lab[[j]] %||% "")
        if (grepl("^CKM stage", y)) {
          drop <- c(drop, j)
          j <- j + 1L
        } else {
          break
        }
      }
    }
  }

  # S4 single-line Smoking percent without levels
  if (kind == "s4") {
    # already covered by Smoking header
  }

  # VIF: Smoking alias only (Smoke kept then renamed)
  if (kind == "vif") {
    # drop_exact + Smoking already; also Smoke Inf pair — keep Smoke rename
  }

  sort(unique(as.integer(drop)))
}

scrub_one <- function(path, kind) {
  if (!file.exists(path)) return(invisible(NULL))
  rows <- find_drop_rows(path, kind)
  message(basename(path), " drop rows: ",
          if (length(rows)) paste(rows, collapse = ",") else "(none)")
  if (length(rows)) pub_xlsx_delete_rows(path, rows)

  lab <- read_col1(path)
  smoke_i <- which(trimws(lab) == "Smoke")
  if (length(smoke_i)) {
    edits <- data.frame(
      row = as.integer(smoke_i), col = 1L, value = "Smoking",
      stringsAsFactors = FALSE
    )
    pub_xlsx_edit_cells(path, edits)
    message("  renamed Smoke -> Smoking @ ", paste(smoke_i, collapse = ","))
  }
  tryCatch(
    pub_xlsx_scrub_underscores(path),
    error = function(e) message("  scrub _: ", conditionMessage(e))
  )
  v <- pub_xlsx_verify(path)
  stopifnot(isTRUE(v$readable), identical(as.integer(v$corrupt_cells), 0L))
  invisible(v)
}

for (td in tab_dirs) {
  if (!dir.exists(td)) next
  message("=== scrub ", td)
  fc <- list.files(td, pattern = "(?i)^Flowchart_attrition", full.names = TRUE)
  if (length(fc)) {
    message("unlink flowchart: ", paste(basename(fc), collapse = ", "))
    unlink(fc)
  }
  scrub_one(file.path(td, "Table 1. Baseline characteristics of CKM.xlsx"), "baseline")
  scrub_one(
    file.path(td, "Table S1. Baseline characteristics before and after imputation (training set).xlsx"),
    "s1mi"
  )
  scrub_one(
    file.path(td, "Table S2. Baseline characteristics before and after imputation (validation set, n=2070).xlsx"),
    "s1mi"
  )
  scrub_one(
    file.path(td, "Table S3. Normality test results for continuous variables.xlsx"),
    "norm"
  )
  scrub_one(
    file.path(td, "Table S4. Baseline characteristics by training and validation sets.xlsx"),
    "s4"
  )
  scrub_one(file.path(td, "Table S5. Univariate Regression Analysis.xlsx"), "uv")
  scrub_one(
    file.path(td, "Table S7. Multicollinearity Analysis VIF screen (validation set).xlsx"),
    "vif"
  )
}

merge_lasso <- function(fig_dir) {
  if (!dir.exists(fig_dir)) return(invisible(FALSE))
  findp <- function(pat) {
    hits <- list.files(
      fig_dir, pattern = pat, full.names = TRUE, recursive = TRUE, ignore.case = TRUE
    )
    hits[endsWith(tolower(hits), ".pdf")]
  }
  s2a <- findp("(?i)Figure\\s*S2A.*LassoGenes")
  s2b <- findp("(?i)Figure\\s*S2B.*LassoModel")
  s1 <- findp("(?i)Figure\\s*S1.*Lasso")
  dest_dir <- if (dir.exists(file.path(fig_dir, "pdf"))) {
    file.path(fig_dir, "pdf")
  } else {
    fig_dir
  }
  dest <- file.path(dest_dir, "Figure S1. Lasso.pdf")
  if (length(s2a) && length(s2b) && !length(s1)) {
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    ok <- isTRUE(tryCatch(
      pub_figure_combine_ab_pdfs(s2a[[1L]], s2b[[1L]], dest),
      error = function(e) {
        message("combine_ab: ", conditionMessage(e))
        FALSE
      }
    ))
    message(if (isTRUE(ok) && file.exists(dest)) {
      paste0("LASSO OK -> ", dest)
    } else {
      "LASSO merge FAILED"
    })
  } else if (length(s1)) {
    message("S1 Lasso exists: ", s1[[1L]])
  } else {
    message("no S2A/B in ", fig_dir)
  }
  leftover <- unique(c(
    findp("(?i)Figure\\s*S2A.*Lasso"),
    findp("(?i)Figure\\s*S2B.*Lasso")
  ))
  if (length(leftover)) {
    message("unlink S2A/B: ", paste(basename(leftover), collapse = ", "))
    unlink(leftover)
  }
  bad3 <- list.files(
    fig_dir, pattern = "(?i)Figure\\s*3\\.?\\s*Subgroup",
    full.names = TRUE, recursive = TRUE
  )
  if (length(bad3)) {
    message("unlink dup Fig3 subgroup: ", paste(basename(bad3), collapse = ", "))
    unlink(bad3)
  }
  invisible(TRUE)
}

for (fd in fig_dirs) {
  message("=== figures ", fd)
  merge_lasso(fd)
}

sr_fig <- file.path(idx, "summary_results", "Figures")
if (dir.exists(sr_fig)) {
  pub_figure_ensure_formats(
    sr_fig,
    config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))
  )
}

message("DONE")
