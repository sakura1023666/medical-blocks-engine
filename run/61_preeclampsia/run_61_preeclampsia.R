#!/usr/bin/env Rscript
# run/61_preeclampsia/run_61_preeclampsia.R
# 全流程：共享层（Blocks 为主 + encode 壳）→ logistic_binary_glm × 两结局 + 亚组
#
#   Rscript run/61_preeclampsia/run_61_preeclampsia.R
#   Rscript run/61_preeclampsia/run_61_preeclampsia.R --config .../config_61_preeclampsia_batch.R
#   Rscript run/61_preeclampsia/run_61_preeclampsia.R --shared-only
#   Rscript run/61_preeclampsia/run_61_preeclampsia.R --units-only

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

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
shared_only <- FALSE
units_only <- FALSE
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--shared-only") {
    shared_only <- TRUE; i <- i + 1L
  } else if (args[[i]] == "--units-only") {
    units_only <- TRUE; i <- i + 1L
  } else i <- i + 1L
}
if (is.null(config_path) || !nzchar(config_path)) {
  config_path <- "/mnt/g/02block_result/61_Preeclampsia/configs/config_61_preeclampsia_batch.R"
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)

if (!exists("pipeline_shared")) stop("config 未定义 pipeline_shared", call. = FALSE)
if (!exists("pipeline_unit")) stop("config 未定义 pipeline_unit", call. = FALSE)

options(warn = 1, cli.hyperlink = FALSE)
Sys.setenv(SMOKE_NO_FEISHU = "1")

out_base <- config$project$output_dir
ck_shared <- (pipeline_shared$checkpoint %||% list())$dir %||%
  file.path(dirname(out_base), "checkpoints", basename(out_base), "_shared")

shared_ctx <- NULL
if (!units_only) {
  cfg_shared <- config
  cfg_shared$project$output_dir <- file.path(out_base, "_shared")
  pl <- pipeline_shared
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- ck_shared
  cli::cli_h1("共享层（Blocks）: {paste(pl$blocks, collapse = ' → ')}")
  shared_ctx <- run_pipeline(root, config = cfg_shared, pipeline = pl)
  m2 <- as.character(shared_ctx$results$Model2Factors %||% character(0))
  if (length(m2)) shared_ctx$results$vif_final_pass <- m2
}

if (shared_only) {
  cli::cli_alert_success("--shared-only 完成")
  quit(status = 0)
}

if (units_only) {
  .pe_load_shared_ck <- function(path) {
    obj <- readRDS(path)
    if (is.list(obj) && !is.null(obj$ctx) && is.list(obj$ctx)) return(obj$ctx)
    obj
  }
  prefer <- c(
    "multicollinearity_screen.rds",
    "step08_multicollinearity_screen.rds",
    "sensitivity_scenarios.rds",
    "step09_sensitivity_scenarios.rds"
  )
  ck_pick <- NULL
  for (bn in prefer) {
    p <- file.path(ck_shared, bn)
    if (file.exists(p)) { ck_pick <- p; break }
  }
  if (is.null(ck_pick)) {
    ck_files <- list.files(ck_shared, pattern = "\\.rds$", full.names = TRUE)
    if (!length(ck_files)) stop("无共享 checkpoint", call. = FALSE)
    ck_files <- ck_files[order(file.info(ck_files)$mtime, decreasing = TRUE)]
    ck_pick <- ck_files[[1L]]
  }
  shared_ctx <- .pe_load_shared_ck(ck_pick)
  cli::cli_alert_info("units-only 载入共享 checkpoint: {basename(ck_pick)}")
  m2 <- as.character(shared_ctx$results$Model2Factors %||% character(0))
  if (length(m2)) shared_ctx$results$vif_final_pass <- m2
}

if (is.null(shared_ctx)) stop("共享层 ctx 为空", call. = FALSE)

