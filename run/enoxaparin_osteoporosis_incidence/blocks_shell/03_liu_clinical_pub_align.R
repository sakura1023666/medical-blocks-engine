#!/usr/bin/env Rscript
###############################################################################
# 03_liu_clinical_pub_align.R
# 将主 output / summary_results 的图、表编号对齐 Liu 2026 临床主文：
#   Fig1 流程 · Fig2 亚组 · Fig3 RCS · Fig4 中介
#   Table1 OP基线 · Table2 长期基线 · Table3 时长Logistic(四分位+连续)
###############################################################################

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block")
root <- normalizePath(root, winslash = "/", mustWork = TRUE)
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/incidence_single_pub_finalize.R"))
source(file.path(root, "run/enoxaparin_osteoporosis_incidence/config_enoxaparin_op_incidence.R"))

out_root <- config$project$output_dir
tabs_dir <- file.path(out_root, "Tables")
sum_tabs <- file.path(out_root, "summary_results", "Tables")
lt_root <- "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/Output/enoxaparin_op_longterm_table2"
lt_tabs <- file.path(lt_root, "Tables")

`%||%` <- function(a, b) if (is.null(a)) b else a

copy_ext <- function(src_xlsx, dest_xlsx) {
  if (!file.exists(src_xlsx)) return(FALSE)
  dir.create(dirname(dest_xlsx), recursive = TRUE, showWarnings = FALSE)
  file.copy(src_xlsx, dest_xlsx, overwrite = TRUE)
  for (ext in c(".tex", ".csv")) {
    s2 <- sub("\\.xlsx$", ext, src_xlsx, ignore.case = TRUE)
    d2 <- sub("\\.xlsx$", ext, dest_xlsx, ignore.case = TRUE)
    if (file.exists(s2)) file.copy(s2, d2, overwrite = TRUE)
  }
  TRUE
}

