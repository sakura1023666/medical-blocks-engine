#!/usr/bin/env Rscript
# 1) 回补二分类结局到 imputed checkpoint
# 2) 仅跑新结局：Cesarean01 / Apgar1_lt8 / Apgar5_lt8 / Newborn_lt1500
# 3) ROC 改为预测 Disease（PE01 = Any PE vs Non-PE）
#
# Rscript run/61_preeclampsia/run_61_pe_new_outcomes_and_roc_disease.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}
`%||%` <- function(a, b) if (!is.null(a)) a else b

script_path <- .init_script_dir()
root <- if (basename(script_path) == "61_preeclampsia" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(root)

config_path <- "/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R"
args <- commandArgs(trailingOnly = TRUE)
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else i <- i + 1L
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)
source(file.path(root, "run/61_preeclampsia/blocks_shell/00block_pe_encode_group3_outcomes.R"), local = FALSE)

options(warn = 1, cli.hyperlink = FALSE)
Sys.setenv(SMOKE_NO_FEISHU = "1")

out_base <- config$project$output_dir
ck_shared <- (pipeline_shared$checkpoint %||% list())$dir %||%
  file.path(dirname(dirname(out_base)), "checkpoints", basename(out_base), "_shared")
ck_shared <- as.character(ck_shared)[1L]

.pe_load_ck <- function(path) {
  obj <- readRDS(path)
  if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
}

prefer <- c(
  "multicollinearity_screen.rds",
  "step08_multicollinearity_screen.rds",
  "imputation.rds",
  "step03_imputation.rds"
)
ck_pick <- NULL
for (bn in prefer) {
  p <- file.path(ck_shared, bn)
  if (file.exists(p)) { ck_pick <- p; break }
}
if (is.null(ck_pick)) stop("无共享 checkpoint", call. = FALSE)
shared_ctx <- .pe_load_ck(ck_pick)
cli::cli_alert_info("载入 checkpoint: {basename(ck_pick)}")

# ── 回补二分类结局列（按 Admission_Num 对齐 raw）────────────────────────────
imp <- as.data.frame(shared_ctx$data$imputed %||% shared_ctx$data$cleaned)
id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
if (!id %in% names(imp)) stop("imputed 缺少 ID 列: ", id, call. = FALSE)

env <- new.env(parent = emptyenv())
load(config$data$rawdata_path, envir = env)
raw <- as.data.frame(env[[config$data$rawdata_obj]])
if (!id %in% names(raw)) stop("raw 缺少 ID 列: ", id, call. = FALSE)

# 体重
nw <- trimws(as.character(raw$Newborn_Weight))
nw <- sub("/.*$", "", nw)
raw$Newborn_Weight_g <- suppressWarnings(as.numeric(nw))
raw$Newborn_Weight_g[is.finite(raw$Newborn_Weight_g) & raw$Newborn_Weight_g <= 0] <- NA_real_
raw$Newborn_lt1500 <- as.integer(
  is.finite(raw$Newborn_Weight_g) & raw$Newborn_Weight_g < 1500
)

# Apgar
raw$APGAR_1min <- suppressWarnings(as.numeric(as.character(raw$APGAR_1min)))
raw$APGAR_5min <- suppressWarnings(as.numeric(as.character(raw$APGAR_5min)))
raw$Apgar1_lt8 <- as.integer(is.finite(raw$APGAR_1min) & raw$APGAR_1min < 8)
raw$Apgar5_lt8 <- as.integer(is.finite(raw$APGAR_5min) & raw$APGAR_5min < 8)

# 剖宫产
raw$Cesarean01 <- as.integer(
  grepl("cesarean", as.character(raw$Delivery_Mode), ignore.case = TRUE)
)

keep_cols <- c(
  id, "Delivery_Mode", "Newborn_Weight_g", "Newborn_lt1500",
  "APGAR_1min", "APGAR_5min", "Apgar1_lt8", "Apgar5_lt8", "Cesarean01"
)
keep_cols <- intersect(keep_cols, names(raw))
map <- raw[, keep_cols, drop = FALSE]
map[[id]] <- as.character(map[[id]])
imp[[id]] <- as.character(imp[[id]])
for (cn in setdiff(keep_cols, id)) imp[[cn]] <- NULL
imp <- merge(imp, map, by = id, all.x = TRUE, sort = FALSE)

