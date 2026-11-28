#!/usr/bin/env Rscript
# Table1 扩展（分娩方式/新生儿体重/Apgar）+ 早中期 BMI/血脂单变量 ROC
# Rscript run/61_preeclampsia/run_61_pe_table1_roc_expand.R

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
source(file.path(root, "Blocks/04_baseline/02block_baseline_multiclass.R"), local = FALSE)

options(warn = 1, cli.hyperlink = FALSE)
Sys.setenv(SMOKE_NO_FEISHU = "1")
if (!requireNamespace("pROC", quietly = TRUE)) {
  stop("需要 pROC 包", call. = FALSE)
}
if (!requireNamespace("openxlsx", quietly = TRUE)) {
  stop("需要 openxlsx 包", call. = FALSE)
}

out_base <- config$project$output_dir
ck_shared <- (pipeline_shared$checkpoint %||% list())$dir %||%
  file.path(dirname(dirname(out_base)), "checkpoints", basename(out_base), "_shared")
ck_shared <- as.character(ck_shared)[1L]

.pe_load_ck <- function(path) {
  obj <- readRDS(path)
  if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
}

ck_imp <- file.path(ck_shared, "imputation.rds")
if (!file.exists(ck_imp)) ck_imp <- file.path(ck_shared, "step03_imputation.rds")
if (!file.exists(ck_imp)) stop("缺少 imputation checkpoint: ", ck_shared, call. = FALSE)
ctx <- .pe_load_ck(ck_imp)
ctx$config <- config
ctx$config$project$output_dir <- out_base

# 回补 Newborn_Weight_g（插补时字符体重列曾被丢掉）
.load_raw <- function() {
  env <- new.env(parent = emptyenv())
  load(config$data$rawdata_path, envir = env)
  env[[config$data$rawdata_obj]]
}
.raw <- .load_raw()
.id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
if (!.id %in% names(ctx$data$imputed) || !.id %in% names(.raw)) {
  stop("无法按 ", .id, " 回补新生儿体重", call. = FALSE)
}
nw <- trimws(as.character(.raw$Newborn_Weight))
nw <- sub("/.*$", "", nw)
.map <- data.frame(
  .id = as.character(.raw[[.id]]),
  Newborn_Weight_g = suppressWarnings(as.numeric(nw)),
  stringsAsFactors = FALSE
)
.map$Newborn_Weight_g[.map$Newborn_Weight_g <= 0] <- NA_real_
imp <- as.data.frame(ctx$data$imputed)
imp$.id <- as.character(imp[[.id]])
imp$Newborn_Weight_g <- NULL
imp <- merge(imp, .map, by = ".id", all.x = TRUE, sort = FALSE)
imp$.id <- NULL
if (!"Delivery_Mode" %in% names(imp) && "Delivery_Mode" %in% names(.raw)) {
  dm <- data.frame(.id = as.character(.raw[[.id]]), Delivery_Mode = .raw$Delivery_Mode)
  imp$.id <- as.character(imp[[.id]])
  imp <- merge(imp, dm, by = ".id", all.x = TRUE, sort = FALSE)
  imp$.id <- NULL
}
for (ac in c("APGAR_1min", "APGAR_5min")) {
  if (ac %in% names(imp)) imp[[ac]] <- suppressWarnings(as.numeric(as.character(imp[[ac]])))
}
ctx$data$imputed <- imp
ctx$data$cleaned <- imp
cli::cli_alert_success(
  "回补 Newborn_Weight_g：非缺失 {sum(is.finite(imp$Newborn_Weight_g))}/{nrow(imp)}"
)

# 输出目录对齐 Full_pipeline/_shared/step05
shared_out <- file.path(out_base, "_shared")
step_name <- "step05_baseline_multiclass"
ctx$output_dir <- file.path(shared_out, step_name)
ctx$output_dir_tables <- file.path(ctx$output_dir, "Tables")
ctx$output_dir_figures <- file.path(ctx$output_dir, "Figures")
ctx$output_dir_data <- file.path(ctx$output_dir, "Data")
for (d in c(ctx$output_dir, ctx$output_dir_tables, ctx$output_dir_figures, ctx$output_dir_data)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}
ctx$block_name <- "baseline_multiclass"
ctx$step_name <- step_name

cli::cli_h1("Table1 扩展重跑")
ctx <- block_baseline_multiclass(ctx)
saveRDS(ctx, file.path(ck_shared, "baseline_multiclass.rds"))
cli::cli_alert_success("Table1 已更新: {ctx$output_dir_tables}")

