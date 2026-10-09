#!/usr/bin/env Rscript
###############################################################################
#  build_aki_sosm_wpr_replication.R — AKI SOSM+WPR 原文复刻 Task 8 CLI
#
#  规格：docs/superpowers/specs/2026-09-17-aki-sosm-wpr-original-paper-replication-design.md
#  简报：.superpowers/sdd/task-8-brief.md
#
#  用法：
#    Rscript run/ml/build_aki_sosm_wpr_replication.R \
#      --config "<study>/config.R" --index "SOSM+WPR" \
#      [--out "<success>/publication_literature_final"] \
#      [--dry-run] [--full-train] [--methods logistic,rf,...] \
#      [--fit-timeout 2100] [--panel-timeout 600] [--assoc-timeout 2400]
#
#  行为：
#   - --dry-run：只打印 34 角色（编号/role/title/db_mode/reference_source/
#     adaptation/来源），不写盘。
#   - 实际构建只写 <out>.__staging__；全部角色就位 + 图四格式 + 逐表
#     pub_xlsx_verify + MANIFEST/README + 90 天字样扫描通过后，原子替换
#     <out>（旧 <out> 先 rename 为 .__previous__ 备份；rename 失败回滚）。
#   - ML：三层（overall / sofa_le10 / sofa_ge11）默认尝试全量五模型；
#     超时/失败降级 logistic，MANIFEST 如实标 smoke_only，绝不谎称全量。
#   - 只调用 Task4/5/6/7 模块（R/ml_reference_*.R 等），不改其实现。
#
#  铁律：禁 90 天字样入终稿；Table1 禁 AKI/No AKI 误标（Survivor/Non-survivor）；
#  eICU 冻结不重训（trained_in=MIMIC-IV）；小数位 3/3/2/4；发表图四目录。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
}

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default = "") {
  hit <- match(flag, args)
  if (is.na(hit) || hit >= length(args)) return(default)
  args[[hit + 1L]]
}

config_path <- arg_value("--config")
index_label <- arg_value("--index")
dry_run <- "--dry-run" %in% args
full_train <- "--full-train" %in% args
methods_arg <- arg_value("--methods", "")
quick <- "--quick" %in% args
if (quick && !nzchar(methods_arg)) methods_arg <- "logistic,rf"
fit_timeout <- suppressWarnings(as.numeric(arg_value("--fit-timeout", "2100"))[1])
panel_timeout <- suppressWarnings(as.numeric(arg_value("--panel-timeout", "600"))[1])
assoc_timeout <- suppressWarnings(as.numeric(arg_value("--assoc-timeout", "2400"))[1])

if (!nzchar(config_path) || !file.exists(config_path)) {
  stop("--config 必须指向存在的研究 config.R", call. = FALSE)
}
authorized_indices <- c("SOSM+WPR", "ACAG+RAR")
if (!index_label %in% authorized_indices) {
  stop("本终稿构建仅授权 --index 为: ", paste(authorized_indices, collapse = ", "),
       call. = FALSE)
}
idx_parts <- strsplit(index_label, "+", fixed = TRUE)[[1]]
if (length(idx_parts) != 2L || any(!nzchar(idx_parts))) {
  stop("--index 须为 A+B 形式（如 ACAG+RAR）", call. = FALSE)
}
INDEX_A <- idx_parts[[1]]
INDEX_B <- idx_parts[[2]]
INDEX_LABEL <- index_label
# 供 Task4 关联图/表读取当前双指标
# .ref_assoc_set_indices 在 source 后调用

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root) || !dir.exists(file.path(engine_root, "R"))) {
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  of <- if (length(fa)) sub("^--file=", "", fa[[1]]) else
    tryCatch(sys.frame(1)$ofile, error = function(e) NULL) %||% "run/ml/build.R"
  cand <- normalizePath(file.path(dirname(of), "../.."), winslash = "/",
                        mustWork = FALSE)
  engine_root <- if (dir.exists(file.path(cand, "R"))) cand else
    "/mnt/e/01block/01Block-new-Final"
}
engine_root <- normalizePath(engine_root, winslash = "/", mustWork = TRUE)
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root)

suppressWarnings(suppressMessages({
  source(file.path(engine_root, "R/utils.R"))
  source(file.path(engine_root, "R/ml_assoc_covariate_rule.R"))
  source(file.path(engine_root, "R/ml_stratified_ctx.R"))
  source(file.path(engine_root, "R/ml_dual_dev_ext.R"))
  source(file.path(engine_root, "R/prognosis_reference_assoc.R"))
  source(file.path(engine_root, "R/prognosis_landmark_ph.R"))
  source(file.path(engine_root, "R/ml_reference_assoc_figures.R"))
  source(file.path(engine_root, "R/ml_frozen_model_bundle.R"))
  source(file.path(engine_root, "R/ml_external_frozen_shap.R"))
  source(file.path(engine_root, "R/ml_reference_paper_profile.R"))
  source(file.path(engine_root, "R/pub_figure_export.R"))
  source(file.path(engine_root, "R/pub_xlsx_surgical.R"))
}))
.ref_assoc_set_indices(c(INDEX_A, INDEX_B))

study_root <- normalizePath(dirname(normalizePath(config_path, winslash = "/")),
                            winslash = "/", mustWork = TRUE)
index_root <- file.path(study_root, "by_index", paste0("【success】", index_label))
if (!dir.exists(index_root)) {
  stop("成功指标目录不存在: ", index_root, call. = FALSE)
}
ck_root <- file.path(study_root, "checkpoints", "by_index", index_label)

## ---------------------------------------------------------------------------
## 安全边界：out 必须位于【success】<index> 内，且不得是受保护旧目录
## ---------------------------------------------------------------------------
resolve_abs <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
index_root_abs <- resolve_abs(index_root)
out_final <- resolve_abs(arg_value("--out",
                                   file.path(index_root_abs,
                                             "publication_literature_final")))
is_inside <- function(child, parent) {
  child <- resolve_abs(child); parent <- resolve_abs(parent)
  nchar(child) >= nchar(parent) &&
    substr(child, 1L, nchar(parent)) == parent
}
if (!is_inside(out_final, index_root_abs)) {
  stop("安全边界：--out 必须位于 ", index_root_abs, " 内（实际: ", out_final, "）",
       call. = FALSE)
}
protected <- resolve_abs(file.path(index_root_abs, c(
  "Tables", "Figures", "MIMIC_IV", "eICU", "Shiny", "code",
  "publication_final", "publication_literature_final",
  "publication_literature_final.__staging__",
  "publication_literature_final.__previous__")))
protected <- setdiff(protected, out_final)  # out 本身即默认终稿路径
hit_prot <- protected[resolve_abs(out_final) == protected |
                        vapply(protected, function(p) is_inside(out_final, p),
                               logical(1))]
if (length(hit_prot)) {
  stop("安全边界：--out 不得覆盖受保护目录（原 Tables/Figures/MIMIC_IV/eICU/旧终稿等）：",
       hit_prot[[1]], call. = FALSE)
}
staging <- paste0(out_final, ".__staging__")