# PE01：三分类 Disease → Any PE
if (!"Disease" %in% names(imp)) stop("imputed 缺少 Disease", call. = FALSE)
imp$PE01 <- as.integer(as.character(imp$Disease) != "Non-preeclampsia")

# 确保 Preterm_delivery 存在（亚组用）
if (!"Preterm_delivery" %in% names(imp) && "Preterm34" %in% names(imp)) {
  imp$Preterm_delivery <- factor(
    ifelse(as.character(imp$Preterm34) == "Preterm34", "Yes", "No"),
    levels = c("No", "Yes")
  )
}
if ("Preterm_delivery" %in% names(imp) && !is.factor(imp$Preterm_delivery)) {
  imp$Preterm_delivery <- factor(
    ifelse(grepl("^Yes|Preterm", as.character(imp$Preterm_delivery), ignore.case = TRUE), "Yes", "No"),
    levels = c("No", "Yes")
  )
}

shared_ctx$data$imputed <- imp
shared_ctx$data$cleaned <- imp
# 写回 imputation/multicollinearity 旁的补丁 rds，供后续 units 用
patch_path <- file.path(ck_shared, "imputed_with_neonatal_outcomes.rds")
saveRDS(list(ctx = shared_ctx), patch_path)
cli::cli_alert_success(
  "回补结局: Cesarean={sum(imp$Cesarean01==1,na.rm=TRUE)}, Apgar1<8={sum(imp$Apgar1_lt8==1,na.rm=TRUE)}, Apgar5<8={sum(imp$Apgar5_lt8==1,na.rm=TRUE)}, NW<1500={sum(imp$Newborn_lt1500==1,na.rm=TRUE)}, PE01={sum(imp$PE01==1,na.rm=TRUE)}"
)

m1 <- as.character(shared_ctx$results$Model1Factors %||% "Age")
m2 <- as.character(shared_ctx$results$Model2Factors %||% character(0))
if (!length(m2)) stop("Model2Factors 为空", call. = FALSE)
shared_ctx$results$vif_final_pass <- m2

new_ous <- c("Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500")
outcomes <- config$pe_outcomes %||% list()

for (ou in new_ous) {
  spec <- outcomes[[ou]]
  if (is.null(spec)) stop("config$pe_outcomes 缺少 ", ou, call. = FALSE)
  oc <- as.character(spec$outcome_column %||% ou)[1L]
  cli::cli_h1("Unit: Disease → {oc}")

  cfg_u <- config
  cfg_u$data$outcome_column <- oc
  cfg_u$incidence$outcome_var <- oc
  cfg_u$project$analysis_group <- as.character(spec$analysis_group %||% "1")[1L]
  cfg_u$project$reference_group <- as.character(spec$reference_group %||% "0")[1L]
  if (!is.null(spec$disease_label) && nzchar(spec$disease_label)) {
    cfg_u$project$disease <- as.character(spec$disease_label)[1L]
  }
  cfg_u$project$output_dir <- file.path(out_base, "by_outcome", oc)
  oc_disp <- as.character(spec$disease_label %||% oc)[1L]
  cfg_u$logistic_binary_glm <- utils::modifyList(
    cfg_u$logistic_binary_glm %||% list(),
    list(
      model1_factors = m1,
      model2_factors = m2,
      table_filename = paste0(
        "Table 2. Logistic regression of Disease ", oc_disp, ".xlsx"
      ),
      random_search = list(enable = FALSE)
    )
  )

  sg_excl <- as.character((cfg_u$subgroup %||% list())$exclude_vars %||% character(0))
  sg_req <- as.character((cfg_u$subgroup %||% list())$required_subgroup_vars %||% character(0))
  outcome_like <- c(
    "GDM01", "Preterm34", "Preterm_delivery",
    "Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000",
    "PE01", "Delivery_Mode", "Newborn_Weight_g", "APGAR_1min", "APGAR_5min"
  )
  sg_excl <- unique(c(sg_excl, setdiff(outcome_like, "Preterm_delivery"), oc, "GDM01"))
  sg_excl <- setdiff(sg_excl, "GDM")
  if (!"Preterm_delivery" %in% sg_req) sg_req <- c(sg_req, "Preterm_delivery")
  if (oc %in% c("GDM01", "GDM")) {
    sg_excl <- unique(c(sg_excl, "GDM", "GDM01"))
    sg_req <- setdiff(sg_req, c("GDM", "GDM01"))
  } else if (!"GDM" %in% sg_req) {
    sg_req <- c(sg_req, "GDM")
  }
  sg_req <- setdiff(sg_req, c("Pre_BMI", "Pre_BMI_subg", oc))
  if (!"Pre_BMI_Group" %in% sg_req) sg_req <- c(sg_req, "Pre_BMI_Group")
  cfg_u$subgroup <- utils::modifyList(
    cfg_u$subgroup %||% list(),
    list(exclude_vars = sg_excl, required_subgroup_vars = sg_req)
  )

  pl_u <- pipeline_unit
  pl_u$checkpoint$enable <- TRUE
  pl_u$checkpoint$dir <- file.path(out_base, "by_outcome", oc, "checkpoints")

  ctx_u <- shared_ctx
  ctx_u$config <- cfg_u
  ctx_u$results$vif_final_pass <- m2
  ctx_u$results$Model1Factors <- m1
  ctx_u$results$Model2Factors <- m2

  ok <- tryCatch({
    run_pipeline(
      root,
      config = cfg_u,
      pipeline = pl_u,
      run_opts = list(
        initial_ctx = ctx_u,
        only = c("logistic_binary_glm", "subgroup_incidence")
      )
    )
    TRUE
  }, error = function(e) {
    cli::cli_alert_danger("{oc} 失败: {conditionMessage(e)}")
    FALSE
  })
  if (ok) cli::cli_alert_success("完成: {oc}")
}

