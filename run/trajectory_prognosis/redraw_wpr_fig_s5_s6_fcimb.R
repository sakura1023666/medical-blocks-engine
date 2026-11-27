#!/usr/bin/env Rscript
# Figure S5 / S6 对齐 fcimb image 5 / image 6（敏感性：完整随访 28 天死亡）
#   S5 = landmark 动态预测 2×2（类轨迹 + Predicted mortality risk）
#   S6 = PAMM 四联图（HR~WPR / 分层 landmark / HR~day / 分层 WPR）
#
#   Rscript run/trajectory_prognosis/redraw_wpr_fig_s5_s6_fcimb.R --index WPR

suppressPackageStartupMessages({ options(warn = 1) })

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

source("R/utils.R")
source("R/pipeline_runner.R")
source("configs/indices/composite_index_vars.R")
source("Blocks/26_trajectory/06block_trajectory_dynpred.R")
source("Blocks/26_trajectory/30block_trajectory_pamm.R")
if (file.exists("R/trajectory_survival_utils.R")) source("R/trajectory_survival_utils.R")

Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

ix <- .get("--index", "WPR")
proj <- .get("--proj", "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
if (!dir.exists(proj)) proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
ng <- as.integer(.get("--ng", "4"))

ix_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
ck_root <- file.path(proj, "checkpoints/by_index", ix)
sum_pdf <- file.path(ix_root, "summary_results/Figures/pdf")
sum_md <- file.path(ix_root, "summary_results/Figures/image_information")
dir.create(sum_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_md, recursive = TRUE, showWarnings = FALSE)
db_out <- file.path(ix_root, "mimic")
sens_model <- file.path(ix_root, "mimic/sensitivity_jlcm_landmark/allcause28/Data",
                        paste0("JLCM_", ix, "_ng", ng, "_allcause28.rds"))
copd_csv <- file.path(proj, "data/mimic/COPD-预后(1).csv")
pri_models <- file.path(ix_root, "mimic/step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))

# ── 0) 错位 Weibull S5–S8 → S14–S17 ────────────────────────────────────────
.reloc_weibull <- function() {
  map <- c(
    "Figure S5. Weibull dynamic model comparison C index.pdf" = "Figure S14. Weibull dynamic model comparison C index.pdf",
    "Figure S6. Weibull dynamic model comparison Accuracy.pdf" = "Figure S15. Weibull dynamic model comparison Accuracy.pdf",
    "Figure S7. Weibull dynamic model comparison Sensitivity.pdf" = "Figure S16. Weibull dynamic model comparison Sensitivity.pdf",
    "Figure S8. Weibull dynamic model comparison Specificity.pdf" = "Figure S17. Weibull dynamic model comparison Specificity.pdf"
  )
  for (old in names(map)) {
    op <- file.path(sum_pdf, old)
    np <- file.path(sum_pdf, map[[old]])
    if (file.exists(op)) file.rename(op, np)
    om <- file.path(sum_md, sub("\\.pdf$", ".md", old))
    nm <- file.path(sum_md, sub("\\.pdf$", ".md", map[[old]]))
    if (file.exists(om)) {
      txt <- readLines(om, warn = FALSE)
      txt <- gsub("Figure S5\\.", "Figure S14.", txt, fixed = FALSE)
      txt <- gsub("Figure S6\\.", "Figure S15.", txt, fixed = FALSE)
      txt <- gsub("Figure S7\\.", "Figure S16.", txt, fixed = FALSE)
      txt <- gsub("Figure S8\\.", "Figure S17.", txt, fixed = FALSE)
      txt <- gsub("# Figure S5", "# Figure S14", txt, fixed = TRUE)
      txt <- gsub("# Figure S6", "# Figure S15", txt, fixed = TRUE)
      txt <- gsub("# Figure S7", "# Figure S16", txt, fixed = TRUE)
      txt <- gsub("# Figure S8", "# Figure S17", txt, fixed = TRUE)
      writeLines(txt, nm)
      unlink(om)
    }
  }
  cli::cli_alert_info("已将错位 Weibull S5–S8 挪到 S14–S17")
}
.reloc_weibull()

# ── allcause 映射 ───────────────────────────────────────────────────────────
.allcause_map <- function() {
  stopifnot(file.exists(copd_csv))
  dt <- unique(data.table::fread(copd_csv), by = "subject_id")
  fmt <- "%d/%m/%Y %H:%M:%S"
  dt[, icu_in := as.POSIXct(icu_intime, format = fmt, tz = "UTC")]
  dt[is.na(icu_in), icu_in := as.POSIXct(icu_intime, format = "%d/%m/%Y %H:%M", tz = "UTC")]
  dt[, dead := as.POSIXct(dead_time, format = fmt, tz = "UTC")]
  dt[is.na(dead) & nzchar(as.character(dead_time)) & as.character(dead_time) != "NA",
     dead := as.POSIXct(dead_time, format = "%d/%m/%Y", tz = "UTC")]
  dt[, days_to_dead := as.numeric(difftime(dead, icu_in, units = "days"))]
  dt[, death_ac := as.integer(!is.na(dead) & is.finite(days_to_dead) & days_to_dead >= 0 & days_to_dead <= 28)]
  dt[, t_ac := data.table::fifelse(death_ac == 1L, pmax(0.01, pmin(28, days_to_dead)), 28)]
  dt[, .(
    subject_id = as.character(subject_id),
    survival_28d = death_ac,
    survival_time_28d = as.numeric(t_ac),
    surv_event = death_ac,
    surv_time = as.numeric(t_ac)
  )]
}

.pad_time0 <- function(md, time_var = "time_day") {
  # 使 landmark=2 时 ≤2 的唯一点 ≥3（0,1,2），对齐 weibull pad
  if (!time_var %in% names(md) || !"subject_id_num" %in% names(md)) return(md)
  tmin <- suppressWarnings(min(as.numeric(md[[time_var]]), na.rm = TRUE))
  if (!is.finite(tmin) || tmin <= 0) return(md)
  pad <- md[!duplicated(md$subject_id_num), , drop = FALSE]
  pad[[time_var]] <- 0
  rbind(pad, md)
}

.apply_allcause_to_df <- function(df, mp) {
  df$subject_id <- as.character(df$subject_id)
  drop_cols <- c("survival_28d", "survival_time_28d", "surv_event", "surv_time")
  df <- df[, setdiff(names(df), drop_cols), drop = FALSE]
  # 去掉无名/NA 列
  bad <- is.na(names(df)) | !nzchar(names(df))
  if (any(bad)) df <- df[, !bad, drop = FALSE]
  out <- merge(df, mp, by = "subject_id", all.x = TRUE)
  miss <- !is.finite(as.numeric(out$surv_event))
  if (any(miss)) {
    cli::cli_alert_warning("allcause 映射缺失 {sum(miss)} 行，保留不可估（下游会滤）")
  }
  out
}

# ── S5：敏感性 dynpred ──────────────────────────────────────────────────────
cli::cli_h1("Figure S5 · sensitivity dynpred (allcause28)")
if (!file.exists(sens_model)) stop("缺敏感性 JLCM：先跑 S4 allcause28 → ", sens_model)
if (!file.exists(pri_models)) stop("缺主文模型包: ", pri_models)

m_sens <- readRDS(sens_model)
e_pri <- new.env(parent = emptyenv())
load(pri_models, envir = e_pri)
mp <- .allcause_map()
md <- .apply_allcause_to_df(e_pri$model_data_final, mp)
md <- .pad_time0(md)
models <- e_pri$models_list_with_cov
models[[paste0("m", ng)]] <- m_sens
.md_id <- md[!duplicated(md$subject_id), c("subject_id", "surv_event"), drop = FALSE]
cli::cli_alert_info(
  "S5 allcause events={sum(as.integer(.md_id$surv_event) == 1L, na.rm = TRUE)}; time_day min={min(md$time_day, na.rm = TRUE)}"
)

prev <- file.path(ck_root, "mimic", "trajectory_km_class.rds")
if (!file.exists(prev)) prev <- file.path(ck_root, "mimic", "trajectory_dynpred.rds")
packed <- readRDS(prev)
ctx <- packed$ctx %||% packed
ctx$config <- config
ctx$config$trajectory_dynpred$pred_scale <- "mortality"
ctx$config$trajectory_dynpred$index_vars <- ix
ctx$config$trajectory_dynpred$jlcm$prefer_ng <- as.integer(ng)
# 文献 image5：2/5/7/12；已 pad time=0 以保住 Day2
ctx$config$trajectory_dynpred$jlcm$assessment_times <- c(2, 5, 7, 12)
ctx$config$trajectory_dynpred$jlcm$ndraws <- as.integer(.get("--ndraws", "120"))
if (is.null(ctx$config$trajectory)) ctx$config$trajectory <- list()
ctx$config$trajectory$jlcm <- ctx$config$trajectory_dynpred$jlcm
ctx$config$trajectory$index_vars <- ix
ctx$config$trajectory$cycle <- 28L
ctx$config$project$database <- "MIMIC"
ctx$config$project$output_dir <- db_out
ctx$config$project$mirror_pub_outputs_to_root <- TRUE

step_out <- file.path(db_out, "step18_trajectory_dynpred_sens")
dir.create(file.path(step_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
ctx$root_output_dir <- db_out
ctx$output_dir <- step_out
ctx$output_dir_figures <- file.path(step_out, "Figures")
unlink(list.files(ctx$output_dir_figures, pattern = "Dynpred|Dynamic", full.names = TRUE))

ctx$results$trajectory_jlcm_models[[ix]] <- list(
  models = models,
  model_data_final = md
)
ctx$results$trajectory_dynpred_newdata <- NULL

skip_dyn <- isTRUE(as.logical(.get("--skip-dynpred", "FALSE")))
src_existing <- list.files(
  file.path(db_out, "step18_trajectory_dynpred_sens/Figures"),
  pattern = "Dynpred.*\\.pdf$", full.names = TRUE
)
if (!length(src_existing))
  src_existing <- list.files(file.path(db_out, "Figures"), pattern = "Figure Dynpred WPR", full.names = TRUE)

if (skip_dyn && length(src_existing)) {
  cli::cli_alert_info("跳过 dynpred 重算，复用 {.file {src_existing[which.max(file.info(src_existing)$mtime)]}}")
} else {
  ctx <- block_trajectory_dynpred(ctx)
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx <- flush_pub_output_queues(ctx)
  } else if (exists("render_queued_figures", mode = "function")) {
    ctx <- render_queued_figures(ctx)
  }
}

src_s5 <- list.files(ctx$output_dir_figures, pattern = "Dynpred.*\\.pdf$", full.names = TRUE)
if (!length(src_s5))
  src_s5 <- list.files(file.path(db_out, "Figures"), pattern = paste0("Dynpred.*", ix), full.names = TRUE)
if (!length(src_s5))
  src_s5 <- src_existing
if (!length(src_s5)) stop("S5：未产出 Dynpred PDF")
src_s5 <- src_s5[which.max(file.info(src_s5)$mtime)]
out_s5 <- file.path(sum_pdf, "Figure S5. Sensitivity dynamic prediction by landmark.pdf")
file.copy(src_s5, out_s5, overwrite = TRUE)
writeLines(c(
  "# Figure S5. Sensitivity dynamic prediction by landmark",
  "",
  "## 图面说明",
  "",
  "2×2 landmark 动态预测（对齐 fcimb Supplementary Figure 5 / image 5.tif）。",
  "各面板：竖虚线=landmark；左侧=该类 WPR 历史均值（点线）；右侧=Predicted mortality risk 至第 28 天。",
  "敏感性结局：MIMIC **完整随访 28 天死亡**（含出院后）；JLCM 为 allcause28 重估模型。",
  "Landmark = 2 / 5 / 7 / 12 天（time=0 历史垫底以保证 Day2 可估）。",
  "",
  "## 分析上下文",
  "",
  paste0("- 暴露：", ix, "；敏感性结局：28 天完整随访死亡"),
  "- 数据库：MIMIC-IV derivation",
  "- 是否拼图：否（单库 2×2）",
  ""
), file.path(sum_md, "Figure S5. Sensitivity dynamic prediction by landmark.md"))
cli::cli_alert_success("S5 → {.file {out_s5}}")

# ── S6：敏感性 PAMM ─────────────────────────────────────────────────────────
cli::cli_h1("Figure S6 · sensitivity PAMM (allcause28)")
prev_p <- file.path(ck_root, "mimic", "trajectory_pamm.rds")
if (!file.exists(prev_p)) prev_p <- file.path(ck_root, "mimic", "trajectory_km_class.rds")
packed_p <- readRDS(prev_p)
ctxp <- packed_p$ctx %||% packed_p
ctxp$config <- config
ctxp$config$trajectory_pamm$index_vars <- ix
ctxp$config$trajectory_pamm$export_figures <- TRUE
ctxp$config$trajectory_pamm$plot_landmarks <- c(2, 5, 12)
ctxp$config$trajectory_pamm$hr_ylab <- "HR for 28-day mortality"
ctxp$config$project$database <- "MIMIC"
ctxp$config$project$output_dir <- db_out

step_p <- file.path(db_out, "step25_trajectory_pamm_sens")
dir.create(file.path(step_p, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(step_p, "Tables", "PAMM"), recursive = TRUE, showWarnings = FALSE)
ctxp$root_output_dir <- db_out
ctxp$output_dir <- step_p
ctxp$output_dir_tables <- file.path(step_p, "Tables")
ctxp$output_dir_figures <- file.path(step_p, "Figures")

# imputed 生存改为 allcause28
if (is.null(ctxp$data$imputed) || !nrow(ctxp$data$imputed)) {
  mi <- file.path(db_out, "step06_imputation/D01_AfterMI_Data.RData")
  if (file.exists(mi)) {
    e <- new.env(parent = emptyenv()); load(mi, envir = e)
    ctxp$data$imputed <- e$imputed %||% e$data %||% e[[ls(e)[1]]]
  }
}
imp <- .apply_allcause_to_df(ctxp$data$imputed, mp)
# PAMM 主要读 survival_28d / survival_time_28d
if (!"survival_28d" %in% names(imp) && "surv_event" %in% names(imp))
  imp$survival_28d <- imp$surv_event
if (!"survival_time_28d" %in% names(imp) && "surv_time" %in% names(imp))
  imp$survival_time_28d <- imp$surv_time
ctxp$data$imputed <- imp
n_id <- length(unique(imp$subject_id))
n_ev <- sum(as.integer(imp[!duplicated(imp$subject_id), "survival_28d"]) == 1L, na.rm = TRUE)
cli::cli_alert_info("PAMM 敏感性事件数={n_ev} / n={n_id}")

ctxp <- block_trajectory_pamm(ctxp)
src_s6 <- list.files(file.path(step_p, "Figures"), pattern = "PAMM.*\\.pdf$", full.names = TRUE)
if (!length(src_s6)) stop("S6：未产出 PAMM PDF")
src_s6 <- src_s6[which.max(file.info(src_s6)$mtime)]
out_s6 <- file.path(sum_pdf, "Figure S6. Sensitivity PAMM time-varying association.pdf")
file.copy(src_s6, out_s6, overwrite = TRUE)
writeLines(c(
  "# Figure S6. Sensitivity PAMM time-varying association",
  "",
  "## 图面说明",
  "",
  "四联图（对齐 fcimb Supplementary Figure 6 / image 6.tif）：",
  "(a) HR~WPR；(b) 按 landmark 分层；(c) HR~Days；(d) 按 WPR 水平分层。",
  "敏感性结局：MIMIC **完整随访 28 天死亡**（与 S4/S5 同口径）。",
  "",
  "## 分析上下文",
  "",
  paste0("- 暴露：", ix, " 连续时变；敏感性结局：28 天完整随访死亡"),
  "- 数据库：MIMIC-IV derivation",
  "- 是否拼图：否（单库四联）",
  ""
), file.path(sum_md, "Figure S6. Sensitivity PAMM time-varying association.md"))
cli::cli_alert_success("S6 → {.file {out_s6}}")

cli::cli_alert_success("Figure S5/S6 已按文献 image5/image6 收口")
