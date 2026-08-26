# tests/test_result_review_guards.R
# 对应《BAR-SAE 结果审查报告》A1–A5 / B2–B4，防止回归。
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pipeline_capability_layer.R"), local = FALSE)

# ── A3: 9e-04 / p≈0.0009 不得写成 P<0.0001 ─────────────────────────────────
stopifnot(exists("pub_format_p_cell", mode = "function"))
p_sci <- pub_format_p_cell(9e-04)
stopifnot(!grepl("0\\.0001", p_sci))
stopifnot(grepl("0\\.001", p_sci))
p_chr <- pub_format_p_cell("9e-04")
stopifnot(!grepl("0\\.0001", p_chr))
stopifnot(identical(pub_format_p_cell(0.0495), "0.0495"))
stopifnot(identical(pub_format_p_cell(0.0085), "0.0085"))
stopifnot(identical(pub_format_p_cell(1e-12), "<0.001"))

# 旧 cox_quartile 格式化：round(p,4) 把 0.00087 打成 "9e-04" 再误标 P<0.0001
old_round <- as.character(round(0.00087, 4))
stopifnot(grepl("[eE]", old_round) || identical(old_round, "9e-04") ||
            identical(old_round, "0.0009"))
stopifnot(!grepl("0\\.0001", pub_format_p_cell(old_round)))

rt <- data.frame(
  V1 = "Q2", V6 = old_round, V9 = "0.1033", V12 = "0.0803",
  stringsAsFactors = FALSE
)
rt2 <- pub_fix_p_cells(rt, c(2L, 3L, 4L))
stopifnot(!any(grepl("0\\.0001", unlist(rt2))))
stopifnot(grepl("0\\.001", rt2$V6))

# ── D1: CI 固定 3 位小数 ────────────────────────────────────────────────────
stopifnot(exists("pub_format_ci", mode = "function"))
stopifnot(identical(pub_format_ci(1.008, 1.02, 3L), "(1.008, 1.020)"))
stopifnot(identical(pub_format_est(1.51, 3L), "1.510"))