# ── ROC：BMI/血脂 → PE01；同一指标各波次合图 ───────────────────────────────
cli::cli_h1("ROC: markers → Disease (PE01), waves overlay")
if (!requireNamespace("pROC", quietly = TRUE)) stop("需要 pROC", call. = FALSE)
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("需要 ggplot2", call. = FALSE)
if (!requireNamespace("openxlsx", quietly = TRUE)) stop("需要 openxlsx", call. = FALSE)

.pe_roc_specs <- list(
  list(stem = "BMI", times = c("Pre", "Early", "Mid", "Late"), label = "BMI"),
  list(stem = "Total_Cholesterol", times = c("Early", "Mid", "Late"), label = "Total cholesterol"),
  list(stem = "Triglycerides", times = c("Early", "Mid", "Late"), label = "Triglycerides"),
  list(stem = "HDL_Cholesterol", times = c("Early", "Mid", "Late"), label = "HDL cholesterol"),
  list(stem = "LDL_Cholesterol", times = c("Early", "Mid", "Late"), label = "LDL cholesterol"),
  list(stem = "FFA_Cholesterol", times = c("Early", "Mid", "Late"), label = "FFA cholesterol")
)
.pe_wave_cols <- c(Pre = "#4C78A8", Early = "#F58518", Mid = "#54A24B", Late = "#E45756")

roc_dir <- file.path(out_base, "_shared/supplement_plan/ROC_bmi_lipid_Disease")
roc_fig <- file.path(roc_dir, "Figures")
roc_tab <- file.path(roc_dir, "Tables")
for (d in c(roc_dir, roc_fig, roc_tab)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)
old_pdf <- list.files(roc_fig, pattern = "^ROC_PE01_.*\\.pdf$", full.names = TRUE)
if (length(old_pdf)) unlink(old_pdf)

