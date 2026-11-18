#!/usr/bin/env Rscript
# tests/smoke_trajectory_joint.R — 联合轨迹发病 核心块冒烟（合成数据）
# 直接调用 block 函数，不依赖完整 run_pipeline；验证 ingest→gbmtm→cox 接线。
options(warn = 1)
options(pipeline.single_db = TRUE)   # 单库交付文件名不追加库标签
`%||%` <- function(a, b) if (is.null(a)) b else a
# root = 从 tests/ 上级，或当前工作目录（约定在仓库根运行）
args <- commandArgs(trailingOnly = FALSE)
self <- grep("^--file=", args, value = TRUE)
root <- if (length(self)) normalizePath(file.path(dirname(dirname(sub("^--file=", "", self[1])))), mustWork = FALSE) else getwd()
if (!dir.exists(file.path(root, "Blocks"))) root <- getwd()

suppressMessages({library(mice); library(survival)})
source(file.path(root, "R/utils.R"))           # register_block / export_sci_table
source(file.path(root, "R/attrition_log.R"))   # attrition_record / *_component_missing_label
source(file.path(root, "R/mi_rubin_pool.R"))
source(file.path(root, "R/literature_trajectory_joint.R"))
source(file.path(root, "R/gbmtm_core.R"))
for (f in list.files(file.path(root, "Blocks/82_trajectory_incidence_joint"),
                     pattern = "^0[123]block", full.names = TRUE)) source(f)

set.seed(1)
n <- 300L
id <- sprintf("S%03d", seq_len(n))
mk <- function(tvec) {                     # 三类潜在轨迹 + 噪声
  cls <- sample(1:3, n, TRUE, c(.5,.3,.2))
  b0 <- c(8.3, 8.7, 8.9)[cls]; b1 <- c(0, .4, .8)[cls]
  sapply(tvec, function(t) b0 + b1 * (t - tvec[1]) + rnorm(n, 0, .15))
}
waves <- c(2, 4, 6)
tyg <- mk(waves); bmi <- mk(waves) * 2; whtr <- mk(waves) * 0.06
df <- data.frame(
  id = id, age = round(rnorm(n, 65, 8)), sex = rbinom(n, 1, .5),
  race_white = rbinom(n, 1, .8), edu = sample(1:7, n, TRUE),
  smoke = rbinom(n, 1, .3), drink = rbinom(n, 1, .4),
  hbp_d = rbinom(n, 1, .35), dm_d = rbinom(n, 1, .15), chol_d = rbinom(n, 1, .2),
  bpmed = rbinom(n, 1, .2), dmmed = rbinom(n, 1, .1),
  angina = 0, mi = 0, hf = 0, arry = 0, stroke = 0)
for (w in waves) {
  df[[paste0("TyG_w", w)]]  <- tyg[, which(waves == w)]
  df[[paste0("BMI_w", w)]]  <- bmi[, which(waves == w)]
  df[[paste0("WHtR_w", w)]] <- whtr[, which(waves == w)]
}
# 注入 ~10% 缺失到某波
miss <- sample(n, 30); df[[paste0("TyG_w6")]][miss] <- NA
cls_true <- sample(1:3, n, TRUE, c(.5,.3,.2))
df$cvd_event  <- rbinom(n, 1, c(.08,.18,.30)[cls_true])
df$cvd_time_m <- ifelse(df$cvd_event == 1, round(runif(n, 6, 90)), round(runif(n, 40, 120)))
df$cvd_time_m[df$cvd_event == 0] <- 120

tmp <- "/tmp/tj_smoke"; unlink(tmp, recursive = TRUE); dir.create(tmp, recursive = TRUE)
out <- file.path(tmp, "Output"); dir.create(out, recursive = TRUE)

cfg <- list(
  project = list(root = root, output_dir = out, name = "smoke_tj", database = "ELSA"),
  data = list(id_column = "id"),
  imputation = list(m = 2L, rubin_pool = TRUE),
  joint_trajectory = list(
    id_column = "id", waves = waves, wave_suffix = "_w",
    index_pairs = list(BMI_TyG = c("TyG", "BMI"), WHtR_TyG = c("TyG", "WHtR")),
    recompute_indices = FALSE,
    prevalent_exclude = list(cvd0 = c("angina","mi","hf","arry","stroke")),
    outcome = list(primary = list(name = "cvd", event_col = "cvd_event", time_col = "cvd_time_m")),
    k_range = 2:4, poly_degree = 2L, n_start = 4L, seed = 7L,
    model_sets = list(model1 = c("age","sex","race_white","edu"),
                      model2 = c("age","sex","race_white","edu","smoke","drink"),
                      model3 = c("age","sex","race_white","edu","smoke","drink","hbp_d","dm_d","chol_d")),
    subgroup = list(vars = c("Age_Group","Sex_lbl"), age_cutoff = 65L, min_events = 10L),
    sensitivity = list(items = c("S0_main","S1_exclude_first2y","S3_exclude_DM","S5_complete_case",
                                 "S7_PP_weighted","S9a_linear_time","S9b_cubic_time"))))

