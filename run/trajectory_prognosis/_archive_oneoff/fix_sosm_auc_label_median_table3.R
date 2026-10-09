#!/usr/bin/env Rscript
# 一次性修补 SOSM：AUC/C-index 图 P= 标签、轨迹图 KM 中位生存 NR、Table3 准完全分离 NE
# 不重跑 weibull bootstrap；从已有 CSV / JLCM 产物重绘后 remirror 到【success】SOSM。
suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr)
})

.root <- {
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env) && dir.exists(env)) normalizePath(env, winslash = "/") else
    normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), "..", ".."), winslash = "/")
}
# Rscript --file= 时 ofile 不可靠，用 commandArgs
.ca <- commandArgs(trailingOnly = FALSE)
.f <- sub("^--file=", "", grep("^--file=", .ca, value = TRUE)[1])
if (length(.f) && nzchar(.f) && !is.na(.f)) {
  .root <- normalizePath(file.path(dirname(.f), "..", ".."), winslash = "/")
}
if (!file.exists(file.path(.root, "Blocks"))) {
  .root <- "/mnt/e/01block/01Block-new-Final"
}
setwd(.root)
source("R/utils.R")
source("R/trajectory_paper_tables.R")
source("Blocks/53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R")
source("Blocks/26_trajectory/04block_trajectory_plot_jlcm.R")
source("R/trajectory_survival_utils.R")

study <- "/mnt/g/DockerHome/5006/medical-blocks-studies/02_fuzhumailiu/tr"
sosm  <- file.path(study, "by_index", "\u3010success\u3011SOSM")
mimic <- file.path(sosm, "mimic")
stopifnot(dir.exists(mimic))

# ── 1) Weibull AUC / C-index：从 CSV 重绘（P= 前缀）─────────────────────────
csv <- file.path(mimic, "Tables", "_archive", "Table_Weibull_Dynamic_Compare_SOSM.csv")
if (!file.exists(csv)) {
  alt <- list.files(file.path(mimic, "step21_trajectory_weibull_compare"),
                    pattern = "Weibull.*SOSM.*\\.csv$", recursive = TRUE, full.names = TRUE)
  csv <- alt[1]
}
stopifnot(file.exists(csv))
res <- utils::read.csv(csv, stringsAsFactors = FALSE)
landmarks <- sort(unique(as.numeric(res$landmark)))
font_family <- "sans"

p_auc <- .twc02_make_line_plot(
  res, "auc", "AUC (landmark -> day 28)", "SOSM", "p_auc", landmarks, font_family
)
p_c <- .twc02_make_line_plot(
  res, "c", "C-index (landmark -> day 28)", "SOSM", "p_cindex", landmarks, font_family
)

out_dirs <- c(
  file.path(mimic, "step21_trajectory_weibull_compare", "Figures"),
  file.path(mimic, "Figures", "_raw"),
  file.path(mimic, "Figures"),
  file.path(sosm, "Figures")
)
for (d in out_dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)

.save_named <- function(plot, stems, width = 6.5, height = 4.8) {
  for (stem in stems) {
    for (d in out_dirs) {
      fp <- file.path(d, paste0(stem, ".pdf"))
      ggplot2::ggsave(fp, plot, width = width, height = height, device = grDevices::cairo_pdf)
      message("wrote ", fp)
    }
  }
}

.save_named(p_auc, c(
  "Figure Weibull Dynamic Compare SOSM AUC",
  "Figure S5-MIMIC. Weibull dynamic model comparison AUC"
))
.save_named(p_c, c(
  "Figure Weibull Dynamic Compare SOSM Cindex",
  "Figure S6-MIMIC. Weibull dynamic model comparison C index"
))

# 同步 CSV 到 Tables（非 archive）
dir.create(file.path(mimic, "Tables"), showWarnings = FALSE, recursive = TRUE)
file.copy(csv, file.path(mimic, "Tables", "Table_Weibull_Dynamic_Compare_SOSM.csv"), overwrite = TRUE)

# ── 2) Table 3：NE 改写 ─────────────────────────────────────────────────────
t3_csv <- file.path(mimic, "Tables", "_archive", "Table_Piecewise_Cox_By_Class.csv")
tab <- utils::read.csv(t3_csv, check.names = FALSE, stringsAsFactors = FALSE)
cut_best <- as.integer(tab$cut[1])
# 就地清洗极值 cell
for (cn in names(tab)) {
  if (!grepl("^\\(", cn)) next
  v <- as.character(tab[[cn]])
  hr_num <- suppressWarnings(as.numeric(sub("\\s*\\(.*$", "", v)))
  bad <- grepl("Inf", v, ignore.case = TRUE) | (!is.na(hr_num) & hr_num >= 1e4)
  v[bad] <- "NE\u2020"
  tab[[cn]] <- v
}
utils::write.csv(tab, file.path(mimic, "Tables", "Table_Piecewise_Cox_By_Class.csv"), row.names = FALSE)
utils::write.csv(tab, t3_csv, row.names = FALSE)