y <- as.integer(imp$PE01)
rows <- list()
for (sp in .pe_roc_specs) {
  curves <- list()
  for (tm in sp$times) {
    mk <- paste0(tm, "_", sp$stem)
    if (!mk %in% names(imp)) next
    x <- suppressWarnings(as.numeric(imp[[mk]]))
    ok <- is.finite(x) & !is.na(y)
    if (sum(ok) < 20L || length(unique(y[ok])) < 2L) next
    roc_obj <- pROC::roc(response = y[ok], predictor = x[ok], quiet = TRUE, direction = "auto")
    auc_v <- as.numeric(pROC::auc(roc_obj))
    ci <- as.numeric(pROC::ci.auc(roc_obj, quiet = TRUE))
    coords <- pROC::coords(
      roc_obj, "best", best.method = "youden",
      ret = c("threshold", "sensitivity", "specificity")
    )
    rows[[length(rows) + 1L]] <- data.frame(
      outcome = "PE01_AnyPE_vs_NonPE",
      marker = mk,
      label = paste(tm, sp$label),
      wave = tm,
      biomarker = sp$label,
      n = sum(ok),
      events = sum(y[ok] == 1L),
      AUC = round(auc_v, 3),
      CI_low = round(ci[[1]], 3),
      CI_high = round(ci[[3]], 3),
      Youden_cutoff = as.numeric(coords[["threshold"]][1L]),
      Sensitivity = round(as.numeric(coords[["sensitivity"]][1L]), 3),
      Specificity = round(as.numeric(coords[["specificity"]][1L]), 3),
      direction = as.character(roc_obj$direction),
      stringsAsFactors = FALSE
    )
    curves[[tm]] <- data.frame(
      wave = tm,
      fpr = 1 - roc_obj$specificities,
      tpr = roc_obj$sensitivities,
      stringsAsFactors = FALSE
    )
  }
  if (!length(curves)) next
  df <- do.call(rbind, curves)
  df$wave <- factor(df$wave, levels = intersect(c("Pre", "Early", "Mid", "Late"), unique(df$wave)))
  lab_map <- c()
  for (tm in levels(df$wave)) {
    hit <- NULL
    for (r in rows) {
      if (identical(r$wave[[1]], tm) && identical(r$biomarker[[1]], sp$label)) {
        hit <- r
        break
      }
    }
    lab_map[tm] <- if (!is.null(hit)) {
      sprintf("%s  AUC=%.3f (%.3f-%.3f)", tm, hit$AUC, hit$CI_low, hit$CI_high)
    } else tm
  }
  df$wave_lab <- factor(lab_map[as.character(df$wave)], levels = unname(lab_map[levels(df$wave)]))
  cols_use <- .pe_wave_cols[levels(df$wave)]
  g <- ggplot2::ggplot(df, ggplot2::aes(x = .data$fpr, y = .data$tpr, color = .data$wave_lab)) +
    ggplot2::geom_path(linewidth = 1.05) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "longdash", color = "gray55") +
    ggplot2::scale_color_manual(
      values = stats::setNames(unname(cols_use), unname(lab_map[levels(df$wave)]))
    ) +
    ggplot2::scale_x_continuous("1 - Specificity", limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::scale_y_continuous("Sensitivity", limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    ggplot2::labs(title = paste0("ROC: ", sp$label, " to Any PE"), color = NULL) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, face = "bold", size = 13),
      panel.grid = ggplot2::element_blank(),
      legend.position = c(0.97, 0.03),
      legend.justification = c(1, 0),
      legend.background = ggplot2::element_rect(
        fill = grDevices::adjustcolor("white", alpha.f = 0.85), color = "gray80"
      ),
      legend.text = ggplot2::element_text(size = 9)
    )
  grDevices::pdf(
    file.path(roc_fig, paste0("ROC_PE01_", sp$stem, "_by_wave.pdf")),
    width = 7, height = 6.5
  )
  print(g)
  grDevices::dev.off()
}

tab <- do.call(rbind, rows)
rownames(tab) <- NULL
tab <- tab[order(tab$biomarker, match(tab$wave, c("Pre", "Early", "Mid", "Late"))), ]
xlsx_path <- file.path(roc_tab, "Table_ROC_BMI_lipid_Disease_PE01.xlsx")
utils::write.csv(tab, file.path(roc_tab, "Table_ROC_BMI_lipid_Disease_PE01.csv"), row.names = FALSE)
openxlsx::write.xlsx(tab, xlsx_path, overwrite = TRUE)
cli::cli_alert_success("Disease ROC: {xlsx_path}；合图 {length(.pe_roc_specs)} 张")
cli::cli_alert_success("全部完成")