m1 <- as.character(shared_ctx$results$Model1Factors %||% "Age")
m2 <- as.character(shared_ctx$results$Model2Factors %||% character(0))
if (!length(m2)) stop("Model2Factors 为空", call. = FALSE)

outcomes <- config$pe_outcomes %||% list(
  Preterm34 = list(outcome_column = "Preterm34", analysis_group = "Preterm34",
                   reference_group = "Term34", disease_label = "Preterm34"),
  GDM01 = list(outcome_column = "GDM01", analysis_group = "1",
               reference_group = "0", disease_label = "GDM")
)

for (ou in names(outcomes)) {
  spec <- outcomes[[ou]]
  oc <- as.character(spec$outcome_column %||% ou)[1L]
  cli::cli_h1("Unit: Disease → {oc}  [logistic_binary_glm + subgroup_incidence]")

  cfg_u <- config
  cfg_u$data$outcome_column <- oc
  cfg_u$incidence$outcome_var <- oc
  cfg_u$project$analysis_group <- as.character(spec$analysis_group %||% oc)[1L]
  cfg_u$project$reference_group <- as.character(spec$reference_group %||% "")[1L]
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
  # 亚组：GDM + 孕前 BMI；GDM 结局下剔除 GDM；早产结局下剔除早产分层
  sg_excl <- as.character((cfg_u$subgroup %||% list())$exclude_vars %||% character(0))
  sg_req <- as.character((cfg_u$subgroup %||% list())$required_subgroup_vars %||% character(0))
  outcome_like <- c(
    "GDM01", "Preterm34", "Preterm_delivery",
    "Cesarean01", "Apgar1_lt8", "Apgar5_lt8", "Newborn_lt1500", "Newborn_lt2000",
    "PE01", "Delivery_Mode", "Newborn_Weight_g", "APGAR_1min", "APGAR_5min"
  )
  sg_excl <- unique(c(sg_excl, setdiff(outcome_like, "Preterm_delivery"), oc, "GDM01"))
  sg_excl <- setdiff(sg_excl, "GDM")
  if (oc %in% c("Preterm34", "Preterm_delivery")) {
    sg_excl <- unique(c(sg_excl, "Preterm_delivery", "Preterm34"))
    sg_req <- setdiff(sg_req, c("Preterm_delivery", "Preterm34"))
  } else if (!"Preterm_delivery" %in% sg_req) {
    sg_req <- c(sg_req, "Preterm_delivery")
  }
  if (oc %in% c("GDM01", "GDM")) {
    sg_excl <- unique(c(sg_excl, "GDM", "GDM01"))
    sg_req <- setdiff(sg_req, c("GDM", "GDM01"))
  } else if (!"GDM" %in% sg_req) {
    sg_req <- c(sg_req, "GDM")
  }
  sg_req <- setdiff(sg_req, c("Pre_BMI", "Pre_BMI_subg"))
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
  # 孕前 BMI 中国四分类；稀有结局若层内过稀可在 Firth 脚本退三分类
  if (file.exists(file.path(root, "run/61_preeclampsia/pe_pre_bmi_group.R"))) {
    source(file.path(root, "run/61_preeclampsia/pe_pre_bmi_group.R"), local = FALSE)
    if (exists(".pe_add_pre_bmi_group", mode = "function")) {
      for (dn in c("imputed", "cleaned")) {
        if (!is.null(ctx_u$data[[dn]]) && is.data.frame(ctx_u$data[[dn]])) {
          ctx_u$data[[dn]] <- .pe_add_pre_bmi_group(ctx_u$data[[dn]], "china4")
        }
      }
    }
  }

  run_pipeline(
    root,
    config = cfg_u,
    pipeline = pl_u,
    run_opts = list(
      initial_ctx = ctx_u,
      only = c("logistic_binary_glm", "subgroup_incidence")
    )
  )
  cli::cli_alert_success("完成: {oc}")
}

cli::cli_alert_success("全流程完成 → {out_base}")