ctx_stub <- list(config = list(project = list(database = "MIMIC")))
fp_t3 <- file.path(sosm, "Tables", "Table 3-MIMIC. Time-dependent HR for trajectory classes.xlsx")
fp_t3b <- file.path(mimic, "Tables", "Table 3-MIMIC. Time-dependent HR for trajectory classes.xlsx")
trajectory_export_table3_sci(
  ctx_stub, tab, cut_best, fp_t3,
  "Table 3. Time-dependent HR for trajectory classes of SOSM",
  end_day = 28L
)
if (exists("render_queued_tables", mode = "function")) render_queued_tables(ctx_stub)
file.copy(fp_t3, fp_t3b, overwrite = TRUE)
message("Table 3 rewritten with NE")

# ── 3) 轨迹图：KM 中位生存 NR ───────────────────────────────────────────────
long_fp <- file.path(mimic, "step14_trajectory_jlcm", "Data", "D01_long_SOSM_D_2.RData")
mod_fp  <- file.path(mimic, "step14_trajectory_jlcm", "Data", "D01_jlcm_SOSM_models.RData")
if (!file.exists(long_fp)) {
  long_fp <- list.files(file.path(mimic, "step14_trajectory_jlcm"),
                        pattern = "D01_long_SOSM_D_2", recursive = TRUE, full.names = TRUE)[1]
}
if (!file.exists(mod_fp)) {
  mod_fp <- list.files(file.path(mimic, "step14_trajectory_jlcm"),
                       pattern = "D01_jlcm_SOSM_models", recursive = TRUE, full.names = TRUE)[1]
}
stopifnot(file.exists(long_fp), file.exists(mod_fp))

e_l <- new.env(parent = emptyenv()); load(long_fp, envir = e_l)
long <- get(ls(e_l)[1], envir = e_l)
e_m <- new.env(parent = emptyenv()); load(mod_fp, envir = e_m)
mlist <- NULL
for (nm in c("models_list_with_cov", "models_list", "models")) {
  if (exists(nm, envir = e_m, inherits = FALSE)) { mlist <- get(nm, envir = e_m); break }
}
if (is.null(mlist)) {
  # 尝试任意含 m2 的 list
  for (nm in ls(e_m)) {
    obj <- get(nm, envir = e_m)
    if (is.list(obj) && !is.null(obj$m2)) { mlist <- obj; break }
  }
}
stopifnot(!is.null(mlist), !is.null(mlist$m2))

# id 列名
id_col <- intersect(c("subject_id", "unify_id_number", "subject_id_num", "id"), names(long))[1]
if (is.na(id_col)) stop("no id col in long")

# Class 列
if (!"Class" %in% names(long) && "class" %in% names(long)) long$Class <- long$class
if (!"Value" %in% names(long) && "SOSM" %in% names(long)) long$Value <- long$SOSM
if (!"Time" %in% names(long) && "time_day" %in% names(long)) long$Time <- long$time_day

p_tr <- .tpj04_make_plot(
  model_obj = mlist$m2, long_data = long, Index = "SOSM", D = 2L,
  cycle = 28L, id_col = id_col, font_family = font_family
)
stopifnot(!is.null(p_tr))

tr_stems <- c(
  "Figure Trajectory SOSM D2",
  "Figure 2-MIMIC. Trajectory of SOSM latent classes"
)
tr_dirs <- c(
  file.path(mimic, "step16_trajectory_plot_jlcm", "Figures"),
  file.path(mimic, "Figures", "_raw"),
  file.path(mimic, "Figures"),
  file.path(sosm, "Figures")
)
for (d in tr_dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
for (stem in tr_stems) {
  for (d in tr_dirs) {
    fp <- file.path(d, paste0(stem, ".pdf"))
    ggplot2::ggsave(fp, p_tr, width = 7.2, height = 3.6, device = grDevices::cairo_pdf)
    message("wrote ", fp)
  }
}

# ── 4) 四目录 png/tiff + image_information ─────────────────────────────────
if (exists("pub_figure_ensure_formats", mode = "function")) {
  for (fig_root in c(file.path(sosm, "Figures"), file.path(mimic, "Figures"))) {
    tryCatch(
      pub_figure_ensure_formats(fig_root, config = list()),
      error = function(e) message("pub_figure_ensure_formats: ", conditionMessage(e))
    )
  }
}

message("SOSM fix done.")
message("Correct AUC day4–14 (dyn): ", paste(round(res$auc_dyn, 3), collapse = ", "))
message("Correct C-index day4–14 (dyn): ", paste(round(res$c_dyn, 3), collapse = ", "))
message("p_auc were misread as AUC; now labeled P= on figures.")
