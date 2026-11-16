#!/usr/bin/env Rscript
## UA_CR (stage01vs23) 交付返工：表别名清理 → ML finalize（S1/Methods/scrub/prune）
suppressPackageStartupMessages({
  root <- "/mnt/e/01block/01Block-new-Final"
  setwd(root)
  source("R/utils.R")
  source("R/pub_xlsx_surgical.R")
  source("R/pub_figure_export.R")
  source("R/incidence_dual_batch_runner.R")
  source("R/ml_index_summary_results.R")
  source("R/pub_delivery_prune.R")
})

idx <- file.path(
  "/mnt/g/02block_result/46_CKM/ml_stage01vs23_charls/by_index",
  "\u3010success\u3011UA_CR"
)
cfg_path <- "/mnt/g/02block_result/46_CKM/ml_stage01vs23_charls/config.R"
source(cfg_path, local = FALSE)
config$project$index_var <- "UA_CR"
config$`_current_index` <- "UA_CR"
config$pub_figures$export_png <- FALSE
config$pub_figures$export_tiff <- FALSE
config$plot$font_family <- "Times"
config$plot$pdf_device <- "cairo_pdf"

drop_exact <- c(
  "waist", "hba1c", "hdl", "TG", "TG,mg/dL", "PLT", "TC", "TC,mg/dL"
)

scrub_table_aliases <- function(path, kind = c("baseline", "s1mi", "uv", "vif", "norm", "s4")) {
  kind <- match.arg(kind)
  if (!file.exists(path)) return(invisible(NULL))
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
          drop <- c(drop, j); j <- j + 1L
        } else break
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
          drop <- c(drop, j); j <- j + 1L
        } else break
      }
    }
  }
  drop <- sort(unique(as.integer(drop)))
  message(basename(path), " drop: ", if (length(drop)) paste(drop, collapse = ",") else "none")
  if (length(drop)) pub_xlsx_delete_rows(path, drop)
  lab2 <- as.character(openxlsx::read.xlsx(path, colNames = FALSE)[[1L]])
  smoke_i <- which(trimws(lab2) == "Smoke")
  if (length(smoke_i)) {
    pub_xlsx_edit_cells(
      path,
      data.frame(row = as.integer(smoke_i), col = 1L, value = "Smoking", stringsAsFactors = FALSE)
    )
  }
  tryCatch(pub_xlsx_scrub_underscores(path), error = function(e) NULL)
  invisible(TRUE)
}

tab_dirs <- unique(c(
  file.path(idx, "summary_results", "Tables"),
  file.path(idx, "Tables"),
  file.path(idx, "CHARLS", "Tables"),
  file.path(idx, "CHARLS", "summary_results", "Tables")
))
for (td in tab_dirs) {
  if (!dir.exists(td)) next
  message("=== scrub ", td)
  fc <- list.files(td, pattern = "(?i)^Flowchart_attrition", full.names = TRUE)
  if (length(fc)) unlink(fc)
  scrub_table_aliases(file.path(td, "Table 1. Baseline characteristics of CKM.xlsx"), "baseline")
  scrub_table_aliases(
    file.path(td, "Table S1. Baseline characteristics before and after imputation (training set).xlsx"),
    "s1mi"
  )
  scrub_table_aliases(
    file.path(td, "Table S2. Baseline characteristics before and after imputation (validation set, n=2070).xlsx"),
    "s1mi"
  )
  scrub_table_aliases(
    file.path(td, "Table S3. Normality test results for continuous variables.xlsx"),
    "norm"
  )
  scrub_table_aliases(
    file.path(td, "Table S4. Baseline characteristics by training and validation sets.xlsx"),
    "s4"
  )
  scrub_table_aliases(file.path(td, "Table S5. Univariate Regression Analysis.xlsx"), "uv")
  scrub_table_aliases(
    file.path(td, "Table S7. Multicollinearity Analysis VIF screen (validation set).xlsx"),
    "vif"
  )
}

## 指标根 + CHARLS Figures curate
for (fd in c(
  file.path(idx, "Figures"),
  file.path(idx, "CHARLS", "Figures"),
  file.path(idx, "summary_results", "Figures")
)) {
  if (!dir.exists(fd)) next
  message("=== curate figures ", fd)
  incidence_batch_curate_ml_pub_figures_dir(fd, cfg = config)
  pub_figure_ensure_formats(fd, config = config)
}

## 完整 finalize（Methods 用 UA_CR、scrub、白名单 prune）
sum_root <- ml_finalize_index_summary_results(
  index_root = idx,
  config = config,
  figures_tables_only = FALSE,
  write_methods = TRUE
)
message("summary_results -> ", sum_root)
message("DONE")
