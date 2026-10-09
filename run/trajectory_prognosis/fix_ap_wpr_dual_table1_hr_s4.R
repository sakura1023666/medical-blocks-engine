#!/usr/bin/env Rscript
# AP WPR dual：修 Table1/S5-eICU 的 HR 展示（对齐 S2 正态 → mean±SD + t 检验），
# 并按「双库 Table1 共同协变量 ∩ 单因素筛」重算 Table S4 VIF。
#
#   Rscript run/trajectory_prognosis/fix_ap_wpr_dual_table1_hr_s4.R

suppressPackageStartupMessages({
  library(openxlsx)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.engine)

source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(.engine, "Blocks/08_vif/01block_multicollinearity.R"), local = FALSE)
source(file.path(.engine, "configs/config_trajectory_prognosis_ap_wpr_dual.R"))

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
proj <- file.path(block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual")
index_root <- file.path(proj, "by_index/WPR")
tab_root <- file.path(index_root, "Tables")
stopifnot(dir.exists(index_root), dir.exists(tab_root))

.common_analysis_vars <- c(
  "Age", "Gender", "Weight", "Height",
  "HR", "RR", "SpO2", "Temperature", "NBPS", "NBPD", "NBPM",
  "RBC", "Hematocrit", "Lymphocytes", "RDW", "ALT", "AST", "LD",
  "Albumin", "Bilirubin_Total", "BUN", "Creatinine",
  "Sodium", "Potassium", "AnionGap", "Glucose", "Total_Cholesterol",
  "Hypertension", "COPD", "CKD", "Hepatitis", "Pneumonia",
  "WPR"
)

.load_imputed <- function(db) {
  ck <- file.path(proj, "checkpoints/by_index/WPR", db, "univariate_prognosis.rds")
  if (!file.exists(ck)) {
    ck <- file.path(proj, "checkpoints/by_index/WPR", db, "baseline_binary.rds")
  }
  stopifnot(file.exists(ck))
  pack <- readRDS(ck)
  dat <- pack$ctx$data$imputed %||% pack$ctx$data$train %||% pack$ctx$data$cleaned
  stopifnot(is.data.frame(dat), "HR" %in% names(dat))
  list(data = dat, ctx = pack$ctx)
}

.find_hr_row <- function(path) {
  df <- openxlsx::read.xlsx(path, colNames = FALSE)
  hit <- which(grepl("^HR(\\s|,|$)", as.character(df[[1]]), perl = TRUE))
  if (!length(hit)) stop("找不到 HR 行: ", basename(path), call. = FALSE)
  as.integer(hit[1L])
}

.fix_hr_row_mean_sd <- function(path, overall, g1, g2, p_chr, footnote_row = NULL) {
  row <- .find_hr_row(path)
  edits <- data.frame(
    row = c(row, row, row, row),
    col = c(2L, 3L, 4L, 5L),
    value = c(overall, g1, g2, p_chr),
    stringsAsFactors = FALSE
  )
  if (!is.null(footnote_row) && is.finite(footnote_row)) {
    edits <- rbind(
      edits,
      data.frame(
        row = as.integer(footnote_row),
        col = 1L,
        value = paste0(
          "Statistical comparisons were performed using Student's t-test, ",
          "the Wilcoxon rank-sum test, or Pearson's chi-squared test."
        ),
        stringsAsFactors = FALSE
      )
    )
  }
  pub_xlsx_edit_cells(path, edits, root = .engine)
  v <- pub_xlsx_verify(path)
  stopifnot(isTRUE(v$readable), identical(as.integer(v$corrupt_cells %||% 0L), 0L))
  cli::cli_alert_success(
    "HR 已改 mean±SD: {basename(path)} (row={row}, p={p_chr})"
  )
  invisible(row)
}

# ── 1) Table 1-eICU：HR → mean±SD + t 检验 ─────────────────────────────────
pack_e <- .load_imputed("eicu")
dat_e <- pack_e$data
ev <- as.character(config$survival$event_var %||% "survival_28d")
y <- pipeline_outcome_as_01(dat_e[[ev]], cfg = config)
hr <- suppressWarnings(as.numeric(dat_e$HR))
ok <- is.finite(hr) & !is.na(y)
hr <- hr[ok]
y <- y[ok]
overall_chr <- fmt_continuous(hr, TRUE)
g0_chr <- fmt_continuous(hr[y == 0], TRUE)
g1_chr <- fmt_continuous(hr[y == 1], TRUE)
tt <- stats::t.test(hr[y == 0], hr[y == 1])
p_chr <- fmt_pval(tt$p.value)
cli::cli_alert_info(
  "eICU HR t-test: overall={overall_chr}; Survivor={g0_chr}; Non-survivor={g1_chr}; p={p_chr}"
)

t1_targets <- c(
  file.path(tab_root, "Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx"),
  file.path(index_root, "eicu/Tables/Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx"),
  file.path(
    index_root,
    "eicu/step08_baseline_binary/Tables/Table 1-eICU. Baseline characteristics of Acute pancreatitis.xlsx"
  )
)
for (fp in t1_targets) {
  if (!file.exists(fp)) next
  # 脚注第 2 句（Wilcoxon-only）→ 含 t 检验
  df0 <- openxlsx::read.xlsx(fp, colNames = FALSE)
  ft_row <- which(grepl("Wilcoxon rank-sum test", as.character(df0[[1]]), fixed = TRUE))[1]
  .fix_hr_row_mean_sd(fp, overall_chr, g0_chr, g1_chr, p_chr, footnote_row = ft_row)
}

# ── 2) Table S5-eICU：HR 与 Table1 同口径（按轨迹类）───────────────────────
ck_jlcm <- file.path(proj, "checkpoints/by_index/WPR/eicu/step01_trajectory_jlcm.rds")
if (file.exists(ck_jlcm)) {
  jl <- readRDS(ck_jlcm)
  d5 <- jl$ctx$data$imputed
  cls <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(d5$trajectory_class))))
  d5$class_factor <- factor(cls, levels = c(1L, 2L), labels = c("Class 1", "Class 2"))
  d5 <- d5[!is.na(d5$class_factor) & is.finite(suppressWarnings(as.numeric(d5$HR))), , drop = FALSE]
  hr5 <- as.numeric(d5$HR)
  overall5 <- fmt_continuous(hr5, TRUE)
  c1 <- fmt_continuous(hr5[d5$class_factor == "Class 1"], TRUE)
  c2 <- fmt_continuous(hr5[d5$class_factor == "Class 2"], TRUE)
  tt5 <- stats::t.test(hr5 ~ d5$class_factor)
  p5 <- fmt_pval(tt5$p.value)
  cli::cli_alert_info("eICU S5 HR t-test by class: p={p5}")
  s5_targets <- c(
    file.path(tab_root, "Table S5-eICU. Baseline characteristics by trajectory class (WPR).xlsx"),
    file.path(index_root, "eicu/Tables/Table S5-eICU. Baseline characteristics by trajectory class (WPR).xlsx")
  )
  for (fp in s5_targets) {
    if (!file.exists(fp)) next
    .fix_hr_row_mean_sd(fp, overall5, c1, c2, p5, footnote_row = NULL)
  }
} else {
  cli::cli_alert_warning("缺 JLCM checkpoint，跳过 S5-eICU HR 修复")
}