# ── A5: 分组表头是 N (%) 不是 Case (%) ──────────────────────────────────────
stopifnot(exists("pub_cox_group_n_header", mode = "function"))
stopifnot(identical(pub_cox_group_n_header(), "N (%)"))
stopifnot(!identical(pub_cox_group_n_header(), "Case (%)"))
stopifnot(identical(pub_glm_group_n_header(), "Events / N (%)"))
stopifnot(identical(pub_glm_group_n_cell(11L, 55L), "11/55 (20.00%)"))
stopifnot(!grepl("Case", pub_glm_group_n_header(), ignore.case = TRUE))
stopifnot(identical(pub_svy_group_events_n_header(), "Events / N (%)"))
# NHANES 加权主表不得再用组占全样本 % 冒充事件率
lqq_src <- paste(readLines(
  file.path(root, "Blocks/11_logistic/13block_logistic_quartile_nhanes_weighted.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl("Events / N \\(%\\)", lqq_src, perl = TRUE))
stopifnot(grepl("pub_svy_group_events_n_cell", lqq_src, fixed = TRUE))
# 随机搜协变量默认关，避免 Table2 与锁定 S7 分叉
lnw_src <- paste(readLines(
  file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl("rs_cfg\\$enable %\\|\\|% FALSE", lnw_src, perl = TRUE))
# 中介路径默认与 Table 2 锁定集同套（covariate_source=table2）
stopifnot(grepl(
  "table2|locked_multivariable_covariates",
  paste(deparse(pipeline_mediation_resolve_path_covariates), collapse = "\n")
))

# ── A1: KM 分组必须与 Cox 左闭右开（>= 切点进下一组）一致 ───────────────────
set.seed(1)
x <- c(rep(5.14, 20L), runif(80, 0, 30))
qs <- as.numeric(stats::quantile(x, na.rm = TRUE))[2:4]
cox_g <- character(length(x))
cox_g[x < qs[1]] <- "Q1"
cox_g[x >= qs[1] & x < qs[2]] <- "Q2"
cox_g[x >= qs[2] & x < qs[3]] <- "Q3"
cox_g[x >= qs[3]] <- "Q4"
km_g <- as.character(pipeline_quartile_factor(x, breaks = qs))
stopifnot(identical(cox_g, km_g))
# 3 个内部切点不得被误当成「去头去尾」后只剩中位数
km_g5 <- as.character(pipeline_quartile_factor(
  x, breaks = c(min(x), qs, max(x))
))
stopifnot(identical(cox_g, km_g5))

# 边界值等于 Q1 切点必须进 Q2（与 cox_quartile 一致，而非 cut(right=TRUE)）
x_eq <- c(qs[1], qs[1], qs[2], qs[3])
g_eq <- as.character(pipeline_quartile_factor(x_eq, breaks = qs))
stopifnot(identical(g_eq[1:2], c("Q2", "Q2")))

# ── A2: KM 图例 E= 必须是总事件，不是 28 天 landmark ────────────────────────
stopifnot(exists("pipeline_km_stratum_counts", mode = "function"))
if (requireNamespace("survival", quietly = TRUE)) {
  df <- data.frame(
    time = c(10, 20, 40, 50, 12, 60),
    event = c(1, 1, 1, 0, 1, 1),
    g = factor(c("Q1", "Q1", "Q1", "Q2", "Q2", "Q2"))
  )
  fit <- survival::survfit(survival::Surv(time, event) ~ g, data = df)
  cnt <- pipeline_km_stratum_counts(fit)
  stopifnot(identical(as.integer(cnt$n), c(3L, 3L)))
  stopifnot(identical(as.integer(cnt$n_event), c(3L, 2L)))
  s28 <- summary(fit, times = 28, extend = TRUE)
  # 28 天事件数必然 ≤ 总事件；本例 Q1 在 28 天后还有死亡
  stopifnot(sum(s28$n.event) < sum(cnt$n_event) || TRUE)
  stopifnot(as.integer(s28$n.event[1]) < as.integer(cnt$n_event[1]))
}

# ── A4: 中介 LM 的 Model1/Model2 必须用 Cox 协变量，禁止写死下标 1,15:18 ──
stopifnot(exists("pipeline_mediation_lm_adjustors", mode = "function"))
ctx_m <- list(results = list(
  cox_model1_covariates = c("Age", "Gender"),
  cox_model2_covariates = "Ventilation",
  Model1Factors = c("Age", "Gender"),
  Model2Factors = c("Age", "Gender", "Ventilation")
))
adj <- pipeline_mediation_lm_adjustors(ctx_m)
stopifnot(identical(adj$m1, c("Age", "Gender")))
stopifnot("Ventilation" %in% adj$m2)
stopifnot(length(adj$m2) > length(adj$m1))
# 短名单不得被 idx_keep=c(1,15:18) 裁成 Model1==Model2
ctx_short <- list(results = list(
  Model2Factors = c("Age", "Gender", "Ventilation_Hour")
))
adj_s <- pipeline_mediation_lm_adjustors(ctx_short)
stopifnot(length(adj_s$m2) >= 1L)

# ── B2: 亚组森林图默认 caption 须写明 Q4 vs Q1 ────────────────────────────
stopifnot(exists("pipeline_subgroup_forest_caption", mode = "function"))
cap <- pipeline_subgroup_forest_caption("BAR", mode = "highest_vs_lowest")
stopifnot(grepl("Q4 vs Q1|highest vs lowest|highest versus lowest", cap, ignore.case = TRUE))

# ── segmented Cox：cox_index_breaks 必须是 3 个内部切点，不能是 min/max 五元组
ctx_br <- list(results = list())
ctx_br <- pipeline_store_continuous_km_cutpoints(
  ctx_br, "BAR", c(0.1, 5.14, 9.17, 16.50, 80), method = "quartile"
)
stopifnot(length(ctx_br$results$cox_index_breaks) == 3L)
stopifnot(isTRUE(all.equal(ctx_br$results$cox_index_breaks, c(5.14, 9.17, 16.50))))

# ── B3: 切点两位小数，16.5 → 16.50 ─────────────────────────────────────────
stopifnot(identical(fmt_num(16.5), "16.50"))
stopifnot(identical(fmt_num(8.12), "8.12"))

# ── B4: 0% 缺失也要有 Missing (%) 行 ───────────────────────────────────────
stopifnot(exists("pipeline_s1_missing_pct_row", mode = "function"))
miss0 <- pipeline_s1_missing_pct_row(c(1, 2, 3), c(1, 2, 3), 3L, 3L)
stopifnot(!is.null(miss0))
stopifnot(grepl("Missing", miss0$Variable))
stopifnot(grepl("0", miss0$Before_MI))

# ── B1: Ventilation 与 Ventilation_Hour 不得映射成同一列 ───────────────────
stopifnot(exists("pipeline_split_ventilation_mapping", mode = "function"))
df_v <- data.frame(
  Ventilation = c(0, 1, 0),
  vent_hour = c(12, 40, 0),
  stringsAsFactors = FALSE
)
out_v <- pipeline_split_ventilation_mapping(df_v)
stopifnot("Ventilation" %in% names(out_v))
stopifnot("Ventilation_Hour" %in% names(out_v))
stopifnot(!is.numeric(out_v$Ventilation) || length(unique(out_v$Ventilation)) <= 2L)

# 仅有小时 → 派生 ever
df_h <- data.frame(Ventilation_Hour = c(0, 12.5, 40), stringsAsFactors = FALSE)
out_h <- pipeline_split_ventilation_mapping(df_h)
stopifnot("Ventilation" %in% names(out_h))
stopifnot(identical(as.integer(out_h$Ventilation), c(0L, 1L, 1L)) ||
            identical(as.character(out_h$Ventilation), c("No", "Yes", "Yes")))

# 闸门 A：eICU 只有 Ventilation 时，keep 里的 Ventilation_Hour 要换成 ever
stopifnot(exists("pipeline_ventilation_keep_alias", mode = "function"))
ka <- pipeline_ventilation_keep_alias(
  c("Age", "Ventilation_Hour", "SOFA"),
  c("Age", "Ventilation", "SOFA")
)
stopifnot("Ventilation" %in% ka)
stopifnot(!"Ventilation_Hour" %in% ka)
# 空 keep 不得被填成仅 Ventilation（否则 105→1）
ka_empty <- pipeline_ventilation_keep_alias(
  character(0),
  c("Age", "AST", "ALT", "Ventilation", "Disease_Group")
)
stopifnot(identical(ka_empty, character(0)))

# 展示名
stopifnot(grepl("ever|Mechanical", pipeline_var_display_name("Ventilation"), ignore.case = TRUE))
stopifnot(grepl("hour|duration", pipeline_var_display_name("Ventilation_Hour"), ignore.case = TRUE))

# 闸门 A：两库通气信息应对齐为共有 ever，小时不得进共有列
stopifnot(exists("pipeline_gate_a_align_ventilation_cols", mode = "function"))
al <- pipeline_gate_a_align_ventilation_cols(
  c("Age", "Ventilation"),
  c("Age", "Ventilation_Hour", "Ventilation"),
  c("Age", "Ventilation_Hour")
)
stopifnot("Ventilation" %in% al)
stopifnot(!"Ventilation_Hour" %in% al)
ever_f <- pipeline_ventilation_as_ever_factor(c(0, 1, 0))
stopifnot(identical(as.character(ever_f), c("No", "Yes", "No")))

# Figure 1：Times New Roman 不得在 pdf() 上炸（须走 pipeline_pdf_device）
stopifnot(exists("pipeline_pdf_device", mode = "function"))
tnr_pdf <- tempfile(fileext = ".pdf")
ff <- pipeline_pdf_device(tnr_pdf, width = 4, height = 3, family = "Times New Roman")
grDevices::dev.off()
stopifnot(file.exists(tnr_pdf), file.info(tnr_pdf)$size > 0)
unlink(tnr_pdf)

# --no-skip 覆盖已有目录
stopifnot(exists("pipeline_remove_dir", mode = "function"))
td <- tempfile("rmdir_test")
dir.create(td, recursive = TRUE)
writeLines("x", file.path(td, "f.txt"))
stopifnot(isTRUE(pipeline_remove_dir(td)))
stopifnot(!dir.exists(td))

# ensure_gate_a / rename 必须接受 force=、overwrite=（--no-skip 重算并覆盖 success）
runner_txt <- paste(
  readLines(file.path(root, "R/incidence_dual_batch_runner.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("force = FALSE", runner_txt))
stopifnot(grepl("overwrite = FALSE", runner_txt))
stopifnot(grepl("force = !skip_exist", runner_txt))
stopifnot(!grepl(
  "dual_db\\$enable\\) && identical\\(db_mode, \"both\"\\)",
  runner_txt
))
surv_txt <- paste(
  readLines(file.path(root, "R/survival_dual_batch_runner.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("force = !skip_exist", surv_txt))
sens_txt <- paste(
  readLines(file.path(root, "R/incidence_sensitivity_suite.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("force = FALSE", sens_txt))
stopifnot(grepl("--no-skip，重跑已成功敏感性", sens_txt))

# ── 缺失>40%：Height/Weight/BMI 不在插补保护名单 ──────────────────────────
stopifnot(exists("pipeline_imputation_missing_protect_vars", mode = "function"))
imp_prot <- pipeline_imputation_missing_protect_vars(list(
  data = list(outcome_column = "Disease_Group", id_column = "ID"),
  incidence = list(index_var = "De_Ritis")
))
stopifnot(!"Height" %in% imp_prot)
stopifnot(!"Weight" %in% imp_prot)
stopifnot(!"BMI" %in% imp_prot)
stopifnot("Age" %in% imp_prot)
stopifnot("Disease_Group" %in% imp_prot)

# ── 多变量 ROC 默认用锁定协变量，不用 config 13 项扩列 ────────────────────
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(root, "Blocks/13_roc/02block_simple_ROC.R"), local = FALSE)
stopifnot(identical(.sroc_resolve_mode(list()), "multivariable"))
stopifnot(identical(.sroc_resolve_mode(list(mode = "univariate")), "univariate"))
stopifnot(identical(
  .sroc_resolve_outcome_var(list(), list(
    project = list(study_type = "prognosis"),
    survival = list(event_var = "fustatus"),
    data = list(outcome_column = "Disease")
  )),
  "fustatus"
))
stopifnot(identical(
  .sroc_resolve_outcome_var(list(), list(
    project = list(study_type = "incidence"),
    survival = list(event_var = "fustatus"),
    data = list(outcome_column = "Disease_Group")
  )),
  "Disease_Group"
))
ctx_roc <- list(results = list(
  vif_final_pass = c("Age", "Hypertension", "Hyperlipidemia", "De_Ritis")
))
cfg_roc <- list(incidence = list(index_var = "De_Ritis"))
cols <- c("Age", "Hypertension", "Hyperlipidemia", "De_Ritis", "WBC", "GCS", "RR")
cov_locked <- .sroc_resolve_covariates(
  list(covariate_source = "locked"), cols, ctx = ctx_roc, cfg = cfg_roc
)
stopifnot(identical(sort(cov_locked), c("Age", "Hyperlipidemia", "Hypertension")))
stopifnot(!"WBC" %in% cov_locked)
cov_cfg <- .sroc_resolve_covariates(
  list(covariate_source = "config", model_covariates = c("WBC", "GCS")),
  cols, ctx = ctx_roc, cfg = cfg_roc
)
stopifnot(identical(sort(cov_cfg), c("GCS", "WBC")))
# 双库 Gate B 锁定后：locked 名单 = Model2Factors（与 Table 2 一致），不是整库 vif_final_pass
ctx_gate <- list(
  results = list(
    dual_db_cox_unified_locked = TRUE,
    Model2Factors = c("Age", "Gender", "RDW"),
    vif_final_pass = c("Age", "BMI", "WBC", "Platelet_Count", "RDW", "Lactate", "PT", "Ventilation", "BAR")
  )
)
cfg_gate <- list(survival = list(index_var = "BAR"), project = list(study_type = "prognosis"))
lk_gate <- locked_multivariable_covariates(ctx_gate, cfg_gate)
stopifnot(identical(sort(lk_gate$covariates), c("Age", "Gender", "RDW")))
stopifnot(!"WBC" %in% lk_gate$covariates)
stopifnot(!"Ventilation" %in% lk_gate$covariates)
# ROC vif_final：用完整 VIF，不跟 Table 2 剪枝短名单
cov_vif <- .sroc_resolve_covariates(
  list(covariate_source = "vif_final"),
  c("Age", "BMI", "WBC", "Platelet_Count", "RDW", "Lactate", "PT", "Ventilation", "BAR", "Gender"),
  ctx = ctx_gate, cfg = cfg_gate
)
stopifnot("WBC" %in% cov_vif)
stopifnot("Ventilation" %in% cov_vif)
stopifnot(!"BAR" %in% cov_vif)
cov_locked_gate <- .sroc_resolve_covariates(
  list(covariate_source = "locked"),
  c("Age", "BMI", "WBC", "Platelet_Count", "RDW", "Lactate", "PT", "Ventilation", "BAR", "Gender"),
  ctx = ctx_gate, cfg = cfg_gate
)
stopifnot(identical(sort(cov_locked_gate), c("Age", "Gender", "RDW")))
cov_empty <- .sroc_resolve_covariates(
  list(covariate_source = "locked"), cols,
  ctx = list(results = list()), cfg = cfg_roc
)
stopifnot(identical(cov_empty, character(0)))
# 块源码：multivariable 且锁定为空必须 stop（非 warning+return）
sroc_src <- paste(readLines(
  file.path(root, "Blocks/13_roc/02block_simple_ROC.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl(
  "mode=multivariable 但锁定协变量为空",
  sroc_src,
  fixed = TRUE
))
stopifnot(grepl(
  'r_cfg\\$mode %\\|\\|% "multivariable"',
  sroc_src,
  perl = TRUE
))

# ── 发病基线：simple_ROC 必须在锁定多因素之后 ────────────────────────────
bl_txt <- paste(readLines(
  file.path(root, "configs/study_interface/baseline_pipelines.json"),
  warn = FALSE
), collapse = "\n")
# regular 批：simple_ROC 须在 multivariate_incidence_harmonized 之后
i_lock <- regexpr("multivariate_incidence_harmonized", bl_txt, fixed = TRUE)[1L]
stopifnot(i_lock > 0L)
bl_after_reg <- substring(bl_txt, i_lock)
i_roc <- regexpr('"simple_ROC"', bl_after_reg, perl = TRUE)[1L]
stopifnot(i_roc > 0L)
# NHANES 批：simple_ROC 须在 multivariate_nhanes_harmonized 之后
i_nh_lock <- regexpr("multivariate_nhanes_harmonized", bl_txt, fixed = TRUE)[1L]
stopifnot(i_nh_lock > 0L)
bl_after_nh <- substring(bl_txt, i_nh_lock)
i_nh_roc <- regexpr('"simple_ROC"', bl_after_nh, perl = TRUE)[1L]
stopifnot(i_nh_roc > 0L)
# 生存基线 core 含 harmonized；simple_ROC 由课题尾部扩展挂上，不得出现在 harmonized 之前
i_surv_harm <- regexpr("multivariate_prognosis_harmonized", bl_txt, fixed = TRUE)[1L]
stopifnot(i_surv_harm > 0L)
ml_roc_pin <- paste(readLines(
  file.path(root, "configs/templates/config_ml_dual_batch.template.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl("mode = \"univariate\"", ml_roc_pin, fixed = TRUE))

# cutoff 默认不导出发表 ROC（发表 Figure S* 由 simple_ROC 产出）
cutoff_src <- paste(readLines(
  file.path(root, "Blocks/14_cutoff/01block_cutoff.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl(
  "export_roc_figure %\\|\\|% FALSE",
  cutoff_src,
  perl = TRUE
))
stopifnot(grepl(
  "export_roc_figure=FALSE，跳过发表 ROC 图",
  cutoff_src,
  fixed = TRUE
))

# ── 中介默认标准化 + 负比例脚注 ───────────────────────────────────────────
fn <- pipeline_mediation_table_footnotes(TRUE)
stopifnot(any(grepl("1-SD", fn, ignore.case = TRUE)))
stopifnot(any(grepl("suppression|masking|遮掩", fn, ignore.case = TRUE)))

# 实验室关联表列名改为 β per 1-SD 后，不得再写 β value（否则 0-row 赋值炸）
med_inc <- paste(readLines(
  file.path(root, "Blocks/20_mediation/02block_mediation_incidence.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl("β per 1-SD", med_inc, fixed = TRUE))
stopifnot(grepl('beta_col <- "β per 1-SD"', med_inc, fixed = TRUE))
stopifnot(!grepl('rt\\[\\["β value"\\]\\]', med_inc))
# 1-SD 标准化：z 必须写进 model_data（na.omit 之后），不能只写在全表再丢列
stopifnot(grepl("model_data\\$\\.M_z\\s*<-\\s*as\\.numeric\\(scale\\(model_data", med_inc))
med_prog <- paste(readLines(
  file.path(root, "Blocks/20_mediation/01block_mediation_prognosis.R"),
  warn = FALSE
), collapse = "\n")
stopifnot(grepl("model_data\\$\\.M_z\\s*<-\\s*as\\.numeric\\(scale\\(model_data", med_prog))

# 冒烟：use_z 路径能产出非空 OR 字符串
set.seed(42)
n <- 120L
x <- rnorm(n)
m <- 0.4 * x + rnorm(n)
y <- rbinom(n, 1L, plogis(-0.5 + 0.5 * x + 0.6 * m))
dat <- data.frame(De_Ritis = x, LD = m, Disease_Group = factor(y, labels = c("Non_ASCVD", "ASCVD")))
# 复现旧 bug：z 在全表、子集丢列 → lm 失败
dat_bad <- dat
dat_bad$.M_z <- as.numeric(scale(dat_bad$LD))
md_bad <- dat_bad[, c("Disease_Group", "De_Ritis", "LD"), drop = FALSE]
stopifnot(!" .M_z" %in% names(md_bad) || !".M_z" %in% names(md_bad))
stopifnot(is.null(tryCatch(lm(.M_z ~ De_Ritis, data = md_bad), error = function(e) NULL)))
# 正确：子集后再写 z
md_ok <- dat[, c("Disease_Group", "De_Ritis", "LD"), drop = FALSE]
md_ok$.M_z <- as.numeric(scale(md_ok$LD))
fit_ok <- lm(.M_z ~ De_Ritis, data = md_ok)
stopifnot(inherits(fit_ok, "lm"))
stopifnot(is.finite(coef(fit_ok)[["De_Ritis"]]))

# ── 汇总 Tables 不写/不留 .tex（LaTeX 仅 step*/Tables）─────────────────────
stopifnot(exists("pipeline_is_aggregate_pub_tables_path", mode = "function"))
stopifnot(isTRUE(pipeline_is_aggregate_pub_tables_path(
  "/out/De_Ritis/Tables/Table S9-MIMIC. Mediation.tex"
)))
stopifnot(isTRUE(pipeline_is_aggregate_pub_tables_path(
  "/out/De_Ritis/MIMIC/Tables/Table S9-MIMIC. Mediation.tex"
)))
stopifnot(isFALSE(pipeline_is_aggregate_pub_tables_path(
  "/out/MIMIC/step25_mediation_incidence/Tables/Table S11.tex"
)))
td_agg <- tempfile("agg_tables_")
dir.create(td_agg)
writeLines("% stale", file.path(td_agg, "Table S9.tex"))
n_purge <- pipeline_purge_aggregate_tex(td_agg)
stopifnot(identical(as.integer(n_purge), 1L))
stopifnot(!file.exists(file.path(td_agg, "Table S9.tex")))
unlink(td_agg, recursive = TRUE)

# ── 汇总 Figures：分库单图硬清扫（只留拼图）────────────────────────────────
source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)
stopifnot(exists("dual_db_purge_single_db_figures", mode = "function"))
fd <- tempfile("agg_figs_")
dir.create(fd)
file.create(file.path(fd, "Figure S3. Mediation path diagram.pdf"))
file.create(file.path(fd, "Figure S3-eICU. Mediation path diagram.pdf"))
file.create(file.path(fd, "Figure S3-MIMIC. Mediation path diagram.pdf"))
file.create(file.path(fd, "Figure 4. Subgroup Forest.pdf"))
purged <- dual_db_purge_single_db_figures(fd)
stopifnot(length(purged) == 2L)
stopifnot(file.exists(file.path(fd, "Figure S3. Mediation path diagram.pdf")))
stopifnot(file.exists(file.path(fd, "Figure 4. Subgroup Forest.pdf")))
stopifnot(!file.exists(file.path(fd, "Figure S3-eICU. Mediation path diagram.pdf")))
stopifnot(!file.exists(file.path(fd, "Figure S3-MIMIC. Mediation path diagram.pdf")))
unlink(fd, recursive = TRUE)

# 单库/未拼成对：不得清掉汇总 Figures 里的 -MIMIC 单图
fd2 <- tempfile("agg_figs_single_")
dir.create(fd2)
file.create(file.path(fd2, "Figure 2-MIMIC. RCS plot.pdf"))
file.create(file.path(fd2, "Figure 1. Flowchart.pdf"))
cfg_single <- list(
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE),
    primary = list(name = "MIMIC"),
    secondary = list(name = "MIMIC")
  )
)
dual_db_combine_paired_figures(dirname(fd2), cfg_single)
# combine 看的是 index_root/Figures；上面把 fd2 当成了 Figures 本身
# 改用正确布局
unlink(fd2, recursive = TRUE)
ix_root <- tempfile("ix_root_")
dir.create(file.path(ix_root, "Figures"), recursive = TRUE)
file.create(file.path(ix_root, "Figures", "Figure 2-MIMIC. RCS plot.pdf"))
file.create(file.path(ix_root, "Figures", "Figure S1-MIMIC. Boxplot.pdf"))
file.create(file.path(ix_root, "Figures", "Figure 1. Flowchart.pdf"))
dual_db_combine_paired_figures(ix_root, cfg_single)
stopifnot(file.exists(file.path(ix_root, "Figures", "Figure 2-MIMIC. RCS plot.pdf")))
stopifnot(file.exists(file.path(ix_root, "Figures", "Figure S1-MIMIC. Boxplot.pdf")))
unlink(ix_root, recursive = TRUE)

# ── 汇总 Figures：export 后顶层无散落图文件 ────────────────────────────────
if (!exists("export_pub_figures", mode = "function")) {
  source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
}
fd_exp <- tempfile("agg_figs_export_")
dir.create(fd_exp)
make_guard_pdf <- function(path) {
  grDevices::pdf(path, width = 4, height = 3, onefile = TRUE)
  plot.new()
  title("guard fig")
  grDevices::dev.off()
}
make_guard_pdf(file.path(fd_exp, "Figure 1. Flowchart.pdf"))
make_guard_pdf(file.path(fd_exp, "Figure 2. RCS plot.pdf"))
export_pub_figures(
  fd_exp,
  meta = list(
    exposure = "De_Ritis",
    outcome = "Disease_Group",
    databases = c("NHANES", "MIMIC"),
    combined = TRUE,
    grouping = "quartile"
  ),
  config = list(pub_figures = list(dpi = 72L))
)
top_after <- list.files(fd_exp, pattern = "\\.(pdf|png|tiff|tif)$", ignore.case = TRUE)
stopifnot(length(top_after) == 0L)
stopifnot(dir.exists(file.path(fd_exp, "pdf")))
stopifnot(dir.exists(file.path(fd_exp, "png")))
stopifnot(dir.exists(file.path(fd_exp, "tiff")))
stopifnot(dir.exists(file.path(fd_exp, "image_information")))
unlink(fd_exp, recursive = TRUE)

# finalize 顺序：curate 之后调用 export_pub_figures
stopifnot(grepl("incidence_batch_curate_index_pub_outputs", runner_txt))
stopifnot(grepl("export_pub_figures\\(figs_dir", runner_txt))
curate_pos <- regexpr("incidence_batch_curate_index_pub_outputs", runner_txt)[1L]
export_pos <- regexpr("export_pub_figures\\(figs_dir", runner_txt)[1L]
stopifnot(curate_pos > 0L, export_pos > 0L, export_pos > curate_pos)

# run_pipeline 收口：pub_renumber 之后 export；dual 分库 worker 跳过
pipe_txt <- paste(
  readLines(file.path(root, "R/pipeline_runner.R"), warn = FALSE),
  collapse = "\n"
)
stopifnot(grepl("export_pub_figures\\(figs", pipe_txt))
stopifnot(grepl("pipeline_figures_is_dual_slot", pipe_txt))
stopifnot(grepl("current_db", pipe_txt))
stopifnot(grepl("dual\\$enable", pipe_txt))
stopifnot(grepl("by_index/\\[\\^/\\]\\+/\\[\\^/\\]\\+/Figures", pipe_txt))
stopifnot(grepl("pub_renumber_pub_dir", pipe_txt))
renum_pos <- regexpr("pub_renumber_pub_dir", pipe_txt)[1L]
pipe_export_pos <- regexpr("export_pub_figures\\(figs", pipe_txt)[1L]
stopifnot(renum_pos > 0L, pipe_export_pos > 0L, pipe_export_pos > renum_pos)

# pipeline_figures_is_dual_slot：current_db / 分库路径名 / by_index 槽位
if (!exists("pipeline_figures_is_dual_slot", mode = "function")) {
  source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
}
stopifnot(exists("pipeline_figures_is_dual_slot", mode = "function"))
cfg_dual <- list(
  dual_db = list(
    enable = TRUE,
    current_db = NULL,
    primary = list(name = "NHANES"),
    secondary = list(name = "MIMIC")
  )
)
stopifnot(isTRUE(pipeline_figures_is_dual_slot(
  "/proj/by_index/UHR/NHANES/Figures", cfg_dual
)))
stopifnot(!isTRUE(pipeline_figures_is_dual_slot(
  "/proj/by_index/UHR/Figures", cfg_dual
)))
cfg_worker <- list(dual_db = list(enable = TRUE, current_db = "nhanes"))
stopifnot(isTRUE(pipeline_figures_is_dual_slot("/proj/Figures", cfg_worker)))

# competing_pub_export：combine 先于 export；export 先于 cli_alert_success
comp_txt <- paste(
  readLines(
    file.path(root, "Blocks/55_competing_risk_full/18block_competing_pub_export.R"),
    warn = FALSE
  ),
  collapse = "\n"
)
stopifnot(grepl("export_pub_figures\\(", comp_txt))
stopifnot(grepl("dual_db_combine_paired_figures", comp_txt))
comp_combine_pos <- regexpr("dual_db_combine_paired_figures", comp_txt)[1L]
comp_export_pos <- regexpr("export_pub_figures\\(", comp_txt)[1L]
comp_success_pos <- regexpr("cli_alert_success\\(\"文献级导出完成", comp_txt)[1L]
stopifnot(
  comp_combine_pos > 0L, comp_export_pos > 0L, comp_success_pos > 0L,
  comp_combine_pos < comp_export_pos, comp_export_pos < comp_success_pos
)

# Charlson 归入 Clinical Scores，不得落到表末
ord <- sort_vars_by_table1_sections(
  c("Age", "WBC", "APSIII", "Hypertension", "Charlson", "De_Ritis"),
  list(incidence = list(index_var = "De_Ritis"), baseline_binary = list())
)
stopifnot(identical(ord[ord %in% c("APSIII", "Charlson")], c("APSIII", "Charlson")))
stopifnot(which(ord == "Charlson") < which(ord == "Hypertension"))

message("test_result_review_guards: OK")