find_one <- function(dir, pattern) {
  hits <- list.files(dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  hits <- hits[grepl("\\.xlsx$", hits, ignore.case = TRUE)]
  if (!length(hits)) return(NA_character_)
  hits[[1L]]
}

fix_p_zero <- function(xlsx_path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  if (!file.exists(xlsx_path)) return(invisible(FALSE))
  sheets <- openxlsx::getSheetNames(xlsx_path)
  any_changed <- FALSE
  wb <- openxlsx::loadWorkbook(xlsx_path)
  for (sh in sheets) {
    d <- tryCatch(openxlsx::read.xlsx(xlsx_path, sheet = sh, colNames = TRUE),
                  error = function(e) NULL)
    if (is.null(d) || !ncol(d)) next
    cn <- names(d)
    p_cols <- which(grepl("^p(\\.|_|$|value|val)|\\bp\\b", cn, ignore.case = TRUE))
    if (!length(p_cols)) {
      # 无列名命中时：扫首行作表头的退化表
      d0 <- tryCatch(openxlsx::read.xlsx(xlsx_path, sheet = sh, colNames = FALSE),
                     error = function(e) NULL)
      if (is.null(d0) || nrow(d0) < 2L) next
      hdr <- as.character(unlist(d0[1, , drop = TRUE]))
      p_cols <- which(grepl("^p(\\.|_|$|value|val)|\\bp\\b", hdr, ignore.case = TRUE))
      if (!length(p_cols)) next
      changed <- FALSE
      for (j in p_cols) {
        x <- as.character(d0[[j]])
        hit <- which(trimws(x) %in% c("0", "0.0", "0.00", "0.000", "0.0000"))
        hit <- hit[hit > 1L]
        if (length(hit)) {
          d0[[j]][hit] <- "<0.001"
          changed <- TRUE
        }
      }
      if (changed) {
        openxlsx::writeData(wb, sheet = sh, x = d0, colNames = FALSE)
        any_changed <- TRUE
      }
      next
    }
    changed <- FALSE
    for (j in p_cols) {
      x <- as.character(d[[j]])
      hit <- which(trimws(x) %in% c("0", "0.0", "0.00", "0.000", "0.0000"))
      if (length(hit)) {
        d[[j]][hit] <- "<0.001"
        changed <- TRUE
      }
    }
    if (changed) {
      openxlsx::writeData(wb, sheet = sh, x = d, colNames = TRUE)
      any_changed <- TRUE
    }
  }
  if (any_changed) {
    openxlsx::saveWorkbook(wb, xlsx_path, overwrite = TRUE)
    message("[align] fixed bare P=0 in ", basename(xlsx_path))
  }
  invisible(any_changed)
}

align_one_tables_dir <- function(tdir, lt_tabs) {
  if (!dir.exists(tdir)) dir.create(tdir, recursive = TRUE, showWarnings = FALSE)
  # 先归档整夹交付表，再从 archive 取源（避免 unlink 后丢路径）
  arch <- file.path(tdir, paste0("_pre_liu_align_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(tdir, pattern = "\\.(xlsx|tex|csv)$", full.names = TRUE)) {
    file.rename(f, file.path(arch, basename(f)))
  }

  t1 <- find_one(arch, "Table 1.*Osteoporosis|Table 1.*Baseline characteristics of Osteoporosis")
  if (is.na(t1)) t1 <- find_one(arch, "^Table 1")
  t2_src <- find_one(lt_tabs, "^Table 1")
  t3 <- find_one(arch, "quartile")
  if (is.na(t3)) t3 <- find_one(arch, "Logistic regression.*quartile")
  t_bin <- find_one(arch, "binary")
  t_med <- find_one(arch, "Mediation")
  t_s1 <- find_one(arch, "before and after imputation")
  t_s2 <- find_one(arch, "Normality")
  t_rcs <- list.files(arch, pattern = "RCS cutoff.*\\.xlsx$", full.names = TRUE, ignore.case = TRUE)

  ok <- TRUE
  if (!is.na(t1)) {
    ok <- copy_ext(t1, file.path(tdir, "Table 1. Baseline characteristics by osteoporosis.xlsx")) && ok
  } else message("[align] WARN: missing Table 1 (OP)")

  if (!is.na(t2_src)) {
    ok <- copy_ext(
      t2_src,
      file.path(tdir, "Table 2. Baseline characteristics by long-term enoxaparin exposure.xlsx")
    ) && ok
  } else message("[align] WARN: missing long-term baseline Table 1 source")

  if (!is.na(t3)) {
    ok <- copy_ext(
      t3,
      file.path(tdir, "Table 3. Association of enoxaparin exposure duration with osteoporosis.xlsx")
    ) && ok
  } else message("[align] WARN: missing quartile logistic")

  if (!is.na(t_s1)) {
    copy_ext(t_s1, file.path(tdir, "Table S1. Baseline characteristics before and after imputation.xlsx"))
  }
  if (!is.na(t_s2)) {
    copy_ext(t_s2, file.path(tdir, "Table S2. Normality test results for continuous variables.xlsx"))
  }
  if (!is.na(t_bin)) {
    copy_ext(t_bin, file.path(tdir, "Table S3. Logistic regression of long-term (>=30d) enoxaparin exposure.xlsx"))
  }
  if (!is.na(t_med)) {
    copy_ext(t_med, file.path(tdir, "Table S4. Mediation analysis of exposure duration.xlsx"))
  }
  if (length(t_rcs)) {
    copy_ext(t_rcs[[1L]], file.path(tdir, "Table S5. Logistic regression at RCS cutoff.xlsx"))
    if (length(t_rcs) >= 2L) {
      copy_ext(t_rcs[[2L]], file.path(tdir, "Table S6. Logistic regression at RCS cutoff (binary).xlsx"))
    }
  }

  for (f in list.files(tdir, pattern = "\\.xlsx$", full.names = TRUE)) {
    if (grepl("Table (3|S3|S5|S6)", basename(f))) fix_p_zero(f)
  }
  invisible(ok)
}

message("[align] 1/3 curate figures with scheme=liu_clinical")
config$pub$figure_scheme <- "liu_clinical"
n_fig <- tryCatch(
  incidence_curate_single_delivery_figures(out_root, config),
  error = function(e) {
    message("[align] figure curate error: ", conditionMessage(e))
    0L
  }
)
message("[align] figures curated, drop≈", n_fig)

# 同步 summary_results Figures：再跑一次 curate 目标含 summary？引擎 curate 通常扫 out_root/Figures
# 重新导出到 summary 由 incidence finalize 其它函数负责；此处对 summary 做同样 rename 逻辑的简易镜像
sum_fig_pdf <- file.path(out_root, "summary_results", "Figures", "pdf")
if (dir.exists(file.path(out_root, "Figures", "pdf")) && dir.exists(dirname(sum_fig_pdf))) {
  dir.create(sum_fig_pdf, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(file.path(out_root, "Figures", "pdf"), full.names = TRUE)) {
    file.copy(f, file.path(sum_fig_pdf, basename(f)), overwrite = TRUE)
  }
  # png/tiff/image_information
  for (sub in c("png", "tiff", "image_information")) {
    src <- file.path(out_root, "Figures", sub)
    dst <- file.path(out_root, "summary_results", "Figures", sub)
    if (!dir.exists(src)) next
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    for (f in list.files(src, full.names = TRUE)) {
      file.copy(f, file.path(dst, basename(f)), overwrite = TRUE)
    }
  }
}

message("[align] 2/3 renumber Tables (main + summary_results)")
align_one_tables_dir(tabs_dir, lt_tabs)
dir.create(sum_tabs, recursive = TRUE, showWarnings = FALSE)
# 先清空 summary 旧交付，再镜像（避免旧 Table2/S3 残留）
old_sum <- list.files(sum_tabs, pattern = "\\.(xlsx|tex|csv)$", full.names = TRUE)
if (length(old_sum)) {
  arch_sum <- file.path(sum_tabs, paste0("_pre_liu_align_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  dir.create(arch_sum, recursive = TRUE, showWarnings = FALSE)
  file.rename(old_sum, file.path(arch_sum, basename(old_sum)))
}
for (f in list.files(tabs_dir, pattern = "\\.(xlsx|tex|csv)$", full.names = TRUE)) {
  file.copy(f, file.path(sum_tabs, basename(f)), overwrite = TRUE)
}

message("[align] 3/3 done. Listing delivery:")
message("Figures/pdf:\n  ", paste(list.files(file.path(out_root, "Figures", "pdf")), collapse = "\n  "))
message("Tables:\n  ", paste(list.files(tabs_dir, pattern = "\\.xlsx$"), collapse = "\n  "))
message("summary_results/Tables:\n  ", paste(list.files(sum_tabs, pattern = "\\.xlsx$"), collapse = "\n  "))