# ── 单变量 ROC：早/中期 BMI + 血脂 to Preterm34 / GDM01 ─────────────────────
cli::cli_h1("单变量 ROC（BMI / 血脂）")
roc_markers <- c(
  "Pre_BMI", "Early_BMI", "Mid_BMI", "Late_BMI",
  "Early_Total_Cholesterol", "Early_Triglycerides", "Early_HDL_Cholesterol",
  "Early_LDL_Cholesterol", "Early_FFA_Cholesterol",
  "Mid_Total_Cholesterol", "Mid_Triglycerides", "Mid_HDL_Cholesterol",
  "Mid_LDL_Cholesterol", "Mid_FFA_Cholesterol",
  "Late_Total_Cholesterol", "Late_Triglycerides", "Late_HDL_Cholesterol",
  "Late_LDL_Cholesterol", "Late_FFA_Cholesterol"
)
outcomes <- list(
  Preterm34 = list(col = "Preterm34", event = "Preterm34"),
  GDM01 = list(col = "GDM01", event = 1L)
)
roc_dir <- file.path(shared_out, "supplement_plan", "ROC_bmi_lipid")
roc_fig <- file.path(roc_dir, "Figures")
roc_tab <- file.path(roc_dir, "Tables")
for (d in c(roc_dir, roc_fig, roc_tab)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)

.disp <- function(v) {
  labs <- getOption("blocks_var_display_labels", default = list())
  if (!is.null(labs[[v]]) && nzchar(labs[[v]])) return(as.character(labs[[v]])[1L])
  # Early_FFA_Cholesterol to Early FFA cholesterol
  stem_map <- c(
    Total_Cholesterol = "Total cholesterol",
    Triglycerides = "Triglycerides",
    HDL_Cholesterol = "HDL cholesterol",
    LDL_Cholesterol = "LDL cholesterol",
    FFA_Cholesterol = "FFA cholesterol",
    BMI = "BMI"
  )
  m <- regexec("^(Pre|Early|Mid|Late)_(.+)$", v)
  r <- regmatches(v, m)[[1]]
  if (length(r) == 3L) {
    st <- stem_map[[r[[3]]]] %||% gsub("_", " ", r[[3]], fixed = TRUE)
    return(paste(r[[2]], st))
  }
  gsub("_", " ", v, fixed = TRUE)
}

rows <- list()
for (onm in names(outcomes)) {
  oc <- outcomes[[onm]]
  y_raw <- imp[[oc$col]]
  if (is.null(y_raw)) next
  if (is.factor(y_raw) || is.character(y_raw)) {
    y <- as.integer(as.character(y_raw) == as.character(oc$event))
  } else {
    y <- as.integer(as.numeric(y_raw) == as.numeric(oc$event))
  }
  for (mk in roc_markers) {
    if (!mk %in% names(imp)) next
    x <- suppressWarnings(as.numeric(imp[[mk]]))
    ok <- is.finite(x) & !is.na(y)
    if (sum(ok) < 20L || length(unique(y[ok])) < 2L) next
    roc_obj <- tryCatch(
      pROC::roc(response = y[ok], predictor = x[ok], quiet = TRUE, direction = "auto"),
      error = function(e) NULL
    )
    if (is.null(roc_obj)) next
    auc_v <- as.numeric(pROC::auc(roc_obj))
    ci <- as.numeric(pROC::ci.auc(roc_obj, quiet = TRUE))
    coords <- pROC::coords(
      roc_obj, "best", best.method = "youden",
      ret = c("threshold", "sensitivity", "specificity")
    )
    rows[[length(rows) + 1L]] <- data.frame(
      outcome = onm,
      marker = mk,
      label = .disp(mk),
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

    # 图：每个 outcome×marker 一张
    df_line <- data.frame(
      fpr = 1 - roc_obj$specificities,
      tpr = roc_obj$sensitivities
    )
    lbl <- sprintf(
      "AUC = %.3f\n95%% CI: [%.3f, %.3f]",
      auc_v, ci[[1]], ci[[3]]
    )
    g <- ggplot2::ggplot(df_line, ggplot2::aes(x = .data$fpr, y = .data$tpr)) +
      ggplot2::geom_path(linewidth = 1, color = "#C6524A") +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "longdash", color = "gray50") +
      ggplot2::scale_x_continuous("1 - Specificity", limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
      ggplot2::scale_y_continuous("Sensitivity", limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
      ggplot2::annotate("text", x = 1, y = 0.3, label = lbl, hjust = 1, size = 3.8, color = "#C6524A") +
      ggplot2::labs(title = paste0("ROC: ", .disp(mk), " to ", onm)) +
      ggplot2::theme_bw(base_family = "sans") +
      ggplot2::theme(
        plot.title = ggplot2::element_text(hjust = 0.5, face = "bold", size = 12),
        panel.grid = ggplot2::element_blank()
      )
    fig_path <- file.path(roc_fig, paste0("ROC_", onm, "_", mk, ".pdf"))
    grDevices::pdf(fig_path, width = 6.5, height = 6.5)
    print(g)
    grDevices::dev.off()
  }
}

tab <- do.call(rbind, rows)
rownames(tab) <- NULL
csv_path <- file.path(roc_tab, "Table_ROC_BMI_lipid_univariate.csv")
xlsx_path <- file.path(roc_tab, "Table_ROC_BMI_lipid_univariate.xlsx")
utils::write.csv(tab, csv_path, row.names = FALSE)
openxlsx::write.xlsx(tab, xlsx_path, overwrite = TRUE)
cli::cli_alert_success("ROC 汇总: {xlsx_path}（{nrow(tab)} 行）")
cli::cli_alert_success("全部完成")
invisible(list(ctx = ctx, roc = tab))