ctx <- list(config = cfg, data = list(raw = df), results = list(), log = list(),
            output_dir = out, root_output_dir = out)

cat("\n== ingest ==\n")
ctx <- block_tj_data_ingest(ctx)
stopifnot(!is.null(ctx$data$cleaned), nrow(ctx$data$cleaned) > 0)
cat("cohort n =", nrow(ctx$data$cleaned), "\n")
cat("outcome cols present:", all(c("cvd_event","cvd_time_m") %in% names(ctx$data$cleaned)), "\n")
cat("tj_outcome present:", !is.null(ctx$results$tj_outcome_cvd), "\n")

cat("\n== gbmtm ==\n")
ctx <- block_tj_gbmtm_fit(ctx)
gc <- grep("^grp_", names(ctx$data$cleaned), value = TRUE)
cat("class cols:", paste(gc, collapse=", "), "\n")
stopifnot(length(gc) == 2)
print(table(ctx$data$cleaned[[gc[1]]], useNA="ifany"))

cat("\n== minimal MICE (exercise Rubin path) ==\n")
# 造一些协变量缺失，建真实 mids，挂 ctx$results$mice_model + mice_row_ids
dfc <- ctx$data$cleaned
inject_na <- function(v, p=0.15) { i <- sample(seq_along(v), floor(p*length(v))); v[i] <- NA; v }
dfc$edu   <- inject_na(dfc$edu)
dfc$fvc   <- inject_na(dfc$age)          # 伪 fvc 供 pmm
dfc$drink <- inject_na(dfc$drink)
imp_dat <- dfc[, c("id","age","sex","race_white","edu","smoke","drink",
                   "hbp_d","dm_d","chol_d","bpmed","dmmed","fvc","cvd_event","cvd_time_m")]
set.seed(9); md <- mice::mice(imp_dat, m = 2L, maxit = 3L, method = "pmm",
                              printFlag = FALSE, seed = 9L)
ctx$data$cleaned <- dfc
ctx$results$mice_model <- md
ctx$results$mice_row_ids <- as.character(imp_dat$id)
cat("mids m =", md$m, " incomplete edu =", sum(is.na(imp_dat$edu)), "\n")

cat("\n== cox (Rubin m=2) ==\n")
ctx <- block_tj_cox_rubin(ctx)
cox <- ctx$results$tj_cox
cat("cox rows:", nrow(cox), " systems:", paste(unique(cox$system), collapse=", "), "\n")
print(cox[cox$model=="model3" & cox$outcome=="cvd", c("system","class","HR","lo","hi","p")], row.names = FALSE)
stopifnot(nrow(cox) > 0)

# 让 cox 能取到结局（ingest 用 primary name=cvd → tj_outcome_cvd）
ctx$results$tj_outcome_primary <- ctx$results$tj_outcome_cvd

cat("\n== subgroup (Rubin m=2) ==\n")
source(file.path(root, "Blocks/82_trajectory_incidence_joint/04block_tj_subgroup.R"))
ctx <- block_tj_subgroup(ctx)
sg <- ctx$results$tj_subgroup
cat("subgroup rows:", nrow(sg), " status:", paste(names(table(sg$status)), collapse="/"), "\n")
print(head(sg[sg$status=="OK", c("system","subgroup","level","class","n","events","HR","lo","hi","p")], 6), row.names = FALSE)
cat("P-int:\n"); print(ctx$results$tj_p_interaction, row.names = FALSE)
stopifnot(nrow(sg) > 0)

cat("\n== sensitivity (Rubin m=2) ==\n")
source(file.path(root, "Blocks/82_trajectory_incidence_joint/05block_tj_sensitivity.R"))
ctx <- block_tj_sensitivity(ctx)
sens <- ctx$results$tj_sensitivity
cat("sens rows:", nrow(sens), " analyses:", paste(unique(sens$analysis), collapse=", "), "\n")
print(sens[sens$system=="BMI_TyG" & sens$class=="T4", c("analysis","HR","lo","hi","p","m")], row.names = FALSE)
stopifnot(nrow(sens) > 0)