## ---------------------------------------------------------------------------
## 路径：checkpoints / attrition CSV / D02 / 旧表
## ---------------------------------------------------------------------------
mi_assoc_ckpt <- file.path(ck_root, "MIMIC_IV", "step16_ml_assoc_bundle.rds")
ei_assoc_ckpt <- file.path(ck_root, "eICU", "step15_ml_assoc_bundle.rds")
mi_ml_ckpt <- file.path(ck_root, "MIMIC_IV", "step17_ml_models_bundle.rds")
ei_ext_ckpt <- file.path(ck_root, "eICU", "step16_ml_eval_external.rds")
for (f in c(mi_assoc_ckpt, ei_assoc_ckpt, mi_ml_ckpt, ei_ext_ckpt)) {
  if (!file.exists(f)) stop("缺关键 checkpoint（禁止编造输入）: ", f, call. = FALSE)
}
find_attrition_csv <- function(db_dir) {
  root <- file.path(index_root, db_dir)
  hits <- list.files(root, pattern = "attrition_flowchart[/\\\\]Tables[/\\\\].*\\.csv$",
                     recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  hits <- hits[!grepl("image_information", hits)]
  if (!length(hits)) {
    hits <- list.files(root, pattern = "(?i)Flowchart_attrition.*\\.csv$",
                       recursive = TRUE, full.names = TRUE)
  }
  if (!length(hits)) stop("缺真实 attrition CSV（Figure 1 禁止编造）: ", root,
                          call. = FALSE)
  steps <- suppressWarnings(as.integer(gsub("step", "", sub(".*(step[0-9]+).*", "\\1", hits))))
  normalizePath(hits[order(steps, decreasing = TRUE)][1], winslash = "/",
                mustWork = FALSE)
}
mimic_csv <- find_attrition_csv("MIMIC_IV")   # 槽名 Flowchart_attrition_nhanes.csv，按目录判库
eicu_csv <- find_attrition_csv("eICU")        # 槽名 Flowchart_attrition_mimic.csv，按目录判库
old_tables <- file.path(index_root, "Tables")
old_fig_pdf <- file.path(index_root, "Figures", "pdf")
data_dir <- file.path(study_root, "data")

## 研究 config（失败不致命：各 ctx 自带 config）
cfg <- tryCatch({
  # 课题 config.R 内部以 source(local=FALSE) 挂接 study_interface 构建脚本，
  # 因此须在全局环境加载（独立 CLI 进程，退出即释放）。
  sys.source(config_path, envir = .GlobalEnv)
  if (exists("config", envir = .GlobalEnv, inherits = FALSE)) {
    get("config", envir = .GlobalEnv, inherits = FALSE)
  } else list()
}, error = function(e) {
  message("config 读取失败（用 ctx 内嵌 config + 默认 pub_digits 兜底）: ",
          conditionMessage(e))
  list()
})

## ---------------------------------------------------------------------------
## 34 角色 profile + 来源映射（dry-run 与实际共用）
## ---------------------------------------------------------------------------
profile <- ml_reference_profile_40537296(indices = c(INDEX_A, INDEX_B))
stopifnot(nrow(profile) == 34L)

sources_for_role <- function(kind, num) {
  if (kind == "figure_main") {
    switch(num,
      "1" = paste0("真实 attrition CSV（按目录判库，槽名不可信）: ",
                   sub(paste0(".*", gsub("+", "\\+", INDEX_LABEL, fixed=TRUE), "/"), "", mimic_csv), " + ",
                   sub(paste0(".*", gsub("+", "\\+", INDEX_LABEL, fixed=TRUE), "/"), "", eicu_csv),
                   "（Task7 ml_reference_build_flowchart）"),
      "2" = "Task4 ref_assoc_run_all -> Figure 2 KM（双库 step16 assoc ctx，只读）",
      "3" = "Task4 ref_assoc_run_all -> Figure 3 RCS（同上）",
      "4" = "Task4 ref_assoc_run_all -> Figure 4 ROC（同上）",
      "5" = "Task4 ref_assoc_run_all -> Figure 5 Landmark（MIMIC 锁定 + eICU 验证）",
      "6" = "Task4 ref_assoc_run_all -> Figure 6 Forest（同上）",
      "7" = "Task6 ml_ref_fig7_boruta；Boruta 仅 MIMIC-IV train（step14/step17 ctx，只读）",
      "8" = "Task6 ml_ref_fig8_grid；Task5 冻结资产（fit->save->load->predict，eICU no_refit）")
  } else if (kind == "figure_supp") {
    switch(num,
      "1" = "CLI 补产：per-db per-stratum cox.zph beta(t) 平滑趋势（分析帧只读；Joint_score 用冻结 lock）",
      "2" = "Task6 ml_ref_s2_boruta（MIMIC-IV overall train Boruta，只读输入）",
      "3" = "Task6 ml_ref_s3_roc（overall 冻结 bundle：MIMIC internal + eICU external）",
      "4" = "Task6 ml_ref_s4_shap（overall 最优冻结模型 SHAP，双库；模型校验和一致断言）",
      "5" = "Task6 ml_ref_s5_waterfalls（SOFA 两层 x 双库 x Survivor/Non-survivor，ml_pick_paired_cases）",
      "6" = paste0("旧 Figures/pdf 只读拷贝重编号：",
                   "Figure 4. ML calibration training internal and external.pdf"),
      "7" = paste0("旧 Figures/pdf 只读拷贝重编号：",
                   "Figure 5. ML metrics training internal and external.pdf"),
      "8" = paste0("旧 Figures/pdf 只读拷贝重编号：",
                   "Figure 6. ML DCA training internal and external.pdf"))
  } else if (kind == "table_main") {
    switch(num,
      "1" = "Task7 ml_reference_build_table1（两库 step16 assoc ctx$data$imputed；Survivor/Non-survivor）",
      "2" = "Task4 ref_assoc_run_all -> Table 2 Joint group Cox（双库 ctx）")
  } else {
    switch(num,
      "1" = "Task7 ml_reference_build_s1（D02_result_MIMIC/eICU 实测旗标 + 上游证据不足标注）",
      "2" = "CLI 补产：双库单因素 Cox（step16 assoc ctx 分析帧只读；VIF 后 Model2 池 + SOSM/WPR）",
      "3" = "Task7 ml_reference_build_s3（本次新冻结资产 feature_manifest 继承审计）",
      "4" = "Task4 -> Table S4 SOSM WPR Cox",
      "5" = "Task4 -> Table S5 ROC/DeLong（Fig4 同源）",
      "6" = "Task4 -> Table S6 PH Overall",
      "7" = "Task4 -> Table S7 PH SOFA <=10",
      "8" = "Task4 -> Table S8 PH SOFA >=11",
      "9" = "Task4 -> Table S9 排除基线 Glucose<70 敏感性（D02 Glucose 按 ID match）",
      "10" = "Task4 -> Table S10 complete-case 敏感性",
      "11" = "Task5 ml_frozen_bind_performance（本次全量三层 bundle + eICU 冻结外验）",
      "12" = paste0("旧 Tables 只读重排：Table 3/4/5 ML performance wide ",
                    "training/validation/eICU-external"),
      "13" = "旧 Tables/Table S7-MIMIC IV. Hyperparameters…（只读重排）",
      "14" = "旧 Tables/Table S8-MIMIC IV. Log-Loss…（只读重排）",
      "15" = "旧 Tables/Table S9-MIMIC IV. DeLong tests (training set)…（只读重排）",
      "16" = "旧 Tables/Table S10-MIMIC IV. NRI and IDI (training set)…（只读重排）")
  }
}

if (isTRUE(dry_run)) {
  cat(sprintf("=== AKI %s 原文复刻：34 角色（dry-run，不写盘） ===\n", INDEX_LABEL))
  cat(sprintf("out(终稿目标) = %s\nstaging       = %s\n", out_final, staging))
  cat(sprintf("full-train 尝试: %s | methods: %s | fit-timeout=%ss panel-timeout=%s\n",
              if (full_train) "yes(explicit)" else "yes(default; 超时/失败降级 logistic)",
              if (nzchar(methods_arg)) methods_arg else "logistic,dt,rf,xgboost,lightgbm",
              fit_timeout, panel_timeout))
  for (i in seq_len(nrow(profile))) {
    cat(sprintf("\n[%02d] %s %s | %s\n  role: %s\n  title: %s\n  db_mode: %s\n  reference_source: %s\n  adaptation: %s\n  source: %s\n",
                i, profile$kind[i],
                if (grepl("supp", profile$kind[i])) paste0("S", profile$number[i]) else profile$number[i],
                if (grepl("figure", profile$kind[i])) "FIGURE" else "TABLE",
                profile$role[i], profile$title[i], profile$db_mode[i],
                profile$reference_source[i], profile$adaptation[i],
                sources_for_role(profile$kind[i], profile$number[i])))
  }
  cat(sprintf("\nDRY_RUN_OK roles=%d | 终稿 90 天字样扫描（profile 全列）=%d\n",
              nrow(profile),
              sum(grepl("90[- ]?(day|d)|90\\s*天", unlist(profile),
                        ignore.case = TRUE))))
  quit(status = 0)
}

## ---------------------------------------------------------------------------
## staging 初始化 + 构建日志 + 预算工具
## ---------------------------------------------------------------------------
unlink(staging, recursive = TRUE)
if (!dir.create(staging, recursive = TRUE, showWarnings = FALSE) &&
    !dir.exists(staging)) {
  stop("无法创建 staging 目录: ", staging, call. = FALSE)
}
dir.create(file.path(staging, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(staging, "Tables"), recursive = TRUE, showWarnings = FALSE)
assets_root <- file.path(staging, "_assets/model_assets")
dir.create(assets_root, recursive = TRUE, showWarnings = FALSE)

log_tsv <- file.path(staging, "_build_log.tsv")
writeLines("time\tstage\tstatus\tseconds\tdetail", log_tsv)
log_stage <- function(stage, status, seconds = NA_real_, detail = "") {
  # atomic_swap 之后 staging 已被 rename：日志跟随迁移到终稿目录，禁止崩尾
  if (!dir.exists(dirname(log_tsv))) {
    cand <- file.path(out_final, "_build_log.tsv")
    if (file.exists(cand) || dir.exists(out_final)) log_tsv <<- cand
  }
  dir.create(dirname(log_tsv), recursive = TRUE, showWarnings = FALSE)
  line <- sprintf("%s\t%s\t%s\t%s\t%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  gsub("\t", " ", stage), status,
                  if (is.na(seconds)) "NA" else round(seconds, 1),
                  gsub("[\t\n]+", " ", as.character(detail)[1]))
  write.table(line, log_tsv, append = TRUE, sep = "\t",
              col.names = FALSE, row.names = FALSE, quote = FALSE)
  message(sprintf("[%-30s] %-10s %s", stage, status, detail))
}

with_budget <- function(sec, expr) {
  setTimeLimit(elapsed = as.integer(max(5, sec)), transient = TRUE)
  on.exit(try(suppressWarnings(
    setTimeLimit(elapsed = Inf, cpu = Inf, elapsed.last = Inf, cpu.last = Inf)),
    silent = TRUE), add = TRUE)
  force(expr)
}
run_stage <- function(name, sec, expr) {
  t0 <- Sys.time()
  r <- tryCatch(
    withCallingHandlers(with_budget(sec, expr),
                        warning = function(w) invokeRestart("muffleWarning")),
    error = function(e) structure(conditionMessage(e), class = "stage_fail"))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (inherits(r, "stage_fail")) {
    log_stage(name, "FAIL", el, r)
    return(list(ok = FALSE, value = NULL, seconds = el, error = r))
  }
  log_stage(name, "OK", el, if (is.character(r)) r else
              if (is.list(r) && is.character(r$msg)) r$msg else "")
  list(ok = TRUE, value = r, seconds = el)
}

if (is.null(cfg$pub_digits)) {
  cfg$pub_digits <- list(est = 3L, p = 3L, desc = 2L, cutoff = 4L)
}
pipeline_apply_pub_digits(cfg)

## SOFA 分层切点（默认三层 0–4 / 5–10 / ≥11，对应原文 NGR/Pre-DM/DM 三层）。
## 单一事实来源：所有 strata_keys / labels / layer_filter 均由此派生。
SOFA_BREAKS <- suppressWarnings(as.integer(
  unlist(cfg$reference$sofa_breaks %||% cfg$ml_frozen_bundle$sofa_breaks %||% c(4L, 10L))
))
if (!length(SOFA_BREAKS) || anyNA(SOFA_BREAKS)) SOFA_BREAKS <- c(4L, 10L)
SOFA_BREAKS <- unique(sort(SOFA_BREAKS))
SOFA_SPEC <- ml_stratum_spec_sofa(breaks = SOFA_BREAKS)

# pub_format_est 是标量函数：向量输入会退化为「首元素原始值」（曾把 S11 整列
# Estimate 写成同一个未格式化数字）。向量化包装强制逐元素 3 位。
fmt3_vec <- function(v) vapply(as.numeric(v), function(x) pub_format_est(x),
                               character(1), USE.NAMES = FALSE)

## ---------------------------------------------------------------------------
## 载入 ctx（只读）+ 发布口径重标（仅内存副本，checkpoint 文件不改）
## ---------------------------------------------------------------------------
mi_assoc <- readRDS(mi_assoc_ckpt)$ctx
ei_assoc <- readRDS(ei_assoc_ckpt)$ctx
mi_ml <- readRDS(mi_ml_ckpt)$ctx
ei_ext <- readRDS(ei_ext_ckpt)$ctx

## 文献 Table2 Model1–3：用课题 config 的 assoc_covariate 覆盖 checkpoint 内旧方案
## （UV/VIF 结果仍来自 checkpoint；scheme/clinical_covariates 必须跟 config.R）
.inject_literature_assoc <- function(ctx, study_cfg) {
  ac <- study_cfg$assoc_covariate %||% list()
  if (!identical(as.character(ac$scheme %||% "")[1L], "literature_m123")) {
    return(ctx)
  }
  ctx$config$assoc_covariate <- modifyList(
    ctx$config$assoc_covariate %||% list(), ac
  )
  dat <- ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned
  nm <- if (is.data.frame(dat)) names(dat) else NULL
  res <- ml_resolve_assoc_covariates(ctx, data_names = nm)
  ctx$results$assoc_model1_factors <- res$M1
  ctx$results$assoc_model2_factors <- res$M2
  ctx$results$assoc_model3_factors <- res$M3 %||% res$M2
  ctx$results$assoc_model2_extras <- res$extras %||% setdiff(res$M2, res$M1)
  ctx$results$assoc_covariate_note <- res$note
  ctx$results$assoc_covariate_scheme <- res$scheme %||% "literature_m123"
  ctx$results$Model3Factors <- res$M3 %||% res$M2
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("literature_m123 injected: {res$note}")
  } else {
    message("literature_m123 injected: ", res$note)
  }
  ctx
}
mi_assoc <- .inject_literature_assoc(mi_assoc, cfg)
## eICU：继承主库 literature Model2/3（外验不重做 UV∩VIF）
if (identical(as.character((cfg$assoc_covariate %||% list())$scheme %||% "")[1L],
              "literature_m123")) {
  ei_assoc$config$assoc_covariate <- modifyList(
    ei_assoc$config$assoc_covariate %||% list(),
    cfg$assoc_covariate %||% list()
  )
  ei_assoc$results$assoc_covariates_inherited_from <- "primary"
  ei_assoc$results$assoc_model1_factors <- mi_assoc$results$assoc_model1_factors
  ei_assoc$results$assoc_model2_factors <- mi_assoc$results$assoc_model2_factors
  ei_assoc$results$assoc_model3_factors <- mi_assoc$results$assoc_model3_factors
  ei_assoc$results$assoc_covariate_note <- paste0(
    "inherited from primary: ", mi_assoc$results$assoc_covariate_note %||% ""
  )
  ei_assoc$results$assoc_covariate_scheme <- "literature_m123"
  ei_assoc$results$Model3Factors <- mi_assoc$results$Model3Factors
  ei_assoc$results$tb1 <- mi_assoc$results$tb1
  ei_assoc$results$vif_screen_pass <- mi_assoc$results$vif_screen_pass
}

relabel_outcome <- function(df) {
  if (!is.data.frame(df)) return(df)
  map_lvl <- function(v) {
    lv <- levels(v) %||% character(0)
    if (length(lv)) {
      new_lv <- ifelse(lv == "AKI", "Non-survivor",
                       ifelse(lv == "No AKI", "Survivor", lv))
      out <- new_lv[as.integer(v)]
      keep <- !(lv %in% c("AKI", "No AKI"))
      out[keep[as.integer(v)]] <- as.character(v)[keep[as.integer(v)]]
      factor(out, levels = union(c("Survivor", "Non-survivor"), new_lv[keep]))
    } else {
      raw <- trimws(as.character(v))
      out <- ifelse(raw == "AKI", "Non-survivor",
                    ifelse(raw == "No AKI", "Survivor", raw))
      factor(out, levels = c("Survivor", "Non-survivor"))
    }
  }
  if ("Group" %in% names(df)) df$Group <- map_lvl(df$Group)
  if ("fustatus" %in% names(df)) df$fustatus <- map_lvl(df$fustatus)
  df
}
relabel_ctx <- function(ctx) {
  ctx$config$project$analysis_group <- "Non-survivor"
  ctx$config$project$reference_group <- "Survivor"
  ctx$data <- lapply(ctx$data, relabel_outcome)
  ctx
}
mi_ml <- relabel_ctx(mi_ml)
ei_ext <- relabel_ctx(ei_ext)
mi_ml$results$authority_checkpoint_path <- mi_ml_ckpt

# 建模 ctx 配置（与 Task5 已验证 smoke 一致；层内 restrict_to_train）
mi_ml$config$feature_selection$enable <- TRUE
mi_ml$config$feature_selection$restrict_to_train <- TRUE
mi_ml$config$feature_selection$target_n_features_min <- 5L
mi_ml$config$feature_selection$target_n_features_max <- 25L
mi_ml$config$feature_selection_boruta <- list(
  enable = TRUE, seed = 42L, boruta_max_runs = 50L, pause_enable = FALSE)
mi_ml$config$ml_logistic$cv_folds <- 5L

## D02 Glucose（按首见 ID match；S9 敏感性用）
d02_env <- function(f) { e <- new.env(); load(f, envir = e); e$data_imp }
d02_mi <- d02_env(file.path(data_dir, "D02_result_MIMIC.RData"))
d02_ei <- d02_env(file.path(data_dir, "D02_result_eICU.RData"))
glucose_from_d02 <- function(d, src) {
  gi <- match(as.character(d$ID), as.character(src$ID))
  data.frame(ID = d$ID, Glucose = src$Glucose[gi], stringsAsFactors = FALSE)
}
cc_frame <- function(d, vars) {
  v <- intersect(c(vars, "futime", "fustatus"), names(d))
  d[stats::complete.cases(d[, v, drop = FALSE]), , drop = FALSE]
}
m2vars <- intersect(unique(c(mi_assoc$results$Model1Factors,
                             mi_assoc$results$Model2Factors)),
                    names(mi_assoc$data$imputed))

mimic_in <- list(
  train = mi_assoc$data$train, analysis = mi_assoc$data$imputed,
  complete_case = cc_frame(mi_assoc$data$imputed, c(INDEX_A, INDEX_B, m2vars)),
  baseline_glucose = glucose_from_d02(mi_assoc$data$imputed, d02_mi),
  assoc_ctx = mi_assoc, config = mi_assoc$config,
  authority_checkpoint = mi_assoc_ckpt)
eicu_in <- list(
  analysis = ei_assoc$data$imputed,
  complete_case = cc_frame(ei_assoc$data$imputed, c(INDEX_A, INDEX_B, m2vars)),
  baseline_glucose = glucose_from_d02(ei_assoc$data$imputed, d02_ei),
  assoc_ctx = ei_assoc, config = ei_assoc$config)

## ---------------------------------------------------------------------------
## A) Figure 1 + Task4 关联全套（Fig2-6 / Table2 / S4-S10）+ Table1 / S1 / S2
## ---------------------------------------------------------------------------
r <- run_stage("figure1_flowchart", 300, {
  p <- ml_reference_build_flowchart(mimic_csv, eicu_csv, staging)
  sprintf("target=%s", basename(p))
})

r <- run_stage("task4_ref_assoc_all", assoc_timeout, {
  res <- ref_assoc_run_all(mimic_in, eicu_in, staging, cutoff = SOFA_BREAKS,
                           grid_n = 40L, quiet = FALSE,
                           indices = c(INDEX_A, INDEX_B))
  list(msg = sprintf("figures=%d tablefiles=%d", length(res$figures),
                     length(res$files) - 1L), res = res)
})
if (!r$ok) {
  stop("Task4 ref_assoc_run_all 失败 —— Figure2-6/Table2/S4-S10 为核心必需角色，终止构建：",
       r$error, call. = FALSE)
}
task4_res <- r$value$res

run_stage("table1_from_analysis_frames", 300, {
  # 原始 fustatus（AKI=死亡 / No AKI=存活）；由 ml_reference_build_table1 正确映射，
  # 禁止在此用 relabel_outcome 误套 Non-survivor 标签导致 N_non=0。
  db_frames <- list(MIMIC_IV = mi_assoc$data$imputed,
                    eICU = ei_assoc$data$imputed)
  vars <- list(
    levels = list(Age = 65L),
    sections = list(
      list(
        title = "Demographics",
        continuous = intersect(c("Age", "Weight"), names(db_frames$MIMIC_IV)),
        categorical = intersect("Gender", names(db_frames$MIMIC_IV))
      ),
      list(
        title = "Exposures",
        continuous = intersect(c(INDEX_A, INDEX_B), names(db_frames$MIMIC_IV)),
        categorical = character(0)
      ),
      list(
        title = "Vital signs / severity",
        continuous = intersect(c("HR", "MAP", "Creatinine", "SOFA"),
                               names(db_frames$MIMIC_IV)),
        categorical = character(0)
      )
    )
  )
  tab <- ml_reference_build_table1(db_frames, staging, vars = vars)
  sprintf("rows=%d xlsx=%s Survivor/Non-survivor OK", nrow(tab),
          basename(attr(tab, "xlsx") %||% "NA"))
}) -> r_t1
if (!r_t1$ok) {
  # 回退：Task7 旧双库 Table 1 只读重排（误标签列头改 Survivor/Non-survivor）
  run_stage("table1_legacy_relayout", 180, {
    tab <- ml_reference_table1_from_existing(
      file.path(old_tables, "Table 1-MIMIC IV. Baseline characteristics of AKI.xlsx"),
      file.path(old_tables, "Table 1-eICU. Baseline characteristics of AKI.xlsx"),
      staging)
    sprintf("rows=%d (read-only relayout fallback)", nrow(tab))
  })
}

run_stage("table_S1_cohort_definition", 300, {
  s1 <- ml_reference_build_s1(index_root, staging)
  sprintf("xlsx=%s", basename(s1$xlsx %||% "NA"))
})

## S2：双库单因素 Cox（CLI 补产；旧 by_index S5 是 logistic 口径不可冒充 Cox）
run_stage("table_S2_univariate_cox", 900, {
  ev01 <- function(x, config) {
    v <- tryCatch(pipeline_outcome_as_01(x, cfg = config), error = function(e) NA)
    if (all(is.na(v))) {
      s <- trimws(as.character(x))
      v <- ifelse(s %in% c("AKI", "Non-survivor", "1", "Yes"), 1L,
                  ifelse(s %in% c("No AKI", "Survivor", "0", "No"), 0L, NA_integer_))
    }
    as.integer(v)
  }
  pool <- unique(c(as.character(mi_assoc$results$Model2Factors %||% character(0)),
                   INDEX_A, INDEX_B))
  rows <- list()
  for (dbname in c("MIMIC-IV", "eICU")) {
    d <- if (dbname == "MIMIC-IV") mi_assoc$data$imputed else ei_assoc$data$imputed
    config <- if (dbname == "MIMIC-IV") mi_assoc$config else ei_assoc$config
    d <- data.frame(d)
    d$D <- ev01(d$fustatus, config)
    d$T <- suppressWarnings(as.numeric(d$futime))
    for (v in pool) {
      if (!v %in% names(d)) next
      x <- suppressWarnings(as.numeric(d[[v]]))
      if (all(is.na(x))) {
        x <- factor(trimws(as.character(d[[v]])))
        if (nlevels(x) < 2L) next
      }
      m <- !is.na(d$D) & is.finite(d$T) & d$T > 0 & !is.na(x)
      sub <- d[m, , drop = FALSE]
      sub$xv <- x[m]
      if (nrow(sub) < 50L || sum(sub$D) < 5L ||
          length(unique(sub$xv)) < 2L) next
      fit <- tryCatch(suppressWarnings(survival::coxph(
        survival::Surv(T, D) ~ xv, data = sub)), error = function(e) NULL)
      if (is.null(fit) || anyNA(stats::coef(fit))) next
      ci <- stats::confint(fit)
      hr <- unname(exp(stats::coef(fit)))
      lo <- unname(exp(ci[1, 1])); hi <- unname(exp(ci[1, 2]))
      pv <- unname(summary(fit)$coefficients[, "Pr(>|z|)"])[1]
      rows[[length(rows) + 1L]] <- data.frame(
        Database = dbname, Variable = v, N = nrow(sub), Events = sum(sub$D),
        `HR (95% CI)` = sprintf("%s (%s, %s)", pub_format_est(hr),
                                pub_format_est(lo), pub_format_est(hi)),
        P = pub_format_p_cell(pv), check.names = FALSE, stringsAsFactors = FALSE)
    }
  }
  s2 <- do.call(rbind, rows)
  if (!nrow(s2)) stop("S2 无可估计单因素 Cox 行")
  sci_xlsx_single_header_booktabs(
    file.path(staging, "Tables",
              "Table S2. Univariate Cox regression analyses in both databases.xlsx"),
    title = "Table S2. Univariate Cox regression analyses of candidate variables with 28-day all-cause mortality in both databases.",
    df_body = s2, sheet = "Table S2",
    footnotes = c(
      paste0("Variables: VIF-passed Model2 pool plus ", INDEX_A, " and ", INDEX_B,
             "; unadjusted univariate Cox per database."),
      "Continuous variables entered as-is; Gender entered as factor. HR (95% CI) and P use project",
      "pub_digits (est=3, p=3). Outcome: 28-day all-cause mortality (Survivor / Non-survivor).",
      "Computed read-only from step16_ml_assoc_bundle analysis frames (imputed; train-fitted imputation)."))
  sprintf("rows=%d", nrow(s2))
})

## ---------------------------------------------------------------------------
## B) ML 冻结三层：fit -> save -> eICU/internal predict -> S11；面板 Fig7/8/S2-S5
## ---------------------------------------------------------------------------
methods_try <- if (nzchar(methods_arg)) {
  tolower(trimws(strsplit(methods_arg, ",")[[1]]))
} else ml_frozen_default_methods()
fallback_method <- if ("logistic" %in% methods_try) "logistic" else methods_try[[1]]
strata_keys <- c("overall", names(SOFA_SPEC$strata))
stratum_labels <- c(overall = "Overall",
                    stats::setNames(vapply(SOFA_SPEC$strata,
                                           function(s) s$label, character(1)),
                                    names(SOFA_SPEC$strata)))

layer_filter <- function(df, key) {
  if (key == "overall") return(df)
  s <- suppressWarnings(as.numeric(as.character(df$SOFA)))
  keep <- ml_stratum_member(s, SOFA_SPEC$strata[[key]])
  df[keep, , drop = FALSE]
}

bundles <- list()     # key -> list(bundle=loaded, mode=...)
for (key in strata_keys) {
  attempt <- function(mset, tag_label) {
    run_stage(paste0("ml_fit_", key, "_", tag_label), fit_timeout, {
      b <- ml_fit_stratum_bundle(mi_ml, key, mset, assets_root = assets_root)
      dir <- ml_save_frozen_bundle(b, file.path(assets_root, key))
      fb <- ml_load_frozen_bundle(dir,
                                  expected_stratum = if (key != "overall") key else NULL)
      sprintf("n_train=%d n_internal=%d feats=%d models=%s",
              fb$counts$n_train, fb$counts$n_internal,
              length(fb$features), paste(names(fb$models), collapse = "+"))
    })
  }
  fit_ok <- FALSE
  degrade_note <- ""
  if (length(methods_try) > 1L) {
    r <- attempt(methods_try, "full5")
    if (r$ok) fit_ok <- TRUE else {
      degrade_note <- sprintf("full5 fail after %.0fs: %s", r$seconds, r$error)
      log_stage(paste0("ml_fit_", key, "_degrade"), "DEGRADE", r$seconds,
                degrade_note)
    }
  }
  if (!fit_ok) {
    r <- attempt(fallback_method, "fallback")
    if (r$ok) fit_ok <- TRUE
  }
  if (!fit_ok) {
    log_stage(paste0("ml_fit_", key), "FAIL", NA,
              "fallback 亦失败——依赖角色将 missing（拒绝假装就绪）")
    next
  }
  fb <- ml_load_frozen_bundle(file.path(assets_root, key),
                              expected_stratum = if (key != "overall") key else NULL)
  mode <- if (length(fb$models) >= 5L) "ready_full" else
    paste0("smoke_only(", paste(names(fb$models), collapse = "/"), ")")
  bundles[[key]] <- list(bundle = fb, mode = mode, degrade = degrade_note)
  log_stage(paste0("ml_bundle_", key), "OK", NA,
            sprintf("models=%s mode=%s trained_in=%s",
                    paste(names(fb$models), collapse = ","), mode,
                    fb$source_database))
}

# 预测（MIMIC internal 行 + eICU 同层）与 S11
mi_frame_all <- mi_ml$data$imputed
id_col <- as.character(mi_ml$config$data$id_column %||% "ID")[1L]
internal_frame <- function(fb, key) {
  d <- mi_frame_all[!is.na(match(as.character(mi_frame_all[[id_col]]),
                                 fb$internal_ids)), , drop = FALSE]
  layer_filter(d, key)
}
s11_rows <- list()
ext_pred <- list()   # key -> list(mi=res, ei=res)
for (key in strata_keys) {
  if (is.null(bundles[[key]])) next
  fb <- bundles[[key]]$bundle
  sk <- if (key != "overall") key else NULL
  re <- run_stage(paste0("predict_external_", key), 900, {
    res <- ml_predict_external_bundle(fb, layer_filter(ei_ext$data$imputed, key),
                                      stratum = sk, database = "eICU")
    stopifnot(isTRUE(res$provenance$no_refit))
    list(msg = sprintf("eICU n=%d no_refit=TRUE", nrow(res$predictions)), res = res)
  })
  ri <- run_stage(paste0("predict_internal_", key), 900, {
    res <- ml_predict_external_bundle(fb, internal_frame(fb, key),
                                      stratum = sk, database = "MIMIC-IV")
    list(msg = sprintf("MIMIC-internal n=%d", nrow(res$predictions)), res = res)
  })
  if (re$ok && ri$ok) {
    ext_pred[[key]] <- list(mi = ri$value$res, ei = re$value$res)
    em <- tryCatch(ml_frozen_external_metrics(fb, re$value$res,
                                              dataset = "external"),
                   error = function(e) {
                     log_stage(paste0("metrics_external_", key), "WARN", NA,
                               conditionMessage(e)); NULL
                   })
    s11 <- tryCatch(ml_frozen_bind_performance(fb, em), error = function(e) NULL)
    if (!is.null(s11)) {
      s11 <- as.data.frame(s11)
      s11$database <- ifelse(as.character(s11$dataset) == "external_validation",
                             "eICU", "MIMIC-IV")
      s11$Trained_in <- "MIMIC-IV"
      s11_rows[[key]] <- s11
    }
  }
}
if (length(s11_rows)) {
  run_stage("table_S11_stratified_performance", 120, {
    s11 <- do.call(rbind, s11_rows); rownames(s11) <- NULL
    exp_df <- s11[, intersect(c("stratum", "database", "Trained_in", "dataset",
                                "model", ".metric", ".estimate"), names(s11))]
    names(exp_df) <- c("Stratum", "Database", "Trained_in", "Dataset", "Model",
                       "Metric", "Estimate")
    exp_df$Estimate <- fmt3_vec(suppressWarnings(as.numeric(exp_df$Estimate)))
    if (!all(grepl("^(NA|-?\\d+\\.\\d{3})$", exp_df$Estimate))) {
      bad <- exp_df$Estimate[!grepl("^(NA|-?\\d+\\.\\d{3})$", exp_df$Estimate)]
      stop("S11 Estimate 存在未格式化(3位)值: ",
           paste(unique(head(bad, 5)), collapse = " | "), call. = FALSE)
    }
    modes <- paste(sprintf("%s=%s", names(bundles),
                           vapply(bundles, function(b) b$mode, character(1))),
                   collapse = "; ")
    sci_xlsx_single_header_booktabs(
      file.path(staging, "Tables",
                "Table S11. Stratified five-model machine-learning performance.xlsx"),
      title = "Table S11. Stratified five-model machine-learning performance (train / internal validation / eICU external).",
      df_body = exp_df, sheet = "Table S11",
      footnotes = c(
        "All models trained ONLY on MIMIC-IV development data (frozen assets; Trained_in=MIMIC-IV).",
        "eICU external = frozen MIMIC-IV models applied WITHOUT refit (no_refit provenance asserted).",
        "Per-stratum Boruta fitted on stratum-train only (restrict_to_train leakage gate).",
        "SOFA entered the overall bundle as a regular predictor; SOFA was excluded from every",
        "stratified candidate domain because it is the stratification key (Fig 7/8 same).",
        sprintf("Honest per-stratum build mode: %s. smoke_only = degraded fit (logistic) after a", modes),
        "full five-model attempt timed out or failed; such rows are NOT a five-model result.",
        "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."))
    sprintf("rows=%d", nrow(exp_df))
  })
}

## S3：继承审计（指向本次新冻结资产目录）
run_stage("table_S3_inherited_audit", 120, {
  s3 <- ml_reference_build_s3(file.path(staging, "_assets/model_assets"), staging)
  sprintf("audit_rows=%d xlsx=%s", nrow(s3$audit), basename(s3$xlsx %||% "NA"))
})

## Fig7 / Fig S2：Boruta 面板（仅 MIMIC-IV train；候选域与 Task5 同口径）
cand_for_stratum <- function(ctx_models, key) {
  spec <- if (key == "overall") NULL else SOFA_SPEC$strata[[key]]
  .ml_frozen_candidate_features(ctx_models, spec)
}
boruta_cache <- list()
for (key in strata_keys) {
  r <- run_stage(paste0("boruta_panel_", key), 900, {
    tr <- layer_filter(mi_ml$data$train, key)
    cand <- intersect(cand_for_stratum(mi_ml, key), names(tr))
    cand <- setdiff(cand, c("futime", "fustatus", "ID", "Group",
                            if (key != "overall") "SOFA" else character(0)))
    d <- tr[, c("Group", cand), drop = FALSE]
    keep <- stats::complete.cases(d)
    d <- d[keep, , drop = FALSE]
    for (cn in names(d)) if (is.character(d[[cn]])) d[[cn]] <- as.factor(d[[cn]])
    b <- ml_ref_boruta_run(d, max_runs = 50L, seed = 42L, database = "MIMIC_IV")
    list(msg = sprintf("features=%d rows=%d", length(cand), nrow(d)), obj = b)
  })
  if (r$ok) boruta_cache[[key]] <- r$value$obj
}
if (sum(names(boruta_cache) != "overall") >= 2L) {
  run_stage("figure7_boruta_strata", 300, {
    bys <- boruta_cache[names(boruta_cache) != "overall"]
    names(bys) <- vapply(names(bys), function(k) SOFA_SPEC$strata[[k]]$label, character(1))
    p <- ml_ref_fig7_boruta(
      bys,
      out_pdf = file.path(staging, "Figures",
                          "Figure 7. Stratified Boruta feature selection in MIMIC-IV.pdf"))
    sprintf("panels=%d", nrow(p$panels))
  })
}
if (!is.null(boruta_cache$overall)) {
  run_stage("figureS2_boruta_overall", 300, {
    p <- ml_ref_s2_boruta(boruta_cache$overall,
                          out_pdf = file.path(staging, "Figures",
                          "Figure S2. Overall Boruta feature selection in MIMIC-IV.pdf"))
    sprintf("panels=%d", nrow(p$panels))
  })
}

## Fig8：库 x SOFA 层（internal + external），冻结 best tag ROC+SHAP
fig8_cells <- list()
shap_by_stratum <- list()
fig8_degraded <- FALSE

# best/降级 tag 的 Fig8 单元格构建（SHAP 内核走 Task6 冻结路径；树模型 SHAP
# 慢时上层调用会降级到 logistic 再试一次）。
fig8_build_cells <- function(fb, mi_res, ei_res, tag, lab, sk) {
  sh_i <- ml_shap_from_frozen_bundle(fb, internal_frame(fb, sk), tag = tag,
                                     sample_n = 200L, stratum = sk)
  sh_e <- ml_shap_from_frozen_bundle(fb, layer_filter(ei_ext$data$imputed, sk),
                                     tag = tag, sample_n = 200L, stratum = sk)
  stopifnot(identical(sh_i$model_checksum, sh_e$model_checksum))
  # 规格：每格 ROC 叠加该层「五模型」（fb$models 全部 tag）；SHAP 仍用最优 tag。
  fig8_roc_multi <- function(res, database) {
    lapply(names(fb$models), function(m) list(
      model = m,
      roc = ml_ref_roc_rows(res$predictions[[m]], res$predictions$truth,
                            dataset = if (database == "eICU")
                              "external_validation" else "internal_validation",
                            model = m, stratum = lab, database = database)))
  }
  list(
    cells = list(
      list(database = "MIMIC-IV", stratum = lab, tag = tag,
           roc = fig8_roc_multi(mi_res, "MIMIC-IV"),
           shp = sh_i$shp),
      list(database = "eICU", stratum = lab, tag = tag,
           roc = fig8_roc_multi(ei_res, "eICU"),
           shp = sh_e$shp)),
    shap = list(sh_i = sh_i, sh_e = sh_e, tag = tag))
}

for (key in names(SOFA_SPEC$strata)) {
  if (is.null(bundles[[key]]) || is.null(ext_pred[[key]])) next
  fb <- bundles[[key]]$bundle
  lab <- stratum_labels[[key]]
  sk <- key
  mi_res <- ext_pred[[key]]$mi
  ei_res <- ext_pred[[key]]$ei
  tag_best <- ml_frozen_best_tag(fb) %||% names(fb$models)[[1]]
  r <- run_stage(paste0("shap_fig8_", key), panel_timeout + 900, {
    out <- fig8_build_cells(fb, mi_res, ei_res, tag_best, lab, sk)
    list(msg = sprintf("tag=%s identity=%s", tag_best,
                       substr(out$shap$sh_i$model_checksum, 1, 12)), out = out)
  })
  if (!r$ok) {
    log_stage(paste0("shap_fig8_", key, "_degrade"), "DEGRADE", r$seconds,
              paste("best-tag SHAP 超时/失败 -> logistic 面板降级:", r$error))
    fig8_degraded <<- TRUE
    r <- run_stage(paste0("shap_fig8_", key, "_logistic"), 900, {
      out <- fig8_build_cells(fb, mi_res, ei_res, "logistic", lab, sk)
      list(msg = "tag=logistic (degraded panel; honest smoke)", out = out)
    })
  }
  if (r$ok) {
    fig8_cells <- c(fig8_cells, r$value$out$cells)
    shap_by_stratum[[key]] <- r$value$out$shap
  }
}
if (length(fig8_cells)) {
  run_stage("figure8_grid", 300, {
    p <- ml_ref_fig8_grid(fig8_cells,
                          out_pdf = file.path(staging, "Figures",
                          "Figure 8. Stratified five-model ROC and SHAP.pdf"))
    # 长表：每格 x 每模型一行（五模型 AUC/95%CI；best=该层内验最优 tag）
    write.csv(p$auc, file.path(staging, "_assets/Figure8_panel_auc.csv"),
              row.names = FALSE)
    sprintf("panels=%d models_per_cell=%s", nrow(p$panels),
            paste(p$panels$n_models, collapse = "/"))
  })
}

## Fig S3 + S4：overall 五模型 ROC / 最优冻结 SHAP
s4_degraded <- FALSE
if (!is.null(bundles$overall) && !is.null(ext_pred$overall)) {
  run_stage("figureS3_roc", 300, {
    fb <- bundles$overall$bundle
    cells <- list()
    for (m in names(fb$models)) {
      cells[[length(cells) + 1L]] <- list(
        model = m, dataset = "internal_validation",
        roc = ml_ref_roc_rows(ext_pred$overall$mi$predictions[[m]],
                              ext_pred$overall$mi$predictions$truth,
                              dataset = "internal_validation", model = m))
      cells[[length(cells) + 1L]] <- list(
        model = m, dataset = "external_validation",
        roc = ml_ref_roc_rows(ext_pred$overall$ei$predictions[[m]],
                              ext_pred$overall$ei$predictions$truth,
                              dataset = "external_validation", model = m))
    }
    p <- ml_ref_s3_roc(cells, out_pdf = file.path(staging, "Figures",
        "Figure S3. Overall five-model ROC internal and external.pdf"))
    write.csv(p$auc, file.path(staging, "_assets/FigureS3_auc.csv"),
              row.names = FALSE)
    sprintf("models=%d", length(unique(as.character(p$auc$model))))
  })
  s4_build <- function(fb, tag) {
    sh_i <- ml_shap_from_frozen_bundle(fb, internal_frame(fb, "overall"),
                                       tag = tag, sample_n = 200L)
    sh_e <- ml_shap_from_frozen_bundle(fb, ei_ext$data$imputed, tag = tag,
                                       sample_n = 200L)
    stopifnot(identical(sh_i$model_checksum, sh_e$model_checksum))
    picks_i <- ml_pick_paired_cases(data.frame(
      database = "MIMIC-IV", stratum = "Overall",
      row_id = seq_along(sh_i$truth),
      truth = sh_i$truth, prob = sh_i$pred_prob,
      stringsAsFactors = FALSE
    ))
    ns <- picks_i[picks_i$outcome_class == "Non-survivor", , drop = FALSE][1, ]
    sv <- picks_i[picks_i$outcome_class == "Survivor", , drop = FALSE][1, ]
    p <- ml_ref_s4_paper(
      sh_i$shp, ns, sv,
      out_pdf = file.path(staging, "Figures",
        "Figure S4. Overall best frozen model SHAP MIMIC-IV eICU.pdf"),
      database = "MIMIC-IV", tag = tag)
    sprintf("paper_layout tag=%s non_row=%s surv_row=%s eICU_checksum_ok",
            tag, ns$row_id, sv$row_id)
  }
  fb <- bundles$overall$bundle
  tag_best <- ml_frozen_best_tag(fb) %||% names(fb$models)[[1]]
  r4 <- run_stage(paste0("figureS4_shap_", tag_best), panel_timeout + 900,
                  s4_build(fb, tag_best))
  if (!r4$ok) {
    log_stage("figureS4_shap_degrade", "DEGRADE", r4$seconds,
              paste("best-tag SHAP 超时/失败 -> logistic 降级:", r4$error))
    s4_degraded <<- TRUE
    run_stage("figureS4_shap_logistic", 900, s4_build(fb, "logistic"))
  }
}

## Fig S5：个体 waterfall（SOFA 三层 x 双库 x Survivor/Non-survivor）
if (length(shap_by_stratum)) {
  run_stage("figureS5_waterfalls", 300, {
    .s5_frame <- function(sh, database, lab) {
      n_shp <- nrow(shapviz::get_shap_values(sh$shp))
      n_meta <- length(sh$truth)
      if (!identical(as.integer(n_shp), as.integer(n_meta))) {
        stop("S5 frame misaligned: ", database, " / ", lab,
             " shap_rows=", n_shp, " meta_rows=", n_meta,
             "（ml_shap_from_frozen_bundle 应对齐）", call. = FALSE)
      }
      data.frame(
        database = database, stratum = lab,
        row_id = seq_len(n_shp), truth = sh$truth,
        prob = sh$pred_prob, stringsAsFactors = FALSE)
    }
    frames <- list()
    key_of_lab <- setNames(names(shap_by_stratum),
                           unname(stratum_labels[names(shap_by_stratum)]))
    for (key in names(shap_by_stratum)) {
      v <- shap_by_stratum[[key]]
      lab <- stratum_labels[[key]]
      frames[[length(frames) + 1L]] <- .s5_frame(v$sh_i, "MIMIC-IV", lab)
      frames[[length(frames) + 1L]] <- .s5_frame(v$sh_e, "eICU", lab)
    }
    allf <- do.call(rbind, frames)
    picks <- ml_pick_paired_cases(allf)
    # 原文 Fig.S5 是单队列 3 层 ×（非存活, 存活）共 6 条 force。
    # 主库 MIMIC-IV 对齐 A–F；eICU 个体解释留在主文 Figure 8。
    st_order <- unname(stratum_labels[names(SOFA_SPEC$strata)])
    picks <- picks[picks$database == "MIMIC-IV", , drop = FALSE]
    picks$stratum <- factor(picks$stratum, levels = st_order)
    picks$outcome_class <- factor(picks$outcome_class,
                                  levels = c("Non-survivor", "Survivor"))
    picks <- picks[order(picks$stratum, picks$outcome_class), , drop = FALSE]
    items <- lapply(seq_len(nrow(picks)), function(i) {
      pk <- picks[i, ]
      v <- shap_by_stratum[[ key_of_lab[pk$stratum] ]]
      if (is.null(v)) stop("S5: unknown stratum label '", pk$stratum, "'",
                           call. = FALSE)
      sh_obj <- if (pk$database == "MIMIC-IV") v$sh_i else v$sh_e
      list(database = pk$database, stratum = pk$stratum,
           outcome_class = pk$outcome_class, row_id = pk$row_id,
           prob = pk$prob, source_row = sh_obj$row_index[pk$row_id],
           shp = sh_obj$shp)
    })
    p <- ml_ref_s5_forces(items, out_pdf = file.path(
      staging, "Figures",
      "Figure S5. Individual SHAP waterfalls survivor non-survivor.pdf"))
    prov <- do.call(rbind, lapply(items, function(x) data.frame(
      database = x$database, stratum = x$stratum,
      outcome_class = x$outcome_class, explained_row = x$row_id,
      source_row_in_frame = x$source_row, prob = x$prob)))
    write.csv(prov, file.path(staging, "_assets/FigureS5_case_provenance.csv"),
              row.names = FALSE)
    sprintf("panels=%d", nrow(p$panels))
  })
}

## Fig S1：对齐原文 Fig.S1（plot.cox.zph：散点+样条±2SE+粉色 y=0）
## 双库一张图 A=MIMIC-IV / B=eICU；Overall 联合 Group；分层 PH 见 Table S6–S8
run_stage("figureS1_ph_trend", 600, {
  locks <- task4_res$locks
  covs0 <- intersect(c("Age", "Gender"), names(mi_assoc$data$imputed))
  fit_zph <- function(d, dbname, config) {
    d <- data.frame(d)
    d$Group <- as.numeric(reference_apply_joint_tertiles(d, locks$joint)$group)
    d <- .ref_assoc_event01(d, "fustatus", config)
    d$T <- suppressWarnings(as.numeric(d$futime))
    d$D <- as.integer(d$fustatus)
    covs <- intersect(covs0, names(d))
    need <- c("T", "D", "Group", covs)
    dd <- d[stats::complete.cases(d[, need, drop = FALSE]), , drop = FALSE]
    dd <- dd[is.finite(dd$T) & dd$T > 0 & dd$T <= 28, , drop = FALSE]
    if (nrow(dd) < 50L || sum(dd$D == 1L) < 10L) {
      stop(dbname, " Overall 不足以估计 cox.zph", call. = FALSE)
    }
    form <- if (length(covs)) {
      stats::as.formula(sprintf("survival::Surv(T, D) ~ Group + %s",
                                paste(.reference_bt(covs), collapse = " + ")))
    } else {
      stats::as.formula("survival::Surv(T, D) ~ Group")
    }
    fit <- survival::coxph(form, data = dd, x = TRUE, y = TRUE, model = TRUE)
    zph <- survival::cox.zph(fit)  # 默认 km，对齐原文非等距 Time 轴
    p_g <- as.numeric(as.data.frame(zph$table)[
      match("Group", rownames(zph$table)), "p"])
    list(zph = zph, n = nrow(dd), events = sum(dd$D == 1L), p = p_g,
         database = dbname)
  }
  mi_z <- fit_zph(mi_assoc$data$imputed, "MIMIC-IV", mi_assoc$config)
  ei_z <- fit_zph(ei_assoc$data$imputed, "eICU", ei_assoc$config)
  .plot_one <- function(z, letter, db, p) {
    idx <- match("Group", colnames(z$y)); if (is.na(idx)) idx <- 1L
    survival:::plot.cox.zph(
      z, resid = TRUE, se = TRUE, df = 4, nsmo = 40, var = idx,
      xlab = "Time", ylab = "Beta(t) for Group",
      main = sprintf("%s  %s\nCOX Regression PH Test Trend Plot_Group",
                     letter, db),
      col = 1, lwd = 1, lty = 1:2, pch = 1, cex = 0.55
    )
    graphics::abline(h = 0, col = "pink", lty = 2, lwd = 1.5)
    graphics::mtext(
      sprintf("Schoenfeld P (Group) = %s",
              format.pval(p, digits = 3, eps = 1e-3)),
      side = 1, line = 3.6, cex = 0.75, adj = 0
    )
  }
  out_pdf <- file.path(staging, "Figures",
    "Figure S1. Time-varying PH coefficient trends by SOFA strata.pdf")
  grDevices::pdf(out_pdf, width = 11.2, height = 5.6, onefile = TRUE)
  graphics::par(mfrow = c(1, 2), mar = c(5.2, 4.2, 3.8, 1.2),
                oma = c(2.8, 0.2, 0.2, 0.2))
  .plot_one(mi_z$zph, "A", mi_z$database, mi_z$p)
  .plot_one(ei_z$zph, "B", ei_z$database, ei_z$p)
  graphics::mtext(
    paste0(
      "Fig. S1  The trends of the proportional-hazards assumption test based on ",
      "the COX regression model. Group = ", INDEX_A, "+", INDEX_B,
      " joint tertile score; Age+Gender adjusted. Pink dashed: Beta(t)=0."
    ),
    side = 1, outer = TRUE, line = 1.4, cex = 0.78, adj = 0
  )
  grDevices::dev.off()
  # 审计：残差点 + 摘要（旧 beta_trends 平滑表不再作为主产物）
  resid_rows <- function(z) {
    idx <- match("Group", colnames(z$zph$y)); if (is.na(idx)) idx <- 1L
    data.frame(database = z$database, time_transform = z$zph$x,
               time = z$zph$time, schoenfeld = z$zph$y[, idx],
               p_group = z$p, n = z$n, events = z$events,
               stringsAsFactors = FALSE)
  }
  write.csv(rbind(resid_rows(mi_z), resid_rows(ei_z)),
            file.path(staging, "_assets/FigureS1_schoenfeld_points.csv"),
            row.names = FALSE)
  write.csv(
    data.frame(database = c(mi_z$database, ei_z$database),
               n = c(mi_z$n, ei_z$n), events = c(mi_z$events, ei_z$events),
               ph_p_group = c(mi_z$p, ei_z$p),
               transform = "km (cox.zph default)",
               stringsAsFactors = FALSE),
    file.path(staging, "_assets/FigureS1_ph_summary.csv"), row.names = FALSE
  )
  sprintf("MIMIC_P=%s eICU_P=%s",
          format.pval(mi_z$p, digits = 3, eps = 1e-3),
          format.pval(ei_z$p, digits = 3, eps = 1e-3))
})

## Fig S6-S8：旧三集图（校准/性能/DCA）只读拷贝重编号
run_stage("figureS6_S8_legacy_copy", 120, {
  copy_map <- c(
    "Figure 4. ML calibration training internal and external.pdf" =
      "Figure S6. Calibration across train internal external sets.pdf",
    "Figure 5. ML metrics training internal and external.pdf" =
      "Figure S7. Performance metrics across train internal external sets.pdf",
    "Figure 6. ML DCA training internal and external.pdf" =
      "Figure S8. Decision curve analysis across train internal external sets.pdf")
  n <- 0L
  missing <- character(0)
  for (src in names(copy_map)) {
    sp <- file.path(old_fig_pdf, src)
    if (!file.exists(sp)) { missing <- c(missing, src); next }
    file.copy(sp, file.path(staging, "Figures", copy_map[[src]]), overwrite = TRUE)
    n <- n + 1L
  }
  if (length(missing)) {
    stop("缺旧三集图（不得编造，角色将 missing）: ",
         paste(missing, collapse = "; "), call. = FALSE)
  }
  sprintf("copied=%d (read-only relayout of legacy overall three-set figures)", n)
})

## ---------------------------------------------------------------------------
## C) 本课题额外表 S12-S16（旧 by_index Tables 只读重排，不改旧文件）
## ---------------------------------------------------------------------------
read_legacy_table <- function(fname) {
  p <- file.path(old_tables, fname)
  if (!file.exists(p)) stop("缺旧表（不得编造）: ", fname, call. = FALSE)
  d <- as.data.frame(openxlsx::read.xlsx(p, colNames = FALSE, check.names = FALSE),
                     stringsAsFactors = FALSE)
  hdr <- trimws(gsub("_", "", as.character(unlist(d[2, ]))))
  body <- d[-c(1, 2), , drop = FALSE]
  stop_i <- which(vapply(seq_len(nrow(body)), function(i) {
    c1 <- trimws(as.character(body[i, 1]))
    length(c1) == 1 && !is.na(c1) &&
      (grepl("^NE\\s*=", c1) || grepl("are presented|test\\.$", c1, ignore.case = TRUE))
  }, logical(1)))
  if (length(stop_i)) body <- body[seq_len(min(stop_i) - 1L), , drop = FALSE]
  body <- body[, seq_len(min(length(hdr), ncol(body))), drop = FALSE]
  names(body) <- hdr[seq_len(ncol(body))]
  keep <- vapply(body, function(col) any(!is.na(col) & nzchar(trimws(as.character(col)))),
                 logical(1))
  body[, keep, drop = FALSE]
}
run_stage("table_S12_legacy_relayout", 180, {
  sets <- list(
    "Train (MIMIC-IV development)" =
      "Table 3-MIMIC IV. ML performance wide training.xlsx",
    "Internal validation (MIMIC-IV)" =
      "Table 4-MIMIC IV. ML performance wide validation.xlsx",
    "External validation (eICU, frozen MIMIC-IV models)" =
      "Table 5-eICU. ML performance wide external validation.xlsx")
  rows <- list()
  for (ds in names(sets)) {
    tb <- read_legacy_table(sets[[ds]])
    mcol <- names(tb)[1]
    ev_val <- ""
    ev_i <- which(trimws(as.character(tb[[mcol]])) == "Events (Case/Total)")
    if (length(ev_i)) {
      ev_val <- as.character(tb[[2]][ev_i[1]])
      tb <- tb[-ev_i, , drop = FALSE]
    }
    for (i in seq_len(nrow(tb))) {
      m <- trimws(as.character(tb[[mcol]][i]))
      if (!nzchar(m) || grepl("^NE\\s*=", m)) next
      row <- stats::setNames(
        list(ds, m, if (i == 1) ev_val else ""),
        c("Dataset", "Model", "Events (Case/Total)"))
      for (cn in setdiff(names(tb), mcol)) {
        row[[cn]] <- as.character(tb[[cn]][i])
      }
      rows[[length(rows) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE)
    }
  }
  s12 <- do.call(rbind, rows)
  colnames(s12)[colnames(s12) == "accuracy"] <- "Accuracy"
  sci_xlsx_single_header_booktabs(
    file.path(staging, "Tables",
              "Table S12. Overall machine-learning performance train internal external.xlsx"),
    title = "Table S12. Overall machine-learning performance across train, internal-validation and external-validation sets.",
    df_body = s12, sheet = "Table S12",
    footnotes = c(
      "Read-only re-layout of the legacy overall-stratum checkpoint tables (Tables 3/4/5); values",
      "unchanged. 'Case' = death (Non-survivor). External validation = eICU scored with frozen",
      "MIMIC-IV-trained models (no refit). Outcome: 28-day all-cause mortality.",
      "Stratified (SOFA) five-model performance is Table S11 (newly fitted frozen bundles)."))
  sprintf("rows=%d", nrow(s12))
})
legacy_relayout <- function(stage, fname, number, title, sheet, footnotes,
                            p_cols = NULL) {
  run_stage(stage, 180, {
    body <- read_legacy_table(fname)
    if (!is.null(p_cols)) {
      for (cn in intersect(p_cols, names(body))) {
        v <- suppressWarnings(as.numeric(body[[cn]]))
        body[[cn]] <- ifelse(is.na(v), as.character(body[[cn]]), pub_format_p(v))
      }
    }
    dest <- file.path(staging, "Tables",
                      paste0("Table ", number, ". ", title, ".xlsx"))
    sci_xlsx_single_header_booktabs(
      dest, title = paste0("Table ", number, ". ", title, "."),
      df_body = body, sheet = sheet, footnotes = footnotes)
    sprintf("rows=%d (read-only relayout of %s)", nrow(body), fname)
  })
}
legacy_relayout(
  "table_S13_hyperparameters",
  "Table S7-MIMIC IV. Hyperparameters for machine learning models.xlsx", "S13",
  "Hyperparameters for the machine-learning models", "Table S13",
  c("Read-only re-layout of the legacy overall-stratum hyperparameter table (Hpbest export).",
    "Stratified frozen assets use the same engine grids; per-stratum manifests under _assets record",
    "package versions. All models trained on MIMIC-IV train only (eICU never refits)."))
legacy_relayout(
  "table_S14_logloss",
  "Table S8-MIMIC IV. Log-Loss.xlsx", "S14",
  "Log-Loss of the machine-learning models", "Table S14",
  c("Read-only re-layout of the legacy overall-stratum Log-Loss table.",
    "External column = eICU evaluated with frozen MIMIC-IV models (no refit).",
    "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."))
legacy_relayout(
  "table_S15_delong",
  "Table S9-MIMIC IV. DeLong tests (training set).xlsx", "S15",
  "DeLong tests for the machine-learning models", "Table S15",
  c("Read-only re-layout of the legacy overall-stratum DeLong table (training set).",
    "P formatted to 3 decimals per project pub_digits; effect strings unchanged.",
    "Figure-4 discrimination DeLong (index vs clinical scores) is Table S5 - a different",
    "comparison; not duplicated here."),
  p_cols = "P value")
legacy_relayout(
  "table_S16_nri_idi",
  "Table S10-MIMIC IV. NRI and IDI (training set).xlsx", "S16",
  "NRI and IDI for the machine-learning models", "Table S16",
  c("Read-only re-layout of the legacy overall-stratum NRI/IDI table (training set).",
    "P columns formatted to 3 decimals per project pub_digits; effect strings unchanged.",
    "Bootstrap seeds fixed in the legacy checkpoint (no seed+day fork)."),
  p_cols = c("P value NRI", "P value IDI"))

## ---------------------------------------------------------------------------
## D) 四格式导出 + image_information 详注（单一公共入口）
## ---------------------------------------------------------------------------
fig_meta <- list(exposure = paste0(INDEX_LABEL, " 联合暴露"),
                 outcome = "28 天全因死亡",
                 grouping = "SOFA<=10 / SOFA>=11 数值分层（含 Overall）",
                 n_by_db = c(`MIMIC-IV` = 18394L, eICU = 10558L),
                 n_total = 28952L, databases = c("MIMIC-IV", "eICU"),
                 combined = TRUE)
r <- run_stage("pub_figure_ensure_formats", 2400, {
  st <- pub_figure_ensure_formats(file.path(staging, "Figures"), meta = fig_meta,
                                  config = cfg, purge = TRUE)
  stopifnot(isTRUE(st$ok))
  sprintf("stems=%d", length(st$status$stems))
})

run_stage("image_information_rewrite", 240, {
  fig_kind <- rbind(profile[profile$kind == "figure_main", ],
                    profile[profile$kind == "figure_supp", ])
  fig_kind$label <- ifelse(grepl("supp", fig_kind$kind),
                           paste0("Figure S", fig_kind$number),
                           paste0("Figure ", fig_kind$number))
  dir_md <- file.path(staging, "Figures", "image_information")
  pdfs <- list.files(file.path(staging, "Figures", "pdf"),
                     pattern = "^Figure.*\\.pdf$", ignore.case = TRUE)
  n <- 0L
  for (fp in pdfs) {
    stem <- sub("\\.pdf$", "", fp, ignore.case = TRUE)
    hit <- which(vapply(fig_kind$label, function(l)
      startsWith(stem, paste0(l, ".")), logical(1)))
    extra <- character(0)
    if (length(hit)) {
      i <- hit[1]
      extra <- c(
        sprintf("图面说明：%s。面板结构：%s。", fig_kind$role[i],
                fig_kind$db_mode[i]),
        sprintf("原文对应：%s。", fig_kind$reference_source[i]),
        sprintf("本课题适配：%s。", fig_kind$adaptation[i]),
        sprintf("数据来源（只读）：%s。",
                sources_for_role(fig_kind$kind[i], fig_kind$number[i])))
    }
    read_csv <- function(p) {
      if (file.exists(p)) tryCatch(utils::read.csv(p, check.names = FALSE),
                                   error = function(e) NULL) else NULL
    }
    if (startsWith(stem, "Figure 8.")) {
      aucd <- read_csv(file.path(staging, "_assets/Figure8_panel_auc.csv"))
      if (!is.null(aucd)) {
        tag_col <- if ("model" %in% names(aucd)) aucd$model else aucd$tag
        extra <- c(extra,
          "SOFA 入模口径：SOFA 为分层键——各 SOFA 层冻结资产的候选域与 Boruta 均排除 SOFA；overall 资产保留 SOFA 为普通预测因子（Fig 7 / Table S11 同口径）。",
          "每格 ROC 叠加该层全部五模型（logistic/dt/rf/xgboost/lightgbm，图例标各模型 AUC）；SHAP beeswarm/importance 两子格用该层内验最优冻结模型（tag 见图内标签）；MIMIC-IV internal 与 eICU external 解释同一冻结模型（model checksum 一致，provenance no_refit）。",
          "SHAP 解释行数：确定性降采样至最多 200 行/格（高置信事件/非事件各半 + seed=42 补足）；ROC 分母=该层全量冻结预测。",
          "图上标注（每格每模型 AUC；冻结模型 pROC，与 Table S11 同源口径；* = SHAP 所用最优模型）：",
          sprintf("- %s | %s | %s%s: AUC=%s (95%%CI %s-%s)", aucd$database,
                  aucd$stratum, tag_col,
                  if ("best" %in% names(aucd))
                    ifelse(as.logical(aucd$best), " *", "") else "",
                  fmt3_vec(aucd$auc), fmt3_vec(aucd$ci_low),
                  fmt3_vec(aucd$ci_high)))
      }
    }
    if (startsWith(stem, "Figure 7.") || startsWith(stem, "Figure S2.")) {
      extra <- c(extra,
        "SOFA 入模口径：Figure 7 两层面板的候选域均已剔除分层键 SOFA（Task5 C1 审查口径）；Figure S2 overall 面板保留 SOFA 为普通预测因子（overall 非分层）。")
    }
    if (startsWith(stem, "Figure S3.")) {
      aucd <- read_csv(file.path(staging, "_assets/FigureS3_auc.csv"))
      if (!is.null(aucd)) extra <- c(extra,
        "SOFA 入模口径：overall 冻结资产保留 SOFA 为普通预测因子（分层资产排除 SOFA，见 Fig7/8 注）。",
        "图上标注（overall AUC；冻结预测）：",
        sprintf("- %s | %s: AUC=%s (95%%CI %s-%s)", aucd$model, aucd$dataset,
                fmt3_vec(aucd$auc), fmt3_vec(aucd$ci_low),
                fmt3_vec(aucd$ci_high)))
    }
    if (startsWith(stem, "Figure S4.")) {
      extra <- c(extra,
        "双库解释同一 MIMIC-IV 冻结模型（model checksum 一致断言通过）；overall 资产含 SOFA 为普通预测因子（分层资产排除 SOFA，见 Fig7/8 注）。",
        "SHAP 解释行数：确定性降采样至最多 200 行/格（高置信事件/非事件各半 + seed=42 补足）。")
    }
    if (startsWith(stem, "Figure S5.")) {
      pv <- read_csv(file.path(staging, "_assets/FigureS5_case_provenance.csv"))
      if (!is.null(pv)) extra <- c(extra,
        "图上标注（个体预测概率，冻结最优模型；样本仅来自本库本层）：",
        sprintf("- %s | %s | %s: pred=%s", pv$database, pv$stratum,
                pv$outcome_class, fmt3_vec(pv$prob)))
    }
    if (startsWith(stem, "Figure S1.")) {
      bt <- read_csv(file.path(staging, "_assets/FigureS1_beta_trends.csv"))
      if (!is.null(bt)) {
        lab <- unique(bt[, c("database", "layer", "exposure_p")])
        extra <- c(extra, "图上标注（各面板 Schoenfeld PH P，Joint score）：",
                   sprintf("- %s | %s: PH P=%s", lab$database, lab$layer,
                           pub_format_p_cell(lab$exposure_p)))
      }
    }
    if (startsWith(stem, "Figure 1.")) {
      fr <- ml_reference_read_flowcharts(mimic_csv, eicu_csv)
      ex <- fr$exclusions
      extra <- c(extra, "逐步人数与排除（相邻步差额，图上「本步排除 X 人」框）：",
                 if (nrow(ex)) sprintf("- %s | %s: 本步排除 %d 人", ex$database,
                                       ex$step, ex$excluded) else
                   "- 两库各步之间无排除（差额=0）")
      for (dbu in c("MIMIC-IV", "eICU")) {
        rr <- fr$rows[fr$rows$database == dbu, ]
        extra <- c(extra, sprintf("- %s 步序列 n：%s", dbu,
                                  paste(format(rr$n, big.mark = ","),
                                        collapse = " -> ")))
      }
    }
    if (startsWith(stem, "Figure S7.")) extra <- c(extra,
      "图上标注口径：AUC 仅来自 roc_auc_score/预测概率；Acc/F1/Sens/Spec 等分类指标与 AUC 分开标注，互不混写。",
      "本图为旧 checkpoint overall 三集性能图只读重编号；数值同 Table S12。")
    if (startsWith(stem, "Figure S6.")) extra <- c(extra,
      "本图为旧 checkpoint overall 三集校准图只读重编号（原文无对应面板，本课题额外补充图）。")
    if (startsWith(stem, "Figure S8.")) extra <- c(extra,
      "本图为旧 checkpoint overall 三集 DCA 图只读重编号；三集阈值范围同标尺。")
    m <- fig_meta
    if (length(extra)) m$figure_body_lines <- extra
    png_ok <- file.exists(file.path(staging, "Figures", "png",
                                    paste0(stem, ".png")))
    tiff_ok <- file.exists(file.path(staging, "Figures", "tiff",
                                     paste0(stem, ".tiff")))
    pub_figure_write_image_md(file.path(dir_md, paste0(stem, ".md")), stem,
                              meta = m, tech = list(),
                              raster_ok = png_ok && tiff_ok)
    n <- n + 1L
  }
  sprintf("md=%d", n)
})

## ---------------------------------------------------------------------------
## E) MANIFEST + README
## ---------------------------------------------------------------------------
target_for_role <- function(kind, num) {
  is_fig <- grepl("figure", kind)
  lab <- if (kind == "figure_main") paste0("Figure ", num) else
    if (kind == "figure_supp") paste0("Figure S", num) else
      if (kind == "table_main") paste0("Table ", num) else paste0("Table S", num)
  ext <- if (is_fig) "\\.pdf$" else "\\.xlsx$"
  if (is_fig) {
    # 四格式导出后平铺 PDF 已收入 pdf/；两处都找
    dirp <- file.path(staging, "Figures", c("", "pdf"))
    for (dd in dirp) {
      files <- grep(ext, list.files(dd, pattern = paste0("^", lab, "\\."),
                                    ignore.case = TRUE),
                    value = TRUE, ignore.case = TRUE)
      if (length(files)) return(file.path("Figures", "pdf", files[[1]]))
    }
    return(NA_character_)
  }
  dirp <- file.path(staging, "Tables")
  files <- list.files(dirp, pattern = paste0("^", lab, "\\."),
                      ignore.case = TRUE)
  if (!length(files)) files <- list.files(dirp, pattern = paste0("^", lab, " "),
                                          ignore.case = TRUE)
  files <- grep(ext, files, ignore.case = TRUE, value = TRUE)
  if (!length(files)) return(NA_character_)
  file.path("Tables", files[[1]])
}

any_smoke <- function() {
  length(bundles) > 0 &&
    any(vapply(bundles, function(b) grepl("smoke_only", b$mode), logical(1)))
}

status_for_role <- function(kind, num, target) {
  if (is.na(target)) return("missing")
  if (kind == "figure_main" && num %in% c("7")) {
    return(if (length(boruta_cache) >= 2L && !any_smoke()) "ready_full" else
             "smoke_only")
  }
  if (kind == "figure_main" && num == "8") {
    return(if (length(shap_by_stratum) >= 2L && !any_smoke() && !fig8_degraded)
             "ready_full" else "smoke_only")
  }
  if (kind == "figure_supp" && num %in% as.character(2:5)) {
    if (is.null(bundles$overall)) return("missing")
    if (any_smoke()) return("smoke_only")
    if (num == "4" && s4_degraded) return("smoke_only")
    if (num == "5" && fig8_degraded) return("smoke_only")
    return("ready_full")
  }
  if (kind == "figure_supp" && num %in% as.character(6:8)) return("legacy_relayout")
  if (kind == "table_supp" && num %in% as.character(12:16)) return("legacy_relayout")
  if (kind == "table_supp" && num == "11") {
    if (!length(bundles)) return("missing")
    return(if (any_smoke()) "smoke_only" else "ready_full")
  }
  "ready"
}

manifest_df <- NULL
run_stage("manifest_readme", 300, {
  prof <- profile
  n <- nrow(prof)
  target <- source_files <- status <- verification <- character(n)
  for (i in seq_len(n)) {
    kind <- prof$kind[i]; num <- prof$number[i]
    tf <- target_for_role(kind, num)
    target[i] <- tf %||% NA_character_
    source_files[i] <- sources_for_role(kind, num)
    status[i] <- status_for_role(kind, num, tf)
    if (is.na(tf)) {
      verification[i] <- "MISSING"
    } else if (grepl("figure", kind)) {
      stem <- sub("\\.pdf$", "", basename(tf))
      p_png <- file.exists(file.path(staging, "Figures", "png", paste0(stem, ".png")))
      p_tif <- file.exists(file.path(staging, "Figures", "tiff", paste0(stem, ".tiff")))
      p_md <- file.exists(file.path(staging, "Figures", "image_information",
                                    paste0(stem, ".md")))
      verification[i] <- sprintf("four_formats=pdf:TRUE,png:%s,tiff:%s,md:%s",
                                 p_png, p_tif, p_md)
      if (!(p_png && p_tif && p_md)) status[i] <- paste0(status[i], "|FORMAT_FAIL")
    } else {
      v <- pub_xlsx_verify(file.path(staging, tf))
      verification[i] <- sprintf("readable=%s,corrupt_cells=%s,styles=%s",
                                 v$readable, v$corrupt_cells, v$styles)
      if (!isTRUE(v$readable) || !identical(as.integer(v$corrupt_cells), 0L) ||
          !(is.finite(v$styles) && v$styles > 0)) {
        status[i] <- paste0(status[i], "|XLSX_FAIL")
      }
    }
  }
  mdf <- cbind(prof, source_files = source_files, target_file = target,
               status = status, verification = verification)
  utils::write.csv(mdf, file.path(staging, "MANIFEST.csv"), row.names = FALSE,
                   fileEncoding = "UTF-8")
  manifest_df <<- mdf

  modes <- if (length(bundles)) paste(sprintf("%s=%s", names(bundles),
          vapply(bundles, function(b) b$mode, character(1))),
          collapse = ", ") else "none"
  degrade <- Filter(nzchar, unlist(lapply(names(bundles), function(k)
    setNames(bundles[[k]]$degrade, k))))
  readme <- c(
    paste0("# AKI ", INDEX_LABEL, " — 原文（PMID 40537296）全图表双库复刻终稿"),
    "",
    sprintf("构建时间: %s | 引擎: %s | 编号单一来源: R/ml_reference_paper_profile.R",
            format(Sys.time()), engine_root),
    "",
    "## 数据库与结局口径",
    "- 主库（开发/内验）: **MIMIC-IV**（分析队列 n=18,394；attrition 26,055 -> 18,394，见 Figure 1）。",
    "- 外验库: **eICU**（分析队列 n=10,558；attrition 15,270 -> 10,558）。",
    "- 结局仅 **28 天全因死亡**（Survivor / Non-survivor）。两库最长随访 28 天；原文的更长随访",
    "  次要结局窗口本数据**不可算**（全稿不出现任何该类结局数字）。",
    "- 分层适配：原文按糖代谢（NGR/Pre-DM/DM）分层；eICU 无 HbA1c **不可算**，改用 AKI ICU 预后",
    "  文献经验证的 **SOFA<=10 / SOFA>=11** 数值分层，两库同公式同切点。",
    "- 原文「ICU 全程低血糖发作」敏感性：两库无该变量 **不可算**；已按规格适配为",
    "  「排除基线 Glucose <70 mg/dL」的联合 Cox 敏感性（Table S9，题名/脚注写明）。",
    "",
    "## 阅读顺序（关联在前、ML 在后）",
    "- Figure 1 纳排 -> Table 1 基线 -> Table 2 联合组 Cox -> Figure 2 KM / Figure 3 RCS /",
    "  Figure 4 ROC / Figure 5 Landmark / Figure 6 亚组森林 -> 补充表 S1-S10（关联侧）。",
    "- ML 在后：Figure 7 Boruta（仅 MIMIC-IV）-> Figure 8 分层五模型 ROC+SHAP -> Table S11；",
    "  补充图 S1-S5（原文角色）+ S6-S8（本课题额外三集图，旧 checkpoint 只读重编号）；",
    "  补充表 S12-S16（本课题额外；旧 overall 三集/超参/LogLoss/DeLong/NRI 表只读重排）。",
    "",
    "## SOFA 分层与冻结外验声明（未重训）",
    "- 全部 ML 模型只在 MIMIC-IV 开发数据训练（层内 train 上 Boruta + 模型，restrict_to_train",
    "  防泄漏）；eICU **不重做 Boruta/VIF、不重训**：ml_load_frozen_bundle +",
    "  ml_predict_external_bundle（provenance no_refit=TRUE；模型文件 md5==manifest checksum）。",
    "- Table S3/S11 与 _assets/model_assets/<stratum>/manifest.json 均记录 trained_in=MIMIC-IV。",
    "",
    "## 构建模式（诚实状态，禁谎称全量）",
    sprintf("- 三层五模型默认逐层尝试；超时/失败降级 logistic 并标 smoke_only。本次: %s。", modes),
    if (length(degrade) && any(nzchar(degrade)))
      c("- 降级原因（MANIFEST 同步标注）:",
        paste0("  - ", names(degrade)[nzchar(degrade)], ": ",
               substr(degrade[nzchar(degrade)], 1, 160))) else
      "- 本次无降级层（或全部成功）。",
    "- MANIFEST.csv 的 status/verification 列逐项记录角色与校验证据；",
    "  smoke_only / legacy_relayout 行不得作为五模型全量或新算结论引用。",
    "",
    "## 旧目录保留（审计底稿）",
    paste0("- by_index/【success】", INDEX_LABEL, "/ 下的 Tables/Figures/MIMIC_IV/eICU 与旧 publication_final/"),
    "  为审计底稿：本终稿**只读引用**（拷贝/重排/重编号），未改动、未删除；",
    "  旧 publication_final/OBSOLETE.md 指向本目录。",
    "",
    "## 编号与校验",
    "- 34 角色 = 主图 Figure 1-8 + 补充图 S1-S8 + 主表 Table 1-2 + 补充表 S1-S16（连续无重号）。",
    "- 图：Figures/pdf|png|tiff|image_information 四目录由 pub_figure_ensure_formats 导出，",
    "  根目录无平铺 PDF；image_information 详注经公共入口写入（含图上标注数值）。",
    "- 表：每张 xlsx 经 pub_xlsx_verify（readable=TRUE、corrupt_cells=0、styles>0）。",
    "- 小数位：est=3 / p=3 / desc=2 / cutoff=4 公共口径（R/utils.R pub_digits）。",
    "",
    "## 审计附件（非投稿产物）",
    "- _assets/：本次新冻结五模型资产（manifest.json 含逐文件 md5 + trained_in）与面板 AUC CSV。",
    "- authority/：Task4 派生权威 checkpoint（三分位锁定链，md5 溯源）。",
    "- _build_log.tsv：分阶段耗时与降级记录。投稿时以上三者可整体移出。")
  writeLines(readme, file.path(staging, "README.md"), useBytes = TRUE)
  sprintf("manifest=%d rows; ready_full=%d smoke_only=%d legacy=%d",
          nrow(mdf), sum(mdf$status == "ready_full"),
          sum(mdf$status == "smoke_only"), sum(mdf$status == "legacy_relayout"))
})

## 90 天字样全量扫描（终稿不得出现）
r_90 <- run_stage("scan_no_90day", 300, {
  hits <- 0L
  scan_one <- function(txt) {
    length(grep("90[- ]?(day|d)\\b|90\\s*天", txt, ignore.case = TRUE))
  }
  for (f in list.files(file.path(staging, "Tables"), pattern = "\\.xlsx$",
                       full.names = TRUE)) {
    d <- tryCatch(as.character(unlist(openxlsx::read.xlsx(f, colNames = FALSE))),
                  error = function(e) character(0))
    hits <- hits + sum(vapply(d, scan_one, integer(1)))
  }
  for (f in list.files(file.path(staging, "Figures", "image_information"),
                       pattern = "\\.md$", full.names = TRUE)) {
    hits <- hits + sum(vapply(readLines(f, warn = FALSE), scan_one, integer(1)))
  }
  for (f in c(file.path(staging, "MANIFEST.csv"), file.path(staging, "README.md"))) {
    if (file.exists(f)) hits <- hits + sum(vapply(readLines(f, warn = FALSE),
                                                  scan_one, integer(1)))
  }
  if (hits > 0L) stop(sprintf("发现 %d 处 90 天字样（终稿禁止）", hits),
                       call. = FALSE)
  "90-day occurrences=0"
})
# 90 天扫描必须门控替换：run_stage 只记 FAIL 不抛错，这里显式硬停
if (!r_90$ok) {
  stop("90 天字样扫描未过，拒绝原子替换（staging 保留供排查）: ",
       r_90$error, call. = FALSE)
}

## 终检（全部必需角色就位，无 *_FAIL/missing；四目录齐；16 图 18 表）
g <- run_stage("final_gate", 120, {
  mdf <- manifest_df
  if (any(grepl("_FAIL|missing", mdf$status))) {
    bad <- mdf[grepl("_FAIL|missing", mdf$status), c("kind", "number", "status")]
    stop("硬失败角色（拒绝替换）: ",
         paste(sprintf("%s%s=%s", bad$kind, bad$number, bad$status),
               collapse = "; "), call. = FALSE)
  }
  st <- pub_figure_formats_status(file.path(staging, "Figures"))
  if (!isTRUE(st$ok) || length(st$flat_leftovers)) {
    stop("四目录不完整或根目录有平铺 PDF（拒绝替换）", call. = FALSE)
  }
  nfig <- length(st$stems)
  ntab <- length(list.files(file.path(staging, "Tables"), pattern = "\\.xlsx$"))
  if (nfig != 16L || ntab != 18L) {
    stop(sprintf("角色数异常 figures=%d(应16) tables=%d(应18)", nfig, ntab),
         call. = FALSE)
  }
  sprintf("figures=%d tables=%d formats_ok=TRUE", nfig, ntab)
})
if (!g$ok) {
  stop("终检未过，拒绝原子替换（staging 保留供排查）: ", g$error, call. = FALSE)
}

## ---------------------------------------------------------------------------
## F) 原子替换 staging -> publication_literature_final
## ---------------------------------------------------------------------------
run_stage("atomic_swap", 300, {
  previous <- paste0(out_final, ".__previous__")
  if (dir.exists(previous)) unlink(previous, recursive = TRUE)
  backed_up <- FALSE
  if (dir.exists(out_final)) {
    if (!file.rename(out_final, previous)) {
      stop("无法备份旧 publication_literature_final -> .__previous__", call. = FALSE)
    }
    backed_up <- TRUE
  }
  if (!file.rename(staging, out_final)) {
    if (backed_up) file.rename(previous, out_final)  # 回滚旧终稿
    stop("staging -> final rename 失败",
         if (backed_up) "（已回滚旧终稿）" else "", call. = FALSE)
  }
  unlink(staging, recursive = TRUE)
  # 旧 publication_final/ 写 OBSOLETE.md 指向新终稿（不删除任何旧审计件）
  old_pub <- file.path(index_root_abs, "publication_final")
  if (dir.exists(old_pub) && !nzchar(Sys.getenv("AKI_REF_REPL_SKIP_OBSOLETE"))) {
    writeLines(c(
      "# OBSOLETE — 本目录已废弃（2026-09-18）",
      "",
      "本目录为旧「既有产物重排」终稿，不符合原文（PMID 40537296）面板结构，",
      "已被原文全图表双库适配复刻新终稿取代：",
      "",
      paste0("- **新终稿目录**: `", basename(out_final), "/`（同级目录）"),
      "- 新终稿规格: docs/superpowers/specs/2026-09-17-aki-sosm-wpr-original-paper-replication-design.md",
      "- 新终稿编号单一来源: R/ml_reference_paper_profile.R（Figure 1-8 / S1-S8 / Table 1-2 / S1-S16，34 角色）",
      "",
      "本目录全部文件保留为审计底稿，**未删除、未改动**；投稿一律使用新终稿目录。"),
      file.path(old_pub, "OBSOLETE.md"), useBytes = TRUE)
  }
  sprintf("swapped: staging -> %s | backup=%s", basename(out_final),
          if (backed_up) basename(previous) else "none")
})

cat(sprintf("\nBUILD_OK out=%s figures=%d tables=%d roles=34\n", out_final,
            length(pub_figure_formats_status(file.path(out_final, "Figures"))$stems),
            length(list.files(file.path(out_final, "Tables"),
                              pattern = "\\.xlsx$"))))
if (length(bundles)) {
  cat("MODES ", paste(sprintf("%s=%s", names(bundles),
      vapply(bundles, function(b) b$mode, character(1))),
      collapse = "  "), "\n", sep = "")
}
cat("LOG ", file.path(out_final, "_build_log.tsv"), "\n", sep = "")
