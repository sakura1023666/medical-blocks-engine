#!/usr/bin/env Rscript
# S1 单胎敏感性：补全全部 pe_outcomes（稀有结局 Firth）
# 写出 Table_S1_singleton_Disease_logistic_all_outcomes.*（不覆盖旧 Preterm+GDM 表）
#
# Rscript run/61_preeclampsia/run_61_pe_s1_singleton_all_outcomes.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "61_preeclampsia" && basename(dirname(sp)) == "run") {
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
    }
  }
  normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}

.root_dir <- .root()
setwd(.root_dir)
source(file.path(.root_dir, "R/utils.R"))
source("/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R")
source(file.path(.root_dir, "run/61_preeclampsia/blocks_shell/01block_pe_plan_supplement.R"))

out_base <- config$project$output_dir
ck_shared <- pipeline_shared$checkpoint$dir
ck <- file.path(ck_shared, "multicollinearity_screen.rds")
if (!file.exists(ck)) ck <- file.path(ck_shared, "step08_multicollinearity_screen.rds")
obj <- readRDS(ck)
ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
data <- as.data.frame(ctx$data$imputed %||% ctx$data$cleaned)
m2 <- as.character(ctx$results$Model2Factors %||% character(0))
if (!length(m2)) stop("Model2Factors 为空", call. = FALSE)

# 回补新生儿 / Apgar / 剖宫产（若尚未在 imputed 中）
id <- as.character(config$data$id_column %||% "Admission_Num")[1L]
need <- c(
  "Cesarean01", "Apgar1_lt8", "Apgar5_lt8",
  "Newborn_lt1500", "Newborn_lt2000"
)
if (!all(need %in% names(data))) {
  env <- new.env(parent = emptyenv())
  load(config$data$rawdata_path, envir = env)
  raw <- as.data.frame(env[[config$data$rawdata_obj]])
  if (!"Cesarean01" %in% names(raw) && "Delivery_Mode" %in% names(raw)) {
    dm <- trimws(as.character(raw$Delivery_Mode))
    raw$Cesarean01 <- as.integer(grepl("剖|Cesarean|cesarean|CS", dm, ignore.case = TRUE))
  }
  nw <- suppressWarnings(as.numeric(sub("/.*$", "", trimws(as.character(raw$Newborn_Weight)))))
  nw[is.finite(nw) & nw <= 0] <- NA_real_
  raw$Newborn_lt1500 <- as.integer(is.finite(nw) & nw < 1500)
  raw$Newborn_lt2000 <- as.integer(is.finite(nw) & nw < 2000)
  raw$APGAR_1min <- suppressWarnings(as.numeric(as.character(raw$APGAR_1min)))
  raw$APGAR_5min <- suppressWarnings(as.numeric(as.character(raw$APGAR_5min)))
  raw$Apgar1_lt8 <- as.integer(is.finite(raw$APGAR_1min) & raw$APGAR_1min < 8)
  raw$Apgar5_lt8 <- as.integer(is.finite(raw$APGAR_5min) & raw$APGAR_5min < 8)
  keep <- intersect(c(id, need), names(raw))
  map <- raw[, keep, drop = FALSE]
  map[[id]] <- as.character(map[[id]])
  data[[id]] <- as.character(data[[id]])
  for (cn in setdiff(keep, id)) data[[cn]] <- NULL
  data <- merge(data, map, by = id, all.x = TRUE, sort = FALSE)
}

data_s1 <- data[as.character(data$Is_Twin) == "No", , drop = FALSE]
m2_s1 <- setdiff(m2, "Is_Twin")
cli::cli_alert_info("S1 单胎 n={nrow(data_s1)}; Model2={paste(m2_s1, collapse=', ')}")

pe_oc <- names(config$pe_outcomes %||% list())
if (!length(pe_oc)) {
  pe_oc <- c(
    "Preterm34", "GDM01", "Cesarean01",
    "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000"
  )
}
pe_oc <- pe_oc[pe_oc %in% names(data_s1)]
cli::cli_alert_info("结局: {paste(pe_oc, collapse=', ')}")

s1_all <- do.call(
  rbind,
  lapply(pe_oc, function(oc) {
    cli::cli_alert_info("拟合 {oc} ({if (.pe_sup_use_firth(oc)) 'Firth' else 'GLM'})...")
    tryCatch(
      .pe_sup_run_disease_logistic(data_s1, m2_s1, oc, "SA_singleton_only"),
      error = function(e) {
        cli::cli_alert_danger("{oc}: {conditionMessage(e)}")
        NULL
      }
    )
  })
)

s1_dir <- file.path(out_base, "_shared", "sensitivity", "S1_singleton_logistic")
dir.create(s1_dir, recursive = TRUE, showWarnings = FALSE)
csv_fp <- file.path(s1_dir, "Table_S1_singleton_Disease_logistic_all_outcomes.csv")
xlsx_fp <- file.path(s1_dir, "Table_S1_singleton_Disease_logistic_all_outcomes.xlsx")
utils::write.csv(s1_all, csv_fp, row.names = FALSE, fileEncoding = "UTF-8")
if (requireNamespace("openxlsx", quietly = TRUE)) {
  openxlsx::write.xlsx(s1_all, xlsx_fp)
}
print(s1_all)
cli::cli_alert_success("已写入（未覆盖旧 Preterm+GDM 表）: {xlsx_fp}")