cat("\n== pub export ==\n")
ctx$results$tj_outcome_primary <- ctx$results$tj_outcome_cvd
source(file.path(root, "Blocks/82_trajectory_incidence_joint/06block_tj_pub_export.R"))
ctx <- block_tj_pub_export(ctx)
DR <- file.path(out, "summary_results")
cat("delivery tables:", length(list.files(file.path(DR,"Tables"))),
    " figs pdf:", length(list.files(file.path(DR,"Figures","pdf"))), "\n")
stopifnot(file.exists(file.path(DR, "Methods_statistical_analysis.md")),
          file.exists(file.path(DR, "Methods_software_versions.txt")),
          length(list.files(file.path(DR, "Tables"), pattern = "\\.xlsx$")) >= 2,
          length(list.files(file.path(DR, "Figures", "pdf"), pattern = "\\.pdf$")) >= 2)
cat("Tables:\n"); print(list.files(file.path(DR, "Tables")))
cat("Figures:\n"); print(list.files(file.path(DR, "Figures", "pdf")))

# ── recompute 回归：00_index 公式逐波重算 + attrition 记账（2026-11-18 eval 修复）──
cat("\n== recompute ingest regression ==\n")
source(file.path(root, "Blocks/82_trajectory_incidence_joint/01block_tj_data_ingest.R"))
nr <- 400L; waves_r <- c(2, 4, 6)
mkc <- function(mn, sd, sp = 0.03) { v <- stats::rnorm(nr, mn, sd); v[sample.int(nr, floor(nr * sp))] <- NA; v }
h0 <- stats::rnorm(nr, 168, 7); h0[sample.int(nr, 8L)] <- NA
dfr <- data.frame(id = sprintf("R%03d", seq_len(nr)), age = round(stats::runif(nr, 50, 88)),
  sex = rbinom(nr, 1, .5), fvc = mkc(300, 60),
  angina = rbinom(nr, 1, .1), mi = rbinom(nr, 1, .08))
for (w in waves_r) {
  dfr[[paste0("Glucose_w", w)]] <- abs(mkc(98, 13))
  dfr[[paste0("Triglycerides_w", w)]] <- abs(mkc(135, 45))
  dfr[[paste0("Weight_w", w)]] <- abs(mkc(76, 11, .06))
  dfr[[paste0("Waist_circumference_w", w)]] <- abs(mkc(91, 11, .04))
  dfr[[paste0("Height_w", w)]] <- if (w == waves_r[1]) h0 else { h <- h0; h[sample.int(nr, 6)] <- NA; h }
}
dfr$cvd_event <- rbinom(nr, 1, .14); dfr$cvd_time_m <- round(stats::runif(nr, 8, 120))
stopifnot(!any(grepl("^(TyG|BMI|WHtR)_w", names(dfr))))  # 无预置派生列→强制重算
out_r <- file.path(tmp, "Output_recompute"); dir.create(out_r, recursive = TRUE, showWarnings = FALSE)
cfg_r <- cfg
cfg_r$project$output_dir <- out_r
cfg_r$joint_trajectory$recompute_indices <- TRUE
cfg_r$joint_trajectory$prevalent_exclude <- list(cvd0 = c("angina", "mi"))
ctx_r <- list(config = cfg_r, data = list(raw = dfr), results = list(), log = list(),
              output_dir = out_r, root_output_dir = out_r)
ctx_r <- block_tj_data_ingest(ctx_r)
need_r <- as.vector(outer(c("TyG", "BMI", "WHtR"), paste0("_w", waves_r), paste0))
stopifnot(all(need_r %in% names(ctx_r$data$cleaned)))
stopifnot(is.numeric(ctx_r$data$cleaned$TyG_w2))
steps_r <- vapply(ctx_r$results$attrition$log %||% list(), function(x) x$step_id, character(1))
stopifnot(length(steps_r) >= 3)   # age/index_missing/prevalent/included 均须记账
ctx_r2 <- tryCatch(block_tj_gbmtm_fit(ctx_r), error = function(e) NULL)
stopifnot(!is.null(ctx_r2), any(grepl("^grp_", names(ctx_r2$data$cleaned))))
cat("recompute cols:", length(need_r), " attrition steps:", paste(steps_r, collapse=", "), "\n")

cat("\nSMOKE_OK\n")