# ── 3) 重算 Table S4（共同协变量 ∩ tb_screen）——必须走 export_sci_table 三线表
.rebuild_s4 <- function(db, db_lab) {
  pack <- .load_imputed(db)
  dat <- pack$data
  tb_screen <- as.character(pack$ctx$results$tb_screen %||% character(0))
  if (!length(tb_screen)) {
    stop("缺 tb_screen: ", db, call. = FALSE)
  }
  vars <- intersect(unique(c(tb_screen, "WPR")), .common_analysis_vars)
  vars <- vars[vars %in% names(dat)]
  vars <- c(setdiff(vars, "WPR"), intersect(vars, "WPR"))
  if (length(vars) < 2L) stop("S4 候选过少: ", db, call. = FALSE)

  vif_tab <- .mcol_build_orig_var_vif_table(vars, dat)
  vif_tab$Variable <- gsub("_", " ", as.character(vif_tab$Variable), fixed = TRUE)
  names(vif_tab) <- c("Variable", "VIF")

  # 用较短 stem 入队（pub_fit_table_stem 会裁括号段），渲染后再改正式文件名与 A1
  short_title <- sprintf("Table S4-%s. Multicollinearity Analysis", db_lab)
  full_title <- sprintf(
    "Table S4-%s. Multicollinearity Analysis (VIF, univariate screen)",
    db_lab
  )
  short_path <- file.path(tab_root, paste0(short_title, ".xlsx"))
  full_name <- paste0(full_title, ".xlsx")

  .table_queue_env$items <- list()
  export_sci_table(vif_tab, short_path, title = short_title)
  ctx_q <- list(
    config = config,
    results = list(),
    output_dir = tab_root,
    output_dir_tables = tab_root,
    root_output_dir = index_root
  )
  ctx_q$config$project$database <- db_lab
  ctx_q <- render_queued_tables(ctx_q)
  if (!file.exists(short_path)) {
    stop("SCI S4 未落盘: ", short_path, call. = FALSE)
  }

  dests <- c(
    file.path(tab_root, full_name),
    file.path(index_root, db, "Tables", full_name),
    file.path(
      index_root, db, "step10_multicollinearity_screen/Tables",
      sprintf("Table S4-%s. Multicollinearity Analysis VIF screen.xlsx", db_lab)
    )
  )
  for (d in dests) {
    dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
    file.copy(short_path, d, overwrite = TRUE)
    pub_xlsx_edit_cells(
      d,
      data.frame(row = 1L, col = 1L, value = full_title, stringsAsFactors = FALSE),
      root = .engine
    )
  }
  unlink(short_path)

  csv_dir <- file.path(index_root, db, "step10_multicollinearity_screen")
  if (dir.exists(csv_dir)) {
    utils::write.csv(
      data.frame(Variable_display = vif_tab$Variable, VIF = vif_tab$VIF),
      file.path(csv_dir, "VIF_check_screen.csv"),
      row.names = FALSE
    )
    writeLines(setdiff(vars, "WPR"), file.path(csv_dir, "VIF_screen_pass.txt"))
  }
  v <- pub_xlsx_verify(file.path(tab_root, full_name))
  cli::cli_alert_success(
    "[{db_lab}] S4 n_var={nrow(vif_tab)} styles={v$styles} corrupt={v$corrupt_cells}: {paste(vif_tab$Variable, collapse=', ')}"
  )
  invisible(vif_tab)
}

s4_m <- .rebuild_s4("mimic", "MIMIC")
s4_e <- .rebuild_s4("eicu", "eICU")

cli::cli_h2("完成：已改 Table1-eICU / S5-eICU（HR）与 Table S4 双库；无改图")
print(list(s4_mimic = s4_m$Variable, s4_eicu = s4_e$Variable))
